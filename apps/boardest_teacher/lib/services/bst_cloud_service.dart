import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'bst_cloud_logger.dart';

class BstCloudService {
  static final BstCloudService instance = BstCloudService._();
  BstCloudService._();

  final Map<String, dynamic> _syncStateStore = {};
  final Map<String, ValueNotifier<dynamic>> _syncStateNotifiers = {};

  void saveSyncState(String key, dynamic value) {
    _syncStateStore[key] = value;
    if (!_syncStateNotifiers.containsKey(key)) {
      _syncStateNotifiers[key] = ValueNotifier(value);
    } else {
      _syncStateNotifiers[key]!.value = value;
    }
  }

  void listenSyncState(String key, void Function(dynamic value) callback) {
    if (!_syncStateNotifiers.containsKey(key)) {
      _syncStateNotifiers[key] = ValueNotifier(_syncStateStore[key]);
    }
    _syncStateNotifiers[key]!.addListener(() {
      callback(_syncStateNotifiers[key]!.value);
    });
  }

  /// Firestore 및 기본 설정을 참조하여 접속 가능한 전자칠판(교실) 목록을 반환합니다.
  Future<List<String>> getOnlineClassrooms() async {
    final classrooms = <String>[];
    try {
      final url = '${AppConfig.firestoreBase}/classrooms?key=${AppConfig.firebaseApiKey}';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final docs = data['documents'] as List<dynamic>? ?? [];
        for (final doc in docs) {
          final fields = doc['fields'] as Map<String, dynamic>?;
          final name = (fields?['name'] as Map?)?['stringValue'] as String? ??
              (doc['name'] as String? ?? '').split('/').last;
          if (name.isNotEmpty) {
            classrooms.add(name);
          }
        }
      }
    } catch (e) {
      debugPrint('[BstCloudService] getOnlineClassrooms error: $e');
    }

    if (classrooms.isEmpty) {
      for (var g = 1; g <= 3; g++) {
        for (var c = 1; c <= 8; c++) {
          classrooms.add('$g학년 $c반');
        }
      }
      classrooms.addAll(['과학실', '음악실', '미술실', '컴퓨터실', '체육관', '도서관']);
    }
    return classrooms;
  }

  /// 특정 교실 전자칠판으로 DriveCast 접속 승인 토큰을 발송합니다.
  Future<bool> approveConnectionRequest({
    required String teacherName,
    required String classroomName,
    required String token,
    required String folderId,
    int durationHours = 1,
  }) async {
    final docId = Uri.encodeComponent(teacherName);
    final classId = Uri.encodeComponent(classroomName);
    final url = '${AppConfig.firestoreBase}/cloud_connections/$docId/requests/$classId?key=${AppConfig.firebaseApiKey}';

    final expiresAt = DateTime.now().add(Duration(hours: durationHours)).toUtc().toIso8601String();

    final body = {
      'fields': {
        'status': {'stringValue': 'approved'},
        'token': {'stringValue': token},
        'folderId': {'stringValue': folderId},
        'expiresAt': {'stringValue': expiresAt},
        'timestamp': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      }
    };

    try {
      final res = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        await BstCloudLogger.instance.logEvent(
          action: 'CAST_APPROVED',
          teacherName: teacherName,
          classroomName: classroomName,
          details: '[$teacherName] 선생님이 [$classroomName] 전자칠판으로 DriveCast($durationHours시간)를 승인했습니다.',
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BstCloudService] approveConnectionRequest error: $e');
      return false;
    }
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class BstAuditLog {
  final String id;
  final String action;
  final String teacherName;
  final String classroomName;
  final String details;
  final DateTime timestamp;

  BstAuditLog({
    required this.id,
    required this.action,
    required this.teacherName,
    required this.classroomName,
    required this.details,
    required this.timestamp,
  });

  factory BstAuditLog.fromFirestore(Map<String, dynamic> doc) {
    final name = doc['name'] as String? ?? '';
    final id = name.split('/').last;
    final fields = doc['fields'] as Map<String, dynamic>? ?? {};

    final action = (fields['action'] as Map?)?['stringValue'] as String? ?? '';
    final teacherName = (fields['teacherName'] as Map?)?['stringValue'] as String? ?? '';
    final classroomName = (fields['classroomName'] as Map?)?['stringValue'] as String? ?? '';
    final details = (fields['details'] as Map?)?['stringValue'] as String? ?? '';
    final tsStr = (fields['timestamp'] as Map?)?['timestampValue'] as String? ?? '';
    final timestamp = DateTime.tryParse(tsStr) ?? DateTime.now();

    return BstAuditLog(
      id: id,
      action: action,
      teacherName: teacherName,
      classroomName: classroomName,
      details: details,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'fields': {
        'action': {'stringValue': action},
        'teacherName': {'stringValue': teacherName},
        'classroomName': {'stringValue': classroomName},
        'details': {'stringValue': details},
        'timestamp': {'timestampValue': timestamp.toUtc().toIso8601String()},
      }
    };
  }
}

class BstCloudLogger {
  static final BstCloudLogger instance = BstCloudLogger._();
  BstCloudLogger._();

  static String get _apiKey => AppConfig.firebaseApiKey;
  static String get _firestoreBase => AppConfig.firestoreBase;

  /// Firestore audit_logs 컬렉션에 보안 이벤트 기기/서버 로깅
  Future<bool> logEvent({
    required String action,
    required String teacherName,
    required String classroomName,
    required String details,
  }) async {
    final url = '$_firestoreBase/audit_logs?key=$_apiKey';
    final log = BstAuditLog(
      id: '',
      action: action,
      teacherName: teacherName,
      classroomName: classroomName,
      details: details,
      timestamp: DateTime.now(),
    );

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(log.toFirestore()),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[BstCloudLogger] logEvent error: $e');
      return false;
    }
  }

  /// 최근 감사 로그 조회 (교사용 앱 및 웹사이트용)
  Future<List<BstAuditLog>> fetchAuditLogs({int limit = 50}) async {
    final url = '$_firestoreBase/audit_logs?key=$_apiKey&pageSize=$limit';
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return [];
      final data = json.decode(res.body) as Map<String, dynamic>;
      final docs = data['documents'] as List<dynamic>? ?? [];
      return docs
          .map((doc) => BstAuditLog.fromFirestore(doc as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[BstCloudLogger] fetchAuditLogs error: $e');
      return [];
    }
  }
}

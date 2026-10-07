import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/app_settings.dart';
import '../models/school.dart';
import '../services/storage_service.dart';

/// 데모 모드 전용 교실 번호(Demo-class1 ~ 10) 비겹침 할당 및 하트비트 서비스
class DemoClassAllocatorService {
  static final DemoClassAllocatorService instance = DemoClassAllocatorService._();
  DemoClassAllocatorService._();

  static const String _rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com';
  
  String? _assignedClassId; // 예: Demo-class3
  Timer? _heartbeatTimer;
  final String _deviceId = 'device_${Random().nextInt(9999999)}';

  String? get assignedClassId => _assignedClassId;

  /// 온라인 기기 10대 이하시 비겹침 배정 알고리즘 (Demo-class 1~10)
  Future<AppSettings> allocateDemoSettings(AppSettings currentSettings) async {
    int chosenNumber = 1;

    try {
      final res = await http
          .get(Uri.parse('$_rtdbBase/demo_active_devices.json'))
          .timeout(const Duration(seconds: 4));

      final activeNumbers = <int>{};
      final now = DateTime.now().millisecondsSinceEpoch;

      if (res.statusCode == 200 && res.body != 'null') {
        final data = jsonDecode(res.body);
        if (data is Map) {
          data.forEach((key, val) {
            // key 예: Demo-class3
            if (key is String && key.startsWith('Demo-class')) {
              final numStr = key.replaceFirst('Demo-class', '');
              final num = int.tryParse(numStr);
              if (num != null && num >= 1 && num <= 10) {
                if (val is Map) {
                  final ts = int.tryParse(val['timestamp']?.toString() ?? '0') ?? 0;
                  // 45초 이내 하트비트가 있으면 활성 기기로 간주
                  if (now - ts < 45000) {
                    activeNumbers.add(num);
                  }
                }
              }
            }
          });
        }
      }

      final allCandidates = List.generate(10, (i) => i + 1); // 1..10
      final available = allCandidates.where((n) => !activeNumbers.contains(n)).toList();

      if (available.isNotEmpty) {
        // 10대 이하: 비어있는 번호 중 랜덤으로 하나 선택 (겹침 없음)
        available.shuffle(Random());
        chosenNumber = available.first;
        debugPrint('[DemoClassAllocator] Allocated non-overlapping class: Demo-class$chosenNumber (Active: $activeNumbers)');
      } else {
        // 10대 초과: 1~10 중 랜덤 선택
        chosenNumber = Random().nextInt(10) + 1;
        debugPrint('[DemoClassAllocator] 10+ devices online, allocated random class: Demo-class$chosenNumber');
      }
    } catch (e) {
      debugPrint('[DemoClassAllocator] Lookup failed, fallback to random: $e');
      chosenNumber = Random().nextInt(10) + 1;
    }

    _assignedClassId = 'Demo-class$chosenNumber';
    _startHeartbeat(_assignedClassId!);

    final demoSchool = School(
      id: 11111,
      code: 11111,
      name: 'Boardest 데모 중학교',
      region: '서울',
    );

    final newSettings = currentSettings.copyWith(
      selectedSchool: demoSchool,
      schoolId: 'Demo',
      selectedGrade: 1,
      selectedClass: chosenNumber,
      specialClassroomMode: true,
      classNickname: _assignedClassId,
      isSetupComplete: true,
    );

    await StorageService().saveSettings(newSettings);
    return newSettings;
  }

  void _startHeartbeat(String classId) {
    _heartbeatTimer?.cancel();
    _sendHeartbeat(classId);

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _sendHeartbeat(classId);
    });
  }

  Future<void> _sendHeartbeat(String classId) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await http.put(
        Uri.parse('$_rtdbBase/demo_active_devices/$classId.json'),
        body: jsonEncode({
          'timestamp': now,
          'deviceId': _deviceId,
          'platform': kIsWeb ? 'web' : 'desktop',
        }),
      );
    } catch (_) {}
  }

  void dispose() {
    _heartbeatTimer?.cancel();
  }
}

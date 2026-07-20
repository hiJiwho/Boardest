import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/app_settings.dart';
import '../config/app_config.dart';
import 'storage_service.dart';

class MealCallService {
  static final MealCallService instance = MealCallService._internal();
  MealCallService._internal();

  Timer? _pollTimer;
  Timer? _activeTimer;
  bool _lastCalledState = false;
  AppSettings? _currentSettings;

  String? _lastMessageSentAt;
  String? _lastCallSentAt;

  // Callbacks to notify UI when events occur
  VoidCallback? onMealCallReceived;
  void Function(String message, String from)? onMessageReceived;
  void Function(String message, String from)? onStudentCallReceived;

  // Track if popup is currently showing to prevent redundant triggers
  bool isPopupShowing = false;

  /// 앱 시작 직후 급식실 대시보드에 교실 온라인 신호 전송
  Future<void> ensurePresence(AppSettings settings) async {
    if (settings.connectionName.isEmpty &&
        settings.selectedSchool == null &&
        !settings.specialClassroomMode) {
      return;
    }
    _currentSettings = settings;
    await _registerClassroom();
  }

  /// 시간대별 동적 폴링 주기 계산
  Duration _getDynamicPollInterval() {
    final now = DateTime.now();
    
    // 주말: 5분 주기
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return const Duration(minutes: 5);
    }
    
    // 급식 시간대 (11:00 ~ 13:30): 3초 주기
    if (now.hour == 11 || now.hour == 12 || (now.hour == 13 && now.minute <= 30)) {
      return const Duration(seconds: 3);
    }
    
    // 정규 수업 시간대 (08:30 ~ 11:00 / 13:30 ~ 17:00): 20초 주기
    if ((now.hour == 8 && now.minute >= 30) || 
        (now.hour >= 9 && now.hour < 11) ||
        (now.hour == 13 && now.minute > 30) ||
        (now.hour >= 14 && now.hour < 17)) {
      return const Duration(seconds: 20);
    }
    
    // 그 외 시간대 (방과 후, 야간 등): 5분 주기
    return const Duration(minutes: 5);
  }

  void startListening(
    AppSettings settings, {
    required VoidCallback onCall,
    required void Function(String message, String from) onMessage,
    required void Function(String message, String from) onStudentCall,
  }) {
    if (settings.connectionName.isEmpty &&
        settings.selectedSchool == null &&
        !settings.specialClassroomMode) {
      return;
    }
    
    stopListening();
    
    _currentSettings = settings;
    onMealCallReceived = onCall;
    onMessageReceived = onMessage;
    onStudentCallReceived = onStudentCall;
    _lastCalledState = false;
    _lastMessageSentAt = null;
    _lastCallSentAt = null;

    // Register/update active status initially
    _registerClassroom();

    // Start dynamic polling scheduler
    _scheduleNextPoll();

    // Refresh active status every 60 seconds (Presence) to save write quota
    _activeTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      _registerClassroom();
    });
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    if (_currentSettings == null) return;
    
    final interval = _getDynamicPollInterval();
    _pollTimer = Timer(interval, () async {
      await _checkCallStatus();
      _scheduleNextPoll();
    });
  }

  void stopListening() {
    _pollTimer?.cancel();
    _activeTimer?.cancel();
    final settings = _currentSettings;
    if (settings != null) {
      unawaited(deleteEatCallDocument(settings: settings));
    }
    _currentSettings = null;
  }

  String get _documentId {
    if (_currentSettings == null) return '';
    final connName = _currentSettings!.connectionName.isNotEmpty ? _currentSettings!.connectionName : 'My';
    
    var cafeteria = _currentSettings!.cafeteriaNum;
    if (cafeteria.startsWith("급식실")) {
      cafeteria = cafeteria.replaceAll("급식실", "");
    }
    if (!['1', '2', '3', '4', '5', '6', '7', '8', '9'].contains(cafeteria)) {
      cafeteria = "1";
    }

    final grade = _currentSettings!.selectedGrade;
    final classNum = _currentSettings!.selectedClass;

    return '${connName}_${cafeteria}_${grade}_$classNum';
  }

  static String get _apiKey => AppConfig.firebaseApiKey;

  String get _endpointUrl {
    final docId = _documentId;
    return 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls/$docId.json';
  }

  Future<void> _registerClassroom() async {
    if (_currentSettings == null) return;

    try {
      final url = '$_endpointUrl?auth=$_apiKey';
      debugPrint('[MealCallService] Registering classroom to RTDB with doc ID: $_documentId, URL: $url');
      var cafeteria = _currentSettings!.cafeteriaNum;
      if (cafeteria.startsWith("급식실")) {
        cafeteria = cafeteria.replaceAll("급식실", "");
      }
      if (!['1', '2', '3', '4', '5', '6', '7', '8', '9'].contains(cafeteria)) {
        cafeteria = "1";
      }

      final connName = _currentSettings!.connectionName.isNotEmpty ? _currentSettings!.connectionName : 'My';
      final schoolName = _currentSettings!.selectedSchool?.name ?? connName;
      final schoolCode = connName;
      final place = _currentSettings!.selectedSchool?.region ?? "연결";
      final classNickname = _currentSettings!.classNickname.isNotEmpty 
          ? _currentSettings!.classNickname 
          : '${_currentSettings!.selectedGrade}학년 ${_currentSettings!.selectedClass}반';

      final payload = {
        "place": place,
        "schoolName": schoolName,
        "schoolCode": schoolCode,
        "cafeteriaNum": cafeteria,
        "grade": _currentSettings!.selectedGrade,
        "classNum": _currentSettings!.selectedClass,
        "classNickname": classNickname,
        "called": _lastCalledState,
        "lastActive": DateTime.now().toUtc().toIso8601String(),
        "classOrder": _currentSettings!.mealCallClassOrder
      };

      await http.patch(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );
    } catch (e) {
      debugPrint('Error registering classroom for meal call: $e');
    }
  }

  Future<void> _checkCallStatus() async {
    if (_currentSettings == null || (_currentSettings!.connectionName.isEmpty && _currentSettings!.selectedSchool == null && !_currentSettings!.specialClassroomMode)) return;

    try {
      final url = '$_endpointUrl?auth=$_apiKey';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200 && response.body != 'null') {
        final fields = json.decode(response.body) as Map<String, dynamic>?;
        if (fields != null) {
          // 1. Meal Call Check
          if (fields['called'] != null) {
            final isCalled = fields['called'] as bool? ?? false;
            if (isCalled && !isPopupShowing) {
              _lastCalledState = true;
              onMealCallReceived?.call();
            } else if (!isCalled) {
              _lastCalledState = false;
            }
          }

          // 2. Message Check
          if (fields['message'] != null && fields['messageSentAt'] != null) {
            final message = fields['message'] as String? ?? '';
            final messageFrom = fields['messageFrom'] as String? ?? '';
            final messageSentAt = fields['messageSentAt'] as String? ?? '';
            
            if (message.isNotEmpty && messageSentAt.isNotEmpty) {
              if (_lastMessageSentAt != messageSentAt) {
                _lastMessageSentAt = messageSentAt;
                onMessageReceived?.call(message, messageFrom);
              }
            }
          }

          // 3. Student Call Check
          if (fields['callMessage'] != null && fields['callSentAt'] != null) {
            final callMessage = fields['callMessage'] as String? ?? '';
            final callerName = fields['callerName'] as String? ?? '';
            final callSentAt = fields['callSentAt'] as String? ?? '';

            if (callMessage.isNotEmpty && callSentAt.isNotEmpty) {
              if (_lastCallSentAt != callSentAt) {
                _lastCallSentAt = callSentAt;
                onStudentCallReceived?.call(callMessage, callerName);
              }
            }
          }
        }
      } else if (response.statusCode == 404 || response.body == 'null') {
        // Not created yet, register it
        _registerClassroom();
      }
    } catch (e) {
      debugPrint('Error checking call status: $e');
    }
  }

  Future<void> clearMealCall() async {
    if (_currentSettings == null || (_currentSettings!.connectionName.isEmpty && _currentSettings!.selectedSchool == null && !_currentSettings!.specialClassroomMode)) return;

    _lastCalledState = false;
    isPopupShowing = false;

    try {
      final url = '$_endpointUrl?auth=$_apiKey';
      final payload = {
        "called": false
      };

      await http.patch(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );
    } catch (e) {
      debugPrint('Error clearing meal call: $e');
    }
  }

  Future<void> clearMessage() async {
    if (_currentSettings == null || (_currentSettings!.connectionName.isEmpty && _currentSettings!.selectedSchool == null && !_currentSettings!.specialClassroomMode)) return;

    isPopupShowing = false;

    try {
      final url = '$_endpointUrl?auth=$_apiKey';
      final payload = {
        "message": "",
        "messageFrom": "",
        "messageSentAt": ""
      };

      await http.patch(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );
    } catch (e) {
      debugPrint('Error clearing message: $e');
    }
  }

  Future<void> clearStudentCall() async {
    if (_currentSettings == null || (_currentSettings!.connectionName.isEmpty && _currentSettings!.selectedSchool == null && !_currentSettings!.specialClassroomMode)) return;

    isPopupShowing = false;

    try {
      final url = '$_endpointUrl?auth=$_apiKey';
      final payload = {
        "callMessage": "",
        "callerName": "",
        "callSentAt": ""
      };

      await http.patch(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );
    } catch (e) {
      debugPrint('Error clearing student call: $e');
    }
  }

  Future<void> deleteEatCallDocument({AppSettings? settings}) async {
    final activeSettings = settings ?? _currentSettings ?? await StorageService().getSettings();
    if (activeSettings.connectionName.isEmpty && activeSettings.selectedSchool == null && !activeSettings.specialClassroomMode) return;

    final connName = activeSettings.connectionName.isNotEmpty ? activeSettings.connectionName : 'My';
    
    var cafeteria = activeSettings.cafeteriaNum;
    if (cafeteria.startsWith("급식실")) {
      cafeteria = cafeteria.replaceAll("급식실", "");
    }
    if (!['1', '2', '3', '4', '5', '6', '7', '8', '9'].contains(cafeteria)) {
      cafeteria = "1";
    }

    final grade = activeSettings.selectedGrade;
    final classNum = activeSettings.selectedClass;
    final docId = '${connName}_${cafeteria}_${grade}_$classNum';

    try {
      final url = 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls/$docId.json?auth=$_apiKey';
      final res = await http.delete(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 || res.statusCode == 204) {
        debugPrint('[MealCallService] eat_calls document $docId deleted successfully.');
      } else {
        debugPrint('[MealCallService] Error deleting eat_calls document $docId (status code: ${res.statusCode}).');
      }
    } catch (e) {
      debugPrint('[MealCallService] Error deleting eat_calls document $docId: $e');
    }
  }

  /// 로컬 서버로부터 직접 호출받았을 때 칠판에 즉시 팝업을 띄우기 위한 원격 호출 트리거
  void triggerMealCallDirectly() {
    if (!isPopupShowing) {
      _lastCalledState = true;
      onMealCallReceived?.call();
    }
  }
}

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

  void startListening(
    AppSettings settings, {
    required VoidCallback onCall,
    required void Function(String message, String from) onMessage,
    required void Function(String message, String from) onStudentCall,
  }) {
    if (settings.connectionName.isEmpty && settings.selectedSchool == null) return;
    
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

    // Poll every 3 seconds for call status
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkCallStatus();
    });

    // Refresh active status every 15 seconds so the web board reflects presence quickly.
    _activeTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _registerClassroom();
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
    return 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/$docId';
  }

  Future<void> _registerClassroom() async {
    if (_currentSettings == null) return;

    try {
      final url = '$_endpointUrl?key=$_apiKey';
      debugPrint('[MealCallService] Registering classroom with doc ID: $_documentId, URL: $url');
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
        "fields": {
          "place": {"stringValue": place},
          "schoolName": {"stringValue": schoolName},
          "schoolCode": {"stringValue": schoolCode},
          "cafeteriaNum": {"stringValue": cafeteria},
          "grade": {"integerValue": _currentSettings!.selectedGrade.toString()},
          "classNum": {"integerValue": _currentSettings!.selectedClass.toString()},
          "classNickname": {"stringValue": classNickname},
          "called": {"booleanValue": _lastCalledState},
          "lastActive": {"stringValue": DateTime.now().toUtc().toIso8601String()},
          "classOrder": {"stringValue": _currentSettings!.mealCallClassOrder}
        }
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
      final url = '$_endpointUrl?key=$_apiKey';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final fields = body['fields'] as Map<String, dynamic>?;
        if (fields != null) {
          // 1. Meal Call Check
          if (fields['called'] != null) {
            final isCalled = fields['called']['booleanValue'] as bool? ?? false;
            if (isCalled && !isPopupShowing) {
              _lastCalledState = true;
              onMealCallReceived?.call();
            } else if (!isCalled) {
              _lastCalledState = false;
            }
          }

          // 2. Message Check
          if (fields['message'] != null && fields['messageSentAt'] != null) {
            final message = fields['message']['stringValue'] as String? ?? '';
            final messageFrom = fields['messageFrom'] != null ? (fields['messageFrom']['stringValue'] as String? ?? '') : '';
            final messageSentAt = fields['messageSentAt']['stringValue'] as String? ?? '';
            
            if (message.isNotEmpty && messageSentAt.isNotEmpty) {
              if (_lastMessageSentAt != messageSentAt) {
                _lastMessageSentAt = messageSentAt;
                onMessageReceived?.call(message, messageFrom);
              }
            }
          }

          // 3. Student Call Check
          if (fields['callMessage'] != null && fields['callSentAt'] != null) {
            final callMessage = fields['callMessage']['stringValue'] as String? ?? '';
            final callerName = fields['callerName'] != null ? (fields['callerName']['stringValue'] as String? ?? '') : '';
            final callSentAt = fields['callSentAt']['stringValue'] as String? ?? '';

            if (callMessage.isNotEmpty && callSentAt.isNotEmpty) {
              if (_lastCallSentAt != callSentAt) {
                _lastCallSentAt = callSentAt;
                onStudentCallReceived?.call(callMessage, callerName);
              }
            }
          }
        }
      } else if (response.statusCode == 404) {
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
      final url = '$_endpointUrl?key=$_apiKey&updateMask.fieldPaths=called';
      final payload = {
        "fields": {
          "called": {"booleanValue": false}
        }
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
      final url = '$_endpointUrl?key=$_apiKey&updateMask.fieldPaths=message&updateMask.fieldPaths=messageFrom&updateMask.fieldPaths=messageSentAt';
      final payload = {
        "fields": {
          "message": {"stringValue": ""},
          "messageFrom": {"stringValue": ""},
          "messageSentAt": {"stringValue": ""}
        }
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
      final url = '$_endpointUrl?key=$_apiKey&updateMask.fieldPaths=callMessage&updateMask.fieldPaths=callerName&updateMask.fieldPaths=callSentAt';
      final payload = {
        "fields": {
          "callMessage": {"stringValue": ""},
          "callerName": {"stringValue": ""},
          "callSentAt": {"stringValue": ""}
        }
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
      final url = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/$docId?key=$_apiKey';
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

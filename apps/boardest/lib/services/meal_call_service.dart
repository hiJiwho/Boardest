import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/app_settings.dart';
import '../config/app_config.dart';
import 'storage_service.dart';

class MealCallService {
  static final MealCallService instance = MealCallService._internal();
  MealCallService._internal();

  /// 급식 호출 수동 즉시 트리거 (디버그/수동 테스트용)
  void triggerMealCallDirectly({String? targetClassroom, String? message}) {
    _lastCalledState = true;
    _manualActive = true;
    _manualActiveExpiresAt = DateTime.now().add(const Duration(minutes: 30));
    onMealCallReceived?.call();
  }

  Timer? _pollTimer;
  Timer? _activeTimer;
  bool _lastCalledState = false;
  AppSettings? _currentSettings;

  String? _lastMessageSentAt;
  String? _lastCallSentAt;

  // Manual active override (최대 5시간 또는 수동 해제)
  bool _manualActive = false;
  DateTime? _manualActiveExpiresAt;

  bool get isManualActive {
    if (!_manualActive) return false;
    if (_manualActiveExpiresAt != null && DateTime.now().isAfter(_manualActiveExpiresAt!)) {
      _manualActive = false;
      _manualActiveExpiresAt = null;
      return false;
    }
    return true;
  }

  Duration get manualRemainingTime {
    if (!isManualActive || _manualActiveExpiresAt == null) return Duration.zero;
    final rem = _manualActiveExpiresAt!.difference(DateTime.now());
    return rem.isNegative ? Duration.zero : rem;
  }

  bool get isCalled => _lastCalledState;

  void setManualActive(bool active) {
    _manualActive = active;
    if (active) {
      _manualActiveExpiresAt = DateTime.now().add(const Duration(hours: 5));
      _registerClassroom();
    } else {
      _manualActiveExpiresAt = null;
    }
  }

  void toggleManualActive() {
    setManualActive(!isManualActive);
  }

  // Callbacks to notify UI when events occur
  VoidCallback? onMealCallReceived;
  void Function(String message, String from)? onMessageReceived;
  void Function(String message, String from)? onStudentCallReceived;
  void Function(String teacherName, String teacherEmail)? onAutoOtpRegistered;

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

  // ─── RTDB Server-Sent Events (SSE) Realtime Stream ───
  http.Client? _sseClient;
  StreamSubscription? _sseSubscription;
  Timer? _reconnectTimer;
  static const String _rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com';

  void _startRtdbStream() {
    _stopRtdbStream();
    if (_currentSettings == null) return;
    final docId = _documentId;
    if (docId.isEmpty) return;

    _sseClient = http.Client();
    _connectRtdbSse(docId);
  }

  Future<void> _connectRtdbSse(String docId) async {
    if (_currentSettings == null) return;
    try {
      final url = Uri.parse('$_rtdbBase/eat_calls/$docId.json');
      final request = http.Request('GET', url);
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await _sseClient?.send(request);
      if (response == null || response.statusCode != 200) {
        _retryRtdbSse(docId);
        return;
      }

      String eventType = 'message';
      _sseSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('event: ')) {
          eventType = line.substring(7).trim();
        } else if (line.startsWith('data: ')) {
          final dataStr = line.substring(6).trim();
          if (dataStr.isNotEmpty && dataStr != 'null') {
            try {
              final jsonObj = json.decode(dataStr);
              _handleRtdbEvent(eventType, jsonObj);
            } catch (_) {}
          }
        }
      }, onDone: () {
        debugPrint('[MealCallService] RTDB SSE stream closed, reconnecting...');
        _retryRtdbSse(docId);
      }, onError: (e) {
        debugPrint('[MealCallService] RTDB SSE stream error: $e, reconnecting...');
        _retryRtdbSse(docId);
      });
      debugPrint('[MealCallService] ⚡ Connected to RTDB SSE stream for $docId');
    } catch (e) {
      debugPrint('[MealCallService] Error connecting RTDB SSE: $e');
      _retryRtdbSse(docId);
    }
  }

  void _retryRtdbSse(String docId) {
    _reconnectTimer?.cancel();
    if (_currentSettings == null) return;
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (_currentSettings != null) {
        _connectRtdbSse(docId);
      }
    });
  }

  void _stopRtdbStream() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sseSubscription?.cancel();
    _sseSubscription = null;
    _sseClient?.close();
    _sseClient = null;
  }

  void _handleRtdbEvent(String eventType, dynamic jsonObj) {
    if (jsonObj is! Map) return;
    final path = jsonObj['path']?.toString() ?? '/';
    final data = jsonObj['data'];

    if (path == '/' && data is Map) {
      final mapData = Map<String, dynamic>.from(data);
      // 1. Meal Call Check
      final isSpecialRoom = _currentSettings?.specialClassroomMode ?? false;
      if (!isSpecialRoom && mapData.containsKey('called')) {
        final isCalled = mapData['called'] == true || mapData['called']?.toString().toLowerCase() == 'true';
        if (isCalled && !isPopupShowing) {
          _lastCalledState = true;
          onMealCallReceived?.call();
        } else if (!isCalled) {
          _lastCalledState = false;
        }
      }

      // 2. Message Check
      if (mapData['message'] != null && mapData['messageSentAt'] != null) {
        final message = mapData['message']?.toString() ?? '';
        final messageFrom = mapData['messageFrom']?.toString() ?? '';
        final messageSentAt = mapData['messageSentAt']?.toString() ?? '';
        if (message.isNotEmpty && messageSentAt.isNotEmpty && _lastMessageSentAt != messageSentAt) {
          _lastMessageSentAt = messageSentAt;
          onMessageReceived?.call(message, messageFrom);
        }
      }

      // 3. Student Call Check
      if (mapData['callMessage'] != null && mapData['callSentAt'] != null) {
        final callMessage = mapData['callMessage']?.toString() ?? '';
        final callerName = mapData['callerName']?.toString() ?? '';
        final callSentAt = mapData['callSentAt']?.toString() ?? '';
        if (callMessage.isNotEmpty && callSentAt.isNotEmpty && _lastCallSentAt != callSentAt) {
          _lastCallSentAt = callSentAt;
          onStudentCallReceived?.call(callMessage, callerName);
        }
      }
    } else if (path == '/called') {
      final isCalled = data == true || data?.toString().toLowerCase() == 'true';
      if (isCalled && !isPopupShowing) {
        _lastCalledState = true;
        onMealCallReceived?.call();
      } else if (!isCalled) {
        _lastCalledState = false;
      }
    } else if (path == '/message') {
      final msg = data?.toString() ?? '';
      if (msg.isNotEmpty) {
        onMessageReceived?.call(msg, '선생님');
      }
    } else if (data is Map) {
      final mapData = Map<String, dynamic>.from(data);
      if (mapData.containsKey('called')) {
        final isCalled = mapData['called'] == true || mapData['called']?.toString().toLowerCase() == 'true';
        if (isCalled && !isPopupShowing) {
          _lastCalledState = true;
          onMealCallReceived?.call();
        } else if (!isCalled) {
          _lastCalledState = false;
        }
      }
      if (mapData.containsKey('message') && mapData.containsKey('messageSentAt')) {
        final msg = mapData['message']?.toString() ?? '';
        final from = mapData['messageFrom']?.toString() ?? '';
        final sentAt = mapData['messageSentAt']?.toString() ?? '';
        if (msg.isNotEmpty && sentAt.isNotEmpty && _lastMessageSentAt != sentAt) {
          _lastMessageSentAt = sentAt;
          onMessageReceived?.call(msg, from);
        }
      }
      if (mapData.containsKey('callMessage') && mapData.containsKey('callSentAt')) {
        final callMsg = mapData['callMessage']?.toString() ?? '';
        final caller = mapData['callerName']?.toString() ?? '';
        final sentAt = mapData['callSentAt']?.toString() ?? '';
        if (callMsg.isNotEmpty && sentAt.isNotEmpty && _lastCallSentAt != sentAt) {
          _lastCallSentAt = sentAt;
          onStudentCallReceived?.call(callMsg, caller);
        }
      }
    }
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

    // 1. RTDB 실시간 SSE 스트림 연결 (0.1초 즉시 수신, Firestore 읽기 0회)
    _startRtdbStream();

    // 2. 초기 1회 상태 등록 & 상태 체크
    _registerClassroom();
    _checkCallStatus();

    // 3. 2분 간격으로 하트비트 전송 및 SSE 연결 상태 감시 (0 Firestore Reads)
    _activeTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (_currentSettings == null) return;
      _registerClassroom();
      if (_sseSubscription == null || _sseClient == null) {
        _startRtdbStream();
      }
    });
  }

  void stopListening() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _activeTimer?.cancel();
    _activeTimer = null;
    _stopRtdbStream();
    final settings = _currentSettings;
    if (settings != null) {
      unawaited(deleteEatCallDocument(settings: settings));
    }
    _currentSettings = null;
  }

  String get _documentId {
    if (_currentSettings == null) return '';
    final code = _currentSettings!.selectedSchool?.code.toString() ?? '';
    final schoolId = _currentSettings!.schoolId.trim();
    String connName = schoolId.isNotEmpty ? schoolId : _currentSettings!.connectionName;
    if (connName.isEmpty || connName.toLowerCase() == 'my') {
      connName = code.isNotEmpty ? code : 'school';
    }
    connName = connName.toLowerCase();
    
    if (_currentSettings!.specialClassroomMode) {
      final roomName = _currentSettings!.classNickname.isNotEmpty
          ? _currentSettings!.classNickname
          : (_currentSettings!.isLearningLab ? '교수학습실' : (_currentSettings!.selectedSubject.isNotEmpty ? _currentSettings!.selectedSubject : 'special'));
      final sanitizedRoom = roomName.replaceAll(RegExp(r'[^\w가-힣]'), '_');
      return '${connName}_special_$sanitizedRoom';
    }

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

  Future<void> _registerClassroom() async {
    if (_currentSettings == null) return;

    try {
      final docId = _documentId;
      var cafeteria = _currentSettings!.cafeteriaNum;
      if (cafeteria.startsWith("급식실")) {
        cafeteria = cafeteria.replaceAll("급식실", "");
      }
      if (!['1', '2', '3', '4', '5', '6', '7', '8', '9'].contains(cafeteria)) {
        cafeteria = "1";
      }

      final schoolId = _currentSettings!.schoolId.trim();
      final code = _currentSettings!.selectedSchool?.code.toString() ?? '';
      String connName = schoolId.isNotEmpty ? schoolId : _currentSettings!.connectionName;
      if (connName.isEmpty || connName.toLowerCase() == 'my') {
        connName = code.isNotEmpty ? code : 'school';
      }
      connName = connName.toLowerCase();

      final schoolName = _currentSettings!.selectedSchool?.name ?? connName;
      final schoolCode = connName;
      final place = _currentSettings!.selectedSchool?.region ?? "연결";
      final classNickname = _currentSettings!.classNickname.isNotEmpty 
          ? _currentSettings!.classNickname 
          : '${_currentSettings!.selectedGrade}학년 ${_currentSettings!.selectedClass}반';

      // 1. Firebase Realtime Database (RTDB) 실시간 온라인 & 하트비트 등록 (0 Firestore Reads)
      try {
        final rtdbUrl = '$_rtdbBase/eat_calls/$docId.json';
        await http.patch(
          Uri.parse(rtdbUrl),
          headers: {"Content-Type": "application/json"},
          body: json.encode({
            'docId': docId,
            'schoolCode': schoolCode,
            'schoolName': schoolName,
            'place': place,
            'cafeteriaNum': cafeteria,
            'grade': _currentSettings!.selectedGrade,
            'classNum': _currentSettings!.selectedClass,
            'classNickname': classNickname,
            'isOnline': true,
            'lastActive': DateTime.now().millisecondsSinceEpoch,
            'classOrder': _currentSettings!.mealCallClassOrder,
          }),
        ).timeout(const Duration(seconds: 4));
      } catch (re) {
        debugPrint('[MealCallService] RTDB heartbeat error: $re');
      }

      // 2. Firestore 동기화 (기존 레거시 백업 유지)
      try {
        const updateMask = 'updateMask.fieldPaths=place&updateMask.fieldPaths=schoolName&updateMask.fieldPaths=schoolCode&updateMask.fieldPaths=cafeteriaNum&updateMask.fieldPaths=grade&updateMask.fieldPaths=classNum&updateMask.fieldPaths=classNickname&updateMask.fieldPaths=lastActive&updateMask.fieldPaths=classOrder';
        final firestoreUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/$docId?$updateMask&key=$_apiKey';
        final payload = {
          'fields': {
            'place': {'stringValue': place},
            'schoolName': {'stringValue': schoolName},
            'schoolCode': {'stringValue': schoolCode},
            'cafeteriaNum': {'stringValue': cafeteria},
            'grade': {'integerValue': '${_currentSettings!.selectedGrade}'},
            'classNum': {'integerValue': '${_currentSettings!.selectedClass}'},
            'classNickname': {'stringValue': classNickname},
            'lastActive': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
            'classOrder': {'stringValue': _currentSettings!.mealCallClassOrder}
          }
        };

        final response = await http.patch(
          Uri.parse(firestoreUrl),
          headers: {"Content-Type": "application/json"},
          body: json.encode(payload),
        );

        if (response.statusCode >= 400) {
          final createUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls?documentId=$docId&key=$_apiKey';
          final initialPayload = {
            'fields': {
              ...payload['fields'] as Map<String, dynamic>,
              'called': {'booleanValue': false},
            }
          };
          await http.post(
            Uri.parse(createUrl),
            headers: {"Content-Type": "application/json"},
            body: json.encode(initialPayload),
          );
        }
      } catch (_) {}

      // 3. Cloudflare Worker KV 동기화
      try {
        await http.post(
          Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/classrooms/heartbeat'),
          headers: {"Content-Type": "application/json"},
          body: json.encode({
            'docId': docId,
            'schoolCode': schoolCode,
            'schoolName': schoolName,
            'cafeteria': cafeteria,
            'grade': _currentSettings!.selectedGrade,
            'class': _currentSettings!.selectedClass,
            'nickname': classNickname,
          }),
        ).timeout(const Duration(seconds: 3));
      } catch (_) {}
    } catch (e) {
      debugPrint('Error registering classroom for meal call: $e');
    }
  }

  Future<void> _checkCallStatus() async {
    if (_currentSettings == null || (_currentSettings!.connectionName.isEmpty && _currentSettings!.selectedSchool == null && !_currentSettings!.specialClassroomMode)) return;

    try {
      final docId = _documentId;
      // 1. RTDB에서 먼저 확인 (무제한 무료, 0 Firestore Reads)
      final rtdbUrl = '$_rtdbBase/eat_calls/$docId.json';
      final response = await http.get(Uri.parse(rtdbUrl)).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200 && response.body != 'null') {
        final jsonMap = json.decode(response.body) as Map<String, dynamic>?;
        if (jsonMap != null) {
          _handleRtdbEvent('get', {'path': '/', 'data': jsonMap});
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking RTDB call status: $e');
    }
  }

  String get _endpointUrl {
    final docId = _documentId;
    return 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/$docId?key=$_apiKey';
  }

  Future<void> clearMealCall() async {
    if (_currentSettings == null || (_currentSettings!.connectionName.isEmpty && _currentSettings!.selectedSchool == null && !_currentSettings!.specialClassroomMode)) return;

    _lastCalledState = false;
    isPopupShowing = false;
    final docId = _documentId;

    // 1. RTDB called 즉시 해제 (0.1초 동기화)
    try {
      final rtdbUrl = '$_rtdbBase/eat_calls/$docId.json';
      await http.patch(
        Uri.parse(rtdbUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({'called': false}),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 2. Firestore 해제 (레거시 동기화)
    try {
      final firestoreUrl = _endpointUrl;
      final payload = {
        'fields': {
          'called': {'booleanValue': false}
        }
      };

      await http.patch(
        Uri.parse(firestoreUrl),
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
    final docId = _documentId;

    // 1. RTDB 쪽지 즉시 클리어
    try {
      final rtdbUrl = '$_rtdbBase/eat_calls/$docId.json';
      await http.patch(
        Uri.parse(rtdbUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          'message': '',
          'messageFrom': '',
          'messageSentAt': ''
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 2. Firestore 쪽지 클리어
    try {
      final firestoreUrl = _endpointUrl;
      final payload = {
        'fields': {
          'message': {'stringValue': ''},
          'messageFrom': {'stringValue': ''},
          'messageSentAt': {'stringValue': ''}
        }
      };

      await http.patch(
        Uri.parse(firestoreUrl),
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
    final docId = _documentId;

    // 1. RTDB 학생 호출 클리어
    try {
      final rtdbUrl = '$_rtdbBase/eat_calls/$docId.json';
      await http.patch(
        Uri.parse(rtdbUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          'callMessage': '',
          'callerName': '',
          'callSentAt': ''
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 2. Firestore 학생 호출 클리어
    try {
      final firestoreUrl = _endpointUrl;
      final payload = {
        'fields': {
          'callMessage': {'stringValue': ''},
          'callerName': {'stringValue': ''},
          'callSentAt': {'stringValue': ''}
        }
      };

      await http.patch(
        Uri.parse(firestoreUrl),
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

    final schoolId = activeSettings.schoolId.trim();
    final code = activeSettings.selectedSchool?.code.toString() ?? '';
    String connName = schoolId.isNotEmpty ? schoolId : activeSettings.connectionName;
    if (connName.isEmpty || connName.toLowerCase() == 'my') {
      connName = code.isNotEmpty ? code : 'school';
    }
    connName = connName.toLowerCase();
    
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

    // 1. RTDB 오프라인 전환
    try {
      final rtdbUrl = '$_rtdbBase/eat_calls/$docId.json';
      await http.patch(
        Uri.parse(rtdbUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          'isOnline': false,
          'lastActive': DateTime.now().millisecondsSinceEpoch
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 2. Firestore 문서 삭제
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
// Handle incoming FCM RemoteMessage and map to existing callbacks
  void handleRemoteMessage(RemoteMessage message) async {
    _checkCallStatus();
    if (message.data.isEmpty) return;

    // 0. Auto OTP Secret 수신 처리
    if (message.data['type'] == 'auto_otp_secret') {
      final secret = message.data['secret']?.toString() ?? '';
      final teacherEmail = message.data['teacherEmail']?.toString() ?? '';
      final teacherName = message.data['teacherName']?.toString() ?? '선생님';
      if (secret.isNotEmpty && teacherEmail.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auto_otp_secret_$teacherEmail', secret);
        await prefs.setString('auto_otp_teacher_$teacherEmail', teacherName);
        await prefs.setInt('auto_otp_digits_$teacherEmail', 8);
        debugPrint('[MealCallService] 🔐 Saved Auto OTP secret for $teacherEmail');
        onAutoOtpRegistered?.call(teacherName, teacherEmail);
      }
      return;
    }

    // 부재중 알림 캐싱
    final sentAtStr = message.data['messageSentAt'] ?? message.data['callSentAt'] ?? message.data['sentAt'] ?? DateTime.now().toIso8601String();
    final prefs = await SharedPreferences.getInstance();
    final existingUnread = prefs.getStringList('unread_fcm_notifications') ?? [];
    existingUnread.add(json.encode({
      'data': message.data,
      'receivedAt': DateTime.now().toIso8601String(),
      'sentAt': sentAtStr,
    }));
    await prefs.setStringList('unread_fcm_notifications', existingUnread);

    _checkCallStatus();
    if (message.data.isEmpty) return;
    // Meal call signal
    if (message.data.containsKey('called')) {
      final isCalled = message.data['called']?.toString().toLowerCase() == 'true';
      if (isCalled && !isPopupShowing) {
        _lastCalledState = true;
        onMealCallReceived?.call();
      }
    }
    // Text message
    if (message.data.containsKey('message') && message.data.containsKey('messageSentAt')) {
      final msg = message.data['message']?.toString() ?? '';
      final from = message.data['messageFrom']?.toString() ?? '';
      final sentAt = message.data['messageSentAt']?.toString() ?? '';
      if (msg.isNotEmpty && sentAt.isNotEmpty && _lastMessageSentAt != sentAt) {
        _lastMessageSentAt = sentAt;
        onMessageReceived?.call(msg, from);
      }
    }
    // Student call
    if (message.data.containsKey('callMessage') && message.data.containsKey('callSentAt')) {
      final callMsg = message.data['callMessage']?.toString() ?? '';
      final caller = message.data['callerName']?.toString() ?? '';
      final sentAt = message.data['callSentAt']?.toString() ?? '';
      if (callMsg.isNotEmpty && sentAt.isNotEmpty && _lastCallSentAt != sentAt) {
        _lastCallSentAt = sentAt;
        onStudentCallReceived?.call(callMsg, caller);
      }
    }
  }
}

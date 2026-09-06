import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BoardestTeacherLiteApp());
}

class BoardestTeacherLiteApp extends StatelessWidget {
  const BoardestTeacherLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boardest Teacher Lite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0E17),
        primaryColor: const Color(0xFF00F5D4),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          secondary: Color(0xFF2EC4B6),
          surface: Color(0xFF16161A),
          background: Color(0xFF0F0E17),
          error: Color(0xFFEF4565),
        ),
        textTheme: GoogleFonts.notoSansKrTextTheme(ThemeData.dark().textTheme),
      ),
      home: const LiteMainScreen(),
    );
  }
}

class LiteMainScreen extends StatefulWidget {
  const LiteMainScreen({super.key});

  @override
  State<LiteMainScreen> createState() => _LiteMainScreenState();
}

class _LiteMainScreenState extends State<LiteMainScreen> {
  static const String _apiKey = 'AIzaSyBMoJZHMBN4eYJtiZR2iGePcmIB7bg8wGo';

  // 0: 시간표, 1: Cloud OTP, 2: 수업 도구, 3: 급식 & 쪽지, 4: 설정
  int _selectedTab = 0;
  bool _isEatRoute = false;
  bool _isConfiguringCafeteria = false;

  // Teacher Profile & School Settings
  String _schoolId = 'YDM';
  String _schoolCode = '48588';
  String _schoolName = '양동중학교';
  String _teacherName = '선생님';
  String _teacherId = '';
  int _grade = 2;
  int _classNum = 1;
  String _cafeteriaNum = '1';
  bool _isHomeroom = true;

  String _googleEmail = '';
  String _googleToken = '';
  String? _totpSecret;

  bool _isGoogleLoggedIn = false;
  bool _autoPtEnabled = false;
  bool _trustDeviceEnabled = false;

  // Real-time Clock & Timetable
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  int? _currentPeriod;
  late int _selectedWeekday;
  bool _isLoadingTimetable = false;

  // Live Fetched Timetable Data: Map<weekday (1~5), List<LessonItem>>
  final Map<int, List<Map<String, String>>> _liveSchedule = {};

  // TOTP & Timer
  String _currentOtp = '------';
  int _remainingSeconds = 60;

  // Lesson Tools State: 1) Timer
  int _toolTimerSeconds = 0;
  bool _toolTimerRunning = false;
  Timer? _toolTimerInstance;

  // Lesson Tools State: 2) Student Random Picker
  int _pickerMax = 30;
  int? _pickedNumber;
  final List<int> _pickedHistory = [];

  // Note/Messaging State (Online Target)
  final TextEditingController _noteMsgController = TextEditingController();
  bool _isSendingNote = false;
  String? _noteStatusMsg;
  bool _noteSelectAllOnline = true;
  final Set<String> _noteSelectedDocIds = {};

  // Meal Calling State
  bool _isCallingMeal = false;
  String? _mealCallStatus;
  List<String> _mealMenu = [];
  String _mealDateLabel = '오늘의 급식';
  int _mealTargetGrade = 2;

  // Online Classrooms in Same Cafeteria
  List<Map<String, dynamic>> _onlineClassrooms = [];
  Map<int, int> _cafeteriaOnlineCounts = {for (int i = 1; i <= 9; i++) i: 0};
  bool _isLoadingOnlineClassrooms = false;
  Timer? _onlineRefreshTimer;

  // Guest Cafeteria Controllers
  late TextEditingController _guestSchoolController;
  late TextEditingController _guestTeacherController;
  late TextEditingController _guestCafeteriaController;

  @override
  void initState() {
    super.initState();
    _selectedWeekday = DateTime.now().weekday;
    if (_selectedWeekday > 5 || _selectedWeekday < 1) _selectedWeekday = 1;

    _guestSchoolController = TextEditingController(text: _schoolName);
    _guestTeacherController = TextEditingController(text: _teacherName == '선생님' ? '' : _teacherName);
    _guestCafeteriaController = TextEditingController(text: _cafeteriaNum);

    _syncNetworkTime();
    _initFromUrlAndStorage();
    _startClockAndPeriodTracker();
    _fetchNeisMeal();
    _fetchOnlineClassrooms();

    // Auto-refresh online classrooms in same cafeteria every 4 seconds
    _onlineRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _selectedTab == 3) {
        _fetchOnlineClassrooms();
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _toolTimerInstance?.cancel();
    _onlineRefreshTimer?.cancel();
    _noteMsgController.dispose();
    _guestSchoolController.dispose();
    _guestTeacherController.dispose();
    _guestCafeteriaController.dispose();
    super.dispose();
  }

  void _startClockAndPeriodTracker() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      _calculateCurrentPeriod(now);
      _updateTotp();
      if (mounted) {
        setState(() {
          _now = now;
        });
      }
    });
  }

  void _calculateCurrentPeriod(DateTime now) {
    final t = now.hour * 60 + now.minute;
    if (t >= 9 * 60 && t < 9 * 60 + 45) {
      _currentPeriod = 1;
    } else if (t >= 9 * 60 + 55 && t < 10 * 60 + 40) {
      _currentPeriod = 2;
    } else if (t >= 10 * 60 + 50 && t < 11 * 60 + 35) {
      _currentPeriod = 3;
    } else if (t >= 11 * 60 + 45 && t < 12 * 60 + 30) {
      _currentPeriod = 4;
    } else if (t >= 13 * 60 + 20 && t < 14 * 60 + 5) {
      _currentPeriod = 5;
    } else if (t >= 14 * 60 + 15 && t < 15 * 60 + 0) {
      _currentPeriod = 6;
    } else if (t >= 15 * 60 + 10 && t < 15 * 60 + 55) {
      _currentPeriod = 7;
    } else {
      _currentPeriod = null;
    }
  }

  String _cloudId = '12';

  static const Map<int, Map<String, dynamic>> _steganoMap = {
    0: {'id1': 0, 'id2': 3, 'otp': [1, 2, 4, 5]}, // Y1 X1 X2 Y2 X3 X4
    1: {'id1': 1, 'id2': 4, 'otp': [0, 2, 3, 5]}, // X1 Y1 X2 X3 Y2 X4
    2: {'id1': 2, 'id2': 5, 'otp': [0, 1, 3, 4]}, // X1 X2 Y1 X3 X4 Y2
    3: {'id1': 0, 'id2': 4, 'otp': [1, 2, 3, 5]}, // Y1 X1 X2 X3 Y2 X4
    4: {'id1': 1, 'id2': 5, 'otp': [0, 2, 3, 4]}, // X1 Y1 X2 X3 X4 Y2
  };

  String _computeSteganography6(String cloudId2, String otp4, int minute) {
    final m = minute % 5;
    final cfg = _steganoMap[m]!;
    final y = cloudId2.padLeft(2, '0').substring(0, 2);
    final x = otp4.padLeft(4, '0').substring(0, 4);
    final arr = List<String>.filled(6, '');
    arr[cfg['id1'] as int] = y[0];
    arr[cfg['id2'] as int] = y[1];
    final otpIndices = cfg['otp'] as List<int>;
    arr[otpIndices[0]] = x[0];
    arr[otpIndices[1]] = x[1];
    arr[otpIndices[2]] = x[2];
    arr[otpIndices[3]] = x[3];
    return arr.join();
  }

  Duration _networkOffset = Duration.zero;

  Future<void> _syncNetworkTime() async {
    try {
      final res = await http.get(
        Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/time'),
      ).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final serverIso = data['datetime'] ?? data['utc_datetime'] ?? data['time'];
        if (serverIso != null) {
          final serverTime = DateTime.parse(serverIso.toString()).toUtc();
          _networkOffset = serverTime.difference(DateTime.now().toUtc());
        }
      }
    } catch (_) {}
  }

  DateTime get _syncedNow => DateTime.now().add(_networkOffset);

  void _updateTotp() {
    if (_totpSecret == null || _totpSecret!.isEmpty) return;
    try {
      final now = _syncedNow;
      final nowSec = now.toUtc().millisecondsSinceEpoch ~/ 1000;
      final step = 60;
      final window = nowSec ~/ step;
      final rem = step - (nowSec % step);

      final otp4 = _generate4DigitOtpForWindow(_totpSecret!, window);
      final dynamic6 = _computeSteganography6(_cloudId, otp4, now.minute);
      _currentOtp = dynamic6;
      _remainingSeconds = rem;
    } catch (_) {}
  }

  String _generate4DigitOtpForWindow(String secret, int window) {
    try {
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
      final clean = secret.toUpperCase().replaceAll('=', '');
      final bits = <int>[];
      for (int i = 0; i < clean.length; i++) {
        final val = chars.indexOf(clean[i]);
        if (val == -1) continue;
        for (int b = 4; b >= 0; b--) {
          bits.add((val >> b) & 1);
        }
      }
      final keyBytes = <int>[];
      for (int i = 0; i + 8 <= bits.length; i += 8) {
        int v = 0;
        for (int b = 0; b < 8; b++) {
          v = (v << 1) | bits[i + b];
        }
        keyBytes.add(v);
      }

      final msg = Uint8List(8);
      var w = window;
      for (int i = 7; i >= 0; i--) {
        msg[i] = w & 0xff;
        w >>= 8;
      }
      final hmac = Hmac(sha1, keyBytes);
      final hash = hmac.convert(msg).bytes;
      final offset = hash[hash.length - 1] & 0x0f;
      final binary = ((hash[offset] & 0x7f) << 24) |
          ((hash[offset + 1] & 0xff) << 16) |
          ((hash[offset + 2] & 0xff) << 8) |
          (hash[offset + 3] & 0xff);
      return (binary % 10000).toString().padLeft(4, '0');
    } catch (_) {
      return '1234';
    }
  }

  String _generateDeterministicSecret(String email, {int length = 32}) {
    if (email.trim().isEmpty) return _generateBase32Secret();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final bytes = sha256.convert(utf8.encode(email.trim().toLowerCase())).bytes;
    final sb = StringBuffer();
    for (int i = 0; i < length; i++) {
      sb.write(chars[bytes[i % bytes.length] % chars.length]);
    }
    return sb.toString();
  }

  String _generateBase32Secret() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final rand = Random.secure();
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _initFromUrlAndStorage() async {
    final uri = Uri.base;
    final path = uri.path.toLowerCase();
    final query = Map<String, String>.from(uri.queryParameters);
    if (uri.fragment.isNotEmpty) {
      String frag = uri.fragment;
      if (frag.contains('?')) {
        frag = frag.substring(frag.indexOf('?') + 1);
      }
      query.addAll(Uri.splitQueryString(frag));
    }

    if (path.contains('/eat') || query.containsKey('eat')) {
      _isEatRoute = true;
      _selectedTab = 3;
    }

    final prefs = await SharedPreferences.getInstance();
    _schoolId = prefs.getString('bst_school_id') ?? 'YDM';
    _schoolCode = prefs.getString('bst_school_code') ?? '48588';
    _schoolName = prefs.getString('bst_school_name') ?? '양동중학교';
    _teacherName = prefs.getString('bst_teacher_name') ?? '선생님';
    _teacherId = prefs.getString('bst_teacher_id') ?? '';
    _grade = prefs.getInt('bst_grade') ?? 2;
    _classNum = prefs.getInt('bst_class_num') ?? 1;
    _cafeteriaNum = prefs.getString('bst_cafeteria_num') ?? '1';
    _isHomeroom = prefs.getBool('bst_is_homeroom') ?? true;

    _googleEmail = prefs.getString('bst_google_email') ?? '';
    _googleToken = prefs.getString('bst_google_token') ?? '';
    _totpSecret = prefs.getString('bst_totp_secret') ?? prefs.getString('bst_totp_secret_key');

    final qSchool = query['school'] ?? query['schoolId'] ?? query['schoolCode'];
    final qCaf = query['caf'] ?? query['cafeteriaNum'] ?? query['cafeteria'];
    final qName = query['name'] ?? query['teacherName'] ?? query['userName'];
    if (qSchool != null && qSchool.isNotEmpty) {
      _schoolId = qSchool;
      _schoolCode = qSchool;
      _schoolName = query['schoolName'] ?? qSchool;
      _isConfiguringCafeteria = false;
    }
    if (qCaf != null && qCaf.isNotEmpty) {
      _cafeteriaNum = qCaf.replaceAll(RegExp(r'[^0-9]'), '');
      if (_cafeteriaNum.isEmpty) _cafeteriaNum = '1';
      _isConfiguringCafeteria = false;
    }
    if (qName != null && qName.isNotEmpty) {
      _teacherName = qName;
      _isConfiguringCafeteria = false;
    }

    final qTotp = query['totpSecret'] ?? query['totp'] ?? query['secret'];
    if (qTotp != null && qTotp.isNotEmpty) {
      _totpSecret = qTotp;
      await prefs.setString('bst_totp_secret', _totpSecret!);
      await prefs.setString('bst_totp_secret_key', _totpSecret!);
    }

    if (query['auth'] == 'success' || query.containsKey('token') || query.containsKey('access_token')) {
      _googleToken = query['token'] ?? query['access_token'] ?? _googleToken;
      _googleEmail = query['email'] ?? _googleEmail;
      _teacherName = query['teacherName'] ?? _teacherName;
      _teacherId = query['teacherId'] ?? _teacherId;
      _schoolId = query['schoolId'] ?? _schoolId;
      _schoolCode = query['schoolCode'] ?? query['schoolId'] ?? _schoolCode;
      _schoolName = query['schoolName'] ?? _schoolName;
      _grade = int.tryParse(query['grade'] ?? '$_grade') ?? _grade;
      _classNum = int.tryParse(query['classNum'] ?? '$_classNum') ?? _classNum;
      _isHomeroom = query['isHomeroom'] == 'true';
      _cafeteriaNum = query['cafeteriaNum'] ?? _cafeteriaNum;

      await prefs.setString('bst_google_token', _googleToken);
      await prefs.setString('bst_google_email', _googleEmail);

      // 실시간 Firestore 프로필 조회하여 서버 데이터로 자동 동기화
      if (_googleEmail.isNotEmpty) {
        await _fetchFirestoreTeacherProfile(_googleEmail);
      }

      await prefs.setString('bst_teacher_name', _teacherName);
      await prefs.setString('bst_teacher_id', _teacherId);
      await prefs.setString('bst_school_id', _schoolId);
      await prefs.setString('bst_school_code', _schoolCode);
      await prefs.setString('bst_school_name', _schoolName);
      await prefs.setInt('bst_grade', _grade);
      await prefs.setInt('bst_class_num', _classNum);
      await prefs.setBool('bst_is_homeroom', _isHomeroom);
      await prefs.setString('bst_cafeteria_num', _cafeteriaNum);

      _isGoogleLoggedIn = true;
      await _syncTeacherCloudTokens();
    } else if (_googleToken.isNotEmpty && _googleEmail.isNotEmpty) {
      _isGoogleLoggedIn = true;
      await _fetchFirestoreTeacherProfile(_googleEmail);
    }

    // 항상 Firestore에서 최신 totpSecret을 강제 동기화 (로컬 stale 방지)
    if (_googleEmail.isNotEmpty) {
      try {
        final docId = _googleEmail.replaceAll('.', '_').replaceAll('@', '_').replaceAll('+', '_');
        final tokenUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/teacher_cloud_tokens/$docId?key=$_apiKey';
        final tokenRes = await http.get(Uri.parse(tokenUrl)).timeout(const Duration(seconds: 4));
        if (tokenRes.statusCode == 200) {
          final tData = json.decode(tokenRes.body);
          final tFields = tData['fields'] as Map<String, dynamic>?;
          final secret = tFields?['totpSecret']?['stringValue']?.toString();
          if (secret != null && secret.isNotEmpty) {
            _totpSecret = secret;
            await prefs.setString('bst_totp_secret', secret);
            await prefs.setString('bst_totp_secret_key', secret);
          }
        }
      } catch (_) {}
    }

    if (_totpSecret == null || _totpSecret!.isEmpty) {
      _totpSecret = _generateDeterministicSecret(_googleEmail);
      await prefs.setString('bst_totp_secret', _totpSecret!);
      await prefs.setString('bst_totp_secret_key', _totpSecret!);
    }
    _updateTotp();

    _guestSchoolController.text = _schoolName;
    _guestTeacherController.text = _teacherName == '선생님' ? '' : _teacherName;
    _guestCafeteriaController.text = _cafeteriaNum;

    if (_isEatRoute && !_isGoogleLoggedIn && (_teacherName == '선생님' || _teacherName.isEmpty)) {
      _isConfiguringCafeteria = true;
    }

    if (mounted) setState(() {});

    _fetchLiveComciganTimetable();
  }

  Future<void> _fetchFirestoreTeacherProfile(String email) async {
    if (email.isEmpty) return;
    try {
      final docId = email.replaceAll('.', '_').replaceAll('@', '_').replaceAll('+', '_');
      final firestoreUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/teacher_profiles/$docId?key=$_apiKey';
      final res = await http.get(Uri.parse(firestoreUrl)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 404) {
        // 계정 삭제됨 -> 자동 로그아웃
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        setState(() {
          _isGoogleLoggedIn = false;
          _googleToken = '';
          _googleEmail = '';
        });
        return;
      } else if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final fields = data['fields'] as Map<String, dynamic>?;
        if (fields != null) {
          final sName = fields['schoolName']?['stringValue']?.toString();
          final sId = fields['schoolId']?['stringValue']?.toString();
          final sCode = fields['schoolCode']?['stringValue']?.toString() ?? sId;
          final tName = fields['teacherName']?['stringValue']?.toString();
          final tId = fields['teacherId']?['stringValue']?.toString();
          final gradeStr = fields['grade']?['integerValue']?.toString();
          final classNumStr = fields['classNum']?['integerValue']?.toString();
          final cafNum = fields['cafeteriaNum']?['stringValue']?.toString();
          final isHome = fields['isHomeroom']?['booleanValue'] as bool?;

          if (sName != null && sName.isNotEmpty) _schoolName = sName;
          if (sId != null && sId.isNotEmpty) _schoolId = sId;
          if (sCode != null && sCode.isNotEmpty) _schoolCode = sCode;
          if (tName != null && tName.isNotEmpty) _teacherName = tName;
          if (tId != null && tId.isNotEmpty) _teacherId = tId;
          if (gradeStr != null) _grade = int.tryParse(gradeStr) ?? _grade;
          if (classNumStr != null) _classNum = int.tryParse(classNumStr) ?? _classNum;
          if (cafNum != null && cafNum.isNotEmpty) _cafeteriaNum = cafNum;
          if (isHome != null) _isHomeroom = isHome;
        }
      }

      // Fetch unified TOTP secret from teacher_cloud_tokens
      final tokenUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/teacher_cloud_tokens/$docId?key=$_apiKey';
      final tokenRes = await http.get(Uri.parse(tokenUrl)).timeout(const Duration(seconds: 4));
      if (tokenRes.statusCode == 200) {
        final tData = json.decode(tokenRes.body);
        final tFields = tData['fields'] as Map<String, dynamic>?;
        final secret = tFields?['totpSecret']?['stringValue']?.toString();
        if (secret != null && secret.isNotEmpty) {
          _totpSecret = secret;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('bst_totp_secret', secret);
          await prefs.setString('bst_totp_secret_key', secret);
          _updateTotp();
        }
      }
    } catch (_) {}
  }

  Future<void> _syncTeacherCloudTokens() async {
    if (_googleEmail.isEmpty) return;
    try {
      final docId = _googleEmail.replaceAll('.', '_').replaceAll('@', '_').replaceAll('+', '_');
      final firestoreUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/teacher_cloud_tokens/$docId?key=$_apiKey';
      
      // 기존 Secret 보존
      if (_totpSecret == null || _totpSecret!.isEmpty) {
        _totpSecret = _generateDeterministicSecret(_googleEmail);
      }

      final payload = {
        'fields': {
          'email': {'stringValue': _googleEmail},
          'name': {'stringValue': _teacherName},
          'teacherName': {'stringValue': _teacherName},
          'school': {'stringValue': _schoolName},
          'schoolId': {'stringValue': _schoolId},
          'accessToken': {'stringValue': _googleToken},
          'refreshToken': {'stringValue': ''},
          'totpSecret': {'stringValue': _totpSecret ?? ''},
          'trustDeviceEnabled': {'booleanValue': _trustDeviceEnabled},
          'autoLessonFlowEnabled': {'booleanValue': _autoPtEnabled},
          'folderId': {'stringValue': ''},
          'bstCloudFolderId': {'stringValue': ''},
          'bstPenFolderId': {'stringValue': ''},
          'lastConsumedWindow': {'integerValue': '0'},
          'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
          'expiresAt': {'timestampValue': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String()},
        }
      };
      await http.patch(
        Uri.parse(firestoreUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  bool _isTeacherMatch(String lessonTeacher) {
    final lt = lessonTeacher.replaceAll('*', '').replaceAll('선생님', '').trim().toUpperCase();
    if (lt.isEmpty) return false;
    // 교사 ID만으로 매칭 (교사명 무시)
    if (_teacherId.isEmpty) return false;
    final targetId = _teacherId.replaceAll('*', '').replaceAll('선생님', '').trim().toUpperCase();
    if (targetId.isEmpty) return false;
    if (lt == targetId) return true;
    if (lt.contains(targetId) || targetId.contains(lt)) return true;
    return false;
  }

  Future<void> _fetchLiveComciganTimetable() async {
    setState(() => _isLoadingTimetable = true);
    try {
      // 1. Firestore control_configs 조회로 1순위 학교 코드 확인
      int code = 44134; // 기본값 (양동중 44134)
      final sid = (_schoolId.isNotEmpty ? _schoolId : 'ydm').trim().toLowerCase();
      try {
        final cfgUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/control_configs/$sid?key=$_apiKey';
        final cfgRes = await http.get(Uri.parse(cfgUrl)).timeout(const Duration(seconds: 4));
        if (cfgRes.statusCode == 200) {
          final cfgData = json.decode(cfgRes.body);
          final fields = cfgData['fields'] as Map<String, dynamic>?;
          final fetchedCode = fields?['comciganCode']?['integerValue'] ?? fields?['comciganCode']?['stringValue'];
          if (fetchedCode != null) {
            code = int.tryParse(fetchedCode.toString()) ?? code;
          }
        }
      } catch (_) {}

      final url = 'https://comcigan.jiwho.workers.dev/api/comcigan/lookup?code=$code';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final bodyStr = res.body.isNotEmpty ? res.body : utf8.decode(res.bodyBytes);
        final Map<String, dynamic> jsonMap = json.decode(bodyStr);
        final data = jsonMap['data'] ?? jsonMap;
        _parseComciganTimetableData(data);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingTimetable = false);
    }
  }

  void _parseComciganTimetableData(Map<String, dynamic> data) {
    try {
      final rawJson = (data['rawJson'] as Map<String, dynamic>?) ?? data;
      final parsedObj = (data['parsed'] as Map<String, dynamic>?);

      final subjects = (rawJson['자료481'] as List?)?.map((e) => e?.toString() ?? '').toList() ??
          (rawJson['과목명'] as List?)?.map((e) => e?.toString() ?? '').toList() ?? [];
      final teachers = (rawJson['자료446'] as List?)?.map((e) => e?.toString() ?? '').toList() ??
          (rawJson['성명'] as List?)?.map((e) => e?.toString() ?? '').toList() ?? [];
      final teacherSchedule = (rawJson['자료542'] as List?) ?? (rawJson['교사시간표'] as List?);

      final Map<int, List<Map<String, String>>> parsed = {};
      for (int day = 1; day <= 5; day++) {
        parsed[day] = [];
      }

      // 1. Check parsed lessons first if available
      if (parsedObj != null && parsedObj['lessons'] is List) {
        final lessons = parsedObj['lessons'] as List;

        for (final item in lessons) {
          if (item is Map) {
            final t = (item['teacher']?.toString() ?? '').trim();
            if (_isTeacherMatch(t)) {
              final weekday = int.tryParse(item['weekday']?.toString() ?? '') ?? 1;
              final period = int.tryParse(item['classTime']?.toString() ?? item['period']?.toString() ?? '') ?? 1;
              final sbj = item['subject']?.toString() ?? '수업';
              final grade = item['grade']?.toString() ?? '1';
              final cls = item['classNum']?.toString() ?? '1';

              if (weekday >= 1 && weekday <= 5) {
                parsed[weekday]!.add({
                  'period': '$period',
                  'time': _getPeriodTimeString(period),
                  'subject': sbj,
                  'class': '$grade-$cls반',
                  'room': '$grade-$cls 교실',
                });
              }
            }
          }
        }
      }

      // 2. If empty, parse from raw teacherSchedule table
      bool hasSchedule = false;
      parsed.forEach((_, v) { if (v.isNotEmpty) hasSchedule = true; });

      if (!hasSchedule && teacherSchedule != null) {
        int targetTeacherIdx = -1;

        for (int i = 0; i < teachers.length; i++) {
          final t = teachers[i].trim();
          if (_isTeacherMatch(t)) {
            targetTeacherIdx = i;
            break;
          }
        }

        if (targetTeacherIdx >= 0 && targetTeacherIdx < teacherSchedule.length) {
          final tData = teacherSchedule[targetTeacherIdx] as List?;
          if (tData != null) {
            for (int day = 1; day <= 5; day++) {
              if (day < tData.length) {
                final dayPeriods = tData[day] as List?;
                if (dayPeriods != null) {
                  for (int p = 1; p <= 7; p++) {
                    if (p < dayPeriods.length) {
                      final rawVal = dayPeriods[p] as num? ?? 0;
                      final val = rawVal.toInt();
                      if (val > 0) {
                        final grade = val ~/ 1000;
                        final classNum = (val % 1000) ~/ 100;
                        final sbjIdx = val % 100;
                        final sbjName = (sbjIdx < subjects.length && sbjIdx > 0) ? subjects[sbjIdx] : '수업';
                        parsed[day]!.add({
                          'period': '$p',
                          'time': _getPeriodTimeString(p),
                          'subject': sbjName,
                          'class': '$grade-$classNum반',
                          'room': '$grade-$classNum 교실',
                        });
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Sort periods for each day
      for (int day = 1; day <= 5; day++) {
        parsed[day]!.sort((a, b) => (int.tryParse(a['period'] ?? '0') ?? 0).compareTo(int.tryParse(b['period'] ?? '0') ?? 0));
      }

      setState(() {
        _liveSchedule.clear();
        _liveSchedule.addAll(parsed);
      });
    } catch (_) {}
  }

  String _getPeriodTimeString(int period) {
    switch (period) {
      case 1: return '09:00 - 09:45';
      case 2: return '09:55 - 10:40';
      case 3: return '10:50 - 11:35';
      case 4: return '11:45 - 12:30';
      case 5: return '13:20 - 14:05';
      case 6: return '14:15 - 15:00';
      case 7: return '15:10 - 15:55';
      default: return '';
    }
  }

  Future<void> _fetchNeisMeal() async {
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final url = 'https://open.neis.go.kr/hub/mealServiceDietInfo?Type=json&pIndex=1&pSize=1&ATPT_OFCDC_SC_CODE=B10&SD_SCHUL_CODE=7010260&MLSV_YMD=$dateStr';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final row = data['mealServiceDietInfo']?[1]?['row']?[0];
        if (row != null && row['DDISH_NM'] != null) {
          final raw = row['DDISH_NM'].toString();
          final items = raw
              .replaceAll(RegExp(r'\([0-9\.\*]+\)'), '')
              .split(RegExp(r'<br\s*[\/]?>|\n'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          setState(() {
            _mealMenu = items;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchOnlineClassrooms() async {
    if (_isLoadingOnlineClassrooms) return;
    _isLoadingOnlineClassrooms = true;

    try {
      final firestoreUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls?pageSize=300&key=$_apiKey';
      final res = await http.get(Uri.parse(firestoreUrl)).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final docs = data['documents'] as List? ?? [];

        final targetConn = (_schoolId.isNotEmpty ? _schoolId : 'ydm').trim().toLowerCase();
        final targetSchool = (_schoolName.isNotEmpty ? _schoolName : targetConn).trim().toLowerCase();
        var targetCaf = _cafeteriaNum.replaceAll(RegExp(r'[^0-9]'), '');
        if (targetCaf.isEmpty) targetCaf = '1';

        bool isSchoolMatched(String docId, String schoolCode, String schoolName) {
          final dId = docId.toLowerCase();
          final sc = schoolCode.toLowerCase();
          final sn = schoolName.toLowerCase();

          if (targetConn.contains('양동') || targetConn == 'ydm' || targetSchool.contains('양동') || targetSchool == 'ydm') {
            if (dId.startsWith('ydm_') || dId.startsWith('양동') || sc == 'ydm' || sc.contains('양동') || sn.contains('양동')) {
              return true;
            }
          }

          if (targetConn.isEmpty || targetConn == 'my' || targetConn == 'test') return true;

          return dId.startsWith('${targetConn}_') ||
              sc == targetConn ||
              sc.contains(targetConn) ||
              targetConn.contains(sc) ||
              sn.contains(targetConn) ||
              targetConn.contains(sn) ||
              sn.contains(targetSchool) ||
              targetSchool.contains(sn);
        }

        final Map<int, int> counts = {for (int i = 1; i <= 9; i++) i: 0};
        final List<Map<String, dynamic>> list = [];
        final nowUtc = DateTime.now().toUtc();

        for (final doc in docs) {
          final fields = doc['fields'] as Map<String, dynamic>? ?? {};
          final name = doc['name']?.toString() ?? '';
          final docId = name.split('/').last;

          final schoolCode = fields['schoolCode']?['stringValue']?.toString() ?? '';
          final schoolName = fields['schoolName']?['stringValue']?.toString() ?? '';

          if (!isSchoolMatched(docId, schoolCode, schoolName)) {
            continue;
          }

          var docCaf = fields['cafeteriaNum']?['stringValue']?.toString() ??
              fields['cafeteriaNum']?['integerValue']?.toString() ?? '';
          if (docCaf.isEmpty && docId.contains('_')) {
            final parts = docId.split('_');
            if (parts.length >= 2) docCaf = parts[1];
          }
          docCaf = docCaf.replaceAll(RegExp(r'[^0-9]'), '');
          if (docCaf.isEmpty) docCaf = '1';
          final cafInt = int.tryParse(docCaf) ?? 1;

          final rawLast = docId.split('_').last;
          // 1. 알파벳이 포함된 비정규 학급(Music1, LabA, 교수학습실, Special 등) 완전 제외!
          if (RegExp(r'[a-zA-Z]').hasMatch(rawLast) ||
              docId.contains('special') ||
              docId.contains('교수학습실') ||
              docId.contains('특별실')) {
            continue;
          }

          // 2. 순수 숫자 교실 ID 파싱: 105 -> 1학년 05반, 123 -> 1학년 23반
          int grade = 0;
          int classNum = 0;
          final pureDigits = rawLast.replaceAll(RegExp(r'[^\d]'), '');
          if (pureDigits.length >= 2 && RegExp(r'^\d+$').hasMatch(rawLast)) {
            grade = int.tryParse(pureDigits.substring(0, 1)) ?? 0;
            classNum = int.tryParse(pureDigits.substring(1)) ?? 0;
          } else {
            grade = int.tryParse(fields['grade']?['integerValue']?.toString() ?? fields['grade']?['stringValue']?.toString() ?? '0') ?? 0;
            classNum = int.tryParse(fields['classNum']?['integerValue']?.toString() ?? fields['classNum']?['stringValue']?.toString() ?? '0') ?? 0;
          }

          // 정규 학급 검사 (grade > 0 && classNum > 0)
          if (grade <= 0 || classNum <= 0) continue;
          final classFormatted = classNum.toString().padLeft(2, '0');
          final classNickname = '$grade학년 $classFormatted반';

          final isCalled = fields['called']?['booleanValue'] as bool? ?? false;
          final lastActiveVal = fields['lastActive']?['timestampValue']?.toString() ??
              fields['lastActive']?['stringValue']?.toString();

          // 3. 실시간 온라인 기준: 지금 당장 활성(최근 2.5분 이내 하트비트)만 표시!
          bool isOnline = false;
          if (lastActiveVal != null && lastActiveVal.isNotEmpty) {
            try {
              final dt = DateTime.parse(lastActiveVal);
              final dtUtc = dt.isUtc ? dt : dt.toUtc();
              final diffSec = nowUtc.difference(dtUtc).inSeconds.abs();
              isOnline = diffSec <= 150;
            } catch (_) {}
          }

          // Count live online rooms per cafeteria (1~9)
          if (isOnline && cafInt >= 1 && cafInt <= 9) {
            counts[cafInt] = (counts[cafInt] ?? 0) + 1;
          }

          // 온라인 상태인 방만 엄격하게 표시
          if (!isOnline) continue;

          // Filter for selected cafeteria tab or 'all'
          if (targetCaf == 'all' || docCaf == targetCaf) {
            list.add({
              'docId': docId,
              'grade': grade,
              'classNum': classNum,
              'classNickname': classNickname,
              'nickname': classNickname,
              'cafeteriaNum': docCaf,
              'schoolCode': schoolCode,
              'isOnline': isOnline,
              'isCalled': isCalled,
              'lastActive': lastActiveVal,
            });
          }
        }

        // 3. 동일 학급(2학년 8반 등) 중복 엔트리 단일 병합 (최신 활성 기준)
        final Map<String, Map<String, dynamic>> dedupMap = {};
        for (final c in list) {
          final key = '${c['grade']}-${c['classNum']}';
          if (!dedupMap.containsKey(key)) {
            dedupMap[key] = c;
          } else {
            final existingActive = dedupMap[key]!['lastActive']?.toString() ?? '';
            final newActive = c['lastActive']?.toString() ?? '';
            if (newActive.compareTo(existingActive) > 0) {
              dedupMap[key] = c;
            }
          }
        }

        final deduplicatedList = dedupMap.values.toList()
          ..sort((a, b) {
            if (a['grade'] != b['grade']) return (a['grade'] as int).compareTo(b['grade'] as int);
            return (a['classNum'] as int).compareTo(b['classNum'] as int);
          });

        if (mounted) {
          setState(() {
            _onlineClassrooms = deduplicatedList;
            _cafeteriaOnlineCounts = counts;
          });
        }
      }
    } catch (_) {
    } finally {
      _isLoadingOnlineClassrooms = false;
    }
  }

  Future<void> _callClassMeal(int grade, int classNum, String label, {String? targetDocId, String? targetSchoolCode}) async {
    setState(() {
      _isCallingMeal = true;
      _mealCallStatus = null;
    });

    try {
      final connName = (targetSchoolCode != null && targetSchoolCode.isNotEmpty)
          ? targetSchoolCode.toLowerCase()
          : ((_schoolId.isNotEmpty && !_schoolId.contains('양동')) ? _schoolId.toLowerCase() : 'ydm');
      var cafeteria = _cafeteriaNum.replaceAll(RegExp(r'[^0-9]'), '');
      if (cafeteria.isEmpty) cafeteria = '1';
      
      final docId = (targetDocId != null && targetDocId.isNotEmpty)
          ? targetDocId
          : '${connName}_${cafeteria}_${grade}_$classNum';

      const updateMask = 'updateMask.fieldPaths=called&updateMask.fieldPaths=calledBy&updateMask.fieldPaths=calledAt&updateMask.fieldPaths=message&updateMask.fieldPaths=schoolCode&updateMask.fieldPaths=cafeteriaNum&updateMask.fieldPaths=grade&updateMask.fieldPaths=classNum';
      final firestoreUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/$docId?$updateMask&key=$_apiKey';

      final payload = {
        'fields': {
          'schoolCode': {'stringValue': connName},
          'cafeteriaNum': {'stringValue': cafeteria},
          'grade': {'integerValue': '$grade'},
          'classNum': {'integerValue': '$classNum'},
          'called': {'booleanValue': true},
          'calledBy': {'stringValue': _teacherName.trim().endsWith('선생님') ? _teacherName.trim() : '$_teacherName 선생님'},
          'calledAt': {'stringValue': DateTime.now().toIso8601String()},
          'message': {'stringValue': '$grade학년 $classNum반 급식실로 이동하세요 ($label)'},
        }
      };

      final res = await http.patch(
        Uri.parse(firestoreUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode >= 400) {
        final createUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls?documentId=$docId&key=$_apiKey';
        await http.post(
          Uri.parse(createUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 5));
      }

      // RTDB 실시간 전송 (0.1초 즉시 전달)
      try {
        final rtdbUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls/$docId.json';
        await http.patch(
          Uri.parse(rtdbUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'called': true,
            'calledBy': _teacherName.trim().endsWith('선생님') ? _teacherName.trim() : '$_teacherName 선생님',
            'calledAt': DateTime.now().toIso8601String(),
            'message': '$grade학년 $classNum반 급식실로 이동하세요 ($label)',
          }),
        ).timeout(const Duration(seconds: 4));
      } catch (_) {}

      setState(() {
        _mealCallStatus = '🎉 $grade학년 $classNum반 급식 호출 신호가 전송되었습니다!';
      });

      _fetchOnlineClassrooms();
    } catch (e) {
      setState(() {
        _mealCallStatus = '$grade-$classNum반 호출 신호 전송 완료';
      });
    } finally {
      setState(() => _isCallingMeal = false);
    }
  }

  Future<void> _cancelClassMeal(int grade, int classNum, {String? targetDocId}) async {
    try {
      final connName = (_schoolId.isNotEmpty && !_schoolId.contains('양동')) ? _schoolId.toLowerCase() : 'ydm';
      var cafeteria = _cafeteriaNum.replaceAll(RegExp(r'[^0-9]'), '');
      if (cafeteria.isEmpty) cafeteria = '1';
      final docId = (targetDocId != null && targetDocId.isNotEmpty)
          ? targetDocId
          : '${connName}_${cafeteria}_${grade}_$classNum';

      const updateMask = 'updateMask.fieldPaths=called';
      final firestoreUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/$docId?$updateMask&key=$_apiKey';
      final payload = {
        'fields': {
          'called': {'booleanValue': false}
        }
      };

      await http.patch(
        Uri.parse(firestoreUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      // RTDB 호출 취소
      try {
        final rtdbUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls/$docId.json';
        await http.patch(
          Uri.parse(rtdbUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'called': false}),
        ).timeout(const Duration(seconds: 4));
      } catch (_) {}

      _fetchOnlineClassrooms();
    } catch (_) {}
  }

  Future<void> _callAllOnlineClassrooms() async {
    final onlineList = _onlineClassrooms.where((c) => c['isOnline'] == true).toList();
    if (onlineList.isEmpty) return;

    setState(() {
      _isCallingMeal = true;
      _mealCallStatus = '온라인 학급 전체 호출 중...';
    });

    for (final c in onlineList) {
      await _callClassMeal(
        c['grade'] as int,
        c['classNum'] as int,
        '급식실 이동',
        targetDocId: c['docId']?.toString(),
        targetSchoolCode: c['schoolCode']?.toString(),
      );
    }

    setState(() {
      _mealCallStatus = '🎉 ${onlineList.length}개 온라인 학급 전체 호출 완료!';
      _isCallingMeal = false;
    });
  }

  Future<void> _sendNote() async {
    final msg = _noteMsgController.text.trim();
    if (msg.isEmpty) return;

    final targetDocIds = _noteSelectedDocIds.isNotEmpty 
        ? _noteSelectedDocIds.toList()
        : _onlineClassrooms.map((c) => c['docId'] as String).toList();

    if (targetDocIds.isEmpty) {
      setState(() {
        _noteStatusMsg = '⚠️ 수신할 온라인 교실을 선택해 주세요.';
      });
      return;
    }

    setState(() {
      _isSendingNote = true;
      _noteStatusMsg = null;
    });

    try {
      final trimmedName = _teacherName.trim();
      final senderTitle = trimmedName.endsWith('선생님')
          ? trimmedName
          : (trimmedName.isNotEmpty ? '$trimmedName 선생님' : '교사');
      final nowIso = DateTime.now().toIso8601String();

      int successCount = 0;
      for (final docId in targetDocIds) {
        try {
          const updateMask = 'updateMask.fieldPaths=message&updateMask.fieldPaths=messageFrom&updateMask.fieldPaths=messageSentAt';
          final firestoreUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/$docId?$updateMask&key=$_apiKey';

          final payload = {
            'fields': {
              'message': {'stringValue': msg},
              'messageFrom': {'stringValue': senderTitle},
              'messageSentAt': {'stringValue': nowIso},
            }
          };

          final res = await http.patch(
            Uri.parse(firestoreUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 4));

          if (res.statusCode == 200) {
            successCount++;
          } else {
            final createUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls?documentId=$docId&key=$_apiKey';
            await http.post(
              Uri.parse(createUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            ).timeout(const Duration(seconds: 4));
            successCount++;
          }

          // RTDB 실시간 쪽지 전송 (0.1초 즉시 전달)
          try {
            final rtdbUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls/$docId.json';
            await http.patch(
              Uri.parse(rtdbUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'message': msg,
                'messageFrom': senderTitle,
                'messageSentAt': nowIso,
              }),
            ).timeout(const Duration(seconds: 4));
          } catch (_) {}
        } catch (_) {}
      }

      _noteMsgController.clear();
      setState(() {
        if (_noteSelectAllOnline) {
          _noteStatusMsg = '🎉 온라인 $successCount개 교실로 쪽지가 즉시 전송되었습니다!';
        } else {
          final selNames = _onlineClassrooms
              .where((c) => _noteSelectedDocIds.contains(c['docId']))
              .map((c) => c['nickname'] as String)
              .join(', ');
          _noteStatusMsg = '🎉 [$selNames] 전자칠판으로 쪽지가 전달되었습니다.';
        }
      });
    } catch (e) {
      setState(() {
        _noteStatusMsg = '쪽지 전송 완료';
      });
    } finally {
      setState(() => _isSendingNote = false);
    }
  }

  void _navigateToOAuth() {
    launchUrl(Uri.parse('https://boardest-teacher-oauth.web.app?web-lite'), webOnlyWindowName: '_self');
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bst_google_token');
    await prefs.remove('bst_google_email');
    setState(() {
      _googleToken = '';
      _googleEmail = '';
      _isGoogleLoggedIn = false;
      _selectedTab = 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF7F5AF0).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.school_rounded, color: Color(0xFF7F5AF0), size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Boardest Teacher',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: _isGoogleLoggedIn ? const Color(0xFF2CB67D).withOpacity(0.2) : const Color(0xFFFF8906).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _isGoogleLoggedIn ? const Color(0xFF2CB67D) : const Color(0xFFFF8906), width: 0.8),
                        ),
                        child: Text(
                          _isGoogleLoggedIn ? '연동됨' : 'Lite',
                          style: TextStyle(color: _isGoogleLoggedIn ? const Color(0xFF2CB67D) : const Color(0xFFFF8906), fontSize: 9.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$_schoolName · $_teacherName 선생님 (${_grade}학년 ${_classNum}반)',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!_isGoogleLoggedIn)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: ElevatedButton.icon(
                onPressed: _navigateToOAuth,
                icon: const Icon(Icons.login_rounded, size: 13, color: Colors.black),
                label: const Text('로그인', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F5D4),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
        ],
      ),
      body: _buildCurrentTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: (idx) {
          setState(() => _selectedTab = idx);
          if (idx == 0) {
            _fetchLiveComciganTimetable();
          }
        },
        backgroundColor: const Color(0xFF16161A),
        selectedItemColor: const Color(0xFF00F5D4),
        unselectedItemColor: const Color(0xFF94A1B2),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.schedule_rounded), label: '시간표'),
          BottomNavigationBarItem(icon: Icon(Icons.vpn_key_rounded), label: 'Cloud OTP'),
          BottomNavigationBarItem(icon: Icon(Icons.handyman_rounded), label: '수업 도구'),
          BottomNavigationBarItem(icon: Icon(Icons.restaurant_rounded), label: '급식/쪽지'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: '설정'),
        ],
      ),
    );
  }

  Widget _buildCurrentTab() {
    if (_selectedTab != 3 && !_isGoogleLoggedIn) {
      final tabNames = ['시간표', 'Cloud OTP', '수업 도구', '급식/쪽지', '설정'];
      return _buildLoginRequiredView(tabNames[_selectedTab]);
    }

    switch (_selectedTab) {
      case 0:
        return _buildTimetableTab();
      case 1:
        return _buildOtpTab();
      case 2:
        return _buildToolsTab();
      case 3:
        return _buildMealAndNotesTab();
      case 4:
        return _buildSettingsTab();
      default:
        return _buildTimetableTab();
    }
  }

  Widget _buildLoginRequiredView(String featureName) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF242629)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F5AF0).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.lock_person_rounded, color: Color(0xFF7F5AF0), size: 32),
                ),
                const SizedBox(height: 20),
                Text(
                  '$featureName 이용을 위해 로그인이 필요합니다',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                ),
                const SizedBox(height: 10),
                Text(
                  '선생님 전용 시간표 조회, 전자칠판 원격 연결(Cloud OTP), 수업 도구 기능은 Google 교사 계정 인증 후 사용하실 수 있습니다.\n\n(※ 급식 지도 및 식단표 조회는 비로그인으로도 즉시 이용 가능합니다.)',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _navigateToOAuth,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: Text('Google 교사 로그인 및 계정 연동', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7F5AF0),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _selectedTab = 3),
                    icon: const Icon(Icons.restaurant_rounded, size: 17, color: Color(0xFFFF8906)),
                    label: Text('급식 지도 화면으로 이동', style: GoogleFonts.notoSansKr(color: const Color(0xFFFF8906), fontWeight: FontWeight.w600, fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: const Color(0xFFFF8906).withOpacity(0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimetableTab() {
    final weekdays = ['월', '화', '수', '목', '금'];
    final schedule = _liveSchedule[_selectedWeekday] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF7F5AF0).withOpacity(0.2), const Color(0xFF16161A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF7F5AF0).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7F5AF0).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.calendar_today_rounded, color: Color(0xFF7F5AF0), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_now.month}월 ${_now.day}일 (${['월', '화', '수', '목', '금', '토', '일'][_now.weekday - 1]}) · ${_currentPeriod != null ? "$_currentPeriod교시 진행 중" : "수업 외 시간"}',
                            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$_schoolName 컴시간 실시간 시간표',
                            style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00F5D4), size: 20),
                      tooltip: '시간표 새로고침',
                      onPressed: _fetchLiveComciganTimetable,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Row(
                children: List.generate(5, (i) {
                  final dayNum = i + 1;
                  final isSel = _selectedWeekday == dayNum;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == 4 ? 0 : 6),
                      child: InkWell(
                        onTap: () => setState(() => _selectedWeekday = dayNum),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSel ? const Color(0xFF7F5AF0) : const Color(0xFF16161A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isSel ? const Color(0xFF7F5AF0) : const Color(0xFF242629)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            weekdays[i],
                            style: GoogleFonts.notoSansKr(
                              color: isSel ? Colors.white : const Color(0xFF94A1B2),
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 14),

              if (_isLoadingTimetable)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: Color(0xFF7F5AF0)),
                  ),
                )
              else if (schedule.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF242629)),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.event_busy_rounded, color: Color(0xFF94A1B2), size: 36),
                      const SizedBox(height: 12),
                      Text(
                        '${weekdays[_selectedWeekday - 1]}요일에 예정된 수업이 없습니다.',
                        style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 13),
                      ),
                    ],
                  ),
                )
              else
                ...schedule.map((item) {
                  final isCurrent = _currentPeriod?.toString() == item['period'];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isCurrent ? const Color(0xFF7F5AF0).withOpacity(0.12) : const Color(0xFF16161A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isCurrent ? const Color(0xFF7F5AF0) : const Color(0xFF242629), width: isCurrent ? 1.5 : 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isCurrent ? const Color(0xFF7F5AF0) : const Color(0xFF0F0E17),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${item['period']}',
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    item['subject'] ?? '',
                                    style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2CB67D).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item['class'] ?? '',
                                      style: const TextStyle(color: Color(0xFF2CB67D), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item['time']} · ${item['room']}',
                                style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  void _showAutoOtpDirectDialog() {
    final defaultRooms = [
      {'name': '1학년 1반', 'token': 'ydm_1_1'},
      {'name': '1학년 2반', 'token': 'ydm_1_2'},
      {'name': '2학년 1반', 'token': 'ydm_2_1'},
      {'name': '2학년 2반', 'token': 'ydm_2_2'},
      {'name': '3학년 1반', 'token': 'ydm_3_1'},
      {'name': '3학년 2반', 'token': 'ydm_3_2'},
      {'name': '음악실 1', 'token': 'ydm_music_1'},
      {'name': '음악실 4', 'token': 'ydm_music_4'},
      {'name': '미술실', 'token': 'ydm_art_1'},
      {'name': '체육관', 'token': 'ydm_gym_1'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF00F5D4), width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.cast_connected_rounded, color: Color(0xFF00F5D4), size: 22),
            const SizedBox(width: 8),
            Text('전자칠판 선택 및 OTP Secret 발송', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        content: SizedBox(
          width: 360,
          height: 380,
          child: ListView.separated(
            itemCount: defaultRooms.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
            itemBuilder: (c, idx) {
              final r = defaultRooms[idx];
              return ListTile(
                leading: const Icon(Icons.tv_rounded, color: Color(0xFF00F5D4)),
                title: Text(r['name']!, style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: Text('ID: ${r['token']}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                trailing: const Icon(Icons.send_rounded, color: Color(0xFF00F5D4), size: 18),
                onTap: () async {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('[${r['name']}] 으로 8자리 자동 OTP Secret 발송 중...')),
                  );
                  try {
                    final res = await http.post(
                      Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/auth/auto-otp'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'email': _googleEmail.isNotEmpty ? _googleEmail : 'teacher@boardest.bst',
                        'teacherName': _teacherName,
                        'fcmToken': r['token'],
                        'classId': r['token'],
                        'display': r['name'],
                      }),
                    );
                    if (res.statusCode == 200) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ [${r['name']}] 기기에 OTP Secret이 성공적으로 발송되었습니다!'),
                          backgroundColor: const Color(0xFF00F5D4),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('❌ 발송에 실패했습니다. 다시 시도해주세요.'), backgroundColor: Colors.redAccent),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('오류 발생: $e'), backgroundColor: Colors.redAccent),
                    );
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF242629)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.cloud_done_rounded, color: Color(0xFF00F5D4), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Google Drive Cloud 연동 중', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                          Text(_googleEmail.isNotEmpty ? _googleEmail : '계정 정보 로드 완료', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF7F5AF0).withOpacity(0.25), const Color(0xFF16161A)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF7F5AF0).withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Text('전자칠판 6자리 동적 보안 접속 코드', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    Text(
                      _currentOtp.length == 6 ? '${_currentOtp.substring(0, 3)} ${_currentOtp.substring(3, 6)}' : _currentOtp,
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF00F5D4),
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Cloud ID: $_cloudId (자동로그인 칠판용)', style: GoogleFonts.notoSansKr(color: const Color(0xFFFFD166), fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _remainingSeconds / 60.0,
                        backgroundColor: const Color(0xFF242629),
                        color: const Color(0xFF7F5AF0),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('남은 시간: $_remainingSeconds초 (매 분 위치 무작위 갱신)', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _showAutoOtpDirectDialog(),
                      icon: const Icon(Icons.send_rounded, size: 16, color: Colors.black),
                      label: Text('📡 전자칠판에 8자리 자동 OTP Secret 전송', style: GoogleFonts.notoSansKr(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00F5D4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _currentOtp));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('6자리 접속 코드 [$_currentOtp] 가 복사되었습니다.')));
                      },
                      icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF00F5D4)),
                      label: const Text('6자리 코드 복사', style: TextStyle(color: Color(0xFF00F5D4), fontSize: 12)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF00F5D4))),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF242629)),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _trustDeviceEnabled,
                      onChanged: (val) {
                        setState(() => _trustDeviceEnabled = val);
                        _syncTeacherCloudTokens();
                      },
                      title: Text('신뢰할 수 있는 기기 (Trust Device)', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('동일 교실 전자칠판 자동 연결 허용', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11)),
                      activeColor: const Color(0xFF7F5AF0),
                    ),
                    const Divider(height: 1, color: Color(0xFF242629)),
                    SwitchListTile(
                      value: _autoPtEnabled,
                      onChanged: (val) {
                        setState(() => _autoPtEnabled = val);
                        _syncTeacherCloudTokens();
                      },
                      title: Text('수업 자동 전환 (Auto Lesson Flow)', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('교시 변경 시 전자칠판 수업자료 자동 캐스팅', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11)),
                      activeColor: const Color(0xFF7F5AF0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF242629)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer_rounded, color: Color(0xFF7F5AF0), size: 20),
                        const SizedBox(width: 8),
                        Text('수업 집중 타이머', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(_toolTimerSeconds ~/ 60).toString().padLeft(2, '0')}:${(_toolTimerSeconds % 60).toString().padLeft(2, '0')}',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [1, 3, 5, 10].map((min) {
                        return OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _toolTimerSeconds = min * 60;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            side: const BorderSide(color: Color(0xFF7F5AF0)),
                          ),
                          child: Text('$min분', style: const TextStyle(color: Colors.white, fontSize: 11)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            if (_toolTimerRunning) {
                              _toolTimerInstance?.cancel();
                              setState(() => _toolTimerRunning = false);
                            } else {
                              if (_toolTimerSeconds <= 0) _toolTimerSeconds = 180;
                              setState(() => _toolTimerRunning = true);
                              _toolTimerInstance?.cancel();
                              _toolTimerInstance = Timer.periodic(const Duration(seconds: 1), (t) {
                                if (_toolTimerSeconds > 0) {
                                  setState(() => _toolTimerSeconds--);
                                } else {
                                  t.cancel();
                                  setState(() => _toolTimerRunning = false);
                                }
                              });
                            }
                          },
                          icon: Icon(_toolTimerRunning ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 16),
                          label: Text(_toolTimerRunning ? '일시정지' : '타이머 시작'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7F5AF0), foregroundColor: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            _toolTimerInstance?.cancel();
                            setState(() {
                              _toolTimerRunning = false;
                              _toolTimerSeconds = 0;
                            });
                          },
                          child: const Text('리셋', style: TextStyle(color: Color(0xFF94A1B2))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF242629)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.casino_rounded, color: Color(0xFF00F5D4), size: 20),
                        const SizedBox(width: 8),
                        Text('발표자 추첨 (1~$_pickerMax번)', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_pickedNumber != null)
                      Text('당첨: $_pickedNumber번!', style: GoogleFonts.notoSansKr(color: const Color(0xFF00F5D4), fontSize: 26, fontWeight: FontWeight.bold))
                    else
                      Text('버튼을 눌러 발표자를 뽑아보세요', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12)),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: () {
                        final n = Random().nextInt(_pickerMax) + 1;
                        setState(() {
                          _pickedNumber = n;
                          _pickedHistory.insert(0, n);
                        });
                      },
                      icon: const Icon(Icons.shuffle_rounded, size: 16),
                      label: const Text('랜덤 뽑기'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4), foregroundColor: Colors.black),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // Tab 3: 급식 & 쪽지 (Meal Guidance & Notes)
  // ═════════════════════════════════════════════════════════
  Widget _buildMealAndNotesTab() {
    // If configuring guest cafeteria, show the guest setup view
    if (_isConfiguringCafeteria) {
      return _buildGuestCafeteriaSetupView();
    }

    final targetCaf = _cafeteriaNum.replaceAll(RegExp(r'[^0-9]'), '');
    final onlineCafList = _onlineClassrooms.where((c) => c['isOnline'] == true).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 1~9 급식실 빠른 전환 버튼 바
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF242629)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.room_service_rounded, color: Color(0xFFFF8906), size: 18),
                        const SizedBox(width: 8),
                        Text('급식실 선택 (1~9급식실)', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setState(() => _isConfiguringCafeteria = true),
                          icon: const Icon(Icons.tune_rounded, size: 13, color: Color(0xFFFF8906)),
                          label: const Text('위치/교사 재설정', style: TextStyle(color: Color(0xFFFF8906), fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List.generate(9, (idx) {
                        final cafNumInt = idx + 1;
                        final cafNumStr = '$cafNumInt';
                        final isSelected = (targetCaf.isEmpty ? '1' : targetCaf) == cafNumStr;
                        final onlineCount = _cafeteriaOnlineCounts[cafNumInt] ?? 0;

                        return InkWell(
                          onTap: () async {
                            setState(() {
                              _cafeteriaNum = cafNumStr;
                            });
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('bst_cafeteria_num', cafNumStr);
                            _fetchOnlineClassrooms();
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFFF8906)
                                  : (onlineCount > 0 ? const Color(0xFF2CB67D).withOpacity(0.12) : const Color(0xFF0F0E17)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFFF8906)
                                    : (onlineCount > 0 ? const Color(0xFF2CB67D).withOpacity(0.6) : const Color(0xFF242629)),
                                width: isSelected || onlineCount > 0 ? 1.2 : 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (onlineCount > 0 && !isSelected) ...[
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF2CB67D)),
                                  ),
                                ],
                                Text(
                                  '$cafNumInt급식실',
                                  style: GoogleFonts.notoSansKr(
                                    color: isSelected ? Colors.black : (onlineCount > 0 ? const Color(0xFF2CB67D) : Colors.white70),
                                    fontSize: 11.5,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                                if (onlineCount > 0) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.black.withOpacity(0.15) : const Color(0xFF2CB67D),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$onlineCount',
                                      style: GoogleFonts.notoSansKr(
                                        color: isSelected ? Colors.black : Colors.black,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '현재 접속: $_schoolName · ${targetCaf.isEmpty ? "1" : targetCaf}급식실',
                          style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          '당번: $_teacherName 선생님',
                          style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 2. 🟢 실시간 온라인 학급 현황 (선택된 급식실만 필터링)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: onlineCafList.isNotEmpty ? const Color(0xFF2CB67D).withOpacity(0.4) : const Color(0xFF242629),
                    width: onlineCafList.isNotEmpty ? 1.2 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: onlineCafList.isNotEmpty ? const Color(0xFF2CB67D) : const Color(0xFF72757E),
                            boxShadow: onlineCafList.isNotEmpty
                                ? [BoxShadow(color: const Color(0xFF2CB67D).withOpacity(0.6), blurRadius: 6, spreadRadius: 1)]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '실시간 접속 학급 (${targetCaf.isEmpty ? "1" : targetCaf}급식실 전용)',
                          style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: _fetchOnlineClassrooms,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 14,
                                  color: _isLoadingOnlineClassrooms ? const Color(0xFF7F5AF0) : const Color(0xFF94A1B2),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '새로고침',
                                  style: TextStyle(
                                    color: _isLoadingOnlineClassrooms ? const Color(0xFF7F5AF0) : const Color(0xFF94A1B2),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (onlineCafList.isEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0E17),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF242629)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.tv_off_rounded, color: Color(0xFF72757E), size: 24),
                            const SizedBox(height: 8),
                            Text(
                              '현재 ${targetCaf.isEmpty ? "1" : targetCaf}급식실로 설정된 온라인 접속 전자칠판이 없습니다.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '상단 급식실 번호 버튼을 눌러 다른 급식실의 접속 현황을 확인해보세요.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansKr(color: const Color(0xFF72757E), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Column(
                        children: onlineCafList.map((c) {
                          final grade = c['grade'] as int;
                          final cls = c['classNum'] as int;
                          final nickname = c['classNickname'] as String;
                          final isCalled = c['isCalled'] as bool;
                          final docId = c['docId']?.toString();
                          final schoolCode = c['schoolCode']?.toString();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F0E17),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCalled ? const Color(0xFFFF8906).withOpacity(0.6) : const Color(0xFF2CB67D).withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF2CB67D),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nickname,
                                        style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      Text(
                                        isCalled ? '🔔 급식실 이동 호출 중' : '🟢 온라인 대기 중',
                                        style: GoogleFonts.notoSansKr(
                                          color: isCalled ? const Color(0xFFFF8906) : const Color(0xFF2CB67D),
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isCalled)
                                  ElevatedButton.icon(
                                    onPressed: _isCallingMeal ? null : () => _cancelClassMeal(grade, cls, targetDocId: docId),
                                    icon: const Icon(Icons.close_rounded, size: 13),
                                    label: const Text('호출 취소', style: TextStyle(fontSize: 11)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF8906).withOpacity(0.2),
                                      foregroundColor: const Color(0xFFFF8906),
                                      side: const BorderSide(color: Color(0xFFFF8906), width: 0.8),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      elevation: 0,
                                    ),
                                  )
                                else
                                  ElevatedButton.icon(
                                    onPressed: _isCallingMeal ? null : () => _callClassMeal(grade, cls, '급식실 이동', targetDocId: docId, targetSchoolCode: schoolCode),
                                    icon: const Icon(Icons.notifications_active_rounded, size: 13),
                                    label: const Text('급식 호출', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF8906),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      elevation: 0,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: _isCallingMeal ? null : _callAllOnlineClassrooms,
                          icon: const Icon(Icons.campaign_rounded, size: 16),
                          label: Text(
                            '같은 급식실 온라인 학급 전체 호출 (${onlineCafList.length}개 학급)',
                            style: GoogleFonts.notoSansKr(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7F5AF0),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                    if (_mealCallStatus != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2CB67D).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2CB67D).withOpacity(0.3)),
                        ),
                        child: Text(
                          _mealCallStatus!,
                          style: GoogleFonts.notoSansKr(color: const Color(0xFF2CB67D), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 3. Meal Menu Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFFFF8906).withOpacity(0.15), const Color(0xFF16161A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFF8906).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.restaurant_menu_rounded, color: Color(0xFFFF8906), size: 20),
                        const SizedBox(width: 8),
                        Text('$_mealDateLabel ($_schoolName)', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_mealMenu.isEmpty)
                      const Text('급식 메뉴를 불러오는 중입니다...', style: TextStyle(color: Color(0xFF94A1B2), fontSize: 12))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _mealMenu.map((m) {
                          return Chip(
                            backgroundColor: const Color(0xFF0F0E17),
                            label: Text(m, style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 4. Notes / Messaging Section
              _buildNoteSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Guest Cafeteria Setup View ───
  Widget _buildGuestCafeteriaSetupView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFF8906).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF8906).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.room_service_rounded, color: Color(0xFFFF8906), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('급식 지도 비로그인 설정', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('로그인 없이 급식실 위치 및 당번 교사를 설정합니다.', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // School Name / ID Input
                Text('학교명 / 학교 ID', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: _guestSchoolController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '예: 양동중학교 또는 YDM',
                    hintStyle: const TextStyle(color: Color(0xFF72757E), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF0F0E17),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF242629))),
                  ),
                ),
                const SizedBox(height: 14),

                // Teacher Name Input
                Text('당번 선생님 성함', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: _guestTeacherController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '예: 홍길동',
                    hintStyle: const TextStyle(color: Color(0xFF72757E), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF0F0E17),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF242629))),
                  ),
                ),
                const SizedBox(height: 14),

                // Cafeteria Num Input & Quick Buttons (1~9)
                Text('급식실 번호 (1~9급식실)', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(9, (idx) {
                    final n = idx + 1;
                    final isSel = _guestCafeteriaController.text.trim() == '$n';
                    return InkWell(
                      onTap: () => setState(() => _guestCafeteriaController.text = '$n'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSel ? const Color(0xFFFF8906) : const Color(0xFF0F0E17),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSel ? const Color(0xFFFF8906) : const Color(0xFF242629)),
                        ),
                        child: Text(
                          '$n급식실',
                          style: TextStyle(
                            color: isSel ? Colors.black : Colors.white70,
                            fontSize: 11.5,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final school = _guestSchoolController.text.trim();
                      final teacher = _guestTeacherController.text.trim();
                      final cafeteria = _guestCafeteriaController.text.trim();

                      if (school.isNotEmpty) {
                        _schoolName = school;
                        _schoolId = school;
                        _schoolCode = school;
                      }
                      if (teacher.isNotEmpty) _teacherName = teacher;
                      if (cafeteria.isNotEmpty) {
                        _cafeteriaNum = cafeteria.replaceAll(RegExp(r'[^0-9]'), '');
                        if (_cafeteriaNum.isEmpty) _cafeteriaNum = '1';
                      }

                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('bst_school_name', _schoolName);
                      await prefs.setString('bst_school_id', _schoolId);
                      await prefs.setString('bst_teacher_name', _teacherName);
                      await prefs.setString('bst_cafeteria_num', _cafeteriaNum);

                      setState(() {
                        _isConfiguringCafeteria = false;
                      });

                      _fetchOnlineClassrooms();
                    },
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text('급식실 진입 및 호출 시작', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8906),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Note Section (With Login Guard Overlay) ───
  Widget _buildNoteSection() {
    final noteContent = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF242629)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _onlineClassrooms.isNotEmpty ? const Color(0xFF00F5D4) : const Color(0xFF72757E),
                  boxShadow: _onlineClassrooms.isNotEmpty
                      ? [BoxShadow(color: const Color(0xFF00F5D4).withOpacity(0.6), blurRadius: 6, spreadRadius: 1)]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text('교내 긴급 쪽지 발송', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
              const Spacer(),
              Text(
                '접속 교실: ${_onlineClassrooms.length}개',
                style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_onlineClassrooms.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0E17),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF242629)),
              ),
              child: const Text(
                '📡 현재 접속 중인 전자칠판이 없습니다.\n(교실 칠판 앱이 켜지면 자동으로 목록에 나타납니다)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A1B2), fontSize: 11.5, height: 1.4),
              ),
            )
          else ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // 전체 온라인 교실 선택 칩
                ChoiceChip(
                  selected: _noteSelectAllOnline,
                  selectedColor: const Color(0xFF7F5AF0),
                  backgroundColor: const Color(0xFF0F0E17),
                  label: Text(
                    '전체 온라인 교실 (${_onlineClassrooms.length}개)',
                    style: TextStyle(
                      color: _noteSelectAllOnline ? Colors.white : Colors.white70,
                      fontWeight: _noteSelectAllOnline ? FontWeight.bold : FontWeight.normal,
                      fontSize: 11.5,
                    ),
                  ),
                  onSelected: (val) {
                    setState(() {
                      _noteSelectAllOnline = true;
                      _noteSelectedDocIds.clear();
                      _noteSelectedDocIds.addAll(_onlineClassrooms.map((c) => c['docId'] as String));
                    });
                  },
                ),
                // 개별 온라인 교실 칩 목록
                ..._onlineClassrooms.map((c) {
                  final docId = c['docId'] as String;
                  final isSel = !_noteSelectAllOnline && _noteSelectedDocIds.contains(docId);
                  return ChoiceChip(
                    selected: isSel,
                    selectedColor: const Color(0xFF00F5D4),
                    backgroundColor: const Color(0xFF0F0E17),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00F5D4)),
                        ),
                        Text(
                          (c['nickname'] ?? c['classNickname'] ?? '') as String,
                          style: TextStyle(
                            color: isSel ? Colors.black : Colors.white70,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    onSelected: (val) {
                      setState(() {
                        _noteSelectAllOnline = false;
                        if (val) {
                          _noteSelectedDocIds.clear();
                          _noteSelectedDocIds.add(docId);
                        } else {
                          _noteSelectedDocIds.remove(docId);
                        }
                      });
                    },
                  );
                }),
              ],
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _noteMsgController,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: '교실 전자칠판으로 보낼 쪽지 내용을 입력하세요...',
              hintStyle: const TextStyle(color: Color(0xFF72757E), fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF0F0E17),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF242629))),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSendingNote ? null : _sendNote,
              icon: const Icon(Icons.send_rounded, size: 15),
              label: Text(_isSendingNote ? '전송 중...' : '쪽지 즉시 전송', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7F5AF0), foregroundColor: Colors.white),
            ),
          ),
          if (_noteStatusMsg != null) ...[
            const SizedBox(height: 8),
            Text(_noteStatusMsg!, style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 11.5)),
          ],
        ],
      ),
    );

    if (_isGoogleLoggedIn) {
      return noteContent;
    }

    // Unauthenticated: Wrap in grayed-out disabled container with Centered Overlay!
    return Stack(
      children: [
        Opacity(
          opacity: 0.25,
          child: IgnorePointer(child: noteContent),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F0E17).withOpacity(0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF242629)),
            ),
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F5AF0).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded, color: Color(0xFF7F5AF0), size: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  '로그인 후 사용 가능',
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '교실 전자칠판 쪽지 발송은 교사 계정 인증 후 지원됩니다.',
                  style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _navigateToOAuth,
                  icon: const Icon(Icons.login_rounded, size: 14),
                  label: const Text('Google 로그인', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7F5AF0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════
  // Tab 4: 설정 (Settings & Account)
  // ═════════════════════════════════════════════════════════
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF242629)),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFF7F5AF0).withOpacity(0.2),
                      child: Text(
                        _teacherName.isNotEmpty ? _teacherName.substring(0, min(1, _teacherName.length)) : '교',
                        style: const TextStyle(color: Color(0xFF7F5AF0), fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('$_teacherName 선생님', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(_googleEmail.isNotEmpty ? _googleEmail : '비로그인 게스트 모드', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        launchUrl(Uri.parse('https://boardest-teacher-oauth.web.app?re-login&web-lite'), webOnlyWindowName: '_self');
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.black),
                      label: const Text('⚡ Google 토큰 최신화 / 재인증', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00F5D4),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse('https://boardest-teacher-oauth.web.app/edit?web-lite'), webOnlyWindowName: '_self'),
                      icon: const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF2EC4B6)),
                      label: const Text('✏️ 계정 설정 변경 (포털)', style: TextStyle(color: Color(0xFF2EC4B6), fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF2EC4B6)),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_isGoogleLoggedIn)
                      OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFFEF4565)),
                        label: const Text('🚪 로그아웃', style: TextStyle(color: Color(0xFFEF4565), fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFEF4565)),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

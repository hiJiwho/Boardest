import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../models/app_settings.dart';
import '../models/school.dart';
import '../config/app_config.dart';
import '../services/storage_service.dart';
import '../services/comcigan_service.dart';
import '../services/cloud_drive_service.dart';
import '../services/totp_service.dart';
import 'teacher_view.dart';

/// Boardest Teacher 전용 교사 로그인 & 프로필 연동 OOBE
class TeacherSetupWizardView extends StatefulWidget {
  const TeacherSetupWizardView({super.key});

  @override
  State<TeacherSetupWizardView> createState() => _TeacherSetupWizardViewState();
}

class _TeacherSetupWizardViewState extends State<TeacherSetupWizardView> {
  final StorageService _storage = StorageService();
  final ComciganService _comcigan = ComciganService();

  bool _isLoading = false;
  String? _loadingStatus;
  String? _errorMessage;

  // 교사 로그인 상태
  bool _isLoggedIn = false;
  String _userEmail = '';
  String _userName = '';

  // 미등록 교사용 프로필 입력 필드
  bool _needsRegistration = false;
  final TextEditingController _schoolSearchController = TextEditingController();
  final TextEditingController _teacherNameController = TextEditingController();
  final TextEditingController _teacherIdController = TextEditingController();
  
  School? _selectedSchool;
  List<School> _searchResults = [];
  bool _isSearchingSchool = false;
  List<String> _teacherList = [];
  bool _isLoadingTeachers = false;

  bool _isHomeroom = true;
  int _selectedGrade = 1;
  int _selectedClass = 1;
  String _selectedCafeteria = '1';

  Timer? _authPollTimer;

  @override
  void initState() {
    super.initState();
    _checkWebOAuthCallback();
    _checkCurrentSession();

    CloudDriveService.instance.onSessionReady = () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const TeacherView()),
        );
      }
    };

    _authPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && CloudDriveService.instance.isLoggedIn && !_isLoggedIn) {
        _onLoggedInSuccess(
          CloudDriveService.instance.userEmail ?? '',
          CloudDriveService.instance.userName ?? '',
        );
      }
    });
  }

  @override
  void dispose() {
    _authPollTimer?.cancel();
    _schoolSearchController.dispose();
    _teacherNameController.dispose();
    _teacherIdController.dispose();
    super.dispose();
  }

  Future<void> _checkCurrentSession() async {
    if (CloudDriveService.instance.isLoggedIn) {
      final email = CloudDriveService.instance.userEmail ?? '';
      final name = CloudDriveService.instance.userName ?? '';
      if (email.isNotEmpty || name.isNotEmpty) {
        _onLoggedInSuccess(email, name);
      }
    }
  }

  /// Web OAuth Redirect Callback 처리
  Future<void> _checkWebOAuthCallback() async {
    if (!kIsWeb) return;
    try {
      final currentUri = Uri.base;
      final params = Map<String, String>.from(currentUri.queryParameters);
      if (currentUri.fragment.isNotEmpty) {
        String frag = currentUri.fragment;
        if (frag.contains('?')) {
          frag = frag.substring(frag.indexOf('?') + 1);
        }
        final fragParams = Uri.splitQueryString(frag);
        params.addAll(fragParams);
      }

      final isAuthSuccess = params['auth'] == 'success';
      final token = params['token'] ?? params['access_token'];
      String email = params['email'] ?? '';
      String name = params['teacherName'] ?? '';
      final teacherId = params['teacherId'] ?? '';
      final schoolId = params['schoolId'] ?? 'YDM';
      final schoolCode = params['schoolCode'] ?? params['schoolId'] ?? '44134';
      String schoolName = params['schoolName'] ?? '';
      final grade = int.tryParse(params['grade'] ?? '1') ?? 1;
      final classNum = int.tryParse(params['classNum'] ?? '1') ?? 1;
      final cafeteria = params['cafeteriaNum'] ?? '1';

      if (isAuthSuccess || (token != null && token.isNotEmpty) || schoolName.isNotEmpty) {
        // 데모 모드 및 일반 모드 호환: 데모 요청 시 가상 데모 계정 프로필 자동 부여
        final isDemoReq = AppConfig.isDemoMode ||
            params.containsKey('Demo') ||
            params.containsKey('demo') ||
            Uri.base.queryParameters.containsKey('Demo') ||
            Uri.base.queryParameters.containsKey('demo') ||
            email.toLowerCase().contains('demo') ||
            name.toLowerCase().contains('데모') ||
            schoolId.toLowerCase().contains('demo');

        if (isDemoReq && schoolName.isEmpty) {
          schoolName = 'Boardest 데모 중학교';
        }

        setState(() {
          _isLoading = true;
          _loadingStatus = '선생님 프로필 및 세션을 연동하고 있습니다...';
        });

        if (token != null && token.isNotEmpty) {
          if (email.isEmpty || name.isEmpty) {
            try {
              final profileRes = await http.get(
                Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
                headers: {'Authorization': 'Bearer $token'},
              );
              if (profileRes.statusCode == 200) {
                final profile = jsonDecode(profileRes.body);
                if (email.isEmpty) email = profile['email'] as String? ?? '';
                if (name.isEmpty) name = profile['name'] as String? ?? '';
              }
            } catch (_) {}
          }

          await CloudDriveService.instance.setSession(
            accessToken: token,
            bstCldToken: token,
            email: email,
            name: name,
            school: schoolName,
          );
        }

        if (schoolName.isNotEmpty && (name.isNotEmpty || teacherId.isNotEmpty)) {
          final effectiveName = name.isNotEmpty ? name : teacherId;
          final effectiveId = teacherId.isNotEmpty ? teacherId : effectiveName;
          int parsedCode = int.tryParse(schoolCode) ?? int.tryParse(schoolId) ?? 44134;
          final school = School(
            id: parsedCode,
            code: parsedCode,
            name: schoolName,
            region: '서울',
          );
          final settings = AppSettings(
            selectedSchool: school,
            schoolId: schoolId,
            selectedGrade: grade,
            selectedClass: classNum,
            selectedTeacher: effectiveName,
            selectedTeacherId: effectiveId,
            selectedTeacherName: effectiveName,
            cafeteriaNum: cafeteria,
            isSetupComplete: true,
          );
          await _storage.saveSettings(settings);

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const TeacherView()),
            );
          }
          return;
        }

        await _onLoggedInSuccess(email, name);
      }
    } catch (e) {
      debugPrint('[TeacherSetupWizard] Web OAuth callback error: $e');
    }
  }

  /// 구글 로그인 성공 후 Firestore 프로필 자동 조회
  Future<void> _onLoggedInSuccess(String email, String name) async {
    final isDemoReq = AppConfig.isDemoMode ||
        Uri.base.queryParameters.containsKey('Demo') ||
        Uri.base.queryParameters.containsKey('demo') ||
        email.toLowerCase().contains('demo') ||
        name.toLowerCase().contains('데모');

    setState(() {
      _isLoggedIn = true;
      _userEmail = email;
      _userName = name;
      _teacherNameController.text = name;
      if (name.length >= 2) {
        _teacherIdController.text = name.substring(0, 2);
      }
      _isLoading = true;
      _loadingStatus = '선생님의 등록 정보를 확인하고 있습니다...';
      _errorMessage = null;
    });

    try {
      Map<String, dynamic>? matchedProfile;

      // 1. Direct doc lookup by sanitized email
      if (email.isNotEmpty) {
        try {
          final docId = email.replaceAll('.', '_').replaceAll('@', '_').replaceAll('+', '_');
          final url = Uri.parse(
            'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/teacher_profiles/$docId?key=${AppConfig.firebaseApiKey}',
          );
          final res = await http.get(url).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final fields = data['fields'] as Map<String, dynamic>?;
            if (fields != null) {
              final Map<String, dynamic> item = {};
              fields.forEach((k, v) {
                if (v is Map) {
                  item[k] = v['stringValue'] ?? v['integerValue'] ?? v['booleanValue'] ?? v['doubleValue'];
                }
              });
              matchedProfile = item;
            }
          }
        } catch (_) {}
      }

      // 2. Fallback to list search if direct lookup missed
      if (matchedProfile == null) {
        final profiles = await _fetchTeacherProfiles();
        for (final p in profiles) {
          final pEmail = p['email']?.toString().toLowerCase() ?? '';
          final pName = p['teacherName']?.toString() ?? '';
          if ((email.isNotEmpty && pEmail == email.toLowerCase()) ||
              (name.isNotEmpty && pName == name)) {
            matchedProfile = p;
            break;
          }
        }
      }

      if (matchedProfile == null && isDemoReq) {
        matchedProfile = {
          'schoolId': '44134',
          'schoolCode': '44134',
          'schoolName': 'Boardest 데모 중학교',
          'teacherName': name.isNotEmpty ? name : '데모교사',
          'teacherId': '1',
          'grade': 1,
          'classNum': 1,
          'cafeteriaNum': '1',
          'isDemoTeacher': true,
        };
      }

      if (matchedProfile != null) {
        // 교사 정보 발견 -> AppSettings 적용 후 바로 앱 시작!
        setState(() {
          _loadingStatus = '🎉 [${matchedProfile!['teacherName']}] 선생님 정보 연동 완료! 앱을 시작합니다...';
        });

        await _applyProfileAndLaunch(matchedProfile);
      } else {
        // 등록된 정보 없음 -> OAuth 정보 기입 화면 노출
        setState(() {
          _isLoading = false;
          _needsRegistration = true;
        });
      }
    } catch (e) {
      debugPrint('[TeacherSetupWizard] Profile fetch error: $e');
      setState(() {
        _isLoading = false;
        _needsRegistration = true;
      });
    }
  }

  /// Firestore teacher_profiles 컬렉션 조회
  Future<List<Map<String, dynamic>>> _fetchTeacherProfiles() async {
    final List<Map<String, dynamic>> list = [];
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/teacher_profiles?key=${AppConfig.firebaseApiKey}',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['documents'] as List?;
        if (docs != null) {
          for (final d in docs) {
            final fields = d['fields'] as Map<String, dynamic>?;
            if (fields != null) {
              final Map<String, dynamic> item = {};
              fields.forEach((k, v) {
                if (v is Map) {
                  item[k] = v['stringValue'] ?? v['integerValue'] ?? v['booleanValue'] ?? v['doubleValue'];
                }
              });
              list.add(item);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[TeacherSetupWizard] _fetchTeacherProfiles error: $e');
    }
    return list;
  }

  /// 프로필 적용 후 메인 교사 화면으로 진입
  Future<void> _applyProfileAndLaunch(Map<String, dynamic> profile) async {
    final schoolName = profile['schoolName']?.toString() ?? '보데스트 중학교';
    final schoolId = profile['schoolId']?.toString() ?? 'bst';
    final teacherName = profile['teacherName']?.toString() ?? (_userName.isNotEmpty ? _userName : '김보데');
    final teacherId = profile['teacherId']?.toString() ?? (_userName.length >= 2 ? _userName.substring(0, 2) : '김보');
    final isHomeroom = profile['isHomeroom'] == true || profile['isHomeroom'] == 'true';
    final grade = int.tryParse(profile['grade']?.toString() ?? '') ?? 1;
    final classNum = int.tryParse(profile['classNum']?.toString() ?? '') ?? 1;
    final cafeteria = profile['cafeteriaNum']?.toString() ?? '1';

    final bool isDemoTeacher = profile['isDemoTeacher'] == true ||
        schoolName.toLowerCase().contains('demo') ||
        schoolName.contains('데모') ||
        schoolId.toLowerCase().contains('demo') ||
        teacherName.toLowerCase().contains('demo') ||
        teacherName.contains('데모');

    final effectiveSchoolName = isDemoTeacher ? 'Boardest 데모 중학교' : schoolName;
    final effectiveSchoolId = isDemoTeacher ? 'Demo' : schoolId;
    final rawCode = profile['schoolCode']?.toString() ?? profile['schoolId']?.toString() ?? '';
    final int effectiveCode = isDemoTeacher ? 11111 : (int.tryParse(rawCode) ?? 44134);

    School school = School(id: effectiveCode, code: effectiveCode, name: effectiveSchoolName, region: '서울');
    if (!isDemoTeacher) {
      try {
        final schools = await _comcigan.searchSchool(schoolName);
        if (schools.isNotEmpty) {
          school = schools.first;
        }
      } catch (_) {}
    }

    final settings = AppSettings(
      selectedSchool: school,
      selectedTeacher: teacherName,
      selectedTeacherId: teacherId,
      selectedGrade: grade,
      selectedClass: classNum,
      cafeteriaNum: cafeteria,
      isSetupComplete: true,
      schoolId: effectiveSchoolId,
    );

    await _storage.saveSettings(settings);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TeacherView()),
      );
    }
  }

  /// 데모 교사 계정 원클릭 로그인 (01 김윤리 / 02 이도형 선택 지원)
  Future<void> _loginAsDemoTeacher([String code = '01']) async {
    final is02 = code == '02';
    final name = is02 ? '이도형' : '김윤리';
    final subject = is02 ? '수학' : '도덕';
    final email = '$code@boardest-teacher-demo.753210.xyz';
    final shortId = is02 ? '12' : '11';
    final grade = 1;
    final classNum = is02 ? 2 : 1;

    setState(() {
      _isLoading = true;
      _loadingStatus = '$code $name 선생님($subject) 계정으로 로그인하고 있습니다...';
      _errorMessage = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final demoToken = 'demo_token_teacher_$shortId';
    final demoTotpSecret = TotpService.generateDeterministicSecret(email);

    await prefs.setString('bst_google_user_email', email);
    await prefs.setString('bst_user_email', email);
    await prefs.setString('bst_google_user_name', name);
    await prefs.setString('bst_user_name', name);
    await prefs.setString('bst_cld_access_token', demoToken);
    await prefs.setString('bst_google_access_token', demoToken);
    await prefs.setString('bst_school_name', '데모중학교');
    await prefs.setString('bst_school_id', 'Demo');
    await prefs.setString('bst_totp_secret_key', demoTotpSecret);
    await prefs.setString('bst_totp_secret', demoTotpSecret);
    await prefs.setString('bst_teacher_short_id', shortId);

    await CloudDriveService.instance.setSession(
      accessToken: demoToken,
      bstCldToken: demoToken,
      refreshToken: '',
      email: email,
      name: name,
      school: '데모중학교',
      totpSecret: demoTotpSecret,
      shortId: shortId,
    );

    final school = School(
      id: 11111,
      code: 11111,
      name: '데모중학교',
      region: '서울',
    );

    final settings = AppSettings(
      selectedSchool: school,
      schoolId: 'Demo',
      selectedGrade: grade,
      selectedClass: classNum,
      selectedTeacher: name,
      selectedTeacherId: name,
      selectedTeacherName: name,
      cafeteriaNum: '1',
      isHomeroom: true,
      isSetupComplete: true,
    );

    await _storage.saveSettings(settings);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TeacherView()),
      );
    }
  }

  /// 구글 로그인 버튼 클릭
  Future<void> _startGoogleLogin() async {
    final isDemo = AppConfig.isDemoMode ||
        Uri.base.queryParameters.containsKey('Demo') ||
        Uri.base.queryParameters.containsKey('demo');
    final demoParam = isDemo ? '&Demo=yes' : '';

    setState(() {
      _isLoading = true;
      _loadingStatus = '구글 로그인 브라우저를 실행합니다...';
      _errorMessage = null;
    });

    if (kIsWeb) {
      // Web: OAuth 포털 리다이렉션 (target=web&return_url=...)
      final returnUrl = Uri.encodeComponent(Uri.base.toString());
      final portalUrl = 'https://boardest-teacher-oauth.web.app/?target=web&return_url=$returnUrl$demoParam';
      try {
        await launchUrl(Uri.parse(portalUrl), webOnlyWindowName: '_self');
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorMessage = '브라우저 실행 실패: $e';
        });
      }
    } else {
      // Windows / Desktop: 외부 브라우저(Chrome)로 OAuth 포털 실행 (target=win&port=...) -> 127.0.0.1 루프백 수신
      final port = CloudDriveService.instance.activePort;
      final url = 'https://boardest-teacher-oauth.web.app/?target=win&port=$port$demoParam';
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorMessage = '로그인 창 실행 오류: $e';
        });
      }
    }
  }

  /// 학교 검색
  Future<void> _searchSchool(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearchingSchool = true;
    });
    try {
      final results = await _comcigan.searchSchool(query.trim());
      setState(() {
        _searchResults = results;
        _isSearchingSchool = false;
      });
    } catch (e) {
      setState(() {
        _isSearchingSchool = false;
        _errorMessage = '학교 검색 실패: $e';
      });
    }
  }

  /// 학교 선택 시 컴시간 교사 목록 조회
  Future<void> _onSelectSchool(School school) async {
    setState(() {
      _selectedSchool = school;
      _schoolSearchController.text = school.name;
      _searchResults = [];
      _isLoadingTeachers = true;
    });

    try {
      final teachers = await _comcigan.getTeachers(school.code);
      setState(() {
        _teacherList = teachers;
        _isLoadingTeachers = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingTeachers = false;
      });
    }
  }

  /// 신규 교사 프로필 등록 및 앱 시작
  Future<void> _saveNewProfileAndLaunch() async {
    if (_selectedSchool == null) {
      setState(() => _errorMessage = '학교를 선택해 주세요.');
      return;
    }
    final tName = _teacherNameController.text.trim();
    if (tName.isEmpty) {
      setState(() => _errorMessage = '교사 성함을 입력해 주세요.');
      return;
    }
    final tId = _teacherIdController.text.trim();
    if (tId.isEmpty) {
      setState(() => _errorMessage = '컴시간 교사 약칭 ID를 입력해 주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingStatus = '교사 프로필을 등록하고 저장하는 중...';
      _errorMessage = null;
    });

    try {
      final profilePayload = {
        'email': {'stringValue': _userEmail},
        'teacherName': {'stringValue': tName},
        'teacherId': {'stringValue': tId},
        'schoolName': {'stringValue': _selectedSchool!.name},
        'schoolId': {'stringValue': 'school_${_selectedSchool!.code}'},
        'isHomeroom': {'booleanValue': _isHomeroom},
        'grade': {'integerValue': _selectedGrade},
        'classNum': {'integerValue': _selectedClass},
        'cafeteriaNum': {'stringValue': _selectedCafeteria},
        'updatedAt': {'stringValue': DateTime.now().toIso8601String()},
      };

      // Firestore teacher_profiles 문서 저장
      final docId = _userEmail.isNotEmpty ? _userEmail.replaceAll(RegExp(r'[.@+]'), '_') : 'teacher_${tName}_${tId}';
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/teacher_profiles/$docId?key=${AppConfig.firebaseApiKey}',
      );

      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': profilePayload}),
      );

      // AppSettings 로컬 저장 후 앱 시작
      final settings = AppSettings(
        selectedSchool: _selectedSchool,
        selectedTeacher: tName,
        selectedTeacherId: tId,
        selectedGrade: _selectedGrade,
        selectedClass: _selectedClass,
        cafeteriaNum: _selectedCafeteria,
        isSetupComplete: true,
        schoolId: 'school_${_selectedSchool!.code}',
      );

      await _storage.saveSettings(settings);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const TeacherView()),
        );
      }
    } catch (e) {
      debugPrint('[TeacherSetupWizard] Save profile error: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = '프로필 등록 중 오류가 발생했습니다: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Column(
        children: [
          if (!kIsWeb && Platform.isWindows)
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: const Color(0xFF16161A),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: (_) => windowManager.startDragging(),
                      child: Row(
                        children: [
                          const Icon(Icons.school_rounded, color: Color(0xFF7F5AF0), size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Boardest Teacher — 시작 설정',
                            style: GoogleFonts.outfit(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, color: Colors.white70, size: 16),
                    onPressed: () => windowManager.minimize(),
                    tooltip: '최소화',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                    onPressed: () => exit(0),
                    tooltip: '닫기',
                  ),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 540),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF242629)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                // 1. 헤더 (로고 및 타이틀)
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7F5AF0).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF7F5AF0).withValues(alpha: 0.4)),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Color(0xFF7F5AF0),
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Boardest Teacher',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '선생님을 위한 맞춤형 스마트 전자칠판',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    color: const Color(0xFF94A1B2),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 28),

                // 2. 상태 메시지 / 에러 메시지
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8BA7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFF8BA7)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFFF8BA7), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // 3. 로딩 상태
                if (_isLoading) ...[
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0E17),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2EC4B6).withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(color: Color(0xFF2EC4B6)),
                        const SizedBox(height: 16),
                        Text(
                          _loadingStatus ?? '잠시만 기다려 주세요...',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ] else if (!_isLoggedIn || !_needsRegistration) ...[
                  // 4. 구글 로그인 카드 (STEP 1)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0E17),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF7F5AF0).withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(AppConfig.isDemoMode ? Icons.science_rounded : Icons.lock_rounded, color: AppConfig.isDemoMode ? const Color(0xFF00F5D4) : const Color(0xFF7F5AF0), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              AppConfig.isDemoMode ? 'Boardest Teacher (데모 모드)' : '교사 구글 계정 인증',
                              style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppConfig.isDemoMode
                              ? '가상 데모 환경입니다. 데모 교사 계정으로 즉시 체험하거나,\nGoogle Drive 연동 시연을 위해 Google 계정으로 로그인할 수 있습니다.'
                              : 'Google 계정으로 로그인하면 등록된 시간표와 교안이 자동으로 동기화됩니다.',
                          style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12.5),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          onPressed: _startGoogleLogin,
                          icon: const Icon(Icons.account_circle_rounded, color: Colors.black87),
                          label: Text(
                            AppConfig.isDemoMode ? 'Google 계정으로 로그인 (Drive 연동 시연)' : 'Google 계정으로 로그인',
                            style: GoogleFonts.notoSansKr(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        if (AppConfig.isDemoMode) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _loginAsDemoTeacher('01'),
                                  icon: const Icon(Icons.school_rounded, color: Colors.black87, size: 18),
                                  label: Text(
                                    '01 김윤리 (도덕 1-1)',
                                    style: GoogleFonts.notoSansKr(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00F5D4),
                                    foregroundColor: Colors.black87,
                                    minimumSize: const Size(0, 48),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _loginAsDemoTeacher('02'),
                                  icon: const Icon(Icons.calculate_rounded, color: Colors.white, size: 18),
                                  label: Text(
                                    '02 이도형 (수학 1-2)',
                                    style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B82F6),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 48),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri.parse(kIsWeb ? 'https://boardest-teacher-oauth.web.app?web' : 'https://boardest-teacher-oauth.web.app?win')),
                          icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF2EC4B6), size: 16),
                          label: Text(
                            '교사 OAuth 등록 포털 바로가기',
                            style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontSize: 12.5),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF2EC4B6)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_needsRegistration) ...[
                  // 5. 미등록 교사용 프로필 입력 카드 (STEP 2: OAuth 정보 기입)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0E17),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2EC4B6).withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.how_to_reg_rounded, color: Color(0xFF2EC4B6), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '교사 프로필 등록',
                              style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '새로운 계정($_userEmail)입니다. 학교 및 컴시간 정보를 입력해 주세요.',
                          style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12),
                        ),
                        const SizedBox(height: 16),

                        // 학교 검색
                        Text('1. 소속 학교 검색', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _schoolSearchController,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '학교명 입력 (예: 보데스트 중)',
                                  hintStyle: const TextStyle(color: Colors.white38),
                                  filled: true,
                                  fillColor: const Color(0xFF16161A),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                ),
                                onSubmitted: _searchSchool,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _searchSchool(_schoolSearchController.text),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7F5AF0)),
                              child: _isSearchingSchool
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('검색'),
                            ),
                          ],
                        ),
                        if (_searchResults.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 120),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16161A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _searchResults.length,
                              itemBuilder: (ctx, i) {
                                final s = _searchResults[i];
                                return ListTile(
                                  dense: true,
                                  title: Text('${s.name} (${s.region})', style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                                  onTap: () => _onSelectSchool(s),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),

                        // 교사 성함 & 컴시간 ID
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('2. 교사 성함', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _teacherNameController,
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFF16161A),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('3. 컴시간 약칭 ID', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _teacherIdController,
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: '예: 홍길',
                                      hintStyle: const TextStyle(color: Colors.white38),
                                      filled: true,
                                      fillColor: const Color(0xFF16161A),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_teacherList.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('컴시간 교사 목록에서 선택:', style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 11)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _teacherList.take(8).map((t) {
                              return ActionChip(
                                label: Text(t, style: const TextStyle(fontSize: 11)),
                                backgroundColor: const Color(0xFF16161A),
                                onPressed: () {
                                  setState(() {
                                    _teacherIdController.text = t;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 14),

                        // 담임 학급 설정
                        Row(
                          children: [
                            Checkbox(
                              value: _isHomeroom,
                              activeColor: const Color(0xFF2EC4B6),
                              onChanged: (val) => setState(() => _isHomeroom = val ?? true),
                            ),
                            Text('담임 교사 (체크 해제 시 교과 전담)', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12.5)),
                          ],
                        ),
                        if (_isHomeroom) ...[
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  dropdownColor: const Color(0xFF16161A),
                                  value: _selectedGrade.clamp(1, 6),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: '학년',
                                    filled: true,
                                    fillColor: const Color(0xFF16161A),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  items: [1, 2, 3, 4, 5, 6].map((g) => DropdownMenuItem(value: g, child: Text('$g학년'))).toList(),
                                  onChanged: (v) => setState(() => _selectedGrade = v ?? 1),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  dropdownColor: const Color(0xFF16161A),
                                  value: _selectedClass.clamp(1, 15),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: '반',
                                    filled: true,
                                    fillColor: const Color(0xFF16161A),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  items: List.generate(15, (i) => i + 1).map((c) => DropdownMenuItem(value: c, child: Text('$c반'))).toList(),
                                  onChanged: (v) => setState(() => _selectedClass = v ?? 1),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20),

                        ElevatedButton.icon(
                          onPressed: _saveNewProfileAndLaunch,
                          icon: const Icon(Icons.check_circle_rounded),
                          label: Text(
                            '교사 정보 저장 및 앱 시작',
                            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2EC4B6),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  ],
),
    );
  }
}

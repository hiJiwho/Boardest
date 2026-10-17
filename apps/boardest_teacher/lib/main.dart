import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';
import 'config/app_config.dart';

import 'models/app_settings.dart';
import 'models/school.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/app_paths.dart';
import 'services/storage_service.dart';
import 'services/bst_save_service.dart';
import 'services/tray_service.dart';
import 'services/comcigan_service.dart';
import 'services/cloud_drive_service.dart';
import 'services/totp_service.dart';
import 'services/deep_link_service.dart';
import 'services/canva_oauth_service.dart';

import 'views/teacher_view.dart';
import 'views/teacher_setup_wizard_view.dart';
import 'services/registry_service.dart';
import 'services/update_service.dart';
import 'package:pdfrx/pdfrx.dart';
import 'views/bst_viewer_route.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await pdfrxFlutterInitialize();
  } catch (e) {
    debugPrint('[Pdfrx] initialization notice: $e');
  }
  AppConfig.initDemoMode(args);
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[Firebase] Initialization error: $e');
  }

  // Windows 레지스트리 파일 확장자 자동 연동 및 레거시 매핑 컨텍스트 메뉴 정리
  if (!kIsWeb && Platform.isWindows) {
    try {
      await acrylic.Window.initialize();
      await RegistryService.instance.registerFileAssociations();
    } catch (e) {
      debugPrint('[Boardest Teacher] Registry initialization error: $e');
    }
  }
  if (!kIsWeb) {
    await AppPaths.init();
    await BstSaveService.instance.ensureStructure();
    await DeepLinkService.instance.init(args);
  }
  await CanvaOAuthService.instance.init();
  await CloudDriveService.instance.init();

  // CLI 인자 파싱
  String? initialTool;
  String? viewBstPath;

  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--view-bst=')) {
      viewBstPath = arg.substring('--view-bst='.length);
      initialTool = 'view_bst';
    } else if (arg == '--view-bst' && i + 1 < args.length) {
      viewBstPath = args[i + 1];
      initialTool = 'view_bst';
      i++;
    } else if (!arg.startsWith('-')) {
      final lower = arg.toLowerCase();
      if (lower.endsWith('.bst') || lower.endsWith('.bsttbp') || lower.endsWith('.bstcanva') || lower.endsWith('.htmlp') || lower.endsWith('.bstpen')) {
        viewBstPath = arg;
        initialTool = 'view_bst';
      }
    }
  }

  // Windows 초기 설정 전에 세팅 및 담임 여부 판단
  final storage = StorageService();

  // Web OAuth Callback 쿼리 파라미터 자동 파싱 및 로그인 처리
  if (kIsWeb) {
    final uri = Uri.base;
    final params = Map<String, String>.from(uri.queryParameters);
    if (uri.fragment.isNotEmpty) {
      String frag = uri.fragment;
      if (frag.contains('?')) {
        frag = frag.substring(frag.indexOf('?') + 1);
      }
      final fragParams = Uri.splitQueryString(frag);
      params.addAll(fragParams);
    }

    final prefs = await SharedPreferences.getInstance();

    // Query param & persistent email based demo detection
    final qDemo = params['Demo'] ?? params['demo'] ?? params['isDemo'];
    final qEmail = params['email'] ?? '';
    final hasOAuthCallback = params['auth'] == 'success' || params.containsKey('token') || params.containsKey('access_token');
    final isIncomingRealUser = hasOAuthCallback && qEmail.isNotEmpty && !qEmail.toLowerCase().endsWith('boardest-teacher-demo.753210.xyz');
    if (isIncomingRealUser) {
      AppConfig.isDemoMode = false;
    } else {
      final existingSavedEmail = prefs.getString('bst_google_user_email') ?? prefs.getString('bst_user_email') ?? '';
      if (qDemo?.toLowerCase() == 'yes' ||
          qDemo?.toLowerCase() == 'true' ||
          qEmail.toLowerCase().endsWith('boardest-teacher-demo.753210.xyz') ||
          (!hasOAuthCallback && existingSavedEmail.toLowerCase().endsWith('boardest-teacher-demo.753210.xyz'))) {
        AppConfig.isDemoMode = true;
      }
    }

    if (hasOAuthCallback || (!AppConfig.isDemoMode && params.containsKey('email'))) {
      final email = params['email'] ?? '';
      final token = params['token'] ?? params['access_token'] ?? '';
      String teacherName = params['teacherName'] ?? '';
      String schoolName = params['schoolName'] ?? '양동중학교';

      if (token.isNotEmpty || email.isNotEmpty) {
        String? totpSecret = params['totpSecret'];
        String? shortId = params['shortId'];
        final refreshToken = params['refreshToken'] ?? '';

        await CloudDriveService.instance.setSession(
          accessToken: token,
          bstCldToken: token,
          refreshToken: refreshToken,
          email: email,
          name: teacherName,
          school: schoolName,
          totpSecret: totpSecret,
          shortId: shortId,
        );
      }
    }
  }

  // ─── 데모 및 일반 세션 동기화 (Web & Windows 공통) ───
  final prefs = await SharedPreferences.getInstance();
  final currentEmailCheck = prefs.getString('bst_google_user_email') ?? prefs.getString('bst_user_email') ?? '';
  if (currentEmailCheck.toLowerCase().endsWith('boardest-teacher-demo.753210.xyz')) {
    AppConfig.isDemoMode = true;
  }

  if (AppConfig.isDemoMode) {
    // 1. 데모 모드: 9개 반(1-1~1-3, 2-1~2-3, 3-1~3-3) 및 9명 교사 완전 순환 배정
    final demoTeachers = [
      (name: '김국어', subject: '국어', grade: 1, classNum: 1, shortId: '11'),
      (name: '이수학', subject: '수학', grade: 1, classNum: 2, shortId: '12'),
      (name: '박영어', subject: '영어', grade: 1, classNum: 3, shortId: '13'),
      (name: '최과학', subject: '과학', grade: 2, classNum: 1, shortId: '14'),
      (name: '정사회', subject: '사회', grade: 2, classNum: 2, shortId: '15'),
      (name: '강역사', subject: '역사', grade: 2, classNum: 3, shortId: '16'),
      (name: '송음악', subject: '음악', grade: 3, classNum: 1, shortId: '17'),
      (name: '윤체육', subject: '체육', grade: 3, classNum: 2, shortId: '18'),
      (name: '조미술', subject: '미술', grade: 3, classNum: 3, shortId: '19'),
    ];

    int teacherSlot = 0;
    // 특정 데모 계정(01, 02 등) 우선 매핑
    final activeEmail = currentEmailCheck.toLowerCase();
    if (activeEmail.startsWith('01@') || activeEmail.contains('teacher-demo.753210.xyz') && activeEmail.startsWith('01')) {
      teacherSlot = 0; // 김국어 (1-1 담임)
    } else if (activeEmail.startsWith('02@') || activeEmail.contains('teacher-demo.753210.xyz') && activeEmail.startsWith('02')) {
      teacherSlot = 1; // 이수학 (1-2 담임)
    } else {
      var deviceId = prefs.getString('bst_demo_device_uuid');
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = 'bst_dev_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
        await prefs.setString('bst_demo_device_uuid', deviceId);
      }

      int slot = 0;
      try {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await http.put(
          Uri.parse('https://jiwhosboardest-default-rtdb.firebaseio.com/demo_active_devices/$deviceId.json'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'lastSeen': nowMs}),
        ).timeout(const Duration(seconds: 2));

        final res = await http.get(
          Uri.parse('https://jiwhosboardest-default-rtdb.firebaseio.com/demo_active_devices.json'),
        ).timeout(const Duration(seconds: 2));

        if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          final activeIds = map.entries
              .where((e) {
                final val = e.value;
                if (val is Map && val['lastSeen'] != null) {
                  return (nowMs - (val['lastSeen'] as num)) < 7200000;
                }
                return true;
              })
              .map((e) => e.key)
              .toList()
            ..sort();

          final idx = activeIds.indexOf(deviceId);
          slot = (idx != -1) ? idx : activeIds.length;
        }
      } catch (_) {
        slot = deviceId.hashCode.abs();
      }

      // 9명까지는 안 겹치고, 9명 넘으면 순환
      teacherSlot = slot % 9;
    }

    final assigned = demoTeachers[teacherSlot];
    final demoEmail = activeEmail.endsWith('boardest-teacher-demo.753210.xyz')
        ? activeEmail
        : '${assigned.shortId == '11' ? '01' : (assigned.shortId == '12' ? '02' : assigned.shortId)}@boardest-teacher-demo.753210.xyz';
    final demoTeacherName = assigned.name;
    final demoTeacherId = assigned.name;
    final demoShortId = assigned.shortId;
    final demoGrade = assigned.grade;
    final demoClassNum = assigned.classNum;
    final demoTotpSecret = TotpService.generateDeterministicSecret(demoEmail);
    final demoToken = 'demo_token_teacher_${assigned.shortId}';
    const demoSchoolId = 'demo';
    const demoSchoolName = '데모 중학교';
    const demoIsHomeroom = true;
    const demoCafeteria = '1';

    await prefs.setString('bst_google_user_email', demoEmail);
    await prefs.setString('bst_user_email', demoEmail);
    await prefs.setString('bst_google_user_name', demoTeacherName);
    await prefs.setString('bst_user_name', demoTeacherName);
    await prefs.setString('bst_cld_access_token', demoToken);
    await prefs.setString('bst_google_access_token', demoToken);
    await prefs.setString('bst_school_name', demoSchoolName);
    await prefs.setString('bst_totp_secret_key', demoTotpSecret);
    await prefs.setString('bst_totp_secret', demoTotpSecret);
    await prefs.setString('bst_teacher_short_id', demoShortId);

    await CloudDriveService.instance.setSession(
      accessToken: demoToken,
      bstCldToken: demoToken,
      refreshToken: '',
      email: demoEmail,
      name: demoTeacherName,
      school: demoSchoolName,
      totpSecret: demoTotpSecret,
      shortId: demoShortId,
    );

    final school = School(
      id: 11111,
      code: 11111,
      name: demoSchoolName,
      region: '서울',
    );
    final existing = await storage.getSettings();
    final newSettings = existing.copyWith(
      selectedSchool: school,
      schoolId: demoSchoolId,
      selectedGrade: demoGrade,
      selectedClass: demoClassNum,
      selectedTeacher: demoTeacherId,
      selectedTeacherId: demoTeacherId,
      selectedTeacherName: demoTeacherName,
      cafeteriaNum: demoCafeteria,
      isHomeroom: demoIsHomeroom,
      isSetupComplete: true,
    );
    await storage.saveSettings(newSettings);
  } else {
    // 2. 일반 모드: 이전 데모 잔여 세션 완전 소각 (데모 로그인도 안 했는데 데모 뜨는 현상 원천 차단)
    final savedEmail = prefs.getString('bst_google_user_email') ?? prefs.getString('bst_user_email') ?? '';
    final savedToken = prefs.getString('bst_cld_access_token') ?? prefs.getString('bst_google_access_token') ?? prefs.getString('bst_token') ?? '';
    final savedName = prefs.getString('bst_google_user_name') ?? prefs.getString('bst_user_name') ?? '';
    final savedSchool = prefs.getString('bst_school_name') ?? '';

    final isExplicitDemoEmail = savedEmail.toLowerCase().endsWith('boardest-teacher-demo.753210.xyz');
    final isLegacyDemoArtifact = !isExplicitDemoEmail && (
        (savedEmail.startsWith('demo_') && savedEmail.endsWith('@boardest.com')) ||
        (savedToken.startsWith('demo_token_') && !isExplicitDemoEmail) ||
        (savedSchool.contains('데모') && !isExplicitDemoEmail && !savedEmail.contains('@'))
    );

    if (isLegacyDemoArtifact) {
      debugPrint('[main.dart] 🧹 Wiping legacy dummy demo session from disk & prefs...');
      await prefs.remove('bst_cld_access_token');
      await prefs.remove('bst_google_access_token');
      await prefs.remove('bst_token');
      await prefs.remove('bst_google_user_email');
      await prefs.remove('bst_user_email');
      await prefs.remove('bst_google_user_name');
      await prefs.remove('bst_user_name');
      await prefs.remove('bst_school_name');
      await prefs.remove('bst_totp_secret');
      await prefs.remove('bst_totp_secret_key');
      await prefs.remove('bst_teacher_short_id');

      if (!kIsWeb) {
        try {
          final f1 = File(p.join(AppPaths.configDir, 'teacher_session.json'));
          if (await f1.exists()) await f1.delete();
          final exeDir = File(Platform.resolvedExecutable).parent.path;
          final f2 = File(p.join(exeDir, 'teacher_session.json'));
          if (await f2.exists()) await f2.delete();
        } catch (_) {}
      }
    } else if (savedEmail.isNotEmpty || savedToken.isNotEmpty) {
      // 일반 및 정식 계정 세션 자동 복원 (새로고침 및 재시작 시 로그인 유지)
      final savedTotp = prefs.getString('bst_totp_secret_key') ?? prefs.getString('bst_totp_secret');
      final savedShortId = prefs.getString('bst_teacher_short_id');
      final savedRefresh = prefs.getString('bst_cld_refresh_token') ?? prefs.getString('bst_refresh_token');
      await CloudDriveService.instance.setSession(
        accessToken: savedToken,
        bstCldToken: savedToken,
        refreshToken: savedRefresh,
        email: savedEmail,
        name: savedName,
        school: savedSchool,
        totpSecret: savedTotp,
        shortId: savedShortId,
      );
    }

    // 3. hijiwho@gmail.com 및 hi.jiwho@gmail.com 정식 회원 자동 복원
    final currentEmail = prefs.getString('bst_google_user_email') ?? prefs.getString('bst_user_email') ?? CloudDriveService.instance.userEmail ?? '';
    final cleanCurrent = currentEmail.toLowerCase().replaceAll('.', '');
    if (cleanCurrent == 'hijiwhogmailcom') {
      try {
        final profileUrl = Uri.parse('${AppConfig.firestoreBase}/teacher_profiles/hi_jiwho_gmail_com?key=${AppConfig.firebaseApiKey}');
        final pRes = await http.get(profileUrl).timeout(const Duration(seconds: 4));
        if (pRes.statusCode == 200) {
          final pData = jsonDecode(pRes.body);
          final fields = pData['fields'] as Map<String, dynamic>?;
          if (fields != null) {
            final tName = (fields['teacherName'] as Map?)?['stringValue']?.toString() ?? '박지후';
            final sName = (fields['schoolName'] as Map?)?['stringValue']?.toString() ?? '양동중학교';
            final sCode = int.tryParse((fields['schoolCode'] as Map?)?['stringValue']?.toString() ?? '44134') ?? 44134;

            await prefs.setString('bst_google_user_email', 'hijiwho@gmail.com');
            await prefs.setString('bst_user_email', 'hijiwho@gmail.com');
            await prefs.setString('bst_google_user_name', tName);
            await prefs.setString('bst_user_name', tName);
            await prefs.setString('bst_school_name', sName);

            final school = School(id: sCode, code: sCode, name: sName, region: '서울');
            final curSettings = await storage.getSettings();
            final fixedSettings = curSettings.copyWith(
              selectedSchool: school,
              schoolId: '44134',
              selectedGrade: 1,
              selectedClass: 1,
              selectedTeacher: '1',
              selectedTeacherId: '1',
              selectedTeacherName: tName,
              cafeteriaNum: '1',
              isHomeroom: true,
              isSetupComplete: true,
            );
            await storage.saveSettings(fixedSettings);
          }
        }
      } catch (_) {}
    }
  }

  final settings = await storage.loadConfigAndSync();

  if (!kIsWeb && Platform.isWindows) {
    try {
      await windowManager.ensureInitialized();

      // 메인 교사용 도구 또는 BST 뷰어 모드: 일반 대형 창 크기
      WindowOptions windowOptions = const WindowOptions(
        size: Size(1200, 800),
        minimumSize: Size(960, 640),
        center: true,
        title: 'Boardest Teacher',
        skipTaskbar: false,
        backgroundColor: Colors.transparent,
        titleBarStyle: TitleBarStyle.normal,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setBackgroundColor(Colors.transparent);
        await windowManager.setPreventClose(true);
        await windowManager.setResizable(true);
        await windowManager.show();
      });

      // 시스템 트레이 설정
      await TrayService.instance.init(
        onRestore: () async {
          await windowManager.show();
          await windowManager.focus();
        },
        onQuit: () {
          TrayService.instance.dispose().then((_) => exit(0));
        },
      );
    } catch (e) {
      debugPrint('[Boardest Teacher] Windows initialization error: $e');
    }
  }

  runApp(TeacherApp(
    settings: settings,
    initialTool: initialTool,
    viewBstPath: viewBstPath,
  ));
}

class TeacherApp extends StatefulWidget {
  final AppSettings settings;
  final String? initialTool;
  final String? viewBstPath;

  const TeacherApp({
    super.key,
    required this.settings,
    this.initialTool,
    this.viewBstPath,
  });

  @override
  State<TeacherApp> createState() => _TeacherAppState();
}

class _TeacherAppState extends State<TeacherApp> with WindowListener {
  late AppSettings _settings;
  String _themeMode = 'system';
  String _themeColor = 'system';
  Color _systemAccentColor = const Color(0xFF7F5AF0);

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _themeMode = _settings.themeMode;
    _themeColor = _settings.themeColor;
    _loadWindowsAccentColor();
    TeacherView.onSettingsChanged = _reloadSettings;
    CloudDriveService.instance.registerLoginCallback(() {
      _reloadSettings();
    });
    if (kIsWeb) {
      _reloadSettings();
    }
    if (!kIsWeb && Platform.isWindows && widget.initialTool != 'lite_map') {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && Platform.isWindows && widget.initialTool != 'lite_map') {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _reloadSettings() async {
    final storage = StorageService();
    final s = await storage.loadConfigAndSync();
    await _loadWindowsAccentColor();
    if (mounted) {
      setState(() {
        _settings = s;
        _themeMode = s.themeMode;
        _themeColor = s.themeColor;
      });
    }
  }

  Future<void> _loadWindowsAccentColor() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '[Convert]::ToString((Get-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\DWM").ColorizationColor, 16)'
      ]);
      if (res.exitCode == 0) {
        final hex = res.stdout.toString().trim();
        if (hex.length >= 8) {
          final colorInt = int.tryParse(hex, radix: 16);
          if (colorInt != null) {
            if (mounted) {
              setState(() {
                _systemAccentColor = Color(colorInt).withOpacity(1.0);
              });
            }
          }
        }
      }
    } catch (_) {}
  }

  Color get _accentColor {
    if (_themeColor == 'purple') return const Color(0xFF7F5AF0);
    if (_themeColor == 'green') return const Color(0xFF2CB67D);
    if (_themeColor == 'blue') return const Color(0xFF007AFF);
    if (_themeColor == 'orange') return const Color(0xFFFF9F0A);
    return _systemAccentColor;
  }

  // 닫기 버튼 눌렀을 때의 동작 인터셉트
  @override
  void onWindowClose() async {
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      if (TeacherView.onWindowClosePressed != null) {
        TeacherView.onWindowClosePressed!();
      } else {
        await windowManager.hide(); // 창만 숨기고 트레이에서 유지
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (widget.initialTool == 'view_bst') {
      home = BstViewerRoute(
        bstPath: widget.viewBstPath ?? '',
        scaleFactor: _settings.scaleFactor,
      );
    } else if (!_settings.isSetupComplete || _settings.selectedSchool == null) {
      home = const TeacherSetupWizardView();
    } else {
      home = const TeacherView();
    }

    final primaryColor = _accentColor;
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'SiwonhanSeolreim',
      primaryColor: primaryColor,
      scaffoldBackgroundColor: const Color(0xFF0F0E17),
      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        secondary: const Color(0xFF2CB67D),
        surface: const Color(0xFF16161A),
        background: const Color(0xFF0F0E17),
        error: const Color(0xFFEF4565),
      ),
      textTheme: GoogleFonts.notoSansKrTextTheme(
        ThemeData.dark().textTheme,
      ),
    );

    final lightTheme = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      fontFamily: 'SiwonhanSeolreim',
      primaryColor: primaryColor,
      scaffoldBackgroundColor: const Color(0xFFF3F3F5),
      colorScheme: ColorScheme.light(
        primary: primaryColor,
        secondary: const Color(0xFF2CB67D),
        surface: Colors.white,
        background: const Color(0xFFF3F3F5),
        error: const Color(0xFFEF4565),
      ),
      textTheme: GoogleFonts.notoSansKrTextTheme(
        ThemeData.light().textTheme,
      ),
    );

    return MaterialApp(
      title: 'Boardest Teacher',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode == 'light' ? ThemeMode.light : (_themeMode == 'dark' ? ThemeMode.dark : ThemeMode.system),
      home: home,
    );
  }
}

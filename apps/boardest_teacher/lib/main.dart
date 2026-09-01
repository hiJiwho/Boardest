import 'dart:async';
import 'dart:convert';
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
import 'services/context_menu_service.dart';
import 'services/tray_service.dart';
import 'services/comcigan_service.dart';
import 'services/cloud_drive_service.dart';
import 'services/deep_link_service.dart';
import 'services/canva_oauth_service.dart';

import 'views/teacher_view.dart';
import 'views/teacher_setup_wizard_view.dart';
import 'views/lite_map_dialog.dart';
import 'services/registry_service.dart';
import 'views/bst_viewer_route.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[Firebase] Initialization error: $e');
  }
  if (!kIsWeb && Platform.isWindows) {
    await acrylic.Window.initialize();
    await RegistryService.instance.registerFileAssociations();
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
  String? liteMapPath;
  String? viewBstPath;

  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--lite-map=')) {
      liteMapPath = arg.substring('--lite-map='.length);
      initialTool = 'lite_map';
    } else if (arg == '--lite-map' && i + 1 < args.length) {
      liteMapPath = args[i + 1];
      initialTool = 'lite_map';
      i++;
    } else if (arg.startsWith('--view-bst=')) {
      viewBstPath = arg.substring('--view-bst='.length);
      initialTool = 'view_bst';
    } else if (arg == '--view-bst' && i + 1 < args.length) {
      viewBstPath = args[i + 1];
      initialTool = 'view_bst';
      i++;
    } else if (!arg.startsWith('-')) {
      final lower = arg.toLowerCase();
      if (lower.endsWith('.bst') || lower.endsWith('.bsttbp') || lower.endsWith('.bstcanva') || lower.endsWith('.bstpen')) {
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
    final cachedToken = prefs.getString('bst_google_access_token') ?? prefs.getString('bst_token') ?? '';
    final cachedEmail = prefs.getString('bst_google_user_email') ?? prefs.getString('bst_user_email') ?? '';

    if (params['auth'] == 'success' || params.containsKey('token') || params.containsKey('access_token') || params.containsKey('email') || cachedToken.isNotEmpty || cachedEmail.isNotEmpty) {
      final email = params['email'] ?? cachedEmail;
      final token = params['token'] ?? params['access_token'] ?? cachedToken;
      String teacherName = params['teacherName'] ?? prefs.getString('bst_google_user_name') ?? prefs.getString('bst_user_name') ?? '';
      String teacherId = params['teacherId'] ?? '';
      String schoolId = params['schoolId'] ?? 'ydm';
      String schoolCode = params['schoolCode'] ?? params['schoolId'] ?? '';
      String schoolName = params['schoolName'] ?? prefs.getString('bst_school_name') ?? '학교';
      int grade = int.tryParse(params['grade'] ?? '1') ?? 1;
      int classNum = int.tryParse(params['classNum'] ?? '1') ?? 1;
      bool isHomeroom = params['isHomeroom'] == 'true';
      String cafeteria = params['cafeteriaNum'] ?? '1';

      // 1. 실시간 Firestore 교사 프로필 조회로 최신 데이터 동기화
      if (email.isNotEmpty) {
        try {
          final docId = email.replaceAll('.', '_').replaceAll('@', '_').replaceAll('+', '_');
          final url = Uri.parse(
            '${AppConfig.firestoreBase}/teacher_profiles/$docId?key=${AppConfig.firebaseApiKey}',
          );
          final res = await http.get(url).timeout(const Duration(seconds: 4));
          if (res.statusCode == 404) {
            debugPrint('[main.dart] ⚠️ Profile deleted from Firestore (404). Clearing session.');
            await storage.clearAllSession();
            // 404 시 설정 완료되지 않은 상태로 초기화
            await storage.saveSettings(AppSettings(isSetupComplete: false));
            return;
          } else if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final fields = data['fields'] as Map<String, dynamic>?;
            if (fields != null) {
              final Map<String, dynamic> map = {};
              fields.forEach((k, v) {
                if (v is Map) {
                  map[k] = v['stringValue'] ?? v['integerValue'] ?? v['booleanValue'] ?? v['doubleValue'];
                }
              });
              schoolName = map['schoolName']?.toString() ?? schoolName;
              schoolId = map['schoolId']?.toString() ?? schoolId;
              schoolCode = map['schoolCode']?.toString() ?? map['schoolId']?.toString() ?? schoolCode;
              teacherName = map['teacherName']?.toString() ?? teacherName;
              teacherId = map['teacherId']?.toString() ?? teacherId;
              grade = int.tryParse(map['grade']?.toString() ?? '') ?? grade;
              classNum = int.tryParse(map['classNum']?.toString() ?? '') ?? classNum;
              isHomeroom = map['isHomeroom'] == true || map['isHomeroom']?.toString().toLowerCase() == 'true';
              cafeteria = map['cafeteriaNum']?.toString() ?? cafeteria;
            }
          }
        } catch (_) {}
      }

      // 2. Boardest Control 등록 학교 코드 1순위 실시간 보정
      try {
        final schoolConfig = await ComciganService.fetchSchoolConfig(schoolId);
        if (schoolConfig != null) {
          if (schoolConfig['comciganCode'] != null) schoolCode = schoolConfig['comciganCode'].toString();
          if (schoolConfig['schoolName'] != null) schoolName = schoolConfig['schoolName'].toString();
        }
      } catch (_) {}

      final refreshToken = params['refreshToken'] ?? prefs.getString('bst_google_refresh_token') ?? '';
      if (refreshToken.isNotEmpty) {
        await prefs.setString('bst_google_refresh_token', refreshToken);
      }

      if (token.isNotEmpty || email.isNotEmpty) {
        await CloudDriveService.instance.setSession(
          accessToken: token,
          bstCldToken: token,
          refreshToken: refreshToken,
          email: email,
          name: teacherName,
          school: schoolName,
        );
      }

      // schoolCode fallback
      if (schoolCode.isEmpty) schoolCode = schoolId;
      final int parsedCode = int.tryParse(schoolCode) ?? int.tryParse(schoolId) ?? 44134;

      // AppSettings 저장 (isSetupComplete = true)
      final school = School(
        id: parsedCode,
        code: parsedCode,
        name: schoolName,
        region: '서울',
      );
      final newSettings = AppSettings(
        selectedSchool: school,
        schoolId: schoolId,
        selectedGrade: grade,
        selectedClass: classNum,
        selectedTeacher: teacherId.isNotEmpty ? teacherId : teacherName,
        selectedTeacherId: teacherId.isNotEmpty ? teacherId : teacherName,
        selectedTeacherName: teacherName,
        cafeteriaNum: cafeteria,
        isSetupComplete: true,
      );
      await storage.saveSettings(newSettings);
    }
  }

  final settings = await storage.loadConfigAndSync();

  bool isHomeroom = false;
  if (initialTool == 'lite_map' && settings.selectedSchool != null) {
    try {
      final comcigan = ComciganService();
      final raw = await comcigan.fetchTimetableRaw(settings.selectedSchool!.code);
      final result = comcigan.parseTimetable(raw);
      
      final homeroomMap = result.homeroomTeachers[settings.selectedGrade];
      if (homeroomMap != null) {
        final homeroomTeacher = homeroomMap[settings.selectedClass];
        if (homeroomTeacher != null) {
          final selectedTeacherSanitized = settings.selectedTeacherId.replaceAll('*', '').trim().toUpperCase();
          final homeroomTeacherSanitized = homeroomTeacher.replaceAll('*', '').trim().toUpperCase();
          isHomeroom = selectedTeacherSanitized.isNotEmpty && selectedTeacherSanitized == homeroomTeacherSanitized;
        }
      }
    } catch (_) {}
  }

  if (!kIsWeb && Platform.isWindows) {
    try {
      await windowManager.ensureInitialized();

      if (initialTool == 'lite_map') {
        // 담임교사일 때만 가로 확장(900x650), 비담임교사일 때는 콤팩트(520x600) 유지
        final size = isHomeroom ? const Size(900, 650) : const Size(520, 600);
        WindowOptions windowOptions = WindowOptions(
          size: size,
          minimumSize: size,
          maximumSize: size,
          center: true,
          title: 'Boardest Pro - 교안 매핑',
          skipTaskbar: false,
        );
        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.show();
          await windowManager.setResizable(false);
          await windowManager.setPreventClose(false); // 바로 종료되도록 설정
        });
      } else {
        // 메인 교사용 도구 또는 BST 뷰어 모드: 일반 대형 창 크기
        WindowOptions windowOptions = const WindowOptions(
          size: Size(1200, 800),
          minimumSize: Size(960, 640),
          center: true,
          title: 'Bst Teacher',
          skipTaskbar: false,
          backgroundColor: Colors.transparent,
          titleBarStyle: TitleBarStyle.hidden,
        );
        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.setBackgroundColor(Colors.transparent);
          await windowManager.setPreventClose(true);
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
      }
    } catch (e) {
      debugPrint('[Boardest Teacher] Windows initialization error: $e');
    }
  }

  runApp(TeacherApp(
    settings: settings,
    initialTool: initialTool,
    liteMapPath: liteMapPath,
    viewBstPath: viewBstPath,
  ));
}

class TeacherApp extends StatefulWidget {
  final AppSettings settings;
  final String? initialTool;
  final String? liteMapPath;
  final String? viewBstPath;

  const TeacherApp({
    super.key,
    required this.settings,
    this.initialTool,
    this.liteMapPath,
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
    if (widget.initialTool == 'lite_map') {
      home = Scaffold(
        backgroundColor: const Color(0xFF0F0E17),
        body: Center(
          child: LiteMapDialog(folderPath: widget.liteMapPath ?? ''),
        ),
      );
    } else if (widget.initialTool == 'view_bst') {
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
      theme: darkTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      home: home,
    );
  }
}

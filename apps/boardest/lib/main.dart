import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:boardest/services/fcm_token_service.dart';
import 'package:boardest/services/comcigan_service.dart';
import 'models/school.dart';
import 'models/app_settings.dart';
import 'package:universal_io/io.dart';
import 'services/app_paths.dart';
import 'services/storage_service.dart';
import 'services/bst_save_service.dart';
import 'services/bst_cloud_service.dart';
import 'services/auth_service.dart';
import 'services/meal_call_service.dart';
import 'config/app_config.dart';
import 'views/setup_wizard_view.dart';
import 'views/dashboard_view.dart';
import 'views/boardest_tools_view.dart';
import 'services/demo_class_allocator_service.dart';
import 'helpers/startup_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';


Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized (in case it's not already)
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: AppConfig.firebaseApiKey,
      authDomain: AppConfig.firebaseAuthDomain,
      projectId: AppConfig.firebaseProjectId,
      storageBucket: AppConfig.firebaseStorageBucket,
      messagingSenderId: AppConfig.firebaseMessagingSenderId,
      appId: AppConfig.firebaseAppId,
    ),
  );
  // Forward to service
  MealCallService.instance.handleRemoteMessage(message);
}

void main(List<String> args) async {
  // Catch all unhandled Flutter errors
  FlutterError.onError = (FlutterErrorDetails details) {
    final errStr = details.exceptionAsString();
    if (errStr.contains('RenderFlex overflowed')) {
      return; // Ignore benign layout pixel overflows
    }
    FlutterError.presentError(details);
    debugPrint('[Boardest Fatal] Unhandled Flutter Error: ${details.exception}');
    NativeStartupHelper.writeCrashLog('FlutterError: ${details.exception}', details.stack?.toString() ?? 'No stacktrace');
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('[Boardest ErrorWidget] Handled UI Exception: ${details.exception}');
    return const Material(
      color: Colors.transparent,
      child: Center(child: SizedBox.shrink()),
    );
  };

  // Catch all unhandled platform/async errors
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[Boardest Fatal] Unhandled Platform Error: $error');
    NativeStartupHelper.writeCrashLog('PlatformError: $error', stack.toString());
    
    return true;
  };

  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.initDemoMode(args);
  try {
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb) {
      final uri = Uri.base;
      final qDemo = uri.queryParameters['demo'] ?? uri.queryParameters['Demo'];
      if (qDemo == '1' || qDemo == 'true') {
        AppConfig.isDemoMode = true;
        await prefs.setBool('bst_persisted_demo', true);
      } else if (qDemo == '0' || qDemo == 'false') {
        AppConfig.isDemoMode = false;
        await prefs.remove('bst_persisted_demo');
      } else if (prefs.getBool('bst_persisted_demo') == true) {
        AppConfig.isDemoMode = true;
      }
    } else {
      if (prefs.getBool('bst_persisted_demo') == true) {
        AppConfig.isDemoMode = true;
      }
    }
  } catch (_) {}
  AppConfig.initLiteMode(args);
  AppConfig.initToolsMode(args);
  try {
    pdfrxFlutterInitialize();
  } catch (e) {
    debugPrint('[Pdfrx] initialization notice: $e');
  }
  if (!kIsWeb) {
    if (Platform.isWindows) {
      try {
        await windowManager.ensureInitialized();
      } catch (_) {}
    }
    await AppPaths.init();
    await BstSaveService.instance.ensureStructure();
    NativeStartupHelper.runWindowsStartupTasks();
  }

  // Initialize Firebase for Web and Mobile platforms (Bypass on Windows/Linux desktop)
  if (kIsWeb || (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS)) {
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          authDomain: AppConfig.firebaseAuthDomain,
          projectId: AppConfig.firebaseProjectId,
          storageBucket: AppConfig.firebaseStorageBucket,
          messagingSenderId: AppConfig.firebaseMessagingSenderId,
          appId: AppConfig.firebaseAppId,
        ),
      );

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        MealCallService.instance.handleRemoteMessage(message);
      });
      debugPrint("Firebase initialized successfully on supported platform (${kIsWeb ? 'Web' : defaultTargetPlatform}).");
    } catch (e) {
      debugPrint("Firebase initialization failed: $e");
    }
  } else {
    debugPrint("Firebase bypass initialization: Desktop platform is bypassed (${defaultTargetPlatform}).");
  }

  final storage = StorageService();
  AppSettings settings = await storage.loadConfigAndSync();

  // Demo 모드일 경우 Demo-class 1~10 비겹침 할당 실행
  if (AppConfig.isDemoMode) {
    settings = await DemoClassAllocatorService.instance.allocateDemoSettings(settings);
    debugPrint('[Boardest Startup] Running in Demo mode: ${settings.classNickname}');
  }

  // Tools 모드일 경우 무설치 수업도구 즉시 실행 세팅
  if (AppConfig.isToolsMode) {
    settings = settings.copyWith(
      isSetupComplete: true,
      selectedSchool: School(id: 0, code: 0, name: 'Boardest Tools', region: '전국'),
    );
    debugPrint('[Boardest Startup] Running in Tools mode');
  }

  // Dynamic Comcigan school code lookup
  if (settings.isSetupComplete && settings.schoolId.isNotEmpty && !AppConfig.isDemoMode) {
    try {
      final schoolCodeStr = await ComciganService.fetchCode(settings.schoolId.trim().toLowerCase());
      final parsedCode = int.tryParse(schoolCodeStr);
      if (parsedCode != null && settings.selectedSchool != null) {
        final updatedSchool = settings.selectedSchool!.copyWith(code: parsedCode);
        settings = settings.copyWith(selectedSchool: updatedSchool);
      }
    } catch (e) {
      debugPrint('[Boardest Startup] ComciganService.fetchCode error: $e');
    }
  }

  // FCM token 저장 (settings 로드 이후)
  if (kIsWeb || (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS)) {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null && settings.schoolId.isNotEmpty) {
        await FcmTokenService.storeToken(fcmToken, settings.schoolId.trim().toLowerCase());
      }
    } catch (e) {
      debugPrint('[Boardest Startup] FCM token store error: $e');
    }
  }

  if (kIsWeb && !AppConfig.isDemoMode) {
    final uri = Uri.base;
    if (uri.queryParameters['auth'] == 'success') {
      final email = uri.queryParameters['email'] ?? '';
      final token = uri.queryParameters['token'] ?? '';
      final teacherName = uri.queryParameters['teacherName'] ?? '';
      final teacherId = uri.queryParameters['teacherId'] ?? '';
      final schoolId = uri.queryParameters['schoolId'] ?? '44134';
      final schoolCode = uri.queryParameters['schoolCode'] ?? schoolId;
      final schoolName = uri.queryParameters['schoolName'] ?? '교사 연구실';
      final grade = int.tryParse(uri.queryParameters['grade'] ?? '1') ?? 1;
      final classNum = int.tryParse(uri.queryParameters['classNum'] ?? '1') ?? 1;
      final cafeteria = uri.queryParameters['cafeteriaNum'] ?? '1';
      final codeInt = int.tryParse(schoolCode) ?? int.tryParse(schoolId) ?? 44134;

      settings = settings.copyWith(
        selectedSchool: School(id: codeInt, code: codeInt, name: schoolName, region: '서울'),
        schoolId: schoolId,
        selectedGrade: grade,
        selectedClass: classNum,
        selectedTeacher: teacherName,
        selectedTeacherId: teacherId.isNotEmpty ? teacherId : teacherName,
        selectedTeacherName: teacherName,
        specialClassroomMode: true,
        specialClassroomType: 2,
        classNickname: teacherName.isNotEmpty ? '$teacherName 선생님' : 'Class Teacher',
        cafeteriaNum: cafeteria,
        isSetupComplete: true,
      );
      if (token.isNotEmpty) {
        BstCloudService.instance.setDirectAccessToken(token, teacherName: teacherName, ownerEmail: email);
      }
      await storage.saveSettings(settings);
    } else if (uri.queryParameters['oobe_callback'] == 'true') {
      final code = int.tryParse(uri.queryParameters['code'] ?? '') ?? 31415;
      final grade = int.tryParse(uri.queryParameters['grade'] ?? '') ?? 2;
      final classNum = int.tryParse(uri.queryParameters['class'] ?? '') ?? 1;

      settings = settings.copyWith(
        selectedSchool: School(id: code, code: code, name: '길동중학교', region: '서울'),
        selectedGrade: grade,
        selectedClass: classNum,
        isSetupComplete: true,
      );
      await storage.saveSettings(settings);
    }
  }

  if (settings.isSetupComplete) {
    unawaited(MealCallService.instance.ensurePresence(settings));
  }
  final authService = AuthService();
  var currentUser = await authService.getCurrentUser();

  // 로그인 검증 및 미로그인 시 샌드박스 정리 & 로그인 요구 (데모 및 툴즈 모드 시 우회)
  if (currentUser == null && !AppConfig.isDemoMode && !AppConfig.isToolsMode) {
    if (settings.isSetupComplete && settings.selectedSchool != null) {
      try {
        final err = await authService.loginOrSignupClass(
          region: settings.selectedSchool!.region,
          school: settings.selectedSchool!.name,
          schoolId: settings.schoolId,
          grade: settings.selectedGrade,
          classNum: settings.selectedClass,
          isSpecial: settings.specialClassroomMode,
          specialId: settings.classNickname,
        );
        if (err == null) {
          currentUser = await authService.getCurrentUser();
          debugPrint('[Boardest Startup] Successfully auto-logged in using saved school settings.');
        } else {
          debugPrint('[Boardest Startup] Auto-login failed: $err');
        }
      } catch (e) {
        debugPrint('[Boardest Startup] Auto-login error: $e');
      }
    }

    // 여전히 로그인이 안 되어있으면 샌드박스 내부 임시 데이터 소거 및 로그인 요구창 진입
    if (currentUser == null && !AppConfig.isDemoMode && !AppConfig.isToolsMode) {
      debugPrint('[Boardest Startup] Not logged in. Purging sandbox data and prompting login...');
      try {
        final tempDir = Directory(AppPaths.bstCldTempDirSync);
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
          tempDir.createSync(recursive: true);
        }
      } catch (_) {}
      settings = settings.copyWith(isSetupComplete: false);
      await storage.saveSettings(settings);
    }
  }

  // Parse launch tool from CLI args
  String? initialTool;
  bool pptFullscreen = false;
  
  for (final arg in args) {
    if (arg == '-board') {
      initialTool = 'whiteboard';
    } else if (arg == '-timer') {
      initialTool = 'timer';
    } else if (arg == '-picker') {
      initialTool = 'picker';
    } else if (arg == '-weather') {
      initialTool = 'weather';
    } else if (arg == '-calendar') {
      initialTool = 'school_calendar';
    } else if (arg == '-ppt' || arg == '-ppt_board') {
      initialTool = 'ppt_board';
    } else if (arg == '-hwp' || arg == '-hwp_board') {
      initialTool = 'hwp_board';
    } else if (arg == '-s') {
      pptFullscreen = true;
      initialTool = 'ppt_board';
    } else if (arg == '-pdf' || arg == '-pdf_board') {
      initialTool = 'pdf_board';
    } else if (arg == '-site' || arg == '-website_board') {
      initialTool = 'website_board';
    } else if (arg == '-calculator') {
      initialTool = 'calculator';
    } else if (arg == '-notepad') {
      initialTool = 'notepad';
    } else if (arg == '-dice') {
      initialTool = 'dice';
    } else if (arg == '-timetable') {
      initialTool = 'timetable';
    } else if (arg == '-noise') {
      initialTool = 'noise';
    } else if (arg == '-settings') {
      initialTool = 'settings';
    } else if (arg == '-explorer' || arg == '-file_explorer') {
      initialTool = 'file_explorer';
    } else if (!arg.startsWith('-')) {
      final lower = arg.toLowerCase();
      if (lower.endsWith('.bsttbp') || lower.endsWith('.tbp')) {
        initialTool = 'tbp_viewer';
      } else if (lower.endsWith('.bstcanva')) {
        initialTool = 'canva_board';
      }
    }
  }

  // Also query Android launch tool via method channel if Android
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      const channel = MethodChannel('com.boardest/launch_args');
      final String? androidTool = await channel.invokeMethod('getLaunchTool');
      if (androidTool != null) {
        initialTool = androidTool;
      }
    } catch (e) {
      debugPrint('Error fetching Android launch tool: $e');
    }
  }

  // Set fullscreen (immersive mode) & lock to landscape for Smartboards
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  runApp(MyApp(
    settings: settings,
    initialTool: initialTool,
    pptFullscreen: pptFullscreen,
    isLoggedIn: currentUser != null,
  ));
}

class MyApp extends StatelessWidget {
  final AppSettings settings;
  final String? initialTool;
  final bool pptFullscreen;
  final bool isLoggedIn;

  const MyApp({
    super.key,
    required this.settings,
    required this.isLoggedIn,
    this.initialTool,
    this.pptFullscreen = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (AppConfig.isToolsMode) {
      home = const BoardestToolsView();
    } else if (AppConfig.isDemoMode) {
      home = DashboardView(initialTool: initialTool, pptFullscreen: pptFullscreen);
    } else if (!settings.isSetupComplete) {
      home = const SetupWizardView();
    } else {
      home = DashboardView(initialTool: initialTool, pptFullscreen: pptFullscreen);
    }

    return MaterialApp(
      title: AppConfig.editionTitle,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
        if (isAndroid) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: const TextScaler.linear(0.8),
            ),
            child: child ?? const SizedBox(),
          );
        }
        return child ?? const SizedBox();
      },
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'SiwonhanSeolreim',
        primaryColor: const Color(0xFF7F5AF0),
        scaffoldBackgroundColor: const Color(0xFF0F0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7F5AF0),
          secondary: Color(0xFF2CB67D),
          surface: Color(0xFF16161A),
          error: Color(0xFFEF4565),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          fontFamily: 'SiwonhanSeolreim',
        ),
      ),
      home: home,
    );
  }
}

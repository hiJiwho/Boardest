import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'models/app_settings.dart';
import 'package:path/path.dart' as p;
import 'services/app_paths.dart';
import 'services/storage_service.dart';
import 'services/bst_save_service.dart';
import 'services/auth_service.dart';
import 'services/system_app_scanner.dart';
import 'services/meal_call_service.dart';
import 'config/app_config.dart';
import 'views/setup_wizard_view.dart';
import 'views/dashboard_view.dart';

void _writeCrashLog(String error, String stackTrace) {
  try {
    final now = DateTime.now().toIso8601String();
    final logContent = '''
======================================================
[Boardest Crash Log]
Timestamp: $now
Error: $error
StackTrace:
$stackTrace
======================================================
\n''';

    final appLog = File(AppPaths.crashLogPath);
    appLog.parent.createSync(recursive: true);
    appLog.writeAsStringSync(logContent, mode: FileMode.append);

    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final exeLog = File(p.join(exeDir, 'crash_logs.txt'));
      exeLog.writeAsStringSync(logContent, mode: FileMode.append);
    }
  } catch (e) {
    debugPrint('Failed to write crash log: $e');
  }
}

void _startWindowsWatchdog() async {
  try {
    final int myPid = pid;
    final String exePath = Platform.resolvedExecutable;
    final String exeDir = File(exePath).parent.path;
    String watchdogExe = p.join(exeDir, 'watchdog.exe');
    if (!await File(watchdogExe).exists()) {
      watchdogExe = p.join(Directory.current.path, 'watchdog.exe');
    }
    if (!await File(watchdogExe).exists()) {
      watchdogExe = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', 'watchdog.exe');
    }
    if (!await File(watchdogExe).exists()) {
      watchdogExe = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Debug', 'watchdog.exe');
    }
    if (!await File(watchdogExe).exists()) {
      watchdogExe = p.join(Directory.current.path, 'build', 'outputs', 'windows', 'Release', 'watchdog.exe');
    }

    if (await File(watchdogExe).exists()) {
      await Process.start(
        watchdogExe,
        ['$myPid', exePath],
        mode: ProcessStartMode.detached,
      );
      debugPrint('[Boardest Watchdog] Background resurrection C# watchdog started for PID $myPid.');
    } else {
      debugPrint('[Boardest Watchdog] C# watchdog executable not found at: $watchdogExe');
    }
  } catch (e) {
    debugPrint('[Boardest Watchdog] Failed to start C# watchdog: $e');
  }
}

void main(List<String> args) async {
  // Catch all unhandled Flutter errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[Boardest Fatal] Unhandled Flutter Error: ${details.exception}');
    _writeCrashLog('FlutterError: ${details.exception}', details.stack?.toString() ?? 'No stacktrace');
  };

  // Catch all unhandled platform/async errors
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[Boardest Fatal] Unhandled Platform Error: $error');
    _writeCrashLog('PlatformError: $error', stack.toString());
    
    return true;
  };

  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  await BstSaveService.instance.ensureStructure();

  // Run automatically on Windows startup to ensure shortcuts exist
  if (Platform.isWindows) {
    SystemAppScanner.createWindowsShortcuts();
    SystemAppScanner.ensureWindowsRunAtStartup();
    _startWindowsWatchdog();
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
      debugPrint("Firebase initialized successfully on supported platform ($defaultTargetPlatform).");
    } catch (e) {
      debugPrint("Firebase initialization failed: $e");
    }
  } else {
    debugPrint("Firebase bypass initialization: Windows/Linux desktop platform is bypassed ($defaultTargetPlatform).");
  }

  final storage = StorageService();
  final AppSettings settings = await storage.loadConfigAndSync();

  if (settings.isSetupComplete) {
    unawaited(MealCallService.instance.ensurePresence(settings));
  }
  final authService = AuthService();
  var currentUser = await authService.getCurrentUser();

  // 자가 치유 및 백그라운드 자동 로그인
  if (settings.isSetupComplete && currentUser == null && !settings.specialClassroomMode) {
    if (settings.selectedSchool != null) {
      try {
        final err = await authService.loginOrSignupClass(
          region: settings.selectedSchool!.region,
          school: settings.selectedSchool!.name,
          grade: settings.selectedGrade,
          classNum: settings.selectedClass,
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
    } else if (arg == '-apps' || arg == '-app_drawer') {
      initialTool = 'app_drawer';
    } else if (arg == '-explorer' || arg == '-file_explorer') {
      initialTool = 'file_explorer';
    }
  }

  // Also query Android launch tool via method channel if Android
  if (Platform.isAndroid) {
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
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

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
    if (!settings.isSetupComplete) {
      home = const SetupWizardView();
    } else {
      home = DashboardView(initialTool: initialTool, pptFullscreen: pptFullscreen);
    }

    return MaterialApp(
      title: 'Boardest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        primaryColor: const Color(0xFF7F5AF0),
        scaffoldBackgroundColor: const Color(0xFF0F0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7F5AF0),
          secondary: Color(0xFF2CB67D),
          surface: Color(0xFF16161A),
          error: Color(0xFFEF4565),
        ),
        textTheme: GoogleFonts.notoSansKrTextTheme(
          ThemeData.dark().textTheme,
        ),
      ),
      home: home,
    );
  }
}

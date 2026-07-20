import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;

import 'models/app_settings.dart';
import 'services/app_paths.dart';
import 'services/storage_service.dart';
import 'services/bst_save_service.dart';
import 'services/context_menu_service.dart';
import 'services/tray_service.dart';
import 'services/comcigan_service.dart';
import 'services/cloud_drive_service.dart';

import 'views/teacher_view.dart';
import 'views/lite_map_dialog.dart';
import 'views/bst_viewer_route.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await acrylic.Window.initialize();
  }
  await AppPaths.init();
  await BstSaveService.instance.ensureStructure();

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
    } else if (arg.startsWith('bst-t://') || arg.startsWith('Bst-t://')) {
      try {
        if (arg.contains('browser-login') || arg.contains('brower-login')) {
          initialTool = 'browser_login';
        } else {
          final uri = Uri.parse(arg);
          final token = uri.queryParameters['token'];
          final email = uri.queryParameters['email'];
          if (token != null && token.isNotEmpty) {
            await CloudDriveService.instance.setSession(
              accessToken: token,
              email: email,
            );
          }
        }
      } catch (_) {}
    }
  }

  // Windows 초기 설정 전에 세팅 및 담임 여부 판단
  final storage = StorageService();
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
          final selectedTeacherSanitized = settings.selectedTeacher.replaceAll('*', '').trim().toUpperCase();
          final homeroomTeacherSanitized = homeroomTeacher.replaceAll('*', '').trim().toUpperCase();
          isHomeroom = selectedTeacherSanitized.isNotEmpty && selectedTeacherSanitized == homeroomTeacherSanitized;
        }
      }
    } catch (_) {}
  }

  if (Platform.isWindows) {
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
          if (initialTool == 'browser_login') {
            unawaited(CloudDriveService.instance.loginWithBrowserOAuth());
          } else {
            await windowManager.show();
          }
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
    if (Platform.isWindows && widget.initialTool != 'lite_map') {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows && widget.initialTool != 'lite_map') {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _reloadSettings() async {
    final storage = StorageService();
    final s = await storage.getSettings() ?? AppSettings();
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
    if (!Platform.isWindows) return;
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
      title: 'Bst Teacher',
      debugShowCheckedModeBanner: false,
      theme: darkTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      home: home,
    );
  }
}

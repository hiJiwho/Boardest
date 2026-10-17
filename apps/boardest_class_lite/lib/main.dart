import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win_wv;
import 'package:win32/win32.dart' show GetSystemMetrics, SM_CXSCREEN, SM_CYSCREEN;
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      backgroundColor: Color(0xFF070B14),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setAsFrameless();
      await windowManager.show();
      await windowManager.focus();
    });
  } else if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boardest Class Lite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00F5D4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ClassLitePage(),
    );
  }
}

/// 창 배치 모드 (hiJiwho/BoardCast 방식)
enum WindowLayoutMode {
  /// 수업시간 감지 자동 전환 (수업시간: 우측 3/4, 쉬는/점심/방과후: 전체화면)
  autoSchedule,

  /// 강제 전체화면 (창틀 없음)
  forceFullscreen,

  /// 강제 수업시간 모드 (우측 3/4 배치)
  forceClassRightThreeQuarters,
}

class ClassLitePage extends StatefulWidget {
  const ClassLitePage({super.key});

  @override
  State<ClassLitePage> createState() => _ClassLitePageState();
}

class _ClassLitePageState extends State<ClassLitePage> {
  static final Uri _siteUri = Uri.parse('https://boardest-class-lite.web.app');

  // Android WebViewController
  WebViewController? _androidWebController;

  // Windows WebviewController (webview_windows)
  win_wv.WebviewController? _windowsWebController;
  bool _windowsWebReady = false;

  bool _isLoading = true;
  String? _loadError;

  // Windows 창 레이아웃 상태 (BoardCast 참조: 평상시 전체화면 / 수업시간 우측 3/4)
  WindowLayoutMode _layoutMode = WindowLayoutMode.autoSchedule;
  bool _isCurrentlyDockedRightThreeQuarters = false;
  bool _isClassTimeDetected = false;
  Timer? _scheduleWatchTimer;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      unawaited(_initializeWindowsWebView());
      _startClassTimeWindowScheduler();
    } else {
      _androidWebController = WebViewController();
      unawaited(_initializeAndroidWebView());
    }
  }

  @override
  void dispose() {
    _scheduleWatchTimer?.cancel();
    _windowsWebController?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // 1. Windows BoardCast-style Window Layout Scheduler (전체화면 vs 수업시간 우측 3/4)
  // ─────────────────────────────────────────────────────────────────

  void _startClassTimeWindowScheduler() {
    // 시작 직후 적용 및 10초마다 수업시간 여부 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_evaluateAndApplyWindowBounds());
    });
    _scheduleWatchTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_evaluateAndApplyWindowBounds());
    });
  }

  /// 현재 시각 및 WebView 내 수업 상태('교시 ... 진행 중')를 함께 확인하여 수업시간 여부 판별
  Future<bool> _detectIsClassTimeNow() async {
    // 1) WebView DOM 텍스트에서 실시간 수업 진행 상태 감지 시도
    if (_windowsWebReady && _windowsWebController != null) {
      try {
        final domResult = await _windowsWebController!.executeScript(
          "(function() { "
          "  const t = document.body ? document.body.innerText : ''; "
          "  if (t.includes('교시') && (t.includes('진행 중') || t.includes('수업 중') || t.includes('종료까지'))) return 'CLASS'; "
          "  if (t.includes('쉬는 시간') || t.includes('점심 시간') || t.includes('점심시간') || t.includes('방과후') || t.includes('아침시간') || t.includes('조회 시간') || t.includes('종례 시간')) return 'BREAK'; "
          "  return 'UNKNOWN'; "
          "})()",
        );
        final statusStr = domResult?.toString().replaceAll('"', '').trim() ?? '';
        if (statusStr == 'CLASS') return true;
        if (statusStr == 'BREAK') return false;
      } catch (_) {}
    }

    // 2) 기본 표준 학교 일과 시간표 기반 수업시간 판별 (평일 월~금)
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }

    final nowMin = now.hour * 60 + now.minute;
    // 표준 중·고교 1~7교시 수업 시간대 (45분 수업, 10분 쉬는시간, 4교시 후 50분 점심시간)
    // 1교시: 08:40~09:25, 2교시: 09:35~10:20, 3교시: 10:30~11:15, 4교시: 11:25~12:10
    // 점심: 12:10~13:00
    // 5교시: 13:00~13:45, 6교시: 13:55~14:40, 7교시: 14:50~15:35
    const classPeriods = <List<int>>[
      [8 * 60 + 40, 9 * 60 + 25],
      [9 * 60 + 35, 10 * 60 + 20],
      [10 * 60 + 30, 11 * 60 + 15],
      [11 * 60 + 25, 12 * 60 + 10],
      [13 * 60 + 0, 13 * 60 + 45],
      [13 * 60 + 55, 14 * 60 + 40],
      [14 * 60 + 50, 15 * 60 + 35],
    ];

    for (final range in classPeriods) {
      if (nowMin >= range[0] && nowMin < range[1]) {
        return true;
      }
    }
    return false;
  }

  Future<void> _evaluateAndApplyWindowBounds({bool forceUpdate = false}) async {
    if (!Platform.isWindows) return;

    final isClass = await _detectIsClassTimeNow();
    bool shouldDockRightThreeQuarters;

    switch (_layoutMode) {
      case WindowLayoutMode.autoSchedule:
        shouldDockRightThreeQuarters = isClass;
        break;
      case WindowLayoutMode.forceFullscreen:
        shouldDockRightThreeQuarters = false;
        break;
      case WindowLayoutMode.forceClassRightThreeQuarters:
        shouldDockRightThreeQuarters = true;
        break;
    }

    if (mounted &&
        (_isClassTimeDetected != isClass ||
            _isCurrentlyDockedRightThreeQuarters != shouldDockRightThreeQuarters)) {
      setState(() {
        _isClassTimeDetected = isClass;
      });
    }

    if (!forceUpdate && _isCurrentlyDockedRightThreeQuarters == shouldDockRightThreeQuarters) {
      return;
    }

    _isCurrentlyDockedRightThreeQuarters = shouldDockRightThreeQuarters;
    await _applyWindowsScreenGeometry(dockRightThreeQuarters: shouldDockRightThreeQuarters);
    if (mounted) setState(() {});
  }

  /// Windows 화면 해상도 기준 창틀 없는 전체화면 또는 우측 3/4 배치 적용
  Future<void> _applyWindowsScreenGeometry({required bool dockRightThreeQuarters}) async {
    if (!Platform.isWindows) return;
    try {
      final screenW = GetSystemMetrics(SM_CXSCREEN).toDouble();
      final screenH = GetSystemMetrics(SM_CYSCREEN).toDouble();

      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setAsFrameless();

      if (dockRightThreeQuarters && screenW > 0 && screenH > 0) {
        await windowManager.setFullScreen(false);
        final targetWidth = (screenW * 0.75).roundToDouble();
        final targetX = screenW - targetWidth; // 좌측 1/4 비우고 우측 3/4 차지
        await windowManager.setBounds(
          Rect.fromLTWH(targetX, 0, targetWidth, screenH),
        );
      } else {
        if (screenW > 0 && screenH > 0) {
          await windowManager.setFullScreen(false);
          await windowManager.setBounds(
            Rect.fromLTWH(0, 0, screenW, screenH),
          );
        } else {
          await windowManager.setFullScreen(true);
        }
      }

      // Web 쪽의 2중 축소 방지 (class_lite_web의 CSS native-docked-class 제어)
      if (_windowsWebReady && _windowsWebController != null) {
        final js = dockRightThreeQuarters
            ? "document.body && document.body.classList.add('native-docked-class');"
            : "document.body && document.body.classList.remove('native-docked-class');";
        try {
          await _windowsWebController!.executeScript(js);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[BoardestClassLite] Window geometry update error: $e');
    }
  }

  void _cycleWindowLayoutMode() {
    setState(() {
      switch (_layoutMode) {
        case WindowLayoutMode.autoSchedule:
          _layoutMode = WindowLayoutMode.forceClassRightThreeQuarters;
          break;
        case WindowLayoutMode.forceClassRightThreeQuarters:
          _layoutMode = WindowLayoutMode.forceFullscreen;
          break;
        case WindowLayoutMode.forceFullscreen:
          _layoutMode = WindowLayoutMode.autoSchedule;
          break;
      }
    });
    unawaited(_evaluateAndApplyWindowBounds(forceUpdate: true));
  }

  // ─────────────────────────────────────────────────────────────────
  // 2. Windows WebView (webview_windows) 초기화
  // ─────────────────────────────────────────────────────────────────

  Future<void> _initializeWindowsWebView() async {
    final controller = win_wv.WebviewController();
    _windowsWebController = controller;
    try {
      await controller.initialize();
      await controller.setBackgroundColor(const Color(0xFF070B14));
      await controller.setPopupWindowPolicy(win_wv.WebviewPopupWindowPolicy.allow);

      controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() {
          _isLoading = state == win_wv.LoadingState.loading;
        });
        if (state == win_wv.LoadingState.navigationCompleted) {
          unawaited(_evaluateAndApplyWindowBounds());
        }
      });

      // WebView WebMessage 수신 (index.html polyfill: window.chrome.webview.postMessage)
      controller.webMessage.listen((rawMessage) {
        _handleIncomingWebMessage(rawMessage);
      });

      await controller.loadUrl(_siteUri.toString());
      if (!mounted) return;
      setState(() {
        _windowsWebReady = true;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.toString();
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // 3. Android WebView (webview_flutter) 초기화
  // ─────────────────────────────────────────────────────────────────

  Future<void> _initializeAndroidWebView() async {
    final controller = _androidWebController!;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(const Color(0xFF0F0E17));
    await controller.addJavaScriptChannel(
      'FlutterChannel',
      onMessageReceived: (JavaScriptMessage msg) {
        _handleIncomingWebMessage(msg.message);
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _isLoading = true;
            _loadError = null;
          });
        },
        onPageFinished: (_) {
          if (!mounted) return;
          setState(() => _isLoading = false);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == false || !mounted) return;
          setState(() {
            _isLoading = false;
            _loadError = error.description;
          });
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null ||
              (uri.scheme != 'https' && request.url != 'about:blank')) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ),
    );

    await controller.loadRequest(_siteUri);
  }

  void _handleIncomingWebMessage(dynamic raw) {
    if (raw == null) return;
    try {
      final text = raw.toString();
      if (text.contains('"type":"appQuit"') || text.contains("'type':'appQuit'")) {
        unawaited(_handleCloseApp());
        return;
      }
      if (text.contains('"type":"setWindowLayout"') || text.contains("'type':'setWindowLayout'")) {
        final isClass = text.contains('"layout":"class"') || text.contains("'layout':'class'");
        if (_layoutMode == WindowLayoutMode.autoSchedule) {
          _isClassTimeDetected = isClass;
          unawaited(_evaluateAndApplyWindowBounds());
        }
      }
    } catch (e) {
      debugPrint('[BoardestClassLite] IPC message handle error: $e');
    }
  }

  Future<void> _reloadWebView() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    if (Platform.isWindows) {
      if (_windowsWebReady && _windowsWebController != null) {
        await _windowsWebController!.reload();
      } else {
        await _initializeWindowsWebView();
      }
    } else if (_androidWebController != null) {
      await _androidWebController!.loadRequest(_siteUri);
    }
  }

  Future<void> _handleBack() async {
    if (Platform.isAndroid && _androidWebController != null) {
      if (await _androidWebController!.canGoBack()) {
        await _androidWebController!.goBack();
      }
      // Android 기본 런처(HOME)로 동작 중일 때는 뒤로가기로 런처가 종료되지 않도록 보호
    }
  }

  Future<void> _handleCloseApp() async {
    if (Platform.isWindows) {
      await windowManager.close();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070B14),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            children: [
              // 1. 메인 경량 WebView 영역
              Positioned.fill(
                child: Platform.isWindows
                    ? (_windowsWebReady && _windowsWebController != null
                        ? win_wv.Webview(_windowsWebController!)
                        : const ColoredBox(color: Color(0xFF070B14)))
                    : (_androidWebController != null
                        ? WebViewWidget(controller: _androidWebController!)
                        : const ColoredBox(color: Color(0xFF070B14))),
              ),

              // 2. 로딩 스플래시 오버레이
              if (_isLoading)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0xFF0F0E17),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image(
                            image: AssetImage('assets/icons/app_logo.png'),
                            width: 84,
                            height: 84,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Boardest Class Lite  v4.0.8',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 20),
                          CircularProgressIndicator(color: Color(0xFF00F5D4)),
                        ],
                      ),
                    ),
                  ),
                ),

              // 3. 오프라인/연결 오류 화면
              if (_loadError case final error?)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121722),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 44, color: Color(0xFFEF4565)),
                        const SizedBox(height: 12),
                        const Text(
                          'Class Lite 사이트에 연결할 수 없습니다.',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white60, fontSize: 12.5),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _reloadWebView,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  ),
                ),

              // 4. 하단 플로팅 제어 바 (BoardCast 스타일: 수업시간 우측 3/4 상태 표시 + 새로고침 + 하단 닫기 버튼)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B111E).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF00F5D4).withValues(alpha: 0.28),
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (Platform.isWindows) ...[
                          InkWell(
                            onTap: _cycleWindowLayoutMode,
                            borderRadius: BorderRadius.circular(999),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isCurrentlyDockedRightThreeQuarters
                                        ? Icons.dock_rounded
                                        : Icons.fullscreen_rounded,
                                    size: 16,
                                    color: const Color(0xFF00F5D4),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _buildLayoutModeLabel(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 16,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            color: Colors.white24,
                          ),
                        ],
                        IconButton(
                          onPressed: _reloadWebView,
                          icon: const Icon(Icons.refresh_rounded, size: 17, color: Colors.white70),
                          tooltip: '새로고침',
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: _handleCloseApp,
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4565).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFEF4565).withValues(alpha: 0.6),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.close_rounded, size: 15, color: Color(0xFFEF4565)),
                                SizedBox(width: 4),
                                Text(
                                  '닫기',
                                  style: TextStyle(
                                    color: Color(0xFFEF4565),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildLayoutModeLabel() {
    switch (_layoutMode) {
      case WindowLayoutMode.autoSchedule:
        return _isCurrentlyDockedRightThreeQuarters
            ? '자동 • 수업시간 (우측 3/4)'
            : '자동 • 쉬는시간 (전체화면)';
      case WindowLayoutMode.forceClassRightThreeQuarters:
        return '수업모드 고정 (우측 3/4)';
      case WindowLayoutMode.forceFullscreen:
        return '전체화면 고정 (100%)';
    }
  }
}

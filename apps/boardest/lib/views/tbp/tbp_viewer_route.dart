import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/tbp_metadata.dart';
import '../../models/board_tools.dart';
import '../../services/tbp/tbp_storage_service.dart';
import '../../services/tbp/tbp_dhash_engine.dart';
import '../../services/tbp/tbp_download_interceptor.dart';
import '../../widgets/annotation_canvas.dart';
import '../../helpers/iframe_view_helper.dart';
import 'tbp_hotspot_overlay.dart';

/// TextBook Plus (TBP) 스마트 교과서 뷰어 (전자칠판 앱 전용)
/// - boadbook 동일 이미지 dHash + 지수 버스트 폴링
/// - Pen / Touch / Smart 3모드 입력 시스템
class TbpViewerRoute extends StatefulWidget {
  final String tbpFilePath;
  final double scaleFactor;

  const TbpViewerRoute({
    super.key,
    required this.tbpFilePath,
    required this.scaleFactor,
  });

  @override
  State<TbpViewerRoute> createState() => _TbpViewerRouteState();
}

class _TbpViewerRouteState extends State<TbpViewerRoute> {
  TbpMetadata? _metadata;
  Map<String, dynamic>? _infoJson;
  String _tbpFolderPath = '';
  bool _isLoading = true;
  String? _errorMessage;

  String _currentDhash = 'default';
  List<Map<String, dynamic>> _currentHotspots = [];

  late final TbpDhashEngine _dhashEngine;

  final WebviewController _winWebview = WebviewController();
  late final WebViewController _androidWebview;
  bool _winWebviewInitialized = false;

  // ─── 입력 모드 ──────────────────────────────────────────
  TbpInputMode _inputMode = TbpInputMode.smart;

  // ─── 판서 ───────────────────────────────────────────────
  final AnnotationController _annotationController = AnnotationController();
  ToolMode _tool = ToolMode.pen;
  Color _penColor = const Color(0xFF8B5CF6);
  double _strokeWidth = 4.0;
  bool _eraseEntireStroke = false;
  double _eraserSize = 30.0;

  // ─── Smart 모드 꾹 누르기 상태 ──────────────────────────
  bool _longPressActive = false;
  final Duration _longPressDuration = const Duration(milliseconds: 500);
  Timer? _longPressTimer;

  final FocusNode _keyboardFocus = FocusNode();

  String _targetUrl = '';

  @override
  void initState() {
    super.initState();
    _annotationController.activeColor = _penColor;
    _annotationController.activeWidth = _strokeWidth;
    _annotationController.toolMode = _tool;
    _annotationController.eraseEntireStroke = _eraseEntireStroke;
    _annotationController.eraserSize = _eraserSize;
    _dhashEngine = TbpDhashEngine(onDhashChanged: _onDhashDetected);
    _loadTbpPackage();
  }

  Future<void> _loadTbpPackage() async {
    try {
      if (widget.tbpFilePath.startsWith('http')) {
        _targetUrl = widget.tbpFilePath;
        if (kIsWeb) {
          setState(() => _isLoading = false);
          return;
        } else if (Platform.isWindows) {
          await _initWindowsWebview(_targetUrl);
        } else {
          _initAndroidWebview(_targetUrl);
        }
        setState(() => _isLoading = false);
        return;
      }

      final meta = await TbpStorageService.instance.loadTbpFile(
        widget.tbpFilePath,
      );
      if (meta == null) {
        setState(() {
          _errorMessage = '.bstTBP 메타데이터 파일 읽기에 실패했습니다.';
          _isLoading = false;
        });
        return;
      }

      _metadata = meta;
      _tbpFolderPath = TbpStorageService.instance.getTbpFolderPath(
        widget.tbpFilePath,
        meta.folderId,
      );
      _infoJson = await TbpStorageService.instance.loadInfoJson(_tbpFolderPath);

      if (_infoJson == null || _infoJson!['webUrl'] == null) {
        setState(() {
          _errorMessage = 'TBP 폴더 내 webUrl 설정이 올바르지 않습니다.';
          _isLoading = false;
        });
        return;
      }

      final targetUrl = _infoJson!['webUrl'] as String;
      _targetUrl = targetUrl;
      if (kIsWeb) {
        setState(() => _isLoading = false);
        return;
      } else if (Platform.isWindows) {
        await _initWindowsWebview(targetUrl);
      } else {
        _initAndroidWebview(targetUrl);
      }

      setState(() => _isLoading = false);

      _dhashEngine.startTracker(
        _winWebviewInitialized ? _winWebview : null,
        Platform.isWindows ? null : _androidWebview,
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'TBP 패키지 로딩 중 오류: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _initWindowsWebview(String url) async {
    try {
      await _winWebview.initialize();
      await _winWebview.setBackgroundColor(Colors.transparent);
      await _winWebview.loadUrl(url);

      _winWebview.webMessage.listen((message) {
        try {
          _dhashEngine.onDhashMessage(message);
          final data = jsonDecode(message);
          if (data['type'] == 'downloadRequest') {
            TbpDownloadInterceptor.instance.handleDownload(
              context: context,
              tbpFolderPath: _tbpFolderPath,
              currentDhash: _currentDhash,
              downloadUrl: data['url'],
              filename: data['filename'],
              scaleFactor: widget.scaleFactor,
            );
          }
        } catch (_) {}
      });

      if (mounted) setState(() => _winWebviewInitialized = true);
    } catch (e) {
      debugPrint('[TbpViewer] Windows webview init error: $e');
    }
  }

  void _initAndroidWebview(String url) {
    _androidWebview = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'TbpChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          try {
            _dhashEngine.onDhashMessage(msg.message);
            final data = jsonDecode(msg.message);
            if (data['type'] == 'downloadRequest') {
              TbpDownloadInterceptor.instance.handleDownload(
                context: context,
                tbpFolderPath: _tbpFolderPath,
                currentDhash: _currentDhash,
                downloadUrl: data['url'],
                filename: data['filename'],
                scaleFactor: widget.scaleFactor,
              );
            }
          } catch (_) {}
        },
      )
      ..loadRequest(Uri.parse(url));
  }

  Future<void> _onDhashDetected(String dHash) async {
    if (_currentDhash == dHash) return;
    _currentDhash = dHash;

    // 판서 저장 후 새 페이지 판서 로드
    // (TBP는 dHash 기반이므로 컨트롤러 재사용 가능)

    final hotspots = await TbpStorageService.instance.loadHotspots(
      _tbpFolderPath,
      dHash,
    );
    if (mounted) setState(() => _currentHotspots = hotspots);
  }

  void _navigatePage(bool isNext) {
    _dhashEngine.navigatePage(isNext: isNext);
  }

  // ─── 입력 모드 판정 ─────────────────────────────────────

  /// 현재 입력 모드 기준 annotation이 활성인지
  bool get _isAnnotationEnabled {
    switch (_inputMode) {
      case TbpInputMode.pen:
        return true;
      case TbpInputMode.touch:
        return false;
      case TbpInputMode.smart:
        return !_longPressActive;
    }
  }

  // ─── Long Press (Smart 모드) ─────────────────────────────

  void _onSmartPointerDown(PointerEvent e) {
    if (_inputMode != TbpInputMode.smart) return;
    // 꾹 누르기 감지 시작
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      if (mounted) setState(() => _longPressActive = true);
    });
  }

  void _onSmartPointerUp(PointerEvent e) {
    _longPressTimer?.cancel();
    if (_longPressActive) {
      if (mounted) setState(() => _longPressActive = false);
    }
  }

  // ─── Keyboard Handler ───────────────────────────────────

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _navigatePage(true);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _navigatePage(false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Timer? _touchDhashTimer;

  void _onPointerDown(PointerDownEvent event) {
    _onSmartPointerDown(event);
    _touchDhashTimer?.cancel();
    _touchDhashTimer = Timer(const Duration(seconds: 1), () {
      _dhashEngine.requestHashNow();
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    _onSmartPointerUp(event);
  }

  @override
  void dispose() {
    _touchDhashTimer?.cancel();
    _dhashEngine.dispose();
    _annotationController.dispose();
    _longPressTimer?.cancel();
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0E17),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00F5D4)),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0E17),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFEF4565),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('뒤로 가기'),
              ),
            ],
          ),
        ),
      );
    }

    final webviewWidget = kIsWeb
        ? getIframeViewWidget('tbp-web-iframe-${_targetUrl.hashCode}', _targetUrl)
        : (Platform.isWindows
            ? (_winWebviewInitialized
                ? Webview(_winWebview)
                : const SizedBox.shrink())
            : WebViewWidget(controller: _androidWebview));

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: (_) => _onSmartPointerUp(const PointerUpEvent()),
        child: Focus(
          focusNode: _keyboardFocus,
          onKeyEvent: _onKeyEvent,
          autofocus: true,
          child: Stack(
            children: [
              // ── 16:9 컨테이너 (WebView + 판서 + 핫스팟) ──
              Positioned.fill(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      children: [
                        // ── WebView 레이어 ──────────────────────────────
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: _isAnnotationEnabled,
                            child: webviewWidget,
                          ),
                        ),

                        // ── 판서 오버레이 ───────────────────────────────
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: !_isAnnotationEnabled,
                            child: Container(
                              color: Colors.transparent,
                              child: AnnotationCanvas(
                                controller: _annotationController,
                                enabled:
                                    _isAnnotationEnabled &&
                                    _tool != ToolMode.pointer,
                                onRightClick: _inputMode == TbpInputMode.touch
                                    ? null
                                    : (pos) {
                                        // 우클릭 핫스팟 생성 (교사용 앱에서만, 전자칠판은 핫스팟 실행만)
                                      },
                              ),
                            ),
                          ),
                        ),

                        // ── 핫스팟 오버레이 ─────────────────────────────
                        Positioned.fill(
                          child: TbpHotspotOverlay(
                            hotspots: _currentHotspots,
                            tbpFolderPath: _tbpFolderPath,
                            currentDhash: _currentDhash,
                            scaleFactor: widget.scaleFactor,
                            inputMode: _inputMode,
                            longPressActive: _longPressActive,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── 상단 컨트롤 바 ─────────────────────────────
              Positioned(
                top: 12 * s,
                left: 16 * s,
                right: 16 * s,
                child: _buildControlBar(s),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlBar(double s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ── 좌측: 뒤로 + 제목 ───────────────────────────────
        _controlContainer(
          s,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
                tooltip: '뒤로',
              ),
              SizedBox(width: 6 * s),
              Text(
                '📖 ${_metadata?.title ?? '교과서'} [${_metadata?.scopeKey ?? ''}]',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14 * s,
                ),
              ),
            ],
          ),
        ),

        // ── 중앙: 페이지 이동 버튼 ─────────────────────────
        _controlContainer(
          s,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.navigate_before_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                tooltip: '이전 페이지 (← ArrowLeft)',
                onPressed: () => _navigatePage(false),
              ),
              IconButton(
                icon: const Icon(
                  Icons.navigate_next_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                tooltip: '다음 페이지 (→ ArrowRight)',
                onPressed: () => _navigatePage(true),
              ),
            ],
          ),
        ),

        // ── 우측: 입력 모드 토글 ────────────────────────────
        _controlContainer(
          s,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modeButton(s, TbpInputMode.pen, '✏️', 'Pen\n(판서 전용)'),
              SizedBox(width: 4 * s),
              _modeButton(s, TbpInputMode.smart, '🧠', 'Smart\n(기본)'),
              SizedBox(width: 4 * s),
              _modeButton(s, TbpInputMode.touch, '👆', 'Touch\n(통과)'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controlContainer(double s, Widget child) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A).withOpacity(0.92),
        borderRadius: BorderRadius.circular(12 * s),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: child,
    );
  }

  Widget _modeButton(double s, TbpInputMode mode, String emoji, String label) {
    final isActive = _inputMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _inputMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF7F5AF0).withOpacity(0.85)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8 * s),
          border: Border.all(
            color: isActive ? const Color(0xFF7F5AF0) : Colors.white24,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: TextStyle(fontSize: 16 * s)),
            Text(
              label,
              style: GoogleFonts.notoSansKr(
                color: isActive ? Colors.white : Colors.white54,
                fontSize: 9 * s,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:path/path.dart' as p;
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../helpers/iframe_view_helper.dart';
import '../models/board_tools.dart';
import '../services/tbp/tbp_dhash_engine.dart';
import '../services/tbp/tbp_download_interceptor.dart';
import '../services/tbp/tbp_storage_service.dart';
import '../widgets/annotation_canvas.dart';
import '../widgets/board_toolbar.dart';
import '../widgets/save_destination_dialog.dart';
import 'tbp/tbp_hotspot_overlay.dart';

/// HTML 기반 모든 프레젠테이션 사이트(Canva, 미리캔버스, Google Slides, Figma, Prezi, Genially, YouTube 등)를
/// TBP와 완벽히 동일한 Dhash 페이지별 판서, 스마트 모드, 핫스팟, 가상 넘기기(PgUp/PgDn)로 지원하는 뷰어 (.HTMLP)
class HtmlPresentView extends StatefulWidget {
  final String? embedUrl;
  final String? title;
  final double scaleFactor;
  final String? initialUrl;
  final String? filePath;
  final bool isTeacherApp;

  const HtmlPresentView({
    super.key,
    this.embedUrl,
    this.title,
    this.scaleFactor = 1.0,
    this.initialUrl,
    this.filePath,
    this.isTeacherApp = false,
  });

  /// 자주 쓰는 프레젠테이션/수업 사이트 URL 및 iframe 코드를 자동으로 임베드(Embed) 가능 URL로 변환
  static String formatPresentUrl(String rawInput) {
    var url = rawInput.trim();
    if (url.isEmpty) return 'https://docs.google.com/presentation';

    // 1. <iframe ... src="..."> 형태 코드가 붙여넣어진 경우 src 속성 자동 추출
    if (url.contains('<iframe') || url.contains('src=')) {
      final srcMatch = RegExp(r'''src\s*=\s*["']([^"']+)["']''', caseSensitive: false).firstMatch(url);
      if (srcMatch != null && srcMatch.group(1) != null) {
        url = srcMatch.group(1)!.trim();
      }
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final segs = uri?.pathSegments.where((e) => e.isNotEmpty).toList() ?? const <String>[];

    // 2. Canva: /design/{id}/{token}/(edit|view|watch) -> /design/{id}/{token}/view?embed
    if (host.contains('canva.com')) {
      final di = segs.indexOf('design');
      if (di >= 0 && segs.length >= di + 3) {
        final id = segs[di + 1];
        final token = segs[di + 2];
        return 'https://www.canva.com/design/$id/$token/view?embed';
      }
      if (di >= 0 && segs.length == di + 2) {
        return 'https://www.canva.com/design/${segs[di + 1]}/view?embed';
      }
      if (!url.contains('embed')) {
        return url.contains('?') ? '$url&embed' : '$url?embed';
      }
      return url;
    }

    // 3. Google Slides / Docs / Forms
    if (host.contains('docs.google.com')) {
      if (url.contains('/presentation/d/')) {
        if (url.contains('/embed') || url.contains('/pubembed')) return url;
        final m = RegExp(r'/presentation/d/([a-zA-Z0-9_-]+)').firstMatch(url);
        if (m != null) {
          return 'https://docs.google.com/presentation/d/${m.group(1)}/embed?start=false&loop=false&delayms=3000';
        }
      }
      if (url.contains('/document/d/') && url.contains('/edit')) {
        return url.replaceAll(RegExp(r'/edit.*$'), '/preview');
      }
      if (url.contains('/spreadsheets/d/') && url.contains('/edit')) {
        return url.replaceAll(RegExp(r'/edit.*$'), '/preview');
      }
      return url;
    }

    // 4. 미리캔버스 (MiriCanvas): miricanvas.com/v/{id}
    if (host.contains('miricanvas.com')) {
      final vi = segs.indexOf('v');
      if (vi >= 0 && segs.length >= vi + 2) {
        return 'https://www.miricanvas.com/v/${segs[vi + 1]}';
      }
      return url;
    }

    // 5. Figma (Figma Slides / Design / Proto / FigJam)
    if (host.contains('figma.com') && !url.contains('figma.com/embed')) {
      return 'https://www.figma.com/embed?embed_host=boardest&url=${Uri.encodeComponent(url)}';
    }

    // 6. Prezi
    if (host.contains('prezi.com')) {
      if (url.contains('/embed/')) return url;
      final pi = segs.indexOf('p');
      if (pi >= 0 && segs.length >= pi + 2 && segs[pi + 1] != 'embed') {
        return 'https://prezi.com/p/embed/${segs[pi + 1]}/';
      }
      final vi = segs.indexOf('v');
      if (vi >= 0 && segs.length >= vi + 2 && segs[vi + 1] != 'embed') {
        final id = segs[vi + 1] == 'view' && segs.length >= vi + 3 ? segs[vi + 2] : segs[vi + 1];
        return 'https://prezi.com/v/embed/$id/';
      }
      return url;
    }

    // 7. Slides.com
    if (host.contains('slides.com') && segs.length >= 2 && segs.last != 'embed' && segs.last != 'fullscreen') {
      return 'https://slides.com/${segs[0]}/${segs[1]}/embed';
    }

    // 8. YouTube (watch?v= / youtu.be / shorts)
    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      if (url.contains('/embed/')) return url;
      String? videoId = uri?.queryParameters['v'];
      if ((videoId == null || videoId.isEmpty) && host.contains('youtu.be') && segs.isNotEmpty) {
        videoId = segs.first;
      } else if ((videoId == null || videoId.isEmpty) && segs.length >= 2 && (segs[0] == 'shorts' || segs[0] == 'live')) {
        videoId = segs[1];
      }
      if (videoId != null && videoId.isNotEmpty) {
        return 'https://www.youtube.com/embed/$videoId?rel=0';
      }
    }

    // 9. Vimeo
    if (host.contains('vimeo.com') && !host.contains('player.vimeo.com') && segs.isNotEmpty) {
      final id = segs.last;
      if (RegExp(r'^\d+$').hasMatch(id)) {
        return 'https://player.vimeo.com/video/$id';
      }
    }

    return url;
  }

  /// URL로부터 사이트 종류 감지 배지 반환
  static String detectSiteLabel(String rawInput) {
    final lower = rawInput.toLowerCase();
    if (lower.contains('canva.com')) return 'Canva';
    if (lower.contains('docs.google.com/presentation')) return 'Google Slides';
    if (lower.contains('docs.google.com')) return 'Google Docs';
    if (lower.contains('miricanvas.com')) return '미리캔버스';
    if (lower.contains('figma.com')) return 'Figma';
    if (lower.contains('prezi.com')) return 'Prezi';
    if (lower.contains('genial.ly') || lower.contains('genially.com')) return 'Genially';
    if (lower.contains('slides.com')) return 'Slides.com';
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) return 'YouTube';
    if (lower.contains('padlet.com')) return 'Padlet';
    return 'HTML Present';
  }

  // 레거시 호환용 별칭 메서드
  static String formatCanvaEmbedUrl(String rawUrl) => formatPresentUrl(rawUrl);

  @override
  State<HtmlPresentView> createState() => _HtmlPresentViewState();
}

/// 레거시 호환을 위한 CanvaBoardView 별칭
typedef CanvaBoardView = HtmlPresentView;

class _HtmlPresentViewState extends State<HtmlPresentView> {
  final AnnotationController _annotationController = AnnotationController();
  final WebviewController _winWebview = WebviewController();
  late final WebViewController _androidWebview;
  late final TbpDhashEngine _dhashEngine;

  bool _isLoading = true;
  bool _winWebviewInitialized = false;
  String? _errorMessage;

  String _targetUrl = '';
  String _displayTitle = 'HTML Present';
  String _projectKey = '';
  String _tbpFolderPath = '';

  String _currentDhash = 'default';
  List<Map<String, dynamic>> _currentHotspots = [];

  // TBP 입력 모드 및 도구
  TbpInputMode _inputMode = TbpInputMode.pen;
  ToolMode _tool = ToolMode.pen;
  Color _penColor = const Color(0xFF00F5D4);
  double _strokeWidth = 4.0;
  ShapeType _activeShape = ShapeType.rectangle;

  Timer? _touchDhashTimer;
  Timer? _autoSavePenTimer;

  bool get _isWebTouchMode =>
      _inputMode == TbpInputMode.touch ||
      _tool == ToolMode.pointer;

  void _handleWebviewHotspotContext(double rx, double ry) {
    // HTMLP mode: Hotspots disabled, annotation-only
    return;
  }

  @override
  void initState() {
    super.initState();
    _displayTitle = widget.title ?? 'HTML Present';
    _dhashEngine = TbpDhashEngine(onDhashChanged: _onDhashDetected);
    _annotationController.activeColor = _penColor;
    _annotationController.activeWidth = _strokeWidth;
    _annotationController.activeShape = _activeShape;
    _annotationController.addListener(_onAnnotationChanged);
    _initProjectAndWebview();
  }

  void _onAnnotationChanged() {
    _scheduleAutoSavePenStrokes();
  }

  String _extractUrlFromRawContent(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';
    try {
      final parsed = jsonDecode(trimmed) as Map<String, dynamic>;
      if (parsed['title'] != null && parsed['title'].toString().trim().isNotEmpty && widget.title == null) {
        _displayTitle = parsed['title'].toString().trim();
      }
      return (parsed['embedUrl'] ?? parsed['url'] ?? parsed['webUrl'] ?? parsed['canvaUrl'] ?? parsed['link'] ?? '').toString().trim();
    } catch (_) {
      if (trimmed.startsWith('http') || trimmed.contains('<iframe')) {
        return trimmed;
      }
    }
    return '';
  }

  Future<void> _initProjectAndWebview() async {
    try {
      var rawUrl = (widget.embedUrl ?? widget.initialUrl ?? '').trim();

      // 파일 경로에서 URL 읽기 지원
      if (rawUrl.isEmpty && widget.filePath != null && widget.filePath!.isNotEmpty) {
        final fp = widget.filePath!.trim();
        if (fp.startsWith('http://') || fp.startsWith('https://') || fp.contains('<iframe')) {
          rawUrl = fp;
        } else if (!kIsWeb) {
          try {
            final f = File(fp);
            if (await f.exists()) {
              final content = await f.readAsString();
              rawUrl = _extractUrlFromRawContent(content);
            }
          } catch (_) {}
        }
      }

      if (rawUrl.isEmpty) {
        setState(() {
          _errorMessage = '프레젠테이션 URL을 찾을 수 없습니다. 올바른 .HTMLP 파일 또는 URL을 열어주세요.';
          _isLoading = false;
        });
        return;
      }

      _targetUrl = HtmlPresentView.formatPresentUrl(rawUrl);

      // 프로젝트 고유 식별키 생성 (URL 해시 기반)
      final safeUrlKey = _targetUrl.replaceAll(RegExp(r'[^\w-]'), '_');
      _projectKey = 'html_present_${safeUrlKey.length > 32 ? safeUrlKey.substring(0, 32) : safeUrlKey}';

      // TBP 가상 프로젝트 등록 (Dhash별 판서 및 핫스팟 보관용)
      _tbpFolderPath = await TbpStorageService.instance.registerCreatedTbpProject(
        meta: {
          'title': _displayTitle,
          'folderId': _projectKey,
          'webUrl': _targetUrl,
          'scopeKey': 'HTMLP',
          'createdAt': DateTime.now().toIso8601String(),
        },
        localDirPath: kIsWeb ? 'web://tbp/$_projectKey' : null,
      );

      // 초기 Dhash ('default') 핫스팟 및 판서 스트로크 로드
      _currentHotspots = await TbpStorageService.instance.loadHotspots(_tbpFolderPath, _currentDhash);
      final initialStrokes = await TbpStorageService.instance.loadPenStrokes(_tbpFolderPath, _currentDhash);
      _annotationController.strokes.clear();
      _annotationController.strokes.addAll(initialStrokes);

      if (kIsWeb) {
        if (mounted) setState(() => _isLoading = false);
        _dhashEngine.startTracker(null, null);
        return;
      } else if (Platform.isWindows) {
        await _initWindowsWebview(_targetUrl);
      } else {
        _initAndroidWebview(_targetUrl);
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }

      _dhashEngine.startTracker(
        _winWebviewInitialized ? _winWebview : null,
        Platform.isWindows ? null : _androidWebview,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'HTML Present 로딩 중 오류 발생: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initWindowsWebview(String url) async {
    try {
      await _winWebview.initialize();
      await _winWebview.setBackgroundColor(Colors.transparent);
      await _winWebview.loadUrl(url);
      await _winWebview.executeScript(_clickerInterceptorJs);

      _winWebview.webMessage.listen((message) {
        try {
          _dhashEngine.onDhashMessage(message);
          final data = jsonDecode(message);
          if (data['type'] == 'downloadRequest') {
            if (mounted) {
              TbpDownloadInterceptor.instance.handleDownload(
                context: context,
                tbpFolderPath: _tbpFolderPath,
                currentDhash: _currentDhash,
                downloadUrl: data['url'],
                filename: data['filename'],
                scaleFactor: widget.scaleFactor,
              );
            }
          }
        } catch (_) {}
      });

      if (mounted) {
        setState(() {
          _winWebviewInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('[HtmlPresentView] Windows webview init error: $e');
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
          } catch (_) {}
        },
      )
      ..loadRequest(Uri.parse(url));
  }

  void _scheduleAutoSavePenStrokes() {
    _autoSavePenTimer?.cancel();
    _autoSavePenTimer = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted) return;
      try {
        await TbpStorageService.instance.savePenStrokes(
          _tbpFolderPath,
          _currentDhash,
          _annotationController.strokes,
        );
        debugPrint('[HtmlPresentView] Auto-saved pen strokes for dhash: $_currentDhash');
      } catch (e) {
        debugPrint('[HtmlPresentView] Auto-save pen strokes error: $e');
      }
    });
  }

  void _onDhashDetected(String dHash) async {
    if (dHash.isEmpty || dHash == _currentDhash) return;

    final prevDhash = _currentDhash;
    final prevStrokes = List<AnnotationStroke>.from(_annotationController.strokes);
    final prevHotspots = List<Map<String, dynamic>>.from(_currentHotspots);

    // 이전 페이지 판서 자동 저장
    if (_tbpFolderPath.isNotEmpty) {
      await TbpStorageService.instance.savePenStrokes(
        _tbpFolderPath,
        prevDhash,
        prevStrokes,
      );
    }

    _currentDhash = dHash;
    var hotspots = await TbpStorageService.instance.loadHotspots(_tbpFolderPath, dHash);
    var strokes = await TbpStorageService.instance.loadPenStrokes(_tbpFolderPath, dHash);

    if (prevDhash == 'default') {
      if (strokes.isEmpty && prevStrokes.isNotEmpty) {
        strokes = prevStrokes;
        await TbpStorageService.instance.savePenStrokes(_tbpFolderPath, dHash, strokes);
      }
      if (hotspots.isEmpty && prevHotspots.isNotEmpty) {
        hotspots = prevHotspots;
        await TbpStorageService.instance.saveHotspots(_tbpFolderPath, dHash, hotspots);
      }
    }

    if (mounted) {
      setState(() {
        _currentHotspots = hotspots;
      });
      _annotationController.strokes.clear();
      _annotationController.strokes.addAll(strokes);
    }
  }

  void _sendVirtualKey(String key, int keyCode) {
    // Canva 및 웹 프레젠테이션 호환: PageDown/PageUp을 한 장씩 넘기는 ArrowRight/ArrowLeft로 완전 매핑
    final effectiveKey = (key == 'PageDown')
        ? 'ArrowRight'
        : (key == 'PageUp')
            ? 'ArrowLeft'
            : key;
    final effectiveCode = (key == 'PageDown')
        ? 39
        : (key == 'PageUp')
            ? 37
            : keyCode;

    final script = '''
      (function() {
        const target = document.activeElement || document.body;
        ['keydown', 'keyup'].forEach(function(type) {
          const evt = new KeyboardEvent(type, {
            key: '$effectiveKey',
            code: '$effectiveKey',
            keyCode: $effectiveCode,
            which: $effectiveCode,
            bubbles: true,
            cancelable: true
          });
          target.dispatchEvent(evt);
          window.dispatchEvent(evt);
          document.dispatchEvent(evt);
        });
      })();
    ''';
    if (!kIsWeb && Platform.isWindows && _winWebviewInitialized) {
      _winWebview.executeScript(script);
    } else if (!kIsWeb && !Platform.isWindows) {
      _androidWebview.runJavaScript(script);
    }
  }

  void _navigatePage({required bool isNext}) {
    _sendVirtualKey(isNext ? 'PageDown' : 'PageUp', isNext ? 34 : 33);
    _dhashEngine.navigatePage(isNext: isNext);
  }

  static const String _clickerInterceptorJs = '''
    (function() {
      if (window.__boardbook_clicker_hooked) return;
      window.__boardbook_clicker_hooked = true;

      function interceptClicker(e) {
        if (e.key === 'PageDown' || e.keyCode === 34) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          if (e.type === 'keydown') {
            const target = document.activeElement || document.body;
            ['keydown', 'keyup'].forEach(function(type) {
              const evt = new KeyboardEvent(type, {
                key: 'ArrowRight',
                code: 'ArrowRight',
                keyCode: 39,
                which: 39,
                bubbles: true,
                cancelable: true
              });
              target.dispatchEvent(evt);
              window.dispatchEvent(evt);
            });
          }
        } else if (e.key === 'PageUp' || e.keyCode === 33) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          if (e.type === 'keydown') {
            const target = document.activeElement || document.body;
            ['keydown', 'keyup'].forEach(function(type) {
              const evt = new KeyboardEvent(type, {
                key: 'ArrowLeft',
                code: 'ArrowLeft',
                keyCode: 37,
                which: 37,
                bubbles: true,
                cancelable: true
              });
              target.dispatchEvent(evt);
              window.dispatchEvent(evt);
            });
          }
        }
      }

      window.addEventListener('keydown', interceptClicker, true);
      window.addEventListener('keyup', interceptClicker, true);
      document.addEventListener('keydown', interceptClicker, true);
      document.addEventListener('keyup', interceptClicker, true);
    })();
  ''';

  void _onPointerDown(PointerDownEvent event) {
    _touchDhashTimer?.cancel();
    _touchDhashTimer = Timer(const Duration(milliseconds: 450), () {
      _dhashEngine.navigatePage(isNext: true);
    });
  }

  @override
  void dispose() {
    _annotationController.removeListener(_onAnnotationChanged);
    _autoSavePenTimer?.cancel();
    _touchDhashTimer?.cancel();
    _dhashEngine.dispose();
    if (!kIsWeb && Platform.isWindows) {
      _winWebview.dispose();
    }
    super.dispose();
  }

  Widget _buildInputModeChip(TbpInputMode mode, String label, double s) {
    final isSelected = _inputMode == mode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16 * s),
        onTap: () {
          setState(() {
            _inputMode = mode;
            if (mode == TbpInputMode.touch) {
              _tool = ToolMode.pointer;
            } else if (_tool == ToolMode.pointer) {
              _tool = ToolMode.pen;
              _annotationController.toolMode = ToolMode.pen;
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 5 * s),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00F5D4) : Colors.transparent,
            borderRadius: BorderRadius.circular(16 * s),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white70,
              fontSize: 11 * s,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0E17),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF00F5D4)),
              SizedBox(height: 16),
              Text(
                '⚡ HTML Present 불러오는 중...',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
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
              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4565), size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 16)),
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
        ? getIframeViewWidget('html-present-iframe-${_targetUrl.hashCode}', _targetUrl)
        : (Platform.isWindows
            ? (_winWebviewInitialized ? Webview(_winWebview) : const SizedBox.shrink())
            : WebViewWidget(controller: _androidWebview));

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        child: Stack(
          children: [
            // ── 16:9 메인 프레젠테이션 컨테이너 ──
            Positioned.fill(
              child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cWidth = constraints.maxWidth > 0 ? constraints.maxWidth : MediaQuery.of(context).size.width;
                      final cHeight = constraints.maxHeight > 0 ? constraints.maxHeight : MediaQuery.of(context).size.height;

                      void openHotspotModalAt(Offset pos) {
                        if (_inputMode == TbpInputMode.pen) return;
                        final rx = (pos.dx / cWidth).clamp(0.02, 0.98);
                        final ry = (pos.dy / cHeight).clamp(0.02, 0.98);
                        _handleWebviewHotspotContext(rx, ry);
                      }

                      return Stack(
                        children: [
                          // 1. Webview 메인 영역
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onSecondaryTapDown: (details) {
                                if (_inputMode != TbpInputMode.pen) {
                                  openHotspotModalAt(details.localPosition);
                                }
                              },
                              child: Listener(
                                behavior: HitTestBehavior.translucent,
                                onPointerDown: (e) {
                                  if (e.buttons == 2 && _inputMode != TbpInputMode.pen) {
                                    openHotspotModalAt(e.localPosition);
                                  }
                                },
                                child: webviewWidget,
                              ),
                            ),
                          ),

                          // 2. 스마트 판서 캔버스 레이어
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: _isWebTouchMode,
                              child: AnnotationCanvas(
                                controller: _annotationController,
                                enabled: !_isWebTouchMode,
                                onRightClick: _inputMode != TbpInputMode.pen ? openHotspotModalAt : null,
                              ),
                            ),
                          ),

                          // 3. 모듈화된 핫스팟 오버레이 핀 레이어
                          Positioned.fill(
                            child: TbpHotspotOverlay(
                              hotspots: _currentHotspots,
                              tbpFolderPath: _tbpFolderPath,
                              currentDhash: _currentDhash,
                              scaleFactor: widget.scaleFactor,
                              inputMode: _inputMode,
                              longPressActive: false,
                              onHotspotsUpdated: (updated) {
                                setState(() {
                                  _currentHotspots = updated;
                                });
                                TbpStorageService.instance.saveHotspots(_tbpFolderPath, _currentDhash, updated);
                              },
                            ),
                          ),

                          // 4. 가상 슬라이드 넘기기 버튼 (좌: PgUp, 우: PgDn)
                          Positioned(
                            left: 12 * s,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: PointerInterceptor(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(24 * s),
                                    onTap: () {
                                      _sendVirtualKey('PageUp', 33);
                                      _dhashEngine.navigatePage(isNext: false);
                                    },
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 14 * s),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF16161A).withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(24 * s),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.35),
                                            blurRadius: 10,
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.arrow_back_ios_new_rounded, size: 16 * s, color: Colors.white),
                                          SizedBox(height: 4 * s),
                                          Text('PgUp', style: TextStyle(color: Colors.white70, fontSize: 9 * s, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          Positioned(
                            right: 12 * s,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: PointerInterceptor(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(24 * s),
                                    onTap: () {
                                      _sendVirtualKey('PageDown', 34);
                                      _dhashEngine.navigatePage(isNext: true);
                                    },
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 14 * s),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF16161A).withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(24 * s),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.35),
                                            blurRadius: 10,
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.arrow_forward_ios_rounded, size: 16 * s, color: Colors.white),
                                          SizedBox(height: 4 * s),
                                          Text('PgDn', style: TextStyle(color: Colors.white70, fontSize: 9 * s, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
            ),

            // ── 상단 타이틀 & 툴바 ──
            Positioned(
              top: 12 * s,
              left: 16 * s,
              right: 16 * s,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PointerInterceptor(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 8 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(24 * s),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                            onPressed: () async {
                              if (_annotationController.strokes.isNotEmpty) {
                                await TbpStorageService.instance.savePenStrokes(
                                  _tbpFolderPath,
                                  _currentDhash,
                                  _annotationController.strokes,
                                );
                              }
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),
                          SizedBox(width: 8 * s),
                          Text(
                            '🌐 $_displayTitle [${HtmlPresentView.detectSiteLabel(_targetUrl)}]',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15 * s,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 3모드 스위처 (마우스 / 스마트 / 주석)
                  PointerInterceptor(
                    child: Container(
                      padding: EdgeInsets.all(4 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20 * s),
                        border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          _buildInputModeChip(TbpInputMode.touch, '🖱️ 마우스', s),
                          _buildInputModeChip(TbpInputMode.smart, '⚡ 스마트', s),
                          _buildInputModeChip(TbpInputMode.pen, '✏️ 주석', s),
                        ],
                      ),
                    ),
                  ),

                  // 이전/다음 슬라이드 & 핫스팟 추가 & .HTMLP 저장
                  PointerInterceptor(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 6 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(30 * s),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.navigate_before_rounded, color: Colors.white, size: 28),
                            tooltip: '이전 페이지 (PgUp)',
                            onPressed: () {
                              _sendVirtualKey('PageUp', 33);
                              _dhashEngine.navigatePage(isNext: false);
                            },
                          ),
                          SizedBox(width: 4 * s),
                          IconButton(
                            icon: const Icon(Icons.navigate_next_rounded, color: Colors.white, size: 28),
                            tooltip: '다음 페이지 (PgDn)',
                            onPressed: () {
                              _sendVirtualKey('PageDown', 34);
                              _dhashEngine.navigatePage(isNext: true);
                            },
                          ),
                          SizedBox(width: 8 * s),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                            label: Text(
                              '+ 핫스팟',
                              style: GoogleFonts.notoSansKr(fontSize: 12 * s, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00F5D4),
                              foregroundColor: Colors.black,
                              padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * s)),
                            ),
                            onPressed: () {
                              final offsetCount = _currentHotspots.length;
                              final rx = (0.2 + (offsetCount % 5) * 0.14).clamp(0.1, 0.88);
                              final ry = (0.22 + (offsetCount ~/ 5) * 0.14).clamp(0.15, 0.82);
                              _handleWebviewHotspotContext(rx, ry);
                            },
                          ),
                          SizedBox(width: 8 * s),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.save_rounded, size: 16),
                            label: Text(
                              'HTMLP 저장',
                              style: GoogleFonts.notoSansKr(fontSize: 12 * s, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7F5AF0),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * s)),
                            ),
                            onPressed: () async {
                              if (_tbpFolderPath.isNotEmpty && _currentDhash.isNotEmpty) {
                                await TbpStorageService.instance.savePenStrokes(
                                  _tbpFolderPath,
                                  _currentDhash,
                                  _annotationController.strokes,
                                );
                              }
                              if (!context.mounted) return;
                              final result = await SaveDestinationDialog.show(
                                context: context,
                                scaleFactor: widget.scaleFactor,
                                title: '💾 HTML Present (.HTMLP) 저장',
                                subTitle: '프레젠테이션 파일(.HTMLP)을 어디에 저장하시겠습니까?',
                              );
                              if (result != null) {
                                final safeName = _displayTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
                                final fileName = safeName.toUpperCase().endsWith('.HTMLP') ? safeName : '$safeName.HTMLP';
                                if (!kIsWeb) {
                                  final outFile = File(p.join(result.targetDirectory.path, fileName));
                                  await outFile.writeAsString(jsonEncode({
                                    'type': 'boardest_html_present',
                                    'title': _displayTitle,
                                    'url': _targetUrl,
                                    'embedUrl': _targetUrl,
                                    'createdAt': DateTime.now().toIso8601String(),
                                  }));
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('✅ [$fileName] 파일이 저장되었습니다!'),
                                      backgroundColor: const Color(0xFF2CB67D),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── 하단 스마트 판서 툴바 (BoardDockToolbar) ──
            Positioned(
              bottom: 16 * s,
              left: 0,
              right: 0,
              child: Center(
                child: PointerInterceptor(
                  child: BoardDockToolbar(
                    scale: widget.scaleFactor,
                    tool: _tool,
                    activeShape: _activeShape,
                    onShapeChanged: (sh) {
                      setState(() {
                        _activeShape = sh;
                        _annotationController.activeShape = sh;
                      });
                    },
                    onToolChanged: (tool) {
                      setState(() {
                        _tool = tool;
                        _annotationController.toolMode = tool;
                        if (tool == ToolMode.pointer) {
                          _inputMode = TbpInputMode.touch;
                        } else if (_inputMode == TbpInputMode.touch) {
                          _inputMode = TbpInputMode.smart;
                        }
                      });
                    },
                    penColor: _penColor,
                    onColorChanged: (c) {
                      setState(() {
                        _penColor = c;
                        _annotationController.activeColor = c;
                      });
                    },
                    strokeWidth: _strokeWidth,
                    onStrokeWidthChanged: (w) {
                      setState(() {
                        _strokeWidth = w;
                        _annotationController.activeWidth = w;
                      });
                    },
                    onUndo: () => _annotationController.undo(),
                    onClear: () {
                      _annotationController.clear();
                      if (_tbpFolderPath.isNotEmpty) {
                        TbpStorageService.instance.savePenStrokes(
                          _tbpFolderPath,
                          _currentDhash,
                          [],
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
import 'package:url_launcher/url_launcher.dart';

import '../helpers/iframe_view_helper.dart';
import '../models/board_tools.dart';
import '../models/tbp_metadata.dart';
import '../services/cloud_drive_service.dart';
import '../services/tbp/tbp_dhash_engine.dart';
import '../services/tbp/tbp_download_interceptor.dart';
import '../services/tbp/tbp_storage_service.dart';
import '../widgets/annotation_canvas.dart';
import 'tbp/tbp_hotspot_overlay.dart';

/// HTML 기반 모든 프레젠테이션 사이트(Canva, 미리캔버스, Google Slides, Genially 등)를
/// TBP와 완벽히 동일한 Dhash 페이지별 판서, 스마트 모드, 핫스팟, 가상 넘기기(PgUp/PgDn)로 지원하는 뷰어
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
    this.isTeacherApp = true,
  });

  /// Canva, 구글 슬라이드 등의 임베드 URL 자동 정규화
  static String formatPresentUrl(String rawUrl) {
    var url = rawUrl.trim();
    if (url.isEmpty) return 'https://www.canva.com';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    // Canva URL 포맷팅: /design/{id}/{token}/(edit|view|watch...) → 공개 임베드 뷰
    // (edit/utm 등 쿼리가 붙은 주소는 비공개 편집 화면이라 403이 발생함)
    if (url.contains('canva.com')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        final segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();
        final di = segs.indexOf('design');
        if (di >= 0 && segs.length >= di + 3) {
          final id = segs[di + 1];
          final token = segs[di + 2];
          return 'https://www.canva.com/design/$id/$token/view?embed';
        }
        if (di >= 0 && segs.length == di + 2) {
          return 'https://www.canva.com/design/${segs[di + 1]}/view?embed';
        }
      }
      if (url.contains('/view?embed')) return url;
      return url;
    }

    // Google Slides URL 포맷팅 (/pub?start=false&loop=false&delayms=3000)
    if (url.contains('docs.google.com/presentation') && url.contains('/edit')) {
      return url.replaceAll(RegExp(r'/edit.*$'), '/embed?start=false&loop=false');
    }

    return url;
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
  String _projectKey = '';
  String _tbpFolderPath = '';

  String _currentDhash = 'default';
  List<Map<String, dynamic>> _currentHotspots = [];

  // TBP 입력 모드 및 도구
  TbpInputMode _inputMode = TbpInputMode.smart;
  ToolMode _tool = ToolMode.pen;
  Color _penColor = const Color(0xFF00F5D4);
  double _strokeWidth = 4.0;

  Timer? _touchDhashTimer;
  Timer? _autoSavePenTimer;
  Timer? _activeSpotTimer;
  int? _spotTimerRemaining;

  @override
  void initState() {
    super.initState();
    _dhashEngine = TbpDhashEngine(onDhashChanged: _onDhashDetected);
    _annotationController.onStrokesChanged = _scheduleAutoSavePenStrokes;
    _annotationController.activeColor = _penColor;
    _annotationController.activeWidth = _strokeWidth;
    _initProjectAndWebview();
  }

  Future<void> _initProjectAndWebview() async {
    try {
      var rawUrl = widget.embedUrl ?? widget.initialUrl ?? '';

      // 파일에서 URL 읽기 지원
      if (rawUrl.isEmpty && widget.filePath != null && widget.filePath!.isNotEmpty) {
        try {
          final f = File(widget.filePath!);
          if (await f.exists()) {
            final content = await f.readAsString();
            try {
              final parsed = jsonDecode(content) as Map<String, dynamic>;
              rawUrl = (parsed['embedUrl'] ?? parsed['url'] ?? parsed['canvaUrl'] ?? parsed['link'] ?? '').toString();
            } catch (_) {
              if (content.trim().startsWith('http')) {
                rawUrl = content.trim();
              }
            }
          }
        } catch (_) {}
      }

      if (rawUrl.isEmpty) {
        rawUrl = 'https://www.canva.com';
      }

      _targetUrl = HtmlPresentView.formatPresentUrl(rawUrl);

      // 프로젝트 고유 식별키 생성 (URL 해시 기반)
      final safeUrlKey = _targetUrl.replaceAll(RegExp(r'[^\w-]'), '_');
      _projectKey = 'html_present_${safeUrlKey.length > 32 ? safeUrlKey.substring(0, 32) : safeUrlKey}';

      // TBP 가상 프로젝트 등록 (Dhash별 판서 및 핫스팟 보관용)
      _tbpFolderPath = await TbpStorageService.instance.registerCreatedTbpProject(
        meta: {
          'title': widget.title ?? 'HTML Present',
          'folderId': _projectKey,
          'webUrl': _targetUrl,
          'scopeKey': 'HTML',
          'createdAt': DateTime.now().toIso8601String(),
        },
        localDirPath: kIsWeb ? 'web://tbp/$_projectKey' : null,
      );

      // 초기 Dhash ('default') 핫스팟 및 판서 스트로크 로드
      _currentHotspots = await TbpStorageService.instance.loadHotspots(_tbpFolderPath, _currentDhash);
      final initialStrokes = await TbpStorageService.instance.loadPenStrokes(_tbpFolderPath, _currentDhash);
      _annotationController.setStrokes(initialStrokes);

      if (kIsWeb) {
        if (mounted) setState(() => _isLoading = false);
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

      _winWebview.webMessage.listen((message) {
        try {
          _dhashEngine.onDhashMessage(message);
          final data = jsonDecode(message);
          if (data['type'] == 'dhashUpdated') {
            _onDhashDetected(data['dhash']);
          } else if (data['type'] == 'downloadRequest') {
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
            final data = jsonDecode(msg.message);
            if (data['type'] == 'dhashUpdated') {
              _onDhashDetected(data['dhash']);
            }
          } catch (_) {}
        },
      )
      ..loadRequest(Uri.parse(url));
  }

  void _scheduleAutoSavePenStrokes() {
    _autoSavePenTimer?.cancel();
    _autoSavePenTimer = Timer(const Duration(milliseconds: 1000), () async {
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
    if (dHash == _currentDhash) return;

    // 이전 페이지 판서 자동 저장
    if (_annotationController.strokes.isNotEmpty) {
      await TbpStorageService.instance.savePenStrokes(
        _tbpFolderPath,
        _currentDhash,
        _annotationController.strokes,
      );
    }

    _currentDhash = dHash;
    final hotspots = await TbpStorageService.instance.loadHotspots(_tbpFolderPath, dHash);
    final strokes = await TbpStorageService.instance.loadPenStrokes(_tbpFolderPath, dHash);

    if (mounted) {
      setState(() {
        _currentHotspots = hotspots;
      });
      _annotationController.setStrokes(strokes);
    }
  }

  void _sendVirtualKey(String key, int keyCode) {
    final script = '''
      (function() {
        const target = document.activeElement || document.body;
        const downEvt = new KeyboardEvent('keydown', {
          key: '$key',
          code: '$key',
          keyCode: $keyCode,
          which: $keyCode,
          bubbles: true,
          cancelable: true
        });
        target.dispatchEvent(downEvt);
        window.dispatchEvent(downEvt);

        const upEvt = new KeyboardEvent('keyup', {
          key: '$key',
          code: '$key',
          keyCode: $keyCode,
          which: $keyCode,
          bubbles: true,
          cancelable: true
        });
        target.dispatchEvent(upEvt);
        window.dispatchEvent(upEvt);

        // Fallback arrow keys for presentation frameworks (Canva, Slides, etc)
        if ('$key' === 'PageDown' || '$key' === 'PageUp') {
          const arrowKey = '$key' === 'PageDown' ? 'ArrowRight' : 'ArrowLeft';
          const arrowCode = '$key' === 'PageDown' ? 39 : 37;
          const aEvt = new KeyboardEvent('keydown', {
            key: arrowKey,
            code: arrowKey,
            keyCode: arrowCode,
            which: arrowCode,
            bubbles: true,
            cancelable: true
          });
          target.dispatchEvent(aEvt);
          window.dispatchEvent(aEvt);
        }
      })();
    ''';
    if (!kIsWeb && Platform.isWindows && _winWebviewInitialized) {
      _winWebview.executeScript(script);
    } else if (!kIsWeb && !Platform.isWindows) {
      _androidWebview.runJavaScript(script);
    }
  }

  void _triggerHotspot(Map<String, dynamic> spot) async {
    final type = (spot['type'] ?? 'url').toString();
    final val = (spot['value'] ?? '').toString().trim();
    final title = (spot['title'] ?? spot['name'] ?? '핫스팟').toString();
    if (val.isEmpty) return;

    switch (type) {
      case 'url':
        final urlStr = (val.startsWith('http://') || val.startsWith('https://')) ? val : 'https://$val';
        await launchUrl(Uri.parse(urlStr), mode: LaunchMode.externalApplication);
        break;
      case 'memo':
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF16161A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Text('📌 ', style: TextStyle(fontSize: 20)),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Text(
              val,
              style: GoogleFonts.notoSansKr(color: const Color(0xFFE2E8F0), fontSize: 14, height: 1.6),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기', style: TextStyle(color: Color(0xFF00F5D4), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        break;
      case 'timer':
        final secs = int.tryParse(val) ?? 180;
        _activeSpotTimer?.cancel();
        setState(() => _spotTimerRemaining = secs);
        _activeSpotTimer = Timer.periodic(const Duration(seconds: 1), (tm) {
          if (!mounted) {
            tm.cancel();
            return;
          }
          if ((_spotTimerRemaining ?? 0) <= 1) {
            tm.cancel();
            setState(() => _spotTimerRemaining = null);
          } else {
            setState(() => _spotTimerRemaining = (_spotTimerRemaining ?? 0) - 1);
          }
        });
        break;
      default:
        TbpDownloadInterceptor.instance.openSupportedViewer(
          context: context,
          filePath: val,
          scaleFactor: widget.scaleFactor,
        );
        break;
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _touchDhashTimer?.cancel();
    _touchDhashTimer = Timer(const Duration(seconds: 1), () {
      _dhashEngine.requestHashNow();
    });
  }

  @override
  void dispose() {
    _autoSavePenTimer?.cancel();
    _touchDhashTimer?.cancel();
    _activeSpotTimer?.cancel();
    _dhashEngine.dispose();
    if (!kIsWeb && Platform.isWindows) {
      _winWebview.dispose();
    }
    super.dispose();
  }

  Widget _buildInputModeChip(TbpInputMode mode, String label, double s) {
    final isSelected = _inputMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _inputMode = mode;
          if (mode == TbpInputMode.touch) {
            _tool = ToolMode.pointer;
          } else if (mode == TbpInputMode.pen && _tool == ToolMode.pointer) {
            _tool = ToolMode.pen;
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
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cWidth = constraints.maxWidth > 0 ? constraints.maxWidth : MediaQuery.of(context).size.width;
                      final cHeight = constraints.maxHeight > 0 ? constraints.maxHeight : MediaQuery.of(context).size.height;

                      void openHotspotModalAt(Offset pos) {
                        final rx = (pos.dx / cWidth).clamp(0.02, 0.98);
                        final ry = (pos.dy / cHeight).clamp(0.02, 0.98);
                        TbpHotspotOverlay.showAddHotspotModal(
                          context,
                          rx,
                          ry,
                          _tbpFolderPath,
                          _currentDhash,
                          _currentHotspots,
                          (updated) {
                            setState(() {
                              _currentHotspots = updated;
                            });
                          },
                        );
                      }

                      return Stack(
                        children: [
                          // 1. Webview 메인 영역 (터치 모드일 때 우클릭 감지 지원)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onSecondaryTapDown: (d) => openHotspotModalAt(d.localPosition),
                              child: webviewWidget,
                            ),
                          ),

                          // 2. 스마트 판서 캔버스 레이어
                          Positioned.fill(
                            child: AnnotationCanvas(
                              controller: _annotationController,
                              enabled: _inputMode != TbpInputMode.touch && _tool != ToolMode.pointer,
                              onRightClick: openHotspotModalAt,
                              onLongPressClick: (pos) {
                                final x = pos.dx.toInt();
                                final y = pos.dy.toInt();
                                final script = '''
                                (function() {
                                  const el = document.elementFromPoint($x, $y);
                                  if (el) {
                                    const evt = new MouseEvent('click', {
                                      bubbles: true,
                                      cancelable: true,
                                      clientX: $x,
                                      clientY: $y
                                    });
                                    el.dispatchEvent(evt);
                                    if (typeof el.click === 'function') el.click();
                                  }
                                })();
                              ''';
                                if (!kIsWeb && Platform.isWindows && _winWebviewInitialized) {
                                  _winWebview.executeScript(script);
                                } else if (!kIsWeb && !Platform.isWindows) {
                                  _androidWebview.runJavaScript(script);
                                }
                              },
                            ),
                          ),

                          // 3. 모듈화된 핫스팟 오버레이 핀 레이어
                          Positioned.fill(
                            child: TbpHotspotOverlay(
                              hotspots: _currentHotspots,
                              tbpFolderPath: _tbpFolderPath,
                              currentDhash: _currentDhash,
                              scaleFactor: widget.scaleFactor,
                              isTeacherApp: widget.isTeacherApp,
                              onTriggerHotspot: _triggerHotspot,
                              onHotspotsUpdated: (updated) {
                                setState(() {
                                  _currentHotspots = updated;
                                });
                              },
                            ),
                          ),

                          // 4. 가상 슬라이드 넘기기 버튼 (좌: PgUp, 우: PgDn)
                          Positioned(
                            left: 12 * s,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: PointerInterceptor(child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(24 * s),
                                  onTap: () => _sendVirtualKey('PageUp', 33),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 14 * s),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF16161A).withOpacity(0.65),
                                      borderRadius: BorderRadius.circular(24 * s),
                                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.35),
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
                              )),
                            ),
                          ),

                          Positioned(
                            right: 12 * s,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: PointerInterceptor(child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(24 * s),
                                  onTap: () => _sendVirtualKey('PageDown', 34),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 14 * s),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF16161A).withOpacity(0.65),
                                      borderRadius: BorderRadius.circular(24 * s),
                                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.35),
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
                              )),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            // 활동 타이머 오버레이
            if (_spotTimerRemaining != null)
              Positioned(
                bottom: 72 * s,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 22 * s, vertical: 10 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(36 * s),
                      border: Border.all(color: const Color(0xFF00F5D4), width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('⏱️ ', style: TextStyle(fontSize: 20 * s)),
                        Text(
                          '${((_spotTimerRemaining ?? 0) ~/ 60).toString().padLeft(2, '0')}:${((_spotTimerRemaining ?? 0) % 60).toString().padLeft(2, '0')}',
                          style: GoogleFonts.outfit(
                            color: (_spotTimerRemaining ?? 0) <= 10 ? const Color(0xFFEF4565) : Colors.white,
                            fontSize: 26 * s,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 10 * s),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white54),
                          onPressed: () {
                            _activeSpotTimer?.cancel();
                            setState(() => _spotTimerRemaining = null);
                          },
                        ),
                      ],
                    ),
                  ),
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
                  PointerInterceptor(child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 8 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.9),
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
                          '✨ ${widget.title ?? 'HTML Present'}',
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15 * s,
                          ),
                        ),
                      ],
                    ),
                  )),

                  // 3모드 스위처 (마우스 / 스마트 / 주석)
                  PointerInterceptor(child: Container(
                    padding: EdgeInsets.all(4 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20 * s),
                      border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        _buildInputModeChip(TbpInputMode.touch, '🖱️ 마우스', s),
                        _buildInputModeChip(TbpInputMode.smart, '⚡ 스마트', s),
                        _buildInputModeChip(TbpInputMode.pen, '✏️ 주석', s),
                      ],
                    ),
                  )),

                  // 이전/다음 슬라이드 & 핫스팟 추가
                  PointerInterceptor(child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 6 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.9),
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
                            TbpHotspotOverlay.showAddHotspotModal(
                              context,
                              0.5,
                              0.5,
                              _tbpFolderPath,
                              _currentDhash,
                              _currentHotspots,
                              (updated) => setState(() => _currentHotspots = updated),
                            );
                          },
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:path/path.dart' as p;
import '../../models/board_tools.dart';
import '../../models/tbp_metadata.dart';
import '../../services/tbp/tbp_storage_service.dart';
import '../../services/tbp/tbp_dhash_engine.dart';
import '../../services/tbp/tbp_download_interceptor.dart';
import '../../services/cloud_drive_service.dart';
import '../../widgets/annotation_canvas.dart';
import '../../widgets/board_toolbar.dart';
import '../../widgets/save_destination_dialog.dart';
import '../../helpers/iframe_view_helper.dart';
import 'tbp_hotspot_overlay.dart';

/// TextBook Plus (TBP) 스마트 교과서 뷰어 (교사용 앱 전용 모듈)
class TbpViewerRoute extends StatefulWidget {
  final String tbpFilePath;
  final double scaleFactor;
  final bool isTeacherApp;

  const TbpViewerRoute({
    super.key,
    required this.tbpFilePath,
    required this.scaleFactor,
    this.isTeacherApp = true,
  });

  @override
  State<TbpViewerRoute> createState() => _TbpViewerRouteState();
}

class _TbpViewerRouteState extends State<TbpViewerRoute> {
  final AnnotationController _annotationController = AnnotationController();
  Color _penColor = const Color(0xFF8B5CF6);
  double _strokeWidth = 4.0;
  ToolMode _tool = ToolMode.pen;
  TbpInputMode _inputMode = TbpInputMode.smart;

  TbpMetadata? _metadata;
  Map<String, dynamic>? _infoJson;
  String _tbpFolderPath = '';
  String _targetUrl = '';
  bool _isLoading = true;
  String? _errorMessage;

  String _currentDhash = 'default';
  List<Map<String, dynamic>> _currentHotspots = [];

  // 활동 타이머 상태
  Timer? _activeSpotTimer;
  int? _spotTimerRemaining;

  late final TbpDhashEngine _dhashEngine;

  final WebviewController _winWebview = WebviewController();
  late final WebViewController _androidWebview;
  bool _winWebviewInitialized = false;

  Timer? _autoSavePenTimer;
  Timer? _smartPassThroughTimer;
  bool _smartClickPassThrough = false;

  bool get _isWebTouchMode =>
      _inputMode == TbpInputMode.touch ||
      _tool == ToolMode.pointer ||
      _smartClickPassThrough;

  void _syncIframePointerEvents() {
    setIframePointerEvents(_isWebTouchMode);
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
        debugPrint('[TbpViewer] Auto-saved pen strokes to Cloud/Local for dhash: $_currentDhash');
      } catch (e) {
        debugPrint('[TbpViewer] Auto-save pen strokes error: $e');
      }
    });
  }

  void _sendVirtualKey(String key, int keyCode) {
    if (kIsWeb) {
      sendVirtualKeyToIframe(key, keyCode);
      if (key == 'PageDown' || key == 'ArrowRight') {
        _dhashEngine.stepWebVirtualPage(1);
      } else if (key == 'PageUp' || key == 'ArrowLeft') {
        _dhashEngine.stepWebVirtualPage(-1);
      }
      _dhashEngine.triggerBurstCapture();
      return;
    }
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

        // Fallback arrow keys for presentation frameworks (HTML Present, Slides, etc)
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
    _dhashEngine.triggerBurstCapture();
  }

  void _handleWebviewHotspotContext(double rx, double ry) {
    if (!mounted) return;
    // 마우스(터치) 모드 또는 스마트 모드에서만 우클릭/길게누르기 핫스팟 생성 허용
    if (_inputMode == TbpInputMode.pen) return;
    setIframePointerEvents(false);
    TbpHotspotOverlay.showAddHotspotModal(
      context,
      rx.clamp(0.02, 0.98),
      ry.clamp(0.02, 0.98),
      _tbpFolderPath,
      _currentDhash,
      _currentHotspots,
      (updated) {
        if (mounted) {
          setState(() {
            _currentHotspots = updated;
          });
        }
        _syncIframePointerEvents();
      },
    ).then((_) => _syncIframePointerEvents());
  }

  @override
  void initState() {
    super.initState();
    _annotationController.onStrokesChanged = _scheduleAutoSavePenStrokes;
    _dhashEngine = TbpDhashEngine(
      onDhashChanged: _onDhashDetected,
      onWebContextMenu: _handleWebviewHotspotContext,
    );
    _syncIframePointerEvents();
    _loadTbpPackage();
  }

  Future<void> _loadTbpPackage() async {
    try {
      final meta = await TbpStorageService.instance.loadTbpFile(
        widget.tbpFilePath,
      );
      if (meta == null) {
        setState(() {
          _errorMessage = '.TBP 메타데이터 파일 읽기에 실패했습니다.';
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
      final targetUrl = (_infoJson?['webUrl'] ?? _infoJson?['targetUrl'] ?? '').toString().trim();
      if (targetUrl.isEmpty) {
        setState(() {
          _errorMessage = 'TBP 폴더 내 webUrl 설정이 올바르지 않습니다.';
          _isLoading = false;
        });
        return;
      }
      _targetUrl = targetUrl;

      // 기존에 저장된 페이지 해시들을 Dhash 엔진에 등록하여 해밍 거리 기반 페이지 매칭 활성화
      final knownHashes = await TbpStorageService.instance.getKnownPageHashes(_tbpFolderPath);
      _dhashEngine.registerKnownHashes(knownHashes);

      // 초기 페이지('default') 핫스팟 및 판서 스트로크 즉시 로드
      final initialHotspots = await TbpStorageService.instance.loadHotspots(
        _tbpFolderPath,
        _currentDhash,
      );
      final initialStrokes = await TbpStorageService.instance.loadPenStrokes(
        _tbpFolderPath,
        _currentDhash,
      );
      _currentHotspots = initialHotspots;
      _annotationController.setStrokes(initialStrokes);

      if (kIsWeb) {
        setState(() {
          _isLoading = false;
        });
        _dhashEngine.startTracker(null, null);
        return;
      } else if (Platform.isWindows) {
        await _initWindowsWebview(targetUrl);
      } else {
        _initAndroidWebview(targetUrl);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      _dhashEngine.startTracker(
        _winWebviewInitialized ? _winWebview : null,
        Platform.isWindows ? null : _androidWebview,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'TBP 패키지 로딩 중 오류 발생: $e';
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

      if (mounted) {
        setState(() {
          _winWebviewInitialized = true;
        });
      }
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
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Text(
              val,
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 15, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기', style: TextStyle(color: Color(0xFF2EC4B6))),
              ),
            ],
          ),
        );
        break;
      case 'timer':
        final secs = int.tryParse(val) ?? 180;
        _activeSpotTimer?.cancel();
        setState(() => _spotTimerRemaining = secs);
        _activeSpotTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) {
            t.cancel();
            return;
          }
          if ((_spotTimerRemaining ?? 0) <= 0) {
            t.cancel();
            setState(() {});
          } else {
            setState(() => _spotTimerRemaining = (_spotTimerRemaining ?? 1) - 1);
          }
        });
        break;
      case 'image':
        final isNet = val.startsWith('http://') || val.startsWith('https://');
        showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Colors.transparent,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: isNet
                      ? Image.network(val, fit: BoxFit.contain)
                      : (!kIsWeb && File(val).existsSync()
                          ? Image.file(File(val), fit: BoxFit.contain)
                          : const Icon(Icons.broken_image, color: Colors.white, size: 80)),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        );
        break;
      default:
        if (val.startsWith('http://') || val.startsWith('https://')) {
          await launchUrl(Uri.parse(val), mode: LaunchMode.externalApplication);
        } else {
          TbpDownloadInterceptor.instance.openSupportedViewer(
            context: context,
            filePath: val,
            scaleFactor: widget.scaleFactor,
          );
        }
        break;
    }
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
          _syncIframePointerEvents();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF7F5AF0) : Colors.transparent,
            borderRadius: BorderRadius.circular(16 * s),
          ),
          child: Text(
            label,
            style: GoogleFonts.notoSansKr(
              color: isSelected ? Colors.white : Colors.white70,
              fontSize: 12 * s,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onDhashDetected(String dHash) async {
    if (dHash.isEmpty || _currentDhash == dHash) return;

    final prevDhash = _currentDhash;
    final prevStrokes = List<AnnotationStroke>.from(_annotationController.strokes);
    final prevHotspots = List<Map<String, dynamic>>.from(_currentHotspots);

    // Save previous dHash strokes
    if (_tbpFolderPath.isNotEmpty) {
      await TbpStorageService.instance.savePenStrokes(
        _tbpFolderPath,
        prevDhash,
        prevStrokes,
      );
    }

    _currentDhash = dHash;
    var hotspots = await TbpStorageService.instance.loadHotspots(
      _tbpFolderPath,
      dHash,
    );
    var strokes = await TbpStorageService.instance.loadPenStrokes(
      _tbpFolderPath,
      dHash,
    );

    // 초기 'default' 상태에서 첫 실제 페이지 해시로 진입 시 작성 중이던 판서/핫스팟 자동 이관
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
      _annotationController.setStrokes(strokes);
    }
  }

  Timer? _touchDhashTimer;

  void _onPointerDown(PointerDownEvent event) {
    _touchDhashTimer?.cancel();
    _touchDhashTimer = Timer(const Duration(milliseconds: 450), () {
      _dhashEngine.triggerBurstCapture();
    });
  }

  @override
  void dispose() {
    _autoSavePenTimer?.cancel();
    _smartPassThroughTimer?.cancel();
    _touchDhashTimer?.cancel();
    _activeSpotTimer?.cancel();
    setIframePointerEvents(true);
    _dhashEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0E17),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2EC4B6)),
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncIframePointerEvents();
    });

    final webviewWidget = kIsWeb
        ? getIframeViewWidget('tbp-teacher-iframe-${_targetUrl.hashCode}', _targetUrl)
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
        child: Stack(
          children: [
            // ── 16:9 컨테이너 (WebView + 판서 + 핫스팟 + 가상 넘기기 버튼) ──
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cWidth = constraints.maxWidth > 0 ? constraints.maxWidth : MediaQuery.of(context).size.width;
                      final cHeight = constraints.maxHeight > 0 ? constraints.maxHeight : MediaQuery.of(context).size.height;

                      void openHotspotModalAt(Offset pos) {
                        // 마우스 모드 또는 스마트 모드에서만 핫스팟 생성 허용 (주석 전용 모드에서는 차단)
                        if (_inputMode == TbpInputMode.pen) return;
                        setIframePointerEvents(false);
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
                            _syncIframePointerEvents();
                          },
                        ).then((_) => _syncIframePointerEvents());
                      }

                      return Stack(
                        children: [
                          // 1. Webview 메인 영역 (마우스 모드일 때 우클릭/길게누르기 핫스팟 감지 지원)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onSecondaryTapDown: (details) {
                                if (_inputMode != TbpInputMode.pen) {
                                  openHotspotModalAt(details.localPosition);
                                }
                              },
                              onLongPressStart: (details) {
                                if (_inputMode == TbpInputMode.touch) {
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
                            child: AnnotationCanvas(
                              controller: _annotationController,
                              enabled: !_isWebTouchMode,
                              onRightClick: _inputMode != TbpInputMode.pen ? openHotspotModalAt : null,
                              onLongPressClick: _inputMode == TbpInputMode.smart
                                  ? (pos) {
                                      setState(() {
                                        _smartClickPassThrough = true;
                                      });
                                      _syncIframePointerEvents();
                                      _smartPassThroughTimer?.cancel();
                                      _smartPassThroughTimer = Timer(const Duration(milliseconds: 2200), () {
                                        if (mounted) {
                                          setState(() {
                                            _smartClickPassThrough = false;
                                          });
                                          _syncIframePointerEvents();
                                          _dhashEngine.triggerBurstCapture();
                                        }
                                      });

                                      ScaffoldMessenger.of(context).clearSnackBars();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('👆 스마트 클릭 통과 활성화 (교과서 버튼/요소 클릭 실행됨 • 2.2초간 직접 터치 가능)'),
                                          duration: Duration(milliseconds: 1400),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );

                                      if (kIsWeb) {
                                        return;
                                      }

                                      final rx = (pos.dx / cWidth).clamp(0.0, 1.0);
                                      final ry = (pos.dy / cHeight).clamp(0.0, 1.0);
                                      final script = '''
                                      (function() {
                                        function fireClickAt(doc, win, cx, cy) {
                                          let el = doc.elementFromPoint(cx, cy);
                                          if (!el) return;
                                          if (el.tagName === 'IFRAME') {
                                            try {
                                              const rect = el.getBoundingClientRect();
                                              const subDoc = el.contentDocument || (el.contentWindow && el.contentWindow.document);
                                              if (subDoc) {
                                                fireClickAt(subDoc, el.contentWindow || win, cx - rect.left, cy - rect.top);
                                                return;
                                              }
                                            } catch (_) {}
                                          }
                                          const opts = { bubbles: true, cancelable: true, view: win, clientX: cx, clientY: cy, button: 0, buttons: 1 };
                                          try { el.dispatchEvent(new PointerEvent('pointerdown', opts)); } catch (_) {}
                                          try { el.dispatchEvent(new MouseEvent('mousedown', opts)); } catch (_) {}
                                          try { el.dispatchEvent(new PointerEvent('pointerup', opts)); } catch (_) {}
                                          try { el.dispatchEvent(new MouseEvent('mouseup', opts)); } catch (_) {}
                                          try { el.dispatchEvent(new MouseEvent('click', opts)); } catch (_) {}
                                          if (typeof el.click === 'function') el.click();
                                          if (typeof el.focus === 'function') el.focus();
                                        }
                                        const x = Math.round($rx * (window.innerWidth || document.documentElement.clientWidth || 1280));
                                        const y = Math.round($ry * (window.innerHeight || document.documentElement.clientHeight || 720));
                                        fireClickAt(document, window, x, y);
                                      })();
                                      ''';
                                      if (!kIsWeb && Platform.isWindows && _winWebviewInitialized) {
                                        _winWebview.executeScript(script);
                                      } else if (!kIsWeb && !Platform.isWindows) {
                                        _androidWebview.runJavaScript(script);
                                      }
                                      _dhashEngine.triggerBurstCapture();
                                    }
                                  : null,
                            ),
                          ),

                          // 3. 모듈화된 핫스팟 오버레이 핀 레이어 (우클릭 핫스팟 추가 & 핀 편집/실행)
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
                              child: MouseRegion(
                                onEnter: (_) => setIframePointerEvents(false),
                                onExit: (_) => _syncIframePointerEvents(),
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
                                          color: const Color(0xFF16161A).withOpacity(0.75),
                                          borderRadius: BorderRadius.circular(24 * s),
                                          border: Border.all(color: Colors.white.withOpacity(0.22)),
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
                              child: MouseRegion(
                                onEnter: (_) => setIframePointerEvents(false),
                                onExit: (_) => _syncIframePointerEvents(),
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
                                          color: const Color(0xFF16161A).withOpacity(0.75),
                                          borderRadius: BorderRadius.circular(24 * s),
                                          border: Border.all(color: Colors.white.withOpacity(0.22)),
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
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // 5. 활동 타이머 오버레이 (활성 시)
                          if (_spotTimerRemaining != null)
                            Positioned(
                              bottom: 72 * s,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: PointerInterceptor(
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
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            // 3. 상단 헤더 및 페이지 넘김
            Positioned(
              top: 16 * s,
              left: 24 * s,
              right: 24 * s,
              child: MouseRegion(
                onEnter: (_) => setIframePointerEvents(false),
                onExit: (_) => _syncIframePointerEvents(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    PointerInterceptor(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16 * s,
                          vertical: 8 * s,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A).withOpacity(0.92),
                          borderRadius: BorderRadius.circular(12 * s),
                          border: Border.all(
                            color: const Color(0xFF2EC4B6).withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                if (_tbpFolderPath.isNotEmpty && _currentDhash.isNotEmpty) {
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
                              '📖 ${_metadata?.title} [${_metadata?.scopeKey}]',
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16 * s,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // TBP 3모드 스위처 (마우스 / 스마트 / 주석)
                    PointerInterceptor(
                      child: Container(
                        padding: EdgeInsets.all(4 * s),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A).withOpacity(0.92),
                          borderRadius: BorderRadius.circular(20 * s),
                          border: Border.all(
                            color: const Color(0xFF7F5AF0).withOpacity(0.5),
                          ),
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

                    PointerInterceptor(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12 * s,
                          vertical: 6 * s,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A).withOpacity(0.92),
                          borderRadius: BorderRadius.circular(30 * s),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.navigate_before_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                              tooltip: '이전 페이지 (PgUp)',
                              onPressed: () {
                                _sendVirtualKey('PageUp', 33);
                                _dhashEngine.navigatePage(isNext: false);
                              },
                            ),
                            SizedBox(width: 4 * s),
                            IconButton(
                              icon: const Icon(
                                Icons.navigate_next_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
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
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12 * s,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2EC4B6),
                                foregroundColor: Colors.black,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10 * s,
                                  vertical: 6 * s,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10 * s),
                                ),
                              ),
                              onPressed: () {
                                setIframePointerEvents(false);
                                final offsetCount = _currentHotspots.length;
                                final rx = (0.2 + (offsetCount % 5) * 0.14).clamp(0.1, 0.88);
                                final ry = (0.22 + (offsetCount ~/ 5) * 0.14).clamp(0.15, 0.82);
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
                                    _syncIframePointerEvents();
                                  },
                                ).then((_) => _syncIframePointerEvents());
                              },
                            ),
                            SizedBox(width: 8 * s),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.save_rounded, size: 16),
                              label: Text(
                                'TBP 저장',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12 * s,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7F5AF0),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10 * s,
                                  vertical: 6 * s,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10 * s),
                                ),
                              ),
                              onPressed: () async {
                                setIframePointerEvents(false);
                                if (_tbpFolderPath.isNotEmpty && _currentDhash.isNotEmpty) {
                                  await TbpStorageService.instance.savePenStrokes(
                                    _tbpFolderPath,
                                    _currentDhash,
                                    _annotationController.strokes,
                                  );
                                }

                                final result = await SaveDestinationDialog.show(
                                  context: context,
                                  scaleFactor: widget.scaleFactor,
                                  title: '💾 TBP 스마트 교과서 저장',
                                  subTitle: 'TBP 교과서 폴더를 어디에 저장하시겠습니까?',
                                );
                                _syncIframePointerEvents();

                                if (result != null) {
                                  final safeTitle = (_metadata?.title ?? 'textbook').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
                                  final folderName = safeTitle.toLowerCase().endsWith('.tbp') ? safeTitle : '$safeTitle.tbp';

                                  if (result.type == SaveTargetType.cloud) {
                                    if (_tbpFolderPath.isNotEmpty) {
                                      await CloudDriveService.instance.saveTbpFolderProjectToDrive(
                                        title: folderName,
                                        localTbpDir: Directory(_tbpFolderPath),
                                        existingDriveFolderId: TbpStorageService.instance.getDriveFolderIdForLocalPath(_tbpFolderPath),
                                      );
                                    }
                                  } else {
                                    final targetDir = Directory(
                                      p.join(result.targetDirectory.path, folderName),
                                    );
                                    if (!targetDir.existsSync()) {
                                      targetDir.createSync(recursive: true);
                                    }
                                    if (_tbpFolderPath.isNotEmpty && Directory(_tbpFolderPath).existsSync()) {
                                      await for (final entity in Directory(_tbpFolderPath).list(recursive: true)) {
                                        if (entity is File) {
                                          final rel = p.relative(entity.path, from: _tbpFolderPath);
                                          final destFile = File(p.join(targetDir.path, rel));
                                          destFile.parent.createSync(recursive: true);
                                          await entity.copy(destFile.path);
                                        }
                                      }
                                    }
                                  }

                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '✅ TBP 교과서 폴더가 [${result.type.name}]에 성공적으로 저장되었습니다!',
                                        ),
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
            ),

            // 4. 하단 스마트 판서 툴바 (BoardDockToolbar)
            Positioned(
              bottom: 16 * s,
              left: 0,
              right: 0,
              child: Center(
                child: MouseRegion(
                  onEnter: (_) => setIframePointerEvents(false),
                  onExit: (_) => _syncIframePointerEvents(),
                  child: PointerInterceptor(
                    child: BoardDockToolbar(
                      scale: widget.scaleFactor,
                      tool: _tool,
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
                        _syncIframePointerEvents();
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
            ),
          ],
        ),
      ),
    );
  }
}

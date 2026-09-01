import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  bool _isLoading = true;
  String? _errorMessage;

  String _currentDhash = 'default';
  List<Map<String, dynamic>> _currentHotspots = [];

  late final TbpDhashEngine _dhashEngine;

  final WebviewController _winWebview = WebviewController();
  late final WebViewController _androidWebview;
  bool _winWebviewInitialized = false;

  @override
  void initState() {
    super.initState();
    _dhashEngine = TbpDhashEngine(onDhashChanged: _onDhashDetected);
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
      if (_infoJson == null || _infoJson!['webUrl'] == null) {
        setState(() {
          _errorMessage = 'TBP 폴더 내 info.json 파일이 없거나 webUrl 설정이 올바르지 않습니다.';
          _isLoading = false;
        });
        return;
      }

      final targetUrl = _infoJson!['webUrl'] as String;

      if (Platform.isWindows) {
        await _initWindowsWebview(targetUrl);
      } else {
        _initAndroidWebview(targetUrl);
      }

      setState(() {
        _isLoading = false;
      });

      _dhashEngine.startTracker(
        _winWebviewInitialized ? _winWebview : null,
        Platform.isWindows ? null : _androidWebview,
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'TBP 패키지 로딩 중 오류 발생: $e';
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
        },
      )
      ..loadRequest(Uri.parse(url));
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
    );
  }

  Future<void> _onDhashDetected(String dHash) async {
    if (_currentDhash == dHash) return;

    // Save previous dHash strokes
    if (_tbpFolderPath.isNotEmpty && _annotationController.strokes.isNotEmpty) {
      await TbpStorageService.instance.savePenStrokes(
        _tbpFolderPath,
        _currentDhash,
        _annotationController.strokes,
      );
    }

    _currentDhash = dHash;
    final hotspots = await TbpStorageService.instance.loadHotspots(
      _tbpFolderPath,
      dHash,
    );
    final strokes = await TbpStorageService.instance.loadPenStrokes(
      _tbpFolderPath,
      dHash,
    );

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
    _touchDhashTimer = Timer(const Duration(seconds: 1), () {
      _dhashEngine.requestHashNow();
    });
  }

  @override
  void dispose() {
    _touchDhashTimer?.cancel();
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

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        child: Stack(
          children: [
            // ── 16:9 컨테이너 (WebView + 판서 + 핫스팟) ──
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: [
                      // 1. Webview 메인 영역
                      Positioned.fill(
                        child: Platform.isWindows
                            ? (_winWebviewInitialized
                                  ? Webview(_winWebview)
                                  : const SizedBox.shrink())
                            : WebViewWidget(controller: _androidWebview),
                      ),

                      // 2. 스마트 판서 캔버스 레이어
                      Positioned.fill(
                        child: AnnotationCanvas(
                          controller: _annotationController,
                          enabled:
                              _inputMode != TbpInputMode.touch &&
                              _tool != ToolMode.pointer,
                          onRightClick: (pos) {
                            if (widget.isTeacherApp) {
                              final size = MediaQuery.of(context).size;
                              final rx = pos.dx / size.width;
                              final ry = pos.dy / size.height;
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
                          },
                          onLongPressClick: (pos) {
                            final x = pos.dx.toInt();
                            final y = pos.dy.toInt();
                            final script =
                                '''
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
                            if (Platform.isWindows && _winWebviewInitialized) {
                              _winWebview.executeScript(script);
                            } else if (!Platform.isWindows) {
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
                          onHotspotsUpdated: (updated) {
                            setState(() {
                              _currentHotspots = updated;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. 상단 헤더 및 페이지 넘김 (PgUp / PgDn 1초 지연)
            Positioned(
              top: 16 * s,
              left: 24 * s,
              right: 24 * s,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16 * s,
                      vertical: 8 * s,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.9),
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
                          onPressed: () => Navigator.pop(context),
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

                  // TBP 3모드 스위처 (마우스 / 스마트 / 주석)
                  Container(
                    padding: EdgeInsets.all(4 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.9),
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

                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12 * s,
                      vertical: 6 * s,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.9),
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
                          onPressed: () =>
                              _dhashEngine.navigatePage(isNext: false),
                        ),
                        SizedBox(width: 8 * s),
                        IconButton(
                          icon: const Icon(
                            Icons.navigate_next_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          tooltip: '다음 페이지 (PgDn)',
                          onPressed: () =>
                              _dhashEngine.navigatePage(isNext: true),
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
                            final result = await SaveDestinationDialog.show(
                              context: context,
                              scaleFactor: widget.scaleFactor,
                              title: '💾 TBP 스마트 교과서 저장',
                              subTitle: 'TBP 교과서 패키지를 어디에 저장하시겠습니까?',
                            );

                            if (result != null) {
                              final targetFile = File(
                                p.join(
                                  result.targetDirectory.path,
                                  '${_metadata?.title ?? "textbook"}.bstTBP',
                                ),
                              );
                              if (_tbpFolderPath.isNotEmpty) {
                                await TbpStorageService.instance.packageBstTbp(
                                  sourceFolderPath: _tbpFolderPath,
                                  outputBstTbpPath: targetFile.path,
                                );
                              } else {
                                final sourceFile = File(widget.tbpFilePath);
                                if (sourceFile.existsSync()) {
                                  await sourceFile.copy(targetFile.path);
                                }
                              }

                              if (result.type == SaveTargetType.cloud &&
                                  targetFile.existsSync()) {
                                await CloudDriveService.instance
                                    .uploadFileToDrive(targetFile);
                              }

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '✅ TBP 교과서가 [${result.type.name}]에 성공적으로 저장되었습니다!',
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
                ],
              ),
            ),

            // 4. 하단 스마트 판서 툴바 (BoardDockToolbar)
            Positioned(
              bottom: 16 * s,
              left: 0,
              right: 0,
              child: Center(
                child: BoardDockToolbar(
                  scale: widget.scaleFactor,
                  tool: _tool,
                  onToolChanged: (tool) {
                    setState(() {
                      _tool = tool;
                      _annotationController.toolMode = tool;
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
          ],
        ),
      ),
    );
  }
}

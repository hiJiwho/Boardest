import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/board_tools.dart';
import '../widgets/annotation_canvas.dart';
import '../widgets/board_toolbar.dart';
import '../services/annotation_storage_service.dart';
import '../services/cloud_drive_service.dart';

/// Boardest Canva 스마트 슬라이드 PDF-스타일 판서 통합 뷰 (.canva 지원)
class CanvaBoardView extends StatefulWidget {
  final double scaleFactor;
  final String? initialUrl;
  final String? filePath;
  final VoidCallback? onBack;

  const CanvaBoardView({
    super.key,
    required this.scaleFactor,
    this.initialUrl,
    this.filePath,
    this.onBack,
  });

  @override
  State<CanvaBoardView> createState() => _CanvaBoardViewState();
}

class _CanvaBoardViewState extends State<CanvaBoardView> {
  late final TextEditingController _urlController;

  WebviewController? _winWebviewController;
  WebViewController? _androidWebController;

  bool _isWebviewInitialized = false;
  String _canvaTitle = 'Canva 수업 슬라이드';

  int _currentPage = 0;
  int _totalPages = 10;

  final Map<int, List<AnnotationStroke>> _pageAnnotations = {};
  final Map<int, AnnotationController> _pageControllers = {};

  Color _penColor = const Color(0xFF8B5CF6);
  double _strokeWidth = 4.0;
  ToolMode _tool = ToolMode.pen;
  bool _eraseEntireStroke = false;
  double _eraserSize = 30.0;

  String _selectedClassForPen = '전체 반 공용 (통합)';
  final List<String> _classList = [
    '전체 반 공용 (통합)',
    '1학년 1반',
    '1학년 2반',
    '2학년 1반',
    '2학년 2반',
    '3학년 1반',
    '3학년 2반',
  ];

  static const String _defaultUrl = 'https://www.canva.com';

  static const String _suppressPopupCssJs = '''
    (function() {
      function purgeCookieBanner() {
        const elements = document.querySelectorAll('div, section, aside, dialog');
        elements.forEach(el => {
          if (el.innerText && (el.innerText.includes('쿠키에 동의') || el.innerText.includes('cookie') || el.innerText.includes('Cookie') || el.innerText.includes('쿠키'))) {
            const btns = el.querySelectorAll('button');
            btns.forEach(btn => {
              if (btn.innerText && (btn.innerText.includes('모든 쿠키 허용') || btn.innerText.includes('동의') || btn.innerText.includes('Allow all') || btn.innerText.includes('모두 허용') || btn.innerText.includes('Accept'))) {
                try { btn.click(); } catch(_) {}
              }
            });
            // Don't just remove the element, as Canva might block scrolling if the overlay is removed but state isn't updated. Clicking is better.
            try { 
              el.style.display = 'none';
              el.style.pointerEvents = 'none';
              el.style.opacity = '0';
              el.style.visibility = 'hidden';
            } catch(_) {}
          }
        });

        // Specific Canva cookie banner button selectors
        const specificBtns = document.querySelectorAll('button[type="button"]');
        specificBtns.forEach(btn => {
          if (btn.innerText && (btn.innerText === '모두 허용' || btn.innerText === 'Accept all' || btn.innerText === '모든 쿠키 허용' || btn.innerText.includes('동의'))) {
            try { btn.click(); } catch(_) {}
          }
        });
      }

      const style = document.createElement('style');
      style.innerHTML = `
        [data-testid="cookie-banner"], [aria-label*="cookie"], [class*="cookieBanner"],
        ._cookie_banner, div[role="dialog"][aria-label*="Cookie"],
        [data-testid="cookie-consent-banner"], [id*="cookie"], [class*="cookie"] {
          display: none !important;
          visibility: hidden !important;
          opacity: 0 !important;
          pointer-events: none !important;
          z-index: -9999 !important;
        }
        body { overflow: auto !important; position: static !important; }
      `;
      document.head.appendChild(style);

      setInterval(purgeCookieBanner, 300);
      purgeCookieBanner();
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _loadEraserPrefs();

    String targetUrl = widget.initialUrl ?? _defaultUrl;

    if (widget.filePath != null && widget.filePath!.isNotEmpty) {
      try {
        final file = File(widget.filePath!);
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          final data = jsonDecode(content);
          if (data['url'] != null) targetUrl = data['url'];
          if (data['title'] != null) _canvaTitle = data['title'];
        }
      } catch (e) {
        debugPrint('[CanvaBoardView] .canva parse error: $e');
      }
    }

    _urlController = TextEditingController(text: targetUrl);
    _loadDiskAnnotations();

    if (Platform.isWindows) {
      _initWindowsWebview();
    } else if (Platform.isAndroid) {
      _initAndroidWebview();
    }
  }

  Future<void> _loadEraserPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _eraseEntireStroke = prefs.getBool('whiteboard_erase_entire') ?? false;
      _eraserSize = prefs.getDouble('whiteboard_eraser_size') ?? 30.0;
    });
  }

  Future<void> _loadDiskAnnotations() async {
    final loaded = await AnnotationStorageService.instance.loadDocumentAnnotations(
      'CANVA',
      _canvaTitle,
      fullFilePath: widget.filePath ?? _urlController.text,
      className: _selectedClassForPen,
    );
    if (mounted) {
      setState(() {
        _pageAnnotations.clear();
        _pageAnnotations.addAll(loaded);
      });
    }
  }

  Future<void> _saveAllAnnotations() async {
    final metadata = {
      'title': _canvaTitle,
      'url': _urlController.text,
      'lastPage': _currentPage,
      'totalPages': _totalPages,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await AnnotationStorageService.instance.saveDocumentAnnotations(
      'CANVA',
      _canvaTitle,
      metadata,
      _pageAnnotations,
      fullFilePath: widget.filePath ?? _urlController.text,
      className: _selectedClassForPen,
    );
  }

  /// PT URL + 판서를 .canva 파일로 내보내기/저장
  Future<void> _exportCanvaPackage() async {
    try {
      await _saveAllAnnotations();

      final appDir = await getApplicationSupportDirectory();
      final canvaDir = Directory('${appDir.path}/BstSave/CANVA');
      if (!canvaDir.existsSync()) canvaDir.createSync(recursive: true);

      final sanitizedTitle = _canvaTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = '$sanitizedTitle.canva';
      final file = File('${canvaDir.path}/$fileName');

      final jsonContent = jsonEncode({
        'title': _canvaTitle,
        'url': _urlController.text,
        'selectedClass': _selectedClassForPen,
        'updatedAt': DateTime.now().toIso8601String(),
        'type': 'CANVA',
      });

      await file.writeAsString(jsonContent, flush: true);

      if (CloudDriveService.instance.isLoggedIn) {
        await CloudDriveService.instance.uploadTextFileToDrive(fileName, jsonContent);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🎉 [$_canvaTitle.canva] 프레젠테이션 및 판서가 .canva 패키지로 저장되었습니다!')),
        );
      }
    } catch (e) {
      debugPrint('[CanvaBoardView] export .canva error: $e');
    }
  }

  AnnotationController _getOrCreateController(int pageIndex) {
    return _pageControllers.putIfAbsent(pageIndex, () {
      final ctrl = AnnotationController();
      ctrl.toolMode = _tool;
      ctrl.activeColor = _penColor;
      ctrl.activeWidth = _strokeWidth;
      ctrl.eraseEntireStroke = _eraseEntireStroke;
      ctrl.eraserSize = _eraserSize;

      final existing = _pageAnnotations[pageIndex];
      if (existing != null && existing.isNotEmpty) {
        ctrl.strokes.addAll(existing);
      }

      ctrl.addListener(() {
        _pageAnnotations[pageIndex] = List<AnnotationStroke>.from(ctrl.strokes);
        unawaited(_saveAllAnnotations());
        if (mounted) setState(() {});
      });

      return ctrl;
    });
  }

  void _syncAllControllers() {
    for (final ctrl in _pageControllers.values) {
      ctrl.toolMode = _tool;
      ctrl.activeColor = _penColor;
      ctrl.activeWidth = _strokeWidth;
      ctrl.eraseEntireStroke = _eraseEntireStroke;
      ctrl.eraserSize = _eraserSize;
    }
  }

  Future<void> _initWindowsWebview() async {
    try {
      _winWebviewController = WebviewController();
      await _winWebviewController!.initialize();
      _winWebviewController!.url.listen((url) {
        if (mounted) setState(() => _urlController.text = url);
      });
      await _winWebviewController!.loadUrl(_convertCanvaEmbedUrl(_urlController.text));
      await _winWebviewController!.executeScript(_suppressPopupCssJs);
      if (mounted) setState(() => _isWebviewInitialized = true);
    } catch (e) {
      debugPrint('[CanvaBoardView] Windows WebView init error: $e');
    }
  }

  void _initAndroidWebview() {
    _androidWebController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (url) {
        _androidWebController?.runJavaScript(_suppressPopupCssJs);
      }))
      ..loadRequest(Uri.parse(_convertCanvaEmbedUrl(_urlController.text)));
    setState(() => _isWebviewInitialized = true);
  }

  String _convertCanvaEmbedUrl(String rawUrl) {
    var url = rawUrl.trim();
    if (url.isEmpty) return _defaultUrl;
    if (!url.startsWith('http')) url = 'https://$url';
    if (url.contains('canva.com/design/') && !url.contains('view?embed')) {
      if (url.endsWith('/view')) {
        url = '$url?embed';
      } else if (!url.endsWith('/')) {
        url = '$url/view?embed';
      }
    }
    return url;
  }

  void _navigateToUrl() {
    final targetUrl = _convertCanvaEmbedUrl(_urlController.text);
    if (Platform.isWindows && _winWebviewController != null) {
      _winWebviewController!.loadUrl(targetUrl);
      _winWebviewController!.executeScript(_suppressPopupCssJs);
    } else if (Platform.isAndroid && _androidWebController != null) {
      _androidWebController!.loadRequest(Uri.parse(targetUrl));
    }
  }

  void _changePage(int targetPage) {
    if (targetPage < 0 || targetPage >= _totalPages) return;
    final diff = targetPage - _currentPage;
    setState(() {
      _currentPage = targetPage;
    });

    final jsKey = diff > 0 ? 'ArrowRight' : 'ArrowLeft';
    final keyCode = diff > 0 ? 39 : 37;
    final jsCode = '''
      (function() {
        var count = ${diff.abs()};
        for (var i = 0; i < count; i++) {
          var evt = new KeyboardEvent('keydown', { key: '$jsKey', code: '$jsKey', keyCode: $keyCode, which: $keyCode, bubbles: true, cancelable: true });
          document.dispatchEvent(evt);
          window.dispatchEvent(evt);
          if (document.activeElement) document.activeElement.dispatchEvent(evt);
        }
      })();
    ''';

    if (Platform.isWindows && _winWebviewController != null) {
      _winWebviewController!.executeScript(jsCode);
    } else if (Platform.isAndroid && _androidWebController != null) {
      _androidWebController!.runJavaScript(jsCode);
    }

    unawaited(_saveAllAnnotations());
  }

  @override
  void dispose() {
    unawaited(_saveAllAnnotations());
    for (final ctrl in _pageControllers.values) {
      ctrl.dispose();
    }
    _urlController.dispose();
    _winWebviewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;
    final ctrl = _getOrCreateController(_currentPage);

    return Scaffold(
      backgroundColor: const Color(0xFF16161A),
      body: SafeArea(
        child: Stack(
          children: [
            // PDF-Style Centered Slide Frame Container
            Center(
              child: Padding(
                padding: EdgeInsets.only(top: 60 * scale, bottom: 80 * scale, left: 16 * scale, right: 16 * scale),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewW = constraints.maxWidth;
                    final viewH = constraints.maxHeight;

                    // 16:9 Presentation Aspect Ratio Frame
                    const aspect = 16.0 / 9.0;
                    double finalW = viewW;
                    double finalH = finalW / aspect;
                    if (finalH > viewH) {
                      finalH = viewH;
                      finalW = finalH * aspect;
                    }

                    return Material(
                      elevation: 12,
                      clipBehavior: Clip.antiAlias,
                      borderRadius: BorderRadius.circular(16 * scale),
                      color: Colors.black,
                      child: SizedBox(
                        width: finalW,
                        height: finalH,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildWebView(),
                            AnnotationCanvas(
                              controller: ctrl,
                              enabled: _tool == ToolMode.pen || _tool == ToolMode.eraser || _tool == ToolMode.select,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Top Header: Class Selector & Document Title & Page Controls
            Positioned(
              top: 12 * scale,
              left: 16 * scale,
              right: 16 * scale,
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12 * scale),
                      border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.6)),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.palette_rounded, color: Color(0xFF8B5CF6), size: 20),
                        SizedBox(width: 8 * scale),
                        Text(
                          _canvaTitle,
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14 * scale),
                        ),
                        SizedBox(width: 12 * scale),
                        DropdownButton<String>(
                          dropdownColor: const Color(0xFF242629),
                          value: _selectedClassForPen,
                          underline: const SizedBox(),
                          style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          items: _classList.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (val) async {
                            if (val != null && val != _selectedClassForPen) {
                              await _saveAllAnnotations();
                              setState(() {
                                _selectedClassForPen = val;
                                _pageAnnotations.clear();
                                for (final c in _pageControllers.values) {
                                  c.clear();
                                }
                              });
                              await _loadDiskAnnotations();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('🏫 [$val] 판서 데이터로 전환되었습니다.')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  SizedBox(width: 12 * scale),

                  // Save as .canva button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                    ),
                    icon: const Icon(Icons.save_alt_rounded, size: 16),
                    label: const Text('.canva 저장'),
                    onPressed: _exportCanvaPackage,
                  ),

                  SizedBox(width: 16 * scale),

                  // Page Pagination (PDF Feeling + JS Keyboard dispatch)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 2 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0xFF242629),
                      borderRadius: BorderRadius.circular(12 * scale),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                          onPressed: _currentPage > 0 ? () => _changePage(_currentPage - 1) : null,
                        ),
                        Text(
                          '슬라이드 ${_currentPage + 1} / $_totalPages 쪽',
                          style: GoogleFonts.outfit(color: const Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 13 * scale),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
                          onPressed: _currentPage < _totalPages - 1 ? () => _changePage(_currentPage + 1) : null,
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () {
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            ),

            // Bottom Board Dock Toolbar
            Positioned(
              bottom: 16 * scale,
              left: 16 * scale,
              right: 16 * scale,
              child: Center(
                child: BoardDockToolbar(
                  scale: scale,
                  tool: _tool,
                  onToolChanged: (mode) {
                    setState(() {
                      _tool = mode;
                    });
                    _syncAllControllers();
                  },
                  strokeWidth: _strokeWidth,
                  onStrokeWidthChanged: (w) {
                    setState(() {
                      _strokeWidth = w;
                      _tool = ToolMode.pen;
                    });
                    _syncAllControllers();
                  },
                  penColor: _penColor,
                  onColorChanged: (c) {
                    setState(() {
                      _penColor = c;
                      _tool = ToolMode.pen;
                    });
                    _syncAllControllers();
                  },
                  onUndo: ctrl.undo,
                  onClear: () => setState(() => ctrl.clear()),
                  onClose: () => Navigator.pop(context),
                  showUrlSearch: true,
                  urlValue: _urlController.text,
                  onUrlSubmitted: (val) {
                    _urlController.text = val;
                    _navigateToUrl();
                  },
                  onUrlRefresh: () {
                    if (Platform.isWindows && _winWebviewController != null) {
                      _winWebviewController!.reload();
                      _winWebviewController!.executeScript(_suppressPopupCssJs);
                    } else if (Platform.isAndroid && _androidWebController != null) {
                      _androidWebController!.reload();
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

  Widget _buildWebView() {
    if (Platform.isWindows && _isWebviewInitialized && _winWebviewController != null) {
      return Webview(_winWebviewController!);
    } else if (Platform.isAndroid && _androidWebController != null) {
      return WebViewWidget(controller: _androidWebController!);
    } else {
      return Center(
        child: Text(
          '🎨 Canva 스마트 슬라이드 뷰어 로딩 중…',
          style: GoogleFonts.notoSansKr(color: Colors.white38),
        ),
      );
    }
  }
}

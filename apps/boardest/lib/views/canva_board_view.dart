import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/board_tools.dart';
import '../widgets/annotation_canvas.dart';
import '../widgets/board_toolbar.dart';
import '../widgets/save_destination_dialog.dart';
import '../services/annotation_storage_service.dart';
import '../services/storage_service.dart';

/// Boardest Canva 스마트 PPT 프레젠테이션 뷰 (.BSTcanva 지원 - 전자칠판 전용)
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
  final FocusNode _keyboardFocusNode = FocusNode();

  WebviewController? _winWebviewController;
  WebViewController? _androidWebController;

  bool _isWebviewInitialized = false;
  String _canvaTitle = 'Canva 수업 프레젠테이션';

  int _currentPage = 0;
  int _totalPages = 1;

  final Map<int, List<AnnotationStroke>> _pageAnnotations = {};
  final Map<int, AnnotationController> _pageControllers = {};

  Color _penColor = const Color(0xFF8B5CF6);
  double _strokeWidth = 4.0;
  ToolMode _tool = ToolMode.pen;
  ShapeType _activeShape = ShapeType.rectangle;
  bool _eraseEntireStroke = false;
  double _eraserSize = 30.0;

  String _selectedClassForPen = '';

  static const String _defaultUrl = 'https://www.canva.com';

  static const String _canvaJsObserver = '''
    (function() {
      function purgeNoise() {
        const selectors = [
          '[data-testid="cookie-banner"]', '[aria-label*="cookie"]', '[class*="cookieBanner"]',
          'header', 'nav', '[data-testid="header"]', 'footer', '[class*="footer"]',
          'button[aria-label*="Canva"]', '._cookie_banner', 'div[role="dialog"][aria-label*="Cookie"]'
        ];
        selectors.forEach(s => {
          document.querySelectorAll(s).forEach(el => {
            try {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
              el.style.opacity = '0';
              el.style.pointerEvents = 'none';
            } catch(_) {}
          });
        });

        document.querySelectorAll('button').forEach(btn => {
          if (btn.innerText && (btn.innerText.includes('모든 쿠키') || btn.innerText.includes('모두 허용') || btn.innerText === 'Accept all' || btn.innerText === 'Accept')) {
            try { btn.click(); } catch(_) {}
          }
        });
      }

      const style = document.createElement('style');
      style.innerHTML = `
        header, nav, footer, [data-testid="header"], [aria-label*="cookie"], [class*="cookie"] {
          display: none !important;
          pointer-events: none !important;
        }
        body, html {
          overflow: hidden !important;
          margin: 0 !important;
          padding: 0 !important;
          background: #000000 !important;
        }
      `;
      document.head.appendChild(style);
      setInterval(purgeNoise, 500);
      purgeNoise();

      let lastPage = -1;
      let lastTotal = -1;

      function parsePageText(text) {
          if (!text) return null;
          let t = text.trim();
          let m = t.match(/(\\d+)\\s*(?:\\/|of)\\s*(\\d+)/);
          if (m) {
              return { current: parseInt(m[1], 10), total: parseInt(m[2], 10) };
          }
          return null;
      }

      function checkPage() {
          let indicators = document.querySelectorAll('[data-testid="page-indicator"], .slide-counter, [class*="pageNum"]');
          let parsed = null;
          for (let i = 0; i < indicators.length; i++) {
              let res = parsePageText(indicators[i].innerText);
              if (res) {
                  parsed = res;
                  break;
              }
          }
          
          if (!parsed) {
              let all = document.querySelectorAll('*');
              for (let i = 0; i < all.length; i++) {
                  if (all[i].children.length === 0 && all[i].innerText) {
                      let res = parsePageText(all[i].innerText);
                      if (res) {
                          parsed = res;
                          break;
                      }
                  }
              }
          }

          if (parsed && (parsed.current !== lastPage || parsed.total !== lastTotal)) {
              lastPage = parsed.current;
              lastTotal = parsed.total;
              let msg = JSON.stringify({ type: 'canva_page', page: parsed.current, total: parsed.total });
              if (window.chrome && window.chrome.webview && window.chrome.webview.postMessage) {
                  window.chrome.webview.postMessage(msg);
              } else if (window.TbpChannel && window.TbpChannel.postMessage) {
                  window.TbpChannel.postMessage(msg);
              }
          }
      }

      const observer = new MutationObserver((mutations) => {
          checkPage();
      });
      observer.observe(document.body, { childList: true, subtree: true, characterData: true });
      setInterval(checkPage, 500);
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
          if (data['embedUrl'] != null)
            targetUrl = data['embedUrl'];
          else if (data['url'] != null)
            targetUrl = data['url'];
          if (data['title'] != null) _canvaTitle = data['title'];
        }
      } catch (e) {
        debugPrint('[CanvaBoardView] .BSTcanva parse error: $e');
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
    final s = await StorageService().getSettings();
    if (!mounted) return;
    setState(() {
      _selectedClassForPen = '${s.selectedGrade}학년 ${s.selectedClass}반';
      _eraseEntireStroke = prefs.getBool('whiteboard_erase_entire') ?? false;
      _eraserSize = prefs.getDouble('whiteboard_eraser_size') ?? 30.0;
    });
  }

  Future<void> _loadDiskAnnotations() async {
    final loaded = await AnnotationStorageService.instance
        .loadDocumentAnnotations(
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

  Future<void> _exportCanvaPackage() async {
    try {
      await _saveAllAnnotations();

      final result = await SaveDestinationDialog.show(
        context: context,
        scaleFactor: widget.scaleFactor,
      );

      if (result == null) return;

      final canvaDir = Directory(
        '${result.targetDirectory.path}/BstSave/CANVA',
      );
      if (!canvaDir.existsSync()) canvaDir.createSync(recursive: true);

      final sanitizedTitle = _canvaTitle.replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );
      final fileName = '$sanitizedTitle.BSTcanva';
      final file = File('${canvaDir.path}/$fileName');

      final jsonContent = jsonEncode({
        'version': 1,
        'title': _canvaTitle,
        'embedUrl': _convertCanvaEmbedUrl(_urlController.text),
      });

      await file.writeAsString(jsonContent, flush: true);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('🎉 [$fileName] 패키지가 저장되었습니다!')));
      }
    } catch (e) {
      debugPrint('[CanvaBoardView] export .BSTcanva error: $e');
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

  void _handleWebMessage(String message) {
    try {
      final data = jsonDecode(message);
      if (data['type'] == 'canva_page') {
        int newPage = data['page'] - 1; // Convert to 0-indexed for internal use
        if (newPage < 0) newPage = 0;
        int total = data['total'];

        if (newPage != _currentPage || total != _totalPages) {
          _onPageChangedFromCanva(newPage, total);
        }
      }
    } catch (e) {
      // Ignore JSON parse errors
    }
  }

  void _onPageChangedFromCanva(int newPage, int newTotal) async {
    if (_currentPage != newPage) {
      await _saveAllAnnotations();
      if (mounted) {
        setState(() {
          _currentPage = newPage;
          _totalPages = newTotal;
        });
      }
    } else if (_totalPages != newTotal) {
      if (mounted) {
        setState(() {
          _totalPages = newTotal;
        });
      }
    }
  }

  Future<void> _initWindowsWebview() async {
    try {
      _winWebviewController = WebviewController();
      await _winWebviewController!.initialize();

      _winWebviewController!.webMessage.listen((msg) {
        if (msg.isNotEmpty) {
          _handleWebMessage(msg);
        }
      });

      _winWebviewController!.url.listen((url) {
        if (mounted) setState(() => _urlController.text = url);
      });
      await _winWebviewController!.loadUrl(
        _convertCanvaEmbedUrl(_urlController.text),
      );
      await _winWebviewController!.executeScript(_canvaJsObserver);
      if (mounted) setState(() => _isWebviewInitialized = true);
    } catch (e) {
      debugPrint('[CanvaBoardView] Windows WebView init error: $e');
    }
  }

  void _initAndroidWebview() {
    _androidWebController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'TbpChannel',
        onMessageReceived: (msg) {
          _handleWebMessage(msg.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            _androidWebController?.runJavaScript(_canvaJsObserver);
          },
        ),
      )
      ..loadRequest(Uri.parse(_convertCanvaEmbedUrl(_urlController.text)));
    setState(() => _isWebviewInitialized = true);
  }

  static String formatCanvaEmbedUrl(String rawUrl) {
    var url = rawUrl.trim();
    if (url.isEmpty) return 'https://www.canva.com/design/DAGXxxx/watch?embed';
    if (!url.startsWith('http')) url = 'https://\$url';

    if (url.contains('canva.com')) {
      final base = url.split('?')[0];
      if (base.endsWith('/view') ||
          base.endsWith('/edit') ||
          base.endsWith('/watch') ||
          base.endsWith('/present')) {
        final cleanBase = base.substring(0, base.lastIndexOf('/'));
        return '\$cleanBase/watch?embed';
      }
      if (!base.endsWith('?embed')) {
        return '\$base/watch?embed';
      }
    }
    return url;
  }

  String _convertCanvaEmbedUrl(String rawUrl) {
    var url = rawUrl.trim();
    if (url.isEmpty) return _defaultUrl;
    if (!url.startsWith('http')) url = 'https://\$url';
    if (url.contains('canva.com/design/') && !url.contains('view?embed')) {
      if (url.endsWith('/view')) {
        url = '\$url?embed';
      } else if (!url.endsWith('/')) {
        url = '\$url/view?embed';
      }
    }
    return url;
  }

  void _navigateToUrl() {
    final targetUrl = _convertCanvaEmbedUrl(_urlController.text);
    if (Platform.isWindows && _winWebviewController != null) {
      _winWebviewController!.loadUrl(targetUrl);
      _winWebviewController!.executeScript(_canvaJsObserver);
    } else if (Platform.isAndroid && _androidWebController != null) {
      _androidWebController!.loadRequest(Uri.parse(targetUrl));
    }
  }

  void _sendPageNavSignal(bool isNext) {
    final jsKey = isNext ? 'ArrowRight' : 'ArrowLeft';
    final keyCode = isNext ? 39 : 37;
    final jsCode = '''
      (function() {
        var evt = new KeyboardEvent('keydown', { key: '\$jsKey', code: '\$jsKey', keyCode: \$keyCode, which: \$keyCode, bubbles: true, cancelable: true });
        document.dispatchEvent(evt);
        window.dispatchEvent(evt);
        if (document.activeElement) document.activeElement.dispatchEvent(evt);
      })();
    ''';

    if (Platform.isWindows && _winWebviewController != null) {
      _winWebviewController!.executeScript(jsCode);
    } else if (Platform.isAndroid && _androidWebController != null) {
      _androidWebController!.runJavaScript(jsCode);
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.pageDown) {
      _sendPageNavSignal(true);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.backspace) {
      _sendPageNavSignal(false);
    }
  }

  @override
  void dispose() {
    unawaited(_saveAllAnnotations());
    for (final ctrl in _pageControllers.values) {
      ctrl.dispose();
    }
    _urlController.dispose();
    _keyboardFocusNode.dispose();
    _winWebviewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;
    final ctrl = _getOrCreateController(_currentPage);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildWebView(),
            IgnorePointer(
              ignoring: _tool == ToolMode.pointer,
              child: AnnotationCanvas(
                controller: ctrl,
                enabled: _tool != ToolMode.pointer,
              ),
            ),

            // Top UI Row
            Positioned(
              top: 16 * scale,
              left: 16 * scale,
              right: 16 * scale,
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12 * scale,
                      vertical: 4 * scale,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12 * scale),
                      border: Border.all(
                        color: const Color(0xFF8B5CF6).withOpacity(0.6),
                      ),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.slideshow_rounded,
                          color: Color(0xFF8B5CF6),
                          size: 20,
                        ),
                        SizedBox(width: 8 * scale),
                        Text(
                          _canvaTitle,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14 * scale,
                          ),
                        ),
                        SizedBox(width: 12 * scale),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8 * scale,
                            vertical: 3 * scale,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F5D4).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6 * scale),
                            border: Border.all(
                              color: const Color(0xFF00F5D4).withOpacity(0.4),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _selectedClassForPen.isNotEmpty ? _selectedClassForPen : '현재 학급',
                            style: GoogleFonts.notoSansKr(
                              color: const Color(0xFF00F5D4),
                              fontSize: 11 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(width: 12 * scale),

                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF8B5CF6)),
                      backgroundColor: Colors.black54,
                      padding: EdgeInsets.symmetric(
                        horizontal: 12 * scale,
                        vertical: 8 * scale,
                      ),
                    ),
                    icon: const Icon(Icons.save_alt_rounded, size: 16),
                    label: const Text('.BSTcanva 저장'),
                    onPressed: _exportCanvaPackage,
                  ),

                  SizedBox(width: 12 * scale),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _tool == ToolMode.pointer
                          ? const Color(0xFF2EC4B6)
                          : const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 12 * scale,
                        vertical: 8 * scale,
                      ),
                    ),
                    icon: Icon(
                      _tool == ToolMode.pointer
                          ? Icons.mouse_rounded
                          : Icons.edit_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _tool == ToolMode.pointer ? '마우스 모드 (클릭 통과)' : '판서 모드',
                    ),
                    onPressed: () {
                      setState(() {
                        _tool = _tool == ToolMode.pointer
                            ? ToolMode.pen
                            : ToolMode.pointer;
                        _syncAllControllers();
                      });
                    },
                  ),

                  const Spacer(),

                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.7),
                    ),
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

            // Bottom UI Row
            Positioned(
              bottom: 16 * scale,
              left: 16 * scale,
              right: 16 * scale,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10 * scale,
                        vertical: 4 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(20 * scale),
                        border: Border.all(
                          color: const Color(0xFF8B5CF6).withOpacity(0.5),
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 10),
                        ],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.chevron_left_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            tooltip: '이전 슬라이드 (←, PageUp)',
                            onPressed: () => _sendPageNavSignal(false),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10 * scale,
                              vertical: 4 * scale,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8 * scale),
                            ),
                            child: Text(
                              '\${_currentPage + 1} / \$_totalPages',
                              style: GoogleFonts.outfit(
                                color: const Color(0xFF00F5D4),
                                fontWeight: FontWeight.bold,
                                fontSize: 13 * scale,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            tooltip: '다음 슬라이드 (→, PageDown)',
                            onPressed: () => _sendPageNavSignal(true),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(width: 12 * scale),

                    BoardDockToolbar(
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
                          if (_tool == ToolMode.pointer) _tool = ToolMode.pen;
                        });
                        _syncAllControllers();
                      },
                      penColor: _penColor,
                      onColorChanged: (c) {
                        setState(() {
                          _penColor = c;
                          if (_tool == ToolMode.pointer) _tool = ToolMode.pen;
                        });
                        _syncAllControllers();
                      },
                      activeShape: _activeShape,
                      onShapeChanged: (s) {
                        setState(() {
                          _activeShape = s;
                          _tool = ToolMode.shape;
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
                        if (Platform.isWindows &&
                            _winWebviewController != null) {
                          _winWebviewController!.reload();
                          _winWebviewController!.executeScript(
                            _canvaJsObserver,
                          );
                        } else if (Platform.isAndroid &&
                            _androidWebController != null) {
                          _androidWebController!.reload();
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
    );
  }

  Widget _buildWebView() {
    if (Platform.isWindows &&
        _isWebviewInitialized &&
        _winWebviewController != null) {
      return Webview(_winWebviewController!);
    } else if (Platform.isAndroid && _androidWebController != null) {
      return WebViewWidget(controller: _androidWebController!);
    } else {
      return Center(
        child: Text(
          '🎨 Canva 스마트 PPT 슬라이드 뷰어 로딩 중…',
          style: GoogleFonts.notoSansKr(color: Colors.white38),
        ),
      );
    }
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';
import '../models/board_tools.dart';
import '../widgets/annotation_canvas.dart';
import '../widgets/board_toolbar.dart';
import '../services/storage_service.dart';

/// 사이트 판서: 보드앱과 동일 도구 UI, 페이지/파일 메뉴 없음, 사이트 조작↔판서 통합 툴바
class WebsiteBoardView extends StatefulWidget {
  final double scaleFactor;
  const WebsiteBoardView({super.key, required this.scaleFactor});

  @override
  State<WebsiteBoardView> createState() => _WebsiteBoardViewState();
}

class _WebsiteBoardViewState extends State<WebsiteBoardView> {
  late AnnotationController _annotationController;
  static const String defaultSiteUrl = 'https://boardest.web.app/sitespen';
  final TextEditingController _urlController = TextEditingController(text: defaultSiteUrl);

  WebviewController? _winWebviewController;
  WebViewController? _androidWebController;
  bool _isWebviewInitialized = false;
  
  /// true = 판서, false = 사이트 클릭(마우스 통과/웹뷰 조작)
  bool _isDrawMode = true;

  Color _penColor = const Color(0xFFEF4565);
  double _strokeWidth = 4.0;
  ToolMode _tool = ToolMode.pen;
  bool _isPenDetailsOpen = false;
  bool _eraseEntireStroke = false;
  double _eraserSize = 30.0;

  @override
  void initState() {
    super.initState();
    _annotationController = AnnotationController();
    _loadEraserPrefs();
    _prepareInitialUrlAndInit();
  }

  Future<void> _prepareInitialUrlAndInit() async {
    try {
      final settings = await StorageService().getSettings();
      final params = <String, String>{};
      if (settings.selectedSchool != null) {
        params['place'] = settings.selectedSchool!.region;
        params['school'] = settings.selectedSchool!.name;
      }
      final baseUri = Uri.parse(defaultSiteUrl);
      final uri = params.isEmpty
          ? baseUri
          : baseUri.replace(queryParameters: params);
      _urlController.text = uri.toString();
    } catch (_) {
      _urlController.text = defaultSiteUrl;
    }

    if (!mounted) return;
    if (Platform.isWindows && !kIsWeb) {
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
    _syncControllerTooling();
  }

  void _syncControllerTooling() {
    _annotationController.toolMode = _tool;
    _annotationController.activeColor = _penColor;
    _annotationController.activeWidth = _strokeWidth;
    _annotationController.eraseEntireStroke = _eraseEntireStroke;
    _annotationController.eraserSize = _eraserSize;
  }

  void _setTool(ToolMode mode) {
    setState(() {
      _isDrawMode = true;
      _tool = mode;
      _isPenDetailsOpen = false;
    });
    _syncControllerTooling();
    _updateWebviewClickThrough();
  }

  Future<void> _initWindowsWebview() async {
    try {
      _winWebviewController = WebviewController();
      await _winWebviewController!.initialize();
      _winWebviewController!.url.listen((url) {
        if (mounted) setState(() => _urlController.text = url);
      });
      _winWebviewController!.historyChanged.listen((_) {});
      await _winWebviewController!.loadUrl(_urlController.text);
      if (mounted) {
        setState(() {
          _isWebviewInitialized = true;
        });
        _updateWebviewClickThrough();
        // Call click-through updates with delays to ensure native child HWND is fully created
        Future.delayed(const Duration(milliseconds: 200), _updateWebviewClickThrough);
        Future.delayed(const Duration(milliseconds: 500), _updateWebviewClickThrough);
        Future.delayed(const Duration(milliseconds: 1000), _updateWebviewClickThrough);
      }
    } catch (e) {
      debugPrint('WebView init: $e');
    }
  }

  void _initAndroidWebview() {
    _androidWebController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (mounted) setState(() => _urlController.text = url);
          },
        ),
      )
      ..loadRequest(Uri.parse(_urlController.text));
    setState(() => _isWebviewInitialized = true);
  }

  Future<void> _navigateToUrl() async {
    var url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'https://$url';

    if (Platform.isWindows && _isWebviewInitialized && _winWebviewController != null) {
      await _winWebviewController!.loadUrl(url);
    } else if (Platform.isAndroid && _androidWebController != null) {
      await _androidWebController!.loadRequest(Uri.parse(url));
    } else {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  void _clearCanvas() {
    setState(() => _annotationController.clear());
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      const channel = MethodChannel('com.boardest/launch_args');
      channel.invokeMethod('setWebviewClickThrough', false);
    }
    _annotationController.dispose();
    _urlController.dispose();
    _winWebviewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;

    return Scaffold(
      backgroundColor: const Color(0xFF16161A),
      body: Stack(
        children: [
          // WebView 배치
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: _isDrawMode,
              child: _buildWebViewLayer(),
            ),
          ),
          // 판서 오버레이 레이어 (WebView 위에)
          if (_isDrawMode)
            Positioned.fill(
              child: AnnotationCanvas(
                controller: _annotationController,
                enabled: _tool == ToolMode.pen || _tool == ToolMode.eraser || _tool == ToolMode.select,
              ),
            ),
          // 플로팅 툴바
          Positioned(
            bottom: 16 * scale,
            left: 16 * scale,
            right: 16 * scale,
            child: Center(
              child: _buildGoodNotesFloatingToolbar(scale),
            ),
          ),
        ],
      ),
    );
  }

  void _updateWebviewClickThrough() {
    if (Platform.isWindows) {
      const channel = MethodChannel('com.boardest/launch_args');
      channel.invokeMethod('setWebviewClickThrough', _isDrawMode);
    }
  }

  /// WebView 레이어 구성
  Widget _buildWebViewLayer() {
    if (Platform.isWindows && _isWebviewInitialized && _winWebviewController != null) {
      return Webview(_winWebviewController!);
    } else if (Platform.isAndroid && _androidWebController != null) {
      return WebViewWidget(controller: _androidWebController!);
    } else {
      return Center(
        child: Text(
          '웹뷰 초기화 중…',
          style: GoogleFonts.notoSansKr(color: Colors.white38),
        ),
      );
    }
  }

  Widget _buildGoodNotesFloatingToolbar(double scale) {
    return BoardDockToolbar(
      scale: scale,
      tool: _isDrawMode ? _tool : ToolMode.pointer,
      onToolChanged: (mode) {
        setState(() {
          if (mode == ToolMode.pointer) {
            _isDrawMode = false;
            _isPenDetailsOpen = false;
          } else {
            _isDrawMode = true;
            _tool = mode;
          }
        });
        _syncControllerTooling();
        _updateWebviewClickThrough();
      },
      strokeWidth: _strokeWidth,
      onStrokeWidthChanged: (w) {
        setState(() {
          _strokeWidth = w;
          _isDrawMode = true;
          _tool = ToolMode.pen;
        });
        _syncControllerTooling();
      },
      penColor: _penColor,
      onColorChanged: (c) {
        setState(() {
          _penColor = c;
          _isDrawMode = true;
          _tool = ToolMode.pen;
        });
        _syncControllerTooling();
      },
      onUndo: _annotationController.undo,
      onClear: _clearCanvas,
      onClose: () => Navigator.pop(context),
      eraseEntireStroke: _eraseEntireStroke,
      onEraseEntireStrokeChanged: (val) async {
        setState(() => _eraseEntireStroke = val);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('whiteboard_erase_entire', val);
        _syncControllerTooling();
      },
      eraserSize: _eraserSize,
      onEraserSizeChanged: (val) async {
        setState(() => _eraserSize = val);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('whiteboard_eraser_size', val);
        _syncControllerTooling();
      },
      showUrlSearch: true,
      urlValue: _urlController.text,
      onUrlSubmitted: (url) {
        setState(() => _urlController.text = url);
        _navigateToUrl();
      },
      onUrlRefresh: () {
        if (Platform.isWindows && _isWebviewInitialized && _winWebviewController != null) {
          _winWebviewController!.reload();
        } else if (Platform.isAndroid && _androidWebController != null) {
          _androidWebController!.reload();
        } else {
          _navigateToUrl();
        }
      },
    );
  }
}

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
import '../services/annotation_storage_service.dart';
import '../services/cloud_drive_service.dart';

import 'dart:async';

/// Hotspot Link Model
class HotspotLink {
  final String id;
  final Offset position;
  final String title;
  final String type; // 'url', 'file', 'tool', 'note'
  final String target; // URL, file path, tool name, or text note

  HotspotLink({
    required this.id,
    required this.position,
    required this.title,
    required this.type,
    required this.target,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': position.dx,
        'y': position.dy,
        'title': title,
        'type': type,
        'target': target,
      };

  factory HotspotLink.fromJson(Map<String, dynamic> json) => HotspotLink(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        position: Offset((json['x'] as num).toDouble(), (json['y'] as num).toDouble()),
        title: json['title'] as String? ?? '핫스팟',
        type: json['type'] as String? ?? 'url',
        target: json['target'] as String? ?? '',
      );
}

/// 사이트 판서: 보드앱과 동일 도구 UI, 페이지/파일 메뉴 없음, 사이트 조작↔판서 통합 툴바
class WebsiteBoardView extends StatefulWidget {
  final double scaleFactor;
  final VoidCallback? onBack;
  final String? initialUrl;
  const WebsiteBoardView({
    super.key,
    required this.scaleFactor,
    this.onBack,
    this.initialUrl,
  });

  @override
  State<WebsiteBoardView> createState() => _WebsiteBoardViewState();
}

class _WebsiteBoardViewState extends State<WebsiteBoardView> {
  late AnnotationController _annotationController;
  static const String defaultSiteUrl = 'https://boardest.web.app/sitespen';
  late final TextEditingController _urlController;

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

  // dHash & Page Navigation State
  int _currentPageIndex = 1;
  String _lastDHash = '';
  Timer? _dHashCheckTimer;
  final List<HotspotLink> _hotspots = [];

  @override
  void initState() {
    super.initState();
    _annotationController = AnnotationController();
    _annotationController.addListener(() {
      _saveAllAnnotations();
      if (mounted) setState(() {});
    });
    _loadEraserPrefs();
    _prepareInitialUrlAndInit();

    // 5초마다 dHash 찍어서 페이지 전환 감지 및 판서/핫스팟 자동 동기화
    _dHashCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkDHashAndSwitchPage();
    });
  }

  void _checkDHashAndSwitchPage() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    
    // URL 및 페이지 상태 결합 dHash 키 생성
    final currentHash = '${url.replaceAll(RegExp(r'[^\w\.-]'), '_')}_p$_currentPageIndex';
    if (_lastDHash.isNotEmpty && _lastDHash != currentHash) {
      await _saveAllAnnotations();
      _lastDHash = currentHash;
      await _loadAnnotations(url);
    } else if (_lastDHash.isEmpty) {
      _lastDHash = currentHash;
    }
  }

  bool _isSaving = false;
  Future<void> _saveAllAnnotations() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _isSaving) return;
    _isSaving = true;
    try {
      final cleanUrl = url.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final metadata = {
        'url': url,
        'type': 'website',
        'totalPages': 1,
        'lastOpened': DateTime.now().toIso8601String(),
      };
      
      final Map<int, List<AnnotationStroke>> pageAnnotations = {
        0: List<AnnotationStroke>.from(_annotationController.strokes),
      };
      
      await AnnotationStorageService.instance.saveDocumentAnnotations(
        'WEBSITE',
        cleanUrl,
        metadata,
        pageAnnotations,
        className: _selectedClassForPen,
      );
    } catch (e) {
      debugPrint('[WebsiteBoardView] Error saving website annotations: $e');
    } finally {
      _isSaving = false;
    }
  }

  String? _lastLoadedUrl;
  Future<void> _loadAnnotations(String url) async {
    final targetUrl = url.trim();
    if (targetUrl.isEmpty || _lastLoadedUrl == targetUrl) return;
    _lastLoadedUrl = targetUrl;
    try {
      final cleanUrl = targetUrl.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final loaded = await AnnotationStorageService.instance.loadDocumentAnnotations(
        'WEBSITE',
        cleanUrl,
        className: _selectedClassForPen,
      );
      if (mounted) {
        setState(() {
          _annotationController.strokes.clear();
          if (loaded.containsKey(0) && loaded[0] != null) {
            _annotationController.strokes.addAll(loaded[0]!);
          }
        });
      }
    } catch (e) {
      debugPrint('[WebsiteBoardView] Error loading website annotations: $e');
    }
  }

  Future<void> _prepareInitialUrlAndInit() async {
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      _urlController = TextEditingController(text: widget.initialUrl);
    } else {
      _urlController = TextEditingController(text: defaultSiteUrl);
      try {
        final settings = await StorageService().getSettings();
        final params = <String, String>{};
        if (settings.selectedSchool != null) {
          params['place'] = settings.selectedSchool!.region;
          params['school'] = settings.selectedSchool!.name;
        }
        params['ui'] = 'teacher';
        if (CloudDriveService.instance.isLoggedIn) {
          if (CloudDriveService.instance.userEmail != null) params['email'] = CloudDriveService.instance.userEmail!;
          if (CloudDriveService.instance.userName != null) params['name'] = CloudDriveService.instance.userName!;
        }
        final baseUri = Uri.parse(defaultSiteUrl);
        final uri = baseUri.replace(queryParameters: params);
        _urlController.text = uri.toString();
      } catch (_) {
        _urlController.text = defaultSiteUrl;
      }
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
        if (mounted) {
          setState(() => _urlController.text = url);
          _loadAnnotations(url);
        }
      });
      _winWebviewController!.historyChanged.listen((_) {});
      await _winWebviewController!.loadUrl(_urlController.text);
      _loadAnnotations(_urlController.text);
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
            if (mounted) {
              setState(() => _urlController.text = url);
              _loadAnnotations(url);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_urlController.text));
    _loadAnnotations(_urlController.text);
    setState(() => _isWebviewInitialized = true);
  }

  Future<void> _navigateToUrl() async {
    var url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'https://$url';

    if (Platform.isWindows && _isWebviewInitialized && _winWebviewController != null) {
      await _winWebviewController!.loadUrl(url);
      _loadAnnotations(url);
    } else if (Platform.isAndroid && _androidWebController != null) {
      await _androidWebController!.loadRequest(Uri.parse(url));
      _loadAnnotations(url);
    } else {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  void _showCreateHotspotDialog(Offset pos) {
    final titleCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    String hotspotType = 'url';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text('📍 핫스팟 링크 추가', style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: '핫스팟 제목', labelStyle: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (context, setDlgState) => DropdownButtonFormField<String>(
                dropdownColor: const Color(0xFF242629),
                value: hotspotType,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: '타입 선택', labelStyle: TextStyle(color: Colors.white70)),
                items: const [
                  DropdownMenuItem(value: 'url', child: Text('🌐 웹 링크 (URL)')),
                  DropdownMenuItem(value: 'file', child: Text('📂 파일 / 교안 문서')),
                  DropdownMenuItem(value: 'tool', child: Text('🛠️ 수업 도구')),
                  DropdownMenuItem(value: 'note', child: Text('📝 텍스트 메모')),
                ],
                onChanged: (val) {
                  if (val != null) setDlgState(() => hotspotType = val);
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: targetCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: '대상 URL / 경로 / 내용', labelStyle: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2EC4B6)),
            onPressed: () {
              final title = titleCtrl.text.trim();
              final target = targetCtrl.text.trim();
              if (title.isEmpty || target.isEmpty) return;
              setState(() {
                _hotspots.add(HotspotLink(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  position: pos,
                  title: title,
                  type: hotspotType,
                  target: target,
                ));
              });
              _saveAllAnnotations();
              Navigator.pop(ctx);
            },
            child: const Text('생성', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _triggerHotspot(HotspotLink spot) async {
    if (spot.type == 'url') {
      if (await canLaunchUrl(Uri.parse(spot.target))) {
        await launchUrl(Uri.parse(spot.target), mode: LaunchMode.externalApplication);
      }
    } else if (spot.type == 'note') {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          title: Text('📝 ${spot.title}', style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontWeight: FontWeight.bold)),
          content: Text(spot.target, style: const TextStyle(color: Colors.white)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('📍 핫스팟 [${spot.title}] 실행: ${spot.target}')),
      );
    }
  }

  void _navigatePage(bool next) {
    setState(() {
      if (next) {
        _currentPageIndex++;
      } else {
        if (_currentPageIndex > 1) _currentPageIndex--;
      }
    });
    final js = next
        ? "document.dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowRight', keyCode: 39, bubbles: true})); window.history.forward();"
        : "document.dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowLeft', keyCode: 37, bubbles: true})); window.history.back();";
    if (Platform.isWindows && _winWebviewController != null) {
      _winWebviewController!.executeScript(js);
    } else if (Platform.isAndroid && _androidWebController != null) {
      _androidWebController!.runJavaScript(js);
    }
    _checkDHashAndSwitchPage();
  }

  void _clearCanvas() {
    setState(() {
      _annotationController.clear();
      _hotspots.clear();
    });
    _saveAllAnnotations();
  }

  @override
  void dispose() {
    _dHashCheckTimer?.cancel();
    if (Platform.isWindows) {
      () async {
        try {
          const channel = MethodChannel('com.boardest/launch_args');
          await channel.invokeMethod('setWebviewClickThrough', false);
        } catch (_) {}
      }();
    }
    _annotationController.dispose();
    _urlController.dispose();
    _winWebviewController?.dispose();
    super.dispose();
  }

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
                onRightClick: (pos) => _showCreateHotspotDialog(pos),
              ),
            ),
          // 핫스팟 핀 오버레이
          ..._hotspots.map((spot) => Positioned(
                left: spot.position.dx - 16,
                top: spot.position.dy - 16,
                child: GestureDetector(
                  onTap: () => _triggerHotspot(spot),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7F5AF0),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on_rounded, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(spot.title, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              )),
          // 반 선택 Selector Top Bar
          Positioned(
            top: 12 * scale,
            left: 16 * scale,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale),
              decoration: BoxDecoration(
                color: const Color(0xFF16161A).withOpacity(0.9),
                borderRadius: BorderRadius.circular(12 * scale),
                border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.5)),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
              ),
              child: Row(
                children: [
                  const Icon(Icons.class_rounded, color: Color(0xFF2EC4B6), size: 18),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    dropdownColor: const Color(0xFF242629),
                    value: _selectedClassForPen,
                    underline: const SizedBox(),
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    items: _classList.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) {
                      if (val != null && val != _selectedClassForPen) {
                        _saveAllAnnotations();
                        setState(() => _selectedClassForPen = val);
                        _lastLoadedUrl = null;
                        _loadAnnotations(_urlController.text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('🏫 [$val] 판서 데이터로 전환되었습니다.')),
                        );
                      }
                    },
                  ),
                ],
              ),
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
      try {
        const channel = MethodChannel('com.boardest/launch_args');
        channel.invokeMethod('setWebviewClickThrough', _isDrawMode);
      } catch (e) {
        debugPrint('[WebsiteBoardView] Failed to update webview clickthrough: $e');
      }
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
      onPrev: () => _navigatePage(false),
      onNext: () => _navigatePage(true),
      pageLabel: '페이지 $_currentPageIndex',
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
      onClose: () {
        if (widget.onBack != null) {
          widget.onBack!();
        } else {
          Navigator.pop(context);
        }
      },
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

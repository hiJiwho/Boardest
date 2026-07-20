import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../widgets/annotation_canvas.dart';
import '../services/storage_service.dart';
import '../services/bst_cloud_service.dart';

class PluginRunnerView extends StatefulWidget {
  final String pluginId;
  final String pluginName;
  final double scaleFactor;
  final AnnotationController? annotationController;

  const PluginRunnerView({
    super.key,
    required this.pluginId,
    required this.pluginName,
    this.scaleFactor = 1.0,
    this.annotationController,
  });

  @override
  State<PluginRunnerView> createState() => _PluginRunnerViewState();
}

class _PluginRunnerViewState extends State<PluginRunnerView> {
  late String _url;
  bool _initialized = false;
  
  // Manifest configurations
  String _displayMode = 'popup'; // 'popup' | 'fullscreen'
  bool _requiresCanvas = false;
  String? _websiteUrl;

  // Custom controller state for drawing
  bool _showDrawingToolbar = true;

  // Drag position for floating window mode
  Offset _position = const Offset(150, 150);

  // Windows WebView Controller
  final WebviewController _winController = WebviewController();
  late final AnnotationController _canvasController;

  @override
  void initState() {
    super.initState();
    _canvasController = widget.annotationController ?? AnnotationController();
    _loadManifestAndInit();
  }

  void _loadManifestAndInit() async {
    final appDir = await getApplicationSupportDirectory();
    final manifestFile = File(p.join(appDir.path, 'plugins', widget.pluginId, 'manifest.json'));
    
    String entryFile = 'index.html';
    
    if (manifestFile.existsSync()) {
      try {
        final data = json.decode(manifestFile.readAsStringSync());
        entryFile = data['entryFile'] ?? 'index.html';
        _displayMode = data['displayMode'] ?? 'popup';
        _requiresCanvas = data['requiresCanvas'] ?? false;
        _websiteUrl = data['url'];
      } catch (e) {
        debugPrint('[PluginRunner] manifest parsing error: $e');
      }
    }

    if (_websiteUrl != null && _websiteUrl!.isNotEmpty) {
      _url = _websiteUrl!;
    } else {
      _url = 'http://localhost:7777/plugins/${widget.pluginId}/$entryFile';
    }

    _initWebview();
  }

  void _initWebview() async {
    if (Platform.isWindows) {
      try {
        await _winController.initialize();
        
        _winController.webMessage.listen((msg) {
          if (msg is Map<String, dynamic>) {
            _handleSdkEvent(msg);
          }
        });

        // Inject rich Javascript SDK bridge including settings loading, USB, roles and bst-Cloud drive access
        await _winController.executeScript('''
          window.boardest = {
            drawStroke: function(strokeJson) {
              window.chrome.webview.postMessage({ type: 'drawStroke', stroke: strokeJson });
            },
            showNotification: function(message) {
              window.chrome.webview.postMessage({ type: 'showNotification', msg: message });
            },
            saveData: function(key, value) {
              window.chrome.webview.postMessage({ type: 'saveData', key: key, val: value });
            },
            usbDetected: async function() {
              window.chrome.webview.postMessage({ type: 'queryUsb' });
              return new Promise((resolve) => {
                window.addEventListener('boardestUsbReply', (e) => resolve(e.detail.connected), { once: true });
              });
            },
            getSettings: async function() {
              window.chrome.webview.postMessage({ type: 'querySettings' });
              return new Promise((resolve) => {
                window.addEventListener('boardestSettingsReply', (e) => resolve(e.detail.settings), { once: true });
              });
            },
            getRole: async function() {
              window.chrome.webview.postMessage({ type: 'queryRole' });
              return new Promise((resolve) => {
                window.addEventListener('boardestRoleReply', (e) => resolve(e.detail.role), { once: true });
              });
            },
            getCloudFiles: async function() {
              window.chrome.webview.postMessage({ type: 'queryCloudFiles' });
              return new Promise((resolve) => {
                window.addEventListener('boardestCloudFilesReply', (e) => resolve(e.detail.files), { once: true });
              });
            },
            close: function() {
              window.chrome.webview.postMessage({ type: 'close' });
            }
          };
        ''');

        await _winController.loadUrl(_url);
        setState(() => _initialized = true);
      } catch (e) {
        debugPrint('[PluginRunner] WebView initialize error: $e');
      }
    } else {
      setState(() => _initialized = true);
    }
  }

  void _handleSdkEvent(Map<String, dynamic> data) async {
    final type = data['type'];
    if (type == 'close') {
      Navigator.pop(context);
    } else if (type == 'showNotification') {
      final msg = data['msg'] as String? ?? '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } else if (type == 'saveData') {
      final key = data['key'] as String? ?? '';
      final val = data['val']?.toString() ?? '';
      if (key.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('plugin_${widget.pluginId}_$key', val);
      }
    } else if (type == 'queryUsb') {
      final prefs = await SharedPreferences.getInstance();
      final isUsb = prefs.getBool('usb_connected') ?? false;
      await _winController.executeScript('''
        window.dispatchEvent(new CustomEvent('boardestUsbReply', { detail: { connected: $isUsb } }));
      ''');
    } else if (type == 'querySettings') {
      final settings = await StorageService().getSettings();
      final settingsJson = json.encode(settings.toJson());
      await _winController.executeScript('''
        window.dispatchEvent(new CustomEvent('boardestSettingsReply', { detail: { settings: $settingsJson } }));
      ''');
    } else if (type == 'queryRole') {
      final appDir = await getApplicationSupportDirectory();
      final manifestFile = File(p.join(appDir.path, 'plugins', widget.pluginId, 'manifest.json'));
      String role = 'both';
      if (manifestFile.existsSync()) {
        try {
          final data = json.decode(manifestFile.readAsStringSync());
          role = data['role'] ?? 'both';
        } catch (_) {}
      }
      await _winController.executeScript('''
        window.dispatchEvent(new CustomEvent('boardestRoleReply', { detail: { role: '$role' } }));
      ''');
    } else if (type == 'queryCloudFiles') {
      final token = BstCloudService.instance.activeToken;
      final folderId = BstCloudService.instance.activeFolderId;
      List<Map<String, String>> filesList = [];
      if (token != null && folderId != null) {
        final files = await BstCloudService.instance.fetchDriveFiles(folderId, token);
        filesList = files.map((f) => {
          'id': f.id,
          'name': f.name,
          'mimeType': f.mimeType,
        }).toList();
      }
      final filesJson = json.encode(filesList);
      await _winController.executeScript('''
        window.dispatchEvent(new CustomEvent('boardestCloudFilesReply', { detail: { files: $filesJson } }));
      ''');
    } else if (type == 'drawStroke') {
      try {
        final strokeData = data['stroke'];
        if (strokeData is Map<String, dynamic>) {
          final stroke = AnnotationStroke.fromJson(strokeData);
          _canvasController.addStroke(stroke);
        }
      } catch (_) {}
    }
  }

  void _triggerPrevPage() async {
    if (Platform.isWindows) {
      if (_websiteUrl != null) {
        await _winController.executeScript('''
          document.dispatchEvent(new KeyboardEvent('keydown', { key: 'PageUp', keyCode: 33, bubbles: true }));
        ''');
      } else {
        await _winController.executeScript('''
          window.dispatchEvent(new CustomEvent('pagechange', { detail: { action: 'prev' } }));
        ''');
      }
    }
  }

  void _triggerNextPage() async {
    if (Platform.isWindows) {
      if (_websiteUrl != null) {
        await _winController.executeScript('''
          document.dispatchEvent(new KeyboardEvent('keydown', { key: 'PageDown', keyCode: 34, bubbles: true }));
        ''');
      } else {
        await _winController.executeScript('''
          window.dispatchEvent(new CustomEvent('pagechange', { detail: { action: 'next' } }));
        ''');
      }
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      _winController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    
    if (_displayMode == 'fullscreen') {
      return _buildFullscreenRunner(s);
    }
    return _buildPopupRunner(s);
  }

  Widget _buildPopupRunner(double s) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        child: Material(
          elevation: 12,
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 420 * s,
            height: 540 * s,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10, width: 1.5),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.extension_rounded, color: Color(0xFF00F5D4), size: 16),
                          const SizedBox(width: 8),
                          Text(
                            widget.pluginName,
                            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      _initialized
                          ? _buildWebViewLayer()
                          : const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4))),
                      
                      if (_requiresCanvas && _showDrawingToolbar)
                        AnnotationCanvas(
                          controller: _canvasController,
                        ),
                    ],
                  ),
                ),
                if (_requiresCanvas) _buildBottomControls(s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenRunner(double s) {
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF121214),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: const Color(0xFF1A1A1E),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.extension_rounded, color: Color(0xFF00F5D4)),
                      const SizedBox(width: 8),
                      Text(
                        widget.pluginName,
                        style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  _initialized
                      ? _buildWebViewLayer()
                      : const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4))),
                  
                  if (_requiresCanvas && _showDrawingToolbar)
                    AnnotationCanvas(
                      controller: _canvasController,
                    ),
                ],
              ),
            ),
            if (_requiresCanvas) _buildBottomControls(s),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls(double s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF0F0E13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.navigate_before_rounded, color: Colors.white),
                onPressed: _triggerPrevPage,
                tooltip: '이전 페이지',
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.navigate_next_rounded, color: Colors.white),
                onPressed: _triggerNextPage,
                tooltip: '다음 페이지',
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _showDrawingToolbar ? Icons.edit_off_rounded : Icons.edit_rounded,
                  color: _showDrawingToolbar ? const Color(0xFF00F5D4) : Colors.white60,
                ),
                onPressed: () {
                  setState(() {
                    _showDrawingToolbar = !_showDrawingToolbar;
                  });
                },
                tooltip: '판서 활성화/비활성화',
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white60),
                onPressed: () {
                  _canvasController.clear();
                },
                tooltip: '판서 초기화',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebViewLayer() {
    if (Platform.isWindows) {
      return Webview(_winController);
    } else {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'BoardestChannel',
          onMessageReceived: (JavaScriptMessage msg) {
            try {
              final data = jsonDecode(msg.message);
              _handleSdkEvent(data);
            } catch (_) {}
          },
        )
        ..loadRequest(Uri.parse(_url));

      controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            controller.runJavaScript('''
              window.boardest = {
                drawStroke: function(strokeJson) {
                  BoardestChannel.postMessage(JSON.stringify({ type: 'drawStroke', stroke: strokeJson }));
                },
                showNotification: function(message) {
                  BoardestChannel.postMessage(JSON.stringify({ type: 'showNotification', msg: message }));
                },
                saveData: function(key, value) {
                  BoardestChannel.postMessage(JSON.stringify({ type: 'saveData', key: key, val: value }));
                },
                usbDetected: async function() {
                  BoardestChannel.postMessage(JSON.stringify({ type: 'queryUsb' }));
                  return new Promise((resolve) => {
                    window.addEventListener('boardestUsbReply', (e) => resolve(e.detail.connected), { once: true });
                  });
                },
                getSettings: async function() {
                  BoardestChannel.postMessage(JSON.stringify({ type: 'querySettings' }));
                  return new Promise((resolve) => {
                    window.addEventListener('boardestSettingsReply', (e) => resolve(e.detail.settings), { once: true });
                  });
                },
                getRole: async function() {
                  BoardestChannel.postMessage(JSON.stringify({ type: 'queryRole' }));
                  return new Promise((resolve) => {
                    window.addEventListener('boardestRoleReply', (e) => resolve(e.detail.role), { once: true });
                  });
                },
                getCloudFiles: async function() {
                  BoardestChannel.postMessage(JSON.stringify({ type: 'queryCloudFiles' }));
                  return new Promise((resolve) => {
                    window.addEventListener('boardestCloudFilesReply', (e) => resolve(e.detail.files), { once: true });
                  });
                },
                close: function() {
                  BoardestChannel.postMessage(JSON.stringify({ type: 'close' }));
                }
              };
            ''');
          },
        ),
      );
      return WebViewWidget(controller: controller);
    }
  }
}

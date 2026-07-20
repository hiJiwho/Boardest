import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';

/// Boardest-Board 광고 차단 순수 웹 브라우저 (판서 툴바 완벽 제거)
class BrowserBoardView extends StatefulWidget {
  final double scaleFactor;
  final String? initialUrl;
  final VoidCallback? onBack;

  const BrowserBoardView({
    super.key,
    required this.scaleFactor,
    this.initialUrl,
    this.onBack,
  });

  @override
  State<BrowserBoardView> createState() => _BrowserBoardViewState();
}

class _BrowserBoardViewState extends State<BrowserBoardView> {
  late final TextEditingController _urlController;
  WebviewController? _winWebviewController;
  WebViewController? _androidWebController;

  bool _isWebviewInitialized = false;
  bool _adBlockEnabled = true;
  static const String _defaultUrl = 'https://www.google.com';

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? _defaultUrl);

    if (Platform.isWindows) {
      _initWindowsWebview();
    } else if (Platform.isAndroid) {
      _initAndroidWebview();
    }
  }

  Future<void> _initWindowsWebview() async {
    try {
      _winWebviewController = WebviewController();
      await _winWebviewController!.initialize();
      _winWebviewController!.url.listen((url) {
        if (mounted) setState(() => _urlController.text = url);
      });
      await _winWebviewController!.loadUrl(_urlController.text);
      if (mounted) setState(() => _isWebviewInitialized = true);
    } catch (e) {
      debugPrint('[BrowserBoardView] Windows WebView init error: $e');
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
          onNavigationRequest: (NavigationRequest request) {
            if (_adBlockEnabled) {
              final url = request.url.toLowerCase();
              if (url.contains('doubleclick.net') ||
                  url.contains('googlesyndication.com') ||
                  url.contains('adservice.google.com') ||
                  url.contains('adnxs.com') ||
                  url.contains('popads.net')) {
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_urlController.text));
    setState(() => _isWebviewInitialized = true);
  }

  void _navigateToUrl() {
    var url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'https://$url';

    if (Platform.isWindows && _winWebviewController != null) {
      _winWebviewController!.loadUrl(url);
    } else if (Platform.isAndroid && _androidWebController != null) {
      _androidWebController!.loadRequest(Uri.parse(url));
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _winWebviewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;

    return Scaffold(
      backgroundColor: const Color(0xFF16161A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar (Pure Browser Bar)
            Container(
              height: 52 * scale,
              padding: EdgeInsets.symmetric(horizontal: 12 * scale),
              color: const Color(0xFF16161A),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () {
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                    onPressed: () {
                      if (Platform.isWindows && _winWebviewController != null) {
                        _winWebviewController!.reload();
                      } else if (Platform.isAndroid && _androidWebController != null) {
                        _androidWebController!.reload();
                      }
                    },
                  ),
                  SizedBox(width: 8 * scale),
                  Expanded(
                    child: Container(
                      height: 38 * scale,
                      decoration: BoxDecoration(
                        color: const Color(0xFF242629),
                        borderRadius: BorderRadius.circular(20 * scale),
                        border: Border.all(color: Colors.white12),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 14 * scale),
                      child: Row(
                        children: [
                          Icon(
                            _adBlockEnabled ? Icons.security_rounded : Icons.language_rounded,
                            size: 16 * scale,
                            color: _adBlockEnabled ? const Color(0xFF2EC4B6) : Colors.white54,
                          ),
                          SizedBox(width: 8 * scale),
                          Expanded(
                            child: TextField(
                              controller: _urlController,
                              style: TextStyle(color: Colors.white, fontSize: 13 * scale),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                hintText: 'URL 또는 검색어 입력…',
                                hintStyle: TextStyle(color: Colors.white38),
                              ),
                              onSubmitted: (_) => _navigateToUrl(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF2EC4B6), size: 18),
                            onPressed: _navigateToUrl,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  Tooltip(
                    message: _adBlockEnabled ? '광고 차단 활성화됨' : '광고 차단 비활성화',
                    child: IconButton(
                      icon: Icon(
                        _adBlockEnabled ? Icons.shield_rounded : Icons.shield_outlined,
                        color: _adBlockEnabled ? const Color(0xFF2EC4B6) : Colors.white38,
                      ),
                      onPressed: () => setState(() => _adBlockEnabled = !_adBlockEnabled),
                    ),
                  ),
                ],
              ),
            ),

            // Pure WebView Body (No annotation overlay, no floating dock)
            Expanded(
              child: _buildWebView(),
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
          '🛡️ 안전 웹 브라우저 로딩 중…',
          style: GoogleFonts.notoSansKr(color: Colors.white38),
        ),
      );
    }
  }
}

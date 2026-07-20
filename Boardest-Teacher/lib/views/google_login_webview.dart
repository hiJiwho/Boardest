import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

class GoogleLoginWebview extends StatefulWidget {
  const GoogleLoginWebview({super.key});

  @override
  State<GoogleLoginWebview> createState() => _GoogleLoginWebviewState();
}

class _GoogleLoginWebviewState extends State<GoogleLoginWebview> {
  final WebviewController _controller = WebviewController();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initWebview();
  }

  Future<void> _initWebview() async {
    try {
      await _controller.initialize();
      // Bypasses the embedded Webview User-Agent block from Google Sign-In
      await _controller.setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      );
      await _controller.loadUrl('https://boardest.web.app/');
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing WebView2: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google 계정 로그인 (Webview2)'),
        backgroundColor: const Color(0xFF16161A),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0F0E17),
      body: _initialized
          ? Webview(_controller)
          : const Center(
              child: CircularProgressIndicator(color: Color(0xFF7F5AF0)),
            ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

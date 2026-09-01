import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_windows/webview_windows.dart';

/// Canva 교사용 계정 로그인 전용 WebView
class CanvaLoginWebview extends StatefulWidget {
  const CanvaLoginWebview({super.key});

  @override
  State<CanvaLoginWebview> createState() => _CanvaLoginWebviewState();
}

class _CanvaLoginWebviewState extends State<CanvaLoginWebview> {
  final _controller = WebviewController();
  bool _isReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initWebview();
  }

  Future<void> _initWebview() async {
    try {
      await _controller.initialize();
      await _controller.loadUrl('https://www.canva.com/login');
      if (mounted) {
        setState(() {
          _isReady = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Canva 로그인 창 로드 오류: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161A),
        foregroundColor: Colors.white,
        title: Text(
          'Canva 교사용 로그인 연동',
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00F5D4)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🟢 Canva 로그인 연동 상태가 설정되었습니다.'),
                  backgroundColor: Color(0xFF7F5AF0),
                ),
              );
              Navigator.pop(context, true);
            },
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Text(
                _error!,
                style: GoogleFonts.notoSansKr(color: const Color(0xFFEF4565)),
              ),
            )
          : !_isReady
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00C4CC)),
                )
              : Webview(_controller),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CanvaLibraryView extends StatefulWidget {
  final String url;

  const CanvaLibraryView({
    Key? key,
    required this.url,
  }) : super(key: key);

  @override
  State<CanvaLibraryView> createState() => _CanvaLibraryViewState();
}

class _CanvaLibraryViewState extends State<CanvaLibraryView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            // Canva 약관/쿠키 배너 숨김 처리 스크립트
            _controller.runJavaScript('''
              try {
                // 쿠키 배너와 관련된 다양한 선택자들
                const selectors = [
                  'div[data-testid="cookie-banner"]',
                  '.cookie-banner',
                  'div[role="dialog"]'
                ];
                
                selectors.forEach(selector => {
                  document.querySelectorAll(selector).forEach(e => {
                    if (e.innerText.includes('cookie') || e.innerText.includes('쿠키') || e.innerText.includes('terms') || e.innerText.includes('약관')) {
                      e.style.display = 'none';
                    }
                  });
                });
              } catch (e) {
                console.error('Error hiding Canva banner:', e);
              }
            ''');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CanvaBoardView extends StatefulWidget {
  final String boardUrl;

  const CanvaBoardView({
    Key? key,
    required this.boardUrl,
  }) : super(key: key);

  @override
  State<CanvaBoardView> createState() => _CanvaBoardViewState();
}

class _CanvaBoardViewState extends State<CanvaBoardView> {
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
      ..loadRequest(Uri.parse(widget.boardUrl));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

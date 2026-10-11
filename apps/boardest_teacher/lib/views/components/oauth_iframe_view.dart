import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'oauth_iframe_stub.dart'
    if (dart.library.html) 'oauth_iframe_web.dart' as impl;

class OAuthIFrameView extends StatelessWidget {
  final String url;
  final double height;

  const OAuthIFrameView({
    super.key,
    required this.url,
    this.height = 560,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return Container(
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_sync_rounded, color: Color(0xFF00F5D4), size: 48),
            const SizedBox(height: 16),
            const Text(
              '웹 브라우저에서 OAuth 설정 진행',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '데스크톱 앱에서는 외부 브라우저를 통해 안전하게 구글 드라이브 및 설정을 연동합니다.',
              style: TextStyle(color: Color(0xFF94A1B2), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return impl.buildOAuthIFrame(url: url, height: height);
  }
}

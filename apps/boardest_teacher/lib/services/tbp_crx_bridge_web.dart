import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class TbpCrxBridge {
  TbpCrxBridge._();
  static final TbpCrxBridge instance = TbpCrxBridge._();

  String extensionId = 'boardest_boardbook_crx';

  Future<bool> checkExtensionInstalled() async {
    if (!kIsWeb) return false;
    try {
      final chrome = js_util.getProperty(html.window, 'chrome');
      if (chrome == null) return false;
      final runtime = js_util.getProperty(chrome, 'runtime');
      if (runtime == null) return false;

      final completer = Completer<bool>();
      final jsReq = js_util.jsify({'action': 'CHECK_INSTALLED'});
      
      js_util.callMethod(runtime, 'sendMessage', [
        extensionId,
        jsReq,
        js_util.allowInterop((response) {
          if (response != null && js_util.getProperty(response, 'installed') == true) {
            completer.complete(true);
          } else {
            completer.complete(false);
          }
        }),
      ]);

      return await completer.future.timeout(const Duration(milliseconds: 600), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> launchBoardBookExtension({
    required BuildContext context,
    required String title,
    required String fileUrl,
    required String type,
    String? driveToken,
    String? pointerId,
  }) async {
    if (!kIsWeb) return false;

    try {
      final chrome = js_util.getProperty(html.window, 'chrome');
      final runtime = chrome != null ? js_util.getProperty(chrome, 'runtime') : null;

      if (runtime != null) {
        final completer = Completer<bool>();
        final jsReq = js_util.jsify({
          'action': 'LAUNCH_BOARDBOOK',
          'title': title,
          'fileUrl': fileUrl,
          'type': type,
          'driveToken': driveToken ?? '',
          'pointerId': pointerId ?? '',
        });

        js_util.callMethod(runtime, 'sendMessage', [
          extensionId,
          jsReq,
          js_util.allowInterop((response) {
            if (response != null && js_util.getProperty(response, 'success') == true) {
              completer.complete(true);
            } else {
              completer.complete(false);
            }
          }),
        ]);

        final success = await completer.future.timeout(const Duration(seconds: 2), onTimeout: () => false);
        if (success) return true;
      }
    } catch (_) {}

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.extension_rounded, color: Color(0xFF00F5D4), size: 24),
              SizedBox(width: 10),
              Text('BoardBook 실행 안내', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '웹 브라우저에서 [$title] ($type) 교안을 우측 판서와 사이트 조작으로 이용하시려면 크롬 익스텐션 또는 전용 앱이 필요합니다.',
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () {
                  html.window.open('/downloads/boardbook_extension.zip', '_blank');
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.download_rounded, color: Color(0xFF00F5D4), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('BoardBook 익스텐션 다운로드 (.zip)', style: TextStyle(color: Color(0xFF00F5D4), fontSize: 13, fontWeight: FontWeight.bold)),
                            Text('다운로드 후 chrome://extensions 에 등록', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () {
                  html.window.open('https://boardest-downloads.web.app', '_blank');
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F5AF0).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF7F5AF0).withOpacity(0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.devices_rounded, color: Color(0xFF9E86F8), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Boardest 전용 앱 다운로드', style: TextStyle(color: Color(0xFF9E86F8), fontSize: 13, fontWeight: FontWeight.bold)),
                            Text('Windows AppX / Android APK 설치', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      );
    }
    return false;
  }
}

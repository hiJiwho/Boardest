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

  // 기본 확장 프로그램 ID (배포 또는 개발자 로드 시의 ID)
  String extensionId = 'boardest_boardbook_crx';

  /// 크롬 익스텐션 설치 여부 및 통신 확인
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

  /// Boardest에서 BoardBook Chrome Extension으로 토큰 및 교안 정보 핸드오프
  Future<bool> launchBoardBookExtension({
    required BuildContext context,
    required String title,
    required String fileUrl,
    required String type, // 'TBP' or 'HTMLP'
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

    // 익스텐션 미설치 또는 실패 시: 안내 모달 띄우기
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.extension_rounded, color: Color(0xFF00F5D4)),
              SizedBox(width: 8),
              Text('BoardBook 익스텐션 필요', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '웹 브라우저 환경에서 [$title] ($type) 교안을 완벽한 우측 판서와 사이트 조작으로 이용하려면 "Boardest BoardBook Chrome Extension"이 필요합니다.',
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '💡 크롬 설정 > 확장 프로그램 관리에서 "압축해제된 확장 프로그램을 로드합니다"를 통해 apps/boardest_crx_boardbook 폴더를 등록하시거나, Boardest 전용 데스크톱 앱(Windows)을 이용해 주세요.',
                  style: TextStyle(color: Color(0xFF94A1B2), fontSize: 11, height: 1.4),
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

// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart';

Future<String?> captureCurrentBrowserScreenHash() async {
  try {
    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) return null;

    final options = js_util.jsify({
      'video': {
        'displaySurface': 'browser',
        'preferCurrentTab': true,
      },
      'audio': false,
    });

    final streamPromise = js_util.callMethod(mediaDevices, 'getDisplayMedia', [options]);
    final html.MediaStream mediaStream = await js_util.promiseToFuture(streamPromise);

    final videoTracks = mediaStream.getVideoTracks();
    if (videoTracks.isEmpty) return null;

    final video = html.VideoElement();
    video.srcObject = mediaStream;
    video.muted = true;
    await video.play();

    // 1프레임 대기
    await Future.delayed(const Duration(milliseconds: 150));

    final canvas = html.CanvasElement(width: 17, height: 16);
    final ctx = canvas.context2D;
    ctx.drawImageScaled(video, 0, 0, 17, 16);

    // 스트림 정지 (자원 해제)
    for (final track in videoTracks) {
      track.stop();
    }

    final imgData = ctx.getImageData(0, 0, 17, 16).data;
    final gray = <double>[];
    for (int i = 0; i < imgData.length; i += 4) {
      gray.add(imgData[i] * 0.299 + imgData[i + 1] * 0.587 + imgData[i + 2] * 0.114);
    }

    final buffer = StringBuffer();
    for (int y = 0; y < 16; y++) {
      for (int x = 0; x < 16; x++) {
        final idx = y * 17 + x;
        buffer.write(gray[idx] > gray[idx + 1] ? '1' : '0');
      }
    }

    final hash = buffer.toString();
    debugPrint('[TbpWebCapture] Captured dHash: ${hash.substring(0, 32)}...');
    return hash;
  } catch (e) {
    debugPrint('[TbpWebCapture] capture error: $e');
    return null;
  }
}

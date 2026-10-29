// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

Future<void> requestWebNotificationPermission() async {
  try {
    if (html.Notification.permission != 'granted') {
      final res = await html.Notification.requestPermission();
      debugPrint('[WebNotification] Permission result: $res');
    }
  } catch (e) {
    debugPrint('[WebNotification] requestPermission error: $e');
  }
}

void showWebBrowserNotification({required String title, required String body}) {
  try {
    if (html.Notification.permission == 'granted') {
      html.Notification(
        title,
        body: body,
        icon: '/favicon.png',
      );
    }
    playNotificationChime();
  } catch (e) {
    debugPrint('[WebNotification] showNotification error: $e');
  }
}

void playNotificationChime() {
  try {
    final ctx = html.AudioContext();
    final osc = ctx.createOscillator();
    final gain = ctx.createGain();

    osc.type = 'sine';

    final num currentTime = ctx.currentTime ?? 0.0;
    osc.frequency?.setValueAtTime(587.33, currentTime);
    osc.frequency?.exponentialRampToValueAtTime(880.0, currentTime + 0.15);

    gain.gain?.setValueAtTime(0.3, currentTime);
    gain.gain?.exponentialRampToValueAtTime(0.001, currentTime + 0.6);

    osc.connect(gain);
    if (ctx.destination != null) {
      gain.connect(ctx.destination!);
    }

    osc.start();
    osc.stop(currentTime + 0.6);
  } catch (e) {
    debugPrint('[WebNotification] playNotificationChime error: $e');
  }
}

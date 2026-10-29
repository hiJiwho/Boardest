// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js' as js;
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
    js.context.callMethod('eval', [r'''
      (function() {
        try {
          const AudioContext = window.AudioContext || window.webkitAudioContext;
          if (!AudioContext) return;
          const ctx = new AudioContext();
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'sine';
          const t = ctx.currentTime;
          osc.frequency.setValueAtTime(587.33, t);
          osc.frequency.exponentialRampToValueAtTime(880.0, t + 0.15);
          gain.gain.setValueAtTime(0.3, t);
          gain.gain.exponentialRampToValueAtTime(0.001, t + 0.6);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(t);
          osc.stop(t + 0.6);
        } catch (_) {}
      })();
    ''']);
  } catch (e) {
    debugPrint('[WebNotification] playNotificationChime error: $e');
  }
}

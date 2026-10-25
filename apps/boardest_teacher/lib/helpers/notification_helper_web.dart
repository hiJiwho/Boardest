// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
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
    final audioCtxClass = js_util.getProperty(html.window, 'AudioContext') ??
        js_util.getProperty(html.window, 'webkitAudioContext');
    if (audioCtxClass == null) return;

    final dynamic ctx = js_util.callConstructor(audioCtxClass, []);
    final dynamic osc = js_util.callMethod(ctx, 'createOscillator', []);
    final dynamic gain = js_util.callMethod(ctx, 'createGain', []);

    js_util.setProperty(osc, 'type', 'sine');

    final double currentTime = js_util.getProperty(ctx, 'currentTime') ?? 0.0;
    final dynamic oscFreq = js_util.getProperty(osc, 'frequency');
    js_util.callMethod(oscFreq, 'setValueAtTime', [587.33, currentTime]);
    js_util.callMethod(oscFreq, 'exponentialRampToValueAtTime', [880.0, currentTime + 0.15]);

    final dynamic gainNode = js_util.getProperty(gain, 'gain');
    js_util.callMethod(gainNode, 'setValueAtTime', [0.3, currentTime]);
    js_util.callMethod(gainNode, 'exponentialRampToValueAtTime', [0.001, currentTime + 0.6]);

    js_util.callMethod(osc, 'connect', [gain]);
    js_util.callMethod(gain, 'connect', [js_util.getProperty(ctx, 'destination')]);

    js_util.callMethod(osc, 'start', []);
    js_util.callMethod(osc, 'stop', [currentTime + 0.6]);
  } catch (e) {
    debugPrint('[WebNotification] playNotificationChime error: $e');
  }
}

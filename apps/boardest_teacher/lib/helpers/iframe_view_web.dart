import 'package:flutter/material.dart';
import 'dart:ui_web' as ui_web;
import 'dart:js_interop';
import 'package:web/web.dart' as web;

bool _allowIframePointerEvents = false;
final List<web.HTMLIFrameElement> _registeredIframes = [];

void setWebIframePointerEvents(bool allow) {
  _allowIframePointerEvents = allow;
  final val = allow ? 'auto' : 'none';
  for (final iframe in _registeredIframes) {
    try {
      iframe.style.pointerEvents = val;
    } catch (_) {}
  }
  try {
    final nodes = web.document.querySelectorAll('iframe');
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes.item(i);
      if (node != null) {
        (node as web.HTMLIFrameElement).style.pointerEvents = val;
      }
    }
  } catch (_) {}
}

void sendWebVirtualKeyToIframe(String key, int keyCode) {
  for (final iframe in _registeredIframes) {
    try {
      final cw = iframe.contentWindow;
      if (cw != null) {
        cw.postMessage(
          {'type': 'keyEvent', 'key': key, 'keyCode': keyCode}.jsify(),
          '*'.toJS,
        );
      }
    } catch (_) {}
  }
}

Widget buildIframeView(String viewType, String url) {
  try {
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId) {
        final iframe = web.HTMLIFrameElement()
          ..src = url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.pointerEvents = _allowIframePointerEvents ? 'auto' : 'none'
          ..allow = 'fullscreen; autoplay; clipboard-read; clipboard-write';
        _registeredIframes.add(iframe);
        return iframe;
      },
    );
  } catch (_) {}
  return HtmlElementView(viewType: viewType);
}

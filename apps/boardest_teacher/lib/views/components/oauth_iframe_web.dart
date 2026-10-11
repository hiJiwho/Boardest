// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

Widget buildOAuthIFrame({required String url, double height = 500}) {
  final viewType = 'oauth-iframe-${url.hashCode}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = html.IFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'camera; microphone; clipboard-write; clipboard-read';
    return iframe;
  });

  return SizedBox(
    height: height,
    width: double.infinity,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: HtmlElementView(viewType: viewType),
    ),
  );
}

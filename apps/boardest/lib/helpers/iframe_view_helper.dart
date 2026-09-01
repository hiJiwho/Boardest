import 'package:flutter/material.dart';
import 'iframe_view_stub.dart'
    if (dart.library.html) 'iframe_view_web.dart'
    if (dart.library.js_interop) 'iframe_view_web.dart';

Widget getIframeViewWidget(String viewType, String url) {
  return buildIframeView(viewType, url);
}

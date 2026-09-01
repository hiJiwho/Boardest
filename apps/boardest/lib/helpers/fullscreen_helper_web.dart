import 'dart:html' as html;

void toggleFullscreenImpl() {
  try {
    final doc = html.document;
    if (doc.fullscreenElement != null) {
      doc.exitFullscreen();
    } else {
      doc.documentElement?.requestFullscreen();
    }
  } catch (_) {}
}

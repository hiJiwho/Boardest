import 'fullscreen_helper_stub.dart'
    if (dart.library.html) 'fullscreen_helper_web.dart';

void toggleAppFullscreen() {
  toggleFullscreenImpl();
}

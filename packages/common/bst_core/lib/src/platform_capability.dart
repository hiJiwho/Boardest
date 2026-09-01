import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class PlatformCapability {
  static bool get isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isWeb => kIsWeb;

  // Windows 전용 네이티브
  static bool get supportsNativeOverlay => isWindows;  // HWP/PPT
  static bool get supportsFfmpeg => isWindows;
  static bool get supportsUsb => isWindows;
  static bool get supportsSystemTray => isWindows;
  static bool get supportsRegistry => isWindows;

  // Web 전용
  static bool get supportsWebFileSystem => isWeb;  // File System Access API
  static bool get supportsPwa => isWeb;
  static bool get needsComciganProxy => isWeb;     // HTTP→HTTPS 프록시 필요

  // 터치 전용
  static bool get isTouchPrimary => isAndroid || isWeb;
}

import 'package:flutter/foundation.dart';

class NativeStartupHelper {
  /// 웹 빌드에서는 크래시 로그를 디버그 콘솔에만 출력합니다.
  static void writeCrashLog(String error, String stackTrace) {
    debugPrint('[Boardest Web Fatal] $error\n$stackTrace');
  }

  /// 웹 빌드에서는 Windows 종속 태스크(단축키 생성, Watchdog 등)를 무시합니다.
  static void runWindowsStartupTasks() {
    debugPrint('[Boardest Web] Bypassing Windows native startup tasks.');
  }
}

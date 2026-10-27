import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../services/app_paths.dart';
import '../services/system_app_scanner.dart';
import '../config/app_config.dart';

class NativeStartupHelper {
  static void writeCrashLog(String error, String stackTrace) {
    try {
      final now = DateTime.now().toIso8601String();
      final logContent = '''
======================================================
[Boardest Crash Log]
Timestamp: $now
Error: $error
StackTrace:
$stackTrace
======================================================
\n''';

      final appLog = File(AppPaths.crashLogPath);
      appLog.parent.createSync(recursive: true);
      appLog.writeAsStringSync(logContent, mode: FileMode.append);

      if (Platform.isWindows) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final exeLog = File(p.join(exeDir, 'crash_logs.txt'));
        exeLog.writeAsStringSync(logContent, mode: FileMode.append);
      }
    } catch (e) {
      debugPrint('Failed to write crash log: $e');
    }
  }

  static void runWindowsStartupTasks() {
    if (kDebugMode || kIsWeb || !Platform.isWindows) return;
    if (AppConfig.isCloudMode || AppConfig.isToolsMode) return; // bcld: 부팅 시 자동 실행 안 함
    SystemAppScanner.createWindowsShortcuts();
    SystemAppScanner.ensureWindowsRunAtStartup();
  }
}

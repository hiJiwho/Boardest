import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../services/app_paths.dart';
import '../services/system_app_scanner.dart';

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
    if (Platform.isWindows) {
      SystemAppScanner.createWindowsShortcuts();
      SystemAppScanner.ensureWindowsRunAtStartup();
      _startWindowsWatchdog();
    }
  }

  static void _startWindowsWatchdog() async {
    try {
      final int myPid = pid;
      final String exePath = Platform.resolvedExecutable;
      final String exeDir = File(exePath).parent.path;
      String watchdogExe = p.join(exeDir, 'watchdog.exe');
      if (!await File(watchdogExe).exists()) {
        watchdogExe = p.join(Directory.current.path, 'watchdog.exe');
      }
      if (!await File(watchdogExe).exists()) {
        watchdogExe = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', 'watchdog.exe');
      }
      if (!await File(watchdogExe).exists()) {
        watchdogExe = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Debug', 'watchdog.exe');
      }
      if (!await File(watchdogExe).exists()) {
        watchdogExe = p.join(Directory.current.path, 'build', 'outputs', 'windows', 'Release', 'watchdog.exe');
      }

      if (await File(watchdogExe).exists()) {
        await Process.start(
          watchdogExe,
          ['$myPid', exePath],
          mode: ProcessStartMode.detached,
        );
        debugPrint('[Boardest Watchdog] Background resurrection C# watchdog started for PID $myPid.');
      } else {
        debugPrint('[Boardest Watchdog] C# watchdog executable not found at: $watchdogExe');
      }
    } catch (e) {
      debugPrint('[Boardest Watchdog] Failed to start C# watchdog: $e');
    }
  }
}

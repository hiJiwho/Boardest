import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'package:bst_core/bst_core.dart';

class PptHelper {
  static const String _executableName = 'boardest_ppt_overlay.exe';

  /// Resolves the executable path from AppX package or fallback.
  static Future<String> _resolvePath() async {
    final exe = await PanserPluginService.ensureExecutable(_executableName);
    return exe ?? _executableName;
  }

  /// Runs the PPT helper executable and returns the result.
  static Future<ProcessResult?> run(List<String> arguments) async {
    if (kIsWeb || !Platform.isWindows) {
      print('PptHelper is only supported on Windows.');
      return null;
    }

    try {
      final target = await _resolvePath();
      final result = await Process.run(target, arguments);
      return result;
    } catch (e) {
      print('Failed to run $_executableName: $e');
      return null;
    }
  }

  /// Starts the PPT helper executable and returns the process.
  static Future<Process?> start(List<String> arguments) async {
    if (kIsWeb || !Platform.isWindows) {
      print('PptHelper is only supported on Windows.');
      return null;
    }

    try {
      final target = await _resolvePath();
      final process = await Process.start(target, arguments);
      return process;
    } catch (e) {
      print('Failed to start $_executableName: $e');
      return null;
    }
  }
}

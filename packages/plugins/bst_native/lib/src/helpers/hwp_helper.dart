import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

class HwpHelper {
  static const String _executableName = 'boardest_hwp_overlay.exe';

  /// Runs the HWP helper executable and returns the result.
  static Future<ProcessResult?> run(List<String> arguments) async {
    if (kIsWeb || !Platform.isWindows) {
      print('HwpHelper is only supported on Windows.');
      return null;
    }

    try {
      final result = await Process.run(_executableName, arguments);
      return result;
    } catch (e) {
      print('Failed to run $_executableName: $e');
      return null;
    }
  }

  /// Starts the HWP helper executable and returns the process.
  static Future<Process?> start(List<String> arguments) async {
    if (kIsWeb || !Platform.isWindows) {
      print('HwpHelper is only supported on Windows.');
      return null;
    }

    try {
      final process = await Process.start(_executableName, arguments);
      return process;
    } catch (e) {
      print('Failed to start $_executableName: $e');
      return null;
    }
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show BuildContext, MediaQuery;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Boardest 데이터 경로 (%APPDATA% on Windows, app support dir on mobile).
class AppPaths {
  AppPaths._();

  static String? _dataRoot;
  static bool _initialized = false;

  static String get dataRootSync {
    if (_dataRoot != null) return _dataRoot!;
    if (Platform.isWindows) {
      return p.join(
        Platform.environment['APPDATA'] ?? Directory.systemTemp.path,
        'Boardest',
      );
    }
    return p.join(Directory.systemTemp.path, 'Boardest');
  }

  static String get bstSaveRootSync {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      return p.join(appData, 'BstSave');
    }
    return p.join(dataRootSync, 'BstSave');
  }

  static String get crashLogPath => p.join(dataRootSync, 'crash_logs.txt');

  static String get configDir => p.join(dataRootSync, 'config');

  static String get schoolConfigPath => p.join(configDir, 'school_config.json');

  static Future<void> init() async {
    if (_initialized) return;
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      _dataRoot = p.join(appData, 'Boardest');
    } else if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationSupportDirectory();
      _dataRoot = p.join(dir.path, 'Boardest');
    } else {
      _dataRoot = p.join(Directory.systemTemp.path, 'Boardest');
    }
    await Directory(_dataRoot!).create(recursive: true);
    await Directory(configDir).create(recursive: true);
    _initialized = true;
  }

  /// 1920×1080 기준 UI 스케일 (FHD 이하에서 박스 침범 방지).
  static double adaptiveUiScale(BuildContext context, double userScaleFactor) {
    if (kIsWeb) return userScaleFactor;
    final size = MediaQuery.sizeOf(context);
    const refW = 1920.0;
    const refH = 1080.0;
    final fit = (size.width / refW) < (size.height / refH)
        ? size.width / refW
        : size.height / refH;
    final adaptive = fit.clamp(0.72, 1.05);
    return userScaleFactor * adaptive;
  }
}

import 'package:universal_io/io.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show BuildContext, MediaQuery;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Boardest 전자칠판용 앱 데이터 경로 (%APPDATA%\jiwho.boardest.board).
class AppPaths {
  AppPaths._();

  static const String appName = 'jiwho.boardest.board';
  static String? _dataRoot;
  static bool _initialized = false;

  /// 앱 기본 최상위 데이터 폴더 (%APPDATA%\jiwho.boardest.board)
  static String get dataRootSync {
    if (_dataRoot != null) return _dataRoot!;
    if (!kIsWeb && Platform.isWindows) {
      return p.join(
        Platform.environment['APPDATA'] ?? Directory.systemTemp.path,
        appName,
      );
    }
    return appName;
  }

  /// 설정 및 자료 저장 폴더 (%APPDATA%\jiwho.boardest.board\bst-save)
  static String get bstSaveRootSync {
    return p.join(dataRootSync, 'bst-save');
  }

  /// 판서 저장 폴더 (%APPDATA%\jiwho.boardest.board\bst-pen)
  static String get bstPenRootSync {
    return p.join(dataRootSync, 'bst-pen');
  }

  /// Bst-cld 임시 작업 폴더
  static String get bstCldTempDirSync {
    if (kIsWeb) return 'bst-cld-Temp';
    final tempDir = p.join(dataRootSync, 'bst-cld-Temp');
    final dir = Directory(tempDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return tempDir;
  }

  /// 크래시 로그 파일 위치
  static String get crashLogPath => p.join(dataRootSync, 'crash_logs.txt');

  /// C++ / C# 헬퍼 오버레이 실행 폴더 (%APPDATA%\jiwho.boardest.board\Cpp-runner)
  static String get cppRunnerDirSync {
    if (kIsWeb) return 'Cpp-runner';
    final runnerDir = p.join(dataRootSync, 'Cpp-runner');
    final dir = Directory(runnerDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return runnerDir;
  }

  /// 설정 저장 폴더 위치 (%APPDATA%\jiwho.boardest.board\bst-save\config)
  static String get configDir => p.join(bstSaveRootSync, 'config');

  /// 학교 기본 설정 파일 위치 (%APPDATA%\jiwho.boardest.board\bst-save\config\school_config.json)
  static String get schoolConfigPath => p.join(configDir, 'school_config.json');

  static Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      _dataRoot = appName;
      _initialized = true;
      return;
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      _dataRoot = p.join(appData, appName);
      
      // Cleanup legacy com.boardest folders if present in APPDATA
      try {
        for (final legacy in ['com.boardest', 'com.boardest.comcigan']) {
          final dir = Directory(p.join(appData, legacy));
          if (dir.existsSync()) {
            dir.deleteSync(recursive: true);
          }
        }
      } catch (e) {
        debugPrint('[AppPaths] Cleanup legacy folder error: $e');
      }
    } else if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationSupportDirectory();
      _dataRoot = p.join(dir.path, appName);
    } else {
      _dataRoot = p.join(Directory.systemTemp.path, appName);
    }
    await Directory(_dataRoot!).create(recursive: true);
    await Directory(bstSaveRootSync).create(recursive: true);
    await Directory(bstPenRootSync).create(recursive: true);
    await Directory(configDir).create(recursive: true);
    _initialized = true;
  }

  /// 1920×1080 기준 화면비 동적 UI 스케일 (오버플로우 방지 및 Android 80% 배율 적용)
  static double adaptiveUiScale(BuildContext context, double userScaleFactor) {
    if (kIsWeb) return userScaleFactor;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 안드로이드 기본 고DPI 환경을 고려하여 80% (0.8x) 배율 기본 적용
      return userScaleFactor * 0.8;
    }
    final size = MediaQuery.of(context).size;

    const refW = 1920.0;
    const refH = 1080.0;
    final fit = (size.width / refW) < (size.height / refH)
        ? size.width / refW
        : size.height / refH;

    final adaptive = fit.clamp(0.85, 1.1);
    return userScaleFactor * adaptive;
  }
}

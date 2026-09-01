import 'dart:convert';
import 'dart:io';
import 'storage_service.dart';

/// Boardest USB 형식 서비스
/// Plus(일반), Pro(교안 매칭) 포맷 관리 (Ultra 비활성화)
class UsbFormatService {
  static const String _configFileName = 'BoardestUSB.json';
  static const String _bstFolderName = 'bst';
  static const String _bstOldFolderName = 'bst-old';

  /// USB 루트에서 현재 포맷 타입을 읽어옴
  /// 반환값: 'Plus' | 'Pro'
  static Future<String> readCurrentType(String usbRoot) async {
    final normalized = _normalizePath(usbRoot);
    final jsonFile = File('$normalized$_configFileName');

    if (!jsonFile.existsSync()) return 'Plus';

    try {
      if (Platform.isWindows) {
        await _runAttrib('-h', jsonFile.path);
      }
      final content = jsonFile.readAsStringSync();
      final config = jsonDecode(content) as Map<String, dynamic>;
      final t = config['type'] as String? ?? '';
      if (Platform.isWindows) {
        await _runAttrib('+h', jsonFile.path);
      }
      if (t == 'Lite') return 'Pro';
    } catch (e) {
      // ignore
    }
    return 'Plus';
  }

  /// USB를 지정된 형식으로 설정
  /// [usbRoot]: USB 루트 경로 (ex. "E:\\")
  /// [type]: 'Plus' | 'Pro'
  static Future<void> applyFormat(String usbRoot, String type) async {
    final normalized = _normalizePath(usbRoot);
    final jsonPath = '$normalized$_configFileName';
    final jsonFile = File(jsonPath);

    // 강제로 Ultra 폴더는 비활성화/숨김해제 처리
    final bstDir = Directory('$normalized$_bstFolderName');
    final bstOldDir = Directory('$normalized$_bstOldFolderName');
    if (bstDir.existsSync()) {
      if (bstOldDir.existsSync()) {
        try {
          if (Platform.isWindows) {
            await _runAttrib('-h -s', bstOldDir.path, recursive: true);
          }
          bstOldDir.deleteSync(recursive: true);
        } catch (_) {}
      }
      try {
        if (Platform.isWindows) {
          await _runAttrib('-h -s', bstDir.path, recursive: true);
        }
        bstDir.renameSync(bstOldDir.path);
      } catch (_) {}
    }

    if (type == 'Plus') {
      // Plus: config 파일 제거
      if (jsonFile.existsSync()) {
        try {
          if (Platform.isWindows) {
            await _runAttrib('-h', jsonPath);
          }
          jsonFile.deleteSync();
        } catch (_) {}
      }
      return;
    }

    if (type == 'Pro') {
      // Pro: 설정 저장소에서 학년 정보를 가져와 JSON 매핑 구성
      final storage = StorageService();
      final settings = await storage.getSettings();
      final grade = settings.selectedGrade;

      final liteSettings = <String, String>{};
      for (int c = 1; c <= 10; c++) {
        final folderName = '$grade학년 ${c}반';
        liteSettings[folderName] = folderName;
      }

      final config = {
        'type': 'Lite',
        'version': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'lite_settings': liteSettings,
        'mappings': [],
      };

      if (jsonFile.existsSync() && Platform.isWindows) {
        await _runAttrib('-h', jsonPath);
      }

      jsonFile.writeAsStringSync(jsonEncode(config));

      if (Platform.isWindows) {
        await _runAttrib('+h', jsonPath);
      }
    }
  }

  /// Windows attrib 명령 실행
  static Future<void> _runAttrib(String flags, String path, {bool recursive = false}) async {
    if (!Platform.isWindows) return;
    try {
      final args = ['attrib', flags, '"$path"'];
      if (recursive) args.addAll(['/s', '/d']);
      await Process.run('cmd', ['/c', ...args]);
    } catch (_) {}
  }

  static String _normalizePath(String path) {
    if (path.endsWith('\\') || path.endsWith('/')) return path;
    return '$path\\';
  }

  /// USB 내 /bst 폴더가 존재하는지 확인 (구버전 호환)
  static bool hasBstFolder(String usbRoot) {
    final normalized = _normalizePath(usbRoot);
    return Directory('$normalized$_bstFolderName').existsSync();
  }

  /// USB 내 /bst-old 폴더가 존재하는지 확인
  static bool hasBstOldFolder(String usbRoot) {
    final normalized = _normalizePath(usbRoot);
    return Directory('$normalized$_bstOldFolderName').existsSync();
  }
}

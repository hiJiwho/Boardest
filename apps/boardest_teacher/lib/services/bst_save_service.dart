import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'app_paths.dart';

/// %APPDATA%/BstSave 폴더 구조 (USB, PDF, PPT, Board) 관리
class BstSaveService {
  BstSaveService._();
  static final BstSaveService instance = BstSaveService._();

  static const subUsb = 'USB';
  static const subPdf = 'PDF';
  static const subPpt = 'PPT';
  static const subBoard = 'Board';

  String? _customSaveRootPath;

  void setCustomRootPath(String? customPath) {
    _customSaveRootPath = customPath;
  }

  String get rootPath => _customSaveRootPath != null && _customSaveRootPath!.isNotEmpty
      ? _customSaveRootPath!
      : AppPaths.bstSaveRootSync;

  String pathFor(String sub) => p.join(rootPath, sub);

  String sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');

  Future<Directory> directoryFor(String sub) async {
    final dir = Directory(pathFor(sub));
    if (!kIsWeb && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> ensureStructure() async {
    if (kIsWeb) return;
    for (final sub in [subUsb, subPdf, subPpt, subBoard]) {
      await directoryFor(sub);
    }
  }

  Future<Directory?> detectUsbDrive() async {
    if (kIsWeb) return null;
    final drives = ['E:\\', 'F:\\', 'G:\\', 'H:\\', 'I:\\', 'D:\\'];
    for (final d in drives) {
      if (Directory(d).existsSync()) return Directory(d);
    }
    return null;
  }
}

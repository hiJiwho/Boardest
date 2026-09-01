import 'dart:convert';
import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/tbp_metadata.dart';

/// TBP (TextBook Plus) 전용 스토리지 및 I/O 전담 서비스
///
/// .bstTBP 파일 형식: Store Level 0 (무압축) ZIP
/// ├── meta.bstsave       ← TBP 메타데이터 (JSON)
/// ├── info.json          ← webUrl 등 기본 설정 (호환성 유지)
/// ├── HOTspot/           ← 핫스팟 데이터 (dHash 기반)
/// │   └── {dHash}/
/// │       └── hotspot.bstsave
/// └── PEN/               ← USB/Local 저장 시 판서 데이터
///     └── {classCode}/
///         └── {dHash}.bstpen
class TbpStorageService {
  static final TbpStorageService instance = TbpStorageService._internal();
  TbpStorageService._internal();

  // 추출된 .bstTBP 패키지들의 캐시 (filePath → 임시 폴더 경로)
  final Map<String, String> _extractCache = {};

  // ─── 패키지 로드 (.bstTBP ZIP) ──────────────────────────────────────

  /// .bstTBP (ZIP) 또는 레거시 .TBP (JSON) 파일 로드
  Future<TbpMetadata?> loadTbpFile(String tbpFilePath) async {
    try {
      // 새 형식: .bstTBP (Store Level 0 ZIP)
      if (tbpFilePath.toLowerCase().endsWith('.bsttbp')) {
        return await _loadFromBstTbpZip(tbpFilePath);
      }
      // 레거시: .TBP (JSON 텍스트 파일)
      final file = File(tbpFilePath);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return TbpMetadata.fromJson(json);
    } catch (e) {
      debugPrint('[TbpStorageService] Error loading TBP file: $e');
      return null;
    }
  }

  Future<TbpMetadata?> _loadFromBstTbpZip(String bstTbpPath) async {
    try {
      // 캐시된 추출 경로 확인
      await _ensureExtracted(bstTbpPath);

      final extractedDir = _extractCache[bstTbpPath];
      if (extractedDir == null) return null;

      // meta.bstsave 읽기
      final metaFile = File(p.join(extractedDir, 'meta.bstsave'));
      if (metaFile.existsSync()) {
        final json = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        return TbpMetadata.fromJson(json);
      }

      // 레거시 호환: info.json에서 읽기
      final infoFile = File(p.join(extractedDir, 'info.json'));
      if (infoFile.existsSync()) {
        final json = jsonDecode(await infoFile.readAsString()) as Map<String, dynamic>;
        return TbpMetadata.fromJson(json);
      }

      return null;
    } catch (e) {
      debugPrint('[TbpStorageService] Error loading .bstTBP ZIP: $e');
      return null;
    }
  }

  /// ZIP 추출 (무압축이므로 매우 빠름). 결과를 _extractCache에 캐시.
  Future<void> _ensureExtracted(String bstTbpPath) async {
    if (_extractCache.containsKey(bstTbpPath)) return;

    final bytes = await File(bstTbpPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final tmpDir = await getTemporaryDirectory();
    final tbpId = p.basenameWithoutExtension(bstTbpPath).replaceAll(RegExp(r'[^\w]'), '_');
    final extractDir = Directory(p.join(tmpDir.path, 'bstTBP_$tbpId'));
    if (!extractDir.existsSync()) {
      extractDir.createSync(recursive: true);
    }

    for (final file in archive) {
      if (file.isFile) {
        final outFile = File(p.join(extractDir.path, file.name));
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
      }
    }

    _extractCache[bstTbpPath] = extractDir.path;
    cleanupOldExtractCache();
  }

  /// 오래된 임시 추출 폴더 정리 (%TEMP%/bstTBP_*)
  Future<void> cleanupOldExtractCache({Duration maxAge = const Duration(days: 1)}) async {
    try {
      final tmpDir = await getTemporaryDirectory();
      if (!tmpDir.existsSync()) return;
      final entities = tmpDir.listSync();
      final now = DateTime.now();
      for (final entity in entities) {
        if (entity is Directory && p.basename(entity.path).startsWith('bstTBP_')) {
          try {
            final stat = entity.statSync();
            if (now.difference(stat.modified) > maxAge) {
              entity.deleteSync(recursive: true);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[TbpStorageService] cleanupOldExtractCache error: $e');
    }
  }

  // ─── 폴더 경로 취득 ────────────────────────────────────────────────────

  /// TBP 폴더 루트 경로 취득 (.bstTBP ZIP 또는 레거시 폴더)
  String getTbpFolderPath(String tbpFilePath, String folderId) {
    // .bstTBP ZIP의 경우 추출된 임시 폴더 반환
    if (tbpFilePath.toLowerCase().endsWith('.bsttbp')) {
      return _extractCache[tbpFilePath] ?? p.join(p.dirname(tbpFilePath), 'TBP-$folderId');
    }
    // 레거시
    final parentDir = p.dirname(tbpFilePath);
    return p.join(parentDir, 'TBP-$folderId');
  }

  // ─── info.json / meta.bstsave ──────────────────────────────────────────

  Future<Map<String, dynamic>?> loadInfoJson(String tbpFolderPath) async {
    try {
      // 새 형식: meta.bstsave
      final metaFile = File(p.join(tbpFolderPath, 'meta.bstsave'));
      if (metaFile.existsSync()) {
        return jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      }
      // 레거시: info.json
      final infoFile = File(p.join(tbpFolderPath, 'info.json'));
      if (!await infoFile.exists()) return null;
      return jsonDecode(await infoFile.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ─── 핫스팟 (.bstsave 우선, 레거시 .json 폴백) ─────────────────────────

  static String sanitizeKey(String key) {
    if (key.length > 32 && RegExp(r'^[01]+$').hasMatch(key)) {
      final sb = StringBuffer();
      for (int i = 0; i < key.length; i += 4) {
        final end = (i + 4 < key.length) ? i + 4 : key.length;
        final chunk = key.substring(i, end).padRight(4, '0');
        final val = int.parse(chunk, radix: 2);
        sb.write(val.toRadixString(16));
      }
      return sb.toString();
    }
    return key;
  }

  Future<List<Map<String, dynamic>>> loadHotspots(String tbpFolderPath, String dHash) async {
    try {
      final key = sanitizeKey(dHash);
      // 새 형식: hotspot.bstsave
      final newFile = File(p.join(tbpFolderPath, 'HOTspot', key, 'hotspot.bstsave'));
      if (newFile.existsSync()) {
        final List list = jsonDecode(await newFile.readAsString());
        return list.cast<Map<String, dynamic>>();
      }
      // 레거시: raw dHash
      final legacyRawFile = File(p.join(tbpFolderPath, 'HOTspot', dHash, 'hotspot.bstsave'));
      if (legacyRawFile.existsSync()) {
        final List list = jsonDecode(await legacyRawFile.readAsString());
        return list.cast<Map<String, dynamic>>();
      }
      // 레거시: hotspot.json
      final legacyFile = File(p.join(tbpFolderPath, 'HOTspot', key, 'hotspot.json'));
      if (legacyFile.existsSync()) {
        final List list = jsonDecode(await legacyFile.readAsString());
        return list.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHotspots(String tbpFolderPath, String dHash, List<Map<String, dynamic>> hotspots) async {
    try {
      final key = sanitizeKey(dHash);
      final pageDir = Directory(p.join(tbpFolderPath, 'HOTspot', key));
      if (!await pageDir.exists()) await pageDir.create(recursive: true);
      final hotspotFile = File(p.join(pageDir.path, 'hotspot.bstsave'));
      await hotspotFile.writeAsString(jsonEncode(hotspots), flush: true);
    } catch (e) {
      debugPrint('[TbpStorageService] Save hotspots error: $e');
    }
  }

  // ─── 판서 스트로크 (.bstpen 우선, 레거시 .iwb 폴백) ────────────────────

  Future<String?> loadStrokeData({
    required String tbpFolderPath,
    required String subFolder,
    required String scopeKey,
    String? filename,
  }) async {
    try {
      final safeKey = sanitizeKey(scopeKey);
      final base = filename != null && filename.isNotEmpty ? '$safeKey$filename' : safeKey;
      final rawBase = filename != null && filename.isNotEmpty ? '$scopeKey$filename' : scopeKey;

      // 축소 형식: .bstpen
      final newFile = File(p.join(tbpFolderPath, subFolder, '$base.bstpen'));
      if (newFile.existsSync()) return await newFile.readAsString();

      // 원본 dHash 형식: .bstpen
      final rawNewFile = File(p.join(tbpFolderPath, subFolder, '$rawBase.bstpen'));
      if (rawNewFile.existsSync()) return await rawNewFile.readAsString();

      // 레거시: .iwb
      final legacyFile = File(p.join(tbpFolderPath, subFolder, '$base.iwb'));
      if (legacyFile.existsSync()) return await legacyFile.readAsString();

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStrokeData({
    required String tbpFolderPath,
    required String subFolder,
    required String scopeKey,
    String? filename,
    required String strokeContent,
  }) async {
    try {
      final targetDir = Directory(p.join(tbpFolderPath, subFolder));
      if (!await targetDir.exists()) await targetDir.create(recursive: true);

      final safeKey = sanitizeKey(scopeKey);
      final base = filename != null && filename.isNotEmpty ? '$safeKey$filename' : safeKey;
      final strokeFile = File(p.join(targetDir.path, '$base.bstpen'));
      await strokeFile.writeAsString(strokeContent, flush: true);
    } catch (e) {
      debugPrint('[TbpStorageService] Save stroke error: $e');
    }
  }

  // ─── .bstTBP 패키징 (새 파일 생성) ────────────────────────────────────

  /// TBP 폴더를 Store Level 0 무압축 .bstTBP ZIP으로 패키징
  Future<bool> packageBstTbp({
    required String sourceFolderPath,
    required String outputBstTbpPath,
  }) async {
    try {
      final archive = Archive();
      final sourceDir = Directory(sourceFolderPath);

      await for (final entity in sourceDir.list(recursive: true)) {
        if (entity is File) {
          final relative = p.relative(entity.path, from: sourceFolderPath).replaceAll('\\', '/');
          final bytes = await entity.readAsBytes();
          // compressionType = 0 → Store (무압축)
          archive.addFile(ArchiveFile.noCompress(relative, bytes.length, bytes));
        }
      }

      final encodedBytes = ZipEncoder().encode(archive);
      if (encodedBytes == null) return false;
      await File(outputBstTbpPath).writeAsBytes(encodedBytes);
      return true;
    } catch (e) {
      debugPrint('[TbpStorageService] Package error: $e');
      return false;
    }
  }

  // ─── 다운로드 캐시 확인 ──────────────────────────────────────────────

  Future<bool> checkExistingDownload(String tbpFolderPath, String dHash, String filename) async {
    try {
      final file = File(p.join(tbpFolderPath, 'Downloads', dHash, filename));
      return await file.exists();
    } catch (_) {
      return false;
    }
  }
}

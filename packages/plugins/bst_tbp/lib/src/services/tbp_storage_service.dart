import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bst_core/bst_core.dart';
import 'package:bst_pen/bst_pen.dart';
import 'tbp_dhash_engine.dart';

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

  /// 패키지 암호화 비밀번호 (사용자 지정: boardest1217)
  static const String packagePassword = 'boardest1217';

  /// 32자리 무작위 고유 ID 발급 (UUID v4 유사 32-hex)
  static String generate32DigitId() {
    final rand = Random.secure();
    return List.generate(32, (_) => rand.nextInt(16).toRadixString(16)).join();
  }

  /// 파일 내용이 포인터 껍데기 JSON인지 검사하고 대상 ID 반환
  static Map<String, dynamic>? parsePointerShell(String content) {
    try {
      final json = jsonDecode(content);
      if (json is Map<String, dynamic> && json['id'] != null && json['type'] != null) {
        final id = json['id'].toString().trim();
        if (id.length == 32) {
          return json;
        }
      }
    } catch (_) {}
    return null;
  }

  /// [교실ID]dhash.pen 표준 파일명 규약 생성 (예: 기본_dhash.pen, [1반]dhash.pen)
  static String getPenFileName(String? classId, String dHash) {
    final rawClass = (classId != null && classId.trim().isNotEmpty && classId != '전체')
        ? classId.trim()
        : '기본';
    final safeHash = sanitizeKey(dHash);
    if (rawClass == '기본') {
      return '기본_$safeHash.pen';
    } else if (rawClass.startsWith('[') && rawClass.endsWith(']')) {
      return '$rawClass$safeHash.pen';
    } else {
      return '[$rawClass]$safeHash.pen';
    }
  }

  static final TbpStorageService instance = TbpStorageService._internal();
  TbpStorageService._internal();

  // 추출된 .bstTBP 패키지들의 캐시 (filePath → 임시 폴더 경로)
  final Map<String, String> _extractCache = {};

  // ─── 패키지 로드 (.bstTBP ZIP) ──────────────────────────────────────

  /// 로컬 TBP 폴더, .bstTBP (ZIP), 또는 레거시 .TBP (JSON) 파일 로드
  Future<TbpMetadata?> loadTbpFile(String tbpFilePath) async {
    try {
      // 1. 폴더 형태 TBP 패키지 (.tbp 폴더 등)
      final dir = Directory(tbpFilePath);
      if (await dir.exists()) {
        _extractCache[tbpFilePath] = dir.path;
        for (final name in ['meta.bstsave', 'manifest.json', 'info.json']) {
          final f = File(p.join(dir.path, name));
          if (f.existsSync()) {
            final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
            return TbpMetadata.fromJson(json);
          }
        }
        return null;
      }

      // 2. .bstTBP (Store Level 0 ZIP)
      if (tbpFilePath.toLowerCase().endsWith('.bsttbp')) {
        return await _loadFromBstTbpZip(tbpFilePath);
      }
      // 3. 레거시: .TBP (JSON 텍스트 파일)
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

      for (final name in ['meta.bstsave', 'manifest.json', 'info.json']) {
        final f = File(p.join(extractedDir, name));
        if (f.existsSync()) {
          final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          return TbpMetadata.fromJson(json);
        }
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

    Directory tmpDir;
    try {
      tmpDir = await getTemporaryDirectory();
    } catch (_) {
      tmpDir = Directory.systemTemp;
    }
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
    await cleanupOldExtractCache();
  }

  /// 오래된 임시 추출 폴더 정리 (%TEMP%/bstTBP_*)
  Future<void> cleanupOldExtractCache({Duration maxAge = const Duration(days: 1)}) async {
    try {
      Directory tmpDir;
      try {
        tmpDir = await getTemporaryDirectory();
      } catch (_) {
        tmpDir = Directory.systemTemp;
      }
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

  /// TBP 폴더 루트 경로 취득 (폴더형 TBP, .bstTBP ZIP 또는 레거시 폴더)
  String getTbpFolderPath(String tbpFilePath, String folderId) {
    if (_extractCache.containsKey(tbpFilePath)) {
      return _extractCache[tbpFilePath]!;
    }
    if (Directory(tbpFilePath).existsSync()) {
      return tbpFilePath;
    }
    final parentDir = p.dirname(tbpFilePath);
    return p.join(parentDir, 'TBP-$folderId');
  }

  // ─── info.json / meta.bstsave / manifest.json ──────────────────────────

  Future<Map<String, dynamic>?> loadInfoJson(String tbpFolderPath) async {
    try {
      for (final name in ['meta.bstsave', 'manifest.json', 'info.json']) {
        final f = File(p.join(tbpFolderPath, name));
        if (f.existsSync()) {
          return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        }
      }
      return null;
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

  /// BoardBook 알고리즘 기반 perceptual dHash 유사성 매칭 (Hamming distance <= threshold)
  Future<String> resolveSimilarHash(
    String tbpFolderPath,
    String subFolder,
    String targetDhash, {
    int threshold = 64,
  }) async {
    if (targetDhash.isEmpty) return targetDhash;
    try {
      final dir = Directory(p.join(tbpFolderPath, subFolder));
      if (!dir.existsSync()) return targetDhash;

      final entities = dir.listSync();
      String? bestMatchKey;
      int minDistance = threshold + 1;

      for (final entity in entities) {
        final rawName = p.basenameWithoutExtension(entity.path);
        if (rawName == targetDhash) return targetDhash;

        // 256비트 해시 간의 해밍 거리 비교
        if (rawName.length == 256 && targetDhash.length == 256) {
          final dist = TbpDhashEngine.hammingDistance(targetDhash, rawName);
          if (dist <= threshold && dist < minDistance) {
            minDistance = dist;
            bestMatchKey = rawName;
          }
        }
      }
      return bestMatchKey ?? targetDhash;
    } catch (_) {
      return targetDhash;
    }
  }

  Future<List<Map<String, dynamic>>> loadHotspots(String tbpFolderPath, String dHash) async {
    try {
      final resolvedDhash = await resolveSimilarHash(tbpFolderPath, 'HOTspot', dHash);
      final key = sanitizeKey(resolvedDhash);
      // 새 형식: hotspot.bstsave
      final newFile = File(p.join(tbpFolderPath, 'HOTspot', key, 'hotspot.bstsave'));
      if (newFile.existsSync()) {
        final List list = jsonDecode(await newFile.readAsString());
        return list.cast<Map<String, dynamic>>();
      }
      // 레거시: raw dHash
      final legacyRawFile = File(p.join(tbpFolderPath, 'HOTspot', resolvedDhash, 'hotspot.bstsave'));
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
      final resolvedDhash = await resolveSimilarHash(tbpFolderPath, 'HOTspot', dHash);
      final key = sanitizeKey(resolvedDhash);
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
    String? classId,
  }) async {
    try {
      final safeKey = sanitizeKey(scopeKey);
      final base = filename != null && filename.isNotEmpty ? '$safeKey$filename' : safeKey;
      final rawBase = filename != null && filename.isNotEmpty ? '$scopeKey$filename' : scopeKey;

      final penFileName = getPenFileName(classId, base);
      final safeClass = (classId != null && classId.trim().isNotEmpty && classId != '전체') ? classId.trim() : '기본';

      // 1. [교실ID]dhash.pen 최우선 로드 (신규 표준 규약)
      final stdPenFile = File(p.join(tbpFolderPath, 'PEN', penFileName));
      if (stdPenFile.existsSync()) return await stdPenFile.readAsString();

      final rootPenFile = File(p.join(tbpFolderPath, penFileName));
      if (rootPenFile.existsSync()) return await rootPenFile.readAsString();

      // 2. 다중 경로 호환성 탐색
      final altPenFile = File(p.join(tbpFolderPath, 'PEN', '${safeClass}_$base.pen'));
      if (altPenFile.existsSync()) return await altPenFile.readAsString();

      final altBstpenFile = File(p.join(tbpFolderPath, 'PEN', '${safeClass}_$base.bstpen'));
      if (altBstpenFile.existsSync()) return await altBstpenFile.readAsString();

      final basePenFile = File(p.join(tbpFolderPath, 'PEN', '$base.pen'));
      if (basePenFile.existsSync()) return await basePenFile.readAsString();

      final rootBasePenFile = File(p.join(tbpFolderPath, '$base.pen'));
      if (rootBasePenFile.existsSync()) return await rootBasePenFile.readAsString();

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
    String? classId,
    required String strokeContent,
  }) async {
    try {
      final targetDir = Directory(p.join(tbpFolderPath, subFolder));
      if (!await targetDir.exists()) await targetDir.create(recursive: true);

      final safeKey = sanitizeKey(scopeKey);
      final base = filename != null && filename.isNotEmpty ? '$safeKey$filename' : safeKey;

      // [교실ID]dhash.pen 표준 파일명 규약 적용 (예: 기본_dhash.pen, [1반]dhash.pen)
      final penFileName = getPenFileName(classId, base);
      final penDir = Directory(p.join(tbpFolderPath, 'PEN'));
      if (!await penDir.exists()) await penDir.create(recursive: true);
      final penFile = File(p.join(penDir.path, penFileName));
      await penFile.writeAsString(strokeContent, flush: true);

      final strokeFile = File(p.join(targetDir.path, '$base.bstpen'));
      await strokeFile.writeAsString(strokeContent, flush: true);
    } catch (e) {
      debugPrint('[TbpStorageService] Save stroke error: $e');
    }
  }

  Future<List<AnnotationStroke>> loadPenStrokes(String tbpFolderPath, String dHash, {String? classId}) async {
    final resolvedDhash = await resolveSimilarHash(tbpFolderPath, 'PEN', dHash);
    final raw = await loadStrokeData(
      tbpFolderPath: tbpFolderPath,
      subFolder: 'PEN',
      scopeKey: resolvedDhash,
      classId: classId,
    );
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((item) => AnnotationStroke.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePenStrokes(String tbpFolderPath, String dHash, List<AnnotationStroke> strokes, {String? classId}) async {
    final resolvedDhash = await resolveSimilarHash(tbpFolderPath, 'PEN', dHash);
    final jsonList = strokes.map((s) => s.toJson()).toList();
    await saveStrokeData(
      tbpFolderPath: tbpFolderPath,
      subFolder: 'PEN',
      scopeKey: resolvedDhash,
      classId: classId,
      strokeContent: jsonEncode(jsonList),
    );
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

import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/tbp_metadata.dart';
import '../../widgets/annotation_canvas.dart';
import '../bst_cloud_service.dart';

/// TBP (TextBook Plus) 전용 스토리지 및 I/O 전담 서비스
///
/// Drive TBP 폴더 형식 (온디맨드 필요 파일만 다운로드/업로드):
/// ├── manifest.json / meta.bstsave / info.json ← TBP 메타데이터 및 webUrl
/// ├── hotspot_{key}.bstsave                   ← 페이지별 핫스팟 데이터 (온디맨드)
/// └── pen_{key}.bstpen                        ← 페이지별 판서 데이터 (온디맨드)
class TbpStorageService {
  static final TbpStorageService instance = TbpStorageService._internal();
  TbpStorageService._internal();

  // 추출된 패키지 또는 클라우드 TBP 폴더 캐시 (tbpFilePath → 로컬 캐시 폴더 경로)
  final Map<String, String> _extractCache = {};
  // 로컬 캐시 폴더 경로 → Google Drive TBP 폴더 ID 매핑
  final Map<String, String> _driveFolderIds = {};
  // Web 인메모리 JSON 캐시 (folderPath::key → jsonString)
  final Map<String, String> _webJsonCache = {};

  /// 새로 생성한 TBP 프로젝트 메타데이터를 즉시 캐시에 등록하여 뷰어 진입 시 지연/오류 방지
  Future<String> registerCreatedTbpProject({
    required Map<String, dynamic> meta,
    String? driveFolderId,
    String? localDirPath,
  }) async {
    final encoded = const JsonEncoder.withIndent('  ').convert(meta);

    if (driveFolderId != null && driveFolderId.isNotEmpty) {
      final rawKey = 'drive://tbp/$driveFolderId';
      final vPath = 'drive_tbp_$driveFolderId';
      _webJsonCache['$vPath::info'] = encoded;
      _webJsonCache['$rawKey::info'] = encoded;
      if (kIsWeb) {
        _extractCache[rawKey] = vPath;
        _driveFolderIds[vPath] = driveFolderId;
      } else {
        try {
          final tmpDir = await getTemporaryDirectory();
          final safeId = driveFolderId.replaceAll(RegExp(r'[^\w-]'), '_');
          final cacheDir = Directory(p.join(tmpDir.path, 'bstTBP_cloud_$safeId'));
          if (!cacheDir.existsSync()) {
            cacheDir.createSync(recursive: true);
          }
          await File(p.join(cacheDir.path, 'manifest.json')).writeAsString(encoded, flush: true);
          await File(p.join(cacheDir.path, 'meta.bstsave')).writeAsString(encoded, flush: true);
          await File(p.join(cacheDir.path, 'info.json')).writeAsString(encoded, flush: true);
          _extractCache[rawKey] = cacheDir.path;
          _driveFolderIds[cacheDir.path] = driveFolderId;
          _webJsonCache['${cacheDir.path}::info'] = encoded;
        } catch (_) {}
      }
    }

    if (localDirPath != null && localDirPath.isNotEmpty) {
      if (kIsWeb || localDirPath.startsWith('web://')) {
        _extractCache[localDirPath] = localDirPath;
        _webJsonCache['$localDirPath::info'] = encoded;
        if (driveFolderId != null && driveFolderId.isNotEmpty) {
          _driveFolderIds[localDirPath] = driveFolderId;
        }
        return localDirPath;
      } else {
        try {
          final dir = Directory(localDirPath);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          for (final sub in ['HOTspot', 'PEN', 'PDF', 'PPT', 'HWP']) {
            final subDir = Directory(p.join(dir.path, sub));
            if (!subDir.existsSync()) subDir.createSync(recursive: true);
          }
          await File(p.join(dir.path, 'manifest.json')).writeAsString(encoded, flush: true);
          await File(p.join(dir.path, 'meta.bstsave')).writeAsString(encoded, flush: true);
          await File(p.join(dir.path, 'info.json')).writeAsString(encoded, flush: true);
          _extractCache[dir.path] = dir.path;
          _webJsonCache['${dir.path}::info'] = encoded;
          if (driveFolderId != null && driveFolderId.isNotEmpty) {
            _driveFolderIds[dir.path] = driveFolderId;
          }
        } catch (_) {}
      }
    }

    if (driveFolderId != null && driveFolderId.isNotEmpty) {
      return 'drive://tbp/$driveFolderId';
    }
    return localDirPath ?? 'web://tbp/${meta['folderId'] ?? 'default'}';
  }

  static bool _isDriveFolderRef(String pathStr) {
    if (pathStr.startsWith('drive://tbp/')) return true;
    if (pathStr.startsWith('web://tbp/')) return false;
    if (pathStr.startsWith('http://') || pathStr.startsWith('https://')) return false;
    if (pathStr.contains('/') || pathStr.contains('\\')) return false;
    final lower = pathStr.toLowerCase();
    if (lower.endsWith('.bsttbp') || lower.endsWith('.tbp') || lower.endsWith('.json')) return false;
    return pathStr.trim().isNotEmpty;
  }

  static String _extractDriveFolderId(String pathStr) {
    if (pathStr.startsWith('drive://tbp/')) {
      return pathStr.substring('drive://tbp/'.length).trim();
    }
    return pathStr.trim();
  }

  // ─── 패키지 로드 (Drive TBP 폴더 / 로컬 TBP 폴더 / 레거시 호환) ──────────────────

  Future<TbpMetadata?> loadTbpFile(String tbpFilePath, {Uint8List? directBytes}) async {
    try {
      // 0. Web 가상 경로 또는 인메모리 캐시 확인
      if (tbpFilePath.startsWith('web://tbp/')) {
        final cached = _webJsonCache['$tbpFilePath::info'];
        if (cached != null) {
          _extractCache[tbpFilePath] = tbpFilePath;
          return TbpMetadata.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        }
      }

      // 1. Google Drive TBP 폴더 (온디맨드: manifest.json / meta.bstsave / info.json 만 먼저 다운로드)
      if (_isDriveFolderRef(tbpFilePath)) {
        final driveFolderId = _extractDriveFolderId(tbpFilePath);
        return await _loadFromDriveTbpFolder(tbpFilePath, driveFolderId);
      }

      if (kIsWeb) {
        final cached = _webJsonCache['$tbpFilePath::info'];
        if (cached != null) {
          _extractCache[tbpFilePath] = tbpFilePath;
          return TbpMetadata.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        }
        final bytes = directBytes ?? BstCloudService.webMemoryFiles[tbpFilePath] ?? BstCloudService.webMemoryFiles[p.basename(tbpFilePath)];
        if (bytes != null && bytes.isNotEmpty) {
          try {
            final archive = ZipDecoder().decodeBytes(bytes);
            for (final f in archive) {
              if (f.name == 'meta.bstsave' || f.name == 'info.json' || f.name == 'manifest.json') {
                final json = jsonDecode(utf8.decode(f.content as List<int>)) as Map<String, dynamic>;
                _webJsonCache['$tbpFilePath::info'] = jsonEncode(json);
                return TbpMetadata.fromJson(json);
              }
            }
          } catch (_) {
            final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
            _webJsonCache['$tbpFilePath::info'] = jsonEncode(json);
            return TbpMetadata.fromJson(json);
          }
        }
        return null;
      }

      // 2. 로컬 디렉토리 형태의 TBP 폴더인 경우 (.tbp 폴더 등)
      final dir = Directory(tbpFilePath);
      if (await dir.exists()) {
        _extractCache[tbpFilePath] = dir.path;
        for (final name in ['meta.bstsave', 'manifest.json', 'info.json']) {
          final f = File(p.join(dir.path, name));
          if (f.existsSync()) {
            final raw = await f.readAsString();
            _webJsonCache['${dir.path}::info'] = raw;
            final json = jsonDecode(raw) as Map<String, dynamic>;
            if (json['folderId'] != null &&
                json['folderId'].toString().isNotEmpty &&
                !json['folderId'].toString().startsWith('local_')) {
              _driveFolderIds[dir.path] = json['folderId'].toString();
            }
            return TbpMetadata.fromJson(json);
          }
        }
        return null;
      }

      // 3. 레거시 .bstTBP (ZIP) 또는 .TBP (JSON) 파일 호환
      if (tbpFilePath.toLowerCase().endsWith('.bsttbp')) {
        return await _loadFromBstTbpZip(tbpFilePath);
      }
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

  Future<TbpMetadata?> _loadFromDriveTbpFolder(String rawKey, String driveFolderId) async {
    try {
      final vPath = 'drive_tbp_$driveFolderId';
      String? rawJson = _webJsonCache['$vPath::info'] ?? _webJsonCache['$rawKey::info'];

      if (rawJson == null || rawJson.trim().isEmpty) {
        for (final fileName in ['manifest.json', 'meta.bstsave', 'info.json']) {
          rawJson = await BstCloudService.instance.fetchTbpFolderFileText(driveFolderId, fileName);
          if (rawJson != null && rawJson.trim().isNotEmpty) break;
        }
      }
      if (rawJson == null || rawJson.trim().isEmpty) return null;

      final json = jsonDecode(rawJson) as Map<String, dynamic>;
      json['folderId'] = (json['folderId']?.toString().isNotEmpty == true)
          ? json['folderId']
          : driveFolderId;
      final encoded = jsonEncode(json);
      _webJsonCache['$vPath::info'] = encoded;
      _webJsonCache['$rawKey::info'] = encoded;

      if (kIsWeb) {
        _extractCache[rawKey] = vPath;
        _driveFolderIds[vPath] = driveFolderId;
        return TbpMetadata.fromJson(json);
      }

      final tmpDir = await getTemporaryDirectory();
      final safeId = driveFolderId.replaceAll(RegExp(r'[^\w-]'), '_');
      final cacheDir = Directory(p.join(tmpDir.path, 'bstTBP_cloud_$safeId'));
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      await File(p.join(cacheDir.path, 'meta.bstsave')).writeAsString(encoded, flush: true);
      await File(p.join(cacheDir.path, 'info.json')).writeAsString(encoded, flush: true);

      _extractCache[rawKey] = cacheDir.path;
      _driveFolderIds[cacheDir.path] = driveFolderId;
      _webJsonCache['${cacheDir.path}::info'] = encoded;
      unawaited(cleanupOldExtractCache());
      return TbpMetadata.fromJson(json);
    } catch (e) {
      debugPrint('[TbpStorageService] _loadFromDriveTbpFolder error: $e');
      return null;
    }
  }

  Future<TbpMetadata?> _loadFromBstTbpZip(String bstTbpPath) async {
    try {
      if (kIsWeb) {
        return await loadTbpFile(bstTbpPath);
      }
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
    unawaited(cleanupOldExtractCache());
  }

  /// 오래된 임시 추출 폴더 정리 (%TEMP%/bstTBP_*)
  Future<void> cleanupOldExtractCache({Duration maxAge = const Duration(days: 1)}) async {
    if (kIsWeb) return;
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

  String getTbpFolderPath(String tbpFilePath, String folderId) {
    if (_extractCache.containsKey(tbpFilePath)) {
      return _extractCache[tbpFilePath]!;
    }
    if (!kIsWeb && Directory(tbpFilePath).existsSync()) {
      return tbpFilePath;
    }
    final parentDir = p.dirname(tbpFilePath);
    return p.join(parentDir, 'TBP-$folderId');
  }

  // ─── info.json / meta.bstsave / manifest.json ──────────────────────────

  Future<Map<String, dynamic>?> loadInfoJson(String tbpFolderPath) async {
    try {
      if (kIsWeb) {
        final cached = _webJsonCache['$tbpFolderPath::info'];
        if (cached != null) return jsonDecode(cached) as Map<String, dynamic>;
        final driveId = _driveFolderIds[tbpFolderPath];
        if (driveId != null) {
          final remote = await BstCloudService.instance.fetchTbpFolderFileText(driveId, 'manifest.json') ??
              await BstCloudService.instance.fetchTbpFolderFileText(driveId, 'info.json');
          if (remote != null) return jsonDecode(remote) as Map<String, dynamic>;
        }
        return null;
      }

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

  // ─── 핫스팟 (.bstsave 우선, Drive 폴더 온디맨드 다운로드 지원) ─────────

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

      if (!kIsWeb) {
        final newFile = File(p.join(tbpFolderPath, 'HOTspot', key, 'hotspot.bstsave'));
        if (newFile.existsSync()) {
          final List list = jsonDecode(await newFile.readAsString());
          return list.cast<Map<String, dynamic>>();
        }
        final legacyRawFile = File(p.join(tbpFolderPath, 'HOTspot', dHash, 'hotspot.bstsave'));
        if (legacyRawFile.existsSync()) {
          final List list = jsonDecode(await legacyRawFile.readAsString());
          return list.cast<Map<String, dynamic>>();
        }
        final legacyFile = File(p.join(tbpFolderPath, 'HOTspot', key, 'hotspot.json'));
        if (legacyFile.existsSync()) {
          final List list = jsonDecode(await legacyFile.readAsString());
          return list.cast<Map<String, dynamic>>();
        }
      }

      // Google Drive TBP 폴더에서 현재 페이지(dHash) 핫스팟 파일만 온디맨드 다운로드
      final driveFolderId = _driveFolderIds[tbpFolderPath];
      if (driveFolderId != null && driveFolderId.isNotEmpty) {
        final remoteStr = await BstCloudService.instance.fetchTbpFolderFileText(
          driveFolderId,
          'hotspot_$key.bstsave',
        );
        if (remoteStr != null && remoteStr.isNotEmpty) {
          if (!kIsWeb) {
            final pageDir = Directory(p.join(tbpFolderPath, 'HOTspot', key));
            if (!pageDir.existsSync()) pageDir.createSync(recursive: true);
            await File(p.join(pageDir.path, 'hotspot.bstsave')).writeAsString(remoteStr, flush: true);
          }
          final List list = jsonDecode(remoteStr);
          return list.cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHotspots(String tbpFolderPath, String dHash, List<Map<String, dynamic>> hotspots) async {
    try {
      final key = sanitizeKey(dHash);
      final encoded = jsonEncode(hotspots);
      if (!kIsWeb) {
        final pageDir = Directory(p.join(tbpFolderPath, 'HOTspot', key));
        if (!await pageDir.exists()) await pageDir.create(recursive: true);
        final hotspotFile = File(p.join(pageDir.path, 'hotspot.bstsave'));
        await hotspotFile.writeAsString(encoded, flush: true);
      }

      final driveFolderId = _driveFolderIds[tbpFolderPath];
      if (driveFolderId != null && driveFolderId.isNotEmpty) {
        unawaited(
          BstCloudService.instance.saveTbpFolderFileText(
            driveFolderId,
            'hotspot_$key.bstsave',
            encoded,
          ),
        );
      }
    } catch (e) {
      debugPrint('[TbpStorageService] Save hotspots error: $e');
    }
  }

  // ─── 판서 스트로크 (.bstpen 우선, Drive 폴더 온디맨드 다운로드/업로드 지원) ────

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

      if (!kIsWeb) {
        final newFile = File(p.join(tbpFolderPath, subFolder, '$base.bstpen'));
        if (newFile.existsSync()) return await newFile.readAsString();

        final rawNewFile = File(p.join(tbpFolderPath, subFolder, '$rawBase.bstpen'));
        if (rawNewFile.existsSync()) return await rawNewFile.readAsString();

        final legacyFile = File(p.join(tbpFolderPath, subFolder, '$base.iwb'));
        if (legacyFile.existsSync()) return await legacyFile.readAsString();
      }

      final driveFolderId = _driveFolderIds[tbpFolderPath];
      if (driveFolderId != null && driveFolderId.isNotEmpty) {
        final remoteStr = await BstCloudService.instance.fetchTbpFolderFileText(
          driveFolderId,
          'pen_$base.bstpen',
        );
        if (remoteStr != null && remoteStr.isNotEmpty) {
          if (!kIsWeb) {
            final targetDir = Directory(p.join(tbpFolderPath, subFolder));
            if (!targetDir.existsSync()) targetDir.createSync(recursive: true);
            await File(p.join(targetDir.path, '$base.bstpen')).writeAsString(remoteStr, flush: true);
          }
          return remoteStr;
        }
      }

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
      final safeKey = sanitizeKey(scopeKey);
      final base = filename != null && filename.isNotEmpty ? '$safeKey$filename' : safeKey;

      if (!kIsWeb) {
        final targetDir = Directory(p.join(tbpFolderPath, subFolder));
        if (!await targetDir.exists()) await targetDir.create(recursive: true);
        final strokeFile = File(p.join(targetDir.path, '$base.bstpen'));
        await strokeFile.writeAsString(strokeContent, flush: true);
      }

      final driveFolderId = _driveFolderIds[tbpFolderPath];
      if (driveFolderId != null && driveFolderId.isNotEmpty) {
        unawaited(
          BstCloudService.instance.saveTbpFolderFileText(
            driveFolderId,
            'pen_$base.bstpen',
            strokeContent,
          ),
        );
      }
    } catch (e) {
      debugPrint('[TbpStorageService] Save stroke error: $e');
    }
  }

  Future<List<AnnotationStroke>> loadPenStrokes(String tbpFolderPath, String dHash) async {
    final raw = await loadStrokeData(tbpFolderPath: tbpFolderPath, subFolder: 'PEN', scopeKey: dHash);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((item) => AnnotationStroke.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePenStrokes(String tbpFolderPath, String dHash, List<AnnotationStroke> strokes) async {
    final jsonList = strokes.map((s) => s.toJson()).toList();
    await saveStrokeData(
      tbpFolderPath: tbpFolderPath,
      subFolder: 'PEN',
      scopeKey: dHash,
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

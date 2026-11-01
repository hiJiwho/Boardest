import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/tbp_metadata.dart';
import '../../widgets/annotation_canvas.dart';
import 'package:bst_pen/bst_pen.dart' as pen;
import '../bst_cloud_service.dart';

/// TBP (TextBook Plus) 전용 스토리지 및 I/O 전담 서비스
///
/// Drive TBP 폴더 형식 (온디맨드 필요 파일만 다운로드/업로드):
/// ├── manifest.json / meta.bstsave / info.json ← TBP 메타데이터 및 webUrl
/// ├── hotspot_{key}.bstsave                   ← 페이지별 핫스팟 데이터 (온디맨드)
/// └── pen_{key}.bstpen                        ← 페이지별 판서 데이터 (온디맨드)
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

    String? resolvedCacheDirPath;
    if (driveFolderId != null && driveFolderId.isNotEmpty) {
      final rawKey = 'drive://tbp/$driveFolderId';
      final vPath = 'drive_tbp_$driveFolderId';
      _webJsonCache['$vPath::info'] = encoded;
      _webJsonCache['$rawKey::info'] = encoded;
      if (kIsWeb) {
        _extractCache[rawKey] = vPath;
        _driveFolderIds[vPath] = driveFolderId;
        resolvedCacheDirPath = vPath;
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
          resolvedCacheDirPath = cacheDir.path;
        } catch (_) {}
      }
    }

    if (localDirPath != null && localDirPath.isNotEmpty) {
      final lowerLocal = localDirPath.toLowerCase();
      final isShellFile = lowerLocal.endsWith('.bst') ||
          lowerLocal.endsWith('.tbp') ||
          lowerLocal.endsWith('.htmlp') ||
          lowerLocal.endsWith('.save') ||
          (!kIsWeb && File(localDirPath).existsSync());
      if (kIsWeb || localDirPath.startsWith('web://')) {
        _extractCache[localDirPath] = localDirPath;
        _webJsonCache['$localDirPath::info'] = encoded;
        if (driveFolderId != null && driveFolderId.isNotEmpty) {
          _driveFolderIds[localDirPath] = driveFolderId;
        }
        return localDirPath;
      } else if (isShellFile) {
        try {
          String targetCacheDir = resolvedCacheDirPath ?? '';
          if (targetCacheDir.isEmpty) {
            final tmpDir = await getTemporaryDirectory();
            final fallbackId = (meta['folderId'] ?? meta['id'] ?? p.basenameWithoutExtension(localDirPath))
                .toString()
                .replaceAll(RegExp(r'[^\w-]'), '_');
            final cacheDir = Directory(p.join(tmpDir.path, 'bstTBP_local_$fallbackId'));
            if (!cacheDir.existsSync()) {
              cacheDir.createSync(recursive: true);
            }
            await File(p.join(cacheDir.path, 'manifest.json')).writeAsString(encoded, flush: true);
            await File(p.join(cacheDir.path, 'meta.bstsave')).writeAsString(encoded, flush: true);
            await File(p.join(cacheDir.path, 'info.json')).writeAsString(encoded, flush: true);
            targetCacheDir = cacheDir.path;
          }
          _extractCache[localDirPath] = targetCacheDir;
          _webJsonCache['$localDirPath::info'] = encoded;
          _webJsonCache['$targetCacheDir::info'] = encoded;
          if (driveFolderId != null && driveFolderId.isNotEmpty) {
            _driveFolderIds[localDirPath] = driveFolderId;
            _driveFolderIds[targetCacheDir] = driveFolderId;
          }
        } catch (_) {}
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
      return resolvedCacheDirPath ?? 'drive://tbp/$driveFolderId';
    }
    if (!kIsWeb && localDirPath == null) {
      try {
        final tmpDir = await getTemporaryDirectory();
        final fallbackId = (meta['folderId'] ?? meta['id'] ?? 'default')
            .toString()
            .replaceAll(RegExp(r'[^\w-]'), '_');
        final cacheDir = Directory(p.join(tmpDir.path, 'bstTBP_url_$fallbackId'));
        if (!cacheDir.existsSync()) {
          cacheDir.createSync(recursive: true);
        }
        await File(p.join(cacheDir.path, 'manifest.json')).writeAsString(encoded, flush: true);
        await File(p.join(cacheDir.path, 'meta.bstsave')).writeAsString(encoded, flush: true);
        await File(p.join(cacheDir.path, 'info.json')).writeAsString(encoded, flush: true);
        _extractCache[cacheDir.path] = cacheDir.path;
        _webJsonCache['${cacheDir.path}::info'] = encoded;
        return cacheDir.path;
      } catch (_) {}
    }
    return localDirPath ?? 'web://tbp/${meta['folderId'] ?? 'default'}';
  }

  static bool _isDriveFolderRef(String pathStr) {
    if (pathStr.startsWith('drive://tbp/')) return true;
    if (pathStr.startsWith('web://tbp/')) return false;
    if (pathStr.startsWith('http://') || pathStr.startsWith('https://')) return false;
    if (pathStr.contains('/') || pathStr.contains('\\')) return false;
    final lower = pathStr.toLowerCase();
    if (lower.endsWith('.bsttbp') ||
        lower.endsWith('.tbp') ||
        lower.endsWith('.bst') ||
        lower.endsWith('.htmlp') ||
        lower.endsWith('.save') ||
        lower.endsWith('.json')) {
      return false;
    }
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
            final shell = TbpStorageService.parsePointerShell(raw);
            if (shell != null) {
              final targetId = shell['id'].toString();
              return await loadTbpFile('drive://tbp/' + targetId);
            }
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

      // 3. 레거시 .bstTBP (ZIP) 또는 .TBP / .tbp.bst (JSON) 파일 호환
      if (tbpFilePath.toLowerCase().endsWith('.bsttbp')) {
        return await _loadFromBstTbpZip(tbpFilePath);
      }
      final file = File(tbpFilePath);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final shell = TbpStorageService.parsePointerShell(content);
      if (shell != null) {
        final targetId = shell['id'].toString();
        final rawDriveKey = 'drive://tbp/$targetId';
        final resolved = await _loadFromDriveTbpFolder(rawDriveKey, targetId, fallbackShell: shell);
        if (resolved != null) {
          if (_extractCache.containsKey(rawDriveKey)) {
            _extractCache[tbpFilePath] = _extractCache[rawDriveKey]!;
          }
          if (_driveFolderIds.containsKey(rawDriveKey)) {
            _driveFolderIds[tbpFilePath] = _driveFolderIds[rawDriveKey]!;
          }
          return resolved;
        }
      }
      final json = jsonDecode(content) as Map<String, dynamic>;
      final tmpDir = await getTemporaryDirectory();
      final safeId = (json['folderId'] ?? json['id'] ?? p.basenameWithoutExtension(tbpFilePath))
          .toString()
          .replaceAll(RegExp(r'[^\w-]'), '_');
      final cacheDir = Directory(p.join(tmpDir.path, 'bstTBP_file_$safeId'));
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      await File(p.join(cacheDir.path, 'meta.bstsave')).writeAsString(content, flush: true);
      await File(p.join(cacheDir.path, 'info.json')).writeAsString(content, flush: true);
      _extractCache[tbpFilePath] = cacheDir.path;
      _webJsonCache['${cacheDir.path}::info'] = content;
      return TbpMetadata.fromJson(json);
    } catch (e) {
      debugPrint('[TbpStorageService] Error loading TBP file: $e');
      return null;
    }
  }

  Future<TbpMetadata?> _loadFromDriveTbpFolder(String rawKey, String driveFolderId, {Map<String, dynamic>? fallbackShell}) async {
    try {
      final token = BstCloudService.instance.activeToken ?? '';
      String actualFolderId = driveFolderId;
      if (fallbackShell != null &&
          fallbackShell['folderId'] != null &&
          fallbackShell['folderId'].toString().trim().isNotEmpty &&
          !fallbackShell['folderId'].toString().startsWith('local_')) {
        actualFolderId = fallbackShell['folderId'].toString().trim();
      }
      final vPath = 'drive_tbp_$driveFolderId';
      String? rawJson = _webJsonCache['$vPath::info'] ?? _webJsonCache['$rawKey::info'];

      // 1. 만약 actualFolderId가 32자리 고유 ID(Hex) 형태인 경우 실체 Google Drive 폴더 검색
      if (rawJson == null && RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(actualFolderId)) {
        if (token.isNotEmpty) {
          var realFolder = await BstCloudService.instance.findDriveFolderByName(actualFolderId, '', token);
          realFolder ??= await BstCloudService.instance.findDriveFolderByName(actualFolderId, 'appDataFolder', token);
          if (realFolder != null && realFolder.isNotEmpty) {
            actualFolderId = realFolder;
          }
        }
      }

      // 2. actualFolderId가 폴더인 경우 manifest.json / meta.bstsave / info.json 검색
      if (rawJson == null || rawJson.trim().isEmpty) {
        for (final fileName in ['manifest.json', 'meta.bstsave', 'info.json']) {
          rawJson = await BstCloudService.instance.fetchTbpFolderFileText(actualFolderId, fileName);
          if (rawJson != null && rawJson.trim().isNotEmpty) break;
        }
      }

      // 3. 폴더 내부에서 못 찾은 경우: driveFolderId가 단일 포인터 껍데기 파일 ID인 경우
      if ((rawJson == null || rawJson.trim().isEmpty) && token.isNotEmpty) {
        try {
          final fileText = await BstCloudService.instance.readDriveFileText(driveFolderId, token);
          if (fileText != null && fileText.trim().isNotEmpty) {
            final parsed = jsonDecode(fileText);
            if (parsed is Map<String, dynamic>) {
              final directFolderId = (parsed['folderId'] ?? '').toString().trim();
              final target32Id = (parsed['id'] ?? parsed['ID'] ?? '').toString().trim();
              String? realFolder = (directFolderId.isNotEmpty && !directFolderId.startsWith('local_'))
                  ? directFolderId
                  : null;
              if (realFolder == null && target32Id.isNotEmpty) {
                realFolder = await BstCloudService.instance.findDriveFolderByName(target32Id, '', token);
                realFolder ??= await BstCloudService.instance.findDriveFolderByName(target32Id, 'appDataFolder', token);
              }
              if (realFolder != null && realFolder.isNotEmpty) {
                actualFolderId = realFolder;
                for (final fileName in ['manifest.json', 'meta.bstsave', 'info.json']) {
                  rawJson = await BstCloudService.instance.fetchTbpFolderFileText(actualFolderId, fileName);
                  if (rawJson != null && rawJson.trim().isNotEmpty) break;
                }
              }

              if (rawJson == null || rawJson.trim().isEmpty) {
                final directUrl = (parsed['webUrl'] ?? parsed['targetUrl'] ?? parsed['url'] ?? parsed['embedUrl'] ?? '').toString().trim();
                if (directUrl.isNotEmpty || parsed.containsKey('title')) {
                  rawJson = jsonEncode({
                    'id': target32Id.isNotEmpty ? target32Id : driveFolderId,
                    'folderId': actualFolderId,
                    'title': parsed['title'] ?? parsed['name'] ?? 'TBP/HTMLP 교재',
                    'webUrl': directUrl,
                    'type': parsed['type'] ?? 'TBP',
                    'version': parsed['version'] ?? '5.3.1',
                  });
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[TbpStorageService] Shell pointer resolution error: $e');
        }
      }

      if ((rawJson == null || rawJson.trim().isEmpty) && fallbackShell != null) {
        final directUrl = (fallbackShell['webUrl'] ?? fallbackShell['targetUrl'] ?? fallbackShell['url'] ?? fallbackShell['embedUrl'] ?? '').toString().trim();
        rawJson = jsonEncode({
          'id': driveFolderId,
          'folderId': actualFolderId,
          'title': fallbackShell['title'] ?? fallbackShell['name'] ?? 'TBP/HTMLP 교재',
          'webUrl': directUrl,
          'type': fallbackShell['type'] ?? 'TBP',
          'version': fallbackShell['version'] ?? '5.3.1',
        });
      }

      if (rawJson == null || rawJson.trim().isEmpty) return null;

      final json = jsonDecode(rawJson) as Map<String, dynamic>;
      json['folderId'] = (json['folderId']?.toString().isNotEmpty == true)
          ? json['folderId']
          : actualFolderId;
      final encoded = jsonEncode(json);
      _webJsonCache['$vPath::info'] = encoded;
      _webJsonCache['$rawKey::info'] = encoded;
      _webJsonCache['drive_tbp_$actualFolderId::info'] = encoded;

      _driveFolderIds[vPath] = actualFolderId;
      _driveFolderIds[rawKey] = actualFolderId;
      _driveFolderIds['drive_tbp_$actualFolderId'] = actualFolderId;
      _driveFolderIds[driveFolderId] = actualFolderId;

      if (kIsWeb) {
        _extractCache[rawKey] = vPath;
        _extractCache['drive://tbp/$actualFolderId'] = vPath;
        _extractCache['drive://tbp/$driveFolderId'] = vPath;
        _driveFolderIds[vPath] = actualFolderId;
        return TbpMetadata.fromJson(json);
      }

      final tmpDir = await getTemporaryDirectory();
      final safeId = actualFolderId.replaceAll(RegExp(r'[^\w-]'), '_');
      final cacheDir = Directory(p.join(tmpDir.path, 'bstTBP_cloud_$safeId'));
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      await File(p.join(cacheDir.path, 'meta.bstsave')).writeAsString(encoded, flush: true);
      await File(p.join(cacheDir.path, 'info.json')).writeAsString(encoded, flush: true);

      _extractCache[rawKey] = cacheDir.path;
      _extractCache['drive://tbp/$actualFolderId'] = cacheDir.path;
      _extractCache['drive://tbp/$driveFolderId'] = cacheDir.path;
      _driveFolderIds[cacheDir.path] = actualFolderId;
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

  // ─── 핫스팟 (.bstsave 우선, Drive 폴더 온디맨드 다운로드/업로드 지원) ────

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

  /// 64자리 16진수(hex) 키를 256비트 이진 문자열로 복원 (해밍 거리 비교용)
  static String? toBinary256(String keyOrHash) {
    final trimmed = keyOrHash.trim();
    if (trimmed.length == 256 && RegExp(r'^[01]+$').hasMatch(trimmed)) {
      return trimmed;
    }
    if (trimmed.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(trimmed)) {
      final sb = StringBuffer();
      for (int i = 0; i < 64; i++) {
        final v = int.parse(trimmed[i], radix: 16);
        sb.write(v.toRadixString(2).padLeft(4, '0'));
      }
      return sb.toString();
    }
    return null;
  }

  /// 두 dHash(256비트 이진 또는 64자 hex) 간의 해밍 거리 계산
  static int hammingDistance(String a, String b) {
    if (a == b) return 0;
    final binA = toBinary256(a);
    final binB = toBinary256(b);
    if (binA == null || binB == null || binA.length != binB.length) return 256;
    int dist = 0;
    for (int i = 0; i < binA.length; i++) {
      if (binA[i] != binB[i]) dist++;
    }
    return dist;
  }

  /// TBP 폴더에 저장된 모든 페이지 dHash 목록 조회 (핫스팟/판서가 존재하는 페이지 추적용)
  Future<List<String>> getKnownPageHashes(String tbpFolderPath) async {
    final result = <String>{};
    try {
      final prefixHotspot = '$tbpFolderPath::hotspot::';
      final prefixPen = '$tbpFolderPath::PEN::';
      for (final k in _webJsonCache.keys) {
        if (k.startsWith(prefixHotspot)) {
          final h = k.substring(prefixHotspot.length);
          if (h.isNotEmpty && h != 'default') result.add(toBinary256(h) ?? h);
        } else if (k.startsWith(prefixPen)) {
          final h = k.substring(prefixPen.length);
          if (h.isNotEmpty && h != 'default') result.add(toBinary256(h) ?? h);
        }
      }

      if (!kIsWeb && tbpFolderPath.isNotEmpty) {
        final rootDir = Directory(tbpFolderPath);
        if (rootDir.existsSync()) {
          for (final entity in rootDir.listSync()) {
            final name = p.basename(entity.path);
            if (entity is File) {
              if (name.startsWith('hotspot_') && name.endsWith('.bstsave')) {
                final k = name.substring('hotspot_'.length, name.length - '.bstsave'.length);
                if (k.isNotEmpty && k != 'default') result.add(toBinary256(k) ?? k);
              } else if (name.startsWith('pen_') && name.endsWith('.bstpen')) {
                final k = name.substring('pen_'.length, name.length - '.bstpen'.length);
                if (k.isNotEmpty && k != 'default') result.add(toBinary256(k) ?? k);
              }
            }
          }
          final hotspotDir = Directory(p.join(tbpFolderPath, 'HOTspot'));
          if (hotspotDir.existsSync()) {
            for (final sub in hotspotDir.listSync()) {
              if (sub is Directory) {
                final k = p.basename(sub.path);
                if (k.isNotEmpty && k != 'default') result.add(toBinary256(k) ?? k);
              }
            }
          }
          final penDir = Directory(p.join(tbpFolderPath, 'PEN'));
          if (penDir.existsSync()) {
            for (final f in penDir.listSync()) {
              if (f is File && f.path.endsWith('.bstpen')) {
                final k = p.basenameWithoutExtension(f.path);
                if (k.isNotEmpty && k != 'default') result.add(toBinary256(k) ?? k);
              }
            }
          }
        }
      }
    } catch (_) {}
    return result.toList();
  }

  /// 해밍 거리 오차 범위(<= 18 bits) 내의 기존 저장된 페이지 키를 찾아 반환
  Future<String> _resolveCanonicalKey(String tbpFolderPath, String rawDhash) async {
    final exactKey = sanitizeKey(rawDhash);
    if (rawDhash == 'default' || toBinary256(rawDhash) == null) {
      return exactKey;
    }
    final knownList = await getKnownPageHashes(tbpFolderPath);
    String? bestKey;
    int bestDist = 19; // 18비트 이하일 때만 동일 페이지로 매칭 (TbpDhashEngine._knownMatchThreshold와 일치)
    for (final known in knownList) {
      final d = hammingDistance(rawDhash, known);
      if (d < bestDist) {
        bestDist = d;
        bestKey = sanitizeKey(known);
      }
    }
    return bestKey ?? exactKey;
  }

  Future<List<Map<String, dynamic>>> loadHotspots(String tbpFolderPath, String dHash) async {
    try {
      final key = await _resolveCanonicalKey(tbpFolderPath, dHash);

      final cached = _webJsonCache['$tbpFolderPath::hotspot::$key'];
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is List) return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (decoded is Map && decoded['hotspots'] is List) {
          return (decoded['hotspots'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }

      if (!kIsWeb) {
        final candidates = <File>[
          File(p.join(tbpFolderPath, 'BBplus', '$key.json')),
          File(p.join(tbpFolderPath, 'BBplus', '$dHash.json')),
          File(p.join(tbpFolderPath, 'HOTspot', key, 'hotspot.bstsave')),
          File(p.join(tbpFolderPath, 'hotspot_$key.bstsave')),
          File(p.join(tbpFolderPath, 'HOTspot', dHash, 'hotspot.bstsave')),
          File(p.join(tbpFolderPath, 'HOTspot', key, 'hotspot.json')),
          if (key == 'ui_home') ...[
            File(p.join(tbpFolderPath, 'BBplus', 'query__embed.json')),
            File(p.join(tbpFolderPath, 'HOTspot', 'query__embed', 'hotspot.bstsave')),
            File(p.join(tbpFolderPath, 'hotspot_query__embed.bstsave')),
            File(p.join(tbpFolderPath, 'BBplus', 'default.json')),
            File(p.join(tbpFolderPath, 'HOTspot', 'default', 'hotspot.bstsave')),
            File(p.join(tbpFolderPath, 'hotspot_default.bstsave')),
          ],
        ];
        for (final f in candidates) {
          if (f.existsSync()) {
            final raw = await f.readAsString();
            final decoded = jsonDecode(raw);
            if (decoded is List) return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            if (decoded is Map && decoded['hotspots'] is List) {
              return (decoded['hotspots'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            }
          }
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
          _webJsonCache['$tbpFolderPath::hotspot::$key'] = remoteStr;
          if (!kIsWeb) {
            final pageDir = Directory(p.join(tbpFolderPath, 'HOTspot', key));
            if (!pageDir.existsSync()) pageDir.createSync(recursive: true);
            await File(p.join(pageDir.path, 'hotspot.bstsave')).writeAsString(remoteStr, flush: true);
          }
          final decoded = jsonDecode(remoteStr);
          if (decoded is List) return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          if (decoded is Map && decoded['hotspots'] is List) {
            return (decoded['hotspots'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
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
      _webJsonCache['$tbpFolderPath::hotspot::$key'] = encoded;
      if (!kIsWeb) {
        // BoardBook 100% 동일 구조: BBplus/[hash].json 저장
        final bbplusDir = Directory(p.join(tbpFolderPath, 'BBplus'));
        if (!await bbplusDir.exists()) await bbplusDir.create(recursive: true);
        final bbplusFile = File(p.join(bbplusDir.path, '$key.json'));
        await bbplusFile.writeAsString(encoded, flush: true);

        final pageDir = Directory(p.join(tbpFolderPath, 'HOTspot', key));
        if (!await pageDir.exists()) await pageDir.create(recursive: true);
        final hotspotFile = File(p.join(pageDir.path, 'hotspot.bstsave'));
        await hotspotFile.writeAsString(encoded, flush: true);
        final rootHotspotFile = File(p.join(tbpFolderPath, 'hotspot_$key.bstsave'));
        await rootHotspotFile.writeAsString(encoded, flush: true);
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

  Future<List<String>> getAvailableClasses(String tbpFolderPath) async {
    final classes = <String>{};
    if (!kIsWeb && tbpFolderPath.isNotEmpty) {
      try {
        final bbpenDir = Directory(p.join(tbpFolderPath, 'BBPen'));
        if (bbpenDir.existsSync()) {
          for (final entity in bbpenDir.listSync()) {
            if (entity is Directory) {
              final name = p.basename(entity.path);
              if (name.isNotEmpty && !name.startsWith('.')) {
                classes.add(name);
              }
            }
          }
        }
        final penDir = Directory(p.join(tbpFolderPath, 'PEN'));
        if (penDir.existsSync()) {
          for (final entity in penDir.listSync()) {
            if (entity is File) {
              final baseName = p.basename(entity.path);
              final matchBracket = RegExp(r'^\[(.*?)\]').firstMatch(baseName);
              if (matchBracket != null && matchBracket.group(1) != null) {
                classes.add(matchBracket.group(1)!);
              } else if (baseName.startsWith('기본_')) {
                classes.add('기본');
              }
            }
          }
        }
      } catch (_) {}
    }
    for (final k in _webJsonCache.keys) {
      if (k.startsWith('$tbpFolderPath::BBPen::')) {
        final parts = k.substring('$tbpFolderPath::BBPen::'.length).split('::');
        if (parts.length >= 2 && parts[0].isNotEmpty) {
          classes.add(parts[0]);
        }
      } else if (k.startsWith('$tbpFolderPath::PEN::')) {
        final parts = k.substring('$tbpFolderPath::PEN::'.length).split('::');
        if (parts.length >= 2 && parts[0].isNotEmpty) {
          final c = parts[0].replaceAll('[', '').replaceAll(']', '');
          if (c.isNotEmpty) classes.add(c);
        }
      }
    }
    final list = classes.toList();
    list.sort();
    return list;
  }

  // ─── 판서 스트로크 (.bstpen 우선, Drive 폴더 온디맨드 다운로드/업로드 지원) ────

  Future<String?> loadStrokeData({
    required String tbpFolderPath,
    required String subFolder,
    required String scopeKey,
    String? filename,
    String? classId,
  }) async {
    try {
      final safeKey = await _resolveCanonicalKey(tbpFolderPath, scopeKey);
      final base = filename != null && filename.isNotEmpty ? '$safeKey$filename' : safeKey;
      final rawBase = filename != null && filename.isNotEmpty ? '$scopeKey$filename' : scopeKey;
      final classKey = (classId != null && classId.trim().isNotEmpty && classId != '전체') ? classId.trim() : null;

      final cachePrefix = classKey != null ? '$tbpFolderPath::BBPen::$classKey::$base' : '$tbpFolderPath::$subFolder::$base';
      final cached = _webJsonCache[cachePrefix] ??
          (classKey == null ? _webJsonCache['$tbpFolderPath::$subFolder::$base'] : null);
      if (cached != null) return cached;

      // hash__1 -> default 강제 리다이렉트 제거 (ui_home만 유지)
      final fallbackBases = (base == 'ui_home')
          ? <String>['default']
          : const <String>[];

      for (final fb in fallbackBases) {
        final fbPrefix = classKey != null ? '$tbpFolderPath::BBPen::$classKey::$fb' : '$tbpFolderPath::$subFolder::$fb';
        final fbCached = _webJsonCache[fbPrefix];
        if (fbCached != null) return fbCached;
      }

      if (!kIsWeb) {
        final penFileName = getPenFileName(classId, base);
        final safeClass = classKey ?? '기본';

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

        if (classKey != null) {
          final classBbpenSvg = File(p.join(tbpFolderPath, 'BBPen', classKey, '$base.svg'));
          if (classBbpenSvg.existsSync()) return await classBbpenSvg.readAsString();

          final classBbpenBstpen = File(p.join(tbpFolderPath, 'BBPen', classKey, '$base.bstpen'));
          if (classBbpenBstpen.existsSync()) return await classBbpenBstpen.readAsString();

          final classBbpenPen = File(p.join(tbpFolderPath, 'BBPen', classKey, '$base.pen'));
          if (classBbpenPen.existsSync()) return await classBbpenPen.readAsString();

          for (final fb in fallbackBases) {
            final fbSvg = File(p.join(tbpFolderPath, 'BBPen', classKey, '$fb.svg'));
            if (fbSvg.existsSync()) return await fbSvg.readAsString();
            final fbBstpen = File(p.join(tbpFolderPath, 'BBPen', classKey, '$fb.bstpen'));
            if (fbBstpen.existsSync()) return await fbBstpen.readAsString();
          }

          // 신규 반 진입 시 글로벌/기본 판서는 로드하지 않고 빈 판서로 반환 (핫스팟만 남기기)
          return null;
        }

        final bbpenSvg = File(p.join(tbpFolderPath, 'BBPen', '$base.svg'));
        if (bbpenSvg.existsSync()) return await bbpenSvg.readAsString();

        final rawBbpenSvg = File(p.join(tbpFolderPath, 'BBPen', '$rawBase.svg'));
        if (rawBbpenSvg.existsSync()) return await rawBbpenSvg.readAsString();

        final bbpenJson = File(p.join(tbpFolderPath, 'BBPen', '$base.json'));
        if (bbpenJson.existsSync()) return await bbpenJson.readAsString();

        final newFile = File(p.join(tbpFolderPath, subFolder, '$base.bstpen'));
        if (newFile.existsSync()) return await newFile.readAsString();

        final legacyRootPenFile = File(p.join(tbpFolderPath, 'pen_$base.bstpen'));
        if (legacyRootPenFile.existsSync()) return await legacyRootPenFile.readAsString();

        final rawNewFile = File(p.join(tbpFolderPath, subFolder, '$rawBase.bstpen'));
        if (rawNewFile.existsSync()) return await rawNewFile.readAsString();

        final legacyFile = File(p.join(tbpFolderPath, subFolder, '$base.iwb'));
        if (legacyFile.existsSync()) return await legacyFile.readAsString();

        for (final fb in fallbackBases) {
          final fbSvg = File(p.join(tbpFolderPath, 'BBPen', '$fb.svg'));
          if (fbSvg.existsSync()) return await fbSvg.readAsString();
          final fbPen = File(p.join(tbpFolderPath, subFolder, '$fb.bstpen'));
          if (fbPen.existsSync()) return await fbPen.readAsString();
          final fbRootPen = File(p.join(tbpFolderPath, 'pen_$fb.bstpen'));
          if (fbRootPen.existsSync()) return await fbRootPen.readAsString();
        }
      }

      final driveFolderId = _driveFolderIds[tbpFolderPath];
      if (driveFolderId != null && driveFolderId.isNotEmpty) {
        final cloudFilename = classKey != null ? 'pen_${classKey}_$base.bstpen' : 'pen_$base.bstpen';
        final remoteStr = await BstCloudService.instance.fetchTbpFolderFileText(
          driveFolderId,
          cloudFilename,
        );
        if (remoteStr != null && remoteStr.isNotEmpty) {
          final cachePrefix = classKey != null ? '$tbpFolderPath::BBPen::$classKey::$base' : '$tbpFolderPath::$subFolder::$base';
          _webJsonCache[cachePrefix] = remoteStr;
          if (!kIsWeb) {
            final targetDir = classKey != null
                ? Directory(p.join(tbpFolderPath, 'BBPen', classKey))
                : Directory(p.join(tbpFolderPath, subFolder));
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
    String? classId,
    required String strokeContent,
  }) async {
    try {
      final safeKey = sanitizeKey(scopeKey);
      final base = filename != null && filename.isNotEmpty ? '$safeKey$filename' : safeKey;
      final classKey = (classId != null && classId.trim().isNotEmpty && classId != '전체') ? classId.trim() : null;

      final cachePrefix = classKey != null ? '$tbpFolderPath::BBPen::$classKey::$base' : '$tbpFolderPath::$subFolder::$base';
      _webJsonCache[cachePrefix] = strokeContent;

      if (!kIsWeb) {
        // [교실ID]dhash.pen 표준 파일명 규약 적용 (예: 기본_dhash.pen, [1반]dhash.pen)
        final penFileName = getPenFileName(classId, base);
        final penDir = Directory(p.join(tbpFolderPath, 'PEN'));
        if (!await penDir.exists()) await penDir.create(recursive: true);
        final penFile = File(p.join(penDir.path, penFileName));
        await penFile.writeAsString(strokeContent, flush: true);

        // 하위 호환성 유지: 기존 BBPen 및 subFolder 구조도 함께 보존
        if (classKey != null) {
          final classDir = Directory(p.join(tbpFolderPath, 'BBPen', classKey));
          if (!await classDir.exists()) await classDir.create(recursive: true);
          final classSvg = File(p.join(classDir.path, '$base.svg'));
          await classSvg.writeAsString(strokeContent, flush: true);
          final classBstpen = File(p.join(classDir.path, '$base.bstpen'));
          await classBstpen.writeAsString(strokeContent, flush: true);
        } else {
          // BoardBook 100% 동일 구조: BBPen/[hash].svg 저장
          final bbpenDir = Directory(p.join(tbpFolderPath, 'BBPen'));
          if (!await bbpenDir.exists()) await bbpenDir.create(recursive: true);
          final bbpenFile = File(p.join(bbpenDir.path, '$base.svg'));
          await bbpenFile.writeAsString(strokeContent, flush: true);

          final targetDir = Directory(p.join(tbpFolderPath, subFolder));
          if (!await targetDir.exists()) await targetDir.create(recursive: true);
          final strokeFile = File(p.join(targetDir.path, '$base.bstpen'));
          await strokeFile.writeAsString(strokeContent, flush: true);
          final rootStrokeFile = File(p.join(tbpFolderPath, 'pen_$base.bstpen'));
          await rootStrokeFile.writeAsString(strokeContent, flush: true);
        }
      }

      final driveFolderId = _driveFolderIds[tbpFolderPath];
      if (driveFolderId != null && driveFolderId.isNotEmpty) {
        final cloudFilename = classKey != null ? 'pen_${classKey}_$base.bstpen' : 'pen_$base.bstpen';
        unawaited(
          BstCloudService.instance.saveTbpFolderFileText(
            driveFolderId,
            cloudFilename,
            strokeContent,
          ),
        );
      }
    } catch (e) {
      debugPrint('[TbpStorageService] Save stroke error: $e');
    }
  }

  Future<List<AnnotationStroke>> loadPenStrokes(String tbpFolderPath, String dHash, {String? classId}) async {
    final raw = await loadStrokeData(
      tbpFolderPath: tbpFolderPath,
      subFolder: 'PEN',
      scopeKey: dHash,
      classId: classId,
    );
    if (raw == null || raw.isEmpty) return [];
    try {
      final trimmed = raw.trim();
      // Boardest 특화 SVG 포맷 판서 복원
      if (trimmed.startsWith('<svg') || trimmed.startsWith('<?xml')) {
        final svgStrokes = pen.SvgStrokeConverter.svgToStrokes(trimmed);
        return svgStrokes
            .map((s) => AnnotationStroke(
                  points: s.points,
                  color: s.color,
                  strokeWidth: s.strokeWidth,
                  isEraser: s.isEraser,
                ))
            .toList();
      }
      // 레거시 JSON 포맷 판서 하위 호환
      final list = jsonDecode(raw) as List;
      return list.map((item) => AnnotationStroke.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePenStrokes(String tbpFolderPath, String dHash, List<AnnotationStroke> strokes, {String? classId}) async {
    // Boardest 자체 특화 SvgStrokeConverter를 통해 순수 SVG 벡터 포맷으로 판서 저장
    final penStrokes = strokes
        .map((s) => pen.AnnotationStroke(
              points: s.points,
              color: s.color,
              strokeWidth: s.strokeWidth,
              isEraser: s.isEraser,
            ))
        .toList();
    final svgContent = pen.SvgStrokeConverter.strokesToSvg(penStrokes, width: 1536, height: 864);
    await saveStrokeData(
      tbpFolderPath: tbpFolderPath,
      subFolder: 'PEN',
      scopeKey: dHash,
      classId: classId,
      strokeContent: svgContent,
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

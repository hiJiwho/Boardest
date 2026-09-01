import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/cloud_file.dart';

/// Boardest Cloud 강화 서비스 (Google Drive v3 & 실시간 동기화)
class CloudDriveService {
  static final CloudDriveService instance = CloudDriveService();

  String? _accessToken;
  String? _rootFolderId;
  CloudSyncStatus _status = CloudSyncStatus.idle;
  final List<CloudFile> _cachedFiles = [];
  final StreamController<CloudSyncStatus> _statusController = StreamController<CloudSyncStatus>.broadcast();
  final StreamController<List<CloudFile>> _filesController = StreamController<List<CloudFile>>.broadcast();

  CloudDriveService();

  CloudSyncStatus get status => _status;
  bool get isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty;
  String? get rootFolderId => _rootFolderId;
  List<CloudFile> get cachedFiles => List.unmodifiable(_cachedFiles);
  Stream<CloudSyncStatus> get statusStream => _statusController.stream;
  Stream<List<CloudFile>> get filesStream => _filesController.stream;

  /// 로컬 파일 캐시 수동 설정
  void setFiles(List<CloudFile> files) {
    _cachedFiles.clear();
    _cachedFiles.addAll(files);
    _filesController.add(List.unmodifiable(_cachedFiles));
  }

  /// 로컬 파일 캐시에 단일 파일 추가/갱신
  void addFile(CloudFile file) {
    _cachedFiles.removeWhere((f) => f.id == file.id);
    _cachedFiles.add(file);
    _filesController.add(List.unmodifiable(_cachedFiles));
  }

  /// 로컬 파일 캐시에서 단일 파일 제거
  void removeFile(String id) {
    _cachedFiles.removeWhere((f) => f.id == id);
    _filesController.add(List.unmodifiable(_cachedFiles));
  }

  /// 동기화 트리거
  Future<void> syncFiles() async {
    if (isLoggedIn) {
      await fetchFiles();
    } else {
      _setStatus(CloudSyncStatus.syncing);
      await Future.delayed(const Duration(milliseconds: 10));
      _setStatus(CloudSyncStatus.completed);
    }
  }

  /// 세션 토큰 및 기본 폴더 설정
  void setSession({required String accessToken, String? rootFolderId}) {
    _accessToken = accessToken;
    if (rootFolderId != null && rootFolderId.isNotEmpty) {
      _rootFolderId = rootFolderId;
    }
  }

  void _setStatus(CloudSyncStatus s) {
    _status = s;
    if (!_statusController.isClosed) {
      _statusController.add(s);
    }
  }

  /// Google Drive API v3 파일 목록 조회 (자동 재시도 포함)
  Future<List<CloudFile>> fetchFiles({String? folderId, int maxRetries = 2}) async {
    if (!isLoggedIn) {
      _setStatus(CloudSyncStatus.error);
      return [];
    }

    _setStatus(CloudSyncStatus.syncing);
    final targetFolder = folderId ?? _rootFolderId;
    String q = "trashed = false";
    if (targetFolder != null && targetFolder.isNotEmpty) {
      q += " and '$targetFolder' in parents";
    }

    final uri = Uri.parse(
      'https://www.googleapis.com/drive/v3/files'
      '?q=${Uri.encodeComponent(q)}'
      '&fields=${Uri.encodeComponent("files(id, name, mimeType, size, modifiedTime, thumbnailLink, webContentLink)")}'
      '&orderBy=modifiedTime desc'
      '&pageSize=100',
    );

    int attempt = 0;
    while (attempt <= maxRetries) {
      try {
        final response = await http.get(
          uri,
          headers: {'Authorization': 'Bearer $_accessToken'},
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final filesList = data['files'] as List<dynamic>? ?? [];
          final List<CloudFile> parsed = filesList.map((f) => CloudFile.fromJson(f as Map<String, dynamic>)).toList();

          _cachedFiles.clear();
          _cachedFiles.addAll(parsed);
          _filesController.add(List.unmodifiable(_cachedFiles));
          _setStatus(CloudSyncStatus.completed);
          return _cachedFiles;
        } else if (response.statusCode == 401) {
          debugPrint('[BstCloud] Access Token expired (401).');
          _setStatus(CloudSyncStatus.error);
          return [];
        }
      } catch (e) {
        debugPrint('[BstCloud] fetchFiles attempt ${attempt + 1} failed: $e');
      }
      attempt++;
      if (attempt <= maxRetries) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    _setStatus(CloudSyncStatus.error);
    return _cachedFiles;
  }

  /// Google Drive 파일 Multipart 업로드
  Future<CloudFile?> uploadFile({
    required String name,
    required Uint8List bytes,
    String? folderId,
    String? mimeType,
  }) async {
    if (!isLoggedIn) return null;
    _setStatus(CloudSyncStatus.syncing);

    final resolvedMime = mimeType ?? _guessMimeType(name);
    final targetFolder = folderId ?? _rootFolderId;

    try {
      final metadata = {
        'name': name,
        'mimeType': resolvedMime,
        if (targetFolder != null && targetFolder.isNotEmpty) 'parents': [targetFolder],
      };

      final boundary = '-------bst_cloud_boundary_${DateTime.now().millisecondsSinceEpoch}';
      final uri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,mimeType,size,modifiedTime');

      final request = http.Request('POST', uri)
        ..headers['Authorization'] = 'Bearer $_accessToken'
        ..headers['Content-Type'] = 'multipart/related; boundary=$boundary';

      final metaBytes = utf8.encode(
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(metadata)}\r\n'
        '--$boundary\r\n'
        'Content-Type: $resolvedMime\r\n\r\n',
      );
      final footerBytes = utf8.encode('\r\n--$boundary--\r\n');

      final bodyBytes = Uint8List(metaBytes.length + bytes.length + footerBytes.length);
      bodyBytes.setRange(0, metaBytes.length, metaBytes);
      bodyBytes.setRange(metaBytes.length, metaBytes.length + bytes.length, bytes);
      bodyBytes.setRange(metaBytes.length + bytes.length, bodyBytes.length, footerBytes);

      request.bodyBytes = bodyBytes;

      final streamedRes = await request.send().timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamedRes);

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newFile = CloudFile.fromJson(data);
        _cachedFiles.removeWhere((f) => f.id == newFile.id);
        _cachedFiles.insert(0, newFile);
        _filesController.add(List.unmodifiable(_cachedFiles));
        _setStatus(CloudSyncStatus.completed);
        debugPrint('[BstCloud] ✅ File uploaded successfully: ${newFile.name} (${newFile.id})');
        return newFile;
      } else {
        debugPrint('[BstCloud] ❌ Upload failed with status: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('[BstCloud] ❌ Upload exception: $e');
    }

    _setStatus(CloudSyncStatus.error);
    return null;
  }

  /// Google Drive 파일 다운로드
  Future<Uint8List?> downloadFile(String fileId) async {
    if (!isLoggedIn) return null;
    _setStatus(CloudSyncStatus.syncing);

    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    try {
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_accessToken'},
      ).timeout(const Duration(seconds: 60));

      if (res.statusCode == 200) {
        _setStatus(CloudSyncStatus.completed);
        return res.bodyBytes;
      }
    } catch (e) {
      debugPrint('[BstCloud] ❌ Download error ($fileId): $e');
    }

    _setStatus(CloudSyncStatus.error);
    return null;
  }

  /// Google Drive 폴더 생성 또는 기존 폴더 검색
  Future<String?> ensureFolder(String folderName, {String? parentFolderId}) async {
    if (!isLoggedIn) return null;
    final parent = parentFolderId ?? _rootFolderId;
    String q = "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and trashed = false";
    if (parent != null && parent.isNotEmpty) {
      q += " and '$parent' in parents";
    }

    try {
      final searchUri = Uri.parse('https://www.googleapis.com/drive/v3/files?q=${Uri.encodeComponent(q)}&fields=files(id,name)');
      final searchRes = await http.get(searchUri, headers: {'Authorization': 'Bearer $_accessToken'}).timeout(const Duration(seconds: 5));
      if (searchRes.statusCode == 200) {
        final data = jsonDecode(searchRes.body);
        final files = data['files'] as List<dynamic>? ?? [];
        if (files.isNotEmpty) {
          return files.first['id'] as String?;
        }
      }

      // 폴더가 없으면 생성
      final createUri = Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id');
      final body = {
        'name': folderName,
        'mimeType': 'application/vnd.google-apps.folder',
        if (parent != null && parent.isNotEmpty) 'parents': [parent],
      };
      final createRes = await http.post(
        createUri,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 6));

      if (createRes.statusCode == 200 || createRes.statusCode == 201) {
        final data = jsonDecode(createRes.body);
        return data['id'] as String?;
      }
    } catch (e) {
      debugPrint('[BstCloud] ensureFolder error: $e');
    }
    return null;
  }

  /// 파일 삭제
  Future<bool> deleteFile(String fileId) async {
    if (!isLoggedIn) return false;
    try {
      final res = await http.delete(
        Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 204 || res.statusCode == 200) {
        _cachedFiles.removeWhere((f) => f.id == fileId);
        _filesController.add(List.unmodifiable(_cachedFiles));
        return true;
      }
    } catch (_) {}
    return false;
  }

  String _guessMimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.tbp') || lower.endsWith('.bst')) return 'application/octet-stream';
    if (lower.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }

  void dispose() {
    _statusController.close();
    _filesController.close();
  }
}

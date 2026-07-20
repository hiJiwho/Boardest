import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'package:http_parser/http_parser.dart';

/// Google Drive API File Model
class CloudDriveFile {
  final String id;
  final String name;
  final String mimeType;
  final int size;
  final String? webViewLink;
  final String? webContentLink;

  CloudDriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    this.webViewLink,
    this.webContentLink,
  });

  factory CloudDriveFile.fromJson(Map<String, dynamic> json) {
    return CloudDriveFile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
      size: int.tryParse(json['size']?.toString() ?? '0') ?? 0,
      webViewLink: json['webViewLink']?.toString(),
      webContentLink: json['webContentLink']?.toString(),
    );
  }
}

/// Boardest Cloud Service — Direct Google OAuth2 & Drive API v3
class CloudDriveService {
  static final CloudDriveService instance = CloudDriveService._internal();
  CloudDriveService._internal();

  static const String _tokenKey = 'bst_google_access_token';
  static const String _userEmailKey = 'bst_google_user_email';
  static const String _userNameKey = 'bst_google_user_name';
  static const String _schoolNameKey = 'bst_google_school_name';

  String? _accessToken;
  String? _userEmail;
  String? _userName;
  String? _schoolName;
  String? _boardestFolderId;
  HttpServer? _localServer;

  bool get isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String? get schoolName => _schoolName;
  String? get accessToken => _accessToken;

  /// 초기화 — 저장된 Google Access Token 및 유저 프로필 로드
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_tokenKey);
      _userEmail = prefs.getString(_userEmailKey);
      _userName = prefs.getString(_userNameKey);
      _schoolName = prefs.getString(_schoolNameKey);
    } catch (_) {}
  }

  /// 로그인 세션 저장
  Future<void> setSession({
    required String accessToken,
    String? email,
    String? name,
    String? school,
  }) async {
    _accessToken = accessToken;
    _userEmail = email;
    _userName = name;
    _schoolName = school;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, accessToken);
    if (email != null) await prefs.setString(_userEmailKey, email);
    if (name != null) await prefs.setString(_userNameKey, name);
    if (school != null) await prefs.setString(_schoolNameKey, school);
  }

  /// 로그아웃
  Future<void> logout() async {
    _accessToken = null;
    _userEmail = null;
    _userName = null;
    _schoolName = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_schoolNameKey);
  }

  /// bst-cloud 웹 인증 포털 열기
  Future<void> openWebAuthPortal() async {
    const url = 'https://bst-cloud.web.app';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  bool _isAuthenticating = false;

  /// Chrome/시스템 브라우저를 열어 구글 로그인 후 토큰 자동 획득 (OAuth Loopback Server)
  Future<bool> loginWithBrowserOAuth() async {
    if (_isAuthenticating) {
      debugPrint('[CloudDriveService] OAuth loopback server already starting/listening...');
      return false;
    }
    _isAuthenticating = true;
    await stopOAuthLoopbackServer();

    try {
      // 127.0.0.1:8080에 임시 HTTP 콜백 서버 바인딩
      _localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080, shared: true);
      debugPrint('[CloudDriveService] OAuth loopback server listening on http://127.0.0.1:8080');

      // 웹 인증 URL (boardest.web.app / bst-cloud에 redirect_uri=http://127.0.0.1:8080/callback 전달)
      final authUrl = Uri.parse(
        'https://boardest.web.app?redirect_uri=http://127.0.0.1:8080/callback',
      );

      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      }

      final completer = Completer<bool>();

      // HTTP 요청 대기
      _localServer!.listen((HttpRequest request) async {
        // CORS 헤더 설정
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        String? token;
        String? email;
        String? name;
        String? school;

        if (request.method == 'POST') {
          try {
            final bodyStr = await utf8.decoder.bind(request).join();
            if (bodyStr.isNotEmpty) {
              final Map<String, dynamic> bodyJson = jsonDecode(bodyStr);
              token = bodyJson['token'] as String? ?? bodyJson['access_token'] as String?;
              email = bodyJson['email'] as String?;
              name = bodyJson['name'] as String?;
              school = bodyJson['school'] as String?;
            }
          } catch (_) {}
        }

        final query = request.uri.queryParameters;
        token ??= query['token'] ?? query['access_token'];
        email ??= query['email'];
        name ??= query['name'];
        school ??= query['school'];

        if (token != null && token.isNotEmpty) {
          await setSession(
            accessToken: token,
            email: email,
            name: name,
            school: school,
          );

          try {
            await windowManager.show();
            await windowManager.focus();
          } catch (_) {}

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write('''
            <!DOCTYPE html>
            <html lang="ko">
            <head>
              <meta charset="utf-8">
              <title>Boardest Google 로그인 완료</title>
              <style>
                body { background: #0f0e17; color: #fffffe; font-family: sans-serif; text-align: center; padding-top: 50px; }
                .card { background: #16161a; border-radius: 20px; padding: 40px; display: inline-block; box-shadow: 0 10px 30px rgba(0,0,0,0.5); }
                h2 { color: #2ec4b6; }
              </style>
            </head>
            <body>
              <div class="card">
                <h2>🎉 Boardest Google 로그인 성공!</h2>
                <p>Google Drive API 연동이 완료되었습니다. 이 브라우저 창을 닫고 교사용 앱으로 돌아가세요.</p>
              </div>
              <script>setTimeout(function() { window.close(); }, 1500);</script>
            </body>
            </html>
            ''');
          await request.response.close();
          await stopOAuthLoopbackServer();
          if (!completer.isCompleted) completer.complete(true);
        } else {
          // 토큰이 파라미터에 없는 경우 HTML 랜딩 페이지(해시 파라미터 자동 추출 및 POST 전송)
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write('''
            <!DOCTYPE html>
            <html lang="ko">
            <head>
              <meta charset="utf-8">
              <title>Boardest 로그인 처리 중...</title>
            </head>
            <body>
              <p>로그인 토큰을 교사용 앱으로 전송 중입니다...</p>
              <script>
                (function() {
                  var params = new URLSearchParams(window.location.search);
                  var hashParams = new URLSearchParams(window.location.hash.substring(1));
                  var token = params.get('token') || params.get('access_token') || hashParams.get('token') || hashParams.get('access_token');
                  var email = params.get('email') || hashParams.get('email');
                  var name = params.get('name') || hashParams.get('name');
                  var school = params.get('school') || hashParams.get('school');
                  if (token) {
                    fetch('/callback', {
                      method: 'POST',
                      headers: { 'Content-Type': 'application/json' },
                      body: JSON.stringify({ token: token, email: email, name: name, school: school })
                    }).then(function() {
                      document.body.innerHTML = '<h2>🎉 로그인 완료! 창이 자동으로 닫힙니다.</h2>';
                      setTimeout(function() { window.close(); }, 1500);
                    });
                  }
                })();
              </script>
            </body>
            </html>
            ''');
          await request.response.close();
        }
      });

      // 3분 동안 로그인 대기 타임아웃
      Timer(const Duration(minutes: 3), () {
        if (!completer.isCompleted) {
          stopOAuthLoopbackServer();
          completer.complete(false);
        }
      });

      final res = await completer.future;
      _isAuthenticating = false;
      return res;
    } catch (e) {
      debugPrint('[CloudDriveService] OAuth loopback error: $e');
      await stopOAuthLoopbackServer();
    } finally {
      _isAuthenticating = false;
    }
    return false;
  }

  Future<void> stopOAuthLoopbackServer() async {
    if (_localServer != null) {
      try {
        await _localServer!.close(force: true);
      } catch (_) {}
      _localServer = null;
    }
  }

  String? _boardestConnectFolderId;
  String? _bstPenFolderId;

  /// Google Drive에서 이름 기반 폴더 검색 (중복 생성 방지)
  Future<String?> findFolderByName(String folderName, {String? parentFolderId}) async {
    if (!isLoggedIn) return null;
    try {
      String q = "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      if (parentFolderId != null && parentFolderId.isNotEmpty) {
        q += " and '$parentFolderId' in parents";
      }

      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?'
        'q=${Uri.encodeComponent(q)}&'
        'fields=files(id,name)&'
        'pageSize=10',
      );

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final files = data['files'] as List? ?? [];
        if (files.isNotEmpty) {
          return files.first['id'].toString();
        }
      }
    } catch (e) {
      debugPrint('[CloudDriveService] findFolderByName error: $e');
    }
    return null;
  }

  /// Google Drive 'boardest-cloud-connect' 루트 최상위 폴더 ID 가져오기/생성
  Future<String?> getOrCreateConnectFolder() async {
    if (!isLoggedIn) return null;
    if (_boardestConnectFolderId != null && _boardestConnectFolderId!.isNotEmpty) {
      return _boardestConnectFolderId;
    }

    final existing = await findFolderByName('boardest-cloud-connect');
    if (existing != null) {
      _boardestConnectFolderId = existing;
      _boardestFolderId = existing;
      return existing;
    }

    final created = await createFolderInDrive('boardest-cloud-connect');
    if (created != null) {
      _boardestConnectFolderId = created;
      _boardestFolderId = created;
    }
    return created;
  }

  /// Google Drive REST API — boardest-cloud-connect 폴더 전용 파일 목록 가져오기
  Future<List<CloudDriveFile>> fetchDriveFiles({String? folderId}) async {
    if (!isLoggedIn) return [];

    try {
      final targetFolder = (folderId != null && folderId.isNotEmpty)
          ? folderId
          : await getOrCreateConnectFolder();

      String q = "trashed = false";
      if (targetFolder != null && targetFolder.isNotEmpty) {
        q += " and '$targetFolder' in parents";
      }

      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?'
        'q=${Uri.encodeComponent(q)}&'
        'fields=files(id,name,mimeType,size,webViewLink,webContentLink)&'
        'pageSize=100&orderBy=modifiedTime desc',
      );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final filesJson = data['files'] as List? ?? [];
        return filesJson
            .map((item) => CloudDriveFile.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('[CloudDriveService] Token expired or unauthorized: ${response.statusCode}');
        await logout();
        unawaited(loginWithBrowserOAuth());
      }
    } catch (e) {
      debugPrint('[CloudDriveService] fetchDriveFiles error: $e');
    }
    return [];
  }

  /// Google Drive REST API — classroom_mappings.json 검색 및 읽기
  Future<Map<String, String>> fetchClassroomMappings() async {
    if (!isLoggedIn) return {};

    try {
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?'
        "q=${Uri.encodeComponent("name = 'classroom_mappings.json' and trashed = false")}&"
        'fields=files(id,name)',
      );

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final files = data['files'] as List? ?? [];
        if (files.isNotEmpty) {
          final fileId = files.first['id'].toString();
          return await downloadClassroomMappingsFile(fileId);
        }
      }
    } catch (e) {
      debugPrint('[CloudDriveService] fetchClassroomMappings error: $e');
    }
    return {};
  }

  /// classroom_mappings.json 다운로드
  Future<Map<String, String>> downloadClassroomMappingsFile(String fileId) async {
    try {
      final url = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('mappings')) {
          final map = data['mappings'] as Map<String, dynamic>;
          return map.map((k, v) => MapEntry(k, v.toString()));
        } else {
          return data.map((k, v) => MapEntry(k, v.toString()));
        }
      }
    } catch (e) {
      debugPrint('[CloudDriveService] downloadClassroomMappingsFile error: $e');
    }
    return {};
  }

  /// Google Drive 파일 다운로드 (임시 폴더 저장)
  Future<File?> downloadDriveFileToTemp(CloudDriveFile driveFile) async {
    if (!isLoggedIn) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath = p.join(tempDir.path, 'bst_cloud_cache', driveFile.name);
      final file = File(targetPath);

      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }

      final url = Uri.parse('https://www.googleapis.com/drive/v3/files/${driveFile.id}?alt=media');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return file;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('[CloudDriveService] Token expired or unauthorized: ${response.statusCode}');
        await logout();
        unawaited(loginWithBrowserOAuth());
      }
    } catch (e) {
      debugPrint('[CloudDriveService] downloadDriveFileToTemp error: $e');
    }
    return null;
  }

  /// Google Drive REST API — 파일 업로드 (Multipart/Related)
  Future<bool> uploadFileToDrive(File localFile, {String? folderId}) async {
    if (!isLoggedIn) return false;
    try {
      final targetParent = (folderId != null && folderId.isNotEmpty) ? folderId : _boardestFolderId;
      final fileName = p.basename(localFile.path);
      final bytes = await localFile.readAsBytes();
      final boundary = '----BoardestBoundary${DateTime.now().millisecondsSinceEpoch}';

      final metadataJson = jsonEncode({
        'name': fileName,
        if (targetParent != null && targetParent.isNotEmpty) 'parents': [targetParent]
      });

      final bodyBuilder = BytesBuilder();
      bodyBuilder.add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadataJson\r\n'));
      bodyBuilder.add(utf8.encode('--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n'));
      bodyBuilder.add(bytes);
      bodyBuilder.add(utf8.encode('\r\n--$boundary--\r\n'));

      final bodyBytes = bodyBuilder.toBytes();

      final uri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
          'Content-Length': bodyBytes.length.toString(),
        },
        body: bodyBytes,
      );

      debugPrint('[CloudDriveService] upload file status: ${response.statusCode}, body: ${response.body}');
      if (response.statusCode == 401) {
        debugPrint('[CloudDriveService] Token expired or 401 Unauthorized. Triggering browser OAuth login...');
        await logout();
        unawaited(loginWithBrowserOAuth());
        return false;
      }
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[CloudDriveService] uploadFileToDrive error: $e');
    }
    return false;
  }

  /// Google Drive 'BST-pen' 판서 폴더 ID 가져오기/생성 (중복 생성 방지)
  Future<String?> getBstPenFolderId() async {
    if (!isLoggedIn) return null;
    if (_bstPenFolderId != null && _bstPenFolderId!.isNotEmpty) {
      return _bstPenFolderId;
    }

    final parentId = await getOrCreateConnectFolder();
    final existing = await findFolderByName('BST-pen', parentFolderId: parentId);
    if (existing != null) {
      _bstPenFolderId = existing;
      return existing;
    }

    final created = await createFolderInDrive('BST-pen', parentFolderId: parentId);
    if (created != null) {
      _bstPenFolderId = created;
    }
    return created;
  }

  /// Google Drive에 새 폴더 생성
  Future<String?> createFolderInDrive(String folderName, {String? parentFolderId}) async {
    if (!isLoggedIn) return null;
    try {
      final targetParent = parentFolderId ?? _boardestFolderId;
      final body = {
        'name': folderName,
        'mimeType': 'application/vnd.google-apps.folder',
        if (targetParent != null && targetParent.isNotEmpty) 'parents': [targetParent],
      };
      final res = await http.post(
        Uri.parse('https://www.googleapis.com/drive/v3/files'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(body),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return data['id'] as String?;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] createFolderInDrive error: $e');
    }
    return null;
  }

  /// 텍스트/JSON 내용을 직접 구글 드라이브 파일로 업로드
  Future<bool> uploadTextFileToDrive(String fileName, String content, {String? folderId}) async {
    if (!isLoggedIn) return false;
    try {
      final targetParent = folderId ?? _boardestFolderId;
      final boundary = '----BoardestBoundary${DateTime.now().millisecondsSinceEpoch}';

      final metadataJson = jsonEncode({
        'name': fileName,
        if (targetParent != null && targetParent.isNotEmpty) 'parents': [targetParent]
      });

      final bodyBuilder = BytesBuilder();
      bodyBuilder.add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadataJson\r\n'));
      bodyBuilder.add(utf8.encode('--$boundary\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n$content\r\n'));
      bodyBuilder.add(utf8.encode('\r\n--$boundary--\r\n'));

      final bodyBytes = bodyBuilder.toBytes();

      final uri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
          'Content-Length': bodyBytes.length.toString(),
        },
        body: bodyBytes,
      );

      debugPrint('[CloudDriveService] upload text status: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[CloudDriveService] uploadTextFileToDrive error: $e');
    }
    return false;
  }

  /// Google Drive에 로컬 폴더 전체(하위 파일 및 폴더) 재귀 업로드
  Future<int> uploadFolderToDrive(Directory localDir, {String? parentFolderId}) async {
    if (!isLoggedIn || !await localDir.exists()) return 0;
    int uploadedCount = 0;
    try {
      final folderName = p.basename(localDir.path);
      final driveFolderId = await createFolderInDrive(folderName, parentFolderId: parentFolderId);
      if (driveFolderId == null) return 0;

      final entities = localDir.listSync(recursive: false);
      for (final entity in entities) {
        if (entity is File) {
          final ok = await uploadFileToDrive(entity, folderId: driveFolderId);
          if (ok) uploadedCount++;
        } else if (entity is Directory) {
          final count = await uploadFolderToDrive(entity, parentFolderId: driveFolderId);
          uploadedCount += count;
        }
      }
    } catch (e) {
      debugPrint('[CloudDriveService] uploadFolderToDrive error: $e');
    }
    return uploadedCount;
  }

  /// Google Drive 폴더 양방향 동기화 (로컬 <-> Drive)
  Future<bool> syncFolderWithDrive(Directory localDir, {String? driveFolderId}) async {
    if (!isLoggedIn) return false;
    try {
      final folderId = driveFolderId ?? await createFolderInDrive(p.basename(localDir.path));
      if (folderId == null) return false;

      // 1. Upload local files that don't exist on remote
      final remoteFiles = await fetchDriveFiles(folderId: folderId);
      final remoteMap = {for (var f in remoteFiles) f.name: f};

      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }

      final localEntities = localDir.listSync(recursive: false);
      for (final entity in localEntities) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (!remoteMap.containsKey(name)) {
            await uploadFileToDrive(entity, folderId: folderId);
          }
        }
      }

      // 2. Download remote files that don't exist locally
      final localFilesMap = {
        for (var f in localEntities.whereType<File>()) p.basename(f.path): f
      };
      for (final rFile in remoteFiles) {
        if (rFile.mimeType != 'application/vnd.google-apps.folder' && !localFilesMap.containsKey(rFile.name)) {
          final downloaded = await downloadDriveFileToTemp(rFile);
          if (downloaded != null) {
            final dest = File(p.join(localDir.path, rFile.name));
            await downloaded.copy(dest.path);
          }
        }
      }
      return true;
    } catch (e) {
      debugPrint('[CloudDriveService] syncFolderWithDrive error: $e');
    }
    return false;
  }
}

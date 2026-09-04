import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import '../config/app_config.dart';
import 'deep_link_service.dart';
import 'canva_oauth_service.dart';
import 'login_helper_html.dart';
import 'totp_service.dart';
import '../models/app_settings.dart';
import '../models/school.dart';
import 'storage_service.dart';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http_parser/http_parser.dart';
import 'package:bst_pen/bst_pen.dart';
import 'folder_picker_helper.dart';

class _PendingLoginSession {
  bool boardestDone = false;
  String boardestToken = '';
  String email = '';
  String name = '';
  String school = '';

  Set<String> requestedScopes = {};

  bool cloudDone = false;
  String cloudAccessToken = '';
  String cloudRefreshToken = '';

  bool canvaDone = false;
  String canvaAccessToken = '';
  String canvaRefreshToken = '';
  String canvaCodeVerifier = '';
  String canvaRedirectUri = '';

  void reset() {
    boardestDone = false;
    boardestToken = '';
    email = '';
    name = '';
    school = '';
    requestedScopes.clear();
    cloudDone = false;
    cloudAccessToken = '';
    cloudRefreshToken = '';
    canvaDone = false;
    canvaAccessToken = '';
    canvaRefreshToken = '';
    canvaCodeVerifier = '';
    canvaRedirectUri = '';
  }
}

String _generatePkceVerifier() {
  final random = Random.secure();
  final values = List<int>.generate(32, (i) => random.nextInt(256));
  return base64Url.encode(values).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
}

String _generatePkceChallenge(String verifier) {
  final bytes = utf8.encode(verifier);
  final digest = sha256.convert(bytes);
  return base64Url.encode(digest.bytes).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
}

/// Google Drive API File Model
class CloudDriveFile {
  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';
  final String id;
  final String name;
  final String mimeType;
  final int size;
  final String? webViewLink;
  final String? webContentLink;
  final DateTime? modifiedTime;

  CloudDriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    this.webViewLink,
    this.webContentLink,
    this.modifiedTime,
  });

  factory CloudDriveFile.fromJson(Map<String, dynamic> json) {
    return CloudDriveFile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
      size: int.tryParse(json['size']?.toString() ?? '0') ?? 0,
      webViewLink: json['webViewLink']?.toString(),
      webContentLink: json['webContentLink']?.toString(),
      modifiedTime: json['modifiedTime'] != null
          ? DateTime.tryParse(json['modifiedTime'].toString())
          : null,
    );
  }
}

/// Boardest Cloud Service — Direct Google OAuth2 & Drive API v3
class CloudDriveService with ChangeNotifier {
  /// 판서 파일명 한국어 친절 포맷팅
  /// 예: "[2-8] 2026-09-04_194842.pen" -> "2학년 8반에서 26년 09월 04일에 시작한 판서"
  static String formatBoardDisplayName(String rawName) {
    if (rawName.isEmpty) return '판서';
    final baseName = p.basenameWithoutExtension(rawName);

    // 1. 학년 / 반 파싱
    String? gradeText;
    String? classText;

    // 패턴 1: [2-8], [208], [2학년 8반]
    final bracketMatch = RegExp(r'\[([0-9]+)[-_ ]?([0-9]*)\]').firstMatch(baseName);
    if (bracketMatch != null) {
      final p1 = bracketMatch.group(1) ?? '';
      final p2 = bracketMatch.group(2) ?? '';
      if (p2.isNotEmpty) {
        gradeText = '${p1}학년';
        classText = '${int.tryParse(p2) ?? p2}반';
      } else if (p1.length == 3) {
        gradeText = '${p1[0]}학년';
        classText = '${int.tryParse(p1.substring(1)) ?? p1.substring(1)}반';
      } else if (p1.length == 2) {
        gradeText = '${p1[0]}학년';
        classText = '${int.tryParse(p1.substring(1)) ?? p1.substring(1)}반';
      }
    }

    if (gradeText == null) {
      final prefixMatch = RegExp(r'^([1-6])[-_]([0-9]{1,2})').firstMatch(baseName);
      if (prefixMatch != null) {
        gradeText = '${prefixMatch.group(1)}학년';
        classText = '${int.tryParse(prefixMatch.group(2)!) ?? prefixMatch.group(2)}반';
      }
    }

    // 2. 날짜 파싱 (2026-09-04 or 20260904 or 260904)
    String? dateText;
    final dateMatch1 = RegExp(r'(20[2-3][0-9])[-_.](0[1-9]|1[0-2])[-_.]([0-3][0-9])').firstMatch(baseName);
    if (dateMatch1 != null) {
      final y = dateMatch1.group(1)!.substring(2);
      final m = dateMatch1.group(2)!;
      final d = dateMatch1.group(3)!;
      dateText = '${y}년 ${m}월 ${d}일';
    } else {
      final dateMatch2 = RegExp(r'(2[0-9])(0[1-9]|1[0-2])([0-3][0-9])').firstMatch(baseName);
      if (dateMatch2 != null) {
        final y = dateMatch2.group(1)!;
        final m = dateMatch2.group(2)!;
        final d = dateMatch2.group(3)!;
        dateText = '${y}년 ${m}월 ${d}일';
      }
    }

    if (gradeText != null && classText != null && dateText != null) {
      return '$gradeText $classText에서 $dateText에 시작한 판서';
    } else if (gradeText != null && classText != null) {
      return '$gradeText $classText 판서';
    } else if (dateText != null) {
      return '$dateText에 시작한 판서';
    }

    return baseName;
  }

  Timer? _bgSyncTimer;
  String? _bgSyncLocalPath;

  void setBackgroundSyncFolder(String? path) {
    _bgSyncLocalPath = path;
    if (path != null && path.isNotEmpty) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('bst_bg_sync_folder', path);
      });
      _startBackgroundSyncTimer();
    } else {
      _bgSyncTimer?.cancel();
      _bgSyncTimer = null;
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('bst_bg_sync_folder');
      });
    }
  }

  void _startBackgroundSyncTimer() {
    if (kIsWeb) return;
    _bgSyncTimer?.cancel();
    _bgSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!isLoggedIn) return;
      final path = _bgSyncLocalPath;
      if (path != null && Directory(path).existsSync()) {
        try {
          await syncLocalFolderToDrive(path);
        } catch (e) {
          debugPrint('[CloudDriveService] Background sync error: $e');
        }
      }
    });
  }

  static final CloudDriveService instance = CloudDriveService._internal();
  CloudDriveService._internal();

  static const String _tokenKey = 'bst_cld_access_token';
  static const String _refreshTokenKey = 'bst_cld_refresh_token';
  static const String _userEmailKey = 'bst_google_user_email';
  static const String _userNameKey = 'bst_google_user_name';
  static const String _schoolNameKey = 'bst_google_school_name';

  String? _accessToken;
  String? _refreshToken;
  String? _userEmail;
  String? _userName;
  String? _schoolName;
  String? _boardestFolderId;
  HttpServer? _localServer;
  bool _isAuthenticating = false;

  bool get isLoggedIn =>
      (_userName != null && _userName!.isNotEmpty) ||
      (_userEmail != null && _userEmail!.isNotEmpty) ||
      (_accessToken != null && _accessToken!.isNotEmpty);
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String? get schoolName => _schoolName;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get boardestFolderId => _boardestFolderId;

  Timer? _autoRefreshTimer;

  void _startAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 40), (_) async {
      debugPrint('[CloudDriveService] 🕒 40분 주기 백그라운드 자동 구글 토큰 갱신 실행');
      await refreshAccessToken();
    });
  }

  int _activePort = 1217;
  int get activePort => _activePort;
  VoidCallback? onSessionReady;

  /// 초기화 — 저장된 Google Access Token, Refresh Token 및 유저 프로필 로드 & 상시 루프백 서버 가동
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_tokenKey);
      _refreshToken = prefs.getString(_refreshTokenKey);
      _userEmail = prefs.getString(_userEmailKey);
      _userName = prefs.getString(_userNameKey);
      _schoolName = prefs.getString(_schoolNameKey);
      await _ensureTotpSecret();
      if (isLoggedIn) {
        _startAutoRefreshTimer();
    unawaited(_syncTeacherCloudTokens());
      }
      await startPersistentLoopbackServer();
    } catch (_) {}
  }

  final _pendingSession = _PendingLoginSession();

  Future<void> startPersistentLoopbackServer() async {
    if (kIsWeb) return;
    if (_localServer != null) {
      await stopOAuthLoopbackServer();
    }
    const defaultPort = 1217;
    try {
      _localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, defaultPort, shared: true);
    } catch (e) {
      debugPrint('[CloudDriveService] Port $defaultPort on loopbackIPv4 unavailable ($e). Binding to dynamic available port...');
      try {
        _localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: true);
      } catch (e2) {
        debugPrint('[CloudDriveService] Failed to bind loopback server: $e2');
        return;
      }
    }

    _activePort = _localServer!.port;
    debugPrint('[CloudDriveService] 🚀 Persistent Loopback Server started on http://127.0.0.1:$_activePort');

    _localServer!.listen((HttpRequest request) async {
      debugPrint('[CloudDriveService] 📥 Received loopback request: ${request.method} ${request.uri}');

      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      request.response.headers.add('Access-Control-Allow-Headers', '*');
      
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      final path = request.uri.path;
      final query = request.uri.queryParameters;

      try {
        if (path == '/oauth-callback') {
          final email = query['email'] ?? '';
          final token = query['token'] ?? '';
          String teacherName = query['teacherName'] ?? '';
          String teacherId = query['teacherId'] ?? '';
          String schoolId = query['schoolId'] ?? '74148';
          String schoolCode = query['schoolCode'] ?? '';
          // schoolCode 정밀 파싱 및 fallback
          int? parsedSchoolCode = int.tryParse(schoolCode);
          if (parsedSchoolCode == null) {
            final lookupKey = schoolCode.isNotEmpty ? schoolCode : schoolId;
            try {
              final fcRes = await http.get(
                Uri.parse('${AppConfig.firebaseFunctionsBase}/getComciganCode?schoolId=${Uri.encodeComponent(lookupKey.trim().toLowerCase())}'),
              ).timeout(const Duration(seconds: 4));
              if (fcRes.statusCode == 200) {
                final fcData = jsonDecode(fcRes.body) as Map<String, dynamic>;
                parsedSchoolCode = int.tryParse(fcData['code']?.toString() ?? '');
              }
            } catch (_) {}
            if (parsedSchoolCode == null) {
              const fallbackMap = {'ydm': 44134};
              parsedSchoolCode = fallbackMap[lookupKey.trim().toLowerCase()] ?? int.tryParse(lookupKey) ?? 44134;
            }
          }
          final int finalSchoolCode = parsedSchoolCode;

          String schoolName = query['schoolName'] ?? '학교';
          int grade = int.tryParse(query['grade'] ?? '1') ?? 1;
          int classNum = int.tryParse(query['classNum'] ?? '1') ?? 1;
          String cafeteria = query['cafeteriaNum'] ?? '1';

          // 실시간 Firestore 교사 프로필 조회
          if (email.isNotEmpty) {
            try {
              final docId = email.replaceAll('.', '_').replaceAll('@', '_').replaceAll('+', '_');
              final url = Uri.parse(
                'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/teacher_profiles/$docId?key=${AppConfig.firebaseApiKey}',
              );
              final res = await http.get(url).timeout(const Duration(seconds: 3));
              if (res.statusCode == 200) {
                final data = jsonDecode(res.body);
                final fields = data['fields'] as Map<String, dynamic>?;
                if (fields != null) {
                  final Map<String, dynamic> map = {};
                  fields.forEach((k, v) {
                    if (v is Map) {
                      map[k] = v['stringValue'] ?? v['integerValue'] ?? v['booleanValue'] ?? v['doubleValue'];
                    }
                  });
                  schoolName = map['schoolName']?.toString() ?? schoolName;
                  schoolId = map['schoolId']?.toString() ?? schoolId;
                  teacherName = map['teacherName']?.toString() ?? teacherName;
                  teacherId = map['teacherId']?.toString() ?? teacherId;
                  grade = int.tryParse(map['grade']?.toString() ?? '') ?? grade;
                  classNum = int.tryParse(map['classNum']?.toString() ?? '') ?? classNum;
                  cafeteria = map['cafeteriaNum']?.toString() ?? cafeteria;
                }
              }
            } catch (_) {}
          }

          final refreshToken = query['refreshToken'] ?? '';

          if (token.isNotEmpty || email.isNotEmpty) {
            _accessToken = token;
            if (refreshToken.isNotEmpty) _refreshToken = refreshToken;
            _userEmail = email;
            _userName = teacherName;
            _schoolName = schoolName;
            final prefs = await SharedPreferences.getInstance();
            if (token.isNotEmpty) await prefs.setString(_tokenKey, token);
            if (refreshToken.isNotEmpty) await prefs.setString(_refreshTokenKey, refreshToken);
            if (email.isNotEmpty) await prefs.setString(_userEmailKey, email);
            if (teacherName.isNotEmpty) await prefs.setString(_userNameKey, teacherName);
            if (schoolName.isNotEmpty) await prefs.setString(_schoolNameKey, schoolName);

            // 전자칠판 및 클라우드 연동을 위한 Firestore 동기화 즉시 실행
            await syncTeacherCloudTokenToFirestore();
          }

          // Save AppSettings
          final storage = StorageService();
          final school = School(
            id: finalSchoolCode,
            code: finalSchoolCode,
            name: schoolName,
            region: '서울',
          );
          final settings = AppSettings(
            selectedSchool: school,
            schoolId: schoolId,
            selectedGrade: grade,
            selectedClass: classNum,
            selectedTeacher: teacherName,
            selectedTeacherId: teacherId.isNotEmpty ? teacherId : teacherName,
            selectedTeacherName: teacherName,
            cafeteriaNum: cafeteria,
            isSetupComplete: true,
          );
          await storage.saveSettings(settings);

          onSessionReady?.call();
          _onLoginSuccess?.call();

          request.response.headers.contentType = ContentType.html;
          request.response.write('''
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"><title>인증 완료</title></head>
            <body style="background:#0f0e17; color:#00f5d4; font-family:sans-serif; text-align:center; padding:40px;">
              <h2>🎉 교사 인증 및 프로필 연동이 완료되었습니다!</h2>
              <p style="color:#94a1b2;">교사용 앱으로 세션이 전달되었습니다. 이 창을 닫으셔도 됩니다.</p>
              <script>setTimeout(() => window.close(), 1200);</script>
            </body>
            </html>
          ''');
          await request.response.close();
          return;
        } else if (path == '/login-helper') {
          request.response.headers.contentType = ContentType.html;
          
          if (query['boardest-login'] == 'true') _pendingSession.requestedScopes.add('boardest');
          if (query['boardest-cloud-login'] == 'true') _pendingSession.requestedScopes.add('cloud');
          if (query['boardest-canva-login'] == 'true') _pendingSession.requestedScopes.add('canva');
          
          if (query['cloud-done'] == 'true') _pendingSession.cloudDone = true;
          if (query['canva-done'] == 'true') _pendingSession.canvaDone = true;
          if (query['boardestDone'] == 'true') _pendingSession.boardestDone = true;

          final html = LoginHelperHtml.generate(
            showBoardest: _pendingSession.requestedScopes.contains('boardest'),
            showCloud: _pendingSession.requestedScopes.contains('cloud'),
            showCanva: _pendingSession.requestedScopes.contains('canva'),
            cloudDone: _pendingSession.cloudDone.toString(),
            canvaDone: _pendingSession.canvaDone.toString(),
            boardestDone: _pendingSession.boardestDone.toString(),
          );
          request.response.write(html);
          
        } else if (path == '/boardest-login-done' && request.method == 'POST') {
          final bodyStr = await utf8.decoder.bind(request).join();
          final data = jsonDecode(bodyStr);
          _pendingSession.boardestToken = data['token'] ?? '';
          if (data['email'] != null) _pendingSession.email = data['email'];
          if (data['name'] != null) _pendingSession.name = data['name'];
          if (data['school'] != null) _pendingSession.school = data['school'];
          _pendingSession.boardestDone = true;
          request.response.statusCode = HttpStatus.ok;
          
        } else if (path == '/cloud-login-done' && request.method == 'POST') {
          final bodyStr = await utf8.decoder.bind(request).join();
          final data = jsonDecode(bodyStr);
          final token = data['token'] ?? '';
          if (token.isNotEmpty) {
            _pendingSession.cloudAccessToken = token;
          }
          _pendingSession.cloudDone = true;
          request.response.statusCode = HttpStatus.ok;
          
        } else if (path == '/login-status') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'boardestDone': _pendingSession.boardestDone,
            'cloudDone': _pendingSession.cloudDone,
            'canvaDone': _pendingSession.canvaDone,
          }));
          
        } else if (path == '/start-boardest-oauth') {
          final authUrl = 'https://accounts.google.com/o/oauth2/v2/auth'
              '?client_id=${AppConfig.googleClientIdNoDrive}'
              '&redirect_uri=http://127.0.0.1:1217/boardest-oauth-callback'
              '&response_type=code'
              '&scope=openid%20https://www.googleapis.com/auth/userinfo.profile%20https://www.googleapis.com/auth/userinfo.email'
              '&access_type=offline'
              '&prompt=consent';
          request.response.statusCode = HttpStatus.found;
          request.response.headers.add('Location', authUrl);

        } else if (path == '/boardest-oauth-callback') {
          final code = query['code'] ?? '';
          if (code.isNotEmpty) {
            await exchangeAuthorizationCode(
              code,
              redirectUri: 'http://127.0.0.1:1217/boardest-oauth-callback',
              withDrive: false,
            );
            _pendingSession.boardestDone = true;
            _pendingSession.email = _userEmail ?? '';
            _pendingSession.name = _userName ?? '';
          }
          request.response.statusCode = HttpStatus.found;
          request.response.headers.add('Location', '/login-helper?boardestDone=true');

        } else if (path == '/start-cloud-oauth') {
          final authUrl = 'https://accounts.google.com/o/oauth2/v2/auth'
              '?client_id=${AppConfig.googleClientIdWithDrive}'
              '&redirect_uri=http://127.0.0.1:1217'
              '&response_type=code'
              '&scope=openid%20https://www.googleapis.com/auth/userinfo.profile%20https://www.googleapis.com/auth/userinfo.email%20https://www.googleapis.com/auth/drive.appdata'
              '&access_type=offline'
              '&prompt=consent';
          request.response.statusCode = HttpStatus.found;
          request.response.headers.add('Location', authUrl);
          
        } else if (path == '/cloud-oauth-callback' || (path == '/' && query.containsKey('code') && !query.containsKey('state'))) {
          final code = query['code'] ?? '';
          if (code.isNotEmpty) {
            final usedRedirectUri = (path == '/') ? 'http://127.0.0.1:1217' : 'http://127.0.0.1:1217/cloud-oauth-callback';
            await exchangeAuthorizationCode(
              code,
              redirectUri: usedRedirectUri,
              withDrive: true,
            );
            _pendingSession.cloudAccessToken = _accessToken ?? '';
            _pendingSession.cloudRefreshToken = _refreshToken ?? '';
            _pendingSession.cloudDone = true;
            if (_userEmail != null && _pendingSession.email.isEmpty) {
              _pendingSession.email = _userEmail!;
            }
            if (_userName != null && _pendingSession.name.isEmpty) {
              _pendingSession.name = _userName!;
            }
            await _ensureBoardestFolders();
            await syncTeacherCloudTokenToFirestore();
          }
          request.response.statusCode = HttpStatus.found;
          request.response.headers.add('Location', '/login-helper?cloud-done=true');
          
        } else if (path == '/start-canva-oauth') {
          final verifier = _generatePkceVerifier();
          final challenge = _generatePkceChallenge(verifier);
          _pendingSession.canvaCodeVerifier = verifier;

          final scopes = Uri.encodeComponent(
            'asset:read asset:write brandtemplate:content:read brandtemplate:content:write '
            'brandtemplate:meta:read comment:read comment:write design:content:read '
            'design:content:write design:meta:read design:meta:write design:permission:read '
            'design:permission:write folder:permission:read folder:permission:write '
            'folder:read folder:write profile:read'
          );
          const redirectUri = 'http://127.0.0.1:1217';
          _pendingSession.canvaRedirectUri = redirectUri;

          final authUrl = 'https://www.canva.com/api/oauth/authorize'
              '?code_challenge_method=s256'
              '&response_type=code'
              '&client_id=${AppConfig.canvaClientId}'
              '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
              '&scope=$scopes'
              '&code_challenge=$challenge';
          request.response.statusCode = HttpStatus.found;
          request.response.headers.add('Location', authUrl);
          
        } else if (path == '/canva-oauth-callback' || (path == '/' && query.containsKey('code'))) {
          final code = query['code'] ?? '';
          if (code.isNotEmpty) {
            try {
              final redirectUri = _pendingSession.canvaRedirectUri.isNotEmpty
                  ? _pendingSession.canvaRedirectUri
                  : 'http://127.0.0.1:1217';

              final tokenBody = <String, String>{
                'grant_type': 'authorization_code',
                'code': code,
                'redirect_uri': redirectUri,
                'client_id': AppConfig.canvaClientId,
                'client_secret': AppConfig.canvaClientSecret,
              };
              if (_pendingSession.canvaCodeVerifier.isNotEmpty) {
                tokenBody['code_verifier'] = _pendingSession.canvaCodeVerifier;
              }

              final basicAuth = base64Encode(utf8.encode('${AppConfig.canvaClientId}:${AppConfig.canvaClientSecret}'));
              final response = await http.post(
                Uri.parse('https://api.canva.com/rest/v1/oauth/token'),
                headers: {
                  'Content-Type': 'application/x-www-form-urlencoded',
                  'Authorization': 'Basic $basicAuth',
                },
                body: tokenBody,
              );
              debugPrint('[CloudDriveService] Canva PKCE token response (${response.statusCode}): ${response.body}');
              if (response.statusCode == 200) {
                final data = jsonDecode(response.body);
                _pendingSession.canvaAccessToken = data['access_token'] ?? '';
                _pendingSession.canvaRefreshToken = data['refresh_token'] ?? '';
                _pendingSession.canvaDone = true;
                request.response.statusCode = HttpStatus.found;
                request.response.headers.add('Location', '/login-helper?canva-done=true');
              } else {
                request.response.statusCode = HttpStatus.found;
                request.response.headers.add('Location', '/login-helper?canva-error=true&message=${Uri.encodeComponent(response.body)}');
              }
            } catch (e) {
              debugPrint('[CloudDriveService] Canva token exchange error: $e');
              request.response.statusCode = HttpStatus.found;
              request.response.headers.add('Location', '/login-helper?canva-error=true&message=${Uri.encodeComponent(e.toString())}');
            }
          } else {
            request.response.statusCode = HttpStatus.found;
            request.response.headers.add('Location', '/login-helper?canva-error=true&message=No+code+provided');
          }
          
        } else if (path == '/notify-app' || path == '/login-complete') {
          await setSession(
            accessToken: _pendingSession.cloudAccessToken.isNotEmpty ? _pendingSession.cloudAccessToken : (_accessToken ?? ''),
            boardestToken: _pendingSession.boardestToken,
            bstCldToken: _pendingSession.cloudAccessToken.isNotEmpty ? _pendingSession.cloudAccessToken : (_accessToken ?? ''),
            refreshToken: _pendingSession.cloudRefreshToken.isNotEmpty ? _pendingSession.cloudRefreshToken : (_refreshToken ?? ''),
            email: _pendingSession.email.isNotEmpty ? _pendingSession.email : (_userEmail ?? ''),
            name: _pendingSession.name.isNotEmpty ? _pendingSession.name : (_userName ?? ''),
            school: _pendingSession.school.isNotEmpty ? _pendingSession.school : (_schoolName ?? ''),
          );
          if (_pendingSession.requestedScopes.contains('canva') && _pendingSession.canvaAccessToken.isNotEmpty) {
            await CanvaOAuthService.instance.setTokens(
              _pendingSession.canvaAccessToken,
              refresh: _pendingSession.canvaRefreshToken,
            );
          }
          
          _pendingSession.reset();
          _isAuthenticating = false;
          _onLoginSuccess?.call();
          
          if (request.method == 'POST' || path == '/notify-app') {
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.add('Access-Control-Allow-Origin', '*');
            request.response.write('ok');
          } else {
            request.response.statusCode = HttpStatus.found;
            request.response.headers.add('Location', 'https://what-is-boardest.web.app');
          }
          
          if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
            await windowManager.show();
            await windowManager.focus();
          }
          
        } else if (path == '/logout') {
          // Google 토큰 revoke 및 로컬 세션 클리어
          final tokenToRevoke = _accessToken ?? _refreshToken;
          if (tokenToRevoke != null && tokenToRevoke.isNotEmpty) {
            try {
              await http.post(
                Uri.parse('https://oauth2.googleapis.com/revoke?token=${Uri.encodeComponent(tokenToRevoke)}'),
                headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              );
            } catch (_) {}
          }
          _accessToken = null;
          _refreshToken = null;
          _userEmail = null;
          _userName = null;
          _schoolName = null;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(_tokenKey);
            await prefs.remove(_refreshTokenKey);
            await prefs.remove(_userEmailKey);
            await prefs.remove(_userNameKey);
            await prefs.remove(_schoolNameKey);
          } catch (_) {}
          _onLoginSuccess = null;
          request.response.headers.contentType = ContentType.html;
          request.response.write('''
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"><title>로그아웃 완료</title></head>
            <body style="background:#0f0e17; color:#ef4565; font-family:sans-serif; text-align:center; padding:40px;">
              <h2>👋 로그아웃 되었습니다.</h2>
              <p style="color:#94a1b2;">Google 토큰이 폐기되고 세션이 초기화되었습니다.</p>
              <script>setTimeout(() => window.close(), 1500);</script>
            </body>
            </html>
          ''');
        } else if (path == '/favicon.ico') {
          request.response.statusCode = HttpStatus.noContent;
        } else {
          request.response.write('<html><body><h2>🟢 Boardest 127.0.0.1 Active (Port $_activePort)</h2></body></html>');
        }
      } catch (e) {
        debugPrint('[CloudDriveService] Request handling error: $e');
      } finally {
        await request.response.close();
      }
    });
  }

  VoidCallback? _onLoginSuccess;
  void registerLoginCallback(VoidCallback cb) => _onLoginSuccess = cb;

  /// Google 계정 재인증 및 토큰 최신화 (?re-login 호출)
  Future<void> reauthenticateGoogle() async {
    final target = kIsWeb ? 'web' : 'win';
    final url = 'https://boardest-teacher-oauth.web.app?re-login&$target';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// 완전 로그아웃 (로컬 데이터 & 세션 삭제)
  Future<void> logout() async {
    await clearSession();
    try {
      final storage = StorageService();
      await storage.clearAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
    _onLoginSuccess?.call();
  }

  /// 세션 완전 초기화 및 로그아웃
  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _userEmail = null;
    _userName = null;
    _schoolName = null;
    _boardestFolderId = null;
    _bstSaveFolderId = null;
    _bstPenFolderId = null;
    _bstCanvaFolderId = null;
    _bstTextbookProFolderId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_userEmailKey);
      await prefs.remove(_userNameKey);
      await prefs.remove(_schoolNameKey);
    } catch (_) {}
  }

  bool _isRefreshing = false;
  /// Google Access Token 토큰 자동 갱신 (OTP 기반 & Cloudflare Worker KV & Refresh Token)
  Future<bool> refreshAccessToken({bool force = false}) async {
    if (_isRefreshing) return false;
    _isRefreshing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      _userEmail ??= prefs.getString(_userEmailKey) ?? prefs.getString('bst_user_email') ?? prefs.getString('email');
      _refreshToken ??= prefs.getString(_refreshTokenKey);

      // 1. Local Refresh Token direct exchange
      if (_refreshToken != null && _refreshToken!.isNotEmpty) {
        var response = await http.post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'refresh_token',
            'refresh_token': _refreshToken!,
            'client_id': AppConfig.googleClientIdWithDrive,
            'client_secret': AppConfig.googleClientSecretWithDrive,
          },
        );
        if (response.statusCode != 200) {
          response = await http.post(
            Uri.parse('https://oauth2.googleapis.com/token'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'grant_type': 'refresh_token',
              'refresh_token': _refreshToken!,
              'client_id': AppConfig.googleClientIdNoDrive,
              'client_secret': AppConfig.googleClientSecretNoDrive,
            },
          );
        }
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final newAccess = data['access_token'] as String?;
          if (newAccess != null && newAccess.isNotEmpty) {
            _accessToken = newAccess;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_tokenKey, newAccess);
            debugPrint('[CloudDriveService] 🔑 Google access token refreshed via direct refreshToken!');
            await syncTeacherCloudTokenToFirestore();
            return true;
          }
        }
      }

      // 2. Cloudflare Worker token/refresh endpoint fallback
      if (_userEmail != null && _userEmail!.isNotEmpty) {
        try {
          final refreshRes = await http.post(
            Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/auth/token/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': _userEmail,
            }),
          ).timeout(const Duration(seconds: 5));
          if (refreshRes.statusCode == 200) {
            final data = jsonDecode(refreshRes.body) as Map<String, dynamic>;
            final newAccess = data['accessToken'] as String?;
            if (newAccess != null && newAccess.isNotEmpty) {
              _accessToken = newAccess;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_tokenKey, newAccess);
              debugPrint('[CloudDriveService] ☁️ Google access token refreshed via Cloudflare Worker KV!');
              await syncTeacherCloudTokenToFirestore();
              return true;
            }
          }
        } catch (_) {}

        // 3. OTP 기반 Cloudflare Worker를 통한 실시간 안전 토큰 갱신
        await _ensureTotpSecret();
        if (_totpSecret != null && _totpSecret!.isNotEmpty) {
          final otp = currentOtp;
          if (otp.isNotEmpty && otp != '------') {
            try {
              final verifyRes = await http.post(
                Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/auth/verify-otp'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'teacherId': _userEmail,
                  'otp': otp,
                }),
              ).timeout(const Duration(seconds: 5));
              if (verifyRes.statusCode == 200) {
                final data = jsonDecode(verifyRes.body) as Map<String, dynamic>;
                final newAccess = data['accessToken'] as String?;
                if (newAccess != null && newAccess.isNotEmpty) {
                  _accessToken = newAccess;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(_tokenKey, newAccess);
                  debugPrint('[CloudDriveService] 🔐 Google access token successfully obtained via OTP & Worker!');
                  await syncTeacherCloudTokenToFirestore();
                  return true;
                }
              }
            } catch (_) {}
          }
        }
      }

      debugPrint('[CloudDriveService] ⚠️ Could not refresh token automatically. Retaining session.');
    } catch (e) {
      debugPrint('[CloudDriveService] Token refresh error: $e');
    } finally {
      _isRefreshing = false;
    }
    return false;
  }

  /// Google Authorization Code -> Drive API Access & Refresh Token 직접 교환 (자급자족)
  Future<bool> exchangeAuthorizationCode(
    String code, {
    String redirectUri = 'http://127.0.0.1:8080',
    bool withDrive = true,
  }) async {
    if (code.isEmpty) return false;
    final clientId = withDrive ? AppConfig.googleClientIdWithDrive : AppConfig.googleClientIdNoDrive;
    final clientSecret = withDrive ? AppConfig.googleClientSecretWithDrive : AppConfig.googleClientSecretNoDrive;

    try {
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
          'client_id': clientId,
          'client_secret': clientSecret,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final access = data['access_token'] as String?;
        final refresh = data['refresh_token'] as String?;
        if (access != null && access.isNotEmpty) {
          _accessToken = access;
          if (refresh != null && refresh.isNotEmpty) {
            _refreshToken = refresh;
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_tokenKey, access);
          if (_refreshToken != null) await prefs.setString(_refreshTokenKey, _refreshToken!);
          _startAutoRefreshTimer();

          // Google UserInfo 직접 조회
          try {
            final profileRes = await http.get(
              Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
              headers: {'Authorization': 'Bearer $access'},
            );
            if (profileRes.statusCode == 200) {
              final profile = jsonDecode(profileRes.body);
              _userEmail = profile['email'] as String?;
              _userName = profile['name'] as String?;
              if (_userEmail != null) await prefs.setString(_userEmailKey, _userEmail!);
              if (_userName != null) await prefs.setString(_userNameKey, _userName!);
            }
          } catch (_) {}

          debugPrint('[CloudDriveService] 🟢 authorization_code로 OAuth 토큰 획득 성공!');
          return true;
        }
      } else {
        debugPrint('[CloudDriveService] exchangeAuthorizationCode error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[CloudDriveService] exchangeAuthorizationCode exception: $e');
    }
    return false;
  }

  String? _bstSaveFolderId;
  String? _bstPenFolderId;
  String? _bstCanvaFolderId;
  String? _bstTextbookProFolderId;
  String? _bstSyncFolderId;

  String? get bstSaveFolderId => _bstSaveFolderId ?? _boardestFolderId;
  String? get bstPenFolderId => _bstPenFolderId;
  String? get bstCanvaFolderId => _bstCanvaFolderId;
  String? get bstTextbookProFolderId => _bstTextbookProFolderId;
  String? get bstSyncFolderId => _bstSyncFolderId;

  /// Boardest 허용 루트 폴더 ID 집합 (ADF 5대 폴더 격리)
  Set<String> get allowedRootFolderIds => {
    if (_boardestFolderId != null && _boardestFolderId!.isNotEmpty) _boardestFolderId!,
    if (_bstSaveFolderId != null && _bstSaveFolderId!.isNotEmpty) _bstSaveFolderId!,
    if (_bstPenFolderId != null && _bstPenFolderId!.isNotEmpty) _bstPenFolderId!,
    if (_bstCanvaFolderId != null && _bstCanvaFolderId!.isNotEmpty) _bstCanvaFolderId!,
    if (_bstTextbookProFolderId != null && _bstTextbookProFolderId!.isNotEmpty) _bstTextbookProFolderId!,
    if (_bstSyncFolderId != null && _bstSyncFolderId!.isNotEmpty) _bstSyncFolderId!,
  };

  /// 프로젝트 용량 한도 (500MB) 및 핫스팟 경고 한도 (100MB)
  static const int maxProjectSizeBytes = 500 * 1024 * 1024; // 500MB
  static const int hotspotWarningSizeBytes = 100 * 1024 * 1024; // 100MB
  static bool isHotspotSizeExceedingWarning(int byteLength) => byteLength > hotspotWarningSizeBytes;
  static bool isProjectSizeExceeded(int totalBytes) => totalBytes > maxProjectSizeBytes;

  Future<void> _ensureBoardestFolders() async {
    if (_accessToken == null || _accessToken!.isEmpty) return;
    try {
      _boardestFolderId = await _getOrCreateFolder('bst-save', 'appDataFolder');
      _bstSaveFolderId = _boardestFolderId;
      _bstPenFolderId = await _getOrCreateFolder('bst-pen', 'appDataFolder');
      _bstCanvaFolderId = await _getOrCreateFolder('bst-canva', 'appDataFolder');
      _bstTextbookProFolderId = await _getOrCreateFolder('bst-textbookpro', 'appDataFolder');
      _bstSyncFolderId = await _getOrCreateFolder('bst-sync', 'appDataFolder');
    } catch (e) {
      debugPrint('[CloudDriveService] _ensureBoardestFolders error: $e');
    }
  }

  Future<String?> _getOrCreateFolder(String folderName, String parentId) async {
    try {
      final isAdf = parentId == 'appDataFolder';
      final parentQuery = isAdf ? "'appDataFolder' in parents" : "'$parentId' in parents";
      final spaceQuery = isAdf ? 'spaces=appDataFolder&' : '';
      final searchUrl = Uri.parse(
        "https://www.googleapis.com/drive/v3/files?${spaceQuery}q=name='$folderName' and mimeType='application/vnd.google-apps.folder' and $parentQuery and trashed=false&fields=files(id,name)",
      );
      final searchRes = await http.get(
        searchUrl,
        headers: {'Authorization': 'Bearer $_accessToken', 'Accept': 'application/json'},
      );
      if (searchRes.statusCode == 200) {
        final data = jsonDecode(searchRes.body);
        final files = data['files'] as List?;
        if (files != null && files.isNotEmpty) {
          return files.first['id'] as String?;
        }
      }

      final createUrl = Uri.parse('https://www.googleapis.com/drive/v3/files');
      final bodyMap = <String, dynamic>{
        'name': folderName,
        'mimeType': 'application/vnd.google-apps.folder',
        'parents': [parentId],
      };

      final createRes = await http.post(
        createUrl,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(bodyMap),
      );
      if (createRes.statusCode == 200 || createRes.statusCode == 201) {
        final createData = jsonDecode(createRes.body);
        return createData['id'] as String?;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] _getOrCreateFolder($folderName) error: $e');
    }
    return null;
  }

  static const String _totpSecretKey = 'bst_totp_secret_key';
  static const String _trustDeviceKey = 'bst_trust_device_enabled';
  static const String _autoLessonFlowKey = 'bst_auto_lesson_flow_enabled';
  static const String _shortIdKey = 'bst_teacher_short_id';
  static const String _deviceKeyIdKey = 'bst_device_key_id';

  String? _totpSecret;
  String? _shortId;
  String? _keyId;
  bool _trustDeviceEnabled = false;
  bool _autoLessonFlowEnabled = true;

  String? get totpSecret => _totpSecret;
  String get shortId => (_shortId != null && _shortId!.isNotEmpty) ? _shortId! : '12';
  String get cloudId => shortId.padLeft(2, '0').substring(0, 2);
  bool get trustDeviceEnabled => _trustDeviceEnabled;
  bool get autoLessonFlowEnabled => _autoLessonFlowEnabled;

  String get currentOtp => (_totpSecret != null && _totpSecret!.isNotEmpty)
      ? TotpService.generate4DigitOtp(_totpSecret!)
      : '0000';

  /// 6자리 동적 자릿수 셔플 (Steganography) 전자칠판 접속 코드
  String get currentStegano6DigitOtp {
    final otp4 = (_totpSecret != null && _totpSecret!.isNotEmpty)
        ? TotpService.generate4DigitOtp(_totpSecret!)
        : '0000';
    final cloudId2 = cloudId;
    return TotpService.encodeSteganography6(cloudId2, otp4);
  }

  /// 하위 호환 getter
  String get currentFull10DigitOtp => currentStegano6DigitOtp;
  int get remainingSeconds => TotpService.getRemainingSeconds(step: 60);

  /// Firestore teacher_cloud_tokens 컬렉션과 TOTP Secret 및 최신 인증 토큰 즉시 동기화
  Future<void> _syncTeacherCloudTokens() async {
    if (_userEmail == null || _userEmail!.isEmpty) return;
    try {
      final docId = _userEmail!.replaceAll('.', '_').replaceAll('@', '_').replaceAll('+', '_');
      const apiKey = 'AIzaSyBMoJZHMBN4eYJtiZR2iGePcmIB7bg8wGo';
      final firestoreUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/teacher_cloud_tokens/$docId?key=$apiKey';

      if (_totpSecret == null || _totpSecret!.isEmpty) {
        _totpSecret = TotpService.generateDeterministicSecret(_userEmail!);
      }

      final payload = {
        'fields': {
          'email': {'stringValue': _userEmail ?? ''},
          'name': {'stringValue': _userName ?? '선생님'},
          'teacherName': {'stringValue': _userName ?? '선생님'},
          'school': {'stringValue': _schoolName ?? ''},
          'schoolId': {'stringValue': ''},
          'accessToken': {'stringValue': _accessToken ?? ''},
          'refreshToken': {'stringValue': _refreshToken ?? ''},
          'totpSecret': {'stringValue': _totpSecret ?? ''},
          'shortId': {'stringValue': _shortId ?? '12'},
          'cloudId': {'stringValue': cloudId},
          'trustDeviceEnabled': {'booleanValue': _trustDeviceEnabled},
          'autoLessonFlowEnabled': {'booleanValue': _autoLessonFlowEnabled},
          'folderId': {'stringValue': _boardestFolderId ?? ''},
          'bstCloudFolderId': {'stringValue': _boardestConnectFolderId ?? ''},
          'bstPenFolderId': {'stringValue': _bstPenFolderId ?? ''},
          'lastConsumedWindow': {'integerValue': '0'},
          'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
          'expiresAt': {'timestampValue': DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String()},
        }
      };

      await http.patch(
        Uri.parse(firestoreUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 4));
      debugPrint('[CloudDriveService] ✅ teacher_cloud_tokens Firestore sync complete ($docId)');
    } catch (e) {
      debugPrint('[CloudDriveService] _syncTeacherCloudTokens error: $e');
    }
  }

  Future<void> _ensureTotpSecret() async {
    final prefs = await SharedPreferences.getInstance();
    _totpSecret = prefs.getString(_totpSecretKey) ?? prefs.getString('bst_totp_secret');
    _shortId = prefs.getString(_shortIdKey);
    _keyId = prefs.getString(_deviceKeyIdKey);
    _trustDeviceEnabled = prefs.getBool(_trustDeviceKey) ?? false;
    _autoLessonFlowEnabled = prefs.getBool(_autoLessonFlowKey) ?? true;

    if (_keyId == null || _keyId!.isEmpty) {
      _keyId = 'dev_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      await prefs.setString(_deviceKeyIdKey, _keyId!);
    }

    if (_totpSecret == null || _totpSecret!.isEmpty) {
      _totpSecret = TotpService.generateDeterministicSecret(_userEmail ?? '');
      await prefs.setString(_totpSecretKey, _totpSecret!);
      await prefs.setString('bst_totp_secret', _totpSecret!);
    }

    // Cloudflare Worker와 기기 및 4자리 ID 동기화
    if (_userEmail != null && _userEmail!.isNotEmpty) {
      try {
        final regRes = await http.post(
          Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/auth/device/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': _userEmail,
            'keyId': _keyId,
            'deviceLabel': kIsWeb ? '교사용 Web 앱' : '교사용 Windows 앱',
            'totpSecret': _totpSecret,
          }),
        ).timeout(const Duration(seconds: 3));

        if (regRes.statusCode == 200) {
          final data = jsonDecode(regRes.body);
          if (data['shortId'] != null) {
            _shortId = data['shortId'].toString();
            await prefs.setString(_shortIdKey, _shortId!);
          }
        }
      } catch (_) {}
    }
    unawaited(_syncTeacherCloudTokens());
    notifyListeners();
  }

  Future<void> setTrustDeviceEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    _trustDeviceEnabled = enabled;
    await prefs.setBool(_trustDeviceKey, enabled);
    // 보안 규칙: 기기 신뢰하기를 끄면 즉시 시크릿을 재발급하여 기존 전자칠판에 저장된 키를 무효화!
    if (!enabled) {
      await regenerateTotpSecret();
    } else {
      await syncTeacherCloudTokenToFirestore();
    }
  }

  Future<void> setAutoLessonFlowEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    _autoLessonFlowEnabled = enabled;
    await prefs.setBool(_autoLessonFlowKey, enabled);
    await syncTeacherCloudTokenToFirestore();
  }

  Future<String> regenerateTotpSecret() async {
    final prefs = await SharedPreferences.getInstance();
    _totpSecret = TotpService.generateSecret();
    await prefs.setString(_totpSecretKey, _totpSecret!);
    await syncTeacherCloudTokenToFirestore();
    return _totpSecret!;
  }

  Future<void> syncTeacherCloudTokenToFirestore() async {
    if (_accessToken == null || _userEmail == null || _userEmail!.isEmpty) return;
    await _ensureTotpSecret();
    try {
      final uid = _userEmail!.replaceAll('.', '_').replaceAll('@', '_');
      final firestoreUrl = '${AppConfig.firestoreBase}/teacher_cloud_tokens/$uid?key=${AppConfig.firebaseApiKey}';
      final payload = {
        'fields': {
          'email': {'stringValue': _userEmail!},
          'name': {'stringValue': _userName ?? ''},
          'school': {'stringValue': _schoolName ?? ''},
          'accessToken': {'stringValue': _accessToken!},
          'refreshToken': {'stringValue': _refreshToken ?? ''},
          'totpSecret': {'stringValue': _totpSecret ?? ''},
          'trustDeviceEnabled': {'booleanValue': _trustDeviceEnabled},
          'autoLessonFlowEnabled': {'booleanValue': _autoLessonFlowEnabled},
          'folderId': {'stringValue': _boardestFolderId ?? ''},
          'bstSaveFolderId': {'stringValue': _bstSaveFolderId ?? _boardestFolderId ?? ''},
          'bstCloudFolderId': {'stringValue': _bstSaveFolderId ?? _boardestFolderId ?? ''},
          'bstPenFolderId': {'stringValue': _bstPenFolderId ?? ''},
          'bstCanvaFolderId': {'stringValue': _bstCanvaFolderId ?? ''},
          'bstTextbookProFolderId': {'stringValue': _bstTextbookProFolderId ?? ''},
          'lastConsumedWindow': {'integerValue': '0'},
          'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
          'expiresAt': {'timestampValue': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String()},
        }
      };
      await http.patch(
        Uri.parse(firestoreUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      debugPrint('[CloudDriveService] ☁ Teacher cloud token, TOTP & trust settings synced to Firestore');
    } catch (e) {
      debugPrint('[CloudDriveService] Failed to sync token to Firestore: $e');
    }
  }

  /// 기기 목록, 최근 접속 로그, 폴더 맵핑 정보 조회
  Future<Map<String, dynamic>> fetchDeviceListAndLogs() async {
    if (_userEmail == null || _userEmail!.isEmpty) {
      return {'devices': [], 'accessLogs': [], 'folderMappings': {}, 'shortId': _shortId ?? '12'};
    }
    try {
      final url = 'https://boardest-cloud-token.jiwho.workers.dev/api/auth/device/list?email=$_userEmail';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['shortId'] != null) {
          _shortId = data['shortId'].toString();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_shortIdKey, _shortId!);
        }
        return data;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] fetchDeviceListAndLogs error: $e');
    }
    return {'devices': [], 'accessLogs': [], 'folderMappings': {}, 'shortId': _shortId ?? '12'};
  }

  /// 8자리 전자칠판 자동 OTP 페어링 코드 승인 및 기기 등록
  Future<bool> confirm8DigitPairingCode(String pairingCode, {String? roomCode}) async {
    if (_userEmail == null || _userEmail!.isEmpty) return false;
    try {
      final url = 'https://boardest-cloud-token.jiwho.workers.dev/api/auth/device/pair-confirm';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _userEmail,
          'pairingCode': pairingCode.replaceAll(RegExp(r'\s+'), ''),
          'roomCode': roomCode ?? '전자칠판',
        }),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['shortId'] != null) {
          _shortId = data['shortId'].toString();
        }
        return true;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] confirm8DigitPairingCode error: $e');
    }
    return false;
  }

  /// 원격 기기 등록 해제
  Future<bool> removeDevice(String keyId) async {
    if (_userEmail == null || _userEmail!.isEmpty) return false;
    try {
      final url = 'https://boardest-cloud-token.jiwho.workers.dev/api/auth/device/remove';
      final res = await http.delete(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _userEmail,
          'keyId': keyId,
        }),
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudDriveService] removeDevice error: $e');
    }
    return false;
  }

  /// 교과/반별 폴더 맵핑 저장
  Future<bool> saveFolderMappings(Map<String, String> mappings) async {
    if (_userEmail == null || _userEmail!.isEmpty) return false;
    try {
      final url = 'https://boardest-cloud-token.jiwho.workers.dev/api/auth/folders/save';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _userEmail,
          'folderMappings': mappings,
        }),
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudDriveService] saveFolderMappings error: $e');
    }
    return false;
  }

  static const String _boardestTokenKey = 'bst_boardest_access_token';
  static const String _bstCldTokenKey = 'bst_cld_access_token';

  String? _boardestToken;
  String? _bstCldToken;

  String? get boardestToken => _boardestToken;
  String? get bstCldToken => _bstCldToken;

  /// 로그인 세션 저장 (boardest, bst-cld 토큰 분리)
  Future<void> setSession({
    required String accessToken,
    String? boardestToken,
    String? bstCldToken,
    String? refreshToken,
    String? email,
    String? name,
    String? school,
  }) async {
    _userEmail = email;
    _userName = name;
    _schoolName = school;

    if (accessToken.isNotEmpty) {
      _accessToken = accessToken;
    }
    if (boardestToken != null && boardestToken.isNotEmpty) {
      _boardestToken = boardestToken;
    }
    if (bstCldToken != null && bstCldToken.isNotEmpty) {
      _bstCldToken = bstCldToken;
      _accessToken = bstCldToken; // Google Drive API Token
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
    }

    // Google Token으로 사용자 정보 직접 조회 (email/name 보충)
    if ((_userEmail == null || _userEmail!.isEmpty) && _accessToken != null && _accessToken!.isNotEmpty) {
      try {
        final userInfoRes = await http.get(
          Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
          headers: {'Authorization': 'Bearer $_accessToken'},
        ).timeout(const Duration(seconds: 4));
        if (userInfoRes.statusCode == 200) {
          final uData = jsonDecode(userInfoRes.body) as Map<String, dynamic>;
          _userEmail = uData['email'] as String? ?? _userEmail;
          _userName = uData['name'] as String? ?? _userName;
        }
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) await prefs.setString(_tokenKey, _accessToken!);
    if (_boardestToken != null) await prefs.setString(_boardestTokenKey, _boardestToken!);
    if (_bstCldToken != null) await prefs.setString(_bstCldTokenKey, _bstCldToken!);
    if (_refreshToken != null) await prefs.setString(_refreshTokenKey, _refreshToken!);
    if (_userEmail != null) await prefs.setString(_userEmailKey, _userEmail!);
    if (_userName != null) await prefs.setString(_userNameKey, _userName!);
    if (_schoolName != null) await prefs.setString(_schoolNameKey, _schoolName!);

    // Worker에서 shortId 동기화
    if (_userEmail != null && _userEmail!.isNotEmpty) {
      try {
        final profRes = await http.get(
          Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/auth/profile/get?email=${Uri.encodeComponent(_userEmail!)}'),
        ).timeout(const Duration(seconds: 4));
        if (profRes.statusCode == 200) {
          final pData = jsonDecode(profRes.body) as Map<String, dynamic>;
          if (pData['shortId'] != null) {
            _shortId = pData['shortId'].toString();
            await prefs.setString(_shortIdKey, _shortId!);
          }
        }
      } catch (_) {}
    }

    _startAutoRefreshTimer();
  }

  /// 웹사이트를 쳐다보지 않고 127.0.0.1 켜두고 구글 OAuth로 직접 직행
  Future<void> openWebAuthPortal() async {
    await loginWithLocalLoopbackOAuth();
  }

  /// Chrome / Edge 브라우저에서 구글 OAuth 로그인 실행 (100% 127.0.0.1 Local Loopback HTTP Server 수신)
  Future<bool> loginWithBrowserOAuth({String? targetWebUrl, bool includeBoardest = true, bool includeBstCld = true, bool includeCanva = false}) async {
    return loginWithLocalLoopbackOAuth(targetWebUrl: targetWebUrl, includeBoardest: includeBoardest, includeBstCld: includeBstCld, includeCanva: includeCanva);
  }

  /// Chrome / Edge 브라우저에서 Google OAuth 로그인 실행 (상시 가동 루프백 서버 포트 사용)
  Future<bool> loginWithLocalLoopbackOAuth({String? targetWebUrl, bool includeBoardest = true, bool includeBstCld = true, bool includeCanva = false}) async {
    _isAuthenticating = true;

    try {
      if (_localServer == null) {
        await startPersistentLoopbackServer();
      }

      List<String> params = [];
      if (includeBoardest) params.add('boardest-login=true');
      if (includeBstCld) params.add('boardest-cloud-login=true');
      final queryString = params.isNotEmpty ? params.join('&') : 'boardest-login=true';

      if (kIsWeb) {
        final webAuthUrl = 'https://boardest-teacher-oauth.web.app/?$queryString&target=web&sys=web';
        await launchUrl(Uri.parse(webAuthUrl), mode: LaunchMode.platformDefault);
        _isAuthenticating = false;
        return true;
      }

      final port = _activePort;
      final authUrl = 'https://boardest-teacher-oauth.web.app/?sys=win&target=win&port=$port&$queryString';
      final uri = Uri.parse(authUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _isAuthenticating = false;
        return true;
      } else {
        _isAuthenticating = false;
        return false;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] OAuth launch error: $e');
    }
    _isAuthenticating = false;
    return false;
  }

  /// Bst-cld 구글 드라이브 '만' 단독 연동 브라우저 OAuth 실행
  Future<bool> loginWithBstCldOnly() async {
    _isAuthenticating = true;
    try {
      if (_localServer == null) {
        await startPersistentLoopbackServer();
      }
      final port = _activePort;
      final redirectUri = 'https://boardest-teacher-oauth.web.app/?sys=win&target=win&port=$port&boardest-cloud-login=true';
      final uri = Uri.parse(redirectUri);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _isAuthenticating = false;
        return true;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] loginWithBstCldOnly error: $e');
    }
    _isAuthenticating = false;
    return false;
  }

  Future<void> stopOAuthLoopbackServer() async {
    if (_localServer != null) {
      try {
        await _localServer!.close(force: false);
      } catch (_) {}
      _localServer = null;
    }
  }

  Future<void> _fetchUserInfoFromGoogle(String accessToken) async {
    try {
      final res = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final email = data['email'] as String? ?? '';
        final name = data['name'] as String? ?? email.split('@').first;

        _userEmail = email;
        _userName = name;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userEmailKey, email);
        await prefs.setString(_userNameKey, name);
      }
    } catch (e) {
      debugPrint('[CloudDriveService] _fetchUserInfoFromGoogle error: $e');
    }
  }

  String? _boardestConnectFolderId;

  /// Google Drive에서 이름 기반 폴더 검색 (중복 생성 방지)
  Future<String?> findFolderByName(String folderName, {String? parentFolderId, bool isAppData = false}) async {
    if (!isLoggedIn) return null;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        String q = "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
        final isAdf = (isAppData || parentFolderId == 'appDataFolder');
        if (parentFolderId != null && parentFolderId.isNotEmpty && parentFolderId != 'root' && parentFolderId != 'appDataFolder') {
          q += " and '$parentFolderId' in parents";
        } else if (isAdf) {
          q += " and 'appDataFolder' in parents";
        }

        final spaceQuery = isAdf ? 'spaces=appDataFolder&' : '';
        final url = Uri.parse(
          'https://www.googleapis.com/drive/v3/files?'
          '$spaceQuery'
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
          return null;
        } else if (response.statusCode == 401 && attempt == 0) {
          debugPrint('[CloudDriveService] Drive API token notice: 401, attempting auto refresh...');
          final refreshed = await refreshAccessToken();
          if (refreshed) continue;
        }
      } catch (e) {
        debugPrint('[CloudDriveService] findFolderByName error: $e');
      }
    }
    return null;
  }

  String? _boardestPenFolderId;

  /// Google Drive 'bst-save' 루트 최상위 격리 폴더 ID 가져오기/생성
  Future<String?> getOrCreateConnectFolder() async {
    if (!isLoggedIn) return null;
    if (_boardestConnectFolderId != null && _boardestConnectFolderId!.isNotEmpty) {
      return _boardestConnectFolderId;
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedId = prefs.getString('bst_save_folder_id') ?? prefs.getString('bst_cld_folder_id');
    if (cachedId != null && cachedId.isNotEmpty) {
      _boardestConnectFolderId = cachedId;
      _boardestFolderId = cachedId;
      return cachedId;
    }

    final created = await _getOrCreateFolder('bst-save', 'appDataFolder');
    if (created != null) {
      _boardestConnectFolderId = created;
      _boardestFolderId = created;
      await prefs.setString('bst_save_folder_id', created);
    }
    return created;
  }

  /// Google Drive 'bst-pen' 최상위 판서 전용 루트 폴더 ID 가져오기/생성
  Future<String?> getOrCreatePenFolder() async {
    if (!isLoggedIn) return null;
    if (_bstPenFolderId != null && _bstPenFolderId!.isNotEmpty) {
      return _bstPenFolderId;
    }

    final existing = await findFolderByName('bst-pen', parentFolderId: 'appDataFolder', isAppData: true);
    if (existing != null) {
      _bstPenFolderId = existing;
      return existing;
    }

    final created = await createFolderInDrive('bst-pen', parentFolderId: 'appDataFolder');
    if (created != null) {
      _bstPenFolderId = created;
    }
    return created;
  }

  /// Google Drive 'bst-canva' 캔바 프로젝트 전용 루트 폴더 ID 가져오기/생성
  Future<String?> getOrCreateCanvaFolder() async {
    if (!isLoggedIn) return null;
    if (_bstCanvaFolderId != null && _bstCanvaFolderId!.isNotEmpty) {
      return _bstCanvaFolderId;
    }

    final existing = await findFolderByName('bst-canva', parentFolderId: 'appDataFolder', isAppData: true);
    if (existing != null) {
      _bstCanvaFolderId = existing;
      return existing;
    }

    final created = await createFolderInDrive('bst-canva', parentFolderId: 'appDataFolder');
    if (created != null) {
      _bstCanvaFolderId = created;
    }
    return created;
  }

  /// Google Drive 'bst-textbookpro' 교과서Pro 프로젝트 전용 루트 폴더 ID 가져오기/생성
  Future<String?> getOrCreateTextbookProFolder() async {
    if (!isLoggedIn) return null;
    if (_bstTextbookProFolderId != null && _bstTextbookProFolderId!.isNotEmpty) {
      return _bstTextbookProFolderId;
    }

    final existing = await findFolderByName('bst-textbookpro', parentFolderId: 'appDataFolder', isAppData: true);
    if (existing != null) {
      _bstTextbookProFolderId = existing;
      return existing;
    }

    final created = await createFolderInDrive('bst-textbookpro', parentFolderId: 'appDataFolder');
    if (created != null) {
      _bstTextbookProFolderId = created;
    }
    return created;
  }

  /// Google Drive 'bst-sync' PC 동기화 전용 루트 폴더 ID 가져오기/생성
  Future<String?> getOrCreateSyncFolder() async {
    if (!isLoggedIn) return null;
    if (_bstSyncFolderId != null && _bstSyncFolderId!.isNotEmpty) {
      return _bstSyncFolderId;
    }

    final existing = await findFolderByName('bst-sync', parentFolderId: 'appDataFolder', isAppData: true);
    if (existing != null) {
      _bstSyncFolderId = existing;
      return existing;
    }

    final created = await createFolderInDrive('bst-sync', parentFolderId: 'appDataFolder');
    if (created != null) {
      _bstSyncFolderId = created;
    }
    return created;
  }

  /// 과목 및 학년 매핑 설정 (subject_mappings.json) 로드
  Future<Map<String, dynamic>> fetchSubjectMappings() async {
    if (!isLoggedIn) return {};
    try {
      final saveFolderId = await getOrCreateConnectFolder();
      if (saveFolderId == null) return {};

      final files = await fetchDriveFiles(folderId: saveFolderId);
      final mappingFile = files.where((f) => f.name == 'subject_mappings.json').firstOrNull;
      if (mappingFile != null) {
        final bytes = await fetchDriveFileBytes(mappingFile.id);
        if (bytes != null && bytes.isNotEmpty) {
          return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('[CloudDriveService] fetchSubjectMappings error: $e');
    }
    return {};
  }

  /// 과목 및 학년 매핑 설정 (subject_mappings.json) 저장
  Future<bool> saveSubjectMappings(Map<String, dynamic> mappings) async {
    if (!isLoggedIn) return false;
    try {
      final saveFolderId = await getOrCreateConnectFolder();
      if (saveFolderId == null) return false;

      final content = utf8.encode(jsonEncode(mappings));
      return await uploadBytesToDrive(Uint8List.fromList(content), 'subject_mappings.json', folderId: saveFolderId);
    } catch (e) {
      debugPrint('[CloudDriveService] saveSubjectMappings error: $e');
      return false;
    }
  }

  /// bst-save 에 저장된 모든 수업 자료 리스트 조회 (폴더 및 메타데이터 제외)
  Future<List<Map<String, dynamic>>> fetchMergedMaterials({String? targetFolderId}) async {
    if (!isLoggedIn) return [];
    final List<Map<String, dynamic>> merged = [];
    final Set<String> seenIds = {};

    try {
      final folderId = targetFolderId ?? await getOrCreateConnectFolder();
      if (folderId != null) {
        final files = await fetchDriveFiles(folderId: folderId, includeFolders: true);
        for (final f in files) {
          if (f.name == 'subject_mappings.json' || f.name == 'classroom_mappings.json') continue;
          if (seenIds.add(f.id)) {
            merged.add({
              'file': f,
              'source': 'cloud',
              'sourceLabel': '☁️ Cloud',
              'folderId': folderId,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[CloudDriveService] fetchMergedMaterials error: $e');
    }

    return merged;
  }

  /// Canva 디자인을 .canva.bst 파일로 bst-save 에 등록
  Future<bool> registerCanvaDesign({required String title, required String canvaUrl}) async {
    try {
      final regExp = RegExp(r'design/([A-Za-z0-9_-]+)');
      final match = regExp.firstMatch(canvaUrl);
      final canvaId = match != null ? match.group(1) : canvaUrl.trim();
      if (canvaId == null || canvaId.isEmpty) return false;

      final safeTitle = title.trim().isNotEmpty ? title.trim() : '켄바 디자인';
      final fileName = '$safeTitle.canva.bst';
      final content = jsonEncode({
        'canvaId': canvaId,
        'title': safeTitle,
        'created': DateTime.now().toIso8601String(),
      });

      final bytes = Uint8List.fromList(utf8.encode(content));
      final saveFolderId = await getOrCreateConnectFolder();
      final success = await uploadBytesToDrive(bytes, fileName, folderId: saveFolderId);
      return success;
    } catch (e) {
      debugPrint('[CloudDriveService] registerCanvaDesign error: $e');
      return false;
    }
  }

  /// bst-save 와 bst-pen 에 폴더 동시 생성
  Future<String?> createFolderPairInDrive(String folderName, {String? parentFolderId}) async {
    final saveFolderId = await getOrCreateConnectFolder();
    final penFolderId = await getOrCreatePenFolder();
    final createdSaveId = await createFolderInDrive(folderName, parentFolderId: parentFolderId ?? saveFolderId);
    if (penFolderId != null) {
      await createFolderInDrive(folderName, parentFolderId: penFolderId);
    }
    return createdSaveId;
  }

  /// bst-save 와 bst-pen 의 폴더 동시 삭제
  Future<bool> deleteFolderPairInDrive(String folderId, String folderName) async {
    await deleteDriveFile(folderId);
    final penFolderId = await getOrCreatePenFolder();
    if (penFolderId != null) {
      final penMatchId = await findFolderByName(folderName, parentFolderId: penFolderId);
      if (penMatchId != null) {
        await deleteDriveFile(penMatchId);
      }
    }
    return true;
  }

  /// ADF(Application Data Folder) 전체 사용 용량 계산 (Byte 단위)
  Future<int> calculateAdfStorageUsage() async {
    if (!isLoggedIn) return 0;
    try {
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?'
        'spaces=appDataFolder&'
        'fields=files(id,size)&'
        'pageSize=1000',
      );
      final res = await http.get(url, headers: authHeaders);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final files = data['files'] as List? ?? [];
        int totalBytes = 0;
        for (final f in files) {
          totalBytes += int.tryParse(f['size']?.toString() ?? '0') ?? 0;
        }
        return totalBytes;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] calculateAdfStorageUsage error: $e');
    }
    return 0;
  }

  /// ADF 영역 과거 데이터 일괄 정리/비우기
  Future<bool> cleanupAdfStorage({bool deleteOldPen = true}) async {
    if (!isLoggedIn) return false;
    try {
      if (deleteOldPen) {
        final penFolderId = await getOrCreatePenFolder();
        if (penFolderId != null) {
          final penDocs = await fetchDriveFoldersInParent(penFolderId);
          for (final doc in penDocs) {
            await deleteDriveFile(doc.id);
          }
        }
      }
      return true;
    } catch (e) {
      debugPrint('[CloudDriveService] cleanupAdfStorage error: $e');
      return false;
    }
  }

  /// 특정 부모 폴더 내 하위 폴더 목록만 안전하게 조회
  Future<List<CloudDriveFile>> fetchDriveFoldersInParent(String parentFolderId, {bool isAppData = false}) async {
    if (!isLoggedIn) return [];
    try {
      final isAdf = (isAppData || parentFolderId == 'appDataFolder');
      final parentQ = (parentFolderId == 'appDataFolder') ? "'appDataFolder' in parents" : "'$parentFolderId' in parents";
      final q = "mimeType = 'application/vnd.google-apps.folder' and $parentQ and trashed = false";
      final spaceQuery = isAdf ? 'spaces=appDataFolder&' : '';
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?'
        '$spaceQuery'
        'q=${Uri.encodeComponent(q)}&'
        'fields=files(id,name,mimeType,modifiedTime)&'
        'pageSize=100&orderBy=modifiedTime desc',
      );

      final res = await http.get(url, headers: authHeaders);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = data['files'] as List? ?? [];
        return list.map((f) => CloudDriveFile.fromJson(f as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('[CloudDriveService] fetchDriveFoldersInParent error: $e');
    }
    return [];
  }

  /// 프로젝트 폴더 내 판서 데이터 (pen_data.json) 저장
  Future<bool> saveProjectPenData(String projectFolderId, Map<String, dynamic> penData) async {
    if (!isLoggedIn) return false;
    final jsonStr = jsonEncode(penData);
    // 기존 pen_data.json 파일이 있는지 확인
    final files = await fetchDriveFiles(folderId: projectFolderId);
    final existingPenFile = files.where((f) => f.name == 'pen_data.json').firstOrNull;
    if (existingPenFile != null) {
      // 기존 파일 내용 덮어쓰기
      try {
        final url = Uri.parse('https://www.googleapis.com/upload/drive/v3/files/${existingPenFile.id}?uploadType=media');
        final res = await http.patch(
          url,
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: utf8.encode(jsonStr),
        );
        return res.statusCode == 200;
      } catch (e) {
        debugPrint('[CloudDriveService] saveProjectPenData patch error: $e');
      }
    }
    // 새로 생성
    return await uploadBytesToDrive(
      Uint8List.fromList(utf8.encode(jsonStr)),
      'pen_data.json',
      folderId: projectFolderId,
    );
  }

  /// 프로젝트 폴더 내 판서 데이터 (pen_data.json) 로드
  Future<Map<String, dynamic>?> fetchProjectPenData(String projectFolderId) async {
    if (!isLoggedIn) return null;
    try {
      final files = await fetchDriveFiles(folderId: projectFolderId);
      final penFile = files.where((f) => f.name == 'pen_data.json').firstOrNull;
      if (penFile == null) return null;

      final bytes = await fetchDriveFileBytes(penFile.id);
      if (bytes != null && bytes.isNotEmpty) {
        final str = utf8.decode(bytes);
        return jsonDecode(str) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] fetchProjectPenData error: $e');
    }
    return null;
  }

  /// ADF /bst-pen/ 내에 PenDocument (manifest.json + pages/page_X.svg) 폴더로 저장
  /// 판서 폴더 명명 규칙 생성:
  /// - 화이트보드: [Teacher] {날짜_시간}.pen (전자칠판: [반 ID] {날짜_시간}.pen)
  /// - Cloud 파일: 교사앱은 [Teacher] {파일명}.pen, 전자칠판은 [반 ID] {파일명}.pen
  static String formatCloudPenFolderName({
    required String fileName,
    String? type,
    bool isTeacherApp = true,
    String? classroom,
    String? teacherName,
  }) {
    // 1. 화이트보드
    if (type?.toUpperCase() == 'WHITEBOARD' || fileName.isEmpty || fileName.toLowerCase().startsWith('whiteboard')) {
      final now = DateTime.now();
      final dtStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      String prefix = '[Teacher]';
      if (!isTeacherApp && classroom != null && classroom.trim().isNotEmpty) {
        final digits = classroom.trim().replaceAll(RegExp(r'[^\d]'), '');
        prefix = digits.isNotEmpty ? '[$digits]' : '[$classroom]';
      }
      return '$prefix $dtStr.pen';
    }

    String prefix = '[Teacher]';
    if (!isTeacherApp && classroom != null && classroom.trim().isNotEmpty) {
      final digits = classroom.trim().replaceAll(RegExp(r'[^\d]'), '');
      prefix = digits.isNotEmpty ? '[$digits]' : '[$classroom]';
    }

    String cleanName = fileName.trim();
    if (cleanName.endsWith('.pen')) {
      cleanName = cleanName.substring(0, cleanName.length - 4);
    }
    if (cleanName.endsWith('.bstpen')) {
      cleanName = cleanName.substring(0, cleanName.length - 7);
    }
    return '$prefix $cleanName.pen';
  }

  /// ADF /bst-pen/ 내에 PenDocument (info.json + manifest.json + pages/page_X.svg) 폴더로 저장
  Future<bool> savePenDocumentToAdf(
    PenDocument doc, {
    String? originalFileName,
    String? classroom,
    String? teacherName,
    String? originalFileId,
  }) async {
    if (!isLoggedIn) return false;
    try {
      final penFolderId = await getOrCreatePenFolder();
      if (penFolderId == null) return false;

      final targetTitle = originalFileName ?? doc.title;
      final folderName = formatCloudPenFolderName(
        fileName: targetTitle,
        classroom: classroom ?? doc.classroom,
        teacherName: teacherName ?? _userName,
      );
      final safeFolderName = folderName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      
      // 1. 해당 판서 전용 하위 폴더 생성 / 조회
      final existingDocs = await fetchDriveFoldersInParent(penFolderId);
      var docFolder = existingDocs.where((f) => f.name == safeFolderName || f.name == targetTitle).firstOrNull;
      String docFolderId;
      if (docFolder != null) {
        docFolderId = docFolder.id;
      } else {
        final newId = await createFolderInDrive(safeFolderName, parentFolderId: penFolderId);
        if (newId == null) return false;
        docFolderId = newId;
      }

      // 2. info.json & manifest.json 메타데이터 저장
      final infoMap = {
        'title': targetTitle,
        'folderName': safeFolderName,
        'classroom': classroom ?? doc.classroom ?? '',
        'teacher': teacherName ?? _userName ?? '',
        'originalFileId': originalFileId ?? '',
        'totalPages': doc.totalPages,
        'createdAt': doc.createdAt,
        'updatedAt': DateTime.now().toIso8601String(),
        'version': 1,
      };
      final infoBytes = Uint8List.fromList(utf8.encode(jsonEncode(infoMap)));
      await uploadBytesToDrive(infoBytes, 'info.json', folderId: docFolderId);

      final manifestJson = utf8.encode(jsonEncode(doc.toManifestJson()));
      await uploadBytesToDrive(Uint8List.fromList(manifestJson), 'manifest.json', folderId: docFolderId);

      // 3. pages/page_X.svg 저장
      for (final entry in doc.pages.entries) {
        final pageIdx = entry.key;
        final svgStr = entry.value;
        final svgBytes = Uint8List.fromList(utf8.encode(svgStr));
        await uploadBytesToDrive(svgBytes, 'page_$pageIdx.svg', folderId: docFolderId);
      }

      return true;
    } catch (e) {
      debugPrint('[CloudDriveService] savePenDocumentToAdf error: $e');
      return false;
    }
  }

  /// ADF /bst-pen/{docFolderId}/ 내 특정 페이지만 0.1초 부분 스트리밍 로드
  Future<String?> streamPenPageFromAdf(String docFolderId, int pageIndex) async {
    if (!isLoggedIn) return null;
    try {
      final files = await fetchDriveFiles(folderId: docFolderId);
      final pageFile = files.where((f) => f.name == 'page_$pageIndex.svg').firstOrNull;
      if (pageFile == null) return null;

      final bytes = await fetchDriveFileBytes(pageFile.id);
      if (bytes != null && bytes.isNotEmpty) {
        return utf8.decode(bytes);
      }
    } catch (e) {
      debugPrint('[CloudDriveService] streamPenPageFromAdf error: $e');
    }
    return null;
  }

  /// ADF /bst-pen/{docFolderId}/ 의 manifest.json 메타데이터 로드
  Future<Map<String, dynamic>?> fetchPenManifestFromAdf(String docFolderId) async {
    if (!isLoggedIn) return null;
    try {
      final files = await fetchDriveFiles(folderId: docFolderId);
      final manifestFile = files.where((f) => f.name == 'manifest.json').firstOrNull;
      if (manifestFile == null) return null;

      final bytes = await fetchDriveFileBytes(manifestFile.id);
      if (bytes != null && bytes.isNotEmpty) {
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] fetchPenManifestFromAdf error: $e');
    }
    return null;
  }

  /// Google Drive REST API — 지정 폴더 또는 bst-save 내 파일 및 폴더 목록 가져오기
  Future<List<CloudDriveFile>> fetchDriveFiles({String? folderId, bool includeFolders = true}) async {
    if (!isLoggedIn) return [];

    try {
      final List<CloudDriveFile> allFiles = [];
      final targetFolder = folderId ?? await getOrCreateConnectFolder();
      if (targetFolder == null) return [];

      final parentQuery = (targetFolder == 'appDataFolder')
          ? "'appDataFolder' in parents"
          : "'$targetFolder' in parents";
      final folderFilter = includeFolders ? "" : " and mimeType!='application/vnd.google-apps.folder'";

      Future<void> querySpace(String? space) async {
        final spaceParam = space != null ? 'spaces=$space&' : '';
        final url = Uri.parse(
          "https://www.googleapis.com/drive/v3/files?${spaceParam}q=trashed=false and $parentQuery$folderFilter&fields=files(id,name,mimeType,size,webViewLink,webContentLink,modifiedTime)&pageSize=100&orderBy=folder,modifiedTime desc",
        );
        var res = await http.get(url, headers: {'Authorization': 'Bearer $_accessToken', 'Accept': 'application/json'});
        if (res.statusCode == 401) {
          final refreshed = await refreshAccessToken();
          if (refreshed) {
            res = await http.get(url, headers: {'Authorization': 'Bearer $_accessToken', 'Accept': 'application/json'});
          }
        }
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final filesJson = data['files'] as List? ?? [];
          for (final item in filesJson) {
            final f = CloudDriveFile.fromJson(item as Map<String, dynamic>);
            final lower = f.name.toLowerCase();
            if (lower.endsWith('.file.pen') || lower == 'classroom_mappings.json' || lower == 'subject_mappings.json') continue;
            if (!allFiles.any((existing) => existing.id == f.id)) {
              allFiles.add(f);
            }
          }
        }
      }

      await querySpace('appDataFolder');
      await querySpace(null);

      return allFiles;
    } catch (e) {
      debugPrint('[CloudDriveService] fetchDriveFiles error: $e');
    }
    return [];
  }

  /// 3번 탭: 'bst-Free' 폴더 내 화이트보드 판서 파일 (.Free.pen) 목록 조회
  Future<List<CloudDriveFile>> fetchFreePenFiles() async {
    if (!isLoggedIn) return [];
    try {
      final List<CloudDriveFile> results = [];
      final driveUrl = Uri.parse(
        "https://www.googleapis.com/drive/v3/files?q=trashed=false and (name contains '.Free.pen' or name contains '.pen')&fields=files(id,name,mimeType,size,modifiedTime)&pageSize=100&orderBy=modifiedTime desc",
      );

      final res = await http.get(
        driveUrl,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final filesJson = data['files'] as List? ?? [];
        for (final item in filesJson) {
          final f = CloudDriveFile.fromJson(item as Map<String, dynamic>);
          if (f.name.toLowerCase().endsWith('.file.pen')) continue;
          results.add(f);
        }
      }
      return results;
    } catch (e) {
      debugPrint('[CloudDriveService] fetchFreePenFiles error: $e');
      return [];
    }
  }

    /// Google Drive REST API — classroom_mappings.json 검색 및 읽기
  Future<Map<String, String>> fetchClassroomMappings() async {
    if (!isLoggedIn) return {};

    try {
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?'
        'spaces=appDataFolder&'
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

  static final Map<String, Uint8List> webMemoryFiles = {};

  /// 14일 이상 미사용된 로컬 클라우드 캐시 자동 정리 (14-day Inactivity Purge)
  Future<void> cleanExpiredCache() async {
    if (kIsWeb) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'bst_cloud_cache'));
      if (!cacheDir.existsSync()) return;

      final now = DateTime.now();
      final files = cacheDir.listSync(recursive: true);
      for (final file in files) {
        if (file is File) {
          final stat = file.statSync();
          final lastAccessed = stat.accessed.isAfter(stat.modified) ? stat.accessed : stat.modified;
          if (now.difference(lastAccessed).inDays >= 14) {
            try {
              file.deleteSync();
              debugPrint('[CloudDriveService] Deleted 14-day expired cache file: ${file.path}');
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[CloudDriveService] cleanExpiredCache error: $e');
    }
  }

  /// Google Drive 파일 다운로드 (Web: 인메모리 스트리밍 / Native: 100% 로컬 다운로드 및 차분 동기화)
  Future<File?> downloadDriveFileToTemp(CloudDriveFile driveFile) async {
    if (!isLoggedIn) return null;

    // Web: 인메모리 스트리밍 (Universal Pen)
    if (kIsWeb) {
      try {
        final url = Uri.parse('https://www.googleapis.com/drive/v3/files/${driveFile.id}?alt=media');
        var response = await http.get(
          url,
          headers: {'Authorization': 'Bearer $_accessToken'},
        );

        if (response.statusCode == 401 || response.statusCode == 403) {
          final refreshed = await refreshAccessToken();
          if (refreshed) {
            response = await http.get(
              url,
              headers: {'Authorization': 'Bearer $_accessToken'},
            );
          }
        }

        if (response.statusCode == 200) {
          webMemoryFiles[driveFile.id] = response.bodyBytes;
          webMemoryFiles[driveFile.name] = response.bodyBytes;
          return File(driveFile.name);
        }
      } catch (e) {
        debugPrint('[CloudDriveService] Web stream error: $e');
      }
      return null;
    }

    // Windows (exe) & Android (apk): 100% 로컬 다운로드 (스트리밍 금지) & 14일 캐시 + 차분 다운로드
    try {
      await cleanExpiredCache();

      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'bst_cloud_cache'));
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }

      final sanitizedName = driveFile.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final localFile = File(p.join(cacheDir.path, '${driveFile.id}_$sanitizedName'));

      final prefs = await SharedPreferences.getInstance();
      final cachedModKey = 'teacher_cache_mod_${driveFile.id}';
      final savedModTime = prefs.getString(cachedModKey);
      final remoteModTime = driveFile.modifiedTime?.toIso8601String() ?? '';

      // 수정본 차분 다운로드: 로컬 파일이 존재하고 원격 수정일시가 일치하면 다운로드 건너뜀
      if (localFile.existsSync() && localFile.lengthSync() > 0) {
        if (remoteModTime.isNotEmpty && savedModTime == remoteModTime) {
          debugPrint('[CloudDriveService] Cache HIT (파일 미수정, 로컬 캐시 즉시 재사용): ${localFile.path}');
          try {
            localFile.setLastModifiedSync(DateTime.now());
          } catch (_) {}
          return localFile;
        }
      }

      debugPrint('[CloudDriveService] Downloading full file to local disk: ${driveFile.name} (${driveFile.id})');
      final url = Uri.parse('https://www.googleapis.com/drive/v3/files/${driveFile.id}?alt=media');
      var response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_accessToken'},
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 401 || response.statusCode == 403) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          response = await http.get(
            url,
            headers: {'Authorization': 'Bearer $_accessToken'},
          ).timeout(const Duration(seconds: 120));
        }
      }

      if (response.statusCode == 200) {
        await localFile.writeAsBytes(response.bodyBytes, flush: true);
        if (remoteModTime.isNotEmpty) {
          await prefs.setString(cachedModKey, remoteModTime);
        }
        debugPrint('[CloudDriveService] Full download complete: ${localFile.path} (${response.bodyBytes.length} bytes)');
        return localFile;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] downloadDriveFileToTemp error: $e');
    }
    return null;
  }

  /// Google Drive 파일 직렬 스트리밍 URL 생성 (Authorization Bearer 헤더 포함)
  String getDriveMediaUrl(String fileId) {
    return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
  }

  /// Google Drive Authorization 헤더
  Map<String, String> get authHeaders => {
        if (_accessToken != null && _accessToken!.isNotEmpty)
          'Authorization': 'Bearer $_accessToken',
      };

  /// 로컬 저장 없이 인메모리(RAM) 스트리밍 바이트 가져오기
  Future<Uint8List?> fetchDriveFileBytes(String fileId) async {
    if (!isLoggedIn) return null;
    try {
      final url = Uri.parse(getDriveMediaUrl(fileId));
      var response = await http.get(url, headers: authHeaders);
      if (response.statusCode == 401 || response.statusCode == 403) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          response = await http.get(url, headers: authHeaders);
        }
      }
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] fetchDriveFileBytes error: $e');
    }
    return null;
  }

  /// Google Drive 파일 이름 변경
  Future<bool> renameDriveFile(String fileId, String newName) async {
    if (!isLoggedIn) return false;
    try {
      final url = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId');
      final res = await http.patch(
        url,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'name': newName}),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudDriveService] renameDriveFile error: $e');
      return false;
    }
  }

  /// Google Drive 파일 삭제
  Future<bool> deleteDriveFile(String fileId) async {
    if (!isLoggedIn) return false;
    try {
      final url = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId');
      final res = await http.delete(
        url,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );
      return res.statusCode == 204 || res.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudDriveService] deleteDriveFile error: $e');
      return false;
    }
  }

  /// 로컬 폴더 ↔ Google Drive bst-sync 폴더 재귀 동기화 (Windows EXE / Desktop)
  Future<int> syncLocalFolderToDrive(String localFolderPath, {String? targetDriveFolderId}) async {
    if (!isLoggedIn) return 0;
    if (kIsWeb) return 0;
    int uploadCount = 0;
    try {
      final rootDir = Directory(localFolderPath);
      if (!rootDir.existsSync()) return 0;

      final syncFolderId = targetDriveFolderId ?? await getOrCreateSyncFolder();
      if (syncFolderId == null) return 0;

      final Map<String, String> folderMap = {'': syncFolderId};
      final allEntities = rootDir.listSync(recursive: true, followLinks: false);

      // 1. 하위 디렉토리 계층 구조 생성
      final dirs = allEntities.whereType<Directory>().toList()
        ..sort((a, b) => a.path.length.compareTo(b.path.length));

      for (final dir in dirs) {
        final rel = p.relative(dir.path, from: localFolderPath).replaceAll('\\', '/');
        final parentRel = p.dirname(rel);
        final parentKey = (parentRel == '.' || parentRel.isEmpty) ? '' : parentRel;
        final parentId = folderMap[parentKey] ?? syncFolderId;
        final dirName = p.basename(dir.path);

        final existingId = await findFolderByName(dirName, parentFolderId: parentId, isAppData: true);
        final driveSubId = existingId ?? await createFolderInDrive(dirName, parentFolderId: parentId);
        if (driveSubId != null) {
          folderMap[rel] = driveSubId;
        }
      }

      // 2. 각 하위 디렉토리 및 루트 내 파일 업로드 (단, 판서 파일 .pen, .bstpen, .iwb 는 동기화 제외!)
      final files = allEntities.whereType<File>().toList();
      for (final file in files) {
        final lower = file.path.toLowerCase();
        if (lower.endsWith('.pen') || lower.endsWith('.bstpen') || lower.endsWith('.iwb')) {
          continue; // 판서 파일 동기화 제외
        }
        final rel = p.relative(file.path, from: localFolderPath).replaceAll('\\', '/');
        final parentRel = p.dirname(rel);
        final parentKey = (parentRel == '.' || parentRel.isEmpty) ? '' : parentRel;
        final targetParentId = folderMap[parentKey] ?? syncFolderId;

        final success = await uploadFileToDrive(file, folderId: targetParentId);
        if (success) uploadCount++;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] syncLocalFolderToDrive error: $e');
    }
    return uploadCount;
  }

  /// 웹 환경(kIsWeb) 폴더 선택 업로드 (상대 경로 디렉토리 자동 생성 및 업로드)
  Future<int> uploadWebFolderFilesToSync(List<WebFolderFile> files, {String? targetDriveFolderId}) async {
    if (!isLoggedIn || files.isEmpty) return 0;
    int uploadCount = 0;
    try {
      final syncFolderId = targetDriveFolderId ?? await getOrCreateSyncFolder();
      if (syncFolderId == null) return 0;

      final Map<String, String> folderMap = {'': syncFolderId};

      for (final file in files) {
        final relPath = file.relativePath.replaceAll('\\', '/');
        final parts = relPath.split('/');

        // 폴더 경로가 포함된 경우 (예: '수업자료/1단원/a.pdf')
        String currentRel = '';
        String currentParentId = syncFolderId;

        if (parts.length > 1) {
          for (int i = 0; i < parts.length - 1; i++) {
            final part = parts[i];
            final nextRel = currentRel.isEmpty ? part : '$currentRel/$part';

            if (!folderMap.containsKey(nextRel)) {
              final existingId = await findFolderByName(part, parentFolderId: currentParentId, isAppData: true);
              final createdId = existingId ?? await createFolderInDrive(part, parentFolderId: currentParentId);
              if (createdId != null) {
                folderMap[nextRel] = createdId;
                currentParentId = createdId;
              }
            } else {
              currentParentId = folderMap[nextRel]!;
            }
            currentRel = nextRel;
          }
        }

        final success = await uploadBytesToDrive(file.bytes, file.name, folderId: currentParentId);
        if (success) uploadCount++;
      }
    } catch (e) {
      debugPrint('[CloudDriveService] uploadWebFolderFilesToSync error: $e');
    }
    return uploadCount;
  }

  /// Google Drive REST API — 바이트 기반 파일 업로드 (웹/네이티브 공용 Multipart/Related)
  Future<bool> uploadBytesToDrive(Uint8List bytes, String fileName, {String? folderId}) async {
    if (!isLoggedIn) return false;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final targetParent = (folderId != null && folderId.isNotEmpty)
            ? folderId
            : (_boardestFolderId ?? await getOrCreateConnectFolder());
        final boundary = '----BoardestBoundary${DateTime.now().millisecondsSinceEpoch}';

        final metadataJson = jsonEncode({
          'name': fileName,
          if (targetParent != null && targetParent.isNotEmpty) 'parents': [targetParent]
        });

        final List<int> body = [];
        body.addAll(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadataJson\r\n'));
        body.addAll(utf8.encode('--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n'));
        body.addAll(bytes);
        body.addAll(utf8.encode('\r\n--$boundary--\r\n'));

        final bodyBytes = Uint8List.fromList(body);

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

        if (response.statusCode == 200 || response.statusCode == 201) {
          // bst-pen 에도 동일 파일명으로 판서 저장 폴더 자동 생성
          try {
            final penFolderId = await getOrCreatePenFolder();
            if (penFolderId != null) {
              await createFolderInDrive(fileName, parentFolderId: penFolderId);
            }
          } catch (_) {}
          return true;
        }
        return false;
      } catch (e) {
        debugPrint('[CloudDriveService] uploadBytesToDrive error: $e');
      }
    }
    return false;
  }

  /// Google Drive REST API — 로컬 파일 업로드 (Multipart/Related)
  /// Google Drive REST API — 로컬 파일 / 바이트 / 텍스트 범용 업로드 (Multipart/Related)
  Future<bool> uploadFileToDrive(dynamic localFile, {String? folderId, String? fileName}) async {
    if (!isLoggedIn) return false;
    try {
      if (localFile is Uint8List) {
        return await uploadBytesToDrive(
          localFile,
          fileName ?? 'upload_${DateTime.now().millisecondsSinceEpoch}',
          folderId: folderId,
        );
      } else if (localFile is List<int>) {
        return await uploadBytesToDrive(
          Uint8List.fromList(localFile),
          fileName ?? 'upload_${DateTime.now().millisecondsSinceEpoch}',
          folderId: folderId,
        );
      } else if (localFile is String) {
        return await uploadBytesToDrive(
          Uint8List.fromList(utf8.encode(localFile)),
          fileName ?? 'upload_${DateTime.now().millisecondsSinceEpoch}.json',
          folderId: folderId,
        );
      }
      if (!kIsWeb && localFile is File) {
        final name = fileName ?? p.basename(localFile.path);
        final bytes = await localFile.readAsBytes();
        return await uploadBytesToDrive(bytes, name, folderId: folderId);
      }
    } catch (e) {
      debugPrint('[CloudDriveService] uploadFileToDrive error: $e');
      return false;
    }
    return false;
  }

  /// Cloud 판서 폴더 저장 ([반ID] 원본파일명.pen)
  /// - Google Drive 'bst-pen' 폴더 내에 info.json (메타데이터) + strokes.json (판서 데이터) 저장
  Future<bool> saveDocumentPenFolderToDrive({
    required String originalFileName,
    String? classCode,
    String? teacherName,
    required String type, // 'PDF', 'PPT', 'HWP', 'WHITEBOARD', 'WEB', 'TBP', 'CANVA'
    required int totalPages,
    required Map<String, dynamic> metadata,
    required Map<String, dynamic> penData,
  }) async {
    if (!isLoggedIn) return false;
    try {
      final penFolderId = await getOrCreatePenFolder();
      if (penFolderId == null) return false;

      // 판서 폴더명 포맷팅: [203] 7단원 수업자료.pptx.pen 또는 [Teacher] {name}.pen
      final folderName = formatCloudPenFolderName(
        fileName: originalFileName,
        classroom: classCode,
        teacherName: teacherName ?? _userName,
      );
      final safeFolderName = folderName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      // 1. 해당 판서 폴더 존재 여부 확인 및 생성
      final existingDocs = await fetchDriveFoldersInParent(penFolderId);
      var docFolder = existingDocs.where((f) => f.name == safeFolderName).firstOrNull;
      String docFolderId;
      if (docFolder != null) {
        docFolderId = docFolder.id;
      } else {
        final newId = await createFolderInDrive(safeFolderName, parentFolderId: penFolderId);
        if (newId == null) return false;
        docFolderId = newId;
      }

      // 2. info.json 저장 (메타데이터)
      final infoMap = {
        'version': 2,
        'type': type,
        'fileName': originalFileName,
        'folderName': safeFolderName,
        'classCode': (classCode != null && classCode.isNotEmpty) ? classCode : '[Teacher]',
        'teacherName': teacherName ?? _userName ?? '',
        'totalPages': totalPages,
        'savedAt': DateTime.now().toIso8601String(),
        'metadata': metadata,
      };
      final infoBytes = Uint8List.fromList(utf8.encode(jsonEncode(infoMap)));
      await uploadBytesToDrive(infoBytes, 'info.json', folderId: docFolderId);

      // 3. strokes.json 저장 (판서 스트로크)
      final strokeBytes = Uint8List.fromList(utf8.encode(jsonEncode(penData)));
      await uploadBytesToDrive(strokeBytes, 'strokes.json', folderId: docFolderId);

      debugPrint('[CloudDriveService] Saved cloud .pen folder: $safeFolderName');
      return true;
    } catch (e) {
      debugPrint('[CloudDriveService] saveDocumentPenFolderToDrive error: $e');
      return false;
    }
  }

  /// Cloud 판서 폴더 목록 조회 (Google Drive 'bst-pen' 내 모든 [반ID] *.pen 폴더 및 info.json 로드)
  Future<List<Map<String, dynamic>>> fetchSavedPenFoldersFromDrive() async {
    if (!isLoggedIn) return [];
    final List<Map<String, dynamic>> result = [];
    try {
      final penFolderId = await getOrCreatePenFolder();
      if (penFolderId == null) return [];

      final folders = await fetchDriveFoldersInParent(penFolderId);
      for (final f in folders) {
        final folderName = f.name;
        if (!folderName.endsWith('.pen')) continue;

        String classCode = '[Teacher]';
        String rawFileName = folderName.substring(0, folderName.length - 4);
        if (folderName.startsWith('[')) {
          final closeIdx = folderName.indexOf(']');
          if (closeIdx > 0) {
            classCode = folderName.substring(0, closeIdx + 1);
            rawFileName = folderName.substring(closeIdx + 1).trim();
            if (rawFileName.endsWith('.pen')) {
              rawFileName = rawFileName.substring(0, rawFileName.length - 4).trim();
            }
          }
        }

        result.add({
          'id': f.id,
          'folderId': f.id,
          'name': folderName,
          'rawFileName': rawFileName,
          'classCode': classCode,
          'isCloud': true,
          'isFolderDoc': true,
          'modifiedTime': f.modifiedTime ?? DateTime.now(),
          'source': 'Google Drive (bst-pen)',
        });
      }
    } catch (e) {
      debugPrint('[CloudDriveService] fetchSavedPenFoldersFromDrive error: $e');
    }
    return result;
  }

  /// Google Drive 'BST-pen' 판서 폴더 ID 가져오기/생성 (중복 생성 방지)
  Future<String?> getBstPenFolderId() async {
    if (!isLoggedIn) return null;
    if (_bstPenFolderId != null && _bstPenFolderId!.isNotEmpty) {
      return _bstPenFolderId;
    }
    return await getOrCreatePenFolder();
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

      final List<int> body = [];
      body.addAll(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadataJson\r\n'));
      body.addAll(utf8.encode('--$boundary\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n$content\r\n'));
      body.addAll(utf8.encode('\r\n--$boundary--\r\n'));

      final bodyBytes = Uint8List.fromList(body);

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
      final folderId = driveFolderId ?? await getOrCreateConnectFolder();
      if (folderId == null) return false;

      // 1. Upload local files and subdirectories that don't exist on remote
      final remoteFiles = await fetchDriveFiles(folderId: folderId);
      final remoteMap = {for (var f in remoteFiles) f.name: f};

      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }

      final localEntities = localDir.listSync(recursive: false);
      for (final entity in localEntities) {
        final name = p.basename(entity.path);
        if (entity is File) {
          if (!remoteMap.containsKey(name)) {
            await uploadFileToDrive(entity, folderId: folderId);
          }
        } else if (entity is Directory) {
          final remoteSub = remoteMap[name];
          final subFolderId = remoteSub?.id ?? await createFolderInDrive(name, parentFolderId: folderId);
          if (subFolderId != null) {
            await syncFolderWithDrive(entity, driveFolderId: subFolderId);
          }
        }
      }

      // 2. Download remote files and subdirectories that don't exist locally
      final localEntitiesMap = {
        for (var e in localDir.listSync(recursive: false)) p.basename(e.path): e
      };

      for (final rFile in remoteFiles) {
        if (rFile.mimeType == 'application/vnd.google-apps.folder') {
          final subDir = Directory(p.join(localDir.path, rFile.name));
          if (!await subDir.exists()) {
            await subDir.create(recursive: true);
          }
          await syncFolderWithDrive(subDir, driveFolderId: rFile.id);
        } else {
          if (!localEntitiesMap.containsKey(rFile.name)) {
            final downloaded = await downloadDriveFileToTemp(rFile);
            if (downloaded != null) {
              final dest = File(p.join(localDir.path, rFile.name));
              await downloaded.copy(dest.path);
            }
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

import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'bst_cloud_logger.dart';
import 'totp_service.dart';

class BstCloudTeacher {
  final String teacherName;
  final String school;
  final String schoolId;
  final String folderId;
  final String bstCloudFolderId;
  final String bstPenFolderId;
  final String ownerEmail;
  final String? directAccessToken;
  final String? refreshToken;
  final String? totpSecret;
  final int lastConsumedWindow;
  final bool trustDeviceEnabled;
  final bool autoLessonFlowEnabled;
  final String? expiresAt;

  BstCloudTeacher({
    required this.teacherName,
    this.school = '',
    this.schoolId = '',
    required this.folderId,
    required this.bstCloudFolderId,
    required this.bstPenFolderId,
    required this.ownerEmail,
    this.directAccessToken,
    this.refreshToken,
    this.totpSecret,
    this.lastConsumedWindow = 0,
    this.trustDeviceEnabled = false,
    this.autoLessonFlowEnabled = true,
    this.expiresAt,
  });

  factory BstCloudTeacher.fromFirestore(Map<String, dynamic> fields, String teacherName) {
    final school = (fields['school'] as Map?)?['stringValue'] as String? ?? (fields['schoolName'] as Map?)?['stringValue'] as String? ?? '';
    final schoolId = (fields['schoolId'] as Map?)?['stringValue'] as String? ?? (fields['schoolCode'] as Map?)?['stringValue'] as String? ?? '';
    final folderId = (fields['folderId'] as Map?)?['stringValue'] as String? ?? '';
    final bstCloudFolderId = (fields['bstCloudFolderId'] as Map?)?['stringValue'] as String? ?? folderId;
    final bstPenFolderId = (fields['bstPenFolderId'] as Map?)?['stringValue'] as String? ?? '';
    final ownerEmail = (fields['email'] as Map?)?['stringValue'] as String? ?? (fields['ownerEmail'] as Map?)?['stringValue'] as String? ?? '';
    final name = (fields['name'] as Map?)?['stringValue'] as String? ?? (fields['teacherName'] as Map?)?['stringValue'] as String? ?? teacherName;
    final token = (fields['accessToken'] as Map?)?['stringValue'] as String?;
    final refresh = (fields['refreshToken'] as Map?)?['stringValue'] as String?;
    final totpSec = (fields['totpSecret'] as Map?)?['stringValue'] as String?;
    final lastWindowStr = (fields['lastConsumedWindow'] as Map?)?['integerValue'] as String? ?? '0';
    final trustDevice = (fields['trustDeviceEnabled'] as Map?)?['booleanValue'] as bool? ?? false;
    final autoLesson = (fields['autoLessonFlowEnabled'] as Map?)?['booleanValue'] as bool? ?? true;
    final exp = (fields['expiresAt'] as Map?)?['stringValue'] as String? ?? (fields['expiresAt'] as Map?)?['timestampValue'] as String?;
    return BstCloudTeacher(
      teacherName: name.isNotEmpty ? name : teacherName,
      school: school,
      schoolId: schoolId,
      folderId: folderId,
      bstCloudFolderId: bstCloudFolderId,
      bstPenFolderId: bstPenFolderId,
      ownerEmail: ownerEmail,
      directAccessToken: token,
      refreshToken: refresh,
      totpSecret: totpSec,
      lastConsumedWindow: int.tryParse(lastWindowStr) ?? 0,
      trustDeviceEnabled: trustDevice,
      autoLessonFlowEnabled: autoLesson,
      expiresAt: exp,
    );
  }
}

class BstCloudFile {
  final String id;
  final String name;
  final String mimeType;
  final int? size;

  BstCloudFile({
    required this.id,
    required this.name,
    required this.mimeType,
    this.size,
  });

  factory BstCloudFile.fromJson(Map<String, dynamic> json) {
    return BstCloudFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      size: json['size'] != null ? int.tryParse(json['size'].toString()) : null,
    );
  }
}

class ReversePairSession {
  final String secret;
  final String mangled;
  final String qrUrl;
  final DateTime createdAt;

  ReversePairSession({
    required this.secret,
    required this.mangled,
    required this.qrUrl,
    required this.createdAt,
  });
}

class BstCloudService {
  static final BstCloudService instance = BstCloudService._();
  BstCloudService._();

  static final Map<String, Uint8List> webMemoryFiles = {};

  String? activeToken;
  String? activeRefreshToken;
  String? activeFolderId;
  String? activeOwnerEmail;
  String? activeTotpSecret;
  String? activeTeacherName;

  /// 현재 활성화된 교사를 이 전자칠판 기기의 신뢰 기기(자동 로그인)로 등록
  Future<bool> registerActiveTeacherAsTrusted() async {
    if (activeOwnerEmail == null || activeOwnerEmail!.isEmpty) return false;
    final email = activeOwnerEmail!;
    final secret = activeTotpSecret ?? '';
    if (secret.isNotEmpty) {
      await saveTrustedSecret(email, secret);
    }
    // Firestore 교사 토큰 문서에 trustDeviceEnabled = true 패치
    if (activeTeacherName != null && activeTeacherName!.isNotEmpty) {
      try {
        final url = '$_firestoreBase/teacher_cloud_tokens/${Uri.encodeComponent(activeTeacherName!)}?updateMask.fieldPaths=trustDeviceEnabled&key=$_apiKey';
        await http.patch(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'fields': {
              'trustDeviceEnabled': {'booleanValue': true},
            },
          }),
        );
      } catch (e) {
        debugPrint('[BstCloudService] registerActiveTeacherAsTrusted patch error: $e');
      }
    }
    return true;
  }

  static String get _apiKey => AppConfig.firebaseApiKey;
  static String get _firestoreBase => AppConfig.firestoreBase;

  /// 1. 모든 드라이브 연동 완료된 교사 리스트 조회 (현재 학교 필터링 지원)
  Future<List<BstCloudTeacher>> getCloudTeachers({String? targetSchoolCode, String? targetSchoolName}) async {
    final teachers = <BstCloudTeacher>[];
    try {
      final url = '$_firestoreBase/teacher_cloud_tokens?key=$_apiKey';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final docs = data['documents'] as List<dynamic>? ?? [];
        for (final doc in docs) {
          final docName = p.basename(doc['name'] as String? ?? '');
          final fields = doc['fields'] as Map<String, dynamic>?;
          if (fields != null && docName.isNotEmpty) {
            final t = BstCloudTeacher.fromFirestore(fields, Uri.decodeComponent(docName));
            if (_isSchoolMatched(t, targetSchoolCode, targetSchoolName)) {
              teachers.add(t);
            }
          }
        }
      }
      if (teachers.isNotEmpty) return teachers;
    } catch (e) {
      debugPrint('[BstCloudService] getCloudTeachers (teacher_cloud_tokens) error: $e');
    }
    // 레거시 컬렉션 fallback
    try {
      final legacyUrl = '$_firestoreBase/teachers_cloud?key=$_apiKey';
      final res = await http.get(Uri.parse(legacyUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final docs = data['documents'] as List<dynamic>? ?? [];
        for (final doc in docs) {
          final name = p.basename(doc['name'] as String? ?? '');
          final fields = doc['fields'] as Map<String, dynamic>?;
          if (fields != null && name.isNotEmpty) {
            final t = BstCloudTeacher.fromFirestore(fields, Uri.decodeComponent(name));
            if (_isSchoolMatched(t, targetSchoolCode, targetSchoolName)) {
              teachers.add(t);
            }
          }
        }
      }
    } catch (_) {}
    return teachers;
  }

  bool _isSchoolMatched(BstCloudTeacher t, String? targetSchoolCode, String? targetSchoolName) {
    if ((targetSchoolCode == null || targetSchoolCode.isEmpty) && (targetSchoolName == null || targetSchoolName.isEmpty)) {
      return true;
    }
    final code = (targetSchoolCode ?? '').trim().toLowerCase();
    final name = (targetSchoolName ?? '').trim().toLowerCase();
    final tSchool = t.school.trim().toLowerCase();
    final tSchoolId = t.schoolId.trim().toLowerCase();

    // Yangdong / YDM special matching
    if (code.contains('양동') || code == 'ydm' || name.contains('양동') || name == 'ydm') {
      if (tSchool.contains('양동') || tSchoolId == 'ydm' || tSchoolId == '48588' || t.teacherName.contains('양동')) {
        return true;
      }
      if (tSchool.isEmpty && tSchoolId.isEmpty) {
        return true;
      }
      return false; // Definitely another school
    }

    if (tSchool.isEmpty && tSchoolId.isEmpty) return true;

    return (code.isNotEmpty && (tSchoolId == code || tSchoolId.contains(code) || code.contains(tSchoolId))) ||
        (name.isNotEmpty && (tSchool.contains(name) || name.contains(tSchool)));
  }

  /// 2. 특정 교사에게 칠판 접속 요청 발송 (1:1 매핑 - Requests 서브컬렉션 사용)
  Future<bool> requestConnection({
    required String teacherName,
    required String classroomName,
  }) async {
    final docId = Uri.encodeComponent(teacherName);
    final classId = Uri.encodeComponent(classroomName);
    final url = '$_firestoreBase/cloud_connections/$docId/requests/$classId?key=$_apiKey';

    final body = {
      'fields': {
        'status': {'stringValue': 'pending'},
        'timestamp': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      }
    };

    try {
      final res = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        await BstCloudLogger.instance.logEvent(
          action: 'CAST_REQUESTED',
          teacherName: teacherName,
          classroomName: classroomName,
          details: '[$classroomName] 교실 전자칠판에서 [$teacherName] 선생님께 DriveCast 접속 승인을 요청했습니다.',
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BstCloudService] requestConnection error: $e');
      return false;
    }
  }

  /// 2.5 교사가 전자칠판으로 DriveCast 승인 토큰 즉시 전송
  Future<bool> approveConnectionRequest({
    required String teacherName,
    required String classroomName,
    required String token,
    required String folderId,
    int durationHours = 1,
  }) async {
    final docId = Uri.encodeComponent(teacherName);
    final classId = Uri.encodeComponent(classroomName);
    final url = '$_firestoreBase/cloud_connections/$docId/requests/$classId?key=$_apiKey';

    final expiresAt = DateTime.now().add(Duration(hours: durationHours)).toUtc().toIso8601String();

    final body = {
      'fields': {
        'status': {'stringValue': 'approved'},
        'token': {'stringValue': token},
        'folderId': {'stringValue': folderId},
        'expiresAt': {'stringValue': expiresAt},
        'timestamp': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      }
    };

    try {
      final res = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[BstCloudService] approveConnectionRequest error: $e');
      return false;
    }
  }

  /// 3. 접속 승인 상세 정보 조회 (Access Token 포함 및 1회성 검증 후 삭제)
  Future<Map<String, String>> getConnectionApprovedDetails({
    required String teacherName,
    required String classroomName,
  }) async {
    final docId = Uri.encodeComponent(teacherName);
    final classId = Uri.encodeComponent(classroomName);
    final url = '$_firestoreBase/cloud_connections/$docId/requests/$classId?key=$_apiKey';
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 404) return {'status': 'none'};
      if (res.statusCode != 200) return {'status': 'error'};

      final data = json.decode(res.body) as Map<String, dynamic>;
      final fields = data['fields'] as Map<String, dynamic>?;
      if (fields == null) return {'status': 'none'};

      final status = (fields['status'] as Map?)?['stringValue'] as String? ?? 'pending';
      if (status == 'approved') {
        final token = (fields['token'] as Map?)?['stringValue'] as String? ?? '';
        final folderId = (fields['folderId'] as Map?)?['stringValue'] as String? ?? '';
        
        // 일회성 매핑: 칠판 클라이언트가 읽어간 즉시 Firestore에서 이 일회성 매핑 문서를 삭제하여 토큰 증발!
        await cancelConnection(teacherName: teacherName, classroomName: classroomName);

        return {
          'status': 'approved',
          'token': token,
          'folderId': folderId,
        };
      }
      return {'status': status};
    } catch (_) {
      return {'status': 'error'};
    }
  }

  /// 4. 접속 승인 초기화/해제 (삭제)
  Future<void> cancelConnection({
    required String teacherName,
    required String classroomName,
  }) async {
    final docId = Uri.encodeComponent(teacherName);
    final classId = Uri.encodeComponent(classroomName);
    final url = '$_firestoreBase/cloud_connections/$docId/requests/$classId?key=$_apiKey';
    try {
      await http.delete(Uri.parse(url)).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// 5. Google Drive API를 통해 boardest-cloud-connect 폴더 내 파일 리스트 조회 (Short-lived Token 사용)
  Future<List<BstCloudFile>> fetchDriveFiles(String folderId, String token) async {
    String targetFolderId = folderId;
    if (targetFolderId.isEmpty || targetFolderId == 'root') {
      final saveFolder = await findDriveFolderByName('bst-save', 'root', token) ??
                         await findDriveFolderByName('bst-cld', 'root', token) ?? 
                         await findDriveFolderByName('boardest-cloud-connect', 'root', token);
      if (saveFolder != null) {
        targetFolderId = saveFolder;
      }
    }

    final query = (targetFolderId.isNotEmpty && targetFolderId != 'root')
        ? "'$targetFolderId' in parents and trashed = false"
        : "trashed = false";
    final url = 'https://www.googleapis.com/drive/v3/files'
        '?q=${Uri.encodeComponent(query)}'
        '&fields=files(id,name,mimeType)';

    try {
      var currentToken = token;
      var res = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $currentToken',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 401 && activeRefreshToken != null && activeRefreshToken!.isNotEmpty) {
        debugPrint('[BstCloudService] fetchDriveFiles 401 Unauthorized. Auto-refreshing access token...');
        final newToken = await exchangeRefreshTokenForAccessToken(activeRefreshToken!);
        if (newToken != null && newToken.isNotEmpty) {
          activeToken = newToken;
          currentToken = newToken;
          res = await http.get(
            Uri.parse(url),
            headers: {
              'Authorization': 'Bearer $currentToken',
            },
          ).timeout(const Duration(seconds: 8));
        }
      }

      if (res.statusCode != 200) {
        debugPrint('[BstCloudService] fetchDriveFiles HTTP error: ${res.statusCode} ${res.body}');
        return [];
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final filesJson = data['files'] as List<dynamic>? ?? [];
      return filesJson.map((f) => BstCloudFile.fromJson(f as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[BstCloudService] fetchDriveFiles error: $e');
      return [];
    }
  }

  String getDriveMediaUrl(String fileId) {
    return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
  }

  /// 6. 14일 이상 미사용된 로컬 클라우드 캐시 자동 정리 (14-day Inactivity Purge)
  Future<void> cleanExpiredCache() async {
    if (kIsWeb) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'boardest_cloud_cache'));
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
              debugPrint('[BstCloudService] Deleted 14-day expired cache file: ${file.path}');
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[BstCloudService] cleanExpiredCache error: $e');
    }
  }

  /// 6.5 Google Drive 파일 다운로드 (Web: 인메모리 스트리밍 / Native: 100% 로컬 다운로드 및 차분 동기화)
  Future<String?> downloadDriveFile(
    String fileId,
    String fileName,
    String token, {
    String? remoteModifiedTime,
    int? remoteSize,
  }) async {
    // Web: 인메모리 스트리밍 (Universal Pen 렌더링용)
    if (kIsWeb) {
      final url = 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
      try {
        var currentToken = token;
        var res = await http.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $currentToken'},
        ).timeout(const Duration(seconds: 60));

        if (res.statusCode == 401 && activeRefreshToken != null && activeRefreshToken!.isNotEmpty) {
          final newToken = await exchangeRefreshTokenForAccessToken(activeRefreshToken!);
          if (newToken != null && newToken.isNotEmpty) {
            activeToken = newToken;
            currentToken = newToken;
            res = await http.get(
              Uri.parse(url),
              headers: {'Authorization': 'Bearer $currentToken'},
            ).timeout(const Duration(seconds: 60));
          }
        }

        if (res.statusCode == 200) {
          webMemoryFiles[fileId] = res.bodyBytes;
          webMemoryFiles[fileName] = res.bodyBytes;
          return fileId;
        }
      } catch (e) {
        debugPrint('[BstCloudService] Web stream error: $e');
      }
      return null;
    }

    // Windows (exe) & Android (apk): 100% 로컬 다운로드 (스트리밍 금지) & 14일 캐시 + 차분 다운로드
    try {
      await cleanExpiredCache();

      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'boardest_cloud_cache'));
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }

      final sanitizedFileName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final localFile = File(p.join(cacheDir.path, '${fileId}_$sanitizedFileName'));

      final prefs = await SharedPreferences.getInstance();
      final cachedModKey = 'cloud_cache_mod_$fileId';
      final savedModTime = prefs.getString(cachedModKey);

      // 수정본 차분 다운로드: 로컬 파일이 존재하고 원격 수정일시가 일치하면 다운로드 건너뜀
      if (localFile.existsSync() && localFile.lengthSync() > 0) {
        if (remoteModifiedTime != null && remoteModifiedTime.isNotEmpty && savedModTime == remoteModifiedTime) {
          debugPrint('[BstCloudService] Cache HIT (파일 미수정, 로컬 캐시 즉시 재사용): ${localFile.path}');
          try {
            localFile.setLastModifiedSync(DateTime.now());
          } catch (_) {}
          return localFile.path;
        }
      }

      // 원격 파일 전체를 한 번에 다운로드
      debugPrint('[BstCloudService] Downloading full file to local disk: $fileName ($fileId)');
      final url = 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
      var currentToken = token;
      var res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $currentToken'},
      ).timeout(const Duration(seconds: 120));

      if (res.statusCode == 401 && activeRefreshToken != null && activeRefreshToken!.isNotEmpty) {
        debugPrint('[BstCloudService] downloadDriveFile 401 Unauthorized. Auto-refreshing access token...');
        final newToken = await exchangeRefreshTokenForAccessToken(activeRefreshToken!);
        if (newToken != null && newToken.isNotEmpty) {
          activeToken = newToken;
          currentToken = newToken;
          res = await http.get(
            Uri.parse(url),
            headers: {'Authorization': 'Bearer $currentToken'},
          ).timeout(const Duration(seconds: 120));
        }
      }

      if (res.statusCode != 200) {
        debugPrint('[BstCloudService] downloadDriveFile HTTP error: ${res.statusCode}');
        return null;
      }

      await localFile.writeAsBytes(res.bodyBytes, flush: true);
      if (remoteModifiedTime != null && remoteModifiedTime.isNotEmpty) {
        await prefs.setString(cachedModKey, remoteModifiedTime);
      }
      debugPrint('[BstCloudService] Full download complete: ${localFile.path} (${res.bodyBytes.length} bytes)');
      return localFile.path;
    } catch (e) {
      debugPrint('[BstCloudService] downloadDriveFile error: $e');
      return null;
    }
  }

  /// Google Drive 파일 바이너리 다운로드 (메모리 로딩 및 Web 렌더링용)
  Future<Uint8List?> downloadDriveFileBytes(String fileId, String token) async {
    try {
      final url = 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
      var currentToken = token;
      var res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $currentToken'},
      ).timeout(const Duration(seconds: 60));

      if (res.statusCode == 401 && activeRefreshToken != null && activeRefreshToken!.isNotEmpty) {
        debugPrint('[BstCloudService] downloadDriveFileBytes 401 Unauthorized. Auto-refreshing access token...');
        final newToken = await exchangeRefreshTokenForAccessToken(activeRefreshToken!);
        if (newToken != null && newToken.isNotEmpty) {
          activeToken = newToken;
          currentToken = newToken;
          res = await http.get(
            Uri.parse(url),
            headers: {'Authorization': 'Bearer $currentToken'},
          ).timeout(const Duration(seconds: 60));
        }
      }

      if (res.statusCode == 200) {
        webMemoryFiles[fileId] = res.bodyBytes;
        return res.bodyBytes;
      }
    } catch (e) {
      debugPrint('[BstCloudService] downloadDriveFileBytes error: $e');
    }
    return null;
  }

  /// 6.5 Google Drive 이름 기반 폴더 검색 (중복 생성 방지, ADF 지원)
  Future<String?> findDriveFolderByName(String folderName, String parentFolderId, String token) async {
    final isAdf = parentFolderId == 'appDataFolder';
    final query = (parentFolderId == 'root' || parentFolderId.isEmpty)
        ? "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        : (isAdf
            ? "name = '$folderName' and 'appDataFolder' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
            : "name = '$folderName' and '$parentFolderId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false");
    final url = 'https://www.googleapis.com/drive/v3/files'
        '?${isAdf ? "spaces=appDataFolder&" : ""}'
        'q=${Uri.encodeComponent(query)}'
        '&fields=files(id,name)';
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final filesJson = data['files'] as List<dynamic>? ?? [];
        if (filesJson.isNotEmpty) {
          return filesJson.first['id'] as String?;
        }
      }
    } catch (e) {
      debugPrint('[BstCloudService] findDriveFolderByName error: $e');
    }
    return null;
  }

  /// 7. Google Drive 폴더 생성 (중복 방지 체크, ADF 지원)
  Future<String?> createDriveFolder(String folderName, String parentFolderId, String token) async {
    final existing = await findDriveFolderByName(folderName, parentFolderId, token);
    if (existing != null) return existing;

    final isAdf = parentFolderId == 'appDataFolder';
    final url = 'https://www.googleapis.com/drive/v3/files';
    try {
      final body = json.encode({
        'name': folderName,
        'mimeType': 'application/vnd.google-apps.folder',
        'parents': [isAdf ? 'appDataFolder' : parentFolderId],
      });
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        return data['id'] as String?;
      } else {
        debugPrint('[BstCloudService] createDriveFolder error: ${res.statusCode} ${res.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[BstCloudService] createDriveFolder Exception: $e');
      return null;
    }
  }

  /// 8. Google Drive 파일 업로드 (.IWB, .json, .pdf 등)
  Future<bool> uploadDriveFile({
    required File localFile,
    required String targetFolderId,
    required String token,
    String? customFileName,
  }) async {
    final fileName = customFileName ?? p.basename(localFile.path);
    final url = 'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart';

    try {
      final bytes = await localFile.readAsBytes();
      final boundary = '----BoardestBoundary${DateTime.now().millisecondsSinceEpoch}';

      final metadata = json.encode({
        'name': fileName,
        'parents': [targetFolderId],
      });

      final bodyBuffer = StringBuffer();
      bodyBuffer.write('--$boundary\r\n');
      bodyBuffer.write('Content-Type: application/json; charset=UTF-8\r\n\r\n');
      bodyBuffer.write('$metadata\r\n');
      bodyBuffer.write('--$boundary\r\n');
      bodyBuffer.write('Content-Type: application/octet-stream\r\n\r\n');

      final headerBytes = utf8.encode(bodyBuffer.toString());
      final footerBytes = utf8.encode('\r\n--$boundary--\r\n');

      final fullBody = <int>[
        ...headerBytes,
        ...bytes,
        ...footerBytes,
      ];

      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: Uint8List.fromList(fullBody),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200 || res.statusCode == 201) {
        debugPrint('[BstCloudService] File uploaded successfully: $fileName');
        return true;
      } else {
        debugPrint('[BstCloudService] Upload HTTP error: ${res.statusCode} ${res.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[BstCloudService] uploadDriveFile Exception: $e');
      return false;
    }
  }

  final Map<String, dynamic> _syncStateStore = {};
  final Map<String, ValueNotifier<dynamic>> _syncStateNotifiers = {};

  void saveSyncState(String key, dynamic value) {
    _syncStateStore[key] = value;
    if (!_syncStateNotifiers.containsKey(key)) {
      _syncStateNotifiers[key] = ValueNotifier(value);
    } else {
      _syncStateNotifiers[key]!.value = value;
    }
  }

  void listenSyncState(String key, void Function(dynamic value) callback) {
    if (!_syncStateNotifiers.containsKey(key)) {
      _syncStateNotifiers[key] = ValueNotifier(_syncStateStore[key]);
    }
    _syncStateNotifiers[key]!.addListener(() {
      callback(_syncStateNotifiers[key]!.value);
    });
  }

  void uploadAnnotation(String cloudFileName, Map<String, dynamic> iwbData) {
    saveSyncState(cloudFileName, iwbData);
  }

  /// 9. Refresh Token -> Google 임시 Access Token 교환
  Future<String?> exchangeRefreshTokenForAccessToken(String refreshToken) async {
    if (refreshToken.isEmpty) return null;
    try {
      final res = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': AppConfig.googleClientId,
          'client_secret': AppConfig.googleClientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        return data['access_token'] as String?;
      }
    } catch (e) {
      debugPrint('[BstCloudService] exchangeRefreshTokenForAccessToken error: $e');
    }
    return null;
  }

  /// 10. 수업자료 (Bst-cloud) 조회 - Read Only (RO)
  Future<List<BstCloudFile>> fetchBstCloudFiles(BstCloudTeacher teacher) async {
    final token = teacher.directAccessToken ?? 
        (teacher.refreshToken != null && teacher.refreshToken!.isNotEmpty 
            ? await exchangeRefreshTokenForAccessToken(teacher.refreshToken!) 
            : null);
    if (token == null || token.isEmpty) return [];

    String targetFolderId = teacher.bstCloudFolderId.isNotEmpty ? teacher.bstCloudFolderId : teacher.folderId;
    return fetchDriveFiles(targetFolderId, token);
  }

  /// 10-1. 1번 탭: 수업 자료 (Save) 파일 조회 (PDF, PPT, Canva 등 순수 교안)
  Future<List<BstCloudFile>> fetchDriveFolderFiles({
    required String accessToken,
    String folderName = 'bst-save',
  }) async {
    try {
      final List<BstCloudFile> results = [];

      // 1. appDataFolder 검색 (spaces=appDataFolder)
      final adfUrl = Uri.parse(
        "https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=trashed=false&fields=files(id,name,mimeType,size,webViewLink,webContentLink)&pageSize=100&orderBy=modifiedTime desc",
      );
      final adfRes = await http.get(adfUrl, headers: {'Authorization': 'Bearer $accessToken'});
      if (adfRes.statusCode == 401) {
        activeToken = null;
        activeTeacherName = null;
        activeOwnerEmail = null;
        activeTotpSecret = null;
        debugPrint('[BstCloudService] Token expired (401). Session reset.');
        return [];
      }

      if (adfRes.statusCode == 200) {
        final data = jsonDecode(adfRes.body);
        for (final f in (data['files'] as List? ?? [])) {
          if (f['mimeType'] == 'application/vnd.google-apps.folder') continue;
          final name = (f['name'] ?? '').toString();
          final lower = name.toLowerCase();
          if (lower == 'subject_mappings.json' || lower == 'classroom_mappings.json') continue;
          // 판서 파일(.pen, .file.pen, .Free.pen, .annot) 및 TBP 파일(.bsttbp, .tbp) 제외 -> 1번 탭은 순수 수업자료
          if (lower.endsWith('.pen') || lower.endsWith('.annot.json') || lower.contains('_annot') || lower.contains('.annotation') || lower.endsWith('.sync.json') || lower.endsWith('.bsttbp') || lower.endsWith('.tbp')) {
            continue;
          }
          results.add(BstCloudFile(
            id: f['id'] ?? '',
            name: name,
            mimeType: f['mimeType'] ?? '',
            size: f['size'] != null ? int.tryParse(f['size'].toString()) : null,
          ));
        }
      }

      // 2. 일반 Drive 검색 (spaces=drive)
      final driveUrl = Uri.parse(
        "https://www.googleapis.com/drive/v3/files?q=trashed=false and mimeType!='application/vnd.google-apps.folder'&fields=files(id,name,mimeType,size,webViewLink,webContentLink)&pageSize=100&orderBy=modifiedTime desc",
      );
      final driveRes = await http.get(driveUrl, headers: {'Authorization': 'Bearer $accessToken'});
      if (driveRes.statusCode == 401) {
        activeToken = null;
        activeTeacherName = null;
        activeOwnerEmail = null;
        activeTotpSecret = null;
        debugPrint('[BstCloudService] Token expired (401). Session reset.');
        return [];
      }

      if (driveRes.statusCode == 200) {
        final data = jsonDecode(driveRes.body);
        for (final f in (data['files'] as List? ?? [])) {
          final name = (f['name'] ?? '').toString();
          final lower = name.toLowerCase();
          if (lower == 'subject_mappings.json' || lower == 'classroom_mappings.json') continue;
          if (lower.endsWith('.pen') || lower.endsWith('.annot.json') || lower.contains('_annot') || lower.contains('.annotation') || lower.endsWith('.sync.json') || lower.endsWith('.bsttbp') || lower.endsWith('.tbp')) {
            continue;
          }
          if (!results.any((r) => r.id == f['id'])) {
            results.add(BstCloudFile(
              id: f['id'] ?? '',
              name: name,
              mimeType: f['mimeType'] ?? '',
              size: f['size'] != null ? int.tryParse(f['size'].toString()) : null,
            ));
          }
        }
      }
      return results;
    } catch (e) {
      debugPrint('[BstCloudService] fetchDriveFolderFiles error: $e');
      return [];
    }
  }

  /// 10-2. 2번 탭: TBP 전자교과서 목록 조회 (.bsttbp, .tbp)
  Future<List<BstCloudFile>> fetchTbpFiles({required String accessToken}) async {
    try {
      final List<BstCloudFile> results = [];
      final driveUrl = Uri.parse(
        "https://www.googleapis.com/drive/v3/files?q=trashed=false and (name contains '.bsttbp' or name contains '.tbp')&fields=files(id,name,mimeType,size)&pageSize=50&orderBy=modifiedTime desc",
      );
      final res = await http.get(driveUrl, headers: {'Authorization': 'Bearer $accessToken'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        for (final f in (data['files'] as List? ?? [])) {
          final name = (f['name'] ?? '').toString();
          if (name.toLowerCase().endsWith('.bsttbp') || name.toLowerCase().endsWith('.tbp')) {
            results.add(BstCloudFile(
              id: f['id'] ?? '',
              name: name,
              mimeType: f['mimeType'] ?? '',
              size: f['size'] != null ? int.tryParse(f['size'].toString()) : null,
            ));
          }
        }
      }
      return results;
    } catch (e) {
      debugPrint('[BstCloudService] fetchTbpFiles error: $e');
      return [];
    }
  }

  /// 10-3. 3번 탭: 화이트보드 판서보드 (Free) 파일 목록 조회 ('bst-Free' 폴더 내 .Free.pen)
  Future<List<BstCloudFile>> fetchBstFreeFiles({required String accessToken}) async {
    try {
      final List<BstCloudFile> results = [];

      // 1. 'bst-Free' 폴더 ID 찾기
      String? freeFolderId = await findDriveFolderByName('bst-Free', 'root', accessToken);
      freeFolderId ??= await findDriveFolderByName('bst-Free', 'appDataFolder', accessToken);

      final q = freeFolderId != null
          ? "'$freeFolderId' in parents and trashed=false"
          : "trashed=false and (name contains '.Free.pen' or name contains '.pen')";

      final url = Uri.parse(
        "https://www.googleapis.com/drive/v3/files?q=${Uri.encodeComponent(q)}&fields=files(id,name,mimeType,size,modifiedTime)&pageSize=100&orderBy=modifiedTime desc",
      );
      final res = await http.get(url, headers: {'Authorization': 'Bearer $accessToken'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        for (final f in (data['files'] as List? ?? [])) {
          if (f['mimeType'] == 'application/vnd.google-apps.folder') continue;
          final name = (f['name'] ?? '').toString();
          // .file.pen (파일 위 판서)는 3번 탭에서도 제외! 오직 .Free.pen 또는 자유 판서만 포함!
          if (name.toLowerCase().endsWith('.file.pen')) continue;
          if (name.toLowerCase().endsWith('.pen') || name.toLowerCase().contains('free')) {
            results.add(BstCloudFile(
              id: f['id'] ?? '',
              name: name,
              mimeType: f['mimeType'] ?? '',
              size: f['size'] != null ? int.tryParse(f['size'].toString()) : null,
            ));
          }
        }
      }
      return results;
    } catch (e) {
      debugPrint('[BstCloudService] fetchBstFreeFiles error: $e');
      return [];
    }
  }

  /// 11. 판서/필기 노트 (Bst-pen) 목록 조회
  Future<List<BstCloudFile>> fetchBstPenFiles(BstCloudTeacher teacher) async {
    final token = teacher.directAccessToken ?? 
        (teacher.refreshToken != null && teacher.refreshToken!.isNotEmpty 
            ? await exchangeRefreshTokenForAccessToken(teacher.refreshToken!) 
            : null);
    if (token == null || token.isEmpty) return [];

    String targetFolderId = teacher.bstPenFolderId;
    if (targetFolderId.isEmpty && teacher.folderId.isNotEmpty) {
      targetFolderId = await findDriveFolderByName('bst-pen', teacher.folderId, token) ?? '';
    }
    if (targetFolderId.isEmpty) return [];
    return fetchDriveFiles(targetFolderId, token);
  }

  /// 12. 전자칠판 판서/필기 노트 직접 업로드 (Bst-pen / Bst-Free 분리 지원)
  Future<bool> uploadBstPenNote({
    required BstCloudTeacher teacher,
    required String fileName,
    required Uint8List bytes,
    String targetFolderName = 'bst-Free',
  }) async {
    final token = teacher.directAccessToken ?? 
        (teacher.refreshToken != null && teacher.refreshToken!.isNotEmpty 
            ? await exchangeRefreshTokenForAccessToken(teacher.refreshToken!) 
            : null);
    if (token == null || token.isEmpty) return false;

    final isFilePen = fileName.toLowerCase().endsWith('.file.pen') || targetFolderName == 'bst-pen';
    final folderName = isFilePen ? 'bst-pen' : 'bst-Free';

    String targetFolderId = await findDriveFolderByName(folderName, 'root', token) ?? '';
    if (targetFolderId.isEmpty) {
      targetFolderId = await createDriveFolder(folderName, 'root', token) ?? '';
    }
    if (targetFolderId.isEmpty) return false;

    final url = 'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart';
    try {
      final boundary = '----BoardestPenBoundary${DateTime.now().millisecondsSinceEpoch}';
      final metadata = json.encode({
        'name': fileName,
        'parents': [targetFolderId],
      });

      final bodyBuffer = StringBuffer();
      bodyBuffer.write('--$boundary\r\n');
      bodyBuffer.write('Content-Type: application/json; charset=UTF-8\r\n\r\n');
      bodyBuffer.write('$metadata\r\n');
      bodyBuffer.write('--$boundary\r\n');
      bodyBuffer.write('Content-Type: application/octet-stream\r\n\r\n');

      final headerBytes = utf8.encode(bodyBuffer.toString());
      final footerBytes = utf8.encode('\r\n--$boundary--\r\n');

      final fullBody = <int>[
        ...headerBytes,
        ...bytes,
        ...footerBytes,
      ];

      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: Uint8List.fromList(fullBody),
      ).timeout(const Duration(seconds: 30));

      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[BstCloudService] uploadBstPenNote error: $e');
      return false;
    }
  }

  /// 전자칠판 현재 activeToken 기반 판서 파일(.file.pen in bst-pen / .Free.pen in bst-Free) 실시간 클라우드 업로드/동기화
  Future<bool> uploadPenBytesDirectly({
    required String fileName,
    required Uint8List bytes,
    String? targetFolderName,
  }) async {
    final token = activeToken;
    if (token == null || token.isEmpty) return false;

    // Web 메모리 캐시 보관
    webMemoryFiles[fileName] = bytes;

    try {
      final isFilePen = fileName.toLowerCase().endsWith('.file.pen') || targetFolderName == 'bst-pen';
      final folderName = isFilePen ? 'bst-pen' : 'bst-Free';

      // 1. 해당 폴더 ID 획득 또는 생성
      String? folderId = await findDriveFolderByName(folderName, 'root', token);
      folderId ??= await createDriveFolder(folderName, 'root', token);

      final url = 'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart';
      final boundary = '----BoardestPenDirect${DateTime.now().millisecondsSinceEpoch}';
      final parentList = (folderId != null && folderId.isNotEmpty) ? [folderId] : <String>[];
      final metadata = json.encode({
        'name': fileName,
        if (parentList.isNotEmpty) 'parents': parentList,
      });

      final bodyBuffer = StringBuffer();
      bodyBuffer.write('--$boundary\r\n');
      bodyBuffer.write('Content-Type: application/json; charset=UTF-8\r\n\r\n');
      bodyBuffer.write('$metadata\r\n');
      bodyBuffer.write('--$boundary\r\n');
      bodyBuffer.write('Content-Type: application/octet-stream\r\n\r\n');

      final headerBytes = utf8.encode(bodyBuffer.toString());
      final footerBytes = utf8.encode('\r\n--$boundary--\r\n');

      final fullBody = <int>[
        ...headerBytes,
        ...bytes,
        ...footerBytes,
      ];

      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: Uint8List.fromList(fullBody),
      ).timeout(const Duration(seconds: 10));

      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[BstCloudService] uploadPenBytesDirectly error: $e');
      return false;
    }
  }

  /// 파일 위 판서 데이터 (.file.pen) 다운로드/불러오기
  Future<Uint8List?> fetchFilePenBytes({
    required String originalFileName,
    required String accessToken,
    String? classCode,
  }) async {
    try {
      final penName = (classCode != null && classCode.isNotEmpty)
          ? '${classCode}_$originalFileName.file.pen'
          : '$originalFileName.file.pen';
      if (webMemoryFiles.containsKey(penName)) {
        return webMemoryFiles[penName];
      }

      // bst-pen 폴더 검색
      final penFolderId = await findDriveFolderByName('bst-pen', 'root', accessToken);
      final q = penFolderId != null
          ? "'$penFolderId' in parents and name = '$penName' and trashed = false"
          : "name = '$penName' and trashed = false";

      final url = Uri.parse(
        "https://www.googleapis.com/drive/v3/files?q=${Uri.encodeComponent(q)}&fields=files(id,name)&pageSize=1",
      );
      final res = await http.get(url, headers: {'Authorization': 'Bearer $accessToken'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final files = data['files'] as List? ?? [];
        if (files.isNotEmpty) {
          final fileId = files[0]['id'];
          final dlUrl = Uri.parse("https://www.googleapis.com/drive/v3/files/$fileId?alt=media");
          final dlRes = await http.get(dlUrl, headers: {'Authorization': 'Bearer $accessToken'});
          if (dlRes.statusCode == 200) {
            webMemoryFiles[penName] = dlRes.bodyBytes;
            return dlRes.bodyBytes;
          }
        }
      }
    } catch (e) {
      debugPrint('[BstCloudService] fetchFilePenBytes error: $e');
    }
    return null;
  }

    /// 13. RFC 6238 TOTP 60초 1회용 동적 PIN 검증 & 단기 Access Token 발급 및 소각 처리
  Future<({bool success, String? accessToken, String? errorMessage})> verifyAndAuthenticateWithTotp({
    required BstCloudTeacher teacher,
    required String inputOtp,
    required String classroomName,
  }) async {
    final secret = (teacher.totpSecret != null && teacher.totpSecret!.isNotEmpty)
        ? teacher.totpSecret!
        : TotpService.generateDeterministicSecret(teacher.ownerEmail);
    if (secret.isEmpty) {
      return (
        success: false,
        accessToken: null,
        errorMessage: '해당 선생님의 교사용 앱에서 OTP 시크릿이 등록되지 않았습니다.'
      );
    }

    final verification = TotpService.verifyOtp(
      secret: secret,
      inputOtp: inputOtp,
      lastConsumedWindow: teacher.lastConsumedWindow,
    );

    if (!verification.isValid) {
      await BstCloudLogger.instance.logEvent(
        action: 'OTP_AUTH_FAILED',
        teacherName: teacher.teacherName,
        classroomName: classroomName,
        details: '[$classroomName] OTP 인증 실패: ${verification.reason ?? "불일치"} (입력: $inputOtp)',
      );
      return (
        success: false,
        accessToken: null,
        errorMessage: verification.reason ?? 'OTP 번호가 일치하지 않습니다.'
      );
    }

    final uid = teacher.ownerEmail.replaceAll('.', '_').replaceAll('@', '_');
    final firestoreUrl = '$_firestoreBase/teacher_cloud_tokens/$uid?key=$_apiKey&updateMask.fieldPaths=lastConsumedWindow';
    try {
      await http.patch(
        Uri.parse(firestoreUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fields': {
            'lastConsumedWindow': {'integerValue': verification.matchedWindow.toString()},
          }
        }),
      );
    } catch (_) {}

    String? accessToken = teacher.directAccessToken;
    if (teacher.refreshToken != null && teacher.refreshToken!.isNotEmpty) {
      accessToken = await exchangeRefreshTokenForAccessToken(teacher.refreshToken!);
    }

    if (accessToken == null || accessToken.isEmpty) {
      return (
        success: false,
        accessToken: null,
        errorMessage: 'Access Token 발급에 실패했습니다. 교사용 앱에서 구글 연동을 확인해주세요.'
      );
    }

    activeToken = accessToken;
    activeTeacherName = teacher.teacherName;
    activeOwnerEmail = teacher.ownerEmail;
    activeTotpSecret = teacher.totpSecret;
    activeFolderId = teacher.bstCloudFolderId.isNotEmpty ? teacher.bstCloudFolderId : teacher.folderId;

    await BstCloudLogger.instance.logEvent(
      action: 'OTP_AUTH_SUCCESS',
      teacherName: teacher.teacherName,
      classroomName: classroomName,
      details: '[$classroomName] 6자리 OTP 인증 성공! 1회용 단기 Access Token 발급 및 소각 완료 (Window: ${verification.matchedWindow})',
    );
    return (
      success: true,
      accessToken: accessToken,
      errorMessage: null
    );
  }

  static const String _boardPairedSecretKey = 'bst_board_paired_secret';
  static const String _boardPairedKeyIdKey = 'bst_board_paired_key_id';

  /// 의도적으로 회손/난독화된 페어링 규격: BSTx! + Base64Url( "BRK#" + reversed(secret) + "#END" )
  static String manglePairSecret(String secret) {
    final reversedStr = secret.split('').reversed.join('');
    final payload = 'BRK#$reversedStr#END';
    final encoded = base64Url.encode(utf8.encode(payload));
    return 'BSTx!$encoded';
  }

  static String? unmanglePairSecret(String mangled) {
    try {
      if (!mangled.startsWith('BSTx!')) return null;
      var b64 = mangled.substring(5);
      b64 = b64.replaceAll('-', '+').replaceAll('_', '/');
      while (b64.length % 4 != 0) {
        b64 += '=';
      }
      final decoded = utf8.decode(base64.decode(b64));
      if (!decoded.startsWith('BRK#') || !decoded.endsWith('#END')) return null;
      final inner = decoded.substring(4, decoded.length - 4);
      return inner.split('').reversed.join('');
    } catch (_) {
      return null;
    }
  }

  /// 1회용 역방향 스마트폰 페어링 세션 생성 (스마트폰 카메라로 QR 스캔 시 바로 OAuth 로그인 및 전자칠판 연동)
  Future<ReversePairSession> createReversePairSession({
    String? schoolCode,
    int? grade,
    int? classNum,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rand = (DateTime.now().microsecondsSinceEpoch % 1000000).toString().padLeft(6, '0');
    final secret = 'sec_${nowMs}_$rand';
    final mangled = manglePairSecret(secret);
    final qrUrl = 'https://boardest-teacher-oauth.web.app/?bst_pair=${Uri.encodeComponent(mangled)}';

    try {
      final docUrl = '$_firestoreBase/cloud_pair_sessions/$secret?key=$_apiKey';
      await http.patch(
        Uri.parse(docUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fields': {
            'status': {'stringValue': 'pending'},
            'secret': {'stringValue': secret},
            'mangled': {'stringValue': mangled},
            'createdAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
            'expiresAt': {'timestampValue': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String()},
            if (schoolCode != null && schoolCode.isNotEmpty) 'schoolCode': {'stringValue': schoolCode},
            if (grade != null) 'grade': {'integerValue': grade.toString()},
            if (classNum != null) 'classNum': {'integerValue': classNum.toString()},
          }
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[BstCloudService] createReversePairSession doc error: $e');
    }

    return ReversePairSession(
      secret: secret,
      mangled: mangled,
      qrUrl: qrUrl,
      createdAt: DateTime.now(),
    );
  }

  /// 스마트폰에서 Google 로그인 및 연동 완료될 때까지 Firestore REST polling
  Future<({bool success, String? teacherName, String? email, String? errorMessage})>
      waitForReversePairAuth(String secret, {Duration timeout = const Duration(minutes: 5), bool Function()? isCancelled}) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < timeout) {
      if (isCancelled?.call() == true) {
        return (success: false, teacherName: null, email: null, errorMessage: '취소되었습니다.');
      }
      await Future.delayed(const Duration(milliseconds: 1500));
      if (isCancelled?.call() == true) {
        return (success: false, teacherName: null, email: null, errorMessage: '취소되었습니다.');
      }

      try {
        final docUrl = '$_firestoreBase/cloud_pair_sessions/$secret?key=$_apiKey';
        final res = await http.get(Uri.parse(docUrl)).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final fields = data['fields'] as Map<String, dynamic>?;
          if (fields != null) {
            final status = (fields['status'] as Map?)?['stringValue'] as String? ?? '';
            if (status == 'authenticated') {
              final token = (fields['accessToken'] as Map?)?['stringValue'] as String?;
              final refreshTok = (fields['refreshToken'] as Map?)?['stringValue'] as String?;
              final tName = (fields['teacherName'] as Map?)?['stringValue'] as String? ?? '선생님';
              final ownerEmail = (fields['email'] as Map?)?['stringValue'] as String? ?? '';
              final totpSec = (fields['totpSecret'] as Map?)?['stringValue'] as String?;
              final folderId = (fields['folderId'] as Map?)?['stringValue'] as String? ?? '';
              final bstCloudFolderId = (fields['bstCloudFolderId'] as Map?)?['stringValue'] as String? ?? folderId;

              if (token != null && token.isNotEmpty) {
                activeToken = token;
                activeRefreshToken = refreshTok;
                activeTeacherName = tName;
                activeOwnerEmail = ownerEmail;
                activeTotpSecret = totpSec;
                activeFolderId = bstCloudFolderId.isNotEmpty ? bstCloudFolderId : folderId;

                // Mark session consumed
                try {
                  await http.patch(
                    Uri.parse('$docUrl&updateMask.fieldPaths=status'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'fields': {'status': {'stringValue': 'consumed'}}
                    }),
                  );
                } catch (_) {}

                return (
                  success: true,
                  teacherName: tName,
                  email: ownerEmail,
                  errorMessage: null,
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[BstCloudService] waitForReversePairAuth check error: $e');
      }
    }

    return (
      success: false,
      teacherName: null,
      email: null,
      errorMessage: '인증 시간이 초과되었습니다 (5분). 다시 시도해주세요.',
    );
  }

  /// 1. 6자리 동적 자릿수 셔플 (Steganography) OTP 검증 (Cloudflare Worker 1차 + Firestore 직접 Fallback 2차)
  Future<({bool success, String? accessToken, String? teacherName, String? email, String? errorMessage})> verify6DigitSteganoOtp(String fullCode, {String? teacherId2}) async {
    try {
      var cleanCode = fullCode.replaceAll(RegExp(r'\s+'), '');
      if (cleanCode.length == 4 && teacherId2 != null && teacherId2.trim().isNotEmpty) {
        cleanCode = TotpService.encodeSteganography6(teacherId2.trim(), cleanCode);
      }
      if (cleanCode.length != 6 && cleanCode.length != 10) {
        return (success: false, accessToken: null, teacherName: null, email: null, errorMessage: '6자리 OTP 코드를 입력해주세요.');
      }

      // 1차: Cloudflare Worker 시도
      try {
        final res = await http.post(
          Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/auth/verify-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'code': cleanCode}),
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          activeToken = data['accessToken']?.toString();
          activeTeacherName = data['teacherName']?.toString() ?? '선생님';
          activeOwnerEmail = data['email']?.toString();
          activeTotpSecret = data['totpSecret']?.toString() ?? data['secret']?.toString();

          return (
            success: true,
            accessToken: activeToken,
            teacherName: activeTeacherName,
            email: activeOwnerEmail,
            errorMessage: null,
          );
        }
      } catch (_) {}

      // 2차: Firestore 직접 Fallback 검증 (시간 디버깅과 무관하게 무조건 실제 현재 시각 DateTime.now() 기준)
      try {
        final teachers = await getCloudTeachers();
        final nowTime = DateTime.now();
        final candidateTimes = [
          nowTime,
          nowTime.subtract(const Duration(minutes: 1)),
          nowTime.add(const Duration(minutes: 1)),
        ];

        for (final teacher in teachers) {
          final sec = (teacher.totpSecret != null && teacher.totpSecret!.isNotEmpty)
              ? teacher.totpSecret!
              : TotpService.generateDeterministicSecret(teacher.ownerEmail);

          bool isMatched = false;

          for (final t in candidateTimes) {
            if (cleanCode.length == 6) {
              final parsed = TotpService.parseSteganography6(cleanCode, time: t);
              final v4 = TotpService.verify4DigitOtp(
                secret: sec,
                inputOtp4: parsed.otp,
                lastConsumedWindow: 0,
                time: t,
              );
              if (v4.isValid) {
                isMatched = true;
                break;
              }
            }
            final vStd = TotpService.verifyComprehensiveOtp(
              secret: sec,
              inputOtp: cleanCode,
              lastConsumedWindow: 0,
              time: t,
            );
            if (vStd.isValid) {
              isMatched = true;
              break;
            }
          }

          if (isMatched) {
            String? tok = teacher.directAccessToken;
            if (teacher.refreshToken != null && teacher.refreshToken!.isNotEmpty) {
              tok = await exchangeRefreshTokenForAccessToken(teacher.refreshToken!);
            }
            if (tok != null && tok.isNotEmpty) {
              activeToken = tok;
              activeTeacherName = teacher.teacherName;
              activeOwnerEmail = teacher.ownerEmail;
              activeTotpSecret = teacher.totpSecret;
              activeFolderId = teacher.bstCloudFolderId.isNotEmpty ? teacher.bstCloudFolderId : teacher.folderId;
              return (
                success: true,
                accessToken: activeToken,
                teacherName: activeTeacherName,
                email: activeOwnerEmail,
                errorMessage: null,
              );
            }
          }
        }
      } catch (fbErr) {
        debugPrint('[BstCloudService] Firestore OTP fallback error: ' + fbErr.toString());
      }

      return (success: false, accessToken: null, teacherName: null, email: null, errorMessage: '일회용 접속 코드가 일치하지 않거나 만료되었습니다.');
    } catch (e) {
      return (success: false, accessToken: null, teacherName: null, email: null, errorMessage: '네트워크 연결 오류: ' + e.toString());
    }
  }

  /// 2. 2자리 Cloud ID 자동로그인 검증 (페어링된 전자칠판 전용)
  Future<({bool success, String? accessToken, String? teacherName, String? email, String? errorMessage})> verify2DigitAutoLogin(String cloudId, String roomCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pairedSecret = prefs.getString(_boardPairedSecretKey);
      final pairedKeyId = prefs.getString(_boardPairedKeyIdKey);

      if (pairedSecret == null || pairedSecret.isEmpty) {
        return (
          success: false,
          accessToken: null,
          teacherName: null,
          email: null,
          errorMessage: '이 전자칠판은 아직 자동로그인이 등록되지 않았습니다.\n상단 6자리 코드를 입력하거나 [칠판 자동로그인 등록]을 진행해주세요.',
        );
      }

      final currentOtp = TotpService.generate4DigitOtp(pairedSecret);
      final res = await http.post(
        Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'shortId': cloudId.trim(),
          'otp': currentOtp,
          'keyId': pairedKeyId,
          'roomCode': roomCode,
        }),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        activeToken = data['accessToken']?.toString();
        return (
          success: true,
          accessToken: activeToken,
          teacherName: data['teacherName']?.toString() ?? '선생님',
          email: data['email']?.toString(),
          errorMessage: null,
        );
      } else {
        final err = jsonDecode(res.body);
        return (success: false, accessToken: null, teacherName: null, email: null, errorMessage: err['error']?.toString() ?? '자동 로그인 실패: 등록되지 않은 Cloud ID이거나 페어링이 만료되었습니다.');
      }
    } catch (e) {
      return (success: false, accessToken: null, teacherName: null, email: null, errorMessage: '네트워크 오류: $e');
    }
  }

  /// 10자리 레거시 호환 메서드
  Future<({bool success, String? accessToken, String? teacherName, String? email, String? errorMessage})> verify10DigitOtp(String fullCode) => verify6DigitSteganoOtp(fullCode);
  Future<({bool success, String? accessToken, String? teacherName, String? email, String? errorMessage})> verify4DigitAutoLogin(String shortId, String roomCode) => verify2DigitAutoLogin(shortId, roomCode);

  /// 3. 전자칠판 자동 로그인 페어링 코드 발급 (3분 유효)
  Future<({bool success, String? pairingCode, int? expiresIn, String? tempSecret, String? errorMessage})> requestPairingCode(String schoolCode, String roomCode) async {
    try {
      final tempSecret = TotpService.generateDeterministicSecret('pair_${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.post(
        Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/auth/device/pair-request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'schoolCode': schoolCode,
          'roomCode': roomCode,
          'tempSecret': tempSecret,
        }),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_boardPairedSecretKey, tempSecret);
        await prefs.setString(_boardPairedKeyIdKey, 'board_${schoolCode.toLowerCase()}_${roomCode.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}');
        return (
          success: true,
          pairingCode: data['pairingCode']?.toString(),
          expiresIn: data['expiresIn'] as int? ?? 180,
          tempSecret: tempSecret,
          errorMessage: null,
        );
      } else {
        return (success: false, pairingCode: null, expiresIn: null, tempSecret: null, errorMessage: '페어링 요청 실패');
      }
    } catch (e) {
      return (success: false, pairingCode: null, expiresIn: null, tempSecret: null, errorMessage: '네트워크 오류: $e');
    }
  }

  static const String _trustedSecretPrefix = 'bst_trusted_secret_';
  static const String _trustedFailPrefix = 'bst_trusted_fails_';

  /// 교사별 신뢰 시크릿 키 로컬 저장
  Future<void> saveTrustedSecret(String email, String secret) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_trustedSecretPrefix${email.toLowerCase().trim()}';
    await prefs.setString(key, secret);
    await prefs.setInt('$_trustedFailPrefix${email.toLowerCase().trim()}', 0);
  }

  /// 교사별 신뢰 시크릿 키 조회
  Future<String?> getTrustedSecret(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_trustedSecretPrefix${email.toLowerCase().trim()}';
    return prefs.getString(key);
  }

  /// 교사별 신뢰 시크릿 키 삭제 (무효화 / 3회 실패 시)
  Future<void> removeTrustedSecret(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_trustedSecretPrefix${email.toLowerCase().trim()}';
    await prefs.remove(key);
    await prefs.remove('$_trustedFailPrefix${email.toLowerCase().trim()}');
  }

  /// 14. 기기 신뢰 자동 OTP 생성 및 인증 (최대 3회 실패 시 수동 입력 전환)
  Future<({bool success, String? accessToken, String? errorMessage, bool needManualOtp})> autoAuthenticateWithTrustedSecret({
    required BstCloudTeacher teacher,
    required String classroomName,
  }) async {
    final email = teacher.ownerEmail.toLowerCase().trim();
    final secret = await getTrustedSecret(email);

    // 1. 기기에 저장된 신뢰 키가 없거나 교사가 기기 신뢰를 끈 경우
    if (secret == null || secret.isEmpty || !teacher.trustDeviceEnabled) {
      if (secret != null && !teacher.trustDeviceEnabled) {
        await removeTrustedSecret(email);
      }
      return (
        success: false,
        accessToken: null,
        errorMessage: '기기 신뢰 키가 없습니다. OTP를 직접 입력해주세요.',
        needManualOtp: true,
      );
    }

    // 2. 현재 시간 기준 60초 OTP 번호 자동 계산
    final autoOtp = TotpService.generateCurrentOtp(secret);

    // 3. 서버에 OTP 검증
    final res = await verifyAndAuthenticateWithTotp(
      teacher: teacher,
      inputOtp: autoOtp,
      classroomName: classroomName,
    );

    final prefs = await SharedPreferences.getInstance();
    final failKey = '$_trustedFailPrefix$email';
    int fails = prefs.getInt(failKey) ?? 0;

    if (res.success) {
      // 성공 시 실패 카운트 리셋
      await prefs.setInt(failKey, 0);
      return (
        success: true,
        accessToken: res.accessToken,
        errorMessage: null,
        needManualOtp: false,
      );
    } else {
      // 실패 시 카운트 증가
      fails++;
      await prefs.setInt(failKey, fails);
      if (fails >= 3) {
        // 3회 이상 실패 시 시크릿 삭제 및 수동 입력으로 강제 전환
        await removeTrustedSecret(email);
        return (
          success: false,
          accessToken: null,
          errorMessage: '다시 입력해주세요 (3회 연속 자동 인증 실패로 신뢰가 초기화되었습니다).',
          needManualOtp: true,
        );
      } else {
        return (
          success: false,
          accessToken: null,
          errorMessage: '자동 인증 실패 ($fails/3). ${res.errorMessage ?? ""}',
          needManualOtp: false,
        );
      }
    }
  }

  /// 7. 수업 상태 저장 (Auto-Lesson Restore용)
  Future<bool> saveLessonSessionState({
    required String teacherEmail,
    required String classroomName,
    required String subject,
    required String fileName,
    required String fileId,
    required String fileType,
    int pageIndex = 1,
    Map<String, dynamic>? extra,
  }) async {
    final docId = Uri.encodeComponent('${teacherEmail}_$classroomName');
    final url = '$_firestoreBase/teacher_lesson_states/$docId?key=$_apiKey';

    final body = {
      'fields': {
        'teacherEmail': {'stringValue': teacherEmail},
        'classroomName': {'stringValue': classroomName},
        'subject': {'stringValue': subject},
        'fileName': {'stringValue': fileName},
        'fileId': {'stringValue': fileId},
        'fileType': {'stringValue': fileType},
        'pageIndex': {'integerValue': pageIndex.toString()},
        'timestamp': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      }
    };

    try {
      final res = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[BstCloudService] saveLessonSessionState error: $e');
      return false;
    }
  }

  /// 7.5 직전 수업 상태 조회 (Auto-Lesson Restore)
  Future<Map<String, dynamic>?> getLatestLessonSessionState({
    required String teacherEmail,
    required String classroomName,
  }) async {
    final docId = Uri.encodeComponent('${teacherEmail}_$classroomName');
    final url = '$_firestoreBase/teacher_lesson_states/$docId?key=$_apiKey';

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;

      final data = json.decode(res.body) as Map<String, dynamic>;
      final fields = data['fields'] as Map<String, dynamic>?;
      if (fields == null) return null;

      return {
        'teacherEmail': (fields['teacherEmail'] as Map?)?['stringValue'] ?? '',
        'classroomName': (fields['classroomName'] as Map?)?['stringValue'] ?? '',
        'subject': (fields['subject'] as Map?)?['stringValue'] ?? '',
        'fileName': (fields['fileName'] as Map?)?['stringValue'] ?? '',
        'fileId': (fields['fileId'] as Map?)?['stringValue'] ?? '',
        'fileType': (fields['fileType'] as Map?)?['stringValue'] ?? '',
        'pageIndex': int.tryParse((fields['pageIndex'] as Map?)?['integerValue']?.toString() ?? '1') ?? 1,
      };
    } catch (e) {
      debugPrint('[BstCloudService] getLatestLessonSessionState error: $e');
      return null;
    }
  }

  /// Drive 파일 텍스트 콘텐츠 읽기 (.canva.bst, .json 등)
  Future<String?> readDriveFileText(String fileId, String accessToken) async {
    try {
      final res = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (res.statusCode == 200) {
        return utf8.decode(res.bodyBytes);
      }
      return null;
    } catch (e) {
      debugPrint('[BstCloudService] readDriveFileText error: $e');
      return null;
    }
  }
}


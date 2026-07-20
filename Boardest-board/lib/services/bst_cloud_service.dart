import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';

class BstCloudTeacher {
  final String teacherName;
  final String folderId;
  final String ownerEmail;

  BstCloudTeacher({
    required this.teacherName,
    required this.folderId,
    required this.ownerEmail,
  });

  factory BstCloudTeacher.fromFirestore(Map<String, dynamic> fields, String teacherName) {
    final folderId = (fields['folderId'] as Map?)?['stringValue'] as String? ?? '';
    final ownerEmail = (fields['ownerEmail'] as Map?)?['stringValue'] as String? ?? '';
    return BstCloudTeacher(
      teacherName: teacherName,
      folderId: folderId,
      ownerEmail: ownerEmail,
    );
  }
}

class BstCloudFile {
  final String id;
  final String name;
  final String mimeType;

  BstCloudFile({
    required this.id,
    required this.name,
    required this.mimeType,
  });

  factory BstCloudFile.fromJson(Map<String, dynamic> json) {
    return BstCloudFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
    );
  }
}

class BstCloudService {
  static final BstCloudService instance = BstCloudService._();
  BstCloudService._();

  String? activeToken;
  String? activeFolderId;

  static String get _apiKey => AppConfig.firebaseApiKey;
  static String get _firestoreBase => AppConfig.firestoreBase;

  /// 1. 모든 드라이브 연동 완료된 교사 리스트 조회
  Future<List<BstCloudTeacher>> getCloudTeachers() async {
    final url = '$_firestoreBase/teachers_cloud?key=$_apiKey';
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final data = json.decode(res.body) as Map<String, dynamic>;
      final docs = data['documents'] as List<dynamic>? ?? [];

      final teachers = <BstCloudTeacher>[];
      for (final doc in docs) {
        final name = p.basename(doc['name'] as String? ?? '');
        final fields = doc['fields'] as Map<String, dynamic>?;
        if (fields != null && name.isNotEmpty) {
          teachers.add(BstCloudTeacher.fromFirestore(fields, Uri.decodeComponent(name)));
        }
      }
      return teachers;
    } catch (e) {
      debugPrint('[BstCloudService] getCloudTeachers error: $e');
      return [];
    }
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
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[BstCloudService] requestConnection error: $e');
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
      final connectFolder = await findDriveFolderByName('boardest-cloud-connect', 'root', token);
      if (connectFolder != null) {
        targetFolderId = connectFolder;
      }
    }

    final query = (targetFolderId.isNotEmpty && targetFolderId != 'root')
        ? "'$targetFolderId' in parents and trashed = false"
        : "trashed = false";
    final url = 'https://www.googleapis.com/drive/v3/files'
        '?q=${Uri.encodeComponent(query)}'
        '&fields=files(id,name,mimeType)';

    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));

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

  /// 6. Google Drive 보안 파일 로컬 임시 다운로드 (Bearer Auth 다운로드)
  Future<String?> downloadDriveFile(String fileId, String fileName, String token) async {
    final url = 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 60));
      
      if (res.statusCode != 200) {
        debugPrint('[BstCloudService] downloadDriveFile HTTP error: ${res.statusCode}');
        return null;
      }
      
      final tempDir = await getTemporaryDirectory();
      // 중복 방지를 위해 temp 폴더 내 고유 폴더 생성
      final uniqueDir = Directory(p.join(tempDir.path, 'cloud_${DateTime.now().millisecondsSinceEpoch}'));
      if (!uniqueDir.existsSync()) {
        uniqueDir.createSync(recursive: true);
      }
      final localFile = File(p.join(uniqueDir.path, fileName));
      await localFile.writeAsBytes(res.bodyBytes);
      return localFile.path;
    } catch (e) {
      debugPrint('[BstCloudService] downloadDriveFile error: $e');
      return null;
    }
  }

  /// 6.5 Google Drive 이름 기반 폴더 검색 (중복 생성 방지)
  Future<String?> findDriveFolderByName(String folderName, String parentFolderId, String token) async {
    final query = (parentFolderId == 'root' || parentFolderId.isEmpty)
        ? "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        : "name = '$folderName' and '$parentFolderId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final url = 'https://www.googleapis.com/drive/v3/files'
        '?q=${Uri.encodeComponent(query)}'
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

  /// 7. Google Drive 폴더 생성 (중복 방지 체크)
  Future<String?> createDriveFolder(String folderName, String parentFolderId, String token) async {
    final existing = await findDriveFolderByName(folderName, parentFolderId, token);
    if (existing != null) return existing;

    final url = 'https://www.googleapis.com/drive/v3/files';
    try {
      final body = json.encode({
        'name': folderName,
        'mimeType': 'application/vnd.google-apps.folder',
        'parents': [parentFolderId],
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
}


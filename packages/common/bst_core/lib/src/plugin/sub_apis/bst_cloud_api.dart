import 'dart:typed_data';

/// Google Drive, Firestore 및 교사 클라우드 동기화 브리지 API
abstract class BstCloudApi {
  /// 현재 클라우드 로그인 여부
  bool get isLoggedIn;

  /// 현재 로그인된 구글 계정 이메일
  String? get userEmail;

  /// 유효한 Google OAuth Access Token 가져오기
  Future<String?> getValidAccessToken();

  /// 교사용 Boardest 전용 클라우드 폴더 ID
  String? get boardestFolderId;

  /// 클라우드에 수업 파일 업로드
  Future<String?> uploadToCloud({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
    String? targetFolderId,
  });

  /// 클라우드 파일 다운로드
  Future<Uint8List?> downloadFromCloud(String fileId);
}

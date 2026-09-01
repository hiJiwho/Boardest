import 'dart:typed_data';

/// 플러그인 전용 격리된 로컬 스토리지 및 파일 입출력 API
abstract class BstStorageApi {
  /// Key-Value 영구 저장소 (플러그인 네임스페이스별 격리)
  Future<void> setString(String key, String value);
  String? getString(String key);

  Future<void> setBool(String key, bool value);
  bool? getBool(String key);

  Future<void> setInt(String key, int value);
  int? getInt(String key);

  Future<void> setJson(String key, Map<String, dynamic> json);
  Map<String, dynamic>? getJson(String key);

  Future<void> remove(String key);

  /// 플러그인 전용 데이터 디렉토리 경로 (Desktop)
  Future<String> getPluginDataDirectory();

  /// 플러그인 전용 로컬 파일 읽기 / 쓰기
  Future<void> writeFile(String relativePath, Uint8List bytes);
  Future<Uint8List?> readFile(String relativePath);
  Future<bool> deleteFile(String relativePath);
}

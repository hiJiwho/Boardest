/// Boardest 앱 설정 중앙 관리
/// 
/// API Key 등 민감 정보는 빌드 시 --dart-define 플래그로 주입됩니다.
/// 개발 시에는 build_dev.bat 또는 build_dev.ps1 스크립트를 사용하세요.
/// 
/// 빌드 예시:
/// flutter run --dart-define=FIREBASE_API_KEY=your_key_here
class AppConfig {
  // Firebase 설정
  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );

  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'jiwhosboardest',
  );

  static const String firebaseAppId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:287519871774:web:ee2177b6a5497ab96cef0f',
  );

  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_SENDER_ID',
    defaultValue: '287519871774',
  );

  static const String firebaseAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: 'jiwhosboardest.firebaseapp.com',
  );

  static const String firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: 'jiwhosboardest.firebasestorage.app',
  );

  /// Firestore REST API 기본 URL
  static String get firestoreBase =>
      'https://firestore.googleapis.com/v1/projects/$firebaseProjectId/databases/(default)/documents';

  /// LAN 서버 포트 (전자칠판 로컬 HTTP 서버)
  static const int lanServerPort = 7777;

  /// LAN 서버 PIN 길이
  static const int lanPinLength = 4;
}

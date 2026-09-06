import 'dart:convert';

/// Boardest 앱 설정 중앙 관리 (CI / Open Source Template)
class AppConfig {
  // Firebase 설정
  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyBMoJZHMBN4eYJtiZR2iGePcmIB7bg8wGo',
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
      'https://firestore.googleapis.com/v1/projects/\/databases/(default)/documents';

  /// Firebase Cloud Functions 기본 URL
  static const String firebaseFunctionsBase = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_BASE',
    defaultValue: 'https://us-central1-jiwhosboardest.cloudfunctions.net',
  );

  // Google OAuth Client for Drive API
  static final String googleClientIdWithDrive = const String.fromEnvironment('GOOGLE_CLIENT_ID_WITH_DRIVE');
  static final String googleClientSecretWithDrive = const String.fromEnvironment('GOOGLE_CLIENT_SECRET_WITH_DRIVE');

  static String get googleClientId => googleClientIdWithDrive;
  static String get googleClientSecret => googleClientSecretWithDrive;

  /// LAN 서버 포트 (전자칠판 로컬 HTTP 서버)
  static const int lanServerPort = 7777;

  /// LAN 서버 PIN 길이
  static const int lanPinLength = 4;
}

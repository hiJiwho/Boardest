import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class GoogleOAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        GoogleAuthProvider authProvider = GoogleAuthProvider();
        authProvider.addScope('https://www.googleapis.com/auth/drive.readonly');
        return await _auth.signInWithPopup(authProvider);
      } else {
        // 데스크톱 환경 구글 로그인은 추후 루프백 또는 전용 플러그인 연동 필요
        debugPrint('Google Sign-In is only fully supported on Web currently.');
        return null;
      }
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
    }
    return null;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}

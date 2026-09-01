import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'cloud_drive_service.dart';

/// 100% Local Loopback (http://127.0.0.1:8080) 인증 서비스
class DeepLinkService {
  static final DeepLinkService instance = DeepLinkService._internal();
  DeepLinkService._internal();

  final StreamController<Uri> _uriController = StreamController<Uri>.broadcast();
  Stream<Uri> get uriStream => _uriController.stream;

  /// 초기화 (100% 127.0.0.1 Loopback 인증 체계)
  Future<void> init(List<String> args) async {
    debugPrint('[DeepLinkService] Initialized for 100% 127.0.0.1 Local Loopback Authentication');
  }

  /// 인증 세션 수신 처리 (Loopback HTTP Server에서 호출)
  void notifyAuthReceived({
    required String token,
    String? refreshToken,
    required String email,
    required String name,
    required String school,
  }) async {
    debugPrint('[DeepLinkService] Loopback Auth Received -> email: $email, name: $name, school: $school');
    final prefs = await SharedPreferences.getInstance();

    if (token.isNotEmpty) await prefs.setString('bst_cld_access_token', token);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString('bst_cld_refresh_token', refreshToken);
    }
    if (email.isNotEmpty) await prefs.setString('bst_cld_user_email', email);
    if (name.isNotEmpty) {
      await prefs.setString('selected_teacher', name);
      await prefs.setString('selected_teacher_name', name);
    }
    if (school.isNotEmpty) await prefs.setString('selected_school_name', school);

    await CloudDriveService.instance.setSession(
      accessToken: token,
      refreshToken: refreshToken,
      email: email,
      name: name,
      school: school,
    );

    final parsedUri = Uri.parse('http://127.0.0.1:8080?token=$token&email=$email&name=$name&school=$school');
    _uriController.add(parsedUri);

    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }
}

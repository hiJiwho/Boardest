import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'passkey_native.dart';

/// Passkey & Saved Devices Service for Boardest Teacher
class PasskeyService {
  PasskeyService._();
  static final PasskeyService instance = PasskeyService._();

  static const String _rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com/passkey';
  static const String _passkeyCredentialKey = 'bst_teacher_passkey_credential_v1';

  /// 선생님 기기에 패스키 자격증명 등록 여부 확인
  Future<bool> isPasskeyRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_passkeyCredentialKey);
  }

  /// 선생님 기기에서 패스키 등록 (로컬 보안 등록 & Firebase Vault에 메타데이터 게시)
  Future<bool> registerPasskey({
    required String teacherName,
    required String email,
    required String schoolName,
    String? refreshToken,
  }) async {
    try {
      if (kIsWeb) {
        // 브라우저 순정 FIDO2 / WebAuthn 창 즉시 호출
        await PasskeyNativeHelper.triggerSystemPasskey(
          email: email,
          displayName: teacherName,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final credential = {
        'teacherName': teacherName,
        'email': email,
        'schoolName': schoolName,
        'createdAt': now,
        'registered': true,
      };
      await prefs.setString(_passkeyCredentialKey, jsonEncode(credential));

      // Firebase RTDB Vault에 등록 (검증용 공개 메타데이터)
      final cleanKey = email.replaceAll(RegExp(r'[.#$\[\]]'), '_');
      await http.patch(
        Uri.parse('$_rtdbBase/vaults/$cleanKey.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'teacherName': teacherName,
          'schoolName': schoolName,
          'hasPasskey': true,
          'updatedAt': now,
        }),
      ).timeout(const Duration(seconds: 4));

      return true;
    } catch (e) {
      debugPrint('[PasskeyService] Failed to register passkey: $e');
      return false;
    }
  }

  /// 칠판의 챌린지 세션에 패스키 승인 전송
  Future<bool> approveBoardSession({
    required String sessionId,
    required String accessToken,
    String? refreshToken,
    required String teacherName,
    required String email,
  }) async {
    try {
      final res = await http.patch(
        Uri.parse('$_rtdbBase/sessions/$sessionId.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': 'approved',
          'accessToken': accessToken,
          if (refreshToken != null) 'refreshToken': refreshToken,
          'teacherName': teacherName,
          'email': email,
          'approvedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[PasskeyService] Failed to approve board session: $e');
      return false;
    }
  }
}

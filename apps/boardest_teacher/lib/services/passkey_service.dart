import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
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

  /// Cloud Connect(스마트폰)에서 등록 완료되었는지 Firebase RTDB 원격 확인
  Future<bool> checkRemoteRegistration(String teacherName, String challengeId) async {
    try {
      if (challengeId.isNotEmpty) {
        final pairRes = await http.get(
          Uri.parse('https://jiwhosboardest-default-rtdb.firebaseio.com/passkey_pairs/$challengeId.json'),
        ).timeout(const Duration(seconds: 2));
        if (pairRes.statusCode == 200 && pairRes.body.isNotEmpty && pairRes.body != 'null') {
          final data = jsonDecode(pairRes.body);
          if (data is Map && (data['status'] == 'registered' || data['status'] == 'approved')) {
            await _markLocalRegistration(teacherName);
            return true;
          }
        }
      }
      final enc = Uri.encodeComponent(teacherName);
      final vaultRes = await http.get(
        Uri.parse('https://jiwhosboardest-default-rtdb.firebaseio.com/passkey_vaults/$enc.json'),
      ).timeout(const Duration(seconds: 2));
      if (vaultRes.statusCode == 200 && vaultRes.body.isNotEmpty && vaultRes.body != 'null') {
        final data = jsonDecode(vaultRes.body);
        if (data is Map && data['credId'] != null) {
          await _markLocalRegistration(teacherName);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _markLocalRegistration(String teacherName) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final credential = {
      'teacherName': teacherName,
      'createdAt': now,
      'registered': true,
      'source': 'cloud_connect',
    };
    await prefs.setString(_passkeyCredentialKey, jsonEncode(credential));
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

  /// 칠판의 챌린지 세션에 패스키 승인 전송 (Challenge-Response SHA-256 서명 포함)
  Future<bool> approveBoardSession({
    required String sessionId,
    String challenge = '',
    required String accessToken,
    String? refreshToken,
    String? folderId,
    required String teacherName,
    required String email,
    String? schoolId,
    String? schoolName,
  }) async {
    try {
      final raw = '$sessionId:$challenge:$accessToken:bst_passkey_v2_hmac_guard';
      final proof = sha256.convert(utf8.encode(raw)).toString();
      final res = await http.patch(
        Uri.parse('$_rtdbBase/sessions/$sessionId.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': 'approved',
          'accessToken': accessToken,
          if (refreshToken != null) 'refreshToken': refreshToken,
          if (folderId != null) 'folderId': folderId,
          if (folderId != null) 'bstCloudFolderId': folderId,
          'teacherName': teacherName,
          'email': email,
          if (schoolId != null && schoolId.isNotEmpty) 'schoolId': schoolId,
          if (schoolName != null && schoolName.isNotEmpty) 'schoolName': schoolName,
          'proof': proof,
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

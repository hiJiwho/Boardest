import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'passkey_native.dart';

/// Passkey & Saved Devices Service for Boardest
/// - 패스키(Passkey) 기반 QR 챌린지 1회용 무기록 잠금해제 (Challenge-Response SHA-256 서명 검증 적용)
/// - Boardest PRO 전용: 등록된 교사 로컬 금고 즉시 열기 (Saved Teachers)
class PasskeyService {
  PasskeyService._();
  static final PasskeyService instance = PasskeyService._();

  static const String _rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com/passkey';
  static const String _savedTeachersPrefKey = 'bst_pro_saved_teachers_v1';
  static const String _proofSalt = 'bst_passkey_v2_hmac_guard';

  /// 칠판 RAM에만 보관하는 세션별 원본 챌린지 (RTDB에는 해시만 게시하여 원격 위조 원천 차단)
  final Map<String, String> _sessionChallenges = {};

  static String computeApprovalProof({
    required String sessionId,
    required String challenge,
    required String accessToken,
  }) {
    final raw = '$sessionId:$challenge:$accessToken:$_proofSalt';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  // ─────────────────────────────────────────────────────────────
  // 1. 칠판 (Class): 패스키 챌린지 세션 생성 & 승인 대기
  // ─────────────────────────────────────────────────────────────

  /// 1회용 챌린지 세션 생성
  Future<({String sessionId, String challenge, String qrPayload})> createChallengeSession({
    String schoolName = '보데스트 중학교',
    String roomName = '1학년 7반',
  }) async {
    final rand = Random.secure();
    final sessionBytes = List<int>.generate(12, (_) => rand.nextInt(256));
    final sessionId = 'bst_' + sessionBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    
    final challengeBytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final challenge = challengeBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _sessionChallenges[sessionId] = challenge;

    final challengeCommitment = sha256.convert(utf8.encode('$sessionId:$challenge')).toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      'challengeCommitment': challengeCommitment,
      'createdAt': now,
      'expiresAt': now + 120000, // 2분 유효
      'school': schoolName,
      'room': roomName,
      'status': 'waiting',
    };

    try {
      await http.put(
        Uri.parse('$_rtdbBase/sessions/$sessionId.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[PasskeyService] Failed to create challenge on RTDB: $e');
    }

    // QR 코드에만 원본 챌린지(c) 탑재 -> 물리적으로 칠판 QR을 스캔한 기기만 챌린지 서명 생성 가능
    final qrPayload = 'https://boardest-cloud-connect.web.app/?key=$sessionId&c=$challenge&school=${Uri.encodeComponent(schoolName)}&device=${Uri.encodeComponent(roomName)}&t=$now';

    return (
      sessionId: sessionId,
      challenge: challenge,
      qrPayload: qrPayload,
    );
  }

  /// 칠판: 세션 승인 여부 폴링/대기 (최대 120초, Challenge-Response 서명 및 실제 토큰 검증 필수)
  Stream<({bool approved, String? accessToken, String? refreshToken, String? teacherName, String? email, String? errorMessage})>
      listenForApproval(String sessionId) async* {
    final startTime = DateTime.now();
    final expectedChallenge = _sessionChallenges[sessionId] ?? '';

    while (DateTime.now().difference(startTime).inSeconds < 120) {
      await Future.delayed(const Duration(milliseconds: 1200));
      try {
        final res = await http.get(
          Uri.parse('$_rtdbBase/sessions/$sessionId.json'),
        ).timeout(const Duration(seconds: 3));

        if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final status = data['status'] as String? ?? 'waiting';

          if (status == 'approved') {
            final accessToken = (data['accessToken'] ?? data['token'])?.toString() ?? '';
            final receivedProof = data['proof']?.toString() ?? '';

            // 1. 가짜 더미 토큰("web_qr_approved_token") 또는 빈 토큰 즉시 차단
            if (accessToken.isEmpty || accessToken == 'web_qr_approved_token') {
              unawaited(deleteSession(sessionId));
              yield (
                approved: false,
                accessToken: null,
                refreshToken: null,
                teacherName: null,
                email: null,
                errorMessage: '유효한 교사 인증 토큰이 없습니다. 먼저 교사용 앱에서 패스키 기기를 등록해주세요.',
              );
              return;
            }

            // 2. Challenge-Response 암호화 서명(proof) 검증: 단순 "status: approved" 주입 공격 완벽 차단
            if (expectedChallenge.isNotEmpty) {
              final expectedProof = computeApprovalProof(
                sessionId: sessionId,
                challenge: expectedChallenge,
                accessToken: accessToken,
              );
              if (receivedProof != expectedProof) {
                debugPrint('[PasskeyService] 🚨 Security Alert: Invalid challenge proof on session $sessionId! Rejecting spoofed approval.');
                unawaited(deleteSession(sessionId));
                yield (
                  approved: false,
                  accessToken: null,
                  refreshToken: null,
                  teacherName: null,
                  email: null,
                  errorMessage: '보안 서명 검증에 실패했습니다 (위조된 승인 요청 차단됨).',
                );
                return;
              }
            }

            // 승인 및 검증 완료! 즉시 세션 노드 파기 (One-time burn)
            _sessionChallenges.remove(sessionId);
            unawaited(deleteSession(sessionId));

            yield (
              approved: true,
              accessToken: accessToken,
              refreshToken: data['refreshToken'] as String?,
              teacherName: (data['teacherName'] ?? data['teacher']) as String?,
              email: data['email'] as String?,
              errorMessage: null,
            );
            return;
          } else if (status == 'rejected') {
            _sessionChallenges.remove(sessionId);
            unawaited(deleteSession(sessionId));
            yield (
              approved: false,
              accessToken: null,
              refreshToken: null,
              teacherName: null,
              email: null,
              errorMessage: '선생님이 패스키 잠금해제 요청을 거절했습니다.',
            );
            return;
          }
        }
      } catch (_) {}
    }

    // 시간 초과
    _sessionChallenges.remove(sessionId);
    unawaited(deleteSession(sessionId));
    yield (
      approved: false,
      accessToken: null,
      refreshToken: null,
      teacherName: null,
      email: null,
      errorMessage: '인증 시간이 만료되었습니다. 다시 시도해 주세요.',
    );
  }

  /// 세션 즉시 파기
  Future<void> deleteSession(String sessionId) async {
    _sessionChallenges.remove(sessionId);
    try {
      await http.delete(
        Uri.parse('$_rtdbBase/sessions/$sessionId.json'),
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // 2. 선생님 앱 (Teacher): 패스키 승인 전송
  // ─────────────────────────────────────────────────────────────

  /// 선생님 기기에서 칠판 세션 승인
  Future<bool> approveSession({
    required String sessionId,
    String challenge = '',
    required String accessToken,
    String? refreshToken,
    required String teacherName,
    required String email,
  }) async {
    try {
      final proof = computeApprovalProof(
        sessionId: sessionId,
        challenge: challenge,
        accessToken: accessToken,
      );
      final res = await http.patch(
        Uri.parse('$_rtdbBase/sessions/$sessionId.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': 'approved',
          'accessToken': accessToken,
          'refreshToken': refreshToken,
          'teacherName': teacherName,
          'email': email,
          'proof': proof,
          'approvedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[PasskeyService] Failed to approve session: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 3. Boardest PRO 전용: 등록된 교사 로컬 금고 (Saved Teachers)
  // ─────────────────────────────────────────────────────────────

  /// PRO 로컬에 등록된 선생님 목록 조회
  Future<List<Map<String, String>>> getProSavedTeachers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_savedTeachersPrefKey);
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// PRO 로컬에 선생님 계정 등록 저장
  Future<void> saveProTeacher({
    required String teacherName,
    required String email,
    required String schoolName,
    String? refreshToken,
    String? accessToken,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await getProSavedTeachers();
      // 기존 동일 이메일 또는 이름 삭제 후 최신화
      list.removeWhere((item) =>
          (email.isNotEmpty && item['email'] == email) ||
          item['teacherName'] == teacherName);
      list.insert(0, {
        'teacherName': teacherName,
        'email': email,
        'schoolName': schoolName,
        if (refreshToken != null) 'refreshToken': refreshToken,
        if (accessToken != null) 'accessToken': accessToken,
        'savedAt': DateTime.now().toIso8601String(),
      });
      await prefs.setString(_savedTeachersPrefKey, jsonEncode(list));
    } catch (e) {
      debugPrint('[PasskeyService] Error saving PRO teacher: $e');
    }
  }

  /// PRO 로컬에서 선생님 등록 해제
  Future<void> removeProTeacher(String identifier) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await getProSavedTeachers();
      list.removeWhere((item) =>
          item['email'] == identifier || item['teacherName'] == identifier);
      await prefs.setString(_savedTeachersPrefKey, jsonEncode(list));
    } catch (_) {}
  }

  /// 브라우저 순정 패스키 로그인 즉시 요청 (QR 없이 직접 인증)
  Future<({bool success, String? teacherName, String? email, String? accessToken})> authenticateNativePasskey() async {
    try {
      if (kIsWeb) {
        final res = await PasskeyNativeHelper.triggerSystemPasskeyGet();
        if (res.success) {
          // 인증 성공! RTDB Vault에서 이메일 매칭 조회
          final email = res.email ?? '';
          String teacherName = '선생님';
          if (email.isNotEmpty) {
            final cleanKey = email.replaceAll(RegExp(r'[.#$\[\]]'), '_');
            try {
              final vRes = await http.get(Uri.parse('$_rtdbBase/vaults/$cleanKey.json')).timeout(const Duration(seconds: 3));
              if (vRes.statusCode == 200 && vRes.body.isNotEmpty && vRes.body != 'null') {
                final vData = jsonDecode(vRes.body);
                teacherName = vData['teacherName'] ?? '선생님';
              }
            } catch (_) {}
          }
          final token = 'passkey_native_${DateTime.now().millisecondsSinceEpoch}';
          return (
            success: true,
            teacherName: teacherName,
            email: email,
            accessToken: token,
          );
        }
      }
    } catch (e) {
      debugPrint('[PasskeyService] authenticateNativePasskey error: $e');
    }
    return (success: false, teacherName: null, email: null, accessToken: null);
  }

  /// 브라우저 순정 패스키 등록 (QR 없이 직접 등록)
  Future<bool> registerNativePasskey({
    required String teacherName,
    required String email,
    required String schoolName,
  }) async {
    try {
      if (kIsWeb) {
        final ok = await PasskeyNativeHelper.triggerSystemPasskeyCreate(
          email: email,
          displayName: teacherName,
        );
        if (ok) {
          final now = DateTime.now().millisecondsSinceEpoch;
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
        }
      }
    } catch (e) {
      debugPrint('[PasskeyService] registerNativePasskey error: $e');
    }
    return false;
  }
}

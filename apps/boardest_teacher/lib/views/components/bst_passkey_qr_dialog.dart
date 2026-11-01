import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/cloud_drive_service.dart';
import '../../services/passkey_service.dart';

/// 교실 전자칠판 / 모바일 스마트폰 패스키(Passkey) QR 등록 다이얼로그
class BstPasskeyQrDialog extends StatefulWidget {
  final String teacherName;
  final String schoolName;
  final String homeroomClass;
  final VoidCallback onRegistered;

  const BstPasskeyQrDialog({
    super.key,
    required this.teacherName,
    required this.schoolName,
    required this.homeroomClass,
    required this.onRegistered,
  });

  static Future<void> show(
    BuildContext context, {
    required String teacherName,
    required String schoolName,
    required String homeroomClass,
    required VoidCallback onRegistered,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BstPasskeyQrDialog(
        teacherName: teacherName,
        schoolName: schoolName,
        homeroomClass: homeroomClass,
        onRegistered: onRegistered,
      ),
    );
  }

  @override
  State<BstPasskeyQrDialog> createState() => _BstPasskeyQrDialogState();
}

class _BstPasskeyQrDialogState extends State<BstPasskeyQrDialog> {
  late String _challengeId;
  late String _registrationUrl;
  bool _isSuccess = false;
  bool _isExpired = false;
  int _remainingSeconds = 120; // 2분 유효시간 제한
  Timer? _countdownTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startRegistrationSession();
  }

  void _startRegistrationSession() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();

    final now = DateTime.now().millisecondsSinceEpoch;
    _challengeId = 'PASSKEY-${now.toString().substring(5)}';
    _remainingSeconds = 120;
    _isExpired = false;

    final token = CloudDriveService.instance.accessToken ?? '';
    final refreshToken = CloudDriveService.instance.refreshToken ?? '';
    final folderId = CloudDriveService.instance.bstSaveFolderId ?? CloudDriveService.instance.boardestFolderId ?? '';
    final email = CloudDriveService.instance.userEmail ?? '';

    final encToken = token.isNotEmpty ? '&token=${Uri.encodeComponent(token)}' : '';
    final encRefresh = refreshToken.isNotEmpty ? '&refreshToken=${Uri.encodeComponent(refreshToken)}' : '';
    final encFolder = folderId.isNotEmpty ? '&folderId=${Uri.encodeComponent(folderId)}' : '';
    final encEmail = email.isNotEmpty ? '&email=${Uri.encodeComponent(email)}' : '';

    // Boardest Cloud Connect 등록 주소 (클라우드 연동 전용, 2분 유효 파라미터 및 인증 토큰 포함)
    final encTeacher = Uri.encodeComponent(widget.teacherName);
    final encSchool = Uri.encodeComponent(widget.schoolName);
    final encDevice = Uri.encodeComponent(widget.homeroomClass);
    _registrationUrl = 'https://boardest-cloud-connect.web.app/?action=register&key=$_challengeId&teacher=$encTeacher&school=$encSchool&device=$encDevice&t=$now$encToken$encRefresh$encFolder$encEmail';

    if (token.isNotEmpty || refreshToken.isNotEmpty) {
      final vaultPayload = jsonEncode({
        'credId': 'passkey_qr',
        'teacher': widget.teacherName,
        'teacherName': widget.teacherName,
        'token': token,
        'accessToken': token,
        'refreshToken': refreshToken,
        'folderId': folderId,
        'bstCloudFolderId': folderId,
        'email': email,
        'updatedAt': now,
      });
      http.put(
        Uri.parse('https://jiwhosboardest-default-rtdb.firebaseio.com/passkey/vaults/$encTeacher.json'),
        headers: {'Content-Type': 'application/json'},
        body: vaultPayload,
      ).ignore();
      http.put(
        Uri.parse('https://jiwhosboardest-default-rtdb.firebaseio.com/passkey_vaults/$encTeacher.json'),
        headers: {'Content-Type': 'application/json'},
        body: vaultPayload,
      ).ignore();
      CloudDriveService.instance.syncTeacherCloudTokenToFirestore(force: true).ignore();
    }

    // 1초 카운트다운 타이머 (2분 시간제한)
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        t.cancel();
        _pollTimer?.cancel();
        setState(() => _isExpired = true);
      }
    });

    // 2초 간격 RTDB 및 Cloud 등록 완료 폴링
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      final isLocal = await PasskeyService.instance.isPasskeyRegistered();
      final isRemote = !isLocal && await PasskeyService.instance.checkRemoteRegistration(widget.teacherName, _challengeId);
      if ((isLocal || isRemote) && mounted && !_isSuccess) {
        setState(() => _isSuccess = true);
        _countdownTimer?.cancel();
        _pollTimer?.cancel();
        widget.onRegistered();
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1220),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00F5D4).withOpacity(0.12),
              blurRadius: 30,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.7),
              blurRadius: 24,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. 헤더 타이틀
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF00F5D4), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'QR 패스키(Passkey) 등록',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${widget.schoolName} · ${widget.teacherName} 선생님',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 2. QR 코드 카드 (2분 유효시간 만료 처리)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: _isExpired ? 0.15 : 1.0,
                    child: QrImageView(
                      data: _registrationUrl,
                      version: QrVersions.auto,
                      size: 210.0,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0D1220),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF0D1220),
                      ),
                    ),
                  ),
                  if (_isExpired)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_off_rounded, color: Colors.redAccent, size: 40),
                        const SizedBox(height: 8),
                        const Text(
                          '2분 유효시간 만료',
                          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '보안을 위해 QR이 무효화되었습니다',
                          style: TextStyle(color: Colors.black54, fontSize: 11),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _startRegistrationSession,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('QR 코드 재발급'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D1220),
                            foregroundColor: const Color(0xFF00F5D4),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 3. 안내 텍스트 및 2분 카운트다운 타이머
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _isExpired ? Colors.redAccent.withOpacity(0.1) : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _isExpired ? Colors.redAccent.withOpacity(0.3) : Colors.white10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isExpired ? Icons.lock_clock_rounded : Icons.timer_outlined,
                    color: _isExpired ? Colors.redAccent : const Color(0xFF00F5D4),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isExpired
                        ? '유효시간 만료 (재발급 필요)'
                        : '⏱️ 남은 유효시간: ${_remainingSeconds ~/ 60}분 ${(_remainingSeconds % 60).toString().padLeft(2, '0')}초',
                    style: TextStyle(
                      color: _isExpired ? Colors.redAccent : Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            Text(
              'Boardest Cloud Connect · 스마트폰 패스키 등록 허브',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),

            const SizedBox(height: 20),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 16),

            // 4. 하단 액션 버튼 (순정 패스키 로컬 버튼 제거 완료)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('닫기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

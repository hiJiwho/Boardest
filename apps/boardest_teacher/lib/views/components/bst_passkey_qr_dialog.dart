import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
  bool _isRegisteringLocally = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().millisecondsSinceEpoch;
    _challengeId = 'PASSKEY-${now.toString().substring(5)}';
    
    // FIDO2 / W3C WebAuthn 국제 규격 모바일 등록 주소 (아이폰 Face ID / 안드로이드 지문 순정 등록)
    final encTeacher = Uri.encodeComponent(widget.teacherName);
    final encSchool = Uri.encodeComponent(widget.schoolName);
    final encEmail = Uri.encodeComponent('${widget.teacherName.toLowerCase()}@school.go.kr');
    _registrationUrl = 'https://boardest-teacher.web.app/passkey.html?challenge=$_challengeId&teacher=$encTeacher&school=$encSchool&email=$encEmail';

    // 2초 간격 등록 완료 폴링 (시뮬레이션 및 실제 서비스 연동)
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      final isReg = await PasskeyService.instance.isPasskeyRegistered();
      if (isReg && mounted && !_isSuccess) {
        setState(() => _isSuccess = true);
        widget.onRegistered();
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });

    // 스마트폰 카메라로 QR 코드를 스캔하여 폰에 직접 패스키를 저장하도록 대기합니다.
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _registerLocally() async {
    setState(() => _isRegisteringLocally = true);
    final ok = await PasskeyService.instance.registerPasskey(
      teacherName: widget.teacherName,
      email: '${widget.teacherName.toLowerCase()}@school.go.kr',
      schoolName: widget.schoolName,
    );
    if (mounted) {
      setState(() {
        _isRegisteringLocally = false;
        _isSuccess = ok;
      });
      if (ok) {
        widget.onRegistered();
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
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

            // 2. QR 코드 카드
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

            const SizedBox(height: 16),

            // 3. 안내 텍스트
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_user_rounded, color: Color(0xFF00F5D4), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '아이폰(Face ID) · 안드로이드(지문) 순정 패스키 규격',
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            Text(
              'FIDO2 / WebAuthn 국제 표준 · 유효시간 3분',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),

            const SizedBox(height: 20),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 16),

            // 4. 하단 액션 버튼
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('닫기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isSuccess ? const Color(0xFF10B981) : const Color(0xFF00F5D4),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isRegisteringLocally ? null : _registerLocally,
                    child: _isRegisteringLocally
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                          )
                        : Text(
                            _isSuccess ? '✓ 등록 완료됨' : '🔐 순정 시스템 패스키 호출',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

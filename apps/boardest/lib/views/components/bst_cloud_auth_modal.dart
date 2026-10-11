import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/passkey_service.dart';
import '../../services/bst_cloud_service.dart';

/// Boardest Cloud 통합 인증 모달
/// 1. 📱 모바일 Web QR (기본값: 스마트폰 카메라로 스캔하여 웹에서 1초 원터치 승인)
/// 2. 🔢 6자리 Stegano OTP (부활: 무선랜/블루투스 없는 데스크톱 & 구형 칠판 100% 호환)
/// 3. 🔑 순정 패스키 (선택: boardest-cloud.web.app 연동 FIDO2 생체인증)
class BstCloudAuthModal extends StatefulWidget {
  final double scale;
  final String schoolName;
  final String gradeClass;
  final VoidCallback onUnlocked;

  const BstCloudAuthModal({
    super.key,
    required this.scale,
    this.schoolName = '보데스트 중학교',
    this.gradeClass = '1학년 7반',
    required this.onUnlocked,
  });

  static Future<void> show(
    BuildContext context, {
    double scale = 1.0,
    String schoolName = '보데스트 중학교',
    String gradeClass = '1학년 7반',
    required VoidCallback onUnlocked,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BstCloudAuthModal(
        scale: scale,
        schoolName: schoolName,
        gradeClass: gradeClass,
        onUnlocked: onUnlocked,
      ),
    );
  }

  @override
  State<BstCloudAuthModal> createState() => _BstCloudAuthModalState();
}

class _BstCloudAuthModalState extends State<BstCloudAuthModal> {
  // 0: 모바일 Web QR (기본값), 1: 6자리 OTP, 2: 순정 패스키
  int _selectedTab = 0;

  // Web QR 세션 상태
  String? _sessionId;
  String? _qrPayload;
  bool _isLoadingSession = true;
  bool _isApproved = false;
  String? _errorMsg;
  StreamSubscription? _approvalSubscription;

  // 6자리 OTP 상태
  String _enteredOtp = '';
  bool _isVerifyingOtp = false;
  bool _saveOtpToDevice = false;
  String? _otpError;

  @override
  void initState() {
    super.initState();
    _startQrSession();
  }

  @override
  void dispose() {
    _approvalSubscription?.cancel();
    if (_sessionId != null) {
      PasskeyService.instance.deleteSession(_sessionId!);
    }
    super.dispose();
  }

  Future<void> _startQrSession() async {
    setState(() {
      _isLoadingSession = true;
      _errorMsg = null;
      _isApproved = false;
    });

    try {
      final res = await PasskeyService.instance.createChallengeSession(
        schoolName: widget.schoolName,
        roomName: widget.gradeClass,
      );

      if (!mounted) return;
      setState(() {
        _sessionId = res.sessionId;
        _qrPayload = res.qrPayload;
        _isLoadingSession = false;
      });

      _approvalSubscription?.cancel();
      _approvalSubscription = PasskeyService.instance
          .listenForApproval(res.sessionId)
          .listen((event) async {
        if (!mounted) return;
        if (event.approved && event.accessToken != null) {
          setState(() {
            _isApproved = true;
          });

          // Cloud 토큰 활성화 (기기 영구 저장하지 않고 현재 칠판 세션 RAM에만 보관)
          BstCloudService.instance.setDirectAccessToken(
            event.accessToken!,
            teacherName: event.teacherName ?? '선생님',
            ownerEmail: event.email ?? '',
          );

          await Future.delayed(const Duration(milliseconds: 700));
          if (mounted) {
            Navigator.of(context).pop();
            widget.onUnlocked();
          }
        } else if (event.errorMessage != null) {
          setState(() {
            _errorMsg = event.errorMessage;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSession = false;
          _errorMsg = 'QR 세션 연결에 실패했습니다: $e';
        });
      }
    }
  }

  // ─── 6자리 OTP 검증 ───
  Future<void> _submitOtp() async {
    if (_enteredOtp.length < 6 || _isVerifyingOtp) return;
    setState(() {
      _isVerifyingOtp = true;
      _otpError = null;
    });

    try {
      final res = await BstCloudService.instance.verify6DigitSteganoOtp(_enteredOtp);
      if (!mounted) return;

      if (res.success && res.accessToken != null) {
        BstCloudService.instance.setDirectAccessToken(
          res.accessToken!,
          teacherName: res.teacherName ?? '선생님',
          ownerEmail: res.email ?? '',
        );

        if (!kIsWeb && _saveOtpToDevice && res.teacherName != null) {
          await PasskeyService.instance.saveProTeacher(
            teacherName: res.teacherName!,
            email: res.email ?? '',
            schoolName: widget.schoolName,
            accessToken: res.accessToken,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 ${res.teacherName ?? "선생님"}의 Cloud 수업자료가 연결되었습니다!'),
            backgroundColor: const Color(0xFF00F5D4),
          ),
        );

        Navigator.of(context).pop();
        widget.onUnlocked();
      } else {
        setState(() {
          _isVerifyingOtp = false;
          _otpError = res.errorMessage ?? 'OTP 인증에 실패했습니다. 번호를 확인해주세요.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifyingOtp = false;
          _otpError = '인증 오류: $e';
        });
      }
    }
  }

  void _onKeypadPress(String key) {
    if (_isVerifyingOtp) return;
    setState(() {
      _otpError = null;
      if (key == 'C') {
        _enteredOtp = '';
      } else if (key == '⌫') {
        if (_enteredOtp.isNotEmpty) {
          _enteredOtp = _enteredOtp.substring(0, _enteredOtp.length - 1);
        }
      } else {
        if (_enteredOtp.length < 6) {
          _enteredOtp += key;
          if (_enteredOtp.length == 6) {
            _submitOtp();
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale.clamp(0.85, 1.3);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 680 * s,
        constraints: BoxConstraints(maxHeight: 640 * s),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24 * s),
          border: Border.all(
            color: const Color(0xFF00F5D4).withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.75),
              blurRadius: 36,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: const Color(0xFF00F5D4).withValues(alpha: 0.12),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 모달 상단 헤더
            Padding(
              padding: EdgeInsets.fromLTRB(24 * s, 20 * s, 20 * s, 12 * s),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12 * s),
                    ),
                    child: Icon(
                      Icons.cloud_sync_rounded,
                      color: const Color(0xFF00F5D4),
                      size: 24 * s,
                    ),
                  ),
                  SizedBox(width: 12 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BOARDEST Cloud 수업 연결',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 20 * s,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${widget.schoolName} • ${widget.gradeClass}',
                          style: GoogleFonts.notoSansKr(
                            color: const Color(0xFF94A3B8),
                            fontSize: 12 * s,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: Colors.white70, size: 24 * s),
                  ),
                ],
              ),
            ),

            // 2. 탭 바 (3원화: 1. Web QR, 2. 6자리 OTP, 3. 순정 Passkey)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24 * s),
              child: Container(
                padding: EdgeInsets.all(4 * s),
                decoration: BoxDecoration(
                  color: const Color(0xFF070B14),
                  borderRadius: BorderRadius.circular(14 * s),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    _buildTabItem(0, '📱 모바일 Web QR', '1초 즉시 승인 (권장)', s),
                    _buildTabItem(1, '🔢 6자리 OTP', '구형칠판/데스크톱 100% 호환', s),
                    _buildTabItem(2, '🔑 순정 패스키', 'boardest-cloud 연동', s),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16 * s),

            // 3. 탭 본문 영역
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24 * s, 0, 24 * s, 20 * s),
                child: IndexedStack(
                  index: _selectedTab,
                  children: [
                    _buildWebQrTab(s),
                    _buildOtpKeypadTab(s),
                    _buildPasskeyTab(s),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String title, String subtitle, double s) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTab = index;
          });
          if (index == 0 && _sessionId == null) {
            _startQrSession();
          }
        },
        borderRadius: BorderRadius.circular(10 * s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 8 * s, horizontal: 8 * s),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00F5D4).withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10 * s),
            border: Border.all(
              color: isSelected ? const Color(0xFF00F5D4) : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.notoSansKr(
                  color: isSelected ? const Color(0xFF00F5D4) : Colors.white70,
                  fontSize: 13 * s,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 2 * s),
              Text(
                subtitle,
                style: GoogleFonts.notoSansKr(
                  color: isSelected ? const Color(0xFF2EC4B6) : const Color(0xFF64748B),
                  fontSize: 9.5 * s,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Tab 0: 모바일 Web QR ───
  Widget _buildWebQrTab(double s) {
    if (_isApproved) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 68),
            SizedBox(height: 16 * s),
            Text(
              '교실 전자칠판 잠금해제 완료!',
              style: GoogleFonts.notoSansKr(
                fontSize: 20 * s,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF10B981),
              ),
            ),
            SizedBox(height: 6 * s),
            Text(
              '선생님의 Cloud 수업 자료를 바로 불러옵니다...',
              style: GoogleFonts.notoSansKr(fontSize: 13 * s, color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // QR 코드 영역
        Container(
          width: 210 * s,
          height: 210 * s,
          padding: EdgeInsets.all(12 * s),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20 * s),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
              ),
            ],
          ),
          child: _isLoadingSession || _qrPayload == null
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF0F172A)),
                )
              : QrImageView(
                  data: _qrPayload!,
                  version: QrVersions.auto,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0F172A),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF0F172A),
                  ),
                ),
        ),

        SizedBox(width: 24 * s),

        // 안내문 및 상태
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20 * s),
                  border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flash_on_rounded, size: 13, color: Color(0xFF00F5D4)),
                    SizedBox(width: 4 * s),
                    Text(
                      '스마트폰 기본 카메라로 비추세요',
                      style: TextStyle(
                        fontSize: 11 * s,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF00F5D4),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12 * s),
              Text(
                '스마트폰 카메라로\nQR 코드를 비추어 로그인',
                style: GoogleFonts.notoSansKr(
                  fontSize: 18 * s,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.35,
                ),
              ),
              SizedBox(height: 8 * s),
              Text(
                '1. 스마트폰 기본 카메라로 QR을 스캔합니다.\n2. 브라우저에서 [즉시 승인]을 1초 터치합니다.\n3. 칠판에서 수업 자료가 바로 열립니다.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 12 * s,
                  color: const Color(0xFF94A3B8),
                  height: 1.5,
                ),
              ),
              if (_errorMsg != null) ...[
                SizedBox(height: 10 * s),
                Text(
                  _errorMsg!,
                  style: const TextStyle(color: Color(0xFFEF4565), fontSize: 11.5),
                ),
              ],
              SizedBox(height: 14 * s),
              OutlinedButton.icon(
                onPressed: _startQrSession,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('새 QR 생성'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00F5D4),
                  side: const BorderSide(color: Color(0xFF00F5D4)),
                  padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 8 * s),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * s)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Tab 1: 6자리 OTP (3x4 키패드) ───
  Widget _buildOtpKeypadTab(double s) {
    return Row(
      children: [
        // 좌측: 입력란 & 상태
        Expanded(
          flex: 11,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '선생님 6자리 안심 OTP 입력',
                style: GoogleFonts.notoSansKr(
                  fontSize: 18 * s,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 6 * s),
              Text(
                '무선랜/블루투스가 없는 교실 PC 및 구형 칠판에서도\nTeacher 앱의 6자리 OTP를 입력하여 즉시 구동됩니다.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11.5 * s,
                  color: const Color(0xFF94A3B8),
                  height: 1.4,
                ),
              ),
              SizedBox(height: 20 * s),

              // 6자리 핀 박스
              Row(
                children: List.generate(6, (i) {
                  final hasDigit = i < _enteredOtp.length;
                  return Expanded(
                    child: Container(
                      height: 52 * s,
                      margin: EdgeInsets.symmetric(horizontal: 3 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF070B14),
                        borderRadius: BorderRadius.circular(10 * s),
                        border: Border.all(
                          color: hasDigit
                              ? const Color(0xFF00F5D4)
                              : Colors.white.withValues(alpha: 0.15),
                          width: hasDigit ? 2 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        hasDigit ? _enteredOtp[i] : '•',
                        style: GoogleFonts.outfit(
                          fontSize: hasDigit ? 24 * s : 18 * s,
                          fontWeight: FontWeight.w900,
                          color: hasDigit ? const Color(0xFF00F5D4) : Colors.white24,
                        ),
                      ),
                    ),
                  );
                }),
              ),

              if (_otpError != null) ...[
                SizedBox(height: 10 * s),
                Text(
                  _otpError!,
                  style: const TextStyle(color: Color(0xFFEF4565), fontSize: 12),
                ),
              ],

              if (!kIsWeb) ...[
                SizedBox(height: 10 * s),
                Row(
                  children: [
                    Checkbox(
                      value: _saveOtpToDevice,
                      activeColor: const Color(0xFF00F5D4),
                      checkColor: Colors.black,
                      onChanged: (val) async {
                        if (val == true) {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF0F172A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16 * s),
                                side: const BorderSide(color: Color(0xFFEF4565), width: 1.5),
                              ),
                              title: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4565), size: 28),
                                  const SizedBox(width: 8),
                                  Text(
                                    '⚠️ 보안 취약 경고',
                                    style: GoogleFonts.notoSansKr(
                                      color: const Color(0xFFEF4565),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16 * s,
                                    ),
                                  ),
                                ],
                              ),
                              content: Text(
                                '공용 전자칠판에 계정을 영구 저장하면 다른 사람이나 학생이 교사 계정에 접근할 수 있어 보안이 취약해집니다.\n\n정말로 이 기기에 계정을 영구 저장하시겠습니까?',
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white70,
                                  fontSize: 13 * s,
                                  height: 1.5,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(
                                    '취소 (RAM에만 임시 유지)',
                                    style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2)),
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFEF4565),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(
                                    '동의하고 영구 등록',
                                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            setState(() => _saveOtpToDevice = true);
                          }
                        } else {
                          setState(() => _saveOtpToDevice = false);
                        }
                      },
                    ),
                    Expanded(
                      child: Text(
                        '이 전자칠판에 계정 영구 등록 (보안 주의)',
                        style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 11 * s),
                      ),
                    ),
                  ],
                ),
              ],

              SizedBox(height: 16 * s),
              ElevatedButton(
                onPressed: _enteredOtp.length == 6 && !_isVerifyingOtp ? _submitOtp : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F5D4),
                  foregroundColor: const Color(0xFF0F172A),
                  padding: EdgeInsets.symmetric(vertical: 14 * s, horizontal: 24 * s),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * s)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isVerifyingOtp) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(width: 8),
                      const Text('검증 중...', style: TextStyle(fontWeight: FontWeight.bold)),
                    ] else ...[
                      const Icon(Icons.lock_open_rounded, size: 18),
                      const SizedBox(width: 8),
                      const Text('6자리 OTP로 즉시 로그인', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        SizedBox(width: 24 * s),

        // 우측: 3x4 키패드
        Expanded(
          flex: 9,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildKeypadRow(['1', '2', '3'], s),
              SizedBox(height: 8 * s),
              _buildKeypadRow(['4', '5', '6'], s),
              SizedBox(height: 8 * s),
              _buildKeypadRow(['7', '8', '9'], s),
              SizedBox(height: 8 * s),
              _buildKeypadRow(['C', '0', '⌫'], s),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeypadRow(List<String> keys, double s) {
    return Row(
      children: keys.map((key) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4 * s),
            child: InkWell(
              onTap: () => _onKeypadPress(key),
              borderRadius: BorderRadius.circular(10 * s),
              child: Container(
                height: 48 * s,
                decoration: BoxDecoration(
                  color: key == 'C' || key == '⌫'
                      ? const Color(0xFF1E293B)
                      : const Color(0xFF070B14),
                  borderRadius: BorderRadius.circular(10 * s),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                alignment: Alignment.center,
                child: Text(
                  key,
                  style: GoogleFonts.outfit(
                    fontSize: 20 * s,
                    fontWeight: FontWeight.bold,
                    color: key == 'C'
                        ? const Color(0xFFEF4565)
                        : (key == '⌫' ? const Color(0xFFFFB703) : Colors.white),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Tab 2: 순정 패스키 ───
  Widget _buildPasskeyTab(double s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(16 * s),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
            ),
            child: Icon(Icons.fingerprint_rounded, size: 54 * s, color: const Color(0xFF00F5D4)),
          ),
          SizedBox(height: 16 * s),
          Text(
            'boardest-cloud.web.app 순정 패스키',
            style: GoogleFonts.notoSansKr(
              fontSize: 18 * s,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8 * s),
          Text(
            'FIDO2 / WebAuthn 지원 브라우저 및 기기에서 사용 가능합니다.\n보안을 위해 칠판에 자격증명을 영구 저장하지 않고 스마트폰 생체인식으로 안전하게 인증합니다.',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
              fontSize: 12 * s,
              color: const Color(0xFF94A3B8),
              height: 1.5,
            ),
          ),
          SizedBox(height: 20 * s),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _selectedTab = 0; // QR 탭으로 전환하여 스마트폰에서 바로 패스키 발동
              });
            },
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('스마트폰으로 패스키 인증하기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: const Color(0xFF0F172A),
              padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 12 * s),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * s)),
            ),
          ),
        ],
      ),
    );
  }
}

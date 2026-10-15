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
  // 0: 모바일 Web QR (기본값), 1: 6자리 OTP, 2: 이미 등록한 교사, 3: 순정 패스키
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
  bool _saveOtpToDevice = true;
  String? _otpError;

  // 등록된 교사 목록
  List<Map<String, String>> _savedTeachers = [];
  bool _isLoadingSavedTeachers = false;

  @override
  void initState() {
    super.initState();
    _startQrSession();
    _loadSavedTeachers();
  }

  Future<void> _loadSavedTeachers() async {
    setState(() => _isLoadingSavedTeachers = true);
    final list = await PasskeyService.instance.getProSavedTeachers();
    if (mounted) {
      setState(() {
        _savedTeachers = list;
        _isLoadingSavedTeachers = false;
      });
    }
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

          // Cloud 토큰 활성화
          BstCloudService.instance.setDirectAccessToken(
            event.accessToken!,
            teacherName: event.teacherName ?? '선생님',
            ownerEmail: event.email ?? '',
          );

          // 등록된 교사로 자동 등록 저장 (Web, Windows, Android 공통)
          await PasskeyService.instance.saveProTeacher(
            teacherName: event.teacherName ?? '선생님',
            email: event.email ?? '',
            schoolName: widget.schoolName,
            accessToken: event.accessToken,
            refreshToken: event.refreshToken,
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

        if (_saveOtpToDevice && res.teacherName != null) {
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

            // 2. 탭 바 (3원화: 1. Web QR, 2. 6자리 OTP, 3. 등록된 교사)
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
                    _buildTabItem(0, '📱 Web QR', '1초 즉시 승인', s),
                    _buildTabItem(1, '🔢 6자리 OTP', '구형칠판 호환', s),
                    _buildTabItem(2, '👨‍🏫 등록된 교사', '원클릭 연동', s),
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
                    _buildSavedTeachersTab(s),
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

  // ─── Tab 2: 등록된 교사 (Saved Teachers) ───
  Widget _buildSavedTeachersTab(double s) {
    if (_isLoadingSavedTeachers) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)));
    }
    if (_savedTeachers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off_rounded, size: 44 * s, color: Colors.white38),
            SizedBox(height: 10 * s),
            Text(
              '이 기기에 등록된 교사가 없습니다.',
              style: GoogleFonts.notoSansKr(
                fontSize: 15 * s,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            SizedBox(height: 6 * s),
            Text(
              '모바일 Web QR 또는 6자리 OTP 인증 시 자동 등록되거나,\n아래 버튼을 눌러 교사를 직접 등록할 수 있습니다.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 11.5 * s,
                color: const Color(0xFF94A3B8),
                height: 1.4,
              ),
            ),
            SizedBox(height: 14 * s),
            ElevatedButton.icon(
              onPressed: () => _showAddTeacherDialog(s),
              icon: Icon(Icons.person_add_alt_1_rounded, size: 16 * s),
              label: Text('+ 새 교사 직접 등록', style: GoogleFonts.notoSansKr(fontSize: 12 * s, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F5D4),
                foregroundColor: const Color(0xFF0F172A),
                padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 10 * s),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * s)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 12 * s),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '등록된 교사 (${_savedTeachers.length}명)',
                style: GoogleFonts.notoSansKr(
                  color: const Color(0xFF00F5D4),
                  fontSize: 14 * s,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Text(
                    '원클릭 연동',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white54,
                      fontSize: 11 * s,
                    ),
                  ),
                  SizedBox(width: 8 * s),
                  ElevatedButton.icon(
                    onPressed: () => _showAddTeacherDialog(s),
                    icon: Icon(Icons.person_add_alt_1_rounded, size: 13 * s),
                    label: Text('+ 교사 등록', style: GoogleFonts.notoSansKr(fontSize: 10.5 * s, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F5D4),
                      foregroundColor: const Color(0xFF0F172A),
                      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6 * s)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _savedTeachers.length,
            separatorBuilder: (_, __) => SizedBox(height: 8 * s),
            itemBuilder: (ctx, idx) {
              final t = _savedTeachers[idx];
              final name = t['teacherName'] ?? '선생님';
              final email = t['email'] ?? '';
              final school = t['schoolName'] ?? '';
              final token = t['accessToken'] ?? 'saved_token_$name';

              return Container(
                padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
                decoration: BoxDecoration(
                  color: const Color(0xFF070B14),
                  borderRadius: BorderRadius.circular(12 * s),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20 * s,
                      backgroundColor: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                      child: Text(
                        name.isNotEmpty ? name.substring(0, 1) : '교',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF00F5D4),
                          fontWeight: FontWeight.bold,
                          fontSize: 16 * s,
                        ),
                      ),
                    ),
                    SizedBox(width: 14 * s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white,
                              fontSize: 15 * s,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (school.isNotEmpty || email.isNotEmpty)
                            Text(
                              [school, email].where((e) => e.isNotEmpty).join(' • '),
                              style: GoogleFonts.notoSansKr(
                                color: const Color(0xFF94A3B8),
                                fontSize: 11 * s,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        BstCloudService.instance.setDirectAccessToken(
                          token,
                          teacherName: name,
                          ownerEmail: email,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('🎉 $name의 Cloud 수업자료가 연결되었습니다!'),
                            backgroundColor: const Color(0xFF00F5D4),
                          ),
                        );
                        Navigator.of(context).pop();
                        widget.onUnlocked();
                      },
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('연결'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00F5D4),
                        foregroundColor: const Color(0xFF0F172A),
                        padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 8 * s),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * s)),
                      ),
                    ),
                    SizedBox(width: 6 * s),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, size: 18 * s, color: Colors.white38),
                      tooltip: '등록 해제',
                      onPressed: () async {
                        await PasskeyService.instance.removeProTeacher(email);
                        _loadSavedTeachers();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showAddTeacherDialog(double s) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16 * s),
          side: const BorderSide(color: Color(0xFF00F5D4), width: 1.2),
        ),
        title: Row(
          children: [
            Icon(Icons.person_add_alt_1_rounded, color: const Color(0xFF00F5D4), size: 20 * s),
            SizedBox(width: 8 * s),
            Text('새 교사 등록', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('이 전자칠판에 등록할 선생님 성함을 입력해주세요.', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * s)),
            SizedBox(height: 12 * s),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * s),
              decoration: InputDecoration(
                labelText: '선생님 성함 (예: 김교사)',
                labelStyle: TextStyle(color: const Color(0xFF00F5D4), fontSize: 12 * s),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * s), borderSide: const BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * s), borderSide: const BorderSide(color: Color(0xFF00F5D4))),
                filled: true,
                fillColor: Colors.black26,
              ),
            ),
            SizedBox(height: 10 * s),
            TextField(
              controller: emailCtrl,
              style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * s),
              decoration: InputDecoration(
                labelText: '학교 구글 이메일 (선택)',
                labelStyle: TextStyle(color: Colors.white60, fontSize: 12 * s),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * s), borderSide: const BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * s), borderSide: const BorderSide(color: Color(0xFF00F5D4))),
                filled: true,
                fillColor: Colors.black26,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: TextStyle(color: Colors.white38, fontSize: 12 * s)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final email = emailCtrl.text.trim();
              await PasskeyService.instance.saveProTeacher(
                teacherName: name,
                email: email,
                schoolName: widget.schoolName,
                accessToken: 'registered_teacher_${DateTime.now().millisecondsSinceEpoch}',
              );
              if (mounted) {
                Navigator.pop(ctx);
                await _loadSavedTeachers();
                setState(() => _selectedTab = 2);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🎉 [$name] 선생님이 등록 교사로 추가되었습니다!'),
                    backgroundColor: const Color(0xFF00F5D4),
                  ),
                );
              }
            },
            child: Text('등록하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12 * s)),
          ),
        ],
      ),
    );
  }
}


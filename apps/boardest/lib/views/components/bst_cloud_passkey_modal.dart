import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/passkey_service.dart';
import '../../services/bst_cloud_service.dart';

class BstCloudPasskeyModal extends StatefulWidget {
  final double scale;
  final String schoolName;
  final String gradeClass;
  final VoidCallback onUnlocked;

  const BstCloudPasskeyModal({
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
      builder: (ctx) => BstCloudPasskeyModal(
        scale: scale,
        schoolName: schoolName,
        gradeClass: gradeClass,
        onUnlocked: onUnlocked,
      ),
    );
  }

  @override
  State<BstCloudPasskeyModal> createState() => _BstCloudPasskeyModalState();
}

class _BstCloudPasskeyModalState extends State<BstCloudPasskeyModal> {
  int _selectedTab = 0; // 0: 패스키 잠금해제 (QR), 1: 등록된 선생님 (PRO Only)

  // QR 패스키 세션 상태
  String? _sessionId;
  String? _qrPayload;
  bool _isLoadingSession = true;
  bool _isApproved = false;
  String? _errorMsg;
  bool _saveToProBoard = false; // 1회 접속 시 자동 등록 방지 (명시적 선택 또는 등록 버튼 클릭 시에만 저장)
  StreamSubscription? _approvalSubscription;

  // PRO 등록된 교사 목록
  List<Map<String, String>> _savedTeachers = [];
  bool _isLoadingSaved = true;

  @override
  void initState() {
    super.initState();
    _startPasskeySession();
    _loadSavedTeachers();
  }

  @override
  void dispose() {
    _approvalSubscription?.cancel();
    if (_sessionId != null) {
      PasskeyService.instance.deleteSession(_sessionId!);
    }
    super.dispose();
  }

  Future<void> _startPasskeySession() async {
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
          .listen((result) async {
        if (!mounted) return;

        if (result.approved && result.accessToken != null) {
          setState(() {
            _isApproved = true;
          });

          // PRO 기기 등록이 체크된 경우 로컬 금고(SharedPreferences / Web localStorage)에 저장
          if (_saveToProBoard && result.teacherName != null) {
            await PasskeyService.instance.saveProTeacher(
              teacherName: result.teacherName!,
              email: result.email ?? '',
              schoolName: widget.schoolName,
              refreshToken: result.refreshToken,
              accessToken: result.accessToken,
            );
          }

          String validToken = result.accessToken!;
          if (result.refreshToken != null && result.refreshToken!.isNotEmpty) {
            BstCloudService.instance.activeRefreshToken = result.refreshToken;
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('bst_active_refresh_token', result.refreshToken!);
              final refreshed = await BstCloudService.instance.exchangeRefreshTokenForAccessToken(result.refreshToken!);
              if (refreshed != null && refreshed.isNotEmpty) {
                validToken = refreshed;
              }
            } catch (tokenErr) {
              debugPrint('[BstCloudPasskeyModal] Token refresh note: $tokenErr');
            }
          }

          // Cloud Service 활성화
          BstCloudService.instance.setDirectAccessToken(
            validToken,
            teacherName: result.teacherName ?? '선생님',
            ownerEmail: result.email ?? '',
            folderId: result.folderId,
            refreshToken: result.refreshToken,
          );

          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) {
            Navigator.pop(context);
            widget.onUnlocked();
          }
        } else if (result.errorMessage != null) {
          setState(() {
            _errorMsg = result.errorMessage;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSession = false;
          _errorMsg = '세션 생성 실패: $e';
        });
      }
    }
  }

  Future<void> _loadSavedTeachers() async {
    setState(() => _isLoadingSaved = true);
    final list = await PasskeyService.instance.getProSavedTeachers();
    if (mounted) {
      setState(() {
        _savedTeachers = list;
        _isLoadingSaved = false;
      });
    }
  }

  Future<void> _unlockWithSavedTeacher(Map<String, String> teacher) async {
    final rToken = teacher['refreshToken'];
    String? token = teacher['accessToken'];
    if (rToken != null && rToken.isNotEmpty) {
      BstCloudService.instance.activeRefreshToken = rToken;
      try {
        final refreshed = await BstCloudService.instance.exchangeRefreshTokenForAccessToken(rToken, forceRefresh: true);
        if (refreshed != null && refreshed.isNotEmpty) {
          token = refreshed;
        }
      } catch (e) {
        debugPrint('[BstCloudPasskeyModal] Refresh error on saved teacher: $e');
      }
    }
    if (token == null || token.isEmpty) return;

    BstCloudService.instance.setDirectAccessToken(
      token,
      teacherName: teacher['teacherName'] ?? '선생님',
      ownerEmail: teacher['email'] ?? '',
      refreshToken: rToken,
    );

    Navigator.pop(context);
    widget.onUnlocked();
  }

  Future<void> _removeSavedTeacher(String email) async {
    await PasskeyService.instance.removeProTeacher(email);
    await _loadSavedTeachers();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;

    return Dialog(
      backgroundColor: const Color(0xFF0F141E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20 * s),
        side: const BorderSide(color: Color(0xFF00F5D4), width: 1.5),
      ),
      child: Container(
        width: 520 * s,
        padding: EdgeInsets.all(24 * s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상단 헤더
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10 * s),
                  ),
                  child: Icon(Icons.key_rounded, color: const Color(0xFF00F5D4), size: 24 * s),
                ),
                SizedBox(width: 12 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Boardest Cloud 잠금해제',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white,
                          fontSize: 18 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${widget.schoolName} · ${widget.gradeClass}',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF94A1B2),
                          fontSize: 12 * s,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            SizedBox(height: 18 * s),

            // 탭 선택: [🔑 패스키 잠금해제 (QR)] vs [🏫 등록된 선생님 (PRO 전용)]
            Container(
              padding: EdgeInsets.all(4 * s),
              decoration: BoxDecoration(
                color: const Color(0xFF161E2E),
                borderRadius: BorderRadius.circular(12 * s),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabButton(
                      index: 0,
                      label: '🔑 패스키 QR 잠금해제',
                      s: s,
                    ),
                  ),
                  Expanded(
                    child: _buildTabButton(
                      index: 1,
                      label: '🏫 등록된 선생님 (!Web PRO)',
                      s: s,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20 * s),

            // 탭 내용
            if (_selectedTab == 0)
              _buildPasskeyQrTab(s)
            else
              _buildSavedTeachersTab(s),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton({required int index, required String label, required double s}) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(8 * s),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8 * s),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00F5D4) : Colors.transparent,
          borderRadius: BorderRadius.circular(8 * s),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            color: isSelected ? Colors.black : const Color(0xFF94A1B2),
            fontSize: 12.5 * s,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // 1. 패스키 QR 잠금해제 탭
  Widget _buildPasskeyQrTab(double s) {
    if (_isLoadingSession) {
      return SizedBox(
        height: 240 * s,
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF00F5D4)),
        ),
      );
    }

    if (_isApproved) {
      return SizedBox(
        height: 240 * s,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF00F5D4), size: 56),
            SizedBox(height: 12 * s),
            Text(
              '선생님 패스키 인증 완료!',
              style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4 * s),
            Text(
              '클라우드 수업자료를 불러오는 중입니다...',
              style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12 * s),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Center(
          child: Container(
            padding: EdgeInsets.all(12 * s),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16 * s),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.25),
                  blurRadius: 16 * s,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: _qrPayload ?? '',
              version: QrVersions.auto,
              size: 190 * s,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        SizedBox(height: 14 * s),
        Text(
          '선생님 휴대폰 기본 카메라 또는 Teacher 앱으로 비추어\n패스키(지문/FaceID)로 1초 만에 승인하세요.',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansKr(
            color: const Color(0xFF94A1B2),
            fontSize: 12.5 * s,
            height: 1.4,
          ),
        ),
        if (!kIsWeb) ...[
          SizedBox(height: 10 * s),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Checkbox(
                value: _saveToProBoard,
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
                          '공용 전자칠판에 계정(리프레시 토큰)을 영구 저장하면 다른 사람이나 학생이 교사 계정 및 수업자료에 접근할 수 있어 보안이 취약해집니다.\n\n정말로 이 공용 기기에 계정을 영구 저장하시겠습니까?',
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
                      setState(() => _saveToProBoard = true);
                    }
                  } else {
                    setState(() => _saveToProBoard = false);
                  }
                },
              ),
              Text(
                '이 교실 칠판에 내 계정 등록하기 (PRO 전용 - 보안 주의)',
                style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12 * s, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
        if (_errorMsg != null) ...[
          SizedBox(height: 8 * s),
          Text(
            _errorMsg!,
            style: const TextStyle(color: Color(0xFFFF5252), fontSize: 12),
          ),
        ],
      ],
    );
  }

  // 2. 등록된 선생님 (PRO 전용) 탭
  Widget _buildSavedTeachersTab(double s) {
    if (kIsWeb) {
      return SizedBox(
        height: 200 * s,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.desktop_windows_rounded, color: Color(0xFF94A1B2), size: 40),
              SizedBox(height: 10 * s),
              Text(
                '등록된 교사 목록은 Boardest PRO(Windows/Android)\n설치 앱 전용 보안 기능입니다.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 13 * s),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoadingSaved) {
      return SizedBox(
        height: 200 * s,
        child: const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4))),
      );
    }

    if (_savedTeachers.isEmpty) {
      return SizedBox(
        height: 200 * s,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_off_rounded, color: Colors.white24, size: 40),
              SizedBox(height: 10 * s),
              Text(
                '이 칠판에 등록된 선생님 계정이 없습니다.',
                style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * s),
              ),
              SizedBox(height: 4 * s),
              Text(
                '[패스키 QR 잠금해제] 탭에서 "이 교실에 등록"을 체크하고\n1회 인증하면 다음부터 바로 열 수 있습니다.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11.5 * s),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 240 * s,
      child: ListView.separated(
        itemCount: _savedTeachers.length,
        separatorBuilder: (context, index) => SizedBox(height: 8 * s),
        itemBuilder: (ctx, i) {
          final t = _savedTeachers[i];
          final name = t['teacherName'] ?? '선생님';
          final email = t['email'] ?? '';
          final school = t['schoolName'] ?? widget.schoolName;

          return Container(
            padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
            decoration: BoxDecoration(
              color: const Color(0xFF161E2E),
              borderRadius: BorderRadius.circular(12 * s),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18 * s,
                  backgroundColor: const Color(0xFF00F5D4).withValues(alpha: 0.2),
                  child: Text(
                    name.isNotEmpty ? name[0] : 'T',
                    style: TextStyle(color: const Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 14 * s),
                  ),
                ),
                SizedBox(width: 12 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name 선생님',
                        style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13 * s),
                      ),
                      Text(
                        '$school · $email',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11 * s),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 6 * s),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * s)),
                  ),
                  onPressed: () => _unlockWithSavedTeacher(t),
                  child: Text('바로 열기', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 11.5 * s)),
                ),
                SizedBox(width: 4 * s),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                  tooltip: '등록 해제',
                  onPressed: () => _removeSavedTeacher(email),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

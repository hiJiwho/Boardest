import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_io/io.dart';
import '../models/app_settings.dart';
import '../services/auth_service.dart';
import '../services/bst_cloud_service.dart';
import '../views/canva_overlay_view.dart';
import '../views/pdf_board_view.dart';
import '../views/ppt_overlay_view.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 전자칠판용 클라우드 파일 탐색기 & 터치 키패드 모달 (BstCloudModal)
class BstCloudModal extends StatefulWidget {
  final double scaleFactor;
  final Function(BstCloudFile file, BstCloudTeacher? teacher)? onFileSelected;

  const BstCloudModal({
    super.key,
    required this.scaleFactor,
    this.onFileSelected,
  });

  @override
  State<BstCloudModal> createState() => _BstCloudModalState();
}

class _BstCloudModalState extends State<BstCloudModal> {
  // 로그인 상태: 'none', 'verifying', 'approved'
  String _status = 'none';
  String? _errorMessage;

  // 0: 6자리 1회용 OTP 모드, 1: 2자리 Cloud ID 자동로그인 모드, 2: 스마트폰 QR 모드
  int _loginMode = 2; // 스마트폰 QR 모드 기본 활성화
  String _enteredPin = '';
  ReversePairSession? _modalQrSession;
  bool _isLoadingModalQr = false;
  bool _modalQrCancelled = false;

  // 파일 탐색기 상태
  bool _loadingFiles = false;
  List<BstCloudFile> _allFiles = [];
  List<BstCloudFile> _filteredFiles = [];
  String _searchQuery = '';
  String _categoryFilter = 'all'; // 'all', 'pdf', 'canva', 'ppt', 'pen'

  String? _driveToken;
  String? _teacherName;
  String _classroomName = '교실';

  // 페어링 등록 상태
  bool _isPairingOpen = false;
  String? _pairingCode;
  int _pairingRemainingSec = 180;
  Timer? _pairingTimer;

  @override
  void initState() {
    super.initState();
    _loadClassroomName();

    // 기존 활성 세션이 이미 존재하면 즉시 파일 탐색기 상태로 진입 (팝업 닫아도 세션 유지)
    if (BstCloudService.instance.activeToken != null) {
      _driveToken = BstCloudService.instance.activeToken;
      _teacherName = BstCloudService.instance.activeTeacherName ?? '선생님';
      _status = 'approved';
      _loadFiles();
    } else {
      _initModalQrSession();
    }
  }

  @override
  void dispose() {
    _modalQrCancelled = true;
    _pairingTimer?.cancel();
    super.dispose();
  }

  void _initModalQrSession() async {
    if (_modalQrSession != null || _isLoadingModalQr) return;
    if (!mounted) return;
    setState(() {
      _isLoadingModalQr = true;
      _modalQrCancelled = false;
    });

    try {
      final user = await AuthService().getCurrentUser();
      final session = await BstCloudService.instance.createReversePairSession(
        grade: user?.grade,
        classNum: user?.classNum,
      );
      if (!mounted) return;
      setState(() {
        _modalQrSession = session;
        _isLoadingModalQr = false;
      });

      final res = await BstCloudService.instance.waitForReversePairAuth(
        session.secret,
        isCancelled: () => !mounted || _modalQrCancelled || BstCloudService.instance.activeToken != null,
      );

      if (!mounted) return;
      if (res.success && BstCloudService.instance.activeToken != null) {
        _driveToken = BstCloudService.instance.activeToken;
        _teacherName = res.teacherName ?? '선생님';
        setState(() {
          _status = 'approved';
          _enteredPin = '';
        });
        _loadFiles();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingModalQr = false);
      }
    }
  }

  void _refreshModalQrSession() {
    setState(() {
      _modalQrCancelled = true;
      _modalQrSession = null;
      _isLoadingModalQr = false;
    });
    _initModalQrSession();
  }

  void _loadClassroomName() async {
    final user = await AuthService().getCurrentUser();
    if (user != null) {
      setState(() {
        _classroomName = '${user.grade}학년 ${user.classNum}반';
      });
    }
  }

  void _loadFiles() async {
    final token = _driveToken ?? BstCloudService.instance.activeToken;
    if (token == null || token.isEmpty) return;

    setState(() => _loadingFiles = true);
    try {
      final files = await BstCloudService.instance.fetchDriveFolderFiles(accessToken: token);
      if (mounted) {
        setState(() {
          _allFiles = files.where((f) => !f.name.endsWith('.json')).toList();
          _applyFilter();
          _loadingFiles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingFiles = false;
          _errorMessage = '파일 목록을 불러오지 못했습니다: $e';
        });
      }
    }
  }

  void _applyFilter() {
    List<BstCloudFile> list = _allFiles;

    // 1. 카테고리 필터
    if (_categoryFilter == 'pdf') {
      list = list.where((f) => f.name.toLowerCase().endsWith('.pdf')).toList();
    } else if (_categoryFilter == 'canva') {
      list = list.where((f) => f.name.toLowerCase().endsWith('.canva.bst') || f.name.toLowerCase().endsWith('.canva')).toList();
    } else if (_categoryFilter == 'ppt') {
      list = list.where((f) => f.name.toLowerCase().endsWith('.ppt') || f.name.toLowerCase().endsWith('.pptx')).toList();
    } else if (_categoryFilter == 'pen') {
      list = list.where((f) => f.name.toLowerCase().endsWith('.pen')).toList();
    }

    // 2. 검색어 필터
    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.trim().toLowerCase();
      list = list.where((f) => f.name.toLowerCase().contains(query)).toList();
    }

    _filteredFiles = list;
  }

  // ─── 터치 키패드 핸들러 ───
  void _onKeypadTap(String val) {
    final maxLen = _loginMode == 0 ? 6 : 2;
    if (val == 'CLEAR') {
      setState(() => _enteredPin = '');
    } else if (val == 'BACK') {
      if (_enteredPin.isNotEmpty) {
        setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
      }
    } else {
      if (_enteredPin.length < maxLen) {
        setState(() {
          _enteredPin += val;
          if (_enteredPin.length == maxLen) {
            _submitPin();
          }
        });
      }
    }
  }

  void _submitPin() async {
    final maxLen = _loginMode == 0 ? 6 : 2;
    if (_enteredPin.length != maxLen) {
      setState(() => _errorMessage = _loginMode == 0 ? '6자리 접속 코드를 입력해주세요.' : '2자리 Cloud ID를 입력해주세요.');
      return;
    }

    setState(() {
      _status = 'verifying';
      _errorMessage = null;
    });

    if (_loginMode == 0) {
      // 6자리 Steganography OTP 검증
      final res = await BstCloudService.instance.verify6DigitSteganoOtp(_enteredPin);
      if (!mounted) return;
      if (res.success && res.accessToken != null) {
        _driveToken = res.accessToken;
        _teacherName = res.teacherName ?? '선생님';
        BstCloudService.instance.activeTeacherName = _teacherName;
        setState(() {
          _status = 'approved';
          _enteredPin = '';
        });
        _loadFiles();
      } else {
        setState(() {
          _status = 'none';
          _errorMessage = res.errorMessage ?? '인증에 실패했습니다. 번호를 다시 확인해주세요.';
          _enteredPin = '';
        });
      }
    } else {
      // 2자리 Cloud ID 자동로그인 검증
      final res = await BstCloudService.instance.verify2DigitAutoLogin(_enteredPin, _classroomName);
      if (!mounted) return;
      if (res.success && res.accessToken != null) {
        _driveToken = res.accessToken;
        _teacherName = res.teacherName ?? '선생님';
        BstCloudService.instance.activeTeacherName = _teacherName;
        setState(() {
          _status = 'approved';
          _enteredPin = '';
        });
        _loadFiles();
      } else {
        setState(() {
          _status = 'none';
          _errorMessage = res.errorMessage ?? '등록되지 않은 Cloud ID이거나 페어링이 만료되었습니다.';
          _enteredPin = '';
        });
      }
    }
  }

  void _logout() {
    BstCloudService.instance.activeToken = null;
    BstCloudService.instance.activeTeacherName = null;
    setState(() {
      _status = 'none';
      _driveToken = null;
      _teacherName = null;
      _enteredPin = '';
      _allFiles = [];
      _filteredFiles = [];
      _errorMessage = null;
    });
  }

  void _openFile(BstCloudFile file) async {
    final token = _driveToken ?? BstCloudService.instance.activeToken;
    if (token == null) return;
    final lower = file.name.toLowerCase();

    if (lower.endsWith('.canva.bst') || lower.endsWith('.canva')) {
      // Canva 디자인 열기
      final content = await BstCloudService.instance.readDriveFileText(file.id, token);
      if (content != null) {
        final data = jsonDecode(content);
        final canvaId = data['canvaId']?.toString() ?? '';
        final title = data['title']?.toString() ?? file.name;
        if (canvaId.isNotEmpty && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => CanvaOverlayView(
                canvaId: canvaId,
                title: title,
                scaleFactor: widget.scaleFactor,
              ),
            ),
          );
        }
      }
    } else if (lower.endsWith('.pdf')) {
      Uint8List? bytes;
      if (file.id.isNotEmpty && token.isNotEmpty) {
        bytes = await BstCloudService.instance.downloadDriveFileBytes(file.id, token);
      }
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => PdfBoardView(
              initialFilePath: file.name,
              pdfData: bytes,
              scaleFactor: widget.scaleFactor,
            ),
          ),
        );
      }
    } else if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => PptOverlayView(
            initialFilePath: file.name,
            scaleFactor: widget.scaleFactor,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('📂 [ ${file.name} ] 파일을 열었습니다.')),
      );
    }
  }

  void _startPairing() async {
    final user = await AuthService().getCurrentUser();
    final schoolCode = user?.school ?? 'ydm';
    final res = await BstCloudService.instance.requestPairingCode(schoolCode, _classroomName);
    if (!mounted) return;

    if (res.success && res.pairingCode != null) {
      setState(() {
        _isPairingOpen = true;
        _pairingCode = res.pairingCode;
        _pairingRemainingSec = res.expiresIn ?? 180;
      });
      _pairingTimer?.cancel();
      _pairingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_isPairingOpen) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_pairingRemainingSec > 0) {
            _pairingRemainingSec--;
          } else {
            _isPairingOpen = false;
            timer.cancel();
          }
        });
      });
    } else {
      setState(() => _errorMessage = res.errorMessage ?? '페어링 요청 실패');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 24 * s, vertical: 20 * s),
      child: Container(
        width: 820 * s,
        height: 600 * s,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24 * s),
          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.25),
              blurRadius: 30,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          children: [
            _buildModalHeader(s),
            Expanded(
              child: _status == 'approved'
                  ? _buildFileExplorerView(s)
                  : _status == 'verifying'
                      ? _buildVerifyingView(s)
                      : _buildKeypadLoginView(s),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 모달 상단 헤더 ───
  Widget _buildModalHeader(double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 14 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B4B).withOpacity(0.6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24 * s)),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6 * s),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.25),
              borderRadius: BorderRadius.circular(10 * s),
            ),
            child: Icon(Icons.cloud_done_rounded, color: const Color(0xFF818CF8), size: 20 * s),
          ),
          SizedBox(width: 10 * s),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _status == 'approved' ? '${_teacherName ?? '선생님'}의 Cloud 파일 탐색기' : 'Boardest Cloud 전자칠판 로그인',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 15 * s,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$_classroomName 전용 클라우드 드라이브 (bst-save)',
                style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 11 * s),
              ),
            ],
          ),
          const Spacer(),
          if (_status == 'approved') ...[
            TextButton.icon(
              icon: Icon(Icons.logout_rounded, color: Colors.redAccent, size: 16 * s),
              label: Text('로그아웃', style: GoogleFonts.notoSansKr(color: Colors.redAccent, fontSize: 12 * s, fontWeight: FontWeight.bold)),
              onPressed: _logout,
            ),
            SizedBox(width: 8 * s),
          ],
          IconButton(
            icon: Icon(Icons.close_rounded, color: Colors.white60, size: 22 * s),
            tooltip: '창 닫기 (세션 유지됨)',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle(double s) {
    return Container(
      padding: EdgeInsets.all(4 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14 * s),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() {
                _loginMode = 2;
                _errorMessage = null;
                _initModalQrSession();
              }),
              borderRadius: BorderRadius.circular(10 * s),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10 * s),
                decoration: BoxDecoration(
                  color: _loginMode == 2 ? const Color(0xFF00F5D4) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10 * s),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, size: 14 * s, color: _loginMode == 2 ? const Color(0xFF0B0F19) : Colors.white70),
                      SizedBox(width: 5 * s),
                      Text(
                        '📷 스마트폰 QR',
                        style: GoogleFonts.notoSansKr(
                          color: _loginMode == 2 ? const Color(0xFF0B0F19) : Colors.white70,
                          fontSize: 12 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() {
                _loginMode = 0;
                _enteredPin = '';
                _errorMessage = null;
              }),
              borderRadius: BorderRadius.circular(10 * s),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10 * s),
                decoration: BoxDecoration(
                  color: _loginMode == 0 ? const Color(0xFF6366F1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10 * s),
                ),
                child: Center(
                  child: Text(
                    '🔑 6자리 코드',
                    style: GoogleFonts.notoSansKr(
                      color: _loginMode == 0 ? Colors.white : Colors.white60,
                      fontSize: 12 * s,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() {
                _loginMode = 1;
                _enteredPin = '';
                _errorMessage = null;
              }),
              borderRadius: BorderRadius.circular(10 * s),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10 * s),
                decoration: BoxDecoration(
                  color: _loginMode == 1 ? const Color(0xFF10B981) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10 * s),
                ),
                child: Center(
                  child: Text(
                    '⚡ Cloud ID',
                    style: GoogleFonts.notoSansKr(
                      color: _loginMode == 1 ? Colors.white : Colors.white60,
                      fontSize: 12 * s,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrStepRow(String step, String text, double s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20 * s,
          height: 20 * s,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.3),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF818CF8), width: 1.2),
          ),
          child: Text(
            step,
            style: GoogleFonts.outfit(color: const Color(0xFF818CF8), fontSize: 11 * s, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(width: 8 * s),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12.5 * s, height: 1.4),
          ),
        ),
      ],
    );
  }

  // ─── 1. 터치 키패드 & QR 로그인 화면 (상단 토글 + PIN 디스플레이/QR + 숫자 키패드) ───
  Widget _buildKeypadLoginView(double s) {
    if (_isPairingOpen && _pairingCode != null) {
      return _buildPairingUI(s);
    }

    if (_loginMode == 2) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(20 * s),
        child: Column(
          children: [
            _buildModeToggle(s),
            SizedBox(height: 24 * s),
            Row(
              children: [
                // 좌측: QR 코드 카드
                Expanded(
                  flex: 4,
                  child: Center(
                    child: _isLoadingModalQr
                        ? const CircularProgressIndicator(color: Color(0xFF6366F1))
                        : _modalQrSession != null
                            ? Container(
                                padding: EdgeInsets.all(16 * s),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20 * s),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF6366F1).withOpacity(0.3),
                                      blurRadius: 20 * s,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: QrImageView(
                                  data: _modalQrSession!.qrUrl,
                                  version: QrVersions.auto,
                                  size: 190 * s,
                                  backgroundColor: Colors.white,
                                  padding: EdgeInsets.zero,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.refresh_rounded, size: 36 * s, color: const Color(0xFF818CF8)),
                                    onPressed: _refreshModalQrSession,
                                  ),
                                  Text('QR 생성 실패 (다시 시도)', style: GoogleFonts.notoSansKr(color: Colors.white60, fontSize: 13 * s)),
                                ],
                              ),
                  ),
                ),
                SizedBox(width: 24 * s),
                // 우측: 설명 및 진행 상태
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F5D4).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8 * s),
                        ),
                        child: Text(
                          '⚡ 앱 설치 불필요 · 스마트폰 카메라 스캔',
                          style: GoogleFonts.notoSansKr(
                            color: const Color(0xFF00F5D4),
                            fontSize: 12 * s,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 12 * s),
                      Text(
                        '스마트폰으로 비추면\n수업자료가 바로 열립니다',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white,
                          fontSize: 20 * s,
                          fontWeight: FontWeight.w900,
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: 12 * s),
                      _buildQrStepRow('1', '스마트폰 기본 카메라를 켜고 왼쪽 QR을 스캔하세요.', s),
                      SizedBox(height: 8 * s),
                      _buildQrStepRow('2', '화면에 나타난 링크를 눌러 Google 계정으로 로그인하세요.', s),
                      SizedBox(height: 8 * s),
                      _buildQrStepRow('3', '로그인 즉시 이 전자칠판에 수업자료 클라우드가 열립니다!', s),
                      SizedBox(height: 16 * s),
                      Row(
                        children: [
                          Container(
                            width: 8 * s,
                            height: 8 * s,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00F5D4),
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 8 * s),
                          Text(
                            '스마트폰 연동 대기 중...',
                            style: GoogleFonts.notoSansKr(
                              color: const Color(0xFF00F5D4),
                              fontSize: 13 * s,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            icon: Icon(Icons.refresh_rounded, size: 16 * s, color: Colors.white54),
                            label: Text('새 QR 생성', style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * s)),
                            onPressed: _refreshModalQrSession,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final maxLen = _loginMode == 0 ? 6 : 2;

    return SingleChildScrollView(
      padding: EdgeInsets.all(20 * s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 좌측: 토글 + PIN 디스플레이 + 안내
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModeToggle(s),

                SizedBox(height: 18 * s),

                // 안내 텍스트
                Text(
                  _loginMode == 0
                      ? '선생님 화면의 6자리 번호를 입력하세요 (학생 훔쳐보기 방지)'
                      : '등록된 전자칠판 전용 Cloud ID 2자리를 입력하세요',
                  style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * s),
                  textAlign: TextAlign.center,
                ),

                SizedBox(height: 16 * s),

                // 2. PIN 디스플레이 박스
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(maxLen, (idx) {
                    final hasChar = idx < _enteredPin.length;
                    final char = hasChar ? _enteredPin[idx] : '';
                    final isCurrent = idx == _enteredPin.length;

                    return Container(
                      width: (_loginMode == 0 ? 46 : 64) * s,
                      height: (_loginMode == 0 ? 56 : 68) * s,
                      margin: EdgeInsets.symmetric(horizontal: 4 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0F19),
                        borderRadius: BorderRadius.circular(12 * s),
                        border: Border.all(
                          color: isCurrent
                              ? (_loginMode == 0 ? const Color(0xFF38BDF8) : const Color(0xFF34D399))
                              : hasChar
                                  ? Colors.white54
                                  : Colors.white12,
                          width: isCurrent ? 2.0 : 1.0,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          char.isNotEmpty ? char : (isCurrent ? '|' : '•'),
                          style: GoogleFonts.sourceCodePro(
                            color: _loginMode == 0 ? const Color(0xFF38BDF8) : const Color(0xFF34D399),
                            fontSize: (_loginMode == 0 ? 26 : 32) * s,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    );
                  }),
                ),

                if (_errorMessage != null) ...[
                  SizedBox(height: 12 * s),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8 * s),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.notoSansKr(color: Colors.redAccent, fontSize: 11.5 * s, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                SizedBox(height: 18 * s),

                // 확인 제출 버튼
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _loginMode == 0 ? const Color(0xFF6366F1) : const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14 * s),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * s)),
                  ),
                  onPressed: _submitPin,
                  child: Text(
                    _loginMode == 0 ? '🚀 6자리 코드로 접속' : '⚡ Cloud ID로 잠금해제',
                    style: GoogleFonts.notoSansKr(fontSize: 14 * s, fontWeight: FontWeight.bold),
                  ),
                ),

                SizedBox(height: 12 * s),

                // 전자칠판 자동로그인 기기 등록 버튼
                TextButton.icon(
                  icon: Icon(Icons.phonelink_setup_rounded, size: 16 * s, color: const Color(0xFFFACC15)),
                  label: Text('이 전자칠판을 자동로그인 기기로 등록하기', style: GoogleFonts.notoSansKr(color: const Color(0xFFFACC15), fontSize: 11 * s, fontWeight: FontWeight.bold)),
                  onPressed: _startPairing,
                ),
              ],
            ),
          ),

          SizedBox(width: 24 * s),

          // 우측: 3x4 터치 숫자 키패드
          Expanded(
            flex: 4,
            child: Container(
              padding: EdgeInsets.all(12 * s),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.6),
                borderRadius: BorderRadius.circular(18 * s),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  _buildKeypadRow(['1', '2', '3'], s),
                  SizedBox(height: 8 * s),
                  _buildKeypadRow(['4', '5', '6'], s),
                  SizedBox(height: 8 * s),
                  _buildKeypadRow(['7', '8', '9'], s),
                  SizedBox(height: 8 * s),
                  _buildKeypadRow(['CLEAR', '0', 'BACK'], s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypadRow(List<String> keys, double s) {
    return Row(
      children: keys.map((k) {
        final isSpecial = k == 'CLEAR' || k == 'BACK';
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4 * s),
            child: InkWell(
              onTap: () => _onKeypadTap(k),
              borderRadius: BorderRadius.circular(12 * s),
              child: Container(
                height: 52 * s,
                decoration: BoxDecoration(
                  color: isSpecial ? const Color(0xFF334155) : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12 * s),
                  border: Border.all(color: Colors.white12),
                ),
                child: Center(
                  child: k == 'BACK'
                      ? Icon(Icons.backspace_outlined, color: Colors.white70, size: 20 * s)
                      : k == 'CLEAR'
                          ? Text('C', style: GoogleFonts.sourceCodePro(color: Colors.redAccent, fontSize: 18 * s, fontWeight: FontWeight.bold))
                          : Text(k, style: GoogleFonts.sourceCodePro(color: Colors.white, fontSize: 22 * s, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── 2. 파일 탐색기 스타일 뷰 (File Explorer) ───
  Widget _buildFileExplorerView(double s) {
    return Column(
      children: [
        // 상단 툴바: 경로 표시줄 & 검색창 & 새로고침
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 10 * s),
          color: const Color(0xFF1E293B).withOpacity(0.4),
          child: Row(
            children: [
              // Breadcrumbs
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8 * s),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_rounded, color: Color(0xFFFACC15), size: 16),
                    SizedBox(width: 6 * s),
                    Text('내 드라이브 > bst-save', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * s, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),

              SizedBox(width: 12 * s),

              // 검색창
              Expanded(
                child: Container(
                  height: 36 * s,
                  padding: EdgeInsets.symmetric(horizontal: 10 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8 * s),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12 * s),
                    decoration: InputDecoration(
                      hintText: '수업 자료 파일 검색...',
                      hintStyle: GoogleFonts.notoSansKr(color: Colors.white30, fontSize: 11.5 * s),
                      border: InputBorder.none,
                      icon: Icon(Icons.search_rounded, color: Colors.white38, size: 16 * s),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _applyFilter();
                      });
                    },
                  ),
                ),
              ),

              SizedBox(width: 10 * s),

              IconButton(
                icon: Icon(Icons.refresh_rounded, color: const Color(0xFF00F5D4), size: 20 * s),
                tooltip: '새로고침',
                onPressed: _loadFiles,
              ),
            ],
          ),
        ),

        // 카테고리 필터 탭 (전체, PDF, Canva, PPT, 판서노트)
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: Row(
            children: [
              _buildFilterChip('all', '전체 자료 (${_allFiles.length})', s),
              SizedBox(width: 8 * s),
              _buildFilterChip('pdf', '📄 PDF 교안', s),
              SizedBox(width: 8 * s),
              _buildFilterChip('canva', '🎨 Canva 디자인', s),
              SizedBox(width: 8 * s),
              _buildFilterChip('ppt', '📊 PPT 슬라이드', s),
              SizedBox(width: 8 * s),
              _buildFilterChip('pen', '📝 판서 기록', s),
            ],
          ),
        ),

        // 파일 그리드 / 목록 뷰
        Expanded(
          child: _loadingFiles
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)))
              : _filteredFiles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open_rounded, color: Colors.white24, size: 48 * s),
                          SizedBox(height: 10 * s),
                          Text(
                            '보관된 수업 자료가 없습니다.\n교사용 앱에서 교안을 업로드하거나 Canva 디자인을 등록하세요.',
                            style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * s),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.all(16 * s),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12 * s,
                        mainAxisSpacing: 12 * s,
                        childAspectRatio: 2.3,
                      ),
                      itemCount: _filteredFiles.length,
                      itemBuilder: (ctx, idx) {
                        final file = _filteredFiles[idx];
                        return _buildFileCard(file, s);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String key, String label, double s) {
    final isSelected = _categoryFilter == key;
    return InkWell(
      onTap: () => setState(() {
        _categoryFilter = key;
        _applyFilter();
      }),
      borderRadius: BorderRadius.circular(20 * s),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 6 * s),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20 * s),
          border: Border.all(color: isSelected ? Colors.transparent : Colors.white12),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 11 * s,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildFileCard(BstCloudFile file, double s) {
    final lower = file.name.toLowerCase();
    final isCanva = lower.endsWith('.canva.bst') || lower.endsWith('.canva');
    final isPdf = lower.endsWith('.pdf');
    final isPpt = lower.endsWith('.ppt') || lower.endsWith('.pptx');
    final isPen = lower.endsWith('.pen');

    final iconColor = isCanva
        ? const Color(0xFF00C4CC)
        : isPdf
            ? const Color(0xFFFF5252)
            : isPpt
                ? const Color(0xFFFF9800)
                : isPen
                    ? const Color(0xFF00F5D4)
                    : const Color(0xFF818CF8);

    final icon = isCanva
        ? Icons.palette_rounded
        : isPdf
            ? Icons.picture_as_pdf_rounded
            : isPpt
                ? Icons.slideshow_rounded
                : isPen
                    ? Icons.edit_note_rounded
                    : Icons.insert_drive_file_rounded;

    return InkWell(
      onTap: () => _openFile(file),
      borderRadius: BorderRadius.circular(14 * s),
      child: Container(
        padding: EdgeInsets.all(10 * s),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.7),
          borderRadius: BorderRadius.circular(14 * s),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10 * s),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10 * s),
              ),
              child: Icon(icon, color: iconColor, size: 24 * s),
            ),
            SizedBox(width: 10 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    file.name,
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontSize: 12 * s,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2 * s),
                  Text(
                    isCanva ? 'Canva 웹 교안' : isPdf ? 'PDF 전자문서' : isPpt ? 'PowerPoint 슬라이드' : '수업 자료',
                    style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 10 * s),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 12 * s),
          ],
        ),
      ),
    );
  }

  Widget _buildVerifyingView(double s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF00F5D4)),
          SizedBox(height: 16 * s),
          Text('단기 보안 토큰 검증 중...', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * s, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPairingUI(double s) {
    return Center(
      child: Container(
        width: 440 * s,
        padding: EdgeInsets.all(20 * s),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18 * s),
          border: Border.all(color: const Color(0xFFFACC15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phonelink_setup_rounded, color: Color(0xFFFACC15), size: 36),
            SizedBox(height: 10 * s),
            Text('전자칠판 자동 로그인 기기 등록', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 15 * s, fontWeight: FontWeight.bold)),
            SizedBox(height: 6 * s),
            Text('교사용 웹/앱의 [인증 & 기기 관리] 화면에서 아래 8자리 등록 코드를 입력하세요.', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 11.5 * s), textAlign: TextAlign.center),
            SizedBox(height: 16 * s),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 10 * s),
              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(12 * s)),
              child: Text(
                _pairingCode != null && _pairingCode!.length == 8
                    ? '${_pairingCode!.substring(0, 4)}  ${_pairingCode!.substring(4, 8)}'
                    : (_pairingCode ?? '--------'),
                style: GoogleFonts.sourceCodePro(color: const Color(0xFF00F5D4), fontSize: 28 * s, fontWeight: FontWeight.w900, letterSpacing: 4 * s),
              ),
            ),
            SizedBox(height: 8 * s),
            Text('유효 시간: $_pairingRemainingSec초', style: GoogleFonts.notoSansKr(color: const Color(0xFFFF8906), fontSize: 11 * s)),
            SizedBox(height: 14 * s),
            ElevatedButton(
              onPressed: () => setState(() => _isPairingOpen = false),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }
}

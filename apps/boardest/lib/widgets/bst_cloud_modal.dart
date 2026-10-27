import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_io/io.dart';
import '../services/auth_service.dart';
import '../services/bst_cloud_service.dart';
import '../views/canva_overlay_view.dart';
import '../views/pdf_board_view.dart';
import '../views/ppt_overlay_view.dart';
import '../views/hwp_overlay_view.dart';
import '../views/tbp/tbp_viewer_route.dart';
import '../views/boardest_pen_view.dart';
import '../services/update_service.dart';
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

  // 페어링 등록 상태 (시크릿 QR 코드 기반 자동 로그인 기기 등록)
  bool _isPairingOpen = false;
  ReversePairSession? _pairingQrSession;
  bool _isLoadingPairingQr = false;
  bool _pairingCancelled = false;
  int _pairingRemainingSec = 300;
  Timer? _pairingTimer;

  @override
  void initState() {
    super.initState();
    _loadClassroomName();

    // 기존 활성 세션이 이미 존재하고 인증 에러가 없을 때만 즉시 파일 탐색기 상태로 진입
    if (BstCloudService.instance.activeToken != null && !BstCloudService.instance.hasAuthError) {
      _driveToken = BstCloudService.instance.activeToken;
      _teacherName = BstCloudService.instance.activeTeacherName ?? '선생님';
      _status = 'approved';
      _loadFiles();
    } else {
      BstCloudService.instance.disconnect();
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

  // 0: Bst (기본 수업자료), 1: Bst TBP (스마트교과서 & 웹교안), 2: Bst Pen (판서노트)
  int _folderTab = 0;

  String get _currentFolderName {
    if (_folderTab == 2) return 'bst-pen';
    return 'bst-save';
  }

  void _loadFiles() async {
    final token = _driveToken ?? BstCloudService.instance.activeToken;
    if (token == null || token.isEmpty) return;

    setState(() => _loadingFiles = true);
    try {
      final targetFolder = _currentFolderName;
      final files = await BstCloudService.instance.fetchFilesBySpecificFolder(
        accessToken: token,
        folderName: targetFolder,
      );

      if (mounted) {
        setState(() {
          _allFiles = files;
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

    // 1. 메인 3대 폴더 탭 필터
    if (_folderTab == 1) {
      // Bst TBP: TBP 교과서 및 HTMLP 교안 포인터
      list = list.where((f) {
        final l = f.name.toLowerCase();
        return l.endsWith('.tbp') ||
            l.endsWith('.tbp.bst') ||
            l.endsWith('.htmlp') ||
            l.endsWith('.htmlp.bst') ||
            l.endsWith('.bsttbp') ||
            l.endsWith('.canva.bst') ||
            l.endsWith('.canva') ||
            l.endsWith('.bstcanva') ||
            f.mimeType == 'application/x-bst-tbp-folder';
      }).toList();
    } else if (_folderTab == 2) {
      // Bst Pen: 판서 파일 전용
      list = list.where((f) => f.name.toLowerCase().endsWith('.pen') || f.name.toLowerCase().endsWith('.bstpen')).toList();
    } else {
      // Bst: 일반 수업 자료 (PDF, PPT, HWP, TBP/HTMLP 껍데기 등) - 판서(.pen)는 제외!
      list = list.where((f) {
        final l = f.name.toLowerCase();
        return !l.endsWith('.pen') && !l.endsWith('.bstpen');
      }).toList();
    }

    // 2. 세부 카테고리 필터
    if (_categoryFilter == 'pdf') {
      list = list.where((f) => f.name.toLowerCase().endsWith('.pdf')).toList();
    } else if (_categoryFilter == 'canva' || _categoryFilter == 'htmlp') {
      list = list.where((f) {
        final l = f.name.toLowerCase();
        return l.endsWith('.htmlp') || l.endsWith('.htmlp.bst') || l.endsWith('.canva.bst') || l.endsWith('.canva') || l.endsWith('.bstcanva');
      }).toList();
    } else if (_categoryFilter == 'tbp') {
      list = list.where((f) {
        final l = f.name.toLowerCase();
        return l.endsWith('.tbp') || l.endsWith('.tbp.bst') || l.endsWith('.bsttbp') || f.mimeType == 'application/x-bst-tbp-folder';
      }).toList();
    } else if (_categoryFilter == 'ppt') {
      list = list.where((f) => f.name.toLowerCase().endsWith('.ppt') || f.name.toLowerCase().endsWith('.pptx')).toList();
    } else if (_categoryFilter == 'hwp') {
      list = list.where((f) => f.name.toLowerCase().endsWith('.hwp') || f.name.toLowerCase().endsWith('.hwpx')).toList();
    } else if (_categoryFilter == 'pen') {
      list = list.where((f) => f.name.toLowerCase().endsWith('.pen') || f.name.toLowerCase().endsWith('.bstpen')).toList();
    }

    // 3. 검색어 필터
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

    // 1. TBP 스마트 교과서 또는 HTMLP 프레젠터 열기 (통합 TbpViewerRoute)
    if (lower.endsWith('.tbp') ||
        lower.endsWith('.tbp.bst') ||
        lower.endsWith('.bsttbp') ||
        lower.endsWith('.htmlp') ||
        lower.endsWith('.htmlp.bst') ||
        lower.endsWith('.canva.bst') ||
        lower.endsWith('.canva') ||
        lower.endsWith('.bstcanva') ||
        file.mimeType == 'application/x-bst-tbp-folder') {
      final isHtmlp = lower.endsWith('.htmlp') ||
          lower.endsWith('.htmlp.bst') ||
          lower.endsWith('.canva.bst') ||
          lower.endsWith('.canva') ||
          lower.endsWith('.bstcanva');
      if (kIsWeb) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF141721),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.block_rounded, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text('TBP 웹 실행 제한', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            content: const Text(
              'TBP 전자교과서는 보안 및 고성능 판서·엔진 구동을 위해 Windows/Android 앱에서만 지원됩니다.\n웹 브라우저에서는 이용하실 수 없습니다.',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('확인', style: TextStyle(color: Color(0xFF00F5D4))),
              ),
            ],
          ),
        );
        return;
      }
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => TbpViewerRoute(
              tbpFilePath: 'drive://tbp/${file.id}',
              title: file.name,
              scaleFactor: widget.scaleFactor,
              mode: isHtmlp ? TbpViewerMode.htmlp : TbpViewerMode.tbp,
            ),
          ),
        );
      }
      return;
    }

    // 2. 전자칠판 판서 노트 열기
    if (lower.endsWith('.pen') || lower.endsWith('.bstpen')) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => BoardestPenView(
              filePath: file.name,
              scaleFactor: widget.scaleFactor,
              teacher: _teacherName ?? '선생님',
              subject: '판서',
            ),
          ),
        );
      }
      return;
    }

    // 3. PDF 문서 열기
    if (lower.endsWith('.pdf')) {
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
      return;
    }

    // 4. PPT 프레젠테이션 열기
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      if (kIsWeb) {
        final driveUrl = 'https://drive.google.com/file/d/${file.id}/view';
        launchUrl(Uri.parse(driveUrl), mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📂 [${file.name}] 다운로드 및 프레젠테이션 실행 중...'), duration: const Duration(seconds: 2)),
        );
        final localPath = await BstCloudService.instance.downloadDriveFile(file.id, file.name, token);
        if (localPath != null && mounted) {
          if (Platform.isWindows) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => PptOverlayView(
                  initialFilePath: localPath,
                  scaleFactor: widget.scaleFactor,
                ),
              ),
            );
          } else {
            await launchUrl(Uri.file(localPath), mode: LaunchMode.externalApplication);
          }
        }
      }
      return;
    }

    // 5. 한글 문서 열기
    if (lower.endsWith('.hwp') || lower.endsWith('.hwpx')) {
      if (kIsWeb) {
        final driveUrl = 'https://drive.google.com/file/d/${file.id}/view';
        launchUrl(Uri.parse(driveUrl), mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📂 [${file.name}] 다운로드 및 한글 뷰어 실행 중...'), duration: const Duration(seconds: 2)),
        );
        final localPath = await BstCloudService.instance.downloadDriveFile(file.id, file.name, token);
        if (localPath != null && mounted) {
          if (Platform.isWindows) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => HwpOverlayView(
                  initialFilePath: localPath,
                  scaleFactor: widget.scaleFactor,
                ),
              ),
            );
          } else {
            await launchUrl(Uri.file(localPath), mode: LaunchMode.externalApplication);
          }
        }
      }
      return;
    }

    // 기타 파일
    if (kIsWeb) {
      final driveUrl = 'https://drive.google.com/file/d/${file.id}/view';
      launchUrl(Uri.parse(driveUrl), mode: LaunchMode.externalApplication);
    } else {
      final localPath = await BstCloudService.instance.downloadDriveFile(file.id, file.name, token);
      if (localPath != null) {
        await launchUrl(Uri.file(localPath), mode: LaunchMode.externalApplication);
      }
    }
  }

  /// 파일 삭제 핸들러 (TBP/HTMLP 영구 삭제 사전 경고)
  Future<void> _deleteFile(BstCloudFile file) async {
    final lower = file.name.toLowerCase();
    final isTbpOrHtmlp = lower.endsWith('.tbp') ||
        lower.endsWith('.tbp.bst') ||
        lower.endsWith('.htmlp') ||
        lower.endsWith('.htmlp.bst') ||
        lower.endsWith('.bsttbp') ||
        lower.endsWith('.canva.bst') ||
        file.mimeType == 'application/x-bst-tbp-folder';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isTbpOrHtmlp ? Icons.warning_amber_rounded : Icons.delete_outline_rounded,
              color: const Color(0xFFEF4565),
              size: 22 * widget.scaleFactor,
            ),
            const SizedBox(width: 8),
            Text(
              isTbpOrHtmlp ? '스마트 교재/교안 삭제 확인' : '파일 삭제 확인',
              style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          isTbpOrHtmlp
              ? '[${file.name}] 을(를) 삭제하시겠습니까?\n\n⚠️ TBP/HTMLP 스마트 교안은 클라우드 포인터 파일 및 bst-tbp에 저장된 원본 프로젝트 데이터가 모두 영구히 삭제됩니다.'
              : '[${file.name}] 파일을 클라우드에서 삭제하시겠습니까?',
          style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4565)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isTbpOrHtmlp ? '영구 삭제' : '삭제',
              style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      bool ok = false;
      if (isTbpOrHtmlp) {
        ok = await BstCloudService.instance.deletePointerShellWithCascade(file);
      } else {
        ok = await BstCloudService.instance.deleteDriveFile(file.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '파일이 삭제되었습니다.' : '파일 삭제에 실패했습니다.'),
            backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4565),
            duration: const Duration(seconds: 2),
          ),
        );
        _loadFiles();
      }
    }
  }

  void _startPairing() async {
    setState(() {
      _isPairingOpen = true;
      _isLoadingPairingQr = true;
      _pairingCancelled = false;
      _pairingRemainingSec = 300;
      _pairingQrSession = null;
    });

    try {
      final user = await AuthService().getCurrentUser();
      final session = await BstCloudService.instance.createReversePairSession(
        schoolCode: user?.school ?? '',
        grade: user?.grade,
        classNum: user?.classNum,
      );
      if (!mounted || _pairingCancelled) return;

      setState(() {
        _pairingQrSession = session;
        _isLoadingPairingQr = false;
      });

      _pairingTimer?.cancel();
      _pairingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_isPairingOpen || _pairingCancelled) {
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

      // Poll until phone/teacher scans and authorizes!
      final res = await BstCloudService.instance.waitForReversePairAuth(
        session.secret,
        isCancelled: () => !mounted || !_isPairingOpen || _pairingCancelled,
      );

      if (!mounted || _pairingCancelled) return;

      if (res.success && BstCloudService.instance.activeToken != null) {
        if (!mounted) return;
        _driveToken = BstCloudService.instance.activeToken;
        _teacherName = res.teacherName ?? '선생님';
        setState(() {
          _isPairingOpen = false;
          _status = 'approved';
          _enteredPin = '';
        });
        _loadFiles();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 [$_teacherName] 선생님의 Cloud 수업자료가 연결되었습니다! (기기 등록은 [교사 등록] 버튼을 눌러주세요)'),
            backgroundColor: const Color(0xFF2EC4B6),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPairingQr = false;
          _errorMessage = '시크릿 QR 생성 실패: $e';
        });
      }
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
                        'QR로 로그인',
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pin_rounded, size: 14 * s, color: _loginMode == 0 ? Colors.white : Colors.white60),
                      SizedBox(width: 5 * s),
                      Text(
                        'OTP로 로그인',
                        style: GoogleFonts.notoSansKr(
                          color: _loginMode == 0 ? Colors.white : Colors.white60,
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.badge_rounded, size: 14 * s, color: _loginMode == 1 ? Colors.white : Colors.white60),
                      SizedBox(width: 5 * s),
                      Text(
                        '교사용 ID로 로그인',
                        style: GoogleFonts.notoSansKr(
                          color: _loginMode == 1 ? Colors.white : Colors.white60,
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
    if (_isPairingOpen) {
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
                      ? '선생님 앱 또는 구글 OTP 앱의 번호를 입력하세요'
                      : '전자칠판에 등록된 교사용 ID (2자리)를 입력하세요',
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
                    _loginMode == 0 ? '🚀 OTP로 로그인' : '⚡ 교사용 ID로 로그인',
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
        // 상단 툴바: 3대 폴더 전환 탭 (Bst, Bst TBP, Bst Pen) & 검색창 & 새로고침
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 10 * s),
          color: const Color(0xFF1E293B).withOpacity(0.4),
          child: Row(
            children: [
              // 3대 핵심 보관함 전환 탭
              _buildFolderTabButton(0, '📁 Bst (자료)', const Color(0xFF38BDF8), s),
              SizedBox(width: 6 * s),
              _buildFolderTabButton(1, '📐 Bst TBP (교재)', const Color(0xFF818CF8), s),
              SizedBox(width: 6 * s),
              _buildFolderTabButton(2, '🎨 Bst Pen (판서)', const Color(0xFF00F5D4), s),

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
                      hintText: '자료 파일 검색...',
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

        // 카테고리 필터 서브 탭
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: Row(
            children: _buildSubCategoryChips(s),
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
                            _folderTab == 1
                                ? '등록된 스마트교과서 또는 웹교안(.tbp / .htmlp)이 없습니다.\n교사용 앱에서 교과서/교안을 저장해주세요.'
                                : _folderTab == 2
                                    ? '보관된 전자칠판 판서 노트(.pen)가 없습니다.'
                                    : '보관된 수업 자료가 없습니다.\n교사용 앱에서 교안을 업로드하세요.',
                            style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12.5 * s),
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

  Widget _buildFolderTabButton(int index, String title, Color activeColor, double s) {
    final isSelected = _folderTab == index;
    return InkWell(
      onTap: () {
        if (_folderTab != index) {
          setState(() {
            _folderTab = index;
            _categoryFilter = 'all';
          });
          _loadFiles();
        }
      },
      borderRadius: BorderRadius.circular(10 * s),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10 * s),
          border: Border.all(color: isSelected ? activeColor : Colors.white12, width: 1.2),
        ),
        child: Text(
          title,
          style: GoogleFonts.notoSansKr(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 11.5 * s,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSubCategoryChips(double s) {
    if (_folderTab == 1) {
      // Bst TBP
      return [
        _buildFilterChip('all', '전체 TBP/HTMLP (${_filteredFiles.length})', s),
        SizedBox(width: 8 * s),
        _buildFilterChip('tbp', '📐 TBP 교과서', s),
        SizedBox(width: 8 * s),
        _buildFilterChip('htmlp', '🌐 HTMLP 웹교안', s),
      ];
    } else if (_folderTab == 2) {
      // Bst Pen
      return [
        _buildFilterChip('all', '전체 판서 (${_filteredFiles.length})', s),
      ];
    } else {
      // Bst 전체
      return [
        _buildFilterChip('all', '전체 자료 (${_allFiles.length})', s),
        SizedBox(width: 8 * s),
        _buildFilterChip('tbp', '📐 TBP/HTMLP', s),
        SizedBox(width: 8 * s),
        _buildFilterChip('pdf', '📕 PDF', s),
        SizedBox(width: 8 * s),
        _buildFilterChip('ppt', '📊 PPT', s),
        SizedBox(width: 8 * s),
        _buildFilterChip('hwp', '📝 한글', s),
      ];
    }
  }

  Widget _buildFilterChip(String key, String label, double s) {
    final isSelected = _categoryFilter == key;
    return InkWell(
      onTap: () {
        if (_categoryFilter != key) {
          setState(() {
            _categoryFilter = key;
            _applyFilter();
          });
        }
      },
      borderRadius: BorderRadius.circular(20 * s),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 5 * s),
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
    final isTbp = lower.endsWith('.tbp') || lower.endsWith('.tbp.bst') || lower.endsWith('.bsttbp') || file.mimeType == 'application/x-bst-tbp-folder';
    final isHtmlp = lower.endsWith('.htmlp') || lower.endsWith('.htmlp.bst') || lower.endsWith('.canva.bst') || lower.endsWith('.canva') || lower.endsWith('.bstcanva');
    final isPdf = lower.endsWith('.pdf');
    final isPpt = lower.endsWith('.ppt') || lower.endsWith('.pptx');
    final isHwp = lower.endsWith('.hwp') || lower.endsWith('.hwpx');
    final isPen = lower.endsWith('.pen') || lower.endsWith('.bstpen');

    final iconColor = isTbp
        ? const Color(0xFF818CF8)
        : isHtmlp
            ? const Color(0xFF00C4CC)
            : isPdf
                ? const Color(0xFFFF5252)
                : isPpt
                    ? const Color(0xFFFF9800)
                    : isHwp
                        ? const Color(0xFF3B82F6)
                        : isPen
                            ? const Color(0xFF00F5D4)
                            : const Color(0xFF94A3B8);

    final icon = isTbp
        ? Icons.auto_stories_rounded
        : isHtmlp
            ? Icons.co_present_rounded
            : isPdf
                ? Icons.picture_as_pdf_rounded
                : isPpt
                    ? Icons.slideshow_rounded
                    : isHwp
                        ? Icons.description_rounded
                        : isPen
                            ? Icons.history_edu_rounded
                            : Icons.insert_drive_file_rounded;

    final typeLabel = isTbp
        ? '📐 TBP 스마트교과서'
        : isHtmlp
            ? '🌐 HTMLP 웹교안'
            : isPdf
                ? '📕 PDF 문서'
                : isPpt
                    ? '📊 PPT 슬라이드'
                    : isHwp
                        ? '📝 한글 문서'
                        : isPen
                            ? '🎨 판서 기록'
                            : '수업 자료';

    return InkWell(
      onTap: () => _openFile(file),
      borderRadius: BorderRadius.circular(14 * s),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 8 * s),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.7),
          borderRadius: BorderRadius.circular(14 * s),
          border: Border.all(color: iconColor.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(9 * s),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10 * s),
              ),
              child: Icon(icon, color: iconColor, size: 22 * s),
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
                      fontSize: 12.5 * s,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2 * s),
                  Text(
                    typeLabel,
                    style: GoogleFonts.notoSansKr(color: iconColor.withOpacity(0.85), fontSize: 10.5 * s, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: Colors.white30, size: 18 * s),
              tooltip: '삭제',
              onPressed: () => _deleteFile(file),
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
        width: 380 * s,
        padding: EdgeInsets.all(22 * s),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(24 * s),
          border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 30 * s,
              spreadRadius: 4 * s,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(6 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFACC15).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.qr_code_scanner_rounded, color: const Color(0xFFFACC15), size: 22 * s),
                ),
                SizedBox(width: 8 * s),
                Text(
                  '자동 로그인 기기 등록',
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 8 * s),
            Text(
              '선생님의 스마트폰 기본 카메라나 교사용 앱으로\n아래 시크릿 QR 코드를 바로 스캔하세요.',
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 11.5 * s, height: 1.4),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16 * s),

            // QR 디스플레이 영역
            Container(
              width: 200 * s,
              height: 200 * s,
              padding: EdgeInsets.all(12 * s),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16 * s),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F5D4).withOpacity(0.2),
                    blurRadius: 16 * s,
                    spreadRadius: 2 * s,
                  ),
                ],
              ),
              child: _isLoadingPairingQr
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF7F5AF0)))
                  : (_pairingQrSession != null
                      ? QrImageView(
                          data: _pairingQrSession!.qrUrl,
                          version: QrVersions.auto,
                          size: 176 * s,
                          gapless: false,
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline_rounded, color: Colors.grey, size: 30 * s),
                              SizedBox(height: 6 * s),
                              Text('QR 생성 실패', style: TextStyle(color: Colors.black54, fontSize: 11 * s)),
                            ],
                          ),
                        )),
            ),
            SizedBox(height: 12 * s),

            Container(
              padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8906).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8 * s),
                border: Border.all(color: const Color(0xFFFF8906).withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, color: const Color(0xFFFF8906), size: 13 * s),
                  SizedBox(width: 4 * s),
                  Text(
                    '유효 시간: $_pairingRemainingSec초 (스캔 시 즉시 등록)',
                    style: GoogleFonts.notoSansKr(color: const Color(0xFFFF8906), fontSize: 11 * s, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16 * s),

            SizedBox(
              width: double.infinity,
              height: 40 * s,
              child: OutlinedButton(
                onPressed: () {
                  _pairingCancelled = true;
                  _pairingTimer?.cancel();
                  setState(() => _isPairingOpen = false);
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * s)),
                ),
                child: Text('닫기', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * s)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

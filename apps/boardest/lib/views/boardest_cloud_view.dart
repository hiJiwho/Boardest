import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/bst_cloud_service.dart';
import '../services/passkey_service.dart';
import 'boardest_pen_view.dart';
import 'pdf_board_view.dart';
import 'tbp/tbp_viewer_route.dart';

/// Boardest Cloud 전용 메인 뷰
/// - 미연결 시: 오직 모바일 Web QR 로그인 메인 화면 (학교 인증 필요한 OTP 배제)
/// - 연결 완료 시: Google Drive 수업 자료 즉시 표시 및 클릭 시 원터치 뷰어 실행
class BoardestCloudView extends StatefulWidget {
  const BoardestCloudView({super.key});

  @override
  State<BoardestCloudView> createState() => _BoardestCloudViewState();
}

class _BoardestCloudViewState extends State<BoardestCloudView> {
  // 연결 상태
  bool _isConnected = false;
  String? _teacherName;
  String? _ownerEmail;

  // QR 세션 상태
  String? _sessionId;
  String? _qrPayload;
  bool _isLoadingQr = true;
  String? _qrError;
  StreamSubscription? _approvalSubscription;

  // 파일 탐색기 상태
  bool _isLoadingFiles = false;
  List<BstCloudFile> _allFiles = [];
  List<BstCloudFile> _filteredFiles = [];
  String _searchQuery = '';
  String _selectedCategory = 'all'; // 'all', 'tbp', 'pdf', 'ppt', 'hwp', 'pen'

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
  }

  @override
  void dispose() {
    _approvalSubscription?.cancel();
    if (_sessionId != null) {
      PasskeyService.instance.deleteSession(_sessionId!);
    }
    super.dispose();
  }

  Future<void> _checkInitialConnection() async {
    final activeToken = BstCloudService.instance.activeToken;
    if (activeToken != null && activeToken.isNotEmpty) {
      setState(() {
        _isConnected = true;
        _teacherName = BstCloudService.instance.activeTeacherName ?? '선생님';
      });
      await _loadFiles();
    } else {
      await _startQrSession();
    }
  }

  /// 📱 QR 세션 시작 (스마트폰 카메라로 스캔하여 Google 로그인)
  Future<void> _startQrSession() async {
    if (!mounted) return;
    setState(() {
      _isLoadingQr = true;
      _qrError = null;
    });

    _approvalSubscription?.cancel();
    if (_sessionId != null) {
      PasskeyService.instance.deleteSession(_sessionId!);
      _sessionId = null;
    }

    try {
      final res = await PasskeyService.instance.createChallengeSession(
        schoolName: 'Boardest Cloud',
        roomName: '전자칠판',
      );

      if (!mounted) return;
      setState(() {
        _sessionId = res.sessionId;
        _qrPayload = res.qrPayload;
        _isLoadingQr = false;
      });

      _approvalSubscription = PasskeyService.instance
          .listenForApproval(res.sessionId)
          .listen((event) async {
        if (!mounted) return;
        if (event.approved && event.accessToken != null) {
          BstCloudService.instance.setDirectAccessToken(
            event.accessToken!,
            teacherName: event.teacherName ?? '선생님',
            ownerEmail: event.email ?? '',
          );
          if (event.refreshToken != null) {
            BstCloudService.instance.activeRefreshToken = event.refreshToken;
          }

          setState(() {
            _isConnected = true;
            _teacherName = event.teacherName ?? '선생님';
            _ownerEmail = event.email;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 ${_teacherName}님의 Cloud가 안전하게 연결되었습니다!'),
              backgroundColor: const Color(0xFF00F5D4),
              behavior: SnackBarBehavior.floating,
            ),
          );

          await _loadFiles();
        } else if (event.errorMessage != null && !event.approved) {
          // 타임아웃 또는 취소
          if (!_isConnected && mounted) {
            setState(() {
              _qrError = event.errorMessage;
            });
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingQr = false;
          _qrError = 'QR 세션을 생성하지 못했습니다: $e';
        });
      }
    }
  }

  /// 📂 Google Drive 내 수업자료 파일 목록 로드
  Future<void> _loadFiles() async {
    final token = BstCloudService.instance.activeToken;
    if (token == null || token.isEmpty) return;

    if (!mounted) return;
    setState(() => _isLoadingFiles = true);

    try {
      // bst-save(일반 자료), bst-tbp(스마트교과서), bst-pen(판서노트) 병렬 로드
      final results = await Future.wait([
        BstCloudService.instance.fetchFilesBySpecificFolder(
          accessToken: token,
          folderName: 'bst-save',
        ),
        BstCloudService.instance.fetchFilesBySpecificFolder(
          accessToken: token,
          folderName: 'bst-tbp',
        ),
        BstCloudService.instance.fetchFilesBySpecificFolder(
          accessToken: token,
          folderName: 'bst-pen',
        ),
      ]);

      final Map<String, BstCloudFile> fileMap = {};
      for (final list in results) {
        for (final file in list) {
          fileMap[file.id] = file;
        }
      }

      if (mounted) {
        setState(() {
          _allFiles = fileMap.values.toList();
          _applyFilter();
          _isLoadingFiles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFiles = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('파일 목록 갱신 오류: $e'),
            backgroundColor: const Color(0xFFEF4565),
          ),
        );
      }
    }
  }

  void _applyFilter() {
    List<BstCloudFile> list = _allFiles;

    // 카테고리 필터
    if (_selectedCategory == 'tbp') {
      list = list.where((f) {
        final l = f.name.toLowerCase();
        return l.endsWith('.tbp') ||
            l.endsWith('.htmlp') ||
            l.endsWith('.bsttbp') ||
            l.endsWith('.canva.bst') ||
            f.mimeType == 'application/x-bst-tbp-folder';
      }).toList();
    } else if (_selectedCategory == 'pdf') {
      list = list.where((f) => f.name.toLowerCase().endsWith('.pdf')).toList();
    } else if (_selectedCategory == 'ppt') {
      list = list.where((f) {
        final l = f.name.toLowerCase();
        return l.endsWith('.ppt') || l.endsWith('.pptx');
      }).toList();
    } else if (_selectedCategory == 'hwp') {
      list = list.where((f) {
        final l = f.name.toLowerCase();
        return l.endsWith('.hwp') || l.endsWith('.hwpx') || l.endsWith('.doc') || l.endsWith('.docx');
      }).toList();
    } else if (_selectedCategory == 'pen') {
      list = list.where((f) {
        final l = f.name.toLowerCase();
        return l.endsWith('.pen') || l.endsWith('.bstpen');
      }).toList();
    }

    // 검색어 필터
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((f) => f.name.toLowerCase().contains(q)).toList();
    }

    _filteredFiles = list;
  }

  /// 🚀 파일 클릭 시 원터치 뷰어 실행
  Future<void> _openFile(BstCloudFile file) async {
    final lower = file.name.toLowerCase();
    final token = BstCloudService.instance.activeToken ?? '';

    // 1. TBP / HTMLP 스마트교과서
    if (lower.endsWith('.tbp') ||
        lower.endsWith('.htmlp') ||
        lower.endsWith('.bsttbp') ||
        file.mimeType == 'application/x-bst-tbp-folder') {
      final isHtmlp = lower.endsWith('.htmlp');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TbpViewerRoute(
            tbpFilePath: 'drive://tbp/${file.id}',
            title: file.name,
            scaleFactor: 1.0,
            mode: isHtmlp ? TbpViewerMode.htmlp : TbpViewerMode.tbp,
          ),
        ),
      );
      return;
    }

    // 2. PDF 문서
    if (lower.endsWith('.pdf')) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF00F5D4)),
        ),
      );

      Uint8List? bytes;
      if (file.id.isNotEmpty && token.isNotEmpty) {
        bytes = await BstCloudService.instance.downloadDriveFileBytes(file.id, token);
      }
      if (mounted) Navigator.pop(context); // 로딩 닫기

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfBoardView(
              initialFilePath: file.name,
              pdfData: bytes,
              scaleFactor: 1.0,
            ),
          ),
        );
      }
      return;
    }

    // 3. 판서 노트
    if (lower.endsWith('.pen') || lower.endsWith('.bstpen')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BoardestPenView(
            filePath: file.name,
            scaleFactor: 1.0,
            teacher: _teacherName ?? '선생님',
            subject: '판서',
          ),
        ),
      );
      return;
    }

    // 4. PPT / HWP / 기타 문서
    final driveUrl = 'https://drive.google.com/file/d/${file.id}/view';
    await launchUrl(Uri.parse(driveUrl), mode: LaunchMode.externalApplication);
  }

  /// 🔒 클라우드 연결 해제
  void _disconnect() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: Row(
          children: [
            const Icon(Icons.logout_rounded, color: Color(0xFFEF4565)),
            const SizedBox(width: 10),
            Text(
              '클라우드 연결 해제',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          '현재 연결된 Cloud 세션을 종료하시겠습니까?\n종료 후 다시 사용하려면 스마트폰 QR 인증이 필요합니다.',
          style: GoogleFonts.notoSansKr(color: const Color(0xFF94A3B8), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              BstCloudService.instance.disconnect();
              setState(() {
                _isConnected = false;
                _teacherName = null;
                _ownerEmail = null;
                _allFiles = [];
                _filteredFiles = [];
              });
              _startQrSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4565),
              foregroundColor: Colors.white,
            ),
            child: const Text('연결 해제'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: SafeArea(
        child: _isConnected ? _buildCloudBrowser() : _buildQrLoginView(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. 미연결 상태: QR 로그인 메인 화면 (오직 QR만 제공, OTP 배제)
  // ─────────────────────────────────────────────────────────────
  Widget _buildQrLoginView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          width: 480,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFF00F5D4).withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: const Color(0xFF00F5D4).withValues(alpha: 0.12),
                blurRadius: 28,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 로고 & 타이틀
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00F5D4), Color(0xFF7F5AF0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.cloud_sync_rounded,
                  color: Colors.black87,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF00F5D4), Color(0xFFA78BFA)],
                ).createShader(bounds),
                child: Text(
                  'Boardest Cloud',
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '선생님의 수업 자료 클라우드 연결',
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 28),

              // QR 코드 카드
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.25),
                      blurRadius: 24,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: _isLoadingQr
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFF7F5AF0)),
                      )
                    : _qrPayload != null
                        ? QrImageView(
                            data: _qrPayload!,
                            version: QrVersions.auto,
                            size: 218,
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.white,
                          )
                        : const Center(
                            child: Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                          ),
              ),
              const SizedBox(height: 24),

              // 안내 문구 (QR 전용, 학교 인증 없이 모바일 즉시 승인)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF334155),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF00F5D4), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '스마트폰 카메라로 QR 코드를 스캔하세요',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Google 로그인 승인 즉시 수업 자료가 열립니다.',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 11,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 새로고침 버튼
              OutlinedButton.icon(
                onPressed: _startQrSession,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  'QR 코드 새로고침',
                  style: GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00F5D4),
                  side: const BorderSide(color: Color(0xFF00F5D4)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. 연결 완료 상태: 파일 브라우저 & 원터치 실행 화면
  // ─────────────────────────────────────────────────────────────
  Widget _buildCloudBrowser() {
    return Column(
      children: [
        _buildBrowserHeader(),
        _buildFilterToolbar(),
        Expanded(
          child: _isLoadingFiles
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00F5D4)),
                )
              : _filteredFiles.isEmpty
                  ? _buildEmptyState()
                  : _buildFileGrid(),
        ),
      ],
    );
  }

  Widget _buildBrowserHeader() {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B)),
        ),
      ),
      child: Row(
        children: [
          // 브랜드 로고
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00F5D4), Color(0xFF7F5AF0)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cloud_done_rounded, color: Colors.black87, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            'Boardest Cloud',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 20),

          // 연결 상태 뱃지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_teacherName ?? "선생님"}의 Cloud 연결됨',
                  style: GoogleFonts.notoSansKr(
                    color: const Color(0xFF34D399),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // 파일 새로고침 버튼
          IconButton(
            onPressed: _loadFiles,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8)),
            tooltip: '파일 새로고침',
          ),
          const SizedBox(width: 8),

          // 로그아웃 (연결 해제)
          OutlinedButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: Text(
              '연결 해제',
              style: GoogleFonts.notoSansKr(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEF4565),
              side: const BorderSide(color: Color(0xFFEF4565)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1120),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B)),
        ),
      ),
      child: Row(
        children: [
          // 검색창
          SizedBox(
            width: 280,
            height: 40,
            child: TextField(
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                  _applyFilter();
                });
              },
              style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: '파일명 검색...',
                hintStyle: GoogleFonts.notoSansKr(color: const Color(0xFF64748B), fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),

          // 카테고리 필터 칩들
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildCategoryChip('all', '전체 (${_allFiles.length})'),
                  _buildCategoryChip('tbp', '📘 TBP 스마트교과서'),
                  _buildCategoryChip('pdf', '📕 PDF 교재'),
                  _buildCategoryChip('ppt', '📙 프레젠테이션'),
                  _buildCategoryChip('hwp', '📄 문서(한글)'),
                  _buildCategoryChip('pen', '✏️ 판서 노트'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String category, String label) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        labelStyle: GoogleFonts.notoSansKr(
          color: isSelected ? Colors.black87 : const Color(0xFF94A3B8),
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
        ),
        backgroundColor: const Color(0xFF1E293B),
        selectedColor: const Color(0xFF00F5D4),
        checkmarkColor: Colors.black87,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? const Color(0xFF00F5D4) : Colors.transparent,
          ),
        ),
        onSelected: (val) {
          setState(() {
            _selectedCategory = category;
            _applyFilter();
          });
        },
      ),
    );
  }

  Widget _buildFileGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 화면 너비에 따른 열 수 계산 (최소 220px 너비)
        final crossAxisCount = (constraints.maxWidth / 220).floor().clamp(2, 6);

        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.95,
          ),
          itemCount: _filteredFiles.length,
          itemBuilder: (context, index) {
            final file = _filteredFiles[index];
            return _buildFileCard(file);
          },
        );
      },
    );
  }

  Widget _buildFileCard(BstCloudFile file) {
    final lower = file.name.toLowerCase();
    IconData iconData = Icons.insert_drive_file_rounded;
    Color iconColor = const Color(0xFF94A3B8);
    Color badgeColor = const Color(0xFF334155);
    String typeLabel = 'FILE';

    if (lower.endsWith('.tbp') || lower.endsWith('.htmlp') || lower.endsWith('.bsttbp') || file.mimeType == 'application/x-bst-tbp-folder') {
      iconData = Icons.menu_book_rounded;
      iconColor = const Color(0xFF00F5D4);
      badgeColor = const Color(0xFF00F5D4).withValues(alpha: 0.15);
      typeLabel = 'TBP';
    } else if (lower.endsWith('.pdf')) {
      iconData = Icons.picture_as_pdf_rounded;
      iconColor = const Color(0xFFEF4565);
      badgeColor = const Color(0xFFEF4565).withValues(alpha: 0.15);
      typeLabel = 'PDF';
    } else if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      iconData = Icons.slideshow_rounded;
      iconColor = const Color(0xFFFF8906);
      badgeColor = const Color(0xFFFF8906).withValues(alpha: 0.15);
      typeLabel = 'PPT';
    } else if (lower.endsWith('.hwp') || lower.endsWith('.hwpx') || lower.endsWith('.doc') || lower.endsWith('.docx')) {
      iconData = Icons.article_rounded;
      iconColor = const Color(0xFF3B82F6);
      badgeColor = const Color(0xFF3B82F6).withValues(alpha: 0.15);
      typeLabel = 'HWP';
    } else if (lower.endsWith('.pen') || lower.endsWith('.bstpen')) {
      iconData = Icons.draw_rounded;
      iconColor = const Color(0xFF10B981);
      badgeColor = const Color(0xFF10B981).withValues(alpha: 0.15);
      typeLabel = 'PEN';
    }

    final sizeStr = file.size != null && file.size! > 0
        ? '${(file.size! / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openFile(file),
        borderRadius: BorderRadius.circular(16),
        hoverColor: const Color(0xFF00F5D4).withValues(alpha: 0.08),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF1E293B),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 아이콘 및 뱃지
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(iconData, color: iconColor, size: 24),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      typeLabel,
                      style: GoogleFonts.outfit(
                        color: iconColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // 파일명
              Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),

              // 파일 크기 & 열기 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    sizeStr,
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF00F5D4).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '열기',
                          style: GoogleFonts.notoSansKr(
                            color: const Color(0xFF00F5D4),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF00F5D4),
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.folder_open_rounded,
              color: Color(0xFF64748B),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '클라우드 폴더(bst-save)에 수업 자료가 없습니다.',
            style: GoogleFonts.notoSansKr(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '스마트폰 또는 교사용 앱에서 수업자료를 업로드하면 실시간으로 표시됩니다.',
            style: GoogleFonts.notoSansKr(
              color: const Color(0xFF64748B),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadFiles,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('새로고침'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

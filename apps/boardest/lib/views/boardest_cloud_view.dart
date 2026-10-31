import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/bst_cloud_service.dart';
import '../services/passkey_service.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import 'boardest_pen_view.dart';
import 'pdf_board_view.dart';
import 'tbp/tbp_viewer_route.dart';

/// Boardest Cloud 전문형 웹 앱 메인 뷰 (bcld.web.app)
/// - 스마트보드 터치 키보드 친화적 초단축 도메인 (bcld)
/// - 순수 Cloud 수업자료 전용: QR 1초 모바일 승인, 실시간 Drive 파일 브라우징, 다이렉트 업로드 & 원터치 뷰어
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
  String? _schoolName;
  String? _schoolId;

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

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdateService.checkAndUpdate(context, silent: true);
      }
    });
  }

  @override
  void dispose() {
    _approvalSubscription?.cancel();
    if (_sessionId != null) {
      PasskeyService.instance.deleteSession(_sessionId!);
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialConnection() async {
    final activeToken = BstCloudService.instance.activeToken;
    if (activeToken != null && activeToken.isNotEmpty && !BstCloudService.instance.hasAuthError) {
      setState(() {
        _isConnected = true;
        _teacherName = BstCloudService.instance.activeTeacherName ?? '선생님';
        _ownerEmail = BstCloudService.instance.activeOwnerEmail;
      });
      await _loadFiles();
      if (!_isConnected || BstCloudService.instance.hasAuthError) {
        BstCloudService.instance.disconnect();
        if (mounted) {
          setState(() {
            _isConnected = false;
            _teacherName = null;
            _ownerEmail = null;
          });
          await _startQrSession();
        }
      }
    } else {
      BstCloudService.instance.disconnect();
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
      final isCloudMode = AppConfig.isCloudMode;
      String schoolName = 'Boardest Class Cloud (BCLD)';
      String roomName = '교실 전자칠판';
      String? schoolId;

      if (!isCloudMode) {
        try {
          final settings = await StorageService().getSettings();
          if (settings.selectedSchool != null && settings.selectedSchool!.name.isNotEmpty) {
            schoolName = settings.selectedSchool!.name;
          }
          if (settings.classNickname.isNotEmpty) {
            roomName = settings.classNickname;
          } else if (settings.selectedGrade > 0 && settings.selectedClass > 0) {
            roomName = '${settings.selectedGrade}학년 ${settings.selectedClass}반';
          }
          if (settings.schoolId.trim().isNotEmpty) {
            schoolId = settings.schoolId.trim().toLowerCase();
          }
        } catch (_) {}
      }

      final res = await PasskeyService.instance.createChallengeSession(
        schoolName: schoolName,
        roomName: roomName,
        schoolId: schoolId,
      );

      if (!mounted) return;
      setState(() {
        _sessionId = res.sessionId;
        _qrPayload = res.qrPayload;
        _isLoadingQr = false;
      });

      _approvalSubscription = PasskeyService.instance
          .listenForApproval(res.sessionId, expectedSchoolId: schoolId)
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
            _schoolName = event.schoolName;
            _schoolId = event.schoolId;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.black87),
                  const SizedBox(width: 8),
                  Text(
                    '🎉 ${_teacherName}님의 Cloud가 연결되었습니다!',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF00F5D4),
              behavior: SnackBarBehavior.floating,
            ),
          );

          await _loadFiles();
        } else if (event.errorMessage != null && !event.approved) {
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
          // 32자리 Hex 실체 폴더는 사용자 목록에서 제외 (.tbp.bst 포인터 파일만 표시)
          if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(file.name.trim())) continue;
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
      debugPrint('[BoardestCloudView] _loadFiles error: $e');
      if (mounted) {
        setState(() {
          _isLoadingFiles = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ 파일 목록을 불러오는 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.orangeAccent,
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
            l.endsWith('.tbp.bst') ||
            l.endsWith('.htmlp') ||
            l.endsWith('.htmlp.bst') ||
            l.endsWith('.bsttbp') ||
            l.endsWith('.canva.bst') ||
            l.endsWith('.canva') ||
            l.endsWith('.bstcanva') ||
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
        lower.endsWith('.tbp.bst') ||
        lower.endsWith('.htmlp') ||
        lower.endsWith('.htmlp.bst') ||
        lower.endsWith('.bsttbp') ||
        lower.endsWith('.canva.bst') ||
        lower.endsWith('.canva') ||
        lower.endsWith('.bstcanva') ||
        file.mimeType == 'application/x-bst-tbp-folder') {
      final isHtmlp = lower.endsWith('.htmlp') ||
          lower.endsWith('.htmlp.bst') ||
          lower.endsWith('.canva.bst') ||
          lower.endsWith('.canva') ||
          lower.endsWith('.bstcanva');
      if (kIsWeb && !isHtmlp) {
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
      if (mounted) Navigator.pop(context);

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

  /// 🗑️ 파일 삭제
  Future<void> _confirmDeleteFile(BstCloudFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4565)),
            const SizedBox(width: 8),
            Text(
              '파일 삭제 확인',
              style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ],
        ),
        content: Text(
          '[${file.name}]\nGoogle Drive에서 이 파일을 삭제하시겠습니까?',
          style: GoogleFonts.notoSansKr(color: const Color(0xFF94A3B8), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4565)),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await BstCloudService.instance.deleteDriveFile(file.id);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🗑️ [${file.name}] 파일이 삭제되었습니다.')),
        );
        await _loadFiles();
      }
    }
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
        child: Column(
          children: [
            ValueListenableBuilder<UpdateState>(
              valueListenable: UpdateService.stateNotifier,
              builder: (ctx, state, _) {
                if (state == UpdateState.downloaded) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF00F5D4), Color(0xFF7F5AF0)],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.system_update_alt_rounded, color: Colors.black, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '✨ Boardest Cloud 새 버전(v${UpdateService.latestVersion ?? '5.3.7'}) 다운로드 완료!',
                            style: GoogleFonts.notoSansKr(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        InkWell(
                          onTap: () => UpdateService.executeInstall(context),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '지금 즉시 업데이트 설치 (v${UpdateService.latestVersion ?? '5.3.7'})',
                              style: GoogleFonts.notoSansKr(color: const Color(0xFF00F5D4), fontSize: 12, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                if (state != UpdateState.downloading) return const SizedBox.shrink();
                return ValueListenableBuilder<double>(
                  valueListenable: UpdateService.downloadProgressNotifier,
                  builder: (c, progress, _) {
                    final pct = (progress * 100).toInt();
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF00F5D4), Color(0xFF7F5AF0)],
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '🚀 새 버전(${UpdateService.latestVersion ?? '5.3.7'}) 백그라운드 다운로드 중... ($pct%)',
                            style: GoogleFonts.notoSansKr(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: UpdateService.isCloudBlockedNotifier,
                builder: (context, isCloudBlocked, _) {
            if (isCloudBlocked) {
              return Center(
                child: Container(
                  width: 520,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141721),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFEF4565), width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, color: Color(0xFFEF4565), size: 54),
                      const SizedBox(height: 16),
                      Text(
                        'Cloud 기능을 사용하시려면 업데이트를 하시기 바랍니다.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00F5D4),
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () => UpdateService.executeInstall(context),
                          icon: const Icon(Icons.download_rounded, color: Colors.black),
                          label: const Text('업데이트 설치', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4565),
                            side: const BorderSide(color: Color(0xFFEF4565)),
                          ),
                          onPressed: () => UpdateService.uninstallApp(context),
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: const Text('앱 삭제'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
                return _isConnected ? _buildCloudBrowser() : _buildQrLoginView();
              },
            ),
          ),
        ],
      ),
    ),
  );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. 미연결 상태: QR 로그인 메인 화면 (터치 키보드 친화적 bcld.web.app)
  // ─────────────────────────────────────────────────────────────
  Widget _buildQrLoginView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          width: 500,
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
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 도메인 뱃지 (스마트보드 터치 4글자 안내)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flash_on_rounded, color: Color(0xFF00F5D4), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'bcld.web.app',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF00F5D4),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // BCLD 브랜드 로고
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00F5D4), Color(0xFF7F5AF0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.cloud_sync_rounded,
                  color: Colors.black87,
                  size: 38,
                ),
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 4),
              Text(
                '스마트 교실을 위한 클라우드 수업자료 허브',
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 24),

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
              const SizedBox(height: 20),

              // 안내 문구 (QR 전용, 학교 인증 없이 모바일 즉시 승인)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF334155)),
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
              const SizedBox(height: 18),

              // 새로고침 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                  if (!kIsWeb) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => UpdateService.uninstallApp(context),
                      icon: const Icon(Icons.delete_forever_rounded, size: 16),
                      label: Text(
                        '앱 삭제',
                        style: GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4565),
                        side: const BorderSide(color: Color(0xFFEF4565)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. 연결 완료 상태: Cloud 전문형 파일 브라우저
  // ─────────────────────────────────────────────────────────────
  Widget _buildCloudBrowser() {
    return Column(
      children: [
        _buildBrowserHeader(),
        _buildFilterToolbar(),
        Expanded(
          child: _isLoadingFiles
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF00F5D4)),
                      SizedBox(height: 16),
                      Text(
                        'Google Drive 수업 자료를 동기화하는 중...',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ),
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
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B)),
        ),
      ),
      child: Row(
        children: [
          // 브랜드 로고 & 도메인 칩
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00F5D4), Color(0xFF7F5AF0)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cloud_done_rounded, color: Colors.black87, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Boardest Cloud',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'BCLD',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF00F5D4),
                      ),
                    ),
                  ),
                ],
              ),
              if (_ownerEmail != null && _ownerEmail!.isNotEmpty)
                Text(
                  _ownerEmail!,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                  ),
                ),
            ],
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

          // 👁️ 교실 열람 전용 모드 뱃지 (사용자 지시: Bcld는 업로드 제거하고 열람만 가능)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF00F5D4).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.remove_red_eye_rounded, size: 14, color: Color(0xFF00F5D4)),
                const SizedBox(width: 6),
                Text(
                  '교실 열람 전용 (Read Only)',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF00F5D4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // 🌐 Google Drive 바로가기
          IconButton(
            onPressed: () {
              launchUrl(
                Uri.parse('https://drive.google.com/drive/my-drive'),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF94A3B8), size: 20),
            tooltip: '내 Google Drive 열기',
          ),

          // 새로고침
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
          // 스마트보드 터치 친화적 검색창
          SizedBox(
            width: 280,
            height: 42,
            child: TextField(
              controller: _searchController,
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
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Color(0xFF64748B), size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _applyFilter();
                          });
                        },
                      )
                    : null,
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
                  _buildCategoryChip('hwp', '📄 문서(한글/워드)'),
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
        // 스마트보드 터치 편의성을 고려한 최소 230px 타겟 너비
        final crossAxisCount = (constraints.maxWidth / 230).floor().clamp(2, 6);

        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
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

    if (lower.endsWith('.tbp') ||
        lower.endsWith('.tbp.bst') ||
        lower.endsWith('.htmlp') ||
        lower.endsWith('.htmlp.bst') ||
        lower.endsWith('.bsttbp') ||
        lower.endsWith('.canva.bst') ||
        lower.endsWith('.canva') ||
        lower.endsWith('.bstcanva') ||
        file.mimeType == 'application/x-bst-tbp-folder') {
      final isHtmlp = lower.endsWith('.htmlp') ||
          lower.endsWith('.htmlp.bst') ||
          lower.endsWith('.canva.bst') ||
          lower.endsWith('.canva') ||
          lower.endsWith('.bstcanva');
      iconData = isHtmlp ? Icons.co_present_rounded : Icons.menu_book_rounded;
      iconColor = const Color(0xFF00F5D4);
      badgeColor = const Color(0xFF00F5D4).withValues(alpha: 0.15);
      typeLabel = isHtmlp ? 'HTMLP' : 'TBP';
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
    } else if (lower.endsWith('.hwp') ||
        lower.endsWith('.hwpx') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.docx')) {
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
        borderRadius: BorderRadius.circular(18),
        hoverColor: const Color(0xFF00F5D4).withValues(alpha: 0.08),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF1E293B),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 아이콘 및 뱃지 + 우측 더보기 메뉴
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
                  Row(
                    children: [
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
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B), size: 18),
                        color: const Color(0xFF1E293B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (val) {
                          if (val == 'open') {
                            _openFile(file);
                          } else if (val == 'drive') {
                            launchUrl(
                              Uri.parse('https://drive.google.com/file/d/${file.id}/view'),
                              mode: LaunchMode.externalApplication,
                            );
                          } else if (val == 'delete') {
                            _confirmDeleteFile(file);
                          }
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'open',
                            child: Row(
                              children: [
                                Icon(Icons.play_circle_fill_rounded, color: Color(0xFF00F5D4), size: 16),
                                SizedBox(width: 8),
                                Text('열기', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'drive',
                            child: Row(
                              children: [
                                Icon(Icons.open_in_new_rounded, color: Color(0xFF94A3B8), size: 16),
                                SizedBox(width: 8),
                                Text('Google Drive에서 보기', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4565), size: 16),
                                SizedBox(width: 8),
                                Text('삭제', style: TextStyle(color: Color(0xFFEF4565), fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
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
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFF64748B),
              size: 52,
            ),
          ),
          const SizedBox(height: 18),
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
            '교사용 앱(Boardest Teacher) 또는 Google Drive에 업로드된 수업 자료가 여기에 안전하게 표시됩니다.',
            style: GoogleFonts.notoSansKr(
              color: const Color(0xFF64748B),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _loadFiles,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('수업 자료 새로고침'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00F5D4),
                  side: const BorderSide(color: Color(0xFF00F5D4)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

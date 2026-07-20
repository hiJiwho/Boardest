import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/bst_cloud_service.dart';
import '../services/auth_service.dart';
import '../views/boardbook_player.dart';
import '../views/pdf_board_view.dart';
import '../views/ppt_overlay_view.dart';
import '../views/video_board_view.dart';
import '../views/hwp_overlay_view.dart';

class BstCloudModal extends StatefulWidget {
  final double scaleFactor;
  const BstCloudModal({super.key, this.scaleFactor = 1.0});

  @override
  State<BstCloudModal> createState() => _BstCloudModalState();
}

class _BstCloudModalState extends State<BstCloudModal> {
  bool _loadingTeachers = true;
  List<BstCloudTeacher> _teachers = [];
  BstCloudTeacher? _selectedTeacher;
  String _status = 'none'; // 'none' | 'pending' | 'approved' | 'rejected' | 'error'
  Timer? _statusTimer;
  int _timeoutSeconds = 60;

  bool _loadingFiles = false;
  List<BstCloudFile> _driveFiles = [];
  String _classroomName = '교실';

  // 교사가 전송해 준 단기 세션 Access Token 및 폴더 ID
  String? _driveToken;
  String? _currentFolderId;

  // 다운로드 진행 모달 상태
  bool _downloading = false;
  String _downloadFileName = '';

  @override
  void initState() {
    super.initState();
    _loadClassroomName();
    _loadTeachers();
  }

  void _loadClassroomName() async {
    final user = await AuthService().getCurrentUser();
    if (user != null) {
      setState(() {
        _classroomName = '${user.grade}학년 ${user.classNum}반';
      });
    }
  }

  void _loadTeachers() async {
    setState(() => _loadingTeachers = true);
    final list = await BstCloudService.instance.getCloudTeachers();
    setState(() {
      _teachers = list;
      _loadingTeachers = false;
    });
  }

  void _startConnectionFlow(BstCloudTeacher teacher) async {
    setState(() {
      _selectedTeacher = teacher;
      _status = 'pending';
      _timeoutSeconds = 60;
    });

    final ok = await BstCloudService.instance.requestConnection(
      teacherName: teacher.teacherName,
      classroomName: _classroomName,
    );

    if (!ok) {
      setState(() => _status = 'error');
      return;
    }

    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_timeoutSeconds <= 0) {
        _cancelFlow();
        return;
      }
      _timeoutSeconds -= 3;

      final details = await BstCloudService.instance.getConnectionApprovedDetails(
        teacherName: teacher.teacherName,
        classroomName: _classroomName,
      );
      final currentStatus = details['status'] ?? 'pending';

      if (currentStatus == 'approved') {
        timer.cancel();
        _driveToken = details['token'];
        _currentFolderId = details['folderId'];
        BstCloudService.instance.activeToken = _driveToken;
        BstCloudService.instance.activeFolderId = _currentFolderId;
        setState(() {
          _status = 'approved';
        });
        if (_currentFolderId != null && _driveToken != null) {
          _loadDriveFiles(_currentFolderId!);
        }
      } else if (currentStatus == 'rejected') {
        timer.cancel();
        setState(() {
          _status = 'rejected';
        });
      }
    });
  }

  void _cancelFlow() {
    _statusTimer?.cancel();
    if (_selectedTeacher != null) {
      BstCloudService.instance.cancelConnection(
        teacherName: _selectedTeacher!.teacherName,
        classroomName: _classroomName,
      );
    }
    BstCloudService.instance.activeToken = null;
    BstCloudService.instance.activeFolderId = null;
    setState(() {
      _selectedTeacher = null;
      _status = 'none';
      _driveFiles = [];
      _driveToken = null;
      _currentFolderId = null;
      _downloading = false;
    });
  }

  void _loadDriveFiles(String folderId) async {
    if (_driveToken == null) return;
    setState(() {
      _loadingFiles = true;
      _currentFolderId = folderId;
    });
    final files = await BstCloudService.instance.fetchDriveFiles(folderId, _driveToken!);
    setState(() {
      _driveFiles = files;
      _loadingFiles = false;
    });
  }

  // 구글 드라이브 파일 클릭 시 보안 토큰 헤더 다운로드 처리 후 로컬에서 기동
  void _onFileClick(BstCloudFile file) async {
    final isFolder = file.mimeType == 'application/vnd.google-apps.folder';

    if (isFolder) {
      _loadDriveFiles(file.id);
      return;
    }

    if (_driveToken == null) return;

    // 1. 다운로드 시작 로딩 UI 출력
    setState(() {
      _downloading = true;
      _downloadFileName = file.name;
    });

    // 2. Google Drive API를 통한 고유 세션 토큰 인증 다운로드
    final localPath = await BstCloudService.instance.downloadDriveFile(
      file.id,
      file.name,
      _driveToken!,
    );

    setState(() {
      _downloading = false;
    });

    if (localPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파일을 다운로드할 수 없습니다. 세션이 만료되었을 수 있습니다.')),
        );
      }
      return;
    }

    // 3. 로컬에 저장된 임시 경로로 네이티브 칠판 뷰어 기동
    final ext = file.name.toLowerCase();

    if (ext.endsWith('.bb')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BoardBookPlayer(
            bbFilePath: localPath,
            scaleFactor: widget.scaleFactor,
          ),
        ),
      );
    } else if (ext.endsWith('.pdf')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfBoardView(
            initialFilePath: localPath,
            scaleFactor: widget.scaleFactor,
          ),
        ),
      );
    } else if (ext.endsWith('.pptx') || ext.endsWith('.ppt')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PptOverlayView(
            initialFilePath: localPath,
            scaleFactor: widget.scaleFactor,
          ),
        ),
      );
    } else if (ext.endsWith('.hwp')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HwpOverlayView(
            initialFilePath: localPath,
            scaleFactor: widget.scaleFactor,
          ),
        ),
      );
    } else if (['.mp4', '.mkv', '.avi', '.mov', '.wmv'].any((e) => ext.endsWith(e))) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoBoardView(
            filePath: localPath,
            scaleFactor: widget.scaleFactor,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    return Dialog(
      backgroundColor: const Color(0xFF13171F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.2),
      ),
      child: Container(
        width: 520 * s,
        height: 600 * s,
        padding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_done_rounded, color: const Color(0xFF7F5AF0), size: 28 * s),
                        const SizedBox(width: 8),
                        Text(
                          'bst-cloud 연동',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 18 * s,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () {
                        _cancelFlow();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 24),
                Expanded(
                  child: _buildContent(s),
                ),
              ],
            ),

            // 다운로드 로딩 오버레이
            if (_downloading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFF00F5D4)),
                        const SizedBox(height: 24),
                        Text(
                          '드라이브에서 안전하게 다운로드하는 중...',
                          style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * s, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _downloadFileName,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(double s) {
    if (_status == 'none') {
      return _buildTeacherList(s);
    } else if (_status == 'pending') {
      return _buildPendingUI(s);
    } else if (_status == 'approved') {
      return _buildFilesList(s);
    } else if (_status == 'rejected') {
      return _buildFeedbackUI('접속 요청이 거절되었습니다.', Icons.block_rounded, Colors.redAccent, s);
    } else {
      return _buildFeedbackUI('요청 처리 도중 네트워크 오류가 발생했습니다.', Icons.error_outline_rounded, Colors.amber, s);
    }
  }

  Widget _buildTeacherList(double s) {
    if (_loadingTeachers) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7F5AF0)));
    }

    if (_teachers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48 * s, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              '연동 설정이 완료된 교사가 없습니다.',
              style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 13 * s),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '수업을 진행할 담당 교사를 선택해 주세요.',
          style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * s),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: _teachers.length,
            itemBuilder: (context, idx) {
              final t = _teachers[idx];
              return Card(
                color: Colors.white.withOpacity(0.03),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(
                    '${t.teacherName} 선생님',
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14 * s),
                  ),
                  subtitle: Text(t.ownerEmail, style: const TextStyle(color: Colors.white30, fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                  onTap: () => _startConnectionFlow(t),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPendingUI(double s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF00F5D4)),
          const SizedBox(height: 24),
          Text(
            '${_selectedTeacher!.teacherName} 선생님 승인 대기 중',
            style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 15 * s, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            '선생님의 웹앱/스마트폰으로 승인 요청 팝업이 전송되었습니다.\n승인 대기 제한시간: $_timeoutSeconds초',
            style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * s, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white12),
            onPressed: _cancelFlow,
            child: const Text('취소하기'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesList(double s) {
    if (_loadingFiles) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)));
    }

    if (_driveFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_rounded, size: 44 * s, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              '구글 드라이브 폴더가 비어 있습니다.',
              style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 13 * s),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '${_selectedTeacher!.teacherName} 선생님의 cloud-connect 드라이브 (보안 연동)',
                style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * s),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.sync_rounded, color: Color(0xFF00F5D4), size: 18),
                  tooltip: '구글 드라이브 폴더 동기화',
                  onPressed: () {
                    if (_currentFolderId != null) {
                      _loadDriveFiles(_currentFolderId!);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🔄 구글 드라이브 폴더 동기화 완료!'), backgroundColor: Color(0xFF2EC4B6)),
                      );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white54, size: 18),
                  tooltip: '상위 폴더',
                  onPressed: () {
                    if (_selectedTeacher != null) {
                      _loadDriveFiles(_selectedTeacher!.folderId);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: _driveFiles.length,
            itemBuilder: (context, idx) {
              final f = _driveFiles[idx];
              final isFolder = f.mimeType == 'application/vnd.google-apps.folder';
              IconData icon;
              Color iconColor;

              if (isFolder) {
                icon = Icons.folder_rounded;
                iconColor = const Color(0xFFFF8E3C);
              } else if (f.name.endsWith('.pdf')) {
                icon = Icons.picture_as_pdf_rounded;
                iconColor = const Color(0xFFEF4565);
              } else if (f.name.endsWith('.bb')) {
                icon = Icons.auto_stories_rounded;
                iconColor = const Color(0xFF7F5AF0);
              } else {
                icon = Icons.insert_drive_file_rounded;
                iconColor = Colors.white54;
              }

              return Card(
                color: Colors.white.withOpacity(0.02),
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  leading: Icon(icon, color: iconColor),
                  title: Text(
                    f.name,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _onFileClick(f),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFeedbackUI(String message, IconData icon, Color color, double s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48 * s, color: color),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * s, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white12),
            onPressed: _cancelFlow,
            child: const Text('돌아가기'),
          ),
        ],
      ),
    );
  }
}

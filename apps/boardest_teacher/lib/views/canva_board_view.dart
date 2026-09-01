import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:webview_windows/webview_windows.dart';
import '../widgets/unified_pen_overlay.dart';
import '../services/app_paths.dart';
import '../services/cloud_drive_service.dart';
import '../services/bst_save_service.dart';
import '../helpers/iframe_view_helper.dart';

class CanvaBoardView extends StatefulWidget {
  final String? embedUrl;
  final String? title;
  final double scaleFactor;
  final String? initialUrl;
  final String? filePath;

  const CanvaBoardView({
    super.key,
    this.embedUrl,
    this.title,
    this.scaleFactor = 1.0,
    this.initialUrl,
    this.filePath,
  });

  static String formatCanvaEmbedUrl(String rawUrl) {
    if (rawUrl.contains('/view?embed')) return rawUrl;
    if (rawUrl.contains('/edit')) {
      return rawUrl.replaceAll('/edit', '/view?embed');
    }
    if (rawUrl.contains('/view')) {
      return rawUrl.replaceAll('/view', '/view?embed');
    }
    return rawUrl.endsWith('/') ? '${rawUrl}view?embed' : '$rawUrl/view?embed';
  }

  @override
  State<CanvaBoardView> createState() => _CanvaBoardViewState();
}

class _CanvaBoardViewState extends State<CanvaBoardView> {
  WebviewController? _winController;
  bool _isReady = false;
  String? _error;
  String _effectiveUrl = '';

  @override
  void initState() {
    super.initState();
    _effectiveUrl = widget.embedUrl ?? widget.initialUrl ?? '';
    _initWebview();
  }

  Future<void> _initWebview() async {
    if (_effectiveUrl.isEmpty) {
      setState(() => _isReady = true);
      return;
    }

    if (kIsWeb) {
      setState(() => _isReady = true);
      return;
    }

    if (Platform.isWindows) {
      try {
        _winController = WebviewController();
        await _winController!.initialize();
        await _winController!.loadUrl(_effectiveUrl);
        if (mounted) {
          setState(() {
            _isReady = true;
          });
        }
      } catch (e) {
        setState(() {
          _error = e.toString();
        });
      }
    } else {
      setState(() => _isReady = true);
    }
  }

  void _showSaveDestinationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Canva 수업 자료 저장 위치 선택',
          style: GoogleFonts.notoSansKr(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSaveOption(
              icon: Icons.cloud_upload_rounded,
              title: 'Boardest Cloud (Drive) 백업',
              subtitle: '구글 드라이브(bst-save)에 백업하여 교실 전자칠판과 연동',
              color: const Color(0xFF00F5D4),
              onTap: () {
                Navigator.pop(ctx);
                _performSave('cloud');
              },
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 12),
              _buildSaveOption(
                icon: Icons.usb_rounded,
                title: 'USB 저장',
                subtitle: '연결된 USB 교과목 폴더에 .bstcanva 보관',
                color: const Color(0xFF2EC4B6),
                onTap: () {
                  Navigator.pop(ctx);
                  _performSave('usb');
                },
              ),
              const SizedBox(height: 12),
              _buildSaveOption(
                icon: Icons.computer_rounded,
                title: '로컬 PC에 저장',
                subtitle: '내 문서/Boardest/CanvaDesigns 폴더에 보관',
                color: const Color(0xFF7F5AF0),
                onTap: () {
                  Navigator.pop(ctx);
                  _performSave('local');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSaveOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performSave([String? mode]) async {
    final title = widget.title ?? 'Canva presentation';
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    final jsonMap = {
      'title': title,
      'embedUrl': widget.embedUrl ?? widget.initialUrl ?? _effectiveUrl,
      'savedAt': DateTime.now().toIso8601String(),
    };
    final content = jsonEncode(jsonMap);
    final bytes = Uint8List.fromList(utf8.encode(content));

    try {
      final cloud = CloudDriveService.instance;
      if (!cloud.isLoggedIn) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Canva는 Cloud 전용 기능입니다. 먼저 Cloud에 로그인해 주세요.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        return;
      }

      final canvaRootId = await cloud.getOrCreateCanvaFolder();
      if (canvaRootId == null) {
        throw Exception('Google Drive /bst-canva 폴더 생성에 실패했습니다.');
      }

      // /bst-canva/ 아래에 해당 프로젝트 전용 폴더 생성/확인
      final existingProjects = await cloud.fetchDriveFoldersInParent(canvaRootId);
      var projectFolder = existingProjects.where((f) => f.name == safeTitle).firstOrNull;
      String projectFolderId;
      if (projectFolder != null) {
        projectFolderId = projectFolder.id;
      } else {
        final newId = await cloud.createFolderInDrive(safeTitle, parentFolderId: canvaRootId);
        if (newId == null) throw Exception('프로젝트 폴더 생성 실패');
        projectFolderId = newId;
      }

      // 1. canvas.json 저장
      final ok = await cloud.uploadBytesToDrive(bytes, 'canvas.json', folderId: projectFolderId);
      
      // 2. pen_data.json 확인 및 저장
      final existingPen = await cloud.fetchProjectPenData(projectFolderId);
      if (existingPen == null) {
        await cloud.saveProjectPenData(projectFolderId, {'strokes': [], 'updatedAt': DateTime.now().toIso8601String()});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '☁️ [$safeTitle] Canva 프로젝트가 Drive(/bst-canva/)에 저장되었습니다!' : '⚠️ Drive 저장 실패'),
            backgroundColor: ok ? const Color(0xFF2EC4B6) : Colors.orangeAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Canva Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 오류: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  void dispose() {
    _winController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Canva Viewer Error: $_error',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    if (!_isReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2EC4B6)),
        ),
      );
    }

    Widget contentWidget;
    if (kIsWeb) {
      contentWidget = getIframeViewWidget('canva-view-${_effectiveUrl.hashCode}', _effectiveUrl);
    } else if (Platform.isWindows && _winController != null) {
      contentWidget = Webview(_winController!);
    } else {
      contentWidget = getIframeViewWidget('canva-view-${_effectiveUrl.hashCode}', _effectiveUrl);
    }

    return UnifiedPenOverlay(
      title: widget.title ?? 'Canva Presentation',
      onClose: () => Navigator.pop(context),
      onSave: _showSaveDestinationDialog,
      child: contentWidget,
    );
  }
}

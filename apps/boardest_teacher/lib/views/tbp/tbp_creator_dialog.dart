import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';

import '../../services/tbp/tbp_storage_service.dart';
import '../../services/bst_save_service.dart';
import '../../services/cloud_drive_service.dart';

/// TextBook Plus (.TBP) 새 교과서 패키지 생성 다이얼로그
class TbpCreatorDialog extends StatefulWidget {
  final double scaleFactor;
  const TbpCreatorDialog({super.key, required this.scaleFactor});

  @override
  State<TbpCreatorDialog> createState() => _TbpCreatorDialogState();
}

class _TbpCreatorDialogState extends State<TbpCreatorDialog> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _webUrlController = TextEditingController();
  final TextEditingController _specialRoomController = TextEditingController();
  final TextEditingController _targetDirController = TextEditingController();

  int _grade = 3;
  int _classNum = 1;
  bool _isSpecialRoom = false;
  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initDefaultTargetDir();
  }

  Future<void> _initDefaultTargetDir() async {
    if (kIsWeb) {
      setState(() {
        _targetDirController.text = 'Google Drive (Bst-save)';
      });
      return;
    }
    try {
      final boardDir = await BstSaveService.instance.directoryFor(
        BstSaveService.subBoard,
      );
      setState(() {
        _targetDirController.text = boardDir.path;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleController.dispose();
    _webUrlController.dispose();
    _specialRoomController.dispose();
    _targetDirController.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    if (kIsWeb) return;
    final selected = await FilePicker.getDirectoryPath();
    if (selected != null && selected.isNotEmpty) {
      setState(() {
        _targetDirController.text = selected;
      });
    }
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final cloud = CloudDriveService.instance;
      if (!cloud.isLoggedIn) {
        setState(() {
          _errorMessage = 'TextBookPro는 Cloud(Google Drive) 전용 기능입니다. 먼저 Cloud에 로그인해 주세요.';
          _isCreating = false;
        });
        return;
      }

      final title = _titleController.text.trim();
      final webUrl = _webUrlController.text.trim();
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final specialRoom = _isSpecialRoom ? _specialRoomController.text.trim() : null;

      final metaData = {
        'version': '2.0.0',
        'title': title,
        'grade': _grade,
        'classNum': _isSpecialRoom ? null : _classNum,
        'specialRoom': specialRoom,
        'webUrl': webUrl,
        'pagesCount': 0,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final tbpRootId = await cloud.getOrCreateTextbookProFolder();
      if (tbpRootId == null) {
        throw Exception('Google Drive /bst-textbookpro 폴더를 찾을 수 없습니다.');
      }

      // /bst-textbookpro/ 아래 프로젝트 전용 폴더 생성
      final existingProjects = await cloud.fetchDriveFoldersInParent(tbpRootId);
      var projectFolder = existingProjects.where((f) => f.name == safeTitle).firstOrNull;
      String projectFolderId;
      if (projectFolder != null) {
        projectFolderId = projectFolder.id;
      } else {
        final newId = await cloud.createFolderInDrive(safeTitle, parentFolderId: tbpRootId);
        if (newId == null) throw Exception('프로젝트 폴더 생성 실패');
        projectFolderId = newId;
      }

      // 1. manifest.json 업로드
      final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(metaData)));
      await cloud.uploadBytesToDrive(manifestBytes, 'manifest.json', folderId: projectFolderId);

      // 2. hotspots.json 초기화 업로드
      final hotspotsBytes = Uint8List.fromList(utf8.encode(jsonEncode({'hotspots': []})));
      await cloud.uploadBytesToDrive(hotspotsBytes, 'hotspots.json', folderId: projectFolderId);

      // 3. pen_data.json 초기화 업로드
      await cloud.saveProjectPenData(projectFolderId, {'strokes': [], 'updatedAt': DateTime.now().toIso8601String()});

      if (mounted) {
        Navigator.of(context).pop(safeTitle);
      }
    } catch (e) {
      debugPrint('TBP Creator Error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'TBP 프로젝트 생성 오류: $e';
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final accentColor = Theme.of(context).primaryColor;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.15),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.auto_stories_rounded,
                        color: accentColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '📚 새 TextBook Plus (.TBP) 생성',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 18 * s,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4565).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.notoSansKr(
                        color: const Color(0xFFEF4565),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 1. 교과서 제목
                _buildLabel('교과서 제목'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _titleController,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '교과서 제목을 입력해 주세요.'
                      : null,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  decoration: _inputDecoration('예: 국어3-지학사'),
                ),
                const SizedBox(height: 16),

                // 2. 전자저작물 Web URL
                _buildLabel('전자저작물 웹 주소 (HTML5 Web URL)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _webUrlController,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '웹 주소를 입력해 주세요.' : null,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  decoration: _inputDecoration(
                    'https://ebook.example.com/viewer.html',
                  ),
                ),
                const SizedBox(height: 16),

                // 3. 대상 학년 선택 (반 선택 제외)
                _buildLabel('대상 학년'),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value: _grade,
                  dropdownColor: const Color(0xFF1E1E24),
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  decoration: _inputDecoration(''),
                  items: [1, 2, 3, 4, 5, 6]
                      .map(
                        (g) => DropdownMenuItem(value: g, child: Text('$g학년')),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _grade = val);
                  },
                ),
                const SizedBox(height: 16),

                // 4. 저장 위치 지정 (Cloud 전용 안내)
                _buildLabel('저장 위치'),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E24),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF242629)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_done_rounded, color: Color(0xFF00F5D4), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Google Drive /bst-textbookpro/ (클라우드 전용)',
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        '취소',
                        style: GoogleFonts.notoSansKr(color: Colors.white38),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isCreating ? null : _handleCreate,
                      icon: _isCreating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: Text(
                        _isCreating ? '생성 중...' : 'Cloud TBP 프로젝트 생성',
                        style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.notoSansKr(
        color: Colors.white54,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.notoSansKr(color: Colors.white24, fontSize: 12),
      fillColor: Colors.white.withOpacity(0.04),
      filled: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
    );
  }
}

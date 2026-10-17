import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

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
      final title = _titleController.text.trim();
      var webUrl = _webUrlController.text.trim();
      if (!webUrl.startsWith('http://') && !webUrl.startsWith('https://')) {
        webUrl = 'https://$webUrl';
      }
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final folderName = safeTitle.toLowerCase().endsWith('.tbp') ? safeTitle : '$safeTitle.tbp';
      final specialRoom = _isSpecialRoom ? _specialRoomController.text.trim() : null;

      String? projectFolderId;
      if (cloud.isLoggedIn) {
        final tbpRootId = await cloud.getOrCreateTextbookProFolder();
        if (tbpRootId != null) {
          final existingProjects = await cloud.fetchDriveFoldersInParent(tbpRootId);
          final projectFolder = existingProjects
              .where((f) => f.name == folderName || f.name == safeTitle)
              .firstOrNull;
          if (projectFolder != null) {
            projectFolderId = projectFolder.id;
          } else {
            projectFolderId = await cloud.createFolderInDrive(folderName, parentFolderId: tbpRootId);
          }
        }
      }

      final fallbackFolderId = projectFolderId ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
      final fullMeta = <String, dynamic>{
        'version': '2.0.0',
        'title': title,
        'grade': _grade,
        'classNum': _isSpecialRoom ? null : _classNum,
        'specialRoom': specialRoom,
        'webUrl': webUrl,
        'pagesCount': 0,
        'folderId': fallbackFolderId,
        'createdAt': DateTime.now().toIso8601String(),
      };
      final metaJsonStr = jsonEncode(fullMeta);

      // 1. Cloud 연동 상태면 Google Drive /bst-tbs/<title>.tbp 폴더에 메타 파일 업로드
      if (projectFolderId != null && projectFolderId.isNotEmpty) {
        await cloud.saveTbpFolderFileText(projectFolderId, 'manifest.json', metaJsonStr);
        await cloud.saveTbpFolderFileText(projectFolderId, 'meta.bstsave', metaJsonStr);
        await cloud.saveTbpFolderFileText(projectFolderId, 'info.json', metaJsonStr);
      }

      // 2. 로컬/Web 경로에도 .tbp 폴더 구조 생성 및 즉시 캐싱
      String? localTbpDirPath;
      if (kIsWeb) {
        localTbpDirPath = projectFolderId != null ? null : 'web://tbp/$folderName';
      } else {
        final baseDir = _targetDirController.text.trim();
        if (baseDir.isNotEmpty && !baseDir.startsWith('Google Drive')) {
          localTbpDirPath = p.join(baseDir, folderName);
        } else {
          final boardDir = await BstSaveService.instance.directoryFor(BstSaveService.subBoard);
          localTbpDirPath = p.join(boardDir.path, folderName);
        }
      }

      final resultPath = await TbpStorageService.instance.registerCreatedTbpProject(
        meta: fullMeta,
        driveFolderId: projectFolderId,
        localDirPath: localTbpDirPath,
      );

      if (mounted) {
        Navigator.of(context).pop(resultPath);
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
    final isCloudLoggedIn = CloudDriveService.instance.isLoggedIn;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📚 새 TextBook Plus (.TBP) 생성',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white,
                              fontSize: 18 * s,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '우클릭으로 웹/문서/영상/타이머/메모 핫스팟을 꽂아 수업 교안을 제작합니다.',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white54,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
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
                _buildLabel('교과서 / 단원 제목'),
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
                  decoration: _inputDecoration('예: 국어3-지학사 2단원'),
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

                // 3. 대상 학년 선택
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

                // 4. 저장 위치 안내 (Cloud + 로컬 폴더 동시 지원)
                _buildLabel('저장 위치 (폴더형 .tbp)'),
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
                      Icon(
                        isCloudLoggedIn ? Icons.cloud_done_rounded : Icons.folder_special_rounded,
                        color: const Color(0xFF00F5D4),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isCloudLoggedIn
                              ? 'Google Drive (/bst-tbs/<제목>.tbp 폴더) + 로컬 캐시 자동 저장'
                              : (kIsWeb
                                  ? '브라우저 세션 저장 (Cloud 연동 시 Google Drive 자동 동기화)'
                                  : _targetDirController.text),
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _pickDirectory,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '폴더 변경',
                              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        ),
                      ],
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
                          : const Icon(Icons.create_new_folder_rounded, size: 18),
                      label: Text(
                        _isCreating ? '생성 중...' : 'TBP 생성 및 저작 시작',
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

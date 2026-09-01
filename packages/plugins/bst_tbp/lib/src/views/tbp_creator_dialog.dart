import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/tbp_storage_service.dart';

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
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(p.join(docDir.path, 'Boardest', 'TBP'));
      if (!targetDir.existsSync()) {
        await targetDir.create(recursive: true);
      }
      setState(() {
        _targetDirController.text = targetDir.path;
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
    final selected = await FilePicker.getDirectoryPath();
    if (selected != null && selected.isNotEmpty) {
      setState(() {
        _targetDirController.text = selected;
      });
    }
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;
    if (_targetDirController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = '저장 위치 폴더를 지정해 주세요.';
      });
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final title = _titleController.text.trim();
      final webUrl = _webUrlController.text.trim();
      final targetDir = _targetDirController.text.trim();
      final specialRoom = _isSpecialRoom
          ? _specialRoomController.text.trim()
          : null;

      final folderId = DateTime.now().millisecondsSinceEpoch.toString();
      final metaData = {
        'version': '1.0.0',
        'folderId': folderId,
        'title': title,
        'grade': _grade,
        'classNum': _isSpecialRoom ? null : _classNum,
        'specialRoom': specialRoom,
        'webUrl': webUrl,
      };

      final tempDir = await Directory.systemTemp.createTemp('tbp_create_');
      final metaFile = File(p.join(tempDir.path, 'meta.bstsave'));
      await metaFile.writeAsString(jsonEncode(metaData));
      final infoFile = File(p.join(tempDir.path, 'info.json'));
      await infoFile.writeAsString(jsonEncode(metaData));

      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final outputBstTbpPath = p.join(targetDir, '$safeTitle.bstTBP');

      final success = await TbpStorageService.instance.packageBstTbp(
        sourceFolderPath: tempDir.path,
        outputBstTbpPath: outputBstTbpPath,
      );

      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}

      if (success && mounted) {
        Navigator.of(context).pop(outputBstTbpPath); // 생성된 .bstTBP 파일 경로 반환
      } else {
        setState(() {
          _errorMessage = '.TBP 패키지 생성 실패. 저장 위치 경로 권한을 확인해 주세요.';
          _isCreating = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '패키지 생성 중 오류 발생: $e';
        _isCreating = false;
      });
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

                // 4. 저장 위치 지정
                _buildLabel('패키지 저장 폴더 위치'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _targetDirController,
                        readOnly: true,
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        decoration: _inputDecoration('저장 폴더'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.folder_open_rounded, color: accentColor),
                      onPressed: _pickDirectory,
                      tooltip: '폴더 선택',
                    ),
                  ],
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
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _isCreating ? '생성 중...' : '.bstTBP 생성하기',
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

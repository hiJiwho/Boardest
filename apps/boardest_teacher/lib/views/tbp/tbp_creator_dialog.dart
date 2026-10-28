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

/// TBP & HTML Present 통합 교안 생성 및 등록 다이얼로그
/// 1. TBP와 HTMLp를 하나로 통합하여 제목과 Web URL을 즉시 입력
/// 2. 파일 드래그앤드롭 / 업로드 상자를 통해 기존 교안 패키지(.tbp, .htmlp, .save, .bst) 복원 지원
/// 3. 대상 학년 제거 & 더미 포인터(.tbp.bst) 저장 위치 지정 (찐 데이터는 bst-tbp에 32자리 고유 ID로 별개 저장)
class TbpCreatorDialog extends StatefulWidget {
  final double scaleFactor;
  final String? initialUrl;
  final String? initialTitle;

  const TbpCreatorDialog({
    super.key,
    required this.scaleFactor,
    this.initialUrl,
    this.initialTitle,
  });

  @override
  State<TbpCreatorDialog> createState() => _TbpCreatorDialogState();
}

class _TbpCreatorDialogState extends State<TbpCreatorDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _webUrlController;
  final TextEditingController _targetDirController = TextEditingController();

  bool _isCreating = false;
  String? _errorMessage;
  String? _droppedFileName;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _webUrlController = TextEditingController(text: widget.initialUrl ?? '');
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
      if (mounted) {
        setState(() {
          _targetDirController.text = boardDir.path;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleController.dispose();
    _webUrlController.dispose();
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

  Future<void> _pickExistingFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tbp', 'htmlp', 'save', 'bst', 'json'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _droppedFileName = file.name;
        });

        // 파일 이름에서 제목 추출
        String baseName = file.name;
        for (final ext in ['.tbp.bst', '.htmlp.bst', '.tbp.save', '.htmlp.save', '.tbp', '.htmlp', '.save', '.bst', '.json']) {
          if (baseName.toLowerCase().endsWith(ext)) {
            baseName = baseName.substring(0, baseName.length - ext.length);
            break;
          }
        }
        if (_titleController.text.trim().isEmpty) {
          _titleController.text = baseName;
        }

        // 파일 내용 파싱하여 URL 및 메타데이터 복원
        if (file.bytes != null) {
          try {
            final jsonStr = utf8.decode(file.bytes!);
            final data = jsonDecode(jsonStr);
            if (data is Map) {
              final url = data['webUrl'] ?? data['url'] ?? data['embedUrl'];
              if (url != null && url.toString().isNotEmpty && _webUrlController.text.trim().isEmpty) {
                _webUrlController.text = url.toString();
              }
              final title = data['title'] ?? data['name'];
              if (title != null && title.toString().isNotEmpty) {
                _titleController.text = title.toString();
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[TbpCreatorDialog] File pick error: $e');
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
      if (webUrl.isNotEmpty && !webUrl.startsWith('http://') && !webUrl.startsWith('https://')) {
        webUrl = 'https://$webUrl';
      }
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final new32Id = CloudDriveService.generate32DigitId();
      final shellFileName = '$safeTitle.tbp.bst';

      final fullMeta = <String, dynamic>{
        'version': '5.3.3',
        'id': new32Id,
        'folderId': new32Id,
        'title': safeTitle,
        'type': 'TBP',
        'webUrl': webUrl,
        'pagesCount': 0,
        'createdAt': DateTime.now().toIso8601String(),
      };
      final metaJsonStr = jsonEncode(fullMeta);

      // 1. Google Drive 연동 상태일 때:
      // (1) 찐 데이터: bst-tbp에 32자리 ID 폴더 생성 + manifest.json 저장
      // (2) 더미 데이터: bst-save에 .tbp.bst 포인터 파일 업로드 -> 파일 관리에 즉시 노출!
      String? realFolderId;
      if (cloud.isLoggedIn) {
        final tbpRootId = await cloud.getOrCreateTextbookProFolder();
        if (tbpRootId != null) {
          realFolderId = await cloud.createFolderInDrive(new32Id, parentFolderId: tbpRootId);
          if (realFolderId != null) {
            fullMeta['folderId'] = realFolderId;
            final updatedMetaStr = jsonEncode(fullMeta);
            await cloud.uploadBytesToDrive(
              Uint8List.fromList(utf8.encode(updatedMetaStr)),
              'manifest.json',
              folderId: realFolderId,
            );
            await cloud.uploadBytesToDrive(
              Uint8List.fromList(utf8.encode(updatedMetaStr)),
              'meta.bstsave',
              folderId: realFolderId,
            );
          }
        }

        // 더미 포인터 파일 bst-save에 생성
        final saveRootId = await cloud.getOrCreateConnectFolder();
        final shellJson = jsonEncode({
          'type': 'TBP',
          'id': new32Id,
          'folderId': realFolderId ?? new32Id,
          'title': safeTitle,
          'webUrl': webUrl,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'version': '5.3.3',
        });
        await cloud.uploadBytesToDrive(
          Uint8List.fromList(utf8.encode(shellJson)),
          shellFileName,
          folderId: saveRootId,
        );
      }

      // 2. 로컬 파일 시스템에 더미 포인터 파일 (.tbp.bst) 저장
      String? localDummyPath;
      if (!kIsWeb) {
        final baseDir = _targetDirController.text.trim();
        final dir = (baseDir.isNotEmpty && !baseDir.startsWith('Google Drive'))
            ? Directory(baseDir)
            : await BstSaveService.instance.directoryFor(BstSaveService.subBoard);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        final dummyFile = File(p.join(dir.path, shellFileName));
        await dummyFile.writeAsString(jsonEncode({
          'type': 'TBP',
          'id': new32Id,
          'folderId': realFolderId ?? new32Id,
          'title': safeTitle,
          'webUrl': webUrl,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'version': '5.3.3',
        }));
        localDummyPath = dummyFile.path;
      }

      // 3. TbpStorageService에 등록
      final resultPath = await TbpStorageService.instance.registerCreatedTbpProject(
        meta: fullMeta,
        driveFolderId: realFolderId ?? new32Id,
        localDirPath: localDummyPath,
      );

      if (mounted) {
        Navigator.of(context).pop(localDummyPath ?? resultPath);
      }
    } catch (e) {
      debugPrint('[TbpCreatorDialog] Error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '교안 생성 오류: $e';
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final accentColor = const Color(0xFF00F5D4);
    final isCloudLoggedIn = CloudDriveService.instance.isLoggedIn;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 580 * s,
        padding: EdgeInsets.all(26 * s),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(24 * s),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.12),
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
                // 헤더
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10 * s),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12 * s),
                      ),
                      child: Icon(
                        Icons.auto_stories_rounded,
                        color: accentColor,
                        size: 24 * s,
                      ),
                    ),
                    SizedBox(width: 14 * s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '✨ TBP & HTML Present 통합 교안 생성',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white,
                              fontSize: 18 * s,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2 * s),
                          Text(
                            'Canva, 슬라이드, 웹 교안 URL과 인터랙티브 핫스팟이 결합된 수업 자료를 제작합니다.',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white54,
                              fontSize: 11.5 * s,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20 * s),

                if (_errorMessage != null) ...[
                  Container(
                    padding: EdgeInsets.all(10 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4565).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8 * s),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.notoSansKr(
                        color: const Color(0xFFEF4565),
                        fontSize: 12 * s,
                      ),
                    ),
                  ),
                  SizedBox(height: 12 * s),
                ],

                // 1. 교안 제목
                _buildLabel('교안 제목'),
                SizedBox(height: 6 * s),
                TextFormField(
                  controller: _titleController,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '교안 제목을 입력해 주세요.'
                      : null,
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * s),
                  decoration: _inputDecoration('예: 3학년 국어 - 2단원 핵심 발표 교안'),
                ),
                SizedBox(height: 16 * s),

                // 2. 전자저작물 / Canva Web URL
                _buildLabel('웹 교안 주소 (Canva, Google Slides, 전자저작물 URL)'),
                SizedBox(height: 6 * s),
                TextFormField(
                  controller: _webUrlController,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '웹 주소를 입력해 주세요.' : null,
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * s),
                  decoration: _inputDecoration('https://www.canva.com/design/... 또는 웹 주소'),
                ),
                SizedBox(height: 16 * s),

                // 3. 업로드 및 드래그 앤 드롭 박스
                _buildLabel('기존 교안 업로드 (선택)'),
                SizedBox(height: 6 * s),
                InkWell(
                  onTap: _pickExistingFile,
                  borderRadius: BorderRadius.circular(12 * s),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 18 * s, horizontal: 16 * s),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(12 * s),
                      border: Border.all(
                        color: _droppedFileName != null ? accentColor : Colors.white.withOpacity(0.12),
                        style: BorderStyle.solid,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _droppedFileName != null ? Icons.check_circle_rounded : Icons.cloud_upload_outlined,
                          color: _droppedFileName != null ? accentColor : Colors.white54,
                          size: 28 * s,
                        ),
                        SizedBox(height: 8 * s),
                        Text(
                          _droppedFileName != null
                              ? '선택된 파일: $_droppedFileName'
                              : '기존 교안 파일(.tbp, .htmlp, .save, .bst)을 드래그하거나 클릭하여 선택',
                          style: GoogleFonts.notoSansKr(
                            color: _droppedFileName != null ? accentColor : Colors.white70,
                            fontSize: 12 * s,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4 * s),
                        Text(
                          '파일 정보를 자동으로 읽어 제목과 URL을 채워 넣습니다.',
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white38,
                            fontSize: 11 * s,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16 * s),

                // 4. 더미 포인터 (.tbp.bst) 저장 위치
                _buildLabel('더미 포인터 (.tbp.bst) 저장 위치'),
                SizedBox(height: 6 * s),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 12 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E24),
                    borderRadius: BorderRadius.circular(10 * s),
                    border: Border.all(color: const Color(0xFF242629)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCloudLoggedIn ? Icons.cloud_done_rounded : Icons.folder_special_rounded,
                        color: accentColor,
                        size: 18 * s,
                      ),
                      SizedBox(width: 8 * s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isCloudLoggedIn
                                  ? 'Google Drive (bst-save) + 로컬 폴더 동시 저장'
                                  : (kIsWeb
                                      ? '브라우저 세션 저장'
                                      : _targetDirController.text),
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white,
                                fontSize: 12 * s,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '더미 포인터(.tbp.bst)만 저장되며, 찐 데이터는 TBP 클라우드(bst-tbp)에 별개 보관됩니다.',
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white38,
                                fontSize: 10.5 * s,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!kIsWeb) ...[
                        SizedBox(width: 8 * s),
                        InkWell(
                          onTap: _pickDirectory,
                          borderRadius: BorderRadius.circular(6 * s),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6 * s),
                            ),
                            child: Text(
                              '폴더 변경',
                              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 11 * s),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 24 * s),

                // 버튼
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
                    SizedBox(width: 8 * s),
                    ElevatedButton.icon(
                      onPressed: _isCreating ? null : _handleCreate,
                      icon: _isCreating
                          ? SizedBox(
                              width: 16 * s,
                              height: 16 * s,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Icon(Icons.rocket_launch_rounded, size: 18 * s, color: Colors.black),
                      label: Text(
                        _isCreating ? '생성 및 등록 중...' : '교안 생성 & 시작',
                        style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        padding: EdgeInsets.symmetric(
                          horizontal: 20 * s,
                          vertical: 12 * s,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10 * s),
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
        color: Colors.white70,
        fontSize: 12 * widget.scaleFactor,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.notoSansKr(color: Colors.white24, fontSize: 12 * widget.scaleFactor),
      fillColor: Colors.white.withOpacity(0.04),
      filled: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 14 * widget.scaleFactor, vertical: 12 * widget.scaleFactor),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10 * widget.scaleFactor),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10 * widget.scaleFactor),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10 * widget.scaleFactor),
        borderSide: const BorderSide(color: Color(0xFF00F5D4), width: 1.5),
      ),
    );
  }
}

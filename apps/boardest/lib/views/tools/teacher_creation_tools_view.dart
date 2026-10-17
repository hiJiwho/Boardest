import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../services/bst_cloud_service.dart';
import '../../services/bst_save_service.dart';
import '../../services/tbp/tbp_storage_service.dart';
import '../boardest_pen_view.dart';
import '../canva_board_view.dart';
import '../tbp/tbp_viewer_route.dart';

/// 교사도구 - [제작 (수업 교안 · TBP 스마트교과서 · Canva 저작)] 전담 뷰
/// - 0: TBP 스마트교과서 폴더 제작 (Google Drive /bst-tbs/<title>.tbp 폴더 생성 및 핫스팟/판서 저작)
/// - 1: Canva 수업 디자인 등록 및 보드 저작
/// - 2: 판서 노트 (.bstpen) 제작 및 수업 자료 Cloud 업로드
class TeacherCreationToolsView extends StatefulWidget {
  final int activeTabIndex;
  final VoidCallback? onRequestCloudConnect;

  const TeacherCreationToolsView({
    super.key,
    required this.activeTabIndex,
    this.onRequestCloudConnect,
  });

  @override
  State<TeacherCreationToolsView> createState() => _TeacherCreationToolsViewState();
}

class _TeacherCreationToolsViewState extends State<TeacherCreationToolsView> {
  // 1. TBP 제작 상태
  final TextEditingController _tbpTitleCtrl = TextEditingController();
  final TextEditingController _tbpSubjectCtrl = TextEditingController(text: '공통');
  final TextEditingController _tbpUrlCtrl = TextEditingController(text: 'https://');
  bool _isCreatingTbp = false;
  List<BstCloudFile> _existingTbpFolders = [];
  bool _isLoadingTbpList = false;

  // 2. Canva 등록 상태
  final TextEditingController _canvaTitleCtrl = TextEditingController();
  final TextEditingController _canvaUrlCtrl = TextEditingController();
  bool _isSavingCanva = false;

  // 3. 판서 교안 제작 상태
  final TextEditingController _penTitleCtrl = TextEditingController();
  final TextEditingController _penSubjectCtrl = TextEditingController(text: '수업 판서');
  bool _isUploadingFile = false;

  @override
  void initState() {
    super.initState();
    _loadExistingTbpFolders();
  }

  @override
  void dispose() {
    _tbpTitleCtrl.dispose();
    _tbpSubjectCtrl.dispose();
    _tbpUrlCtrl.dispose();
    _canvaTitleCtrl.dispose();
    _canvaUrlCtrl.dispose();
    _penTitleCtrl.dispose();
    _penSubjectCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingTbpFolders() async {
    final token = BstCloudService.instance.activeToken;
    if (token == null || token.isEmpty) return;
    setState(() => _isLoadingTbpList = true);
    try {
      final list = await BstCloudService.instance.fetchFilesBySpecificFolder(
        accessToken: token,
        folderName: 'bst-tbs',
      );
      if (mounted) {
        setState(() {
          _existingTbpFolders = list;
          _isLoadingTbpList = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTbpList = false);
    }
  }

  Future<void> _handleCreateTbpFolder() async {
    final title = _tbpTitleCtrl.text.trim();
    final subject = _tbpSubjectCtrl.text.trim().isEmpty ? '공통' : _tbpSubjectCtrl.text.trim();
    var url = _tbpUrlCtrl.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('교과서 제목을 입력해주세요.'), backgroundColor: Color(0xFFEF4565)),
      );
      return;
    }
    if (url.isEmpty || url == 'https://' || url == 'http://') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('디지털교과서 또는 수업 웹 URL을 입력해주세요.'), backgroundColor: Color(0xFFEF4565)),
      );
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    setState(() => _isCreatingTbp = true);
    try {
      final token = BstCloudService.instance.activeToken;
      String? folderId;
      if (token != null && token.isNotEmpty) {
        folderId = await BstCloudService.instance.createTbpProjectFolderOnDrive(
          title: title,
          subject: subject,
          targetUrl: url,
          accessToken: token,
        );
      }

      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final folderName = safeTitle.toLowerCase().endsWith('.tbp') ? safeTitle : '$safeTitle.tbp';
      final fallbackId = folderId ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
      final fullMeta = <String, dynamic>{
        'version': '2.0.0',
        'title': title,
        'subject': subject,
        'webUrl': url,
        'targetUrl': url,
        'folderId': fallbackId,
        'createdAt': DateTime.now().toIso8601String(),
      };

      String? localTbpDirPath;
      if (kIsWeb) {
        localTbpDirPath = folderId != null ? null : 'web://tbp/$folderName';
      } else {
        try {
          final boardDir = await BstSaveService.instance.directoryFor(BstSaveService.subBoard);
          localTbpDirPath = p.join(boardDir.path, folderName);
        } catch (_) {}
      }

      final resultPath = await TbpStorageService.instance.registerCreatedTbpProject(
        meta: fullMeta,
        driveFolderId: folderId,
        localDirPath: localTbpDirPath,
      );

      if (!mounted) return;
      setState(() => _isCreatingTbp = false);
      _tbpTitleCtrl.clear();
      if (folderId != null && folderId.isNotEmpty) {
        _loadExistingTbpFolders();
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TbpViewerRoute(
            tbpFilePath: resultPath,
            scaleFactor: 1.0,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreatingTbp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e'), backgroundColor: const Color(0xFFEF4565)),
      );
    }
  }

  Future<void> _handleOpenCanvaAuthoring() async {
    final title = _canvaTitleCtrl.text.trim().isEmpty ? 'Canva 수업교안' : _canvaTitleCtrl.text.trim();
    final url = _canvaUrlCtrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Canva 공유 링크 또는 임베드 URL을 입력해주세요.'), backgroundColor: Color(0xFFEF4565)),
      );
      return;
    }

    final token = BstCloudService.instance.activeToken;
    if (token != null && token.isNotEmpty) {
      setState(() => _isSavingCanva = true);
      try {
        final payload = jsonEncode({
          'title': title,
          'url': url,
          'createdAt': DateTime.now().toIso8601String(),
        });
        await BstCloudService.instance.uploadFileToDrive(
          fileName: '$title.canva.bst',
          bytes: Uint8List.fromList(utf8.encode(payload)),
          mimeType: 'application/json',
          accessToken: token,
        );
      } catch (_) {}
      if (mounted) setState(() => _isSavingCanva = false);
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CanvaBoardView(
          filePath: url,
          scaleFactor: 1.0,
        ),
      ),
    );
  }

  Future<void> _handleUploadMaterialToCloud() async {
    final token = BstCloudService.instance.activeToken;
    if (token == null || token.isEmpty) {
      widget.onRequestCloudConnect?.call();
      return;
    }

    final picked = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'ppt', 'pptx', 'hwp', 'hwpx', 'pen', 'bstpen'],
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() => _isUploadingFile = true);
    try {
      final ok = await BstCloudService.instance.uploadFileToDrive(
        fileName: file.name,
        bytes: bytes,
        mimeType: 'application/octet-stream',
        accessToken: token,
      );
      if (!mounted) return;
      setState(() => _isUploadingFile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '☁️ [${file.name}] 수업 교안함에 업로드 완료!' : '업로드에 실패했습니다.'),
          backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4565),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.activeTabIndex.clamp(0, 2),
      children: [
        _buildTbpCreationPanel(),
        _buildCanvaCreationPanel(),
        _buildPenAndMaterialCreationPanel(),
      ],
    );
  }

  // ════════════════ 1. TBP 스마트교과서 폴더 제작 패널 ════════════════
  Widget _buildTbpCreationPanel() {
    final isCloudConnected = BstCloudService.instance.activeToken != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 좌측: 새 TBP 폴더형 프로젝트 생성 폼
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121722),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF7F5AF0).withValues(alpha: 0.35), width: 1.5),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7F5AF0).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.auto_stories_rounded, color: Color(0xFF7F5AF0), size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TBP 스마트교과서 제작 (폴더형 Cloud 저장)',
                                  style: GoogleFonts.notoSansKr(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Google Drive TBP 폴더에 폴더 형태로 저장되어 필요한 페이지 데이터만 즉시 로드됩니다.',
                                  style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildInputField(
                        controller: _tbpTitleCtrl,
                        label: '교과서 / 단원명',
                        hint: '예: 중1 과학 3단원 빛과 파동',
                        icon: Icons.book_rounded,
                      ),
                      const SizedBox(height: 14),
                      _buildInputField(
                        controller: _tbpSubjectCtrl,
                        label: '과목명',
                        hint: '예: 과학, 수학, 영어',
                        icon: Icons.category_rounded,
                      ),
                      const SizedBox(height: 14),
                      _buildInputField(
                        controller: _tbpUrlCtrl,
                        label: '디지털교과서 / 수업 웹 URL',
                        hint: 'https://...',
                        icon: Icons.link_rounded,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7F5AF0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isCreatingTbp ? null : _handleCreateTbpFolder,
                          icon: _isCreatingTbp
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.create_new_folder_rounded),
                          label: Text(
                            isCloudConnected ? 'TBP 폴더 생성 및 핫스팟 저작 시작' : 'Cloud 연결 후 TBP 폴더 생성',
                            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // 우측: 기존 TBP 폴더 목록 (클릭 시 이어서 제작/열기)
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121722),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '내 Cloud TBP 교과서 목록',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          IconButton(
                            onPressed: _loadExistingTbpFolders,
                            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00F5D4), size: 18),
                            tooltip: '새로고침',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (!isCloudConnected)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              '우측 상단 [Cloud 연동] 후\n생성된 TBP 교과서 폴더를 편집할 수 있습니다.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 12.5),
                            ),
                          ),
                        )
                      else if (_isLoadingTbpList)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator(color: Color(0xFF7F5AF0))),
                        )
                      else if (_existingTbpFolders.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              '아직 생성된 TBP 폴더가 없습니다.',
                              style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 12.5),
                            ),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 280),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _existingTbpFolders.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final item = _existingTbpFolders[idx];
                              return ListTile(
                                dense: true,
                                tileColor: Colors.white.withValues(alpha: 0.04),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                leading: const Icon(Icons.auto_stories_rounded, color: Color(0xFF7F5AF0), size: 20),
                                title: Text(
                                  item.name,
                                  style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.edit_note_rounded, color: Color(0xFF00F5D4), size: 20),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => TbpViewerRoute(
                                        tbpFilePath: 'drive://tbp/${item.id}',
                                        scaleFactor: 1.0,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════ 2. CANVA 수업 디자인 등록 & 저작 패널 ════════════════
  Widget _buildCanvaCreationPanel() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF121722),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF00C4CC).withValues(alpha: 0.35), width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C4CC).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.palette_rounded, color: Color(0xFF00C4CC), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Canva 수업 디자인 등록 및 판서 결합',
                        style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Canva 공유 링크를 교안함에 등록하고 슬라이드별 판서 레이어를 결합합니다.',
                        style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildInputField(
                controller: _canvaTitleCtrl,
                label: '수업 디자인 제목',
                hint: '예: 2학기 역사 발표 수업 슬라이드',
                icon: Icons.title_rounded,
              ),
              const SizedBox(height: 14),
              _buildInputField(
                controller: _canvaUrlCtrl,
                label: 'Canva 공유 / 임베드 URL',
                hint: 'https://www.canva.com/design/...',
                icon: Icons.link_rounded,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C4CC),
                    foregroundColor: const Color(0xFF080D11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _isSavingCanva ? null : _handleOpenCanvaAuthoring,
                  icon: const Icon(Icons.launch_rounded),
                  label: Text(
                    'Canva 교안 등록 및 보드 열기',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════ 3. 새 판서 교안 (.bstpen) 제작 & Cloud 자료 업로드 ════════════════
  Widget _buildPenAndMaterialCreationPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 좌측: 새 판서 노트 제작
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121722),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.draw_rounded, color: Color(0xFF00F5D4), size: 24),
                          const SizedBox(width: 10),
                          Text(
                            '새 판서 노트 (.bstpen) 제작',
                            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInputField(
                        controller: _penTitleCtrl,
                        label: '판서 노트 파일명',
                        hint: '예: 1단원 핵심정리 판서',
                        icon: Icons.edit_document,
                      ),
                      const SizedBox(height: 12),
                      _buildInputField(
                        controller: _penSubjectCtrl,
                        label: '과목명',
                        hint: '예: 수학',
                        icon: Icons.bookmark_border_rounded,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00F5D4),
                            foregroundColor: const Color(0xFF080D11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            final name = _penTitleCtrl.text.trim().isEmpty
                                ? '수업판서_${DateTime.now().millisecondsSinceEpoch}.bstpen'
                                : '${_penTitleCtrl.text.trim()}.bstpen';
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BoardestPenView(
                                  filePath: name,
                                  scaleFactor: 1.0,
                                  teacher: BstCloudService.instance.activeTeacherName ?? '교사',
                                  subject: _penSubjectCtrl.text.trim().isEmpty ? '판서' : _penSubjectCtrl.text.trim(),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.brush_rounded),
                          label: Text('판서 저작 스튜디오 열기', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // 우측: 수업 자료 Cloud 업로드
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121722),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cloud_upload_rounded, color: Color(0xFF38BDF8), size: 24),
                          const SizedBox(width: 10),
                          Text(
                            '수업 교안 Cloud 업로드',
                            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'PDF, PPTX, HWPX, 판서(.bstpen) 교안을 Google Drive 교안함(bst-save)에 업로드하여 교실 전자칠판에서 즉시 불러옵니다.',
                        style: GoogleFonts.notoSansKr(color: Colors.white60, fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF38BDF8),
                            foregroundColor: const Color(0xFF080D11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isUploadingFile ? null : _handleUploadMaterialToCloud,
                          icon: _isUploadingFile
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Color(0xFF080D11), strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_file_rounded),
                          label: Text('파일 선택 및 Cloud 업로드', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.notoSansKr(color: Colors.white30, fontSize: 13),
            prefixIcon: Icon(icon, color: Colors.white54, size: 18),
            filled: true,
            fillColor: const Color(0xFF080D11),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
        ),
      ],
    );
  }
}

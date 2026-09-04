import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:universal_io/io.dart';
import 'package:path/path.dart' as p;
import 'package:bst_pen/bst_pen.dart';
import '../services/cloud_drive_service.dart';
import '../services/app_paths.dart';
import '../models/app_settings.dart';
import '../services/storage_service.dart';

/// Boardest .pen 판서 저장소 뷰어 (Cloud bst-pen / Local & USB .pen)
class SavedInkView extends StatefulWidget {
  final double scaleFactor;
  final VoidCallback? onBack;

  const SavedInkView({super.key, required this.scaleFactor, this.onBack});

  @override
  State<SavedInkView> createState() => _SavedInkViewState();
}

class _SavedInkViewState extends State<SavedInkView> {
  bool _isLoading = true;
  AppSettings? _settings;
  List<Map<String, dynamic>> _inkFiles = [];
  String _selectedClassFilter = '전체';
  String _selectedTypeFilter = '전체';
  String _searchQuery = '';

  final List<String> _classOptions = [
    '전체',
    '[Teacher]',
    '[101]', '[102]', '[103]', '[104]',
    '[201]', '[202]', '[203]', '[204]',
    '[301]', '[302]', '[303]', '[304]',
    '특수교실',
  ];

  final List<String> _typeOptions = ['전체', '칠판', 'PPT', 'PDF', 'HWP', 'TBP', 'Canva'];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    _settings = await StorageService().getSettings() ?? AppSettings();
    await _fetchInkFiles();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchInkFiles() async {
    final List<Map<String, dynamic>> list = [];
    final cloud = CloudDriveService.instance;

    // 1. Google Drive /bst-pen/ 내 판서 폴더 ([반ID] 원본파일명.pen) 목록 조회
    if (cloud.isLoggedIn) {
      try {
        final cloudPenFolders = await cloud.fetchSavedPenFoldersFromDrive();
        list.addAll(cloudPenFolders);
      } catch (e) {
        debugPrint('[SavedInkView] Cloud pen fetch error: $e');
      }
    }

    // 2. 로컬 디스크 및 USB bst-pen 폴더 목록 조회 (.pen 파일)
    if (!kIsWeb) {
      try {
        final penDir = Directory(AppPaths.bstPenRootSync);
        if (penDir.existsSync()) {
          final localFiles = penDir.listSync(recursive: true).whereType<File>().toList();
          for (final f in localFiles) {
            final fileName = p.basename(f.path);
            final ext = p.extension(f.path).toLowerCase();
            if (ext == '.pen' || ext == '.bstpen') {
              final stat = f.statSync();

              String classCode = '[Teacher]';
              String rawFileName = fileName;
              if (rawFileName.endsWith('.pen')) rawFileName = rawFileName.substring(0, rawFileName.length - 4);
              if (rawFileName.endsWith('.bstpen')) rawFileName = rawFileName.substring(0, rawFileName.length - 7);

              if (rawFileName.startsWith('[')) {
                final closeIdx = rawFileName.indexOf(']');
                if (closeIdx > 0) {
                  classCode = rawFileName.substring(0, closeIdx + 1);
                  rawFileName = rawFileName.substring(closeIdx + 1).trim();
                }
              }

              list.add({
                'id': f.path,
                'name': fileName,
                'rawFileName': rawFileName,
                'classCode': classCode,
                'isCloud': false,
                'isFolderDoc': false,
                'modifiedTime': stat.modified,
                'size': stat.size,
                'source': '로컬 디스크 (.pen)',
                'localPath': f.path,
              });
            }
          }
        }
      } catch (e) {
        debugPrint('[SavedInkView] Local fetch error: $e');
      }
    }

    // 정렬 (최신순)
    list.sort((a, b) {
      final tA = a['modifiedTime'] as DateTime? ?? DateTime(2000);
      final tB = b['modifiedTime'] as DateTime? ?? DateTime(2000);
      return tB.compareTo(tA);
    });

    if (mounted) {
      setState(() {
        _inkFiles = list;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredFiles {
    return _inkFiles.where((item) {
      final name = (item['name'] as String? ?? '').toLowerCase();
      final classCode = item['classCode'] as String? ?? '';
      final rawName = (item['rawFileName'] as String? ?? '').toLowerCase();

      // 1. 반별 필터
      if (_selectedClassFilter != '전체') {
        if (_selectedClassFilter == '특수교실') {
          if (!name.contains('특수') && !classCode.contains('특수')) return false;
        } else {
          final filterCode = _selectedClassFilter.toLowerCase();
          if (!classCode.toLowerCase().contains(filterCode) && !name.contains(filterCode)) return false;
        }
      }

      // 2. 유형 필터
      if (_selectedTypeFilter != '전체') {
        final f = _selectedTypeFilter.toLowerCase();
        if (f == '칠판' && !name.contains('board') && !name.contains('칠판') && !name.contains('quick')) return false;
        if (f == 'ppt' && !name.contains('ppt')) return false;
        if (f == 'pdf' && !name.contains('pdf')) return false;
        if (f == 'hwp' && !name.contains('hwp')) return false;
        if (f == 'tbp' && !name.contains('tbp')) return false;
        if (f == 'canva' && !name.contains('canva')) return false;
      }

      // 3. 검색어 필터
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        if (!name.contains(q) && !rawName.contains(q)) return false;
      }

      return true;
    }).toList();
  }

  Future<void> _previewInkFile(Map<String, dynamic> item) async {
    final name = item['name'] as String? ?? '판서';
    final isCloud = item['isCloud'] as bool? ?? false;
    final isFolderDoc = item['isFolderDoc'] as bool? ?? false;
    final folderId = item['folderId'] as String?;
    final localPath = item['localPath'] as String?;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _PenViewerDialog(
        title: name,
        isCloud: isCloud,
        isFolderDoc: isFolderDoc,
        folderId: folderId,
        localPath: localPath,
        item: item,
      ),
    );
  }

  Future<void> _renameInkFile(Map<String, dynamic> item) async {
    final oldName = item['name']?.toString() ?? '';
    final rawName = item['rawFileName']?.toString() ?? oldName;
    final isCloud = item['isCloud'] == true;
    final id = item['id']?.toString() ?? '';
    final localPath = item['localPath']?.toString();

    final controller = TextEditingController(text: rawName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.draw_rounded, color: Color(0xFF00F5D4), size: 20),
            const SizedBox(width: 8),
            Text('자유판서 이름 변경', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('기존: $oldName', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              style: GoogleFonts.notoSansKr(color: Colors.white),
              decoration: InputDecoration(
                hintText: '새 판서명을 입력하세요',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('변경', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != rawName) {
      final classCode = item['classCode']?.toString() ?? '';
      String targetFullName = newName.trim();
      if (classCode.isNotEmpty && !targetFullName.contains(classCode)) {
        targetFullName = '$classCode $targetFullName';
      }
      if (!targetFullName.toLowerCase().endsWith('.pen')) {
        targetFullName = '$targetFullName.pen';
      }

      final ok = await CloudDriveService.instance.renamePenFile(
        fileOrFolderId: id,
        newName: targetFullName,
        isCloud: isCloud,
        localPath: localPath,
      );

      if (ok) {
        await _fetchInkFiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('판서명이 "$targetFullName"(으)로 변경되었습니다.'), backgroundColor: const Color(0xFF00F5D4)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('판서 이름 변경 실패')),
          );
        }
      }
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '';
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final cloud = CloudDriveService.instance;
    final filtered = _filteredFiles;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Row(
          children: [
            const Icon(Icons.border_color_rounded, color: Color(0xFF00F5D4)),
            const SizedBox(width: 8),
            Text(
              '판서 보관함 (.pen)',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16 * s,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00F5D4)),
            onPressed: _loadAll,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7F5AF0)))
          : SingleChildScrollView(
              padding: EdgeInsets.all(20 * s),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 960 * s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── 상단 상태 배너 ───────────────────────────
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(14 * s),
                          border: Border.all(color: const Color(0xFF242629)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              cloud.isLoggedIn ? Icons.cloud_done_rounded : Icons.folder_shared_rounded,
                              color: cloud.isLoggedIn ? const Color(0xFF00F5D4) : const Color(0xFF7F5AF0),
                              size: 20 * s,
                            ),
                            SizedBox(width: 10 * s),
                            Expanded(
                              child: Text(
                                cloud.isLoggedIn
                                    ? '☁️ Google Drive bst-pen 폴더 및 로컬 .pen 판서가 실시간 연동됩니다. (총 ${filtered.length}개 판서)'
                                    : '💾 로컬 저장소 .pen 판서 목록입니다. (Google Drive 로그인 시 클라우드 판서 자동 조회)',
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white,
                                  fontSize: 12 * s,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16 * s),

                      // ── 필터 및 검색 바 ─────────────────────────
                      Container(
                        padding: EdgeInsets.all(14 * s),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(14 * s),
                          border: Border.all(color: const Color(0xFF242629)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text('반별: ', style: TextStyle(color: Colors.white70, fontSize: 12 * s)),
                                SizedBox(width: 6 * s),
                                DropdownButton<String>(
                                  value: _selectedClassFilter,
                                  dropdownColor: const Color(0xFF242629),
                                  style: TextStyle(color: Colors.white, fontSize: 12 * s),
                                  items: _classOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                                  onChanged: (v) => setState(() => _selectedClassFilter = v ?? '전체'),
                                ),
                                SizedBox(width: 16 * s),
                                Text('유형: ', style: TextStyle(color: Colors.white70, fontSize: 12 * s)),
                                SizedBox(width: 6 * s),
                                DropdownButton<String>(
                                  value: _selectedTypeFilter,
                                  dropdownColor: const Color(0xFF242629),
                                  style: TextStyle(color: Colors.white, fontSize: 12 * s),
                                  items: _typeOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                                  onChanged: (v) => setState(() => _selectedTypeFilter = v ?? '전체'),
                                ),
                              ],
                            ),
                            SizedBox(height: 10 * s),
                            TextField(
                              onChanged: (val) => setState(() => _searchQuery = val),
                              style: TextStyle(color: Colors.white, fontSize: 12.5 * s),
                              decoration: InputDecoration(
                                hintText: '판서 원본 파일명 / 반ID 검색...',
                                hintStyle: TextStyle(color: const Color(0xFF72757E), fontSize: 12 * s),
                                prefixIcon: Icon(Icons.search_rounded, color: const Color(0xFF72757E), size: 18 * s),
                                filled: true,
                                fillColor: const Color(0xFF0F0E17),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10 * s),
                                  borderSide: const BorderSide(color: Color(0xFF242629)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16 * s),

                      // ── 판서 파일 리스트 ─────────────────────────
                      if (filtered.isEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 40 * s),
                          alignment: Alignment.center,
                          child: Column(
                            children: [
                              Icon(Icons.draw_outlined, size: 40 * s, color: const Color(0xFF72757E)),
                              SizedBox(height: 10 * s),
                              Text(
                                '저장된 .pen 판서 기록이 없습니다.',
                                style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * s),
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, idx) {
                            final item = filtered[idx];
                            final isCloud = item['isCloud'] as bool? ?? false;
                            final name = item['name'] as String? ?? '';
                            final classCode = item['classCode'] as String? ?? '[Teacher]';
                            final rawFileName = item['rawFileName'] as String? ?? name;
                            final modTime = item['modifiedTime'] as DateTime?;
                            final timeStr = _formatDateTime(modTime);

                            return Container(
                              margin: EdgeInsets.only(bottom: 10 * s),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16161A),
                                borderRadius: BorderRadius.circular(12 * s),
                                border: Border.all(color: const Color(0xFF242629)),
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: EdgeInsets.all(8 * s),
                                  decoration: BoxDecoration(
                                    color: (isCloud ? const Color(0xFF00F5D4) : const Color(0xFF7F5AF0)).withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isCloud ? Icons.cloud_done_rounded : Icons.draw_rounded,
                                    color: isCloud ? const Color(0xFF00F5D4) : const Color(0xFF7F5AF0),
                                    size: 20 * s,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7F5AF0).withOpacity(0.25),
                                        borderRadius: BorderRadius.circular(6 * s),
                                        border: Border.all(color: const Color(0xFF7F5AF0).withOpacity(0.5)),
                                      ),
                                      child: Text(
                                        classCode,
                                        style: GoogleFonts.outfit(
                                          color: const Color(0xFF9E86FF),
                                          fontSize: 11 * s,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 8 * s),
                                    Expanded(
                                      child: Text(
                                        rawFileName,
                                        style: GoogleFonts.notoSansKr(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13 * s,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: EdgeInsets.only(top: 4 * s),
                                  child: Text(
                                    '${item['source']}  ·  수정시각: $timeStr',
                                    style: TextStyle(color: const Color(0xFF94A1B2), fontSize: 11 * s),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.drive_file_rename_outline_rounded, size: 18 * s, color: const Color(0xFF00F5D4)),
                                      tooltip: '자유판서 이름 변경',
                                      onPressed: () => _renameInkFile(item),
                                    ),
                                    SizedBox(width: 4 * s),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF242629),
                                        foregroundColor: const Color(0xFF00F5D4),
                                        elevation: 0,
                                        padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * s)),
                                      ),
                                      onPressed: () => _previewInkFile(item),
                                      icon: const Icon(Icons.visibility_rounded, size: 14),
                                      label: const Text('열람'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// .pen 스트로크 & 벡터 렌더링 다이얼로그
class _PenViewerDialog extends StatefulWidget {
  final String title;
  final bool isCloud;
  final bool isFolderDoc;
  final String? folderId;
  final String? localPath;
  final Map<String, dynamic> item;

  const _PenViewerDialog({
    required this.title,
    required this.isCloud,
    required this.isFolderDoc,
    this.folderId,
    this.localPath,
    required this.item,
  });

  @override
  State<_PenViewerDialog> createState() => _PenViewerDialogState();
}

class _PenViewerDialogState extends State<_PenViewerDialog> {
  bool _loading = true;
  int _currentPage = 1;
  int _totalPages = 1;
  Map<int, List<AnnotationStroke>> _pageStrokes = {};
  Map<String, dynamic>? _infoMetadata;

  @override
  void initState() {
    super.initState();
    _loadPenData();
  }

  Future<void> _loadPenData() async {
    setState(() => _loading = true);

    try {
      if (widget.isCloud && widget.folderId != null) {
        final cloud = CloudDriveService.instance;
        final files = await cloud.fetchDriveFiles(folderId: widget.folderId!);
        
        // info.json 로드
        final infoFile = files.where((f) => f.name == 'info.json').firstOrNull;
        if (infoFile != null) {
          final bytes = await cloud.fetchDriveFileBytes(infoFile.id);
          if (bytes != null && bytes.isNotEmpty) {
            _infoMetadata = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>?;
          }
        }

        // strokes.json 로드
        final strokesFile = files.where((f) => f.name == 'strokes.json' || f.name.endsWith('.pen')).firstOrNull;
        if (strokesFile != null) {
          final bytes = await cloud.fetchDriveFileBytes(strokesFile.id);
          if (bytes != null && bytes.isNotEmpty) {
            final penJson = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
            final penData = BstPenData.fromJson(penJson);
            _totalPages = penData.totalPages > 0 ? penData.totalPages : 1;
            _pageStrokes = penData.pages;
          }
        }
      } else if (widget.localPath != null) {
        final file = File(widget.localPath!);
        if (file.existsSync()) {
          final penJson = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          final penData = BstPenData.fromJson(penJson);
          _totalPages = penData.totalPages > 0 ? penData.totalPages : 1;
          _pageStrokes = penData.pages;
          _infoMetadata = penJson['metadata'] as Map<String, dynamic>?;
        }
      }
    } catch (e) {
      debugPrint('[_PenViewerDialog] Error loading pen: $e');
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStrokes = _pageStrokes[_currentPage - 1] ?? _pageStrokes[_currentPage] ?? [];

    return Dialog(
      backgroundColor: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 860,
        height: 620,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.draw_rounded, color: Color(0xFF00F5D4), size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Color(0xFF242629), height: 20),

            // Canvas area
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF7F5AF0)))
                  : Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0E17),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF242629)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _PreviewStrokePainter(currentStrokes),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),

            // Navigation bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '페이지 $_currentPage / $_totalPages',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                      onPressed: _currentPage > 1
                          ? () => setState(() => _currentPage--)
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
                      onPressed: _currentPage < _totalPages
                          ? () => setState(() => _currentPage++)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewStrokePainter extends CustomPainter {
  final List<AnnotationStroke> strokes;

  _PreviewStrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      paint.color = stroke.color;
      paint.strokeWidth = stroke.strokeWidth;

      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.strokeWidth / 2, paint);
      } else {
        final path = Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewStrokePainter oldDelegate) => true;
}

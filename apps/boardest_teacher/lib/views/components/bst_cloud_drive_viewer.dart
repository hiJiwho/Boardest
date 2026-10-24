import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/cloud_drive_service.dart';

/// Boardest Teacher 전용 차세대 고시인성 Cloud File Viewer
/// - 기존의 좁고 잘 안보이던 파일 목록을 시원한 대형 카드 및 리스트로 전면 개편
/// - PDF, PPT, Canva, HWP, .pen 판서 시각적 프리뷰 및 원클릭 교실 전송 지원
class BstCloudDriveViewer extends StatefulWidget {
  final double scale;
  final Function(Map<String, dynamic> file)? onOpenFile;
  final Function(Map<String, dynamic> file)? onSendToBoard;
  final VoidCallback? onUploadTap;
  final VoidCallback? onNewFolderTap;
  final VoidCallback? onCanvaTap;

  const BstCloudDriveViewer({
    super.key,
    this.scale = 1.0,
    this.onOpenFile,
    this.onSendToBoard,
    this.onUploadTap,
    this.onNewFolderTap,
    this.onCanvaTap,
  });

  @override
  State<BstCloudDriveViewer> createState() => _BstCloudDriveViewerState();
}

class _BstCloudDriveViewerState extends State<BstCloudDriveViewer> {
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _categoryFilter = '전체'; // 전체, PDF, Canva, PPT, 한글, 판서
  bool _isGridView = true; // 그리드 뷰 vs 리스트 뷰

  // 폴더 탐색 스택
  final List<Map<String, String>> _folderStack = [];
  String _currentFolderName = 'bst-save (수업 교안함)';
  String? _currentFolderId;
  String? _rootFolderId;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  /// fetchMergedMaterials 가 반환하는 {'file': CloudDriveFile, ...} 를 평탄화
  Map<String, dynamic> _flattenItem(Map<String, dynamic> item) {
    final f = item['file'];
    if (f is CloudDriveFile) {
      return <String, dynamic>{
        'id': f.id,
        'name': f.name,
        'mimeType': f.mimeType,
        'size': f.size,
        'modifiedTime': f.modifiedTime,
        'webViewLink': f.webViewLink,
        'webContentLink': f.webContentLink,
        'source': item['source'],
        'sourceLabel': item['sourceLabel'],
        'folderId': item['folderId'],
      };
    }
    return item;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _reloadCurrent() => _loadFiles(
        folderId: _folderStack.isNotEmpty ? _folderStack.last['id'] : null,
        folderName: _currentFolderName,
      );

  Future<String?> _askText(String title, String initial, {String hint = ''}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text(title, style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _renameFile(Map<String, dynamic> file) async {
    final id = (file['id'] ?? '').toString();
    final oldName = (file['name'] ?? '').toString();
    if (id.isEmpty) return;
    final newName = await _askText('이름 바꾸기', oldName, hint: '새 이름');
    if (newName == null || newName.isEmpty || newName == oldName) return;
    final ok = await CloudDriveService.instance.renameDriveFile(id, newName);
    _toast(ok ? '이름이 "$newName"(으)로 변경되었습니다.' : '이름 변경에 실패했습니다.');
    if (ok) await _reloadCurrent();
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    final id = (file['id'] ?? '').toString();
    final name = (file['name'] ?? '').toString();
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text('삭제', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('"$name" 을(를) Google Drive에서 삭제하시겠습니까?', style: GoogleFonts.notoSansKr(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await CloudDriveService.instance.deleteDriveFile(id);
    _toast(ok ? '삭제되었습니다.' : '삭제에 실패했습니다.');
    if (ok) await _reloadCurrent();
  }

  Future<void> _newFolder() async {
    final name = await _askText('새 폴더 만들기', '', hint: '폴더 이름');
    if (name == null || name.isEmpty) return;
    final parent = _currentFolderId ?? _rootFolderId ?? await CloudDriveService.instance.getOrCreateConnectFolder();
    final id = await CloudDriveService.instance.createFolderInDrive(name, parentFolderId: parent);
    _toast(id != null ? '폴더 "$name" 이(가) 생성되었습니다.' : '폴더 생성에 실패했습니다.');
    if (id != null) await _reloadCurrent();
  }

  Future<void> _moveFile(Map<String, dynamic> file) async {
    final id = (file['id'] ?? '').toString();
    final name = (file['name'] ?? '').toString();
    if (id.isEmpty) return;

    final rootId = _rootFolderId ?? await CloudDriveService.instance.getOrCreateConnectFolder();
    if (rootId == null) {
      _toast('이동할 폴더 목록을 불러오지 못했습니다.');
      return;
    }
    // 이동 후보: bst-save 루트 + 그 하위 폴더 + 현재 폴더의 하위 폴더
    final candidates = <Map<String, String>>[
      {'id': rootId, 'name': '📁 bst-save (최상위)'},
    ];
    final seen = <String>{rootId};
    Future<void> addFolders(String parent, String prefix) async {
      final list = await CloudDriveService.instance.fetchDriveFiles(folderId: parent, includeFolders: true);
      for (final f in list) {
        if (f.mimeType == 'application/vnd.google-apps.folder' && f.id != id && seen.add(f.id)) {
          candidates.add({'id': f.id, 'name': '$prefix${f.name}'});
        }
      }
    }
    await addFolders(rootId, '   📂 ');
    if (_currentFolderId != null && _currentFolderId != rootId) {
      await addFolders(_currentFolderId!, '      ↳ ');
    }
    if (!mounted) return;

    final target = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text('"$name" 이동', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        content: SizedBox(
          width: 380,
          height: 320,
          child: ListView(
            children: candidates
                .map((c) => ListTile(
                      dense: true,
                      title: Text(c['name']!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      onTap: () => Navigator.pop(ctx, c['id']),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.white60))),
        ],
      ),
    );
    if (target == null) return;
    final ok = await CloudDriveService.instance.moveDriveFile(id, target);
    _toast(ok ? '이동되었습니다.' : '이동에 실패했습니다.');
    if (ok) await _reloadCurrent();
  }

  Widget _buildItemMenu(Map<String, dynamic> file, double s) {
    return PopupMenuButton<String>(
      tooltip: '더보기',
      color: const Color(0xFF1E293B),
      icon: Icon(Icons.more_vert_rounded, color: Colors.white54, size: 18 * s),
      padding: EdgeInsets.zero,
      onSelected: (v) {
        if (v == 'rename') _renameFile(file);
        if (v == 'move') _moveFile(file);
        if (v == 'delete') _deleteFile(file);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('✏️ 이름 바꾸기', style: TextStyle(color: Colors.white))),
        PopupMenuItem(value: 'move', child: Text('📂 폴더로 이동', style: TextStyle(color: Colors.white))),
        PopupMenuItem(value: 'delete', child: Text('🗑️ 삭제', style: TextStyle(color: Color(0xFFFF8BA7)))),
      ],
    );
  }

  Future<void> _loadFiles({String? folderId, String? folderName, bool resetToRoot = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      if (resetToRoot) {
        _folderStack.clear();
        _currentFolderName = 'bst-save (수업 교안함)';
      } else if (folderName != null) {
        _currentFolderName = folderName;
      }
    });

    try {
      if (folderId == null) {
        final merged = await CloudDriveService.instance.fetchMergedMaterials();
        final flatMerged = merged.map(_flattenItem).toList();
        final rootId = await CloudDriveService.instance.getOrCreateConnectFolder();
        final folders = await CloudDriveService.instance.fetchDriveFiles(
          folderId: null,
          includeFolders: true,
        );
        final subFolders = folders
            .where((f) => f.mimeType == 'application/vnd.google-apps.folder')
            .map((f) => <String, dynamic>{
                  'id': f.id,
                  'name': f.name,
                  'mimeType': f.mimeType,
                  'size': f.size,
                  'modifiedTime': f.modifiedTime,
                  'source': 'save',
                  'folderId': rootId,
                })
            .toList();
        // 중복(같은 id) 제거
        final seen = <String>{};
        final all = <Map<String, dynamic>>[];
        for (final f in [...flatMerged, ...subFolders]) {
          if (seen.add((f['id'] ?? '').toString())) all.add(f);
        }
        if (!mounted) return;
        setState(() {
          _currentFolderId = null;
          _rootFolderId = rootId;
          _files = all;
          _isLoading = false;
        });
      } else {
        final list = await CloudDriveService.instance.fetchDriveFiles(
          folderId: folderId,
          includeFolders: true,
        );
        if (!mounted) return;
        setState(() {
          _currentFolderId = folderId;
          _files = list.map((f) => <String, dynamic>{
            'id': f.id,
            'name': f.name,
            'mimeType': f.mimeType,
            'size': f.size,
            'modifiedTime': f.modifiedTime,
            'webViewLink': f.webViewLink,
            'webContentLink': f.webContentLink,
            'folderId': folderId,
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isTbpFolderItem(Map<String, dynamic> file) {
    final name = (file['name'] ?? '').toString().toLowerCase();
    final mimeType = (file['mimeType'] ?? '').toString();
    final source = (file['source'] ?? '').toString();
    if (source == 'tbp' || source == 'canva' || source == 'htmlp') return true;
    if (mimeType == 'application/x-bst-tbp-folder' || mimeType == 'application/x-bst-htmlp-folder') return true;
    if (mimeType == 'application/vnd.google-apps.folder' &&
        (name.endsWith('.tbp') || name.endsWith('.bsttbp') || name.endsWith('.htmlp') || name.endsWith('.canva.bst') || name.endsWith('.bstcanva'))) {
      return true;
    }
    return false;
  }

  List<Map<String, dynamic>> get _filteredFiles {
    return _files.where((file) {
      final name = (file['name'] ?? '').toString().toLowerCase();
      final isTbpFolder = _isTbpFolderItem(file);
      final isFolder = file['mimeType'] == 'application/vnd.google-apps.folder' && !isTbpFolder;

      // 1. 검색어 필터
      if (_searchQuery.isNotEmpty && !name.contains(_searchQuery.toLowerCase())) {
        return false;
      }

      // 2. 카테고리 필터
      if (_categoryFilter == '전체') return true;
      if (isFolder) return true; // 일반 폴더는 카테고리 필터 중에도 표시

      if (_categoryFilter == '📁 수업 자료' || _categoryFilter == '수업 자료') {
        return !isTbpFolder &&
            !name.endsWith('.pen') &&
            !name.endsWith('.bstpen') &&
            !name.endsWith('.bsttbp') &&
            !name.endsWith('.tbp') &&
            !name.endsWith('.htmlp') &&
            !name.contains('canva');
      }
      if (_categoryFilter == '📐 TBP & HTML Present' || _categoryFilter == '📐 TBP & Canva' || _categoryFilter == 'TBP & Canva') {
        final isTbp = isTbpFolder || name.endsWith('.bsttbp') || name.endsWith('.tbp') || name.contains('tbp') || name.contains('교과서');
        final isCanva = file['source'] == 'canva' || name.endsWith('.htmlp') || name.endsWith('.canva') || name.endsWith('.canva.bst') || name.endsWith('.bstcanva') || name.contains('canva');
        return isTbp || isCanva;
      }
      if (_categoryFilter == '✏️ 판서 (.pen)' || _categoryFilter == '판서') {
        final isPen = name.endsWith('.pen') || name.endsWith('.bstpen');
        if (!isPen) return false;
        final size = file['size'];
        if (size is int && size <= 0) return false;
        return true;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale.clamp(0.85, 1.3);
    final displayList = _filteredFiles;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20 * s),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 상단 바: 브레드크럼 경로 + 뷰 전환 + 새로고침 + 툴바 액션
          _buildTopBar(s),

          // 2. 검색창 & 카테고리 칩 필터
          _buildSearchAndFilters(s),

          // 3. 파일 목록 본문
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00F5D4), strokeWidth: 2.5),
                  )
                : displayList.isEmpty
                    ? _buildEmptyState(s)
                    : _isGridView
                        ? _buildGridView(displayList, s)
                        : _buildListView(displayList, s),
          ),
        ],
      ),
    );
  }

  // ─── 1. 상단 바 ───
  Widget _buildTopBar(double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20 * s)),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6 * s),
            decoration: BoxDecoration(
              color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8 * s),
            ),
            child: Icon(Icons.folder_shared_rounded, color: const Color(0xFF00F5D4), size: 18 * s),
          ),
          SizedBox(width: 10 * s),
          if (_folderStack.isNotEmpty)
            IconButton(
              onPressed: () {
                _folderStack.removeLast();
                if (_folderStack.isEmpty) {
                  _loadFiles(resetToRoot: true);
                } else {
                  _loadFiles(
                    folderId: _folderStack.last['id'],
                    folderName: _folderStack.last['name'],
                  );
                }
              },
              tooltip: '상위 폴더로',
              icon: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20 * s),
            ),

          // 브레드크럼 경로
          Expanded(
            child: Row(
              children: [
                InkWell(
                  onTap: () => _loadFiles(resetToRoot: true),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.home_rounded, color: const Color(0xFF00F5D4), size: 16 * s),
                      SizedBox(width: 4 * s),
                      Text(
                        '내 드라이브',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF00F5D4),
                          fontSize: 13 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_folderStack.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6 * s),
                    child: Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 16 * s),
                  ),
                  Text(
                    _currentFolderName,
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontSize: 13 * s,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // 뷰 토글 (그리드 / 리스트)
          IconButton(
            onPressed: () => setState(() => _isGridView = !_isGridView),
            tooltip: _isGridView ? '목록으로 보기' : '격자로 보기',
            icon: Icon(
              _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
              color: const Color(0xFF00F5D4),
              size: 20 * s,
            ),
          ),

          // 새로고침
          IconButton(
            onPressed: () => _loadFiles(
              folderId: _folderStack.isNotEmpty ? _folderStack.last['id'] : null,
              folderName: _currentFolderName,
            ),
            tooltip: '새로고침',
            icon: Icon(Icons.refresh_rounded, color: Colors.white70, size: 20 * s),
          ),

          // 새 폴더
          IconButton(
            onPressed: _newFolder,
            tooltip: '새 폴더',
            icon: Icon(Icons.create_new_folder_rounded, color: const Color(0xFFFFB703), size: 20 * s),
          ),

          SizedBox(width: 6 * s),

          // 툴바 빠른 액션 (업로드 / 새 폴더 / Canva)
          if (widget.onUploadTap != null)
            ElevatedButton.icon(
              onPressed: widget.onUploadTap,
              icon: const Icon(Icons.upload_file_rounded, size: 14),
              label: const Text('업로드'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F5D4),
                foregroundColor: const Color(0xFF0F172A),
                padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                textStyle: TextStyle(fontSize: 11 * s, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  // ─── 2. 검색 & 필터 ───
  Widget _buildSearchAndFilters(double s) {
    final categories = ['전체', '📁 수업 자료', '📐 TBP & HTML Present', '✏️ 판서 (.pen)'];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
      color: Colors.black.withValues(alpha: 0.15),
      child: Row(
        children: [
          // 검색창
          Expanded(
            flex: 4,
            child: Container(
              height: 36 * s,
              decoration: BoxDecoration(
                color: const Color(0xFF070B14),
                borderRadius: BorderRadius.circular(10 * s),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12 * s),
                decoration: InputDecoration(
                  hintText: '자료 이름 검색...',
                  hintStyle: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 11.5 * s),
                  prefixIcon: Icon(Icons.search_rounded, color: const Color(0xFF00F5D4), size: 18 * s),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8 * s),
                ),
              ),
            ),
          ),

          SizedBox(width: 12 * s),

          // 카테고리 칩
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categories.map((cat) {
                  final isSelected = _categoryFilter == cat;
                  return Padding(
                    padding: EdgeInsets.only(right: 6 * s),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _categoryFilter = cat),
                      selectedColor: const Color(0xFF00F5D4),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: GoogleFonts.notoSansKr(
                        color: isSelected ? const Color(0xFF0F172A) : Colors.white70,
                        fontSize: 11 * s,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 0),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 3. 그리드 뷰 (대형 카드) ───
  Widget _buildGridView(List<Map<String, dynamic>> list, double s) {
    return GridView.builder(
      padding: EdgeInsets.all(16 * s),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.15,
        crossAxisSpacing: 14 * s,
        mainAxisSpacing: 14 * s,
      ),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final file = list[i];
        final name = file['name']?.toString() ?? '파일';
        final isTbpFolder = _isTbpFolderItem(file);
        final isFolder = file['mimeType'] == 'application/vnd.google-apps.folder' && !isTbpFolder;
        final meta = _resolveFileMeta(name, isFolder, isTbpFolder: isTbpFolder);

        return InkWell(
          onTap: () {
            if (isFolder) {
              _folderStack.add({'id': file['id']?.toString() ?? '', 'name': name});
              _loadFiles(folderId: file['id']?.toString(), folderName: name);
            } else {
              widget.onOpenFile?.call(file);
            }
          },
          borderRadius: BorderRadius.circular(14 * s),
          child: Container(
            padding: EdgeInsets.all(12 * s),
            decoration: BoxDecoration(
              color: const Color(0xFF161F30),
              borderRadius: BorderRadius.circular(14 * s),
              border: Border.all(color: meta.color.withValues(alpha: 0.35), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: EdgeInsets.all(8 * s),
                      decoration: BoxDecoration(
                        color: meta.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8 * s),
                      ),
                      child: Icon(meta.icon, color: meta.color, size: 24 * s),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                          decoration: BoxDecoration(
                            color: meta.color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4 * s),
                          ),
                          child: Text(
                            meta.tag,
                            style: TextStyle(
                              color: meta.color,
                              fontSize: 9 * s,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 28 * s,
                          height: 24 * s,
                          child: _buildItemMenu(file, s),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 8 * s),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 12.5 * s,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 4 * s),
                if (!isFolder && widget.onSendToBoard != null)
                  InkWell(
                    onTap: () => widget.onSendToBoard?.call(file),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.send_rounded, size: 12, color: Color(0xFF00F5D4)),
                        SizedBox(width: 4 * s),
                        Text(
                          '칠판으로 전송',
                          style: TextStyle(
                            fontSize: 10 * s,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF00F5D4),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    isFolder ? '폴더 열기 ›' : '클릭하여 열기',
                    style: TextStyle(fontSize: 10 * s, color: Colors.white38),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── 4. 리스트 뷰 ───
  Widget _buildListView(List<Map<String, dynamic>> list, double s) {
    return ListView.separated(
      padding: EdgeInsets.all(16 * s),
      itemCount: list.length,
      separatorBuilder: (_, __) => SizedBox(height: 8 * s),
      itemBuilder: (ctx, i) {
        final file = list[i];
        final name = file['name']?.toString() ?? '파일';
        final isTbpFolder = _isTbpFolderItem(file);
        final isFolder = file['mimeType'] == 'application/vnd.google-apps.folder' && !isTbpFolder;
        final meta = _resolveFileMeta(name, isFolder, isTbpFolder: isTbpFolder);

        return InkWell(
          onTap: () {
            if (isFolder) {
              _folderStack.add({'id': file['id']?.toString() ?? '', 'name': name});
              _loadFiles(folderId: file['id']?.toString(), folderName: name);
            } else {
              widget.onOpenFile?.call(file);
            }
          },
          borderRadius: BorderRadius.circular(12 * s),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
            decoration: BoxDecoration(
              color: const Color(0xFF161F30),
              borderRadius: BorderRadius.circular(12 * s),
              border: Border.all(color: meta.color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(meta.icon, color: meta.color, size: 22 * s),
                SizedBox(width: 12 * s),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4 * s),
                  ),
                  child: Text(
                    meta.tag,
                    style: TextStyle(
                      color: meta.color,
                      fontSize: 9 * s,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 10 * s),
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontSize: 13 * s,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isFolder && widget.onSendToBoard != null)
                  IconButton(
                    onPressed: () => widget.onSendToBoard?.call(file),
                    tooltip: '칠판으로 전송',
                    icon: Icon(Icons.send_rounded, color: const Color(0xFF00F5D4), size: 18 * s),
                  ),
                _buildItemMenu(file, s),
                Icon(
                  isFolder ? Icons.chevron_right_rounded : Icons.open_in_new_rounded,
                  color: Colors.white38,
                  size: 18 * s,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(double s) {
    final isDriveConnected = CloudDriveService.instance.isGoogleDriveConnected;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isDriveConnected ? Icons.folder_open_rounded : Icons.cloud_off_rounded,
            size: 48 * s,
            color: isDriveConnected ? Colors.white24 : const Color(0xFFFF8906).withOpacity(0.4),
          ),
          SizedBox(height: 12 * s),
          Text(
            !isDriveConnected
                ? 'Google Drive가 연동되지 않았습니다.'
                : _searchQuery.isNotEmpty
                    ? '검색된 자료가 없습니다.'
                    : '이 폴더에 자료가 없습니다.',
            style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 13 * s),
          ),
          if (!isDriveConnected) ...[
            SizedBox(height: 14 * s),
            ElevatedButton.icon(
              onPressed: () async {
                final ok = await CloudDriveService.instance.loginWithBrowserOAuth();
                if (ok && mounted) {
                  _loadFiles();
                }
              },
              icon: Icon(Icons.login_rounded, size: 16 * s),
              label: Text(
                'Google Drive 로그인 및 연동',
                style: GoogleFonts.notoSansKr(fontSize: 12 * s, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7F5AF0),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 10 * s),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * s)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _FileMeta _resolveFileMeta(String name, bool isFolder, {bool isTbpFolder = false}) {
    final lower = name.toLowerCase();
    if (isTbpFolder || lower.endsWith('.tbp') || lower.endsWith('.bsttbp')) {
      return _FileMeta(const Color(0xFF7F5AF0), Icons.auto_stories_rounded, 'TBP');
    }
    if (isFolder) {
      return _FileMeta(const Color(0xFFFFB703), Icons.folder_rounded, '폴더');
    }
    if (lower.endsWith('.pdf')) {
      return _FileMeta(const Color(0xFFEF4565), Icons.picture_as_pdf_rounded, 'PDF');
    }
    if (lower.endsWith('.htmlp') || lower.endsWith('.htmlp.bst') || lower.endsWith('.canva') || lower.endsWith('.canva.bst') || lower.endsWith('.bstcanva')) {
      return _FileMeta(const Color(0xFF00C4CC), Icons.slideshow_rounded, 'HTMLP');
    }
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return _FileMeta(const Color(0xFFFF8906), Icons.slideshow_rounded, 'PPT');
    }
    if (lower.endsWith('.hwp') || lower.endsWith('.hwpx')) {
      return _FileMeta(const Color(0xFF29B6F6), Icons.description_rounded, '한글');
    }
    if (lower.endsWith('.pen') || lower.endsWith('.bstpen') || lower.endsWith('.iwb')) {
      return _FileMeta(const Color(0xFF00F5D4), Icons.draw_rounded, '판서');
    }
    return _FileMeta(const Color(0xFF818CF8), Icons.insert_drive_file_rounded, '파일');
  }
}

class _FileMeta {
  final Color color;
  final IconData icon;
  final String tag;
  const _FileMeta(this.color, this.icon, this.tag);
}

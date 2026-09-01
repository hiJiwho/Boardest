import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/storage_service.dart';

class UsbExplorer extends StatefulWidget {
  final String drivePath;
  final double scaleFactor;
  final void Function(String filePath)? onFileOpen;
  final bool isPro;
  final void Function(String folderPath)? onSyncNow;
  final void Function(String folderPath)? onRegisterSync;

  const UsbExplorer({
    super.key,
    required this.drivePath,
    this.scaleFactor = 1.4,
    this.onFileOpen,
    this.isPro = false,
    this.onSyncNow,
    this.onRegisterSync,
  });

  @override
  State<UsbExplorer> createState() => _UsbExplorerState();
}

class _UsbExplorerState extends State<UsbExplorer> {
  late String _currentPath;
  List<FileSystemEntity> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.drivePath;
    _loadDirectoryContents();
  }

  @override
  void didUpdateWidget(UsbExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drivePath != widget.drivePath) {
      _currentPath = widget.drivePath;
      _loadDirectoryContents();
    }
  }

  bool _isEligibleForReorder(FileSystemEntity entity) {
    if (entity is! File) return false;
    final ext = p.extension(entity.path).toLowerCase();
    return ['.hwp', '.ppt', '.pptx', '.pdf'].contains(ext);
  }

  Future<void> _loadDirectoryContents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dir = Directory(_currentPath);
      if (await dir.exists()) {
        final rawList = await dir.list().toList();
        
        // Sort: directories first alphabetically
        final dirs = rawList.whereType<Directory>().toList()
          ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

        var files = rawList.whereType<File>().toList();
        if (!widget.isPro) {
          files = files.where((f) => p.basename(f.path).toLowerCase() != 'boardestusb.json').toList();
        }

        // Split into eligible (HWP, PPT, PDF) and other files
        final eligibleFiles = files.where(_isEligibleForReorder).toList();
        final otherFiles = files.where((f) => !_isEligibleForReorder(f)).toList()
          ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

        // Sort eligible files by saved order if exists
        final prefs = await SharedPreferences.getInstance();
        final savedOrder = prefs.getStringList('file_order_${_currentPath.toLowerCase()}');
        
        if (savedOrder != null && savedOrder.isNotEmpty) {
          final Map<String, int> orderMap = {
            for (int i = 0; i < savedOrder.length; i++) savedOrder[i].toLowerCase(): i
          };
          eligibleFiles.sort((a, b) {
            final nameA = p.basename(a.path).toLowerCase();
            final nameB = p.basename(b.path).toLowerCase();
            final idxA = orderMap[nameA];
            final idxB = orderMap[nameB];
            if (idxA != null && idxB != null) {
              return idxA.compareTo(idxB);
            } else if (idxA != null) {
              return -1;
            } else if (idxB != null) {
              return 1;
            } else {
              return nameA.compareTo(nameB);
            }
          });
        } else {
          eligibleFiles.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
        }

        setState(() {
          _items = [...dirs, ...eligibleFiles, ...otherFiles];
          _isLoading = false;
        });
      } else {
        setState(() {
          _items = [];
          _errorMessage = '드라이브를 찾을 수 없습니다.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _items = [];
        _errorMessage = '폴더 내용을 읽을 수 없습니다.\n($e)';
        _isLoading = false;
      });
    }
  }

  Future<void> _reorderFile(int index, bool moveUp) async {
    final targetIndex = moveUp ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= _items.length) return;
    
    final itemA = _items[index];
    final itemB = _items[targetIndex];
    
    // Only allow reordering if both items are eligible files
    if (!_isEligibleForReorder(itemA) || !_isEligibleForReorder(itemB)) return;
    
    setState(() {
      _items[index] = itemB;
      _items[targetIndex] = itemA;
    });
    
    // Save new file order
    final prefs = await SharedPreferences.getInstance();
    final fileNames = _items.whereType<File>().map((f) => p.basename(f.path)).toList();
    await prefs.setStringList('file_order_${_currentPath.toLowerCase()}', fileNames);
  }

  void _navigateTo(String path) {
    setState(() {
      _currentPath = path;
    });
    _loadDirectoryContents();
  }

  void _navigateUp() {
    final parent = Directory(_currentPath).parent;
    // Do not go above the USB drive root path
    if (_currentPath.toLowerCase() == widget.drivePath.toLowerCase() || 
        _currentPath.toLowerCase() == '${widget.drivePath}\\'.toLowerCase()) {
      return;
    }
    _navigateTo(parent.path);
  }

  Future<void> _openFile(String path) async {
    try {
      final lowerPath = path.toLowerCase();
      
      // Record the file opening
      await StorageService().recordOpenedUsbFile(path);
      
      // If parent dashboard passed an onFileOpen callback, route it there (professional teaching session)
      if (widget.onFileOpen != null &&
          (lowerPath.endsWith('.pdf') || lowerPath.endsWith('.pptx') || lowerPath.endsWith('.ppt') ||
          lowerPath.endsWith('.iwb'))) {
        widget.onFileOpen!(path);
        return;
      }

      if (Platform.isWindows) {
        // Open natively with Windows shell explorer (which launches the default app associate)
        await Process.run('explorer.exe', [path]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('파일을 열 수 없습니다: $e')),
      );
    }
  }

  Future<void> _revealInExplorer(String path) async {
    if (Platform.isWindows) {
      try {
        await Process.run('explorer.exe', ['/select,', path]);
      } catch (_) {}
    }
  }

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    final name = p.basename(entity.path);
    final isDir = entity is Directory;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text(isDir ? '폴더 삭제' : '파일 삭제', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('정말로 "$name"${isDir ? ' 폴더와 모든 내용' : ''}을(를) 삭제하시겠습니까?', style: GoogleFonts.notoSansKr(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (isDir) {
          await (entity as Directory).delete(recursive: true);
        } else {
          await entity.delete();
        }
        await _loadDirectoryContents();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  Future<void> _renameEntity(FileSystemEntity entity) async {
    final oldName = p.basename(entity.path);
    final isDir = entity is Directory;
    final ext = isDir ? '' : p.extension(oldName);
    final nameWithoutExt = isDir ? oldName : p.basenameWithoutExtension(oldName);

    final controller = TextEditingController(text: nameWithoutExt);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text(isDir ? '폴더 이름 변경' : '파일 이름 변경', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.notoSansKr(color: Colors.white),
          decoration: InputDecoration(
            hintText: '새 이름을 입력하세요',
            hintStyle: GoogleFonts.notoSansKr(color: Colors.white38),
            suffixText: ext,
            suffixStyle: GoogleFonts.notoSansKr(color: Colors.white60),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7F5AF0)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('변경', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != nameWithoutExt) {
      try {
        final targetName = isDir ? newName : '$newName$ext';
        final newPath = p.join(p.dirname(entity.path), targetName);
        await entity.rename(newPath);
        await _loadDirectoryContents();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('이름 변경 실패: $e')));
      }
    }
  }

  IconData _getFileIcon(FileSystemEntity entity) {
    if (entity is Directory) {
      return Icons.folder_rounded;
    }
    
    final path = entity.path.toLowerCase();
    if (path.endsWith('.iwb')) {
      return Icons.draw_rounded;
    } else if (path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png') || path.endsWith('.gif')) {
      return Icons.image_rounded;
    } else if (path.endsWith('.mp4') || path.endsWith('.mkv') || path.endsWith('.avi')) {
      return Icons.video_library_rounded;
    } else if (path.endsWith('.mp3') || path.endsWith('.wav')) {
      return Icons.music_note_rounded;
    } else if (path.endsWith('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    } else if (path.endsWith('.txt') || path.endsWith('.docx') || path.endsWith('.xlsx') || path.endsWith('.pptx') || path.endsWith('.hwp')) {
      return Icons.description_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor(FileSystemEntity entity) {
    if (entity is Directory) {
      return const Color(0xFF00F5D4);
    }
    final path = entity.path.toLowerCase();
    if (path.endsWith('.iwb')) {
      return const Color(0xFF2EC4B6);
    } else if (path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png') || path.endsWith('.gif')) {
      return const Color(0xFF2CB67D);
    } else if (path.endsWith('.pdf') || path.endsWith('.txt') || path.endsWith('.docx') || path.endsWith('.xlsx') || path.endsWith('.pptx') || path.endsWith('.hwp')) {
      return const Color(0xFF00F5D4);
    } else if (path.endsWith('.mp4') || path.endsWith('.mkv') || path.endsWith('.avi')) {
      return const Color(0xFF2EC4B6).withValues(alpha: 0.8);
    }
    return Colors.white60;
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final textColor70 = isDark ? Colors.white70 : Colors.black54;
    final textColor60 = isDark ? Colors.white60 : Colors.black54;
    final textColor38 = isDark ? Colors.white38 : Colors.black38;
    final textColor24 = isDark ? Colors.white24 : Colors.black26;
    final cardColor = isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withOpacity(0.015);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withOpacity(0.08);
    
    // Breadcrumbs calculations
    final relativePath = _currentPath.substring(widget.drivePath.length);
    final displayPath = 'USB:${relativePath.isEmpty ? '\\' : relativePath}';

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          // Breadcrumbs and Up button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_upward_rounded, color: textColor70, size: 20),
                  onPressed: _currentPath.toLowerCase() == widget.drivePath.toLowerCase() ? null : _navigateUp,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    displayPath,
                    style: GoogleFonts.outfit(
                      fontSize: 9.5 * scale,
                      color: textColor60,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh_rounded, color: textColor70, size: 20),
                  onPressed: _loadDirectoryContents,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          
          // File list area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2EC4B6)))
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.notoSansKr(color: Colors.pinkAccent, fontSize: 13),
                          ),
                        ),
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Text(
                              '빈 폴더입니다.',
                              style: GoogleFonts.notoSansKr(color: textColor24, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(4),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              final isDir = item is Directory;
                              final name = item.path.split(Platform.pathSeparator).last;

                              return InkWell(
                                onTap: () {
                                  if (isDir) {
                                    _navigateTo(item.path);
                                  } else {
                                    _openFile(item.path);
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _getFileIcon(item),
                                        color: _getFileColor(item),
                                        size: 22 * scale,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 11 * scale,
                                            color: isDir ? textColor : textColor70,
                                            fontWeight: isDir ? FontWeight.bold : FontWeight.normal,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert_rounded, color: textColor60, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          color: isDark ? const Color(0xFF16161A) : Colors.white,
                                          onSelected: (val) {
                                            if (val == 'open') {
                                              if (isDir) {
                                                _navigateTo(item.path);
                                              } else {
                                                _openFile(item.path);
                                              }
                                            } else if (val == 'rename') {
                                              _renameEntity(item);
                                            } else if (val == 'delete') {
                                              _deleteEntity(item);
                                            } else if (val == 'reveal') {
                                              _revealInExplorer(item.path);
                                            } else if (val == 'sync' && widget.onSyncNow != null) {
                                              widget.onSyncNow!(item.path);
                                            } else if (val == 'register' && widget.onRegisterSync != null) {
                                              widget.onRegisterSync!(item.path);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'open',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.open_in_new_rounded, size: 16, color: textColor70),
                                                  const SizedBox(width: 8),
                                                  Text('열기', style: GoogleFonts.notoSansKr(color: textColor, fontSize: 11)),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'rename',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit_rounded, size: 16, color: textColor70),
                                                  const SizedBox(width: 8),
                                                  Text('이름 바꾸기', style: GoogleFonts.notoSansKr(color: textColor, fontSize: 11)),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'reveal',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.folder_open_rounded, size: 16, color: textColor70),
                                                  const SizedBox(width: 8),
                                                  Text('탐색기에서 보기', style: GoogleFonts.notoSansKr(color: textColor, fontSize: 11)),
                                                ],
                                              ),
                                            ),
                                            if (widget.isPro && isDir) ...[
                                              PopupMenuItem(
                                                value: 'sync',
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.sync_rounded, size: 16, color: Color(0xFF00F5D4)),
                                                    const SizedBox(width: 8),
                                                    Text('지금 동기화', style: GoogleFonts.notoSansKr(color: textColor, fontSize: 11)),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'register',
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.bookmark_add_rounded, size: 16, color: Color(0xFF00F5D4)),
                                                    const SizedBox(width: 8),
                                                    Text('동기화 폴더 등록', style: GoogleFonts.notoSansKr(color: textColor, fontSize: 11)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            const PopupMenuDivider(),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.pinkAccent),
                                                  const SizedBox(width: 8),
                                                  Text('삭제', style: GoogleFonts.notoSansKr(color: Colors.pinkAccent, fontSize: 11)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (isDir) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          color: textColor24,
                                          size: 18,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

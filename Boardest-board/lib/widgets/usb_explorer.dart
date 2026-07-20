import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../views/boardest_pen_view.dart';
import '../services/storage_service.dart';

class UsbExplorer extends StatefulWidget {
  final String drivePath;
  final double scaleFactor;
  final void Function(String filePath)? onFileOpen;

  const UsbExplorer({
    super.key,
    required this.drivePath,
    this.scaleFactor = 1.4,
    this.onFileOpen,
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

  Future<void> _loadDirectoryContents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dir = Directory(_currentPath);
      if (await dir.exists()) {
        final rawList = await dir.list().toList();
        
        // Sort: directories first, then files alphabetically
        final dirs = rawList.whereType<Directory>().toList()
          ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
        final files = rawList.whereType<File>().toList()
          ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

        setState(() {
          _items = [...dirs, ...files];
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
          lowerPath.endsWith('.hwp') || lowerPath.endsWith('.iwb'))) {
        widget.onFileOpen!(path);
        return;
      }

      // Boardest custom formats and common presentation/document formats open in BoardestPenView
      if (lowerPath.endsWith('.pdf') || lowerPath.endsWith('.pptx') || lowerPath.endsWith('.ppt') ||
          lowerPath.endsWith('.hwp') || lowerPath.endsWith('.iwb')) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => BoardestPenView(
              filePath: path,
              scaleFactor: widget.scaleFactor,
            ),
          ),
        );
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
    
    // Breadcrumbs calculations
    final relativePath = _currentPath.substring(widget.drivePath.length);
    final displayPath = 'USB:${relativePath.isEmpty ? '\\' : relativePath}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          // Breadcrumbs and Up button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white70, size: 20),
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
                      color: Colors.white60,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
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
                              style: GoogleFonts.notoSansKr(color: Colors.white24, fontSize: 13),
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
                                            color: isDir ? Colors.white : Colors.white70,
                                            fontWeight: isDir ? FontWeight.bold : FontWeight.normal,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isDir)
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: Colors.white24,
                                          size: 18,
                                        ),
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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../services/youtube_embed_service.dart';
import 'video_board_view.dart';

class VideoItem {
  final String title;
  final String path;
  final int durationSeconds;

  VideoItem({
    required this.title,
    required this.path,
    this.durationSeconds = 0,
  });
}

/// 영상 모음 및 컷편집 전용 스마트 모듈 (유튜브 URL -> MP4 로컬 저장 + 영상 모아보기 + 컷편집)
class VideoCollectionBoardView extends StatefulWidget {
  final double scaleFactor;
  final VoidCallback? onBack;

  const VideoCollectionBoardView({
    super.key,
    required this.scaleFactor,
    this.onBack,
  });

  @override
  State<VideoCollectionBoardView> createState() => _VideoCollectionBoardViewState();
}

class _VideoCollectionBoardViewState extends State<VideoCollectionBoardView> {
  final TextEditingController _urlController = TextEditingController();
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  List<VideoItem> _videoList = [];
  VideoItem? _selectedVideo;
  VideoPlayerController? _videoPlayerController;

  // 컷편집 상태 (초 단위)
  double _trimStart = 0.0;
  double _trimEnd = 10.0;
  double _maxDuration = 100.0;
  bool _isPlayingTrimmed = false;

  @override
  void initState() {
    super.initState();
    _loadVideoCollection();
  }

  Future<void> _loadVideoCollection() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final ytDir = Directory(p.join(appDir.path, 'BstSave', 'YOUTUBE'));
      if (!ytDir.existsSync()) ytDir.createSync(recursive: true);

      final files = ytDir.listSync().whereType<File>().where((f) {
        final ext = p.extension(f.path).toLowerCase();
        return ['.mp4', '.mkv', '.avi', '.mov'].contains(ext);
      }).toList();

      final items = files.map((f) {
        return VideoItem(
          title: p.basenameWithoutExtension(f.path),
          path: f.path,
        );
      }).toList();

      setState(() {
        _videoList = items;
        if (items.isNotEmpty && _selectedVideo == null) {
          _selectVideo(items.first);
        }
      });
    } catch (e) {
      debugPrint('[VideoCollection] Load error: $e');
    }
  }

  Future<void> _downloadFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.1;
      _downloadStatus = '다운로드 준비 중…';
    });

    final file = await YouTubeEmbedService.downloadVideoDirectly(
      url,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
            _downloadStatus = status;
          });
        }
      },
    );

    if (!mounted) return;

    setState(() {
      _isDownloading = false;
    });

    if (file != null && file.existsSync()) {
      _urlController.clear();
      await _loadVideoCollection();
      final newItem = _videoList.firstWhere(
        (v) => v.path == file.path,
        orElse: () => VideoItem(title: p.basenameWithoutExtension(file.path), path: file.path),
      );
      _selectVideo(newItem);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🎬 영상 다운로드가 완료되어 모음에 추가되었습니다!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('영상 다운로드 실패: $_downloadStatus')),
      );
    }
  }

  Future<void> _selectVideo(VideoItem video) async {
    _videoPlayerController?.dispose();
    _videoPlayerController = null;

    final controller = VideoPlayerController.file(File(video.path));
    try {
      await controller.initialize();
      final duration = controller.value.duration.inSeconds.toDouble();
      setState(() {
        _selectedVideo = video;
        _videoPlayerController = controller;
        _maxDuration = duration > 0 ? duration : 100.0;
        _trimStart = 0.0;
        _trimEnd = _maxDuration;
      });
    } catch (e) {
      debugPrint('[VideoCollection] Player init error: $e');
      setState(() {
        _selectedVideo = video;
      });
    }
  }

  void _previewTrimmedSegment() {
    if (_videoPlayerController == null) return;
    _videoPlayerController!.seekTo(Duration(seconds: _trimStart.toInt()));
    _videoPlayerController!.play();
    setState(() => _isPlayingTrimmed = true);

    // Stop at trim end
    final durationMs = ((_trimEnd - _trimStart) * 1000).toInt();
    Future.delayed(Duration(milliseconds: durationMs), () {
      if (mounted && _isPlayingTrimmed) {
        _videoPlayerController?.pause();
        setState(() => _isPlayingTrimmed = false);
      }
    });
  }

  void _openInVideoBoard(VideoItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoBoardView(
          filePath: item.path,
          scaleFactor: widget.scaleFactor,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: SafeArea(
        child: Column(
          children: [
            // Top Header
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 12 * s),
              color: const Color(0xFF16161A),
              child: Row(
                children: [
                  const Icon(Icons.video_library_rounded, color: Color(0xFF7F5AF0), size: 24),
                  SizedBox(width: 12 * s),
                  Text(
                    '영상 모음 및 컷편집 모듈',
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () {
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            ),

            // Main Content Area
            Expanded(
              child: Row(
                children: [
                  // Left: URL Downloader & Video Collection List
                  Container(
                    width: 340 * s,
                    color: const Color(0xFF16161A),
                    padding: EdgeInsets.all(16 * s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('유튜브 URL 입력 (MP4 자동 다운로드)', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8 * s),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _urlController,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'https://youtu.be/...',
                                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                                  filled: true,
                                  fillColor: const Color(0xFF242629),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                            SizedBox(width: 8 * s),
                            ElevatedButton(
                              onPressed: _isDownloading ? null : _downloadFromUrl,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7F5AF0),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              child: const Icon(Icons.download_rounded, size: 20),
                            ),
                          ],
                        ),
                        if (_isDownloading) ...[
                          SizedBox(height: 10 * s),
                          LinearProgressIndicator(value: _downloadProgress, backgroundColor: Colors.white12, color: const Color(0xFF00F5D4)),
                          SizedBox(height: 4 * s),
                          Text(_downloadStatus, style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 11)),
                        ],

                        SizedBox(height: 20 * s),
                        const Divider(color: Colors.white12),
                        SizedBox(height: 10 * s),

                        Text('📁 저장된 영상 모음 (${_videoList.length})', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        SizedBox(height: 10 * s),

                        Expanded(
                          child: _videoList.isEmpty
                              ? Center(
                                  child: Text('저장된 영상이 없습니다.\nURL을 입력하여 저장해 보세요!', textAlign: TextAlign.center, style: GoogleFonts.notoSansKr(color: Colors.white30, fontSize: 12)),
                                )
                              : ListView.builder(
                                  itemCount: _videoList.length,
                                  itemBuilder: (context, idx) {
                                    final item = _videoList[idx];
                                    final isSelected = _selectedVideo?.path == item.path;

                                    return ListTile(
                                      selected: isSelected,
                                      selectedTileColor: const Color(0xFF7F5AF0).withOpacity(0.2),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      leading: const Icon(Icons.movie_rounded, color: Color(0xFF2CB67D)),
                                      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isSelected ? const Color(0xFF00F5D4) : Colors.white, fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                      onTap: () => _selectVideo(item),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF7F5AF0)),
                                        onPressed: () => _openInVideoBoard(item),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),

                  const VerticalDivider(width: 1, color: Colors.white12),

                  // Right: Video Player Preview & Cut Editor
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(20 * s),
                      child: _selectedVideo == null
                          ? Center(child: Text('왼쪽 목록에서 영상을 선택해 주세요.', style: GoogleFonts.notoSansKr(color: Colors.white30)))
                          : Column(
                              children: [
                                // Video Preview Screen
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: _videoPlayerController != null && _videoPlayerController!.value.isInitialized
                                          ? AspectRatio(
                                              aspectRatio: _videoPlayerController!.value.aspectRatio,
                                              child: VideoPlayer(_videoPlayerController!),
                                            )
                                          : const Center(child: CircularProgressIndicator(color: Color(0xFF7F5AF0))),
                                    ),
                                  ),
                                ),

                                SizedBox(height: 16 * s),

                                // Cut Editing Panel (구간 선택 컷편집)
                                Container(
                                  padding: EdgeInsets.all(16 * s),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF16161A),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.content_cut_rounded, color: Color(0xFF00F5D4), size: 18),
                                          SizedBox(width: 8 * s),
                                          Text('영상 구간 선택 (컷편집)', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                          const Spacer(),
                                          Text(
                                            '구간: ${_trimStart.toInt()}초 ~ ${_trimEnd.toInt()}초 (총 ${(_trimEnd - _trimStart).toInt()}초)',
                                            style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 10 * s),
                                      RangeSlider(
                                        values: RangeValues(_trimStart, _trimEnd.clamp(_trimStart + 1, _maxDuration)),
                                        min: 0.0,
                                        max: _maxDuration > 0 ? _maxDuration : 100.0,
                                        activeColor: const Color(0xFF7F5AF0),
                                        inactiveColor: Colors.white12,
                                        onChanged: (RangeValues values) {
                                          setState(() {
                                            _trimStart = values.start;
                                            _trimEnd = values.end;
                                          });
                                        },
                                      ),
                                      SizedBox(height: 10 * s),
                                      Row(
                                        children: [
                                          ElevatedButton.icon(
                                            onPressed: _previewTrimmedSegment,
                                            icon: Icon(_isPlayingTrimmed ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                            label: Text(_isPlayingTrimmed ? '정지' : '선택 구간 미리보기'),
                                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2CB67D), foregroundColor: Colors.white),
                                          ),
                                          SizedBox(width: 12 * s),
                                          ElevatedButton.icon(
                                            onPressed: () => _openInVideoBoard(_selectedVideo!),
                                            icon: const Icon(Icons.edit_note_rounded),
                                            label: const Text('전자칠판 판서로 열기'),
                                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7F5AF0), foregroundColor: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
}

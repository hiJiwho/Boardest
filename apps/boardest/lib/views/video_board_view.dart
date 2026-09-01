import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../services/youtube_embed_service.dart';
import '../widgets/save_destination_dialog.dart';
import 'package:http/http.dart' as http;
import '../services/universal_media_service.dart';

class VideoTextOverlay {
  String text;
  double x;
  double y;
  int startMs;
  int endMs;

  VideoTextOverlay({
    required this.text,
    required this.x,
    required this.y,
    required this.startMs,
    required this.endMs,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'x': x,
    'y': y,
    'startMs': startMs,
    'endMs': endMs,
  };

  factory VideoTextOverlay.fromJson(Map<String, dynamic> json) =>
      VideoTextOverlay(
        text: json['text'] ?? '',
        x: (json['x'] as num?)?.toDouble() ?? 0.5,
        y: (json['y'] as num?)?.toDouble() ?? 0.8,
        startMs: (json['startMs'] as num?)?.toInt() ?? 0,
        endMs: (json['endMs'] as num?)?.toInt() ?? 10000,
      );
}

class VideoClipItem {
  String id;
  String title;
  String filePath;
  int startTrimMs;
  int endTrimMs;
  int skipStartMs;
  int skipEndMs;
  List<VideoTextOverlay> overlays;

  VideoClipItem({
    required this.id,
    required this.title,
    required this.filePath,
    this.startTrimMs = 0,
    this.endTrimMs = 0,
    this.skipStartMs = 0,
    this.skipEndMs = 0,
    List<VideoTextOverlay>? overlays,
  }) : overlays = overlays ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filePath': p.basename(filePath),
    'startTrimMs': startTrimMs,
    'endTrimMs': endTrimMs,
    'skipStartMs': skipStartMs,
    'skipEndMs': skipEndMs,
    'overlays': overlays.map((o) => o.toJson()).toList(),
  };

  factory VideoClipItem.fromJson(Map<String, dynamic> json) => VideoClipItem(
    id: json['id'] ?? '',
    title: json['title'] ?? '클립',
    filePath: json['filePath'] ?? '',
    startTrimMs: (json['startTrimMs'] as num?)?.toInt() ?? 0,
    endTrimMs: (json['endTrimMs'] as num?)?.toInt() ?? 0,
    skipStartMs: (json['skipStartMs'] as num?)?.toInt() ?? 0,
    skipEndMs: (json['skipEndMs'] as num?)?.toInt() ?? 0,
    overlays: (json['overlays'] as List? ?? [])
        .map((o) => VideoTextOverlay.fromJson(o))
        .toList(),
  );
}

/// 5-Step 비디오 스튜디오 (1. MP4 넣기 ➔ 2. 순서 ➔ 3. 컷편집 ➔ 4. 텍스트 삽입 ➔ 5. 저장 [Cloud/USB/PC]) - Boardest-board
class VideoBoardView extends StatefulWidget {
  final double scaleFactor;
  final String? filePath;
  final VoidCallback? onBack;

  const VideoBoardView({
    super.key,
    required this.scaleFactor,
    this.filePath,
    this.onBack,
  });

  @override
  State<VideoBoardView> createState() => _VideoBoardViewState();
}

class _VideoBoardViewState extends State<VideoBoardView> {
  int _currentStep = 1;

  VideoPlayerController? _videoController;
  List<VideoClipItem> _playlist = [];
  int _currentClipIndex = 0;
  bool _isPlaying = false;
  bool _isLoading = false;

  final TextEditingController _urlInputCtrl = TextEditingController();
  final Map<String, int> _classProgress = {};
  String _selectedClass = '전체 반 공용 (통합)';

  final List<String> _classList = [
    '전체 반 공용 (통합)',
    '1학년 1반',
    '1학년 2반',
    '2학년 1반',
    '2학년 2반',
    '3학년 1반',
    '3학년 2반',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.filePath != null) {
      if (widget.filePath!.toLowerCase().endsWith('.vid')) {
        _loadVidPackage(widget.filePath!);
      } else {
        _playlist.add(
          VideoClipItem(
            id: 'C_1',
            title: p.basenameWithoutExtension(widget.filePath!),
            filePath: widget.filePath!,
          ),
        );
        _loadClip(0);
      }
    }
  }

  @override
  void dispose() {
    _videoController?.pause();
    _videoController?.dispose();
    _urlInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClip(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    _currentClipIndex = index;
    final item = _playlist[index];

    final oldCtrl = _videoController;
    _videoController = null;
    oldCtrl?.pause();
    await oldCtrl?.dispose();

    final file = File(item.filePath);
    if (!await file.exists()) return;

    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    controller.addListener(_onVideoPositionChanged);

    if (item.startTrimMs > 0) {
      await controller.seekTo(Duration(milliseconds: item.startTrimMs));
    }

    if (mounted) {
      setState(() {
        _videoController = controller;
        _isPlaying = false;
      });
    }
  }

  void _onVideoPositionChanged() {
    if (_videoController == null || !_videoController!.value.isInitialized)
      return;

    final posMs = _videoController!.value.position.inMilliseconds;
    if (_playlist.isEmpty || _currentClipIndex >= _playlist.length) return;
    final clip = _playlist[_currentClipIndex];

    if (clip.skipStartMs > 0 && clip.skipEndMs > clip.skipStartMs) {
      if (posMs >= clip.skipStartMs && posMs < clip.skipEndMs) {
        _videoController!.seekTo(Duration(milliseconds: clip.skipEndMs));
      }
    }

    if (clip.endTrimMs > 0 && posMs >= clip.endTrimMs) {
      _videoController!.pause();
      if (_currentClipIndex < _playlist.length - 1) {
        _loadClip(_currentClipIndex + 1).then((_) => _videoController?.play());
      }
    }

    _classProgress[_selectedClass] = posMs;
  }

  Future<void> _addVideoFile() async {
    final pick = await FilePicker.pickFiles(type: FileType.video);
    if (pick != null && pick.files.single.path != null) {
      final path = pick.files.single.path!;
      final name = p.basenameWithoutExtension(path);
      setState(() {
        _playlist.add(
          VideoClipItem(
            id: 'C_${DateTime.now().millisecondsSinceEpoch}',
            title: name,
            filePath: path,
          ),
        );
      });
      if (_playlist.length == 1) _loadClip(0);
    }
  }

  Future<void> _addWebVideoLink() async {
    final url = _urlInputCtrl.text.trim();
    if (url.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final saveFile = await UniversalMediaService.downloadMediaToMp4(
        url,
        onProgress: (progress, status) {
          if (mounted) {
            final p = (progress * 100).toStringAsFixed(1);
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$status $p%'),
                duration: const Duration(milliseconds: 500),
              ),
            );
          }
        },
      );

      if (saveFile != null && saveFile.existsSync()) {
        setState(() {
          _playlist.add(
            VideoClipItem(
              id: 'C_${DateTime.now().millisecondsSinceEpoch}',
              title: '웹비디오 클립 ${_playlist.length + 1}',
              filePath: saveFile.path,
            ),
          );
        });
        _urlInputCtrl.clear();
        if (_playlist.length == 1) _loadClip(0);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportSingleMp4(VideoClipItem clip) async {
    final file = File(clip.filePath);
    if (!file.existsSync()) return;

    final targetPath = await FilePicker.saveFile(
      dialogTitle: '💾 추출된 MP4 동영상 저장',
      fileName: '${clip.title}.mp4',
      type: FileType.video,
    );

    if (targetPath != null) {
      await file.copy(targetPath);
    }
  }

  Future<void> _exportVidPackage() async {
    if (_playlist.isEmpty) return;

    final target = await SaveDestinationDialog.show(
      context: context,
      scaleFactor: widget.scaleFactor,
      title: '🎬 .vid 비디오 패키지 저장 위치 선택',
      subTitle: 'Cloud (BST-Cloud), USB 저장장치, PC (로컬) 중 선택해 주세요.',
    );

    if (target == null) return;

    setState(() => _isLoading = true);
    try {
      final archive = Archive();
      final clipsJson = <Map<String, dynamic>>[];

      for (int i = 0; i < _playlist.length; i++) {
        final item = _playlist[i];
        final file = File(item.filePath);
        if (await file.exists()) {
          final fileBytes = await file.readAsBytes();
          final archiveName = 'media/clip_$i${p.extension(item.filePath)}';
          archive.addFile(
            ArchiveFile(archiveName, fileBytes.length, fileBytes),
          );

          final clipMeta = item.toJson();
          clipMeta['filePath'] = archiveName;
          clipsJson.add(clipMeta);
        }
      }

      final projectMeta = {
        'version': '1.0.0',
        'title': _playlist.isNotEmpty ? _playlist.first.title : '수업 비디오',
        'createdAt': DateTime.now().toIso8601String(),
        'progress': _classProgress,
        'clips': clipsJson,
      };

      final jsonStr = jsonEncode(projectMeta);
      final jsonBytes = utf8.encode(jsonStr);
      archive.addFile(ArchiveFile('project.json', jsonBytes.length, jsonBytes));

      final encoder = ZipEncoder();
      final zipData = encoder.encode(archive);

      if (zipData != null) {
        final savePath = p.join(
          target.targetDirectory.path,
          '${projectMeta['title']}.vid',
        );
        await File(savePath).writeAsBytes(zipData, flush: true);
      }
    } catch (e) {
      debugPrint('[VideoBoardView] Export error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadVidPackage(String vidFilePath) async {
    setState(() => _isLoading = true);
    try {
      final file = File(vidFilePath);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? projectFile;
      final mediaFiles = <String, List<int>>{};

      for (final f in archive) {
        if (f.name == 'project.json') {
          projectFile = f;
        } else if (f.name.startsWith('media/')) {
          mediaFiles[f.name] = f.content as List<int>;
        }
      }

      if (projectFile == null) return;

      final jsonContent = utf8.decode(projectFile.content as List<int>);
      final meta = jsonDecode(jsonContent) as Map<String, dynamic>;

      final tempDir = Directory.systemTemp.createTempSync('bst_vid_extract_');
      final newPlaylist = <VideoClipItem>[];

      final clips = meta['clips'] as List? ?? [];
      for (final c in clips) {
        final item = VideoClipItem.fromJson(c);
        final relPath = c['filePath'] as String;
        final data = mediaFiles[relPath];
        if (data != null) {
          final extractedFile = File(p.join(tempDir.path, p.basename(relPath)));
          await extractedFile.writeAsBytes(data);
          item.filePath = extractedFile.path;
          newPlaylist.add(item);
        }
      }

      setState(() {
        _playlist = newPlaylist;
      });

      if (_playlist.isNotEmpty) {
        _loadClip(0);
      }
    } catch (e) {
      debugPrint('[VideoBoardView] Error loading .vid package: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onStepTabSelected(int step) {
    setState(() => _currentStep = step);
    if ((step == 3 || step == 4) &&
        _playlist.isNotEmpty &&
        _videoController == null) {
      _loadClip(_currentClipIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            if (widget.onBack != null)
              widget.onBack!();
            else
              Navigator.pop(context);
          },
        ),
        title: Text(
          '🎬 5-Step 비디오 스튜디오 (.vid)',
          style: GoogleFonts.notoSansKr(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16 * s,
          ),
        ),
        actions: [
          DropdownButton<String>(
            dropdownColor: const Color(0xFF242629),
            value: _selectedClass,
            style: GoogleFonts.notoSansKr(
              color: Colors.white,
              fontSize: 12 * s,
            ),
            items: _classList
                .map((c) => DropdownMenuItem(value: c, child: Text('🏫 $c')))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedClass = val);
            },
          ),
          SizedBox(width: 16 * s),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: const Color(0xFF1E1E24),
            padding: EdgeInsets.symmetric(vertical: 12 * s, horizontal: 16 * s),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStepTab(
                  1,
                  '1. MP4 넣기',
                  Icons.video_call_rounded,
                  primaryColor,
                ),
                _buildStepTab(
                  2,
                  '2. 순서 정하기',
                  Icons.swap_vert_rounded,
                  primaryColor,
                ),
                _buildStepTab(
                  3,
                  '3. 컷편집',
                  Icons.content_cut_rounded,
                  primaryColor,
                ),
                _buildStepTab(
                  4,
                  '4. 텍스트 삽입',
                  Icons.subtitles_rounded,
                  primaryColor,
                ),
                _buildStepTab(
                  5,
                  '5. 저장 (Cloud/USB/PC)',
                  Icons.save_alt_rounded,
                  primaryColor,
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2EC4B6)),
                  )
                : _buildStepContent(s, primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTab(
    int stepNumber,
    String title,
    IconData icon,
    Color accent,
  ) {
    final isSel = _currentStep == stepNumber;
    return InkWell(
      onTap: () => _onStepTabSelected(stepNumber),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSel ? accent.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSel ? accent : Colors.white10),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSel ? accent : Colors.white54, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.notoSansKr(
                color: isSel ? Colors.white : Colors.white54,
                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(double s, Color accent) {
    switch (_currentStep) {
      case 1:
        return Padding(
          padding: EdgeInsets.all(24 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📥 Step 1: 비디오 파일 및 웹 링크 추가',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 18 * s,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16 * s),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlInputCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '유튜브 / 릴스 / 틱톡 URL 주소 입력',
                        hintStyle: const TextStyle(color: Colors.white38),
                        fillColor: Colors.white.withOpacity(0.05),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12 * s),
                  ElevatedButton.icon(
                    onPressed: _addWebVideoLink,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('웹 스트림 변환'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20 * s),
              ElevatedButton.icon(
                onPressed: _addVideoFile,
                icon: const Icon(Icons.video_library_rounded),
                label: const Text('내 컴퓨터에서 MP4 파일 추가'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
              ),
              SizedBox(height: 24 * s),
              Text(
                '현재 등록된 클립 목록 (${_playlist.length}개):',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white70,
                  fontSize: 14 * s,
                ),
              ),
              SizedBox(height: 12 * s),
              Expanded(
                child: ListView.builder(
                  itemCount: _playlist.length,
                  itemBuilder: (ctx, i) => ListTile(
                    leading: Icon(Icons.movie_rounded, color: accent),
                    title: Text(
                      _playlist[i].title,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      _playlist[i].filePath,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.save_alt_rounded,
                        color: Color(0xFF2EC4B6),
                      ),
                      tooltip: 'MP4 영상 파일로 컴퓨터에 추출 저장',
                      onPressed: () => _exportSingleMp4(_playlist[i]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

      case 2:
        return Padding(
          padding: EdgeInsets.all(24 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🔀 Step 2: 클립 순서 정하기 (Reorder)',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 18 * s,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16 * s),
              Expanded(
                child: ReorderableListView(
                  onReorder: (oldIdx, newIdx) {
                    setState(() {
                      if (newIdx > oldIdx) newIdx -= 1;
                      final item = _playlist.removeAt(oldIdx);
                      _playlist.insert(newIdx, item);
                    });
                  },
                  children: List.generate(_playlist.length, (i) {
                    final item = _playlist[i];
                    return Card(
                      key: ValueKey(item.id),
                      color: const Color(0xFF16161A),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: accent,
                          child: Text('${i + 1}'),
                        ),
                        title: Text(
                          item.title,
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: const Icon(
                          Icons.drag_handle_rounded,
                          color: Colors.white54,
                        ),
                        onTap: () => _loadClip(i),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );

      case 3:
      case 4:
        final totalDurationMs = (_videoController?.value.isInitialized == true)
            ? _videoController!.value.duration.inMilliseconds.toDouble()
            : 60000.0;

        return Row(
          children: [
            Container(
              width: 320 * s,
              color: const Color(0xFF16161A),
              padding: EdgeInsets.all(16 * s),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentStep == 3
                          ? '✂️ Step 3: 컷편집 (Trim/Skip)'
                          : '💬 Step 4: 텍스트/자막 오버레이',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15 * s,
                      ),
                    ),
                    SizedBox(height: 16 * s),

                    if (_playlist.isNotEmpty) ...[
                      Text(
                        '선택된 클립: ${_playlist[_currentClipIndex].title}',
                        style: const TextStyle(
                          color: Color(0xFF2EC4B6),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 12 * s),
                    ],

                    if (_currentStep == 3 && _playlist.isNotEmpty) ...[
                      Text(
                        '시작 구간 트림 (ms): ${_playlist[_currentClipIndex].startTrimMs}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Slider(
                        value: _playlist[_currentClipIndex].startTrimMs
                            .toDouble()
                            .clamp(0.0, totalDurationMs),
                        max: totalDurationMs > 0 ? totalDurationMs : 100.0,
                        onChanged: (val) {
                          setState(
                            () => _playlist[_currentClipIndex].startTrimMs = val
                                .toInt(),
                          );
                          _videoController?.seekTo(
                            Duration(milliseconds: val.toInt()),
                          );
                        },
                      ),
                      SizedBox(height: 12 * s),
                      Text(
                        '스킵 구간 시작 (ms): ${_playlist[_currentClipIndex].skipStartMs}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Slider(
                        value: _playlist[_currentClipIndex].skipStartMs
                            .toDouble()
                            .clamp(0.0, totalDurationMs),
                        max: totalDurationMs > 0 ? totalDurationMs : 100.0,
                        onChanged: (val) {
                          setState(
                            () => _playlist[_currentClipIndex].skipStartMs = val
                                .toInt(),
                          );
                          _videoController?.seekTo(
                            Duration(milliseconds: val.toInt()),
                          );
                        },
                      ),
                    ] else if (_currentStep == 4) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          final ctrl = TextEditingController();
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF16161A),
                              title: const Text(
                                '텍스트 추가',
                                style: TextStyle(color: Colors.white),
                              ),
                              content: TextField(
                                controller: ctrl,
                                style: const TextStyle(color: Colors.white),
                              ),
                              actions: [
                                ElevatedButton(
                                  onPressed: () {
                                    if (ctrl.text.trim().isNotEmpty &&
                                        _playlist.isNotEmpty) {
                                      setState(() {
                                        _playlist[_currentClipIndex].overlays
                                            .add(
                                              VideoTextOverlay(
                                                text: ctrl.text.trim(),
                                                x: 0.5,
                                                y: 0.8,
                                                startMs: 0,
                                                endMs: totalDurationMs.toInt(),
                                              ),
                                            );
                                      });
                                      Navigator.pop(ctx);
                                    }
                                  },
                                  child: const Text('추가'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.text_fields_rounded),
                        label: const Text('새 자막 텍스트 추가'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            Expanded(
              child: Container(
                color: Colors.black,
                child:
                    _videoController != null &&
                        _videoController!.value.isInitialized
                    ? Stack(
                        children: [
                          Center(
                            child: AspectRatio(
                              aspectRatio: _videoController!.value.aspectRatio,
                              child: VideoPlayer(_videoController!),
                            ),
                          ),
                          if (_playlist.isNotEmpty &&
                              _currentClipIndex < _playlist.length)
                            ..._playlist[_currentClipIndex].overlays.map((ov) {
                              final posMs = _videoController!
                                  .value
                                  .position
                                  .inMilliseconds;
                              if (posMs >= ov.startMs && posMs <= ov.endMs) {
                                return Positioned(
                                  left:
                                      ov.x *
                                      MediaQuery.of(context).size.width *
                                      0.5,
                                  top:
                                      ov.y *
                                      MediaQuery.of(context).size.height *
                                      0.5,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      ov.text,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16 * s,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            }),
                          Positioned(
                            left: 20,
                            right: 20,
                            bottom: 20,
                            child: Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      if (_isPlaying) {
                                        _videoController!.pause();
                                        _isPlaying = false;
                                      } else {
                                        _videoController!.play();
                                        _isPlaying = true;
                                      }
                                    });
                                  },
                                ),
                                Expanded(
                                  child: VideoProgressIndicator(
                                    _videoController!,
                                    allowScrubbing: true,
                                    colors: VideoProgressColors(
                                      playedColor: accent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.movie_filter_rounded,
                              color: Colors.white38,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '동영상을 선택해 주세요.',
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white54,
                              ),
                            ),
                            if (_playlist.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => _loadClip(0),
                                child: const Text('첫 번째 클립 재생'),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ),
          ],
        );

      case 5:
      default:
        return Center(
          child: Container(
            width: 480 * s,
            padding: EdgeInsets.all(32 * s),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A),
              borderRadius: BorderRadius.circular(24 * s),
              border: Border.all(color: accent.withOpacity(0.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.save_alt_rounded, color: accent, size: 48 * s),
                SizedBox(height: 16 * s),
                Text(
                  '💾 Step 5: .vid 비디오 패키지 최종 저장',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 18 * s,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8 * s),
                Text(
                  'Cloud (BST-Cloud), USB 저장장치, PC (로컬 AppData) 중 선택하여 .vid 포맷으로 저장합니다.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white54,
                    fontSize: 12 * s,
                  ),
                ),
                SizedBox(height: 24 * s),
                ElevatedButton.icon(
                  onPressed: _exportVidPackage,
                  icon: const Icon(Icons.file_download_rounded),
                  label: const Text('.vid 저장 위치 선택하기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

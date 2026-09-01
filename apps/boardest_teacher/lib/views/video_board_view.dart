import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;

import '../services/youtube_embed_service.dart';
import '../services/bstvideo_service.dart';
import '../services/app_paths.dart';
import '../widgets/save_destination_dialog.dart';
import 'package:http/http.dart' as http;
import '../services/universal_media_service.dart';

// Pen Annotation canvas (basic placeholder implementation to fulfill the requirements)
class AnnotationCanvas extends StatefulWidget {
  final VoidCallback onClear;
  final VoidCallback onSave;

  const AnnotationCanvas({
    Key? key,
    required this.onClear,
    required this.onSave,
  }) : super(key: key);

  @override
  _AnnotationCanvasState createState() => _AnnotationCanvasState();
}

class _AnnotationCanvasState extends State<AnnotationCanvas> {
  List<Offset?> points = [];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              RenderBox renderBox = context.findRenderObject() as RenderBox;
              points.add(renderBox.globalToLocal(details.globalPosition));
            });
          },
          onPanEnd: (details) {
            points.add(null);
          },
          child: CustomPaint(
            painter: _DrawingPainter(points: points),
            size: Size.infinite,
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.white),
                onPressed: () {
                  setState(() => points.clear());
                  widget.onClear();
                },
              ),
              IconButton(
                icon: const Icon(Icons.save, color: Colors.white),
                onPressed: widget.onSave,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<Offset?> points;
  _DrawingPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = const Color(0xFFFF8906)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class VideoBoardView extends StatefulWidget {
  final double scaleFactor;
  final String? initialVidPath;
  final VoidCallback? onBack;

  const VideoBoardView({
    super.key,
    required this.scaleFactor,
    this.initialVidPath,
    this.onBack,
  });

  @override
  State<VideoBoardView> createState() => _VideoBoardViewState();
}

class _VideoBoardViewState extends State<VideoBoardView> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  bool _isLoading = false;

  final TextEditingController _urlInputCtrl = TextEditingController();

  BstVideoProject _project = BstVideoProject(
    version: 2,
    title: '새 비디오 프로젝트',
    maskedRegions: [],
    timeline: [],
  );

  String? _currentBstVideoPath;

  bool _isMaskingMode = false;
  int? _maskMarkerA;

  bool _isPenMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialVidPath != null) {
      _loadBstVideo(widget.initialVidPath!);
    }
  }

  @override
  void dispose() {
    _videoController?.pause();
    _videoController?.dispose();
    _urlInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBstVideo(String path) async {
    setState(() => _isLoading = true);
    try {
      final project = await BstVideoService.instance.loadProject(path);
      final mp4Path = await BstVideoService.instance.getMp4Path(path);

      _currentBstVideoPath = path;
      _project = project;

      final oldCtrl = _videoController;
      _videoController = null;
      oldCtrl?.pause();
      await oldCtrl?.dispose();

      final controller = VideoPlayerController.file(File(mp4Path));
      await controller.initialize();
      controller.addListener(_onVideoPositionChanged);

      if (mounted) {
        setState(() {
          _videoController = controller;
          _isPlaying = false;
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('로딩 오류: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onVideoPositionChanged() {
    if (_videoController == null || !_videoController!.value.isInitialized)
      return;

    final posMs = _videoController!.value.position.inMilliseconds;

    // Masked region playback (skip regions)
    for (var region in _project.maskedRegions) {
      if (posMs >= region.startMs && posMs < region.endMs) {
        _videoController!.seekTo(Duration(milliseconds: region.endMs));
        break;
      }
    }

    // Trigger rebuild for progress bar
    setState(() {});
  }

  Future<void> _pickLocalMp4() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov', 'avi', 'mkv'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final title = p.basenameWithoutExtension(path);
      setState(() => _isLoading = true);
      try {
        final outDir = Directory.systemTemp.createTempSync('bst_pkg_');
        final outPath = p.join(outDir.path, '$title.BSTvideo');

        final initialProject = BstVideoProject(
          version: 2,
          title: title,
          maskedRegions: [],
          timeline: [],
        );

        await BstVideoService.instance.packageBstVideo(
          outputPath: outPath,
          renderedMp4: path,
          originalMp4: path,
          project: initialProject,
        );

        await _loadBstVideo(outPath);
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('로컬 MP4 가져오기 오류: $e')));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
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
        final outDir = Directory.systemTemp.createTempSync('bst_pkg_');
        final title = '웹 다운로드 영상';
        final outPath = p.join(outDir.path, '$title.BSTvideo');

        final initialProject = BstVideoProject(
          version: 2,
          title: title,
          maskedRegions: [],
          timeline: [],
        );

        await BstVideoService.instance.packageBstVideo(
          outputPath: outPath,
          renderedMp4: saveFile.path,
          originalMp4: saveFile.path,
          project: initialProject,
          sourceUrl: url,
        );

        _urlInputCtrl.clear();
        await _loadBstVideo(outPath);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류 발생: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProject() async {
    if (_currentBstVideoPath == null) return;

    final target = await SaveDestinationDialog.show(
      context: context,
      scaleFactor: widget.scaleFactor,
      title: '🎬 .BSTvideo 프로젝트 저장',
      subTitle: '저장 위치를 선택해 주세요.',
    );

    if (target == null) return;

    setState(() => _isLoading = true);
    try {
      // First save project internally
      await BstVideoService.instance.saveProject(
        _currentBstVideoPath!,
        _project,
      );

      final savePath = p.join(
        target.targetDirectory.path,
        '${_project.title}.BSTvideo',
      );
      await File(_currentBstVideoPath!).copy(savePath);

      // Cloud saves working copy
      final cloudDir = Directory(p.join(AppPaths.bstSaveRootSync, 'VIDEO'));
      if (!cloudDir.existsSync()) cloudDir.createSync(recursive: true);
      await File(
        _currentBstVideoPath!,
      ).copy(p.join(cloudDir.path, '${_project.title}.BSTvideo'));

      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('✨ 저장 완료: $savePath')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 오류: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTime(int ms) {
    final d = Duration(milliseconds: ms);
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _onTimelineTap(TapUpDetails details, double totalWidth, int durationMs) {
    final dx = details.localPosition.dx;
    final percent = (dx / totalWidth).clamp(0.0, 1.0);
    final tappedMs = (percent * durationMs).toInt();

    if (_isMaskingMode) {
      if (_maskMarkerA == null) {
        setState(() => _maskMarkerA = tappedMs);
      } else {
        final startMs = _maskMarkerA! < tappedMs ? _maskMarkerA! : tappedMs;
        final endMs = _maskMarkerA! > tappedMs ? _maskMarkerA! : tappedMs;

        setState(() {
          _project.maskedRegions.add(
            MaskedRegion(startMs: startMs, endMs: endMs, label: '마스킹'),
          );
          _maskMarkerA = null;
          _isMaskingMode = false;
        });
      }
    } else {
      _videoController?.seekTo(Duration(milliseconds: tappedMs));
    }
  }

  void _saveAnnotation() {
    if (_videoController == null) return;
    final ms = _videoController!.value.position.inMilliseconds;
    final penDir = Directory(p.join(AppPaths.bstPenRootSync, 'VIDEO'));
    if (!penDir.existsSync()) penDir.createSync(recursive: true);
    // Dummy content for bstpen
    final penFile = File(p.join(penDir.path, '$ms.bstpen'));
    penFile.writeAsStringSync('{"timestamp": $ms, "hasAnnotation": true}');

    setState(() => _isPenMode = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('판서가 저장되었습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final primaryColor = const Color(0xFF7F5AF0);
    final secondaryColor = const Color(0xFF2EC4B6);
    final accentColor = const Color(0xFFFF8906);
    final bgColor = const Color(0xFF0F0E17);

    return Scaffold(
      backgroundColor: bgColor,
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
          '🎬 Video Board',
          style: GoogleFonts.notoSansKr(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16 * s,
          ),
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2EC4B6),
              foregroundColor: Colors.black,
              padding: EdgeInsets.symmetric(
                horizontal: 10 * s,
                vertical: 6 * s,
              ),
            ),
            icon: const Icon(Icons.folder_open_rounded, size: 16),
            label: Text(
              '로컬 MP4 가져오기',
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.bold,
                fontSize: 12 * s,
              ),
            ),
            onPressed: _pickLocalMp4,
          ),
          SizedBox(width: 8 * s),
          IconButton(
            icon: Icon(Icons.save, color: primaryColor),
            onPressed: _saveProject,
            tooltip: '저장',
          ),
          SizedBox(width: 16 * s),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : Row(
              children: [
                // LEFT SIDE (65%)
                Expanded(
                  flex: 65,
                  child: Container(
                    color: Colors.black,
                    child: Column(
                      children: [
                        if (_videoController == null) ...[
                          Expanded(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '🎬 비디오 가져오기 (MP4 / YouTube)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18 * s,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 20 * s),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF2EC4B6,
                                            ),
                                            foregroundColor: Colors.black,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 16 * s,
                                              vertical: 12 * s,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.folder_open_rounded,
                                          ),
                                          label: Text(
                                            '📁 내 PC 로컬 MP4 파일 선택',
                                            style: GoogleFonts.notoSansKr(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          onPressed: _pickLocalMp4,
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 16 * s),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 360 * s,
                                          child: TextField(
                                            controller: _urlInputCtrl,
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                            decoration: InputDecoration(
                                              hintText:
                                                  '유튜브 URL 입력 (https://www.youtube.com/watch?v=...)',
                                              hintStyle: const TextStyle(
                                                color: Colors.white38,
                                              ),
                                              fillColor: Colors.white
                                                  .withOpacity(0.1),
                                              filled: true,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      10 * s,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 8 * s),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: primaryColor,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 16 * s,
                                              vertical: 14 * s,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.download_rounded,
                                          ),
                                          label: const Text(
                                            '유튜브 다운로드',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          onPressed: _addWebVideoLink,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          // Video Player
                          Expanded(
                            child: Stack(
                              children: [
                                Center(
                                  child: AspectRatio(
                                    aspectRatio:
                                        _videoController!.value.aspectRatio,
                                    child: VideoPlayer(_videoController!),
                                  ),
                                ),
                                if (_isPenMode)
                                  Positioned.fill(
                                    child: AnnotationCanvas(
                                      onClear: () {},
                                      onSave: _saveAnnotation,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Controls
                          Container(
                            color: const Color(0xFF16161A),
                            padding: EdgeInsets.symmetric(
                              horizontal: 16 * s,
                              vertical: 8 * s,
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                  ),
                                  onPressed: () {
                                    if (_isPenMode) return;
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
                                Text(
                                  '${_formatTime(_videoController!.value.position.inMilliseconds)} / ${_formatTime(_videoController!.value.duration.inMilliseconds)}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: Icon(
                                    Icons.edit,
                                    color: _isPenMode
                                        ? accentColor
                                        : Colors.white,
                                  ),
                                  tooltip: '판서 모드',
                                  onPressed: () {
                                    setState(() {
                                      _isPenMode = !_isPenMode;
                                      if (_isPenMode && _isPlaying) {
                                        _videoController!.pause();
                                        _isPlaying = false;
                                      }
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.content_cut,
                                    color: _isMaskingMode
                                        ? secondaryColor
                                        : Colors.white,
                                  ),
                                  tooltip: '✂️ 컷편집 (마스킹)',
                                  onPressed: () {
                                    setState(() {
                                      _isMaskingMode = !_isMaskingMode;
                                      _maskMarkerA = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          // Timeline Bar
                          Container(
                            height: 60 * s,
                            width: double.infinity,
                            color: const Color(0xFF1E1E24),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final totalWidth = constraints.maxWidth;
                                final durationMs = _videoController!
                                    .value
                                    .duration
                                    .inMilliseconds;
                                final currentMs = _videoController!
                                    .value
                                    .position
                                    .inMilliseconds;

                                if (durationMs == 0)
                                  return const SizedBox.shrink();

                                return GestureDetector(
                                  onTapUp: (details) => _onTimelineTap(
                                    details,
                                    totalWidth,
                                    durationMs,
                                  ),
                                  child: Stack(
                                    children: [
                                      // Progress
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        width:
                                            (currentMs / durationMs) *
                                            totalWidth,
                                        child: Container(
                                          color: primaryColor.withOpacity(0.5),
                                        ),
                                      ),
                                      // Masked Regions
                                      ..._project.maskedRegions.map((region) {
                                        final left =
                                            (region.startMs / durationMs) *
                                            totalWidth;
                                        final right =
                                            (region.endMs / durationMs) *
                                            totalWidth;
                                        return Positioned(
                                          left: left,
                                          width: right - left,
                                          top: 0,
                                          bottom: 0,
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _project.maskedRegions.remove(
                                                  region,
                                                );
                                              });
                                            },
                                            child: Container(
                                              color: Colors.black.withOpacity(
                                                0.7,
                                              ),
                                              child: const Center(
                                                child: Icon(
                                                  Icons.delete,
                                                  color: Colors.white54,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      // Marker A
                                      if (_maskMarkerA != null)
                                        Positioned(
                                          left:
                                              (_maskMarkerA! / durationMs) *
                                              totalWidth,
                                          top: 0,
                                          bottom: 0,
                                          child: Container(
                                            width: 2,
                                            color: secondaryColor,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // RIGHT SIDE (35%)
                Expanded(
                  flex: 35,
                  child: Container(
                    color: const Color(0xFF1E1E24),
                    child: Column(
                      children: [
                        Container(
                          padding: EdgeInsets.all(16 * s),
                          color: const Color(0xFF16161A),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '타임라인 인덱스',
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16 * s,
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: secondaryColor,
                                ),
                                icon: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  '현재 시간에 인덱스 추가',
                                  style: TextStyle(color: Colors.white),
                                ),
                                onPressed: () {
                                  if (_videoController == null) return;
                                  final currentMs = _videoController!
                                      .value
                                      .position
                                      .inMilliseconds;
                                  final ctrl = TextEditingController();
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: const Color(0xFF16161A),
                                      title: Text(
                                        '인덱스 추가 (${_formatTime(currentMs)})',
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                      content: TextField(
                                        controller: ctrl,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: const InputDecoration(
                                          hintText: '라벨 입력',
                                          hintStyle: TextStyle(
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('취소'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: primaryColor,
                                          ),
                                          onPressed: () {
                                            if (ctrl.text.isNotEmpty) {
                                              setState(() {
                                                _project.timeline.add(
                                                  TimelineIndex(
                                                    ms: currentMs,
                                                    label: ctrl.text,
                                                  ),
                                                );
                                                _project.timeline.sort(
                                                  (a, b) =>
                                                      a.ms.compareTo(b.ms),
                                                );
                                              });
                                              Navigator.pop(ctx);
                                            }
                                          },
                                          child: const Text(
                                            '저장',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _project.timeline.length,
                            itemBuilder: (context, index) {
                              final item = _project.timeline[index];
                              return ListTile(
                                leading: Text(
                                  _formatTime(item.ms),
                                  style: TextStyle(
                                    color: accentColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                title: Text(
                                  item.label,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.white54,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _project.timeline.removeAt(index);
                                    });
                                  },
                                ),
                                onTap: () {
                                  if (_videoController != null) {
                                    _videoController!.seekTo(
                                      Duration(milliseconds: item.ms),
                                    );
                                  }
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
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/annotation_canvas.dart';
import '../widgets/board_toolbar.dart';
import '../models/board_tools.dart';

class VideoBoardView extends StatefulWidget {
  final String filePath;
  final double scaleFactor;

  const VideoBoardView({
    super.key,
    required this.filePath,
    required this.scaleFactor,
  });

  @override
  State<VideoBoardView> createState() => _VideoBoardViewState();
}

class _VideoBoardViewState extends State<VideoBoardView> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String _durationText = '00:00 / 00:00';
  double _sliderValue = 0.0;
  bool _userScrubbing = false;

  // 판서 도구 상태
  late AnnotationController _annotationController;
  Color _penColor = const Color(0xFFEF4565);
  double _strokeWidth = 4.0;
  ToolMode _tool = ToolMode.pen;
  ShapeType _activeShape = ShapeType.line;
  bool _eraseEntireStroke = false;
  double _eraserSize = 30.0;

  @override
  void initState() {
    super.initState();
    _annotationController = AnnotationController();
    _loadEraserPrefs();
    _initVideo();
  }

  Future<void> _loadEraserPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _eraseEntireStroke = prefs.getBool('whiteboard_erase_entire') ?? false;
      _eraserSize = prefs.getDouble('whiteboard_eraser_size') ?? 30.0;
    });
    _syncControllerTooling();
  }

  void _syncControllerTooling() {
    _annotationController.toolMode = _tool;
    _annotationController.activeColor = _penColor;
    _annotationController.activeWidth = _strokeWidth;
    _annotationController.eraseEntireStroke = _eraseEntireStroke;
    _annotationController.eraserSize = _eraserSize;
    _annotationController.activeShape = _activeShape;
  }

  void _initVideo() {
    final file = File(widget.filePath);
    _controller = VideoPlayerController.file(file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
          _isPlaying = _controller.value.isPlaying;
        });
        _controller.addListener(_videoListener);
        _controller.play();
      });
  }

  void _videoListener() {
    if (!mounted || _userScrubbing) return;

    final pos = _controller.value.position;
    final dur = _controller.value.duration;
    
    setState(() {
      _isPlaying = _controller.value.isPlaying;
      if (dur.inMilliseconds > 0) {
        _sliderValue = pos.inMilliseconds / dur.inMilliseconds;
      }
      _durationText = '${_formatDuration(pos)} / ${_formatDuration(dur)}';
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _togglePlay() {
    if (!_isInitialized) return;
    setState(() {
      if (_isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
      _isPlaying = !_isPlaying;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_videoListener);
    _controller.dispose();
    _annotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 비디오 화면 레이어
          if (_isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4))),

          // 2. 판서 캔버스 레이어
          Positioned.fill(
            child: AnnotationCanvas(
              controller: _annotationController,
              enabled: _tool == ToolMode.pen || _tool == ToolMode.eraser || _tool == ToolMode.select || _tool == ToolMode.shape,
            ),
          ),

          // 3. 상단 제어 바 (파일명 및 닫기)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 24 * s, vertical: 16 * s),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      File(widget.filePath).uri.pathSegments.last,
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 16 * s,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 4. 비디오 재생 퀵 컨트롤러 바
          Positioned(
            bottom: 84 * s,
            left: 32 * s,
            right: 32 * s,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28 * s,
                    ),
                    onPressed: _togglePlay,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _durationText,
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12 * s),
                  ),
                  Expanded(
                    child: Slider(
                      activeColor: const Color(0xFF00F5D4),
                      inactiveColor: Colors.white24,
                      value: _sliderValue.clamp(0.0, 1.0),
                      onChangeStart: (_) {
                        _userScrubbing = true;
                      },
                      onChanged: (val) {
                        setState(() {
                          _sliderValue = val;
                        });
                      },
                      onChangeEnd: (val) async {
                        if (_isInitialized) {
                          final duration = _controller.value.duration;
                          final target = duration * val;
                          await _controller.seekTo(target);
                        }
                        _userScrubbing = false;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 5. 판서 도구 플로팅 툴바
          Positioned(
            bottom: 16 * s,
            left: 16 * s,
            right: 16 * s,
            child: Center(
              child: _buildFloatingToolbar(s),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingToolbar(double scale) {
    return BoardDockToolbar(
      scale: scale,
      tool: _tool,
      onToolChanged: (mode) {
        setState(() {
          _tool = mode;
        });
        _syncControllerTooling();
      },
      strokeWidth: _strokeWidth,
      onStrokeWidthChanged: (w) {
        setState(() {
          _strokeWidth = w;
          _tool = ToolMode.pen;
        });
        _syncControllerTooling();
      },
      penColor: _penColor,
      onColorChanged: (c) {
        setState(() {
          _penColor = c;
          _tool = ToolMode.pen;
        });
        _syncControllerTooling();
      },
      activeShape: _activeShape,
      onShapeChanged: (shape) {
        setState(() {
          _activeShape = shape;
          _tool = ToolMode.shape;
        });
        _syncControllerTooling();
      },
      onUndo: _annotationController.undo,
      onClear: () => setState(() => _annotationController.clear()),
      onClose: () => Navigator.pop(context),
      eraseEntireStroke: _eraseEntireStroke,
      onEraseEntireStrokeChanged: (val) async {
        setState(() => _eraseEntireStroke = val);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('whiteboard_erase_entire', val);
        _syncControllerTooling();
      },
      eraserSize: _eraserSize,
      onEraserSizeChanged: (val) async {
        setState(() => _eraserSize = val);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('whiteboard_eraser_size', val);
        _syncControllerTooling();
      },
    );
  }
}

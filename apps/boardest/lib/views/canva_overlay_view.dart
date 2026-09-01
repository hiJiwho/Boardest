import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../helpers/iframe_view_helper.dart';

/// Canva 웹 임베드 + Boardest 펜 판서 레이어 결합 뷰어
class CanvaOverlayView extends StatefulWidget {
  final String canvaId;
  final String title;
  final String? localFilePath;
  final double scaleFactor;

  const CanvaOverlayView({
    super.key,
    required this.canvaId,
    required this.title,
    this.localFilePath,
    this.scaleFactor = 1.0,
  });

  @override
  State<CanvaOverlayView> createState() => _CanvaOverlayViewState();
}

class _CanvaOverlayViewState extends State<CanvaOverlayView> {
  late String _viewType;
  bool _isPenActive = false;
  Color _penColor = const Color(0xFF00F5D4);
  double _penStroke = 3.0;

  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];

  @override
  void initState() {
    super.initState();
    _viewType = 'canva-embed-${widget.canvaId}-${DateTime.now().millisecondsSinceEpoch}';
  }

  String _extractCanvaEmbedUrl(String raw) {
    if (raw.isEmpty) return 'https://www.canva.com';
    if (raw.startsWith('http') && raw.contains('embed')) {
      return raw;
    }
    final match = RegExp(r'/design/([a-zA-Z0-9_-]+)').firstMatch(raw);
    if (match != null && match.groupCount >= 1) {
      final designId = match.group(1)!;
      return 'https://www.canva.com/design/$designId/view?embed';
    }
    final cleanId = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (cleanId.isNotEmpty) {
      return 'https://www.canva.com/design/$cleanId/view?embed';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final canvaUrl = _extractCanvaEmbedUrl(widget.canvaId);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // 1. Canva Web Embed
          Positioned.fill(
            child: getIframeViewWidget(_viewType, canvaUrl),
          ),

          // 2. Ink Drawing Layer (Active when pen mode is on)
          if (_isPenActive)
            Positioned.fill(
              child: GestureDetector(
                onPanStart: (details) {
                  setState(() {
                    _currentStroke = [details.localPosition];
                    _strokes.add(_currentStroke);
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    _currentStroke.add(details.localPosition);
                  });
                },
                onPanEnd: (_) {
                  setState(() {
                    _currentStroke = [];
                  });
                },
                child: CustomPaint(
                  painter: _CanvaStrokePainter(strokes: _strokes, color: _penColor, strokeWidth: _penStroke),
                ),
              ),
            ),

          // 3. Top Floating Control Bar
          Positioned(
            top: 14 * s,
            left: 14 * s,
            right: 14 * s,
            child: Row(
              children: [
                // Back / Close
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12 * s),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                SizedBox(width: 10 * s),
                // Title Badge
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 8 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12 * s),
                    border: Border.all(color: const Color(0xFF00C4CC).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.palette_rounded, color: Color(0xFF00C4CC), size: 18),
                      SizedBox(width: 8 * s),
                      Text(
                        widget.title,
                        style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * s, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Pen / Eraser Toolbar
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12 * s),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit_rounded, color: _isPenActive ? const Color(0xFF00F5D4) : Colors.white60),
                        tooltip: '판서 모드 전환',
                        onPressed: () => setState(() => _isPenActive = !_isPenActive),
                      ),
                      if (_isPenActive) ...[
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                          tooltip: '판서 모두 지우기',
                          onPressed: () => setState(() => _strokes.clear()),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CanvaStrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color color;
  final double strokeWidth;

  _CanvaStrokePainter({required this.strokes, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvaStrokePainter oldDelegate) => true;
}

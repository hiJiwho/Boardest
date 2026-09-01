import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Boardest 단일화 판서 오버레이 레이어 (`UnifiedPenOverlay`)
/// PDF, PPT, TBP, Web, Canva 등 모든 뷰어를 감싸 동일한 펜/형광펜/지우개/레이저/페이지 툴바를 제공합니다.
class UnifiedPenOverlay extends StatefulWidget {
  final Widget child;
  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onSave;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int>? onPageChanged;

  const UnifiedPenOverlay({
    super.key,
    required this.child,
    required this.title,
    this.onClose,
    this.onSave,
    this.currentPage = 1,
    this.totalPages = 1,
    this.onPageChanged,
  });

  @override
  State<UnifiedPenOverlay> createState() => _UnifiedPenOverlayState();
}

enum PenMode { none, pen, highlighter, eraser, laser }

class _Point {
  final Offset offset;
  final Color color;
  final double strokeWidth;
  final bool isHighlighter;

  _Point({
    required this.offset,
    required this.color,
    required this.strokeWidth,
    this.isHighlighter = false,
  });
}

class _Stroke {
  final List<_Point> points;
  _Stroke(this.points);
}

class _UnifiedPenOverlayState extends State<UnifiedPenOverlay> {
  PenMode _mode = PenMode.none;
  Color _currentColor = const Color(0xFFFF0055);
  double _penWidth = 4.0;
  
  final List<_Stroke> _strokes = [];
  _Stroke? _currentStroke;
  Offset? _laserPosition;

  final List<Color> _palette = [
    const Color(0xFFFF0055), // Vibrant Red
    const Color(0xFF00F5D4), // Teal / Mint
    const Color(0xFFFFD166), // Yellow
    const Color(0xFF00B4D8), // Blue
    const Color(0xFFFFFFFF), // White
    const Color(0xFF000000), // Black
  ];

  void _onPanStart(DragStartDetails details) {
    if (_mode == PenMode.none) return;
    if (_mode == PenMode.laser) {
      setState(() => _laserPosition = details.localPosition);
      return;
    }

    final point = _Point(
      offset: details.localPosition,
      color: _mode == PenMode.highlighter ? _currentColor.withOpacity(0.4) : _currentColor,
      strokeWidth: _mode == PenMode.highlighter ? _penWidth * 3.5 : _penWidth,
      isHighlighter: _mode == PenMode.highlighter,
    );

    setState(() {
      _currentStroke = _Stroke([point]);
      _strokes.add(_currentStroke!);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_mode == PenMode.none) return;
    if (_mode == PenMode.laser) {
      setState(() => _laserPosition = details.localPosition);
      return;
    }

    if (_mode == PenMode.eraser) {
      final pos = details.localPosition;
      setState(() {
        _strokes.removeWhere((stroke) =>
          stroke.points.any((pt) => (pt.offset - pos).distance < 20.0));
      });
      return;
    }

    if (_currentStroke != null) {
      final point = _Point(
        offset: details.localPosition,
        color: _mode == PenMode.highlighter ? _currentColor.withOpacity(0.4) : _currentColor,
        strokeWidth: _mode == PenMode.highlighter ? _penWidth * 3.5 : _penWidth,
        isHighlighter: _mode == PenMode.highlighter,
      );
      setState(() {
        _currentStroke!.points.add(point);
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_mode == PenMode.laser) {
      setState(() => _laserPosition = null);
    }
    _currentStroke = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Underlying Content (PDF, Web, Canva, PPT, etc.)
          Positioned.fill(child: widget.child),

          // 2. Drawing Canvas Layer
          if (_mode != PenMode.none)
            Positioned.fill(
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: CustomPaint(
                  painter: _PenPainter(
                    strokes: _strokes,
                    laserPosition: _laserPosition,
                  ),
                ),
              ),
            ),

          // 3. Top Custom Window Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF131418).withOpacity(0.85),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
                    onPressed: widget.onClose ?? () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.title,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (widget.onSave != null)
                    ElevatedButton.icon(
                      onPressed: widget.onSave,
                      icon: const Icon(Icons.save_alt_rounded, size: 16),
                      label: const Text('내보내기 / 저장'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7F5AF0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 4. Floating Unified Pen Toolbar (Bottom Center)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1D24).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, spreadRadius: 2),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mode Selectors
                    _buildToolButton(Icons.mouse_rounded, PenMode.none, '선택/조작'),
                    _buildToolButton(Icons.edit_rounded, PenMode.pen, '펜'),
                    _buildToolButton(Icons.border_color_rounded, PenMode.highlighter, '형광펜'),
                    _buildToolButton(Icons.auto_fix_high_rounded, PenMode.laser, '레이저 포인터'),
                    _buildToolButton(Icons.cleaning_services_rounded, PenMode.eraser, '지우개'),
                    
                    const SizedBox(width: 8),
                    Container(height: 24, width: 1, color: Colors.white24),
                    const SizedBox(width: 8),

                    // Color Palette (Only when Pen/Highlighter selected)
                    if (_mode == PenMode.pen || _mode == PenMode.highlighter) ...[
                      ..._palette.map((color) => GestureDetector(
                        onTap: () => setState(() => _currentColor = color),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _currentColor == color ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      )),
                      const SizedBox(width: 8),
                      Container(height: 24, width: 1, color: Colors.white24),
                      const SizedBox(width: 8),
                    ],

                    // Clear All
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 20),
                      tooltip: '판서 전체 지우기',
                      onPressed: () => setState(() => _strokes.clear()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(IconData icon, PenMode mode, String label) {
    final isSelected = _mode == mode;
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon, color: isSelected ? const Color(0xFF00F5D4) : Colors.white60, size: 20),
        onPressed: () => setState(() => _mode = mode),
      ),
    );
  }
}

class _PenPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final Offset? laserPosition;

  _PenPainter({required this.strokes, this.laserPosition});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.points.first.color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke.points.first.strokeWidth
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(stroke.points.first.offset.dx, stroke.points.first.offset.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].offset.dx, stroke.points[i].offset.dy);
      }
      canvas.drawPath(path, paint);
    }

    if (laserPosition != null) {
      final laserPaint = Paint()
        ..color = const Color(0xFFFF0055)
        ..style = PaintingStyle.fill;
      final glowPaint = Paint()
        ..color = const Color(0xFFFF0055).withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      canvas.drawCircle(laserPosition!, 12, glowPaint);
      canvas.drawCircle(laserPosition!, 6, laserPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

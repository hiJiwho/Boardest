import 'dart:math';
import 'package:flutter/material.dart';
import '../models/board_tools.dart';

class AnnotationStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;

  AnnotationStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
  });

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    'color': color.value,
    'strokeWidth': strokeWidth,
    'isEraser': isEraser,
  };

  factory AnnotationStroke.fromJson(Map<String, dynamic> json) {
    final pts = (json['points'] as List)
        .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
        .toList();
    return AnnotationStroke(
      points: pts,
      color: Color(json['color'] as int),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      isEraser: json['isEraser'] as bool? ?? false,
    );
  }

  AnnotationStroke translate(Offset delta) {
    return AnnotationStroke(
      points: points.map((p) => p + delta).toList(),
      color: color,
      strokeWidth: strokeWidth,
      isEraser: isEraser,
    );
  }
}

class AnnotationController extends ChangeNotifier {
  final List<AnnotationStroke> _strokes = [];
  final List<List<AnnotationStroke>> _undoHistory = [];

  ToolMode toolMode = ToolMode.pen;
  Color activeColor = Colors.white;
  double activeWidth = 4.0;
  bool eraseEntireStroke = false;
  double eraserSize = 30.0;

  // Lasso (Selection) Tool States
  List<Offset> lassoPolygon = [];
  bool isLassoActive = false;
  List<int> selectedStrokeIndices = [];
  List<Offset> lastLassoPolygon = [];
  Offset? dragSelectedStart;

  bool get isEraser => toolMode == ToolMode.eraser;
  set isEraser(bool val) {
    toolMode = val ? ToolMode.eraser : ToolMode.pen;
    notifyListeners();
  }

  List<AnnotationStroke> get strokes => _strokes;

  // Ray-casting point-in-polygon algorithm for Lasso Selection
  bool isPointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].dy > point.dy) != (polygon[j].dy > point.dy) &&
          (point.dx < (polygon[j].dx - polygon[i].dx) * (point.dy - polygon[i].dy) / (polygon[j].dy - polygon[i].dy) + polygon[i].dx)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  void checkLassoSelection() {
    if (lassoPolygon.length < 3) return;
    lastLassoPolygon = List.from(lassoPolygon);
    final selected = <int>[];
    for (int i = 0; i < _strokes.length; i++) {
      final stroke = _strokes[i];
      if (stroke.isEraser) continue;
      bool hasPointInside = stroke.points.any((p) => isPointInPolygon(p, lassoPolygon));
      if (hasPointInside) {
        selected.add(i);
      }
    }
    selectedStrokeIndices = selected;
    notifyListeners();
  }

  void clearLassoSelection() {
    selectedStrokeIndices.clear();
    lastLassoPolygon.clear();
    lassoPolygon.clear();
    notifyListeners();
  }

  void notifyLassoChanged() {
    notifyListeners();
  }

  void startDraggingSelected() {
    _saveToHistory();
  }

  void dragSelectedStrokes(Offset delta) {
    if (selectedStrokeIndices.isEmpty) return;
    for (final idx in selectedStrokeIndices) {
      if (idx < _strokes.length) {
        _strokes[idx] = _strokes[idx].translate(delta);
      }
    }
    notifyListeners();
  }

  void clear() {
    _saveToHistory();
    _strokes.clear();
    notifyListeners();
  }

  void _saveToHistory() {
    if (_strokes.isEmpty) return;
    _undoHistory.add(List<AnnotationStroke>.from(_strokes));
    if (_undoHistory.length > 30) {
      _undoHistory.removeAt(0);
    }
  }

  void undo() {
    if (_undoHistory.isEmpty) return;
    _strokes.clear();
    _strokes.addAll(_undoHistory.removeLast());
    notifyListeners();
  }

  double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-6) return (p - a).distance;
    final t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
    final clamped = t.clamp(0.0, 1.0);
    final closest = Offset(a.dx + ab.dx * clamped, a.dy + ab.dy * clamped);
    return (p - closest).distance;
  }

  bool _strokeTouchedByEraser(List<Offset> points, Offset center, double radius) {
    for (final pt in points) {
      if ((pt - center).distance < radius) return true;
    }
    for (int i = 1; i < points.length; i++) {
      if (_distancePointToSegment(center, points[i - 1], points[i]) < radius) return true;
    }
    return false;
  }

  List<Offset> _densifyPolyline(List<Offset> points, double step) {
    if (points.length < 2) return List<Offset>.from(points);
    final out = <Offset>[points.first];
    for (int i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final len = (b - a).distance;
      if (len <= step) {
        out.add(b);
      } else {
        final steps = (len / step).ceil();
        for (int k = 1; k <= steps; k++) {
          out.add(Offset.lerp(a, b, k / steps)!);
        }
      }
    }
    return out;
  }

  List<List<Offset>> _splitPolylineByEraser(List<Offset> points, Offset center, double radius) {
    final segments = <List<Offset>>[];
    var current = <Offset>[];

    void flush() {
      if (current.length >= 2) segments.add(List<Offset>.from(current));
      current = [];
    }

    for (final pt in points) {
      if ((pt - center).distance < radius) {
        if (current.isNotEmpty) flush();
      } else {
        current.add(pt);
      }
    }
    flush();
    return segments;
  }

  void eraseAt(Offset center) {
    final radius = eraserSize;
    final newStrokes = <AnnotationStroke>[];
    bool changed = false;

    for (final stroke in _strokes) {
      if (stroke.isEraser) continue;

      if (eraseEntireStroke) {
        if (_strokeTouchedByEraser(stroke.points, center, radius)) {
          changed = true;
        } else {
          newStrokes.add(stroke);
        }
      } else {
        final sampleStep = min(4.0, radius / 3);
        final dense = stroke.points.length >= 2
            ? _densifyPolyline(stroke.points, sampleStep)
            : stroke.points;
        final parts = _splitPolylineByEraser(dense, center, radius);

        if (parts.isEmpty) {
          changed = true;
        } else if (parts.length == 1 &&
            parts.first.length == dense.length &&
            dense.length == stroke.points.length) {
          newStrokes.add(stroke);
        } else {
          changed = true;
          for (final seg in parts) {
            newStrokes.add(AnnotationStroke(
              points: seg,
              color: stroke.color,
              strokeWidth: stroke.strokeWidth,
            ));
          }
        }
      }
    }

    if (changed) {
      _strokes.clear();
      _strokes.addAll(newStrokes);
      notifyListeners();
    }
  }

  void beginStroke(Offset point) {
    _saveToHistory();
    _strokes.add(AnnotationStroke(
      points: [point],
      color: activeColor,
      strokeWidth: activeWidth,
    ));
    notifyListeners();
  }

  void extendStroke(Offset point) {
    if (_strokes.isEmpty) return;
    final last = _strokes.removeLast();
    _strokes.add(AnnotationStroke(
      points: [...last.points, point],
      color: last.color,
      strokeWidth: last.strokeWidth,
    ));
    notifyListeners();
  }

  void addStroke(AnnotationStroke stroke) {
    _saveToHistory();
    _strokes.add(stroke);
    notifyListeners();
  }
}

class AnnotationCanvas extends StatefulWidget {
  final AnnotationController controller;
  final bool enabled;
  final Function(Offset localPosition)? onRightClick;

  const AnnotationCanvas({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onRightClick,
  });

  @override
  State<AnnotationCanvas> createState() => _AnnotationCanvasState();
}

class _AnnotationCanvasState extends State<AnnotationCanvas> {
  final GlobalKey _canvasKey = GlobalKey();
  List<Offset> _activePoints = [];
  bool _isDrawing = false;

  Offset _local(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  void _onPanStart(DragStartDetails d) {
    if (!widget.enabled) return;
    final p = _local(d.globalPosition);

    final ctrl = widget.controller;
    if (ctrl.toolMode == ToolMode.eraser) {
      ctrl.eraseAt(p);
      setState(() {
        _isDrawing = true;
      });
      return;
    }
    if (ctrl.toolMode == ToolMode.select) {
      if (ctrl.selectedStrokeIndices.isNotEmpty && ctrl.isPointInPolygon(p, ctrl.lastLassoPolygon)) {
        ctrl.dragSelectedStart = p;
        ctrl.startDraggingSelected();
      } else {
        ctrl.clearLassoSelection();
        ctrl.isLassoActive = true;
        ctrl.lassoPolygon = [p];
      }
      setState(() {});
      return;
    }
    if (ctrl.toolMode != ToolMode.pen) return;

    setState(() {
      _isDrawing = true;
      _activePoints = [p];
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!widget.enabled) return;
    final p = _local(d.globalPosition);

    final ctrl = widget.controller;
    if (ctrl.toolMode == ToolMode.eraser) {
      ctrl.eraseAt(p);
      return;
    }
    if (ctrl.toolMode == ToolMode.select) {
      if (ctrl.dragSelectedStart != null) {
        final delta = p - ctrl.dragSelectedStart!;
        ctrl.dragSelectedStrokes(delta);
        ctrl.dragSelectedStart = p;
        ctrl.lastLassoPolygon = ctrl.lastLassoPolygon.map((pt) => pt + delta).toList();
      } else if (ctrl.isLassoActive) {
        ctrl.lassoPolygon.add(p);
        ctrl.notifyLassoChanged(); // Force repaint
      }
      return;
    }
    if (ctrl.toolMode != ToolMode.pen) return;

    setState(() {
      _activePoints.add(p);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    final ctrl = widget.controller;
    if (ctrl.toolMode == ToolMode.select) {
      if (ctrl.isLassoActive) {
        ctrl.checkLassoSelection();
        ctrl.isLassoActive = false;
        ctrl.lassoPolygon.clear();
        setState(() {});
      }
      ctrl.dragSelectedStart = null;
      return;
    }
    if (_isDrawing) {
      if (ctrl.toolMode == ToolMode.pen && _activePoints.isNotEmpty) {
        final stroke = AnnotationStroke(
          points: List<Offset>.from(_activePoints),
          color: ctrl.activeColor,
          strokeWidth: ctrl.activeWidth,
        );
        ctrl.addStroke(stroke);
      }
      setState(() {
        _isDrawing = false;
        _activePoints = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _canvasKey,
      behavior: widget.enabled ? HitTestBehavior.opaque : HitTestBehavior.translucent,
      onPanStart: widget.enabled ? _onPanStart : null,
      onPanUpdate: widget.enabled ? _onPanUpdate : null,
      onPanEnd: widget.enabled ? _onPanEnd : null,
      onSecondaryTapUp: (details) {
        if (widget.onRightClick != null) {
          widget.onRightClick!(details.localPosition);
        }
      },
      child: RepaintBoundary(
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _AnnotationPainter(
                strokes: widget.controller.strokes,
                activePoints: _isDrawing ? _activePoints : null,
                activeColor: widget.controller.activeColor,
                activeWidth: widget.controller.activeWidth,
                lassoPolygon: widget.controller.lassoPolygon,
                lastLassoPolygon: widget.controller.selectedStrokeIndices.isNotEmpty 
                    ? widget.controller.lastLassoPolygon 
                    : null,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final List<AnnotationStroke> strokes;
  final List<Offset>? activePoints;
  final Color activeColor;
  final double activeWidth;
  final List<Offset>? lassoPolygon;
  final List<Offset>? lastLassoPolygon;

  _AnnotationPainter({
    required this.strokes,
    this.activePoints,
    required this.activeColor,
    required this.activeWidth,
    this.lassoPolygon,
    this.lastLassoPolygon,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw completed strokes
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }

      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.strokeWidth / 2, paint);
      } else {
        canvas.drawPath(path, paint);
      }
    }

    // 2. Draw active stroke in real-time
    if (activePoints != null && activePoints!.isNotEmpty) {
      final paint = Paint()
        ..color = activeColor
        ..strokeWidth = activeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path()..moveTo(activePoints!.first.dx, activePoints!.first.dy);
      for (int i = 1; i < activePoints!.length; i++) {
        path.lineTo(activePoints![i].dx, activePoints![i].dy);
      }

      if (activePoints!.length == 1) {
        canvas.drawCircle(activePoints!.first, activeWidth / 2, paint);
      } else {
        canvas.drawPath(path, paint);
      }
    }

    // 3. Draw active lasso polygon
    if (lassoPolygon != null && lassoPolygon!.isNotEmpty) {
      final lassoPaint = Paint()
        ..color = const Color(0xFF00F5D4).withOpacity(0.8)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final lassoFill = Paint()
        ..color = const Color(0xFF00F5D4).withOpacity(0.08)
        ..style = PaintingStyle.fill;

      final path = Path()..moveTo(lassoPolygon!.first.dx, lassoPolygon!.first.dy);
      for (int i = 1; i < lassoPolygon!.length; i++) {
        path.lineTo(lassoPolygon![i].dx, lassoPolygon![i].dy);
      }
      path.close();
      canvas.drawPath(path, lassoFill);
      canvas.drawPath(path, lassoPaint);
    }

    // 4. Draw selected lasso boundary highlight
    if (lastLassoPolygon != null && lastLassoPolygon!.isNotEmpty) {
      final selectedPaint = Paint()
        ..color = const Color(0xFF00F5D4).withOpacity(0.9)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      final selectedFill = Paint()
        ..color = const Color(0xFF00F5D4).withOpacity(0.12)
        ..style = PaintingStyle.fill;

      final path = Path()..moveTo(lastLassoPolygon!.first.dx, lastLassoPolygon!.first.dy);
      for (int i = 1; i < lastLassoPolygon!.length; i++) {
        path.lineTo(lastLassoPolygon![i].dx, lastLassoPolygon![i].dy);
      }
      path.close();
      canvas.drawPath(path, selectedFill);
      canvas.drawPath(path, selectedPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}

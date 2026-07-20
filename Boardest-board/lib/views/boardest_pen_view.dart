import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/calculator_modal.dart';
import '../widgets/notepad_modal.dart';
import '../widgets/usb_explorer.dart';
import '../models/board_tools.dart';
import '../services/board_storage_service.dart';
import '../services/bst_save_service.dart';

// ═══════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════

class DrawingStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final StrokeType type;

  DrawingStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.type,
  });

  DrawingStroke translate(Offset offset) {
    return DrawingStroke(
      points: points.map((p) => p + offset).toList(),
      color: color,
      strokeWidth: strokeWidth,
      type: type,
    );
  }
}

enum StrokeType { pen, marker, pencil, brush, cali, eraser }

enum ElementType { image, table, formula, timer }

class BoardElement {
  final String id;
  final ElementType type;
  Offset position;
  Size size;
  final String? url;
  final String? text;
  final List<List<String>>? tableData;
  int timerSeconds;
  bool timerRunning;
  int timerRemaining;
  final Uint8List? imageBytes;

  BoardElement({
    required this.id,
    required this.type,
    required this.position,
    required this.size,
    this.url,
    this.text,
    this.tableData,
    this.timerSeconds = 0,
    this.timerRunning = false,
    this.timerRemaining = 0,
    this.imageBytes,
  });
}

class BoardestPenView extends StatefulWidget {
  final String filePath;
  final double scaleFactor;
  final String? teacher;
  final String? subject;

  const BoardestPenView({
    super.key,
    required this.filePath,
    required this.scaleFactor,
    this.teacher,
    this.subject,
  });

  @override
  State<BoardestPenView> createState() => _BoardestPenViewState();
}

class _BoardestPenViewState extends State<BoardestPenView> with TickerProviderStateMixin {
  late String _activeFilePath;

  // ── Pages ─────────────────────────────────────────────
  int _currentPage = 1;
  int _totalPages = 1;
  final Map<int, List<DrawingStroke>> _pageStrokes = {};
  final Map<int, List<List<DrawingStroke>>> _undoHistory = {};
  final Map<int, List<List<DrawingStroke>>> _redoStack = {};
  final Map<int, List<BoardElement>> _pageElements = {};

  // ── Infinite Canvas & Panning ──────────────────────────
  Offset _canvasOffset = Offset.zero;
  Offset? _panStart;

  // ── Lasso / Selection (올가미) ─────────────────────────
  List<Offset> _lassoPolygon = []; // Tracks the lasso drawing path
  bool _isLassoActive = false;
  List<int> _selectedStrokeIndices = []; // Indices of strokes currently selected by lasso
  Offset? _dragSelectedStart;
  bool _selectEntireStroke = true; // true: 획 선택, false: 부분 선택
  List<Offset> _lastLassoPolygon = []; // Keeps copy of the last drawn lasso path
  bool _eraseEntireStroke = false; // true: 획 지우개, false: 부분 지우개
  double _eraserSize = 30.0; // 지우개 반경 크기

  // ── Drawing ───────────────────────────────────────────
  List<Offset> _activePoints = [];
  bool _isDrawing = false;
  Offset? _shapeStart;

  // ── Tool state ────────────────────────────────────────
  ToolMode _tool = ToolMode.pen;
  Color _penColor = Colors.white;
  double _strokeWidth = 4.0;
  StrokeType _strokeType = StrokeType.pen;
  ShapeType _activeShape = ShapeType.line;

  // ── Background Configuration ──────────────────────────
  Color _boardBgColor = const Color(0xFF0F0E17);
  String _bgPattern = 'none'; // 'none', 'grid', 'line'
  bool _isMenuOpen = false;
  bool _isPenDetailsOpen = false;
  bool _isShapeDetailsOpen = false;

  // ── Stylus / Palm Rejection ───────────────────────────
  PointerDeviceKind? _lastPointerKind;
  bool _palmRejectionEnabled = false; // 손바닥 터치 오작동 방지
  bool _hasSeenStylus = false; // 스타일러스 펜 사용 감지 여부

  // ── Timers / Keys ──────────────────────────────────────
  final GlobalKey _canvasKey = GlobalKey();
  final Map<String, Timer> _activeTimers = {};

  @override
  void initState() {
    super.initState();
    _activeFilePath = widget.filePath;
    _initPage(1);
    _loadPersistentSettings();
    if (_activeFilePath.toLowerCase().endsWith('.iwb')) {
      _loadIwb(_activeFilePath);
    }
  }

  String get _boardFileBaseName => p.basenameWithoutExtension(_activeFilePath);

  bool get _isBstSaveBoard =>
      _activeFilePath.contains(p.join('BstSave', 'Board'));

  Future<void> _loadIwb(String path) async {
    try {
      final loaded = await BoardStorageService.instance.loadBoardFromPath(path);
      if (loaded != null) {
        _applyLoadedStrokes(loaded.totalPages, loaded.pageStrokes);
        return;
      }

      final file = File(path);
      if (!await file.exists()) return;

      final contents = await file.readAsString();
      final iwbData = json.decode(contents) as Map<String, dynamic>;

      final pagesData = iwbData['pages'] as Map<String, dynamic>? ?? {};
      final Map<int, List<Map<String, dynamic>>> pageStrokes = {};
      pagesData.forEach((key, value) {
        final idx = int.tryParse(key);
        if (idx == null || value is! List) return;
        pageStrokes[idx] = value
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });

      final totalPages = (iwbData['totalPages'] as num?)?.toInt() ??
          (pageStrokes.keys.isEmpty ? 1 : pageStrokes.keys.reduce((a, b) => a > b ? a : b));

      _applyLoadedStrokes(totalPages, pageStrokes);
    } catch (e) {
      debugPrint('Error loading IWB: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('IWB 파일을 불러오는 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  void _applyLoadedStrokes(
    int totalPages,
    Map<int, List<Map<String, dynamic>>> pageStrokes,
  ) {
    setState(() {
      _totalPages = totalPages.clamp(1, 999);
      _pageStrokes.clear();
      for (int p = 1; p <= _totalPages; p++) {
        _initPage(p);
        final pageStrokesData = pageStrokes[p] ?? [];
        _pageStrokes[p] = pageStrokesData.map(_strokeFromMap).toList();
      }
      _currentPage = 1;
    });
  }

  DrawingStroke _strokeFromMap(Map<String, dynamic> strokeData) {
    try {
      final pointsData = strokeData['points'] as List<dynamic>? ?? [];
      final points = pointsData
          .map((pt) {
            final dx = pt['dx'];
            final dy = pt['dy'];
            return Offset(
              dx is num ? dx.toDouble() : 0.0,
              dy is num ? dy.toDouble() : 0.0,
            );
          })
          .toList();

      final isEraser = strokeData['isEraser'] as bool? ?? false;
      final typeIndex = strokeData['type'] as int?;
      final type = typeIndex != null
          ? StrokeType.values[typeIndex.clamp(0, StrokeType.values.length - 1)]
          : (isEraser ? StrokeType.eraser : StrokeType.pen);

      final colorVal = strokeData['color'];
      Color color = Colors.white;
      if (colorVal is int) {
        color = Color(colorVal);
      } else if (colorVal is String) {
        color = Color(int.tryParse(colorVal) ?? 0xFFFFFFFF);
      }

      final wVal = strokeData['strokeWidth'];
      final strokeWidth = wVal is num ? wVal.toDouble() : 4.0;

      return DrawingStroke(
        points: points,
        color: color,
        strokeWidth: strokeWidth,
        type: type,
      );
    } catch (e) {
      debugPrint('Error parsing stroke: $e');
      return DrawingStroke(
        points: [],
        color: Colors.white,
        strokeWidth: 4.0,
        type: StrokeType.pen,
      );
    }
  }

  Map<String, dynamic> _strokeToMap(DrawingStroke stroke) => {
        'points': stroke.points.map((pt) => {'dx': pt.dx, 'dy': pt.dy}).toList(),
        'color': stroke.color.value,
        'strokeWidth': stroke.strokeWidth,
        'type': stroke.type.index,
      };

  Future<void> _saveBoardMapping(String targetPath) async {
    if (widget.teacher == null || widget.subject == null) return;
    await BoardStorageService.instance.setMappedBoardPath(
      widget.teacher!,
      widget.subject!,
      targetPath,
    );
  }

  Future<void> _autoSaveBoard() async {
    try {
      final Map<int, List<Map<String, dynamic>>> pageData = {};
      for (int pIndex = 1; pIndex <= _totalPages; pIndex++) {
        final strokes = _pageStrokes[pIndex] ?? [];
        pageData[pIndex] = strokes.map(_strokeToMap).toList();
      }

      if (_isBstSaveBoard ||
          (widget.teacher != null && widget.subject != null)) {
        final dir = await BstSaveService.instance.directoryFor(BstSaveService.subBoard);
        if (!_activeFilePath.startsWith(dir.path)) {
          _activeFilePath = p.join(dir.path, '$_boardFileBaseName.iwb');
        }

        final metadata = <String, dynamic>{
          'teacher': widget.teacher ?? '',
          'subject': widget.subject ?? '',
          'updatedAt': DateTime.now().toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
        };

        final existing =
            await BoardStorageService.instance.loadBoardMetadata(_boardFileBaseName);
        if (existing != null && existing['createdAt'] != null) {
          metadata['createdAt'] = existing['createdAt'];
        }

        await BoardStorageService.instance.saveBoardStrokes(
          fileBaseName: _boardFileBaseName,
          metadata: metadata,
          pageStrokes: pageData,
        );

        if (widget.teacher != null && widget.subject != null) {
          await _saveBoardMapping(_activeFilePath);
        }
      } else {
        final file = File(_activeFilePath);
        final parent = file.parent;
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        await file.writeAsString(json.encode({
          'version': 2,
          'strokesOnly': true,
          'totalPages': _totalPages,
          'pages': pageData.map((k, v) => MapEntry(k.toString(), v)),
        }));
      }

      debugPrint('[BoardestPenView] Auto-saved whiteboard to $_activeFilePath');
    } catch (e) {
      debugPrint('Error auto-saving whiteboard: $e');
    }
  }

  Future<void> _loadPersistentSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorVal = prefs.getInt('whiteboard_bg_color');
      final pattern = prefs.getString('whiteboard_bg_pattern');
      final eraseWhole = prefs.getBool('whiteboard_erase_entire');
      final eraserSizeVal = prefs.getDouble('whiteboard_eraser_size');
      if (mounted) {
        setState(() {
          if (colorVal != null) {
            _boardBgColor = Color(colorVal);
          }
          if (pattern != null) {
            _bgPattern = pattern;
          }
          if (eraseWhole != null) {
            _eraseEntireStroke = eraseWhole;
          }
          if (eraserSizeVal != null) {
            _eraserSize = eraserSizeVal;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading persistent whiteboard settings: $e');
    }
  }

  Future<void> _savePersistentSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('whiteboard_bg_color', _boardBgColor.value);
      await prefs.setString('whiteboard_bg_pattern', _bgPattern);
      await prefs.setBool('whiteboard_erase_entire', _eraseEntireStroke);
      await prefs.setDouble('whiteboard_eraser_size', _eraserSize);
    } catch (e) {
      debugPrint('Error saving persistent whiteboard settings: $e');
    }
  }

  @override
  void dispose() {
    for (final t in _activeTimers.values) t.cancel();
    unawaited(_autoSaveBoard());
    super.dispose();
  }

  void _initPage(int p) {
    _pageStrokes.putIfAbsent(p, () => []);
    _undoHistory.putIfAbsent(p, () => []);
    _redoStack.putIfAbsent(p, () => []);
    _pageElements.putIfAbsent(p, () => []);
  }

  void _addPage() {
    setState(() {
      _totalPages++;
      _initPage(_totalPages);
      _currentPage = _totalPages;
    });
  }

  void _goTo(int p) {
    if (p >= 1 && p <= _totalPages) {
      setState(() {
        _selectedStrokeIndices.clear();
        _currentPage = p;
      });
    } else if (p > _totalPages) {
      // Smart Auto-generate next page when hitting end arrow!
      _addPage();
    }
  }

  List<DrawingStroke> get _strokes {
    _initPage(_currentPage);
    return _pageStrokes[_currentPage]!;
  }
  List<BoardElement> get _elements {
    _initPage(_currentPage);
    return _pageElements[_currentPage]!;
  }

  void _saveSnapshot() {
    _initPage(_currentPage);
    _undoHistory[_currentPage]!.add(List<DrawingStroke>.from(_strokes));
    if (_undoHistory[_currentPage]!.length > 60) {
      _undoHistory[_currentPage]!.removeAt(0);
    }
    _redoStack[_currentPage]!.clear();
  }

  void _undo() {
    _initPage(_currentPage);
    final hist = _undoHistory[_currentPage]!;
    if (hist.isEmpty) return;
    _redoStack[_currentPage]!.add(List<DrawingStroke>.from(_strokes));
    setState(() {
      _selectedStrokeIndices.clear();
      _pageStrokes[_currentPage] = hist.removeLast();
    });
    _autoSaveBoard();
  }

  void _redo() {
    _initPage(_currentPage);
    final stack = _redoStack[_currentPage]!;
    if (stack.isEmpty) return;
    _undoHistory[_currentPage]!.add(List<DrawingStroke>.from(_strokes));
    setState(() {
      _selectedStrokeIndices.clear();
      _pageStrokes[_currentPage] = stack.removeLast();
    });
    _autoSaveBoard();
  }

  void _clearPage() {
    _saveSnapshot();
    setState(() {
      _selectedStrokeIndices.clear();
      _pageStrokes[_currentPage] = [];
      _pageElements[_currentPage] = [];
    });
    _autoSaveBoard();
  }

  // ═══════════════════════════════════════════════════════
  // LASSO MATH ALGORITHM (RAY-CASTING POINT-IN-POLYGON)
  // ═══════════════════════════════════════════════════════

  bool _isPointInPolygon(Offset point, List<Offset> polygon) {
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

  void _checkLassoSelection() {
    if (_lassoPolygon.length < 3) return;
    _lastLassoPolygon = List.from(_lassoPolygon);
    final selected = <int>[];
    for (int i = 0; i < _strokes.length; i++) {
      final stroke = _strokes[i];
      bool hasPointInside = stroke.points.any((p) => _isPointInPolygon(p, _lassoPolygon));
      if (hasPointInside) {
        selected.add(i);
      }
    }
    setState(() {
      _selectedStrokeIndices = selected;
    });
  }

  // ═══════════════════════════════════════════════════════
  // DRAWING & PANNING EVENTS
  // ═══════════════════════════════════════════════════════

  Offset _local(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    final localRaw = box?.globalToLocal(global) ?? global;
    return localRaw - _canvasOffset;
  }

  void _onPanStart(DragStartDetails d) {
    // Palm Rejection: 스타일러스 사용 중 손바닥 터치 오작동 방지
    if (_palmRejectionEnabled && _hasSeenStylus && _lastPointerKind == PointerDeviceKind.touch) {
      return;
    }

    final p = _local(d.globalPosition);

    if (_tool == ToolMode.pan) {
      _panStart = d.globalPosition;
      return;
    }

    if (_tool == ToolMode.eraser) {
      _saveSnapshot();
      _eraseAt(p);
      return;
    }

    if (_tool == ToolMode.select) {
      if (_selectedStrokeIndices.isNotEmpty) {
        _dragSelectedStart = p;
        return;
      }
      _saveSnapshot();
      setState(() {
        _isLassoActive = true;
        _lassoPolygon = [p];
        _selectedStrokeIndices.clear();
      });
      return;
    }

    if (_tool == ToolMode.pointer) return;

    _saveSnapshot();
    setState(() {
      _isDrawing = true;
      _activePoints = [p];
      if (_tool == ToolMode.shape) _shapeStart = p;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_tool == ToolMode.pan && _panStart != null) {
      final delta = d.globalPosition - _panStart!;
      setState(() {
        _canvasOffset += delta;
        _panStart = d.globalPosition;
      });
      return;
    }

    final p = _local(d.globalPosition);

    if (_tool == ToolMode.eraser) {
      _eraseAt(p);
      return;
    }

    if (_tool == ToolMode.select) {
      if (_dragSelectedStart != null) {
        final delta = p - _dragSelectedStart!;
        setState(() {
          for (final index in _selectedStrokeIndices) {
            if (_selectEntireStroke) {
              _strokes[index] = _strokes[index].translate(delta);
            } else {
              final updatedPoints = _strokes[index].points.map((pt) {
                if (_isPointInPolygon(pt, _lastLassoPolygon)) {
                  return pt + delta;
                }
                return pt;
              }).toList();
              _strokes[index] = DrawingStroke(
                points: updatedPoints,
                color: _strokes[index].color,
                strokeWidth: _strokes[index].strokeWidth,
                type: _strokes[index].type,
              );
            }
          }
          _dragSelectedStart = p;
        });
        return;
      }
      if (_isLassoActive) {
        setState(() {
          _lassoPolygon.add(p);
        });
      }
      return;
    }

    if (!_isDrawing) return;

    setState(() {
      if (_tool == ToolMode.shape && _shapeStart != null) {
        _activePoints = _genShape(_activeShape, _shapeStart!, p);
      } else {
        _activePoints.add(p);
      }
    });
  }

  void _onPanEnd(DragEndDetails _) {
    _panStart = null;
    _dragSelectedStart = null;

    if (_tool == ToolMode.select) {
      if (_isLassoActive) {
        _checkLassoSelection();
        setState(() {
          _isLassoActive = false;
          _lassoPolygon.clear();
        });
      }
      _autoSaveBoard();
      return;
    }

    if (_tool == ToolMode.eraser) {
      _autoSaveBoard();
      return;
    }

    if (!_isDrawing || _activePoints.isEmpty) return;

    final stroke = DrawingStroke(
      points: List.from(_activePoints),
      color: _penColor,
      strokeWidth: _strokeWidth,
      type: _strokeType,
    );
    setState(() => _strokes.add(stroke));
    setState(() {
      _isDrawing = false;
      _activePoints = [];
      _shapeStart = null;
    });
    _autoSaveBoard();
  }

  /// 선분 위 최단 거리 — 획 지우개가 얇은 선 사이를 지나갈 때도 감지
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
      if (_distancePointToSegment(center, points[i - 1], points[i]) < radius) {
        return true;
      }
    }
    return false;
  }

  /// 부분 지우개: 샘플 포인트 사이를 촘촘히 보간해 원형 지우개에 닿은 구간만 분할
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

  void _eraseAt(Offset p) {
    final radius = _eraserSize;
    final newStrokes = <DrawingStroke>[];
    bool changed = false;

    for (final stroke in _strokes) {
      if (stroke.type == StrokeType.eraser) continue;

      if (_eraseEntireStroke) {
        if (_strokeTouchedByEraser(stroke.points, p, radius)) {
          changed = true;
        } else {
          newStrokes.add(stroke);
        }
      } else {
        final sampleStep = min(4.0, radius / 3);
        final dense = stroke.points.length >= 2
            ? _densifyPolyline(stroke.points, sampleStep)
            : stroke.points;
        final parts = _splitPolylineByEraser(dense, p, radius);

        if (parts.isEmpty) {
          changed = true;
        } else if (parts.length == 1 &&
            parts.first.length == dense.length &&
            dense.length == stroke.points.length) {
          newStrokes.add(stroke);
        } else {
          changed = true;
          for (final seg in parts) {
            newStrokes.add(DrawingStroke(
              points: seg,
              color: stroke.color,
              strokeWidth: stroke.strokeWidth,
              type: stroke.type,
            ));
          }
        }
      }
    }

    if (changed) {
      setState(() {
        _pageStrokes[_currentPage] = newStrokes;
      });
    }
  }

  void _persistEraserPrefs() {
    unawaited(_savePersistentSettings());
  }

  List<Offset> _genShape(ShapeType shape, Offset start, Offset end) {
    switch (shape) {
      case ShapeType.line:
        return [start, end];
      case ShapeType.arrow:
        final dir = end - start;
        if (dir.distance == 0) return [start, end];
        final u = dir / dir.distance;
        final v = Offset(-u.dy, u.dx);
        final arrowLength = 15.0;
        final h1 = end - u * arrowLength + v * (arrowLength * 0.5);
        final h2 = end - u * arrowLength - v * (arrowLength * 0.5);
        return [start, end, h1, end, h2];
      case ShapeType.triangle:
        final top = Offset((start.dx + end.dx) / 2, start.dy);
        final bottomLeft = Offset(start.dx, end.dy);
        final bottomRight = end;
        return [top, bottomLeft, bottomRight, top];
      case ShapeType.rectangle:
        return [
          start,
          Offset(end.dx, start.dy),
          end,
          Offset(start.dx, end.dy),
          start,
        ];
      case ShapeType.circle:
        final r = (end - start).distance;
        final pts = <Offset>[];
        for (double i = 0; i <= 360; i += 10) {
          final rad = i * pi / 180;
          pts.add(start + Offset(r * cos(rad), r * sin(rad)));
        }
        return pts;
      case ShapeType.cube:
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final offset = Offset(dx * 0.3, -dy * 0.3);
        final p0 = start;
        final p1 = Offset(start.dx + dx * 0.7, start.dy);
        final p2 = Offset(start.dx + dx * 0.7, start.dy + dy * 0.7);
        final p3 = Offset(start.dx, start.dy + dy * 0.7);
        final q0 = p0 + offset;
        final q1 = p1 + offset;
        final q2 = p2 + offset;
        final q3 = p3 + offset;
        return [
          p0, p1, p2, p3, p0,
          q0, q1, q2, q3, q0,
          q1, p1, p2, q2, q3, p3, p0, q0
        ];
      case ShapeType.cylinder:
        final w = (end.dx - start.dx).abs();
        final h = (end.dy - start.dy).abs();
        final rx = w / 2;
        final ry = h * 0.15;
        final cx = (start.dx + end.dx) / 2;
        final topCenter = Offset(cx, start.dy + ry);
        final bottomCenter = Offset(cx, end.dy - ry);
        final pts = <Offset>[];
        for (double i = 0; i <= 360; i += 10) {
          final rad = i * pi / 180;
          pts.add(topCenter + Offset(rx * cos(rad), ry * sin(rad)));
        }
        pts.add(bottomCenter + Offset(rx, 0));
        for (double i = 0; i <= 360; i += 10) {
          final rad = i * pi / 180;
          pts.add(bottomCenter + Offset(rx * cos(rad), ry * sin(rad)));
        }
        pts.add(topCenter + Offset(-rx, 0));
        return pts;
      default:
        return [start, end];
    }
  }

  // ═══════════════════════════════════════════════════════
  // BUILD CANVAS & DESIGN SYSTEM
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;

    return Scaffold(
      backgroundColor: _boardBgColor,
      body: Stack(
        children: [
          // 1. Drawing Canvas
          Positioned.fill(
            child: Listener(
              onPointerDown: (event) {
                _lastPointerKind = event.kind;
                if (event.kind == PointerDeviceKind.stylus || event.kind == PointerDeviceKind.invertedStylus) {
                  _hasSeenStylus = true;
                }
                if (event.kind == PointerDeviceKind.invertedStylus) {
                  if (_tool != ToolMode.eraser) {
                    setState(() {
                      _tool = ToolMode.eraser;
                    });
                  }
                }
              },
              child: GestureDetector(
                key: _canvasKey,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: ClipRect(
                  child: CustomPaint(
                    painter: _InfiniteBoardPainter(
                      strokes: _strokes,
                      activePoints: _activePoints,
                      canvasOffset: _canvasOffset,
                      bgPattern: _bgPattern,
                      boardBgColor: _boardBgColor,
                      lassoPoints: _isLassoActive ? _lassoPolygon : null,
                      selectedIndices: _selectedStrokeIndices,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 2. HSL Pen Details Card
          if (_isPenDetailsOpen)
            Positioned(
              bottom: 84 * scale,
              left: MediaQuery.of(context).size.width / 2 - 120 * scale,
              child: _buildPenDetailsCard(scale),
            ),

          // 2.7 HSL Shape Details Card
          if (_isShapeDetailsOpen && _tool == ToolMode.shape)
            Positioned(
              bottom: 84 * scale,
              left: MediaQuery.of(context).size.width / 2 - 160 * scale,
              child: _buildShapeDetailsCard(scale),
            ),

          // 3. Eraser bubble reset menu (GOODNOTES BUBBLE STYLE)
          if (_tool == ToolMode.eraser)
            Positioned(
              bottom: 84 * scale,
              left: MediaQuery.of(context).size.width / 2 - 60 * scale,
              child: _buildEraserBubbleMenu(scale),
            ),

          // 3.1. Selection Mode Bubble Menu
          if (_tool == ToolMode.select)
            Positioned(
              bottom: 84 * scale,
              left: MediaQuery.of(context).size.width / 2 - 80 * scale,
              child: _buildSelectionBubbleMenu(scale),
            ),

          // 4. File Sidebar Menu
          if (_isMenuOpen)
            Positioned(
              bottom: 84 * scale,
              left: 20 * scale,
              child: _buildFileSidebarMenu(scale),
            ),

          // 5. Sleek GoodNotes Bottom Floating Toolbar
          Positioned(
            bottom: 20 * scale,
            left: 20 * scale,
            right: 20 * scale,
            child: Center(
              child: _buildGoodNotesFloatingToolbar(scale),
            ),
          ),

          // Top Header back button
          Positioned(
            top: 20 * scale,
            left: 20 * scale,
            child: FloatingActionButton.small(
              backgroundColor: const Color(0xFF13171F),
              foregroundColor: Colors.white,
              child: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // PREMIUM COMPONENT BUILDERS (UI/UX COPIES)
  // ═══════════════════════════════════════════════════════

  Widget _buildGoodNotesFloatingToolbar(double scale) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF13171F).withOpacity(0.94),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 16, spreadRadius: 2),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // File menu pop-up (삼선 아이콘)
          IconButton(
            tooltip: '파일 메뉴',
            icon: const Icon(Icons.menu_rounded, color: Colors.tealAccent),
            onPressed: () => setState(() {
              _isMenuOpen = !_isMenuOpen;
              _isPenDetailsOpen = false;
            }),
          ),

          // Page indicators

          // Page indicators
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70),
            onPressed: _currentPage > 1 ? () => _goTo(_currentPage - 1) : null,
          ),
          Text(
            '${_currentPage.toString().padLeft(2, '0')} / ${_totalPages.toString().padLeft(2, '0')}',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 13 * scale,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            onPressed: () => _goTo(_currentPage + 1), // Triggers auto-add if past final page!
          ),

          // Add Page Button
          IconButton(
            tooltip: '새 페이지 즉시 추가',
            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.tealAccent),
            onPressed: _addPage,
          ),

          Container(width: 1, height: 24, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 12)),

          // 1. Pen Tool (Double click to open details)
          _buildToolDockBtn(
            Icons.edit_rounded,
            '펜 도구 (더블 클릭 시 색상/굵기 설정)',
            ToolMode.pen,
            () {
              if (_tool == ToolMode.pen) {
                setState(() {
                  _isPenDetailsOpen = !_isPenDetailsOpen;
                  _isMenuOpen = false;
                });
              } else {
                setState(() {
                  _tool = ToolMode.pen;
                  _isPenDetailsOpen = false;
                  _isShapeDetailsOpen = false;
                  _selectedStrokeIndices.clear(); // Clear lasso selection on switch!
                });
              }
            },
            scale,
          ),

          // 2. Eraser
          _buildToolDockBtn(
            Icons.auto_fix_high_rounded,
            '지우개 도구 (클릭 시 상단 초기화 단추 팝업)',
            ToolMode.eraser,
            () => setState(() {
              _tool = ToolMode.eraser;
              _isPenDetailsOpen = false;
              _isShapeDetailsOpen = false;
              _selectedStrokeIndices.clear(); // Clear lasso selection on switch!
            }),
            scale,
          ),

          // 3. Lasso Tool (올가미)
          _buildToolDockBtn(
            Icons.select_all_rounded,
            '올가미 선택 도구 (선택 후 끌어서 필기 이동)',
            ToolMode.select,
            () => setState(() {
              _tool = ToolMode.select;
              _isPenDetailsOpen = false;
              _isShapeDetailsOpen = false;
            }),
            scale,
          ),

          // 3.5 Shape Tool (도형)
          _buildToolDockBtn(
            Icons.crop_square_rounded,
            '도형 삽입 도구 (클릭 시 세부 선택 팝업)',
            ToolMode.shape,
            () {
              if (_tool == ToolMode.shape) {
                setState(() {
                  _isShapeDetailsOpen = !_isShapeDetailsOpen;
                  _isPenDetailsOpen = false;
                });
              } else {
                setState(() {
                  _tool = ToolMode.shape;
                  _isShapeDetailsOpen = true;
                  _isPenDetailsOpen = false;
                  _selectedStrokeIndices.clear();
                });
              }
            },
            scale,
          ),

          // 4. Pan / Scroll Tool (손바닥)
          _buildToolDockBtn(
            Icons.pan_tool_rounded,
            '보드판 이동 도구 (칠판 화면 이동)',
            ToolMode.pan,
            () => setState(() {
              _tool = ToolMode.pan;
              _isPenDetailsOpen = false;
              _isShapeDetailsOpen = false;
              _selectedStrokeIndices.clear(); // Clear lasso selection on switch!
            }),
            scale,
          ),

          Container(width: 1, height: 24, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 12)),

          // Undo, Redo
          IconButton(icon: const Icon(Icons.undo_rounded, color: Colors.white70), onPressed: _undo),
          IconButton(icon: const Icon(Icons.redo_rounded, color: Colors.white70), onPressed: _redo),
        ],
      ),
    );
  }

  Widget _buildToolDockBtn(IconData icon, String tooltip, ToolMode mode, VoidCallback onTap, double scale) {
    final active = _tool == mode;
    final activeColor = const Color(0xFF00F5D4);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: active ? activeColor.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? activeColor : Colors.transparent),
          ),
          child: Icon(icon, color: active ? activeColor : Colors.white70, size: 18 * scale),
        ),
      ),
    );
  }

  // GOODNOTES STYLED ERASER BUBBLE MENU
  Widget _buildEraserBubbleMenu(double scale) {
    return Card(
      color: const Color(0xFF13171F).withOpacity(0.96),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.16)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_fix_high_rounded, color: Colors.tealAccent, size: 16),
            const SizedBox(width: 8),
            Text(
              '지우개 종류:',
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 10 * scale, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 6),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: !_eraseEntireStroke ? const Color(0xFF00F5D4).withOpacity(0.2) : Colors.transparent,
                foregroundColor: !_eraseEntireStroke ? const Color(0xFF00F5D4) : Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('부분 지우개', style: GoogleFonts.notoSansKr(fontSize: 10 * scale, fontWeight: FontWeight.bold)),
              onPressed: () {
                setState(() => _eraseEntireStroke = false);
                _persistEraserPrefs();
              },
            ),
            const SizedBox(width: 6),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: _eraseEntireStroke ? const Color(0xFF00F5D4).withOpacity(0.2) : Colors.transparent,
                foregroundColor: _eraseEntireStroke ? const Color(0xFF00F5D4) : Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('획 지우개', style: GoogleFonts.notoSansKr(fontSize: 10 * scale, fontWeight: FontWeight.bold)),
              onPressed: () {
                setState(() => _eraseEntireStroke = true);
                _persistEraserPrefs();
              },
            ),
            const SizedBox(width: 12),
            Container(width: 1, height: 16, color: Colors.white24),
            const SizedBox(width: 12),
            Text(
              '지우개 크기:',
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 10 * scale, fontWeight: FontWeight.bold),
            ),
            SizedBox(
              width: 100 * scale,
              child: Slider(
                value: _eraserSize,
                min: 5.0,
                max: 100.0,
                activeColor: const Color(0xFF00F5D4),
                onChanged: (val) {
                  setState(() => _eraserSize = val);
                  _persistEraserPrefs();
                },
              ),
            ),
            Text('${_eraserSize.toStringAsFixed(0)}px', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 10)),
            const SizedBox(width: 12),
            Container(width: 1, height: 16, color: Colors.white24),
            const SizedBox(width: 12),
            // >> 초기화 Button!
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFEF4565).withOpacity(0.15),
                foregroundColor: const Color(0xFFEF4565),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 12),
              label: Text(
                '초기화',
                style: GoogleFonts.notoSansKr(fontSize: 10 * scale, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                _clearPage();
                setState(() {
                  _tool = ToolMode.pen; // Auto switch back to pen
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBubbleMenu(double scale) {
    return Card(
      color: const Color(0xFF13171F).withOpacity(0.96),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.16)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.select_all_rounded, color: Colors.tealAccent, size: 14),
            const SizedBox(width: 8),
            Text(
              '선택 방식:',
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 10 * scale, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: _selectEntireStroke ? const Color(0xFF00F5D4).withOpacity(0.2) : Colors.transparent,
                foregroundColor: _selectEntireStroke ? const Color(0xFF00F5D4) : Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('획 선택', style: GoogleFonts.notoSansKr(fontSize: 10 * scale, fontWeight: FontWeight.bold)),
              onPressed: () => setState(() => _selectEntireStroke = true),
            ),
            const SizedBox(width: 6),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: !_selectEntireStroke ? const Color(0xFF00F5D4).withOpacity(0.2) : Colors.transparent,
                foregroundColor: !_selectEntireStroke ? const Color(0xFF00F5D4) : Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('부분 선택', style: GoogleFonts.notoSansKr(fontSize: 10 * scale, fontWeight: FontWeight.bold)),
              onPressed: () => setState(() => _selectEntireStroke = false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShapeDetailsCard(double scale) {
    return Card(
      color: const Color(0xFF13171F).withOpacity(0.96),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.16)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🔷 삽입할 도형 선택',
              style: GoogleFonts.notoSansKr(
                color: Colors.white70,
                fontSize: 11 * scale,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildShapeSelectorBtn('📏 직선', ShapeType.line, scale),
                _buildShapeSelectorBtn('↗️ 화살표', ShapeType.arrow, scale),
                _buildShapeSelectorBtn('🔺 삼각형', ShapeType.triangle, scale),
                _buildShapeSelectorBtn('🟩 사각형', ShapeType.rectangle, scale),
                _buildShapeSelectorBtn('🟡 원', ShapeType.circle, scale),
                _buildShapeSelectorBtn('📦 큐브', ShapeType.cube, scale),
                _buildShapeSelectorBtn('🛢️ 원기둥', ShapeType.cylinder, scale),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShapeSelectorBtn(String label, ShapeType type, double scale) {
    final active = _activeShape == type;
    final activeColor = const Color(0xFF00F5D4);
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeShape = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.18) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? activeColor : Colors.white.withOpacity(0.1)),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            color: active ? activeColor : Colors.white70,
            fontSize: 11 * scale,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildPenDetailsCard(double scale) {
    final colors = [
      Colors.white,
      Colors.black,
      const Color(0xFFEF4565), // Red
      const Color(0xFFFFD60A), // Yellow
      const Color(0xFF00F5D4), // Teal
      const Color(0xFF3DA9FC), // Sky
      const Color(0xFF2CB67D), // Green
      Colors.orange,
      Colors.purple,
    ];

    return Card(
      color: const Color(0xFF13171F).withOpacity(0.96),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.12)),
      ),
      child: Container(
        width: 260 * scale,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('펜 굵기 & 타입 설정', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 11 * scale, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: colors.map((c) {
                final active = _penColor.value == c.value;
                return GestureDetector(
                  onTap: () => setState(() => _penColor = c),
                  child: Container(
                    width: 24 * scale,
                    height: 24 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c,
                      border: Border.all(color: active ? Colors.white : Colors.white24, width: active ? 2 : 1),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.line_weight_rounded, color: Colors.white60, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    min: 1.0,
                    max: 20.0,
                    value: _strokeWidth,
                    activeColor: const Color(0xFF00F5D4),
                    onChanged: (v) => setState(() => _strokeWidth = v),
                  ),
                ),
                Text('${_strokeWidth.toStringAsFixed(0)}px', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSidebarMenu(double scale) {
    return Card(
      color: const Color(0xFF13171F),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.12)),
      ),
      child: Container(
        width: 220 * scale,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMenuItem(Icons.add_box_rounded, '새 칠판 캔버스 생성', () async {
              setState(() {
                _currentPage = 1;
                _totalPages = 1;
                _strokes.clear();
                _pageStrokes.clear();
                _initPage(1);
                _isMenuOpen = false;
              });
              if (widget.teacher != null && widget.subject != null) {
                final dir = await BstSaveService.instance.directoryFor(BstSaveService.subBoard);
                final stamp = DateTime.now().millisecondsSinceEpoch;
                final base = BoardStorageService.instance.boardFileBaseName(
                  widget.teacher!,
                  widget.subject!,
                );
                _activeFilePath = p.join(dir.path, '${base}_$stamp.iwb');
                await _saveBoardMapping(_activeFilePath);
              }
              await _autoSaveBoard();
            }),
             // IWB 가져오기
            _buildMenuItem(Icons.file_open_rounded, 'IWB 파일 가져오기', () async {
              setState(() => _isMenuOpen = false);
              final result = await fp.FilePicker.pickFiles(
                dialogTitle: 'IWB 파일 가져오기',
                type: fp.FileType.custom,
                allowedExtensions: ['iwb'],
              );
              if (result != null && result.files.single.path != null) {
                final path = result.files.single.path!;
                await _loadIwb(path);
                setState(() {
                  _activeFilePath = path;
                });
                await _saveBoardMapping(path);
                await _autoSaveBoard();
              }
            }),
            // IWB 내보내기
            _buildMenuItem(Icons.save_rounded, 'IWB 파일로 저장/내보내기', () {
              _saveBoard();
              setState(() => _isMenuOpen = false);
            }),
            _buildMenuItem(Icons.picture_as_pdf_rounded, 'PDF 파일로 내보내기', () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('판서 칠판이 PDF 문서로 성공적으로 익스포트되었습니다! 📄')),
              );
              setState(() => _isMenuOpen = false);
            }),
            _buildMenuItem(Icons.dashboard_customize_rounded, '배경화면 & 격자 설정', () {
              setState(() => _isMenuOpen = false);
              _showBackgroundOptionModal(context, widget.scaleFactor);
            }),
            const Divider(color: Colors.white10),
            _buildMenuItem(Icons.power_settings_new_rounded, '종료', () {
              Navigator.of(context).pop();
            }),
          ],

        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Colors.tealAccent, size: 16),
      title: Text(title, style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 11)),
      onTap: onTap,
    );
  }

  // Dedicated Background Template Options modal
  void _showBackgroundOptionModal(BuildContext context, double scale) {
    showModalBottomSheet(
      backgroundColor: const Color(0xFF13171F),
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '배경화면 & 격자 템플릿 설정',
                style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15 * scale),
              ),
              const SizedBox(height: 16),
              // Diverse Background presets HSL
              SizedBox(
                height: 140 * scale,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildBgColorSelectBtn('클래식 다크', const Color(0xFF0F0E17), scale),
                      _buildBgColorSelectBtn('칠판 초록', const Color(0xFF122C1E), scale),
                      _buildBgColorSelectBtn('차콜 그레이', const Color(0xFF1C1A27), scale),
                      _buildBgColorSelectBtn('네이비 블랙', const Color(0xFF0B132B), scale),
                      _buildBgColorSelectBtn('딥 포레스트', const Color(0xFF0A2016), scale),
                      _buildBgColorSelectBtn('딥 퍼플', const Color(0xFF1E152A), scale),
                      _buildBgColorSelectBtn('모카 브라운', const Color(0xFF231B19), scale),
                      _buildBgColorSelectBtn('화이트보드', const Color(0xFFFAFAFA), scale),
                      _buildBgColorSelectBtn('웜 샌드 베이지', const Color(0xFFF7F4EB), scale),
                      _buildBgColorSelectBtn('파스텔 민트', const Color(0xFFE0F2F1), scale),
                      _buildBgColorSelectBtn('소프트 스카이', const Color(0xFFE3F2FD), scale),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 10),
              Text(
                '템플릿 격자 설정',
                style: GoogleFonts.notoSansKr(color: Colors.white60, fontSize: 11 * scale),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildPatternSelectBtn('격자 없음', 'none', scale),
                    const SizedBox(width: 8),
                    _buildPatternSelectBtn('모눈종이 (Grid)', 'grid', scale),
                    const SizedBox(width: 8),
                    _buildPatternSelectBtn('가로줄공책 (Line)', 'line', scale),
                    const SizedBox(width: 8),
                    _buildPatternSelectBtn('점 격자 (Dot)', 'dot', scale),
                    const SizedBox(width: 8),
                    _buildPatternSelectBtn('영어 쓰기 (English)', 'english', scale),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBgColorSelectBtn(String name, Color color, double scale) {
    final isSelected = _boardBgColor.value == color.value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _boardBgColor = color;
        });
        _savePersistentSettings();
        _autoSaveBoard();
        Navigator.of(context).pop();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.amberAccent : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          name,
          style: GoogleFonts.notoSansKr(
            color: color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 11 * scale,
          ),
        ),
      ),
    );
  }

  Widget _buildPatternSelectBtn(String name, String pattern, double scale) {
    final isSelected = _bgPattern == pattern;
    return GestureDetector(
      onTap: () {
        setState(() {
          _bgPattern = pattern;
        });
        _savePersistentSettings();
        _autoSaveBoard();
        Navigator.of(context).pop();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00F5D4).withOpacity(0.12) : Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF00F5D4) : Colors.white12,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          name,
          style: GoogleFonts.notoSansKr(
            color: isSelected ? const Color(0xFF00F5D4) : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 11 * scale,
          ),
        ),
      ),
    );
  }

  Future<void> _saveBoard() async {
    try {
      String? outputFile = await fp.FilePicker.saveFile(
        dialogTitle: 'IWB 파일 저장',
        fileName: 'board_backup.iwb',
        type: fp.FileType.custom,
        allowedExtensions: ['iwb'],
      );
      if (outputFile == null) return;

      final Map<String, dynamic> iwbData = {
        'version': 1,
        'totalPages': _totalPages,
        'boardBgColor': _boardBgColor.value,
        'bgPattern': _bgPattern,
        'pages': {},
      };

      for (int p = 1; p <= _totalPages; p++) {
        final strokes = _pageStrokes[p] ?? [];
        final pageData = [];
        for (final stroke in strokes) {
          pageData.add({
            'points': stroke.points.map((pt) => {'dx': pt.dx, 'dy': pt.dy}).toList(),
            'color': stroke.color.value,
            'strokeWidth': stroke.strokeWidth,
            'type': stroke.type.index,
          });
        }
        iwbData['pages'][p.toString()] = pageData;
      }

      final file = File(outputFile);
      await file.writeAsString(json.encode(iwbData));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('판서 칠판이 IWB 포맷으로 성공적으로 백업되었습니다! 💾')),
        );
      }
    } catch (e) {
      debugPrint('Error saving IWB: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('IWB 파일 저장 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════
// INFINITE WHITEBOARD CUSTOM PAINTER
// ═══════════════════════════════════════════════════════

class _InfiniteBoardPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final List<Offset> activePoints;
  final Offset canvasOffset;
  final String bgPattern;
  final Color boardBgColor;
  final List<Offset>? lassoPoints;
  final List<int> selectedIndices;

  _InfiniteBoardPainter({
    required this.strokes,
    required this.activePoints,
    required this.canvasOffset,
    required this.bgPattern,
    required this.boardBgColor,
    this.lassoPoints,
    required this.selectedIndices,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = boardBgColor;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final isLight = boardBgColor.computeLuminance() > 0.5;
    final gridColor = isLight ? Colors.blueGrey.withOpacity(0.24) : Colors.white.withOpacity(0.12);

    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);

    if (bgPattern == 'grid') {
      final p = Paint()
        ..color = gridColor
        ..strokeWidth = 1.0;
      double startX = -canvasOffset.dx - 1000;
      double endX = startX + size.width + 2000;
      double startY = -canvasOffset.dy - 1000;
      double endY = startY + size.height + 2000;

      for (double x = startX - (startX % 40); x < endX; x += 40) {
        canvas.drawLine(Offset(x, startY), Offset(x, endY), p);
      }
      for (double y = startY - (startY % 40); y < endY; y += 40) {
        canvas.drawLine(Offset(startX, y), Offset(endX, y), p);
      }
    } else if (bgPattern == 'line') {
      final p = Paint()
        ..color = gridColor
        ..strokeWidth = 1.0;
      double startY = -canvasOffset.dy - 1000;
      double endY = startY + size.height + 2000;
      double startX = -canvasOffset.dx - 1000;
      double endX = startX + size.width + 2000;

      for (double y = startY - (startY % 30); y < endY; y += 30) {
        canvas.drawLine(Offset(startX, y), Offset(endX, y), p);
      }
    } else if (bgPattern == 'dot') {
      final p = Paint()
        ..color = gridColor.withOpacity(gridColor.opacity * 2.5)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      double startX = -canvasOffset.dx - 1000;
      double endX = startX + size.width + 2000;
      double startY = -canvasOffset.dy - 1000;
      double endY = startY + size.height + 2000;

      for (double x = startX - (startX % 40); x < endX; x += 40) {
        for (double y = startY - (startY % 40); y < endY; y += 40) {
          canvas.drawPoints(ui.PointMode.points, [Offset(x, y)], p);
        }
      }
    } else if (bgPattern == 'english') {
      final pBlue = Paint()
        ..color = gridColor
        ..strokeWidth = 1.0;
      final pRed = Paint()
        ..color = Colors.red.withOpacity(isLight ? 0.15 : 0.08)
        ..strokeWidth = 1.0;
      double startY = -canvasOffset.dy - 1000;
      double endY = startY + size.height + 2000;
      double startX = -canvasOffset.dx - 1000;
      double endX = startX + size.width + 2000;

      for (double y = startY - (startY % 80); y < endY; y += 80) {
        canvas.drawLine(Offset(startX, y), Offset(endX, y), pBlue);
        canvas.drawLine(Offset(startX, y + 10), Offset(endX, y + 10), pBlue);
        canvas.drawLine(Offset(startX, y + 20), Offset(endX, y + 20), pRed);
        canvas.drawLine(Offset(startX, y + 30), Offset(endX, y + 30), pBlue);
      }
    }

    for (int i = 0; i < strokes.length; i++) {
      final s = strokes[i];
      final isSelected = selectedIndices.contains(i);

      final paint = Paint()
        ..color = s.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = isSelected ? s.strokeWidth + 2.0 : s.strokeWidth
        ..style = PaintingStyle.stroke;

      if (isSelected) {
        final glowPaint = Paint()
          ..color = Colors.tealAccent.withOpacity(0.4)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = s.strokeWidth + 6.0
          ..style = PaintingStyle.stroke;
        _drawStrokePath(canvas, s.points, glowPaint);
      }

      _drawStrokePath(canvas, s.points, paint);
    }

    if (activePoints.isNotEmpty) {
      final activePaint = Paint()
        ..color = strokes.isEmpty ? Colors.white : strokes.last.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke;
      _drawStrokePath(canvas, activePoints, activePaint);
    }

    if (lassoPoints != null && lassoPoints!.isNotEmpty) {
      final lassoPaint = Paint()
        ..color = Colors.tealAccent
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final lassoFill = Paint()
        ..color = Colors.tealAccent.withOpacity(0.08)
        ..style = PaintingStyle.fill;

      final path = Path()..moveTo(lassoPoints!.first.dx, lassoPoints!.first.dy);
      for (int i = 1; i < lassoPoints!.length; i++) {
        path.lineTo(lassoPoints![i].dx, lassoPoints![i].dy);
      }
      path.close();

      canvas.drawPath(path, lassoFill);
      canvas.drawPath(path, lassoPaint);
    }

    canvas.restore();
  }

  void _drawStrokePath(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      canvas.drawCircle(points.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _InfiniteBoardPainter oldDelegate) => true;
}

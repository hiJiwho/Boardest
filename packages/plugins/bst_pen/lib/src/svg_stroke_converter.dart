import 'dart:ui';
import 'annotation_canvas.dart';

/// SVG 벡터 획 변환 및 Smooth Bezier 곡선 생성 유틸리티
class SvgStrokeConverter {
  /// 획 목록을 웹 표준 SVG 문자열로 변환 (Smooth Bezier 곡선 + data-num 순서 주입)
  static String strokesToSvg(
    List<AnnotationStroke> strokes, {
    double width = 1920,
    double height = 1080,
  }) {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width.toInt()} ${height.toInt()}" width="$width" height="$height">');

    int order = 1;
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final pathData = _pointsToSmoothBezierPath(stroke.points);
      final colorHex = _colorToHex(stroke.color);
      final opacity = stroke.color.opacity;
      final strokeW = stroke.strokeWidth;
      final isEraser = stroke.isEraser;

      sb.write('  <path d="$pathData" ');
      sb.write('stroke="$colorHex" ');
      if (opacity < 1.0) {
        sb.write('stroke-opacity="${opacity.toStringAsFixed(2)}" ');
      }
      sb.write('stroke-width="${strokeW.toStringAsFixed(1)}" ');
      sb.write('stroke-linecap="round" ');
      sb.write('stroke-linejoin="round" ');
      sb.write('fill="none" ');
      sb.write('data-num="$order" ');
      if (isEraser) {
        sb.write('data-type="eraser" ');
      }
      sb.writeln('/>');
      order++;
    }

    sb.writeln('</svg>');
    return sb.toString();
  }

  /// 좌표(Dot) 리스트를 부드러운 2차 베지어 곡선(Smooth Bezier) SVG Path로 변환
  static String _pointsToSmoothBezierPath(List<Offset> points) {
    if (points.isEmpty) return '';
    if (points.length == 1) {
      final p = points[0];
      return 'M ${p.dx.toStringAsFixed(1)} ${p.dy.toStringAsFixed(1)} L ${(p.dx + 0.1).toStringAsFixed(1)} ${(p.dy + 0.1).toStringAsFixed(1)}';
    }
    if (points.length == 2) {
      final p0 = points[0];
      final p1 = points[1];
      return 'M ${p0.dx.toStringAsFixed(1)} ${p0.dy.toStringAsFixed(1)} L ${p1.dx.toStringAsFixed(1)} ${p1.dy.toStringAsFixed(1)}';
    }

    final sb = StringBuffer();
    sb.write('M ${points[0].dx.toStringAsFixed(1)} ${points[0].dy.toStringAsFixed(1)} ');

    for (int i = 1; i < points.length - 1; i++) {
      final pCurrent = points[i];
      final pNext = points[i + 1];
      final midX = ((pCurrent.dx + pNext.dx) / 2).toStringAsFixed(1);
      final midY = ((pCurrent.dy + pNext.dy) / 2).toStringAsFixed(1);
      final ctrlX = pCurrent.dx.toStringAsFixed(1);
      final ctrlY = pCurrent.dy.toStringAsFixed(1);
      sb.write('Q $ctrlX $ctrlY $midX $midY ');
    }

    final last = points.last;
    sb.write('L ${last.dx.toStringAsFixed(1)} ${last.dy.toStringAsFixed(1)}');
    return sb.toString();
  }

  /// SVG 문자열을 파싱하여 AnnotationStroke 목록으로 복원
  static List<AnnotationStroke> svgToStrokes(String svgString) {
    final List<AnnotationStroke> strokes = [];
    final pathRegex = RegExp(r'<path\s+([^>]+)\/?>', multiLine: true, caseSensitive: false);
    final matches = pathRegex.allMatches(svgString);

    for (final match in matches) {
      final attrStr = match.group(1) ?? '';
      final d = _extractAttr(attrStr, 'd');
      if (d == null || d.isEmpty) continue;

      final strokeColorStr = _extractAttr(attrStr, 'stroke') ?? '#000000';
      final strokeOpacityStr = _extractAttr(attrStr, 'stroke-opacity') ?? '1.0';
      final strokeWidthStr = _extractAttr(attrStr, 'stroke-width') ?? '3.0';
      final dataType = _extractAttr(attrStr, 'data-type');
      final isEraser = dataType == 'eraser';

      final points = _parsePathDToPoints(d);
      if (points.isEmpty) continue;

      final color = _parseColor(strokeColorStr, strokeOpacityStr);
      final strokeWidth = double.tryParse(strokeWidthStr) ?? 3.0;

      strokes.add(AnnotationStroke(
        points: points,
        color: color,
        strokeWidth: strokeWidth,
        isEraser: isEraser,
      ));
    }

    return strokes;
  }

  static String? _extractAttr(String attrStr, String attrName) {
    final reg = RegExp('$attrName="([^"]+)"', caseSensitive: false);
    final m = reg.firstMatch(attrStr);
    return m?.group(1);
  }

  static List<Offset> _parsePathDToPoints(String d) {
    final List<Offset> points = [];
    final tokens = d.trim().split(RegExp(r'\s+'));
    int i = 0;
    while (i < tokens.length) {
      final cmd = tokens[i];
      if (cmd == 'M' || cmd == 'L') {
        if (i + 2 < tokens.length) {
          final x = double.tryParse(tokens[i + 1]);
          final y = double.tryParse(tokens[i + 2]);
          if (x != null && y != null) points.add(Offset(x, y));
          i += 3;
        } else {
          break;
        }
      } else if (cmd == 'Q') {
        if (i + 4 < tokens.length) {
          final endX = double.tryParse(tokens[i + 3]);
          final endY = double.tryParse(tokens[i + 4]);
          if (endX != null && endY != null) points.add(Offset(endX, endY));
          i += 5;
        } else {
          break;
        }
      } else {
        i++;
      }
    }
    return points;
  }

  static String _colorToHex(Color color) {
    return '#${(color.value & 0x00FFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  static Color _parseColor(String hex, String opacityStr) {
    var cleanHex = hex.replaceAll('#', '').trim();
    if (cleanHex.length == 6) {
      cleanHex = 'FF$cleanHex';
    }
    final intVal = int.tryParse(cleanHex, radix: 16) ?? 0xFF000000;
    final op = double.tryParse(opacityStr) ?? 1.0;
    return Color(intVal).withOpacity(op.clamp(0.0, 1.0));
  }
}

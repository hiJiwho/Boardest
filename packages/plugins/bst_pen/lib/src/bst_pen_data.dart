import 'dart:ui';
import 'annotation_canvas.dart';

class BstPenData {
  final int version;
  final bool strokesOnly;
  final int totalPages;
  final Map<int, List<AnnotationStroke>> pages;

  BstPenData({
    this.version = 2,
    this.strokesOnly = true,
    this.totalPages = 1,
    required this.pages,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> jsonPages = {};
    pages.forEach((pageIdx, strokes) {
      jsonPages[pageIdx.toString()] = strokes.map((stroke) => {
        'points': stroke.points.map((pt) => {'dx': pt.dx, 'dy': pt.dy}).toList(),
        'color': stroke.color.value,
        'strokeWidth': stroke.strokeWidth,
        'isEraser': stroke.isEraser,
      }).toList();
    });

    return {
      'version': version,
      'strokesOnly': strokesOnly,
      'totalPages': totalPages,
      'pages': jsonPages,
    };
  }

  factory BstPenData.fromJson(Map<String, dynamic> json) {
    final Map<int, List<AnnotationStroke>> parsedPages = {};
    final pagesData = json['pages'] as Map<String, dynamic>? ?? {};

    pagesData.forEach((pageStr, strokesJsonList) {
      final pageIdx = int.tryParse(pageStr);
      if (pageIdx != null && strokesJsonList is List) {
        parsedPages[pageIdx] = strokesJsonList.map((item) {
          final strokeMap = item as Map<String, dynamic>;
          final rawPts = strokeMap['points'] as List? ?? [];
          final pts = rawPts.map<Offset>((p) {
            if (p is Map) {
              final x = ((p['dx'] ?? p['x'] ?? 0.0) as num).toDouble();
              final y = ((p['dy'] ?? p['y'] ?? 0.0) as num).toDouble();
              return Offset(x, y);
            }
            return Offset.zero;
          }).toList();
          return AnnotationStroke(
            points: pts,
            color: Color(strokeMap['color'] as int? ?? 0xFF000000),
            strokeWidth: (strokeMap['strokeWidth'] as num?)?.toDouble() ?? 3.0,
            isEraser: strokeMap['isEraser'] as bool? ?? false,
          );
        }).toList();
      }
    });

    return BstPenData(
      version: json['version'] as int? ?? 2,
      strokesOnly: json['strokesOnly'] as bool? ?? true,
      totalPages: json['totalPages'] as int? ?? 1,
      pages: parsedPages,
    );
  }
}

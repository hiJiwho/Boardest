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
      jsonPages[pageIdx.toString()] = strokes.map((stroke) => stroke.toJson()).toList();
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
    final rawPages = json['pages'];
    final Map<dynamic, dynamic> pagesData = rawPages is Map ? rawPages : {};

    pagesData.forEach((pageStr, strokesJsonList) {
      final pageIdx = int.tryParse(pageStr.toString());
      if (pageIdx != null && strokesJsonList is List) {
        parsedPages[pageIdx] = strokesJsonList.map((item) {
          if (item is Map<String, dynamic>) {
            return AnnotationStroke.fromJson(item);
          } else if (item is Map) {
            return AnnotationStroke.fromJson(Map<String, dynamic>.from(item));
          }
          return AnnotationStroke(
            points: const [],
            color: const Color(0xFF000000),
            strokeWidth: 3.0,
            isEraser: false,
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BstPenData) return false;
    if (other.version != version ||
        other.strokesOnly != strokesOnly ||
        other.totalPages != totalPages ||
        other.pages.length != pages.length) {
      return false;
    }
    for (final entry in pages.entries) {
      final otherStrokes = other.pages[entry.key];
      if (otherStrokes == null || otherStrokes.length != entry.value.length) {
        return false;
      }
      for (int i = 0; i < entry.value.length; i++) {
        if (entry.value[i] != otherStrokes[i]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        version,
        strokesOnly,
        totalPages,
        Object.hashAll(pages.keys),
      );
}

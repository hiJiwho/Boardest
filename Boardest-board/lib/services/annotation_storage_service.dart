import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../widgets/annotation_canvas.dart';
import 'bst_save_service.dart';

class AnnotationStorageService {
  static final AnnotationStorageService instance = AnnotationStorageService._internal();
  AnnotationStorageService._internal();

  Future<Directory> _getBstSaveSubdirectory(String sub) async {
    return BstSaveService.instance.directoryFor(sub);
  }

  String _sanitizeKey(String key) => BstSaveService.instance.sanitizeFileName(key);

  /// Saves both metadata JSON and strokes IWB for PDF or PPT
  Future<void> saveDocumentAnnotations(
    String type, // 'PDF' or 'PPT'
    String fileName,
    Map<String, dynamic> metadata,
    Map<int, List<AnnotationStroke>> pageAnnotations,
  ) async {
    try {
      final dir = await _getBstSaveSubdirectory(type.toUpperCase());
      final sanitized = _sanitizeKey(fileName);

      // 1. Save metadata JSON
      final jsonFile = File(p.join(dir.path, '$sanitized.json'));
      await jsonFile.writeAsString(json.encode(metadata), flush: true);

      // 2. Save strokes IWB
      final iwbFile = File(p.join(dir.path, '$sanitized.iwb'));
      final Map<String, dynamic> iwbData = {
        'version': 1,
        'totalPages': metadata['totalPages'] ?? 1,
        'pages': {},
      };

      pageAnnotations.forEach((pageIdx, strokes) {
        final pageData = [];
        for (final stroke in strokes) {
          pageData.add({
            'points': stroke.points.map((pt) => {'dx': pt.dx, 'dy': pt.dy}).toList(),
            'color': stroke.color.value,
            'strokeWidth': stroke.strokeWidth,
            'isEraser': stroke.isEraser,
          });
        }
        iwbData['pages'][pageIdx.toString()] = pageData;
      });

      await iwbFile.writeAsString(json.encode(iwbData), flush: true);
      debugPrint('[AnnotationStorageService] Saved $type annotations for $sanitized');
    } catch (e) {
      debugPrint('Error saving $type annotations for $fileName: $e');
    }
  }

  /// Loads strokes from the standard .iwb file
  Future<Map<int, List<AnnotationStroke>>> loadDocumentAnnotations(
    String type, // 'PDF' or 'PPT'
    String fileName,
  ) async {
    try {
      final dir = await _getBstSaveSubdirectory(type.toUpperCase());
      final sanitized = _sanitizeKey(fileName);
      final file = File(p.join(dir.path, '$sanitized.iwb'));

      if (!await file.exists()) {
        return {};
      }

      final iwbStr = await file.readAsString();
      final iwbData = json.decode(iwbStr) as Map<String, dynamic>;
      final pagesData = iwbData['pages'] as Map<String, dynamic>? ?? {};

      final Map<int, List<AnnotationStroke>> result = {};
      pagesData.forEach((pageStr, strokesJsonList) {
        final pageIdx = int.tryParse(pageStr);
        if (pageIdx != null && strokesJsonList is List) {
          final List<AnnotationStroke> strokes = [];
          for (final item in strokesJsonList) {
            final Map<String, dynamic> strokeMap = item as Map<String, dynamic>;
            final pts = (strokeMap['points'] as List)
                .map<Offset>((p) => Offset((p['dx'] as num).toDouble(), (p['dy'] as num).toDouble()))
                .toList();
            strokes.add(AnnotationStroke(
              points: pts,
              color: Color(strokeMap['color'] as int),
              strokeWidth: (strokeMap['strokeWidth'] as num).toDouble(),
              isEraser: strokeMap['isEraser'] as bool? ?? false,
            ));
          }
          result[pageIdx] = strokes;
        }
      });

      return result;
    } catch (e) {
      debugPrint('Error loading $type annotations for $fileName: $e');
      return {};
    }
  }

  /// Saves metadata JSON only (ignores strokes IWB) for PDF or PPT
  Future<void> saveDocumentMetadata(
    String type, // 'PDF' or 'PPT'
    String fileName,
    Map<String, dynamic> metadata,
  ) async {
    try {
      final dir = await _getBstSaveSubdirectory(type.toUpperCase());
      final sanitized = _sanitizeKey(fileName);
      final jsonFile = File(p.join(dir.path, '$sanitized.json'));
      await jsonFile.writeAsString(json.encode(metadata), flush: true);
      debugPrint('[AnnotationStorageService] Saved $type metadata for $sanitized');
    } catch (e) {
      debugPrint('Error saving $type metadata for $fileName: $e');
    }
  }

  /// Loads metadata from the standard .json file
  Future<Map<String, dynamic>?> loadDocumentMetadata(
    String type, // 'PDF' or 'PPT'
    String fileName,
  ) async {
    try {
      final dir = await _getBstSaveSubdirectory(type.toUpperCase());
      final sanitized = _sanitizeKey(fileName);
      final file = File(p.join(dir.path, '$sanitized.json'));

      if (!await file.exists()) {
        return null;
      }

      final jsonStr = await file.readAsString();
      return json.decode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error loading $type metadata for $fileName: $e');
      return null;
    }
  }

  /// Clears annotations (both IWB and JSON) for a specific document
  Future<void> clearDocumentAnnotations(
    String type, // 'PDF' or 'PPT'
    String fileName,
  ) async {
    try {
      final dir = await _getBstSaveSubdirectory(type.toUpperCase());
      final sanitized = _sanitizeKey(fileName);

      final jsonFile = File(p.join(dir.path, '$sanitized.json'));
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }

      final iwbFile = File(p.join(dir.path, '$sanitized.iwb'));
      if (await iwbFile.exists()) {
        await iwbFile.delete();
      }
    } catch (e) {
      debugPrint('Error clearing $type annotations for $fileName: $e');
    }
  }
}

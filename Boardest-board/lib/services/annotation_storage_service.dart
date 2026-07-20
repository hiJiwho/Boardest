import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/annotation_canvas.dart';
import 'bst_save_service.dart';
import 'bst_cloud_service.dart';

class AnnotationStorageService {
  static final AnnotationStorageService instance = AnnotationStorageService._internal();
  AnnotationStorageService._internal();

  Future<Directory> _getBstSaveSubdirectory(String sub) async {
    return BstSaveService.instance.directoryFor(sub);
  }

  String _sanitizeKey(String key) => BstSaveService.instance.sanitizeFileName(key);

  Future<String> _getClassNickname() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('app_settings');
      if (jsonStr != null) {
        final map = jsonDecode(jsonStr);
        return map['classNickname'] as String? ?? '일반';
      }
    } catch (_) {}
    return '일반';
  }

  Future<File> _resolveIwbFile(String type, String fileName, {String? fullFilePath, String? className}) async {
    final classTag = (className != null && className.isNotEmpty && className != '전체 반 공용 (통합)') ? '[$className]' : '';
    if (fullFilePath != null && Platform.isWindows) {
      try {
        final root = p.rootPrefix(fullFilePath);
        final jsonFile = File(p.join(root, 'BoardestUSB.json'));
        if (jsonFile.existsSync()) {
          final content = jsonFile.readAsStringSync();
          final config = jsonDecode(content);
          if (config['type'] == 'Bst') {
            final classNickname = className ?? await _getClassNickname();
            final baseName = p.basename(fullFilePath);
            final dirPath = p.join(root, 'bst', 'JSON');
            final dir = Directory(dirPath);
            if (!dir.existsSync()) {
              dir.createSync(recursive: true);
            }
            return File(p.join(dirPath, '[$classNickname]$baseName.IWB'));
          }
        }
      } catch (e) {
        debugPrint('[AnnotationStorageService] resolve USB path failed: $e');
      }
    }
    final dir = await _getBstSaveSubdirectory(type.toUpperCase());
    final sanitized = _sanitizeKey(fileName);
    return File(p.join(dir.path, '$classTag$sanitized.iwb'));
  }

  Future<File> _resolveJsonFile(String type, String fileName, {String? fullFilePath, String? className}) async {
    final classTag = (className != null && className.isNotEmpty && className != '전체 반 공용 (통합)') ? '[$className]' : '';
    if (fullFilePath != null && Platform.isWindows) {
      try {
        final root = p.rootPrefix(fullFilePath);
        final jsonFile = File(p.join(root, 'BoardestUSB.json'));
        if (jsonFile.existsSync()) {
          final content = jsonFile.readAsStringSync();
          final config = jsonDecode(content);
          if (config['type'] == 'Bst') {
            final classNickname = className ?? await _getClassNickname();
            final baseName = p.basename(fullFilePath);
            final dirPath = p.join(root, 'bst', 'JSON');
            final dir = Directory(dirPath);
            if (!dir.existsSync()) {
              dir.createSync(recursive: true);
            }
            return File(p.join(dirPath, '[$classNickname]$baseName.json'));
          }
        }
      } catch (e) {
        debugPrint('[AnnotationStorageService] resolve USB path failed: $e');
      }
    }
    final dir = await _getBstSaveSubdirectory(type.toUpperCase());
    final sanitized = _sanitizeKey(fileName);
    return File(p.join(dir.path, '$classTag$sanitized.json'));
  }

  /// Saves both metadata JSON and strokes IWB for PDF or PPT
  Future<void> saveDocumentAnnotations(
    String type, // 'PDF' or 'PPT'
    String fileName,
    Map<String, dynamic> metadata,
    Map<int, List<AnnotationStroke>> pageAnnotations, {
    String? fullFilePath,
    String? className,
  }) async {
    try {
      // 1. Save metadata JSON
      final jsonFile = await _resolveJsonFile(type, fileName, fullFilePath: fullFilePath, className: className);
      await jsonFile.writeAsString(json.encode(metadata), flush: true);

      // 2. Save strokes IWB
      final iwbFile = await _resolveIwbFile(type, fileName, fullFilePath: fullFilePath, className: className);
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

      if (className != null && className != '전체 반 공용 (통합)') {
        try {
          final sanitized = _sanitizeKey(fileName);
          final cloudFileName = '[$className]${sanitized}_annotation.iwb';
          BstCloudService.instance.uploadAnnotation(cloudFileName, iwbData);
        } catch (_) {}
      }

      debugPrint('[AnnotationStorageService] Saved $type annotations for $fileName (${className ?? "default"})');
    } catch (e) {
      debugPrint('Error saving $type annotations for $fileName: $e');
    }
  }

  /// Loads strokes from the standard .iwb file
  Future<Map<int, List<AnnotationStroke>>> loadDocumentAnnotations(
    String type, // 'PDF' or 'PPT'
    String fileName, {
    String? fullFilePath,
    String? className,
    File? forcedFile,
  }) async {
    try {
      final file = forcedFile ?? await _resolveIwbFile(type, fileName, fullFilePath: fullFilePath, className: className);

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

      // 전체 반 공용(통합) 판서가 있고, 현재 개별 반 판서를 로드 중이면 공용 판서를 함께 병합!
      if (className != null && className != '전체 반 공용 (통합)') {
        final commonFile = await _resolveIwbFile(type, fileName, fullFilePath: fullFilePath, className: '전체 반 공용 (통합)');
        if (await commonFile.exists()) {
          try {
            final commonIwbStr = await commonFile.readAsString();
            final commonIwbData = json.decode(commonIwbStr) as Map<String, dynamic>;
            final commonPagesData = commonIwbData['pages'] as Map<String, dynamic>? ?? {};
            commonPagesData.forEach((pageStr, strokesJsonList) {
              final pageIdx = int.tryParse(pageStr);
              if (pageIdx != null && strokesJsonList is List) {
                final commonStrokes = strokesJsonList.map((item) {
                  final strokeMap = item as Map<String, dynamic>;
                  final pts = (strokeMap['points'] as List)
                      .map<Offset>((p) => Offset((p['dx'] as num).toDouble(), (p['dy'] as num).toDouble()))
                      .toList();
                  return AnnotationStroke(
                    points: pts,
                    color: Color(strokeMap['color'] as int),
                    strokeWidth: (strokeMap['strokeWidth'] as num).toDouble(),
                    isEraser: strokeMap['isEraser'] as bool? ?? false,
                  );
                }).toList();
                if (!result.containsKey(pageIdx)) {
                  result[pageIdx] = commonStrokes;
                } else {
                  result[pageIdx]!.insertAll(0, commonStrokes);
                }
              }
            });
          } catch (_) {}
        }
      }

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
    Map<String, dynamic> metadata, {
    String? fullFilePath,
  }) async {
    try {
      final jsonFile = await _resolveJsonFile(type, fileName, fullFilePath: fullFilePath);
      await jsonFile.writeAsString(json.encode(metadata), flush: true);
      debugPrint('[AnnotationStorageService] Saved $type metadata for $fileName');
    } catch (e) {
      debugPrint('Error saving $type metadata for $fileName: $e');
    }
  }

  /// Loads metadata from the standard .json file
  Future<Map<String, dynamic>?> loadDocumentMetadata(
    String type, // 'PDF' or 'PPT'
    String fileName, {
    String? fullFilePath,
  }) async {
    try {
      final file = await _resolveJsonFile(type, fileName, fullFilePath: fullFilePath);

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
    String fileName, {
    String? fullFilePath,
  }) async {
    try {
      final jsonFile = await _resolveJsonFile(type, fileName, fullFilePath: fullFilePath);
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }

      final iwbFile = await _resolveIwbFile(type, fileName, fullFilePath: fullFilePath);
      if (await iwbFile.exists()) {
        await iwbFile.delete();
      }
    } catch (e) {
      debugPrint('Error clearing $type annotations for $fileName: $e');
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/annotation_canvas.dart';
import 'bst_save_service.dart';
import 'cloud_drive_service.dart';

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

  Future<File> _resolveIwbFile(String type, String fileName, {String? fullFilePath, String? className, bool useFallback = false}) async {
    final classTag = (className != null && className.isNotEmpty && className != '전체 반 공용 (통합)') ? '[$className]' : '';
    if (fullFilePath != null && !useFallback) {
      if (Platform.isWindows) {
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
        } catch (_) {}
      }
      try {
        final dirPath = p.dirname(fullFilePath);
        final baseName = p.basenameWithoutExtension(fullFilePath);
        return File(p.join(dirPath, '$classTag$baseName.iwb'));
      } catch (_) {}
    }
    final dir = await _getBstSaveSubdirectory(type.toUpperCase());
    final sanitized = _sanitizeKey(fileName);
    return File(p.join(dir.path, '$classTag$sanitized.iwb'));
  }

  Future<File> _resolveJsonFile(String type, String fileName, {String? fullFilePath, String? className, bool useFallback = false}) async {
    final classTag = (className != null && className.isNotEmpty && className != '전체 반 공용 (통합)') ? '[$className]' : '';
    if (fullFilePath != null && !useFallback) {
      if (Platform.isWindows) {
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
        } catch (_) {}
      }
      try {
        final dirPath = p.dirname(fullFilePath);
        final baseName = p.basenameWithoutExtension(fullFilePath);
        return File(p.join(dirPath, '$classTag$baseName.json'));
      } catch (_) {}
    }
    final dir = await _getBstSaveSubdirectory(type.toUpperCase());
    final sanitized = _sanitizeKey(fileName);
    return File(p.join(dir.path, '$classTag$sanitized.json'));
  }

  Map<String, dynamic> _serializePageAnnotations(Map<String, dynamic> metadata, Map<int, List<AnnotationStroke>> pageAnnotations) {
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
    return iwbData;
  }

  /// Saves both metadata JSON and strokes IWB for PDF or PPT
  Future<void> saveDocumentAnnotations(
    String type, // 'PDF' or 'PPT' or 'WEBSITE'
    String fileName,
    Map<String, dynamic> metadata,
    Map<int, List<AnnotationStroke>> pageAnnotations, {
    String? fullFilePath,
    String? className,
  }) async {
    try {
      try {
        // 1. Save metadata JSON next to document
        final jsonFile = await _resolveJsonFile(type, fileName, fullFilePath: fullFilePath, className: className);
        final parent = jsonFile.parent;
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        await jsonFile.writeAsString(json.encode(metadata), flush: true);

        // 2. Save strokes IWB next to document
        final iwbFile = await _resolveIwbFile(type, fileName, fullFilePath: fullFilePath, className: className);
        final iwbData = _serializePageAnnotations(metadata, pageAnnotations);
        await iwbFile.writeAsString(json.encode(iwbData), flush: true);

        if (className == null || className == '전체 반 공용 (통합)') {
          final defaultClasses = ['1학년 1반', '1학년 2반', '2학년 1반', '2학년 2반', '3학년 1반', '3학년 2반'];
          for (final cls in defaultClasses) {
            try {
              final classIwbFile = await _resolveIwbFile(type, fileName, fullFilePath: fullFilePath, className: cls);
              await classIwbFile.writeAsString(json.encode(iwbData), flush: true);
            } catch (_) {}
          }
        }
      } catch (writeErr) {
        // Fallback to appdata if writing next to file failed (e.g. read-only folder)
        if (fullFilePath != null) {
          final jsonFile = await _resolveJsonFile(type, fileName, fullFilePath: fullFilePath, className: className, useFallback: true);
          await jsonFile.writeAsString(json.encode(metadata), flush: true);

          final iwbFile = await _resolveIwbFile(type, fileName, fullFilePath: fullFilePath, className: className, useFallback: true);
          final iwbData = _serializePageAnnotations(metadata, pageAnnotations);
          await iwbFile.writeAsString(json.encode(iwbData), flush: true);
        } else {
          rethrow;
        }
      }
      // If BST-Cloud is logged in, upload .IWB and JSON annotations to BST-pen folder in Drive
      if (CloudDriveService.instance.isLoggedIn) {
        try {
          final penFolderId = await CloudDriveService.instance.getBstPenFolderId();
          final iwbData = _serializePageAnnotations(metadata, pageAnnotations);
          final sanitized = _sanitizeKey(fileName);
          final classTag = (className != null && className.isNotEmpty && className != '전체 반 공용 (통합)') ? '[$className]' : '[공통]';
          final cloudFileName = '$classTag${sanitized}_annotation.iwb';
          unawaited(CloudDriveService.instance.uploadTextFileToDrive(cloudFileName, json.encode(iwbData), folderId: penFolderId));
        } catch (cloudErr) {
          debugPrint('[AnnotationStorageService] BST-pen Cloud sync error: $cloudErr');
        }
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
      File file = forcedFile ?? await _resolveIwbFile(type, fileName, fullFilePath: fullFilePath, className: className);

      if (!await file.exists()) {
        if (fullFilePath != null && forcedFile == null) {
          file = await _resolveIwbFile(type, fileName, fullFilePath: fullFilePath, className: className, useFallback: true);
          if (!await file.exists()) {
            return {};
          }
        } else {
          return {};
        }
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

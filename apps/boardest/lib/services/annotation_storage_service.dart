import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../widgets/annotation_canvas.dart';
import 'bst_save_service.dart';
import 'bst_cloud_service.dart';
import 'app_paths.dart';

/// Boardest Unified .pen 판서 저장소 서비스 (전자칠판 전용)
/// 
/// 📌 3대 핵심 실행 및 저장 환경:
/// 1) Teacher 앱으로 실행 (Cloud/Local 무관):
///    - 화이트보드: [Teacher] {날짜_시간}.pen
///    - 파일 열기: [Teacher] {파일명}.pen
/// 2) 전자칠판의 로컬에 저장할 때 (Cloud 미로그인, 시간표 기준 교사):
///    - 화이트보드: [교사ID] {날짜_시간}.pen
///    - 파일 열기: [교사ID] {파일명}.pen
/// 3) 전자칠판이지만 Cloud 로그인 했을 때 (OTP 페어링 / Cloud):
///    - 화이트보드: [교실ID] {날짜_시간}.pen
///    - 파일 열기: [교실ID] {파일명}.pen
class AnnotationStorageService {
  static final AnnotationStorageService instance = AnnotationStorageService._internal();
  AnnotationStorageService._internal();

  Future<Directory> _getBstSaveSubdirectory(String sub) async {
    return BstSaveService.instance.directoryFor(sub);
  }

  Future<Directory> _getBstPenSubdirectory(String sub) async {
    final dir = Directory(p.join(AppPaths.bstPenRootSync, sub));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _sanitizeKey(String key) => BstSaveService.instance.sanitizeFileName(key);

  // ─── 클래스 코드 변환 [교실ID] ──────────────────────────────────────────
  /// "1학년 1반" → "[101]", "2학년 3반" → "[203]", 특별실 그대로 → "[과학실]"
  static String classToCode(String? className) {
    if (className == null || className.trim().isEmpty || className == '전체 반 공용 (통합)' || className == '교사용' || className == 'Teacher') {
      return '[Teacher]';
    }
    final trimmed = className.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      return trimmed;
    }
    // 한글 학년/반 패턴 파싱
    final match = RegExp(r'(\d+)학년\s*(\d+)반').firstMatch(trimmed);
    if (match != null) {
      final grade = match.group(1)!;
      final classNum = match.group(2)!.padLeft(2, '0');
      return '[$grade$classNum]';
    }
    return '[$trimmed]';
  }

  /// 표준 .pen 파일명 생성 규칙 (3가지 경우의 수 100% 적용)
  static String formatPenName({
    required String type, // 'WHITEBOARD', 'PDF', 'PPT', 'HWP', 'WEB', 'TBP', 'CANVA'
    String? fileName,
    bool isTeacherApp = false,
    bool isCloud = false,
    String? teacherId,
    String? classroomId,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final dtStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final isWhiteboard = type.toUpperCase() == 'WHITEBOARD' || fileName == null || fileName.isEmpty || fileName.toLowerCase().startsWith('whiteboard') || fileName.toLowerCase().startsWith('quick_board');

    // 1) Teacher 앱으로 실행 (Cloud/Local 무관)
    if (isTeacherApp) {
      if (isWhiteboard) {
        return '[Teacher] $dtStr.pen';
      }
      String cleanName = fileName.trim();
      if (cleanName.endsWith('.pen')) cleanName = cleanName.substring(0, cleanName.length - 4);
      if (cleanName.endsWith('.bstpen')) cleanName = cleanName.substring(0, cleanName.length - 7);
      return '[Teacher] $cleanName.pen';
    }

    // 2) 전자칠판이지만 Cloud(OTP) 로그인 했을 때 -> [교실ID]
    if (isCloud) {
      final classPrefix = (classroomId != null && classroomId.trim().isNotEmpty) ? classToCode(classroomId) : '[101]';
      if (isWhiteboard) {
        return '$classPrefix $dtStr.pen';
      }
      String cleanName = fileName.trim();
      if (cleanName.endsWith('.pen')) cleanName = cleanName.substring(0, cleanName.length - 4);
      if (cleanName.endsWith('.bstpen')) cleanName = cleanName.substring(0, cleanName.length - 7);
      return '$classPrefix $cleanName.pen';
    }

    // 3) 전자칠판의 로컬에 저장할 때 -> [교사ID] (시간표 기준)
    String teacherPrefix = '[Teacher]';
    if (teacherId != null && teacherId.trim().isNotEmpty) {
      final t = teacherId.trim();
      teacherPrefix = t.startsWith('[') && t.endsWith(']') ? t : '[$t]';
    }
    if (isWhiteboard) {
      return '$teacherPrefix $dtStr.pen';
    }
    String cleanName = fileName.trim();
    if (cleanName.endsWith('.pen')) cleanName = cleanName.substring(0, cleanName.length - 4);
    if (cleanName.endsWith('.bstpen')) cleanName = cleanName.substring(0, cleanName.length - 7);
    return '$teacherPrefix $cleanName.pen';
  }

  // ─── 파일 경로 해결 (.pen 우선) ──────────────────────────────

  Future<File> _resolvePenFile(
    String type,
    String fileName, {
    String? fullFilePath,
    String? classroomId,
    String? teacherId,
    bool isTeacherApp = false,
    bool isCloud = false,
  }) async {
    final penFileName = formatPenName(
      type: type,
      fileName: fileName,
      isTeacherApp: isTeacherApp,
      isCloud: isCloud,
      teacherId: teacherId,
      classroomId: classroomId,
    );

    if (fullFilePath != null && !kIsWeb && Platform.isWindows) {
      try {
        final root = p.rootPrefix(fullFilePath);
        final usbFlag = File(p.join(root, 'BoardestUSB.json'));
        if (usbFlag.existsSync()) {
          final dirPath = p.join(root, 'bst', 'bst-pen', type.toUpperCase());
          Directory(dirPath).createSync(recursive: true);
          return File(p.join(dirPath, penFileName));
        }
      } catch (e) {
        debugPrint('[AnnotationStorageService] USB resolve failed: $e');
      }
    }

    final dir = await _getBstPenSubdirectory(type.toUpperCase());
    return File(p.join(dir.path, penFileName));
  }

  Future<File> _resolveBstsaveFile(String type, String fileName, {String? fullFilePath, String? classroomId, String? teacherId}) async {
    final penName = formatPenName(
      type: type,
      fileName: fileName,
      teacherId: teacherId,
      classroomId: classroomId,
    );
    final baseName = penName.endsWith('.pen') ? penName.substring(0, penName.length - 4) : penName;
    final saveFileName = '$baseName.bstsave';

    if (fullFilePath != null && !kIsWeb && Platform.isWindows) {
      try {
        final root = p.rootPrefix(fullFilePath);
        final usbFlag = File(p.join(root, 'BoardestUSB.json'));
        if (usbFlag.existsSync()) {
          final dirPath = p.join(root, 'bst', 'bst-save', type.toUpperCase());
          Directory(dirPath).createSync(recursive: true);
          return File(p.join(dirPath, saveFileName));
        }
      } catch (e) {
        debugPrint('[AnnotationStorageService] USB resolve failed: $e');
      }
    }

    final dir = await _getBstSaveSubdirectory(type.toUpperCase());
    return File(p.join(dir.path, saveFileName));
  }

  // ─── 레거시 .bstpen / .iwb / .json 폴백 읽기 ──────────────

  Future<File?> _findLegacyFile(String type, String fileName, {String? classroomId, String? teacherId}) async {
    final classCode = classToCode(classroomId);
    final dir = await _getBstPenSubdirectory(type.toUpperCase());
    final legacyDir = await _getBstSaveSubdirectory(type.toUpperCase());
    final sanitized = _sanitizeKey(fileName);
    String cleanBase = sanitized;
    if (cleanBase.endsWith('.pen')) cleanBase = cleanBase.substring(0, cleanBase.length - 4);

    final teacherPrefix = (teacherId != null && teacherId.isNotEmpty) ? '[$teacherId]' : '[Teacher]';

    final candidates = [
      '$teacherPrefix $cleanBase.pen',
      '$classCode $cleanBase.pen',
      '$classCode$cleanBase.pen',
      '$classCode$cleanBase.bstpen',
      '$classCode $cleanBase.bstpen',
      '$classCode$cleanBase.iwb',
      '$cleanBase.pen',
      '$cleanBase.bstpen',
      '$cleanBase.iwb',
    ];

    for (final cand in candidates) {
      final f1 = File(p.join(dir.path, cand));
      if (f1.existsSync()) return f1;
      final f2 = File(p.join(legacyDir.path, cand));
      if (f2.existsSync()) return f2;
    }
    return null;
  }

  // ─── 저장 ──────────────────────────────────────────────────────────────

  /// PDF/PPT/HWP/문서/칠판 판서 저장 (.pen 표준)
  Future<void> saveDocumentAnnotations(
    String type,
    String fileName,
    Map<String, dynamic> metadata,
    Map<int, List<AnnotationStroke>> pageAnnotations, {
    String? fullFilePath,
    String? classroomId,
    String? className,
    String? teacherId,
    bool isTeacherApp = false,
    bool isCloud = false,
  }) async {
    try {
      final effectiveClass = classroomId ?? className;
      final formattedPenName = formatPenName(
        type: type,
        fileName: fileName,
        isTeacherApp: isTeacherApp,
        isCloud: isCloud,
        teacherId: teacherId,
        classroomId: effectiveClass,
      );

      final totalPages = metadata['totalPages'] as int? ?? (pageAnnotations.isEmpty ? 1 : pageAnnotations.keys.reduce((a, b) => a > b ? a : b) + 1);

      // 1. 판서 스트로크 데이터 구조화
      final Map<String, dynamic> penData = {
        'version': 2,
        'type': type,
        'fileName': fileName,
        'formattedPenName': formattedPenName,
        'classroomId': effectiveClass ?? '',
        'teacherId': teacherId ?? '',
        'totalPages': totalPages,
        'savedAt': DateTime.now().toIso8601String(),
        'metadata': metadata,
        'pages': {},
      };

      pageAnnotations.forEach((pageIdx, strokes) {
        penData['pages'][pageIdx.toString()] = strokes.map((stroke) => {
          'points': stroke.points.map((pt) => {'dx': pt.dx, 'dy': pt.dy}).toList(),
          'color': stroke.color.value,
          'strokeWidth': stroke.strokeWidth,
          'isEraser': stroke.isEraser,
        }).toList();
      });

      // 2. 로컬 / USB 디스크에 .pen 파일로 저장
      if (!kIsWeb) {
        final penFile = await _resolvePenFile(
          type,
          fileName,
          fullFilePath: fullFilePath,
          classroomId: effectiveClass,
          teacherId: teacherId,
          isTeacherApp: isTeacherApp,
          isCloud: isCloud,
        );
        await penFile.parent.create(recursive: true);
        await penFile.writeAsString(json.encode(penData), flush: true);

        // 메타데이터 .bstsave 도 저장
        final metaFile = await _resolveBstsaveFile(
          type,
          fileName,
          fullFilePath: fullFilePath,
          classroomId: effectiveClass,
          teacherId: teacherId,
        );
        await metaFile.parent.create(recursive: true);
        await metaFile.writeAsString(json.encode(metadata), flush: true);
      }

      // 3. BstCloudService 실시간 동기화 상태 갱신
      try {
        BstCloudService.instance.saveSyncState(formattedPenName, penData);
      } catch (_) {}

      debugPrint('[AnnotationStorageService] Saved .pen: $formattedPenName ($type)');
    } catch (e) {
      debugPrint('[AnnotationStorageService] Error saving $type annotations for $fileName: $e');
    }
  }

  // ─── 읽기 ──────────────────────────────────────────────────────────────

  /// PDF/PPT/HWP/칠판 판서 로드 (.pen 우선)
  Future<Map<int, List<AnnotationStroke>>> loadDocumentAnnotations(
    String type,
    String fileName, {
    String? fullFilePath,
    String? classroomId,
    String? className,
    String? teacherId,
    bool isTeacherApp = false,
    bool isCloud = false,
    File? forcedFile,
  }) async {
    try {
      final effectiveClass = classroomId ?? className;
      File? file = forcedFile;
      if (file == null && !kIsWeb) {
        final penFile = await _resolvePenFile(
          type,
          fileName,
          fullFilePath: fullFilePath,
          classroomId: effectiveClass,
          teacherId: teacherId,
          isTeacherApp: isTeacherApp,
          isCloud: isCloud,
        );
        if (penFile.existsSync()) {
          file = penFile;
        } else {
          file = await _findLegacyFile(type, fileName, classroomId: effectiveClass, teacherId: teacherId);
        }
      }

      if (file == null || !file.existsSync()) return {};

      final penStr = await file.readAsString();
      final penData = json.decode(penStr) as Map<String, dynamic>;
      final pagesData = penData['pages'] as Map<String, dynamic>? ?? {};

      final Map<int, List<AnnotationStroke>> result = {};
      pagesData.forEach((pageStr, strokesJsonList) {
        final pageIdx = int.tryParse(pageStr);
        if (pageIdx != null && strokesJsonList is List) {
          result[pageIdx] = strokesJsonList.map((item) {
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

      return result;
    } catch (e) {
      debugPrint('[AnnotationStorageService] Error loading $type annotations for $fileName: $e');
      return {};
    }
  }

  // ─── 메타데이터 저장/로드 ───────────────────────────────────────────────

  Future<void> saveDocumentMetadata(
    String type,
    String fileName,
    Map<String, dynamic> metadata, {
    String? fullFilePath,
    String? teacherId,
    String? classroomId,
  }) async {
    try {
      final metaFile = await _resolveBstsaveFile(
        type,
        fileName,
        fullFilePath: fullFilePath,
        classroomId: classroomId,
        teacherId: teacherId,
      );
      await metaFile.parent.create(recursive: true);
      await metaFile.writeAsString(json.encode(metadata), flush: true);
    } catch (e) {
      debugPrint('[AnnotationStorageService] Error saving $type metadata for $fileName: $e');
    }
  }

  Future<Map<String, dynamic>?> loadDocumentMetadata(
    String type,
    String fileName, {
    String? fullFilePath,
    String? teacherId,
    String? classroomId,
  }) async {
    try {
      final metaFile = await _resolveBstsaveFile(
        type,
        fileName,
        fullFilePath: fullFilePath,
        classroomId: classroomId,
        teacherId: teacherId,
      );
      if (!metaFile.existsSync()) {
        final legacyDir = await _getBstSaveSubdirectory(type.toUpperCase());
        final legacy = File(p.join(legacyDir.path, '${_sanitizeKey(fileName)}.json'));
        if (legacy.existsSync()) {
          return json.decode(await legacy.readAsString()) as Map<String, dynamic>;
        }
        return null;
      }
      return json.decode(await metaFile.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[AnnotationStorageService] Error loading $type metadata for $fileName: $e');
      return null;
    }
  }

  // ─── 판서 삭제 ─────────────────────────────────────────────────────────

  Future<void> clearDocumentAnnotations(
    String type,
    String fileName, {
    String? fullFilePath,
    String? classroomId,
    String? teacherId,
  }) async {
    try {
      final metaFile = await _resolveBstsaveFile(type, fileName, fullFilePath: fullFilePath, classroomId: classroomId, teacherId: teacherId);
      if (metaFile.existsSync()) await metaFile.delete();

      final penFile = await _resolvePenFile(type, fileName, fullFilePath: fullFilePath, classroomId: classroomId, teacherId: teacherId);
      if (penFile.existsSync()) await penFile.delete();
    } catch (e) {
      debugPrint('[AnnotationStorageService] Error clearing $type annotations for $fileName: $e');
    }
  }
}

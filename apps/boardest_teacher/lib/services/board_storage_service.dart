import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'bst_save_service.dart';

/// 기본 판서: %appdata%/BstSave/Board — 파일당 .json(교사·과목 등) + .iwb(획만, 배경 무시)
class BoardStorageService {
  static final BoardStorageService instance = BoardStorageService._internal();
  BoardStorageService._internal();

  static const _mappingFileName = 'board_mappings.json';

  Future<Directory> _getBoardDirectory() =>
      BstSaveService.instance.directoryFor(BstSaveService.subBoard);

  String _sanitizeKey(String key) =>
      BstSaveService.instance.sanitizeFileName(key);

  File _mappingFile() => File(p.join(
        BstSaveService.instance.pathFor(BstSaveService.subBoard),
        _mappingFileName,
      ));

  /// 교사+과목 기본 보드 경로 (.iwb 전체 경로)
  Future<String?> getMappedBoardPath(String teacher, String subject) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('web_board_mapped_${teacher}_$subject');
    }
    final file = _mappingFile();
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final mappings = json.decode(raw) as Map<String, dynamic>;
      final key = '${teacher}_$subject';
      final path = mappings[key] as String?;
      if (path != null && path.isNotEmpty && await File(path).exists()) {
        return path;
      }
    } catch (e) {
      debugPrint('[BoardStorage] mapping read error: $e');
    }
    return null;
  }

  Future<void> setMappedBoardPath(
    String teacher,
    String subject,
    String iwbPath,
  ) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('web_board_mapped_${teacher}_$subject', iwbPath);
      return;
    }
    try {
      await _getBoardDirectory();
      final file = _mappingFile();
      Map<String, dynamic> mappings = {};
      if (await file.exists()) {
        try {
          mappings = json.decode(await file.readAsString()) as Map<String, dynamic>;
        } catch (_) {}
      }
      mappings['${teacher}_$subject'] = iwbPath;
      await file.writeAsString(json.encode(mappings), flush: true);
    } catch (e) {
      debugPrint('[BoardStorage] mapping save error: $e');
    }
  }

  String boardFileBaseName(String teacher, String subject) {
    final t = _sanitizeKey(teacher);
    final s = _sanitizeKey(subject);
    return '${t}_$s';
  }

  Future<String> defaultBoardPath(String teacher, String subject) async {
    if (kIsWeb) {
      return '${boardFileBaseName(teacher, subject)}.iwb';
    }
    final dir = await _getBoardDirectory();
    return p.join(dir.path, '${boardFileBaseName(teacher, subject)}.iwb');
  }

  /// 수업 시간: 매핑 → 동일 교사·과목 보드 → 기본 파일명 순
  Future<String> resolveBoardPathForLesson({
    required String teacher,
    required String subject,
  }) async {
    final mapped = await getMappedBoardPath(teacher, subject);
    if (mapped != null) return mapped;

    final boards = await listBoardsForTeacherAndSubject(teacher, subject);
    if (boards.isNotEmpty) {
      final fileName = boards.first['fileName'] as String;
      if (kIsWeb) return '$fileName.iwb';
      final dir = await _getBoardDirectory();
      return p.join(dir.path, '$fileName.iwb');
    }

    return defaultBoardPath(teacher, subject);
  }

  Future<void> saveBoardStrokes({
    required String fileBaseName,
    required Map<String, dynamic> metadata,
    required Map<int, List<Map<String, dynamic>>> pageStrokes,
    String? className,
  }) async {
    try {
      final sanitized = _sanitizeKey(fileBaseName);
      final classTag = (className != null && className.isNotEmpty && className != '전체 반 공용 (통합)') ? '[$className]' : '';
      final fullName = '$classTag$sanitized';

      final iwbData = <String, dynamic>{
        'version': 2,
        'strokesOnly': true,
        'totalPages': pageStrokes.isEmpty ? 1 : pageStrokes.keys.reduce((a, b) => a > b ? a : b),
        'pages': <String, dynamic>{},
      };

      pageStrokes.forEach((pageIdx, strokes) {
        iwbData['pages'][pageIdx.toString()] = strokes;
      });

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('web_board_meta_$fullName', json.encode(metadata));
        await prefs.setString('web_board_$fullName', json.encode(iwbData));
        debugPrint('[BoardStorage] Web saved board $fullName');
        return;
      }

      final dir = await _getBoardDirectory();
      final jsonFile = File(p.join(dir.path, '$fullName.json'));
      await jsonFile.writeAsString(json.encode(metadata), flush: true);

      final iwbFile = File(p.join(dir.path, '$fullName.iwb'));
      await iwbFile.writeAsString(json.encode(iwbData), flush: true);
      debugPrint('[BoardStorage] Saved board $fullName');
    } catch (e) {
      debugPrint('[BoardStorage] save error: $e');
    }
  }

  /// IWB 로드 — boardBgColor / bgPattern 은 무시 (판서 배경은 앱 설정 사용)
  Future<({
    int totalPages,
    Map<int, List<Map<String, dynamic>>> pageStrokes,
    Map<String, dynamic>? metadata,
  })?> loadBoardFromPath(String iwbPath) async {
    try {
      final baseName = p.basenameWithoutExtension(iwbPath);
      final metadata = await loadBoardMetadata(baseName);

      String? iwbStr;
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        iwbStr = prefs.getString('web_board_$baseName');
        if (iwbStr == null) return null;
      } else {
        final file = File(iwbPath);
        if (!await file.exists()) return null;
        iwbStr = await file.readAsString();
      }

      final iwbData = json.decode(iwbStr) as Map<String, dynamic>;
      final pagesData = iwbData['pages'] as Map<String, dynamic>? ?? {};

      final Map<int, List<Map<String, dynamic>>> result = {};
      pagesData.forEach((pageStr, strokesJsonList) {
        final pageIdx = int.tryParse(pageStr);
        if (pageIdx != null && strokesJsonList is List) {
          result[pageIdx] = strokesJsonList
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      });

      final totalPages = (iwbData['totalPages'] as num?)?.toInt() ??
          (result.keys.isEmpty ? 1 : result.keys.reduce((a, b) => a > b ? a : b));

      return (
        totalPages: totalPages,
        pageStrokes: result,
        metadata: metadata,
      );
    } catch (e) {
      debugPrint('[BoardStorage] load error for $iwbPath: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> loadBoardMetadata(String fileBaseName) async {
    try {
      final sanitized = _sanitizeKey(fileBaseName);
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final metaStr = prefs.getString('web_board_meta_$sanitized');
        if (metaStr == null) return null;
        return json.decode(metaStr) as Map<String, dynamic>;
      }
      final dir = await _getBoardDirectory();
      final file = File(p.join(dir.path, '$sanitized.json'));
      if (!await file.exists()) return null;
      return json.decode(await file.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listBoardsForTeacher(String teacher) async {
    if (kIsWeb) {
      return [];
    }
    try {
      final dir = await _getBoardDirectory();
      final boards = <Map<String, dynamic>>[];

      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        if (entity.path.endsWith(_mappingFileName)) continue;

        final fileName = p.basenameWithoutExtension(entity.path);
        final metadata = await loadBoardMetadata(fileName);
        if (metadata == null) continue;
        if (metadata['teacher'] != teacher) continue;

        final subject = metadata['subject'] as String? ?? '';
        if (_isBreakSubject(subject)) continue;

        boards.add({'fileName': fileName, 'metadata': metadata});
      }

      boards.sort((a, b) {
        final dateA = DateTime.tryParse(a['metadata']['updatedAt']?.toString() ?? '');
        final dateB = DateTime.tryParse(b['metadata']['updatedAt']?.toString() ?? '');
        if (dateA == null || dateB == null) return 0;
        return dateB.compareTo(dateA);
      });

      return boards;
    } catch (e) {
      debugPrint('[BoardStorage] list by teacher error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> listBoardsForTeacherAndSubject(
    String teacher,
    String subject,
  ) async {
    final all = await listBoardsForTeacher(teacher);
    return all
        .where((b) => (b['metadata'] as Map)['subject'] == subject)
        .toList();
  }

  static bool _isBreakSubject(String subject) {
    final s = subject.trim();
    return s.contains('쉬는') || s.contains('쉬는시간') || s == '점심' || s.contains('점심시간');
  }

  Future<void> deleteBoard(String fileBaseName) async {
    try {
      final sanitized = _sanitizeKey(fileBaseName);
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('web_board_meta_$sanitized');
        await prefs.remove('web_board_$sanitized');
        return;
      }
      final dir = await _getBoardDirectory();
      for (final ext in ['.json', '.iwb']) {
        final f = File(p.join(dir.path, '$sanitized$ext'));
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      debugPrint('[BoardStorage] delete error: $e');
    }
  }
}

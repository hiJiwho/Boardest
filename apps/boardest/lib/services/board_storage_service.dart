import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'bst_save_service.dart';
import 'app_paths.dart';
import 'annotation_storage_service.dart';

/// 전자칠판 로컬 기본 판서 및 교사별 화이트보드 관리 스토리지 서비스
/// - 파일 규격: .pen 표준
/// - 로컬 저장 시: [교사ID] {파일명}.pen (화이트보드: [교사ID] {날짜_시간}.pen)
/// - Cloud 저장 시: [교실ID] {파일명}.pen
class BoardStorageService {
  static final BoardStorageService instance = BoardStorageService._internal();
  BoardStorageService._internal();

  static const _mappingFileName = 'board_mappings.json';

  /// 판서 파일명 한국어 친절 포맷팅
  /// 예: "[2-8] 2026-09-04_194842.pen" -> "2학년 8반에서 26년 09월 04일에 시작한 판서"
  static String formatBoardDisplayName(String rawName) {
    if (rawName.isEmpty) return '판서';
    final baseName = p.basenameWithoutExtension(rawName);

    // 1. 학년 / 반 파싱
    String? gradeText;
    String? classText;

    // 패턴 1: [2-8], [208], [2학년 8반]
    final bracketMatch = RegExp(r'\[([0-9]+)[-_ ]?([0-9]*)\]').firstMatch(baseName);
    if (bracketMatch != null) {
      final p1 = bracketMatch.group(1) ?? '';
      final p2 = bracketMatch.group(2) ?? '';
      if (p2.isNotEmpty) {
        gradeText = '${p1}학년';
        classText = '${int.tryParse(p2) ?? p2}반';
      } else if (p1.length == 3) {
        gradeText = '${p1[0]}학년';
        classText = '${int.tryParse(p1.substring(1)) ?? p1.substring(1)}반';
      } else if (p1.length == 2) {
        gradeText = '${p1[0]}학년';
        classText = '${int.tryParse(p1.substring(1)) ?? p1.substring(1)}반';
      }
    }

    if (gradeText == null) {
      final prefixMatch = RegExp(r'^([1-6])[-_]([0-9]{1,2})').firstMatch(baseName);
      if (prefixMatch != null) {
        gradeText = '${prefixMatch.group(1)}학년';
        classText = '${int.tryParse(prefixMatch.group(2)!) ?? prefixMatch.group(2)}반';
      }
    }

    // 2. 날짜 파싱 (2026-09-04 or 20260904 or 260904)
    String? dateText;
    final dateMatch1 = RegExp(r'(20[2-3][0-9])[-_.](0[1-9]|1[0-2])[-_.]([0-3][0-9])').firstMatch(baseName);
    if (dateMatch1 != null) {
      final y = dateMatch1.group(1)!.substring(2);
      final m = dateMatch1.group(2)!;
      final d = dateMatch1.group(3)!;
      dateText = '${y}년 ${m}월 ${d}일';
    } else {
      final dateMatch2 = RegExp(r'(2[0-9])(0[1-9]|1[0-2])([0-3][0-9])').firstMatch(baseName);
      if (dateMatch2 != null) {
        final y = dateMatch2.group(1)!;
        final m = dateMatch2.group(2)!;
        final d = dateMatch2.group(3)!;
        dateText = '${y}년 ${m}월 ${d}일';
      }
    }

    if (gradeText != null && classText != null && dateText != null) {
      return '$gradeText $classText에서 $dateText에 시작한 판서';
    } else if (gradeText != null && classText != null) {
      return '$gradeText $classText 판서';
    } else if (dateText != null) {
      return '$dateText에 시작한 판서';
    }

    return baseName;
  }

  Future<Directory> _getBoardDirectory() =>
      BstSaveService.instance.directoryFor(BstSaveService.subBoard);

  Future<Directory> _getPenRootDirectory() async {
    final dir = Directory(AppPaths.bstPenRootSync);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _sanitizeKey(String key) =>
      BstSaveService.instance.sanitizeFileName(key);

  File _mappingFile() => File(p.join(
        BstSaveService.instance.pathFor(BstSaveService.subBoard),
        _mappingFileName,
      ));

  String boardFileBaseName(String teacher, String subject) {
    final t = _sanitizeKey(teacher);
    final s = _sanitizeKey(subject);
    return '${t}_$s';
  }

  /// 교사+과목 기본 보드 경로 (.pen 전체 경로)
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
    String penPath,
  ) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('web_board_mapped_${teacher}_$subject', penPath);
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
      mappings['${teacher}_$subject'] = penPath;
      await file.writeAsString(json.encode(mappings), flush: true);
    } catch (e) {
      debugPrint('[BoardStorage] mapping save error: $e');
    }
  }

  /// 수업 시간: 시간표 기준 교사가 들어왔을 때 해당 교사의 최근 화이트보드 (.pen) 로드 또는 신규 생성
  Future<String> resolveBoardPathForLesson({
    required String teacher,
    String? subject,
    bool isCloud = false,
    String? classroomId,
  }) async {
    // 1. Cloud 연동 상태인 경우: [교실ID] {날짜_시간}.pen
    if (isCloud) {
      final penName = AnnotationStorageService.formatPenName(
        type: 'WHITEBOARD',
        isTeacherApp: false,
        isCloud: true,
        classroomId: classroomId,
      );
      final dir = await _getBoardDirectory();
      return p.join(dir.path, penName);
    }

    // 2. Local 상태인 경우: 해당 교사의 최근 저장된 로컬 화이트보드 탐색
    final teacherBoards = await listBoardsForTeacher(teacher);
    if (teacherBoards.isNotEmpty) {
      final latest = teacherBoards.first;
      final fullPath = latest['fullPath'] as String?;
      if (fullPath != null && await File(fullPath).exists()) {
        return fullPath;
      }
    }

    // 3. 최근 화이트보드가 없으면 신규 [교사ID] {날짜_시간}.pen 경로 생성
    final newPenName = AnnotationStorageService.formatPenName(
      type: 'WHITEBOARD',
      teacherId: teacher,
      isTeacherApp: false,
      isCloud: false,
    );
    final dir = await _getBoardDirectory();
    return p.join(dir.path, newPenName);
  }

  /// 특정 교사의 로컬 화이트보드 목록 조회 (.pen 파일들)
  Future<List<Map<String, dynamic>>> listBoardsForTeacher(String teacher) async {
    if (kIsWeb) return [];
    try {
      final dir = await _getBoardDirectory();
      final penRootDir = await _getPenRootDirectory();
      final cleanTeacher = teacher.replaceAll(RegExp(r'[\[\]]'), '').trim();
      final tag = '[$cleanTeacher]';

      final List<File> filesToCheck = [];
      if (dir.existsSync()) {
        filesToCheck.addAll(dir.listSync(recursive: true).whereType<File>());
      }
      if (penRootDir.existsSync()) {
        filesToCheck.addAll(penRootDir.listSync(recursive: true).whereType<File>());
      }

      final boards = <Map<String, dynamic>>[];
      final seenPaths = <String>{};

      for (final file in filesToCheck) {
        final fileName = p.basename(file.path);
        final ext = p.extension(file.path).toLowerCase();
        if (ext != '.pen' && ext != '.iwb') continue;
        if (!fileName.contains(tag) && !fileName.contains(cleanTeacher)) continue;
        if (seenPaths.contains(file.path)) continue;
        seenPaths.add(file.path);

        final stat = file.statSync();
        boards.add({
          'fileName': fileName,
          'fullPath': file.path,
          'teacher': cleanTeacher,
          'modifiedTime': stat.modified,
          'size': stat.size,
        });
      }

      boards.sort((a, b) {
        final tA = a['modifiedTime'] as DateTime;
        final tB = b['modifiedTime'] as DateTime;
        return tB.compareTo(tA);
      });

      return boards;
    } catch (e) {
      debugPrint('[BoardStorage] list by teacher error: $e');
      return [];
    }
  }

  /// 로컬에 판서가 저장된 전체 교사 목록 및 교사별 화이트보드 맵 조회 (Cloud 사용 교사는 제외)
  Future<Map<String, List<Map<String, dynamic>>>> listAllLocalTeachersWithBoards() async {
    final Map<String, List<Map<String, dynamic>>> resultMap = {};
    if (kIsWeb) return resultMap;

    try {
      final dir = await _getBoardDirectory();
      final penRootDir = await _getPenRootDirectory();

      final List<File> files = [];
      if (dir.existsSync()) {
        files.addAll(dir.listSync(recursive: true).whereType<File>());
      }
      if (penRootDir.existsSync()) {
        files.addAll(penRootDir.listSync(recursive: true).whereType<File>());
      }

      for (final f in files) {
        final fileName = p.basename(f.path);
        final ext = p.extension(f.path).toLowerCase();
        if (ext != '.pen' && ext != '.iwb') continue;

        // Cloud 접두사 또는 [Teacher]는 제외하고 [교사ID] 패턴만 추출
        if (fileName.startsWith('[Teacher]')) continue;
        // 반ID 패턴([101], [203] 등)도 교실용이므로 제외
        if (RegExp(r'^\[\d+\]').hasMatch(fileName)) continue;

        String teacherName = '기타 교사';
        if (fileName.startsWith('[')) {
          final closeIdx = fileName.indexOf(']');
          if (closeIdx > 1) {
            teacherName = fileName.substring(1, closeIdx).trim();
          }
        }

        final stat = f.statSync();
        final item = {
          'fileName': fileName,
          'fullPath': f.path,
          'teacher': teacherName,
          'modifiedTime': stat.modified,
          'size': stat.size,
        };

        resultMap.putIfAbsent(teacherName, () => []).add(item);
      }

      // 각 교사별 최신순 정렬
      resultMap.forEach((k, v) {
        v.sort((a, b) => (b['modifiedTime'] as DateTime).compareTo(a['modifiedTime'] as DateTime));
      });
    } catch (e) {
      debugPrint('[BoardStorage] listAllLocalTeachersWithBoards error: $e');
    }

    return resultMap;
  }

  /// 보드 로드 (.pen / .iwb 호환)
  Future<({
    int totalPages,
    Map<int, List<Map<String, dynamic>>> pageStrokes,
    Map<String, dynamic>? metadata,
  })?> loadBoardFromPath(String penPath) async {
    try {
      final baseName = p.basenameWithoutExtension(penPath);
      final metadata = await loadBoardMetadata(baseName);

      String? contentStr;
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        contentStr = prefs.getString('web_board_$baseName');
        if (contentStr == null) return null;
      } else {
        final file = File(penPath);
        if (!await file.exists()) return null;
        contentStr = await file.readAsString();
      }

      final data = json.decode(contentStr) as Map<String, dynamic>;
      final pagesData = data['pages'] as Map<String, dynamic>? ?? {};

      final Map<int, List<Map<String, dynamic>>> result = {};
      pagesData.forEach((pageStr, strokesJsonList) {
        final pageIdx = int.tryParse(pageStr);
        if (pageIdx != null && strokesJsonList is List) {
          result[pageIdx] = strokesJsonList
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      });

      final totalPages = (data['totalPages'] as num?)?.toInt() ??
          (result.keys.isEmpty ? 1 : result.keys.reduce((a, b) => a > b ? a : b));

      return (
        totalPages: totalPages,
        pageStrokes: result,
        metadata: metadata,
      );
    } catch (e) {
      debugPrint('[BoardStorage] load error for $penPath: $e');
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

      final penData = <String, dynamic>{
        'version': 2,
        'strokesOnly': true,
        'totalPages': pageStrokes.isEmpty ? 1 : pageStrokes.keys.reduce((a, b) => a > b ? a : b),
        'pages': <String, dynamic>{},
      };

      pageStrokes.forEach((pageIdx, strokes) {
        penData['pages'][pageIdx.toString()] = strokes;
      });

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('web_board_meta_$fullName', json.encode(metadata));
        await prefs.setString('web_board_$fullName', json.encode(penData));
        return;
      }

      final dir = await _getBoardDirectory();
      final jsonFile = File(p.join(dir.path, '$fullName.json'));
      await jsonFile.writeAsString(json.encode(metadata), flush: true);

      final penFile = File(p.join(dir.path, '$fullName.pen'));
      await penFile.writeAsString(json.encode(penData), flush: true);
    } catch (e) {
      debugPrint('[BoardStorage] save error: $e');
    }
  }

  /// 보드 삭제 (.pen 및 관련 메타 파일)
  Future<void> deleteBoardByPath(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      final jsonPath = p.setExtension(filePath, '.json');
      final jFile = File(jsonPath);
      if (await jFile.exists()) await jFile.delete();

      final savePath = p.setExtension(filePath, '.bstsave');
      final sFile = File(savePath);
      if (await sFile.exists()) await sFile.delete();
    } catch (e) {
      debugPrint('[BoardStorage] delete error: $e');
    }
  }
}

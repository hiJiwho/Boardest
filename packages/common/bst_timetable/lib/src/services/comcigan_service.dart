import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:bst_core/bst_core.dart';

class TimetableResult {
  final String schoolName;
  final List<String> periodTimes;
  final Map<int, int> classCounts;
  final List<Lesson> lessons;
  final Map<int, Map<int, String>> homeroomTeachers;

  TimetableResult({
    required this.schoolName,
    required this.periodTimes,
    required this.classCounts,
    required this.lessons,
    required this.homeroomTeachers,
  });

  /// 특별실 모드: 특정 교시에 특정 교사(약칭)가 수업하는 학급을 역추적합니다.
  Map<String, int>? findClassByTeacherAndPeriod({
    required int weekday,
    required int period,
    required String teacherAbbr,
  }) {
    if (teacherAbbr.isEmpty) return null;
    final sanitized = teacherAbbr.replaceAll('*', '').trim();
    if (sanitized.isEmpty) return null;

    for (final lesson in lessons) {
      if (lesson.weekday == weekday &&
          lesson.classTime == period &&
          lesson.teacher.replaceAll('*', '').trim() == sanitized) {
        return {'grade': lesson.grade, 'classNum': lesson.classNum};
      }
    }
    return null;
  }
}

class ComciganService {
  final http.Client _client;

  ComciganService({http.Client? client}) : _client = client ?? http.Client();

  /// 컴시간 원본 JSON 데이터를 표준 키 포맷으로 정규화합니다.
  static Map<String, dynamic> normalizeRawData(Map<String, dynamic> rawJson) {
    final normalized = <String, dynamic>{};
    rawJson.forEach((k, v) {
      if (k.contains('147')) {
        normalized['자료147'] = v;
      } else if (k.contains('446')) {
        normalized['자료446'] = v;
      } else if (k.contains('492')) {
        normalized['자료492'] = v;
      } else if (k.contains('481')) {
        normalized['자료481'] = v;
      } else if (k.contains('542')) {
        normalized['자료542'] = v;
      } else if (k.contains('245')) {
        normalized['자료245'] = v;
      } else if (k.contains('학급수') || (v is List && v.length == 4 && v[1] is num)) {
        normalized['학급수'] = v;
      } else if (k.contains('분리') || v == 100 || v == 1000) {
        normalized['분리'] = v;
      } else if (k.contains('일과시간') || (v is List && v.isNotEmpty && v.first.toString().contains('('))) {
        normalized['일과시간'] = v;
      } else if (k.contains('학교명')) {
        normalized['학교명'] = v;
      } else {
        normalized[k] = v;
      }
    });
    return normalized;
  }

  /// 컴시간 원본 데이터를 파싱하여 TimetableResult 객체로 반환합니다.
  static TimetableResult parseTimetableData(
    Map<String, dynamic> rawJson, {
    int? targetGrade,
    int? targetClass,
  }) {
    final data = normalizeRawData(rawJson);

    final schoolName = data['학교명'] as String? ?? '';
    final periodTimesRaw = data['일과시간'] as List? ?? [];
    final periodTimes = periodTimesRaw.map((e) => e.toString()).toList();

    final classCountsRaw = data['학급수'] as List? ?? [0, 0, 0, 0];
    final classCounts = <int, int>{};
    for (int g = 1; g <= 3; g++) {
      if (g < classCountsRaw.length) {
        classCounts[g] = (classCountsRaw[g] as num?)?.toInt() ?? 0;
      }
    }

    final teachersRaw = data['자료446'] as List? ?? [];
    final subjectsRaw = data['자료492'] as List? ?? [];
    final lessonsRaw = data['자료481'] as List? ?? [];

    final homeroomTeachers = <int, Map<int, String>>{};
    final lessons = <Lesson>[];

    // 담임선생님 정보 추출 (자료147)
    final homeroomRaw = data['자료147'] as List?;
    if (homeroomRaw != null) {
      for (int g = 1; g < homeroomRaw.length; g++) {
        if (homeroomRaw[g] is List) {
          final gList = homeroomRaw[g] as List;
          for (int c = 1; c < gList.length; c++) {
            final tIndex = (gList[c] as num?)?.toInt() ?? 0;
            if (tIndex > 0 && tIndex < teachersRaw.length) {
              homeroomTeachers.putIfAbsent(g, () => {})[c] = teachersRaw[tIndex].toString();
            }
          }
        }
      }
    }

    // 시간표 과목 및 교사 매핑 (자료481: [grade][class][weekday][period])
    if (lessonsRaw.isNotEmpty) {
      for (int g = 1; g < lessonsRaw.length; g++) {
        if (targetGrade != null && targetGrade != g) continue;
        if (lessonsRaw[g] is! List) continue;
        final gradeList = lessonsRaw[g] as List;

        for (int c = 1; c < gradeList.length; c++) {
          if (targetClass != null && targetClass != c) continue;
          if (gradeList[c] is! List) continue;
          final classList = gradeList[c] as List;

          for (int w = 1; w < classList.length && w <= 5; w++) {
            if (classList[w] is! List) continue;
            final dayList = classList[w] as List;

            for (int p = 1; p < dayList.length; p++) {
              final cellVal = (dayList[p] as num?)?.toInt() ?? 0;
              if (cellVal <= 0) continue;

              final int sIndex;
              final int tIndex;
              final int separation = (data['분리'] as num?)?.toInt() ?? 100;

              if (separation == 1000) {
                sIndex = cellVal ~/ 1000;
                tIndex = cellVal % 1000;
              } else {
                sIndex = cellVal ~/ 100;
                tIndex = cellVal % 100;
              }

              final subjectName = (sIndex > 0 && sIndex < subjectsRaw.length)
                  ? subjectsRaw[sIndex].toString()
                  : '';
              final teacherName = (tIndex > 0 && tIndex < teachersRaw.length)
                  ? teachersRaw[tIndex].toString()
                  : '';

              if (subjectName.isNotEmpty || teacherName.isNotEmpty) {
                lessons.add(Lesson(
                  grade: g,
                  classNum: c,
                  weekday: w,
                  classTime: p,
                  teacher: teacherName,
                  subject: subjectName,
                  classroom: '$g-$c',
                  isChanged: false,
                ));
              }
            }
          }
        }
      }
    }

    return TimetableResult(
      schoolName: schoolName,
      periodTimes: periodTimes,
      classCounts: classCounts,
      lessons: lessons,
      homeroomTeachers: homeroomTeachers,
    );
  }

  /// 웹 및 데스크톱 전 환경에서 학교 시간표 원본 JSON을 조회합니다.
  Future<Map<String, dynamic>> fetchTimetableRaw(
    int schoolCode, {
    int weekOffset = 0,
    http.Client? client,
  }) async {
    final activeClient = client ?? _client;
    final workerUrl = Uri.parse('https://comcigan.jiwho.workers.dev/api/comcigan/lookup?code=$schoolCode');
    
    try {
      final response = await activeClient.get(workerUrl).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonMap = json.decode(utf8.decode(response.bodyBytes));
        final Map<String, dynamic> data = jsonMap['data'] ?? {};
        final Map<String, dynamic> rawJson = Map<String, dynamic>.from(data['rawJson'] ?? {});
        final normalized = normalizeRawData(rawJson);
        if (!normalized.containsKey('학교명') || normalized['학교명'] == null || normalized['학교명'].toString().isEmpty) {
          normalized['학교명'] = 'School_$schoolCode';
        }
        return normalized;
      }
    } catch (_) {
      // Worker failed or timed out
    }

    // Fallback: return minimal structure with schoolCode
    return normalizeRawData({'학교명': 'School_$schoolCode'});
  }
}

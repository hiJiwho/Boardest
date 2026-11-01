import 'dart:convert';
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
    if (teacherAbbr.isEmpty) {
      return null;
    }
    final sanitized = teacherAbbr.replaceAll('*', '').replaceAll('선생님', '').trim();
    if (sanitized.isEmpty) {
      return null;
    }

    for (final lesson in lessons) {
      if (lesson.weekday == weekday && lesson.classTime == period) {
        final tName = lesson.teacher.replaceAll('*', '').replaceAll('선생님', '').trim();
        if (tName.isEmpty) {
          continue;
        }
        if (tName == sanitized) {
          return {'grade': lesson.grade, 'classNum': lesson.classNum};
        }
        // Substring / prefix match for 2+ char names (e.g. "홍길" in "홍길동")
        if (sanitized.length >= 2 && (tName.startsWith(sanitized) || sanitized.startsWith(tName))) {
          return {'grade': lesson.grade, 'classNum': lesson.classNum};
        }
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'schoolName': schoolName,
      'periodTimes': periodTimes,
      'classCounts': classCounts.map((k, v) => MapEntry(k.toString(), v)),
      'lessons': lessons.map((l) => l.toJson()).toList(),
      'homeroomTeachers': homeroomTeachers.map(
        (g, m) => MapEntry(g.toString(), m.map((c, t) => MapEntry(c.toString(), t))),
      ),
    };
  }

  factory TimetableResult.fromJson(Map<String, dynamic> json) {
    final schoolName = json['schoolName']?.toString() ?? '';
    final periodTimes = (json['periodTimes'] as List? ?? []).map((e) => e.toString()).toList();
    final classCounts = <int, int>{};
    if (json['classCounts'] is Map) {
      (json['classCounts'] as Map).forEach((k, v) {
        final g = int.tryParse(k.toString());
        if (g != null) {
          classCounts[g] = (v as num?)?.toInt() ?? 0;
        }
      });
    }
    final lessons = <Lesson>[];
    if (json['lessons'] is List) {
      for (final l in json['lessons'] as List) {
        if (l is Map) {
          lessons.add(Lesson.fromJson(Map<String, dynamic>.from(l)));
        }
      }
    }
    final homeroomTeachers = <int, Map<int, String>>{};
    if (json['homeroomTeachers'] is Map) {
      (json['homeroomTeachers'] as Map).forEach((gk, gv) {
        final g = int.tryParse(gk.toString());
        if (g != null && gv is Map) {
          final cMap = <int, String>{};
          gv.forEach((ck, cv) {
            final c = int.tryParse(ck.toString());
            if (c != null && cv != null) {
              cMap[c] = cv.toString();
            }
          });
          homeroomTeachers[g] = cMap;
        }
      });
    }
    return TimetableResult(
      schoolName: schoolName,
      periodTimes: periodTimes,
      classCounts: classCounts,
      lessons: lessons,
      homeroomTeachers: homeroomTeachers,
    );
  }
}

class ComciganService {
  final http.Client _client;
  static final Map<int, Map<String, dynamic>> _cache = {};

  ComciganService({http.Client? client}) : _client = client ?? http.Client();

  /// Gets cached raw timetable for a school if available.
  static Map<String, dynamic>? getCachedData(int schoolCode) {
    return _cache[schoolCode];
  }

  /// Sets cached raw timetable for a school.
  static void setCachedData(int schoolCode, Map<String, dynamic> data) {
    _cache[schoolCode] = Map<String, dynamic>.from(data);
  }

  /// Clears the timetable cache.
  static void clearCache({int? schoolCode}) {
    if (schoolCode != null) {
      _cache.remove(schoolCode);
    } else {
      _cache.clear();
    }
  }

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
      } else if (k.contains('학급수') || (v is List && v.length >= 4 && v.length <= 10 && v[1] is num)) {
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
    for (int g = 1; g < classCountsRaw.length; g++) {
      classCounts[g] = (classCountsRaw[g] as num?)?.toInt() ?? 0;
    }
    if (classCounts.isEmpty) {
      classCounts[1] = 0;
      classCounts[2] = 0;
      classCounts[3] = 0;
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
              final tName = teachersRaw[tIndex]?.toString().trim() ?? '';
              if (tName.isNotEmpty) {
                homeroomTeachers.putIfAbsent(g, () => {})[c] = tName;
              }
            }
          }
        }
      }
    }

    // 시간표 과목 및 교사 매핑 (자료481: [grade][class][weekday][period])
    // w: 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun (주말 시간표 지원)
    if (lessonsRaw.isNotEmpty) {
      for (int g = 1; g < lessonsRaw.length; g++) {
        if (targetGrade != null && targetGrade != g) {
          continue;
        }
        if (lessonsRaw[g] is! List) {
          continue;
        }
        final gradeList = lessonsRaw[g] as List;

        for (int c = 1; c < gradeList.length; c++) {
          if (targetClass != null && targetClass != c) {
            continue;
          }
          if (gradeList[c] is! List) {
            continue;
          }
          final classList = gradeList[c] as List;

          for (int w = 1; w < classList.length && w <= 7; w++) {
            if (classList[w] is! List) {
              continue;
            }
            final dayList = classList[w] as List;

            for (int p = 1; p < dayList.length; p++) {
              final rawCell = dayList[p];
              final int cellVal;
              final bool isChangedCell;

              if (rawCell is num) {
                cellVal = rawCell.toInt();
                isChangedCell = false;
              } else if (rawCell is String) {
                final cleaned = rawCell.replaceAll('>', '').trim();
                cellVal = int.tryParse(cleaned) ?? 0;
                isChangedCell = rawCell.contains('>');
              } else {
                cellVal = 0;
                isChangedCell = false;
              }

              if (cellVal <= 0) {
                continue;
              }

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
                  ? (subjectsRaw[sIndex]?.toString().trim() ?? '')
                  : '';
              String teacherName = (tIndex > 0 && tIndex < teachersRaw.length)
                  ? (teachersRaw[tIndex]?.toString().trim() ?? '')
                  : '';

              // 교사 미지정 시 담임교사 폴백 (자율/동아리/창체/진로 등)
              if (teacherName.isEmpty && homeroomTeachers[g]?[c] != null) {
                if (subjectName.contains('자율') ||
                    subjectName.contains('동아리') ||
                    subjectName.contains('창체') ||
                    subjectName.contains('진로') ||
                    subjectName.isEmpty) {
                  teacherName = homeroomTeachers[g]![c]!;
                }
              }

              if (subjectName.isNotEmpty || teacherName.isNotEmpty) {
                lessons.add(Lesson(
                  grade: g,
                  classNum: c,
                  weekday: w,
                  classTime: p,
                  teacher: teacherName,
                  subject: subjectName,
                  classroom: '$g-$c',
                  isChanged: isChangedCell,
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

  /// 웹 및 데스크톱 전 환경에서 학교 시간표 원본 JSON을 조회합니다 (오프라인 캐싱 지원).
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
        final bool isRealData = rawJson.isNotEmpty &&
            (rawJson.containsKey('자료481') ||
                rawJson.containsKey('자료446') ||
                (normalized.containsKey('학교명') &&
                    !normalized['학교명'].toString().startsWith('School_')));
        if (!normalized.containsKey('학교명') || normalized['학교명'] == null || normalized['학교명'].toString().isEmpty) {
          normalized['학교명'] = 'School_$schoolCode';
        }
        if (isRealData) {
          _cache[schoolCode] = normalized;
          return normalized;
        } else if (_cache.containsKey(schoolCode)) {
          return _cache[schoolCode]!;
        }
        return normalized;
      }
    } catch (_) {
      // Worker failed or timed out (offline)
    }

    // 오프라인 캐시 우선 복구
    if (_cache.containsKey(schoolCode)) {
      return _cache[schoolCode]!;
    }

    // Fallback: return minimal structure with schoolCode
    return normalizeRawData({'학교명': 'School_$schoolCode'});
  }
}

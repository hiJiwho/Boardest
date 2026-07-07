import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cp949_codec/cp949_codec.dart';
import '../models/school.dart';
import '../models/lesson.dart';

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
  /// 한 교사는 동시에 한 반만 가르칠 수 있으므로 첫 번째 매칭 결과를 반환합니다.
  /// 
  /// [weekday]: 1=월요일 ~ 5=금요일
  /// [period]: 교시 번호 (1~8)
  /// [teacherAbbr]: 컴시간에서 온 교사 약칭 (예: "김희", "이정" 등 2글자)
  /// 
  /// 반환: { 'grade': X, 'classNum': Y } 또는 null (찾을 수 없는 경우)
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
  static const String _defaultUrl = 'http://xn--s39aj90b0nb2xw6xh.kr';
  
  String? _baseUrl;
  String? _extractCode;
  List<String>? _scData;

  String? get baseUrl => _baseUrl;
  String? get extractCode => _extractCode;
  List<String>? get scData => _scData;

  /// Initializes the session parameters by fetching the Comcigan landing frame.
  Future<void> init() async {
    // 이미 초기화된 경우 스킵 (재호출 시 실패 방지)
    if (_baseUrl != null && _extractCode != null && _scData != null) return;
    try {
      final response = await http.get(Uri.parse(_defaultUrl)).timeout(const Duration(seconds: 7));
      String html;
      try {
        html = utf8.decode(response.bodyBytes);
      } catch (_) {
        html = cp949.decode(response.bodyBytes);
      }

      // Parse the frame source URL
      final RegExp frameRegExp = RegExp(r"""<frame\s+[^>]*src=["']([^"']+)["']""", caseSensitive: false);
      final match = frameRegExp.firstMatch(html);
      if (match == null) {
        throw Exception('Failed to find frame source in Comcigan landing page');
      }
      
      String framePath = match.group(1)!;
      final resolvedUri = Uri.parse(_defaultUrl).resolve(framePath);
      _baseUrl = '${resolvedUri.scheme}://${resolvedUri.host}:${resolvedUri.port}';

      // Load frame HTML and decode in CP949
      final frameResponse = await http.get(resolvedUri).timeout(const Duration(seconds: 7));
      final frameHtml = cp949.decode(frameResponse.bodyBytes);

      // Extract school search code path
      // e.g. url:'./36179?17384l'+sc -> url: './36179?17384l'
      final RegExp schoolRaRegExp = RegExp(r"url\s*:\s*'\s*\./([^']+)'", caseSensitive: false);
      final schoolRaMatch = schoolRaRegExp.firstMatch(frameHtml);
      if (schoolRaMatch == null) {
        throw Exception('Failed to extract school_ra search path');
      }
      _extractCode = '/${schoolRaMatch.group(1)!}';

      // Extract sc_data parameters
      // e.g. sc_data('73629_',sc,1,'0');
      final int scDataIdx = frameHtml.indexOf("sc_data('");
      if (scDataIdx == -1) {
        throw Exception('Failed to locate sc_data initialization call');
      }
      final String subStr = frameHtml.substring(scDataIdx, scDataIdx + 50).replaceAll(' ', '');
      final RegExp argRegExp = RegExp(r"\((.*?)\)");
      final argMatch = argRegExp.firstMatch(subStr);
      if (argMatch == null) {
        throw Exception('Failed to extract arguments from sc_data');
      }
      
      _scData = argMatch.group(1)!
          .split(',')
          .map((s) => s.replaceAll("'", "").replaceAll('"', ''))
          .toList();
    } catch (e) {
      throw Exception('Comcigan initialization failed: $e');
    }
  }

  /// Searches for schools matching the keyword.
  Future<List<School>> searchSchool(String keyword) async {
    await init();

    // Convert keyword to CP949 URL hex string
    final List<int> cp949Bytes = cp949.encode(keyword);
    final String hexQuery = cp949Bytes.map((b) => '%${b.toRadixString(16).padLeft(2, '0')}').join('');

    final String url = _baseUrl! + _extractCode! + hexQuery;
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 7));
    final String body = _cleanJsonBody(_decodeBody(response.bodyBytes));
    final Map<String, dynamic> data = json.decode(body);
    final List<dynamic> rawList = data['학교검색'] ?? [];
    return rawList.map((raw) => School.fromRawList(raw)).toList();
  }

  /// Fetches raw JSON timetable data from the server.
  Future<Map<String, dynamic>> fetchTimetableRaw(int schoolCode, {int weekOffset = 0}) async {
    await init();

    final String da1 = weekOffset.toString();
    final String s7 = '${_scData![0]}$schoolCode';
    final String payload = '${s7}_${da1}_${_scData![2]}';
    final String base64Payload = base64.encode(utf8.encode(payload));

    final String path = _extractCode!.split('?')[0];
    final String url = '${_baseUrl!}$path?$base64Payload';

    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 7));
    final String body = _cleanJsonBody(_decodeBody(response.bodyBytes));
    return json.decode(body) as Map<String, dynamic>;
  }

  /// Decodes and parses raw JSON timetable data into the custom TimetableResult model.
  TimetableResult parseTimetable(Map<String, dynamic> data) {
    final String schoolName = data['학교명'] ?? '';
    final List<String> periodTimes = List<String>.from(data['일과시간'] ?? []);

    // Extract class counts per grade
    final Map<int, int> classCounts = {};
    final List<dynamic> rawClassCounts = data['학급수'] ?? [];
    for (int g = 1; g < rawClassCounts.length; g++) {
      classCounts[g] = rawClassCounts[g] as int;
    }

    final int bunri = (data['분리'] as num? ?? 100).toInt();
    final List<dynamic> teacherList = data['자료446'] ?? [];
    final List<dynamic> subjectList = data['자료492'] ?? [];

    // Parse homeroom teachers mapping
    final Map<int, Map<int, String>> homeroomTeachers = {};
    final List<dynamic> rawHomeroom = data['담임'] ?? [];
    for (int g = 1; g <= classCounts.length; g++) {
      homeroomTeachers[g] = {};
      if (g - 1 < rawHomeroom.length) {
        final List<dynamic> gradeHomeroom = rawHomeroom[g - 1] ?? [];
        for (int c = 1; c <= classCounts[g]!; c++) {
          if (c - 1 < gradeHomeroom.length) {
            final int teacherIdx = gradeHomeroom[c - 1] as int;
            if (teacherIdx < teacherList.length) {
              String name = teacherList[teacherIdx].toString().replaceAll('*', '');
              homeroomTeachers[g]![c] = name;
            }
          }
        }
      }
    }

    final List<Lesson> lessons = [];
    final dynamic rawDaily = data['자료147'];
    final dynamic rawOriginal = data['자료481'];
    final dynamic rawClassrooms = data['자료245'];
    final bool hasClassroom = (data['강의실'] ?? 0) == 1;

    for (int grade = 1; grade <= classCounts.length; grade++) {
      final int numClasses = classCounts[grade]!;
      for (int classNum = 1; classNum <= numClasses; classNum++) {
        for (int weekday = 1; weekday <= 5; weekday++) {
          for (int period = 1; period <= 8; period++) {
            int dailyVal = _getValue(rawDaily, grade, classNum, weekday, period);
            final int origVal = _getValue(rawOriginal, grade, classNum, weekday, period);

            if (dailyVal == 0) {
              // Try to find if any teacher is teaching this Grade/Class at this Weekday/Period in 자료542
              final List<dynamic>? teacherSchedules = data['자료542'] as List<dynamic>?;
              if (teacherSchedules != null) {
                for (int t = 1; t < teacherSchedules.length; t++) {
                  final int val = _getTeacherScheduleValue(teacherSchedules, t, weekday, period);
                  if (val != 0) {
                    final int sb = val ~/ 1000;
                    final int gc = (val % 1000) ~/ 100;
                    final int cc = val % 100;
                    if (gc == grade && cc == classNum) {
                      if (bunri == 100) {
                        dailyVal = t * 100 + sb;
                      } else {
                        dailyVal = sb * bunri + t;
                      }
                      break;
                    }
                  }
                }
              }
            }

            int valToDecode = dailyVal;
            bool isSelfStudy = false;

            if (dailyVal == 0) {
              // Empty slot (no class at all or holiday)
              continue;
            }

            int th, sb;
            if (valToDecode >= 10000) {
              sb = valToDecode ~/ 1000;
              th = valToDecode % 100;
            } else if (bunri == 100) {
              th = valToDecode ~/ 100;
              sb = valToDecode % 100;
            } else {
              th = valToDecode % bunri;
              sb = valToDecode ~/ bunri;
            }

            String tt = '';
            int sbForIndex = sb;
            if (bunri != 100) {
              int t = sb ~/ bunri;
              if (t >= 1 && t <= 26) {
                tt = '${String.fromCharCode(t + 64)}_';
              }
              sbForIndex = sb % bunri;
            }

            String teacherName = '';
            if (th >= 0 && th < teacherList.length) {
              teacherName = teacherList[th].toString().replaceAll('*', '');
            }

            String subjectName = '';
            if (sbForIndex >= 0 && sbForIndex < subjectList.length) {
              subjectName = subjectList[sbForIndex].toString();
            }

            if (subjectName.contains('자율') || subjectName.contains('동아리') || sbForIndex == 30 || sbForIndex == 35) {
              final hrTeacher = homeroomTeachers[grade]?[classNum];
              if (hrTeacher != null && hrTeacher.isNotEmpty) {
                teacherName = hrTeacher;
              }
            }

            // Apply split/concurrent class group codes
            if (tt.isEmpty) {
              final String groupCode = _getConcurrentGroupCode(data, grade, classNum, sbForIndex, weekday, period, bunri);
              if (groupCode.isNotEmpty) {
                subjectName = groupCode + subjectName;
              }
            } else {
              subjectName = tt + subjectName;
            }

            if (dailyVal != origVal) {
              subjectName = '$subjectName*';
            }

            String classroom = '';
            if (hasClassroom) {
              final String? roomData = _getClassroomData(rawClassrooms, grade, classNum, weekday, period);
              if (roomData != null && roomData.contains('_')) {
                final parts = roomData.split('_');
                final int? roomNum = int.tryParse(parts[0]);
                if (roomNum != null && roomNum > 0) {
                  classroom = parts[1];
                }
              }
            }

            lessons.add(Lesson(
              grade: grade,
              classNum: classNum,
              weekday: weekday,
              classTime: period,
              teacher: teacherName,
              subject: subjectName,
              classroom: classroom,
              isChanged: dailyVal != origVal,
            ));
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

  int _getValue(dynamic array, int grade, int classNum, int weekday, int period) {
    try {
      if (array == null || array is! List) return 0;
      if (grade < array.length) {
        final gradeData = array[grade];
        if (gradeData is List && classNum < gradeData.length) {
          final classData = gradeData[classNum];
          if (classData is List && weekday < classData.length) {
            final dayData = classData[weekday];
            if (dayData is List && period < dayData.length) {
              return dayData[period] as int? ?? 0;
            }
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  int _getTeacherScheduleValue(dynamic array, int teacherIdx, int weekday, int period) {
    try {
      if (array == null || array is! List) return 0;
      if (teacherIdx < array.length) {
        final teacherData = array[teacherIdx];
        if (teacherData is List && weekday < teacherData.length) {
          final dayData = teacherData[weekday];
          if (dayData is List && period < dayData.length) {
            final rawVal = dayData[period];
            if (rawVal == null) return 0;
            if (rawVal is int) return rawVal;
            if (rawVal is String) {
              final cleaned = rawVal.replaceAll('>', '').trim();
              return int.tryParse(cleaned) ?? 0;
            }
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  String? _getClassroomData(dynamic array, int grade, int classNum, int weekday, int period) {
    try {
      if (array == null || array is! List) return null;
      if (grade < array.length) {
        final gradeData = array[grade];
        if (gradeData is List && classNum < gradeData.length) {
          final classData = gradeData[classNum];
          if (classData is List && weekday < classData.length) {
            final dayData = classData[weekday];
            if (dayData is List && period < dayData.length) {
              return dayData[period]?.toString();
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String _getConcurrentGroupCode(
    Map<String, dynamic> data,
    int grade,
    int classNum,
    int subject,
    int weekday,
    int period,
    int bunri,
  ) {
    final List<dynamic>? concurrentGroups = data['동시그룹'] as List<dynamic>?;
    if (concurrentGroups == null || concurrentGroups.isEmpty) return '';

    final int count = concurrentGroups[0][0] as int;
    for (int i = 1; i <= count; i++) {
      if (i >= concurrentGroups.length) break;
      final List<dynamic> group = concurrentGroups[i] as List<dynamic>;
      final int groupSize = group[0] as int;

      for (int k = 1; k <= 2; k++) {
        bool isMatch = false;
        int groupCodeVal = 0;
        for (int j = 1; j <= groupSize; j++) {
          if (j >= group.length) break;
          final int val = group[j] as int;

          final int subject4 = val ~/ 1000;
          final int group2 = subject4 ~/ 1000;
          final int subject2 = subject4 - group2 * 1000;
          final int teacher = group2 ~/ 100;
          groupCodeVal = group2 - teacher * 100;

          final int classVal = val - subject4 * 1000;
          final int grade2 = classVal ~/ 100;
          final int classNum2 = classVal - grade2 * 100;

          final int dailyVal2 = _getValue(data['자료147'], grade2, classNum2, weekday, period);
          int subject3, teacher2;
          if (dailyVal2 >= 10000) {
            subject3 = dailyVal2 ~/ 1000;
            teacher2 = dailyVal2 % 100;
          } else if (bunri == 100) {
            teacher2 = dailyVal2 ~/ 100;
            subject3 = dailyVal2 % 100;
          } else {
            teacher2 = dailyVal2 % bunri;
            subject3 = dailyVal2 ~/ bunri;
          }

          if (k == 1) {
            if (!(subject2 == subject3 && teacher == teacher2)) {
              isMatch = false;
              break;
            }
            if (grade == grade2 && classNum == classNum2 && subject == subject2 && teacher == teacher2 && groupCodeVal > 0) {
              isMatch = true;
            }
          } else {
            if (subject2 != subject3) {
              isMatch = false;
              break;
            }
            if (grade == grade2 && classNum == classNum2 && subject == subject2 && groupCodeVal > 0) {
              isMatch = true;
            }
          }
        }
        if (isMatch) {
          final int codeAscii = groupCodeVal + 64;
          if (codeAscii >= 65 && codeAscii <= 90) {
            return '${String.fromCharCode(codeAscii)}_';
          }
        }
      }
    }
    return '';
  }

  String _decodeBody(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return cp949.decode(bytes);
    }
  }

  String _cleanJsonBody(String body) {
    final int firstBrace = body.indexOf('{');
    final int lastBrace = body.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      return body.substring(firstBrace, lastBrace + 1);
    }
    return body;
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cp949_codec/cp949_codec.dart';
import '../models/school.dart';
import '../models/lesson.dart';
import '../config/app_config.dart';

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

  /// 교사명 자동 매핑 (예: 3글자 "임채훈" 입력시 -> 컴시간 1~2글자 약칭 "임채", "채훈", "임" 자동 맵핑)
  String matchComciganTeacherName(String fullInputName) {
    final teacherAbbrs = lessons.map((l) => l.teacher.replaceAll('*', '').trim()).toSet().where((t) => t.isNotEmpty).toList();
    return matchTeacherNameFromList(fullInputName, teacherAbbrs);
  }

  /// 교사 목록(1~2글자 컴시간 약칭)과 입력된 3글자 이상 이름 사이의 최적 근접 매핑
  static String matchTeacherNameFromList(String fullInputName, List<String> teacherList) {
    final cleanInput = fullInputName.replaceAll('*', '').replaceAll('선생님', '').trim();
    if (cleanInput.isEmpty || teacherList.isEmpty) return fullInputName;

    final cleanCandidates = teacherList
        .map((t) => t.replaceAll('*', '').replaceAll('선생님', '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (cleanCandidates.isEmpty) return cleanInput;

    // 1. Exact match
    for (int i = 0; i < cleanCandidates.length; i++) {
      if (cleanCandidates[i] == cleanInput) return cleanCandidates[i];
    }

    // 2. Family name + 1st given name char (e.g. input "임채훈" -> matches "임채")
    if (cleanInput.length >= 2) {
      final prefix2 = cleanInput.substring(0, 2);
      for (int i = 0; i < cleanCandidates.length; i++) {
        if (cleanCandidates[i] == prefix2 || cleanCandidates[i].startsWith(prefix2)) {
          return cleanCandidates[i];
        }
      }
    }

    // 3. Substring match (e.g. input "박지후" contains "지후" or "박지")
    for (int i = 0; i < cleanCandidates.length; i++) {
      if (cleanInput.contains(cleanCandidates[i]) || cleanCandidates[i].contains(cleanInput)) {
        return cleanCandidates[i];
      }
    }

    // 4. Family name (1st char) match
    if (cleanInput.isNotEmpty) {
      final familyName = cleanInput.substring(0, 1);
      for (int i = 0; i < cleanCandidates.length; i++) {
        if (cleanCandidates[i].startsWith(familyName)) {
          return cleanCandidates[i];
        }
      }
    }

    return cleanInput;
  }

  /// 특별실 모드: 특정 교시에 특정 교사(약칭)가 수업하는 학급을 역추적합니다.
  Map<String, int>? findClassByTeacherAndPeriod({
    required int weekday,
    required int period,
    required String teacherAbbr,
  }) {
    if (teacherAbbr.isEmpty) return null;
    final sanitized = teacherAbbr.replaceAll('*', '').trim();
    if (sanitized.isEmpty) return null;
    final matchedTeacher = matchComciganTeacherName(sanitized);

    for (final lesson in lessons) {
      final tName = lesson.teacher.replaceAll('*', '').trim();
      if (lesson.weekday == weekday &&
          lesson.classTime == period &&
          (tName == sanitized || tName == matchedTeacher || cleanNameMatch(tName, sanitized))) {
        return {'grade': lesson.grade, 'classNum': lesson.classNum};
      }
    }
    return null;
  }

  bool cleanNameMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    return a.contains(b) || b.contains(a);
  }
}


class ComciganService {
  static const String _defaultUrl = 'http://xn--s39aj90b0nb2xw6xh.kr';
  static final Map<String, Map<String, dynamic>> _schoolConfigCache = {};

  /// Boardest Control에 등록된 학교 설정을 Firestore control_configs에서 1순위로 상시 조회합니다.
  static Future<Map<String, dynamic>> fetchSchoolConfig(String schoolId) async {
    final cleanId = schoolId.trim().toLowerCase();
    if (cleanId.isEmpty) return {};

    if (_schoolConfigCache.containsKey(cleanId)) {
      return _schoolConfigCache[cleanId]!;
    }

    // 1. Firestore control_configs 상시 조회 (소문자, 대문자)
    for (final docKey in [cleanId, cleanId.toUpperCase()]) {
      try {
        final url = Uri.parse('${AppConfig.firestoreBase}/control_configs/$docKey?key=${AppConfig.firebaseApiKey}');
        final res = await http.get(url).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          final fields = data['fields'] as Map<String, dynamic>?;
          if (fields != null) {
            final Map<String, dynamic> result = {};
            final schoolName = fields['schoolName']?['stringValue']?.toString() ??
                               fields['name']?['stringValue']?.toString() ?? '';
            final codeStr = fields['comciganCode']?['integerValue']?.toString() ??
                            fields['comciganCode']?['stringValue']?.toString() ??
                            fields['schoolCode']?['integerValue']?.toString() ??
                            fields['schoolCode']?['stringValue']?.toString() ??
                            fields['code']?['integerValue']?.toString() ??
                            fields['code']?['stringValue']?.toString() ?? '';
            final int? code = int.tryParse(codeStr);
            if (code != null && code > 0) {
              result['schoolCode'] = code;
              result['schoolName'] = schoolName.isNotEmpty ? schoolName : (cleanId == 'ydm' ? '양동중학교' : '학교');
              result['schoolId'] = cleanId;
              debugPrint('[ComciganService] 🎯 control_configs resolved: $cleanId -> $code (${result['schoolName']})');
              _schoolConfigCache[cleanId] = result;
              return result;
            }
          }
        }
      } catch (_) {}
    }

    // 2. Fallback map
    const fallbackMap = {'ydm': 44134};
    final int fallbackCode = fallbackMap[cleanId] ?? int.tryParse(cleanId) ?? 44134;
    final fallbackResult = {
      'schoolCode': fallbackCode,
      'schoolName': cleanId == 'ydm' ? '양동중학교' : '학교',
      'schoolId': cleanId,
    };
    _schoolConfigCache[cleanId] = fallbackResult;
    return fallbackResult;
  }

  /// schoolId를 컴시간 숫자 코드로 상시 변환
  static Future<int> fetchCode(String schoolId) async {
    final config = await fetchSchoolConfig(schoolId);
    return config['schoolCode'] as int? ?? 44134;
  }
  
  String? _baseUrl;
  String? _extractCode;
  List<String>? _scData;

  String? get baseUrl => _baseUrl;
  String? get extractCode => _extractCode;
  List<String>? get scData => _scData;

  /// Initializes the session parameters by fetching the Comcigan landing frame.
  Future<void> init() async {
    if (kIsWeb) return;
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
    if (kIsWeb) {
      final workerUrl = Uri.parse('https://comcigan.jiwho.workers.dev/api/comcigan/search?school=${Uri.encodeQueryComponent(keyword)}');
      final response = await http.get(workerUrl).timeout(const Duration(seconds: 7));
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonMap = json.decode(utf8.decode(response.bodyBytes));
        final List<dynamic> rawList = jsonMap['schools'] ?? [];
        return rawList.map((item) {
          final int rCode = (item['regionCode'] is num)
              ? (item['regionCode'] as num).toInt()
              : int.tryParse(item['regionCode']?.toString() ?? '0') ?? 0;
          final int sCode = (item['code'] is num)
              ? (item['code'] as num).toInt()
              : int.tryParse(item['code']?.toString() ?? '0') ?? 0;
          return School(
            id: rCode,
            region: item['region']?.toString() ?? '',
            name: item['name']?.toString() ?? '',
            code: sCode,
          );
        }).toList();
      }
      return [];
    }

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
    // 1. Cloudflare Worker API 우선 시도 (Web & Desktop 공통 고속/안정)
    try {
      final workerUrl = Uri.parse('https://comcigan.jiwho.workers.dev/api/comcigan/lookup?code=$schoolCode&offset=$weekOffset');
      final response = await http.get(workerUrl).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final String bodyStr = response.body.isNotEmpty ? response.body : utf8.decode(response.bodyBytes);
        final Map<String, dynamic> jsonMap = json.decode(bodyStr);
        final Map<String, dynamic> data = jsonMap['data'] ?? {};
        final Map<String, dynamic> rawJson = Map<String, dynamic>.from(data['rawJson'] ?? {});

        final normalized = <String, dynamic>{};
        if (data['parsed'] != null && data['parsed'] is Map) {
          normalized['__parsed__'] = data['parsed'];
        }
        rawJson.forEach((k, v) {
          if (k.contains('147')) normalized['자료147'] = v;
          else if (k.contains('446')) normalized['자료446'] = v;
          else if (k.contains('492')) normalized['자료492'] = v;
          else if (k.contains('481')) normalized['자료481'] = v;
          else if (k.contains('542')) normalized['자료542'] = v;
          else if (k.contains('245')) normalized['자료245'] = v;
          else if (k.contains('학급수') || (v is List && v.length == 4 && v[1] is num)) normalized['학급수'] = v;
          else if (k.contains('분리') || v == 100 || v == 1000) normalized['분리'] = v;
          else if (k.contains('일과시간') || (v is List && v.isNotEmpty && v.first.toString().contains('('))) normalized['일과시간'] = v;
          else if (k.contains('학교명')) normalized['학교명'] = v;
          else normalized[k] = v;
        });
        if (normalized.isNotEmpty) return normalized;
      }
    } catch (e) {
      debugPrint('[ComciganService] Worker lookup fallback: $e');
    }

    if (kIsWeb) {
      throw Exception('Cloudflare Worker request failed on Web platform.');
    }

    // 2. Desktop 네이티브 컴시간 직접 파싱 (Fallback)
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

  /// Fetches the list of teacher names for the specified school.
  Future<List<String>> getTeachers(int schoolCode) async {
    try {
      final raw = await fetchTimetableRaw(schoolCode);
      final List<dynamic> teacherListRaw = raw['자료446'] ?? [];
      final List<String> teachers = [];
      for (int i = 1; i < teacherListRaw.length; i++) {
        final name = _fixMojibake(teacherListRaw[i].toString()).replaceAll('*', '').trim();
        if (name.isNotEmpty && !teachers.contains(name)) {
          teachers.add(name);
        }
      }
      teachers.sort();
      return teachers;
    } catch (e) {
      return [];
    }
  }

  Future<TimetableResult> getTimetable(int schoolCode) async {
    final raw = await fetchTimetableRaw(schoolCode);
    return parseTimetable(raw);
  }

  /// Decodes and parses raw JSON timetable data into the custom TimetableResult model.
  TimetableResult parseTimetable(Map<String, dynamic> data) {
    if (data.containsKey('__parsed__') && data['__parsed__'] is Map) {
      try {
        final parsedMap = Map<String, dynamic>.from(data['__parsed__'] as Map);
        final List<dynamic> rawLessons = parsedMap['lessons'] ?? [];
        final List<Lesson> parsedLessons = rawLessons.map((item) => Lesson.fromJson(Map<String, dynamic>.from(item as Map))).toList();
        
        final Map<int, int> classCounts = {};
        final rawCounts = parsedMap['classCounts'] as Map<String, dynamic>? ?? {};
        rawCounts.forEach((k, v) {
          final g = int.tryParse(k);
          if (g != null) classCounts[g] = (v as num?)?.toInt() ?? 0;
        });

        final List<String> periodTimes = (parsedMap['periodTimes'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        final String schoolName = _fixMojibake(parsedMap['schoolName']?.toString() ?? '');

        return TimetableResult(
          schoolName: schoolName,
          periodTimes: periodTimes,
          classCounts: classCounts,
          lessons: parsedLessons,
          homeroomTeachers: {},
        );
      } catch (e) {
        debugPrint('[Comcigan] Error parsing pre-parsed timetable: $e');
      }
    }

    final String schoolName = _fixMojibake(data['학교명'] ?? '');
    final List<String> periodTimes = List<String>.from(data['일과시간'] ?? []);

    // Extract class counts per grade
    final Map<int, int> classCounts = {};
    final List<dynamic> rawClassCounts = data['학급수'] ?? [];
    for (int g = 1; g < rawClassCounts.length; g++) {
      classCounts[g] = (rawClassCounts[g] as num?)?.toInt() ?? 0;
    }

    final int bunri = (data['분리'] as num? ?? 100).toInt();
    final List<dynamic> rawTeacherList = data['자료446'] ?? [];
    final List<String> teacherList = rawTeacherList.map((t) => _fixMojibake(t.toString())).toList();
    final List<dynamic> rawSubjectList = data['자료492'] ?? [];
    final List<String> subjectList = rawSubjectList.map((s) => _fixMojibake(s.toString())).toList();

    // Parse homeroom teachers mapping
    final Map<int, Map<int, String>> homeroomTeachers = {};
    final List<dynamic> rawHomeroom = data['담임'] ?? [];
    for (int g = 1; g <= classCounts.length; g++) {
      homeroomTeachers[g] = {};
      if (g - 1 < rawHomeroom.length) {
        final List<dynamic> gradeHomeroom = (rawHomeroom[g - 1] as List<dynamic>?) ?? [];
        for (int c = 1; c <= (classCounts[g] ?? 0); c++) {
          if (c - 1 < gradeHomeroom.length) {
            final int teacherIdx = (gradeHomeroom[c - 1] as num?)?.toInt() ?? 0;
            if (teacherIdx >= 0 && teacherIdx < teacherList.length) {
              String name = teacherList[teacherIdx].replaceAll('*', '');
              (homeroomTeachers[g] ??= {})[c] = _fixMojibake(name);
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

    for (int grade = 1; grade <= (classCounts.isEmpty ? 3 : classCounts.length); grade++) {
      final int numClasses = classCounts[grade] ?? (grade < rawClassCounts.length ? (rawClassCounts[grade] as num?)?.toInt() ?? 10 : 10);
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

            if (dailyVal == 0) {
              if (origVal != 0) {
                dailyVal = origVal;
              }
            }

            int valToDecode = dailyVal;
            bool isSelfStudy = false;

            if (dailyVal == 0) {
              // Empty slot (no class at all)
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
              final raw = dayData[period];
              if (raw == null) return 0;
              if (raw is num) return raw.toInt();
              if (raw is String) return int.tryParse(raw.replaceAll('>', '').trim()) ?? 0;
              return 0;
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
            if (rawVal is num) return rawVal.toInt();
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
    try {
      final List<dynamic>? concurrentGroups = data['동시그룹'] as List<dynamic>?;
      if (concurrentGroups == null || concurrentGroups.isEmpty) return '';

      final int count = (concurrentGroups[0][0] as num?)?.toInt() ?? 0;
      for (int i = 1; i <= count; i++) {
        if (i >= concurrentGroups.length) break;
        final dynamic groupRaw = concurrentGroups[i];
        if (groupRaw is! List || groupRaw.isEmpty) continue;
        final int groupSize = (groupRaw[0] as num?)?.toInt() ?? 0;

        for (int k = 1; k <= 2; k++) {
          bool isMatch = false;
          int groupCodeVal = 0;
          for (int j = 1; j <= groupSize; j++) {
            if (j >= groupRaw.length) break;
            final int val = (groupRaw[j] as num?)?.toInt() ?? 0;

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
    } catch (_) {}
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

  String _fixMojibake(String input) {
    if (input.isEmpty) return input;
    try {
      final bytes = cp949.encode(input);
      final fixed = utf8.decode(bytes, allowMalformed: false);
      if (fixed.isNotEmpty && !fixed.contains('\uFFFD')) {
        return fixed;
      }
    } catch (_) {}
    return input;
  }
}

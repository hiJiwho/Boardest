import '../models/app_settings.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cp949_codec/cp949_codec.dart';
import '../models/school.dart';
import '../models/lesson.dart';
import '../config/app_config.dart';
import 'storage_service.dart';

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

  /// 데모 전용 시간표 생성 (교실 9개: 1-1~1-3, 2-1~2-3, 3-1~3-3 / 교사 9명 / 하루 안에서 교사 수업 절대 안 겹치게 완전 순환)
  static TimetableResult generateDemo(String teacherName, {int homeroomGrade = 1, int homeroomClass = 1}) {
    final effectiveName = teacherName.isNotEmpty ? teacherName : '김윤리';

    final teachers = [
      '김윤리',       // 0: 도덕 (01 계정 기본 교사)
      '이도형',       // 1: 수학 (02 계정 기본 교사)
      '박영어',       // 2: 영어
      '최과학',       // 3: 과학
      '정사회',       // 4: 사회
      '강역사',       // 5: 역사
      '송음악',       // 6: 음악
      '윤체육',       // 7: 체육
      '조미술',       // 8: 미술
    ];

    final subjects = ['도덕', '수학', '영어', '과학', '사회', '역사', '음악', '체육', '미술'];

    int targetSlot = 0;
    if (effectiveName.contains('수학') || effectiveName == '이수학' || effectiveName == '이도형') {
      targetSlot = 1;
    } else if (effectiveName.contains('영어') || effectiveName == '박영어') {
      targetSlot = 2;
    } else if (effectiveName.contains('과학') || effectiveName == '최과학') {
      targetSlot = 3;
    } else if (effectiveName.contains('사회') || effectiveName == '정사회') {
      targetSlot = 4;
    } else if (effectiveName.contains('역사') || effectiveName == '강역사') {
      targetSlot = 5;
    } else if (effectiveName.contains('음악') || effectiveName == '송음악') {
      targetSlot = 6;
    } else if (effectiveName.contains('체육') || effectiveName == '윤체육') {
      targetSlot = 7;
    } else if (effectiveName.contains('미술') || effectiveName == '조미술') {
      targetSlot = 8;
    } else {
      targetSlot = 0;
    }
    teachers[targetSlot] = effectiveName;

    // 9개 학급: 1학년 1~3반, 2학년 1~3반, 3학년 1~3반
    final classList = <({int grade, int classNum})>[
      (grade: 1, classNum: 1),
      (grade: 1, classNum: 2),
      (grade: 1, classNum: 3),
      (grade: 2, classNum: 1),
      (grade: 2, classNum: 2),
      (grade: 2, classNum: 3),
      (grade: 3, classNum: 1),
      (grade: 3, classNum: 2),
      (grade: 3, classNum: 3),
    ];

    final lessons = <Lesson>[];

    // 라틴 방진 순환: 어떤 요일, 어떤 교시에서도 9개 반에 9명의 교사가 정확히 1:1로 들어가 하루 동안 절대 겹치지 않음!
    for (int day = 1; day <= 7; day++) {
      for (int p = 1; p <= 7; p++) {
        for (int k = 0; k < classList.length; k++) {
          final cInfo = classList[k];
          final tIdx = (k + (p - 1) + (day - 1) * 2) % 9;
          lessons.add(Lesson(
            grade: cInfo.grade,
            classNum: cInfo.classNum,
            weekday: day,
            classTime: p,
            teacher: teachers[tIdx],
            subject: subjects[tIdx],
            classroom: '${cInfo.grade}-${cInfo.classNum}',
            isChanged: false,
          ));
        }
      }
    }

    final homeroomMap = {
      1: {1: teachers[0], 2: teachers[1], 3: teachers[2]},
      2: {1: teachers[3], 2: teachers[4], 3: teachers[5]},
      3: {1: teachers[6], 2: teachers[7], 3: teachers[8]},
    };

    return TimetableResult(
      schoolName: '데모 중학교',
      periodTimes: ['09:00', '09:50', '10:40', '11:30', '12:20', '13:50', '14:40'],
      classCounts: {1: 3, 2: 3, 3: 3},
      lessons: lessons,
      homeroomTeachers: homeroomMap,
    );
  }

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

    // 4. Family name (1st char) match ONLY when Comcigan entry itself is 1 character
    if (cleanInput.isNotEmpty) {
      final familyName = cleanInput.substring(0, 1);
      for (int i = 0; i < cleanCandidates.length; i++) {
        if (cleanCandidates[i] == familyName) {
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

  /// 컴시간 '일과시간' 데이터로부터 학교 실제 교시별 시정표(TimeSettings)를 정밀 파싱합니다.
  static TimeSettings? parseTimeSettingsFromPeriodTimes(
    List<String> periodTimes, {
    TimeSettings? currentSettings,
  }) {
    if (periodTimes.isEmpty) return null;

    final parsedTimes = <int, String>{}; // period -> "HH:mm"
    final timeMinutes = <int, int>{}; // period -> total minutes

    final timeReg = RegExp(r'(0[7-9]|1[0-9]|20)\s*[:시]\s*([0-5]\d)');
    final prefixReg = RegExp(r'^(\d{1,2})\s*[\(교시:]');
    final parenReg = RegExp(r'[\(\[]\s*(\d{1,2})\s*[\)\]]');

    for (int i = 0; i < periodTimes.length; i++) {
      final raw = periodTimes[i].trim();
      final timeMatch = timeReg.firstMatch(raw);
      if (timeMatch != null) {
        final h = int.tryParse(timeMatch.group(1)!) ?? 0;
        final m = int.tryParse(timeMatch.group(2)!) ?? 0;
        final timeStr = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

        int period = i + 1;
        final prefixMatch = prefixReg.firstMatch(raw);
        if (prefixMatch != null) {
          final p = int.tryParse(prefixMatch.group(1)!);
          if (p != null && p >= 1 && p <= 12) period = p;
        } else {
          final parenMatch = parenReg.firstMatch(raw);
          if (parenMatch != null) {
            final p = int.tryParse(parenMatch.group(1)!);
            if (p != null && p >= 1 && p <= 12) period = p;
          }
        }

        parsedTimes[period] = timeStr;
        timeMinutes[period] = h * 60 + m;
      }
    }

    if (parsedTimes.isEmpty) return null;

    final sortedPeriods = parsedTimes.keys.toList()..sort();
    final firstP = sortedPeriods.first;
    final firstStartStr = parsedTimes[firstP]!;
    final firstMin = timeMinutes[firstP]!;

    // 연속된 교시간의 간격(interval) 계산
    final intervals = <int>[];
    int lunchAfterPeriod = currentSettings?.lunchAfterPeriod ?? 4;
    int maxGap = 0;

    for (int idx = 0; idx < sortedPeriods.length - 1; idx++) {
      final p1 = sortedPeriods[idx];
      final p2 = sortedPeriods[idx + 1];
      if (p2 == p1 + 1) {
        final gap = timeMinutes[p2]! - timeMinutes[p1]!;
        if (gap > 0 && gap < 180) {
          intervals.add(gap);
          if (gap > maxGap && gap >= 70) {
            maxGap = gap;
            lunchAfterPeriod = p1;
          }
        }
      }
    }

    // 일반 수업+쉬는시간 단위 결정 (예: 50, 55, 또는 60분)
    int standardInterval = 55;
    if (intervals.isNotEmpty) {
      final normalIntervals = intervals.where((g) => g < 75).toList();
      if (normalIntervals.isNotEmpty) {
        normalIntervals.sort();
        standardInterval = normalIntervals[normalIntervals.length ~/ 2];
      }
    }

    int lessonDur = (standardInterval - 10).clamp(40, 50);
    int breakDur = 10;
    int lunchDur = currentSettings?.lunchDuration ?? 50;

    if (maxGap >= 70) {
      lunchDur = (maxGap - lessonDur).clamp(40, 90);
    }

    // 조회: 1교시 시작 15분 전
    final morningMin = firstMin - 15;
    final mH = (morningMin ~/ 60).clamp(0, 23);
    final mM = (morningMin % 60).clamp(0, 59);
    final morningStartStr = '${mH.toString().padLeft(2, '0')}:${mM.toString().padLeft(2, '0')}';

    final periodStartTimesList = <String>[];
    for (int p = 1; p <= (sortedPeriods.last.clamp(1, 10)); p++) {
      if (parsedTimes.containsKey(p)) {
        periodStartTimesList.add(parsedTimes[p]!);
      } else {
        periodStartTimesList.add('');
      }
    }

    return TimeSettings(
      lessonDuration: lessonDur,
      breakDuration: breakDur,
      lunchDuration: lunchDur,
      lunchAfterPeriod: lunchAfterPeriod,
      firstPeriodStart: firstStartStr,
      morningAssemblyStart: morningStartStr,
      morningAssemblyEnd: firstStartStr,
      afternoonAssemblyStart: currentSettings?.afternoonAssemblyStart ?? '16:10',
      afternoonAssemblyEnd: currentSettings?.afternoonAssemblyEnd ?? '16:30',
      afternoonAssemblyAfterMinutes: currentSettings?.afternoonAssemblyAfterMinutes ?? 10,
      afternoonAssemblyDuration: currentSettings?.afternoonAssemblyDuration ?? 20,
      periodStartTimes: periodStartTimesList,
    );
  }

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
              result['schoolName'] = schoolName.isNotEmpty ? schoolName : (cleanId == 'ydm' ? '보데스트 중학교' : '보데스트 중학교');
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
    const fallbackMap = {'ydm': 44134, 'demo': 44134, '44134': 44134};
    final int fallbackCode = fallbackMap[cleanId] ?? int.tryParse(cleanId) ?? 44134;
    final fallbackName = (cleanId == 'ydm') ? '양동중학교' : '데모중학교';
    final fallbackResult = {
      'schoolCode': fallbackCode,
      'schoolName': fallbackName,
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
  String? _hourToken;
  String? _sessionCookie;
  String _route = '941645';
  String _searchPrefix = '99604l';
  String _scPrefix = '106958_';
  String _aesKeyHex = '4eb6d28336f50bca3799179b2cd4ead31ec882bd32cdd12018840a2911a33db6';

  String? get baseUrl => _baseUrl;
  String? get extractCode => _extractCode;
  List<String>? get scData => _scData;

  /// 메모리 캐시를 초기화합니다.
  static void clearCache({int? schoolCode}) {
    if (schoolCode != null) {
      _inMemoryTimetableCache.remove(schoolCode);
    } else {
      _inMemoryTimetableCache.clear();
      _schoolConfigCache.clear();
    }
  }

  Map<String, String> _buildComciganHeaders() {
    final headers = <String, String>{
      'Referer': '${_baseUrl ?? 'http://comci.net:4082'}/st',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Accept': '*/*',
    };
    if (_hourToken != null && _hourToken!.isNotEmpty) {
      headers['X-Hour-Token'] = _hourToken!;
    }
    if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
      headers['Cookie'] = _sessionCookie!;
    }
    return headers;
  }

  /// Deobfuscates Comcigan's 2026 `hour-obfuscated-v2` and `hour-ajax-obfuscated-v1` scripts.
  static String _deobfuscateHourJs(String html) {
    final blockRe = RegExp(
      r'\/\* hour-[a-z0-9-]+ \*\/\(function\(a,k\)\{[\s\S]*?\}\)\((\[\[[\s\S]*?\]\]),\s*(\d+)\);',
    );
    String current = html;
    final decodedBlocks = <String>[];
    for (int depth = 0; depth < 4; depth++) {
      final matches = blockRe.allMatches(current).toList();
      if (matches.isEmpty) break;
      final nextLayer = StringBuffer();
      for (final m in matches) {
        try {
          final arr = json.decode(m.group(1)!) as List<dynamic>;
          final k = int.parse(m.group(2)!);
          final sb = StringBuffer();
          for (int i = 0; i < arr.length; i++) {
            final item = arr[i] as List<dynamic>;
            final flag = (item[0] as num).toInt();
            final s = item[1].toString();
            if (flag != 0) {
              sb.write(s);
            } else {
              for (int j = 0; j < s.length; j += 4) {
                final hexVal = int.parse(s.substring(j, j + 4), radix: 16);
                final code = hexVal ^ ((k + (j ~/ 4) * 13) & 255);
                sb.writeCharCode(code);
              }
            }
          }
          final decoded = sb.toString();
          decodedBlocks.add(decoded);
          nextLayer.writeln(decoded);
        } catch (_) {}
      }
      current = nextLayer.toString();
    }
    return decodedBlocks.join('\n');
  }

  /// Initializes the session parameters by fetching the Comcigan landing frame.
  Future<void> init({bool force = false}) async {
    if (kIsWeb) return;
    if (!force && _baseUrl != null && (_hourToken != null || _extractCode != null)) return;
    try {
      Uri resolvedUri = Uri.parse('http://comci.net:4082/st');
      try {
        final response = await http.get(Uri.parse(_defaultUrl)).timeout(const Duration(seconds: 5));
        String html;
        try {
          html = utf8.decode(response.bodyBytes);
        } catch (_) {
          html = cp949.decode(response.bodyBytes);
        }
        final RegExp frameRegExp = RegExp(r"""<frame\s+[^>]*src=["']([^"']+)["']""", caseSensitive: false);
        final match = frameRegExp.firstMatch(html);
        if (match != null) {
          resolvedUri = Uri.parse(_defaultUrl).resolve(match.group(1)!);
        }
      } catch (_) {}

      _baseUrl = '${resolvedUri.scheme}://${resolvedUri.host}:${resolvedUri.port}';

      final frameResponse = await http.get(resolvedUri).timeout(const Duration(seconds: 7));
      final setCookie = frameResponse.headers['set-cookie'];
      if (setCookie != null && setCookie.isNotEmpty) {
        _sessionCookie = setCookie.split(';').first.trim();
      }

      String frameHtml;
      try {
        frameHtml = cp949.decode(frameResponse.bodyBytes);
      } catch (_) {
        frameHtml = utf8.decode(frameResponse.bodyBytes, allowMalformed: true);
      }

      final tokenMatch = RegExp(r"window\.__HourRequestToken\s*=\s*'([^']+)'").firstMatch(frameHtml);
      if (tokenMatch != null) {
        _hourToken = tokenMatch.group(1)!;
      }

      final deobfuscated = _deobfuscateHourJs(frameHtml);
      final combinedJs = '$frameHtml\n$deobfuscated';

      final routeMatch = RegExp(r"url\s*:\s*'\.\/(\d+)\?'").firstMatch(combinedJs);
      if (routeMatch != null) {
        _route = routeMatch.group(1)!;
      }

      final searchPrefixMatch = RegExp(r"btoa\('(\d+l)'").firstMatch(combinedJs);
      if (searchPrefixMatch != null) {
        _searchPrefix = searchPrefixMatch.group(1)!;
      }

      final scPrefixMatch = RegExp(r"sc_data\('(\d+_)'").firstMatch(combinedJs);
      if (scPrefixMatch != null) {
        _scPrefix = scPrefixMatch.group(1)!;
      }

      final keyPartsMatch = RegExp(r"\['([0-9a-f]{16})','([0-9a-f]{16})','([0-9a-f]{16})','([0-9a-f]{16})'\]").firstMatch(combinedJs);
      if (keyPartsMatch != null) {
        _aesKeyHex = '${keyPartsMatch.group(3)!}${keyPartsMatch.group(2)!}${keyPartsMatch.group(4)!}${keyPartsMatch.group(1)!}';
      }

      _extractCode = '/$_route?$_searchPrefix';
      _scData = [_scPrefix, '0', '1', '0'];
    } catch (e) {
      debugPrint('[ComciganService] Comcigan init warning: $e');
      _baseUrl ??= 'http://comci.net:4082';
      _extractCode ??= '/$_route?$_searchPrefix';
      _scData ??= [_scPrefix, '0', '1', '0'];
    }
  }

  String _decryptPayloadIfNeeded(String rawBody) {
    final trimmed = rawBody.trim();
    if (trimmed.startsWith('enc5:') || trimmed.startsWith('enc1:')) {
      final parts = trimmed.split(':');
      if (parts.length >= 3) {
        final ivBytes = base64.decode(parts[1]);
        final cipherBytes = base64.decode(parts[2]);
        final keyBytes = _ComciganAes256.hexToBytes(_aesKeyHex);
        final decryptedBytes = _ComciganAes256.decryptCbc(cipherBytes, keyBytes, ivBytes);
        return utf8.decode(decryptedBytes, allowMalformed: true).replaceAll('\x00', '').trim();
      }
    }
    return _cleanJsonBody(trimmed);
  }

  static Map<String, dynamic> _normalizeComciganMap(Map<String, dynamic> rawJson) {
    final normalized = <String, dynamic>{};
    rawJson.forEach((k, v) {
      if (k == '자료147' || k == '자료146' || k.contains('147') || k.contains('146')) {
        normalized['자료147'] = v;
      } else if (k == '자료446' || k == '자료131' || k.contains('446') || k.contains('131')) {
        normalized['자료446'] = v;
      } else if (k == '자료492' || k == '자료133' || k.contains('492') || k.contains('133')) {
        normalized['자료492'] = v;
      } else if (k == '자료481' || k == '자료115' || k.contains('481') || k.contains('115')) {
        normalized['자료481'] = v;
      } else if (k == '자료542' || k == '자료140' || k.contains('542') || k.contains('140')) {
        normalized['자료542'] = v;
      } else if (k == '자료245' || k == '자료160' || k.contains('245') || k.contains('160')) {
        normalized['자료245'] = v;
      } else if (k == '학급수' || (!rawJson.containsKey('학급수') && !normalized.containsKey('학급수') && k.contains('학급수') && !k.contains('가상'))) {
        normalized['학급수'] = v;
      } else if (k.contains('분리') || v == 100 || v == 1000) {
        normalized['분리'] = v;
      } else if (k.contains('일과시간') || (v is List && v.isNotEmpty && v.first.toString().contains('('))) {
        normalized['일과시간'] = v;
      } else if (k.contains('학교명')) {
        normalized['학교명'] = v;
      }
      normalized[k] = v;
    });
    return normalized;
  }

  /// Searches for schools matching the keyword.
  Future<List<School>> searchSchool(String keyword) async {
    final cleanKeyword = keyword.trim();
    if (cleanKeyword.isEmpty) return [];

    if (!kIsWeb) {
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          await init(force: attempt > 0);
          final encodedKeyword = Uri.encodeComponent(cleanKeyword);
          final queryPayload = '$_searchPrefix${encodedKeyword}_enc5';
          final b64Query = Uri.encodeComponent(base64.encode(utf8.encode(queryPayload)));
          final url = '${_baseUrl!}/$_route?$b64Query';

          final response = await http
              .get(Uri.parse(url), headers: _buildComciganHeaders())
              .timeout(const Duration(seconds: 7));
          if (response.statusCode == 200) {
            final rawText = _decodeBody(response.bodyBytes);
            final decrypted = _decryptPayloadIfNeeded(rawText);
            final Map<String, dynamic> data = json.decode(_cleanJsonBody(decrypted));
            final List<dynamic> rawList = data['학교검색'] ?? [];
            final schools = rawList.map((raw) => School.fromRawList(raw)).toList();
            for (final s in schools) {
              if (s.code > 0 && s.name.isNotEmpty) {
                _knownSchoolNames[s.code] = s.name;
              }
            }
            return schools;
          }
        } catch (e) {
          debugPrint('[ComciganService] searchSchool attempt ${attempt + 1} error: $e');
        }
      }
    }

    // Fallback to Cloudflare Worker if on Web or direct failed
    try {
      final workerUrl = Uri.parse('https://comcigan.jiwho.workers.dev/api/comcigan/search?school=${Uri.encodeQueryComponent(cleanKeyword)}');
      final response = await http.get(workerUrl).timeout(const Duration(seconds: 7));
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonMap = json.decode(utf8.decode(response.bodyBytes));
        final List<dynamic> rawList = jsonMap['schools'] ?? jsonMap['results'] ?? [];
        return rawList.map((item) => School.fromRawList(item)).toList();
      }
    } catch (e) {
      debugPrint('[ComciganService] Worker searchSchool fallback error: $e');
    }
    return [];
  }

  static final Map<int, Map<String, dynamic>> _inMemoryTimetableCache = {};
  static final Map<int, String> _knownSchoolNames = {};

  /// Fetches raw JSON timetable data from the server with offline local caching.
  Future<Map<String, dynamic>> fetchTimetableRaw(int schoolCode, {int weekOffset = 0}) async {
    // 1. Desktop / Mobile 네이티브 컴시간 2026 enc5 프로토콜 직접 조회 (1순위)
    if (!kIsWeb) {
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          await init(force: attempt > 0);
          final int rWeek = weekOffset + 1;
          final String payload = '$_scPrefix${schoolCode}_0_${rWeek}_enc5';
          final String base64Payload = base64.encode(utf8.encode(payload));
          final String url = '${_baseUrl!}/$_route?$base64Payload';

          final response = await http
              .get(Uri.parse(url), headers: _buildComciganHeaders())
              .timeout(const Duration(seconds: 7));
          if (response.statusCode == 200) {
            final String rawText = _decodeBody(response.bodyBytes);
            final String decrypted = _decryptPayloadIfNeeded(rawText);
            final decoded = json.decode(_cleanJsonBody(decrypted)) as Map<String, dynamic>;
            final normalized = _normalizeComciganMap(decoded);
            final currentSchoolName = (normalized['학교명'] ?? '').toString();
            if ((currentSchoolName.isEmpty || currentSchoolName.startsWith('컴시간')) &&
                _knownSchoolNames.containsKey(schoolCode)) {
              normalized['학교명'] = _knownSchoolNames[schoolCode]!;
            }
            if (normalized.containsKey('자료147') || normalized.containsKey('자료446') || normalized.containsKey('학교명')) {
              _inMemoryTimetableCache[schoolCode] = normalized;
              try {
                StorageService().saveCachedTimetable(schoolCode, normalized);
              } catch (_) {}
              return normalized;
            }
          }
        } catch (e) {
          debugPrint('[ComciganService] Direct enc5 fetch attempt ${attempt + 1} failed: $e');
        }
      }
    }

    // 2. Cloudflare Worker API 시도 (Web 및 보조 폴백)
    try {
      final workerUrl = Uri.parse('https://comcigan.jiwho.workers.dev/api/comcigan/lookup?code=$schoolCode&offset=$weekOffset');
      final response = await http.get(workerUrl).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final String bodyStr = response.body.isNotEmpty ? response.body : utf8.decode(response.bodyBytes);
        final Map<String, dynamic> jsonMap = json.decode(bodyStr);
        final Map<String, dynamic> data = jsonMap['data'] ?? {};
        final Map<String, dynamic> rawJson = Map<String, dynamic>.from(data['rawJson'] ?? {});

        final normalized = _normalizeComciganMap(rawJson);
        if (data['parsed'] != null && data['parsed'] is Map) {
          normalized['__parsed__'] = data['parsed'];
        }
        if (normalized.isNotEmpty && (normalized.containsKey('자료147') || normalized.containsKey('__parsed__'))) {
          _inMemoryTimetableCache[schoolCode] = normalized;
          try {
            StorageService().saveCachedTimetable(schoolCode, normalized);
          } catch (_) {}
          return normalized;
        }
      }
    } catch (e) {
      debugPrint('[ComciganService] Worker lookup fallback: $e');
    }

    // 3. OFFLINE CACHE FALLBACK
    if (_inMemoryTimetableCache.containsKey(schoolCode)) {
      debugPrint('[ComciganService] Returning in-memory cached timetable for $schoolCode');
      return _inMemoryTimetableCache[schoolCode]!;
    }

    try {
      final diskCached = await StorageService().getCachedTimetable(schoolCode);
      if (diskCached != null) {
        final normalized = _normalizeComciganMap(diskCached);
        debugPrint('[ComciganService] Returning disk-cached timetable for $schoolCode');
        _inMemoryTimetableCache[schoolCode] = normalized;
        return normalized;
      }
    } catch (_) {}

    return {'학교명': 'School_$schoolCode'};
  }

  /// Fetches the list of teacher names for the specified school.
  Future<List<String>> getTeachers(int schoolCode) async {
    try {
      final raw = await fetchTimetableRaw(schoolCode);
      final List<dynamic> teacherListRaw = raw['자료446'] ?? raw['자료131'] ?? [];
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
    try {
      final raw = await fetchTimetableRaw(schoolCode);
      final result = parseTimetable(raw);
      if (result.lessons.isNotEmpty) {
        return result;
      }
    } catch (e) {
      debugPrint('[ComciganService] getTimetable online fetch error: $e');
    }

    // Disk cache fallback for offline teacher
    try {
      final diskCached = await StorageService().getCachedTimetable(schoolCode);
      if (diskCached != null) {
        final result = parseTimetable(_normalizeComciganMap(diskCached));
        if (result.lessons.isNotEmpty) {
          debugPrint('[ComciganService] ✅ Loaded timetable from offline cache');
          return result;
        }
      }
    } catch (_) {}

    // Safe demo fallback to prevent blank or crash
    debugPrint('[ComciganService] ⚠️ Returning fallback demo timetable');
    return TimetableResult.generateDemo('');
  }

  /// Decodes and parses raw JSON timetable data into the custom TimetableResult model.
  TimetableResult parseTimetable(Map<String, dynamic> rawInput) {
    final data = _normalizeComciganMap(rawInput);
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
    List<String> periodTimes = [];
    if (data['일과시간'] != null && data['일과시간'] is List) {
      periodTimes = (data['일과시간'] as List).map((e) => e.toString()).toList();
    } else {
      for (final entry in data.entries) {
        if (entry.key.contains('일과시간') && entry.value is List) {
          periodTimes = (entry.value as List).map((e) => e.toString()).toList();
          break;
        }
      }
    }

    // Extract class counts per grade
    final Map<int, int> classCounts = {};
    final List<dynamic> rawClassCounts = data['학급수'] ?? [];
    for (int g = 1; g < rawClassCounts.length; g++) {
      classCounts[g] = (rawClassCounts[g] as num?)?.toInt() ?? 0;
    }

    final int bunri = (data['분리'] as num? ?? 100).toInt();
    final List<dynamic> rawTeacherList = data['자료446'] ?? data['자료131'] ?? [];
    final List<String> teacherList = rawTeacherList.map((t) => _fixMojibake(t.toString())).toList();
    final List<dynamic> rawSubjectList = data['자료492'] ?? data['자료133'] ?? [];
    final List<String> subjectList = rawSubjectList.map((s) => _fixMojibake(s.toString())).toList();

    // Parse homeroom teachers mapping
    final Map<int, Map<int, String>> homeroomTeachers = {};
    final List<dynamic> rawHomeroom = data['담임'] ?? [];
    for (int g = 1; g <= classCounts.length; g++) {
      homeroomTeachers[g] = {};
      if (g - 1 < rawHomeroom.length) {
        final List<dynamic> gradeHomeroom = (rawHomeroom[g - 1] is List ? rawHomeroom[g - 1] as List<dynamic> : (g < rawHomeroom.length && rawHomeroom[g] is List ? rawHomeroom[g] as List<dynamic> : []));
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
    final dynamic rawDaily = data['자료147'] ?? data['자료146'];
    final dynamic rawOriginal = data['자료481'] ?? data['자료115'];
    final dynamic rawClassrooms = data['자료245'] ?? data['자료160'];
    final bool hasClassroom = (data['강의실'] ?? 0) == 1;

    for (int grade = 1; grade <= (classCounts.isEmpty ? 3 : classCounts.length); grade++) {
      final int numClasses = classCounts[grade] ?? (grade < rawClassCounts.length ? (rawClassCounts[grade] as num?)?.toInt() ?? 10 : 10);
      for (int classNum = 1; classNum <= numClasses; classNum++) {
        for (int weekday = 1; weekday <= 7; weekday++) {
          for (int period = 1; period <= 8; period++) {
            int dailyVal = _getValue(rawDaily, grade, classNum, weekday, period);
            final int origVal = _getValue(rawOriginal, grade, classNum, weekday, period);

            if (dailyVal == 0) {
              // Try to find if any teacher is teaching this Grade/Class at this Weekday/Period in 자료542
              final List<dynamic>? teacherSchedules = (data['자료542'] ?? data['자료140']) as List<dynamic>?;
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

            if (dailyVal == 0) {
              // Empty slot (no class at all)
              continue;
            }

            int th, sb;
            if (bunri == 100) {
              if (valToDecode >= 10000) {
                sb = valToDecode ~/ 1000;
                th = valToDecode % 100;
              } else {
                th = valToDecode ~/ 100;
                sb = valToDecode % 100;
              }
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

            if (teacherName.isEmpty || subjectName.contains('자율') || subjectName.contains('동아리') || sbForIndex == 30 || sbForIndex == 35) {
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

            if (dailyVal != origVal && origVal != 0) {
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
              isChanged: dailyVal != origVal && origVal != 0,
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

            final int dailyVal2 = _getValue(data['자료147'] ?? data['자료146'], grade2, classNum2, weekday, period);
            int subject3, teacher2;
            if (bunri == 100) {
              if (dailyVal2 >= 10000) {
                subject3 = dailyVal2 ~/ 1000;
                teacher2 = dailyVal2 % 100;
              } else {
                teacher2 = dailyVal2 ~/ 100;
                subject3 = dailyVal2 % 100;
              }
            } else {
              teacher2 = dailyVal2 % bunri;
              subject3 = (dailyVal2 ~/ bunri) % bunri;
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

/// Pure-Dart AES-256-CBC decryptor for Comcigan 2026 `enc5` / `enc1` payloads.
class _ComciganAes256 {
  static const List<int> _sBox = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ];

  static const List<int> _invSBox = [
    0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
    0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
    0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
    0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
    0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
    0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
    0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
    0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
    0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
    0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
    0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
    0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
    0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
    0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
    0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
    0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d,
  ];

  static const List<int> _rCon = [
    0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36,
  ];

  static Uint8List hexToBytes(String hex) {
    final clean = hex.trim();
    final out = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static int _gmul(int a, int b) {
    int p = 0;
    int aa = a;
    int bb = b;
    for (int i = 0; i < 8; i++) {
      if ((bb & 1) != 0) p ^= aa;
      final hiBit = (aa & 0x80) != 0;
      aa = (aa << 1) & 0xff;
      if (hiBit) aa ^= 0x1b;
      bb >>= 1;
    }
    return p;
  }

  static Uint8List _expandKey256(Uint8List key) {
    final w = Uint8List(240);
    for (int i = 0; i < 32; i++) {
      w[i] = key[i];
    }
    final temp = Uint8List(4);
    for (int i = 8; i < 60; i++) {
      final prevOffset = (i - 1) * 4;
      temp[0] = w[prevOffset];
      temp[1] = w[prevOffset + 1];
      temp[2] = w[prevOffset + 2];
      temp[3] = w[prevOffset + 3];

      if (i % 8 == 0) {
        final t = temp[0];
        temp[0] = _sBox[temp[1]] ^ _rCon[i ~/ 8];
        temp[1] = _sBox[temp[2]];
        temp[2] = _sBox[temp[3]];
        temp[3] = _sBox[t];
      } else if (i % 8 == 4) {
        temp[0] = _sBox[temp[0]];
        temp[1] = _sBox[temp[1]];
        temp[2] = _sBox[temp[2]];
        temp[3] = _sBox[temp[3]];
      }

      final curOffset = i * 4;
      final backOffset = (i - 8) * 4;
      w[curOffset] = w[backOffset] ^ temp[0];
      w[curOffset + 1] = w[backOffset + 1] ^ temp[1];
      w[curOffset + 2] = w[backOffset + 2] ^ temp[2];
      w[curOffset + 3] = w[backOffset + 3] ^ temp[3];
    }
    return w;
  }

  static void _addRoundKey(Uint8List state, Uint8List roundKeys, int round) {
    final offset = round * 16;
    for (int i = 0; i < 16; i++) {
      state[i] ^= roundKeys[offset + i];
    }
  }

  static void _invShiftRows(Uint8List s) {
    // Row 1: shift right by 1
    int t = s[13];
    s[13] = s[9];
    s[9] = s[5];
    s[5] = s[1];
    s[1] = t;
    // Row 2: shift right by 2
    t = s[2];
    s[2] = s[10];
    s[10] = t;
    t = s[6];
    s[6] = s[14];
    s[14] = t;
    // Row 3: shift right by 3 (left by 1)
    t = s[3];
    s[3] = s[7];
    s[7] = s[11];
    s[11] = s[15];
    s[15] = t;
  }

  static void _invSubBytes(Uint8List s) {
    for (int i = 0; i < 16; i++) {
      s[i] = _invSBox[s[i]];
    }
  }

  static void _invMixColumns(Uint8List s) {
    for (int c = 0; c < 4; c++) {
      final idx = c * 4;
      final s0 = s[idx];
      final s1 = s[idx + 1];
      final s2 = s[idx + 2];
      final s3 = s[idx + 3];
      s[idx] = _gmul(s0, 0x0e) ^ _gmul(s1, 0x0b) ^ _gmul(s2, 0x0d) ^ _gmul(s3, 0x09);
      s[idx + 1] = _gmul(s0, 0x09) ^ _gmul(s1, 0x0e) ^ _gmul(s2, 0x0b) ^ _gmul(s3, 0x0d);
      s[idx + 2] = _gmul(s0, 0x0d) ^ _gmul(s1, 0x09) ^ _gmul(s2, 0x0e) ^ _gmul(s3, 0x0b);
      s[idx + 3] = _gmul(s0, 0x0b) ^ _gmul(s1, 0x0d) ^ _gmul(s2, 0x09) ^ _gmul(s3, 0x0e);
    }
  }

  static Uint8List decryptCbc(List<int> cipherBytes, Uint8List key, List<int> iv) {
    final roundKeys = _expandKey256(key);
    final out = Uint8List(cipherBytes.length);
    final block = Uint8List(16);
    List<int> prevBlock = iv;

    for (int offset = 0; offset + 16 <= cipherBytes.length; offset += 16) {
      for (int i = 0; i < 16; i++) {
        block[i] = cipherBytes[offset + i];
      }
      _addRoundKey(block, roundKeys, 14);
      for (int round = 13; round >= 1; round--) {
        _invShiftRows(block);
        _invSubBytes(block);
        _addRoundKey(block, roundKeys, round);
        _invMixColumns(block);
      }
      _invShiftRows(block);
      _invSubBytes(block);
      _addRoundKey(block, roundKeys, 0);

      for (int i = 0; i < 16; i++) {
        out[offset + i] = block[i] ^ prevBlock[i];
      }
      prevBlock = cipherBytes.sublist(offset, offset + 16);
    }

    if (out.isEmpty) return out;
    final padLen = out.last;
    if (padLen >= 1 && padLen <= 16 && padLen <= out.length) {
      bool validPad = true;
      for (int i = out.length - padLen; i < out.length; i++) {
        if (out[i] != padLen) {
          validPad = false;
          break;
        }
      }
      if (validPad) {
        return Uint8List.sublistView(out, 0, out.length - padLen);
      }
    }
    return out;
  }
}

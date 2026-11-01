import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bst_core/bst_core.dart';

class NeisService {
  final http.Client _client;
  final String _baseUrl = 'https://open.neis.go.kr/hub';
  final String? apiKey;

  NeisService({http.Client? client, this.apiKey}) : _client = client ?? http.Client();

  /// 학사일정 API 호출
  Future<dynamic> fetchSchoolSchedule({
    required String atptOfcdcScCode,
    required String sdSchulCode,
    String? aaYmd,
    String? aaFromYmd,
    String? aaToYmd,
  }) async {
    final queryParams = <String, String>{
      'Type': 'json',
      'ATPT_OFCDC_SC_CODE': atptOfcdcScCode,
      'SD_SCHUL_CODE': sdSchulCode,
    };
    if (apiKey != null) {
      queryParams['KEY'] = apiKey!;
    }
    if (aaYmd != null) {
      queryParams['AA_YMD'] = aaYmd;
    }
    if (aaFromYmd != null) {
      queryParams['AA_FROM_YMD'] = aaFromYmd;
    }
    if (aaToYmd != null) {
      queryParams['AA_TO_YMD'] = aaToYmd;
    }

    final uri = Uri.parse('$_baseUrl/SchoolSchedule').replace(queryParameters: queryParams);
    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch NEIS schedule');
    }
  }

  /// 급식 API 호출
  Future<dynamic> fetchMealServiceDietInfo({
    required String atptOfcdcScCode,
    required String sdSchulCode,
    String? mlsvYmd,
    String? mlsvFromYmd,
    String? mlsvToYmd,
  }) async {
    final queryParams = <String, String>{
      'Type': 'json',
      'ATPT_OFCDC_SC_CODE': atptOfcdcScCode,
      'SD_SCHUL_CODE': sdSchulCode,
    };
    if (apiKey != null) {
      queryParams['KEY'] = apiKey!;
    }
    if (mlsvYmd != null) {
      queryParams['MLSV_YMD'] = mlsvYmd;
    }
    if (mlsvFromYmd != null) {
      queryParams['MLSV_FROM_YMD'] = mlsvFromYmd;
    }
    if (mlsvToYmd != null) {
      queryParams['MLSV_TO_YMD'] = mlsvToYmd;
    }

    final uri = Uri.parse('$_baseUrl/mealServiceDietInfo').replace(queryParameters: queryParams);
    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch NEIS meal service diet info');
    }
  }

  /// NEIS 시간표 API 호출 (elsTimetable, misTimetable, hisTimetable, spsTimetable)
  /// [schoolType]: 'els' (초등), 'mis' (중등), 'his' (고등), 'sps' (특수). 기본값: 'his'
  Future<dynamic> fetchTimetable({
    required String atptOfcdcScCode,
    required String sdSchulCode,
    String schoolType = 'his',
    int? grade,
    int? classNm,
    String? tiYmd,
    String? tiFromYmd,
    String? tiToYmd,
    int pIndex = 1,
    int pSize = 100,
  }) async {
    final queryParams = <String, String>{
      'Type': 'json',
      'pIndex': pIndex.toString(),
      'pSize': pSize.toString(),
      'ATPT_OFCDC_SC_CODE': atptOfcdcScCode,
      'SD_SCHUL_CODE': sdSchulCode,
    };
    if (apiKey != null) {
      queryParams['KEY'] = apiKey!;
    }
    if (grade != null) {
      queryParams['GRADE'] = grade.toString();
    }
    if (classNm != null) {
      queryParams['CLASS_NM'] = classNm.toString();
    }
    if (tiYmd != null) {
      queryParams['ALL_TI_YMD'] = tiYmd;
    }
    if (tiFromYmd != null) {
      queryParams['TI_FROM_YMD'] = tiFromYmd;
    }
    if (tiToYmd != null) {
      queryParams['TI_TO_YMD'] = tiToYmd;
    }

    final endpoint = '${schoolType.toLowerCase()}Timetable';
    final uri = Uri.parse('$_baseUrl/$endpoint').replace(queryParameters: queryParams);
    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch NEIS timetable for $endpoint');
    }
  }

  /// Parse NEIS timetable response to list of Lesson objects
  static List<Lesson> parseNeisTimetable(dynamic jsonResponse, {String schoolType = 'his'}) {
    final lessons = <Lesson>[];
    if (jsonResponse is! Map<String, dynamic>) {
      return lessons;
    }

    final key = '${schoolType.toLowerCase()}Timetable';
    final tableData = jsonResponse[key];
    if (tableData is! List || tableData.length < 2) {
      return lessons;
    }

    final rows = (tableData[1] as Map)['row'];
    if (rows is! List) {
      return lessons;
    }

    for (final row in rows) {
      if (row is! Map) {
        continue;
      }
      final grade = int.tryParse(row['GRADE']?.toString() ?? '') ?? 1;
      final classNum = int.tryParse(row['CLASS_NM']?.toString() ?? '') ?? 1;
      final classTime = int.tryParse(row['PERIO']?.toString() ?? '') ?? 1;
      final ymd = row['ALL_TI_YMD']?.toString() ?? '';

      // Calculate weekday from ALL_TI_YMD (YYYYMMDD) if available
      int weekday = 1;
      if (ymd.length == 8) {
        final year = int.tryParse(ymd.substring(0, 4)) ?? 2026;
        final month = int.tryParse(ymd.substring(4, 6)) ?? 1;
        final day = int.tryParse(ymd.substring(6, 8)) ?? 1;
        weekday = DateTime(year, month, day).weekday;
      }

      final subject = row['ITRT_CNTNT']?.toString() ?? '';
      final classroom = '$grade-$classNum';

      if (subject.isNotEmpty) {
        lessons.add(Lesson(
          grade: grade,
          classNum: classNum,
          weekday: weekday,
          classTime: classTime,
          teacher: '',
          subject: subject,
          classroom: classroom,
          isChanged: false,
        ));
      }
    }

    return lessons;
  }
}

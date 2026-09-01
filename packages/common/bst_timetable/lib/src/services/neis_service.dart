import 'dart:convert';
import 'package:http/http.dart' as http;

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
      if (apiKey != null) 'KEY': apiKey!,
      'Type': 'json',
      'ATPT_OFCDC_SC_CODE': atptOfcdcScCode,
      'SD_SCHUL_CODE': sdSchulCode,
      if (aaYmd != null) 'AA_YMD': aaYmd,
      if (aaFromYmd != null) 'AA_FROM_YMD': aaFromYmd,
      if (aaToYmd != null) 'AA_TO_YMD': aaToYmd,
    };

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
      if (apiKey != null) 'KEY': apiKey!,
      'Type': 'json',
      'ATPT_OFCDC_SC_CODE': atptOfcdcScCode,
      'SD_SCHUL_CODE': sdSchulCode,
      if (mlsvYmd != null) 'MLSV_YMD': mlsvYmd,
      if (mlsvFromYmd != null) 'MLSV_FROM_YMD': mlsvFromYmd,
      if (mlsvToYmd != null) 'MLSV_TO_YMD': mlsvToYmd,
    };

    final uri = Uri.parse('$_baseUrl/mealServiceDietInfo').replace(queryParameters: queryParams);
    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch NEIS meal service diet info');
    }
  }
}

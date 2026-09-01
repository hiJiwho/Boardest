import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('Debug SchoolSchedule API directly', () async {
    // 1. Resolve school code for 양동중학교
    final schoolName = '양동중학교';
    final apiKey = '821179541cf54b6288d51741f30e1c90';
    
    final queryUrl = Uri.parse(
      'https://open.neis.go.kr/hub/schoolInfo'
      '?KEY=$apiKey'
      '&Type=json'
      '&pIndex=1'
      '&pSize=5'
      '&SCHUL_NM=${Uri.encodeComponent(schoolName)}',
    );

    final res = await http.get(queryUrl);
    final data = json.decode(res.body);
    final firstRow = data['schoolInfo'][1]['row'][0];
    final officeCode = firstRow['ATPT_OFCDC_SC_CODE'] as String;
    final schoolCode = firstRow['SD_SCHUL_CODE'] as String;
    
    print('Office Code: $officeCode, School Code: $schoolCode');
    
    // 2. Fetch schedule
    final fromDateStr = '20260522';
    final toDateStr = '20270522';
    
    final scheduleUrl = Uri.parse(
      'https://open.neis.go.kr/hub/SchoolSchedule'
      '?KEY=$apiKey'
      '&Type=json'
      '&ATPT_OFCDC_SC_CODE=$officeCode'
      '&SD_SCHUL_CODE=$schoolCode'
      '&AA_FROM_YMD=$fromDateStr'
      '&AA_TO_YMD=$toDateStr'
      '&pIndex=1'
      '&pSize=100',
    );
    
    final sRes = await http.get(scheduleUrl);
    print('Response status: ${sRes.statusCode}');
    print('Response body: ${sRes.body}');
  });
}

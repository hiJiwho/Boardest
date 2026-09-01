import 'package:flutter_test/flutter_test.dart';
import 'package:boardest/services/comcigan_service.dart';

void main() {
  test('Test Comcigan Service and Parser', () async {
    final service = ComciganService();
    
    print('\n======================================');
    print('1. Initializing Comcigan session...');
    await service.init();
    print('   Base URL: ${service.baseUrl}');
    print('   Extract Code: ${service.extractCode}');
    print('   scData: ${service.scData}');
    
    expect(service.baseUrl, isNotNull);
    expect(service.extractCode, isNotNull);
    expect(service.scData, isNotEmpty);

    print('\n2. Searching school "광명북고"...');
    final schools = await service.searchSchool('광명북고');
    print('   Found ${schools.length} schools.');
    for (var s in schools) {
      print('   - $s');
    }
    expect(schools, isNotEmpty);
    
    final targetSchool = schools.firstWhere((s) => s.name.contains('광명북고등학교'));
    expect(targetSchool.code, equals(36854));

    print('\n3. Fetching raw timetable data for ${targetSchool.name} (${targetSchool.code})...');
    final rawData = await service.fetchTimetableRaw(targetSchool.code);
    expect(rawData, isNotEmpty);
    expect(rawData['학교명'], isNotNull);
    print('   Raw timetable data size: ${rawData.toString().length} chars');

    print('\n4. Decoding and parsing timetable data...');
    final result = service.parseTimetable(rawData);
    print('   School Name in Data: ${result.schoolName}');
    print('   Periods: ${result.periodTimes}');
    print('   Class Counts per Grade: ${result.classCounts}');
    print('   Total Lessons Parsed: ${result.lessons.length}');
    
    expect(result.schoolName, isNotEmpty);
    expect(result.lessons, isNotEmpty);

    print('\n5. Sampling first few lessons:');
    result.lessons.take(10).forEach((l) => print('   - $l'));
    
    print('======================================\n');
  });
}

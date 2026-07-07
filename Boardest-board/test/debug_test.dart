import 'package:flutter_test/flutter_test.dart';
import 'package:boardest/services/comcigan_service.dart';

void main() {
  test('Debug Yangdong Middle School Comcigan parser', () async {
    final service = ComciganService();
    
    print('Searching "양동중학교"...');
    final schools = await service.searchSchool('양동중');
    print('Found schools:');
    for (final s in schools) {
      print(' - ${s.name} (Code: ${s.code}, Region: ${s.region})');
    }

    if (schools.isEmpty) {
      print('No schools found!');
      return;
    }

    for (final targetSchool in schools) {
      print('====================================');
      print('Testing school: ${targetSchool.name} (${targetSchool.code}, Region: ${targetSchool.region})');
      try {
        print('Fetching raw timetable...');
        final rawData = await service.fetchTimetableRaw(targetSchool.code);
        print('Raw data keys: ${rawData.keys.toList()}');
        print('Raw data school name: ${rawData['학교명']}');
        
        print('Parsing timetable...');
        final result = service.parseTimetable(rawData);
        print('Parsing complete! Subject count: ${result.lessons.length}');
      } catch (e, stack) {
        print('Error occurred: $e');
        print('Stacktrace: $stack');
      }
    }
  });
}

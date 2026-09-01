import 'package:flutter_test/flutter_test.dart';
import 'package:boardest/services/neis_service.dart';

void main() {
  test('Verify NeisService for 양동중', () async {
    final service = NeisService();
    
    print('--- Fetching school schedule for 양동중 ---');
    final schedule = await service.fetchSchoolSchedule('양동중', DateTime.now());
    print('Schedule count: ${schedule.length}');
    for (var event in schedule.take(10)) {
      print('Event: ${event['title']} on ${event['date']}');
    }

    print('--- Fetching meal for 양동중 ---');
    final meal = await service.fetchTodayMeal('양동중', DateTime.now());
    print('Meal:\n$meal');
  });
}

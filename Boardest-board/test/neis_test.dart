import 'package:flutter_test/flutter_test.dart';
import 'package:boardest/services/neis_service.dart';

void main() {
  test('Test NeisService fetches and cleans school meals', () async {
    final neis = NeisService();

    // Fetch lunch for 광명북고등학교 on a standard school weekday, e.g. 2026-05-20 (Wednesday)
    final date = DateTime(2026, 5, 20);
    final meal = await neis.fetchTodayMeal('광명북고등학교', date);

    print('Fetched Meal for 광명북고등학교 (2026-05-20):\n$meal');

    // Asserts
    expect(meal, isNotEmpty);
    expect(meal.contains('<br/>'), isFalse);
    expect(meal.contains(RegExp(r'\(\d+\)')), isFalse); // allergy indexes stripped
  });
}

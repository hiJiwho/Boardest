import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:boardest_teacher/models/meal_models.dart';
import 'package:boardest_teacher/services/neis_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MealDayInfo NEIS Allergy Parsing (1~19)', () {
    test('Correctly parses all 19 allergy codes from NEIS DDISH_NM format', () {
      final rawNeisMenu = '''
친환경 흑미밥
소고기 된장찌개 (5.6.16.)
수제 떡갈비구이 (10.5.6.)
골뱅이 야채무침 (18.)
왕새우튀김 (9.6.)
꽃게탕 (8.)
견과류 샐러드 (4.14.19.)
치즈 계란말이 (1.2.)
고등어 무조림 (7.)
닭강정 (15.6.)
오징어 볶음 (17.)
메밀소바 (3.6.)
복숭아 젤리 (11.)
방울토마토 (12.)
건포도 브레드 (6.13.)
''';

      final date = DateTime(2026, 11, 2);
      final info = MealDayInfo.fromNeisRaw(date, rawNeisMenu, calories: '750 kcal');

      expect(info.dishes.length, 15);
      expect(info.calories, '750 kcal');

      // Check specific dish allergy matches
      final beefSoup = info.dishes.firstWhere((d) => d.name.contains('소고기 된장찌개'));
      expect(beefSoup.allergyCodes, containsAll([5, 6, 16]));
      expect(beefSoup.allergies, containsAll(['대두', '밀', '소고기']));
      expect(beefSoup.matchesAllergy(16), isTrue); // 소고기
      expect(beefSoup.matchesAllergy(5), isTrue);  // 대두
      expect(beefSoup.matchesAllergy(6), isTrue);  // 밀
      expect(beefSoup.matchesAllergy(1), isFalse); // 난류

      // Check Crab (8: 게) and Shrimp (9: 새우)
      final shrimp = info.dishes.firstWhere((d) => d.name.contains('왕새우튀김'));
      expect(shrimp.allergyCodes, contains(9));
      expect(shrimp.allergies, contains('새우'));
      expect(shrimp.matchesAllergy(9), isTrue);
      expect(shrimp.matchesAllergy('새우'), isTrue);

      final crab = info.dishes.firstWhere((d) => d.name.contains('꽃게탕'));
      expect(crab.allergyCodes, contains(8));
      expect(crab.allergies, contains('게'));
      expect(crab.matchesAllergy(8), isTrue);
      expect(crab.matchesAllergy('게'), isTrue);

      // Check Nuts (4: 땅콩, 14: 호두, 19: 잣)
      final nuts = info.dishes.firstWhere((d) => d.name.contains('견과류 샐러드'));
      expect(nuts.allergyCodes, containsAll([4, 14, 19]));
      expect(nuts.matchesAllergy(4), isTrue);
      expect(nuts.matchesAllergy(14), isTrue);
      expect(nuts.matchesAllergy(19), isTrue);

      // Check Egg & Milk (1: 난류, 2: 우유)
      final eggRoll = info.dishes.firstWhere((d) => d.name.contains('치즈 계란말이'));
      expect(eggRoll.allergyCodes, containsAll([1, 2]));
      expect(eggRoll.matchesAllergy(1), isTrue);
      expect(eggRoll.matchesAllergy(2), isTrue);

      // Check all 19 allergy indexes registered
      final allIndexes = info.allAllergyIndexes;
      for (int i = 1; i <= 19; i++) {
        expect(allIndexes.contains(i), isTrue, reason: 'Allergy code $i must be detected');
      }
    });

    test('Handles edge cases in allergy regex (spaces, asterisks, trailing dots)', () {
      const raw = '마카로니 샐러드 ( 1. 2. 6.* )<br/>과일주스(11, 12.)';
      final info = MealDayInfo.fromNeisRaw(DateTime(2026, 11, 3), raw);

      expect(info.dishes.length, 2);
      final salad = info.dishes[0];
      expect(salad.name, '마카로니 샐러드');
      expect(salad.allergyCodes, containsAll([1, 2, 6]));

      final juice = info.dishes[1];
      expect(juice.name, '과일주스');
      expect(juice.allergyCodes, containsAll([11, 12]));
    });

    test('MealDayInfo JSON serialization and deserialization for offline storage', () {
      final date = DateTime(2026, 11, 4);
      final original = MealDayInfo(
        date: date,
        dishes: [
          MealDishItem(name: '카레라이스', allergies: ['돼지', '대두', '밀'], allergyCodes: [10, 5, 6]),
          MealDishItem(name: '배추김치'),
          MealDishItem(name: '유기농 사과주스'),
        ],
        calories: '680 kcal',
        footnotes: ['! (돼지) : 돼지고기 알레르기 조심'],
      );

      final jsonMap = original.toJson();
      final restored = MealDayInfo.fromJson(jsonMap);

      expect(restored.dishes.length, 3);
      expect(restored.dishes[0].name, '카레라이스');
      expect(restored.dishes[0].allergies, ['돼지', '대두', '밀']);
      expect(restored.dishes[0].allergyCodes, [10, 5, 6]);
      expect(restored.dishes[0].matchesAllergy(10), isTrue);
      expect(restored.calories, '680 kcal');
      expect(restored.hasAllergy(10), isTrue);
      expect(restored.hasAllergy(1), isFalse);
    });
  });

  group('NeisService Offline Monthly Meal Cache', () {
    test('Loads and restores cached monthly meal data from SharedPreferences when offline', () async {
      final year = 2026;
      final month = 11;
      const schoolName = '테스트중학교';
      final cacheKey = '$schoolName-$year-$month';

      final sampleMonthlyData = {
        '1': MealDayInfo(
          date: DateTime(year, month, 1),
          dishes: [
            MealDishItem(name: '쇠고기 볶음밥', allergies: ['소고기', '난류'], allergyCodes: [16, 1]),
            MealDishItem(name: '콩나물국', allergies: ['대두'], allergyCodes: [5]),
          ],
          calories: '650 kcal',
        ).toJson(),
        '2': MealDayInfo(
          date: DateTime(year, month, 2),
          dishes: [
            MealDishItem(name: '등심 돈까스', allergies: ['돼지', '밀', '난류'], allergyCodes: [10, 6, 1]),
          ],
          calories: '720 kcal',
        ).toJson(),
      };

      // Set up mocked SharedPreferences with pre-cached monthly meals
      SharedPreferences.setMockInitialValues({
        'bst_month_meals_$cacheKey': json.encode(sampleMonthlyData),
      });

      final neis = NeisService();
      final meals = await neis.fetchMonthMeals(schoolName, year, month);

      expect(meals.isNotEmpty, isTrue);
      expect(meals.containsKey(1), isTrue);
      expect(meals.containsKey(2), isTrue);

      final day1 = meals[1]!;
      expect(day1.dishes.length, 2);
      expect(day1.dishes[0].name, '쇠고기 볶음밥');
      expect(day1.dishes[0].matchesAllergy(16), isTrue);
      expect(day1.dishes[0].matchesAllergy(1), isTrue);

      final day2 = meals[2]!;
      expect(day2.dishes[0].name, '등심 돈까스');
      expect(day2.hasAllergy(10), isTrue);
      expect(day2.hasAllergy(8), isFalse);
    });
  });
}

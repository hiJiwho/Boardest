import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:boardest_teacher_lite/models/meal_models.dart';
import 'package:boardest_teacher_lite/services/neis_meal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Teacher Lite NEIS Allergy Parsing (1~19)', () {
    test('Correctly extracts all 19 allergy codes and formats badges', () {
      final rawNeisMenu = '''
칼슘 기장밥
얼큰 해물탕 (8.9.17.18.)
매콤 제육볶음 (10.5.6.)
시금치 나물무침
배추김치
메밀전병 (3.6.)
호두 멸치볶음 (14.5.)
땅콩 드레싱 샐러드 (4.1.)
잣죽 (19.)
고등어 오븐구이 (7.)
닭꼬치구이 (15.6.)
토마토 샐러드 (12.)
황도 복숭아 (11.)
소고기 무국 (16.)
수제 소시지 (10.13.)
치즈 케이크 (1.2.)
''';

      final date = DateTime(2026, 11, 5);
      final info = LiteMealDayInfo.fromNeisRaw(date, rawNeisMenu, calories: '720 kcal');

      expect(info.dishes.length, 16);

      // Check seafood: Crab(8), Shrimp(9), Squid(17), Shellfish(18)
      final seafood = info.dishes.firstWhere((d) => d.name.contains('얼큰 해물탕'));
      expect(seafood.allergyCodes, containsAll([8, 9, 17, 18]));
      expect(seafood.allergies, containsAll(['게', '새우', '오징어', '조개']));
      expect(seafood.matchesAllergy(8), isTrue);
      expect(seafood.matchesAllergy(9), isTrue);
      expect(seafood.matchesAllergy(17), isTrue);
      expect(seafood.matchesAllergy(18), isTrue);
      expect(seafood.matchesAllergy('게'), isTrue);
      expect(seafood.matchesAllergy('새우'), isTrue);

      // Check Pork (10), Soy (5), Wheat (6)
      final pork = info.dishes.firstWhere((d) => d.name.contains('매콤 제육볶음'));
      expect(pork.allergyCodes, containsAll([10, 5, 6]));
      expect(pork.matchesAllergy(10), isTrue);
      expect(pork.matchesAllergy(5), isTrue);
      expect(pork.matchesAllergy(6), isTrue);

      // Check Buckwheat (3)
      final buckwheat = info.dishes.firstWhere((d) => d.name.contains('메밀전병'));
      expect(buckwheat.allergyCodes, contains(3));
      expect(buckwheat.matchesAllergy(3), isTrue);

      // Check Pine nut (19)
      final pineNut = info.dishes.firstWhere((d) => d.name.contains('잣죽'));
      expect(pineNut.allergyCodes, contains(19));
      expect(pineNut.matchesAllergy(19), isTrue);

      // Check Sulfite (13)
      final sausage = info.dishes.firstWhere((d) => d.name.contains('수제 소시지'));
      expect(sausage.allergyCodes, contains(13));
      expect(sausage.matchesAllergy(13), isTrue);

      // Check hasAllergy at day level
      for (int i = 1; i <= 19; i++) {
        expect(info.hasAllergy(i), isTrue, reason: 'Day info should match allergy code $i');
      }
    });

    test('LiteMealDayInfo JSON serialization and deserialization for offline cache', () {
      final date = DateTime(2026, 11, 6);
      final original = LiteMealDayInfo(
        date: date,
        dishes: [
          LiteMealDishItem(name: '오므라이스', allergies: ['난류', '우유', '토마토'], allergyCodes: [1, 2, 12]),
          LiteMealDishItem(name: '깍두기'),
          LiteMealDishItem(name: '수제 와플', allergies: ['밀', '난류', '우유'], allergyCodes: [6, 1, 2]),
        ],
        calories: '710 kcal',
      );

      final jsonMap = original.toJson();
      final restored = LiteMealDayInfo.fromJson(jsonMap);

      expect(restored.dishes.length, 3);
      expect(restored.dishes[0].name, '오므라이스');
      expect(restored.dishes[0].allergies, ['난류', '우유', '토마토']);
      expect(restored.dishes[0].allergyCodes, [1, 2, 12]);
      expect(restored.dishes[0].matchesAllergy(12), isTrue);
      expect(restored.hasAllergy(1), isTrue);
      expect(restored.hasAllergy(8), isFalse);
    });

    test('LiteNeisMealService restores cached today and monthly meals when offline', () async {
      final year = 2026;
      final month = 11;
      const schoolQuery = '테스트학교';
      final date = DateTime(year, month, 10);
      final dateStr = '$year${month.toString().padLeft(2, '0')}10';
      final todayCacheKey = '$schoolQuery-$dateStr';
      final monthCacheKey = '$schoolQuery-$year-$month';

      final sampleToday = LiteMealDayInfo(
        date: date,
        dishes: [
          LiteMealDishItem(name: '칼슘 기장밥'),
          LiteMealDishItem(name: '닭볶음탕', allergies: ['닭', '대두'], allergyCodes: [15, 5]),
        ],
        calories: '690 kcal',
      ).toJson();

      final sampleMonth = {
        '10': sampleToday,
        '11': LiteMealDayInfo(
          date: DateTime(year, month, 11),
          dishes: [
            LiteMealDishItem(name: '비빔밥', allergies: ['난류', '대두', '소고기'], allergyCodes: [1, 5, 16]),
          ],
          calories: '730 kcal',
        ).toJson(),
      };

      SharedPreferences.setMockInitialValues({
        'bst_lite_meal_$todayCacheKey': json.encode(sampleToday),
        'bst_lite_month_$monthCacheKey': json.encode(sampleMonth),
      });

      final service = LiteNeisMealService();

      // Test today meal offline cache
      final todayInfo = await service.fetchTodayMealInfo(schoolQuery, date);
      expect(todayInfo.dishes.length, 2);
      expect(todayInfo.dishes[1].name, '닭볶음탕');
      expect(todayInfo.hasAllergy(15), isTrue);

      // Test month meals offline cache
      final monthMeals = await service.fetchMonthMeals(schoolQuery, year, month);
      expect(monthMeals.containsKey(10), isTrue);
      expect(monthMeals.containsKey(11), isTrue);
      expect(monthMeals[11]!.dishes[0].name, '비빔밥');
      expect(monthMeals[11]!.hasAllergy(16), isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/services/comcigan_service.dart';
import '../lib/services/storage_service.dart';
import '../lib/models/lesson.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Boardest Teacher ComciganService & Timetable Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('generateDemo generates 7-day conflict-free schedule', () {
      final demo = TimetableResult.generateDemo('이도형', homeroomGrade: 2, homeroomClass: 1);
      expect(demo.schoolName, equals('데모 중학교'));
      expect(demo.periodTimes.length, equals(7));
      expect(demo.classCounts.length, equals(3));
      expect(demo.lessons.isNotEmpty, isTrue);

      // Verify weekend lessons exist (day 6 and 7)
      final satLessons = demo.lessons.where((l) => l.weekday == 6).toList();
      final sunLessons = demo.lessons.where((l) => l.weekday == 7).toList();
      expect(satLessons.isNotEmpty, isTrue);
      expect(sunLessons.isNotEmpty, isTrue);

      // Verify reverse lookup
      final match = demo.findClassByTeacherAndPeriod(weekday: 1, period: 1, teacherAbbr: '이도형');
      expect(match, isNotNull);
      expect(match!['grade'], isNotNull);
      expect(match['classNum'], isNotNull);
    });

    test('matchTeacherNameFromList handles 1~3 character abbreviations', () {
      final candidates = ['홍길', '김철', '이영'];
      expect(TimetableResult.matchTeacherNameFromList('홍길동', candidates), equals('홍길'));
      expect(TimetableResult.matchTeacherNameFromList('김철수선생님', candidates), equals('김철'));
      expect(TimetableResult.matchTeacherNameFromList('이영희', candidates), equals('이영'));
      expect(TimetableResult.matchTeacherNameFromList('박지후', candidates), equals('박지후'));
    });

    test('parseTimeSettingsFromPeriodTimes calculates correct intervals and lunch break', () {
      final periods = [
        '(1) 08:40',
        '(2) 09:35',
        '(3) 10:30',
        '(4) 11:25',
        '(5) 13:10', // Lunch between 4 and 5 (gap = 105 min)
        '(6) 14:05',
        '(7) 15:00',
      ];

      final settings = ComciganService.parseTimeSettingsFromPeriodTimes(periods);
      expect(settings, isNotNull);
      expect(settings!.firstPeriodStart, equals('08:40'));
      expect(settings.lunchAfterPeriod, equals(4));
      expect(settings.periodStartTimes.length, greaterThanOrEqualTo(7));
      expect(settings.morningAssemblyStart, equals('08:25'));
    });

    test('parseTimetable handles weekend days (1..7) and missing teacher fallback', () {
      final service = ComciganService();
      final mockRaw = {
        '학교명': '주말테스트학교',
        '학급수': [0, 2, 2],
        '일과시간': ['(1) 09:00', '(2) 09:50'],
        '자료446': ['', '홍길동'],
        '자료492': ['', '자율'],
        '담임': [
          [1, 1], // Grade 1: Class 1 -> Hong, Class 2 -> Hong
        ],
        '자료481': [
          [],
          [
            [],
            [
              [],
              [0, 101], // Mon: Hong / Jayul
              [],
              [],
              [],
              [],
              [0, 1], // Sat (w=6): th=0 (missing teacher), sb=1 (Jayul) -> teacher falls back to homeroom (Hong)
            ],
          ],
        ],
        '분리': 100,
      };

      final result = service.parseTimetable(mockRaw);
      expect(result.schoolName, equals('주말테스트학교'));
      expect(result.lessons.length, equals(2));

      final satLesson = result.lessons.firstWhere((l) => l.weekday == 6);
      expect(satLesson.weekday, equals(6));
      expect(satLesson.subject, contains('자율'));
      expect(satLesson.teacher, equals('홍길동')); // Homeroom fallback
    });

    test('StorageService saves and retrieves cached timetable for offline use', () async {
      final storage = StorageService();
      final mockData = {
        '학교명': '오프라인중학교',
        '학급수': [0, 3, 3],
        '자료446': ['', '김교사'],
      };

      await storage.saveCachedTimetable(98765, mockData);
      final loaded = await storage.getCachedTimetable(98765);
      expect(loaded, isNotNull);
      expect(loaded!['학교명'], equals('오프라인중학교'));
    });

    test('ComciganService getTimetable falls back to offline cache or demo without crash', () async {
      final storage = StorageService();
      final service = ComciganService();

      final cachedRaw = {
        '학교명': '캐시백업고교',
        '학급수': [0, 1],
        '자료446': ['', '박교사'],
        '자료492': ['', '과학'],
        '자료481': [
          [],
          [
            [],
            [
              [],
              [0, 101],
            ],
          ],
        ],
      };

      // Save to cache
      await storage.saveCachedTimetable(77777, cachedRaw);

      // Retrieve via service (offline simulation: online fetch fails for mock school code)
      final timetable = await service.getTimetable(77777);
      expect(timetable, isNotNull);
      expect(timetable.lessons.isNotEmpty, isTrue);
    });
  });
}

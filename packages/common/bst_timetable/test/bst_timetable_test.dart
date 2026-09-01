import 'package:flutter_test/flutter_test.dart';
import 'package:bst_timetable/bst_timetable.dart';

void main() {
  group('ComciganService Normalization & Parsing Tests', () {
    test('normalizeRawData maps obfuscated keys to canonical Korean keys', () {
      final raw = {
        '자료147_test': [[0], [0, 1]],
        '자료446_test': ['', '김선생', '이선생'],
        '자료492_test': ['', '국어', '수학'],
        '자료481_test': [
          [],
          [
            [],
            [
              [],
              [0, 101, 202], // Mon: period 1 (Sub 1, Tea 1), period 2 (Sub 2, Tea 2)
            ]
          ]
        ],
        '학급수': [0, 2, 2, 2],
        '일과시간': ['1(09:00)', '2(10:00)'],
        '학교명': '테스트중학교',
        '분리': 100,
      };

      final normalized = ComciganService.normalizeRawData(raw);
      expect(normalized['학교명'], '테스트중학교');
      expect(normalized['학급수'], [0, 2, 2, 2]);
      expect(normalized['자료446'], isNotNull);
      expect(normalized['자료492'], isNotNull);
      expect(normalized['자료481'], isNotNull);
    });

    test('parseTimetableData builds valid TimetableResult structure', () {
      final mockRaw = {
        '학교명': '보디스트고등학교',
        '학급수': [0, 3, 3, 3],
        '일과시간': ['1(08:40)', '2(09:35)'],
        '자료446': ['', '홍길동', '김철수'],
        '자료492': ['', '수학', '영어'],
        '자료147': [
          [],
          [0, 1, 2], // Grade 1: Class 1 -> Hong, Class 2 -> Kim
        ],
        '자료481': [
          [], // Grade 0 (unused)
          [
            [], // Grade 1, Class 0 (unused)
            [
              [], // Weekday 0 (unused)
              [0, 101, 202], // Mon: 1st period -> 101 (Math / Hong), 2nd period -> 202 (English / Kim)
            ],
          ],
        ],
        '분리': 100,
      };

      final result = ComciganService.parseTimetableData(mockRaw);
      expect(result.schoolName, '보디스트고등학교');
      expect(result.classCounts[1], 3);
      expect(result.homeroomTeachers[1]?[1], '홍길동');
      expect(result.homeroomTeachers[1]?[2], '김철수');
      expect(result.lessons.length, 2);

      final lesson1 = result.lessons[0];
      expect(lesson1.grade, 1);
      expect(lesson1.classNum, 1);
      expect(lesson1.weekday, 1);
      expect(lesson1.classTime, 1);
      expect(lesson1.subject, '수학');
      expect(lesson1.teacher, '홍길동');

      // Test special room reverse teacher lookup
      final match1 = result.findClassByTeacherAndPeriod(
        weekday: 1,
        period: 1,
        teacherAbbr: '홍길동',
      );
      expect(match1, isNotNull);
      expect(match1!['grade'], 1);
      expect(match1['classNum'], 1);

      final noMatch = result.findClassByTeacherAndPeriod(
        weekday: 1,
        period: 1,
        teacherAbbr: '박영희',
      );
      expect(noMatch, isNull);
    });

    test('fetchTimetableRaw returns valid map without throwing on any platform', () async {
      final service = ComciganService();
      // Calling fetchTimetableRaw should complete gracefully and return a normalized map
      final rawMap = await service.fetchTimetableRaw(99999);
      expect(rawMap, isA<Map<String, dynamic>>());
      expect(rawMap.containsKey('학교명'), isTrue);
    });
  });

  group('NeisService Tests', () {
    test('NeisService handles null API key with default hub baseUrl', () {
      final neis = NeisService();
      expect(neis.apiKey, isNull);
    });
  });
}

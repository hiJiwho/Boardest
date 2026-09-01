import 'package:flutter_test/flutter_test.dart';
import 'package:bst_core/bst_core.dart';
import 'package:bst_timetable/bst_timetable.dart';

void main() {
  group('ComciganService & TimetableResult Adversarial Tests', () {
    test('normalizeRawData handles dirty and alternative key variations', () {
      final dirtyJson = {
        'prefix_자료147_suffix': [null, [null, 1]],
        'some_자료446_extra': ['', '홍길동'],
        'custom_자료492_key': ['', '수학'],
        'table_자료481_data': [
          null,
          [
            null,
            [
              null,
              [null, 101], // grade 1, class 1, weekday 1, period 1 -> s=1, t=1
            ]
          ]
        ],
        'total_학급수_info': [0, 5, 5, 5],
        '분리_type': 100,
        '일과시간_표': ['(1) 09:00', '(2) 09:50'],
        '학교명_공식': '테스트고등학교',
      };

      final normalized = ComciganService.normalizeRawData(dirtyJson);
      expect(normalized.containsKey('자료147'), isTrue);
      expect(normalized.containsKey('자료446'), isTrue);
      expect(normalized.containsKey('자료492'), isTrue);
      expect(normalized.containsKey('자료481'), isTrue);
      expect(normalized.containsKey('학급수'), isTrue);
      expect(normalized.containsKey('분리'), isTrue);
      expect(normalized.containsKey('일과시간'), isTrue);
      expect(normalized['학교명'], equals('테스트고등학교'));
    });

    test('parseTimetableData with out-of-bound indices and ragged structures', () {
      final malformedRaw = {
        '학교명': '예외테스트고교',
        '학급수': [0, 2, 2, 2],
        '일과시간': ['(1) 09:00', '(2) 09:50'],
        '자료446': ['', '김교사'], // Only 1 teacher at index 1
        '자료492': ['', '국어'], // Only 1 subject at index 1
        '자료147': [
          null,
          [null, 999], // Out of bounds homeroom teacher index (999 >= 2)
        ],
        '자료481': [
          null,
          [
            null,
            [
              null,
              [
                null,
                101, // Valid: s=1 (국어), t=1 (김교사)
                9999, // Invalid: s=99, t=99 (out of bounds) -> should not crash
                0, // Ignored cell
                -50, // Negative cell -> should not crash
              ],
            ],
          ],
        ],
        '분리': 100,
      };

      final result = ComciganService.parseTimetableData(malformedRaw);
      expect(result.schoolName, equals('예외테스트고교'));
      expect(result.periodTimes.length, equals(2));
      // Out of bounds homeroom teacher should be safely skipped
      expect(result.homeroomTeachers[1], isNull);

      // Only valid lesson is parsed
      expect(result.lessons.length, equals(1));
      expect(result.lessons.first.grade, equals(1));
      expect(result.lessons.first.classNum, equals(1));
      expect(result.lessons.first.subject, equals('국어'));
      expect(result.lessons.first.teacher, equals('김교사'));
    });

    test('TimetableResult.findClassByTeacherAndPeriod with privacy masking and edge cases', () {
      final lessons = [
        Lesson(
          grade: 2,
          classNum: 3,
          weekday: 1, // Monday
          classTime: 3, // 3rd period
          teacher: '홍*동',
          subject: '수학',
          classroom: '2-3',
          isChanged: false,
        ),
      ];

      final result = TimetableResult(
        schoolName: '테스트고',
        periodTimes: [],
        classCounts: {1: 10, 2: 10, 3: 10},
        lessons: lessons,
        homeroomTeachers: {},
      );

      // 1. Exact match with unmasked query
      final found1 = result.findClassByTeacherAndPeriod(
        weekday: 1,
        period: 3,
        teacherAbbr: '홍동',
      );
      expect(found1, equals({'grade': 2, 'classNum': 3}));

      // 2. Query with asterisk
      final found2 = result.findClassByTeacherAndPeriod(
        weekday: 1,
        period: 3,
        teacherAbbr: '홍*동',
      );
      expect(found2, equals({'grade': 2, 'classNum': 3}));

      // 3. Query with non-matching teacher or empty
      expect(
        result.findClassByTeacherAndPeriod(weekday: 1, period: 3, teacherAbbr: ''),
        isNull,
      );
      expect(
        result.findClassByTeacherAndPeriod(weekday: 1, period: 3, teacherAbbr: '***'),
        isNull,
      );
      expect(
        result.findClassByTeacherAndPeriod(weekday: 1, period: 3, teacherAbbr: '김철수'),
        isNull,
      );
      // 4. Non-matching period or weekday
      expect(
        result.findClassByTeacherAndPeriod(weekday: 2, period: 3, teacherAbbr: '홍동'),
        isNull,
      );
      expect(
        result.findClassByTeacherAndPeriod(weekday: 1, period: 4, teacherAbbr: '홍동'),
        isNull,
      );
    });

    test('Separation code 1000 vs 100 decoding math', () {
      final raw1000 = {
        '학교명': '분리1000학교',
        '학급수': [0, 1],
        '일과시간': [],
        '자료446': List.generate(500, (i) => '교사$i'),
        '자료492': List.generate(500, (i) => '과목$i'),
        '자료481': [
          null,
          [
            null,
            [
              null,
              [null, 123456], // sIndex = 123, tIndex = 456
            ]
          ]
        ],
        '분리': 1000,
      };

      final result1000 = ComciganService.parseTimetableData(raw1000);
      expect(result1000.lessons.length, equals(1));
      expect(result1000.lessons.first.subject, equals('과목123'));
      expect(result1000.lessons.first.teacher, equals('교사456'));
    });
  });
}

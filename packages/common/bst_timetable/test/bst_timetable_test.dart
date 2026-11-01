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

    test('Weekend schedules (Saturday=6, Sunday=7) and string format changed cells (>101)', () {
      final weekendRaw = {
        '학교명': '주말특성화고',
        '학급수': [0, 2, 2, 2],
        '일과시간': ['1(09:00)', '2(10:00)'],
        '자료446': ['', '홍길동', '이토요', '박일요'],
        '자료492': ['', '국어', '로봇공학', '코딩'],
        '자료481': [
          [],
          [
            [],
            [
              [], // weekday 0
              [0, 101], // Mon
              [], // Tue
              [], // Wed
              [], // Thu
              [], // Fri
              [0, '>202'], // Sat (weekday 6): Changed robot class with teacher 2
              [0, '303'], // Sun (weekday 7): Coding with teacher 3
            ],
          ],
        ],
        '분리': 100,
      };

      final result = ComciganService.parseTimetableData(weekendRaw);
      expect(result.lessons.length, 3);

      final satLesson = result.lessons.firstWhere((l) => l.weekday == 6);
      expect(satLesson.subject, contains('로봇공학'));
      expect(satLesson.teacher, '이토요');
      expect(satLesson.isChanged, isTrue);

      final sunLesson = result.lessons.firstWhere((l) => l.weekday == 7);
      expect(sunLesson.subject, contains('코딩'));
      expect(sunLesson.teacher, '박일요');
      expect(sunLesson.isChanged, isFalse);
    });

    test('Elementary school 6-grade support and out-of-range target filtering', () {
      final elemRaw = {
        '학교명': '보디스트초등학교',
        '학급수': [0, 4, 4, 4, 5, 5, 6], // 6 grades
        '일과시간': ['1(09:00)'],
        '자료446': ['', '담임교사'],
        '자료492': ['', '창체'],
        '자료481': [
          [],
          for (int g = 1; g <= 6; g++)
            [
              [],
              [
                [],
                [0, 101], // Mon 1st period
              ],
            ],
        ],
        '분리': 100,
      };

      final resultAll = ComciganService.parseTimetableData(elemRaw);
      expect(resultAll.classCounts.length, 6);
      expect(resultAll.classCounts[6], 6);
      expect(resultAll.lessons.length, 6);

      // Target grade out of range (e.g. grade 99)
      final resultOutOfRange = ComciganService.parseTimetableData(elemRaw, targetGrade: 99);
      expect(resultOutOfRange.lessons, isEmpty);

      // Target grade 6 specific
      final resultGrade6 = ComciganService.parseTimetableData(elemRaw, targetGrade: 6);
      expect(resultGrade6.lessons.length, 1);
      expect(resultGrade6.lessons.first.grade, 6);
    });

    test('Missing teacher resolves to homeroom teacher for self-study and homeroom', () {
      final missingTeacherRaw = {
        '학교명': '테스트중학교',
        '학급수': [0, 2],
        '일과시간': ['1(09:00)'],
        '자료446': ['', '담임선생'], // index 1
        '자료492': ['', '자율활동'], // index 1
        '자료147': [
          [],
          [0, 1], // Grade 1 Class 1 homeroom is teacher 1
        ],
        '자료481': [
          [],
          [
            [],
            [
              [],
              [0, 100], // Sub 1, Teacher 0 (missing teacher)
            ],
          ],
        ],
        '분리': 100,
      };

      final result = ComciganService.parseTimetableData(missingTeacherRaw);
      expect(result.lessons.length, 1);
      // Resolved to homeroom teacher
      expect(result.lessons.first.teacher, '담임선생');
    });

    test('TimetableResult toJson and fromJson round-trip serialization', () {
      final original = TimetableResult(
        schoolName: '시리얼라이즈학교',
        periodTimes: ['09:00', '10:00'],
        classCounts: {1: 5, 2: 4, 3: 4},
        lessons: [
          Lesson(
            grade: 1,
            classNum: 2,
            weekday: 3,
            classTime: 4,
            teacher: '정교사',
            subject: '역사',
            classroom: '1-2',
            isChanged: true,
          ),
        ],
        homeroomTeachers: {
          1: {2: '정교사'},
        },
      );

      final jsonMap = original.toJson();
      final restored = TimetableResult.fromJson(jsonMap);

      expect(restored.schoolName, original.schoolName);
      expect(restored.periodTimes, original.periodTimes);
      expect(restored.classCounts[1], 5);
      expect(restored.lessons.length, 1);
      expect(restored.lessons.first.teacher, '정교사');
      expect(restored.lessons.first.subject, contains('역사'));
      expect(restored.homeroomTeachers[1]?[2], '정교사');
    });

    test('ComciganService cache set, get, clear and offline recovery', () async {
      ComciganService.clearCache();
      expect(ComciganService.getCachedData(12345), isNull);

      final cachedMock = {'학교명': '캐시학교', '학급수': [0, 3, 3]};
      ComciganService.setCachedData(12345, cachedMock);
      expect(ComciganService.getCachedData(12345), isNotNull);
      expect(ComciganService.getCachedData(12345)?['학교명'], '캐시학교');

      // fetchTimetableRaw with invalid endpoint uses cached data when offline
      final service = ComciganService();
      final recovered = await service.fetchTimetableRaw(12345);
      expect(recovered['학교명'], '캐시학교');

      ComciganService.clearCache(schoolCode: 12345);
      expect(ComciganService.getCachedData(12345), isNull);
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

    test('parseNeisTimetable parses valid NEIS JSON response to Lesson objects', () {
      final mockNeisJson = {
        'hisTimetable': [
          {
            'head': [
              {'list_total_count': 1},
              {'RESULT': {'CODE': 'INFO-000', 'MESSAGE': '정상 처리되었습니다.'}},
            ],
          },
          {
            'row': [
              {
                'ATPT_OFCDC_SC_CODE': 'B10',
                'SD_SCHUL_CODE': '7010057',
                'AY': '2026',
                'SEM': '1',
                'ALL_TI_YMD': '20260420', // Monday
                'GRADE': '2',
                'CLASS_NM': '3',
                'PERIO': '2',
                'ITRT_CNTNT': '인공지능기초',
              },
            ],
          },
        ],
      };

      final lessons = NeisService.parseNeisTimetable(mockNeisJson, schoolType: 'his');
      expect(lessons.length, 1);
      final l = lessons.first;
      expect(l.grade, 2);
      expect(l.classNum, 3);
      expect(l.classTime, 2);
      expect(l.subject, '인공지능기초');
      expect(l.classroom, '2-3');
      expect(l.weekday, 1); // 2026-04-20 is Monday (1)
    });

    test('parseNeisTimetable handles empty or malformed inputs without throwing', () {
      expect(NeisService.parseNeisTimetable(null), isEmpty);
      expect(NeisService.parseNeisTimetable({}), isEmpty);
      expect(NeisService.parseNeisTimetable({'hisTimetable': []}), isEmpty);
      expect(NeisService.parseNeisTimetable({'hisTimetable': [{'head': []}, {'row': 'invalid'}]}), isEmpty);
    });
  });
}

import '../models/lesson.dart';

class DemoTimetableService {
  static const List<String> subjects = [
    '도덕',
    '수학',
    '영어',
    '과학',
    '사회',
    '역사',
    '음악',
    '체육',
    '미술',
  ];

  static const List<String> teachers = [
    '김윤리',
    '이도형',
    '박영어',
    '최과학',
    '정사회',
    '강역사',
    '송음악',
    '윤체육',
    '조미술',
  ];

  static final List<({int grade, int classNum})> classList = [
    (grade: 1, classNum: 1),
    (grade: 1, classNum: 2),
    (grade: 1, classNum: 3),
    (grade: 2, classNum: 1),
    (grade: 2, classNum: 2),
    (grade: 2, classNum: 3),
    (grade: 3, classNum: 1),
    (grade: 3, classNum: 2),
    (grade: 3, classNum: 3),
  ];

  /// Extracts class number integer from class ID
  static int parseClassNumber(String classId) {
    return parseGradeAndClass(classId).classNum;
  }

  /// Extracts class number and grade from class ID
  /// Formats: "101" -> 1-1, "203" -> 2-3, "Demo-class1" -> 1-1, "ydm_1_2_1" -> 2-1
  static ({int grade, int classNum}) parseGradeAndClass(String classId) {
    if (classId.contains('_')) {
      final parts = classId.split('_');
      if (parts.length >= 4) {
        final g = int.tryParse(parts[parts.length - 2]) ?? 1;
        final c = int.tryParse(parts.last) ?? 1;
        return (grade: g, classNum: c);
      }
    }
    final numMatch = RegExp(r'(\d+)').firstMatch(classId);
    if (numMatch != null) {
      final val = int.tryParse(numMatch.group(1)!) ?? 1;
      if (val >= 100) {
        final g = val ~/ 100;
        final c = val % 100;
        return (grade: g, classNum: c);
      }
      return (grade: 1, classNum: val);
    }
    return (grade: 1, classNum: 1);
  }

  /// Generates a conflict-free middle school timetable for the week
  /// Exactly matching Boardest Teacher app's 9x9 latin square
  static Map<int, List<Lesson>> generateWeeklyTimetable(String classId) {
    final parsed = parseGradeAndClass(classId);
    final targetGrade = parsed.grade;
    final targetClass = parsed.classNum;

    // Find class index (0..8)
    int classIdx = classList.indexWhere((c) => c.grade == targetGrade && c.classNum == targetClass);
    if (classIdx == -1) {
      classIdx = (targetClass - 1).clamp(0, classList.length - 1);
    }

    final Map<int, List<Lesson>> weekly = {};

    for (int day = 1; day <= 7; day++) {
      final List<Lesson> dayLessons = [];
      const int periodsCount = 7;

      for (int period = 1; period <= periodsCount; period++) {
        // Latin square mapping identical to Boardest Teacher comcigan_service
        final tIdx = (classIdx + (period - 1) + (day - 1) * 2) % 9;

        dayLessons.add(
          Lesson(
            grade: targetGrade,
            classNum: targetClass,
            weekday: day,
            classTime: period,
            subject: subjects[tIdx],
            teacher: teachers[tIdx],
            classroom: '$targetGrade-$targetClass',
            isChanged: false,
          ),
        );
      }
      weekly[day] = dayLessons;
    }

    return weekly;
  }

  static List<Lesson> getAllDemoLessons(String classId) {
    final weekly = generateWeeklyTimetable(classId);
    final List<Lesson> all = [];
    weekly.forEach((_, list) => all.addAll(list));
    return all;
  }
}

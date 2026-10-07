import '../models/lesson.dart';

class DemoTimetableService {
  static const List<String> subjects = [
    '국어',
    '수학',
    '영어',
    '사회',
    '과학',
    '도덕',
    '기술가정',
    '체육',
    '음악',
    '미술',
    '한문',
    '정보',
  ];

  static const List<String> teachers = [
    '김한국',
    '이수리',
    '박글로벌',
    '최역사',
    '정탐구',
    '강바른',
    '윤기술',
    '송건강',
    '신선율',
    '조예술',
    '한문정',
    '오코딩',
  ];

  /// Extracts class number integer from class ID (e.g. "Demo-class1" -> 1, "Demo-class3" -> 3)
  static int parseClassNumber(String classId) {
    final match = RegExp(r'(\d+)').firstMatch(classId);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 1;
    }
    return 1;
  }

  /// Generates a conflict-free middle school timetable for the week
  /// Each class (Demo-class1, Demo-class2, ...) gets mutually exclusive subjects at the same period
  static Map<int, List<Lesson>> generateWeeklyTimetable(String classId) {
    final classNum = parseClassNumber(classId);
    final Map<int, List<Lesson>> weekly = {};

    // Days 1 (Mon) to 5 (Fri)
    for (int day = 1; day <= 5; day++) {
      final List<Lesson> dayLessons = [];
      // 6 or 7 periods per day (e.g. Mon, Wed, Fri: 6, Tue, Thu: 7)
      final int periodsCount = (day == 2 || day == 4) ? 7 : 6;

      for (int period = 1; period <= periodsCount; period++) {
        // Latin square mapping: ensures no two classes share the same subject in the same period on the same day
        final subjectIdx = (classNum + period + day * 3) % subjects.length;
        final teacherIdx = subjectIdx % teachers.length;

        dayLessons.add(
          Lesson(
            grade: 1,
            classNum: classNum,
            weekday: day,
            classTime: period,
            subject: subjects[subjectIdx],
            teacher: teachers[teacherIdx],
            classroom: 'Demo-$classNum',
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

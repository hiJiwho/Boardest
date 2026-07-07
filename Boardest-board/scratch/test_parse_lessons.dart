import '../lib/services/comcigan_service.dart';

void main() async {
  final service = ComciganService();
  try {
    final raw = await service.fetchTimetableRaw(44134);
    final result = service.parseTimetable(raw);
    
    print('Lessons for Grade 2, Class 1:');
    final g2c1 = result.lessons.where((l) => l.grade == 2 && l.classNum == 1).toList();
    for (int weekday = 1; weekday <= 5; weekday++) {
      print('Weekday $weekday:');
      final dayLessons = g2c1.where((l) => l.weekday == weekday).toList()..sort((a, b) => a.classTime.compareTo(b.classTime));
      for (final lesson in dayLessons) {
        print('  Period ${lesson.classTime}: ${lesson.subject} (${lesson.teacher})');
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}

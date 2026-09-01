import '../lib/services/comcigan_service.dart';

void main() async {
  final service = ComciganService();
  try {
    final raw = await service.fetchTimetableRaw(44134);
    final result = service.parseTimetable(raw);
    
    print('Homeroom teachers:');
    print(result.homeroomTeachers);
    
    print('Lessons for Grade 2, Class 3 Friday:');
    final g2c3 = result.lessons.where((l) => l.grade == 2 && l.classNum == 3 && l.weekday == 5).toList();
    for (final lesson in g2c3) {
      print('  Period ${lesson.classTime}: ${lesson.subject} (${lesson.teacher})');
    }
  } catch (e) {
    print('Error: $e');
  }
}

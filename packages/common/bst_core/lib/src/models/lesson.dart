class Lesson {
  final int grade;
  final int classNum;
  final int weekday; // 1: Mon, 2: Tue, 3: Wed, 4: Thu, 5: Fri
  final int classTime; // 1 to 8 (period index)
  final String teacher;
  final String subject;
  final String classroom;
  final bool isChanged;

  Lesson({
    required this.grade,
    required this.classNum,
    required this.weekday,
    required this.classTime,
    required this.teacher,
    required String subject,
    required this.classroom,
    required this.isChanged,
  }) : this.subject = (isChanged && !subject.endsWith('*')) ? '$subject*' : subject;

  Map<String, dynamic> toJson() {
    return {
      'grade': grade,
      'classNum': classNum,
      'weekday': weekday,
      'classTime': classTime,
      'teacher': teacher,
      'subject': subject,
      'classroom': classroom,
      'isChanged': isChanged,
    };
  }

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      grade: json['grade'] as int,
      classNum: json['classNum'] as int,
      weekday: json['weekday'] as int,
      classTime: json['classTime'] as int,
      teacher: json['teacher'] as String,
      subject: json['subject'] as String,
      classroom: json['classroom'] as String,
      isChanged: json['isChanged'] as bool,
    );
  }

  @override
  String toString() {
    return 'Lesson(grade: $grade, classNum: $classNum, weekday: $weekday, classTime: $classTime, subject: $subject, teacher: $teacher, classroom: $classroom, isChanged: $isChanged)';
  }
}

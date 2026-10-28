import 'dart:convert';

/// 수행평가 / 과제 항목 모델
class AssessmentItem {
  final String id;
  final String schoolCode;
  final int grade;
  final int classNum; // 0이면 학년 전체 공통
  final String subject;
  final String title;
  final String description;
  final DateTime dueDate;
  final String type; // '수행평가', '과제', '단원평가', '프로젝트'
  final String authorRole; // 'teacher' or 'student'
  final String authorName;
  final DateTime createdAt;
  final bool isCompleted;

  AssessmentItem({
    required this.id,
    required this.schoolCode,
    required this.grade,
    this.classNum = 0,
    required this.subject,
    required this.title,
    this.description = '',
    required this.dueDate,
    this.type = '수행평가',
    required this.authorRole,
    required this.authorName,
    required this.createdAt,
    this.isCompleted = false,
  });

  int get dDay {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return target.difference(today).inDays;
  }

  String get dDayString {
    final d = dDay;
    if (d > 0) return 'D-$d';
    if (d == 0) return 'D-Day';
    return 'D+${d.abs()}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'schoolCode': schoolCode,
        'grade': grade,
        'classNum': classNum,
        'subject': subject,
        'title': title,
        'description': description,
        'dueDate': dueDate.toIso8601String(),
        'type': type,
        'authorRole': authorRole,
        'authorName': authorName,
        'createdAt': createdAt.toIso8601String(),
        'isCompleted': isCompleted,
      };

  factory AssessmentItem.fromJson(Map<String, dynamic> json) {
    return AssessmentItem(
      id: json['id']?.toString() ?? '',
      schoolCode: json['schoolCode']?.toString() ?? '',
      grade: int.tryParse(json['grade']?.toString() ?? '1') ?? 1,
      classNum: int.tryParse(json['classNum']?.toString() ?? '0') ?? 0,
      subject: json['subject']?.toString() ?? '기타',
      title: json['title']?.toString() ?? '무제',
      description: json['description']?.toString() ?? '',
      dueDate: DateTime.tryParse(json['dueDate']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 7)),
      type: json['type']?.toString() ?? '수행평가',
      authorRole: json['authorRole']?.toString() ?? 'teacher',
      authorName: json['authorName']?.toString() ?? '선생님',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      isCompleted: json['isCompleted'] == true,
    );
  }
}

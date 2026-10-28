
/// 수행평가 / 과제 항목 모델 (v5.3.4 세분화 필드 지원)
class AssessmentItem {
  final String id;
  final String schoolCode;
  final int grade;
  final int classNum; // 0이면 학년 전체 공통
  final String subject;
  final String title;
  final String description; // 세부 내용
  final String range; // 수행 범위 (예: 교과서 45~52쪽)
  final String precautions; // 주의사항 (예: 계산기 지참, 부정행위 금지)
  final int round; // 평가 회차 (1차, 2차 등)
  final int period; // 실시 교시 (예: 2교시)
  final int points; // 배점 (예: 20점)
  final DateTime dueDate; // 실시 일시 / 마감일
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
    this.range = '',
    this.precautions = '',
    this.round = 1,
    this.period = 1,
    this.points = 100,
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

  String get scheduleDisplay {
    final p = period > 0 ? '$period교시' : '';
    return '${dueDate.month}/${dueDate.day} $p'.trim();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'schoolCode': schoolCode,
        'grade': grade,
        'classNum': classNum,
        'subject': subject,
        'title': title,
        'description': description,
        'range': range,
        'precautions': precautions,
        'round': round,
        'period': period,
        'points': points,
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
      range: json['range']?.toString() ?? '',
      precautions: json['precautions']?.toString() ?? '',
      round: int.tryParse(json['round']?.toString() ?? '1') ?? 1,
      period: int.tryParse(json['period']?.toString() ?? '1') ?? 1,
      points: int.tryParse(json['points']?.toString() ?? '100') ?? 100,
      dueDate: DateTime.tryParse(json['dueDate']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 7)),
      type: json['type']?.toString() ?? '수행평가',
      authorRole: json['authorRole']?.toString() ?? 'teacher',
      authorName: json['authorName']?.toString() ?? '선생님',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      isCompleted: json['isCompleted'] == true,
    );
  }

  String get dday => dDayString;

  AssessmentItem copyWith({
    String? id,
    String? schoolCode,
    int? grade,
    int? classNum,
    String? title,
    String? subject,
    String? description,
    String? range,
    String? precautions,
    int? round,
    int? period,
    int? points,
    DateTime? dueDate,
    String? type,
    String? authorRole,
    String? authorName,
    bool? isCompleted,
  }) {
    return AssessmentItem(
      id: id ?? this.id,
      schoolCode: schoolCode ?? this.schoolCode,
      grade: grade ?? this.grade,
      classNum: classNum ?? this.classNum,
      subject: subject ?? this.subject,
      title: title ?? this.title,
      description: description ?? this.description,
      range: range ?? this.range,
      precautions: precautions ?? this.precautions,
      round: round ?? this.round,
      period: period ?? this.period,
      points: points ?? this.points,
      dueDate: dueDate ?? this.dueDate,
      type: type ?? this.type,
      authorRole: authorRole ?? this.authorRole,
      authorName: authorName ?? this.authorName,
      createdAt: createdAt,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

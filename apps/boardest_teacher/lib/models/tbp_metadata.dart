/// TBP (.TBP 파일 내용) 메타데이터 규격 모델
class TbpMetadata {
  final String version;
  final String folderId;
  final String title;
  final int grade;
  final int? classNum;
  final String? specialRoom;

  TbpMetadata({
    this.version = '1.0.0',
    required this.folderId,
    required this.title,
    required this.grade,
    this.classNum,
    this.specialRoom,
  });

  /// 반 스코프 키 (예: '3-1' 또는 'Music2')
  String get scopeKey {
    if (specialRoom != null && specialRoom!.isNotEmpty) {
      return specialRoom!;
    }
    final c = classNum ?? 1;
    return '$grade-$c';
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'folderId': folderId,
        'title': title,
        'grade': grade,
        'classNum': classNum,
        'specialRoom': specialRoom,
      };

  factory TbpMetadata.fromJson(Map<String, dynamic> json) => TbpMetadata(
        version: json['version'] ?? '1.0.0',
        folderId: json['folderId'] ?? '',
        title: json['title'] ?? '',
        grade: json['grade'] ?? 3,
        classNum: json['classNum'],
        specialRoom: json['specialRoom'],
      );
}

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
        version: (json['version'] ?? '5.4.0').toString(),
        folderId: (json['folderId'] ?? json['id'] ?? json['ID'] ?? '').toString(),
        title: (json['title'] ?? json['name'] ?? '').toString(),
        grade: json['grade'] is int ? json['grade'] as int : (int.tryParse(json['grade']?.toString() ?? '3') ?? 3),
        classNum: json['classNum'] is int ? json['classNum'] as int : int.tryParse(json['classNum']?.toString() ?? ''),
        specialRoom: json['specialRoom']?.toString(),
      );
}

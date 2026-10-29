/// 학교 행사 및 공지 광고판 모델 (사진 + 제목 형식)
class SchoolNotice {
  final String id;
  final String title;
  final String imageUrl;
  final String teacherName;
  final String? endDate; // YYYY-MM-DD
  final DateTime createdAt;

  SchoolNotice({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.teacherName = '',
    this.endDate,
    required this.createdAt,
  });

  /// 완료 건은 48시간 뒤 자동 만료/삭제 판정
  bool get isExpired48h {
    if (endDate == null || endDate!.isEmpty) return false;
    final endD = DateTime.tryParse(endDate!);
    if (endD == null) return false;
    // 완료일 23:59:59 기준 48시간 경과 여부
    final expiryLimit = DateTime(endD.year, endD.month, endD.day, 23, 59, 59).add(const Duration(hours: 48));
    return DateTime.now().isAfter(expiryLimit);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'imageUrl': imageUrl,
    'teacherName': teacherName,
    'endDate': endDate,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SchoolNotice.fromJson(Map<String, dynamic> json) {
    return SchoolNotice(
      id: json['id']?.toString() ?? 'ad_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title']?.toString() ?? '학교 행사 안내',
      imageUrl: json['imageUrl']?.toString() ?? '',
      teacherName: json['teacherName']?.toString() ?? '',
      endDate: json['endDate']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

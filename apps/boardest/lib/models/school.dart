class School {
  final int id;
  final String region;
  final String name;
  final int code;

  School({
    required this.id,
    required this.region,
    required this.name,
    required this.code,
  });

  /// Creates a School object from the raw list format returned by Comcigan API.
  /// Legacy Format: [id, region, name, code]
  /// 2026 Format: [id, region, name, code1, code2, code3] where real code index = (id ~/ 6347) + 2
  factory School.fromRawList(dynamic rawInput) {
    if (rawInput is Map) {
      return School(
        id: (rawInput['id'] ?? rawInput['regionCode'] ?? 0) is num
            ? ((rawInput['id'] ?? rawInput['regionCode'] ?? 0) as num).toInt()
            : int.tryParse((rawInput['id'] ?? rawInput['regionCode'] ?? '0').toString()) ?? 0,
        region: (rawInput['region'] ?? '').toString(),
        name: (rawInput['name'] ?? '').toString(),
        code: (rawInput['code'] ?? 0) is num
            ? (rawInput['code'] as num).toInt()
            : int.tryParse((rawInput['code'] ?? '0').toString()) ?? 0,
      );
    }
    final List<dynamic> raw = rawInput as List<dynamic>;
    final int idVal = (raw[0] is num) ? (raw[0] as num).toInt() : int.tryParse(raw[0].toString()) ?? 0;
    final int codeIdx = (raw.length > 4 && idVal >= 6347)
        ? ((idVal ~/ 6347) + 2).clamp(3, raw.length - 1)
        : 3;
    final int codeVal = (raw[codeIdx] is num)
        ? (raw[codeIdx] as num).toInt()
        : int.tryParse(raw[codeIdx].toString()) ?? 0;
    return School(
      id: idVal,
      region: raw[1].toString(),
      name: raw[2].toString(),
      code: codeVal,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'region': region, 'name': name, 'code': code};
  }

  factory School.fromJson(Map<String, dynamic> json) {
    return School(
      id: json['id'] as int,
      region: json['region'] as String,
      name: json['name'] as String,
      code: json['code'] as int,
    );
  }

  School copyWith({int? id, String? region, String? name, int? code}) {
    return School(
      id: id ?? this.id,
      region: region ?? this.region,
      name: name ?? this.name,
      code: code ?? this.code,
    );
  }

  @override
  String toString() =>
      'School(id: $id, region: $region, name: $name, code: $code)';
}

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
  /// Format: [id, region, name, code]
  factory School.fromRawList(List<dynamic> raw) {
    return School(
      id: raw[0] as int,
      region: raw[1] as String,
      name: raw[2] as String,
      code: raw[3] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'region': region,
      'name': name,
      'code': code,
    };
  }

  factory School.fromJson(Map<String, dynamic> json) {
    return School(
      id: json['id'] as int,
      region: json['region'] as String,
      name: json['name'] as String,
      code: json['code'] as int,
    );
  }

  @override
  String toString() => 'School(id: $id, region: $region, name: $name, code: $code)';
}

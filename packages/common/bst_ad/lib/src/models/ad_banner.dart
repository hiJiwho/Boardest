class AdBanner {
  final String id;
  final String imageUrl;
  final String clickUrl;
  final int remainingSeconds;

  AdBanner({
    required this.id,
    required this.imageUrl,
    required this.clickUrl,
    required this.remainingSeconds,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'imageUrl': imageUrl,
        'clickUrl': clickUrl,
        'remainingSeconds': remainingSeconds,
      };

  factory AdBanner.fromJson(Map<String, dynamic> json) => AdBanner(
        id: json['id'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        clickUrl: json['clickUrl'] as String? ?? '',
        remainingSeconds: (json['remainingSeconds'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() => 'AdBanner(id: $id, url: $clickUrl, remaining: ${remainingSeconds}s)';
}

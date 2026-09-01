enum CloudSyncStatus { idle, syncing, completed, error }

class CloudFile {
  final String id;
  final String name;
  final String mimeType;
  final int size;
  final DateTime modifiedTime;
  final String? downloadUrl;
  final String? thumbnailUrl;

  const CloudFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.modifiedTime,
    this.downloadUrl,
    this.thumbnailUrl,
  });

  bool get isTbp => name.toLowerCase().endsWith('.tbp');
  bool get isPdf => name.toLowerCase().endsWith('.pdf') || mimeType == 'application/pdf';
  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'size': size,
        'modifiedTime': modifiedTime.toIso8601String(),
        'downloadUrl': downloadUrl,
        'thumbnailUrl': thumbnailUrl,
      };

  factory CloudFile.fromJson(Map<String, dynamic> json) => CloudFile(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        size: json['size'] as int? ?? 0,
        modifiedTime: json['modifiedTime'] != null
            ? DateTime.parse(json['modifiedTime'] as String)
            : DateTime.now(),
        downloadUrl: json['downloadUrl'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
      );

  @override
  String toString() => 'CloudFile(id: $id, name: $name, mimeType: $mimeType, size: $size)';
}

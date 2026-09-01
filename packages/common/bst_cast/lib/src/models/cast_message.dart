class CastMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String schoolId;
  final int grade;
  final int classNumber;
  final String contentType;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  const CastMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.schoolId,
    required this.grade,
    required this.classNumber,
    required this.contentType,
    required this.payload,
    required this.timestamp,
  });

  String get roomId => '${schoolId}_${grade}-$classNumber';

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'schoolId': schoolId,
        'grade': grade,
        'classNumber': classNumber,
        'contentType': contentType,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
      };

  factory CastMessage.fromJson(Map<String, dynamic> json) => CastMessage(
        id: json['id'] as String? ?? '',
        senderId: json['senderId'] as String? ?? '',
        senderName: json['senderName'] as String? ?? '',
        schoolId: json['schoolId'] as String? ?? '',
        grade: json['grade'] as int? ?? 1,
        classNumber: json['classNumber'] as int? ?? 1,
        contentType: json['contentType'] as String? ?? 'custom',
        payload: json['payload'] != null
            ? Map<String, dynamic>.from(json['payload'] as Map)
            : <String, dynamic>{},
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now(),
      );

  @override
  String toString() => 'CastMessage(id: $id, room: $roomId, type: $contentType)';
}

class CastSignalingData {
  final String type;
  final String senderId;
  final String targetId;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  const CastSignalingData({
    required this.type,
    required this.senderId,
    required this.targetId,
    required this.data,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'senderId': senderId,
        'targetId': targetId,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
      };

  factory CastSignalingData.fromJson(Map<String, dynamic> json) => CastSignalingData(
        type: json['type'] as String? ?? 'ping',
        senderId: json['senderId'] as String? ?? '',
        targetId: json['targetId'] as String? ?? '',
        data: json['data'] != null
            ? Map<String, dynamic>.from(json['data'] as Map)
            : <String, dynamic>{},
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now(),
      );
}

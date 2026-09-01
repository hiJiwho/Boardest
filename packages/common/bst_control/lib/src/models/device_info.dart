class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String licenseKey;
  final DateTime registeredAt;

  DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.licenseKey,
    required this.registeredAt,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? '',
      licenseKey: json['licenseKey'] as String? ?? '',
      registeredAt: json['registeredAt'] != null
          ? DateTime.tryParse(json['registeredAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'licenseKey': licenseKey,
      'registeredAt': registeredAt.toIso8601String(),
    };
  }

  @override
  String toString() => 'DeviceInfo(id: $deviceId, name: $deviceName, key: $licenseKey)';
}

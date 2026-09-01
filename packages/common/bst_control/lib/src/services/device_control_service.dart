import '../models/device_info.dart';

class DeviceControlService {
  final Duration validationDelay;

  DeviceControlService({this.validationDelay = const Duration(milliseconds: 50)});

  Future<bool> validateLicenseKey(String licenseKey) async {
    if (licenseKey.isEmpty) {
      return false;
    }
    if (validationDelay > Duration.zero) {
      await Future.delayed(validationDelay);
    }
    return licenseKey.startsWith('BST-');
  }

  Future<DeviceInfo?> registerDevice(String deviceId, String deviceName, String licenseKey) async {
    final isValid = await validateLicenseKey(licenseKey);
    if (!isValid) {
      return null;
    }
    
    return DeviceInfo(
      deviceId: deviceId,
      deviceName: deviceName,
      licenseKey: licenseKey,
      registeredAt: DateTime.now(),
    );
  }

  Future<void> sendCommandToDevice(String deviceId, String command) async {
    // Logic for sending command to device
  }
}

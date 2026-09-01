import 'package:flutter_test/flutter_test.dart';
import 'package:bst_control/bst_control.dart';

void main() {
  group('DeviceInfo Model Tests', () {
    test('DeviceInfo toJson and fromJson round-trip', () {
      final now = DateTime.utc(2026, 8, 21, 14, 0, 0);
      final info = DeviceInfo(
        deviceId: 'dev_999',
        deviceName: 'Classroom 3-2 Board',
        licenseKey: 'BST-PRO-2026-X',
        registeredAt: now,
      );

      final json = info.toJson();
      expect(json['deviceId'], 'dev_999');
      expect(json['deviceName'], 'Classroom 3-2 Board');
      expect(json['licenseKey'], 'BST-PRO-2026-X');
      expect(json['registeredAt'], now.toIso8601String());

      final restored = DeviceInfo.fromJson(json);
      expect(restored.deviceId, 'dev_999');
      expect(restored.deviceName, 'Classroom 3-2 Board');
      expect(restored.licenseKey, 'BST-PRO-2026-X');
      expect(restored.registeredAt, equals(now));
      expect(restored.toString(), contains('dev_999'));
    });

    test('DeviceInfo.fromJson handles missing fields gracefully', () {
      final restored = DeviceInfo.fromJson({});
      expect(restored.deviceId, '');
      expect(restored.deviceName, '');
      expect(restored.licenseKey, '');
      expect(restored.registeredAt, isNotNull);
    });
  });

  group('DeviceControlService Tests', () {
    test('validateLicenseKey accepts BST- prefix and rejects others', () async {
      final service = DeviceControlService(validationDelay: Duration.zero);

      expect(await service.validateLicenseKey(''), isFalse);
      expect(await service.validateLicenseKey('INVALID-KEY'), isFalse);
      expect(await service.validateLicenseKey('BST-VALID-KEY'), isTrue);
    });

    test('registerDevice succeeds for valid key and fails for invalid key', () async {
      final service = DeviceControlService(validationDelay: Duration.zero);

      final failedDevice = await service.registerDevice('d1', 'Device 1', 'INVALID-KEY');
      expect(failedDevice, isNull);

      final validDevice = await service.registerDevice('d2', 'Device 2', 'BST-KEY-123');
      expect(validDevice, isNotNull);
      expect(validDevice!.deviceId, 'd2');
      expect(validDevice.deviceName, 'Device 2');
      expect(validDevice.licenseKey, 'BST-KEY-123');

      // Command dispatch should complete cleanly
      await service.sendCommandToDevice('d2', 'REBOOT');
    });
  });
}

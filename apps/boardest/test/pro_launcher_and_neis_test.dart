import 'package:flutter_test/flutter_test.dart';
import 'package:boardest/models/app_settings.dart';

void main() {
  group('Boardest Class PRO Unlimited App Addition Tests', () {
    test('1. AppSettings supports more than 18 launcher slots without truncation', () {
      final initialSlots = List.generate(
        25,
        (i) => LauncherSlot(
          type: LauncherSlotType.systemApp,
          name: 'App $i',
          id: 'com.app.$i',
        ),
      );

      final settings = AppSettings(launcherSlots: initialSlots);
      expect(settings.launcherSlots.length, equals(25));
      expect(settings.launcherSlots[24].name, equals('App 24'));

      // JSON roundtrip serialization
      final json = settings.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.launcherSlots.length, equals(25));
      expect(restored.launcherSlots[20].name, equals('App 20'));
      expect(restored.launcherSlots[24].id, equals('com.app.24'));
    });

    test('2. Dynamic slot indexing and removal handles shifting correctly', () {
      final slots = List.generate(
        18,
        (i) => LauncherSlot(
          type: i < 14 ? LauncherSlotType.empty : LauncherSlotType.systemApp,
          name: i < 14 ? '' : 'CustomApp ${i - 14}',
          id: i < 14 ? '' : 'custom.$i',
        ),
      );

      // Add 2 more custom apps (total 6 custom apps: indices 14..19)
      slots.add(LauncherSlot(type: LauncherSlotType.systemApp, name: 'CustomApp 4', id: 'custom.18'));
      slots.add(LauncherSlot(type: LauncherSlotType.systemApp, name: 'CustomApp 5', id: 'custom.19'));

      expect(slots.length, equals(20));

      // Remove slot at index 15 ('CustomApp 1')
      final updatedSlots = List<LauncherSlot>.from(slots);
      updatedSlots.removeAt(15);
      while (updatedSlots.length < 18) {
        updatedSlots.add(LauncherSlot(type: LauncherSlotType.empty, name: '', id: ''));
      }

      expect(updatedSlots.length, equals(19));
      expect(updatedSlots[14].name, equals('CustomApp 0'));
      expect(updatedSlots[15].name, equals('CustomApp 2')); // shifted
      expect(updatedSlots[18].name, equals('CustomApp 5'));
    });
  });
}

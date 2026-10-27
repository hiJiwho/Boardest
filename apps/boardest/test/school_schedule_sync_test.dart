import 'package:flutter_test/flutter_test.dart';
import 'package:boardest/models/app_settings.dart';
import 'package:boardest/services/comcigan_service.dart';
import 'package:boardest/services/timetable_schedule_calculator.dart';

void main() {
  group('1. Comcigan School Period Times Parsing Tests', () {
    test('Correctly parses middle school 45m schedule with periodTimes', () {
      final periodTimes = [
        '1(08:40)',
        '2(09:35)',
        '3(10:30)',
        '4(11:25)',
        '5(13:10)',
        '6(14:05)',
        '7(15:00)',
      ];

      final ts = ComciganService.parseTimeSettingsFromPeriodTimes(periodTimes);
      expect(ts, isNotNull);
      expect(ts!.firstPeriodStart, equals('08:40'));
      expect(ts.lessonDuration, equals(45));
      expect(ts.breakDuration, equals(10));
      expect(ts.lunchAfterPeriod, equals(4));
      // Lunch gap: 13:10 - 11:25 = 105 mins. Lunch duration = 105 - 45 = 60 mins.
      expect(ts.lunchDuration, equals(60));
      expect(ts.morningAssemblyStart, equals('08:25'));
      expect(ts.morningAssemblyEnd, equals('08:40'));
      expect(ts.periodStartTimes, equals(['08:40', '09:35', '10:30', '11:25', '13:10', '14:05', '15:00']));
    });

    test('Correctly parses high school 50m schedule with parentheses format', () {
      final periodTimes = [
        '(1) 09:00',
        '(2) 10:00',
        '(3) 11:00',
        '(4) 12:00',
        '(5) 13:50',
        '(6) 14:50',
        '(7) 15:50',
      ];

      final ts = ComciganService.parseTimeSettingsFromPeriodTimes(periodTimes);
      expect(ts, isNotNull);
      expect(ts!.firstPeriodStart, equals('09:00'));
      expect(ts.lessonDuration, equals(50));
      expect(ts.breakDuration, equals(10));
      expect(ts.lunchAfterPeriod, equals(4));
      expect(ts.lunchDuration, equals(60));
      expect(ts.periodStartTimes, equals(['09:00', '10:00', '11:00', '12:00', '13:50', '14:50', '15:50']));
    });
  });

  group('2. TimetableScheduleCalculator Dynamic Schedule Tests', () {
    test('Calculates exact period time ranges matching school periodStartTimes', () {
      final ts = TimeSettings(
        lessonDuration: 45,
        breakDuration: 10,
        lunchDuration: 60,
        lunchAfterPeriod: 4,
        firstPeriodStart: '08:40',
        periodStartTimes: ['08:40', '09:35', '10:30', '11:25', '13:10', '14:05', '15:00'],
      );

      final now = DateTime(2026, 10, 27);
      final ranges = TimetableScheduleCalculator.generatePeriodRanges(
        ts: ts,
        now: now,
        lessonsForDisplayDay: [],
      );

      // Verify Period 1
      final p1 = ranges.firstWhere((r) => r.period == 1);
      expect(p1.start.hour, equals(8));
      expect(p1.start.minute, equals(40));
      expect(p1.end.hour, equals(9));
      expect(p1.end.minute, equals(25));

      // Verify Period 5 (after lunch)
      final p5 = ranges.firstWhere((r) => r.period == 5);
      expect(p5.start.hour, equals(13));
      expect(p5.start.minute, equals(10));
      expect(p5.end.hour, equals(13));
      expect(p5.end.minute, equals(55));

      // Verify Lunch range
      final lunchRange = ranges.firstWhere((r) => r.label == '점심 시간');
      expect(lunchRange.start.hour, equals(12));
      expect(lunchRange.start.minute, equals(10));
      expect(lunchRange.end.hour, equals(13));
      expect(lunchRange.end.minute, equals(0));
    });
  });

  group('3. Class PRO App Registration Preservation Bug Fix Tests', () {
    test('Custom registered apps at slot indices 14..17 are never wiped or truncated', () {
      final initialSettings = AppSettings();
      expect(initialSettings.launcherSlots.length, greaterThanOrEqualTo(18));

      // User adds custom apps to slot 14, 15
      final updatedSlots = List<LauncherSlot>.from(initialSettings.launcherSlots);
      updatedSlots[14] = LauncherSlot(
        type: LauncherSlotType.systemApp,
        name: 'Canva',
        id: 'https://www.canva.com',
      );
      updatedSlots[15] = LauncherSlot(
        type: LauncherSlotType.systemApp,
        name: '한글2024',
        id: 'C:\\Program Files\\Hnc\\Hwp.exe',
      );

      final savedSettings = initialSettings.copyWith(launcherSlots: updatedSlots);
      final json = savedSettings.toJson();

      // Simulate app restart / settings reload
      final reloadedSettings = AppSettings.fromJson(json);

      expect(reloadedSettings.launcherSlots.length, greaterThanOrEqualTo(18));
      expect(reloadedSettings.launcherSlots[14].name, equals('Canva'));
      expect(reloadedSettings.launcherSlots[14].id, equals('https://www.canva.com'));
      expect(reloadedSettings.launcherSlots[14].type, equals(LauncherSlotType.systemApp));

      expect(reloadedSettings.launcherSlots[15].name, equals('한글2024'));
      expect(reloadedSettings.launcherSlots[15].id, equals('C:\\Program Files\\Hnc\\Hwp.exe'));
      expect(reloadedSettings.launcherSlots[15].type, equals(LauncherSlotType.systemApp));
    });

    test('Having explorer.exe or youtube URL does not reset custom slots', () {
      final slots = List<LauncherSlot>.generate(
        18,
        (i) => LauncherSlot(type: LauncherSlotType.empty, name: '', id: ''),
      );
      slots[14] = LauncherSlot(
        type: LauncherSlotType.systemApp,
        name: '유튜브',
        id: 'https://www.youtube.com',
      );
      slots[15] = LauncherSlot(
        type: LauncherSlotType.systemApp,
        name: '파일 탐색기',
        id: 'explorer.exe',
      );

      final json = {'launcherSlots': slots.map((s) => s.toJson()).toList()};
      final reloaded = AppSettings.fromJson(json);

      expect(reloaded.launcherSlots[14].name, equals('유튜브'));
      expect(reloaded.launcherSlots[14].id, equals('https://www.youtube.com'));
      expect(reloaded.launcherSlots[15].name, equals('파일 탐색기'));
      expect(reloaded.launcherSlots[15].id, equals('explorer.exe'));
    });
  });
}

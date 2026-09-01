import 'dart:async';
import 'package:universal_io/io.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';

/// 대시보드 [PeriodTimeRange]와 동일한 구조 (순환 import 방지)
class SchedulePeriodRange {
  final int period;
  final DateTime start;
  final DateTime end;
  final bool isClass;

  const SchedulePeriodRange({
    required this.period,
    required this.start,
    required this.end,
    required this.isClass,
  });
}

/// Windows 전용: 쉬는 시간·점심·하교 후 모니터 절전, 수업 교시에 복귀.
class SleepSchedulerService {
  bool _isAutoSleepEnabled = false;
  bool _deviceAsleep = false;
  List<SchedulePeriodRange> _ranges = [];
  DateTime? _snoozeUntil;

  static const platform = MethodChannel('com.boardest/launch_args');

  bool get isAutoSleepEnabled => _isAutoSleepEnabled;
  bool get isDeviceAsleep => _deviceAsleep;

  void enableAutoSleep(List<SchedulePeriodRange> ranges) {
    _ranges = ranges;
    _isAutoSleepEnabled = true;
    _deviceAsleep = false;
    _snoozeUntil = null;
  }

  void refreshRanges(List<SchedulePeriodRange> ranges) => _ranges = ranges;

  void disableAutoSleep() {
    _isAutoSleepEnabled = false;
    _snoozeUntil = null;
    if (_deviceAsleep) {
      _wakeFromSleep();
      _deviceAsleep = false;
    }
  }

  void snooze(Duration duration, {DateTime? customNow}) {
    final now = customNow ?? DateTime.now();
    _snoozeUntil = now.add(duration);
    debugPrint('[SleepScheduler] Sleep snoozed until $_snoozeUntil');
  }

  bool _inClassPeriod(DateTime now) {
    return _ranges.any(
      (r) => r.isClass && !now.isBefore(r.start) && now.isBefore(r.end),
    );
  }

  bool _inBreakOrLunch(DateTime now) {
    return _ranges.any(
      (r) => !r.isClass && r.period == 0 && !now.isBefore(r.start) && now.isBefore(r.end),
    );
  }

  bool shouldSleep(DateTime now) {
    if (_snoozeUntil != null && now.isBefore(_snoozeUntil!)) return false;
    if (_inClassPeriod(now)) {
      // 수업 시간이 시작되면 이전의 snooze 설정은 초기화
      _snoozeUntil = null;
      return false;
    }
    if (_inBreakOrLunch(now)) return true;

    DateTime? lastEventEnd;
    for (final r in _ranges) {
      if (r.end.isBefore(now)) {
        if (lastEventEnd == null || r.end.isAfter(lastEventEnd)) {
          lastEventEnd = r.end;
        }
      }
    }

    if (lastEventEnd != null) {
      return now.difference(lastEventEnd) >= const Duration(minutes: 1);
    }

    return false;
  }

  void checkAndExecuteSleep({DateTime? customNow}) {
    if (kIsWeb || !Platform.isWindows) return;

    final now = customNow ?? DateTime.now();

    if (_inClassPeriod(now)) {
      if (_deviceAsleep) {
        _wakeFromSleep();
        _deviceAsleep = false;
      }
      return;
    }

    if (shouldSleep(now)) {
      if (!_deviceAsleep) {
        _triggerSleep();
        _deviceAsleep = true;
      }
    }
  }

  Future<void> _triggerSleep() async {
    try {
      await platform.invokeMethod('triggerSleep');
      debugPrint('[SleepScheduler] Monitor sleep triggered');
    } catch (e) {
      debugPrint('[SleepScheduler] triggerSleep error: $e');
    }
  }

  Future<void> _wakeFromSleep() async {
    try {
      await platform.invokeMethod('wakeFromSleep');
      debugPrint('[SleepScheduler] Monitor wake triggered');
    } catch (e) {
      debugPrint('[SleepScheduler] wakeFromSleep error: $e');
    }
  }

  void dispose() {}
}

/// [DashboardView._generatePeriodRanges]와 동일한 로직
List<SchedulePeriodRange> buildScheduleRanges(TimeSettings ts, DateTime now) {
  final List<SchedulePeriodRange> ranges = [];

  final timeParts = ts.firstPeriodStart.split(':');
  final firstPeriodH = int.tryParse(timeParts[0]) ?? 8;
  final firstPeriodM = int.tryParse(timeParts.length > 1 ? timeParts[1] : '40') ?? 40;
  final firstPeriodStart = DateTime(now.year, now.month, now.day, firstPeriodH, firstPeriodM);

  DateTime morningStart;
  DateTime morningEnd;

  final morningBefore = ts.morningAssemblyBeforeMinutes;
  if (morningBefore != null) {
    morningStart = firstPeriodStart.subtract(Duration(minutes: morningBefore));
    final dur = int.tryParse(ts.morningAssemblyEnd) ?? (morningBefore > 5 ? morningBefore - 5 : morningBefore);
    morningEnd = morningStart.add(Duration(minutes: dur));
  } else {
    final morningPartsStart = ts.morningAssemblyStart.split(':');
    final morningHStart = int.tryParse(morningPartsStart[0]) ?? 8;
    final morningMStart = int.tryParse(morningPartsStart.length > 1 ? morningPartsStart[1] : '25') ?? 25;

    final morningPartsEnd = ts.morningAssemblyEnd.split(':');
    final morningHEnd = int.tryParse(morningPartsEnd[0]) ?? 8;
    final morningMEnd = int.tryParse(morningPartsEnd.length > 1 ? morningPartsEnd[1] : '40') ?? 40;

    morningStart = DateTime(now.year, now.month, now.day, morningHStart, morningMStart);
    morningEnd = DateTime(now.year, now.month, now.day, morningHEnd, morningMEnd);
  }

  // 0. 조회 전 아침 시간
  final morningEarly = DateTime(now.year, now.month, now.day, 7, 0);
  if (morningStart.isAfter(morningEarly)) {
    ranges.add(SchedulePeriodRange(
      period: -3,
      start: morningEarly,
      end: morningStart,
      isClass: false,
    ));
  }

  // 1. 조회 시간
  ranges.add(SchedulePeriodRange(
    period: -1,
    start: morningStart,
    end: morningEnd,
    isClass: false,
  ));

  // 2. 조회 후 ~ 1교시 전 쉬는시간
  if (morningEnd.isBefore(firstPeriodStart)) {
    ranges.add(SchedulePeriodRange(
      period: 0,
      start: morningEnd,
      end: firstPeriodStart,
      isClass: false,
    ));
  }

  // 3. 교시별 수업 & 쉬는시간 & 점심시간
  int currentMinutes = firstPeriodH * 60 + firstPeriodM;
  DateTime? lastPeriodEndTime;

  for (int p = 1; p <= 8; p++) {
    final classStart = DateTime(now.year, now.month, now.day, currentMinutes ~/ 60, currentMinutes % 60);
    currentMinutes += ts.lessonDuration;
    final classEnd = DateTime(now.year, now.month, now.day, currentMinutes ~/ 60, currentMinutes % 60);
    ranges.add(SchedulePeriodRange(period: p, start: classStart, end: classEnd, isClass: true));

    if (p == 8) {
      lastPeriodEndTime = classEnd;
    }

    if (p == ts.lunchAfterPeriod) {
      final pureLunchMinutes = (ts.lunchDuration - ts.breakDuration).clamp(1, 180);
      final lunchStart = classEnd;
      final pureLunchEnd = lunchStart.add(Duration(minutes: pureLunchMinutes));
      final totalLunchEnd = lunchStart.add(Duration(minutes: ts.lunchDuration));

      ranges.add(SchedulePeriodRange(period: 0, start: lunchStart, end: pureLunchEnd, isClass: false));

      if (ts.lunchDuration > pureLunchMinutes) {
        ranges.add(SchedulePeriodRange(period: 0, start: pureLunchEnd, end: totalLunchEnd, isClass: false));
      }
      currentMinutes += ts.lunchDuration;
    } else if (p < 8) {
      final breakEnd = classEnd.add(Duration(minutes: ts.breakDuration));
      ranges.add(SchedulePeriodRange(period: 0, start: classEnd, end: breakEnd, isClass: false));
      currentMinutes += ts.breakDuration;
    }
  }

  // 4. 종례 시간
  final lastEnd = lastPeriodEndTime ?? DateTime(now.year, now.month, now.day, currentMinutes ~/ 60, currentMinutes % 60);
  final afterMinutes = ts.afternoonAssemblyAfterMinutes ?? 10;
  final durationMinutes = ts.afternoonAssemblyDuration;

  if (afterMinutes > 0) {
    final breakStart = lastEnd;
    final breakEnd = breakStart.add(Duration(minutes: afterMinutes));
    ranges.add(SchedulePeriodRange(period: 0, start: breakStart, end: breakEnd, isClass: false));
  }

  final afternoonStart = lastEnd.add(Duration(minutes: afterMinutes));
  final afternoonEnd = afternoonStart.add(Duration(minutes: durationMinutes));
  ranges.add(SchedulePeriodRange(period: -2, start: afternoonStart, end: afternoonEnd, isClass: false));

  ranges.sort((a, b) => a.start.compareTo(b.start));
  return ranges;
}

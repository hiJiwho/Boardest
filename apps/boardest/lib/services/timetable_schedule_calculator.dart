import '../config/app_config.dart';
import '../models/app_settings.dart';
import '../models/lesson.dart';
import 'comcigan_service.dart';
import 'demo_timetable_service.dart';

class PeriodTimeRange {
  final int period; // 0 for break/lunch, 1-8 for classes
  final String label;
  final DateTime start;
  final DateTime end;
  final bool isClass;

  PeriodTimeRange({
    required this.period,
    required this.label,
    required this.start,
    required this.end,
    required this.isClass,
  });
}

/// Boardest 시간표 계산 및 교시 범위 생성 전담 모듈
class TimetableScheduleCalculator {
  const TimetableScheduleCalculator._();

  static Lesson emptyLesson(AppSettings settings, int period, int weekday) {
    return Lesson(
      grade: settings.selectedGrade,
      classNum: settings.selectedClass,
      weekday: weekday,
      classTime: period,
      subject: '',
      teacher: '',
      classroom: '',
      isChanged: false,
    );
  }

  static List<Lesson> getLessonsForDay({
    required TimetableResult? timetableResult,
    required AppSettings settings,
    required int day,
  }) {
    if (timetableResult == null) return [];

    final isDemo = AppConfig.isDemoMode ||
        settings.schoolId.toLowerCase() == 'demo' ||
        (settings.selectedSchool?.name.contains('데모') == true);
    if (isDemo) {
      final parsed = DemoTimetableService.parseGradeAndClass(
        settings.classNickname.isNotEmpty ? settings.classNickname : 'Demo-class1',
      );
      final targetGrade = settings.selectedGrade > 0 ? settings.selectedGrade : parsed.grade;
      final targetClassNum = settings.selectedClass > 0 ? settings.selectedClass : parsed.classNum;

      final matched = timetableResult.lessons
          .where((lesson) =>
              lesson.grade == targetGrade &&
              lesson.classNum == targetClassNum &&
              lesson.weekday == day)
          .toList();
      if (matched.isNotEmpty) return matched;

      // Fallback: match by classNum and day
      final classOnlyMatched = timetableResult.lessons
          .where((lesson) => lesson.classNum == targetClassNum && lesson.weekday == day)
          .toList();
      if (classOnlyMatched.isNotEmpty) return classOnlyMatched;

      // Fallback: match any lessons for that day
      final dayMatched = timetableResult.lessons.where((lesson) => lesson.weekday == day).toList();
      if (dayMatched.isNotEmpty) return dayMatched;
    }

    if (settings.isLearningLab) {
      return [];
    }

    if (settings.isTeacherFixedRoom) {
      final candidates = <String>{
        settings.selectedTeacherId.replaceAll('*', '').replaceAll(' ', '').trim(),
        settings.selectedTeacher.replaceAll('*', '').replaceAll(' ', '').trim(),
        settings.selectedTeacherName.replaceAll('*', '').replaceAll(' ', '').trim(),
      }..removeWhere((s) => s.isEmpty);

      if (candidates.isEmpty) return [];

      final rawLessons = timetableResult.lessons.where((lesson) {
        if (lesson.weekday != day) return false;
        final lt = lesson.teacher.replaceAll('*', '').replaceAll(' ', '').trim();
        if (lt.isEmpty) return false;
        return candidates.any((c) =>
            lt == c ||
            (c.length >= 2 && lt.startsWith(c)) ||
            (lt.length >= 2 && c.startsWith(lt)));
      }).toList();

      if (rawLessons.isEmpty) return [];

      final classes = rawLessons.map((l) => '${l.grade}-${l.classNum}').toSet();

      int maxPeriod = 0;
      for (final lesson in timetableResult.lessons) {
        if (lesson.weekday == day &&
            classes.contains('${lesson.grade}-${lesson.classNum}')) {
          if (lesson.classTime > maxPeriod) {
            maxPeriod = lesson.classTime;
          }
        }
      }

      if (maxPeriod == 0) maxPeriod = 7;

      final List<Lesson> filledLessons = [];
      for (int period = 1; period <= maxPeriod; period++) {
        final lesson = rawLessons.firstWhere(
          (l) => l.classTime == period,
          orElse: () => Lesson(
            grade: 0,
            classNum: 0,
            weekday: day,
            classTime: period,
            subject: '',
            teacher: '',
            classroom: '',
            isChanged: false,
          ),
        );

        if (lesson.grade == 0) {
          filledLessons.add(lesson);
        } else {
          filledLessons.add(
            Lesson(
              grade: lesson.grade,
              classNum: lesson.classNum,
              weekday: lesson.weekday,
              classTime: lesson.classTime,
              subject: lesson.subject,
              teacher: '${lesson.grade}-${lesson.classNum}',
              classroom: lesson.classroom,
              isChanged: lesson.isChanged,
            ),
          );
        }
      }
      return filledLessons;
    } else {
      final rawLessons = timetableResult.lessons.where((lesson) {
        return lesson.grade == settings.selectedGrade &&
            lesson.classNum == settings.selectedClass &&
            lesson.weekday == day;
      }).toList();

      if (rawLessons.isEmpty) return [];

      int maxPeriod = 0;
      for (final l in rawLessons) {
        if (l.classTime > maxPeriod) {
          maxPeriod = l.classTime;
        }
      }
      if (maxPeriod == 0) maxPeriod = 7;

      final List<Lesson> filledLessons = [];
      for (int period = 1; period <= maxPeriod; period++) {
        final lesson = rawLessons.firstWhere(
          (l) => l.classTime == period,
          orElse: () => Lesson(
            grade: settings.selectedGrade,
            classNum: settings.selectedClass,
            weekday: day,
            classTime: period,
            subject: '',
            teacher: '',
            classroom: '',
            isChanged: false,
          ),
        );

        if (lesson.subject.isEmpty) {
          filledLessons.add(lesson);
        } else {
          filledLessons.add(
            Lesson(
              grade: lesson.grade,
              classNum: lesson.classNum,
              weekday: lesson.weekday,
              classTime: lesson.classTime,
              subject: lesson.subject,
              teacher: AppSettings.formatTeacherDisplayName(lesson.teacher),
              classroom: lesson.classroom,
              isChanged: lesson.isChanged,
            ),
          );
        }
      }
      return filledLessons;
    }
  }

  static List<PeriodTimeRange> generatePeriodRanges({
    required TimeSettings ts,
    required DateTime now,
    required List<Lesson> lessonsForDisplayDay,
  }) {
    final List<PeriodTimeRange> ranges = [];

    final timeParts = ts.firstPeriodStart.split(':');
    final firstPeriodH = int.tryParse(timeParts[0]) ?? 8;
    final firstPeriodM =
        int.tryParse(timeParts.length > 1 ? timeParts[1] : '40') ?? 40;
    final firstPeriodStart = DateTime(
      now.year,
      now.month,
      now.day,
      firstPeriodH,
      firstPeriodM,
    );

    DateTime morningStart;
    DateTime morningEnd;

    final morningBefore = ts.morningAssemblyBeforeMinutes;
    if (morningBefore != null) {
      morningStart = firstPeriodStart.subtract(Duration(minutes: morningBefore));
      final dur = int.tryParse(ts.morningAssemblyEnd) ??
          (morningBefore > 5 ? morningBefore - 5 : morningBefore);
      morningEnd = morningStart.add(Duration(minutes: dur));
    } else {
      final morningPartsStart = ts.morningAssemblyStart.split(':');
      final morningHStart = int.tryParse(morningPartsStart[0]) ?? 8;
      final morningMStart =
          int.tryParse(morningPartsStart.length > 1 ? morningPartsStart[1] : '25') ?? 25;

      final morningPartsEnd = ts.morningAssemblyEnd.split(':');
      final morningHEnd = int.tryParse(morningPartsEnd[0]) ?? 8;
      final morningMEnd =
          int.tryParse(morningPartsEnd.length > 1 ? morningPartsEnd[1] : '40') ?? 40;

      morningStart = DateTime(now.year, now.month, now.day, morningHStart, morningMStart);
      morningEnd = DateTime(now.year, now.month, now.day, morningHEnd, morningMEnd);
    }

    final morningMidnight = DateTime(now.year, now.month, now.day, 0, 0, 0);
    if (morningStart.isAfter(morningMidnight)) {
      ranges.add(
        PeriodTimeRange(
          period: -3,
          label: '아침 시간',
          start: morningMidnight,
          end: morningStart,
          isClass: false,
        ),
      );
    }

    ranges.add(
      PeriodTimeRange(
        period: -1,
        label: '조회 시간',
        start: morningStart,
        end: morningEnd,
        isClass: false,
      ),
    );

    if (morningEnd.isBefore(firstPeriodStart)) {
      ranges.add(
        PeriodTimeRange(
          period: 0,
          label: '쉬는 시간',
          start: morningEnd,
          end: firstPeriodStart,
          isClass: false,
        ),
      );
    }

    int currentMinutes = firstPeriodH * 60 + firstPeriodM;

    int maxPeriod = 7;
    if (lessonsForDisplayDay.isNotEmpty) {
      final activeLessons = lessonsForDisplayDay.where((l) => l.subject.trim().isNotEmpty);
      if (activeLessons.isNotEmpty) {
        maxPeriod = activeLessons.map((l) => l.classTime).reduce((a, b) => a > b ? a : b);
      } else {
        maxPeriod = lessonsForDisplayDay.map((l) => l.classTime).reduce((a, b) => a > b ? a : b);
      }
    }
    if (maxPeriod < 4) maxPeriod = 7;

    DateTime? lastPeriodEndTime;

    for (int p = 1; p <= maxPeriod; p++) {
      DateTime classStart;
      DateTime classEnd;
      if (p - 1 < ts.periodStartTimes.length && ts.periodStartTimes[p - 1].contains(':')) {
        final parts = ts.periodStartTimes[p - 1].split(':');
        final ph = int.tryParse(parts[0]) ?? (currentMinutes ~/ 60);
        final pm = int.tryParse(parts[1]) ?? (currentMinutes % 60);
        classStart = DateTime(now.year, now.month, now.day, ph, pm);
        classEnd = classStart.add(Duration(minutes: ts.lessonDuration));
        currentMinutes = ph * 60 + pm + ts.lessonDuration;
      } else {
        classStart = DateTime(
          now.year,
          now.month,
          now.day,
          currentMinutes ~/ 60,
          currentMinutes % 60,
        );
        currentMinutes += ts.lessonDuration;
        classEnd = DateTime(
          now.year,
          now.month,
          now.day,
          currentMinutes ~/ 60,
          currentMinutes % 60,
        );
      }

      ranges.add(
        PeriodTimeRange(
          period: p,
          label: '$p교시',
          start: classStart,
          end: classEnd,
          isClass: true,
        ),
      );

      if (p == maxPeriod) {
        lastPeriodEndTime = classEnd;
      }

      // Check if next period has an exact start time configured
      if (p < maxPeriod && p < ts.periodStartTimes.length && ts.periodStartTimes[p].contains(':')) {
        final nextParts = ts.periodStartTimes[p].split(':');
        final nH = int.tryParse(nextParts[0]) ?? 0;
        final nM = int.tryParse(nextParts[1]) ?? 0;
        final nextStart = DateTime(now.year, now.month, now.day, nH, nM);
        if (nextStart.isAfter(classEnd)) {
          final gap = nextStart.difference(classEnd).inMinutes;
          if (gap >= 35 || p == ts.lunchAfterPeriod) {
            final pureLunch = (gap - 10).clamp(1, 180);
            final pureLunchEnd = classEnd.add(Duration(minutes: pureLunch));
            ranges.add(
              PeriodTimeRange(
                period: 0,
                label: '점심 시간',
                start: classEnd,
                end: pureLunchEnd,
                isClass: false,
              ),
            );
            ranges.add(
              PeriodTimeRange(
                period: 0,
                label: '쉬는 시간',
                start: pureLunchEnd,
                end: nextStart,
                isClass: false,
              ),
            );
          } else {
            ranges.add(
              PeriodTimeRange(
                period: 0,
                label: '쉬는 시간',
                start: classEnd,
                end: nextStart,
                isClass: false,
              ),
            );
          }
          currentMinutes = nH * 60 + nM;
          continue;
        }
      }

      if (p == ts.lunchAfterPeriod) {
        // 점심시간 10분 전부터는 다음 교시 준비 쉬는시간으로 취급
        final pureLunchMinutes = (ts.lunchDuration - 10).clamp(1, 180);
        final lunchStart = classEnd;
        final pureLunchEnd = lunchStart.add(Duration(minutes: pureLunchMinutes));
        final totalLunchEnd = lunchStart.add(Duration(minutes: ts.lunchDuration));

        ranges.add(
          PeriodTimeRange(
            period: 0,
            label: '점심 시간',
            start: lunchStart,
            end: pureLunchEnd,
            isClass: false,
          ),
        );

        ranges.add(
          PeriodTimeRange(
            period: 0,
            label: '쉬는 시간',
            start: pureLunchEnd,
            end: totalLunchEnd,
            isClass: false,
          ),
        );

        currentMinutes += ts.lunchDuration;
      } else if (p < maxPeriod) {
        final breakStart = classEnd;
        final breakEnd = breakStart.add(Duration(minutes: ts.breakDuration));
        ranges.add(
          PeriodTimeRange(
            period: 0,
            label: '쉬는 시간',
            start: breakStart,
            end: breakEnd,
            isClass: false,
          ),
        );
        currentMinutes += ts.breakDuration;
      }
    }

    final lastEnd = lastPeriodEndTime ??
        DateTime(
          now.year,
          now.month,
          now.day,
          currentMinutes ~/ 60,
          currentMinutes % 60,
        );
    final afterMinutes = ts.afternoonAssemblyAfterMinutes ?? 10;
    final durationMinutes = ts.afternoonAssemblyDuration;

    if (afterMinutes > 0) {
      final breakStart = lastEnd;
      final breakEnd = breakStart.add(Duration(minutes: afterMinutes));
      ranges.add(
        PeriodTimeRange(
          period: 0,
          label: '쉬는 시간',
          start: breakStart,
          end: breakEnd,
          isClass: false,
        ),
      );
    }

    final afternoonStart = lastEnd.add(Duration(minutes: afterMinutes));
    final afternoonEnd = afternoonStart.add(Duration(minutes: durationMinutes));
    ranges.add(
      PeriodTimeRange(
        period: -2,
        label: '종례 시간',
        start: afternoonStart,
        end: afternoonEnd,
        isClass: false,
      ),
    );

    final nightMidnight = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    if (afternoonEnd.isBefore(nightMidnight)) {
      ranges.add(
        PeriodTimeRange(
          period: -4,
          label: '방과후',
          start: afternoonEnd,
          end: nightMidnight,
          isClass: false,
        ),
      );
    }

    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
  }

  static String? getNextClassForSpecialRoom({
    required Lesson? nextLesson,
    required TimetableResult? timetableResult,
    required AppSettings settings,
  }) {
    if (nextLesson == null || timetableResult == null) return null;

    final candidates = [
      settings.selectedTeacherId.replaceAll('*', '').replaceAll(' ', '').trim(),
      settings.selectedTeacher.replaceAll('*', '').replaceAll(' ', '').trim(),
      settings.selectedTeacherName.replaceAll('*', '').replaceAll(' ', '').trim(),
    ].where((s) => s.isNotEmpty).toList();

    if (candidates.isEmpty) return null;

    final today = DateTime.now();
    final weekday = today.weekday;
    if (weekday > 5) return null;

    Map<String, int>? classInfo;
    for (final cand in candidates) {
      classInfo = timetableResult.findClassByTeacherAndPeriod(
        weekday: weekday,
        period: nextLesson.classTime,
        teacherAbbr: cand,
      );
      if (classInfo != null) break;
    }

    if (classInfo == null) return null;
    return '${classInfo['grade']}학년 ${classInfo['classNum']}반';
  }
}

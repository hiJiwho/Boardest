import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_settings.dart';
import '../models/lesson.dart';
import '../services/comcigan_service.dart';
import '../services/storage_service.dart';

/// 교사 / 교실 실시간 시간표 팝업 뷰어
class TeacherTimetablePopupDialog extends StatefulWidget {
  final double scaleFactor;
  const TeacherTimetablePopupDialog({super.key, required this.scaleFactor});

  static Future<void> show(BuildContext context, double scaleFactor) {
    return showDialog(
      context: context,
      builder: (_) => TeacherTimetablePopupDialog(scaleFactor: scaleFactor),
    );
  }

  @override
  State<TeacherTimetablePopupDialog> createState() =>
      _TeacherTimetablePopupDialogState();
}

class _TeacherTimetablePopupDialogState
    extends State<TeacherTimetablePopupDialog> {
  final StorageService _storage = StorageService();
  final ComciganService _comcigan = ComciganService();

  AppSettings? _settings;
  TimetableResult? _timetableResult;
  bool _loading = true;
  String? _error;

  Timer? _ticker;
  DateTime _now = DateTime.now();

  int _selectedMode = 0; // 0: 교사 개인 시간표, 1: 학급 시간표

  @override
  void initState() {
    super.initState();
    _loadData();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final s = await _storage.getSettings() ?? AppSettings();
      _settings = s;

      if (s.selectedSchool != null) {
        final res = await _comcigan.getTimetable(s.selectedSchool!.code);
        _timetableResult = res;
      }

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '시간표 데이터를 불러오지 못했습니다: $e';
          _loading = false;
        });
      }
    }
  }

  // 현재 교시 계산 (TimeSettings 기반)
  Map<String, dynamic> _getCurrentPeriodInfo() {
    if (_settings == null) {
      return {'period': 0, 'status': '미정', 'remaining': Duration.zero};
    }
    final ts = _settings!.timeSettings;

    final startParts = ts.firstPeriodStart.split(':');
    final startHour = int.tryParse(startParts[0]) ?? 8;
    final startMin = int.tryParse(startParts.length > 1 ? startParts[1] : '40') ?? 40;
    final firstPeriodStart = DateTime(_now.year, _now.month, _now.day, startHour, startMin);

    // 조회 시간
    final mStartParts = ts.morningAssemblyStart.split(':');
    final mEndParts = ts.morningAssemblyEnd.split(':');
    final morningStart = DateTime(_now.year, _now.month, _now.day, int.tryParse(mStartParts[0]) ?? 8, int.tryParse(mStartParts.length > 1 ? mStartParts[1] : '25') ?? 25);
    final morningEnd = DateTime(_now.year, _now.month, _now.day, int.tryParse(mEndParts[0]) ?? 8, int.tryParse(mEndParts.length > 1 ? mEndParts[1] : '40') ?? 40);

    if (_now.isBefore(morningStart)) {
      return {
        'period': -3,
        'isClass': false,
        'status': '🌅 아침시간 (조회 전)',
        'remaining': morningStart.difference(_now),
      };
    } else if (_now.isBefore(morningEnd)) {
      return {
        'period': -1,
        'isClass': false,
        'status': '🌅 조회 시간',
        'remaining': morningEnd.difference(_now),
      };
    } else if (_now.isBefore(firstPeriodStart)) {
      return {
        'period': 0,
        'isClass': false,
        'status': '☕ 쉬는시간 (1교시 준비)',
        'remaining': firstPeriodStart.difference(_now),
      };
    }

    final lessonDur = Duration(minutes: ts.lessonDuration);
    final breakDur = Duration(minutes: ts.breakDuration);
    final lunchDur = Duration(minutes: ts.lunchDuration);
    final pureLunchDur = Duration(minutes: (ts.lunchDuration - ts.breakDuration).clamp(1, 180));

    DateTime pStart = firstPeriodStart;
    DateTime? lastClassEnd;

    for (int p = 1; p <= 7; p++) {
      final pEnd = pStart.add(lessonDur);
      if (_now.isAfter(pStart) && _now.isBefore(pEnd)) {
        return {
          'period': p,
          'isClass': true,
          'status': '$p교시 수업 진행 중',
          'remaining': pEnd.difference(_now),
        };
      }

      if (p == 7) {
        lastClassEnd = pEnd;
      }

      if (p == ts.lunchAfterPeriod) {
        final pureEnd = pEnd.add(pureLunchDur);
        final totalEnd = pEnd.add(lunchDur);
        if (_now.isAfter(pEnd) && _now.isBefore(pureEnd)) {
          return {
            'period': 0,
            'isClass': false,
            'status': '🍱 점심시간',
            'remaining': pureEnd.difference(_now),
          };
        } else if (_now.isAfter(pureEnd) && _now.isBefore(totalEnd)) {
          return {
            'period': 0,
            'isClass': false,
            'status': '☕ 쉬는시간 (다음: ${p + 1}교시)',
            'remaining': totalEnd.difference(_now),
          };
        }
        pStart = totalEnd;
      } else {
        final bEnd = pEnd.add(breakDur);
        if (_now.isAfter(pEnd) && _now.isBefore(bEnd)) {
          return {
            'period': 0,
            'isClass': false,
            'status': '☕ 쉬는시간 (다음: ${p + 1}교시)',
            'remaining': bEnd.difference(_now),
          };
        }
        pStart = bEnd;
      }
    }

    // 종례 시간 (마지막 교시 종료 후 n분 후 m분 진행)
    final lastEnd = lastClassEnd ?? pStart;
    final afterMin = ts.afternoonAssemblyAfterMinutes ?? 10;
    final durMin = ts.afternoonAssemblyDuration;

    final assemblyStart = lastEnd.add(Duration(minutes: afterMin));
    final assemblyEnd = assemblyStart.add(Duration(minutes: durMin));

    if (_now.isAfter(lastEnd) && _now.isBefore(assemblyStart)) {
      return {
        'period': 0,
        'isClass': false,
        'status': '☕ 종례 준비 / 쉬는시간',
        'remaining': assemblyStart.difference(_now),
      };
    } else if (_now.isAfter(assemblyStart) && _now.isBefore(assemblyEnd)) {
      return {
        'period': -2,
        'isClass': false,
        'status': '🌆 종례 시간',
        'remaining': assemblyEnd.difference(_now),
      };
    }

    return {
      'period': 0,
      'isClass': false,
      'status': '하교 / 일과 종료',
      'remaining': Duration.zero,
    };
  }

  Lesson? _getLesson(int weekday, int period) {
    if (_timetableResult == null || _settings == null) return null;
    final teacherName = _settings!.selectedTeacherId.replaceAll('*', '').trim();
    final grade = _settings!.selectedGrade;
    final classNum = _settings!.selectedClass;

    for (final l in _timetableResult!.lessons) {
      if (l.weekday == weekday && l.classTime == period) {
        if (_selectedMode == 0) {
          // 교사 시간표
          if (teacherName.isNotEmpty &&
              l.teacher.replaceAll('*', '').trim() == teacherName) {
            return l;
          }
        } else {
          // 학급 시간표
          if (l.grade == grade && l.classNum == classNum) {
            return l;
          }
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    final info = _getCurrentPeriodInfo();
    final remSecs = (info['remaining'] as Duration).inSeconds;
    final remMin = remSecs ~/ 60;
    final remSec = remSecs % 60;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 720 * s,
        padding: EdgeInsets.all(20 * s),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(20 * s),
          border: Border.all(
            color: const Color(0xFF7F5AF0).withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7F5AF0).withOpacity(0.2),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Bar
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F5AF0).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12 * s),
                  ),
                  child: Icon(
                    Icons.calendar_today_rounded,
                    color: const Color(0xFF7F5AF0),
                    size: 20 * s,
                  ),
                ),
                SizedBox(width: 12 * s),
                Text(
                  '📅 실시간 수업 & 시간표 팝업',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 16 * s,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),

                // Mode Switcher
                Container(
                  padding: EdgeInsets.all(3 * s),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10 * s),
                  ),
                  child: Row(
                    children: [
                      _buildModeButton(0, '👨‍🏫 내 수업 시간표', s),
                      _buildModeButton(
                        1,
                        '🏫 ${_settings?.selectedGrade ?? 1}-${_settings?.selectedClass ?? 1}반 시간표',
                        s,
                      ),
                    ],
                  ),
                ),

                SizedBox(width: 8 * s),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                    size: 20 * s,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            SizedBox(height: 16 * s),

            // Live Period Header Banner
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 16 * s,
                vertical: 12 * s,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2B2C40), Color(0xFF1F202C)],
                ),
                borderRadius: BorderRadius.circular(14 * s),
                border: Border.all(
                  color: const Color(0xFF2EC4B6).withOpacity(0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    info['isClass'] == true
                        ? Icons.timer_outlined
                        : Icons.coffee_rounded,
                    color: info['isClass'] == true
                        ? const Color(0xFF2EC4B6)
                        : const Color(0xFFFFB703),
                    size: 22 * s,
                  ),
                  SizedBox(width: 10 * s),
                  Text(
                    '${info['status']}',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontSize: 14 * s,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (remSecs > 0)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10 * s,
                        vertical: 4 * s,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2EC4B6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20 * s),
                      ),
                      child: Text(
                        '남은 시간: ${remMin.toString().padLeft(2, '0')}:${remSec.toString().padLeft(2, '0')}',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF2EC4B6),
                          fontSize: 12 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            SizedBox(height: 16 * s),

            // Timetable Grid
            _loading
                ? const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(color: Color(0xFF7F5AF0)),
                  )
                : _buildTimetableGrid(s),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(int mode, String label, double s) {
    final active = _selectedMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _selectedMode = mode),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 5 * s),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF7F5AF0) : Colors.transparent,
          borderRadius: BorderRadius.circular(8 * s),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            color: active ? Colors.white : Colors.white54,
            fontSize: 11 * s,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTimetableGrid(double s) {
    final days = ['월', '화', '수', '목', '금'];
    final currentDayIndex = _now.weekday; // 1: Mon ~ 5: Fri

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12 * s),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          children: [
            // Header Row (Days)
            Row(
              children: [
                _buildHeaderCell('교시', 50 * s, s),
                for (int i = 0; i < 5; i++)
                  _buildHeaderCell(
                    days[i],
                    120 * s,
                    s,
                    isToday: currentDayIndex == i + 1,
                  ),
              ],
            ),

            // Period Rows (1 ~ 7교시)
            for (int p = 1; p <= 7; p++)
              Row(
                children: [
                  _buildHeaderCell('$p교시', 50 * s, s),
                  for (int d = 1; d <= 5; d++)
                    _buildLessonCell(d, p, 120 * s, s),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(
    String label,
    double width,
    double s, {
    bool isToday = false,
  }) {
    return Container(
      width: width,
      height: 34 * s,
      alignment: Alignment.center,
      color: isToday
          ? const Color(0xFF7F5AF0).withOpacity(0.2)
          : Colors.white.withOpacity(0.04),
      child: Text(
        label,
        style: GoogleFonts.notoSansKr(
          color: isToday ? const Color(0xFF7F5AF0) : Colors.white70,
          fontSize: 12 * s,
          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildLessonCell(int weekday, int period, double width, double s) {
    final lesson = _getLesson(weekday, period);
    final curInfo = _getCurrentPeriodInfo();
    final isCurrent =
        curInfo['period'] == period &&
        curInfo['isClass'] == true &&
        _now.weekday == weekday;

    return Container(
      width: width,
      height: 48 * s,
      margin: EdgeInsets.all(1 * s),
      padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 4 * s),
      decoration: BoxDecoration(
        color: isCurrent
            ? const Color(0xFF2EC4B6).withOpacity(0.15)
            : (lesson != null
                  ? Colors.white.withOpacity(0.04)
                  : Colors.transparent),
        borderRadius: BorderRadius.circular(6 * s),
        border: Border.all(
          color: isCurrent
              ? const Color(0xFF2EC4B6)
              : Colors.white.withOpacity(0.05),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: lesson != null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  lesson.subject,
                  style: GoogleFonts.notoSansKr(
                    color: isCurrent ? const Color(0xFF2EC4B6) : Colors.white,
                    fontSize: 12 * s,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2 * s),
                Text(
                  _selectedMode == 0
                      ? '${lesson.grade}-${lesson.classNum}반'
                      : lesson.teacher,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white54,
                    fontSize: 10 * s,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            )
          : Center(
              child: Text(
                '-',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white24,
                  fontSize: 11 * s,
                ),
              ),
            ),
    );
  }
}

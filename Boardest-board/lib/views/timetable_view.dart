import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import '../models/school.dart';
import '../models/lesson.dart';
import '../models/app_settings.dart';
import '../services/comcigan_service.dart';
import '../services/storage_service.dart';
import 'setup_wizard_view.dart';

class TimetableView extends StatefulWidget {
  final School school;
  final List<Map<String, dynamic>> apiScheduleEvents;
  final bool initialShowCalendar;

  const TimetableView({
    super.key,
    required this.school,
    this.apiScheduleEvents = const [],
    this.initialShowCalendar = false,
  });

  @override
  State<TimetableView> createState() => _TimetableViewState();
}

class _TimetableViewState extends State<TimetableView> with SingleTickerProviderStateMixin {
  final ComciganService _comciganService = ComciganService();
  final StorageService _storageService = StorageService();

  TimetableResult? _timetableResult;
  AppSettings _appSettings = AppSettings();
  bool _isLoading = true;
  String? _errorMessage;

  int _selectedGrade = 1;
  int _selectedClass = 1;
  int _selectedWeekday = 1; // 1: Mon, 2: Tue, 3: Wed, 4: Thu, 5: Fri
  bool _isWeekView = true; // Toggle between day list and weekly grid
  bool _showCalendarView = false;
  late DateTime _calendarMonth;

  late TabController _weekdayTabController;

  @override
  void initState() {
    super.initState();
    _weekdayTabController = TabController(length: 5, vsync: this);
    _showCalendarView = widget.initialShowCalendar;
    _calendarMonth = DateTime.now();
    
    // Set weekday to current day if Mon-Fri, else Monday
    final today = DateTime.now().weekday;
    _selectedWeekday = (today >= 1 && today <= 5) ? today : 1;
    _weekdayTabController.index = _selectedWeekday - 1;

    _loadSavedPreferencesAndFetch();
  }

  @override
  void dispose() {
    _weekdayTabController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPreferencesAndFetch() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch school timetable
      final rawData = await _comciganService.fetchTimetableRaw(widget.school.code);
      final result = _comciganService.parseTimetable(rawData);

      // Load saved settings
      final settings = await _storageService.getSettings();

      setState(() {
        _timetableResult = result;
        _appSettings = settings;
        _selectedGrade = settings.selectedGrade;
        _selectedClass = settings.selectedClass;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '시간표 데이터를 가져오지 못했습니다. 네트워크 상태를 확인하고 다시 시도해 주세요.';
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshTimetable() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final rawData = await _comciganService.fetchTimetableRaw(widget.school.code);
      final result = _comciganService.parseTimetable(rawData);
      setState(() {
        _timetableResult = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '시간표 갱신에 실패했습니다.';
        _isLoading = false;
      });
    }
  }

  void _openSettings() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SetupWizardView()),
    );
    
    if (result == true) {
      _loadSavedPreferencesAndFetch();
    }
  }

  List<Lesson> _getFilteredLessons() {
    if (_timetableResult == null) return [];
    
    if (_appSettings.specialClassroomMode) {
      final teacherName = _appSettings.selectedTeacher.replaceAll('*', '').trim();
      if (teacherName.isEmpty) return [];

      final rawLessons = _timetableResult!.lessons.where((lesson) {
        return lesson.teacher.replaceAll('*', '').trim() == teacherName;
      }).toList();

      return rawLessons.map((l) {
        return Lesson(
          grade: l.grade,
          classNum: l.classNum,
          weekday: l.weekday,
          classTime: l.classTime,
          subject: l.subject, // 원래 교과명 그대로 렌더링
          teacher: '${l.grade}-${l.classNum}', // 교사명 자리에 해당 학급(예: "2-3") 매핑
          classroom: l.classroom,
          isChanged: l.isChanged,
        );
      }).toList();
    } else {
      return _timetableResult!.lessons.where((lesson) {
        return lesson.grade == _selectedGrade && lesson.classNum == _selectedClass;
      }).map((l) {
        return Lesson(
          grade: l.grade,
          classNum: l.classNum,
          weekday: l.weekday,
          classTime: l.classTime,
          subject: l.subject,
          teacher: AppSettings.formatTeacherDisplayName(l.teacher), // 일반 모드는 "성 + 교사" 포맷 적용
          classroom: l.classroom,
          isChanged: l.isChanged,
        );
      }).toList();
    }
  }

  List<Lesson> _getLessonsForDay(int day) {
    return _getFilteredLessons().where((l) => l.weekday == day).toList()
      ..sort((a, b) => a.classTime.compareTo(b.classTime));
  }

  // _getHomeroomTeacher() 제거됨 (개인정보 보호)
  // _getTeacherDisplayName() 제거됨 (개인정보 보호)

  /// 수업 시간대 문자열 계산 (교사 정보와 무관, 순수 시간 계산)
  String _getCalculatedTimeRange(int period) {
    final ts = _appSettings.timeSettings;
    final timeParts = ts.firstPeriodStart.split(':');
    final startH = int.tryParse(timeParts[0]) ?? 8;
    final startM = int.tryParse(timeParts[1]) ?? 40;
    int currentMinutes = startH * 60 + startM;

    for (int p = 1; p <= period; p++) {
      int start = currentMinutes;
      int end = start + ts.lessonDuration;

      if (p == period) {
        final sH = (start ~/ 60).toString().padLeft(2, '0');
        final sM = (start % 60).toString().padLeft(2, '0');
        final eH = (end ~/ 60).toString().padLeft(2, '0');
        final eM = (end % 60).toString().padLeft(2, '0');
        return '$sH:$sM - $eH:$eM';
      }

      if (p == ts.lunchAfterPeriod) {
        currentMinutes = end + ts.lunchDuration;
      } else {
        currentMinutes = end + ts.breakDuration;
      }
    }
    return '';
  }

  void _prevMonth() {
    setState(() {
      _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);
    });
  }

  List<String> _getEventsForDay(DateTime day) {
    final list = <String>[];
    for (final ev in widget.apiScheduleEvents) {
      final date = ev['date'] as DateTime?;
      final title = ev['title'] as String?;
      if (date != null && title != null) {
        if (date.year == day.year && date.month == day.month && date.day == day.day) {
          list.add(title);
        }
      }
    }
    // Mock default events if NEIS has no records for demo
    if (list.isEmpty && widget.apiScheduleEvents.isEmpty) {
      final now = DateTime.now();
      if (day.year == now.year && day.month == now.month) {
        if (day.day == 10) list.add('수행평가 기간');
        if (day.day == 14) list.add('학부모 상담');
        if (day.day == 24) list.add('중간고사');
        if (day.day == 25) list.add('중간고사');
      }
    }
    return list;
  }

  Widget _buildCalendarView(double scale) {
    final firstDayOfMonth = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final lastDayOfMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final startWeekday = firstDayOfMonth.weekday % 7; // 0 for Sunday, 6 for Saturday

    final totalCells = ((daysInMonth + startWeekday) / 7).ceil() * 7;
    final weekDays = ['일', '월', '화', '수', '목', '금', '토'];

    // Collect upcoming events
    final allEvents = <Map<String, dynamic>>[];
    if (widget.apiScheduleEvents.isNotEmpty) {
      allEvents.addAll(widget.apiScheduleEvents);
    } else {
      final now = DateTime.now();
      allEvents.addAll([
        {'title': '수행평가 기간', 'date': DateTime(now.year, now.month, 10)},
        {'title': '학부모 상담', 'date': DateTime(now.year, now.month, 14)},
        {'title': '중간고사 시작', 'date': DateTime(now.year, now.month, 24)},
        {'title': '중간고사 종료', 'date': DateTime(now.year, now.month, 25)},
      ]);
    }
    allEvents.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    final upcomingEvents = allEvents.where((e) {
      final date = e['date'] as DateTime;
      return date.isAfter(DateTime.now().subtract(const Duration(days: 1)));
    }).take(5).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Section: Main Calendar Grid
          Expanded(
            flex: 7,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              child: Column(
                children: [
                  // Month switcher
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                        onPressed: _prevMonth,
                      ),
                      Text(
                        '${_calendarMonth.year}년 ${_calendarMonth.month}월',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                        onPressed: _nextMonth,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Weekdays headers
                  Row(
                    children: weekDays.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final dayName = entry.value;
                      Color textColor = Colors.white54;
                      if (idx == 0) textColor = const Color(0xFFEF4565); // Sunday
                      if (idx == 6) textColor = const Color(0xFF00F5D4); // Saturday

                      return Expanded(
                        child: Center(
                          child: Text(
                            dayName,
                            style: GoogleFonts.notoSansKr(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),

                  // Grid view
                  Expanded(
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        childAspectRatio: 1.2,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: totalCells,
                      itemBuilder: (context, index) {
                        final cellDayNumber = index - startWeekday + 1;
                        final isCurrentMonthDay = cellDayNumber > 0 && cellDayNumber <= daysInMonth;

                        if (!isCurrentMonthDay) {
                          return const SizedBox.shrink();
                        }

                        final dayDate = DateTime(_calendarMonth.year, _calendarMonth.month, cellDayNumber);
                        final dayEvents = _getEventsForDay(dayDate);
                        final hasEvents = dayEvents.isNotEmpty;
                        final isToday = DateTime.now().year == dayDate.year &&
                            DateTime.now().month == dayDate.month &&
                            DateTime.now().day == dayDate.day;

                        final weekdayIdx = index % 7;
                        Color dayColor = Colors.white;
                        if (weekdayIdx == 0) dayColor = const Color(0xFFEF4565);
                        if (weekdayIdx == 6) dayColor = const Color(0xFF00F5D4);

                        return Container(
                          decoration: BoxDecoration(
                            color: isToday
                                ? const Color(0xFF2EC4B6).withOpacity(0.18)
                                : Colors.white.withOpacity(0.015),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isToday
                                  ? const Color(0xFF2EC4B6)
                                  : Colors.white.withOpacity(0.04),
                              width: isToday ? 1.5 : 1,
                            ),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$cellDayNumber',
                                style: GoogleFonts.outfit(
                                  color: isToday ? Colors.white : dayColor.withOpacity(0.8),
                                  fontSize: 12,
                                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              const Spacer(),
                              if (hasEvents)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7F5AF0).withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    dayEvents.first,
                                    style: GoogleFonts.notoSansKr(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Right Section: Upcoming Events
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '다가오는 일정',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: upcomingEvents.isEmpty
                        ? Center(
                            child: Text(
                              '등록된 다가오는 일정이\n없습니다.',
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white30,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: upcomingEvents.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, idx) {
                              final ev = upcomingEvents[idx];
                              final date = ev['date'] as DateTime;
                              final dday = date.difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)).inDays;
                              final ddayLabel = dday == 0 ? 'D-Day' : 'D-$dday';

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2EC4B6).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        ddayLabel,
                                        style: GoogleFonts.outfit(
                                          color: const Color(0xFF00F5D4),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ev['title'] as String,
                                            style: GoogleFonts.notoSansKr(
                                              color: Colors.white.withOpacity(0.9),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
                                            style: GoogleFonts.outfit(
                                              color: Colors.white38,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _appSettings.scaleFactor;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0E17),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -120,
            right: -100,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2EC4B6).withOpacity(0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2CB67D).withOpacity(0.08),
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80.0, sigmaY: 80.0),
            child: Container(color: Colors.transparent),
          ),
          // Main Scroll View
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2EC4B6)),
                    ),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.notoSansKr(
                                  color: const Color(0xFFEF4565),
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2EC4B6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _loadSavedPreferencesAndFetch,
                                child: Text('다시 시도', style: GoogleFonts.notoSansKr(color: Colors.white)),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _openSettings,
                                child: Text('설정 열기', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2))),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Block
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (Navigator.canPop(context)) ...[
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                                    tooltip: '대시보드로 돌아가기',
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _showCalendarView ? '${widget.school.name} - 학사달력' : widget.school.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.notoSansKr(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            _showCalendarView
                                                ? '$_selectedGrade학년 $_selectedClass반 | 학사일정 관리'
                                                : '$_selectedGrade학년 $_selectedClass반',
                                            style: GoogleFonts.notoSansKr(
                                              color: const Color(0xFF2EC4B6),
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        _showCalendarView ? Icons.calendar_view_week_rounded : Icons.calendar_month_rounded,
                                        color: const Color(0xFF00F5D4),
                                      ),
                                      tooltip: _showCalendarView ? '시간표 보기' : '학사달력 보기',
                                      onPressed: () {
                                        setState(() {
                                          _showCalendarView = !_showCalendarView;
                                        });
                                      },
                                    ),
                                    if (!_showCalendarView) ...[
                                      IconButton(
                                        icon: Icon(
                                          _isWeekView ? Icons.calendar_view_day : Icons.grid_on,
                                          color: const Color(0xFF94A1B2),
                                        ),
                                        tooltip: _isWeekView ? '일별 보기' : '주간 보기',
                                        onPressed: () {
                                          setState(() {
                                            _isWeekView = !_isWeekView;
                                          });
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.refresh, color: Color(0xFF94A1B2)),
                                        onPressed: _refreshTimetable,
                                      ),
                                    ],
                                    IconButton(
                                      icon: const Icon(Icons.settings, color: Color(0xFF94A1B2)),
                                      tooltip: '설정 관리',
                                      onPressed: _openSettings,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Divider(color: Colors.white10),

                          // Display Views (Day or Week or Calendar)
                          Expanded(
                            child: _showCalendarView
                                ? _buildCalendarView(scale)
                                : (_isWeekView
                                    ? _buildWeekViewGrid()
                                    : _buildDayViewTabs()),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    ),
  );
  }

  /// Weekly Grid Schedule View
  Widget _buildWeekViewGrid() {
    final weekdays = ['월', '화', '수', '목', '금'];
    final Map<int, List<Lesson>> dayLessons = {};
    for (int d = 1; d <= 5; d++) {
      dayLessons[d] = _getLessonsForDay(d);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Container(
              padding: const EdgeInsets.all(16.0),
              width: constraints.maxWidth > 600 ? constraints.maxWidth : 600,
              child: Table(
                border: TableBorder.all(color: Colors.white10, width: 1, borderRadius: BorderRadius.circular(8)),
                columnWidths: const {
                  0: FixedColumnWidth(45), // Period column
                  1: FlexColumnWidth(),    // Mon
                  2: FlexColumnWidth(),    // Tue
                  3: FlexColumnWidth(),    // Wed
                  4: FlexColumnWidth(),    // Thu
                  5: FlexColumnWidth(),    // Fri
                },
                children: [
                  // Weekdays Header Row
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFF16161A)),
                    children: [
                      const TableCell(child: SizedBox(height: 40, child: Center(child: Text('')))),
                      ...weekdays.map((day) => TableCell(
                        child: SizedBox(
                          height: 40,
                          child: Center(
                            child: Text(
                              day,
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      )),
                    ],
                  ),
                  // Period rows (1 to 8)
                  ...List.generate(8, (periodIndex) {
                    final period = periodIndex + 1;
                    return TableRow(
                      children: [
                        // Period Label Cell
                        TableCell(
                          verticalAlignment: TableCellVerticalAlignment.middle,
                          child: Container(
                            height: 72,
                            color: const Color(0xFF16161A).withOpacity(0.5),
                            child: Center(
                              child: Text(
                                '$period',
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF2EC4B6),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Days cell (Mon - Fri)
                        ...List.generate(5, (dayIndex) {
                          final day = dayIndex + 1;
                          final lessons = dayLessons[day] ?? [];
                          final lesson = lessons.firstWhere(
                            (l) => l.classTime == period,
                            orElse: () => Lesson(
                              grade: _selectedGrade,
                              classNum: _selectedClass,
                              weekday: day,
                              classTime: period,
                              teacher: '',
                              subject: '',
                              classroom: '',
                              isChanged: false,
                            ),
                          );

                          final isEmpty = lesson.subject.isEmpty;

                          return TableCell(
                            child: Container(
                              height: 72,
                              color: lesson.isChanged 
                                  ? const Color(0xFFEF4565).withOpacity(0.08)
                                  : Colors.transparent,
                              padding: const EdgeInsets.all(4.0),
                              child: isEmpty
                                  ? const Center(child: Text('-'))
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          lesson.subject,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.notoSansKr(
                                            color: lesson.isChanged ? const Color(0xFFEF4565) : Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (lesson.classroom.isNotEmpty) ...[
                                          const SizedBox(height: 1),
                                          Text(
                                            lesson.classroom,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.notoSansKr(
                                              color: const Color(0xFF2CB67D),
                                              fontSize: 9,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Day View with tab selectors
  Widget _buildDayViewTabs() {
    final weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일'];

    return Column(
      children: [
        // TabBar
        TabBar(
          controller: _weekdayTabController,
          indicatorColor: const Color(0xFF2EC4B6),
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF72757E),
          labelStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 14),
          indicatorSize: TabBarIndicatorSize.label,
          tabs: weekdays.map((day) => Tab(text: day.substring(0, 1))).toList(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _weekdayTabController,
            physics: const BouncingScrollPhysics(),
            children: List.generate(5, (index) {
              final weekday = index + 1;
              final lessons = _getLessonsForDay(weekday);

              if (lessons.isEmpty) {
                return Center(
                  child: Text(
                    '등록된 수업 일정이 없습니다.',
                    style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2)),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16.0),
                physics: const BouncingScrollPhysics(),
                itemCount: lessons.length,
                itemBuilder: (context, idx) {
                  final lesson = lessons[idx];
                  
                  // Calculate dynamic time range based on TimeSettings configuration
                  final timeRange = _getCalculatedTimeRange(lesson.classTime);

                  // Extract stem to look up textbook image mapping
                  final imgPath = _appSettings.getTextbookPath(lesson.subject, grade: lesson.grade);
                  final hasImage = imgPath != null && File(imgPath).existsSync();

                  // 교사 이름 표시 제거됨 (개인정보 보호)

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: lesson.isChanged 
                            ? const Color(0xFFEF4565).withOpacity(0.3)
                            : Colors.white.withOpacity(0.06),
                        width: 1.2,
                      ),
                      boxShadow: lesson.isChanged
                          ? [
                              BoxShadow(
                                color: const Color(0xFFEF4565).withOpacity(0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                      // Render textbook image in the background with a darkened color filter for readability
                      image: hasImage
                          ? DecorationImage(
                              image: FileImage(File(imgPath)),
                              fit: BoxFit.cover,
                              colorFilter: ColorFilter.mode(
                                Colors.black.withOpacity(0.78),
                                BlendMode.srcOver,
                              ),
                            )
                          : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          // Period Number Circle
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: lesson.isChanged 
                                  ? const Color(0xFFEF4565).withOpacity(0.15)
                                  : const Color(0xFF2EC4B6).withOpacity(0.15),
                              border: Border.all(
                                color: lesson.isChanged 
                                    ? const Color(0xFFEF4565).withOpacity(0.3)
                                    : const Color(0xFF2EC4B6).withOpacity(0.3),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${lesson.classTime}',
                                style: GoogleFonts.outfit(
                                  color: lesson.isChanged ? const Color(0xFFEF4565) : const Color(0xFF2EC4B6),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          // Subject & Mapped Teacher Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      lesson.subject,
                                      style: GoogleFonts.notoSansKr(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (lesson.isChanged) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4565).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '변경',
                                          style: GoogleFonts.notoSansKr(
                                            color: const Color(0xFFEF4565),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Dynamic Calculated Time Range & Classroom
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (timeRange.isNotEmpty)
                                Text(
                                  timeRange,
                                  style: GoogleFonts.outfit(
                                    color: const Color(0xFF72757E),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              if (lesson.classroom.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2CB67D).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF2CB67D).withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    lesson.classroom,
                                    style: GoogleFonts.notoSansKr(
                                      color: const Color(0xFF2CB67D),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ),
      ],
    );
  }
}

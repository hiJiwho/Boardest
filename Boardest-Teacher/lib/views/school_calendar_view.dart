import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SchoolCalendarDialog extends StatefulWidget {
  final double scaleFactor;
  final List<Map<String, dynamic>> apiScheduleEvents;

  const SchoolCalendarDialog({
    super.key,
    required this.scaleFactor,
    required this.apiScheduleEvents,
  });

  @override
  State<SchoolCalendarDialog> createState() => _SchoolCalendarDialogState();
}

class _SchoolCalendarDialogState extends State<SchoolCalendarDialog> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime.now();
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _dialogBg => _isDark ? const Color(0xFF0F0E17).withOpacity(0.85) : Colors.white.withOpacity(0.95);
  Color get _borderColor => _isDark ? const Color(0xFF2EC4B6).withOpacity(0.3) : const Color(0xFF2EC4B6).withOpacity(0.5);
  Color get _textColor => _isDark ? Colors.white : Colors.black87;
  Color get _textColor70 => _isDark ? Colors.white70 : Colors.black54;
  Color get _textColor54 => _isDark ? Colors.white54 : Colors.black54;
  Color get _textColor38 => _isDark ? Colors.white30 : Colors.black38;
  Color get _cardColor => _isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02);
  Color get _cardBorderColor => _isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.06);

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  // Get event for a specific day
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

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;

    // Days in current month grid calculations
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final startWeekday = firstDayOfMonth.weekday % 7; // 0 for Sunday, 6 for Saturday

    final totalCells = ((daysInMonth + startWeekday) / 7).ceil() * 7;

    final weekDays = ['일', '월', '화', '수', '목', '금', '토'];

    // Collect upcoming events for right-side display
    final allEvents = <Map<String, dynamic>>[];
    if (widget.apiScheduleEvents.isNotEmpty) {
      allEvents.addAll(widget.apiScheduleEvents);
    } else {
      // Mock events fallback
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
    }).take(4).toList();

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: AlertDialog(
        backgroundColor: _dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: _borderColor, width: 1.5),
        ),
        titlePadding: EdgeInsets.fromLTRB(24 * scale, 20 * scale, 20 * scale, 8 * scale),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: Color(0xFF00F5D4)),
                SizedBox(width: 10 * scale),
                Text(
                  '학사달력',
                  style: GoogleFonts.notoSansKr(
                    color: _textColor,
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: _textColor54, size: 20 * scale),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        contentPadding: EdgeInsets.fromLTRB(20 * scale, 4 * scale, 20 * scale, 24 * scale),
        content: SizedBox(
          width: 760 * scale,
          height: 480 * scale,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Section: Main Calendar Grid
              Expanded(
                flex: 7,
                child: Column(
                  children: [
                    // Calendar header (Month switcher)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(Icons.chevron_left_rounded, color: _textColor70, size: 24 * scale),
                          onPressed: _prevMonth,
                        ),
                        Text(
                          '${_currentMonth.year}년 ${_currentMonth.month}월',
                          style: GoogleFonts.outfit(
                            color: _textColor,
                            fontSize: 20 * scale,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_right_rounded, color: _textColor70, size: 24 * scale),
                          onPressed: _nextMonth,
                        ),
                      ],
                    ),
                    SizedBox(height: 12 * scale),

                    // Weekdays headers
                    Row(
                      children: weekDays.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final dayName = entry.value;
                        Color textColor = _textColor54;
                        if (idx == 0) textColor = const Color(0xFFEF4565); // Sunday
                        if (idx == 6) textColor = const Color(0xFF00F5D4); // Saturday

                        return Expanded(
                          child: Center(
                            child: Text(
                              dayName,
                              style: GoogleFonts.notoSansKr(
                                color: textColor,
                                fontSize: 12 * scale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 8 * scale),

                    // Calendar Month days Grid
                    Expanded(
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          childAspectRatio: 1.1,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                        itemCount: totalCells,
                        itemBuilder: (context, index) {
                          final cellDayNumber = index - startWeekday + 1;
                          final isCurrentMonthDay = cellDayNumber > 0 && cellDayNumber <= daysInMonth;

                          if (!isCurrentMonthDay) {
                            return const SizedBox.shrink();
                          }

                          final dayDate = DateTime(_currentMonth.year, _currentMonth.month, cellDayNumber);
                          final dayEvents = _getEventsForDay(dayDate);
                          final hasEvents = dayEvents.isNotEmpty;
                          final isToday = DateTime.now().year == dayDate.year &&
                              DateTime.now().month == dayDate.month &&
                              DateTime.now().day == dayDate.day;

                          final weekdayIdx = index % 7;
                          Color dayColor = _textColor;
                          if (weekdayIdx == 0) dayColor = const Color(0xFFEF4565);
                          if (weekdayIdx == 6) dayColor = const Color(0xFF00F5D4);

                          return Container(
                            decoration: BoxDecoration(
                              color: isToday
                                  ? const Color(0xFF2EC4B6).withOpacity(0.18)
                                  : _cardColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isToday
                                    ? const Color(0xFF2EC4B6)
                                    : _cardBorderColor,
                                width: isToday ? 1.5 : 1,
                              ),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$cellDayNumber',
                                  style: GoogleFonts.outfit(
                                    color: isToday ? _textColor : dayColor.withOpacity(0.8),
                                    fontSize: 12 * scale,
                                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                const Spacer(),
                                if (hasEvents)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _isDark ? const Color(0xFF7F5AF0).withOpacity(0.85) : const Color(0xFF7F5AF0),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      dayEvents.first,
                                      style: GoogleFonts.notoSansKr(
                                        color: Colors.white,
                                        fontSize: 7 * scale,
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
              SizedBox(width: 20 * scale),

              // Divider
              Container(
                width: 1,
                color: _borderColor,
              ),
              SizedBox(width: 20 * scale),

              // Right Section: Upcoming events
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '다가오는 일정',
                      style: GoogleFonts.notoSansKr(
                        color: _textColor,
                        fontSize: 15 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16 * scale),
                    Expanded(
                      child: upcomingEvents.isEmpty
                          ? Center(
                              child: Text(
                                '등록된 다가오는 일정이\n없습니다.',
                                style: GoogleFonts.notoSansKr(
                                  color: _textColor38,
                                  fontSize: 12 * scale,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: upcomingEvents.length,
                              separatorBuilder: (_, __) => SizedBox(height: 10 * scale),
                              itemBuilder: (context, idx) {
                                final ev = upcomingEvents[idx];
                                final date = ev['date'] as DateTime;
                                final dday = date.difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)).inDays;
                                final ddayLabel = dday == 0 ? 'D-Day' : 'D-$dday';

                                return Container(
                                  padding: EdgeInsets.all(12 * scale),
                                  decoration: BoxDecoration(
                                    color: _cardColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _cardBorderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2EC4B6).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          ddayLabel,
                                          style: GoogleFonts.outfit(
                                            color: const Color(0xFF00F5D4),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11 * scale,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12 * scale),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              ev['title'] as String,
                                              style: GoogleFonts.notoSansKr(
                                                color: _textColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12 * scale,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
                                              style: GoogleFonts.outfit(
                                                color: _textColor38,
                                                fontSize: 10 * scale,
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
            ],
          ),
        ),
      ),
    );
  }
}

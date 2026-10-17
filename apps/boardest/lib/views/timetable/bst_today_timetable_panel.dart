import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/app_settings.dart';
import '../../models/lesson.dart';
import '../../services/timetable_schedule_calculator.dart';

/// Boardest 오늘의 시간표 패널 (좌측 세로형 교시 카드 & 교과서 배경 & 진행률 게이지)
class BstTodayTimetablePanel extends StatelessWidget {
  final List<Lesson> lessons;
  final bool isWeekend;
  final AppSettings settings;
  final PeriodTimeRange? currentPeriod;
  final Lesson? nextLesson;
  final String countdownTime;
  final double periodProgress;
  final VoidCallback onOpenWeeklyTimetable;
  final ValueChanged<Lesson> onSelectLesson;
  final String Function(int period) getPeriodTimeString;
  final ImageProvider? Function(String? path, {String? subject}) getAdaptiveImageProvider;

  const BstTodayTimetablePanel({
    super.key,
    required this.lessons,
    required this.isWeekend,
    required this.settings,
    required this.currentPeriod,
    required this.nextLesson,
    required this.countdownTime,
    required this.periodProgress,
    required this.onOpenWeeklyTimetable,
    required this.onSelectLesson,
    required this.getPeriodTimeString,
    required this.getAdaptiveImageProvider,
  });

  @override
  Widget build(BuildContext context) {
    final scale = settings.scaleFactor;

    if (settings.isLearningLab) {
      final labName = settings.classNickname.isNotEmpty ? settings.classNickname : '교수학습실';
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF081714),
          borderRadius: BorderRadius.circular(24 * scale),
          border: Border.all(
            color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
            width: 1.2,
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 14 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                labName,
                style: GoogleFonts.notoSansKr(
                  fontSize: 17 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            SizedBox(height: 12 * scale),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(16 * scale),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2EC4B6).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF2EC4B6).withValues(alpha: 0.3)),
                      ),
                      child: Icon(Icons.school_rounded, color: const Color(0xFF2EC4B6), size: 36 * scale),
                    ),
                    SizedBox(height: 12 * scale),
                    Text(
                      '교수학습 전용 공간',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 15 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4 * scale),
                    Text(
                      '정규 수업 시간표 없음',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white38,
                        fontSize: 12 * scale,
                      ),
                    ),
                    SizedBox(height: 16 * scale),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A),
                        borderRadius: BorderRadius.circular(8 * scale),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mail_outline_rounded, color: const Color(0xFF00F5D4), size: 14 * scale),
                          SizedBox(width: 6 * scale),
                          Text(
                            '쪽지 수신 가능',
                            style: GoogleFonts.notoSansKr(
                              color: const Color(0xFF00F5D4),
                              fontSize: 11 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 6 * scale),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A),
                        borderRadius: BorderRadius.circular(8 * scale),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.widgets_outlined, color: const Color(0xFF2EC4B6), size: 14 * scale),
                          SizedBox(width: 6 * scale),
                          Text(
                            'BST 스마트 도구 사용 가능',
                            style: GoogleFonts.notoSansKr(
                              color: const Color(0xFF2EC4B6),
                              fontSize: 11 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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

    final displayLessons = List<Lesson>.from(lessons);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081714),
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(
          color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
          width: 1.2,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 14 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 10 * scale),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10 * scale),
                  child: Image.asset(
                    'assets/icons/app_logo.png',
                    width: 38 * scale,
                    height: 38 * scale,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: 38 * scale,
                      height: 38 * scale,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10 * scale),
                      ),
                      child: Icon(Icons.dashboard_rounded, color: const Color(0xFF00F5D4), size: 22 * scale),
                    ),
                  ),
                ),
                SizedBox(width: 10 * scale),
                Expanded(
                  child: GestureDetector(
                    onTap: onOpenWeeklyTimetable,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              'Boardest',
                              style: GoogleFonts.outfit(
                                fontSize: 18 * scale,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(width: 6 * scale),
                            Text(
                              'by Jiwho',
                              style: GoogleFonts.outfit(
                                fontSize: 9 * scale,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF00F5D4),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          isWeekend ? '월요일 시간표' : '오늘의 시간표',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13 * scale,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onOpenWeeklyTimetable,
                  icon: Icon(Icons.calendar_month_rounded, color: Colors.white38, size: 18 * scale),
                  tooltip: '주간 시간표',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          SizedBox(height: 8 * scale),
          Expanded(
            child: displayLessons.isEmpty
                ? Center(
                    child: Text(
                      isWeekend ? '주말에는 수업이 없습니다' : '수업 일정이 없습니다',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white38,
                        fontSize: 13 * scale,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(displayLessons.length > 7 ? 7 : displayLessons.length, (index) {
                      final lesson = displayLessons[index];
                      final isCurrent = currentPeriod?.isClass == true && currentPeriod?.period == lesson.classTime;
                      final isNextInBreak =
                          currentPeriod != null && !currentPeriod!.isClass && nextLesson?.classTime == lesson.classTime;
                      final isLast = index == (displayLessons.length > 7 ? 6 : displayLessons.length - 1);
                      final subject = lesson.subject.isNotEmpty ? lesson.subject : '${lesson.classTime}교시';
                      final timeStr = getPeriodTimeString(lesson.classTime);
                      final textbookPath =
                          lesson.subject.isNotEmpty ? settings.getTextbookPath(lesson.subject) : null;
                      final imgProvider = getAdaptiveImageProvider(textbookPath, subject: lesson.subject);

                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(bottom: isLast ? 0 : 8 * scale),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                if (lesson.subject.isNotEmpty) {
                                  onSelectLesson(lesson);
                                }
                              },
                              borderRadius: BorderRadius.circular(14 * scale),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? const Color(0xFF004D40)
                                      : (isNextInBreak ? const Color(0xFF0A3029) : const Color(0xFF0F2622)),
                                  borderRadius: BorderRadius.circular(14 * scale),
                                  border: Border.all(
                                    color: isCurrent
                                       ? const Color(0xFF00F5D4)
                                       : (isNextInBreak
                                           ? const Color(0xFF2EC4B6).withValues(alpha: 0.7)
                                           : const Color(0xFF2EC4B6).withValues(alpha: 0.35)),
                                    width: isCurrent ? 2.0 : 1.2,
                                  ),
                                  image: imgProvider != null
                                      ? DecorationImage(
                                          image: imgProvider,
                                          fit: BoxFit.cover,
                                          colorFilter: ColorFilter.mode(
                                            (isCurrent ? const Color(0xFF003830) : const Color(0xFF081714))
                                                .withValues(alpha: 0.85),
                                            BlendMode.srcOver,
                                          ),
                                        )
                                      : null,
                                  boxShadow: isCurrent
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFF00F5D4).withValues(alpha: 0.4),
                                            blurRadius: 12 * scale,
                                            spreadRadius: 2 * scale,
                                          ),
                                        ]
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.3),
                                            blurRadius: 3 * scale,
                                            offset: Offset(0, 1.5 * scale),
                                          ),
                                        ],
                                ),
                                child: Stack(
                                  children: [
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: EdgeInsets.symmetric(
                                                      horizontal: 5 * scale,
                                                      vertical: 1.5 * scale,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: isCurrent ? const Color(0xFF00F5D4) : Colors.white12,
                                                      borderRadius: BorderRadius.circular(4 * scale),
                                                    ),
                                                    child: Text(
                                                      '${lesson.classTime}교시',
                                                      style: GoogleFonts.outfit(
                                                        color: isCurrent ? Colors.black : Colors.white70,
                                                        fontSize: 11 * scale,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  if (timeStr.isNotEmpty) ...[
                                                    SizedBox(width: 4 * scale),
                                                    Text(
                                                      timeStr,
                                                      style: GoogleFonts.outfit(
                                                        color: Colors.white54,
                                                        fontSize: 9.5 * scale,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              if (isCurrent && countdownTime.isNotEmpty) ...[
                                                Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 5 * scale,
                                                    vertical: 1.5 * scale,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF00F5D4).withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(4 * scale),
                                                    border: Border.all(color: const Color(0xFF00F5D4), width: 0.8),
                                                  ),
                                                  child: Text(
                                                    '$countdownTime 남음',
                                                    style: GoogleFonts.notoSansKr(
                                                      color: const Color(0xFF00F5D4),
                                                      fontSize: 9.5 * scale,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ] else if (isNextInBreak) ...[
                                                Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 5 * scale,
                                                    vertical: 1.5 * scale,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF2EC4B6).withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(4 * scale),
                                                  ),
                                                  child: Text(
                                                    '다음 수업',
                                                    style: GoogleFonts.notoSansKr(
                                                      color: const Color(0xFF74F8E5),
                                                      fontSize: 9.5 * scale,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  settings.specialClassroomMode
                                                      ? '${lesson.grade}학년 ${lesson.classNum}반'
                                                      : subject,
                                                  style: GoogleFonts.notoSansKr(
                                                    color: isCurrent ? const Color(0xFF00F5D4) : Colors.white,
                                                    fontSize: (settings.specialClassroomMode ? 18.0 : 21.0) * scale,
                                                    fontWeight: FontWeight.w900,
                                                    shadows: [
                                                      Shadow(
                                                        color: Colors.black.withValues(alpha: 0.9),
                                                        blurRadius: 4,
                                                      ),
                                                    ],
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                if (settings.specialClassroomMode && lesson.subject.isNotEmpty)
                                                  Text(
                                                    lesson.subject,
                                                    style: GoogleFonts.notoSansKr(
                                                      color: isCurrent ? const Color(0xFF74F8E5) : Colors.white70,
                                                      fontSize: 11 * scale,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(height: 2 * scale),
                                        ],
                                      ),
                                    ),
                                    if (isCurrent) ...[
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.only(
                                            bottomLeft: Radius.circular(14 * scale),
                                            bottomRight: Radius.circular(14 * scale),
                                          ),
                                          child: LinearProgressIndicator(
                                            value: periodProgress,
                                            minHeight: 3.5 * scale,
                                            backgroundColor: Colors.white12,
                                            valueColor: const AlwaysStoppedAnimation(Color(0xFF00F5D4)),
                                          ),
                                        ),
                                      ),
                                    ] else if (isNextInBreak) ...[
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.only(
                                            bottomLeft: Radius.circular(14 * scale),
                                            bottomRight: Radius.circular(14 * scale),
                                          ),
                                          child: LinearProgressIndicator(
                                            value: periodProgress,
                                            minHeight: 2.5 * scale,
                                            backgroundColor: Colors.white12,
                                            valueColor: const AlwaysStoppedAnimation(Color(0xFF2EC4B6)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
          ),
        ],
      ),
    );
  }
}

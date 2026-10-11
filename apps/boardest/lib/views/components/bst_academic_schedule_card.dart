import 'package:flutter/material.dart';

class AcademicEventItem {
  final String title;
  final String dDay;
  final Color? badgeColor;

  const AcademicEventItem({
    required this.title,
    required this.dDay,
    this.badgeColor,
  });
}

class BstAcademicScheduleCard extends StatelessWidget {
  final String dateString;
  final String currentPeriodStatus;
  final List<AcademicEventItem> events;
  final VoidCallback? onTap;

  const BstAcademicScheduleCard({
    super.key,
    required this.dateString,
    required this.currentPeriodStatus,
    this.events = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 상단: 오늘 날짜 + 현재 교시 및 남은 시간
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Row(
                children: [
                  const Text('📅 ', style: TextStyle(fontSize: 12)),
                  Text(
                    dateString,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00F5D4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    currentPeriodStatus,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF00F5D4),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // 2. 하단: 학사일정 D-Day 목록
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🎯 학사일정 D-Day',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFF8906),
                  ),
                ),
                Text(
                  '전체보기 ›',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            Expanded(
              child: events.isEmpty
                  ? Center(
                      child: Text(
                        '등록된 학사일정이 없습니다.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 5),
                      itemBuilder: (context, index) {
                        final ev = events[index];
                        final badgeColor = ev.badgeColor ?? const Color(0xFFFF8906);
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                ev.title,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFE2E8F0),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: badgeColor.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: badgeColor.withOpacity(0.4)),
                              ),
                              child: Text(
                                ev.dDay,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: badgeColor,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

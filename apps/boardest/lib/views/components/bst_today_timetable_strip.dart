import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';

class TimetablePeriodItem {
  final int period;
  final String subject;
  final bool isCurrent;
  final String? targetClass;

  const TimetablePeriodItem({
    required this.period,
    required this.subject,
    this.isCurrent = false,
    this.targetClass,
  });
}

class BstTodayTimetableStrip extends StatelessWidget {
  final List<TimetablePeriodItem> periods;
  final ValueChanged<int>? onPeriodTap;
  final String? Function(String subject)? getTextbookPath;
  final Uint8List? Function(String subject)? getTextbookBytes;
  final bool isSpecialRoom;

  const BstTodayTimetableStrip({
    super.key,
    required this.periods,
    this.onPeriodTap,
    this.getTextbookPath,
    this.getTextbookBytes,
    this.isSpecialRoom = false,
  });

  Color _getSubjectColor(String subject) {
    if (subject.contains('국어') || subject.contains('문학')) return const Color(0xFFEF4444);
    if (subject.contains('수학')) return const Color(0xFF3B82F6);
    if (subject.contains('영어')) return const Color(0xFF10B981);
    if (subject.contains('과학') || subject.contains('물리') || subject.contains('화학') || subject.contains('생물') || subject.contains('지구')) return const Color(0xFF8B5CF6);
    if (subject.contains('사회') || subject.contains('역사') || subject.contains('도덕') || subject.contains('지리')) return const Color(0xFFF59E0B);
    if (subject.contains('체육') || subject.contains('스포츠')) return const Color(0xFF06B6D4);
    if (subject.contains('음악')) return const Color(0xFFEC4899);
    if (subject.contains('미술')) return const Color(0xFFF97316);
    if (subject.contains('정보') || subject.contains('컴퓨터') || subject.contains('기술')) return const Color(0xFF14B8A6);
    return const Color(0xFF6366F1);
  }

  String _getSubjectIcon(String subject) {
    if (subject.contains('국어') || subject.contains('문학')) return '📖';
    if (subject.contains('수학')) return '📐';
    if (subject.contains('영어')) return '🔤';
    if (subject.contains('과학') || subject.contains('물리') || subject.contains('화학') || subject.contains('생물')) return '🔬';
    if (subject.contains('사회') || subject.contains('역사') || subject.contains('도덕') || subject.contains('지리')) return '🌏';
    if (subject.contains('체육') || subject.contains('스포츠')) return '⚽';
    if (subject.contains('음악')) return '🎵';
    if (subject.contains('미술')) return '🎨';
    if (subject.contains('정보') || subject.contains('컴퓨터') || subject.contains('기술')) return '💻';
    return '📘';
  }

  Widget _buildTextbookCover(String subject, String? imagePath, Uint8List? imageBytes, Color subjectColor) {
    if (imageBytes != null && imageBytes.isNotEmpty) {
      return Container(
        color: const Color(0xFF070B14),
        padding: const EdgeInsets.all(4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _buildFallbackCover(subject, subjectColor),
          ),
        ),
      );
    }
    if (imagePath != null && imagePath.isNotEmpty) {
      if (!kIsWeb && File(imagePath).existsSync()) {
        return Container(
          color: const Color(0xFF070B14),
          padding: const EdgeInsets.all(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(imagePath),
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _buildFallbackCover(subject, subjectColor),
            ),
          ),
        );
      } else if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        return Container(
          color: const Color(0xFF070B14),
          padding: const EdgeInsets.all(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              imagePath,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _buildFallbackCover(subject, subjectColor),
            ),
          ),
        );
      }
    }
    return _buildFallbackCover(subject, subjectColor);
  }

  Widget _buildFallbackCover(String subject, Color color) {
    final icon = _getSubjectIcon(subject);
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Stack(
        children: [
          // 배경 패턴 장식
          Positioned(
            right: -6,
            bottom: -6,
            child: Text(
              icon,
              style: TextStyle(
                fontSize: 34,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 2),
                Text(
                  '교과서',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (periods.isEmpty) {
      return Container(
        height: 110,
        alignment: Alignment.center,
        child: Text(
          '오늘 등록된 시간표 일과가 없습니다.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final cardSize = totalHeight > 0 ? totalHeight : 96.0;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.start,
            children: List.generate(periods.length, (index) {
              final item = periods[index];
              final subjectColor = _getSubjectColor(item.subject);
              final imagePath = getTextbookPath?.call(item.subject);
              final imageBytes = getTextbookBytes?.call(item.subject);

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: cardSize, // 과목당 1:1 비율 (정사각형)
                  height: cardSize,
                  child: InkWell(
                    onTap: () => onPeriodTap?.call(item.period),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      decoration: BoxDecoration(
                        color: item.isCurrent
                            ? const Color(0xFF0F1E2E)
                            : const Color(0xFF0B101B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: item.isCurrent
                              ? const Color(0xFF00F5D4)
                              : Colors.white.withValues(alpha: 0.1),
                          width: item.isCurrent ? 2 : 1,
                        ),
                        boxShadow: item.isCurrent
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF00F5D4).withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. 좌측: 교과서 높이 꽉 차게 (좌측 : 우측 = 3 : 1)
                            Expanded(
                              flex: 3,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildTextbookCover(item.subject, imagePath, imageBytes, subjectColor),
                                  if (isSpecialRoom && (item.targetClass?.isNotEmpty == true))
                                    Positioned(
                                      left: 2,
                                      right: 2,
                                      bottom: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F1E2E).withValues(alpha: 0.94),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFF00F5D4), width: 1),
                                        ),
                                        child: Text(
                                          item.targetClass!,
                                          style: const TextStyle(
                                            color: Color(0xFF00F5D4),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                          ),
                                          maxLines: 1,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // 구분선
                            Container(
                              width: 1,
                              color: Colors.white.withValues(alpha: 0.08),
                            ),

                            // 2. 우측: 1.국어 시계방향 90도 회전 (flex: 1)
                            Expanded(
                              flex: 1,
                              child: Container(
                                color: item.isCurrent
                                    ? const Color(0xFF00F5D4).withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.03),
                                alignment: Alignment.center,
                                child: RotatedBox(
                                  quarterTurns: 1, // 시계방향 90도 회전
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${item.period}.',
                                        style: TextStyle(
                                          color: item.isCurrent ? const Color(0xFF00F5D4) : subjectColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        item.subject,
                                        style: TextStyle(
                                          color: item.isCurrent ? Colors.white : const Color(0xFFE2E8F0),
                                          fontSize: 12,
                                          fontWeight: item.isCurrent ? FontWeight.w900 : FontWeight.w700,
                                          letterSpacing: -0.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (item.isCurrent) ...[
                                        const SizedBox(width: 4),
                                        const Text(
                                          '●',
                                          style: TextStyle(
                                            color: Color(0xFF00F5D4),
                                            fontSize: 8,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

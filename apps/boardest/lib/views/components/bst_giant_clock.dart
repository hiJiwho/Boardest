import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

/// Boardest 전자칠판 미니멀 심플 디지털 시계
/// - 상단: 날짜 크게 & D-Day 뱃지 (꾹 누르면 학교 일정 선택 변경)
/// - 중앙: 시:분:초 전체 동일한 크기의 흰색 Bold 폰트
/// - 하단: 남은 시간 텍스트 (몇 분 몇 초) + 실시간 프로그레스 줄(게이지 라인)
class BstGiantClock extends StatefulWidget {
  final Color accentColor;
  final VoidCallback? onLongPress;
  final VoidCallback? onDdayLongPress;
  final String? dateLabel;
  final String? ddayLabel;
  final String? remainingTimeText;
  final double? remainingProgress;

  const BstGiantClock({
    super.key,
    this.accentColor = const Color(0xFF00F5D4),
    this.onLongPress,
    this.onDdayLongPress,
    this.dateLabel,
    this.ddayLabel,
    this.remainingTimeText,
    this.remainingProgress,
  });

  @override
  State<BstGiantClock> createState() => _BstGiantClockState();
}

class _BstGiantClockState extends State<BstGiantClock> {
  late DateTime _currentTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDate(DateTime d) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[d.weekday - 1];
    return '${d.month}월 ${d.day}일 ($wd)';
  }

  @override
  Widget build(BuildContext context) {
    final h = _currentTime.hour.toString().padLeft(2, '0');
    final m = _currentTime.minute.toString().padLeft(2, '0');
    final s = _currentTime.second.toString().padLeft(2, '0');
    final dateDisplay = widget.dateLabel ?? _formatDate(_currentTime);

    final progress = (widget.remainingProgress ?? 0.0).clamp(0.0, 1.0);

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Tooltip(
        message: '시계를 길게 누르면 날짜 및 시간 변경(디버깅)이 가능합니다',
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1322),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 상단: 날짜 크게 & D-day 뱃지 (꾹 누르면 학교 일정 선택)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 날짜 크게
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 16, color: widget.accentColor),
                      const SizedBox(width: 8),
                      Text(
                        dateDisplay,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),

                  // D-day 뱃지 (꾹 누르면 학교 일정 선택)
                  GestureDetector(
                    onLongPress: widget.onDdayLongPress,
                    onTap: widget.onDdayLongPress,
                    child: Tooltip(
                      message: '길게 누르면 학교 일정 중에서 D-Day를 변경할 수 있습니다',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: widget.accentColor.withValues(alpha: 0.45),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.flag_rounded, size: 13, color: widget.accentColor),
                            const SizedBox(width: 5),
                            Text(
                              (widget.ddayLabel != null && widget.ddayLabel!.isNotEmpty)
                                  ? widget.ddayLabel!
                                  : 'D-Day 설정',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: widget.accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // 2. 중앙: 시:분:초 대형 폰트 + 우측 원형 남은 시간 게이지 & D-day
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '$h:$m:$s',
                            style: const TextStyle(
                              fontSize: 64,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -1.5,
                              fontFeatures: [FontFeature.tabularFigures()],
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // 원형 남은 시간 인디케이터
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 58,
                          height: 58,
                          child: CircularProgressIndicator(
                            value: progress > 0 ? progress : 0.05,
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
                            strokeWidth: 5.5,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(progress * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: widget.accentColor,
                              ),
                            ),
                            Text(
                              '남음',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 3. 하단: 남은 시간 텍스트 (몇 분 몇 초) + 실시간 프로그레스 게이지 줄
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_bottom_rounded, size: 13, color: widget.accentColor),
                          const SizedBox(width: 6),
                          Text(
                            (widget.remainingTimeText != null && widget.remainingTimeText!.isNotEmpty)
                                ? widget.remainingTimeText!
                                : '일과 시간표 진행 중',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                      if (widget.remainingProgress != null)
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: widget.accentColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 실시간 진행도 줄 게이지 (Progress Line)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 5,
                      color: Colors.white.withValues(alpha: 0.08),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress > 0 ? progress : 0.01,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.accentColor.withValues(alpha: 0.6),
                                widget.accentColor,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

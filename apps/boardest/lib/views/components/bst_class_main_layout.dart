import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';
import '../../models/meal_models.dart';
import '../../models/app_settings.dart' show LauncherSlot;
import 'bst_today_timetable_strip.dart' show TimetablePeriodItem;
import 'bst_tools_dock.dart' show BstToolType, BstToolsDock;

export 'bst_today_timetable_strip.dart';
export 'bst_tools_dock.dart';
export '../../models/meal_models.dart';
export '../../models/app_settings.dart' show LauncherSlot;

const _amber = Color(0xFFFFC857);

/// Boardest Class 4.2.0 Golden Layout
/// - 좌측 원통형 물레방아 시간표 (거리별 폭 축소 애니메이션)
/// - 대형 교과서 커버 + 하단 전폭 진행도 바 (교과서/필기시작 버튼 제거)
/// - 수업 중: 초 없는 대형 HH:mm 시계(260px 높이, 수업종료 문구 제외) + 여백 넉넉한 도구함 그리드
///   - 도구함에서 '급식' 클릭 시 급식 식단표 오버레이 화면 전환 및 복귀 버튼
/// - 수업 중 + Cloud/USB 연결: 리스트형 파일함 + 하단 1줄 가로 도구함
/// - 쉬는 시간: 초 포함 순백색 시계(360px) + '쉬는 시간 종료까지 남은 시간' 표기
///   - 미연결: 바닥 끝까지 시원하게 다 쓰는 급식 식단표(폰트 25px) + 우측 세로 독 도구함
///   - 연결: 급식 위치에 리스트형 USB/Cloud 파일함(급식 탭 전환 가능) + 우측 세로 독 도구함
class BstClassMainLayout extends StatefulWidget {
  final String appName;
  final String schoolName;
  final String gradeClass;
  final List<TimetablePeriodItem> periods;
  final ValueChanged<int>? onPeriodTap;
  final String? Function(String subject)? getTextbookPath;
  final Uint8List? Function(String subject)? getTextbookBytes;

  final String dateString;
  final String? ddayLabel;
  final VoidCallback? onDdayLongPress;
  final String currentPeriodStatus;
  final VoidCallback? onClockLongPress;
  final String? clockRemainingDetailText;
  final double? clockRemainingProgress;

  final String currentSubject;
  final String subjectDescription;
  final String nextSubject;
  final String nextSubjectRoom;
  final String subjectIcon;
  final String? currentTextbookImagePath;
  final Uint8List? currentTextbookBytes;
  final String? remainingTimeText;
  final VoidCallback? onLessonInfoTap;

  final List<MealDishItem> todayDishes;
  final String todayCalories;
  final List<MealDishItem> tomorrowDishes;
  final String tomorrowCalories;
  final String tomorrowDateLabel;
  final DateTime? currentTime;
  final TimeOfDay lunchStartTime;
  final TimeOfDay lunchEndTime;
  final Future<void> Function(String dishName)? onMealVote;
  final ValueChanged<String>? onShowVoteBreakdown;
  final bool isCloudActive;
  final VoidCallback? onCloudToggle;

  // 전용 교실 모드 지원
  final bool isSpecialRoom;
  final String? specialSubjectName;

  // Cloud 탐색기 인라인 표시
  final bool showCloudFiles;
  final Widget? cloudFilesWidget;

  final bool isPro;
  final bool isWindows;
  final double scaleFactor;
  final VoidCallback? onLogoTap;
  final ValueChanged<BstToolType>? onToolTap;
  final VoidCallback? onAddAppTap;
  final VoidCallback? onMinimizeTap;
  final VoidCallback? onCloseTap;
  final List<LauncherSlot>? customSlots;
  final ValueChanged<LauncherSlot>? onLaunchApp;
  final ValueChanged<int>? onRemoveApp;
  final ValueChanged<int>? onAddAppToSlot;

  const BstClassMainLayout({
    super.key,
    this.appName = 'Class',
    this.schoolName = '보데스트 중학교',
    this.gradeClass = '1학년 7반',
    this.periods = const [],
    this.onPeriodTap,
    this.getTextbookPath,
    this.getTextbookBytes,
    this.onLogoTap,
    required this.dateString,
    this.ddayLabel,
    this.onDdayLongPress,
    required this.currentPeriodStatus,
    this.onClockLongPress,
    this.clockRemainingDetailText,
    this.clockRemainingProgress,
    required this.currentSubject,
    this.subjectDescription = '',
    required this.nextSubject,
    this.nextSubjectRoom = '',
    this.subjectIcon = '📘',
    this.currentTextbookImagePath,
    this.currentTextbookBytes,
    this.remainingTimeText,
    this.onLessonInfoTap,
    required this.todayDishes,
    this.todayCalories = '',
    required this.tomorrowDishes,
    this.tomorrowCalories = '',
    this.tomorrowDateLabel = '내일',
    this.currentTime,
    this.lunchStartTime = const TimeOfDay(hour: 12, minute: 30),
    this.lunchEndTime = const TimeOfDay(hour: 13, minute: 20),
    this.onMealVote,
    this.onShowVoteBreakdown,
    this.isCloudActive = false,
    this.onCloudToggle,
    this.isSpecialRoom = false,
    this.specialSubjectName,
    this.showCloudFiles = false,
    this.cloudFilesWidget,
    this.isPro = false,
    this.isWindows = false,
    this.scaleFactor = 1.0,
    this.onToolTap,
    this.onAddAppTap,
    this.onMinimizeTap,
    this.onCloseTap,
    this.customSlots,
    this.onLaunchApp,
    this.onRemoveApp,
    this.onAddAppToSlot,
  });

  @override
  State<BstClassMainLayout> createState() => _BstClassMainLayoutState();
}

class _BstClassMainLayoutState extends State<BstClassMainLayout> {
  int _curIndex = 0;
  bool _showClassMeal = false;
  int _recessTab = 0; // 0: USB/Cloud, 1: 급식

  static const _defaultPeriodTimes = [
    ('09:00', '09:50'),
    ('10:00', '10:50'),
    ('11:00', '11:50'),
    ('12:00', '12:50'),
    ('13:40', '14:30'),
    ('14:40', '15:30'),
  ];

  static const _defaultTools = <(IconData, String, String, Color, BstToolType)>[
    (Icons.edit_rounded, '판서', '무한 캔버스 판서', Color(0xFF00F5D4), BstToolType.pen),
    (Icons.timer_outlined, '타이머', '수업 집중 타이머', Color(0xFFFFC857), BstToolType.timer),
    (Icons.casino_outlined, '추첨', '발표자 번호 추첨', Color(0xFFFF6B6B), BstToolType.random),
    (Icons.calculate_outlined, '계산기', '공학용 수식 계산', Color(0xFF4D96FF), BstToolType.calculator),
    (Icons.restaurant_rounded, '급식', '오늘 점심 식단표 확인', Color(0xFF00C896), BstToolType.web),
    (Icons.cloud_outlined, 'Cloud', '수업 자료 클라우드', Color(0xFF7F5AF0), BstToolType.cloud),
  ];

  static const _sampleFiles = <(String, String, String, Color, IconData)>[
    ('수학I_03단원_삼각함수.pdf', 'PDF', '3.4 MB', Color(0xFFFF6B6B), Icons.picture_as_pdf_rounded),
    ('2026_모의고사_기출분석.pptx', 'PPT', '8.9 MB', Color(0xFFFF8906), Icons.slideshow_rounded),
    ('[전자교과서] 수학I 비상', 'TBP', '45 MB', Color(0xFF7F5AF0), Icons.auto_stories_rounded),
    ('함수의극한_인터랙티브', 'HTMLP', '3.1 MB', Color(0xFF00C4CC), Icons.co_present_rounded),
    ('10월19일_판서노트.pen', 'PEN', '5.1 MB', Color(0xFF00C896), Icons.draw_rounded),
    ('수학I_수행평가_학습지.hwpx', 'HWP', '1.8 MB', Color(0xFF4D96FF), Icons.description_rounded),
  ];

  TextStyle _ts(double size, {FontWeight w = FontWeight.w700, Color c = Colors.white, double? h, double? ls}) {
    return TextStyle(
      fontFamily: 'SiwonhanSeolreim',
      fontSize: size,
      fontWeight: w,
      color: c,
      height: h,
      letterSpacing: ls,
    );
  }

  Widget _glassSurface({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    double radius = 20,
    bool glow = false,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF141721).withOpacity(0.85),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: glow ? const Color(0xFF00F5D4).withOpacity(0.5) : Colors.white.withOpacity(0.12),
          width: glow ? 1.5 : 1.0,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: const Color(0xFF00F5D4).withOpacity(0.18),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );
  }

  Widget _glassTile({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    double radius = 14,
    bool selected = false,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF00F5D4).withOpacity(0.14) : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? const Color(0xFF00F5D4).withOpacity(0.45) : Colors.white.withOpacity(0.08),
        ),
      ),
      child: child,
    );
  }

  bool get _isClassTime {
    final status = widget.currentPeriodStatus.trim();
    if (status.contains('진행 중') || status.contains('수업 중')) return true;
    if (status.contains('준비') || status.contains('쉬는') || status.contains('종료')) return false;
    return widget.currentSubject.isNotEmpty && widget.currentSubject != '수업 없음';
  }

  List<TimetablePeriodItem> get _effectivePeriods {
    if (widget.periods.isNotEmpty) return widget.periods;
    return List.generate(
      6,
      (i) => TimetablePeriodItem(
        period: i + 1,
        subject: ['국어', '수학', '영어', '과학', '사회', '체육'][i],
        isCurrent: i == 3,
        targetClass: widget.gradeClass,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initCurrentPeriod();
  }

  @override
  void didUpdateWidget(covariant BstClassMainLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPeriodStatus != widget.currentPeriodStatus ||
        oldWidget.currentSubject != widget.currentSubject) {
      _initCurrentPeriod();
    }
  }

  void _initCurrentPeriod() {
    final ep = _effectivePeriods;
    final idx = ep.indexWhere((p) => p.isCurrent);
    if (idx != -1) {
      _curIndex = idx;
    } else {
      _curIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 좌측 물레방아 시간표 (너비 820px, 좌측 밀착)
              SizedBox(
                width: 820,
                child: _leftWheelArea(),
              ),
              const SizedBox(width: 20),
              // 2. 우측 시계 + 도구함 / 파일함 / 급식 식단표
              Expanded(
                child: _rightContentArea(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────── 1. 좌측 물레방아 시간표 ─────────
  Widget _leftWheelArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _brandBadge(),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, bc) => _buildWheel(bc),
          ),
        ),
      ],
    );
  }

  Widget _brandBadge() {
    final title = widget.isSpecialRoom
        ? (widget.specialSubjectName ?? '전용 교실')
        : '${widget.schoolName}  ·  ${widget.gradeClass}';

    return _glassSurface(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF00F5D4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('bt', style: _ts(17, w: FontWeight.w900, c: Colors.black)),
          ),
          const SizedBox(width: 10),
          Text('BOARDEST Class', style: _ts(17, w: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF00F5D4).withOpacity(0.16),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF00F5D4), width: 1),
            ),
            child: Text('PRO', style: _ts(11, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
          ),
          const SizedBox(width: 16),
          Text(
            title,
            style: _ts(15, w: FontWeight.w700, c: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildWheel(BoxConstraints bc) {
    final H = bc.maxHeight;
    final W = bc.maxWidth;
    final ep = _effectivePeriods;
    final n = ep.length.clamp(1, 10);
    const g = 10.0;
    const hc = 74.0;
    final hcur = (H - (n - 1) * (hc + g)).clamp(220.0, H);

    double topOf(int i) {
      if (i < _curIndex) return i * (hc + g);
      if (i == _curIndex) return _curIndex * (hc + g);
      return _curIndex * (hc + g) + hcur + g + (i - _curIndex - 1) * (hc + g);
    }

    final items = <Widget>[];
    for (int i = 0; i < n; i++) {
      final h = i == _curIndex ? hcur : hc;
      final top = topOf(i);
      final isCurrent = i == _curIndex;
      final isPast = i < _curIndex;
      final dist = (i - _curIndex).abs();
      // 현재 수업과 멀어질수록 과목 폭을 점진적으로 줄이는 원통형 물레방아 효과 (34px씩 축소)
      final itemWidth = isCurrent ? W : (W - (dist * 34.0)).clamp(560.0, W);

      items.add(
        AnimatedPositioned(
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeOutCubic,
          left: 0,
          top: top,
          width: itemWidth,
          height: h,
          child: GestureDetector(
            onTap: () {
              setState(() => _curIndex = i);
              widget.onPeriodTap?.call(i);
            },
            child: isCurrent ? _currentPeriodCard(ep[i]) : _thumbnailBlockCard(ep[i], isPast, i),
          ),
        ),
      );
    }
    return Stack(children: items);
  }

  /// [현재 수업 중 과목 카드]: 교과서 사진 대폭 확대 + 과목명 초대형 + 진행도는 하단 전폭 (교과서/필기 버튼 완전 제거)
  Widget _currentPeriodCard(TimetablePeriodItem p) {
    final times = (p.period >= 1 && p.period <= _defaultPeriodTimes.length)
        ? _defaultPeriodTimes[p.period - 1]
        : ('09:00', '09:50');
    final start = times.$1;
    final end = times.$2;

    return _glassSurface(
      glow: true,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 상단: 대형 교과서 커버 + 우측 수업 정보
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 대형 교과서 커버
                SizedBox(
                  width: 320,
                  child: _buildBookCoverWidget(p.subject, radius: 18),
                ),
                const SizedBox(width: 24),
                // 우측 핵심 수업 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 교시 뱃지 및 시간대
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F5D4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_circle_fill_rounded, size: 16, color: Colors.black),
                                const SizedBox(width: 6),
                                Text('${p.period}교시 · 수업 진행 중',
                                    style: _ts(14, w: FontWeight.w900, c: Colors.black)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$start ~ $end',
                                style: _ts(16, w: FontWeight.w700, c: Colors.white70)),
                          ),
                        ],
                      ),
                      // 과목명 초대형
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          p.subject,
                          style: _ts(130, w: FontWeight.w900, h: 1.0),
                        ),
                      ),
                      // 교사 / 교과서 / 학급 정보
                      Row(
                        children: [
                          const Icon(Icons.person_pin_rounded, color: Color(0xFF00F5D4), size: 24),
                          const SizedBox(width: 8),
                          Text(
                            p.targetClass != null && p.targetClass!.isNotEmpty
                                ? '${p.targetClass} 담당'
                                : '${widget.gradeClass}',
                            style: _ts(22, w: FontWeight.w800, c: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '·  [전자교과서] ${p.subject}',
                            style: _ts(18, w: FontWeight.w600, c: Colors.white60),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 2. 진행도는 아래로 넣어서 (하단 전폭 프로그레스 영역)
          _bottomProgressArea(),
        ],
      ),
    );
  }

  Widget _bottomProgressArea() {
    final progress = widget.clockRemainingProgress ?? 0.64;
    final remainText = widget.clockRemainingDetailText ?? widget.remainingTimeText ?? '수업 종료까지 18분 30초 남음';
    final percentStr = '${(progress * 100).toInt()}%';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.timelapse_rounded, color: Color(0xFF00F5D4), size: 22),
              const SizedBox(width: 8),
              Text(remainText, style: _ts(18, w: FontWeight.w800, c: Colors.white)),
              const Spacer(),
              Text(percentStr, style: _ts(22, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
              const SizedBox(width: 8),
              Text('(진행 중)', style: _ts(14, w: FontWeight.w600, c: Colors.white60)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 12,
              color: const Color(0xFF00F5D4),
              backgroundColor: Colors.white.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }

  /// [비수업 과목 카드] M3 서페이스 + 교과서 썸네일 블록형
  Widget _thumbnailBlockCard(TimetablePeriodItem p, bool isPast, int idx) {
    final times = (p.period >= 1 && p.period <= _defaultPeriodTimes.length)
        ? _defaultPeriodTimes[p.period - 1]
        : ('09:00', '09:50');
    final start = times.$1;
    final end = times.$2;

    return _glassTile(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // 미니 교과서 표지 썸네일
          Opacity(
            opacity: isPast ? 0.45 : 0.9,
            child: SizedBox(
              width: 52,
              height: double.infinity,
              child: _buildBookCoverWidget(p.subject, radius: 8, isMini: true),
            ),
          ),
          const SizedBox(width: 14),
          // 교시 번호
          SizedBox(
            width: 38,
            child: Text(
              '${p.period}',
              style: _ts(28, w: FontWeight.w900, c: isPast ? Colors.white30 : const Color(0xFF00F5D4)),
            ),
          ),
          // 과목명
          Expanded(
            child: Text(
              p.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _ts(30, w: FontWeight.w800, c: isPast ? Colors.white38 : Colors.white),
            ),
          ),
          // 시간대 & 대상
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                p.targetClass ?? widget.gradeClass,
                style: _ts(15, w: FontWeight.w700, c: isPast ? Colors.white38 : Colors.white),
              ),
              Text('$start ~ $end', style: _ts(13, c: isPast ? Colors.white24 : Colors.white60)),
            ],
          ),
          const SizedBox(width: 12),
          Icon(
            isPast ? Icons.check_circle_rounded : Icons.schedule_rounded,
            color: isPast ? const Color(0xFF00F5D4).withOpacity(0.5) : Colors.white38,
            size: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildBookCoverWidget(String subject, {double radius = 14, bool isMini = false}) {
    // 1. 전달받은 교과서 이미지 바이트 또는 경로 확인
    if (widget.currentTextbookBytes != null && widget.currentTextbookBytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(widget.currentTextbookBytes!, fit: BoxFit.cover),
      );
    }
    if (widget.currentTextbookImagePath != null && widget.currentTextbookImagePath!.isNotEmpty) {
      final file = File(widget.currentTextbookImagePath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.file(file, fit: BoxFit.cover),
        );
      }
    }

    // 2. 과목별 그라데이션 및 질감
    Color grad1 = const Color(0xFF1E3C72);
    Color grad2 = const Color(0xFF2A5298);
    String icon = '📘';

    if (subject.contains('국어') || subject.contains('문학')) {
      grad1 = const Color(0xFFB22222); grad2 = const Color(0xFFE55D5D); icon = '📖';
    } else if (subject.contains('수학')) {
      grad1 = const Color(0xFF0F3443); grad2 = const Color(0xFF34E89E); icon = '📐';
    } else if (subject.contains('영어')) {
      grad1 = const Color(0xFF004E92); grad2 = const Color(0xFF000428); icon = '🔤';
    } else if (subject.contains('과학') || subject.contains('물리') || subject.contains('화학')) {
      grad1 = const Color(0xFF4A00E0); grad2 = const Color(0xFF8E2DE2); icon = '🔬';
    } else if (subject.contains('사회') || subject.contains('역사')) {
      grad1 = const Color(0xFFB06AB3); grad2 = const Color(0xFF4568DC); icon = '🌏';
    } else if (subject.contains('체육') || subject.contains('스포츠')) {
      grad1 = const Color(0xFF11998E); grad2 = const Color(0xFF38EF7D); icon = '⚽';
    } else if (subject.contains('음악')) {
      grad1 = const Color(0xFFFF512F); grad2 = const Color(0xFFDD2476); icon = '🎵';
    } else if (subject.contains('미술')) {
      grad1 = const Color(0xFFFF8008); grad2 = const Color(0xFFFFC837); icon = '🎨';
    }

    if (isMini) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(colors: [grad1, grad2], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        alignment: Alignment.center,
        child: Text(icon, style: const TextStyle(fontSize: 22)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(colors: [grad1, grad2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 18,
            offset: const Offset(4, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 책등 바인더 음영 효과
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 18,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(radius)),
                gradient: LinearGradient(
                  colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 20, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('2026 개정', style: _ts(12, w: FontWeight.w800, c: Colors.white70)),
                    ),
                    Text(icon, style: const TextStyle(fontSize: 28)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('중학교', style: _ts(14, w: FontWeight.w700, c: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(
                      subject,
                      style: _ts(38, w: FontWeight.w900, c: Colors.white, h: 1.05),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('디지털 교과서 TBP', style: _ts(12, w: FontWeight.w800, c: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────── 2. 우측 콘텐츠 영역 ─────────
  Widget _rightContentArea() {
    final inClass = _isClassTime;

    return Column(
      children: [
        // 시계: 수업 중(초 없이 260px 높이 초대형 HH:mm + 여백) vs 쉬는 시간(초 포함 360px 대형)
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          height: inClass ? 260 : 360,
          child: inClass ? _classTimeCompactClock() : _recessTimeLargeClock(),
        ),
        const SizedBox(height: 18),
        // 하단 메인 콘텐츠
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildRightMainContent(inClass),
          ),
        ),
      ],
    );
  }

  static const _wd = ['월', '화', '수', '목', '금', '토', '일'];

  /// [수업 시간용 시계]: 초 단위 제거(HH:mm) + 폰트 260px 대형 + 수업종료 문구 제외 + 여유로운 여백
  Widget _classTimeCompactClock() {
    final now = widget.currentTime ?? DateTime.now();
    final date = '${now.year}년 ${now.month}월 ${now.day}일 (${_wd[now.weekday - 1]})';

    return _glassSurface(
      padding: const EdgeInsets.fromLTRB(30, 16, 30, 16),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, color: Color(0xFF00F5D4), size: 20),
              const SizedBox(width: 10),
              Text(date, style: _ts(20, w: FontWeight.w700, c: Colors.white)),
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('수업 진행 중', style: _ts(13, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
              ),
              const Spacer(),
              if (widget.ddayLabel != null && widget.ddayLabel!.isNotEmpty)
                GestureDetector(
                  onLongPress: widget.onDdayLongPress,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(widget.ddayLabel!, style: _ts(14, w: FontWeight.w700, c: const Color(0xFF00F5D4))),
                  ),
                ),
            ],
          ),
          Expanded(
            child: Center(
              child: StreamBuilder<DateTime>(
                stream: Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
                initialData: DateTime.now(),
                builder: (c, snap) {
                  final t = snap.data ?? DateTime.now();
                  String two(int v) => v.toString().padLeft(2, '0');
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${two(t.hour)}:${two(t.minute)}',
                      style: _ts(260, w: FontWeight.w900, h: 0.9, ls: -4, c: Colors.white),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [쉬는 시간용 시계]: 초 단위(HH:mm:ss) 포함 순백색 초대형 시계 + 쉬는 시간 종료 안내 표기
  Widget _recessTimeLargeClock() {
    final now = widget.currentTime ?? DateTime.now();
    final date = '${now.year}년 ${now.month}월 ${now.day}일 (${_wd[now.weekday - 1]})';

    return _glassSurface(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, color: Color(0xFF00F5D4), size: 22),
              const SizedBox(width: 10),
              Text(date, style: _ts(23, w: FontWeight.w700, c: Colors.white)),
              const Spacer(),
              if (widget.ddayLabel != null && widget.ddayLabel!.isNotEmpty)
                GestureDetector(
                  onLongPress: widget.onDdayLongPress,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(widget.ddayLabel!, style: _ts(14, w: FontWeight.w700, c: const Color(0xFF00F5D4))),
                  ),
                ),
            ],
          ),
          Expanded(
            child: Center(
              child: StreamBuilder<DateTime>(
                stream: Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
                initialData: DateTime.now(),
                builder: (c, snap) {
                  final t = snap.data ?? DateTime.now();
                  String two(int v) => v.toString().padLeft(2, '0');
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
                      style: _ts(360, w: FontWeight.w900, h: 0.95, ls: -4, c: Colors.white),
                    ),
                  );
                },
              ),
            ),
          ),
          // 쉬는 시간에만 시계 아래 표기
          Row(
            children: [
              const Icon(Icons.coffee_rounded, color: Color(0xFF00F5D4), size: 22),
              const SizedBox(width: 8),
              Text(
                widget.clockRemainingDetailText ?? '쉬는 시간 종료까지 남은 시간',
                style: _ts(18, c: Colors.white, w: FontWeight.w800),
              ),
              const Spacer(),
              if (widget.nextSubject.isNotEmpty)
                Text('다음 수업: ${widget.nextSubject}',
                    style: _ts(17, c: const Color(0xFF00F5D4), w: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }

  /// 4가지 시나리오에 따른 하단 메인 영역 분기
  Widget _buildRightMainContent(bool inClass) {
    if (inClass) {
      if (_showClassMeal) {
        return _classMealOverlay(key: const ValueKey('class_meal_overlay'));
      }
      if (!widget.isCloudActive) {
        // [수업 중 미연결] 급식 식단표 치우고, 여백 넉넉한 대형 기본 수업 도구함 그리드
        return _classToolsGrid(key: const ValueKey('class_tools_grid'));
      } else {
        // [수업 중 + Cloud/USB 연결] 시계 아래 세로 리스트형 파일함 + 그 아래 1줄 가로 도구함
        return _classTimeCloudFilesAndToolbar(key: const ValueKey('class_files_tools'));
      }
    } else {
      if (!widget.isCloudActive) {
        // [쉬는 시간 미연결] 바닥 끝까지 시원하게 다 쓰는 급식 식단표 + 우측 세로 도구함 독
        return Row(
          key: const ValueKey('recess_meal_dock'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _mealTableFull()),
            const SizedBox(width: 16),
            SizedBox(width: 96, child: _verticalToolbarDock()),
          ],
        );
      } else {
        // [쉬는 시간 + Cloud/USB 연결] 급식 위치에 USB 파일함 (급식 탭 전환 가능) + 우측 세로 독
        return Row(
          key: const ValueKey('recess_usb_panel'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _recessCloudPanel()),
            const SizedBox(width: 16),
            SizedBox(width: 96, child: _verticalToolbarDock()),
          ],
        );
      }
    }
  }

  /// 수업 중 급식 식단표 확인 뷰 (수업 도구함에서 '급식' 클릭 시 노출)
  Widget _classMealOverlay({Key? key}) {
    return KeyedSubtree(
      key: key,
      child: _glassSurface(
        padding: const EdgeInsets.fromLTRB(26, 18, 26, 18),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.restaurant_rounded, color: Color(0xFF00F5D4), size: 24),
                const SizedBox(width: 10),
                Text('급식 식단표 (수업 중 확인)', style: _ts(23, w: FontWeight.w800)),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showClassMeal = false),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_back_rounded, size: 18, color: Colors.black),
                        const SizedBox(width: 6),
                        Text('수업 도구함으로 복귀', style: _ts(15, w: FontWeight.w900, c: Colors.black)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _mealColumn('오늘 점심', widget.todayCalories, widget.todayDishes, true),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _mealColumn(
                      widget.tomorrowDateLabel.isNotEmpty ? widget.tomorrowDateLabel : '내일 점심',
                      widget.tomorrowCalories,
                      widget.tomorrowDishes,
                      false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [수업 도구 대형 그리드]: 기존 Boardest 공식 도구들(판서, 타이머, 추첨, 계산기, 급식, Cloud)만 정갈하게 구성
  Widget _classToolsGrid({Key? key}) {
    return KeyedSubtree(
      key: key,
      child: _glassSurface(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.widgets_rounded, color: Color(0xFF00F5D4), size: 24),
                const SizedBox(width: 10),
                Text('수업 도구 모음', style: _ts(23, w: FontWeight.w800)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('터치 시 즉시 실행', style: _ts(12, c: Colors.white60, w: FontWeight.w600)),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showClassMeal = true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C896).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00C896).withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.restaurant_rounded, size: 16, color: Color(0xFF00C896)),
                        const SizedBox(width: 6),
                        Text('급식 식단표 띄우기',
                            style: _ts(13, w: FontWeight.w800, c: const Color(0xFF00C896))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 22,
                  mainAxisSpacing: 22,
                  childAspectRatio: 1.4,
                ),
                itemCount: _defaultTools.length,
                itemBuilder: (context, i) {
                  final tool = _defaultTools[i];
                  return InkWell(
                    onTap: () {
                      if (tool.$2 == '급식') {
                        setState(() => _showClassMeal = true);
                      } else if (tool.$2 == 'Cloud') {
                        widget.onCloudToggle?.call();
                      } else {
                        widget.onToolTap?.call(tool.$5);
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: _glassTile(
                      radius: 16,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: tool.$4.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: tool.$4.withOpacity(0.4), width: 1.2),
                                ),
                                child: Icon(tool.$1, color: tool.$4, size: 32),
                              ),
                              const Spacer(),
                              const Icon(Icons.arrow_outward_rounded, color: Colors.white38, size: 20),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tool.$2, style: _ts(24, w: FontWeight.w800, c: Colors.white)),
                              const SizedBox(height: 4),
                              Text(tool.$3,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _ts(15, c: Colors.white60)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [수업 중 + Cloud/USB 연결]: 시계 아래 세로 리스트형 파일 목록 + 그 아래 한 줄 가로 도구함
  Widget _classTimeCloudFilesAndToolbar({Key? key}) {
    return Column(
      key: key,
      children: [
        // 상단: Cloud/USB 파일 목록 (세로 리스트형!)
        Expanded(
          child: widget.cloudFilesWidget ??
              _glassSurface(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F5D4).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.cloud_rounded, color: Color(0xFF00F5D4), size: 20),
                        ),
                        const SizedBox(width: 10),
                        Text('클라우드 / USB 수업 자료', style: _ts(21, w: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F5D4).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('연결됨',
                              style: _ts(12, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: widget.onCloudToggle,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                                const SizedBox(width: 4),
                                Text('닫기', style: _ts(12, w: FontWeight.w700, c: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _sampleFiles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (c, i) {
                          final f = _sampleFiles[i];
                          return _glassTile(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: f.$4.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(f.$5, color: f.$4, size: 24),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(f.$1,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: _ts(18, w: FontWeight.w800)),
                                      const SizedBox(height: 3),
                                      Text('${f.$2} · ${f.$3}', style: _ts(13, c: Colors.white54)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00F5D4).withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('열기',
                                      style: _ts(13, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
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
        const SizedBox(height: 14),
        // 하단: 한 줄로 도구들이 뜨는 가로 툴바 바
        _singleRowToolbar(),
      ],
    );
  }

  /// 한 줄 가로 툴바 바
  Widget _singleRowToolbar() {
    return _glassSurface(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final t in _defaultTools)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () {
                    if (t.$2 == '급식') {
                      setState(() => _showClassMeal = true);
                    } else if (t.$2 == 'Cloud') {
                      widget.onCloudToggle?.call();
                    } else {
                      widget.onToolTap?.call(t.$5);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: _glassTile(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    radius: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.$1,
                            color: t.$2 == '급식' ? const Color(0xFF00C896) : const Color(0xFF00F5D4),
                            size: 22),
                        const SizedBox(width: 8),
                        Text(t.$2, style: _ts(16, w: FontWeight.w800, c: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// [쉬는 시간 + Cloud/USB 연결]: 급식 위치에 리스트형 USB 파일함 (급식 탭 전환 가능)
  Widget _recessCloudPanel() {
    return _glassSurface(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      child: Column(
        children: [
          // 상단: 탭 전환 [클라우드/USB 수업 자료] vs [급식 식단표]
          Row(
            children: [
              InkWell(
                onTap: () => setState(() => _recessTab = 0),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _recessTab == 0 ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_rounded,
                          size: 18, color: _recessTab == 0 ? Colors.black : Colors.white70),
                      const SizedBox(width: 6),
                      Text('클라우드 / USB 파일',
                          style: _ts(16,
                              w: FontWeight.w800,
                              c: _recessTab == 0 ? Colors.black : Colors.white70)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _recessTab = 1),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _recessTab == 1 ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.restaurant_rounded,
                          size: 18, color: _recessTab == 1 ? Colors.black : Colors.white70),
                      const SizedBox(width: 6),
                      Text('급식 식단표',
                          style: _ts(16,
                              w: FontWeight.w800,
                              c: _recessTab == 1 ? Colors.black : Colors.white70)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text('쉬는 시간 동안 다음 수업 준비 가능', style: _ts(13, c: Colors.white54)),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _recessTab == 0
                ? (widget.cloudFilesWidget ??
                    ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _sampleFiles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (c, i) {
                        final f = _sampleFiles[i];
                        return _glassTile(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: f.$4.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(f.$5, color: f.$4, size: 24),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(f.$1,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: _ts(18, w: FontWeight.w800)),
                                    const SizedBox(height: 4),
                                    Text('${f.$2} · ${f.$3}', style: _ts(13, c: Colors.white54)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00F5D4).withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('열기',
                                    style: _ts(13, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
                              ),
                            ],
                          ),
                        );
                      },
                    ))
                : Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _mealColumn('오늘 점심', widget.todayCalories, widget.todayDishes, true),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: _mealColumn(
                          widget.tomorrowDateLabel.isNotEmpty ? widget.tomorrowDateLabel : '내일 점심',
                          widget.tomorrowCalories,
                          widget.tomorrowDishes,
                          false,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// [쉬는 시간 미연결] 바닥 끝까지 시원하게 다 쓰는 급식 식단표
  Widget _mealTableFull() {
    return _glassSurface(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_rounded, color: Color(0xFF00F5D4), size: 24),
              const SizedBox(width: 10),
              Text('급식 식단표', style: _ts(23, w: FontWeight.w800)),
              const SizedBox(width: 10),
              Text('(클릭 시 알레르기 강조 & 투표)', style: _ts(14, c: Colors.white54)),
              const Spacer(),
              if (widget.onCloudToggle != null)
                InkWell(
                  onTap: widget.onCloudToggle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_sync_rounded, size: 14, color: Color(0xFF00F5D4)),
                        const SizedBox(width: 6),
                        Text('Cloud 전환', style: _ts(12, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _mealColumn('오늘 점심', widget.todayCalories, widget.todayDishes, true),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: _mealColumn(
                    widget.tomorrowDateLabel.isNotEmpty ? widget.tomorrowDateLabel : '내일 점심',
                    widget.tomorrowCalories,
                    widget.tomorrowDishes,
                    false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 급식 메뉴 열 (폰트 25px 굵고 시원하게 확대, 알레르기 칩 표시)
  Widget _mealColumn(String title, String kcal, List<MealDishItem> dishes, bool today) {
    return _glassTile(
      selected: today,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        children: [
          Row(
            children: [
              Text(title,
                  style: _ts(21, w: FontWeight.w800, c: today ? const Color(0xFF00F5D4) : Colors.white)),
              const Spacer(),
              if (kcal.isNotEmpty)
                Text(kcal, style: _ts(15, c: Colors.white54, w: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1.2, color: Colors.white.withOpacity(0.15)),
          Expanded(
            child: dishes.isEmpty
                ? Center(
                    child: Text('급식 정보가 없습니다.', style: _ts(16, c: Colors.white38)),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final d in dishes)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                d.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _ts(25, w: FontWeight.w800),
                              ),
                            ),
                            for (final tag in d.allergies)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _amber.withOpacity(0.18),
                                  border: Border.all(color: _amber.withOpacity(0.7)),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(tag, style: _ts(12, w: FontWeight.w800, c: _amber)),
                              ),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 우측 끝에 세로로 독(Dock) 형태로 세운 도구함
  Widget _verticalToolbarDock() {
    return _glassSurface(
      radius: 20,
      glow: true,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (int i = 0; i < _defaultTools.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: InkWell(
                  onTap: () {
                    final t = _defaultTools[i];
                    if (t.$2 == '급식') {
                      setState(() => _showClassMeal = true);
                    } else if (t.$2 == 'Cloud') {
                      widget.onCloudToggle?.call();
                    } else {
                      widget.onToolTap?.call(t.$5);
                    }
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: _glassTile(
                    selected: i == 0,
                    radius: 14,
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_defaultTools[i].$1,
                            size: 28,
                            color: i == 0 ? const Color(0xFF00F5D4) : Colors.white60),
                        const SizedBox(height: 3),
                        Text(_defaultTools[i].$2,
                            style: _ts(13,
                                w: FontWeight.w800,
                                c: i == 0 ? Colors.white : Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

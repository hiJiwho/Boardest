import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';
import '../../models/meal_models.dart';
import '../../models/app_settings.dart' show LauncherSlot;
import '../../services/system_app_scanner.dart';
import '../modals/app_drawer_dialog.dart';
import 'bst_today_timetable_strip.dart' show TimetablePeriodItem;
import 'bst_tools_dock.dart' show BstToolType, BstToolsDock;

export 'bst_today_timetable_strip.dart';
export 'bst_tools_dock.dart';
export '../../models/meal_models.dart';
export '../../models/app_settings.dart' show LauncherSlot;

const _amber = Color(0xFFFFC857);

/// Boardest Class 4.2.1 Golden Layout
/// - DPI 최적화 (급식 메뉴 16~17px로 축소, 전체 배율 조절, 여유로운 여백)
/// - 쉬는 시간 안내는 오직 시계 아래에만 표시!
/// - 수업 중일 때만 좌측 카드에 수업 진행도 프로그레스 바 노출
/// - 과목별로 완전히 다른 고유 교과서 표지 (색상, 아이콘, 타이틀 패턴)
/// - 급식 버튼은 수업시간에만 노출 (쉬는시간에는 급식 식단표가 상시 노출되므로 도구함에서 제외)
/// - 시계 꾹 길게 누르면 디버깅 다이얼로그 호출 가능 (onClockLongPress)
/// - 설정 버튼 (톱니바퀴) 도구함에 정식 복구
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
  List<ScannedApp> _systemApps = [];

  static final _defaultDemoSystemApps = [
    ScannedApp(name: '웹 브라우저', appId: 'browser'),
    ScannedApp(name: '파워포인트', appId: 'powerpoint'),
    ScannedApp(name: '한글 (HWP)', appId: 'hancom'),
    ScannedApp(name: '계산기', appId: 'calculator'),
    ScannedApp(name: '파일 탐색기', appId: 'explorer'),
    ScannedApp(name: '카메라', appId: 'camera'),
  ];

  Future<void> _loadSystemApps() async {
    if (kIsWeb) return;
    try {
      final apps = SystemAppScanner.externalAppsOnly(await SystemAppScanner.scanInstalledApps());
      if (mounted) {
        setState(() {
          _systemApps = apps;
        });
      }
    } catch (e) {
      debugPrint('[BstClassMainLayout] _loadSystemApps error: $e');
    }
  }

  static const _defaultPeriodTimes = [
    ('09:00', '09:50'),
    ('10:00', '10:50'),
    ('11:00', '11:50'),
    ('12:00', '12:50'),
    ('13:40', '14:30'),
    ('14:40', '15:30'),
    ('15:40', '16:30'),
  ];

  // 수업 중 도구 목록 (급식 버튼 포함 + 설정 버튼 포함)
  static const _classTools = <(IconData, String, String, Color, BstToolType)>[
    (Icons.edit_rounded, '판서', '무한 캔버스 판서', Color(0xFF00F5D4), BstToolType.pen),
    (Icons.timer_outlined, '타이머', '수업 집중 타이머', Color(0xFFFFC857), BstToolType.timer),
    (Icons.casino_outlined, '추첨', '발표자 번호 추첨', Color(0xFFFF6B6B), BstToolType.random),
    (Icons.calculate_outlined, '계산기', '공학용 수식 계산', Color(0xFF4D96FF), BstToolType.calculator),
    (Icons.restaurant_rounded, '급식', '오늘 점심 식단표 확인', Color(0xFF00C896), BstToolType.web),
    (Icons.cloud_outlined, 'Cloud', '수업 자료 클라우드', Color(0xFF7F5AF0), BstToolType.cloud),
    (Icons.settings_rounded, '설정', '전자칠판 환경설정', Color(0xFF94A1B2), BstToolType.settings),
  ];

  // 쉬는 시간 도구 목록 (급식 식단표가 화면에 상시 노출되므로 급식 제외! + 설정 포함)
  static const _recessTools = <(IconData, String, String, Color, BstToolType)>[
    (Icons.edit_rounded, '판서', '무한 캔버스 판서', Color(0xFF00F5D4), BstToolType.pen),
    (Icons.timer_outlined, '타이머', '수업 집중 타이머', Color(0xFFFFC857), BstToolType.timer),
    (Icons.casino_outlined, '추첨', '발표자 번호 추첨', Color(0xFFFF6B6B), BstToolType.random),
    (Icons.calculate_outlined, '계산기', '공학용 수식 계산', Color(0xFF4D96FF), BstToolType.calculator),
    (Icons.cloud_outlined, 'Cloud', '수업 자료 클라우드', Color(0xFF7F5AF0), BstToolType.cloud),
    (Icons.settings_rounded, '설정', '전자칠판 환경설정', Color(0xFF94A1B2), BstToolType.settings),
  ];

  static const _sampleFiles = <(String, String, String, Color, IconData)>[
    ('수학I_03단원_삼각함수.pdf', 'PDF', '3.4 MB', Color(0xFFFF6B6B), Icons.picture_as_pdf_rounded),
    ('2026_모의고사_기출분석.pptx', 'PPT', '8.9 MB', Color(0xFFFF8906), Icons.slideshow_rounded),
    ('[전자교과서] 수학I 비상', 'TBP', '45 MB', Color(0xFF7F5AF0), Icons.auto_stories_rounded),
    ('함수의극한_인터랙티브', 'HTMLP', '3.1 MB', Color(0xFF00C4CC), Icons.co_present_rounded),
    ('10월20일_판서노트.pen', 'PEN', '5.1 MB', Color(0xFF00C896), Icons.draw_rounded),
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
    double radius = 18,
    bool glow = false,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF141721).withOpacity(0.88),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: glow ? const Color(0xFF00F5D4).withOpacity(0.45) : Colors.white.withOpacity(0.1),
          width: glow ? 1.5 : 1.0,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: const Color(0xFF00F5D4).withOpacity(0.16),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );
  }

  Widget _glassTile({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
    double radius = 12,
    bool selected = false,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF00F5D4).withOpacity(0.12) : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? const Color(0xFF00F5D4).withOpacity(0.4) : Colors.white.withOpacity(0.08),
        ),
      ),
      child: child,
    );
  }

  /// 실제 수업 진행 중인지 여부 (정확한 상태 판별)
  bool get _isClassTime {
    final status = widget.currentPeriodStatus.trim();
    if (status.contains('수업 준비') || status.contains('쉬는') || status.contains('종료')) {
      return false;
    }
    if (status.contains('진행 중') || status.contains('수업 중')) {
      return true;
    }
    return false;
  }

  List<TimetablePeriodItem> get _effectivePeriods {
    if (widget.periods.isNotEmpty) return widget.periods;
    return List.generate(
      6,
      (i) => TimetablePeriodItem(
        period: i + 1,
        subject: ['국어', '수학', '영어', '과학', '사회', '체육'][i],
        isCurrent: i == 0,
        targetClass: widget.gradeClass,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initCurrentPeriod();
    _loadSystemApps();
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
          padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 좌측 물레방아 시간표 (너비 780px, 좌측 밀착)
              SizedBox(
                width: 780,
                child: _leftWheelArea(),
              ),
              const SizedBox(width: 18),
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
        const SizedBox(height: 10),
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
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF00F5D4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('bt', style: _ts(16, w: FontWeight.w900, c: Colors.black)),
          ),
          const SizedBox(width: 8),
          Text('BOARDEST Class', style: _ts(16, w: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF00F5D4).withOpacity(0.16),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF00F5D4), width: 1),
            ),
            child: Text('PRO', style: _ts(10.5, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
          ),
          const SizedBox(width: 14),
          Text(
            title,
            style: _ts(14, w: FontWeight.w700, c: Colors.white70),
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
    const g = 8.0;
    const hc = 68.0;
    final hcur = (H - (n - 1) * (hc + g)).clamp(210.0, H);

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
      // 현재 수업과 멀어질수록 과목 폭을 점진적으로 줄이는 원통형 물레방아 효과 (32px씩 축소)
      final itemWidth = isCurrent ? W : (W - (dist * 32.0)).clamp(540.0, W);

      items.add(
        AnimatedPositioned(
          duration: const Duration(milliseconds: 500),
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

  /// [현재 선택된 과목 카드]: DPI 조절(과목명 크기 78~84px), 수업 중일 때만 진행도 노출
  Widget _currentPeriodCard(TimetablePeriodItem p) {
    final times = (p.period >= 1 && p.period <= _defaultPeriodTimes.length)
        ? _defaultPeriodTimes[p.period - 1]
        : ('09:00', '09:50');
    final start = times.$1;
    final end = times.$2;
    final inClass = _isClassTime && p.isCurrent;

    return _glassSurface(
      glow: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 상단: 교과서 커버 + 우측 수업 정보
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 단정한 교과서 커버 (폭 250px)
                SizedBox(
                  width: 250,
                  child: _buildBookCoverWidget(p.subject, radius: 14),
                ),
                const SizedBox(width: 20),
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
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: inClass ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  inClass ? Icons.play_circle_fill_rounded : Icons.schedule_rounded,
                                  size: 14,
                                  color: inClass ? Colors.black : Colors.white70,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  inClass ? '${p.period}교시 · 수업 진행 중' : '${p.period}교시 · 다음 수업',
                                  style: _ts(13, w: FontWeight.w900, c: inClass ? Colors.black : Colors.white),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('$start ~ $end',
                                style: _ts(14, w: FontWeight.w700, c: Colors.white70)),
                          ),
                        ],
                      ),
                      // 과목명 (DPI 조정: 너무 비대하지 않고 알맞은 스케일 78~84px)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          p.subject,
                          style: _ts(82, w: FontWeight.w900, h: 1.05),
                        ),
                      ),
                      // 교사 / 교과서 / 학급 정보
                      Row(
                        children: [
                          const Icon(Icons.person_pin_rounded, color: Color(0xFF00F5D4), size: 20),
                          const SizedBox(width: 6),
                          Text(
                            p.targetClass != null && p.targetClass!.isNotEmpty
                                ? '${p.targetClass} 담당'
                                : '${widget.gradeClass}',
                            style: _ts(18, w: FontWeight.w800, c: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '·  [전자교과서] ${p.subject}',
                            style: _ts(15, w: FontWeight.w600, c: Colors.white60),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 2. 하단 전폭 진행도 바는 오직 수업 중일 때만 노출! (쉬는 시간 안내는 시계 아래에만!)
          if (inClass) ...[
            const SizedBox(height: 12),
            _bottomProgressArea(),
          ],
        ],
      ),
    );
  }

  /// 수업 중일 때만 나타나는 진행도 바
  Widget _bottomProgressArea() {
    final progress = widget.clockRemainingProgress ?? 0.64;
    final remainText = widget.clockRemainingDetailText ?? widget.remainingTimeText ?? '수업 종료까지 남은 시간';
    final percentStr = '${(progress * 100).toInt()}%';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.timelapse_rounded, color: Color(0xFF00F5D4), size: 18),
              const SizedBox(width: 6),
              Text(remainText, style: _ts(15, w: FontWeight.w800, c: Colors.white)),
              const Spacer(),
              Text(percentStr, style: _ts(18, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
              const SizedBox(width: 6),
              Text('(진행 중)', style: _ts(12, w: FontWeight.w600, c: Colors.white60)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 10,
              color: const Color(0xFF00F5D4),
              backgroundColor: Colors.white.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }

  /// [비선택 과목 카드] M3 서페이스 + 교과서 썸네일 블록형
  Widget _thumbnailBlockCard(TimetablePeriodItem p, bool isPast, int idx) {
    final times = (p.period >= 1 && p.period <= _defaultPeriodTimes.length)
        ? _defaultPeriodTimes[p.period - 1]
        : ('09:00', '09:50');
    final start = times.$1;
    final end = times.$2;

    return _glassTile(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // 미니 교과서 표지 썸네일 (과목별로 고유한 색상 및 아이콘)
          Opacity(
            opacity: isPast ? 0.45 : 0.95,
            child: SizedBox(
              width: 48,
              height: double.infinity,
              child: _buildBookCoverWidget(p.subject, radius: 6, isMini: true),
            ),
          ),
          const SizedBox(width: 12),
          // 교시 번호
          SizedBox(
            width: 32,
            child: Text(
              '${p.period}',
              style: _ts(24, w: FontWeight.w900, c: isPast ? Colors.white30 : const Color(0xFF00F5D4)),
            ),
          ),
          // 과목명 (DPI 조정 24px)
          Expanded(
            child: Text(
              p.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _ts(24, w: FontWeight.w800, c: isPast ? Colors.white38 : Colors.white),
            ),
          ),
          // 시간대 & 대상
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                p.targetClass ?? widget.gradeClass,
                style: _ts(13, w: FontWeight.w700, c: isPast ? Colors.white38 : Colors.white),
              ),
              Text('$start ~ $end', style: _ts(11.5, c: isPast ? Colors.white24 : Colors.white60)),
            ],
          ),
          const SizedBox(width: 10),
          Icon(
            isPast ? Icons.check_circle_rounded : Icons.schedule_rounded,
            color: isPast ? const Color(0xFF00F5D4).withOpacity(0.5) : Colors.white38,
            size: 18,
          ),
        ],
      ),
    );
  }

  /// [과목별 고유 교과서 커버 위젯]: 과목마다 완전히 다른 색상, 아이콘, 타이틀 레이아웃
  Widget _buildBookCoverWidget(String subject, {double radius = 14, bool isMini = false}) {
    // 1. 해당 과목에 명시적으로 연결된 개별 교과서 이미지 확인
    final customBytes = widget.getTextbookBytes?.call(subject);
    if (customBytes != null && customBytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(customBytes, fit: BoxFit.cover),
      );
    }
    final customPath = widget.getTextbookPath?.call(subject);
    if (customPath != null && customPath.isNotEmpty) {
      final file = File(customPath);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.file(file, fit: BoxFit.cover),
        );
      }
    }

    // 현재 수업 중인 과목과 정확히 일치할 때만 currentTextbookBytes 사용
    if (subject == widget.currentSubject) {
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
    }

    // 2. 과목별 고유 테마 컬러 & 아이콘 & 서브텍스트 생성
    Color grad1 = const Color(0xFF1E3C72);
    Color grad2 = const Color(0xFF2A5298);
    String icon = '📘';
    String category = '일반 교과';

    if (subject.contains('국어') || subject.contains('문학')) {
      grad1 = const Color(0xFF8B0000); grad2 = const Color(0xFFE53935); icon = '📖'; category = '국어과';
    } else if (subject.contains('수학')) {
      grad1 = const Color(0xFF0F3443); grad2 = const Color(0xFF00F5D4); icon = '📐'; category = '수학과';
    } else if (subject.contains('영어')) {
      grad1 = const Color(0xFF003973); grad2 = const Color(0xFFE5E5BE); icon = '🔤'; category = '외국어과';
    } else if (subject.contains('과학') || subject.contains('물리') || subject.contains('화학') || subject.contains('생물') || subject.contains('지구')) {
      grad1 = const Color(0xFF4A00E0); grad2 = const Color(0xFF8E2DE2); icon = '🔬'; category = '과학교과';
    } else if (subject.contains('역사')) {
      grad1 = const Color(0xFF5D4037); grad2 = const Color(0xFFD7CCC8); icon = '🏛️'; category = '역사과';
    } else if (subject.contains('사회') || subject.contains('지리')) {
      grad1 = const Color(0xFF6A11CB); grad2 = const Color(0xFF2575FC); icon = '🌏'; category = '사회과';
    } else if (subject.contains('도덕') || subject.contains('윤리')) {
      grad1 = const Color(0xFF134E5E); grad2 = const Color(0xFF71B280); icon = '🕊️'; category = '도덕과';
    } else if (subject.contains('음악')) {
      grad1 = const Color(0xFFD81B60); grad2 = const Color(0xFFFF80AB); icon = '🎵'; category = '예술과';
    } else if (subject.contains('미술')) {
      grad1 = const Color(0xFFE65100); grad2 = const Color(0xFFFFB74D); icon = '🎨'; category = '예술과';
    } else if (subject.contains('체육') || subject.contains('스포츠')) {
      grad1 = const Color(0xFF00796B); grad2 = const Color(0xFF00E676); icon = '⚽'; category = '체육과';
    } else if (subject.contains('정보') || subject.contains('컴퓨터') || subject.contains('기술') || subject.contains('가정')) {
      grad1 = const Color(0xFF0D47A1); grad2 = const Color(0xFF00E5FF); icon = '💻'; category = '기술·가정';
    } else if (subject.contains('한문') || subject.contains('한자')) {
      grad1 = const Color(0xFF3E2723); grad2 = const Color(0xFF8D6E63); icon = '🏮'; category = '한문과';
    }

    if (isMini) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(colors: [grad1, grad2], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        alignment: Alignment.center,
        child: Text(icon, style: const TextStyle(fontSize: 20)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(colors: [grad1, grad2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 14,
            offset: const Offset(3, 5),
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
            width: 14,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(radius)),
                gradient: LinearGradient(
                  colors: [Colors.black.withOpacity(0.5), Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(category, style: _ts(11, w: FontWeight.w800, c: Colors.white70)),
                    ),
                    Text(icon, style: const TextStyle(fontSize: 24)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('중학교 교과서', style: _ts(12.5, w: FontWeight.w700, c: Colors.white70)),
                    const SizedBox(height: 3),
                    Text(
                      subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _ts(30, w: FontWeight.w900, c: Colors.white, h: 1.05),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('디지털 교과서 TBP', style: _ts(11, w: FontWeight.w800, c: Colors.white)),
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
        // 시계: 수업 중(높이 210px) vs 쉬는 시간(높이 290px), GestureDetector로 꾹 눌러 디버깅 가능!
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          height: inClass ? 210 : 290,
          child: inClass ? _classTimeCompactClock() : _recessTimeLargeClock(),
        ),
        const SizedBox(height: 14),
        // 하단 메인 콘텐츠
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _buildRightMainContent(inClass),
          ),
        ),
      ],
    );
  }

  static const _wd = ['월', '화', '수', '목', '금', '토', '일'];

  /// [수업 시간용 시계]: 꾹 누르면 디버그 가능 (onClockLongPress) + HH:mm 순백색 시계
  Widget _classTimeCompactClock() {
    final now = widget.currentTime ?? DateTime.now();
    final date = '${now.year}년 ${now.month}월 ${now.day}일 (${_wd[now.weekday - 1]})';

    return GestureDetector(
      onLongPress: widget.onClockLongPress,
      child: _glassSurface(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: Color(0xFF00F5D4), size: 18),
                const SizedBox(width: 8),
                Text(date, style: _ts(18, w: FontWeight.w700, c: Colors.white)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('수업 진행 중', style: _ts(12, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
                ),
                const Spacer(),
                if (widget.ddayLabel != null && widget.ddayLabel!.isNotEmpty)
                  GestureDetector(
                    onLongPress: widget.onDdayLongPress,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(widget.ddayLabel!, style: _ts(13, w: FontWeight.w700, c: const Color(0xFF00F5D4))),
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
                        style: _ts(180, w: FontWeight.w900, h: 0.9, ls: -3, c: Colors.white),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [쉬는 시간용 시계]: 꾹 누르면 디버깅 가능 (onClockLongPress) + 쉬는 시간 안내는 오직 시계 아래에만 표시!
  Widget _recessTimeLargeClock() {
    final now = widget.currentTime ?? DateTime.now();
    final date = '${now.year}년 ${now.month}월 ${now.day}일 (${_wd[now.weekday - 1]})';

    return GestureDetector(
      onLongPress: widget.onClockLongPress,
      child: _glassSurface(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: Color(0xFF00F5D4), size: 19),
                const SizedBox(width: 8),
                Text(date, style: _ts(19, w: FontWeight.w700, c: Colors.white)),
                const Spacer(),
                if (widget.ddayLabel != null && widget.ddayLabel!.isNotEmpty)
                  GestureDetector(
                    onLongPress: widget.onDdayLongPress,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(widget.ddayLabel!, style: _ts(13, w: FontWeight.w700, c: const Color(0xFF00F5D4))),
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
                        style: _ts(220, w: FontWeight.w900, h: 0.95, ls: -3, c: Colors.white),
                      ),
                    );
                  },
                ),
              ),
            ),
            // 쉬는 시간 안내 문구는 오직 시계 아래에만 명확하게 표시! (사용자 핵심 요청)
            Row(
              children: [
                const Icon(Icons.coffee_rounded, color: Color(0xFF00F5D4), size: 19),
                const SizedBox(width: 7),
                Text(
                  widget.clockRemainingDetailText ?? '쉬는 시간 (수업 준비 중)',
                  style: _ts(16, c: Colors.white, w: FontWeight.w800),
                ),
                const Spacer(),
                if (widget.nextSubject.isNotEmpty)
                  Text('다음 수업: ${widget.nextSubject}',
                      style: _ts(15, c: const Color(0xFF00F5D4), w: FontWeight.w800)),
              ],
            ),
          ],
        ),
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
        // [수업 중 미연결] 도구 모음 그리드 (급식 버튼 포함 + 설정 버튼 포함)
        return _classToolsGrid(key: const ValueKey('class_tools_grid'));
      } else {
        // [수업 중 + Cloud/USB 연결] 세로 리스트형 파일함 + 그 아래 1줄 가로 도구함
        return _classTimeCloudFilesAndToolbar(key: const ValueKey('class_files_tools'));
      }
    } else {
      if (!widget.isCloudActive) {
        // [쉬는 시간 미연결] 급식 식단표 + 우측 세로 독 (급식 버튼 제외, 설정 포함)
        return Row(
          key: const ValueKey('recess_meal_dock'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _mealTableFull()),
            const SizedBox(width: 14),
            SizedBox(width: 88, child: _verticalToolbarDock(inClass: false)),
          ],
        );
      } else {
        // [쉬는 시간 + Cloud/USB 연결] 급식 위치에 리스트형 USB 파일함 + 우측 세로 독
        return Row(
          key: const ValueKey('recess_usb_panel'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _recessCloudPanel()),
            const SizedBox(width: 14),
            SizedBox(width: 88, child: _verticalToolbarDock(inClass: false)),
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
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.restaurant_rounded, color: Color(0xFF00F5D4), size: 22),
                const SizedBox(width: 8),
                Text('급식 식단표 (수업 중 확인)', style: _ts(20, w: FontWeight.w800)),
                const Spacer(),
                InkWell(
                  onTap: () => _showMonthlyMealDialog(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month_rounded, size: 14, color: Color(0xFF00F5D4)),
                        const SizedBox(width: 5),
                        Text('월 급식표', style: _ts(12.5, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () => setState(() => _showClassMeal = false),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_back_rounded, size: 16, color: Colors.black),
                        const SizedBox(width: 5),
                        Text('수업 도구함으로 복귀', style: _ts(13.5, w: FontWeight.w900, c: Colors.black)),
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
      ),
    );
  }

  /// [수업 도구 중앙 정렬]: 사용자의 요청에 따라 수업 도구들을 정가운데로 대칭 정렬!
  Widget _classToolsGrid({Key? key}) {
    final row1 = _classTools.sublist(0, 4); // 판서, 타이머, 추첨, 계산기
    final row2 = _classTools.sublist(4);    // 급식, Cloud, 설정
    final showSystemApps = !kIsWeb && (widget.isPro || _systemApps.isNotEmpty || Platform.isWindows || Platform.isAndroid);
    final cardHeight = showSystemApps ? 96.0 : 110.0;

    Widget buildToolCard((IconData, String, String, Color, BstToolType) tool, {double width = 175, double? height}) {
      return SizedBox(
        width: width,
        height: height ?? cardHeight,
        child: InkWell(
          onTap: () {
            if (tool.$2 == '급식') {
              setState(() => _showClassMeal = true);
            } else if (tool.$2 == 'Cloud') {
              widget.onCloudToggle?.call();
            } else {
              widget.onToolTap?.call(tool.$5);
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: _glassTile(
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tool.$4.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: tool.$4.withOpacity(0.4), width: 1.1),
                      ),
                      child: Icon(tool.$1, color: tool.$4, size: 22),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_outward_rounded, color: Colors.white38, size: 15),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tool.$2, style: _ts(18, w: FontWeight.w800, c: Colors.white)),
                    const SizedBox(height: 1),
                    Text(tool.$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _ts(11.5, c: Colors.white60)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return KeyedSubtree(
      key: key,
      child: _glassSurface(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.widgets_rounded, color: Color(0xFF00F5D4), size: 22),
                const SizedBox(width: 8),
                Text('수업 도구 모음', style: _ts(20, w: FontWeight.w800)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('터치 시 즉시 실행', style: _ts(11, c: Colors.white60, w: FontWeight.w600)),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showClassMeal = true),
                  borderRadius: BorderRadius.circular(7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C896).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFF00C896).withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.restaurant_rounded, size: 14, color: Color(0xFF00C896)),
                        const SizedBox(width: 5),
                        Text('급식 식단표 띄우기',
                            style: _ts(12, w: FontWeight.w800, c: const Color(0xFF00C896))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // 수업 도구를 상하좌우 완벽한 정중앙으로 대칭 정렬!
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < row1.length; i++) ...[
                          if (i > 0) const SizedBox(width: 14),
                          buildToolCard(row1[i]),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < row2.length; i++) ...[
                          if (i > 0) const SizedBox(width: 14),
                          buildToolCard(row2[i]),
                        ],
                      ],
                    ),
                    // PRO 버전(Windows/Android): 수업시간에 도구 아래 시스템 앱 노출, 웹에서는 비워둠!
                    if (showSystemApps) ...[
                      const SizedBox(height: 14),
                      _buildSystemAppsRow(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [PRO 에디션] 수업 시간 도구 아래 설치된 시스템 앱 (Windows / Android) 바로가기 바
  Widget _buildSystemAppsRow() {
    if (kIsWeb) return const SizedBox.shrink();
    final hasNativeApps = _systemApps.isNotEmpty;
    final displayApps = hasNativeApps ? _systemApps.take(10).toList() : _defaultDemoSystemApps;

    return Container(
      constraints: const BoxConstraints(maxWidth: 780),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00F5D4).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  kIsWeb
                      ? Icons.apps_rounded
                      : (Platform.isWindows ? Icons.desktop_windows_rounded : Icons.android_rounded),
                  size: 14,
                  color: const Color(0xFF00F5D4),
                ),
                const SizedBox(width: 4),
                Text('시스템 앱', style: _ts(12, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final app in displayApps) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: InkWell(
                        onTap: () {
                          if (!kIsWeb) {
                            SystemAppScanner.launchApp(app.appId);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${app.name} 앱은 Windows / Android PRO 환경에서 바로 실행됩니다.'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withOpacity(0.09)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (app.iconPath != null &&
                                  app.iconPath!.isNotEmpty &&
                                  File(app.iconPath!).existsSync())
                                Image.file(File(app.iconPath!), width: 16, height: 16)
                              else
                                const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF00F5D4)),
                              const SizedBox(width: 5),
                              Text(app.name, style: _ts(12.5, w: FontWeight.w700, c: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              if (!kIsWeb) {
                showDialog(
                  context: context,
                  builder: (ctx) => const AppDrawerDialog(scale: 1.0),
                );
              }
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.grid_view_rounded, size: 13, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text('전체 앱', style: _ts(11, w: FontWeight.w700, c: Colors.white70)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [수업 중 + Cloud/USB 연결]: 세로 리스트형 파일 목록 + 그 아래 한 줄 가로 도구함
  Widget _classTimeCloudFilesAndToolbar({Key? key}) {
    return Column(
      key: key,
      children: [
        // 상단: Cloud/USB 파일 목록 (세로 리스트형!)
        Expanded(
          child: widget.cloudFilesWidget ??
              _glassSurface(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F5D4).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.cloud_rounded, color: Color(0xFF00F5D4), size: 17),
                        ),
                        const SizedBox(width: 8),
                        Text('클라우드 / USB 수업 자료', style: _ts(18, w: FontWeight.w800)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F5D4).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('연결됨',
                              style: _ts(11, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: widget.onCloudToggle,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.close_rounded, size: 13, color: Colors.white70),
                                const SizedBox(width: 4),
                                Text('닫기', style: _ts(11.5, w: FontWeight.w700, c: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        itemCount: _sampleFiles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (c, i) {
                          final f = _sampleFiles[i];
                          return _glassTile(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: f.$4.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(f.$5, color: f.$4, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(f.$1,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: _ts(15, w: FontWeight.w800)),
                                      const SizedBox(height: 2),
                                      Text('${f.$2} · ${f.$3}', style: _ts(11.5, c: Colors.white54)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00F5D4).withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('열기',
                                      style: _ts(11.5, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
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
        const SizedBox(height: 12),
        // 하단: 한 줄로 도구들이 뜨는 가로 툴바 바
        _singleRowToolbar(),
      ],
    );
  }

  /// 한 줄 가로 툴바 바
  Widget _singleRowToolbar() {
    return _glassSurface(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final t in _classTools)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
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
                  borderRadius: BorderRadius.circular(10),
                  child: _glassTile(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    radius: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.$1,
                            color: t.$2 == '급식' ? const Color(0xFF00C896) : const Color(0xFF00F5D4),
                            size: 18),
                        const SizedBox(width: 6),
                        Text(t.$2, style: _ts(14, w: FontWeight.w800, c: Colors.white)),
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

  /// [쉬는 시간 + Cloud/USB 연결]: 급식 위치에 리스트형 USB 파일함
  Widget _recessCloudPanel() {
    return _glassSurface(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        children: [
          // 상단: 탭 전환 [클라우드/USB 수업 자료] vs [급식 식단표]
          Row(
            children: [
              InkWell(
                onTap: () => setState(() => _recessTab = 0),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _recessTab == 0 ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_rounded,
                          size: 16, color: _recessTab == 0 ? Colors.black : Colors.white70),
                      const SizedBox(width: 5),
                      Text('클라우드 / USB 파일',
                          style: _ts(14,
                              w: FontWeight.w800,
                              c: _recessTab == 0 ? Colors.black : Colors.white70)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => setState(() => _recessTab = 1),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _recessTab == 1 ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.restaurant_rounded,
                          size: 16, color: _recessTab == 1 ? Colors.black : Colors.white70),
                      const SizedBox(width: 5),
                      Text('급식 식단표',
                          style: _ts(14,
                              w: FontWeight.w800,
                              c: _recessTab == 1 ? Colors.black : Colors.white70)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text('쉬는 시간 동안 다음 수업 준비 가능', style: _ts(12, c: Colors.white54)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _recessTab == 0
                ? (widget.cloudFilesWidget ??
                    ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      itemCount: _sampleFiles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (c, i) {
                        final f = _sampleFiles[i];
                        return _glassTile(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: f.$4.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(f.$5, color: f.$4, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(f.$1,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: _ts(15, w: FontWeight.w800)),
                                    const SizedBox(height: 2),
                                    Text('${f.$2} · ${f.$3}', style: _ts(11.5, c: Colors.white54)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00F5D4).withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('열기',
                                    style: _ts(11.5, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
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
                      const SizedBox(width: 12),
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

  static const Map<String, String> _allergyDescMap = {
    '난류': '달걀, 메추리알 등 가금류 난류 성분',
    '우유': '우유, 유당 및 유제품 성분',
    '메밀': '메밀가루 및 메밀 성분',
    '땅콩': '땅콩 및 견과류 기름 성분',
    '대두': '대두(콩), 두부, 된장, 간장 성분',
    '밀': '밀가루 및 글루텐 성분',
    '고등어': '고등어 및 등푸른생선 성분',
    '갑각': '새우, 게 등 갑각류 성분',
    '돼지': '돼지고기 및 돈육 가공 성분',
    '복숭아': '복숭아 및 생과일 성분',
    '토마토': '토마토 및 케첩 성분',
    '아황산': '아황산염 (식품 보존료)',
    '호두': '호두 및 견과류 성분',
    '닭고기': '닭고기 및 계육 가공 성분',
    '소고기': '소고기 및 우육 가공 성분',
    '오징어': '오징어 및 연체류 성분',
    '조개': '조개, 굴, 전복, 홍합 등 패류 성분',
    '잣': '잣 및 견과류 성분',
  };

  /// 메뉴를 꾹 누르면 뜨는 알레르기 정보 팝업
  void _showAllergyPopup(BuildContext context, MealDishItem dish) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF141721).withOpacity(0.96),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00F5D4).withOpacity(0.2),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.restaurant_menu_rounded, color: Color(0xFF00F5D4), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('메뉴 알레르기 유발 정보', style: _ts(13, c: const Color(0xFF00F5D4), w: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(dish.name, style: _ts(20, w: FontWeight.w900, c: Colors.white)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(height: 1, color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 16),
                if (dish.allergies.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00F5D4), size: 36),
                          const SizedBox(height: 10),
                          Text('등록된 주요 알레르기 유발 성분이 없습니다.', style: _ts(15, c: Colors.white70, w: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('안심하고 맛있게 식사하세요!', style: _ts(12.5, c: Colors.white38)),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Text('해당 메뉴 포함 알레르기 유발 성분:', style: _ts(14, c: Colors.white70, w: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in dish.allergies)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8906).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFF8906).withOpacity(0.6)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFFF8906)),
                              const SizedBox(width: 5),
                              Text(a, style: _ts(13, w: FontWeight.w900, c: const Color(0xFFFF8906))),
                              const SizedBox(width: 5),
                              Text('(${_allergyDescMap[a] ?? '주의'})', style: _ts(11, c: Colors.white70)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('※ 식품의약품안전처 고시 19대 알레르기 유발 식품 기준',
                      style: _ts(11.5, c: Colors.white38, w: FontWeight.w500)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F5D4),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('확인', style: _ts(15, w: FontWeight.w900, c: Colors.black)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// [월 급식표] 다이얼로그
  void _showMonthlyMealDialog(BuildContext context) {
    final now = widget.currentTime ?? DateTime.now();
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Container(
            width: 860,
            height: 600,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF141721).withOpacity(0.96),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00F5D4).withOpacity(0.2),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF00F5D4), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('이번 달 급식 식단표', style: _ts(13, c: const Color(0xFF00F5D4), w: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('${now.year}년 ${now.month}월 급식 현황', style: _ts(22, w: FontWeight.w900, c: Colors.white)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 26),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(height: 1, color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.separated(
                    itemCount: 20,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (c, i) {
                      final day = now.day - (now.weekday - 1) + (i - 5);
                      if (day < 1 || day > 31) return const SizedBox.shrink();
                      final date = DateTime(now.year, now.month, day);
                      if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
                        return const SizedBox.shrink();
                      }
                      final isToday = date.day == now.day && date.month == now.month;
                      final dummyMeal = MealDayInfo.generateDemo(date);
                      final dishNames = dummyMeal.dishes.map((d) => d.name).join(' · ');

                      return _glassTile(
                        selected: isToday,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        radius: 12,
                        child: Row(
                          children: [
                            Container(
                              width: 90,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: isToday ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: Text(
                                  '${date.month}/${date.day} (${_wd[date.weekday - 1]})${isToday ? ' 오늘' : ''}',
                                  style: _ts(13,
                                      w: FontWeight.w900,
                                      c: isToday ? Colors.black : Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                dishNames,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _ts(14.5,
                                    w: isToday ? FontWeight.w900 : FontWeight.w700,
                                    c: isToday ? const Color(0xFF00F5D4) : Colors.white),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(dummyMeal.calories, style: _ts(12.5, c: Colors.white54, w: FontWeight.w600)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// [쉬는 시간 미연결] 바닥 끝까지 시원하게 다 쓰는 급식 식단표 (알레르기 칩 제외 + 월 급식표 버튼 + 메뉴 꾹 누르면 팝업)
  Widget _mealTableFull() {
    return _glassSurface(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_rounded, color: Color(0xFF00F5D4), size: 20),
              const SizedBox(width: 8),
              Text('급식 식단표', style: _ts(19, w: FontWeight.w800)),
              const SizedBox(width: 8),
              Text('(메뉴 꾹 누르면 알레르기 정보)', style: _ts(12, c: Colors.white54)),
              const Spacer(),
              // 월 급식표 버튼
              InkWell(
                onTap: () => _showMonthlyMealDialog(context),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 14, color: Color(0xFF00F5D4)),
                      const SizedBox(width: 5),
                      Text('월 급식표', style: _ts(12, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                    ],
                  ),
                ),
              ),
              if (widget.onCloudToggle != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: widget.onCloudToggle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_sync_rounded, size: 13, color: Colors.white70),
                        const SizedBox(width: 5),
                        Text('Cloud 전환', style: _ts(11.5, w: FontWeight.w700, c: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _mealColumn('오늘 점심', widget.todayCalories, widget.todayDishes, true),
                ),
                const SizedBox(width: 12),
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

  /// [급식 메뉴 열]: 알레르기 칩 제외 (메뉴 텍스트 깔끔하고 큼직하게 유지) + 꾹 누르면 팝업!
  Widget _mealColumn(String title, String kcal, List<MealDishItem> dishes, bool today) {
    return _glassTile(
      selected: today,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              Text(title,
                  style: _ts(17, w: FontWeight.w800, c: today ? const Color(0xFF00F5D4) : Colors.white)),
              const Spacer(),
              if (kcal.isNotEmpty)
                Text(kcal, style: _ts(13, c: Colors.white54, w: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Container(height: 1.0, color: Colors.white.withOpacity(0.12)),
          const SizedBox(height: 4),
          Expanded(
            child: dishes.isEmpty
                ? Center(
                    child: Text('급식 정보가 없습니다.', style: _ts(14, c: Colors.white38)),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final d in dishes)
                        InkWell(
                          onTap: () => _showAllergyPopup(context, d),
                          onLongPress: () => _showAllergyPopup(context, d),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.circle, size: 5, color: Color(0xFF00F5D4)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    d.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _ts(17, w: FontWeight.w800, c: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 우측 끝에 세로로 독(Dock) 형태로 세운 도구함
  /// - 쉬는 시간에는 급식 버튼 제외! (급식 식단표가 화면에 상시 노출)
  /// - 설정 버튼 (⚙️) 포함!
  Widget _verticalToolbarDock({bool inClass = false}) {
    final toolsList = inClass ? _classTools : _recessTools;

    return _glassSurface(
      radius: 16,
      glow: true,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (int i = 0; i < toolsList.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: InkWell(
                  onTap: () {
                    final t = toolsList[i];
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
                    selected: i == 0,
                    radius: 12,
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(toolsList[i].$1,
                            size: 24,
                            color: i == 0 ? const Color(0xFF00F5D4) : Colors.white60),
                        const SizedBox(height: 2),
                        Text(toolsList[i].$2,
                            style: _ts(12,
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

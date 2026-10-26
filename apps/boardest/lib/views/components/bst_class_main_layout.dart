import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';
import '../../models/meal_models.dart';
import '../../models/app_settings.dart' show LauncherSlot;
import '../../config/app_config.dart';
import '../../services/system_app_scanner.dart';
import '../../services/update_service.dart';
import '../modals/app_drawer_dialog.dart';
import '../../services/meal_vote_service.dart';
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
  // 조/종례/점심시간 헤더 및 카운트다운 (해당 시간일 때만 노출)
  final String? activeSpecialPeriod; // '아침시간', '조회시간', '점심시간', '종례시간'
  final String? specialPeriodRemainingText;

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
    this.activeSpecialPeriod,
    this.specialPeriodRemainingText,
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
  final Set<String> _highlightedMealNames = {}; // 메뉴 꾹 누르면 형광펜 토글

  (String, String) _getTimesForPeriod(TimetablePeriodItem p) {
    if (p.startTime != null && p.endTime != null && p.startTime!.isNotEmpty) {
      return (p.startTime!, p.endTime!);
    }
    if (p.period >= 1 && p.period <= _defaultPeriodTimes.length) {
      return _defaultPeriodTimes[p.period - 1];
    }
    return ('09:00', '09:50');
  }

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

  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    _initCurrentPeriod();
    _loadSystemApps();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BstClassMainLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPeriodStatus != widget.currentPeriodStatus ||
        oldWidget.currentSubject != widget.currentSubject ||
        oldWidget.activeSpecialPeriod != widget.activeSpecialPeriod) {
      _initCurrentPeriod();
    }
  }

  void _initCurrentPeriod() {
    final hasSpecial = widget.activeSpecialPeriod != null && widget.activeSpecialPeriod!.isNotEmpty;
    if (hasSpecial) {
      _curIndex = -1;
      return;
    }
    final ep = _effectivePeriods;
    final idx = ep.indexWhere((p) => p.isCurrent);
    if (idx != -1) {
      _curIndex = idx;
    } else {
      _curIndex = -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Column(
          children: [
            // 상단: 백그라운드 업데이트 다운로드 진행 바 (승인 없이 무인 다운로드 시 표시)
            ValueListenableBuilder<UpdateState>(
              valueListenable: UpdateService.stateNotifier,
              builder: (ctx, state, _) {
                if (state != UpdateState.downloading) return const SizedBox.shrink();
                return ValueListenableBuilder<double>(
                  valueListenable: UpdateService.downloadProgressNotifier,
                  builder: (c, progress, _) {
                    final pct = (progress * 100).toInt();
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF00F5D4), Color(0xFF7F5AF0)],
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '🚀 새 버전(${UpdateService.latestVersion ?? '5.0.6'}) 백그라운드 다운로드 중... ($pct%)',
                            style: _ts(12, w: FontWeight.w900, c: Colors.black),
                          ),
                          const Spacer(),
                          const Text(
                            '수업 종료 후 쉬는 시간에 자동으로 교체할 수 있습니다.',
                            style: TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. 좌측 시간표 (더 얇고 세로 전체 채움: 200px)
                    SizedBox(
                      width: 200,
                      child: _leftWheelArea(),
                    ),
                    const SizedBox(width: 14),
                    // 2. 우측 시계 + (수업/급식) + BST 도구 1열 (나머지 전체 확장)
                    Expanded(
                      child: _rightContentArea(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────── 1. 좌측 시간표 리스트 (Today's Timetable) ─────────
  Widget _leftWheelArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _brandBadge(),
        const SizedBox(height: 10),
        Expanded(
          child: _leftTimetableList(),
        ),
      ],
    );
  }

  TimetablePeriodItem _currentOrSelectedPeriod() {
    final ep = _effectivePeriods;
    if (_curIndex >= 0 && _curIndex < ep.length) {
      return ep[_curIndex];
    }
    final cur = ep.indexWhere((p) => p.isCurrent);
    if (cur != -1) {
      return ep[cur];
    }
    if (ep.isNotEmpty) {
      return ep.first;
    }
    return TimetablePeriodItem(
      period: 1,
      subject: widget.currentSubject.isNotEmpty ? widget.currentSubject : '수업 준비 중',
      isCurrent: true,
    );
  }

  Widget _leftTimetableList() {
    final ep = _effectivePeriods;
    final special = widget.activeSpecialPeriod;
    final hasSpecial = special != null && special.isNotEmpty;
    final n = ep.length;

    int specialInsertIndex = 0;
    if (hasSpecial) {
      if (special.contains('아침') || special.contains('조회')) {
        specialInsertIndex = 0;
      } else if (special.contains('점심')) {
        specialInsertIndex = 4.clamp(0, n);
      } else if (special.contains('종례')) {
        specialInsertIndex = n;
      }
    }

    final items = <Widget>[];

    for (int i = 0; i < n; i++) {
      if (hasSpecial && i == specialInsertIndex) {
        items.add(_compactSpecialPeriodCard(special));
      }
      final p = ep[i];
      final isSelected = (i == _curIndex) || (_curIndex == -1 && p.isCurrent);
      items.add(_compactTimetableItem(p, i, isSelected));
    }
    if (hasSpecial && specialInsertIndex >= n) {
      items.add(_compactSpecialPeriodCard(special));
    }

    return _glassSurface(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6, right: 4),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: Color(0xFF00F5D4), size: 15),
                const SizedBox(width: 6),
                Text('오늘의 시간표', style: _ts(14, w: FontWeight.w800)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('총 $n교시', style: _ts(10.5, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 6),
          // 6교시, 7교시 등 교시 수에 맞게 위부터 아래까지 세로로 균등하게 꽉 채움!
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int idx = 0; idx < items.length; idx++) ...[
                  if (idx > 0) const SizedBox(height: 5),
                  Expanded(child: items[idx]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [오늘의 시간표 카드]: 좌측 교시+과목명+시간 / 우측 교과서 사진 / 배경 은은한 교과서 워터마크
  Widget _compactTimetableItem(TimetablePeriodItem p, int i, bool isSelected) {
    final times = _getTimesForPeriod(p);
    final start = times.$1;
    final end = times.$2;
    final inClass = _isClassTime && p.isCurrent;

    return GestureDetector(
      onTap: () {
        setState(() => _curIndex = i);
        widget.onPeriodTap?.call(i);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.08),
              width: isSelected ? 1.8 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00F5D4).withOpacity(0.25),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Stack(
            children: [
              // 1. 배경에 은은하게 교과서 사진
              Positioned.fill(
                child: Opacity(
                  opacity: 0.12,
                  child: _buildBookCoverWidget(p.subject, radius: 0),
                ),
              ),
              // 반투명 어두운 그라디언트 오버레이 (가독성 확보)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFF141923).withOpacity(isSelected ? 0.75 : 0.88),
                        const Color(0xFF141923).withOpacity(isSelected ? 0.50 : 0.70),
                      ],
                    ),
                  ),
                ),
              ),
              // 2. 내용: 좌측 교시 + 과목명 + 시작/끝 시간, 우측 교과서 사진
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 좌측: 교시 순서 뱃지
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${p.period}',
                        style: _ts(
                          12.5,
                          w: FontWeight.w900,
                          c: isSelected ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    // 과목명 및 시작 끝
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.subject,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _ts(
                                    14,
                                    w: FontWeight.w800,
                                    c: isSelected ? const Color(0xFF00F5D4) : Colors.white,
                                  ),
                                ),
                              ),
                              if (inClass) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00F5D4).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text('수업중', style: _ts(8.5, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(
                            start,
                            maxLines: 1,
                            style: _ts(9.5, c: Colors.white70, w: FontWeight.w600),
                          ),
                          Text(
                            end,
                            maxLines: 1,
                            style: _ts(9.0, c: Colors.white54, w: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 우측: 교과서 사진 썸네일 (확대된 시인성)
                    Center(
                      child: SizedBox(
                        width: 34,
                        height: 47,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.35),
                                blurRadius: 4,
                                offset: const Offset(1, 2),
                              ),
                            ],
                          ),
                          child: _buildBookCoverWidget(p.subject, radius: 5, isMini: true),
                        ),
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

  Widget _compactSpecialPeriodCard(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC857).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFC857).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC857).withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.restaurant_rounded, color: Color(0xFFFFC857), size: 14),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _ts(12.5, w: FontWeight.w900, c: const Color(0xFFFFC857))),
                Text(
                  widget.specialPeriodRemainingText ?? '일과 진행 중',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _ts(9, c: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandBadge() {
    final title = widget.isSpecialRoom
        ? (widget.specialSubjectName ?? '전용 교실')
        : '${widget.schoolName} · ${widget.gradeClass}';

    return _glassSurface(
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/icons/logo.png',
              width: 24,
              height: 24,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('BOARDEST', style: _ts(13, w: FontWeight.w900)),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withOpacity(0.16),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF00F5D4), width: 0.8),
                      ),
                      child: Text('v5.1.0', style: _ts(8.5, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
                    ),
                    if (!kIsWeb) ...[
                      const SizedBox(width: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('PRO', style: _ts(8.0, w: FontWeight.w800, c: Colors.white70)),
                      ),
                    ],
                  ],
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _ts(10.5, w: FontWeight.w600, c: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeSpecialPeriodCard(String title, double h, double w) {
    Color accentColor = const Color(0xFF00F5D4);
    IconData icon = Icons.wb_sunny_rounded;
    String subtitle = '상쾌하고 활기찬 아침 시간!';
    if (title.contains('조회')) {
      accentColor = const Color(0xFFFFC857);
      icon = Icons.campaign_rounded;
      subtitle = '오늘 하루 일정과 공지사항을 확인하세요';
    } else if (title.contains('점심')) {
      accentColor = const Color(0xFF00C896);
      icon = Icons.restaurant_rounded;
      subtitle = '맛있는 점심 시간! 친구들과 즐겁게 식사하세요';
    } else if (title.contains('종례')) {
      accentColor = const Color(0xFFFF6B6B);
      icon = Icons.school_rounded;
      subtitle = '오늘 하루도 정말 수고 많았습니다!';
    }

    final remainingText = widget.specialPeriodRemainingText ?? '';

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withOpacity(0.25),
            const Color(0xFF141923).withOpacity(0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.85), width: 2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.22),
              shape: BoxShape.circle,
              border: Border.all(color: accentColor.withOpacity(0.6), width: 1.5),
            ),
            child: Icon(icon, color: accentColor, size: 32),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _ts(34, w: FontWeight.w900, c: Colors.white, ls: -1),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: _ts(13.5, w: FontWeight.w600, c: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (remainingText.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accentColor, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, color: accentColor, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    remainingText,
                    style: _ts(16, w: FontWeight.w800, c: Colors.white),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWheel(BoxConstraints bc) => _leftTimetableList();

  Widget _buildSpecialPeriodCover(String special) {
    Color g1 = const Color(0xFF0F3443);
    Color g2 = const Color(0xFF00F5D4);
    String icon = '☀️';
    String tag = '아침 활동';
    if (special.contains('조회')) {
      g1 = const Color(0xFFE65100); g2 = const Color(0xFFFFC857); icon = '📢'; tag = '학급 조회';
    } else if (special.contains('점심')) {
      g1 = const Color(0xFF00796B); g2 = const Color(0xFF00C896); icon = '🍱'; tag = '점심 시간';
    } else if (special.contains('종례')) {
      g1 = const Color(0xFF8B0000); g2 = const Color(0xFFFF6B6B); icon = '🏫'; tag = '학급 종례';
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(colors: [g1, g2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(tag, style: _ts(13, w: FontWeight.w900, c: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  /// [현재 선택된 과목 카드]: 조/종례/점심시간에는 과목명 대신 해당 시간을 크게 텍스트로 노출
  /// - 수업 중에는 교과서 크기를 아담하게 줄이고, 교과서 바로 옆에 디지털 시계(HH:mm) 배치
  Widget _currentPeriodCard(TimetablePeriodItem p) {
    final times = _getTimesForPeriod(p);
    final start = times.$1;
    final end = times.$2;
    final inClass = _isClassTime && p.isCurrent;

    final special = widget.activeSpecialPeriod;
    final hasSpecial = special != null && special.isNotEmpty;

    final displayTitle = hasSpecial ? special : p.subject;
    final badgeLabel = hasSpecial
        ? '$special 진행 중'
        : (inClass ? '${p.period}교시 · 수업 진행 중' : '${p.period}교시 · 다음 수업');

    String subText = '·  [전자교과서] ${p.subject}';
    if (hasSpecial) {
      if (special.contains('조회')) {
        subText = '·  오늘 하루 일정과 공지사항을 확인하세요';
      } else if (special.contains('점심')) {
        subText = '·  맛있는 점심 시간! 친구들과 즐겁게 식사하세요';
      } else if (special.contains('종례')) {
        subText = '·  오늘 하루도 정말 수고 많았습니다!';
      } else {
        subText = '·  상쾌하고 활기찬 하루의 시작!';
      }
    }

    if (inClass) {
      // ══════════════════════════════════════════════════════════
      // [수업 모드 전용 레이아웃]: 상하 100% 꽉 채우기
      // 상단: 날짜 바 & 교시 뱃지
      // 중단: 교과서(크기 대폭 축소) + 그 옆에 대형 디지털 시계 (HH:mm)
      // 하단: 과목명 크게(FittedBox) + 학급 정보
      // ══════════════════════════════════════════════════════════
      final now = widget.currentTime ?? DateTime.now();
      final date = '${now.year}년 ${now.month}월 ${now.day}일 (${_wd[now.weekday - 1]})';
      String two(int v) => v.toString().padLeft(2, '0');

      return _glassSurface(
        glow: true,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 상단 정보 바 (날짜, 교시 진행 뱃지, 교시 시간)
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: Color(0xFF00F5D4), size: 16),
                const SizedBox(width: 8),
                Text(date, style: _ts(15, w: FontWeight.w700, c: Colors.white)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_circle_fill_rounded, size: 13, color: Colors.black),
                      const SizedBox(width: 4),
                      Text(badgeLabel, style: _ts(12, w: FontWeight.w900, c: Colors.black)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('$start ~ $end', style: _ts(13, w: FontWeight.w700, c: Colors.white70)),
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
                      child: Text(widget.ddayLabel!, style: _ts(12, w: FontWeight.w700, c: const Color(0xFF00F5D4))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 2. 중앙: 시원하게 키운 교과서 표지 + 그 옆에 대형 시계 (HH:mm) 나란히 배치!
            Expanded(
              flex: 5,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 시원하게 키운 교과서 표지 (높이에 맞추어 비율 유지)
                  AspectRatio(
                    aspectRatio: 0.72,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 14,
                            offset: const Offset(2, 6),
                          ),
                        ],
                      ),
                      child: hasSpecial
                          ? _buildSpecialPeriodCover(special)
                          : _buildBookCoverWidget(p.subject, radius: 14),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // 교과서 바로 옆에 뜨는 시계 (HH:mm)
                  Expanded(
                    child: GestureDetector(
                      onLongPress: widget.onClockLongPress,
                      child: Container(
                        height: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text(
                              '${two(now.hour)}:${two(now.minute)}',
                              style: _ts(200, w: FontWeight.w900, h: 0.85, ls: -4, c: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. 하단: 과목명 크게 + 학급 정보 (담당 텍스트 삭제)
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      displayTitle,
                      style: _ts(68, w: FontWeight.w900, h: 1.05),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.school_rounded, color: Color(0xFF00F5D4), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        widget.gradeClass.isNotEmpty ? widget.gradeClass : '우리반',
                        style: _ts(17, w: FontWeight.w800, c: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          subText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _ts(14.5, w: FontWeight.w600, c: Colors.white60),
                        ),
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

    // 쉬는 시간 / 방과 후 기본 카드
    return _glassSurface(
      glow: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 단정한 교과서 또는 특수 일과 전용 커버
          AspectRatio(
            aspectRatio: 0.72,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
              child: hasSpecial
                  ? _buildSpecialPeriodCover(special)
                  : _buildBookCoverWidget(p.subject, radius: 12),
            ),
          ),
          const SizedBox(width: 18),
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
                        color: (inClass || hasSpecial) ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            (inClass || hasSpecial) ? Icons.play_circle_fill_rounded : Icons.schedule_rounded,
                            size: 14,
                            color: (inClass || hasSpecial) ? Colors.black : Colors.white70,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            badgeLabel,
                            style: _ts(13, w: FontWeight.w900, c: (inClass || hasSpecial) ? Colors.black : Colors.white),
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
                      child: Text(
                        hasSpecial && (widget.specialPeriodRemainingText != null)
                            ? widget.specialPeriodRemainingText!
                            : '$start ~ $end',
                        style: _ts(14, w: FontWeight.w700, c: Colors.white70),
                      ),
                    ),
                  ],
                ),
                // 과목명 또는 특수 일과 텍스트 크게 표시
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    displayTitle,
                    style: _ts(64, w: FontWeight.w900, h: 1.05),
                  ),
                ),
                // 학급 정보 & 교과서/특수일과 안내 (담당 텍스트 삭제)
                Row(
                  children: [
                    const Icon(Icons.school_rounded, color: Color(0xFF00F5D4), size: 17),
                    const SizedBox(width: 6),
                    Text(
                      widget.gradeClass.isNotEmpty ? widget.gradeClass : '우리반',
                      style: _ts(15, w: FontWeight.w800, c: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        subText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _ts(13.5, w: FontWeight.w600, c: Colors.white60),
                      ),
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

  /// [비선택 과목 카드] M3 서페이스 + 교과서 썸네일 블록형
  Widget _thumbnailBlockCard(TimetablePeriodItem p, bool isPast, int idx) {
    final times = _getTimesForPeriod(p);
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
              height: 66,
              child: _buildBookCoverWidget(p.subject, radius: 7, isMini: true),
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
              Text(start, style: _ts(11, c: isPast ? Colors.white24 : Colors.white70, w: FontWeight.w600)),
              Text(end, style: _ts(10.5, c: isPast ? Colors.white24 : Colors.white54, w: FontWeight.w500)),
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

    final isDemoCover = AppConfig.isDemoMode || widget.schoolName.contains('데모');
    if (isDemoCover) {
      // 데모 버전 전용 신규 모던 일러스트형 교과서 표지 테마
      if (subject.contains('국어') || subject.contains('문학')) {
        grad1 = const Color(0xFF3A1C71); grad2 = const Color(0xFFD76D77); icon = '🖋️'; category = 'DEMO 국어';
      } else if (subject.contains('수학')) {
        grad1 = const Color(0xFF0F2027); grad2 = const Color(0xFF00B4DB); icon = '💠'; category = 'DEMO 수학';
      } else if (subject.contains('영어')) {
        grad1 = const Color(0xFF1A2980); grad2 = const Color(0xFF26D0CE); icon = '🌐'; category = 'DEMO 영어';
      } else if (subject.contains('과학') || subject.contains('물리') || subject.contains('화학') || subject.contains('생물')) {
        grad1 = const Color(0xFF134E5E); grad2 = const Color(0xFF71B280); icon = '🧬'; category = 'DEMO 과학';
      } else if (subject.contains('역사') || subject.contains('사회')) {
        grad1 = const Color(0xFF4B1248); grad2 = const Color(0xFFF0C27B); icon = '🧭'; category = 'DEMO 사회';
      } else if (subject.contains('정보') || subject.contains('AI') || subject.contains('컴퓨터')) {
        grad1 = const Color(0xFF0F0C29); grad2 = const Color(0xFF7F5AF0); icon = '🤖'; category = 'DEMO 정보';
      } else if (subject.contains('체육') || subject.contains('스포츠')) {
        grad1 = const Color(0xFF11998E); grad2 = const Color(0xFF38EF7D); icon = '🏅'; category = 'DEMO 체육';
      } else if (subject.contains('음악') || subject.contains('미술') || subject.contains('예술')) {
        grad1 = const Color(0xFF833AB4); grad2 = const Color(0xFFFD1D1D); icon = '🎭'; category = 'DEMO 예술';
      } else {
        grad1 = const Color(0xFF1F1C2C); grad2 = const Color(0xFF928DAB); icon = '✨'; category = 'DEMO 교과';
      }
    }

    if (isMini) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(colors: [grad1, grad2], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: isDemoCover ? const Color(0xFF00F5D4).withOpacity(0.55) : Colors.white.withOpacity(0.2)),
        ),
        alignment: Alignment.center,
        child: Text(icon, style: TextStyle(fontSize: isDemoCover ? 14 : 15)),
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
                    Text(isDemoCover ? '2026 미래형 데모교과서' : '중학교 교과서', style: _ts(12.5, w: FontWeight.w700, c: Colors.white70)),
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
                  child: Text(isDemoCover ? 'BOARDEST 스마트북' : '디지털 교과서 TBP', style: _ts(11, w: FontWeight.w800, c: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [수업 시간용 상단 시계 카드]: 절반 상단 전체 차지
  Widget _inClassClockCard() {
    final now = widget.currentTime ?? DateTime.now();
    final date = '${now.year}년 ${now.month}월 ${now.day}일 (${_wd[now.weekday - 1]})';
    String two(int v) => v.toString().padLeft(2, '0');

    return GestureDetector(
      onLongPress: widget.onClockLongPress,
      child: _glassSurface(
        glow: true,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상단: 날짜 + 수업 진행 중 뱃지 + D-day
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: Color(0xFF00F5D4), size: 16),
                const SizedBox(width: 8),
                Text(date, style: _ts(16, w: FontWeight.w700, c: Colors.white)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF00F5D4), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_circle_fill_rounded, size: 13, color: Color(0xFF00F5D4)),
                      const SizedBox(width: 4),
                      Text('수업 진행 중', style: _ts(12, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
                    ],
                  ),
                ),
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
                      child: Text(widget.ddayLabel!, style: _ts(12.5, w: FontWeight.w700, c: const Color(0xFF00F5D4))),
                    ),
                  ),
              ],
            ),
            // 중앙: 대형 디지털 시계 (HH:mm:ss)
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    '${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
                    style: _ts(160, w: FontWeight.w900, h: 0.9, ls: -3, c: Colors.white),
                  ),
                ),
              ),
            ),
            // 하단: 수업 잔여 시간 / 알림 안내
            Row(
              children: [
                const Icon(Icons.timer_outlined, color: Color(0xFF00F5D4), size: 17),
                const SizedBox(width: 7),
                Text(
                  widget.clockRemainingDetailText ?? '수업 진행 중',
                  style: _ts(14.5, c: Colors.white70, w: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// [수업 시간용 하단 교과서 & 과목명 카드]: 절반 하단 전체 차지
  Widget _inClassSubjectCard(TimetablePeriodItem p) {
    final times = _getTimesForPeriod(p);
    final start = times.$1;
    final end = times.$2;
    final special = widget.activeSpecialPeriod;
    final hasSpecial = special != null && special.isNotEmpty;
    final displayTitle = hasSpecial ? special : p.subject;
    final badgeLabel = hasSpecial ? '$special' : '${p.period}교시';

    return _glassSurface(
      glow: true,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 교과서 표지 (aspectRatio 0.72)
          AspectRatio(
            aspectRatio: 0.72,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
              child: hasSpecial
                  ? _buildSpecialPeriodCover(special)
                  : _buildBookCoverWidget(p.subject, radius: 12),
            ),
          ),
          const SizedBox(width: 18),
          // 2. 과목명 + 교시/시간 정보 + 학급
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(badgeLabel, style: _ts(13, w: FontWeight.w900, c: Colors.black)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('$start ~ $end', style: _ts(12.5, w: FontWeight.w700, c: Colors.white70)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    displayTitle,
                    style: _ts(56, w: FontWeight.w900, h: 1.05),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.school_rounded, color: Color(0xFF00F5D4), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      widget.gradeClass.isNotEmpty ? widget.gradeClass : '우리반',
                      style: _ts(14.5, w: FontWeight.w800, c: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        hasSpecial ? '·  특수 일과 진행 중' : '·  [전자교과서] ${p.subject}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _ts(13, w: FontWeight.w600, c: Colors.white60),
                      ),
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

  // ───────── 2. 우측 콘텐츠 영역 ─────────
  Widget _rightContentArea() {
    final inClass = _isClassTime;
    final activePeriod = _currentOrSelectedPeriod();

    if (inClass) {
      // ─── [수업 중 모드: 좌측 절반(상단 시계, 하단 교과서+과목명) + 우측 통째로 도구함] ───
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 좌측 절반: 상단 시계 + 하단 교과서와 과목명
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: _inClassClockCard(),
                ),
                const SizedBox(height: 12),
                Expanded(
                  flex: 5,
                  child: _inClassSubjectCard(activePeriod),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // 우측: 통째로 도구 패널 (급식/Cloud 누르면 해당 패널로 오버레이 전환)
          Expanded(
            flex: 1,
            child: _buildInClassRightPanel(),
          ),
        ],
      );
    } else {
      // ─── [쉬는 시간 / 방과 후 모드] ───
      // 상단: 시계 조금 좌측 + 우측 원형 쉬는시간 얼마 남았는지 띄움 (시계 높이 확대: 280)
      // 하단: 지금 수업과 급식 (2열 그대로)
      // 그 아래: BST 도구 1열
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 280,
            child: _recessTimeLargeClock(),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 1,
                  child: _currentPeriodCard(activePeriod),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: (widget.isCloudActive && widget.showCloudFiles && widget.cloudFilesWidget != null)
                      ? _recessCloudPanel()
                      : ValueListenableBuilder<UpdateState>(
                          valueListenable: UpdateService.stateNotifier,
                          builder: (ctx, updateState, _) {
                            if (updateState == UpdateState.downloaded) {
                              return _updateRequiredCard();
                            }
                            return _mealTableFull();
                          },
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: _buildHorizontalToolsRow(inClass: false),
          ),
        ],
      );
    }
  }

  /// [수업 중 우측 패널]: 수업 도구 기본 노출, 급식이나 Cloud를 누르면 해당 패널로 가려지고 교체
  Widget _buildInClassRightPanel() {
    if (_showClassMeal) {
      return Stack(
        children: [
          Positioned.fill(child: _mealTableFull()),
          Positioned(
            top: 10,
            right: 10,
            child: InkWell(
              onTap: () => setState(() => _showClassMeal = false),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.isCloudActive && widget.showCloudFiles && widget.cloudFilesWidget != null) {
      return Stack(
        children: [
          Positioned.fill(child: widget.cloudFilesWidget!),
          Positioned(
            top: 10,
            right: 10,
            child: InkWell(
              onTap: () => widget.onCloudToggle?.call(),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      );
    }

    return _classToolsGrid(key: const ValueKey('class_tools_grid'));
  }

  Widget _buildHorizontalToolsRow({required bool inClass}) {
    final tools = inClass ? _classTools : _recessTools;
    final canUseSystemApps = !kIsWeb && (widget.isPro || Platform.isWindows || Platform.isAndroid);
    final customSlots = canUseSystemApps ? (widget.customSlots ?? const <LauncherSlot>[]) : const <LauncherSlot>[];

    return _glassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tool in tools) ...[
            Expanded(
              child: InkWell(
                onTap: () {
                  if (tool.$2 == '급식') {
                    if (inClass) {
                      setState(() => _showClassMeal = true);
                    } else {
                      _showMonthlyMealDialog(context);
                    }
                  } else if (tool.$2 == 'Cloud') {
                    widget.onCloudToggle?.call();
                  } else {
                    widget.onToolTap?.call(tool.$5);
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: _glassTile(
                  radius: 10,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: tool.$4.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: tool.$4.withOpacity(0.4), width: 1.1),
                        ),
                        child: Icon(tool.$1, color: tool.$4, size: 17),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tool.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _ts(13.5, w: FontWeight.w800, c: Colors.white),
                            ),
                            Text(
                              tool.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _ts(9.5, c: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          for (int idx = 0; idx < customSlots.length; idx++) ...[
            Expanded(
              child: InkWell(
                onTap: () {
                  final slot = customSlots[idx];
                  if (widget.onLaunchApp != null) {
                    widget.onLaunchApp!(slot);
                  } else {
                    SystemAppScanner.launchApp(slot.id);
                  }
                },
                onLongPress: () => widget.onRemoveApp?.call(idx),
                borderRadius: BorderRadius.circular(10),
                child: _glassTile(
                  radius: 10,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F5D4).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.45)),
                        ),
                        alignment: Alignment.center,
                        child: (customSlots[idx].iconPath != null &&
                                customSlots[idx].iconPath!.isNotEmpty &&
                                File(customSlots[idx].iconPath!).existsSync())
                            ? Image.file(File(customSlots[idx].iconPath!), width: 20, height: 20)
                            : const Icon(Icons.apps_rounded, color: Color(0xFF00F5D4), size: 17),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customSlots[idx].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _ts(13, w: FontWeight.w800, c: Colors.white),
                            ),
                            Text(
                              '시스템 앱',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _ts(9.5, c: const Color(0xFF00F5D4)),
                            ),
                          ],
                        ),
                      ),
                      if (widget.onRemoveApp != null)
                        InkWell(
                          onTap: () => widget.onRemoveApp?.call(idx),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 2),
                            child: Icon(Icons.close_rounded, size: 13, color: Colors.white38),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (canUseSystemApps && widget.onAddAppTap != null)
            Tooltip(
              message: '도구함에 시스템 앱 추가',
              child: InkWell(
                onTap: widget.onAddAppTap,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, color: Color(0xFF00F5D4), size: 20),
                      const SizedBox(width: 4),
                      Text('앱 추가', style: _ts(12, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static const _wd = ['월', '화', '수', '목', '금', '토', '일'];

  /// [수업 시간용 시계]: HH:mm 만 뜨게 가운데쯤 위치
  Widget _classTimeCompactClock() {
    final now = widget.currentTime ?? DateTime.now();
    final date = '${now.year}년 ${now.month}월 ${now.day}일 (${_wd[now.weekday - 1]})';

    return GestureDetector(
      onLongPress: widget.onClockLongPress,
      child: _glassSurface(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: Color(0xFF00F5D4), size: 16),
                const SizedBox(width: 7),
                Text(date, style: _ts(16, w: FontWeight.w700, c: Colors.white)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('수업 진행 중', style: _ts(11, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
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
                      child: Text(widget.ddayLabel!, style: _ts(12.5, w: FontWeight.w700, c: const Color(0xFF00F5D4))),
                    ),
                  ),
              ],
            ),
            // 시계 HH:mm 만 뜨게 가운데쯤 위치
            Expanded(
              child: Center(
                child: Builder(
                  builder: (c) {
                    final t = widget.currentTime ?? DateTime.now();
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

  /// [쉬는 시간용 시계]: 시계는 조금 좌측으로, 우측에 원형으로 쉬는시간 얼마 남았는지 띄움
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
              child: Row(
                children: [
                  // 시계를 조금 좌측으로 배치
                  Expanded(
                    child: Align(
                      alignment: const Alignment(-0.25, 0.0),
                      child: Builder(
                        builder: (c) {
                          final t = widget.currentTime ?? DateTime.now();
                          String two(int v) => v.toString().padLeft(2, '0');
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
                              style: _ts(240, w: FontWeight.w900, h: 0.9, ls: -4, c: Colors.white),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // 우측에 원형으로 쉬는시간 얼마 남았는지 띄움
                  _buildRecessCircularTimer(),
                ],
              ),
            ),
            // 쉬는 시간 안내 문구
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

  /// [우측 원형 쉬는 시간 타이머]
  Widget _buildRecessCircularTimer() {
    final elapsed = widget.clockRemainingProgress ?? 0.0;
    final remaining = (1.0 - elapsed).clamp(0.0, 1.0);

    String timeMain = '';
    String timeSub = '남은 시간';

    final detail = widget.clockRemainingDetailText ?? '';
    if (detail.contains('남음')) {
      final clean = detail.replaceAll('남음', '').replaceAll('쉬는시간', '').replaceAll('쉬는 시간', '').trim();
      timeMain = clean;
    } else if (detail.isNotEmpty) {
      timeMain = detail;
    } else {
      timeMain = '휴식 중';
    }

    return Container(
      width: 145,
      height: 145,
      margin: const EdgeInsets.only(right: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 배경 트랙
          SizedBox(
            width: 135,
            height: 135,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 9,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.08)),
            ),
          ),
          // 잔여 시간 프로그레스 아크
          SizedBox(
            width: 135,
            height: 135,
            child: CircularProgressIndicator(
              value: remaining > 0 ? remaining : 1.0,
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00F5D4)),
              backgroundColor: Colors.transparent,
            ),
          ),
          // 중앙 잔여 시간 텍스트
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined, color: Color(0xFF00F5D4), size: 20),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    timeMain,
                    style: _ts(17, w: FontWeight.w900, c: Colors.white, h: 1.1),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeSub,
                  style: _ts(10.5, w: FontWeight.w700, c: const Color(0xFF00F5D4)),
                ),
              ],
            ),
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
        // [수업 중 미연결] 도구 모음 그리드 (급식 버튼 포함 + 설정 버튼 포함)
        return _classToolsGrid(key: const ValueKey('class_tools_grid'));
      } else {
        // [수업 중 + Cloud/USB 연결] 세로 리스트형 파일함 + 그 아래 1줄 가로 도구함
        return _classTimeCloudFilesAndToolbar(key: const ValueKey('class_files_tools'));
      }
    } else {
      if (!widget.isCloudActive) {
        // [쉬는 시간 미연결] 급식 식단표 + 우측 세로 독
        // 최신 버전 다운로드 완료 시 수업시간에는 보류하고, 쉬는시간에 급식 대신 [업데이트 필요함!!] 카드 노출!
        return Row(
          key: const ValueKey('recess_meal_dock'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ValueListenableBuilder<UpdateState>(
                valueListenable: UpdateService.stateNotifier,
                builder: (ctx, updateState, _) {
                  if (updateState == UpdateState.downloaded) {
                    return _updateRequiredCard();
                  }
                  return _mealTableFull();
                },
              ),
            ),
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

  /// [쉬는 시간용] 급식 대신 노출되는 대형 업데이트 필요 알림 카드
  Widget _updateRequiredCard() {
    final isWin = !kIsWeb && Platform.isWindows;
    final ver = UpdateService.latestVersion ?? '5.0.6';

    return _glassSurface(
      padding: const EdgeInsets.all(28),
      glow: true,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withOpacity(0.18),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFF6B6B), width: 2),
              ),
              child: const Icon(
                Icons.system_update_rounded,
                color: Color(0xFFFF6B6B),
                size: 56,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '⚠️ 업데이트 필요함!!',
              style: _ts(32, w: FontWeight.w900, c: const Color(0xFFFF6B6B)),
            ),
            const SizedBox(height: 12),
            Text(
              'Boardest 최신 버전(v$ver) 패키지가 백그라운드에서 다운로드되었습니다.',
              textAlign: TextAlign.center,
              style: _ts(17, w: FontWeight.w800, c: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              isWin
                  ? '설치 버튼을 누르면 즉시 교체 설치가 진행되고 앱이 자동으로 다시 시작됩니다.'
                  : '설치 버튼을 누른 후 시스템 화면에서 수동 설치를 완료해 주세요.',
              textAlign: TextAlign.center,
              style: _ts(13, c: Colors.white60, w: FontWeight.w600),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => UpdateService.executeInstall(context),
                  icon: const Icon(Icons.download_done_rounded, size: 22, color: Colors.black),
                  label: Text('지금 즉시 설치 및 적용', style: _ts(16, w: FontWeight.w900, c: Colors.black)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 8,
                  ),
                ),
                const SizedBox(width: 14),
                OutlinedButton(
                  onPressed: () => UpdateService.stateNotifier.value = UpdateState.idle,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('급식표 보기', style: _ts(14, w: FontWeight.w700, c: Colors.white60)),
                ),
              ],
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

    Widget buildToolCard((IconData, String, String, Color, BstToolType) tool, {double? height}) {
      return SizedBox(
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
                      children: [
                        for (int i = 0; i < row1.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(child: buildToolCard(row1[i])),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        for (int i = 0; i < row2.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(child: buildToolCard(row2[i])),
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

  /// [PRO 에디션] 수업 시간 도구 아래 설치된 시스템 앱 바로가기 (Windows / Android 공통 지원 + 직접 앱 추가/제거)
  Widget _buildSystemAppsRow() {
    if (kIsWeb) return const SizedBox.shrink();
    final customSlots = widget.customSlots ?? const <LauncherSlot>[];
    final hasNativeApps = _systemApps.isNotEmpty;
    final fallbackApps = hasNativeApps ? _systemApps.take(4).toList() : _defaultDemoSystemApps.take(4).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      Platform.isWindows ? Icons.desktop_windows_rounded : Icons.android_rounded,
                      size: 14,
                      color: const Color(0xFF00F5D4),
                    ),
                    const SizedBox(width: 5),
                    Text('시스템 앱 바로가기', style: _ts(12, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                  ],
                ),
              ),
              const Spacer(),
              if (widget.onAddAppTap != null) ...[
                InkWell(
                  onTap: widget.onAddAppTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded, size: 14, color: Color(0xFF00F5D4)),
                        const SizedBox(width: 3),
                        Text('시스템 앱 넣기', style: _ts(11, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
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
                      Text('전체 앱 보기', style: _ts(11, c: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // 1) 사용자가 직접 등록한 시스템 앱 슬롯 우선 표시
              for (int i = 0; i < customSlots.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (widget.onLaunchApp != null) {
                        widget.onLaunchApp!(customSlots[i]);
                      } else {
                        SystemAppScanner.launchApp(customSlots[i].id);
                      }
                    },
                    onLongPress: () => widget.onRemoveApp?.call(i),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.35)),
                      ),
                      child: Row(
                        children: [
                          if (customSlots[i].iconPath != null &&
                              customSlots[i].iconPath!.isNotEmpty &&
                              File(customSlots[i].iconPath!).existsSync())
                            Image.file(File(customSlots[i].iconPath!), width: 24, height: 24)
                          else
                            const Icon(Icons.apps_rounded, size: 22, color: Color(0xFF00F5D4)),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              customSlots[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _ts(13, w: FontWeight.w800, c: Colors.white),
                            ),
                          ),
                          if (widget.onRemoveApp != null)
                            InkWell(
                              onTap: () => widget.onRemoveApp?.call(i),
                              child: const Icon(Icons.close_rounded, size: 15, color: Colors.white54),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              // 2) 사용자 슬롯이 비어있을 경우 기본 추천 시스템 앱 노출
              if (customSlots.isEmpty)
                for (int i = 0; i < fallbackApps.length && i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => SystemAppScanner.launchApp(fallbackApps[i].appId),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Row(
                          children: [
                            if (fallbackApps[i].iconPath != null &&
                                fallbackApps[i].iconPath!.isNotEmpty &&
                                File(fallbackApps[i].iconPath!).existsSync())
                              Image.file(File(fallbackApps[i].iconPath!), width: 24, height: 24)
                            else
                              const Icon(Icons.apps_rounded, size: 22, color: Color(0xFF00F5D4)),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                fallbackApps[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _ts(13, w: FontWeight.w800, c: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              // 3) 시스템 앱 추가 슬롯 카드 (최대 4개 미만일 때 표시)
              if (widget.onAddAppTap != null && customSlots.length < 4) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: widget.onAddAppTap,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_circle_outline_rounded, size: 20, color: Color(0xFF00F5D4)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '앱 추가',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _ts(13, w: FontWeight.w800, c: const Color(0xFF00F5D4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
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

  /// [통합 메뉴 상세 다이얼로그]: 메뉴를 꾹 누르면 투표 내역 / 형광펜 여부 / 알레르기 상세 다 띄우고 +10표 버튼도 지원!
  void _showDishFullDetailDialog(BuildContext context, MealDishItem dish, {required bool isToday}) {
    final allergyStr = _formatDishAllergies(dish);

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final classVotes = MealVoteService.instance.getClassVotes(dish.name);
            final total = MealVoteService.instance.getTotalVotes(dish.name);
            final isHighlighted = _highlightedMealNames.contains(dish.name);
            final canVote = AppConfig.isDemoMode || (isToday && _isMealVoteTimeNow());

            return AlertDialog(
              backgroundColor: const Color(0xFF141721),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: const Color(0xFF00F5D4).withOpacity(0.5), width: 1.5),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.restaurant_rounded, color: Color(0xFF00F5D4), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dish.name, style: _ts(19, w: FontWeight.w900, c: Colors.white)),
                        const SizedBox(height: 2),
                        Text('현재 전교 총 $total표 득표', style: _ts(13, c: const Color(0xFFFF6B6B), w: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 형광펜 토글 버튼
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (_highlightedMealNames.contains(dish.name)) {
                            _highlightedMealNames.remove(dish.name);
                          } else {
                            _highlightedMealNames.add(dish.name);
                          }
                        });
                        setDialogState(() {});
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(
                          color: isHighlighted
                              ? const Color(0xFFFFEE55).withOpacity(0.22)
                              : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isHighlighted ? const Color(0xFFFFD166) : Colors.white24,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isHighlighted ? Icons.brush_rounded : Icons.brush_outlined,
                              color: isHighlighted ? const Color(0xFFFFD166) : Colors.white70,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isHighlighted ? '형광펜 강조 해제하기' : '이 메뉴 형광펜으로 칠하기',
                              style: _ts(13.5,
                                  w: FontWeight.w800,
                                  c: isHighlighted ? const Color(0xFFFFD166) : Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. 알레르기 유발 식품 상세
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF00F5D4)),
                              const SizedBox(width: 6),
                              Text('알레르기 유발 성분', style: _ts(13, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            allergyStr.isNotEmpty ? allergyStr : '알레르기 유발 성분 없음 (안심 식단)',
                            style: _ts(13, c: allergyStr.isNotEmpty ? Colors.white : Colors.white60, w: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 3. 반별 투표 내역
                    Text('반별 득표 현황', style: _ts(13.5, w: FontWeight.w800, c: Colors.white70)),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 140),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: classVotes.isEmpty
                          ? Center(
                              child: Text('아직 등록된 투표 내역이 없습니다.', style: _ts(12.5, c: Colors.white38)),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                for (final entry in classVotes.entries)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.04),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.meeting_room_outlined, size: 14, color: Color(0xFF00F5D4)),
                                        const SizedBox(width: 6),
                                        Text(entry.key, style: _ts(13, w: FontWeight.w700, c: Colors.white)),
                                        const Spacer(),
                                        Text('${entry.value}표',
                                            style: _ts(13, w: FontWeight.w900, c: const Color(0xFFFF6B6B))),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 14),

                    // 4. 한 번에 10표 올리는 버튼 (연속 선택 가능!)
                    if (canVote) ...[
                      ElevatedButton.icon(
                        onPressed: () async {
                          // 10표 올리기 (로컬에 즉시 +10표 반영, 서버 폭주 없음)
                          final sId = widget.schoolName.isNotEmpty ? widget.schoolName : 'Demo';
                          final cKey = widget.gradeClass.isNotEmpty ? widget.gradeClass : '우리반';
                          final now = widget.currentTime ?? DateTime.now();
                          await MealVoteService.instance.recordLocalVote(
                            schoolId: sId,
                            date: DateTime(now.year, now.month, now.day),
                            dishName: dish.name,
                            classKey: cKey,
                            amount: 10,
                          );
                          setDialogState(() {});
                          setState(() {});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('🔥 ${dish.name}에 10표를 투표했습니다! (현재 총 ${MealVoteService.instance.getTotalVotes(dish.name)}표)'),
                                backgroundColor: const Color(0xFF00C896),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.local_fire_department_rounded, color: Colors.black, size: 18),
                        label: Text('🔥 한 번에 10표 올리기 (+10표)', style: _ts(13.5, w: FontWeight.w900, c: Colors.black)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F5D4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        child: Text(
                          isToday ? '※ 점심시간 종료 5분 전이 지나 투표가 마감되었습니다.' : '※ 당일 급식에만 투표할 수 있습니다.',
                          style: _ts(11, c: Colors.white38),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('확인', style: _ts(14, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// [월 급식표] 달력형 다이얼로그 (알레르기 필터 칩 + 꾹 누르면 알레르기/형광펜 + 메뉴 옆 ❤️득표수 노출)
  void _showMonthlyMealDialog(BuildContext context) {
    final now = widget.currentTime ?? DateTime.now();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.78),
      builder: (ctx) {
        DateTime displayMonth = DateTime(now.year, now.month, 1);
        String? selectedAllergy;
        final highlighted = Set<String>.from(_highlightedMealNames);

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final daysInMonth = DateTime(displayMonth.year, displayMonth.month + 1, 0).day;
            
            // Generate list of all school days (Mon-Fri) for this month
            final schoolDays = <DateTime>[];
            for (int d = 1; d <= daysInMonth; d++) {
              final date = DateTime(displayMonth.year, displayMonth.month, d);
              if (date.weekday != DateTime.saturday && date.weekday != DateTime.sunday) {
                schoolDays.add(date);
              }
            }

            final allergyNames = [
              '난류', '우유', '메밀', '땅콩', '대두', '밀', '고등어', '게', '새우',
              '돼지고기', '복숭아', '토마토', '아황산염', '호두', '닭고기', '쇠고기', '오징어', '조개류'
            ];

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Container(
                width: 1080,
                height: 700,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF141721).withOpacity(0.97),
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 헤더: 이번 달 급식 달력 & 닫기 (현재 달 고정)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F5D4).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF00F5D4), size: 22),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${displayMonth.year}년 ${displayMonth.month}월 급식 달력 (이번 달)',
                          style: _ts(20, w: FontWeight.w900, c: Colors.white),
                        ),
                        const Spacer(),
                        Text(
                          '※ 메뉴 꾹 누르면 형광펜 & 알레르기 & 투표 정보',
                          style: _ts(11.5, c: Colors.white54),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 24),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 2. 알레르기 필터 칩 바
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // 전체 해제
                          InkWell(
                            onTap: () => setDialogState(() => selectedAllergy = null),
                            child: Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: selectedAllergy == null
                                    ? const Color(0xFF00F5D4).withOpacity(0.2)
                                    : Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selectedAllergy == null
                                      ? const Color(0xFF00F5D4)
                                      : Colors.white24,
                                ),
                              ),
                              child: Text(
                                '전체 보기',
                                style: _ts(11.5,
                                    w: FontWeight.w800,
                                    c: selectedAllergy == null ? const Color(0xFF00F5D4) : Colors.white70),
                              ),
                            ),
                          ),
                          for (final a in allergyNames) ...[
                            InkWell(
                              onTap: () {
                                setDialogState(() {
                                  selectedAllergy = (selectedAllergy == a ? null : a);
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: selectedAllergy == a
                                      ? const Color(0xFFFF9800).withOpacity(0.3)
                                      : Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: selectedAllergy == a
                                        ? const Color(0xFFFF9800)
                                        : Colors.white24,
                                    width: selectedAllergy == a ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Text(
                                  a,
                                  style: _ts(
                                    11.5,
                                    w: FontWeight.w800,
                                    c: selectedAllergy == a ? const Color(0xFFFF9800) : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 6),
                    // 3. 요일 헤더 (월 화 수 목 금)
                    Row(
                      children: [
                        for (final dayName in ['월', '화', '수', '목', '금'])
                          Expanded(
                            child: Center(
                              child: Text(
                                dayName,
                                style: _ts(14, w: FontWeight.w900, c: const Color(0xFF00F5D4)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 4. 달력 그리드
                    Expanded(
                      child: GridView.builder(
                        itemCount: schoolDays.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          childAspectRatio: 1.05,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemBuilder: (c, idx) {
                          final date = schoolDays[idx];
                          final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
                          final meal = MealDayInfo.generateDemo(date);

                          return Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? const Color(0xFF00F5D4).withOpacity(0.12)
                                  : Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isToday ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.08),
                                width: isToday ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '${date.month}/${date.day} (${_wd[date.weekday - 1]})',
                                      style: _ts(12,
                                          w: FontWeight.w900,
                                          c: isToday ? const Color(0xFF00F5D4) : Colors.white),
                                    ),
                                    if (isToday) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00F5D4),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: Text('오늘', style: _ts(8.5, w: FontWeight.w900, c: Colors.black)),
                                      ),
                                    ],
                                    const Spacer(),
                                    Text(meal.calories, style: _ts(9.5, c: Colors.white38)),
                                  ],
                                ),
                                const Divider(color: Colors.white12, height: 8),
                                Expanded(
                                  child: ListView(
                                    children: [
                                      for (final dish in meal.dishes) ...[
                                        Builder(builder: (dishCtx) {
                                          final hasAllergy = selectedAllergy != null &&
                                              (dish.allergies.contains(selectedAllergy) ||
                                                  _formatDishAllergies(dish).contains(selectedAllergy!));
                                          final isMarked = highlighted.contains(dish.name);
                                          final votes = MealVoteService.instance.getTotalVotes(dish.name);
                                          final heartStr = votes > 0 ? ' ❤️$votes' : '';

                                          return InkWell(
                                            onLongPress: () {
                                              _showDishFullDetailDialog(context, dish, isToday: isToday);
                                            },
                                            child: Container(
                                              margin: const EdgeInsets.only(bottom: 2),
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: hasAllergy
                                                    ? const Color(0xFFFF9800).withOpacity(0.35)
                                                    : (isMarked ? const Color(0xFFFFEE55).withOpacity(0.35) : Colors.transparent),
                                                borderRadius: BorderRadius.circular(4),
                                                border: hasAllergy
                                                    ? Border.all(color: const Color(0xFFFF9800), width: 1.2)
                                                    : (isMarked ? Border.all(color: const Color(0xFFFFD166), width: 1) : null),
                                              ),
                                              child: Text(
                                                '${dish.name}$heartStr',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: _ts(
                                                  11,
                                                  w: (hasAllergy || isMarked) ? FontWeight.w900 : FontWeight.w600,
                                                  c: hasAllergy
                                                      ? const Color(0xFFFFD180)
                                                      : (isMarked ? const Color(0xFFFFEE55) : Colors.white),
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
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
            );
          },
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
              Text('(메뉴 꾹 누르면 반별 득표 현황)', style: _ts(12, c: Colors.white54)),
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
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: _mealColumn('오늘 점심', widget.todayCalories, widget.todayDishes, true),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 1,
                  child: _mealColumn(
                    widget.tomorrowDateLabel.isNotEmpty ? widget.tomorrowDateLabel : '다음 급식',
                    widget.tomorrowCalories,
                    widget.tomorrowDishes,
                    false,
                  ),
                ),
              ],
            ),
          ),
          // 사용자 요청 안내 문구 작게 표기
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '※ 투표는 당일 점심시간 5분 전까지 가능하며, 점심시간부터 득표수가 공개됩니다. (메뉴를 꾹 누르면 반별 득표 현황 확인)',
              style: _ts(11, c: Colors.white54, w: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 알레르기 코드/번호를 한국어 식재료명으로 변환
  String _formatDishAllergies(MealDishItem d) {
    if (d.allergies.isEmpty) return '';
    final names = d.allergies.map((a) {
      final code = int.tryParse(a);
      if (code != null && MealDayInfo.allergyCodeMap.containsKey(code)) {
        return MealDayInfo.allergyCodeMap[code]!;
      }
      return a;
    }).toSet().toList();
    return names.join(', ');
  }

  bool _isMealVoteTimeNow() {
    if (AppConfig.isDemoMode) return true;
    final now = widget.currentTime ?? DateTime.now();
    final special = widget.activeSpecialPeriod ?? '';
    if (special.contains('점심')) return true;
    final mins = now.hour * 60 + now.minute;
    // 당일 아침부터 점심 종료 5분 전(13:20)까지 언제든 투표 가능!
    return mins < (13 * 60 + 20);
  }

  bool _isMealVoteResultTimeNow() {
    final now = widget.currentTime ?? DateTime.now();
    final special = widget.activeSpecialPeriod ?? '';
    if (special.contains('점심')) return true;
    final mins = now.hour * 60 + now.minute;
    return mins >= (12 * 60 + 15);
  }

  /// [급식 메뉴 열]: 오늘과 내일 1:1 분할, 메뉴명 바로 아래 알레르기 정보 표시, 꾹 누르면 반별 득표 현황!
  Widget _mealColumn(String title, String kcal, List<MealDishItem> dishes, bool today) {
    return _glassTile(
      selected: today,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                title,
                style: _ts(17, w: FontWeight.w800, c: today ? const Color(0xFF00F5D4) : Colors.white),
              ),
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
                      for (final d in dishes) ...[
                        Builder(
                          builder: (context) {
                            final isHighlighted = _highlightedMealNames.contains(d.name);
                            final allergyStr = _formatDishAllergies(d);
                            final isResultTime = _isMealVoteResultTimeNow();

                            return InkWell(
                              onTap: () {
                                _showDishFullDetailDialog(context, d, isToday: today);
                              },
                              onLongPress: () {
                                _showDishFullDetailDialog(context, d, isToday: today);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: isHighlighted
                                      ? const Color(0xFFFFEE55).withOpacity(0.35)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isHighlighted
                                      ? Border.all(color: const Color(0xFFFFD166), width: 1.5)
                                      : null,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 6,
                                      color: isHighlighted
                                          ? const Color(0xFFFFD166)
                                          : const Color(0xFF00F5D4),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            d.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: _ts(
                                              16,
                                              w: FontWeight.w800,
                                              c: isHighlighted
                                                  ? const Color(0xFFFFEE55)
                                                  : Colors.white,
                                            ),
                                          ),
                                          if (allergyStr.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 1),
                                              child: Text(
                                                '알레르기: $allergyStr',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: _ts(
                                                  11,
                                                  c: isHighlighted
                                                      ? const Color(0xFFFFEE55).withOpacity(0.9)
                                                      : Colors.white54,
                                                  w: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (today) ...[
                                      InkWell(
                                        onTap: () async {
                                          final sId = widget.schoolName.isNotEmpty ? widget.schoolName : 'Demo';
                                          final cKey = widget.gradeClass.isNotEmpty ? widget.gradeClass : '우리반';
                                          final now = widget.currentTime ?? DateTime.now();
                                          await MealVoteService.instance.recordLocalVote(
                                            schoolId: sId,
                                            date: DateTime(now.year, now.month, now.day),
                                            dishName: d.name,
                                            classKey: cKey,
                                            amount: 10,
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('🔥 ${d.name}에 10표를 투표했습니다! (현재 총 ${MealVoteService.instance.getTotalVotes(d.name)}표)'),
                                                backgroundColor: const Color(0xFF00C896),
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                            setState(() {});
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF00F5D4).withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.5)),
                                          ),
                                          child: Text('+10', style: _ts(11, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    // 점심시간 투표 기능 및 점심시간 전/후 득표수 분기 (점심시간 전에는 표수 숨김)
                                    ValueListenableBuilder<Map<String, Map<String, int>>>(
                                      valueListenable: MealVoteService.instance.votesNotifier,
                                      builder: (ctx, _, __) {
                                        final votes = MealVoteService.instance.getTotalVotes(d.name);
                                        return InkWell(
                                          onTap: () async {
                                            if (today && _isMealVoteTimeNow()) {
                                              await widget.onMealVote?.call(d.name);
                                              if (context.mounted) setState(() {});
                                            }
                                          },
                                          borderRadius: BorderRadius.circular(10),
                                          child: Container(
                                            margin: const EdgeInsets.only(left: 2),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: votes > 0
                                                  ? const Color(0xFFFF6B6B).withOpacity(0.22)
                                                  : Colors.white.withOpacity(0.06),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: votes > 0
                                                    ? const Color(0xFFFF6B6B).withOpacity(0.65)
                                                    : Colors.white24,
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  votes > 0 ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                                  color: votes > 0 ? const Color(0xFFFF6B6B) : Colors.white60,
                                                  size: 14,
                                                ),
                                                if (isResultTime) ...[
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '$votes표',
                                                    style: _ts(
                                                      11.5,
                                                      w: FontWeight.w800,
                                                      c: votes > 0 ? const Color(0xFFFF6B6B) : Colors.white70,
                                                    ),
                                                  ),
                                                ] else if (votes > 0) ...[
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${votes}표',
                                                    style: _ts(
                                                      10.5,
                                                      w: FontWeight.w800,
                                                      c: const Color(0xFFFF6B6B),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
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

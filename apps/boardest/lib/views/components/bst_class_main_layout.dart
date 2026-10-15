import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'bst_app_header.dart';
import 'bst_today_timetable_strip.dart';
import 'bst_giant_clock.dart';
import 'bst_lesson_info_card.dart';
import 'bst_dual_meal_card.dart';
import '../../models/meal_models.dart';
import 'bst_tools_dock.dart';
import 'bst_class_tools_panel.dart';
import '../../models/app_settings.dart' show LauncherSlot;

export 'bst_today_timetable_strip.dart';
export 'bst_tools_dock.dart';
export '../../models/meal_models.dart';
export '../../models/app_settings.dart' show LauncherSlot;

/// Boardest 전자칠판 메인 골든 레이아웃
/// - 교과서 좌측 밀착 & 일과 시간표
/// - 전고(Full Height) 롱-사이즈 수업도구 독 (시간표 옆, 시계 옆, 하단 카드 옆 상시 노출)
/// - 전용 교실 모드: 최상단 교과명 강조, 교과서 대신 들어오는 반 대형 표기
/// - Cloud 활성화 시 파일 탐색기 인라인 렌더링 지원
class BstClassMainLayout extends StatelessWidget {
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

  Widget _buildLessonInfoCard() {
    return BstLessonInfoCard(
      currentSubject: currentSubject,
      subjectDescription: subjectDescription,
      nextSubject: nextSubject,
      nextSubjectRoom: nextSubjectRoom,
      subjectIcon: subjectIcon,
      textbookImagePath: currentTextbookImagePath,
      textbookBytes: currentTextbookBytes,
      remainingTimeText: remainingTimeText,
      onTap: onLessonInfoTap,
    );
  }

  Widget _buildMealCard() {
    return BstDualMealCard(
      schoolName: schoolName,
      todayDishes: todayDishes,
      todayCalories: todayCalories,
      tomorrowDishes: tomorrowDishes,
      tomorrowCalories: tomorrowCalories,
      tomorrowDateLabel: tomorrowDateLabel,
      isCloudActive: isCloudActive,
      onCloudToggle: onCloudToggle,
      currentTime: currentTime,
      lunchStartTime: lunchStartTime,
      lunchEndTime: lunchEndTime,
      onVote: onMealVote,
      onShowVoteBreakdown: onShowVoteBreakdown,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = scaleFactor.clamp(0.5, 4.0);

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(12 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 최상단 고정 헤더 바 (로고, 학교/학급 이름 또는 전용교실 교과명, 윈도우 제어)
              BstAppHeader(
                appName: appName,
                schoolName: schoolName,
                gradeClass: gradeClass,
                isWindows: isWindows,
                onLogoTap: onLogoTap,
                onMinimizeTap: onMinimizeTap,
                onCloseTap: onCloseTap,
                isCloudActive: isCloudActive,
                onCloudTap: onCloudToggle,
                isSpecialRoom: isSpecialRoom,
                specialSubjectName: specialSubjectName,
              ),

              SizedBox(height: 10 * s),

              // 2. 메인 대시보드 2열 레이아웃
              // 좌측(flex: 1): 대형 시계 (flex: 2) : [평소: 급식 2단 / Cloud: 수업카드] (flex: 3) = 2 : 3
              // 우측(flex: 1): 일과 시간표 (flex: 2) : [평소: 수업카드 / Cloud: Cloud패널] (flex: 7) : 수업도구함 (flex: 1) = 2 : 7 : 1
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // [좌측 열 (가로 flex: 1)]
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. 대형 시계 (세로 flex: 2, 40%)
                          Expanded(
                            flex: 2,
                            child: BstGiantClock(
                              accentColor: isWindows
                                  ? const Color(0xFF60CDFF)
                                  : const Color(0xFF00F5D4),
                              onLongPress: onClockLongPress,
                              onDdayLongPress: onDdayLongPress,
                              dateLabel: dateString,
                              ddayLabel: ddayLabel,
                              remainingTimeText: clockRemainingDetailText,
                              remainingProgress: clockRemainingProgress,
                            ),
                          ),

                          SizedBox(height: 10 * s),

                          // 2. 좌측 하단 (세로 flex: 3, 60%)
                          // 평소에는 급식 식단표 (2단), Cloud 활성화 시에는 지금 수업 카드
                          Expanded(
                            flex: 3,
                            child: (isCloudActive && showCloudFiles)
                                ? _buildLessonInfoCard()
                                : _buildMealCard(),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(width: 10 * s),

                    // [우측 열 (가로 flex: 1)]: 일과 (1) : 중단 (7) : 도구함 (1) = 1 : 7 : 1
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. 일과 시간표 스트립 (세로 flex: 1)
                          Expanded(
                            flex: 1,
                            child: BstTodayTimetableStrip(
                              periods: periods,
                              onPeriodTap: onPeriodTap,
                              getTextbookPath: getTextbookPath,
                              getTextbookBytes: getTextbookBytes,
                              isSpecialRoom: isSpecialRoom,
                            ),
                          ),

                          SizedBox(height: 10 * s),

                          // 2. 우측 중단 (세로 flex: 7, 70%)
                          // 평소에는 지금&다음 수업 카드, Cloud 활성화 시에는 Cloud 탐색 패널
                          Expanded(
                            flex: 7,
                            child: (isCloudActive && showCloudFiles && cloudFilesWidget != null)
                                ? cloudFilesWidget!
                                : _buildLessonInfoCard(),
                          ),

                          SizedBox(height: 10 * s),

                          // 3. 수업 도구함 (세로 flex: 1, 10%)
                          Expanded(
                            flex: 1,
                            child: BstToolsDock(
                              isPro: isPro,
                              isWindows: isWindows,
                              onToolTap: onToolTap,
                              onAddAppTap: onAddAppTap,
                              onMinimizeTap: onMinimizeTap,
                              onCloseTap: onCloseTap,
                              customSlots: customSlots,
                              onLaunchApp: onLaunchApp,
                              onRemoveApp: onRemoveApp,
                              onAddAppToSlot: onAddAppToSlot,
                            ),
                          ),
                        ],
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

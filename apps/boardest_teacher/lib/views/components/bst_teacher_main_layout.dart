import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../services/update_service.dart';

class BstTeacherMainLayout extends StatelessWidget {
  final String schoolName;
  final String teacherName;
  final String homeroomClass;
  final bool hasPasskey;
  final VoidCallback? onRegisterPasskey;

  final String currentTab;
  final ValueChanged<String>? onTabSelected;
  final Widget? activeContent;

  final Widget? teacherTimetableWidget;
  final Widget? homeroomTimetableWidget;
  final Widget? todayTimetableWidget;
  final Widget? dashboardFilesWidget;
  final bool isHomeroom;

  final String currentOtp;
  final int remainingOtpSeconds;
  final VoidCallback? onOpenPopups;
  final VoidCallback? onResumeLesson;
  final VoidCallback? onStartQuickLesson;
  final VoidCallback? onCreateQuickMaterial;

  final bool isLoggedIn;
  final String? userEmail;
  final VoidCallback? onLoginPressed;
  final VoidCallback? onLogoutPressed;

  const BstTeacherMainLayout({
    super.key,
    this.schoolName = '보데스트 중학교',
    this.teacherName = '김보데',
    this.homeroomClass = '1학년 7반',
    this.isHomeroom = true,
    this.hasPasskey = true,
    this.onRegisterPasskey,
    this.currentTab = 'timetable',
    this.onTabSelected,
    this.activeContent,
    this.teacherTimetableWidget,
    this.homeroomTimetableWidget,
    this.todayTimetableWidget,
    this.dashboardFilesWidget,
    this.currentOtp = '------',
    this.remainingOtpSeconds = 60,
    this.onOpenPopups,
    this.onResumeLesson,
    this.onStartQuickLesson,
    this.onCreateQuickMaterial,
    this.isLoggedIn = false,
    this.userEmail,
    this.onLoginPressed,
    this.onLogoutPressed,
  });

  static const _nav = <(IconData, String, String)>[
    (Icons.dashboard_rounded, '대시보드', 'dashboard'),
    (Icons.calendar_month_rounded, '시간표', 'timetable'),
    (Icons.add_circle_outline_rounded, '새로 만들기', 'create'),
    (Icons.folder_open_rounded, '파일 관리', 'files'),
    (Icons.restaurant_rounded, '급식', 'meal'),
    (Icons.mark_email_unread_rounded, '쪽지', 'memo'),
    (Icons.draw_rounded, '판서 관리함', 'archive'),
  ];

  static const _mockFiles = <(String, String, String, Color, IconData)>[];

  static const _mockTodaySchedule = [
    ('1교시', '09:00', '2-1반', '수학 II', Color(0xFF4D96FF), false),
    ('2교시', '10:00', '연구실', '수업 준비 (공강)', Colors.white24, false),
    ('3교시', '11:00', '2-3반', '수학 II', Color(0xFF4D96FF), false),
    ('4교시', '12:00', '3-2반', '수학 I (현재 진행)', Color(0xFF00F5D4), true),
    ('5교시', '13:40', '3-4반', '기하와 벡터', Color(0xFF7F5AF0), false),
    ('6교시', '14:40', '1-2반', '수학 동아리', Color(0xFFFF8906), false),
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

  Widget _surface({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    double radius = 16,
    bool glow = false,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF141721).withOpacity(0.88),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: glow ? const Color(0xFF00F5D4).withOpacity(0.45) : Colors.white.withOpacity(0.1),
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: const Color(0xFF00F5D4).withOpacity(0.15),
                  blurRadius: 18,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: child,
    );
  }

  Widget _tile({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    double radius = 12,
    bool selected = false,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF00F5D4).withOpacity(0.14) : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? const Color(0xFF00F5D4).withOpacity(0.4) : Colors.white.withOpacity(0.08),
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 슬림 사이드바 내비게이션 (너비 210px)
              SizedBox(
                width: 210,
                child: _sidebar(),
              ),
              const SizedBox(width: 16),
              // 2. 메인 컨텐츠 영역
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: (currentTab == 'dashboard' || currentTab == 'home')
                      ? _dashboardHomeK()
                      : (currentTab == 'timetable' || currentTab == 'weekly_timetable'
                          ? _weeklyTimetableSubPage()
                          : (activeContent ?? const SizedBox())),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────── 사이드바 ─────────
  Widget _sidebar() {
    return _surface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/icons/logo.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('BOARDEST', style: _ts(14, w: FontWeight.w900, h: 1.1)),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F5D4).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF00F5D4), width: 0.8),
                        ),
                        child: Text('v${UpdateService.currentVersion}', style: _ts(8.5, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
                      ),
                    ],
                  ),
                  Text(kIsWeb ? 'Teacher' : 'Teacher PRO', style: _ts(12, w: FontWeight.w700, c: const Color(0xFF00F5D4))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (final nav in _nav)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () => onTabSelected?.call(nav.$3),
                borderRadius: BorderRadius.circular(10),
                child: _tile(
                  selected: currentTab == nav.$3,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(nav.$1, size: 18, color: currentTab == nav.$3 ? const Color(0xFF00F5D4) : Colors.white60),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          nav.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _ts(13.5,
                              w: currentTab == nav.$3 ? FontWeight.w800 : FontWeight.w500,
                              c: currentTab == nav.$3 ? Colors.white : Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Spacer(),
          // 설정 바로가기 버튼
          InkWell(
            onTap: () => onTabSelected?.call('settings'),
            borderRadius: BorderRadius.circular(10),
            child: _tile(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  const Icon(Icons.settings_rounded, size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text('설정', style: _ts(13, w: FontWeight.w700, c: Colors.white70)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 교사 계정 정보 카드
          _tile(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF00F5D4),
                  child: Text(
                    teacherName.isNotEmpty ? teacherName[0] : '선',
                    style: _ts(14, w: FontWeight.w900, c: Colors.black),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$teacherName 선생님', style: _ts(12.5, w: FontWeight.w800)),
                      Text(schoolName, style: _ts(10.5, c: Colors.white54)),
                    ],
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────── Teacher K안 대시보드 홈 ─────────
  // [좌측: 교사 세로 시간표 타임라인] + [우측 상단: OTP & Drive용량] + [우측 하단: 세로 리스트형 Cloud 파일함]
  Widget _dashboardHomeK() {
    return KeyedSubtree(
      key: const ValueKey('teacher_k_dashboard'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 좌측: 교사 세로 시간표 타임라인 (너비 310px)
          SizedBox(
            width: 310,
            child: _teacherVerticalTimelineCard(),
          ),
          const SizedBox(width: 16),
          // 2. 우측: 상단(OTP + Drive) + 하단(세로 리스트형 Cloud 파일함)
          Expanded(
            child: Column(
              children: [
                _topHeader('내 수업 자료 & 클라우드'),
                const SizedBox(height: 12),
                // 우측 상단: [OTP 와이드 카드] + [Drive 사용 용량 카드] 2개 나란히
                SizedBox(
                  height: 155,
                  child: Row(
                    children: [
                      Expanded(flex: 5, child: _otpCardWideK()),
                      const SizedBox(width: 14),
                      Expanded(flex: 4, child: _driveStorageCardCompact()),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // 우측 하단: 실제 업로드된 Cloud 파일함 (더미 파일 완전 제거!)
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: dashboardFilesWidget ?? _fileListView(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topHeader(String title) {
    return Row(
      children: [
        Text(title, style: _ts(22, w: FontWeight.w900)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(Icons.sync_rounded, color: Color(0xFF00F5D4), size: 16),
              const SizedBox(width: 6),
              Text('Google Drive 실시간 연동됨',
                  style: _ts(12, c: const Color(0xFF00F5D4), w: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (onResumeLesson != null)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF00F5D4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onResumeLesson,
            icon: const Icon(Icons.play_circle_outline_rounded, size: 16, color: Color(0xFF00F5D4)),
            label: Text('이어서 하기', style: _ts(12, w: FontWeight.w800)),
          ),
      ],
    );
  }

  /// [K안 좌측: 교사 세로 타임라인 시간표 카드]
  Widget _teacherVerticalTimelineCard() {
    return _surface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 18, color: Color(0xFF00F5D4)),
              const SizedBox(width: 8),
              Text('교사 오늘 시간표', style: _ts(16, w: FontWeight.w900)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('오늘 일과', style: _ts(11, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: todayTimetableWidget != null
                ? todayTimetableWidget!
                : ListView.separated(
              itemCount: _mockTodaySchedule.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (c, i) {
                final sc = _mockTodaySchedule[i];
                return _tile(
                  selected: sc.$6,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sc.$1,
                              style: _ts(15,
                                  w: FontWeight.w900,
                                  c: sc.$6 ? const Color(0xFF00F5D4) : Colors.white60)),
                          Text(sc.$2, style: _ts(11.5, c: Colors.white38)),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sc.$3, style: _ts(14, w: FontWeight.w800)),
                            Text(sc.$4,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _ts(12, c: sc.$6 ? const Color(0xFF00F5D4) : Colors.white60)),
                          ],
                        ),
                      ),
                      if (sc.$6)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F5D4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('수업 중',
                              style: _ts(10.5, w: FontWeight.w900, c: Colors.black)),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => onTabSelected?.call('weekly_timetable'),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_month_rounded, size: 15, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text('주간 전체 시간표 열기', style: _ts(13, w: FontWeight.w700, c: Colors.white70)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [K안 우측 상단 OTP 와이드 카드]
  Widget _otpCardWideK() {
    final progress = (remainingOtpSeconds / 60.0).clamp(0.0, 1.0);

    return _surface(
      glow: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 6,
                    color: const Color(0xFF00F5D4),
                    backgroundColor: Colors.white.withOpacity(0.1),
                  ),
                ),
                const Icon(Icons.key_rounded, color: Color(0xFF00F5D4), size: 28),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text('전자칠판 OTP: ', style: _ts(13, c: Colors.white70)),
                    Text(currentOtp,
                        style: _ts(22, w: FontWeight.w900, c: Colors.white, ls: 2.0)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('유효시간 ${remainingOtpSeconds}초 남음 · 칠판에 입력 시 잠금 해제',
                    style: _ts(11, c: Colors.white54)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: onRegisterPasskey,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.qr_code_2_rounded, size: 14, color: Colors.black),
                        const SizedBox(width: 4),
                        Text('스마트폰 QR로 칠판 로그인',
                            style: _ts(11, w: FontWeight.w900, c: Colors.black)),
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

  /// [K안 우측 상단 앱 보관자료 용량 카드] (앱 차지 용량만 표기)
  Widget _driveStorageCardCompact() {
    return _surface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded, size: 16, color: Color(0xFF00F5D4)),
              const SizedBox(width: 6),
              Text('Boardest 보관함 용량', style: _ts(13.5, w: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('동기화 완료', style: _ts(10.5, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('앱 보관자료 142.8 MB 사용 중', style: _ts(14.5, w: FontWeight.w900, c: Colors.white)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                  value: 0.18,
                  minHeight: 6,
                  color: Color(0xFF00F5D4),
                  backgroundColor: Colors.white12,
                ),
              ),
            ],
          ),
          Text('내 교안, 판서, 교과서만 안전하게 백업 중', style: _ts(11, c: Colors.white54)),
        ],
      ),
    );
  }

  Widget _chipsAndSearchRow() {
    return Row(
      children: [
        for (final t in ['전체', 'PDF', 'PPT', 'HWP', 'TBP 교과서', 'HTMLP', '판서'])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: t == '전체' ? const Color(0xFF00F5D4) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                t,
                style: _ts(12,
                    w: t == '전체' ? FontWeight.w900 : FontWeight.w600,
                    c: t == '전체' ? Colors.black : Colors.white70),
              ),
            ),
          ),
        const Spacer(),
        Container(
          width: 220,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 16, color: Colors.white38),
              const SizedBox(width: 6),
              Text('자료 검색...', style: _ts(12, c: Colors.white38)),
            ],
          ),
        ),
      ],
    );
  }

  /// [우측 하단: 세로 리스트형 Cloud 파일함]
  Widget _fileListView() {
    return _surface(
      padding: const EdgeInsets.all(16),
      child: ListView.separated(
        itemCount: _mockFiles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (c, i) {
          final f = _mockFiles[i];
          return _tile(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          style: _ts(15, w: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('${f.$2} · ${f.$3}', style: _ts(12, c: Colors.white54)),
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
                      style: _ts(12, w: FontWeight.w900, c: const Color(0xFF00F5D4))),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 서브 페이지: 주간 시간표 전체 뷰
  Widget _weeklyTimetableSubPage() {
    return KeyedSubtree(
      key: const ValueKey('tab_weekly_timetable'),
      child: _surface(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: Color(0xFF00F5D4), size: 20),
                const SizedBox(width: 8),
                Text('주간 전체 시간표', style: _ts(18, w: FontWeight.w900)),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => onTabSelected?.call('timetable'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00F5D4),
                    side: const BorderSide(color: Color(0xFF00F5D4)),
                  ),
                  child: const Text('대시보드로 복귀'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: teacherTimetableWidget ??
                        Center(
                          child: Text('시간표 로드 중...', style: _ts(14, c: Colors.white38)),
                        ),
                  ),
                  if (isHomeroom && homeroomTimetableWidget != null) ...[
                    const SizedBox(width: 14),
                    Expanded(child: homeroomTimetableWidget!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

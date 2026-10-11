import 'package:flutter/material.dart';

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

  final String currentOtp;
  final int remainingOtpSeconds;
  final VoidCallback? onOpenPopups;
  final VoidCallback? onResumeLesson;
  final VoidCallback? onStartQuickLesson;
  final VoidCallback? onCreateQuickMaterial;

  const BstTeacherMainLayout({
    super.key,
    this.schoolName = '보데스트 중학교',
    this.teacherName = '김보데',
    this.homeroomClass = '1학년 7반',
    this.hasPasskey = true,
    this.onRegisterPasskey,
    this.currentTab = 'timetable',
    this.onTabSelected,
    this.activeContent,
    this.teacherTimetableWidget,
    this.homeroomTimetableWidget,
    this.currentOtp = '------',
    this.remainingOtpSeconds = 60,
    this.onOpenPopups,
    this.onResumeLesson,
    this.onStartQuickLesson,
    this.onCreateQuickMaterial,
  });

  Widget _buildLeftNavButton({
    required String icon,
    required String label,
    required String tabId,
    bool isSettings = false,
  }) {
    final isSelected = currentTab == tabId;
    return InkWell(
      onTap: () => onTabSelected?.call(tabId),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00F5D4)
              : Colors.white.withOpacity(0.035),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00F5D4)
                : Colors.white.withOpacity(0.08),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF00F5D4).withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Text(
              icon,
              style: TextStyle(
                fontSize: 16,
                color: isSelected ? Colors.black : Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected ? Colors.black : const Color(0xFFE2E8F0),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.black,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 좌측 도구 독 (240px 고정)
            Container(
              width: 240,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0B101C).withOpacity(0.98),
                border: Border(
                  right: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단 브랜딩 (클릭 시 홈 시간표로 이동)
                  InkWell(
                    onTap: () => onTabSelected?.call('timetable'),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              'assets/icons/logo.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00F5D4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(child: Text('⚡')),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'BOARDEST Teacher',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  '$schoolName $homeroomClass',
                                  style: const TextStyle(
                                    color: Color(0xFF00F5D4),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const Text(
                                  'by jiwho',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 12),

                  // 빠른 수업 액션 2개 (바로 수업하기, 바로 자료 만들기)
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: onStartQuickLesson,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F5D4).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.4)),
                            ),
                            child: const Column(
                              children: [
                                Text('⚡', style: TextStyle(fontSize: 14)),
                                SizedBox(height: 2),
                                Text(
                                  '바로 수업하기',
                                  style: TextStyle(color: Color(0xFF00F5D4), fontSize: 10.5, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: InkWell(
                          onTap: onCreateQuickMaterial,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7F5AF0).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF7F5AF0).withOpacity(0.4)),
                            ),
                            child: const Column(
                              children: [
                                Text('✨', style: TextStyle(fontSize: 14)),
                                SizedBox(height: 2),
                                Text(
                                  '자료 만들기',
                                  style: TextStyle(color: Color(0xFF7F5AF0), fontSize: 10.5, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 12),

                  // 도구 목록 (원격제어 없음, 쪽지 발송 / 판서 관리 포함)
                  _buildLeftNavButton(
                    icon: '📅',
                    label: '시간표 대시보드',
                    tabId: 'timetable',
                  ),
                  const SizedBox(height: 5),
                  _buildLeftNavButton(
                    icon: '🚀',
                    label: '노트북 판서',
                    tabId: 'lesson',
                  ),
                  const SizedBox(height: 5),
                  _buildLeftNavButton(
                    icon: '📂',
                    label: 'Cloud 파일 열기',
                    tabId: 'cloud_open',
                  ),
                  const SizedBox(height: 5),
                  _buildLeftNavButton(
                    icon: '✨',
                    label: 'Cloud 교안 생성 (TBP)',
                    tabId: 'cloud_create',
                  ),
                  const SizedBox(height: 5),
                  _buildLeftNavButton(
                    icon: '💌',
                    label: '쪽지 발송',
                    tabId: 'memo',
                  ),
                  const SizedBox(height: 5),
                  _buildLeftNavButton(
                    icon: '🎨',
                    label: '판서 관리 (보관함)',
                    tabId: 'archive',
                  ),
                  const SizedBox(height: 5),
                  _buildLeftNavButton(
                    icon: '🍱',
                    label: '급식 & 급식지도',
                    tabId: 'meal',
                  ),
                  const SizedBox(height: 5),
                  _buildLeftNavButton(
                    icon: '☁️',
                    label: 'Cloud 보안 설정',
                    tabId: 'cloud_settings',
                  ),

                  const Spacer(),

                  _buildLeftNavButton(
                    icon: '⚙️',
                    label: '교사 환경 설정',
                    tabId: 'settings',
                    isSettings: true,
                  ),
                ],
              ),
            ),

            // 2. 메인 컨텐츠 영역 (선택된 탭에 따라 가운데 전환)
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: currentTab == 'timetable'
                    ? _buildTimetableHome()
                    : _buildSubTabContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 탭: 주간 시간표 홈 (패스키 배너 + 2열 시간표)
  Widget _buildTimetableHome() {
    return KeyedSubtree(
      key: const ValueKey('tab_timetable'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 상단 대시보드 퀵바 (이어서 하기, 소형 OTP, 팝업 열기, QR 패스키)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF00F5D4).withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF00F5D4).withOpacity(0.25),
                ),
              ),
              child: Row(
                children: [
                  // 교사 정보 및 안내
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '$teacherName 선생님 ($homeroomClass)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00F5D4).withOpacity(0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '온라인 연동 중',
                                style: TextStyle(
                                  color: Color(0xFF00F5D4),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          '교사 시간표 · 담임반 시간표 듀얼 뷰 | 칠판 연결 및 수업 관리',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 1. 소형 OTP 코드 뱃지 (남은 시간 초 표시)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🔑 OTP ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700)),
                        Text(
                          currentOtp,
                          style: const TextStyle(
                            color: Color(0xFF00F5D4),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F5D4).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${remainingOtpSeconds}초',
                            style: const TextStyle(
                              color: Color(0xFF00F5D4),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. 이어서 하기 버튼
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF00F5D4)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onResumeLesson,
                    icon: const Icon(Icons.play_circle_outline_rounded, size: 16, color: Color(0xFF00F5D4)),
                    label: const Text('이어서 하기', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),

                  // 3. 팝업 열기 버튼 (타이머/계산기 등)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onOpenPopups,
                    icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 16, color: Colors.white70),
                    label: const Text('팝업 열기', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),

                  // 4. QR 패스키 관리 버튼
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasPasskey ? const Color(0xFF00F5D4) : const Color(0xFF7F5AF0),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    onPressed: onRegisterPasskey,
                    icon: Icon(hasPasskey ? Icons.qr_code_scanner_rounded : Icons.qr_code_rounded, size: 16),
                    label: Text(
                      hasPasskey ? 'QR 패스키' : '패스키 등록',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 2열 시간표 영역
            Expanded(
              child: Row(
                children: [
                  // 1. 내 담당 수업 시간표
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '👩‍🏫 내 담당 수업 시간표 ($teacherName)',
                                style: const TextStyle(
                                  color: Color(0xFF00F5D4),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Text(
                                '주간 시간표',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12, height: 16),
                          Expanded(
                            child: teacherTimetableWidget ??
                                Center(
                                  child: Text(
                                    '시간표를 로드 중입니다...',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  // 2. 우리 반 (담임 학급) 시간표
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '🏫 우리 반 시간표 ($homeroomClass)',
                                style: const TextStyle(
                                  color: Color(0xFF8B5CF6),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Text(
                                '담임 학급 일과',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12, height: 16),
                          Expanded(
                            child: homeroomTimetableWidget ??
                                Center(
                                  child: Text(
                                    '담임 학급 시간표를 로드 중입니다...',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 12,
                                    ),
                                  ),
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
      ),
    );
  }

  /// 서브 탭 컨텐츠 영역 (수업 판서, Canva, 급식 지도, 쪽지, 보관함 등)
  Widget _buildSubTabContent() {
    return KeyedSubtree(
      key: ValueKey('tab_$currentTab'),
      child: Column(
        children: [
          // 상단 네비게이션 헤더 바 (홈으로 복귀 버튼 및 타이틀)
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0B101C),
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
              ),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => onTabSelected?.call('timetable'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 16),
                        SizedBox(width: 6),
                        Text(
                          '주간 시간표로 돌아가기',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  _getTabTitle(currentTab),
                  style: const TextStyle(
                    color: Color(0xFF00F5D4),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          // 본문 위젯
          Expanded(
            child: activeContent ?? const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _getTabTitle(String tab) {
    switch (tab) {
      case 'lesson':
        return '🚀 노트북 판서 워크스페이스';
      case 'cloud_open':
        return '📂 Cloud 에서 열기 (드라이브 & 판서 파일)';
      case 'cloud_create':
        return '✨ Cloud 에서 생성 (TBP, Canva, 파일 업로드 등)';
      case 'cloud_settings':
        return '☁️ Cloud 설정 (국제 규격 패스키 & 인증 기기)';
      case 'meal':
        return '🍱 실시간 급식지도 & 반별 급식 호출';
      case 'memo':
        return '💌 전자칠판 쪽지 발송 (긴급 공지)';
      case 'archive':
        return '🎨 판서 보관함 (.pen & Cloud 저장소)';
      case 'settings':
        return '⚙️ 교사 환경 설정';
      default:
        return '워크스페이스';
    }
  }
}

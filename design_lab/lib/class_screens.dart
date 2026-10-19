import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'mock.dart';
import 'skins.dart';

const _amber = Color(0xFFFFC857);

const _todayMeal = <(String, List<String>)>[
  ('무농약찰흑미밥', []),
  ('메이플피칸파이', ['난류', '우유', '대두']),
  ('참치두부김치찌개', ['대두', '돼지']),
  ('계란구이', ['난류']),
  ('불어묵야채볶음', ['난류', '대두', '밀']),
  ('수제오리떡갈비구이', ['난류', '밀', '돼지']),
  ('총각김치', []),
];
const _nextMeal = <(String, List<String>)>[
  ('무농약잡곡밥', []),
  ('두부된장찌개', ['대두', '밀', '조개']),
  ('돈육고추장불고기', ['대두', '밀', '돼지']),
  ('콘치즈구이', ['우유']),
  ('배추김치', []),
  ('양념쌈장', ['대두', '밀', '마늘']),
  ('바나나', []),
];
const _tools = <(IconData, String)>[
  (Icons.edit_rounded, '판서'),
  (Icons.timer_outlined, '타이머'),
  (Icons.casino_outlined, '추첨'),
  (Icons.calculate_outlined, '계산기'),
  (Icons.restaurant_rounded, '급식'),
  (Icons.cloud_outlined, 'Cloud'),
  (Icons.settings_rounded, '설정'),
];

/// 수업 시간에 중앙에 노출되는 기본 수업 도구 모음 (기존과 동일한 핵심 도구들로만 구성)
const _classroomTools = <(IconData, String, String, Color)>[
  (Icons.edit_rounded, '판서', '무한 캔버스 판서', Color(0xFF00F5D4)),
  (Icons.timer_outlined, '타이머', '수업 집중 타이머', Color(0xFFFFC857)),
  (Icons.casino_outlined, '추첨', '발표자 번호 추첨', Color(0xFFFF6B6B)),
  (Icons.calculate_outlined, '계산기', '공학용 수식 계산', Color(0xFF4D96FF)),
  (Icons.restaurant_rounded, '급식', '오늘 점심 식단표 확인', Color(0xFF00C896)),
  (Icons.cloud_outlined, 'Cloud', '수업 자료 클라우드', Color(0xFF7F5AF0)),
];

/// Cloud/USB 연결 시 노출되는 수업 자료 파일 목록
const _usbFiles = <(String, String, String, Color, IconData)>[
  ('수학I_03단원_삼각함수.pdf', 'PDF', '3.4 MB', Color(0xFFFF6B6B), Icons.picture_as_pdf_rounded),
  ('2026_모의고사_기출분석.pptx', 'PPT', '8.9 MB', Color(0xFFFF8906), Icons.slideshow_rounded),
  ('[전자교과서] 수학I 비상', 'TBP', '45 MB', Color(0xFF7F5AF0), Icons.auto_stories_rounded),
  ('함수의극한_인터랙티브', 'HTMLP', '3.1 MB', Color(0xFF00C4CC), Icons.co_present_rounded),
  ('10월19일_3교시_판서노트.pen', 'PEN', '5.1 MB', Color(0xFF00C896), Icons.draw_rounded),
  ('수학I_수행평가_학습지.hwpx', 'HWP', '1.8 MB', Color(0xFF4D96FF), Icons.description_rounded),
];

/// Boardest Class 신규 시안
/// [variant]: 'L' (K+I 믹스 1: 대형 교과서 + 하단 전폭 프로그레스 + M3 표지 블록)
///           'M' (K+I 믹스 2: 초대형 교과서 + 하단 눈금 게이지 + 콤팩트 스트립)
///           'K' (교과서 표지 블록형) / 'J' (슬림 텍스트형)
class ClassScreenJK extends StatefulWidget {
  final String variant; // 'L', 'M', 'K', 'J'
  final Skin skin;
  const ClassScreenJK({super.key, required this.variant, required this.skin});

  @override
  State<ClassScreenJK> createState() => _ClassScreenJKState();
}

class _ClassScreenJKState extends State<ClassScreenJK> {
  int cur = 3; // 4교시
  Skin get s => widget.skin;

  bool isClassTime = true;       // 수업시간 (true) vs 쉬는시간 (false)
  bool isCloudConnected = false;  // Cloud/USB 연결 (true) vs 미연결 (false)
  bool showClassMeal = false;     // 수업 중 급식 식단표 확인 모드
  int recessTab = 0;              // 쉬는시간+USB 모드에서 0: USB파일, 1: 급식

  String get _variantTitle {
    switch (widget.variant) {
      case 'L':
        return 'Class L안 (K+I 믹스 · 대형 교과서 + 하단 전폭 진행도)';
      case 'M':
        return 'Class M안 (K+I 믹스 · 초대형 교과서 + 하단 게이지 눈금)';
      case 'K':
        return 'Class K안 (교과서 표지 블록형)';
      case 'J':
      default:
        return 'Class J안 (슬림 텍스트형)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      DesignFrame(
        w: 1920,
        h: 1080,
        child: s.backdrop(
          Padding(
            // 왼쪽 벽에 완전히 딱 붙게 좌측 패딩 14px
            padding: const EdgeInsets.fromLTRB(14, 16, 20, 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 1. 좌측 물레방아 시간표
              SizedBox(width: 820, child: _leftWheelArea()),
              const SizedBox(width: 24),
              // 2. 우측 시계 + 급식 + 우측 세로 도구함 독
              Expanded(child: _rightContentArea()),
            ]),
          ),
        ),
      ),
      DemoBar(
        title: _variantTitle,
        value: cur,
        count: periods.length,
        onChanged: (v) => setState(() => cur = v),
      ),
    ]);
  }

  // ───────── 1. 좌측: 물레방아 시간표 ─────────
  Widget _leftWheelArea() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _brandBadge(),
      const SizedBox(height: 12),
      Expanded(child: LayoutBuilder(builder: (c, bc) => _buildWheel(bc))),
    ]);
  }

  Widget _brandBadge() {
    return s.surface(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: s.accent, borderRadius: BorderRadius.circular(8)),
          child: Text('bt', style: s.ts(16, w: FontWeight.w900, c: s.onAccent)),
        ),
        const SizedBox(width: 8),
        Text('BOARDEST Class', style: s.ts(17, w: FontWeight.w800)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: s.accent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: s.accent, width: 1),
          ),
          child: Text('PRO', style: s.ts(11, w: FontWeight.w900, c: s.accent)),
        ),
      ]),
    );
  }

  Widget _buildWheel(BoxConstraints bc) {
    final H = bc.maxHeight, W = bc.maxWidth;
    const n = 6;
    const g = 10.0;
    // L: 74px, M: 64px, K: 76px, J: 60px
    final hc = widget.variant == 'J'
        ? 60.0
        : widget.variant == 'M'
            ? 64.0
            : 74.0;
    final hcur = H - (n - 1) * (hc + g);

    double topOf(int i) {
      if (i < cur) return i * (hc + g);
      if (i == cur) return cur * (hc + g);
      return cur * (hc + g) + hcur + g + (i - cur - 1) * (hc + g);
    }

    final items = <Widget>[];
    for (int i = 0; i < n; i++) {
      final h = i == cur ? hcur : hc;
      final top = topOf(i);
      final isCurrent = i == cur;
      final isPast = i < cur;
      final dist = (i - cur).abs();
      // 현재 수업과 멀어질수록 과목 폭을 점진적으로 줄이는 원통형 물레방아 효과!
      // 현재 수업: W (820px), 1칸 멀어질 때마다 34px씩 축소되어 오른쪽이 원통 곡면처럼 수축
      final itemWidth = isCurrent ? W : (W - (dist * 34.0)).clamp(560.0, W);

      Widget cardContent;
      if (isCurrent) {
        cardContent = _currentPeriodCard(periods[i]);
      } else {
        switch (widget.variant) {
          case 'L':
            cardContent = _m3ThumbnailBlockCard(periods[i], isPast);
            break;
          case 'M':
            cardContent = _compactHybridCard(periods[i], isPast);
            break;
          case 'J':
            cardContent = _slimTextPeriodCard(periods[i], isPast);
            break;
          case 'K':
          default:
            cardContent = _blockThumbnailPeriodCard(periods[i], isPast);
            break;
        }
      }

      items.add(AnimatedPositioned(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        left: 0,
        top: top,
        width: itemWidth,
        height: h,
        child: GestureDetector(
          onTap: () => setState(() => cur = i),
          child: cardContent,
        ),
      ));
    }
    return Stack(children: items);
  }

  /// [현재 수업 중 과목 카드]: 교과서 사진 대폭 확대 + 진행도는 하단 전폭으로 배치 (버튼 완전 제거)
  Widget _currentPeriodCard(Period p) {
    final start = p.time;
    final parts = start.split(':');
    final endHour = int.parse(parts[0]);
    final endMin = int.parse(parts[1]) + 50;
    final endTime = '${(endHour + endMin ~/ 60).toString().padLeft(2, "0")}:${(endMin % 60).toString().padLeft(2, "0")}';
    final isM = widget.variant == 'M';
    final bookW = isM ? 340.0 : 320.0;

    return s.surface(
      strong: true,
      glow: true,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 상단: [교과서 사진 더 크게 (폭 320~340px)] + [우측: 교시/시간 + 초대형 과목명 + 교사명]
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 교과서 사진 크게 (실제 책 질감 및 입체감)
                SizedBox(
                  width: bookW,
                  child: BookCover(p, radius: 18, isHero: true),
                ),
                const SizedBox(width: 26),
                // 우측 핵심 수업 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 상단: [4교시 · 수업 진행 중] + 시간대
                      Row(children: [
                        s.pill('${p.no}교시 · 수업 진행 중', icon: Icons.play_circle_fill_rounded, selected: true),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                          child: Text('$start ~ $endTime', style: s.ts(17, w: FontWeight.w700, c: Colors.white70)),
                        ),
                      ]),
                      // 중앙: 과목명 아주 크게
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(p.subject, style: s.ts(134, w: FontWeight.w900, h: 1.0)),
                      ),
                      // 하단: 교사 및 교과서 정보
                      Row(children: [
                        Icon(Icons.person_pin_rounded, color: s.accent, size: 24),
                        const SizedBox(width: 8),
                        Text('${p.teacher} 선생님', style: s.ts(23, w: FontWeight.w800, c: Colors.white)),
                        const SizedBox(width: 12),
                        Text('·  ${p.book}', style: s.ts(19, w: FontWeight.w600, c: s.dim)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 2. 진행도는 아래로 넣어서 (하단 전폭 프로그레스 영역)
          _bottomProgressArea(showGaugeMarks: isM),
        ],
      ),
    );
  }

  /// 하단 전폭 진행도 바
  Widget _bottomProgressArea({bool showGaugeMarks = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Row(children: [
            Icon(Icons.timelapse_rounded, color: s.accent, size: 22),
            const SizedBox(width: 8),
            Text('수업 종료까지 18분 31초 남음', style: s.ts(19, w: FontWeight.w800, c: s.ink)),
            const Spacer(),
            Text('64%', style: s.ts(22, w: FontWeight.w900, c: s.accent)),
            const SizedBox(width: 8),
            Text('(32분 / 50분 경과)', style: s.ts(15, w: FontWeight.w600, c: s.dim)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: 0.64,
              minHeight: 14,
              color: s.accent,
              backgroundColor: Colors.white.withOpacity(0.12),
            ),
          ),
          if (showGaugeMarks) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0분 (시작)', style: s.ts(12, c: s.faint, w: FontWeight.w700)),
                Text('25분 (절반)', style: s.ts(12, c: s.faint, w: FontWeight.w700)),
                Text('50분 (종료)', style: s.ts(12, c: s.faint, w: FontWeight.w700)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// [L안: K+I 믹스] M3 서페이스 + 교과서 썸네일 블록형
  Widget _m3ThumbnailBlockCard(Period p, bool isPast) {
    final start = p.time;
    final parts = start.split(':');
    final endHour = int.parse(parts[0]);
    final endMin = int.parse(parts[1]) + 50;
    final endTime = '${(endHour + endMin ~/ 60).toString().padLeft(2, "0")}:${(endMin % 60).toString().padLeft(2, "0")}';

    return s.tile(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(children: [
        // 교과서 표지 미니 썸네일
        Opacity(
          opacity: isPast ? 0.45 : 0.95,
          child: SizedBox(
            width: 54,
            height: double.infinity,
            child: BookCover(p, radius: 8, showTitle: false),
          ),
        ),
        const SizedBox(width: 14),
        // 교시 번호 (M3 원형 뱃지)
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isPast ? Colors.white.withOpacity(0.06) : p.color.withOpacity(0.18),
            shape: BoxShape.circle,
            border: Border.all(color: isPast ? Colors.transparent : p.color.withOpacity(0.4)),
          ),
          child: Text('${p.no}', style: s.ts(22, w: FontWeight.w900, c: isPast ? s.faint : p.color)),
        ),
        const SizedBox(width: 14),
        // 과목명
        Expanded(
          child: Text(
            p.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: s.ts(29, w: FontWeight.w800, c: isPast ? s.faint : s.ink),
          ),
        ),
        // 교사명 및 시간대
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(p.teacher, style: s.ts(16, w: FontWeight.w700, c: isPast ? s.faint : s.ink)),
          Text('$start ~ $endTime', style: s.ts(14, c: isPast ? s.faint : s.dim, w: FontWeight.w600)),
        ]),
        const SizedBox(width: 12),
        Icon(
          isPast ? Icons.check_circle_rounded : Icons.schedule_rounded,
          color: isPast ? s.accent.withOpacity(0.6) : s.dim,
          size: 22,
        ),
      ]),
    );
  }

  /// [M안: K+I 믹스] 콤팩트 하이브리드 스트립 (높이 64px로 압축하여 현재 수업 카드 영역을 극대화)
  Widget _compactHybridCard(Period p, bool isPast) {
    final start = p.time;
    final parts = start.split(':');
    final endHour = int.parse(parts[0]);
    final endMin = int.parse(parts[1]) + 50;
    final endTime = '${(endHour + endMin ~/ 60).toString().padLeft(2, "0")}:${(endMin % 60).toString().padLeft(2, "0")}';

    return s.tile(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(children: [
        Opacity(
          opacity: isPast ? 0.4 : 0.9,
          child: SizedBox(
            width: 44,
            height: double.infinity,
            child: BookCover(p, radius: 6, showTitle: false),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 30,
          child: Text('${p.no}', style: s.ts(24, w: FontWeight.w900, c: isPast ? s.faint : p.color)),
        ),
        Expanded(
          child: Text(
            p.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: s.ts(25, w: FontWeight.w800, c: isPast ? s.faint : s.ink),
          ),
        ),
        Text(p.teacher, style: s.ts(15, c: isPast ? s.faint : s.dim)),
        const SizedBox(width: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(isPast ? 0.03 : 0.06),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$start ~ $endTime', style: s.ts(14, c: isPast ? s.faint : s.dim, w: FontWeight.w600)),
        ),
        const SizedBox(width: 10),
        Icon(
          isPast ? Icons.check_circle_rounded : Icons.schedule_rounded,
          color: isPast ? s.accent.withOpacity(0.5) : s.dim,
          size: 19,
        ),
      ]),
    );
  }

  /// [J안: 비수업 과목] 텍스트 중심(과목명, 교시, 시작-종료 시간)으로 극도로 얇고 깔끔하게 줄인 스트립
  Widget _slimTextPeriodCard(Period p, bool isPast) {
    final start = p.time;
    final parts = start.split(':');
    final endHour = int.parse(parts[0]);
    final endMin = int.parse(parts[1]) + 50;
    final endTime = '${(endHour + endMin ~/ 60).toString().padLeft(2, "0")}:${(endMin % 60).toString().padLeft(2, "0")}';

    return s.tile(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Row(children: [
        // 교시 번호
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isPast ? Colors.white12 : p.color.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Text('${p.no}', style: s.ts(18, w: FontWeight.w900, c: isPast ? s.faint : p.color)),
        ),
        const SizedBox(width: 14),
        // 과목명
        Expanded(
          child: Text(
            p.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: s.ts(24, w: FontWeight.w800, c: isPast ? s.faint : s.ink),
          ),
        ),
        // 교사명
        Text(p.teacher, style: s.ts(16, c: isPast ? s.faint : s.dim)),
        const SizedBox(width: 16),
        // 시작-종료 시간
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(isPast ? 0.03 : 0.06),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$start ~ $endTime', style: s.ts(15, c: isPast ? s.faint : s.dim, w: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        // 완료 또는 예정 아이콘
        Icon(
          isPast ? Icons.check_circle_rounded : Icons.schedule_rounded,
          color: isPast ? s.accent.withOpacity(0.5) : s.dim,
          size: 20,
        ),
      ]),
    );
  }

  /// [K안: 비수업 과목] 교과서 표지 썸네일 + 과목명 블록형
  Widget _blockThumbnailPeriodCard(Period p, bool isPast) {
    final start = p.time;
    final parts = start.split(':');
    final endHour = int.parse(parts[0]);
    final endMin = int.parse(parts[1]) + 50;
    final endTime = '${(endHour + endMin ~/ 60).toString().padLeft(2, "0")}:${(endMin % 60).toString().padLeft(2, "0")}';

    return s.tile(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(children: [
        // 교과서 표지 미니 썸네일
        Opacity(
          opacity: isPast ? 0.45 : 0.9,
          child: SizedBox(
            width: 52,
            height: double.infinity,
            child: BookCover(p, radius: 8, showTitle: false),
          ),
        ),
        const SizedBox(width: 14),
        // 교시 번호
        SizedBox(
          width: 36,
          child: Text('${p.no}', style: s.ts(28, w: FontWeight.w900, c: isPast ? s.faint : p.color)),
        ),
        // 과목명
        Expanded(
          child: Text(
            p.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: s.ts(30, w: FontWeight.w800, c: isPast ? s.faint : s.ink),
          ),
        ),
        // 교사명 및 시간
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(p.teacher, style: s.ts(15, w: FontWeight.w700, c: isPast ? s.faint : s.ink)),
          Text('$start ~ $endTime', style: s.ts(13, c: isPast ? s.faint : s.dim)),
        ]),
        const SizedBox(width: 12),
        Icon(
          isPast ? Icons.check_circle_rounded : Icons.schedule_rounded,
          color: isPast ? s.accent.withOpacity(0.6) : s.dim,
          size: 22,
        ),
      ]),
    );
  }

  // ───────── 2. 우측: 시계 + [수업도구 / USB 파일 / 급식] 4가지 시나리오 ─────────
  Widget _rightContentArea() {
    return Column(children: [
      // 상단: 4개 시나리오 퀵 전환 바 (실시간 데모 조작용)
      _scenarioQuickBar(),
      const SizedBox(height: 12),
      // 시계: 수업시간(초 없이 260px로 확장하여 초대형 HH:mm과 여백 확보) vs 쉬는시간(초 포함 360px 대형)
      AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        height: isClassTime ? 260 : 360,
        child: isClassTime ? _classTimeCompactClock() : _recessTimeLargeClock(),
      ),
      const SizedBox(height: 18),
      // 하단 메인 콘텐츠 (4가지 시나리오)
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildRightMainContent(),
        ),
      ),
    ]);
  }

  /// 4가지 시나리오 퀵 프리셋 바 (수업시간, 수업+USB, 쉬는시간, 쉬는시간+USB)
  Widget _scenarioQuickBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, color: s.accent, size: 18),
          const SizedBox(width: 8),
          Text('상황 시뮬레이션:', style: s.ts(13, w: FontWeight.w700, c: s.dim)),
          const SizedBox(width: 10),
          _modePill('1. 수업 중 (기본 도구함)', isClassTime && !isCloudConnected, () {
            setState(() {
              isClassTime = true;
              isCloudConnected = false;
              showClassMeal = false;
            });
          }, Icons.play_arrow_rounded),
          const SizedBox(width: 6),
          _modePill('2. 수업 + USB 연결', isClassTime && isCloudConnected, () {
            setState(() {
              isClassTime = true;
              isCloudConnected = true;
              showClassMeal = false;
            });
          }, Icons.usb_rounded),
          const SizedBox(width: 6),
          _modePill('3. 쉬는 시간 (급식)', !isClassTime && !isCloudConnected, () {
            setState(() {
              isClassTime = false;
              isCloudConnected = false;
              showClassMeal = false;
            });
          }, Icons.coffee_rounded),
          const SizedBox(width: 6),
          _modePill('4. 쉬는 시간 + USB', !isClassTime && isCloudConnected, () {
            setState(() {
              isClassTime = false;
              isCloudConnected = true;
              showClassMeal = false;
            });
          }, Icons.cloud_done_rounded),
        ],
      ),
    );
  }

  Widget _modePill(String title, bool active, VoidCallback onTap, IconData icon) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? s.accent : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: active ? s.onAccent : Colors.white70),
          const SizedBox(width: 5),
          Text(title, style: s.ts(12, w: active ? FontWeight.w900 : FontWeight.w600, c: active ? s.onAccent : Colors.white70)),
        ]),
      ),
    );
  }

  static const _wd = ['월', '화', '수', '목', '금', '토', '일'];

  /// [수업 시간용 시계]: 초 단위 제거(HH:mm) + 폰트 대폭 확대 + 수업종료 문구 완전 제거 + 여유로운 여백
  Widget _classTimeCompactClock() {
    final now = DateTime.now();
    final date = '${now.year}년 ${now.month}월 ${now.day}일 (${_wd[now.weekday - 1]})';

    return s.surface(
      padding: const EdgeInsets.fromLTRB(30, 16, 30, 16),
      child: Column(
        children: [
          Row(children: [
            Icon(Icons.calendar_today_rounded, color: s.accent, size: 20),
            const SizedBox(width: 10),
            Text(date, style: s.ts(20, w: FontWeight.w700, c: Colors.white)),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: s.accent.withOpacity(0.18), borderRadius: BorderRadius.circular(6)),
              child: Text('수업 진행 중', style: s.ts(13, w: FontWeight.w900, c: s.accent)),
            ),
            const Spacer(),
            s.pill('D-42 기말고사', icon: Icons.flag_rounded),
          ]),
          Expanded(
            child: Center(
              child: StreamBuilder<DateTime>(
                stream: Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
                initialData: DateTime.now(),
                builder: (c, snap) {
                  final t = snap.data!;
                  String two(int v) => v.toString().padLeft(2, '0');
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${two(t.hour)}:${two(t.minute)}',
                      style: s.ts(260, w: FontWeight.w900, h: 0.9, ls: -4, c: Colors.white),
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

  /// [쉬는 시간용 시계]: 초 단위(HH:mm:ss) 포함 대형 순백색 시계 + 쉬는 시간 종료 안내 표기!
  Widget _recessTimeLargeClock() {
    final now = DateTime.now();
    final date = '${now.year}년 ${now.month}월 ${now.day}일 (${_wd[now.weekday - 1]})';

    return s.surface(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
      child: Column(children: [
        Row(children: [
          Icon(Icons.calendar_today_rounded, color: s.accent, size: 22),
          const SizedBox(width: 10),
          Text(date, style: s.ts(23, w: FontWeight.w700, c: Colors.white)),
          const Spacer(),
          s.pill('D-42 기말고사', icon: Icons.flag_rounded),
        ]),
        Expanded(
          child: Center(
            child: StreamBuilder<DateTime>(
              stream: Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
              initialData: DateTime.now(),
              builder: (c, snap) {
                final t = snap.data!;
                String two(int v) => v.toString().padLeft(2, '0');
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
                    style: s.ts(360, w: FontWeight.w900, h: 0.95, ls: -4, c: Colors.white),
                  ),
                );
              },
            ),
          ),
        ),
        // 쉬는 시간에만 시계 아래 표기 (요청 반영)
        Row(children: [
          Icon(Icons.coffee_rounded, color: s.accent, size: 22),
          const SizedBox(width: 8),
          Text('쉬는 시간 종료까지 06분 45초 남음', style: s.ts(18, c: Colors.white, w: FontWeight.w800)),
          const Spacer(),
          Text('다음: 4교시 영어 (11:00 시작)', style: s.ts(17, c: s.accent, w: FontWeight.w800)),
        ]),
      ]),
    );
  }

  /// 4가지 시나리오에 따른 우측 메인 하단 영역 렌더링
  Widget _buildRightMainContent() {
    if (isClassTime) {
      if (showClassMeal) {
        // 수업 중 급식 식단표 확인 오버레이
        return _classMealOverlay(key: const ValueKey('class_meal_overlay'));
      }
      if (!isCloudConnected) {
        // [모드 1: 수업시간 기본] 급식 완전히 치우고, 중앙에 여백 넉넉한 대형 기본수업도구 그리드 노출!
        return _classToolsGrid(key: const ValueKey('class_tools_grid'));
      } else {
        // [모드 2: 수업시간 + USB 연결] 시계 아래에 파일 뜨고, 그 아래 한줄로 도구들 노출!
        return _classTimeCloudFilesAndToolbar(key: const ValueKey('class_files_tools'));
      }
    } else {
      if (!isCloudConnected) {
        // [모드 3: 쉬는시간 기본] 급식 식단표 + 우측 세로 도구함 독
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
        // [모드 4: 쉬는시간 + USB 연결] 급식 위치에 USB 파일함(급식 탭 전환 가능) + 우측 세로 독
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
      child: s.surface(
        padding: const EdgeInsets.fromLTRB(26, 18, 26, 18),
        child: Column(
          children: [
            Row(children: [
              Icon(Icons.restaurant_rounded, color: s.accent, size: 24),
              const SizedBox(width: 10),
              Text('급식 식단표 (수업 중 확인)', style: s.ts(23, w: FontWeight.w800)),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => showClassMeal = false),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: s.accent, borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.arrow_back_rounded, size: 18, color: s.onAccent),
                    const SizedBox(width: 6),
                    Text('수업 도구함으로 복귀', style: s.ts(15, w: FontWeight.w900, c: s.onAccent)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Expanded(
              child: Row(children: [
                Expanded(flex: 3, child: _mealColumn('오늘 점심 (금)', '742.0 kcal', _todayMeal, true)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _mealColumn('다음 급식 (월)', '777.0 kcal', _nextMeal, false)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  /// [모드 1] 수업 도구 대형 그리드 (여백 넉넉함 + 판서, 타이머, 추첨, 계산기, 급식, Cloud 기존 도구로만 구성)
  Widget _classToolsGrid({Key? key}) {
    return KeyedSubtree(
      key: key,
      child: s.surface(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.widgets_rounded, color: s.accent, size: 24),
              const SizedBox(width: 10),
              Text('수업 도구 모음', style: s.ts(23, w: FontWeight.w800)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                child: Text('터치 시 즉시 실행', style: s.ts(12, c: s.dim, w: FontWeight.w600)),
              ),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => showClassMeal = true),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00C896).withOpacity(0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.restaurant_rounded, size: 16, color: Color(0xFF00C896)),
                    const SizedBox(width: 6),
                    Text('급식 식단표 띄우기', style: s.ts(13, w: FontWeight.w800, c: const Color(0xFF00C896))),
                  ]),
                ),
              ),
            ]),
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
                itemCount: _classroomTools.length,
                itemBuilder: (context, i) {
                  final tool = _classroomTools[i];
                  return InkWell(
                    onTap: () {
                      if (tool.$2 == '급식') {
                        setState(() => showClassMeal = true);
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: s.tile(
                      radius: 16,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
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
                            Icon(Icons.arrow_outward_rounded, color: s.dim, size: 20),
                          ]),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tool.$2, style: s.ts(24, w: FontWeight.w800, c: s.ink)),
                              const SizedBox(height: 4),
                              Text(tool.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: s.ts(15, c: s.dim)),
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

  /// [모드 2] 수업 중 + USB 연결: 시계 아래 USB 파일 목록 + 그 아래 한줄 가로 도구함
  Widget _classTimeCloudFilesAndToolbar({Key? key}) {
    return Column(
      key: key,
      children: [
        // 상단: Cloud/USB 파일 목록
        Expanded(
          child: s.surface(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: const Color(0xFF00F5D4).withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.usb_rounded, color: Color(0xFF00F5D4), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text('USB 드라이브 수업 자료', style: s.ts(21, w: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF00F5D4).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text('D: 연결됨 · 6개 파일', style: s.ts(12, w: FontWeight.w800, c: const Color(0xFF00F5D4))),
                  ),
                  const Spacer(),
                  s.pill('파일 탐색기 열기', icon: Icons.folder_open_rounded),
                ]),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _usbFiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (c, i) {
                      final f = _usbFiles[i];
                      return s.tile(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        child: Row(children: [
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
                                Text(f.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: s.ts(18, w: FontWeight.w800)),
                                const SizedBox(height: 3),
                                Text('${f.$2} · ${f.$3}', style: s.ts(13, c: s.faint)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(color: s.accent.withOpacity(0.18), borderRadius: BorderRadius.circular(8)),
                            child: Text('열기', style: s.ts(13, w: FontWeight.w900, c: s.accent)),
                          ),
                        ]),
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

  /// 한 줄 가로 툴바 바 (급식 클릭 시 급식 식단표로 즉시 전환 지원)
  Widget _singleRowToolbar() {
    return s.surface(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final t in _tools)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () {
                    if (t.$2 == '급식') {
                      setState(() => showClassMeal = true);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: s.tile(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    radius: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.$1, color: t.$2 == '급식' ? const Color(0xFF00C896) : s.accent, size: 22),
                        const SizedBox(width: 8),
                        Text(t.$2, style: s.ts(16, w: FontWeight.w800, c: s.ink)),
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

  /// [모드 4] 쉬는 시간 + USB 연결: 급식 위치에 USB 파일 패널 노출 (급식 탭 전환 가능)
  Widget _recessCloudPanel() {
    return s.surface(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      child: Column(
        children: [
          // 상단: 탭 전환 [USB 수업 자료 (6개)] vs [급식 식단표]
          Row(children: [
            InkWell(
              onTap: () => setState(() => recessTab = 0),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: recessTab == 0 ? s.accent : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.usb_rounded, size: 18, color: recessTab == 0 ? s.onAccent : Colors.white70),
                  const SizedBox(width: 6),
                  Text('USB 수업 자료 (6개)', style: s.ts(16, w: FontWeight.w800, c: recessTab == 0 ? s.onAccent : Colors.white70)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => setState(() => recessTab = 1),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: recessTab == 1 ? s.accent : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.restaurant_rounded, size: 18, color: recessTab == 1 ? s.onAccent : Colors.white70),
                  const SizedBox(width: 6),
                  Text('급식 식단표', style: s.ts(16, w: FontWeight.w800, c: recessTab == 1 ? s.onAccent : Colors.white70)),
                ]),
              ),
            ),
            const Spacer(),
            Text('쉬는 시간 동안 다음 수업 준비 가능', style: s.ts(13, c: s.faint)),
          ]),
          const SizedBox(height: 14),
          Expanded(
            child: recessTab == 0
                ? ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _usbFiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (c, i) {
                      final f = _usbFiles[i];
                      return s.tile(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        child: Row(children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: f.$4.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                            child: Icon(f.$5, color: f.$4, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(f.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: s.ts(18, w: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text('${f.$2} · ${f.$3}', style: s.ts(13, c: s.faint)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(color: s.accent.withOpacity(0.18), borderRadius: BorderRadius.circular(8)),
                            child: Text('열기', style: s.ts(13, w: FontWeight.w900, c: s.accent)),
                          ),
                        ]),
                      );
                    },
                  )
                : Row(children: [
                    Expanded(flex: 3, child: _mealColumn('오늘 점심 (금)', '742.0 kcal', _todayMeal, true)),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: _mealColumn('다음 급식 (월)', '777.0 kcal', _nextMeal, false)),
                  ]),
          ),
        ],
      ),
    );
  }

  /// [모드 3용] 바닥 끝까지 시원하게 다 쓰는 급식 식단표
  Widget _mealTableFull() {
    return s.surface(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(children: [
        Row(children: [
          Icon(Icons.restaurant_rounded, color: s.accent, size: 24),
          const SizedBox(width: 10),
          Text('급식 식단표', style: s.ts(23, w: FontWeight.w800)),
          const SizedBox(width: 10),
          Text('(클릭 시 알레르기 & 투표)', style: s.ts(14, c: s.faint)),
          const Spacer(),
          s.pill('월간 식단표', icon: Icons.calendar_month_rounded),
          const SizedBox(width: 8),
          s.pill('Cloud 전환', icon: Icons.cloud_sync_rounded),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Row(children: [
            Expanded(flex: 3, child: _mealColumn('오늘 점심 (금)', '742.0 kcal', _todayMeal, true)),
            const SizedBox(width: 14),
            Expanded(flex: 2, child: _mealColumn('다음 급식 (월)', '777.0 kcal', _nextMeal, false)),
          ]),
        ),
      ]),
    );
  }

  Widget _mealColumn(String title, String kcal, List<(String, List<String>)> dishes, bool today) {
    return s.tile(
      selected: today,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(children: [
        Row(children: [
          Text(title, style: s.ts(21, w: FontWeight.w800, c: today ? s.accent : s.ink)),
          const Spacer(),
          Text(kcal, style: s.ts(15, c: s.faint, w: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Container(height: 1.2, color: Colors.white.withOpacity(0.15)),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final d in dishes)
              Row(children: [
                Expanded(
                  child: Text(
                    d.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: s.ts(25, w: FontWeight.w800),
                  ),
                ),
                for (final tag in d.$2)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _amber.withOpacity(0.18),
                      border: Border.all(color: _amber.withOpacity(0.7)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(tag, style: s.ts(12, w: FontWeight.w800, c: _amber)),
                  ),
              ]),
          ]),
        ),
      ]),
    );
  }

  /// 우측 끝에 세로로 독(Dock) 형태로 세운 도구함
  Widget _verticalToolbarDock() {
    return s.surface(
      radius: 20,
      strong: true,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (int i = 0; i < _tools.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: s.tile(
                selected: i == 0,
                radius: 14,
                padding: EdgeInsets.zero,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_tools[i].$1, size: 28, color: i == 0 ? s.accent : s.dim),
                  const SizedBox(height: 3),
                  Text(_tools[i].$2, style: s.ts(13, w: FontWeight.w800, c: i == 0 ? s.ink : s.dim)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

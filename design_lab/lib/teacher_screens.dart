import 'package:flutter/material.dart';
import 'mock.dart';
import 'skins.dart';

const _nav = <(IconData, String)>[
  (Icons.dashboard_rounded, '대시보드'),
  (Icons.folder_rounded, '내 수업 자료'),
  (Icons.auto_stories_rounded, '전자교과서 TBP'),
  (Icons.co_present_rounded, 'HTML Present'),
  (Icons.draw_rounded, '판서 노트'),
  (Icons.calendar_month_rounded, '주간 시간표 (전체)'),
  (Icons.settings_rounded, '설정'),
];

/// 교사용 오늘 수업 스케줄 목업
const _teacherTodaySchedule = [
  ('1교시', '09:00', '2-1반', '수학 II', Color(0xFF4D96FF), false),
  ('2교시', '10:00', '연구실', '수업 준비 (공강)', Colors.white24, false),
  ('3교시', '11:00', '2-3반', '수학 II', Color(0xFF4D96FF), false),
  ('4교시', '12:00', '3-2반', '수학 I (현재 진행)', Color(0xFF00F5D4), true),
  ('5교시', '13:40', '3-4반', '기하와 벡터', Color(0xFF7F5AF0), false),
  ('6교시', '14:40', '1-2반', '수학 동아리', Color(0xFFFF8906), false),
];

/// Boardest Teacher 신규 시안
/// [variant]: 'J' (상단 3위젯: OTP + Drive용량 + 오늘시간표 / 하단 광폭 Cloud 파일함)
///           'K' (좌측 교사 세로 시간표 타임라인 / 우측 상단 OTP+Drive / 우측 하단 Cloud 파일함)
class TeacherScreenJK extends StatelessWidget {
  final String variant; // 'J' or 'K'
  final Skin skin;
  const TeacherScreenJK({super.key, required this.variant, required this.skin});

  Skin get s => skin;
  bool get isJ => variant == 'J';

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      DesignFrame(
        w: 1280,
        h: 800,
        child: s.backdrop(
          Padding(
            padding: const EdgeInsets.all(22),
            child: isJ ? _layoutJ() : _layoutK(),
          ),
        ),
      ),
      DemoBar(
        title: 'Teacher ${variant}안 (${isJ ? "상단 3단 위젯 + 대형 파일함" : "좌측 시간표 타임라인 + 우측 분할"})',
      ),
    ]);
  }

  // ───────── J안 레이아웃: 사이드바 + [상단 3단: OTP / Drive용량 / 교사시간표] + [하단 파일함] ─────────
  Widget _layoutJ() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 220, child: _sidebar()),
      const SizedBox(width: 18),
      Expanded(
        child: Column(children: [
          // 헤더
          _topHeader('이수학 선생님 대시보드 👨‍🏫'),
          const SizedBox(height: 14),

          // 상단 3개 핵심 위젯: [1. 전자칠판 OTP] + [2. Google Drive 용량] + [3. 오늘 교사 시간표]
          SizedBox(
            height: 180,
            child: Row(children: [
              // 1. 전자칠판 OTP
              SizedBox(width: 280, child: _otpCardCompact()),
              const SizedBox(width: 14),
              // 2. 사용 중인 Drive 용량/상태 (연결된 교실 대신 배치)
              SizedBox(width: 220, child: _driveStorageCard()),
              const SizedBox(width: 14),
              // 3. 교사 오늘 시간표 (가로 콤팩트 뷰)
              Expanded(child: _teacherHorizontalScheduleCard()),
            ]),
          ),
          const SizedBox(height: 14),

          // 파일 카테고리 칩 & 검색
          _chipsAndSearchRow(),
          const SizedBox(height: 12),

          // 하단: 시원한 광폭 Cloud 파일 갤러리 (4열)
          Expanded(child: _fileGrid(4, 1.25, 8)),
        ]),
      ),
    ]);
  }

  // ───────── K안 레이아웃: 사이드바 + [좌측: 교사 세로 시간표] + [우측 상단: OTP & Drive] + [우측 하단: 파일함] ─────────
  Widget _layoutK() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 슬림 사이드바
      SizedBox(width: 200, child: _sidebar(isSlim: true)),
      const SizedBox(width: 16),

      // 좌측: 교사 세로 타임라인 시간표 (1~6교시 상세 리스트)
      SizedBox(width: 310, child: _teacherVerticalTimelineCard()),
      const SizedBox(width: 16),

      // 우측: 상단(OTP + Drive) + 하단(Cloud 파일함)
      Expanded(
        child: Column(children: [
          _topHeader('내 수업 자료 & 클라우드'),
          const SizedBox(height: 12),

          // 우측 상단: [OTP 링 카드] + [Drive 용량 카드] 2개 나란히
          SizedBox(
            height: 155,
            child: Row(children: [
              Expanded(flex: 5, child: _otpCardWideK()),
              const SizedBox(width: 14),
              Expanded(flex: 4, child: _driveStorageCardCompact()),
            ]),
          ),
          const SizedBox(height: 12),

          _chipsAndSearchRow(),
          const SizedBox(height: 10),

          // 우측 하단: Cloud 파일 갤러리 (3열)
          Expanded(child: _fileGrid(3, 1.18, 6)),
        ]),
      ),
    ]);
  }

  // ───────── 컴포넌트 모음 ─────────

  Widget _logo() => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: s.accent, borderRadius: BorderRadius.circular(10)),
        child: Icon(Icons.dashboard_customize_rounded, color: s.onAccent, size: 20),
      );

  Widget _sidebar({bool isSlim = false}) {
    return s.surface(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _logo(),
          const SizedBox(width: 10),
          Text(isSlim ? 'Boardest\nTeacher' : 'BOARDEST\nTeacher', style: s.ts(15, w: FontWeight.w900, h: 1.15)),
        ]),
        const SizedBox(height: 22),
        for (int i = 0; i < _nav.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: s.tile(
              selected: i == 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(_nav[i].$1, size: 18, color: i == 0 ? s.accent : s.dim),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _nav[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: s.ts(13.5, w: i == 0 ? FontWeight.w800 : FontWeight.w500, c: i == 0 ? s.ink : s.dim),
                  ),
                ),
              ]),
            ),
          ),
        const Spacer(),
        // 교사 계정 정보
        s.tile(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            CircleAvatar(radius: 16, backgroundColor: s.accent, child: Text('이', style: s.ts(14, w: FontWeight.w900, c: s.onAccent))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('이수학 선생님', style: s.ts(12.5, w: FontWeight.w800)),
                Text('Demo 중학교', style: s.ts(10.5, c: s.faint)),
              ]),
            ),
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle)),
          ]),
        ),
      ]),
    );
  }

  Widget _topHeader(String title) {
    return Row(children: [
      Text(title, style: s.ts(23, w: FontWeight.w900)),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Icon(Icons.sync_rounded, color: s.accent, size: 16),
          const SizedBox(width: 6),
          Text('Google Drive 실시간 연동됨', style: s.ts(12, c: s.accent, w: FontWeight.w700)),
        ]),
      ),
      const SizedBox(width: 10),
      s.button('새 자료 업로드', icon: Icons.upload_rounded),
    ]);
  }

  // 1. [전자칠판 OTP 링 카드 (J안용)]
  Widget _otpCardCompact() {
    return s.surface(
      glow: true,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Icon(Icons.lock_rounded, size: 16, color: s.accent),
          const SizedBox(width: 6),
          Text('전자칠판 OTP', style: s.ts(14, w: FontWeight.w800)),
          const Spacer(),
          Text('41초', style: s.ts(12, c: s.accent, w: FontWeight.w800)),
        ]),
        Row(children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: 0.68,
                  strokeWidth: 6,
                  color: s.accent,
                  backgroundColor: Colors.white.withOpacity(0.1),
                ),
              ),
              Icon(Icons.phonelink_ring_rounded, color: s.accent, size: 30),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('482 915', style: s.ts(25, w: FontWeight.w900, ls: 1.5, c: Colors.white)),
              const SizedBox(height: 4),
              Text('칠판에 입력 시 1초 만에\n수업 자료가 연동됩니다', style: s.ts(11, c: s.dim, h: 1.25)),
            ]),
          ),
        ]),
        SizedBox(
          width: double.infinity,
          height: 32,
          child: Center(child: s.pill('스마트폰 QR 로그인', icon: Icons.qr_code_2_rounded, selected: true)),
        ),
      ]),
    );
  }

  // 2. [사용 중인 Drive 용량/상태 카드 (J안)]
  Widget _driveStorageCard() {
    return s.surface(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Icon(Icons.cloud_done_rounded, size: 16, color: const Color(0xFF4D96FF)),
          const SizedBox(width: 6),
          Text('Drive 용량', style: s.ts(14, w: FontWeight.w800)),
          const Spacer(),
          Text('42%', style: s.ts(13, w: FontWeight.w900, c: s.accent)),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('6.3', style: s.ts(28, w: FontWeight.w900, c: Colors.white)),
            Text(' GB', style: s.ts(14, w: FontWeight.w700, c: s.dim)),
            Text(' / 15 GB', style: s.ts(12, c: s.faint)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 0.42,
              minHeight: 8,
              color: s.accent,
              backgroundColor: Colors.white.withOpacity(0.1),
            ),
          ),
        ]),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            Icon(Icons.check_circle_rounded, color: const Color(0xFF34D399), size: 13),
            const SizedBox(width: 5),
            Text('여유 공간 8.7 GB', style: s.ts(11.5, c: s.dim, w: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }

  // 3. [교사 오늘 시간표 카드 (J안 가로 콤팩트 뷰)]
  Widget _teacherHorizontalScheduleCard() {
    return s.surface(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.calendar_today_rounded, size: 16, color: s.accent),
          const SizedBox(width: 6),
          Text('오늘 내 수업 시간표 (10.19 일)', style: s.ts(14, w: FontWeight.w800)),
          const Spacer(),
          Text('총 4개 수업 (공강 2)', style: s.ts(12, c: s.faint)),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: Row(children: [
            for (final sc in _teacherTodaySchedule)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: sc.$6 ? s.accent.withOpacity(0.2) : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sc.$6 ? s.accent : Colors.white10, width: sc.$6 ? 1.5 : 1),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(sc.$1, style: s.ts(12, w: FontWeight.w900, c: sc.$6 ? s.accent : s.dim)),
                      Text(sc.$2, style: s.ts(10.5, c: s.faint)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(sc.$3, style: s.ts(13, w: FontWeight.w800, c: sc.$6 ? Colors.white : s.ink)),
                      Text(
                        sc.$4,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: s.ts(11, c: sc.$6 ? s.accent : s.faint, w: sc.$6 ? FontWeight.w800 : FontWeight.w500),
                      ),
                    ]),
                    if (sc.$6)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: s.accent, borderRadius: BorderRadius.circular(4)),
                        child: Text('진행 중', style: s.ts(9.5, w: FontWeight.w900, c: s.onAccent)),
                      )
                    else
                      const SizedBox(height: 14),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  // ───────── K안용 전용 컴포넌트 ─────────

  /// [K안 좌측: 교사 세로 타임라인 시간표 카드]
  Widget _teacherVerticalTimelineCard() {
    return s.surface(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.schedule_rounded, size: 18, color: s.accent),
          const SizedBox(width: 8),
          Text('교사 오늘 시간표', style: s.ts(16, w: FontWeight.w900)),
          const Spacer(),
          s.pill('10.19 (일)', selected: true),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: _teacherTodaySchedule.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (c, i) {
              final sc = _teacherTodaySchedule[i];
              return s.tile(
                selected: sc.$6,
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  // 시간 및 교시
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sc.$1, style: s.ts(15, w: FontWeight.w900, c: sc.$6 ? s.accent : s.dim)),
                    Text(sc.$2, style: s.ts(11.5, c: s.faint)),
                  ]),
                  const SizedBox(width: 14),
                  // 교실 및 과목명
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(sc.$3, style: s.ts(14, w: FontWeight.w800)),
                      Text(sc.$4, maxLines: 1, overflow: TextOverflow.ellipsis, style: s.ts(12, c: sc.$6 ? s.accent : s.dim)),
                    ]),
                  ),
                  if (sc.$6)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: s.accent, borderRadius: BorderRadius.circular(6)),
                      child: Text('수업 중', style: s.ts(10.5, w: FontWeight.w900, c: s.onAccent)),
                    ),
                ]),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // 하단: 주간 전체 시간표 보기 버튼
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.calendar_month_rounded, size: 15, color: s.dim),
            const SizedBox(width: 6),
            Text('주간 전체 시간표 열기', style: s.ts(13, w: FontWeight.w700, c: s.dim)),
          ]),
        ),
      ]),
    );
  }

  /// [K안 우측 상단 OTP 와이드 카드]
  Widget _otpCardWideK() {
    return s.surface(
      glow: true,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: 0.68,
                strokeWidth: 6,
                color: s.accent,
                backgroundColor: Colors.white.withOpacity(0.1),
              ),
            ),
            Icon(Icons.key_rounded, color: s.accent, size: 28),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              Text('전자칠판 OTP: ', style: s.ts(13, c: s.dim)),
              Text('482 915', style: s.ts(20, w: FontWeight.w900, c: Colors.white)),
            ]),
            const SizedBox(height: 4),
            Text('유효시간 41초 남음 · 칠판에 입력 시 잠금 해제', style: s.ts(11, c: s.faint)),
            const SizedBox(height: 8),
            s.pill('스마트폰 QR로 칠판 로그인', icon: Icons.qr_code_2_rounded, selected: true),
          ]),
        ),
      ]),
    );
  }

  /// [K안 우측 상단 Drive 용량 카드]
  Widget _driveStorageCardCompact() {
    return s.surface(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Icon(Icons.cloud_done_rounded, size: 16, color: s.accent),
          const SizedBox(width: 6),
          Text('Google Drive 용량', style: s.ts(13.5, w: FontWeight.w800)),
          const Spacer(),
          Text('42%', style: s.ts(13, w: FontWeight.w900, c: s.accent)),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('6.3 GB 사용 / 15 GB', style: s.ts(15, w: FontWeight.w900, c: Colors.white)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0.42,
              minHeight: 6,
              color: s.accent,
              backgroundColor: Colors.white.withOpacity(0.1),
            ),
          ),
        ]),
        Text('여유 공간 8.7 GB 남음 (동기화 완료)', style: s.ts(11, c: s.faint)),
      ]),
    );
  }

  // ───────── 파일 목록 그리드 공통 ─────────

  Widget _chipsAndSearchRow() {
    return Row(children: [
      for (final t in ['전체', 'PDF', 'PPT', 'HWP', 'TBP 교과서', 'HTMLP', '판서'])
        Padding(padding: const EdgeInsets.only(right: 6), child: s.pill(t, selected: t == '전체')),
      const Spacer(),
      SizedBox(
        width: 220,
        height: 36,
        child: s.tile(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          child: Row(children: [
            Icon(Icons.search_rounded, size: 16, color: s.faint),
            const SizedBox(width: 6),
            Text('자료 검색...', style: s.ts(12, c: s.faint)),
          ]),
        ),
      ),
    ]);
  }

  Widget _fileGrid(int cols, double ratio, int count) {
    return GridView.count(
      crossAxisCount: cols,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: ratio,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        for (final f in files.take(count))
          s.tile(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(s.r > 20 ? 14 : 6),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [f.color.withOpacity(0.55), f.color.withOpacity(0.12)],
                    ),
                  ),
                  child: Stack(children: [
                    Center(child: Icon(f.icon, size: 40, color: Colors.white.withOpacity(0.9))),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(4)),
                        child: Text(f.kind, style: s.ts(9.5, w: FontWeight.w800)),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: s.ts(12.5, w: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(f.size, style: s.ts(10.5, c: s.faint)),
            ]),
          ),
      ],
    );
  }
}

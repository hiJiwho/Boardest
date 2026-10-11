import 'package:flutter/material.dart';
import 'ui.dart';
import 'library.dart';

/// Boardest Teacher — 교사용 앱 (1280×720 기준)
class TeacherApp extends StatefulWidget {
  const TeacherApp({super.key});
  @override
  State<TeacherApp> createState() => _TeacherAppState();
}

class _TeacherAppState extends State<TeacherApp> {
  int nav = 0;
  bool locked = true; // 칠판 잠금 여부
  int remote = 0;
  static const navs = [
    (Icons.today_rounded, '오늘'),
    (Icons.folder_special_rounded, '자료함'),
    (Icons.cast_connected_rounded, '원격 제어'),
    (Icons.restaurant_rounded, '급식'),
    (Icons.settings_rounded, '설정'),
  ];

  @override
  Widget build(BuildContext context) {
    return Aurora(
      a: T.purple,
      b: T.violet,
      child: Row(children: [
        _rail(),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(a), child: c)),
            child: KeyedSubtree(
              key: ValueKey(nav),
              child: switch (nav) {
                0 => _today(),
                1 => LibraryView(onClose: () => setState(() => nav = 0), compact: true),
                2 => _remote(),
                3 => _simple('급식 정보', Icons.restaurant_rounded, T.orange),
                _ => _simple('설정', Icons.settings_rounded, T.sub),
              },
            ),
          ),
        ),
      ]),
    );
  }

  Widget _rail() => Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: const BoxDecoration(color: Color(0xCC0A1022), border: Border(right: BorderSide(color: T.line))),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [T.purple, T.violet]), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.school_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 26),
          for (var i = 0; i < navs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Pressable(
                onTap: () => setState(() => nav = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 72,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: nav == i ? T.purple.withValues(alpha: 0.3) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: nav == i ? T.violet : Colors.transparent),
                  ),
                  child: Column(children: [
                    Icon(navs[i].$1, color: nav == i ? Colors.white : T.sub, size: 24),
                    const SizedBox(height: 4),
                    Text(navs[i].$2, style: T.h(11, c: nav == i ? Colors.white : T.sub, w: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          const Spacer(),
          const CircleAvatar(backgroundColor: T.teal, child: Text('김', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
        ]),
      );

  Widget _today() => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(children: [
          Row(children: [
            LiveClock(builder: (n) => Text('안녕하세요, 김지우 선생님', style: T.h(26))),
            const Spacer(),
            const PillTag('Cloud 연결됨', icon: Icons.cloud_done_rounded),
          ]),
          const SizedBox(height: 16),
          Expanded(
            flex: 5,
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Reveal(
                  child: Glass(
                    padding: const EdgeInsets.all(26),
                    gradient: LinearGradient(colors: [T.teal.withValues(alpha: 0.28), const Color(0xFF11182F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.lock_open_rounded, color: T.mint),
                        const SizedBox(width: 8),
                        Text('칠판 로그인 OTP', style: T.h(18)),
                        const Spacer(),
                        const PillTag('60초마다 갱신', icon: Icons.autorenew_rounded),
                      ]),
                      const SizedBox(height: 18),
                      const FittedBox(fit: BoxFit.scaleDown, child: OtpBox(digit: 96)),
                      const SizedBox(height: 14),
                      Text('칠판 Cloud 로그인 화면에 이 번호를 입력하세요. QR / 패스키 로그인은 칠판에서 선택합니다.', style: T.h(13, c: T.sub, w: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Reveal(
                  delayMs: 100,
                  child: Glass(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('오늘 수업', style: T.h(18)),
                        const Spacer(),
                        Text('${subjects[nowPeriod].name} 진행 중', style: T.h(12, c: T.mint)),
                      ]),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView(children: [
                          for (var i = 0; i < 5; i++)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: i == nowPeriod ? subjects[i].color.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: i == nowPeriod ? subjects[i].color : T.line),
                              ),
                              child: Row(children: [
                                CircleAvatar(radius: 16, backgroundColor: subjects[i].color, child: Text('${i + 1}', style: T.h(13))),
                                const SizedBox(width: 12),
                                Expanded(child: Text('2-${i + 2}  ${subjects[i].name}', style: T.h(15))),
                                Text(periodTimes[i], style: T.h(12, c: T.sub, w: FontWeight.w600)),
                              ]),
                            ),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(
            flex: 3,
            child: Reveal(
              delayMs: 200,
              child: Row(children: [
                for (final q in const [
                  (Icons.menu_book_rounded, '수학 2-1 열기', '지금 수업 교과서', T.orange),
                  (Icons.cloud_rounded, '1단원 PPT', 'Cloud · 오늘 09:12', T.teal),
                  (Icons.palette_rounded, '도형 수업 디자인', 'Canva', T.purple),
                  (Icons.draw_rounded, '판서 저장본', '어제 3개', T.violet),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Pressable(
                        onTap: () => setState(() => nav = 1),
                        child: Glass(
                          border: q.$4.withValues(alpha: 0.5),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(q.$1, color: q.$4, size: 30),
                            const SizedBox(height: 10),
                            Text(q.$2, style: T.h(16)),
                            Text(q.$3, style: T.h(12, c: T.sub, w: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      );

  Widget _remote() => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('원격 제어', style: T.h(28)),
          const SizedBox(height: 4),
          Text('연결된 전자칠판을 선택하고 수업 화면을 제어하세요', style: T.h(13, c: T.sub, w: FontWeight.w600)),
          const SizedBox(height: 18),
          Expanded(
            child: Row(children: [
              SizedBox(
                width: 330,
                child: ListView(children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Pressable(
                        onTap: () => setState(() => remote = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: T.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: remote == i ? T.mint : T.line, width: remote == i ? 2 : 1),
                          ),
                          child: Row(children: [
                            Icon(Icons.tv_rounded, color: remote == i ? T.mint : T.sub, size: 32),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(['2학년 4반 칠판', '2학년 6반 칠판', '과학실'][i], style: T.h(16)),
                                Text(i == 1 ? '오프라인' : '연결됨 · 지연 12ms', style: T.h(12, c: i == 1 ? T.red : T.teal, w: FontWeight.w600)),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Glass(
                  child: Column(children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(colors: [subjects[1].color.withValues(alpha: 0.5), T.bg2]),
                          border: Border.all(color: T.line),
                        ),
                        alignment: Alignment.center,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.cast_connected_rounded, size: 54, color: Colors.white70),
                          const SizedBox(height: 10),
                          Text('칠판 화면 미러링', style: T.h(18)),
                          Text('수학 2-1 · 48쪽', style: T.h(13, c: T.sub, w: FontWeight.w600)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      GradButton('이전', icon: Icons.chevron_left_rounded, colors: const [T.card2, T.card2], dark: false, onTap: () {}),
                      const SizedBox(width: 10),
                      GradButton(locked ? '칠판 잠금 해제' : '칠판 잠금', icon: locked ? Icons.lock_open_rounded : Icons.lock_rounded, onTap: () => setState(() => locked = !locked)),
                      const SizedBox(width: 10),
                      GradButton('다음', icon: Icons.chevron_right_rounded, colors: const [T.card2, T.card2], dark: false, onTap: () {}),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      );

  Widget _simple(String t, IconData i, Color c) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 64, color: c), const SizedBox(height: 12), Text(t, style: T.h(26)), Text('프로토타입 범위 밖 화면', style: T.h(13, c: T.sub))]),
      );
}

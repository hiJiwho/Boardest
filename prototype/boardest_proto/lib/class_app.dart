import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'ui.dart';
import 'library.dart';

/// Boardest Class — 전자칠판 대시보드 (1280×720 기준)
class ClassApp extends StatefulWidget {
  const ClassApp({super.key});
  @override
  State<ClassApp> createState() => _ClassAppState();
}

class _ClassAppState extends State<ClassApp> {
  bool library = false;
  bool cloud = false;
  bool special = false; // 교과전용관 모드

  void _openLogin() async {
    final r = await showDialog<bool>(context: context, builder: (_) => const CloudLoginSheet());
    if (r == true && mounted) setState(() => cloud = true);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Aurora(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(children: [
            _topBar(),
            const SizedBox(height: 12),
            Expanded(child: special ? _specialHome() : _home()),
          ]),
        ),
      ),
      // 라이브러리 전체화면 (슬라이드 인)
      AnimatedSlide(
        offset: library ? Offset.zero : const Offset(0, 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        child: library ? LibraryView(onClose: () => setState(() => library = false)) : const SizedBox.expand(),
      ),
    ]);
  }

  Widget _topBar() => Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [T.teal, T.purple]), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.dashboard_customize_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Text('Boardest Class', style: T.h(18)),
        const SizedBox(width: 14),
        Text(special ? '과학실 · 김지우 선생님' : '보데스트중학교 · 2학년 4반', style: T.h(14, c: T.sub, w: FontWeight.w600)),
        const Spacer(),
        Pressable(
          onTap: () => setState(() => special = !special),
          child: PillTag(special ? '교과 전용관 모드' : '일반 학급 모드', color: special ? T.violet : T.teal, icon: Icons.swap_horiz_rounded),
        ),
        const SizedBox(width: 10),
        Pressable(
          onTap: cloud ? () => setState(() => cloud = false) : _openLogin,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: cloud
                ? const PillTag('Cloud 연결됨 · RAM', key: ValueKey(1), color: T.mint, icon: Icons.cloud_done_rounded)
                : const PillTag('Cloud 로그인', key: ValueKey(0), color: T.orange, icon: Icons.cloud_off_rounded),
          ),
        ),
      ]);

  /// 1 : 2 : 3  /  가로 3 : 1
  Widget _home() => Column(children: [
        Expanded(
          flex: 3,
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Column(children: [
                Expanded(flex: 1, child: Reveal(child: _timetableStrip())),
                const SizedBox(height: 12),
                Expanded(flex: 2, child: Reveal(delayMs: 100, child: _clockCard())),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 1, child: Reveal(delayMs: 200, child: _toolPanel())),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: 3,
          child: Row(children: [
            Expanded(child: Reveal(delayMs: 300, child: _nowCard())),
            const SizedBox(width: 12),
            Expanded(child: Reveal(delayMs: 400, child: _mealCard())),
          ]),
        ),
      ]);

  Widget _timetableStrip() => Glass(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(builder: (_, c) {
          final h = c.maxHeight;
          return Row(mainAxisAlignment: MainAxisAlignment.start, children: [
            for (var i = 0; i < 7; i++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: BookCard(s: subjects[i], period: i, time: periodTimes[i], active: i == nowPeriod, done: i < nowPeriod, h: h),
              ),
          ]);
        }),
      );

  Widget _clockCard() => Glass(
        gradient: LinearGradient(colors: [T.purple.withValues(alpha: 0.25), const Color(0xFF11182F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        child: LiveClock(builder: (n) {
          final h12 = n.hour % 12 == 0 ? 12 : n.hour % 12;
          return Row(children: [
            Expanded(
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${n.month}월 ${n.day}일 ${weekdays[n.weekday - 1]}요일 · ${n.hour < 12 ? '오전' : '오후'}', style: T.h(20, c: T.sub, w: FontWeight.w700)),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Text('$h12:${two(n.minute)}', style: T.h(150, ls: -4)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24, left: 8),
                      child: Text(two(n.second), style: T.h(48, c: T.mint)),
                    ),
                  ]),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Ring(
                value: (n.minute % 55) / 55,
                size: 110,
                color: T.teal,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${55 - n.minute % 55}', style: T.h(30)),
                  Text('분 남음', style: T.h(11, c: T.sub, w: FontWeight.w600)),
                ]),
              ),
            ]),
          ]);
        }),
      );

  Widget _toolPanel() {
    final tools = <(IconData, String, Color, VoidCallback)>[
      (Icons.draw_rounded, '판서', T.purple, () => _msg('판서 도구 실행')),
      (Icons.timer_rounded, '타이머', T.orange, () => showDialog(context: context, builder: (_) => const TimerDialog())),
      (Icons.casino_rounded, '발표자', T.red, () => showDialog(context: context, builder: (_) => const PickerDialog())),
      (Icons.calculate_rounded, '계산기', T.blue, () => _msg('계산기 실행')),
      (Icons.folder_special_rounded, '자료함', T.teal, () => setState(() => library = true)),
      (Icons.cloud_rounded, 'Cloud', T.mint, cloud ? () => setState(() => library = true) : _openLogin),
      (Icons.wb_sunny_rounded, '날씨', const Color(0xFFFBBF24), () => _msg('맑음 21°C')),
      (Icons.calendar_month_rounded, '학사달력', T.violet, () => _msg('10월 학사일정')),
    ];
    return Glass(
      padding: const EdgeInsets.all(10),
      child: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.05,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final t in tools)
            Pressable(
              onTap: t.$4,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(colors: [t.$3.withValues(alpha: 0.35), t.$3.withValues(alpha: 0.1)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  border: Border.all(color: t.$3.withValues(alpha: 0.5)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(t.$1, color: Colors.white, size: 30),
                  const SizedBox(height: 6),
                  Text(t.$2, style: T.h(13)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _nowCard() {
    final s = subjects[nowPeriod];
    return Glass(
      gradient: LinearGradient(colors: [s.color.withValues(alpha: 0.4), const Color(0xFF11182F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      child: Row(children: [
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: s.color.withValues(alpha: 0.6), blurRadius: 30)]),
          child: Icon(s.icon, color: Colors.white, size: 56),
        ),
        const SizedBox(width: 22),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const PillTag('지금 · 3교시', icon: Icons.play_circle_fill_rounded),
            const SizedBox(height: 10),
            Text(s.name, style: T.h(56)),
            const SizedBox(height: 6),
            Text('10:30 – 11:15  ·  김OO 선생님', style: T.h(15, c: T.sub, w: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(children: [
              Text('다음', style: T.h(13, c: T.sub)),
              const SizedBox(width: 8),
              PillTag('4교시 ${subjects[nowPeriod + 1].name}', color: subjects[nowPeriod + 1].color),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _mealCard() => Glass(
        gradient: LinearGradient(colors: [T.orange.withValues(alpha: 0.22), const Color(0xFF11182F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.restaurant_rounded, color: T.orange),
            const SizedBox(width: 8),
            Text('오늘 급식', style: T.h(20)),
            const Spacer(),
            const PillTag('급식실 1 · 4교시 후', color: T.orange),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              for (var i = 0; i < mealMenu.length; i++)
                Reveal(
                  delayMs: 500 + i * 60,
                  from: const Offset(0, 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14), border: Border.all(color: T.line)),
                    child: Text(mealMenu[i], style: T.h(18, w: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
          Text('열량 742kcal · 알레르기 5, 6, 13', style: T.h(12, c: T.sub, w: FontWeight.w600)),
        ]),
      );

  /// 교과 전용관: 맨 위 교과명, 교과서 대신 '반'을 시간표에 크게
  Widget _specialHome() {
    const classes = ['2-1', '2-3', '2-4', '2-6', '2-7', '1-2', '1-5'];
    return Column(children: [
      Reveal(
        child: Glass(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          gradient: LinearGradient(colors: [T.violet.withValues(alpha: 0.4), const Color(0xFF11182F)]),
          child: Row(children: [
            const Icon(Icons.science_rounded, color: Colors.white, size: 36),
            const SizedBox(width: 14),
            Text('과학', style: T.h(44)),
            const SizedBox(width: 14),
            const PillTag('교과 전용관', color: T.violet),
            const Spacer(),
            LiveClock(builder: (n) => Text('${n.hour}:${two(n.minute)}', style: T.h(52, c: T.mint))),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        flex: 2,
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Reveal(
              delayMs: 100,
              child: Glass(
                child: LayoutBuilder(builder: (_, c) => Row(children: [
                  for (var i = 0; i < 7; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Container(
                        width: (c.maxWidth - 60) / 7,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: i == nowPeriod ? [T.violet, T.purple] : [T.card2, T.card],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: i == nowPeriod ? Colors.white : T.line, width: i == nowPeriod ? 2.5 : 1),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('${i + 1}교시', style: T.h(12, c: T.sub)),
                          const SizedBox(height: 6),
                          Text(classes[i], style: T.h(30)),
                          Text(periodTimes[i], style: T.h(11, c: T.sub, w: FontWeight.w600)),
                        ]),
                      ),
                    ),
                ])),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 1, child: Reveal(delayMs: 200, child: _toolPanel())),
        ]),
      ),
      const SizedBox(height: 12),
      Expanded(
        flex: 2,
        child: Row(children: [
          Expanded(
            child: Reveal(
              delayMs: 300,
              child: Glass(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const PillTag('지금 수업 반', icon: Icons.groups_rounded),
                  const SizedBox(height: 8),
                  Text('2학년 4반', style: T.h(72)),
                  Text('다음 4교시 → 2학년 6반', style: T.h(15, c: T.sub, w: FontWeight.w600)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Reveal(delayMs: 400, child: _mealCard())),
        ]),
      ),
    ]);
  }

  void _msg(String m) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m), backgroundColor: T.card2, behavior: SnackBarBehavior.floating, width: 280));
}

/// 타이머 (동작함)
class TimerDialog extends StatefulWidget {
  const TimerDialog({super.key});
  @override
  State<TimerDialog> createState() => _TimerDialogState();
}

class _TimerDialogState extends State<TimerDialog> {
  int total = 300, left = 300;
  Timer? t;
  void _toggle() {
    if (t != null) {
      t!.cancel();
      setState(() => t = null);
      return;
    }
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (left <= 0) {
        t?.cancel();
        setState(() => t = null);
      } else {
        setState(() => left--);
      }
    });
    setState(() {});
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Glass(
          radius: 30,
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Ring(
              value: left / total,
              size: 260,
              color: left < 30 ? T.red : T.orange,
              child: Text('${two(left ~/ 60)}:${two(left % 60)}', style: T.h(64)),
            ),
            const SizedBox(height: 18),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (final m in [1, 3, 5, 10])
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Pressable(
                    onTap: () => setState(() {
                      total = left = m * 60;
                    }),
                    child: PillTag('$m분', color: T.orange),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            GradButton(t == null ? '시작' : '일시정지', icon: t == null ? Icons.play_arrow_rounded : Icons.pause_rounded, colors: const [T.orange, Color(0xFFFFD166)], onTap: _toggle),
          ]),
        ),
      );
}

/// 발표자 뽑기 (동작함)
class PickerDialog extends StatefulWidget {
  const PickerDialog({super.key});
  @override
  State<PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<PickerDialog> {
  int n = 7;
  bool rolling = false;
  Future<void> _roll() async {
    setState(() => rolling = true);
    final r = math.Random();
    for (var i = 0; i < 22; i++) {
      await Future.delayed(Duration(milliseconds: 40 + i * 9));
      if (!mounted) return;
      setState(() => n = r.nextInt(28) + 1);
    }
    setState(() => rolling = false);
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Glass(
          radius: 30,
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('발표 번호', style: T.h(18, c: T.sub)),
            const SizedBox(height: 10),
            AnimatedScale(
              scale: rolling ? 0.9 : 1.1,
              duration: const Duration(milliseconds: 200),
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(colors: [T.red, T.orange]).createShader(r),
                child: Text('$n', style: T.h(160, c: Colors.white)),
              ),
            ),
            const SizedBox(height: 14),
            GradButton(rolling ? '뽑는 중...' : '뽑기', icon: Icons.casino_rounded, colors: const [T.red, T.orange], dark: false, onTap: rolling ? null : _roll),
          ]),
        ),
      );
}

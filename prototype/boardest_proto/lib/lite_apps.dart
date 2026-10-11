import 'package:flutter/material.dart';
import 'ui.dart';

/// Boardest Teacher Lite — 모바일 (390×800 기준)
class TeacherLiteApp extends StatefulWidget {
  const TeacherLiteApp({super.key});
  @override
  State<TeacherLiteApp> createState() => _TeacherLiteAppState();
}

class _TeacherLiteAppState extends State<TeacherLiteApp> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: T.bg,
      child: Column(children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(key: ValueKey(tab), child: switch (tab) { 0 => _timetable(), 1 => _otp(), _ => _meal() }),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          decoration: const BoxDecoration(color: Color(0xFF0A1022), border: Border(top: BorderSide(color: T.line))),
          child: Row(children: [
            for (final e in [(Icons.view_timeline_rounded, '시간표'), (Icons.password_rounded, 'OTP'), (Icons.restaurant_rounded, '급식')].indexed)
              Expanded(
                child: Pressable(
                  onTap: () => setState(() => tab = e.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(color: tab == e.$1 ? T.teal.withValues(alpha: 0.18) : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                    child: Column(children: [
                      Icon(e.$2.$1, color: tab == e.$1 ? T.mint : T.sub),
                      Text(e.$2.$2, style: T.h(11, c: tab == e.$1 ? T.mint : T.sub, w: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _timetable() => Aurora(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Text('Teacher Lite', style: T.h(20)),
              const Spacer(),
              const PillTag('v1.2 최신', icon: Icons.verified_rounded),
            ]),
            const SizedBox(height: 14),
            // 상시 OTP 퀵바
            Reveal(
              child: Glass(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                gradient: LinearGradient(colors: [T.teal.withValues(alpha: 0.3), const Color(0xFF11182F)]),
                border: T.mint.withValues(alpha: 0.4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('칠판 로그인 OTP', style: T.h(12, c: T.sub)),
                  const SizedBox(height: 4),
                  const FittedBox(fit: BoxFit.scaleDown, child: OtpBox(digit: 50, compact: true)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Text('오늘 시간표', style: T.h(16)),
            const SizedBox(height: 10),
            for (var i = 0; i < 7; i++)
              Reveal(
                delayMs: 60 * i,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: i == nowPeriod ? subjects[i].color.withValues(alpha: 0.25) : T.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: i == nowPeriod ? subjects[i].color : T.line, width: i == nowPeriod ? 2 : 1),
                  ),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: subjects[i].color, borderRadius: BorderRadius.circular(12)),
                      child: Icon(subjects[i].icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${i + 1}교시  ${subjects[i].name}', style: T.h(15))),
                    Text(periodTimes[i], style: T.h(12, c: T.sub, w: FontWeight.w600)),
                  ]),
                ),
              ),
          ]),
        ),
      );

  Widget _otp() => Aurora(
        child: SafeArea(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('칠판 로그인 번호', style: T.h(16, c: T.sub)),
            const SizedBox(height: 24),
            const FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: OtpBox(digit: 64))),
            const SizedBox(height: 28),
            const PillTag('칠판의 Cloud 로그인 > OTP 입력', icon: Icons.touch_app_rounded),
          ]),
        ),
      );

  Widget _meal() => SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('오늘 급식', style: T.h(22)),
          const SizedBox(height: 12),
          for (final m in mealMenu)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: T.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: T.line)),
              child: Text(m, style: T.h(18, w: FontWeight.w700)),
            ),
        ]),
      );
}

/// Boardest Class Lite — 초경량 시간표/급식 (1280×720, 순수 HTML 느낌의 플랫·고대비)
class ClassLiteApp extends StatelessWidget {
  const ClassLiteApp({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0F1A),
      padding: const EdgeInsets.all(22),
      child: Column(children: [
        Row(children: [
          LiveClock(builder: (n) => Text('${n.hour}:${two(n.minute)}', style: T.h(86, ls: -3))),
          const SizedBox(width: 18),
          LiveClock(builder: (n) => Text('${n.month}월 ${n.day}일 ${weekdays[n.weekday - 1]}요일\n2학년 4반', style: T.h(22, c: T.sub, w: FontWeight.w700))),
          const Spacer(),
          const PillTag('Lite · 자동 업데이트 완료 v1.2', icon: Icons.system_update_alt_rounded),
        ]),
        const SizedBox(height: 18),
        Expanded(
          flex: 3,
          child: Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == 6 ? 0 : 10),
                  decoration: BoxDecoration(
                    color: i == nowPeriod ? subjects[i].color : const Color(0xFF151C30),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: i == nowPeriod ? Colors.white : T.line, width: i == nowPeriod ? 3 : 1),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${i + 1}', style: T.h(18, c: i == nowPeriod ? Colors.white : T.sub)),
                    const SizedBox(height: 8),
                    Text(subjects[i].name, style: T.h(34)),
                    const SizedBox(height: 6),
                    Text(periodTimes[i], style: T.h(13, c: i == nowPeriod ? Colors.white : T.sub, w: FontWeight.w600)),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        Expanded(
          flex: 2,
          child: Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(color: const Color(0xFF151C30), borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('지금', style: T.h(16, c: T.sub)),
                  Text('3교시 ${subjects[nowPeriod].name}', style: T.h(54, c: subjects[nowPeriod].color)),
                  Text('다음 · 4교시 ${subjects[nowPeriod + 1].name}', style: T.h(18, c: T.sub, w: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(color: const Color(0xFF151C30), borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('오늘 급식', style: T.h(20, c: T.orange)),
                  const SizedBox(height: 10),
                  Expanded(child: Wrap(spacing: 10, runSpacing: 8, children: [for (final m in mealMenu) Text(m, style: T.h(22, w: FontWeight.w700))])),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

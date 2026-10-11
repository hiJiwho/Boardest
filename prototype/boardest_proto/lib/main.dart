import 'package:flutter/material.dart';
import 'ui.dart';
import 'class_app.dart';
import 'teacher_app.dart';
import 'lite_apps.dart';

void main() => runApp(const ProtoApp());

class ProtoApp extends StatelessWidget {
  const ProtoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Boardest UI Prototype',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF04060C),
          colorScheme: const ColorScheme.dark(primary: T.teal),
          useMaterial3: true,
        ),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int app = 0;
  static const apps = [
    ('Class', Icons.dashboard_customize_rounded, T.teal, '전자칠판 대시보드'),
    ('Teacher', Icons.school_rounded, T.purple, '교사용 앱'),
    ('Teacher Lite', Icons.smartphone_rounded, T.mint, '모바일 OTP·시간표'),
    ('Class Lite', Icons.bolt_rounded, T.orange, '초경량 시간표'),
  ];

  @override
  Widget build(BuildContext context) {
    final phone = app == 2;
    final size = phone ? const Size(390, 800) : const Size(1280, 720);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(-0.6, -0.8), radius: 1.4, colors: [Color(0xFF14183A), Color(0xFF04060C)]),
        ),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(children: [
                Text('Boardest', style: T.h(20)),
                const SizedBox(width: 8),
                Text('UI Prototype · 승인용', style: T.h(13, c: T.sub, w: FontWeight.w600)),
                const Spacer(),
                for (var i = 0; i < apps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Pressable(
                      onTap: () => setState(() => app = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: app == i ? apps[i].$3 : T.card,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: app == i ? [BoxShadow(color: apps[i].$3.withValues(alpha: 0.5), blurRadius: 16)] : null,
                          border: Border.all(color: T.line),
                        ),
                        child: Row(children: [
                          Icon(apps[i].$2, size: 18, color: app == i ? const Color(0xFF04141A) : T.sub),
                          const SizedBox(width: 6),
                          Text(apps[i].$1, style: T.h(13, c: app == i ? const Color(0xFF04141A) : Colors.white)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      width: size.width,
                      height: size.height,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(phone ? 44 : 22),
                        border: Border.all(color: phone ? const Color(0xFF2A3050) : T.line, width: phone ? 8 : 1),
                        boxShadow: [BoxShadow(color: apps[app].$3.withValues(alpha: 0.25), blurRadius: 60, spreadRadius: 2)],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        child: KeyedSubtree(
                          key: ValueKey(app),
                          child: switch (app) {
                            0 => const ClassApp(),
                            1 => const TeacherApp(),
                            2 => const TeacherLiteApp(),
                            _ => const ClassLiteApp(),
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

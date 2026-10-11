import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// ───────── Design tokens (전 앱 공통) ─────────
class T {
  static const bg = Color(0xFF080C18);
  static const bg2 = Color(0xFF0E1428);
  static const card = Color(0xFF141B33);
  static const card2 = Color(0xFF1A2342);
  static const line = Color(0x1AFFFFFF);
  static const teal = Color(0xFF2EC4B6);
  static const mint = Color(0xFF00F5D4);
  static const purple = Color(0xFF7B61FF);
  static const violet = Color(0xFFA78BFA);
  static const orange = Color(0xFFFF9F1C);
  static const red = Color(0xFFEF4565);
  static const blue = Color(0xFF3B82F6);
  static const sub = Color(0xFF8E9ABF);

  static TextStyle h(double s, {Color c = Colors.white, FontWeight w = FontWeight.w800, double? ls}) =>
      TextStyle(fontSize: s, color: c, fontWeight: w, letterSpacing: ls, height: 1.15);
}

/// ───────── Mock data ─────────
class Subject {
  final String name;
  final Color color;
  final IconData icon;
  const Subject(this.name, this.color, this.icon);
}

const subjects = <Subject>[
  Subject('국어', Color(0xFFEF4565), Icons.menu_book_rounded),
  Subject('수학', Color(0xFF3B82F6), Icons.calculate_rounded),
  Subject('영어', Color(0xFF16A34A), Icons.translate_rounded),
  Subject('과학', Color(0xFFA855F7), Icons.science_rounded),
  Subject('사회', Color(0xFFF59E0B), Icons.public_rounded),
  Subject('체육', Color(0xFF14B8A6), Icons.sports_soccer_rounded),
  Subject('음악', Color(0xFFEC4899), Icons.music_note_rounded),
];

const periodTimes = ['08:40', '09:35', '10:30', '11:25', '13:10', '14:05', '15:00'];
const mealMenu = ['잡곡밥', '된장찌개', '불고기', '콩나물무침', '배추김치', '사과'];

/// 현재 교시 (프로토에서는 3교시로 고정 표시, 0-index)
const int nowPeriod = 2;

/// ───────── Live clock ─────────
class LiveClock extends StatefulWidget {
  final Widget Function(DateTime now) builder;
  const LiveClock({super.key, required this.builder});
  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late Timer _t;
  DateTime _now = DateTime.now();
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_now);
}

String two(int n) => n.toString().padLeft(2, '0');
const weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// ───────── Glass card ─────────
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Gradient? gradient;
  final Color? border;
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.gradient,
    this.border,
  });
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: gradient ??
              const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF18203C), Color(0xFF11182F)],
              ),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border ?? T.line),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: child,
      );
}

/// ───────── Hover/press scale ─────────
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const Pressable({super.key, required this.child, this.onTap});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _h = false, _d = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _d = true),
          onTapCancel: () => setState(() => _d = false),
          onTapUp: (_) => setState(() => _d = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _d ? 0.95 : (_h ? 1.04 : 1),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutBack,
            child: widget.child,
          ),
        ),
      );
}

/// ───────── Fade/slide in on build ─────────
class Reveal extends StatelessWidget {
  final Widget child;
  final int delayMs;
  final Offset from;
  const Reveal({super.key, required this.child, this.delayMs = 0, this.from = const Offset(0, 24)});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 600 + delayMs),
        curve: Interval(delayMs / (600 + delayMs), 1, curve: Curves.easeOutCubic),
        builder: (_, v, c) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(from.dx * (1 - v), from.dy * (1 - v)), child: c),
        ),
        child: child,
      );
}

/// ───────── Animated aurora background ─────────
class Aurora extends StatefulWidget {
  final Widget child;
  final Color a, b;
  const Aurora({super.key, required this.child, this.a = T.purple, this.b = T.teal});
  @override
  State<Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<Aurora> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = _c.value * 2 * math.pi;
          return Container(
            color: T.bg,
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _AuroraPainter(t, widget.a, widget.b))),
              child!,
            ]),
          );
        },
        child: widget.child,
      );
}

class _AuroraPainter extends CustomPainter {
  final double t;
  final Color a, b;
  _AuroraPainter(this.t, this.a, this.b);
  @override
  void paint(Canvas canvas, Size s) {
    void blob(Offset c, double r, Color col) {
      final p = Paint()
        ..shader = RadialGradient(colors: [col.withValues(alpha: 0.28), col.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, p);
    }

    blob(Offset(s.width * (0.2 + 0.1 * math.sin(t)), s.height * (0.25 + 0.1 * math.cos(t))), s.width * 0.45, a);
    blob(Offset(s.width * (0.85 + 0.08 * math.cos(t)), s.height * (0.8 + 0.1 * math.sin(t))), s.width * 0.5, b);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter o) => o.t != t;
}

/// ───────── Textbook card ─────────
class BookCard extends StatelessWidget {
  final Subject s;
  final bool active;
  final bool done;
  final String time;
  final int period;
  final double h;
  const BookCard({
    super.key,
    required this.s,
    required this.period,
    required this.time,
    this.active = false,
    this.done = false,
    this.h = 120,
  });
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: h * 0.82,
      height: h,
      padding: EdgeInsets.all(h * 0.07),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [s.color, Color.lerp(s.color, Colors.black, 0.45)!],
        ),
        border: Border.all(color: active ? Colors.white : Colors.white24, width: active ? 2.5 : 1),
        boxShadow: [
          BoxShadow(color: s.color.withValues(alpha: active ? 0.7 : 0.25), blurRadius: active ? 26 : 10, offset: const Offset(0, 6)),
        ],
      ),
      child: Opacity(
        opacity: done ? 0.45 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
                child: Text('${period + 1}', style: T.h(h * 0.11)),
              ),
              const Spacer(),
              if (active) Icon(Icons.bolt_rounded, color: Colors.white, size: h * 0.14),
            ]),
            const Spacer(),
            Icon(s.icon, color: Colors.white70, size: h * 0.24),
            SizedBox(height: h * 0.02),
            Text(s.name, style: T.h(h * 0.16)),
            Text(time, style: T.h(h * 0.095, c: Colors.white70, w: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// ───────── Circular countdown ring ─────────
class Ring extends StatelessWidget {
  final double value;
  final double size;
  final Color color;
  final Widget child;
  const Ring({super.key, required this.value, required this.size, required this.color, required this.child});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(size: Size.square(size), painter: _RingPainter(value, color)),
          child,
        ]),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color c;
  _RingPainter(this.v, this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(6, 6, s.width - 12, s.height - 12);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = Colors.white10;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7
      ..color = c;
    canvas.drawArc(r, 0, 2 * math.pi, false, bg);
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * v, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.v != v || o.c != c;
}

/// ───────── OTP (mock, 60s window) ─────────
class OtpBox extends StatefulWidget {
  final double digit;
  final bool compact;
  const OtpBox({super.key, this.digit = 54, this.compact = false});
  @override
  State<OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<OtpBox> {
  late Timer _t;
  int _left = 60 - DateTime.now().second;
  String _code = '';
  @override
  void initState() {
    super.initState();
    _code = _gen();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _left = 60 - DateTime.now().second;
        if (_left == 60) _code = _gen();
      });
    });
  }

  String _gen() {
    final w = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final n = (w * 2654435761) % 1000000;
    return n.toString().padLeft(6, '0');
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digits = '${_code.substring(0, 3)}  ${_code.substring(3)}';
    final ring = Ring(
      value: _left / 60,
      size: widget.compact ? 54 : 84,
      color: _left < 10 ? T.red : T.mint,
      child: Text('$_left', style: T.h(widget.compact ? 16 : 24)),
    );
    final code = ShaderMask(
      shaderCallback: (r) => const LinearGradient(colors: [T.mint, Colors.white, T.teal]).createShader(r),
      child: Text(
        digits,
        style: TextStyle(
          fontSize: widget.digit,
          fontWeight: FontWeight.w900,
          letterSpacing: widget.digit * 0.12,
          color: Colors.white,
        ),
      ),
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [code, SizedBox(width: widget.digit * 0.4), ring]);
  }
}

/// ───────── Pills & buttons ─────────
class PillTag extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const PillTag(this.text, {super.key, this.color = T.teal, this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 6)],
          Text(text, style: T.h(12, c: color, w: FontWeight.w700)),
        ]),
      );
}

class GradButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final List<Color> colors;
  final VoidCallback? onTap;
  final bool dark;
  const GradButton(this.label, {super.key, this.icon, this.colors = const [T.teal, T.mint], this.onTap, this.dark = true});
  @override
  Widget build(BuildContext context) {
    final fg = dark ? const Color(0xFF04141A) : Colors.white;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
          Text(label, style: T.h(15, c: fg)),
        ]),
      ),
    );
  }
}

/// Segmented tab selector
class Seg extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final Color color;
  const Seg({super.key, required this.labels, required this.index, required this.onChanged, this.color = T.purple});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFF0A1022), borderRadius: BorderRadius.circular(14), border: Border.all(color: T.line)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? color : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: i == index ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 14)] : null,
                  ),
                  child: Text(labels[i], style: T.h(13, c: i == index ? Colors.white : T.sub, w: FontWeight.w700)),
                ),
              ),
            ),
        ]),
      );
}

/// Fake QR
class FakeQr extends StatelessWidget {
  final double size;
  const FakeQr({super.key, this.size = 200});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: CustomPaint(painter: _QrPainter()),
      );
}

class _QrPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    const n = 25;
    final u = s.width / n;
    final rnd = math.Random(7);
    final p = Paint()..color = const Color(0xFF0B1020);
    bool finder(int x, int y) => (x < 8 && y < 8) || (x > n - 9 && y < 8) || (x < 8 && y > n - 9);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (finder(x, y)) continue;
        if (rnd.nextDouble() > 0.52) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x * u, y * u, u * 0.92, u * 0.92), Radius.circular(u * 0.2)), p);
        }
      }
    }
    void eye(double ox, double oy) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(ox * u, oy * u, 7 * u, 7 * u), Radius.circular(u)), p);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH((ox + 1) * u, (oy + 1) * u, 5 * u, 5 * u), Radius.circular(u * 0.7)), Paint()..color = Colors.white);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH((ox + 2) * u, (oy + 2) * u, 3 * u, 3 * u), Radius.circular(u * 0.5)), p);
    }

    eye(0, 0);
    eye(n - 7, 0);
    eye(0, n - 7);
  }

  @override
  bool shouldRepaint(_) => false;
}

/// ───────── 급식 데이터 (알레르기 번호 포함) ─────────
class Dish {
  final String name;
  final List<int> allergy;
  const Dish(this.name, [this.allergy = const []]);
}

const allergyNames = {
  1: '난류', 2: '우유', 3: '메밀', 4: '땅콩', 5: '대두', 6: '밀', 7: '고등어', 8: '게', 9: '새우',
  10: '돼지고기', 11: '복숭아', 12: '토마토', 13: '아황산류', 14: '호두', 15: '닭고기', 16: '쇠고기', 17: '오징어', 18: '조개류',
};

const mealToday = [
  Dish('잡곡밥'),
  Dish('된장찌개', [5, 6, 13]),
  Dish('불고기', [5, 6, 10, 16]),
  Dish('콩나물무침', [5]),
  Dish('배추김치', [9, 13]),
  Dish('우유', [2]),
];

const mealTomorrow = [
  Dish('치킨마요덮밥', [1, 5, 6, 15]),
  Dish('미소국', [5, 6]),
  Dish('감자채볶음'),
  Dish('오이무침'),
  Dish('깍두기', [9]),
  Dish('요구르트', [2]),
];

Color allergyColor(int n) => Color.lerp(const Color(0xFFFF6B6B), const Color(0xFFFFD166), (n % 6) / 6)!;

/// 급식 패널: 오늘+내일, 알레르기 번호 표시, 탭=투표, 꾹=형광펜
class MealPanel extends StatefulWidget {
  const MealPanel({super.key});
  @override
  State<MealPanel> createState() => _MealPanelState();
}

class _MealPanelState extends State<MealPanel> {
  final highlighted = <String>{};
  final votes = <String, int>{'불고기': 12, '치킨마요덮밥': 19};
  final voted = <String>{};

  Widget _day(String title, List<Dish> list, String tag, Color c) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PillTag(tag, color: c),
          const SizedBox(width: 8),
          Text(title, style: T.h(15)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: Column(children: [
            for (final d in list)
              Expanded(
                child: _row('$tag-${d.name}', d),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _row(String key, Dish d) {
    final hl = highlighted.contains(key);
    final v = votes[d.name] ?? 0;
    final mine = voted.contains(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: () => setState(() {
          if (mine) {
            voted.remove(key);
            votes[d.name] = v - 1;
          } else {
            voted.add(key);
            votes[d.name] = v + 1;
          }
        }),
        onLongPress: () => setState(() => hl ? highlighted.remove(key) : highlighted.add(key)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: hl ? const Color(0xFFFFEB3B) : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: mine ? T.mint : T.line, width: mine ? 1.5 : 1),
          ),
          child: Row(children: [
            Expanded(
              child: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h(15, c: hl ? Colors.black : Colors.white, w: FontWeight.w700)),
            ),
            for (final a in d.allergy)
              Container(
                margin: const EdgeInsets.only(left: 3),
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: allergyColor(a), shape: BoxShape.circle),
                child: Text('$a', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black)),
              ),
            const SizedBox(width: 8),
            Icon(mine ? Icons.thumb_up_alt_rounded : Icons.thumb_up_off_alt_rounded, size: 15, color: hl ? Colors.black87 : (mine ? T.mint : T.sub)),
            const SizedBox(width: 3),
            SizedBox(width: 20, child: Text('$v', style: T.h(12, c: hl ? Colors.black87 : T.sub, w: FontWeight.w700))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          const Icon(Icons.restaurant_rounded, color: T.orange, size: 20),
          const SizedBox(width: 8),
          Text('급식', style: T.h(18)),
          const Spacer(),
          Text('탭 = 투표 · 꾹 = 형광펜', style: T.h(11, c: T.sub, w: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _day('오늘', mealToday, '10/10', T.orange),
            const SizedBox(width: 14),
            _day('내일', mealTomorrow, '10/11', T.teal),
          ]),
        ),
      ]);
}

/// ───────── 교과서 표지 이미지 (실제 판에서는 교과서 이미지 사용) ─────────
class BookCover extends StatelessWidget {
  final Subject s;
  final double h;
  final String label;
  final bool active;
  final bool done;
  const BookCover({super.key, required this.s, required this.h, this.label = '2-1', this.active = false, this.done = false});
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: h * 0.76,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? Colors.white : Colors.black26, width: active ? 3 : 1),
        boxShadow: [BoxShadow(color: s.color.withValues(alpha: active ? 0.8 : 0.3), blurRadius: active ? 28 : 10, offset: const Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: done ? 0.4 : 1,
        child: Stack(fit: StackFit.expand, children: [
          CustomPaint(painter: _CoverPainter(s.color)),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: h * 0.06, vertical: h * 0.03),
              color: Colors.black.withValues(alpha: 0.35),
              child: Text('${s.name} $label', style: T.h(h * 0.085, w: FontWeight.w700)),
            ),
          ),
          Positioned(
            left: h * 0.06,
            right: h * 0.04,
            bottom: h * 0.1,
            child: Text(s.name, style: T.h(h * 0.26, w: FontWeight.w900)),
          ),
          Positioned(
            left: h * 0.06,
            bottom: h * 0.03,
            child: Text('중학교  교육부', style: T.h(h * 0.06, c: Colors.white70, w: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _CoverPainter extends CustomPainter {
  final Color c;
  _CoverPainter(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(c, Colors.white, .25)!, Color.lerp(c, Colors.black, .5)!]).createShader(Offset.zero & s));
    canvas.drawCircle(Offset(s.width * .8, s.height * .35), s.width * .42, Paint()..color = Colors.white.withValues(alpha: 0.14));
    canvas.drawCircle(Offset(s.width * .2, s.height * .6), s.width * .3, Paint()..color = Colors.black.withValues(alpha: 0.12));
    final p = Path()
      ..moveTo(0, s.height * .72)
      ..quadraticBezierTo(s.width * .5, s.height * .55, s.width, s.height * .78)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(p, Paint()..color = Colors.black.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(_) => false;
}

/// ───────── 쪽지 (Teacher / Lite 공용) ─────────
class MessageView extends StatefulWidget {
  final bool compact;
  const MessageView({super.key, this.compact = false});
  @override
  State<MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends State<MessageView> {
  final ctl = TextEditingController();
  String to = '2학년 4반 칠판';
  final sent = <(String, String, String)>[
    ('2학년 4반 칠판', '오늘 5교시는 체육관에서 진행합니다.', '09:12'),
    ('2학년 6반 칠판', '급식 지도 순서 변경 안내', '어제'),
  ];
  static const targets = ['2학년 4반 칠판', '2학년 6반 칠판', '전체 칠판'];

  void _send() {
    if (ctl.text.trim().isEmpty) return;
    setState(() {
      sent.insert(0, (to, ctl.text.trim(), '방금'));
      ctl.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('쪽지 발송', style: T.h(widget.compact ? 22 : 28)),
          const SizedBox(height: 4),
          Text('선택한 칠판 화면에 쪽지가 알림으로 표시됩니다', style: T.h(12, c: T.sub, w: FontWeight.w600)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in targets)
              Pressable(
                onTap: () => setState(() => to = t),
                child: PillTag(t, color: to == t ? T.mint : T.sub, icon: to == t ? Icons.check_rounded : null),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '쪽지 내용을 입력하세요',
              hintStyle: const TextStyle(color: T.sub),
              filled: true,
              fillColor: T.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: GradButton('보내기', icon: Icons.send_rounded, onTap: _send)),
          const SizedBox(height: 10),
          Text('보낸 쪽지', style: T.h(14, c: T.sub)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              for (final m in sent)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: T.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: T.line)),
                  child: Row(children: [
                    const Icon(Icons.mark_email_read_rounded, color: T.teal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.$1, style: T.h(12, c: T.teal)),
                        Text(m.$2, style: T.h(14, w: FontWeight.w600)),
                      ]),
                    ),
                    Text(m.$3, style: T.h(11, c: T.sub)),
                  ]),
                ),
            ]),
          ),
        ]),
      );
}

/// ───────── 판서 관리 (Teacher / Lite 공용) ─────────
class InkView extends StatefulWidget {
  final bool compact;
  const InkView({super.key, this.compact = false});
  @override
  State<InkView> createState() => _InkViewState();
}

class _InkViewState extends State<InkView> {
  final list = <(String, String, bool)>[
    ('수학 2-1 · 도형', '오늘 09:40', true),
    ('국어 받아쓰기', '어제', true),
    ('과학 실험 정리', '2일 전', false),
    ('영어 단어 퀴즈', '3일 전', false),
    ('사회 지도 활동', '1주 전', false),
    ('자유 판서', '1주 전', false),
  ];
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('판서 관리', style: T.h(widget.compact ? 22 : 28)),
          const SizedBox(height: 4),
          Text('칠판에서 저장한 판서를 열고, Cloud에 보관하거나 삭제하세요', style: T.h(12, c: T.sub, w: FontWeight.w600)),
          const SizedBox(height: 14),
          Expanded(
            child: GridView.builder(
              itemCount: list.length,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: widget.compact ? 220 : 260, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.05),
              itemBuilder: (_, i) {
                final e = list[i];
                return Reveal(
                  delayMs: i * 50,
                  child: Glass(
                    padding: const EdgeInsets.all(10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(color: const Color(0xFF0B1020), borderRadius: BorderRadius.circular(12), border: Border.all(color: T.line)),
                          child: CustomPaint(painter: _InkPainter(i), size: Size.infinite),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(e.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h(13)),
                      Row(children: [
                        Text(e.$2, style: T.h(11, c: T.sub, w: FontWeight.w600)),
                        const Spacer(),
                        Icon(e.$3 ? Icons.cloud_done_rounded : Icons.cloud_upload_outlined, size: 16, color: e.$3 ? T.mint : T.sub),
                        const SizedBox(width: 6),
                        GestureDetector(onTap: () => setState(() => list.removeAt(i)), child: const Icon(Icons.delete_outline_rounded, size: 18, color: T.red)),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      );
}

class _InkPainter extends CustomPainter {
  final int seed;
  _InkPainter(this.seed);
  @override
  void paint(Canvas canvas, Size s) {
    final r = math.Random(seed + 3);
    final cols = [T.mint, T.orange, T.violet, Colors.white];
    for (var k = 0; k < 4; k++) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.5
        ..color = cols[(k + seed) % 4];
      final path = Path()..moveTo(r.nextDouble() * s.width, r.nextDouble() * s.height);
      for (var j = 0; j < 3; j++) {
        path.quadraticBezierTo(r.nextDouble() * s.width, r.nextDouble() * s.height, r.nextDouble() * s.width, r.nextDouble() * s.height);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

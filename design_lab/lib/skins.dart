import 'dart:ui';
import 'package:flutter/material.dart';

/// 디자인 스킨: 같은 레이아웃을 글래스 / Fluent / Material 로 해석
abstract class Skin {
  const Skin();
  String get name;
  Color get accent;
  Color get onAccent;
  Color get ink => Colors.white;
  Color get dim => const Color(0xB3FFFFFF);
  Color get faint => const Color(0x66FFFFFF);
  String? get font => 'SiwonhanSeolreim';
  double get r;

  Widget backdrop(Widget child);
  Widget surface({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(20), double? radius, bool strong = false, bool glow = false});
  Widget tile({required Widget child, bool selected = false, EdgeInsetsGeometry padding = const EdgeInsets.all(14), double? radius});
  Widget pill(String text, {IconData? icon, bool selected = false, Color? color});
  Widget button(String label, {IconData? icon, bool primary = true});

  TextStyle ts(double size, {FontWeight w = FontWeight.w500, Color? c, double? h, double? ls}) => TextStyle(
        fontFamily: font,
        fontFamilyFallback: const ['Noto Sans KR', 'Malgun Gothic', 'sans-serif'],
        fontSize: size,
        fontWeight: w,
        color: c ?? ink,
        height: h,
        letterSpacing: ls,
        decoration: TextDecoration.none,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  Widget _label(String text, IconData? icon, Color color, double size, FontWeight w) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: size + 3, color: color), SizedBox(width: size * 0.4)],
          Text(text, style: ts(size, w: w, c: color)),
        ],
      );
}

// ═════════════════════════════════════════════════════════════
// 1) Glassmorphism — 유리 질감 + 민트 포인트
// ═════════════════════════════════════════════════════════════
class GlassSkin extends Skin {
  const GlassSkin();
  @override
  String get name => 'Glassmorphism';
  @override
  Color get accent => const Color(0xFF00F5D4);
  @override
  Color get onAccent => const Color(0xFF00201A);
  @override
  double get r => 30;

  Widget _blob(Color c, double s) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c.withOpacity(0.5), c.withOpacity(0)])),
      );

  @override
  Widget backdrop(Widget child) => Container(
        color: const Color(0xFF050A12),
        child: Stack(fit: StackFit.expand, children: [
          Positioned(left: -260, top: -260, child: _blob(accent, 900)),
          Positioned(right: -220, bottom: -280, child: _blob(const Color(0xFF7F5AF0), 900)),
          Positioned(right: 320, top: -320, child: _blob(const Color(0xFF2D7DFF), 700)),
          Positioned(left: 200, bottom: -380, child: _blob(accent, 600)),
          child,
        ]),
      );

  @override
  Widget surface({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(20), double? radius, bool strong = false, bool glow = false}) {
    final rad = BorderRadius.circular(radius ?? r);
    return Container(
      decoration: BoxDecoration(
        borderRadius: rad,
        boxShadow: [
          if (glow) BoxShadow(color: accent.withOpacity(0.28), blurRadius: 44) else BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 30, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: rad,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: rad,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(strong ? 0.22 : 0.13), Colors.white.withOpacity(strong ? 0.07 : 0.04)]),
              border: Border.all(color: glow ? accent.withOpacity(0.75) : Colors.white.withOpacity(0.22), width: glow ? 1.6 : 1.1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget tile({required Widget child, bool selected = false, EdgeInsetsGeometry padding = const EdgeInsets.all(14), double? radius}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius ?? r * 0.62),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [(selected ? accent : Colors.white).withOpacity(selected ? 0.24 : 0.12), (selected ? accent : Colors.white).withOpacity(selected ? 0.08 : 0.03)]),
          border: Border.all(color: selected ? accent.withOpacity(0.85) : Colors.white.withOpacity(0.14), width: selected ? 1.5 : 1),
          boxShadow: selected ? [BoxShadow(color: accent.withOpacity(0.22), blurRadius: 22)] : null,
        ),
        child: child,
      );

  @override
  Widget pill(String text, {IconData? icon, bool selected = false, Color? color}) {
    final fg = selected ? onAccent : (color ?? ink);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: selected ? accent : (color ?? Colors.white).withOpacity(0.12),
        border: Border.all(color: selected ? accent : Colors.white.withOpacity(0.2)),
        boxShadow: selected ? [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 16)] : null,
      ),
      child: _label(text, icon, fg, 14, FontWeight.w800),
    );
  }

  @override
  Widget button(String label, {IconData? icon, bool primary = true}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          color: primary ? accent : Colors.white.withOpacity(0.12),
          border: Border.all(color: primary ? accent : Colors.white.withOpacity(0.25)),
          boxShadow: primary ? [BoxShadow(color: accent.withOpacity(0.45), blurRadius: 22)] : null,
        ),
        child: _label(label, icon, primary ? onAccent : ink, 17, FontWeight.w900),
      );
}

// ═════════════════════════════════════════════════════════════
// 2) Fluent (Windows 11 Mica / Acrylic)
// ═════════════════════════════════════════════════════════════
class FluentSkin extends Skin {
  const FluentSkin();
  @override
  String get name => 'Fluent';
  @override
  Color get accent => const Color(0xFF3DEBD0);
  @override
  Color get onAccent => const Color(0xFF00201A);
  @override
  double get r => 8;
  @override
  String? get font => 'SiwonhanSeolreim';

  @override
  Widget backdrop(Widget child) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1C2B2A), Color(0xFF202020), Color(0xFF1B1F2A)]),
        ),
        child: child,
      );

  @override
  Widget surface({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(20), double? radius, bool strong = false, bool glow = false}) {
    final rad = BorderRadius.circular(radius ?? r);
    return Container(
      decoration: BoxDecoration(borderRadius: rad, boxShadow: [BoxShadow(color: Colors.black.withOpacity(strong ? 0.4 : 0.26), blurRadius: strong ? 24 : 12, offset: const Offset(0, 6))]),
      child: ClipRRect(
        borderRadius: rad,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: rad,
              color: const Color(0xFF2B2B2B).withOpacity(strong ? 0.9 : 0.72),
              border: Border.all(color: glow ? accent.withOpacity(0.7) : Colors.white.withOpacity(0.09), width: glow ? 1.5 : 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget tile({required Widget child, bool selected = false, EdgeInsetsGeometry padding = const EdgeInsets.all(14), double? radius}) {
    final rad = BorderRadius.circular(radius ?? 6);
    return Container(
      decoration: BoxDecoration(borderRadius: rad, border: Border.all(color: Colors.white.withOpacity(selected ? 0.1 : 0.06))),
      child: ClipRRect(
        borderRadius: rad,
        child: Container(
          color: Colors.white.withOpacity(selected ? 0.11 : 0.05),
          child: Stack(fit: StackFit.passthrough, children: [
            Padding(padding: padding, child: child),
            if (selected)
              Positioned(left: 0, top: 0, bottom: 0, child: Center(child: Container(width: 3, height: 18, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget pill(String text, {IconData? icon, bool selected = false, Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: selected ? accent : (color ?? Colors.white).withOpacity(0.07),
          border: Border.all(color: selected ? accent : Colors.white.withOpacity(0.1)),
        ),
        child: _label(text, icon, selected ? onAccent : (color ?? ink), 13.5, FontWeight.w600),
      );

  @override
  Widget button(String label, {IconData? icon, bool primary = true}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: primary ? accent : Colors.white.withOpacity(0.08),
          border: Border.all(color: primary ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.1)),
        ),
        child: _label(label, icon, primary ? onAccent : ink, 15, FontWeight.w600),
      );
}

// ═════════════════════════════════════════════════════════════
// 3) Material 3 (Tonal / 큰 라운드 / Pill 버튼)
// ═════════════════════════════════════════════════════════════
class MaterialSkin extends Skin {
  const MaterialSkin();
  @override
  String get name => 'Material 3';
  @override
  Color get accent => const Color(0xFF5EEAD0);
  @override
  Color get onAccent => const Color(0xFF00382F);
  @override
  double get r => 28;
  @override
  String? get font => 'SiwonhanSeolreim';

  static const _container = Color(0xFF19211E);
  static const _containerHi = Color(0xFF222B28);
  static const _secondary = Color(0xFF1E4D45);
  static const _onSecondary = Color(0xFFB9F5EA);

  @override
  Widget backdrop(Widget child) => Container(color: const Color(0xFF0E1513), child: child);

  @override
  Widget surface({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(20), double? radius, bool strong = false, bool glow = false}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius ?? r),
          color: glow ? const Color(0xFF1B3A35) : (strong ? _containerHi : _container),
        ),
        child: child,
      );

  @override
  Widget tile({required Widget child, bool selected = false, EdgeInsetsGeometry padding = const EdgeInsets.all(14), double? radius}) => Container(
        padding: padding,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius ?? 20), color: selected ? _secondary : _containerHi),
        child: child,
      );

  @override
  Widget pill(String text, {IconData? icon, bool selected = false, Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? _secondary : Colors.transparent,
          border: selected ? null : Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: _label(text, selected ? (icon ?? Icons.check_rounded) : icon, selected ? _onSecondary : (color ?? dim), 14, FontWeight.w500),
      );

  @override
  Widget button(String label, {IconData? icon, bool primary = true}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(40), color: primary ? accent : const Color(0xFF2C3834)),
        child: _label(label, icon, primary ? onAccent : _onSecondary, 16, FontWeight.w600),
      );
}

const kSkins = <Skin>[GlassSkin(), FluentSkin(), MaterialSkin()];

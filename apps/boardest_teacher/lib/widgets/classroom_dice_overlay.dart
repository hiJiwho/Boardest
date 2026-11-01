import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/lesson_tools.dart';

/// 플로팅 수업 주사위 오버레이 위젯
class ClassroomDiceOverlay extends StatefulWidget {
  final double scale;
  final Offset initialOffset;
  final VoidCallback onClose;
  final LessonDiceEngine? engine;

  const ClassroomDiceOverlay({
    super.key,
    required this.scale,
    required this.initialOffset,
    required this.onClose,
    this.engine,
  });

  @override
  State<ClassroomDiceOverlay> createState() => _ClassroomDiceOverlayState();
}

class _ClassroomDiceOverlayState extends State<ClassroomDiceOverlay> {
  late Offset _offset;
  late LessonDiceEngine _engine;
  bool _ownsEngine = false;

  @override
  void initState() {
    super.initState();
    _offset = widget.initialOffset;
    if (widget.engine != null) {
      _engine = widget.engine!;
    } else {
      _engine = LessonDiceEngine();
      _ownsEngine = true;
    }
    _engine.addListener(_onEngineUpdated);
  }

  void _onEngineUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineUpdated);
    if (_ownsEngine) {
      _engine.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    const accentColor = Color(0xFF2EC4B6);

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _offset += details.delta;
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 320 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20 * scale),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20 * scale,
                  spreadRadius: 2 * scale,
                ),
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.12),
                  blurRadius: 12 * scale,
                  spreadRadius: 1 * scale,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20 * scale),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 헤더 바
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14 * scale,
                        vertical: 10 * scale,
                      ),
                      color: Colors.white.withValues(alpha: 0.05),
                      child: Row(
                        children: [
                          Icon(
                            Icons.casino_rounded,
                            color: accentColor,
                            size: 16 * scale,
                          ),
                          SizedBox(width: 8 * scale),
                          Text(
                            '수업 주사위 (암호학적 RNG)',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontWeight: FontWeight.bold,
                              fontSize: 12 * scale,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.close_rounded,
                              color: const Color(0xFFEF4565),
                              size: 16 * scale,
                            ),
                            onPressed: widget.onClose,
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: EdgeInsets.all(16.0 * scale),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 주사위 개수 선택기
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [1, 2, 3, 4].map((count) {
                              final isSelected = _engine.diceCount == count;
                              return GestureDetector(
                                onTap: _engine.isRolling
                                    ? null
                                    : () => _engine.setDiceCount(count),
                                child: Container(
                                  margin: EdgeInsets.symmetric(horizontal: 4 * scale),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12 * scale,
                                    vertical: 6 * scale,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? accentColor.withValues(alpha: 0.25)
                                        : Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(8 * scale),
                                    border: Border.all(
                                      color: isSelected
                                          ? accentColor
                                          : Colors.white.withValues(alpha: 0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    '$count개',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 11 * scale,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? accentColor : Colors.white60,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          SizedBox(height: 16 * scale),

                          // 주사위 면 렌더링
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12 * scale,
                            runSpacing: 12 * scale,
                            children: _engine.currentValues.map((val) {
                              return _buildDieFace(val, scale, _engine.isRolling);
                            }).toList(),
                          ),
                          SizedBox(height: 14 * scale),

                          // 주사위 합계 표시
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12 * scale,
                              vertical: 4 * scale,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8 * scale),
                            ),
                            child: Text(
                              '합계: ${_engine.sum}  (${_engine.currentValues.join(' + ')})',
                              style: GoogleFonts.outfit(
                                fontSize: 13 * scale,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF00F5D4),
                              ),
                            ),
                          ),
                          SizedBox(height: 16 * scale),

                          // 던지기 버튼
                          SizedBox(
                            width: double.infinity,
                            height: 38 * scale,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10 * scale),
                                ),
                              ),
                              onPressed: _engine.isRolling
                                  ? null
                                  : () => _engine.rollWithAnimation(),
                              child: Text(
                                _engine.isRolling ? '주사위 굴리는 중...' : '주사위 굴리기 🎲',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDieFace(int value, double scale, bool isRolling) {
    const size = 60.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size * scale,
      height: size * scale,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(
          color: isRolling ? const Color(0xFF00F5D4) : const Color(0xFF2EC4B6).withValues(alpha: 0.6),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isRolling ? const Color(0xFF00F5D4) : const Color(0xFF2EC4B6))
                .withValues(alpha: isRolling ? 0.4 : 0.15),
            blurRadius: isRolling ? 16 * scale : 8 * scale,
            spreadRadius: isRolling ? 2 * scale : 0,
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$value',
          style: GoogleFonts.outfit(
            fontSize: 32 * scale,
            fontWeight: FontWeight.w900,
            color: isRolling ? const Color(0xFF00F5D4) : Colors.white,
          ),
        ),
      ),
    );
  }
}

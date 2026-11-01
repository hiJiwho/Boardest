import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/lesson_tools.dart';

/// 화면 강조용 스포트라이트 & 돋보기 오버레이
class SpotlightMagnifierOverlay extends StatefulWidget {
  final double scale;
  final VoidCallback onClose;
  final Offset? initialCenter;
  final double initialRadius;

  const SpotlightMagnifierOverlay({
    super.key,
    required this.scale,
    required this.onClose,
    this.initialCenter,
    this.initialRadius = 140.0,
  });

  @override
  State<SpotlightMagnifierOverlay> createState() => _SpotlightMagnifierOverlayState();
}

class _SpotlightMagnifierOverlayState extends State<SpotlightMagnifierOverlay> {
  late SpotlightGeometry _geometry;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final size = MediaQuery.of(context).size;
      final center = widget.initialCenter ?? Offset(size.width / 2, size.height / 2);
      _geometry = SpotlightGeometry(
        center: center,
        radius: widget.initialRadius,
        darkness: 0.75,
        isMagnifier: false,
        magnification: 1.75,
      );
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;

    return Stack(
      children: [
        // 1. 암전 마스크 및 스포트라이트 홀
        Positioned.fill(
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _geometry = _geometry.copyWith(
                  center: _geometry.center + details.delta,
                );
              });
            },
            child: CustomPaint(
              painter: _SpotlightPainter(geometry: _geometry),
              child: Container(),
            ),
          ),
        ),

        // 2. 돋보기 모드일 때 렌즈 링 및 확대 배율 뱃지
        Positioned(
          left: _geometry.center.dx - _geometry.radius,
          top: _geometry.center.dy - _geometry.radius,
          child: IgnorePointer(
            child: Container(
              width: _geometry.radius * 2,
              height: _geometry.radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _geometry.isMagnifier
                      ? const Color(0xFF00F5D4)
                      : const Color(0xFFFF8906),
                  width: 3 * scale,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_geometry.isMagnifier
                            ? const Color(0xFF00F5D4)
                            : const Color(0xFFFF8906))
                        .withValues(alpha: 0.4),
                    blurRadius: 16 * scale,
                    spreadRadius: 2 * scale,
                  ),
                ],
              ),
              child: _geometry.isMagnifier
                  ? Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8 * scale,
                          vertical: 4 * scale,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6 * scale),
                        ),
                        child: Text(
                          '${_geometry.magnification.toStringAsFixed(1)}x 돋보기',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF00F5D4),
                            fontSize: 12 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),

        // 3. 하단 플로팅 컨트롤 바
        Positioned(
          bottom: 24 * scale,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 16 * scale,
                  vertical: 10 * scale,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20 * scale),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20 * scale,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 모드 전환 버튼
                    IconButton(
                      icon: Icon(
                        _geometry.isMagnifier ? Icons.zoom_in : Icons.highlight,
                        color: _geometry.isMagnifier
                            ? const Color(0xFF00F5D4)
                            : const Color(0xFFFF8906),
                        size: 20 * scale,
                      ),
                      tooltip: _geometry.isMagnifier ? '스포트라이트 모드로 전환' : '돋보기 모드로 전환',
                      onPressed: () {
                        setState(() {
                          _geometry = _geometry.copyWith(
                            isMagnifier: !_geometry.isMagnifier,
                          );
                        });
                      },
                    ),
                    SizedBox(width: 8 * scale),

                    // 크기 조절 프리셋
                    _buildSizePreset('소', 90.0, scale),
                    SizedBox(width: 4 * scale),
                    _buildSizePreset('중', 140.0, scale),
                    SizedBox(width: 4 * scale),
                    _buildSizePreset('대', 220.0, scale),
                    SizedBox(width: 12 * scale),

                    // 어둡기 조절 토글
                    IconButton(
                      icon: Icon(
                        Icons.brightness_medium_rounded,
                        color: Colors.white70,
                        size: 18 * scale,
                      ),
                      tooltip: '암전 농도 조절',
                      onPressed: () {
                        setState(() {
                          final nextDarkness = _geometry.darkness >= 0.85
                              ? 0.5
                              : _geometry.darkness + 0.15;
                          _geometry = _geometry.copyWith(darkness: nextDarkness);
                        });
                      },
                    ),
                    SizedBox(width: 8 * scale),

                    // 닫기 버튼
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: const Color(0xFFEF4565),
                        size: 20 * scale,
                      ),
                      tooltip: '도구 종료',
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSizePreset(String label, double radius, double scale) {
    final isSelected = (_geometry.radius - radius).abs() < 1.0;
    return GestureDetector(
      onTap: () {
        setState(() {
          _geometry = _geometry.copyWith(radius: radius);
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6 * scale),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white24,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 11 * scale,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final SpotlightGeometry geometry;

  _SpotlightPainter({required this.geometry});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: geometry.darkness)
      ..style = PaintingStyle.fill;

    // 전체 화면 패스 생성
    final screenPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // 스포트라이트 원형 구멍 패스
    final holePath = Path()
      ..addOval(
        Rect.fromCircle(
          center: geometry.center,
          radius: geometry.radius,
        ),
      );

    // 차집합을 통해 스포트라이트 영역을 투명하게 뚫음
    final resultPath = Path.combine(PathOperation.difference, screenPath, holePath);
    canvas.drawPath(resultPath, backgroundPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.geometry.center != geometry.center ||
        oldDelegate.geometry.radius != geometry.radius ||
        oldDelegate.geometry.darkness != geometry.darkness ||
        oldDelegate.geometry.isMagnifier != geometry.isMagnifier;
  }
}

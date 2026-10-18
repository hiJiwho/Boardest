import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NoiseMeterModal extends StatefulWidget {
  const NoiseMeterModal({super.key});

  @override
  State<NoiseMeterModal> createState() => _NoiseMeterModalState();
}

class _NoiseMeterModalState extends State<NoiseMeterModal> {
  double _decibels = 42.0;
  String _mode = '자습'; // 자습, 모둠, 발표
  double _threshold = 50.0;
  bool _alertActive = false;
  bool _isMonitoring = true;

  final List<double> _history = List.generate(24, (_) => 35.0);

  @override
  void initState() {
    super.initState();
    _simulateDecibels();
  }

  void _simulateDecibels() async {
    while (mounted && _isMonitoring) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) break;

      setState(() {
        double base = 32.0;
        double variance = 8.0;
        if (_mode == '자습') {
          base = 32.0;
          variance = 8.0;
        } else if (_mode == '모둠') {
          base = 65.0;
          variance = 20.0;
        } else if (_mode == '발표') {
          base = 45.0;
          variance = 15.0;
        }

        double roll = DateTime.now().millisecond / 1000.0;
        _decibels = base + (roll * variance);

        if (roll > 0.92) {
          _decibels += 15.0;
        }

        _alertActive = _decibels > _threshold;

        _history.removeAt(0);
        _history.add(_decibels);
      });
    }
  }

  @override
  void dispose() {
    _isMonitoring = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0E17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: _alertActive
              ? const Color(0xFFEF4565)
              : const Color(0xFF2EC4B6).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.volume_up_rounded,
                color: _alertActive
                    ? const Color(0xFFEF4565)
                    : const Color(0xFF00F5D4),
              ),
              const SizedBox(width: 10),
              Text(
                '교실 소음 측정기',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _alertActive
                  ? const Color(0xFFEF4565).withValues(alpha: 0.15)
                  : const Color(0xFF2EC4B6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _alertActive ? '경고: 소음 초과!' : '정상 수치',
              style: GoogleFonts.notoSansKr(
                color: _alertActive
                    ? const Color(0xFFEF4565)
                    : const Color(0xFF00F5D4),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildModeTab('자습', '🤫 자습 시간'),
                _buildModeTab('발표', '📢 발표 시간'),
                _buildModeTab('모둠', '🗣️ 모둠 활동'),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              height: 140,
              width: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF16161A),
                border: Border.all(
                  color: _alertActive
                      ? const Color(0xFFEF4565)
                      : const Color(0xFF2EC4B6),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (_alertActive
                                ? const Color(0xFFEF4565)
                                : const Color(0xFF2EC4B6))
                            .withValues(alpha: 0.2),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _decibels.toStringAsFixed(1),
                    style: GoogleFonts.outfit(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: _alertActive
                          ? const Color(0xFFEF4565)
                          : Colors.white,
                    ),
                  ),
                  Text(
                    'dB',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  '경고 임계치: ${_threshold.toInt()} dB',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF2EC4B6),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: const Color(0xFF00F5D4),
                      overlayColor: const Color(
                        0xFF00F5D4,
                      ).withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _threshold,
                      min: 40,
                      max: 90,
                      onChanged: (val) {
                        setState(() {
                          _threshold = val;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 60,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF16161A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _history.map((dbVal) {
                  final double h = 5 + ((dbVal - 30) / 60) * 40;
                  final clampedH = h.clamp(5.0, 48.0);
                  final isOver = dbVal > _threshold;

                  return Container(
                    width: 10,
                    height: clampedH,
                    decoration: BoxDecoration(
                      color: isOver
                          ? const Color(0xFFEF4565)
                          : const Color(0xFF2CB67D),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '닫기',
            style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2)),
          ),
        ),
      ],
    );
  }

  Widget _buildModeTab(String targetMode, String label) {
    final isSelected = _mode == targetMode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _mode = targetMode;
          if (targetMode == '자습') _threshold = 50.0;
          if (targetMode == '발표') _threshold = 60.0;
          if (targetMode == '모둠') _threshold = 78.0;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2EC4B6).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00F5D4)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            color: isSelected ? const Color(0xFF00F5D4) : Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

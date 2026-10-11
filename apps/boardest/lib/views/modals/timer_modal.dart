import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TimerModal extends StatefulWidget {
  const TimerModal({super.key});

  @override
  State<TimerModal> createState() => _TimerModalState();
}

class _TimerModalState extends State<TimerModal> {
  int _secondsElapsed = 0;
  Timer? _timer;
  bool _isRunning = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() {
        _isRunning = false;
      });
    } else {
      setState(() {
        _isRunning = true;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _secondsElapsed++;
        });
      });
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _secondsElapsed = 0;
      _isRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0E17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: const Color(0xFF2EC4B6).withValues(alpha: 0.3)),
      ),
      title: Row(
        children: [
          const Icon(Icons.timer_rounded, color: Color(0xFF00F5D4)),
          const SizedBox(width: 10),
          Text(
            '타이머 / 스톱워치',
            style: GoogleFonts.notoSansKr(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(_secondsElapsed ~/ 60).toString().padLeft(2, '0')}:${(_secondsElapsed % 60).toString().padLeft(2, '0')}',
            style: GoogleFonts.outfit(
              fontSize: 64,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF00F5D4),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRunning
                      ? Colors.orange
                      : const Color(0xFF2EC4B6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _toggleTimer,
                child: Text(_isRunning ? '일시정지' : '시작'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4565),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _resetTimer,
                child: const Text('초기화'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '닫기',
            style: GoogleFonts.notoSansKr(color: Colors.white60),
          ),
        ),
      ],
    );
  }
}

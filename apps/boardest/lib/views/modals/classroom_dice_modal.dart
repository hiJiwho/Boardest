import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ClassroomDiceModal extends StatefulWidget {
  const ClassroomDiceModal({super.key});

  @override
  State<ClassroomDiceModal> createState() => _ClassroomDiceModalState();
}

class _ClassroomDiceModalState extends State<ClassroomDiceModal> {
  int _diceCount = 1;
  List<int> _diceValues = [1];
  bool _isRolling = false;
  final Random _rng = Random.secure();

  void _rollDice() async {
    if (_isRolling) return;
    setState(() {
      _isRolling = true;
    });

    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      setState(() {
        _diceValues = List.generate(
          _diceCount,
          (_) => _rng.nextInt(6) + 1,
        );
      });
    }

    if (mounted) {
      setState(() {
        _isRolling = false;
      });
    }
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
          const Icon(Icons.casino_rounded, color: Color(0xFF00F5D4)),
          const SizedBox(width: 10),
          Text(
            '수업 주사위',
            style: GoogleFonts.notoSansKr(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [1, 2, 3].map((count) {
              final isSelected = _diceCount == count;
              return GestureDetector(
                onTap: () {
                  if (_isRolling) return;
                  setState(() {
                    _diceCount = count;
                    _diceValues = List.generate(count, (_) => 1);
                  });
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF2EC4B6).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF00F5D4)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    '${count}개',
                    style: GoogleFonts.notoSansKr(
                      color: isSelected
                          ? const Color(0xFF00F5D4)
                          : Colors.white60,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_diceCount, (index) {
              final val = _diceValues[index];
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 12),
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isRolling
                        ? const Color(0xFF00F5D4)
                        : const Color(0xFF2EC4B6).withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_isRolling
                                  ? const Color(0xFF00F5D4)
                                  : const Color(0xFF2EC4B6))
                              .withValues(alpha: _isRolling ? 0.35 : 0.15),
                      blurRadius: _isRolling ? 20 : 10,
                      spreadRadius: _isRolling ? 2 : 0,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '$val',
                  style: GoogleFonts.outfit(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: _isRolling ? const Color(0xFF00F5D4) : Colors.white,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 32),
        ],
      ),
      actionsPadding: const EdgeInsets.only(bottom: 20, right: 20, left: 20),
      actions: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2EC4B6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: _isRolling ? null : _rollDice,
                child: Text(
                  _isRolling ? '주사위 굴리는 중...' : '주사위 던지기 🎲',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardest_teacher/models/lesson_tools.dart';
import 'package:boardest_teacher/widgets/classroom_dice_overlay.dart';
import 'package:boardest_teacher/widgets/spotlight_magnifier_overlay.dart';

void main() {
  group('18 Lesson Tools Suite Unit Tests (M2 / C05 - C07)', () {
    // ────────── 1. LessonTimerEngine (C05: Timer & Stopwatch) ──────────
    test('LessonTimerEngine - countdown state transitions and finish trigger', () {
      bool soundTriggered = false;
      final timer = LessonTimerEngine(
        initialTargetSeconds: 3,
        initialMode: LessonTimerMode.countdown,
        onFinished: () {
          soundTriggered = true;
        },
      );

      expect(timer.mode, equals(LessonTimerMode.countdown));
      expect(timer.remainingSeconds, equals(3));
      expect(timer.isRunning, isFalse);
      expect(timer.hasFinished, isFalse);
      expect(timer.formattedDisplay, equals('00:03'));

      // Start countdown
      timer.start();
      expect(timer.isRunning, isTrue);

      // Tick 1
      timer.tick();
      expect(timer.remainingSeconds, equals(2));
      expect(timer.formattedDisplay, equals('00:02'));

      // Tick 2
      timer.tick();
      expect(timer.remainingSeconds, equals(1));

      // Tick 3: finishes
      timer.tick();
      expect(timer.remainingSeconds, equals(0));
      expect(timer.isRunning, isFalse);
      expect(timer.hasFinished, isTrue);
      expect(soundTriggered, isTrue);

      // Adjust seconds (+60)
      timer.adjustSeconds(60);
      expect(timer.remainingSeconds, equals(60));
      expect(timer.hasFinished, isFalse);

      // Reset
      timer.reset();
      expect(timer.remainingSeconds, equals(60));
      expect(timer.isRunning, isFalse);
    });

    test('LessonTimerEngine - stopwatch mode count up', () {
      final timer = LessonTimerEngine(
        initialTargetSeconds: 300,
        initialMode: LessonTimerMode.stopwatch,
      );

      expect(timer.mode, equals(LessonTimerMode.stopwatch));
      expect(timer.elapsedSeconds, equals(0));

      timer.start();
      for (int i = 0; i < 65; i++) {
        timer.tick();
      }
      expect(timer.elapsedSeconds, equals(65));
      expect(timer.formattedDisplay, equals('01:05'));

      timer.pause();
      expect(timer.isRunning, isFalse);
      expect(timer.elapsedSeconds, equals(65));

      timer.reset();
      expect(timer.elapsedSeconds, equals(0));
    });

    // ────────── 2. LessonDiceEngine (C06: Cryptographic Dice) ──────────
    test('LessonDiceEngine - fair bounds and cryptographic randomness', () {
      final engine = LessonDiceEngine();
      engine.setDiceCount(3);
      expect(engine.diceCount, equals(3));

      for (int roll = 0; roll < 100; roll++) {
        final result = engine.rollImmediate();
        expect(result.length, equals(3));
        for (final val in result) {
          expect(val >= 1 && val <= 6, isTrue);
        }
        expect(engine.sum, equals(result.fold<int>(0, (a, b) => a + b)));
      }

      expect(engine.history.isNotEmpty, isTrue);
      expect(engine.history.first.values.length, equals(3));
    });

    test('LessonDiceEngine - rollWithAnimation produces valid outcome', () async {
      final engine = LessonDiceEngine();
      engine.setDiceCount(2);

      final outcome = await engine.rollWithAnimation(steps: 3, interval: const Duration(milliseconds: 5));
      expect(outcome.length, equals(2));
      expect(outcome[0] >= 1 && outcome[0] <= 6, isTrue);
      expect(outcome[1] >= 1 && outcome[1] <= 6, isTrue);
      expect(engine.isRolling, isFalse);
    });

    // ────────── 3. StudentPickerEngine (C06: Repeat Prevention) ──────────
    test('StudentPickerEngine - avoids repeats until full reset cycle', () {
      const total = 10;
      final picker = StudentPickerEngine(total: total);
      expect(picker.totalStudents, equals(total));
      expect(picker.remainingCount, equals(total));

      final drawnOrder = <int>[];

      // Draw all 10 students
      for (int i = 0; i < total; i++) {
        expect(picker.isCycleComplete, isFalse);
        final winner = picker.drawImmediate();
        expect(winner >= 1 && winner <= total, isTrue);
        expect(drawnOrder.contains(winner), isFalse, reason: 'Must not repeat student in same cycle');
        drawnOrder.add(winner);
        expect(picker.remainingCount, equals(total - (i + 1)));
      }

      expect(drawnOrder.length, equals(total));
      expect(drawnOrder.toSet().length, equals(total), reason: 'Every student was drawn exactly once');
      expect(picker.isCycleComplete, isTrue);

      // Drawing again starts a new cycle cleanly
      final nextWinner = picker.drawImmediate();
      expect(nextWinner >= 1 && nextWinner <= total, isTrue);
      expect(picker.pickedStudents.length, equals(1));
    });

    test('StudentPickerEngine - drawWithAnimation completes and avoids duplicates', () async {
      final picker = StudentPickerEngine(total: 5);
      final w1 = await picker.drawWithAnimation(steps: 2, interval: const Duration(milliseconds: 5));
      final w2 = await picker.drawWithAnimation(steps: 2, interval: const Duration(milliseconds: 5));

      expect(w1, isNotNull);
      expect(w2, isNotNull);
      expect(w1, isNot(equals(w2)));
      expect(picker.pickedStudents.contains(w1), isTrue);
      expect(picker.pickedStudents.contains(w2), isTrue);
    });

    // ────────── 4. SpotlightGeometry (C07: Spotlight & Magnifier) ──────────
    test('SpotlightGeometry - radial focus boundary and magnifier mode', () {
      const geo = SpotlightGeometry(
        center: Offset(500, 300),
        radius: 100.0,
        darkness: 0.8,
        isMagnifier: false,
        magnification: 2.0,
      );

      // Points strictly inside
      expect(geo.isInside(const Offset(500, 300)), isTrue);
      expect(geo.isInside(const Offset(550, 350)), isTrue);
      expect(geo.isInside(const Offset(600, 300)), isTrue);

      // Points outside
      expect(geo.isInside(const Offset(601, 300)), isFalse);
      expect(geo.isInside(const Offset(0, 0)), isFalse);

      // Mode toggling
      final magnifier = geo.copyWith(isMagnifier: true, magnification: 2.5);
      expect(magnifier.isMagnifier, isTrue);
      expect(magnifier.magnification, equals(2.5));
      expect(magnifier.center, equals(const Offset(500, 300)));
    });
  });

  group('Lesson Tools Widget Verification Tests', () {
    testWidgets('ClassroomDiceOverlay renders and updates dice count', (tester) async {
      bool closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ClassroomDiceOverlay(
                  scale: 1.0,
                  initialOffset: const Offset(100, 100),
                  onClose: () => closed = true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('수업 주사위 (암호학적 RNG)'), findsOneWidget);
      expect(find.text('주사위 굴리기 🎲'), findsOneWidget);
      expect(find.text('1개'), findsOneWidget);
      expect(find.text('2개'), findsOneWidget);

      // Switch to 2 dice
      await tester.tap(find.text('2개'));
      await tester.pump();
      expect(find.text('2개'), findsOneWidget);

      // Tap close button
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('SpotlightMagnifierOverlay renders custom mask and switches mode', (tester) async {
      bool closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotlightMagnifierOverlay(
              scale: 1.0,
              onClose: () => closed = true,
              initialCenter: const Offset(200, 200),
              initialRadius: 100.0,
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('소'), findsOneWidget);
      expect(find.text('중'), findsOneWidget);
      expect(find.text('대'), findsOneWidget);

      // Switch mode to Magnifier
      final modeBtn = find.byTooltip('돋보기 모드로 전환');
      expect(modeBtn, findsOneWidget);
      await tester.tap(modeBtn);
      await tester.pump();

      expect(find.textContaining('돋보기'), findsOneWidget);

      // Tap close button
      await tester.tap(find.byTooltip('도구 종료'));
      await tester.pump();
      expect(closed, isTrue);
    });
  });
}

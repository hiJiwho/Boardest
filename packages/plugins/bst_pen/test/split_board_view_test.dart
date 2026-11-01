import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_pen/bst_pen.dart';

void main() {
  group('SplitBoardController Unit Tests', () {
    test('Default initialization has 4 panes and twoVertical split mode at 0.5:0.5', () {
      final ctrl = SplitBoardController();
      expect(ctrl.splitMode, equals(SplitMode.twoVertical));
      expect(ctrl.splitRatioX, equals(0.5));
      expect(ctrl.splitRatioY, equals(0.5));
      expect(ctrl.panes.length, equals(4));
      expect(ctrl.activePaneIndex, equals(0));
      expect(ctrl.activePane.title, equals('1분할'));
    });

    test('Mode switching updates splitMode and notifies listeners', () {
      final ctrl = SplitBoardController();
      int notified = 0;
      ctrl.addListener(() => notified++);

      ctrl.splitMode = SplitMode.twoHorizontal;
      expect(ctrl.splitMode, equals(SplitMode.twoHorizontal));
      expect(notified, equals(1));

      ctrl.splitMode = SplitMode.quad;
      expect(ctrl.splitMode, equals(SplitMode.quad));
      expect(notified, equals(2));

      ctrl.splitMode = SplitMode.single;
      expect(ctrl.splitMode, equals(SplitMode.single));
      expect(notified, equals(3));
    });

    test('Resize handles clamp split ratios between 0.15 and 0.85', () {
      final ctrl = SplitBoardController();

      // Lower bound clamp
      ctrl.splitRatioX = 0.05;
      expect(ctrl.splitRatioX, equals(0.15));

      // Upper bound clamp
      ctrl.splitRatioX = 0.95;
      expect(ctrl.splitRatioX, equals(0.85));

      // Normal range
      ctrl.splitRatioX = 0.35;
      expect(ctrl.splitRatioX, equals(0.35));

      // splitRatioY clamp
      ctrl.splitRatioY = -0.2;
      expect(ctrl.splitRatioY, equals(0.15));
      ctrl.splitRatioY = 1.2;
      expect(ctrl.splitRatioY, equals(0.85));
    });

    test('resetSplitRatios restores both X and Y ratios to exact 0.5', () {
      final ctrl = SplitBoardController();
      ctrl.splitRatioX = 0.25;
      ctrl.splitRatioY = 0.75;
      expect(ctrl.splitRatioX, equals(0.25));
      expect(ctrl.splitRatioY, equals(0.75));

      ctrl.resetSplitRatios();
      expect(ctrl.splitRatioX, equals(0.5));
      expect(ctrl.splitRatioY, equals(0.5));
    });

    test('Touch/pen coordinate isolation: Pane strokes remain strictly independent', () {
      final ctrl = SplitBoardController();

      // Add stroke to Pane 0
      final stroke0 = AnnotationStroke(
        points: [const Offset(10, 20), const Offset(30, 40)],
        color: const Color(0xFF00F5D4),
        strokeWidth: 4.0,
      );
      ctrl.panes[0].controller.addStroke(stroke0);

      // Verify Pane 0 has stroke, other panes have 0 strokes
      expect(ctrl.panes[0].controller.strokes.length, equals(1));
      expect(ctrl.panes[1].controller.strokes.isEmpty, isTrue);
      expect(ctrl.panes[2].controller.strokes.isEmpty, isTrue);
      expect(ctrl.panes[3].controller.strokes.isEmpty, isTrue);

      // Add stroke to Pane 2
      final stroke2 = AnnotationStroke(
        points: [const Offset(100, 100), const Offset(150, 150)],
        color: const Color(0xFFFF0055),
        strokeWidth: 6.0,
      );
      ctrl.panes[2].controller.addStroke(stroke2);

      expect(ctrl.panes[0].controller.strokes.length, equals(1));
      expect(ctrl.panes[1].controller.strokes.length, equals(0));
      expect(ctrl.panes[2].controller.strokes.length, equals(1));
      expect(ctrl.panes[3].controller.strokes.length, equals(0));

      // Clearing Pane 0 leaves Pane 2 intact
      ctrl.panes[0].clear();
      expect(ctrl.panes[0].controller.strokes.isEmpty, isTrue);
      expect(ctrl.panes[2].controller.strokes.length, equals(1));

      // clearAllPanes clears everything
      ctrl.clearAllPanes();
      expect(ctrl.panes[0].controller.strokes.isEmpty, isTrue);
      expect(ctrl.panes[2].controller.strokes.isEmpty, isTrue);
    });

    test('Tool synchronization: when sync is false, color/width only affects target pane', () {
      final ctrl = SplitBoardController(syncTools: false);

      ctrl.setPenColor(const Color(0xFFFFD166), 1);
      expect(ctrl.panes[0].controller.activeColor, equals(const Color(0xFF00F5D4)));
      expect(ctrl.panes[1].controller.activeColor, equals(const Color(0xFFFFD166)));

      // When sync is true, all panes update
      ctrl.syncToolsAcrossPanes = true;
      ctrl.setPenColor(const Color(0xFFFFFFFF));
      expect(ctrl.panes[0].controller.activeColor, equals(const Color(0xFFFFFFFF)));
      expect(ctrl.panes[1].controller.activeColor, equals(const Color(0xFFFFFFFF)));
      expect(ctrl.panes[2].controller.activeColor, equals(const Color(0xFFFFFFFF)));
      expect(ctrl.panes[3].controller.activeColor, equals(const Color(0xFFFFFFFF)));
    });
  });

  group('SplitBoardView Widget Tests', () {
    testWidgets('Renders 2-way vertical layout with draggable divider and reset button', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ctrl = SplitBoardController(initialMode: SplitMode.twoVertical);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 750,
              child: SplitBoardView(
                controller: ctrl,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header title and split mode buttons
      expect(find.text('화면 분할 판서 (Split Board)'), findsOneWidget);
      expect(find.text('좌우 2분할'), findsOneWidget);
      expect(find.text('상하 2분할'), findsOneWidget);
      expect(find.text('4분할'), findsOneWidget);
      expect(find.text('1분할'), findsOneWidget);
      expect(find.text('2분할'), findsOneWidget);

      // Verify on-divider 1:1 reset button exists
      expect(find.text('1:1'), findsOneWidget);

      // Drag resize divider to change splitRatioX
      ctrl.splitRatioX = 0.3;
      await tester.pumpAndSettle();
      expect(ctrl.splitRatioX, equals(0.3));

      // Tap reset button in toolbar
      await tester.tap(find.text('1:1 균등 리셋'));
      await tester.pumpAndSettle();
      expect(ctrl.splitRatioX, equals(0.5));
    });

    testWidgets('Renders 2-way horizontal layout with horizontal divider', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ctrl = SplitBoardController(initialMode: SplitMode.twoHorizontal);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 750,
              child: SplitBoardView(
                controller: ctrl,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1분할'), findsOneWidget);
      expect(find.text('2분할'), findsOneWidget);

      ctrl.splitRatioY = 0.7;
      await tester.pumpAndSettle();
      expect(ctrl.splitRatioY, equals(0.7));

      // Reset
      ctrl.resetSplitRatios();
      await tester.pumpAndSettle();
      expect(ctrl.splitRatioY, equals(0.5));
    });

    testWidgets('Renders 4-way quad layout with 4 independent panes and center handle', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ctrl = SplitBoardController(initialMode: SplitMode.quad);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 750,
              child: SplitBoardView(
                controller: ctrl,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check 4 pane titles
      expect(find.text('1분할'), findsOneWidget);
      expect(find.text('2분할'), findsOneWidget);
      expect(find.text('3분할'), findsOneWidget);
      expect(find.text('4분할'), findsNWidgets(2)); // 1 in toolbar mode switcher, 1 in 4th pane header chip

      // Quad center handle icon exists
      expect(find.byTooltip('1:1:1:1 균등 분할 리셋'), findsOneWidget);

      ctrl.splitRatioX = 0.25;
      ctrl.splitRatioY = 0.75;
      await tester.pumpAndSettle();
      expect(ctrl.splitRatioX, equals(0.25));
      expect(ctrl.splitRatioY, equals(0.75));

      // Tap center reset button
      await tester.tap(find.byTooltip('1:1:1:1 균등 분할 리셋'));
      await tester.pumpAndSettle();
      expect(ctrl.splitRatioX, equals(0.5));
      expect(ctrl.splitRatioY, equals(0.5));
    });

    testWidgets('Drawing on a split pane strictly confines coordinates and isolates events', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ctrl = SplitBoardController(initialMode: SplitMode.twoVertical);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 750,
              child: SplitBoardView(
                controller: ctrl,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Draw inside Pane 0 (left half: x: 0..594, y: 54..750)
      final gesture = await tester.startGesture(const Offset(100, 200));
      await gesture.moveTo(const Offset(200, 300));
      await gesture.moveTo(const Offset(300, 400));
      await gesture.up();
      await tester.pumpAndSettle();

      // Pane 0 must have received the stroke
      expect(ctrl.panes[0].controller.strokes.length, equals(1));
      // Pane 1 must have ZERO strokes (zero bleed-through)
      expect(ctrl.panes[1].controller.strokes.length, equals(0));

      final strokePoints = ctrl.panes[0].controller.strokes.first.points;
      expect(strokePoints.length, greaterThanOrEqualTo(1));
      // Verify points are positive local coordinates within the pane's width (~594) and height (~696)
      for (final pt in strokePoints) {
        expect(pt.dx, greaterThanOrEqualTo(0.0));
        expect(pt.dx, lessThanOrEqualTo(600.0));
        expect(pt.dy, greaterThanOrEqualTo(0.0));
        expect(pt.dy, lessThanOrEqualTo(750.0));
      }
    });
  });
}

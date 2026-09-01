import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_pen/bst_pen.dart';

void main() {
  group('AnnotationStroke & BstPenData Adversarial & Edge Case Tests', () {
    test('Mixed coordinate keys {dx, dy} vs {x, y} and corrupt point payload resilience', () {
      final json = {
        'points': [
          {'dx': 10.5, 'dy': 20.5},
          {'x': 30.0, 'y': 40.0},
          {'dx': 50.0, 'y': 60.0}, // Mixed keys
          {'x': 70.0, 'dy': 80.0}, // Mixed keys
          {}, // Missing keys -> fallback (0.0, 0.0)
          'corrupted_entry', // Non-map item -> fallback Offset.zero
          null, // Null item -> fallback Offset.zero
        ],
        'color': 0xFFFF0000,
        'strokeWidth': 5.5,
        'isEraser': false,
      };

      final stroke = AnnotationStroke.fromJson(json);
      expect(stroke.points.length, equals(7));
      expect(stroke.points[0], equals(const Offset(10.5, 20.5)));
      expect(stroke.points[1], equals(const Offset(30.0, 40.0)));
      expect(stroke.points[2], equals(const Offset(50.0, 60.0)));
      expect(stroke.points[3], equals(const Offset(70.0, 80.0)));
      expect(stroke.points[4], equals(Offset.zero));
      expect(stroke.points[5], equals(Offset.zero));
      expect(stroke.points[6], equals(Offset.zero));
      expect(stroke.color.value, equals(0xFFFF0000));
      expect(stroke.strokeWidth, equals(5.5));
      expect(stroke.isEraser, isFalse);

      // Roundtrip serialization maintains both {dx, dy, x, y}
      final out = stroke.toJson();
      final pts = out['points'] as List;
      expect((pts[0] as Map)['dx'], equals(10.5));
      expect((pts[0] as Map)['x'], equals(10.5));
      expect((pts[0] as Map)['dy'], equals(20.5));
      expect((pts[0] as Map)['y'], equals(20.5));
    });

    test('BstPenData handling of corrupted page numbers and null structures', () {
      final corruptJson = {
        'version': 2,
        'totalPages': 3,
        'pages': {
          '0': [
            {
              'points': [{'dx': 1.0, 'dy': 2.0}],
              'color': 0xFFFFFFFF,
              'strokeWidth': 2.0,
            }
          ],
          'invalid_key': [
            {
              'points': [{'x': 5.0, 'y': 10.0}],
            }
          ],
          '-1': [
            {
              'points': [{'dx': 10.0, 'dy': 20.0}],
            }
          ],
        }
      };

      final penData = BstPenData.fromJson(corruptJson);
      // Valid integer keys (0 and -1) are parsed; non-integer 'invalid_key' is ignored
      expect(penData.pages.containsKey(0), isTrue);
      expect(penData.pages.containsKey(-1), isTrue);
      expect(penData.pages.length, equals(2));
      expect(penData.pages[0]!.first.points.first, equals(const Offset(1.0, 2.0)));
    });

    test('AnnotationController Lasso ray-casting algorithm edge cases', () {
      final ctrl = AnnotationController();

      // 1. Degenerate polygons (<3 vertices)
      expect(ctrl.isPointInPolygon(const Offset(10, 10), []), isFalse);
      expect(ctrl.isPointInPolygon(const Offset(10, 10), [const Offset(0, 0)]), isFalse);
      expect(ctrl.isPointInPolygon(const Offset(10, 10), [const Offset(0, 0), const Offset(20, 20)]), isFalse);

      // 2. Square polygon: (0,0) -> (100,0) -> (100,100) -> (0,100)
      final square = [
        const Offset(0, 0),
        const Offset(100, 0),
        const Offset(100, 100),
        const Offset(0, 100),
      ];

      // Inside point
      expect(ctrl.isPointInPolygon(const Offset(50, 50), square), isTrue);
      // Outside point
      expect(ctrl.isPointInPolygon(const Offset(150, 50), square), isFalse);
      expect(ctrl.isPointInPolygon(const Offset(-10, 50), square), isFalse);
      expect(ctrl.isPointInPolygon(const Offset(50, -10), square), isFalse);
      expect(ctrl.isPointInPolygon(const Offset(50, 110), square), isFalse);
    });

    test('AnnotationController undo history capping at 30 items', () {
      final ctrl = AnnotationController();

      // Add 40 strokes and verify undo does not crash and respects stack depth
      for (int i = 0; i < 40; i++) {
        ctrl.addStroke(AnnotationStroke(
          points: [Offset(i.toDouble(), i.toDouble())],
          color: const Color(0xFF000000),
          strokeWidth: 2.0,
        ));
      }
      expect(ctrl.strokes.length, equals(40));

      // Undo 30 times
      for (int i = 0; i < 30; i++) {
        ctrl.undo();
      }
      // After 30 undos, history reaches initial state recorded (10 items remaining)
      expect(ctrl.strokes.length, equals(10));

      // Undoing when history is exhausted does not throw or mutate
      ctrl.undo();
      expect(ctrl.strokes.length, equals(10));
    });

    test('Eraser splitting logic on multi-point polyline', () {
      final ctrl = AnnotationController();
      // Polyline from (0,0) to (100,0) with 11 points
      final points = List.generate(11, (i) => Offset(i * 10.0, 0));
      ctrl.addStroke(AnnotationStroke(
        points: points,
        color: const Color(0xFFFFFFFF),
        strokeWidth: 4.0,
      ));

      expect(ctrl.strokes.length, equals(1));
      expect(ctrl.strokes.first.points.length, equals(11));

      // Erase at center (50, 0) with radius 15.0
      ctrl.eraserSize = 15.0;
      ctrl.eraseEntireStroke = false;
      ctrl.eraseAt(const Offset(50, 0));

      // The stroke should be split into 2 separate segments
      expect(ctrl.strokes.length, equals(2));
      // First segment ends before 50 - 15 = 35
      expect(ctrl.strokes[0].points.last.dx, lessThanOrEqualTo(40.0));
      // Second segment starts after 50 + 15 = 65
      expect(ctrl.strokes[1].points.first.dx, greaterThanOrEqualTo(60.0));
    });

    test('dragSelectedStrokes resilience against out-of-bound indices', () {
      final ctrl = AnnotationController();
      ctrl.addStroke(AnnotationStroke(
        points: [const Offset(10, 10)],
        color: const Color(0xFFFFFFFF),
        strokeWidth: 2.0,
      ));

      // Artificially inject out-of-bound selected index
      ctrl.selectedStrokeIndices = [0, 999]; // 999 is out of bounds
      // Should not throw IndexOutOfBoundsException
      ctrl.dragSelectedStrokes(const Offset(5, 5));
      expect(ctrl.strokes[0].points[0], equals(const Offset(15, 15)));
    });
  });
}

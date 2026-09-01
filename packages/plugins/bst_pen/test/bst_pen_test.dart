import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_pen/bst_pen.dart';

void main() {
  group('AnnotationStroke Coordinate Interoperability Tests', () {
    test('AnnotationStroke serializes points with both {dx, dy} and {x, y}', () {
      final stroke = AnnotationStroke(
        points: const [Offset(10.5, 20.5), Offset(30.0, 40.0)],
        color: const Color(0xFFFF0000),
        strokeWidth: 4.0,
        isEraser: false,
      );

      final json = stroke.toJson();
      expect(json['points'], isA<List>());
      final p0 = (json['points'] as List)[0] as Map<String, dynamic>;
      expect(p0['dx'], 10.5);
      expect(p0['dy'], 20.5);
      expect(p0['x'], 10.5);
      expect(p0['y'], 20.5);
      expect(json['color'], const Color(0xFFFF0000).value);
      expect(json['strokeWidth'], 4.0);
      expect(json['isEraser'], isFalse);
    });

    test('AnnotationStroke deserializes legacy {x, y} coordinates', () {
      final legacyJson = {
        'points': [
          {'x': 50.0, 'y': 100.0},
          {'x': 60.0, 'y': 110.0},
        ],
        'color': 0xFF00FF00,
        'strokeWidth': 2.5,
        'isEraser': true,
      };

      final stroke = AnnotationStroke.fromJson(legacyJson);
      expect(stroke.points.length, 2);
      expect(stroke.points[0].dx, 50.0);
      expect(stroke.points[0].dy, 100.0);
      expect(stroke.color, const Color(0xFF00FF00));
      expect(stroke.strokeWidth, 2.5);
      expect(stroke.isEraser, isTrue);
    });

    test('AnnotationStroke deserializes standard {dx, dy} coordinates', () {
      final standardJson = {
        'points': [
          {'dx': 12.0, 'dy': 34.0},
        ],
        'color': 0xFF0000FF,
        'strokeWidth': 5.0,
      };

      final stroke = AnnotationStroke.fromJson(standardJson);
      expect(stroke.points.length, 1);
      expect(stroke.points[0].dx, 12.0);
      expect(stroke.points[0].dy, 34.0);
      expect(stroke.color, const Color(0xFF0000FF));
    });

    test('AnnotationStroke.translate shifts coordinates correctly', () {
      final stroke = AnnotationStroke(
        points: const [Offset(10, 20)],
        color: const Color(0xFF000000),
        strokeWidth: 2.0,
      );

      final translated = stroke.translate(const Offset(5, -10));
      expect(translated.points[0].dx, 15);
      expect(translated.points[0].dy, 10);
    });
  });

  group('BstPenData Serialization and Compatibility Tests', () {
    test('BstPenData parses pages with both legacy and new coordinate formats', () {
      final penJson = {
        'version': 2,
        'strokesOnly': true,
        'totalPages': 3,
        'pages': {
          '1': [
            {
              'points': [{'x': 10.0, 'y': 20.0}],
              'color': 0xFFFFFFFF,
              'strokeWidth': 3.0,
            }
          ],
          '2': [
            {
              'points': [{'dx': 30.0, 'dy': 40.0}],
              'color': 0xFFFF0000,
              'strokeWidth': 6.0,
            }
          ]
        }
      };

      final bstPenData = BstPenData.fromJson(penJson);
      expect(bstPenData.totalPages, 3);
      expect(bstPenData.pages.containsKey(1), isTrue);
      expect(bstPenData.pages.containsKey(2), isTrue);

      final page1Stroke = bstPenData.pages[1]!.first;
      expect(page1Stroke.points.first.dx, 10.0);
      expect(page1Stroke.points.first.dy, 20.0);

      final page2Stroke = bstPenData.pages[2]!.first;
      expect(page2Stroke.points.first.dx, 30.0);
      expect(page2Stroke.points.first.dy, 40.0);

      final serialized = bstPenData.toJson();
      expect(serialized['version'], 2);
      expect(serialized['pages']['1'], isNotNull);
      expect(serialized['pages']['2'], isNotNull);
    });
  });
}

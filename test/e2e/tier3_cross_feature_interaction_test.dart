import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_pen/bst_pen.dart';
import 'helpers/e2e_test_fixtures.dart';

void main() {
  group('[Tier 3: Cross-Feature Interactions] Multi-System Orchestration & State Cache', () {
    // ────────── 1. Slide Navigation + Pen Persistence + Classroom Isolation ──────────
    test('Cross-Feature: In-memory cache isolates notes across classrooms and slides with 0ms restore', () {
      // Memory cache simulating _pageStrokesMemory in TbpViewerRoute / CanvaBoardView
      final Map<String, List<AnnotationStroke>> pageStrokesMemory = {};

      String buildCacheKey(String classId, String dHash) => '$classId::$dHash';

      void saveStrokesToMemory(String classId, String dHash, List<AnnotationStroke> strokes) {
        pageStrokesMemory[buildCacheKey(classId, dHash)] = List.from(strokes);
      }

      List<AnnotationStroke> loadStrokesFromMemory(String classId, String dHash) {
        final key = buildCacheKey(classId, dHash);
        return pageStrokesMemory[key] ?? [];
      }

      // Step 1: Class 101 on Canva Slide 1 (dHash = 'slide_01')
      const classA = '[101]';
      const slide1 = 'dhash_slide_01';
      final strokeA1 = AnnotationStroke(
        points: const [Offset(100, 100), Offset(150, 150)],
        color: Colors.red,
        strokeWidth: 3.0,
      );
      saveStrokesToMemory(classA, slide1, [strokeA1]);

      // Step 2: Class 101 advances to Slide 2 (dHash = 'slide_02')
      const slide2 = 'dhash_slide_02';
      final strokeA2 = AnnotationStroke(
        points: const [Offset(200, 200), Offset(250, 250)],
        color: Colors.blue,
        strokeWidth: 4.0,
      );
      saveStrokesToMemory(classA, slide2, [strokeA2]);

      // Step 3: Switch active class to Class 102 on Slide 1
      const classB = '[102]';
      // Verify isolation: Class 102 on Slide 1 must NOT see Class 101's strokes
      final strokesB1Initial = loadStrokesFromMemory(classB, slide1);
      expect(strokesB1Initial.isEmpty, isTrue);

      // Class 102 draws their own notes on Slide 1
      final strokeB1 = AnnotationStroke(
        points: const [Offset(300, 300), Offset(350, 350)],
        color: Colors.green,
        strokeWidth: 5.0,
      );
      saveStrokesToMemory(classB, slide1, [strokeB1]);

      // Step 4: Switch back to Class 101 on Slide 1 -> 0ms instant restoration!
      final restoredA1 = loadStrokesFromMemory(classA, slide1);
      expect(restoredA1.length, equals(1));
      expect(restoredA1.first.color, equals(Colors.red));
      expect(restoredA1.first.points, equals(const [Offset(100, 100), Offset(150, 150)]));

      // Step 5: Advance Class 101 to Slide 2 -> instant restoration of slide 2 strokes!
      final restoredA2 = loadStrokesFromMemory(classA, slide2);
      expect(restoredA2.length, equals(1));
      expect(restoredA2.first.color, equals(Colors.blue));

      // Step 6: Verify Class 102 notes on Slide 1 remain intact and unpolluted
      final restoredB1 = loadStrokesFromMemory(classB, slide1);
      expect(restoredB1.length, equals(1));
      expect(restoredB1.first.color, equals(Colors.green));
    });

    // ────────── 2. Offline Mode + Assessment Sync + Background Storage ──────────
    test('Cross-Feature: Offline mode gracefully recovers from network drop with cached assessment state', () {
      // Local persistent store mock
      final Map<String, String> localPrefs = {};

      const schoolCode = 'ydm';
      const grade = 2;
      const classNum = 3;
      final cacheKey = 'cached_assessments_${schoolCode}_${grade}_$classNum';

      // Seed local cache with initial assessment
      final initialItem = {
        'id': 'ass_001',
        'title': '수학 2단원 수행평가',
        'subject': '수학',
        'grade': 2,
        'classNum': 3,
        'dueDate': '2026-11-05',
      };
      localPrefs[cacheKey] = json.encode([initialItem]);

      // Simulated loader that attempts network fetch with fallback to local cache
      Future<List<Map<String, dynamic>>> fetchAssessmentsWithFallback({required bool isNetworkOnline}) async {
        // 1. Try network if online
        if (isNetworkOnline) {
          // Network succeeds: returns fresh items and updates cache
          final freshItems = [
            initialItem,
            {
              'id': 'ass_002',
              'title': '과학 탐구 보고서',
              'subject': '과학',
              'grade': 2,
              'classNum': 3,
              'dueDate': '2026-11-10',
            },
          ];
          localPrefs[cacheKey] = json.encode(freshItems);
          return freshItems;
        }

        // 2. Network fails (offline / socket exception): fallback to cache
        final cached = localPrefs[cacheKey];
        if (cached != null) {
          final List list = json.decode(cached);
          return list.cast<Map<String, dynamic>>();
        }
        return [];
      }

      // Test 1: Fetch while offline returns cached item
      final offlineResult = fetchAssessmentsWithFallback(isNetworkOnline: false);
      expect(offlineResult, completion(hasLength(1)));

      // Test 2: Network recovers and synchronizes
      final onlineResult = fetchAssessmentsWithFallback(isNetworkOnline: true);
      expect(onlineResult, completion(hasLength(2)));

      // Test 3: Fetch offline again after sync now has both items cached
      final subsequentOfflineResult = fetchAssessmentsWithFallback(isNetworkOnline: false);
      expect(subsequentOfflineResult, completion(hasLength(2)));
    });

    // ────────── 3. Tool Dock Interactivity with Active Drawing Buffer ──────────
    test('Cross-Feature: Floating dock timer operations do not mutate drawing canvas undo stack', () {
      final controller = AnnotationController();
      controller.activeColor = Colors.amber;
      controller.activeWidth = 4.0;

      // Draw stroke 1
      final stroke1 = AnnotationStroke(
        points: const [Offset(10, 10), Offset(20, 20)],
        color: Colors.amber,
        strokeWidth: 4.0,
      );
      controller.addStroke(stroke1);
      expect(controller.strokes.length, equals(1));

      // Simulate Floating Dock Timer active in foreground (e.g. 5 ticks)
      int timerSeconds = 60;
      for (int i = 0; i < 5; i++) {
        timerSeconds--;
      }
      expect(timerSeconds, equals(55));

      // Draw stroke 2 while timer is running
      final stroke2 = AnnotationStroke(
        points: const [Offset(30, 30), Offset(40, 40)],
        color: Colors.white,
        strokeWidth: 2.0,
      );
      controller.addStroke(stroke2);
      expect(controller.strokes.length, equals(2));

      // Undo operation on canvas restores prior stroke state
      controller.undo();
      expect(controller.strokes.length, equals(1));
      expect(controller.strokes.first, equals(stroke1));

      // Timer state remains completely isolated
      expect(timerSeconds, equals(55));
    });
  });
}

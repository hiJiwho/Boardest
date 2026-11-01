import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:bst_pen/bst_pen.dart';
import 'package:bst_tbp/bst_tbp.dart';
import 'helpers/e2e_test_fixtures.dart';

void main() {
  group('[Tier 2: Boundary & Corner Cases] Degenerate Inputs & Fault Stress', () {
    // ────────── 1. Empty/Null/Malformed Hashes ──────────
    test('Degenerate Hashes: handles empty, whitespace, and special characters safely', () {
      // Empty and whitespace dHash
      expect(
        E2ETestFixtures.formatPenFileName(classId: '1반', dHash: ''),
        equals('[1반].pen'),
      );
      expect(
        E2ETestFixtures.formatPenFileName(classId: '1반', dHash: '   '),
        equals('[1반].pen'),
      );

      // Null classId with empty hash
      expect(
        E2ETestFixtures.formatPenFileName(classId: null, dHash: ''),
        equals('기본_.pen'),
      );

      // Key sanitization in TbpStorageService
      expect(TbpStorageService.sanitizeKey(''), equals(''));
      expect(TbpStorageService.sanitizeKey('regular_page_01'), equals('regular_page_01'));

      // Binary string conversion: 32+ bits binary string gets converted to hex
      final binaryKey = '111100001111000011110000111100001111'; // > 32 bits
      final sanitized = TbpStorageService.sanitizeKey(binaryKey);
      expect(sanitized, isNot(equals(binaryKey)));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(sanitized), isTrue);

      // Hamming distance with degenerate inputs
      expect(TbpDhashEngine.hammingDistance('', ''), equals(0));
      expect(TbpDhashEngine.hammingDistance('101', ''), equals(9999));
      expect(TbpDhashEngine.hammingDistance('101', '10101'), equals(9999));
    });

    // ────────── 2. Rapid Page Navigation & Cooldown Throttle ──────────
    test('Rapid Page Turn: 350ms cooldown blocks double-page skipping', () {
      // Navigation throttle state machine
      DateTime? lastNavTime;
      const int cooldownMs = 350;
      int pageNumber = 1;
      int acceptedNavCount = 0;
      int droppedNavCount = 0;

      bool requestNavigateNext(DateTime requestTime) {
        if (lastNavTime != null) {
          final diff = requestTime.difference(lastNavTime!).inMilliseconds;
          if (diff < cooldownMs) {
            droppedNavCount++;
            return false; // Throttled!
          }
        }
        lastNavTime = requestTime;
        pageNumber++;
        acceptedNavCount++;
        return true;
      }

      final baseTime = DateTime(2026, 11, 1, 9, 0, 0);

      // Trigger 1 at 0ms -> Accepted
      expect(requestNavigateNext(baseTime), isTrue);
      expect(pageNumber, equals(2));

      // Trigger 2 at 50ms (ultra-fast burst) -> Dropped!
      expect(requestNavigateNext(baseTime.add(const Duration(milliseconds: 50))), isFalse);
      expect(pageNumber, equals(2));

      // Trigger 3 at 120ms -> Dropped!
      expect(requestNavigateNext(baseTime.add(const Duration(milliseconds: 120))), isFalse);
      expect(pageNumber, equals(2));

      // Trigger 4 at 250ms -> Dropped!
      expect(requestNavigateNext(baseTime.add(const Duration(milliseconds: 250))), isFalse);
      expect(pageNumber, equals(2));

      // Trigger 5 at 360ms (> 350ms cooldown) -> Accepted!
      expect(requestNavigateNext(baseTime.add(const Duration(milliseconds: 360))), isTrue);
      expect(pageNumber, equals(3));

      expect(acceptedNavCount, equals(2));
      expect(droppedNavCount, equals(3));
    });

    // ────────── 3. Coordinate & Canvas Boundary Clamping ──────────
    test('Coordinate Boundaries: handles negative, zero, and extreme coordinates', () {
      // Single dot stroke
      final dotStroke = AnnotationStroke(
        points: const [Offset(500, 300)],
        color: Colors.red,
        strokeWidth: 5.0,
      );
      final dotJson = dotStroke.toJson();
      expect((dotJson['points'] as List).length, equals(1));

      // Negative and out-of-screen coordinates
      final extremeStroke = AnnotationStroke(
        points: const [
          Offset(-500, -200),
          Offset(0, 0),
          Offset(1920, 1080),
          Offset(99999, 88888),
        ],
        color: Colors.green,
        strokeWidth: 2.0,
      );
      final extremeJson = extremeStroke.toJson();
      final restored = AnnotationStroke.fromJson(extremeJson);
      expect(restored.points.length, equals(4));
      expect(restored.points[0], equals(const Offset(-500, -200)));
      expect(restored.points[1], equals(Offset.zero));
      expect(restored.points[3], equals(const Offset(99999, 88888)));

      // SVG export of extreme strokes does not crash or produce invalid tags
      final doc = PenDocument.fromStrokesMap(
        title: 'Boundary Test',
        strokesPages: {
          1: [dotStroke, extremeStroke],
        },
      );
      expect(doc.pages.containsKey(1), isTrue);
      final svg = doc.pages[1]!;
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, isNot(contains('NaN')));
      expect(svg, isNot(contains('Infinity')));
    });

    // ────────── 4. Offline Fallback & Assessment Sync ──────────
    test('Offline & Empty Fallback: installed classes 1~12 protection on empty remote state', () {
      // Installed classes resolver simulator
      List<int> resolveInstalledClasses(Map<String, dynamic>? remoteEatCalls) {
        if (remoteEatCalls == null || remoteEatCalls.isEmpty) {
          // Fallback protection: 1~12 classes available by default
          return List.generate(12, (index) => index + 1);
        }
        final list = <int>[];
        remoteEatCalls.forEach((key, value) {
          final classNum = int.tryParse(key);
          if (classNum != null) list.add(classNum);
        });
        list.sort();
        return list.isEmpty ? List.generate(12, (index) => index + 1) : list;
      }

      // Case 1: remote is null -> 1~12 fallback
      final fallbackNull = resolveInstalledClasses(null);
      expect(fallbackNull.length, equals(12));
      expect(fallbackNull.first, equals(1));
      expect(fallbackNull.last, equals(12));

      // Case 2: remote is empty map -> 1~12 fallback
      final fallbackEmpty = resolveInstalledClasses({});
      expect(fallbackEmpty.length, equals(12));

      // Case 3: remote has active classes -> returns active
      final active = resolveInstalledClasses({'1': true, '3': true, '5': true});
      expect(active, equals([1, 3, 5]));
    });

    // ────────── 5. Corrupted & Malformed Archive Handling ──────────
    test('Malformed Archive: PenArchiveService gracefully rejects corrupted bytes', () {
      // Degenerate 1: Empty byte array yields default blank document
      final emptyResult = PenArchiveService.instance.unpackFromPenBytes(Uint8List(0));
      expect(emptyResult, isNotNull);
      expect(emptyResult!.title, equals('무제 판서'));
      expect(emptyResult.pages.isEmpty, isTrue);

      // Degenerate 2: Archive containing malformed manifest.json (FormatException) returns null safely
      final malformedArchive = Archive();
      final malformedBytes = utf8.encode('NOT_VALID_JSON{{{');
      malformedArchive.addFile(ArchiveFile.noCompress('manifest.json', malformedBytes.length, malformedBytes));
      final zipWithBadManifest = Uint8List.fromList(ZipEncoder().encode(malformedArchive, level: 0));
      final malformedResult = PenArchiveService.instance.unpackFromPenBytes(zipWithBadManifest);
      expect(malformedResult, isNull);

      // Degenerate 3: Valid ZIP with empty metadata
      final docWithEmptyMeta = PenDocument(
        title: '',
        totalPages: 0,
        createdAt: '',
        updatedAt: '',
        pages: {},
      );
      final bytes = PenArchiveService.instance.packToPenBytes(docWithEmptyMeta);
      final unpacked = PenArchiveService.instance.unpackFromPenBytes(bytes);
      expect(unpacked, isNotNull);
      expect(unpacked!.title, equals('')); // Empty string preserved
      expect(unpacked.totalPages, equals(0));
    });
  });
}

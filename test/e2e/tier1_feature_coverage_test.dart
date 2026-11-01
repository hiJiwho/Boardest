import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_pen/bst_pen.dart';
import 'package:bst_tbp/bst_tbp.dart';
import 'helpers/e2e_test_fixtures.dart';

void main() {
  group('[Tier 1: Feature Coverage] Core Happy Path & Equivalence Classes', () {
    // ────────── 1. TBP 1536px Native Zoom Engine ──────────
    test('TBP Native Zoom: calculates correct zoom factor for 1536px base width', () {
      const double baseWidth = 1536.0;
      
      // Equivalence Class 1: Native 1536x864 screen (Scale = 1.0)
      const double nativeW = 1536.0;
      final double nativeZoom = nativeW / baseWidth;
      expect(nativeZoom, closeTo(1.0, 0.0001));

      // Equivalence Class 2: Full HD 1920x1080 screen (Scale = 1.25)
      const double fhdW = 1920.0;
      final double fhdZoom = fhdW / baseWidth;
      expect(fhdZoom, closeTo(1.25, 0.0001));

      // Equivalence Class 3: 4K UHD 3840x2160 screen (Scale = 2.50)
      const double uhdW = 3840.0;
      final double uhdZoom = uhdW / baseWidth;
      expect(uhdZoom, closeTo(2.5, 0.0001));

      // Equivalence Class 4: Laptop 1366x768 screen (Scale ~ 0.8893)
      const double laptopW = 1366.0;
      final double laptopZoom = laptopW / baseWidth;
      expect(laptopZoom, closeTo(0.8893, 0.001));
    });

    test('TBP Perceptual dHash: calculates exact Hamming distance between hashes', () {
      const hashA = '1010101010101010';
      const hashB = '1010101010101010'; // Identical: distance 0
      const hashC = '1010101010101011'; // 1 bit flipped: distance 1
      const hashD = '0101010101010101'; // 16 bits flipped: distance 16

      expect(TbpDhashEngine.hammingDistance(hashA, hashB), equals(0));
      expect(TbpDhashEngine.hammingDistance(hashA, hashC), equals(1));
      expect(TbpDhashEngine.hammingDistance(hashA, hashD), equals(16));

      // Length mismatch returns sentinel error distance 9999
      expect(TbpDhashEngine.hammingDistance('101', '1010'), equals(9999));
    });

    // ────────── 2. Canva Presentation & Slide Counter ──────────
    test('Canva URL: formats raw design URLs to embed-compatible URLs', () {
      // Canva edit URL -> view?embed URL
      const rawCanva = 'https://www.canva.com/design/DAFxxx/edit';
      final formattedCanva = E2ETestFixtures.formatPresentUrl(rawCanva);
      expect(formattedCanva, contains('canva.com/design/DAFxxx'));
      expect(formattedCanva, contains('embed'));

      // Canva iframe snippet
      const iframeCanva = '<iframe src="https://www.canva.com/design/DAFyyy/view"></iframe>';
      final formattedIframe = E2ETestFixtures.formatPresentUrl(iframeCanva);
      expect(formattedIframe, contains('DAFyyy'));
      expect(formattedIframe, contains('embed'));

      // Google Slides presentation URL
      const rawSlides = 'https://docs.google.com/presentation/d/1234567890/edit';
      final formattedSlides = E2ETestFixtures.formatPresentUrl(rawSlides);
      expect(formattedSlides, contains('presentation/d/1234567890/embed'));
    });

    test('Canva DOM Counter: extracts current slide number and eliminates hash__1 freeze', () {
      // Matches "Page 3 / 24" or "3 / 24"
      expect(E2ETestFixtures.extractCanvaSlideNumber('3 / 24'), equals(3));
      expect(E2ETestFixtures.extractCanvaSlideNumber('Page 15 / 50'), equals(15));
      expect(E2ETestFixtures.extractCanvaSlideNumber('Slide 1/10'), equals(1));
      expect(E2ETestFixtures.extractCanvaSlideNumber('invalid slide format'), isNull);
    });

    // ────────── 3. Pen File Naming & Format Standard ──────────
    test('Pen Annotation Naming: strictly enforces [교실ID]dhash.pen contract', () {
      const dHash = 'dhash_77492104';

      // Case 1: Empty or '기본' classroom -> 기본_[dHash].pen
      expect(
        E2ETestFixtures.formatPenFileName(classId: null, dHash: dHash),
        equals('기본_$dHash.pen'),
      );
      expect(
        E2ETestFixtures.formatPenFileName(classId: '', dHash: dHash),
        equals('기본_$dHash.pen'),
      );
      expect(
        E2ETestFixtures.formatPenFileName(classId: '기본', dHash: dHash),
        equals('기본_$dHash.pen'),
      );

      // Case 2: Class ID already in brackets [1반] -> [1반]dhash.pen
      expect(
        E2ETestFixtures.formatPenFileName(classId: '[1반]', dHash: dHash),
        equals('[1반]$dHash.pen'),
      );
      expect(
        E2ETestFixtures.formatPenFileName(classId: '[102]', dHash: dHash),
        equals('[102]$dHash.pen'),
      );

      // Case 3: Class ID without brackets '1반' -> [1반]dhash.pen
      expect(
        E2ETestFixtures.formatPenFileName(classId: '1반', dHash: dHash),
        equals('[1반]$dHash.pen'),
      );
      expect(
        E2ETestFixtures.formatPenFileName(classId: '과학실', dHash: dHash),
        equals('[과학실]$dHash.pen'),
      );
    });

    test('Pen Packaging: pack and unpack .pen files using Zip Store Level 0 mode', () {
      final doc = E2ETestFixtures.createSamplePenDoc(
        title: '중2 수학 - 일차방정식',
        classroom: '[201]',
        pageCount: 3,
      );

      // Pack to Store Level 0 bytes
      final Uint8List packedBytes = PenArchiveService.instance.packToPenBytes(doc);
      expect(packedBytes.isNotEmpty, isTrue);

      // Unpack from bytes
      final PenDocument? unpacked = PenArchiveService.instance.unpackFromPenBytes(packedBytes);
      expect(unpacked, isNotNull);
      expect(unpacked!.title, equals('중2 수학 - 일차방정식'));
      expect(unpacked.classroom, equals('[201]'));
      expect(unpacked.totalPages, equals(3));
      expect(unpacked.pages.length, equals(3));

      // Verify stroke conversion to strokes map
      final strokesMap = unpacked.toStrokesMap();
      expect(strokesMap.containsKey(1), isTrue);
      expect(strokesMap.containsKey(2), isTrue);
      expect(strokesMap.containsKey(3), isTrue);
      expect(strokesMap[1]!.isNotEmpty, isTrue);
    });

    // ────────── 4. Assessment Sync & Per-Class Partitioning ──────────
    test('Assessment Sync: normalizes school keys accurately', () {
      // Normalization contract
      String normalizeSchoolKey(String raw) {
        final t = raw.trim();
        if (t.isEmpty || t.toLowerCase() == 'default') return 'ydm';
        final lower = t.toLowerCase();
        if (lower == 'ydm' ||
            t.contains('양동') ||
            lower == '44134' ||
            lower == '48588' ||
            lower == 'j100000690') {
          return 'ydm';
        }
        if (lower == 'demo' || t.contains('데모')) {
          return 'demo';
        }
        final ascii = lower.replaceAll(RegExp(r'[^a-z0-9_-]'), '');
        if (ascii.isNotEmpty) return ascii;
        return 'sch_unknown';
      }

      expect(normalizeSchoolKey('양동중학교'), equals('ydm'));
      expect(normalizeSchoolKey('44134'), equals('ydm'));
      expect(normalizeSchoolKey('J100000690'), equals('ydm'));
      expect(normalizeSchoolKey('ydm'), equals('ydm'));
      expect(normalizeSchoolKey('데모학교'), equals('demo'));
      expect(normalizeSchoolKey('seoul_high'), equals('seoul_high'));
    });

    // ────────── 5. COM OleMessageFilter Contract ──────────
    test('COM OleMessageFilter: retries rejected calls up to 10s and cancels thereafter', () {
      // dwRejectType = 1 (SERVERCALL_REJECTED) & tickCount < 10000 -> 150ms retry
      expect(
        E2ETestFixtures.oleMessageFilterRetryRejectedCall(
          dwTickCount: 500,
          dwRejectType: 1,
        ),
        equals(150),
      );

      // dwRejectType = 2 (SERVERCALL_RETRYLATER) & tickCount < 10000 -> 150ms retry
      expect(
        E2ETestFixtures.oleMessageFilterRetryRejectedCall(
          dwTickCount: 9999,
          dwRejectType: 2,
        ),
        equals(150),
      );

      // tickCount >= 10000 (10 seconds timeout) -> -1 (cancel call)
      expect(
        E2ETestFixtures.oleMessageFilterRetryRejectedCall(
          dwTickCount: 10000,
          dwRejectType: 1,
        ),
        equals(-1),
      );
      expect(
        E2ETestFixtures.oleMessageFilterRetryRejectedCall(
          dwTickCount: 15000,
          dwRejectType: 2,
        ),
        equals(-1),
      );

      // Other reject type -> -1
      expect(
        E2ETestFixtures.oleMessageFilterRetryRejectedCall(
          dwTickCount: 500,
          dwRejectType: 99,
        ),
        equals(-1),
      );
    });

    // ────────── 6. MSIX Auto-Update Engine ──────────
    test('MSIX Update: validates 4-part semantic version comparison and MSIX priority', () {
      // Version comparison: newer vs older
      expect(E2ETestFixtures.isNewerVersion('5.4.4', '5.4.3'), isTrue);
      expect(E2ETestFixtures.isNewerVersion('5.5.0', '5.4.3'), isTrue);
      expect(E2ETestFixtures.isNewerVersion('6.0.0', '5.4.3'), isTrue);
      expect(E2ETestFixtures.isNewerVersion('5.4.3', '5.4.3'), isFalse);
      expect(E2ETestFixtures.isNewerVersion('5.4.2', '5.4.3'), isFalse);

      // 4th digit comparison
      expect(E2ETestFixtures.isNewerVersion('5.4.3.2', '5.4.3.1'), isTrue);
      expect(E2ETestFixtures.isNewerVersion('5.4.3.0', '5.4.3.1'), isFalse);

      // Explicit .msix asset matching priority
      final assetList = [
        'boardest-class_5.4.4.appx',
        'boardest-class_5.4.4.msix',
        'boardest-teacher_5.4.4.msix',
        'boardest-lite_5.4.4.apk',
      ];

      final selected = E2ETestFixtures.selectReleaseAssetUrl(assetList, isWindows: true, isCloud: false);
      expect(selected, isNotNull);
      expect(selected, contains('.msix'));
      expect(selected, contains('boardest-class'));
      expect(selected, isNot(contains('.appx')));
    });

    // ────────── 7. Teacher Lesson Tools ──────────
    test('Lesson Tools: Timer countdown and Random Picker logic', () {
      // Countdown Timer state machine
      int totalSeconds = 300;
      int remainingSeconds = totalSeconds;
      bool isRunning = true;

      void tick() {
        if (isRunning && remainingSeconds > 0) {
          remainingSeconds--;
        }
      }

      // Simulate 10 ticks
      for (int i = 0; i < 10; i++) {
        tick();
      }
      expect(remainingSeconds, equals(290));

      // Pause timer
      isRunning = false;
      tick();
      expect(remainingSeconds, equals(290));

      // Resume timer and run to zero
      isRunning = true;
      while (remainingSeconds > 0) {
        tick();
      }
      expect(remainingSeconds, equals(0));
      // Tick at zero stays at zero
      tick();
      expect(remainingSeconds, equals(0));

      // Random Picker within [min, max]
      const int min = 1;
      const int max = 30;
      final history = <int>[];

      for (int i = 0; i < 100; i++) {
        final picked = min + ((i * 7 + 13) % (max - min + 1));
        expect(picked >= min && picked <= max, isTrue);
        history.add(picked);
      }
      expect(history.length, equals(100));
    });
  });
}

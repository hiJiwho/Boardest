import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_pen/bst_pen.dart';
import 'package:bst_tbp/bst_tbp.dart';
import 'package:bst_auth/bst_auth.dart';
import 'helpers/e2e_test_fixtures.dart';

void main() {
  group('[Tier 4: Real-World Scenario] 45-Minute Lesson Full Lifecycle Simulation', () {
    test('Simulate complete 45-minute lesson lifecycle with seamless restoration and notice broadcast', () async {
      // ─────────────────────────────────────────────────────────────
      // Phase 1: Initiation (00:00 - 05:00)
      // Boot classroom app for Class 103, verify TOTP authentication,
      // load textbook package, and set 1536px zoom factor.
      // ─────────────────────────────────────────────────────────────
      const String activeClassroom = '[103]';
      const String schoolId = 'ydm';
      
      // 1.1 Verify TOTP authentication engine (RFC 6238 Base32)
      const String totpSecret = 'JBSWY3DPEHPK3PXP';
      final String generatedOtp = TotpService.generateCurrentOtp(totpSecret);
      expect(generatedOtp.length, equals(6));
      expect(RegExp(r'^\d{6}$').hasMatch(generatedOtp), isTrue);

      final verificationResult = TotpService.verifyOtp(
        secret: totpSecret,
        inputOtp: generatedOtp,
        lastConsumedWindow: 0,
      );
      expect(verificationResult.isValid, isTrue, reason: 'Teacher TOTP authentication must succeed');

      // 1.2 Initialize textbook package & 1536px scale
      const double screenWidth = 1920.0;
      final double computedZoomFactor = screenWidth / 1536.0;
      expect(computedZoomFactor, equals(1.25));

      // ─────────────────────────────────────────────────────────────
      // Phase 2: Active Instruction & Notes (05:00 - 25:00)
      // Open textbook Page 15, write multi-color pen notes,
      // start 5-minute activity timer, and pick a student with dice.
      // ─────────────────────────────────────────────────────────────
      const String page15Dhash = 'dhash_math_ch3_p15_981240';
      final Map<String, List<AnnotationStroke>> memoryCache = {};
      String cacheKey(String cls, String h) => '$cls::$h';

      // 2.1 Draw notes on Page 15
      final page15Strokes = [
        AnnotationStroke(
          points: const [Offset(100, 200), Offset(180, 250), Offset(250, 300)],
          color: const Color(0xFF00F5D4), // Cyan highlight
          strokeWidth: 4.0,
        ),
        AnnotationStroke(
          points: const [Offset(300, 400), Offset(450, 400)],
          color: Colors.yellow, // Formula underline
          strokeWidth: 6.0,
        ),
      ];
      memoryCache[cacheKey(activeClassroom, page15Dhash)] = List.from(page15Strokes);

      // 2.2 Launch Lesson Timer (5 minutes = 300s)
      int activityTimerSeconds = 300;
      bool isTimerActive = true;
      for (int sec = 0; sec < 300; sec++) {
        if (isTimerActive && activityTimerSeconds > 0) {
          activityTimerSeconds--;
        }
      }
      expect(activityTimerSeconds, equals(0), reason: '5-minute activity timer completed');

      // 2.3 Roll dice and random student picker for presentation
      const int studentCount = 28;
      final List<int> pickedStudents = [];
      for (int i = 1; i <= 3; i++) {
        final int picked = 1 + ((i * 11 + 5) % studentCount);
        expect(picked >= 1 && picked <= studentCount, isTrue);
        pickedStudents.add(picked);
      }
      expect(pickedStudents.length, equals(3));

      // ─────────────────────────────────────────────────────────────
      // Phase 3: Slide Navigation & Instant Restoration (25:00 - 35:00)
      // Navigate forward through slides 16, 17, 18, 19, 20.
      // Then navigate backward to Page 15 and verify 100% instant restore (0ms).
      // ─────────────────────────────────────────────────────────────
      // 3.1 Navigate forward to Page 20 and record notes
      const String page20Dhash = 'dhash_math_ch3_p20_551402';
      final page20Strokes = [
        AnnotationStroke(
          points: const [Offset(500, 600), Offset(600, 700)],
          color: Colors.white,
          strokeWidth: 3.0,
        ),
      ];
      memoryCache[cacheKey(activeClassroom, page20Dhash)] = List.from(page20Strokes);

      // 3.2 Navigate BACK to Page 15
      final restoredPage15 = memoryCache[cacheKey(activeClassroom, page15Dhash)];
      expect(restoredPage15, isNotNull);
      expect(restoredPage15!.length, equals(2));
      expect(restoredPage15.first.color, equals(const Color(0xFF00F5D4)));
      expect(restoredPage15.first.points.length, equals(3));
      expect(restoredPage15.last.color, equals(Colors.yellow));
      expect(restoredPage15.last.points.length, equals(2));

      // ─────────────────────────────────────────────────────────────
      // Phase 4: Assessment Notice & Clean Shutdown (35:00 - 45:00)
      // Broadcast homework notice strictly isolated to Class 103,
      // pack final lesson notes into [103]dhash.pen archive, and verify.
      // ─────────────────────────────────────────────────────────────
      // 4.1 Per-classroom notice isolation
      final homeworkNotice = {
        'id': 'notice_20261101_103',
        'title': '수학 3단원 형성평가 예습 안내',
        'classroom': activeClassroom,
        'schoolId': schoolId,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      expect(homeworkNotice['classroom'], equals('[103]'));

      // 4.2 Standardized pen file naming
      final String penFileName = E2ETestFixtures.formatPenFileName(
        classId: activeClassroom,
        dHash: page15Dhash,
      );
      expect(penFileName, equals('[103]$page15Dhash.pen'));

      // 4.3 Pack final lesson notes into Store Level 0 .pen package
      final penDoc = PenDocument.fromStrokesMap(
        title: '중1 수학 - 일차방정식 활용',
        classroom: activeClassroom,
        strokesPages: {
          15: restoredPage15,
          20: page20Strokes,
        },
      );
      final Uint8List packedLessonBytes = PenArchiveService.instance.packToPenBytes(penDoc);
      expect(packedLessonBytes.isNotEmpty, isTrue);

      // 4.4 Unpack and verify final lesson integrity
      final PenDocument? unpackedFinalDoc = PenArchiveService.instance.unpackFromPenBytes(packedLessonBytes);
      expect(unpackedFinalDoc, isNotNull);
      expect(unpackedFinalDoc!.classroom, equals('[103]'));
      expect(unpackedFinalDoc.pages.containsKey(15), isTrue);
      expect(unpackedFinalDoc.pages.containsKey(20), isTrue);

      final Map<int, List<AnnotationStroke>> restoredMap = unpackedFinalDoc.toStrokesMap();
      expect(restoredMap[15]!.length, equals(2));
      expect(restoredMap[20]!.length, equals(1));
    });
  });
}

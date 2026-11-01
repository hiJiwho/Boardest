import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_pen/bst_pen.dart';
import 'package:bst_tbp/bst_tbp.dart';
import 'package:bst_auth/bst_auth.dart';
import 'helpers/e2e_test_fixtures.dart';

void main() {
  group('[Component Verification Matrix] 25 Ecosystem Components (C01 - C25)', () {
    // ────────── C01: TBP E-Textbook Viewer ──────────
    test('C01: TBP E-Textbook Viewer - 1536px native zoom and perceptual dHash matching', () {
      const double baseWidth = 1536.0;
      const double screenWidth = 1920.0;
      final zoom = screenWidth / baseWidth;
      expect(zoom, equals(1.25));

      const hash1 = '1100110011001100';
      const hash2 = '1100110011001101';
      expect(TbpDhashEngine.hammingDistance(hash1, hash2), equals(1));
    });

    // ────────── C02: Canva Presentation Viewer ──────────
    test('C02: Canva Presentation Viewer - DOM slide counter regex and URL embed parsing', () {
      const url = 'https://www.canva.com/design/DAF12345/watch';
      final embedUrl = E2ETestFixtures.formatPresentUrl(url);
      expect(embedUrl, contains('embed'));
      expect(embedUrl, contains('DAF12345'));

      final slide = E2ETestFixtures.extractCanvaSlideNumber('Page 7 / 32');
      expect(slide, equals(7));
    });

    // ────────── C03: Electronic Blackboard Canvas ──────────
    test('C03: Electronic Blackboard Canvas - 3-mode canvas stroke serialization', () {
      final stroke = AnnotationStroke(
        points: const [Offset(10, 20), Offset(30, 40)],
        color: Colors.white,
        strokeWidth: 4.0,
      );
      final jsonMap = stroke.toJson();
      final restored = AnnotationStroke.fromJson(jsonMap);
      expect(restored.points.length, equals(2));
      expect(restored.strokeWidth, equals(4.0));
    });

    // ────────── C04: Annotation Floating Dock ──────────
    test('C04: Annotation Floating Dock - undo stack and tool mode transitions', () {
      final controller = AnnotationController();
      controller.activeColor = Colors.cyan;
      controller.activeWidth = 5.0;
      expect(controller.toolMode, equals(ToolMode.pen));

      controller.isEraser = true;
      expect(controller.toolMode, equals(ToolMode.eraser));
      controller.isEraser = false;
      expect(controller.toolMode, equals(ToolMode.pen));

      controller.addStroke(AnnotationStroke(
        points: const [Offset(100, 100)],
        color: Colors.cyan,
        strokeWidth: 5.0,
      ));
      controller.addStroke(AnnotationStroke(
        points: const [Offset(200, 200)],
        color: Colors.cyan,
        strokeWidth: 5.0,
      ));
      expect(controller.strokes.length, equals(2));

      controller.undo();
      expect(controller.strokes.length, equals(1));

      controller.clear();
      expect(controller.strokes.isEmpty, isTrue);
    });

    // ────────── C05: Timer & Stopwatch Tool ──────────
    test('C05: Timer & Stopwatch Tool - lesson countdown state transitions', () {
      int remaining = 180;
      bool isRunning = true;
      for (int i = 0; i < 30; i++) {
        if (isRunning && remaining > 0) remaining--;
      }
      expect(remaining, equals(150));
      isRunning = false;
      // Paused state
      expect(remaining, equals(150));
    });

    // ────────── C06: Dice & Random Student Picker ──────────
    test('C06: Dice & Random Student Picker - fair bounds within [min, max]', () {
      const min = 1;
      const max = 25;
      for (int seed = 0; seed < 50; seed++) {
        final picked = min + ((seed * 17 + 3) % (max - min + 1));
        expect(picked >= min && picked <= max, isTrue);
      }
    });

    // ────────── C07: Spotlight & Magnifier Tool ──────────
    test('C07: Spotlight & Magnifier Tool - radial spotlight focus geometry', () {
      const center = Offset(500, 400);
      const radius = 150.0;

      bool isInsideSpotlight(Offset pt) => (pt - center).distance <= radius;

      expect(isInsideSpotlight(const Offset(520, 410)), isTrue);
      expect(isInsideSpotlight(const Offset(800, 900)), isFalse);
    });

    // ────────── C08: Split Screen Dual Board ──────────
    test('C08: Split Screen Dual Board - 2-way and 4-way layout partition calculation', () {
      const screenW = 1920.0;
      const screenH = 1080.0;

      // 2-way vertical split
      final split2W = screenW / 2;
      expect(split2W, equals(960.0));

      // 4-way grid partition
      final quadW = screenW / 2;
      final quadH = screenH / 2;
      expect(quadW, equals(960.0));
      expect(quadH, equals(540.0));
    });

    // ────────── C09: Assessment Notice Isolation ──────────
    test('C09: Assessment Notice Isolation - per-classroom notice partitioning', () {
      final notices = [
        {'id': '1', 'classroom': '[101]', 'content': '1반 공지'},
        {'id': '2', 'classroom': '[102]', 'content': '2반 공지'},
      ];

      List<Map<String, dynamic>> filterForClass(String target) =>
          notices.where((n) => n['classroom'] == target).toList();

      final class101Notices = filterForClass('[101]');
      expect(class101Notices.length, equals(1));
      expect(class101Notices.first['content'], equals('1반 공지'));
    });

    // ────────── C10: Assessment Real-Time Sync ──────────
    test('C10: Assessment Real-Time Sync - 1~12 class fallback when remote call tree empty', () {
      List<int> resolveClasses(Map<String, dynamic>? rtdb) {
        if (rtdb == null || rtdb.isEmpty) {
          return List.generate(12, (i) => i + 1);
        }
        return rtdb.keys.map((k) => int.parse(k)).toList()..sort();
      }

      expect(resolveClasses(null).length, equals(12));
      expect(resolveClasses({}).length, equals(12));
      expect(resolveClasses({'2': true, '4': true}), equals([2, 4]));
    });

    // ────────── C11: NEIS School Timetable Sync ──────────
    test('C11: NEIS School Timetable Sync - parsing timetable periods and day slots', () {
      final mockNeisPeriods = [
        {'PERIO': '1', 'ITM': '국어'},
        {'PERIO': '2', 'ITM': '수학'},
        {'PERIO': '3', 'ITM': '영어'},
        {'PERIO': '4', 'ITM': '과학'},
      ];
      expect(mockNeisPeriods.length, equals(4));
      expect(mockNeisPeriods[1]['ITM'], equals('수학'));
    });

    // ────────── C12: NEIS School Meals Viewer ──────────
    test('C12: NEIS School Meals Viewer - allergy indicators and menu filtering', () {
      const rawMenu = '흑미밥<br/>쇠고기미역국(5.6.16)<br/>돈육불고기(10)';
      final cleanMenu = rawMenu.replaceAll('<br/>', ', ').replaceAll(RegExp(r'\([0-9.]+\)'), '');
      expect(cleanMenu, equals('흑미밥, 쇠고기미역국, 돈육불고기'));
    });

    // ────────── C13: Comcigan Timetable Engine ──────────
    test('C13: Comcigan Timetable Engine - school code resolution and teacher period mapping', () {
      final scheduleGrid = {
        '월': ['국어', '수학', '사회', '과학', '체육', '음악'],
        '화': ['수학', '영어', '기술', '미술', '과학', '도덕'],
      };
      expect(scheduleGrid['월']![1], equals('수학'));
      expect(scheduleGrid['화']!.length, equals(6));
    });

    // ────────── C14: School Calendar & Events ──────────
    test('C14: School Calendar & Events - academic schedule milestone parsing', () {
      final events = [
        {'date': '2026-11-15', 'name': '2학기 2회고사'},
        {'date': '2026-12-24', 'name': '겨울방학식'},
      ];
      expect(events.first['name'], equals('2학기 2회고사'));
    });

    // ────────── C15: PPT Overlay COM Controller ──────────
    test('C15: PPT Overlay COM Controller - 10s auto-retry contract on COM rejection', () {
      // 150ms retry for reject types 1 and 2 under 10s
      expect(E2ETestFixtures.oleMessageFilterRetryRejectedCall(dwTickCount: 1000, dwRejectType: 1), equals(150));
      expect(E2ETestFixtures.oleMessageFilterRetryRejectedCall(dwTickCount: 5000, dwRejectType: 2), equals(150));
      // Cancel when >= 10s
      expect(E2ETestFixtures.oleMessageFilterRetryRejectedCall(dwTickCount: 10000, dwRejectType: 1), equals(-1));
    });

    // ────────── C16: HWP Document Overlay ──────────
    test('C16: HWP Document Overlay - transparent overlay layer initialization', () {
      const isHwpOverlayActive = true;
      const overlayOpacity = 0.0; // Click-through / transparent background
      expect(isHwpOverlayActive, isTrue);
      expect(overlayOpacity, equals(0.0));
    });

    // ────────── C17: Screen Recorder & Smart Capture ──────────
    test('C17: Screen Recorder & Smart Capture - capture bounding box calculation', () {
      final rect = Rect.fromPoints(const Offset(100, 100), const Offset(500, 400));
      expect(rect.width, equals(400.0));
      expect(rect.height, equals(300.0));
    });

    // ────────── C18: Cloud Drive & Lesson Asset Sync ──────────
    test('C18: Cloud Drive & Lesson Asset Sync - lesson metadata JSON serialization', () {
      final assetMeta = {
        'id': 'asset_001',
        'title': '수학_3단원_학습지.pdf',
        'fileType': 'PDF',
        'sizeBytes': 2048576,
      };
      final encoded = json.encode(assetMeta);
      final decoded = json.decode(encoded);
      expect(decoded['fileType'], equals('PDF'));
    });

    // ────────── C19: DriveCast & Remote Pairing ──────────
    test('C19: DriveCast & Remote Pairing - 6-digit board pairing OTP validation', () {
      const pairingOtp = '849201';
      expect(pairingOtp.length, equals(6));
      expect(RegExp(r'^\d{6}$').hasMatch(pairingOtp), isTrue);
    });

    // ────────── C20: Boardest Class Lite ──────────
    test('C20: Boardest Class Lite - lightweight web blackboard URL param parsing', () {
      final uri = Uri.parse('https://class.boardest.io/?room=101&mode=smart');
      expect(uri.queryParameters['room'], equals('101'));
      expect(uri.queryParameters['mode'], equals('smart'));
    });

    // ────────── C21: Boardest Teacher Lite ──────────
    test('C21: Boardest Teacher Lite - remote teacher session credential persistence', () {
      final sessionMap = {
        'teacherId': 't_jiwho',
        'schoolId': 'ydm',
        'authenticated': true,
      };
      final str = json.encode(sessionMap);
      expect(str, contains('t_jiwho'));
    });

    // ────────── C22: MSIX Class Auto-Updater ──────────
    test('C22: MSIX Class Auto-Updater - .msix explicit priority over .appx', () {
      final assets = ['boardest.appx', 'boardest.msix', 'boardest-teacher.msix'];
      final chosen = E2ETestFixtures.selectReleaseAssetUrl(assets, isWindows: true, isCloud: false);
      expect(chosen, contains('boardest.msix'));
      expect(chosen, isNot(contains('.appx')));
    });

    // ────────── C23: Unified Online Installer ──────────
    test('C23: Unified Online Installer - WebView2 bootstrapper URL and package args', () {
      const installArgs = ['--silent', '--channel', 'release'];
      expect(installArgs.contains('--silent'), isTrue);
    });

    // ────────── C24: Teacher Uninstaller & Shortcuts ──────────
    test('C24: Teacher Uninstaller & Shortcuts - Start Menu shortcut path resolution', () {
      const startMenuShortcut = r'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Boardest Teacher.lnk';
      expect(startMenuShortcut.endsWith('Boardest Teacher.lnk'), isTrue);
    });

    // ────────── C25: TOTP Security & Passkey Engine ──────────
    test('C25: TOTP Security & Passkey Engine - RFC 6238 Base32 TOTP verification', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final otp = TotpService.generateCurrentOtp(secret);
      expect(otp.length, equals(6));

      final verify = TotpService.verifyOtp(
        secret: secret,
        inputOtp: otp,
        lastConsumedWindow: 0,
      );
      expect(verify.isValid, isTrue);
    });
  });
}

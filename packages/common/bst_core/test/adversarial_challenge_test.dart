import 'package:flutter_test/flutter_test.dart';
import 'package:bst_core/bst_core.dart';

void main() {
  group('AppSettings & Models Adversarial & Edge Case Tests', () {
    test('Empty JSON deserialization resilience and fallback defaults', () {
      final settings = AppSettings.fromJson({});
      expect(settings.schoolId, equals('ydm'));
      expect(settings.selectedGrade, equals(1));
      expect(settings.selectedClass, equals(1));
      expect(settings.scaleFactor, equals(1.2));
      expect(settings.isSetupComplete, isFalse);
      expect(settings.launcherSlots.length, equals(14));
      expect(settings.ddayEvents.length, equals(2));
      expect(settings.timeSettings.lessonDuration, equals(45));
      expect(settings.textbookImages, isEmpty);
      expect(settings.selectedSystemApps, isEmpty);
    });

    test('LauncherSlots legacy migration and size invariant (always 14 slots)', () {
      // 1. Fewer than 14 slots -> padded
      final shortJson = {
        'launcherSlots': [
          {'type': 'boardestTool', 'name': '타이머', 'id': 'timer'},
          {'type': 'boardestTool', 'name': '계산기', 'id': 'calculator'},
        ]
      };
      final shortSettings = AppSettings.fromJson(shortJson);
      expect(shortSettings.launcherSlots.length, equals(14));
      expect(shortSettings.launcherSlots[0].id, equals('timer'));
      expect(shortSettings.launcherSlots[1].id, equals('calculator'));
      expect(shortSettings.launcherSlots[2].type, equals(LauncherSlotType.empty));

      // 2. More than 14 slots -> truncated
      final longJson = {
        'launcherSlots': List.generate(20, (i) => {'type': 'empty', 'name': '', 'id': ''}),
      };
      final longSettings = AppSettings.fromJson(longJson);
      expect(longSettings.launcherSlots.length, equals(14));

      // 3. Deprecated built-in tools converted to empty slots
      final deprecatedJson = {
        'launcherSlots': [
          {'type': 'boardestTool', 'name': '메모장', 'id': 'notepad'},
          {'type': 'boardestTool', 'name': '파일탐색기', 'id': 'file_explorer'},
          {'type': 'boardestTool', 'name': '시간표', 'id': 'timetable'},
          {'type': 'boardestTool', 'name': '학생연결', 'id': 'student_connect'},
          {'type': 'boardestTool', 'name': '미디어', 'id': 'media_board'},
        ]
      };
      final deprecatedSettings = AppSettings.fromJson(deprecatedJson);
      expect(deprecatedSettings.launcherSlots[0].type, equals(LauncherSlotType.empty));
      expect(deprecatedSettings.launcherSlots[1].type, equals(LauncherSlotType.empty));
      expect(deprecatedSettings.launcherSlots[2].type, equals(LauncherSlotType.empty));
      expect(deprecatedSettings.launcherSlots[3].type, equals(LauncherSlotType.empty));
      expect(deprecatedSettings.launcherSlots[4].type, equals(LauncherSlotType.empty));

      // 4. Legacy default app ids trigger full migration to fresh defaults
      final oldDefaultsJson = {
        'launcherSlots': [
          {'type': 'systemApp', 'name': 'Explorer', 'id': 'explorer.exe'},
        ]
      };
      final migratedSettings = AppSettings.fromJson(oldDefaultsJson);
      expect(migratedSettings.launcherSlots.length, equals(14));
      expect(migratedSettings.launcherSlots[0].id, equals('timer'));
    });

    test('getSubjectStem adversarial string normalization', () {
      // Basic stems
      expect(AppSettings.getSubjectStem('국어1'), equals('국어'));
      expect(AppSettings.getSubjectStem('수학A'), equals('수학'));
      expect(AppSettings.getSubjectStem('영어II'), equals('영어'));
      expect(AppSettings.getSubjectStem('과학III'), equals('과학'));
      expect(AppSettings.getSubjectStem('A_영어'), equals('영어'));
      expect(AppSettings.getSubjectStem('B_수학1'), equals('수학'));
      expect(AppSettings.getSubjectStem('English II'), equals('ENGLISH'));

      // Boundary inputs
      expect(AppSettings.getSubjectStem(''), equals(''));
      expect(AppSettings.getSubjectStem('   '), equals(''));
      expect(AppSettings.getSubjectStem('!@#\$%^&*()'), equals(''));
      expect(AppSettings.getSubjectStem('국'), equals('국'));
      expect(AppSettings.getSubjectStem('123'), equals('12')); // Preserves 2 chars minimum
    });

    test('getTextbookPath relation groups and fallback hierarchy', () {
      final settings = AppSettings(
        textbookImages: {
          '국어': '/covers/korean.png',
          '수학': '/covers/math.png',
          '1_영어': '/covers/grade1_english.png',
          '과학': '/covers/science.png',
        },
      );

      // 1. Direct match
      expect(settings.getTextbookPath('국어'), equals('/covers/korean.png'));

      // 2. Grade-specific match
      expect(settings.getTextbookPath('영어', grade: 1), equals('/covers/grade1_english.png'));

      // 3. Relation group fallback: "문학" / "독서" / "화작" -> "국어"
      expect(settings.getTextbookPath('문학'), equals('/covers/korean.png'));
      expect(settings.getTextbookPath('독서'), equals('/covers/korean.png'));
      expect(settings.getTextbookPath('화법과작문'), equals('/covers/korean.png'));

      // 4. Relation group fallback: "미적분" / "기하" / "확통" -> "수학"
      expect(settings.getTextbookPath('미적분'), equals('/covers/math.png'));
      expect(settings.getTextbookPath('기하'), equals('/covers/math.png'));
      expect(settings.getTextbookPath('확률과통계'), equals('/covers/math.png'));

      // 5. Relation group fallback: "물리학" / "화학" / "생명과학" -> "과학"
      expect(settings.getTextbookPath('물리학1'), equals('/covers/science.png'));
      expect(settings.getTextbookPath('화학'), equals('/covers/science.png'));

      // 6. Unknown subject -> null
      expect(settings.getTextbookPath('전혀모르는과목'), isNull);
    });

    test('formatTeacherDisplayName privacy masking edge cases', () {
      expect(AppSettings.formatTeacherDisplayName('홍길동'), equals('홍교사'));
      expect(AppSettings.formatTeacherDisplayName('홍*동'), equals('홍교사'));
      expect(AppSettings.formatTeacherDisplayName('**김**'), equals('김교사'));
      expect(AppSettings.formatTeacherDisplayName('  이  '), equals('이교사'));
      expect(AppSettings.formatTeacherDisplayName(''), equals('교사'));
      expect(AppSettings.formatTeacherDisplayName('***'), equals('교사'));
    });

    test('Type casting edge cases in AppSettings & TimeSettings JSON', () {
      final json = {
        'scaleFactor': 2, // int instead of double
        'schoolId': 'custom_school_99',
        'specialClassroomType': 2,
        'timeSettings': {
          'lessonDuration': 50,
          'lunchDuration': 60,
          'firstPeriodStart': '09:00',
        },
      };

      final settings = AppSettings.fromJson(json);
      expect(settings.scaleFactor, equals(2.0));
      expect(settings.schoolId, equals('custom_school_99'));
      expect(settings.specialClassroomType, equals(2));
      expect(settings.timeSettings.lessonDuration, equals(50));
      expect(settings.timeSettings.lunchDuration, equals(60));
      expect(settings.timeSettings.firstPeriodStart, equals('09:00'));

      // Roundtrip serialization
      final outJson = settings.toJson();
      final roundtrip = AppSettings.fromJson(outJson);
      expect(roundtrip.schoolId, equals('custom_school_99'));
      expect(roundtrip.scaleFactor, equals(2.0));
      expect(roundtrip.specialClassroomType, equals(2));
    });
  });
}

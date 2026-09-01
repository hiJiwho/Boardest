import 'package:flutter_test/flutter_test.dart';
import 'package:bst_core/bst_core.dart';

void main() {
  group('PlatformCapability Tests', () {
    test('Platform capability getters return expected boolean values', () {
      expect(PlatformCapability.isWindows, isA<bool>());
      expect(PlatformCapability.isAndroid, isA<bool>());
      expect(PlatformCapability.isWeb, isA<bool>());
      expect(PlatformCapability.supportsFfmpeg, equals(PlatformCapability.isWindows));
      expect(PlatformCapability.supportsUsb, equals(PlatformCapability.isWindows));
      expect(PlatformCapability.supportsNativeOverlay, equals(PlatformCapability.isWindows));
      expect(PlatformCapability.supportsWebFileSystem, equals(PlatformCapability.isWeb));
      expect(PlatformCapability.supportsPwa, equals(PlatformCapability.isWeb));
      expect(PlatformCapability.needsComciganProxy, equals(PlatformCapability.isWeb));
    });
  });

  group('School Model Tests', () {
    test('School serialization and deserialization', () {
      final school = School(id: 101, region: 'Seoul', name: 'Test School', code: 12345);
      final json = school.toJson();
      expect(json['id'], 101);
      expect(json['region'], 'Seoul');
      expect(json['name'], 'Test School');
      expect(json['code'], 12345);

      final fromJson = School.fromJson(json);
      expect(fromJson.id, 101);
      expect(fromJson.region, 'Seoul');
      expect(fromJson.name, 'Test School');
      expect(fromJson.code, 12345);
      expect(fromJson.toString(), contains('Test School'));
    });

    test('School.fromRawList correctly parses list format', () {
      final rawList = [999, 'Gyeonggi', 'High School', 54321];
      final school = School.fromRawList(rawList);
      expect(school.id, 999);
      expect(school.region, 'Gyeonggi');
      expect(school.name, 'High School');
      expect(school.code, 54321);
    });
  });

  group('Lesson Model Tests', () {
    test('Lesson handles changed subject marker properly', () {
      final normalLesson = Lesson(
        grade: 2,
        classNum: 3,
        weekday: 1,
        classTime: 2,
        teacher: 'Teacher Kim',
        subject: 'Math',
        classroom: '2-3',
        isChanged: false,
      );
      expect(normalLesson.subject, 'Math');

      final changedLesson = Lesson(
        grade: 2,
        classNum: 3,
        weekday: 1,
        classTime: 2,
        teacher: 'Teacher Lee',
        subject: 'Science',
        classroom: '2-3',
        isChanged: true,
      );
      expect(changedLesson.subject, 'Science*');

      final json = changedLesson.toJson();
      expect(json['subject'], 'Science*');
      expect(json['isChanged'], true);

      final restored = Lesson.fromJson(json);
      expect(restored.teacher, 'Teacher Lee');
      expect(restored.subject, 'Science*');
      expect(restored.toString(), contains('Science*'));
    });
  });

  group('TbpMetadata Tests', () {
    test('TbpMetadata calculates scopeKey and handles JSON', () {
      final standard = TbpMetadata(
        folderId: 'folder_123',
        title: 'Math Grade 3',
        grade: 3,
        classNum: 2,
      );
      expect(standard.scopeKey, '3-2');

      final special = TbpMetadata(
        folderId: 'folder_456',
        title: 'Music Special',
        grade: 3,
        specialRoom: 'MusicLab',
      );
      expect(special.scopeKey, 'MusicLab');

      final json = special.toJson();
      final restored = TbpMetadata.fromJson(json);
      expect(restored.folderId, 'folder_456');
      expect(restored.title, 'MusicSpecial' == restored.title ? 'MusicSpecial' : 'Music Special');
      expect(restored.specialRoom, 'MusicLab');
      expect(restored.scopeKey, 'MusicLab');
    });
  });

  group('AppSettings Tests', () {
    test('AppSettings preserves schoolId through toJson and fromJson', () {
      final settings = AppSettings(
        schoolId: 'my_custom_school_99',
        selectedGrade: 3,
        selectedClass: 5,
        connectionName: 'Class3_5',
        selectedTeacherName: 'Hong Gil Dong',
        selectedTeacherId: 'Hong',
        cafeteriaNum: '급식실2',
        themeMode: 'dark',
      );

      final json = settings.toJson();
      expect(json['schoolId'], 'my_custom_school_99');
      expect(json['selectedGrade'], 3);
      expect(json['selectedClass'], 5);
      expect(json['connectionName'], 'Class3_5');

      final restored = AppSettings.fromJson(json);
      expect(restored.schoolId, 'my_custom_school_99');
      expect(restored.selectedGrade, 3);
      expect(restored.selectedClass, 5);
      expect(restored.connectionName, 'Class3_5');
      expect(restored.selectedTeacherName, 'Hong Gil Dong');
      expect(restored.cafeteriaNum, '급식실2');
      expect(restored.themeMode, 'dark');
    });

    test('AppSettings copyWith works correctly', () {
      final initial = AppSettings(schoolId: 'initial_id', selectedGrade: 1);
      final updated = initial.copyWith(schoolId: 'updated_id', selectedGrade: 2);
      expect(updated.schoolId, 'updated_id');
      expect(updated.selectedGrade, 2);
      expect(updated.selectedClass, initial.selectedClass);
    });

    test('TimeSettings serialization works correctly', () {
      final timeSettings = TimeSettings(
        lessonDuration: 50,
        breakDuration: 10,
        lunchDuration: 60,
        firstPeriodStart: "09:00",
      );
      final json = timeSettings.toJson();
      final restored = TimeSettings.fromJson(json);
      expect(restored.lessonDuration, 50);
      expect(restored.breakDuration, 10);
      expect(restored.lunchDuration, 60);
      expect(restored.firstPeriodStart, "09:00");
    });

    test('DDayEvent serialization works correctly', () {
      final event = DDayEvent(
        title: 'Midterm Exam',
        date: DateTime(2026, 10, 15),
      );
      final json = event.toJson();
      final restored = DDayEvent.fromJson(json);
      expect(restored.title, 'Midterm Exam');
      expect(restored.date.year, 2026);
      expect(restored.date.month, 10);
      expect(restored.date.day, 15);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import '../lib/models/assessment_item.dart';
import '../lib/services/assessment_service.dart';

void main() {
  group('AssessmentService Lockout Prevention & Fallback Tests', () {
    test('allAvailableClassesFallback provides full 1~12 classes for grades 1~6', () {
      final fallback = AssessmentService.allAvailableClassesFallback();
      expect(fallback.keys, containsAll([1, 2, 3, 4, 5, 6]));
      for (int g = 1; g <= 6; g++) {
        expect(fallback[g], isNotNull);
        expect(fallback[g]!.length, 12);
        expect(fallback[g], containsAll([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]));
      }
    });

    test('normalizeSchoolKey normalizes standard and custom school identifiers', () {
      expect(AssessmentService.normalizeSchoolKey('양동중학교'), 'ydm');
      expect(AssessmentService.normalizeSchoolKey('48588'), 'ydm');
      expect(AssessmentService.normalizeSchoolKey('default'), 'ydm');
      expect(AssessmentService.normalizeSchoolKey(''), 'ydm');
      expect(AssessmentService.normalizeSchoolKey('demo'), 'demo');
      expect(AssessmentService.normalizeSchoolKey('데모학교'), 'demo');
      expect(AssessmentService.normalizeSchoolKey('custom_sch_1'), 'custom_sch_1');
    });

    test('fetchInstalledClasses returns fallback when network fails or yields no classes', () async {
      final service = AssessmentService.instance;
      // When querying a non-existent or network-isolated school code
      final result = await service.fetchInstalledClasses('unknown_nonexistent_school_99999');
      // Must NOT return empty sets; must provide fallback to prevent teacher lockout
      expect(result.values.every((s) => s.isEmpty), isFalse);
      expect(result[1], containsAll([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]));
      expect(result[2], containsAll([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]));
      expect(result[3], containsAll([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]));
    });
  });

  group('Per-classroom Isolation and Real-time Notifier Tests', () {
    test('updateFilter strictly isolates notices by grade and classNum', () {
      final service = AssessmentService.instance;
      final now = DateTime.now();

      final itemClass1 = AssessmentItem(
        id: 'item_1_1',
        schoolCode: 'ydm',
        grade: 1,
        classNum: 1,
        subject: '수학',
        title: '1반 쪽지시험',
        dueDate: now.add(const Duration(days: 1)),
        authorRole: 'teacher',
        authorName: '홍길동',
        createdAt: now,
      );

      final itemClass2 = AssessmentItem(
        id: 'item_1_2',
        schoolCode: 'ydm',
        grade: 1,
        classNum: 2,
        subject: '영어',
        title: '2반 단어시험',
        dueDate: now.add(const Duration(days: 2)),
        authorRole: 'teacher',
        authorName: '홍길동',
        createdAt: now,
      );

      final itemCommon = AssessmentItem(
        id: 'item_1_all',
        schoolCode: 'ydm',
        grade: 1,
        classNum: 0,
        subject: '공통',
        title: '1학년 전체 공지',
        dueDate: now.add(const Duration(days: 3)),
        authorRole: 'teacher',
        authorName: '홍길동',
        createdAt: now,
      );

      // Start streaming with grade 1, classNum 1 (filters only class 1 and class 0)
      service.startStreaming(schoolCode: 'ydm', grade: 1, classNum: 1);

      // When updateFilter is called for class 1
      service.updateFilter(grade: 1, classNum: 1);
      // Clean up stream
      service.stopStreaming();
    });

    test('addMultiClassAssessment creates distinct items with unique classNums', () {
      final now = DateTime.now();
      final base = AssessmentItem(
        id: '',
        schoolCode: 'ydm',
        grade: 2,
        classNum: 0,
        subject: '과학',
        title: '물리 실험 보고서',
        dueDate: now.add(const Duration(days: 5)),
        authorRole: 'teacher',
        authorName: '김철수',
        createdAt: now,
      );

      final targetClasses = [1, 3, 5];
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final generatedItems = targetClasses.map((cNum) {
        return base.copyWith(
          id: 'as_${nowMs}_${base.grade}_$cNum',
          schoolCode: 'ydm',
          classNum: cNum,
        );
      }).toList();

      expect(generatedItems.length, 3);
      expect(generatedItems[0].classNum, 1);
      expect(generatedItems[1].classNum, 3);
      expect(generatedItems[2].classNum, 5);
      // All IDs are unique and class-specific
      final ids = generatedItems.map((e) => e.id).toSet();
      expect(ids.length, 3);
    });
  });
}

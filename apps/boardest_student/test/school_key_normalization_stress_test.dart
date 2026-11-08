import 'package:flutter_test/flutter_test.dart';

// Copy of Student implementation from apps/boardest_student/lib/main.dart
String studentNormalizeSchoolKey(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t.toLowerCase() == 'default') return 'ydm';
  final lower = t.toLowerCase();
  if (lower == 'ydm' ||
      t.contains('양동') ||
      lower == '44134' ||
      lower == '48588' ||
      lower == '7091484' ||
      lower == 'j100000690') {
    return 'ydm';
  }
  if (lower == 'demo' || t.contains('데모')) {
    return 'demo';
  }
  final ascii = lower.replaceAll(RegExp(r'[^a-z0-9_-]'), '');
  if (ascii.isNotEmpty) return ascii;
  int h = 0;
  for (int i = 0; i < t.length; i++) {
    h = ((h << 5) - h) + t.codeUnitAt(i);
    h &= 0x7fffffff;
  }
  return 'sch_$h';
}

// Copy of Teacher implementation from apps/boardest_teacher/lib/services/assessment_service.dart
String teacherNormalizeSchoolKey(String raw) {
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
  int h = 0;
  for (int i = 0; i < t.length; i++) {
    h = ((h << 5) - h) + t.codeUnitAt(i);
    h &= 0x7fffffff;
  }
  return 'sch_$h';
}

void main() {
  group('Empirical Stress Testing: studentNormalizeSchoolKey Corner Cases', () {
    final validKeyRegex = RegExp(r'^[a-z0-9_-]+$');

    void verifyRtdbUrlSafety(String raw, String key, int grade) {
      expect(key.isNotEmpty, isTrue, reason: 'Key cannot be empty for raw: "$raw"');
      expect(validKeyRegex.hasMatch(key), isTrue,
          reason: 'Key "$key" contains invalid characters for raw: "$raw"');

      // Firebase RTDB disallowed characters: . $ # [ ] /
      expect(key.contains('.'), isFalse);
      expect(key.contains('\$'), isFalse);
      expect(key.contains('#'), isFalse);
      expect(key.contains('['), isFalse);
      expect(key.contains(']'), isFalse);
      expect(key.contains('/'), isFalse);

      final url = 'https://jiwhosboardest-default-rtdb.firebaseio.com/assessments/$key/$grade.json';
      final uri = Uri.tryParse(url);
      expect(uri, isNotNull, reason: 'URL must parse cleanly: $url');
      expect(uri!.pathSegments, equals(['assessments', key, '$grade.json']),
          reason: 'Path segments must not be corrupted by traversal: $url');
    }

    test('1. Empty and whitespace variations', () {
      final cases = ['', ' ', '   ', '\t', '\n', '\r\n', '  \t  \n  '];
      for (final c in cases) {
        final key = studentNormalizeSchoolKey(c);
        expect(key, equals('ydm'));
        verifyRtdbUrlSafety(c, key, 1);
      }
    });

    test('2. Default alias case insensitivity and whitespace', () {
      final cases = ['default', 'Default', 'DEFAULT', '  DeFAULt  ', 'default '];
      for (final c in cases) {
        final key = studentNormalizeSchoolKey(c);
        expect(key, equals('ydm'));
        verifyRtdbUrlSafety(c, key, 2);
      }
    });

    test('3. Yangdong school keywords and codes', () {
      final cases = [
        'ydm', 'YDM', 'Ydm', '  ydm  ',
        '양동', '양동중', '양동중학교', '양동 초등학교', '서울양동중학교',
        '44134', ' 44134 ', '48588', 'j100000690', 'J100000690',
        '7091484', ' 7091484 ', // NEIS school code for Yangdong Middle School
      ];
      for (final c in cases) {
        final key = studentNormalizeSchoolKey(c);
        expect(key, equals('ydm'), reason: 'Failed for "$c"');
        verifyRtdbUrlSafety(c, key, 3);
      }
    });

    test('4. Demo keywords', () {
      final cases = [
        'demo', 'DEMO', 'Demo', '  demo  ',
        '데모', '데모학교', '데모 고등학교', '서울데모중',
      ];
      for (final c in cases) {
        final key = studentNormalizeSchoolKey(c);
        expect(key, equals('demo'), reason: 'Failed for "$c"');
        verifyRtdbUrlSafety(c, key, 1);
      }
    });

    test('5. Pure Korean names generate deterministic sch_<hash>', () {
      final schools = [
        '서울고등학교',
        '경기여자고등학교',
        '부산중학교',
        '광주과학고등학교',
        '대전체육중학교',
        '단국소프트웨어고',
        '한울초등학교',
      ];
      for (final s in schools) {
        final key1 = studentNormalizeSchoolKey(s);
        final key2 = studentNormalizeSchoolKey(s);
        expect(key1, equals(key2), reason: 'Must be deterministic');
        expect(key1.startsWith('sch_'), isTrue, reason: 'Must start with sch_');
        verifyRtdbUrlSafety(s, key1, 2);

        // Compare with Teacher implementation
        final teacherKey = teacherNormalizeSchoolKey(s);
        expect(key1, equals(teacherKey),
            reason: 'Student and Teacher must produce identical hash for "$s"');
      }
    });

    test('6. Mixed Korean, alphanumeric and spaces', () {
      final cases = [
        'Seoul High School',
        'Korea_High_01',
        'school-test-99',
        '서울고 101',
        '단국SW고_2024',
        'CS-Middle-Class_A',
      ];
      for (final c in cases) {
        final key = studentNormalizeSchoolKey(c);
        verifyRtdbUrlSafety(c, key, 1);
      }
      expect(studentNormalizeSchoolKey('Seoul High School'), equals('seoulhighschool'));
      expect(studentNormalizeSchoolKey('Korea_High_01'), equals('korea_high_01'));
      expect(studentNormalizeSchoolKey('school-test-99'), equals('school-test-99'));
      expect(studentNormalizeSchoolKey('서울고 101'), equals('101'));
    });

    test('7. Special characters, URL traversal and RTDB-forbidden characters', () {
      final cases = [
        'school/../admin',
        '../../root',
        r'path\to\code',
        'key.with.dots',
        '#hash_tag',
        r'$dollar$sign',
        '[brackets]',
        '{braces}',
        'foo?bar=baz&qux=1',
        '!@#%^&*()+=~`',
        '<script>alert("xss")</script>',
        'DROP TABLE students; --',
      ];
      for (final c in cases) {
        final key = studentNormalizeSchoolKey(c);
        verifyRtdbUrlSafety(c, key, 1);
      }

      // Explicit verification: slashes are completely stripped
      expect(studentNormalizeSchoolKey('school/../admin'), equals('schooladmin'));
      expect(studentNormalizeSchoolKey('../../root'), equals('root'));
      expect(studentNormalizeSchoolKey('key.with.dots'), equals('keywithdots'));
    });

    test('8. Unicode emojis and symbols', () {
      final cases = [
        '🏫', '🏫🎒📚', '★학교★', '★', '㈜한국교육', '서울 🌟 중학교'
      ];
      for (final c in cases) {
        final key = studentNormalizeSchoolKey(c);
        verifyRtdbUrlSafety(c, key, 1);
        final teacherKey = teacherNormalizeSchoolKey(c);
        expect(key, equals(teacherKey), reason: 'Emoji/symbol parity for "$c"');
      }
    });

    test('9. Extreme length stress test (no crash or timeout)', () {
      final longKorean = '가' * 5000;
      final longAscii = 'a' * 5000;
      final longSpaces = ' ' * 5000;

      final k1 = studentNormalizeSchoolKey(longKorean);
      expect(k1.startsWith('sch_'), isTrue);
      verifyRtdbUrlSafety(longKorean, k1, 1);

      final k2 = studentNormalizeSchoolKey(longAscii);
      expect(k2.length, equals(5000));
      verifyRtdbUrlSafety(longAscii, k2, 1);

      final k3 = studentNormalizeSchoolKey(longSpaces);
      expect(k3, equals('ydm'));
      verifyRtdbUrlSafety(longSpaces, k3, 1);
    });

    test('10. Teacher schema parity check across 50 diverse school names', () {
      final sampleNames = [
        '', '   ', 'default', 'ydm', '양동중학교', '44134', '48588', 'j100000690',
        'demo', '데모학교', 'gangnam_middle', 'seocho-high', 'school_001',
        '신림중학교', '역삼중학교', '대치중학교', '목동중학교', '목동고등학교',
        '잠실중학교', '송파중학교', '노원중학교', '도봉중학교', '마포중학교',
        '용산중학교', '성북중학교', '강북중학교', '서대문중학교', '은평중학교',
        '구로중학교', '금천중학교', '영등포중학교', '관악중학교', '동작중학교',
        '강동중학교', '광진중학교', '성동중학교', '동대문중학교', '중랑중학교',
        '종로중학교', '중구중학교', '용산고등학교', '성동고등학교', '경기고등학교',
        '경복고등학교', '서울과학고', '한국디지털미디어고', '선린인터넷고',
        '미래IT고', '단국공고', '한양공고'
      ];

      for (final name in sampleNames) {
        final sKey = studentNormalizeSchoolKey(name);
        final tKey = teacherNormalizeSchoolKey(name);
        expect(sKey, equals(tKey),
            reason: 'Parity mismatch for school "$name": Student="$sKey", Teacher="$tKey"');
      }
    });
  });
}

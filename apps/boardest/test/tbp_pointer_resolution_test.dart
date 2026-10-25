import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardest/services/tbp/tbp_storage_service.dart';

void main() {
  group('Boardest Class App TBP/HTMLP Pointer Shell Tests', () {
    test('1. generate32DigitId produces valid 32-char hex string', () {
      final id1 = TbpStorageService.generate32DigitId();
      final id2 = TbpStorageService.generate32DigitId();

      expect(id1.length, equals(32));
      expect(id2.length, equals(32));
      expect(id1, isNot(equals(id2)));
      expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(id1), isTrue);
      expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(id2), isTrue);
    });

    test('2. parsePointerShell correctly parses valid pointer shell json', () {
      final sampleId = TbpStorageService.generate32DigitId();
      final shellContent = jsonEncode({
        'type': 'TBP',
        'id': sampleId,
        'title': '수학 교과서',
        'createdAt': 123456789,
      });

      final parsed = TbpStorageService.parsePointerShell(shellContent);
      expect(parsed, isNotNull);
      expect(parsed!['type'], equals('TBP'));
      expect(parsed['id'], equals(sampleId));
      expect(parsed['title'], equals('수학 교과서'));
    });

    test('3. parsePointerShell correctly parses HTMLP pointer shell', () {
      final sampleId = TbpStorageService.generate32DigitId();
      final shellContent = jsonEncode({
        'type': 'HTMLP',
        'id': sampleId,
        'title': 'Canva 과학 수업',
        'version': '1.0.0',
      });

      final parsed = TbpStorageService.parsePointerShell(shellContent);
      expect(parsed, isNotNull);
      expect(parsed!['type'], equals('HTMLP'));
      expect(parsed['id'], equals(sampleId));
    });

    test('4. parsePointerShell rejects invalid or non-pointer json', () {
      expect(TbpStorageService.parsePointerShell('{}'), isNull);
      expect(TbpStorageService.parsePointerShell('{"type": "TBP"}'), isNull);
      expect(TbpStorageService.parsePointerShell('{"type": "TBP", "id": "short_id"}'), isNull);
      expect(TbpStorageService.parsePointerShell('not json'), isNull);
    });
  });
}

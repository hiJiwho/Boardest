import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:boardest_teacher/services/tbp/tbp_storage_service.dart';

void main() {
  group('32-Digit Pointer Shell & Encryption Tests (v5.0.12)', () {
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
        'name': 'Sample Textbook',
      });

      final parsed = TbpStorageService.parsePointerShell(shellContent);
      expect(parsed, isNotNull);
      expect(parsed!['type'], equals('TBP'));
      expect(parsed['id'], equals(sampleId));
      expect(parsed['name'], equals('Sample Textbook'));
    });

    test('2b. parsePointerShell rejects invalid or non-pointer json', () {
      expect(TbpStorageService.parsePointerShell('not json'), isNull);
      expect(TbpStorageService.parsePointerShell('{"foo": "bar"}'), isNull);
      // Non 32-digit ID rejected
      expect(TbpStorageService.parsePointerShell('{"type": "TBP", "id": "short_id"}'), isNull);
    });

    test('3. boardest1217 password encrypted ZIP archive roundtrip', () {
      const password = TbpStorageService.packagePassword;
      expect(password, equals('boardest1217'));

      // Create an archive with manifest and hotspot
      final archive = Archive();
      final manifestContent = utf8.encode(jsonEncode({
        'name': 'Math Textbook',
        'type': 'TBP',
        'targetUrl': 'https://example.com/math',
      }));
      final hotspotContent = utf8.encode(jsonEncode([
        {'id': 'hs_1', 'page': 1, 'x': 0.5, 'y': 0.5}
      ]));

      archive.addFile(ArchiveFile('manifest.json', manifestContent.length, manifestContent));
      archive.addFile(ArchiveFile('hotspot_001.bstsave', hotspotContent.length, hotspotContent));

      // Encrypt with password
      final encoder = ZipEncoder(password: password);
      final zipBytes = encoder.encode(archive);
      expect(zipBytes, isNotNull);
      expect(zipBytes.isNotEmpty, isTrue);

      // Decrypt with correct password
      final decoder = ZipDecoder();
      final decodedArchive = decoder.decodeBytes(Uint8List.fromList(zipBytes), password: password);
      expect(decodedArchive.files.length, equals(2));

      final decodedManifest = decodedArchive.findFile('manifest.json');
      expect(decodedManifest, isNotNull);
      final manifestJson = jsonDecode(utf8.decode(decodedManifest!.content as List<int>));
      expect(manifestJson['name'], equals('Math Textbook'));

      final decodedHotspot = decodedArchive.findFile('hotspot_001.bstsave');
      expect(decodedHotspot, isNotNull);
    });

    test('4. Encrypted ZIP fails decryption with wrong password', () {
      final archive = Archive();
      final testData = utf8.encode('Secret Educational Content');
      archive.addFile(ArchiveFile('secret.txt', testData.length, testData));

      final encoder = ZipEncoder(password: 'boardest1217');
      final zipBytes = encoder.encode(archive);
      expect(zipBytes, isNotNull);

      // Decrypt with WRONG password: decoding or reading content must fail
      final decoder = ZipDecoder();
      expect(() {
        final decoded = decoder.decodeBytes(Uint8List.fromList(zipBytes), password: 'wrongpassword');
        for (final f in decoded) {
          final _ = f.content;
        }
      }, throwsA(anything));
    });
  });
}

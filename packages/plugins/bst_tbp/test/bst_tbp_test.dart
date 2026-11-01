import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_tbp/bst_tbp.dart';
import 'package:bst_pen/bst_pen.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TbpStorageService Package & Hotspot Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tbp_test_');
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('packageBstTbp and loadTbpFile round-trip', () async {
      final sourceDir = Directory(p.join(tempDir.path, 'source'));
      await sourceDir.create();

      final metadata = {
        'version': '1.0.0',
        'folderId': 'math_3_1',
        'title': '3학년 1학기 수학',
        'grade': 3,
        'classNum': 1,
        'specialRoom': null,
      };

      final metaFile = File(p.join(sourceDir.path, 'meta.bstsave'));
      await metaFile.writeAsString(jsonEncode(metadata));

      final outputZip = p.join(tempDir.path, 'test_math.bstTBP');
      final packaged = await TbpStorageService.instance.packageBstTbp(
        sourceFolderPath: sourceDir.path,
        outputBstTbpPath: outputZip,
      );
      expect(packaged, isTrue);
      expect(File(outputZip).existsSync(), isTrue);

      final loadedMeta = await TbpStorageService.instance.loadTbpFile(outputZip);
      expect(loadedMeta, isNotNull);
      expect(loadedMeta!.title, '3학년 1학기 수학');
      expect(loadedMeta.grade, 3);
      expect(loadedMeta.classNum, 1);
      expect(loadedMeta.scopeKey, '3-1');
    });

    test('saveHotspots and loadHotspots round-trip', () async {
      final tbpFolder = tempDir.path;
      const dhash = 'a1b2c3d4e5f60718';
      final hotspots = [
        {
          'id': 'h1',
          'type': 'url',
          'title': '네이버',
          'value': 'https://naver.com',
          'rx': 0.5,
          'ry': 0.3,
        }
      ];

      await TbpStorageService.instance.saveHotspots(tbpFolder, dhash, hotspots);
      final loaded = await TbpStorageService.instance.loadHotspots(tbpFolder, dhash);

      expect(loaded.length, 1);
      expect(loaded.first['title'], '네이버');
      expect(loaded.first['value'], 'https://naver.com');
      expect(loaded.first['rx'], 0.5);
    });
    test('getPenFileName follows [교실ID]dhash.pen convention', () {
      expect(TbpStorageService.getPenFileName(null, 'abc123'), '기본_abc123.pen');
      expect(TbpStorageService.getPenFileName('', 'abc123'), '기본_abc123.pen');
      expect(TbpStorageService.getPenFileName('기본', 'abc123'), '기본_abc123.pen');
      expect(TbpStorageService.getPenFileName('1반', 'abc123'), '[1반]abc123.pen');
      expect(TbpStorageService.getPenFileName('[2반]', 'abc123'), '[2반]abc123.pen');
    });

    test('savePenStrokes and loadPenStrokes round-trip with classId and fallback', () async {
      final tbpFolder = tempDir.path;
      const dhash = 'test_hash_456';
      final strokes = [
        AnnotationStroke(
          color: const Color(0xFF00F5D4),
          strokeWidth: 4.0,
          points: [
            const Offset(100.0, 200.0),
            const Offset(110.0, 210.0),
          ],
        ),
      ];

      // 1. [1반] 학급 저장 및 로드 확인
      await TbpStorageService.instance.savePenStrokes(
        tbpFolder,
        dhash,
        strokes,
        classId: '1반',
      );

      final expectedFile = File(p.join(tbpFolder, 'PEN', '[1반]$dhash.pen'));
      expect(expectedFile.existsSync(), isTrue);

      final loaded = await TbpStorageService.instance.loadPenStrokes(
        tbpFolder,
        dhash,
        classId: '1반',
      );
      expect(loaded.length, 1);
      expect(loaded.first.color, const Color(0xFF00F5D4));

      // 2. 하위 호환 폴백 탐색 확인 (루트에 legacy_dhash.pen이 있는 경우)
      const legacyHash = 'legacy_789';
      final legacyFile = File(p.join(tbpFolder, '$legacyHash.pen'));
      await legacyFile.writeAsString(jsonEncode(strokes.map((s) => s.toJson()).toList()));

      final loadedFallback = await TbpStorageService.instance.loadPenStrokes(
        tbpFolder,
        legacyHash,
      );
      expect(loadedFallback.length, 1);
      expect(loadedFallback.first.color, const Color(0xFF00F5D4));
    });
  });

  group('TbpDhashEngine Message Processing Tests', () {
    test('onDhashMessage parses dhashResult correctly', () {
      String? detectedHash;
      final engine = TbpDhashEngine(
        onDhashChanged: (hash) {
          detectedHash = hash;
        },
      );

      const jsonMsg = '{"type":"dhashResult","hash":"ff00ff00ff00ff00"}';
      engine.onDhashMessage(jsonMsg);

      expect(detectedHash, 'ff00ff00ff00ff00');
      engine.dispose();
    });

    test('onDhashMessage parses requestNavigation correctly', () {
      bool? navigatedNext;
      final engine = TbpDhashEngine(
        onDhashChanged: (_) {},
        onNavigationRequested: (isNext) {
          navigatedNext = isNext;
        },
      );

      engine.onDhashMessage('{"type":"requestNavigation","isNext":true}');
      expect(navigatedNext, isTrue);

      engine.onDhashMessage('{"type":"requestNavigation","isNext":false}');
      expect(navigatedNext, isFalse);
      engine.dispose();
    });
  });
}

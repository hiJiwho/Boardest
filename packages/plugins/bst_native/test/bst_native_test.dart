import 'package:flutter_test/flutter_test.dart';
import 'package:bst_native/bst_native.dart';

void main() {
  group('HwpHelper & PptHelper Native Tests', () {
    test('HwpHelper handles execution gracefully', () async {
      final result = await HwpHelper.run(['--help']);
      // On non-windows/test runner without executable, should return null safely without throwing
      expect(result == null || result.exitCode is int, isTrue);

      final process = await HwpHelper.start(['--version']);
      expect(process == null || process.pid is int, isTrue);
    });

    test('PptHelper handles execution gracefully', () async {
      final result = await PptHelper.run(['--help']);
      expect(result == null || result.exitCode is int, isTrue);

      final process = await PptHelper.start(['--version']);
      expect(process == null || process.pid is int, isTrue);
    });
  });
}

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_auth/bst_auth.dart';

void main() {
  group('TotpService Adversarial & Stress Challenge Tests', () {
    const testSecret = 'JBSWY3DPEHPK3PXP'; // Base32 for "Hello!\xde\xad\xbe\xef"

    test('RFC 6238 & Base32 decoding resilience on malformed inputs', () {
      // 1. Lowercase base32 string
      final decodedLower = TotpService.base32Decode('jbswy3dpehpk3pxp');
      final decodedUpper = TotpService.base32Decode('JBSWY3DPEHPK3PXP');
      expect(decodedLower, equals(decodedUpper));

      // 2. Base32 with '=' padding
      final decodedPadded = TotpService.base32Decode('JBSWY3DPEHPK3PXP====');
      expect(decodedPadded, equals(decodedUpper));

      // 3. Base32 with invalid characters (spaces, dashes, 8, 9, special chars)
      final decodedDirty = TotpService.base32Decode('JBSW-Y3DP EHPK!3PXP#89');
      expect(decodedDirty, equals(decodedUpper));

      // 4. Empty string secret
      final emptyDecoded = TotpService.base32Decode('');
      expect(emptyDecoded, isEmpty);

      // 5. Code generation with empty secret
      expect(TotpService.generateOtpForWindow('', 12345), equals('000000'));
      expect(TotpService.generateCurrentOtp(''), equals('000000'));
    });

    test('Clock drift tolerance (±1 step) and strict window bounding', () {
      final baseTime = DateTime.utc(2026, 8, 21, 12, 0, 0); // epoch = 1787313600
      final currentWindow = TotpService.getCurrentWindow(time: baseTime, step: 30);
      final currentOtp = TotpService.generateOtpForWindow(testSecret, currentWindow);
      final prevOtp = TotpService.generateOtpForWindow(testSecret, currentWindow - 1);
      final nextOtp = TotpService.generateOtpForWindow(testSecret, currentWindow + 1);
      final farPastOtp = TotpService.generateOtpForWindow(testSecret, currentWindow - 2);
      final farFutureOtp = TotpService.generateOtpForWindow(testSecret, currentWindow + 2);

      // Current OTP verification
      final resCurr = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: currentOtp,
        lastConsumedWindow: currentWindow - 2,
        time: baseTime,
      );
      expect(resCurr.isValid, isTrue);
      expect(resCurr.matchedWindow, equals(currentWindow));

      // Previous window OTP verification (Drift -1)
      final resPrev = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: prevOtp,
        lastConsumedWindow: currentWindow - 2,
        time: baseTime,
      );
      expect(resPrev.isValid, isTrue);
      expect(resPrev.matchedWindow, equals(currentWindow - 1));

      // Next window OTP verification (Drift +1)
      final resNext = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: nextOtp,
        lastConsumedWindow: currentWindow - 2,
        time: baseTime,
      );
      expect(resNext.isValid, isTrue);
      expect(resNext.matchedWindow, equals(currentWindow + 1));

      // Far past OTP verification (Drift -2) -> Must REJECT
      final resFarPast = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: farPastOtp,
        lastConsumedWindow: currentWindow - 5,
        time: baseTime,
      );
      expect(resFarPast.isValid, isFalse, reason: 'Drift -2 must be rejected');

      // Far future OTP verification (Drift +2) -> Must REJECT
      final resFarFuture = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: farFutureOtp,
        lastConsumedWindow: currentWindow - 5,
        time: baseTime,
      );
      expect(resFarFuture.isValid, isFalse, reason: 'Drift +2 must be rejected');
    });

    test('Replay attack protection and single-use consumption guarantee', () {
      final baseTime = DateTime.utc(2026, 8, 21, 12, 0, 0);
      final currentWindow = TotpService.getCurrentWindow(time: baseTime, step: 30);
      final currentOtp = TotpService.generateOtpForWindow(testSecret, currentWindow);

      // First validation: should succeed
      final res1 = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: currentOtp,
        lastConsumedWindow: 0,
        time: baseTime,
      );
      expect(res1.isValid, isTrue);
      expect(res1.matchedWindow, equals(currentWindow));

      // Replay immediate: lastConsumedWindow updated to currentWindow
      final res2 = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: currentOtp,
        lastConsumedWindow: currentWindow,
        time: baseTime,
      );
      expect(res2.isValid, isFalse);
      expect(res2.reason, contains('이미 사용된 1회용 OTP'));

      // Next window should still succeed
      final nextWindow = currentWindow + 1;
      final nextOtp = TotpService.generateOtpForWindow(testSecret, nextWindow);
      final nextTime = baseTime.add(const Duration(seconds: 30));

      final res3 = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: nextOtp,
        lastConsumedWindow: currentWindow,
        time: nextTime,
      );
      expect(res3.isValid, isTrue);
      expect(res3.matchedWindow, equals(nextWindow));
    });

    test('Boundary second transitions: exactly at window step boundaries', () {
      // Step boundary at 30 seconds
      final t0 = DateTime.utc(2026, 8, 21, 12, 0, 29);
      final t1 = DateTime.utc(2026, 8, 21, 12, 0, 30);
      final t2 = DateTime.utc(2026, 8, 21, 12, 0, 31);

      final w0 = TotpService.getCurrentWindow(time: t0, step: 30);
      final w1 = TotpService.getCurrentWindow(time: t1, step: 30);
      final w2 = TotpService.getCurrentWindow(time: t2, step: 30);

      expect(w1, equals(w0 + 1));
      expect(w2, equals(w1));

      expect(TotpService.getRemainingSeconds(time: t0, step: 30), equals(1));
      expect(TotpService.getRemainingSeconds(time: t1, step: 30), equals(30));
      expect(TotpService.getRemainingSeconds(time: t2, step: 30), equals(29));
    });

    test('OtpAuth URI generation and formatting with special characters in email and issuer', () {
      final uriStr = TotpService.getOtpAuthUri(
        secret: testSecret,
        email: 'teacher+special@boardest.com',
        issuer: 'Boardest Cloud & School',
        period: 30,
      );
      final uri = Uri.parse(uriStr);
      expect(uri.scheme, equals('otpauth'));
      expect(uri.host, equals('totp'));
      expect(uri.queryParameters['secret'], equals(testSecret));
      expect(uri.queryParameters['period'], equals('30'));
      expect(uri.queryParameters['digits'], equals('6'));
      expect(uri.queryParameters['issuer'], equals('Boardest Cloud & School'));
    });

    test('Stress secret generator length bounds and character space', () {
      for (final len in [16, 32, 64, 128]) {
        final secret = TotpService.generateSecret(length: len);
        expect(secret.length, equals(len));
        expect(RegExp(r'^[A-Z2-7]+$').hasMatch(secret), isTrue);
      }
    });
  });
}

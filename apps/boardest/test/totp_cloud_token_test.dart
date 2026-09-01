import 'package:flutter_test/flutter_test.dart';
import 'package:boardest/services/totp_service.dart';

void main() {
  group('🔐 Boardest TOTP & Cloud Token Zero-Trust Engine Tests', () {
    const testSecret = 'JBSWY3DPEHPK3PXP'; // Base32 RFC 4648 test secret

    test('1. Secret Base32 Generation & Format', () {
      final secret = TotpService.generateSecret(length: 32);
      expect(secret.length, equals(32));
      expect(RegExp(r'^[A-Z2-7]+$').hasMatch(secret), isTrue);
    });

    test('2. Deterministic OTP Generation for fixed window', () {
      final otp1 = TotpService.generateOtpForWindow(testSecret, 1000);
      final otp2 = TotpService.generateOtpForWindow(testSecret, 1000);
      expect(otp1, equals(otp2));
      expect(otp1.length, equals(6));
      expect(int.tryParse(otp1), isNotNull);
    });

    test('3. OTP Verification Success for current window', () {
      final currentOtp = TotpService.generateCurrentOtp(testSecret);
      final result = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: currentOtp,
        lastConsumedWindow: 0,
      );

      expect(result.isValid, isTrue);
      expect(result.matchedWindow, isNotNull);
      expect(result.reason, isNull);
    });

    test('4. OTP Verification Replay Attack Prevention (lastConsumedWindow)', () {
      final currentOtp = TotpService.generateCurrentOtp(testSecret);
      final currentWindow = TotpService.getCurrentWindow();

      // First consumption succeeds
      final firstResult = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: currentOtp,
        lastConsumedWindow: currentWindow - 10,
      );
      expect(firstResult.isValid, isTrue);

      // Replay of the exact same window MUST fail!
      final replayResult = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: currentOtp,
        lastConsumedWindow: firstResult.matchedWindow,
      );
      expect(replayResult.isValid, isFalse);
      expect(replayResult.reason, contains('이미 사용된'));
    });

    test('5. Invalid OTP Rejection', () {
      final result = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: '999999',
        lastConsumedWindow: 0,
      );
      expect(result.isValid, isFalse);
    });

    test('6. Window Drift Tolerance (30s & 60s windows)', () {
      final currentWindow = TotpService.getCurrentWindow(step: 60);
      final prevOtp = TotpService.generateOtpForWindow(testSecret, currentWindow - 1);
      final nextOtp = TotpService.generateOtpForWindow(testSecret, currentWindow + 1);

      final prevResult = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: prevOtp,
        lastConsumedWindow: 0,
      );
      expect(prevResult.isValid, isTrue);

      final nextResult = TotpService.verifyOtp(
        secret: testSecret,
        inputOtp: nextOtp,
        lastConsumedWindow: 0,
      );
      expect(nextResult.isValid, isTrue);
    });
  });
}

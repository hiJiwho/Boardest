import 'package:flutter_test/flutter_test.dart';
import 'package:bst_auth/bst_auth.dart';

void main() {
  test('TOTP generation and verification test for teacher lite', () {
    final secret = TotpService.generateSecret();
    expect(secret.length, 32);

    final otp = TotpService.generateCurrentOtp(secret, step: 60);
    expect(otp.length, 6);
    expect(int.tryParse(otp), isNotNull);

    final result = TotpService.verifyOtp(
      secret: secret,
      inputOtp: otp,
      lastConsumedWindow: 0,
    );
    expect(result.isValid, isTrue);
  });
}

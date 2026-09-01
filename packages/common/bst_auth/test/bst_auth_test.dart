import 'package:flutter_test/flutter_test.dart';
import 'package:bst_auth/bst_auth.dart';

void main() {
  group('TotpService Unit Tests', () {
    test('generateSecret produces valid 32-character base32 secret', () {
      final secret = TotpService.generateSecret();
      expect(secret.length, 32);
      expect(RegExp(r'^[A-Z2-7]+$').hasMatch(secret), isTrue);
    });

    test('generateSecret with custom length', () {
      final secret = TotpService.generateSecret(length: 16);
      expect(secret.length, 16);
      expect(RegExp(r'^[A-Z2-7]+$').hasMatch(secret), isTrue);
    });

    test('base32Decode correctly decodes base32 strings', () {
      final decoded = TotpService.base32Decode('JBSWY3DPEHPK3PXP');
      expect(decoded, isNotEmpty);
      expect(decoded.length, equals(10));
    });

    test('getCurrentWindow and getRemainingSeconds', () {
      final fixedTime = DateTime.utc(2026, 8, 21, 12, 0, 15);
      final window30 = TotpService.getCurrentWindow(time: fixedTime, step: 30);
      final remaining30 = TotpService.getRemainingSeconds(time: fixedTime, step: 30);
      expect(remaining30, 15);

      final window60 = TotpService.getCurrentWindow(time: fixedTime, step: 60);
      final remaining60 = TotpService.getRemainingSeconds(time: fixedTime, step: 60);
      expect(remaining60, 45);
      expect(window30, isA<int>());
      expect(window60, isA<int>());
    });

    test('generateOtpForWindow generates 6-digit numeric string', () {
      const testSecret = 'JBSWY3DPEHPK3PXP';
      final otp = TotpService.generateOtpForWindow(testSecret, 1234567);
      expect(otp.length, 6);
      expect(int.tryParse(otp), isNotNull);
    });

    test('generateOtpForWindow returns 000000 on empty secret', () {
      expect(TotpService.generateOtpForWindow('', 100), '000000');
    });

    test('generateCurrentOtp generates consistent OTP for same timestamp', () {
      const testSecret = 'JBSWY3DPEHPK3PXP';
      final time = DateTime.utc(2026, 8, 21, 10, 30, 0);
      final otp1 = TotpService.generateCurrentOtp(testSecret, time: time);
      final otp2 = TotpService.generateCurrentOtp(testSecret, time: time);
      expect(otp1, equals(otp2));
      expect(otp1.length, 6);
    });

    test('getOtpAuthUri generates standard otpauth URI', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final uri = TotpService.getOtpAuthUri(
        secret: secret,
        email: 'teacher@school.kr',
        issuer: 'Boardest',
      );
      expect(uri, contains('otpauth://totp/'));
      expect(uri, contains('secret=JBSWY3DPEHPK3PXP'));
      expect(uri, contains('issuer=Boardest'));
      expect(uri, contains('digits=6'));
    });

    test('getQrCodeImageUrl generates HTTPS QR URL', () {
      final qrUrl = TotpService.getQrCodeImageUrl('otpauth://totp/test?secret=XYZ');
      expect(qrUrl, startsWith('https://api.qrserver.com/v1/create-qr-code/'));
      expect(qrUrl, contains('size=250x250'));
    });

    test('verifyOtp validates correct current OTP and rejects used/consumed window', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final fixedTime = DateTime.utc(2026, 8, 21, 12, 0, 0);
      final validOtp = TotpService.generateCurrentOtp(secret, time: fixedTime, step: 30);
      final currentWindow = TotpService.getCurrentWindow(time: fixedTime, step: 30);

      // 1. Valid OTP with no prior consumed window
      final result1 = TotpService.verifyOtp(
        secret: secret,
        inputOtp: validOtp,
        lastConsumedWindow: 0,
        time: fixedTime,
      );
      expect(result1.isValid, isTrue);
      expect(result1.matchedWindow, equals(currentWindow));
      expect(result1.reason, isNull);

      // 2. Replay attack prevention: same window already consumed
      final result2 = TotpService.verifyOtp(
        secret: secret,
        inputOtp: validOtp,
        lastConsumedWindow: currentWindow,
        time: fixedTime,
      );
      expect(result2.isValid, isFalse);
      expect(result2.reason, contains('이미 사용된 1회용 OTP입니다'));

      // 3. Incorrect OTP
      final result3 = TotpService.verifyOtp(
        secret: secret,
        inputOtp: '999999' == validOtp ? '111111' : '999999',
        lastConsumedWindow: 0,
        time: fixedTime,
      );
      expect(result3.isValid, isFalse);
      expect(result3.reason, contains('일치하지 않습니다'));
    });
  });

  group('CanvaOAuthService Unit Tests', () {
    test('generateRandomString produces base64url string of requested length', () {
      final canvaService = CanvaOAuthService();
      final str32 = canvaService.generateRandomString(32);
      final str128 = canvaService.generateRandomString(128);

      expect(str32.length, 32);
      expect(str128.length, 128);
    });

    test('generateCodeChallenge generates valid S256 PKCE challenge', () {
      final canvaService = CanvaOAuthService();
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final challenge = canvaService.generateCodeChallenge(verifier);

      expect(challenge, isNotEmpty);
      expect(challenge.contains('='), isFalse);
    });

    test('buildAuthUrl constructs correct Canva authorization URI', () {
      final canvaService = CanvaOAuthService();
      final uri = canvaService.buildAuthUrl(
        codeChallenge: 'test_challenge_123',
        state: 'test_state_456',
        customClientId: 'custom_canva_id',
        customRedirectUri: 'http://127.0.0.1:1217/callback',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.canva.com');
      expect(uri.path, '/api/oauth/authorize');
      expect(uri.queryParameters['response_type'], 'code');
      expect(uri.queryParameters['client_id'], 'custom_canva_id');
      expect(uri.queryParameters['redirect_uri'], 'http://127.0.0.1:1217/callback');
      expect(uri.queryParameters['code_challenge'], 'test_challenge_123');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(uri.queryParameters['state'], 'test_state_456');
    });
  });

  group('SessionManager Unit Tests', () {
    test('SessionManager starts and disposes cleanly', () {
      final sessionManager = SessionManager();
      sessionManager.startSession();
      sessionManager.resetSession();
      sessionManager.dispose();
      // Test passed without unhandled timer exception
      expect(true, isTrue);
    });
  });
}

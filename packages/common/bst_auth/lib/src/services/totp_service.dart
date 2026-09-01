import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'network_time_service.dart';

/// RFC 6238 Time-Based One-Time Password (TOTP) 엔진
/// - Google Authenticator / Microsoft Authenticator / Boardest App 호환
/// - 표준 30초 주기 및 60초 주기 지원
/// - 6자리 숫자 OTP
class TotpService {
  static const int stepSeconds = 60; // 1분 (60초) 주기
  static const int digits = 6;

  /// 32글자 Base32 시크릿 키 생성 (RFC 4648 Base32)
  static String generateSecret({int length = 32}) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Base32 문자열 디코딩
  static Uint8List base32Decode(String base32) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final cleaned = base32.toUpperCase().replaceAll('=', '');
    final bits = <int>[];
    for (int i = 0; i < cleaned.length; i++) {
      final val = chars.indexOf(cleaned[i]);
      if (val == -1) continue;
      for (int b = 4; b >= 0; b--) {
        bits.add((val >> b) & 1);
      }
    }
    final bytes = <int>[];
    for (int i = 0; i + 8 <= bits.length; i += 8) {
      int byteVal = 0;
      for (int b = 0; b < 8; b++) {
        byteVal = (byteVal << 1) | bits[i + b];
      }
      bytes.add(byteVal);
    }
    return Uint8List.fromList(bytes);
  }

  /// 현재 시각의 윈도우 인덱스 (기본: 30초 또는 지정 주기)
  static int getCurrentWindow({DateTime? time, int step = stepSeconds}) {
    final now = (time ?? NetworkTimeService.instance.now).toUtc().millisecondsSinceEpoch ~/ 1000;
    return now ~/ step;
  }

  /// 현재 주기에서 남은 시간(초)
  static int getRemainingSeconds({DateTime? time, int step = stepSeconds}) {
    final now = (time ?? NetworkTimeService.instance.now).toUtc().millisecondsSinceEpoch ~/ 1000;
    return step - (now % step);
  }

  /// 특정 윈도우 인덱스에 대한 6자리 OTP 코드 생성 (RFC 6238)
  static String generateOtpForWindow(String secret, int window) {
    if (secret.isEmpty) return '000000';
    try {
      final key = base32Decode(secret);
      final msg = Uint8List(8);
      var w = window;
      for (int i = 7; i >= 0; i--) {
        msg[i] = w & 0xff;
        w >>= 8;
      }
      final hmac = Hmac(sha1, key);
      final hash = hmac.convert(msg).bytes;
      final offset = hash[hash.length - 1] & 0x0f;
      final binary = ((hash[offset] & 0x7f) << 24) |
          ((hash[offset + 1] & 0xff) << 16) |
          ((hash[offset + 2] & 0xff) << 8) |
          (hash[offset + 3] & 0xff);
      final otp = binary % 1000000;
      return otp.toString().padLeft(digits, '0');
    } catch (_) {
      return '000000';
    }
  }

  /// 현재 시점의 실시간 OTP 6자리 코드
  static String generateCurrentOtp(String secret, {DateTime? time, int step = stepSeconds}) {
    return generateOtpForWindow(secret, getCurrentWindow(time: time, step: step));
  }

  /// Google Authenticator / OTP 앱 등록용 표준 otpauth:// URI 생성
  static String getOtpAuthUri({
    required String secret,
    required String email,
    String issuer = 'Boardest',
    int period = 30,
  }) {
    final label = Uri.encodeComponent('$issuer:$email');
    return 'otpauth://totp/$label?secret=$secret&issuer=${Uri.encodeComponent(issuer)}&period=$period&digits=6';
  }

  /// Google Authenticator QR 코드 이미지 URL 생성 (HTTPS)
  static String getQrCodeImageUrl(String otpAuthUri, {int size = 250}) {
    return 'https://api.qrserver.com/v1/create-qr-code/?size=${size}x$size&data=${Uri.encodeComponent(otpAuthUri)}';
  }

  /// OTP 검증 (Google Authenticator 30초 및 60초 주기 모두 지원, 단일 사용 1회성 소각 검사)
  static ({bool isValid, int matchedWindow, String? reason}) verifyOtp({
    required String secret,
    required String inputOtp,
    required int lastConsumedWindow,
    DateTime? time,
  }) {
    final cleanOtp = inputOtp.trim().replaceAll(' ', '');

    // 1. Google Authenticator 표준 30초 윈도우 검사 (±1 윈도우 허용)
    final currentWindow30 = getCurrentWindow(time: time, step: 30);
    final candidateWindows30 = [currentWindow30, currentWindow30 - 1, currentWindow30 + 1];

    for (final window in candidateWindows30) {
      final expectedOtp = generateOtpForWindow(secret, window);
      if (expectedOtp == cleanOtp) {
        if (window <= lastConsumedWindow) {
          return (
            isValid: false,
            matchedWindow: window,
            reason: '이미 사용된 1회용 OTP입니다. 다음 갱신 번호로 입력하세요.'
          );
        }
        return (
          isValid: true,
          matchedWindow: window,
          reason: null
        );
      }
    }

    // 2. 60초 윈도우 검사 (구버전 호환)
    final currentWindow60 = getCurrentWindow(time: time, step: 60);
    final candidateWindows60 = [currentWindow60, currentWindow60 - 1, currentWindow60 + 1];

    for (final window in candidateWindows60) {
      final expectedOtp = generateOtpForWindow(secret, window);
      if (expectedOtp == cleanOtp) {
        if (window <= lastConsumedWindow) {
          return (
            isValid: false,
            matchedWindow: window,
            reason: '이미 사용된 1회용 OTP입니다. 다음 갱신 번호로 입력하세요.'
          );
        }
        return (
          isValid: true,
          matchedWindow: window,
          reason: null
        );
      }
    }

    return (
      isValid: false,
      matchedWindow: -1,
      reason: '인증번호(OTP)가 일치하지 않습니다.'
    );
  }
}

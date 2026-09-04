import 'dart:convert';
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

  /// 이메일 기반 결정적 Base32 시크릿 키 생성 (어떤 클라이언트에서도 동일 계정이면 동일 Secret 산출)
  static String generateDeterministicSecret(String email, {int length = 32}) {
    if (email.trim().isEmpty) return generateSecret(length: length);
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final bytes = sha256.convert(utf8.encode(email.trim().toLowerCase())).bytes;
    final sb = StringBuffer();
    for (int i = 0; i < length; i++) {
      sb.write(chars[bytes[i % bytes.length] % chars.length]);
    }
    return sb.toString();
  }

  /// Base32 문자열 디코딩
  static Uint8List _base32Decode(String base32) {
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

  /// 현재 시각의 윈도우 인덱스 (기본: 30초 주기, 시간 디버깅과 무관하게 무조건 실제 현재 시각 DateTime.now() 기준)
  static int getCurrentWindow({DateTime? time, int step = stepSeconds}) {
    final now = (time ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    return now ~/ step;
  }

  /// 현재 주기에서 남은 시간(초)
  static int getRemainingSeconds({DateTime? time, int step = stepSeconds}) {
    final now = (time ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    return step - (now % step);
  }

  /// 특정 윈도우 인덱스에 대한 6자리 OTP 코드 생성 (RFC 6238)
  static String generateOtpForWindow(String secret, int window) {
    if (secret.isEmpty) return '000000';
    try {
      final key = _base32Decode(secret);
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

  /// 특정 윈도우 인덱스에 대한 N자리 (6자리 또는 8자리) OTP 코드 생성 (RFC 6238)
  static String generateOtpForDigits(String secret, int window, {int digits = 6}) {
    if (secret.isEmpty) return '0'.padLeft(digits, '0');
    try {
      final key = _base32Decode(secret);
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
      final divisor = digits == 8 ? 100000000 : 1000000;
      final otp = binary % divisor;
      return otp.toString().padLeft(digits, '0');
    } catch (_) {
      return '0'.padLeft(digits, '0');
    }
  }

  /// 8자리 자동 로그인 전용 실시간 OTP 코드 생성
  static String generate8DigitOtp(String secret, {DateTime? time, int step = stepSeconds}) {
    return generateOtpForDigits(secret, getCurrentWindow(time: time, step: step), digits: 8);
  }

  /// 4자리 TOTP 검증 (±1 윈도우 허용)
  static ({bool isValid, int matchedWindow, String? reason}) verify4DigitOtp({
    required String secret,
    required String inputOtp4,
    required int lastConsumedWindow,
    DateTime? time,
    int step = 60,
  }) {
    final cleanOtp = inputOtp4.trim();
    final currentWindow = getCurrentWindow(time: time, step: step);
    final candidateWindows = [currentWindow, currentWindow - 1, currentWindow + 1];

    for (final window in candidateWindows) {
      final expectedOtp = generateOtpForWindow(secret, window);
      // 4자리 비교 (끝 4자리 또는 앞 4자리)
      final expected4 = generate4DigitOtp(secret, time: DateTime.fromMillisecondsSinceEpoch(window * step * 1000), step: step);
      if (expected4 == cleanOtp) {
        if (window <= lastConsumedWindow) {
          return (isValid: false, matchedWindow: window, reason: '이미 사용된 1회용 OTP입니다.');
        }
        return (isValid: true, matchedWindow: window, reason: null);
      }
    }
    return (isValid: false, matchedWindow: -1, reason: 'OTP 번호가 일치하지 않습니다.');
  }

  /// 8자리 자동 로그인 OTP 검증 (±1 윈도우 허용)
  static ({bool isValid, int matchedWindow, String? reason}) verify8DigitOtp({
    required String secret,
    required String inputOtp8,
    required int lastConsumedWindow,
    DateTime? time,
    int step = 30,
  }) {
    final cleanOtp = inputOtp8.trim();
    final currentWindow = getCurrentWindow(time: time, step: step);
    final candidateWindows = [currentWindow, currentWindow - 1, currentWindow + 1];

    for (final window in candidateWindows) {
      final expected8 = generateOtpForDigits(secret, window, digits: 8);
      if (expected8 == cleanOtp) {
        if (window <= lastConsumedWindow) {
          return (isValid: false, matchedWindow: window, reason: '이미 사용된 1회용 OTP입니다.');
        }
        return (isValid: true, matchedWindow: window, reason: null);
      }
    }
    return (isValid: false, matchedWindow: -1, reason: '8자리 자동 OTP가 일치하지 않습니다.');
  }

  /// 2(교사 ID) + 4(OTP) Steganography 6자리 또는 8자리 또는 표준 6자리 통합 검증
  static ({bool isValid, int matchedWindow, String? reason, String? parsedCloudId}) verifyComprehensiveOtp({
    required String secret,
    required String inputOtp,
    required int lastConsumedWindow,
    DateTime? time,
  }) {
    final clean = inputOtp.trim().replaceAll(' ', '');

    // 1. 8자리 Auto OTP
    if (clean.length == 8) {
      final res8 = verify8DigitOtp(secret: secret, inputOtp8: clean, lastConsumedWindow: lastConsumedWindow, time: time);
      return (isValid: res8.isValid, matchedWindow: res8.matchedWindow, reason: res8.reason, parsedCloudId: null);
    }

    // 2. 6자리 Steganography (2자리 교사 ID + 4자리 OTP)
    if (clean.length == 6) {
      final parsed = parseSteganography6(clean, time: time);
      final res4 = verify4DigitOtp(secret: secret, inputOtp4: parsed.otp, lastConsumedWindow: lastConsumedWindow, time: time);
      if (res4.isValid) {
        return (isValid: true, matchedWindow: res4.matchedWindow, reason: null, parsedCloudId: parsed.cloudId);
      }
      // 표준 6자리 RFC 6238 fallback
      final resStd = verifyOtp(secret: secret, inputOtp: clean, lastConsumedWindow: lastConsumedWindow, time: time);
      if (resStd.isValid) {
        return (isValid: true, matchedWindow: resStd.matchedWindow, reason: null, parsedCloudId: null);
      }
    }

    // 3. 4자리 순수 OTP
    if (clean.length == 4) {
      final res4 = verify4DigitOtp(secret: secret, inputOtp4: clean, lastConsumedWindow: lastConsumedWindow, time: time);
      return (isValid: res4.isValid, matchedWindow: res4.matchedWindow, reason: res4.reason, parsedCloudId: null);
    }

    return (isValid: false, matchedWindow: -1, reason: '유효한 OTP 형식이 아닙니다.', parsedCloudId: null);
  }

  /// 6자리 동적 자릿수 셔플 (Steganography) 매핑 테이블
  static const Map<int, ({int id1, int id2, List<int> otp})> steganoMap = {
    0: (id1: 0, id2: 3, otp: [1, 2, 4, 5]), // Y1 X1 X2 Y2 X3 X4
    1: (id1: 1, id2: 4, otp: [0, 2, 3, 5]), // X1 Y1 X2 X3 Y2 X4
    2: (id1: 2, id2: 5, otp: [0, 1, 3, 4]), // X1 X2 Y1 X3 X4 Y2
    3: (id1: 0, id2: 4, otp: [1, 2, 3, 5]), // Y1 X1 X2 X3 Y2 X4
    4: (id1: 1, id2: 5, otp: [0, 2, 3, 4]), // X1 Y1 X2 X3 X4 Y2
  };

  /// 4자리 TOTP 생성 (60초 주기)
  static String generate4DigitOtp(String secret, {DateTime? time, int step = 60}) {
    if (secret.isEmpty) return '0000';
    try {
      final window = getCurrentWindow(time: time, step: step);
      final key = _base32Decode(secret);
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
      final otp = binary % 10000;
      return otp.toString().padLeft(4, '0');
    } catch (_) {
      return '0000';
    }
  }

  /// 6자리 동적 자릿수 셔플 (Steganography) 생성 (무조건 실제 현재 시각 DateTime.now() 기준)
  static String encodeSteganography6(String cloudId2, String otp4, {DateTime? time}) {
    final now = time ?? DateTime.now();
    final m = now.minute % 5;
    final cfg = steganoMap[m]!;
    final y = cloudId2.padLeft(2, '0').substring(0, 2);
    final x = otp4.padLeft(4, '0').substring(0, 4);
    final arr = List<String>.filled(6, '0');
    arr[cfg.id1] = y[0];
    arr[cfg.id2] = y[1];
    arr[cfg.otp[0]] = x[0];
    arr[cfg.otp[1]] = x[1];
    arr[cfg.otp[2]] = x[2];
    arr[cfg.otp[3]] = x[3];
    return arr.join('');
  }

  /// 6자리 동적 자릿수 셔플 (Steganography) 파싱 (무조건 실제 현재 시각 DateTime.now() 기준)
  static ({String cloudId, String otp}) parseSteganography6(String code, {DateTime? time}) {
    final now = time ?? DateTime.now();
    final m = now.minute % 5;
    final cfg = steganoMap[m]!;
    final clean = code.trim().padLeft(6, '0');
    final cloudId = clean[cfg.id1] + clean[cfg.id2];
    final otp = clean[cfg.otp[0]] + clean[cfg.otp[1]] + clean[cfg.otp[2]] + clean[cfg.otp[3]];
    return (cloudId: cloudId, otp: otp);
  }
}

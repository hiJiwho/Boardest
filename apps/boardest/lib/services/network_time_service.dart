import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 외부 네트워크 표준 시각 동기화 서비스
/// - 로컬 클라이언트 기기의 시스템 시각 오차를 보정하여 정확한 UTC 표준 시각을 유지합니다.
/// - 다중 외부 시간 API 및 HTTP Date Header Fallback 지원
class NetworkTimeService {
  static final NetworkTimeService instance = NetworkTimeService._internal();
  NetworkTimeService._internal() {
    syncTime();
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (_) => syncTime());
  }

  Timer? _syncTimer;
  Duration _offset = Duration.zero;
  bool _isSynced = false;

  /// 현재 시간 오프셋
  Duration get offset => _offset;

  /// 동기화 성공 여부
  bool get isSynced => _isSynced;

  /// 시스템 시각에 네트워크 오프셋을 더한 실시간 보정 시각
  DateTime get now => DateTime.now().add(_offset);

  /// 시스템 시각에 네트워크 오프셋을 더한 실시간 보정 UTC 시각
  DateTime get nowUtc => DateTime.now().toUtc().add(_offset);

  /// 외부 서버를 통한 시각 동기화 실행 (다중 Fallback)
  Future<DateTime> syncTime() async {
    // 1. Cloudflare Worker API
    try {
      final start = DateTime.now();
      final res = await http.get(
        Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/time'),
      ).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final serverIso = data['datetime'] ?? data['utc_datetime'] ?? data['time'];
        if (serverIso != null) {
          final serverTime = DateTime.parse(serverIso.toString()).toUtc();
          final rtt = DateTime.now().difference(start);
          _applyServerTime(serverTime.add(rtt ~/ 2));
          return now;
        }
      }
    } catch (_) {}

    // 2. WorldTimeAPI Fallback
    try {
      final start = DateTime.now();
      final res = await http.get(
        Uri.parse('https://worldtimeapi.org/api/timezone/Etc/UTC'),
      ).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final serverIso = data['utc_datetime'];
        if (serverIso != null) {
          final serverTime = DateTime.parse(serverIso.toString()).toUtc();
          final rtt = DateTime.now().difference(start);
          _applyServerTime(serverTime.add(rtt ~/ 2));
          return now;
        }
      }
    } catch (_) {}

    // 3. timeapi.io Fallback
    try {
      final start = DateTime.now();
      final res = await http.get(
        Uri.parse('https://timeapi.io/api/time/current/zone?timeZone=UTC'),
      ).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final serverIso = data['dateTime'];
        if (serverIso != null) {
          final serverTime = DateTime.parse(serverIso.toString()).toUtc();
          final rtt = DateTime.now().difference(start);
          _applyServerTime(serverTime.add(rtt ~/ 2));
          return now;
        }
      }
    } catch (_) {}

    // 4. HTTP Date Header Fallback (Google)
    try {
      final start = DateTime.now();
      final res = await http.head(
        Uri.parse('https://www.google.com/generate_204'),
      ).timeout(const Duration(seconds: 3));

      final dateHeader = res.headers['date'];
      if (dateHeader != null && dateHeader.isNotEmpty) {
        final serverTime = _parseHttpDate(dateHeader);
        if (serverTime != null) {
          final rtt = DateTime.now().difference(start);
          _applyServerTime(serverTime.add(rtt ~/ 2));
          return now;
        }
      }
    } catch (_) {}

    return now;
  }

  void _applyServerTime(DateTime serverUtc) {
    final localUtc = DateTime.now().toUtc();
    _offset = serverUtc.difference(localUtc);
    _isSynced = true;
    debugPrint('[NetworkTimeService] ⏱️ 시각 동기화 완료: offset=${_offset.inMilliseconds}ms');
  }

  static DateTime? _parseHttpDate(String date) {
    try {
      const months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
      };
      final parts = date.split(' ');
      if (parts.length >= 5) {
        final day = int.parse(parts[1]);
        final month = months[parts[2]]!;
        final year = int.parse(parts[3]);
        final timeParts = parts[4].split(':');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final second = int.parse(timeParts[2]);
        return DateTime.utc(year, month, day, hour, minute, second);
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}

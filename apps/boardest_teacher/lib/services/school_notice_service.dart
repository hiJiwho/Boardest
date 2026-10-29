import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/school_notice.dart';

/// 학교 행사 및 공지 광고판 서비스 (RTDB 동기화 + 48시간 경과 건 자동 삭제)
class SchoolNoticeService {
  static final SchoolNoticeService instance = SchoolNoticeService._internal();
  SchoolNoticeService._internal();

  static const String _rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com/school_notices';
  final ValueNotifier<List<SchoolNotice>> noticesNotifier = ValueNotifier<List<SchoolNotice>>([]);

  List<SchoolNotice> get notices => noticesNotifier.value;

  String _cleanCode(String code) {
    final s = code.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    return s.isEmpty ? 'default' : s;
  }

  /// 공지 / 행사 목록 불러오기 (만료 48시간 경과 건 자동 제거 & RTDB 삭제)
  Future<List<SchoolNotice>> loadNotices({required String schoolCode}) async {
    final effectiveCode = _cleanCode(schoolCode);
    final url = '$_rtdbBase/$effectiveCode.json';

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.body != 'null') {
        final data = json.decode(res.body);
        final List<SchoolNotice> list = [];

        if (data is Map) {
          for (final entry in data.entries) {
            final val = entry.value;
            if (val is Map) {
              final notice = SchoolNotice.fromJson(Map<String, dynamic>.from(val));
              if (notice.isExpired48h) {
                // 48시간 지난 완료 건은 Firebase RTDB에서 자동 삭제
                _deleteNoticeSilently(effectiveCode, notice.id);
              } else {
                list.add(notice);
              }
            }
          }
        }

        // 최신 생성순 정렬
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        noticesNotifier.value = list;
        return list;
      } else {
        noticesNotifier.value = [];
      }
    } catch (e) {
      debugPrint('[SchoolNoticeService] loadNotices error: $e');
    }

    return noticesNotifier.value;
  }

  Future<void> _deleteNoticeSilently(String effectiveCode, String id) async {
    try {
      await http.delete(Uri.parse('$_rtdbBase/$effectiveCode/$id.json')).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// 행사 / 광고 등록 (사진 + 제목)
  Future<bool> addNotice({
    required String schoolCode,
    required SchoolNotice notice,
  }) async {
    final effectiveCode = _cleanCode(schoolCode);
    final url = '$_rtdbBase/$effectiveCode/${notice.id}.json';

    try {
      final res = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(notice.toJson()),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200 || res.statusCode == 204) {
        final current = List<SchoolNotice>.from(noticesNotifier.value);
        current.removeWhere((e) => e.id == notice.id);
        current.insert(0, notice);
        noticesNotifier.value = current;
        return true;
      }
    } catch (e) {
      debugPrint('[SchoolNoticeService] addNotice error: $e');
    }
    return false;
  }

  /// 행사 / 광고 삭제
  Future<bool> deleteNotice({
    required String schoolCode,
    required String noticeId,
  }) async {
    final effectiveCode = _cleanCode(schoolCode);
    final url = '$_rtdbBase/$effectiveCode/$noticeId.json';

    try {
      final res = await http.delete(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 || res.statusCode == 204) {
        final current = List<SchoolNotice>.from(noticesNotifier.value);
        current.removeWhere((e) => e.id == noticeId);
        noticesNotifier.value = current;
        return true;
      }
    } catch (e) {
      debugPrint('[SchoolNoticeService] deleteNotice error: $e');
    }
    return false;
  }
}

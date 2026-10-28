import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/assessment_item.dart';

/// 교사용 수행평가 / 과제 관리 서비스 (친환경 RTDB 동기화 + 로컬 캐시)
class AssessmentService {
  static final AssessmentService instance = AssessmentService._internal();
  AssessmentService._internal();

  static const String _rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com/assessments';
  final ValueNotifier<List<AssessmentItem>> assessmentsNotifier = ValueNotifier<List<AssessmentItem>>([]);

  List<AssessmentItem> get assessments => assessmentsNotifier.value;

  Future<List<AssessmentItem>> loadAssessments({
    required String schoolCode,
    required int grade,
    int? classNum,
  }) async {
    final sCode = schoolCode.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    final effectiveCode = sCode.isEmpty ? 'default' : sCode;
    final cacheKey = 'cached_teacher_assessments_${effectiveCode}_$grade';

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final decoded = json.decode(cachedJson) as List<dynamic>;
        final items = decoded.map((e) => AssessmentItem.fromJson(e as Map<String, dynamic>)).toList();
        _filterAndNotify(items, classNum);
      }
    } catch (e) {
      debugPrint('[Teacher AssessmentService] Cache error: $e');
    }

    try {
      final url = '$_rtdbBase/$effectiveCode/$grade.json';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.body != 'null') {
        final data = json.decode(res.body);
        final List<AssessmentItem> fetched = [];
        if (data is Map) {
          data.forEach((key, val) {
            if (val is Map) {
              fetched.add(AssessmentItem.fromJson(Map<String, dynamic>.from(val)));
            }
          });
        }
        fetched.sort((a, b) => a.dueDate.compareTo(b.dueDate));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(cacheKey, json.encode(fetched.map((e) => e.toJson()).toList()));
        _filterAndNotify(fetched, classNum);
        return assessmentsNotifier.value;
      }
    } catch (e) {
      debugPrint('[Teacher AssessmentService] RTDB fetch error: $e');
    }

    return assessmentsNotifier.value;
  }

  void _filterAndNotify(List<AssessmentItem> allItems, int? classNum) {
    if (classNum == null || classNum == 0) {
      assessmentsNotifier.value = allItems;
    } else {
      assessmentsNotifier.value = allItems.where((it) => it.classNum == 0 || it.classNum == classNum).toList();
    }
  }

  Future<bool> addAssessment({
    required String schoolCode,
    required AssessmentItem item,
  }) async {
    final sCode = schoolCode.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    final effectiveCode = sCode.isEmpty ? 'default' : sCode;
    final url = '$_rtdbBase/$effectiveCode/${item.grade}/${item.id}.json';

    try {
      final res = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(item.toJson()),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200 || res.statusCode == 204) {
        final current = List<AssessmentItem>.from(assessmentsNotifier.value);
        current.removeWhere((e) => e.id == item.id);
        current.add(item);
        current.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        assessmentsNotifier.value = current;
        return true;
      }
    } catch (e) {
      debugPrint('[Teacher AssessmentService] Add error: $e');
    }
    return false;
  }

  Future<bool> deleteAssessment({
    required String schoolCode,
    required int grade,
    required String itemId,
  }) async {
    final sCode = schoolCode.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    final effectiveCode = sCode.isEmpty ? 'default' : sCode;
    final url = '$_rtdbBase/$effectiveCode/$grade/$itemId.json';

    try {
      final res = await http.delete(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 || res.statusCode == 204) {
        final current = List<AssessmentItem>.from(assessmentsNotifier.value);
        current.removeWhere((e) => e.id == itemId);
        assessmentsNotifier.value = current;
        return true;
      }
    } catch (e) {
      debugPrint('[Teacher AssessmentService] Delete error: $e');
    }
    return false;
  }
}

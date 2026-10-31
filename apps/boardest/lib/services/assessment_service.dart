import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/assessment_item.dart';

/// 교실용 수행평가 / 과제 관리 서비스 (RTDB 실시간 동기화 + 반별 엄격 격리)
class AssessmentService {
  static final AssessmentService instance = AssessmentService._internal();
  AssessmentService._internal();

  static const String _rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com/assessments';
  final ValueNotifier<List<AssessmentItem>> assessmentsNotifier = ValueNotifier<List<AssessmentItem>>([]);
  int? _activeGrade;
  int? _activeClassNum;

  List<AssessmentItem> get assessments => assessmentsNotifier.value;

  /// 학교 코드/학교명을 표준 RTDB 키로 정규화 (예: '양동중학교', '48588', '44134', 'ydm' -> 'ydm')
  static String normalizeSchoolKey(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t.toLowerCase() == 'default') return 'ydm';
    final lower = t.toLowerCase();
    if (lower == 'ydm' ||
        t.contains('양동') ||
        lower == '44134' ||
        lower == '48588' ||
        lower == 'j100000690') {
      return 'ydm';
    }
    if (lower == 'demo' || t.contains('데모')) {
      return 'demo';
    }
    final ascii = lower.replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    if (ascii.isNotEmpty) return ascii;
    int h = 0;
    for (int i = 0; i < t.length; i++) {
      h = ((h << 5) - h) + t.codeUnitAt(i);
      h &= 0x7fffffff;
    }
    return 'sch_$h';
  }

  /// 로컬 캐시 로드 후 비동기 RTDB 동기화 (현재 학년·반에 해당하는 수행평가만 필터링)
  Future<List<AssessmentItem>> loadAssessments({
    required String schoolCode,
    required int grade,
    int? classNum,
  }) async {
    _activeGrade = grade;
    if (classNum != null && classNum > 0) {
      _activeClassNum = classNum;
    }
    final effectiveClassNum = classNum ?? _activeClassNum;
    final effectiveCode = normalizeSchoolKey(schoolCode);
    final cacheKey = 'cached_assessments_${effectiveCode}_${grade}_${effectiveClassNum ?? 0}';

    // 1. 로컬 캐시 즉시 반환
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final decoded = json.decode(cachedJson) as List<dynamic>;
        final items = decoded.map((e) => AssessmentItem.fromJson(e as Map<String, dynamic>)).toList();
        _filterAndNotify(items, grade, effectiveClassNum);
      }
    } catch (e) {
      debugPrint('[AssessmentService] Local cache read error: $e');
    }

    // 2. RTDB 비동기 실시간 페치
    try {
      final url = '$_rtdbBase/$effectiveCode/$grade.json';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final List<AssessmentItem> fetched = [];
        if (res.body != 'null' && res.body.isNotEmpty) {
          final data = json.decode(res.body);
          if (data is Map) {
            data.forEach((key, val) {
              if (val is Map) {
                final map = Map<String, dynamic>.from(val);
                if ((map['id']?.toString() ?? '').isEmpty) {
                  map['id'] = key.toString();
                }
                fetched.add(AssessmentItem.fromJson(map));
              }
            });
          }
        }
        fetched.sort((a, b) => a.dueDate.compareTo(b.dueDate));

        _filterAndNotify(fetched, grade, effectiveClassNum);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          cacheKey,
          json.encode(assessmentsNotifier.value.map((e) => e.toJson()).toList()),
        );
        return assessmentsNotifier.value;
      }
    } catch (e) {
      debugPrint('[AssessmentService] RTDB fetch error: $e');
    }

    return assessmentsNotifier.value;
  }

  void _filterAndNotify(List<AssessmentItem> allItems, int grade, int? classNum) {
    final filtered = allItems.where((it) {
      if (it.grade != grade && it.grade != 0) return false;
      if (classNum != null && classNum > 0) {
        // 교실에서 등록한 수행평가는 오직 해당 반(it.classNum == classNum)에만 표시!
        // 교사 앱에서 전체 공통(classNum == 0)으로 등록한 경우 또는 해당 반(classNum)으로 등록한 경우만 표시!
        if (it.classNum == classNum) return true;
        if (it.classNum == 0 && it.authorRole == 'teacher') return true;
        return false;
      }
      return true;
    }).toList();
    filtered.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    assessmentsNotifier.value = filtered;
  }

  /// 수행평가 등록 (교실/교사 공통, 교실에서 등록 시 해당 반 번호로 엄격 고정)
  Future<bool> addAssessment({
    required String schoolCode,
    required AssessmentItem item,
  }) async {
    final effectiveCode = normalizeSchoolKey(schoolCode);
    final effectiveClass = item.classNum > 0 ? item.classNum : (_activeClassNum ?? 1);
    final normalizedItem = item.copyWith(
      schoolCode: effectiveCode,
      classNum: effectiveClass,
    );
    final url = '$_rtdbBase/$effectiveCode/${normalizedItem.grade}/${normalizedItem.id}.json';

    try {
      final res = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(normalizedItem.toJson()),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200 || res.statusCode == 204) {
        final current = List<AssessmentItem>.from(assessmentsNotifier.value);
        current.removeWhere((e) => e.id == normalizedItem.id);
        if (_activeClassNum == null ||
            _activeClassNum == 0 ||
            normalizedItem.classNum == _activeClassNum) {
          current.add(normalizedItem);
          current.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        }
        assessmentsNotifier.value = current;
        return true;
      }
    } catch (e) {
      debugPrint('[AssessmentService] Add error: $e');
    }
    return false;
  }

  /// 수행평가 삭제
  Future<bool> deleteAssessment({
    required String schoolCode,
    required int grade,
    required String itemId,
  }) async {
    final effectiveCode = normalizeSchoolKey(schoolCode);
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
      debugPrint('[AssessmentService] Delete error: $e');
    }
    return false;
  }
}

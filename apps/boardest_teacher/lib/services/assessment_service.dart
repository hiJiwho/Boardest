import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/assessment_item.dart';

/// 교사용 수행평가 / 과제 관리 서비스 (RTDB 실시간 동기화 + 설치 학급 감지)
class AssessmentService {
  static final AssessmentService instance = AssessmentService._internal();
  AssessmentService._internal();

  static const String _rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com/assessments';
  static const String _eatCallsUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls.json';

  final ValueNotifier<List<AssessmentItem>> assessmentsNotifier = ValueNotifier<List<AssessmentItem>>([]);
  final List<AssessmentItem> _rawGradeItems = [];

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

  /// 학교 내 설치된 학급(1~12반) 목록을 학년별(1~3학년)로 조회
  Future<Map<int, Set<int>>> fetchInstalledClasses(String schoolCode) async {
    final effectiveCode = normalizeSchoolKey(schoolCode);
    final Map<int, Set<int>> result = {
      1: <int>{},
      2: <int>{},
      3: <int>{},
    };

    try {
      final res = await http.get(Uri.parse(_eatCallsUrl)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.body != 'null') {
        final data = json.decode(res.body);
        if (data is Map) {
          data.forEach((key, val) {
            if (val is! Map) return;
            final docId = key.toString();
            if (docId.isEmpty) return;

            final lowerDoc = docId.toLowerCase();
            if (val['isLite'] == true ||
                lowerDoc.contains('lite') ||
                lowerDoc.contains('local') ||
                lowerDoc.contains('special')) {
              return;
            }

            final docSchoolKey = normalizeSchoolKey(val['schoolCode']?.toString() ?? '');
            final docNameKey = normalizeSchoolKey(val['schoolName']?.toString() ?? '');
            final prefixMatch = lowerDoc.startsWith('${effectiveCode}_');

            if (!prefixMatch && docSchoolKey != effectiveCode && docNameKey != effectiveCode) {
              return;
            }

            int grade = int.tryParse(val['grade']?.toString() ?? '') ?? 0;
            int cls = int.tryParse(val['classNum']?.toString() ?? val['class']?.toString() ?? '') ?? 0;

            if (grade <= 0 || cls <= 0) {
              final parts = docId.split('_');
              if (parts.length >= 4) {
                grade = int.tryParse(parts[parts.length - 2]) ?? grade;
                cls = int.tryParse(parts[parts.length - 1]) ?? cls;
              }
            }

            if (grade >= 1 && grade <= 3 && cls >= 1 && cls <= 12) {
              result[grade]!.add(cls);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[Teacher AssessmentService] fetchInstalledClasses error: $e');
    }

    return result;
  }

  Future<List<AssessmentItem>> loadAssessments({
    required String schoolCode,
    required int grade,
    int? classNum,
  }) async {
    final effectiveCode = normalizeSchoolKey(schoolCode);
    final cacheKey = 'cached_teacher_assessments_${effectiveCode}_$grade';

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final decoded = json.decode(cachedJson) as List<dynamic>;
        final items = decoded.map((e) => AssessmentItem.fromJson(e as Map<String, dynamic>)).toList();
        _rawGradeItems
          ..clear()
          ..addAll(items);
        _filterAndNotify(items, grade, classNum);
      }
    } catch (e) {
      debugPrint('[Teacher AssessmentService] Cache error: $e');
    }

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
        _rawGradeItems
          ..clear()
          ..addAll(fetched);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(cacheKey, json.encode(fetched.map((e) => e.toJson()).toList()));
        _filterAndNotify(fetched, grade, classNum);
        return assessmentsNotifier.value;
      }
    } catch (e) {
      debugPrint('[Teacher AssessmentService] RTDB fetch error: $e');
    }

    return assessmentsNotifier.value;
  }

  void _filterAndNotify(List<AssessmentItem> allItems, int grade, int? classNum) {
    final gradeFiltered = allItems.where((it) => it.grade == grade || it.grade == 0).toList();
    if (classNum == null || classNum == 0) {
      assessmentsNotifier.value = gradeFiltered;
    } else {
      assessmentsNotifier.value = gradeFiltered
          .where((it) => it.classNum == 0 || it.classNum == classNum)
          .toList();
    }
  }

  Future<bool> addAssessment({
    required String schoolCode,
    required AssessmentItem item,
  }) async {
    final effectiveCode = normalizeSchoolKey(schoolCode);
    final normalizedItem = item.copyWith(schoolCode: effectiveCode);
    final url = '$_rtdbBase/$effectiveCode/${normalizedItem.grade}/${normalizedItem.id}.json';

    try {
      final res = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(normalizedItem.toJson()),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200 || res.statusCode == 204) {
        _rawGradeItems.removeWhere((e) => e.id == normalizedItem.id);
        _rawGradeItems.add(normalizedItem);
        _rawGradeItems.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        assessmentsNotifier.value = List<AssessmentItem>.from(_rawGradeItems);
        return true;
      }
    } catch (e) {
      debugPrint('[Teacher AssessmentService] Add error: $e');
    }
    return false;
  }

  /// 선택한 여러 학급에 한 번에 수행평가 등록
  Future<bool> addMultiClassAssessment({
    required String schoolCode,
    required AssessmentItem baseItem,
    required List<int> targetClasses,
  }) async {
    final effectiveCode = normalizeSchoolKey(schoolCode);
    final sortedClasses = targetClasses.where((c) => c >= 1 && c <= 12).toSet().toList()..sort();
    if (sortedClasses.isEmpty) {
      return false;
    }
    bool allSuccess = true;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < sortedClasses.length; i++) {
      final cNum = sortedClasses[i];
      final item = baseItem.copyWith(
        id: 'as_${nowMs}_${baseItem.grade}_$cNum',
        schoolCode: effectiveCode,
        classNum: cNum,
      );
      final ok = await addAssessment(schoolCode: effectiveCode, item: item);
      if (!ok) allSuccess = false;
    }
    await loadAssessments(schoolCode: effectiveCode, grade: baseItem.grade);
    return allSuccess;
  }

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
        _rawGradeItems.removeWhere((e) => e.id == itemId);
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

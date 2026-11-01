import 'dart:async';
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

  // ─── RTDB Server-Sent Events (SSE) Realtime Stream ───
  http.Client? _sseClient;
  StreamSubscription? _sseSubscription;
  Timer? _reconnectTimer;
  String? _streamingSchoolCode;
  int? _streamingGrade;
  int? _streamingClassNum;

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

  /// 네트워크 장애, 타임아웃, 미등록 상태 시 1~12반 공지 잠금(Lockout)을 방지하는 안전 폴백
  static Map<int, Set<int>> allAvailableClassesFallback() {
    return {
      for (int g = 1; g <= 6; g++)
        g: {for (int c = 1; c <= 12; c++) c},
    };
  }

  /// 학교 내 설치된 학급(1~12반) 목록을 학년별(1~6학년)로 조회
  /// 타임아웃, 네트워크 오류, 또는 감지된 학급이 0개인 경우 1~12반 전체 활성화 폴백을 반환하여
  /// 교사의 공지 작성이 차단(Lockout)되지 않도록 보장합니다.
  Future<Map<int, Set<int>>> fetchInstalledClasses(String schoolCode) async {
    final effectiveCode = normalizeSchoolKey(schoolCode);
    final Map<int, Set<int>> result = {
      for (int g = 1; g <= 6; g++) g: <int>{},
    };

    try {
      final res = await http.get(Uri.parse(_eatCallsUrl)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.body != 'null' && res.body.isNotEmpty) {
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

            // [급식 & 쪽지와 동일]: 최근 24시간 안에 신호가 있었던 학급만 필터링
            final activeTimeVal = val['registeredAt'] ?? val['lastActive'];
            if (activeTimeVal != null) {
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              int regMs = 0;
              if (activeTimeVal is num) {
                regMs = activeTimeVal.toInt();
              } else {
                regMs = DateTime.tryParse(activeTimeVal.toString())?.millisecondsSinceEpoch ?? 0;
              }
              if (regMs > 0) {
                final diffHours = (nowMs - regMs).abs() / (1000 * 60 * 60);
                if (diffHours > 24) return; // 24시간 지난 학급 제외
              }
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

            if (grade >= 1 && grade <= 6 && cls >= 1 && cls <= 12) {
              result[grade]!.add(cls);
            }
          });
        }
      } else {
        debugPrint('[Teacher AssessmentService] fetchInstalledClasses non-200 or empty');
        return result;
      }
    } catch (e) {
      debugPrint('[Teacher AssessmentService] fetchInstalledClasses error: $e');
      return result;
    }

    final bool allEmpty = result.values.every((s) => s.isEmpty);
    if (allEmpty) {
      debugPrint('[Teacher AssessmentService] No active installed classes found in 24h window');
      return result;
    }

    return result;
  }

  /// RTDB SSE 실시간 스트림 연결 시작 (수행평가 변경 사항 0.1초 내 즉시 화면 반영)
  void startStreaming({
    required String schoolCode,
    required int grade,
    int? classNum,
  }) {
    final effectiveCode = normalizeSchoolKey(schoolCode);
    if (_streamingSchoolCode == effectiveCode &&
        _streamingGrade == grade &&
        _sseSubscription != null) {
      _streamingClassNum = classNum;
      _filterAndNotify(_rawGradeItems, grade, classNum);
      return;
    }

    stopStreaming();
    _streamingSchoolCode = effectiveCode;
    _streamingGrade = grade;
    _streamingClassNum = classNum;

    _sseClient = http.Client();
    _connectRtdbSse(effectiveCode, grade);
  }

  /// 실시간 스트림 해제
  void stopStreaming() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      _sseSubscription?.cancel();
    } catch (_) {}
    _sseSubscription = null;
    try {
      _sseClient?.close();
    } catch (_) {}
    _sseClient = null;
  }

  /// 필터링 학급 업데이트 (스트림 유지 상태에서 선택 반 변경)
  void updateFilter({required int grade, int? classNum}) {
    _streamingGrade = grade;
    _streamingClassNum = classNum;
    _filterAndNotify(_rawGradeItems, grade, classNum);
  }

  Future<void> _connectRtdbSse(String schoolKey, int grade) async {
    try {
      final url = Uri.parse('$_rtdbBase/$schoolKey/$grade.json');
      final request = http.Request('GET', url);
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await _sseClient?.send(request);
      if (response == null || response.statusCode != 200) {
        _retryRtdbSse(schoolKey, grade);
        return;
      }

      String eventType = 'message';
      _sseSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('event: ')) {
          eventType = line.substring(7).trim();
        } else if (line.startsWith('data: ')) {
          final dataStr = line.substring(6).trim();
          if (dataStr.isNotEmpty && dataStr != 'null') {
            try {
              final jsonObj = json.decode(dataStr);
              _handleRtdbEvent(eventType, jsonObj);
            } catch (_) {}
          }
        }
      }, onDone: () {
        debugPrint('[Teacher AssessmentService] RTDB SSE stream closed, reconnecting...');
        _retryRtdbSse(schoolKey, grade);
      }, onError: (e) {
        debugPrint('[Teacher AssessmentService] RTDB SSE stream error: $e, reconnecting...');
        _retryRtdbSse(schoolKey, grade);
      });
      debugPrint('[Teacher AssessmentService] ⚡ Connected to RTDB SSE stream for $schoolKey/$grade');
    } catch (e) {
      debugPrint('[Teacher AssessmentService] RTDB SSE connection error: $e');
      _retryRtdbSse(schoolKey, grade);
    }
  }

  void _retryRtdbSse(String schoolKey, int grade) {
    if (_sseClient == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (_streamingSchoolCode == schoolKey && _streamingGrade == grade) {
        _sseClient?.close();
        _sseClient = http.Client();
        _connectRtdbSse(schoolKey, grade);
      }
    });
  }

  void _handleRtdbEvent(String eventType, dynamic jsonObj) {
    if (jsonObj is! Map) return;
    final path = jsonObj['path']?.toString() ?? '/';
    final data = jsonObj['data'];

    if (eventType == 'put') {
      if (path == '/' || path.isEmpty) {
        final List<AssessmentItem> newItems = [];
        if (data is Map) {
          data.forEach((key, val) {
            if (val is Map) {
              final map = Map<String, dynamic>.from(val);
              if ((map['id']?.toString() ?? '').isEmpty) {
                map['id'] = key.toString();
              }
              newItems.add(AssessmentItem.fromJson(map));
            }
          });
        }
        newItems.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        _rawGradeItems
          ..clear()
          ..addAll(newItems);
        _filterAndNotify(_rawGradeItems, _streamingGrade ?? 1, _streamingClassNum);
      } else {
        final itemId = path.startsWith('/') ? path.substring(1) : path;
        if (data == null) {
          _rawGradeItems.removeWhere((e) => e.id == itemId);
        } else if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          if ((map['id']?.toString() ?? '').isEmpty) {
            map['id'] = itemId;
          }
          final item = AssessmentItem.fromJson(map);
          _rawGradeItems.removeWhere((e) => e.id == itemId);
          _rawGradeItems.add(item);
          _rawGradeItems.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        }
        _filterAndNotify(_rawGradeItems, _streamingGrade ?? 1, _streamingClassNum);
      }
    } else if (eventType == 'patch') {
      if (data is Map) {
        data.forEach((key, val) {
          final itemId = key.toString();
          if (val == null) {
            _rawGradeItems.removeWhere((e) => e.id == itemId);
          } else if (val is Map) {
            final map = Map<String, dynamic>.from(val);
            if ((map['id']?.toString() ?? '').isEmpty) {
              map['id'] = itemId;
            }
            final item = AssessmentItem.fromJson(map);
            _rawGradeItems.removeWhere((e) => e.id == itemId);
            _rawGradeItems.add(item);
          }
        });
        _rawGradeItems.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        _filterAndNotify(_rawGradeItems, _streamingGrade ?? 1, _streamingClassNum);
      }
    }
  }

  Future<List<AssessmentItem>> loadAssessments({
    required String schoolCode,
    required int grade,
    int? classNum,
  }) async {
    _streamingGrade = grade;
    _streamingClassNum = classNum;
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
        _filterAndNotify(_rawGradeItems, _streamingGrade ?? normalizedItem.grade, _streamingClassNum);
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
    await loadAssessments(schoolCode: effectiveCode, grade: baseItem.grade, classNum: _streamingClassNum);
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
        _filterAndNotify(_rawGradeItems, _streamingGrade ?? grade, _streamingClassNum);
        return true;
      }
    } catch (e) {
      debugPrint('[Teacher AssessmentService] Delete error: $e');
    }
    return false;
  }
}

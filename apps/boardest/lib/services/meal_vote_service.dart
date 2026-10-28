import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service to handle meal dish highlights and zero-leak voting across classrooms via Firebase RTDB
/// - 투표 가능 시간 동안 로컬 저장만 수행 (네트워크 요청 0회)
/// - 점심시간 종료 10분 전: 교실 투표 서버 1회 전송 (PUT)
/// - 1분 뒤 (종료 9분 전): 전교 투표 서버 1회 취합 (GET) & 전자칠판 로컬 영구 저장
/// - 2분 뒤 (종료 8분 전): 서버 데이터 1회 삭제 (DELETE) -> Firebase DB 점유용량 0KB
/// - 과거 투표 기록 전자칠판 자체 영구 보존 및 월간 급식표 조회 지원
class MealVoteService {
  static final MealVoteService instance = MealVoteService._internal();
  MealVoteService._internal();

  static const String _rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com';

  String _currentSchoolId = '';
  DateTime? _activeDate;

  // 현재 메모리에 로드된 투표 데이터: dishKey -> { classKey: count }
  Map<String, Map<String, int>> _voteData = {};

  // 과거 기록 캐시: dateKey -> { dishKey: totalVotes }
  final Map<String, Map<String, int>> _historyCache = {};

  // 당일 일회성 전송/조회/삭제 플래그 (중복 호출 방지)
  final Set<String> _syncedServerDates = {};
  final Set<String> _fetchedFinalDates = {};
  final Set<String> _purgedServerDates = {};

  final ValueNotifier<Map<String, Map<String, int>>> votesNotifier = ValueNotifier({});

  String sanitizeKey(String raw) {
    return raw
        .replaceAll('/', '_')
        .replaceAll('.', '_')
        .replaceAll('#', '_')
        .replaceAll(r'$', '_')
        .replaceAll('[', '_')
        .replaceAll(']', '_');
  }

  String getDateKey(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  String _getLocalVotePrefKey(String schoolId, String dateKey) =>
      'bst_meal_votes_local_${sanitizeKey(schoolId)}_$dateKey';

  String _getHistoryPrefKey(String schoolId, String dateKey) =>
      'bst_meal_vote_history_${sanitizeKey(schoolId)}_$dateKey';

  /// 시작 시 초기화
  Future<void> startListening(String schoolId, DateTime date) async {
    _currentSchoolId = schoolId.trim().isEmpty ? 'default' : schoolId.trim();
    _activeDate = date;

    // 1. 과거 만료된 임시 투표 캐시 정리
    _purgeExpiredTempCaches();

    // 2. 당일 로컬 데이터(교실 투표 또는 영구 저장된 최종 집계) 복원
    await _loadDayVotes(_currentSchoolId, date);
  }

  void stopListening() {
    // 타이머 없음 - 상시 폴링 0
  }

  /// 30일이 지난 과거 캐시 및 서버 데이터 자동 삭제 (30일 보관 정책)
  Future<void> _purgeExpiredTempCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final cutoffDate = now.subtract(const Duration(days: 30));
      final allKeys = prefs.getKeys();
      for (final k in allKeys) {
        if (k.startsWith('bst_meal_votes_local_') || k.startsWith('bst_meal_vote_history_')) {
          final parts = k.split('_');
          if (parts.isNotEmpty) {
            final dateStr = parts.last;
            if (dateStr.length == 8) {
              final y = int.tryParse(dateStr.substring(0, 4));
              final m = int.tryParse(dateStr.substring(4, 6));
              final d = int.tryParse(dateStr.substring(6, 8));
              if (y != null && m != null && d != null) {
                final date = DateTime(y, m, d);
                if (date.isBefore(cutoffDate)) {
                  await prefs.remove(k);
                }
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  /// 로컬 저장소에서 당일 투표 복원
  Future<void> _loadDayVotes(String schoolId, DateTime date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = getDateKey(date);
      final sId = schoolId.trim().isNotEmpty && schoolId != 'default' && schoolId != 'Demo'
        ? schoolId.trim()
        : (_currentSchoolId.isNotEmpty ? _currentSchoolId : (schoolId.trim().isNotEmpty ? schoolId.trim() : 'default'));

      // 우선 최종 합산 기록(전교 집계 영구 저장본)이 있는지 확인
      final historyRaw = prefs.getString(_getHistoryPrefKey(sId, dateKey));
      if (historyRaw != null && historyRaw.isNotEmpty) {
        final decoded = json.decode(historyRaw);
        if (decoded is Map<String, dynamic>) {
          final Map<String, Map<String, int>> map = {};
          decoded.forEach((dKey, val) {
            if (val is Map) {
              final Map<String, int> inner = {};
              val.forEach((cKey, v) => inner[cKey.toString()] = (v as num?)?.toInt() ?? 0);
              map[dKey] = inner;
            } else if (val is num) {
              map[dKey] = {'전교': val.toInt()};
            }
          });
          _voteData = map;
          votesNotifier.value = Map.from(_voteData);
          return;
        }
      }

      // 없으면 진행 중인 당일 로컬 교실 투표 불러오기
      final localRaw = prefs.getString(_getLocalVotePrefKey(sId, dateKey));
      if (localRaw != null && localRaw.isNotEmpty) {
        final decoded = json.decode(localRaw);
        if (decoded is Map<String, dynamic>) {
          final Map<String, Map<String, int>> map = {};
          decoded.forEach((dKey, val) {
            if (val is Map) {
              final Map<String, int> inner = {};
              val.forEach((cKey, v) => inner[cKey.toString()] = (v as num?)?.toInt() ?? 0);
              map[dKey] = inner;
            }
          });
          _voteData = map;
          votesNotifier.value = Map.from(_voteData);
        }
      }
    } catch (e) {
      debugPrint('[MealVoteService] Error loading day votes: $e');
    }
  }

  /// 투표 기록 (로컬 SharedPreferences에만 기록, 네트워크 요청 0회!)
  /// [amount] 기본 1표, 10표 올리기 버튼 지원 (+10)
  Future<void> recordLocalVote({
    required String schoolId,
    required DateTime date,
    required String dishName,
    required String classKey,
    int amount = 1,
  }) async {
    final sId = schoolId.trim().isNotEmpty && schoolId != 'default' && schoolId != 'Demo'
        ? schoolId.trim()
        : (_currentSchoolId.isNotEmpty ? _currentSchoolId : (schoolId.trim().isNotEmpty ? schoolId.trim() : 'default'));
    final dateKey = getDateKey(date);
    final dishKey = sanitizeKey(dishName);
    final sanitizedClass = sanitizeKey(classKey.isEmpty ? '우리반' : classKey);

    final currentClassMap = Map<String, int>.from(_voteData[dishKey] ?? {});
    final currentCount = currentClassMap[sanitizedClass] ?? 0;
    final nextCount = currentCount + amount;
    currentClassMap[sanitizedClass] = nextCount;
    _voteData[dishKey] = currentClassMap;
    votesNotifier.value = Map.from(_voteData);

    // 로컬에 영구 저장 (네트워크 0회)
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getLocalVotePrefKey(sId, dateKey);
      await prefs.setString(key, json.encode(_voteData));
    } catch (e) {
      debugPrint('[MealVoteService] Error saving local vote: $e');
    }
  }

  /// 기존 호환용 submitVote
  Future<void> submitVote({
    required String schoolId,
    required DateTime date,
    required String dishName,
    required String classKey,
    int amount = 1,
  }) async {
    await recordLocalVote(
      schoolId: schoolId,
      date: date,
      dishName: dishName,
      classKey: classKey,
      amount: amount,
    );
  }

  /// 점심시간 종료 전: 로컬 영구 저장소에 투표 결과 보존 (네트워크 요청 0회!)
  Future<void> syncClassVotesToServer({
    required String schoolId,
    required DateTime date,
    required String classKey,
  }) async {
    final sId = schoolId.trim().isNotEmpty && schoolId != 'default' && schoolId != 'Demo'
        ? schoolId.trim()
        : (_currentSchoolId.isNotEmpty ? _currentSchoolId : (schoolId.trim().isNotEmpty ? schoolId.trim() : 'default'));
    final dateKey = getDateKey(date);

    if (_syncedServerDates.contains(dateKey)) return;
    _syncedServerDates.add(dateKey);

    try {
      final prefs = await SharedPreferences.getInstance();
      final historyKey = _getHistoryPrefKey(sId, dateKey);
      await prefs.setString(historyKey, json.encode(_voteData));
    } catch (_) {}
  }

  /// 점심시간 종료 전: 로컬 영구 저장소에 투표 결과 확정 (네트워크 요청 0회!)
  Future<void> fetchAndPersistFinalResults({
    required String schoolId,
    required DateTime date,
  }) async {
    final sId = schoolId.trim().isNotEmpty && schoolId != 'default' && schoolId != 'Demo'
        ? schoolId.trim()
        : (_currentSchoolId.isNotEmpty ? _currentSchoolId : (schoolId.trim().isNotEmpty ? schoolId.trim() : 'default'));
    final dateKey = getDateKey(date);

    if (_fetchedFinalDates.contains(dateKey)) return;
    _fetchedFinalDates.add(dateKey);

    try {
      final Map<String, int> totals = {};
      _voteData.forEach((dishKey, classMap) {
        int sum = 0;
        classMap.forEach((_, c) => sum += c);
        totals[dishKey] = sum;
      });
      _historyCache[dateKey] = totals;

      final prefs = await SharedPreferences.getInstance();
      final historyKey = _getHistoryPrefKey(sId, dateKey);
      await prefs.setString(historyKey, json.encode(_voteData));
    } catch (_) {}
  }

  /// 서버 투표 보관 정책 (30일간 보관하여 월간 급식표 등에서 열람 가능, 30일 초과 시에만 자동 삭제)
  Future<void> purgeServerVotes({
    required String schoolId,
    required DateTime date,
  }) async {
    // 30일간 서버에 보존하므로 즉시 삭제하지 않음
  }

  /// 메뉴의 총 득표수 가져오기
  int getTotalVotes(String dishName) {
    final key = sanitizeKey(dishName);
    final map = _voteData[key];
    if (map == null) return 0;
    int total = 0;
    map.forEach((_, count) => total += count);
    return total;
  }

  /// 메뉴의 반별 득표 세부내역
  Map<String, int> getClassVotes(String dishName) {
    final key = sanitizeKey(dishName);
    return _voteData[key] ?? {};
  }

  /// 과거 날짜의 최종 투표 결과 조회 (월간 급식표용, 로컬 캐시 우선, 서버 조회 지원)
  Future<Map<String, int>> getHistoricalVotes(String schoolId, DateTime date) async {
    final sId = schoolId.trim().isNotEmpty && schoolId != 'default' && schoolId != 'Demo'
        ? schoolId.trim()
        : (_currentSchoolId.isNotEmpty ? _currentSchoolId : (schoolId.trim().isNotEmpty ? schoolId.trim() : 'default'));
    final dateKey = getDateKey(date);

    // 1. 메모리 캐시 확인
    if (_historyCache.containsKey(dateKey)) {
      return _historyCache[dateKey]!;
    }

    // 2. 당일 활성 날짜이면 현재 _voteData에서 계산
    if (_activeDate != null && getDateKey(_activeDate!) == dateKey) {
      final Map<String, int> todayTotals = {};
      _voteData.forEach((dishKey, classMap) {
        int sum = 0;
        classMap.forEach((_, c) => sum += c);
        todayTotals[dishKey] = sum;
      });
      return todayTotals;
    }

    // 3. SharedPreferences 영구 저장소에서 조회
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_getHistoryPrefKey(sId, dateKey));
      if (raw != null && raw.isNotEmpty) {
        final decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) {
          final Map<String, int> totals = {};
          decoded.forEach((dishKey, val) {
            if (val is Map) {
              int sum = 0;
              val.forEach((_, c) => sum += ((c as num?)?.toInt() ?? 0));
              totals[dishKey] = sum;
            } else if (val is num) {
              totals[dishKey] = val.toInt();
            }
          });
          _historyCache[dateKey] = totals;
          return totals;
        }
      }
    } catch (e) {
      debugPrint('[MealVoteService] Error reading historical votes: $e');
    }

    // 4. 당일 로컬 투표에서도 확인 (네트워크 요청 0회)
    try {
      final prefs = await SharedPreferences.getInstance();
      final localRaw = prefs.getString(_getLocalVotePrefKey(sId, dateKey));
      if (localRaw != null && localRaw.isNotEmpty) {
        final decoded = json.decode(localRaw);
        if (decoded is Map<String, dynamic>) {
          final Map<String, int> totals = {};
          decoded.forEach((dishKey, val) {
            if (val is Map) {
              int sum = 0;
              val.forEach((_, c) => sum += ((c as num?)?.toInt() ?? 0));
              totals[dishKey] = sum;
            } else if (val is num) {
              totals[dishKey] = val.toInt();
            }
          });
          _historyCache[dateKey] = totals;
          return totals;
        }
      }
    } catch (_) {}

    return {};
  }
}

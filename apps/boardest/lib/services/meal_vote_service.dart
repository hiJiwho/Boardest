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

  /// 만료된 임시 로컬 캐시 정리
  Future<void> _purgeExpiredTempCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey = _activeDate != null ? getDateKey(_activeDate!) : getDateKey(DateTime.now());
      final allKeys = prefs.getKeys();
      for (final k in allKeys) {
        if (k.startsWith('bst_meal_votes_local_')) {
          if (!k.endsWith(todayKey)) {
            await prefs.remove(k);
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
      final sId = schoolId.trim().isEmpty ? 'default' : schoolId.trim();

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
  Future<void> recordLocalVote({
    required String schoolId,
    required DateTime date,
    required String dishName,
    required String classKey,
  }) async {
    final sId = schoolId.trim().isEmpty ? 'default' : schoolId.trim();
    final dateKey = getDateKey(date);
    final dishKey = sanitizeKey(dishName);
    final sanitizedClass = sanitizeKey(classKey.isEmpty ? '우리반' : classKey);

    final currentClassMap = Map<String, int>.from(_voteData[dishKey] ?? {});
    final currentCount = currentClassMap[sanitizedClass] ?? 0;
    final nextCount = currentCount + 1;
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
  }) async {
    await recordLocalVote(
      schoolId: schoolId,
      date: date,
      dishName: dishName,
      classKey: classKey,
    );
  }

  /// 점심시간 종료 10분 전: 교실 투표 결과를 RTDB에 딱 1회 PUT 전송
  Future<void> syncClassVotesToServer({
    required String schoolId,
    required DateTime date,
    required String classKey,
  }) async {
    final sId = schoolId.trim().isEmpty ? 'default' : schoolId.trim();
    final dateKey = getDateKey(date);
    final sanitizedClass = sanitizeKey(classKey.isEmpty ? '우리반' : classKey);

    if (_syncedServerDates.contains(dateKey)) return;
    _syncedServerDates.add(dateKey);

    debugPrint('[MealVoteService] 🚀 Syncing class votes to server for $dateKey ($sanitizedClass)...');
    try {
      for (final entry in _voteData.entries) {
        final dishKey = entry.key;
        final count = entry.value[sanitizedClass] ?? 0;
        if (count > 0) {
          final url = Uri.parse('$_rtdbBase/meal_votes/$sId/$dateKey/$dishKey/$sanitizedClass.json');
          await http.put(url, body: json.encode(count));
        }
      }
      debugPrint('[MealVoteService] ✅ Sync complete for $dateKey');
    } catch (e) {
      debugPrint('[MealVoteService] ⚠️ Sync error: $e');
    }
  }

  /// 점심시간 종료 9분 전 (1분 뒤): RTDB에서 전교 결과 1회 GET 가져와서 전자칠판 자체에 영구 저장
  Future<void> fetchAndPersistFinalResults({
    required String schoolId,
    required DateTime date,
  }) async {
    final sId = schoolId.trim().isEmpty ? 'default' : schoolId.trim();
    final dateKey = getDateKey(date);

    if (_fetchedFinalDates.contains(dateKey)) return;
    _fetchedFinalDates.add(dateKey);

    debugPrint('[MealVoteService] 📥 Fetching all school votes from server for $dateKey...');
    try {
      final url = Uri.parse('$_rtdbBase/meal_votes/$sId/$dateKey.json');
      final res = await http.get(url);
      if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
        final decoded = json.decode(res.body);
        if (decoded is Map<String, dynamic>) {
          final Map<String, Map<String, int>> merged = {};
          final Map<String, int> totals = {};

          decoded.forEach((dishKey, classMap) {
            if (classMap is Map) {
              final Map<String, int> inner = {};
              int sum = 0;
              classMap.forEach((cKey, v) {
                final c = (v as num?)?.toInt() ?? 0;
                inner[cKey.toString()] = c;
                sum += c;
              });
              merged[dishKey] = inner;
              totals[dishKey] = sum;
            }
          });

          // 로컬 데이터 병합
          _voteData = merged;
          votesNotifier.value = Map.from(_voteData);
          _historyCache[dateKey] = totals;

          // 전자칠판 자체(SharedPreferences)에 영구 저장
          final prefs = await SharedPreferences.getInstance();
          final historyKey = _getHistoryPrefKey(sId, dateKey);
          await prefs.setString(historyKey, json.encode(merged));
          debugPrint('[MealVoteService] 💾 Final votes persisted locally to $historyKey');
        }
      }
    } catch (e) {
      debugPrint('[MealVoteService] ⚠️ Fetch final votes error: $e');
    }
  }

  /// 점심시간 종료 8분 전 (2분 뒤): RTDB에서 해당 날짜 데이터 완전 삭제 (DELETE) -> 서버 점유 0KB
  Future<void> purgeServerVotes({
    required String schoolId,
    required DateTime date,
  }) async {
    final sId = schoolId.trim().isEmpty ? 'default' : schoolId.trim();
    final dateKey = getDateKey(date);

    if (_purgedServerDates.contains(dateKey)) return;
    _purgedServerDates.add(dateKey);

    debugPrint('[MealVoteService] 🧹 Purging server votes for $dateKey (Firebase 0KB)...');
    try {
      final url = Uri.parse('$_rtdbBase/meal_votes/$sId/$dateKey.json');
      final res = await http.delete(url);
      debugPrint('[MealVoteService] 🗑️ Server votes purged (Status: ${res.statusCode})');
    } catch (e) {
      debugPrint('[MealVoteService] ⚠️ Purge server error: $e');
    }
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

  /// 과거 날짜의 최종 투표 결과 조회 (월간 급식표용, 로컬 캐시 우선)
  Future<Map<String, int>> getHistoricalVotes(String schoolId, DateTime date) async {
    final sId = schoolId.trim().isEmpty ? 'default' : schoolId.trim();
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

    return {};
  }
}

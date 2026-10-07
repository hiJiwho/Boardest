import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service to handle meal dish highlights and real-time voting across classrooms via Firebase RTDB
class MealVoteService {
  static final MealVoteService instance = MealVoteService._internal();
  MealVoteService._internal();

  static const String _rtdbBase = 'https://jiwhosboardest-default-rtdb.firebaseio.com';

  Timer? _refreshTimer;
  String _currentSchoolId = '';
  DateTime? _activeDate;
  Map<String, Map<String, int>> _voteData = {}; // dishName -> { classKey: count }
  
  final ValueNotifier<Map<String, Map<String, int>>> votesNotifier = ValueNotifier({});

  String _sanitizeKey(String raw) {
    return raw.replaceAll('/', '_').replaceAll('.', '_').replaceAll('#', '_').replaceAll(r'$', '_').replaceAll('[', '_').replaceAll(']', '_');
  }

  void startListening(String schoolId, DateTime date) {
    _currentSchoolId = schoolId.trim().isEmpty ? 'default' : schoolId.trim();
    _activeDate = date;
    fetchVotes();

    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      fetchVotes();
    });
  }

  void stopListening() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  String _getDateKey(DateTime date) => '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  Future<void> fetchVotes() async {
    if (_activeDate == null || _currentSchoolId.isEmpty) return;
    final dateKey = _getDateKey(_activeDate!);
    final url = Uri.parse('$_rtdbBase/meal_votes/$_currentSchoolId/$dateKey.json');

    try {
      final res = await http.get(url);
      if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
        final decoded = json.decode(res.body);
        if (decoded is Map<String, dynamic>) {
          final Map<String, Map<String, int>> result = {};
          decoded.forEach((dishKey, classMap) {
            if (classMap is Map) {
              final Map<String, int> inner = {};
              classMap.forEach((cKey, v) {
                inner[cKey.toString()] = (v as num?)?.toInt() ?? 0;
              });
              result[dishKey] = inner;
            }
          });
          _voteData = result;
          votesNotifier.value = Map.from(_voteData);
        }
      } else if (res.statusCode == 200 && res.body == 'null') {
        _voteData = {};
        votesNotifier.value = {};
      }
    } catch (e) {
      debugPrint('[MealVoteService] Error fetching votes: $e');
    }
  }

  /// Get total votes for a dish
  int getTotalVotes(String dishName) {
    final key = _sanitizeKey(dishName);
    final map = _voteData[key];
    if (map == null) return 0;
    int total = 0;
    map.forEach((_, count) => total += count);
    return total;
  }

  /// Get breakdown by class for a dish
  Map<String, int> getClassVotes(String dishName) {
    final key = _sanitizeKey(dishName);
    return _voteData[key] ?? {};
  }

  /// Submit a vote (only 1 vote per tap, cannot cancel)
  Future<void> submitVote({
    required String schoolId,
    required DateTime date,
    required String dishName,
    required String classKey,
  }) async {
    final sId = schoolId.trim().isEmpty ? 'default' : schoolId.trim();
    final dateKey = _getDateKey(date);
    final dishKey = _sanitizeKey(dishName);
    final sanitizedClass = _sanitizeKey(classKey.isEmpty ? '기타반' : classKey);

    // Optimistic update
    final currentMap = Map<String, int>.from(_voteData[dishKey] ?? {});
    final currentCount = currentMap[sanitizedClass] ?? 0;
    currentMap[sanitizedClass] = currentCount + 1;
    _voteData[dishKey] = currentMap;
    votesNotifier.value = Map.from(_voteData);

    try {
      final url = Uri.parse('$_rtdbBase/meal_votes/$sId/$dateKey/$dishKey/$sanitizedClass.json');
      // Increment in RTDB
      await http.put(url, body: json.encode(currentCount + 1));
    } catch (e) {
      debugPrint('[MealVoteService] Error submitting vote: $e');
    }
  }
}

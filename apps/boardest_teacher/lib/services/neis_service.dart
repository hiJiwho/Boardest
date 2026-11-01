import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meal_models.dart';

class NeisService {
  static final String _encNeisKey = 'ODIxMTc5NTQxY2Y1NGI2Mjg4ZDUxNzQxZjMwZTFjOTA=';
  static String get _apiKey => const String.fromEnvironment('NEIS_API_KEY').isNotEmpty
      ? const String.fromEnvironment('NEIS_API_KEY')
      : utf8.decode(base64.decode(_encNeisKey));

  // In-memory cache for resolved school codes: schoolName -> { officeCode, schoolCode }
  static final Map<String, Map<String, String>> _schoolCodesCache = {};

  // In-memory cache for meal info: 'schoolName-dateStr' -> MealDayInfo
  static final Map<String, MealDayInfo> _mealInfoMemoryCache = {};

  // In-memory cache for month meals: 'schoolName-year-month' -> Map<int, MealDayInfo>
  static final Map<String, Map<int, MealDayInfo>> _monthMealsMemoryCache = {};

  /// Normalizes school names into search candidates
  static List<String> _getSchoolNameCandidates(String schoolName) {
    final raw = schoolName.trim();
    final stripped = raw.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    final Set<String> candidates = {raw, stripped};

    for (final name in [stripped, raw]) {
      if (name.isEmpty) continue;
      if (name.endsWith('초')) {
        candidates.add('$name등학교');
      } else if (name.endsWith('중')) {
        candidates.add('$name학교');
      } else if (name.endsWith('고')) {
        candidates.add('$name등학교');
      } else if (name.endsWith('초등학교')) {
        candidates.add(name.substring(0, name.length - 2));
      } else if (name.endsWith('중학교')) {
        candidates.add(name.substring(0, name.length - 2));
      } else if (name.endsWith('고등학교')) {
        candidates.add('${name.substring(0, name.length - 3)}고');
      }
    }
    return candidates.where((c) => c.isNotEmpty).toList();
  }

  /// Searches school info to retrieve NEIS ATPT_OFCDC_SC_CODE and SD_SCHUL_CODE
  Future<Map<String, String>?> _resolveSchoolCodes(String schoolName) async {
    // Check cache first
    if (_schoolCodesCache.containsKey(schoolName)) {
      return _schoolCodesCache[schoolName];
    }

    final candidates = _getSchoolNameCandidates(schoolName);

    for (final candidate in candidates) {
      if (_schoolCodesCache.containsKey(candidate)) {
        final cached = _schoolCodesCache[candidate]!;
        _schoolCodesCache[schoolName] = cached;
        return cached;
      }

      try {
        final queryUrl = Uri.parse(
          'https://open.neis.go.kr/hub/schoolInfo'
          '?KEY=$_apiKey'
          '&Type=json'
          '&pIndex=1'
          '&pSize=5'
          '&SCHUL_NM=${Uri.encodeComponent(candidate)}',
        );

        final response = await http.get(queryUrl).timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) continue;

        final data = json.decode(response.body);
        if (data == null || data['schoolInfo'] == null || (data['schoolInfo'] as List).length < 2) continue;

        final rowObj = data['schoolInfo'][1];
        if (rowObj is! Map || rowObj['row'] == null || (rowObj['row'] as List).isEmpty) continue;

        final rows = rowObj['row'] as List<dynamic>;

        // Extract codes from the first exact/best match
        final firstRow = rows[0] as Map<String, dynamic>;
        final codes = {
          'officeCode': firstRow['ATPT_OFCDC_SC_CODE']?.toString() ?? '',
          'schoolCode': firstRow['SD_SCHUL_CODE']?.toString() ?? '',
        };
        if (codes['officeCode']!.isEmpty || codes['schoolCode']!.isEmpty) continue;

        _schoolCodesCache[schoolName] = codes;
        _schoolCodesCache[candidate] = codes;
        return codes;
      } catch (_) {
        // Continue to next candidate
      }
    }
    return null;
  }

  /// Fetches lunch meal menu as structured MealDayInfo with allergy annotations
  Future<MealDayInfo> fetchMealDayInfo(String schoolName, DateTime date) async {
    if (schoolName == 'Demo' || schoolName.toLowerCase().contains('demo') || schoolName.contains('데모')) {
      return MealDayInfo.generateDemo(date);
    }

    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final dateStr = '$year$month$day';
    final cacheKey = '$schoolName-$dateStr';

    // 1) In-memory cache check
    if (_mealInfoMemoryCache.containsKey(cacheKey)) {
      return _mealInfoMemoryCache[cacheKey]!;
    }

    // Helper to read offline persistent cache
    Future<MealDayInfo?> loadOfflineCache() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('bst_meal_info_$cacheKey');
        if (raw != null && raw.isNotEmpty) {
          final decoded = json.decode(raw);
          if (decoded is Map<String, dynamic>) {
            final info = MealDayInfo.fromJson(decoded);
            _mealInfoMemoryCache[cacheKey] = info;
            return info;
          }
        }
      } catch (_) {}
      return null;
    }

    // Helper to save offline persistent cache
    void saveOfflineCache(MealDayInfo info) async {
      try {
        _mealInfoMemoryCache[cacheKey] = info;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bst_meal_info_$cacheKey', json.encode(info.toJson()));
      } catch (_) {}
    }

    final codes = await _resolveSchoolCodes(schoolName);
    if (codes == null) {
      final cached = await loadOfflineCache();
      if (cached != null) return cached;
      return MealDayInfo(date: date, dishes: [], footnotes: ['학교 기본 정보를 찾을 수 없습니다.']);
    }

    final officeCode = codes['officeCode']!;
    final schoolCode = codes['schoolCode']!;

    try {
      // First attempt: with MMEAL_SC_CODE=2 (Lunch)
      Uri queryUrl = Uri.parse(
        'https://open.neis.go.kr/hub/mealServiceDietInfo'
        '?KEY=$_apiKey'
        '&Type=json'
        '&ATPT_OFCDC_SC_CODE=$officeCode'
        '&SD_SCHUL_CODE=$schoolCode'
        '&MLSV_YMD=$dateStr'
        '&MMEAL_SC_CODE=2',
      );

      var response = await http.get(queryUrl).timeout(const Duration(seconds: 6));
      var data = response.statusCode == 200 ? json.decode(response.body) : null;
      var rows = <dynamic>[];

      if (data != null && data['mealServiceDietInfo'] != null && (data['mealServiceDietInfo'] as List).length >= 2) {
        final rowObj = data['mealServiceDietInfo'][1];
        if (rowObj is Map && rowObj['row'] != null && (rowObj['row'] as List).isNotEmpty) {
          rows = rowObj['row'] as List<dynamic>;
        }
      }

      // Second attempt: without MMEAL_SC_CODE
      if (rows.isEmpty) {
        queryUrl = Uri.parse(
          'https://open.neis.go.kr/hub/mealServiceDietInfo'
          '?KEY=$_apiKey'
          '&Type=json'
          '&ATPT_OFCDC_SC_CODE=$officeCode'
          '&SD_SCHUL_CODE=$schoolCode'
          '&MLSV_YMD=$dateStr',
        );
        response = await http.get(queryUrl).timeout(const Duration(seconds: 6));
        data = response.statusCode == 200 ? json.decode(response.body) : null;
        if (data != null && data['mealServiceDietInfo'] != null && (data['mealServiceDietInfo'] as List).length >= 2) {
          final rowObj = data['mealServiceDietInfo'][1];
          if (rowObj is Map && rowObj['row'] != null && (rowObj['row'] as List).isNotEmpty) {
            rows = rowObj['row'] as List<dynamic>;
          }
        }
      }

      if (rows.isEmpty) {
        final cached = await loadOfflineCache();
        if (cached != null) return cached;
        return MealDayInfo(date: date, dishes: [], footnotes: ['오늘 등록된 급식 메뉴가 없습니다.']);
      }

      final mealRow = (rows.firstWhere(
        (r) => r is Map && r['MMEAL_SC_CODE'] == '2',
        orElse: () => rows.first,
      )) as Map<String, dynamic>;

      final rawDdish = mealRow['DDISH_NM']?.toString() ?? '';
      final rawCal = (mealRow['CAL_INFO'] as String? ?? '').replaceAll('Kcal', 'kcal').trim();
      final info = MealDayInfo.fromNeisRaw(date, rawDdish, calories: rawCal);
      saveOfflineCache(info);
      return info;
    } catch (_) {
      final cached = await loadOfflineCache();
      if (cached != null) return cached;
      return MealDayInfo(date: date, dishes: [], footnotes: ['급식 정보를 불러오는 중 일시적 오류가 발생했습니다.']);
    }
  }

  /// Fetches lunch meal menu for a specific date (YYYYMMDD) and formats with allergy badges
  Future<String> fetchTodayMeal(String schoolName, DateTime date) async {
    final info = await fetchMealDayInfo(schoolName, date);
    if (info.dishes.isEmpty) {
      return info.footnotes.isNotEmpty ? info.footnotes.first : '오늘 등록된 급식 메뉴가 없습니다.';
    }
    return info.dishes.map((d) => '${d.name} ${d.allergyDisplay}'.trim()).join('\n');
  }

  /// Cleans HTML breaks and strips allergy index numbers (e.g. "(1.5.13.)")
  static String cleanMealMenu(String rawMenu) {
    if (rawMenu.isEmpty) return '급식 메뉴가 비어 있습니다.';

    var cleaned = rawMenu.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    final RegExp allergyRegExp = RegExp(r'\([0-9. \t\n*]+\)');
    cleaned = cleaned.replaceAll(allergyRegExp, '');

    final lines = cleaned
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    return lines.join('\n');
  }

  /// Fetches lunch meals for an entire month with persistent offline cache
  Future<Map<int, MealDayInfo>> fetchMonthMeals(String schoolName, int year, int month) async {
    if (schoolName == 'Demo' || schoolName.toLowerCase().contains('demo') || schoolName.contains('데모')) {
      final Map<int, MealDayInfo> map = {};
      final daysInMonth = DateTime(year, month + 1, 0).day;
      for (int d = 1; d <= daysInMonth; d++) {
        final date = DateTime(year, month, d);
        map[d] = MealDayInfo.generateDemo(date);
      }
      return map;
    }

    final cacheKey = '$schoolName-$year-$month';
    if (_monthMealsMemoryCache.containsKey(cacheKey)) {
      return _monthMealsMemoryCache[cacheKey]!;
    }

    // Helper to read offline persistent monthly cache
    Future<Map<int, MealDayInfo>?> loadOfflineMonthCache() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('bst_month_meals_$cacheKey');
        if (raw != null && raw.isNotEmpty) {
          final decoded = json.decode(raw);
          if (decoded is Map) {
            final Map<int, MealDayInfo> restored = {};
            decoded.forEach((key, val) {
              final day = int.tryParse(key.toString());
              if (day != null && val is Map<String, dynamic>) {
                restored[day] = MealDayInfo.fromJson(val);
              }
            });
            if (restored.isNotEmpty) {
              _monthMealsMemoryCache[cacheKey] = restored;
              return restored;
            }
          }
        }
      } catch (_) {}
      return null;
    }

    // Helper to save offline persistent monthly cache
    void saveOfflineMonthCache(Map<int, MealDayInfo> map) async {
      try {
        _monthMealsMemoryCache[cacheKey] = map;
        final prefs = await SharedPreferences.getInstance();
        final encodable = map.map((k, v) => MapEntry(k.toString(), v.toJson()));
        await prefs.setString('bst_month_meals_$cacheKey', json.encode(encodable));
      } catch (_) {}
    }

    final codes = await _resolveSchoolCodes(schoolName);
    if (codes == null) {
      final cached = await loadOfflineMonthCache();
      return cached ?? {};
    }

    final officeCode = codes['officeCode']!;
    final schoolCode = codes['schoolCode']!;

    final daysInMonth = DateTime(year, month + 1, 0).day;
    final fromDateStr = '$year${month.toString().padLeft(2, '0')}01';
    final toDateStr = '$year${month.toString().padLeft(2, '0')}${daysInMonth.toString().padLeft(2, '0')}';

    try {
      Uri queryUrl = Uri.parse(
        'https://open.neis.go.kr/hub/mealServiceDietInfo'
        '?KEY=$_apiKey'
        '&Type=json'
        '&ATPT_OFCDC_SC_CODE=$officeCode'
        '&SD_SCHUL_CODE=$schoolCode'
        '&MLSV_FROM_YMD=$fromDateStr'
        '&MLSV_TO_YMD=$toDateStr'
        '&MMEAL_SC_CODE=2'
        '&pSize=50',
      );

      var response = await http.get(queryUrl).timeout(const Duration(seconds: 8));
      var data = response.statusCode == 200 ? json.decode(response.body) : null;
      var rows = <dynamic>[];

      if (data != null && data['mealServiceDietInfo'] != null && (data['mealServiceDietInfo'] as List).length >= 2) {
        final rowObj = data['mealServiceDietInfo'][1];
        if (rowObj is Map && rowObj['row'] != null && (rowObj['row'] as List).isNotEmpty) {
          rows = rowObj['row'] as List<dynamic>;
        }
      }

      if (rows.isEmpty) {
        queryUrl = Uri.parse(
          'https://open.neis.go.kr/hub/mealServiceDietInfo'
          '?KEY=$_apiKey'
          '&Type=json'
          '&ATPT_OFCDC_SC_CODE=$officeCode'
          '&SD_SCHUL_CODE=$schoolCode'
          '&MLSV_FROM_YMD=$fromDateStr'
          '&MLSV_TO_YMD=$toDateStr'
          '&pSize=50',
        );
        response = await http.get(queryUrl).timeout(const Duration(seconds: 8));
        data = response.statusCode == 200 ? json.decode(response.body) : null;
        if (data != null && data['mealServiceDietInfo'] != null && (data['mealServiceDietInfo'] as List).length >= 2) {
          final rowObj = data['mealServiceDietInfo'][1];
          if (rowObj is Map && rowObj['row'] != null && (rowObj['row'] as List).isNotEmpty) {
            rows = rowObj['row'] as List<dynamic>;
          }
        }
      }

      final Map<int, MealDayInfo> map = {};

      for (final row in rows) {
        final ymd = row['MLSV_YMD'] as String? ?? '';
        if (ymd.length == 8) {
          final day = int.tryParse(ymd.substring(6, 8));
          if (day != null) {
            final date = DateTime(year, month, day);
            final rawDdish = row['DDISH_NM']?.toString() ?? '';
            final rawCal = (row['CAL_INFO'] as String? ?? '').replaceAll('Kcal', 'kcal').trim();
            map[day] = MealDayInfo.fromNeisRaw(date, rawDdish, calories: rawCal);
          }
        }
      }

      if (map.isNotEmpty) {
        saveOfflineMonthCache(map);
        return map;
      }

      final cached = await loadOfflineMonthCache();
      return cached ?? {};
    } catch (_) {
      final cached = await loadOfflineMonthCache();
      return cached ?? {};
    }
  }

  /// Fetches school schedule events from date for 365 days
  Future<List<Map<String, dynamic>>> fetchSchoolSchedule(String schoolName, DateTime startDate) async {
    final codes = await _resolveSchoolCodes(schoolName);
    if (codes == null) {
      return [];
    }

    final officeCode = codes['officeCode']!;
    final schoolCode = codes['schoolCode']!;

    final startYear = startDate.year.toString();
    final startMonth = startDate.month.toString().padLeft(2, '0');
    final startDay = startDate.day.toString().padLeft(2, '0');
    final fromDateStr = '$startYear$startMonth$startDay';

    // Query for next 365 days
    final endDate = startDate.add(const Duration(days: 365));
    final endYear = endDate.year.toString();
    final endMonth = endDate.month.toString().padLeft(2, '0');
    final endDay = endDate.day.toString().padLeft(2, '0');
    final toDateStr = '$endYear$endMonth$endDay';

    try {
      final queryUrl = Uri.parse(
        'https://open.neis.go.kr/hub/SchoolSchedule'
        '?KEY=$_apiKey'
        '&Type=json'
        '&ATPT_OFCDC_SC_CODE=$officeCode'
        '&SD_SCHUL_CODE=$schoolCode'
        '&AA_FROM_YMD=$fromDateStr'
        '&AA_TO_YMD=$toDateStr'
        '&pIndex=1'
        '&pSize=100',
      );

      final response = await http.get(queryUrl).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      if (data == null || data['SchoolSchedule'] == null) return [];

      final rows = data['SchoolSchedule'][1]['row'] as List<dynamic>;
      final List<Map<String, dynamic>> events = [];

      for (final row in rows) {
        final dateStr = row['AA_YMD'] as String? ?? '';
        final eventName = row['EVENT_NM'] as String? ?? '';
        
        // Skip weekly holidays or empty event names
        if (dateStr.isEmpty || eventName.isEmpty || eventName.contains('토요휴업일') || eventName.contains('일요일') || eventName.contains('토요일')) {
          continue;
        }

        if (dateStr.length == 8) {
          final year = int.tryParse(dateStr.substring(0, 4)) ?? startDate.year;
          final month = int.tryParse(dateStr.substring(4, 6)) ?? startDate.month;
          final day = int.tryParse(dateStr.substring(6, 8)) ?? startDate.day;
          final eventDate = DateTime(year, month, day);

          events.add({
            'title': eventName,
            'date': eventDate,
          });
        }
      }

      // Sort by date ascending
      events.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
      return events;
    } catch (e) {
      return [];
    }
  }
}

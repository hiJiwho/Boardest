import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meal_models.dart';

class LiteNeisMealService {
  static const String _encNeisKey = 'ODIxMTc5NTQxY2Y1NGI2Mjg4ZDUxNzQxZjMwZTFjOTA=';
  static String get _apiKey => const String.fromEnvironment('NEIS_API_KEY').isNotEmpty
      ? const String.fromEnvironment('NEIS_API_KEY')
      : utf8.decode(base64.decode(_encNeisKey));

  static final Map<String, LiteMealDayInfo> _todayMemoryCache = {};
  static final Map<String, Map<int, LiteMealDayInfo>> _monthMemoryCache = {};
  static final Map<String, Map<String, String>> _schoolCodesCache = {};

  Future<Map<String, String>?> resolveSchoolCodes(String schoolQuery) async {
    final query = schoolQuery.trim();
    if (query.isEmpty) return {'officeCode': 'B10', 'schoolCode': '7010260'};
    if (_schoolCodesCache.containsKey(query)) return _schoolCodesCache[query];

    if (RegExp(r'^\d{7}$').hasMatch(query)) {
      return {'officeCode': 'B10', 'schoolCode': query};
    }

    try {
      final url = Uri.parse(
        'https://open.neis.go.kr/hub/schoolInfo'
        '?KEY=$_apiKey'
        '&Type=json'
        '&pIndex=1'
        '&pSize=5'
        '&SCHUL_NM=${Uri.encodeComponent(query)}',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final rows = data?['schoolInfo']?[1]?['row'] as List<dynamic>?;
        if (rows != null && rows.isNotEmpty) {
          final first = rows[0] as Map<String, dynamic>;
          final codes = {
            'officeCode': first['ATPT_OFCDC_SC_CODE']?.toString() ?? 'B10',
            'schoolCode': first['SD_SCHUL_CODE']?.toString() ?? '7010260',
          };
          _schoolCodesCache[query] = codes;
          return codes;
        }
      }
    } catch (_) {}

    return {'officeCode': 'B10', 'schoolCode': '7010260'};
  }

  Future<LiteMealDayInfo> fetchTodayMealInfo(String schoolQuery, DateTime date) async {
    final dateStr = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final cacheKey = '$schoolQuery-$dateStr';

    if (_todayMemoryCache.containsKey(cacheKey)) {
      return _todayMemoryCache[cacheKey]!;
    }

    Future<LiteMealDayInfo?> loadOffline() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('bst_lite_meal_$cacheKey');
        if (raw != null && raw.isNotEmpty) {
          final decoded = json.decode(raw);
          if (decoded is Map<String, dynamic>) {
            final info = LiteMealDayInfo.fromJson(decoded);
            _todayMemoryCache[cacheKey] = info;
            return info;
          }
        }
      } catch (_) {}
      return null;
    }

    void saveOffline(LiteMealDayInfo info) async {
      try {
        _todayMemoryCache[cacheKey] = info;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bst_lite_meal_$cacheKey', json.encode(info.toJson()));
      } catch (_) {}
    }

    final codes = await resolveSchoolCodes(schoolQuery);
    final officeCode = codes?['officeCode'] ?? 'B10';
    final schoolCode = codes?['schoolCode'] ?? '7010260';

    try {
      final url = Uri.parse(
        'https://open.neis.go.kr/hub/mealServiceDietInfo'
        '?KEY=$_apiKey'
        '&Type=json'
        '&pIndex=1'
        '&pSize=1'
        '&ATPT_OFCDC_SC_CODE=$officeCode'
        '&SD_SCHUL_CODE=$schoolCode'
        '&MLSV_YMD=$dateStr'
        '&MMEAL_SC_CODE=2',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final row = data['mealServiceDietInfo']?[1]?['row']?[0];
        if (row != null && row['DDISH_NM'] != null) {
          final raw = row['DDISH_NM'].toString();
          final rawCal = (row['CAL_INFO']?.toString() ?? '').replaceAll('Kcal', 'kcal').trim();
          final info = LiteMealDayInfo.fromNeisRaw(date, raw, calories: rawCal);
          saveOffline(info);
          return info;
        }
      }

      final cached = await loadOffline();
      if (cached != null) return cached;
      return LiteMealDayInfo(date: date, dishes: [], footnotes: ['오늘 등록된 급식 메뉴가 없습니다.']);
    } catch (_) {
      final cached = await loadOffline();
      if (cached != null) return cached;
      return LiteMealDayInfo(date: date, dishes: [], footnotes: ['급식 정보를 불러오는 중 오류가 발생했습니다.']);
    }
  }

  Future<Map<int, LiteMealDayInfo>> fetchMonthMeals(String schoolQuery, int year, int month) async {
    final cacheKey = '$schoolQuery-$year-$month';
    if (_monthMemoryCache.containsKey(cacheKey)) {
      return _monthMemoryCache[cacheKey]!;
    }

    Future<Map<int, LiteMealDayInfo>?> loadOffline() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('bst_lite_month_$cacheKey');
        if (raw != null && raw.isNotEmpty) {
          final decoded = json.decode(raw);
          if (decoded is Map) {
            final Map<int, LiteMealDayInfo> map = {};
            decoded.forEach((k, v) {
              final d = int.tryParse(k.toString());
              if (d != null && v is Map<String, dynamic>) {
                map[d] = LiteMealDayInfo.fromJson(v);
              }
            });
            if (map.isNotEmpty) {
              _monthMemoryCache[cacheKey] = map;
              return map;
            }
          }
        }
      } catch (_) {}
      return null;
    }

    void saveOffline(Map<int, LiteMealDayInfo> map) async {
      try {
        _monthMemoryCache[cacheKey] = map;
        final prefs = await SharedPreferences.getInstance();
        final encodable = map.map((k, v) => MapEntry(k.toString(), v.toJson()));
        await prefs.setString('bst_lite_month_$cacheKey', json.encode(encodable));
      } catch (_) {}
    }

    final codes = await resolveSchoolCodes(schoolQuery);
    final officeCode = codes?['officeCode'] ?? 'B10';
    final schoolCode = codes?['schoolCode'] ?? '7010260';

    final daysInMonth = DateTime(year, month + 1, 0).day;
    final fromDateStr = '$year${month.toString().padLeft(2, '0')}01';
    final toDateStr = '$year${month.toString().padLeft(2, '0')}${daysInMonth.toString().padLeft(2, '0')}';

    try {
      final url = Uri.parse(
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
      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final rows = data?['mealServiceDietInfo']?[1]?['row'] as List<dynamic>?;
        if (rows != null && rows.isNotEmpty) {
          final Map<int, LiteMealDayInfo> map = {};
          for (final row in rows) {
            final ymd = row['MLSV_YMD']?.toString() ?? '';
            if (ymd.length == 8) {
              final d = int.tryParse(ymd.substring(6, 8));
              if (d != null) {
                final date = DateTime(year, month, d);
                final rawDdish = row['DDISH_NM']?.toString() ?? '';
                final rawCal = (row['CAL_INFO']?.toString() ?? '').replaceAll('Kcal', 'kcal').trim();
                map[d] = LiteMealDayInfo.fromNeisRaw(date, rawDdish, calories: rawCal);
              }
            }
          }
          if (map.isNotEmpty) {
            saveOffline(map);
            return map;
          }
        }
      }

      final cached = await loadOffline();
      return cached ?? {};
    } catch (_) {
      final cached = await loadOffline();
      return cached ?? {};
    }
  }
}

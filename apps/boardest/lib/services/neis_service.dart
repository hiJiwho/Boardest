import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/meal_models.dart';

class NeisService {
  static const String _apiKey = '821179541cf54b6288d51741f30e1c90';

  // In-memory cache for resolved school codes: schoolName -> { officeCode, schoolCode }
  static final Map<String, Map<String, String>> _schoolCodesCache = {};

  /// Searches school info to retrieve NEIS ATPT_OFCDC_SC_CODE and SD_SCHUL_CODE
  Future<Map<String, String>?> _resolveSchoolCodes(String schoolName) async {
    // Check cache first
    if (_schoolCodesCache.containsKey(schoolName)) {
      return _schoolCodesCache[schoolName];
    }

    try {
      final queryUrl = Uri.parse(
        'https://open.neis.go.kr/hub/schoolInfo'
        '?KEY=$_apiKey'
        '&Type=json'
        '&pIndex=1'
        '&pSize=5'
        '&SCHUL_NM=${Uri.encodeComponent(schoolName)}',
      );

      final response = await http.get(queryUrl);
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data == null || data['schoolInfo'] == null) return null;

      final rows = data['schoolInfo'][1]['row'] as List<dynamic>;
      if (rows.isEmpty) return null;

      // Extract codes from the first exact/best match
      final firstRow = rows[0] as Map<String, dynamic>;
      final codes = {
        'officeCode': firstRow['ATPT_OFCDC_SC_CODE'] as String,
        'schoolCode': firstRow['SD_SCHUL_CODE'] as String,
      };

      _schoolCodesCache[schoolName] = codes;
      return codes;
    } catch (_) {
      return null;
    }
  }

  /// Fetches lunch meal menu as structured MealDayInfo with allergy annotations
  Future<MealDayInfo> fetchMealDayInfo(String schoolName, DateTime date) async {
    if (AppConfig.isDemoMode || schoolName == 'Demo' || schoolName.toLowerCase().contains('demo') || schoolName.contains('데모')) {
      return MealDayInfo.generateDemo(date);
    }

    final codes = await _resolveSchoolCodes(schoolName);
    if (codes == null) {
      return MealDayInfo(date: date, dishes: [], footnotes: ['학교 기본 정보를 찾을 수 없습니다.']);
    }

    final officeCode = codes['officeCode']!;
    final schoolCode = codes['schoolCode']!;
    
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final dateStr = '$year$month$day';

    try {
      final queryUrl = Uri.parse(
        'https://open.neis.go.kr/hub/mealServiceDietInfo'
        '?KEY=$_apiKey'
        '&Type=json'
        '&ATPT_OFCDC_SC_CODE=$officeCode'
        '&SD_SCHUL_CODE=$schoolCode'
        '&MLSV_YMD=$dateStr'
        '&MMEAL_SC_CODE=2',
      );

      final response = await http.get(queryUrl);
      if (response.statusCode != 200) {
        return MealDayInfo(date: date, dishes: [], footnotes: ['급식을 불러오지 못했습니다.']);
      }

      final data = json.decode(response.body);
      if (data == null || data['mealServiceDietInfo'] == null) {
        return MealDayInfo(date: date, dishes: [], footnotes: []);
      }

      final rows = data['mealServiceDietInfo'][1]['row'] as List<dynamic>;
      if (rows.isEmpty) return MealDayInfo(date: date, dishes: [], footnotes: []);

      final mealRow = rows[0] as Map<String, dynamic>;
      final rawDdish = mealRow['DDISH_NM'] as String? ?? '';
      
      return MealDayInfo.fromNeisRaw(date, rawDdish);
    } catch (_) {
      return MealDayInfo(date: date, dishes: [], footnotes: ['급식 정보를 불러오는 중 오류가 발생했습니다.']);
    }
  }

  /// Fetches lunch meals for an entire month
  Future<Map<int, MealDayInfo>> fetchMonthMeals(String schoolName, int year, int month) async {
    if (AppConfig.isDemoMode || schoolName == 'Demo' || schoolName.toLowerCase().contains('demo') || schoolName.contains('데모')) {
      final Map<int, MealDayInfo> map = {};
      final daysInMonth = DateTime(year, month + 1, 0).day;
      for (int d = 1; d <= daysInMonth; d++) {
        final date = DateTime(year, month, d);
        map[d] = MealDayInfo.generateDemo(date);
      }
      return map;
    }

    final codes = await _resolveSchoolCodes(schoolName);
    if (codes == null) return {};

    final officeCode = codes['officeCode']!;
    final schoolCode = codes['schoolCode']!;

    final daysInMonth = DateTime(year, month + 1, 0).day;
    final fromDateStr = '$year${month.toString().padLeft(2, '0')}01';
    final toDateStr = '$year${month.toString().padLeft(2, '0')}${daysInMonth.toString().padLeft(2, '0')}';

    try {
      final queryUrl = Uri.parse(
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

      final response = await http.get(queryUrl);
      if (response.statusCode != 200) return {};

      final data = json.decode(response.body);
      if (data == null || data['mealServiceDietInfo'] == null) return {};

      final rows = data['mealServiceDietInfo'][1]['row'] as List<dynamic>;
      final Map<int, MealDayInfo> result = {};

      for (final row in rows) {
        final ymd = row['MLSV_YMD'] as String? ?? '';
        final rawDdish = row['DDISH_NM'] as String? ?? '';
        if (ymd.length == 8) {
          final d = int.tryParse(ymd.substring(6, 8));
          if (d != null) {
            final date = DateTime(year, month, d);
            result[d] = MealDayInfo.fromNeisRaw(date, rawDdish);
          }
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Fetches lunch meal menu for a specific date (YYYYMMDD) and cleans allergy indexes
  Future<String> fetchTodayMeal(String schoolName, DateTime date) async {
    final info = await fetchMealDayInfo(schoolName, date);
    if (info.dishes.isEmpty) {
      return info.footnotes.isNotEmpty ? info.footnotes.first : '오늘 등록된 급식 메뉴가 없습니다.';
    }
    return info.dishes.map((d) => '${d.name} ${d.allergyDisplay}'.trim()).join('\n');
  }

  /// Cleans HTML breaks and strips allergy index numbers (e.g. "(1.5.13.)")
  String _cleanMealMenu(String rawMenu) {
    if (rawMenu.isEmpty) return '급식 메뉴가 비어 있습니다.';

    // Replace HTML <br/> with newline
    var cleaned = rawMenu.replaceAll(RegExp(r'<br\s*/?>'), '\n');

    // Strip out parentheses containing allergy numbers (e.g. "(1.2.3.4.)" or "(5.9.13.)")
    final RegExp allergyRegExp = RegExp(r'\([0-9. \t\n]+\)');
    cleaned = cleaned.replaceAll(allergyRegExp, '');

    // Cleanup whitespace, asterisks, or duplicate spaces
    final lines = cleaned
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    return lines.join('\n');
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

      final response = await http.get(queryUrl);
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


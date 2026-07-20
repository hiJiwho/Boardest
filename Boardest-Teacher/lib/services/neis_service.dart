import 'dart:convert';
import 'package:http/http.dart' as http;

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

  /// Fetches lunch meal menu for a specific date (YYYYMMDD) and cleans allergy indexes
  Future<String> fetchTodayMeal(String schoolName, DateTime date) async {
    final codes = await _resolveSchoolCodes(schoolName);
    if (codes == null) {
      return '학교 기본 정보를 나이스 API에서 찾을 수 없습니다.';
    }

    final officeCode = codes['officeCode']!;
    final schoolCode = codes['schoolCode']!;
    
    // Format date as YYYYMMDD
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
        '&MMEAL_SC_CODE=2', // 2 represents standard High/Middle School Lunch (중식)
      );

      final response = await http.get(queryUrl);
      if (response.statusCode != 200) return '급식을 불러오지 못했습니다. (HTTP ${response.statusCode})';

      final data = json.decode(response.body);
      
      // If no lunch menu is registered (e.g., weekends, holidays)
      if (data == null || data['mealServiceDietInfo'] == null) {
        return '오늘 등록된 급식 메뉴가 없습니다.';
      }

      final rows = data['mealServiceDietInfo'][1]['row'] as List<dynamic>;
      if (rows.isEmpty) return '오늘 등록된 급식 메뉴가 없습니다.';

      final mealRow = rows[0] as Map<String, dynamic>;
      final rawDdish = mealRow['DDISH_NM'] as String? ?? '';
      
      return _cleanMealMenu(rawDdish);
    } catch (e) {
      return '급식 정보를 받아오는 중 오류가 발생했습니다.';
    }
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

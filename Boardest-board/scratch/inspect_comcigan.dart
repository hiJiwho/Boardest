import 'dart:convert';
import 'package:cp949_codec/cp949_codec.dart';
import 'package:http/http.dart' as http;

void main() async {
  final defaultUrl = 'http://xn--s39aj90b0nb2xw6xh.kr';
  try {
    print('Fetching Comcigan base...');
    final response = await http.get(Uri.parse(defaultUrl));
    String html = cp949.decode(response.bodyBytes);
    final RegExp frameRegExp = RegExp(r"""<frame\s+[^>]*src=["']([^"']+)["']""", caseSensitive: false);
    final match = frameRegExp.firstMatch(html);
    if (match == null) return;
    
    final resolvedUri = Uri.parse(defaultUrl).resolve(match.group(1)!);
    final baseUrl = '${resolvedUri.scheme}://${resolvedUri.host}:${resolvedUri.port}';
    final frameResponse = await http.get(resolvedUri);
    final frameHtml = cp949.decode(frameResponse.bodyBytes);
    
    final RegExp schoolRaRegExp = RegExp(r"url\s*:\s*'\s*\./([^']+)'", caseSensitive: false);
    final schoolRaMatch = schoolRaRegExp.firstMatch(frameHtml);
    if (schoolRaMatch == null) return;
    
    final extractCode = '/${schoolRaMatch.group(1)!}';
    final idx = frameHtml.indexOf("sc_data('");
    final subStr = frameHtml.substring(idx, idx + 50).replaceAll(' ', '');
    final RegExp argRegExp = RegExp(r"\((.*?)\)");
    final argMatch = argRegExp.firstMatch(subStr);
    if (argMatch == null) return;
    final scData = argMatch.group(1)!.split(',').map((s) => s.replaceAll("'", "").replaceAll('"', '')).toList();
    
    final schoolCode = 44134; // 양동중학교
    final String s7 = '${scData[0]}$schoolCode';
    final String payload = '${s7}_0_${scData[2]}';
    final String base64Payload = base64.encode(utf8.encode(payload));
    final String path = extractCode.split('?')[0];
    final String url = '$baseUrl$path?$base64Payload';
    
    print('Fetching timetable raw from $url...');
    final tResponse = await http.get(Uri.parse(url));
    final bodyBytes = tResponse.bodyBytes;
    String body;
    try {
      body = utf8.decode(bodyBytes);
    } catch (_) {
      body = cp949.decode(bodyBytes);
    }
    
    final int firstBrace = body.indexOf('{');
    final int lastBrace = body.lastIndexOf('}');
    final cleanBody = body.substring(firstBrace, lastBrace + 1);
    final Map<String, dynamic> data = json.decode(cleanBody);
    
    print('School Name: ${data['학교명']}');
    final List<dynamic> teachers = data['자료446'] ?? [];
    final List<dynamic> subjects = data['자료492'] ?? [];
    
    // Grade 2, Class 1
    final int grade = 2;
    final int classNum = 1;
    
    final rawDaily = data['자료147'];
    final rawOriginal = data['자료481'];
    
    print('\n--- SUBJECTS LIST ---');
    for (int i = 0; i < subjects.length; i++) {
      if (subjects[i].toString().isNotEmpty) {
        print('$i: ${subjects[i]}');
      }
    }
    
    print('\n--- TEACHERS LIST ---');
    for (int i = 0; i < teachers.length; i++) {
      if (teachers[i].toString().isNotEmpty) {
        print('$i: ${teachers[i]}');
      }
    }
    
    print('\n--- TIMETABLE (Grade $grade, Class $classNum) ---');
    for (int weekday = 1; weekday <= 5; weekday++) {
      print('Weekday $weekday:');
      for (int period = 1; period <= 8; period++) {
        int dVal = 0;
        int oVal = 0;
        try {
          dVal = rawDaily[grade][classNum][weekday][period];
        } catch (_) {}
        try {
          oVal = rawOriginal[grade][classNum][weekday][period];
        } catch (_) {}
        print('  Period $period: Daily=$dVal, Original=$oVal');
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}

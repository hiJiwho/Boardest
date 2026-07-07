import 'dart:convert';
import 'package:cp949_codec/cp949_codec.dart';
import 'package:http/http.dart' as http;

void main() async {
  final defaultUrl = 'http://xn--s39aj90b0nb2xw6xh.kr';
  try {
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
    
    print('전일제:');
    print(data['전일제']);
    print('요일별시수:');
    print(data['요일별시수']);
  } catch (e) {
    print('Error: $e');
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class YouTubeEmbedService {
  static final RegExp _ytRegex = RegExp(
    r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/|youtube\.com\/shorts\/)([^"&?\/\s]{11})',
    caseSensitive: false,
  );

  /// Extract 11-character YouTube video ID from any raw YouTube URL
  static String? extractVideoId(String url) {
    final match = _ytRegex.firstMatch(url.trim());
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  /// Convert any raw YouTube link to ad-free no-cookie embed URL with optional start/end trim segment
  static String convertToEmbedUrl(String rawUrl, {int? startSeconds, int? endSeconds}) {
    final videoId = extractVideoId(rawUrl);
    if (videoId != null && videoId.isNotEmpty) {
      var embed = 'https://www.youtube-nocookie.com/embed/$videoId?autoplay=1&modestbranding=1&rel=0&enablejsapi=1';
      if (startSeconds != null && startSeconds > 0) embed += '&start=$startSeconds';
      if (endSeconds != null && endSeconds > 0) embed += '&end=$endSeconds';
      return embed;
    }
    var trimmed = rawUrl.trim();
    if (!trimmed.startsWith('http')) trimmed = 'https://$trimmed';
    return trimmed;
  }

  /// 서드파티 웹 변환 사이트(yt2mp4 등) 없이 유튜브 공식 CDN(googlevideo.com)에서
  /// 영상 스트림을 직접 다운로드하는 로컬 직접 다운로드 서비스 (교육청 차단 우회)
  static Future<File?> downloadVideoDirectly(
    String youtubeUrl, {
    String? customSavePath,
    void Function(double progress, String status)? onProgress,
  }) async {
    final videoId = extractVideoId(youtubeUrl);
    if (videoId == null || videoId.isEmpty) return null;

    onProgress?.call(0.05, '🔍 유튜브 공식 CDN 스트림 주소 탐색 중…');

    try {
      final appDir = await getApplicationSupportDirectory();
      final ytDir = Directory(p.join(appDir.path, 'BstSave', 'YOUTUBE'));
      if (!ytDir.existsSync()) ytDir.createSync(recursive: true);

      final targetPath = customSavePath ?? p.join(ytDir.path, '$videoId.mp4');
      final targetFile = File(targetPath);

      if (targetFile.existsSync() && targetFile.lengthSync() > 1024 * 1024) {
        onProgress?.call(1.0, '⚡ 이미 로컬에 저장된 mp4 영상을 확인했습니다.');
        return targetFile;
      }

      // 1. yt-dlp 로컬 실행 파일 존재 시 우선 사용
      try {
        final ytDlpResult = await Process.run('yt-dlp', [
          '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
          '-o', targetPath,
          youtubeUrl,
        ]);
        if (ytDlpResult.exitCode == 0 && targetFile.existsSync()) {
          onProgress?.call(1.0, '✅ yt-dlp 로컬 직접 다운로드 완료!');
          return targetFile;
        }
      } catch (_) {}

      // 2. yt-dlp 미설치 시 YouTube 공식 PlayerResponse HTML 직접 파싱 (서드파티 사이트 이용 안 함)
      final watchUri = Uri.parse('https://www.youtube.com/watch?v=$videoId&bpctr=9999999999&has_verified=1');
      final res = await http.get(watchUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
      }).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        onProgress?.call(0.0, '❌ 유튜브 페이지 요청 실패: HTTP ${res.statusCode}');
        return null;
      }

      final html = res.body;
      String? streamUrl;

      // Extract ytInitialPlayerResponse JSON
      final match = RegExp(r'ytInitialPlayerResponse\s*=\s*(\{.+?\});</script>').firstMatch(html);
      if (match != null) {
        final jsonStr = match.group(1);
        if (jsonStr != null) {
          final data = jsonDecode(jsonStr);
          final formats = data['streamingData']?['formats'] as List?;
          if (formats != null && formats.isNotEmpty) {
            for (final f in formats) {
              if (f['url'] != null && (f['mimeType'] as String? ?? '').contains('video/mp4')) {
                streamUrl = f['url'] as String;
                break;
              }
            }
            streamUrl ??= formats.first['url'] as String?;
          }
        }
      }

      if (streamUrl == null || streamUrl.isEmpty) {
        onProgress?.call(0.0, '❌ 스트림 주소를 추출하지 못했습니다. (임베드 뷰어로 시청 가능)');
        return null;
      }

      onProgress?.call(0.3, '📥 googlevideo.com 공식 서버에서 MP4 비디오 직접 다운로드 중…');

      // Download bytes from YouTube's official CDN (googlevideo.com)
      final videoRes = await http.get(Uri.parse(streamUrl)).timeout(const Duration(minutes: 5));
      if (videoRes.statusCode == 200 && videoRes.bodyBytes.isNotEmpty) {
        await targetFile.writeAsBytes(videoRes.bodyBytes, flush: true);
        onProgress?.call(1.0, '🎉 로컬 MP4 비디오 직접 다운로드 성공!');
        return targetFile;
      }
    } catch (e) {
      debugPrint('[YouTubeEmbedService] Direct download error: $e');
      onProgress?.call(0.0, '❌ 로컬 다운로드 오류: $e');
    }

    return null;
  }
}

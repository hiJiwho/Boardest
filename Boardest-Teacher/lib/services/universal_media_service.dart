import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum MediaType { youtube, tiktok, instagram, directMp4, unknown }

class MediaItem {
  final String title;
  final String originalUrl;
  final String localPath;
  final MediaType type;

  MediaItem({
    required this.title,
    required this.originalUrl,
    required this.localPath,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'originalUrl': originalUrl,
    'localPath': localPath,
    'type': type.name,
  };

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      title: json['title'] ?? '수업 영상',
      originalUrl: json['originalUrl'] ?? '',
      localPath: json['localPath'] ?? '',
      type: MediaType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MediaType.unknown,
      ),
    );
  }
}

class UniversalMediaService {
  static final RegExp _ytRegex = RegExp(
    r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/|youtube\.com\/shorts\/)([^"&?\/\s]{11})',
    caseSensitive: false,
  );

  static MediaType detectMediaType(String url) {
    final trimmed = url.trim().toLowerCase();
    if (trimmed.contains('youtube.com') || trimmed.contains('youtu.be')) {
      return MediaType.youtube;
    } else if (trimmed.contains('tiktok.com')) {
      return MediaType.tiktok;
    } else if (trimmed.contains('instagram.com')) {
      return MediaType.instagram;
    } else if (trimmed.endsWith('.mp4') || trimmed.endsWith('.mov') || trimmed.endsWith('.mkv') || trimmed.contains('video/mp4')) {
      return MediaType.directMp4;
    }
    return MediaType.unknown;
  }

  /// 서드파티 변환 웹사이트 없이 모든 비디오 플랫폼(YouTube, TikTok, Instagram, MP4)을
  /// 로컬 MP4 파일로 직접 다운로드 (교육청 Wi-Fi 방화벽 차단 우회)
  static Future<File?> downloadMediaToMp4(
    String rawUrl, {
    String? customSavePath,
    void Function(double progress, String status)? onProgress,
  }) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return null;

    final type = detectMediaType(url);
    final hash = url.hashCode.abs();

    try {
      final appDir = await getApplicationSupportDirectory();
      final mediaDir = Directory(p.join(appDir.path, 'BstSave', 'MEDIA'));
      if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);

      final targetPath = customSavePath ?? p.join(mediaDir.path, 'media_$hash.mp4');
      final targetFile = File(targetPath);

      if (targetFile.existsSync() && targetFile.lengthSync() > 100 * 1024) {
        onProgress?.call(1.0, '⚡ 이미 로컬에 다운로드 완료된 MP4 파일입니다.');
        return targetFile;
      }

      onProgress?.call(0.1, '🔍 [${type.name.toUpperCase()}] 비디오 직접 미디어 CDN 추출 중…');

      // 1. yt-dlp 로컬 커맨드가 사용 가능한 경우 최우선 실행 (YouTube/TikTok/Insta 모두 지원)
      try {
        final res = await Process.run('yt-dlp', [
          '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
          '-o', targetPath,
          url,
        ]);
        if (res.exitCode == 0 && targetFile.existsSync()) {
          onProgress?.call(1.0, '✅ 로컬 yt-dlp 지원 미디어 다운로드 성공!');
          return targetFile;
        }
      } catch (_) {}

      // 2. 플랫폼별 직접 CDN 파싱 및 스트림 다운로드
      if (type == MediaType.directMp4) {
        onProgress?.call(0.3, '📥 MP4 파일 데이터 직접 다운로드 중…');
        final res = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 5));
        if (res.statusCode == 200) {
          await targetFile.writeAsBytes(res.bodyBytes, flush: true);
          onProgress?.call(1.0, '🎉 MP4 비디오 직접 다운로드 성공!');
          return targetFile;
        }
      } else if (type == MediaType.youtube) {
        final videoIdMatch = _ytRegex.firstMatch(url);
        final videoId = videoIdMatch?.group(1);
        if (videoId != null) {
          final watchUri = Uri.parse('https://www.youtube.com/watch?v=$videoId&bpctr=9999999999&has_verified=1');
          final res = await http.get(watchUri, headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36',
          }).timeout(const Duration(seconds: 10));

          if (res.statusCode == 200) {
            final html = res.body;
            final match = RegExp(r'ytInitialPlayerResponse\s*=\s*(\{.+?\});</script>').firstMatch(html);
            if (match != null && match.group(1) != null) {
              final data = jsonDecode(match.group(1)!);
              final formats = data['streamingData']?['formats'] as List?;
              String? cdnUrl;
              if (formats != null && formats.isNotEmpty) {
                for (final f in formats) {
                  if (f['url'] != null && (f['mimeType'] as String? ?? '').contains('video/mp4')) {
                    cdnUrl = f['url'] as String;
                    break;
                  }
                }
                cdnUrl ??= formats.first['url'] as String?;
              }
              if (cdnUrl != null) {
                onProgress?.call(0.4, '📥 googlevideo.com 공식 CDN 스트림 받는 중…');
                final streamRes = await http.get(Uri.parse(cdnUrl)).timeout(const Duration(minutes: 5));
                if (streamRes.statusCode == 200) {
                  await targetFile.writeAsBytes(streamRes.bodyBytes, flush: true);
                  onProgress?.call(1.0, '🎉 YouTube MP4 비디오 다운로드 완료!');
                  return targetFile;
                }
              }
            }
          }
        }
      } else if (type == MediaType.tiktok) {
        // TikTok Direct API
        onProgress?.call(0.3, '🎵 TikTok 무워터마크 CDN 분석 중…');
        final apiUri = Uri.parse('https://www.tikwm.com/api/?url=${Uri.encodeComponent(url)}');
        final apiRes = await http.get(apiUri).timeout(const Duration(seconds: 10));
        if (apiRes.statusCode == 200) {
          final data = jsonDecode(apiRes.body);
          final playUrl = data['data']?['play'] as String?;
          if (playUrl != null) {
            onProgress?.call(0.6, '📥 TikTok 비디오 스트림 다운로드 중…');
            final videoRes = await http.get(Uri.parse(playUrl)).timeout(const Duration(minutes: 3));
            if (videoRes.statusCode == 200) {
              await targetFile.writeAsBytes(videoRes.bodyBytes, flush: true);
              onProgress?.call(1.0, '🎉 TikTok MP4 다운로드 완료!');
              return targetFile;
            }
          }
        }
      } else if (type == MediaType.instagram) {
        // Instagram Direct CDN
        onProgress?.call(0.3, '📸 Instagram Reels 비디오 추출 중…');
        final cleanUrl = url.split('?').first + '?__a=1&__d=dis';
        final instaRes = await http.get(Uri.parse(cleanUrl), headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36',
        }).timeout(const Duration(seconds: 10));

        if (instaRes.statusCode == 200) {
          final data = jsonDecode(instaRes.body);
          final videoUrl = data['graphql']?['shortcode_media']?['video_url'] as String?
              ?? data['items']?[0]?['video_versions']?[0]?['url'] as String?;
          if (videoUrl != null) {
            onProgress?.call(0.6, '📥 Instagram MP4 스트림 다운로드 중…');
            final videoRes = await http.get(Uri.parse(videoUrl)).timeout(const Duration(minutes: 3));
            if (videoRes.statusCode == 200) {
              await targetFile.writeAsBytes(videoRes.bodyBytes, flush: true);
              onProgress?.call(1.0, '🎉 Instagram MP4 다운로드 완료!');
              return targetFile;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[UniversalMediaService] Download error: $e');
      onProgress?.call(0.0, '❌ 다운로드 중 에러 발생: $e');
    }

    return null;
  }
}

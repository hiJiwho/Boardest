import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeStreamExtractor {
  Future<String?> getVideoStreamUrl(String videoId) async {
    final yt = YoutubeExplode();
    try {
      var manifest = await yt.videos.streamsClient.getManifest(videoId);
      var streamInfo = manifest.muxed.withHighestBitrate();
      return streamInfo.url.toString();
    } catch (e) {
      debugPrint('Error extracting YouTube stream: $e');
      return null;
    } finally {
      yt.close();
    }
  }
}

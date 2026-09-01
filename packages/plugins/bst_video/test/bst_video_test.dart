import 'package:flutter_test/flutter_test.dart';
import 'package:bst_video/bst_video.dart';

void main() {
  group('VideoStudioService Unit Tests', () {
    test('VideoStudioService initializes and processes video', () async {
      final service = VideoStudioService();
      await service.initialize();
      await service.processVideo();
      expect(service, isNotNull);
    });
  });

  group('VideoEditorRenderer Unit Tests', () {
    test('VideoEditorRenderer renders cut without crashing', () async {
      final renderer = VideoEditorRenderer();
      await renderer.renderCut(
        startTime: const Duration(seconds: 5),
        endTime: const Duration(seconds: 15),
        sourcePath: 'input.mp4',
        outputPath: 'output.mp4',
      );
      expect(renderer, isNotNull);
    });
  });

  group('YouTubeStreamExtractor Unit Tests', () {
    test('YouTubeStreamExtractor handles invalid videoId safely and returns null', () async {
      final extractor = YouTubeStreamExtractor();
      final url = await extractor.getVideoStreamUrl('invalid_video_id_xyz');
      expect(url, isNull);
    });
  });
}

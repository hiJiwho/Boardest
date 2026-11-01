import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:bst_pen/bst_pen.dart';

/// Synthetic test fixtures and mock models for Boardest E2E testing
class E2ETestFixtures {
  /// Standardized Pen File Name Generator according to PROJECT.md Contract
  static String formatPenFileName({
    required String? classId,
    required String dHash,
  }) {
    final cleanHash = dHash.trim();
    if (classId == null || classId.trim().isEmpty || classId.trim() == '기본') {
      return '기본_$cleanHash.pen';
    }
    final trimmed = classId.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      return '$trimmed$cleanHash.pen';
    }
    return '[$trimmed]$cleanHash.pen';
  }

  /// COM OleMessageFilter simulator according to PROJECT.md Contract
  static int oleMessageFilterRetryRejectedCall({
    required int dwTickCount,
    required int dwRejectType, // 1: SERVERCALL_REJECTED, 2: SERVERCALL_RETRYLATER
  }) {
    if (dwTickCount >= 10000) {
      return -1; // Cancel call after 10s timeout
    }
    if (dwRejectType == 1 || dwRejectType == 2) {
      return 150; // Retry after 150ms
    }
    return -1;
  }

  /// UpdateService version comparator according to UpdateService logic
  static bool isNewerVersion(String target, String current) {
    final t = target.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final c = current.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final maxLen = t.length > c.length ? t.length : c.length;
    for (var i = 0; i < maxLen; i++) {
      final tv = i < t.length ? t[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (tv != cv) return tv > cv;
    }
    return false;
  }

  /// UpdateService MSIX asset selector simulator
  static String? selectReleaseAssetUrl(List<String> assetNames, {bool isWindows = true, bool isCloud = false}) {
    if (!isWindows) {
      // Android APK selection
      for (final name in assetNames) {
        if (name.endsWith('.apk') &&
            !name.contains('teacher') &&
            !name.contains('lite') &&
            (isCloud ? name.contains('cloud') : !name.contains('cloud'))) {
          return 'https://releases.boardest/$name';
        }
      }
      return null;
    }

    // Explicit .msix priority over .appx
    String? msixMatch;
    String? appxFallback;
    for (final name in assetNames) {
      if (name.contains('teacher') || name.contains('lite') || name.contains('overlay')) {
        continue;
      }
      if (isCloud && !name.contains('cloud') && !name.contains('bcld')) {
        continue;
      }
      if (!isCloud && (name.contains('cloud') || name.contains('bcld'))) {
        continue;
      }

      if (name.endsWith('.msix')) {
        msixMatch ??= 'https://releases.boardest/$name';
      } else if (name.endsWith('.appx')) {
        appxFallback ??= 'https://releases.boardest/$name';
      }
    }
    return msixMatch ?? appxFallback;
  }

  /// Create sample AnnotationStroke with custom points
  static AnnotationStroke createSampleStroke({
    required int pageIndex,
    required Color color,
    required double strokeWidth,
    List<Offset> offsets = const [Offset(100, 100), Offset(200, 200), Offset(300, 250)],
  }) {
    return AnnotationStroke(
      points: offsets,
      color: color,
      strokeWidth: strokeWidth,
    );
  }

  /// Create sample PenDocument in memory
  static PenDocument createSamplePenDoc({
    required String title,
    required String classroom,
    required int pageCount,
  }) {
    final Map<int, List<AnnotationStroke>> pagesMap = {};
    for (int i = 1; i <= pageCount; i++) {
      pagesMap[i] = [
        createSampleStroke(
          pageIndex: i,
          color: Colors.blue,
          strokeWidth: 3.0,
          offsets: [Offset(50.0 * i, 100.0), Offset(100.0 * i, 150.0)],
        ),
      ];
    }
    return PenDocument.fromStrokesMap(
      title: title,
      strokesPages: pagesMap,
      classroom: classroom,
    );
  }

  /// Fast dHash calculator simulation
  static String computeDHashFromText(String content) {
    int hash = 0;
    for (int i = 0; i < content.length; i++) {
      hash = ((hash << 5) - hash) + content.codeUnitAt(i);
      hash |= 0;
    }
    return 'dhash_${hash.abs()}';
  }

  /// Canva DOM slide counter regex parser
  static int? extractCanvaSlideNumber(String domText) {
    final match = RegExp(r'\b(\d+)\s*/\s*(\d+)\b').firstMatch(domText);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Presentation URL formatter (Canva, Google Slides, MiriCanvas)
  static String formatPresentUrl(String rawInput) {
    var url = rawInput.trim();
    if (url.isEmpty) return 'https://docs.google.com/presentation';

    if (url.contains('<iframe') || url.contains('src=')) {
      final srcMatch = RegExp(r'''src\s*=\s*["']([^"']+)["']''', caseSensitive: false).firstMatch(url);
      if (srcMatch != null && srcMatch.group(1) != null) {
        url = srcMatch.group(1)!.trim();
      }
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final segs = uri?.pathSegments.where((e) => e.isNotEmpty).toList() ?? const <String>[];

    if (host.contains('canva.com')) {
      final di = segs.indexOf('design');
      if (di >= 0 && segs.length >= di + 3) {
        final id = segs[di + 1];
        final token = segs[di + 2];
        return 'https://www.canva.com/design/$id/$token/view?embed';
      }
      if (di >= 0 && segs.length == di + 2) {
        return 'https://www.canva.com/design/${segs[di + 1]}/view?embed';
      }
      if (!url.contains('embed')) {
        return url.contains('?') ? '$url&embed' : '$url?embed';
      }
      return url;
    }

    if (host.contains('docs.google.com')) {
      if (url.contains('/presentation/d/')) {
        if (url.contains('/embed') || url.contains('/pubembed')) return url;
        final m = RegExp(r'/presentation/d/([a-zA-Z0-9_-]+)').firstMatch(url);
        if (m != null) {
          return 'https://docs.google.com/presentation/d/${m.group(1)}/embed?start=false&loop=false&delayms=3000';
        }
      }
      if (url.contains('/document/d/') && url.contains('/edit')) {
        return url.replaceAll(RegExp(r'/edit.*$'), '/preview');
      }
    }

    return url;
  }
}

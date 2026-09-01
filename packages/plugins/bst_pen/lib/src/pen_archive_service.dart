import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'package:path/path.dart' as p;
import 'annotation_canvas.dart';
import 'svg_stroke_converter.dart';

/// .pen 판서 문서 데이터 모델
class PenDocument {
  final String title;
  final int totalPages;
  final String createdAt;
  final String updatedAt;
  final String? classroom;
  final String? subject;
  final double canvasWidth;
  final double canvasHeight;
  final Map<int, String> pages; // pageIndex -> SVG String
  final Map<String, Uint8List> media; // fileName -> Bytes

  PenDocument({
    required this.title,
    required this.totalPages,
    required this.createdAt,
    required this.updatedAt,
    this.classroom,
    this.subject,
    this.canvasWidth = 1920,
    this.canvasHeight = 1080,
    required this.pages,
    Map<String, Uint8List>? media,
  }) : media = media ?? {};

  /// AnnotationStroke 맵으로부터 PenDocument 생성
  factory PenDocument.fromStrokesMap({
    required String title,
    required Map<int, List<AnnotationStroke>> strokesPages,
    String? classroom,
    String? subject,
    double canvasWidth = 1920,
    double canvasHeight = 1080,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final Map<int, String> svgPages = {};

    strokesPages.forEach((pageIdx, strokes) {
      svgPages[pageIdx] = SvgStrokeConverter.strokesToSvg(
        strokes,
        width: canvasWidth,
        height: canvasHeight,
      );
    });

    final total = svgPages.isEmpty ? 1 : svgPages.keys.reduce((a, b) => a > b ? a : b);

    return PenDocument(
      title: title,
      totalPages: total,
      createdAt: now,
      updatedAt: now,
      classroom: classroom,
      subject: subject,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      pages: svgPages,
    );
  }

  /// PenDocument의 SVG 페이지를 AnnotationStroke 맵으로 변환
  Map<int, List<AnnotationStroke>> toStrokesMap() {
    final Map<int, List<AnnotationStroke>> res = {};
    pages.forEach((pageIdx, svgStr) {
      res[pageIdx] = SvgStrokeConverter.svgToStrokes(svgStr);
    });
    return res;
  }

  Map<String, dynamic> toManifestJson() {
    return {
      'version': '3.0.0',
      'format': 'bst_pen_v3',
      'title': title,
      'totalPages': totalPages,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (classroom != null) 'classroom': classroom,
      if (subject != null) 'subject': subject,
      'canvasWidth': canvasWidth,
      'canvasHeight': canvasHeight,
    };
  }
}

/// .pen 파일 패킹(Archive) & 압축 해제 유틸리티 (ZIP Store Mode / Level=0)
class PenArchiveService {
  static final PenArchiveService instance = PenArchiveService._internal();
  PenArchiveService._internal();

  /// PenDocument를 ZIP Store Mode (무압축 0ms 지연) .pen 바이트로 패킹
  Uint8List packToPenBytes(PenDocument doc) {
    final archive = Archive();

    // 1. manifest.json
    final manifestBytes = utf8.encode(jsonEncode(doc.toManifestJson()));
    archive.addFile(ArchiveFile.noCompress('manifest.json', manifestBytes.length, manifestBytes));

    // 2. pages/page_X.svg
    doc.pages.forEach((pageIdx, svgStr) {
      final svgBytes = utf8.encode(svgStr);
      archive.addFile(ArchiveFile.noCompress('pages/page_$pageIdx.svg', svgBytes.length, svgBytes));
    });

    // 3. media/
    doc.media.forEach((fileName, bytes) {
      archive.addFile(ArchiveFile.noCompress('media/$fileName', bytes.length, bytes));
    });

    // Zip Level 0 (Store Mode)
    final zipBytes = ZipEncoder().encode(archive, level: 0);
    return Uint8List.fromList(zipBytes);
  }

  /// .pen ZIP 바이트로부터 PenDocument 언패킹
  PenDocument? unpackFromPenBytes(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      String? manifestStr;
      final Map<int, String> pages = {};
      final Map<String, Uint8List> media = {};

      for (final file in archive) {
        if (file.isFile) {
          final name = file.name.replaceAll('\\', '/');
          if (name == 'manifest.json' || name == 'info.json') {
            manifestStr = utf8.decode(file.content as List<int>);
          } else if (name.startsWith('pages/page_') && name.endsWith('.svg')) {
            final match = RegExp(r'pages/page_(\d+)\.svg').firstMatch(name);
            if (match != null) {
              final pageIdx = int.parse(match.group(1)!);
              pages[pageIdx] = utf8.decode(file.content as List<int>);
            }
          } else if (name.startsWith('media/')) {
            final fileName = p.basename(name);
            media[fileName] = Uint8List.fromList(file.content as List<int>);
          }
        }
      }

      final Map<String, dynamic> manifest = manifestStr != null ? jsonDecode(manifestStr) : {};

      return PenDocument(
        title: manifest['title'] ?? '무제 판서',
        totalPages: manifest['totalPages'] ?? (pages.isEmpty ? 1 : pages.length),
        createdAt: manifest['createdAt'] ?? DateTime.now().toUtc().toIso8601String(),
        updatedAt: manifest['updatedAt'] ?? DateTime.now().toUtc().toIso8601String(),
        classroom: manifest['classroom'],
        subject: manifest['subject'],
        canvasWidth: (manifest['canvasWidth'] as num?)?.toDouble() ?? 1920.0,
        canvasHeight: (manifest['canvasHeight'] as num?)?.toDouble() ?? 1080.0,
        pages: pages,
        media: media,
      );
    } catch (e) {
      debugPrint('[PenArchiveService] unpack error: $e');
      return null;
    }
  }

  /// 로컬 파일로 저장 (Store Mode 단일 .pen)
  Future<bool> saveLocalPenFile(String filePath, PenDocument doc) async {
    if (kIsWeb) return false;
    try {
      final bytes = packToPenBytes(doc);
      final file = File(filePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } catch (e) {
      debugPrint('[PenArchiveService] saveLocalPenFile error: $e');
      return false;
    }
  }

  /// 로컬 .pen 파일 로드
  Future<PenDocument?> loadLocalPenFile(String filePath) async {
    if (kIsWeb) return null;
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return unpackFromPenBytes(bytes);
    } catch (e) {
      debugPrint('[PenArchiveService] loadLocalPenFile error: $e');
      return null;
    }
  }
}

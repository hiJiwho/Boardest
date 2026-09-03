import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class MaskedRegion {
  final int startMs;
  final int endMs;
  final String? label;

  MaskedRegion({required this.startMs, required this.endMs, this.label});

  Map<String, dynamic> toJson() => {
    'startMs': startMs,
    'endMs': endMs,
    'label': label,
  };

  factory MaskedRegion.fromJson(Map<String, dynamic> json) => MaskedRegion(
    startMs: (json['startMs'] as num?)?.toInt() ?? 0,
    endMs: (json['endMs'] as num?)?.toInt() ?? 0,
    label: json['label'] as String?,
  );
}

class TimelineIndex {
  final int ms;
  final String label;

  TimelineIndex({required this.ms, required this.label});

  Map<String, dynamic> toJson() => {
    'ms': ms,
    'label': label,
  };

  factory TimelineIndex.fromJson(Map<String, dynamic> json) => TimelineIndex(
    ms: (json['ms'] as num).toInt(),
    label: json['label'] as String,
  );
}

class BstVideoProject {
  final int version;
  final String title;
  final List<MaskedRegion> maskedRegions;
  final List<TimelineIndex> timeline;

  BstVideoProject({
    required this.version,
    required this.title,
    required this.maskedRegions,
    required this.timeline,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'title': title,
    'maskedRegions': maskedRegions.map((e) => e.toJson()).toList(),
    'timeline': timeline.map((e) => e.toJson()).toList(),
  };

  factory BstVideoProject.fromJson(Map<String, dynamic> json) => BstVideoProject(
    version: (json['version'] as num?)?.toInt() ?? 2,
    title: json['title'] as String? ?? 'Untitled',
    maskedRegions: (json['maskedRegions'] as List<dynamic>? ?? [])
        .map((e) => MaskedRegion.fromJson(e as Map<String, dynamic>))
        .toList(),
    timeline: (json['timeline'] as List<dynamic>? ?? [])
        .map((e) => TimelineIndex.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class BstVideoService {
  BstVideoService._privateConstructor();
  static final BstVideoService instance = BstVideoService._privateConstructor();

  Future<BstVideoProject> loadProject(String bstVideoFilePath) async {
    final file = File(bstVideoFilePath);
    if (!await file.exists()) {
      throw Exception('File not found: $bstVideoFilePath');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final projectFile = archive.findFile('project.bstsave');
    if (projectFile == null) {
      throw Exception('project.bstsave not found in archive');
    }

    final jsonContent = utf8.decode(projectFile.content as List<int>);
    final map = jsonDecode(jsonContent) as Map<String, dynamic>;
    return BstVideoProject.fromJson(map);
  }

  Future<String> getMp4Path(String bstVideoFilePath) async {
    final file = File(bstVideoFilePath);
    if (!await file.exists()) {
      throw Exception('File not found');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final mp4File = archive.findFile('rendered.mp4');
    if (mp4File == null) {
      throw Exception('rendered.mp4 not found in archive');
    }

    Directory cacheDir;
    if (Platform.isWindows) {
      cacheDir = Directory.systemTemp.createTempSync('bstvideo_cache_');
    } else {
      cacheDir = await getTemporaryDirectory();
    }
    
    final tempMp4 = File(p.join(cacheDir.path, 'rendered_${DateTime.now().millisecondsSinceEpoch}.mp4'));
    await tempMp4.writeAsBytes(mp4File.content as List<int>);
    
    return p.normalize(tempMp4.path);
  }

  Future<void> saveProject(String bstVideoFilePath, BstVideoProject project) async {
    final file = File(bstVideoFilePath);
    if (!await file.exists()) {
      throw Exception('File not found');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final newArchive = Archive();
    final projectJson = jsonEncode(project.toJson());
    final projectBytes = utf8.encode(projectJson);

    bool projectReplaced = false;

    for (final f in archive) {
      if (f.name == 'project.bstsave') {
        newArchive.addFile(ArchiveFile('project.bstsave', projectBytes.length, projectBytes));
        projectReplaced = true;
      } else {
        newArchive.addFile(f);
      }
    }

    if (!projectReplaced) {
      newArchive.addFile(ArchiveFile('project.bstsave', projectBytes.length, projectBytes));
    }

    final encoder = ZipEncoder();
    final zipData = encoder.encode(newArchive, level: 0);
    if (zipData != null) {
      await file.writeAsBytes(zipData, flush: true);
    }
  }

  Future<String> packageBstVideo({
    required String outputPath,
    required String renderedMp4,
    required String originalMp4,
    required BstVideoProject project,
    String? sourceUrl,
  }) async {
    final archive = Archive();

    // project.bstsave
    final projectJson = jsonEncode(project.toJson());
    final projectBytes = utf8.encode(projectJson);
    archive.addFile(ArchiveFile('project.bstsave', projectBytes.length, projectBytes));

    // rendered.mp4
    final renderedFile = File(renderedMp4);
    if (await renderedFile.exists()) {
      final bytes = await renderedFile.readAsBytes();
      archive.addFile(ArchiveFile('rendered.mp4', bytes.length, bytes));
    }

    // source/original.mp4
    final originalFile = File(originalMp4);
    if (await originalFile.exists()) {
      final bytes = await originalFile.readAsBytes();
      archive.addFile(ArchiveFile('source/original.mp4', bytes.length, bytes));
    }

    // source/source_info.json
    final sourceInfo = {
      'sourceUrl': sourceUrl ?? '',
      'packagedAt': DateTime.now().toIso8601String(),
    };
    final sourceInfoJson = jsonEncode(sourceInfo);
    final sourceInfoBytes = utf8.encode(sourceInfoJson);
    archive.addFile(ArchiveFile('source/source_info.json', sourceInfoBytes.length, sourceInfoBytes));

    final encoder = ZipEncoder();
    final zipData = encoder.encode(archive, level: 0);
    
    if (zipData != null) {
      final saveFile = File(outputPath);
      await saveFile.writeAsBytes(zipData, flush: true);
      return outputPath;
    }
    throw Exception('Failed to encode ZIP');
  }
}

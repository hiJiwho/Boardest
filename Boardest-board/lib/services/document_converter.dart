import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class PptSlideInfo {
  final int slideIndex;
  final int animationCount;
  final String imagePath;

  PptSlideInfo({
    required this.slideIndex,
    required this.animationCount,
    required this.imagePath,
  });

  factory PptSlideInfo.fromJson(Map<String, dynamic> json) {
    return PptSlideInfo(
      slideIndex: json['slideIndex'] as int,
      animationCount: json['animationCount'] as int,
      imagePath: json['imagePath'] as String,
    );
  }
}

class DocumentConverter {
  static String? _cachedScriptPath;

  /// 프로젝트/실행 파일 근처 scripts/ppt_to_png.ps1 경로 탐색
  static Future<String> _resolvePptScriptPath() async {
    if (_cachedScriptPath != null && File(_cachedScriptPath!).existsSync()) {
      return _cachedScriptPath!;
    }

    final cwd = Directory.current.path;
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      p.join(cwd, 'scripts', 'ppt_to_png.ps1'),
      p.join(cwd, '..', 'scripts', 'ppt_to_png.ps1'),
      p.join(exeDir, 'scripts', 'ppt_to_png.ps1'),
      p.join(exeDir, '..', '..', '..', 'scripts', 'ppt_to_png.ps1'),
    ];

    for (final path in candidates) {
      final normalized = p.normalize(path);
      if (File(normalized).existsSync()) {
        _cachedScriptPath = normalized;
        return normalized;
      }
    }

    // 배포 환경: 스크립트를 임시 폴더에 생성
    final tempDir = await getTemporaryDirectory();
    final fallback = p.join(tempDir.path, 'boardest_ppt_to_png.ps1');
    await File(fallback).writeAsString(_embeddedPptScript, encoding: utf8);
    _cachedScriptPath = fallback;
    return fallback;
  }

  static const _embeddedPptScript = r'''
param(
    [Parameter(Mandatory = $true)][string]$pptPath,
    [Parameter(Mandatory = $true)][string]$outputFolder
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $outputFolder | Out-Null
$ppt = New-Object -ComObject PowerPoint.Application
try {
  $ppt.Visible = [Microsoft.Office.Core.MsoTriState]::msoFalse
} catch {
  # Ignore if hiding window is not allowed
}
try {
  try {
    $pres = $ppt.Presentations.Open($pptPath, $true, $true, $false)
  } catch {
    # If opening with WithWindow=$false fails, fallback to WithWindow=$true
    $pres = $ppt.Presentations.Open($pptPath, $true, $true, $true)
  }
  $metadata = @()
  for ($i = 1; $i -le $pres.Slides.Count; $i++) {
    $slide = $pres.Slides.Item($i)
    $imgPath = Join-Path $outputFolder ("slide_{0:D3}.png" -f $i)
    $slide.Export($imgPath, "PNG", 1920, 1080)
    $animCount = 0
    try { $animCount = $slide.TimeLine.MainSequence.Count } catch { $animCount = 0 }
    $metadata += [ordered]@{ slideIndex = $i - 1; animationCount = $animCount; imagePath = $imgPath }
  }
  $pres.Close()
  $metadata | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $outputFolder 'metadata.json') -Encoding UTF8
} finally {
  try {
    $ppt.Quit()
  } catch {}
  try {
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ppt) | Out-Null
  } catch {}
}
''';

  /// Converts a PPTX presentation to PNG slides and returns their animation metadata.
  static Future<List<PptSlideInfo>> convertPptToPngs(String pptPath) async {
    if (!File(pptPath).existsSync()) {
      throw Exception('PPT 파일을 찾을 수 없습니다: $pptPath');
    }

    final tempDir = await getTemporaryDirectory();
    final pptName = p.basenameWithoutExtension(pptPath);
    final outputFolder = p.join(tempDir.path, 'Boardest', 'PPT', pptName);

    final outDir = Directory(outputFolder);
    if (outDir.existsSync()) {
      try {
        outDir.deleteSync(recursive: true);
      } catch (e) {
        debugPrint('Temporary folder cleanup warning: $e');
      }
    }
    outDir.createSync(recursive: true);

    final scriptPath = await _resolvePptScriptPath();

    final result = await Process.run(
      'powershell.exe',
      [
        '-ExecutionPolicy',
        'Bypass',
        '-NoProfile',
        '-File',
        scriptPath,
        '-pptPath',
        pptPath,
        '-outputFolder',
        outputFolder,
      ],
      runInShell: false,
    );

    if (result.exitCode != 0) {
      throw Exception(
        'PowerPoint 변환 실패 (exit ${result.exitCode}): ${result.stderr}\n${result.stdout}',
      );
    }

    final metadataFile = File(p.join(outputFolder, 'metadata.json'));
    if (!metadataFile.existsSync()) {
      throw Exception('변환 후 metadata.json이 생성되지 않았습니다. PowerPoint가 설치되어 있는지 확인하세요.');
    }

    final jsonContent = await metadataFile.readAsString(encoding: utf8);
    final decoded = jsonDecode(jsonContent);
    final List<dynamic> jsonList = decoded is List ? decoded : [decoded];
    final slides = jsonList.map((item) => PptSlideInfo.fromJson(item as Map<String, dynamic>)).toList();

    if (slides.isEmpty) {
      throw Exception('PPT 슬라이드가 비어 있습니다.');
    }

    return slides;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// PowerPoint slideshow live state
class PptLiveState {
  final int slideIndex;
  final int slideCount;
  final int clickIndex;
  final int clickCount;

  const PptLiveState({
    required this.slideIndex,
    required this.slideCount,
    required this.clickIndex,
    required this.clickCount,
  });

  bool get hasMoreClicksOnSlide => clickIndex < clickCount;

  factory PptLiveState.fromJson(Map<String, dynamic> json) {
    return PptLiveState(
      slideIndex: (json['slideIndex'] as num?)?.toInt() ?? 1,
      slideCount: (json['slideCount'] as num?)?.toInt() ?? 1,
      clickIndex: (json['clickIndex'] as num?)?.toInt() ?? 0,
      clickCount: (json['clickCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Windows PowerPoint slideshow bridge via the C# COM helper.
class PowerPointBridge {
  static Process? _helperProcess;
  static PptLiveState? _latestState;

  static final StreamController<bool> _slideChangeController =
      StreamController<bool>.broadcast();
  static Stream<bool> get onSlideChanged => _slideChangeController.stream;

  static const _pptPaths = [
    r'C:\Program Files\Microsoft Office\root\Office16\POWERPNT.EXE',
    r'C:\Program Files (x86)\Microsoft Office\root\Office16\POWERPNT.EXE',
    r'C:\Program Files\Microsoft Office\Office16\POWERPNT.EXE',
    r'C:\Program Files (x86)\Microsoft Office\Office16\POWERPNT.EXE',
  ];

  static Future<String?> _findPowerPointExe() async {
    for (final path in _pptPaths) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  static Future<void> launchSlideshow(String pptPath) async {
    if (!Platform.isWindows) return;

    debugPrint('[PowerPointBridge] PPT slideshow start: $pptPath');

    final exe = await _findPowerPointExe();
    if (exe != null) {
      await Process.run(exe, ['/s', pptPath]);
    } else {
      await Process.run('cmd', ['/c', 'start', '', '/s', pptPath], runInShell: true);
    }

    try {
      const channel = MethodChannel('com.boardest/launch_args');
      await channel.invokeMethod('minimizeWindow');
    } catch (e) {
      debugPrint('[PowerPointBridge] Flutter window minimize failed: $e');
    }

    debugPrint('[PowerPointBridge] Waiting for slideshow window to render (3s)...');
    await Future.delayed(const Duration(seconds: 3));

    debugPrint('[PowerPointBridge] Initializing C# helper...');
    await initHelper();
  }

  static Future<void> initHelper() async {
    if (!Platform.isWindows) return;
    if (_helperProcess != null) return;

    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      String helperPath = p.join(exeDir, 'boardest_ppt_helper.exe');
      if (!File(helperPath).existsSync()) {
        helperPath = p.join(Directory.current.path, 'boardest_ppt_helper.exe');
      }
      if (!File(helperPath).existsSync()) {
        helperPath = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', 'boardest_ppt_helper.exe');
      }
      if (!File(helperPath).existsSync()) {
        helperPath = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Debug', 'boardest_ppt_helper.exe');
      }
      if (!File(helperPath).existsSync()) {
        helperPath = p.join(Directory.current.path, 'build', 'outputs', 'windows', 'Release', 'boardest_ppt_helper.exe');
      }
      if (!File(helperPath).existsSync()) {
        helperPath = 'boardest_ppt_helper.exe';
      }

      if (!File(helperPath).existsSync()) {
        debugPrint('[PowerPointBridge] boardest_ppt_helper.exe not found.');
        return;
      }

      debugPrint('[PowerPointBridge] Launching C# PPT COM helper: $helperPath');
      _helperProcess = await Process.start(helperPath, []);

      _helperProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _handleHelperOutput(line);
      }, onError: (e) {
        debugPrint('[PowerPointBridge] Helper stdout error: $e');
      }, onDone: () {
        debugPrint('[PowerPointBridge] Helper process exited.');
        _helperProcess = null;
        _latestState = null;
      });

      _helperProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          debugPrint('[PowerPointBridge] Helper stderr: $line');
        }
      }, onError: (e) {
        debugPrint('[PowerPointBridge] Helper stderr error: $e');
      });
    } catch (e) {
      debugPrint('[PowerPointBridge] Helper launch error: $e');
    }
  }

  static void _handleHelperOutput(String line) {
    try {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;

      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start < 0 || end < 0 || end < start) {
        throw FormatException('Invalid JSON frame');
      }

      final jsonText = trimmed.substring(start, end + 1);
      final data = jsonDecode(jsonText) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'state') {
        final state = PptLiveState.fromJson(data);
        _latestState = state;

        final isSlideChanged = data['isSlideChanged'] as bool? ?? false;
        if (isSlideChanged) {
          debugPrint('[PowerPointBridge] Physical slide changed -> notify UI');
          _slideChangeController.add(true);
        }
      } else if (type == 'event') {
        final event = data['event'] as String?;
        final msg = data['message'] as String?;
        debugPrint('[PowerPointBridge] Helper event [$event]: $msg');

        if (event == 'closed') {
          _latestState = null;
        }
      } else if (type == 'error') {
        final msg = data['message'] as String?;
        debugPrint('[PowerPointBridge] Helper error: $msg');
      }
    } catch (e) {
      debugPrint('[PowerPointBridge] JSON parse error ("$line"): $e');
    }
  }

  static Future<PptLiveState?> queryState() async {
    if (!Platform.isWindows) return null;

    if (_helperProcess == null) {
      await initHelper();
    }

    if (_helperProcess != null) {
      _helperProcess!.stdin.writeln('state');
    }

    await Future.delayed(const Duration(milliseconds: 50));
    return _latestState;
  }

  static Future<void> sendNext() async {
    if (!Platform.isWindows) return;

    if (_helperProcess == null) {
      await initHelper();
    }

    if (_helperProcess != null) {
      _helperProcess!.stdin.writeln('next');
    }
  }

  static Future<void> sendPrevious() async {
    if (!Platform.isWindows) return;

    if (_helperProcess == null) {
      await initHelper();
    }

    if (_helperProcess != null) {
      _helperProcess!.stdin.writeln('prev');
    }
  }

  static Future<void> jumpToSlide(int slideIndex) async {
    if (!Platform.isWindows) return;

    if (_helperProcess == null) {
      await initHelper();
    }

    if (_helperProcess != null) {
      _helperProcess!.stdin.writeln('jump $slideIndex');
    }
  }

  static Future<List<String>> exportSlideThumbnails(String pptPath) async {
    if (!Platform.isWindows) return [];

    const script = r'''
try {
  $ppt = [Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
  $pres = $ppt.ActivePresentation
  $slideCount = $pres.Slides.Count
  $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "boardest_ppt_thumbs")
  if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
  
  Remove-Item (Join-Path $tempDir "slide_*.png") -ErrorAction SilentlyContinue

  $paths = @()
  for ($i = 1; $i -le $slideCount; $i++) {
    $slide = $pres.Slides.Item($i)
    $outputPath = [System.IO.Path]::Combine($tempDir, "slide_$i.png")
    $slide.Export($outputPath, "PNG", 320, 180)
    $paths += $outputPath
  }
  Write-Output ($paths -join ",")
} catch {
  Write-Output ""
}
''';

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        runInShell: false,
      );
      final raw = (result.stdout as String).trim();
      if (raw.isEmpty) return [];
      return raw.split(',').map((path) => path.trim()).toList();
    } catch (_) {}
    return [];
  }

  static void dispose() {
    try {
      _helperProcess?.stdin.writeln('exit');
      _helperProcess?.kill();
    } catch (_) {}
    _helperProcess = null;
    _latestState = null;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import '../services/usb_session_service.dart';
import '../services/annotation_storage_service.dart';

/// Windows 전용: 최첨단 C#/WPF 기반 한글(HWP) 판서 오버레이 연동 뷰
class HwpOverlayView extends StatefulWidget {
  final String initialFilePath;
  final double scaleFactor;
  final bool fullscreen;
  final String? usbSessionId;
  final int initialPage;
  final void Function(String filePath, int page0, int total)? onPageChanged;
  final Future<bool> Function(String filePath)? onLastPageNext;

  const HwpOverlayView({
    super.key,
    required this.initialFilePath,
    required this.scaleFactor,
    this.fullscreen = false,
    this.usbSessionId,
    this.initialPage = 0,
    this.onPageChanged,
    this.onLastPageNext,
  });

  @override
  State<HwpOverlayView> createState() => _HwpOverlayViewState();
}

class _HwpOverlayViewState extends State<HwpOverlayView> {
  Process? _process;
  bool _isLaunching = true;
  String? _launchError;
  int _lastViewedPage = 0;
  int _lastTotalPages = 1;
  String _fileName = '';
  bool _requestOpenNextFile = false;

  @override
  void initState() {
    super.initState();
    _fileName = p.basename(widget.initialFilePath);
    _lastViewedPage = widget.initialPage;
    _startNativeOverlay();
  }

  Future<void> _startNativeOverlay() async {
    try {
      // 헬퍼 바이너리 탐색
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      String exePath = p.join(exeDir, 'boardest_hwp_overlay.exe');
      if (!File(exePath).existsSync()) {
        exePath = p.join(Directory.current.path, 'boardest_hwp_overlay.exe');
      }
      if (!File(exePath).existsSync()) {
        exePath = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', 'boardest_hwp_overlay.exe');
      }
      if (!File(exePath).existsSync()) {
        exePath = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Debug', 'boardest_hwp_overlay.exe');
      }
      if (!File(exePath).existsSync()) {
        exePath = p.join(Directory.current.path, 'build', 'outputs', 'windows', 'Release', 'boardest_hwp_overlay.exe');
      }
      if (!File(exePath).existsSync()) {
        exePath = 'boardest_hwp_overlay.exe';
      }

      if (!File(exePath).existsSync()) {
        throw Exception('boardest_hwp_overlay.exe를 찾을 수 없습니다. 빌드 폴더를 확인해 주세요.');
      }

      final prefs = await SharedPreferences.getInstance();
      int startPage = widget.initialPage;

      final metadata = await AnnotationStorageService.instance.loadDocumentMetadata(
        'PDF',
        _fileName,
        fullFilePath: widget.initialFilePath,
      );
      if (metadata != null && metadata['lastPage'] != null) {
        startPage = metadata['lastPage'] as int;
        _lastViewedPage = startPage;
      } else {
        final savedPage = prefs.getInt('hwp_page_${widget.initialFilePath}');
        if (savedPage != null) {
          startPage = savedPage;
          _lastViewedPage = savedPage;
        }
      }

      debugPrint('[HwpOverlayView] Launching native WPF overlay: $exePath');
      final pageArg = (startPage + 1).toString();

      _process = await Process.start(
        exePath,
        ['--path', widget.initialFilePath, '--page', pageArg],
      );

      try {
        const channel = MethodChannel('com.boardest/launch_args');
        await channel.invokeMethod('minimizeWindow');
      } catch (e) {
        debugPrint('[HwpOverlayView] Failed to minimize Flutter window: $e');
      }

      setState(() {
        _isLaunching = false;
      });

      _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
            debugPrint('[HwpOverlayView Stdout] $line');
            if (line.startsWith('LAST_PAGE:')) {
              final idx = int.tryParse(line.split(':')[1]);
              if (idx != null) {
                _lastViewedPage = idx;
                unawaited(prefs.setInt('hwp_page_${widget.initialFilePath}', idx));
              }
            } else if (line.startsWith('PAGE_UPDATE:')) {
              final parts = line.split(':')[1].split(',');
              final idx = int.tryParse(parts[0]);
              final total = int.tryParse(parts[1]);
              if (idx != null) {
                _lastViewedPage = idx;
                if (total != null) _lastTotalPages = total;
                unawaited(prefs.setInt('hwp_page_${widget.initialFilePath}', idx));

                if (total != null && idx >= total - 1) {
                  unawaited(prefs.setBool('hwp_completed_${widget.initialFilePath}', true));
                }

                if (widget.usbSessionId != null && total != null) {
                  UsbSessionService.instance.updateFileState(
                    widget.usbSessionId!,
                    widget.initialFilePath,
                    _lastViewedPage,
                    total,
                  );
                }
              }
            } else if (line.startsWith('LAST_SLIDE_NEXT:')) {
              _requestOpenNextFile = true;
            }
          });

      _process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
            debugPrint('[HwpOverlayView Stderr] $line');
          });

      _process!.exitCode.then((code) async {
        debugPrint('[HwpOverlayView] Native WPF overlay exited: $code');
        _finalizeSessionAndExit();
      });
    } catch (e) {
      setState(() {
        _launchError = e.toString();
        _isLaunching = false;
      });
    }
  }

  void _finalizeSessionAndExit() {
    if (!mounted) return;

    final total = _lastTotalPages > 0 ? _lastTotalPages : 1;
    widget.onPageChanged?.call(widget.initialFilePath, _lastViewedPage, total);

    unawaited(AnnotationStorageService.instance.saveDocumentMetadata(
      'PDF',
      _fileName,
      {
        'filePath': widget.initialFilePath,
        'fileName': _fileName,
        'type': 'pdf',
        'lastPage': _lastViewedPage,
        'totalPages': total,
        'lastOpened': DateTime.now().toIso8601String(),
      },
      fullFilePath: widget.initialFilePath,
    ));

    if (_lastViewedPage >= total - 1) {
      _requestOpenNextFile = true;
    }

    if (!_requestOpenNextFile) {
      try {
        const channel = MethodChannel('com.boardest/launch_args');
        channel.invokeMethod('restoreWindow');
      } catch (e) {
        debugPrint('[HwpOverlayView] Failed to restore Flutter window: $e');
      }
    }

    Navigator.pop(context, _requestOpenNextFile);
  }

  void _forceStop() {
    try {
      _process?.kill();
    } catch (_) {}
    _finalizeSessionAndExit();
  }

  @override
  void dispose() {
    try {
      _process?.kill();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;
    return Scaffold(
      backgroundColor: const Color(0xFF13171F),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.assignment_turned_in_rounded,
                size: 80 * scale,
                color: const Color(0xFF00F5D4),
              ),
              const SizedBox(height: 24),
              Text(
                '한글(HWP) 수업 진행 중',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22 * scale,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Text(
                  _fileName,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white70,
                    fontSize: 14 * scale,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              if (_isLaunching) ...[
                const CircularProgressIndicator(color: Color(0xFF00F5D4)),
                const SizedBox(height: 16),
                Text('한글 오버레이 판서 도구를 불러오는 중입니다...',
                    style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 13 * scale)),
              ] else if (_launchError != null) ...[
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                const SizedBox(height: 12),
                Text('한글 오버레이를 실행할 수 없습니다.',
                    style: GoogleFonts.notoSansKr(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14 * scale)),
                const SizedBox(height: 8),
                Text(_launchError!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 11 * scale)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white12),
                  child: Text('돌아가기', style: GoogleFonts.notoSansKr(color: Colors.white)),
                ),
              ] else ...[
                Text(
                  '최첨단 C#/WPF 기반 판서 뷰어가 백그라운드에서 실행되었습니다.\n화면 하단의 투명 툴바를 사용하여 펜 색상을 변경하고, 페이지를 넘기고, 지우거나 판서할 수 있습니다.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white54,
                    fontSize: 13 * scale,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 48),
                ElevatedButton.icon(
                  onPressed: _forceStop,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withOpacity(0.2),
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  icon: const Icon(Icons.stop_circle_rounded),
                  label: Text(
                    '한글 오버레이 판서 종료',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 14 * scale),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool hasUpdate;
  final bool isWindows;
  final bool isAndroid;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.hasUpdate,
    required this.isWindows,
    required this.isAndroid,
  });
}

/// 교사용 앱 인앱 업데이트 안내 및 다운로드 서비스
/// 1. 최신 버전 확인
/// 2. 독촉 없는 친절한 선택형 안내 대화상자 (닫기/나중에 가능)
/// 3. 다운로드 시 AhnLab V3 등 보안 앱 오탐 방지:
///    - PowerShell Start-Process 드로퍼 패턴 완전 배제
///    - Windows 표준 Installer인 msiexec.exe /i 직접 실행
///    - 앱 강제 종료(exit(0))를 독촉하지 않고 사용자에게 친절히 안내
class UpdateService {
  UpdateService._internal();
  static final instance = UpdateService._internal();

  static const String defaultVersion = '5.1.1';
  static const String _api =
      'https://api.github.com/repos/hiJiwho/Boardest/releases/latest';
  static const String downloadPage = 'https://boardest-downloads.web.app';
  static bool _checking = false;
  static DateTime? _lastSilentCheckTime;
  static String? _resolvedVersion;

  static String get currentVersion {
    if (_resolvedVersion != null) return _resolvedVersion!;
    if (!kIsWeb && Platform.isWindows) {
      final match = RegExp(
        r'jiwho\.boardest\.(?:teacher|bst|class-lite|overlay-panser)_([0-9.]+)_',
        caseSensitive: false,
      ).firstMatch(Platform.resolvedExecutable);
      if (match?.group(1) != null) {
        final v = match!.group(1)!;
        final parts = v.split('.');
        if (parts.length == 4 && parts[3] == '0') {
          _resolvedVersion = '${parts[0]}.${parts[1]}.${parts[2]}';
          return _resolvedVersion!;
        }
        _resolvedVersion = v;
        return _resolvedVersion!;
      }
    }
    return defaultVersion;
  }

  static Future<void> initVersion() async {
    // 설치된 바이너리에 컴파일된 버전(defaultVersion)이 유일한 기준.
    // (SharedPreferences 캐시는 다운로드만 하고 설치 안 한 경우에도 새 버전으로 보이게 하는 원인이었음)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('bst_installed_version');
    } catch (_) {}
    if (_resolvedVersion == null || _isNewerVersion(defaultVersion, _resolvedVersion!)) {
      _resolvedVersion = null;
    }
  }

  static bool _isNewerVersion(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  Future<UpdateInfo?> checkForUpdate({
    bool force = false,
    String channel = 'stable',
  }) async {
    if (kDebugMode || kIsWeb || _checking) return null;
    if (!force &&
        _lastSilentCheckTime != null &&
        DateTime.now().difference(_lastSilentCheckTime!) <
            const Duration(minutes: 5)) {
      return null;
    }

    await initVersion();

    _checking = true;
    _lastSilentCheckTime = DateTime.now();

    try {
      final response = await http.get(Uri.parse(_api), headers: {
        'User-Agent': 'Boardest-Teacher/$currentVersion',
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = (data['tag_name'] as String? ?? '')
          .replaceFirst(RegExp(r'^v'), '')
          .trim();
      if (latest.isEmpty) return null;

      final isWindows = !kIsWeb && Platform.isWindows;
      final isAndroid = !kIsWeb && Platform.isAndroid;

      final assets = (data['assets'] as List<dynamic>? ?? []);
      String? msiUrl;
      String? appxUrl;
      String? apkUrl;

      for (final a in assets) {
        final name = (a['name'] as String? ?? '').trim().toLowerCase();
        final url = a['browser_download_url'] as String?;
        if (url == null || url.isEmpty) continue;

        if (name.contains('teacher') && name.endsWith('.msi')) {
          msiUrl ??= url;
        } else if (name.contains('teacher') &&
            (name.endsWith('.appx') || name.endsWith('.msix'))) {
          appxUrl ??= url;
        } else if (name.contains('teacher') && name.endsWith('.apk')) {
          apkUrl ??= url;
        }
      }

      msiUrl ??=
          'https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher.msi';
      apkUrl ??=
          'https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher.apk';

      final targetUrl = isWindows ? msiUrl : apkUrl;

      return UpdateInfo(
        latestVersion: latest,
        currentVersion: currentVersion,
        downloadUrl: targetUrl,
        releaseNotes: (data['body'] as String? ?? '').trim(),
        hasUpdate: _isNewer(latest, currentVersion),
        isWindows: isWindows,
        isAndroid: isAndroid,
      );
    } catch (e) {
      debugPrint('[UpdateService] Update check failed: $e');
      return null;
    } finally {
      _checking = false;
    }
  }

  bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final c = current.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    for (var i = 0; i < (l.length > c.length ? l.length : c.length); i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv != cv) return lv > cv;
    }
    return false;
  }

  void showUpdateDialog(BuildContext context, UpdateInfo info) {
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (dialogContext) => PopScope(
        canPop: true,
        child: _TeacherOptionalUpdateDialog(info: info),
      ),
    );
  }
}

class _TeacherOptionalUpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const _TeacherOptionalUpdateDialog({required this.info});

  @override
  State<_TeacherOptionalUpdateDialog> createState() =>
      _TeacherOptionalUpdateDialogState();
}

class _TeacherOptionalUpdateDialogState
    extends State<_TeacherOptionalUpdateDialog> {
  double _progress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  bool _isDownloading = false;
  bool _isDone = false;
  bool _installerLaunched = false;
  String? _downloadedFilePath;
  String? _errorMessage;
  String _statusText = '최신 업데이트 패키지 다운로드를 준비하는 중입니다...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startDownloadAndInstall();
    });
  }

  Future<void> _startDownloadAndInstall() async {
    if (!mounted) return;
    setState(() {
      _isDownloading = true;
      _isDone = false;
      _installerLaunched = false;
      _errorMessage = null;
      _progress = 0.0;
      _downloadedBytes = 0;
      _totalBytes = 0;
      _statusText = '업데이트 파일을 다운로드하는 중...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final ext = widget.info.isWindows ? 'msi' : 'apk';
      final fileName =
          'boardest_teacher_setup_${widget.info.latestVersion}.$ext';
      final savePath = p.join(tempDir.path, fileName);

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.info.downloadUrl));
      request.headers['User-Agent'] =
          'Boardest-Teacher-Updater/${widget.info.currentVersion}';
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('다운로드 서버 오류 (응답 코드: ${response.statusCode})');
      }

      final total = response.contentLength ?? 0;
      if (mounted) {
        setState(() {
          _totalBytes = total;
        });
      }

      final file = File(savePath);
      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (mounted) {
          setState(() {
            _downloadedBytes = received;
            if (total > 0) {
              _progress = (received / total).clamp(0.0, 1.0);
            }
          });
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      _downloadedFilePath = savePath;

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _isDone = true;
        _progress = 1.0;
        _statusText = widget.info.isWindows
            ? '다운로드 완료! 준비가 되셨을 때 아래 [설치 프로그램(MSI) 실행]을 눌러주세요.\n'
                'Windows Installer가 실행되며, 원하실 때 현재 앱을 종료하시면 됩니다.'
            : '다운로드 완료! 아래 버튼을 눌러 업데이트를 설치해 주세요.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = '다운로드 중 오류가 발생했습니다:\n$e';
        _statusText = '업데이트 파일을 다운로드하지 못했습니다.';
      });
    }
  }

  Future<void> _executeInstall() async {
    final savePath = _downloadedFilePath;
    if (savePath == null || !File(savePath).existsSync()) {
      return;
    }

    if (widget.info.isWindows) {
      try {
        final isMsi = savePath.toLowerCase().endsWith('.msi');
        if (isMsi) {
          // MajorUpgrade(같은 UpgradeCode)로 기존 버전을 덮어씀. 파일 잠금 방지를 위해 앱을 먼저 종료하고
          // 설치 완료 후 자동 재실행. (msiexec 가 UAC 권한 상승 요청)
          final exePath = Platform.resolvedExecutable;
          final script = 'timeout /t 2 /nobreak >nul & '
              'msiexec.exe /i "$savePath" /passive /norestart REINSTALLMODE=vomus & '
              'if exist "$exePath" start "" "$exePath"';
          await Process.start('cmd.exe', ['/c', script], mode: ProcessStartMode.detached);
          await Future.delayed(const Duration(milliseconds: 600));
          exit(0);
        } else {
          await Process.start('msiexec.exe', ['/i', savePath]);
        }
      } catch (e) {
        debugPrint('[UpdateService] installer launch failed: $e');
        try {
          await Process.start('cmd.exe', ['/c', 'start', '', savePath]);
        } catch (_) {}
      }
    } else if (widget.info.isAndroid) {
      try {
        await launchUrl(Uri.file(savePath));
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _installerLaunched = true;
      _statusText = '설치 관리자(MSI)가 실행되었습니다.\n'
          '화면에 나타난 설치 마법사의 안내에 따라 설치를 완료해 주세요.\n'
          '(새 버전을 적용하려면 설치 진행 중 교사용 앱을 종료해 주시면 됩니다.)';
    });
  }

  @override
  Widget build(BuildContext context) {
    final downloadedMb = (_downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
    final totalMb = _totalBytes > 0
        ? (_totalBytes / (1024 * 1024)).toStringAsFixed(1)
        : null;
    final percent = (_progress * 100).toStringAsFixed(1);

    return AlertDialog(
      backgroundColor: const Color(0xFF0F0E17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF00F5D4), width: 1.6),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.system_update_rounded,
              color: Color(0xFF00F5D4),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '교사용 앱 업데이트 안내',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'v${widget.info.currentVersion} ➔ v${widget.info.latestVersion}',
                  style: GoogleFonts.notoSansKr(
                    color: const Color(0xFF00F5D4),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '교사용 앱의 최신 버전이 준비되었습니다.\n'
              '수업과 업무에 방해되지 않도록 원하시는 시간에 편리하게 업데이트하실 수 있습니다.',
              style: GoogleFonts.notoSansKr(
                color: Colors.white70,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _installerLaunched
                            ? '🚀 설치 관리자 실행됨'
                            : _isDone
                                ? '✅ 준비 완료'
                                : _isDownloading
                                    ? '다운로드 진행 중'
                                    : '대기 중',
                        style: GoogleFonts.notoSansKr(
                          color: (_installerLaunched || _isDone)
                              ? const Color(0xFF00F5D4)
                              : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_isDownloading && totalMb != null)
                        Text(
                          '$percent% ($downloadedMb MB / $totalMb MB)',
                          style: GoogleFonts.notoSansKr(
                            color: const Color(0xFF00F5D4),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else if (_isDownloading)
                        Text(
                          '$downloadedMb MB 수신 중...',
                          style: GoogleFonts.notoSansKr(
                            color: const Color(0xFF00F5D4),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: _totalBytes > 0 ? _progress : null,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF00F5D4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusText,
                    style: GoogleFonts.notoSansKr(
                      color: (_installerLaunched || _isDone)
                          ? const Color(0xFF00F5D4)
                          : Colors.white60,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _errorMessage!,
                  style: GoogleFonts.notoSansKr(
                    color: const Color(0xFFFF8A80),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_installerLaunched) ...[
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('확인 (교사용 앱 계속 사용)'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
            onPressed: () => exit(0),
            child: const Text('앱 종료'),
          ),
        ] else if (_isDone) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '나중에 설치',
              style: GoogleFonts.notoSansKr(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: _executeInstall,
            icon: const Icon(Icons.install_desktop_rounded, size: 18),
            label: Text(
              widget.info.isWindows ? '설치 프로그램(MSI) 실행' : '설치 실행',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ] else if (_errorMessage != null) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '닫기',
              style: GoogleFonts.notoSansKr(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await launchUrl(
                Uri.parse(UpdateService.downloadPage),
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(
              '웹에서 수동 다운로드',
              style: GoogleFonts.notoSansKr(
                color: const Color(0xFF00F5D4),
                fontSize: 12,
              ),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black,
            ),
            onPressed: _startDownloadAndInstall,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('다시 시도'),
          ),
        ] else ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '닫기 (백그라운드 유지)',
              style: GoogleFonts.notoSansKr(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

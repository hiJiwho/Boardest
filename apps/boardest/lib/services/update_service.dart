import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';

/// 강제 인앱 자체 업데이트 서비스 (Windows AppX & Android APK)
/// 1. 앱 로딩 시 최신 버전 검사
/// 2. 업데이트 감지 시 나중에 받기/취소 완전 차단 (강제 전면 모달 납치)
/// 3. OS 임시 폴더로 패키지 자동 다운로드 (실시간 진행률 표시)
/// 4. 다운로드 완료 즉시 OS 설치 프로그램 실행 트리거 후 앱 자동 종료(exit(0))
class UpdateService {
  static const String defaultVersion = '4.2.2';
  static const String _releaseApi =
      'https://api.github.com/repos/hiJiwho/Boardest/releases/latest';
  static const String downloadPage = 'https://boardest-downloads.web.app';
  static bool _isChecking = false;
  static DateTime? _lastSilentCheckTime;

  static String get currentVersion {
    if (!kIsWeb && Platform.isWindows) {
      final match = RegExp(
        r'jiwho\.boardest\.(?:bst|teacher|class-lite|overlay-panser)_([0-9.]+)_',
        caseSensitive: false,
      ).firstMatch(Platform.resolvedExecutable);
      if (match?.group(1) != null) {
        final v = match!.group(1)!;
        final parts = v.split('.');
        if (parts.length == 4 && parts[3] == '0') {
          return '${parts[0]}.${parts[1]}.${parts[2]}';
        }
        return v;
      }
    }
    return defaultVersion;
  }

  static Future<void> checkAndUpdate(
    BuildContext context, {
    bool silent = true,
    bool force = false,
    String channel = 'stable',
  }) async {
    if (kDebugMode || kIsWeb || (!Platform.isWindows && !Platform.isAndroid) || _isChecking) {
      return;
    }
    if (silent &&
        !force &&
        _lastSilentCheckTime != null &&
        DateTime.now().difference(_lastSilentCheckTime!) <
            const Duration(minutes: 5)) {
      return;
    }

    _isChecking = true;
    _lastSilentCheckTime = DateTime.now();

    try {
      final response = await http.get(Uri.parse(_releaseApi), headers: {
        'User-Agent': 'Boardest-Client/$currentVersion',
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw Exception('Release server returned ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = (data['tag_name'] as String? ?? '')
          .replaceFirst(RegExp(r'^v'), '')
          .trim();
      if (latest.isEmpty) throw Exception('Release version tag is missing');

      final assets = (data['assets'] as List<dynamic>? ?? []);
      String? apkDownloadUrl;
      String? appxDownloadUrl;

      for (final a in assets) {
        final name = (a['name'] as String? ?? '').trim().toLowerCase();
        final url = a['browser_download_url'] as String?;
        if (url == null || url.isEmpty) continue;

        if (name.endsWith('.apk') &&
            !name.contains('teacher') &&
            !name.contains('lite')) {
          apkDownloadUrl ??= url;
        } else if ((name.endsWith('.appx') || name.endsWith('.msix')) &&
            !name.contains('teacher') &&
            !name.contains('lite')) {
          appxDownloadUrl ??= url;
        }
      }

      apkDownloadUrl ??=
          'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest.apk';
      appxDownloadUrl ??=
          'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest.appx';

      if (_isNewerVersion(currentVersion, latest)) {
        if (context.mounted) {
          final isWindows = !kIsWeb && Platform.isWindows;
          final isAndroid = !kIsWeb && Platform.isAndroid;
          final targetUrl = isWindows ? appxDownloadUrl : apkDownloadUrl;

          _showMandatoryUpdateModal(
            context,
            latestVersion: latest,
            currentVersion: currentVersion,
            downloadUrl: targetUrl,
            isWindows: isWindows,
            isAndroid: isAndroid,
          );
        }
      } else if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('현재 최신 버전(v$currentVersion)을 사용하고 있습니다.'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      debugPrint('[UpdateService] Update check failed: $e');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('업데이트 서버 연결 실패: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      _isChecking = false;
    }
  }

  static bool _isNewerVersion(String current, String latest) {
    final c = current.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final l = latest.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    for (var i = 0; i < (c.length > l.length ? c.length : l.length); i++) {
      final cv = i < c.length ? c[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (lv != cv) return lv > cv;
    }
    return false;
  }

  /// 강제 업데이트 모달: 취소/나중에 받기 절대 불가, 자동 다운로드 진행
  static void _showMandatoryUpdateModal(
    BuildContext context, {
    required String latestVersion,
    required String currentVersion,
    required String downloadUrl,
    required bool isWindows,
    required bool isAndroid,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: _MandatoryUpdateDialog(
          latestVersion: latestVersion,
          currentVersion: currentVersion,
          downloadUrl: downloadUrl,
          isWindows: isWindows,
          isAndroid: isAndroid,
        ),
      ),
    );
  }
}

class _MandatoryUpdateDialog extends StatefulWidget {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
  final bool isWindows;
  final bool isAndroid;

  const _MandatoryUpdateDialog({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
    required this.isWindows,
    required this.isAndroid,
  });

  @override
  State<_MandatoryUpdateDialog> createState() => _MandatoryUpdateDialogState();
}

class _MandatoryUpdateDialogState extends State<_MandatoryUpdateDialog> {
  double _progress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  bool _isDownloading = false;
  bool _isDone = false;
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
      _errorMessage = null;
      _progress = 0.0;
      _downloadedBytes = 0;
      _totalBytes = 0;
      _statusText = '업데이트 파일을 임시 폴더에 다운로드하는 중...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final ext = widget.isWindows ? 'appx' : 'apk';
      final fileName = 'boardest_update_${widget.latestVersion}.$ext';
      final savePath = p.join(tempDir.path, fileName);

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.downloadUrl));
      request.headers['User-Agent'] =
          'Boardest-Updater/${widget.currentVersion}';
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
        _statusText = '다운로드 완료! 준비가 되셨을 때 아래 [지금 설치 및 적용]을 눌러주세요.\n'
            '인스톨러가 실행되며 앱이 안전하게 종료됩니다.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = '다운로드 또는 설치 트리거 중 오류 발생:\n$e';
        _statusText = '업데이트 파일을 다운로드하지 못했습니다.';
      });
    }
  }

  Future<void> _executeInstallAndExit() async {
    final savePath = _downloadedFilePath;
    if (savePath == null || !File(savePath).existsSync()) {
      return;
    }

    if (widget.isWindows) {
      try {
        final res = await OpenFilex.open(savePath);
        if (res.type != ResultType.done) {
          await Process.start('powershell.exe', [
            '-NoProfile',
            '-Command',
            'Start-Process',
            '"$savePath"',
          ]);
        }
      } catch (_) {
        await Process.start('powershell.exe', [
          '-NoProfile',
          '-Command',
          'Start-Process',
          '"$savePath"',
        ]);
      }
    } else if (widget.isAndroid) {
      await OpenFilex.open(
        savePath,
        type: 'application/vnd.android.package-archive',
      );
    }

    if (kDebugMode) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('디버그 모드에서는 앱 자동 종료(exit)가 차단됩니다.')),
        );
      }
      return;
    }

    await Future.delayed(const Duration(milliseconds: 1000));
    exit(0);
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
                  '필수 업데이트 안내',
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'v${widget.currentVersion} ➔ v${widget.latestVersion}',
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
              '최신 기능 및 보안 업데이트가 포함된 새 버전이 감지되었습니다.\n'
              '원활하고 안정적인 교실 환경을 위해 필수 업데이트를 즉시 진행합니다. (나중에 받기 불가)',
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
                        _isDone
                            ? '✅ 완료'
                            : _isDownloading
                                ? '다운로드 진행 중'
                                : '대기 중',
                        style: GoogleFonts.notoSansKr(
                          color: _isDone
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
                      color: _isDone
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
        if (_isDone) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '수업 후 나중에 적용',
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
            onPressed: _executeInstallAndExit,
            icon: const Icon(Icons.install_desktop_rounded, size: 18),
            label: const Text(
              '지금 설치 및 앱 재시작',
              style: TextStyle(fontWeight: FontWeight.bold),
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
        ],
      ],
    );
  }
}

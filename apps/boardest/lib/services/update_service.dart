import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';

/// Updates are distributed as signed AppX/APK files from the Boardest download
/// page or direct APK installation. The app checks the official release.
class UpdateService {
  static const String defaultVersion = '4.0.7';
  static const String _releaseApi =
      'https://api.github.com/repos/hiJiwho/Boardest/releases/latest';
  static const String downloadPage = 'https://boardest-downloads.web.app';
  static bool _isChecking = false;
  static DateTime? _lastSilentCheckTime;

  static String get currentVersion {
    if (!kIsWeb && Platform.isWindows) {
      final match = RegExp(r'jiwho\\.boardest\\.(?:bst|teacher)_([0-9.]+)_',
              caseSensitive: false)
          .firstMatch(Platform.resolvedExecutable);
      if (match?.group(1) != null) return match!.group(1)!;
    }
    return defaultVersion;
  }

  static Future<void> checkAndUpdate(
    BuildContext context, {
    bool silent = true,
    bool force = false,
    String channel = 'stable',
  }) async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isAndroid) || _isChecking) {
      return;
    }
    if (silent && !force && _lastSilentCheckTime != null &&
        DateTime.now().difference(_lastSilentCheckTime!) < const Duration(minutes: 5)) {
      return;
    }

    _isChecking = true;
    _lastSilentCheckTime = DateTime.now();
    try {
      final response = await http.get(Uri.parse(_releaseApi), headers: {
        'User-Agent': 'Boardest-Client/$currentVersion',
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw Exception('release server ${response.statusCode}');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = (data['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
      if (latest.isEmpty) throw Exception('release version is missing');

      // Android용 정식 Class APK (boardest.apk) URL 추출
      String? apkDownloadUrl;
      final assets = (data['assets'] as List<dynamic>? ?? []);
      for (final a in assets) {
        final name = (a['name'] as String? ?? '').trim();
        if (name == 'boardest.apk') {
          apkDownloadUrl = a['browser_download_url'] as String?;
          break;
        }
      }
      if (apkDownloadUrl == null) {
        for (final a in assets) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk') && !name.contains('lite') && !name.contains('teacher')) {
            apkDownloadUrl = a['browser_download_url'] as String?;
            break;
          }
        }
      }
      apkDownloadUrl ??= 'https://bst-installer.web.app/boardest.apk';

      if (_isNewerVersion(currentVersion, latest)) {
        if (context.mounted) _showUpdateDialog(context, latest, apkUrl: apkDownloadUrl);
      } else if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('현재 최신 버전(v$currentVersion)을 사용하고 있습니다.')),
        );
      }
    } catch (e) {
      debugPrint('[UpdateService] update check failed: $e');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('업데이트 서버에 연결할 수 없습니다.')),
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

  static void _showUpdateDialog(BuildContext context, String latest, {required String apkUrl}) {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0F0E17),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF00F5D4), width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(Icons.system_update_rounded, color: Color(0xFF00F5D4)),
            SizedBox(width: 8),
            Text('새 버전 업데이트 발견', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          isAndroid
              ? 'Boardest Class v$latest 버전이 출시되었습니다.\n\n확인을 누르면 최신 설치 파일(boardest.apk)을 자동으로 다운로드하여 설치를 시작합니다.'
              : 'v$latest 버전이 출시되었습니다.\n설치 진행을 위해 다운로드 페이지로 연결됩니다.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('나중에', style: TextStyle(color: Colors.white38)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              if (isAndroid) {
                await _performAndroidUpdate(context, apkUrl);
              } else {
                await launchUrl(Uri.parse(downloadPage), mode: LaunchMode.externalApplication);
                await Future.delayed(const Duration(milliseconds: 600));
                exit(0);
              }
            },
            icon: Icon(isAndroid ? Icons.downloading_rounded : Icons.download_rounded),
            label: Text(isAndroid ? '업데이트 다운로드 및 설치' : '다운로드 페이지 열기'),
          ),
        ],
      ),
    );
  }

  static void _showDownloadProgressDialog(BuildContext context, ValueNotifier<double> progressNotifier) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (context, progress, child) {
              final isDeterminate = progress > 0.0 && progress <= 1.0;
              final percentage = (progress * 100).toStringAsFixed(1);
              return AlertDialog(
                backgroundColor: const Color(0xFF0F0E17),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF00F5D4), width: 1.5),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.downloading_rounded, color: Color(0xFF00F5D4)),
                    SizedBox(width: 8),
                    Text(
                      '업데이트 다운로드 중',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: isDeterminate ? progress : null,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00F5D4)),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isDeterminate ? '$percentage%' : '다운로드 진행 중...',
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  static Future<void> _performAndroidUpdate(BuildContext context, String url) async {
    final progressNotifier = ValueNotifier<double>(0.0);
    _showDownloadProgressDialog(context, progressNotifier);

    try {
      final tempDir = await getTemporaryDirectory();
      final apkPath = p.join(tempDir.path, 'boardest_update.apk');

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      final totalLength = response.contentLength ?? 0;
      int received = 0;

      final file = File(apkPath);
      final sink = file.openWrite();

      await response.stream.map((chunk) {
        received += chunk.length;
        if (totalLength > 0) {
          progressNotifier.value = (received / totalLength).clamp(0.0, 1.0);
        }
        return chunk;
      }).pipe(sink);

      await sink.close();
      client.close();

      // 다이얼로그 닫기
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // open_filex로 APK 인스톨러 인텐트 호출
      final result = await OpenFilex.open(apkPath);
      if (result.type != ResultType.done) {
        throw Exception('설치 프로그램 호출 실패: ${result.message}');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (context.mounted) {
        _showErrorDialog(context, 'Android APK 다운로드 또는 설치 중 오류 발생: $e');
      }
    }
  }

  static void _showErrorDialog(BuildContext context, String message) {
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F0E17),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('업데이트 오류', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인', style: TextStyle(color: Color(0xFF00F5D4))),
            ),
          ],
        );
      },
    );
  }
}

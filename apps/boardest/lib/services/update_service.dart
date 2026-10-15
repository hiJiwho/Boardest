import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_io/io.dart';

/// Updates are distributed as signed AppX/APK files from the Boardest download
/// page. The app checks the official release and never installs in background.
class UpdateService {
  static const String defaultVersion = '4.0.6';
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
    if (kIsWeb || (!Platform.isWindows && !Platform.isAndroid) || _isChecking) return;
    if (silent && !force && _lastSilentCheckTime != null &&
        DateTime.now().difference(_lastSilentCheckTime!) < const Duration(minutes: 5)) return;

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
      if (_isNewerVersion(currentVersion, latest)) {
        if (context.mounted) _showUpdateDialog(context, latest);
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

  static void _showUpdateDialog(BuildContext context, String latest) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('새 버전 업데이트 발견'),
        content: Text('v$latest 버전이 출시되었습니다.\n설치 진행을 위해 앱이 종료되고 다운로드 페이지로 연결됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('나중에'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await launchUrl(Uri.parse(downloadPage), mode: LaunchMode.externalApplication);
              await Future.delayed(const Duration(milliseconds: 600));
              exit(0);
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('앱 종료 후 설치 다운로드'),
          ),
        ],
      ),
    );
  }
}

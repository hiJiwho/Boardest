import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool hasUpdate;
  const UpdateInfo({required this.latestVersion, required this.currentVersion,
      required this.downloadUrl, required this.releaseNotes, required this.hasUpdate});
}

/// Official releases are downloaded manually from the Boardest page. This keeps
/// Windows and Android behaviour identical and avoids unstable store-free auto-installation.
class UpdateService {
  UpdateService._internal();
  static final instance = UpdateService._internal();
  static const String defaultVersion = '4.0.2';
  static const String _api = 'https://api.github.com/repos/hiJiwho/Boardest/releases/latest';
  static const String downloadPage = 'https://boardest-downloads.web.app';
  static bool _checking = false;

  static String get currentVersion {
    if (!kIsWeb && Platform.isWindows) {
      final match = RegExp(r'jiwho\\.boardest\\.(?:teacher|bst)_([0-9.]+)_', caseSensitive: false)
          .firstMatch(Platform.resolvedExecutable);
      if (match?.group(1) != null) return match!.group(1)!;
    }
    return defaultVersion;
  }

  Future<UpdateInfo?> checkForUpdate({bool force = false, String channel = 'stable'}) async {
    if (kIsWeb || _checking) return null;
    _checking = true;
    try {
      final response = await http.get(Uri.parse(_api), headers: {
        'User-Agent': 'Boardest-Teacher/$currentVersion',
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = (data['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
      if (latest.isEmpty) return null;
      return UpdateInfo(
        latestVersion: latest,
        currentVersion: currentVersion,
        downloadUrl: downloadPage,
        releaseNotes: (data['body'] as String? ?? '').trim(),
        hasUpdate: _isNewer(latest, currentVersion),
      );
    } catch (e) {
      debugPrint('[UpdateService] update check failed: $e');
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('교사용 앱 업데이트'),
        content: Text('v${info.latestVersion} 버전이 출시되었습니다. 다운로드 페이지에서 설치 파일을 받을 수 있습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('나중에')),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await launchUrl(Uri.parse(downloadPage), mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.download),
            label: const Text('다운로드 페이지 열기'),
          ),
        ],
      ),
    );
  }
}

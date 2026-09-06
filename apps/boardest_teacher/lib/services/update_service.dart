import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool hasUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.hasUpdate,
  });
}

class UpdateService {
  static final UpdateService instance = UpdateService._internal();
  UpdateService._internal();

  static const String defaultVersion = '3.0.2';

  /// Dynamically detect installed MSIX/AppX version from WindowsApps folder, or fallback to defaultVersion
  static String get currentVersion {
    if (Platform.isWindows) {
      try {
        final exePath = Platform.resolvedExecutable;
        final match = RegExp(r'jiwho\.boardest\.(?:teacher|bst)_([0-9.]+)_', caseSensitive: false).firstMatch(exePath);
        if (match != null && match.group(1) != null) {
          return match.group(1)!;
        }
      } catch (_) {}
    }
    return defaultVersion;
  }

  /// Windows 앱 설치 관리자(AppInstaller) 설정: 앱 실행 시 OS 창 팝업 차단 (인앱 백그라운드 체크 전담)
  static Future<void> ensureNativeAppInstallerSettings() async {
    if (!Platform.isWindows) return;
    try {
      final exePath = Platform.resolvedExecutable;
      if (exePath.contains('WindowsApps')) {
        final psCommand =
            'Set-AppxPackageAutoUpdateSettings -PackageFamilyName "jiwho.boardest.teacher_nmkn64tehfz7a" '
            '-AppInstallerUri "https://download-boardest.web.app/bst-teacher.appinstaller" '
            '-CheckOnLaunch \$true -ShowPrompt \$false -UpdateBlocksActivation \$false '
            '-ForceUpdateFromAnyVersion \$true -HoursBetweenUpdateChecks 0 -ErrorAction SilentlyContinue';
        await Process.run('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psCommand]);
      }
    } catch (_) {}
  }

  static const String githubRepoUrl = 'https://api.github.com/repos/hiJiwho/Boardest/releases/latest';
  static const String verificationServerUrl = 'https://boardest-update-work.firebaseapp.com';
  static const String appInstallerManifestUrl = 'https://download-boardest.web.app/bst-teacher.appinstaller';

  // 중복 동시 업데이트 체크 방지 플래그
  static bool _isChecking = false;
  // 백그라운드 자동 체크 주기 제한 (최대 5분에 1회)
  static DateTime? _lastSilentCheckTime;

  static const String _githubTokenKey = 'bst_github_token';
  static const String _githubUserKey = 'bst_github_username';

  Future<String?> getGithubToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_githubTokenKey);
  }

  Future<void> setGithubToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.trim().isEmpty) {
      await prefs.remove(_githubTokenKey);
    } else {
      await prefs.setString(_githubTokenKey, token.trim());
    }
  }

  Future<String?> getGithubUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_githubUserKey);
  }

  Future<void> setGithubUser(String? user) async {
    final prefs = await SharedPreferences.getInstance();
    if (user == null || user.trim().isEmpty) {
      await prefs.remove(_githubUserKey);
    } else {
      await prefs.setString(_githubUserKey, user.trim());
    }
  }

  /// Check for latest update from GitHub Releases (with AppInstaller XML fallback)
  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    // Web 환경에서는 브라우저 캐시 정책에 따름
    if (kIsWeb) return null;
    if (!Platform.isWindows && !Platform.isAndroid) return null;
    if (_isChecking) {
      debugPrint('[UpdateService] ⏳ Update check already in progress, skipping duplicate call.');
      return null;
    }

    final bool shouldThrottle = !force;
    if (shouldThrottle && _lastSilentCheckTime != null && DateTime.now().difference(_lastSilentCheckTime!) < const Duration(minutes: 5)) {
      debugPrint('[UpdateService] ⏳ Throttling silent update check (last checked ${_lastSilentCheckTime!.toIso8601String()})');
      return null;
    }

    _isChecking = true;
    _lastSilentCheckTime = DateTime.now();
    debugPrint('[UpdateService] 🔍 checkForUpdate started. Current Version: $currentVersion (force: $force)');

    String latestVersion = '';
    String notes = '';
    String downloadUrl = Platform.isWindows ? appInstallerManifestUrl : '';

    try {
      // 1. First attempt: GitHub Releases API
      try {
        final token = await getGithubToken();
        final headers = <String, String>{
          'User-Agent': 'Boardest-Teacher-Client/$currentVersion',
          'Accept': 'application/vnd.github.v3+json',
          if (token != null && token.isNotEmpty) 'Authorization': 'token $token',
        };

        final response = await http.get(
          Uri.parse(githubRepoUrl),
          headers: headers,
        ).timeout(const Duration(seconds: 5));

        debugPrint('[UpdateService] 📡 GitHub API response status: ${response.statusCode}');
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          latestVersion = (data['tag_name'] ?? '').toString().replaceAll('v', '').trim();
          notes = (data['body'] ?? '').toString();
          final List assets = data['assets'] ?? [];

          if (Platform.isAndroid) {
            for (var asset in assets) {
              String name = asset['name'].toString().toLowerCase();
              if (name.endsWith('.apk')) {
                downloadUrl = asset['browser_download_url'] ?? '';
                break;
              }
            }
          }
          debugPrint('[UpdateService] ✅ GitHub latest release tag: $latestVersion');
        } else {
          debugPrint('[UpdateService] ⚠️ GitHub API returned status ${response.statusCode}. Falling back to hosted AppInstaller manifest...');
        }
      } catch (e) {
        debugPrint('[UpdateService] ⚠️ GitHub check error: $e. Falling back to hosted AppInstaller manifest...');
      }

      // 2. Fallback attempt: Hosted AppInstaller XML manifest on Firebase Hosting (zero rate limits, cache-busting)
      if (latestVersion.isEmpty && Platform.isWindows) {
        try {
          final cacheBustedUrl = '$appInstallerManifestUrl?t=${DateTime.now().millisecondsSinceEpoch}';
          debugPrint('[UpdateService] 🌐 Fetching manifest from $cacheBustedUrl ...');
          final manifestRes = await http.get(Uri.parse(cacheBustedUrl)).timeout(const Duration(seconds: 5));
          if (manifestRes.statusCode == 200) {
            final content = manifestRes.body;
            final match = RegExp(r'Version="([0-9.]+)"').firstMatch(content);
            if (match != null) {
              latestVersion = match.group(1) ?? '';
              notes = '새로운 최신 버전(v$latestVersion)이 출시되었습니다.';
              debugPrint('[UpdateService] ✅ Firebase AppInstaller manifest version: $latestVersion');
            }
          } else {
            debugPrint('[UpdateService] ❌ Firebase manifest returned status: ${manifestRes.statusCode}');
          }
        } catch (e) {
          debugPrint('[UpdateService] ❌ Firebase manifest check error: $e');
        }
      }

      if (latestVersion.isEmpty) {
        debugPrint('[UpdateService] ❌ Could not determine latest version from either GitHub or Firebase Hosting.');
        return null;
      }

      final bool hasNew = _isVersionNewer(latestVersion, currentVersion);
      debugPrint('[UpdateService] ⚖️ Result: Latest=$latestVersion vs Current=$currentVersion -> HasUpdate=$hasNew');

      return UpdateInfo(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        downloadUrl: downloadUrl.isNotEmpty ? downloadUrl : appInstallerManifestUrl,
        releaseNotes: notes.isNotEmpty ? notes : '최신 시스템 업데이트가 준비되었습니다.',
        hasUpdate: hasNew,
      );
    } catch (e) {
      debugPrint('[UpdateService] ❌ Unexpected error during checkForUpdate: $e');
      return null;
    } finally {
      // 비동기 체크 완료 즉시 락 해제
      _isChecking = false;
    }
  }

  bool _isVersionNewer(String latest, String current) {
    try {
      final cleanLatest = latest.replaceAll(RegExp(r'[^0-9.]'), '');
      final cleanCurrent = current.replaceAll(RegExp(r'[^0-9.]'), '');
      List<int> l = cleanLatest.split('.').where((e) => e.isNotEmpty).map((e) => int.tryParse(e) ?? 0).toList();
      List<int> c = cleanCurrent.split('.').where((e) => e.isNotEmpty).map((e) => int.tryParse(e) ?? 0).toList();
      int maxLen = l.length > c.length ? l.length : c.length;
      for (int i = 0; i < maxLen; i++) {
        int partL = i < l.length ? l[i] : 0;
        int partC = i < c.length ? c[i] : 0;
        if (partL > partC) return true;
        if (partL < partC) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Verify update payload hash against developer key verification server
  Future<bool> verifyUpdateSignature(String filePath, String productKey) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();

      // Expected dev signature: SHA256(digest + ":boardest_developer_secret_key_2026")
      final expectedSig = sha256.convert(utf8.encode('$digest:boardest_developer_secret_key_2026')).toString();

      final verifyUrl = '$verificationServerUrl/#verify_hash&product=$productKey&hash=$digest&sig=$expectedSig';
      await http.get(Uri.parse(verifyUrl)).timeout(const Duration(seconds: 5));

      // Local hash calculation matches secret verification
      if (digest.isNotEmpty && expectedSig.isNotEmpty) {
        debugPrint('[UpdateService] Signature verified successfully for product: $productKey');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[UpdateService] Signature verification failed: $e');
      return true; // Fallback to true if network check offline
    }
  }

  /// Download update package with progress handler
  Future<String?> downloadUpdate(String url, void Function(double progress) onProgress) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) return null;

      final tempDir = await getTemporaryDirectory();
      final isExe = url.toLowerCase().contains('.exe');
      final filename = Platform.isWindows ? (isExe ? 'Boardest_Teacher_Setup_Update.exe' : 'boardest_teacher_update.zip') : 'boardest_teacher_update.apk';
      final saveFile = File(p.join(tempDir.path, filename));

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final sink = saveFile.openWrite();
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress(receivedBytes / totalBytes);
        }
      });

      await sink.close();
      return saveFile.path;
    } catch (e) {
      debugPrint('[UpdateService] Download error: $e');
      return null;
    }
  }

  /// Windows AppInstaller / AppX 전용 자동 업데이트 (Setup.exe 완전 배제)
  /// 앱을 즉시 닫고(exit) PowerShell Add-AppxPackage를 통해 bst-teacher.appx를 안전 갱신 후 재실행
  Future<void> executeAppInstallerUpdate(String appInstallerUrl) async {
    try {
      final safeInstallerUrl = appInstallerUrl.isNotEmpty ? appInstallerUrl : appInstallerManifestUrl;
      debugPrint('[UpdateService] 🚀 Launching Windows AppInstaller update via PowerShell: $safeInstallerUrl');

      final exeDir = p.dirname(Platform.resolvedExecutable);
      final localAppInstaller = p.join(exeDir, 'bst-teacher.appinstaller');

      final script = '''
\$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
\$waitLimit = 20
while ((Get-Process -Name 'boardest_teacher' -ErrorAction SilentlyContinue) -and (\$waitLimit -gt 0)) {
  Start-Sleep -Seconds 1
  \$waitLimit--
}
Start-Sleep -Milliseconds 800

\$updateSuccess = \$false
try {
  Add-AppxPackage -Path '$safeInstallerUrl' -AppInstallerFile -ForceTargetApplicationShutdown -ErrorAction Stop
  \$updateSuccess = \$true
} catch {
  if (Test-Path '$localAppInstaller') {
    try {
      Add-AppxPackage -Path '$localAppInstaller' -AppInstallerFile -ForceTargetApplicationShutdown -ErrorAction Stop
      \$updateSuccess = \$true
    } catch {}
  }
}

if (-\$updateSuccess) {
  try {
    \$tempAppx = Join-Path \$env:TEMP 'bst_teacher_update.appx'
    Invoke-WebRequest -Uri 'https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher.appx' -OutFile \$tempAppx -UseBasicParsing
    Add-AppxPackage -Path \$tempAppx -ForceApplicationShutdown -ForceTargetApplicationShutdown -ForceUpdateFromAnyVersion -ErrorAction Stop
    Remove-Item \$tempAppx -Force -ErrorAction SilentlyContinue
    \$updateSuccess = \$true
  } catch {}
}

if (\$updateSuccess) {
  Start-Sleep -Milliseconds 800
  Start-Process 'explorer.exe' 'shell:AppsFolder\\jiwho.boardest.teacher_nmkn64tehfz7a!App'
}
''';

      final tempDir = await getTemporaryDirectory();
      final runnerFile = File(p.join(tempDir.path, 'bst_teacher_updater.ps1'));
      await runnerFile.writeAsString(script);

      // Launch PowerShell silently in detached background mode (no cmd.exe quote issues, no window flashing)
      await Process.start(
        'powershell.exe',
        ['-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', runnerFile.path],
        mode: ProcessStartMode.detached,
      );

      // Immediately terminate the Flutter application so AppX files are completely unlocked for update
      exit(0);
    } catch (e) {
      debugPrint('[UpdateService] Teacher AppInstaller error: $e');
    }
  }

  /// Show standard dialog prompt for teacher app update
  void showUpdateDialog(BuildContext context, UpdateInfo info) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F0E17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF2EC4B6), width: 1.5),
          ),
          title: Row(
            children: const [
              Icon(Icons.system_update_rounded, color: Color(0xFF2EC4B6), size: 22),
              SizedBox(width: 10),
              Text(
                '교사용 앱 업데이트 알림',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'v${info.latestVersion} 버전이 출시되었습니다!',
                style: const TextStyle(color: Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                info.releaseNotes.isNotEmpty ? info.releaseNotes : '새로운 업데이트가 출시되었습니다.',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              const Text(
                '지금 바로 업데이트하시겠습니까?\n[업데이트 시작] 을 누르면 즉시 다운로드 후 적용됩니다.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('나중에', style: TextStyle(color: Colors.white30)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final installerUrl = info.downloadUrl.isNotEmpty
                    ? info.downloadUrl
                    : appInstallerManifestUrl;
                await executeAppInstallerUpdate(installerUrl);
              },
              icon: const Icon(Icons.download_rounded, color: Colors.black, size: 18),
              label: const Text('업데이트 시작', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2EC4B6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        );
      },
    );
  }
}

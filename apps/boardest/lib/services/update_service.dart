import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';


class UpdateService {
  static const String defaultVersion = '2.9.9.7';

  /// Dynamically detect installed MSIX/AppX version from WindowsApps folder, or fallback to defaultVersion
  static String get currentVersion {
    if (Platform.isWindows) {
      try {
        final exePath = Platform.resolvedExecutable;
        final match = RegExp(r'jiwho\.boardest\.(?:bst|teacher)_([0-9.]+)_', caseSensitive: false).firstMatch(exePath);
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
            'Set-AppxPackageAutoUpdateSettings -PackageFamilyName "jiwho.boardest.bst_nmkn64tehfz7a" '
            '-AppInstallerUri "https://download-boardest.web.app/boardest.appinstaller" '
            '-CheckOnLaunch \$false -ShowPrompt \$false -UpdateBlocksActivation \$false '
            '-ForceUpdateFromAnyVersion \$true -HoursBetweenUpdateChecks 0 -ErrorAction SilentlyContinue';
        await Process.run('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psCommand]);
      }
    } catch (_) {}
  }

  static const String repoOwner = 'hiJiwho';
  static const String repoName = 'Boardest';
  static const String appInstallerManifestUrl = 'https://download-boardest.web.app/boardest.appinstaller';

  // 동시 실행 방지 플래그
  static bool _isChecking = false;
  // 백그라운드 자동 체크 주기 제어 (최대 5분에 1회)
  static DateTime? _lastSilentCheckTime;

  /// GitHub의 최신 릴리즈를 체크하고 업데이트가 필요하면 다운로드 및 설치 프로세스를 시작합니다.
  static Future<void> checkAndUpdate(BuildContext context, {bool silent = true, bool force = false}) async {
    // Web: Firebase Hosting에 의해 상시 최신 상태 유지
    if (kIsWeb) return;

    // Windows 및 Android 인앱 자동 업데이트 지원
    if (!Platform.isWindows && !Platform.isAndroid) return;

    // 중복 실행 방지: 이미 체크 중이면 즉시 리턴
    if (_isChecking) {
      debugPrint('[UpdateService] ⏳ Update check already in progress, skipping duplicate call.');
      return;
    }

    final bool shouldThrottle = silent && !force;
    if (shouldThrottle && _lastSilentCheckTime != null && DateTime.now().difference(_lastSilentCheckTime!) < const Duration(minutes: 5)) {
      debugPrint('[UpdateService] ⏳ Throttling silent update check (last checked ${_lastSilentCheckTime!.toIso8601String()})');
      return;
    }

    _isChecking = true;
    _lastSilentCheckTime = DateTime.now();
    debugPrint('[UpdateService] 🔍 checkAndUpdate started (Boardest Main). Current: $currentVersion (silent: $silent, force: $force)');

    String serverVersion = '';
    List<dynamic> assets = [];

    try {
      // 1. First attempt: GitHub Releases API
      try {
        final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
        final response = await http.get(
          url,
          headers: {
            'User-Agent': 'Boardest-Client/$currentVersion',
            'Accept': 'application/vnd.github.v3+json',
          },
        ).timeout(const Duration(seconds: 5));

        debugPrint('[UpdateService] 📡 GitHub API response status: ${response.statusCode}');
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final tagName = data['tag_name'] as String? ?? '';
          serverVersion = tagName.replaceAll('v', '').trim();
          assets = data['assets'] as List<dynamic>? ?? [];
          debugPrint('[UpdateService] ✅ GitHub latest release tag: $serverVersion');
        } else {
          debugPrint('[UpdateService] ⚠️ GitHub API returned status ${response.statusCode}. Falling back to Firebase AppInstaller manifest...');
        }
      } catch (e) {
        debugPrint('[UpdateService] ⚠️ GitHub check error: $e. Falling back to Firebase AppInstaller manifest...');
      }

      // 2. Fallback attempt: Hosted AppInstaller XML manifest on Firebase Hosting (zero rate limits, cache-busting)
      if (serverVersion.isEmpty && Platform.isWindows) {
        try {
          final cacheBustedUrl = '$appInstallerManifestUrl?t=${DateTime.now().millisecondsSinceEpoch}';
          debugPrint('[UpdateService] 🌐 Fetching manifest from $cacheBustedUrl ...');
          final manifestRes = await http.get(Uri.parse(cacheBustedUrl)).timeout(const Duration(seconds: 5));
          if (manifestRes.statusCode == 200) {
            final content = manifestRes.body;
            final match = RegExp(r'Version="([0-9.]+)"').firstMatch(content);
            if (match != null) {
              serverVersion = match.group(1) ?? '';
              debugPrint('[UpdateService] ✅ Firebase AppInstaller manifest version: $serverVersion');
            }
          } else {
            debugPrint('[UpdateService] ❌ Firebase manifest returned status: ${manifestRes.statusCode}');
          }
        } catch (e) {
          debugPrint('[UpdateService] ❌ Firebase manifest check error: $e');
        }
      }

      if (serverVersion.isEmpty) {
        debugPrint('[UpdateService] ❌ Could not determine latest version from either GitHub or Firebase.');
        if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('업데이트 서버에 연결할 수 없습니다.'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      final bool hasNew = _isNewerVersion(currentVersion, serverVersion);
      debugPrint('[UpdateService] ⚖️ Result: Latest=$serverVersion vs Current=$currentVersion -> HasUpdate=$hasNew');

      if (hasNew) {
        if (silent && Platform.isWindows) {
          debugPrint('[UpdateService] 🚀 Background update found on launch. Executing quiet updater and terminating.');
          _performWindowsUpdate(null, appInstallerManifestUrl);
        } else if (context.mounted) {
          _showUpdateDialog(context, serverVersion, () {
            if (Platform.isWindows) {
              _performWindowsUpdate(context, appInstallerManifestUrl);
            } else if (Platform.isAndroid) {
              final apkAsset = assets.firstWhere(
                (asset) => (asset['name'] as String).endsWith('.apk'),
                orElse: () => null,
              );
              if (apkAsset != null) {
                final downloadUrl = apkAsset['browser_download_url'] as String;
                _performAndroidUpdate(context, downloadUrl);
              }
            }
          });
        }
      } else {
        if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 현재 최신 버전(v$currentVersion)을 사용하고 있습니다.'),
              backgroundColor: const Color(0xFF2EC4B6),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] Error during update check: $e');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업데이트 확인 오류: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      // 락 즉시 해제
      _isChecking = false;
    }
  }

  static bool _isNewerVersion(String current, String server) {
    try {
      final cleanCurrent = current.replaceAll(RegExp(r'[^0-9.]'), '');
      final cleanServer = server.replaceAll(RegExp(r'[^0-9.]'), '');
      List<int> c = cleanCurrent.split('.').where((e) => e.isNotEmpty).map((e) => int.tryParse(e) ?? 0).toList();
      List<int> s = cleanServer.split('.').where((e) => e.isNotEmpty).map((e) => int.tryParse(e) ?? 0).toList();
      int maxLen = s.length > c.length ? s.length : c.length;
      for (int i = 0; i < maxLen; i++) {
        int partS = i < s.length ? s[i] : 0;
        int partC = i < c.length ? c[i] : 0;
        if (partS > partC) return true;
        if (partS < partC) return false;
      }
    } catch (_) {}
    return false;
  }

  static void _showUpdateDialog(
    BuildContext context,
    String newVersion,
    VoidCallback onConfirm,
  ) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F0E17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF2EC4B6), width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.system_update_rounded, color: Color(0xFF2EC4B6), size: 22),
              const SizedBox(width: 10),
              const Text(
                '업데이트 알림',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'v$newVersion 버전이 출시되었습니다!',
                style: const TextStyle(color: Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                '지금 바로 업데이트하시겠습니까?\n[업데이트 시작] 을 누르면 즉시 다운로드 후 재시작합니다.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('나중에', style: TextStyle(color: Colors.white30)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onConfirm();
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

  static void _showDownloadProgressDialog(BuildContext context, ValueNotifier<double> progressNotifier) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, child) {
            final percentage = (progress * 100).toStringAsFixed(1);
            return AlertDialog(
              backgroundColor: const Color(0xFF0F0E17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF2EC4B6), width: 1.5),
              ),
              title: const Text(
                '업데이트 다운로드 중',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2EC4B6)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$percentage%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  static Future<void> _performWindowsUpdate(BuildContext? context, String appInstallerUrl) async {
    try {
      final safeInstallerUrl = appInstallerUrl.isNotEmpty ? appInstallerUrl : appInstallerManifestUrl;
      debugPrint('[UpdateService] 🚀 Launching Boardest Windows AppInstaller update via PowerShell: $safeInstallerUrl');

      final exeDir = p.dirname(Platform.resolvedExecutable);
      final localAppInstaller = p.join(exeDir, 'boardest.appinstaller');

      final script = '''
\$ErrorActionPreference = 'Continue'
\$waitLimit = 20
while ((Get-Process -Name 'boardest' -ErrorAction SilentlyContinue) -and (\$waitLimit -gt 0)) {
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

if (-not \$updateSuccess) {
  try {
    \$tempAppx = Join-Path \$env:TEMP 'boardest_update.appx'
    Invoke-WebRequest -Uri 'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest.appx' -OutFile \$tempAppx -UseBasicParsing
    Add-AppxPackage -Path \$tempAppx -ForceApplicationShutdown -ForceTargetApplicationShutdown -ErrorAction Stop
    Remove-Item \$tempAppx -Force -ErrorAction SilentlyContinue
    \$updateSuccess = \$true
  } catch {}
}

if (\$updateSuccess) {
  Start-Sleep -Milliseconds 800
  Start-Process 'explorer.exe' 'shell:AppsFolder\\jiwho.boardest.bst_nmkn64tehfz7a!App'
}
''';

      final tempDir = await getTemporaryDirectory();
      final runnerFile = File(p.join(tempDir.path, 'boardest_updater.ps1'));
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
      debugPrint('[UpdateService] Error executing Windows update: $e');
      if (context != null && context.mounted) {
        _showErrorDialog(context, 'Windows 자동 업데이트 실행 중 오류 발생: $e');
      }
    }
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
          progressNotifier.value = received / totalLength;
        }
        return chunk;
      }).pipe(sink);

      await sink.close();
      client.close();

      if (context.mounted) Navigator.of(context).pop();

      final result = await OpenFilex.open(apkPath);
      if (result.type != ResultType.done) {
        throw Exception('설치 프로그램 호출 실패: ${result.message}');
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) _showErrorDialog(context, 'Android APK 다운로드 또는 설치 중 오류 발생: $e');
    }
  }

  static void _showErrorDialog(BuildContext context, String message) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F0E17),
          title: const Text('오류', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인', style: TextStyle(color: Color(0xFF2EC4B6))),
            ),
          ],
        );
      },
    );
  }
}

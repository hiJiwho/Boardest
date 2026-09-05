import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';


class UpdateService {
  static const String currentVersion = '2.9.9.2';
  static const String repoOwner = 'hiJiwho';
  static const String repoName = 'Boardest';

  // 중복 업데이트 체크 방지 플래그 (앱 실행 중 1회만 실행)
  static bool _isChecking = false;

  /// GitHub의 최신 릴리즈를 체크하고 업데이트가 필요하면 다운로드 및 설치 프로세스를 시작합니다.
  static Future<void> checkAndUpdate(BuildContext context, {bool silent = true}) async {
    // Web: Firebase Hosting에 의해 상시 최신 상태 유지
    if (kIsWeb) return;

    // Windows 및 Android 인앱 자동 업데이트 지원
    if (!Platform.isWindows && !Platform.isAndroid) return;

    // 중복 실행 방지: 이미 체크 중이면 즉시 리턴
    if (_isChecking) return;
    _isChecking = true;
    try {
      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'Boardest-Client/$currentVersion',
          'Accept': 'application/vnd.github.v3+json',
        },
      ).timeout(const Duration(seconds: 8));
      
      if (response.statusCode != 200) {
        debugPrint('Update check returned status code: ${response.statusCode}');
        if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('업데이트 서버 응답 코드: ${response.statusCode}'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      if (tagName.isEmpty) return;

      final serverVersion = tagName.replaceAll(RegExp(r'[^0-9.]'), ''); // e.g. "v1.0.1" -> "1.0.1"
      if (_isNewerVersion(currentVersion, serverVersion)) {
        debugPrint('New version available: $serverVersion (Current: $currentVersion)');
        final assets = data['assets'] as List<dynamic>? ?? [];
        
        if (context.mounted) {
          _showUpdateDialog(context, serverVersion, () {
            if (Platform.isWindows) {
              String appInstallerUrl = 'https://download-boardest.web.app/bst.appinstaller';
              for (final asset in assets) {
                final name = (asset['name'] as String? ?? '').toLowerCase();
                if (name.endsWith('.appinstaller') || name == 'boardest.appinstaller' || name == 'bst.appinstaller') {
                  appInstallerUrl = asset['browser_download_url'] as String? ?? appInstallerUrl;
                  break;
                }
              }
              _performWindowsUpdate(context, appInstallerUrl);
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
            const SnackBar(
              content: Text('🎉 현재 최신 버전(v$currentVersion)을 사용하고 있습니다.'),
              backgroundColor: Color(0xFF2EC4B6),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error during update check: $e');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업데이트 확인 오류: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      // 2분 후 재체크 허용
      Future.delayed(const Duration(minutes: 2), () => _isChecking = false);
    }
  }

  static bool _isNewerVersion(String current, String server) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final serverParts = server.split('.').map(int.parse).toList();
      for (int i = 0; i < serverParts.length; i++) {
        if (i >= currentParts.length) return true;
        if (serverParts[i] > currentParts[i]) return true;
        if (serverParts[i] < currentParts[i]) return false;
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


  static Future<void> _performWindowsUpdate(BuildContext context, String appInstallerUrl) async {
    try {
      final script = '''
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "     Boardest 전자칠판 AppX 자동 업데이트 진행 중...  " -ForegroundColor Yellow
Write-Host "=================================================" -ForegroundColor Cyan
Start-Sleep -Milliseconds 800
try {
  Write-Host "AppInstaller를 통해 최신 AppX 패키지를 배포합니다..." -ForegroundColor Gray
  Add-AppxPackage -AppInstallerFile '$appInstallerUrl' -ForceUpdateFromAnyVersion -ErrorAction Stop
  Write-Host "업데이트 완료! Boardest를 재실행합니다..." -ForegroundColor Green
  Start-Sleep -Milliseconds 800
  Start-Process 'explorer.exe' 'shell:AppsFolder\\jiwho.boardest.bst_nmkn64tehfz7a!App'
} catch {
  Write-Host "AppInstaller 실패, 직접 최신 AppX 다운로드 설치를 시도합니다..." -ForegroundColor Yellow
  \$tempAppx = Join-Path \$env:TEMP 'boardest_update.appx'
  Invoke-WebRequest -Uri 'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest.appx' -OutFile \$tempAppx
  Add-AppxPackage -Path \$tempAppx -ForceUpdateFromAnyVersion
  Remove-Item \$tempAppx -Force -ErrorAction SilentlyContinue
  Start-Process 'explorer.exe' 'shell:AppsFolder\\jiwho.boardest.bst_nmkn64tehfz7a!App'
}
''';

      await Process.start(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        mode: ProcessStartMode.detached,
      );

      exit(0);
    } catch (e) {
      debugPrint('Error executing Windows update: $e');
      if (context.mounted) {
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

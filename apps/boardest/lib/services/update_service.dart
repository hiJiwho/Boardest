import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:open_filex/open_filex.dart';


class UpdateService {
  static const String currentVersion = '2.9.8.5';
  static const String repoOwner = 'hiJiwho';
  static const String repoName = 'Boardest';

  // 중복 업데이트 체크 방지 플래그 (앱 실행 중 1회만 실행)
  static bool _isChecking = false;

  /// GitHub의 최신 릴리즈를 체크하고 업데이트가 필요하면 다운로드 및 설치 프로세스를 시작합니다.
  static Future<void> checkAndUpdate(BuildContext context) async {
    // 중복 실행 방지: 이미 체크 중이면 즉시 리턴
    if (_isChecking) return;
    _isChecking = true;
    try {
      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'Boardest-Client/2.9.8.5',
          'Accept': 'application/vnd.github.v3+json',
        },
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode != 200) {
        debugPrint('Update check returned status code: ${response.statusCode}');
        return; // 리포지토리가 비어있거나 릴리즈가 아직 없을 경우 무시
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      if (tagName.isEmpty) return;

      final serverVersion = tagName.replaceAll(RegExp(r'[^0-9.]'), ''); // e.g. "v1.0.1" -> "1.0.1"
      if (_isNewerVersion(currentVersion, serverVersion)) {
        debugPrint('New version available: $serverVersion (Current: $currentVersion)');
        final assets = data['assets'] as List<dynamic>? ?? [];
        
        if (Platform.isWindows) {
          // 1순위: Boardest_Setup.exe 설치 프로그램 에셋
          // 2순위: .zip 무설치 압축 에셋
          final exeAsset = assets.firstWhere(
            (asset) {
              final n = (asset['name'] as String).toLowerCase();
              return n.endsWith('.exe') && !n.contains('teacher') && (n.contains('setup') || n.contains('boardest'));
            },
            orElse: () => null,
          );
          final zipAsset = assets.firstWhere(
            (asset) => (asset['name'] as String).endsWith('.zip'),
            orElse: () => null,
          );

          if (exeAsset != null) {
            final downloadUrl = exeAsset['browser_download_url'] as String;
            _showUpdateDialog(context, serverVersion, () {
              _performWindowsInstallerUpdate(context, downloadUrl);
            });
          } else if (zipAsset != null) {
            final downloadUrl = zipAsset['browser_download_url'] as String;
            _showUpdateDialog(context, serverVersion, () {
              _performWindowsUpdate(context, downloadUrl);
            });
          }
        } else if (Platform.isAndroid) {
          final apkAsset = assets.firstWhere(
            (asset) => (asset['name'] as String).endsWith('.apk'),
            orElse: () => null,
          );
          if (apkAsset != null) {
            final downloadUrl = apkAsset['browser_download_url'] as String;
            _showUpdateDialog(context, serverVersion, () {
              _performAndroidUpdate(context, downloadUrl);
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error during update check: $e');
    } finally {
      // 2분 후 재체크 허용 (앱 재실행 후 업데이트 안 됐을 경우 대비)
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

  /// Inno Setup 설치형 자동 업데이트 (무인 설치 및 자동 재실행)
  static Future<void> _performWindowsInstallerUpdate(BuildContext context, String url) async {
    final progressNotifier = ValueNotifier<double>(0.0);
    _showDownloadProgressDialog(context, progressNotifier);

    try {
      final tempDir = await getTemporaryDirectory();
      final setupPath = p.join(tempDir.path, 'Boardest_Setup_Update.exe');

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      final totalLength = response.contentLength ?? 0;
      int received = 0;

      final file = File(setupPath);
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

      // Execute Inno Setup installer silently and restart application
      await Process.start(
        setupPath,
        ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) _showErrorDialog(context, 'Windows 설치형 자동 업데이트 중 오류 발생: $e');
    }
  }

  /// 무설치 ZIP 압축 해제 및 덮어쓰기 업데이트
  static Future<void> _performWindowsUpdate(BuildContext context, String url) async {
    final progressNotifier = ValueNotifier<double>(0.0);
    _showDownloadProgressDialog(context, progressNotifier);

    try {
      final tempDir = await getTemporaryDirectory();
      final zipPath = p.join(tempDir.path, 'boardest_update.zip');
      final extractDir = p.join(tempDir.path, 'boardest_extracted');

      // Download file
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      final totalLength = response.contentLength ?? 0;
      int received = 0;

      final file = File(zipPath);
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

      // Extract ZIP
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final extractFolder = Directory(extractDir);
      if (extractFolder.existsSync()) {
        extractFolder.deleteSync(recursive: true);
      }
      extractFolder.createSync(recursive: true);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(p.join(extractDir, filename));
          outFile.createSync(recursive: true);
          await outFile.writeAsBytes(data);
        } else {
          final outDir = Directory(p.join(extractDir, filename));
          outDir.createSync(recursive: true);
        }
      }

      final currentExePath = Platform.resolvedExecutable;
      final currentAppDir = p.dirname(currentExePath);

      final updaterBatPath = p.join(tempDir.path, 'boardest_updater.bat');
      final updaterContent = '''
@echo off
title Boardest Updater
echo Waiting for Boardest to close...
timeout /t 2 /nobreak > nul
echo Copying new files to: "$currentAppDir"
xcopy /y /e /q "$extractDir\\*" "$currentAppDir\\"
echo Restarting Boardest...
start "" "$currentExePath"
echo Done. Cleaning up...
del "%~f0"
''';

      await File(updaterBatPath).writeAsString(updaterContent);

      if (context.mounted) Navigator.of(context).pop();

      await Process.start('cmd.exe', ['/c', updaterBatPath], runInShell: true);
      exit(0);
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) _showErrorDialog(context, 'Windows 자동 업데이트 중 오류 발생: $e');
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

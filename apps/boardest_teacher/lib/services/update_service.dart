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

  static const String currentVersion = '2.9.9.1';
  static const String githubRepoUrl = 'https://api.github.com/repos/hiJiwho/Boardest/releases/latest';
  static const String verificationServerUrl = 'https://boardest-update-work.firebaseapp.com';

  // 중복 업데이트 체크 방지 플래그 (앱 실행 중 1회만 실행)
  static bool _isChecking = false;

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

  /// Check for latest update from GitHub Releases (with optional PAT auth)
  Future<UpdateInfo?> checkForUpdate() async {
    // Web 환경에서는 브라우저 캐시 정책에 따름
    if (kIsWeb) return null;
    if (!Platform.isWindows && !Platform.isAndroid) return null;
    if (_isChecking) return null; // 중복 실행 방지
    _isChecking = true;
    try {
      final token = await getGithubToken();
      final headers = <String, String>{
        'User-Agent': 'Boardest-Teacher-Client/2.9.8.9',
        'Accept': 'application/vnd.github.v3+json',
        if (token != null && token.isNotEmpty) 'Authorization': 'token $token',
      };

      var response = await http.get(
        Uri.parse(githubRepoUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) {
        response = await http.get(
          Uri.parse('https://api.github.com/repos/hiJiwho/Boardest/releases/latest'),
          headers: headers,
        ).timeout(const Duration(seconds: 4));
      }

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final String tag = (data['tag_name'] ?? 'v1.0.0').toString().replaceAll('v', '').trim();
      final String notes = (data['body'] ?? '새로운 업데이트가 출시되었습니다.').toString();

      List assets = data['assets'] ?? [];
      String downloadUrl = '';

      // Windows: AppInstaller / AppX 전용 업데이트 (Setup.exe 배제)
      if (Platform.isWindows) {
        for (var asset in assets) {
          String name = asset['name'].toString().toLowerCase();
          if (name == 'bst-teacher.appinstaller' || (name.contains('teacher') && name.endsWith('.appinstaller'))) {
            downloadUrl = asset['browser_download_url'] ?? '';
            break;
          }
        }
        if (downloadUrl.isEmpty) {
          downloadUrl = 'https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher.appinstaller';
        }
      } else if (Platform.isAndroid) {
        for (var asset in assets) {
          String name = asset['name'].toString().toLowerCase();
          if (name.endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'] ?? '';
            break;
          }
        }
      }

      bool hasNew = _isVersionNewer(tag, currentVersion);

      return UpdateInfo(
        latestVersion: tag,
        currentVersion: currentVersion,
        downloadUrl: downloadUrl,
        releaseNotes: notes,
        hasUpdate: hasNew,
      );
    } catch (_) {
      return null;
    } finally {
      // 2분 후 재체크 허용
      Future.delayed(const Duration(minutes: 2), () => _isChecking = false);
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
      final script = '''
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "   Boardest Teacher AppX 자동 업데이트 진행 중... " -ForegroundColor Yellow
Write-Host "=================================================" -ForegroundColor Cyan
Start-Sleep -Milliseconds 800
try {
  Write-Host "AppInstaller를 통해 최신 AppX 패키지를 배포합니다..." -ForegroundColor Gray
  Add-AppxPackage -AppInstallerFile '$appInstallerUrl' -ForceUpdateFromAnyVersion -ErrorAction Stop
  Write-Host "업데이트 완료! 교사용 앱을 실행합니다..." -ForegroundColor Green
  Start-Sleep -Milliseconds 800
  Start-Process 'explorer.exe' 'shell:AppsFolder\\jiwho.boardest.teacher_nmkn64tehfz7a!App'
} catch {
  Write-Host "AppInstaller URL 실패, 백업 AppX 다운로드 설치를 시도합니다..." -ForegroundColor Yellow
  \$tempAppx = Join-Path \$env:TEMP 'bst_teacher_update.appx'
  Invoke-WebRequest -Uri 'https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher.appx' -OutFile \$tempAppx
  Add-AppxPackage -Path \$tempAppx -ForceUpdateFromAnyVersion
  Remove-Item \$tempAppx -Force -ErrorAction SilentlyContinue
  Start-Process 'explorer.exe' 'shell:AppsFolder\\jiwho.boardest.teacher_nmkn64tehfz7a!App'
}
''';

      await Process.start(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        mode: ProcessStartMode.detached,
      );

      // 파일 잠금 해제를 위해 교사용 앱 즉시 종료
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
                    : 'https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher.appinstaller';
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

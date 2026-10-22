import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';

enum UpdateState {
  idle,
  downloading,
  downloaded,
  installing,
}

/// 백그라운드 무인 자동 업데이트 서비스 (Windows AppX & Android APK)
/// 1. 앱 시작 시 승인 팝업 없이 백그라운드에서 즉시 최신 패키지 다운로드 시작
/// 2. 상단에 [업데이트 다운로드 중 (XX%)] 슬림 프로그레스 바 표시
/// 3. 다운로드 완료 후 수업시간이면 보류, 쉬는시간에 급식 대신 [업데이트 필요함!!] 카드 노출
/// 4. 안드로이드는 수동 설치 안내 후 패키지 인스톨러 열기, 윈도우는 Add-AppxPackage 실행 후 재실행
class UpdateService {
  static const String defaultVersion = '5.0.7';
  static const String _releaseApi =
      'https://api.github.com/repos/hiJiwho/Boardest/releases/latest';
  static const String downloadPage = 'https://boardest-downloads.web.app';

  static final ValueNotifier<UpdateState> stateNotifier =
      ValueNotifier(UpdateState.idle);
  static final ValueNotifier<double> downloadProgressNotifier =
      ValueNotifier(0.0);
  static final ValueNotifier<double> installProgressNotifier =
      ValueNotifier(0.0);

  static String? latestVersion;
  static String? downloadedPackagePath;
  static bool _isChecking = false;
  static DateTime? _lastSilentCheckTime;
  static String? _resolvedVersion;

  static String get currentVersion {
    if (_resolvedVersion != null) return _resolvedVersion!;
    if (!kIsWeb && Platform.isWindows) {
      final match = RegExp(
        r'jiwho\.boardest\.(?:bst|teacher|class-lite|overlay-panser)_([0-9.]+)_',
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('bst_installed_version');
    } catch (_) {}
    try {
      final jsonStr = await rootBundle.loadString('version.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final v = data['version'] as String?;
      if (v != null && v.isNotEmpty) {
        _resolvedVersion = v.trim();
      }
    } catch (_) {}
  }

  /// 백그라운드 업데이트 확인 및 다운로드 시작
  static Future<void> checkAndUpdate(
    BuildContext context, {
    bool silent = true,
    bool force = false,
    String? channel,
  }) async {
    // 웹, 디버그, 교사용 앱, 지원하지 않는 OS는 건너뜀
    if (kIsWeb || (!Platform.isWindows && !Platform.isAndroid) || _isChecking) {
      return;
    }
    if (stateNotifier.value != UpdateState.idle) {
      return;
    }
    if (silent &&
        !force &&
        _lastSilentCheckTime != null &&
        DateTime.now().difference(_lastSilentCheckTime!) <
            const Duration(minutes: 5)) {
      return;
    }

    await initVersion();

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
        latestVersion = latest;
        final isWindows = !kIsWeb && Platform.isWindows;
        final targetUrl = isWindows ? appxDownloadUrl : apkDownloadUrl;

        // 승인 없이 바로 백그라운드 다운로드 개시!
        unawaited(_startSilentDownload(targetUrl, latest, isWindows));
      }
    } catch (e) {
      debugPrint('[UpdateService] Update check failed: $e');
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

  /// 백그라운드 자동 다운로드 실행
  static Future<void> _startSilentDownload(
    String downloadUrl,
    String version,
    bool isWindows,
  ) async {
    try {
      stateNotifier.value = UpdateState.downloading;
      downloadProgressNotifier.value = 0.0;

      final tempDir = await getTemporaryDirectory();
      final ext = isWindows ? 'appx' : 'apk';
      final fileName = 'boardest_update_$version.$ext';
      final savePath = p.join(tempDir.path, fileName);

      // 이미 완전한 파일이 존재하는 경우
      final existingFile = File(savePath);
      if (existingFile.existsSync() && existingFile.lengthSync() > 10 * 1024 * 1024) {
        downloadedPackagePath = savePath;
        downloadProgressNotifier.value = 1.0;
        stateNotifier.value = UpdateState.downloaded;
        return;
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers['User-Agent'] = 'Boardest-Updater/$currentVersion';
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      final file = File(savePath);
      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          downloadProgressNotifier.value = (received / total).clamp(0.0, 1.0);
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      downloadedPackagePath = savePath;
      downloadProgressNotifier.value = 1.0;
      stateNotifier.value = UpdateState.downloaded;
      debugPrint('[UpdateService] Download complete: $savePath');
    } catch (e) {
      debugPrint('[UpdateService] Silent download failed: $e');
      stateNotifier.value = UpdateState.idle;
    }
  }

  /// 다운로드된 패키지 설치 실행
  static Future<void> executeInstall(BuildContext context) async {
    final savePath = downloadedPackagePath;
    if (savePath == null || !File(savePath).existsSync()) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (latestVersion != null && latestVersion!.isNotEmpty) {
        await prefs.setString('bst_installed_version', latestVersion!);
        _resolvedVersion = latestVersion;
      }
    } catch (_) {}

    if (!kIsWeb && Platform.isAndroid) {
      // 안드로이드: 수동 설치 안내 다이얼로그 표시
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF141721),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: const [
              Icon(Icons.android_rounded, color: Color(0xFF00F5D4), size: 28),
              SizedBox(width: 10),
              Text('앱 업데이트 안내', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: const Text(
            '잠시 후 시스템 패키지 설치 프로그램이 실행됩니다.\n화면에 나타나는 [설치] 또는 [업데이트] 버튼을 눌러 수동 설치를 완료해 주세요.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F5D4),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('설치 화면 열기', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      await OpenFilex.open(
        savePath,
        type: 'application/vnd.android.package-archive',
      );
      return;
    }

    if (!kIsWeb && Platform.isWindows) {
      // 윈도우: Add-AppxPackage 실행 및 퍼센트 게이지 표시 후 재실행
      stateNotifier.value = UpdateState.installing;
      installProgressNotifier.value = 0.05;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: ValueListenableBuilder<double>(
            valueListenable: installProgressNotifier,
            builder: (c, progress, _) {
              final pct = (progress * 100).toInt();
              return AlertDialog(
                backgroundColor: const Color(0xFF0D111A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Color(0xFF00F5D4), width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(28),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.autorenew_rounded, color: Color(0xFF00F5D4), size: 48),
                    const SizedBox(height: 16),
                    Text(
                      '업데이트 설치 중...',
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '새 버전을 등록하고 앱을 자동으로 다시 시작합니다.\n잠시만 기다려주세요. ($pct%)',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        minHeight: 10,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF00F5D4)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      // 타이머로 퍼센트 점진적 증가
      Timer? progressTimer;
      progressTimer = Timer.periodic(const Duration(milliseconds: 150), (t) {
        if (installProgressNotifier.value < 0.85) {
          installProgressNotifier.value += 0.05;
        }
      });

      try {
        // 백그라운드 PowerShell Add-AppxPackage 실행
        final proc = await Process.start('powershell.exe', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          'Add-AppxPackage -Path "$savePath" -ForceApplicationShutdown',
        ]);

        final exitCode = await proc.exitCode;
        progressTimer.cancel();
        installProgressNotifier.value = 1.0;

        if (exitCode == 0) {
          await Future.delayed(const Duration(milliseconds: 800));
          exit(0);
        } else {
          // 실패 시 fallback: Start-Process 실행
          await Process.start('powershell.exe', [
            '-NoProfile',
            '-Command',
            'Start-Process',
            '"$savePath"',
          ]);
          await Future.delayed(const Duration(milliseconds: 800));
          exit(0);
        }
      } catch (e) {
        progressTimer.cancel();
        debugPrint('[UpdateService] AppX install error: $e');
        // 수동 열기 시도
        await OpenFilex.open(savePath);
        exit(0);
      }
    }
  }
}

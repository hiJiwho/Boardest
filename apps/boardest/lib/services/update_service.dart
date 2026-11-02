import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, MethodChannel;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import 'system_app_scanner.dart';

enum UpdateState {
  idle,
  checking,
  downloading,
  downloaded,
  installing,
}

/// 백그라운드 무인 자동 업데이트 및 버전 보안 잠금(Lockout) 서비스
/// 1. 최신 버전 확인 및 4번째 자리 무시(5.2.1.1과 5.2.1.2는 1개 업데이트로 간주)
/// 2. 맨 앞자리(Major) 변경 시 즉시 앱 잠금 (실행 차단)
/// 3. 6차례 업데이트 지연 시 앱 잠금 (실행 차단)
/// 4. 3차례 업데이트 지연 시 Cloud 기능 사용 제한
/// 5. 잠금 화면 필수 4대 버튼: [업데이트 다운 / 수동 설치 / 앱 런처 / 앱 삭제]
/// 6. 윈도우: AppData에 다운로드 후 종료하지 않고 윈도우 패키지 설치 관리자(AppX) 구동 -> 새 앱 실행 시 이전 AppX 자동 삭제
class UpdateService {
  static const String defaultVersion = '5.5.3.1';
  static const String defaultBuildNumber = '5531';
  static const String defaultFullVersion = '5.5.3.1+5531';
  static const String _releasesApi =
      'https://api.github.com/repos/hiJiwho/Boardest/releases?per_page=30';
  static const String downloadPage = 'https://boardest-downloads.web.app';

  static final ValueNotifier<UpdateState> stateNotifier =
      ValueNotifier(UpdateState.idle);
  static final ValueNotifier<double> downloadProgressNotifier =
      ValueNotifier(0.0);
  static final ValueNotifier<double> installProgressNotifier =
      ValueNotifier(0.0);

  static final ValueNotifier<bool> isBlockedNotifier = ValueNotifier(false);
  static final ValueNotifier<bool> isCloudBlockedNotifier = ValueNotifier(false);
  static String? blockReason;

  static String? latestVersion;
  static String? downloadedPackagePath;
  static bool _isChecking = false;
  static DateTime? _lastSilentCheckTime;
  static String? _resolvedVersion;

  static String get currentVersion {
    if (_resolvedVersion != null) return _resolvedVersion!;
    if (!kIsWeb && Platform.isWindows) {
      final match = RegExp(
        r'jiwho\.boardest\.(?:bst|cloud|board|class|teacher|class-lite|overlay-panser)_([0-9.]+)_',
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

    // 1) On Android, try MethodChannel first to query native package version (versionName)
    if (!kIsWeb && Platform.isAndroid) {
      final channels = ['boardest/version', 'com.boardest/launch_args'];
      for (final chName in channels) {
        try {
          final channel = MethodChannel(chName);
          final res = await channel.invokeMethod<dynamic>('getAppVersion') ??
              await channel.invokeMethod<dynamic>('getPackageInfo');
          if (res is Map) {
            final v = (res['versionName'] ?? res['version'])?.toString();
            final b = (res['versionCode'] ?? res['buildNumber'])?.toString();
            if (v != null && v.trim().isNotEmpty) {
              final vTrim = v.trim();
              _resolvedVersion = (b != null && b.trim().isNotEmpty) ? '$vTrim+$b' : vTrim;
              debugPrint('[UpdateService] Resolved Android version from MethodChannel ($chName): $_resolvedVersion');
              return;
            }
          } else if (res is String && res.trim().isNotEmpty) {
            _resolvedVersion = res.trim();
            debugPrint('[UpdateService] Resolved Android version from MethodChannel string ($chName): $_resolvedVersion');
            return;
          }
        } catch (_) {}
      }
    }

    // 2) Try PackageInfo.fromPlatform()
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      final b = info.buildNumber.trim();
      if (v.isNotEmpty) {
        _resolvedVersion = b.isNotEmpty ? '$v+$b' : v;
        debugPrint('[UpdateService] Resolved version from PackageInfo: $_resolvedVersion');
        return;
      }
    } catch (e) {
      debugPrint('[UpdateService] PackageInfo lookup error: $e');
    }

    // 3) Try Windows MSIX executable path regex
    if (!kIsWeb && Platform.isWindows) {
      final match = RegExp(
        r'jiwho\.boardest\.(?:bst|cloud|board|class|teacher|class-lite|overlay-panser)_([0-9.]+)_',
        caseSensitive: false,
      ).firstMatch(Platform.resolvedExecutable);
      if (match?.group(1) != null) {
        final v = match!.group(1)!;
        final parts = v.split('.');
        if (parts.length == 4 && parts[3] == '0') {
          _resolvedVersion = '${parts[0]}.${parts[1]}.${parts[2]}';
          return;
        }
        _resolvedVersion = v;
        return;
      }
    }

    // 4) Try version.json from rootBundle
    for (final path in ['assets/version.json', 'version.json']) {
      try {
        final jsonStr = await rootBundle.loadString(path);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final v = (data['version'] as String?)?.trim();
        final b = (data['build_number'] ?? data['buildNumber'])?.toString().trim();
        if (v != null && v.isNotEmpty) {
          _resolvedVersion = (b != null && b.isNotEmpty) ? '$v+$b' : v;
          debugPrint('[UpdateService] Resolved version from $path: $_resolvedVersion');
          return;
        }
      } catch (_) {}
    }

    // 5) Cache fallback
    _resolvedVersion = defaultFullVersion;
  }

  /// 4번째 자리를 제거하고 앞 3자리(Major.Minor.Patch)만 반환 (빌드 번호 및 v 접두사 제거)
  static String normalizeVersion(String v) {
    final clean = v.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.trim();
    final parts = clean.split('.');
    if (parts.length >= 3) {
      return '${parts[0]}.${parts[1]}.${parts[2]}';
    }
    return clean;
  }

  /// Windows 패키지 에셋 우선순위 점수 계산 (.msix 최우선, boardest-class 우선)
  /// 반환값: 0 (비매칭) ~ 100 (최우선 매칭)
  static int getWindowsAssetScore(String name, {required bool isCloud}) {
    final lower = name.trim().toLowerCase();
    final isMsix = lower.endsWith('.msix');
    final isAppx = lower.endsWith('.appx');
    if (!isMsix && !isAppx) return 0;

    if (isCloud) {
      if (lower.contains('teacher') || lower.contains('overlay')) return 0;
      final isCloudAsset = lower.contains('boardest-cloud') ||
          lower.contains('class-cloud') ||
          lower.contains('bcld');
      if (!isCloudAsset) return 0;

      if (isMsix) {
        if (lower.startsWith('boardest-cloud') || lower.contains('boardest-cloud')) return 100;
        if (lower.startsWith('class-cloud') || lower.contains('class-cloud')) return 90;
        return 80;
      } else {
        if (lower.startsWith('boardest-cloud') || lower.contains('boardest-cloud')) return 40;
        if (lower.startsWith('class-cloud') || lower.contains('class-cloud')) return 30;
        return 20;
      }
    } else {
      if (lower.contains('teacher') ||
          lower.contains('lite') ||
          lower.contains('cloud') ||
          lower.contains('bcld') ||
          lower.contains('overlay')) {
        return 0;
      }

      if (isMsix) {
        if (lower == 'boardest-class.msix' || lower.startsWith('boardest-class.')) return 100;
        if (lower.contains('boardest-class')) return 95;
        if (lower == 'boardest.msix' || lower.startsWith('boardest.')) return 85;
        if (lower.contains('bst-class') || lower.contains('boardest')) return 80;
        return 70;
      } else {
        if (lower == 'boardest-class.appx' || lower.startsWith('boardest-class.')) return 40;
        if (lower.contains('boardest-class')) return 35;
        if (lower == 'boardest.appx' || lower.startsWith('boardest.')) return 30;
        if (lower.contains('bst-class') || lower.contains('boardest')) return 25;
        return 20;
      }
    }
  }

  /// Android APK 에셋 우선순위 점수 계산
  static int getApkAssetScore(String name, {required bool isCloud}) {
    final lower = name.trim().toLowerCase();
    if (!lower.endsWith('.apk')) return 0;

    if (isCloud) {
      if (lower.contains('teacher') || lower.contains('overlay')) return 0;
      final isCloudAsset = lower.contains('boardest-cloud') ||
          lower.contains('class-cloud') ||
          lower.contains('bcld');
      if (!isCloudAsset) return 0;

      if (lower.startsWith('boardest-cloud') || lower.contains('boardest-cloud')) return 100;
      if (lower.startsWith('class-cloud') || lower.contains('class-cloud')) return 90;
      return 80;
    } else {
      if (lower.contains('teacher') ||
          lower.contains('lite') ||
          lower.contains('cloud') ||
          lower.contains('bcld') ||
          lower.contains('overlay')) {
        return 0;
      }

      if (lower == 'boardest-class.apk' || lower.startsWith('boardest-class.')) return 100;
      if (lower.contains('boardest-class')) return 95;
      if (lower == 'boardest.apk' || lower.startsWith('boardest.')) return 85;
      if (lower.contains('bst-class') || lower.contains('boardest')) return 80;
      return 70;
    }
  }

  /// 다운로드 URL에서 패키지 파일 확장자 추출 (.msix, .appx, .apk, .exe 동적 매칭)
  static String extractExtensionFromUrl(String url, {required bool isWindows}) {
    final uriPath = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (uriPath.endsWith('.msix')) return 'msix';
    if (uriPath.endsWith('.appx')) return 'appx';
    if (uriPath.endsWith('.apk')) return 'apk';
    if (uriPath.endsWith('.exe')) return 'exe';
    return isWindows ? 'msix' : 'apk';
  }

  /// 이전 다운로드된 임시 AppX / APK / MSIX 설치 파일 자동 삭제 (새 앱 실행 시 자동 정리)
  static Future<void> cleanupOldUpdates() async {
    if (kIsWeb) return;
    try {
      final dirsToClean = <Directory>[];

      try {
        final appSupport = await getApplicationSupportDirectory();
        dirsToClean.add(Directory(p.join(appSupport.path, 'Updates')));
      } catch (_) {}

      try {
        final tempDir = await getTemporaryDirectory();
        dirsToClean.add(Directory(p.join(tempDir.path, 'Updates')));
        dirsToClean.add(tempDir);
      } catch (_) {}

      for (final targetDir in dirsToClean) {
        if (!targetDir.existsSync()) continue;
        for (final entity in targetDir.listSync()) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            final base = p.basename(entity.path).toLowerCase();
            final isInstaller = ext == '.appx' || ext == '.msix' || ext == '.apk' || ext == '.exe';
            final isLegacyTemp = base.startsWith('boardest_update_') || base.startsWith('boardest_cloud_update_');
            if (isInstaller || isLegacyTemp) {
              try {
                entity.deleteSync();
                debugPrint('[UpdateService] 🧹 Old installer package removed: ${entity.path}');
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] cleanupOldUpdates error: $e');
    }
  }

  /// 백그라운드 업데이트 확인, 버전 차이 계산 및 잠금 여부 판별
  static Future<void> checkAndUpdate(
    BuildContext context, {
    bool silent = true,
    bool force = false,
    String? channel,
  }) async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isAndroid) || _isChecking) {
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
    await cleanupOldUpdates();

    _isChecking = true;
    _lastSilentCheckTime = DateTime.now();
    if (!silent || force) {
      stateNotifier.value = UpdateState.checking;
    }

    try {
      final response = await http.get(Uri.parse(_releasesApi), headers: {
        'User-Agent': 'Boardest-Client/$currentVersion',
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw Exception('Release server returned ${response.statusCode}');
      }

      final releases = jsonDecode(response.body) as List<dynamic>;
      if (releases.isEmpty) return;

      // 1. 4번째 자리를 무시한 유니크 릴리즈 목록 추출
      final List<String> distinctNormalizedReleases = [];
      String? latestFullTag;
      Map<String, dynamic>? latestReleaseData;

      for (final r in releases) {
        final tag = (r['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '').trim();
        if (tag.isEmpty) continue;
        latestFullTag ??= tag;
        latestReleaseData ??= r as Map<String, dynamic>;

        final normalized = normalizeVersion(tag);
        if (!distinctNormalizedReleases.contains(normalized)) {
          distinctNormalizedReleases.add(normalized);
        }
      }

      if (latestFullTag == null || latestReleaseData == null) return;
      latestVersion = latestFullTag;

      final currentNorm = normalizeVersion(currentVersion);

      // 2. 맨 앞자리(Major) 버전 변경 확인
      final currentMajor = int.tryParse(currentNorm.split('.').first) ?? 5;
      final latestMajor = int.tryParse(distinctNormalizedReleases.first.split('.').first) ?? 5;
      final bool isMajorBehind = latestMajor > currentMajor;

      // 3. 지연 횟수(Lag) 계산 (현재 버전보다 높은 릴리즈 개수 카운트)
      int lagCount = 0;
      for (final rel in distinctNormalizedReleases) {
        if (_isNewerVersion(rel, currentNorm)) {
          lagCount++;
        }
      }

      debugPrint('[UpdateService] Current: $currentVersion ($currentNorm), Latest: $latestFullTag, Distinct Releases: $distinctNormalizedReleases, Lag: $lagCount, MajorBehind: $isMajorBehind');

      // 4. Cloud 차단 (3회 지연 시)
      if (lagCount >= 3 || isMajorBehind) {
        isCloudBlockedNotifier.value = true;
      } else {
        isCloudBlockedNotifier.value = false;
      }

      // 5. 앱 실행 차단 (Major 변경 또는 6회 지연 시)
      if (isMajorBehind || lagCount >= 6) {
        isBlockedNotifier.value = true;
        blockReason = isMajorBehind
            ? '주요 대규모 메이저 업데이트($latestMajor.x.x)가 배포되었습니다.'
            : '보안 기준(6차례 업데이트 지연)을 초과하여 현재 버전을 사용할 수 없습니다.';
        if (context.mounted) {
          showLockoutDialog(context);
        }
        return;
      }

      // 6. 정상 업데이트 다운로드 처리
      final assets = (latestReleaseData['assets'] as List<dynamic>? ?? []);
      String? apkDownloadUrl;
      int bestApkScore = 0;
      String? windowsDownloadUrl;
      int bestWindowsScore = 0;
      final isCloud = AppConfig.isCloudMode;

      for (final a in assets) {
        final name = (a['name'] as String? ?? '').trim();
        final url = a['browser_download_url'] as String?;
        if (url == null || url.isEmpty) continue;

        final winScore = getWindowsAssetScore(name, isCloud: isCloud);
        if (winScore > bestWindowsScore) {
          bestWindowsScore = winScore;
          windowsDownloadUrl = url;
        }

        final apkScore = getApkAssetScore(name, isCloud: isCloud);
        if (apkScore > bestApkScore) {
          bestApkScore = apkScore;
          apkDownloadUrl = url;
        }
      }

      apkDownloadUrl ??= isCloud
          ? 'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-cloud.apk'
          : 'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest.apk';
      windowsDownloadUrl ??= isCloud
          ? 'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-cloud.msix'
          : 'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-class.msix';

      if (_isNewerVersion(distinctNormalizedReleases.first, currentNorm)) {
        final isWindows = !kIsWeb && Platform.isWindows;
        final targetUrl = isWindows ? windowsDownloadUrl : apkDownloadUrl;
        unawaited(_startSilentDownload(targetUrl, latestFullTag, isWindows));
      }
    } catch (e) {
      debugPrint('[UpdateService] Update check failed: $e');
      _lastSilentCheckTime = null; // 부팅 시 네트워크 미연결로 인한 실패 시 쿨다운 리셋하여 재시도 허용
    } finally {
      _isChecking = false;
      if (stateNotifier.value == UpdateState.checking) {
        stateNotifier.value = UpdateState.idle;
      }
    }
  }

  static bool isNewerVersion(String target, String current) {
    final tClean = target.replaceFirst(RegExp(r'^[vV]'), '').trim();
    final cClean = current.replaceFirst(RegExp(r'^[vV]'), '').trim();

    final tParts = tClean.split('+');
    final cParts = cClean.split('+');

    final tSem = tParts.first.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final cSem = cParts.first.split('.').map((v) => int.tryParse(v) ?? 0).toList();

    final maxLen = tSem.length > cSem.length ? tSem.length : cSem.length;
    for (var i = 0; i < maxLen; i++) {
      final tv = i < tSem.length ? tSem[i] : 0;
      final cv = i < cSem.length ? cSem[i] : 0;
      if (tv != cv) return tv > cv;
    }

    if (tParts.length > 1 && cParts.length > 1) {
      final tb = int.tryParse(tParts[1].trim()) ?? 0;
      final cb = int.tryParse(cParts[1].trim()) ?? 0;
      if (tb != cb) return tb > cb;
    }

    return false;
  }

  static bool _isNewerVersion(String target, String current) => isNewerVersion(target, current);

  /// AppData/Updates 폴더에 백그라운드 다운로드
  static Future<void> _startSilentDownload(
    String downloadUrl,
    String version,
    bool isWindows,
  ) async {
    try {
      stateNotifier.value = UpdateState.downloading;
      downloadProgressNotifier.value = 0.0;

      final Directory updatesDir;
      if (!kIsWeb && Platform.isAndroid) {
        final cacheDir = await getTemporaryDirectory();
        updatesDir = Directory(p.join(cacheDir.path, 'Updates'));
      } else {
        final appSupport = await getApplicationSupportDirectory();
        updatesDir = Directory(p.join(appSupport.path, 'Updates'));
      }
      if (!updatesDir.existsSync()) {
        updatesDir.createSync(recursive: true);
      }

      final ext = extractExtensionFromUrl(downloadUrl, isWindows: isWindows);
      final prefix = AppConfig.isCloudMode ? 'boardest_cloud_update' : 'boardest_update';
      final fileName = '${prefix}_$version.$ext';
      final savePath = p.join(updatesDir.path, fileName);

      // 동일 버전의 다른 확장자 잔여 파일 정리 (.msix vs .appx 충돌 및 파일 손상 방지)
      final otherExt = ext == 'msix' ? 'appx' : (ext == 'appx' ? 'msix' : null);
      if (otherExt != null) {
        try {
          final conflictingFile = File(p.join(updatesDir.path, '${prefix}_$version.$otherExt'));
          if (conflictingFile.existsSync()) {
            conflictingFile.deleteSync();
            debugPrint('[UpdateService] 🧹 Removed conflicting alternate package: ${conflictingFile.path}');
          }
        } catch (_) {}
      }

      final existingFile = File(savePath);
      if (existingFile.existsSync() && existingFile.lengthSync() > 15 * 1024 * 1024) {
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
      debugPrint('[UpdateService] Update package downloaded: $savePath');
    } catch (e) {
      debugPrint('[UpdateService] Silent download failed: $e');
      stateNotifier.value = UpdateState.idle;
    }
  }

  /// 다운로드된 패키지 설치 실행 (윈도우: 윈도우 패키지 설치 관리자 호출, 앱 종료 안 함)
  static Future<void> executeInstall(BuildContext context) async {
    final savePath = downloadedPackagePath;
    stateNotifier.value = UpdateState.installing;

    if (savePath == null || !File(savePath).existsSync()) {
      stateNotifier.value = UpdateState.idle;
      // 다운로드된 파일이 없으면 바로 다운로드 사이트 열기
      await launchUrl(Uri.parse(downloadPage), mode: LaunchMode.externalApplication);
      return;
    }

    if (!kIsWeb && Platform.isAndroid) {
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
            '시스템 패키지 설치 프로그램이 실행됩니다.\n화면에 나타나는 [설치] 또는 [업데이트] 버튼을 눌러 설치를 완료해 주세요.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F5D4),
                foregroundColor: Colors.black,
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚀 최신 버전 자동 설치를 시작합니다. 잠시 후 새 버전으로 자동 재시작됩니다...'),
            backgroundColor: Color(0xFF00F5D4),
            duration: Duration(seconds: 6),
          ),
        );
      }

      if (savePath.toLowerCase().endsWith('.exe')) {
        try {
          await Process.start(
            savePath,
            ['--update'],
            mode: ProcessStartMode.detached,
          );
          exit(0);
        } catch (e) {
          debugPrint('[UpdateService] Failed to launch installer exe: $e');
        }
      }

      final pkgFilter = AppConfig.isCloudMode ? 'jiwho.boardest.cloud' : 'jiwho.boardest.bst';
      final escapedPath = savePath.replaceAll("'", "''");
      final psScript = "Start-Sleep -Milliseconds 600; "
          "try { "
          "Add-AppxPackage -Path '$escapedPath' -ForceApplicationShutdown -ErrorAction Stop; "
          "\$pkg = Get-AppxPackage -Name '*$pkgFilter*' | Sort-Object Version -Descending | Select-Object -First 1; "
          "if (\$pkg) { Start-Process 'explorer.exe' ('shell:AppsFolder\\' + \$pkg.PackageFamilyName + '!App') } "
          "} catch { "
          "Start-Process -FilePath 'explorer.exe' -ArgumentList ('\"' + '$escapedPath' + '\"'); "
          "}";

      try {
        await Process.start(
          'cmd.exe',
          [
            '/c',
            'start',
            '""',
            '/min',
            'powershell.exe',
            '-WindowStyle',
            'Hidden',
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            psScript,
          ],
          mode: ProcessStartMode.detached,
        );
      } catch (_) {
        try {
          await Process.start('powershell.exe', ['-Command', "Start-Process -FilePath '$escapedPath'"]);
        } catch (_) {
          await OpenFilex.open(savePath);
        }
      }
    }
  }

  /// 앱 삭제 (안드로이드 OS 패키지 제거 인텐트 / 윈도우 앱 및 기능 설정창 및 AppX 제거)
  static Future<void> uninstallApp([BuildContext? context]) async {
    if (context != null && context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161922),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFEF4565), width: 1.5),
          ),
          title: Row(
            children: const [
              Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4565), size: 26),
              SizedBox(width: 10),
              Text('앱 삭제 확인', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: const Text(
            '기기에서 Boardest 앱을 완전히 삭제(제거)하시겠습니까?\n삭제 후에는 필요 시 다운로드 사이트에서 다시 설치하셔야 합니다.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4565),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('삭제 진행', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.boardest/launch_args');
        await channel.invokeMethod('uninstallApp');
      } catch (_) {
        final pkg = AppConfig.isCloudMode ? 'jiwho.boardest.cloud' : 'jiwho.boardest.bst';
        try {
          await Process.run('am', ['start', '-a', 'android.intent.action.DELETE', '-d', 'package:$pkg']);
        } catch (_) {}
      }
    } else if (!kIsWeb && Platform.isWindows) {
      final pkgName = AppConfig.isCloudMode ? 'jiwho.boardest.cloud' : 'jiwho.boardest.bst';
      try {
        await Process.start('cmd.exe', ['/c', 'start', 'ms-settings:appsfeatures']);
      } catch (_) {
        try {
          await Process.start('control.exe', ['appwiz.cpl']);
        } catch (_) {}
      }
      try {
        await Process.start('powershell.exe', [
          '-WindowStyle',
          'Hidden',
          '-NoProfile',
          '-Command',
          'Start-Sleep -Seconds 1; Get-AppxPackage -Name "*$pkgName*" | Remove-AppxPackage',
        ]);
      } catch (_) {}
      exit(0);
    }
  }

  /// Cloud 기능 3회 지연 제한 안내 모달
  static void showCloudBlockedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141721),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFEF4565), width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.cloud_off_rounded, color: Color(0xFFEF4565), size: 26),
            SizedBox(width: 10),
            Text(
              'Cloud 기능 제한 안내',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Cloud 기능을 사용하시려면 업데이트를 하시기 바랍니다.',
          style: TextStyle(color: Colors.white, fontSize: 15, height: 1.5, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (downloadedPackagePath != null && File(downloadedPackagePath!).existsSync()) {
                await executeInstall(context);
              } else {
                await launchUrl(Uri.parse(downloadPage), mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.system_update_alt_rounded, color: Colors.black, size: 18),
            label: const Text('업데이트 설치', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// 보안 잠금 화면 (업데이트 다운 / 수동 설치 / 앱 런처 / 앱 삭제)
  static void showLockoutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 580,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF141721),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFEF4565), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4565).withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4565).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security_update_warning_rounded,
                    color: Color(0xFFEF4565),
                    size: 48,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '[업데이트 필수]',
                  style: GoogleFonts.notoSansKr(
                    color: const Color(0xFFEF4565),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '이 버전은 안전하지 않습니다.\n다운로드 버튼을 눌러 다운받고 새로운 버전을 다운받으세요.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (blockReason != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    blockReason!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 26),

                // 4대 필수 작업 버튼
                Column(
                  children: [
                    // 1. 업데이트 다운
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F5D4),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          if (downloadedPackagePath != null && File(downloadedPackagePath!).existsSync()) {
                            await executeInstall(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('⚡ 최신 버전을 다운로드하는 중입니다. 잠시만 기다려주세요...')),
                            );
                            await checkAndUpdate(context, force: true);
                            if (downloadedPackagePath != null && context.mounted) {
                              await executeInstall(context);
                            }
                          }
                        },
                        icon: const Icon(Icons.download_rounded, color: Colors.black),
                        label: Text(
                          '1. 업데이트 다운 및 설치',
                          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 2. 수동 설치
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF00BAF2)),
                          foregroundColor: const Color(0xFF00BAF2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          launchUrl(Uri.parse(downloadPage), mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.open_in_browser_rounded),
                        label: Text('2. 수동 설치 (다운로드 사이트 열기)', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 3. 앱 런처 (시스템 앱 실행 허용)
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF7F5AF0)),
                          foregroundColor: const Color(0xFF7F5AF0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          _showSystemAppsLauncherModal(context);
                        },
                        icon: const Icon(Icons.apps_rounded),
                        label: Text('3. 앱 런처 (기기 내 설치된 앱 실행)', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 4. 앱 삭제
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.withValues(alpha: 0.2),
                          foregroundColor: const Color(0xFFEF4565),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFEF4565)),
                          ),
                        ),
                        onPressed: () => uninstallApp(context),
                        icon: const Icon(Icons.delete_forever_rounded),
                        label: Text('4. 앱 삭제 (기기에서 제거)', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 기기 내 설치된 시스템 앱 런처 다이얼로그 (앱 차단 상태에서도 외부 앱 실행 가능)
  static void _showSystemAppsLauncherModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF161922),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 540,
          height: 520,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.apps_rounded, color: Color(0xFF00F5D4), size: 24),
                      SizedBox(width: 8),
                      Text('시스템 앱 런처', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '앱이 업데이트를 위해 잠긴 상태에서도 기기에 설치된 기본 앱들을 실행할 수 있습니다.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<List<ScannedApp>>(
                  future: SystemAppScanner.scanInstalledApps(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF00F5D4)));
                    }
                    final apps = snapshot.data ?? [];
                    if (apps.isEmpty) {
                      return const Center(
                        child: Text('실행 가능한 시스템 앱이 없습니다.', style: TextStyle(color: Colors.white38)),
                      );
                    }
                    return GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: apps.length,
                      itemBuilder: (context, index) {
                        final app = apps[index];
                        return InkWell(
                          onTap: () {
                            SystemAppScanner.launchApp(app.appId);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.touch_app_rounded, color: Color(0xFF00F5D4), size: 28),
                                const SizedBox(height: 8),
                                Text(
                                  app.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

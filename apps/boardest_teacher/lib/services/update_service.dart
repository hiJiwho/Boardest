import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, MethodChannel;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool hasUpdate;
  final bool isWindows;
  final bool isAndroid;
  final bool isBlocked;
  final bool isCloudBlocked;
  final int lagCount;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.hasUpdate,
    required this.isWindows,
    required this.isAndroid,
    this.isBlocked = false,
    this.isCloudBlocked = false,
    this.lagCount = 0,
  });
}

/// 교사용 앱 인앱 업데이트 안내, 보안 잠금 및 알람 서비스
/// 1. 최신 버전 확인 (4번째 자리 무시: 5.2.1.1과 5.2.1.2는 1개 업데이트로 간주)
/// 2. 버전보다 큰 버전 있으면 업데이트 알람만 제공 (누르면 사이트 열려 직접 다운로드)
/// 3. 맨 앞자리(Major) 변경 또는 6차례 업데이트 지연 시:
///    [업데이트 필수] "이 버전은 안전하지 않습니다. 새 버전의 msi 를 다운받아주시기 바랍니다. [다운로드 사이트 이동]" 팝업 표시 후 20초 뒤 자동 삭제/종료!
/// 4. 3차례 업데이트 지연 시 Cloud 기능 제한
class UpdateService {
  UpdateService._internal();
  static final instance = UpdateService._internal();

  static const String defaultVersion = '5.6.1';
  static const String defaultBuildNumber = '5610';
  static const String defaultFullVersion = '5.6.1+5610';
  static const String _releasesApi =
      'https://api.github.com/repos/hiJiwho/Boardest/releases?per_page=30';
  static const String downloadPage = 'https://boardest-downloads.web.app';
  static bool _checking = false;
  static DateTime? _lastSilentCheckTime;
  static String? _resolvedVersion;

  static final ValueNotifier<bool> isBlockedNotifier = ValueNotifier(false);
  static final ValueNotifier<bool> isCloudBlockedNotifier = ValueNotifier(false);
  static final ValueNotifier<bool> hasUpdateNotifier = ValueNotifier(false);

  static String get currentVersion {
    if (_resolvedVersion != null) return _resolvedVersion!;
    if (!kIsWeb && Platform.isWindows) {
      final match = RegExp(
        r'jiwho\.boardest\.(?:teacher|bst|class-lite|overlay-panser)_([0-9.]+)_',
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

    // 2) Compare PackageInfo and assets/version.json, picking the highest resolved version
    String? pkgVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      final b = info.buildNumber.trim();
      if (v.isNotEmpty) {
        pkgVersion = b.isNotEmpty ? '$v+$b' : v;
      }
    } catch (e) {
      debugPrint('[UpdateService] PackageInfo lookup error: $e');
    }

    String? assetVersion;
    for (final path in ['assets/version.json', 'version.json']) {
      try {
        final jsonStr = await rootBundle.loadString(path);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final v = (data['version'] as String?)?.trim();
        final b = (data['build_number'] ?? data['buildNumber'])?.toString().trim();
        if (v != null && v.isNotEmpty) {
          assetVersion = (b != null && b.isNotEmpty) ? '$v+$b' : v;
          break;
        }
      } catch (_) {}
    }

    if (pkgVersion != null && assetVersion != null) {
      _resolvedVersion = isNewerVersion(assetVersion, pkgVersion) ? assetVersion : pkgVersion;
      if (isNewerVersion(defaultFullVersion, _resolvedVersion!)) {
        _resolvedVersion = defaultFullVersion;
      }
      debugPrint('[UpdateService] Resolved version (pkg vs asset): $_resolvedVersion');
      return;
    } else if (pkgVersion != null) {
      _resolvedVersion = isNewerVersion(defaultFullVersion, pkgVersion) ? defaultFullVersion : pkgVersion;
      return;
    } else if (assetVersion != null) {
      _resolvedVersion = isNewerVersion(defaultFullVersion, assetVersion) ? defaultFullVersion : assetVersion;
      return;
    }

    // 3) Try Windows MSIX executable path regex
    if (!kIsWeb && Platform.isWindows) {
      final match = RegExp(
        r'jiwho\.boardest\.(?:teacher|bst|class-lite|overlay-panser)_([0-9.]+)_',
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

    // 4) Cache fallback
    _resolvedVersion = defaultFullVersion;
  }

  /// 이전 다운로드된 임시 설치 파일 자동 삭제
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
            final isInstaller = ext == '.appx' || ext == '.msix' || ext == '.apk' || ext == '.exe' || ext == '.msi';
            final isLegacyTemp = base.startsWith('boardest_') || base.startsWith('bst_');
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

  /// 4번째 자리를 제거하고 앞 3자리만 반환 (빌드 번호 및 v 접두사 제거)
  static String normalizeVersion(String v) {
    final clean = v.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.trim();
    final parts = clean.split('.');
    if (parts.length >= 3) {
      return '${parts[0]}.${parts[1]}.${parts[2]}';
    }
    return clean;
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

  static bool _isNewer(String target, String current) => isNewerVersion(target, current);

  /// 앱 삭제 (안드로이드 OS 제거 / 윈도우 앱 및 기능 설정 실행)
  static Future<void> uninstallApp([BuildContext? context]) async {
    if (context != null && context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
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
            '기기에서 Boardest Teacher 앱을 완전히 삭제(제거)하시겠습니까?\n삭제 후에는 필요 시 다운로드 사이트에서 다시 설치하셔야 합니다.',
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
        try {
          await Process.run('am', ['start', '-a', 'android.intent.action.DELETE', '-d', 'package:jiwho.boardest.teacher']);
        } catch (_) {}
      }
    } else if (!kIsWeb && Platform.isWindows) {
      try {
        await Process.start('cmd.exe', ['/c', 'start', 'ms-settings:appsfeatures']);
      } catch (_) {
        try {
          await Process.start('control.exe', ['appwiz.cpl']);
        } catch (_) {}
      }
      exit(0);
    }
  }

  Future<UpdateInfo?> checkForUpdate({
    bool force = false,
    String channel = 'stable',
  }) async {
    if (kIsWeb || _checking) return null;
    if (!force &&
        _lastSilentCheckTime != null &&
        DateTime.now().difference(_lastSilentCheckTime!) <
            const Duration(minutes: 5)) {
      return null;
    }

    await initVersion();
    await cleanupOldUpdates();

    _checking = true;
    _lastSilentCheckTime = DateTime.now();

    try {
      final response = await http.get(Uri.parse(_releasesApi), headers: {
        'User-Agent': 'Boardest-Teacher/$currentVersion',
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final releases = jsonDecode(response.body) as List<dynamic>;
      if (releases.isEmpty) return null;

      // 4번째 자리를 무시한 유니크 릴리즈 목록 구성 및 [Must update] 강제 락다운 감지
      final List<String> distinctNormalized = [];
      String? latestFullTag;
      Map<String, dynamic>? latestReleaseData;
      bool hasMustUpdateAhead = false;

      final currentNorm = normalizeVersion(currentVersion);

      for (final r in releases) {
        final tag = (r['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '').trim();
        if (tag.isEmpty) continue;
        if (latestFullTag == null || _isNewer(normalizeVersion(tag), normalizeVersion(latestFullTag))) {
          latestFullTag = tag;
          latestReleaseData = r as Map<String, dynamic>;
        }

        final norm = normalizeVersion(tag);
        if (!distinctNormalized.contains(norm)) {
          distinctNormalized.add(norm);
        }

        // [Must update] 키워드가 본인 버전보다 상위(최신) 릴리즈 제목/본문에 포함되어 있는지 검사
        if (_isNewer(norm, currentNorm)) {
          final relName = (r['name'] as String? ?? '').toLowerCase();
          final relBody = (r['body'] as String? ?? '').toLowerCase();
          if (relName.contains('[must update]') || relBody.contains('[must update]')) {
            hasMustUpdateAhead = true;
          }
        }
      }

      if (latestFullTag == null || latestReleaseData == null) return null;

      distinctNormalized.sort((a, b) => _isNewer(a, b) ? -1 : (_isNewer(b, a) ? 1 : 0));

      // 메이저 버전 변경 판별
      final currentMajor = int.tryParse(currentNorm.split('.').first) ?? 5;
      final latestMajor = int.tryParse(distinctNormalized.first.split('.').first) ?? 5;
      final bool isMajorBehind = latestMajor > currentMajor;

      // 지연 횟수(Lag) 계산
      int lagCount = 0;
      for (final rel in distinctNormalized) {
        if (_isNewer(rel, currentNorm)) {
          lagCount++;
        }
      }

      final isBlocked = isMajorBehind || lagCount >= 6 || hasMustUpdateAhead;
      final isCloudBlocked = lagCount >= 3 || isMajorBehind || hasMustUpdateAhead;

      isBlockedNotifier.value = isBlocked;
      isCloudBlockedNotifier.value = isCloudBlocked;

      final isWindows = !kIsWeb && Platform.isWindows;
      final isAndroid = !kIsWeb && Platform.isAndroid;

      final assets = (latestReleaseData['assets'] as List<dynamic>? ?? []);
      String? installerUrl;
      String? msiUrl;
      String? apkUrl;

      for (final a in assets) {
        final name = (a['name'] as String? ?? '').trim().toLowerCase();
        final url = a['browser_download_url'] as String?;
        if (url == null || url.isEmpty) continue;

        if (name.contains('teacher') && (name.endsWith('-installer.exe') || name.endsWith('setup.exe') || (name.endsWith('.exe') && !name.contains('windows')))) {
          installerUrl ??= url;
        } else if (name.contains('teacher') && name.endsWith('.msi')) {
          msiUrl ??= url;
        } else if (name.contains('teacher') && name.endsWith('.apk')) {
          apkUrl ??= url;
        }
      }

      final selectedWindowsUrl = installerUrl ?? msiUrl ?? 'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-teacher.exe';
      final selectedApkUrl = apkUrl ?? 'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-teacher-lite.apk';

      final hasUpdate = _isNewer(distinctNormalized.first, currentNorm);
      hasUpdateNotifier.value = hasUpdate;

      return UpdateInfo(
        latestVersion: latestFullTag,
        currentVersion: currentVersion,
        downloadUrl: isWindows ? selectedWindowsUrl : selectedApkUrl,
        releaseNotes: (latestReleaseData['body'] as String? ?? '').trim(),
        hasUpdate: hasUpdate,
        isWindows: isWindows,
        isAndroid: isAndroid,
        isBlocked: isBlocked,
        isCloudBlocked: isCloudBlocked,
        lagCount: lagCount,
      );
    } catch (e) {
      debugPrint('[UpdateService] Update check failed: $e');
      return null;
    } finally {
      _checking = false;
    }
  }

  /// 사이드바 및 설정 창에서 즉시 업데이트 확인 및 피드백 UI 표시
  Future<void> checkAndPromptUpdate(BuildContext context, {bool force = false}) async {
    final info = await checkForUpdate(force: force);
    if (!context.mounted) return;
    if (info != null && (info.hasUpdate || info.isBlocked)) {
      showUpdateDialog(context, info);
    } else if (force) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('현재 최신 버전(v${normalizeVersion(currentVersion)})을 사용 중입니다.'),
          backgroundColor: const Color(0xFF00B4D8),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 온라인 인스톨러(.exe / .msi) 또는 APK를 자동 다운로드하여 즉시 실행합니다.
  static Future<bool> downloadAndLaunchInstaller(
    UpdateInfo info, {
    void Function(String status)? onStatus,
  }) async {
    if (kIsWeb) {
      await launchUrl(Uri.parse(downloadPage), mode: LaunchMode.externalApplication);
      return true;
    }
    try {
      onStatus?.call('최신 설치 관리자 다운로드 중...');
      final tempDir = await getTemporaryDirectory();
      final url = info.downloadUrl.isNotEmpty
          ? info.downloadUrl
          : 'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-teacher.exe';
      final ext = url.toLowerCase().endsWith('.msi')
          ? '.msi'
          : (url.toLowerCase().endsWith('.apk') ? '.apk' : '.exe');
      final targetPath = p.join(tempDir.path, 'boardest-teacher-updater$ext');

      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        final file = File(targetPath);
        await file.writeAsBytes(res.bodyBytes, flush: true);
        onStatus?.call('설치 관리자 실행 중...');
        if (Platform.isWindows) {
          if (ext == '.msi') {
            await Process.start('msiexec.exe', ['/i', file.path], mode: ProcessStartMode.detached);
          } else {
            await Process.start(file.path, [], mode: ProcessStartMode.detached);
          }
          await Future.delayed(const Duration(milliseconds: 500));
          exit(0);
        } else {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          return true;
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] Auto installer launch failed: $e');
    }
    await launchUrl(Uri.parse(downloadPage), mode: LaunchMode.externalApplication);
    return false;
  }

  /// Cloud 기능 3회 지연 제한 안내 모달
  static void showCloudBlockedDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
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
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(downloadPage), mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.download_rounded, color: Colors.black, size: 18),
            label: const Text('다운로드 사이트 이동', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// 교사용 앱 업데이트 다이얼로그 노출
  /// - 차단 상태(isBlocked): 자동 업데이트 실행 지원 모달 렌더링
  /// - 일반 업데이트 상태: 자동 업데이트 및 다운로드 사이트 이동 모달
  void showUpdateDialog(BuildContext context, UpdateInfo info) {
    if (!context.mounted) return;
    if (info.isBlocked) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.8),
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: _TeacherMandatoryLockoutDialog(info: info),
        ),
      );
    } else {
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.65),
        builder: (dialogContext) => PopScope(
          canPop: true,
          child: _TeacherOptionalUpdateDialog(info: info),
        ),
      );
    }
  }
}

/// 필수 업데이트 잠금 다이얼로그 (원클릭 자동 인스톨러 실행 지원)
class _TeacherMandatoryLockoutDialog extends StatefulWidget {
  final UpdateInfo info;
  const _TeacherMandatoryLockoutDialog({required this.info});

  @override
  State<_TeacherMandatoryLockoutDialog> createState() =>
      _TeacherMandatoryLockoutDialogState();
}

class _TeacherMandatoryLockoutDialogState
    extends State<_TeacherMandatoryLockoutDialog> {
  int _secondsLeft = 20;
  Timer? _timer;
  bool _isUpdating = false;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted || _isUpdating) return;
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
        }
      });
      if (_secondsLeft <= 0) {
        t.cancel();
        _triggerAutoUpdate();
      }
    });
  }

  Future<void> _triggerAutoUpdate() async {
    if (_isUpdating) return;
    setState(() {
      _isUpdating = true;
      _statusText = '최신 인스톨러 다운로드 중...';
    });
    await UpdateService.downloadAndLaunchInstaller(
      widget.info,
      onStatus: (s) {
        if (mounted) setState(() => _statusText = s);
      },
    );
    if (mounted) {
      setState(() => _isUpdating = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFEF4565), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4565).withOpacity(0.3),
              blurRadius: 40,
              spreadRadius: 6,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4565).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.system_update_alt_rounded,
                color: Color(0xFFEF4565),
                size: 46,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '[필수 업데이트 안내 · v${widget.info.latestVersion}]',
              style: GoogleFonts.notoSansKr(
                color: const Color(0xFFEF4565),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isUpdating
                  ? _statusText
                  : '필수 업데이트(v${widget.info.latestVersion})가 감지되었습니다.\n아래 버튼을 누르면 자동으로 최신 설치 관리자를 실행하여 업데이트합니다.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isUpdating)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F5D4)),
                    )
                  else
                    const Icon(Icons.timer_outlined, color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _isUpdating
                        ? '업데이트 설치 관리자를 준비하고 있습니다...'
                        : '$_secondsLeft초 뒤 자동으로 업데이트 설치 관리자가 실행됩니다.',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.orangeAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F5D4),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isUpdating ? null : _triggerAutoUpdate,
                    icon: const Icon(Icons.rocket_launch_rounded, color: Colors.black),
                    label: Text(
                      '지금 자동 업데이트 실행',
                      style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    launchUrl(Uri.parse(UpdateService.downloadPage), mode: LaunchMode.externalApplication);
                  },
                  child: const Text('웹사이트'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 일반적인 업데이트 알람 대화상자 (원클릭 자동 인스톨러 실행 지원)
class _TeacherOptionalUpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _TeacherOptionalUpdateDialog({required this.info});

  @override
  State<_TeacherOptionalUpdateDialog> createState() => _TeacherOptionalUpdateDialogState();
}

class _TeacherOptionalUpdateDialogState extends State<_TeacherOptionalUpdateDialog> {
  bool _isUpdating = false;
  String _statusText = '';

  Future<void> _startUpdate() async {
    if (_isUpdating) return;
    setState(() {
      _isUpdating = true;
      _statusText = '설치 관리자 다운로드 중...';
    });
    await UpdateService.downloadAndLaunchInstaller(
      widget.info,
      onStatus: (s) {
        if (mounted) setState(() => _statusText = s);
      },
    );
    if (mounted) setState(() => _isUpdating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00F5D4).withOpacity(0.12),
              blurRadius: 36,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.system_update_rounded, color: Color(0xFF00F5D4), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '새 버전 출시 알림',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '현재 버전: v${widget.info.currentVersion} ➔ 최신 버전: v${widget.info.latestVersion}',
                        style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              _isUpdating
                  ? _statusText
                  : '새 버전(v${widget.info.latestVersion})이 준비되었습니다.\n"지금 자동 업데이트"를 누르면 설치 관리자가 자동으로 실행됩니다.',
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isUpdating ? null : () => Navigator.pop(context),
                  child: const Text('나중에', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    launchUrl(Uri.parse(UpdateService.downloadPage), mode: LaunchMode.externalApplication);
                  },
                  child: const Text('웹사이트 이동', style: TextStyle(color: Color(0xFF00F5D4))),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isUpdating ? null : _startUpdate,
                  icon: _isUpdating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.download_rounded, color: Colors.black, size: 18),
                  label: Text('지금 자동 업데이트', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

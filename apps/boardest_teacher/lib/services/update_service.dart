import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, MethodChannel;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
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

  static const String defaultVersion = '5.4.1';
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
    try {
      final jsonStr = await rootBundle.loadString('version.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final v = data['version'] as String?;
      if (v != null && v.isNotEmpty) {
        _resolvedVersion = v.trim();
      }
    } catch (_) {}
  }

  /// 4번째 자리를 제거하고 앞 3자리만 반환
  static String normalizeVersion(String v) {
    final clean = v.replaceFirst(RegExp(r'^v'), '').trim();
    final parts = clean.split('.');
    if (parts.length >= 3) {
      return '${parts[0]}.${parts[1]}.${parts[2]}';
    }
    return clean;
  }

  static bool _isNewer(String target, String current) {
    final t = target.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final c = current.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    for (var i = 0; i < (t.length > c.length ? t.length : c.length); i++) {
      final tv = i < t.length ? t[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (tv != cv) return tv > cv;
    }
    return false;
  }

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

      // 4번째 자리를 무시한 유니크 릴리즈 목록 구성
      final List<String> distinctNormalized = [];
      String? latestFullTag;
      Map<String, dynamic>? latestReleaseData;

      for (final r in releases) {
        final tag = (r['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '').trim();
        if (tag.isEmpty) continue;
        latestFullTag ??= tag;
        latestReleaseData ??= r as Map<String, dynamic>;

        final norm = normalizeVersion(tag);
        if (!distinctNormalized.contains(norm)) {
          distinctNormalized.add(norm);
        }
      }

      if (latestFullTag == null || latestReleaseData == null) return null;

      final currentNorm = normalizeVersion(currentVersion);

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

      final isBlocked = isMajorBehind || lagCount >= 6;
      final isCloudBlocked = lagCount >= 3 || isMajorBehind;

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

      installerUrl ??= 'https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-teacher-installer.exe';
      msiUrl ??= 'https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher.msi';
      apkUrl ??= 'https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher.apk';

      final hasUpdate = _isNewer(distinctNormalized.first, currentNorm);
      hasUpdateNotifier.value = hasUpdate;

      return UpdateInfo(
        latestVersion: latestFullTag,
        currentVersion: currentVersion,
        downloadUrl: isWindows ? (installerUrl ?? msiUrl) : apkUrl,
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
  /// - 차단 상태(isBlocked): 20초 카운트다운 후 앱 삭제/종료 모달 강제 렌더링
  /// - 일반 업데이트 상태: 다운로드 사이트 이동 버튼이 포함된 안내 모달
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

/// 6차례 지연 또는 메이저 버전 변경 시 20초 카운트다운 후 자동 삭제/종료 강제 잠금 다이얼로그
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

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
        }
      });
      if (_secondsLeft <= 0) {
        t.cancel();
        // 20초 만료 시 앱 삭제 실행 후 종료!
        await UpdateService.uninstallApp(context);
        exit(0);
      }
    });
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
                Icons.warning_amber_rounded,
                color: Color(0xFFEF4565),
                size: 46,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '[업데이트 필수]',
              style: GoogleFonts.notoSansKr(
                color: const Color(0xFFEF4565),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '업데이트가 감지되었습니다.\n이 앱을 설치했던 installer 를 열어서 업데이트 해주세요.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '$_secondsLeft초 뒤 앱이 종료 및 삭제됩니다.',
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
                    onPressed: () {
                      launchUrl(Uri.parse(UpdateService.downloadPage), mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.open_in_browser_rounded, color: Colors.black),
                    label: Text(
                      '다운로드 사이트 이동',
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
                  onPressed: () async {
                    await UpdateService.uninstallApp(context);
                    exit(0);
                  },
                  child: const Text('지금 삭제'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 일반적인 업데이트 알람 대화상자 (사용자가 직접 수동 다운로드 사이트로 이동)
class _TeacherOptionalUpdateDialog extends StatelessWidget {
  final UpdateInfo info;
  const _TeacherOptionalUpdateDialog({required this.info});

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
                        '현재 버전: v${info.currentVersion} ➔ 최신 버전: v${info.latestVersion}',
                        style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              '업데이트가 감지되었습니다. 이 앱을 설치했던 installer 를 열어서 업데이트 해주세요.\n(웹 사이트 이동 버튼을 누르면 최신 설치 관리자를 다시 다운로드하실 수도 있습니다.)',
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('나중에', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    launchUrl(Uri.parse(UpdateService.downloadPage), mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.download_rounded, color: Colors.black, size: 18),
                  label: Text('다운로드 사이트 이동', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

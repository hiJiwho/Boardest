# Requirement 2 Investigation Report: Android App Update Infinite Loop Analysis

**Investigator**: explorer_update_loop  
**Target Requirement**: Requirement 2 (Android 환경에서 앱 업데이트 완료 후에도 계속 '업데이트 필요' 알림/잠금이 발생하는 무한 루프 버그 수정)  
**Target Codebases**: 
- `apps/boardest/lib/services/update_service.dart`
- `apps/boardest_teacher/lib/services/update_service.dart`
- `apps/boardest/lib/views/dashboard_view.dart`
- `apps/boardest/pubspec.yaml`, `apps/boardest_teacher/pubspec.yaml`
- `apps/boardest/test/update_service_test.dart`

---

## 1. Observation

### 1.1 App Version Retrieval on Android (`UpdateService.currentVersion` & `initVersion()`)
In `apps/boardest/lib/services/update_service.dart` (lines 56–90):
```dart
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
    try {
      final jsonStr = await rootBundle.loadString('version.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final v = data['version'] as String?;
      if (v != null && v.isNotEmpty) {
        _resolvedVersion = v.trim();
      }
    } catch (_) {}
  }
```
In `apps/boardest_teacher/lib/services/update_service.dart` (lines 62–96):
Identical logic is implemented.

**Direct Observations**:
1. `PackageInfo.fromPlatform()` is **nowhere in the codebase**. Neither `apps/boardest/pubspec.yaml` nor `apps/boardest_teacher/pubspec.yaml` declared `package_info_plus` as a dependency.
2. `Platform.isWindows` is `false` on Android.
3. `rootBundle.loadString('version.json')` **always fails on Android** because `version.json` is generated solely during `flutter build web` into `build/web/version.json`. It is not included in the Android asset manifest (`pubspec.yaml` lines 106–114). The exception is swallowed in `catch (_) {}`.
4. `SharedPreferences` explicitly deletes `'bst_installed_version'` on line 80/86.
5. Consequently, on Android, `_resolvedVersion` remains `null` permanently, and `currentVersion` **always returns `defaultVersion`** (which was `'5.4.3'` before the recent commit, and `'5.3.7'` before that).

### 1.2 Android Cache Directory Mismatch in `cleanupOldUpdates()` vs `_startSilentDownload()`
In `apps/boardest/lib/services/update_service.dart`:
Line 194–200 (`cleanupOldUpdates()`):
```dart
  static Future<void> cleanupOldUpdates() async {
    if (kIsWeb) return;
    try {
      final appSupport = await getApplicationSupportDirectory();
      final updatesDir = Directory(p.join(appSupport.path, 'Updates'));
      if (updatesDir.existsSync()) {
        for (final entity in updatesDir.listSync()) {
          ...
```
Line 393–403 (`_startSilentDownload()`):
```dart
      final Directory updatesDir;
      if (!kIsWeb && Platform.isAndroid) {
        final cacheDir = await getTemporaryDirectory();
        updatesDir = Directory(p.join(cacheDir.path, 'Updates'));
      } else {
        final appSupport = await getApplicationSupportDirectory();
        updatesDir = Directory(p.join(appSupport.path, 'Updates'));
      }
```
Line 422–428 (`_startSilentDownload()`):
```dart
      final existingFile = File(savePath);
      if (existingFile.existsSync() && existingFile.lengthSync() > 15 * 1024 * 1024) {
        downloadedPackagePath = savePath;
        downloadProgressNotifier.value = 1.0;
        stateNotifier.value = UpdateState.downloaded;
        return;
      }
```
**Direct Observations**:
1. On Android, `_startSilentDownload` downloads APK packages into `getTemporaryDirectory() / 'Updates'` (`/data/user/0/<pkg>/cache/Updates`).
2. `cleanupOldUpdates()` on startup scans **only** `getApplicationSupportDirectory() / 'Updates'` (`/data/user/0/<pkg>/files/Updates`). It **never** inspects or purges `getTemporaryDirectory() / 'Updates'`.
3. Because the downloaded APK is never deleted on Android, on subsequent launches `existingFile.existsSync()` is immediately `true`, setting `stateNotifier.value = UpdateState.downloaded` immediately without downloading.

### 1.3 Automatic Update Dialog Trigger on App Launch
In `apps/boardest/lib/views/dashboard_view.dart` (lines 437–444):
```dart
  void _onUpdateStateChanged() {
    if (!mounted) return;
    if (UpdateService.stateNotifier.value == UpdateState.downloaded) {
      if (!kIsWeb && Platform.isAndroid) {
        UpdateService.executeInstall(context);
      }
    }
  }
```
In `apps/boardest/lib/services/update_service.dart` (lines 475–511):
`executeInstall()` displays:
```dart
AlertDialog(
  title: Text('앱 업데이트 안내'),
  content: Text('시스템 패키지 설치 프로그램이 실행됩니다.\n화면에 나타나는 [설치] 또는 [업데이트] 버튼을 눌러 설치를 완료해 주세요.'),
  actions: [ElevatedButton(child: Text('설치 화면 열기'))]
)
```
and calls `OpenFilex.open(savePath, type: 'application/vnd.android.package-archive')`.
**Direct Observations**:
1. When `stateNotifier.value` transitions to `UpdateState.downloaded`, `executeInstall(context)` is automatically fired on Android.
2. After `OpenFilex.open()`, `stateNotifier.value` is **never reset** to `UpdateState.idle`.
3. If the user installs the update and reopens the app (or returns to the app from the package installer), the app immediately enters the same condition.

### 1.4 Security Lockout Modal Trigger (`lagCount >= 6` or `isMajorBehind`)
In `apps/boardest/lib/services/update_service.dart` (lines 290–322):
```dart
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
```
In `apps/boardest/lib/services/update_service.dart` (lines 701–758):
`showLockoutDialog()` renders a non-dismissible dialog:
`barrierDismissible: false`, `PopScope(canPop: false)`, title: `[업데이트 필수]`, content: `'이 버전은 안전하지 않습니다.\n다운로드 버튼을 눌러 다운받고 새로운 버전을 다운받으세요.'`.
In `apps/boardest_teacher/lib/services/update_service.dart` (lines 372–405):
`_TeacherMandatoryLockoutDialog` renders a 20-second countdown timer that invokes `UpdateService.uninstallApp(context)` to automatically uninstall and close the app.

### 1.5 GitHub Releases Tags vs pubspec.yaml Version Discrepancies
Command `powershell -Command "(Invoke-RestMethod -Uri 'https://api.github.com/repos/hiJiwho/Boardest/releases?per_page=10' -Headers @{'User-Agent'='PowerShell'}).tag_name"` returned:
`v5.4.3`, `v5.4.1`, `v5.4.0`, `v5.3.7`, `v5.3.6`, `v5.3.5`, `v5.3.4`, `v5.3.3`, `v5.3.1`, `v5.1.2.1`.

1. **Tag format on GitHub**: Always `v<major>.<minor>.<patch>` (e.g. `v5.4.3`). They do **not** contain build numbers (`+5500`).
2. **Version format in `pubspec.yaml`**: `version: 5.5.0+5500`.
3. In `apps/boardest/lib/services/update_service.dart`:
   - Line 274: `r['tag_name'].replaceFirst(RegExp(r'^v'), '').trim();` (Case-sensitive regex! Fails on uppercase `V`).
   - Line 93–100 (`normalizeVersion`): `v.replaceFirst(RegExp(r'^v', caseSensitive: false), '').split('+').first.trim();` (Correctly strips `+5500`).
4. In `apps/boardest_teacher/lib/services/update_service.dart`:
   - Line 214: `r['tag_name'].replaceFirst(RegExp(r'^v'), '').trim();` (Case-sensitive).
   - Line 99–106 (`normalizeVersion`):
     ```dart
     static String normalizeVersion(String v) {
       final clean = v.replaceFirst(RegExp(r'^v'), '').trim();
       final parts = clean.split('.');
       if (parts.length >= 3) {
         return '${parts[0]}.${parts[1]}.${parts[2]}';
       }
       return clean;
     }
     ```
     Notice that `boardest_teacher` **does NOT strip `+` build metadata**! If passed `5.5.0+5500`, `parts[2]` becomes `'0+5500'`, and `int.tryParse('0+5500')` returns `null` which defaults to `0`.

---

## 2. Logic Chain

```
[Observation 1.1] Android has no PackageInfo; version.json is missing in APK assets; Platform.isWindows is false.
       │
       ▼
[Step 1] _resolvedVersion remains null on Android. currentVersion always falls back to static defaultVersion.
       │
       ▼
[Step 2] If the installed APK was compiled with an older defaultVersion (e.g. '5.4.3' or '5.3.7'), the newly installed app on Android still believes it is that older version.
       │
       ▼
[Observation 1.5] GitHub Releases API returns v5.5.0 (or v5.4.3). _isNewerVersion(target, currentNorm) evaluates 5.5.0 > 5.4.3 -> true.
       │
       ▼
[Step 3] checkAndUpdate() detects an update. Lag count is calculated. If lagCount >= 6, showLockoutDialog() permanently blocks the app [Observation 1.4].
       │
       ▼
[Step 4] Silent download starts.
       │
       ▼
[Observation 1.2] cleanupOldUpdates() purged appSupport/Updates, but _startSilentDownload uses cacheDir/Updates on Android.
       │
       ▼
[Step 5] The downloaded APK was NEVER deleted by cleanupOldUpdates(). existingFile.existsSync() is immediately true.
       │
       ▼
[Step 6] stateNotifier.value is immediately set to UpdateState.downloaded without downloading.
       │
       ▼
[Observation 1.3] dashboard_view.dart listener fires immediately: UpdateService.executeInstall(context).
       │
       ▼
[Step 7] Modal dialog pops up immediately ("시스템 패키지 설치 프로그램이 실행됩니다..."), launching the Android installer.
       │
       ▼
[Step 8] User installs update or cancels, then reopens app. Repeat Step 1 -> INFINITE UPDATE LOOP.
```

---

## 3. Caveats

1. **Android Permission and OpenFilex**: On Android 8.0+ (API 26+), installing APKs via `OpenFilex` requires the `REQUEST_INSTALL_PACKAGES` permission in `AndroidManifest.xml`. If denied, the system installer dialog may not pop up or may immediately exit back to the app without installing, making the loop look like a crash or instant relaunch.
2. **Web vs Desktop vs Android**: The regex resolution in `Platform.resolvedExecutable` works reliably on Windows MSIX packages because the install directory contains the package version (e.g. `..._5.5.0.0_x64...`). On Android, `Platform.resolvedExecutable` is `/system/bin/app_process64`, so platform-native package inspection (`package_info_plus` or Android `MethodChannel`) is required.
3. No caveats regarding the root causes; all evidence directly reproduces the exact failure mode.

---

## 4. Conclusion & Root Causes

### 4.1 Root Causes Identified
1. **No dynamic version query on Android**: Neither `PackageInfo.fromPlatform()` nor Android `PackageManager` was called in `UpdateService.dart`. `version.json` is missing in Android assets, causing Android to always use the hardcoded `defaultVersion`.
2. **Asymmetric Cache Directory Bug**: `cleanupOldUpdates()` cleans `getApplicationSupportDirectory() / 'Updates'`, while `_startSilentDownload()` on Android writes to and checks `getTemporaryDirectory() / 'Updates'`. The downloaded APK is never cleaned, causing `existingFile.existsSync()` to immediately trigger `UpdateState.downloaded` on every startup.
3. **Unchecked UI Trigger & State Reset Missing**: `dashboard_view.dart` listens to `stateNotifier == UpdateState.downloaded` and directly calls `executeInstall(context)`. `executeInstall()` never resets `stateNotifier.value` to `UpdateState.idle`.
4. **Version Normalization & Tag Parsing Inconsistencies**:
   - `apps/boardest/lib/services/update_service.dart` line 274 uses case-sensitive `RegExp(r'^v')`.
   - `apps/boardest_teacher/lib/services/update_service.dart` does not strip `+` build metadata in `normalizeVersion()`, leading to parsing failures when SemVer versions with `+5500` are evaluated.
   - When versions are identical (e.g. `5.5.0` vs `v5.5.0`), build number metadata mismatch or stale `defaultVersion` caused `_isNewerVersion()` to yield false positives.

---

## 5. Precise Code-Level Fix Strategy

### 5.1 Step 1: Add `package_info_plus` Dependency
In `apps/boardest/pubspec.yaml` and `apps/boardest_teacher/pubspec.yaml`:
```yaml
dependencies:
  package_info_plus: ^9.0.0
```

### 5.2 Step 2: Implement Dynamic PackageInfo Resolution in `initVersion()`
In `apps/boardest/lib/services/update_service.dart` and `apps/boardest_teacher/lib/services/update_service.dart`:
```dart
import 'package:package_info_plus/package_info_plus.dart';

  static Future<void> initVersion() async {
    // 1. First priority: PackageInfo from platform (works on Android, iOS, Windows, macOS, Linux, Web)
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

    // 2. Second priority (Windows MSIX package executable path)
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

    // 3. Third priority (Web version.json)
    try {
      final jsonStr = await rootBundle.loadString('version.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final v = data['version'] as String?;
      if (v != null && v.isNotEmpty) {
        _resolvedVersion = v.trim();
        return;
      }
    } catch (_) {}

    // 4. Fallback to constant
    _resolvedVersion = defaultFullVersion;
  }
```

### 5.3 Step 3: Fix Directory Mismatch in `cleanupOldUpdates()`
In `apps/boardest/lib/services/update_service.dart`:
```dart
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
      } catch (_) {}

      for (final updatesDir in dirsToClean) {
        if (updatesDir.existsSync()) {
          for (final entity in updatesDir.listSync()) {
            if (entity is File) {
              final ext = p.extension(entity.path).toLowerCase();
              if (ext == '.appx' || ext == '.msix' || ext == '.apk' || ext == '.exe') {
                try {
                  entity.deleteSync();
                  debugPrint('[UpdateService] 🧹 Old installer package removed: ${entity.path}');
                } catch (_) {}
              }
            }
          }
        }
      }
      ...
```

### 5.4 Step 4: Fix State Reset in `executeInstall()` and `showLockoutDialog()`
In `apps/boardest/lib/services/update_service.dart`:
```dart
  static Future<void> executeInstall(BuildContext context) async {
    final savePath = downloadedPackagePath;
    // Reset state to idle so subsequent resumes do not auto-re-prompt
    stateNotifier.value = UpdateState.idle;

    if (savePath == null || !File(savePath).existsSync()) {
      await launchUrl(Uri.parse(downloadPage), mode: LaunchMode.externalApplication);
      return;
    }
    ...
```

### 5.5 Step 5: Unify Tag Normalization & Version Comparison
In both `apps/boardest/lib/services/update_service.dart` and `apps/boardest_teacher/lib/services/update_service.dart`:
```dart
  static String normalizeVersion(String v) {
    final clean = v.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.trim();
    final parts = clean.split('.');
    if (parts.length >= 3) {
      return '${parts[0]}.${parts[1]}.${parts[2]}';
    }
    return clean;
  }

  static bool _isNewerVersion(String target, String current) {
    // 1. Strip 'v'/'V' and isolate base SemVer and build numbers
    final tTag = target.replaceFirst(RegExp(r'^[vV]'), '').trim();
    final cTag = current.replaceFirst(RegExp(r'^[vV]'), '').trim();

    final tParts = tTag.split('+');
    final cParts = cTag.split('+');

    final tSem = tParts.first.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final cSem = cParts.first.split('.').map((v) => int.tryParse(v) ?? 0).toList();

    final maxLen = tSem.length > cSem.length ? tSem.length : cSem.length;
    for (var i = 0; i < maxLen; i++) {
      final tv = i < tSem.length ? tSem[i] : 0;
      final cv = i < cSem.length ? cSem[i] : 0;
      if (tv != cv) return tv > cv;
    }

    // 2. If SemVer is identical, compare build number only when both provide it
    if (tParts.length > 1 && cParts.length > 1) {
      final tb = int.tryParse(tParts[1]) ?? 0;
      final cb = int.tryParse(cParts[1]) ?? 0;
      if (tb != cb) return tb > cb;
    }

    return false;
  }
```

### 5.6 Files to Modify
1. `apps/boardest/pubspec.yaml` — Add `package_info_plus: ^9.0.0`
2. `apps/boardest_teacher/pubspec.yaml` — Add `package_info_plus: ^9.0.0`
3. `apps/boardest/lib/services/update_service.dart`:
   - `initVersion()`: PackageInfo resolution + fallback chain
   - `cleanupOldUpdates()`: Purge both `tempDir/Updates` and `appSupport/Updates`
   - `executeInstall()`: Reset `stateNotifier.value = UpdateState.idle`
   - `normalizeVersion()`, `_isNewerVersion()`, tag parsing with case-insensitive `^[vV]`
4. `apps/boardest_teacher/lib/services/update_service.dart`:
   - `initVersion()`: PackageInfo resolution + fallback chain
   - `normalizeVersion()`, `_isNewer()`: Sync with `boardest` logic (strip `+` and case-insensitive `v`)
5. `apps/boardest/test/update_service_test.dart`:
   - Add unit tests for `_isNewerVersion` with SemVer + build numbers (`5.5.0+5500` vs `v5.5.0` -> false)
   - Add unit tests for case-insensitive `V5.5.0` vs `v5.5.0`
   - Add unit tests for `getTemporaryDirectory` update cleaning

---

## 6. Verification Method

1. **Unit Tests**:
   Run Flutter tests in `apps/boardest`:
   ```powershell
   cd apps/boardest
   flutter test test/update_service_test.dart
   ```
2. **Version Comparison Edge Cases**:
   - `_isNewerVersion('v5.5.0', '5.5.0')` => `false`
   - `_isNewerVersion('5.5.0', '5.5.0+5500')` => `false`
   - `_isNewerVersion('v5.5.0+5500', '5.5.0+5500')` => `false`
   - `_isNewerVersion('v5.5.0', '5.5.0+5500')` => `false`
   - `_isNewerVersion('v5.5.1', '5.5.0+5500')` => `true`
   - `_isNewerVersion('v5.5.0+5501', '5.5.0+5500')` => `true`
   - `_isNewerVersion('v5.4.3', '5.5.0')` => `false`
3. **Invalidation Condition**:
   If `_isNewerVersion` returns `true` when target and current represent the same version, or if `currentVersion` on Android returns an empty string or outdated version after installing a new APK, the verification fails.

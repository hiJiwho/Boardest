import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ScannedApp {
  final String name;
  final String appId;
  final String? iconPath;
  final bool hasIcon;

  ScannedApp({
    required this.name,
    required this.appId,
    this.iconPath,
    this.hasIcon = false,
  });
}

class SystemAppScanner {
  static List<ScannedApp>? _cachedApps;
  static const _channel = MethodChannel('com.boardest/launch_args');

  static void clearCache() {
    _cachedApps = null;
  }

  /// Boardest 내부 도구·바로가기는 앱 목록에서 제외.
  static bool isBoardestEntry(ScannedApp app) {
    final n = app.name.toLowerCase();
    final id = app.appId.toLowerCase();
    return id.startsWith('boardest://') ||
        id.contains('boardest') ||
        n.contains('boardest') ||
        n.contains('(boardest)');
  }

  static List<ScannedApp> externalAppsOnly(List<ScannedApp> apps) {
    return apps.where((a) => !isBoardestEntry(a)).toList();
  }
  static Future<void> createWindowsShortcuts() async {
    if (!Platform.isWindows) return;
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return;
      final boardestShortcutDir = Directory('$appData\\Microsoft\\Windows\\Start Menu\\Programs\\Boardest');
      
      bool needsCreation = false;
      if (!boardestShortcutDir.existsSync()) {
        needsCreation = true;
      } else {
        final entities = boardestShortcutDir.listSync();
        if (entities.length != 1) {
          needsCreation = true;
        } else {
          for (final entity in entities) {
            final name = entity.path.split('\\').last;
            if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(name)) {
              needsCreation = true;
              break;
            }
          }
        }
      }

      if (needsCreation) {
        final resolvedExe = Platform.resolvedExecutable;
        final tempDir = Directory.systemTemp;
        final scriptFile = File('${tempDir.path}\\boardest_create_shortcuts.ps1');

        final scriptContent = '''
\$target = "$resolvedExe"
\$shortcutFolder = "\$env:APPDATA\\Microsoft\\Windows\\Start Menu\\Programs\\Boardest"

# Clean recreate to remove any garbled shortcuts
if (Test-Path \$shortcutFolder) {
    Remove-Item -Path \$shortcutFolder -Recurse -Force | Out-Null
}
New-Item -ItemType Directory -Path \$shortcutFolder | Out-Null

\$wsh = New-Object -ComObject WScript.Shell

\$lnk = Join-Path \$shortcutFolder "Boardest.lnk"
\$sc = \$wsh.CreateShortcut(\$lnk)
\$sc.TargetPath = \$target
\$sc.Save()
''';
        // Write the PowerShell script using UTF-8 with BOM
        final bytes = utf8.encode(scriptContent);
        final bomBytes = [0xEF, 0xBB, 0xBF];
        await scriptFile.writeAsBytes([...bomBytes, ...bytes]);

        await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            scriptFile.path,
          ],
        );
        try {
          await scriptFile.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error creating Windows shortcuts: $e');
    }
  }

  /// Windows 로그인 시 Boardest 자동 실행 (현재 사용자 Run 레지스트리)
  static Future<void> ensureWindowsRunAtStartup() async {
    if (!Platform.isWindows) return;
    try {
      final exe = Platform.resolvedExecutable.replaceAll("'", "''");
      await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "\$runKey = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run'; "
              "Set-ItemProperty -Path \$runKey -Name 'Boardest' -Value '\"$exe\"'",
        ],
      );
      debugPrint('[SystemAppScanner] Windows Run-at-logon entry ensured.');
    } catch (e) {
      debugPrint('Error setting Windows autostart: $e');
    }
  }

  static Future<List<ScannedApp>> scanInstalledApps({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedApps != null && _cachedApps!.isNotEmpty) {
      return _cachedApps!;
    }
    final List<ScannedApp> apps = [];
    if (Platform.isWindows) {
      try {
        final tempDir = Directory.systemTemp;
        final scriptFile = File('${tempDir.path}\\boardest_get_icons.ps1');

        final scriptContent = '''
\$cacheDir = "\$env:TEMP\\boardest_icons"
if (!(Test-Path \$cacheDir)) {
    New-Item -ItemType Directory -Path \$cacheDir | Out-Null
}

\$apps = Get-StartApps

\$needsExtraction = \$false
foreach (\$app in \$apps) {
    \$safeId = \$app.AppID -replace '[\\\\/:*?"<>|! ]', '_'
    \$targetPng = Join-Path \$cacheDir "\$safeId.png"
    \$failedFile = Join-Path \$cacheDir "\$safeId.png.failed"
    if (!(Test-Path \$targetPng) -and !(Test-Path \$failedFile)) {
        \$needsExtraction = \$true
        break
    }
}

\$lnkMap = @{}
\$uwpPkgs = @{}

if (\$needsExtraction) {
    Add-Type -AssemblyName System.Drawing
    \$wsh = New-Object -ComObject WScript.Shell

    \$shortcutPaths = @(
        "\$env:APPDATA\\Microsoft\\Windows\\Start Menu\\Programs",
        "\$env:ProgramData\\Microsoft\\Windows\\Start Menu\\Programs"
    )

    foreach (\$dir in \$shortcutPaths) {
        if (Test-Path \$dir) {
            Get-ChildItem -Path \$dir -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                \$name = [System.IO.Path]::GetFileNameWithoutExtension(\$_.Name).ToLower()
                if (!\$lnkMap.ContainsKey(\$name)) {
                    try {
                        \$shortcut = \$wsh.CreateShortcut(\$_.FullName)
                        \$targetPath = \$shortcut.TargetPath
                        if (\$targetPath -and (Test-Path \$targetPath)) {
                            \$lnkMap[\$name] = \$targetPath
                        } else {
                            \$lnkMap[\$name] = \$_.FullName
                        }
                    } catch {
                        \$lnkMap[\$name] = \$_.FullName
                    }
                }
            }
        }
    }

    Get-AppxPackage | ForEach-Object {
        if (\$_.PackageFamilyName -and \$_.InstallLocation) {
            \$uwpPkgs[\$_.PackageFamilyName.ToLower()] = \$_.InstallLocation
        }
    }
}

function Find-UwpLogo(\$installLocation) {
    \$subDirs = @("Assets", "VisualElements", "images", "")
    foreach (\$sub in \$subDirs) {
        \$path = Join-Path \$installLocation \$sub
        if (Test-Path \$path) {
            \$pngs = Get-ChildItem -Path \$path -Filter "*.png" -ErrorAction SilentlyContinue
            if (\$pngs) {
                \$preferred = \$pngs | Where-Object { 
                    \$_.Name -match "AppList|Logo|Square|Tile|Icon" -and 
                    \$_.Name -notmatch "targetsize-(16|24|30|32|36|40)" 
                } | Select-Object -First 1
                if (\$preferred) { return \$preferred.FullName }
                return \$pngs[0].FullName
            }
        }
    }
    
    \$assetsPath = Join-Path \$installLocation "Assets"
    if (Test-Path \$assetsPath) {
        \$pngs = Get-ChildItem -Path \$assetsPath -Filter "*.png" -Recurse -ErrorAction SilentlyContinue
        if (\$pngs) {
            \$preferred = \$pngs | Where-Object { 
                \$_.Name -match "AppList|Logo|Square|Tile|Icon" -and 
                \$_.Name -notmatch "targetsize-(16|24|30|32|36|40)" 
            } | Select-Object -First 1
            if (\$preferred) { return \$preferred.FullName }
            return \$pngs[0].FullName
        }
    }
    return \$null
}

\$result = @()

foreach (\$app in \$apps) {
    \$name = \$app.Name
    \$appId = \$app.AppID
    \$iconPath = ""
    
    \$safeId = \$appId -replace '[\\\\/:*?"<>|! ]', '_'
    \$targetPng = Join-Path \$cacheDir "\$safeId.png"
    \$failedFile = Join-Path \$cacheDir "\$safeId.png.failed"
    
    try {
        if (Test-Path \$targetPng) {
            \$iconPath = \$targetPng
        } elseif (Test-Path \$failedFile) {
            \$iconPath = ""
        } else {
            \$lowerName = \$name.ToLower()
            \$resolvedPath = ""
            if (\$lnkMap.ContainsKey(\$lowerName)) {
                \$resolvedPath = \$lnkMap[\$lowerName]
            } elseif (Test-Path \$appId) {
                \$resolvedPath = \$appId
            }
            
            if (\$resolvedPath -ne "" -and (Test-Path \$resolvedPath)) {
                \$icon = [System.Drawing.Icon]::ExtractAssociatedIcon(\$resolvedPath)
                \$bmp = \$icon.ToBitmap()
                \$bmp.Save(\$targetPng, [System.Drawing.Imaging.ImageFormat]::Png)
                \$icon.Dispose()
                \$bmp.Dispose()
                \$iconPath = \$targetPng
            }
            elseif (\$appId.Contains("!") -or \$appId -match "^[A-Za-z0-9\\.]+\\_[a-z0-9]+") {
                \$pfn = \$appId.Split("!")[0].ToLower()
                if (\$uwpPkgs.ContainsKey(\$pfn)) {
                    \$installLocation = \$uwpPkgs[\$pfn]
                    if (\$installLocation -and (Test-Path \$installLocation)) {
                        \$uwpLogo = Find-UwpLogo \$installLocation
                        if (\$uwpLogo -and (Test-Path \$uwpLogo)) {
                            Copy-Item \$uwpLogo \$targetPng -Force
                            \$iconPath = \$targetPng
                        }
                    }
                }
            }
            
            if (!(Test-Path \$targetPng)) {
                New-Item -ItemType File -Path \$failedFile -Force | Out-Null
            }
        }
    } catch {
        if (!(Test-Path \$targetPng)) {
            New-Item -ItemType File -Path \$failedFile -Force | Out-Null
        }
    }
    
    \$displayIconPath = \$iconPath -replace '\\\\', '/'
    
    \$result += [PSCustomObject]@{
        Name = \$name
        AppID = \$appId
        IconPath = \$displayIconPath
    }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
\$result | ConvertTo-Json
''';

        await scriptFile.writeAsString(scriptContent, encoding: utf8);

        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            scriptFile.path,
          ],
          stdoutEncoding: utf8,
        );

        try {
          await scriptFile.delete();
        } catch (_) {}

        if (result.exitCode == 0) {
          final String output = result.stdout.toString();
          if (output.trim().isNotEmpty) {
            final decoded = jsonDecode(output);
            final List<dynamic> jsonList = decoded is List ? decoded : [decoded];
            final Set<String> seenNames = {};
            for (final item in jsonList) {
              if (item is Map) {
                final name = item['Name']?.toString() ?? '';
                final appId = item['AppID']?.toString() ?? '';
                final iconPath = item['IconPath']?.toString() ?? '';
                if (name.isNotEmpty && appId.isNotEmpty) {
                  final lowerName = name.toLowerCase();
                  if (!seenNames.contains(lowerName)) {
                    final hasIconFile = iconPath.isNotEmpty && File(iconPath).existsSync();
                    apps.add(ScannedApp(
                      name: name,
                      appId: appId,
                      iconPath: iconPath.isNotEmpty ? iconPath : null,
                      hasIcon: hasIconFile,
                    ));
                    seenNames.add(lowerName);
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('PowerShell app scan failed: $e');
      }

      // Fallback: if PowerShell scan failed or returned no apps, do a quick shallow scan of Start Menu folders
      if (apps.isEmpty) {
        try {
          final scannedApps = await Isolate.run<List<ScannedApp>>(() {
            final List<ScannedApp> localApps = [];
            final List<Directory> dirs = [];
            
            // 1. User Start Menu
            final appData = Platform.environment['APPDATA'];
            if (appData != null) {
              dirs.add(Directory('$appData\\Microsoft\\Windows\\Start Menu\\Programs'));
            }
            
            // 2. Common Start Menu
            final programData = Platform.environment['PROGRAMDATA'];
            if (programData != null) {
              dirs.add(Directory('$programData\\Microsoft\\Windows\\Start Menu\\Programs'));
            }
            
            final Set<String> seenNames = {};
            
            void scanDir(Directory dir, int maxDepth, int currentDepth) {
              if (currentDepth > maxDepth) return;
              try {
                if (!dir.existsSync()) return;
                final List<FileSystemEntity> entities = dir.listSync(followLinks: false);
                for (final entity in entities) {
                  if (entity is File) {
                    final path = entity.path;
                    if (path.toLowerCase().endsWith('.lnk')) {
                      final filename = path.contains('\\') ? path.split('\\').last : path.split('/').last;
                      if (filename.toLowerCase().endsWith('.lnk') && filename.length > 4) {
                        final name = filename.substring(0, filename.length - 4); // Remove .lnk
                        final appId = path;
                        if (name.isNotEmpty && appId.isNotEmpty) {
                          final lowerName = name.toLowerCase();
                          if (!seenNames.contains(lowerName)) {
                            localApps.add(ScannedApp(name: name, appId: appId, hasIcon: false));
                            seenNames.add(lowerName);
                          }
                        }
                      }
                    }
                  } else if (entity is Directory) {
                    scanDir(entity, maxDepth, currentDepth + 1);
                  }
                }
              } catch (_) {
                // Ignore directory access / permission errors
              }
            }

            for (final dir in dirs) {
              scanDir(dir, 2, 1); // Limit depth to 2 for quick scanning as a fallback
            }
            
            return localApps;
          });
          apps.addAll(scannedApps);
        } catch (e) {
          debugPrint('Windows app fallback directory scan failed: $e');
        }
      }
    } else if (Platform.isAndroid) {
      try {
        final dynamic raw = await _channel.invokeMethod('listInstalledApps');
        if (raw is List) {
          for (final item in raw) {
            if (item is Map) {
              final name = item['name']?.toString() ?? '';
              final pkg = item['appId']?.toString() ?? '';
              if (name.isNotEmpty && pkg.isNotEmpty && pkg != 'com.boardest.comcigan.boardest') {
                apps.add(ScannedApp(name: name, appId: pkg, hasIcon: false));
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Android app scan (channel) failed: $e');
        try {
          final result = await Process.run('pm', ['list', 'packages', '-3']);
          if (result.exitCode == 0) {
            for (final line in result.stdout.toString().split('\n')) {
              if (line.startsWith('package:')) {
                final pkg = line.replaceFirst('package:', '').trim();
                if (pkg.isNotEmpty && pkg != 'com.boardest.comcigan.boardest') {
                  apps.add(ScannedApp(name: pkg.split('.').last, appId: pkg, hasIcon: false));
                }
              }
            }
          }
        } catch (e2) {
          debugPrint('Android app scan (pm) failed: $e2');
        }
      }
    }

    final filtered = externalAppsOnly(apps);
    filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _cachedApps = filtered;
    return filtered;
  }

  static Future<bool> launchApp(String appId) async {
    if (appId.startsWith('http://') || appId.startsWith('https://')) {
      try {
        final uri = Uri.parse(appId);
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Error launching URL app: $e');
        return false;
      }
    }
    if (Platform.isWindows) {
      try {
        final lower = appId.toLowerCase();
        
        // Direct handling for shortcut (.lnk) files to avoid CreateProcessW errors
        if (lower.endsWith('.lnk')) {
          await Process.start('explorer.exe', [appId], mode: ProcessStartMode.detached);
          return true;
        }

        // Determine if this is a standard absolute local executable file
        final isLocalFile = (lower.endsWith('.exe') ||
                lower.endsWith('.bat') ||
                lower.endsWith('.cmd')) &&
            (lower.startsWith('c:\\') ||
                lower.startsWith('d:\\') ||
                RegExp(r'^[a-z]:[/\\]', caseSensitive: false).hasMatch(lower) ||
                lower.startsWith('\\\\'));

        if (isLocalFile) {
          await Process.start(
            appId,
            [],
            mode: ProcessStartMode.detached,
            runInShell: lower.endsWith('.bat') || lower.endsWith('.cmd'),
          );
          return true;
        } else if (lower.endsWith('.exe') || lower.endsWith('.bat') || lower.endsWith('.cmd')) {
          // Launch standard bare system executables directly without shell:AppsFolder wrapper
          await Process.start(
            appId,
            [],
            mode: ProcessStartMode.detached,
            runInShell: lower.endsWith('.bat') || lower.endsWith('.cmd'),
          );
          return true;
        } else {
          // Launch via shell:AppsFolder for Windows Store Apps / Start Menu AppIDs
          final result = await Process.run('explorer.exe', ['shell:AppsFolder\\$appId']);
          return result.exitCode == 0;
        }
      } catch (e) {
        debugPrint('Error launching Windows app: $e');
        try {
          await Process.start('explorer.exe', [appId], mode: ProcessStartMode.detached);
          return true;
        } catch (_) {
          return false;
        }
      }
    } else if (Platform.isAndroid) {
      try {
        final launched = await _channel.invokeMethod<bool>('launchApp', {'packageName': appId});
        if (launched == true) return true;
      } catch (e) {
        debugPrint('Android launchApp channel failed: $e');
      }
      return false;
    }
    return false;
  }
}

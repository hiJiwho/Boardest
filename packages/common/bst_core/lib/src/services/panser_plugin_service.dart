import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';

/// Service to ensure the BST Overlay Panser plugin (AppX) is installed and up-to-date.
/// Downloads and installs from GitHub Releases on first launch.
class PanserPluginService {
  static const String packageFamilyOrName = 'jiwho.boardest.plugin.overlaypanser';
  static const String downloadUrl =
      'https://github.com/hiJiwho/Boardest/releases/latest/download/bst-overlay-panser.appx';

  /// Check if the AppX package is installed on the system.
  static Future<bool> isInstalled() async {
    if (!Platform.isWindows) return false;
    try {
      final res = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        'Get-AppxPackage -Name "$packageFamilyOrName" | Select-Object -ExpandProperty InstallLocation'
      ]);
      final out = res.stdout.toString().trim();
      return out.isNotEmpty && Directory(out).existsSync();
    } catch (e) {
      debugPrint('[PanserPlugin] Check isInstalled error: $e');
      return false;
    }
  }

  /// Get the installation directory of the AppX package.
  static Future<String?> getInstallLocation() async {
    if (!Platform.isWindows) return null;
    try {
      final res = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        'Get-AppxPackage -Name "$packageFamilyOrName" | Select-Object -ExpandProperty InstallLocation'
      ]);
      final out = res.stdout.toString().trim();
      if (out.isNotEmpty && Directory(out).existsSync()) {
        return out;
      }
    } catch (e) {
      debugPrint('[PanserPlugin] getInstallLocation error: $e');
    }
    return null;
  }

  /// Locate a specific helper executable inside the package or local app directory.
  static Future<String?> findExecutable(String exeName) async {
    if (!Platform.isWindows) return null;

    // 1. Check AppX installed package directory
    final appxDir = await getInstallLocation();
    if (appxDir != null) {
      final appxExe = p.join(appxDir, exeName);
      if (File(appxExe).existsSync()) {
        return appxExe;
      }
    }

    // 2. Fallback: Check alongside current executable (if running portable/debug)
    final localDir = File(Platform.resolvedExecutable).parent.path;
    final localExe = p.join(localDir, exeName);
    if (File(localExe).existsSync()) {
      return localExe;
    }

    return null;
  }

  /// Download and install the package from GitHub Releases on first launch.
  static Future<bool> installFromGithub({void Function(double progress)? onProgress}) async {
    if (!Platform.isWindows) return false;

    try {
      debugPrint('[PanserPlugin] Downloading $downloadUrl...');
      final tempDir = await getTemporaryDirectory();
      final appxPath = p.join(tempDir.path, 'bst-overlay-panser.appx');

      final client = http.Client();
      final req = http.Request('GET', Uri.parse(downloadUrl));
      final resp = await client.send(req);

      if (resp.statusCode != 200) {
        debugPrint('[PanserPlugin] Download failed with status ${resp.statusCode}');
        client.close();
        return false;
      }

      final total = resp.contentLength ?? 0;
      int received = 0;
      final file = File(appxPath);
      final sink = file.openWrite();

      await resp.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      });

      await sink.close();
      client.close();
      debugPrint('[PanserPlugin] Download complete. Installing package: $appxPath');

      // Install using Add-AppxPackage
      final installRes = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        'Add-AppxPackage -Path "$appxPath" -ForceApplicationShutdown'
      ]);

      if (installRes.exitCode == 0) {
        debugPrint('[PanserPlugin] Successfully installed bst-overlay-panser.appx!');
        try {
          file.deleteSync();
        } catch (_) {}
        return true;
      } else {
        debugPrint('[PanserPlugin] Add-AppxPackage error: ${installRes.stderr}');
        return false;
      }
    } catch (e) {
      debugPrint('[PanserPlugin] Install error: $e');
      return false;
    }
  }

  /// Ensure the package is installed, downloading it if necessary.
  static Future<String?> ensureExecutable(String exeName, {void Function(double progress)? onProgress}) async {
    var exePath = await findExecutable(exeName);
    if (exePath != null) return exePath;

    final installed = await installFromGithub(onProgress: onProgress);
    if (installed) {
      return await findExecutable(exeName);
    }
    return null;
  }
}

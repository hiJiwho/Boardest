import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

enum SyncDirection { localToUsb, usbToLocal }

class SyncChange {
  final String relativePath;
  final SyncDirection direction;
  final int bytes;

  const SyncChange(this.relativePath, this.direction, this.bytes);
}

class SyncConflict {
  final String relativePath;
  const SyncConflict(this.relativePath);
}

class SyncPreview {
  final List<SyncChange> changes;
  final List<SyncConflict> conflicts;
  const SyncPreview(this.changes, this.conflicts);

  int get uploadBytes => changes
      .where((change) => change.direction == SyncDirection.localToUsb)
      .fold(0, (total, change) => total + change.bytes);
}

class SyncResult {
  final int copied;
  final int verified;
  final List<String> failures;
  const SyncResult({required this.copied, required this.verified, required this.failures});
}

/// Two-way USB sync with a persisted hash baseline for conflict detection.
class UsbSyncService {
  static const _stateFolder = '.boardest';
  static const _stateFile = 'sync_state.json';

  Future<SyncPreview> preview(Directory local, Directory usb) async {
    final localFiles = await _snapshot(local);
    final usbFiles = await _snapshot(usb);
    final baseline = await _readState(usb);
    final changes = <SyncChange>[];
    final conflicts = <SyncConflict>[];

    final names = {...localFiles.keys, ...usbFiles.keys};
    for (final name in names) {
      final left = localFiles[name];
      final right = usbFiles[name];
      if (left == null) {
        changes.add(SyncChange(name, SyncDirection.usbToLocal, right!.bytes));
        continue;
      }
      if (right == null) {
        changes.add(SyncChange(name, SyncDirection.localToUsb, left.bytes));
        continue;
      }
      if (left.hash == right.hash) continue;

      final base = baseline[name];
      if (base != null && left.hash != base && right.hash != base) {
        conflicts.add(SyncConflict(name));
        continue;
      }
      changes.add(SyncChange(
        name,
        left.modified.isAfter(right.modified) ? SyncDirection.localToUsb : SyncDirection.usbToLocal,
        left.modified.isAfter(right.modified) ? left.bytes : right.bytes,
      ));
    }
    changes.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    conflicts.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return SyncPreview(changes, conflicts);
  }

  Future<SyncResult> apply(Directory local, Directory usb, SyncPreview preview) async {
    final failures = <String>[];
    var copied = 0;
    var verified = 0;
    for (final change in preview.changes) {
      final sourceRoot = change.direction == SyncDirection.localToUsb ? local : usb;
      final targetRoot = change.direction == SyncDirection.localToUsb ? usb : local;
      final source = File(p.join(sourceRoot.path, change.relativePath));
      final target = File(p.join(targetRoot.path, change.relativePath));
      try {
        await target.parent.create(recursive: true);
        await source.copy(target.path);
        copied++;
        if (await _hash(source) == await _hash(target)) {
          verified++;
        } else {
          failures.add('${change.relativePath}: verification failed');
        }
      } catch (error) {
        failures.add('${change.relativePath}: $error');
      }
    }
    if (failures.isEmpty) await _writeState(usb, await _snapshot(local));
    return SyncResult(copied: copied, verified: verified, failures: failures);
  }

  Future<int?> getUsbFreeBytes(String usbRoot) async {
    if (!Platform.isWindows) return null;
    try {
      final drive = p.rootPrefix(usbRoot).replaceAll('\\', '').replaceAll(':', '');
      final result = await Process.run('powershell', [
        '-NoProfile', '-Command',
        "(Get-PSDrive -Name '$drive').Free",
      ]);
      return result.exitCode == 0 ? int.tryParse(result.stdout.toString().trim()) : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, _SyncFile>> _snapshot(Directory root) async {
    final result = <String, _SyncFile>{};
    if (!await root.exists()) return result;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || p.isWithin(p.join(root.path, _stateFolder), entity.path)) continue;
      final relative = p.relative(entity.path, from: root.path).replaceAll('\\', '/').toLowerCase();
      result[relative] = _SyncFile(
        entity.path,
        await entity.length(),
        await entity.lastModified(),
        await _hash(entity),
      );
    }
    return result;
  }

  Future<Map<String, String>> _readState(Directory usb) async {
    final file = File(p.join(usb.path, _stateFolder, _stateFile));
    if (!await file.exists()) return {};
    try {
      return Map<String, String>.from((jsonDecode(await file.readAsString()) as Map)['files'] as Map? ?? {});
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeState(Directory usb, Map<String, _SyncFile> files) async {
    final file = File(p.join(usb.path, _stateFolder, _stateFile));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'files': files.map((name, file) => MapEntry(name, file.hash)),
    }));
  }

  Future<String> _hash(File file) async => sha256.convert(await file.readAsBytes()).toString();
}

class _SyncFile {
  final String path;
  final int bytes;
  final DateTime modified;
  final String hash;
  const _SyncFile(this.path, this.bytes, this.modified, this.hash);
}

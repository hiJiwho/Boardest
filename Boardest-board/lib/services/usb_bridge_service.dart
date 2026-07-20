import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// File-based Teacher <-> Board protocol stored on a shared USB drive.
/// It deliberately lives outside lesson folders so existing USB layouts remain valid.
class UsbBridgeService {
  static const protocolVersion = 1;
  static const _rootName = '.boardest';

  static Directory _root(String usbRoot) =>
      Directory(p.join(usbRoot, _rootName));
  static Directory _commands(String usbRoot) =>
      Directory(p.join(_root(usbRoot).path, 'commands'));
  static Directory _acks(String usbRoot) =>
      Directory(p.join(_root(usbRoot).path, 'acks'));

  static Future<void> ensure(String usbRoot) async {
    await _root(usbRoot).create(recursive: true);
    await _commands(usbRoot).create(recursive: true);
    await _acks(usbRoot).create(recursive: true);
    final meta = File(p.join(_root(usbRoot).path, 'meta.json'));
    if (!await meta.exists()) {
      await _writeJson(meta, {
        'protocolVersion': protocolVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  static Future<bool> isCompatible(String usbRoot) async {
    try {
      final meta = File(p.join(_root(usbRoot).path, 'meta.json'));
      if (!await meta.exists())
        return true; // A regular USB becomes compatible on first use.
      final json = await _readJson(meta);
      return (json['protocolVersion'] as num?)?.toInt() == protocolVersion;
    } catch (_) {
      return false;
    }
  }

  static Future<String> queueCommand(
    String usbRoot,
    String type, {
    Map<String, dynamic> payload = const {},
  }) async {
    await ensure(usbRoot);
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${type.replaceAll(RegExp(r'[^a-z0-9_]'), '_')}';
    await _writeJson(File(p.join(_commands(usbRoot).path, '$id.json')), {
      'id': id,
      'type': type,
      'payload': payload,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'protocolVersion': protocolVersion,
    });
    return id;
  }

  static Future<List<Map<String, dynamic>>> takeCommands(String usbRoot) async {
    await ensure(usbRoot);
    final result = <Map<String, dynamic>>[];
    await for (final entity in _commands(usbRoot).list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final command = await _readJson(entity);
        final id = command['id']?.toString();
        if (id == null || id.isEmpty) continue;
        await entity.rename(p.join(_commands(usbRoot).path, '.$id.processing'));
        result.add(command);
      } catch (_) {
        // A command can be observed while Teacher is atomically publishing it.
      }
    }
    return result;
  }

  static Future<void> acknowledge(
    String usbRoot,
    String id, {
    required bool success,
    String? message,
  }) async {
    await ensure(usbRoot);
    await _writeJson(File(p.join(_acks(usbRoot).path, '$id.json')), {
      'id': id,
      'success': success,
      'message': message ?? '',
      'processedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> readAcknowledgements(
    String usbRoot,
  ) async {
    if (!await _acks(usbRoot).exists()) return [];
    final result = <Map<String, dynamic>>[];
    await for (final entity in _acks(usbRoot).list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        result.add(await _readJson(entity));
      } catch (_) {}
    }
    result.sort(
      (a, b) => (b['processedAt']?.toString() ?? '').compareTo(
        a['processedAt']?.toString() ?? '',
      ),
    );
    return result;
  }

  static Future<void> publishBoardStatus(
    String usbRoot,
    Map<String, dynamic> status,
  ) async {
    await ensure(usbRoot);
    await _writeJson(File(p.join(_root(usbRoot).path, 'board_status.json')), {
      ...status,
      'protocolVersion': protocolVersion,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<Map<String, dynamic>?> readBoardStatus(String usbRoot) async {
    final file = File(p.join(_root(usbRoot).path, 'board_status.json'));
    if (!await file.exists()) return null;
    try {
      return await _readJson(file);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeSyncManifest(
    String usbRoot,
    List<Directory> folders,
  ) async {
    await ensure(usbRoot);
    final files = <Map<String, dynamic>>[];
    for (final folder in folders) {
      if (!await folder.exists()) continue;
      await for (final entity in folder.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final bytes = await entity.readAsBytes();
        files.add({
          'path': entity.path,
          'size': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
          'modifiedAt': (await entity.lastModified()).toUtc().toIso8601String(),
        });
      }
    }
    await _writeJson(File(p.join(_root(usbRoot).path, 'sync_manifest.json')), {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'files': files,
    });
  }

  static Future<File> createDiagnosticReport(
    String usbRoot,
    Map<String, dynamic> report,
  ) async {
    await ensure(usbRoot);
    final file = File(
      p.join(
        _root(usbRoot).path,
        'diagnostic_${DateTime.now().millisecondsSinceEpoch}.json',
      ),
    );
    await _writeJson(file, {
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      ...report,
    });
    return file;
  }

  static Future<Map<String, dynamic>> _readJson(File file) async =>
      Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);

  static Future<void> _writeJson(File file, Map<String, dynamic> value) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value));
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}

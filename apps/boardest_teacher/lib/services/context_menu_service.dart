import 'dart:io';
import 'package:flutter/foundation.dart';

/// Windows Shell 우클릭 컨텍스트 메뉴 & 파일 연결 프로그램 서비스
/// 1. 폴더 우클릭: "Boardest Pro — 이 폴더를 교안으로 매핑" (Directory)
/// 2. 드라이브 우클릭: "Boardest Pro — 이 드라이브를 교안으로 매핑" (Drive)
/// 3. .BST 파일 연결: 더블 클릭 시 Boardest가 "--view-bst <파일경로>"로 실행되도록 연결
class ContextMenuService {
  static const _dirMenuKey = r'HKCR\Directory\shell\BoardestProMap';
  static const _dirCommandKey = r'HKCR\Directory\shell\BoardestProMap\command';

  static const _driveMenuKey = r'HKCR\Drive\shell\BoardestProMap';
  static const _driveCommandKey = r'HKCR\Drive\shell\BoardestProMap\command';

  static const _bstExtKey = r'HKCR\.BST';
  static const _bstClassKey = r'HKCR\Boardest.BstFile';
  static const _bstCommandKey = r'HKCR\Boardest.BstFile\shell\open\command';

  /// 컨텍스트 메뉴 및 파일 연결 등록
  /// [exePath]: Boardest.exe 절대 경로 (전달하지 않으면 현재 실행 파일 경로 사용)
  static Future<bool> registerAll({String? exePath}) async {
    if (!Platform.isWindows) return false;

    final exe = exePath ?? Platform.resolvedExecutable;
    final escaped = exe.replaceAll('"', r'\"');

    try {
      // 1. Directory (폴더 우클릭)
      final d1 = await _regAdd(key: _dirMenuKey, valueName: '', valueType: 'REG_SZ', data: 'Boardest Pro — 이 폴더를 교안으로 매핑');
      final d2 = await _regAdd(key: _dirMenuKey, valueName: 'Icon', valueType: 'REG_SZ', data: '"$escaped"');
      final d3 = await _regAdd(key: _dirCommandKey, valueName: '', valueType: 'REG_SZ', data: '"$escaped" --lite-map "%1"');

      // 2. Drive (드라이브 루트 우클릭)
      final dr1 = await _regAdd(key: _driveMenuKey, valueName: '', valueType: 'REG_SZ', data: 'Boardest Pro — 이 드라이브를 교안으로 매핑');
      final dr2 = await _regAdd(key: _driveMenuKey, valueName: 'Icon', valueType: 'REG_SZ', data: '"$escaped"');
      final dr3 = await _regAdd(key: _driveCommandKey, valueName: '', valueType: 'REG_SZ', data: '"$escaped" --lite-map "%1"');

      // 3. .BST 파일 연결
      final ext = await _regAdd(key: _bstExtKey, valueName: '', valueType: 'REG_SZ', data: 'Boardest.BstFile');
      final cls = await _regAdd(key: _bstClassKey, valueName: '', valueType: 'REG_SZ', data: 'Boardest 수업 자료');
      final bstCmd = await _regAdd(key: _bstCommandKey, valueName: '', valueType: 'REG_SZ', data: '"$escaped" --view-bst "%1"');

      final success = d1 && d2 && d3 && dr1 && dr2 && dr3 && ext && cls && bstCmd;
      debugPrint('[ContextMenuService] Registered all shell integrations: $success');
      return success;
    } catch (e) {
      debugPrint('[ContextMenuService] registerAll error: $e');
      return false;
    }
  }

  /// 컨텍스트 메뉴 및 파일 연결 등록 해제
  static Future<bool> unregisterAll() async {
    if (!Platform.isWindows) return false;
    try {
      final r1 = await Process.run('reg', ['delete', _dirMenuKey, '/f']);
      final r2 = await Process.run('reg', ['delete', _driveMenuKey, '/f']);
      final r3 = await Process.run('reg', ['delete', _bstExtKey, '/f']);
      final r4 = await Process.run('reg', ['delete', _bstClassKey, '/f']);

      final success = r1.exitCode == 0 && r2.exitCode == 0 && r3.exitCode == 0 && r4.exitCode == 0;
      debugPrint('[ContextMenuService] Unregistered all shell integrations: $success');
      return success;
    } catch (e) {
      debugPrint('[ContextMenuService] unregisterAll error: $e');
      return false;
    }
  }

  /// 현재 컨텍스트 메뉴가 등록되어 있는지 확인
  static Future<bool> isRegistered() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('reg', ['query', _dirMenuKey]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _regAdd({
    required String key,
    required String valueName,
    required String valueType,
    required String data,
  }) async {
    final args = ['add', key, '/f', '/t', valueType, '/d', data];
    if (valueName.isNotEmpty) {
      args.addAll(['/v', valueName]);
    }
    final result = await Process.run('reg', args);
    return result.exitCode == 0;
  }
}

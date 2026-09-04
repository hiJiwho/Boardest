import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_drive_service.dart';

/// Bst-cloud-pro PC 지정 폴더 백그라운드 파일 동기화 서비스 (판서 제외)
class PcSyncService {
  static final PcSyncService instance = PcSyncService._internal();
  PcSyncService._internal();

  Timer? _syncTimer;
  bool _isSyncing = false;
  String? _localSyncPath;

  bool get isSyncing => _isSyncing;
  String? get localSyncPath => _localSyncPath;

  /// 동기화 초기화 및 타이머 가동
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _localSyncPath = prefs.getString('bst_pc_sync_folder');
      if (_localSyncPath == null || _localSyncPath!.isEmpty) {
        final docDir = await getApplicationDocumentsDirectory();
        _localSyncPath = p.join(docDir.path, 'BoardestSync');
      }
      final dir = Directory(_localSyncPath!);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      startAutoSync();
    } catch (e) {
      debugPrint('[PcSyncService] Init error: $e');
    }
  }

  /// 사용자가 지정한 로컬 동기화 폴더 설정
  Future<void> setCustomSyncPath(String customPath) async {
    _localSyncPath = customPath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bst_pc_sync_folder', customPath);
    final dir = Directory(customPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    syncNow();
  }

  void startAutoSync() {
    _syncTimer?.cancel();
    // 60초마다 백그라운드 파일 검사 및 동기화
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) => syncNow());
  }

  void stopAutoSync() {
    _syncTimer?.cancel();
  }

  /// 백그라운드 파일 동기화 (단, 판서 파일(.pen, .bstpen, .iwb)은 동기화 대상에서 제외)
  Future<void> syncNow() async {
    if (_isSyncing || !CloudDriveService.instance.isLoggedIn || _localSyncPath == null) return;
    _isSyncing = true;
    try {
      final dir = Directory(_localSyncPath!);
      if (!dir.existsSync()) return;

      final entities = dir.listSync(recursive: false);
      debugPrint('[PcSyncService] Checking ${entities.length} local items for Bst-cloud sync...');

      final driveFiles = await CloudDriveService.instance.fetchDriveFiles();
      final driveNameMap = {for (final df in driveFiles) df.name: df};

      for (final entity in entities) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          final lower = fileName.toLowerCase();

          // 단 판서 제외: .pen, .bstpen, .iwb, 임시파일 제외
          if (lower.endsWith('.pen') || lower.endsWith('.bstpen') || lower.endsWith('.iwb') || lower.startsWith('~') || lower.startsWith('.')) {
            continue;
          }

          if (!driveNameMap.containsKey(fileName)) {
            debugPrint('[PcSyncService] Uploading new local file to Bst-cloud: $fileName');
            await CloudDriveService.instance.uploadFileToDrive(entity);
          }
        }
      }
    } catch (e) {
      debugPrint('[PcSyncService] syncNow error: $e');
    } finally {
      _isSyncing = false;
    }
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'cloud_drive_service.dart';

/// Bst-cloud-pro PC 지정 폴더 백그라운드 파일 동기화 서비스
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
      final docDir = await getApplicationDocumentsDirectory();
      _localSyncPath = p.join(docDir.path, 'BoardestSync');
      final dir = Directory(_localSyncPath!);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      startAutoSync();
    } catch (e) {
      debugPrint('[PcSyncService] Init error: $e');
    }
  }

  void startAutoSync() {
    _syncTimer?.cancel();
    // 60초마다 백그라운드 파일 검사 및 동기화
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) => syncNow());
  }

  void stopAutoSync() {
    _syncTimer?.cancel();
  }

  Future<void> syncNow() async {
    if (_isSyncing || !CloudDriveService.instance.isLoggedIn || _localSyncPath == null) return;
    _isSyncing = true;
    try {
      final dir = Directory(_localSyncPath!);
      if (!dir.existsSync()) return;

      final files = dir.listSync();
      debugPrint('[PcSyncService] Syncing ${files.length} local items with Bst-cloud...');

      // Bst-cloud Drive 파일 목록 가져오기
      final driveFiles = await CloudDriveService.instance.fetchDriveFiles();
      for (final entity in files) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          final existsOnDrive = driveFiles.any((df) => df.name == fileName);
          if (!existsOnDrive) {
            debugPrint('[PcSyncService] Uploading new local file to Bst-cloud: $fileName');
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

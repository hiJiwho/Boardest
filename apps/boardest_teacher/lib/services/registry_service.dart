import 'dart:io';
import 'package:flutter/foundation.dart';

/// Windows Registry 전용 파일 확장자 연동 서비스
class RegistryService {
  static final RegistryService instance = RegistryService._internal();
  RegistryService._internal();

  /// BST 전용 연동 대상 확장자 목록 (.bstsave 제외)
  static const List<String> bstExtensions = [
    '.bstTBP',
    '.BSTvideo',
    '.BSTcanva',
    '.bstpen',
  ];

  /// Windows 레지스트리에 BST 전용 확장자 자동 등록 (HKCU\Software\Classes)
  Future<void> registerFileAssociations() async {
    if (!Platform.isWindows) return;

    try {
      final exePath = Platform.resolvedExecutable;
      debugPrint('[RegistryService] Registering file associations for: $exePath');

      for (final ext in bstExtensions) {
        final progId = 'BoardestFile${ext.replaceAll('.', '').toUpperCase()}';
        
        // 1. Extension -> ProgId 연동
        await _runRegAdd(
          r'HKCU\Software\Classes\' + ext,
          '',
          progId,
        );

        // 2. ProgId 설명 및 아이콘 등록
        await _runRegAdd(
          r'HKCU\Software\Classes\' + progId,
          '',
          'Boardest Dedicated File ($ext)',
        );

        // 3. Open Command 등록 (%1 인자 포함)
        final openCommand = '"$exePath" "%1"';
        await _runRegAdd(
          r'HKCU\Software\Classes\' + progId + r'\shell\open\command',
          '',
          openCommand,
        );
      }

      // 4. 기존 레거시 반/교안 매핑 탐색기 컨텍스트 메뉴 잔재 제거
      await cleanupLegacyContextMenu();

      // 5. Windows 앱 설치 관리자(AppInstaller)가 매번 실행 시 GitHub/서버 업데이트를 확인하도록 OS 설정 보장
      await ensureAppInstallerAutoUpdateSettings();

      debugPrint('[RegistryService] Successfully registered Windows file associations and AppInstaller auto-update settings!');
    } catch (e) {
      debugPrint('[RegistryService] Registry registration error: $e');
    }
  }

  /// Windows 앱 설치 관리자(AppInstaller)가 매번 실행 시 GitHub/서버에 업데이트가 있는지 확인하도록 OS 설정 보장
  Future<void> ensureAppInstallerAutoUpdateSettings() async {
    if (!Platform.isWindows) return;
    try {
      final exePath = Platform.resolvedExecutable;
      if (exePath.contains('WindowsApps')) {
        final psCommand =
            'Set-AppxPackageAutoUpdateSettings -PackageFamilyName "jiwho.boardest.teacher_nmkn64tehfz7a" '
            '-AppInstallerUri "https://download-boardest.web.app/bst-teacher.appinstaller" '
            '-CheckOnLaunch \$true -ShowPrompt \$true -UpdateBlocksActivation \$true '
            '-ForceUpdateFromAnyVersion \$true -HoursBetweenUpdateChecks 0 -ErrorAction SilentlyContinue';
        await Process.run('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psCommand]);
      }
    } catch (e) {
      debugPrint('[RegistryService] AutoUpdateSettings error: $e');
    }
  }

  /// 과거 버전에서 등록되었던 탐색기 우클릭 교안/반 매핑 레지스트리 키 자동 정리
  Future<void> cleanupLegacyContextMenu() async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('reg', ['delete', r'HKCU\Software\Classes\Directory\shell\BoardestMap', '/f']);
      await Process.run('reg', ['delete', r'HKCU\Software\Classes\Drive\shell\BoardestMap', '/f']);
    } catch (_) {}
  }

  Future<bool> _runRegAdd(String keyPath, String valueName, String valueData) async {
    try {
      final args = <String>[
        'add',
        keyPath,
        '/f',
      ];
      if (valueName.isEmpty) {
        args.add('/ve');
      } else {
        args.addAll(['/v', valueName]);
      }
      args.addAll(['/d', valueData]);

      final res = await Process.run('reg', args);
      return res.exitCode == 0;
    } catch (e) {
      debugPrint('[RegistryService] reg add failed for $keyPath: $e');
      return false;
    }
  }
}

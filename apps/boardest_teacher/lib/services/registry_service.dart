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
      debugPrint('[RegistryService] Successfully registered Windows file associations!');
    } catch (e) {
      debugPrint('[RegistryService] Registry registration error: $e');
    }
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

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 시스템 트레이 서비스
/// - 현재 교시/반 정보를 툴팁으로 실시간 표시
/// - 우클릭 메뉴: 앱 열기 / 완전 종료
/// - 싱글톤 패턴 (앱 전역에서 하나만 존재)
class TrayService {
  static TrayService? _instance;
  static TrayService get instance => _instance ??= TrayService._();
  TrayService._();

  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();

  bool _initialized = false;
  VoidCallback? _onRestore;
  VoidCallback? _onQuit;

  String _currentPeriodLabel = '';
  String _currentClassLabel = '';

  static String get _iconPath {
    // 실행 파일 옆에 있는 아이콘 우선, 없으면 assets 경로
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final ico = '$exeDir\\data\\flutter_assets\\assets\\app_icon.ico';
    if (File(ico).existsSync()) return ico;
    return 'assets/app_icon.ico';
  }

  /// 트레이 초기화
  Future<void> init({
    VoidCallback? onRestore,
    VoidCallback? onQuit,
  }) async {
    if (!Platform.isWindows) return;
    if (_initialized) return;

    _onRestore = onRestore;
    _onQuit = onQuit;

    try {
      // window_manager 초기화
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        skipTaskbar: false,
      );
      await windowManager.waitUntilReadyToShow(windowOptions);

      // 창 닫기 이벤트를 트레이 최소화로 인터셉트
      await windowManager.setPreventClose(true);

      // 트레이 초기화
      await _systemTray.initSystemTray(
        title: 'Bst',
        iconPath: _iconPath,
        toolTip: 'Bst Teacher',
      );

      // 우클릭 컨텍스트 메뉴
      await _updateContextMenu();

      // 트레이 이벤트 등록
      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick ||
            eventName == kSystemTrayEventDoubleClick) {
          _onRestore?.call();
          _appWindow.show();
        }
      });

      _initialized = true;
      debugPrint('[TrayService] System tray initialized.');
    } catch (e) {
      debugPrint('[TrayService] Failed to initialize: $e');
    }
  }

  Future<void> _updateContextMenu() async {
    final periodLine = _currentPeriodLabel.isNotEmpty
        ? '$_currentPeriodLabel — $_currentClassLabel'
        : '수업 없음 — $_currentClassLabel';

    final menu = Menu();
    await menu.buildFrom([
      MenuSeparator(),
      MenuItemLabel(
        label: periodLine,
        enabled: false,
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '🏫  Bst Teacher 열기',
        onClicked: (menuItem) {
          _onRestore?.call();
          _appWindow.show();
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '✕  완전 종료',
        onClicked: (menuItem) {
          _onQuit?.call();
          windowManager.setPreventClose(false).then((_) => windowManager.destroy());
        },
      ),
    ]);
    await _systemTray.setContextMenu(menu);
  }

  /// 교시/반 정보 업데이트 (트레이 툴팁 & 메뉴 실시간 반영)
  Future<void> updateStatus({
    required String periodLabel,   // 예: "3교시 진행 중"
    required String classLabel,    // 예: "2학년 3반"
  }) async {
    if (!Platform.isWindows || !_initialized) return;
    if (_currentPeriodLabel == periodLabel && _currentClassLabel == classLabel) return;

    _currentPeriodLabel = periodLabel;
    _currentClassLabel = classLabel;

    final tooltip = periodLabel.isNotEmpty
        ? '📚 $periodLabel | $classLabel'
        : 'Bst — $classLabel';

    try {
      await _systemTray.setSystemTrayInfo(toolTip: tooltip);
      await _updateContextMenu();
    } catch (e) {
      debugPrint('[TrayService] Failed to update: $e');
    }
  }

  /// 트레이로 최소화 (창 숨기기)
  Future<void> minimizeToTray() async {
    if (!Platform.isWindows || !_initialized) return;
    try {
      await _appWindow.hide();
    } catch (e) {
      debugPrint('[TrayService] minimizeToTray error: $e');
    }
  }

  /// 창 복원
  Future<void> restoreWindow() async {
    if (!Platform.isWindows) return;
    try {
      await _appWindow.show();
    } catch (e) {
      debugPrint('[TrayService] restoreWindow error: $e');
    }
  }

  Future<void> dispose() async {
    if (_initialized) {
      try {
        await _systemTray.destroy();
        await windowManager.setPreventClose(false);
      } catch (_) {}
    }
    _initialized = false;
  }
}

import 'package:flutter/widgets.dart';
import 'plugin_context.dart';

/// 플러그인이 UI 상에 마운트될 슬롯 위치 정의
enum PluginSlot {
  /// 7x2 메인 런처 그리드에 앱 아이콘 형태로 마운트
  launcher,

  /// PPT / HWP / 브라우저 위에 투명 오버레이 레이어로 마운트 (예: bst_pen)
  overlay,

  /// 전체 화면 독점 뷰로 마운트 (예: bst_canva, bst_pdf, bst_video)
  fullScreen,

  /// 교사용 도구 사이드바 패널에 마운트 (예: bst_cast 컨트롤러)
  sidePanel,

  /// 플로팅 도구 모음(FAB 형태)에 마운트
  floatingTool,

  /// UI 없이 백그라운드 서비스로만 동작
  backgroundOnly,
}

/// 플러그인 메타데이터
class PluginManifest {
  final String id; // e.g. 'bst.plugin.pen'
  final String name; // e.g. 'Boardest Pen'
  final String version; // e.g. '1.0.0'
  final String author;
  final String description;
  final PluginSlot targetSlot;
  final Set<String> supportedPlatforms; // 'windows', 'web', 'android', 'macos'
  final List<String> requiredPermissions; // e.g. ['storage', 'cloud', 'events']

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    this.author = 'Boardest Team',
    this.description = '',
    required this.targetSlot,
    this.supportedPlatforms = const {'windows', 'web', 'android', 'macos'},
    this.requiredPermissions = const [],
  });
}

/// 모든 Boardest 플러그인이 구현해야 하는 최상위 인터페이스
abstract class BoardestPlugin {
  PluginManifest get manifest;

  /// 플러그인 초기화 (앱 기동 시 1회 호출)
  Future<void> onInitialize(PluginContext context);

  /// 플러그인 활성화 (UI 슬롯 마운트 직전)
  Future<void> onEnable();

  /// 플러그인 비활성화 (UI 슬롯 언마운트 직후)
  Future<void> onDisable();

  /// 플러그인 종료 및 메모리 해제
  Future<void> onDestroy();

  /// 플러그인 아이콘 위젯
  Widget buildIcon(BuildContext context);

  /// 플러그인 UI 렌더링 엔트리포인트
  Widget buildWidget(BuildContext context, {Map<String, dynamic>? params});
}

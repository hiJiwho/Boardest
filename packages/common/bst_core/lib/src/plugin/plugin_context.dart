import 'bst_api.dart';
import 'bst_plugin.dart';

/// 각 플러그인에 주입되는 런타임 실행 환경 컨텍스트
class PluginContext {
  /// 플러그인 메타데이터
  final PluginManifest manifest;

  /// 호스트 시스템 및 보디스트 전역 API 진입점
  final BstApi api;

  /// 플러그인 인스턴스 전용 설정값 / 파라미터
  final Map<String, dynamic> extra;

  const PluginContext({
    required this.manifest,
    required this.api,
    this.extra = const {},
  });
}

import 'package:flutter/foundation.dart';
import 'bst_api.dart';
import 'bst_plugin.dart';
import 'plugin_context.dart';

/// 플러그인 등록, 활성화, 슬롯별 조회 및 생명주기 관리자
class PluginRegistry {
  PluginRegistry._();
  static final PluginRegistry instance = PluginRegistry._();

  final Map<String, BoardestPlugin> _plugins = {};
  final Set<String> _enabledPluginIds = {};

  List<BoardestPlugin> get allPlugins => _plugins.values.toList();
  List<BoardestPlugin> get enabledPlugins =>
      _plugins.values.where((p) => _enabledPluginIds.contains(p.manifest.id)).toList();

  /// 플러그인 등록 및 초기화
  Future<void> register(BoardestPlugin plugin, {BstApi? customApi}) async {
    final id = plugin.manifest.id;
    if (_plugins.containsKey(id)) {
      debugPrint('[PluginRegistry] Plugin $id already registered. Replacing...');
    }
    _plugins[id] = plugin;

    final api = customApi ?? BstApi.instance;
    final context = PluginContext(
      manifest: plugin.manifest,
      api: api,
    );

    try {
      await plugin.onInitialize(context);
      _enabledPluginIds.add(id);
      await plugin.onEnable();
      debugPrint('[PluginRegistry] ✅ Plugin $id successfully initialized and enabled.');
    } catch (e) {
      debugPrint('[PluginRegistry] ❌ Failed to initialize plugin $id: $e');
    }
  }

  /// 특정 슬롯에 해당하는 활성화된 플러그인 목록 조회
  List<BoardestPlugin> getPluginsForSlot(PluginSlot slot) {
    return enabledPlugins.where((p) => p.manifest.targetSlot == slot).toList();
  }

  /// ID로 특정 플러그인 찾기
  BoardestPlugin? getPlugin(String id) => _plugins[id];

  /// 플러그인 활성화
  Future<void> enablePlugin(String id) async {
    final plugin = _plugins[id];
    if (plugin != null && !_enabledPluginIds.contains(id)) {
      _enabledPluginIds.add(id);
      await plugin.onEnable();
    }
  }

  /// 플러그인 비활성화
  Future<void> disablePlugin(String id) async {
    final plugin = _plugins[id];
    if (plugin != null && _enabledPluginIds.contains(id)) {
      _enabledPluginIds.remove(id);
      await plugin.onDisable();
    }
  }

  /// 모든 플러그인 종료
  Future<void> disposeAll() async {
    for (final plugin in _plugins.values) {
      try {
        await plugin.onDisable();
        await plugin.onDestroy();
      } catch (_) {}
    }
    _plugins.clear();
    _enabledPluginIds.clear();
  }
}

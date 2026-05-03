import 'package:flutter/foundation.dart';

/// 描述一次成功的 `ToolSearch` 加载，用于触发 transcript 顶部的 SnackBar 提示。
@immutable
class AiToolSearchLoadedEvent {
  const AiToolSearchLoadedEvent({
    required this.sessionId,
    required this.loadedNames,
    required this.totalDeferred,
    required this.query,
    required this.revision,
  });

  final String sessionId;
  final List<String> loadedNames;
  final int totalDeferred;
  final String query;
  final int revision;

  int get loadedCount => loadedNames.length;
}

/// 跨调用累计每个会话已通过 `ToolSearch` 加载的 MCP 工具名，并以
/// [ValueListenable] 形式向 UI 广播一次性事件。
class McpLoadedToolsTracker {
  final Map<String, Set<String>> _loadedBySession = <String, Set<String>>{};
  final ValueNotifier<AiToolSearchLoadedEvent?> _signal =
      ValueNotifier<AiToolSearchLoadedEvent?>(null);
  int _revision = 0;

  ValueListenable<AiToolSearchLoadedEvent?> get signal => _signal;

  /// 返回指定会话已加载的 MCP 工具完整名（按字母升序，不可变视图）。
  List<String> namesForSession(String sessionId) {
    final names = _loadedBySession[sessionId];
    if (names == null || names.isEmpty) return const <String>[];
    final sorted = names.toList()..sort();
    return List<String>.unmodifiable(sorted);
  }

  /// 返回指定会话当前已加载的工具集合的只读快照（无序）。控制器在构造
  /// `_applyMcpLazyLoading` 输入时需要 `Set<String>`。
  Set<String> rawSetForSession(String sessionId) {
    final names = _loadedBySession[sessionId];
    if (names == null || names.isEmpty) return const <String>{};
    return Set<String>.unmodifiable(names);
  }

  /// 吸收 ToolSearch 工具结果中 `tool_search_loaded_names` 元数据，更新累计
  /// 集合并广播事件。返回新增（去重前）的名字，若无可吸收则返回空。
  List<String> absorb({
    required String sessionId,
    required Object? loadedNamesRaw,
    Object? totalDeferredRaw,
    Object? queryRaw,
  }) {
    if (loadedNamesRaw is! List || loadedNamesRaw.isEmpty) {
      return const <String>[];
    }
    final bucket = _loadedBySession.putIfAbsent(sessionId, () => <String>{});
    final addedNames = <String>[];
    for (final entry in loadedNamesRaw) {
      if (entry is String && entry.isNotEmpty) {
        bucket.add(entry);
        addedNames.add(entry);
      }
    }
    if (addedNames.isEmpty) return const <String>[];
    _revision += 1;
    _signal.value = AiToolSearchLoadedEvent(
      sessionId: sessionId,
      loadedNames: List<String>.unmodifiable(addedNames),
      totalDeferred: totalDeferredRaw is int
          ? totalDeferredRaw
          : (totalDeferredRaw is num
                ? totalDeferredRaw.toInt()
                : addedNames.length),
      query: queryRaw is String ? queryRaw : '',
      revision: _revision,
    );
    return List<String>.unmodifiable(addedNames);
  }

  /// 清空指定会话的已加载缓存。返回被清除的工具数量。
  int clearSession(String sessionId) {
    final removed = _loadedBySession.remove(sessionId);
    return removed?.length ?? 0;
  }

  void dispose() {
    _signal.dispose();
  }
}

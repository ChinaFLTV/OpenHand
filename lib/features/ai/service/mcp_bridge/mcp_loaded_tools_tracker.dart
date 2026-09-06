import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_clip.dart';

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

/// 单次 `ToolSearch` 加载在历史时间线中的来源类别，用于在 dialog 上贴
/// 一个区分标签（普通 AI session vs Harness phase）。
enum AiToolSearchLoadSource {
  /// 普通 AI 会话内部的 ToolSearch 调用。
  aiSession,

  /// Harness Engineering phase（HarnessApiPhaseRunner）内部的 ToolSearch 调用。
  harnessPhase,
}

/// 单次 `ToolSearch` 加载在历史时间线中的一条记录。
@immutable
class AiToolSearchLoadHistoryEntry {
  const AiToolSearchLoadHistoryEntry({
    required this.timestamp,
    required this.query,
    required this.addedNames,
    required this.totalDeferred,
    this.source = AiToolSearchLoadSource.aiSession,
  });

  /// 触发时间（UTC）。
  final DateTime timestamp;

  /// 模型本次发出的 `query`（已去除首尾空白）。空字符串表示元数据缺失。
  final String query;

  /// 本次新增加载的工具完整名（已按字母排序）。
  final List<String> addedNames;

  /// 本轮 catalog 中处于 deferred 状态的总数（来自工具元数据回填）。
  final int totalDeferred;

  /// 触发来源（普通 AI session / Harness phase），用于 UI 上贴一个识别标签。
  final AiToolSearchLoadSource source;

  int get addedCount => addedNames.length;
}

/// 跨调用累计每个会话已通过 `ToolSearch` 匹配的工具名，并以
/// [ValueListenable] 形式向 UI 广播一次性事件。
class McpLoadedToolsTracker {
  McpLoadedToolsTracker({
    this.maxTrackedSessions = defaultMaxTrackedSessions,
    this.maxNamesPerSession = defaultMaxNamesPerSession,
    this.maxHistoryPerSession = defaultMaxHistoryPerSession,
    this.maxNameCharacters = defaultMaxNameCharacters,
    this.maxQueryCharacters = defaultMaxQueryCharacters,
  }) {
    if (maxTrackedSessions < 1 ||
        maxNamesPerSession < 1 ||
        maxHistoryPerSession < 1 ||
        maxNameCharacters < 1 ||
        maxQueryCharacters < 1) {
      throw ArgumentError('ToolSearch 跟踪上限必须大于零。');
    }
  }

  static const int defaultMaxTrackedSessions = 128;
  static const int defaultMaxNamesPerSession = 4096;
  static const int defaultMaxHistoryPerSession = 500;
  static const int defaultMaxNameCharacters = 512;
  static const int defaultMaxQueryCharacters = 4096;

  final int maxTrackedSessions;
  final int maxNamesPerSession;
  final int maxHistoryPerSession;
  final int maxNameCharacters;
  final int maxQueryCharacters;
  final Map<String, Set<String>> _loadedBySession = <String, Set<String>>{};
  final Map<String, List<AiToolSearchLoadHistoryEntry>> _historyBySession =
      <String, List<AiToolSearchLoadHistoryEntry>>{};
  final ValueNotifier<AiToolSearchLoadedEvent?> _signal =
      ValueNotifier<AiToolSearchLoadedEvent?>(null);
  int _revision = 0;
  bool _disposed = false;

  ValueListenable<AiToolSearchLoadedEvent?> get signal => _signal;

  /// 返回指定会话已加载的工具名（按字母升序，不可变视图）。
  List<String> namesForSession(String sessionId) {
    if (_disposed) return const <String>[];
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null) return const <String>[];
    final names = _loadedBySession[normalizedSessionId];
    if (names == null || names.isEmpty) return const <String>[];
    final sorted = _sortedToolNames(names);
    return List<String>.unmodifiable(sorted);
  }

  /// 返回指定会话的 ToolSearch 加载历史，按时间正序（旧→新）。
  List<AiToolSearchLoadHistoryEntry> historyForSession(String sessionId) {
    if (_disposed) return const <AiToolSearchLoadHistoryEntry>[];
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null) {
      return const <AiToolSearchLoadHistoryEntry>[];
    }
    final history = _historyBySession[normalizedSessionId];
    if (history == null || history.isEmpty) {
      return const <AiToolSearchLoadHistoryEntry>[];
    }
    return List<AiToolSearchLoadHistoryEntry>.unmodifiable(history);
  }

  /// 吸收 ToolSearch 工具结果中 `tool_search_loaded_names` 元数据，更新累计
  /// 集合并广播事件。返回本次真正新增的名字，若无新增则返回空。
  List<String> absorb({
    required String sessionId,
    required Object? loadedNamesRaw,
    Object? totalDeferredRaw,
    Object? queryRaw,
  }) {
    if (_disposed) return const <String>[];
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null ||
        loadedNamesRaw is! List ||
        loadedNamesRaw.isEmpty) {
      return const <String>[];
    }
    final bucket = _loadedBySession.putIfAbsent(
      normalizedSessionId,
      SplayTreeSet<String>.new,
    );
    final addedNames = <String>[];
    for (final entry in loadedNamesRaw.take(maxNamesPerSession * 2)) {
      if (bucket.length >= maxNamesPerSession) break;
      if (entry is String) {
        final name = entry.trim();
        if (name.isNotEmpty &&
            name.length <= maxNameCharacters &&
            !bucket.contains(name) &&
            bucket.length < maxNamesPerSession &&
            bucket.add(name)) {
          addedNames.add(name);
        }
      }
    }
    if (addedNames.isEmpty) {
      if (bucket.isEmpty) _loadedBySession.remove(normalizedSessionId);
      _touchSession(normalizedSessionId);
      return const <String>[];
    }
    _revision += 1;
    final totalDeferred = _nonNegativeIntFromMetadata(
      totalDeferredRaw,
      fallback: addedNames.length,
    );
    final query = queryRaw is String
        ? clipText(queryRaw.trim(), maxQueryCharacters, suffix: '')
        : '';
    final sortedAdded = _sortedToolNames(addedNames);
    final history =
        _historyBySession.putIfAbsent(
          normalizedSessionId,
          () => <AiToolSearchLoadHistoryEntry>[],
        )..add(
          AiToolSearchLoadHistoryEntry(
            timestamp: DateTime.now().toUtc(),
            query: query,
            addedNames: List<String>.unmodifiable(sortedAdded),
            totalDeferred: totalDeferred,
          ),
        );
    if (history.length > maxHistoryPerSession) {
      history.removeRange(0, history.length - maxHistoryPerSession);
    }
    _touchSession(normalizedSessionId);
    _trimTrackedSessions();
    _signal.value = AiToolSearchLoadedEvent(
      sessionId: normalizedSessionId,
      loadedNames: List<String>.unmodifiable(sortedAdded),
      totalDeferred: totalDeferred,
      query: query,
      revision: _revision,
    );
    return List<String>.unmodifiable(sortedAdded);
  }

  /// 清空指定会话的已加载缓存与历史时间线。返回被清除的工具数量。
  int clearSession(String sessionId) {
    if (_disposed) return 0;
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null) return 0;
    final removed = _loadedBySession.remove(normalizedSessionId);
    _historyBySession.remove(normalizedSessionId);
    return removed?.length ?? 0;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loadedBySession.clear();
    _historyBySession.clear();
    _signal.dispose();
  }

  void _touchSession(String sessionId) {
    final loaded = _loadedBySession.remove(sessionId);
    if (loaded != null) _loadedBySession[sessionId] = loaded;
    final history = _historyBySession.remove(sessionId);
    if (history != null) _historyBySession[sessionId] = history;
  }

  void _trimTrackedSessions() {
    while (_loadedBySession.length > maxTrackedSessions) {
      final oldestSessionId = _loadedBySession.keys.first;
      _loadedBySession.remove(oldestSessionId);
      _historyBySession.remove(oldestSessionId);
    }
  }

  static List<String> _sortedToolNames(Iterable<String> names) {
    final sorted = trimmedNonEmptyStrings(
      names,
    ).toSet().toList(growable: false);
    sorted.sort();
    return sorted;
  }

  static int _nonNegativeIntFromMetadata(
    Object? value, {
    required int fallback,
  }) {
    if (value is int) {
      return value < 0 ? fallback : value;
    }
    if (value is num && value.isFinite) {
      final parsed = value.toInt();
      return parsed < 0 ? fallback : parsed;
    }
    return fallback;
  }
}

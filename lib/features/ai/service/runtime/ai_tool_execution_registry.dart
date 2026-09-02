import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';

final Object _registrationZoneKey = Object();
final Stopwatch _toolExecutionStopwatch = Stopwatch()..start();

/// 工具调用执行登记中心 —— 全应用单例。
///
/// 设计目的（参考 Claude Code `AppState.tasks` + `killTask`）：
///   * **可观测性**：任何"正在执行的工具调用"都注册一条不可变 [AiToolExecutionRecord]，
///     UI 可以订阅 [activeRecords] 实时展示运行队列、PID、起始时间、阶段。
///   * **可中断性**：每条记录都关联一个 killer 闭包；调用 [cancelToolCall] 可独立
///     终止某一条工具调用，调用 [cancelSession] 可级联终止某会话名下全部工具调用，
///     互不干扰，避免 per-session cancel Future "一刀切"误杀并行兄弟。
///
/// 该模块只负责"注册-观察-取消"，不直接派生子进程；具体进程派生与信号语义由
/// `AiBashToolService._killProcess` / MCP 实现 / 技能脚本各自负责。
class AiToolExecutionRegistry with ChangeNotifier {
  AiToolExecutionRegistry._internal();

  static const Duration _cancelTimeout = Duration(seconds: 3);
  static const int _cancelConcurrency = 4;

  static final AiToolExecutionRegistry instance =
      AiToolExecutionRegistry._internal();

  /// (sessionId, toolCallId) → 内部条目（含可变 killer / pid）。
  final Map<({String sessionId, String toolCallId}), _RegisteredEntry>
  _entries = <({String sessionId, String toolCallId}), _RegisteredEntry>{};

  /// 当前全部进行中的执行记录，按起始时间升序。
  ///
  /// 返回不可变快照；UI 端在 `addListener` 中重读即可。
  List<AiToolExecutionRecord> get activeRecords {
    final list =
        _entries.values.map((entry) => entry.record).toList(growable: false)
          ..sort((a, b) => a._startedAtElapsed.compareTo(b._startedAtElapsed));
    return List<AiToolExecutionRecord>.unmodifiable(list);
  }

  AiToolExecutionRecord? recordOf({
    required String sessionId,
    required String toolCallId,
  }) => _entries[(sessionId: sessionId.trim(), toolCallId: toolCallId.trim())]
      ?.record;

  /// 注册一条新的工具调用执行；若 [toolCallId] 已存在，先异步回收旧执行，
  /// 避免替换记录后丢失旧进程的 killer。
  ///
  /// 默认 [killer] 为 no-op；具体实现（如 Bash 工具）可在派生 Process 后通过
  /// [attachKiller] 替换为真正的进程终止函数。[attachPid] 可在拿到 pid 后补登。
  AiToolExecutionRegistration? register({
    required String toolCallId,
    required String sessionId,
    required AiToolExecutionKind kind,
    required String displayName,
    Future<void> Function()? killer,
  }) {
    final normalizedToolCallId = toolCallId.trim();
    final normalizedSessionId = sessionId.trim();
    if (normalizedToolCallId.isEmpty || normalizedSessionId.isEmpty) {
      return null;
    }
    final key = (
      sessionId: normalizedSessionId,
      toolCallId: normalizedToolCallId,
    );
    final previous = _entries[key];
    if (previous != null) {
      unawaited(_cancelEntry(previous, '替换重复工具调用：$normalizedToolCallId'));
    }
    final entry = _RegisteredEntry(
      killer: killer ?? () => Future<void>.value(),
      record: AiToolExecutionRecord(
        toolCallId: normalizedToolCallId,
        sessionId: normalizedSessionId,
        kind: kind,
        displayName: displayName,
        startedAt: DateTime.now(),
      ),
    );
    _entries[key] = entry;
    notifyListeners();
    return AiToolExecutionRegistration._(key, entry);
  }

  void attachPid(String toolCallId, int pid) {
    final entry = _entryForMutation(toolCallId);
    if (entry == null || entry.cancelRequested) return;
    entry.record = entry.record.copyWith(pid: pid);
    notifyListeners();
  }

  void attachKiller(String toolCallId, Future<void> Function() killer) {
    final entry = _entryForMutation(toolCallId);
    if (entry == null) return;
    if (entry.cancelRequested) {
      unawaited(_runKiller(killer, '取消迟到的工具调用：${entry.record.toolCallId}'));
      return;
    }
    entry.killer = killer;
  }

  /// 在注册令牌对应的异步 Zone 中执行，防止重复 ID 的旧执行污染新记录。
  Future<T> runRegistered<T>(
    AiToolExecutionRegistration? registration,
    Future<T> Function() action,
  ) {
    if (registration == null) return action();
    return runZoned(
      action,
      zoneValues: <Object?, Object?>{_registrationZoneKey: registration},
    );
  }

  /// 注销令牌对应的工具调用；已被同 ID 新执行替换时保持新记录不变。
  void unregister(AiToolExecutionRegistration registration) {
    if (identical(_entries[registration._key], registration._entry)) {
      _entries.remove(registration._key);
      notifyListeners();
    }
  }

  /// 主动终止指定工具调用。
  ///
  /// 调用方应在 UI 的"工具卡片右上角 X 按钮"或全局命令面板里触发。
  /// 真正的进程信号由注册时附带的 killer 决定（Bash 工具会发 SIGTERM→SIGKILL）。
  Future<void> cancelToolCall({
    required String sessionId,
    required String toolCallId,
  }) async {
    final normalizedSessionId = sessionId.trim();
    final normalizedToolCallId = toolCallId.trim();
    final entry =
        _entries[(
          sessionId: normalizedSessionId,
          toolCallId: normalizedToolCallId,
        )];
    if (entry == null) return;
    await _cancelEntry(entry, '取消工具调用：$normalizedToolCallId');
  }

  /// 仅取消令牌对应的执行，避免旧执行超时后误杀同 ID 的新执行。
  Future<void> cancelRegistration(
    AiToolExecutionRegistration? registration,
  ) async {
    if (registration == null) return;
    await _cancelEntry(
      registration._entry,
      '取消工具调用：${registration.toolCallId}',
    );
  }

  /// 级联取消某 sessionId 名下全部进行中的工具调用。
  Future<void> cancelSession(String sessionId) async {
    final targets = _entries.values
        .where((entry) => entry.record.sessionId == sessionId)
        .toList(growable: false);
    await forEachIndexWithConcurrencyLimit(
      itemCount: targets.length,
      maxConcurrency: _cancelConcurrency,
      task: (index) {
        final entry = targets[index];
        return _cancelEntry(entry, '取消会话工具调用：${entry.record.toolCallId}');
      },
    );
  }

  Future<void> _cancelEntry(_RegisteredEntry entry, String action) async {
    entry.cancelRequested = true;
    if (!entry.cancelCompleter.isCompleted) entry.cancelCompleter.complete();
    final future = entry.cancelFuture ?? _runKiller(entry.killer, action);
    entry.cancelFuture ??= future;
    await future;
    final key = (
      sessionId: entry.record.sessionId,
      toolCallId: entry.record.toolCallId,
    );
    if (identical(_entries[key], entry)) {
      _entries.remove(key);
      notifyListeners();
    }
  }

  Future<void> _runKiller(Future<void> Function() killer, String action) async {
    await runAsyncCleanupBounded(
      killer,
      timeout: _cancelTimeout,
      onError: (error, stack) =>
          silentLog('ai_tool_exec_registry', action, error, stack),
    );
  }

  _RegisteredEntry? _entryForMutation(String toolCallId) {
    final normalizedToolCallId = toolCallId.trim();
    if (normalizedToolCallId.isEmpty) return null;
    final registration =
        Zone.current[_registrationZoneKey] as AiToolExecutionRegistration?;
    if (registration != null) {
      if (registration.toolCallId != normalizedToolCallId) return null;
      // 已替换的执行仍持有独立记录，便于取消后迟到的进程绑定清理器，
      // 同时避免改动同 ID 的新记录。
      return registration._entry;
    }
    _RegisteredEntry? match;
    for (final entry in _entries.values) {
      if (entry.record.toolCallId != normalizedToolCallId) continue;
      if (match != null) return null;
      match = entry;
    }
    return match;
  }
}

/// 单次工具执行的不可伪造注册令牌。
class AiToolExecutionRegistration {
  const AiToolExecutionRegistration._(this._key, this._entry);

  final ({String sessionId, String toolCallId}) _key;
  final _RegisteredEntry _entry;

  String get sessionId => _key.sessionId;
  String get toolCallId => _key.toolCallId;

  Future<void> get cancelSignal => _entry.cancelCompleter.future;
  bool get isCancellationRequested => _entry.cancelRequested;
}

/// 工具调用类别。
enum AiToolExecutionKind { builtin, mcp, skill }

/// 单条工具调用执行记录（不可变）。
@immutable
class AiToolExecutionRecord {
  AiToolExecutionRecord({
    required this.toolCallId,
    required this.sessionId,
    required this.kind,
    required this.displayName,
    required this.startedAt,
    this.pid,
    Duration? startedAtElapsed,
  }) : _startedAtElapsed = startedAtElapsed ?? _toolExecutionStopwatch.elapsed;

  final String toolCallId;
  final String sessionId;
  final AiToolExecutionKind kind;
  final String displayName;
  final DateTime startedAt;
  final Duration _startedAtElapsed;

  /// 已派生子进程时的进程 ID；HTTP/纯 Dart 工具为 null。
  final int? pid;

  Duration get elapsed => _toolExecutionStopwatch.elapsed - _startedAtElapsed;

  AiToolExecutionRecord copyWith({int? pid}) => AiToolExecutionRecord(
    toolCallId: toolCallId,
    sessionId: sessionId,
    kind: kind,
    displayName: displayName,
    startedAt: startedAt,
    pid: pid ?? this.pid,
    startedAtElapsed: _startedAtElapsed,
  );
}

class _RegisteredEntry {
  _RegisteredEntry({required this.killer, required this.record});

  Future<void> Function() killer;
  AiToolExecutionRecord record;
  final Completer<void> cancelCompleter = Completer<void>();
  bool cancelRequested = false;
  Future<void>? cancelFuture;
}

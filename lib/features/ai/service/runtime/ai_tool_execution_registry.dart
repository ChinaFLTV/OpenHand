import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';

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

  /// toolCallId → 内部条目（含可变 killer / pid）。
  final Map<String, _RegisteredEntry> _entries = <String, _RegisteredEntry>{};

  /// 当前全部进行中的执行记录，按起始时间升序。
  ///
  /// 返回不可变快照；UI 端在 `addListener` 中重读即可。
  List<AiToolExecutionRecord> get activeRecords {
    final list =
        _entries.values.map((entry) => entry.record).toList(growable: false)
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return List<AiToolExecutionRecord>.unmodifiable(list);
  }

  AiToolExecutionRecord? recordOf(String toolCallId) =>
      _entries[toolCallId]?.record;

  /// 注册一条新的工具调用执行；若 [toolCallId] 已存在，先异步回收旧执行，
  /// 避免替换记录后丢失旧进程的 killer。
  ///
  /// 默认 [killer] 为 no-op；具体实现（如 Bash 工具）可在派生 Process 后通过
  /// [attachKiller] 替换为真正的进程终止函数。[attachPid] 可在拿到 pid 后补登。
  void register({
    required String toolCallId,
    required String sessionId,
    required AiToolExecutionKind kind,
    required String displayName,
    Future<void> Function()? killer,
  }) {
    if (toolCallId.isEmpty) {
      return;
    }
    final previous = _entries[toolCallId];
    if (previous != null) {
      unawaited(_cancelEntry(previous, 'replace duplicate $toolCallId'));
    }
    _entries[toolCallId] = _RegisteredEntry(
      killer: killer ?? () => Future<void>.value(),
      record: AiToolExecutionRecord(
        toolCallId: toolCallId,
        sessionId: sessionId,
        kind: kind,
        displayName: displayName,
        startedAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void attachPid(String toolCallId, int pid) {
    final entry = _entries[toolCallId];
    if (entry == null) return;
    entry.record = entry.record.copyWith(pid: pid);
    notifyListeners();
  }

  void attachKiller(String toolCallId, Future<void> Function() killer) {
    final entry = _entries[toolCallId];
    if (entry == null) return;
    entry.killer = killer;
  }

  /// 注销一条工具调用执行；幂等。
  void unregister(String toolCallId) {
    if (_entries.remove(toolCallId) != null) {
      notifyListeners();
    }
  }

  /// 主动终止指定工具调用。
  ///
  /// 调用方应在 UI 的"工具卡片右上角 X 按钮"或全局命令面板里触发。
  /// 真正的进程信号由注册时附带的 killer 决定（Bash 工具会发 SIGTERM→SIGKILL）。
  Future<void> cancelToolCall(String toolCallId) async {
    final entry = _entries[toolCallId];
    if (entry == null) return;
    await _cancelEntry(entry, 'cancel $toolCallId');
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
        return _cancelEntry(entry, 'cancel-session ${entry.record.toolCallId}');
      },
    );
  }

  Future<void> _cancelEntry(_RegisteredEntry entry, String action) async {
    await runAsyncCleanupBounded(
      entry.killer,
      timeout: _cancelTimeout,
      onError: (error, stack) =>
          silentLog('ai_tool_exec_registry', action, error, stack),
    );
  }
}

/// 工具调用类别。
enum AiToolExecutionKind { builtin, mcp, skill }

/// 单条工具调用执行记录（不可变）。
@immutable
class AiToolExecutionRecord {
  const AiToolExecutionRecord({
    required this.toolCallId,
    required this.sessionId,
    required this.kind,
    required this.displayName,
    required this.startedAt,
    this.pid,
  });

  final String toolCallId;
  final String sessionId;
  final AiToolExecutionKind kind;
  final String displayName;
  final DateTime startedAt;

  /// 已派生子进程时的进程 ID；HTTP/纯 Dart 工具为 null。
  final int? pid;

  Duration get elapsed => DateTime.now().difference(startedAt);

  AiToolExecutionRecord copyWith({int? pid}) => AiToolExecutionRecord(
    toolCallId: toolCallId,
    sessionId: sessionId,
    kind: kind,
    displayName: displayName,
    startedAt: startedAt,
    pid: pid ?? this.pid,
  );
}

class _RegisteredEntry {
  _RegisteredEntry({required this.killer, required this.record});

  Future<void> Function() killer;
  AiToolExecutionRecord record;
}

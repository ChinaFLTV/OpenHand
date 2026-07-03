import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../../app/model/cron_config.dart';
import '../../app/support/openhand_notification_service.dart';
import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/timer_safety.dart';
import '../mcp/index.dart';
import 'data/crons_store.dart';
import 'model/cron_parser.dart';
import 'service/cron_executor.dart';

/// Controller for managing cron job configurations and scheduling.
///
/// Follows the same ChangeNotifier + mutation queue pattern as HooksController.
class CronsController extends ChangeNotifier with WidgetsBindingObserver {
  CronsController._({
    required CronsStore store,
    required List<CronEntry> entries,
    bool isLoading = false,
  }) : _store = store,
       _entries = entries,
       _entriesView = List<CronEntry>.unmodifiable(entries),
       _isLoading = isLoading;

  /// Constructs a [CronsController] synchronously without performing the
  /// initial sqlite load, system seeding, signal-watcher binding, or
  /// scheduler startup. Reports `isLoading == true` until the caller awaits
  /// (or fires-and-forgets) [initialize].
  ///
  /// Used by `main.dart` to keep cron sqlite I/O off the boot critical
  /// path. The user-visible `CronsView` and any UI that reads `entries`
  /// must tolerate an empty list while `isLoading == true`.
  factory CronsController.uninitialized({CronsStore? store}) {
    return CronsController._(
      store: store ?? CronsStore(),
      entries: <CronEntry>[],
      isLoading: true,
    );
  }

  static const Uuid _uuid = Uuid();

  static Future<CronsController> create({CronsStore? store}) async {
    final controller = CronsController.uninitialized(store: store);
    await controller.initialize();
    return controller;
  }

  /// Performs the deferred boot work: sqlite table ensure, full entries
  /// load, system-managed Hermes Talker entry seeding/refresh, app lifecycle
  /// observer + signal watcher registration, and scheduler startup. Safe to
  /// invoke at most once — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_isDisposed || _hasInitialized) return;
    _hasInitialized = true;
    try {
      await _store.ensureTable();
      final entries = await _store.loadAll();
      // Seed the Hermes Talker self-learning system entry if needed, then
      // refresh only system-managed display/scheduling fields. User-toggleable
      // fields and runtime state are preserved.
      final existingIndex = entries.indexWhere(
        (e) => e.id == selfLearningSystemEntryId,
      );
      if (existingIndex == -1) {
        entries.add(_buildSelfLearningSystemEntry());
        await _store.saveAll(entries);
      } else {
        final existing = entries[existingIndex];
        final canonical = _buildSelfLearningSystemEntry();
        final refreshed = existing.copyWith(
          name: canonical.name,
          description: canonical.description,
          scriptType: canonical.scriptType,
          cronExpression: canonical.cronExpression,
          timeoutSeconds: canonical.timeoutSeconds,
          tags: canonical.tags,
          onSuccessNotify: canonical.onSuccessNotify,
          onFailureNotify: canonical.onFailureNotify,
          onTimeoutNotify: canonical.onTimeoutNotify,
        );
        final needsRefresh =
            existing.name != refreshed.name ||
            existing.description != refreshed.description ||
            existing.scriptType != refreshed.scriptType ||
            existing.cronExpression != refreshed.cronExpression ||
            existing.timeoutSeconds != refreshed.timeoutSeconds;
        if (needsRefresh) {
          entries[existingIndex] = refreshed;
          await _store.saveAll(entries);
        }
      }
      // MCP 关键词倒排索引重建系统条目。该条目「特殊」在：
      //   * 是否存在完全由「全局设置 → MCP → 更新关键词映射模式」驱动；
      //   * 冷启动模式下条目应不存在（彻底删除）；
      //   * 定时间隔 / 每日定点模式下条目存在且强制 enabled=true，UI 禁止切换；
      // 因此启动期不主动 seed —— 由 main.dart 的 IIFE 在 initialize() 之后
      // 立即调用 updateMcpKeywordIndexSchedule(...) 同步当前设置。这里仅在
      // 已存在时刷新静态字段（名称/描述/超时/通知策略/tags），保持 cron
      // 表达式与 enabled 不变 —— 这两项由 settings 联动维护。
      final keywordIndex = entries.indexWhere(
        (e) => e.id == mcpKeywordIndexSystemEntryId,
      );
      if (keywordIndex != -1) {
        final existing = entries[keywordIndex];
        final canonical = _buildMcpKeywordIndexSystemEntry();
        final refreshed = existing.copyWith(
          name: canonical.name,
          description: canonical.description,
          scriptType: canonical.scriptType,
          timeoutSeconds: canonical.timeoutSeconds,
          tags: canonical.tags,
          onSuccessNotify: canonical.onSuccessNotify,
          onFailureNotify: canonical.onFailureNotify,
          onTimeoutNotify: canonical.onTimeoutNotify,
        );
        if (existing.name != refreshed.name ||
            existing.description != refreshed.description ||
            existing.scriptType != refreshed.scriptType ||
            existing.timeoutSeconds != refreshed.timeoutSeconds) {
          entries[keywordIndex] = refreshed;
          await _store.saveAll(entries);
        }
      }
      if (_isDisposed) return;
      _entries = entries;
      _entriesView = List<CronEntry>.unmodifiable(entries);
      WidgetsBinding.instance.addObserver(this);
      _bindProcessSignalWatchers();
      _startScheduler();
    } finally {
      _isLoading = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  /// Stable id of the system-seeded Hermes Talker self-learning cron entry.
  static const String selfLearningSystemEntryId = 'self_learning.hermes_talker';

  /// Tag that marks a cron entry as system-managed (read-only in UI).
  static const String systemTag = 'system';

  /// Tag that associates a system entry with the Hermes Talker template.
  static const String hermesTalkerTag = 'hermes_talker';

  static CronEntry _buildSelfLearningSystemEntry() {
    return const CronEntry(
      id: selfLearningSystemEntryId,
      name: 'Hermes Talker 自我学习',
      description:
          '系统内置：每 5 分钟触发一次 Hermes Talker 自我学习，'
          '让 AI 在后台把近期对话中沉淀的知识与偏好静默写入记忆 / 画像 / 技能库。'
          '本任务为系统管理，无法删除；如需暂停，请使用右侧开关关闭。',
      scriptType: CronScriptType.agent,
      cronExpression: '*/5 * * * *',
      timeoutSeconds: 600,
      tags: <String>[systemTag, hermesTalkerTag],
      onSuccessNotify: CronNotifyType.none,
      onFailureNotify: CronNotifyType.log,
      onTimeoutNotify: CronNotifyType.log,
    );
  }

  /// MCP 关键词倒排索引重建系统条目的稳定 id。
  static const String mcpKeywordIndexSystemEntryId =
      'mcp_keyword_index.rebuild';

  /// 标记 MCP 关键词倒排索引系统任务的 tag。
  static const String mcpKeywordIndexTag = 'mcp_keyword_index';

  static CronEntry _buildMcpKeywordIndexSystemEntry() {
    return const CronEntry(
      id: mcpKeywordIndexSystemEntryId,
      name: 'MCP 关键词倒排索引重建',
      description:
          '系统内置：按「全局设置 → MCP → 更新关键词映射模式」驱动。'
          '冷启动模式下不存在；定时间隔 / 每日定点模式下由系统创建并保持启用。'
          '该任务的启用状态由设置项强制锁定，无法手动开关，亦无法删除；'
          '可查看执行历史 / 立即执行一次。',
      scriptType: CronScriptType.agent,
      cronExpression: '0 2 * * *',
      timeoutSeconds: 1800,
      tags: <String>[systemTag, mcpKeywordIndexTag],
      onSuccessNotify: CronNotifyType.none,
      onFailureNotify: CronNotifyType.log,
      onTimeoutNotify: CronNotifyType.log,
    );
  }

  /// 根据「更新关键词映射模式」设置同步 MCP 关键词倒排索引系统 cron 条目：
  ///  - cold-start：彻底删除条目（如已存在），并取消已绑定的定时器；
  ///  - interval / scheduled：若条目不存在则创建，存在则改写 cron 表达式，
  ///    并强制 enabled = true。
  ///
  /// 该任务的存在与否完全由设置项驱动，UI 禁止用户手动启用/停用/删除。
  Future<void> updateMcpKeywordIndexSchedule({
    required McpKeywordIndexUpdateMode mode,
    required int intervalValue,
    required McpKeywordIndexIntervalUnit intervalUnit,
    required String scheduledTimeOfDay,
  }) async {
    if (!_hasInitialized) return;
    await _commitMutation(() async {
      final index = _entries.indexWhere(
        (e) => e.id == mcpKeywordIndexSystemEntryId,
      );
      if (mode == McpKeywordIndexUpdateMode.coldStart) {
        if (index == -1) return false;
        final removed = _entries[index];
        _setEntries(
          _entries.where((e) => e.id != mcpKeywordIndexSystemEntryId).toList(),
        );
        await _store.saveAll(_entries);
        _cancelTimer(removed.id);
        return true;
      }
      final cronExpression = buildMcpKeywordIndexCronExpression(
        mode: mode,
        intervalValue: intervalValue,
        intervalUnit: intervalUnit,
        scheduledTimeOfDay: scheduledTimeOfDay,
      );
      if (index == -1) {
        final canonical = _buildMcpKeywordIndexSystemEntry();
        final created = canonical.copyWith(
          cronExpression: cronExpression,
          enabled: true,
        );
        _setEntries(<CronEntry>[..._entries, created]);
        await _store.saveAll(_entries);
        _scheduleJob(created);
        return true;
      }
      final existing = _entries[index];
      if (existing.cronExpression == cronExpression && existing.enabled) {
        return false;
      }
      final refreshed = existing.copyWith(
        cronExpression: cronExpression,
        enabled: true,
      );
      _setEntries(<CronEntry>[
        ..._entries.sublist(0, index),
        refreshed,
        ..._entries.sublist(index + 1),
      ]);
      await _store.saveAll(_entries);
      _cancelTimer(refreshed.id);
      _scheduleJob(refreshed);
      return true;
    });
  }

  final CronsStore _store;
  List<CronEntry> _entries;
  List<CronEntry> _entriesView;
  bool _isLoading;
  bool _hasInitialized = false;
  bool _isDisposed = false;
  bool _isShuttingDown = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  Future<void> _mutationQueue = Future<void>.value();

  /// Active timers keyed by cron job id.
  final Map<String, Timer> _scheduledTimers = {};

  /// Currently running jobs keyed by cron job id.
  final Map<String, CronExecutionHandle> _runningJobs = {};

  /// Currently running agent-typed jobs keyed by cron job id. Separate from
  /// [_runningJobs] because agent jobs don't spawn a process and therefore
  /// have no [CronExecutionHandle] to track; we only need an overlap guard.
  final Set<String> _runningAgentJobIds = <String>{};

  StreamSubscription<ProcessSignal>? _sigTermWatcher;
  StreamSubscription<ProcessSignal>? _sigIntWatcher;

  /// Cached execution history keyed by cron job id.
  final Map<String, List<CronExecutionRecord>> _historyCache = {};

  /// Detected system users for the run-as-user picker.
  List<String> _systemUsers = const <String>['root'];

  List<CronEntry> get entries => _entriesView;

  /// 暴露内部 store 句柄以便"应用数据 → 数据清理"模块在不增设额外
  /// 控制器方法的前提下查询执行历史的体积估算。**只读**用法；写入仍走
  /// controller 的高层 API（例如 [clearAllHistory]）以保证内存缓存与
  /// notifyListeners 时序一致。
  CronsStore get store => _store;
  bool get isLoading => _isLoading;
  List<String> get systemUsers => _systemUsers;

  List<CronExecutionRecord> historyFor(String cronId) {
    return _historyCache[cronId] ?? const <CronExecutionRecord>[];
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_hasInitialized) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _isDisposed = true;
    _shutdownSchedulersAndJobs();
    _sigTermWatcher?.cancel();
    _sigIntWatcher?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.detached) {
      _shutdownSchedulersAndJobs();
      return;
    }
    if (!_isDisposed && !_isShuttingDown) {
      _restartScheduler();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  Future<bool> addCron(CronEntry entry) async {
    return _commitMutation(() async {
      final now = DateTime.now();
      final newEntry = entry.copyWith(
        id: entry.id.isEmpty ? _uuid.v4() : null,
        createdAt: now,
        updatedAt: now,
      );
      _setEntries(<CronEntry>[..._entries, newEntry]);
      await _store.saveAll(_entries);
      _scheduleJob(newEntry);
      return true;
    });
  }

  Future<bool> updateCron(CronEntry updated) async {
    return _commitMutation(() async {
      final index = _entries.indexWhere((item) => item.id == updated.id);
      if (index < 0) return false;
      final entry = updated.copyWith(updatedAt: DateTime.now());
      _setEntries(<CronEntry>[
        ..._entries.sublist(0, index),
        entry,
        ..._entries.sublist(index + 1),
      ]);
      await _store.saveAll(_entries);
      _cancelTimer(entry.id);
      _scheduleJob(entry);
      return true;
    });
  }

  Future<bool> deleteCron(String id) async {
    return _commitMutation(() async {
      final before = _entries.length;
      final target = _entries.firstWhere(
        (item) => item.id == id,
        orElse: () => _missingSentinel,
      );
      if (identical(target, _missingSentinel)) return false;
      // System-managed entries are not user-deletable.
      if (target.tags.contains(systemTag)) return false;
      _setEntries(_entries.where((item) => item.id != id).toList());
      if (_entries.length == before) return false;
      await _store.saveAll(_entries);
      _cancelTimer(id);
      _historyCache.remove(id);
      await _store.deleteHistoryForCron(id);
      return true;
    });
  }

  static const CronEntry _missingSentinel = CronEntry(id: '', name: '');

  /// `appContext` 中存放 Hermes Talker 单次 tick 的会话级 JSON 报告
  /// （`List<SelfLearningSessionReport.toJson()>` 序列化结果）的键名。
  /// 由 `main.dart` 的 agent handler 写入，由 Crons 历史 UI 解析渲染。
  static const String hermesTalkerReportsKey = 'hermes_talker.reports';

  /// `appContext` 中存放 Hermes Talker 单次 tick 聚合统计的键名
  /// （`{scanned, triggered, skipped, errors}` 的 JSON 编码）。
  static const String hermesTalkerStatsKey = 'hermes_talker.stats';

  /// Handler invoked for `CronScriptType.agent` entries. Bootstrap injects
  /// this via [registerAgentHandler] to plug the Hermes Talker
  /// `SelfLearningScheduler`. Handlers must never throw.
  ///
  /// 返回的 [AgentHandlerResult.stdout] 写入历史记录的 stdout 字段，
  /// [AgentHandlerResult.appContext] 写入历史记录的 app_context 字段，
  /// 用于在 Crons 历史详情中展示富信息（例如 Hermes Talker 的会话报告）。
  Future<AgentHandlerResult> Function(CronEntry entry)? _agentHandler;

  /// Registers (or replaces) the in-process handler for Agent-typed cron
  /// entries. Passing `null` removes the handler.
  void registerAgentHandler(
    Future<AgentHandlerResult> Function(CronEntry entry)? handler,
  ) {
    _agentHandler = handler;
  }

  Future<void> _executeAgentJob(
    CronEntry entry, {
    required String triggerType,
  }) async {
    final startedAt = DateTime.now();
    String stdout = '';
    Map<String, String> appContext = const <String, String>{};
    String status = 'success';
    String? errorMessage;
    try {
      final handler = _agentHandler;
      if (handler == null) {
        stdout = 'noop: agent handler not registered';
      } else {
        final result = await handler(entry);
        stdout = result.stdout;
        appContext = result.appContext;
      }
    } catch (error) {
      status = 'failed';
      errorMessage = '$error';
    }

    final record = CronExecutionRecord(
      id: _uuid.v4(),
      cronId: entry.id,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      status: status,
      stdout: stdout,
      stderr: errorMessage ?? '',
      errorMessage: errorMessage,
      triggerType: triggerType,
      appContext: appContext,
    );
    try {
      await _store.insertHistory(record);
      await _store.pruneHistory(entry.id);
    } catch (error, stack) {
      silentLog('crons_controller', 'persist agent history', error, stack);
      // ignore history persistence errors — the scheduler will try again.
    }
    final cached = _historyCache[entry.id] ?? <CronExecutionRecord>[];
    _historyCache[entry.id] = [record, ...cached].take(50).toList();

    _updateEntry(
      entry.id,
      (e) => e.copyWith(
        status: status == 'success' ? CronJobStatus.idle : CronJobStatus.failed,
        lastRunAt: startedAt,
        consecutiveFailures: status == 'success'
            ? 0
            : entry.consecutiveFailures + 1,
        updatedAt: DateTime.now(),
      ),
    );
    try {
      final updated = _entries.firstWhere(
        (e) => e.id == entry.id,
        orElse: () => entry,
      );
      await _store.updateOne(updated);
    } catch (error, stack) {
      silentLog(
        'crons_controller',
        'persist entry after run completion',
        error,
        stack,
      );
    }
    // Re-schedule next run.
    final current = _entries.firstWhere(
      (e) => e.id == entry.id,
      orElse: () => entry,
    );
    _scheduleJob(current);
    notifyListeners();
  }

  Future<bool> toggleCronEnabled(String id, {required bool enabled}) async {
    return _commitMutation(() async {
      final index = _entries.indexWhere((item) => item.id == id);
      if (index < 0) return false;
      final entry = _entries[index].copyWith(
        enabled: enabled,
        status: enabled ? CronJobStatus.idle : CronJobStatus.paused,
        updatedAt: DateTime.now(),
      );
      _setEntries(<CronEntry>[
        ..._entries.sublist(0, index),
        entry,
        ..._entries.sublist(index + 1),
      ]);
      await _store.saveAll(_entries);
      if (enabled) {
        _scheduleJob(entry);
      } else {
        _cancelTimer(id);
      }
      return true;
    });
  }

  /// Manually trigger a cron job right now.
  Future<void> runNow(String id) async {
    if (!_canExecuteInCurrentState) return;
    final index = _entries.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final entry = _entries[index];
    if (!entry.enabled) return;
    // Agent crons dispatch via [_agentHandler] and do not require a script payload.
    if (entry.scriptType != CronScriptType.agent && !entry.hasScript) return;
    await _executeJob(entry, triggerType: 'manual');
  }

  Future<void> loadHistory(String cronId) async {
    final records = await _store.loadHistory(cronId);
    _historyCache[cronId] = records;
    notifyListeners();
  }

  Future<bool> clearHistoryForCron(String cronId) async {
    return _commitMutation(() async {
      await _store.deleteHistoryForCron(cronId);
      _historyCache.remove(cronId);
      return true;
    });
  }

  Future<bool> deleteHistoryRecord(String cronId, String recordId) async {
    return _commitMutation(() async {
      await _store.deleteHistoryRecord(recordId);
      final cached = _historyCache[cronId];
      if (cached != null) {
        cached.removeWhere((r) => r.id == recordId);
      }
      return true;
    });
  }

  /// 2026-04-25 — 删除所有 [cutoff] 之前的执行历史，返回受影响的行数。
  /// 同步刷新内存缓存以避免 UI 看到陈旧数据。
  /// 这是一个"尽力而为"的清理，调用方负责自身的异常兜底；
  /// 失败时返回 0，不抛异常。
  Future<int> purgeHistoryOlderThan(DateTime cutoff) async {
    int affected = 0;
    try {
      affected = await _store.deleteHistoryOlderThan(cutoff);
    } catch (error, stack) {
      silentLog('crons_controller', 'purgeHistoryOlderThan', error, stack);
      return 0;
    }
    if (affected == 0) return 0;
    final cutoffKey = cutoff;
    for (final cronId in _historyCache.keys.toList()) {
      final cached = _historyCache[cronId];
      if (cached == null) continue;
      _historyCache[cronId] = cached
          .where((r) => r.startedAt.isAfter(cutoffKey))
          .toList(growable: false);
    }
    notifyListeners();
    return affected;
  }

  /// 2026-04-26 — 清空全部 cron 执行历史。返回受影响行数；失败返回 0
  /// 并 silentLog，不抛异常。仅由全局设置中的"日志清理 / 全部数据清空"
  /// 触发，调用方负责弹窗二次确认。
  Future<int> clearAllHistory() async {
    int affected = 0;
    try {
      affected = await _store.deleteAllHistory();
    } catch (error, stack) {
      silentLog('crons_controller', 'clearAllHistory', error, stack);
      return 0;
    }
    if (_historyCache.isNotEmpty) {
      _historyCache.clear();
    }
    notifyListeners();
    return affected;
  }

  /// 2026-05-23 — 清空全部"非系统"cron 任务（保留 Hermes Talker / MCP
  /// 关键词索引等带 [systemTag] 的内置条目，避免清理后丢失自学习能力）。
  /// 同步取消调度、清理历史缓存，返回受影响条目数。
  Future<int> clearAllNonSystemCrons() async {
    int removed = 0;
    await _commitMutation(() async {
      final preserved = _entries
          .where((entry) => entry.tags.contains(systemTag))
          .toList();
      removed = _entries.length - preserved.length;
      if (removed == 0) return true;
      for (final entry in _entries) {
        if (entry.tags.contains(systemTag)) continue;
        _cancelTimer(entry.id);
        _historyCache.remove(entry.id);
        try {
          await _store.deleteHistoryForCron(entry.id);
        } catch (error, stack) {
          silentLog(
            'crons_controller',
            'clearAllNonSystemCrons/history/${entry.id}',
            error,
            stack,
          );
        }
      }
      _setEntries(preserved);
      await _store.saveAll(preserved);
      return true;
    });
    return removed;
  }

  Future<void> refresh() async {
    final entries = await _store.loadAll();
    _setEntries(entries);
    _restartScheduler();
    notifyListeners();
  }

  /// Scan system users available on this machine.
  Future<void> scanSystemUsers() async {
    try {
      if (Platform.isWindows) {
        _systemUsers = const <String>['SYSTEM'];
        notifyListeners();
        return;
      }
      final result = await runProcessWithTimeout('cut', const <String>[
        '-d:',
        '-f1',
        '/etc/passwd',
      ], tag: 'crons_controller');
      if (result != null && result.exitCode == 0) {
        final users = trimmedNonEmptyStrings(
          (result.stdout as String).split('\n'),
        ).where((s) => !s.startsWith('#')).toList();
        if (users.isNotEmpty) {
          // Ensure 'root' is at the front.
          users.remove('root');
          _systemUsers = <String>['root', ...users];
        }
      }
    } catch (error, stack) {
      silentLog('crons_controller', 'scan system users', error, stack);
      // Keep default ['root'].
    }
    notifyListeners();
  }

  void _bindProcessSignalWatchers() {
    if (kIsWeb || Platform.isWindows) return;
    try {
      _sigTermWatcher = ProcessSignal.sigterm.watch().listen((_) {
        _shutdownSchedulersAndJobs();
      });
      _sigIntWatcher = ProcessSignal.sigint.watch().listen((_) {
        _shutdownSchedulersAndJobs();
      });
    } catch (error, stack) {
      silentLog(
        'crons_controller',
        'bind process signal watchers',
        error,
        stack,
      );
      // Signal streams are not available on all desktop runtimes.
    }
  }

  bool get _canExecuteInCurrentState {
    return !_isDisposed &&
        !_isShuttingDown &&
        _appLifecycleState != AppLifecycleState.detached;
  }

  void _shutdownSchedulersAndJobs() {
    if (_isShuttingDown) return;
    _isShuttingDown = true;
    for (final timer in _scheduledTimers.values) {
      timer.cancel();
    }
    _scheduledTimers.clear();
    for (final job in _runningJobs.values) {
      job.cancel();
    }
    _runningJobs.clear();
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  void _startScheduler() {
    if (!_canExecuteInCurrentState) return;
    scanSystemUsers();
    for (final entry in _entries) {
      _scheduleJob(entry, refreshEntriesView: false);
    }
    _refreshEntriesView();
  }

  void _restartScheduler() {
    if (!_canExecuteInCurrentState) return;
    for (final timer in _scheduledTimers.values) {
      timer.cancel();
    }
    _scheduledTimers.clear();
    _startScheduler();
  }

  void _cancelTimer(String id) {
    _scheduledTimers[id]?.cancel();
    _scheduledTimers.remove(id);
  }

  void _scheduleJob(CronEntry entry, {bool refreshEntriesView = true}) {
    if (!_canExecuteInCurrentState) return;
    _cancelTimer(entry.id);
    if (!entry.enabled) return;
    // Agent crons are scheduled without a script payload; execution is routed
    // through [_agentHandler] rather than [CronExecutor].
    if (entry.scriptType != CronScriptType.agent && !entry.hasScript) return;

    final nextRun = CronParser.nextRun(entry.cronExpression);
    if (nextRun == null) return;

    final delay = nextRun.difference(DateTime.now());
    if (delay.isNegative) {
      // If already past, schedule for 1 second from now.
      _scheduledTimers[entry.id] = startSafeTimer(
        const Duration(seconds: 1),
        () => _onTimerFired(entry.id),
      );
    } else {
      // Cap timer at ~24 hours to avoid dart Timer overflow issues.
      final cappedDelay = delay > const Duration(hours: 24)
          ? const Duration(hours: 24)
          : delay;
      _scheduledTimers[entry.id] = startSafeTimer(
        cappedDelay,
        () => _onTimerFired(entry.id),
      );
    }

    // Update nextRunAt on the entry without triggering persistence loop.
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      _entries[index] = _entries[index].copyWith(nextRunAt: nextRun);
      if (refreshEntriesView) {
        _refreshEntriesView();
      }
    }
  }

  void _onTimerFired(String id) {
    if (!_canExecuteInCurrentState) return;
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final entry = _entries[index];
    if (!entry.enabled) return;

    final now = DateTime.now();
    final nextRun = entry.nextRunAt;

    if (nextRun != null && now.isBefore(nextRun)) {
      // Timer fired early (due to 24h cap). Re-schedule.
      _scheduleJob(entry);
      return;
    }

    // Execute the job.
    _executeJob(entry);
  }

  Future<void> _executeJob(
    CronEntry entry, {
    String triggerType = 'scheduled',
  }) async {
    if (!_canExecuteInCurrentState) return;
    // Prevent overlapping executions of the same job.
    if (_runningJobs.containsKey(entry.id)) return;

    // Mark as running.
    _updateEntryStatus(entry.id, CronJobStatus.running);

    // System agent entries dispatch to an injected handler rather than a
    // spawned process. If bootstrap has not registered the handler yet, the job
    // is reported as a no-op success so the scheduler can retry on the next tick.
    if (entry.scriptType == CronScriptType.agent) {
      if (_runningAgentJobIds.contains(entry.id)) return;
      _runningAgentJobIds.add(entry.id);
      try {
        await _executeAgentJob(entry, triggerType: triggerType);
      } finally {
        _runningAgentJobIds.remove(entry.id);
      }
      return;
    }

    final executionHandle = CronExecutor.start(
      entry,
      triggerType: triggerType,
      runtimeContext: <String, String>{
        'app.lifecycle': _appLifecycleState.name,
      },
    );
    _runningJobs[entry.id] = executionHandle;

    try {
      final record = await executionHandle.result;

      // Persist execution record.
      await _store.insertHistory(record);
      await _store.pruneHistory(entry.id);

      // Update cache.
      final cached = _historyCache[entry.id] ?? <CronExecutionRecord>[];
      _historyCache[entry.id] = [record, ...cached].take(50).toList();

      // Update entry status based on result.
      final newStatus = switch (record.status) {
        'success' => CronJobStatus.idle,
        'timed_out' => CronJobStatus.error,
        'failed' => CronJobStatus.failed,
        'killed' => CronJobStatus.idle,
        _ => CronJobStatus.error,
      };

      final consecutiveFailures = switch (record.status) {
        'success' => 0,
        'killed' => entry.consecutiveFailures,
        _ => entry.consecutiveFailures + 1,
      };

      _updateEntry(
        entry.id,
        (e) => e.copyWith(
          status: newStatus,
          lastRunAt: record.startedAt,
          lastExitCode: record.exitCode,
          consecutiveFailures: consecutiveFailures,
          updatedAt: DateTime.now(),
        ),
      );
      await _store.updateOne(
        _entries.firstWhere((e) => e.id == entry.id, orElse: () => entry),
      );

      await _sendExecutionNotification(entry, record);

      // Re-schedule next run.
      final current = _entries.firstWhere(
        (e) => e.id == entry.id,
        orElse: () => entry,
      );
      _scheduleJob(current);
    } catch (error, stack) {
      silentLog('crons_controller', 'execute cron job', error, stack);
      _updateEntryStatus(entry.id, CronJobStatus.error);
    } finally {
      _runningJobs.remove(entry.id);
      notifyListeners();
    }
  }

  void _updateEntryStatus(String id, CronJobStatus status) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _entries[index] = _entries[index].copyWith(status: status);
    _refreshEntriesView();
    notifyListeners();
  }

  void _updateEntry(String id, CronEntry Function(CronEntry) updater) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _entries[index] = updater(_entries[index]);
    _refreshEntriesView();
  }

  void _setEntries(List<CronEntry> entries) {
    _entries = entries;
    _refreshEntriesView();
  }

  void _refreshEntriesView() {
    _entriesView = List<CronEntry>.unmodifiable(_entries);
  }

  Future<void> _sendExecutionNotification(
    CronEntry entry,
    CronExecutionRecord record,
  ) async {
    final notifyConfig = _resolveNotifyConfig(entry, record);
    if (notifyConfig.type == CronNotifyType.none ||
        notifyConfig.type == CronNotifyType.log ||
        record.status == 'killed') {
      return;
    }

    final localeName = Platform.localeName;
    final statusLabel = switch (record.status) {
      'success' => openHandLocalizedTextForLocaleName(
        localeName,
        zh: '执行成功',
        en: 'Succeeded',
        zhHant: '執行成功',
        fr: 'Réussi',
        de: 'Erfolgreich',
        ja: '成功',
      ),
      'timed_out' => openHandLocalizedTextForLocaleName(
        localeName,
        zh: '执行超时',
        en: 'Timed Out',
        zhHant: '執行逾時',
        fr: 'Délai dépassé',
        de: 'Zeitüberschreitung',
        ja: 'タイムアウト',
      ),
      'failed' => openHandLocalizedTextForLocaleName(
        localeName,
        zh: '执行失败',
        en: 'Failed',
        zhHant: '執行失敗',
        fr: 'Échec',
        de: 'Fehlgeschlagen',
        ja: '失敗',
      ),
      _ => record.status,
    };

    final title = openHandLocalizedTextForLocaleName(
      localeName,
      zh: '定时任务：${entry.name}',
      en: 'Cron Job: ${entry.name}',
      zhHant: '定時任務：${entry.name}',
      fr: 'Tâche planifiée : ${entry.name}',
      de: 'Cron-Aufgabe: ${entry.name}',
      ja: '定期タスク: ${entry.name}',
    );
    final body = _resolveNotificationBody(
      entry,
      record,
      statusLabel,
      localeName,
    );
    final level = _mapNotifySeverityToLevel(notifyConfig.severity);

    if (notifyConfig.type == CronNotifyType.system) {
      final shown = await OpenHandNotificationService.showSystem(
        title: title,
        body: body,
        level: level,
        playSound: notifyConfig.playSound,
        vibrate: notifyConfig.vibrate,
      );
      if (!shown) {
        await OpenHandNotificationService.showInApp(
          title: title,
          body: body,
          level: level,
          playSound: notifyConfig.playSound,
          vibrate: notifyConfig.vibrate,
        );
      }
      return;
    }

    if (notifyConfig.type == CronNotifyType.appNotification) {
      await OpenHandNotificationService.showInApp(
        title: title,
        body: body,
        level: level,
        playSound: notifyConfig.playSound,
        vibrate: notifyConfig.vibrate,
      );
    }
  }

  ({
    CronNotifyType type,
    CronNotifySeverity severity,
    bool playSound,
    bool vibrate,
  })
  _resolveNotifyConfig(CronEntry entry, CronExecutionRecord record) {
    return switch (record.status) {
      'success' => (
        type: entry.onSuccessNotify,
        severity: entry.onSuccessSeverity,
        playSound: entry.onSuccessPlaySound,
        vibrate: entry.onSuccessVibrate,
      ),
      'timed_out' => (
        type: entry.onTimeoutNotify,
        severity: entry.onTimeoutSeverity,
        playSound: entry.onTimeoutPlaySound,
        vibrate: entry.onTimeoutVibrate,
      ),
      _ => (
        type: entry.onFailureNotify,
        severity: entry.onFailureSeverity,
        playSound: entry.onFailurePlaySound,
        vibrate: entry.onFailureVibrate,
      ),
    };
  }

  OpenHandNotificationLevel _mapNotifySeverityToLevel(
    CronNotifySeverity severity,
  ) {
    return switch (severity) {
      CronNotifySeverity.info => OpenHandNotificationLevel.info,
      CronNotifySeverity.success => OpenHandNotificationLevel.success,
      CronNotifySeverity.warning => OpenHandNotificationLevel.warning,
      CronNotifySeverity.error => OpenHandNotificationLevel.error,
      CronNotifySeverity.critical => OpenHandNotificationLevel.critical,
    };
  }

  String _resolveNotificationBody(
    CronEntry entry,
    CronExecutionRecord record,
    String statusLabel,
    String localeName,
  ) {
    final custom = switch (record.status) {
      'success' => entry.onSuccessMessage,
      'timed_out' => entry.onTimeoutMessage,
      _ => entry.onFailureMessage,
    };
    if (custom != null && custom.trim().isNotEmpty) {
      return custom.trim();
    }

    final elapsed = '${record.elapsedMs}ms';
    if (record.status == 'success') {
      return openHandLocalizedTextForLocaleName(
        localeName,
        zh: '$statusLabel，耗时 $elapsed。',
        en: '$statusLabel in $elapsed.',
        zhHant: '$statusLabel，耗時 $elapsed。',
        fr: '$statusLabel en $elapsed.',
        de: '$statusLabel in $elapsed.',
        ja: '$statusLabel、所要時間 $elapsed。',
      );
    }

    final error = (record.errorMessage ?? '').trim();
    if (error.isNotEmpty) {
      return openHandLocalizedTextForLocaleName(
        localeName,
        zh: '$statusLabel，耗时 $elapsed。原因：$error',
        en: '$statusLabel in $elapsed. Reason: $error',
        zhHant: '$statusLabel，耗時 $elapsed。原因：$error',
        fr: '$statusLabel en $elapsed. Raison : $error',
        de: '$statusLabel in $elapsed. Grund: $error',
        ja: '$statusLabel、所要時間 $elapsed。理由: $error',
      );
    }

    return openHandLocalizedTextForLocaleName(
      localeName,
      zh: '$statusLabel，耗时 $elapsed。',
      en: '$statusLabel in $elapsed.',
      zhHant: '$statusLabel，耗時 $elapsed。',
      fr: '$statusLabel en $elapsed.',
      de: '$statusLabel in $elapsed.',
      ja: '$statusLabel、所要時間 $elapsed。',
    );
  }

  // ---------------------------------------------------------------------------
  // Mutation queue
  // ---------------------------------------------------------------------------

  Future<bool> _commitMutation(Future<bool> Function() mutation) {
    final completer = Completer<bool>();
    _mutationQueue = _mutationQueue.then((_) async {
      try {
        final result = await mutation();
        notifyListeners();
        completer.complete(result);
      } catch (error, stack) {
        silentLog('crons_controller', 'commit cron mutation', error, stack);
        completer.complete(false);
      }
    });
    return completer.future;
  }
}

/// Agent 处理函数返回的结构化结果。
///
/// * [stdout] 写入 [CronExecutionRecord.stdout]，用于历史详情默认展示。
/// * [appContext] 写入 [CronExecutionRecord.appContext]，用于承载结构化
///   元数据（例如 Hermes Talker 的会话级 JSON 报告），由 UI 侧根据特定
///   key 渲染富面板。
class AgentHandlerResult {
  const AgentHandlerResult({
    this.stdout = '',
    this.appContext = const <String, String>{},
  });

  final String stdout;
  final Map<String, String> appContext;
}

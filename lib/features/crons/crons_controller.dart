import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../../app/model/cron_config.dart';
import '../../app/support/openhand_notification_service.dart';
import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/serial_task_queue.dart';
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
  static const int _maxConcurrentExecutions = 8;

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
    if (_isDisposed) return;
    await _mutationQueue.enqueue(() async {
      if (_isDisposed || _hasInitialized) return;
      await _loadConfigurationLocked();
    });
  }

  Future<void> _loadConfigurationLocked() async {
    _isLoading = true;
    _hasTrustedSnapshot = false;
    _errorMessage = null;
    _runtimeGeneration++;
    _cancelScheduledTimers();
    for (final job in _runningJobs.values) {
      job.cancel();
    }
    notifyListeners();
    try {
      await _store.ensureTable();
      final entries = await _store.loadAll();
      var needsSave = false;
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        if (entry.status == CronJobStatus.running) {
          entries[index] = entry.copyWith(
            status: entry.enabled ? CronJobStatus.idle : CronJobStatus.paused,
          );
          needsSave = true;
        }
      }
      // Seed the Hermes Talker self-learning system entry if needed, then
      // refresh only system-managed display/scheduling fields. User-toggleable
      // fields and runtime state are preserved.
      final existingIndex = entries.indexWhere(
        (e) => e.id == selfLearningSystemEntryId,
      );
      if (existingIndex == -1) {
        entries.add(_buildSelfLearningSystemEntry());
        needsSave = true;
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
            existing.timeoutSeconds != refreshed.timeoutSeconds ||
            !listEquals(existing.tags, refreshed.tags) ||
            existing.onSuccessNotify != refreshed.onSuccessNotify ||
            existing.onFailureNotify != refreshed.onFailureNotify ||
            existing.onTimeoutNotify != refreshed.onTimeoutNotify;
        if (needsRefresh) {
          entries[existingIndex] = refreshed;
          needsSave = true;
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
            existing.timeoutSeconds != refreshed.timeoutSeconds ||
            !listEquals(existing.tags, refreshed.tags) ||
            existing.onSuccessNotify != refreshed.onSuccessNotify ||
            existing.onFailureNotify != refreshed.onFailureNotify ||
            existing.onTimeoutNotify != refreshed.onTimeoutNotify) {
          entries[keywordIndex] = refreshed;
          needsSave = true;
        }
      }
      if (needsSave) await _store.saveAll(entries);
      if (_isDisposed) return;
      _setEntries(entries);
      _hasTrustedSnapshot = true;
      if (!_hasInitialized) {
        WidgetsBinding.instance.addObserver(this);
        _bindProcessSignalWatchers();
        _hasInitialized = true;
      }
      _startScheduler();
    } catch (error, stack) {
      _hasTrustedSnapshot = false;
      _errorMessage = '$error';
      silentLog('crons_controller', 'load cron configuration', error, stack);
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
    await _commitMutation(() async {
      final index = _entries.indexWhere(
        (e) => e.id == mcpKeywordIndexSystemEntryId,
      );
      if (mode == McpKeywordIndexUpdateMode.coldStart) {
        if (index == -1) return false;
        final next = _entries
            .where((entry) => entry.id != mcpKeywordIndexSystemEntryId)
            .toList();
        await _store.saveAll(next);
        _setEntries(next);
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
        final next = <CronEntry>[..._entries, created];
        await _store.saveAll(next);
        _setEntries(next);
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
      final next = <CronEntry>[
        ..._entries.sublist(0, index),
        refreshed,
        ..._entries.sublist(index + 1),
      ];
      await _store.saveAll(next);
      _setEntries(next);
      return true;
    });
  }

  final CronsStore _store;
  List<CronEntry> _entries;
  List<CronEntry> _entriesView;
  bool _isLoading;
  bool _hasInitialized = false;
  bool _hasTrustedSnapshot = false;
  String? _errorMessage;
  bool _isDisposed = false;
  bool _isShuttingDown = false;
  int _runtimeGeneration = 0;
  int _activeExecutionCount = 0;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  final SerialTaskQueue _mutationQueue = SerialTaskQueue();

  /// Active timers keyed by cron job id.
  final Map<String, Timer> _scheduledTimers = {};

  /// Currently running jobs keyed by cron job id.
  final Map<String, CronExecutionHandle> _runningJobs = {};

  /// 智能体任务的执行令牌。超时后原任务仍未结束时保留令牌，避免重复调度。
  final Map<String, Object> _runningAgentJobTokens = <String, Object>{};

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
  String? get errorMessage => _errorMessage;
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
    final sigTermWatcher = _sigTermWatcher;
    final sigIntWatcher = _sigIntWatcher;
    _sigTermWatcher = null;
    _sigIntWatcher = null;
    unawaited(_cancelSignalWatcher(sigTermWatcher, 'SIGTERM'));
    unawaited(_cancelSignalWatcher(sigIntWatcher, 'SIGINT'));
    super.dispose();
  }

  Future<void> _cancelSignalWatcher(
    StreamSubscription<ProcessSignal>? subscription,
    String signalName,
  ) async {
    await cancelStreamSubscriptionBounded<ProcessSignal>(
      subscription,
      onError: (error, stack) => silentLog(
        'crons_controller',
        'cancel $signalName watcher',
        error,
        stack,
      ),
    );
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

  // CRUD
  Future<bool> addCron(CronEntry entry) async {
    return _commitMutation(() async {
      final now = DateTime.now();
      final requestedId = entry.id.trim();
      final id = requestedId.isEmpty ? _uuid.v4() : requestedId;
      if (_entries.any((item) => item.id == id)) return false;
      final newEntry = entry.copyWith(id: id, createdAt: now, updatedAt: now);
      final next = <CronEntry>[..._entries, newEntry];
      await _store.saveAll(next);
      _setEntries(next);
      return true;
    });
  }

  Future<bool> updateCron(CronEntry updated) async {
    final id = updated.id.trim();
    if (id.isEmpty || id != updated.id) return false;
    return _commitMutation(() async {
      final index = _entries.indexWhere((item) => item.id == id);
      if (index < 0) return false;
      final current = _entries[index];
      final entry = updated.copyWith(updatedAt: DateTime.now());
      final preserved = entry.copyWith(
        status: current.status,
        lastRunAt: current.lastRunAt,
        nextRunAt: current.nextRunAt,
        lastExitCode: current.lastExitCode,
        consecutiveFailures: current.consecutiveFailures,
        createdAt: current.createdAt,
        clearLastRunAt: current.lastRunAt == null,
        clearNextRunAt: current.nextRunAt == null,
        clearLastExitCode: current.lastExitCode == null,
      );
      final next = <CronEntry>[
        ..._entries.sublist(0, index),
        preserved,
        ..._entries.sublist(index + 1),
      ];
      await _store.saveAll(next);
      _setEntries(next);
      return true;
    });
  }

  Future<bool> deleteCron(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return false;
    return _commitMutation(() async {
      final before = _entries.length;
      final target = _entries.firstWhere(
        (item) => item.id == normalizedId,
        orElse: () => _missingSentinel,
      );
      if (identical(target, _missingSentinel)) return false;
      // System-managed entries are not user-deletable.
      if (target.tags.contains(systemTag)) return false;
      final next = _entries.where((item) => item.id != normalizedId).toList();
      if (next.length == before) return false;
      await _store.saveAll(next);
      _setEntries(next);
      _historyCache.remove(normalizedId);
      try {
        await _store.deleteHistoryForCron(normalizedId);
      } catch (error, stack) {
        silentLog(
          'crons_controller',
          'delete history for removed cron',
          error,
          stack,
        );
      }
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

  Future<bool> _executeAgentJob(
    CronEntry entry, {
    required String triggerType,
    required int generation,
    required Object executionToken,
  }) async {
    var keepsExecutionLock = false;
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
        final pending = handler(entry);
        late final AgentHandlerResult result;
        try {
          result = await pending.timeout(
            Duration(seconds: entry.timeoutSeconds),
          );
        } on TimeoutException {
          status = 'timed_out';
          errorMessage = '智能体定时任务超时（${entry.timeoutSeconds} 秒）。';
          keepsExecutionLock = true;
          _observeTimedOutAgentCompletion(
            pending,
            entryId: entry.id,
            executionToken: executionToken,
          );
          rethrow;
        }
        stdout = result.stdout;
        appContext = result.appContext;
      }
    } on TimeoutException {
      // 超时后仅在后台观察原任务，当前执行立即结束。
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
    if (!_isCurrentRuntime(generation)) return keepsExecutionLock;
    try {
      await _store.insertHistory(record);
      await _store.pruneHistory(entry.id);
    } catch (error, stack) {
      silentLog('crons_controller', 'persist agent history', error, stack);
      // ignore history persistence errors — the scheduler will try again.
    }
    final cached = _historyCache[entry.id] ?? <CronExecutionRecord>[];
    _historyCache[entry.id] = [record, ...cached].take(50).toList();
    await _commitRuntimeEntry(
      entry.id,
      (e) => e.copyWith(
        status: switch (status) {
          'success' => CronJobStatus.idle,
          'timed_out' => CronJobStatus.error,
          _ => CronJobStatus.failed,
        },
        lastRunAt: startedAt,
        consecutiveFailures: status == 'success'
            ? 0
            : e.consecutiveFailures + 1,
        updatedAt: DateTime.now(),
      ),
      generation: generation,
    );
    notifyListeners();
    return keepsExecutionLock;
  }

  /// 原 Future 完成后才释放超时任务的重入锁，防止同一任务并发积压。
  void _observeTimedOutAgentCompletion(
    Future<AgentHandlerResult> pending, {
    required String entryId,
    required Object executionToken,
  }) {
    void release() {
      if (!identical(_runningAgentJobTokens[entryId], executionToken)) return;
      _runningAgentJobTokens.remove(entryId);
      if (_activeExecutionCount > 0) _activeExecutionCount--;
      _scheduleCurrentEntry(entryId);
      notifyListeners();
    }

    unawaited(
      pending.then<void>(
        (_) => release(),
        onError: (Object error, StackTrace stack) {
          silentLog('crons_controller', '观察超时智能体任务的迟到异常', error, stack);
          release();
        },
      ),
    );
  }

  Future<bool> toggleCronEnabled(String id, {required bool enabled}) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return false;
    return _commitMutation(() async {
      final index = _entries.indexWhere((item) => item.id == normalizedId);
      if (index < 0) return false;
      final entry = _entries[index].copyWith(
        enabled: enabled,
        status: enabled ? CronJobStatus.idle : CronJobStatus.paused,
        updatedAt: DateTime.now(),
      );
      final next = <CronEntry>[
        ..._entries.sublist(0, index),
        entry,
        ..._entries.sublist(index + 1),
      ];
      await _store.saveAll(next);
      _setEntries(next);
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
    await _enqueueHistoryOperation<void>('loadHistory', null, () async {
      final records = await _store.loadHistory(cronId);
      _historyCache[cronId] = records;
      notifyListeners();
    });
  }

  Future<bool> clearHistoryForCron(String cronId) async {
    return _enqueueHistoryOperation<bool>(
      'clearHistoryForCron',
      false,
      () async {
        await _store.deleteHistoryForCron(cronId);
        _historyCache.remove(cronId);
        notifyListeners();
        return true;
      },
    );
  }

  Future<bool> deleteHistoryRecord(String cronId, String recordId) async {
    return _enqueueHistoryOperation<bool>(
      'deleteHistoryRecord',
      false,
      () async {
        await _store.deleteHistoryRecord(recordId);
        final cached = _historyCache[cronId];
        if (cached != null) {
          cached.removeWhere((r) => r.id == recordId);
        }
        notifyListeners();
        return true;
      },
    );
  }

  /// 删除所有 [cutoff] 之前的执行历史，返回受影响的行数。
  /// 同步刷新内存缓存以避免 UI 看到陈旧数据。
  /// 这是一个"尽力而为"的清理，调用方负责自身的异常兜底；
  /// 失败时返回 0，不抛异常。
  Future<int> purgeHistoryOlderThan(DateTime cutoff) async {
    return _enqueueHistoryOperation<int>('purgeHistoryOlderThan', 0, () async {
      final affected = await _store.deleteHistoryOlderThan(cutoff);
      if (affected == 0) return 0;
      for (final cronId in _historyCache.keys.toList()) {
        final cached = _historyCache[cronId];
        if (cached == null) continue;
        _historyCache[cronId] = cached
            .where((record) => record.startedAt.isAfter(cutoff))
            .toList(growable: false);
      }
      notifyListeners();
      return affected;
    });
  }

  /// 清空全部 cron 执行历史。返回受影响行数；失败返回 0
  /// 并 silentLog，不抛异常。仅由全局设置中的"日志清理 / 全部数据清空"
  /// 触发，调用方负责弹窗二次确认。
  Future<int> clearAllHistory() async {
    return _enqueueHistoryOperation<int>('clearAllHistory', 0, () async {
      final affected = await _store.deleteAllHistory();
      _historyCache.clear();
      notifyListeners();
      return affected;
    });
  }

  /// 清空全部"非系统"cron 任务（保留 Hermes Talker / MCP
  /// 关键词索引等带 [systemTag] 的内置条目，避免清理后丢失自学习能力）。
  /// 同步取消调度、清理历史缓存，返回受影响条目数。
  Future<int> clearAllNonSystemCrons() async {
    int removed = 0;
    final committed = await _commitMutation(() async {
      final preserved = _entries
          .where((entry) => entry.tags.contains(systemTag))
          .toList();
      removed = _entries.length - preserved.length;
      if (removed == 0) return true;
      final removedEntries = _entries
          .where((entry) => !entry.tags.contains(systemTag))
          .toList(growable: false);
      await _store.saveAll(preserved);
      _setEntries(preserved);
      for (final entry in removedEntries) {
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
      return true;
    });
    return committed ? removed : 0;
  }

  Future<void> refresh() async {
    await _mutationQueue.enqueue(() async {
      if (_isDisposed) return;
      await _loadConfigurationLocked();
    });
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
        _hasInitialized &&
        _hasTrustedSnapshot &&
        !_isShuttingDown &&
        _appLifecycleState != AppLifecycleState.detached;
  }

  void _shutdownSchedulersAndJobs() {
    if (_isShuttingDown) return;
    _isShuttingDown = true;
    _runtimeGeneration++;
    _cancelScheduledTimers();
    for (final job in _runningJobs.values) {
      job.cancel();
    }
    _runningJobs.clear();
  }

  // Scheduling
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
    _cancelScheduledTimers();
    _startScheduler();
  }

  void _cancelScheduledTimers() {
    for (final timer in _scheduledTimers.values) {
      timer.cancel();
    }
    _scheduledTimers.clear();
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
    if (_runningJobs.containsKey(entry.id) ||
        _runningAgentJobTokens.containsKey(entry.id) ||
        _activeExecutionCount >= _maxConcurrentExecutions) {
      _scheduleCurrentEntry(entry.id);
      return;
    }
    final generation = _runtimeGeneration;
    _activeExecutionCount++;
    _updateEntryStatus(entry.id, CronJobStatus.running);

    // System agent entries dispatch to an injected handler rather than a
    // spawned process. If bootstrap has not registered the handler yet, the job
    // is reported as a no-op success so the scheduler can retry on the next tick.
    if (entry.scriptType == CronScriptType.agent) {
      final executionToken = Object();
      var keepsExecutionLock = false;
      _runningAgentJobTokens[entry.id] = executionToken;
      try {
        keepsExecutionLock = await _executeAgentJob(
          entry,
          triggerType: triggerType,
          generation: generation,
          executionToken: executionToken,
        );
      } finally {
        if (!keepsExecutionLock &&
            identical(_runningAgentJobTokens[entry.id], executionToken)) {
          _runningAgentJobTokens.remove(entry.id);
        }
        if (!keepsExecutionLock && _activeExecutionCount > 0) {
          _activeExecutionCount--;
        }
        if (!keepsExecutionLock) _scheduleCurrentEntry(entry.id);
        notifyListeners();
      }
      return;
    }

    try {
      final executionHandle = CronExecutor.start(
        entry,
        triggerType: triggerType,
        runtimeContext: <String, String>{
          'app.lifecycle': _appLifecycleState.name,
        },
      );
      _runningJobs[entry.id] = executionHandle;
      final record = await executionHandle.result;
      if (!_isCurrentRuntime(generation)) return;

      try {
        await _store.insertHistory(record);
        await _store.pruneHistory(entry.id);
      } catch (error, stack) {
        silentLog('crons_controller', 'persist cron history', error, stack);
      }

      final cached = _historyCache[entry.id] ?? <CronExecutionRecord>[];
      _historyCache[entry.id] = [record, ...cached].take(50).toList();
      final newStatus = switch (record.status) {
        'success' => CronJobStatus.idle,
        'timed_out' => CronJobStatus.error,
        'failed' => CronJobStatus.failed,
        'killed' => CronJobStatus.idle,
        _ => CronJobStatus.error,
      };

      await _commitRuntimeEntry(
        entry.id,
        (current) => current.copyWith(
          status: newStatus,
          lastRunAt: record.startedAt,
          lastExitCode: record.exitCode,
          consecutiveFailures: switch (record.status) {
            'success' => 0,
            'killed' => current.consecutiveFailures,
            _ => current.consecutiveFailures + 1,
          },
          updatedAt: DateTime.now(),
        ),
        generation: generation,
      );
      try {
        await _sendExecutionNotification(entry, record);
      } catch (error, stack) {
        silentLog('crons_controller', 'send cron notification', error, stack);
      }
    } catch (error, stack) {
      silentLog('crons_controller', 'execute cron job', error, stack);
      await _commitRuntimeEntry(
        entry.id,
        (current) => current.copyWith(
          status: CronJobStatus.error,
          consecutiveFailures: current.consecutiveFailures + 1,
          updatedAt: DateTime.now(),
        ),
        generation: generation,
      );
    } finally {
      _runningJobs.remove(entry.id);
      if (_activeExecutionCount > 0) _activeExecutionCount--;
      _scheduleCurrentEntry(entry.id);
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

  bool _isCurrentRuntime(int generation) {
    return generation == _runtimeGeneration && _canExecuteInCurrentState;
  }

  Future<bool> _commitRuntimeEntry(
    String id,
    CronEntry Function(CronEntry current) update, {
    required int generation,
  }) {
    return _mutationQueue.enqueue(() async {
      if (!_isCurrentRuntime(generation)) return false;
      final index = _entries.indexWhere((entry) => entry.id == id);
      if (index < 0) return false;
      final updated = update(_entries[index]);
      try {
        await _store.updateRuntimeState(updated);
      } catch (error, stack) {
        silentLog(
          'crons_controller',
          'persist cron runtime state',
          error,
          stack,
        );
        return false;
      }
      _entries[index] = updated;
      _refreshEntriesView();
      notifyListeners();
      return true;
    });
  }

  void _scheduleCurrentEntry(String id) {
    if (!_canExecuteInCurrentState) return;
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index >= 0) _scheduleJob(_entries[index]);
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

  // Mutation queue
  Future<T> _enqueueHistoryOperation<T>(
    String tag,
    T fallback,
    Future<T> Function() operation,
  ) {
    if (_isDisposed) return Future<T>.value(fallback);
    return _mutationQueue.enqueue(() async {
      if (_isDisposed) return fallback;
      try {
        await _store.ensureTable();
        return await operation();
      } catch (error, stack) {
        silentLog('crons_controller', tag, error, stack);
        return fallback;
      }
    });
  }

  Future<bool> _commitMutation(Future<bool> Function() mutation) {
    if (_isDisposed) return Future<bool>.value(false);
    return _mutationQueue.enqueue(() async {
      if (_isDisposed) return false;
      if (!await _ensureReadyLocked()) return false;
      final previousEntries = List<CronEntry>.from(_entries);
      _hasTrustedSnapshot = false;
      _errorMessage = null;
      _cancelScheduledTimers();
      notifyListeners();
      try {
        final result = await mutation();
        _hasTrustedSnapshot = true;
        _restartScheduler();
        notifyListeners();
        return result;
      } catch (error, stack) {
        _setEntries(previousEntries);
        _hasTrustedSnapshot = false;
        _errorMessage = '$error';
        silentLog('crons_controller', 'commit cron mutation', error, stack);
        notifyListeners();
        return false;
      }
    });
  }

  Future<bool> _ensureReadyLocked() async {
    if (_hasInitialized && _hasTrustedSnapshot) return true;
    await _loadConfigurationLocked();
    return _hasInitialized && _hasTrustedSnapshot;
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

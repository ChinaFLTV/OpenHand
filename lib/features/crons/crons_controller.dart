import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../../app/model/cron_config.dart';
import '../../app/support/openhand_notification_service.dart';
import 'cron_executor.dart';
import 'cron_parser.dart';
import 'crons_store.dart';

/// Controller for managing cron job configurations and scheduling.
///
/// Follows the same ChangeNotifier + mutation queue pattern as HooksController.
class CronsController extends ChangeNotifier with WidgetsBindingObserver {
  CronsController._({
    required CronsStore store,
    required List<CronEntry> entries,
  }) : _store = store,
       _entries = entries;

  static const Uuid _uuid = Uuid();

  static Future<CronsController> create({CronsStore? store}) async {
    final effectiveStore = store ?? CronsStore();
    await effectiveStore.ensureTable();
    final entries = await effectiveStore.loadAll();
    // 2026-04-25 (Task 19) — Seed the Hermes Talker self-learning system
    // entry on first launch if it does not already exist. The entry is
    // treated as read-only by the UI (see crons_view.dart system tag check).
    if (!entries.any((e) => e.id == selfLearningSystemEntryId)) {
      entries.add(_buildSelfLearningSystemEntry());
      await effectiveStore.saveAll(entries);
    }
    final controller = CronsController._(
      store: effectiveStore,
      entries: entries,
    );
    WidgetsBinding.instance.addObserver(controller);
    controller._bindProcessSignalWatchers();
    controller._startScheduler();
    return controller;
  }

  /// Stable id of the system-seeded Hermes Talker self-learning cron entry.
  static const String selfLearningSystemEntryId =
      'self_learning.hermes_talker';

  /// Tag that marks a cron entry as system-managed (read-only in UI).
  static const String systemTag = 'system';

  /// Tag that associates a system entry with the Hermes Talker template.
  static const String hermesTalkerTag = 'hermes_talker';

  static CronEntry _buildSelfLearningSystemEntry() {
    return const CronEntry(
      id: selfLearningSystemEntryId,
      name: 'Hermes Talker 自我学习',
      description:
          'System-managed: dispatches the Hermes Talker self-learning agent '
          'every 5 minutes.',
      scriptType: CronScriptType.agent,
      cronExpression: '*/5 * * * *',
      timeoutSeconds: 600,
      tags: <String>[systemTag, hermesTalkerTag],
      onSuccessNotify: CronNotifyType.none,
      onFailureNotify: CronNotifyType.log,
      onTimeoutNotify: CronNotifyType.log,
    );
  }

  final CronsStore _store;
  List<CronEntry> _entries;
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

  List<CronEntry> get entries => List<CronEntry>.unmodifiable(_entries);
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
    WidgetsBinding.instance.removeObserver(this);
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
      _entries = <CronEntry>[..._entries, newEntry];
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
      _entries = <CronEntry>[
        ..._entries.sublist(0, index),
        entry,
        ..._entries.sublist(index + 1),
      ];
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
      // 2026-04-25 (Task 20) — guard system-managed entries from deletion.
      if (target.tags.contains(systemTag)) return false;
      _entries = _entries.where((item) => item.id != id).toList();
      if (_entries.length == before) return false;
      await _store.saveAll(_entries);
      _cancelTimer(id);
      _historyCache.remove(id);
      await _store.deleteHistoryForCron(id);
      return true;
    });
  }

  static const CronEntry _missingSentinel = CronEntry(id: '', name: '');

  /// Handler invoked for `CronScriptType.agent` entries. Bootstrap injects
  /// this via [registerAgentHandler] to plug the Hermes Talker
  /// `SelfLearningScheduler`. Handlers must never throw.
  ///
  /// The return value is a terse status string (e.g. `'ok: triggered=2'`)
  /// stored in the [CronExecutionRecord.stdout] field.
  Future<String> Function(CronEntry entry)? _agentHandler;

  /// Registers (or replaces) the in-process handler for Agent-typed cron
  /// entries. Passing `null` removes the handler.
  void registerAgentHandler(
    Future<String> Function(CronEntry entry)? handler,
  ) {
    _agentHandler = handler;
  }

  Future<void> _executeAgentJob(
    CronEntry entry, {
    required String triggerType,
  }) async {
    final startedAt = DateTime.now();
    String stdout = '';
    String status = 'success';
    String? errorMessage;
    try {
      final handler = _agentHandler;
      if (handler == null) {
        stdout = 'noop: agent handler not registered';
      } else {
        stdout = await handler(entry);
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
    );
    try {
      await _store.insertHistory(record);
      await _store.pruneHistory(entry.id);
    } catch (_) {
      // ignore history persistence errors — the scheduler will try again.
    }
    final cached = _historyCache[entry.id] ?? <CronExecutionRecord>[];
    _historyCache[entry.id] = [record, ...cached].take(50).toList();

    _updateEntry(
      entry.id,
      (e) => e.copyWith(
        status: status == 'success'
            ? CronJobStatus.idle
            : CronJobStatus.failed,
        lastRunAt: startedAt,
        consecutiveFailures: status == 'success'
            ? 0
            : entry.consecutiveFailures + 1,
        updatedAt: DateTime.now(),
      ),
    );
    try {
      await _store.updateOne(_entries.firstWhere((e) => e.id == entry.id));
    } catch (_) {}
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
      _entries = <CronEntry>[
        ..._entries.sublist(0, index),
        entry,
        ..._entries.sublist(index + 1),
      ];
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
    // 2026-04-25 (Task 16/19) — agent-typed crons have no script payload;
    // they dispatch via [_agentHandler]. Only gate non-agent jobs on
    // [hasScript].
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

  Future<void> refresh() async {
    final entries = await _store.loadAll();
    _entries = entries;
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
      final result = await Process.run('cut', ['-d:', '-f1', '/etc/passwd']);
      if (result.exitCode == 0) {
        final users = (result.stdout as String)
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.startsWith('#'))
            .toList();
        if (users.isNotEmpty) {
          // Ensure 'root' is at the front.
          users.remove('root');
          _systemUsers = <String>['root', ...users];
        }
      }
    } catch (_) {
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
    } catch (_) {
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
      _scheduleJob(entry);
    }
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

  void _scheduleJob(CronEntry entry) {
    if (!_canExecuteInCurrentState) return;
    _cancelTimer(entry.id);
    if (!entry.enabled) return;
    // 2026-04-25 (Task 16/19) — agent-typed crons are scheduled even
    // though they carry no script payload: execution is routed through
    // [_agentHandler] rather than [CronExecutor].
    if (entry.scriptType != CronScriptType.agent && !entry.hasScript) return;

    final nextRun = CronParser.nextRun(entry.cronExpression);
    if (nextRun == null) return;

    final delay = nextRun.difference(DateTime.now());
    if (delay.isNegative) {
      // If already past, schedule for 1 second from now.
      _scheduledTimers[entry.id] = Timer(
        const Duration(seconds: 1),
        () => _onTimerFired(entry.id),
      );
    } else {
      // Cap timer at ~24 hours to avoid dart Timer overflow issues.
      final cappedDelay = delay > const Duration(hours: 24)
          ? const Duration(hours: 24)
          : delay;
      _scheduledTimers[entry.id] = Timer(
        cappedDelay,
        () => _onTimerFired(entry.id),
      );
    }

    // Update nextRunAt on the entry without triggering persistence loop.
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      _entries[index] = _entries[index].copyWith(nextRunAt: nextRun);
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

    // 2026-04-25 (Task 19) — system agent entries are dispatched to an
    // injected handler rather than spawned as processes. If no handler is
    // registered yet (e.g. bootstrap hasn't finished wiring the scheduler),
    // the entry is reported as a no-op success so the scheduler can retry
    // on the next tick.
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
        _entries.firstWhere((e) => e.id == entry.id),
      );

      await _sendExecutionNotification(entry, record);

      // Re-schedule next run.
      final current = _entries.firstWhere(
        (e) => e.id == entry.id,
        orElse: () => entry,
      );
      _scheduleJob(current);
    } catch (e) {
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
    notifyListeners();
  }

  void _updateEntry(String id, CronEntry Function(CronEntry) updater) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _entries[index] = updater(_entries[index]);
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

    final isZh = Platform.localeName.toLowerCase().startsWith('zh');
    final statusLabel = switch (record.status) {
      'success' => isZh ? '执行成功' : 'Succeeded',
      'timed_out' => isZh ? '执行超时' : 'Timed Out',
      'failed' => isZh ? '执行失败' : 'Failed',
      _ => record.status,
    };

    final title = isZh ? '定时任务: ${entry.name}' : 'Cron Job: ${entry.name}';
    final body = _resolveNotificationBody(entry, record, statusLabel, isZh);
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
  }) _resolveNotifyConfig(
    CronEntry entry,
    CronExecutionRecord record,
  ) {
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
    bool isZh,
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
      return isZh
          ? '$statusLabel，耗时 $elapsed。'
          : '$statusLabel in $elapsed.';
    }

    final error = (record.errorMessage ?? '').trim();
    if (error.isNotEmpty) {
      return isZh
          ? '$statusLabel，耗时 $elapsed。原因: $error'
          : '$statusLabel in $elapsed. Reason: $error';
    }

    return isZh ? '$statusLabel，耗时 $elapsed。' : '$statusLabel in $elapsed.';
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
      } catch (error) {
        completer.complete(false);
      }
    });
    return completer.future;
  }
}

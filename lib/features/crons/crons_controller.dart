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
import '../../shared/util/user_failure_message.dart';
import '../mcp/index.dart';
import 'data/crons_store.dart';
import 'model/cron_parser.dart';
import 'service/cron_executor.dart';

const Duration _cronControllerShutdownTimeout = Duration(seconds: 3);

/// 管理定时任务配置与调度。
///
/// 沿用 HooksController 的 ChangeNotifier 与变更队列模式。
class CronsController extends ChangeNotifier with WidgetsBindingObserver {
  CronsController._({
    required this._store,
    required List<CronEntry> entries,
    this._isLoading = false,
  }) : _entries = entries,
       _entriesView = List<CronEntry>.unmodifiable(entries);

  /// 同步创建控制器，暂不加载 SQLite、补齐系统任务、绑定信号或启动调度器。
  /// [initialize] 完成前保持 `isLoading == true`，条目列表可能为空。
  factory CronsController.uninitialized({CronsStore? store}) {
    return CronsController._(
      store: store ?? CronsStore(),
      entries: <CronEntry>[],
      isLoading: true,
    );
  }

  static const Uuid _uuid = Uuid();
  static const int _maxConcurrentExecutions = 8;
  static const int _maxCachedHistoryJobs = 20;
  static const int _maxCachedHistoryRecordsPerJob = 50;

  /// 执行延迟初始化：加载数据、同步系统任务、绑定生命周期并启动调度器。
  /// 重复调用不会重复初始化。
  Future<void> initialize() async {
    if (_isDisposed || _isPermanentlyStopped) return;
    await _mutationQueue.enqueue(() async {
      if (_isDisposed || _isPermanentlyStopped || _hasInitialized) return;
      await _loadConfigurationLocked();
    });
  }

  Future<void> _loadConfigurationLocked() async {
    final hadTrustedSnapshot = _hasTrustedSnapshot;
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
      // 按需补齐 Hermes Talker 自学习任务，仅刷新系统管理字段，保留用户配置与运行状态。
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
      // 因此启动期不主动补齐，由 main.dart 的初始化逻辑在 initialize() 之后
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
      if (_isDisposed || _isPermanentlyStopped) return;
      _setEntries(entries);
      final activeIds = entries.map((entry) => entry.id).toSet();
      _entryRuntimeTokens.removeWhere((id, _) => !activeIds.contains(id));
      _hasTrustedSnapshot = true;
      if (!_hasInitialized) {
        WidgetsBinding.instance.addObserver(this);
        _hasInitialized = true;
      }
      _startScheduler();
    } catch (error, stack) {
      silentLog('crons_controller', '加载定时任务配置', error, stack);
      _hasTrustedSnapshot = hadTrustedSnapshot;
      _errorMessage = userFailureMessage(error, fallback: '定时任务配置加载失败，请稍后重试。');
      if (_hasTrustedSnapshot) _restartScheduler();
    } finally {
      _isLoading = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  /// Hermes Talker 自学习系统任务的稳定 ID。
  static const String selfLearningSystemEntryId = 'self_learning.hermes_talker';

  /// 标记 UI 只读系统任务的标签。
  static const String systemTag = 'system';

  /// 关联 Hermes Talker 模板的系统任务标签。
  static const String hermesTalkerTag = 'hermes_talker';

  static CronEntry _buildSelfLearningSystemEntry() {
    // 名称与说明按当前语言产出：上层每次加载都会用这里的规范值刷新落库条目，
    // 所以切换语言重启后列表里的文案会跟着变。
    return CronEntry(
      id: selfLearningSystemEntryId,
      name: openHandAmbientText(
        zh: 'Hermes Talker 自我学习',
        en: 'Hermes Talker self-learning',
        fr: 'Auto-apprentissage Hermes Talker',
        de: 'Hermes-Talker-Selbstlernen',
        ja: 'Hermes Talker の自己学習',
      ),
      description: openHandAmbientText(
        zh:
            '系统内置：每 5 分钟触发一次 Hermes Talker 自我学习，'
            '让 AI 在后台把近期对话中沉淀的知识与偏好静默写入记忆 / 画像 / 技能库。'
            '本任务为系统管理，无法删除；如需暂停，请使用右侧开关关闭。',
        en:
            'Built in: runs Hermes Talker self-learning every 5 minutes so the '
            'assistant quietly writes knowledge and preferences distilled from '
            'recent conversations into memory, profile and skills. '
            'System-managed and not removable; use the switch on the right to pause it.',
        fr:
            "Intégré : lance l'auto-apprentissage Hermes Talker toutes les 5 minutes "
            "afin que l'assistant enregistre discrètement les connaissances et "
            "préférences issues des conversations récentes dans la mémoire, le profil "
            "et les compétences. Géré par le système et non supprimable ; utilisez "
            "l'interrupteur à droite pour le suspendre.",
        de:
            'Systemintern: startet alle 5 Minuten das Hermes-Talker-Selbstlernen, '
            'damit die KI Wissen und Vorlieben aus den letzten Gesprächen still in '
            'Gedächtnis, Profil und Skills schreibt. Systemverwaltet und nicht '
            'löschbar; zum Pausieren den Schalter rechts nutzen.',
        ja:
            'システム内蔵：5 分ごとに Hermes Talker の自己学習を実行し、直近の会話から'
            '得た知識と好みをメモリ / プロフィール / スキルへ静かに書き込みます。'
            'システム管理のため削除できません。一時停止は右側のスイッチで行えます。',
      ),
      scriptType: CronScriptType.managed,
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
    return CronEntry(
      id: mcpKeywordIndexSystemEntryId,
      name: openHandAmbientText(
        zh: 'MCP 关键词倒排索引重建',
        en: 'Rebuild MCP keyword inverted index',
        fr: "Reconstruire l'index inversé des mots-clés MCP",
        de: 'MCP-Stichwortindex neu aufbauen',
        ja: 'MCP キーワード転置インデックスの再構築',
      ),
      description: openHandAmbientText(
        zh:
            '系统内置：按「全局设置 → MCP → 更新关键词映射模式」驱动。'
            '冷启动模式下不存在；定时间隔 / 每日定点模式下由系统创建并保持启用。'
            '该任务的启用状态由设置项强制锁定，无法手动开关，亦无法删除；'
            '可查看执行历史 / 立即执行一次。',
        en:
            'Built in: driven by Settings → MCP → keyword mapping update mode. '
            'Absent in cold-start mode; created and kept enabled in interval or '
            'daily modes. Its enabled state is locked by that setting, so it cannot '
            'be toggled or removed here; you can still view run history or run it once.',
        fr:
            'Intégré : piloté par Réglages → MCP → mode de mise à jour des mots-clés. '
            'Absent en mode démarrage à froid ; créé et maintenu actif en mode '
            'intervalle ou quotidien. Son activation est verrouillée par ce réglage : '
            "impossible de le basculer ou de le supprimer ici ; l'historique et "
            "l'exécution ponctuelle restent disponibles.",
        de:
            'Systemintern: gesteuert über Einstellungen → MCP → Aktualisierungsmodus '
            'der Stichwortzuordnung. Im Kaltstart-Modus nicht vorhanden; in den Modi '
            'Intervall oder täglich wird sie angelegt und aktiv gehalten. Der '
            'Aktivierungszustand ist durch diese Einstellung gesperrt, daher hier '
            'weder umschaltbar noch löschbar; Verlauf und Einzelausführung bleiben möglich.',
        ja:
            'システム内蔵：「設定 → MCP → キーワードマッピング更新モード」に従います。'
            'コールドスタートモードでは存在せず、一定間隔 / 毎日定時モードではシステムが'
            '作成して有効のまま保ちます。有効状態はその設定に固定されるため、ここでの'
            '切り替えや削除はできません。実行履歴の確認と単発実行は可能です。',
      ),
      scriptType: CronScriptType.managed,
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
        _invalidateEntryRuntime(
          mcpKeywordIndexSystemEntryId,
          removeToken: true,
        );
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
        status: CronJobStatus.idle,
      );
      final next = <CronEntry>[
        ..._entries.sublist(0, index),
        refreshed,
        ..._entries.sublist(index + 1),
      ];
      await _store.saveAll(next);
      _invalidateEntryRuntime(mcpKeywordIndexSystemEntryId);
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

  /// 进程级停机（dispose / SIGTERM / SIGINT）。与 [_isShuttingDown] 不同，
  /// 它一旦置位就不再解除；桌面端窗口全部关闭触发的 detached 不属于此类，
  /// 那只是可恢复的挂起。
  bool _isPermanentlyStopped = false;
  int _runtimeGeneration = 0;
  final Set<Object> _activeExecutionTokens = <Object>{};
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  final SerialTaskQueue _mutationQueue = SerialTaskQueue();
  final OpenHandSingleFlight<void> _systemUserScanFlight =
      OpenHandSingleFlight<void>();
  Completer<void>? _activeExecutionsCompleter;
  Future<void>? _shutdownFuture;

  /// 按任务 ID 保存的活动定时器。
  final Map<String, Timer> _scheduledTimers = {};

  /// 按任务 ID 保存的运行中进程任务。
  final Map<String, CronExecutionHandle> _runningJobs = {};

  /// 进程任务启动完成前的短暂占位，防止状态通知同步重入造成重复启动。
  final Map<String, Object> _startingJobTokens = <String, Object>{};

  /// 系统托管任务的执行令牌。超时后原任务仍未结束时保留令牌，避免重复调度。
  final Map<String, Object> _runningManagedJobTokens = <String, Object>{};

  /// 单个任务运行态令牌。配置变更后，旧执行结果不得回写新配置。
  final Map<String, Object> _entryRuntimeTokens = <String, Object>{};

  /// 按任务 ID 缓存的执行历史。
  final Map<String, List<CronExecutionRecord>> _historyCache = {};

  /// 供运行用户选择器使用的系统用户列表。
  List<String> _systemUsers = const <String>['root'];

  List<CronEntry> get entries => _entriesView;

  int get _activeExecutionCount => _activeExecutionTokens.length;

  Future<void> get _activeExecutionsIdle =>
      _activeExecutionsCompleter?.future ?? Future<void>.value();

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

  void _cacheHistory(String cronId, Iterable<CronExecutionRecord> records) {
    _historyCache.remove(cronId);
    _historyCache[cronId] = List<CronExecutionRecord>.unmodifiable(
      records.take(_maxCachedHistoryRecordsPerJob),
    );
    while (_historyCache.length > _maxCachedHistoryJobs) {
      _historyCache.remove(_historyCache.keys.first);
    }
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _startShutdownCleanup();
    _isDisposed = true;
    super.dispose();
  }

  /// 停止调度并有界等待队列和活动任务结束，可重复调用。
  Future<void> shutdown() => _startShutdownCleanup();

  Future<void> _startShutdownCleanup() {
    final active = _shutdownFuture;
    if (active != null) return active;
    if (_hasInitialized) WidgetsBinding.instance.removeObserver(this);
    _shutdownSchedulersAndJobs(permanent: true);
    final shutdown = () async {
      await runAsyncCleanupBounded(
        () => Future.wait<void>(<Future<void>>[
          _mutationQueue.idle,
          _systemUserScanFlight.idle,
          _activeExecutionsIdle,
        ]),
        timeout: _cronControllerShutdownTimeout,
        onError: (error, stack) =>
            silentLog('crons_controller', '等待定时任务控制器关闭', error, stack),
      );
      if (!_isDisposed) dispose();
    }();
    _shutdownFuture = shutdown;
    return shutdown;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.detached) {
      _shutdownSchedulersAndJobs(permanent: false);
      return;
    }
    if (_isDisposed || _isPermanentlyStopped) return;
    // detached 在桌面端只代表窗口全部关闭，应用仍可被重新唤起。必须解除
    // 停机闩锁，否则 _canExecuteInCurrentState 恒为 false，_restartScheduler
    // 与 runNow 都会静默直接 return，所有定时任务永久失效。
    _isShuttingDown = false;
    _restartScheduler();
    notifyListeners();
  }

  // 增删改查
  Future<bool> addCron(CronEntry entry) async {
    return _commitMutation(() async {
      final userEntryCount = _entries
          .where((item) => item.scriptType != CronScriptType.managed)
          .length;
      if (userEntryCount >= kCronMaxUserEntryCount) {
        _errorMessage = '用户定时任务不能超过 $kCronMaxUserEntryCount 条。';
        notifyListeners();
        return false;
      }
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
      final status = !entry.enabled
          ? CronJobStatus.paused
          : _isEntryExecuting(id) || current.status == CronJobStatus.paused
          ? CronJobStatus.idle
          : current.status;
      final preserved = entry.copyWith(
        status: status,
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
      _invalidateEntryRuntime(id);
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
      // 系统管理任务不允许用户删除。
      if (target.tags.contains(systemTag)) return false;
      final next = _entries.where((item) => item.id != normalizedId).toList();
      if (next.length == before) return false;
      await _store.saveAll(next);
      _invalidateEntryRuntime(normalizedId, removeToken: true);
      _setEntries(next);
      _historyCache.remove(normalizedId);
      try {
        await _store.deleteHistoryForCron(normalizedId);
      } catch (error, stack) {
        silentLog('crons_controller', '删除已移除定时任务的历史', error, stack);
      }
      return true;
    });
  }

  static const CronEntry _missingSentinel = CronEntry(id: '', name: '');

  /// `appContext` 中存放 Hermes Talker 单次 tick 的会话级 JSON 报告
  /// （`List<SelfLearningSessionReport.toJson()>` 序列化结果）的键名。
  /// 由 `main.dart` 的任务处理器写入，由 Crons 历史 UI 解析渲染。
  static const String hermesTalkerReportsKey = 'hermes_talker.reports';

  /// `appContext` 中存放 Hermes Talker 单次 tick 聚合统计的键名
  /// （`{scanned, triggered, skipped, errors}` 的 JSON 编码）。
  static const String hermesTalkerStatsKey = 'hermes_talker.stats';

  /// `CronScriptType.managed` 任务的进程内处理器，由启动流程注入 Hermes Talker
  /// `SelfLearningScheduler`。处理器不应抛出异常。
  ///
  /// 返回的 [CronTaskHandlerResult.stdout] 写入历史记录的 stdout 字段，
  /// [CronTaskHandlerResult.appContext] 写入历史记录的 app_context 字段，
  /// 用于在 Crons 历史详情中展示富信息（例如 Hermes Talker 的会话报告）。
  Future<CronTaskHandlerResult> Function(CronEntry entry)? _taskHandler;

  /// 注册或替换系统托管任务处理器，传入 `null` 时移除。
  void registerTaskHandler(
    Future<CronTaskHandlerResult> Function(CronEntry entry)? handler,
  ) {
    _taskHandler = handler;
  }

  Future<bool> _executeManagedJob(
    CronEntry entry, {
    required String triggerType,
    required int generation,
    required Object entryRuntimeToken,
    required Object executionToken,
    required Object activeExecutionToken,
  }) async {
    var keepsManagedLock = false;
    final startedAt = DateTime.now();
    String stdout = '';
    Map<String, String> appContext = const <String, String>{};
    String status = 'success';
    String? errorMessage;
    try {
      final handler = _taskHandler;
      if (handler == null) {
        stdout = '未注册系统托管任务处理器，已跳过执行。';
      } else {
        final pending = handler(entry);
        late final CronTaskHandlerResult result;
        try {
          result = await pending.timeout(
            Duration(seconds: entry.timeoutSeconds),
          );
        } on TimeoutException {
          status = 'timed_out';
          errorMessage = '系统托管任务超时（${entry.timeoutSeconds} 秒）。';
          keepsManagedLock = true;
          _observeTimedOutManagedCompletion(
            pending,
            entryId: entry.id,
            executionToken: executionToken,
            activeExecutionToken: activeExecutionToken,
          );
          rethrow;
        }
        stdout = result.stdout;
        appContext = result.appContext;
      }
    } on TimeoutException {
      // 超时后仅在后台观察原任务，当前执行立即结束。
    } catch (error, stack) {
      status = 'failed';
      errorMessage = userFailureMessage(error, fallback: '系统托管任务执行失败，请稍后重试。');
      silentLog('crons_controller', '执行系统托管任务', error, stack);
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
    await _commitExecutionResult(
      entry,
      record,
      generation: generation,
      entryRuntimeToken: entryRuntimeToken,
      updateEntry: (current) => current.copyWith(
        status: switch (status) {
          'success' => CronJobStatus.idle,
          'timed_out' => CronJobStatus.error,
          _ => CronJobStatus.failed,
        },
        lastRunAt: startedAt,
        consecutiveFailures: status == 'success'
            ? 0
            : current.consecutiveFailures + 1,
        updatedAt: DateTime.now(),
      ),
    );
    return keepsManagedLock;
  }

  /// 原 Future 完成后释放超时任务的重入锁，避免不可取消任务重复堆积。
  void _observeTimedOutManagedCompletion(
    Future<CronTaskHandlerResult> pending, {
    required String entryId,
    required Object executionToken,
    required Object activeExecutionToken,
  }) {
    if (!identical(_runningManagedJobTokens[entryId], executionToken)) {
      _finishActiveExecution(activeExecutionToken);
      return;
    }

    unawaited(
      pending.then<void>(
        (_) {
          _finishActiveExecution(activeExecutionToken);
          _releaseManagedExecutionLock(entryId, executionToken);
        },
        onError: (Object error, StackTrace stack) {
          silentLog('crons_controller', '观察超时系统托管任务的迟到异常', error, stack);
          _finishActiveExecution(activeExecutionToken);
          _releaseManagedExecutionLock(entryId, executionToken);
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
      if (_entries[index].tags.contains(mcpKeywordIndexTag)) return false;
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
      if (!enabled) _invalidateEntryRuntime(normalizedId);
      _setEntries(next);
      return true;
    });
  }

  /// 立即手动执行定时任务。
  Future<void> runNow(String id) async {
    if (!_canExecuteInCurrentState) return;
    final index = _entries.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final entry = _entries[index];
    if (!entry.enabled) return;
    // 系统托管任务通过 [_taskHandler] 执行，无需脚本内容。
    if (entry.scriptType != CronScriptType.managed && !entry.hasScript) return;
    await _executeJob(entry, triggerType: 'manual');
  }

  Future<void> loadHistory(String cronId) async {
    final normalizedId = cronId.trim();
    if (normalizedId.isEmpty || normalizedId != cronId) return;
    await _enqueueHistoryOperation<void>('加载执行历史', null, () async {
      if (!_entries.any((entry) => entry.id == normalizedId)) {
        _historyCache.remove(normalizedId);
        return;
      }
      final records = await _store.loadHistory(normalizedId);
      _cacheHistory(normalizedId, records);
      notifyListeners();
    });
  }

  Future<bool> clearHistoryForCron(String cronId) async {
    return _enqueueHistoryOperation<bool>('清空定时任务历史', false, () async {
      await _store.deleteHistoryForCron(cronId);
      _historyCache.remove(cronId);
      notifyListeners();
      return true;
    });
  }

  Future<bool> deleteHistoryRecord(String cronId, String recordId) async {
    final normalizedCronId = cronId.trim();
    final normalizedRecordId = recordId.trim();
    if (normalizedCronId.isEmpty ||
        normalizedCronId != cronId ||
        normalizedRecordId.isEmpty ||
        normalizedRecordId != recordId) {
      return false;
    }
    return _enqueueHistoryOperation<bool>('删除执行历史记录', false, () async {
      final deleted = await _store.deleteHistoryRecord(
        normalizedCronId,
        normalizedRecordId,
      );
      if (!deleted) return false;
      final cached = _historyCache[normalizedCronId];
      if (cached != null) {
        _historyCache[normalizedCronId] =
            List<CronExecutionRecord>.unmodifiable(
              cached.where((record) => record.id != normalizedRecordId),
            );
      }
      notifyListeners();
      return true;
    });
  }

  /// 删除所有 [cutoff] 之前的执行历史，返回受影响的行数。
  /// 同步刷新内存缓存以避免 UI 看到陈旧数据。
  /// 这是一个"尽力而为"的清理，调用方负责自身的异常兜底；
  /// 失败时返回 0，不抛异常。
  Future<int> purgeHistoryOlderThan(DateTime cutoff) async {
    return _enqueueHistoryOperation<int>('清理过期执行历史', 0, () async {
      final affected = await _store.deleteHistoryOlderThan(cutoff);
      if (affected == 0) return 0;
      for (final cronId in _historyCache.keys.toList()) {
        final cached = _historyCache[cronId];
        if (cached == null) continue;
        _historyCache[cronId] = List<CronExecutionRecord>.unmodifiable(
          cached.where((record) => record.startedAt.isAfter(cutoff)),
        );
      }
      notifyListeners();
      return affected;
    });
  }

  /// 清空全部 cron 执行历史。仅由全局设置中的“日志清理 / 全部数据清空”
  /// 触发，失败时向调用方报告，避免界面误报清理成功。
  Future<int> clearAllHistory() async {
    if (_isDisposed || _isPermanentlyStopped) {
      throw StateError('定时任务控制器已停止。');
    }
    return _mutationQueue.enqueue(() async {
      if (_isDisposed) throw StateError('定时任务控制器已停止。');
      await _store.ensureTable();
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
      for (final entry in removedEntries) {
        _invalidateEntryRuntime(entry.id, removeToken: true);
      }
      _setEntries(preserved);
      for (final entry in removedEntries) {
        _historyCache.remove(entry.id);
        try {
          await _store.deleteHistoryForCron(entry.id);
        } catch (error, stack) {
          silentLog(
            'crons_controller',
            '清空非系统定时任务历史/${entry.id}',
            error,
            stack,
          );
        }
      }
      return true;
    });
    if (!committed) {
      throw StateError(_errorMessage ?? '清空非系统定时任务失败。');
    }
    return removed;
  }

  Future<void> refresh() async {
    if (_isDisposed || _isPermanentlyStopped) return;
    await _mutationQueue.enqueue(() async {
      if (_isDisposed || _isPermanentlyStopped) return;
      await _loadConfigurationLocked();
    });
  }

  /// 扫描当前机器可用的系统用户。
  Future<void> scanSystemUsers() {
    if (_isDisposed || _isPermanentlyStopped) return Future<void>.value();
    return _systemUserScanFlight.run(_scanSystemUsers);
  }

  Future<void> _scanSystemUsers() async {
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
      if (_isDisposed || _isPermanentlyStopped) return;
      if (result != null && result.exitCode == 0) {
        final users = trimmedNonEmptyStrings(
          (result.stdout as String).split('\n'),
        ).where((s) => !s.startsWith('#')).toList();
        if (users.isNotEmpty) {
          // 保证 root 位于列表首位。
          users.remove('root');
          _systemUsers = List<String>.unmodifiable(<String>['root', ...users]);
        }
      }
    } catch (error, stack) {
      silentLog('crons_controller', '扫描系统用户', error, stack);
      // 保留默认 root 用户。
    }
    notifyListeners();
  }

  bool get _canExecuteInCurrentState {
    return !_isDisposed &&
        _hasInitialized &&
        _hasTrustedSnapshot &&
        !_isShuttingDown &&
        _appLifecycleState != AppLifecycleState.detached;
  }

  void _shutdownSchedulersAndJobs({required bool permanent}) {
    if (permanent) _isPermanentlyStopped = true;
    if (!_isShuttingDown) {
      _isShuttingDown = true;
      _runtimeGeneration++;
      _cancelScheduledTimers();
      for (final job in _runningJobs.values) {
        job.cancel();
      }
    }
    if (!permanent) return;
    _runningJobs.clear();
    _startingJobTokens.clear();
    _runningManagedJobTokens.clear();
    _entryRuntimeTokens.clear();
  }

  // 调度
  void _startScheduler() {
    if (!_canExecuteInCurrentState) return;
    unawaited(scanSystemUsers());
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
    // 系统托管任务无需脚本内容，通过 [_taskHandler] 而非 [CronExecutor] 执行。
    if (entry.scriptType != CronScriptType.managed && !entry.hasScript) return;

    final nextRun = CronParser.nextRun(entry.cronExpression);
    if (nextRun == null) return;

    final delay = nextRun.difference(DateTime.now());
    if (delay.isNegative) {
      // 计划时间已过时，延迟一秒执行。
      _scheduledTimers[entry.id] = startSafeTimer(
        const Duration(seconds: 1),
        () => _onTimerFired(entry.id),
      );
    } else {
      // 单次定时最长 24 小时，避免 Timer 处理超长时限时溢出。
      final cappedDelay = delay > const Duration(hours: 24)
          ? const Duration(hours: 24)
          : delay;
      _scheduledTimers[entry.id] = startSafeTimer(
        cappedDelay,
        () => _onTimerFired(entry.id),
      );
    }

    // 只更新内存中的下次运行时间，避免触发持久化循环。
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
      // 24 小时分段定时提前触发，继续调度剩余时间。
      _scheduleJob(entry);
      return;
    }

    // 执行任务。
    _executeJob(entry);
  }

  Future<void> _executeJob(
    CronEntry entry, {
    String triggerType = 'scheduled',
  }) async {
    if (!_canExecuteInCurrentState) return;
    if (_isEntryExecuting(entry.id) ||
        _activeExecutionCount >= _maxConcurrentExecutions) {
      _scheduleCurrentEntry(entry.id);
      return;
    }
    final generation = _runtimeGeneration;
    final entryRuntimeToken = _ensureEntryRuntimeToken(entry.id);
    final isManaged = entry.scriptType == CronScriptType.managed;
    Object? managedExecutionToken;
    Object? processStartToken;
    if (isManaged) {
      managedExecutionToken = Object();
      _runningManagedJobTokens[entry.id] = managedExecutionToken;
    } else {
      processStartToken = Object();
      _startingJobTokens[entry.id] = processStartToken;
    }
    final activeExecutionToken = Object();
    _registerActiveExecution(activeExecutionToken);
    _updateEntryStatus(entry.id, CronJobStatus.running);

    if (!_isCurrentRuntime(
      generation,
      entryId: entry.id,
      entryRuntimeToken: entryRuntimeToken,
    )) {
      if (processStartToken != null &&
          identical(_startingJobTokens[entry.id], processStartToken)) {
        _startingJobTokens.remove(entry.id);
      }
      if (managedExecutionToken != null &&
          identical(
            _runningManagedJobTokens[entry.id],
            managedExecutionToken,
          )) {
        _runningManagedJobTokens.remove(entry.id);
      }
      _finishActiveExecution(activeExecutionToken);
      notifyListeners();
      return;
    }

    if (isManaged) {
      final executionToken = managedExecutionToken!;
      var keepsManagedLock = false;
      try {
        keepsManagedLock = await _executeManagedJob(
          entry,
          triggerType: triggerType,
          generation: generation,
          entryRuntimeToken: entryRuntimeToken,
          executionToken: executionToken,
          activeExecutionToken: activeExecutionToken,
        );
      } finally {
        if (keepsManagedLock) {
          notifyListeners();
        } else {
          _finishActiveExecution(activeExecutionToken);
          _releaseManagedExecutionLock(entry.id, executionToken);
        }
      }
      return;
    }

    CronExecutionHandle? executionHandle;
    try {
      executionHandle = CronExecutor.start(
        entry,
        triggerType: triggerType,
        runtimeContext: <String, String>{
          'app.lifecycle': _appLifecycleState.name,
        },
      );
      _runningJobs[entry.id] = executionHandle;
      if (processStartToken != null &&
          identical(_startingJobTokens[entry.id], processStartToken)) {
        _startingJobTokens.remove(entry.id);
      }
      final record = await executionHandle.result;
      final newStatus = switch (record.status) {
        'success' => CronJobStatus.idle,
        'timed_out' => CronJobStatus.error,
        'failed' => CronJobStatus.failed,
        'killed' => CronJobStatus.idle,
        _ => CronJobStatus.error,
      };
      final committed = await _commitExecutionResult(
        entry,
        record,
        generation: generation,
        entryRuntimeToken: entryRuntimeToken,
        updateEntry: (current) => current.copyWith(
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
      );
      if (committed) {
        try {
          await _sendExecutionNotification(entry, record);
        } catch (error, stack) {
          silentLog('crons_controller', '发送定时任务通知', error, stack);
        }
      }
    } catch (error, stack) {
      silentLog('crons_controller', '执行定时任务', error, stack);
      await _commitRuntimeEntry(
        entry.id,
        (current) => current.copyWith(
          status: CronJobStatus.error,
          consecutiveFailures: current.consecutiveFailures + 1,
          updatedAt: DateTime.now(),
        ),
        generation: generation,
        entryRuntimeToken: entryRuntimeToken,
      );
    } finally {
      if (processStartToken != null &&
          identical(_startingJobTokens[entry.id], processStartToken)) {
        _startingJobTokens.remove(entry.id);
      }
      if (executionHandle != null &&
          identical(_runningJobs[entry.id], executionHandle)) {
        _runningJobs.remove(entry.id);
      }
      _finishActiveExecution(activeExecutionToken);
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

  void _registerActiveExecution(Object token) {
    if (_activeExecutionTokens.isEmpty) {
      _activeExecutionsCompleter = Completer<void>();
    }
    _activeExecutionTokens.add(token);
  }

  void _finishActiveExecution(Object token) {
    if (!_activeExecutionTokens.remove(token) ||
        _activeExecutionTokens.isNotEmpty) {
      return;
    }
    final completer = _activeExecutionsCompleter;
    _activeExecutionsCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Object _ensureEntryRuntimeToken(String id) {
    return _entryRuntimeTokens.putIfAbsent(id, Object.new);
  }

  bool _isEntryExecuting(String id) {
    return _runningJobs.containsKey(id) ||
        _startingJobTokens.containsKey(id) ||
        _runningManagedJobTokens.containsKey(id);
  }

  void _releaseManagedExecutionLock(String entryId, Object executionToken) {
    if (!identical(_runningManagedJobTokens[entryId], executionToken)) return;
    _runningManagedJobTokens.remove(entryId);
    final index = _entries.indexWhere((entry) => entry.id == entryId);
    if (index >= 0) {
      final current = _entries[index];
      if (current.status == CronJobStatus.running) {
        _entries[index] = current.copyWith(
          status: current.enabled ? CronJobStatus.idle : CronJobStatus.paused,
        );
        _refreshEntriesView();
      }
    }
    _scheduleCurrentEntry(entryId);
    notifyListeners();
  }

  void _invalidateEntryRuntime(String id, {bool removeToken = false}) {
    if (removeToken) {
      _entryRuntimeTokens.remove(id);
    } else {
      _entryRuntimeTokens[id] = Object();
    }
    _runningJobs[id]?.cancel();
  }

  bool _isCurrentRuntime(
    int generation, {
    String? entryId,
    Object? entryRuntimeToken,
  }) {
    if (generation != _runtimeGeneration || !_canExecuteInCurrentState) {
      return false;
    }
    return entryId == null ||
        entryRuntimeToken == null ||
        identical(_entryRuntimeTokens[entryId], entryRuntimeToken);
  }

  Future<bool> _commitExecutionResult(
    CronEntry entry,
    CronExecutionRecord record, {
    required int generation,
    required Object entryRuntimeToken,
    required CronEntry Function(CronEntry current) updateEntry,
  }) {
    return _mutationQueue.enqueue(() async {
      if (!_isCurrentRuntime(
        generation,
        entryId: entry.id,
        entryRuntimeToken: entryRuntimeToken,
      )) {
        return false;
      }
      try {
        await _store.insertHistory(record);
        await _store.pruneHistory(entry.id);
      } catch (error, stack) {
        silentLog('crons_controller', '保存定时任务历史', error, stack);
      }
      if (!_isCurrentRuntime(
        generation,
        entryId: entry.id,
        entryRuntimeToken: entryRuntimeToken,
      )) {
        return false;
      }
      final index = _entries.indexWhere((current) => current.id == entry.id);
      if (index < 0) return false;
      final updated = updateEntry(_entries[index]);
      try {
        await _store.updateRuntimeState(updated);
      } catch (error, stack) {
        silentLog('crons_controller', '保存定时任务运行状态', error, stack);
        return false;
      }
      if (!_isCurrentRuntime(
        generation,
        entryId: entry.id,
        entryRuntimeToken: entryRuntimeToken,
      )) {
        return false;
      }
      final cached = _historyCache[entry.id];
      if (cached != null) {
        _cacheHistory(entry.id, <CronExecutionRecord>[record, ...cached]);
      }
      _entries[index] = updated;
      _refreshEntriesView();
      notifyListeners();
      return true;
    });
  }

  Future<bool> _commitRuntimeEntry(
    String id,
    CronEntry Function(CronEntry current) update, {
    required int generation,
    required Object entryRuntimeToken,
  }) {
    return _mutationQueue.enqueue(() async {
      if (!_isCurrentRuntime(
        generation,
        entryId: id,
        entryRuntimeToken: entryRuntimeToken,
      )) {
        return false;
      }
      final index = _entries.indexWhere((entry) => entry.id == id);
      if (index < 0) return false;
      final updated = update(_entries[index]);
      try {
        await _store.updateRuntimeState(updated);
      } catch (error, stack) {
        silentLog('crons_controller', '保存定时任务运行状态', error, stack);
        return false;
      }
      if (!_isCurrentRuntime(
        generation,
        entryId: id,
        entryRuntimeToken: entryRuntimeToken,
      )) {
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
    _entries = entries
        .map((entry) {
          if (!_runningManagedJobTokens.containsKey(entry.id)) return entry;
          final status = entry.enabled
              ? CronJobStatus.running
              : CronJobStatus.paused;
          return entry.status == status
              ? entry
              : entry.copyWith(status: status);
        })
        .toList(growable: false);
    final activeIds = _entries.map((entry) => entry.id).toSet();
    _historyCache.removeWhere((id, _) => !activeIds.contains(id));
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

    final statusLabel = switch (record.status) {
      'success' => openHandAmbientText(
        zh: '执行成功',
        en: 'Succeeded',
        zhHant: '執行成功',
        fr: 'Réussi',
        de: 'Erfolgreich',
        ja: '成功',
      ),
      'timed_out' => openHandAmbientText(
        zh: '执行超时',
        en: 'Timed Out',
        zhHant: '執行逾時',
        fr: 'Délai dépassé',
        de: 'Zeitüberschreitung',
        ja: 'タイムアウト',
      ),
      'failed' => openHandAmbientText(
        zh: '执行失败',
        en: 'Failed',
        zhHant: '執行失敗',
        fr: 'Échec',
        de: 'Fehlgeschlagen',
        ja: '失敗',
      ),
      _ => record.status,
    };

    final title = openHandAmbientText(
      zh: '定时任务：${entry.name}',
      en: 'Cron Job: ${entry.name}',
      zhHant: '定時任務：${entry.name}',
      fr: 'Tâche planifiée : ${entry.name}',
      de: 'Cron-Aufgabe: ${entry.name}',
      ja: '定期タスク: ${entry.name}',
    );
    final body = _resolveNotificationBody(entry, record, statusLabel);
    final level = notifyConfig.severity.notificationLevel;

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

  String _resolveNotificationBody(
    CronEntry entry,
    CronExecutionRecord record,
    String statusLabel,
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
    // 仅失败且带错误详情时追加原因，其余状态共用同一条耗时文案。
    final error = record.status == 'success'
        ? ''
        : (record.errorMessage ?? '').trim();
    if (error.isEmpty) {
      return openHandAmbientText(
        zh: '$statusLabel，耗时 $elapsed。',
        en: '$statusLabel in $elapsed.',
        zhHant: '$statusLabel，耗時 $elapsed。',
        fr: '$statusLabel en $elapsed.',
        de: '$statusLabel in $elapsed.',
        ja: '$statusLabel、所要時間 $elapsed。',
      );
    }
    return openHandAmbientText(
      zh: '$statusLabel，耗时 $elapsed。原因：$error',
      en: '$statusLabel in $elapsed. Reason: $error',
      zhHant: '$statusLabel，耗時 $elapsed。原因：$error',
      fr: '$statusLabel en $elapsed. Raison : $error',
      de: '$statusLabel in $elapsed. Grund: $error',
      ja: '$statusLabel、所要時間 $elapsed。理由: $error',
    );
  }

  // 变更队列
  Future<T> _enqueueHistoryOperation<T>(
    String tag,
    T fallback,
    Future<T> Function() operation,
  ) {
    if (_isDisposed || _isPermanentlyStopped) {
      return Future<T>.value(fallback);
    }
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
    if (_isDisposed || _isPermanentlyStopped) {
      return Future<bool>.value(false);
    }
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
        _hasTrustedSnapshot = true;
        _errorMessage = userFailureMessage(error, fallback: '定时任务保存失败，请稍后重试。');
        silentLog('crons_controller', '提交定时任务变更', error, stack);
        _restartScheduler();
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

/// 系统托管任务处理函数返回的结构化结果。
///
/// * [stdout] 写入 [CronExecutionRecord.stdout]，用于历史详情默认展示。
/// * [appContext] 写入 [CronExecutionRecord.appContext]，用于承载结构化
///   元数据（例如 Hermes Talker 的会话级 JSON 报告），由 UI 侧根据特定
///   key 渲染富面板。
class CronTaskHandlerResult {
  const CronTaskHandlerResult({
    this.stdout = '',
    this.appContext = const <String, String>{},
  });

  final String stdout;
  final Map<String, String> appContext;
}

/// [CronNotifySeverity] 到通知级别的唯一映射，控制器与编辑弹窗共用，
/// 避免两处 switch 随枚举演进各自漂移。
extension CronNotifySeverityLevel on CronNotifySeverity {
  OpenHandNotificationLevel get notificationLevel => switch (this) {
    CronNotifySeverity.info => OpenHandNotificationLevel.info,
    CronNotifySeverity.success => OpenHandNotificationLevel.success,
    CronNotifySeverity.warning => OpenHandNotificationLevel.warning,
    CronNotifySeverity.error => OpenHandNotificationLevel.error,
    CronNotifySeverity.critical => OpenHandNotificationLevel.critical,
  };
}

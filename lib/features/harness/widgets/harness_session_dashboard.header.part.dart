part of 'harness_session_dashboard.dart';

const Duration _heTokenUsageRefreshDelay = Duration(milliseconds: 140);
const Duration _heTokenUsageLoadTimeout = Duration(seconds: 8);
const double _heToolbarItemSpacing = 4;

class _HePaneHeader extends StatelessWidget {
  const _HePaneHeader({
    required this.config,
    required this.orchestrator,
    required this.isZh,
    required this.isRunning,
    required this.isDone,
    required this.sessionTitle,
    required this.updatedAtLabel,
    required this.sessionId,
    required this.createdAtLabel,
    required this.sessionCreatedAt,
    required this.sessionUpdatedAt,
    required this.onCancel,
    required this.onRestart,
    required this.fullAccessPermission,
    required this.onToggleFullAccess,
    this.replayPendingDeadlineListenable,
    this.onCancelPendingReplay,
  });

  final HarnessSessionConfig config;
  final HarnessOrchestrator orchestrator;
  final bool isZh;
  final bool isRunning;
  final bool isDone;
  final String? sessionTitle;
  final String? updatedAtLabel;
  final String? sessionId;
  final String? createdAtLabel;
  final DateTime? sessionCreatedAt;
  final DateTime? sessionUpdatedAt;
  final VoidCallback onCancel;
  final VoidCallback onRestart;
  final bool fullAccessPermission;
  final ValueChanged<bool> onToggleFullAccess;

  /// 传入后，从 [ToolSearchReplayDispatcher.pendingDeadlineListenable] 领取
  /// 反悔窗口 deadline；window 内按秒起动倒计时 chip。
  final ValueListenable<DateTime?>? replayPendingDeadlineListenable;

  /// 点击 chip 时调用；通常接 [ToolSearchReplayDispatcher.cancel]。
  final VoidCallback? onCancelPendingReplay;

  String _effectiveTitle(BuildContext context) =>
      (sessionTitle?.trim().isNotEmpty == true)
      ? sessionTitle!
      : openHandLocalizedText(
          context,
          zh: 'Harness Engineering 会话',
          zhHant: 'Harness Engineering 會話',
          en: 'Harness Engineering Session',
          fr: 'Session Harness Engineering',
          de: 'Harness Engineering-Sitzung',
          ja: 'Harness Engineering セッション',
        );

  /// 返回“元数据采集 1/3”形式的当前执行位置。
  String _phaseProgressLabel(BuildContext context) {
    final logs = orchestrator.phaseLogs;
    final total = logs.length;
    final awaitingApproval = orchestrator.awaitingApprovalPhase;
    if (awaitingApproval != null) {
      final idx = logs.indexWhere((l) => l.phase == awaitingApproval);
      final pos = idx >= 0 ? idx + 1 : total;
      final name = _heHarnessPhaseLabel(context, awaitingApproval);
      return openHandLocalizedText(
        context,
        zh: '$name $pos/$total · 待批准',
        zhHant: '$name $pos/$total · 待核准',
        en: '$name $pos/$total · Awaiting Approval',
        fr: '$name $pos/$total · En attente d’approbation',
        de: '$name $pos/$total · Wartet auf Freigabe',
        ja: '$name $pos/$total · 承認待ち',
      );
    }
    final current = orchestrator.currentPhase;
    if (isRunning && current != null) {
      final idx = logs.indexWhere((l) => l.phase == current);
      final pos = idx >= 0 ? idx + 1 : total;
      final name = _heHarnessPhaseLabel(context, current);
      return '$name $pos/$total';
    }
    final completed = logs
        .where((l) => l.status == HarnessPhaseStatus.completed)
        .length;
    final failed = logs
        .where((l) => l.status == HarnessPhaseStatus.failed)
        .length;
    if (total == 0) {
      return openHandLocalizedText(
        context,
        zh: '待开始',
        zhHant: '尚未開始',
        en: 'Not started',
        fr: 'Non démarré',
        de: 'Nicht gestartet',
        ja: '未開始',
      );
    }
    if (failed > 0) {
      return openHandLocalizedText(
        context,
        zh: '阶段失败 $failed/$total',
        zhHant: '階段失敗 $failed/$total',
        en: '$failed/$total failed',
        fr: '$failed/$total en échec',
        de: '$failed/$total fehlgeschlagen',
        ja: '$failed/$total 失敗',
      );
    }
    if (completed == total) {
      return openHandLocalizedText(
        context,
        zh: '全部完成 $total',
        zhHant: '全部完成 $total',
        en: '$total done',
        fr: '$total terminées',
        de: '$total erledigt',
        ja: '$total 件完了',
      );
    }
    return openHandLocalizedText(
      context,
      zh: '完成 $completed/$total',
      zhHant: '完成 $completed/$total',
      en: '$completed/$total done',
      fr: '$completed/$total terminées',
      de: '$completed/$total erledigt',
      ja: '$completed/$total 完了',
    );
  }

  IconData _phaseProgressIcon() {
    if (orchestrator.awaitingApprovalPhase != null) {
      return Icons.pause_circle_filled_rounded;
    }
    if (isRunning) return Icons.sync_rounded;
    final logs = orchestrator.phaseLogs;
    if (logs.any((l) => l.status == HarnessPhaseStatus.failed)) {
      return Icons.error_outline_rounded;
    }
    if (orchestrator.status == HarnessOrchestratorStatus.completed) {
      return Icons.check_circle_outline_rounded;
    }
    if (orchestrator.status == HarnessOrchestratorStatus.cancelled) {
      return Icons.cancel_outlined;
    }
    return Icons.pending_outlined;
  }

  Color _phaseProgressColor(ColorScheme cs) {
    if (orchestrator.awaitingApprovalPhase != null) {
      return _hePausedTone;
    }
    if (isRunning) return _heRunningTone;
    final logs = orchestrator.phaseLogs;
    if (logs.any((l) => l.status == HarnessPhaseStatus.failed)) {
      return _heFailedTone;
    }
    if (orchestrator.status == HarnessOrchestratorStatus.completed) {
      return _heCompletedTone;
    }
    if (orchestrator.status == HarnessOrchestratorStatus.cancelled) {
      return _hePausedTone;
    }
    return _hePendingTone;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reviewRetries = orchestrator.reviewRetryCount;
    final effectiveTitle = _effectiveTitle(context);
    final toolbarItems = <Widget>[
      OhPill(
        icon: _phaseProgressIcon(),
        label: _phaseProgressLabel(context),
        foregroundColor: _phaseProgressColor(colorScheme),
      ),
      if (replayPendingDeadlineListenable != null)
        HarnessPendingReplayBadge(
          isZh: isZh,
          deadlineListenable: replayPendingDeadlineListenable!,
          onCancel: onCancelPendingReplay,
        ),
      if (reviewRetries > 0)
        OhPill(
          icon: Icons.replay_rounded,
          label: openHandLocalizedText(
            context,
            zh: '重试 $reviewRetries/3',
            zhHant: '重試 $reviewRetries/3',
            en: 'Retry $reviewRetries/3',
            fr: 'Réessai $reviewRetries/3',
            de: 'Wiederholung $reviewRetries/3',
            ja: '再試行 $reviewRetries/3',
          ),
          foregroundColor: const Color(0xFFF57F17),
        ),
      const OhPill(
        icon: Icons.layers_rounded,
        label: 'Harness Engineering · v$kHarnessOrchestratorDisplayVersion',
      ),
      OhPill(
        icon: Icons.data_object_rounded,
        label: openHandLocalizedText(
          context,
          zh: '会话元数据',
          zhHant: '會話中繼資料',
          en: 'Session Metadata',
          fr: 'Métadonnées de session',
          de: 'Sitzungsmetadaten',
          ja: 'セッションメタデータ',
        ),
        onTap: () => _showSessionMetadata(context),
      ),
      OhPill(
        icon: Icons.folder_special_rounded,
        label: openHandLocalizedText(
          context,
          zh: '资产文件',
          zhHant: '資產檔案',
          en: 'Steering Assets',
          fr: 'Ressources de pilotage',
          de: 'Steuerungsdateien',
          ja: 'ステアリング資産',
        ),
        onTap: () => _showSteeringAssets(context),
      ),
      if (isRunning)
        OhPill(
          icon: Icons.stop_circle_outlined,
          label: _heCancelLabel(context),
          foregroundColor: colorScheme.error,
          onTap: onCancel,
        ),
      if (isDone && orchestrator.status != HarnessOrchestratorStatus.completed)
        OhPill(
          icon: Icons.restart_alt_rounded,
          label: orchestrator.status == HarnessOrchestratorStatus.failed
              ? _heRetryFailedPhaseLabel(context)
              : openHandLocalizedText(
                  context,
                  zh: '重新开始',
                  zhHant: '重新開始',
                  en: 'Restart',
                  fr: 'Redémarrer',
                  de: 'Neu starten',
                  ja: '再開',
                ),
          onTap: onRestart,
        ),
      _HeTokenUsageDial(
        key: ValueKey<String>('harness-token-${sessionId ?? ''}'),
        sessionId: sessionId,
        legacyStartAt: sessionCreatedAt,
        legacyEndAt: isRunning ? null : sessionUpdatedAt,
      ),
    ];

    return OpenHandSessionHeaderBar(
      toolbarSpacing: _heToolbarItemSpacing,
      toolbarItems: toolbarItems,
      title: OpenHandAnimatedTitleText(
        text: effectiveTitle,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  void _showSessionMetadata(BuildContext context) {
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => _HeSessionMetadataDialog(
        config: config,
        orchestrator: orchestrator,
        sessionTitle: _effectiveTitle(context),
        sessionId: sessionId,
        createdAtLabel: createdAtLabel,
        updatedAtLabel: updatedAtLabel,
      ),
    );
  }

  void _showSteeringAssets(BuildContext context) {
    final steeringRoot = p.join(config.persistenceDirectory, 'steering');
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _HeSteeringAssetsDialog(steeringRoot: steeringRoot),
    );
  }
}

class _HeTokenUsageDial extends StatefulWidget {
  const _HeTokenUsageDial({
    super.key,
    required this.sessionId,
    required this.legacyStartAt,
    required this.legacyEndAt,
  });

  final String? sessionId;
  final DateTime? legacyStartAt;
  final DateTime? legacyEndAt;

  @override
  State<_HeTokenUsageDial> createState() => _HeTokenUsageDialState();
}

class _HeTokenUsageDialState extends State<_HeTokenUsageDial> {
  final AiUsageTracker _tracker = AiUsageTracker.instance;
  AiUsageSummary _summary = const AiUsageSummary();
  Timer? _refreshTimer;
  int _loadGeneration = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _tracker.changes.addListener(_scheduleRefresh);
    unawaited(_loadSummary());
  }

  @override
  void didUpdateWidget(covariant _HeTokenUsageDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId == widget.sessionId &&
        oldWidget.legacyStartAt == widget.legacyStartAt &&
        oldWidget.legacyEndAt == widget.legacyEndAt) {
      return;
    }
    unawaited(_loadSummary());
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _refreshTimer?.cancel();
    _tracker.changes.removeListener(_scheduleRefresh);
    super.dispose();
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = startSafeTimer(_heTokenUsageRefreshDelay, () {
      _refreshTimer = null;
      if (mounted) return _loadSummary();
    });
  }

  Future<void> _loadSummary() async {
    final generation = ++_loadGeneration;
    final sessionId = widget.sessionId?.trim() ?? '';
    if (sessionId.isEmpty) {
      if (mounted) {
        setState(() {
          _summary = const AiUsageSummary();
          _loaded = true;
        });
      }
      return;
    }
    try {
      final summary = await _tracker
          .loadSessionSummary(
            sessionId: sessionId,
            source: AiUsageSource.harness,
            legacyStartAt: widget.legacyStartAt,
            legacyEndAt: widget.legacyEndAt,
          )
          .timeout(_heTokenUsageLoadTimeout);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _summary = summary;
        _loaded = true;
      });
    } catch (error, stack) {
      silentLog(
        'harness_session_dashboard',
        '加载 Harness Token 统计',
        error,
        stack,
      );
    }
  }

  AiSessionStatistics _buildStatistics() {
    final hasCacheUsage =
        _summary.cacheInputTokens > 0 ||
        _summary.cacheReadTokens > 0 ||
        _summary.cacheCreationTokens > 0;
    return AiSessionStatistics(
      totalMessageCount: _summary.requestCount + _summary.successCount,
      userMessageCount: _summary.requestCount,
      assistantMessageCount: _summary.successCount,
      toolMessageCount: 0,
      mcpMessageCount: 0,
      skillMessageCount: 0,
      compressionPointCount: 0,
      totalInputCharacters: 0,
      totalOutputCharacters: 0,
      totalPromptCharacters: 0,
      promptBuildCount: _summary.requestCount,
      compressionRunCount: 0,
      totalPromptTokens: _summary.promptTokens,
      totalCompletionTokens: _summary.completionTokens,
      totalTokens: _summary.totalTokens,
      cacheCreationTokens: hasCacheUsage ? _summary.cacheCreationTokens : null,
      cacheReadTokens: hasCacheUsage ? _summary.cacheReadTokens : null,
      reasoningTokens: _summary.reasoningTokens,
      audioInputTokens: _summary.audioInputTokens,
      imageInputTokens: _summary.imageInputTokens,
      videoInputTokens: _summary.videoInputTokens,
      cacheHitRatio: hasCacheUsage ? _summary.cacheHitRate : null,
    );
  }

  AiSession _buildSession(AiSessionStatistics statistics) {
    final usedTokens = _summary.latestContextUsedTokens;
    final windowTokens = _summary.latestContextWindowTokens;
    final hasContextUsage = usedTokens > 0 && windowTokens > 0;
    final contextMetadata = hasContextUsage
        ? <String, Object?>{
            aiContextUsedTokensMetadataKey: usedTokens,
            aiContextWindowTokensMetadataKey: windowTokens,
            aiContextUsageMetadataKey:
                AiContextUsageBreakdown.fromCharacterCounts(
                  <AiContextUsageCategory, int>{
                    AiContextUsageCategory.conversation: usedTokens,
                  },
                  totalTokens: usedTokens,
                ).toJson(),
          }
        : const <String, Object?>{};
    final createdAt =
        widget.legacyStartAt ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return AiSession(
      id: 'harness-token:${widget.sessionId?.trim() ?? ''}',
      title: 'Harness Engineering',
      templateId: 'harness_engineering',
      templateName: 'Harness Engineering',
      templateIconName: 'bolt',
      templateInternalVersion: '1.0.0',
      createdAt: createdAt,
      updatedAt: widget.legacyEndAt ?? createdAt,
      messages: const <AiSessionMessage>[],
      environment: AiSessionEnvironment.fromJson(const <String, Object?>{}),
      statistics: statistics,
      recentErrors: const <AiSessionErrorRecord>[],
      lastPromptMetadata: contextMetadata,
    );
  }

  @override
  Widget build(BuildContext context) {
    final statistics = _buildStatistics();
    final session = _buildSession(statistics);
    final enabled = _loaded && (widget.sessionId?.trim().isNotEmpty ?? false);
    final uncachedPromptTokens =
        _summary.cacheInputTokens -
        _summary.cacheReadTokens -
        _summary.cacheCreationTokens;
    return Semantics(
      button: enabled,
      enabled: enabled,
      label: openHandLocalizedText(
        context,
        zh: 'Token 统计',
        zhHant: 'Token 統計',
        en: 'Token usage',
        fr: 'Utilisation des tokens',
        de: 'Token-Nutzung',
        ja: 'Token 使用量',
      ),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: OpenHandSessionTokenUsageDial(
          session: session,
          statistics: statistics,
          claudeStyle: false,
          enabled: enabled,
          hydrateSessionStatistics: false,
          allowManualCompaction: false,
          uncachedPromptTokens: uncachedPromptTokens > 0
              ? uncachedPromptTokens
              : 0,
        ),
      ),
    );
  }
}

// Harness 会话元数据弹窗，与普通会话元数据弹窗保持一致。
class _HeSessionMetadataDialog extends StatelessWidget {
  const _HeSessionMetadataDialog({
    required this.config,
    required this.orchestrator,
    required this.sessionTitle,
    this.sessionId,
    this.createdAtLabel,
    this.updatedAtLabel,
  });

  final HarnessSessionConfig config;
  final HarnessOrchestrator orchestrator;
  final String sessionTitle;
  final String? sessionId;
  final String? createdAtLabel;
  final String? updatedAtLabel;

  String _statusLabel(BuildContext context, HarnessOrchestratorStatus s) =>
      switch (s) {
        HarnessOrchestratorStatus.idle => openHandLocalizedText(
          context,
          zh: '准备中',
          zhHant: '準備中',
          en: 'Idle',
          fr: 'Inactif',
          de: 'Bereit',
          ja: '待機中',
        ),
        HarnessOrchestratorStatus.running => _harnessSessionRunningLabel(
          context,
        ),
        HarnessOrchestratorStatus.completed => openHandCompletedLabel(context),
        HarnessOrchestratorStatus.failed => openHandFailedLabel(context),
        HarnessOrchestratorStatus.cancelled => _harnessSessionCancelledLabel(
          context,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final logs = orchestrator.phaseLogs;
    // 仅在模型列表变化时重建，忽略设置控制器的其他通知。
    final aiModels = context.select<SettingsController?, List<AiModelConfig>>(
      (controller) => controller?.aiModels ?? const <AiModelConfig>[],
    );

    final totalPhases = HarnessPhase.values.length;
    final completedPhases = logs
        .where((l) => l.status == HarnessPhaseStatus.completed)
        .length;
    final failedPhases = logs
        .where((l) => l.status == HarnessPhaseStatus.failed)
        .length;
    final totalLogLines = logs.fold<int>(0, (sum, l) => sum + l.lines.length);

    final summaryBlocks = <Widget>[
      OpenHandMetadataSummaryTile(
        label: openHandLocalizedText(
          context,
          zh: '阶段总数',
          zhHant: '階段總數',
          en: 'Total Phases',
          fr: 'Total des phases',
          de: 'Phasen gesamt',
          ja: 'フェーズ総数',
        ),
        value: '$totalPhases',
      ),
      OpenHandMetadataSummaryTile(
        label: openHandLocalizedText(
          context,
          zh: '已完成阶段',
          zhHant: '已完成階段',
          en: 'Completed',
          fr: 'Terminées',
          de: 'Abgeschlossen',
          ja: '完了済み',
        ),
        value: '$completedPhases',
      ),
      OpenHandMetadataSummaryTile(
        label: openHandLocalizedText(
          context,
          zh: '失败阶段',
          zhHant: '失敗階段',
          en: 'Failed',
          fr: 'Échecs',
          de: 'Fehlgeschlagen',
          ja: '失敗',
        ),
        value: '$failedPhases',
      ),
      OpenHandMetadataSummaryTile(
        label: openHandLocalizedText(
          context,
          zh: '日志总行数',
          zhHant: '日誌總行數',
          en: 'Total Log Lines',
          fr: 'Lignes de journal',
          de: 'Logzeilen gesamt',
          ja: 'ログ総行数',
        ),
        value: '$totalLogLines',
      ),
      OpenHandMetadataSummaryTile(
        label: _harnessSessionStatusLabel(context),
        value: _statusLabel(context, orchestrator.status),
      ),
      OpenHandMetadataSummaryTile(
        label: openHandLocalizedText(
          context,
          zh: '当前阶段',
          zhHant: '目前階段',
          en: 'Current Phase',
          fr: 'Phase actuelle',
          de: 'Aktuelle Phase',
          ja: '現在のフェーズ',
        ),
        value: orchestrator.currentPhase != null
            ? _heHarnessPhaseLabel(context, orchestrator.currentPhase!)
            : '--',
      ),
    ];

    final roleConfigs = <(String, HarnessRoleConfig)>[
      (
        openHandLocalizedText(
          context,
          zh: '探档者 (Profiler)',
          zhHant: '探檔者 (Profiler)',
          en: 'Profiler',
          fr: 'Profileur',
          de: 'Profiler',
          ja: 'プロファイラー',
        ),
        config.profilerConfig,
      ),
      (
        openHandLocalizedText(
          context,
          zh: '调查者 (Reader)',
          zhHant: '調查者 (Reader)',
          en: 'Reader',
          fr: 'Lecteur',
          de: 'Leser',
          ja: 'リーダー',
        ),
        config.readerConfig,
      ),
      (
        openHandLocalizedText(
          context,
          zh: '规划者 (Planner)',
          zhHant: '規劃者 (Planner)',
          en: 'Planner',
          fr: 'Planificateur',
          de: 'Planer',
          ja: 'プランナー',
        ),
        config.plannerConfig,
      ),
      (
        openHandLocalizedText(
          context,
          zh: '实施者 (Implementer)',
          zhHant: '實施者 (Implementer)',
          en: 'Implementer',
          fr: 'Implémenteur',
          de: 'Umsetzer',
          ja: '実装者',
        ),
        config.implementerConfig,
      ),
      (
        openHandLocalizedText(
          context,
          zh: '验收者 (Reviewer)',
          zhHant: '驗收者 (Reviewer)',
          en: 'Reviewer',
          fr: 'Relecteur',
          de: 'Prüfer',
          ja: 'レビュー担当',
        ),
        config.reviewerConfig,
      ),
    ];

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: double.infinity,
      maxHeightFraction: 0.82,
      safeAreaMinimum: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OpenHandMetadataDialogHeader(
              title: openHandLocalizedText(
                context,
                zh: '当前会话元数据',
                zhHant: '目前會話中繼資料',
                en: 'Current Session Metadata',
                fr: 'Métadonnées de la session',
                de: 'Aktuelle Sitzungsmetadaten',
                ja: '現在のセッションメタデータ',
              ),
              subtitle: sessionTitle,
            ),
            kOpenHandGap18,
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Summary tiles ──
                    Wrap(spacing: 12, runSpacing: 12, children: summaryBlocks),
                    kOpenHandGap18,

                    // ── Session overview ──
                    OpenHandMetadataSection(
                      title: openHandLocalizedText(
                        context,
                        zh: '会话概览',
                        zhHant: '會話概覽',
                        en: 'Session Overview',
                        fr: 'Aperçu de la session',
                        de: 'Sitzungsübersicht',
                        ja: 'セッション概要',
                      ),
                      children: [
                        OpenHandMetadataEntryRow(
                          label: openHandSessionIdLabel(context),
                          value: sessionId ?? '--',
                        ),
                        OpenHandMetadataEntryRow(
                          label: openHandTemplateLabel(context),
                          value: 'Harness Engineering',
                        ),
                        OpenHandMetadataEntryRow(
                          label: openHandCreatedAtLabel(context),
                          value: createdAtLabel ?? '--',
                        ),
                        OpenHandMetadataEntryRow(
                          label: openHandUpdatedAtLabel(context),
                          value: updatedAtLabel ?? '--',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _harnessSessionStatusLabel(context),
                          value: _statusLabel(context, orchestrator.status),
                        ),
                        if (orchestrator.errorMessage?.isNotEmpty == true)
                          OpenHandMetadataEntryRow(
                            label: openHandLocalizedText(
                              context,
                              zh: '错误信息',
                              zhHant: '錯誤資訊',
                              en: 'Error',
                              fr: 'Erreur',
                              de: 'Fehler',
                              ja: 'エラー',
                            ),
                            value: orchestrator.errorMessage!,
                          ),
                      ],
                    ),
                    kOpenHandGap16,

                    // ── Task config ──
                    OpenHandMetadataSection(
                      title: openHandLocalizedText(
                        context,
                        zh: '任务配置',
                        zhHant: '任務設定',
                        en: 'Task Config',
                        fr: 'Configuration de tâche',
                        de: 'Aufgabenkonfiguration',
                        ja: 'タスク設定',
                      ),
                      children: [
                        OpenHandMetadataEntryRow(
                          label: openHandTaskLabel(context),
                          value: config.task.isEmpty ? '-' : config.task,
                        ),
                        OpenHandMetadataEntryRow(
                          label: openHandWorkingDirectoryLabel(context),
                          value: config.workingDirectory.isEmpty
                              ? '-'
                              : config.workingDirectory,
                        ),
                        OpenHandMetadataEntryRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '持久化目录',
                            zhHant: '持久化目錄',
                            en: 'Persistence Directory',
                            fr: 'Répertoire de persistance',
                            de: 'Persistenzverzeichnis',
                            ja: '永続化ディレクトリ',
                          ),
                          value: config.persistenceDirectory.isEmpty
                              ? '-'
                              : config.persistenceDirectory,
                        ),
                      ],
                    ),
                    kOpenHandGap16,

                    // ── Role configs ──
                    OpenHandMetadataSection(
                      title: openHandLocalizedText(
                        context,
                        zh: '角色配置',
                        zhHant: '角色設定',
                        en: 'Role Configs',
                        fr: 'Configurations des rôles',
                        de: 'Rollenkonfigurationen',
                        ja: 'ロール設定',
                      ),
                      children: [
                        for (final entry in roleConfigs)
                          OpenHandMetadataEntryRow(
                            label: entry.$1,
                            value: entry.$2.isUrlMode
                                ? 'URL/API · ${_heDescribeAiModelConfig(context, aiModels, entry.$2.aiModelConfigId, urlModeModelId: entry.$2.urlModeModelId)}'
                                : entry.$2.isConfigured
                                ? '${entry.$2.cliName} · ${describeHarnessCliModel(entry.$2.modelId, locale: Localizations.localeOf(context))}'
                                : _heHarnessNotConfiguredText(context),
                          ),
                      ],
                    ),
                    kOpenHandGap16,

                    // ── Phase status ──
                    OpenHandMetadataSection(
                      title: openHandLocalizedText(
                        context,
                        zh: '阶段状态',
                        zhHant: '階段狀態',
                        en: 'Phase Status',
                        fr: 'État des phases',
                        de: 'Phasenstatus',
                        ja: 'フェーズ状態',
                      ),
                      children: [
                        for (final log in logs)
                          OpenHandMetadataEntryRow(
                            label: _heHarnessPhaseLabel(context, log.phase),
                            value: () {
                              final parts = <String>[
                                harnessPhaseStatusLabel(context, log.status),
                              ];
                              if (log.exitCode != null) {
                                parts.add(
                                  '${openHandLocalizedText(context, zh: '退出码', zhHant: '結束碼', en: 'Exit code', fr: 'Code de sortie', de: 'Exit-Code', ja: '終了コード')}: ${log.exitCode}',
                                );
                              }
                              parts.add(
                                '${openHandLocalizedText(context, zh: '日志行数', zhHant: '日誌行數', en: 'Log lines', fr: 'Lignes de journal', de: 'Logzeilen', ja: 'ログ行数')}: ${log.lines.length}',
                              );
                              if (log.savedLogPath?.isNotEmpty == true) {
                                parts.add(
                                  '${openHandLocalizedText(context, zh: '日志文件', zhHant: '日誌檔案', en: 'Log file', fr: 'Fichier journal', de: 'Logdatei', ja: 'ログファイル')}: ${log.savedLogPath}',
                                );
                              }
                              return parts.join(' · ');
                            }(),
                          ),
                      ],
                    ),
                    kOpenHandGap4,
                  ],
                ),
              ),
            ),
            kOpenHandGap18,

            // ── Close button ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  onPressed: () => Navigator.of(context).pop(),
                  label: openHandCloseLabel(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 阶段状态的唯一文案来源：头部摘要与阶段卡片共用，避免同一状态在两处
/// 出现「已完成 / 执行完成」这类只有中文不同的分叉。
String harnessPhaseStatusLabel(BuildContext context, HarnessPhaseStatus s) =>
    switch (s) {
      HarnessPhaseStatus.pending => openHandLocalizedText(
        context,
        zh: '等待中',
        zhHant: '等待中',
        en: 'Pending',
        fr: 'En attente',
        de: 'Ausstehend',
        ja: '待機中',
      ),
      HarnessPhaseStatus.paused => openHandLocalizedText(
        context,
        zh: '暂停中',
        zhHant: '暫停中',
        en: 'Paused',
        fr: 'En pause',
        de: 'Pausiert',
        ja: '一時停止中',
      ),
      HarnessPhaseStatus.running => _harnessSessionRunningLabel(context),
      HarnessPhaseStatus.completed => openHandCompletedLabel(context),
      HarnessPhaseStatus.failed => openHandFailedLabel(context),
      HarnessPhaseStatus.cancelled => _harnessSessionCancelledLabel(context),
      HarnessPhaseStatus.skipped => openHandLocalizedText(
        context,
        zh: '已跳过',
        zhHant: '已跳過',
        en: 'Skipped',
        fr: 'Ignoré',
        de: 'Übersprungen',
        ja: 'スキップ済み',
      ),
    };

String _harnessSessionCancelledLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已中止',
    zhHant: '已中止',
    en: 'Cancelled',
    fr: 'Annulé',
    de: 'Abgebrochen',
    ja: '中止済み',
  );
}

String _harnessSessionRunningLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '运行中',
    zhHant: '執行中',
    en: 'Running',
    fr: 'En cours',
    de: 'Wird ausgeführt',
    ja: '実行中',
  );
}

String _harnessSessionStatusLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '执行状态',
    zhHant: '執行狀態',
    en: 'Status',
    fr: 'État',
    de: 'Status',
    ja: '状態',
  );
}

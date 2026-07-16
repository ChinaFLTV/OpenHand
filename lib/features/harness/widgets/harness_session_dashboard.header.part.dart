part of 'harness_session_dashboard.dart';

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

  /// Returns a label like "元数据采集 1/3" describing current execution position.
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
    final logs = orchestrator.phaseLogs;
    final reviewRetries = orchestrator.reviewRetryCount;
    final totalLines = logs.fold<int>(0, (sum, l) => sum + l.lines.length);
    final effectiveTitle = _effectiveTitle(context);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: OpenHandAnimatedTitleText(
                    text: effectiveTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: Row(
                      children: [
                        // ── Phase progress (mirrors runtime mode / template pill) ──
                        OhPill(
                          icon: _phaseProgressIcon(),
                          label: _phaseProgressLabel(context),
                          foregroundColor: _phaseProgressColor(colorScheme),
                        ),
                        if (replayPendingDeadlineListenable != null) ...[
                          const SizedBox(width: 8),
                          HarnessPendingReplayBadge(
                            isZh: isZh,
                            deadlineListenable:
                                replayPendingDeadlineListenable!,
                            onCancel: onCancelPendingReplay,
                          ),
                        ],
                        if (reviewRetries > 0) ...[
                          const SizedBox(width: 8),
                          // ── Review retry counter ──
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
                            foregroundColor: const Color(0xFFF57F17), // amber
                          ),
                        ],
                        const SizedBox(width: 8),
                        const OhPill(
                          icon: Icons.layers_rounded,
                          label:
                              'Harness Engineering · v$kHarnessOrchestratorDisplayVersion',
                        ),
                        const SizedBox(width: 8),
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
                        const SizedBox(width: 8),
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
                        if (updatedAtLabel?.isNotEmpty == true) ...[
                          const SizedBox(width: 8),
                          OhPill(
                            icon: Icons.update_rounded,
                            label: updatedAtLabel!,
                          ),
                        ],
                        if (isRunning) ...[
                          const SizedBox(width: 8),
                          OhPill(
                            icon: Icons.stop_circle_outlined,
                            label: openHandLocalizedText(
                              context,
                              zh: '中止',
                              zhHant: '中止',
                              en: 'Cancel',
                              fr: 'Annuler',
                              de: 'Abbrechen',
                              ja: '中止',
                            ),
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            onTap: onCancel,
                          ),
                        ],
                        if (isDone &&
                            orchestrator.status !=
                                HarnessOrchestratorStatus.completed) ...[
                          const SizedBox(width: 8),
                          OhPill(
                            icon: Icons.restart_alt_rounded,
                            label:
                                orchestrator.status ==
                                    HarnessOrchestratorStatus.failed
                                ? openHandLocalizedText(
                                    context,
                                    zh: '重试失败阶段',
                                    zhHant: '重試失敗階段',
                                    en: 'Retry Failed Phase',
                                    fr: 'Réessayer la phase échouée',
                                    de: 'Fehlgeschlagene Phase wiederholen',
                                    ja: '失敗したフェーズを再試行',
                                  )
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
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _HeOutputLinesDial(totalLines: totalLines),
        ],
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

// _HeSessionMetadataDialog — full metadata dialog matching _SessionMetadataDialog
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
        HarnessOrchestratorStatus.running => openHandLocalizedText(
          context,
          zh: '运行中',
          zhHant: '執行中',
          en: 'Running',
          fr: 'En cours',
          de: 'Wird ausgeführt',
          ja: '実行中',
        ),
        HarnessOrchestratorStatus.completed => openHandLocalizedText(
          context,
          zh: '已完成',
          zhHant: '已完成',
          en: 'Completed',
          fr: 'Terminé',
          de: 'Abgeschlossen',
          ja: '完了',
        ),
        HarnessOrchestratorStatus.failed => openHandLocalizedText(
          context,
          zh: '失败',
          zhHant: '失敗',
          en: 'Failed',
          fr: 'Échec',
          de: 'Fehlgeschlagen',
          ja: '失敗',
        ),
        HarnessOrchestratorStatus.cancelled => openHandLocalizedText(
          context,
          zh: '已中止',
          zhHant: '已中止',
          en: 'Cancelled',
          fr: 'Annulé',
          de: 'Abgebrochen',
          ja: '中止済み',
        ),
      };

  String _phaseStatusLabel(BuildContext context, HarnessPhaseStatus s) =>
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
        HarnessPhaseStatus.running => openHandLocalizedText(
          context,
          zh: '运行中',
          zhHant: '執行中',
          en: 'Running',
          fr: 'En cours',
          de: 'Wird ausgeführt',
          ja: '実行中',
        ),
        HarnessPhaseStatus.completed => openHandLocalizedText(
          context,
          zh: '已完成',
          zhHant: '已完成',
          en: 'Completed',
          fr: 'Terminé',
          de: 'Abgeschlossen',
          ja: '完了',
        ),
        HarnessPhaseStatus.failed => openHandLocalizedText(
          context,
          zh: '失败',
          zhHant: '失敗',
          en: 'Failed',
          fr: 'Échec',
          de: 'Fehlgeschlagen',
          ja: '失敗',
        ),
        HarnessPhaseStatus.cancelled => openHandLocalizedText(
          context,
          zh: '已中止',
          zhHant: '已中止',
          en: 'Cancelled',
          fr: 'Annulé',
          de: 'Abgebrochen',
          ja: '中止済み',
        ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final logs = orchestrator.phaseLogs;
    // `context.select` so the header only rebuilds when the cached aiModels
    // reference changes, not on every unrelated SettingsController notify.
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
      _HeSummaryTile(
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
      _HeSummaryTile(
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
      _HeSummaryTile(
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
      _HeSummaryTile(
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
      _HeSummaryTile(
        label: openHandLocalizedText(
          context,
          zh: '执行状态',
          zhHant: '執行狀態',
          en: 'Status',
          fr: 'État',
          de: 'Status',
          ja: '状態',
        ),
        value: _statusLabel(context, orchestrator.status),
      ),
      _HeSummaryTile(
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
      maxWidth: 860,
      maxHeight: double.infinity,
      maxHeightFraction: 0.82,
      safeAreaMinimum: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Title row ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '当前会话元数据',
                          zhHant: '目前會話中繼資料',
                          en: 'Current Session Metadata',
                          fr: 'Métadonnées de la session',
                          de: 'Aktuelle Sitzungsmetadaten',
                          ja: '現在のセッションメタデータ',
                        ),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        sessionTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Summary tiles ──
                    Wrap(spacing: 12, runSpacing: 12, children: summaryBlocks),
                    const SizedBox(height: 18),

                    // ── Session overview ──
                    _HeMetadataSection(
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
                        _HeMetadataEntryRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '会话 ID',
                            zhHant: '會話 ID',
                            en: 'Session ID',
                            fr: 'ID de session',
                            de: 'Sitzungs-ID',
                            ja: 'セッション ID',
                          ),
                          value: sessionId ?? '--',
                        ),
                        _HeMetadataEntryRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '模板',
                            zhHant: '範本',
                            en: 'Template',
                            fr: 'Modèle',
                            de: 'Vorlage',
                            ja: 'テンプレート',
                          ),
                          value: 'Harness Engineering',
                        ),
                        _HeMetadataEntryRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '创建时间',
                            zhHant: '建立時間',
                            en: 'Created At',
                            fr: 'Créé le',
                            de: 'Erstellt am',
                            ja: '作成日時',
                          ),
                          value: createdAtLabel ?? '--',
                        ),
                        _HeMetadataEntryRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '更新时间',
                            zhHant: '更新時間',
                            en: 'Updated At',
                            fr: 'Mis à jour le',
                            de: 'Aktualisiert am',
                            ja: '更新日時',
                          ),
                          value: updatedAtLabel ?? '--',
                        ),
                        _HeMetadataEntryRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '执行状态',
                            zhHant: '執行狀態',
                            en: 'Status',
                            fr: 'État',
                            de: 'Status',
                            ja: '状態',
                          ),
                          value: _statusLabel(context, orchestrator.status),
                        ),
                        if (orchestrator.errorMessage?.isNotEmpty == true)
                          _HeMetadataEntryRow(
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
                    const SizedBox(height: 16),

                    // ── Task config ──
                    _HeMetadataSection(
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
                        _HeMetadataEntryRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '任务描述',
                            zhHant: '任務描述',
                            en: 'Task',
                            fr: 'Tâche',
                            de: 'Aufgabe',
                            ja: 'タスク',
                          ),
                          value: config.task.isEmpty ? '-' : config.task,
                        ),
                        _HeMetadataEntryRow(
                          label: openHandLocalizedText(
                            context,
                            zh: '工作目录',
                            zhHant: '工作目錄',
                            en: 'Working Directory',
                            fr: 'Répertoire de travail',
                            de: 'Arbeitsverzeichnis',
                            ja: '作業ディレクトリ',
                          ),
                          value: config.workingDirectory.isEmpty
                              ? '-'
                              : config.workingDirectory,
                        ),
                        _HeMetadataEntryRow(
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
                    const SizedBox(height: 16),

                    // ── Role configs ──
                    _HeMetadataSection(
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
                          _HeMetadataEntryRow(
                            label: entry.$1,
                            value: entry.$2.isUrlMode
                                ? 'URL/API · ${_heDescribeAiModelConfig(context, aiModels, entry.$2.aiModelConfigId, urlModeModelId: entry.$2.urlModeModelId)}'
                                : entry.$2.isConfigured
                                ? '${entry.$2.cliName} · ${_heDescribeHarnessCliModel(context, findHarnessCliByName(entry.$2.cliName), entry.$2.modelId)}'
                                : _heHarnessNotConfiguredText(context),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Phase status ──
                    _HeMetadataSection(
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
                          _HeMetadataEntryRow(
                            label: _heHarnessPhaseLabel(context, log.phase),
                            value: () {
                              final parts = <String>[
                                _phaseStatusLabel(context, log.status),
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
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ── Close button ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  onPressed: () => Navigator.of(context).pop(),
                  label: openHandLocalizedText(
                    context,
                    zh: '关闭',
                    zhHant: '關閉',
                    en: 'Close',
                    fr: 'Fermer',
                    de: 'Schließen',
                    ja: '閉じる',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// HE Metadata dialog sub-widgets (matching _SessionMetadataDialog style)
class _HeSummaryTile extends StatelessWidget {
  const _HeSummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 188,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeMetadataSection extends StatelessWidget {
  const _HeMetadataSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _HeMetadataEntryRow extends StatelessWidget {
  const _HeMetadataEntryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

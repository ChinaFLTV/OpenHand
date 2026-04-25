part of 'hardness_session_dashboard.dart';

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
  });

  final HardnessSessionConfig config;
  final HardnessOrchestrator orchestrator;
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

  String get _effectiveTitle => (sessionTitle?.trim().isNotEmpty == true)
      ? sessionTitle!
      : (isZh ? 'Hardness Engineering 会话' : 'Hardness Engineering Session');

  /// Returns a label like "元数据采集 1/3" describing current execution position.
  String _phaseProgressLabel() {
    final logs = orchestrator.phaseLogs;
    final total = logs.length;
    final awaitingApproval = orchestrator.awaitingApprovalPhase;
    if (awaitingApproval != null) {
      final idx = logs.indexWhere((l) => l.phase == awaitingApproval);
      final pos = idx >= 0 ? idx + 1 : total;
      final name = isZh
          ? awaitingApproval.displayNameZh
          : awaitingApproval.displayNameEn;
      return isZh
          ? '$name $pos/$total · 待批准'
          : '$name $pos/$total · Awaiting Approval';
    }
    final current = orchestrator.currentPhase;
    if (isRunning && current != null) {
      final idx = logs.indexWhere((l) => l.phase == current);
      final pos = idx >= 0 ? idx + 1 : total;
      final name = isZh ? current.displayNameZh : current.displayNameEn;
      return '$name $pos/$total';
    }
    final completed = logs
        .where((l) => l.status == HardnessPhaseStatus.completed)
        .length;
    final failed = logs
        .where((l) => l.status == HardnessPhaseStatus.failed)
        .length;
    if (total == 0) return isZh ? '待开始' : 'Not started';
    if (failed > 0) {
      return isZh ? '阶段失败 $failed/$total' : '$failed/$total failed';
    }
    if (completed == total) return isZh ? '全部完成 $total' : '$total done';
    return isZh ? '完成 $completed/$total' : '$completed/$total done';
  }

  IconData _phaseProgressIcon() {
    if (orchestrator.awaitingApprovalPhase != null) {
      return Icons.pause_circle_filled_rounded;
    }
    if (isRunning) return Icons.sync_rounded;
    final logs = orchestrator.phaseLogs;
    if (logs.any((l) => l.status == HardnessPhaseStatus.failed)) {
      return Icons.error_outline_rounded;
    }
    if (orchestrator.status == HardnessOrchestratorStatus.completed) {
      return Icons.check_circle_outline_rounded;
    }
    if (orchestrator.status == HardnessOrchestratorStatus.cancelled) {
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
    if (logs.any((l) => l.status == HardnessPhaseStatus.failed)) {
      return _heFailedTone;
    }
    if (orchestrator.status == HardnessOrchestratorStatus.completed) {
      return _heCompletedTone;
    }
    if (orchestrator.status == HardnessOrchestratorStatus.cancelled) {
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
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: <Widget>[
                          ...previousChildren,
                          ...?(currentChild == null
                              ? null
                              : <Widget>[currentChild]),
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      final curved = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      );
                      final slide = Tween<Offset>(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(curved);
                      final scale = Tween<double>(
                        begin: 0.96,
                        end: 1,
                      ).animate(curved);
                      return ClipRect(
                        child: FadeTransition(
                          opacity: curved,
                          child: SlideTransition(
                            position: slide,
                            child: ScaleTransition(scale: scale, child: child),
                          ),
                        ),
                      );
                    },
                    child: Text(
                      _effectiveTitle,
                      key: ValueKey<String>(_effectiveTitle),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
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
                        _HePill(
                          icon: _phaseProgressIcon(),
                          label: _phaseProgressLabel(),
                          foregroundColor: _phaseProgressColor(colorScheme),
                        ),
                        if (reviewRetries > 0) ...[
                          const SizedBox(width: 8),
                          // ── Review retry counter ──
                          _HePill(
                            icon: Icons.replay_rounded,
                            label: isZh
                                ? '重试 $reviewRetries/3'
                                : 'Retry $reviewRetries/3',
                            foregroundColor: const Color(0xFFF57F17), // amber
                          ),
                        ],
                        const SizedBox(width: 8),
                        const _HePill(
                          icon: Icons.layers_rounded,
                          label:
                              'Hardness Engineering · v$kHardnessOrchestratorDisplayVersion',
                        ),
                        const SizedBox(width: 8),
                        _HePill(
                          icon: Icons.data_object_rounded,
                          label: isZh ? '会话元数据' : 'Session Metadata',
                          onTap: () => _showSessionMetadata(context),
                        ),
                        const SizedBox(width: 8),
                        _HePill(
                          icon: Icons.folder_special_rounded,
                          label: isZh ? '资产文件' : 'Steering Assets',
                          onTap: () => _showSteeringAssets(context),
                        ),
                        if (updatedAtLabel?.isNotEmpty == true) ...[
                          const SizedBox(width: 8),
                          _HePill(
                            icon: Icons.update_rounded,
                            label: updatedAtLabel!,
                          ),
                        ],
                        if (isRunning) ...[
                          const SizedBox(width: 8),
                          _HePill(
                            icon: Icons.stop_circle_outlined,
                            label: isZh ? '中止' : 'Cancel',
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            onTap: onCancel,
                          ),
                        ],
                        if (isDone &&
                            orchestrator.status !=
                                HardnessOrchestratorStatus.completed) ...[
                          const SizedBox(width: 8),
                          _HePill(
                            icon: Icons.restart_alt_rounded,
                            label:
                                orchestrator.status ==
                                    HardnessOrchestratorStatus.failed
                                ? (isZh ? '重试失败阶段' : 'Retry Failed Phase')
                                : (isZh ? '重新开始' : 'Restart'),
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
        isZh: isZh,
        sessionTitle: _effectiveTitle,
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
          _HeSteeringAssetsDialog(steeringRoot: steeringRoot, isZh: isZh),
    );
  }
}

// =============================================================================
// _HeSessionMetadataDialog — full metadata dialog matching _SessionMetadataDialog
// =============================================================================

class _HeSessionMetadataDialog extends StatelessWidget {
  const _HeSessionMetadataDialog({
    required this.config,
    required this.orchestrator,
    required this.isZh,
    required this.sessionTitle,
    this.sessionId,
    this.createdAtLabel,
    this.updatedAtLabel,
  });

  final HardnessSessionConfig config;
  final HardnessOrchestrator orchestrator;
  final bool isZh;
  final String sessionTitle;
  final String? sessionId;
  final String? createdAtLabel;
  final String? updatedAtLabel;

  String _statusLabel(HardnessOrchestratorStatus s) => switch (s) {
    HardnessOrchestratorStatus.idle => isZh ? '准备中' : 'Idle',
    HardnessOrchestratorStatus.running => isZh ? '运行中' : 'Running',
    HardnessOrchestratorStatus.completed => isZh ? '已完成' : 'Completed',
    HardnessOrchestratorStatus.failed => isZh ? '失败' : 'Failed',
    HardnessOrchestratorStatus.cancelled => isZh ? '已中止' : 'Cancelled',
  };

  String _phaseStatusLabel(HardnessPhaseStatus s) => switch (s) {
    HardnessPhaseStatus.pending => isZh ? '等待中' : 'Pending',
    HardnessPhaseStatus.paused => isZh ? '暂停中' : 'Paused',
    HardnessPhaseStatus.running => isZh ? '运行中' : 'Running',
    HardnessPhaseStatus.completed => isZh ? '已完成' : 'Completed',
    HardnessPhaseStatus.failed => isZh ? '失败' : 'Failed',
    HardnessPhaseStatus.cancelled => isZh ? '已中止' : 'Cancelled',
    HardnessPhaseStatus.skipped => isZh ? '已跳过' : 'Skipped',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final logs = orchestrator.phaseLogs;
    final settingsController = Provider.of<SettingsController?>(context);
    final aiModels = settingsController?.aiModels ?? const <AiModelConfig>[];

    final totalPhases = HardnessPhase.values.length;
    final completedPhases = logs
        .where((l) => l.status == HardnessPhaseStatus.completed)
        .length;
    final failedPhases = logs
        .where((l) => l.status == HardnessPhaseStatus.failed)
        .length;
    final totalLogLines = logs.fold<int>(0, (sum, l) => sum + l.lines.length);

    final summaryBlocks = <Widget>[
      _HeSummaryTile(
        label: isZh ? '阶段总数' : 'Total Phases',
        value: '$totalPhases',
      ),
      _HeSummaryTile(
        label: isZh ? '已完成阶段' : 'Completed',
        value: '$completedPhases',
      ),
      _HeSummaryTile(label: isZh ? '失败阶段' : 'Failed', value: '$failedPhases'),
      _HeSummaryTile(
        label: isZh ? '日志总行数' : 'Total Log Lines',
        value: '$totalLogLines',
      ),
      _HeSummaryTile(
        label: isZh ? '执行状态' : 'Status',
        value: _statusLabel(orchestrator.status),
      ),
      _HeSummaryTile(
        label: isZh ? '当前阶段' : 'Current Phase',
        value: orchestrator.currentPhase != null
            ? (isZh
                  ? orchestrator.currentPhase!.displayNameZh
                  : orchestrator.currentPhase!.displayNameEn)
            : '--',
      ),
    ];

    final roleConfigs = <(String, HardnessRoleConfig)>[
      (isZh ? '探档者 (Profiler)' : 'Profiler', config.profilerConfig),
      (isZh ? '调查者 (Reader)' : 'Reader', config.readerConfig),
      (isZh ? '规划者 (Planner)' : 'Planner', config.plannerConfig),
      (isZh ? '实施者 (Implementer)' : 'Implementer', config.implementerConfig),
      (isZh ? '验收者 (Reviewer)' : 'Reviewer', config.reviewerConfig),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                          isZh ? '当前会话元数据' : 'Current Session Metadata',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sessionTitle,
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

              // ── Summary tiles ──
              Wrap(spacing: 12, runSpacing: 12, children: summaryBlocks),
              const SizedBox(height: 18),

              // ── Scrollable sections ──
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Session overview ──
                      _HeMetadataSection(
                        title: isZh ? '会话概览' : 'Session Overview',
                        children: [
                          _HeMetadataEntryRow(
                            label: isZh ? '会话 ID' : 'Session ID',
                            value: sessionId ?? '--',
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '模板' : 'Template',
                            value: 'Hardness Engineering',
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '创建时间' : 'Created At',
                            value: createdAtLabel ?? '--',
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '更新时间' : 'Updated At',
                            value: updatedAtLabel ?? '--',
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '执行状态' : 'Status',
                            value: _statusLabel(orchestrator.status),
                          ),
                          if (orchestrator.errorMessage?.isNotEmpty == true)
                            _HeMetadataEntryRow(
                              label: isZh ? '错误信息' : 'Error',
                              value: orchestrator.errorMessage!,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Task config ──
                      _HeMetadataSection(
                        title: isZh ? '任务配置' : 'Task Config',
                        children: [
                          _HeMetadataEntryRow(
                            label: isZh ? '任务描述' : 'Task',
                            value: config.task.isEmpty ? '-' : config.task,
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '工作目录' : 'Working Directory',
                            value: config.workingDirectory.isEmpty
                                ? '-'
                                : config.workingDirectory,
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '持久化目录' : 'Persistence Directory',
                            value: config.persistenceDirectory.isEmpty
                                ? '-'
                                : config.persistenceDirectory,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Role configs ──
                      _HeMetadataSection(
                        title: isZh ? '角色配置' : 'Role Configs',
                        children: [
                          for (final entry in roleConfigs)
                            _HeMetadataEntryRow(
                              label: entry.$1,
                              value: entry.$2.isUrlMode
                                  ? 'URL/API · ${_heDescribeAiModelConfig(aiModels, entry.$2.aiModelConfigId, isZh: isZh, urlModeModelId: entry.$2.urlModeModelId)}'
                                  : entry.$2.isConfigured
                                  ? '${entry.$2.cliName} · ${describeHardnessCliModel(findHardnessCliByName(entry.$2.cliName), entry.$2.modelId, isZh: isZh)}'
                                  : (isZh ? '未配置' : 'Not configured'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Phase status ──
                      _HeMetadataSection(
                        title: isZh ? '阶段状态' : 'Phase Status',
                        children: [
                          for (final log in logs)
                            _HeMetadataEntryRow(
                              label: isZh
                                  ? log.phase.displayNameZh
                                  : log.phase.displayNameEn,
                              value: () {
                                final parts = <String>[
                                  _phaseStatusLabel(log.status),
                                ];
                                if (log.exitCode != null) {
                                  parts.add(
                                    '${isZh ? '退出码' : 'Exit code'}: ${log.exitCode}',
                                  );
                                }
                                parts.add(
                                  '${isZh ? '日志行数' : 'Log lines'}: ${log.lines.length}',
                                );
                                if (log.savedLogPath?.isNotEmpty == true) {
                                  parts.add(
                                    '${isZh ? '日志文件' : 'Log file'}: ${log.savedLogPath}',
                                  );
                                }
                                return parts.join(' · ');
                              }(),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ── Close button ──
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(),
                    label: isZh ? '关闭' : 'Close',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// HE Metadata dialog sub-widgets (matching _SessionMetadataDialog style)
// =============================================================================

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

// =============================================================================
// Q弹 entrance animation wrapper for phase cards.
// Plays a single fade + vertical-slide + subtle scale pop when the card first
// appears in the list. Uses easeOutBack so the card slightly overshoots and
// settles back — giving that characteristic "Q弹丝滑" spring feel.
// =============================================================================


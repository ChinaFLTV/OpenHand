part of 'settings_view.dart';

class _MachineTerminalBuiltinToolSummaryCard extends StatelessWidget {
  const _MachineTerminalBuiltinToolSummaryCard({
    required this.configs,
    required this.onEnableAll,
    required this.onDisableAll,
  });

  final List<AiBuiltinToolConfig> configs;
  final VoidCallback? onEnableAll;
  final VoidCallback? onDisableAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabledCount = configs.where((config) => config.enabled).length;
    final mutationCount = configs
        .where((config) => config.kind.isMachineTerminalMutationTool)
        .length;
    final enabledMutationCount = configs
        .where(
          (config) =>
              config.enabled && config.kind.isMachineTerminalMutationTool,
        )
        .length;
    final readCount = configs.length - mutationCount;
    final enabledReadCount = enabledCount - enabledMutationCount;
    final allEnabled = configs.isNotEmpty && enabledCount == configs.length;
    final allDisabled = configs.isNotEmpty && enabledCount == 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.tertiary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(kOpenHandRadius12),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.terminal_rounded, color: cs.tertiary),
            ),
            kOpenHandHGap12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '机器终端工具',
                      en: 'Machine terminal tools',
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  kOpenHandGap4,
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '全局启用表示允许参与目录解析；运行时仅机器专家线程模板会看到这些终端读写与控制工具。',
                      en: 'Global enablement allows catalog resolution. At runtime, only Machine Expert sessions can see these terminal read/write/control tools.',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  kOpenHandGap10,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: allEnabled ? null : onEnableAll,
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: Text(
                          openHandLocalizedText(
                            context,
                            zh: '启用终端工具',
                            en: 'Enable terminal tools',
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: allDisabled ? null : onDisableAll,
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        label: Text(
                          openHandLocalizedText(
                            context,
                            zh: '禁用终端工具',
                            en: 'Disable terminal tools',
                          ),
                        ),
                      ),
                    ],
                  ),
                  kOpenHandGap10,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AgentToolMetricChip(
                        icon: Icons.toggle_on_rounded,
                        label: openHandLocalizedText(
                          context,
                          zh: '已启用 $enabledCount/${configs.length}',
                          en: 'Enabled $enabledCount/${configs.length}',
                        ),
                      ),
                      _AgentToolMetricChip(
                        icon: Icons.visibility_outlined,
                        label: openHandLocalizedText(
                          context,
                          zh: '读取 $enabledReadCount/$readCount',
                          en: 'Read $enabledReadCount/$readCount',
                        ),
                      ),
                      _AgentToolMetricChip(
                        icon: Icons.edit_note_rounded,
                        label: openHandLocalizedText(
                          context,
                          zh: '变更 $enabledMutationCount/$mutationCount',
                          en: 'Mutating $enabledMutationCount/$mutationCount',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentBuiltinToolSummaryCard extends StatelessWidget {
  const _AgentBuiltinToolSummaryCard({
    required this.configs,
    required this.onEnableAll,
    required this.onDisableAll,
  });

  final List<AiBuiltinToolConfig> configs;
  final VoidCallback? onEnableAll;
  final VoidCallback? onDisableAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabledCount = configs.where((config) => config.enabled).length;
    final mutationCount = configs
        .where((config) => config.kind.isAgentMutationTool)
        .length;
    final enabledMutationCount = configs
        .where((config) => config.enabled && config.kind.isAgentMutationTool)
        .length;
    final readOnlyCount = configs.length - mutationCount;
    final enabledReadOnlyCount = enabledCount - enabledMutationCount;
    final allEnabled = configs.isNotEmpty && enabledCount == configs.length;
    final allDisabled = configs.isNotEmpty && enabledCount == 0;
    final groupSummaries = AiAgentBuiltinToolGroup.values
        .map((group) {
          final groupConfigs = configs
              .where((config) => config.kind.agentToolGroup == group)
              .toList(growable: false);
          return _AgentToolGroupSummary(
            group: group,
            totalCount: groupConfigs.length,
            enabledCount: groupConfigs.where((config) => config.enabled).length,
            mutationCount: groupConfigs
                .where((config) => config.kind.isAgentMutationTool)
                .length,
          );
        })
        .where((summary) => summary.totalCount > 0)
        .toList(growable: false);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(kOpenHandRadius12),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.account_tree_rounded, color: cs.primary),
            ),
            kOpenHandHGap12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '智能体协同工具',
                      en: 'Agent coordination tools',
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  kOpenHandGap4,
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '全局启用只表示工具允许参与目录解析；实际进入线程会话工具目录，还需要至少一个已启用智能体在配置弹窗中绑定对应工具。',
                      en: 'Global enablement only allows catalog resolution. A tool appears in chat sessions only when at least one enabled agent binds it in the agent configuration dialog.',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  kOpenHandGap10,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: allEnabled ? null : onEnableAll,
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: Text(
                          openHandLocalizedText(
                            context,
                            zh: '启用智能体工具',
                            en: 'Enable agent tools',
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: allDisabled ? null : onDisableAll,
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        label: Text(
                          openHandLocalizedText(
                            context,
                            zh: '禁用智能体工具',
                            en: 'Disable agent tools',
                          ),
                        ),
                      ),
                    ],
                  ),
                  kOpenHandGap10,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AgentToolMetricChip(
                        icon: Icons.toggle_on_rounded,
                        label: openHandLocalizedText(
                          context,
                          zh: '已启用 $enabledCount/${configs.length}',
                          en: 'Enabled $enabledCount/${configs.length}',
                        ),
                      ),
                      _AgentToolMetricChip(
                        icon: Icons.visibility_outlined,
                        label: openHandLocalizedText(
                          context,
                          zh: '只读 $enabledReadOnlyCount/$readOnlyCount',
                          en: 'Read-only $enabledReadOnlyCount/$readOnlyCount',
                        ),
                      ),
                      _AgentToolMetricChip(
                        icon: Icons.edit_note_rounded,
                        label: openHandLocalizedText(
                          context,
                          zh: '变更 $enabledMutationCount/$mutationCount',
                          en: 'Mutating $enabledMutationCount/$mutationCount',
                        ),
                      ),
                    ],
                  ),
                  if (groupSummaries.isNotEmpty) ...[
                    kOpenHandGap12,
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final summary in groupSummaries)
                          _AgentToolGroupChip(summary: summary),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentToolGroupSummary {
  const _AgentToolGroupSummary({
    required this.group,
    required this.totalCount,
    required this.enabledCount,
    required this.mutationCount,
  });

  final AiAgentBuiltinToolGroup group;
  final int totalCount;
  final int enabledCount;
  final int mutationCount;
}

class _AgentToolGroupChip extends StatelessWidget {
  const _AgentToolGroupChip({required this.summary});

  final _AgentToolGroupSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final allEnabled = summary.enabledCount == summary.totalCount;
    final statusColor = allEnabled ? cs.primary : cs.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 178, maxWidth: 236),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(kOpenHandRadius12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(
                agentBuiltinToolGroupIcon(summary.group),
                size: 18,
                color: statusColor,
              ),
              kOpenHandHGap8,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      agentBuiltinToolGroupLabel(context, summary.group),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    kOpenHandGap2,
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '启用 ${summary.enabledCount}/${summary.totalCount} · 变更 ${summary.mutationCount}',
                        en: 'Enabled ${summary.enabledCount}/${summary.totalCount} · Mutating ${summary.mutationCount}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentToolMetricChip extends StatelessWidget {
  const _AgentToolMetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.72),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: cs.primary),
            kOpenHandHGap6,
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Builtin Tool Tile (list item in the tool catalog overview)

class _BuiltinToolTile extends StatelessWidget {
  const _BuiltinToolTile({
    required this.config,
    required this.isFirst,
    required this.isLast,
    required this.onToggle,
    required this.onEdit,
    this.onMoveUp,
    this.onMoveDown,
    this.onDelete,
  });

  final AiBuiltinToolConfig config;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDelete;

  IconData _toolIcon(AiBuiltinToolKind kind) {
    return switch (kind) {
      AiBuiltinToolKind.task => Icons.task_alt_rounded,
      AiBuiltinToolKind.bash => Icons.terminal_rounded,
      AiBuiltinToolKind.bashBackground => Icons.dvr_rounded,
      AiBuiltinToolKind.taskOutput => Icons.output_rounded,
      AiBuiltinToolKind.taskStop => Icons.stop_circle_outlined,
      AiBuiltinToolKind.glob => Icons.folder_copy_outlined,
      AiBuiltinToolKind.grep => Icons.search_rounded,
      AiBuiltinToolKind.ls => Icons.list_alt_rounded,
      AiBuiltinToolKind.exitPlanMode => Icons.exit_to_app_rounded,
      AiBuiltinToolKind.read => Icons.description_outlined,
      AiBuiltinToolKind.edit => Icons.edit_note_rounded,
      AiBuiltinToolKind.multiEdit => Icons.edit_attributes_rounded,
      AiBuiltinToolKind.applyFileDiffs => Icons.difference_rounded,
      AiBuiltinToolKind.write => Icons.save_outlined,
      AiBuiltinToolKind.notebookEdit => Icons.book_outlined,
      AiBuiltinToolKind.webFetch => Icons.language_rounded,
      AiBuiltinToolKind.todoWrite => Icons.checklist_rounded,
      AiBuiltinToolKind.webSearch => Icons.travel_explore_rounded,
      AiBuiltinToolKind.lsp => Icons.code_rounded,
      AiBuiltinToolKind.codebaseSearch => Icons.manage_search_rounded,
      AiBuiltinToolKind.git => Icons.merge_rounded,
      AiBuiltinToolKind.deleteFile => Icons.delete_outline_rounded,
      AiBuiltinToolKind.readLints => Icons.bug_report_outlined,
      AiBuiltinToolKind.askUserChoice => Icons.quiz_outlined,
      AiBuiltinToolKind.skillManager => Icons.auto_stories_rounded,
      AiBuiltinToolKind.toolSearch => Icons.search_rounded,
      AiBuiltinToolKind.dingTalkToolSearch => Icons.extension_rounded,
      AiBuiltinToolKind.dingtalkDws => Icons.extension_rounded,
      AiBuiltinToolKind.dingtalkImageGeneration => Icons.image_rounded,
      AiBuiltinToolKind.dingtalkVideoGeneration => Icons.movie_rounded,
      AiBuiltinToolKind.dingtalkAudioGeneration => Icons.audiotrack_rounded,
      AiBuiltinToolKind.memory => Icons.psychology_rounded,
      AiBuiltinToolKind.knowledgeSearch => Icons.library_books_outlined,
      AiBuiltinToolKind.knowledgeRead => Icons.menu_book_outlined,
      AiBuiltinToolKind.agentList => Icons.badge_outlined,
      AiBuiltinToolKind.agentDetail => Icons.assignment_ind_outlined,
      AiBuiltinToolKind.agentActivityLog => Icons.history_rounded,
      AiBuiltinToolKind.agentAuditReport => Icons.analytics_outlined,
      AiBuiltinToolKind.agentAuditRecord => Icons.manage_search_outlined,
      AiBuiltinToolKind.agentApprovalRequest => Icons.approval_outlined,
      AiBuiltinToolKind.agentKpiUpsert => Icons.flag_outlined,
      AiBuiltinToolKind.agentResourceUpdate => Icons.speed_outlined,
      AiBuiltinToolKind.agentClusterConfigure => Icons.account_tree_outlined,
      AiBuiltinToolKind.agentClusterStatus => Icons.account_tree_rounded,
      AiBuiltinToolKind.agentTaskList => Icons.playlist_add_check_rounded,
      AiBuiltinToolKind.agentTaskPublish => Icons.send_to_mobile_rounded,
      AiBuiltinToolKind.agentTaskTrack => Icons.track_changes_rounded,
      AiBuiltinToolKind.agentTaskProgress => Icons.trending_up_rounded,
      AiBuiltinToolKind.agentTaskCancel => Icons.cancel_outlined,
      AiBuiltinToolKind.agentTaskPause => Icons.pause_circle_outline_rounded,
      AiBuiltinToolKind.agentTaskTerminate => Icons.gpp_bad_outlined,
      AiBuiltinToolKind.agentTaskResume => Icons.play_circle_outline_rounded,
      AiBuiltinToolKind.agentTaskComplete => Icons.task_alt_outlined,
      AiBuiltinToolKind.agentTaskResult => Icons.fact_check_outlined,
      AiBuiltinToolKind.machineTerminalRead => Icons.terminal_rounded,
      AiBuiltinToolKind.machineTerminalWrite =>
        Icons.keyboard_command_key_rounded,
      AiBuiltinToolKind.machineTerminalExec =>
        Icons.play_circle_outline_rounded,
      AiBuiltinToolKind.machineTerminalControl => Icons.tune_rounded,
    };
  }

  String _loadStrategyLabel(
    AppLocalizations l10n,
    AiBuiltinToolLoadStrategy strategy,
  ) {
    return switch (strategy) {
      AiBuiltinToolLoadStrategy.eager => l10n.builtinToolLoadStrategyEagerShort,
      AiBuiltinToolLoadStrategy.lazy => l10n.builtinToolLoadStrategyLazy,
      AiBuiltinToolLoadStrategy.deferred =>
        l10n.builtinToolLoadStrategyDeferred,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final customDisplayName = config.displayName?.trim();
    final customSummary = config.summary?.trim();
    final displayName = customDisplayName?.isNotEmpty == true
        ? customDisplayName!
        : config.kind.isAgentCoordinationTool
        ? agentBuiltinToolLabel(context, config.kind)
        : config.kind.name;
    final summaryText = customSummary?.isNotEmpty == true
        ? customSummary!
        : config.kind.isAgentCoordinationTool
        ? '${agentBuiltinToolCanonicalName(config.kind)} · ${agentBuiltinToolSummary(context, config.kind)}'
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: config.enabled
            ? colorScheme.surfaceContainerLow
            : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(
          color: config.enabled
              ? colorScheme.outlineVariant.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              _toolIcon(config.kind),
              size: 28,
              color: config.enabled
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            kOpenHandHGap14,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: config.enabled
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.6,
                                  ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (config.isCustom) ...[
                        kOpenHandHGap8,
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(
                              kOpenHandRadius4,
                            ),
                          ),
                          child: Text(
                            l10n.builtinToolCustomBadge,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.tertiary,
                            ),
                          ),
                        ),
                      ],
                      kOpenHandHGap8,
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(kOpenHandRadius4),
                        ),
                        child: Text(
                          _loadStrategyLabel(l10n, config.loadStrategy),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      if (config.forceLoad) ...[
                        kOpenHandHGap6,
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.62,
                            ),
                            borderRadius: BorderRadius.circular(
                              kOpenHandRadius4,
                            ),
                          ),
                          child: Text(
                            l10n.builtinToolForceBadge,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                      kOpenHandHGap6,
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(kOpenHandRadius4),
                        ),
                        child: Text(
                          'P${config.priority}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (summaryText != null) ...[
                    kOpenHandGap4,
                    Text(
                      summaryText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (config.tags.isNotEmpty) ...[
                    kOpenHandGap4,
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: config.tags
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(
                                  alpha: 0.4,
                                ),
                                borderRadius: BorderRadius.circular(
                                  kOpenHandRadius4,
                                ),
                              ),
                              child: Text(
                                tag,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
            ),
            kOpenHandHGap8,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onMoveUp != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    tooltip: l10n.builtinToolMoveUp,
                    onPressed: onMoveUp,
                    visualDensity: VisualDensity.compact,
                  ),
                if (onMoveUp != null) kOpenHandHGap8,
                if (onMoveDown != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    tooltip: l10n.builtinToolMoveDown,
                    onPressed: onMoveDown,
                    visualDensity: VisualDensity.compact,
                  ),
                if (onMoveDown != null) kOpenHandHGap8,
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: l10n.commonEdit,
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                ),
                if (onDelete != null) ...[
                  kOpenHandHGap8,
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: colorScheme.error,
                    ),
                    tooltip: l10n.commonDelete,
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                kOpenHandHGap8,
                Switch(value: config.enabled, onChanged: onToggle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BuiltinToolEditorDialog extends StatefulWidget {
  const _BuiltinToolEditorDialog({
    required this.initial,
    this.defaultName,
    this.defaultDescription,
    this.defaultParameters,
    this.availableModels = const <AiModelConfig>[],
    this.recentModelSelections = const <RecentModelSelection>[],
  });

  final AiBuiltinToolConfig initial;

  final String? defaultName;

  final String? defaultDescription;

  final Map<String, Object?>? defaultParameters;

  final List<AiModelConfig> availableModels;

  final List<RecentModelSelection> recentModelSelections;

  @override
  State<_BuiltinToolEditorDialog> createState() =>
      _BuiltinToolEditorDialogState();
}

class _BuiltinToolEditorDialogState extends State<_BuiltinToolEditorDialog> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _summaryController;
  late final TextEditingController _promptOverrideController;
  late final TextEditingController _schemaOverrideController;
  late final TextEditingController _priorityController;
  late final TextEditingController _maxOutputCharsController;
  late final TextEditingController _timeoutSecondsController;
  late final TextEditingController _maxRetriesController;
  late final TextEditingController _retryBackoffMsController;
  late final TextEditingController _tagsController;

  late bool _enabled;
  late AiBuiltinToolLoadStrategy _loadStrategy;
  late bool _forceLoad;
  late bool? _requireConfirmation;
  late bool _retryOnFailure;
  AiWebSearchSettings? _webSearchSettings;
  AiWebFetchSettings? _webFetchSettings;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _displayNameController = TextEditingController(
      text: c.displayName ?? widget.defaultName ?? '',
    );
    _summaryController = TextEditingController(
      text: c.summary ?? widget.defaultDescription ?? '',
    );
    _promptOverrideController = TextEditingController(
      text: c.promptOverride ?? '',
    );
    final schemaMap = c.schemaOverride ?? widget.defaultParameters;
    _schemaOverrideController = TextEditingController(
      text: schemaMap != null ? prettyPrintJson(schemaMap) : '',
    );
    _priorityController = TextEditingController(text: '${c.priority}');
    _maxOutputCharsController = TextEditingController(
      text: c.maxOutputChars != null ? '${c.maxOutputChars}' : '',
    );
    _timeoutSecondsController = TextEditingController(
      text: c.timeoutSeconds != null ? '${c.timeoutSeconds}' : '',
    );
    _maxRetriesController = TextEditingController(text: '${c.maxRetries}');
    _retryBackoffMsController = TextEditingController(
      text: '${c.retryBackoffMs}',
    );
    _tagsController = TextEditingController(text: c.tags.join(', '));
    _enabled = c.enabled;
    _loadStrategy = c.loadStrategy;
    _forceLoad = c.forceLoad;
    _requireConfirmation = c.requireConfirmation;
    _retryOnFailure = c.retryOnFailure;
    if (c.kind == AiBuiltinToolKind.webSearch) {
      _webSearchSettings =
          c.webSearchSettings ?? AiWebSearchSettings.defaults();
    }
    if (c.kind == AiBuiltinToolKind.webFetch) {
      _webFetchSettings = c.webFetchSettings ?? AiWebFetchSettings.defaults();
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _summaryController.dispose();
    _promptOverrideController.dispose();
    _schemaOverrideController.dispose();
    _priorityController.dispose();
    _maxOutputCharsController.dispose();
    _timeoutSecondsController.dispose();
    _maxRetriesController.dispose();
    _retryBackoffMsController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  AiBuiltinToolConfig _buildConfig() {
    final displayName = _displayNameController.text.trim();
    final summary = _summaryController.text.trim();
    final promptOverride = _promptOverrideController.text.trim();
    final schemaText = _schemaOverrideController.text.trim();
    Map<String, Object?>? schemaOverride;
    if (schemaText.isNotEmpty) {
      schemaOverride = optionalStringKeyedMapFromJsonText(schemaText);
    }
    final priority = clampedIntFromText(
      _priorityController.text,
      fallback: 100,
      min: 0,
      max: 9999,
    );
    final maxOutputChars = optionalIntFromText(_maxOutputCharsController.text);
    final timeoutSeconds = _timeoutSecondsController.text.trim().isEmpty
        ? null
        : clampedIntFromText(
            _timeoutSecondsController.text,
            fallback: AiBuiltinToolConfig.defaultTimeoutSeconds,
            min: AiBuiltinToolConfig.minTimeoutSeconds,
            max: AiBuiltinToolConfig.maxTimeoutSeconds,
          );
    final maxRetries = clampedIntFromText(
      _maxRetriesController.text,
      fallback: 0,
      min: 0,
      max: AiBuiltinToolConfig.maxRetriesUpperBound,
    );
    final retryBackoffMs = clampedIntFromText(
      _retryBackoffMsController.text,
      fallback: AiBuiltinToolConfig.defaultRetryBackoffMs,
      min: 0,
      max: AiBuiltinToolConfig.maxRetryBackoffMs,
    );
    final rawTags = splitTrimmedNonEmpty(_tagsController.text);

    return widget.initial.copyWith(
      enabled: _enabled,
      displayName: displayName.isEmpty ? null : displayName,
      summary: summary.isEmpty ? null : summary,
      promptOverride: promptOverride.isEmpty ? null : promptOverride,
      schemaOverride: schemaOverride,
      priority: priority,
      loadStrategy: _loadStrategy,
      forceLoad: _forceLoad,
      tags: rawTags,
      maxOutputChars: maxOutputChars,
      timeoutSeconds: timeoutSeconds,
      requireConfirmation: _requireConfirmation,
      retryOnFailure: _retryOnFailure,
      maxRetries: maxRetries,
      retryBackoffMs: retryBackoffMs,
      webSearchSettings: _webSearchSettings,
      webFetchSettings: _webFetchSettings,
      clearDisplayName: displayName.isEmpty,
      clearSummary: summary.isEmpty,
      clearPromptOverride: promptOverride.isEmpty,
      clearSchemaOverride: schemaText.isEmpty,
      clearMaxOutputChars: _maxOutputCharsController.text.trim().isEmpty,
      clearTimeoutSeconds: _timeoutSecondsController.text.trim().isEmpty,
      clearRequireConfirmation: _requireConfirmation == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: !_isSaving,
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: kOpenHandDialogWidthStandard,
        maxHeight: kOpenHandDialogHeightTall,
        safeAreaMinimum: kOpenHandDialogDefaultInsetPadding,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.build_circle_outlined, color: colorScheme.primary),
                  kOpenHandHGap12,
                  Expanded(
                    child: Text(
                      l10n.builtinToolEditorTitle(widget.initial.kind.name),
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              kOpenHandGap16,

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.builtinToolEnableTitle),
                        subtitle: Text(
                          l10n.builtinToolEnableBody,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        value: _enabled,
                        onChanged: (value) => setState(() => _enabled = value),
                      ),
                      kOpenHandGap14,

                      TextField(
                        controller: _displayNameController,
                        decoration: InputDecoration(
                          labelText: l10n.builtinToolDisplayNameLabel,
                          hintText: widget.initial.kind.name,
                          helperText: l10n.builtinToolDisplayNameHelper,
                        ),
                      ),
                      kOpenHandGap14,

                      TextField(
                        controller: _summaryController,
                        decoration: InputDecoration(
                          labelText: l10n.builtinToolSummaryLabel,
                          helperText: l10n.builtinToolSummaryHelper,
                        ),
                        maxLines: 2,
                      ),
                      kOpenHandGap14,

                      TextField(
                        controller: _promptOverrideController,
                        decoration: InputDecoration(
                          labelText: l10n.builtinToolPromptOverrideLabel,
                          helperText: l10n.builtinToolPromptOverrideHelper,
                        ),
                        maxLines: 4,
                        minLines: 2,
                      ),
                      kOpenHandGap14,

                      TextField(
                        controller: _schemaOverrideController,
                        decoration: InputDecoration(
                          labelText: l10n.builtinToolSchemaOverrideLabel,
                          helperText: l10n.builtinToolSchemaOverrideHelper,
                        ),
                        maxLines: 6,
                        minLines: 3,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: kOpenHandMonospaceFontFamily,
                        ),
                      ),
                      kOpenHandGap14,

                      // Priority & Load Strategy row
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _priorityController,
                              keyboardType: TextInputType.number,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: l10n.builtinToolPriorityLabel,
                                helperText: l10n.builtinToolPriorityHelper,
                              ),
                            ),
                          ),
                          kOpenHandHGap14,
                          Expanded(
                            child:
                                AnimatedDropdownButtonFormField<
                                  AiBuiltinToolLoadStrategy
                                >(
                                  initialValue: _loadStrategy,
                                  decoration: InputDecoration(
                                    labelText:
                                        l10n.builtinToolLoadStrategyLabel,
                                  ),
                                  items: AiBuiltinToolLoadStrategy.values
                                      .map(
                                        (s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(
                                            _loadStrategyLabelStatic(l10n, s),
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _loadStrategy = value);
                                    }
                                  },
                                ),
                          ),
                        ],
                      ),
                      kOpenHandGap14,

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.builtinToolForceLoadTitle),
                        subtitle: Text(
                          l10n.builtinToolForceLoadBody,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        value: _forceLoad,
                        onChanged: (value) =>
                            setState(() => _forceLoad = value),
                      ),
                      kOpenHandGap14,

                      // Max output chars & Timeout
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _maxOutputCharsController,
                              keyboardType: TextInputType.number,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: l10n.builtinToolMaxOutputLabel,
                                hintText: l10n.builtinToolGlobalDefaultHint,
                              ),
                            ),
                          ),
                          kOpenHandHGap14,
                          Expanded(
                            child: TextField(
                              controller: _timeoutSecondsController,
                              keyboardType: TextInputType.number,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: l10n.builtinToolTimeoutLabel,
                                hintText: l10n.builtinToolTimeoutHint(
                                  AiBuiltinToolConfig.defaultTimeoutSeconds,
                                ),
                                helperText: l10n.builtinToolTimeoutHelper(
                                  AiBuiltinToolConfig.defaultTimeoutSeconds,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      kOpenHandGap14,

                      // Retry on failure / Max retries
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l10n.builtinToolRetryLabel),
                              subtitle: Text(
                                l10n.builtinToolRetryBody,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              value: _retryOnFailure,
                              onChanged: (value) =>
                                  setState(() => _retryOnFailure = value),
                            ),
                          ),
                          kOpenHandHGap14,
                          Expanded(
                            child: TextField(
                              controller: _maxRetriesController,
                              enabled: _retryOnFailure,
                              keyboardType: TextInputType.number,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: l10n.builtinToolMaxRetriesLabel(
                                  AiBuiltinToolConfig.maxRetriesUpperBound,
                                ),
                                helperText: l10n.builtinToolMaxRetriesHelper(
                                  AiBuiltinToolConfig.maxRetriesUpperBound,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      kOpenHandGap14,

                      // Retry backoff base (ms)
                      TextField(
                        controller: _retryBackoffMsController,
                        enabled: _retryOnFailure,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: l10n.builtinToolBackoffLabel,
                          hintText: l10n.builtinToolBackoffHint(
                            AiBuiltinToolConfig.defaultRetryBackoffMs,
                          ),
                          helperText: l10n.builtinToolBackoffHelper(
                            AiBuiltinToolConfig.maxRetryBackoffMs,
                          ),
                        ),
                      ),
                      kOpenHandGap14,

                      // Require confirmation
                      _RequireConfirmationField(
                        value: _requireConfirmation,
                        onChanged: (v) =>
                            setState(() => _requireConfirmation = v),
                      ),
                      kOpenHandGap14,

                      // ── WebSearch-specific section ──
                      if (widget.initial.kind == AiBuiltinToolKind.webSearch &&
                          _webSearchSettings != null) ...[
                        _WebSearchSettingsEditor(
                          value: _webSearchSettings!,
                          availableModels: widget.availableModels,
                          recentModelSelections: widget.recentModelSelections,
                          onChanged: (next) =>
                              setState(() => _webSearchSettings = next),
                        ),
                        kOpenHandGap14,
                      ],

                      // ── WebFetch-specific section ──
                      if (widget.initial.kind == AiBuiltinToolKind.webFetch &&
                          _webFetchSettings != null) ...[
                        _WebFetchSettingsEditor(
                          value: _webFetchSettings!,
                          availableModels: widget.availableModels,
                          recentModelSelections: widget.recentModelSelections,
                          onChanged: (next) =>
                              setState(() => _webFetchSettings = next),
                        ),
                        kOpenHandGap14,
                      ],

                      // Tags
                      TextField(
                        controller: _tagsController,
                        decoration: InputDecoration(
                          labelText: l10n.builtinToolTagsLabel,
                          helperText: l10n.builtinToolTagsHelper,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Actions ──
              kOpenHandGap20,
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    label: l10n.commonCancel,
                  ),
                  kOpenHandHGap12,
                  OpenHandDialogActionButton.primary(
                    onPressed: _isSaving
                        ? null
                        : () {
                            setState(() => _isSaving = true);
                            Navigator.of(context).pop(_buildConfig());
                          },
                    label: l10n.commonSave,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _loadStrategyLabelStatic(
    AppLocalizations l10n,
    AiBuiltinToolLoadStrategy strategy,
  ) {
    return switch (strategy) {
      AiBuiltinToolLoadStrategy.eager => l10n.builtinToolLoadStrategyEagerFull,
      AiBuiltinToolLoadStrategy.lazy => l10n.builtinToolLoadStrategyLazy,
      AiBuiltinToolLoadStrategy.deferred =>
        l10n.builtinToolLoadStrategyDeferred,
    };
  }
}

class _RequireConfirmationField extends StatelessWidget {
  const _RequireConfirmationField({
    required this.value,
    required this.onChanged,
  });

  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.builtinToolRequireConfirmationTitle,
          style: theme.textTheme.titleSmall,
        ),
        kOpenHandGap6,
        Text(
          l10n.builtinToolRequireConfirmationBody,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap8,
        SegmentedButton<bool?>(
          segments: [
            ButtonSegment<bool?>(
              value: null,
              label: Text(l10n.builtinToolConfirmationDefault, softWrap: false),
            ),
            ButtonSegment<bool?>(
              value: true,
              label: Text(l10n.builtinToolConfirmationYes, softWrap: false),
            ),
            ButtonSegment<bool?>(
              value: false,
              label: Text(l10n.builtinToolConfirmationNo, softWrap: false),
            ),
          ],
          selected: {value},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onChanged(selection.first);
            }
          },
        ),
      ],
    );
  }
}

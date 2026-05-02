part of 'openhand_home_page.dart';

class _SessionMetadataDialog extends StatelessWidget {
  const _SessionMetadataDialog({
    required this.session,
    this.liveRuntimeToolPreview,
    this.activeProfile,
    this.claudeStyle = true,
  });

  final AiSession session;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final AiModelProfile? activeProfile;
  final bool claudeStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statistics = session.statistics;
    final environment = session.environment;
    final lastPromptMetadata = session.lastPromptMetadata;
    final runtimeStatus = _runtimeToolCatalogStatus(
      session,
      livePreview: liveRuntimeToolPreview,
    );
    final hasPromptMetadata = lastPromptMetadata.isNotEmpty;
    final writeCommandConfirmationEnabled =
        lastPromptMetadata['write_command_confirmation_enabled'] == true;
    final allowCommandRuleCount = _metadataInt(
      lastPromptMetadata['allow_command_rule_count'],
    );
    final allowCommandRules = _metadataObjectList(
      lastPromptMetadata['allow_command_rules'],
    );
    final todoWriteRecommended =
        lastPromptMetadata['todo_write_recommended'] == true;
    final todoWriteReason = '${lastPromptMetadata['todo_write_reason'] ?? ''}'
        .trim();
    final planHistory = session.planHistory.reversed.toList(growable: false);
    final currentTodos = session.todoItems
        .map((item) => item.toJson())
        .toList(growable: false);
    final recentErrors = session.recentErrors
        .where((error) => error.stage != 'title_generation')
        .toList(growable: false);
    final summaryBlocks = <Widget>[
      _MetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaMessages,
        value: '${statistics.totalMessageCount}',
      ),
      _MetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaPromptBuilds,
        value: '${statistics.promptBuildCount}',
      ),
      _MetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaCompressions,
        value: '${statistics.compressionRunCount}',
      ),
      _MetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaTotalTokens,
        value: '${statistics.totalTokens ?? 0}',
      ),
      _MetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaMode,
        value: _runtimeModeLabel(context, runtimeStatus, compact: true),
      ),
      _MetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaRuntimeTools,
        value: !runtimeStatus.supportsToolCalls
            ? '-'
            : runtimeStatus.hasSnapshot && !runtimeStatus.stale
            ? '${runtimeStatus.toolCount}'
            : AppLocalizations.of(context)!.sessMetaPending,
      ),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.sessMetaCurrentSessionMetadata,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          session.title,
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
              Wrap(spacing: 12, runSpacing: 12, children: summaryBlocks),
              ..._buildSessionCostSection(context, theme, colorScheme),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MetadataSection(
                        title: AppLocalizations.of(context)!.sessMetaSessionOverview,
                        children: [
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'session_id',
                            ),
                            value: session.id,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(context, 'template'),
                            value:
                                '${session.templateName} · v${session.templateInternalVersion}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'created_at',
                            ),
                            value: _formatDateTime(session.createdAt),
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'updated_at',
                            ),
                            value: _formatDateTime(session.updatedAt),
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'last_model',
                            ),
                            value:
                                session.lastUsedModelLabel ??
                                session.lastUsedModelId ??
                                '-',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'compression_checkpoint',
                            ),
                            value:
                                session.latestCompressionCheckpointMessageId ??
                                '-',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'latest_compression_at',
                            ),
                            value: session.latestCompressionAt == null
                                ? '-'
                                : _formatDateTime(session.latestCompressionAt!),
                          ),
                        ],
                      ),
                      if (session.templateId == 'hardness_engineering') ...[
                        const SizedBox(height: 16),
                        _buildHardnessConfigSection(context, session),
                      ],
                      if (session.templateId == 'programming_expert') ...[
                        const SizedBox(height: 16),
                        _buildProgrammingExpertConfigSection(context, session),
                      ],
                      if (session.metadata.entries
                          .where(
                            (e) =>
                                !(session.templateId ==
                                        'hardness_engineering' &&
                                    e.key == 'hardness_config') &&
                                !(session.templateId == 'programming_expert' &&
                                    e.key == 'programming_expert_config'),
                          )
                          .isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _MetadataSection(
                          title: AppLocalizations.of(context)!.sessMetaExtendedMetadata,
                          children: session.metadata.entries
                              .where(
                                (e) =>
                                    !(session.templateId ==
                                            'hardness_engineering' &&
                                        e.key == 'hardness_config') &&
                                    !(session.templateId ==
                                            'programming_expert' &&
                                        e.key == 'programming_expert_config'),
                              )
                              .map((entry) {
                                return _MetadataEntryRow(
                                  label: entry.key,
                                  value: '${entry.value}',
                                );
                              })
                              .toList(growable: false),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: AppLocalizations.of(context)!.sessMetaStatistics,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _MetadataChip(
                                label:
                                    '${AppLocalizations.of(context)!.sessMetaUser} ${statistics.userMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${AppLocalizations.of(context)!.sessMetaAssistant} ${statistics.assistantMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${AppLocalizations.of(context)!.sessMetaTool} ${statistics.toolMessageCount}',
                              ),
                              _MetadataChip(
                                label: 'MCP ${statistics.mcpMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${AppLocalizations.of(context)!.sessMetaSkill} ${statistics.skillMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${AppLocalizations.of(context)!.sessMetaCompression} ${statistics.compressionPointCount}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'total_input_characters',
                            ),
                            value: '${statistics.totalInputCharacters}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'total_output_characters',
                            ),
                            value: '${statistics.totalOutputCharacters}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'total_prompt_characters',
                            ),
                            value: '${statistics.totalPromptCharacters}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'last_prompt_system_message_count',
                            ),
                            value: '${statistics.lastPromptSystemMessageCount}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'last_prompt_history_message_count',
                            ),
                            value:
                                '${statistics.lastPromptHistoryMessageCount}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: AppLocalizations.of(context)!.sessMetaEnvironment,
                        children: [
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'locale_tag',
                            ),
                            value: environment.localeTag,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(context, 'platform'),
                            value: environment.platform,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'app_version',
                            ),
                            value:
                                '${environment.appVersion} (${environment.appBuildNumber})',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'compression_threshold_chars',
                            ),
                            value: '${environment.compressionThresholdChars}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'single_round_tool_call_limit',
                            ),
                            value: '${environment.singleRoundToolCallLimit}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'sequential_tool_round_limit',
                            ),
                            value: '${environment.sequentialToolRoundLimit}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'application_directory',
                            ),
                            value: environment.applicationDirectory,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'home_directory',
                            ),
                            value: environment.homeDirectory,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'settings_file',
                            ),
                            value: environment.settingsFilePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'skills_storage',
                            ),
                            value: environment.skillsStoragePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'mcp_servers_file',
                            ),
                            value: environment.mcpServersFilePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'user_memory_file',
                            ),
                            value: environment.userMemoryFilePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'sessions_directory',
                            ),
                            value: environment.sessionsDirectoryPath,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: AppLocalizations.of(context)!.sessMetaCommandPolicy,
                        children: !hasPromptMetadata
                            ? [
                                Text(
                                  AppLocalizations.of(context)!.sessMetaPromptMetadataIsNotAvailableYet,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ]
                            : [
                                _MetadataEntryRow(
                                  label: AppLocalizations.of(context)!.sessMetaWriteConfirmation,
                                  value: writeCommandConfirmationEnabled
                                      ? AppLocalizations.of(context)!.sessMetaRequired
                                      : AppLocalizations.of(context)!.sessMetaNotRequired,
                                ),
                                _MetadataEntryRow(
                                  label: AppLocalizations.of(context)!.sessMetaAllowRules,
                                  value: '$allowCommandRuleCount',
                                ),
                                if (allowCommandRules.isEmpty)
                                  Text(
                                    AppLocalizations.of(context)!.sessMetaThereAreNoSurfacedAllowCommand,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: allowCommandRules
                                        .map((rule) {
                                          final pattern =
                                              '${rule['pattern'] ?? ''}'.trim();
                                          final matchMode =
                                              '${rule['match_mode'] ?? ''}'
                                                  .trim();
                                          if (pattern.isEmpty) {
                                            return null;
                                          }
                                          final prefix = matchMode.isEmpty
                                              ? ''
                                              : '$matchMode: ';
                                          return _MetadataChip(
                                            label: '$prefix$pattern',
                                          );
                                        })
                                        .whereType<Widget>()
                                        .toList(growable: false),
                                  ),
                              ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: AppLocalizations.of(context)!.sessMetaRuntimeOrchestration,
                        children: [
                          _MetadataEntryRow(
                            label: AppLocalizations.of(context)!.sessMetaStateSource,
                            value: runtimeStatus.isLivePreview
                                ? AppLocalizations.of(context)!.sessMetaGeneratedFromTheCurrentModelMcp
                                : AppLocalizations.of(context)!.sessMetaTheLastPersistedRuntimeSnapshot,
                          ),
                          _MetadataEntryRow(
                            label: AppLocalizations.of(context)!.sessMetaMode,
                            value: _runtimeModeLabel(context, runtimeStatus),
                          ),
                          _MetadataEntryRow(
                            label: AppLocalizations.of(context)!.sessMetaToolCatalogState,
                            value: _runtimeToolCatalogStatusLabel(
                              context,
                              runtimeStatus,
                            ),
                          ),
                          _MetadataEntryRow(
                            label: AppLocalizations.of(context)!.sessMetaGateReason,
                            value: _runtimeToolGateReasonLabel(
                              context,
                              runtimeStatus.gateReason,
                            ),
                          ),
                          _MetadataEntryRow(
                            label: AppLocalizations.of(context)!.sessMetaRuntimeToolCount,
                            value:
                                runtimeStatus.hasSnapshot &&
                                    !runtimeStatus.stale
                                ? '${runtimeStatus.toolCount}'
                                : AppLocalizations.of(context)!.sessMetaRefreshesNextRound,
                          ),
                          if (runtimeStatus.notices.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              AppLocalizations.of(context)!.sessMetaRuntimeNotices,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: runtimeStatus.notices
                                  .map((item) => _MetadataChip(label: item))
                                  .toList(growable: false),
                            ),
                          ],
                          if (runtimeStatus.toolNames.isNotEmpty &&
                              !runtimeStatus.stale) ...[
                            const SizedBox(height: 12),
                            Text(
                              AppLocalizations.of(context)!.sessMetaCurrentRuntimeTools,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: runtimeStatus.toolNames
                                  .map((item) => _MetadataChip(label: item))
                                  .toList(growable: false),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: AppLocalizations.of(context)!.sessMetaTaskTracking,
                        children: [
                          _MetadataEntryRow(
                            label: AppLocalizations.of(context)!.sessMetaCurrentTodos,
                            value: '${currentTodos.length}',
                          ),
                          _MetadataEntryRow(
                            label: AppLocalizations.of(context)!.sessMetaPlanRecords,
                            value: '${planHistory.length}',
                          ),
                          _MetadataEntryRow(
                            label: AppLocalizations.of(context)!.sessMetaTodowriteReminder,
                            value: hasPromptMetadata
                                ? (todoWriteRecommended
                                      ? AppLocalizations.of(context)!.sessMetaTriggered
                                      : AppLocalizations.of(context)!.sessMetaNotTriggered)
                                : AppLocalizations.of(context)!.sessMetaUnavailable,
                          ),
                          if (todoWriteReason.isNotEmpty)
                            _MetadataEntryRow(
                              label: AppLocalizations.of(context)!.sessMetaReminderReason,
                              value: todoWriteReason,
                            ),
                          if (currentTodos.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: currentTodos
                                  .map((todo) {
                                    final id = '${todo['id'] ?? ''}'.trim();
                                    final content = '${todo['content'] ?? ''}'
                                        .trim();
                                    final status = '${todo['status'] ?? ''}'
                                        .trim();
                                    if (content.isEmpty) {
                                      return null;
                                    }
                                    final prefix = status.isEmpty
                                        ? ''
                                        : '[$status] ';
                                    final idPrefix = id.isEmpty ? '' : '$id: ';
                                    return _MetadataChip(
                                      label: '$prefix$idPrefix$content',
                                    );
                                  })
                                  .whereType<Widget>()
                                  .toList(growable: false),
                            ),
                          if (planHistory.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              AppLocalizations.of(context)!.sessMetaPlanHistory,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...planHistory.asMap().entries.map(
                              (entry) => _MetadataPlanRecordCard(
                                planIndex: planHistory.length - entry.key,
                                planRecord: entry.value,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: AppLocalizations.of(context)!.sessMetaRecentErrors,
                        children: recentErrors.isEmpty
                            ? [
                                Text(
                                  AppLocalizations.of(context)!.sessMetaThereAreNoSessionErrorsTo,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ]
                            : recentErrors
                                  .map(
                                    (error) => _MetadataErrorCard(error: error),
                                  )
                                  .toList(growable: false),
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: AppLocalizations.of(context)!.sessMetaLastPromptMetadata,
                        children: [
                          _MetadataJsonPanel(
                            content: const JsonEncoder.withIndent(
                              '  ',
                            ).convert(session.lastPromptMetadata),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(),
                    label: AppLocalizations.of(context)!.sessMetaClose,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 1C-C：在 summaryBlocks 之后追加按 4 分量拆解的成本估算。
  /// 数据源：`session.statistics` 累计 token + `activeProfile` 单价。
  /// 当 [activeProfile] 为 null 或所有价格字段缺失时返回空 list — UI 不渲染。
  List<Widget> _buildSessionCostSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (activeProfile == null) return const <Widget>[];
    final stats = session.statistics;
    final breakdown = AiCostBreakdown.compute(
      usage: AiTokenUsage(
        promptTokens: stats.totalPromptTokens ?? 0,
        completionTokens: stats.totalCompletionTokens ?? 0,
        cacheReadTokens: stats.cacheReadTokens ?? 0,
        cacheCreationTokens: stats.cacheCreationTokens ?? 0,
      ),
      profile: activeProfile,
      claudeStyle: claudeStyle,
    );
    if (breakdown == null || breakdown.isEmpty) return const <Widget>[];

    final l10n = AppLocalizations.of(context)!;
    final budget = context
        .watch<SettingsController>()
        .aiBudgetUsdPerSession;
    final overBudget = budget > 0 &&
        breakdown.totalUsd != null &&
        breakdown.totalUsd! > budget;
    final headStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    );
    final keyStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final amberStyle = valueStyle?.copyWith(color: Colors.amber.shade700);

    String fmt(double v) {
      if (v == 0) return r'$0.0000';
      if (v >= 1) return '\$${v.toStringAsFixed(2)}';
      if (v >= 0.01) return '\$${v.toStringAsFixed(4)}';
      return '\$${v.toStringAsFixed(6)}';
    }

    Widget row(String label, double usd, {TextStyle? style}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: keyStyle),
            Text(fmt(usd), style: style ?? valueStyle),
          ],
        ),
      );
    }

    return <Widget>[
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tokenPopupCostHeading.toUpperCase(), style: headStyle),
            const SizedBox(height: 6),
            if (breakdown.inputUsd != null)
              row(l10n.tokenPopupCostInput, breakdown.inputUsd!),
            if (breakdown.outputUsd != null)
              row(l10n.tokenPopupCostOutput, breakdown.outputUsd!),
            if (breakdown.cacheReadUsd != null)
              row(l10n.tokenPopupCostCacheRead, breakdown.cacheReadUsd!,
                  style: amberStyle),
            if (breakdown.cacheWriteUsd != null)
              row(l10n.tokenPopupCostCacheWrite, breakdown.cacheWriteUsd!,
                  style: amberStyle),
            if (breakdown.totalUsd != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.tokenPopupCostTotal,
                      style: keyStyle?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      fmt(breakdown.totalUsd!),
                      style: valueStyle?.copyWith(
                        color: overBudget
                            ? colorScheme.error
                            : colorScheme.primary,
                        fontWeight:
                            overBudget ? FontWeight.w800 : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (overBudget) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.sessionMetadataOverBudgetNotice(
                            fmt(breakdown.totalUsd!),
                            fmt(budget),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    ];
  }
}

class _MetadataSection extends StatelessWidget {
  const _MetadataSection({required this.title, required this.children});

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
        borderRadius: BorderRadius.circular(20),
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

class _MetadataSummaryTile extends StatelessWidget {
  const _MetadataSummaryTile({required this.label, required this.value});

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
        borderRadius: _borderRadius18,
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

class _MetadataEntryRow extends StatelessWidget {
  const _MetadataEntryRow({required this.label, required this.value});

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

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: _borderRadius999,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _sessionPlanStatusLabel(
  BuildContext context,
  AiSessionPlanStatus status,
) {
  return switch (status) {
    AiSessionPlanStatus.pendingApproval => AppLocalizations.of(context)!.sessMetaPendingApproval,
    AiSessionPlanStatus.inProgress => AppLocalizations.of(context)!.sessMetaInProgress,
    AiSessionPlanStatus.completed => AppLocalizations.of(context)!.sessMetaCompleted,
    AiSessionPlanStatus.failed => AppLocalizations.of(context)!.sessMetaFailed,
    AiSessionPlanStatus.cancelled => AppLocalizations.of(context)!.sessMetaCancelled,
  };
}

class _MetadataPlanRecordCard extends StatelessWidget {
  const _MetadataPlanRecordCard({
    required this.planIndex,
    required this.planRecord,
  });

  final int planIndex;
  final AiSessionPlanRecord planRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = switch (planRecord.status) {
      AiSessionPlanStatus.pendingApproval => colorScheme.secondary,
      AiSessionPlanStatus.inProgress => colorScheme.tertiary,
      AiSessionPlanStatus.completed => colorScheme.primary,
      AiSessionPlanStatus.failed => colorScheme.error,
      AiSessionPlanStatus.cancelled => colorScheme.outline,
    };
    final steps = planRecord.steps
        .map((item) {
          final content = item.content.trim();
          if (content.isEmpty) {
            return null;
          }
          return _MetadataChip(label: content);
        })
        .whereType<Widget>()
        .toList(growable: false);
    final planSummary = planRecord.plan.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                AppLocalizations.of(context)!.sessMetaPlanPlanindex(planIndex),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: _borderRadius999,
                ),
                child: Text(
                  _sessionPlanStatusLabel(context, planRecord.status),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${AppLocalizations.of(context)!.sessMetaCreated} ${_formatDateTime(planRecord.createdAt)} · ${AppLocalizations.of(context)!.sessMetaUpdated} ${_formatDateTime(planRecord.updatedAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (planSummary.isNotEmpty && steps.isEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(
              planSummary,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: steps),
          ],
        ],
      ),
    );
  }
}

class _MetadataErrorCard extends StatelessWidget {
  const _MetadataErrorCard({required this.error});

  final AiSessionErrorRecord error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentation = _presentSessionError(context, error);
    final detail = (error.detail ?? '').trim();
    final rawMessage = error.message.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            presentation.title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onErrorContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            presentation.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onErrorContainer,
              height: 1.4,
            ),
          ),
          if (detail.isNotEmpty && detail != rawMessage) ...[
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.sessMetaErrorDetail,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onErrorContainer.withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${_sessionErrorStageLabel(context, error.stage)} · ${_formatDateTime(error.createdAt)} · ${error.hasBeenPresented ? AppLocalizations.of(context)!.sessMetaPresented : AppLocalizations.of(context)!.sessMetaPending}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onErrorContainer.withValues(alpha: 0.84),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionErrorPresentation {
  const _SessionErrorPresentation({required this.title, required this.message});

  final String title;
  final String message;
}

_SessionErrorPresentation _presentSessionError(
  BuildContext context,
  AiSessionErrorRecord error,
) {
  final fallbackTitle = _sessionErrorStageLabel(context, error.stage);
  final rawMessage = error.message.trim();
  final fallbackMessage = rawMessage.isNotEmpty
      ? rawMessage
      : AppLocalizations.of(context)!.sessMetaThisSessionEndedEarlyRetryThe;
  // Chat 系列 stage 直接使用底层 AiChatException 输出的「现象 / 原因 / 建议」
  // 三段式中英诊断文案：第一行作为 banner 标题，其余多行作为正文，避免之前
  // 一律展示通用兜底文案、丢失协议/网络层细节的问题。
  if (_isStructuredChatErrorMessage(rawMessage) &&
      const <String>{
        'chat_request',
        'chat_stream',
        'chat_continuation_request',
      }.contains(error.stage)) {
    return _splitStructuredErrorMessage(rawMessage, fallbackTitle);
  }
  return switch (error.stage) {
    'tool_loop' => _SessionErrorPresentation(
      title: AppLocalizations.of(context)!.sessMetaToolCallsStoppedForSafety,
      message: () {
        final configuredLimit = _extractConfiguredToolLoopLimit(
          error.detail ?? '',
        );
        final limitSuffix = configuredLimit == null
            ? ''
            : AppLocalizations.of(context)!.sessMetaTheCurrentSequentialToolRoundLimit(configuredLimit);
        return AppLocalizations.of(context)!.sessMetaOpenhandStoppedThisSessionForSafety +
            limitSuffix;
      }(),
    ),
    'chat_stream' => _SessionErrorPresentation(
      title: AppLocalizations.of(context)!.sessMetaResponseInterrupted,
      message: AppLocalizations.of(context)!.sessMetaTheResponseWasInterruptedWhileStreaming,
    ),
    'chat_request' => _SessionErrorPresentation(
      title: AppLocalizations.of(context)!.sessMetaRequestFailed,
      message: AppLocalizations.of(context)!.sessMetaTheRequestFailedBeforeTheAssistant,
    ),
    'chat_continuation_request' => _SessionErrorPresentation(
      title: AppLocalizations.of(context)!.sessMetaContinuationFailed,
      message: AppLocalizations.of(context)!.sessMetaTheSessionFailedWhileRequestingThe,
    ),
    _ => _SessionErrorPresentation(
      title: fallbackTitle,
      message: fallbackMessage,
    ),
  };
}

int? _extractConfiguredToolLoopLimit(String detail) {
  final match = _toolLoopLimitPattern.firstMatch(detail);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1) ?? '');
}

/// 判断 `error.message` 是否来自 AiChatService / AiImageGenerationService /
/// AiModelScanner 抛出的「现象 / 原因 / 建议」三段式中英双语文案。三个
/// helper (`_ChatErrorMessages` / `_MediaErrorMessages` / `_ScanErrorMessages`)
/// 共用 `_format` 写出 `原因 / Why:` + `建议 / Try:` 两个固定锚点，匹配其中
/// 任一即可识别为结构化文案。
bool _isStructuredChatErrorMessage(String raw) {
  if (raw.isEmpty) return false;
  return raw.contains('原因 / Why:') || raw.contains('建议 / Try:');
}

/// 把结构化三段式文案拆成 banner 用的 (title, message) —— 第一非空行作为
/// 标题，其余原样保留作为正文。当原文异常时退回 [fallbackTitle]。
_SessionErrorPresentation _splitStructuredErrorMessage(
  String raw,
  String fallbackTitle,
) {
  final lines = raw.split('\n');
  String title = fallbackTitle;
  var headerIndex = -1;
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    if (trimmed.isEmpty) continue;
    title = trimmed;
    headerIndex = i;
    break;
  }
  if (headerIndex < 0) {
    return _SessionErrorPresentation(title: fallbackTitle, message: raw);
  }
  final body = lines
      .sublist(headerIndex + 1)
      .join('\n')
      .replaceFirst(RegExp(r'^\n+'), '')
      .trimRight();
  return _SessionErrorPresentation(
    title: title,
    message: body.isEmpty ? raw : body,
  );
}

String _sessionErrorStageLabel(BuildContext context, String stage) {
  return switch (stage) {
    'tool_loop' => AppLocalizations.of(context)!.sessMetaSafetyStop,
    'chat_stream' => AppLocalizations.of(context)!.sessMetaStreamError,
    'chat_request' => AppLocalizations.of(context)!.sessMetaRequestError,
    'chat_continuation_request' => AppLocalizations.of(context)!.sessMetaContinuationError,
    'tool_execution' => AppLocalizations.of(context)!.sessMetaToolExecutionError,
    'history_compression' => AppLocalizations.of(context)!.sessMetaCompressionError,
    'user_prompt_hook' => AppLocalizations.of(context)!.sessMetaPromptBlocked,
    'title_generation' => AppLocalizations.of(context)!.sessMetaTitleGenerationError,
    _ => AppLocalizations.of(context)!.sessMetaSessionError,
  };
}

class _MetadataJsonPanel extends StatelessWidget {
  const _MetadataJsonPanel({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF17181C),
        borderRadius: _borderRadius18,
      ),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontFamily: 'monospace',
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

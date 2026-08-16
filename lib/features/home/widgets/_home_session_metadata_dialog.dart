part of '../openhand_home_page.dart';

const Duration _kCacheHitTrendRevealDuration = kOpenHandMotion520;

class _LiveSessionMetadataDialog extends StatelessWidget {
  const _LiveSessionMetadataDialog({
    required this.session,
    required this.controller,
    this.liveRuntimeToolPreview,
    this.activeProfile,
    this.claudeStyle = true,
  });

  final AiSession session;
  final AiSessionController controller;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final AiModelProfile? activeProfile;
  final bool claudeStyle;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final liveSession = controller.sessionById(session.id) ?? session;
        return _SessionMetadataDialog(
          session: liveSession,
          controller: controller,
          liveRuntimeToolPreview: liveRuntimeToolPreview,
          activeProfile: activeProfile,
          claudeStyle: claudeStyle,
        );
      },
    );
  }
}

class _SessionMetadataDialog extends StatelessWidget {
  const _SessionMetadataDialog({
    required this.session,
    required this.controller,
    this.liveRuntimeToolPreview,
    this.activeProfile,
    this.claudeStyle = true,
  });

  final AiSession session;
  final AiSessionController controller;
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
        lastPromptMetadata['write_command_confirmation_required'] is bool
        ? lastPromptMetadata['write_command_confirmation_required'] == true
        : lastPromptMetadata['write_command_confirmation_enabled'] == true &&
              !runtimeStatus.fullAccessPermission;
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
    final machineTerminalMetadata = _metadataObjectMap(
      session.metadata[kMachineTerminalMetadataKey],
    );
    final extendedMetadataEntries = _visibleSessionMetadataEntries(session);
    final summaryBlocks = <Widget>[
      OpenHandMetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaMessages,
        value: '${statistics.totalMessageCount}',
      ),
      OpenHandMetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaPromptBuilds,
        value: '${statistics.promptBuildCount}',
      ),
      OpenHandMetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaCompressions,
        value: '${statistics.compressionRunCount}',
      ),
      OpenHandMetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaTotalTokens,
        value: '${statistics.totalTokens ?? 0}',
      ),
      if ((statistics.reasoningTokens ?? 0) > 0)
        OpenHandMetadataSummaryTile(
          label: AppLocalizations.of(context)!.tokenPopupReasoning,
          value: '${statistics.reasoningTokens}',
        ),
      OpenHandMetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaMode,
        value: _runtimeModeLabel(context, runtimeStatus, compact: true),
      ),
      OpenHandMetadataSummaryTile(
        label: AppLocalizations.of(context)!.permissionLabel,
        value: runtimeStatus.fullAccessPermission
            ? AppLocalizations.of(context)!.mcpServerStatusEnabled
            : AppLocalizations.of(context)!.mcpServerStatusDisabled,
      ),
      OpenHandMetadataSummaryTile(
        label: AppLocalizations.of(context)!.sessMetaRuntimeTools,
        value: !runtimeStatus.supportsToolCalls
            ? '-'
            : runtimeStatus.hasSnapshot && !runtimeStatus.stale
            ? '${runtimeStatus.toolCount}'
            : AppLocalizations.of(context)!.sessMetaPending,
      ),
    ];

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OpenHandMetadataDialogHeader(
              title: AppLocalizations.of(
                context,
              )!.sessMetaCurrentSessionMetadata,
              subtitle: session.title,
            ),
            kOpenHandGap18,
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 12, runSpacing: 12, children: summaryBlocks),
                    ..._buildSessionCostSection(context, theme, colorScheme),
                    kOpenHandGap18,
                    OpenHandMetadataSection(
                      title: AppLocalizations.of(
                        context,
                      )!.sessMetaSessionOverview,
                      children: [
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(context, 'session_id'),
                          value: session.id,
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(context, 'template'),
                          value:
                              '${session.templateName} · v${session.templateInternalVersion}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(context, 'created_at'),
                          value: formatYearMonthDayHmLocal(session.createdAt),
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(context, 'updated_at'),
                          value: formatYearMonthDayHmLocal(session.updatedAt),
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(context, 'last_model'),
                          value:
                              session.lastUsedModelLabel ??
                              session.lastUsedModelId ??
                              '-',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'auto_title_acquired',
                          ),
                          value: session.autoTitleAcquired
                              ? '✓ ${openHandLocalizedText(context, zh: '已获取', en: 'Acquired')}'
                              : '✗ ${openHandLocalizedText(context, zh: '未获取', en: 'Not acquired')}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'auto_title_retry_count',
                          ),
                          value: '${session.autoTitleRetryCount}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'compression_checkpoint',
                          ),
                          value:
                              session.latestCompressionCheckpointMessageId ??
                              '-',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'latest_compression_at',
                          ),
                          value: session.latestCompressionAt == null
                              ? '-'
                              : formatYearMonthDayHmLocal(session.latestCompressionAt!),
                        ),
                      ],
                    ),
                    if (session.templateId == 'harness_engineering') ...[
                      kOpenHandGap16,
                      _buildHarnessConfigSection(context, session),
                    ],
                    if (session.templateId == 'programming_expert') ...[
                      kOpenHandGap16,
                      _buildProgrammingExpertConfigSection(context, session),
                    ],
                    if (session.templateId == 'web_reverse_expert') ...[
                      kOpenHandGap16,
                      _buildWebReverseConfigSection(context, session),
                    ],
                    if (machineTerminalMetadata.isNotEmpty) ...[
                      kOpenHandGap16,
                      _buildMachineTerminalMetadataSection(
                        context,
                        machineTerminalMetadata,
                      ),
                    ],
                    if (extendedMetadataEntries.isNotEmpty) ...[
                      kOpenHandGap16,
                      OpenHandMetadataSection(
                        title: AppLocalizations.of(
                          context,
                        )!.sessMetaExtendedMetadata,
                        children: extendedMetadataEntries
                            .map(
                              (entry) => _MetadataStructuredValue(
                                label: entry.key,
                                value: entry.value,
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                    kOpenHandGap16,
                    OpenHandMetadataSection(
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
                        kOpenHandGap12,
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'total_input_characters',
                          ),
                          value: '${statistics.totalInputCharacters}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'total_output_characters',
                          ),
                          value: '${statistics.totalOutputCharacters}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'total_prompt_characters',
                          ),
                          value: '${statistics.totalPromptCharacters}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'last_prompt_system_message_count',
                          ),
                          value: '${statistics.lastPromptSystemMessageCount}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'last_prompt_history_message_count',
                          ),
                          value: '${statistics.lastPromptHistoryMessageCount}',
                        ),
                      ],
                    ),
                    ..._buildContextBudgetSection(
                      context,
                      theme,
                      colorScheme,
                      lastPromptMetadata,
                    ),
                    ..._buildPostCompactRehydrationSection(
                      context,
                      lastPromptMetadata,
                    ),
                    ..._buildCompactMemorySection(context, lastPromptMetadata),
                    kOpenHandGap16,
                    OpenHandMetadataSection(
                      title: AppLocalizations.of(context)!.sessMetaEnvironment,
                      children: [
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(context, 'locale_tag'),
                          value: environment.localeTag,
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(context, 'platform'),
                          value: environment.platform,
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'app_version',
                          ),
                          value:
                              '${environment.appVersion} (${environment.appBuildNumber})',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'compression_threshold_chars',
                          ),
                          value: '${environment.compressionThresholdChars}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'single_round_tool_call_limit',
                          ),
                          value: '${environment.singleRoundToolCallLimit}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'sequential_tool_round_limit',
                          ),
                          value: '${environment.sequentialToolRoundLimit}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'application_directory',
                          ),
                          value: environment.applicationDirectory,
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'home_directory',
                          ),
                          value: environment.homeDirectory,
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'settings_file',
                          ),
                          value: environment.settingsFilePath,
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'skills_storage',
                          ),
                          value: environment.skillsStoragePath,
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'mcp_servers_file',
                          ),
                          value: environment.mcpServersFilePath,
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'user_memory_file',
                          ),
                          value: environment.userMemoryFilePath,
                        ),
                        OpenHandMetadataEntryRow(
                          label: _localizedMetadataField(
                            context,
                            'sessions_directory',
                          ),
                          value: environment.sessionsDirectoryPath,
                        ),
                      ],
                    ),
                    kOpenHandGap16,
                    OpenHandMetadataSection(
                      title: AppLocalizations.of(
                        context,
                      )!.sessMetaCommandPolicy,
                      children: !hasPromptMetadata
                          ? [
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.sessMetaPromptMetadataIsNotAvailableYet,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ]
                          : [
                              OpenHandMetadataEntryRow(
                                label: AppLocalizations.of(
                                  context,
                                )!.sessMetaWriteConfirmation,
                                value: writeCommandConfirmationEnabled
                                    ? AppLocalizations.of(
                                        context,
                                      )!.sessMetaRequired
                                    : AppLocalizations.of(
                                        context,
                                      )!.sessMetaNotRequired,
                              ),
                              OpenHandMetadataEntryRow(
                                label: AppLocalizations.of(
                                  context,
                                )!.sessMetaAllowRules,
                                value: '$allowCommandRuleCount',
                              ),
                              if (allowCommandRules.isEmpty)
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.sessMetaThereAreNoSurfacedAllowCommand,
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
                    kOpenHandGap16,
                    OpenHandMetadataSection(
                      title: AppLocalizations.of(
                        context,
                      )!.sessMetaRuntimeOrchestration,
                      children: [
                        OpenHandMetadataEntryRow(
                          label: AppLocalizations.of(
                            context,
                          )!.sessMetaStateSource,
                          value: runtimeStatus.isLivePreview
                              ? AppLocalizations.of(
                                  context,
                                )!.sessMetaGeneratedFromTheCurrentModelMcp
                              : AppLocalizations.of(
                                  context,
                                )!.sessMetaTheLastPersistedRuntimeSnapshot,
                        ),
                        OpenHandMetadataEntryRow(
                          label: AppLocalizations.of(context)!.sessMetaMode,
                          value: _runtimeModeLabel(context, runtimeStatus),
                        ),
                        OpenHandMetadataEntryRow(
                          label: AppLocalizations.of(context)!.permissionLabel,
                          value: runtimeStatus.fullAccessPermission
                              ? AppLocalizations.of(
                                  context,
                                )!.mcpServerStatusEnabled
                              : AppLocalizations.of(
                                  context,
                                )!.mcpServerStatusDisabled,
                        ),
                        OpenHandMetadataEntryRow(
                          label: AppLocalizations.of(
                            context,
                          )!.sessMetaToolCatalogState,
                          value: _runtimeToolCatalogStatusLabel(
                            context,
                            runtimeStatus,
                          ),
                        ),
                        OpenHandMetadataEntryRow(
                          label: AppLocalizations.of(
                            context,
                          )!.sessMetaGateReason,
                          value: _runtimeToolGateReasonLabel(
                            context,
                            runtimeStatus.gateReason,
                          ),
                        ),
                        OpenHandMetadataEntryRow(
                          label: AppLocalizations.of(
                            context,
                          )!.sessMetaRuntimeToolCount,
                          value:
                              runtimeStatus.hasSnapshot && !runtimeStatus.stale
                              ? '${runtimeStatus.toolCount}'
                              : AppLocalizations.of(
                                  context,
                                )!.sessMetaRefreshesNextRound,
                        ),
                        if (runtimeStatus.notices.isNotEmpty) ...[
                          kOpenHandGap12,
                          Text(
                            AppLocalizations.of(
                              context,
                            )!.sessMetaRuntimeNotices,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          kOpenHandGap10,
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
                          kOpenHandGap12,
                          Text(
                            AppLocalizations.of(
                              context,
                            )!.sessMetaCurrentRuntimeTools,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          kOpenHandGap10,
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
                    kOpenHandGap16,
                    OpenHandMetadataSection(
                      title: AppLocalizations.of(context)!.sessMetaTaskTracking,
                      children: [
                        OpenHandMetadataEntryRow(
                          label: AppLocalizations.of(
                            context,
                          )!.sessMetaCurrentTodos,
                          value: '${currentTodos.length}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: AppLocalizations.of(
                            context,
                          )!.sessMetaPlanRecords,
                          value: '${planHistory.length}',
                        ),
                        OpenHandMetadataEntryRow(
                          label: AppLocalizations.of(
                            context,
                          )!.sessMetaTodowriteReminder,
                          value: hasPromptMetadata
                              ? (todoWriteRecommended
                                    ? AppLocalizations.of(
                                        context,
                                      )!.sessMetaTriggered
                                    : AppLocalizations.of(
                                        context,
                                      )!.sessMetaNotTriggered)
                              : AppLocalizations.of(
                                  context,
                                )!.sessMetaUnavailable,
                        ),
                        if (todoWriteReason.isNotEmpty)
                          OpenHandMetadataEntryRow(
                            label: AppLocalizations.of(
                              context,
                            )!.sessMetaReminderReason,
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
                          kOpenHandGap12,
                          Text(
                            AppLocalizations.of(context)!.sessMetaPlanHistory,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          kOpenHandGap10,
                          ...planHistory.asMap().entries.map(
                            (entry) => _MetadataPlanRecordCard(
                              planIndex: planHistory.length - entry.key,
                              planRecord: entry.value,
                            ),
                          ),
                        ],
                      ],
                    ),
                    kOpenHandGap16,
                    OpenHandMetadataSection(
                      title: AppLocalizations.of(context)!.sessMetaRecentErrors,
                      children: recentErrors.isEmpty
                          ? [
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.sessMetaThereAreNoSessionErrorsTo,
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
                    kOpenHandGap16,
                    OpenHandMetadataSection(
                      title: AppLocalizations.of(
                        context,
                      )!.sessMetaLastPromptMetadata,
                      children: [
                        _MetadataJsonPanel(
                          content: prettyPrintJson(session.lastPromptMetadata),
                        ),
                      ],
                    ),
                    _SessionAuditContent(
                      session: session,
                      controller: controller,
                      claudeStyle: claudeStyle,
                    ),
                    kOpenHandGap4,
                  ],
                ),
              ),
            ),
            kOpenHandGap18,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
    );
  }

  /// 在 summaryBlocks 之后渲染缓存命中率随消息推进的折线趋势图。
  /// 数据源：优先使用 session.statistics 内的完整预计算趋势点；缺失时才从
  /// 当前消息窗口兜底重算。低于 2 个数据点时不渲染。
  ///
  /// 抽出独立的 [_CacheHitTrendChart] 子部件支持
  /// (a) 悬停 tooltip 标注每点 %；(b) 切换显示另一条协议公式的叠加曲线。
  List<Widget> _buildCacheHitTrendSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final trend = SessionCacheHitTrend.fromStatisticsOrSession(
      session,
      claudeStyle: claudeStyle,
    );
    if (!trend.hasEnoughPoints) return const <Widget>[];

    return [
      kOpenHandGap12,
      _CacheHitTrendChart(trend: trend, primaryClaudeStyle: claudeStyle),
    ];
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
        reasoningTokens: stats.reasoningTokens,
      ),
      profile: activeProfile,
      claudeStyle: claudeStyle,
    );
    if (breakdown == null || breakdown.isEmpty) return const <Widget>[];

    final l10n = AppLocalizations.of(context)!;
    final budget = context.select<SettingsController, double>(
      (controller) => controller.aiBudgetUsdPerSession,
    );
    final overBudget =
        budget > 0 &&
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
      kOpenHandGap14,
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: kOpenHandBorderRadius12,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tokenPopupCostHeading.toUpperCase(), style: headStyle),
            kOpenHandGap6,
            if (breakdown.inputUsd != null)
              row(l10n.tokenPopupCostInput, breakdown.inputUsd!),
            if (breakdown.outputUsd != null)
              row(l10n.tokenPopupCostOutput, breakdown.outputUsd!),
            if (breakdown.cacheReadUsd != null)
              row(
                l10n.tokenPopupCostCacheRead,
                breakdown.cacheReadUsd!,
                style: amberStyle,
              ),
            if (breakdown.cacheWriteUsd != null)
              row(
                l10n.tokenPopupCostCacheWrite,
                breakdown.cacheWriteUsd!,
                style: amberStyle,
              ),
            if (breakdown.totalUsd != null) ...[
              kOpenHandGap4,
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
                        fontWeight: overBudget ? FontWeight.w800 : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (overBudget) ...[
                kOpenHandGap6,
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.55),
                    borderRadius: kOpenHandBorderRadius8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: colorScheme.onErrorContainer,
                      ),
                      kOpenHandHGap6,
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

  List<Widget> _buildContextBudgetSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    Map<String, Object?> metadata,
  ) {
    final cacheHitTrendWidgets = _buildCacheHitTrendSection(
      context,
      theme,
      colorScheme,
    );
    final estimatedTokens = _metadataInt(
      metadata['context_budget_estimated_prompt_tokens'],
    );
    if (estimatedTokens <= 0 && cacheHitTrendWidgets.isEmpty) {
      return const <Widget>[];
    }
    final maxTokens = _metadataInt(metadata['context_budget_model_max_tokens']);
    final remainingTokens = _metadataInt(
      metadata['context_budget_remaining_tokens'],
    );
    final effectiveWindowTokens = _metadataInt(
      metadata['context_budget_effective_window_tokens'],
    );
    final autoCompactThresholdTokens = _metadataInt(
      metadata['context_budget_auto_compact_threshold_tokens'],
    );
    final usagePercent = _metadataInt(metadata['context_budget_usage_percent']);
    final percentLeft = _metadataInt(metadata['context_budget_percent_left']);
    final status = '${metadata['context_budget_status'] ?? 'unknown'}'.trim();
    final statusColor = switch (status) {
      'critical' => colorScheme.error,
      'auto_compact' => colorScheme.tertiary,
      'warning' => Colors.amber.shade700,
      'ok' => colorScheme.primary,
      _ => colorScheme.outline,
    };
    final statusLabel = switch (status) {
      'critical' => openHandLocalizedText(context, zh: '危险', en: 'Critical'),
      'auto_compact' => openHandLocalizedText(
        context,
        zh: '需压缩',
        en: 'Compact',
      ),
      'warning' => openHandLocalizedText(context, zh: '偏高', en: 'High'),
      'ok' => openHandLocalizedText(context, zh: '正常', en: 'OK'),
      _ => openHandUnknownLabel(context),
    };
    final usageValue = maxTokens > 0
        ? (usagePercent / 100).clamp(0.0, 1.0)
        : null;

    return <Widget>[
      kOpenHandGap16,
      OpenHandMetadataSection(
        title: openHandLocalizedText(
          context,
          zh: '上下文预算',
          en: 'Context Budget',
        ),
        children: [
          if (estimatedTokens > 0) ...[
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: usageValue ?? 0,
                    minHeight: 8,
                    borderRadius: kOpenHandPillBorderRadius,
                    color: statusColor,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
                kOpenHandHGap12,
                _MetadataChip(label: statusLabel),
              ],
            ),
            kOpenHandGap14,
            OpenHandMetadataEntryRow(
              label: _localizedMetadataField(
                context,
                'context_budget_estimated_prompt_tokens',
              ),
              value: '$estimatedTokens',
            ),
            OpenHandMetadataEntryRow(
              label: _localizedMetadataField(
                context,
                'context_budget_model_max_tokens',
              ),
              value: maxTokens > 0 ? '$maxTokens' : '-',
            ),
            OpenHandMetadataEntryRow(
              label: _localizedMetadataField(
                context,
                'context_budget_effective_window_tokens',
              ),
              value: effectiveWindowTokens > 0 ? '$effectiveWindowTokens' : '-',
            ),
            OpenHandMetadataEntryRow(
              label: _localizedMetadataField(
                context,
                'context_budget_auto_compact_threshold_tokens',
              ),
              value: autoCompactThresholdTokens > 0
                  ? '$autoCompactThresholdTokens'
                  : '-',
            ),
            OpenHandMetadataEntryRow(
              label: _localizedMetadataField(
                context,
                'context_budget_remaining_tokens',
              ),
              value: maxTokens > 0 ? '$remainingTokens' : '-',
            ),
            OpenHandMetadataEntryRow(
              label: _localizedMetadataField(
                context,
                'context_budget_percent_left',
              ),
              value: maxTokens > 0 ? '$percentLeft%' : '-',
            ),
            OpenHandMetadataEntryRow(
              label: _localizedMetadataField(
                context,
                'context_budget_usage_percent',
              ),
              value: maxTokens > 0 ? '$usagePercent%' : '-',
            ),
          ],
          if (cacheHitTrendWidgets.isNotEmpty) ...[
            if (estimatedTokens > 0) kOpenHandGap4,
            ...cacheHitTrendWidgets,
          ],
        ],
      ),
    ];
  }

  List<Widget> _buildCompactMemorySection(
    BuildContext context,
    Map<String, Object?> metadata,
  ) {
    final checkpoint = session.latestCompressionPoint;
    final rehydration = _metadataObjectMap(
      metadata['post_compact_rehydration'],
    );
    if (checkpoint == null && rehydration.isEmpty) {
      return const <Widget>[];
    }
    final sidecarPath = '${rehydration['session_memory_sidecar_path'] ?? ''}'
        .trim();
    final sidecarPresent =
        rehydration['session_memory_sidecar_present'] == true;
    final restoredFromSidecar =
        checkpoint?.metadata['restored_from_compact_memory_sidecar'] == true;
    final sidecarStatus = checkpoint == null
        ? openHandLocalizedText(context, zh: '未生成', en: 'Not Generated')
        : restoredFromSidecar
        ? openHandLocalizedText(context, zh: '已恢复', en: 'Restored')
        : sidecarPresent
        ? openHandLocalizedText(context, zh: '已登记', en: 'Registered')
        : openHandLocalizedText(
            context,
            zh: '等待下次 Prompt 刷新',
            en: 'Pending Prompt Refresh',
          );

    return <Widget>[
      kOpenHandGap16,
      OpenHandMetadataSection(
        title: openHandLocalizedText(
          context,
          zh: '压缩记忆 Sidecar',
          en: 'Compact Memory Sidecar',
        ),
        children: [
          OpenHandMetadataEntryRow(
            label: _localizedMetadataField(
              context,
              'compact_memory_sidecar_status',
            ),
            value: sidecarStatus,
          ),
          OpenHandMetadataEntryRow(
            label: _localizedMetadataField(
              context,
              'compact_memory_checkpoint_id',
            ),
            value: checkpoint?.id ?? '-',
          ),
          OpenHandMetadataEntryRow(
            label: _localizedMetadataField(
              context,
              'compact_memory_checkpoint_characters',
            ),
            value: checkpoint == null ? '-' : '${checkpoint.characterCount}',
          ),
          OpenHandMetadataEntryRow(
            label: _localizedMetadataField(
              context,
              'compact_memory_restored_from_sidecar',
            ),
            value: restoredFromSidecar
                ? openHandYesLabel(context)
                : openHandNoLabel(context),
          ),
          OpenHandMetadataEntryRow(
            label: _localizedMetadataField(
              context,
              'compact_memory_sidecar_path',
            ),
            value: sidecarPath.isEmpty ? '-' : sidecarPath,
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildPostCompactRehydrationSection(
    BuildContext context,
    Map<String, Object?> metadata,
  ) {
    final rehydration = _metadataObjectMap(
      metadata['post_compact_rehydration'],
    );
    if (rehydration.isEmpty) {
      return const <Widget>[];
    }
    final channels = _metadataStringList(rehydration['restored_channels']);
    final checkpointId = '${rehydration['checkpoint_message_id'] ?? ''}'.trim();
    final checkpointCreatedAt = '${rehydration['checkpoint_created_at'] ?? ''}'
        .trim();
    final active = rehydration['active'] == true;
    final runtimeToolCount = _metadataInt(rehydration['runtime_tool_count']);
    final builtinToolCount = _metadataInt(rehydration['builtin_tool_count']);
    final skillToolCount = _metadataInt(rehydration['skill_tool_count']);
    final mcpToolCount = _metadataInt(rehydration['mcp_tool_count']);
    final recentReadFileCount = _metadataInt(
      rehydration['recent_read_file_count'],
    );
    final invokedSkillCount = _metadataInt(rehydration['invoked_skill_count']);
    final mcpServerInstructionCount = _metadataInt(
      rehydration['mcp_server_instruction_count'],
    );
    final sessionStartHookCount = _metadataInt(
      rehydration['session_start_hook_count'],
    );
    final agentResultCount = _metadataInt(rehydration['agent_result_count']);
    final deferredBuiltinToolCount = _metadataInt(
      rehydration['deferred_builtin_tool_count'],
    );
    final agentTypeCount = _metadataInt(rehydration['agent_type_count']);

    return <Widget>[
      kOpenHandGap16,
      OpenHandMetadataSection(
        title: openHandLocalizedText(
          context,
          zh: '压缩后上下文恢复',
          en: 'Post-Compact Rehydration',
        ),
        children: [
          OpenHandMetadataEntryRow(
            label: _localizedMetadataField(context, 'post_compact_active'),
            value: active
                ? openHandLocalizedText(context, zh: '启用', en: 'Active')
                : openHandLocalizedText(context, zh: '未启用', en: 'Inactive'),
          ),
          OpenHandMetadataEntryRow(
            label: _localizedMetadataField(context, 'checkpoint_message_id'),
            value: checkpointId.isEmpty ? '-' : checkpointId,
          ),
          OpenHandMetadataEntryRow(
            label: _localizedMetadataField(context, 'checkpoint_created_at'),
            value: checkpointCreatedAt.isEmpty ? '-' : checkpointCreatedAt,
          ),
          OpenHandMetadataEntryRow(
            label: _localizedMetadataField(context, 'runtime_tool_count'),
            value:
                '$runtimeToolCount ($builtinToolCount builtin, $skillToolCount skill, $mcpToolCount MCP)',
          ),
          OpenHandMetadataEntryRow(
            label: _localizedMetadataField(context, 'restored_signal_counts'),
            value:
                'read_files=$recentReadFileCount, skills=$invokedSkillCount, mcp_instructions=$mcpServerInstructionCount, session_hooks=$sessionStartHookCount, agent_results=$agentResultCount, deferred_tools=$deferredBuiltinToolCount, agent_types=$agentTypeCount',
          ),
          kOpenHandGap2,
          Text(
            openHandLocalizedText(context, zh: '恢复通道', en: 'Restored Channels'),
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          kOpenHandGap10,
          if (channels.isEmpty)
            Text(
              openHandLocalizedText(context, zh: '暂无恢复通道。', en: 'No channels.'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: channels
                  .map((channel) => _MetadataChip(label: channel))
                  .toList(growable: false),
            ),
        ],
      ),
    ];
  }
}

List<MapEntry<String, Object?>> _visibleSessionMetadataEntries(
  AiSession session,
) {
  return session.metadata.entries
      .where((entry) {
        if (entry.key == kMachineTerminalMetadataKey) return false;
        if (session.templateId == 'harness_engineering' &&
            entry.key == 'harness_config') {
          return false;
        }
        if (session.templateId == 'programming_expert' &&
            entry.key == 'programming_expert_config') {
          return false;
        }
        if (session.templateId == 'web_reverse_expert' &&
            entry.key == 'web_reverse_config') {
          return false;
        }
        if (session.templateId == 'android_reverse_expert' &&
            entry.key == 'android_reverse_config') {
          return false;
        }
        return true;
      })
      .toList(growable: false);
}

Widget _buildMachineTerminalMetadataSection(
  BuildContext context,
  Map<String, Object?> metadata,
) {
  final defaults = _metadataObjectMap(metadata['terminal_defaults']);
  final capabilities = _metadataObjectMap(metadata['capabilities']);
  final ui = _metadataObjectMap(metadata['ui']);
  final runtime = _metadataObjectMap(metadata['runtime']);
  final activeTerminal = _metadataObjectMap(runtime['active_terminal']);
  final terminals = _metadataObjectList(runtime['terminals']);
  final toolNames = _metadataStringList(metadata['tool_names']);
  final status = optionalStringFromValue(runtime['status']);
  final activeTerminalId =
      optionalStringFromValue(runtime['active_terminal_id']) ??
      optionalStringFromValue(metadata['active_terminal_id']);
  final activeSize = _terminalSizeText(activeTerminal);
  final terminalCount = _metadataInt(runtime['terminal_count']);
  final colorScheme = Theme.of(context).colorScheme;

  return OpenHandMetadataSection(
    title: openHandLocalizedText(
      context,
      zh: '机器终端元数据',
      zhHant: '機器終端中繼資料',
      en: 'Machine Terminal Metadata',
    ),
    children: [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MetadataInfoTile(
            icon: Icons.terminal_rounded,
            label: openHandLocalizedText(
              context,
              zh: '运行状态',
              zhHant: '執行狀態',
              en: 'Status',
              fr: 'État',
              de: 'Status',
              ja: '状態',
            ),
            value: _machineTerminalStatusLabel(context, status),
            color: _machineTerminalStatusColor(colorScheme, status),
          ),
          _MetadataInfoTile(
            icon: Icons.tab_rounded,
            label: _homeTerminalsLabel(context),
            value: terminalCount > 0 ? '$terminalCount' : '${terminals.length}',
            color: colorScheme.primary,
          ),
          _MetadataInfoTile(
            icon: Icons.developer_board_rounded,
            label: openHandLocalizedText(
              context,
              zh: '当前终端',
              en: 'Active Terminal',
            ),
            value: activeTerminalId ?? '-',
            color: colorScheme.tertiary,
          ),
          _MetadataInfoTile(
            icon: Icons.aspect_ratio_rounded,
            label: openHandLocalizedText(context, zh: '终端尺寸', en: 'Size'),
            value: activeSize,
            color: colorScheme.secondary,
          ),
        ],
      ),
      kOpenHandGap14,
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(context, zh: '工作流', en: 'Workflow'),
        value: _metadataDisplayValue(metadata['workflow']),
      ),
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(context, zh: '渲染面板', en: 'Surface'),
        value: _metadataDisplayValue(metadata['surface']),
      ),
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(context, zh: '工作区 ID', en: 'Workspace ID'),
        value: _metadataDisplayValue(metadata['terminal_workspace_id']),
      ),
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(context, zh: '默认工作目录', en: 'Default CWD'),
        value: _metadataDisplayValue(metadata['default_working_directory']),
      ),
      OpenHandMetadataEntryRow(
        label: _homeCreatedAtLabel(context),
        value: _metadataDisplayValue(metadata['created_at']),
      ),
      OpenHandMetadataEntryRow(
        label: _homeUpdatedAtLabel(context),
        value: _metadataDisplayValue(metadata['updated_at']),
      ),
      if (activeTerminal.isNotEmpty)
        _MetadataStructuredValue(
          label: openHandLocalizedText(
            context,
            zh: '当前终端状态',
            en: 'Active Terminal',
          ),
          value: activeTerminal,
        ),
      if (defaults.isNotEmpty)
        _MetadataStructuredValue(
          label: openHandLocalizedText(
            context,
            zh: '终端默认参数',
            en: 'Terminal Defaults',
          ),
          value: defaults,
        ),
      if (capabilities.isNotEmpty) ...[
        kOpenHandGap4,
        _MetadataGroupLabel(
          label: openHandLocalizedText(context, zh: '终端能力', en: 'Capabilities'),
          detail: openHandLocalizedText(
            context,
            zh: 'AI 与用户在机器专家线程内可用的终端能力',
            en: 'Terminal capabilities available in this template',
          ),
        ),
        kOpenHandGap10,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: capabilities.entries
              .map(
                (entry) => _MetadataCapabilityChip(
                  label: _metadataFieldTitle(entry.key),
                  enabled: entry.value == true,
                ),
              )
              .toList(growable: false),
        ),
      ],
      if (ui.isNotEmpty)
        _MetadataStructuredValue(
          label: openHandLocalizedText(context, zh: '界面特性', en: 'UI Features'),
          value: ui,
        ),
      if (toolNames.isNotEmpty) ...[
        kOpenHandGap12,
        _MetadataGroupLabel(
          label: openHandLocalizedText(
            context,
            zh: '内建终端工具',
            en: 'Built-in Tools',
          ),
          detail: openHandLocalizedText(
            context,
            zh: '仅机器专家模板开放',
            en: 'Scoped to the machine expert template',
          ),
        ),
        kOpenHandGap10,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: toolNames
              .map((toolName) => _MetadataChip(label: toolName))
              .toList(growable: false),
        ),
      ],
      if (terminals.isNotEmpty) ...[
        kOpenHandGap12,
        _MetadataGroupLabel(
          label: openHandLocalizedText(
            context,
            zh: '运行中终端',
            en: 'Runtime Terminals',
          ),
          detail: openHandLocalizedText(
            context,
            zh: '轻量状态摘要，不包含终端输出正文',
            en: 'Lightweight status summaries without terminal output',
          ),
        ),
        kOpenHandGap10,
        ...terminals.asMap().entries.map(
          (entry) => _MachineTerminalMetadataCard(
            index: entry.key + 1,
            terminal: entry.value,
          ),
        ),
      ],
    ],
  );
}

Map<String, Object?> _metadataObjectMap(Object? rawValue) {
  return stringKeyedMapFromValue(rawValue);
}

String _metadataDisplayValue(Object? value) {
  if (value == null) return '-';
  if (value is String) return nonBlankStringOr(value, '-');
  if (value is num || value is bool) return '$value';
  if (value is DateTime) return value.toUtc().toIso8601String();
  return _metadataJsonEncode(value);
}

String _metadataJsonEncode(Object? value) {
  try {
    return prettyPrintJson(value);
  } catch (_) {
    return '${value ?? '-'}';
  }
}

String _metadataFieldTitle(String key) {
  const labels = <String, String>{
    'schema_version': 'Schema 版本',
    'template_id': '模板 ID',
    'surface': '渲染面板',
    'workflow': '工作流',
    'session_id': '会话 ID',
    'terminal_workspace_id': '终端工作区 ID',
    'active_terminal_id': '当前终端 ID',
    'default_working_directory': '默认工作目录',
    'created_at': '创建时间',
    'updated_at': '更新时间',
    'terminal_defaults': '终端默认参数',
    'capabilities': '终端能力',
    'ui': '界面特性',
    'tool_names': '内建终端工具',
    'runtime': '运行时',
    'status': '状态',
    'terminal_count': '终端数量',
    'active_terminal': '当前终端',
    'terminals': '终端列表',
    'terminal_id': '终端 ID',
    'identity': '终端身份',
    'shell': 'Shell',
    'working_directory': '工作目录',
    'rows': '行数',
    'columns': '列数',
    'max_rows': '最大行数',
    'max_columns': '最大列数',
    'scrollback_lines': '回滚行数',
    'command_timeout_ms': '命令超时',
    'command_poll_interval_ms': '命令轮询间隔',
    'max_retained_output_characters': '保留输出上限',
    'max_tool_output_characters': '工具输出上限',
    'output_characters': '输出字符数',
    'started_at': '启动时间',
    'pid': '进程 ID',
    'exit_code': '退出码',
    'error_message': '错误信息',
    'panel': '面板位置',
    'auto_scroll_to_bottom': '自动滚动到底部',
    'terminal_tabs': '终端标签',
    'status_bar': '状态栏',
    'metadata_bar': '元数据栏',
    'read': '读取终端',
    'write': '写入终端',
    'execute': '执行命令',
    'control': '控制终端',
    'resize': '调整尺寸',
    'multiple_terminals': '多终端',
    'duplicate_terminal': '复制终端',
    'interactive_input': '交互输入',
    'ansi_output': 'ANSI 输出',
    'shell_completion': 'Shell 补全',
    'formatted_command_output': '格式化命令输出',
    'marker_isolated_exec': '分隔标记执行',
    'status_inspection': '状态查看',
    'environment_metadata': '环境元数据',
    'native_keybindings': '原生快捷键',
    'smooth_auto_scroll': '丝滑自动滚动',
  };
  final normalized = key.trim();
  if (normalized.isEmpty) return '-';
  final direct = labels[normalized];
  if (direct != null) return direct;
  final words = normalized
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .split(RegExp(r'[_\-\s]+'))
      .where((part) => part.trim().isNotEmpty)
      .map((part) {
        final lower = part.toLowerCase();
        return lower.length <= 1
            ? lower.toUpperCase()
            : '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .toList(growable: false);
  return words.isEmpty ? normalized : words.join(' ');
}

String _terminalSizeText(Map<String, Object?> terminal) {
  final columns = _metadataInt(terminal['columns']);
  final rows = _metadataInt(terminal['rows']);
  if (columns <= 0 || rows <= 0) return '-';
  return '$columns×$rows';
}

String _machineTerminalStatusLabel(BuildContext context, String? status) {
  return switch (status) {
    'running' => openHandRunningLabel(context),
    'starting' => _homeStartingLabel(context),
    'stopped' => openHandStoppedLabel(context),
    'failed' => _homeFailedLabel(context),
    'idle' => openHandLocalizedText(context, zh: '空闲', en: 'Idle'),
    _ => openHandUnknownLabel(context),
  };
}

Color _machineTerminalStatusColor(ColorScheme colorScheme, String? status) {
  return switch (status) {
    'running' => colorScheme.primary,
    'starting' => colorScheme.tertiary,
    'stopped' => colorScheme.outline,
    'failed' => colorScheme.error,
    'idle' => colorScheme.secondary,
    _ => colorScheme.outline,
  };
}

bool _metadataIsShortScalar(Object? value) {
  if (value == null || value is num || value is bool) return true;
  if (value is String) {
    return value.trim().length <= 48 && !value.contains('\n');
  }
  return false;
}

Widget _buildMetadataStructuredNode(
  BuildContext context,
  Object? value, {
  int depth = 0,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final map = value is Map ? _metadataObjectMap(value) : null;
  if (map != null) {
    if (map.isEmpty) {
      return Text(
        '-',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (depth >= 3) {
      return _MetadataJsonPanel(content: _metadataJsonEncode(map));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.52),
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: map.entries
            .map((entry) {
              final childMap = entry.value is Map
                  ? _metadataObjectMap(entry.value)
                  : null;
              final childList = entry.value is List
                  ? entry.value as List
                  : null;
              if (childMap == null && childList == null) {
                return OpenHandMetadataEntryRow(
                  label: _metadataFieldTitle(entry.key),
                  value: _metadataDisplayValue(entry.value),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MetadataGroupLabel(label: _metadataFieldTitle(entry.key)),
                    kOpenHandGap8,
                    _buildMetadataStructuredNode(
                      context,
                      entry.value,
                      depth: depth + 1,
                    ),
                  ],
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  if (value is List) {
    if (value.isEmpty) {
      return Text(
        '-',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (value.every(_metadataIsShortScalar) && value.length <= 24) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: value
            .map((item) => _MetadataChip(label: _metadataDisplayValue(item)))
            .toList(growable: false),
      );
    }
    if (depth >= 3) {
      return _MetadataJsonPanel(content: _metadataJsonEncode(value));
    }
    final visibleItems = value.take(40).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...visibleItems.asMap().entries.map((entry) {
          final item = entry.value;
          final scalar = _metadataIsShortScalar(item) || item is String;
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.52),
              borderRadius: kOpenHandBorderRadius14,
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.42),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${entry.key + 1}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                kOpenHandGap8,
                scalar
                    ? SelectableText(
                        _metadataDisplayValue(item),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                        ),
                      )
                    : _buildMetadataStructuredNode(
                        context,
                        item,
                        depth: depth + 1,
                      ),
              ],
            ),
          );
        }),
        if (value.length > visibleItems.length)
          Text(
            openHandLocalizedText(
              context,
              zh: '还有 ${value.length - visibleItems.length} 项未展示，请复制完整元数据查看。',
              en: '${value.length - visibleItems.length} more items are hidden. Copy full metadata to inspect them.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  return SelectableText(
    _metadataDisplayValue(value),
    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
  );
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
        borderRadius: kOpenHandPillBorderRadius,
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

class _MetadataInfoTile extends StatelessWidget {
  const _MetadataInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: 188,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: kOpenHandBorderRadius12,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                kOpenHandGap4,
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataGroupLabel extends StatelessWidget {
  const _MetadataGroupLabel({required this.label, this.detail});

  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final detailText = detail?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (detailText != null && detailText.isNotEmpty) ...[
          kOpenHandGap3,
          Text(
            detailText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _MetadataCapabilityChip extends StatelessWidget {
  const _MetadataCapabilityChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = enabled ? colorScheme.primary : colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: enabled ? 0.12 : 0.08),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled ? Icons.check_rounded : Icons.remove_rounded,
            size: 15,
            color: color,
          ),
          kOpenHandHGap5,
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataStructuredValue extends StatelessWidget {
  const _MetadataStructuredValue({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _metadataFieldTitle(label),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          kOpenHandGap8,
          _buildMetadataStructuredNode(context, value),
        ],
      ),
    );
  }
}

class _MachineTerminalMetadataCard extends StatelessWidget {
  const _MachineTerminalMetadataCard({
    required this.index,
    required this.terminal,
  });

  final int index;
  final Map<String, Object?> terminal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = optionalStringFromValue(terminal['status']);
    final statusColor = _machineTerminalStatusColor(colorScheme, status);
    final id = optionalStringFromValue(terminal['terminal_id']) ?? '-';
    final identity = optionalStringFromValue(terminal['identity']) ?? '-';
    final size = _terminalSizeText(terminal);
    final outputCharacters = _metadataInt(terminal['output_characters']);
    final extraRows = <Widget>[
      OpenHandMetadataEntryRow(
        label: _metadataFieldTitle('shell'),
        value: _metadataDisplayValue(terminal['shell']),
      ),
      OpenHandMetadataEntryRow(
        label: _metadataFieldTitle('working_directory'),
        value: _metadataDisplayValue(terminal['working_directory']),
      ),
      OpenHandMetadataEntryRow(
        label: _metadataFieldTitle('started_at'),
        value: _metadataDisplayValue(terminal['started_at']),
      ),
      OpenHandMetadataEntryRow(
        label: _metadataFieldTitle('updated_at'),
        value: _metadataDisplayValue(terminal['updated_at']),
      ),
      if (terminal.containsKey('pid'))
        OpenHandMetadataEntryRow(
          label: _metadataFieldTitle('pid'),
          value: _metadataDisplayValue(terminal['pid']),
        ),
      if (terminal.containsKey('exit_code'))
        OpenHandMetadataEntryRow(
          label: _metadataFieldTitle('exit_code'),
          value: _metadataDisplayValue(terminal['exit_code']),
        ),
      if (optionalStringFromValue(terminal['error_message']) != null)
        OpenHandMetadataEntryRow(
          label: _metadataFieldTitle('error_message'),
          value: _metadataDisplayValue(terminal['error_message']),
        ),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
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
                '${_homeTerminalLabel(context)} #$index',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.13),
                  borderRadius: kOpenHandPillBorderRadius,
                ),
                child: Text(
                  _machineTerminalStatusLabel(context, status),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
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
              _MetadataChip(label: 'ID $id'),
              _MetadataChip(label: identity),
              _MetadataChip(
                label: size == '-'
                    ? openHandLocalizedText(context, zh: '尺寸 -', en: 'Size -')
                    : size,
              ),
              _MetadataChip(
                label:
                    '${openHandOutputLabel(context)} $outputCharacters ${openHandLocalizedText(context, zh: '字符', en: 'chars')}',
              ),
            ],
          ),
          kOpenHandGap12,
          ...extraRows,
        ],
      ),
    );
  }
}

String _sessionPlanStatusLabel(
  BuildContext context,
  AiSessionPlanStatus status,
) {
  return switch (status) {
    AiSessionPlanStatus.pendingApproval => AppLocalizations.of(
      context,
    )!.sessMetaPendingApproval,
    AiSessionPlanStatus.inProgress => AppLocalizations.of(
      context,
    )!.sessMetaInProgress,
    AiSessionPlanStatus.completed => AppLocalizations.of(
      context,
    )!.sessMetaCompleted,
    AiSessionPlanStatus.failed => AppLocalizations.of(context)!.sessMetaFailed,
    AiSessionPlanStatus.cancelled => AppLocalizations.of(
      context,
    )!.sessMetaCancelled,
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
        borderRadius: kOpenHandBorderRadius16,
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
                  borderRadius: kOpenHandPillBorderRadius,
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
          kOpenHandGap8,
          Text(
            '${AppLocalizations.of(context)!.sessMetaCreated} ${formatYearMonthDayHmLocal(planRecord.createdAt)} · ${AppLocalizations.of(context)!.sessMetaUpdated} ${formatYearMonthDayHmLocal(planRecord.updatedAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (planSummary.isNotEmpty && steps.isEmpty) ...[
            kOpenHandGap10,
            SelectableText(
              planSummary,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ],
          if (steps.isNotEmpty) ...[
            kOpenHandGap10,
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
        borderRadius: kOpenHandBorderRadius16,
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
          kOpenHandGap6,
          SelectableText(
            presentation.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onErrorContainer,
              height: 1.4,
            ),
          ),
          if (detail.isNotEmpty && detail != rawMessage) ...[
            kOpenHandGap8,
            Text(
              AppLocalizations.of(context)!.sessMetaErrorDetail,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onErrorContainer.withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
              ),
            ),
            kOpenHandGap4,
            SelectableText(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ],
          kOpenHandGap8,
          Text(
            '${_sessionErrorStageLabel(context, error.stage)} · ${formatYearMonthDayHmLocal(error.createdAt)} · ${error.hasBeenPresented ? AppLocalizations.of(context)!.sessMetaPresented : AppLocalizations.of(context)!.sessMetaPending}',
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
  if (StructuredErrorText.isStructured(rawMessage) &&
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
            : AppLocalizations.of(
                context,
              )!.sessMetaTheCurrentSequentialToolRoundLimit(configuredLimit);
        return AppLocalizations.of(
              context,
            )!.sessMetaOpenhandStoppedThisSessionForSafety +
            limitSuffix;
      }(),
    ),
    'chat_stream' => _SessionErrorPresentation(
      title: AppLocalizations.of(context)!.sessMetaResponseInterrupted,
      message: AppLocalizations.of(
        context,
      )!.sessMetaTheResponseWasInterruptedWhileStreaming,
    ),
    'chat_request' => _SessionErrorPresentation(
      title: AppLocalizations.of(context)!.sessMetaRequestFailed,
      message: AppLocalizations.of(
        context,
      )!.sessMetaTheRequestFailedBeforeTheAssistant,
    ),
    'chat_continuation_request' => _SessionErrorPresentation(
      title: AppLocalizations.of(context)!.sessMetaContinuationFailed,
      message: AppLocalizations.of(
        context,
      )!.sessMetaTheSessionFailedWhileRequestingThe,
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
  return optionalIntFromValue(match.group(1));
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
    'chat_continuation_request' => AppLocalizations.of(
      context,
    )!.sessMetaContinuationError,
    'tool_execution' => AppLocalizations.of(
      context,
    )!.sessMetaToolExecutionError,
    'history_compression' => AppLocalizations.of(
      context,
    )!.sessMetaCompressionError,
    'user_prompt_hook' => AppLocalizations.of(context)!.sessMetaPromptBlocked,
    'title_generation' => AppLocalizations.of(
      context,
    )!.sessMetaTitleGenerationError,
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
        borderRadius: kOpenHandBorderRadius18,
      ),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontFamily: kOpenHandMonospaceFontFamily,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _CacheHitSparklinePainter extends CustomPainter {
  _CacheHitSparklinePainter({
    required this.ratios,
    required this.progress,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.dotColor,
    this.altRatios,
    this.altLineColor,
    this.altDotColor,
    this.focusedIndex,
    this.focusGuideColor,
  });

  final List<double?> ratios;
  final List<double?>? altRatios;
  final double progress;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color dotColor;
  final Color? altLineColor;
  final Color? altDotColor;
  final int? focusedIndex;
  final Color? focusGuideColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (ratios.isEmpty) return;
    final w = size.width;
    final h = size.height;

    // 网格：25% / 50% / 75% 三条参考线。
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    for (final f in const <double>[0.25, 0.5, 0.75]) {
      final y = h - h * f;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    if (ratios.length < 2) return;
    final n = ratios.length;
    final stepX = w / (n - 1);

    // 焦点引导线（hover tooltip 时垂直高亮）。在曲线下方先画。
    final fi = focusedIndex;
    if (fi != null && fi >= 0 && fi < n && focusGuideColor != null) {
      final x = fi * stepX;
      final guidePaint = Paint()
        ..color = focusGuideColor!
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(x, 0), Offset(x, h), guidePaint);
    }

    _drawSeries(
      canvas: canvas,
      w: w,
      h: h,
      stepX: stepX,
      data: ratios,
      lineColor: lineColor,
      fillColor: fillColor,
      dotColor: dotColor,
      drawFill: true,
      focusedIndex: fi,
    );

    final alt = altRatios;
    if (alt != null && alt.length == n) {
      _drawSeries(
        canvas: canvas,
        w: w,
        h: h,
        stepX: stepX,
        data: alt,
        lineColor: altLineColor ?? lineColor,
        fillColor: null,
        dotColor: altDotColor ?? dotColor,
        drawFill: false,
        focusedIndex: fi,
      );
    }
  }

  void _drawSeries({
    required Canvas canvas,
    required double w,
    required double h,
    required double stepX,
    required List<double?> data,
    required Color lineColor,
    required Color? fillColor,
    required Color dotColor,
    required bool drawFill,
    required int? focusedIndex,
  }) {
    final n = data.length;
    final visibleCount = (n * progress).clamp(1, n).toDouble();
    final fullCount = visibleCount.floor();
    final partial = visibleCount - fullCount;

    // 把数据切成连续段，每段独立画线 + 可选填充。
    final segments = <List<Offset>>[];
    var current = <Offset>[];

    Offset? pointFor(int i) {
      final r = data[i];
      if (r == null) return null;
      final x = i * stepX;
      final y = h - h * r.clamp(0.0, 1.0);
      return Offset(x, y);
    }

    void flush() {
      if (current.isNotEmpty) {
        segments.add(List<Offset>.from(current));
      }
      current = <Offset>[];
    }

    for (var i = 0; i < fullCount && i < n; i++) {
      final p = pointFor(i);
      if (p == null) {
        flush();
        continue;
      }
      current.add(p);
    }
    if (partial > 0 && fullCount < n && fullCount >= 1) {
      final a = pointFor(fullCount - 1);
      final b = pointFor(fullCount);
      if (a != null && b != null) {
        final ip = Offset(
          a.dx + (b.dx - a.dx) * partial,
          a.dy + (b.dy - a.dy) * partial,
        );
        current.add(ip);
      }
    }
    flush();

    if (drawFill && fillColor != null) {
      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      for (final seg in segments) {
        if (seg.length < 2) continue;
        final path = Path()..moveTo(seg.first.dx, h);
        for (final p in seg) {
          path.lineTo(p.dx, p.dy);
        }
        path
          ..lineTo(seg.last.dx, h)
          ..close();
        canvas.drawPath(path, fillPaint);
      }
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final seg in segments) {
      if (seg.length < 2) continue;
      final path = Path()..moveTo(seg.first.dx, seg.first.dy);
      for (var i = 1; i < seg.length; i++) {
        path.lineTo(seg[i].dx, seg[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // 末点高亮（取最后一段的最后一个点）。
    if (segments.isNotEmpty) {
      final tail = segments.last;
      if (tail.isNotEmpty) {
        final dotPaint = Paint()..color = dotColor;
        canvas.drawCircle(tail.last, 2.6, dotPaint);
      }
    }

    // 焦点点突出显示。
    if (focusedIndex != null &&
        focusedIndex >= 0 &&
        focusedIndex < n &&
        focusedIndex < fullCount) {
      final p = pointFor(focusedIndex);
      if (p != null) {
        final ringPaint = Paint()
          ..color = dotColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;
        canvas.drawCircle(p, 4.0, ringPaint);
        canvas.drawCircle(p, 1.8, Paint()..color = dotColor);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CacheHitSparklinePainter old) {
    return old.progress != progress ||
        old.ratios.length != ratios.length ||
        old.lineColor != lineColor ||
        old.fillColor != fillColor ||
        old.altRatios?.length != altRatios?.length ||
        old.altLineColor != altLineColor ||
        old.focusedIndex != focusedIndex;
  }
}

/// 缓存命中率趋势图 (stateful)：
/// - 鼠标悬停 / 触屏点击曲线时显示 tooltip 标注该点的轮次序号与命中率
/// - 提供「叠加另一条协议公式」开关，将 Claude 与 OpenAI 两种公式同图对比
class _CacheHitTrendChart extends StatefulWidget {
  const _CacheHitTrendChart({
    required this.trend,
    required this.primaryClaudeStyle,
  });

  final SessionCacheHitTrend trend;
  final bool primaryClaudeStyle;

  @override
  State<_CacheHitTrendChart> createState() => _CacheHitTrendChartState();
}

class _CacheHitTrendChartState extends State<_CacheHitTrendChart> {
  bool _overlayOn = false;
  int? _focusedIndex;
  bool _focusScheduled = false;

  static const double _chartHeight = 56;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final motionDisabled = !openHandTickerMotionEnabled(context);

    // 同步收集 primary / alt 两条曲线;长度对齐,缺失点为 null。
    final primary = widget.trend.points
        .map((point) => point.hitRatio)
        .toList(growable: false);
    final alt = widget.trend.points
        .map((point) {
          final prompt = point.promptTokens;
          final read = point.cacheReadTokens;
          return computeCacheHitRatio(
            promptTokens: prompt,
            cacheReadTokens: read,
            cacheWriteTokens: point.cacheWriteTokens,
            claudeStyle: !widget.primaryClaudeStyle,
          );
        })
        .toList(growable: false);
    if (primary.length < 2) return const SizedBox.shrink();

    final primaryNonNull = primary.toList(growable: false);
    final last = primaryNonNull.last;
    final avg = primaryNonNull.reduce((a, b) => a + b) / primaryNonNull.length;
    final maxRatio = primaryNonNull.reduce((a, b) => a > b ? a : b);

    final headStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    );
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    String pct(double v) => '${(v * 100).round()}%';

    final primaryLabel = widget.primaryClaudeStyle
        ? l10n.sessMetaCacheHitFormulaClaude
        : l10n.sessMetaCacheHitFormulaOpenAi;
    final altLabel = widget.primaryClaudeStyle
        ? l10n.sessMetaCacheHitFormulaOpenAi
        : l10n.sessMetaCacheHitFormulaClaude;

    final altColor = colorScheme.tertiary;
    final ttlLabel = openHandLocalizedText(context, zh: 'TTL', en: 'TTL');
    final driftLabel = openHandLocalizedText(
      context,
      zh: '前缀漂移',
      en: 'Prefix drift',
    );
    final automaticProviderMissLabel = openHandLocalizedText(
      context,
      zh: '自动缓存低命中',
      en: 'Automatic cache miss',
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.sessMetaCacheHitTrend, style: headStyle),
              kOpenHandHGap8,
              _CacheHitLegendChip(
                color: colorScheme.primary,
                label: primaryLabel,
                solid: true,
              ),
              if (_overlayOn) ...[
                kOpenHandHGap6,
                _CacheHitLegendChip(
                  color: altColor,
                  label: altLabel,
                  solid: false,
                ),
              ],
              const Spacer(),
              Text(
                '${l10n.sessMetaCacheHitLast}: ${pct(last)}'
                ' · ${l10n.sessMetaCacheHitAvg}: ${pct(avg)}'
                ' · ${l10n.sessMetaCacheHitMax}: ${pct(maxRatio)}'
                ' · n=${primary.length}',
                style: valueStyle,
              ),
              kOpenHandHGap8,
              InkWell(
                onTap: () => setState(() => _overlayOn = !_overlayOn),
                borderRadius: kOpenHandBorderRadius8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    _overlayOn
                        ? l10n.sessMetaCacheHitOverlayOff
                        : l10n.sessMetaCacheHitOverlayOn,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
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
              _CacheHitDiagnosisChip(
                color: colorScheme.secondary,
                label:
                    '$ttlLabel × ${widget.trend.points.where((p) => p.ttlSuspected).length}',
              ),
              _CacheHitDiagnosisChip(
                color: colorScheme.error,
                label:
                    '$driftLabel × ${widget.trend.points.where((p) => p.prefixDriftSuspected).length}',
              ),
              _CacheHitDiagnosisChip(
                color: colorScheme.tertiary,
                label:
                    '$automaticProviderMissLabel × ${widget.trend.points.where((p) => p.automaticProviderMissSuspected).length}',
              ),
            ],
          ),
          kOpenHandGap10,
          SizedBox(
            height: _chartHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final n = primary.length;
                final stepX = n <= 1 ? width : width / (n - 1);

                void updateFocus(Offset local) {
                  if (n <= 1) return;
                  final raw = (local.dx / stepX).round();
                  final clamped = raw.clamp(0, n - 1).toInt();
                  if (_focusedIndex != clamped) {
                    _focusedIndex = clamped;
                    if (!_focusScheduled) {
                      _focusScheduled = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _focusScheduled = false;
                        if (mounted) setState(() {});
                      });
                    }
                  }
                }

                final fi = _focusedIndex;
                final tooltipChildren = <Widget>[];
                if (fi != null && fi >= 0 && fi < primary.length) {
                  final pv = primary[fi];
                  final av = _overlayOn && fi < alt.length ? alt[fi] : null;
                  final point = widget.trend.points[fi];
                  final tooltipX = (fi * stepX).clamp(0.0, width);

                  final label = StringBuffer()
                    ..write(l10n.sessMetaCacheHitPoint(fi + 1));
                  label
                    ..write('  ')
                    ..write(primaryLabel)
                    ..write(': ')
                    ..write(pct(pv));
                  if (av != null) {
                    label
                      ..write('  ')
                      ..write(altLabel)
                      ..write(': ')
                      ..write(pct(av));
                  }
                  if (point.ttlSuspected) {
                    label.write('  $ttlLabel');
                  } else if (point.prefixDriftSuspected) {
                    label.write('  $driftLabel');
                  } else if (point.automaticProviderMissSuspected) {
                    label.write('  $automaticProviderMissLabel');
                  }
                  tooltipChildren.add(
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment(
                            n <= 1 ? 0 : ((tooltipX / width) * 2 - 1),
                            -1,
                          ),
                          child: Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.inverseSurface.withValues(
                                alpha: 0.9,
                              ),
                              borderRadius: BorderRadius.circular(kOpenHandRadius6),
                            ),
                            child: Text(
                              label.toString(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onInverseSurface,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return MouseRegion(
                  onHover: (event) => updateFocus(event.localPosition),
                  onExit: (_) {
                    if (_focusedIndex != null) {
                      _focusedIndex = null;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() {});
                      });
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => updateFocus(d.localPosition),
                    onPanUpdate: (d) => updateFocus(d.localPosition),
                    onPanEnd: (_) {
                      if (_focusedIndex != null) {
                        _focusedIndex = null;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() {});
                        });
                      }
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: motionDisabled ? 1.0 : 0.0,
                              end: 1.0,
                            ),
                            duration: openHandMotionDuration(
                              context,
                              _kCacheHitTrendRevealDuration,
                            ),
                            curve: kOpenHandSwitchInCurve,
                            builder: (context, t, _) {
                              return CustomPaint(
                                painter: _CacheHitSparklinePainter(
                                  ratios: primary,
                                  altRatios: _overlayOn ? alt : null,
                                  progress: t,
                                  lineColor: colorScheme.primary,
                                  fillColor: colorScheme.primary.withValues(
                                    alpha: 0.18,
                                  ),
                                  gridColor: colorScheme.outlineVariant
                                      .withValues(alpha: 0.35),
                                  dotColor: colorScheme.primary,
                                  altLineColor: altColor,
                                  altDotColor: altColor,
                                  focusedIndex: _focusedIndex,
                                  focusGuideColor: colorScheme.outline
                                      .withValues(alpha: 0.45),
                                ),
                                size: Size.infinite,
                              );
                            },
                          ),
                        ),
                        ...tooltipChildren,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CacheHitDiagnosisChip extends StatelessWidget {
  const _CacheHitDiagnosisChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _CacheHitLegendChip extends StatelessWidget {
  const _CacheHitLegendChip({
    required this.color,
    required this.label,
    required this.solid,
  });

  final Color color;
  final String label;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: solid ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: solid ? null : Border.all(color: color, width: 1.4),
          ),
        ),
        kOpenHandHGap4,
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

part of 'openhand_home_page.dart';

class _SessionMetadataDialog extends StatelessWidget {
  const _SessionMetadataDialog({
    required this.session,
    this.liveRuntimeToolPreview,
  });

  final AiSession session;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;

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
        label: _localizedText(context, zh: '消息总数', en: 'Messages'),
        value: '${statistics.totalMessageCount}',
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: 'Prompt 构建', en: 'Prompt Builds'),
        value: '${statistics.promptBuildCount}',
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '压缩次数', en: 'Compressions'),
        value: '${statistics.compressionRunCount}',
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '总 Token', en: 'Total Tokens'),
        value: '${statistics.totalTokens ?? 0}',
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '当前模式', en: 'Mode'),
        value: _runtimeModeLabel(context, runtimeStatus, compact: true),
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '运行工具', en: 'Runtime Tools'),
        value: !runtimeStatus.supportsToolCalls
            ? '-'
            : runtimeStatus.hasSnapshot && !runtimeStatus.stale
            ? '${runtimeStatus.toolCount}'
            : _localizedText(context, zh: '待刷新', en: 'Pending'),
      ),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _localizedText(
                            context,
                            zh: '当前会话元数据',
                            en: 'Current Session Metadata',
                          ),
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
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '会话概览',
                          en: 'Session Overview',
                        ),
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
                                !(session.templateId ==
                                        'programming_expert' &&
                                    e.key == 'programming_expert_config'),
                          )
                          .isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _MetadataSection(
                          title: _localizedText(
                            context,
                            zh: '扩展元数据',
                            en: 'Extended Metadata',
                          ),
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
                        title: _localizedText(
                          context,
                          zh: '统计信息',
                          en: 'Statistics',
                        ),
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '用户', en: 'User')} ${statistics.userMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '助手', en: 'Assistant')} ${statistics.assistantMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '工具', en: 'Tool')} ${statistics.toolMessageCount}',
                              ),
                              _MetadataChip(
                                label: 'MCP ${statistics.mcpMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '技能', en: 'Skill')} ${statistics.skillMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '压缩', en: 'Compression')} ${statistics.compressionPointCount}',
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
                        title: _localizedText(
                          context,
                          zh: '运行环境',
                          en: 'Environment',
                        ),
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
                        title: _localizedText(
                          context,
                          zh: '命令策略',
                          en: 'Command Policy',
                        ),
                        children: !hasPromptMetadata
                            ? [
                                Text(
                                  _localizedText(
                                    context,
                                    zh: '当前还没有可展示的 prompt 元数据。',
                                    en: 'Prompt metadata is not available yet.',
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ]
                            : [
                                _MetadataEntryRow(
                                  label: _localizedText(
                                    context,
                                    zh: '写命令确认',
                                    en: 'Write Confirmation',
                                  ),
                                  value: writeCommandConfirmationEnabled
                                      ? _localizedText(
                                          context,
                                          zh: '需要确认',
                                          en: 'Required',
                                        )
                                      : _localizedText(
                                          context,
                                          zh: '无需确认',
                                          en: 'Not required',
                                        ),
                                ),
                                _MetadataEntryRow(
                                  label: _localizedText(
                                    context,
                                    zh: '允许规则数',
                                    en: 'Allow Rules',
                                  ),
                                  value: '$allowCommandRuleCount',
                                ),
                                if (allowCommandRules.isEmpty)
                                  Text(
                                    _localizedText(
                                      context,
                                      zh: '当前没有已上屏的允许命令规则。',
                                      en: 'There are no surfaced allow command rules.',
                                    ),
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
                        title: _localizedText(
                          context,
                          zh: '运行时编排',
                          en: 'Runtime Orchestration',
                        ),
                        children: [
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '状态来源',
                              en: 'State Source',
                            ),
                            value: runtimeStatus.isLivePreview
                                ? _localizedText(
                                    context,
                                    zh: '根据当前模型、MCP/Skills 与 Plan 状态即时生成',
                                    en: 'Generated from the current model, MCP/skills, and plan state',
                                  )
                                : _localizedText(
                                    context,
                                    zh: '上一轮已落盘的运行时快照',
                                    en: 'The last persisted runtime snapshot',
                                  ),
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '当前模式',
                              en: 'Mode',
                            ),
                            value: _runtimeModeLabel(context, runtimeStatus),
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '工具目录状态',
                              en: 'Tool Catalog State',
                            ),
                            value: _runtimeToolCatalogStatusLabel(
                              context,
                              runtimeStatus,
                            ),
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '门控原因',
                              en: 'Gate Reason',
                            ),
                            value: _runtimeToolGateReasonLabel(
                              context,
                              runtimeStatus.gateReason,
                            ),
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '当前运行时工具数',
                              en: 'Runtime Tool Count',
                            ),
                            value:
                                runtimeStatus.hasSnapshot &&
                                    !runtimeStatus.stale
                                ? '${runtimeStatus.toolCount}'
                                : _localizedText(
                                    context,
                                    zh: '等待下一轮刷新',
                                    en: 'Refreshes next round',
                                  ),
                          ),
                          if (runtimeStatus.notices.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              _localizedText(
                                context,
                                zh: '运行时 Notices',
                                en: 'Runtime Notices',
                              ),
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
                              _localizedText(
                                context,
                                zh: '当前运行时工具',
                                en: 'Current Runtime Tools',
                              ),
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
                        title: _localizedText(
                          context,
                          zh: '任务跟踪',
                          en: 'Task Tracking',
                        ),
                        children: [
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '当前 Todo 数量',
                              en: 'Current Todos',
                            ),
                            value: '${currentTodos.length}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '计划记录数量',
                              en: 'Plan Records',
                            ),
                            value: '${planHistory.length}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: 'TodoWrite 强提醒',
                              en: 'TodoWrite Reminder',
                            ),
                            value: hasPromptMetadata
                                ? (todoWriteRecommended
                                      ? _localizedText(
                                          context,
                                          zh: '已触发',
                                          en: 'Triggered',
                                        )
                                      : _localizedText(
                                          context,
                                          zh: '未触发',
                                          en: 'Not triggered',
                                        ))
                                : _localizedText(
                                    context,
                                    zh: '暂无数据',
                                    en: 'Unavailable',
                                  ),
                          ),
                          if (todoWriteReason.isNotEmpty)
                            _MetadataEntryRow(
                              label: _localizedText(
                                context,
                                zh: '提醒原因',
                                en: 'Reminder Reason',
                              ),
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
                              _localizedText(
                                context,
                                zh: '计划历史',
                                en: 'Plan History',
                              ),
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
                        title: _localizedText(
                          context,
                          zh: '最近异常',
                          en: 'Recent Errors',
                        ),
                        children: recentErrors.isEmpty
                            ? [
                                Text(
                                  _localizedText(
                                    context,
                                    zh: '当前没有需要关注的会话异常。',
                                    en: 'There are no session errors to review.',
                                  ),
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
                        title: _localizedText(
                          context,
                          zh: '最后一次 Prompt 元数据',
                          en: 'Last Prompt Metadata',
                        ),
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
                    label: _localizedText(context, zh: '关闭', en: 'Close'),
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
    AiSessionPlanStatus.pendingApproval => _localizedText(
      context,
      zh: '待确认',
      en: 'Pending Approval',
    ),
    AiSessionPlanStatus.inProgress => _localizedText(
      context,
      zh: '进行中',
      en: 'In Progress',
    ),
    AiSessionPlanStatus.completed => _localizedText(
      context,
      zh: '已完成',
      en: 'Completed',
    ),
    AiSessionPlanStatus.failed => _localizedText(
      context,
      zh: '失败',
      en: 'Failed',
    ),
    AiSessionPlanStatus.cancelled => _localizedText(
      context,
      zh: '已取消',
      en: 'Cancelled',
    ),
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
                _localizedText(
                  context,
                  zh: '计划 #$planIndex',
                  en: 'Plan #$planIndex',
                ),
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
            '${_localizedText(context, zh: '创建', en: 'Created')} ${_formatDateTime(planRecord.createdAt)} · ${_localizedText(context, zh: '更新', en: 'Updated')} ${_formatDateTime(planRecord.updatedAt)}',
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
              _localizedText(context, zh: '错误细节', en: 'Error Detail'),
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
            '${_sessionErrorStageLabel(context, error.stage)} · ${_formatDateTime(error.createdAt)} · ${error.hasBeenPresented ? _localizedText(context, zh: '已展示', en: 'Presented') : _localizedText(context, zh: '未展示', en: 'Pending')}',
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
      : _localizedText(
          context,
          zh: '当前会话已提前结束。请重试或继续发送更具体的指令。',
          en: 'This session ended early. Retry the request or continue with a more specific instruction.',
        );
  return switch (error.stage) {
    'tool_loop' => _SessionErrorPresentation(
      title: _localizedText(
        context,
        zh: '工具调用已安全停止',
        en: 'Tool Calls Stopped for Safety',
      ),
      message: () {
        final configuredLimit = _extractConfiguredToolLoopLimit(
          error.detail ?? '',
        );
        final limitSuffix = configuredLimit == null
            ? ''
            : _localizedText(
                context,
                zh: ' 当前连续工具轮次上限为 $configuredLimit。',
                en: ' The current sequential tool round limit is $configuredLimit.',
              );
        return _localizedText(
              context,
              zh: '本次会话连续触发了过多轮工具调用，OpenHand 已为安全起见提前停止。这次停止发生在会话控制层，并不是某个具体工具真的执行失败。你可以让助手先总结当前进展，或给出更具体的下一步指令。',
              en: 'OpenHand stopped this session for safety after too many sequential tool rounds. This stop happened in the session controller before the next tool could run, not because one specific tool execution failed. Ask the assistant to summarize the current progress or give a more specific next step.',
            ) +
            limitSuffix;
      }(),
    ),
    'chat_stream' => _SessionErrorPresentation(
      title: _localizedText(context, zh: '回答已中断', en: 'Response Interrupted'),
      message: _localizedText(
        context,
        zh: '本次回答在流式接收过程中异常中断，当前会话已停止。你可以直接重试，或继续发送下一条消息。',
        en: 'The response was interrupted while streaming and this session has stopped. Retry the request or continue with a new message.',
      ),
    ),
    'chat_request' => _SessionErrorPresentation(
      title: _localizedText(context, zh: '请求发送失败', en: 'Request Failed'),
      message: _localizedText(
        context,
        zh: '本次请求在发送阶段失败，当前会话未继续执行。你可以检查配置后重试，或继续发送新的消息。',
        en: 'The request failed before the assistant could continue. Check the configuration and retry, or send a new message.',
      ),
    ),
    'chat_continuation_request' => _SessionErrorPresentation(
      title: _localizedText(context, zh: '后续请求失败', en: 'Continuation Failed'),
      message: _localizedText(
        context,
        zh: '本次会话在继续执行后续步骤时，请求下一轮模型响应失败。已完成的步骤与工具结果都已保留，你可以直接回复继续/重试，或检查配置后再试。',
        en: 'The session failed while requesting the next assistant round after continuing execution. Completed steps and tool results were preserved. Reply with continue/retry, or check the configuration and try again.',
      ),
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

String _sessionErrorStageLabel(BuildContext context, String stage) {
  return switch (stage) {
    'tool_loop' => _localizedText(context, zh: '安全停止', en: 'Safety Stop'),
    'chat_stream' => _localizedText(context, zh: '响应中断', en: 'Stream Error'),
    'chat_request' => _localizedText(context, zh: '请求失败', en: 'Request Error'),
    'chat_continuation_request' => _localizedText(
      context,
      zh: '后续请求失败',
      en: 'Continuation Error',
    ),
    'tool_execution' => _localizedText(
      context,
      zh: '工具执行失败',
      en: 'Tool Execution Error',
    ),
    'history_compression' => _localizedText(
      context,
      zh: '历史压缩失败',
      en: 'Compression Error',
    ),
    'user_prompt_hook' => _localizedText(
      context,
      zh: '提示词被拦截',
      en: 'Prompt Blocked',
    ),
    'title_generation' => _localizedText(
      context,
      zh: '标题生成失败',
      en: 'Title Generation Error',
    ),
    _ => _localizedText(context, zh: '会话异常', en: 'Session Error'),
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


part of '../openhand_home_page.dart';

class _ThreadTemplateDialog extends StatelessWidget {
  const _ThreadTemplateDialog({required this.templates});

  final List<AiThreadTemplate> templates;
  static const double _dialogMaxWidth = 1080;
  static const double _dialogMaxHeight = 640;
  static const double _cardMinWidth = 220;
  static const double _cardMaxWidth = 300;
  static const double _gridSpacing = 16;
  static const double _dialogHorizontalInset = 48;
  static const double _dialogVerticalInset = 72;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = math
        .max(
          _cardMinWidth,
          math.min(_dialogMaxWidth, viewport.width - _dialogHorizontalInset),
        )
        .toDouble();
    final dialogHeight = math
        .max(
          360,
          math.min(_dialogMaxHeight, viewport.height - _dialogVerticalInset),
        )
        .toDouble();
    return buildOpenHandAlertDialog(
      title: Text(l10n.threadTemplateDialogTitle),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.threadTemplateDialogBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = _resolveCardWidth(constraints.maxWidth);
                  return Wrap(
                    spacing: _gridSpacing,
                    runSpacing: _gridSpacing,
                    children: templates
                        .map(
                          (template) => _ThreadTemplateCard(
                            template: template,
                            width: cardWidth,
                            onTap: () => Navigator.of(context).pop(template.id),
                          ),
                        )
                        .toList(growable: false),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
      ],
    );
  }

  double _resolveCardWidth(double availableWidth) {
    if (!availableWidth.isFinite || availableWidth <= _cardMinWidth) {
      return _cardMinWidth;
    }
    final columnCount = math.max(
      1,
      ((availableWidth + _gridSpacing) / (_cardMinWidth + _gridSpacing))
          .floor(),
    );
    final width =
        (availableWidth - _gridSpacing * (columnCount - 1)) / columnCount;
    return width.clamp(_cardMinWidth, _cardMaxWidth).toDouble();
  }
}

class _ThreadTemplateCard extends StatefulWidget {
  const _ThreadTemplateCard({
    required this.template,
    required this.onTap,
    this.width = 280,
  });

  final AiThreadTemplate template;
  final VoidCallback onTap;
  final double width;

  @override
  State<_ThreadTemplateCard> createState() => _ThreadTemplateCardState();
}

class _ThreadTemplateCardState extends State<_ThreadTemplateCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      width: widget.width,
      height: 300,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: _borderRadius18,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    widget.template.iconData,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(widget.template.name, style: theme.textTheme.titleMedium),
                Expanded(
                  child: OpenHandSafeScrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Text(
                        widget.template.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'v${widget.template.internalVersion}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

Widget _buildProgrammingExpertConfigSection(
  BuildContext context,
  AiSession session,
) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
  final sectionTitle = isZh ? '编程专家配置' : 'Programming Expert Config';
  final rawConfig = session.metadata['programming_expert_config'];

  final Map<String, Object?> configMap;
  if (rawConfig is Map<String, Object?>) {
    configMap = rawConfig;
  } else if (rawConfig is Map) {
    configMap = Map<String, Object?>.from(rawConfig);
  } else {
    return _MetadataSection(
      title: sectionTitle,
      children: [
        Text(
          isZh
              ? '配置数据尚未写入会话元数据。'
              : 'Configuration data has not been stored in session metadata.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  final projectRoot = '${configMap['project_root'] ?? ''}'.trim();
  final language = '${configMap['language'] ?? 'mixed'}'.trim();
  final sdkPath = OpenHandPaths.normalizeOptionalPath(
    '${configMap['sdk_path'] ?? ''}',
  );
  final lspPath = OpenHandPaths.normalizeOptionalPath(
    '${configMap['lsp_path'] ?? ''}',
  );
  return _MetadataSection(
    title: sectionTitle,
    children: [
      _MetadataEntryRow(
        label: isZh ? '项目根目录' : 'Project Root',
        value: projectRoot.isEmpty ? '-' : projectRoot,
      ),
      _MetadataEntryRow(
        label: isZh ? '项目语言' : 'Project Language',
        value: _programmingLanguageLabel(context, language),
      ),
      _MetadataEntryRow(
        label: isZh ? 'SDK 路径' : 'SDK Path',
        value: sdkPath.isEmpty ? '-' : OpenHandPaths.shortenHomePath(sdkPath),
      ),
      _MetadataEntryRow(
        label: isZh ? 'LSP 路径' : 'LSP Path',
        value: lspPath.isEmpty ? '-' : OpenHandPaths.shortenHomePath(lspPath),
      ),
    ],
  );
}

Widget _buildHardnessConfigSection(BuildContext context, AiSession session) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
  final sectionTitle = isZh
      ? 'Harness Engineering 配置'
      : 'Harness Engineering Config';
  final rawConfig = session.metadata['hardness_config'];

  final Map<String, Object?> configMap;
  if (rawConfig is Map<String, Object?>) {
    configMap = rawConfig;
  } else if (rawConfig is Map) {
    configMap = Map<String, Object?>.from(rawConfig);
  } else {
    return _MetadataSection(
      title: sectionTitle,
      children: [
        Text(
          isZh
              ? '配置数据尚未写入会话元数据（该会话可能创建于功能推出之前）。'
              : 'Configuration data has not been stored in session metadata (session may predate this feature).',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  HardnessRoleConfig? parseRole(String key) {
    final raw = configMap[key];
    if (raw is Map<String, Object?>) return HardnessRoleConfig.fromJson(raw);
    if (raw is Map) {
      return HardnessRoleConfig.fromJson(Map<String, Object?>.from(raw));
    }
    return null;
  }

  final task = '${configMap['task'] ?? ''}'.trim();
  final workingDirectory = '${configMap['working_directory'] ?? ''}'.trim();
  final persistenceDirectory = '${configMap['persistence_directory'] ?? ''}'
      .trim();
  final firstRunRaw = configMap['first_run'];

  final roleConfigs = <(String, HardnessRoleConfig?)>[
    (isZh ? '探档者 (Profiler)' : 'Profiler', parseRole('profiler')),
    (isZh ? '调查者 (Reader)' : 'Reader', parseRole('reader')),
    (isZh ? '规划者 (Planner)' : 'Planner', parseRole('planner')),
    (isZh ? '实施者 (Implementer)' : 'Implementer', parseRole('implementer')),
    (isZh ? '验收者 (Reviewer)' : 'Reviewer', parseRole('reviewer')),
  ];

  return _MetadataSection(
    title: sectionTitle,
    children: [
      if (task.isNotEmpty)
        _MetadataEntryRow(label: isZh ? '任务描述' : 'Task', value: task),
      _MetadataEntryRow(
        label: isZh ? '工作目录' : 'Working Directory',
        value: workingDirectory.isEmpty ? '-' : workingDirectory,
      ),
      _MetadataEntryRow(
        label: isZh ? '持久化目录' : 'Persistence Directory',
        value: persistenceDirectory.isEmpty ? '-' : persistenceDirectory,
      ),
      if (firstRunRaw != null)
        _MetadataEntryRow(
          label: isZh ? '首次运行' : 'First Run',
          value: firstRunRaw == true
              ? (isZh ? '是（含探档阶段）' : 'Yes (profiler phase included)')
              : (isZh ? '否（增量运行）' : 'No (incremental run)'),
        ),
      const SizedBox(height: 12),
      Text(
        isZh ? '角色配置' : 'Role Configs',
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      for (final entry in roleConfigs)
        _MetadataEntryRow(
          label: entry.$1,
          value: () {
            final rc = entry.$2;
            if (rc == null || !rc.isConfigured) {
              return isZh ? '未配置' : 'Not configured';
            }
            return '${rc.cliName} · ${describeHardnessCliModel(findHardnessCliByName(rc.cliName), rc.modelId, isZh: isZh)}';
          }(),
        ),
    ],
  );
}

String _localizedText(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  final languageCode = Localizations.localeOf(context).languageCode;
  return languageCode.startsWith('zh') ? zh : en;
}

Widget _buildWebReverseConfigSection(BuildContext context, AiSession session) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
  final sectionTitle = isZh ? 'Web 逆向配置' : 'Web Reverse Config';
  final config = WebReverseSessionConfig.fromJson(
    session.metadata['web_reverse_config'],
  );
  if (config == null) {
    return _MetadataSection(
      title: sectionTitle,
      children: [
        Text(
          isZh
              ? '配置数据尚未写入会话元数据。'
              : 'Configuration data has not been stored in session metadata.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
  return _MetadataSection(
    title: sectionTitle,
    children: [
      _MetadataEntryRow(
        label: isZh ? '目标 URL' : 'Target URL',
        value: config.targetUrl,
      ),
      _MetadataEntryRow(
        label: isZh ? '逆向目标' : 'Objective',
        value: config.objective,
      ),
      _MetadataEntryRow(
        label: isZh ? '浏览器' : 'Browser',
        value: config.browserKind.displayName,
      ),
      _MetadataEntryRow(label: 'CDP Port', value: '${config.cdpPort}'),
      _MetadataEntryRow(
        label: isZh ? '登录态' : 'Login Mode',
        value: isZh ? config.loginMode.label : config.loginMode.id,
      ),
      if (config.proxy != null && config.proxy!.isNotEmpty)
        _MetadataEntryRow(label: isZh ? '代理' : 'Proxy', value: config.proxy!),
      if (config.keywords.isNotEmpty)
        _MetadataEntryRow(
          label: isZh ? '关键关键字' : 'Keywords',
          value: config.keywords.join(', '),
        ),
      if (config.triggerActions != null && config.triggerActions!.isNotEmpty)
        _MetadataEntryRow(
          label: isZh ? '触发动作' : 'Trigger Actions',
          value: config.triggerActions!,
        ),
      _MetadataEntryRow(
        label: isZh ? 'Profile 目录' : 'User Data Dir',
        value: OpenHandPaths.shortenHomePath(config.userDataDir),
      ),
    ],
  );
}

Future<String?> _showEditQueuedMessageDialog(
  BuildContext context,
  String currentText,
) async {
  final languageCode = Localizations.localeOf(context).languageCode;
  final isZh = languageCode.startsWith('zh');
  return showOpenHandTextInputDialog(
    context: context,
    title: isZh ? '编辑等待消息' : 'Edit Queued Message',
    initialValue: currentText,
    hintText: isZh ? '输入消息内容…' : 'Enter message…',
    cancelLabel: isZh ? '取消' : 'Cancel',
    confirmLabel: isZh ? '保存' : 'Save',
    maxWidth: 480,
    minLines: 3,
    maxLines: 8,
    trimResult: false,
    decoration: InputDecoration(
      border: const OutlineInputBorder(),
      hintText: isZh ? '输入消息内容…' : 'Enter message…',
    ),
  );
}

String _localizedMetadataField(BuildContext context, String field) {
  return switch (field) {
    'session_id' => _localizedText(context, zh: '会话 ID', en: 'Session ID'),
    'template' => _localizedText(context, zh: '模板', en: 'Template'),
    'created_at' => _localizedText(context, zh: '创建时间', en: 'Created At'),
    'updated_at' => _localizedText(context, zh: '更新时间', en: 'Updated At'),
    'last_model' => _localizedText(context, zh: '最近模型', en: 'Last Model'),
    'auto_title_acquired' => _localizedText(
      context,
      zh: '标题获取状态',
      en: 'Title Acquired',
    ),
    'auto_title_retry_count' => _localizedText(
      context,
      zh: '标题重试次数',
      en: 'Title Retry Count',
    ),
    'compression_checkpoint' => _localizedText(
      context,
      zh: '压缩检查点',
      en: 'Compression Checkpoint',
    ),
    'latest_compression_at' => _localizedText(
      context,
      zh: '最近压缩时间',
      en: 'Latest Compression At',
    ),
    'total_input_characters' => _localizedText(
      context,
      zh: '输入字符总数',
      en: 'Total Input Characters',
    ),
    'total_output_characters' => _localizedText(
      context,
      zh: '输出字符总数',
      en: 'Total Output Characters',
    ),
    'total_prompt_characters' => _localizedText(
      context,
      zh: 'Prompt 字符总数',
      en: 'Total Prompt Characters',
    ),
    'last_prompt_system_message_count' => _localizedText(
      context,
      zh: '上次 Prompt 系统消息数',
      en: 'Last Prompt System Message Count',
    ),
    'last_prompt_history_message_count' => _localizedText(
      context,
      zh: '上次 Prompt 历史消息数',
      en: 'Last Prompt History Message Count',
    ),
    'context_budget_estimated_prompt_tokens' => _localizedText(
      context,
      zh: '估算 Prompt Token',
      en: 'Estimated Prompt Tokens',
    ),
    'context_budget_model_max_tokens' => _localizedText(
      context,
      zh: '模型上下文窗口',
      en: 'Model Context Window',
    ),
    'context_budget_effective_window_tokens' => _localizedText(
      context,
      zh: '有效上下文窗口',
      en: 'Effective Context Window',
    ),
    'context_budget_auto_compact_threshold_tokens' => _localizedText(
      context,
      zh: '自动压缩阈值',
      en: 'Auto-Compact Threshold',
    ),
    'context_budget_remaining_tokens' => _localizedText(
      context,
      zh: '估算剩余 Token',
      en: 'Estimated Remaining Tokens',
    ),
    'context_budget_percent_left' => _localizedText(
      context,
      zh: '距自动压缩剩余',
      en: 'Left Until Auto-Compact',
    ),
    'context_budget_usage_percent' => _localizedText(
      context,
      zh: '估算使用率',
      en: 'Estimated Usage',
    ),
    'compact_memory_sidecar_status' => _localizedText(
      context,
      zh: 'Sidecar 状态',
      en: 'Sidecar Status',
    ),
    'compact_memory_checkpoint_id' => _localizedText(
      context,
      zh: 'Checkpoint ID',
      en: 'Checkpoint ID',
    ),
    'compact_memory_checkpoint_characters' => _localizedText(
      context,
      zh: 'Checkpoint 字符数',
      en: 'Checkpoint Characters',
    ),
    'compact_memory_restored_from_sidecar' => _localizedText(
      context,
      zh: '从 Sidecar 恢复',
      en: 'Restored From Sidecar',
    ),
    'compact_memory_sidecar_path' => _localizedText(
      context,
      zh: 'Sidecar 路径',
      en: 'Sidecar Path',
    ),
    'locale_tag' => _localizedText(context, zh: '语言区域', en: 'Locale Tag'),
    'platform' => _localizedText(context, zh: '平台', en: 'Platform'),
    'app_version' => _localizedText(context, zh: '应用版本', en: 'App Version'),
    'compression_threshold_chars' => _localizedText(
      context,
      zh: '压缩阈值字符数',
      en: 'Compression Threshold Characters',
    ),
    'single_round_tool_call_limit' => _localizedText(
      context,
      zh: '单轮工具调用上限',
      en: 'Per-Response Tool Call Limit',
    ),
    'sequential_tool_round_limit' => _localizedText(
      context,
      zh: '连续工具轮次上限',
      en: 'Sequential Tool Round Limit',
    ),
    'application_directory' => _localizedText(
      context,
      zh: '应用目录',
      en: 'Application Directory',
    ),
    'home_directory' => _localizedText(
      context,
      zh: '主目录',
      en: 'Home Directory',
    ),
    'settings_file' => _localizedText(context, zh: '设置文件', en: 'Settings File'),
    'skills_storage' => _localizedText(
      context,
      zh: '技能目录',
      en: 'Skills Storage',
    ),
    'mcp_servers_file' => _localizedText(
      context,
      zh: 'MCP 文件',
      en: 'MCP Servers File',
    ),
    'user_memory_file' => _localizedText(
      context,
      zh: '记忆文件',
      en: 'User Memory File',
    ),
    'sessions_directory' => _localizedText(
      context,
      zh: '会话目录',
      en: 'Sessions Directory',
    ),
    _ => field,
  };
}

// ── Harness Engineering annotation parsing ───────────────────────────────────

final RegExp _heAgentPattern = RegExp(r'\[HE_AGENT:(\w+)\|([^\]]+)\]');
final RegExp _hePhasePattern = RegExp(r'\[HE_PHASE:(\w+)\]');

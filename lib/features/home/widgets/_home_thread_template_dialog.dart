part of '../openhand_home_page.dart';

class _ThreadTemplateDialog extends StatelessWidget {
  const _ThreadTemplateDialog({required this.templates});

  final List<AiThreadTemplate> templates;
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
    final dialogWidth = math.max(
      _cardMinWidth,
      math.min(
        kOpenHandDialogWidthPanel,
        viewport.width - _dialogHorizontalInset,
      ),
    );
    final dialogHeight = math
        .max(
          360,
          math.min(
            kOpenHandDialogHeightStandard,
            viewport.height - _dialogVerticalInset,
          ),
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
              kOpenHandGap18,
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
    return width.clamp(_cardMinWidth, _cardMaxWidth);
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
        borderRadius: BorderRadius.circular(kOpenHandRadius24),
        child: InkWell(
          borderRadius: BorderRadius.circular(kOpenHandRadius24),
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
                    borderRadius: kOpenHandBorderRadius18,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    widget.template.iconData,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                kOpenHandGap16,
                Text(widget.template.name, style: theme.textTheme.titleMedium),
                Expanded(
                  child: OpenHandSafeScrollbar(
                    controller: _scrollController,
                    thumbVisibility: false,
                    trackVisibility: false,
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
                kOpenHandGap14,
                Text(
                  widget.template.internalVersionLabel,
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

Widget _buildProgrammingExpertConfigSection(
  BuildContext context,
  AiSession session,
) {
  final sectionTitle = openHandLocalizedText(
    context,
    zh: '编程专家配置',
    zhHant: '程式專家設定',
    en: 'Programming Expert Config',
    fr: 'Configuration expert dev',
    de: 'Programmierexperten-Konfiguration',
    ja: 'プログラミング専門家設定',
  );
  final configMap = _threadTemplateMetadataMap(
    session,
    'programming_expert_config',
  );
  if (configMap == null) {
    return _buildMissingThreadTemplateConfigSection(context, sectionTitle);
  }

  final projectRoot = '${configMap['project_root'] ?? ''}'.trim();
  final language = '${configMap['language'] ?? 'mixed'}'.trim();
  final sdkPath = OpenHandPaths.normalizeOptionalPath(
    '${configMap['sdk_path'] ?? ''}',
  );
  final lspPath = OpenHandPaths.normalizeOptionalPath(
    '${configMap['lsp_path'] ?? ''}',
  );
  return OpenHandMetadataSection(
    title: sectionTitle,
    children: [
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(
          context,
          zh: '项目根目录',
          zhHant: '專案根目錄',
          en: 'Project Root',
          fr: 'Racine du projet',
          de: 'Projektstamm',
          ja: 'プロジェクトルート',
        ),
        value: projectRoot.isEmpty ? '-' : projectRoot,
      ),
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(
          context,
          zh: '项目语言',
          zhHant: '專案語言',
          en: 'Project Language',
          fr: 'Langage du projet',
          de: 'Projektsprache',
          ja: 'プロジェクト言語',
        ),
        value: _programmingLanguageLabel(context, language),
      ),
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(
          context,
          zh: 'SDK 路径',
          zhHant: 'SDK 路徑',
          en: 'SDK Path',
          fr: 'Chemin SDK',
          de: 'SDK-Pfad',
          ja: 'SDK パス',
        ),
        value: sdkPath.isEmpty ? '-' : OpenHandPaths.shortenHomePath(sdkPath),
      ),
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(
          context,
          zh: 'LSP 路径',
          zhHant: 'LSP 路徑',
          en: 'LSP Path',
          fr: 'Chemin LSP',
          de: 'LSP-Pfad',
          ja: 'LSP パス',
        ),
        value: lspPath.isEmpty ? '-' : OpenHandPaths.shortenHomePath(lspPath),
      ),
    ],
  );
}

Widget _buildHarnessConfigSection(BuildContext context, AiSession session) {
  final theme = Theme.of(context);
  final sectionTitle = openHandLocalizedText(
    context,
    zh: 'Harness Engineering 配置',
    zhHant: 'Harness Engineering 設定',
    en: 'Harness Engineering Config',
    fr: 'Configuration Harness Engineering',
    de: 'Harness-Engineering-Konfiguration',
    ja: 'Harness Engineering 設定',
  );
  final configMap = _threadTemplateMetadataMap(session, 'harness_config');
  if (configMap == null) {
    return _buildMissingThreadTemplateConfigSection(
      context,
      sectionTitle,
      includeLegacyHint: true,
    );
  }

  HarnessRoleConfig? parseRole(String key) {
    final raw = configMap[key];
    if (raw is Map<String, Object?>) return HarnessRoleConfig.fromJson(raw);
    if (raw is Map) {
      return HarnessRoleConfig.fromJson(stringKeyedMapFromValue(raw));
    }
    return null;
  }

  final task = '${configMap['task'] ?? ''}'.trim();
  final workingDirectory = '${configMap['working_directory'] ?? ''}'.trim();
  final persistenceDirectory = '${configMap['persistence_directory'] ?? ''}'
      .trim();
  final firstRunRaw = configMap['first_run'];

  final roleConfigs = <(String, HarnessRoleConfig?)>[
    (
      openHandLocalizedText(
        context,
        zh: '探档者 (Profiler)',
        zhHant: '探檔者 (Profiler)',
        en: 'Profiler',
        fr: 'Profiler',
        de: 'Profiler',
        ja: 'Profiler',
      ),
      parseRole('profiler'),
    ),
    (
      openHandLocalizedText(
        context,
        zh: '调查者 (Reader)',
        zhHant: '調查者 (Reader)',
        en: 'Reader',
        fr: 'Lecteur',
        de: 'Reader',
        ja: 'Reader',
      ),
      parseRole('reader'),
    ),
    (
      openHandLocalizedText(
        context,
        zh: '规划者 (Planner)',
        zhHant: '規劃者 (Planner)',
        en: 'Planner',
        fr: 'Planificateur',
        de: 'Planner',
        ja: 'Planner',
      ),
      parseRole('planner'),
    ),
    (
      openHandLocalizedText(
        context,
        zh: '实施者 (Implementer)',
        zhHant: '實作者 (Implementer)',
        en: 'Implementer',
        fr: 'Implémenteur',
        de: 'Implementer',
        ja: 'Implementer',
      ),
      parseRole('implementer'),
    ),
    (
      openHandLocalizedText(
        context,
        zh: '验收者 (Reviewer)',
        zhHant: '驗收者 (Reviewer)',
        en: 'Reviewer',
        fr: 'Relecteur',
        de: 'Reviewer',
        ja: 'Reviewer',
      ),
      parseRole('reviewer'),
    ),
  ];

  return OpenHandMetadataSection(
    title: sectionTitle,
    children: [
      if (task.isNotEmpty)
        OpenHandMetadataEntryRow(
          label: openHandTaskLabel(context),
          value: task,
        ),
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(
          context,
          zh: '工作目录',
          zhHant: '工作目錄',
          en: 'Working Directory',
          fr: 'Dossier de travail',
          de: 'Arbeitsverzeichnis',
          ja: '作業ディレクトリ',
        ),
        value: workingDirectory.isEmpty ? '-' : workingDirectory,
      ),
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(
          context,
          zh: '持久化目录',
          zhHant: '持久化目錄',
          en: 'Persistence Directory',
          fr: 'Dossier persistant',
          de: 'Persistenzverzeichnis',
          ja: '永続化ディレクトリ',
        ),
        value: persistenceDirectory.isEmpty ? '-' : persistenceDirectory,
      ),
      if (firstRunRaw != null)
        OpenHandMetadataEntryRow(
          label: openHandLocalizedText(
            context,
            zh: '首次运行',
            zhHant: '首次執行',
            en: 'First Run',
            fr: 'Premier lancement',
            de: 'Erster Lauf',
            ja: '初回実行',
          ),
          value: firstRunRaw == true
              ? openHandLocalizedText(
                  context,
                  zh: '是（含探档阶段）',
                  zhHant: '是（含探檔階段）',
                  en: 'Yes (profiler phase included)',
                  fr: 'Oui (phase profiler incluse)',
                  de: 'Ja (Profiler-Phase enthalten)',
                  ja: 'はい（Profiler フェーズを含む）',
                )
              : openHandLocalizedText(
                  context,
                  zh: '否（增量运行）',
                  zhHant: '否（增量執行）',
                  en: 'No (incremental run)',
                  fr: 'Non (exécution incrémentale)',
                  de: 'Nein (inkrementeller Lauf)',
                  ja: 'いいえ（増分実行）',
                ),
        ),
      kOpenHandGap12,
      Text(
        openHandLocalizedText(
          context,
          zh: '角色配置',
          zhHant: '角色設定',
          en: 'Role Configs',
          fr: 'Configurations de rôle',
          de: 'Rollenkonfigurationen',
          ja: 'ロール設定',
        ),
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      kOpenHandGap10,
      for (final entry in roleConfigs)
        OpenHandMetadataEntryRow(
          label: entry.$1,
          value: () {
            final rc = entry.$2;
            if (rc == null || !rc.isConfigured) {
              return openHandNotConfiguredLabel(context);
            }
            return '${rc.cliName} · ${describeHarnessCliModel(rc.modelId, locale: Localizations.localeOf(context))}';
          }(),
        ),
    ],
  );
}

Map<String, Object?>? _threadTemplateMetadataMap(
  AiSession session,
  String key,
) {
  final rawValue = session.metadata[key];
  return rawValue is Map ? stringKeyedMapFromValue(rawValue) : null;
}

Widget _buildMissingThreadTemplateConfigSection(
  BuildContext context,
  String title, {
  bool includeLegacyHint = false,
}) {
  final theme = Theme.of(context);
  return OpenHandMetadataSection(
    title: title,
    children: [
      Text(
        includeLegacyHint
            ? openHandLocalizedText(
                context,
                zh: '配置数据尚未写入会话元数据（该会话可能创建于功能推出之前）。',
                zhHant: '設定資料尚未寫入會話中繼資料（此會話可能早於此功能）。',
                en: 'Configuration data has not been stored in session metadata (session may predate this feature).',
                fr: 'Les données de configuration ne sont pas dans les métadonnées de session (session peut-être antérieure à cette fonction).',
                de: 'Konfigurationsdaten fehlen in den Sitzungsmetadaten (die Sitzung ist eventuell älter als diese Funktion).',
                ja: '設定データはセッションメタデータにありません（この機能以前のセッションの可能性があります）。',
              )
            : openHandLocalizedText(
                context,
                zh: '配置数据尚未写入会话元数据。',
                zhHant: '設定資料尚未寫入會話中繼資料。',
                en: 'Configuration data has not been stored in session metadata.',
                fr: 'Les données de configuration ne sont pas encore dans les métadonnées de session.',
                de: 'Konfigurationsdaten wurden noch nicht in den Sitzungsmetadaten gespeichert.',
                ja: '設定データはまだセッションメタデータに保存されていません。',
              ),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

Widget _buildWebReverseConfigSection(BuildContext context, AiSession session) {
  final sectionTitle = openHandLocalizedText(
    context,
    zh: 'Web 逆向配置',
    zhHant: 'Web 逆向設定',
    en: 'Web Reverse Config',
    fr: 'Configuration Web Reverse',
    de: 'Web-Reverse-Konfiguration',
    ja: 'Web Reverse 設定',
  );
  final config = WebReverseSessionConfig.fromJson(
    session.metadata['web_reverse_config'],
  );
  if (config == null) {
    return _buildMissingThreadTemplateConfigSection(context, sectionTitle);
  }
  return OpenHandMetadataSection(
    title: sectionTitle,
    children: [
      OpenHandMetadataEntryRow(
        label: openHandTargetUrlLabel(context),
        value: config.targetUrl,
      ),
      OpenHandMetadataEntryRow(
        label: openHandObjectiveLabel(context),
        value: config.objective,
      ),
      OpenHandMetadataEntryRow(
        label: openHandBrowserLabel(context),
        value: config.browserKind.displayName,
      ),
      OpenHandMetadataEntryRow(label: 'CDP Port', value: '${config.cdpPort}'),
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(
          context,
          zh: 'AI 侧 CDP MCP',
          zhHant: 'AI 側 CDP MCP',
          en: 'AI-side CDP MCP',
          fr: 'CDP MCP côté IA',
          de: 'AI-seitiges CDP MCP',
          ja: 'AI側 CDP MCP',
        ),
        value: config.cdpMcpEnabled
            ? openHandEnabledLabel(context)
            : openHandDisabledLabel(context),
      ),
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(
          context,
          zh: '登录态',
          zhHant: '登入狀態',
          en: 'Login Mode',
          fr: 'Mode de connexion',
          de: 'Login-Modus',
          ja: 'ログインモード',
        ),
        value: webReverseLoginModeLabel(context, config.loginMode),
      ),
      if (config.proxy != null && config.proxy!.isNotEmpty)
        OpenHandMetadataEntryRow(
          label: openHandProxyLabel(context),
          value: config.proxy!,
        ),
      if (config.keywords.isNotEmpty)
        OpenHandMetadataEntryRow(
          label: openHandKeywordsLabel(context),
          value: config.keywords.join(', '),
        ),
      if (config.triggerActions != null && config.triggerActions!.isNotEmpty)
        OpenHandMetadataEntryRow(
          label: openHandTriggerActionsLabel(context),
          value: config.triggerActions!,
        ),
      OpenHandMetadataEntryRow(
        label: openHandLocalizedText(
          context,
          zh: 'Profile 目录',
          zhHant: 'Profile 目錄',
          en: 'User Data Dir',
          fr: 'Dossier profil',
          de: 'Profildatenordner',
          ja: 'ユーザーデータディレクトリ',
        ),
        value: OpenHandPaths.shortenHomePath(config.userDataDir),
      ),
    ],
  );
}

Future<String?> _showEditQueuedMessageDialog(
  BuildContext context,
  String currentText,
) async {
  final hint = openHandLocalizedText(
    context,
    zh: '输入消息内容…',
    zhHant: '輸入訊息內容…',
    en: 'Enter message…',
    fr: 'Saisir le message…',
    de: 'Nachricht eingeben…',
    ja: 'メッセージを入力…',
  );
  return showOpenHandTextInputDialog(
    context: context,
    title: openHandLocalizedText(
      context,
      zh: '编辑等待消息',
      zhHant: '編輯等待訊息',
      en: 'Edit Queued Message',
      fr: 'Modifier le message en attente',
      de: 'Wartende Nachricht bearbeiten',
      ja: '待機中メッセージを編集',
    ),
    initialValue: currentText,
    hintText: hint,
    cancelLabel: openHandCancelLabel(context),
    confirmLabel: openHandSaveLabel(context),
    maxWidth: 480,
    minLines: 3,
    maxLines: 8,
    trimResult: false,
    decoration: InputDecoration(
      border: const OutlineInputBorder(),
      hintText: hint,
    ),
  );
}

String _localizedMetadataField(BuildContext context, String field) {
  return switch (field) {
    'session_id' => openHandSessionIdLabel(context),
    'template' => openHandTemplateLabel(context),
    'created_at' => _homeCreatedAtLabel(context),
    'updated_at' => _homeUpdatedAtLabel(context),
    'last_model' => openHandLocalizedText(
      context,
      zh: '最近模型',
      en: 'Last Model',
    ),
    'auto_title_acquired' => openHandLocalizedText(
      context,
      zh: '标题获取状态',
      en: 'Title Acquired',
    ),
    'auto_title_retry_count' => openHandLocalizedText(
      context,
      zh: '标题重试次数',
      en: 'Title Retry Count',
    ),
    'compression_checkpoint' => openHandLocalizedText(
      context,
      zh: '压缩检查点',
      en: 'Compression Checkpoint',
    ),
    'latest_compression_at' => openHandLocalizedText(
      context,
      zh: '最近压缩时间',
      en: 'Latest Compression At',
    ),
    'total_input_characters' => openHandLocalizedText(
      context,
      zh: '输入字符总数',
      en: 'Total Input Characters',
    ),
    'total_output_characters' => openHandLocalizedText(
      context,
      zh: '输出字符总数',
      en: 'Total Output Characters',
    ),
    'total_prompt_characters' => openHandLocalizedText(
      context,
      zh: 'Prompt 字符总数',
      en: 'Total Prompt Characters',
    ),
    'last_prompt_system_message_count' => openHandLocalizedText(
      context,
      zh: '上次 Prompt 系统消息数',
      en: 'Last Prompt System Message Count',
    ),
    'last_prompt_history_message_count' => openHandLocalizedText(
      context,
      zh: '上次 Prompt 历史消息数',
      en: 'Last Prompt History Message Count',
    ),
    'context_budget_estimated_prompt_tokens' => openHandLocalizedText(
      context,
      zh: '估算 Prompt Token',
      en: 'Estimated Prompt Tokens',
    ),
    'context_budget_model_max_tokens' => openHandLocalizedText(
      context,
      zh: '模型上下文窗口',
      en: 'Model Context Window',
    ),
    'context_budget_effective_window_tokens' => openHandLocalizedText(
      context,
      zh: '有效上下文窗口',
      en: 'Effective Context Window',
    ),
    'context_budget_auto_compact_threshold_tokens' => openHandLocalizedText(
      context,
      zh: '自动压缩阈值',
      en: 'Auto-Compact Threshold',
    ),
    'context_budget_remaining_tokens' => openHandLocalizedText(
      context,
      zh: '估算剩余 Token',
      en: 'Estimated Remaining Tokens',
    ),
    'context_budget_percent_left' => openHandLocalizedText(
      context,
      zh: '距自动压缩剩余',
      en: 'Left Until Auto-Compact',
    ),
    'context_budget_usage_percent' => openHandLocalizedText(
      context,
      zh: '估算使用率',
      en: 'Estimated Usage',
    ),
    'compact_memory_sidecar_status' => openHandLocalizedText(
      context,
      zh: 'Sidecar 状态',
      en: 'Sidecar Status',
    ),
    'compact_memory_checkpoint_id' => openHandLocalizedText(
      context,
      zh: 'Checkpoint ID',
      en: 'Checkpoint ID',
    ),
    'compact_memory_checkpoint_characters' => openHandLocalizedText(
      context,
      zh: 'Checkpoint 字符数',
      en: 'Checkpoint Characters',
    ),
    'compact_memory_restored_from_sidecar' => openHandLocalizedText(
      context,
      zh: '从 Sidecar 恢复',
      en: 'Restored From Sidecar',
    ),
    'compact_memory_sidecar_path' => openHandLocalizedText(
      context,
      zh: 'Sidecar 路径',
      en: 'Sidecar Path',
    ),
    'locale_tag' => openHandLocalizedText(
      context,
      zh: '语言区域',
      en: 'Locale Tag',
    ),
    'platform' => _homePlatformLabel(context),
    'app_version' => openHandLocalizedText(
      context,
      zh: '应用版本',
      en: 'App Version',
    ),
    'compression_threshold_chars' => openHandLocalizedText(
      context,
      zh: '压缩阈值字符数',
      en: 'Compression Threshold Characters',
    ),
    'single_round_tool_call_limit' => openHandLocalizedText(
      context,
      zh: '单轮工具调用上限',
      en: 'Per-Response Tool Call Limit',
    ),
    'sequential_tool_round_limit' => openHandLocalizedText(
      context,
      zh: '连续工具轮次上限',
      en: 'Sequential Tool Round Limit',
    ),
    'application_directory' => openHandLocalizedText(
      context,
      zh: '应用目录',
      en: 'Application Directory',
    ),
    'home_directory' => openHandLocalizedText(
      context,
      zh: '主目录',
      en: 'Home Directory',
    ),
    'settings_file' => openHandLocalizedText(
      context,
      zh: '设置文件',
      en: 'Settings File',
    ),
    'skills_storage' => openHandLocalizedText(
      context,
      zh: '技能目录',
      en: 'Skills Storage',
    ),
    'mcp_servers_file' => openHandLocalizedText(
      context,
      zh: 'MCP 文件',
      en: 'MCP Servers File',
    ),
    'user_memory_file' => openHandLocalizedText(
      context,
      zh: '记忆文件',
      en: 'User Memory File',
    ),
    'sessions_directory' => _homeSessionsDirectoryLabel(context),
    _ => field,
  };
}

// Harness Engineering 注解解析。

final RegExp _heAgentPattern = RegExp(r'\[HE_AGENT:(\w+)\|([^\]]+)\]');
final RegExp _hePhasePattern = RegExp(r'\[HE_PHASE:(\w+)\]');

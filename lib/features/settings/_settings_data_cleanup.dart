// ignore_for_file: prefer_const_constructors

part of 'settings_view.dart';

/// 2026-04-26 — 全局设置 → 应用数据 → 数据清理 UI section。
///
/// 这是一个独立的 [StatefulWidget]，自己持有 [DataCleanupService] 实例，
/// 在 [State.initState] 中触发首次异步测算，避免阻塞 settings 页面构建。
///
/// 重要原则：
/// - 任何"测算"和"清理"操作都通过 service 走 isolate / 异步路径；
/// - 操作期间禁用对应按钮，避免重复触发；
/// - 任何点击"清理"都会先弹出二次确认弹窗，弹窗使用 [showAnimatedDialog]
///   以与全局"弹窗动画设置"保持一致；
/// - 取消按钮与确认按钮均使用 [OpenHandDialogActionButton]，因此尺寸完全
///   相同（参见 `kOpenHandDialogActionButtonWidth/Height`）。
class _DataCleanupSection extends StatefulWidget {
  const _DataCleanupSection();

  @override
  State<_DataCleanupSection> createState() => _DataCleanupSectionState();
}

class _DataCleanupSectionState extends State<_DataCleanupSection> {
  late final DataCleanupService _service;
  bool _serviceReady = false;

  /// 每个分类的最近一次测算结果。`null` 表示尚未测算或正在测算中。
  final Map<DataCleanupCategory, DataCleanupSizeReport> _reports = {};

  /// 标记某个分类正在执行清理，用以禁用按钮。
  final Set<DataCleanupCategory> _cleaningCategories =
      <DataCleanupCategory>{};

  /// 标记某个分类正在执行测算，用以展示 progress 占位符。
  final Set<DataCleanupCategory> _measuringCategories =
      <DataCleanupCategory>{};

  /// 自增令牌：保护异步回调对应的 setState 不被旧请求覆盖。
  int _measureToken = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_serviceReady) {
      return;
    }
    _service = DataCleanupService(
      aiSessionController: context.read<AiSessionController>(),
      cronsController: context.read<CronsController>(),
      memoryController: context.read<MemoryController>(),
      mcpController: context.read<McpController>(),
      skillsController: context.read<SkillsController>(),
      settingsController: context.read<SettingsController>(),
    );
    _serviceReady = true;
    // 推迟到当前帧之后再触发测算：避免 didChangeDependencies 内部直接
    // setState 引发"build 期间 setState"告警（measure 回调里会 setState）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _measureAll();
    });
  }

  Future<void> _measureAll() async {
    final token = ++_measureToken;
    if (!mounted) return;
    setState(() {
      for (final c in DataCleanupCategory.values) {
        _measuringCategories.add(c);
      }
    });
    Future<void> measureOne(
      DataCleanupCategory category,
      Future<DataCleanupSizeReport> Function() task,
    ) async {
      DataCleanupSizeReport report;
      try {
        report = await task();
      } catch (error, stack) {
        silentLog(
          'data_cleanup',
          'measure/${category.name}',
          error,
          stack,
        );
        report = DataCleanupSizeReport.unknown;
      }
      if (!mounted || token != _measureToken) {
        return;
      }
      setState(() {
        _reports[category] = report;
        _measuringCategories.remove(category);
      });
    }

    // 并发跑：每个 isolate 工作互不依赖。
    await Future.wait(<Future<void>>[
      measureOne(DataCleanupCategory.multimedia, _service.measureMultimedia),
      measureOne(DataCleanupCategory.sessions, _service.measureSessions),
      measureOne(DataCleanupCategory.appCache, _service.measureAppCache),
      measureOne(DataCleanupCategory.logs, _service.measureLogs),
      measureOne(DataCleanupCategory.userMemory, _service.measureUserMemory),
      measureOne(DataCleanupCategory.mcpConfig, _service.measureMcpConfig),
      measureOne(
        DataCleanupCategory.skillsDirectory,
        _service.measureSkillsDirectory,
      ),
      measureOne(
        DataCleanupCategory.lspDirectory,
        _service.measureLspDirectory,
      ),
      measureOne(
        DataCleanupCategory.fileMutationLedger,
        _service.measureMutationLedger,
      ),
    ]);
    if (!mounted || token != _measureToken) {
      return;
    }
    // wipeAll 直接由各分支求和。
    final summed = DataCleanupCategory.values
        .where((c) => c != DataCleanupCategory.wipeAll)
        .map((c) => _reports[c] ?? DataCleanupSizeReport.empty)
        .fold<DataCleanupSizeReport>(
          DataCleanupSizeReport.empty,
          (acc, item) => acc + item,
        );
    setState(() {
      _reports[DataCleanupCategory.wipeAll] = summed;
      _measuringCategories.remove(DataCleanupCategory.wipeAll);
    });
  }

  Future<void> _onCleanPressed(DataCleanupCategory category) async {
    final l10n = AppLocalizations.of(context)!;
    final navigatorContext = context;
    final confirmed = await showAnimatedDialog<bool>(
      context: navigatorContext,
      builder: (dialogContext) => _DataCleanupConfirmDialog(
        title: _categoryTitle(dialogContext, category),
        body: _categoryConfirmBody(dialogContext, category),
        confirmLabel: _localizedText(
          dialogContext,
          zh: '清理',
          en: 'Clean',
        ),
        cancelLabel: l10n.commonCancel,
        isDestructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _cleaningCategories.add(category);
    });
    // 提前在 await 前抓取本地化文案，避免 use_build_context_synchronously
    // 警告（清理任务跨越异步边界，跨越后再用 context 拿 l10n 不安全）。
    final partialFailureTemplate = _localizedText(
      context,
      zh: '部分数据清理失败（{count} 个分类），剩余项已保留。',
      en:
          'Some data could not be cleaned ({count} categories). '
          'Remaining items were preserved.',
    );
    final genericFailureTemplate = _localizedText(
      context,
      zh: '清理失败：{error}',
      en: 'Clean failed: {error}',
    );
    final categoryTitle = _categoryTitle(context, category);
    final successText = _localizedText(
      context,
      zh: '已清理：$categoryTitle',
      en: 'Cleaned: $categoryTitle',
    );
    String? errorText;
    try {
      switch (category) {
        case DataCleanupCategory.multimedia:
          await _service.cleanMultimedia();
          break;
        case DataCleanupCategory.sessions:
          await _service.cleanSessions();
          break;
        case DataCleanupCategory.appCache:
          await _service.cleanAppCache();
          break;
        case DataCleanupCategory.logs:
          await _service.cleanLogs();
          break;
        case DataCleanupCategory.userMemory:
          await _service.cleanUserMemory();
          break;
        case DataCleanupCategory.mcpConfig:
          await _service.cleanMcpConfig();
          break;
        case DataCleanupCategory.skillsDirectory:
          await _service.cleanSkillsDirectory();
          break;
        case DataCleanupCategory.lspDirectory:
          await _service.cleanLspDirectory();
          break;
        case DataCleanupCategory.fileMutationLedger:
          await _service.cleanMutationLedger();
          break;
        case DataCleanupCategory.wipeAll:
          final errors = await _service.cleanAll();
          if (errors > 0) {
            errorText = partialFailureTemplate.replaceAll(
              '{count}',
              '$errors',
            );
          }
          break;
      }
    } catch (error, stack) {
      silentLog('data_cleanup', 'clean/${category.name}', error, stack);
      errorText = genericFailureTemplate.replaceAll('{error}', '$error');
    } finally {
      if (mounted) {
        setState(() {
          _cleaningCategories.remove(category);
        });
      }
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (errorText != null) {
      messenger?.showSnackBar(SnackBar(content: Text(errorText)));
    } else {
      messenger?.showSnackBar(SnackBar(content: Text(successText)));
    }
    // 重新测算，让 UI 反映最新体积。
    await _measureAll();
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSubsectionCard(
      title: _localizedText(context, zh: '数据清理', en: 'Data Cleanup'),
      description: _localizedText(
        context,
        zh:
            '所有体积测算与文件删除都在后台 worker 线程中执行，不会阻塞主线程；'
            '点击清理后将弹窗二次确认，确认操作不可撤销。',
        en:
            'Size measurement and file deletion run on background workers and '
            'never block the UI thread. A confirmation dialog appears before '
            'every cleanup; the action cannot be undone.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final category in DataCleanupCategory.values) ...[
            _DataCleanupRow(
              icon: _categoryIcon(category),
              title: _categoryTitle(context, category),
              subtitle: _categorySubtitle(context, category),
              report: _reports[category],
              isMeasuring: _measuringCategories.contains(category),
              isCleaning: _cleaningCategories.contains(category),
              isDestructive: category == DataCleanupCategory.wipeAll,
              onClean: () => _onCleanPressed(category),
            ),
            if (category != DataCleanupCategory.values.last)
              const Divider(height: 24),
          ],
          const SizedBox(height: 16),
          const _LedgerAdvancedControls(),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _measuringCategories.isNotEmpty ? null : _measureAll,
              icon: const Icon(Icons.refresh_outlined),
              label: Text(
                _localizedText(context, zh: '重新测算', en: 'Recalculate'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单行清理项 UI。左侧图标 + 标题 + 描述 + 大小展示，右侧清理按钮。
class _DataCleanupRow extends StatelessWidget {
  const _DataCleanupRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.report,
    required this.isMeasuring,
    required this.isCleaning,
    required this.isDestructive,
    required this.onClean,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final DataCleanupSizeReport? report;
  final bool isMeasuring;
  final bool isCleaning;
  final bool isDestructive;
  final VoidCallback onClean;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sizeText = isMeasuring || report == null
        ? _localizedText(context, zh: '测算中…', en: 'Measuring…')
        : formatHumanBytes(report!.bytes);
    final itemCount = report?.itemCount;
    final detailText = (isMeasuring || report == null)
        ? null
        : (itemCount != null && itemCount > 0
              ? _localizedText(
                  context,
                  zh: '$itemCount 项',
                  en: '$itemCount item${itemCount == 1 ? '' : 's'}',
                )
              : null);
    final canClean = !isCleaning &&
        !isMeasuring &&
        report != null &&
        (report!.bytes > 0 || (report!.itemCount ?? 0) > 0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 560;
        final infoColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: isDestructive
                      ? colorScheme.error
                      : colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (isMeasuring) ...[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                RollingText(
                  text: sizeText,
                  style: theme.textTheme.titleSmall!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDestructive
                        ? colorScheme.error
                        : colorScheme.primary,
                  ),
                ),
                if (detailText != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '· ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  RollingText(
                    text: detailText,
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
        // 用 ButtonStyle 锁住内边距 / 触控目标 / 文本样式，避免 M3 默认
        // FilledButton.icon 在外层 `SizedBox(height: 40)` 下会把 label
        // 挤出可视区（icon + 文本叠在一起，看起来"按钮文本不见了"）。
        final buttonStyle = FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(112, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
          textStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ).copyWith(
          backgroundColor: isDestructive
              ? WidgetStateProperty.resolveWith<Color?>((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return colorScheme.error.withValues(alpha: 0.32);
                  }
                  return colorScheme.error;
                })
              : null,
          foregroundColor: isDestructive
              ? WidgetStateProperty.resolveWith<Color?>((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return colorScheme.onError.withValues(alpha: 0.7);
                  }
                  return colorScheme.onError;
                })
              : null,
        );
        final cleanIcon = isCleaning
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDestructive
                      ? colorScheme.onError
                      : colorScheme.primary,
                ),
              )
            : Icon(
                isDestructive
                    ? Icons.delete_forever_outlined
                    : Icons.cleaning_services_outlined,
                size: 18,
              );
        final cleanLabel = Text(
          isDestructive
              ? _localizedText(context, zh: '一键清空', en: 'Wipe All')
              : _localizedText(context, zh: '清理', en: 'Clean'),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
        );
        // 不再外包 `SizedBox(height: 40)`：让按钮按 ButtonStyle 自己选定
        // intrinsic 高度（约 40~44），不会再压缩 label。
        final cleanButton = isDestructive
            ? FilledButton.icon(
                onPressed: canClean ? onClean : null,
                style: buttonStyle,
                icon: cleanIcon,
                label: cleanLabel,
              )
            : FilledButton.tonalIcon(
                onPressed: canClean ? onClean : null,
                style: buttonStyle,
                icon: cleanIcon,
                label: cleanLabel,
              );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              infoColumn,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: cleanButton),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: infoColumn),
            const SizedBox(width: 16),
            cleanButton,
          ],
        );
      },
    );
  }
}

/// 数据清理二次确认弹窗。复用 [showAnimatedDialog] 因此进/出动画与
/// "全局设置 → 弹窗动画设置"保持一致；按钮使用 [OpenHandDialogActionButton]，
/// 因此取消与确认尺寸完全相同。
class _DataCleanupConfirmDialog extends StatelessWidget {
  const _DataCleanupConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.isDestructive,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    isDestructive
                        ? Icons.warning_amber_outlined
                        : Icons.delete_outline,
                    color: isDestructive
                        ? colorScheme.error
                        : colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(body, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    label: cancelLabel,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 12),
                  OpenHandDialogActionButton.primary(
                    label: confirmLabel,
                    onPressed: () => Navigator.of(context).pop(true),
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

IconData _categoryIcon(DataCleanupCategory category) {
  switch (category) {
    case DataCleanupCategory.multimedia:
      return Icons.image_outlined;
    case DataCleanupCategory.sessions:
      return Icons.forum_outlined;
    case DataCleanupCategory.appCache:
      return Icons.dns_outlined;
    case DataCleanupCategory.logs:
      return Icons.receipt_long_outlined;
    case DataCleanupCategory.userMemory:
      return Icons.psychology_outlined;
    case DataCleanupCategory.mcpConfig:
      return Icons.cable_outlined;
    case DataCleanupCategory.skillsDirectory:
      return Icons.auto_awesome_outlined;
    case DataCleanupCategory.lspDirectory:
      return Icons.code_outlined;
    case DataCleanupCategory.fileMutationLedger:
      return Icons.history_rounded;
    case DataCleanupCategory.wipeAll:
      return Icons.delete_sweep_outlined;
  }
}

String _categoryTitle(BuildContext context, DataCleanupCategory category) {
  switch (category) {
    case DataCleanupCategory.multimedia:
      return _localizedText(context, zh: '多媒体数据', en: 'Multimedia Data');
    case DataCleanupCategory.sessions:
      return _localizedText(context, zh: '会话数据', en: 'Sessions');
    case DataCleanupCategory.appCache:
      return _localizedText(context, zh: '应用缓存', en: 'App Cache');
    case DataCleanupCategory.logs:
      return _localizedText(context, zh: '日志数据', en: 'Logs');
    case DataCleanupCategory.userMemory:
      return _localizedText(context, zh: '用户记忆', en: 'User Memory');
    case DataCleanupCategory.mcpConfig:
      return _localizedText(context, zh: 'MCP 配置', en: 'MCP Config');
    case DataCleanupCategory.skillsDirectory:
      return _localizedText(context, zh: '技能目录', en: 'Skills Directory');
    case DataCleanupCategory.lspDirectory:
      return _localizedText(context, zh: 'LSP 安装目录', en: 'LSP Install Dir');
    case DataCleanupCategory.fileMutationLedger:
      return _localizedText(context, zh: '文件变动历史', en: 'File Mutation Ledger');
    case DataCleanupCategory.wipeAll:
      return _localizedText(context, zh: '全部数据', en: 'All Data');
  }
}

String _categorySubtitle(
  BuildContext context,
  DataCleanupCategory category,
) {
  switch (category) {
    case DataCleanupCategory.multimedia:
      return _localizedText(
        context,
        zh: '会话附件（图片、文档等）。清理后历史消息中的附件会显示为缺失。',
        en:
            'Session attachments (images, documents). After cleanup, '
            'attachments in older messages will appear as missing.',
      );
    case DataCleanupCategory.sessions:
      return _localizedText(
        context,
        zh: '所有 AI 会话与消息（含旧版 JSON）。清理后会话列表会被清空。',
        en:
            'All AI sessions and messages (including legacy JSON). The '
            'session list will be empty after cleanup.',
      );
    case DataCleanupCategory.appCache:
      return _localizedText(
        context,
        zh: '~/.openhand/cache/ 目录下的临时缓存文件。',
        en: 'Temporary cache files under ~/.openhand/cache/.',
      );
    case DataCleanupCategory.logs:
      return _localizedText(
        context,
        zh: 'cron 执行历史 + ~/.openhand/logs/ 目录。',
        en: 'Cron execution history + the ~/.openhand/logs/ directory.',
      );
    case DataCleanupCategory.userMemory:
      return _localizedText(
        context,
        zh: '用户画像与所有用户记忆条目。清理后自学习子 Agent 会重新累积。',
        en:
            'User profile + all user memory entries. The self-learning '
            'sub-agent will gradually rebuild them.',
      );
    case DataCleanupCategory.mcpConfig:
      return _localizedText(
        context,
        zh: '已配置的 MCP Server 列表（JSON 文件）。清理后 MCP 列表会变空。',
        en:
            'Configured MCP Server list (JSON file). The MCP list will be '
            'empty after cleanup.',
      );
    case DataCleanupCategory.skillsDirectory:
      return _localizedText(
        context,
        zh: '当前技能目录下的全部文件。包含用户自定义的技能内容，请谨慎操作。',
        en:
            'All files under the current skills directory. User-authored '
            'skills are included; proceed with caution.',
      );
    case DataCleanupCategory.lspDirectory:
      return _localizedText(
        context,
        zh: '~/.openhand/lsp/ 目录下托管下载的 LSP 二进制。下次需要时会自动重装。',
        en:
            'Managed LSP binaries under ~/.openhand/lsp/. They will be '
            'reinstalled on next use.',
      );
    case DataCleanupCategory.fileMutationLedger:
      return _localizedText(
        context,
        zh:
            '~/.openhand/file_history/ 下的文件变动 ledger（before/after 快照 + jsonl '
            '记录）。清理后历史卡片可能不再展示可撤销状态。',
        en:
            'File mutation ledger under ~/.openhand/file_history/ (before/'
            'after blobs + jsonl). After cleanup, historical cards may no '
            'longer expose undo controls.',
      );
    case DataCleanupCategory.wipeAll:
      return _localizedText(
        context,
        zh:
            '一次性清理上述所有分类的数据。不会删除 sqlite 数据库文件本身或'
            ' settings.json，否则会让正在运行的进程崩溃；如需彻底重置，请手动'
            '删除 ~/.openhand。',
        en:
            'Cleans every category above in one shot. The sqlite DB file and '
            'settings.json are not removed (would crash the running '
            'process); remove ~/.openhand manually for a full reset.',
      );
  }
}

String _categoryConfirmBody(
  BuildContext context,
  DataCleanupCategory category,
) {
  final detail = _categorySubtitle(context, category);
  return _localizedText(
    context,
    zh: '确认清理「${_categoryTitle(context, category)}」？\n\n$detail\n\n该操作无法撤销。',
    en:
        'Clean "${_categoryTitle(context, category)}"?\n\n$detail\n\n'
        'This action cannot be undone.',
  );
}

/// 文件变动 ledger 的高级配置：每文件最多保留 N 条 + N 天前自动清理。
/// 配置走 ledger 自身的 `<root>/config.json`，不进入 SettingsController。
class _LedgerAdvancedControls extends StatefulWidget {
  const _LedgerAdvancedControls();

  @override
  State<_LedgerAdvancedControls> createState() =>
      _LedgerAdvancedControlsState();
}

class _LedgerAdvancedControlsState extends State<_LedgerAdvancedControls> {
  final AiFileMutationLedger _ledger = AiFileMutationLedger();
  LedgerConfig? _config;
  LedgerStatsSnapshot? _stats;
  Timer? _saveDebounce;
  bool _pruneNowBusy = false;
  ({int removed, int bytesFreed})? _lastGcStats;

  @override
  void initState() {
    super.initState();
    _ledger.loadConfig().then((c) {
      if (!mounted) return;
      setState(() => _config = c);
    });
    _refreshStats();
  }

  Future<void> _refreshStats() async {
    final stats = await _ledger.statsSnapshot();
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  /// 阶段 ⑦d：手动触发一次 ledger 维护——按当前 days/maxVersions 立刻
  /// 跑一遍 prune，刷新统计。期间禁用按钮 + 显示进度。
  /// 阶段 ⑫c：追加一次 GC 并展示 freed blobs 数量与字节数。
  Future<void> _pruneNow() async {
    final cfg = _config;
    if (cfg == null) return;
    setState(() => _pruneNowBusy = true);
    try {
      if (cfg.autoCleanupDays > 0) {
        await _ledger.pruneOlderThan(Duration(days: cfg.autoCleanupDays));
      }
      if (cfg.maxVersionsPerFile > 0) {
        await _ledger.pruneToMaxVersionsPerFile(cfg.maxVersionsPerFile);
      }
      final gc = await _ledger.gcUnreferencedBlobs();
      if (mounted) {
        setState(() => _lastGcStats = gc);
      }
      await _refreshStats();
    } finally {
      if (mounted) setState(() => _pruneNowBusy = false);
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _scheduleSave(LedgerConfig next) {
    setState(() => _config = next);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () async {
      await _ledger.saveConfig(next);
      if (!mounted) return;
      // 配置变更可能触发后续清理；顺手刷新一次统计。
      await _refreshStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = _config;
    if (config == null) {
      return SizedBox(
        height: 64,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                _localizedText(context,
                    zh: '文件变动历史 — 高级控制', en: 'File Mutation Ledger — Advanced'),
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_stats != null)
                Text(
                  _localizedText(context,
                      zh: '${_stats!.sessionCount} 会话 · '
                          '${_stats!.recordCount} 条 · '
                          '${_stats!.blobCount} blobs',
                      en: '${_stats!.sessionCount} sessions · '
                          '${_stats!.recordCount} records · '
                          '${_stats!.blobCount} blobs'),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _SliderRow(
            label: _localizedText(context,
                zh: '每文件最多保留 N 条历史',
                en: 'Max versions per file'),
            valueText: config.maxVersionsPerFile == 0
                ? _localizedText(context, zh: '不限制', en: 'Unlimited')
                : '${config.maxVersionsPerFile}',
            value: config.maxVersionsPerFile.toDouble(),
            min: LedgerConfig.minMaxVersionsPerFile.toDouble(),
            max: LedgerConfig.maxMaxVersionsPerFile.toDouble(),
            divisions: LedgerConfig.maxMaxVersionsPerFile,
            onChanged: (v) => _scheduleSave(
                config.copyWith(maxVersionsPerFile: v.round())),
          ),
          _SliderRow(
            label: _localizedText(context,
                zh: 'N 天前的历史自动清理（启动时）',
                en: 'Auto-cleanup older than N days (on launch)'),
            valueText: config.autoCleanupDays == 0
                ? _localizedText(context, zh: '关闭', en: 'Disabled')
                : _localizedText(context,
                    zh: '${config.autoCleanupDays} 天',
                    en: '${config.autoCleanupDays} days'),
            value: config.autoCleanupDays.toDouble(),
            min: LedgerConfig.minAutoCleanupDays.toDouble(),
            max: LedgerConfig.maxAutoCleanupDays.toDouble(),
            divisions: LedgerConfig.maxAutoCleanupDays,
            onChanged: (v) => _scheduleSave(
                config.copyWith(autoCleanupDays: v.round())),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _pruneNowBusy ? null : _pruneNow,
              icon: _pruneNowBusy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.primary),
                    )
                  : Icon(Icons.cleaning_services_rounded,
                      size: 16, color: cs.primary),
              label: Text(_localizedText(context,
                  zh: '立即清理超期', en: 'Prune now')),
            ),
          ),
          if (_lastGcStats != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _localizedText(context,
                    zh:
                        '上次 GC 释放 ${_lastGcStats!.removed} 个 blob · ${formatHumanBytes(_lastGcStats!.bytesFreed)}',
                    en:
                        'Last GC freed ${_lastGcStats!.removed} blob(s) · ${formatHumanBytes(_lastGcStats!.bytesFreed)}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 12),
              Text(valueText, style: theme.textTheme.labelMedium),
            ],
          ),
          SizedBox(
            height: 28,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions <= 0 ? null : divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

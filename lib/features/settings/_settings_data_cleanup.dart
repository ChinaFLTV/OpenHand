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
                Text(
                  sizeText,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDestructive
                        ? colorScheme.error
                        : colorScheme.primary,
                  ),
                ),
                if (detailText != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '· $detailText',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
        final cleanButton = SizedBox(
          height: 40,
          child: isDestructive
              ? FilledButton.icon(
                  onPressed: canClean ? onClean : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                  ),
                  icon: isCleaning
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onError,
                          ),
                        )
                      : const Icon(Icons.delete_forever_outlined, size: 18),
                  label: Text(
                    _localizedText(context, zh: '一键清空', en: 'Wipe All'),
                  ),
                )
              : FilledButton.tonalIcon(
                  onPressed: canClean ? onClean : null,
                  icon: isCleaning
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        )
                      : const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: Text(
                    _localizedText(context, zh: '清理', en: 'Clean'),
                  ),
                ),
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
    case DataCleanupCategory.wipeAll:
      return _localizedText(
        context,
        zh:
            '一次性清理上述所有分类的数据。**不会**删除应用配置、用户记忆与'
            '已下载的 LSP / MCP 配置；如需彻底重置，请手动删除 ~/.openhand。',
        en:
            'Cleans every category above in one shot. App settings, user '
            'memory, and downloaded LSP / MCP configs are NOT touched; '
            'remove ~/.openhand manually for a full reset.',
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

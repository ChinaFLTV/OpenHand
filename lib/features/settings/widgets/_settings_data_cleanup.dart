part of 'settings_view.dart';

/// 异步测算数据占用，限制测算并发，并在清理前统一确认。
class _DataCleanupSection extends StatefulWidget {
  const _DataCleanupSection();

  @override
  State<_DataCleanupSection> createState() => _DataCleanupSectionState();
}

class _DataCleanupSectionState extends State<_DataCleanupSection> {
  static const int _maxConcurrentMeasurements = 3;

  late final DataCleanupService _service;
  bool _serviceReady = false;

  final Map<DataCleanupCategory, DataCleanupSizeReport> _reports = {};
  final Set<DataCleanupCategory> _cleaningCategories = <DataCleanupCategory>{};
  final Set<DataCleanupCategory> _measuringCategories = <DataCleanupCategory>{};
  int _measureToken = 0;
  int? _webSearchCacheBytes;
  int? _webFetchCacheBytes;
  int? _mediaCacheBytes;
  SpeechDataCleanupSizeReport? _speechResourcesReport;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_serviceReady) {
      return;
    }
    _service = DataCleanupService(
      aiSessionController: context.read<AiSessionController>(),
      cronsController: context.read<CronsController>(),
      hooksController: context.read<HooksController>(),
      instructionsController: context.read<InstructionsController>(),
      memoryController: context.read<MemoryController>(),
      mcpController: context.read<McpController>(),
      messageGatewayController: context.read<MessageGatewayController>(),
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
        silentLog('data_cleanup', '统计/${category.name}', error, stack);
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

    Future<void> measureBreakdown({
      required String action,
      required Future<int> Function() task,
      required void Function(int bytes) apply,
    }) async {
      var bytes = 0;
      try {
        bytes = await task();
      } catch (error, stack) {
        silentLog('data_cleanup', action, error, stack);
      }
      if (!mounted || token != _measureToken) return;
      setState(() => apply(bytes));
    }

    Future<void> measureSpeechResources() async {
      SpeechDataCleanupSizeReport report;
      try {
        report = await _service.measureSpeechResources();
      } catch (error, stack) {
        silentLog('data_cleanup', '统计语音模型资源', error, stack);
        report = const SpeechDataCleanupSizeReport(
          recognitionModels: DataCleanupSizeReport.unknown,
          synthesisModels: DataCleanupSizeReport.unknown,
          sharedResources: DataCleanupSizeReport.unknown,
        );
      }
      if (!mounted || token != _measureToken) return;
      setState(() {
        _speechResourcesReport = report;
        _reports[DataCleanupCategory.speechResources] = report.total;
        _measuringCategories.remove(DataCleanupCategory.speechResources);
      });
    }

    final measurements = <Future<void> Function()>[
      () => measureOne(
        DataCleanupCategory.multimedia,
        _service.measureMultimedia,
      ),
      measureSpeechResources,
      () => measureOne(DataCleanupCategory.sessions, _service.measureSessions),
      () => measureOne(DataCleanupCategory.appCache, _service.measureAppCache),
      () => measureOne(DataCleanupCategory.logs, _service.measureLogs),
      () => measureOne(
        DataCleanupCategory.userMemory,
        _service.measureUserMemory,
      ),
      () =>
          measureOne(DataCleanupCategory.mcpConfig, _service.measureMcpConfig),
      () => measureOne(
        DataCleanupCategory.mcpOpsCache,
        _service.measureMcpOpsCache,
      ),
      () => measureOne(
        DataCleanupCategory.webGatewayOpsCache,
        _service.measureWebGatewayOpsCache,
      ),
      () => measureOne(DataCleanupCategory.hooks, _service.measureHooks),
      () => measureOne(DataCleanupCategory.crons, _service.measureCrons),
      () => measureOne(
        DataCleanupCategory.instructions,
        _service.measureInstructions,
      ),
      () => measureOne(
        DataCleanupCategory.skillsDirectory,
        _service.measureSkillsDirectory,
      ),
      () => measureOne(
        DataCleanupCategory.lspDirectory,
        _service.measureLspDirectory,
      ),
      () => measureOne(
        DataCleanupCategory.fileMutationLedger,
        _service.measureMutationLedger,
      ),
      // 子缓存只用于父分类明细，不重复计入分类总量。
      () => measureBreakdown(
        action: '统计 Web 搜索缓存',
        task: WebSearchCacheStore.instance.totalBytesOnDisk,
        apply: (bytes) => _webSearchCacheBytes = bytes,
      ),
      () => measureBreakdown(
        action: '统计 Web 抓取缓存',
        task: WebFetchCacheStore.instance.totalBytesOnDisk,
        apply: (bytes) => _webFetchCacheBytes = bytes,
      ),
      () => measureBreakdown(
        action: '统计媒体缓存',
        task: () async => (await MediaCacheService.measureCache()).bytes,
        apply: (bytes) => _mediaCacheBytes = bytes,
      ),
    ];
    await forEachIndexWithConcurrencyLimit(
      itemCount: measurements.length,
      maxConcurrency: _maxConcurrentMeasurements,
      shouldContinue: () => mounted && token == _measureToken,
      task: (index) => measurements[index](),
    );
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
    final confirmed = await showOpenHandConfirmDialog(
      context: navigatorContext,
      title: _categoryTitle(navigatorContext, category),
      message: _categoryConfirmBody(navigatorContext, category),
      confirmLabel: openHandLocalizedText(
        navigatorContext,
        zh: '清理',
        en: 'Clean',
      ),
      cancelLabel: l10n.commonCancel,
      destructive: true,
      maxWidth: 520,
      icon: Icon(
        Icons.warning_amber_outlined,
        color: Theme.of(navigatorContext).colorScheme.error,
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
    final partialFailureTemplate = openHandLocalizedText(
      context,
      zh: '部分数据清理失败（{count} 个分类），剩余项已保留。',
      en:
          'Some data could not be cleaned ({count} categories). '
          'Remaining items were preserved.',
    );
    final genericFailureTemplate = openHandLocalizedText(
      context,
      zh: '清理失败，请稍后重试。',
      en: 'Clean failed. Please try again.',
    );
    final categoryTitle = _categoryTitle(context, category);
    final successText = openHandLocalizedText(
      context,
      zh: '已清理：$categoryTitle',
      en: 'Cleaned: $categoryTitle',
    );
    String? errorText;
    try {
      switch (category) {
        case DataCleanupCategory.multimedia:
          await _service.cleanMultimedia();
        case DataCleanupCategory.speechResources:
          await _service.cleanSpeechResources();
        case DataCleanupCategory.sessions:
          await _service.cleanSessions();
        case DataCleanupCategory.appCache:
          await _service.cleanAppCache();
        case DataCleanupCategory.logs:
          await _service.cleanLogs();
        case DataCleanupCategory.userMemory:
          await _service.cleanUserMemory();
        case DataCleanupCategory.mcpConfig:
          await _service.cleanMcpConfig();
        case DataCleanupCategory.mcpOpsCache:
          await _service.cleanMcpOpsCache();
        case DataCleanupCategory.webGatewayOpsCache:
          await _service.cleanWebGatewayOpsCache();
        case DataCleanupCategory.hooks:
          await _service.cleanHooks();
        case DataCleanupCategory.crons:
          await _service.cleanCrons();
        case DataCleanupCategory.instructions:
          await _service.cleanInstructions();
        case DataCleanupCategory.skillsDirectory:
          await _service.cleanSkillsDirectory();
        case DataCleanupCategory.lspDirectory:
          await _service.cleanLspDirectory();
        case DataCleanupCategory.fileMutationLedger:
          await _service.cleanMutationLedger();
        case DataCleanupCategory.wipeAll:
          final errors = await _service.cleanAll();
          if (errors > 0) {
            errorText = partialFailureTemplate.replaceAll('{count}', '$errors');
          }
      }
    } catch (error, stack) {
      silentLog('data_cleanup', '清理/${category.name}', error, stack);
      errorText = genericFailureTemplate;
    } finally {
      if (mounted) {
        setState(() {
          _cleaningCategories.remove(category);
        });
      }
    }
    if (!mounted) return;
    if (errorText != null) {
      showOpenHandErrorSnack(context, errorText);
    } else {
      showOpenHandSuccessSnack(context, successText);
    }
    // 重新测算，让 UI 反映最新体积。
    await _measureAll();
  }

  String _cacheBreakdownLine({
    required BuildContext context,
    required int? bytes,
    required String zhLabel,
    required String enLabel,
  }) {
    if (bytes == null) {
      return openHandLocalizedText(
        context,
        zh: '其中 $zhLabel 缓存：测算中…',
        en: '$enLabel cache: measuring…',
      );
    }
    if (bytes <= 0) {
      return openHandLocalizedText(
        context,
        zh: '其中 $zhLabel 缓存：0 B',
        en: '$enLabel cache: 0 B',
      );
    }
    final human = formatByteSize(bytes);
    return openHandLocalizedText(
      context,
      zh: '其中 $zhLabel 缓存：$human',
      en: '$enLabel cache: $human',
    );
  }

  String? _buildMultimediaBreakdown(BuildContext context) {
    return _cacheBreakdownLine(
      context: context,
      bytes: _mediaCacheBytes,
      zhLabel: '网络多媒体',
      enLabel: 'Remote media',
    );
  }

  String? _buildAppCacheBreakdown(BuildContext context) {
    final searchLine = _cacheBreakdownLine(
      context: context,
      bytes: _webSearchCacheBytes,
      zhLabel: 'WebSearch',
      enLabel: 'WebSearch',
    );
    final fetchLine = _cacheBreakdownLine(
      context: context,
      bytes: _webFetchCacheBytes,
      zhLabel: 'WebFetch',
      enLabel: 'WebFetch',
    );
    return '$searchLine\n$fetchLine';
  }

  String? _buildSpeechResourcesBreakdown(BuildContext context) {
    final report = _speechResourcesReport;
    if (report == null) return null;
    final recognition = formatByteSize(report.recognitionModels.bytes);
    final synthesis = formatByteSize(report.synthesisModels.bytes);
    final shared = formatByteSize(report.sharedResources.bytes);
    return openHandLocalizedText(
      context,
      zh:
          '语音识别模型：$recognition\n'
          '语音朗读模型：$synthesis\n'
          '共享运行环境与下载缓存：$shared',
      en:
          'Speech recognition models: $recognition\n'
          'Speech synthesis models: $synthesis\n'
          'Shared runtimes and download cache: $shared',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSubsectionCard(
      title: openHandLocalizedText(context, zh: '数据清理', en: 'Data Cleanup'),
      description: openHandLocalizedText(
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
              breakdown: switch (category) {
                DataCleanupCategory.multimedia => _buildMultimediaBreakdown(
                  context,
                ),
                DataCleanupCategory.speechResources =>
                  _buildSpeechResourcesBreakdown(context),
                DataCleanupCategory.appCache => _buildAppCacheBreakdown(
                  context,
                ),
                _ => null,
              },
              onClean: () => _onCleanPressed(category),
            ),
            if (category != DataCleanupCategory.values.last)
              const Divider(height: 24),
          ],
          kOpenHandGap16,
          const _LedgerAdvancedControls(),
          kOpenHandGap12,
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _measuringCategories.isNotEmpty ? null : _measureAll,
              icon: const Icon(Icons.refresh_outlined),
              label: Text(
                openHandLocalizedText(context, zh: '重新测算', en: 'Recalculate'),
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
    this.breakdown,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final DataCleanupSizeReport? report;
  final bool isMeasuring;
  final bool isCleaning;
  final bool isDestructive;
  final VoidCallback onClean;
  final String? breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sizeText = isMeasuring || report == null
        ? openHandLocalizedText(context, zh: '测算中…', en: 'Measuring…')
        : formatByteSize(report!.bytes);
    final itemCount = report?.itemCount;
    final detailText = (isMeasuring || report == null)
        ? null
        : (itemCount != null && itemCount > 0
              ? openHandLocalizedText(
                  context,
                  zh: '$itemCount 项',
                  en: '$itemCount item${itemCount == 1 ? '' : 's'}',
                )
              : null);
    final canClean =
        !isCleaning &&
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
                kOpenHandHGap12,
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            kOpenHandGap6,
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            kOpenHandGap8,
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
                  kOpenHandHGap8,
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
                  kOpenHandHGap10,
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
            if (breakdown != null) ...[
              kOpenHandGap4,
              Row(
                children: [
                  Icon(
                    Icons.subdirectory_arrow_right,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  kOpenHandHGap4,
                  Flexible(
                    child: Text(
                      breakdown!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
        // 用 ButtonStyle 锁住内边距 / 触控目标 / 文本样式，避免 M3 默认
        // FilledButton.icon 在外层 `SizedBox(height: 40)` 下会把 label
        // 挤出可视区（icon + 文本叠在一起，看起来"按钮文本不见了"）。
        final buttonStyle =
            FilledButton.styleFrom(
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
              ? openHandLocalizedText(context, zh: '一键清空', en: 'Wipe All')
              : openHandLocalizedText(context, zh: '清理', en: 'Clean'),
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
              kOpenHandGap12,
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: cleanButton,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: infoColumn),
            kOpenHandHGap16,
            cleanButton,
          ],
        );
      },
    );
  }
}

IconData _categoryIcon(DataCleanupCategory category) {
  switch (category) {
    case DataCleanupCategory.multimedia:
      return Icons.image_outlined;
    case DataCleanupCategory.speechResources:
      return Icons.record_voice_over_outlined;
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
    case DataCleanupCategory.mcpOpsCache:
      return Icons.monitor_heart_outlined;
    case DataCleanupCategory.webGatewayOpsCache:
      return Icons.hub_outlined;
    case DataCleanupCategory.hooks:
      return Icons.webhook_outlined;
    case DataCleanupCategory.crons:
      return Icons.schedule_outlined;
    case DataCleanupCategory.instructions:
      return Icons.menu_book_outlined;
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
      return openHandLocalizedText(context, zh: '多媒体数据', en: 'Multimedia Data');
    case DataCleanupCategory.speechResources:
      return openHandLocalizedText(
        context,
        zh: '语音模型资源',
        en: 'Speech Model Resources',
      );
    case DataCleanupCategory.sessions:
      return openHandLocalizedText(context, zh: '会话数据', en: 'Sessions');
    case DataCleanupCategory.appCache:
      return openHandLocalizedText(context, zh: '应用缓存', en: 'App Cache');
    case DataCleanupCategory.logs:
      return openHandLocalizedText(context, zh: '日志数据', en: 'Logs');
    case DataCleanupCategory.userMemory:
      return openHandLocalizedText(context, zh: '用户记忆', en: 'User Memory');
    case DataCleanupCategory.mcpConfig:
      return openHandLocalizedText(context, zh: 'MCP 配置', en: 'MCP Config');
    case DataCleanupCategory.mcpOpsCache:
      return openHandLocalizedText(
        context,
        zh: 'MCP 运维缓存',
        en: 'MCP Ops Cache',
      );
    case DataCleanupCategory.webGatewayOpsCache:
      return openHandLocalizedText(
        context,
        zh: 'Web 网关运维缓存',
        en: 'Web Gateway Ops Cache',
      );
    case DataCleanupCategory.hooks:
      return openHandLocalizedText(context, zh: 'Hooks 配置', en: 'Hooks');
    case DataCleanupCategory.crons:
      return openHandLocalizedText(context, zh: '定时任务', en: 'Cron Jobs');
    case DataCleanupCategory.instructions:
      return openHandLocalizedText(context, zh: '用户指令', en: 'Instructions');
    case DataCleanupCategory.skillsDirectory:
      return openHandLocalizedText(context, zh: '技能目录', en: 'Skills Directory');
    case DataCleanupCategory.lspDirectory:
      return openHandLocalizedText(
        context,
        zh: 'LSP 安装目录',
        en: 'LSP Install Dir',
      );
    case DataCleanupCategory.fileMutationLedger:
      return openHandLocalizedText(
        context,
        zh: '文件变动历史',
        en: 'File Mutation Ledger',
      );
    case DataCleanupCategory.wipeAll:
      return openHandLocalizedText(context, zh: '全部数据', en: 'All Data');
  }
}

String _categorySubtitle(BuildContext context, DataCleanupCategory category) {
  switch (category) {
    case DataCleanupCategory.multimedia:
      return openHandLocalizedText(
        context,
        zh:
            '会话附件、旧临时生成媒体与 ~/.openhand/cache/media/ 网络多媒体缓存。'
            '清理后历史消息中的本地附件会显示为缺失，网络媒体会重新下载缓存。',
        en:
            'Session attachments, legacy generated media temp files, and the '
            '~/.openhand/cache/media/ remote media cache. Local attachments in '
            'older messages will appear as missing; remote media will cache '
            'again on next load.',
      );
    case DataCleanupCategory.speechResources:
      return openHandLocalizedText(
        context,
        zh:
            '语音识别与语音朗读下载的本地模型、隔离运行环境及下载缓存。'
            '清理会停止并禁用已启用的本地语音服务；在线服务选择、凭据和模型参数保持不变，'
            '本地资源可在下次使用时重新下载。',
        en:
            'Downloaded speech recognition and synthesis models, isolated '
            'runtimes, and download cache. Cleanup stops and disables active '
            'local speech services while preserving online selections, '
            'credentials, and model parameters. Local resources can be '
            'downloaded again when needed.',
      );
    case DataCleanupCategory.sessions:
      return openHandLocalizedText(
        context,
        zh: '所有 AI 会话与消息（含旧版 JSON）。清理后会话列表会被清空。',
        en:
            'All AI sessions and messages (including legacy JSON). The '
            'session list will be empty after cleanup.',
      );
    case DataCleanupCategory.appCache:
      return openHandLocalizedText(
        context,
        zh:
            '~/.openhand/cache/ 下的临时缓存文件，不包含由“多媒体数据”与“语音模型资源”'
            '单独管理的缓存。',
        en:
            'Temporary cache files under ~/.openhand/cache/, excluding caches '
            'managed by "Multimedia Data" and "Speech Model Resources".',
      );
    case DataCleanupCategory.logs:
      return openHandLocalizedText(
        context,
        zh: 'cron 执行历史 + ~/.openhand/logs/ 目录。',
        en: 'Cron execution history + the ~/.openhand/logs/ directory.',
      );
    case DataCleanupCategory.userMemory:
      return openHandLocalizedText(
        context,
        zh: '用户画像与所有用户记忆条目。清理后自学习子 Agent 会重新累积。',
        en:
            'User profile + all user memory entries. The self-learning '
            'sub-agent will gradually rebuild them.',
      );
    case DataCleanupCategory.mcpConfig:
      return openHandLocalizedText(
        context,
        zh: '已配置的 MCP Server 列表（JSON 文件）。清理后 MCP 列表会变空。',
        en:
            'Configured MCP Server list (JSON file). The MCP list will be '
            'empty after cleanup.',
      );
    case DataCleanupCategory.mcpOpsCache:
      return openHandLocalizedText(
        context,
        zh: 'MCP 服务器运维弹窗本地持久化的监控趋势、运行快照与日志审计数据。清理后不影响 MCP 配置。',
        en:
            'Locally persisted MCP operations trends, runtime snapshots and '
            'audit logs. MCP configuration is not affected.',
      );
    case DataCleanupCategory.webGatewayOpsCache:
      return openHandLocalizedText(
        context,
        zh: 'Web 消息网关运维弹窗本地持久化的监控趋势、运行快照与内存日志回溯数据。',
        en:
            'Locally persisted Web Message Gateway operations trends, runtime '
            'snapshots and in-memory log history.',
      );
    case DataCleanupCategory.hooks:
      return openHandLocalizedText(
        context,
        zh: '全局设置 → Hooks 中配置的钩子脚本（sqlite hooks 表）。清理后 Hooks 列表会变空。',
        en:
            'Hook scripts configured under Settings → Hooks (sqlite `hooks` '
            'table). The Hooks list will be empty after cleanup.',
      );
    case DataCleanupCategory.crons:
      return openHandLocalizedText(
        context,
        zh: '用户创建的定时任务（不含 Hermes Talker 自主学习、MCP 关键词索引等系统内置任务）。清理后用户任务列表会变空，执行历史在「日志数据」中独立清理。',
        en:
            'User-created cron jobs. System-managed entries (Hermes Talker '
            'self-learning, MCP keyword index, etc.) are preserved. Execution '
            'history is cleaned separately under "Logs".',
      );
    case DataCleanupCategory.instructions:
      return openHandLocalizedText(
        context,
        zh: '全局设置 → 指令中用户自定义的指令条目（sqlite user_instructions 表）。清理后指令列表会变空。',
        en:
            'User-authored instruction entries under Settings → Instructions '
            '(sqlite `user_instructions` table). The list will be empty '
            'after cleanup.',
      );
    case DataCleanupCategory.skillsDirectory:
      return openHandLocalizedText(
        context,
        zh: '当前技能目录下的全部文件。包含用户自定义的技能内容，请谨慎操作。',
        en:
            'All files under the current skills directory. User-authored '
            'skills are included; proceed with caution.',
      );
    case DataCleanupCategory.lspDirectory:
      return openHandLocalizedText(
        context,
        zh: '~/.openhand/lsp/ 目录下托管下载的 LSP 二进制。下次需要时会自动重装。',
        en:
            'Managed LSP binaries under ~/.openhand/lsp/. They will be '
            'reinstalled on next use.',
      );
    case DataCleanupCategory.fileMutationLedger:
      return openHandLocalizedText(
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
      return openHandLocalizedText(
        context,
        zh:
            '一次性清理上述所有分类的数据。不会删除含当前设置的 sqlite 数据库文件，'
            '否则会让正在运行的进程崩溃；如需彻底重置，请退出应用后手动删除 '
            '~/.openhand。',
        en:
            'Cleans every category above in one shot. The sqlite database '
            'containing current settings is retained because deleting it '
            'would crash the running process. Quit the app before manually '
            'removing ~/.openhand for a full reset.',
      );
  }
}

String _categoryConfirmBody(
  BuildContext context,
  DataCleanupCategory category,
) {
  final detail = _categorySubtitle(context, category);
  return openHandLocalizedText(
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
  final OpenHandDebouncer _saveDebounce = OpenHandDebouncer(
    delay: const Duration(milliseconds: 350),
  );
  LedgerConfig? _config;
  LedgerConfig? _persistedConfig;
  LedgerConfig? _pendingConfig;
  int _configSaveRevision = 0;
  LedgerStatsSnapshot? _stats;
  bool _pruneNowBusy = false;
  ({int removed, int bytesFreed})? _lastGcStats;
  final ValueNotifier<int> _cleanupPulse = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _ledger.loadConfig().then(
      (config) {
        if (!mounted) return;
        setState(() {
          _config = config;
          _persistedConfig = config;
        });
      },
      onError: (Object error, StackTrace stack) {
        silentLog('ledger_config', '加载账本配置', error, stack);
      },
    );
    _refreshStats();
  }

  Future<void> _refreshStats() async {
    try {
      final stats = await _ledger.statsSnapshot();
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (error, stack) {
      silentLog('ledger_stats', '刷新账本统计', error, stack);
    }
  }

  /// 按当前 days/maxVersions 手动执行一次 ledger 维护并刷新统计。
  Future<void> _pruneNow() async {
    final cfg = _config;
    if (cfg == null) return;
    setState(() => _pruneNowBusy = true);
    try {
      if (cfg.autoCleanupDays > 0) {
        await _ledger.pruneOlderThan(Duration(days: cfg.autoCleanupDays));
      }
      await _ledger.pruneToMaxVersionsPerFile(cfg.maxVersionsPerFile);
      final gc = await _ledger.gcUnreferencedBlobs();
      if (mounted) {
        setState(() => _lastGcStats = gc);
        _cleanupPulse.value += 1;
        // SnackBar 反馈与 undo/redo 节奏一致：2s。
        showOpenHandSuccessSnack(
          context,
          openHandLocalizedText(
            context,
            zh:
                '已清理 · 释放 ${gc.removed} 个 blob · '
                '${formatByteSize(gc.bytesFreed)}',
            en:
                'Cleaned · ${gc.removed} blob(s) · '
                '${formatByteSize(gc.bytesFreed)} freed',
          ),
        );
      }
      await _refreshStats();
    } catch (error, stack) {
      silentLog('ledger_prune', '裁剪账本', error, stack);
      if (mounted) {
        final detail = userFailureMessage(error, fallback: '无法清理文件历史。');
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '文件历史清理失败：$detail',
            en: 'Failed to prune file history: $detail',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pruneNowBusy = false);
    }
  }

  @override
  void dispose() {
    final pendingConfig = _pendingConfig;
    _pendingConfig = null;
    _saveDebounce.dispose();
    if (pendingConfig != null) {
      unawaited(
        _ledger
            .saveConfig(pendingConfig)
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) {
                silentLog('ledger_config', '退出设置页时保存账本配置', error, stack);
              },
            ),
      );
    }
    _cleanupPulse.dispose();
    super.dispose();
  }

  // ───────────────────────── 跨会话搜索 / 导出 / 导入 ─────────────────────────
  Future<void> _exportLedgerToClipboard() async {
    final pendingText = openHandLocalizedText(
      context,
      zh: '正在导出全部 ledger…',
      en: 'Exporting all ledger…',
    );
    showOpenHandInfoSnack(
      context,
      pendingText,
      duration: kOpenHandSnackBarBriefDuration,
    );
    try {
      final json = await _ledger.exportBundleJson();
      if (!mounted) return;
      final copied = await copyOpenHandTextToClipboard(
        logTag: 'settings',
        context: context,
        text: json,
        logAction: '复制账本数据包',
        showSuccess: false,
      );
      if (!copied || !mounted) return;
      _cleanupPulse.value += 1;
      final bytes = utf8.encode(json).length;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已复制 ledger bundle · ${formatByteSize(bytes)}',
          en: 'Copied ledger bundle · ${formatByteSize(bytes)}',
        ),
      );
    } catch (error, stack) {
      silentLog('ledger_export', '导出账本', error, stack);
      if (!mounted) return;
      final detail = userFailureMessage(error, fallback: '无法导出文件历史。');
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '导出失败：$detail',
          en: 'Export failed: $detail',
        ),
      );
    }
  }

  Future<void> _importLedgerFromClipboard() async {
    final raw = await getOpenHandClipboardText() ?? '';
    if (!mounted) return;
    if (raw.trim().isEmpty) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(context, zh: '剪贴板为空', en: 'Clipboard is empty'),
      );
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '从剪贴板导入 ledger',
        en: 'Import ledger from clipboard',
      ),
      message: openHandLocalizedText(
        context,
        zh:
            '将合并剪贴板中的 ledger bundle 到当前 file_history 目录。'
            '同 recordId 的条目会跳过。该操作不可撤销。',
        en:
            'The ledger bundle in your clipboard will be merged into the '
            'current file_history. Records with duplicate ids are '
            'skipped. This cannot be undone.',
      ),
      confirmLabel: openHandImportLabel(context),
      cancelLabel: AppLocalizations.of(context)!.commonCancel,
      maxWidth: 520,
      icon: Icon(
        Icons.download_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final imported = await _ledger.importBundleJson(raw);
      if (!mounted) return;
      _cleanupPulse.value += 1;
      await _refreshStats();
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已导入 $imported 条新记录',
          en: 'Imported $imported new record(s)',
        ),
      );
    } catch (error, stack) {
      silentLog('ledger_import', '导入账本', error, stack);
      if (!mounted) return;
      final detail = userFailureMessage(error, fallback: '无法导入文件历史。');
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '导入失败：$detail',
          en: 'Import failed: $detail',
        ),
      );
    }
  }

  Future<void> _openLedgerSearchDialog() async {
    await showAnimatedDialog<void>(
      context: context,
      builder: (ctx) => _LedgerSearchDialog(ledger: _ledger),
    );
  }

  void _scheduleSave(LedgerConfig next) {
    final revision = ++_configSaveRevision;
    _pendingConfig = next;
    setState(() => _config = next);
    _saveDebounce.schedule(() async {
      if (revision == _configSaveRevision) {
        _pendingConfig = null;
      }
      try {
        await _ledger.saveConfig(next);
        if (!mounted) return;
        _persistedConfig = next;
        await _refreshStats();
      } catch (error, stack) {
        silentLog('ledger_config', '保存账本配置', error, stack);
        if (!mounted || revision != _configSaveRevision) return;
        setState(() => _config = _persistedConfig);
        final detail = userFailureMessage(error, fallback: '无法保存文件历史设置。');
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '文件历史设置保存失败：$detail',
            en: 'Failed to save file-history settings: $detail',
          ),
        );
      }
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
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(kOpenHandRadius12),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune_rounded, size: 16, color: cs.primary),
                  kOpenHandHGap8,
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '文件变动历史 — 高级控制',
                      en: 'File Mutation Ledger — Advanced',
                    ),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (_stats != null)
                    Text(
                      openHandLocalizedText(
                        context,
                        zh:
                            '${_stats!.sessionCount} 会话 · '
                            '${_stats!.recordCount} 条 · '
                            '${_stats!.blobCount} blobs',
                        en:
                            '${_stats!.sessionCount} sessions · '
                            '${_stats!.recordCount} records · '
                            '${_stats!.blobCount} blobs',
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              kOpenHandGap6,
              _SliderRow(
                label: openHandLocalizedText(
                  context,
                  zh: '每文件最多保留 N 条历史',
                  en: 'Max versions per file',
                ),
                valueText: '${config.maxVersionsPerFile}',
                value: config.maxVersionsPerFile.toDouble(),
                min: LedgerConfig.minMaxVersionsPerFile.toDouble(),
                max: LedgerConfig.maxMaxVersionsPerFile.toDouble(),
                divisions:
                    LedgerConfig.maxMaxVersionsPerFile -
                    LedgerConfig.minMaxVersionsPerFile,
                onChanged: (v) => _scheduleSave(
                  config.copyWith(maxVersionsPerFile: v.round()),
                ),
              ),
              _SliderRow(
                label: openHandLocalizedText(
                  context,
                  zh: 'N 天前的历史自动清理（启动时）',
                  en: 'Auto-cleanup older than N days (on launch)',
                ),
                valueText: config.autoCleanupDays == 0
                    ? openHandLocalizedText(context, zh: '关闭', en: 'Disabled')
                    : openHandLocalizedText(
                        context,
                        zh: '${config.autoCleanupDays} 天',
                        en: '${config.autoCleanupDays} days',
                      ),
                value: config.autoCleanupDays.toDouble(),
                min: LedgerConfig.minAutoCleanupDays.toDouble(),
                max: LedgerConfig.maxAutoCleanupDays.toDouble(),
                divisions: LedgerConfig.maxAutoCleanupDays,
                onChanged: (v) =>
                    _scheduleSave(config.copyWith(autoCleanupDays: v.round())),
              ),
              // mini-diff 阈值（KiB）：在 (阈值, 256 KiB] 区间仅保留 +/- 行。
              _SliderRow(
                label: openHandLocalizedText(
                  context,
                  zh: 'Mini-diff 阈值（超过则仅保留 +/- 行）',
                  en: 'Mini-diff threshold (drop context above)',
                ),
                valueText: config.miniDiffMaxBytes == 0
                    ? openHandLocalizedText(context, zh: '禁用', en: 'Disabled')
                    : '${(config.miniDiffMaxBytes / kBytesPerKiB).round()} KiB',
                value: config.miniDiffMaxBytes.toDouble(),
                min: LedgerConfig.minMiniDiffMaxBytes.toDouble(),
                max: LedgerConfig.maxMiniDiffMaxBytes.toDouble(),
                divisions: 32,
                onChanged: (v) {
                  // 对齐到 8 KiB step
                  const step = 8 * kBytesPerKiB;
                  final snapped = ((v / step).round() * step).clamp(
                    LedgerConfig.minMiniDiffMaxBytes,
                    LedgerConfig.maxMiniDiffMaxBytes,
                  );
                  _scheduleSave(config.copyWith(miniDiffMaxBytes: snapped));
                },
              ),
              kOpenHandGap6,
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _openLedgerSearchDialog,
                      icon: Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '搜索…',
                          en: 'Search…',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _exportLedgerToClipboard,
                      icon: Icon(
                        Icons.ios_share_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '导出全部',
                          en: 'Export all',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _importLedgerFromClipboard,
                      icon: Icon(
                        Icons.download_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '从剪贴板导入',
                          en: 'Import from clipboard',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _pruneNowBusy ? null : _pruneNow,
                      icon: _pruneNowBusy
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            )
                          : Icon(
                              Icons.cleaning_services_rounded,
                              size: 16,
                              color: cs.primary,
                            ),
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '立即清理超期',
                          en: 'Prune now',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_lastGcStats != null) ...[
                kOpenHandGap4,
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    openHandLocalizedText(
                      context,
                      zh: '上次 GC 释放 ${_lastGcStats!.removed} 个 blob · ${formatByteSize(_lastGcStats!.bytesFreed)}',
                      en: 'Last GC freed ${_lastGcStats!.removed} blob(s) · ${formatByteSize(_lastGcStats!.bytesFreed)}',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // 成功 prune 后顶部发一次 highlight pulse。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(child: HighlightPulse(signal: _cleanupPulse)),
        ),
      ],
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
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              kOpenHandHGap12,
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

/// 跨会话 ledger 搜索弹窗。
class _LedgerSearchDialog extends StatefulWidget {
  const _LedgerSearchDialog({required this.ledger});
  final AiFileMutationLedger ledger;

  @override
  State<_LedgerSearchDialog> createState() => _LedgerSearchDialogState();
}

class _LedgerSearchDialogState extends State<_LedgerSearchDialog> {
  final TextEditingController _pathCtrl = TextEditingController();
  final TextEditingController _toolCtrl = TextEditingController();
  final OpenHandDebouncer _searchDebounce = OpenHandDebouncer(
    delay: const Duration(milliseconds: 220),
  );
  final Set<FileMutationKind> _selectedKinds = <FileMutationKind>{};
  _LedgerTimeRange _timeRange = _LedgerTimeRange.all;
  bool _searchBusy = false;
  bool _exportBusy = false;
  bool _searchFailed = false;
  List<FileMutationView> _results = const <FileMutationView>[];
  int _page = 1;
  int _pageSize = kOpenHandTableDefaultPageSize;
  int _runToken = 0;

  @override
  void initState() {
    super.initState();
    // 进入即跑一次默认搜索（不过滤），让用户立即看到全量。
    unawaited(_runSearch());
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _toolCtrl.dispose();
    _searchDebounce.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _searchDebounce.schedule(_runSearch);
  }

  Future<void> _runSearch() async {
    if (!mounted) return;
    final token = ++_runToken;
    setState(() {
      _searchBusy = true;
      _searchFailed = false;
    });
    try {
      final tools = splitLooseDelimitedValues(_toolCtrl.text);
      final results = await widget.ledger.searchRecords(
        pathContains: _pathCtrl.text.trim(),
        toolNames: tools.isEmpty ? null : tools,
        kinds: _selectedKinds.isEmpty ? null : _selectedKinds,
        since: _timeRange.computeSince(),
        limit: AiFileMutationLedger.maxSearchResults,
      );
      if (!mounted || token != _runToken) return;
      setState(() {
        _results = results;
        _page = 1;
      });
    } catch (error, stack) {
      silentLog('ledger_search_dialog', '搜索账本记录', error, stack);
      if (mounted && token == _runToken) {
        setState(() => _searchFailed = true);
      }
    } finally {
      if (mounted && token == _runToken) {
        setState(() => _searchBusy = false);
      }
    }
  }

  Future<void> _copyResults() async {
    final json = prettyPrintJson(
      _results.map((v) => v.record.toJson()).toList(),
    );
    await copyOpenHandTextToClipboard(
      logTag: 'settings',
      context: context,
      text: json,
      successMessage: openHandLocalizedText(
        context,
        zh: '已复制 ${_results.length} 条结果到剪贴板',
        en: 'Copied ${_results.length} record(s) to clipboard',
      ),
      logAction: '复制账本搜索结果',
    );
  }

  /// 把当前过滤结果（含 blob）打成 bundle JSON 复制到剪贴板。
  Future<void> _exportFilteredAsBundle() async {
    if (_results.isEmpty || _exportBusy) return;
    setState(() => _exportBusy = true);
    try {
      final bundle = await widget.ledger.exportRecordsAsBundleJson(
        _results.map((v) => v.record),
      );
      if (!mounted) return;
      await copyOpenHandTextToClipboard(
        logTag: 'settings',
        context: context,
        text: bundle,
        successMessage: openHandLocalizedText(
          context,
          zh: '已导出 ${_results.length} 条筛选结果（含 blob）到剪贴板',
          en: 'Exported ${_results.length} filtered record(s) (with blobs)',
        ),
        logAction: '复制筛选后的账本数据包',
      );
    } catch (error, stack) {
      silentLog('ledger_search_dialog', '导出筛选后的账本数据包', error, stack);
      if (!mounted) return;
      final detail = userFailureMessage(error, fallback: '无法导出筛选结果。');
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '导出失败：$detail',
          en: 'Export failed: $detail',
        ),
      );
    } finally {
      if (mounted) setState(() => _exportBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final maxWidth = (viewport.width * 0.72).clamp(420, 920).toDouble();
    final maxHeight = (viewport.height * 0.72).clamp(420, 720).toDouble();
    final resultWindow = OpenHandPageWindow.normalize(
      page: _page,
      pageSize: _pageSize,
      total: _results.length,
    );
    final pageResults = resultWindow.slice(_results);
    return buildOpenHandDialog(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Focus(
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.search_rounded, color: cs.primary, size: 18),
                    kOpenHandHGap8,
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '搜索文件变动 ledger',
                        en: 'Search file mutation ledger',
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: openHandCloseLabel(context),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                kOpenHandGap8,
                TextField(
                  controller: _pathCtrl,
                  onChanged: (_) => _scheduleSearch(),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.folder_outlined, size: 16),
                    hintText: openHandLocalizedText(
                      context,
                      zh: '路径包含（如 lib/features/...）',
                      en: 'Path contains (e.g. lib/features/...)',
                    ),
                  ),
                ),
                kOpenHandGap6,
                TextField(
                  controller: _toolCtrl,
                  onChanged: (_) => _scheduleSearch(),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.build_rounded, size: 16),
                    hintText: openHandLocalizedText(
                      context,
                      zh: '工具名（逗号或空格分隔，如 Edit, Write）',
                      en: 'Tool names (comma/space separated, e.g. Edit, Write)',
                    ),
                  ),
                ),
                kOpenHandGap6,
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final k in FileMutationKind.values)
                      FilterChip(
                        label: Text(k.name),
                        selected: _selectedKinds.contains(k),
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _selectedKinds.add(k);
                            } else {
                              _selectedKinds.remove(k);
                            }
                          });
                          _scheduleSearch();
                        },
                      ),
                  ],
                ),
                kOpenHandGap4,
                // 时间范围预设。
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final r in _LedgerTimeRange.values)
                      ChoiceChip(
                        label: Text(r.label(context)),
                        selected: _timeRange == r,
                        onSelected: (sel) {
                          if (!sel) return;
                          setState(() => _timeRange = r);
                          _scheduleSearch();
                        },
                      ),
                  ],
                ),
                const Divider(height: 18),
                Expanded(
                  child: OpenHandContentStateSwitcher(
                    // 外层 Expanded 已定高，这里只做淡入淡出。
                    animateSize: false,
                    stateKey: _searchBusy
                        ? 'busy'
                        : _searchFailed
                        ? 'error'
                        : _results.isEmpty
                        ? 'empty'
                        : 'results',
                    child: _searchBusy
                        ? Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: cs.primary,
                              ),
                            ),
                          )
                        : _searchFailed
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: cs.error,
                                ),
                                kOpenHandGap6,
                                Text(
                                  openHandLocalizedText(
                                    context,
                                    zh: '账本记录搜索失败',
                                    en: 'Failed to search ledger records',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.error,
                                  ),
                                ),
                                kOpenHandGap4,
                                IconButton(
                                  tooltip: openHandLocalizedText(
                                    context,
                                    zh: '重试',
                                    en: 'Retry',
                                  ),
                                  onPressed: _runSearch,
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                              ],
                            ),
                          )
                        : _results.isEmpty
                        ? OpenHandInlineEmptyState(
                            message: openHandLocalizedText(
                              context,
                              zh: '没有匹配的记录。',
                              en: 'No matching records.',
                            ),
                            dense: true,
                          )
                        : ListView.separated(
                            itemCount: pageResults.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: cs.outlineVariant),
                            itemBuilder: (ctx, i) {
                              final v = pageResults[i];
                              final r = v.record;
                              final greyed = v.isEffectivelyUndone;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.primary.withValues(
                                          alpha: 0.10,
                                        ),
                                        borderRadius: const BorderRadius.all(
                                          Radius.circular(kOpenHandRadius4),
                                        ),
                                      ),
                                      child: Text(
                                        r.kind.name,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: cs.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    kOpenHandHGap6,
                                    Text(
                                      r.toolName,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                    kOpenHandHGap8,
                                    Expanded(
                                      child: _PathHighlightText(
                                        path: r.filePath,
                                        query: _pathCtrl.text.trim(),
                                        baseColor: greyed
                                            ? cs.onSurfaceVariant.withValues(
                                                alpha: 0.6,
                                              )
                                            : cs.onSurface,
                                        decoration: greyed
                                            ? TextDecoration.lineThrough
                                            : null,
                                        highlightBg: cs.primary.withValues(
                                          alpha: 0.18,
                                        ),
                                        highlightFg: cs.primary,
                                        textStyle: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                    kOpenHandHGap6,
                                    Text(
                                      r.createdAt
                                          .toLocal()
                                          .toIso8601String()
                                          .substring(0, 19),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
                if (!_searchBusy && !_searchFailed && _results.isNotEmpty) ...[
                  kOpenHandGap8,
                  OpenHandTablePagination(
                    total: resultWindow.total,
                    page: resultWindow.page,
                    pageSize: resultWindow.pageSize,
                    onPageChanged: (page) => setState(() => _page = page),
                    onPageSizeChanged: (size) => setState(() {
                      _pageSize = size;
                      _page = 1;
                    }),
                  ),
                ],
                kOpenHandGap8,
                Row(
                  children: [
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '${_results.length} 条结果',
                        en: '${_results.length} result(s)',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _results.isEmpty || _searchBusy || _exportBusy
                          ? null
                          : _exportFilteredAsBundle,
                      icon: const Icon(Icons.archive_outlined, size: 16),
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '导出筛选结果（含 blob）',
                          en: 'Export filtered (with blobs)',
                        ),
                      ),
                    ),
                    kOpenHandHGap4,
                    TextButton.icon(
                      onPressed: _results.isEmpty ? null : _copyResults,
                      icon: const Icon(Icons.copy_all_rounded, size: 16),
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '复制结果 JSON',
                          en: 'Copy results JSON',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 路径高亮文字：当 `query` 非空时把命中片段着色并加微底高亮。
class _PathHighlightText extends StatelessWidget {
  const _PathHighlightText({
    required this.path,
    required this.query,
    required this.baseColor,
    required this.decoration,
    required this.highlightBg,
    required this.highlightFg,
    required this.textStyle,
  });

  final String path;
  final String query;
  final Color baseColor;
  final TextDecoration? decoration;
  final Color highlightBg;
  final Color highlightFg;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final base = (textStyle ?? const TextStyle()).copyWith(
      fontFamily: kOpenHandMonospaceFontFamily,
      color: baseColor,
      decoration: decoration,
    );
    if (query.isEmpty) {
      return Text(
        path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    final lcPath = path.toLowerCase();
    final lcQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < path.length) {
      final hit = lcPath.indexOf(lcQuery, cursor);
      if (hit < 0) {
        spans.add(TextSpan(text: path.substring(cursor), style: base));
        break;
      }
      if (hit > cursor) {
        spans.add(TextSpan(text: path.substring(cursor, hit), style: base));
      }
      spans.add(
        TextSpan(
          text: path.substring(hit, hit + lcQuery.length),
          style: base.copyWith(
            color: highlightFg,
            fontWeight: FontWeight.w700,
            backgroundColor: highlightBg,
          ),
        ),
      );
      cursor = hit + lcQuery.length;
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }
}

/// 搜索时间范围预设。
enum _LedgerTimeRange {
  all,
  today,
  last7d,
  last30d;

  String label(BuildContext context) {
    switch (this) {
      case _LedgerTimeRange.all:
        return openHandLocalizedText(context, zh: '全部', en: 'All time');
      case _LedgerTimeRange.today:
        return openHandLocalizedText(context, zh: '今日', en: 'Today');
      case _LedgerTimeRange.last7d:
        return openHandLocalizedText(context, zh: '近 7 天', en: 'Last 7 days');
      case _LedgerTimeRange.last30d:
        return openHandLocalizedText(context, zh: '近 30 天', en: 'Last 30 days');
    }
  }

  DateTime? computeSince() {
    final now = DateTime.now();
    switch (this) {
      case _LedgerTimeRange.all:
        return null;
      case _LedgerTimeRange.today:
        return DateTime(now.year, now.month, now.day);
      case _LedgerTimeRange.last7d:
        return now.subtract(const Duration(days: 7));
      case _LedgerTimeRange.last30d:
        return now.subtract(const Duration(days: 30));
    }
  }
}

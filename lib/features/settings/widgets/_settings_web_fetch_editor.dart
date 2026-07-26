part of 'settings_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WebFetch 工具的引擎、缓存和遥测设置。
// 仅当 _BuiltinToolEditorDialog 编辑的是 AiBuiltinToolKind.webFetch 时挂载。
// ─────────────────────────────────────────────────────────────────────────────

class _WebFetchSettingsEditor extends StatefulWidget {
  const _WebFetchSettingsEditor({
    required this.value,
    required this.onChanged,
    required this.availableModels,
    required this.recentModelSelections,
  });

  final AiWebFetchSettings value;
  final ValueChanged<AiWebFetchSettings> onChanged;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;

  @override
  State<_WebFetchSettingsEditor> createState() =>
      _WebFetchSettingsEditorState();
}

class _WebFetchSettingsEditorState extends State<_WebFetchSettingsEditor> {
  late TextEditingController _resultCountController;
  late TextEditingController _cacheTtlController;
  late TextEditingController _cacheMaxBytesController;
  late TextEditingController _parallelWorkersController;

  // 当前磁盘上已经落盘的 WebFetch 缓存字节数，由 [_refreshCacheBytesOnDisk]
  // 异步加载；null 代表尚未读取或读取失败。
  int? _cacheBytesOnDisk;
  bool _clearingCache = false;

  // ── Telemetry (调用日志 + 引擎健康度) ──
  List<WebFetchCallLog> _recentCalls = const [];
  Map<AiWebFetchEngineKind, WebFetchEngineStat> _engineStats = const {};
  Map<AiWebFetchEngineKind, List<WebFetchEngineSample>> _engineHistory =
      const {};
  bool _telemetryLoading = false;
  bool _clearingTelemetry = false;
  bool _exportingTelemetry = false;
  WebFetchScraplingProbeStatus _scraplingProbe =
      const WebFetchScraplingProbeStatus(
        ready: false,
        code: 'not_checked',
        detail: 'Not checked yet.',
      );
  bool _scraplingProbeLoading = false;
  bool _scraplingRuntimeBusy = false;

  @override
  void initState() {
    super.initState();
    _resultCountController = TextEditingController(
      text: '${widget.value.resultCount}',
    );
    _cacheTtlController = TextEditingController(
      text: '${widget.value.cacheTtlSeconds}',
    );
    _cacheMaxBytesController = TextEditingController(
      text: formatMegabytesInput(widget.value.cacheMaxBytes),
    );
    _parallelWorkersController = TextEditingController(
      text: '${widget.value.parallelWorkers}',
    );
    _scraplingProbe = context
        .read<AiSessionController>()
        .toolRuntimeService
        .lastWebFetchScraplingProbe;
    _refreshCacheBytesOnDisk();
    _refreshTelemetry();
    unawaited(_refreshScraplingProbe());
  }

  Future<void> _refreshCacheBytesOnDisk() async {
    try {
      final bytes = await WebFetchCacheStore.instance.totalBytesOnDisk();
      if (!mounted) return;
      setState(() => _cacheBytesOnDisk = bytes);
    } catch (e, st) {
      silentLog('settings_web_fetch_editor', '刷新磁盘缓存大小', e, st);
      if (!mounted) return;
      setState(() => _cacheBytesOnDisk = 0);
    }
  }

  Future<void> _refreshTelemetry() async {
    if (_telemetryLoading) return;
    setState(() => _telemetryLoading = true);
    try {
      final (calls, stats, history) = await (
        WebFetchTelemetryStore.instance.recentCalls(),
        WebFetchTelemetryStore.instance.engineStats(),
        WebFetchTelemetryStore.instance.engineHistory(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _recentCalls = calls;
        _engineStats = stats;
        _engineHistory = history;
        _telemetryLoading = false;
      });
    } catch (e, st) {
      silentLog('settings_web_fetch_editor', '刷新遥测数据', e, st);
      if (!mounted) return;
      setState(() => _telemetryLoading = false);
    }
  }

  Future<void> _refreshScraplingProbe([
    AiWebFetchScraplingSettings? settings,
  ]) async {
    if (_scraplingProbeLoading) return;
    setState(() => _scraplingProbeLoading = true);
    final effectiveSettings = settings ?? widget.value.scrapling;
    try {
      final probe = await context
          .read<AiSessionController>()
          .toolRuntimeService
          .probeWebFetchScrapling(settings: effectiveSettings);
      if (!mounted) return;
      setState(() {
        _scraplingProbe = probe;
        _scraplingProbeLoading = false;
      });
    } catch (e, st) {
      silentLog('settings_web_fetch_editor', '刷新 Scrapling 探测状态', e, st);
      if (!mounted) return;
      setState(() {
        _scraplingProbe = WebFetchScraplingProbeStatus(
          ready: false,
          code: 'probe_failed',
          detail: '$e',
          updatedAt: DateTime.now().toUtc(),
        );
        _scraplingProbeLoading = false;
      });
    }
  }

  Future<void> _resetScraplingRuntime() async {
    try {
      await context
          .read<AiSessionController>()
          .toolRuntimeService
          .resetWebFetchScrapling();
    } catch (e, st) {
      silentLog('settings_web_fetch_editor', '重置 Scrapling 运行时', e, st);
    }
    await _refreshScraplingProbe();
  }

  Future<void> _installScraplingRuntime() async {
    if (_scraplingRuntimeBusy) return;
    setState(() => _scraplingRuntimeBusy = true);
    try {
      final result = await showAnimatedDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _ScraplingRuntimeDialog(
          action: _ScraplingRuntimeAction.install,
          settings: widget.value.scrapling,
        ),
      );
      if (!mounted) return;
      if (result == true) {
        showOpenHandSuccessSnack(
          context,
          openHandLocalizedText(
            context,
            zh: 'Scrapling 运行时安装完成',
            en: 'Scrapling runtime installed',
          ),
        );
      }
    } catch (e, st) {
      silentLog('settings_web_fetch_editor', '安装 Scrapling 运行时', e, st);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(context, zh: '安装失败：$e', en: 'Install failed: $e'),
      );
    } finally {
      if (mounted) setState(() => _scraplingRuntimeBusy = false);
    }
    await _refreshScraplingProbe();
  }

  Future<void> _uninstallScraplingRuntime() async {
    if (_scraplingRuntimeBusy) return;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '卸载 Scrapling 运行时？',
        en: 'Uninstall Scrapling runtime?',
      ),
      message: openHandLocalizedText(
        context,
        zh: '会执行 python -m pip uninstall -y scrapling，并重置当前 Scrapling 本地运行时。',
        en: 'This runs python -m pip uninstall -y scrapling and resets the current local Scrapling runtime.',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandLocalizedText(context, zh: '确认卸载', en: 'Uninstall'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _scraplingRuntimeBusy = true);
    try {
      final result = await showAnimatedDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _ScraplingRuntimeDialog(
          action: _ScraplingRuntimeAction.uninstall,
          settings: widget.value.scrapling,
        ),
      );
      if (!mounted) return;
      if (result == true) {
        showOpenHandSuccessSnack(
          context,
          openHandLocalizedText(
            context,
            zh: 'Scrapling 运行时已卸载',
            en: 'Scrapling runtime uninstalled',
          ),
        );
      }
    } catch (e, st) {
      silentLog('settings_web_fetch_editor', '卸载 Scrapling 运行时', e, st);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '卸载失败：$e',
          en: 'Uninstall failed: $e',
        ),
      );
    } finally {
      if (mounted) setState(() => _scraplingRuntimeBusy = false);
    }
    await _refreshScraplingProbe();
  }

  Future<void> _confirmAndClearTelemetry() async {
    if (_clearingTelemetry) return;
    final confirmed = await _confirmClearToolTelemetry(
      context: context,
      toolLabel: 'WebFetch',
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearingTelemetry = true);
    try {
      await WebFetchTelemetryStore.instance.clearAll();
    } catch (e, st) {
      silentLog('settings_web_fetch_editor', '清空遥测数据', e, st);
    }
    if (!mounted) return;
    setState(() => _clearingTelemetry = false);
    await _refreshTelemetry();
  }

  Future<void> _exportTelemetry({required bool asCsv}) async {
    if (_exportingTelemetry) return;
    setState(() => _exportingTelemetry = true);
    try {
      await _exportToolTelemetry<WebFetchCallLog>(
        context: context,
        logTag: 'Web 抓取设置',
        fileStem: 'webfetch',
        asCsv: asCsv,
        loadCalls: () => WebFetchTelemetryStore.instance.recentCalls(
          limit: WebFetchTelemetryStore.maxRecentCalls,
        ),
        encodeJson: _callsToJson,
        encodeCsv: _callsToCsv,
      );
    } finally {
      if (mounted) setState(() => _exportingTelemetry = false);
    }
  }

  String _callsToJson(List<WebFetchCallLog> calls) {
    return _encodeJsonList(calls.map((c) => c.toJson()));
  }

  String _callsToCsv(List<WebFetchCallLog> calls) {
    final buf = StringBuffer();
    buf.writeln(
      'timestamp_ms,timestamp_iso,url,cache_status,success,total_duration_ms,'
      'content_chars,fallback_used,winning_engine,error_message,per_engine',
    );
    for (final c in calls) {
      final iso = DateTime.fromMillisecondsSinceEpoch(
        c.timestampMs,
      ).toIso8601String();
      final pe = c.perEngine
          .map(
            (p) =>
                '${p.kind.name}:${p.success ? "ok" : "fail"}/${p.elapsedMs}ms/${p.contentBytes}B',
          )
          .join(';');
      buf.writeln(
        _csvRow([
          c.timestampMs,
          iso,
          c.url,
          c.cacheStatus,
          c.success,
          c.totalDurationMs,
          c.contentChars,
          c.fallbackUsed,
          c.winningEngine?.name,
          c.errorMessage,
          pe,
        ]),
      );
    }
    return buf.toString();
  }

  Future<void> _resetEngineCooldown(AiWebFetchEngineKind kind) async {
    try {
      await WebFetchTelemetryStore.instance.clearEngineCooldown(kind);
    } catch (e, st) {
      silentLog('settings_web_fetch_editor', '重置引擎冷却状态', e, st);
    }
    await _refreshTelemetry();
  }

  @override
  void didUpdateWidget(covariant _WebFetchSettingsEditor old) {
    super.didUpdateWidget(old);
    _syncControllerValue(
      _resultCountController,
      old.value.resultCount,
      widget.value.resultCount,
    );
    _syncControllerValue(
      _cacheTtlController,
      old.value.cacheTtlSeconds,
      widget.value.cacheTtlSeconds,
    );
    _syncControllerValue(
      _cacheMaxBytesController,
      old.value.cacheMaxBytes,
      widget.value.cacheMaxBytes,
      format: formatMegabytesInput,
    );
    _syncControllerValue(
      _parallelWorkersController,
      old.value.parallelWorkers,
      widget.value.parallelWorkers,
    );
  }

  @override
  void dispose() {
    _resultCountController.dispose();
    _cacheTtlController.dispose();
    _cacheMaxBytesController.dispose();
    _parallelWorkersController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndClearCache() async {
    if (_clearingCache) return;
    final confirmed = await _confirmClearLocalCache(
      context: context,
      toolLabel: 'WebFetch',
      titleZhVerb: '清理',
      titleEnVerb: 'Clear',
      contentZh: '将立即删除所有已落盘的正文文件与映射索引 (index.json)，后续相同关键词需要重新发起网络搜索。',
      contentEn:
          'All persisted body files and the mapping index (index.json) will be deleted immediately. Future hits with the same query will need a fresh online search.',
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearingCache = true);
    try {
      await WebFetchCacheStore.instance.clearAll();
    } catch (e, st) {
      silentLog('settings_web_fetch_editor', '清空本地缓存', e, st);
    }
    if (!mounted) return;
    setState(() => _clearingCache = false);
    await _refreshCacheBytesOnDisk();
    if (!mounted) return;
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: 'WebFetch 本地缓存已清空',
        en: 'WebFetch local cache cleared',
      ),
      duration: kOpenHandMotion1800,
    );
  }

  void _emit(AiWebFetchSettings next) => widget.onChanged(next);

  void _reorderEngines(int oldIndex, int newIndex) {
    _emit(
      widget.value.copyWith(
        engines: _reorderedCopy(widget.value.engines, oldIndex, newIndex),
      ),
    );
  }

  void _updateEngine(int index, AiWebFetchEngineConfig next) {
    final list = List<AiWebFetchEngineConfig>.from(widget.value.engines);
    list[index] = next;
    _emit(widget.value.copyWith(engines: list));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final v = widget.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        Text(
          openHandLocalizedText(
            context,
            zh: 'WebFetch 专属配置',
            en: 'WebFetch Settings',
          ),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          openHandLocalizedText(
            context,
            zh:
                'WebFetch 内建工具会按以下顺序调用启用的引擎并行抓取目标 URL,'
                '取首个有效结果作为页面正文返回给模型。',
            en:
                'WebFetch fans out URL fetches across the engines below; '
                'the first non-empty extracted body wins.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),

        _WebEngineDispatchControls(
          featureName: 'WebFetch',
          resultCountController: _resultCountController,
          defaultResultCount: AiWebFetchSettings.defaultResultCount,
          minResultCount: AiWebFetchSettings.minResultCount,
          maxResultCount: AiWebFetchSettings.maxResultCount,
          onResultCountChanged: (value) =>
              _emit(v.copyWith(resultCount: value)),
          parallel: v.parallel,
          onParallelChanged: (value) => _emit(v.copyWith(parallel: value)),
          parallelWorkersController: _parallelWorkersController,
          minParallelWorkers: AiWebFetchSettings.minParallelWorkers,
          maxParallelWorkers: AiWebFetchSettings.maxParallelWorkers,
          onParallelWorkersChanged: (value) =>
              _emit(v.copyWith(parallelWorkers: value)),
        ),
        const SizedBox(height: 14),

        // ── 本地持久化缓存 ──
        Text(
          openHandLocalizedText(context, zh: '本地缓存', en: 'Local Cache'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          openHandLocalizedText(
            context,
            zh:
                '相同 URL 与 prompt 抓取后的正文会写入本地磁盘 (~/.openhand/cache/web_fetch/)，'
                '后续在 TTL 内复用直接返回，零网络消耗。容量上限按 LRU 淘汰。',
            en:
                'Hits with the same URL/prompt persist to disk '
                '(~/.openhand/cache/web_fetch/) and are reused within TTL. '
                'Old entries evict on cap.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _buildWebEngineCacheFields(
          context: context,
          ttlController: _cacheTtlController,
          maxBytesController: _cacheMaxBytesController,
          defaultTtlSeconds: AiWebFetchSettings.defaultCacheTtlSeconds,
          minTtlSeconds: AiWebFetchSettings.minCacheTtlSeconds,
          maxTtlSeconds: AiWebFetchSettings.maxCacheTtlSeconds,
          defaultMaxBytes: AiWebFetchSettings.defaultCacheMaxBytes,
          minMaxBytes: AiWebFetchSettings.minCacheMaxBytes,
          maxMaxBytes: AiWebFetchSettings.maxCacheMaxBytes,
          currentMaxBytes: v.cacheMaxBytes,
          onTtlChanged: (value) => _emit(v.copyWith(cacheTtlSeconds: value)),
          onMaxBytesChanged: (value) => _emit(v.copyWith(cacheMaxBytes: value)),
        ),
        const SizedBox(height: 10),
        _buildToolCacheActions(
          context: context,
          bytesOnDisk: _cacheBytesOnDisk,
          clearing: _clearingCache,
          onRefresh: _refreshCacheBytesOnDisk,
          onClear: _confirmAndClearCache,
        ),
        const SizedBox(height: 16),

        // 引擎列表。
        Text(
          openHandLocalizedText(context, zh: '抓取引擎', en: 'Fetch Engines'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          openHandLocalizedText(
            context,
            zh:
                '拖拽卡片调整顺序；启用至少一个引擎；若全部禁用则自动启用 '
                'Bing/DuckDuckGo 兜底。Scrapling/Jina 均按开关配置执行。',
            en:
                'Drag cards to reorder; enable at least one. '
                'If all are disabled, Bing/DuckDuckGo fallback kicks in. '
                'Scrapling/Jina run only when enabled.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          physics: const NeverScrollableScrollPhysics(),
          proxyDecorator: (child, index, animation) =>
              _settingsTransparentReorderProxy(
                context,
                child,
                index,
                animation,
              ),
          itemCount: v.engines.length,
          onReorder: _reorderEngines,
          itemBuilder: (ctx, idx) {
            final cfg = v.engines[idx];
            if (cfg.kind == AiWebFetchEngineKind.scrapling) {
              return _ScraplingSettingsCard(
                key: ValueKey(cfg.kind),
                index: idx,
                config: cfg,
                settings: v.scrapling,
                probe: _scraplingProbe,
                loading: _scraplingProbeLoading,
                runtimeBusy: _scraplingRuntimeBusy,
                onEngineChanged: (next) => _updateEngine(idx, next),
                onSettingsChanged: (next) {
                  _emit(v.copyWith(scrapling: next));
                  unawaited(_refreshScraplingProbe(next));
                },
                onRefresh: _refreshScraplingProbe,
                onResetRuntime: _resetScraplingRuntime,
                onInstallRuntime: _installScraplingRuntime,
                onUninstallRuntime: _uninstallScraplingRuntime,
              );
            }
            return _WebFetchEngineCard(
              key: ValueKey(cfg.kind),
              index: idx,
              config: cfg,
              availableModels: widget.availableModels,
              onChanged: (next) => _updateEngine(idx, next),
            );
          },
        ),

        const SizedBox(height: 16),
        ..._buildWebEngineResilienceSettingsSection(
          context: context,
          theme: theme,
          colorScheme: colorScheme,
          resilience: v.resilience,
          onChanged: (resilience) => _emit(v.copyWith(resilience: resilience)),
        ),

        const SizedBox(height: 16),
        ..._buildTelemetrySection(context, theme, colorScheme, v),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 遥测界面（调用日志和引擎健康度）
  // ───────────────────────────────────────────────────────────────────────────
  List<Widget> _buildTelemetrySection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AiWebFetchSettings v,
  ) {
    final hasData = _recentCalls.isNotEmpty || _engineStats.isNotEmpty;
    return [
      ..._buildToolTelemetryHeader(
        context: context,
        description: openHandLocalizedText(
          context,
          zh:
              '近期 50 条 WebFetch 调用与每引擎累计成功率、平均耗时、累计字节；'
              '数据持久化在 ~/.openhand/cache/web_fetch/telemetry/。',
          en:
              'Recent 50 WebFetch invocations plus per-engine cumulative '
              'success-rate / avg latency / total hits. Persisted under '
              '~/.openhand/cache/web_fetch/telemetry/.',
        ),
        hasData: hasData,
        hasCalls: _recentCalls.isNotEmpty,
        loading: _telemetryLoading,
        clearing: _clearingTelemetry,
        exporting: _exportingTelemetry,
        onExportJson: () => _exportTelemetry(asCsv: false),
        onExportCsv: () => _exportTelemetry(asCsv: true),
        onRefresh: _refreshTelemetry,
        onClear: _confirmAndClearTelemetry,
      ),
      const SizedBox(height: 8),
      ..._buildToolTelemetryBody(
        context: context,
        loading: _telemetryLoading,
        emptyMessage: openHandLocalizedText(
          context,
          zh: '暂无调用记录。下一次 WebFetch 调用结束后会自动记录。',
          en:
              'No calls recorded yet. The next WebFetch invocation '
              'will be logged automatically.',
        ),
        engineRows: _engineStats.entries
            .map(
              (entry) => _buildEngineStatRow(context, entry.key, entry.value),
            )
            .toList(growable: false),
        callRows: _recentCalls
            .take(_maxToolTelemetryCallRows)
            .map((call) => _buildCallLogRow(context, call))
            .toList(growable: false),
        totalCallCount: _recentCalls.length,
      ),
    ];
  }

  Widget _buildEngineStatRow(
    BuildContext context,
    AiWebFetchEngineKind kind,
    WebFetchEngineStat stat,
  ) {
    return _buildToolEngineStatRow<WebFetchEngineSample>(
      context: context,
      engineName: kind.name,
      successRate: stat.successRate,
      summary: openHandLocalizedText(
        context,
        zh: '${stat.totalCalls} 次 · 平均 ${stat.avgDurationMs.toStringAsFixed(0)}ms · 累计 ${stat.totalBytes} 字节',
        en: '${stat.totalCalls} calls · avg ${stat.avgDurationMs.toStringAsFixed(0)}ms · ${stat.totalBytes} bytes',
      ),
      lastError: stat.lastError,
      inCooldown: stat.isInCooldown(),
      cooldownUntilMs: stat.cooldownUntilMs,
      quotaError: stat.lastQuotaError,
      onResetCooldown: () => _resetEngineCooldown(kind),
      samples: _engineHistory[kind] ?? const <WebFetchEngineSample>[],
    );
  }

  Widget _buildCallLogRow(BuildContext context, WebFetchCallLog call) {
    return _buildToolCallLogRow(
      context: context,
      timestampMs: call.timestampMs,
      cacheStatus: call.cacheStatus,
      title: call.url,
      summary: openHandLocalizedText(
        context,
        zh:
            '${call.success ? "成功" : "失败"} · ${call.totalDurationMs}ms · ${call.contentChars} 字'
            '${call.fallbackUsed ? " · fallback" : ""}'
            '${call.errorMessage != null ? " · ${call.errorMessage}" : ""}',
        en:
            '${call.success ? "ok" : "fail"} · ${call.totalDurationMs}ms · ${call.contentChars} chars'
            '${call.fallbackUsed ? " · fallback" : ""}'
            '${call.errorMessage != null ? " · ${call.errorMessage}" : ""}',
      ),
      engineResults: call.perEngine
          .map(
            (result) => (
              label:
                  '${result.kind.name}:${result.success ? "✓${result.contentBytes}B" : "✗"}/${result.elapsedMs}ms',
              success: result.success,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ScraplingSettingsCard extends StatefulWidget {
  const _ScraplingSettingsCard({
    required super.key,
    required this.index,
    required this.config,
    required this.settings,
    required this.probe,
    required this.loading,
    required this.runtimeBusy,
    required this.onEngineChanged,
    required this.onSettingsChanged,
    required this.onRefresh,
    required this.onResetRuntime,
    required this.onInstallRuntime,
    required this.onUninstallRuntime,
  });

  final int index;
  final AiWebFetchEngineConfig config;
  final AiWebFetchScraplingSettings settings;
  final WebFetchScraplingProbeStatus probe;
  final bool loading;
  final bool runtimeBusy;
  final ValueChanged<AiWebFetchEngineConfig> onEngineChanged;
  final ValueChanged<AiWebFetchScraplingSettings> onSettingsChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onResetRuntime;
  final Future<void> Function() onInstallRuntime;
  final Future<void> Function() onUninstallRuntime;

  @override
  State<_ScraplingSettingsCard> createState() => _ScraplingSettingsCardState();
}

class _ScraplingSettingsCardState extends State<_ScraplingSettingsCard> {
  late TextEditingController _pythonController;
  late TextEditingController _startupController;
  late TextEditingController _requestController;
  late TextEditingController _installController;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _pythonController = TextEditingController(
      text: widget.settings.pythonExecutable ?? '',
    );
    _startupController = TextEditingController(
      text: '${widget.settings.startupTimeoutSeconds}',
    );
    _requestController = TextEditingController(
      text: '${widget.settings.requestTimeoutSeconds}',
    );
    _installController = TextEditingController(
      text: '${widget.settings.installTimeoutSeconds}',
    );
  }

  @override
  void didUpdateWidget(covariant _ScraplingSettingsCard old) {
    super.didUpdateWidget(old);
    if (old.settings.pythonExecutable != widget.settings.pythonExecutable &&
        _pythonController.text != (widget.settings.pythonExecutable ?? '')) {
      _pythonController.text = widget.settings.pythonExecutable ?? '';
    }
    if (old.settings.startupTimeoutSeconds !=
            widget.settings.startupTimeoutSeconds &&
        _startupController.text != '${widget.settings.startupTimeoutSeconds}') {
      _startupController.text = '${widget.settings.startupTimeoutSeconds}';
    }
    if (old.settings.requestTimeoutSeconds !=
            widget.settings.requestTimeoutSeconds &&
        _requestController.text != '${widget.settings.requestTimeoutSeconds}') {
      _requestController.text = '${widget.settings.requestTimeoutSeconds}';
    }
    if (old.settings.installTimeoutSeconds !=
            widget.settings.installTimeoutSeconds &&
        _installController.text != '${widget.settings.installTimeoutSeconds}') {
      _installController.text = '${widget.settings.installTimeoutSeconds}';
    }
  }

  @override
  void dispose() {
    _pythonController.dispose();
    _startupController.dispose();
    _requestController.dispose();
    _installController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final probe = widget.probe;
    final (chipBg, chipFg, chipLabel) = _scraplingProbePresentation(
      context,
      probe,
    );
    return _ToolEngineCardShell(
      key: ValueKey('engine-${widget.config.kind.name}-${widget.index}'),
      index: widget.index,
      name: 'Scrapling',
      subtitle: openHandLocalizedText(
        context,
        zh: '本地 Python 抓取桥接 · 复杂页面更稳',
        en: 'Local Python bridge · better on complex pages',
      ),
      enabled: widget.config.enabled,
      onEnabledChanged: (value) =>
          widget.onEngineChanged(widget.config.copyWith(enabled: value)),
      expanded: _expanded,
      onExpandedChanged: (value) => setState(() => _expanded = value),
      headerTrailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          chipLabel,
          style: theme.textTheme.bodySmall?.copyWith(color: chipFg),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            probe.detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if ((probe.pythonExecutable ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              openHandLocalizedText(
                context,
                zh: 'Python: ${probe.pythonExecutable}',
                en: 'Python: ${probe.pythonExecutable}',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFamily: kOpenHandMonospaceFontFamily,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: widget.loading || widget.runtimeBusy
                    ? null
                    : widget.onRefresh,
                icon: widget.loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(
                  openHandLocalizedText(context, zh: '检测环境', en: 'Probe'),
                ),
              ),
              TextButton.icon(
                onPressed: widget.runtimeBusy || widget.loading
                    ? null
                    : widget.onResetRuntime,
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '重置运行时',
                    en: 'Reset Runtime',
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: widget.runtimeBusy || widget.loading
                    ? null
                    : widget.onInstallRuntime,
                icon: widget.runtimeBusy && !widget.probe.runtimeInstalled
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 16),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '安装运行时',
                    en: 'Install Runtime',
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: widget.runtimeBusy || widget.loading
                    ? null
                    : widget.onUninstallRuntime,
                icon: widget.runtimeBusy && widget.probe.runtimeInstalled
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded, size: 16),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '卸载运行时',
                    en: 'Uninstall Runtime',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pythonController,
            decoration: InputDecoration(
              labelText: openHandLocalizedText(
                context,
                zh: 'Python 可执行文件（留空自动发现）',
                en: 'Python executable (blank = auto detect)',
              ),
            ),
            onChanged: (value) {
              final trimmed = value.trim();
              widget.onSettingsChanged(
                widget.settings.copyWith(
                  pythonExecutable: trimmed.isEmpty ? null : trimmed,
                  clearPythonExecutable: trimmed.isEmpty,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startupController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: openHandLocalizedText(
                      context,
                      zh: '启动超时（秒）',
                      en: 'Startup timeout (s)',
                    ),
                  ),
                  onChanged: (value) {
                    widget.onSettingsChanged(
                      widget.settings.copyWith(
                        startupTimeoutSeconds: clampedIntFromText(
                          value,
                          fallback: AiWebFetchScraplingSettings
                              .defaultStartupTimeoutSeconds,
                          min: AiWebFetchScraplingSettings
                              .minStartupTimeoutSeconds,
                          max: AiWebFetchScraplingSettings
                              .maxStartupTimeoutSeconds,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _requestController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: openHandLocalizedText(
                      context,
                      zh: '请求超时（秒）',
                      en: 'Request timeout (s)',
                    ),
                  ),
                  onChanged: (value) {
                    widget.onSettingsChanged(
                      widget.settings.copyWith(
                        requestTimeoutSeconds: clampedIntFromText(
                          value,
                          fallback: AiWebFetchScraplingSettings
                              .defaultRequestTimeoutSeconds,
                          min: AiWebFetchScraplingSettings
                              .minRequestTimeoutSeconds,
                          max: AiWebFetchScraplingSettings
                              .maxRequestTimeoutSeconds,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _installController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: openHandLocalizedText(
                context,
                zh: '安装/卸载超时（秒）',
                en: 'Install/Uninstall timeout (s)',
              ),
            ),
            onChanged: (value) {
              widget.onSettingsChanged(
                widget.settings.copyWith(
                  installTimeoutSeconds: clampedIntFromText(
                    value,
                    fallback: AiWebFetchScraplingSettings
                        .defaultInstallTimeoutSeconds,
                    min: AiWebFetchScraplingSettings.minInstallTimeoutSeconds,
                    max: AiWebFetchScraplingSettings.maxInstallTimeoutSeconds,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            openHandLocalizedText(
              context,
              zh: '默认使用当前 Python 执行 pip install / uninstall Scrapling 运行时；仍保持现有全局弹窗与设置页动效风格。',
              en: 'Uses the current Python to run pip install / uninstall for the Scrapling runtime while preserving the existing dialog and settings motion style.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

(Color, Color, String) _scraplingProbePresentation(
  BuildContext context,
  WebFetchScraplingProbeStatus probe,
) {
  final colorScheme = Theme.of(context).colorScheme;
  if (probe.ready) {
    return (
      colorScheme.primaryContainer,
      colorScheme.onPrimaryContainer,
      openHandLocalizedText(context, zh: '已就绪', en: 'Ready'),
    );
  }
  return switch (probe.code) {
    'python_not_found' => (
      colorScheme.errorContainer,
      colorScheme.onErrorContainer,
      openHandLocalizedText(context, zh: '缺少 Python', en: 'No Python'),
    ),
    'scrapling_not_installed' || 'scrapling_fetchers_missing' => (
      colorScheme.tertiaryContainer,
      colorScheme.onTertiaryContainer,
      openHandLocalizedText(context, zh: '缺少依赖', en: 'Missing deps'),
    ),
    'probe_failed' || 'bridge_exception' => (
      colorScheme.errorContainer,
      colorScheme.onErrorContainer,
      openHandLocalizedText(context, zh: '探测失败', en: 'Probe failed'),
    ),
    'not_checked' => (
      colorScheme.surfaceContainerHighest,
      colorScheme.onSurfaceVariant,
      openHandLocalizedText(context, zh: '未检测', en: 'Not checked'),
    ),
    _ => (
      colorScheme.surfaceContainerHighest,
      colorScheme.onSurfaceVariant,
      openHandLocalizedText(context, zh: '未就绪', en: 'Not ready'),
    ),
  };
}

String _fetchEngineDisplayName(AiWebFetchEngineKind kind) {
  return switch (kind) {
    AiWebFetchEngineKind.firecrawl => 'Firecrawl',
    AiWebFetchEngineKind.scrapling => 'Scrapling',
    AiWebFetchEngineKind.jina => 'Jina Reader',
    AiWebFetchEngineKind.tavily => 'Tavily Extract',
    AiWebFetchEngineKind.exa => 'Exa Contents',
    AiWebFetchEngineKind.kimi => 'Kimi (Moonshot)',
    AiWebFetchEngineKind.baidu => '百度 AI 搜索',
    AiWebFetchEngineKind.linkup => 'Linkup',
    AiWebFetchEngineKind.bocha => '博查 Bocha',
    AiWebFetchEngineKind.duckduckgo => 'DuckDuckGo',
    AiWebFetchEngineKind.grok => 'xAI Grok',
    AiWebFetchEngineKind.gemini => 'Google Gemini',
    AiWebFetchEngineKind.bing => 'Bing',
  };
}

class _WebFetchEngineCard extends StatefulWidget {
  const _WebFetchEngineCard({
    required super.key,
    required this.index,
    required this.config,
    required this.availableModels,
    required this.onChanged,
  });

  final int index;
  final AiWebFetchEngineConfig config;
  final List<AiModelConfig> availableModels;
  final ValueChanged<AiWebFetchEngineConfig> onChanged;

  @override
  State<_WebFetchEngineCard> createState() => _WebFetchEngineCardState();
}

class _WebFetchEngineCardState extends State<_WebFetchEngineCard> {
  late TextEditingController _jinaConnectionTimeoutController;
  late TextEditingController _jinaResponseTimeoutController;

  @override
  void initState() {
    super.initState();
    _jinaConnectionTimeoutController = TextEditingController(
      text: '${widget.config.connectionTimeoutSeconds}',
    );
    _jinaResponseTimeoutController = TextEditingController(
      text: '${widget.config.responseTimeoutSeconds}',
    );
  }

  @override
  void didUpdateWidget(covariant _WebFetchEngineCard old) {
    super.didUpdateWidget(old);
    syncTextControllerText(
      _jinaConnectionTimeoutController,
      '${widget.config.connectionTimeoutSeconds}',
      previous: '${old.config.connectionTimeoutSeconds}',
    );
    syncTextControllerText(
      _jinaResponseTimeoutController,
      '${widget.config.responseTimeoutSeconds}',
      previous: '${old.config.responseTimeoutSeconds}',
    );
  }

  @override
  void dispose() {
    _jinaConnectionTimeoutController.dispose();
    _jinaResponseTimeoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    return _ToolEngineCard(
      key: ValueKey('engine-${cfg.kind.name}-${widget.index}'),
      index: widget.index,
      name: _fetchEngineDisplayName(cfg.kind),
      subtitle: _fetchEngineSubtitle(context, cfg.kind),
      enabled: cfg.enabled,
      onEnabledChanged: (value) =>
          widget.onChanged(cfg.copyWith(enabled: value)),
      weight: cfg.weight,
      minWeight: AiWebFetchEngineConfig.minWeight,
      maxWeight: AiWebFetchEngineConfig.maxWeight,
      onWeightChanged: (value) => widget.onChanged(cfg.copyWith(weight: value)),
      maxRetries: cfg.maxRetries,
      maxRetriesUpperBound: AiWebFetchEngineConfig.maxRetriesUpperBound,
      onMaxRetriesChanged: (value) =>
          widget.onChanged(cfg.copyWith(maxRetries: value)),
      truncationChars: cfg.truncationChars,
      defaultTruncationChars: AiWebFetchEngineConfig.defaultTruncationChars,
      minTruncationChars: AiWebFetchEngineConfig.minTruncationChars,
      maxTruncationChars: AiWebFetchEngineConfig.maxTruncationChars,
      onTruncationCharsChanged: (value) =>
          widget.onChanged(cfg.copyWith(truncationChars: value)),
      requiresApiKey: cfg.kind.requiresApiKey,
      apiKey: cfg.apiKey,
      apiKeyHint: _fetchApiKeyHint(cfg.kind),
      onApiKeyChanged: (value) => widget.onChanged(
        cfg.copyWith(apiKey: value, clearApiKey: value == null),
      ),
      availableModels: widget.availableModels,
      providerConfigId: cfg.providerConfigId,
      onProviderConfigIdChanged: _fetchCanLinkProvider(cfg.kind)
          ? (id) => widget.onChanged(
              cfg.copyWith(
                providerConfigId: id,
                clearProviderConfigId: id == null,
              ),
            )
          : null,
      extrasBeforeApiKey: [
        if (cfg.kind == AiWebFetchEngineKind.jina) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildEngineNumberField(
                  controller: _jinaConnectionTimeoutController,
                  label: openHandLocalizedText(
                    context,
                    zh: '连接超时 (秒)',
                    en: 'Connect Timeout (s)',
                  ),
                  helperText:
                      '${AiWebFetchEngineConfig.minConnectionTimeoutSeconds}-'
                      '${AiWebFetchEngineConfig.maxConnectionTimeoutSeconds}',
                  fallback:
                      AiWebFetchEngineConfig.defaultConnectionTimeoutSeconds,
                  min: AiWebFetchEngineConfig.minConnectionTimeoutSeconds,
                  max: AiWebFetchEngineConfig.maxConnectionTimeoutSeconds,
                  onChanged: (value) => widget.onChanged(
                    cfg.copyWith(connectionTimeoutSeconds: value),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEngineNumberField(
                  controller: _jinaResponseTimeoutController,
                  label: openHandLocalizedText(
                    context,
                    zh: '响应超时 (秒)',
                    en: 'Response Timeout (s)',
                  ),
                  helperText:
                      '${AiWebFetchEngineConfig.minResponseTimeoutSeconds}-'
                      '${AiWebFetchEngineConfig.maxResponseTimeoutSeconds}',
                  fallback:
                      AiWebFetchEngineConfig.defaultResponseTimeoutSeconds,
                  min: AiWebFetchEngineConfig.minResponseTimeoutSeconds,
                  max: AiWebFetchEngineConfig.maxResponseTimeoutSeconds,
                  onChanged: (value) => widget.onChanged(
                    cfg.copyWith(responseTimeoutSeconds: value),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

bool _fetchCanLinkProvider(AiWebFetchEngineKind kind) {
  return kind == AiWebFetchEngineKind.kimi ||
      kind == AiWebFetchEngineKind.grok ||
      kind == AiWebFetchEngineKind.gemini;
}

String? _fetchApiKeyHint(AiWebFetchEngineKind kind) {
  return switch (kind) {
    AiWebFetchEngineKind.firecrawl => 'fc-...',
    AiWebFetchEngineKind.scrapling => null,
    AiWebFetchEngineKind.jina => null,
    AiWebFetchEngineKind.tavily => 'tvly-...',
    AiWebFetchEngineKind.exa => 'exa-...',
    AiWebFetchEngineKind.kimi => 'sk-... (Moonshot)',
    AiWebFetchEngineKind.baidu => 'api_key:secret_key',
    AiWebFetchEngineKind.linkup => 'lk-...',
    AiWebFetchEngineKind.bocha => 'sk-... (Bocha)',
    AiWebFetchEngineKind.grok => 'xai-...',
    AiWebFetchEngineKind.gemini => 'AIza...',
    _ => null,
  };
}

String _fetchEngineSubtitle(BuildContext context, AiWebFetchEngineKind kind) {
  return switch (kind) {
    AiWebFetchEngineKind.firecrawl => openHandLocalizedText(
      context,
      zh: '专业网页抓取 · 渲染 JS',
      en: 'Pro scrape · renders JS',
    ),
    AiWebFetchEngineKind.scrapling => openHandLocalizedText(
      context,
      zh: '本地 Python 抓取 · 复杂页面更稳',
      en: 'Local Python scrape · better on complex pages',
    ),
    AiWebFetchEngineKind.jina => openHandLocalizedText(
      context,
      zh: 'r.jina.ai · Markdown 正文',
      en: 'r.jina.ai · Markdown content',
    ),
    AiWebFetchEngineKind.tavily => openHandLocalizedText(
      context,
      zh: 'Tavily Extract · advanced',
      en: 'Tavily Extract · advanced',
    ),
    AiWebFetchEngineKind.exa => openHandLocalizedText(
      context,
      zh: 'Exa Contents · livecrawl',
      en: 'Exa Contents · livecrawl',
    ),
    AiWebFetchEngineKind.kimi => openHandLocalizedText(
      context,
      zh: 'Moonshot 内置联网 · 以 URL 为查询',
      en: 'Moonshot web tool · query=URL',
    ),
    AiWebFetchEngineKind.baidu => openHandLocalizedText(
      context,
      zh: '百度 AI 搜索 · 以 URL 为查询',
      en: 'Baidu AI search · query=URL',
    ),
    AiWebFetchEngineKind.linkup => openHandLocalizedText(
      context,
      zh: 'Linkup deep · 以 URL 为查询',
      en: 'Linkup deep · query=URL',
    ),
    AiWebFetchEngineKind.bocha => openHandLocalizedText(
      context,
      zh: '博查 · 以 URL 为查询',
      en: 'Bocha · query=URL',
    ),
    AiWebFetchEngineKind.duckduckgo => openHandLocalizedText(
      context,
      zh: '无 Key · HTTP 直连兜底',
      en: 'No-key · direct HTTP fallback',
    ),
    AiWebFetchEngineKind.grok => openHandLocalizedText(
      context,
      zh: 'xAI Live Search · 引用解析 URL',
      en: 'xAI Live · citations',
    ),
    AiWebFetchEngineKind.gemini => openHandLocalizedText(
      context,
      zh: 'Google Grounding · URL 摘录',
      en: 'Google Grounding · URL excerpt',
    ),
    AiWebFetchEngineKind.bing => openHandLocalizedText(
      context,
      zh: '默认兜底 · HTTP 直连',
      en: 'Default fallback · direct HTTP',
    ),
  };
}

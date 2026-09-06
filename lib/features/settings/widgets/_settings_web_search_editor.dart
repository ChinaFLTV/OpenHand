part of 'settings_view.dart';

// WebSearch 工具的子代理、引擎和摘要设置。
// 仅当 _BuiltinToolEditorDialog 编辑的是 AiBuiltinToolKind.webSearch 时挂载。

class _WebSearchSettingsEditor extends StatefulWidget {
  const _WebSearchSettingsEditor({
    required this.value,
    required this.onChanged,
    required this.availableModels,
    required this.recentModelSelections,
  });

  final AiWebSearchSettings value;
  final ValueChanged<AiWebSearchSettings> onChanged;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;

  @override
  State<_WebSearchSettingsEditor> createState() =>
      _WebSearchSettingsEditorState();
}

class _WebSearchSettingsEditorState extends State<_WebSearchSettingsEditor>
    with
        _ToolTelemetryPanelHost<
          _WebSearchSettingsEditor,
          WebSearchCallLog,
          AiWebSearchEngineKind,
          WebSearchEngineStat,
          WebSearchEngineSample
        > {
  late final _WebEngineEditorControllers _commonControllers;
  late TextEditingController _summaryMinController;
  late TextEditingController _summaryMaxController;

  @override
  void initState() {
    super.initState();
    _commonControllers = _WebEngineEditorControllers(
      resultCount: widget.value.resultCount,
      cacheTtlSeconds: widget.value.cacheTtlSeconds,
      cacheMaxBytes: widget.value.cacheMaxBytes,
      parallelWorkers: widget.value.parallelWorkers,
    );
    _summaryMinController = TextEditingController(
      text: '${widget.value.summaryMinChars}',
    );
    _summaryMaxController = TextEditingController(
      text: '${widget.value.summaryMaxChars}',
    );
    _refreshCacheBytesOnDisk();
    _refreshTelemetry();
  }

  @override
  String get _telemetryLogTag => 'settings_web_search_editor';

  @override
  String get _telemetryToolLabel => 'WebSearch';

  @override
  String get _telemetryExportLogTag => 'Web 搜索设置';

  @override
  String get _telemetryFileStem => 'websearch';

  @override
  Future<int> _loadCacheBytesOnDisk() {
    return WebSearchCacheStore.instance.totalBytesOnDisk();
  }

  @override
  Future<
    (
      List<WebSearchCallLog>,
      Map<AiWebSearchEngineKind, WebSearchEngineStat>,
      Map<AiWebSearchEngineKind, List<WebSearchEngineSample>>,
    )
  >
  _loadTelemetry() {
    return (
      WebSearchTelemetryStore.instance.recentCalls(),
      WebSearchTelemetryStore.instance.engineStats(),
      WebSearchTelemetryStore.instance.engineHistory(),
    ).wait;
  }

  @override
  Future<void> _clearTelemetryStore() {
    return WebSearchTelemetryStore.instance.clearAll();
  }

  @override
  Future<void> _clearEngineCooldown(AiWebSearchEngineKind kind) {
    return WebSearchTelemetryStore.instance.clearEngineCooldown(kind);
  }

  @override
  Future<List<WebSearchCallLog>> _loadCallsForExport() {
    return WebSearchTelemetryStore.instance.recentCalls(
      limit: webEngineDefaultRecentCalls,
    );
  }

  @override
  String _callsToJson(List<WebSearchCallLog> calls) {
    return _encodeJsonList(calls.map((c) => c.toJson()));
  }

  @override
  String _callsToCsv(List<WebSearchCallLog> calls) {
    final buf = StringBuffer();
    buf.writeln(
      'timestamp_ms,timestamp_iso,query,cache_status,success,total_duration_ms,'
      'merged_hit_count,fallback_used,summary_chars,error_message,model_protocol,'
      'model_id,per_engine',
    );
    for (final c in calls) {
      final iso = DateTime.fromMillisecondsSinceEpoch(
        c.timestampMs,
      ).toIso8601String();
      final pe = c.perEngine
          .map(
            (p) =>
                '${p.kind.name}:${p.success ? "ok" : "fail"}/${p.elapsedMs}ms/${p.hitCount}h',
          )
          .join(';');
      buf.writeln(
        encodeCsvRow([
          c.timestampMs,
          iso,
          c.query,
          c.cacheStatus,
          c.success,
          c.totalDurationMs,
          c.mergedHitCount,
          c.fallbackUsed,
          c.summaryChars,
          c.errorMessage,
          c.modelProtocol,
          c.modelId,
          pe,
        ]),
      );
    }
    return buf.toString();
  }

  @override
  void didUpdateWidget(covariant _WebSearchSettingsEditor old) {
    super.didUpdateWidget(old);
    _commonControllers.sync(
      oldResultCount: old.value.resultCount,
      resultCount: widget.value.resultCount,
      oldCacheTtlSeconds: old.value.cacheTtlSeconds,
      cacheTtlSeconds: widget.value.cacheTtlSeconds,
      oldCacheMaxBytes: old.value.cacheMaxBytes,
      cacheMaxBytes: widget.value.cacheMaxBytes,
      oldParallelWorkers: old.value.parallelWorkers,
      parallelWorkers: widget.value.parallelWorkers,
    );
    _syncControllerValue(
      _summaryMinController,
      old.value.summaryMinChars,
      widget.value.summaryMinChars,
    );
    _syncControllerValue(
      _summaryMaxController,
      old.value.summaryMaxChars,
      widget.value.summaryMaxChars,
    );
  }

  @override
  void dispose() {
    _commonControllers.dispose();
    _summaryMinController.dispose();
    _summaryMaxController.dispose();
    super.dispose();
  }

  @override
  Future<void> _clearCacheStore() => WebSearchCacheStore.instance.clearAll();

  @override
  String get _cacheClearContentZh =>
      '将立即删除所有已落盘的 summary 文件与映射索引 (index.json)，后续相同关键词需要重新发起网络搜索。';

  @override
  String get _cacheClearContentEn =>
      'All persisted summary files and the mapping index (index.json) will be deleted immediately. Future hits with the same query will need a fresh online search.';

  void _emit(AiWebSearchSettings next) => widget.onChanged(next);

  Future<void> _pickFixedModel() async {
    // 实时获取最新模型列表，避免设置变更后数据不同步
    final settingsController = Provider.of<SettingsController?>(
      context,
      listen: false,
    );
    final latestModels = settingsController?.aiModels ?? widget.availableModels;
    final latestRecent =
        settingsController?.recentModelSelections ??
        widget.recentModelSelections;
    final picked = await showModelSearchSelector(
      context: context,
      models: latestModels,
      recentSelections: latestRecent,
      selectedConfigId: widget.value.fixedModelProviderConfigId,
      selectedModelId: widget.value.fixedModelId,
    );
    if (!mounted || picked == null) return;
    _emit(
      widget.value.copyWith(
        fixedModelProviderConfigId: picked.$1,
        fixedModelId: picked.$2,
      ),
    );
  }

  String _modelLabel() {
    final cfgId = widget.value.fixedModelProviderConfigId;
    final modelId = widget.value.fixedModelId;
    if (cfgId == null || modelId == null) {
      return openHandLocalizedText(context, zh: '未选择', en: 'Not selected');
    }
    final match = widget.availableModels
        .where((m) => m.id == cfgId)
        .firstOrNull;
    if (match == null) {
      return '${openHandLocalizedText(context, zh: '已失效', en: 'Stale')} · $modelId';
    }
    return '${match.providerLabel} · $modelId';
  }

  void _reorderEngines(int oldIndex, int newIndex) {
    _emit(
      widget.value.copyWith(
        engines: _reorderedCopy(widget.value.engines, oldIndex, newIndex),
      ),
    );
  }

  void _updateEngine(int index, AiWebSearchEngineConfig next) {
    _emit(
      widget.value.copyWith(
        engines: _replacedCopy(widget.value.engines, index, next),
      ),
    );
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
            zh: 'WebSearch 专属配置',
            en: 'WebSearch Settings',
          ),
          style: theme.textTheme.titleMedium,
        ),
        kOpenHandGap4,
        Text(
          openHandLocalizedText(
            context,
            zh:
                'WebSearch 内建工具会以 sub-agent 模式按以下顺序调用启用的搜索引擎,'
                '汇总结果交由模型生成最终 summary。',
            en:
                'WebSearch runs as a sub-agent: it calls the enabled engines '
                'below in order, then asks a model to summarize the merged hits.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap14,

        // 子代理模型。
        Text(
          openHandLocalizedText(context, zh: 'Summary 模型', en: 'Summary Model'),
          style: theme.textTheme.titleSmall,
        ),
        kOpenHandGap8,
        SegmentedButton<AiWebSearchModelMode>(
          segments: [
            ButtonSegment(
              value: AiWebSearchModelMode.followSession,
              icon: const Icon(Icons.link_rounded),
              label: Text(
                openHandLocalizedText(
                  context,
                  zh: '跟随会话',
                  en: 'Follow session',
                ),
                softWrap: false,
              ),
            ),
            ButtonSegment(
              value: AiWebSearchModelMode.fixed,
              icon: const Icon(Icons.push_pin_rounded),
              label: Text(
                openHandLocalizedText(context, zh: '固定模型', en: 'Fixed'),
                softWrap: false,
              ),
            ),
          ],
          selected: {v.modelMode},
          onSelectionChanged: (s) {
            if (s.isNotEmpty) {
              _emit(v.copyWith(modelMode: s.first));
            }
          },
        ),
        kOpenHandGap8,
        if (v.modelMode == AiWebSearchModelMode.fixed) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome_rounded),
                  onPressed: _pickFixedModel,
                  label: Text(_modelLabel(), overflow: TextOverflow.ellipsis),
                ),
              ),
              if (v.fixedModelProviderConfigId != null) ...[
                kOpenHandHGap8,
                IconButton(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '清除',
                    zhHant: '清除',
                    en: 'Clear',
                    fr: 'Effacer',
                    de: 'Löschen',
                    ja: '消去',
                  ),
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () => _emit(v.copyWith(clearFixedModel: true)),
                ),
              ],
            ],
          ),
        ],
        kOpenHandGap14,

        _WebEngineDispatchControls(
          featureName: 'WebSearch',
          resultCountController: _commonControllers.resultCount,
          defaultResultCount: AiWebSearchSettings.defaultResultCount,
          minResultCount: AiWebSearchSettings.minResultCount,
          maxResultCount: AiWebSearchSettings.maxResultCount,
          onResultCountChanged: (value) =>
              _emit(v.copyWith(resultCount: value)),
          parallel: v.parallel,
          onParallelChanged: (value) => _emit(v.copyWith(parallel: value)),
          parallelWorkersController: _commonControllers.parallelWorkers,
          onParallelWorkersChanged: (value) =>
              _emit(v.copyWith(parallelWorkers: value)),
        ),
        kOpenHandGap14,

        // 摘要细节与风格。
        Row(
          children: [
            Expanded(
              child: AnimatedDropdownButtonFormField<AiWebSearchSummaryDetail>(
                initialValue: v.summaryDetail,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: 'Summary 简洁程度',
                    en: 'Summary Detail',
                  ),
                ),
                items: AiWebSearchSummaryDetail.values
                    .map(
                      (d) => DropdownMenuItem(
                        value: d,
                        child: Text(_summaryDetailLabel(context, d)),
                      ),
                    )
                    .toList(),
                onChanged: (d) {
                  if (d != null) _emit(v.copyWith(summaryDetail: d));
                },
              ),
            ),
            kOpenHandHGap12,
            Expanded(
              child: AnimatedDropdownButtonFormField<AiWebSearchSummaryStyle>(
                initialValue: v.summaryStyle,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: 'Summary 语言风格',
                    en: 'Summary Style',
                  ),
                ),
                items: AiWebSearchSummaryStyle.values
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(_summaryStyleLabel(context, s)),
                      ),
                    )
                    .toList(),
                onChanged: (s) {
                  if (s != null) _emit(v.copyWith(summaryStyle: s));
                },
              ),
            ),
          ],
        ),
        kOpenHandGap12,
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _summaryMinController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: 'Summary 最少字数',
                    en: 'Summary Min Chars',
                  ),
                  helperText: openHandLocalizedText(
                    context,
                    zh: '0 表示不限制下界',
                    en: '0 = no lower bound',
                  ),
                ),
                onChanged: (s) {
                  _emit(
                    v.copyWith(
                      summaryMinChars: clampedIntFromText(
                        s,
                        fallback: 0,
                        min: 0,
                        max: AiWebSearchSettings.maxSummaryMaxChars,
                      ),
                    ),
                  );
                },
              ),
            ),
            kOpenHandHGap12,
            Expanded(
              child: TextField(
                controller: _summaryMaxController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: 'Summary 最大字数',
                    en: 'Summary Max Chars',
                  ),
                  helperText: openHandLocalizedText(
                    context,
                    zh: '0 表示不限上界 (谨慎)',
                    en: '0 = no upper bound (use with care)',
                  ),
                ),
                onChanged: (s) {
                  _emit(
                    v.copyWith(
                      summaryMaxChars: clampedIntFromText(
                        s,
                        fallback: 0,
                        min: 0,
                        max: AiWebSearchSettings.maxSummaryMaxChars,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        kOpenHandGap16,

        // ── 本地持久化缓存 ──
        Text(
          _settingsLocalCacheLabel(context),
          style: theme.textTheme.titleSmall,
        ),
        kOpenHandGap4,
        Text(
          openHandLocalizedText(
            context,
            zh:
                '相同关键词与设置的搜索 summary 会写入本地磁盘 (~/.openhand/cache/web_search/)，'
                '后续在 TTL 内复用直接返回，零网络消耗。容量上限按 LRU 淘汰。',
            en:
                'Hits with the same query/settings persist to disk '
                '(~/.openhand/cache/web_search/) and are reused within TTL. '
                'Old entries evict on cap.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap8,
        _buildWebEngineCacheFields(
          context: context,
          ttlController: _commonControllers.cacheTtl,
          maxBytesController: _commonControllers.cacheMaxBytes,
          defaultTtlSeconds: AiWebSearchSettings.defaultCacheTtlSeconds,
          currentMaxBytes: v.cacheMaxBytes,
          onTtlChanged: (value) => _emit(v.copyWith(cacheTtlSeconds: value)),
          onMaxBytesChanged: (value) => _emit(v.copyWith(cacheMaxBytes: value)),
        ),
        kOpenHandGap10,
        _buildCacheActionsRow(context),
        kOpenHandGap16,

        ...buildWebEngineListSection(
          context: context,
          theme: theme,
          colorScheme: colorScheme,
          title: openHandLocalizedText(
            context,
            zh: '搜索引擎',
            en: 'Search Engines',
          ),
          description: openHandLocalizedText(
            context,
            zh:
                '拖拽卡片调整顺序;启用至少一个引擎,'
                '若全部禁用则自动启用 Bing/DuckDuckGo 兜底。',
            en:
                'Drag cards to reorder; enable at least one. '
                'If all are disabled, Bing/DuckDuckGo fallback kicks in.',
          ),
          itemCount: v.engines.length,
          onReorder: _reorderEngines,
          itemBuilder: (ctx, idx) {
            final cfg = v.engines[idx];
            return _WebSearchEngineCard(
              key: ValueKey(cfg.kind),
              index: idx,
              config: cfg,
              availableModels: widget.availableModels,
              onChanged: (next) => _updateEngine(idx, next),
            );
          },
        ),

        kOpenHandGap16,
        ..._buildWebEngineResilienceSettingsSection(
          context: context,
          theme: theme,
          colorScheme: colorScheme,
          resilience: v.resilience,
          onChanged: (resilience) => _emit(v.copyWith(resilience: resilience)),
        ),

        kOpenHandGap16,
        ..._buildTelemetrySection(context),
      ],
    );
  }

  List<Widget> _buildTelemetrySection(BuildContext context) {
    return _buildTelemetryPanel(
      context: context,
      description: openHandLocalizedText(
        context,
        zh:
            '近期 50 条 WebSearch 调用与每引擎累计成功率、平均耗时、命中数；'
            '数据持久化在 ~/.openhand/cache/web_search/telemetry/。',
        en:
            'Recent 50 WebSearch invocations plus per-engine cumulative '
            'success-rate / avg latency / total hits. Persisted under '
            '~/.openhand/cache/web_search/telemetry/.',
      ),
      emptyMessage: openHandLocalizedText(
        context,
        zh: '暂无调用记录。下一次 WebSearch 调用结束后会自动记录。',
        en:
            'No calls recorded yet. The next WebSearch invocation '
            'will be logged automatically.',
      ),
      buildEngineRow: (kind, stat) => _buildEngineStatRow(context, kind, stat),
      buildCallRow: (call) => _buildCallLogRow(context, call),
    );
  }

  Widget _buildEngineStatRow(
    BuildContext context,
    AiWebSearchEngineKind kind,
    WebSearchEngineStat stat,
  ) {
    return _buildToolEngineStatRow<WebSearchEngineSample>(
      context: context,
      engineName: kind.name,
      successRate: stat.successRate,
      summary: openHandLocalizedText(
        context,
        zh: '${stat.totalCalls} 次 · 平均 ${stat.avgDurationMs.toStringAsFixed(0)}ms · 累计 ${stat.totalHits} 命中',
        en: '${stat.totalCalls} calls · avg ${stat.avgDurationMs.toStringAsFixed(0)}ms · ${stat.totalHits} hits',
      ),
      lastError: stat.lastError,
      inCooldown: stat.isInCooldown(),
      cooldownUntilMs: stat.cooldownUntilMs,
      quotaError: stat.lastQuotaError,
      onResetCooldown: () => _resetEngineCooldown(kind),
      samples: _engineHistory[kind] ?? const <WebSearchEngineSample>[],
    );
  }

  Widget _buildCallLogRow(BuildContext context, WebSearchCallLog call) {
    return _buildToolCallLogRow(
      context: context,
      timestampMs: call.timestampMs,
      cacheStatus: call.cacheStatus,
      title: call.query,
      summary: openHandLocalizedText(
        context,
        zh:
            '${call.success ? "成功" : "失败"} · ${call.totalDurationMs}ms · ${call.mergedHitCount} 条结果 · 摘要 ${call.summaryChars} 字'
            '${call.fallbackUsed ? " · fallback" : ""}'
            '${call.errorMessage != null ? " · ${call.errorMessage}" : ""}',
        en:
            '${call.success ? "ok" : "fail"} · ${call.totalDurationMs}ms · ${call.mergedHitCount} hits · summary ${call.summaryChars} chars'
            '${call.fallbackUsed ? " · fallback" : ""}'
            '${call.errorMessage != null ? " · ${call.errorMessage}" : ""}',
      ),
      engineResults: call.perEngine
          .map(
            (result) => (
              label:
                  '${result.kind.name}:${result.success ? "✓${result.hitCount}" : "✗"}/${result.elapsedMs}ms',
              success: result.success,
            ),
          )
          .toList(growable: false),
    );
  }
}

String _summaryDetailLabel(BuildContext context, AiWebSearchSummaryDetail d) {
  return switch (d) {
    AiWebSearchSummaryDetail.brief => openHandLocalizedText(
      context,
      zh: '简明扼要',
      en: 'Brief',
    ),
    AiWebSearchSummaryDetail.balanced => openHandLocalizedText(
      context,
      zh: '中规中矩',
      en: 'Balanced',
    ),
    AiWebSearchSummaryDetail.comprehensive => openHandLocalizedText(
      context,
      zh: '全面详细',
      en: 'Comprehensive',
    ),
    AiWebSearchSummaryDetail.exhaustive => openHandLocalizedText(
      context,
      zh: '细致入微',
      en: 'Exhaustive',
    ),
  };
}

String _summaryStyleLabel(BuildContext context, AiWebSearchSummaryStyle s) {
  return switch (s) {
    AiWebSearchSummaryStyle.neutral => openHandLocalizedText(
      context,
      zh: '中性百科',
      en: 'Neutral',
    ),
    AiWebSearchSummaryStyle.technical => openHandLocalizedText(
      context,
      zh: '技术分析',
      en: 'Technical',
    ),
    AiWebSearchSummaryStyle.casual => openHandLocalizedText(
      context,
      zh: '通俗轻松',
      en: 'Casual',
    ),
    AiWebSearchSummaryStyle.structured => openHandStructuredLabel(context),
  };
}

String _engineDisplayName(AiWebSearchEngineKind kind) {
  return switch (kind) {
    AiWebSearchEngineKind.tavily => 'Tavily',
    AiWebSearchEngineKind.exa => 'Exa',
    AiWebSearchEngineKind.kimi => 'Kimi (Moonshot)',
    AiWebSearchEngineKind.baidu => '百度 AI 搜索',
    AiWebSearchEngineKind.linkup => 'Linkup',
    AiWebSearchEngineKind.bocha => '博查 Bocha',
    AiWebSearchEngineKind.duckduckgo => 'DuckDuckGo',
    AiWebSearchEngineKind.grok => 'xAI Grok',
    AiWebSearchEngineKind.gemini => 'Google Gemini',
    AiWebSearchEngineKind.bing => 'Bing',
    AiWebSearchEngineKind.searxng => 'SearXNG / Startpage',
  };
}

class _WebSearchEngineCard extends StatefulWidget {
  const _WebSearchEngineCard({
    required super.key,
    required this.index,
    required this.config,
    required this.availableModels,
    required this.onChanged,
  });

  final int index;
  final AiWebSearchEngineConfig config;
  final List<AiModelConfig> availableModels;
  final ValueChanged<AiWebSearchEngineConfig> onChanged;

  @override
  State<_WebSearchEngineCard> createState() => _WebSearchEngineCardState();
}

class _WebSearchEngineCardState extends State<_WebSearchEngineCard> {
  late TextEditingController _endpointController;

  @override
  void initState() {
    super.initState();
    _endpointController = TextEditingController(
      text: widget.config.endpointOverride ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _WebSearchEngineCard old) {
    super.didUpdateWidget(old);
    syncTextControllerText(
      _endpointController,
      widget.config.endpointOverride ?? '',
      previous: old.config.endpointOverride ?? '',
    );
  }

  @override
  void dispose() {
    _endpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    return _ToolEngineCard(
      // key 只认引擎种类，不掺位置下标：外层列表可拖拽排序，掺了下标后每次
      // 拖动都会让位移过的卡片换 key、State 连同展开态与未提交的输入一起被销毁。
      key: ValueKey('engine-${cfg.kind.name}'),
      index: widget.index,
      name: _engineDisplayName(cfg.kind),
      subtitle: _engineSubtitle(context, cfg.kind),
      enabled: cfg.enabled,
      onEnabledChanged: (value) =>
          widget.onChanged(cfg.copyWith(enabled: value)),
      weight: cfg.weight,
      minWeight: AiWebSearchEngineConfig.minWeight,
      maxWeight: AiWebSearchEngineConfig.maxWeight,
      onWeightChanged: (value) => widget.onChanged(cfg.copyWith(weight: value)),
      maxRetries: cfg.maxRetries,
      maxRetriesUpperBound: AiWebSearchEngineConfig.maxRetriesUpperBound,
      onMaxRetriesChanged: (value) =>
          widget.onChanged(cfg.copyWith(maxRetries: value)),
      truncationChars: cfg.truncationChars,
      defaultTruncationChars: AiWebSearchEngineConfig.defaultTruncationChars,
      minTruncationChars: AiWebSearchEngineConfig.minTruncationChars,
      maxTruncationChars: AiWebSearchEngineConfig.maxTruncationChars,
      onTruncationCharsChanged: (value) =>
          widget.onChanged(cfg.copyWith(truncationChars: value)),
      requiresApiKey: cfg.kind.requiresApiKey,
      apiKey: cfg.apiKey,
      apiKeyHint: _apiKeyHint(cfg.kind),
      onApiKeyChanged: (value) => widget.onChanged(
        cfg.copyWith(apiKey: value, clearApiKey: value == null),
      ),
      availableModels: widget.availableModels,
      providerConfigId: cfg.providerConfigId,
      onProviderConfigIdChanged: _canLinkProvider(cfg.kind)
          ? (id) => widget.onChanged(
              cfg.copyWith(
                providerConfigId: id,
                clearProviderConfigId: id == null,
              ),
            )
          : null,
      extrasAfterApiKey: [
        if (cfg.kind == AiWebSearchEngineKind.searxng) ...[
          kOpenHandGap8,
          TextField(
            controller: _endpointController,
            decoration: InputDecoration(
              labelText: openHandLocalizedText(
                context,
                zh: '实例 Endpoint',
                en: 'Instance Endpoint',
              ),
              hintText: 'https://searxng.example.com',
            ),
            onChanged: (text) {
              final endpoint = nullIfBlank(text);
              widget.onChanged(
                cfg.copyWith(
                  endpointOverride: endpoint,
                  clearEndpointOverride: endpoint == null,
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

bool _canLinkProvider(AiWebSearchEngineKind kind) {
  return kind == AiWebSearchEngineKind.kimi ||
      kind == AiWebSearchEngineKind.grok ||
      kind == AiWebSearchEngineKind.gemini;
}

String? _apiKeyHint(AiWebSearchEngineKind kind) {
  return switch (kind) {
    AiWebSearchEngineKind.tavily => 'tvly-...',
    AiWebSearchEngineKind.exa => 'exa-...',
    AiWebSearchEngineKind.kimi => 'sk-... (Moonshot)',
    AiWebSearchEngineKind.baidu => 'api_key:secret_key',
    AiWebSearchEngineKind.linkup => 'lk-...',
    AiWebSearchEngineKind.bocha => 'sk-... (Bocha)',
    AiWebSearchEngineKind.grok => 'xai-...',
    AiWebSearchEngineKind.gemini => 'AIza...',
    _ => null,
  };
}

String _engineSubtitle(BuildContext context, AiWebSearchEngineKind kind) {
  return switch (kind) {
    AiWebSearchEngineKind.tavily => openHandLocalizedText(
      context,
      zh: '专业 AI 搜索 · 高精度',
      en: 'Pro AI search · high precision',
    ),
    AiWebSearchEngineKind.exa => openHandLocalizedText(
      context,
      zh: '神经搜索 · 内容深度索引',
      en: 'Neural search · deep content',
    ),
    AiWebSearchEngineKind.kimi => openHandLocalizedText(
      context,
      zh: 'Moonshot 内置联网工具',
      en: 'Moonshot built-in web tool',
    ),
    AiWebSearchEngineKind.baidu => openHandLocalizedText(
      context,
      zh: '中文友好 · 百度生态',
      en: 'CN-friendly · Baidu ecosystem',
    ),
    AiWebSearchEngineKind.linkup => openHandLocalizedText(
      context,
      zh: '欧洲 AI 搜索 API',
      en: 'EU AI search API',
    ),
    AiWebSearchEngineKind.bocha => openHandLocalizedText(
      context,
      zh: '中文 AI 搜索 · 国内访问稳定',
      en: 'CN AI search · stable in mainland',
    ),
    AiWebSearchEngineKind.duckduckgo => openHandLocalizedText(
      context,
      zh: '无需 Key · HTML 抓取兜底',
      en: 'No-key · HTML scrape fallback',
    ),
    AiWebSearchEngineKind.grok => openHandLocalizedText(
      context,
      zh: 'xAI Live Search · 实时数据',
      en: 'xAI Live Search · realtime',
    ),
    AiWebSearchEngineKind.gemini => openHandLocalizedText(
      context,
      zh: 'Google Grounding · 高质量',
      en: 'Google Grounding · high quality',
    ),
    AiWebSearchEngineKind.bing => openHandLocalizedText(
      context,
      zh: 'HTML 抓取 · 默认兜底',
      en: 'HTML scrape · default fallback',
    ),
    AiWebSearchEngineKind.searxng => openHandLocalizedText(
      context,
      zh: '开源元搜索 · 自托管',
      en: 'OSS meta-search · self-host',
    ),
  };
}

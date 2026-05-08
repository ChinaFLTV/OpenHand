part of 'settings_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WebSearch tool — sub-agent / engines / summary configuration editor.
// 仅当 _BuiltinToolEditorDialog 编辑的是 AiBuiltinToolKind.webSearch 时挂载。
// ─────────────────────────────────────────────────────────────────────────────

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

class _WebSearchSettingsEditorState extends State<_WebSearchSettingsEditor> {
  late TextEditingController _resultCountController;
  late TextEditingController _summaryMinController;
  late TextEditingController _summaryMaxController;
  late TextEditingController _cacheTtlController;
  late TextEditingController _cacheMaxBytesController;

  @override
  void initState() {
    super.initState();
    _resultCountController = TextEditingController(
      text: '${widget.value.resultCount}',
    );
    _summaryMinController = TextEditingController(
      text: '${widget.value.summaryMinChars}',
    );
    _summaryMaxController = TextEditingController(
      text: '${widget.value.summaryMaxChars}',
    );
    _cacheTtlController = TextEditingController(
      text: '${widget.value.cacheTtlSeconds}',
    );
    _cacheMaxBytesController = TextEditingController(
      text: _bytesToMb(widget.value.cacheMaxBytes),
    );
  }

  @override
  void didUpdateWidget(covariant _WebSearchSettingsEditor old) {
    super.didUpdateWidget(old);
    if (old.value.resultCount != widget.value.resultCount &&
        _resultCountController.text != '${widget.value.resultCount}') {
      _resultCountController.text = '${widget.value.resultCount}';
    }
    if (old.value.summaryMinChars != widget.value.summaryMinChars &&
        _summaryMinController.text != '${widget.value.summaryMinChars}') {
      _summaryMinController.text = '${widget.value.summaryMinChars}';
    }
    if (old.value.summaryMaxChars != widget.value.summaryMaxChars &&
        _summaryMaxController.text != '${widget.value.summaryMaxChars}') {
      _summaryMaxController.text = '${widget.value.summaryMaxChars}';
    }
    if (old.value.cacheTtlSeconds != widget.value.cacheTtlSeconds &&
        _cacheTtlController.text != '${widget.value.cacheTtlSeconds}') {
      _cacheTtlController.text = '${widget.value.cacheTtlSeconds}';
    }
    if (old.value.cacheMaxBytes != widget.value.cacheMaxBytes &&
        _cacheMaxBytesController.text !=
            _bytesToMb(widget.value.cacheMaxBytes)) {
      _cacheMaxBytesController.text = _bytesToMb(widget.value.cacheMaxBytes);
    }
  }

  @override
  void dispose() {
    _resultCountController.dispose();
    _summaryMinController.dispose();
    _summaryMaxController.dispose();
    _cacheTtlController.dispose();
    _cacheMaxBytesController.dispose();
    super.dispose();
  }

  static String _bytesToMb(int bytes) {
    if (bytes <= 0) return '0';
    final mb = bytes / (1024 * 1024);
    return mb >= 100
        ? mb.toStringAsFixed(0)
        : (mb >= 10 ? mb.toStringAsFixed(1) : mb.toStringAsFixed(2));
  }

  void _emit(AiWebSearchSettings next) => widget.onChanged(next);

  Future<void> _pickFixedModel() async {
    final picked = await showModelSearchSelector(
      context: context,
      models: widget.availableModels,
      recentSelections: widget.recentModelSelections,
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
      return _localizedText(context, zh: '未选择', en: 'Not selected');
    }
    final match = widget.availableModels
        .where((m) => m.id == cfgId)
        .firstOrNull;
    if (match == null) {
      return '${_localizedText(context, zh: '已失效', en: 'Stale')} · $modelId';
    }
    return '${match.providerLabel} · $modelId';
  }

  void _reorderEngines(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final list = List<AiWebSearchEngineConfig>.from(widget.value.engines);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    _emit(widget.value.copyWith(engines: list));
  }

  void _updateEngine(int index, AiWebSearchEngineConfig next) {
    final list = List<AiWebSearchEngineConfig>.from(widget.value.engines);
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
          _localizedText(context, zh: 'WebSearch 专属配置', en: 'WebSearch Settings'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          _localizedText(
            context,
            zh: 'WebSearch 内建工具会以 sub-agent 模式按以下顺序调用启用的搜索引擎,'
                '汇总结果交由模型生成最终 summary。',
            en: 'WebSearch runs as a sub-agent: it calls the enabled engines '
                'below in order, then asks a model to summarize the merged hits.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),

        // ── Sub-agent model ──
        Text(
          _localizedText(context, zh: 'Summary 模型', en: 'Summary Model'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SegmentedButton<AiWebSearchModelMode>(
          segments: [
            ButtonSegment(
              value: AiWebSearchModelMode.followSession,
              icon: const Icon(Icons.link_rounded),
              label: Text(
                _localizedText(
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
                _localizedText(context, zh: '固定模型', en: 'Fixed'),
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
        const SizedBox(height: 8),
        if (v.modelMode == AiWebSearchModelMode.fixed) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome_rounded),
                  onPressed: _pickFixedModel,
                  label: Text(
                    _modelLabel(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (v.fixedModelProviderConfigId != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _localizedText(context, zh: '清除', en: 'Clear'),
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () =>
                      _emit(v.copyWith(clearFixedModel: true)),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 14),

        // ── Result count ──
        TextField(
          controller: _resultCountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: _localizedText(
              context,
              zh: '结果数量 (${AiWebSearchSettings.minResultCount}-'
                  '${AiWebSearchSettings.maxResultCount})',
              en: 'Result Count (${AiWebSearchSettings.minResultCount}-'
                  '${AiWebSearchSettings.maxResultCount})',
            ),
            helperText: _localizedText(
              context,
              zh: '默认 ${AiWebSearchSettings.defaultResultCount},'
                  '控制 WebSearch 返回给模型的条目个数。',
              en: 'Default ${AiWebSearchSettings.defaultResultCount}; '
                  'caps how many hits are forwarded to the summary model.',
            ),
          ),
          onChanged: (s) {
            final parsed = int.tryParse(s.trim());
            if (parsed == null) return;
            final clamped = parsed.clamp(
              AiWebSearchSettings.minResultCount,
              AiWebSearchSettings.maxResultCount,
            );
            _emit(v.copyWith(resultCount: clamped));
          },
        ),
        const SizedBox(height: 14),

        // ── Parallel switch + workers ──
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _localizedText(
                    context,
                    zh: '并行调度引擎',
                    en: 'Parallel Engines',
                  ),
                ),
                subtitle: Text(
                  _localizedText(
                    context,
                    zh: '启用后通过信号量限流并行调用多个引擎,提速明显;关闭后串行依次调用。',
                    en: 'When on, engines fan out under a semaphore-bounded '
                        'concurrency limit; off = strict serial.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: v.parallel,
                onChanged: (b) => _emit(v.copyWith(parallel: b)),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: TextField(
                enabled: v.parallel,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                controller: TextEditingController(
                  text: '${v.parallelWorkers}',
                ),
                decoration: InputDecoration(
                  labelText: _localizedText(
                    context,
                    zh: 'Workers (${AiWebSearchSettings.minParallelWorkers}-'
                        '${AiWebSearchSettings.maxParallelWorkers})',
                    en: 'Workers (${AiWebSearchSettings.minParallelWorkers}-'
                        '${AiWebSearchSettings.maxParallelWorkers})',
                  ),
                ),
                onChanged: (s) {
                  final parsed = int.tryParse(s.trim());
                  if (parsed == null) return;
                  _emit(
                    v.copyWith(
                      parallelWorkers: parsed.clamp(
                        AiWebSearchSettings.minParallelWorkers,
                        AiWebSearchSettings.maxParallelWorkers,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Summary detail / style ──
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<AiWebSearchSummaryDetail>(
                initialValue: v.summaryDetail,
                decoration: InputDecoration(
                  labelText: _localizedText(
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
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<AiWebSearchSummaryStyle>(
                initialValue: v.summaryStyle,
                decoration: InputDecoration(
                  labelText: _localizedText(
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
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _summaryMinController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: _localizedText(
                    context,
                    zh: 'Summary 最少字数',
                    en: 'Summary Min Chars',
                  ),
                  helperText: _localizedText(
                    context,
                    zh: '0 表示不限制下界',
                    en: '0 = no lower bound',
                  ),
                ),
                onChanged: (s) {
                  final parsed = int.tryParse(s.trim()) ?? 0;
                  _emit(
                    v.copyWith(
                      summaryMinChars: parsed.clamp(
                        0,
                        AiWebSearchSettings.maxSummaryMaxChars,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _summaryMaxController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: _localizedText(
                    context,
                    zh: 'Summary 最大字数',
                    en: 'Summary Max Chars',
                  ),
                  helperText: _localizedText(
                    context,
                    zh: '0 表示不限上界 (谨慎)',
                    en: '0 = no upper bound (use with care)',
                  ),
                ),
                onChanged: (s) {
                  final parsed = int.tryParse(s.trim()) ?? 0;
                  _emit(
                    v.copyWith(
                      summaryMaxChars: parsed.clamp(
                        0,
                        AiWebSearchSettings.maxSummaryMaxChars,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── 本地持久化缓存 ──
        Text(
          _localizedText(context, zh: '本地缓存', en: 'Local Cache'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          _localizedText(
            context,
            zh: '相同关键词与设置的搜索 summary 会写入本地磁盘 (~/.openhand/cache/web_search/)，'
                '后续在 TTL 内复用直接返回，零网络消耗。容量上限按 LRU 淘汰。',
            en: 'Hits with the same query/settings persist to disk '
                '(~/.openhand/cache/web_search/) and are reused within TTL. '
                'Old entries evict on cap.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cacheTtlController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: _localizedText(
                    context,
                    zh: '缓存 TTL (秒)',
                    en: 'Cache TTL (seconds)',
                  ),
                  helperText: _localizedText(
                    context,
                    zh: '默认 300 秒 = 5 分钟; 设为 0 关闭缓存',
                    en: 'Default 300s (5 min); 0 disables caching',
                  ),
                ),
                onChanged: (s) {
                  final parsed = int.tryParse(s.trim()) ?? 0;
                  _emit(
                    v.copyWith(
                      cacheTtlSeconds: parsed.clamp(
                        AiWebSearchSettings.minCacheTtlSeconds,
                        AiWebSearchSettings.maxCacheTtlSeconds,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _cacheMaxBytesController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _localizedText(
                    context,
                    zh: '缓存上限 (MB)',
                    en: 'Cache Cap (MB)',
                  ),
                  helperText: _localizedText(
                    context,
                    zh: '默认 50 MB; 0 = 不限 (不推荐)',
                    en: 'Default 50 MB; 0 = unlimited (not recommended)',
                  ),
                ),
                onChanged: (s) {
                  final parsed = double.tryParse(s.trim()) ?? 0.0;
                  final bytes = (parsed * 1024 * 1024).round();
                  _emit(
                    v.copyWith(
                      cacheMaxBytes: bytes.clamp(
                        AiWebSearchSettings.minCacheMaxBytes,
                        AiWebSearchSettings.maxCacheMaxBytes,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Engines list ──
        Text(
          _localizedText(context, zh: '搜索引擎', en: 'Search Engines'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          _localizedText(
            context,
            zh: '拖拽卡片调整顺序;启用至少一个引擎,'
                '若全部禁用则自动启用 Bing/DuckDuckGo 兜底。',
            en: 'Drag cards to reorder; enable at least one. '
                'If all are disabled, Bing/DuckDuckGo fallback kicks in.',
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
      ],
    );
  }
}

String _summaryDetailLabel(
  BuildContext context,
  AiWebSearchSummaryDetail d,
) {
  return switch (d) {
    AiWebSearchSummaryDetail.brief => _localizedText(
      context,
      zh: '简明扼要',
      en: 'Brief',
    ),
    AiWebSearchSummaryDetail.balanced => _localizedText(
      context,
      zh: '中规中矩',
      en: 'Balanced',
    ),
    AiWebSearchSummaryDetail.comprehensive => _localizedText(
      context,
      zh: '全面详细',
      en: 'Comprehensive',
    ),
    AiWebSearchSummaryDetail.exhaustive => _localizedText(
      context,
      zh: '细致入微',
      en: 'Exhaustive',
    ),
  };
}

String _summaryStyleLabel(BuildContext context, AiWebSearchSummaryStyle s) {
  return switch (s) {
    AiWebSearchSummaryStyle.neutral => _localizedText(
      context,
      zh: '中性百科',
      en: 'Neutral',
    ),
    AiWebSearchSummaryStyle.technical => _localizedText(
      context,
      zh: '技术分析',
      en: 'Technical',
    ),
    AiWebSearchSummaryStyle.casual => _localizedText(
      context,
      zh: '通俗轻松',
      en: 'Casual',
    ),
    AiWebSearchSummaryStyle.structured => _localizedText(
      context,
      zh: '结构化',
      en: 'Structured',
    ),
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
  late TextEditingController _apiKeyController;
  late TextEditingController _retryController;
  late TextEditingController _truncationController;
  late TextEditingController _endpointController;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.config.apiKey ?? '');
    _retryController = TextEditingController(
      text: '${widget.config.maxRetries}',
    );
    _truncationController = TextEditingController(
      text: '${widget.config.truncationChars}',
    );
    _endpointController = TextEditingController(
      text: widget.config.endpointOverride ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _WebSearchEngineCard old) {
    super.didUpdateWidget(old);
    if (old.config.apiKey != widget.config.apiKey &&
        _apiKeyController.text != (widget.config.apiKey ?? '')) {
      _apiKeyController.text = widget.config.apiKey ?? '';
    }
    if (old.config.maxRetries != widget.config.maxRetries &&
        _retryController.text != '${widget.config.maxRetries}') {
      _retryController.text = '${widget.config.maxRetries}';
    }
    if (old.config.truncationChars != widget.config.truncationChars &&
        _truncationController.text != '${widget.config.truncationChars}') {
      _truncationController.text = '${widget.config.truncationChars}';
    }
    if (old.config.endpointOverride != widget.config.endpointOverride &&
        _endpointController.text != (widget.config.endpointOverride ?? '')) {
      _endpointController.text = widget.config.endpointOverride ?? '';
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _retryController.dispose();
    _truncationController.dispose();
    _endpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cfg = widget.config;
    final name = _engineDisplayName(cfg.kind);

    return Padding(
      key: ValueKey('engine-${cfg.kind.name}-${widget.index}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cfg.enabled
              ? colorScheme.surfaceContainerLow
              : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cfg.enabled
                ? colorScheme.primary.withValues(alpha: 0.4)
                : colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_indicator_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.titleSmall),
                        Text(
                          _engineSubtitle(context, cfg.kind),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _expanded
                        ? _localizedText(context, zh: '收起', en: 'Collapse')
                        : _localizedText(context, zh: '展开', en: 'Expand'),
                    icon: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                  Switch(
                    value: cfg.enabled,
                    onChanged: (v) =>
                        widget.onChanged(cfg.copyWith(enabled: v)),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                Text(
                  _localizedText(
                    context,
                    zh: '权重 ${cfg.weight} (1 = 最低,100 = 最高;影响 summary 偏重)',
                    en: 'Weight ${cfg.weight} (higher = more emphasis in '
                        'summary)',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                Slider(
                  min: AiWebSearchEngineConfig.minWeight.toDouble(),
                  max: AiWebSearchEngineConfig.maxWeight.toDouble(),
                  divisions:
                      AiWebSearchEngineConfig.maxWeight -
                      AiWebSearchEngineConfig.minWeight,
                  value: cfg.weight.toDouble().clamp(
                    AiWebSearchEngineConfig.minWeight.toDouble(),
                    AiWebSearchEngineConfig.maxWeight.toDouble(),
                  ),
                  label: '${cfg.weight}',
                  onChanged: (v) =>
                      widget.onChanged(cfg.copyWith(weight: v.round())),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _retryController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: _localizedText(
                            context,
                            zh: '重试次数',
                            en: 'Max Retries',
                          ),
                        ),
                        onChanged: (s) {
                          final parsed = int.tryParse(s.trim()) ?? 0;
                          widget.onChanged(
                            cfg.copyWith(
                              maxRetries: parsed.clamp(
                                0,
                                AiWebSearchEngineConfig.maxRetriesUpperBound,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _truncationController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: _localizedText(
                            context,
                            zh: '截断阈值 (字符)',
                            en: 'Truncation (chars)',
                          ),
                        ),
                        onChanged: (s) {
                          final parsed =
                              int.tryParse(s.trim()) ??
                              AiWebSearchEngineConfig.defaultTruncationChars;
                          widget.onChanged(
                            cfg.copyWith(
                              truncationChars: parsed.clamp(
                                AiWebSearchEngineConfig.minTruncationChars,
                                AiWebSearchEngineConfig.maxTruncationChars,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                if (cfg.kind.requiresApiKey) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    decoration: InputDecoration(
                      labelText: _localizedText(
                        context,
                        zh: 'API Key',
                        en: 'API Key',
                      ),
                      hintText: _apiKeyHint(cfg.kind),
                    ),
                    obscureText: true,
                    onChanged: (s) {
                      final trimmed = s.trim();
                      widget.onChanged(
                        cfg.copyWith(
                          apiKey: trimmed.isEmpty ? null : trimmed,
                          clearApiKey: trimmed.isEmpty,
                        ),
                      );
                    },
                  ),
                  if (_canLinkProvider(cfg.kind)) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: cfg.providerConfigId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '复用 Provider 的 API Key (可选)',
                          en: 'Reuse Provider API Key (optional)',
                        ),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          child: Text(
                            _localizedText(context, zh: '不复用', en: 'None'),
                          ),
                        ),
                        for (final m in widget.availableModels)
                          DropdownMenuItem<String?>(
                            value: m.id,
                            child: Text(
                              '${m.providerLabel} (${m.protocolType.storageValue})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) => widget.onChanged(
                        cfg.copyWith(
                          providerConfigId: id,
                          clearProviderConfigId: id == null,
                        ),
                      ),
                    ),
                  ],
                ],
                if (cfg.kind == AiWebSearchEngineKind.searxng) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _endpointController,
                    decoration: InputDecoration(
                      labelText: _localizedText(
                        context,
                        zh: '实例 Endpoint',
                        en: 'Instance Endpoint',
                      ),
                      hintText: 'https://searxng.example.com',
                    ),
                    onChanged: (s) {
                      final trimmed = s.trim();
                      widget.onChanged(
                        cfg.copyWith(
                          endpointOverride: trimmed.isEmpty ? null : trimmed,
                          clearEndpointOverride: trimmed.isEmpty,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
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
    AiWebSearchEngineKind.tavily => _localizedText(
      context,
      zh: '专业 AI 搜索 · 高精度',
      en: 'Pro AI search · high precision',
    ),
    AiWebSearchEngineKind.exa => _localizedText(
      context,
      zh: '神经搜索 · 内容深度索引',
      en: 'Neural search · deep content',
    ),
    AiWebSearchEngineKind.kimi => _localizedText(
      context,
      zh: 'Moonshot 内置联网工具',
      en: 'Moonshot built-in web tool',
    ),
    AiWebSearchEngineKind.baidu => _localizedText(
      context,
      zh: '中文友好 · 百度生态',
      en: 'CN-friendly · Baidu ecosystem',
    ),
    AiWebSearchEngineKind.linkup => _localizedText(
      context,
      zh: '欧洲 AI 搜索 API',
      en: 'EU AI search API',
    ),
    AiWebSearchEngineKind.bocha => _localizedText(
      context,
      zh: '中文 AI 搜索 · 国内访问稳定',
      en: 'CN AI search · stable in mainland',
    ),
    AiWebSearchEngineKind.duckduckgo => _localizedText(
      context,
      zh: '无需 Key · HTML 抓取兜底',
      en: 'No-key · HTML scrape fallback',
    ),
    AiWebSearchEngineKind.grok => _localizedText(
      context,
      zh: 'xAI Live Search · 实时数据',
      en: 'xAI Live Search · realtime',
    ),
    AiWebSearchEngineKind.gemini => _localizedText(
      context,
      zh: 'Google Grounding · 高质量',
      en: 'Google Grounding · high quality',
    ),
    AiWebSearchEngineKind.bing => _localizedText(
      context,
      zh: 'HTML 抓取 · 默认兜底',
      en: 'HTML scrape · default fallback',
    ),
    AiWebSearchEngineKind.searxng => _localizedText(
      context,
      zh: '开源元搜索 · 自托管',
      en: 'OSS meta-search · self-host',
    ),
  };
}

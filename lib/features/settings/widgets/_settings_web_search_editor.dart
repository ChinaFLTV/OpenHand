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
  late TextEditingController _parallelWorkersController;

  // 当前磁盘上已经落盘的 WebSearch 缓存字节数，由 [_refreshCacheBytesOnDisk]
  // 异步加载；null 代表尚未读取或读取失败。
  int? _cacheBytesOnDisk;
  bool _clearingCache = false;

  // ── Telemetry (调用日志 + 引擎健康度) ──
  List<WebSearchCallLog> _recentCalls = const [];
  Map<AiWebSearchEngineKind, WebSearchEngineStat> _engineStats = const {};
  Map<AiWebSearchEngineKind, List<WebSearchEngineSample>> _engineHistory =
      const {};
  bool _telemetryLoading = false;
  bool _clearingTelemetry = false;
  bool _exportingTelemetry = false;

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
      text: formatMegabytesInput(widget.value.cacheMaxBytes),
    );
    _parallelWorkersController = TextEditingController(
      text: '${widget.value.parallelWorkers}',
    );
    _refreshCacheBytesOnDisk();
    _refreshTelemetry();
  }

  Future<void> _refreshCacheBytesOnDisk() async {
    try {
      final bytes = await WebSearchCacheStore.instance.totalBytesOnDisk();
      if (!mounted) return;
      setState(() => _cacheBytesOnDisk = bytes);
    } catch (e, st) {
      silentLog('settings.websearch', '_refreshCacheBytesOnDisk', e, st);
      if (!mounted) return;
      setState(() => _cacheBytesOnDisk = 0);
    }
  }

  Future<void> _refreshTelemetry() async {
    if (_telemetryLoading) return;
    setState(() => _telemetryLoading = true);
    try {
      // Three independent reads on the same store: parallelize so the
      // refresh latency is bounded by max(read) instead of sum(read).
      final results = await Future.wait<Object>([
        WebSearchTelemetryStore.instance.recentCalls(),
        WebSearchTelemetryStore.instance.engineStats(),
        WebSearchTelemetryStore.instance.engineHistory(),
      ]);
      final calls = results[0] as List<WebSearchCallLog>;
      final stats =
          results[1] as Map<AiWebSearchEngineKind, WebSearchEngineStat>;
      final history =
          results[2] as Map<AiWebSearchEngineKind, List<WebSearchEngineSample>>;
      if (!mounted) return;
      setState(() {
        _recentCalls = calls;
        _engineStats = stats;
        _engineHistory = history;
        _telemetryLoading = false;
      });
    } catch (e, st) {
      silentLog('settings.websearch', '_refreshTelemetry', e, st);
      if (!mounted) return;
      setState(() => _telemetryLoading = false);
    }
  }

  Future<void> _confirmAndClearTelemetry() async {
    if (_clearingTelemetry) return;
    final confirmed = await _confirmClearToolTelemetry(
      context: context,
      toolLabel: 'WebSearch',
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearingTelemetry = true);
    try {
      await WebSearchTelemetryStore.instance.clearAll();
    } catch (e, st) {
      silentLog('settings.websearch', '_confirmAndClearTelemetry', e, st);
    }
    if (!mounted) return;
    setState(() => _clearingTelemetry = false);
    await _refreshTelemetry();
  }

  Future<void> _exportTelemetry({required bool asCsv}) async {
    if (_exportingTelemetry) return;
    setState(() => _exportingTelemetry = true);
    try {
      await _exportToolTelemetry<WebSearchCallLog>(
        context: context,
        fileStem: 'websearch',
        asCsv: asCsv,
        loadCalls: () => WebSearchTelemetryStore.instance.recentCalls(
          limit: WebSearchTelemetryStore.maxRecentCalls,
        ),
        encodeJson: _callsToJson,
        encodeCsv: _callsToCsv,
      );
    } catch (e, st) {
      silentLog('settings.websearch', '_exportTelemetry', e, st);
      if (!mounted) return;
      OpenHandSnackBar.showError(
        context,
        openHandLocalizedText(context, zh: '导出失败：$e', en: 'Export failed: $e'),
      );
    } finally {
      if (mounted) setState(() => _exportingTelemetry = false);
    }
  }

  String _callsToJson(List<WebSearchCallLog> calls) {
    return _encodeJsonList(calls.map((c) => c.toJson()));
  }

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
        _csvRow([
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

  Future<void> _resetEngineCooldown(AiWebSearchEngineKind kind) async {
    try {
      await WebSearchTelemetryStore.instance.clearEngineCooldown(kind);
    } catch (e, st) {
      silentLog('settings.websearch', '_resetEngineCooldown', e, st);
    }
    await _refreshTelemetry();
  }

  @override
  void didUpdateWidget(covariant _WebSearchSettingsEditor old) {
    super.didUpdateWidget(old);
    if (old.value.resultCount != widget.value.resultCount &&
        _resultCountController.text != '${widget.value.resultCount}') {
      _syncControllerText(
        _resultCountController,
        '${widget.value.resultCount}',
      );
    }
    if (old.value.summaryMinChars != widget.value.summaryMinChars &&
        _summaryMinController.text != '${widget.value.summaryMinChars}') {
      _syncControllerText(
        _summaryMinController,
        '${widget.value.summaryMinChars}',
      );
    }
    if (old.value.summaryMaxChars != widget.value.summaryMaxChars &&
        _summaryMaxController.text != '${widget.value.summaryMaxChars}') {
      _syncControllerText(
        _summaryMaxController,
        '${widget.value.summaryMaxChars}',
      );
    }
    if (old.value.cacheTtlSeconds != widget.value.cacheTtlSeconds &&
        _cacheTtlController.text != '${widget.value.cacheTtlSeconds}') {
      _syncControllerText(
        _cacheTtlController,
        '${widget.value.cacheTtlSeconds}',
      );
    }
    if (old.value.cacheMaxBytes != widget.value.cacheMaxBytes &&
        _cacheMaxBytesController.text !=
            formatMegabytesInput(widget.value.cacheMaxBytes)) {
      _syncControllerText(
        _cacheMaxBytesController,
        formatMegabytesInput(widget.value.cacheMaxBytes),
      );
    }
    if (old.value.parallelWorkers != widget.value.parallelWorkers &&
        _parallelWorkersController.text != '${widget.value.parallelWorkers}') {
      _syncControllerText(
        _parallelWorkersController,
        '${widget.value.parallelWorkers}',
      );
    }
  }

  @override
  void dispose() {
    _resultCountController.dispose();
    _summaryMinController.dispose();
    _summaryMaxController.dispose();
    _cacheTtlController.dispose();
    _cacheMaxBytesController.dispose();
    _parallelWorkersController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndClearCache() async {
    if (_clearingCache) return;
    final confirmed = await _confirmClearLocalCache(
      context: context,
      toolLabel: 'WebSearch',
      titleZhVerb: '清理',
      titleEnVerb: 'Clear',
      contentZh: '将立即删除所有已落盘的 summary 文件与映射索引 (index.json)，后续相同关键词需要重新发起网络搜索。',
      contentEn:
          'All persisted summary files and the mapping index (index.json) will be deleted immediately. Future hits with the same query will need a fresh online search.',
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearingCache = true);
    try {
      await WebSearchCacheStore.instance.clearAll();
    } catch (e, st) {
      silentLog('settings.websearch', '_confirmAndClearCache', e, st);
    }
    if (!mounted) return;
    setState(() => _clearingCache = false);
    await _refreshCacheBytesOnDisk();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      OpenHandSnackBar.showInfoOn(
        context,
        messenger,
        openHandLocalizedText(
          context,
          zh: 'WebSearch 本地缓存已清空',
          en: 'WebSearch local cache cleared',
        ),
        duration: const Duration(milliseconds: 1800),
      );
    }
  }

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
          openHandLocalizedText(
            context,
            zh: 'WebSearch 专属配置',
            en: 'WebSearch Settings',
          ),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
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
        const SizedBox(height: 14),

        // ── Sub-agent model ──
        Text(
          openHandLocalizedText(context, zh: 'Summary 模型', en: 'Summary Model'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 8),
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
                const SizedBox(width: 8),
                IconButton(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '清除',
                    en: 'Clear',
                  ),
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () => _emit(v.copyWith(clearFixedModel: true)),
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
            labelText: openHandLocalizedText(
              context,
              zh:
                  '结果数量 (${AiWebSearchSettings.minResultCount}-'
                  '${AiWebSearchSettings.maxResultCount})',
              en:
                  'Result Count (${AiWebSearchSettings.minResultCount}-'
                  '${AiWebSearchSettings.maxResultCount})',
            ),
            helperText: openHandLocalizedText(
              context,
              zh:
                  '默认 ${AiWebSearchSettings.defaultResultCount},'
                  '控制 WebSearch 返回给模型的条目个数。',
              en:
                  'Default ${AiWebSearchSettings.defaultResultCount}; '
                  'caps how many hits are forwarded to the summary model.',
            ),
          ),
          onChanged: (s) {
            final parsed = optionalIntFromText(s);
            if (parsed == null) return;
            _emit(
              v.copyWith(
                resultCount: parsed
                    .clamp(
                      AiWebSearchSettings.minResultCount,
                      AiWebSearchSettings.maxResultCount,
                    )
                    .toInt(),
              ),
            );
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
                  openHandLocalizedText(
                    context,
                    zh: '并行调度引擎',
                    en: 'Parallel Engines',
                  ),
                ),
                subtitle: Text(
                  openHandLocalizedText(
                    context,
                    zh: '启用后通过信号量限流并行调用多个引擎,提速明显;关闭后串行依次调用。',
                    en:
                        'When on, engines fan out under a semaphore-bounded '
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
                controller: _parallelWorkersController,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh:
                        'Workers (${AiWebSearchSettings.minParallelWorkers}-'
                        '${AiWebSearchSettings.maxParallelWorkers})',
                    en:
                        'Workers (${AiWebSearchSettings.minParallelWorkers}-'
                        '${AiWebSearchSettings.maxParallelWorkers})',
                  ),
                ),
                onChanged: (s) {
                  final parsed = optionalIntFromText(s);
                  if (parsed == null) return;
                  _emit(
                    v.copyWith(
                      parallelWorkers: parsed
                          .clamp(
                            AiWebSearchSettings.minParallelWorkers,
                            AiWebSearchSettings.maxParallelWorkers,
                          )
                          .toInt(),
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
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<AiWebSearchSummaryStyle>(
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
        const SizedBox(height: 12),
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
            const SizedBox(width: 12),
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
        const SizedBox(height: 16),

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
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cacheTtlController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: '缓存 TTL (秒)',
                    en: 'Cache TTL (seconds)',
                  ),
                  helperText: openHandLocalizedText(
                    context,
                    zh: '默认 300 秒 = 5 分钟; 设为 0 关闭缓存',
                    en: 'Default 300s (5 min); 0 disables caching',
                  ),
                ),
                onChanged: (s) {
                  _emit(
                    v.copyWith(
                      cacheTtlSeconds: clampedIntFromText(
                        s,
                        fallback: 0,
                        min: AiWebSearchSettings.minCacheTtlSeconds,
                        max: AiWebSearchSettings.maxCacheTtlSeconds,
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
                  labelText: openHandLocalizedText(
                    context,
                    zh: '缓存上限 (MB)',
                    en: 'Cache Cap (MB)',
                  ),
                  helperText: openHandLocalizedText(
                    context,
                    zh: '默认 50 MB; 0 = 不限 (不推荐)',
                    en: 'Default 50 MB; 0 = unlimited (not recommended)',
                  ),
                ),
                onChanged: (s) {
                  _emit(
                    v.copyWith(
                      cacheMaxBytes: megabytesTextToBytes(
                        s,
                        fallbackBytes: v.cacheMaxBytes,
                        minBytes: AiWebSearchSettings.minCacheMaxBytes,
                        maxBytes: AiWebSearchSettings.maxCacheMaxBytes,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // ── 当前已落盘大小 + 显式清理按钮 ──
        Row(
          children: [
            Expanded(
              child: Text(
                openHandLocalizedText(
                  context,
                  zh: '当前已占用：${formatNullableByteSize(_cacheBytesOnDisk, pendingLabel: '…')}',
                  en: 'On disk: ${formatNullableByteSize(_cacheBytesOnDisk, pendingLabel: '…')}',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _clearingCache ? null : _refreshCacheBytesOnDisk,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                openHandLocalizedText(context, zh: '刷新', en: 'Refresh'),
              ),
            ),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                foregroundColor: colorScheme.onPrimary,
                disabledForegroundColor: colorScheme.onSurface.withValues(
                  alpha: 0.38,
                ),
              ),
              onPressed: _clearingCache ? null : _confirmAndClearCache,
              icon: _clearingCache
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : Icon(
                      Icons.delete_sweep,
                      size: 16,
                      color: colorScheme.onPrimary,
                    ),
              label: Text(
                openHandLocalizedText(
                  context,
                  zh: _clearingCache ? '清理中…' : '清理缓存',
                  en: _clearingCache ? 'Clearing…' : 'Clear Cache',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Engines list ──
        Text(
          openHandLocalizedText(context, zh: '搜索引擎', en: 'Search Engines'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          openHandLocalizedText(
            context,
            zh:
                '拖拽卡片调整顺序;启用至少一个引擎,'
                '若全部禁用则自动启用 Bing/DuckDuckGo 兜底。',
            en:
                'Drag cards to reorder; enable at least one. '
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
            return _WebSearchEngineCard(
              key: ValueKey(cfg.kind),
              index: idx,
              config: cfg,
              availableModels: widget.availableModels,
              onChanged: (next) => _updateEngine(idx, next),
            );
          },
        ),

        const SizedBox(height: 16),
        ..._buildAdvancedSection(context, theme, colorScheme, v),

        const SizedBox(height: 16),
        ..._buildTelemetrySection(context, theme, colorScheme, v),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 高级设置（cooldown 阈值 / 告警 / throttle）
  // ───────────────────────────────────────────────────────────────────────────
  List<Widget> _buildAdvancedSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AiWebSearchSettings v,
  ) {
    return [
      Text(
        openHandLocalizedText(
          context,
          zh: '高级（健壮性）',
          en: 'Advanced (resilience)',
        ),
        style: theme.textTheme.titleSmall,
      ),
      const SizedBox(height: 8),
      // cooldown 三档
      Text(
        openHandLocalizedText(
          context,
          zh: '失败自动降级（cooldown）阈值',
          en: 'Failure auto-cooldown thresholds',
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      _AdvancedCooldownTierRow(
        label: openHandLocalizedText(context, zh: '一级', en: 'Tier 1'),
        failures: v.cooldownTier1Failures,
        seconds: v.cooldownTier1Seconds,
        onChangedFailures: (n) =>
            _updateAdvanced(v.copyWith(cooldownTier1Failures: n)),
        onChangedSeconds: (n) =>
            _updateAdvanced(v.copyWith(cooldownTier1Seconds: n)),
      ),
      _AdvancedCooldownTierRow(
        label: openHandLocalizedText(context, zh: '二级', en: 'Tier 2'),
        failures: v.cooldownTier2Failures,
        seconds: v.cooldownTier2Seconds,
        onChangedFailures: (n) =>
            _updateAdvanced(v.copyWith(cooldownTier2Failures: n)),
        onChangedSeconds: (n) =>
            _updateAdvanced(v.copyWith(cooldownTier2Seconds: n)),
      ),
      _AdvancedCooldownTierRow(
        label: openHandLocalizedText(context, zh: '三级', en: 'Tier 3'),
        failures: v.cooldownTier3Failures,
        seconds: v.cooldownTier3Seconds,
        onChangedFailures: (n) =>
            _updateAdvanced(v.copyWith(cooldownTier3Failures: n)),
        onChangedSeconds: (n) =>
            _updateAdvanced(v.copyWith(cooldownTier3Seconds: n)),
      ),
      const SizedBox(height: 4),
      _AdvancedNumberRow(
        label: openHandLocalizedText(
          context,
          zh: '配额/限流冷却（秒）',
          en: 'Quota cooldown (s)',
        ),
        value: v.cooldownQuotaSeconds,
        min: AiWebSearchSettings.minCooldownSeconds,
        max: AiWebSearchSettings.maxCooldownSeconds,
        onChanged: (n) => _updateAdvanced(v.copyWith(cooldownQuotaSeconds: n)),
      ),
      const SizedBox(height: 12),
      // 告警
      Text(
        openHandLocalizedText(
          context,
          zh: '健康度告警（0 = 关闭，至少 5 次调用后才会触发）',
          en: 'Health alerts (0 = off; needs ≥5 calls)',
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      _AdvancedNumberRow(
        label: openHandLocalizedText(
          context,
          zh: '成功率低于（%）',
          en: 'Success rate below (%)',
        ),
        value: v.alertSuccessRatePct,
        min: 0,
        max: AiWebSearchSettings.maxAlertSuccessRatePct,
        onChanged: (n) => _updateAdvanced(v.copyWith(alertSuccessRatePct: n)),
      ),
      _AdvancedNumberRow(
        label: openHandLocalizedText(
          context,
          zh: '平均耗时高于（毫秒）',
          en: 'Avg duration above (ms)',
        ),
        value: v.alertAvgDurationMs,
        min: 0,
        max: AiWebSearchSettings.maxAlertAvgDurationMs,
        onChanged: (n) => _updateAdvanced(v.copyWith(alertAvgDurationMs: n)),
      ),
      const SizedBox(height: 12),
      // throttle
      Text(
        openHandLocalizedText(
          context,
          zh: '速率限制（每引擎每分钟最大调用数；0 = 不限）',
          en: 'Rate limit (per engine, per minute; 0 = off)',
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      _AdvancedNumberRow(
        label: openHandLocalizedText(context, zh: '上限', en: 'Cap'),
        value: v.throttlePerMinute,
        min: 0,
        max: AiWebSearchSettings.maxThrottlePerMinute,
        onChanged: (n) => _updateAdvanced(v.copyWith(throttlePerMinute: n)),
      ),
    ];
  }

  void _updateAdvanced(AiWebSearchSettings next) {
    _emit(next);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Telemetry UI（调用日志 + 引擎健康度）
  // ───────────────────────────────────────────────────────────────────────────
  List<Widget> _buildTelemetrySection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AiWebSearchSettings v,
  ) {
    final hasData = _recentCalls.isNotEmpty || _engineStats.isNotEmpty;
    return [
      Text(
        openHandLocalizedText(
          context,
          zh: '调用日志 / 引擎健康度',
          en: 'Call History / Engine Health',
        ),
        style: theme.textTheme.titleSmall,
      ),
      const SizedBox(height: 4),
      Text(
        openHandLocalizedText(
          context,
          zh:
              '近期 50 条 WebSearch 调用与每引擎累计成功率、平均耗时、命中数；'
              '数据持久化在 ~/.openhand/cache/web_search/telemetry/。',
          en:
              'Recent 50 WebSearch invocations plus per-engine cumulative '
              'success-rate / avg latency / total hits. Persisted under '
              '~/.openhand/cache/web_search/telemetry/.',
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          const Spacer(),
          TextButton.icon(
            onPressed:
                _telemetryLoading ||
                    _clearingTelemetry ||
                    _exportingTelemetry ||
                    _recentCalls.isEmpty
                ? null
                : () => _exportTelemetry(asCsv: false),
            icon: const Icon(Icons.code, size: 16),
            label: Text(
              openHandLocalizedText(context, zh: '导出 JSON', en: 'Export JSON'),
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed:
                _telemetryLoading ||
                    _clearingTelemetry ||
                    _exportingTelemetry ||
                    _recentCalls.isEmpty
                ? null
                : () => _exportTelemetry(asCsv: true),
            icon: _exportingTelemetry
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_chart, size: 16),
            label: Text(
              openHandLocalizedText(context, zh: '导出 CSV', en: 'Export CSV'),
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: _telemetryLoading || _clearingTelemetry
                ? null
                : _refreshTelemetry,
            icon: _telemetryLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: Text(
              openHandLocalizedText(context, zh: '刷新', en: 'Refresh'),
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: !hasData || _clearingTelemetry
                ? null
                : _confirmAndClearTelemetry,
            icon: _clearingTelemetry
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.delete_sweep, size: 16, color: colorScheme.error),
            label: Text(
              openHandLocalizedText(
                context,
                zh: _clearingTelemetry ? '清空中…' : '清空记录',
                en: _clearingTelemetry ? 'Clearing…' : 'Clear Logs',
              ),
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (!hasData && !_telemetryLoading)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            openHandLocalizedText(
              context,
              zh: '暂无调用记录。下一次 WebSearch 调用结束后会自动记录。',
              en:
                  'No calls recorded yet. The next WebSearch invocation '
                  'will be logged automatically.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        )
      else ...[
        if (_engineStats.isNotEmpty) ...[
          Text(
            openHandLocalizedText(context, zh: '引擎健康度', en: 'Engine Health'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ..._engineStats.entries
              .toList(growable: false)
              .map(
                (e) => _buildEngineStatRow(
                  context,
                  theme,
                  colorScheme,
                  e.key,
                  e.value,
                ),
              ),
          const SizedBox(height: 12),
        ],
        if (_recentCalls.isNotEmpty) ...[
          Text(
            openHandLocalizedText(context, zh: '最近调用', en: 'Recent Calls'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ..._recentCalls
              .take(20)
              .map((c) => _buildCallLogRow(context, theme, colorScheme, c)),
          if (_recentCalls.length > 20)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                openHandLocalizedText(
                  context,
                  zh: '… 还有 ${_recentCalls.length - 20} 条更早记录',
                  en: '… ${_recentCalls.length - 20} older entries',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    ];
  }

  Widget _buildEngineStatRow(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AiWebSearchEngineKind kind,
    WebSearchEngineStat stat,
  ) {
    final pct = (stat.successRate * 100);
    final pctColor = pct >= 80
        ? Colors.green.shade600
        : pct >= 50
        ? Colors.orange.shade600
        : colorScheme.error;
    final inCooldown = stat.isInCooldown();
    final samples = _engineHistory[kind] ?? const <WebSearchEngineSample>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  kind.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 84,
                child: Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: finiteUnitInterval(stat.successRate),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: pctColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                child: Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall?.copyWith(color: pctColor),
                ),
              ),
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '${stat.totalCalls} 次 · 平均 ${stat.avgDurationMs.toStringAsFixed(0)}ms · 累计 ${stat.totalHits} 命中',
                    en: '${stat.totalCalls} calls · avg ${stat.avgDurationMs.toStringAsFixed(0)}ms · ${stat.totalHits} hits',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (stat.lastError != null)
                Tooltip(
                  message: stat.lastError ?? '',
                  child: Icon(
                    Icons.error_outline,
                    size: 14,
                    color: colorScheme.error,
                  ),
                ),
            ],
          ),
          if (inCooldown || stat.lastQuotaError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 92 + 6),
              child: Row(
                children: [
                  if (inCooldown) ...[
                    _SettingsStatusChip(
                      icon: Icons.pause_circle_outline,
                      label: openHandLocalizedText(
                        context,
                        zh: '降级中 · 剩余 ${_settingsFormatRemainingUntilMs(stat.cooldownUntilMs)}',
                        en: 'cooldown · ${_settingsFormatRemainingUntilMs(stat.cooldownUntilMs)} left',
                      ),
                      backgroundColor: colorScheme.errorContainer,
                      foregroundColor: colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => _resetEngineCooldown(kind),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          openHandLocalizedText(context, zh: '重置', en: 'Reset'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            decoration: TextDecoration.underline,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (stat.lastQuotaError != null) ...[
                    if (inCooldown) const SizedBox(width: 6),
                    Tooltip(
                      message: stat.lastQuotaError ?? '',
                      child: _SettingsStatusChip(
                        icon: Icons.speed,
                        label: openHandLocalizedText(
                          context,
                          zh: '配额/限流',
                          en: 'rate limit',
                        ),
                        backgroundColor: colorScheme.tertiaryContainer,
                        foregroundColor: colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (samples.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 92 + 6),
              child: SizedBox(
                width: 240,
                height: 28,
                child: CustomPaint(
                  painter: _WebSearchSparklinePainter(
                    samples: samples,
                    successColor: Colors.green.shade600,
                    failureColor: colorScheme.error,
                    lineColor: colorScheme.primary.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCallLogRow(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    WebSearchCallLog call,
  ) {
    final timeStr = _settingsFormatMonthDayHmsFromEpochMs(call.timestampMs);
    final (chipBg, chipFg, chipLabel) = switch (call.cacheStatus) {
      'hit' => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        'cache hit',
      ),
      'miss-stored' => (
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
        'fresh',
      ),
      'miss-empty' => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
        'empty',
      ),
      'disabled' => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
        'cache off',
      ),
      'bypass' => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
        'bypass',
      ),
      _ => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
        call.cacheStatus,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              timeStr,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              chipLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: chipFg,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  call.query,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  openHandLocalizedText(
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (call.perEngine.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: call.perEngine
                          .map(
                            (p) => Text(
                              '${p.kind.name}:${p.success ? "✓${p.hitCount}" : "✗"}/${p.elapsedMs}ms',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: p.success
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.error,
                              ),
                            ),
                          )
                          .toList(growable: false),
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

class _AdvancedCooldownTierRow extends StatelessWidget {
  const _AdvancedCooldownTierRow({
    required this.label,
    required this.failures,
    required this.seconds,
    required this.onChangedFailures,
    required this.onChangedSeconds,
  });

  final String label;
  final int failures;
  final int seconds;
  final ValueChanged<int> onChangedFailures;
  final ValueChanged<int> onChangedSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Text(
            openHandLocalizedText(context, zh: '连续失败 ', en: 'fails ≥ '),
            style: theme.textTheme.bodySmall,
          ),
          SizedBox(
            width: 60,
            child: _SettingsIntField(
              value: failures,
              min: AiWebSearchSettings.minCooldownFailures,
              max: AiWebSearchSettings.maxCooldownFailures,
              onChanged: onChangedFailures,
            ),
          ),
          Text(
            openHandLocalizedText(
              context,
              zh: ' 次  →  冷却 ',
              en: '  →  cooldown ',
            ),
            style: theme.textTheme.bodySmall,
          ),
          SizedBox(
            width: 80,
            child: _SettingsIntField(
              value: seconds,
              min: AiWebSearchSettings.minCooldownSeconds,
              max: AiWebSearchSettings.maxCooldownSeconds,
              onChanged: onChangedSeconds,
            ),
          ),
          Text(
            openHandLocalizedText(context, zh: ' 秒', en: ' s'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _AdvancedNumberRow extends StatelessWidget {
  const _AdvancedNumberRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
          SizedBox(
            width: 100,
            child: _SettingsIntField(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _WebSearchSparklinePainter extends CustomPainter {
  _WebSearchSparklinePainter({
    required this.samples,
    required this.successColor,
    required this.failureColor,
    required this.lineColor,
  });

  final List<WebSearchEngineSample> samples;
  final Color successColor;
  final Color failureColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    // 取最近 50 个样本，duration 归一化成 y。
    final tail = samples.length > 50
        ? samples.sublist(samples.length - 50)
        : samples;
    final maxDur = tail.fold<int>(
      0,
      (m, s) => s.durationMs > m ? s.durationMs : m,
    );
    final scaleY = maxDur == 0 ? 0.0 : (size.height - 4) / maxDur;
    final stepX = tail.length == 1
        ? size.width
        : size.width / (tail.length - 1);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < tail.length; i++) {
      final x = i * stepX;
      final y = size.height - 2 - tail[i].durationMs * scaleY;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    final dotSuccess = Paint()..color = successColor;
    final dotFailure = Paint()..color = failureColor;
    for (var i = 0; i < tail.length; i++) {
      final x = i * stepX;
      final y = size.height - 2 - tail[i].durationMs * scaleY;
      canvas.drawCircle(
        Offset(x, y),
        1.6,
        tail[i].success ? dotSuccess : dotFailure,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WebSearchSparklinePainter old) =>
      old.samples != samples ||
      old.successColor != successColor ||
      old.failureColor != failureColor ||
      old.lineColor != lineColor;
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
    AiWebSearchSummaryStyle.structured => openHandLocalizedText(
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
  bool _apiKeyVisible = false;

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
                        ? openHandLocalizedText(
                            context,
                            zh: '收起',
                            en: 'Collapse',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '展开',
                            en: 'Expand',
                          ),
                    icon: _SettingsExpandIcon(expanded: _expanded),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                  Switch(
                    value: cfg.enabled,
                    onChanged: (v) =>
                        widget.onChanged(cfg.copyWith(enabled: v)),
                  ),
                ],
              ),
              _SettingsElasticExpansion(
                expanded: _expanded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '权重 ${cfg.weight} (1 = 最低,100 = 最高;影响 summary 偏重)',
                        en:
                            'Weight ${cfg.weight} (higher = more emphasis in '
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
                              labelText: openHandLocalizedText(
                                context,
                                zh: '重试次数',
                                en: 'Max Retries',
                              ),
                            ),
                            onChanged: (s) {
                              widget.onChanged(
                                cfg.copyWith(
                                  maxRetries: clampedIntFromText(
                                    s,
                                    fallback: 0,
                                    min: 0,
                                    max: AiWebSearchEngineConfig
                                        .maxRetriesUpperBound,
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
                              labelText: openHandLocalizedText(
                                context,
                                zh: '截断阈值 (字符)',
                                en: 'Truncation (chars)',
                              ),
                            ),
                            onChanged: (s) {
                              widget.onChanged(
                                cfg.copyWith(
                                  truncationChars: clampedIntFromText(
                                    s,
                                    fallback: AiWebSearchEngineConfig
                                        .defaultTruncationChars,
                                    min: AiWebSearchEngineConfig
                                        .minTruncationChars,
                                    max: AiWebSearchEngineConfig
                                        .maxTruncationChars,
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
                          labelText: openHandLocalizedText(
                            context,
                            zh: 'API Key',
                            en: 'API Key',
                          ),
                          hintText: _apiKeyHint(cfg.kind),
                          suffixIcon: IconButton(
                            tooltip: _apiKeyVisible
                                ? openHandLocalizedText(
                                    context,
                                    zh: '隐藏 API Key',
                                    en: 'Hide API Key',
                                  )
                                : openHandLocalizedText(
                                    context,
                                    zh: '显示 API Key',
                                    en: 'Show API Key',
                                  ),
                            icon: Icon(
                              _apiKeyVisible
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                            onPressed: () => setState(
                              () => _apiKeyVisible = !_apiKeyVisible,
                            ),
                          ),
                        ),
                        obscureText: !_apiKeyVisible,
                        enableSuggestions: false,
                        autocorrect: false,
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
                            labelText: openHandLocalizedText(
                              context,
                              zh: '复用 Provider 的 API Key (可选)',
                              en: 'Reuse Provider API Key (optional)',
                            ),
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              child: Text(
                                openHandLocalizedText(
                                  context,
                                  zh: '不复用',
                                  en: 'None',
                                ),
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
                          labelText: openHandLocalizedText(
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
                              endpointOverride: trimmed.isEmpty
                                  ? null
                                  : trimmed,
                              clearEndpointOverride: trimmed.isEmpty,
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
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

part of 'web_reverse_dashboard_dialog.dart';

// Performance：实时 Performance.getMetrics 卡片 + Tracing 录制（导出 trace.json）

class _PerformancePanel extends StatefulWidget {
  const _PerformancePanel({
    required this.controller,
    required this.isZh,
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
  final bool isZh;
  final bool reduceMotion;

  @override
  State<_PerformancePanel> createState() => _PerformancePanelState();
}

class _PerformancePanelState extends State<_PerformancePanel> {
  Timer? _refreshTimer;
  List<(String, double)> _metrics = const [];
  // 关键指标的滑动窗口（最近 60 个采样点 ≈ 2 分钟）。
  final Map<String, List<double>> _history = <String, List<double>>{};
  static const int _historyLen = 60;
  String? _metricsTargetId;
  int _refreshSerial = 0;
  bool _refreshInFlight = false;
  bool _tracing = false;
  Duration _traceDuration = const Duration(seconds: 5);
  // 录制提前停止信号；非空表示当前在录，点击 Stop 时 complete 即可让
  // [WebReverseSessionController.recordTrace] 立即 Tracing.end。
  Completer<void>? _traceEarlyStop;
  // 上次成功录制的 trace JSON，用于「查看火焰图」按钮；超过 8MB 不缓存以
  // 防内存暴涨。
  String? _lastTraceJson;
  // 解析后的 trace 事件，按 5 条 lane（Loading/Scripting/Rendering/Painting/Other）
  // 直接画到面板里的 inline timeline。单次录制结果，跨录制覆盖。
  List<_TraceLaneEvent> _traceLanes = const [];
  double _traceMinTs = 0;
  double _traceMaxTs = 0;

  // FPS：用 requestAnimationFrame 在浏览器里采样上一秒帧数，
  // 通过 Runtime.evaluate 拉回。
  Timer? _fpsTimer;
  final List<double> _fpsHistory = <double>[];
  bool _fpsBootstrapped = false;
  String? _fpsTargetId;

  // Long task：浏览器 PerformanceObserver 推到 window.__oh_long_tasks，
  // 每 1s 拉一次清空，dashboard 展示最近 50 条。
  Timer? _longTaskTimer;
  bool _longTaskBootstrapped = false;
  String? _longTaskTargetId;
  final List<Map<String, Object?>> _longTasks = <Map<String, Object?>>[];
  static const int _longTasksMax = 50;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = startNonOverlappingPeriodicTimer(
      const Duration(seconds: 2),
      (_) => _refresh(),
      onError: (error, stack) =>
          silentLog('web_reverse_dashboard_dialog', '刷新性能指标', error, stack),
    );
    _fpsTimer = startNonOverlappingPeriodicTimer(
      const Duration(seconds: 1),
      (_) => _sampleFps(),
      onError: (error, stack) =>
          silentLog('web_reverse_dashboard_dialog', '采样 FPS', error, stack),
    );
    _longTaskTimer = startNonOverlappingPeriodicTimer(
      const Duration(seconds: 1),
      (_) => _sampleLongTasks(),
      onError: (error, stack) =>
          silentLog('web_reverse_dashboard_dialog', '采样长任务', error, stack),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _fpsTimer?.cancel();
    _longTaskTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      await _refreshOnce();
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _refreshOnce() async {
    final serial = ++_refreshSerial;
    final controller = widget.controller;
    final targetId = controller.currentPageTargetId;
    final m = await controller.performanceMetrics();
    if (!mounted || serial != _refreshSerial) return;
    if (controller.currentPageTargetId != targetId) return;
    if (_metricsTargetId != targetId) {
      _metricsTargetId = targetId;
      _history.clear();
    }
    for (final (name, value) in m) {
      final list = _history.putIfAbsent(name, () => <double>[]);
      list.add(value);
      while (list.length > _historyLen) {
        list.removeAt(0);
      }
    }
    setState(() => _metrics = m);
  }

  /// 在 page 内安装一个滑动 FPS 计数器（首次），随后每秒读一次。
  Future<void> _sampleFps() async {
    final cdp = widget.controller;
    if (!cdp.isRunning) return;
    final targetId = cdp.currentPageTargetId;
    if (_fpsTargetId != targetId) {
      _fpsTargetId = targetId;
      _fpsBootstrapped = false;
      _fpsHistory.clear();
    }
    if (!_fpsBootstrapped) {
      final installed = await cdp.installFpsCounter();
      if (!mounted || cdp.currentPageTargetId != targetId) return;
      if (!installed) return;
      _fpsBootstrapped = true;
    }
    final fps = await cdp.readFps();
    if (!mounted || cdp.currentPageTargetId != targetId || fps == null) return;
    setState(() {
      _fpsHistory.add(fps);
      while (_fpsHistory.length > _historyLen) {
        _fpsHistory.removeAt(0);
      }
    });
  }

  /// 在 page 内安装 PerformanceObserver longtask（首次），随后每秒拉一次新增。
  Future<void> _sampleLongTasks() async {
    final cdp = widget.controller;
    if (!cdp.isRunning) return;
    final targetId = cdp.currentPageTargetId;
    if (_longTaskTargetId != targetId) {
      _longTaskTargetId = targetId;
      _longTaskBootstrapped = false;
      _longTasks.clear();
    }
    if (!_longTaskBootstrapped) {
      final installed = await cdp.installLongTaskObserver();
      if (!mounted || cdp.currentPageTargetId != targetId) return;
      if (!installed) return;
      _longTaskBootstrapped = true;
    }
    final fresh = await cdp.readLongTasks();
    if (!mounted || cdp.currentPageTargetId != targetId || fresh.isEmpty) {
      return;
    }
    setState(() {
      _longTasks.addAll(fresh);
      while (_longTasks.length > _longTasksMax) {
        _longTasks.removeAt(0);
      }
    });
  }

  /// 把上次录制的 trace 解析成 X 事件帧序列，用 _FlamePainter 渲染简化火焰图。
  /// 仅识别 ph='X'（complete）类型，按 ts 起点 + dur 长度 + tid 行号布局。
  void _showFlameGraph() {
    final raw = _lastTraceJson;
    if (raw == null) return;
    webReverseToolDialogs.show<void>(
      context: context,
      builder: (_) => _FlameGraphDialog(traceJson: raw),
    );
  }

  /// 把当前记录的 FPS 历史 + Long task 列表合并成 CSV 落盘。两段数据放
  /// 同一个文件，靠 section 标记区分，方便 Excel / 数据分析工具一次性吃。
  Future<void> _exportCsv() async {
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final buf = StringBuffer();
    buf.writeln('# section,fps_history');
    buf.writeln('seconds_ago,fps');
    for (var i = 0; i < _fpsHistory.length; i++) {
      final secAgo = _fpsHistory.length - 1 - i;
      buf.writeln('$secAgo,${_fpsHistory[i].toStringAsFixed(2)}');
    }
    buf.writeln();
    buf.writeln('# section,long_tasks');
    buf.writeln('start_time_ms,duration_ms,name');
    for (final task in _longTasks) {
      final start = task['startTime'];
      final dur = task['duration'];
      final name = '${task['name'] ?? 'longtask'}'
          .replaceAll(',', ' ')
          .replaceAll('\n', ' ');
      buf.writeln('${start ?? ''},${dur ?? 0},$name');
    }
    const typeGroup = XTypeGroup(label: 'CSV', extensions: <String>['csv']);
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'performance-$ts.csv',
        acceptedTypeGroups: const [typeGroup],
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '选择性能 CSV 保存位置', error, stack);
    }
    if (!mounted || location == null) return;
    try {
      await writeFileAtomically(File(location.path), buf.toString());
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        webReverseSavedToFileMessage(context, location.path),
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '导出性能 CSV', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        webReverseSaveFailedMessage(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  Future<void> _record() async {
    final earlyStop = Completer<void>();
    setState(() {
      _tracing = true;
      _traceEarlyStop = earlyStop;
    });
    String? json;
    try {
      json = await widget.controller.recordTrace(
        duration: _traceDuration,
        earlyStop: earlyStop.future,
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '录制性能轨迹', error, stack);
    }
    if (!mounted) return;
    setState(() {
      _tracing = false;
      _traceEarlyStop = null;
    });
    if (json == null) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'Trace 录制失败',
          zhHant: 'Trace 錄製失敗',
          en: 'Trace failed',
          fr: 'Échec de la trace',
          de: 'Trace fehlgeschlagen',
          ja: 'Trace の記録に失敗しました',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    if (json.length <= 8 * kBytesPerMiB) {
      _lastTraceJson = json;
      // 解析为 inline timeline；解析失败也不致命，只是显示空状态。
      try {
        final parsed = _parseTraceLanes(json);
        _traceLanes = parsed.events;
        _traceMinTs = parsed.minTs;
        _traceMaxTs = parsed.maxTs;
      } catch (error, stack) {
        silentLog('web_reverse_dashboard_dialog', '解析性能轨迹泳道', error, stack);
        _traceLanes = const [];
      }
      if (mounted) setState(() {});
    }
    const typeGroup = XTypeGroup(label: 'Trace', extensions: <String>['json']);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'trace-$ts.json',
        acceptedTypeGroups: const [typeGroup],
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '选择性能轨迹保存位置', error, stack);
    }
    if (location == null) return;
    try {
      await writeFileAtomically(File(location.path), json);
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'Trace 已保存到 ${location.path}',
          zhHant: 'Trace 已儲存到 ${location.path}',
          en: 'Trace saved to ${location.path}',
          fr: 'Trace enregistrée dans ${location.path}',
          de: 'Trace gespeichert unter ${location.path}',
          ja: 'Trace を ${location.path} に保存しました',
        ),
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '写入性能轨迹', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'Trace 保存失败',
          zhHant: 'Trace 儲存失敗',
          en: 'Trace save failed',
          fr: 'Échec de l’enregistrement de la trace',
          de: 'Trace konnte nicht gespeichert werden',
          ja: 'Trace の保存に失敗しました',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const highlights = <String>[
      'JSHeapUsedSize',
      'JSHeapTotalSize',
      'Documents',
      'Frames',
      'Nodes',
      'LayoutCount',
      'RecalcStyleCount',
      'TaskDuration',
    ];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                openHandLocalizedText(
                  context,
                  zh: '实时性能指标（每 2s 刷新）',
                  zhHant: '即時效能指標（每 2s 重新整理）',
                  en: 'Live Performance Metrics (refresh 2s)',
                  fr: 'Métriques de performance live (2 s)',
                  de: 'Live-Performance-Metriken (alle 2 s)',
                  ja: 'リアルタイム性能指標（2 秒ごとに更新）',
                ),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              WebReverseSelectButton<Duration>(
                value: _traceDuration,
                dense: true,
                minWidth: 84,
                tooltip: openHandLocalizedText(
                  context,
                  zh: '选择 Trace 时长',
                  zhHant: '選擇 Trace 時長',
                  en: 'Select trace duration',
                  fr: 'Choisir la durée de trace',
                  de: 'Trace-Dauer auswahlen',
                  ja: 'Trace 時間を選択',
                ),
                onChanged: _tracing
                    ? null
                    : (v) => setState(() => _traceDuration = v),
                options: const [
                  WebReverseSelectOption(
                    value: Duration(seconds: 3),
                    label: '3 s',
                  ),
                  WebReverseSelectOption(
                    value: Duration(seconds: 5),
                    label: '5 s',
                  ),
                  WebReverseSelectOption(
                    value: Duration(seconds: 10),
                    label: '10 s',
                  ),
                  WebReverseSelectOption(
                    value: Duration(seconds: 30),
                    label: '30 s',
                  ),
                ],
              ),
              kOpenHandHGap10,
              if (_tracing)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  ),
                  onPressed: _traceEarlyStop == null
                      ? null
                      : () {
                          final c = _traceEarlyStop;
                          if (c != null && !c.isCompleted) c.complete();
                        },
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '停止录制',
                      zhHant: '停止錄製',
                      en: 'Stop',
                      fr: 'Arrêter',
                      de: 'Stoppen',
                      ja: '停止',
                    ),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _record,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '录制 Trace',
                      zhHant: '錄製 Trace',
                      en: 'Record Trace',
                      fr: 'Enregistrer trace',
                      de: 'Trace aufzeichnen',
                      ja: 'Trace を記録',
                    ),
                  ),
                ),
              kOpenHandHGap10,
              OutlinedButton.icon(
                onPressed: (_fpsHistory.isEmpty && _longTasks.isEmpty)
                    ? null
                    : _exportCsv,
                icon: const Icon(Icons.table_view_rounded, size: 18),
                label: Text(_wrExportCsvLabel(context)),
              ),
              kOpenHandHGap10,
              OutlinedButton.icon(
                onPressed: _lastTraceJson == null ? null : _showFlameGraph,
                icon: const Icon(Icons.local_fire_department_rounded, size: 18),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '火焰图',
                    zhHant: '火焰圖',
                    en: 'Flame graph',
                    fr: 'Flame graph',
                    de: 'Flamegraph',
                    ja: 'フレームグラフ',
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          // 录制完成后直接在面板里画一段 5 lane 的 timeline，免去打开火焰图弹窗
          // 的步骤；交互上支持水平双指 / Ctrl+滚轮缩放 + 拖拽平移 + hover tooltip。
          if (_traceLanes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TraceLanesInline(
                events: _traceLanes,
                minTs: _traceMinTs,
                maxTs: _traceMaxTs,
              ),
            ),
          // FPS 横幅卡片：单独一行展示，sparkline 占满宽度。
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: webReverseSurfaceCardDecoration(cs, radius: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'FPS',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      kOpenHandGap2,
                      Text(
                        _fpsHistory.isEmpty
                            ? '—'
                            : _fpsHistory.last.toStringAsFixed(1),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _fpsHistory.isEmpty
                              ? cs.onSurfaceVariant
                              : (_fpsHistory.last >= 50
                                    ? Colors.green
                                    : (_fpsHistory.last >= 30
                                          ? Colors.orange
                                          : cs.error)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    // FPS 折线同样使用 AnimatedSparkline，让 1s 一次的更新
                    // 看起来像水波而不是台阶。
                    child: _AnimatedSparkline(
                      values: _fpsHistory,
                      color: cs.primary,
                      fillBelow: true,
                      upperBound: 60,
                      reduceMotion: widget.reduceMotion,
                    ),
                  ),
                ),
              ],
            ),
          ),
          kOpenHandGap10,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _metrics.isEmpty
                      ? OpenHandInlineEmptyState(
                          message: openHandLocalizedText(
                            context,
                            zh: '尚无指标数据。',
                            zhHant: '尚無指標資料。',
                            en: 'No metrics yet.',
                            fr: 'Aucune métrique pour le moment.',
                            de: 'Noch keine Metriken.',
                            ja: '指標データはまだありません。',
                          ),
                        )
                      : GridView.count(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2.2,
                          children: _orderedMetrics(highlights).map((m) {
                            final history = _history[m.$1] ?? const <double>[];
                            return AnimatedContainer(
                              duration: widget.reduceMotion
                                  ? Duration.zero
                                  : kOpenHandMotion220,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: webReverseSurfaceCardDecoration(
                                cs,
                                radius: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // 指标名 i18n：显示翻译后的友好名 + 原 CDP 名
                                  // 双行；保留原名是为了让懂 CDP 的用户随手对照
                                  // Performance.getMetrics 文档。
                                  Tooltip(
                                    message: m.$1,
                                    child: Text(
                                      _localizedMetricName(context, m.$1),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            fontWeight: FontWeight.w700,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    _formatMetric(m.$1, m.$2),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  SizedBox(
                                    height: 24,
                                    // sparkline 用 AnimatedSparkline 平滑过渡：
                                    // 数据每 2s 一次跳变会太硬，加 240ms 缓动
                                    // 让折线落点像液面一样平滑接管。
                                    child: _AnimatedSparkline(
                                      values: history,
                                      color: cs.primary,
                                      fillBelow: true,
                                      reduceMotion: widget.reduceMotion,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
                kOpenHandHGap12,
                // Long tasks 侧栏：固定 320 宽，紧凑列表 + 时长高亮。
                SizedBox(width: 320, child: _LongTasksPane(tasks: _longTasks)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatMetric(String name, double v) {
    if (v.abs() < 1) return v.toStringAsFixed(3);
    if (v.abs() < 1000) return v.toStringAsFixed(2);
    return v.toStringAsFixed(0);
  }

  /// 按 [highlights] 顺序排前面的高优先级指标，剩余按字母顺序拼后面。
  List<(String, double)> _orderedMetrics(List<String> highlights) {
    final hi = _metrics.where((m) => highlights.contains(m.$1)).toList()
      ..sort(
        (a, b) => highlights.indexOf(a.$1).compareTo(highlights.indexOf(b.$1)),
      );
    final lo = _metrics.where((m) => !highlights.contains(m.$1)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return [...hi, ...lo];
  }
}

/// CDP `Performance.getMetrics` 指标名 → 本地化展示名。
/// 仅做覆盖性翻译；未命中名直接回退到原名（保证未来 CDP 新增字段时不会丢字段）。
String _localizedMetricName(BuildContext context, String cdpName) {
  switch (cdpName) {
    // 生命周期 / 时间
    case 'Timestamp':
      return openHandLocalizedText(
        context,
        zh: '时间戳',
        zhHant: '時間戳',
        en: 'Timestamp',
        fr: 'Horodatage',
        de: 'Zeitstempel',
        ja: 'タイムスタンプ',
      );
    case 'AudioHandlers':
      return openHandLocalizedText(
        context,
        zh: '音频处理器',
        zhHant: '音訊處理器',
        en: 'Audio Handlers',
        fr: 'Handlers audio',
        de: 'Audio-Handler',
        ja: 'オーディオハンドラ',
      );
    case 'AudioWorkletProcessors':
      return openHandLocalizedText(
        context,
        zh: '音频 Worklet 处理器',
        zhHant: '音訊 Worklet 處理器',
        en: 'Audio Worklet Processors',
        fr: 'Processeurs Audio Worklet',
        de: 'Audio-Worklet-Prozessoren',
        ja: 'Audio Worklet プロセッサ',
      );
    case 'Documents':
      return openHandLocalizedText(
        context,
        zh: 'Document 数',
        zhHant: 'Document 數',
        en: 'Documents',
        fr: 'Documents',
        de: 'Dokumente',
        ja: 'Document 数',
      );
    case 'Frames':
      return openHandLocalizedText(
        context,
        zh: 'Frame 数',
        zhHant: 'Frame 數',
        en: 'Frames',
        fr: 'Frames',
        de: 'Frames',
        ja: 'Frame 数',
      );
    case 'JSEventListeners':
      return openHandLocalizedText(
        context,
        zh: 'JS 事件监听器',
        zhHant: 'JS 事件監聽器',
        en: 'JS Event Listeners',
        fr: 'Listeners JS',
        de: 'JS-Event-Listener',
        ja: 'JS イベントリスナー',
      );
    case 'Nodes':
      return openHandLocalizedText(
        context,
        zh: 'DOM 节点数',
        zhHant: 'DOM 節點數',
        en: 'DOM Nodes',
        fr: 'Nœuds DOM',
        de: 'DOM-Knoten',
        ja: 'DOM ノード数',
      );
    case 'LayoutCount':
      return openHandLocalizedText(
        context,
        zh: '布局次数',
        zhHant: '版面配置次數',
        en: 'Layout Count',
        fr: 'Nombre de layouts',
        de: 'Layout-Anzahl',
        ja: 'レイアウト回数',
      );
    case 'RecalcStyleCount':
      return openHandLocalizedText(
        context,
        zh: '样式重算次数',
        zhHant: '樣式重算次數',
        en: 'Recalc Style Count',
        fr: 'Recalculs de style',
        de: 'Style-Neuberechnungen',
        ja: 'スタイル再計算回数',
      );
    case 'LayoutDuration':
      return openHandLocalizedText(
        context,
        zh: '布局耗时',
        zhHant: '版面配置耗時',
        en: 'Layout Duration',
        fr: 'Durée layout',
        de: 'Layout-Dauer',
        ja: 'レイアウト時間',
      );
    case 'RecalcStyleDuration':
      return openHandLocalizedText(
        context,
        zh: '样式重算耗时',
        zhHant: '樣式重算耗時',
        en: 'Recalc Style Duration',
        fr: 'Durée recalcul style',
        de: 'Style-Neuberechnungsdauer',
        ja: 'スタイル再計算時間',
      );
    case 'DevToolsCommandDuration':
      return openHandLocalizedText(
        context,
        zh: 'DevTools 命令耗时',
        zhHant: 'DevTools 命令耗時',
        en: 'DevTools Cmd Duration',
        fr: 'Durée commandes DevTools',
        de: 'DevTools-Befehlsdauer',
        ja: 'DevTools コマンド時間',
      );
    case 'ScriptDuration':
      return openHandLocalizedText(
        context,
        zh: '脚本耗时',
        zhHant: '腳本耗時',
        en: 'Script Duration',
        fr: 'Durée script',
        de: 'Script-Dauer',
        ja: 'スクリプト時間',
      );
    case 'V8CompileDuration':
      return openHandLocalizedText(
        context,
        zh: 'V8 编译耗时',
        zhHant: 'V8 編譯耗時',
        en: 'V8 Compile Duration',
        fr: 'Durée compilation V8',
        de: 'V8-Kompilierdauer',
        ja: 'V8 コンパイル時間',
      );
    case 'TaskDuration':
      return openHandLocalizedText(
        context,
        zh: '任务耗时',
        zhHant: '任務耗時',
        en: 'Task Duration',
        fr: 'Durée tâche',
        de: 'Task-Dauer',
        ja: 'タスク時間',
      );
    case 'TaskOtherDuration':
      return openHandLocalizedText(
        context,
        zh: '其他任务耗时',
        zhHant: '其他任務耗時',
        en: 'Task Other Duration',
        fr: 'Durée autres tâches',
        de: 'Andere Task-Dauer',
        ja: 'その他タスク時間',
      );
    case 'ThreadTime':
      return openHandLocalizedText(
        context,
        zh: '线程时间',
        zhHant: '執行緒時間',
        en: 'Thread Time',
        fr: 'Temps thread',
        de: 'Thread-Zeit',
        ja: 'スレッド時間',
      );
    case 'ProcessTime':
      return openHandLocalizedText(
        context,
        zh: '进程时间',
        zhHant: '行程時間',
        en: 'Process Time',
        fr: 'Temps processus',
        de: 'Prozesszeit',
        ja: 'プロセス時間',
      );
    case 'JSHeapUsedSize':
      return openHandLocalizedText(
        context,
        zh: 'JS 堆已用',
        zhHant: 'JS 堆已用',
        en: 'JS Heap Used',
        fr: 'Tas JS utilisé',
        de: 'JS-Heap genutzt',
        ja: 'JS Heap 使用済み',
      );
    case 'JSHeapTotalSize':
      return openHandLocalizedText(
        context,
        zh: 'JS 堆总量',
        zhHant: 'JS 堆總量',
        en: 'JS Heap Total',
        fr: 'Tas JS total',
        de: 'JS-Heap gesamt',
        ja: 'JS Heap 合計',
      );
    case 'FirstMeaningfulPaint':
      return openHandLocalizedText(
        context,
        zh: '首次有意义绘制',
        zhHant: '首次有意義繪製',
        en: 'First Meaningful Paint',
        fr: 'Premier rendu significatif',
        de: 'First Meaningful Paint',
        ja: 'First Meaningful Paint',
      );
    case 'DomContentLoaded':
      return 'DOMContentLoaded';
    case 'NavigationStart':
      return openHandLocalizedText(
        context,
        zh: '导航开始',
        zhHant: '導覽開始',
        en: 'Navigation Start',
        fr: 'Début navigation',
        de: 'Navigationsstart',
        ja: 'ナビゲーション開始',
      );
    case 'AdSubframes':
      return openHandLocalizedText(
        context,
        zh: '广告子框架',
        zhHant: '廣告子框架',
        en: 'Ad Subframes',
        fr: 'Sous-frames pub',
        de: 'Ad-Subframes',
        ja: '広告サブフレーム',
      );
    case 'ArrayBufferContents':
      return openHandLocalizedText(
        context,
        zh: 'ArrayBuffer 内容',
        zhHant: 'ArrayBuffer 內容',
        en: 'ArrayBuffer Contents',
        fr: 'Contenu ArrayBuffer',
        de: 'ArrayBuffer-Inhalte',
        ja: 'ArrayBuffer 内容',
      );
    case 'Resources':
      return openHandLocalizedText(
        context,
        zh: '资源数',
        zhHant: '資源數',
        en: 'Resources',
        fr: 'Ressources',
        de: 'Ressourcen',
        ja: 'リソース数',
      );
    case 'ContextLifecycleStateObservers':
      return openHandLocalizedText(
        context,
        zh: '上下文生命周期观察者',
        zhHant: '上下文生命週期觀察者',
        en: 'Context Lifecycle Observers',
        fr: 'Observateurs cycle contexte',
        de: 'Kontext-Lebenszyklusbeobachter',
        ja: 'コンテキストライフサイクル監視',
      );
    case 'V8PerContextDatas':
      return openHandLocalizedText(
        context,
        zh: 'V8 上下文数据',
        zhHant: 'V8 上下文資料',
        en: 'V8 Context Data',
        fr: 'Données contexte V8',
        de: 'V8-Kontextdaten',
        ja: 'V8 コンテキストデータ',
      );
    case 'WorkerGlobalScopes':
      return openHandLocalizedText(
        context,
        zh: 'Worker 全局作用域',
        zhHant: 'Worker 全域作用域',
        en: 'Worker Global Scopes',
        fr: 'Scopes globaux Worker',
        de: 'Worker Global Scopes',
        ja: 'Worker グローバルスコープ',
      );
    case 'UACSSResources':
      return openHandLocalizedText(
        context,
        zh: 'UA CSS 资源',
        zhHant: 'UA CSS 資源',
        en: 'UA CSS Resources',
        fr: 'Ressources CSS UA',
        de: 'UA-CSS-Ressourcen',
        ja: 'UA CSS リソース',
      );
    case 'RTCPeerConnections':
      return openHandLocalizedText(
        context,
        zh: 'WebRTC 连接',
        zhHant: 'WebRTC 連線',
        en: 'WebRTC Connections',
        fr: 'Connexions WebRTC',
        de: 'WebRTC-Verbindungen',
        ja: 'WebRTC 接続',
      );
    case 'ResourceFetchers':
      return openHandLocalizedText(
        context,
        zh: '资源 Fetcher',
        zhHant: '資源 Fetcher',
        en: 'Resource Fetchers',
        fr: 'Fetchers de ressources',
        de: 'Resource Fetcher',
        ja: 'リソース Fetcher',
      );
    case 'AdSubframesEvictions':
      return openHandLocalizedText(
        context,
        zh: '广告子框架淘汰',
        zhHant: '廣告子框架淘汰',
        en: 'Ad Subframe Evictions',
        fr: 'Évictions sous-frames pub',
        de: 'Ad-Subframe-Evictions',
        ja: '広告サブフレーム削除',
      );
    case 'NumberOfDocuments':
      return openHandLocalizedText(
        context,
        zh: 'Document 数（细分）',
        zhHant: 'Document 數（細分）',
        en: 'Documents (detail)',
        fr: 'Documents (détail)',
        de: 'Dokumente (Detail)',
        ja: 'Document 数（詳細）',
      );
    case 'NumberOfActiveAndInactiveAnimations':
      return openHandLocalizedText(
        context,
        zh: '活动/休眠动画数',
        zhHant: '活動/休眠動畫數',
        en: 'Active/Inactive Animations',
        fr: 'Animations actives/inactives',
        de: 'Aktive/inaktive Animationen',
        ja: 'アクティブ/非アクティブアニメーション数',
      );
    case 'NumberOfMediaContexts':
      return openHandLocalizedText(
        context,
        zh: '媒体上下文数',
        zhHant: '媒體上下文數',
        en: 'Media Contexts',
        fr: 'Contextes media',
        de: 'Medienkontexte',
        ja: 'メディアコンテキスト数',
      );
    case 'AdFrameSubframes':
      return openHandLocalizedText(
        context,
        zh: '广告子框架（嵌套）',
        zhHant: '廣告子框架（巢狀）',
        en: 'Ad Frame Subframes',
        fr: 'Sous-frames pub imbriquées',
        de: 'Ad-Frame-Subframes',
        ja: '広告サブフレーム（ネスト）',
      );
    case 'AnimationCallbackPropertyTreeBuildersTime':
      return openHandLocalizedText(
        context,
        zh: '动画属性树构建耗时',
        zhHant: '動畫屬性樹建構耗時',
        en: 'Animation Property Tree Time',
        fr: 'Temps arbre propriétés animation',
        de: 'Animations-Property-Tree-Zeit',
        ja: 'アニメーションプロパティツリー構築時間',
      );
    case 'PaintingTime':
      return openHandLocalizedText(
        context,
        zh: '绘制耗时',
        zhHant: '繪製耗時',
        en: 'Painting Time',
        fr: 'Temps peinture',
        de: 'Paint-Zeit',
        ja: '描画時間',
      );
    case 'CompositingTime':
      return openHandLocalizedText(
        context,
        zh: '合成耗时',
        zhHant: '合成耗時',
        en: 'Compositing Time',
        fr: 'Temps composition',
        de: 'Compositing-Zeit',
        ja: '合成時間',
      );
    case 'CSSStyleSheets':
      return openHandLocalizedText(
        context,
        zh: 'CSS 样式表',
        zhHant: 'CSS 樣式表',
        en: 'CSS Style Sheets',
        fr: 'Feuilles CSS',
        de: 'CSS-Stylesheets',
        ja: 'CSS スタイルシート',
      );
    case 'ImageHolders':
      return openHandLocalizedText(
        context,
        zh: '图片占位符',
        zhHant: '圖片占位符',
        en: 'Image Holders',
        fr: 'Supports image',
        de: 'Image Holder',
        ja: '画像ホルダー',
      );
    case 'CompositorVisibleRectChange':
      return openHandLocalizedText(
        context,
        zh: '合成器可见矩形变更',
        zhHant: '合成器可見矩形變更',
        en: 'Compositor Visible Rect Change',
        fr: 'Changement rect visible compositor',
        de: 'Compositor Visible-Rect-Änderung',
        ja: 'コンポジタ表示矩形変更',
      );
    default:
      return cdpName;
  }
}

List<double> _resampleSparklineValues(List<double> source, int targetLength) {
  if (source.length == targetLength) return List<double>.from(source);
  if (source.isEmpty) return List<double>.filled(targetLength, 0);
  if (source.length > targetLength) {
    return source.sublist(source.length - targetLength);
  }
  return <double>[
    ...List<double>.filled(targetLength - source.length, source.first),
    ...source,
  ];
}

/// 平滑动画版 Sparkline：当传入 [values] 改变时不再瞬时跳点，
/// 而是用 240ms 的 easeOutCubic 把"上一组"折线值插值到"下一组"。
/// 配合 [_PerformancePanelState] 的 2s 周期采样，能让曲线像水波一样滑过。
class _AnimatedSparkline extends StatefulWidget {
  const _AnimatedSparkline({
    required this.values,
    required this.color,
    this.fillBelow = false,
    this.upperBound,
    this.reduceMotion = false,
  });

  final List<double> values;
  final Color color;
  final bool fillBelow;
  final double? upperBound;
  final bool reduceMotion;

  @override
  State<_AnimatedSparkline> createState() => _AnimatedSparklineState();
}

class _AnimatedSparklineState extends State<_AnimatedSparkline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: kOpenHandMotion240,
  );
  late List<double> _from = List<double>.from(widget.values);
  late List<double> _to = List<double>.from(widget.values);

  @override
  void didUpdateWidget(covariant _AnimatedSparkline old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.values, widget.values)) {
      _from = _resampleSparklineValues(_currentValues(), widget.values.length);
      _to = List<double>.from(widget.values);
      if (widget.reduceMotion) {
        _ac.value = 1;
      } else {
        _ac
          ..reset()
          ..animateTo(1, curve: kOpenHandSwitchInCurve);
      }
    }
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  List<double> _currentValues() {
    if (_from.length != _to.length) return _to;
    if (!_ac.isAnimating && _ac.value == 1) return _to;
    final t = _ac.value;
    return List<double>.generate(
      _to.length,
      (i) => _from[i] + (_to[i] - _from[i]) * t,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, _) => CustomPaint(
        painter: _Sparkline(
          values: _currentValues(),
          color: widget.color,
          fillBelow: widget.fillBelow,
          upperBound: widget.upperBound,
        ),
      ),
    );
  }
}

/// Long Task 列表：浏览器主线程 ≥50ms 的任务。颜色按时长分级。
class _LongTasksPane extends StatelessWidget {
  const _LongTasksPane({required this.tasks});
  final List<Map<String, Object?>> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: webReverseSurfaceCardDecoration(cs, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                kOpenHandHGap6,
                Expanded(
                  child: Text(
                    openHandLocalizedText(
                      context,
                      zh: '长任务（≥50ms 主线程阻塞）',
                      zhHant: '長任務（≥50ms 主執行緒阻塞）',
                      en: 'Long Tasks (≥50ms)',
                      fr: 'Tâches longues (≥50ms)',
                      de: 'Long Tasks (≥50ms)',
                      ja: 'Long Tasks（≥50ms）',
                    ),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: kOpenHandPillBorderRadius,
                  ),
                  child: Text(
                    '${tasks.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: tasks.isEmpty
                ? OpenHandInlineEmptyState(
                    message: openHandLocalizedText(
                      context,
                      zh: '暂无长任务。\n刷新页面或交互后此处会实时刷新。',
                      zhHant: '暫無長任務。\n重新整理頁面或互動後此處會即時更新。',
                      en: 'No long tasks yet.',
                      fr: 'Aucune tâche longue pour le moment.',
                      de: 'Noch keine Long Tasks.',
                      ja: 'Long Task はまだありません。',
                    ),
                    dense: true,
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: tasks.length,
                    itemBuilder: (_, idx) {
                      final t = tasks[tasks.length - 1 - idx];
                      final dur =
                          optionalNonNegativeDoubleFromValue(t['duration']) ??
                          0;
                      final color = dur >= 200
                          ? cs.error
                          : (dur >= 100 ? Colors.orange : cs.primary);
                      final attribution = t['attribution'];
                      final attribLabel = attribution is Map
                          ? '${attribution['containerType'] ?? ''} '
                                '${attribution['containerName'] ?? attribution['containerSrc'] ?? ''}'
                          : '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 4,
                              height: 28,
                              margin: const EdgeInsets.only(right: 8, top: 2),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(
                                  kOpenHandRadius2,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${dur.toStringAsFixed(0)} ms',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: kOpenHandMonospaceFontFamily,
                                      fontWeight: FontWeight.w800,
                                      color: color,
                                    ),
                                  ),
                                  if (attribLabel.trim().isNotEmpty)
                                    Text(
                                      attribLabel,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            fontFamily:
                                                kOpenHandMonospaceFontFamily,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 极简 sparkline：垂直自适应到当前窗口的 min/max；
/// fillBelow=true 时画线下半透明面，更直观体现趋势。
class _Sparkline extends CustomPainter {
  _Sparkline({
    required this.values,
    required this.color,
    this.fillBelow = false,
    this.upperBound,
  });

  final List<double> values;
  final Color color;
  final bool fillBelow;
  final double? upperBound;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var min = values.first;
    var max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final hi = upperBound != null ? math.max(max, upperBound!) : max;
    final lo = math.min(min, hi - 1e-6);
    final span = (hi - lo).abs() < 1e-9 ? 1 : (hi - lo);
    final stride = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * stride;
      final norm = (values[i] - lo) / span;
      final y = size.height - norm * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    if (fillBelow) {
      final fill = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..color = color.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _Sparkline old) =>
      old.values != values ||
      old.color != color ||
      old.fillBelow != fillBelow ||
      old.upperBound != upperBound;
}

// Memory：HeapProfiler.takeHeapSnapshot 拉 .heapsnapshot，导出可用于 DevTools 重放。

class _MemoryPanel extends StatefulWidget {
  const _MemoryPanel({
    required this.controller,
    required this.isZh,
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
  final bool isZh;
  final bool reduceMotion;

  @override
  State<_MemoryPanel> createState() => _MemoryPanelState();
}

class _MemoryPanelState extends State<_MemoryPanel> {
  bool _capturing = false;
  ({String json, int bytes})? _last;
  // 最近两次快照（轮转），供「比较」入口算 delta。第三次采集时丢掉最旧。
  ({String json, int bytes, DateTime ts})? _snapA;
  ({String json, int bytes, DateTime ts})? _snapB;
  // V8 实时折线：每 1.5s 拉一次 JSHeapUsedSize / JSHeapTotalSize。
  Timer? _heapTimer;
  final List<double> _heapUsed = <double>[];
  final List<double> _heapTotal = <double>[];
  static const int _heapHistoryLen = 80;
  // 采样期间的每 tick 分配增量（used.t - used.t-1，取正值）。
  // 配合 Switch 形式的「采样开关」让用户在采样窗口内直观看到分配压力曲
  // 线；停止后会冻结，待下次开启再清空。
  final List<double> _samplingDeltas = <double>[];
  static const int _samplingDeltasMax = 120;
  double? _samplingLastUsed;
  // 采样收尾后的 top-N 函数。
  ({int totalSize, List<({String label, int size, List<String> stack})> top})?
  _samplingResult;
  // ── 阈值告警 ─────────────────────────────────────────────────────────
  // 用户可通过 V8 卡片右侧滑块调整；触发后 60s 冷却防刷屏。
  double _heapWarnThresholdMb = 100;
  DateTime? _lastWarnAt;
  bool _heapBreached = false;

  @override
  void initState() {
    super.initState();
    _heapTimer = startNonOverlappingPeriodicTimer(
      const Duration(milliseconds: 1500),
      (_) => _sampleHeap(),
      onError: (error, stack) =>
          silentLog('web_reverse_dashboard_dialog', '采样堆内存', error, stack),
    );
    unawaited(_sampleHeap());
    // 读回 session metadata 中保存的最近两次堆快照，让用户
    // 关闭 Dashboard 再打开仍能直接「比较」，不必重新采集。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final snaps = context
          .findAncestorStateOfType<_WebReverseDashboardDialogState>()
          ?.readHeapSnapshots();
      if (snaps == null) return;
      setState(() {
        _snapA = snaps.snapA;
        _snapB = snaps.snapB;
      });
    });
  }

  @override
  void dispose() {
    _heapTimer?.cancel();
    super.dispose();
  }

  Future<void> _sampleHeap() async {
    if (!widget.controller.isRunning) return;
    final r = await widget.controller.readJsHeap();
    if (!mounted || r == null) return;
    final usedMb = r.used / kBytesPerKiB / kBytesPerKiB;
    final breached = usedMb > _heapWarnThresholdMb;
    setState(() {
      _heapUsed.add(r.used);
      _heapTotal.add(r.total);
      while (_heapUsed.length > _heapHistoryLen) {
        _heapUsed.removeAt(0);
        _heapTotal.removeAt(0);
      }
      _heapBreached = breached;
      // 采样窗口内追加每 tick 分配增量（正值；GC 回收当 0），
      // 让下方 sparkline 实时反映分配压力。
      if (widget.controller.isMemorySampling) {
        final prev = _samplingLastUsed ?? r.used;
        final delta = math.max(0.0, r.used - prev);
        _samplingDeltas.add(delta);
        while (_samplingDeltas.length > _samplingDeltasMax) {
          _samplingDeltas.removeAt(0);
        }
        _samplingLastUsed = r.used;
      } else {
        _samplingLastUsed = r.used;
      }
    });
    // 触发告警：超过阈值且距上次告警 ≥ 60s 才再次提示。
    if (breached) {
      final now = DateTime.now();
      if (_lastWarnAt == null ||
          now.difference(_lastWarnAt!) > const Duration(seconds: 60)) {
        _lastWarnAt = now;
        if (mounted) {
          showOpenHandErrorSnack(
            context,
            openHandLocalizedText(
              context,
              zh: 'V8 堆已用 ${usedMb.toStringAsFixed(1)} MB，超过阈值 ${_heapWarnThresholdMb.toStringAsFixed(0)} MB',
              zhHant:
                  'V8 堆已用 ${usedMb.toStringAsFixed(1)} MB，超過閾值 ${_heapWarnThresholdMb.toStringAsFixed(0)} MB',
              en: 'V8 heap ${usedMb.toStringAsFixed(1)} MB exceeds threshold ${_heapWarnThresholdMb.toStringAsFixed(0)} MB',
              fr: 'Tas V8 ${usedMb.toStringAsFixed(1)} MB au-dessus du seuil ${_heapWarnThresholdMb.toStringAsFixed(0)} MB',
              de: 'V8-Heap ${usedMb.toStringAsFixed(1)} MB uberschreitet Schwelle ${_heapWarnThresholdMb.toStringAsFixed(0)} MB',
              ja: 'V8 heap ${usedMb.toStringAsFixed(1)} MB がしきい値 ${_heapWarnThresholdMb.toStringAsFixed(0)} MB を超えました',
            ),
            duration: kOpenHandSnackBarNormalDuration,
          );
        }
      }
    }
  }

  Future<void> _toggleSampling() async {
    if (widget.controller.isMemorySampling) {
      final r = await widget.controller.stopMemorySampling();
      if (!mounted) return;
      setState(() => _samplingResult = r);
      if (r == null) {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '采样收尾失败',
            zhHant: '採樣收尾失敗',
            en: 'Stop sampling failed',
            fr: 'Échec de l’arrêt de l’échantillonnage',
            de: 'Sampling konnte nicht beendet werden',
            ja: 'サンプリング停止に失敗しました',
          ),
          duration: kOpenHandSnackBarBriefDuration,
        );
      }
    } else {
      final ok = await widget.controller.startMemorySampling();
      if (!mounted) return;
      if (!ok) {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '采样启动失败',
            zhHant: '採樣啟動失敗',
            en: 'Start sampling failed',
            fr: 'Échec du démarrage de l’échantillonnage',
            de: 'Sampling konnte nicht gestartet werden',
            ja: 'サンプリング開始に失敗しました',
          ),
          duration: kOpenHandSnackBarBriefDuration,
        );
      } else {
        setState(() {
          _samplingResult = null;
          // 清空旧的采样窗口序列，sparkline 从 0 重新累计。
          _samplingDeltas.clear();
          _samplingLastUsed = null;
        });
      }
    }
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    final r = await widget.controller.takeHeapSnapshot();
    if (!mounted) return;
    setState(() {
      _capturing = false;
      _last = r;
      // 滚动两个槽位：B 永远是最新，A 是上一份。
      if (r != null) {
        final fresh = (json: r.json, bytes: r.bytes, ts: DateTime.now());
        _snapA = _snapB;
        _snapB = fresh;
      }
    });
    if (r != null) {
      // 持久化：单份快照可能数 MB（基本是文本 JSON），写一次 metadata
      // 就够；下次打开 Dashboard 自动 readHeapSnapshots 复原 A/B。
      context
          .findAncestorStateOfType<_WebReverseDashboardDialogState>()
          ?.persistHeapSnapshots(snapA: _snapA, snapB: _snapB);
    }
    if (r == null) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '快照采集失败',
          zhHant: '快照採集失敗',
          en: 'Snapshot failed',
          fr: 'Échec de la capture du snapshot',
          de: 'Snapshot fehlgeschlagen',
          ja: 'スナップショット取得に失敗しました',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  /// 在隔离线程比较最近两份堆快照。
  Future<void> _compareSnapshots() async {
    if (_capturing) return;
    final a = _snapA;
    final b = _snapB;
    if (a == null || b == null) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '需要至少两次快照才能比较',
          zhHant: '需要至少兩次快照才能比較',
          en: 'Need at least two snapshots',
          fr: 'Au moins deux snapshots sont nécessaires',
          de: 'Mindestens zwei Snapshots erforderlich',
          ja: '比較には 2 回以上のスナップショットが必要です',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    setState(() => _capturing = true);
    late final _HeapDiffResult result;
    try {
      result = await compute(_heapDiffWorker, <String, String>{
        'a': a.json,
        'b': b.json,
      });
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '比较堆快照', error, stack);
      if (mounted) {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '堆快照比较失败',
            zhHant: '堆快照比較失敗',
            en: 'Heap snapshot comparison failed',
            fr: 'Échec de la comparaison des snapshots du tas',
            de: 'Heap-Snapshot-Vergleich fehlgeschlagen',
            ja: 'ヒープスナップショットの比較に失敗しました',
          ),
          duration: kOpenHandSnackBarBriefDuration,
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
    if (!mounted) return;
    webReverseToolDialogs.show<void>(
      context: context,
      builder: (_) => _SnapshotDiffDialog(
        whenA: a.ts,
        whenB: b.ts,
        bytesA: a.bytes,
        bytesB: b.bytes,
        result: result,
        bJson: b.json,
      ),
    );
  }

  Future<void> _save() async {
    final r = _last;
    if (r == null) return;
    const typeGroup = XTypeGroup(
      label: 'Heap Snapshot',
      extensions: <String>['heapsnapshot'],
    );
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'heap-$ts.heapsnapshot',
        acceptedTypeGroups: const [typeGroup],
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '选择堆数据保存位置', error, stack);
    }
    if (location == null) return;
    try {
      await writeFileAtomically(File(location.path), r.json);
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        webReverseSavedToFileMessage(context, location.path),
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '写入堆数据', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        webReverseSaveFailedMessage(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── V8 实时堆使用折线 ─────────────────────────────────────
          _V8HeapLiveCard(
            used: _heapUsed,
            total: _heapTotal,
            thresholdMb: _heapWarnThresholdMb,
            breached: _heapBreached,
            onThresholdChanged: (v) => setState(() => _heapWarnThresholdMb = v),
          ),
          kOpenHandGap10,
          // 「采样开关 + 实时 sparkline」整合卡片：开关切换会
          // 触发 startSampling / stopSampling；采样窗口内 1.5s 拍一根条柱，
          // 高度 = 该 tick 的 used 增量（>=0），自动归一化。停止后冻结便
          // 于回顾，下次开启自动清空。
          _HeapSamplingSwitchCard(
            isSampling: widget.controller.isMemorySampling,
            deltas: _samplingDeltas,
            onToggle: _toggleSampling,
            reduceMotion: widget.reduceMotion,
          ),
          kOpenHandGap12,
          // ── 采样 / 快照工具栏 ──────────────────────────────────────
          Row(
            children: [
              Text(
                openHandLocalizedText(
                  context,
                  zh: 'V8 堆快照',
                  zhHant: 'V8 堆快照',
                  en: 'V8 Heap Snapshot',
                  fr: 'Snapshot du tas V8',
                  de: 'V8-Heap-Snapshot',
                  ja: 'V8 Heap Snapshot',
                ),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _capturing ? null : _capture,
                icon: Icon(
                  _capturing
                      ? Icons.hourglass_top_rounded
                      : Icons.camera_alt_rounded,
                  size: 18,
                ),
                label: Text(
                  _capturing
                      ? openHandLocalizedText(
                          context,
                          zh: '采集中…',
                          zhHant: '採集中…',
                          en: 'Capturing…',
                          fr: 'Capture…',
                          de: 'Erfassen…',
                          ja: '取得中…',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '采集快照',
                          zhHant: '採集快照',
                          en: 'Capture Snapshot',
                          fr: 'Capturer snapshot',
                          de: 'Snapshot erfassen',
                          ja: 'スナップショット取得',
                        ),
                ),
              ),
              kOpenHandHGap8,
              OutlinedButton.icon(
                onPressed: (!_capturing && _snapA != null && _snapB != null)
                    ? _compareSnapshots
                    : null,
                icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '比较快照',
                    zhHant: '比較快照',
                    en: 'Diff snapshots',
                    fr: 'Comparer snapshots',
                    de: 'Snapshots vergleichen',
                    ja: 'スナップショット比較',
                  ),
                ),
              ),
              kOpenHandHGap8,
              OutlinedButton.icon(
                onPressed: _last == null ? null : _save,
                icon: const Icon(Icons.save_alt_rounded, size: 18),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '保存到文件',
                    zhHant: '儲存到檔案',
                    en: 'Save to File',
                    fr: 'Enregistrer fichier',
                    de: 'In Datei speichern',
                    ja: 'ファイルに保存',
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          if (_samplingResult != null)
            Expanded(child: _SamplingTopList(result: _samplingResult!))
          else if (_last != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: webReverseSurfaceCardDecoration(cs, radius: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '最近一次快照',
                      zhHant: '最近一次快照',
                      en: 'Latest Snapshot',
                      fr: 'Dernier snapshot',
                      de: 'Letzter Snapshot',
                      ja: '最新スナップショット',
                    ),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  kOpenHandGap6,
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '原始大小约 ${formatByteSize(_last!.bytes)} · 可保存为 .heapsnapshot 后在 Chrome DevTools → Memory → Load 里打开重放。',
                      zhHant:
                          '原始大小約 ${formatByteSize(_last!.bytes)} · 可儲存為 .heapsnapshot 後在 Chrome DevTools → Memory → Load 裡開啟重放。',
                      en: '~${formatByteSize(_last!.bytes)} · save as .heapsnapshot and load it back in Chrome DevTools.',
                      fr: '~${formatByteSize(_last!.bytes)} · enregistrez en .heapsnapshot puis chargez dans Chrome DevTools.',
                      de: '~${formatByteSize(_last!.bytes)} · als .heapsnapshot speichern und in Chrome DevTools laden.',
                      ja: '約 ${formatByteSize(_last!.bytes)} · .heapsnapshot として保存し Chrome DevTools で読み込めます。',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              openHandLocalizedText(
                context,
                zh: '点击「采集快照」拉一次 V8 堆快照；或「开始采样」做分配采样直到停止后看 Top-N。',
                zhHant: '點擊「採集快照」拉一次 V8 堆快照；或「開始採樣」做分配採樣直到停止後看 Top-N。',
                en: 'Click "Capture Snapshot" to take a heap snapshot, or start sampling for top-N allocation profile.',
                fr: 'Cliquez sur Capturer snapshot, ou lancez l’échantillonnage pour voir le Top-N à l’arrêt.',
                de: 'Snapshot erfassen oder Sampling starten, um danach das Top-N-Allokationsprofil zu sehen.',
                ja: '「スナップショット取得」で V8 heap snapshot を取得するか、サンプリングを開始して停止後に Top-N を確認します。',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.55,
              ),
            ),
        ],
      ),
    );
  }
}

/// V8 堆 Used/Total 实时折线卡片。
/// 支持告警阈值滑块；超过阈值时卡片描边变红、Used 数字加色，
/// Sparkline 颜色顺势切到 error 色，让用户一眼看到内存压力。
class _V8HeapLiveCard extends StatelessWidget {
  const _V8HeapLiveCard({
    required this.used,
    required this.total,
    required this.thresholdMb,
    required this.breached,
    required this.onThresholdChanged,
  });

  final List<double> used;
  final List<double> total;
  final double thresholdMb;
  final bool breached;
  final ValueChanged<double> onThresholdChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lastUsed = used.isEmpty ? 0.0 : used.last;
    final lastTotal = total.isEmpty ? 0.0 : total.last;
    final usedColor = breached ? cs.error : cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(
          color: breached ? cs.error : cs.outlineVariant,
          width: breached ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: 'V8 堆（实时，1.5s 间隔）',
                        zhHant: 'V8 堆（即時，1.5s 間隔）',
                        en: 'V8 Heap (live, 1.5s)',
                        fr: 'Tas V8 (live, 1,5 s)',
                        de: 'V8-Heap (live, 1,5 s)',
                        ja: 'V8 Heap（ライブ、1.5s 間隔）',
                      ),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (breached) ...[
                      kOpenHandHGap6,
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: cs.error,
                      ),
                    ],
                  ],
                ),
                kOpenHandGap4,
                Text(
                  '${openHandLocalizedText(context, zh: "已用", zhHant: "已用", en: "Used", fr: "Utilise", de: "Genutzt", ja: "使用済み")}: ${formatByteSize(lastUsed)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: usedColor,
                  ),
                ),
                Text(
                  '${openHandLocalizedText(context, zh: "总量", zhHant: "總量", en: "Total", fr: "Total", de: "Gesamt", ja: "合計")}: ${formatByteSize(lastTotal)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 72,
              child: _AnimatedDualSparkline(
                primary: used,
                secondary: total,
                primaryColor: usedColor,
                secondaryColor: cs.tertiary,
              ),
            ),
          ),
          // 阈值控件：左侧标题 + 滑块 + 当前值。宽度固定 220 防止挤压 sparkline。
          SizedBox(
            width: 220,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 13,
                        color: cs.onSurfaceVariant,
                      ),
                      kOpenHandHGap4,
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '阈值告警',
                          zhHant: '閾值告警',
                          en: 'Threshold',
                          fr: 'Seuil',
                          de: 'Schwelle',
                          ja: 'しきい値',
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${thresholdMb.toStringAsFixed(0)} MB',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          color: breached ? cs.error : cs.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: breached ? cs.error : cs.primary,
                      thumbColor: breached ? cs.error : cs.primary,
                    ),
                    child: Slider(
                      min: 32,
                      max: 1024,
                      divisions: 31,
                      value: thresholdMb.clamp(32, 1024).toDouble(),
                      onChanged: onThresholdChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DualLineSparkline extends CustomPainter {
  _DualLineSparkline({
    required this.primary,
    required this.secondary,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final List<double> primary;
  final List<double> secondary;
  final Color primaryColor;
  final Color secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (primary.length < 2) return;
    final all = [...primary, ...secondary];
    var min = all.first;
    var max = all.first;
    for (final v in all) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final span = (max - min).abs() < 1e-9 ? 1 : (max - min);
    Path build(List<double> values, {required bool fill}) {
      final p = Path();
      final stride = size.width / (values.length - 1);
      for (var i = 0; i < values.length; i++) {
        final x = i * stride;
        final norm = (values[i] - min) / span;
        final y = size.height - norm * size.height;
        if (i == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      if (fill) {
        p.lineTo(size.width, size.height);
        p.lineTo(0, size.height);
        p.close();
      }
      return p;
    }

    canvas.drawPath(
      build(secondary, fill: true),
      Paint()
        ..color = secondaryColor.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      build(secondary, fill: false),
      Paint()
        ..color = secondaryColor
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      build(primary, fill: true),
      Paint()
        ..color = primaryColor.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      build(primary, fill: false),
      Paint()
        ..color = primaryColor
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _DualLineSparkline old) =>
      old.primary != primary || old.secondary != secondary;
}

/// 平滑动画版双线 Sparkline：与 [_AnimatedSparkline] 同思路，
/// 在 primary / secondary 数据更新时用 240ms 缓动把上一帧线性插值到下一帧，
/// 配合 V8 实时 1.5s 采样让"已用 / 总量"的曲线呈现 Q 弹流动感。
class _AnimatedDualSparkline extends StatefulWidget {
  const _AnimatedDualSparkline({
    required this.primary,
    required this.secondary,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final List<double> primary;
  final List<double> secondary;
  final Color primaryColor;
  final Color secondaryColor;

  @override
  State<_AnimatedDualSparkline> createState() => _AnimatedDualSparklineState();
}

class _AnimatedDualSparklineState extends State<_AnimatedDualSparkline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: kOpenHandMotion240,
  );
  late List<double> _fromPri = List<double>.from(widget.primary);
  late List<double> _toPri = List<double>.from(widget.primary);
  late List<double> _fromSec = List<double>.from(widget.secondary);
  late List<double> _toSec = List<double>.from(widget.secondary);

  @override
  void didUpdateWidget(covariant _AnimatedDualSparkline old) {
    super.didUpdateWidget(old);
    final reduceMotion = !_wrMotionEnabled(context);
    var changed = false;
    if (!listEquals(old.primary, widget.primary)) {
      _fromPri = _resampleSparklineValues(_curPri(), widget.primary.length);
      _toPri = List<double>.from(widget.primary);
      changed = true;
    }
    if (!listEquals(old.secondary, widget.secondary)) {
      _fromSec = _resampleSparklineValues(_curSec(), widget.secondary.length);
      _toSec = List<double>.from(widget.secondary);
      changed = true;
    }
    if (changed) {
      if (reduceMotion) {
        _ac.value = 1;
      } else {
        _ac
          ..reset()
          ..animateTo(1, curve: kOpenHandSwitchInCurve);
      }
    }
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  List<double> _curPri() {
    if (_fromPri.length != _toPri.length || _ac.value == 1) return _toPri;
    final t = _ac.value;
    return List<double>.generate(
      _toPri.length,
      (i) => _fromPri[i] + (_toPri[i] - _fromPri[i]) * t,
    );
  }

  List<double> _curSec() {
    if (_fromSec.length != _toSec.length || _ac.value == 1) return _toSec;
    final t = _ac.value;
    return List<double>.generate(
      _toSec.length,
      (i) => _fromSec[i] + (_toSec[i] - _fromSec[i]) * t,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, _) => CustomPaint(
        painter: _DualLineSparkline(
          primary: _curPri(),
          secondary: _curSec(),
          primaryColor: widget.primaryColor,
          secondaryColor: widget.secondaryColor,
        ),
      ),
    );
  }
}

// Memory: 「采样开关 + 实时 sparkline」整合卡片。Switch 触发 HeapProfiler.
// startSampling / stopSampling；采样窗口内 1.5s 拍一根柱，宽度自适应、高
// 度按窗内峰值归一。停止后冻结柱序，便于回放分配压力曲线。reduceMotion 时
// 仍渲染但不做柱条动画。
class _HeapSamplingSwitchCard extends StatelessWidget {
  const _HeapSamplingSwitchCard({
    required this.isSampling,
    required this.deltas,
    required this.onToggle,
    required this.reduceMotion,
  });

  final bool isSampling;
  final List<double> deltas;
  final Future<void> Function() onToggle;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final peak = deltas.isEmpty ? 0.0 : deltas.reduce((a, b) => a > b ? a : b);
    final total = deltas.isEmpty ? 0.0 : deltas.reduce((a, b) => a + b);
    final activeBorder = isSampling ? cs.primary : cs.outlineVariant;
    final activeBg = isSampling
        ? cs.primaryContainer.withValues(alpha: 0.18)
        : cs.surfaceContainerHigh;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: activeBg,
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: activeBorder, width: isSampling ? 1.4 : 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      isSampling
                          ? Icons.radio_button_checked_rounded
                          : Icons.timeline_rounded,
                      size: 14,
                      color: isSampling ? cs.primary : cs.onSurfaceVariant,
                    ),
                    kOpenHandHGap4,
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '堆分配采样',
                        zhHant: '堆分配採樣',
                        en: 'Heap allocation sampling',
                        fr: 'Échantillonnage allocations heap',
                        de: 'Heap-Allokationssampling',
                        ja: 'Heap 割り当てサンプリング',
                      ),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                kOpenHandGap6,
                Text(
                  isSampling
                      ? openHandLocalizedText(
                          context,
                          zh: '采样中…',
                          zhHant: '採樣中…',
                          en: 'Sampling…',
                          fr: 'Échantillonnage…',
                          de: 'Sampling…',
                          ja: 'サンプリング中…',
                        )
                      : (deltas.isEmpty
                            ? openHandLocalizedText(
                                context,
                                zh: '未开启',
                                zhHant: '未啟用',
                                en: 'Off',
                                fr: 'Désactivé',
                                de: 'Aus',
                                ja: 'オフ',
                              )
                            : openHandStoppedLabel(context)),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isSampling ? cs.primary : cs.onSurface,
                  ),
                ),
                if (deltas.isNotEmpty)
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '峰值 ${formatByteSize(peak)} · 累计 ${formatByteSize(total)}',
                      zhHant:
                          '峰值 ${formatByteSize(peak)} · 累計 ${formatByteSize(total)}',
                      en: 'peak ${formatByteSize(peak)} · sum ${formatByteSize(total)}',
                      fr: 'pic ${formatByteSize(peak)} · somme ${formatByteSize(total)}',
                      de: 'Peak ${formatByteSize(peak)} · Summe ${formatByteSize(total)}',
                      ja: 'ピーク ${formatByteSize(peak)} · 合計 ${formatByteSize(total)}',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: 44,
                child: deltas.isEmpty
                    ? OpenHandInlineEmptyState(
                        message: openHandLocalizedText(
                          context,
                          zh: '开启后每 1.5s 记录一次分配增量',
                          zhHant: '啟用後每 1.5s 記錄一次分配增量',
                          en: 'Records allocation deltas every 1.5s',
                          fr: 'Enregistre les deltas d’allocation toutes les 1,5 s',
                          de: 'Erfasst Allokationsdeltas alle 1,5 s',
                          ja: '有効化後、1.5 秒ごとに割り当て増分を記録します',
                        ),
                        dense: true,
                      )
                    : CustomPaint(
                        painter: _HeapSamplingBarsPainter(
                          deltas: deltas,
                          color: isSampling ? cs.primary : cs.secondary,
                          peak: peak,
                        ),
                        size: Size.infinite,
                      ),
              ),
            ),
          ),
          Tooltip(
            message: isSampling
                ? openHandLocalizedText(
                    context,
                    zh: '关闭后保留窗口柱条',
                    zhHant: '關閉後保留窗口柱條',
                    en: 'Off keeps bars',
                    fr: 'Désactivé garde les barres',
                    de: 'Aus behalt Balken',
                    ja: 'オフ後もバーを保持',
                  )
                : openHandLocalizedText(
                    context,
                    zh: '开启堆分配采样',
                    zhHant: '啟用堆分配採樣',
                    en: 'Start heap sampling',
                    fr: 'Démarrer échantillonnage heap',
                    de: 'Heap-Sampling starten',
                    ja: 'Heap サンプリングを開始',
                  ),
            child: Switch.adaptive(
              value: isSampling,
              onChanged: (_) => onToggle(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeapSamplingBarsPainter extends CustomPainter {
  _HeapSamplingBarsPainter({
    required this.deltas,
    required this.color,
    required this.peak,
  });

  final List<double> deltas;
  final Color color;
  final double peak;

  @override
  void paint(Canvas canvas, Size size) {
    if (deltas.isEmpty || size.width <= 0 || size.height <= 0) return;
    final n = deltas.length;
    final slot = size.width / n;
    final barWidth = math.max(1.0, slot - 1.5);
    final norm = peak <= 0 ? 1.0 : peak;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < n; i++) {
      final v = deltas[i];
      final hRatio = unitRatio(v, norm);
      // 视觉低位至少 1.5px，保证 0 增量也有薄基线提示采样仍在跑。
      final h = math.max(1.5, size.height * hRatio);
      final x = i * slot + (slot - barWidth) / 2;
      final y = size.height - h;
      final alpha = v <= 0 ? 0.35 : (0.55 + 0.45 * hRatio);
      paint.color = color.withValues(alpha: alpha);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeapSamplingBarsPainter old) =>
      old.deltas.length != deltas.length ||
      (old.deltas.isNotEmpty &&
          deltas.isNotEmpty &&
          old.deltas.last != deltas.last) ||
      old.peak != peak ||
      old.color != color;
}

class _SamplingTopList extends StatelessWidget {
  const _SamplingTopList({required this.result});
  final ({
    int totalSize,
    List<({String label, int size, List<String> stack})> top,
  })
  result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: webReverseSurfaceCardDecoration(cs, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                openHandLocalizedText(
                  context,
                  zh: '采样 Top-N（按 selfSize）',
                  zhHant: '採樣 Top-N（按 selfSize）',
                  en: 'Sampling Top-N (selfSize)',
                  fr: 'Top-N échantillonnage (selfSize)',
                  de: 'Sampling Top-N (selfSize)',
                  ja: 'サンプリング Top-N（selfSize）',
                ),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                openHandLocalizedText(
                  context,
                  zh: '总分配 ${formatByteSize(result.totalSize)}',
                  zhHant: '總分配 ${formatByteSize(result.totalSize)}',
                  en: 'Total ${formatByteSize(result.totalSize)}',
                  fr: 'Total ${formatByteSize(result.totalSize)}',
                  de: 'Gesamt ${formatByteSize(result.totalSize)}',
                  ja: '合計 ${formatByteSize(result.totalSize)}',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          kOpenHandGap6,
          Expanded(
            child: ListView.builder(
              itemCount: result.top.length,
              itemBuilder: (_, i) {
                final r = result.top[i];
                final ratio = unitRatio(r.size, result.totalSize);
                return InkWell(
                  onTap: () => _showStack(context, r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '#${i + 1}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            r.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: kOpenHandMonospaceFontFamily,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Stack(
                            children: [
                              Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainer,
                                  borderRadius: BorderRadius.circular(
                                    kOpenHandRadius3,
                                  ),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: ratio.clamp(0.0, 1.0),
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(
                                      kOpenHandRadius3,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        kOpenHandHGap10,
                        SizedBox(
                          width: 84,
                          child: Text(
                            formatByteSize(r.size),
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: kOpenHandMonospaceFontFamily,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showStack(
    BuildContext context,
    ({String label, int size, List<String> stack}) row,
  ) {
    webReverseToolDialogs.show<void>(
      context: context,
      builder: (dialogContext) {
        return buildOpenHandAlertDialog(
          title: Text(
            openHandLocalizedText(
              dialogContext,
              zh: '调用栈：${row.label}',
              zhHant: '呼叫堆疊：${row.label}',
              en: 'Call stack: ${row.label}',
              fr: 'Pile d’appels : ${row.label}',
              de: 'Call Stack: ${row.label}',
              ja: 'コールスタック: ${row.label}',
            ),
          ),
          content: SizedBox(
            width: 720,
            height: 420,
            child: row.stack.isEmpty
                ? Center(
                    child: Text(
                      openHandLocalizedText(
                        dialogContext,
                        zh: '(此节点无父级链)',
                        zhHant: '(此節點無父級鏈)',
                        en: '(no parent stack)',
                        fr: '(aucune pile parente)',
                        de: '(kein Parent-Stack)',
                        ja: '（親スタックなし）',
                      ),
                      style: TextStyle(
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: row.stack.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final entry = row.stack[row.stack.length - 1 - i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 32,
                              child: Text(
                                '#$i',
                                style: const TextStyle(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                entry,
                                style: const TextStyle(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () async {
                final copied = await copyWebReverseTextToClipboard(
                  context: context,
                  text: row.stack.join('\n'),
                  logTag: 'web_reverse_memory_panel',
                  logAction: '复制调用栈',
                  showSuccess: false,
                );
                if (copied == null) return;
                if (!dialogContext.mounted || !context.mounted) return;
                Navigator.of(dialogContext).pop();
                showWebReverseClipboardSuccessSnack(
                  context: context,
                  base: openHandCopiedLabel(context),
                  result: copied,
                );
              },
              label: openHandLocalizedText(
                dialogContext,
                zh: '复制',
                zhHant: '複製',
                en: 'Copy',
                fr: 'Copier',
                de: 'Kopieren',
                ja: 'コピー',
              ),
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: openHandCloseLabel(dialogContext),
            ),
          ],
        );
      },
    );
  }
}

// Application：Cookies / Local Storage / Session Storage（按 origin 切换）

class _ApplicationPanel extends StatefulWidget {
  const _ApplicationPanel({
    required this.controller,
    required this.isZh,
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
  final bool isZh;
  final bool reduceMotion;

  @override
  State<_ApplicationPanel> createState() => _ApplicationPanelState();
}

enum _AppTab {
  cookies,
  localStorage,
  sessionStorage,
  indexedDb,
  cacheStorage,
  serviceWorkers,
}

class _ApplicationPanelState extends State<_ApplicationPanel> {
  static const int _indexedDbDescribeConcurrency = 4;
  static const Duration _indexedDbDescribeTotalTimeout = Duration(seconds: 30);
  static const int _indexedDbMaxDescribedStores = 4096;
  static const int _indexedDbMaxSchemaChars = 4 * kBytesPerMiB;

  _AppTab _tab = _AppTab.cookies;
  String? _origin;
  List<Map<String, Object?>> _cookies = const [];
  List<({String key, String value})> _storage = const [];
  List<String> _idbNames = const [];
  Map<String, ({int version, List<String> stores})> _idbDescribed =
      const <String, ({int version, List<String> stores})>{};
  List<String> _cacheNames = const [];
  List<Map<String, Object?>> _swVersions = const [];
  bool _loading = false;
  bool _refreshQueued = false;
  Future<void>? _refreshTask;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() {
    _refreshQueued = true;
    final pending = _refreshTask;
    if (pending != null) return pending;
    late final Future<void> task;
    task = _drainRefreshQueue().whenComplete(() {
      if (identical(_refreshTask, task)) _refreshTask = null;
    });
    _refreshTask = task;
    return task;
  }

  Future<void> _drainRefreshQueue() async {
    if (mounted) setState(() => _loading = true);
    try {
      while (mounted && _refreshQueued) {
        _refreshQueued = false;
        await _refreshOnce();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshOnce() async {
    final tab = _tab;
    final origin = await widget.controller.currentOrigin();
    List<Map<String, Object?>> cookies = const [];
    List<({String key, String value})> storage = const [];
    List<String> idbNames = const [];
    var idbDescribed = const <String, ({int version, List<String> stores})>{};
    List<String> cacheNames = const [];
    List<Map<String, Object?>> swVersions = const [];
    if (tab == _AppTab.cookies) {
      cookies = await widget.controller.listCookies();
    } else if (tab == _AppTab.localStorage || tab == _AppTab.sessionStorage) {
      if (origin != null && origin.isNotEmpty) {
        storage = await widget.controller.listDomStorage(
          origin: origin,
          isLocalStorage: tab == _AppTab.localStorage,
        );
      }
    } else if (tab == _AppTab.indexedDb) {
      idbNames = await widget.controller.listIndexedDbNames();
      final acc = <String, ({int version, List<String> stores})>{};
      var retainedStores = 0;
      var retainedSchemaChars = 0;
      final stopwatch = Stopwatch()..start();
      await forEachIndexWithConcurrencyLimit(
        itemCount: idbNames.length,
        maxConcurrency: _indexedDbDescribeConcurrency,
        shouldContinue: () =>
            mounted &&
            _tab == tab &&
            stopwatch.elapsed < _indexedDbDescribeTotalTimeout &&
            retainedStores < _indexedDbMaxDescribedStores &&
            retainedSchemaChars < _indexedDbMaxSchemaChars,
        task: (index) async {
          final name = idbNames[index];
          final info = await widget.controller.describeIndexedDb(name);
          if (info != null) {
            final schemaChars =
                name.length +
                info.stores.fold<int>(
                  0,
                  (total, store) => total + store.length,
                );
            if (retainedStores + info.stores.length >
                    _indexedDbMaxDescribedStores ||
                retainedSchemaChars + schemaChars > _indexedDbMaxSchemaChars) {
              return;
            }
            retainedStores += info.stores.length;
            retainedSchemaChars += schemaChars;
            acc[name] = (version: info.version, stores: info.stores);
          }
        },
      );
      idbDescribed = acc;
    } else if (tab == _AppTab.cacheStorage) {
      cacheNames = await widget.controller.listCacheStorage();
    } else if (tab == _AppTab.serviceWorkers) {
      swVersions = await widget.controller.listServiceWorkers();
    }
    if (!mounted || tab != _tab) return;
    setState(() {
      _origin = origin;
      if (tab == _AppTab.cookies) _cookies = cookies;
      if (tab == _AppTab.localStorage || tab == _AppTab.sessionStorage) {
        _storage = storage;
      }
      if (tab == _AppTab.indexedDb) {
        _idbNames = idbNames;
        _idbDescribed = idbDescribed;
      }
      if (tab == _AppTab.cacheStorage) _cacheNames = cacheNames;
      if (tab == _AppTab.serviceWorkers) _swVersions = swVersions;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in _AppTab.values)
                _TextTabPill(
                  label: _appTabLabel(t, isZh),
                  active: _tab == t,
                  onTap: () {
                    setState(() => _tab = t);
                    _refresh();
                  },
                ),
            ],
          ),
          kOpenHandGap10,
          Row(
            children: [
              if (_origin != null)
                Expanded(
                  child: Text(
                    _origin!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFamily: kOpenHandMonospaceFontFamily,
                    ),
                  ),
                ),
              IconButton(
                tooltip: openHandRefreshLabel(context),
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
            ],
          ),
          kOpenHandGap8,
          Expanded(
            child: switch (_tab) {
              _AppTab.cookies => _CookiesTable(
                cookies: _cookies,
                controller: widget.controller,
                onChanged: _refresh,
              ),
              _AppTab.localStorage || _AppTab.sessionStorage => _StorageTable(
                rows: _storage,
                controller: widget.controller,
                origin: _origin,
                isLocalStorage: _tab == _AppTab.localStorage,
                onChanged: _refresh,
              ),
              _AppTab.indexedDb => _IndexedDbTable(
                controller: widget.controller,
                names: _idbNames,
                described: _idbDescribed,
                onChanged: _refresh,
              ),
              _AppTab.cacheStorage => _NameListPanel(names: _cacheNames),
              _AppTab.serviceWorkers => _ServiceWorkersTable(
                versions: _swVersions,
                controller: widget.controller,
                onChanged: _refresh,
              ),
            },
          ),
        ],
      ),
    );
  }

  String _appTabLabel(_AppTab t, bool isZh) => switch (t) {
    _AppTab.cookies => 'Cookies',
    _AppTab.localStorage => 'Local Storage',
    _AppTab.sessionStorage => 'Session Storage',
    _AppTab.indexedDb => 'IndexedDB',
    _AppTab.cacheStorage => 'Cache Storage',
    _AppTab.serviceWorkers => 'Service Workers',
  };
}

class _CookiesTable extends StatefulWidget {
  const _CookiesTable({
    required this.cookies,
    required this.controller,
    required this.onChanged,
  });
  final List<Map<String, Object?>> cookies;
  final WebReverseSessionController controller;
  final Future<void> Function() onChanged;

  @override
  State<_CookiesTable> createState() => _CookiesTableState();
}

class _CookiesTableState extends State<_CookiesTable> {
  final ScrollController _hCtrl = ScrollController();

  @override
  void dispose() {
    _hCtrl.dispose();
    super.dispose();
  }

  Future<void> _addCookie() =>
      _upsertCookie(initial: const <String, Object?>{});

  Future<void> _editCookie(Map<String, Object?> cookie) =>
      _upsertCookie(initial: cookie);

  /// 新增与编辑共用同一条落库路径：弹编辑器 → 写入 → 回调刷新。
  Future<void> _upsertCookie({required Map<String, Object?> initial}) async {
    final saved = await _showCookieEditor(context, initial: initial);
    if (saved == null || !mounted) return;
    final ok = await widget.controller.setCookie(
      name: '${saved['name'] ?? ''}',
      value: '${saved['value'] ?? ''}',
      domain: _cookieScopeValue(saved['domain']),
      path: _cookieScopeValue(saved['path']),
      partitionKey: _cookiePartitionKey(saved['partitionKey']),
    );
    if (ok && mounted) await widget.onChanged();
  }

  Future<void> _deleteCookie(Map<String, Object?> cookie) async {
    await widget.controller.deleteCookie(
      name: '${cookie['name'] ?? ''}',
      domain: _cookieScopeValue(cookie['domain']),
      path: _cookieScopeValue(cookie['path']),
      partitionKey: _cookiePartitionKey(cookie['partitionKey']),
    );
    if (mounted) await widget.onChanged();
  }

  /// domain / path 留空表示「不限定」，统一折叠为 null 交给 CDP。
  static String? _cookieScopeValue(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  static Map<String, Object?>? _cookiePartitionKey(Object? value) =>
      value is Map ? stringKeyedMapFromValue(value) : null;

  Future<void> _clearAll() async {
    if (widget.cookies.isEmpty) return;
    final ok = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '清空全部 cookie？',
        zhHant: '清空全部 cookie？',
        en: 'Clear all cookies?',
        fr: 'Effacer tous les cookies ?',
        de: 'Alle Cookies löschen?',
        ja: 'すべての cookie をクリアしますか？',
      ),
      message: openHandLocalizedText(
        context,
        zh: '将清空当前浏览器会话中的全部 cookie，无法撤销。',
        zhHant: '將清空目前瀏覽器工作階段中的全部 cookie，無法復原。',
        en: 'This clears all cookies in the current browser session and cannot be undone.',
        fr: 'Tous les cookies de la session actuelle seront supprimés. Cette action est irréversible.',
        de: 'Alle Cookies der aktuellen Browsersitzung werden gelöscht. Dies kann nicht rückgängig gemacht werden.',
        ja: '現在のブラウザーセッションのすべての cookie を消去します。元に戻せません。',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandClearLabel(context),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final cleared = await widget.controller.clearAllCookies();
    if (cleared && mounted) await widget.onChanged();
  }

  Future<void> _exportJson() async {
    final encoded = prettyPrintJson(widget.cookies);
    await copyWebReverseTextToClipboard(
      context: context,
      text: encoded,
      successBase: openHandLocalizedText(
        context,
        zh: '已复制 ${widget.cookies.length} 条 cookie 到剪贴板',
        zhHant: '已複製 ${widget.cookies.length} 筆 cookie 到剪貼簿',
        en: 'Copied ${widget.cookies.length} cookies to clipboard',
        fr: '${widget.cookies.length} cookies copiés dans le presse-papiers',
        de: '${widget.cookies.length} Cookies in die Zwischenablage kopiert',
        ja: '${widget.cookies.length} 件の cookie をクリップボードにコピーしました',
      ),
      logTag: 'web_reverse_cookies_panel',
      logAction: '复制导出内容',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cookies = widget.cookies;
    return Column(
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: _addCookie,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(_webReverseDashAddCookieLabel(context)),
            ),
            kOpenHandHGap4,
            TextButton.icon(
              onPressed: cookies.isEmpty ? null : _exportJson,
              icon: const Icon(Icons.copy_all_rounded, size: 16),
              label: Text(openHandExportJsonLabel(context)),
            ),
            kOpenHandHGap4,
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: cs.error),
              onPressed: cookies.isEmpty ? null : _clearAll,
              icon: const Icon(Icons.delete_sweep_rounded, size: 16),
              label: Text(_webReverseDashClearAllLabel(context)),
            ),
          ],
        ),
        Expanded(
          child: cookies.isEmpty
              ? OpenHandInlineEmptyState(
                  message: _webReverseDashEmptyLabel(context),
                  dense: true,
                )
              : OpenHandSafeScrollbar(
                  controller: _hCtrl,
                  child: SingleChildScrollView(
                    controller: _hCtrl,
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowHeight: 30,
                        dataRowMinHeight: 24,
                        dataRowMaxHeight: 36,
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Value')),
                          DataColumn(label: Text('Domain')),
                          DataColumn(label: Text('Path')),
                          DataColumn(label: Text('Expires')),
                          DataColumn(label: Text('HttpOnly')),
                          DataColumn(label: Text('Secure')),
                          DataColumn(label: Text('SameSite')),
                          DataColumn(label: Text('')),
                        ],
                        rows: [
                          for (final c in cookies)
                            DataRow(
                              cells: [
                                DataCell(_mono('${c['name'] ?? ''}')),
                                DataCell(
                                  _mono(
                                    clipTextWithEllipsis(
                                      '${c['value'] ?? ''}',
                                      80,
                                    ),
                                  ),
                                ),
                                DataCell(_mono('${c['domain'] ?? ''}')),
                                DataCell(_mono('${c['path'] ?? ''}')),
                                DataCell(_mono(_formatExpires(c['expires']))),
                                DataCell(
                                  Text(c['httpOnly'] == true ? '✓' : ''),
                                ),
                                DataCell(Text(c['secure'] == true ? '✓' : '')),
                                DataCell(_mono('${c['sameSite'] ?? ''}')),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: _wrEditLabel(context),
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 16,
                                        padding: const EdgeInsets.all(6),
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        onPressed:
                                            c['partitionKeyOpaque'] == true
                                            ? null
                                            : () => _editCookie(c),
                                        icon: const Icon(Icons.edit_rounded),
                                      ),
                                      kOpenHandHGap4,
                                      IconButton(
                                        tooltip: openHandDeleteLabel(context),
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 16,
                                        padding: const EdgeInsets.all(6),
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        onPressed:
                                            c['partitionKeyOpaque'] == true
                                            ? null
                                            : () => _deleteCookie(c),
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          color: cs.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _mono(String s) => Text(
    s,
    style: const TextStyle(
      fontFamily: kOpenHandMonospaceFontFamily,
      fontSize: 12,
    ),
  );

  String _formatExpires(Object? raw) {
    if (raw == null) return '';
    final n = raw is num ? raw.toDouble() : 0;
    if (n <= 0) return 'Session';
    final dt = DateTime.fromMillisecondsSinceEpoch((n * 1000).toInt());
    return dt.toIso8601String().split('.').first;
  }
}

/// Cookie 编辑对话框（新增 / 编辑共用）。
Future<Map<String, Object?>?> _showCookieEditor(
  BuildContext context, {
  required Map<String, Object?> initial,
}) async {
  final name = TextEditingController(text: '${initial['name'] ?? ''}');
  final value = TextEditingController(text: '${initial['value'] ?? ''}');
  final domain = TextEditingController(text: '${initial['domain'] ?? ''}');
  final path = TextEditingController(text: '${initial['path'] ?? '/'}');
  try {
    return await showOpenHandFormDialog<Map<String, Object?>>(
      context: context,
      title: initial.isEmpty
          ? _webReverseDashAddCookieLabel(context)
          : openHandLocalizedText(
              context,
              zh: '编辑 cookie',
              zhHant: '編輯 cookie',
              en: 'Edit cookie',
              fr: 'Modifier cookie',
              de: 'Cookie bearbeiten',
              ja: 'cookie を編集',
            ),
      submitLabel: openHandSaveLabel(context),
      cancelLabel: openHandCancelLabel(context),
      maxWidth: 360,
      onSubmit: (_) => <String, Object?>{
        'name': name.text.trim(),
        'value': value.text,
        'domain': domain.text.trim(),
        'path': path.text.trim(),
        if (initial['partitionKey'] case final partitionKey?)
          'partitionKey': partitionKey,
      },
      contentBuilder: (_) => SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: WebReverseSessionController.maxCookieNameChars,
              decoration: const InputDecoration(
                labelText: 'Name',
                counterText: '',
              ),
            ),
            kOpenHandGap10,
            TextField(
              controller: value,
              maxLines: 3,
              maxLength: WebReverseSessionController.maxCookieValueChars,
              decoration: const InputDecoration(
                labelText: 'Value',
                counterText: '',
              ),
            ),
            kOpenHandGap10,
            TextField(
              controller: domain,
              maxLength: WebReverseSessionController.maxCookieDomainChars,
              decoration: const InputDecoration(
                labelText: 'Domain',
                counterText: '',
              ),
            ),
            kOpenHandGap10,
            TextField(
              controller: path,
              maxLength: WebReverseSessionController.maxCookiePathChars,
              decoration: const InputDecoration(
                labelText: 'Path',
                counterText: '',
              ),
            ),
          ],
        ),
      ),
    );
  } finally {
    name.dispose();
    value.dispose();
    domain.dispose();
    path.dispose();
  }
}

class _StorageTable extends StatefulWidget {
  const _StorageTable({
    required this.rows,
    required this.controller,
    required this.origin,
    required this.isLocalStorage,
    required this.onChanged,
  });

  final List<({String key, String value})> rows;
  final WebReverseSessionController controller;
  final String? origin;
  final bool isLocalStorage;
  final Future<void> Function() onChanged;

  @override
  State<_StorageTable> createState() => _StorageTableState();
}

class _StorageTableState extends State<_StorageTable> {
  Future<void> _add() async {
    final origin = widget.origin;
    if (origin == null || origin.isEmpty) return;
    final saved = await _showStorageEditor(
      context,
      initialKey: '',
      initialValue: '',
    );
    if (saved == null || !mounted) return;
    await widget.controller.setDomStorageItem(
      origin: origin,
      isLocalStorage: widget.isLocalStorage,
      key: saved.key,
      value: saved.value,
    );
    if (mounted) await widget.onChanged();
  }

  Future<void> _edit(({String key, String value}) r) async {
    final origin = widget.origin;
    if (origin == null || origin.isEmpty) return;
    final saved = await _showStorageEditor(
      context,
      initialKey: r.key,
      initialValue: r.value,
    );
    if (saved == null || !mounted) return;
    if (saved.key != r.key) {
      // key 改了，先删旧再写新。
      await widget.controller.removeDomStorageItem(
        origin: origin,
        isLocalStorage: widget.isLocalStorage,
        key: r.key,
      );
    }
    await widget.controller.setDomStorageItem(
      origin: origin,
      isLocalStorage: widget.isLocalStorage,
      key: saved.key,
      value: saved.value,
    );
    if (mounted) await widget.onChanged();
  }

  Future<void> _delete(({String key, String value}) r) async {
    final origin = widget.origin;
    if (origin == null || origin.isEmpty) return;
    await widget.controller.removeDomStorageItem(
      origin: origin,
      isLocalStorage: widget.isLocalStorage,
      key: r.key,
    );
    if (mounted) await widget.onChanged();
  }

  Future<void> _clearAll() async {
    final origin = widget.origin;
    if (origin == null || origin.isEmpty || widget.rows.isEmpty) return;
    final storageKind = widget.isLocalStorage
        ? 'localStorage'
        : 'sessionStorage';
    final ok = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '清空全部条目？',
        zhHant: '清空全部項目？',
        en: 'Clear all entries?',
        fr: 'Effacer toutes les entrées ?',
        de: 'Alle Einträge leeren?',
        ja: 'すべてのエントリをクリアしますか？',
      ),
      message: openHandLocalizedText(
        context,
        zh: '将删除 ${widget.rows.length} 条 $storageKind 条目，无法撤销。',
        zhHant: '將刪除 ${widget.rows.length} 筆 $storageKind 項目，無法復原。',
        en: 'Will delete ${widget.rows.length} entries. This cannot be undone.',
        fr: 'Supprime ${widget.rows.length} entrées. Cette action est irréversible.',
        de: 'Löscht ${widget.rows.length} Einträge. Dies kann nicht rückgängig gemacht werden.',
        ja: '${widget.rows.length} 件のエントリを削除します。元に戻せません。',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandClearLabel(context),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final cleared = await widget.controller.clearDomStorage(
      origin: origin,
      isLocalStorage: widget.isLocalStorage,
    );
    if (cleared && mounted) await widget.onChanged();
  }

  Future<void> _exportJson() async {
    final map = <String, String>{for (final r in widget.rows) r.key: r.value};
    final encoded = prettyPrintJson(map);
    await copyWebReverseTextToClipboard(
      context: context,
      text: encoded,
      successBase: openHandLocalizedText(
        context,
        zh: '已复制 ${widget.rows.length} 条到剪贴板',
        zhHant: '已複製 ${widget.rows.length} 筆到剪貼簿',
        en: 'Copied ${widget.rows.length} entries to clipboard',
        fr: '${widget.rows.length} entrées copiées dans le presse-papiers',
        de: '${widget.rows.length} Einträge in die Zwischenablage kopiert',
        ja: '${widget.rows.length} 件をクリップボードにコピーしました',
      ),
      logTag: 'web_reverse_storage_panel',
      logAction: '复制导出内容',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rows = widget.rows;
    final originOk = widget.origin != null && widget.origin!.isNotEmpty;
    return Column(
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: !originOk ? null : _add,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(
                openHandLocalizedText(
                  context,
                  zh: '新增条目',
                  zhHant: '新增項目',
                  en: 'Add entry',
                  fr: 'Ajouter une entrée',
                  de: 'Eintrag hinzufügen',
                  ja: 'エントリを追加',
                ),
              ),
            ),
            kOpenHandHGap4,
            TextButton.icon(
              onPressed: rows.isEmpty ? null : _exportJson,
              icon: const Icon(Icons.copy_all_rounded, size: 16),
              label: Text(openHandExportJsonLabel(context)),
            ),
            kOpenHandHGap4,
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: cs.error),
              onPressed: rows.isEmpty || !originOk ? null : _clearAll,
              icon: const Icon(Icons.delete_sweep_rounded, size: 16),
              label: Text(_webReverseDashClearAllLabel(context)),
            ),
          ],
        ),
        Expanded(
          child: rows.isEmpty
              ? OpenHandInlineEmptyState(
                  message: _webReverseDashEmptyLabel(context),
                  dense: true,
                )
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: cs.outlineVariant),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 200,
                            child: SelectableText(
                              r.key,
                              style: const TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              r.value,
                              maxLines: 4,
                              style: const TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _wrEditLabel(context),
                            visualDensity: VisualDensity.compact,
                            iconSize: 16,
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () => _edit(r),
                            icon: const Icon(Icons.edit_rounded),
                          ),
                          kOpenHandHGap4,
                          IconButton(
                            tooltip: openHandDeleteLabel(context),
                            visualDensity: VisualDensity.compact,
                            iconSize: 16,
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () => _delete(r),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: cs.error,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<({String key, String value})?> _showStorageEditor(
  BuildContext context, {
  required String initialKey,
  required String initialValue,
}) async {
  final keyCtrl = TextEditingController(text: initialKey);
  final valueCtrl = TextEditingController(text: initialValue);
  try {
    return await showOpenHandFormDialog<({String key, String value})>(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '存储条目',
        zhHant: '儲存項目',
        en: 'Storage entry',
        fr: 'Entrée de stockage',
        de: 'Speichereintrag',
        ja: 'ストレージ項目',
      ),
      submitLabel: openHandSaveLabel(context),
      cancelLabel: openHandCancelLabel(context),
      maxWidth: 380,
      onSubmit: (_) => (key: keyCtrl.text.trim(), value: valueCtrl.text),
      contentBuilder: (_) => SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyCtrl,
              maxLength: WebReverseSessionController.maxStorageKeyChars,
              decoration: const InputDecoration(
                labelText: 'Key',
                counterText: '',
              ),
            ),
            kOpenHandGap10,
            TextField(
              controller: valueCtrl,
              maxLines: 6,
              minLines: 2,
              maxLength: WebReverseSessionController.maxStorageValueChars,
              decoration: const InputDecoration(
                labelText: 'Value',
                counterText: '',
              ),
            ),
          ],
        ),
      ),
    );
  } finally {
    keyCtrl.dispose();
    valueCtrl.dispose();
  }
}

// Application 子组件：IndexedDB / Cache Storage / Service Workers

class _IndexedDbTable extends StatefulWidget {
  const _IndexedDbTable({
    required this.controller,
    required this.names,
    required this.described,
    required this.onChanged,
  });

  final WebReverseSessionController controller;
  final List<String> names;
  final Map<String, ({int version, List<String> stores})> described;
  final Future<void> Function() onChanged;

  @override
  State<_IndexedDbTable> createState() => _IndexedDbTableState();
}

class _IndexedDbTableState extends State<_IndexedDbTable> {
  /// 当前展开的 (db, store)；null 表示未展开。
  ({String db, String store})? _selected;
  List<Map<String, Object?>> _entries = const [];
  bool _hasMore = false;
  bool _entriesCapped = false;
  int _skipCount = 0;
  bool _loading = false;

  Future<void> _expand(String db, String store) async {
    if (_loading) return;
    setState(() {
      _selected = (db: db, store: store);
      _entries = const [];
      _skipCount = 0;
      _hasMore = false;
      _entriesCapped = false;
      _loading = true;
    });
    final r = await widget.controller.readIndexedDbStore(
      dbName: db,
      storeName: store,
    );
    if (!mounted) return;
    setState(() {
      _entries = r?.entries ?? const [];
      _hasMore = r?.hasMore ?? false;
      _entriesCapped =
          _hasMore &&
          _entries.length >=
              WebReverseSessionController.maxIndexedDbRetainedEntries;
      if (_entriesCapped) _hasMore = false;
      _skipCount = WebReverseSessionController.defaultIndexedDbPageSize;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _selected == null) return;
    final remaining =
        WebReverseSessionController.maxIndexedDbRetainedEntries -
        _entries.length;
    if (remaining <= 0) {
      setState(() {
        _hasMore = false;
        _entriesCapped = true;
      });
      return;
    }
    setState(() => _loading = true);
    final requestPageSize =
        remaining < WebReverseSessionController.defaultIndexedDbPageSize
        ? remaining
        : WebReverseSessionController.defaultIndexedDbPageSize;
    final r = await widget.controller.readIndexedDbStore(
      dbName: _selected!.db,
      storeName: _selected!.store,
      skipCount: _skipCount,
      pageSize: requestPageSize,
    );
    if (!mounted) return;
    setState(() {
      final nextEntries = r?.entries ?? const <Map<String, Object?>>[];
      _entries = [..._entries, ...nextEntries.take(remaining)];
      final serverHasMore = r?.hasMore ?? false;
      _entriesCapped =
          serverHasMore &&
          (nextEntries.isEmpty ||
              _entries.length >=
                  WebReverseSessionController.maxIndexedDbRetainedEntries);
      _hasMore = serverHasMore && nextEntries.isNotEmpty && !_entriesCapped;
      _skipCount += requestPageSize;
      _loading = false;
    });
  }

  Future<bool> _confirmDestructiveAction({
    required String titleZh,
    required String titleEn,
    required String titleZhHant,
    required String titleFr,
    required String titleDe,
    required String titleJa,
    required String messageZh,
    required String messageEn,
    required String messageZhHant,
    required String messageFr,
    required String messageDe,
    required String messageJa,
    required String confirmZh,
    required String confirmEn,
    required String confirmZhHant,
    required String confirmFr,
    required String confirmDe,
    required String confirmJa,
  }) {
    return showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: titleZh,
        zhHant: titleZhHant,
        en: titleEn,
        fr: titleFr,
        de: titleDe,
        ja: titleJa,
      ),
      message: openHandLocalizedText(
        context,
        zh: messageZh,
        zhHant: messageZhHant,
        en: messageEn,
        fr: messageFr,
        de: messageDe,
        ja: messageJa,
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandLocalizedText(
        context,
        zh: confirmZh,
        zhHant: confirmZhHant,
        en: confirmEn,
        fr: confirmFr,
        de: confirmDe,
        ja: confirmJa,
      ),
      destructive: true,
    );
  }

  /// 删除整个数据库。弹二次确认。
  Future<void> _confirmDeleteDb(String dbName) async {
    final ok = await _confirmDestructiveAction(
      titleZh: '删除数据库',
      titleEn: 'Delete database',
      titleZhHant: '刪除資料庫',
      titleFr: 'Supprimer la base',
      titleDe: 'Datenbank löschen',
      titleJa: 'データベースを削除',
      messageZh: '确定删除数据库 “$dbName” 及其全部 store ？此操作不可撤销。',
      messageEn: 'Delete database “$dbName” and all stores? Irreversible.',
      messageZhHant: '確定刪除資料庫「$dbName」及其全部 store？此操作無法復原。',
      messageFr:
          'Supprimer la base “$dbName” et tous ses stores ? Action irréversible.',
      messageDe:
          'Datenbank “$dbName” und alle Stores löschen? Dies kann nicht rückgängig gemacht werden.',
      messageJa: 'データベース「$dbName」とすべての store を削除しますか？元に戻せません。',
      confirmZh: '删除',
      confirmEn: 'Delete',
      confirmZhHant: '刪除',
      confirmFr: 'Supprimer',
      confirmDe: 'Löschen',
      confirmJa: '削除',
    );
    if (!mounted || !ok) return;
    final success = await widget.controller.deleteIndexedDb(dbName);
    if (!mounted) return;
    if (success) {
      setState(() {
        if (_selected?.db == dbName) {
          _selected = null;
          _entries = const [];
          _hasMore = false;
          _skipCount = 0;
        }
      });
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已删除 $dbName',
          zhHant: '已刪除 $dbName',
          en: 'Deleted $dbName',
          fr: '$dbName supprimée',
          de: '$dbName gelöscht',
          ja: '$dbName を削除しました',
        ),
      );
      await widget.onChanged();
    } else {
      showOpenHandErrorSnack(
        context,
        _webReverseDashDeleteFailedLabel(context),
      );
    }
  }

  /// 清空当前选中 store 的全部记录。
  Future<void> _confirmClearStore() async {
    final selected = _selected;
    if (selected == null) return;
    final ok = await _confirmDestructiveAction(
      titleZh: '清空 Object Store',
      titleEn: 'Clear object store',
      titleZhHant: '清空 Object Store',
      titleFr: 'Vider l’object store',
      titleDe: 'Object Store leeren',
      titleJa: 'Object Store をクリア',
      messageZh: '确定清空 “${selected.db} / ${selected.store}” 的全部记录？',
      messageEn: 'Clear all records in “${selected.db} / ${selected.store}”?',
      messageZhHant: '確定清空「${selected.db} / ${selected.store}」的全部記錄？',
      messageFr:
          'Vider tous les enregistrements dans “${selected.db} / ${selected.store}” ?',
      messageDe:
          'Alle Datensätze in “${selected.db} / ${selected.store}” leeren?',
      messageJa: '「${selected.db} / ${selected.store}」の全レコードをクリアしますか？',
      confirmZh: '清空',
      confirmEn: 'Clear',
      confirmZhHant: '清空',
      confirmFr: 'Vider',
      confirmDe: 'Leeren',
      confirmJa: 'クリア',
    );
    if (!mounted || !ok) return;
    final success = await widget.controller.clearIndexedDbStore(
      dbName: selected.db,
      storeName: selected.store,
    );
    if (!mounted) return;
    if (success) {
      await _expand(selected.db, selected.store);
      if (mounted) {
        showOpenHandSuccessSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '已清空',
            zhHant: '已清空',
            en: 'Cleared',
            fr: 'Vidée',
            de: 'Geleert',
            ja: 'クリアしました',
          ),
        );
      }
    } else {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '清空失败',
          zhHant: '清空失敗',
          en: 'Clear failed',
          fr: 'Échec du vidage',
          de: 'Leeren fehlgeschlagen',
          ja: 'クリアに失敗しました',
        ),
      );
    }
  }

  /// 删除单条记录。CDP 传入原始 key 结构（RemoteObject 转 IndexedDB.Key）。
  Future<void> _confirmDeleteEntry(Map<String, Object?> entry) async {
    final selected = _selected;
    if (selected == null) return;
    final keyRaw = entry['key'];
    final keyParam = _remoteObjectToKey(keyRaw);
    if (keyParam == null) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '不支持的 key 类型',
          zhHant: '不支援的 key 類型',
          en: 'Unsupported key type',
          fr: 'Type de key non pris en charge',
          de: 'Nicht unterstützter key-Typ',
          ja: '未対応の key 型です',
        ),
      );
      return;
    }
    final keyDescription = _describeRemoteObject(keyRaw);
    final ok = await _confirmDestructiveAction(
      titleZh: '删除记录',
      titleEn: 'Delete record',
      titleZhHant: '刪除記錄',
      titleFr: 'Supprimer l’enregistrement',
      titleDe: 'Datensatz löschen',
      titleJa: 'レコードを削除',
      messageZh: '确定删除 key = $keyDescription ？',
      messageEn: 'Delete record with key = $keyDescription?',
      messageZhHant: '確定刪除 key = $keyDescription？',
      messageFr: 'Supprimer l’enregistrement avec key = $keyDescription ?',
      messageDe: 'Datensatz mit key = $keyDescription löschen?',
      messageJa: 'key = $keyDescription のレコードを削除しますか？',
      confirmZh: '删除',
      confirmEn: 'Delete',
      confirmZhHant: '刪除',
      confirmFr: 'Supprimer',
      confirmDe: 'Löschen',
      confirmJa: '削除',
    );
    if (!mounted || !ok) return;
    final success = await widget.controller.deleteIndexedDbEntry(
      dbName: selected.db,
      storeName: selected.store,
      key: keyParam,
    );
    if (!mounted) return;
    if (success) {
      await _expand(selected.db, selected.store);
      if (mounted) {
        showOpenHandSuccessSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '已删除',
            zhHant: '已刪除',
            en: 'Deleted',
            fr: 'Supprimé',
            de: 'Gelöscht',
            ja: '削除しました',
          ),
        );
      }
    } else {
      showOpenHandErrorSnack(
        context,
        _webReverseDashDeleteFailedLabel(context),
      );
    }
  }

  /// CDP RemoteObject -> IndexedDB.Key 请求参数。仅支持 string / number；
  /// date / array 类型返回 null（需要手工处理）。
  Map<String, Object?>? _remoteObjectToKey(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    final value = raw['value'];
    final desc = raw['description'];
    if (type == 'string') {
      final v = value ?? desc;
      if (v is String) return <String, Object?>{'type': 'string', 'string': v};
    }
    if (type == 'number') {
      final n = value is num ? value : num.tryParse('${value ?? desc ?? ''}');
      if (n != null) {
        return <String, Object?>{'type': 'number', 'number': n};
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (widget.names.isEmpty) {
      return OpenHandInlineEmptyState(
        message: _webReverseDashEmptyLabel(context),
        dense: true,
      );
    }
    final selected = _selected;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左：db / store 树
        SizedBox(
          width: 240,
          child: ListView.builder(
            itemCount: widget.names.length,
            itemBuilder: (_, i) {
              final name = widget.names[i];
              final info = widget.described[name];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.storage_rounded,
                            size: 16,
                            color: cs.primary,
                          ),
                          kOpenHandHGap6,
                          Expanded(
                            child: SelectableText(
                              name,
                              style: const TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (info != null)
                            Text(
                              'v${info.version}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          IconButton(
                            tooltip: openHandLocalizedText(
                              context,
                              zh: '删除数据库',
                              zhHant: '刪除資料庫',
                              en: 'Delete database',
                              fr: 'Supprimer la base',
                              de: 'Datenbank löschen',
                              ja: 'データベースを削除',
                            ),
                            iconSize: 14,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 26,
                              height: 26,
                            ),
                            onPressed: () => _confirmDeleteDb(name),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: cs.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (info != null)
                      for (final s in info.stores)
                        InkWell(
                          onTap: () => _expand(name, s),
                          borderRadius: kOpenHandBorderRadius6,
                          child: Container(
                            margin: const EdgeInsets.only(left: 22, top: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  selected != null &&
                                      selected.db == name &&
                                      selected.store == s
                                  ? cs.primaryContainer
                                  : Colors.transparent,
                              borderRadius: kOpenHandBorderRadius6,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.table_rows_rounded,
                                  size: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                                kOpenHandHGap6,
                                Expanded(
                                  child: Text(
                                    s,
                                    style: const TextStyle(
                                      fontFamily: kOpenHandMonospaceFontFamily,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              );
            },
          ),
        ),
        VerticalDivider(width: 1, color: cs.outlineVariant),
        // 右：store entries 表
        Expanded(
          child: selected == null
              ? OpenHandInlineEmptyState(
                  message: openHandLocalizedText(
                    context,
                    zh: '点击左侧 store 查看记录',
                    zhHant: '點選左側 store 查看記錄',
                    en: 'Select a store on the left to view records',
                    fr: 'Sélectionnez un store à gauche pour voir les enregistrements',
                    de: 'Wählen Sie links einen Store aus, um Datensätze anzuzeigen',
                    ja: '左側の store を選択してレコードを表示',
                  ),
                  dense: true,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${selected.db} / ${selected.store}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '${_entries.length}${_hasMore || _entriesCapped ? "+" : ""}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFamily: kOpenHandMonospaceFontFamily,
                            ),
                          ),
                          kOpenHandHGap8,
                          if (_hasMore)
                            TextButton.icon(
                              onPressed: _loading ? null : _loadMore,
                              icon: const Icon(
                                Icons.expand_more_rounded,
                                size: 16,
                              ),
                              label: Text(
                                openHandLocalizedText(
                                  context,
                                  zh: '加载更多',
                                  zhHant: '載入更多',
                                  en: 'Load more',
                                  fr: 'Charger plus',
                                  de: 'Mehr laden',
                                  ja: 'さらに読み込む',
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: openHandLocalizedText(
                              context,
                              zh: '清空当前 store',
                              zhHant: '清空目前 store',
                              en: 'Clear current store',
                              fr: 'Vider le store actuel',
                              de: 'Aktuellen Store leeren',
                              ja: '現在の store をクリア',
                            ),
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            onPressed: _loading ? null : _confirmClearStore,
                            icon: Icon(
                              Icons.delete_sweep_outlined,
                              color: cs.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _entries.isEmpty && !_loading
                          ? OpenHandInlineEmptyState(
                              message: _webReverseDashEmptyLabel(context),
                              dense: true,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              itemCount: _entries.length + (_loading ? 1 : 0),
                              separatorBuilder: (_, _) =>
                                  Divider(height: 1, color: cs.outlineVariant),
                              itemBuilder: (_, i) {
                                if (i >= _entries.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return _IndexedDbEntryRow(
                                  entry: _entries[i],
                                  onDelete: () =>
                                      _confirmDeleteEntry(_entries[i]),
                                );
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// IndexedDB.requestData 回来的单条记录视图。CDP 的 key/value 是嵌套 RemoteObject，
/// 直接 jsonEncode 即可读到 description 字段；展开/收起避免一行撑爆。
class _IndexedDbEntryRow extends StatefulWidget {
  const _IndexedDbEntryRow({required this.entry, required this.onDelete});
  final Map<String, Object?> entry;
  final VoidCallback onDelete;

  @override
  State<_IndexedDbEntryRow> createState() => _IndexedDbEntryRowState();
}

class _IndexedDbEntryRowState extends State<_IndexedDbEntryRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entry = widget.entry;
    final keyDesc = _describeRemoteObject(entry['key']);
    final valDesc = _describeRemoteObject(entry['value']);
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                kOpenHandHGap4,
                SizedBox(
                  width: 200,
                  child: Text(
                    keyDesc,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    valDesc,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '删除记录',
                    zhHant: '刪除記錄',
                    en: 'Delete record',
                    fr: 'Supprimer l’enregistrement',
                    de: 'Datensatz löschen',
                    ja: 'レコードを削除',
                  ),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: widget.onDelete,
                  icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 0, 0),
                child: SelectableText(
                  prettyPrintJson(entry),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// CDP RemoteObject -> 人可读字符串。被 _IndexedDbTable / _IndexedDbEntryRow 共用。
String _describeRemoteObject(Object? raw) {
  if (raw is! Map) return '${raw ?? ''}';
  final type = raw['type'];
  final desc = raw['description'];
  final value = raw['value'];
  if (desc is String && desc.isNotEmpty) return desc;
  if (value != null) return '$value';
  return '<$type>';
}

class _NameListPanel extends StatelessWidget {
  const _NameListPanel({required this.names});
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (names.isEmpty) {
      return OpenHandInlineEmptyState(
        message: _webReverseDashEmptyLabel(context),
        dense: true,
      );
    }
    return ListView.builder(
      itemCount: names.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.folder_zip_rounded, size: 16, color: cs.primary),
            kOpenHandHGap8,
            Expanded(
              child: SelectableText(
                names[i],
                style: const TextStyle(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceWorkersTable extends StatelessWidget {
  const _ServiceWorkersTable({
    required this.versions,
    required this.controller,
    required this.onChanged,
  });
  final List<Map<String, Object?>> versions;
  final WebReverseSessionController controller;
  final Future<void> Function() onChanged;

  Future<void> _registerNew(BuildContext context) async {
    final ok = await showOpenHandTextInputDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '注册 Service Worker',
        zhHant: '註冊 Service Worker',
        en: 'Register SW',
        fr: 'Enregistrer un SW',
        de: 'SW registrieren',
        ja: 'SW を登録',
      ),
      hintText: 'scopeURL',
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandLocalizedText(
        context,
        zh: '注册',
        zhHant: '註冊',
        en: 'Register',
        fr: 'Enregistrer',
        de: 'Registrieren',
        ja: '登録',
      ),
      decoration: const InputDecoration(labelText: 'scopeURL'),
    );
    if (ok == null || ok.isEmpty) return;
    await controller.registerServiceWorker(ok);
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _registerNew(context),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(
              openHandLocalizedText(
                context,
                zh: '注册新 SW',
                zhHant: '註冊新 SW',
                en: 'Register new SW',
                fr: 'Enregistrer un nouveau SW',
                de: 'Neuen SW registrieren',
                ja: '新しい SW を登録',
              ),
            ),
          ),
        ),
        Expanded(
          child: versions.isEmpty
              ? OpenHandInlineEmptyState(
                  message: _webReverseDashEmptyLabel(context),
                  dense: true,
                )
              : ListView.separated(
                  itemCount: versions.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: cs.outlineVariant),
                  itemBuilder: (_, i) {
                    final v = versions[i];
                    final status = '${v['runningStatus'] ?? v['status'] ?? ''}';
                    final url = '${v['scriptURL'] ?? ''}';
                    final scope = '${v['scopeURL'] ?? ''}';
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      status == 'running' ||
                                          status == 'activated'
                                      ? cs.primaryContainer
                                      : cs.surfaceContainerHigh,
                                  borderRadius: kOpenHandPillBorderRadius,
                                ),
                                child: Text(
                                  status.isEmpty ? '?' : status,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontFamily: kOpenHandMonospaceFontFamily,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              kOpenHandHGap8,
                              Expanded(
                                child: SelectableText(
                                  url,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontFamily: kOpenHandMonospaceFontFamily,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: openHandUpdateLabel(context),
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: scope.isEmpty
                                    ? null
                                    : () async {
                                        await controller.updateServiceWorker(
                                          scope,
                                        );
                                        await onChanged();
                                      },
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                              kOpenHandHGap4,
                              IconButton(
                                tooltip: openHandLocalizedText(
                                  context,
                                  zh: '卸载',
                                  zhHant: '解除註冊',
                                  en: 'Unregister',
                                  fr: 'Désenregistrer',
                                  de: 'Austragen',
                                  ja: '登録解除',
                                ),
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: scope.isEmpty
                                    ? null
                                    : () async {
                                        await controller
                                            .unregisterServiceWorker(scope);
                                        await onChanged();
                                      },
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: cs.error,
                                ),
                              ),
                            ],
                          ),
                          if (scope.isNotEmpty) ...[
                            kOpenHandGap4,
                            Text(
                              'scope: $scope',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontFamily: kOpenHandMonospaceFontFamily,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// Security：Security.securityStateChanged 实时

class _SecurityPanel extends StatefulWidget {
  const _SecurityPanel({required this.controller});
  final WebReverseSessionController controller;

  @override
  State<_SecurityPanel> createState() => _SecurityPanelState();
}

class _SecurityPanelState extends State<_SecurityPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.enableSecurity();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final state = widget.controller.securityState;
    final color = switch (state) {
      'secure' => Colors.green,
      'insecure' => cs.error,
      'neutral' => cs.outline,
      _ => cs.outline,
    };
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '当前安全状态：',
                  zhHant: '目前安全狀態：',
                  en: 'Current security state: ',
                  fr: 'État de sécurité actuel : ',
                  de: 'Aktueller Sicherheitsstatus: ',
                  ja: '現在のセキュリティ状態: ',
                ),
                style: theme.textTheme.titleSmall,
              ),
              Text(
                state ??
                    openHandLocalizedText(
                      context,
                      zh: '（尚未上报）',
                      zhHant: '（尚未回報）',
                      en: '(no data)',
                      fr: '(aucune donnée)',
                      de: '(keine Daten)',
                      ja: '（データなし）',
                    ),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: webReverseSurfaceCardDecoration(cs, radius: 12),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.controller.securityExplanationsJson ??
                      openHandLocalizedText(
                        context,
                        zh: '尚未收到 explanations。访问任意 https 页面后会自动刷新。',
                        zhHant: '尚未收到 explanations。造訪任一 https 頁面後會自動更新。',
                        en: 'No explanations yet. Visit any https page to populate.',
                        fr: 'Aucune explanation pour le moment. Ouvrez une page https pour remplir cette zone.',
                        de: 'Noch keine explanations. Öffnen Sie eine https-Seite, um sie zu laden.',
                        ja: 'explanations はまだありません。任意の https ページを開くと自動更新されます。',
                      ),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Recorder：注入轻量 init script 录制 click / input / hashchange / popstate

class _RecorderPanel extends StatefulWidget {
  const _RecorderPanel({required this.controller});

  final WebReverseSessionController controller;

  @override
  State<_RecorderPanel> createState() => _RecorderPanelState();
}

class _RecorderPanelState extends State<_RecorderPanel> {
  bool _replaying = false;

  // Recorder 不走 dashboard 的分类刷新分支；直接订阅 controller，保证 Stop
  // 和步数变化能即时反馈。
  late final VoidCallback _ctrlListener;

  @override
  void initState() {
    super.initState();
    _ctrlListener = () {
      if (!mounted) return;
      setState(() {});
    };
    widget.controller.addListener(_ctrlListener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_ctrlListener);
    super.dispose();
  }

  String _scriptExportHeader(String generatedAt) => openHandLocalizedText(
    context,
    zh: '由 OpenHand Web 逆向 Recorder 自动导出（$generatedAt）',
    zhHant: '由 OpenHand Web 逆向 Recorder 自動匯出（$generatedAt）',
    en: 'Generated by OpenHand Web Reverse Recorder ($generatedAt)',
    fr: 'Généré par OpenHand Web Reverse Recorder ($generatedAt)',
    de: 'Exportiert von OpenHand Web Reverse Recorder ($generatedAt)',
    ja: 'OpenHand Web Reverse Recorder により生成（$generatedAt）',
  );

  Future<void> _save() async {
    final steps = widget.controller.recorderSteps;
    if (steps.isEmpty) return;
    const typeGroup = XTypeGroup(label: 'JSON', extensions: <String>['json']);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'recorder-$ts.json',
        acceptedTypeGroups: const [typeGroup],
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '选择录制数据保存位置', error, stack);
    }
    if (location == null) return;
    try {
      await writeFileAtomically(File(location.path), prettyPrintJson(steps));
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        webReverseSavedToFileMessage(context, location.path),
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '写入录制数据', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        webReverseSaveFailedMessage(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  Future<void> _import() async {
    const typeGroup = XTypeGroup(label: 'JSON', extensions: <String>['json']);
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [typeGroup]);
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '打开录制数据文件', error, stack);
    }
    if (file == null) return;
    try {
      final read = await readWebReverseTextFile(
        file,
        maxBytes: WebReverseSessionController.maxRecorderImportBytes,
      );
      if (!mounted) return;
      if (read.isTooLarge) {
        showOpenHandErrorSnack(
          context,
          webReverseTextFileTooLargeMessage(
            read.tooLargeBytes!,
            context: context,
            maxBytes: WebReverseSessionController.maxRecorderImportBytes,
          ),
          duration: kOpenHandSnackBarBriefDuration,
        );
        return;
      }
      final raw = read.text!;
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('结果不是列表。');
      final steps = stringKeyedMapListFromValue(decoded);
      widget.controller.setRecorderSteps(steps);
      if (!mounted) return;
      final importedCount = widget.controller.recorderSteps.length;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已导入 $importedCount 步',
          zhHant: '已匯入 $importedCount 步',
          en: 'Imported $importedCount steps',
          fr: '$importedCount étapes importées',
          de: '$importedCount Schritte importiert',
          ja: '$importedCount ステップをインポートしました',
        ),
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '解析录制数据 JSON', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '导入失败：JSON 格式不合法',
          zhHant: '匯入失敗：JSON 格式不合法',
          en: 'Import failed: invalid JSON',
          fr: 'Échec de l’import : JSON invalide',
          de: 'Import fehlgeschlagen: ungültiges JSON',
          ja: 'インポートに失敗しました: JSON 形式が不正です',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  Future<void> _replay() async {
    setState(() => _replaying = true);
    final result = await widget.controller.replaySteps();
    if (!mounted) return;
    setState(() => _replaying = false);
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '重放完成：${result.executed} 步成功，${result.failed} 步失败',
        zhHant: '重放完成：${result.executed} 步成功，${result.failed} 步失敗',
        en: 'Replay done: ${result.executed} ok, ${result.failed} failed',
        fr: 'Relecture terminée : ${result.executed} réussies, ${result.failed} échouées',
        de: 'Replay abgeschlossen: ${result.executed} erfolgreich, ${result.failed} fehlgeschlagen',
        ja: 'リプレイ完了: ${result.executed} 件成功、${result.failed} 件失敗',
      ),
    );
  }

  /// 把 recorder steps 翻译成 puppeteer / playwright 的 JS 脚本并落盘。
  /// 翻译规则：navigate → page.goto；click → page.click；input → page.type；
  /// change → page.select / page.click 取决于 value 类型；assertText → 等价
  /// 选择器读 textContent 后断言；assertVisible → 等待选择器可见。
  Future<void> _exportAsCode(String kind) async {
    final steps = widget.controller.recorderSteps;
    if (steps.isEmpty) return;
    final code = kind == 'puppeteer'
        ? _renderPuppeteerScript(steps)
        : _renderPlaywrightScript(steps);
    const typeGroup = XTypeGroup(label: 'JS', extensions: <String>['js']);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'recorder-$kind-$ts.js',
        acceptedTypeGroups: const [typeGroup],
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '选择录制代码导出位置', error, stack);
    }
    if (!mounted || location == null) return;
    try {
      await writeFileAtomically(File(location.path), code);
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        webReverseSavedToFileMessage(context, location.path),
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '导出 $kind 代码', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        webReverseSaveFailedMessage(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  String _renderPuppeteerScript(List<Map<String, Object?>> steps) {
    final generatedAt = DateTime.now().toIso8601String();
    final buf = StringBuffer()
      ..writeln('// ${_scriptExportHeader(generatedAt)}')
      ..writeln("const puppeteer = require('puppeteer');")
      ..writeln('(async () => {')
      ..writeln('  const browser = await puppeteer.launch({headless: false});')
      ..writeln('  const page = await browser.newPage();');
    for (final s in steps) {
      _emitStep(buf, s, framework: 'puppeteer');
    }
    buf
      ..writeln('  await browser.close();')
      ..writeln('})();');
    return buf.toString();
  }

  String _renderPlaywrightScript(List<Map<String, Object?>> steps) {
    final generatedAt = DateTime.now().toIso8601String();
    final buf = StringBuffer()
      ..writeln('// ${_scriptExportHeader(generatedAt)}')
      ..writeln("const {chromium} = require('playwright');")
      ..writeln('(async () => {')
      ..writeln('  const browser = await chromium.launch({headless: false});')
      ..writeln('  const context = await browser.newContext();')
      ..writeln('  const page = await context.newPage();');
    for (final s in steps) {
      _emitStep(buf, s, framework: 'playwright');
    }
    buf
      ..writeln('  await browser.close();')
      ..writeln('})();');
    return buf.toString();
  }

  void _emitStep(
    StringBuffer buf,
    Map<String, Object?> s, {
    required String framework,
  }) {
    final type = '${s['type'] ?? ''}';
    final selector = s['selector'] is String ? s['selector'] as String : '';
    final value = s['value'];
    final url = '${s['url'] ?? ''}';
    final expected = '${s['expected'] ?? ''}';
    String esc(String t) => t.replaceAll('\\', r'\\').replaceAll("'", r"\'");
    switch (type) {
      case 'navigate':
        if (url.isNotEmpty) {
          buf.writeln("  await page.goto('${esc(url)}');");
        }
      case 'click':
        if (selector.isNotEmpty) {
          if (s['doubleClick'] == true) {
            buf.writeln(
              "  await page.click('${esc(selector)}', {clickCount: 2});",
            );
          } else {
            buf.writeln("  await page.click('${esc(selector)}');");
          }
        }
      case 'input':
        if (selector.isNotEmpty && value is String) {
          if (framework == 'puppeteer') {
            buf
              ..writeln(
                "  await page.click('${esc(selector)}', {clickCount: 3});",
              )
              ..writeln(
                "  await page.type('${esc(selector)}', '${esc(value)}');",
              );
          } else {
            buf.writeln(
              "  await page.fill('${esc(selector)}', '${esc(value)}');",
            );
          }
        }
      case 'change':
        if (selector.isEmpty) break;
        if (value is String) {
          if (framework == 'puppeteer') {
            buf.writeln(
              "  await page.select('${esc(selector)}', '${esc(value)}');",
            );
          } else {
            buf.writeln(
              "  await page.selectOption('${esc(selector)}', '${esc(value)}');",
            );
          }
        } else if (value is bool) {
          if (value) {
            buf.writeln("  await page.click('${esc(selector)}');");
          }
        }
      case 'assertText':
        if (selector.isNotEmpty) {
          if (framework == 'puppeteer') {
            buf.writeln(
              "  await page.waitForFunction((sel, expected) => document.querySelector(sel) && document.querySelector(sel).textContent.includes(expected), {}, '${esc(selector)}', '${esc(expected)}');",
            );
          } else {
            buf.writeln(
              "  await expect(page.locator('${esc(selector)}')).toContainText('${esc(expected)}');",
            );
          }
        }
      case 'assertVisible':
        if (selector.isNotEmpty) {
          if (framework == 'puppeteer') {
            buf.writeln(
              "  await page.waitForSelector('${esc(selector)}', {visible: true});",
            );
          } else {
            buf.writeln(
              "  await expect(page.locator('${esc(selector)}')).toBeVisible();",
            );
          }
        }
    }
  }

  Future<void> _addAssertion(String kind) async {
    final selectorCtrl = TextEditingController();
    final expectedCtrl = TextEditingController();
    try {
      final result = await showOpenHandFormDialog<bool>(
        context: context,
        title: kind == 'assertText'
            ? openHandLocalizedText(
                context,
                zh: '断言：元素文本包含',
                zhHant: '斷言：元素文字包含',
                en: 'Assert: element text contains',
                fr: 'Assertion : le texte contient',
                de: 'Assert: Elementtext enthält',
                ja: 'アサート: 要素テキストを含む',
              )
            : openHandLocalizedText(
                context,
                zh: '断言：元素可见',
                zhHant: '斷言：元素可見',
                en: 'Assert: element visible',
                fr: 'Assertion : élément visible',
                de: 'Assert: Element sichtbar',
                ja: 'アサート: 要素が表示される',
              ),
        submitLabel: openHandAddLabel(context),
        cancelLabel: openHandCancelLabel(context),
        maxWidth: 420,
        onSubmit: (_) => true,
        contentBuilder: (_) => SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: selectorCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: 'CSS 选择器',
                    zhHant: 'CSS 選擇器',
                    en: 'CSS Selector',
                    fr: 'Sélecteur CSS',
                    de: 'CSS-Selektor',
                    ja: 'CSS セレクター',
                  ),
                  hintText: '#login-btn / .header > h1',
                ),
              ),
              if (kind == 'assertText') ...[
                kOpenHandGap12,
                TextField(
                  controller: expectedCtrl,
                  decoration: InputDecoration(
                    labelText: openHandLocalizedText(
                      context,
                      zh: '期望包含的文本',
                      zhHant: '預期包含的文字',
                      en: 'Expected text',
                      fr: 'Texte attendu',
                      de: 'Erwarteter Text',
                      ja: '期待するテキスト',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      if (!mounted || result != true) return;
      final selector = selectorCtrl.text.trim();
      if (selector.isEmpty) return;
      widget.controller.addAssertionStep(
        kind,
        selector: selector,
        expected: kind == 'assertText' ? expectedCtrl.text : null,
      );
    } finally {
      selectorCtrl.dispose();
      expectedCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ctrl = widget.controller;
    final steps = ctrl.recorderSteps;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: ctrl.isRecording
                    ? () => ctrl.stopRecording()
                    : () => ctrl.startRecording(),
                icon: Icon(
                  ctrl.isRecording
                      ? Icons.stop_rounded
                      : Icons.fiber_manual_record_rounded,
                  size: 18,
                  color: ctrl.isRecording ? null : Colors.red,
                ),
                label: Text(
                  ctrl.isRecording
                      ? openHandLocalizedText(
                          context,
                          zh: '停止录制',
                          zhHant: '停止錄製',
                          en: 'Stop recording',
                          fr: 'Arrêter',
                          de: 'Aufnahme stoppen',
                          ja: '録画を停止',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '开始录制',
                          zhHant: '開始錄製',
                          en: 'Record',
                          fr: 'Enregistrer',
                          de: 'Aufnehmen',
                          ja: '録画開始',
                        ),
                ),
              ),
              kOpenHandHGap8,
              OutlinedButton.icon(
                onPressed: (steps.isEmpty || ctrl.isRecording || _replaying)
                    ? null
                    : _replay,
                icon: Icon(
                  _replaying
                      ? Icons.hourglass_top_rounded
                      : Icons.play_circle_rounded,
                  size: 18,
                ),
                label: Text(
                  _replaying
                      ? openHandLocalizedText(
                          context,
                          zh: '重放中…',
                          zhHant: '重放中…',
                          en: 'Replaying…',
                          fr: 'Relecture…',
                          de: 'Replay läuft…',
                          ja: 'リプレイ中…',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '重放',
                          zhHant: '重放',
                          en: 'Replay',
                          fr: 'Relire',
                          de: 'Replay',
                          ja: 'リプレイ',
                        ),
                ),
              ),
              kOpenHandHGap8,
              OutlinedButton.icon(
                onPressed: steps.isEmpty ? null : _save,
                icon: const Icon(Icons.save_alt_rounded, size: 18),
                label: Text(openHandExportJsonLabel(context)),
              ),
              kOpenHandHGap8,
              AnimatedPopupMenuButton<String>(
                tooltip: openHandLocalizedText(
                  context,
                  zh: '导出为代码',
                  zhHant: '匯出為程式碼',
                  en: 'Export as code',
                  fr: 'Exporter en code',
                  de: 'Als Code exportieren',
                  ja: 'コードとしてエクスポート',
                ),
                onSelected: (k) => _exportAsCode(k),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'puppeteer',
                    enabled: steps.isNotEmpty,
                    child: const Text('Puppeteer (.js)'),
                  ),
                  PopupMenuItem(
                    value: 'playwright',
                    enabled: steps.isNotEmpty,
                    child: const Text('Playwright (.js)'),
                  ),
                ],
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.code_rounded, size: 18),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '导出为代码',
                      zhHant: '匯出為程式碼',
                      en: 'Export code',
                      fr: 'Exporter code',
                      de: 'Code exportieren',
                      ja: 'コードをエクスポート',
                    ),
                  ),
                ),
              ),
              kOpenHandHGap8,
              OutlinedButton.icon(
                onPressed: ctrl.isRecording ? null : _import,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '导入 JSON',
                    zhHant: '匯入 JSON',
                    en: 'Import JSON',
                    fr: 'Importer JSON',
                    de: 'JSON importieren',
                    ja: 'JSON をインポート',
                  ),
                ),
              ),
              kOpenHandHGap8,
              AnimatedPopupMenuButton<String>(
                tooltip: openHandLocalizedText(
                  context,
                  zh: '添加断言',
                  zhHant: '新增斷言',
                  en: 'Add assertion',
                  fr: 'Ajouter une assertion',
                  de: 'Assertion hinzufügen',
                  ja: 'アサートを追加',
                ),
                onSelected: (kind) => _addAssertion(kind),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'assertText',
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: '断言文本（assertText）',
                        zhHant: '斷言文字（assertText）',
                        en: 'Text assertion (assertText)',
                        fr: 'Assertion texte (assertText)',
                        de: 'Text-Assertion (assertText)',
                        ja: 'テキストアサート（assertText）',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'assertVisible',
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: '断言可见（assertVisible）',
                        zhHant: '斷言可見（assertVisible）',
                        en: 'Visible assertion (assertVisible)',
                        fr: 'Assertion visible (assertVisible)',
                        de: 'Sichtbarkeits-Assertion (assertVisible)',
                        ja: '表示アサート（assertVisible）',
                      ),
                    ),
                  ),
                ],
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.rule_rounded, size: 18),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '添加断言',
                      zhHant: '新增斷言',
                      en: 'Add assertion',
                      fr: 'Ajouter assertion',
                      de: 'Assertion hinzufügen',
                      ja: 'アサートを追加',
                    ),
                  ),
                ),
              ),
              kOpenHandHGap8,
              IconButton(
                tooltip: openHandClearLabel(context),
                onPressed: (steps.isEmpty || ctrl.isRecording)
                    ? null
                    : ctrl.clearRecorderSteps,
                icon: const Icon(Icons.cleaning_services_rounded, size: 18),
              ),
              const Spacer(),
              Text(
                openHandLocalizedText(
                  context,
                  zh: '${steps.length} 步',
                  zhHant: '${steps.length} 步',
                  en: '${steps.length} steps',
                  fr: '${steps.length} étapes',
                  de: '${steps.length} Schritte',
                  ja: '${steps.length} ステップ',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          Expanded(
            child: steps.isEmpty
                ? Center(
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: '点击「开始录制」后在浏览器中操作页面，事件会按时间序记录。',
                        zhHant: '點選「開始錄製」後在瀏覽器中操作頁面，事件會依時間記錄。',
                        en: 'Click Record, then interact with the browser; events are logged here.',
                        fr: 'Cliquez sur Enregistrer, puis utilisez le navigateur ; les événements apparaissent ici.',
                        de: 'Klicken Sie auf Aufnehmen und bedienen Sie den Browser; Ereignisse erscheinen hier.',
                        ja: '「録画開始」を押してブラウザーを操作すると、イベントがここに記録されます。',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: steps.length,
                    itemBuilder: (_, idx) {
                      final s = steps[idx];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh,
                            borderRadius: kOpenHandBorderRadius8,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '#${idx + 1}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontFamily: kOpenHandMonospaceFontFamily,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 88,
                                child: Text(
                                  '${s['type'] ?? ''}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontFamily: kOpenHandMonospaceFontFamily,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  jsonEncode(s),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: kOpenHandMonospaceFontFamily,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 快照比较弹窗里的一行：左标签 / 中 A→B 数值 / 右 delta（带正负号）。
class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.label,
    required this.a,
    required this.b,
    required this.delta,
  });

  final String label;
  final String a;
  final String b;
  final num delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final positive = delta > 0;
    final color = delta == 0
        ? cs.onSurfaceVariant
        : (positive ? cs.error : Colors.green);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$a  →  $b',
              style: const TextStyle(fontFamily: kOpenHandMonospaceFontFamily),
            ),
          ),
          Text(
            (delta == 0 ? '0' : (positive ? '+$delta' : '$delta')),
            style: TextStyle(
              fontFamily: kOpenHandMonospaceFontFamily,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 把 Tracing.dataCollected JSON 转成简化火焰图的弹窗。
///
/// 横轴展示时间标尺；点击事件可查看详情，右侧按耗时列出高开销事件。
class _FlameGraphDialog extends StatefulWidget {
  const _FlameGraphDialog({required this.traceJson});

  final String traceJson;

  @override
  State<_FlameGraphDialog> createState() => _FlameGraphDialogState();
}

class _FlameGraphDialogState extends State<_FlameGraphDialog> {
  late final List<_FlameEvent> _events;
  late final int _minTs;
  late final int _maxTs;
  // 命中高亮：点击 top-list 后写入，painter 把对应索引画亮，1 秒后消逝。
  int? _hitIndex;
  Timer? _hitTimer;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void dispose() {
    _hitTimer?.cancel();
    super.dispose();
  }

  void _parse() {
    var minT = 1 << 62;
    var maxT = -1;
    final all = <_FlameEvent>[];
    try {
      final decoded = decodeStringKeyedJsonMap(widget.traceJson);
      if (decoded == null) {
        throw const FormatException('跟踪数据 JSON 必须是对象。');
      }
      final raw = decoded['traceEvents'];
      final list = raw is List ? raw : const <Object?>[];
      for (final item in list.whereType<Map>()) {
        if (item['ph'] != 'X') continue;
        final ts = optionalIntFromValue(item['ts']);
        final dur = optionalIntFromValue(item['dur']);
        if (ts == null || dur == null || dur <= 0) continue;
        all.add(
          _FlameEvent(
            tid: '${item['tid'] ?? '0'}',
            name: '${item['name'] ?? ''}',
            ts: ts,
            dur: dur,
            cat: '${item['cat'] ?? ''}',
            pid: '${item['pid'] ?? ''}',
            args: stringKeyedMapFromValue(item['args']),
          ),
        );
        if (ts < minT) minT = ts;
        if (ts + dur > maxT) maxT = ts + dur;
      }
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '解析性能轨迹事件', error, stack);
    }
    if (all.length > 3000) {
      final step = (all.length / 3000).ceil();
      _events = [for (var i = 0; i < all.length; i += step) all[i]];
    } else {
      _events = all;
    }
    _minTs = minT == (1 << 62) ? 0 : minT;
    _maxTs = maxT < 0 ? 0 : maxT;
  }

  void _highlightFromTopList(int idx) {
    _hitTimer?.cancel();
    setState(() => _hitIndex = idx);
    _hitTimer = startSafeTimer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _hitIndex = null);
    });
  }

  void _showEventDetail(_FlameEvent e) {
    showOpenHandInfoDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '事件详情',
        zhHant: '事件詳情',
        en: 'Event detail',
        fr: 'Détail de l’événement',
        de: 'Ereignisdetails',
        ja: 'イベント詳細',
      ),
      closeLabel: openHandCloseLabel(context),
      content: SizedBox(
        width: 560,
        child: SelectableText(
          'name: ${e.name}\n'
          'cat: ${e.cat}\n'
          'pid: ${e.pid} · tid: ${e.tid}\n'
          'ts: ${e.ts} (μs)\n'
          'dur: ${e.dur} μs (${(e.dur / 1000).toStringAsFixed(2)} ms)\n'
          '\nargs:\n${prettyPrintJson(e.args)}',
          style: const TextStyle(
            fontFamily: kOpenHandMonospaceFontFamily,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 计算 Top dur 30：按 dur 降序，给原索引一并保留（用于火焰图高亮）。
    final indexed = <(int, _FlameEvent)>[
      for (var i = 0; i < _events.length; i++) (i, _events[i]),
    ]..sort((a, b) => b.$2.dur.compareTo(a.$2.dur));
    final top = indexed.take(30).toList();
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthFull,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.local_fire_department_rounded,
            title: openHandLocalizedText(
              context,
              zh: '火焰图（${_events.length} 事件 · ${((_maxTs - _minTs) / 1000).toStringAsFixed(2)} ms）',
              zhHant:
                  '火焰圖（${_events.length} 事件 · ${((_maxTs - _minTs) / 1000).toStringAsFixed(2)} ms）',
              en: 'Flame graph (${_events.length} events · ${((_maxTs - _minTs) / 1000).toStringAsFixed(2)} ms)',
              fr: 'Flame graph (${_events.length} événements · ${((_maxTs - _minTs) / 1000).toStringAsFixed(2)} ms)',
              de: 'Flamegraph (${_events.length} Ereignisse · ${((_maxTs - _minTs) / 1000).toStringAsFixed(2)} ms)',
              ja: 'フレームグラフ（${_events.length} イベント · ${((_maxTs - _minTs) / 1000).toStringAsFixed(2)} ms）',
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: _events.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: '没有可视化的完整事件（trace 内可能只含 metadata）。',
                        zhHant: '沒有可視化的完整事件（trace 內可能只含 metadata）。',
                        en: 'No X-phase events to plot.',
                        fr: 'Aucun événement X-phase à afficher.',
                        de: 'Keine X-Phase-Ereignisse zum Anzeigen.',
                        ja: '描画できる X-phase イベントがありません。',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 火焰图主体 + 时间轴。
                      Expanded(
                        flex: 4,
                        child: InteractiveViewer(
                          maxScale: 8,
                          minScale: 0.5,
                          child: SizedBox(
                            width: 1600,
                            height: 540,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) {
                                final hit = _hitTest(
                                  d.localPosition,
                                  const Size(1600, 540),
                                );
                                if (hit != null) _showEventDetail(hit);
                              },
                              child: CustomPaint(
                                painter: _FlamePainter(
                                  events: _events,
                                  minTs: _minTs,
                                  maxTs: _maxTs,
                                  primary: cs.primary,
                                  tertiary: cs.tertiary,
                                  onSurface: cs.onSurface,
                                  grid: cs.outlineVariant,
                                  hitIndex: _hitIndex,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      // 右侧 Top dur 列表。
                      SizedBox(
                        width: 280,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 12, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                openHandLocalizedText(
                                  context,
                                  zh: '按耗时排序 Top 30',
                                  zhHant: '依耗時排序 Top 30',
                                  en: 'Top 30 by duration',
                                  fr: 'Top 30 par durée',
                                  de: 'Top 30 nach Dauer',
                                  ja: '所要時間順 Top 30',
                                ),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              kOpenHandGap6,
                              Expanded(
                                child: ListView.builder(
                                  itemCount: top.length,
                                  itemBuilder: (_, i) {
                                    final (idx, e) = top[i];
                                    final ms = e.dur / 1000;
                                    return InkWell(
                                      onTap: () => _highlightFromTopList(idx),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 4,
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 60,
                                              child: Text(
                                                '${ms.toStringAsFixed(2)}ms',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      fontFamily:
                                                          kOpenHandMonospaceFontFamily,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: ms > 50
                                                          ? cs.error
                                                          : cs.primary,
                                                    ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                e.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      fontFamily:
                                                          kOpenHandMonospaceFontFamily,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 火焰图点击命中：把 (localPosition, canvas size) 反推回事件索引。
  /// painter 在 paint 时按 (e.ts - minTs)/span * w 算 x，按 tid 索引算 y。
  _FlameEvent? _hitTest(Offset local, Size size) {
    if (_events.isEmpty) return null;
    final span = (_maxTs - _minTs).toDouble().clamp(1, double.infinity);
    final tidIndex = <String, int>{};
    for (final e in _events) {
      tidIndex.putIfAbsent(e.tid, () => tidIndex.length);
    }
    final canvasH = size.height - _FlamePainter.kAxisH;
    final rowH = canvasH / tidIndex.length.clamp(1, 999);
    for (final e in _events) {
      final x = (e.ts - _minTs) / span * size.width;
      final w = (e.dur / span * size.width).clamp(1, size.width).toDouble();
      final y = (tidIndex[e.tid] ?? 0) * rowH;
      final h = (rowH - 2).clamp(2.0, double.infinity);
      if (local.dx >= x &&
          local.dx <= x + w &&
          local.dy >= y &&
          local.dy <= y + h) {
        return e;
      }
    }
    return null;
  }
}

class _FlameEvent {
  const _FlameEvent({
    required this.tid,
    required this.name,
    required this.ts,
    required this.dur,
    this.cat = '',
    this.pid = '',
    this.args = const <String, Object?>{},
  });

  final String tid;
  final String name;
  final int ts;
  final int dur;
  final String cat;
  final String pid;
  final Map<String, Object?> args;
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({
    required this.events,
    required this.minTs,
    required this.maxTs,
    required this.primary,
    required this.tertiary,
    required this.onSurface,
    required this.grid,
    this.hitIndex,
  });

  /// 时间轴高度（底部留给刻度文字 + 网格线）。_FlameGraphDialogState
  /// 在 hitTest 时减去这个高度，确保点到底部刻度区不会误命中事件。
  static const double kAxisH = 22;

  final List<_FlameEvent> events;
  final int minTs;
  final int maxTs;
  final Color primary;
  final Color tertiary;
  final Color onSurface;
  final Color grid;
  final int? hitIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (events.isEmpty) return;
    final span = (maxTs - minTs).toDouble().clamp(1, double.infinity);
    final tidIndex = <String, int>{};
    for (final e in events) {
      tidIndex.putIfAbsent(e.tid, () => tidIndex.length);
    }
    final canvasH = size.height - kAxisH;
    final rowH = canvasH / tidIndex.length.clamp(1, 999);
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      final x = (e.ts - minTs) / span * size.width;
      final w = (e.dur / span * size.width).clamp(1, size.width).toDouble();
      final y = (tidIndex[e.tid] ?? 0) * rowH;
      final h = (rowH - 2).clamp(2.0, double.infinity);
      // 颜色按 dur 长短分级：>50ms 用 tertiary（红橙），其它用 primary。
      // hitIndex 命中时改用满色 + 描边高亮。
      final isHit = hitIndex == i;
      final baseColor = e.dur > 50000
          ? tertiary
          : primary.withValues(alpha: 0.55);
      final color = isHit ? primary : baseColor;
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = color);
      if (isHit) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, w, h),
          Paint()
            ..color = onSurface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
      if (w > 40) {
        final tp = TextPainter(
          text: TextSpan(
            text: e.name,
            style: TextStyle(
              color: onSurface,
              fontSize: 10,
              fontFamily: kOpenHandMonospaceFontFamily,
            ),
          ),
          maxLines: 1,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: w - 4);
        tp.paint(canvas, Offset(x + 2, y + 1));
      }
    }
    // ── 时间轴：顶上一条灰色基线 + 5 等分刻度，下方贴 ms 数值。
    final axisY = canvasH;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, axisY), Offset(size.width, axisY), gridPaint);
    for (var k = 0; k <= 5; k++) {
      final x = size.width * k / 5;
      canvas.drawLine(Offset(x, axisY), Offset(x, axisY + 4), gridPaint);
      final ms = (span * k / 5) / 1000;
      final tp = TextPainter(
        text: TextSpan(
          text: '${ms.toStringAsFixed(2)} ms',
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.7),
            fontSize: 9,
            fontFamily: kOpenHandMonospaceFontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var labelX = x - tp.width / 2;
      if (labelX < 0) labelX = 0;
      if (labelX + tp.width > size.width) labelX = size.width - tp.width;
      tp.paint(canvas, Offset(labelX, axisY + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _FlamePainter old) =>
      old.events != events ||
      old.minTs != minTs ||
      old.maxTs != maxTs ||
      old.hitIndex != hitIndex;
}

/// .heapsnapshot 解析结果：按 (typeName, constructorName) 聚合的两份对象
/// 列表 + 排好序的 top growth。所有数值都是有限可序列化的纯类型，能跨
/// isolate 安全传输。
class _HeapDiffResult {
  const _HeapDiffResult({
    required this.nodesA,
    required this.nodesB,
    required this.totalSelfA,
    required this.totalSelfB,
    required this.growth,
    required this.error,
  });

  final int nodesA;
  final int nodesB;
  final int totalSelfA;
  final int totalSelfB;
  final List<_HeapGrowthEntry> growth;
  final String? error;
}

class _HeapGrowthEntry {
  const _HeapGrowthEntry({
    required this.label,
    required this.bytesDelta,
    required this.countDelta,
    required this.bytesA,
    required this.bytesB,
    required this.countA,
    required this.countB,
  });

  final String label;
  final int bytesDelta;
  final int countDelta;
  final int bytesA;
  final int bytesB;
  final int countA;
  final int countB;
}

/// 在 isolate 里跑：把两份 heapsnapshot JSON 解析成「constructor →
/// (字节累计, 节点数)」聚合表，然后做 delta 排序。失败时返回 error。
_HeapDiffResult _heapDiffWorker(Map<String, String> input) {
  try {
    final aggA = _aggregateHeap(input['a']!);
    final aggB = _aggregateHeap(input['b']!);
    final all = <String>{...aggA.byCtor.keys, ...aggB.byCtor.keys};
    final list = <_HeapGrowthEntry>[];
    for (final k in all) {
      final ea = aggA.byCtor[k];
      final eb = aggB.byCtor[k];
      final bytesA = ea?.bytes ?? 0;
      final bytesB = eb?.bytes ?? 0;
      final countA = ea?.count ?? 0;
      final countB = eb?.count ?? 0;
      list.add(
        _HeapGrowthEntry(
          label: k,
          bytesDelta: bytesB - bytesA,
          countDelta: countB - countA,
          bytesA: bytesA,
          bytesB: bytesB,
          countA: countA,
          countB: countB,
        ),
      );
    }
    list.sort((x, y) => y.bytesDelta.compareTo(x.bytesDelta));
    final top = list.take(40).toList(growable: false);
    return _HeapDiffResult(
      nodesA: aggA.nodeCount,
      nodesB: aggB.nodeCount,
      totalSelfA: aggA.totalSelf,
      totalSelfB: aggB.totalSelf,
      growth: top,
      error: null,
    );
  } catch (e) {
    return _HeapDiffResult(
      nodesA: 0,
      nodesB: 0,
      totalSelfA: 0,
      totalSelfB: 0,
      growth: const [],
      error: '$e',
    );
  }
}

class _HeapAggResult {
  _HeapAggResult({
    required this.byCtor,
    required this.nodeCount,
    required this.totalSelf,
  });

  final Map<String, ({int bytes, int count})> byCtor;
  final int nodeCount;
  final int totalSelf;
}

List<String> _heapStringList(Object? value, List<String> fallback) {
  final parsed = stringListFromValue(value);
  return parsed.isEmpty ? fallback : parsed;
}

List<String> _heapFirstStringList(Object? value, List<String> fallback) {
  if (value is! List || value.isEmpty) return fallback;
  return _heapStringList(value.first, fallback);
}

int _heapIntAt(List<Object?> values, int index, {int fallback = 0}) {
  if (index < 0 || index >= values.length) return fallback;
  return intFromValue(values[index], fallback: fallback);
}

/// 解析 .heapsnapshot 头：
/// snapshot.meta.node_fields 给出每节点字段顺序，含 type/name/self_size 等；
/// snapshot.meta.node_types[0] 为 type 名称表（如 hidden/object/string）；
/// nodes 是扁平 int 数组，长度 = node_count * fields.length；
/// strings 是字符串表，name 字段是其下标。
/// 我们按 type==object 时 ctor=strings\[name]，其他类型用 `<type>` 字面聚合。
_HeapAggResult _aggregateHeap(String src) {
  final m = decodeStringKeyedJsonMap(src);
  if (m == null) {
    throw const FormatException('堆快照 JSON 必须是对象。');
  }
  final snapshot = stringKeyedMapFromValue(m['snapshot']);
  final meta = stringKeyedMapFromValue(snapshot['meta']);
  final fields = _heapStringList(meta['node_fields'], const [
    'type',
    'name',
    'id',
    'self_size',
    'edge_count',
  ]);
  final fLen = fields.length;
  final iType = fields.indexOf('type');
  final iName = fields.indexOf('name');
  final iSelf = fields.indexOf('self_size');
  final typeNames = _heapFirstStringList(meta['node_types'], const ['object']);
  final strings = stringListFromValue(m['strings']);
  final nodes = m['nodes'] is List
      ? List<Object?>.of(m['nodes'] as List, growable: false)
      : const <Object?>[];
  final byCtor = <String, ({int bytes, int count})>{};
  var totalSelf = 0;
  if (fLen <= 0 || iType < 0) {
    return _HeapAggResult(byCtor: byCtor, nodeCount: 0, totalSelf: totalSelf);
  }
  // nodes 内可能是 int / num / string，统一用共享解析兜底。
  for (var i = 0; i + fLen <= nodes.length; i += fLen) {
    final type = _heapIntAt(nodes, i + iType);
    final nameIdx = iName >= 0 ? _heapIntAt(nodes, i + iName) : 0;
    final self = iSelf >= 0 ? _heapIntAt(nodes, i + iSelf) : 0;
    final typeName = (type >= 0 && type < typeNames.length)
        ? typeNames[type]
        : '?';
    String label;
    if (typeName == 'object') {
      label = (nameIdx >= 0 && nameIdx < strings.length)
          ? strings[nameIdx]
          : '<object>';
    } else if (typeName == 'closure') {
      final fn = (nameIdx >= 0 && nameIdx < strings.length)
          ? strings[nameIdx]
          : '';
      label = fn.isEmpty ? '<closure>' : 'closure:$fn';
    } else {
      label = '<$typeName>';
    }
    final cur = byCtor[label];
    byCtor[label] = (
      bytes: (cur?.bytes ?? 0) + self,
      count: (cur?.count ?? 0) + 1,
    );
    totalSelf += self;
  }
  return _HeapAggResult(
    byCtor: byCtor,
    nodeCount:
        optionalIntFromValue(snapshot['node_count']) ?? (nodes.length ~/ fLen),
    totalSelf: totalSelf,
  );
}

/// 展示两份堆快照的增量，并按需解析所选构造器的保持者链。
class _SnapshotDiffDialog extends StatefulWidget {
  const _SnapshotDiffDialog({
    required this.whenA,
    required this.whenB,
    required this.bytesA,
    required this.bytesB,
    required this.result,
    required this.bJson,
  });

  final DateTime whenA;
  final DateTime whenB;
  final int bytesA;
  final int bytesB;
  final _HeapDiffResult result;
  final String bJson;

  static String _fmtSigned(int v) => v >= 0 ? '+$v' : '$v';

  @override
  State<_SnapshotDiffDialog> createState() => _SnapshotDiffDialogState();
}

class _SnapshotDiffDialogState extends State<_SnapshotDiffDialog> {
  final ScrollController _growthScrollController = ScrollController();
  String? _selectedLabel;
  bool _retainerLoading = false;
  _RetainerChainResult? _retainerResult;

  @override
  void dispose() {
    _growthScrollController.dispose();
    super.dispose();
  }

  Future<void> _onRowTap(String label) async {
    if (_retainerLoading) return;
    setState(() {
      _selectedLabel = label;
      _retainerLoading = true;
      _retainerResult = null;
    });
    late final _RetainerChainResult result;
    try {
      result = await compute(_findRetainerChainsWorker, <String, String>{
        'json': widget.bJson,
        'label': label,
      });
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '解析堆快照保持者链', error, stack);
      result = _RetainerChainResult(
        label: label,
        found: false,
        totalInstances: 0,
        chains: const <_RetainerChain>[],
        error: '保持者链解析失败。',
      );
    }
    if (!mounted) return;
    setState(() {
      _retainerLoading = false;
      _retainerResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final result = widget.result;
    final dBytes = widget.bytesB - widget.bytesA;
    final dNodes = result.nodesB - result.nodesA;
    final dSelf = result.totalSelfB - result.totalSelfA;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthFull,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.compare_arrows_rounded,
            title: openHandLocalizedText(
              context,
              zh: '堆快照对比',
              zhHant: '堆快照對比',
              en: 'Heap snapshot diff',
              fr: 'Diff des snapshots du tas',
              de: 'Heap-Snapshot-Vergleich',
              ja: 'ヒープスナップショット比較',
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A: ${widget.whenA.toLocal().toIso8601String().split(".").first}'
                  '   →   '
                  'B: ${widget.whenB.toLocal().toIso8601String().split(".").first}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
                kOpenHandGap10,
                _DiffRow(
                  label: openHandLocalizedText(
                    context,
                    zh: '原始字节',
                    zhHant: '原始位元組',
                    en: 'Raw bytes',
                    fr: 'Octets bruts',
                    de: 'Rohbytes',
                    ja: '生バイト',
                  ),
                  a: formatByteSize(widget.bytesA),
                  b: formatByteSize(widget.bytesB),
                  delta: dBytes,
                ),
                _DiffRow(
                  label: openHandLocalizedText(
                    context,
                    zh: '节点数',
                    zhHant: '節點數',
                    en: 'Nodes',
                    fr: 'Nœuds',
                    de: 'Knoten',
                    ja: 'ノード数',
                  ),
                  a: '${result.nodesA}',
                  b: '${result.nodesB}',
                  delta: dNodes,
                ),
                _DiffRow(
                  label: openHandLocalizedText(
                    context,
                    zh: '自有大小',
                    zhHant: '自身大小',
                    en: 'Self size',
                    fr: 'Taille propre',
                    de: 'Self Size',
                    ja: '自己サイズ',
                  ),
                  a: formatByteSize(result.totalSelfA),
                  b: formatByteSize(result.totalSelfB),
                  delta: dSelf,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Row(
              children: [
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '构造器增长 Top 40',
                    zhHant: '建構子增長 Top 40',
                    en: 'Top 40 constructor growth',
                    fr: 'Top 40 croissance par constructeur',
                    de: 'Top 40 Konstruktorwachstum',
                    ja: 'コンストラクター増加 Top 40',
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                kOpenHandHGap10,
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '点击任一行 → 右侧显示保持者链',
                    zhHant: '點選任一列 → 右側顯示保持者鏈',
                    en: 'Click a row → retainer chain on the right',
                    fr: 'Cliquez une ligne → chaîne de rétention à droite',
                    de: 'Zeile anklicken → Retainer Chain rechts',
                    ja: '行をクリック → 右側に保持者チェーンを表示',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (result.error != null)
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '解析失败：${result.error}',
                      zhHant: '解析失敗：${result.error}',
                      en: 'Parse error: ${result.error}',
                      fr: 'Erreur d’analyse : ${result.error}',
                      de: 'Parse-Fehler: ${result.error}',
                      ja: '解析エラー: ${result.error}',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
              ],
            ),
          ),
          Flexible(
            child: result.growth.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: '无可见增长',
                        zhHant: '無可見增長',
                        en: 'No growth detected',
                        fr: 'Aucune croissance détectée',
                        de: 'Kein Wachstum erkannt',
                        ja: '増加は検出されませんでした',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: PrimaryScrollController.none(
                          child: OpenHandSafeScrollbar(
                            controller: _growthScrollController,
                            child: SingleChildScrollView(
                              controller: _growthScrollController,
                              primary: false,
                              padding: const EdgeInsets.fromLTRB(20, 0, 12, 16),
                              child: DataTable(
                                headingRowHeight: 32,
                                dataRowMinHeight: 28,
                                dataRowMaxHeight: 32,
                                columnSpacing: 24,
                                showCheckboxColumn: false,
                                columns: [
                                  DataColumn(
                                    label: Text(
                                      openHandLocalizedText(
                                        context,
                                        zh: '构造器',
                                        zhHant: '建構子',
                                        en: 'Constructor',
                                        fr: 'Constructeur',
                                        de: 'Konstruktor',
                                        ja: 'コンストラクター',
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      openHandLocalizedText(
                                        context,
                                        zh: '字节增量',
                                        zhHant: '位元組增量',
                                        en: 'Δ bytes',
                                        fr: 'Δ octets',
                                        de: 'Δ Bytes',
                                        ja: 'Δ バイト',
                                      ),
                                    ),
                                    numeric: true,
                                  ),
                                  DataColumn(
                                    label: Text(
                                      openHandLocalizedText(
                                        context,
                                        zh: '节点增量',
                                        zhHant: '節點增量',
                                        en: 'Δ count',
                                        fr: 'Δ nombre',
                                        de: 'Δ Anzahl',
                                        ja: 'Δ 件数',
                                      ),
                                    ),
                                    numeric: true,
                                  ),
                                  DataColumn(
                                    label: Text(
                                      openHandLocalizedText(
                                        context,
                                        zh: 'A 字节',
                                        zhHant: 'A 位元組',
                                        en: 'A bytes',
                                        fr: 'Octets A',
                                        de: 'A Bytes',
                                        ja: 'A バイト',
                                      ),
                                    ),
                                    numeric: true,
                                  ),
                                  DataColumn(
                                    label: Text(
                                      openHandLocalizedText(
                                        context,
                                        zh: 'B 字节',
                                        zhHant: 'B 位元組',
                                        en: 'B bytes',
                                        fr: 'Octets B',
                                        de: 'B Bytes',
                                        ja: 'B バイト',
                                      ),
                                    ),
                                    numeric: true,
                                  ),
                                ],
                                rows: [
                                  for (final g in result.growth)
                                    DataRow(
                                      selected: g.label == _selectedLabel,
                                      onSelectChanged: (_) =>
                                          _onRowTap(g.label),
                                      cells: [
                                        DataCell(
                                          SelectableText(
                                            g.label,
                                            style: const TextStyle(
                                              fontFamily:
                                                  kOpenHandMonospaceFontFamily,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            formatSignedByteSize(g.bytesDelta),
                                            style: TextStyle(
                                              fontFamily:
                                                  kOpenHandMonospaceFontFamily,
                                              fontSize: 12,
                                              color: g.bytesDelta > 0
                                                  ? cs.error
                                                  : (g.bytesDelta < 0
                                                        ? Colors.green
                                                        : cs.onSurfaceVariant),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            _SnapshotDiffDialog._fmtSigned(
                                              g.countDelta,
                                            ),
                                            style: const TextStyle(
                                              fontFamily:
                                                  kOpenHandMonospaceFontFamily,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            formatByteSize(g.bytesA),
                                            style: const TextStyle(
                                              fontFamily:
                                                  kOpenHandMonospaceFontFamily,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            formatByteSize(g.bytesB),
                                            style: const TextStyle(
                                              fontFamily:
                                                  kOpenHandMonospaceFontFamily,
                                              fontSize: 12,
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
                      ),
                      if (_selectedLabel != null) ...[
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: 360,
                          child: _RetainerSidePanel(
                            ctorLabel: _selectedLabel!,
                            loading: _retainerLoading,
                            result: _retainerResult,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 单条保持者链，路径从目标实例向外延伸。
class _RetainerChain {
  const _RetainerChain({required this.path});
  final List<String> path;
  int get hops => path.length;
}

class _RetainerChainResult {
  const _RetainerChainResult({
    required this.label,
    required this.found,
    required this.totalInstances,
    required this.chains,
    required this.error,
  });
  final String label;
  final bool found;
  final int totalInstances;
  final List<_RetainerChain> chains;
  final String? error;
}

/// 在 isolate 里跑：解析 .heapsnapshot 的 nodes / edges 表，建立反向邻
/// 接表，从该 ctor label 的代表实例出发往上反推 retainer chain（最多 5
/// 跳；同一节点不重复扩展防回路）；展示时取最短的 6 条 chain。
_RetainerChainResult _findRetainerChainsWorker(Map<String, String> input) {
  final src = input['json'] ?? '';
  final wantLabel = input['label'] ?? '';
  try {
    final m = decodeStringKeyedJsonMap(src);
    if (m == null) {
      throw const FormatException('堆快照 JSON 必须是对象。');
    }
    final snapshot = stringKeyedMapFromValue(m['snapshot']);
    final meta = stringKeyedMapFromValue(snapshot['meta']);
    final nodeFields = _heapStringList(meta['node_fields'], const [
      'type',
      'name',
      'id',
      'self_size',
      'edge_count',
    ]);
    final edgeFields = _heapStringList(meta['edge_fields'], const [
      'type',
      'name_or_index',
      'to_node',
    ]);
    final nLen = nodeFields.length;
    final eLen = edgeFields.length;
    final iType = nodeFields.indexOf('type');
    final iName = nodeFields.indexOf('name');
    final iEdgeCount = nodeFields.indexOf('edge_count');
    final iEdgeTo = edgeFields.indexOf('to_node');
    final iEdgeName = edgeFields.indexOf('name_or_index');
    if (nLen <= 0 || eLen <= 0 || iType < 0 || iEdgeTo < 0) {
      throw const FormatException('堆快照字段元数据无效。');
    }
    final typeNames = _heapFirstStringList(meta['node_types'], const [
      'object',
    ]);
    final nodes = m['nodes'] is List
        ? List<Object?>.of(m['nodes'] as List, growable: false)
        : const <Object?>[];
    final edges = m['edges'] is List
        ? List<Object?>.of(m['edges'] as List, growable: false)
        : const <Object?>[];
    final strings = stringListFromValue(m['strings']);

    String labelOfNode(int nodeIdx) {
      final base = nodeIdx;
      final type = _heapIntAt(nodes, base + iType);
      final nameIdx = iName >= 0 ? _heapIntAt(nodes, base + iName) : 0;
      final typeName = (type >= 0 && type < typeNames.length)
          ? typeNames[type]
          : '?';
      final name = (nameIdx >= 0 && nameIdx < strings.length)
          ? strings[nameIdx]
          : '';
      if (typeName == 'object') return name.isEmpty ? '<object>' : name;
      if (typeName == 'closure') {
        return name.isEmpty ? '<closure>' : 'closure:$name';
      }
      return '<$typeName>';
    }

    // 节点起始下标列表（每个 node 占 nLen 个 int）。i-th 节点在
    // nodes[i*nLen .. i*nLen + nLen - 1]。
    final nodeCount = nodes.length ~/ (nLen == 0 ? 1 : nLen);
    // 第一遍：累计每个 node 的 edges 起始位置（在 edges 数组里的偏移）。
    final edgeOffsets = List<int>.filled(nodeCount + 1, 0);
    for (var i = 0; i < nodeCount; i++) {
      final ec = iEdgeCount >= 0 ? _heapIntAt(nodes, i * nLen + iEdgeCount) : 0;
      edgeOffsets[i + 1] = edgeOffsets[i] + ec * eLen;
    }

    // 找出该 ctor 的所有实例 nodeIndex；再挑 self_size 最大的代表。
    final iSelf = nodeFields.indexOf('self_size');
    final candidates = <int>[];
    for (var i = 0; i < nodeCount; i++) {
      if (labelOfNode(i * nLen) == wantLabel) candidates.add(i);
    }
    if (candidates.isEmpty) {
      return _RetainerChainResult(
        label: wantLabel,
        found: false,
        totalInstances: 0,
        chains: const [],
        error: null,
      );
    }
    int leader = candidates.first;
    if (iSelf >= 0) {
      var bestSelf = -1;
      for (final c in candidates) {
        final s = _heapIntAt(nodes, c * nLen + iSelf);
        if (s > bestSelf) {
          bestSelf = s;
          leader = c;
        }
      }
    }

    // 第二遍：构建反向邻接表 reverse[targetNode] = list of (source,
    // edgeName). edges 里每条 edge 的 to_node 是「字节偏移」（按 V8
    // heapsnapshot 规范），需要除以 nLen 还原成节点 index。
    final reverse = List<List<int>>.generate(nodeCount, (_) => <int>[]);
    final reverseEdgeName = List<List<String>>.generate(
      nodeCount,
      (_) => <String>[],
    );
    for (var src = 0; src < nodeCount; src++) {
      final start = edgeOffsets[src];
      final end = edgeOffsets[src + 1];
      for (var e = start; e + eLen <= end; e += eLen) {
        final to = _heapIntAt(edges, e + iEdgeTo);
        final tIdx = to ~/ nLen;
        if (tIdx < 0 || tIdx >= nodeCount) continue;
        final nameIdx = iEdgeName >= 0 ? _heapIntAt(edges, e + iEdgeName) : 0;
        // edge 的 name_or_index 对 element 边是数字索引、对 property/internal
        // 边是 strings[name] 的下标。这里只展示前者数字、后者字符串。
        final n = (nameIdx >= 0 && nameIdx < strings.length)
            ? strings[nameIdx]
            : '$nameIdx';
        reverse[tIdx].add(src);
        reverseEdgeName[tIdx].add(n);
      }
    }

    // BFS 从 leader 反向走，最多 5 跳。每条 chain 最长 6 个 label
    // （目标 + 5 个 retainer）。同一节点不重复扩展防环。
    final chains = <_RetainerChain>[];
    final visited = <int>{};
    final queue = <(int node, List<String> path)>[
      (leader, [labelOfNode(leader * nLen)]),
    ];
    while (queue.isNotEmpty && chains.length < 12) {
      final entry = queue.removeAt(0);
      final node = entry.$1;
      final path = entry.$2;
      visited.add(node);
      final retainers = reverse[node];
      if (retainers.isEmpty || path.length >= 6) {
        chains.add(_RetainerChain(path: path));
        continue;
      }
      // 取每个节点的至多 3 个 retainer 进队，避免邻接爆炸。
      var emitted = 0;
      for (var k = 0; k < retainers.length && emitted < 3; k++) {
        final r = retainers[k];
        if (visited.contains(r)) continue;
        final retainerLabel =
            '${labelOfNode(r * nLen)} . ${reverseEdgeName[node][k]}';
        queue.add((r, [...path, retainerLabel]));
        emitted++;
      }
    }
    chains.sort((a, b) => a.hops.compareTo(b.hops));
    return _RetainerChainResult(
      label: wantLabel,
      found: true,
      totalInstances: candidates.length,
      chains: chains.take(6).toList(growable: false),
      error: null,
    );
  } catch (e) {
    return _RetainerChainResult(
      label: wantLabel,
      found: false,
      totalInstances: 0,
      chains: const [],
      error: '$e',
    );
  }
}

/// 保持者链侧栏：标题 + 实例数 + 链路列表。链路渲染成树状缩进，每跳一
/// 个 ChevronRight 图标 + 反指 retainer label。
class _RetainerSidePanel extends StatelessWidget {
  const _RetainerSidePanel({
    required this.ctorLabel,
    required this.loading,
    required this.result,
  });

  final String ctorLabel;
  final bool loading;
  final _RetainerChainResult? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            openHandLocalizedText(
              context,
              zh: '保持者链',
              zhHant: '保持者鏈',
              en: 'Retainer chain',
              fr: 'Chaîne de rétention',
              de: 'Retainer Chain',
              ja: '保持者チェーン',
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          kOpenHandGap4,
          SelectableText(
            ctorLabel,
            style: const TextStyle(
              fontFamily: kOpenHandMonospaceFontFamily,
              fontSize: 11,
            ),
          ),
          kOpenHandGap10,
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (result == null)
            Text(
              openHandLocalizedText(
                context,
                zh: '尚未分析',
                zhHant: '尚未分析',
                en: 'Not analyzed',
                fr: 'Non analysé',
                de: 'Nicht analysiert',
                ja: '未解析',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else if (result!.error != null)
            Text(
              openHandLocalizedText(
                context,
                zh: '解析失败：${result!.error}',
                zhHant: '解析失敗：${result!.error}',
                en: 'Parse failed: ${result!.error}',
                fr: 'Échec de l’analyse : ${result!.error}',
                de: 'Analyse fehlgeschlagen: ${result!.error}',
                ja: '解析に失敗しました: ${result!.error}',
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            )
          else if (!result!.found)
            Text(
              openHandLocalizedText(
                context,
                zh: '快照中未找到该构造器实例',
                zhHant: '快照中找不到該建構子實例',
                en: 'Constructor not in snapshot',
                fr: 'Constructeur absent du snapshot',
                de: 'Konstruktor nicht im Snapshot',
                ja: 'スナップショット内にコンストラクターが見つかりません',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else ...[
            Text(
              openHandLocalizedText(
                context,
                zh: '找到 ${result!.totalInstances} 个实例 · 取自有大小最大的代表',
                zhHant: '找到 ${result!.totalInstances} 個實例 · 取自身大小最大的代表',
                en: '${result!.totalInstances} instances · using largest leader',
                fr: '${result!.totalInstances} instances · plus grand représentant',
                de: '${result!.totalInstances} Instanzen · größter Vertreter',
                ja: '${result!.totalInstances} 個のインスタンス · 最大の代表を使用',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            kOpenHandGap10,
            Expanded(
              child: ListView.builder(
                itemCount: result!.chains.length,
                itemBuilder: (_, idx) {
                  final chain = result!.chains[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: webReverseSurfaceCardDecoration(
                        cs,
                        radius: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            openHandLocalizedText(
                              context,
                              zh: 'chain · ${chain.hops} 跳',
                              zhHant: 'chain · ${chain.hops} 跳',
                              en: 'chain · ${chain.hops} hops',
                              fr: 'chain · ${chain.hops} sauts',
                              de: 'chain · ${chain.hops} Hops',
                              ja: 'chain · ${chain.hops} ホップ',
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                          kOpenHandGap4,
                          for (var i = chain.path.length - 1; i >= 0; i--)
                            Padding(
                              padding: EdgeInsets.only(
                                left: (chain.path.length - 1 - i) * 10.0,
                                top: 1,
                                bottom: 1,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.subdirectory_arrow_right_rounded,
                                    size: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  kOpenHandHGap4,
                                  Expanded(
                                    child: SelectableText(
                                      chain.path[i],
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontFamily:
                                            kOpenHandMonospaceFontFamily,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Performance：inline timeline lanes（Loading/Scripting/Rendering/Painting/Other）
// _TraceLaneEvent + _parseTraceLanes + _TraceLanesInline + _TraceLanesPainter

/// 单个 trace 事件在 lane timeline 里的最小描述。
class _TraceLaneEvent {
  _TraceLaneEvent({
    required this.startMs,
    required this.durMs,
    required this.lane,
    required this.name,
  });

  /// 相对于 trace 起点的毫秒数。
  final double startMs;
  final double durMs;

  /// 0=Loading 1=Scripting 2=Rendering 3=Painting 4=Other
  final int lane;
  final String name;
}

class _TraceLaneParseResult {
  _TraceLaneParseResult(this.events, this.minTs, this.maxTs);
  final List<_TraceLaneEvent> events;
  final double minTs;
  final double maxTs;
}

/// 把 Chrome trace JSON 解析成 lane 事件序列。
/// 仅识别 `ph == 'X'`（complete）类型，时长 < 0.05ms 的噪声事件丢弃。
/// 最多保留 8000 条，避免 isolate-free 主线程渲染卡顿。
_TraceLaneParseResult _parseTraceLanes(String json) {
  final decodedMap = decodeStringKeyedJsonMap(json);
  final rawEvents = decodedMap == null
      ? decodeJsonList(json)
      : decodedMap['traceEvents'];
  final events = rawEvents is List ? rawEvents : const <Object?>[];
  if (events.isEmpty) return _TraceLaneParseResult(const [], 0, 0);
  final out = <_TraceLaneEvent>[];
  double minTs = double.infinity;
  double maxTs = -double.infinity;
  for (final raw in events) {
    if (raw is! Map) continue;
    if (raw['ph'] != 'X') continue;
    final ts = optionalNonNegativeDoubleFromValue(raw['ts']);
    final dur = optionalNonNegativeDoubleFromValue(raw['dur']);
    if (ts == null || dur == null) continue;
    if (dur < 50) continue; // <0.05ms 噪声
    final name = (raw['name'] as String?) ?? '';
    final cat = (raw['cat'] as String?) ?? '';
    final lane = _categorizeLane(name, cat);
    final startMs = ts / 1000.0;
    final durMs = dur / 1000.0;
    if (startMs < minTs) minTs = startMs;
    if (startMs + durMs > maxTs) maxTs = startMs + durMs;
    out.add(
      _TraceLaneEvent(startMs: startMs, durMs: durMs, lane: lane, name: name),
    );
    if (out.length >= 8000) break;
  }
  if (out.isEmpty) return _TraceLaneParseResult(const [], 0, 0);
  // 全部 startMs 归一到 0 起点
  final shifted = out
      .map(
        (e) => _TraceLaneEvent(
          startMs: e.startMs - minTs,
          durMs: e.durMs,
          lane: e.lane,
          name: e.name,
        ),
      )
      .toList(growable: false);
  return _TraceLaneParseResult(shifted, 0, maxTs - minTs);
}

/// Chrome trace 事件 → lane index。
int _categorizeLane(String name, String cat) {
  // Loading
  if (cat.contains('loading') ||
      cat.contains('netlog') ||
      name == 'ParseHTML' ||
      name == 'ResourceFinish' ||
      name == 'ResourceReceiveResponse' ||
      name == 'ResourceSendRequest' ||
      name == 'ResourceReceivedData' ||
      name == 'XHRReadyStateChange' ||
      name == 'XHRLoad') {
    return 0;
  }
  // Painting
  if (name == 'Paint' ||
      name == 'RasterTask' ||
      name == 'CompositeLayers' ||
      name == 'UpdateLayerTree' ||
      name == 'PaintImage' ||
      name == 'DecodeImage' ||
      name == 'Decode Image' ||
      name == 'Decode LazyPixelRef' ||
      name == 'DrawFrame') {
    return 3;
  }
  // Rendering
  if (name == 'Layout' ||
      name == 'UpdateLayoutTree' ||
      name == 'RecalculateStyles' ||
      name == 'ScheduleStyleRecalculation' ||
      name == 'ParseAuthorStyleSheet' ||
      name == 'HitTest') {
    return 2;
  }
  // Scripting
  if (cat.contains('v8') ||
      cat.contains('disabled-by-default-v8') ||
      name == 'FunctionCall' ||
      name == 'EvaluateScript' ||
      name == 'TimerFire' ||
      name == 'TimerInstall' ||
      name == 'TimerRemove' ||
      name == 'GCEvent' ||
      name == 'MajorGC' ||
      name == 'MinorGC' ||
      name == 'RunMicrotasks' ||
      name == 'V8.Execute' ||
      name == 'CompileScript' ||
      name == 'v8.compile') {
    return 1;
  }
  return 4;
}

/// 面板内嵌的 trace lane timeline。横向 InteractiveViewer 支持
/// 双指 / Ctrl+滚轮缩放，普通拖动平移；reduceMotion 时禁用任何
/// 隐式动画（CustomPaint 本身就是静态绘制）。
class _TraceLanesInline extends StatefulWidget {
  const _TraceLanesInline({
    required this.events,
    required this.minTs,
    required this.maxTs,
  });

  final List<_TraceLaneEvent> events;
  final double minTs;
  final double maxTs;

  @override
  State<_TraceLanesInline> createState() => _TraceLanesInlineState();
}

class _TraceLanesInlineState extends State<_TraceLanesInline> {
  Offset? _hoverPos;
  _TraceLaneEvent? _hoverEvent;
  bool _hoverScheduled = false;

  static const double _kLaneH = 18;
  static const double _kAxisH = 18;
  static const int _kLaneCount = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = widget.maxTs <= 0 ? 1.0 : widget.maxTs;
    const totalH = _kLaneH * _kLaneCount + _kAxisH;
    return Container(
      decoration: webReverseSurfaceCardDecoration(cs, radius: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_rounded, size: 16, color: cs.primary),
              kOpenHandHGap6,
              Text(
                openHandLocalizedText(
                  context,
                  zh: 'Trace 时间线（${widget.events.length} 事件 · ${total.toStringAsFixed(1)} ms）',
                  zhHant:
                      'Trace 時間線（${widget.events.length} 事件 · ${total.toStringAsFixed(1)} ms）',
                  en: 'Trace timeline (${widget.events.length} events · ${total.toStringAsFixed(1)} ms)',
                  fr: 'Chronologie Trace (${widget.events.length} événements · ${total.toStringAsFixed(1)} ms)',
                  de: 'Trace-Zeitleiste (${widget.events.length} Ereignisse · ${total.toStringAsFixed(1)} ms)',
                  ja: 'Trace タイムライン（${widget.events.length} イベント · ${total.toStringAsFixed(1)} ms）',
                ),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              kOpenHandHGap14,
              for (final entry in _kLaneMeta.asMap().entries) ...[
                if (entry.key != 0) kOpenHandHGap8,
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: entry.value.color,
                    borderRadius: BorderRadius.circular(kOpenHandRadius2),
                  ),
                ),
                kOpenHandHGap4,
                Text(
                  openHandLocalizedText(
                    context,
                    zh: entry.value.zh,
                    zhHant: entry.value.zhHant,
                    en: entry.value.en,
                    fr: entry.value.fr,
                    de: entry.value.de,
                    ja: entry.value.ja,
                  ),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ],
          ),
          kOpenHandGap8,
          SizedBox(
            height: totalH,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return MouseRegion(
                  onHover: (e) => _updateHover(e.localPosition, width),
                  onExit: (_) {
                    _hoverPos = null;
                    _hoverEvent = null;
                    if (_hoverScheduled) return;
                    _hoverScheduled = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _hoverScheduled = false;
                      if (mounted) setState(() {});
                    });
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _TraceLanesPainter(
                            events: widget.events,
                            totalMs: total,
                            laneH: _kLaneH,
                            axisH: _kAxisH,
                            laneCount: _kLaneCount,
                            outline: cs.outlineVariant,
                            axisLabel: cs.onSurfaceVariant,
                            highlight: _hoverEvent,
                          ),
                        ),
                      ),
                      if (_hoverEvent != null && _hoverPos != null)
                        Positioned(
                          left: (_hoverPos!.dx + 12).clamp(0, width - 240),
                          top: (_hoverPos!.dy + 12).clamp(0, totalH - 60),
                          child: IgnorePointer(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 240),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: cs.inverseSurface,
                                borderRadius: kOpenHandBorderRadius6,
                              ),
                              child: Text(
                                '${_hoverEvent!.name}\n'
                                '${_hoverEvent!.startMs.toStringAsFixed(2)} ms +${_hoverEvent!.durMs.toStringAsFixed(2)} ms',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onInverseSurface,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _updateHover(Offset pos, double width) {
    final total = widget.maxTs <= 0 ? 1.0 : widget.maxTs;
    final laneIdx = (pos.dy ~/ _kLaneH).clamp(0, _kLaneCount - 1);
    final tMs = pos.dx / width * total;
    _TraceLaneEvent? hit;
    // 反向遍历，命中前景（最后绘制）事件；O(N) 足够 8000 内。
    for (var i = widget.events.length - 1; i >= 0; i--) {
      final e = widget.events[i];
      if (e.lane != laneIdx) continue;
      if (tMs >= e.startMs && tMs <= e.startMs + e.durMs) {
        hit = e;
        break;
      }
    }
    _hoverPos = pos;
    _hoverEvent = hit;
    if (_hoverScheduled) return;
    _hoverScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hoverScheduled = false;
      if (mounted) setState(() {});
    });
  }
}

/// Trace lane name + color metadata.
const List<
  ({
    String zh,
    String zhHant,
    String en,
    String fr,
    String de,
    String ja,
    Color color,
  })
>
_kLaneMeta =
    <
      ({
        String zh,
        String zhHant,
        String en,
        String fr,
        String de,
        String ja,
        Color color,
      })
    >[
      (
        zh: '加载',
        zhHant: '載入',
        en: 'Loading',
        fr: 'Chargement',
        de: 'Laden',
        ja: '読み込み',
        color: Color(0xFF60A5FA),
      ),
      (
        zh: '脚本',
        zhHant: '腳本',
        en: 'Scripting',
        fr: 'Script',
        de: 'Scripting',
        ja: 'スクリプト',
        color: Color(0xFFFBBF24),
      ),
      (
        zh: '渲染',
        zhHant: '渲染',
        en: 'Rendering',
        fr: 'Rendu',
        de: 'Rendering',
        ja: 'レンダリング',
        color: Color(0xFFA78BFA),
      ),
      (
        zh: '绘制',
        zhHant: '繪製',
        en: 'Painting',
        fr: 'Peinture',
        de: 'Painting',
        ja: '描画',
        color: Color(0xFF34D399),
      ),
      (
        zh: '其它',
        zhHant: '其他',
        en: 'Other',
        fr: 'Autre',
        de: 'Sonstiges',
        ja: 'その他',
        color: Color(0xFF94A3B8),
      ),
    ];

class _TraceLanesPainter extends CustomPainter {
  _TraceLanesPainter({
    required this.events,
    required this.totalMs,
    required this.laneH,
    required this.axisH,
    required this.laneCount,
    required this.outline,
    required this.axisLabel,
    required this.highlight,
  });

  final List<_TraceLaneEvent> events;
  final double totalMs;
  final double laneH;
  final double axisH;
  final int laneCount;
  final Color outline;
  final Color axisLabel;
  final _TraceLaneEvent? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    if (width <= 0) return;
    final pxPerMs = width / (totalMs <= 0 ? 1 : totalMs);
    final laneBg = Paint()..color = outline.withValues(alpha: 0.18);
    final laneBorder = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = 0; i < laneCount; i++) {
      final rect = Rect.fromLTWH(0, i * laneH, width, laneH);
      // 间隔条纹增强可读性
      if (i.isOdd) canvas.drawRect(rect, laneBg);
      canvas.drawLine(
        Offset(0, (i + 1) * laneH),
        Offset(width, (i + 1) * laneH),
        laneBorder,
      );
    }
    // 事件矩形
    final fills = _kLaneMeta.map((m) => Paint()..color = m.color).toList();
    final highlightStroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final e in events) {
      final left = e.startMs * pxPerMs;
      final w = (e.durMs * pxPerMs).clamp(1.0, width);
      final top = e.lane * laneH + 2;
      final rect = Rect.fromLTWH(left, top, w, laneH - 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(kOpenHandRadius2)),
        fills[e.lane],
      );
      if (identical(e, highlight)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect,
            const Radius.circular(kOpenHandRadius2),
          ),
          highlightStroke,
        );
      }
    }
    // 时间刻度
    final axisY = laneCount * laneH;
    final axisLine = Paint()
      ..color = outline
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, axisY), Offset(width, axisY), axisLine);
    const tickCount = 6;
    for (var i = 0; i <= tickCount; i++) {
      final x = width * i / tickCount;
      canvas.drawLine(Offset(x, axisY), Offset(x, axisY + 4), axisLine);
      final tp = TextPainter(
        text: TextSpan(
          text: '${(totalMs * i / tickCount).toStringAsFixed(0)}ms',
          style: TextStyle(color: axisLabel, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (x - tp.width / 2).clamp(0, width - tp.width).toDouble();
      tp.paint(canvas, Offset(dx, axisY + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _TraceLanesPainter old) =>
      old.events != events ||
      old.totalMs != totalMs ||
      old.highlight != highlight ||
      old.outline != outline;
}

// ── 本文件内复用的文案 ──
// 同一标签在本文件里出现两次以上；抽成函数后措辞只有一个改动点。

String _webReverseDashAddCookieLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '新增 cookie',
    zhHant: '新增 cookie',
    en: 'Add cookie',
    fr: 'Ajouter un cookie',
    de: 'Cookie hinzufügen',
    ja: 'cookie を追加',
  );
}

String _webReverseDashClearAllLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '清空',
    zhHant: '清空',
    en: 'Clear all',
    fr: 'Tout effacer',
    de: 'Alle leeren',
    ja: 'すべてクリア',
  );
}

String _webReverseDashDeleteFailedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '删除失败',
    zhHant: '刪除失敗',
    en: 'Delete failed',
    fr: 'Échec de la suppression',
    de: 'Löschen fehlgeschlagen',
    ja: '削除に失敗しました',
  );
}

String _webReverseDashEmptyLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '（空）',
    zhHant: '（空）',
    en: '(empty)',
    fr: '(vide)',
    de: '(leer)',
    ja: '（空）',
  );
}

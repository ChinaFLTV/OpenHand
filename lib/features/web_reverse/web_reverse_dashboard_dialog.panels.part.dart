part of 'web_reverse_dashboard_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────
// Performance：实时 Performance.getMetrics 卡片 + Tracing 录制（导出 trace.json）
// ─────────────────────────────────────────────────────────────────────────

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
  bool _tracing = false;
  Duration _traceDuration = const Duration(seconds: 5);
  // 上次成功录制的 trace JSON，用于「查看火焰图」按钮；超过 8MB 不缓存以
  // 防内存暴涨。
  String? _lastTraceJson;

  // FPS：用 requestAnimationFrame 在浏览器里采样上一秒帧数，
  // 通过 Runtime.evaluate 拉回。
  Timer? _fpsTimer;
  final List<double> _fpsHistory = <double>[];
  bool _fpsBootstrapped = false;

  // Long task：浏览器 PerformanceObserver 推到 window.__oh_long_tasks，
  // 每 1s 拉一次清空，dashboard 展示最近 50 条。
  Timer? _longTaskTimer;
  bool _longTaskBootstrapped = false;
  final List<Map<String, Object?>> _longTasks = <Map<String, Object?>>[];
  static const int _longTasksMax = 50;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refresh(),
    );
    _fpsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _sampleFps(),
    );
    _longTaskTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _sampleLongTasks(),
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
    final m = await widget.controller.performanceMetrics();
    if (!mounted) return;
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
    if (!_fpsBootstrapped) {
      _fpsBootstrapped = true;
      await cdp.installFpsCounter();
    }
    final fps = await cdp.readFps();
    if (!mounted || fps == null) return;
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
    if (!_longTaskBootstrapped) {
      _longTaskBootstrapped = true;
      await cdp.installLongTaskObserver();
    }
    final fresh = await cdp.readLongTasks();
    if (!mounted || fresh.isEmpty) return;
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
    showDialog<void>(
      context: context,
      builder: (_) => _FlameGraphDialog(traceJson: raw, isZh: widget.isZh),
    );
  }

  /// 把当前记录的 FPS 历史 + Long task 列表合并成 CSV 落盘。两段数据放
  /// 同一个文件，靠 section 标记区分，方便 Excel / 数据分析工具一次性吃。
  Future<void> _exportCsv() async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
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
    } catch (_) {}
    if (!mounted || location == null) return;
    try {
      await File(location.path).writeAsString(buf.toString());
      if (!mounted) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? '已保存到 ${location.path}' : 'Saved',
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'export performance csv',
        error,
        stack,
      );
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '保存失败' : 'Save failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _record() async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _tracing = true);
    String? json;
    try {
      json = await widget.controller.recordTrace(duration: _traceDuration);
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', 'recordTrace', error, stack);
    }
    if (!mounted) return;
    setState(() => _tracing = false);
    if (json == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? 'Trace 录制失败' : 'Trace failed',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    if (json.length <= 8 * 1024 * 1024) {
      _lastTraceJson = json;
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
      silentLog(
        'web_reverse_dashboard_dialog',
        'getSaveLocation trace',
        error,
        stack,
      );
    }
    if (location == null) return;
    try {
      await File(location.path).writeAsString(json);
      if (!mounted) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? 'Trace 已保存到 ${location.path}' : 'Saved',
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', 'write trace', error, stack);
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? 'Trace 保存失败' : 'Save failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
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
                isZh ? '实时性能指标（每 2s 刷新）' : 'Live Performance Metrics (refresh 2s)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              DropdownButton<Duration>(
                value: _traceDuration,
                onChanged: _tracing
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _traceDuration = v);
                      },
                items: const [
                  DropdownMenuItem(value: Duration(seconds: 3), child: Text('3 s')),
                  DropdownMenuItem(value: Duration(seconds: 5), child: Text('5 s')),
                  DropdownMenuItem(value: Duration(seconds: 10), child: Text('10 s')),
                  DropdownMenuItem(value: Duration(seconds: 30), child: Text('30 s')),
                ],
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _tracing ? null : _record,
                icon: Icon(
                  _tracing
                      ? Icons.fiber_manual_record_rounded
                      : Icons.play_arrow_rounded,
                  size: 18,
                ),
                label: Text(_tracing
                    ? (isZh ? '录制中…' : 'Recording…')
                    : (isZh ? '录制 Trace' : 'Record Trace')),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed:
                    (_fpsHistory.isEmpty && _longTasks.isEmpty) ? null : _exportCsv,
                icon: const Icon(Icons.table_view_rounded, size: 18),
                label: Text(isZh ? '导出 CSV' : 'Export CSV'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _lastTraceJson == null ? null : _showFlameGraph,
                icon: const Icon(Icons.local_fire_department_rounded, size: 18),
                label: Text(isZh ? '火焰图' : 'Flame graph'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // FPS 横幅卡片：单独一行展示，sparkline 占满宽度。
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('FPS',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
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
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _metrics.isEmpty
                      ? Center(
                          child: Text(
                            isZh ? '尚无指标数据。' : 'No metrics yet.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : GridView.count(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2.2,
                          children: _orderedMetrics(highlights).map((m) {
                            final history =
                                _history[m.$1] ?? const <double>[];
                            return AnimatedContainer(
                              duration: widget.reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: cs.outlineVariant),
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
                                      _localizedMetricName(m.$1, isZh),
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
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
                const SizedBox(width: 12),
                // Long tasks 侧栏：固定 320 宽，紧凑列表 + 时长高亮。
                SizedBox(
                  width: 320,
                  child: _LongTasksPane(
                    tasks: _longTasks,
                    isZh: isZh,
                  ),
                ),
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
      ..sort((a, b) =>
          highlights.indexOf(a.$1).compareTo(highlights.indexOf(b.$1)));
    final lo = _metrics.where((m) => !highlights.contains(m.$1)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return [...hi, ...lo];
  }
}

/// CDP `Performance.getMetrics` 指标名 → 本地化展示名。
/// 仅做覆盖性翻译；未命中名直接回退到原名（保证未来 CDP 新增字段时不会丢字段）。
String _localizedMetricName(String cdpName, bool isZh) {
  if (!isZh) {
    // 英文环境下用更人类可读的展示名替换驼峰原名（如 Frames Per Second）。
    return _enFriendlyMetricName(cdpName);
  }
  switch (cdpName) {
    // 生命周期 / 时间
    case 'Timestamp':
      return '时间戳';
    case 'AudioHandlers':
      return '音频处理器';
    case 'AudioWorkletProcessors':
      return '音频 Worklet 处理器';
    case 'Documents':
      return 'Document 数';
    case 'Frames':
      return 'Frame 数';
    case 'JSEventListeners':
      return 'JS 事件监听器';
    case 'Nodes':
      return 'DOM 节点数';
    case 'LayoutCount':
      return '布局次数';
    case 'RecalcStyleCount':
      return '样式重算次数';
    case 'LayoutDuration':
      return '布局耗时';
    case 'RecalcStyleDuration':
      return '样式重算耗时';
    case 'DevToolsCommandDuration':
      return 'DevTools 命令耗时';
    case 'ScriptDuration':
      return '脚本耗时';
    case 'V8CompileDuration':
      return 'V8 编译耗时';
    case 'TaskDuration':
      return '任务耗时';
    case 'TaskOtherDuration':
      return '其他任务耗时';
    case 'ThreadTime':
      return '线程时间';
    case 'ProcessTime':
      return '进程时间';
    case 'JSHeapUsedSize':
      return 'JS 堆已用';
    case 'JSHeapTotalSize':
      return 'JS 堆总量';
    case 'FirstMeaningfulPaint':
      return '首次有意义绘制';
    case 'DomContentLoaded':
      return 'DOMContentLoaded';
    case 'NavigationStart':
      return '导航开始';
    case 'AdSubframes':
      return '广告子框架';
    case 'ArrayBufferContents':
      return 'ArrayBuffer 内容';
    case 'Resources':
      return '资源数';
    case 'ContextLifecycleStateObservers':
      return '上下文生命周期观察者';
    case 'V8PerContextDatas':
      return 'V8 上下文数据';
    case 'WorkerGlobalScopes':
      return 'Worker 全局作用域';
    case 'UACSSResources':
      return 'UA CSS 资源';
    case 'RTCPeerConnections':
      return 'WebRTC 连接';
    case 'ResourceFetchers':
      return '资源 Fetcher';
    case 'AdSubframesEvictions':
      return '广告子框架淘汰';
    case 'NumberOfDocuments':
      return 'Document 数（细分）';
    case 'NumberOfActiveAndInactiveAnimations':
      return '活动/休眠动画数';
    case 'NumberOfMediaContexts':
      return '媒体上下文数';
    case 'AdFrameSubframes':
      return '广告子框架（嵌套）';
    case 'AnimationCallbackPropertyTreeBuildersTime':
      return '动画属性树构建耗时';
    case 'PaintingTime':
      return '绘制耗时';
    case 'CompositingTime':
      return '合成耗时';
    case 'CSSStyleSheets':
      return 'CSS 样式表';
    case 'ImageHolders':
      return '图片占位符';
    case 'CompositorVisibleRectChange':
      return '合成器可见矩形变更';
    default:
      return cdpName;
  }
}

String _enFriendlyMetricName(String cdpName) {
  switch (cdpName) {
    case 'JSHeapUsedSize':
      return 'JS Heap Used';
    case 'JSHeapTotalSize':
      return 'JS Heap Total';
    case 'TaskDuration':
      return 'Task Duration';
    case 'TaskOtherDuration':
      return 'Task Other Duration';
    case 'LayoutDuration':
      return 'Layout Duration';
    case 'RecalcStyleDuration':
      return 'Recalc Style Duration';
    case 'ScriptDuration':
      return 'Script Duration';
    case 'V8CompileDuration':
      return 'V8 Compile Duration';
    case 'DevToolsCommandDuration':
      return 'DevTools Cmd Duration';
    case 'FirstMeaningfulPaint':
      return 'First Meaningful Paint';
    case 'DomContentLoaded':
      return 'DOMContentLoaded';
    case 'NavigationStart':
      return 'Navigation Start';
    case 'JSEventListeners':
      return 'JS Event Listeners';
    case 'LayoutCount':
      return 'Layout Count';
    case 'RecalcStyleCount':
      return 'Recalc Style Count';
    default:
      return cdpName;
  }
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
    duration: const Duration(milliseconds: 240),
  );
  late List<double> _from = List<double>.from(widget.values);
  late List<double> _to = List<double>.from(widget.values);

  @override
  void didUpdateWidget(covariant _AnimatedSparkline old) {
    super.didUpdateWidget(old);
    if (!_listEquals(old.values, widget.values)) {
      _from = _resampleTo(_currentValues(), widget.values.length);
      _to = List<double>.from(widget.values);
      if (widget.reduceMotion) {
        _ac.value = 1;
      } else {
        _ac
          ..reset()
          ..animateTo(1, curve: Curves.easeOutCubic);
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

  List<double> _resampleTo(List<double> src, int n) {
    if (src.length == n) return List<double>.from(src);
    if (src.isEmpty) return List<double>.filled(n, 0);
    if (src.length > n) {
      // 缩短：取尾部 n 个，模拟历史窗口左移。
      return src.sublist(src.length - n);
    }
    // 拉长：左侧补首值。
    final pad = List<double>.filled(n - src.length, src.first);
    return [...pad, ...src];
  }

  bool _listEquals(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
  const _LongTasksPane({required this.tasks, required this.isZh});
  final List<Map<String, Object?>> tasks;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isZh ? '长任务（≥50ms 主线程阻塞）' : 'Long Tasks (≥50ms)',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${tasks.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
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
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        isZh
                            ? '暂无长任务。\n刷新页面或交互后此处会实时刷新。'
                            : 'No long tasks yet.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.55,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: tasks.length,
                    itemBuilder: (_, idx) {
                      final t = tasks[tasks.length - 1 - idx];
                      final dur = (t['duration'] as num?)?.toDouble() ?? 0;
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
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${dur.toStringAsFixed(0)} ms',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
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
                                        fontFamily: 'monospace',
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

// ─────────────────────────────────────────────────────────────────────────
// Memory：HeapProfiler.takeHeapSnapshot 拉 .heapsnapshot，导出可用于 DevTools 重放。
// ─────────────────────────────────────────────────────────────────────────

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
    _heapTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _sampleHeap(),
    );
    unawaited(_sampleHeap());
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
    final usedMb = r.used / 1024 / 1024;
    final breached = usedMb > _heapWarnThresholdMb;
    setState(() {
      _heapUsed.add(r.used);
      _heapTotal.add(r.total);
      while (_heapUsed.length > _heapHistoryLen) {
        _heapUsed.removeAt(0);
        _heapTotal.removeAt(0);
      }
      _heapBreached = breached;
    });
    // 触发告警：超过阈值且距上次告警 ≥ 60s 才再次提示。
    if (breached) {
      final now = DateTime.now();
      if (_lastWarnAt == null ||
          now.difference(_lastWarnAt!) > const Duration(seconds: 60)) {
        _lastWarnAt = now;
        if (mounted) {
          final isZh = widget.isZh;
          final cs = Theme.of(context).colorScheme;
          OpenHandSnackBar.show(
            context,
            ScaffoldMessenger.of(context),
            SnackBar(
              backgroundColor: cs.error,
              content: Text(
                isZh
                    ? 'V8 堆已用 ${usedMb.toStringAsFixed(1)} MB，超过阈值 ${_heapWarnThresholdMb.toStringAsFixed(0)} MB'
                    : 'V8 heap ${usedMb.toStringAsFixed(1)} MB exceeds threshold ${_heapWarnThresholdMb.toStringAsFixed(0)} MB',
                style: TextStyle(
                  color: cs.onError,
                  fontWeight: FontWeight.w700,
                ),
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleSampling() async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    if (widget.controller.isMemorySampling) {
      final r = await widget.controller.stopMemorySampling();
      if (!mounted) return;
      setState(() => _samplingResult = r);
      if (r == null) {
        OpenHandSnackBar.showErrorOn(
          context,
          messenger,
          isZh ? '采样收尾失败' : 'Stop sampling failed',
          duration: const Duration(seconds: 2),
        );
      }
    } else {
      final ok = await widget.controller.startMemorySampling();
      if (!mounted) return;
      if (!ok) {
        OpenHandSnackBar.showErrorOn(
          context,
          messenger,
          isZh ? '采样启动失败' : 'Start sampling failed',
          duration: const Duration(seconds: 2),
        );
      } else {
        setState(() => _samplingResult = null);
      }
    }
  }

  Future<void> _capture() async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
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
    if (r == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '快照采集失败' : 'Snapshot failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// 比较 _snapA 与 _snapB：从 .heapsnapshot 头部读 nodes / strings 计数和
  /// total_size，输出节点数 / 字节数差。两份缺一即提示。
  void _compareSnapshots() {
    final isZh = widget.isZh;
    final a = _snapA;
    final b = _snapB;
    if (a == null || b == null) {
      OpenHandSnackBar.showInfo(
        context,
        isZh ? '需要至少两次快照才能比较' : 'Need at least two snapshots',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    int countNodes(String src) {
      try {
        final m = jsonDecode(src) as Map<String, Object?>;
        final snap = m['snapshot'] as Map?;
        return (snap?['node_count'] as num?)?.toInt() ?? 0;
      } catch (_) {
        return 0;
      }
    }

    final nodesA = countNodes(a.json);
    final nodesB = countNodes(b.json);
    final dBytes = b.bytes - a.bytes;
    final dNodes = nodesB - nodesA;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isZh ? '快照比较' : 'Snapshot diff'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('A: ${a.ts.toLocal().toIso8601String().split(".").first}'),
              Text('B: ${b.ts.toLocal().toIso8601String().split(".").first}'),
              const SizedBox(height: 12),
              _DiffRow(
                label: isZh ? '原始字节' : 'Raw bytes',
                a: '${a.bytes}',
                b: '${b.bytes}',
                delta: dBytes,
              ),
              _DiffRow(
                label: isZh ? '节点数' : 'Nodes',
                a: '$nodesA',
                b: '$nodesB',
                delta: dNodes,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(isZh ? '关闭' : 'Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final r = _last;
    if (r == null) return;
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
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
      silentLog(
        'web_reverse_dashboard_dialog',
        'getSaveLocation heap',
        error,
        stack,
      );
    }
    if (location == null) return;
    try {
      await File(location.path).writeAsString(r.json);
      if (!mounted) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? '已保存到 ${location.path}' : 'Saved',
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'write heap',
        error,
        stack,
      );
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '保存失败' : 'Save failed',
        duration: const Duration(seconds: 2),
      );
    }
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
          // ── V8 实时堆使用折线 ─────────────────────────────────────
          _V8HeapLiveCard(
            used: _heapUsed,
            total: _heapTotal,
            isZh: isZh,
            thresholdMb: _heapWarnThresholdMb,
            breached: _heapBreached,
            onThresholdChanged: (v) => setState(() => _heapWarnThresholdMb = v),
          ),
          const SizedBox(height: 12),
          // ── 采样 / 快照工具栏 ──────────────────────────────────────
          Row(
            children: [
              Text(
                isZh ? 'V8 堆快照' : 'V8 Heap Snapshot',
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
                label: Text(_capturing
                    ? (isZh ? '采集中…' : 'Capturing…')
                    : (isZh ? '采集快照' : 'Capture Snapshot')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (_snapA != null && _snapB != null)
                    ? _compareSnapshots
                    : null,
                icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                label: Text(isZh ? '比较快照' : 'Diff snapshots'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _toggleSampling,
                icon: Icon(
                  widget.controller.isMemorySampling
                      ? Icons.stop_circle_rounded
                      : Icons.timeline_rounded,
                  size: 18,
                ),
                label: Text(
                  widget.controller.isMemorySampling
                      ? (isZh ? '停止采样' : 'Stop sampling')
                      : (isZh ? '开始采样' : 'Start sampling'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _last == null ? null : _save,
                icon: const Icon(Icons.save_alt_rounded, size: 18),
                label: Text(isZh ? '保存到文件' : 'Save to File'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_samplingResult != null)
            Expanded(
              child: _SamplingTopList(result: _samplingResult!, isZh: isZh),
            )
          else if (_last != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isZh ? '最近一次快照' : 'Latest Snapshot',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isZh
                        ? '原始大小约 ${(_last!.bytes / 1024 / 1024).toStringAsFixed(2)} MB · 可保存为 .heapsnapshot 后在 Chrome DevTools → Memory → Load 里打开重放。'
                        : '~${(_last!.bytes / 1024 / 1024).toStringAsFixed(2)} MB · save as .heapsnapshot and load it back in Chrome DevTools.',
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
              isZh
                  ? '点击「采集快照」拉一次 V8 堆快照；或「开始采样」做分配采样直到停止后看 Top-N。'
                  : 'Click "Capture Snapshot" to take a heap snapshot, or start sampling for top-N allocation profile.',
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
    required this.isZh,
    required this.thresholdMb,
    required this.breached,
    required this.onThresholdChanged,
  });

  final List<double> used;
  final List<double> total;
  final bool isZh;
  final double thresholdMb;
  final bool breached;
  final ValueChanged<double> onThresholdChanged;

  String _fmt(double v) {
    if (v < 1024) return '${v.toStringAsFixed(0)} B';
    if (v < 1024 * 1024) return '${(v / 1024).toStringAsFixed(1)} KB';
    return '${(v / 1024 / 1024).toStringAsFixed(2)} MB';
  }

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
        borderRadius: BorderRadius.circular(12),
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
                      isZh ? 'V8 堆（实时，1.5s 间隔）' : 'V8 Heap (live, 1.5s)',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (breached) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.warning_amber_rounded,
                          size: 14, color: cs.error),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${isZh ? "已用" : "Used"}: ${_fmt(lastUsed)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: usedColor,
                  ),
                ),
                Text(
                  '${isZh ? "总量" : "Total"}: ${_fmt(lastTotal)}',
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
                      Icon(Icons.tune_rounded,
                          size: 13, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        isZh ? '阈值告警' : 'Threshold',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${thresholdMb.toStringAsFixed(0)} MB',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
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
    duration: const Duration(milliseconds: 240),
  );
  late List<double> _fromPri = List<double>.from(widget.primary);
  late List<double> _toPri = List<double>.from(widget.primary);
  late List<double> _fromSec = List<double>.from(widget.secondary);
  late List<double> _toSec = List<double>.from(widget.secondary);

  @override
  void didUpdateWidget(covariant _AnimatedDualSparkline old) {
    super.didUpdateWidget(old);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    var changed = false;
    if (!_eq(old.primary, widget.primary)) {
      _fromPri = _resampleTo(_curPri(), widget.primary.length);
      _toPri = List<double>.from(widget.primary);
      changed = true;
    }
    if (!_eq(old.secondary, widget.secondary)) {
      _fromSec = _resampleTo(_curSec(), widget.secondary.length);
      _toSec = List<double>.from(widget.secondary);
      changed = true;
    }
    if (changed) {
      if (reduceMotion) {
        _ac.value = 1;
      } else {
        _ac
          ..reset()
          ..animateTo(1, curve: Curves.easeOutCubic);
      }
    }
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  bool _eq(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<double> _resampleTo(List<double> src, int n) {
    if (src.length == n) return List<double>.from(src);
    if (src.isEmpty) return List<double>.filled(n, 0);
    if (src.length > n) return src.sublist(src.length - n);
    final pad = List<double>.filled(n - src.length, src.first);
    return [...pad, ...src];
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

class _SamplingTopList extends StatelessWidget {
  const _SamplingTopList({required this.result, required this.isZh});
  final ({
    int totalSize,
    List<({String label, int size, List<String> stack})> top
  }) result;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isZh ? '采样 Top-N（按 selfSize）' : 'Sampling Top-N (selfSize)',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                isZh
                    ? '总分配 ${(result.totalSize / 1024).toStringAsFixed(1)} KB'
                    : 'Total ${(result.totalSize / 1024).toStringAsFixed(1)} KB',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              itemCount: result.top.length,
              itemBuilder: (_, i) {
                final r = result.top[i];
                final ratio = result.totalSize == 0
                    ? 0.0
                    : r.size / result.totalSize;
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
                              fontFamily: 'monospace',
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
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: ratio.clamp(0.0, 1.0),
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 84,
                          child: Text(
                            '${(r.size / 1024).toStringAsFixed(1)} KB',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
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
    final isZh = this.isZh;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            isZh ? '调用栈：${row.label}' : 'Call stack: ${row.label}',
          ),
          content: SizedBox(
            width: 720,
            height: 420,
            child: row.stack.isEmpty
                ? Center(
                    child: Text(
                      isZh ? '(此节点无父级链)' : '(no parent stack)',
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
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
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                entry,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
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
              onPressed: () {
                Clipboard.setData(ClipboardData(text: row.stack.join('\n')));
                Navigator.of(dialogContext).pop();
                OpenHandSnackBar.showSuccess(
                  context,
                  isZh ? '已复制' : 'Copied',
                  duration: const Duration(seconds: 1),
                );
              },
              label: isZh ? '复制' : 'Copy',
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: isZh ? '关闭' : 'Close',
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Application：Cookies / Local Storage / Session Storage（按 origin 切换）
// ─────────────────────────────────────────────────────────────────────────

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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    final origin = await widget.controller.currentOrigin();
    final tab = _tab;
    List<Map<String, Object?>> cookies = const [];
    List<({String key, String value})> storage = const [];
    List<String> idbNames = const [];
    var idbDescribed =
        const <String, ({int version, List<String> stores})>{};
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
      for (final name in idbNames) {
        final info = await widget.controller.describeIndexedDb(name);
        if (info != null) {
          acc[name] = (version: info.version, stores: info.stores);
        }
      }
      idbDescribed = acc;
    } else if (tab == _AppTab.cacheStorage) {
      cacheNames = await widget.controller.listCacheStorage();
    } else if (tab == _AppTab.serviceWorkers) {
      swVersions = await widget.controller.listServiceWorkers();
    }
    if (!mounted) return;
    setState(() {
      _origin = origin;
      _cookies = cookies;
      _storage = storage;
      _idbNames = idbNames;
      _idbDescribed = idbDescribed;
      _cacheNames = cacheNames;
      _swVersions = swVersions;
      _loading = false;
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
                _AppTabPill(
                  label: _appTabLabel(t, isZh),
                  active: _tab == t,
                  onTap: () {
                    setState(() => _tab = t);
                    _refresh();
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_origin != null)
                Expanded(
                  child: Text(
                    _origin!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              IconButton(
                tooltip: isZh ? '刷新' : 'Refresh',
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: switch (_tab) {
              _AppTab.cookies => _CookiesTable(
                  cookies: _cookies,
                  controller: widget.controller,
                  isZh: isZh,
                  onChanged: _refresh,
                ),
              _AppTab.localStorage ||
              _AppTab.sessionStorage =>
                _StorageTable(
                  rows: _storage,
                  controller: widget.controller,
                  origin: _origin,
                  isLocalStorage: _tab == _AppTab.localStorage,
                  isZh: isZh,
                  onChanged: _refresh,
                ),
              _AppTab.indexedDb => _IndexedDbTable(
                  controller: widget.controller,
                  names: _idbNames,
                  described: _idbDescribed,
                ),
              _AppTab.cacheStorage =>
                _NameListPanel(names: _cacheNames, isZh: isZh),
              _AppTab.serviceWorkers =>
                _ServiceWorkersTable(
                  versions: _swVersions,
                  controller: widget.controller,
                  isZh: isZh,
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

class _AppTabPill extends StatelessWidget {
  const _AppTabPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: active ? cs.primaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kToolbarRadius),
        side: BorderSide(
          color: active
              ? cs.primary.withValues(alpha: 0.4)
              : cs.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_kToolbarRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: active ? cs.onPrimaryContainer : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _CookiesTable extends StatefulWidget {
  const _CookiesTable({
    required this.cookies,
    required this.controller,
    required this.isZh,
    required this.onChanged,
  });
  final List<Map<String, Object?>> cookies;
  final WebReverseSessionController controller;
  final bool isZh;
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

  Future<void> _addCookie() async {
    final saved = await _showCookieEditor(
      context,
      initial: const <String, Object?>{},
      isZh: widget.isZh,
    );
    if (saved == null || !mounted) return;
    final ok = await widget.controller.setCookie(
      name: '${saved['name'] ?? ''}',
      value: '${saved['value'] ?? ''}',
      domain: '${saved['domain'] ?? ''}'.trim().isEmpty
          ? null
          : '${saved['domain']}',
      path: '${saved['path'] ?? ''}'.trim().isEmpty ? null : '${saved['path']}',
    );
    if (ok && mounted) await widget.onChanged();
  }

  Future<void> _editCookie(Map<String, Object?> c) async {
    final saved = await _showCookieEditor(
      context,
      initial: c,
      isZh: widget.isZh,
    );
    if (saved == null || !mounted) return;
    final ok = await widget.controller.setCookie(
      name: '${saved['name'] ?? ''}',
      value: '${saved['value'] ?? ''}',
      domain: '${saved['domain'] ?? ''}'.trim().isEmpty
          ? null
          : '${saved['domain']}',
      path: '${saved['path'] ?? ''}'.trim().isEmpty ? null : '${saved['path']}',
    );
    if (ok && mounted) await widget.onChanged();
  }

  Future<void> _deleteCookie(Map<String, Object?> c) async {
    await widget.controller.deleteCookie(
      name: '${c['name'] ?? ''}',
      domain: '${c['domain'] ?? ''}'.trim().isEmpty
          ? null
          : '${c['domain']}',
      path: '${c['path'] ?? ''}'.trim().isEmpty ? null : '${c['path']}',
    );
    if (mounted) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cookies = widget.cookies;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addCookie,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(widget.isZh ? '新增 cookie' : 'Add cookie'),
          ),
        ),
        Expanded(
          child: cookies.isEmpty
              ? Center(
                  child: Text(
                    '(empty)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
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
                                    _mono(_truncate('${c['value'] ?? ''}', 80))),
                                DataCell(_mono('${c['domain'] ?? ''}')),
                                DataCell(_mono('${c['path'] ?? ''}')),
                                DataCell(_mono(_formatExpires(c['expires']))),
                                DataCell(
                                    Text(c['httpOnly'] == true ? '✓' : '')),
                                DataCell(Text(c['secure'] == true ? '✓' : '')),
                                DataCell(_mono('${c['sameSite'] ?? ''}')),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: widget.isZh ? '编辑' : 'Edit',
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 16,
                                        padding: const EdgeInsets.all(6),
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        onPressed: () => _editCookie(c),
                                        icon: const Icon(Icons.edit_rounded),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        tooltip:
                                            widget.isZh ? '删除' : 'Delete',
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 16,
                                        padding: const EdgeInsets.all(6),
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        onPressed: () => _deleteCookie(c),
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
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      );

  String _truncate(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n)}…';

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
  required bool isZh,
}) async {
  final name = TextEditingController(text: '${initial['name'] ?? ''}');
  final value = TextEditingController(text: '${initial['value'] ?? ''}');
  final domain = TextEditingController(text: '${initial['domain'] ?? ''}');
  final path = TextEditingController(text: '${initial['path'] ?? '/'}');
  final result = await showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => AlertDialog(
      title:
          Text(isZh ? (initial.isEmpty ? '新增 cookie' : '编辑 cookie') : 'Cookie'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: value,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Value'),
            ),
            TextField(
              controller: domain,
              decoration: const InputDecoration(labelText: 'Domain'),
            ),
            TextField(
              controller: path,
              decoration: const InputDecoration(labelText: 'Path'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isZh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(<String, Object?>{
            'name': name.text.trim(),
            'value': value.text,
            'domain': domain.text.trim(),
            'path': path.text.trim(),
          }),
          child: Text(isZh ? '保存' : 'Save'),
        ),
      ],
    ),
  );
  name.dispose();
  value.dispose();
  domain.dispose();
  path.dispose();
  return result;
}

class _StorageTable extends StatefulWidget {
  const _StorageTable({
    required this.rows,
    required this.controller,
    required this.origin,
    required this.isLocalStorage,
    required this.isZh,
    required this.onChanged,
  });

  final List<({String key, String value})> rows;
  final WebReverseSessionController controller;
  final String? origin;
  final bool isLocalStorage;
  final bool isZh;
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
      isZh: widget.isZh,
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
      isZh: widget.isZh,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rows = widget.rows;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.origin == null || widget.origin!.isEmpty
                ? null
                : _add,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(widget.isZh ? '新增条目' : 'Add entry'),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    '(empty)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
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
                                fontFamily: 'monospace',
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
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: widget.isZh ? '编辑' : 'Edit',
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
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: widget.isZh ? '删除' : 'Delete',
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
  required bool isZh,
}) async {
  final keyCtrl = TextEditingController(text: initialKey);
  final valueCtrl = TextEditingController(text: initialValue);
  final result = await showDialog<({String key, String value})>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(isZh ? '存储条目' : 'Storage entry'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyCtrl,
              decoration: const InputDecoration(labelText: 'Key'),
            ),
            TextField(
              controller: valueCtrl,
              maxLines: 6,
              minLines: 2,
              decoration: const InputDecoration(labelText: 'Value'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isZh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            (key: keyCtrl.text.trim(), value: valueCtrl.text),
          ),
          child: Text(isZh ? '保存' : 'Save'),
        ),
      ],
    ),
  );
  keyCtrl.dispose();
  valueCtrl.dispose();
  return result;
}

// ─────────────────────────────────────────────────────────────────────────
// Application 子组件：IndexedDB / Cache Storage / Service Workers
// ─────────────────────────────────────────────────────────────────────────

class _IndexedDbTable extends StatefulWidget {
  const _IndexedDbTable({
    required this.controller,
    required this.names,
    required this.described,
  });

  final WebReverseSessionController controller;
  final List<String> names;
  final Map<String, ({int version, List<String> stores})> described;

  @override
  State<_IndexedDbTable> createState() => _IndexedDbTableState();
}

class _IndexedDbTableState extends State<_IndexedDbTable> {
  /// 当前展开的 (db, store)；null 表示未展开。
  ({String db, String store})? _selected;
  List<Map<String, Object?>> _entries = const [];
  bool _hasMore = false;
  int _skipCount = 0;
  bool _loading = false;

  Future<void> _expand(String db, String store) async {
    if (_loading) return;
    setState(() {
      _selected = (db: db, store: store);
      _entries = const [];
      _skipCount = 0;
      _hasMore = false;
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
      _skipCount = _entries.length;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _selected == null) return;
    setState(() => _loading = true);
    final r = await widget.controller.readIndexedDbStore(
      dbName: _selected!.db,
      storeName: _selected!.store,
      skipCount: _skipCount,
    );
    if (!mounted) return;
    setState(() {
      _entries = [..._entries, ...?r?.entries];
      _hasMore = r?.hasMore ?? false;
      _skipCount = _entries.length;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (widget.names.isEmpty) {
      return Center(
        child: Text('(empty)',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant)),
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
                          Icon(Icons.storage_rounded,
                              size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SelectableText(
                              name,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (info != null)
                            Text(
                              'v${info.version}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontFamily: 'monospace',
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (info != null)
                      for (final s in info.stores)
                        InkWell(
                          onTap: () => _expand(name, s),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            margin: const EdgeInsets.only(left: 22, top: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: selected != null &&
                                      selected.db == name &&
                                      selected.store == s
                                  ? cs.primaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.table_rows_rounded,
                                    size: 12, color: cs.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    s,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
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
              ? Center(
                  child: Text(
                    '点击左侧 store 查看记录',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
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
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '${_entries.length}${_hasMore ? "+" : ""}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_hasMore)
                            TextButton.icon(
                              onPressed: _loading ? null : _loadMore,
                              icon: const Icon(Icons.expand_more_rounded,
                                  size: 16),
                              label: Text(
                                Localizations.localeOf(context)
                                        .languageCode
                                        .startsWith('zh')
                                    ? '加载更多'
                                    : 'Load more',
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _entries.isEmpty && !_loading
                          ? Center(
                              child: Text('(empty)',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  )),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              itemCount:
                                  _entries.length + (_loading ? 1 : 0),
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: cs.outlineVariant,
                              ),
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
  const _IndexedDbEntryRow({required this.entry});
  final Map<String, Object?> entry;

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
                const SizedBox(width: 4),
                SizedBox(
                  width: 200,
                  child: Text(
                    keyDesc,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
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
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 0, 0),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(entry),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// CDP RemoteObject -> 人可读字符串。
  static String _describeRemoteObject(Object? raw) {
    if (raw is! Map) return '${raw ?? ''}';
    final type = raw['type'];
    final desc = raw['description'];
    final value = raw['value'];
    if (desc is String && desc.isNotEmpty) return desc;
    if (value != null) return '$value';
    return '<$type>';
  }
}

class _NameListPanel extends StatelessWidget {
  const _NameListPanel({required this.names, required this.isZh});
  final List<String> names;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (names.isEmpty) {
      return Center(
        child: Text('(empty)',
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      itemCount: names.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.folder_zip_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                names[i],
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
    required this.isZh,
    required this.onChanged,
  });
  final List<Map<String, Object?>> versions;
  final WebReverseSessionController controller;
  final bool isZh;
  final Future<void> Function() onChanged;

  Future<void> _registerNew(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isZh ? '注册 Service Worker' : 'Register SW'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'scopeURL'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(isZh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: Text(isZh ? '注册' : 'Register'),
          ),
        ],
      ),
    );
    ctrl.dispose();
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
            label: Text(isZh ? '注册新 SW' : 'Register new SW'),
          ),
        ),
        Expanded(
          child: versions.isEmpty
              ? Center(
                  child: Text(
                    '(empty)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  itemCount: versions.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: cs.outlineVariant),
                  itemBuilder: (_, i) {
                    final v = versions[i];
                    final status =
                        '${v['runningStatus'] ?? v['status'] ?? ''}';
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
                                  color: status == 'running' ||
                                          status == 'activated'
                                      ? cs.primaryContainer
                                      : cs.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  status.isEmpty ? '?' : status,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SelectableText(
                                  url,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: isZh ? '更新' : 'Update',
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
                                            .updateServiceWorker(scope);
                                        await onChanged();
                                      },
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: isZh ? '卸载' : 'Unregister',
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
                            const SizedBox(height: 4),
                            Text(
                              'scope: $scope',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontFamily: 'monospace',
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

// ─────────────────────────────────────────────────────────────────────────
// Security：Security.securityStateChanged 实时
// ─────────────────────────────────────────────────────────────────────────

class _SecurityPanel extends StatefulWidget {
  const _SecurityPanel({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;

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
    final isZh = widget.isZh;
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
              const SizedBox(width: 8),
              Text(
                isZh ? '当前安全状态：' : 'Current security state: ',
                style: theme.textTheme.titleSmall,
              ),
              Text(
                state ?? (isZh ? '(尚未上报)' : '(no data)'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.controller.securityExplanationsJson ??
                      (isZh
                          ? '尚未收到 explanations。访问任意 https 页面后会自动刷新。'
                          : 'No explanations yet. Visit any https page to populate.'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
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

// ─────────────────────────────────────────────────────────────────────────
// Recorder：注入轻量 init script 录制 click / input / hashchange / popstate
// ─────────────────────────────────────────────────────────────────────────

class _RecorderPanel extends StatefulWidget {
  const _RecorderPanel({
    required this.controller,
    required this.isZh,
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
  final bool isZh;
  final bool reduceMotion;

  @override
  State<_RecorderPanel> createState() => _RecorderPanelState();
}

class _RecorderPanelState extends State<_RecorderPanel> {
  bool _replaying = false;

  Future<void> _save() async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
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
      silentLog(
        'web_reverse_dashboard_dialog',
        'getSaveLocation recorder',
        error,
        stack,
      );
    }
    if (location == null) return;
    try {
      await File(location.path).writeAsString(
        const JsonEncoder.withIndent('  ').convert(steps),
      );
      if (!mounted) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? '已保存到 ${location.path}' : 'Saved',
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'write recorder',
        error,
        stack,
      );
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '保存失败' : 'Save failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _import() async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    const typeGroup = XTypeGroup(label: 'JSON', extensions: <String>['json']);
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [typeGroup]);
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'openFile recorder',
        error,
        stack,
      );
    }
    if (file == null) return;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('not a list');
      final steps = decoded
          .whereType<Map>()
          .map((m) => Map<String, Object?>.from(m))
          .toList(growable: false);
      widget.controller.setRecorderSteps(steps);
      if (!mounted) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? '已导入 ${steps.length} 步' : 'Imported ${steps.length} steps',
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'parse recorder json',
        error,
        stack,
      );
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '导入失败：JSON 格式不合法' : 'Import failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _replay() async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _replaying = true);
    final result = await widget.controller.replaySteps();
    if (!mounted) return;
    setState(() => _replaying = false);
    OpenHandSnackBar.showInfoOn(
      context,
      messenger,
      isZh
          ? '重放完成：${result.executed} 步成功，${result.failed} 步失败'
          : 'Replay done: ${result.executed} ok, ${result.failed} failed',
    );
  }

  /// 把 recorder steps 翻译成 puppeteer / playwright 的 JS 脚本并落盘。
  /// 翻译规则：navigate → page.goto；click → page.click；input → page.type；
  /// change → page.select / page.click 取决于 value 类型；assertText → 等价
  /// 选择器读 textContent 后断言；assertVisible → 等待选择器可见。
  Future<void> _exportAsCode(String kind) async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
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
    } catch (_) {}
    if (!mounted || location == null) return;
    try {
      await File(location.path).writeAsString(code);
      if (!mounted) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? '已保存到 ${location.path}' : 'Saved',
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'export $kind code',
        error,
        stack,
      );
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '保存失败' : 'Save failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  String _renderPuppeteerScript(List<Map<String, Object?>> steps) {
    final buf = StringBuffer()
      ..writeln(
          '// 由 OpenHand Web 逆向 Recorder 自动导出（${DateTime.now().toIso8601String()}）')
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
    final buf = StringBuffer()
      ..writeln(
          '// 由 OpenHand Web 逆向 Recorder 自动导出（${DateTime.now().toIso8601String()}）')
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
                "  await page.click('${esc(selector)}', {clickCount: 2});");
          } else {
            buf.writeln("  await page.click('${esc(selector)}');");
          }
        }
      case 'input':
        if (selector.isNotEmpty && value is String) {
          if (framework == 'puppeteer') {
            buf
              ..writeln("  await page.click('${esc(selector)}', {clickCount: 3});")
              ..writeln("  await page.type('${esc(selector)}', '${esc(value)}');");
          } else {
            buf.writeln("  await page.fill('${esc(selector)}', '${esc(value)}');");
          }
        }
      case 'change':
        if (selector.isEmpty) break;
        if (value is String) {
          if (framework == 'puppeteer') {
            buf.writeln(
                "  await page.select('${esc(selector)}', '${esc(value)}');");
          } else {
            buf.writeln(
                "  await page.selectOption('${esc(selector)}', '${esc(value)}');");
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
                "  await page.waitForFunction((sel, expected) => document.querySelector(sel) && document.querySelector(sel).textContent.includes(expected), {}, '${esc(selector)}', '${esc(expected)}');");
          } else {
            buf.writeln(
                "  await expect(page.locator('${esc(selector)}')).toContainText('${esc(expected)}');");
          }
        }
      case 'assertVisible':
        if (selector.isNotEmpty) {
          if (framework == 'puppeteer') {
            buf.writeln(
                "  await page.waitForSelector('${esc(selector)}', {visible: true});");
          } else {
            buf.writeln(
                "  await expect(page.locator('${esc(selector)}')).toBeVisible();");
          }
        }
    }
  }

  Future<void> _addAssertion(String kind) async {
    final isZh = widget.isZh;
    final selectorCtrl = TextEditingController();
    final expectedCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          kind == 'assertText'
              ? (isZh ? '断言：元素文本包含' : 'Assert: element text contains')
              : (isZh ? '断言：元素可见' : 'Assert: element visible'),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: selectorCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: isZh ? 'CSS 选择器' : 'CSS Selector',
                  hintText: '#login-btn / .header > h1',
                ),
              ),
              if (kind == 'assertText') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: expectedCtrl,
                  decoration: InputDecoration(
                    labelText: isZh ? '期望包含的文本' : 'Expected text',
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: isZh ? '取消' : 'Cancel',
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: isZh ? '添加' : 'Add',
          ),
        ],
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
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
                label: Text(ctrl.isRecording
                    ? (isZh ? '停止录制' : 'Stop')
                    : (isZh ? '开始录制' : 'Record')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed:
                    (steps.isEmpty || ctrl.isRecording || _replaying)
                        ? null
                        : _replay,
                icon: Icon(
                  _replaying
                      ? Icons.hourglass_top_rounded
                      : Icons.play_circle_rounded,
                  size: 18,
                ),
                label: Text(_replaying
                    ? (isZh ? '重放中…' : 'Replaying…')
                    : (isZh ? '重放' : 'Replay')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: steps.isEmpty ? null : _save,
                icon: const Icon(Icons.save_alt_rounded, size: 18),
                label: Text(isZh ? '导出 JSON' : 'Export'),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: isZh ? '导出为代码' : 'Export as code',
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
                  label: Text(isZh ? '导出为代码' : 'Export code'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: ctrl.isRecording ? null : _import,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(isZh ? '导入 JSON' : 'Import'),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: isZh ? '添加断言' : 'Add assertion',
                onSelected: (kind) => _addAssertion(kind),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'assertText',
                    child: Text(isZh ? '断言文本（assertText）' : 'assertText'),
                  ),
                  PopupMenuItem(
                    value: 'assertVisible',
                    child: Text(isZh ? '断言可见（assertVisible）' : 'assertVisible'),
                  ),
                ],
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.rule_rounded, size: 18),
                  label: Text(isZh ? '添加断言' : 'Add assertion'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: isZh ? '清空' : 'Clear',
                onPressed: (steps.isEmpty || ctrl.isRecording)
                    ? null
                    : ctrl.clearRecorderSteps,
                icon: const Icon(Icons.cleaning_services_rounded, size: 18),
              ),
              const Spacer(),
              Text(
                isZh ? '${steps.length} 步' : '${steps.length} steps',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: steps.isEmpty
                ? Center(
                    child: Text(
                      isZh
                          ? '点击「开始录制」后在浏览器中操作页面，事件会按时间序记录。'
                          : 'Click Record then interact with the browser; events log here.',
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '#${idx + 1}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 88,
                                child: Text(
                                  '${s['type'] ?? ''}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  jsonEncode(s),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
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
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              '$a  →  $b',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          Text(
            (delta == 0 ? '0' : (positive ? '+$delta' : '$delta')),
            style: TextStyle(
              fontFamily: 'monospace',
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
/// 解析规则：只挑 ph == 'X'（完整事件）、有 ts + dur 的条目；按 tid 分行
/// 堆叠，按时间轴横向布局；超过 3000 个事件自动抽样到 3000 个保性能。
class _FlameGraphDialog extends StatelessWidget {
  const _FlameGraphDialog({required this.traceJson, required this.isZh});

  final String traceJson;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    List<_FlameEvent> events;
    int minTs;
    int maxTs;
    try {
      final decoded = jsonDecode(traceJson) as Map<String, Object?>;
      final raw = decoded['traceEvents'];
      final list = raw is List ? raw : const <Object?>[];
      var minT = (1 << 62);
      var maxT = -1;
      final all = <_FlameEvent>[];
      for (final item in list.whereType<Map>()) {
        if (item['ph'] != 'X') continue;
        final ts = (item['ts'] as num?)?.toInt();
        final dur = (item['dur'] as num?)?.toInt();
        if (ts == null || dur == null || dur <= 0) continue;
        all.add(_FlameEvent(
          tid: '${item['tid'] ?? '0'}',
          name: '${item['name'] ?? ''}',
          ts: ts,
          dur: dur,
        ));
        if (ts < minT) minT = ts;
        if (ts + dur > maxT) maxT = ts + dur;
      }
      // 抽样：对超长 trace 取等距样本，火焰图依然能反映分布。
      if (all.length > 3000) {
        final step = (all.length / 3000).ceil();
        events = [for (var i = 0; i < all.length; i += step) all[i]];
      } else {
        events = all;
      }
      minTs = minT;
      maxTs = maxT;
    } catch (_) {
      events = const [];
      minTs = 0;
      maxTs = 0;
    }
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isZh
                          ? '火焰图（${events.length} 事件 · ${(maxTs - minTs) / 1000} ms）'
                          : 'Flame graph (${events.length} ev · ${(maxTs - minTs) / 1000} ms)',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: events.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        isZh
                            ? '没有可视化的完整事件（trace 内可能只含 metadata）。'
                            : 'No X-phase events to plot.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  : InteractiveViewer(
                      maxScale: 8,
                      minScale: 0.5,
                      child: SizedBox(
                        width: 1600,
                        height: 480,
                        child: CustomPaint(
                          painter: _FlamePainter(
                            events: events,
                            minTs: minTs,
                            maxTs: maxTs,
                            primary: cs.primary,
                            tertiary: cs.tertiary,
                            onSurface: cs.onSurface,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlameEvent {
  const _FlameEvent({
    required this.tid,
    required this.name,
    required this.ts,
    required this.dur,
  });

  final String tid;
  final String name;
  final int ts;
  final int dur;
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({
    required this.events,
    required this.minTs,
    required this.maxTs,
    required this.primary,
    required this.tertiary,
    required this.onSurface,
  });

  final List<_FlameEvent> events;
  final int minTs;
  final int maxTs;
  final Color primary;
  final Color tertiary;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    if (events.isEmpty) return;
    final span = (maxTs - minTs).toDouble().clamp(1, double.infinity);
    final tidIndex = <String, int>{};
    for (final e in events) {
      tidIndex.putIfAbsent(e.tid, () => tidIndex.length);
    }
    final rowH = size.height / (tidIndex.length).clamp(1, 999);
    for (final e in events) {
      final x = (e.ts - minTs) / span * size.width;
      final w = (e.dur / span * size.width).clamp(1, size.width).toDouble();
      final y = (tidIndex[e.tid] ?? 0) * rowH;
      final h = (rowH - 2).clamp(2.0, double.infinity);
      // 颜色按 dur 长短分级：>50ms 用 tertiary（红橙），其它用 primary。
      final color = e.dur > 50000
          ? tertiary
          : primary.withValues(alpha: 0.55);
      canvas.drawRect(
        Rect.fromLTWH(x, y, w, h),
        Paint()..color = color,
      );
      if (w > 40) {
        final tp = TextPainter(
          text: TextSpan(
            text: e.name,
            style: TextStyle(
              color: onSurface,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          maxLines: 1,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: w - 4);
        tp.paint(canvas, Offset(x + 2, y + 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FlamePainter old) =>
      old.events != events || old.minTs != minTs || old.maxTs != maxTs;
}

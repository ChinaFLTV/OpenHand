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
      messenger.showSnackBar(SnackBar(
        content: Text(isZh ? 'Trace 录制失败' : 'Trace failed'),
        duration: const Duration(seconds: 2),
      ));
      return;
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
      messenger.showSnackBar(SnackBar(
        content: Text(isZh ? 'Trace 已保存到 ${location.path}' : 'Saved'),
        duration: const Duration(seconds: 2),
      ));
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', 'write trace', error, stack);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(isZh ? 'Trace 保存失败' : 'Save failed'),
        duration: const Duration(seconds: 2),
      ));
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
                    child: CustomPaint(
                      painter: _Sparkline(
                        values: _fpsHistory,
                        color: cs.primary,
                        fillBelow: true,
                        upperBound: 60,
                      ),
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
                                  Text(
                                    m.$1,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _formatMetric(m.$1, m.$2),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  SizedBox(
                                    height: 24,
                                    child: CustomPaint(
                                      painter: _Sparkline(
                                        values: history,
                                        color: cs.primary,
                                        fillBelow: true,
                                      ),
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

  Future<void> _capture() async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _capturing = true);
    final r = await widget.controller.takeHeapSnapshot();
    if (!mounted) return;
    setState(() {
      _capturing = false;
      _last = r;
    });
    if (r == null) {
      messenger.showSnackBar(SnackBar(
        content: Text(isZh ? '快照采集失败' : 'Snapshot failed'),
        duration: const Duration(seconds: 2),
      ));
    }
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
      messenger.showSnackBar(SnackBar(
        content: Text(isZh ? '已保存到 ${location.path}' : 'Saved'),
        duration: const Duration(seconds: 2),
      ));
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'write heap',
        error,
        stack,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(isZh ? '保存失败' : 'Save failed'),
        duration: const Duration(seconds: 2),
      ));
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
                onPressed: _last == null ? null : _save,
                icon: const Icon(Icons.save_alt_rounded, size: 18),
                label: Text(isZh ? '保存到文件' : 'Save to File'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_last != null)
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
                  ? '点击「采集快照」从浏览器拉取一次 V8 堆快照（可能需要数秒）。'
                  : 'Click "Capture Snapshot" to take a V8 heap snapshot (a few seconds).',
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
              _AppTab.cookies => _CookiesTable(cookies: _cookies),
              _AppTab.localStorage ||
              _AppTab.sessionStorage =>
                _StorageTable(rows: _storage),
              _AppTab.indexedDb => _IndexedDbTable(
                  controller: widget.controller,
                  names: _idbNames,
                  described: _idbDescribed,
                ),
              _AppTab.cacheStorage =>
                _NameListPanel(names: _cacheNames, isZh: isZh),
              _AppTab.serviceWorkers =>
                _ServiceWorkersTable(versions: _swVersions),
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
  const _CookiesTable({required this.cookies});
  final List<Map<String, Object?>> cookies;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cookies = widget.cookies;
    if (cookies.isEmpty) {
      return Center(
        child: Text('(empty)',
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      );
    }
    return Scrollbar(
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
            ],
            rows: [
              for (final c in cookies)
                DataRow(cells: [
                  DataCell(_mono('${c['name'] ?? ''}')),
                  DataCell(_mono(_truncate('${c['value'] ?? ''}', 80))),
                  DataCell(_mono('${c['domain'] ?? ''}')),
                  DataCell(_mono('${c['path'] ?? ''}')),
                  DataCell(_mono(_formatExpires(c['expires']))),
                  DataCell(Text(c['httpOnly'] == true ? '✓' : '')),
                  DataCell(Text(c['secure'] == true ? '✓' : '')),
                  DataCell(_mono('${c['sameSite'] ?? ''}')),
                ]),
            ],
          ),
        ),
      ),
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

class _StorageTable extends StatelessWidget {
  const _StorageTable({required this.rows});
  final List<({String key, String value})> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (rows.isEmpty) {
      return Center(
        child: Text('(empty)',
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant),
      itemBuilder: (_, i) {
        final r = rows[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
            ],
          ),
        );
      },
    );
  }
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
  const _ServiceWorkersTable({required this.versions});
  final List<Map<String, Object?>> versions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (versions.isEmpty) {
      return Center(
        child: Text('(empty)',
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      );
    }
    return ListView.separated(
      itemCount: versions.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant),
      itemBuilder: (_, i) {
        final v = versions[i];
        final status = '${v['runningStatus'] ?? v['status'] ?? ''}';
        final url = '${v['scriptURL'] ?? ''}';
        final scope = '${v['scopeURL'] ?? ''}';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: status == 'running' || status == 'activated'
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
      messenger.showSnackBar(SnackBar(
        content: Text(isZh ? '已保存到 ${location.path}' : 'Saved'),
        duration: const Duration(seconds: 2),
      ));
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'write recorder',
        error,
        stack,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(isZh ? '保存失败' : 'Save failed'),
        duration: const Duration(seconds: 2),
      ));
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
      messenger.showSnackBar(SnackBar(
        content: Text(isZh ? '已导入 ${steps.length} 步' : 'Imported ${steps.length} steps'),
        duration: const Duration(seconds: 2),
      ));
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'parse recorder json',
        error,
        stack,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(isZh ? '导入失败：JSON 格式不合法' : 'Import failed'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _replay() async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _replaying = true);
    final result = await widget.controller.replaySteps();
    if (!mounted) return;
    setState(() => _replaying = false);
    messenger.showSnackBar(SnackBar(
      content: Text(isZh
          ? '重放完成：${result.executed} 步成功，${result.failed} 步失败'
          : 'Replay done: ${result.executed} ok, ${result.failed} failed'),
      duration: const Duration(seconds: 3),
    ));
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
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(isZh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isZh ? '添加' : 'Add'),
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

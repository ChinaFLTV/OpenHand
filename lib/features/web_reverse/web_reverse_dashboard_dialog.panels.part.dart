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
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _fpsTimer?.cancel();
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
                      final history = _history[m.$1] ?? const <double>[];
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
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

class _CookiesTable extends StatelessWidget {
  const _CookiesTable({required this.cookies});
  final List<Map<String, Object?>> cookies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (cookies.isEmpty) {
      return Center(
        child: Text('(empty)',
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      );
    }
    return Scrollbar(
      child: SingleChildScrollView(
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

class _IndexedDbTable extends StatelessWidget {
  const _IndexedDbTable({required this.names, required this.described});

  final List<String> names;
  final Map<String, ({int version, List<String> stores})> described;

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
    return ListView.separated(
      itemCount: names.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant),
      itemBuilder: (_, i) {
        final name = names[i];
        final info = described[name];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.storage_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SelectableText(
                      name,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (info != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'v${info.version}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              if (info != null && info.stores.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final s in info.stores)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: cs.outlineVariant),
                        ),
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
              ],
            ],
          ),
        );
      },
    );
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

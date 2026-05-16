part of 'web_reverse_dashboard_dialog.dart';

/// Network 资源类型过滤——对标 Chrome DevTools 顶部的 All / Fetch+XHR / JS / CSS
/// / Img / Media / Manifest / WS / Wasm / Doc / Other 按钮组。
///
/// `match` 直接接收一条 entry 的 resourceType（CDP `type`）以及 mimeType，
/// 返回是否命中该过滤项。这样一份过滤规则就能覆盖 Network 列表 + 所有视图统计。
enum _ResourceFilter {
  all,
  fetchXhr,
  doc,
  css,
  js,
  font,
  img,
  media,
  manifest,
  ws,
  wasm,
  other;

  String label(bool isZh) => switch (this) {
        _ResourceFilter.all => isZh ? '全部' : 'All',
        _ResourceFilter.fetchXhr => 'Fetch/XHR',
        _ResourceFilter.doc => isZh ? '文档' : 'Doc',
        _ResourceFilter.css => 'CSS',
        _ResourceFilter.js => 'JS',
        _ResourceFilter.font => isZh ? '字体' : 'Font',
        _ResourceFilter.img => isZh ? '图片' : 'Img',
        _ResourceFilter.media => isZh ? '媒体' : 'Media',
        _ResourceFilter.manifest => 'Manifest',
        _ResourceFilter.ws => 'WS',
        _ResourceFilter.wasm => 'Wasm',
        _ResourceFilter.other => isZh ? '其他' : 'Other',
      };

  bool matches(CdpNetworkEntry e) {
    final t = e.resourceType.toLowerCase();
    final m = (e.mimeType ?? '').toLowerCase();
    return switch (this) {
      _ResourceFilter.all => true,
      _ResourceFilter.fetchXhr => t == 'fetch' || t == 'xhr',
      _ResourceFilter.doc => t == 'document',
      _ResourceFilter.css => t == 'stylesheet',
      _ResourceFilter.js => t == 'script' || m.contains('javascript'),
      _ResourceFilter.font => t == 'font' || m.startsWith('font/'),
      _ResourceFilter.img => t == 'image' || m.startsWith('image/'),
      _ResourceFilter.media =>
        t == 'media' || m.startsWith('audio/') || m.startsWith('video/'),
      _ResourceFilter.manifest => t == 'manifest',
      _ResourceFilter.ws => t == 'websocket' || t == 'eventsource',
      _ResourceFilter.wasm => t == 'wasm' || m.contains('wasm'),
      _ResourceFilter.other => !(<String>[
            'fetch',
            'xhr',
            'document',
            'stylesheet',
            'script',
            'font',
            'image',
            'media',
            'manifest',
            'websocket',
            'eventsource',
            'wasm',
          ]).contains(t),
    };
  }
}

class _NetworkBody extends StatelessWidget {
  const _NetworkBody({
    required this.state,
    required this.controller,
    required this.isZh,
    required this.reduceMotion,
  });

  final _WebReverseDashboardDialogState state;
  final WebReverseSessionController controller;
  final bool isZh;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final all = controller.networkRequests;
    final filterText = state._networkFilter.toLowerCase();
    final resourceFilter = state._resourceFilter;

    bool match(CdpNetworkEntry e) {
      if (!resourceFilter.matches(e)) return false;
      if (filterText.isEmpty) return true;
      return e.url.toLowerCase().contains(filterText) ||
          e.method.toLowerCase().contains(filterText);
    }

    final filtered =
        all.where(match).toList(growable: false);
    final selected = state._selectedRequest;
    final hasSelection =
        selected != null && _networkByIdContains(all, selected.requestId);
    return Column(
      children: [
        if (controller.isFetchInterceptEnabled)
          _PendingFetchBanner(controller: controller, isZh: isZh),
        _ResourceFilterBar(
          value: resourceFilter,
          isZh: isZh,
          onChanged: (v) => state.rebuildFromExternal(() {
            state._resourceFilter = v;
            // 切过滤后选中条目可能被过滤掉，自动收起详情。
            if (state._selectedRequest != null &&
                !v.matches(state._selectedRequest!)) {
              state._selectedRequest = null;
            }
          }),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: hasSelection
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 480,
                      child: _NetworkList(
                        items: filtered,
                        listKey: state._networkListKey,
                        selectedId: selected.requestId,
                        onSelect: (e) =>
                            state.rebuildFromExternal(() => state._selectedRequest = e),
                        onCopyUrl: (e) => _copyUrl(context, e, isZh),
                        reduceMotion: reduceMotion,
                        isZh: isZh,
                      ),
                    ),
                    VerticalDivider(width: 1, color: cs.outlineVariant),
                    Expanded(
                      child: _RequestDetailPanel(
                        controller: controller,
                        entry: selected,
                        isZh: isZh,
                        reduceMotion: reduceMotion,
                        onClose: () =>
                            state.rebuildFromExternal(() => state._selectedRequest = null),
                      ),
                    ),
                  ],
                )
              : _NetworkList(
                  items: filtered,
                  listKey: state._networkListKey,
                  selectedId: null,
                  onSelect: (e) =>
                      state.rebuildFromExternal(() => state._selectedRequest = e),
                  onCopyUrl: (e) => _copyUrl(context, e, isZh),
                  reduceMotion: reduceMotion,
                  isZh: isZh,
                ),
        ),
      ],
    );
  }

  bool _networkByIdContains(List<CdpNetworkEntry> all, String id) {
    for (final e in all) {
      if (e.requestId == id) return true;
    }
    return false;
  }

  void _copyUrl(BuildContext context, CdpNetworkEntry e, bool isZh) {
    Clipboard.setData(ClipboardData(text: e.url));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isZh ? '已复制 URL' : 'URL copied'),
      duration: const Duration(seconds: 1),
    ));
  }
}

/// 资源类型过滤栏：水平滚动的胶囊组。
class _ResourceFilterBar extends StatelessWidget {
  const _ResourceFilterBar({
    required this.value,
    required this.isZh,
    required this.onChanged,
  });

  final _ResourceFilter value;
  final bool isZh;
  final ValueChanged<_ResourceFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: 38,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            for (final f in _ResourceFilter.values) ...[
              _FilterChipPill(
                label: f.label(isZh),
                active: f == value,
                onTap: () => onChanged(f),
                theme: theme,
                cs: cs,
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChipPill extends StatelessWidget {
  const _FilterChipPill({
    required this.label,
    required this.active,
    required this.onTap,
    required this.theme,
    required this.cs,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final ThemeData theme;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: active ? cs.onPrimaryContainer : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkList extends StatelessWidget {
  const _NetworkList({
    required this.items,
    required this.listKey,
    required this.selectedId,
    required this.onSelect,
    required this.onCopyUrl,
    required this.reduceMotion,
    required this.isZh,
  });

  final List<CdpNetworkEntry> items;
  final GlobalKey<AnimatedListState> listKey;
  final String? selectedId;
  final ValueChanged<CdpNetworkEntry> onSelect;
  final ValueChanged<CdpNetworkEntry> onCopyUrl;
  final bool reduceMotion;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            isZh
                ? '暂无网络请求。在浏览器中操作页面后此处会实时刷新。'
                : 'No network requests yet. Interact with the page to populate this view.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    // 计算 Waterfall 时间窗：取列表中最早的 timestamp 与最晚的 finishedAt 作为
    // 总轴；不足 200ms 时强制拉到 200ms 避免短请求条带塌缩。
    final earliest = items
        .map((e) => e.timestamp)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final latest = items.fold<DateTime>(earliest, (acc, e) {
      final tail = e.loadingFinishedAt ?? e.responseReceivedAt ?? e.timestamp;
      return tail.isAfter(acc) ? tail : acc;
    });
    var totalMs = latest.difference(earliest).inMilliseconds;
    if (totalMs < 200) totalMs = 200;
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (_, idx) {
        final e = items[items.length - 1 - idx];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _AnimatedAppearOnce(
            duration: reduceMotion ? Duration.zero : _kSwitchDuration,
            child: _NetworkRow(
              entry: e,
              earliest: earliest,
              totalMs: totalMs,
              selected: e.requestId == selectedId,
              onTap: () => onSelect(e),
              onCopyUrl: () => onCopyUrl(e),
            ),
          ),
        );
      },
    );
  }
}

/// 仅在第一次构建时做 fade+slide 入场，后续 rebuild 不再播。
/// 用于列表项滚入视口时的丝滑感，不会因 list rebuild 抖动。
class _AnimatedAppearOnce extends StatefulWidget {
  const _AnimatedAppearOnce({
    required this.child,
    required this.duration,
  });

  final Widget child;
  final Duration duration;

  @override
  State<_AnimatedAppearOnce> createState() => _AnimatedAppearOnceState();
}

class _AnimatedAppearOnceState extends State<_AnimatedAppearOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
      AnimationController(vsync: this, duration: widget.duration)..forward();

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.duration == Duration.zero) return widget.child;
    return FadeTransition(
      opacity: CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic),
        ),
        child: widget.child,
      ),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.entry,
    required this.earliest,
    required this.totalMs,
    required this.selected,
    required this.onTap,
    required this.onCopyUrl,
  });

  final CdpNetworkEntry entry;
  final DateTime earliest;
  final int totalMs;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onCopyUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = selected
        ? cs.primaryContainer
        : entry.isError
            ? cs.errorContainer
            : (entry.statusCode != null && entry.statusCode! >= 300
                ? cs.tertiaryContainer
                : cs.surfaceContainerHigh);
    final onColor = selected
        ? cs.onPrimaryContainer
        : entry.isError
            ? cs.onErrorContainer
            : (entry.statusCode != null && entry.statusCode! >= 300
                ? cs.onTertiaryContainer
                : cs.onSurface);
    final fileName = _extractFileName(entry.url);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onCopyUrl,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  entry.method,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: onColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  entry.statusCode?.toString() ??
                      (entry.failed ? 'ERR' : '...'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: onColor,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  entry.resourceType,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: onColor.withValues(alpha: 0.75),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: onColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Waterfall：宽 140，按整窗 totalMs 推算条带 left/width。
              Expanded(
                flex: 2,
                child: _Waterfall(
                  entry: entry,
                  earliest: earliest,
                  totalMs: totalMs,
                  selected: selected,
                ),
              ),
              if (entry.fromCache)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.cached_rounded,
                    size: 14,
                    color: onColor.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _extractFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments;
      if (segs.isNotEmpty && segs.last.isNotEmpty) {
        final qs = uri.hasQuery ? '?${uri.query}' : '';
        return '${segs.last}$qs';
      }
      return uri.host;
    } catch (_) {
      return url;
    }
  }
}

/// Waterfall 单行：用两段条带表示「请求—响应」「响应—结束」两个时间区间。
/// 颜色随选中态切换；总轴长度由父级算好的 totalMs 控制。
class _Waterfall extends StatelessWidget {
  const _Waterfall({
    required this.entry,
    required this.earliest,
    required this.totalMs,
    required this.selected,
  });

  final CdpNetworkEntry entry;
  final DateTime earliest;
  final int totalMs;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final start = entry.timestamp.difference(earliest).inMilliseconds;
    final mid = (entry.responseReceivedAt ?? entry.loadingFinishedAt ?? entry.timestamp)
        .difference(earliest)
        .inMilliseconds;
    final end = (entry.loadingFinishedAt ?? entry.responseReceivedAt ?? entry.timestamp)
        .difference(earliest)
        .inMilliseconds;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        if (w <= 0 || totalMs <= 0) return const SizedBox.shrink();
        double xOf(int ms) => (ms.clamp(0, totalMs) / totalMs) * w;
        final leftX = xOf(start);
        final midX = xOf(mid);
        final endX = xOf(end);
        final waitW = (midX - leftX).clamp(2.0, w);
        final downloadW = (endX - midX).clamp(0.0, w);
        return SizedBox(
          height: 16,
          child: Stack(
            children: [
              Positioned(
                left: leftX,
                top: 5,
                child: Container(
                  width: waitW,
                  height: 6,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.onPrimaryContainer.withValues(alpha: 0.7)
                        : cs.primary.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (downloadW > 0)
                Positioned(
                  left: midX,
                  top: 5,
                  child: Container(
                    width: downloadW,
                    height: 6,
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.onPrimaryContainer
                          : cs.tertiary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(3),
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


/// 拦截模式横幅：列出待决策请求 + 全部放行/逐条 abort。
/// 仅在 controller.isFetchInterceptEnabled 时显示。
class _PendingFetchBanner extends StatelessWidget {
  const _PendingFetchBanner({required this.controller, required this.isZh});

  final WebReverseSessionController controller;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pending = controller.pendingFetchRequests;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.55),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.block_rounded, size: 16, color: cs.onTertiaryContainer),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isZh
                  ? '请求拦截已启用：${pending.length} 个请求待决策（点击下方继续/中止）。'
                  : 'Request intercept on: ${pending.length} pending.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (pending.isNotEmpty) ...[
            FilledButton.tonal(
              onPressed: controller.continueAllFetch,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(isZh ? '全部放行' : 'Continue all'),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: isZh ? '查看待决策请求' : 'Pending requests',
              icon: const Icon(Icons.list_alt_rounded, size: 18),
              itemBuilder: (_) => [
                for (final p in pending.take(20))
                  PopupMenuItem(
                    value: p.requestId,
                    onTap: () => _showActions(context, p),
                    child: Text(
                      '${p.method} ${p.url}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showActions(
    BuildContext context,
    ({String requestId, String method, String url}) p,
  ) {
    Future.microtask(() async {
      if (!context.mounted) return;
      final isZh = this.isZh;
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(isZh ? '处理拦截请求' : 'Handle intercepted request'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p.method} ${p.url}',
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('Aborted'),
              child: Text(isZh ? '中止 (Aborted)' : 'Abort'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop('AccessDenied'),
              child: const Text('AccessDenied'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop('TimedOut'),
              child: const Text('TimedOut'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('continue'),
              child: Text(isZh ? '继续' : 'Continue'),
            ),
          ],
        ),
      );
      if (action == null) return;
      if (action == 'continue') {
        await controller.continueFetchRequest(p.requestId);
      } else {
        await controller.abortFetchRequest(p.requestId, reason: action);
      }
    });
  }
}

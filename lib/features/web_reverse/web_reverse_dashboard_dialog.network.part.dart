part of 'web_reverse_dashboard_dialog.dart';

const double _kReplayResultDialogWidth = 640;
const double _kReplayResultDialogHeight = 360;
const double _kNetworkMethodColumnWidth = 78;
const double _kNetworkStatusColumnWidth = 48;
const double _kNetworkTypeColumnWidth = 88;
const Duration _kReplaySnackBarDuration = Duration(seconds: 2);
const Duration _kReplayCopySnackBarDuration = Duration(seconds: 1);

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

    final filtered = all.where(match).toList(growable: false);
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
          // 2026-05-17 — 详情面板进出动画：用 AnimatedSwitcher 把"列表
          // 独占" 与 "列表 + 详情" 两种 layout 之间的切换包裹起来，
          // 详情侧从右滑入并淡入；关闭时反向滑出。同时面板宽度由
          // AnimatedSize 缓动，避免直接 size jump 导致的视觉硬切。
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final fade = FadeTransition(opacity: animation, child: child);
              if (child.key == const ValueKey<String>('with-detail')) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: fade,
                );
              }
              return fade;
            },
            child: hasSelection
                ? ResizableSplitter(
                    key: const ValueKey<String>('with-detail'),
                    initialLeftFraction: 0.4,
                    minLeft: 320,
                    minRight: 360,
                    left: _NetworkList(
                      items: filtered,
                      listKey: state._networkListKey,
                      selectedId: selected.requestId,
                      onSelect: (e) => state.rebuildFromExternal(
                        () => state._selectedRequest = e,
                      ),
                      onCopyUrl: (e) => _copyUrl(context, e, isZh),
                      controller: controller,
                      reduceMotion: reduceMotion,
                      isZh: isZh,
                    ),
                    right: _RequestDetailPanel(
                      controller: controller,
                      entry: selected,
                      isZh: isZh,
                      reduceMotion: reduceMotion,
                      onClose: () => state.rebuildFromExternal(
                        () => state._selectedRequest = null,
                      ),
                    ),
                  )
                : _NetworkList(
                    key: const ValueKey<String>('list-only'),
                    items: filtered,
                    listKey: state._networkListKey,
                    selectedId: null,
                    onSelect: (e) => state.rebuildFromExternal(
                      () => state._selectedRequest = e,
                    ),
                    onCopyUrl: (e) => _copyUrl(context, e, isZh),
                    controller: controller,
                    reduceMotion: reduceMotion,
                    isZh: isZh,
                  ),
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

  Future<void> _copyUrl(
    BuildContext context,
    CdpNetworkEntry e,
    bool isZh,
  ) async {
    final copied = await setWebReverseClipboardText(e.url);
    if (!context.mounted) return;
    OpenHandSnackBar.showSuccess(
      context,
      webReverseClipboardSnackMessage(
        isZh: isZh,
        base: isZh ? '已复制 URL' : 'URL copied',
        result: copied,
      ),
      duration: const Duration(seconds: 1),
    );
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
          color: active ? cs.primary.withValues(alpha: 0.4) : cs.outlineVariant,
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
    super.key,
    required this.items,
    required this.listKey,
    required this.selectedId,
    required this.onSelect,
    required this.onCopyUrl,
    required this.controller,
    required this.reduceMotion,
    required this.isZh,
  });

  final List<CdpNetworkEntry> items;
  final GlobalKey<AnimatedListState> listKey;
  final String? selectedId;
  final ValueChanged<CdpNetworkEntry> onSelect;
  final ValueChanged<CdpNetworkEntry> onCopyUrl;
  final WebReverseSessionController controller;
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
              controller: controller,
              isZh: isZh,
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
  const _AnimatedAppearOnce({required this.child, required this.duration});

  final Widget child;
  final Duration duration;

  @override
  State<_AnimatedAppearOnce> createState() => _AnimatedAppearOnceState();
}

class _AnimatedAppearOnceState extends State<_AnimatedAppearOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.duration == Duration.zero) return widget.child;
    // Q 弹入场：Fade + Slide(easeOutBack 微回弹) + Scale(0.96 → 1)。
    // 既覆盖 Network / Console 等条目卡片的「出现」动效，又把过去的纯
    // easeOutCubic 升级为带轻微弹簧的曲线，让条目堆叠时更生动。
    final fade = CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic);
    final pop = CurvedAnimation(parent: _ac, curve: Curves.easeOutBack);
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(pop),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(pop),
          child: widget.child,
        ),
      ),
    );
  }
}

class _NetworkMetaCell extends StatelessWidget {
  const _NetworkMetaCell({
    required this.width,
    required this.text,
    required this.style,
  });

  final double width;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: style,
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
    required this.controller,
    required this.isZh,
  });

  final CdpNetworkEntry entry;
  final DateTime earliest;
  final int totalMs;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onCopyUrl;
  final WebReverseSessionController controller;
  final bool isZh;

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
    final blocked = controller.blockedUrls.contains(entry.url);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onCopyUrl,
        onSecondaryTapUp: (d) => _showRowMenu(context, d.globalPosition),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              _NetworkMetaCell(
                width: _kNetworkMethodColumnWidth,
                text: entry.method,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: onColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _NetworkMetaCell(
                width: _kNetworkStatusColumnWidth,
                text:
                    entry.statusCode?.toString() ??
                    (entry.failed ? 'ERR' : '...'),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: onColor,
                ),
              ),
              _NetworkMetaCell(
                width: _kNetworkTypeColumnWidth,
                text: entry.resourceType,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: onColor.withValues(alpha: 0.75),
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
              if (blocked)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: isZh ? '已屏蔽' : 'Blocked',
                    child: Icon(Icons.block_rounded, size: 14, color: cs.error),
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

  Future<void> _showRowMenu(BuildContext context, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final blocked = controller.blockedUrls.contains(entry.url);
    final messenger = ScaffoldMessenger.of(context);
    final selected = await showAnimatedMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'copy_url',
          child: Row(
            children: [
              const Icon(Icons.link_rounded, size: 16),
              const SizedBox(width: 8),
              Text(isZh ? '复制 URL' : 'Copy URL'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_curl',
          child: Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 16),
              const SizedBox(width: 8),
              Text(isZh ? '复制为 cURL' : 'Copy as cURL'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_fetch',
          child: Row(
            children: [
              const Icon(Icons.code_rounded, size: 16),
              const SizedBox(width: 8),
              Text(isZh ? '复制为 fetch' : 'Copy as fetch'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'replay',
          child: Row(
            children: [
              const Icon(Icons.replay_rounded, size: 16),
              const SizedBox(width: 8),
              Text(isZh ? '重放此请求' : 'Replay XHR'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'replayEdit',
          child: Row(
            children: [
              const Icon(Icons.edit_note_rounded, size: 16),
              const SizedBox(width: 8),
              Text(isZh ? '编辑后重放（改 URL / Header）' : 'Edit & replay'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (blocked)
          PopupMenuItem(
            value: 'unblock',
            child: Row(
              children: [
                const Icon(Icons.lock_open_rounded, size: 16),
                const SizedBox(width: 8),
                Text(isZh ? '取消屏蔽该 URL' : 'Unblock URL'),
              ],
            ),
          )
        else
          PopupMenuItem(
            value: 'block',
            child: Row(
              children: [
                const Icon(Icons.block_rounded, size: 16),
                const SizedBox(width: 8),
                Text(isZh ? '屏蔽此 URL' : 'Block this URL'),
              ],
            ),
          ),
      ],
    );
    if (selected == null || !context.mounted) return;
    switch (selected) {
      case 'copy_url':
        final copied = await setWebReverseClipboardText(entry.url);
        if (!context.mounted) return;
        OpenHandSnackBar.showSuccessOn(
          context,
          messenger,
          webReverseClipboardSnackMessage(
            isZh: isZh,
            base: isZh ? '已复制 URL' : 'URL copied',
            result: copied,
          ),
          duration: const Duration(seconds: 1),
        );
      case 'copy_curl':
        final copied = await setWebReverseClipboardText(
          _asCurl(entry, windows: false),
        );
        if (!context.mounted) return;
        OpenHandSnackBar.showSuccessOn(
          context,
          messenger,
          webReverseClipboardSnackMessage(
            isZh: isZh,
            base: isZh ? '已复制 cURL' : 'cURL copied',
            result: copied,
          ),
          duration: const Duration(seconds: 1),
        );
      case 'copy_fetch':
        final copied = await setWebReverseClipboardText(
          _asFetch(entry, node: false),
        );
        if (!context.mounted) return;
        OpenHandSnackBar.showSuccessOn(
          context,
          messenger,
          webReverseClipboardSnackMessage(
            isZh: isZh,
            base: isZh ? '已复制 fetch' : 'fetch copied',
            result: copied,
          ),
          duration: const Duration(seconds: 1),
        );
      case 'block':
        await controller.blockUrl(entry.url);
        if (!context.mounted) return;
        OpenHandSnackBar.showInfoOn(
          context,
          messenger,
          isZh ? '已屏蔽该 URL' : 'URL blocked',
          duration: const Duration(seconds: 2),
        );
      case 'unblock':
        await controller.unblockUrl(entry.url);
        if (!context.mounted) return;
        OpenHandSnackBar.showInfoOn(
          context,
          messenger,
          isZh ? '已取消屏蔽' : 'URL unblocked',
          duration: const Duration(seconds: 2),
        );
      case 'replay':
        if (!context.mounted) return;
        await _replayAndShow(context);
      case 'replayEdit':
        if (!context.mounted) return;
        await _replayWithOverridesAndShow(context);
    }
  }

  Future<void> _replayWithOverridesAndShow(BuildContext context) async {
    final overrides =
        await showWebReverseToolDialog<
          ({String url, Map<String, String> headers})
        >(
          context: context,
          builder: (_) => _ReplayOverrideEditor(entry: entry, isZh: isZh),
        );
    if (overrides == null || !context.mounted) return;
    await _runReplayAndShow(
      context,
      overrideUrl: overrides.url,
      overrideHeaders: overrides.headers,
    );
  }

  Future<void> _replayAndShow(BuildContext context) async {
    await _runReplayAndShow(context);
  }

  Future<void> _runReplayAndShow(
    BuildContext context, {
    String? overrideUrl,
    Map<String, String>? overrideHeaders,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await _replayRequestWithLoading(
      context,
      overrideUrl: overrideUrl,
      overrideHeaders: overrideHeaders,
    );
    if (!context.mounted) return;
    if (result == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '重放失败' : 'Replay failed',
        duration: _kReplaySnackBarDuration,
      );
      return;
    }
    await _showReplayResultDialog(context, messenger, result);
  }

  Future<({int status, String body})?> _replayRequestWithLoading(
    BuildContext context, {
    String? overrideUrl,
    Map<String, String>? overrideHeaders,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showOpenHandLoadingDialog(
        context: context,
        message: isZh ? '重放中...' : 'Replaying...',
      ),
    );
    try {
      return await controller.replayRequest(
        entry,
        overrideUrl: overrideUrl,
        overrideHeaders: overrideHeaders,
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'replay network row',
        error,
        stack,
      );
      return null;
    } finally {
      if (navigator.mounted) {
        navigator.pop();
      }
    }
  }

  Future<void> _showReplayResultDialog(
    BuildContext context,
    ScaffoldMessengerState messenger,
    ({int status, String body}) result,
  ) {
    final body = result.body;
    final bodyText = body.isEmpty ? (isZh ? '(响应体为空)' : '(empty body)') : body;
    return showWebReverseToolDialog<void>(
      context: context,
      builder: (dialogContext) => buildOpenHandAlertDialog(
        title: Text(
          isZh
              ? '重放结果（HTTP ${result.status}）'
              : 'Replay (HTTP ${result.status})',
        ),
        content: SizedBox(
          width: _kReplayResultDialogWidth,
          height: _kReplayResultDialogHeight,
          child: SingleChildScrollView(
            child: SelectableText(
              bodyText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () async {
              final copied = await setWebReverseClipboardText(body);
              if (!dialogContext.mounted) return;
              OpenHandSnackBar.showSuccessOn(
                dialogContext,
                messenger,
                webReverseClipboardSnackMessage(
                  isZh: isZh,
                  base: isZh ? '响应体已复制' : 'Body copied',
                  result: copied,
                ),
                duration: _kReplayCopySnackBarDuration,
              );
            },
            label: isZh ? '复制响应体' : 'Copy body',
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: isZh ? '关闭' : 'Close',
          ),
        ],
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
    final mid =
        (entry.responseReceivedAt ?? entry.loadingFinishedAt ?? entry.timestamp)
            .difference(earliest)
            .inMilliseconds;
    final end =
        (entry.loadingFinishedAt ?? entry.responseReceivedAt ?? entry.timestamp)
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
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
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
            AnimatedPopupMenuButton<String>(
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
      final action = await showWebReverseToolDialog<String>(
        context: context,
        builder: (dialogContext) => buildOpenHandAlertDialog(
          title: Text(isZh ? '处理拦截请求' : 'Handle intercepted request'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.method} ${p.url}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop('Aborted'),
              label: isZh ? '中止' : 'Abort',
            ),
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop('AccessDenied'),
              label: 'AccessDenied',
            ),
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop('TimedOut'),
              label: 'TimedOut',
            ),
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop('edit'),
              label: isZh ? '修改放行' : 'Modify & continue',
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop('continue'),
              label: isZh ? '继续' : 'Continue',
            ),
          ],
        ),
      );
      if (action == null || !context.mounted) return;
      if (action == 'continue') {
        await controller.continueFetchRequest(p.requestId);
      } else if (action == 'edit') {
        await _showEditDialog(context, p);
      } else {
        await controller.abortFetchRequest(p.requestId, reason: action);
      }
    });
  }

  Future<void> _showEditDialog(
    BuildContext context,
    ({String requestId, String method, String url}) p,
  ) async {
    final isZh = this.isZh;
    final urlCtrl = TextEditingController(text: p.url);
    final methodCtrl = TextEditingController(text: p.method);
    final headersCtrl = TextEditingController(); // 一行 key:value
    final bodyCtrl = TextEditingController();
    try {
      final result = await showOpenHandFormDialog<bool>(
        context: context,
        title: isZh ? '修改请求后放行' : 'Modify and continue',
        submitLabel: isZh ? '放行' : 'Send',
        cancelLabel: isZh ? '取消' : 'Cancel',
        maxWidth: 560,
        onSubmit: (_) => true,
        contentBuilder: (_) => SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(labelText: 'URL'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: methodCtrl,
                  decoration: const InputDecoration(labelText: 'Method'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: headersCtrl,
                  maxLines: 6,
                  minLines: 3,
                  decoration: InputDecoration(
                    labelText: isZh
                        ? 'Headers（每行 Key: Value，留空则保持原样）'
                        : 'Headers (Key: Value per line; empty = keep original)',
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 6,
                  minLines: 3,
                  decoration: InputDecoration(
                    labelText: isZh
                        ? 'Body（留空则保持原样）'
                        : 'Body (empty = keep original)',
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
      if (result != true) return;
      final headersRaw = headersCtrl.text.trim();
      final headers = headersRaw.isEmpty ? null : _parseHeaderLines(headersRaw);
      final body = bodyCtrl.text;
      final bodyB64 = body.isEmpty ? null : base64Encode(utf8.encode(body));
      await controller.continueFetchRequestEdited(
        p.requestId,
        url: nullIfBlank(urlCtrl.text),
        method: nullIfBlank(methodCtrl.text),
        headers: headers,
        postDataBase64: bodyB64,
      );
    } finally {
      urlCtrl.dispose();
      methodCtrl.dispose();
      headersCtrl.dispose();
      bodyCtrl.dispose();
    }
  }
}

/// 编辑后重放对话框：直接复刻 _InterceptRuleEditor 的字段设计（URL +
/// header overrides），让用户先 rewrite 再 replay 一次单条请求；与拦截规则
/// editor 行为一致，区别在 block 路径不暴露（重放只关心 url / headers）。
class _ReplayOverrideEditor extends StatefulWidget {
  const _ReplayOverrideEditor({required this.entry, required this.isZh});

  final CdpNetworkEntry entry;
  final bool isZh;

  @override
  State<_ReplayOverrideEditor> createState() => _ReplayOverrideEditorState();
}

class _ReplayOverrideEditorState extends State<_ReplayOverrideEditor> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _headersCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.entry.url);
    _headersCtrl = TextEditingController(
      text: _formatHeaderLines(widget.entry.requestHeaders),
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _headersCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isZh = widget.isZh;
    return buildOpenHandDialogFormShell(
      context: context,
      title: isZh ? '编辑后重放' : 'Edit & replay',
      maxWidth: 600,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlCtrl,
              decoration: InputDecoration(labelText: isZh ? '重放 URL' : 'URL'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _headersCtrl,
              maxLines: 8,
              minLines: 4,
              decoration: InputDecoration(
                labelText: isZh
                    ? 'Request Headers（每行 Key: Value，留空保留原值）'
                    : 'Request headers (Key: Value per line)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '取消' : 'Cancel',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            Navigator.of(context).pop((
              url: _urlCtrl.text.trim(),
              headers: _parseHeaderLines(_headersCtrl.text),
            ));
          },
          label: isZh ? '重放' : 'Replay',
        ),
      ],
    );
  }
}

// 「实时」面板 —— WebSocket / EventSource 全局聚合视图。
// 左侧：当前会话所有 WebSocket / EventSource 连接列表（按最近一次帧时间倒序）。
// 右侧：选中连接的帧流，支持方向过滤（sent / received / error）、
// 子串过滤、自动滚到最新帧、复制载荷。
// 数据源：controller.networkRequests 中 isWebSocket=true 的条目。controller 已
// 自动把 CDP `Network.webSocketCreated/FrameSent/FrameReceived/FrameError` 写
// 进对应 entry.wsFrames（上限 2000 条 LRU）。
// 风格：圆角胶囊 + 220ms easeOutCubic + 遵守 MediaQuery.disableAnimationsOf。

part of 'web_reverse_dashboard_dialog.dart';

class _RealtimeBody extends StatefulWidget {
  const _RealtimeBody({required this.controller});
  final WebReverseSessionController controller;

  @override
  State<_RealtimeBody> createState() => _RealtimeBodyState();
}

class _RealtimeBodyState extends State<_RealtimeBody> {
  String? _selectedReqId;
  String _filter = '';
  final Set<CdpWebSocketDirection> _dirFilter = {
    CdpWebSocketDirection.sent,
    CdpWebSocketDirection.received,
    CdpWebSocketDirection.error,
  };
  bool _autoFollow = true;
  final ScrollController _scroll = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  CdpWebSocketFrame? _lastFrame;
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted || _updateScheduled) return;
    _updateScheduled = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (!mounted || !_autoFollow || _selectedReqId == null) return;
      final entry = _selectedEntry();
      final latest = entry == null || entry.wsFrames.isEmpty
          ? null
          : entry.wsFrames.last;
      if (latest == null || identical(latest, _lastFrame)) return;
      _lastFrame = latest;
      _scrollGuard.followToBottom(_scroll, animated: true);
    });
  }

  List<CdpNetworkEntry> _wsEntries() {
    final out = <CdpNetworkEntry>[];
    for (final e in widget.controller.networkRequests) {
      if (e.isWebSocket) out.add(e);
    }
    out.sort((a, b) {
      final at = a.wsFrames.isEmpty ? a.timestamp : a.wsFrames.last.timestamp;
      final bt = b.wsFrames.isEmpty ? b.timestamp : b.wsFrames.last.timestamp;
      return bt.compareTo(at);
    });
    return out;
  }

  CdpNetworkEntry? _selectedEntry() {
    final id = _selectedReqId;
    if (id == null) return null;
    for (final e in widget.controller.networkRequests) {
      if (e.requestId == id) return e;
    }
    return null;
  }

  String _dirLabel(CdpWebSocketDirection d, AppLocalizations? loc) {
    switch (d) {
      case CdpWebSocketDirection.sent:
        return loc?.webReverseRealtimeDirSent ?? 'Sent';
      case CdpWebSocketDirection.received:
        return loc?.webReverseRealtimeDirRecv ?? 'Recv';
      case CdpWebSocketDirection.error:
        return loc?.webReverseRealtimeDirError ?? 'Error';
    }
  }

  IconData _dirIcon(CdpWebSocketDirection d) {
    switch (d) {
      case CdpWebSocketDirection.sent:
        return Icons.north_east_rounded;
      case CdpWebSocketDirection.received:
        return Icons.south_west_rounded;
      case CdpWebSocketDirection.error:
        return Icons.error_outline_rounded;
    }
  }

  Color _dirColor(CdpWebSocketDirection d, ColorScheme cs) {
    switch (d) {
      case CdpWebSocketDirection.sent:
        return cs.tertiary;
      case CdpWebSocketDirection.received:
        return cs.primary;
      case CdpWebSocketDirection.error:
        return cs.error;
    }
  }

  Future<void> _copyFrame(CdpWebSocketFrame f) async {
    await copyWebReverseTextToClipboard(
      context: context,
      text: f.payload,
      successBase:
          AppLocalizations.of(context)?.webReverseRealtimePayloadCopied ??
          'Payload copied',
      logTag: 'web_reverse_realtime_panel',
      logAction: '复制帧数据',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final entries = _wsEntries();
    final selected = _selectedEntry();
    final reduceMotion = !_wrMotionEnabled(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧：连接列表
          SizedBox(
            width: 320,
            child: Container(
              decoration: webReverseSurfaceCardDecoration(cs, radius: 16),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_rounded, size: 16, color: cs.primary),
                        kOpenHandHGap8,
                        Expanded(
                          child: Text(
                            loc?.webReverseRealtimeTitle ?? 'Realtime',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${entries.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        kOpenHandHGap8,
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: entries.isEmpty
                        ? OpenHandInlineEmptyState(
                            message:
                                loc?.webReverseRealtimeEmpty ??
                                'No WebSocket / EventSource yet.',
                            dense: true,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) =>
                                kOpenHandGap2,
                            itemBuilder: (_, i) {
                              final e = entries[i];
                              final isSel = e.requestId == _selectedReqId;
                              return _ConnTile(
                                entry: e,
                                selected: isSel,
                                onTap: () {
                                  setState(() {
                                    _selectedReqId = e.requestId;
                                    _lastFrame = e.wsFrames.isEmpty
                                        ? null
                                        : e.wsFrames.last;
                                  });
                                  _scrollGuard.scheduleFollowToBottom(
                                    _scroll,
                                    animated: true,
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          kOpenHandHGap12,
          // 右侧：帧流
          Expanded(
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : _kSwitchDuration,
              curve: _kSwitchInCurve,
              decoration: webReverseSurfaceCardDecoration(cs, radius: 16),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: selected == null
                  ? Center(
                      child: Text(
                        loc?.webReverseRealtimePickPrompt ??
                            'Pick a connection to view frames.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : _buildFrameStream(selected, theme, cs, loc),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrameStream(
    CdpNetworkEntry entry,
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
  ) {
    final frames = entry.wsFrames.where((f) {
      if (!_dirFilter.contains(f.direction)) return false;
      if (_filter.isEmpty) return true;
      return f.payload.toLowerCase().contains(_filter.toLowerCase());
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 工具条：方向过滤 + 文本过滤 + 自动跟随
        Row(
          children: [
            for (final d in CdpWebSocketDirection.values) ...[
              FilterChip(
                label: Text(_dirLabel(d, loc)),
                avatar: Icon(_dirIcon(d), size: 14, color: _dirColor(d, cs)),
                selected: _dirFilter.contains(d),
                onSelected: (v) => setState(() {
                  if (v) {
                    _dirFilter.add(d);
                  } else {
                    _dirFilter.remove(d);
                  }
                }),
              ),
              kOpenHandHGap6,
            ],
            kOpenHandHGap6,
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  border: const OutlineInputBorder(),
                  hintText:
                      loc?.webReverseRealtimeFilterHint ??
                      'Filter payload (substring)',
                ),
                onChanged: (v) => setState(() => _filter = v.trim()),
              ),
            ),
            kOpenHandHGap8,
            FilterChip(
              label: Text(loc?.webReverseRealtimeAutoFollow ?? 'Auto-follow'),
              avatar: const Icon(Icons.vertical_align_bottom_rounded, size: 14),
              selected: _autoFollow,
              onSelected: (v) => setState(() => _autoFollow = v),
            ),
          ],
        ),
        kOpenHandGap8,
        // 标题条：连接 URL + 帧数 + 时长
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.06),
            borderRadius: kOpenHandBorderRadius10,
            border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 14, color: cs.primary),
              kOpenHandHGap6,
              Expanded(
                child: SelectableText(
                  entry.url,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              kOpenHandHGap6,
              Text(
                loc?.webReverseRealtimeFrameCount(entry.wsFrames.length) ??
                    '${entry.wsFrames.length} frames',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        kOpenHandGap8,
        // 帧列表
        Expanded(
          child: frames.isEmpty
              ? OpenHandInlineEmptyState(
                  message:
                      loc?.webReverseRealtimeNoMatching ??
                      'No matching frames.',
                  dense: true,
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: _scrollGuard.handleNotification,
                  child: ListView.separated(
                    controller: _scroll,
                    itemCount: frames.length,
                    separatorBuilder: (_, _) => kOpenHandGap4,
                    itemBuilder: (_, i) {
                      final f = frames[i];
                      return _FrameTile(
                        frame: f,
                        icon: _dirIcon(f.direction),
                        color: _dirColor(f.direction, cs),
                        label: _dirLabel(f.direction, loc),
                        onCopy: () => _copyFrame(f),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _ConnTile extends StatelessWidget {
  const _ConnTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });
  final CdpNetworkEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSse = entry.resourceType.toLowerCase() == 'eventsource';
    return InkWell(
      borderRadius: kOpenHandBorderRadius10,
      onTap: onTap,
      child: AnimatedContainer(
        duration: openHandMotionDuration(
          context,
          kOpenHandMotion160,
        ),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: kOpenHandBorderRadius10,
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isSse ? cs.tertiary : cs.primary).withValues(
                  alpha: 0.14,
                ),
                borderRadius: kOpenHandBorderRadius6,
              ),
              child: Text(
                isSse ? 'SSE' : 'WS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSse ? cs.tertiary : cs.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
            kOpenHandHGap8,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Uri.tryParse(entry.url)?.path ?? entry.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${entry.wsFrames.length} frames',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.frame,
    required this.icon,
    required this.color,
    required this.label,
    required this.onCopy,
  });
  final CdpWebSocketFrame frame;
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final payload = frame.errorMessage ?? frame.payload;
    final preview = clipTextByCodeUnits(payload, 800, suffix: '…');
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: kOpenHandBorderRadius10,
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              kOpenHandHGap6,
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              kOpenHandHGap10,
              Text(
                formatHourMinuteSecondMillis(frame.timestamp),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              kOpenHandHGap10,
              Text(
                '${payload.length} B',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 14),
                onPressed: onCopy,
              ),
            ],
          ),
          kOpenHandGap4,
          SelectableText(
            preview,
            style: const TextStyle(
              fontFamily: kOpenHandMonospaceFontFamily,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

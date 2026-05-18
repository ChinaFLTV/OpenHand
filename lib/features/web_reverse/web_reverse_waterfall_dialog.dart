/// 网络瀑布图面板。
///
/// 数据源：[WebReverseSessionController.networkRequests]。
/// 每行展示一个请求横向条带：
///   - 起点 = (entry.timestamp - earliest)
///   - 蓝色段 = 等待响应 (timestamp → responseReceivedAt)
///   - 绿色段 = 下载 (responseReceivedAt → loadingFinishedAt)
///   - 灰色虚线 = 仍未完成（无 loadingFinishedAt）
/// 支持 URL 子串过滤、按耗时排序、点击复制 URL。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseWaterfallDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _WaterfallDialog(controller: controller, isZh: isZh),
  );
}

enum _SortMode { time, duration, size }

class _WaterfallDialog extends StatefulWidget {
  const _WaterfallDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_WaterfallDialog> createState() => _WaterfallDialogState();
}

class _WaterfallDialogState extends State<_WaterfallDialog> {
  final TextEditingController _filterCtrl = TextEditingController();
  _SortMode _sort = _SortMode.time;
  bool _onlyXhr = false;

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  List<CdpNetworkEntry> _filtered() {
    final q = _filterCtrl.text.trim().toLowerCase();
    final list = widget.controller.networkRequests.where((e) {
      if (_onlyXhr) {
        final rt = e.resourceType.toLowerCase();
        if (rt != 'xhr' && rt != 'fetch') return false;
      }
      if (q.isEmpty) return true;
      return e.url.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case _SortMode.time:
        list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        break;
      case _SortMode.duration:
        list.sort((a, b) => _duration(b).compareTo(_duration(a)));
        break;
      case _SortMode.size:
        list.sort((a, b) =>
            (b.encodedDataLength ?? 0).compareTo(a.encodedDataLength ?? 0));
        break;
    }
    return list;
  }

  int _duration(CdpNetworkEntry e) {
    final end = e.loadingFinishedAt ?? e.responseReceivedAt;
    if (end == null) return 0;
    return end.difference(e.timestamp).inMilliseconds;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final entries = _filtered();
    final messenger = ScaffoldMessenger.maybeOf(context);

    // 时间窗
    DateTime? earliest;
    DateTime? latest;
    for (final e in entries) {
      if (earliest == null || e.timestamp.isBefore(earliest)) earliest = e.timestamp;
      final end = e.loadingFinishedAt ?? e.responseReceivedAt ?? e.timestamp;
      if (latest == null || end.isAfter(latest)) latest = end;
    }
    final windowMs = (earliest != null && latest != null)
        ? latest.difference(earliest).inMilliseconds.clamp(1, 1 << 30)
        : 1;

    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.timeline_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isZh ? '请求瀑布图' : 'Network Waterfall',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          isZh
                              ? '蓝段 = 等待 TTFB，绿段 = 下载；点击行复制 URL'
                              : 'Blue = wait TTFB, Green = download; click row to copy URL',
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: isZh ? '刷新' : 'Refresh',
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _filterCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        hintText: isZh ? 'URL 子串过滤' : 'filter URL substring',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: Text(isZh ? '仅 XHR/Fetch' : 'XHR/Fetch only'),
                    selected: _onlyXhr,
                    onSelected: (v) => setState(() => _onlyXhr = v),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<_SortMode>(
                    value: _sort,
                    onChanged: (v) {
                      if (v != null) setState(() => _sort = v);
                    },
                    items: [
                      DropdownMenuItem(value: _SortMode.time, child: Text(isZh ? '时间' : 'Time')),
                      DropdownMenuItem(value: _SortMode.duration, child: Text(isZh ? '耗时' : 'Duration')),
                      DropdownMenuItem(value: _SortMode.size, child: Text(isZh ? '大小' : 'Size')),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${entries.length}',
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          isZh ? '没有请求' : 'No requests',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          const leftWidth = 360.0;
                          final barWidth = (constraints.maxWidth - leftWidth - 16).clamp(120.0, 9999.0);
                          return Column(
                            children: [
                              _scaleHeader(theme, cs, leftWidth, barWidth, windowMs, isZh),
                              Divider(height: 1, color: cs.outlineVariant),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: entries.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant),
                                  itemBuilder: (_, i) {
                                    final e = entries[i];
                                    return _row(
                                      theme: theme,
                                      cs: cs,
                                      e: e,
                                      earliest: earliest!,
                                      windowMs: windowMs,
                                      leftWidth: leftWidth,
                                      barWidth: barWidth,
                                      isZh: isZh,
                                      onTap: () async {
                                        await Clipboard.setData(ClipboardData(text: e.url));
                                        if (messenger != null && mounted) {
                                          OpenHandSnackBar.showSuccessOn(
                                            context,
                                            messenger,
                                            isZh ? '已复制 URL' : 'URL copied',
                                          );
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    label: isZh ? '关闭' : 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scaleHeader(ThemeData theme, ColorScheme cs, double leftWidth,
      double barWidth, int windowMs, bool isZh) {
    final ticks = <Widget>[];
    const tickCount = 5;
    for (var i = 0; i <= tickCount; i++) {
      final ratio = i / tickCount;
      final ms = (windowMs * ratio).round();
      ticks.add(Positioned(
        left: barWidth * ratio - 16,
        child: Text(
          '${ms}ms',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontFamily: 'monospace',
            fontSize: 10,
          ),
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: leftWidth,
            child: Text(
              isZh ? '请求' : 'Request',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: barWidth,
            height: 16,
            child: Stack(children: ticks),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required ThemeData theme,
    required ColorScheme cs,
    required CdpNetworkEntry e,
    required DateTime earliest,
    required int windowMs,
    required double leftWidth,
    required double barWidth,
    required bool isZh,
    required VoidCallback onTap,
  }) {
    final startMs = e.timestamp.difference(earliest).inMilliseconds;
    final ttfbEnd = e.responseReceivedAt ?? e.loadingFinishedAt ?? e.timestamp;
    final downloadEnd = e.loadingFinishedAt ?? ttfbEnd;
    final waitMs = ttfbEnd.difference(e.timestamp).inMilliseconds.clamp(0, 1 << 30);
    final downMs = downloadEnd.difference(ttfbEnd).inMilliseconds.clamp(0, 1 << 30);
    final pending = e.loadingFinishedAt == null && e.responseReceivedAt == null;

    double pos(int ms) => (ms / windowMs).clamp(0.0, 1.0) * barWidth;
    final left = pos(startMs);
    final waitW = pos(startMs + waitMs) - left;
    final downW = pos(startMs + waitMs + downMs) - (left + waitW);

    final status = e.statusCode;
    final statusColor = status == null
        ? cs.onSurfaceVariant
        : (status >= 500
            ? cs.error
            : (status >= 400
                ? Colors.orange
                : (status >= 300 ? Colors.amber : cs.primary)));

    final size = e.encodedDataLength;
    final total = waitMs + downMs;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(
                      e.method,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      status?.toString() ?? '—',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _shortUrl(e.url),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: barWidth,
              height: 16,
              child: Stack(
                children: [
                  Positioned(
                    left: left,
                    top: 4,
                    height: 8,
                    width: (waitW + downW).clamp(1.0, barWidth),
                    child: pending
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: cs.outlineVariant, width: 1),
                            ),
                          )
                        : Row(
                            children: [
                              Container(
                                width: waitW.clamp(0.0, barWidth),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.7),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(2),
                                    bottomLeft: Radius.circular(2),
                                  ),
                                ),
                              ),
                              Container(
                                width: downW.clamp(0.0, barWidth),
                                decoration: BoxDecoration(
                                  color: cs.tertiary.withValues(alpha: 0.85),
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(2),
                                    bottomRight: Radius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  Positioned(
                    left: (left + waitW + downW + 4).clamp(0.0, barWidth - 60),
                    top: 0,
                    child: Text(
                      pending
                          ? (isZh ? '…' : '…')
                          : '${total}ms${size != null ? '·${_fmtSize(size)}' : ''}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                        fontSize: 10,
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
  }

  String _shortUrl(String url) {
    try {
      final u = Uri.parse(url);
      final path = u.path.isEmpty ? '/' : u.path;
      return '${u.host}$path';
    } catch (_) {
      return url;
    }
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)}MB';
  }
}

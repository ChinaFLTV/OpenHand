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

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
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
                    onPressed: () => _importHar(isZh),
                    icon: const Icon(Icons.file_upload_outlined),
                    tooltip: isZh ? '导入 HAR' : 'Import HAR',
                  ),
                  IconButton(
                    onPressed: entries.isEmpty ? null : () => _exportHar(isZh),
                    icon: const Icon(Icons.file_download_outlined),
                    tooltip: isZh ? '导出 HAR' : 'Export HAR',
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
                  _initiatorBadge(theme, cs, e, isZh),
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

  /// Initiator 入口徽标：有调用栈/url 时高亮，可点击展开详情并跳转 Sources。
  Widget _initiatorBadge(
    ThemeData theme,
    ColorScheme cs,
    CdpNetworkEntry e,
    bool isZh,
  ) {
    final hasAny = (e.initiatorUrl != null && e.initiatorUrl!.isNotEmpty) ||
        e.initiatorStack.isNotEmpty ||
        (e.initiatorType != null && e.initiatorType!.isNotEmpty);
    final type = (e.initiatorType ?? 'other').toLowerCase();
    final letter = switch (type) {
      'script' => 'S',
      'parser' => 'P',
      'preflight' => 'F',
      _ => 'O',
    };
    final color = hasAny ? cs.primary : cs.outlineVariant;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: hasAny
            ? (isZh
                ? '发起方：$type${e.initiatorUrl != null ? "\n${e.initiatorUrl}" : ""}'
                : 'Initiator: $type${e.initiatorUrl != null ? "\n${e.initiatorUrl}" : ""}')
            : (isZh ? '无 Initiator 信息' : 'No initiator info'),
        child: InkWell(
          onTap: hasAny ? () => _showInitiator(e, isZh) : null,
          borderRadius: BorderRadius.circular(3),
          child: Container(
            width: 16,
            height: 14,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              letter,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showInitiator(CdpNetworkEntry e, bool isZh) async {
    final ctrl = widget.controller;
    await showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final cs = theme.colorScheme;
        final frames = e.initiatorStack;
        return Dialog(
          backgroundColor: cs.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SizedBox(
            width: 720,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                  child: Row(
                    children: [
                      Icon(Icons.account_tree_rounded, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isZh ? '请求发起方' : 'Request Initiator',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
                  child: Row(
                    children: [
                      Text(
                        '${isZh ? "类型" : "Type"}: ${e.initiatorType ?? "—"}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(),
                      if (e.initiatorUrl != null && e.initiatorUrl!.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            ctrl.requestSourceJump(
                              url: e.initiatorUrl!,
                              line: e.initiatorLineNumber ?? 0,
                              col: e.initiatorColumnNumber ?? 0,
                            );
                            Navigator.of(dialogContext).pop();
                            if (mounted) Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.launch_rounded, size: 14),
                          label: Text(isZh ? '跳到 Sources' : 'Open in Sources'),
                        ),
                    ],
                  ),
                ),
                if (e.initiatorUrl != null && e.initiatorUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                    child: Text(
                      '${e.initiatorUrl}:${(e.initiatorLineNumber ?? 0) + 1}:${(e.initiatorColumnNumber ?? 0) + 1}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                Divider(height: 1, color: cs.outlineVariant),
                Container(
                  constraints: const BoxConstraints(maxHeight: 360),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: frames.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            isZh
                                ? '没有 JavaScript 调用栈（parser/preflight 类型常见）'
                                : 'No JavaScript stack (typical for parser/preflight)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: frames.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: cs.outlineVariant),
                          itemBuilder: (_, i) {
                            final f = frames[i];
                            final fn = (f['functionName'] as String?) ?? '';
                            final url = (f['url'] as String?) ?? '';
                            final line =
                                ((f['lineNumber'] as num?)?.toInt() ?? 0) + 1;
                            final col =
                                ((f['columnNumber'] as num?)?.toInt() ?? 0) + 1;
                            return InkWell(
                              onTap: url.isEmpty
                                  ? null
                                  : () {
                                      ctrl.requestSourceJump(
                                        url: url,
                                        line:
                                            (f['lineNumber'] as num?)?.toInt() ??
                                                0,
                                        col:
                                            (f['columnNumber'] as num?)?.toInt() ??
                                                0,
                                      );
                                      Navigator.of(dialogContext).pop();
                                      if (mounted) Navigator.of(context).pop();
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fn.isEmpty ? '(anonymous)' : fn,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    if (url.isNotEmpty)
                                      Text(
                                        '$url:$line:$col',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OpenHandDialogActionButton.secondary(
                        label: isZh ? '关闭' : 'Close',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _importHar(bool isZh) async {
    final messenger = ScaffoldMessenger.of(context);
    const typeGroup =
        XTypeGroup(label: 'HAR', extensions: <String>['har', 'json']);
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [typeGroup]);
    } catch (error, stack) {
      silentLog('web_reverse_waterfall_dialog', 'openFile har', error, stack);
    }
    if (file == null) return;
    bool merge = false;
    final existing = widget.controller.networkRequests.length;
    if (existing > 0 && mounted) {
      final mode = await showAnimatedDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(isZh ? '加载 HAR' : 'Load HAR'),
          content: Text(
            isZh
                ? '当前已有 $existing 条记录，选择加载方式：'
                : 'Network list has $existing entries. Choose load mode:',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop('cancel'),
              child: Text(isZh ? '取消' : 'Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dctx).pop('merge'),
              child: Text(isZh ? '合并' : 'Merge'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dctx).pop('replace'),
              child: Text(isZh ? '替换' : 'Replace'),
            ),
          ],
        ),
      );
      if (mode == null || mode == 'cancel') return;
      merge = mode == 'merge';
    }
    try {
      final bytes = await file.readAsBytes();
      final r = widget.controller.loadHarBytes(bytes, merge: merge);
      if (!mounted) return;
      setState(() {});
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh
            ? '${merge ? "合并" : "替换"}加载 ${r.loaded} 条；跳过 ${r.skipped} 条'
            : '${merge ? "Merged" : "Replaced"}: ${r.loaded}; skipped ${r.skipped}',
        duration: const Duration(seconds: 3),
      );
    } catch (error, stack) {
      silentLog('web_reverse_waterfall_dialog', 'parse har', error, stack);
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? 'HAR 解析失败' : 'HAR parse failed',
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _exportHar(bool isZh) async {
    final messenger = ScaffoldMessenger.of(context);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    const typeGroup = XTypeGroup(label: 'HAR', extensions: <String>['har']);
    FileSaveLocation? loc;
    try {
      loc = await getSaveLocation(
        suggestedName: 'web-reverse-$ts.har',
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog('web_reverse_waterfall_dialog', 'getSaveLocation har', error,
          stack);
    }
    if (loc == null) return;
    String? written;
    try {
      written = await widget.controller
          .exportHarToPath(loc.path)
          .timeout(const Duration(seconds: 10));
    } catch (error, stack) {
      silentLog(
          'web_reverse_waterfall_dialog', 'exportHarToPath', error, stack);
    }
    if (!mounted) return;
    if (written == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? 'HAR 保存失败或超时' : 'HAR save failed or timed out',
        duration: const Duration(seconds: 3),
      );
    } else {
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? 'HAR 已保存到 $written' : 'HAR saved to $written',
        duration: const Duration(seconds: 3),
      );
    }
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

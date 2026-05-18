/// Heap Snapshot 抓取面板 — 包装 [WebReverseSessionController.takeHeapSnapshot]。
///
/// HeapProfiler.takeHeapSnapshot → 拼接 .heapsnapshot 文本 → 落盘
/// （Chrome DevTools / Edge DevTools 的 Memory tab 可加载）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseHeapSnapshotDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _HeapDialog(controller: controller, isZh: isZh),
  );
}

class _HeapDialog extends StatefulWidget {
  const _HeapDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_HeapDialog> createState() => _HeapDialogState();
}

class _HeapDialogState extends State<_HeapDialog> {
  bool _busy = false;
  String _status = '';
  String _lastSaved = '';
  int _lastBytes = 0;

  Future<void> _take() async {
    final isZh = widget.isZh;
    setState(() {
      _busy = true;
      _status = isZh ? '正在抓取 Heap Snapshot（可能耗时数秒）...' : 'Taking heap snapshot...';
    });
    ({String json, int bytes})? r;
    try {
      r = await widget.controller.takeHeapSnapshot();
    } catch (e, s) {
      silentLog('web-reverse', 'heap-snapshot.take', e, s);
    }
    if (!mounted) return;
    if (r == null || r.json.isEmpty) {
      setState(() {
        _busy = false;
        _status = isZh ? '抓取失败或无数据' : 'Snapshot failed or empty';
      });
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/openhand_heap_$ts.heapsnapshot');
    await file.writeAsString(r.json);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastSaved = file.path;
      _lastBytes = r!.bytes;
      _status = isZh
          ? '已保存：${file.path} (${(_lastBytes / 1024 / 1024).toStringAsFixed(2)} MB)'
          : 'Saved: ${file.path} (${(_lastBytes / 1024 / 1024).toStringAsFixed(2)} MB)';
    });
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        isZh ? 'Heap snapshot 已保存' : 'Snapshot saved',
      );
    }
  }

  Future<void> _copyPath() async {
    try {
      await Clipboard.setData(ClipboardData(text: _lastSaved));
    } catch (e, s) {
      silentLog('web-reverse', 'heap-snapshot.clipboard', e, s);
      return;
    }
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        widget.isZh ? '路径已复制' : 'Path copied',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.memory_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isZh ? 'Heap Snapshot' : 'Heap Snapshot',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          isZh
                              ? 'HeapProfiler.takeHeapSnapshot → .heapsnapshot（DevTools Memory 可加载）'
                              : 'HeapProfiler.takeHeapSnapshot → .heapsnapshot',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  if (_busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.flash_on_rounded, color: cs.secondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _status.isEmpty
                          ? (isZh
                              ? '点击下方按钮抓取当前页面的 V8 Heap Snapshot。\n大型页面可能产生 50MB+ 文件。'
                              : 'Click below to capture current page V8 heap snapshot.\nLarge pages may produce 50MB+ files.')
                          : _status,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  if (_lastSaved.isNotEmpty)
                    Expanded(
                      child: OpenHandDialogActionButton.secondary(
                        label: isZh ? '复制路径' : 'Copy path',
                        icon: Icons.copy_rounded,
                        onPressed: _copyPath,
                      ),
                    ),
                  if (_lastSaved.isNotEmpty) const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _take,
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: Text(isZh ? '抓取快照' : 'Take Snapshot'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OpenHandDialogActionButton.primary(
                      label: isZh ? '关闭' : 'Close',
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
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

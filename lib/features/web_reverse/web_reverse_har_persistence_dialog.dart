/// HAR 全量持久化面板。
///
/// 在 [web_reverse_session_controller] 的基础 HAR 导出能力之上提供：
/// - 即时落盘到用户选定路径
/// - 反向加载外部 HAR 文件（替换/合并到当前会话）
/// - 周期性自动轮转：每 N 分钟把当前 HAR 写到指定目录下带时间戳的文件
///
/// 自动轮转使用 Timer.periodic，dialog 关闭后会沿用 _ScopeState 静态字段继续运行；
/// 用户可在面板里随时停止。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseHarPersistenceDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) =>
        _HarPersistenceDialog(controller: controller, isZh: isZh),
  );
}

/// 进程内单例状态：dialog 关闭后 timer 继续运行。
class _AutoRotateState {
  Timer? timer;
  Duration interval = const Duration(minutes: 15);
  String? folder;
  int rotations = 0;
  String? lastFile;
  DateTime? nextAt;
}

final _AutoRotateState _autoRotate = _AutoRotateState();

class _HarPersistenceDialog extends StatefulWidget {
  const _HarPersistenceDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_HarPersistenceDialog> createState() => _HarPersistenceDialogState();
}

class _HarPersistenceDialogState extends State<_HarPersistenceDialog> {
  bool _busy = false;
  String _status = '';
  bool _mergeOnLoad = false;
  Duration _interval = _autoRotate.interval;
  String? _folder = _autoRotate.folder;
  Timer? _uiRefresh;

  @override
  void initState() {
    super.initState();
    // 每秒刷新一次「下一次轮转剩余」展示。
    _uiRefresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiRefresh?.cancel();
    super.dispose();
  }

  Future<void> _saveNow() async {
    if (_busy) return;
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    const tg = XTypeGroup(label: 'HAR', extensions: <String>['har']);
    FileSaveLocation? loc;
    try {
      loc = await getSaveLocation(
        suggestedName: 'web-reverse-$ts.har',
        acceptedTypeGroups: const <XTypeGroup>[tg],
      );
    } catch (e, s) {
      silentLog('web_reverse_har_persistence', 'getSaveLocation', e, s);
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
          context, messenger, isZh ? '打开保存对话框失败' : 'Failed to open save dialog');
      return;
    }
    if (loc == null) return;
    setState(() {
      _busy = true;
      _status = isZh ? '导出中...' : 'Exporting...';
    });
    try {
      final written = await widget.controller
          .exportHarToPath(loc.path)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (written == null) {
        setState(() => _status = isZh ? '导出失败（无 HAR 草稿）' : 'Export failed (no HAR draft)');
        OpenHandSnackBar.showErrorOn(
            context, messenger, isZh ? '导出失败' : 'Export failed');
      } else {
        setState(() => _status = (isZh ? '已写出: ' : 'Wrote: ') + written);
        OpenHandSnackBar.showSuccessOn(
            context, messenger, isZh ? 'HAR 已保存' : 'HAR saved');
      }
    } catch (e, s) {
      silentLog('web_reverse_har_persistence', 'exportHarToPath', e, s);
      if (!mounted) return;
      setState(() => _status = isZh ? '导出异常: $e' : 'Export error: $e');
      OpenHandSnackBar.showErrorOn(
          context, messenger, isZh ? '导出异常' : 'Export error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadHar() async {
    if (_busy) return;
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    const tg = XTypeGroup(label: 'HAR', extensions: <String>['har', 'json']);
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const <XTypeGroup>[tg]);
    } catch (e, s) {
      silentLog('web_reverse_har_persistence', 'openFile', e, s);
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
          context, messenger, isZh ? '打开文件对话框失败' : 'Failed to open file dialog');
      return;
    }
    if (file == null) return;
    setState(() {
      _busy = true;
      _status = isZh ? '解析 HAR...' : 'Parsing HAR...';
    });
    try {
      final bytes = await file.readAsBytes();
      final r = widget.controller.loadHarBytes(bytes, merge: _mergeOnLoad);
      if (!mounted) return;
      setState(() => _status = isZh
          ? '加载完成: ${r.loaded} 条 / 跳过 ${r.skipped} 条（${_mergeOnLoad ? '合并' : '替换'}）'
          : 'Loaded: ${r.loaded} / skipped ${r.skipped} (${_mergeOnLoad ? 'merge' : 'replace'})');
      OpenHandSnackBar.showSuccessOn(
          context, messenger, isZh ? 'HAR 已加载' : 'HAR loaded');
    } catch (e, s) {
      silentLog('web_reverse_har_persistence', 'loadHarBytes', e, s);
      if (!mounted) return;
      setState(() => _status = isZh ? '加载异常: $e' : 'Load error: $e');
      OpenHandSnackBar.showErrorOn(
          context, messenger, isZh ? '加载异常' : 'Load error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFolder() async {
    final isZh = widget.isZh;
    try {
      final dir = await getDirectoryPath(
        confirmButtonText: isZh ? '选择' : 'Select',
      );
      if (dir == null) return;
      setState(() => _folder = dir);
    } catch (e, s) {
      silentLog('web_reverse_har_persistence', 'getDirectoryPath', e, s);
    }
  }

  void _startAutoRotate() {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    final folder = _folder;
    if (folder == null || folder.isEmpty) {
      OpenHandSnackBar.showErrorOn(
          context, messenger, isZh ? '请先选择目录' : 'Choose a folder first');
      return;
    }
    _autoRotate.timer?.cancel();
    _autoRotate.interval = _interval;
    _autoRotate.folder = folder;
    _autoRotate.nextAt = DateTime.now().add(_interval);
    final ctrl = widget.controller;
    _autoRotate.timer = Timer.periodic(_interval, (_) async {
      try {
        final ts = DateTime.now()
            .toIso8601String()
            .replaceAll(':', '-')
            .replaceAll('.', '-');
        final dest = '${_autoRotate.folder}${Platform.pathSeparator}web-reverse-$ts.har';
        final written = await ctrl
            .exportHarToPath(dest)
            .timeout(const Duration(seconds: 20));
        if (written != null) {
          _autoRotate.rotations += 1;
          _autoRotate.lastFile = written;
        }
        _autoRotate.nextAt = DateTime.now().add(_autoRotate.interval);
      } catch (e, s) {
        silentLog('web_reverse_har_persistence', 'auto-rotate tick', e, s);
      }
    });
    setState(() {});
    OpenHandSnackBar.showSuccessOn(
        context, messenger, isZh ? '已启动自动轮转' : 'Auto-rotate started');
  }

  void _stopAutoRotate() {
    _autoRotate.timer?.cancel();
    _autoRotate.timer = null;
    _autoRotate.nextAt = null;
    setState(() {});
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
          context, m, widget.isZh ? '已停止自动轮转' : 'Auto-rotate stopped');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final entryCount = widget.controller.networkRequests.length;
    final lastHar = widget.controller.lastHarPath;
    final running = _autoRotate.timer != null;
    String remaining = '';
    if (running && _autoRotate.nextAt != null) {
      final diff = _autoRotate.nextAt!.difference(DateTime.now());
      if (!diff.isNegative) {
        final m = diff.inMinutes;
        final s = diff.inSeconds % 60;
        remaining = '${m}m ${s}s';
      } else {
        remaining = '0s';
      }
    }
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 780),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.save_as_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isZh ? 'HAR 全量持久化' : 'HAR Persistence',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          isZh
                              ? '立即落盘 / 反向加载 / 周期自动轮转'
                              : 'Save now / Load back / Periodic rotation',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isZh ? '当前会话状态' : 'Session status',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isZh
                                ? '抓包条目: $entryCount'
                                : 'Captured entries: $entryCount',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (lastHar != null && lastHar.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                (isZh ? '上次 HAR: ' : 'Last HAR: ') + lastHar,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: cs.onSurfaceVariant),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isZh ? '手动操作' : 'Manual',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _saveNow,
                          icon: _busy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download_rounded, size: 18),
                          label: Text(isZh ? '立即保存 HAR' : 'Save HAR now'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _loadHar,
                          icon: const Icon(Icons.upload_file_rounded, size: 18),
                          label: Text(isZh ? '加载外部 HAR' : 'Load external HAR'),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _mergeOnLoad,
                              onChanged: (v) =>
                                  setState(() => _mergeOnLoad = v ?? false),
                            ),
                            Text(isZh ? '合并（不清空）' : 'Merge (no clear)'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      isZh ? '周期自动轮转' : 'Auto-rotate',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(isZh ? '间隔:' : 'Interval:'),
                        const SizedBox(width: 8),
                        DropdownButton<Duration>(
                          value: _interval,
                          onChanged: running
                              ? null
                              : (v) {
                                  if (v != null) {
                                    setState(() => _interval = v);
                                  }
                                },
                          items: const [
                            DropdownMenuItem(
                                value: Duration(minutes: 5), child: Text('5 min')),
                            DropdownMenuItem(
                                value: Duration(minutes: 15), child: Text('15 min')),
                            DropdownMenuItem(
                                value: Duration(minutes: 30), child: Text('30 min')),
                            DropdownMenuItem(
                                value: Duration(minutes: 60), child: Text('60 min')),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: running ? null : _pickFolder,
                          icon: const Icon(Icons.folder_rounded, size: 18),
                          label: Text(isZh ? '选择目录' : 'Choose folder'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _folder ?? (isZh ? '（未选择）' : '(not chosen)'),
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: cs.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (!running)
                          FilledButton.icon(
                            onPressed: _startAutoRotate,
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: Text(isZh ? '启动' : 'Start'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _stopAutoRotate,
                            style: FilledButton.styleFrom(
                                backgroundColor: cs.errorContainer,
                                foregroundColor: cs.onErrorContainer),
                            icon: const Icon(Icons.stop_rounded, size: 18),
                            label: Text(isZh ? '停止' : 'Stop'),
                          ),
                      ],
                    ),
                    if (running) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isZh
                                  ? '运行中 · 已轮转 ${_autoRotate.rotations} 次 · 下次 $remaining 后'
                                  : 'Running · ${_autoRotate.rotations} rotations · next in $remaining',
                              style: theme.textTheme.bodySmall,
                            ),
                            if (_autoRotate.lastFile != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                (isZh ? '最近一份: ' : 'Last: ') +
                                    _autoRotate.lastFile!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: cs.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (_status.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Text(
                          _status,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      isZh ? '说明' : 'Notes',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isZh
                          ? '· 立即保存：把内部 HAR 草稿复制到你选择的 .har 路径。\n'
                              '· 加载外部 HAR：解析 HAR 1.2 并写回 networkRequests，可选合并到现有列表。\n'
                              '· 自动轮转：每 N 分钟把当前快照写到目录下带 ISO 时间戳的 .har 文件；对话框关闭后继续运行，需手动停止。'
                          : '· Save now: copy internal HAR draft to chosen .har path.\n'
                              '· Load external HAR: parse HAR 1.2 and write back to networkRequests; merge optional.\n'
                              '· Auto-rotate: writes current snapshot to folder with ISO-timestamped .har every N minutes; survives dialog close — stop manually.',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
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
}

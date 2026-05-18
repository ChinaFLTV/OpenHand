/// 多账号会话快照切换器。
///
/// "保存当前 cookies + 当前 origin storage" → 命名快照入列表；任意时刻点
/// "应用" 即清空当前 cookies 并回放保存值。导出/导入 JSON 跨设备同步。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseAccountSnapshotsDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _AccountSnapshotsDialog(
      controller: controller,
      isZh: isZh,
    ),
  );
}

class _AccountSnapshotsDialog extends StatefulWidget {
  const _AccountSnapshotsDialog({
    required this.controller,
    required this.isZh,
  });
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_AccountSnapshotsDialog> createState() =>
      _AccountSnapshotsDialogState();
}

class _AccountSnapshotsDialogState extends State<_AccountSnapshotsDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_busy) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final snap = await widget.controller.captureAccountSnapshot(name);
      if (!mounted) return;
      if (snap != null) {
        _nameCtrl.clear();
        if (messenger != null) {
          OpenHandSnackBar.showSuccessOn(
            context,
            messenger,
            widget.isZh
                ? '已保存「${snap.name}」（${snap.cookies.length} cookies）'
                : 'Saved "${snap.name}" (${snap.cookies.length} cookies)',
          );
        }
      }
    } catch (e, st) {
      silentLog('web_reverse_account_snapshots_dialog', 'capture', e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(WebReverseAccountSnapshot snap) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final ok = await widget.controller.restoreAccountSnapshot(snap);
      if (!mounted) return;
      if (messenger != null) {
        if (ok) {
          OpenHandSnackBar.showSuccessOn(
            context,
            messenger,
            widget.isZh
                ? '已应用「${snap.name}」，建议刷新页面让 JS 重新读取'
                : 'Applied "${snap.name}". Refresh the page so JS re-reads it.',
            duration: const Duration(seconds: 4),
          );
        } else {
          OpenHandSnackBar.showErrorOn(
            context,
            messenger,
            widget.isZh ? '应用失败：未连上 CDP' : 'Apply failed: no CDP session',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(WebReverseAccountSnapshot snap) async {
    await widget.controller.deleteAccountSnapshot(snap.id);
  }

  Future<void> _export() async {
    final list = widget.controller.accountSnapshots
        .map((s) => s.toJson())
        .toList(growable: false);
    final json = const JsonEncoder.withIndent('  ').convert(list);
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        widget.isZh
            ? '已复制 ${list.length} 份快照 JSON 到剪贴板'
            : 'Copied ${list.length} snapshots JSON to clipboard',
      );
    }
  }

  Future<void> _import() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final parsed = jsonDecode(text);
      if (parsed is! List) throw const FormatException('expect JSON array');
      final merged = <WebReverseAccountSnapshot>[
        ...widget.controller.accountSnapshots,
        for (final raw in parsed)
          if (raw is Map)
            WebReverseAccountSnapshot.fromJson(
              Map<String, Object?>.from(raw),
            ),
      ];
      widget.controller.setAccountSnapshots(merged);
      if (!mounted) return;
      if (messenger != null) {
        OpenHandSnackBar.showSuccessOn(
          context,
          messenger,
          widget.isZh
              ? '已导入 ${parsed.length} 份快照'
              : 'Imported ${parsed.length} snapshots',
        );
      }
    } catch (e, st) {
      silentLog('web_reverse_account_snapshots_dialog', 'import', e, st);
      if (!mounted) return;
      if (messenger != null) {
        OpenHandSnackBar.showErrorOn(
          context,
          messenger,
          widget.isZh ? '剪贴板内容不是有效快照 JSON' : 'Clipboard is not a snapshot JSON',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final snaps = widget.controller.accountSnapshots;
        return Dialog(
          backgroundColor: cs.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
            child: Column(
              children: [
                _buildHeader(theme, cs, isZh),
                Divider(height: 1, color: cs.outlineVariant),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            labelText:
                                isZh ? '为当前账号取名' : 'Name for current account',
                            hintText: isZh ? '如 main / test-001' : 'e.g. main / test-001',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _capture(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : _capture,
                        icon: const Icon(Icons.bookmark_add_rounded, size: 18),
                        label: Text(isZh ? '保存当前' : 'Capture'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: snaps.isEmpty ? null : _export,
                        icon: const Icon(Icons.upload_rounded, size: 16),
                        label: Text(isZh ? '导出全部到剪贴板' : 'Export all'),
                      ),
                      TextButton.icon(
                        onPressed: _import,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: Text(isZh ? '从剪贴板导入' : 'Import'),
                      ),
                      const Spacer(),
                      Text(
                        isZh ? '共 ${snaps.length} 份' : '${snaps.length} total',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: snaps.isEmpty
                      ? _buildEmpty(theme, cs, isZh)
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          itemCount: snaps.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, idx) =>
                              _buildRow(theme, cs, isZh, snaps[idx]),
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
      },
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs, bool isZh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Icon(Icons.switch_account_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isZh ? '多账号会话快照' : 'Account Snapshots',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  isZh
                      ? '保存当前 cookies + localStorage/sessionStorage，一键切换不同账号'
                      : 'Save cookies + localStorage/sessionStorage; one-click switch between accounts',
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
    );
  }

  Widget _buildEmpty(ThemeData theme, ColorScheme cs, bool isZh) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_circle_outlined,
                size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              isZh
                  ? '还没有任何快照。在上方输入名字 → 点"保存当前"开始'
                  : 'No snapshots yet. Type a name above → click "Capture".',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
    WebReverseAccountSnapshot snap,
  ) {
    final ts = snap.capturedAt;
    final stamp =
        '${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snap.name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (snap.origin.isNotEmpty) snap.origin,
                    stamp,
                  ].join(' · '),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    _badge(theme, cs, '${snap.cookies.length} cookies'),
                    _badge(theme, cs, '${snap.localStorage.length} local'),
                    _badge(theme, cs, '${snap.sessionStorage.length} session'),
                  ],
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _apply(snap),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: Text(isZh ? '应用' : 'Apply'),
          ),
          IconButton(
            tooltip: isZh ? '删除' : 'Delete',
            onPressed: () => _delete(snap),
            icon: Icon(Icons.delete_outline_rounded, color: cs.error),
          ),
        ],
      ),
    );
  }

  Widget _badge(ThemeData theme, ColorScheme cs, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: cs.onSecondaryContainer,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      );
}

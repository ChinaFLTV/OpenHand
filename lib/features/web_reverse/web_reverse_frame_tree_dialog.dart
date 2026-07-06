/// Page.getFrameTree 递归查看器。
///
/// 把当前 target 的 frame 树以缩进列表渲染：每帧显示 id / name / url / mimeType /
/// securityOrigin / loaderId / unreachableUrl。支持点击复制 url 与刷新。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseFrameTreeDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showWebReverseToolDialog<void>(
    context: context,
    builder: (_) => _FrameTreeDialog(controller: controller),
  );
}

class _FrameTreeDialog extends StatefulWidget {
  const _FrameTreeDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_FrameTreeDialog> createState() => _FrameTreeDialogState();
}

class _FrameRow {
  _FrameRow({
    required this.depth,
    required this.id,
    required this.name,
    required this.url,
    required this.origin,
    required this.mimeType,
    required this.unreachableUrl,
    required this.loaderId,
  });
  final int depth;
  final String id;
  final String name;
  final String url;
  final String origin;
  final String mimeType;
  final String unreachableUrl;
  final String loaderId;
}

class _FrameTreeDialogState extends State<_FrameTreeDialog> {
  bool _busy = false;
  String _err = '';
  final List<_FrameRow> _rows = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = '';
      _rows.clear();
    });
    Map<String, Object?>? r;
    try {
      r = await widget.controller.sendRawCdp(method: 'Page.getFrameTree');
    } catch (e, s) {
      silentLog('web_reverse_frame_tree_dialog', 'frame-tree.load', e, s);
    }
    if (!mounted) return;
    if (r == null || r['error'] != null) {
      setState(() {
        _busy = false;
        _err =
            AppLocalizations.of(
              context,
            )?.webReverseFrameTreeFailed('${r?['error'] ?? 'unknown'}') ??
            'Failed: ${r?['error'] ?? 'unknown'}';
      });
      return;
    }
    final tree = r['frameTree'];
    if (tree is Map) {
      _walk(tree.cast<String, Object?>(), 0);
    }
    setState(() => _busy = false);
  }

  void _walk(Map<String, Object?> node, int depth) {
    final frame = (node['frame'] is Map)
        ? (node['frame']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    _rows.add(
      _FrameRow(
        depth: depth,
        id: (frame['id'] ?? '').toString(),
        name: (frame['name'] ?? '').toString(),
        url: (frame['url'] ?? '').toString(),
        origin: (frame['securityOrigin'] ?? '').toString(),
        mimeType: (frame['mimeType'] ?? '').toString(),
        unreachableUrl: (frame['unreachableUrl'] ?? '').toString(),
        loaderId: (frame['loaderId'] ?? '').toString(),
      ),
    );
    final children = node['childFrames'];
    if (children is List) {
      for (final c in children.whereType<Map>()) {
        _walk(c.cast<String, Object?>(), depth + 1);
      }
    }
  }

  Future<void> _copy(String s) async {
    late final WebReverseClipboardCopyResult copied;
    try {
      copied = await setWebReverseClipboardText(s);
    } catch (e, st) {
      silentLog('web_reverse_frame_tree_dialog', 'frame-tree.copy', e, st);
      return;
    }
    if (!mounted) return;
    showWebReverseClipboardSuccessSnack(
      context: context,
      base: AppLocalizations.of(context)?.webReverseFrameTreeCopied ?? 'Copied',
      result: copied,
    );
  }

  Future<void> _copyJson() async {
    final lines = _rows
        .map(
          (r) => {
            'depth': r.depth,
            'id': r.id,
            'name': r.name,
            'url': r.url,
            'origin': r.origin,
            'mimeType': r.mimeType,
            'unreachableUrl': r.unreachableUrl,
            'loaderId': r.loaderId,
          },
        )
        .toList();
    await _copy(const JsonEncoder.withIndent('  ').convert(lines));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.account_tree_rounded,
            title: loc?.webReverseFrameTreeTitle ?? 'Frame Tree',
            subtitle:
                loc?.webReverseFrameTreeSubtitle ??
                'Page.getFrameTree · main + nested iframes',
            actions: [
              IconButton(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: loc?.webReverseFrameTreeRefresh ?? 'Refresh',
              ),
              IconButton(
                onPressed: _rows.isEmpty ? null : _copyJson,
                icon: const Icon(Icons.data_object_rounded),
                tooltip: loc?.webReverseFrameTreeCopyJson ?? 'Copy JSON',
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _err.isEmpty
                ? const SizedBox(width: double.infinity)
                : Container(
                    width: double.infinity,
                    color: cs.errorContainer,
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      _err,
                      style: TextStyle(color: cs.onErrorContainer),
                    ),
                  ),
          ),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                ? Center(
                    child: Text(
                      loc?.webReverseFrameTreeEmpty ?? 'No frames',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    itemCount: _rows.length,
                    itemBuilder: (_, i) =>
                        _FrameTile(row: _rows[i], onCopy: _copy, cs: cs),
                  ),
          ),
          buildOpenHandDialogFooter(
            primaryLabel: loc?.commonClose ?? 'Close',
            onPrimaryPressed: () => Navigator.of(context).pop(),
            leading: Text(
              loc?.webReverseFrameTreeCount(_rows.length) ??
                  '${_rows.length} frames',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({required this.row, required this.onCopy, required this.cs});
  final _FrameRow row;
  final ValueChanged<String> onCopy;
  final ColorScheme cs;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8, left: (row.depth * 16).toDouble()),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                row.depth == 0
                    ? Icons.public_rounded
                    : Icons.subdirectory_arrow_right_rounded,
                size: 14,
                color: cs.primary,
              ),
              const SizedBox(width: 6),
              if (row.name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      row.name,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
              if (row.mimeType.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      row.mimeType,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: cs.onTertiaryContainer,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              SelectableText(
                row.id,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  row.url.isEmpty ? '(empty url)' : row.url,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              if (row.url.isNotEmpty)
                InkWell(
                  onTap: () => onCopy(row.url),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          if (row.origin.isNotEmpty || row.unreachableUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (row.origin.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        'origin: ${row.origin}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (row.unreachableUrl.isNotEmpty)
                    Expanded(
                      child: Text(
                        'unreachable: ${row.unreachableUrl}',
                        style: TextStyle(fontSize: 10.5, color: cs.error),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Page.getFrameTree 递归查看器。
///
/// 把当前 target 的 frame 树以缩进列表渲染：每帧显示 id / name / url / mimeType /
/// securityOrigin / loaderId / unreachableUrl。支持点击复制 url 与刷新。
library;

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/motion_durations.dart';
import '../../shared/ui/motion_preference.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_reveal_switcher.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

const int _kMaxFrameTreeRows = 2 * kBytesPerKiB;
const int _kMaxFrameTreeDepth = 64;
const int _kMaxFrameTreeFieldChars = 2 * kBytesPerKiB;

Future<void> showWebReverseFrameTreeDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
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
  bool _truncated = false;
  final List<_FrameRow> _rows = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = '';
      _truncated = false;
      _rows.clear();
    });
    Map<String, Object?>? r;
    try {
      r = await widget.controller.sendRawCdp(method: 'Page.getFrameTree');
    } catch (e, s) {
      silentLog('web_reverse_frame_tree_dialog', '加载页面帧树', e, s);
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
    if (_rows.length >= _kMaxFrameTreeRows || depth > _kMaxFrameTreeDepth) {
      _truncated = true;
      return;
    }
    final frame = (node['frame'] is Map)
        ? (node['frame']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    _rows.add(
      _FrameRow(
        depth: depth,
        id: _clipFrameField(frame['id']),
        name: _clipFrameField(frame['name']),
        url: _clipFrameField(frame['url']),
        origin: _clipFrameField(frame['securityOrigin']),
        mimeType: _clipFrameField(frame['mimeType']),
        unreachableUrl: _clipFrameField(frame['unreachableUrl']),
        loaderId: _clipFrameField(frame['loaderId']),
      ),
    );
    final children = node['childFrames'];
    if (children is List) {
      for (final c in children.whereType<Map>()) {
        if (_rows.length >= _kMaxFrameTreeRows ||
            depth >= _kMaxFrameTreeDepth) {
          _truncated = true;
          break;
        }
        _walk(c.cast<String, Object?>(), depth + 1);
      }
    }
  }

  String _clipFrameField(Object? value) {
    if (value == null) return '';
    return clipTextWithEllipsis('$value', _kMaxFrameTreeFieldChars);
  }

  Future<void> _copy(String s) async {
    await copyWebReverseTextToClipboard(
      context: context,
      text: s,
      successBase:
          AppLocalizations.of(context)?.webReverseFrameTreeCopied ?? 'Copied',
      logTag: 'web_reverse_frame_tree_dialog',
      logAction: '复制页面帧树',
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
    await _copy(prettyPrintJson(lines));
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
            duration: openHandMotionDuration(context, kOpenHandMotion260),
            curve: kOpenHandSwitchInCurve,
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
            child: OpenHandContentStateSwitcher(
              // 外层 Expanded 已经定死高度，这里只做淡入淡出。
              animateSize: false,
              stateKey: _busy
                  ? 'busy'
                  : _rows.isEmpty
                  ? 'empty'
                  : 'rows',
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? OpenHandInlineEmptyState(
                      message: loc?.webReverseFrameTreeEmpty ?? 'No frames',
                      dense: true,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) =>
                          _FrameTile(row: _rows[i], onCopy: _copy, cs: cs),
                    ),
            ),
          ),
          buildOpenHandDialogFooter(
            primaryLabel: loc?.commonClose ?? 'Close',
            onPrimaryPressed: () => Navigator.of(context).pop(),
            leading: Text(
              '${loc?.webReverseFrameTreeCount(_rows.length) ?? '${_rows.length} frames'}${_truncated ? '+' : ''}',
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
      decoration: webReverseSurfaceCardDecoration(cs),
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
              kOpenHandHGap6,
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
                      borderRadius: kOpenHandBorderRadius4,
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
                      borderRadius: kOpenHandBorderRadius4,
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
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          kOpenHandGap6,
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  row.url.isEmpty ? '(empty url)' : row.url,
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                  ),
                ),
              ),
              if (row.url.isNotEmpty)
                InkWell(
                  onTap: () => onCopy(row.url),
                  borderRadius: kOpenHandBorderRadius6,
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

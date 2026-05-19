/// 网络请求批量重放器。
///
/// 多选 `controller.networkRequests` 中的请求，顺序调用 `replayRequest`，
/// 显示每条状态与原状态对比，导出 JSON。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseReplayDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _ReplayDialog(controller: controller, isZh: isZh),
  );
}

class _ReplayDialog extends StatefulWidget {
  const _ReplayDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  // ignore: unused_field
  final bool isZh;
  @override
  State<_ReplayDialog> createState() => _ReplayDialogState();
}

class _ReplayResult {
  _ReplayResult({
    required this.requestId,
    required this.url,
    required this.method,
    required this.originalStatus,
    required this.newStatus,
    required this.bodyPreview,
    required this.ok,
  });
  final String requestId;
  final String url;
  final String method;
  final int? originalStatus;
  final int? newStatus;
  final String bodyPreview;
  final bool ok;
}

class _ReplayDialogState extends State<_ReplayDialog> {
  final Set<String> _selected = <String>{};
  final Map<String, _ReplayResult> _results = {};
  String _filter = '';
  bool _busy = false;
  int _progress = 0;
  int _total = 0;

  List<CdpNetworkEntry> get _entries {
    final list = widget.controller.networkRequests
        .where((e) => !e.isWebSocket)
        .toList();
    if (_filter.isEmpty) return list;
    final f = _filter.toLowerCase();
    return list.where((e) => e.url.toLowerCase().contains(f)).toList();
  }

  Future<void> _runBatch() async {
    final loc = AppLocalizations.of(context);
    final byId = {for (final e in widget.controller.networkRequests) e.requestId: e};
    final picks = _selected.map((id) => byId[id]).whereType<CdpNetworkEntry>().toList();
    if (picks.isEmpty) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _total = picks.length;
      _results.clear();
    });
    for (final e in picks) {
      if (!mounted) return;
      try {
        final r = await widget.controller.replayRequest(e);
        _results[e.requestId] = _ReplayResult(
          requestId: e.requestId,
          url: e.url,
          method: e.method,
          originalStatus: e.statusCode,
          newStatus: r?.status,
          bodyPreview: (r?.body ?? '').length > 200
              ? '${(r?.body ?? '').substring(0, 200)}…'
              : (r?.body ?? ''),
          ok: r != null && r.status >= 200 && r.status < 400,
        );
      } catch (err, st) {
        silentLog('web-reverse', 'replay.batch', err, st);
        _results[e.requestId] = _ReplayResult(
          requestId: e.requestId,
          url: e.url,
          method: e.method,
          originalStatus: e.statusCode,
          newStatus: null,
          bodyPreview: '$err',
          ok: false,
        );
      }
      if (!mounted) return;
      setState(() => _progress += 1);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      final okCount = _results.values.where((r) => r.ok).length;
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        loc?.webReverseReplayDone(okCount, _results.length) ??
            'Replay done: $okCount/${_results.length} ok',
      );
    }
  }

  Future<void> _exportJson() async {
    final data = _results.values
        .map((r) => {
              'requestId': r.requestId,
              'method': r.method,
              'url': r.url,
              'originalStatus': r.originalStatus,
              'newStatus': r.newStatus,
              'bodyPreview': r.bodyPreview,
              'ok': r.ok,
            })
        .toList();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    try {
      await Clipboard.setData(ClipboardData(text: json));
    } catch (e, st) {
      silentLog('web-reverse', 'replay.export', e, st);
      return;
    }
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        loc?.webReverseReplayJsonCopied ?? 'JSON copied',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final entries = _entries;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.replay_circle_filled_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc?.webReverseReplayTitle ??
                              'Network Request Replayer',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          loc?.webReverseReplaySubtitle ??
                              'multi-select → sequential replay → diff',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _results.isEmpty ? null : _exportJson,
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: loc?.webReverseReplayCopyResultsJson ??
                        'Copy results JSON',
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: loc?.webReverseReplayFilterByUrl ??
                            'Filter by URL',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (v) => setState(() => _filter = v.trim()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton.icon(
                    onPressed: entries.isEmpty
                        ? null
                        : () => setState(() {
                              _selected
                                ..clear()
                                ..addAll(entries.map((e) => e.requestId));
                            }),
                    icon: const Icon(Icons.select_all_rounded, size: 18),
                    label: Text(
                        loc?.webReverseReplaySelectAll ?? 'Select All'),
                  ),
                  TextButton.icon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(() => _selected.clear()),
                    icon: const Icon(Icons.deselect_rounded, size: 18),
                    label: Text(loc?.webReverseReplayClear ?? 'Clear'),
                  ),
                ],
              ),
            ),
            if (_busy)
              LinearProgressIndicator(
                value: _total == 0 ? 0 : _progress / _total,
                minHeight: 3,
              ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        loc?.webReverseReplayEmpty ??
                            'No HTTP requests in session',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: entries.length,
                      itemBuilder: (_, i) {
                        final e = entries[i];
                        final picked = _selected.contains(e.requestId);
                        final r = _results[e.requestId];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: picked
                                ? cs.primaryContainer.withValues(alpha: 0.35)
                                : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: picked ? cs.primary : cs.outlineVariant,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: _busy
                                ? null
                                : () => setState(() {
                                      if (picked) {
                                        _selected.remove(e.requestId);
                                      } else {
                                        _selected.add(e.requestId);
                                      }
                                    }),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: picked,
                                        onChanged: _busy
                                            ? null
                                            : (v) => setState(() {
                                                  if (v == true) {
                                                    _selected
                                                        .add(e.requestId);
                                                  } else {
                                                    _selected
                                                        .remove(e.requestId);
                                                  }
                                                }),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cs.secondaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          e.method,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSecondaryContainer,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (e.statusCode != null)
                                        Text(
                                          '${e.statusCode}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: e.isError
                                                ? cs.error
                                                : cs.onSurface,
                                          ),
                                        ),
                                      const Spacer(),
                                      if (r != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: r.ok
                                                ? cs.tertiaryContainer
                                                : cs.errorContainer,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            r.newStatus == null
                                                ? '!'
                                                : '→ ${r.newStatus}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: r.ok
                                                  ? cs.onTertiaryContainer
                                                  : cs.onErrorContainer,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    e.url,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  if (r != null && r.bodyPreview.isNotEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 4),
                                      child: Text(
                                        r.bodyPreview,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _busy
                          ? (loc?.webReverseReplayProgress(_progress, _total) ??
                              'Replaying $_progress / $_total')
                          : (loc?.webReverseReplaySelected(
                                  _selected.length, entries.length) ??
                              'Selected ${_selected.length} / ${entries.length}'),
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OpenHandDialogActionButton.secondary(
                    label: loc?.webReverseReplayRunBatch ?? 'Run Batch',
                    icon: Icons.send_rounded,
                    busy: _busy,
                    onPressed: (_busy || _selected.isEmpty) ? null : _runBatch,
                  ),
                  const SizedBox(width: 8),
                  OpenHandDialogActionButton.primary(
                    label: loc?.webReverseReplayClose ?? 'Close',
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

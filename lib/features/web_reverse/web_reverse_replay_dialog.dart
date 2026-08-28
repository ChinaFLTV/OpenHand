/// 网络请求批量重放器。
///
/// 多选 `controller.networkRequests` 中的请求，顺序调用 `replayRequest`，
/// 显示每条状态与原状态对比，导出 JSON。
library;

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseReplayDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _ReplayDialog(controller: controller),
  );
}

class _ReplayDialog extends StatefulWidget {
  const _ReplayDialog({required this.controller});
  final WebReverseSessionController controller;
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
    final byId = {
      for (final e in widget.controller.networkRequests) e.requestId: e,
    };
    final picks = _selected
        .map((id) => byId[id])
        .whereType<CdpNetworkEntry>()
        .toList();
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
          bodyPreview: clipTextByCodeUnits(r?.body ?? '', 200, suffix: '…'),
          ok: r != null && r.status >= 200 && r.status < 400,
        );
      } catch (err, st) {
        silentLog('web_reverse_replay_dialog', '批量重放', err, st);
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
    final okCount = _results.values.where((r) => r.ok).length;
    showOpenHandSuccessSnack(
      context,
      loc?.webReverseReplayDone(okCount, _results.length) ??
          'Replay done: $okCount/${_results.length} ok',
    );
  }

  Future<void> _exportJson() async {
    final data = _results.values
        .map(
          (r) => {
            'requestId': r.requestId,
            'method': r.method,
            'url': r.url,
            'originalStatus': r.originalStatus,
            'newStatus': r.newStatus,
            'bodyPreview': r.bodyPreview,
            'ok': r.ok,
          },
        )
        .toList();
    final json = prettyPrintJson(data);
    final loc = AppLocalizations.of(context);
    await copyWebReverseTextToClipboard(
      context: context,
      text: json,
      successBase: loc?.webReverseReplayJsonCopied ?? 'JSON copied',
      logTag: 'web_reverse_replay_dialog',
      logAction: '导出重放结果',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final entries = _entries;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightTall,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.replay_circle_filled_rounded,
            title: loc?.webReverseReplayTitle ?? 'Network Request Replayer',
            subtitle:
                loc?.webReverseReplaySubtitle ??
                'multi-select → sequential replay → diff',
            actions: [
              IconButton(
                onPressed: _results.isEmpty ? null : _exportJson,
                icon: const Icon(Icons.copy_rounded),
                tooltip:
                    loc?.webReverseReplayCopyResultsJson ?? 'Copy results JSON',
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText:
                          loc?.webReverseReplayFilterByUrl ?? 'Filter by URL',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                      border: const OutlineInputBorder(
                        borderRadius: kOpenHandBorderRadius10,
                      ),
                    ),
                    onChanged: (v) => setState(() => _filter = v.trim()),
                  ),
                ),
                kOpenHandHGap10,
                TextButton.icon(
                  onPressed: entries.isEmpty
                      ? null
                      : () => setState(() {
                          _selected
                            ..clear()
                            ..addAll(entries.map((e) => e.requestId));
                        }),
                  icon: const Icon(Icons.select_all_rounded, size: 18),
                  label: Text(loc?.webReverseReplaySelectAll ?? 'Select All'),
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
          OpenHandBusyProgressBar(
            busy: _busy,
            value: _total == 0 ? 0 : _progress / _total,
          ),
          Expanded(
            child: entries.isEmpty
                ? OpenHandInlineEmptyState(
                    message:
                        loc?.webReverseReplayEmpty ??
                        'No HTTP requests in session',
                    dense: true,
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
                          borderRadius: kOpenHandBorderRadius10,
                          border: Border.all(
                            color: picked ? cs.primary : cs.outlineVariant,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: kOpenHandBorderRadius10,
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
                                                _selected.add(e.requestId);
                                              } else {
                                                _selected.remove(e.requestId);
                                              }
                                            }),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.secondaryContainer,
                                        borderRadius: kOpenHandBorderRadius4,
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
                                    kOpenHandHGap8,
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
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: r.ok
                                              ? cs.tertiaryContainer
                                              : cs.errorContainer,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
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
                                kOpenHandGap4,
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
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      r.bodyPreview,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily:
                                            kOpenHandMonospaceFontFamily,
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
          buildOpenHandDialogActionsBar(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            leading: Text(
              _busy
                  ? (loc?.webReverseReplayProgress(_progress, _total) ??
                        'Replaying $_progress / $_total')
                  : (loc?.webReverseReplaySelected(
                          _selected.length,
                          entries.length,
                        ) ??
                        'Selected ${_selected.length} / ${entries.length}'),
              style: theme.textTheme.labelMedium,
            ),
            actions: [
              OpenHandDialogActionButton.secondary(
                label: loc?.webReverseReplayRunBatch ?? 'Run Batch',
                icon: Icons.send_rounded,
                busy: _busy,
                onPressed: (_busy || _selected.isEmpty) ? null : _runBatch,
              ),
              OpenHandDialogActionButton.primary(
                label: loc?.webReverseReplayClose ?? 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

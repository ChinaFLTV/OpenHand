/// Console 错误聚类面板。
///
/// 把 `controller.consoleMessages` 按 (level + 归一化文案首行 + URL 片段)
/// 聚成簇，按出现次数倒序展示。点击展开看原始条目。
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseConsoleClusterDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _ConsoleClusterDialog(controller: controller),
  );
}

class _Cluster {
  _Cluster({
    required this.signature,
    required this.level,
    required this.firstLine,
  });
  final String signature;
  final String level;
  final String firstLine;
  final List<CdpConsoleEntry> entries = [];
  DateTime? get first => entries.isEmpty ? null : entries.first.timestamp;
  DateTime? get last => entries.isEmpty ? null : entries.last.timestamp;
}

class _ConsoleClusterDialog extends StatefulWidget {
  const _ConsoleClusterDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_ConsoleClusterDialog> createState() => _ConsoleClusterDialogState();
}

class _ConsoleClusterDialogState extends State<_ConsoleClusterDialog> {
  String _levelFilter = 'all';
  String _query = '';
  final Set<String> _expanded = <String>{};

  List<_Cluster> _build() {
    final map = <String, _Cluster>{};
    for (final e in widget.controller.consoleMessages) {
      if (_levelFilter != 'all' && e.level != _levelFilter) continue;
      if (_query.isNotEmpty &&
          !e.text.toLowerCase().contains(_query.toLowerCase())) {
        continue;
      }
      final sig = '${e.level}|${normalizeConsoleSignature(e.text)}';
      final c = map.putIfAbsent(
        sig,
        () => _Cluster(
          signature: sig,
          level: e.level,
          firstLine: e.text.split('\n').first.trim(),
        ),
      );
      c.entries.add(e);
    }
    final list = map.values.toList()
      ..sort((a, b) => b.entries.length.compareTo(a.entries.length));
    return list;
  }

  Color _colorFor(String lvl, ColorScheme cs) {
    switch (lvl) {
      case 'error':
        return cs.error;
      case 'warning':
        return Colors.amber.shade700;
      case 'info':
        return cs.tertiary;
      default:
        return cs.onSurfaceVariant;
    }
  }

  Future<void> _copyCluster(_Cluster c) async {
    final payload = {
      'signature': c.signature,
      'level': c.level,
      'count': c.entries.length,
      'firstAt': c.first?.toIso8601String(),
      'lastAt': c.last?.toIso8601String(),
      'samples': c.entries
          .take(20)
          .map((e) => {'ts': e.timestamp.toIso8601String(), 'text': e.text})
          .toList(),
    };
    await copyWebReverseTextToClipboard(
      context: context,
      text: prettyPrintJson(payload),
      successBase:
          AppLocalizations.of(context)?.webReverseConsoleClusterCopied ??
          'Cluster JSON copied',
      logTag: 'web_reverse_console_cluster_dialog',
      logAction: '复制控制台聚类结果',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final clusters = _build();
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: kOpenHandDialogHeightTall,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.bug_report_rounded,
            title: loc?.webReverseConsoleClusterTitle ?? 'Console Clusters',
            subtitle:
                loc?.webReverseConsoleClusterSubtitle(
                  widget.controller.consoleMessageCount,
                  clusters.length,
                ) ??
                'dedupe by level + normalized first line · ${widget.controller.consoleMessageCount} entries / ${clusters.length} clusters',
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            actions: [
              IconButton(
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh_rounded),
                tooltip: loc?.webReverseConsoleClusterRefresh ?? 'Refresh',
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    for (final lvl in const [
                      'all',
                      'error',
                      'warning',
                      'info',
                      'log',
                    ])
                      ChoiceChip(
                        label: Text(lvl),
                        selected: _levelFilter == lvl,
                        onSelected: (_) => setState(() => _levelFilter = lvl),
                      ),
                  ],
                ),
                kOpenHandHGap12,
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText:
                          loc?.webReverseConsoleClusterFilterHint ?? 'filter',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: clusters.isEmpty
                ? OpenHandInlineEmptyState(
                    message:
                        loc?.webReverseConsoleClusterNoMatch ??
                        'No matching entries',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: clusters.length,
                    itemBuilder: (_, i) {
                      final c = clusters[i];
                      final open = _expanded.contains(c.signature);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: webReverseSurfaceCardDecoration(cs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              borderRadius: kOpenHandBorderRadius10,
                              onTap: () => setState(() {
                                if (open) {
                                  _expanded.remove(c.signature);
                                } else {
                                  _expanded.add(c.signature);
                                }
                              }),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _colorFor(
                                          c.level,
                                          cs,
                                        ).withValues(alpha: 0.15),
                                        borderRadius: kOpenHandBorderRadius10,
                                      ),
                                      child: Text(
                                        c.level,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _colorFor(c.level, cs),
                                        ),
                                      ),
                                    ),
                                    kOpenHandHGap10,
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.primaryContainer.withValues(
                                          alpha: 0.5,
                                        ),
                                        borderRadius: kOpenHandBorderRadius10,
                                      ),
                                      child: Text(
                                        '× ${c.entries.length}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    kOpenHandHGap10,
                                    Expanded(
                                      child: Text(
                                        c.firstLine,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily:
                                              kOpenHandMonospaceFontFamily,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.copy_rounded,
                                        size: 16,
                                      ),
                                      tooltip:
                                          loc?.webReverseConsoleClusterCopyJson ??
                                          'Copy JSON',
                                      onPressed: () => _copyCluster(c),
                                    ),
                                    Icon(
                                      open
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (open)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      loc?.webReverseConsoleClusterTimes(
                                            c.first?.toIso8601String() ?? '',
                                            c.last?.toIso8601String() ?? '',
                                          ) ??
                                          'first: ${c.first?.toIso8601String()}\nlast: ${c.last?.toIso8601String()}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                    kOpenHandGap6,
                                    for (final e in c.entries.take(30))
                                      Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: cs.surface,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: cs.outlineVariant,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              e.timestamp
                                                  .toIso8601String()
                                                  .substring(11, 23),
                                              style: TextStyle(
                                                fontFamily:
                                                    kOpenHandMonospaceFontFamily,
                                                fontSize: 10,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                            kOpenHandGap2,
                                            SelectableText(
                                              e.text,
                                              style: const TextStyle(
                                                fontFamily:
                                                    kOpenHandMonospaceFontFamily,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (c.entries.length > 30)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          loc?.webReverseConsoleClusterMore(
                                                c.entries.length - 30,
                                              ) ??
                                              '… and ${c.entries.length - 30} more',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          buildOpenHandDialogFooter(
            primaryLabel: loc?.commonClose ?? 'Close',
            onPrimaryPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

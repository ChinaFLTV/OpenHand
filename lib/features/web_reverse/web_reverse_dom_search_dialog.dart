/// DOM 选择器搜索面板。
///
/// `DOM.performSearch` 接受 CSS selector / 纯文本 / XPath，返回 searchId +
/// resultCount；再以 `DOM.getSearchResults` 拉一批 nodeId 出来逐个 describe。
/// 每行右侧的瞄准按钮调用 `domHighlightNode` 在页面里画 inspector 框。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseDomSearchDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _DomSearchDialog(controller: controller),
  );
}

class _DomSearchDialog extends StatefulWidget {
  const _DomSearchDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_DomSearchDialog> createState() => _DomSearchDialogState();
}

class _Hit {
  _Hit({required this.nodeId, required this.label, required this.detail});
  final int nodeId;
  final String label;
  final String detail;
}

class _DomSearchDialogState extends State<_DomSearchDialog> {
  static const int _maxQueryChars = 16 * 1024;
  static const int _maxSearchIdChars = kBytesPerKiB;
  static const int _maxResults = 200;
  static const int _describeConcurrency = 4;
  static const Duration _commandTimeout = Duration(seconds: 6);
  static const Duration _describeWindow = Duration(seconds: 30);

  final _queryCtrl = TextEditingController();
  String _status = '';
  bool _busy = false;
  List<_Hit> _hits = [];
  int _resultCount = 0;
  int _searchSerial = 0;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final loc = AppLocalizations.of(context);
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) return;
    if (q.length > _maxQueryChars) {
      setState(() => _status = 'Query is too long.');
      return;
    }
    final serial = ++_searchSerial;
    final targetId = widget.controller.currentPageTargetId;
    String? activeSearchId;
    setState(() {
      _busy = true;
      _status = loc?.webReverseDomSearchSearching ?? 'Searching...';
      _hits = [];
    });
    try {
      await widget.controller.sendRawCdp(
        method: 'DOM.enable',
        timeout: _commandTimeout,
      );
      final r = await widget.controller.sendRawCdp(
        method: 'DOM.performSearch',
        paramsJson: jsonEncode({
          'query': q,
          'includeUserAgentShadowDOM': false,
        }),
        timeout: _commandTimeout,
      );
      if (r == null || r['error'] != null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status =
              loc?.webReverseDomSearchFailed('${r?['error'] ?? 'unknown'}') ??
              'Failed: ${r?['error'] ?? 'unknown'}';
        });
        return;
      }
      activeSearchId = '${r['searchId'] ?? ''}'.trim();
      _resultCount = (r['resultCount'] is num)
          ? (r['resultCount'] as num).toInt()
          : 0;
      if (activeSearchId.isEmpty ||
          activeSearchId.length > _maxSearchIdChars ||
          _resultCount <= 0) {
        if (activeSearchId.length > _maxSearchIdChars) activeSearchId = null;
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = loc?.webReverseDomSearchNoMatches ?? 'No matches';
        });
        return;
      }
      final toIndex = _resultCount > _maxResults ? _maxResults : _resultCount;
      final batch = await widget.controller.sendRawCdp(
        method: 'DOM.getSearchResults',
        paramsJson: jsonEncode({
          'searchId': activeSearchId,
          'fromIndex': 0,
          'toIndex': toIndex,
        }),
        timeout: _commandTimeout,
      );
      if (batch == null || batch['error'] != null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status =
              loc?.webReverseDomSearchGetFailed('${batch?['error']}') ??
              'getSearchResults failed';
        });
        return;
      }
      final ids = <int>[];
      final seenIds = <int>{};
      final raw = batch['nodeIds'];
      if (raw is List) {
        for (final v in raw) {
          if (v is num && v.isFinite) {
            final id = v.toInt();
            if (id > 0 && seenIds.add(id)) ids.add(id);
          }
        }
      }
      final results = List<_Hit?>.filled(ids.length, null);
      final deadline = MonotonicDeadline(_describeWindow);
      try {
        await forEachIndexWithConcurrencyLimit(
          itemCount: ids.length,
          maxConcurrency: _describeConcurrency,
          shouldContinue: () =>
              mounted &&
              serial == _searchSerial &&
              widget.controller.currentPageTargetId == targetId &&
              !deadline.isExpired,
          task: (index) async {
            final id = ids[index];
            try {
              final desc = await widget.controller.domDescribeNode(id);
              if (desc == null) return;
              final node = desc;
              final nodeName = (node['nodeName'] ?? '?')
                  .toString()
                  .toLowerCase();
              final attrs = node['attributes'];
              final attrMap = <String, String>{};
              if (attrs is List) {
                for (var i = 0; i + 1 < attrs.length; i += 2) {
                  attrMap['${attrs[i]}'] = '${attrs[i + 1]}';
                }
              }
              final idAttr = attrMap['id'];
              final classAttr = attrMap['class'];
              final label = StringBuffer('<$nodeName');
              if (idAttr != null && idAttr.isNotEmpty) {
                label.write(' id="$idAttr"');
              }
              if (classAttr != null && classAttr.isNotEmpty) {
                final cls = clipTextByCodeUnits(classAttr, 60, suffix: '…');
                label.write(' class="$cls"');
              }
              label.write('>');
              final detail = attrMap.entries
                  .where((e) => e.key != 'id' && e.key != 'class')
                  .take(4)
                  .map((e) {
                    final v = clipTextByCodeUnits(e.value, 40, suffix: '…');
                    return '${e.key}="$v"';
                  })
                  .join(' ');
              results[index] = _Hit(
                nodeId: id,
                label: label.toString(),
                detail: detail,
              );
            } catch (e, st) {
              silentLog('web_reverse_dom_search_dialog', '描述 DOM 搜索节点', e, st);
            }
          },
        );
      } finally {
        deadline.stop();
      }
      if (!mounted || serial != _searchSerial) return;
      if (widget.controller.currentPageTargetId != targetId) {
        setState(() {
          _busy = false;
          _status = 'Page changed. Run the search again.';
        });
        return;
      }
      final hits = results.whereType<_Hit>().toList(growable: false);
      setState(() {
        _busy = false;
        _hits = hits;
        _status =
            loc?.webReverseDomSearchHitCount(_resultCount, hits.length) ??
            'Matched $_resultCount, showing top ${hits.length}';
      });
    } catch (e, st) {
      silentLog('web_reverse_dom_search_dialog', '执行 DOM 搜索', e, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Error: $e';
      });
    } finally {
      if (activeSearchId != null && activeSearchId.isNotEmpty) {
        await widget.controller.sendRawCdp(
          method: 'DOM.discardSearchResults',
          paramsJson: jsonEncode(<String, Object?>{'searchId': activeSearchId}),
          timeout: _commandTimeout,
        );
      }
    }
  }

  Future<void> _highlight(int id) async {
    try {
      await widget.controller.sendRawCdp(method: 'Overlay.enable');
      await widget.controller.domHighlightNode(id);
    } catch (e, st) {
      silentLog('web_reverse_dom_search_dialog', '高亮 DOM 搜索结果', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.travel_explore_rounded,
            title: loc?.webReverseDomSearchTitle ?? 'DOM Selector Search',
            subtitle: 'DOM.performSearch · CSS / text / XPath',
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText:
                          loc?.webReverseDomSearchHint ??
                          'selector / text / XPath, Enter to run',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: const OutlineInputBorder(borderRadius: kOpenHandBorderRadius10),
                    ),
                    onSubmitted: _busy ? null : (_) => _runSearch(),
                  ),
                ),
                kOpenHandHGap8,
                FilledButton.icon(
                  onPressed: _busy ? null : _runSearch,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(loc?.webReverseDomSearchRun ?? 'Run'),
                ),
              ],
            ),
          ),
          OpenHandBusyProgressBar(busy: _busy),
          Expanded(
            child: _hits.isEmpty
                ? OpenHandInlineEmptyState(
                    message: _status.isEmpty
                        ? (loc?.webReverseDomSearchExample ??
                              'e.g. button[data-action] · #login · //a[contains(@href,"docs")]')
                        : _status,
                    dense: true,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _hits.length,
                    itemBuilder: (_, i) {
                      final h = _hits[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: webReverseSurfaceCardDecoration(cs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    h.label,
                                    style: const TextStyle(
                                      fontFamily: kOpenHandMonospaceFontFamily,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (h.detail.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        h.detail,
                                        style: TextStyle(
                                          fontFamily:
                                              kOpenHandMonospaceFontFamily,
                                          fontSize: 10,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      'nodeId=${h.nodeId}',
                                      style: TextStyle(
                                        fontFamily:
                                            kOpenHandMonospaceFontFamily,
                                        fontSize: 10,
                                        color: cs.onSurfaceVariant.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _highlight(h.nodeId),
                              icon: const Icon(
                                Icons.center_focus_strong_rounded,
                              ),
                              tooltip:
                                  loc?.webReverseDomSearchHighlight ??
                                  'Highlight in page',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (_status.isNotEmpty && _hits.isNotEmpty)
            Container(
              width: double.infinity,
              color: cs.surfaceContainerHigh,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                _status,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
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

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
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseDomSearchDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showAnimatedDialog<void>(
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
  final _queryCtrl = TextEditingController();
  String _status = '';
  bool _busy = false;
  List<_Hit> _hits = [];
  String? _searchId;
  int _resultCount = 0;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final loc = AppLocalizations.of(context);
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _status = loc?.webReverseDomSearchSearching ?? 'Searching...';
      _hits = [];
    });
    try {
      await widget.controller.sendRawCdp(method: 'DOM.enable');
      final r = await widget.controller.sendRawCdp(
        method: 'DOM.performSearch',
        paramsJson: jsonEncode({
          'query': q,
          'includeUserAgentShadowDOM': false,
        }),
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
      _searchId = '${r['searchId'] ?? ''}';
      _resultCount = (r['resultCount'] is num)
          ? (r['resultCount'] as num).toInt()
          : 0;
      if (_searchId == null || _searchId!.isEmpty || _resultCount == 0) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = loc?.webReverseDomSearchNoMatches ?? 'No matches';
        });
        return;
      }
      // 拉前 200 条结果，避免一次过载。
      final toIndex = _resultCount > 200 ? 200 : _resultCount;
      final batch = await widget.controller.sendRawCdp(
        method: 'DOM.getSearchResults',
        paramsJson: jsonEncode({
          'searchId': _searchId,
          'fromIndex': 0,
          'toIndex': toIndex,
        }),
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
      final raw = batch['nodeIds'];
      if (raw is List) {
        for (final v in raw) {
          if (v is num) ids.add(v.toInt());
        }
      }
      final hits = <_Hit>[];
      for (final id in ids) {
        try {
          final desc = await widget.controller.domDescribeNode(id);
          if (desc == null) continue;
          final node = desc['node'] as Map?;
          if (node == null) continue;
          final nodeName = (node['nodeName'] ?? '?').toString().toLowerCase();
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
            final cls = classAttr.length > 60
                ? '${classAttr.substring(0, 60)}…'
                : classAttr;
            label.write(' class="$cls"');
          }
          label.write('>');
          final detail = attrMap.entries
              .where((e) => e.key != 'id' && e.key != 'class')
              .take(4)
              .map((e) {
                final v = e.value.length > 40
                    ? '${e.value.substring(0, 40)}…'
                    : e.value;
                return '${e.key}="$v"';
              })
              .join(' ');
          hits.add(_Hit(nodeId: id, label: label.toString(), detail: detail));
        } catch (e, st) {
          silentLog(
            'web_reverse_dom_search_dialog',
            'dom-search.describe',
            e,
            st,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _hits = hits;
        _status =
            loc?.webReverseDomSearchHitCount(_resultCount, hits.length) ??
            'Matched $_resultCount, showing top ${hits.length}';
      });
    } catch (e, st) {
      silentLog('web_reverse_dom_search_dialog', 'dom-search.run', e, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _highlight(int id) async {
    try {
      await widget.controller.sendRawCdp(method: 'Overlay.enable');
      await widget.controller.domHighlightNode(id);
    } catch (e, st) {
      silentLog('web_reverse_dom_search_dialog', 'dom-search.highlight', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 820,
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: _busy ? null : (_) => _runSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _runSearch,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(loc?.webReverseDomSearchRun ?? 'Run'),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 3),
          Expanded(
            child: _hits.isEmpty
                ? Center(
                    child: Text(
                      _status.isEmpty
                          ? (loc?.webReverseDomSearchExample ??
                                'e.g. button[data-action] · #login · //a[contains(@href,"docs")]')
                          : _status,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _hits.length,
                    itemBuilder: (_, i) {
                      final h = _hits[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.outlineVariant),
                        ),
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
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (h.detail.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        h.detail,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
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
                                        fontFamily: 'monospace',
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

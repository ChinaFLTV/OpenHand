/// 本地 Mock 拦截面板。
///
/// 维护一组 mock 规则（id + 名称 + URL 通配 + 可选 method 过滤 + 状态码 +
/// content-type + body）。命中后由控制器 `Fetch.fulfillRequest` 直接短路网络
/// 层，浏览器侧看到的就是 mock 出的响应。也展示最近 200 次命中记录。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseMockRulesDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _MockRulesDialog(controller: controller, isZh: isZh),
  );
}

class _MockRulesDialog extends StatefulWidget {
  const _MockRulesDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_MockRulesDialog> createState() => _MockRulesDialogState();
}

class _MockRulesDialogState extends State<_MockRulesDialog> {
  late List<WebReverseMockRule> _draft;
  int _selected = -1;

  @override
  void initState() {
    super.initState();
    _draft = List<WebReverseMockRule>.from(widget.controller.mockRules);
    if (_draft.isNotEmpty) _selected = 0;
    widget.controller.addListener(_onCtrl);
  }

  void _onCtrl() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    super.dispose();
  }

  void _commit() {
    widget.controller.setMockRules(_draft);
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      final loc = AppLocalizations.of(context);
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        loc?.webReverseMockRulesSavedCount(_draft.length) ??
            'Saved ${_draft.length} rule(s)',
      );
    }
  }

  void _addRule() {
    final loc = AppLocalizations.of(context);
    setState(() {
      _draft.add(
        WebReverseMockRule(
          id: 'mk_${DateTime.now().microsecondsSinceEpoch}',
          name: loc?.webReverseMockRulesNewRule ?? 'New rule',
          urlPattern: 'https://api.example.com/*',
        ),
      );
      _selected = _draft.length - 1;
    });
  }

  void _removeAt(int i) {
    setState(() {
      _draft.removeAt(i);
      if (_selected >= _draft.length) _selected = _draft.length - 1;
    });
  }

  Future<void> _exportJson() async {
    final out = const JsonEncoder.withIndent(
      '  ',
    ).convert(_draft.map((e) => e.toJson()).toList());
    final loc = AppLocalizations.of(context);
    final m = ScaffoldMessenger.maybeOf(context);
    final copied = await setWebReverseClipboardText(out);
    if (!mounted) return;
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        webReverseClipboardSnackMessage(
          isZh: widget.isZh,
          base: loc?.webReverseMockRulesJsonCopied ?? 'JSON copied',
          result: copied,
        ),
      );
    }
  }

  Future<void> _importJson() async {
    final loc = AppLocalizations.of(context);
    final m = ScaffoldMessenger.maybeOf(context);
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text ?? '';
      final decoded = jsonDecode(text);
      if (decoded is! List) throw Exception('expected array');
      if (!mounted) return;
      setState(() {
        _draft = decoded
            .whereType<Map>()
            .map(
              (e) => WebReverseMockRule.fromJson(Map<String, Object?>.from(e)),
            )
            .toList();
        _selected = _draft.isEmpty ? -1 : 0;
      });
      if (m != null) {
        OpenHandSnackBar.showSuccessOn(
          context,
          m,
          loc?.webReverseMockRulesImportedCount(_draft.length) ??
              'Imported ${_draft.length}',
        );
      }
    } catch (e, st) {
      silentLog('web_reverse_mock_rules', 'import', e, st);
      if (!mounted) return;
      if (m != null) {
        OpenHandSnackBar.showErrorOn(
          context,
          m,
          loc?.webReverseMockRulesImportFailed('$e') ?? 'Import failed: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final hits = widget.controller.mockHits;

    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.alt_route_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc?.webReverseMockRulesTitle ?? 'Local Mock',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          loc?.webReverseMockRulesSubtitle ??
                              'URL pattern match → Fetch.fulfillRequest returns a canned response',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip:
                        loc?.webReverseMockRulesExportJson ?? 'Export JSON',
                    onPressed: _exportJson,
                    icon: const Icon(Icons.upload_rounded),
                  ),
                  IconButton(
                    tooltip:
                        loc?.webReverseMockRulesImportJson ?? 'Import JSON',
                    onPressed: _importJson,
                    icon: const Icon(Icons.download_rounded),
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
              child: Row(
                children: [
                  SizedBox(
                    width: 320,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                          child: Row(
                            children: [
                              Text(
                                '${loc?.webReverseMockRulesListLabel ?? 'Rules'} (${_draft.length})',
                                style: theme.textTheme.labelMedium,
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: loc?.webReverseMockRulesAdd ?? 'Add',
                                onPressed: _addRule,
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _draft.isEmpty
                              ? Center(
                                  child: Text(
                                    loc?.webReverseMockRulesEmptyRules ??
                                        'No rules',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  itemCount: _draft.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 4),
                                  itemBuilder: (_, i) {
                                    final r = _draft[i];
                                    final sel = i == _selected;
                                    return Material(
                                      color: sel
                                          ? cs.primaryContainer.withValues(
                                              alpha: 0.4,
                                            )
                                          : cs.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(8),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () =>
                                            setState(() => _selected = i),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            8,
                                            6,
                                            4,
                                            6,
                                          ),
                                          child: Row(
                                            children: [
                                              Switch(
                                                value: r.enabled,
                                                onChanged: (v) => setState(() {
                                                  _draft[i] = r.copyWith(
                                                    enabled: v,
                                                  );
                                                }),
                                              ),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      r.name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme
                                                          .labelMedium,
                                                    ),
                                                    Text(
                                                      r.urlPattern,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: cs
                                                                .onSurfaceVariant,
                                                            fontFamily:
                                                                'monospace',
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                tooltip:
                                                    loc?.webReverseMockRulesDelete ??
                                                    'Delete',
                                                onPressed: () => _removeAt(i),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 16,
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
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  Expanded(
                    child: _selected < 0 || _selected >= _draft.length
                        ? Center(
                            child: Text(
                              loc?.webReverseMockRulesPickRule ??
                                  'Pick a rule on the left',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        : _RuleEditor(
                            key: ValueKey(_draft[_selected].id),
                            rule: _draft[_selected],
                            onChanged: (updated) {
                              setState(() => _draft[_selected] = updated);
                            },
                          ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            SizedBox(
              height: 110,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          loc?.webReverseMockRulesHits ?? 'Hits',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${hits.length})',
                          style: theme.textTheme.labelSmall,
                        ),
                        const Spacer(),
                        if (hits.isNotEmpty)
                          TextButton.icon(
                            onPressed: widget.controller.clearMockHits,
                            icon: const Icon(
                              Icons.cleaning_services_rounded,
                              size: 14,
                            ),
                            label: Text(
                              loc?.webReverseMockRulesClear ?? 'Clear',
                            ),
                          ),
                      ],
                    ),
                    Expanded(
                      child: hits.isEmpty
                          ? Center(
                              child: Text(
                                loc?.webReverseMockRulesNoHits ?? 'No hits yet',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: hits.length,
                              itemBuilder: (_, i) {
                                final h = hits[i];
                                return Text(
                                  '${_fmt(h.at)}  '
                                  '${h.status}  '
                                  '${h.ruleName}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OpenHandDialogActionButton.secondary(
                    label: loc?.webReverseMockRulesClose ?? 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  OpenHandDialogActionButton.primary(
                    label: loc?.webReverseMockRulesSaveApply ?? 'Save & Apply',
                    onPressed: _commit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({super.key, required this.rule, required this.onChanged});
  final WebReverseMockRule rule;
  final ValueChanged<WebReverseMockRule> onChanged;
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late TextEditingController _name;
  late TextEditingController _pattern;
  late TextEditingController _method;
  late TextEditingController _status;
  late TextEditingController _contentType;
  late TextEditingController _body;
  late TextEditingController _headers;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.rule.name);
    _pattern = TextEditingController(text: widget.rule.urlPattern);
    _method = TextEditingController(text: widget.rule.methodFilter);
    _status = TextEditingController(text: '${widget.rule.statusCode}');
    _contentType = TextEditingController(text: widget.rule.contentType);
    _body = TextEditingController(text: widget.rule.body);
    _headers = TextEditingController(
      text: widget.rule.extraHeaders.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n'),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    _method.dispose();
    _status.dispose();
    _contentType.dispose();
    _body.dispose();
    _headers.dispose();
    super.dispose();
  }

  void _push() {
    final hdrs = <String, String>{};
    for (final line in _headers.text.split('\n')) {
      final s = line.trim();
      if (s.isEmpty) continue;
      final idx = s.indexOf(':');
      if (idx <= 0) continue;
      hdrs[s.substring(0, idx).trim()] = s.substring(idx + 1).trim();
    }
    widget.onChanged(
      widget.rule.copyWith(
        name: _name.text,
        urlPattern: _pattern.text,
        methodFilter: _method.text,
        statusCode: int.tryParse(_status.text) ?? widget.rule.statusCode,
        contentType: _contentType.text,
        body: _body.text,
        extraHeaders: hdrs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            onChanged: (_) => _push(),
            decoration: InputDecoration(
              labelText: loc?.webReverseMockRulesRuleName ?? 'Name',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pattern,
            onChanged: (_) => _push(),
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText:
                  loc?.webReverseMockRulesUrlPattern ?? 'URL pattern (* / ?)',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _method,
                  onChanged: (_) => _push(),
                  decoration: InputDecoration(
                    labelText:
                        loc?.webReverseMockRulesMethodLabel ??
                        'Method (blank=ALL)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _status,
                  onChanged: (_) => _push(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _contentType,
                  onChanged: (_) => _push(),
                  decoration: const InputDecoration(
                    labelText: 'Content-Type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _headers,
            onChanged: (_) => _push(),
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              labelText:
                  loc?.webReverseMockRulesExtraHeaders ??
                  'Extra headers (Key: Value per line)',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            onChanged: (_) => _push(),
            minLines: 8,
            maxLines: 18,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              labelText:
                  loc?.webReverseMockRulesResponseBody ?? 'Response body',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cookie 编辑器：通过 `Network.getCookies` / `Network.setCookie` /
/// `Network.deleteCookies` 完成全量 CRUD。按 domain 分组展示，
/// 双击行直接进入编辑面板，新增亦走同一个面板。
///
/// 与「应用」tab 的 Cookies 视图互补：那里偏批量浏览，这里偏精修。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseCookieEditorDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showWebReverseToolDialog<void>(
    context: context,
    builder: (_) => _CookieEditorDialog(controller: controller),
  );
}

class _CookieRow {
  _CookieRow(this.raw);
  final Map<String, Object?> raw;

  String get name => (raw['name'] as String?) ?? '';
  String get value => (raw['value'] as String?) ?? '';
  String get domain => (raw['domain'] as String?) ?? '';
  String get path => (raw['path'] as String?) ?? '/';
  bool get httpOnly => raw['httpOnly'] == true;
  bool get secure => raw['secure'] == true;
  String get sameSite => (raw['sameSite'] as String?) ?? '';
  num? get expires => raw['expires'] as num?;
}

class _CookieEditorDialog extends StatefulWidget {
  const _CookieEditorDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_CookieEditorDialog> createState() => _CookieEditorDialogState();
}

class _CookieEditorDialogState extends State<_CookieEditorDialog> {
  bool _loading = false;
  String _filter = '';
  List<_CookieRow> _all = const [];
  String _status = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    final loc0 = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _status = loc0?.webReverseCookieEditorFetching ?? 'Fetching cookies...';
    });
    try {
      final r = await widget.controller.sendRawCdp(
        method: 'Network.getCookies',
        paramsJson: '{}',
      );
      if (!mounted) return;
      final loc1 = AppLocalizations.of(context);
      if (r == null || r['error'] != null) {
        final err = (r?['error'] ?? 'unknown').toString();
        setState(() {
          _status =
              loc1?.webReverseCookieEditorFetchFailed(err) ?? 'Failed: $err';
        });
        return;
      }
      final list = (r['cookies'] as List?) ?? const [];
      _all = stringKeyedMapListFromValue(list).map(_CookieRow.new).toList()
        ..sort((a, b) {
          final d = a.domain.compareTo(b.domain);
          if (d != 0) return d;
          return a.name.compareTo(b.name);
        });
      setState(
        () => _status =
            loc1?.webReverseCookieEditorCookieCount(_all.length) ??
            '${_all.length} cookies',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_CookieRow> get _visible {
    if (_filter.trim().isEmpty) return _all;
    final f = _filter.toLowerCase();
    return _all
        .where(
          (c) =>
              c.name.toLowerCase().contains(f) ||
              c.domain.toLowerCase().contains(f) ||
              c.value.toLowerCase().contains(f),
        )
        .toList();
  }

  Future<void> _delete(_CookieRow row) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final r = await widget.controller.sendRawCdp(
      method: 'Network.deleteCookies',
      paramsJson: jsonEncode({
        'name': row.name,
        'domain': row.domain,
        'path': row.path,
      }),
    );
    if (!mounted) return;
    final loc1 = AppLocalizations.of(context);
    if (r == null || r['error'] != null) {
      if (messenger != null) {
        OpenHandSnackBar.showErrorOn(
          context,
          messenger,
          loc1?.webReverseCookieEditorDeleteFailed ?? 'Delete failed',
        );
      }
      return;
    }
    if (messenger != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        loc1?.webReverseCookieEditorDeleted(row.name) ?? 'Deleted ${row.name}',
      );
    }
    await _refresh();
  }

  Future<void> _edit(_CookieRow? row) async {
    final result = await showWebReverseToolDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _CookieEditPanel(row: row),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final r = await widget.controller.sendRawCdp(
      method: 'Network.setCookie',
      paramsJson: jsonEncode(result),
    );
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    if (r == null || r['error'] != null || r['success'] == false) {
      if (messenger != null) {
        OpenHandSnackBar.showErrorOn(
          context,
          messenger,
          loc?.webReverseCookieEditorWriteFailed ?? 'Write failed',
        );
      }
      return;
    }
    if (messenger != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        loc?.webReverseCookieEditorSaved ?? 'Saved',
      );
    }
    await _refresh();
  }

  Future<void> _copyJson() async {
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(_visible.map((c) => c.raw).toList());
    final copied = await setWebReverseClipboardText(json);
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        webReverseClipboardSnackMessage(
          context: context,
          base: loc?.webReverseCookieEditorCopiedJson ?? 'JSON copied',
          result: copied,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final list = _visible;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 920,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.cookie_rounded,
            title: loc?.webReverseCookieEditorTitle ?? 'Cookie Editor',
            subtitle:
                loc?.webReverseCookieEditorSubtitle ??
                'Network.getCookies / setCookie / deleteCookies — full CRUD',
            actions: [
              IconButton(
                tooltip: loc?.webReverseCookieEditorRefresh ?? 'Refresh',
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: loc?.webReverseCookieEditorCopyJson ?? 'Copy JSON',
                onPressed: list.isEmpty ? null : _copyJson,
                icon: const Icon(Icons.copy_all_rounded),
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText:
                          loc?.webReverseCookieEditorFilterHint ??
                          'Filter name / domain / value',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _loading ? null : () => _edit(null),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(loc?.webReverseCookieEditorNewBtn ?? 'New'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading && list.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                ? Center(
                    child: Text(
                      loc?.webReverseCookieEditorEmptyCookies ?? 'No cookies',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return ListTile(
                        dense: true,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              c.domain,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            c.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (c.httpOnly)
                              _badge(theme, 'HttpOnly', cs.tertiary),
                            if (c.secure) _badge(theme, 'Secure', cs.primary),
                            if (c.sameSite.isNotEmpty)
                              _badge(theme, c.sameSite, cs.secondary),
                            IconButton(
                              tooltip:
                                  loc?.webReverseCookieEditorEdit ?? 'Edit',
                              onPressed: () => _edit(c),
                              icon: const Icon(Icons.edit_rounded, size: 16),
                            ),
                            IconButton(
                              tooltip:
                                  loc?.webReverseCookieEditorDelete ?? 'Delete',
                              onPressed: () => _delete(c),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _edit(c),
                      );
                    },
                  ),
          ),
          buildWebReverseStatusBar(
            context,
            status: _status,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          ),
        ],
      ),
    );
  }

  Widget _badge(ThemeData theme, String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _CookieEditPanel extends StatefulWidget {
  const _CookieEditPanel({required this.row});
  final _CookieRow? row;
  @override
  State<_CookieEditPanel> createState() => _CookieEditPanelState();
}

class _CookieEditPanelState extends State<_CookieEditPanel> {
  late final TextEditingController _name;
  late final TextEditingController _value;
  late final TextEditingController _domain;
  late final TextEditingController _path;
  late final TextEditingController _url;
  late final TextEditingController _expires;
  bool _httpOnly = false;
  bool _secure = false;
  String _sameSite = '';

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _name = TextEditingController(text: r?.name ?? '');
    _value = TextEditingController(text: r?.value ?? '');
    _domain = TextEditingController(text: r?.domain ?? '');
    _path = TextEditingController(text: r?.path ?? '/');
    _url = TextEditingController();
    _expires = TextEditingController(
      text: r?.expires == null ? '' : r!.expires!.toString(),
    );
    _httpOnly = r?.httpOnly ?? false;
    _secure = r?.secure ?? false;
    _sameSite = r?.sameSite ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _domain.dispose();
    _path.dispose();
    _url.dispose();
    _expires.dispose();
    super.dispose();
  }

  void _submit() {
    final loc = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      final m = ScaffoldMessenger.maybeOf(context);
      if (m != null) {
        OpenHandSnackBar.showErrorOn(
          context,
          m,
          loc?.webReverseCookieEditorNameRequired ?? 'name required',
        );
      }
      return;
    }
    final out = <String, Object?>{
      'name': name,
      'value': _value.text,
      if (_domain.text.trim().isNotEmpty) 'domain': _domain.text.trim(),
      if (_path.text.trim().isNotEmpty) 'path': _path.text.trim(),
      if (_url.text.trim().isNotEmpty) 'url': _url.text.trim(),
      if (_httpOnly) 'httpOnly': true,
      if (_secure) 'secure': true,
      if (_sameSite.isNotEmpty) 'sameSite': _sameSite,
    };
    final exp = optionalDoubleFromValue(_expires.text);
    if (exp != null) out['expires'] = exp;
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final title = widget.row == null
        ? (loc?.webReverseCookieEditorNewCookie ?? 'New Cookie')
        : (loc?.webReverseCookieEditorEditCookie(widget.row!.name) ??
              'Edit ${widget.row!.name}');
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 560,
      maxHeight: 680,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: widget.row == null
                ? Icons.add_circle_outline_rounded
                : Icons.edit_rounded,
            title: title,
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(
                    loc?.webReverseCookieEditorFieldName ?? 'name *',
                    _name,
                  ),
                  _field(
                    loc?.webReverseCookieEditorFieldValue ?? 'value',
                    _value,
                    maxLines: 4,
                  ),
                  _field(
                    loc?.webReverseCookieEditorFieldDomain ?? 'domain',
                    _domain,
                    hint: '.example.com',
                  ),
                  _field(loc?.webReverseCookieEditorFieldPath ?? 'path', _path),
                  _field(
                    loc?.webReverseCookieEditorFieldUrl ?? 'URL (optional)',
                    _url,
                    hint: 'https://...',
                  ),
                  _field(
                    loc?.webReverseCookieEditorFieldExpires ??
                        'expires (unix sec)',
                    _expires,
                    hint: '1700000000',
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          value: _httpOnly,
                          onChanged: (v) =>
                              setState(() => _httpOnly = v ?? false),
                          title: const Text('HttpOnly'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          value: _secure,
                          onChanged: (v) =>
                              setState(() => _secure = v ?? false),
                          title: const Text('Secure'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('SameSite', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: ['', 'Strict', 'Lax', 'None']
                        .map(
                          (s) => ChoiceChip(
                            label: Text(
                              s.isEmpty
                                  ? (loc?.webReverseCookieEditorSameSiteUnset ??
                                        'unset')
                                  : s,
                            ),
                            selected: _sameSite == s,
                            onSelected: (_) => setState(() => _sameSite = s),
                          ),
                        )
                        .toList(),
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
                  onPressed: () => Navigator.of(context).pop(),
                  label: loc?.webReverseCookieEditorCancel ?? 'Cancel',
                ),
                const SizedBox(width: 8),
                OpenHandDialogActionButton.primary(
                  onPressed: _submit,
                  label: loc?.webReverseCookieEditorSave ?? 'Save',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    String? hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
      ),
    );
  }
}

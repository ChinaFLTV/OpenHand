/// Cookie 编辑器：通过控制器封装的 `Network.getCookies` / `Network.setCookie` /
/// `Network.deleteCookies` 完成常用字段 CRUD。按 domain 分组展示，
/// 双击行直接进入编辑面板，新增亦走同一个面板。
///
/// 与「应用」tab 的 Cookies 视图互补：那里偏批量浏览，这里偏精修。
library;

import 'dart:async';
import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseCookieEditorDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
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
  bool get canMutate => raw['partitionKeyOpaque'] != true;
  Map<String, Object?>? get partitionKey => raw['partitionKey'] is Map
      ? stringKeyedMapFromValue(raw['partitionKey'])
      : null;
}

class _CookieEditorDialog extends StatefulWidget {
  const _CookieEditorDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_CookieEditorDialog> createState() => _CookieEditorDialogState();
}

class _CookieEditorDialogState extends State<_CookieEditorDialog> {
  bool _loading = false;
  bool _refreshPending = false;
  Future<void>? _refreshTask;
  bool _mutating = false;
  String _filter = '';
  List<_CookieRow> _all = const [];
  String _status = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() {
    if (!mounted) return Future<void>.value();
    _refreshPending = true;
    final activeTask = _refreshTask;
    if (activeTask != null) return activeTask;
    final loc0 = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _status = loc0?.webReverseCookieEditorFetching ?? 'Fetching cookies...';
    });
    late final Future<void> task;
    task = _drainRefreshRequests().whenComplete(() {
      if (!identical(_refreshTask, task)) return;
      _refreshTask = null;
      if (mounted) setState(() => _loading = false);
    });
    _refreshTask = task;
    return task;
  }

  Future<void> _drainRefreshRequests() async {
    while (mounted && _refreshPending) {
      _refreshPending = false;
      try {
        final cookies = await widget.controller.listCookies(all: false);
        if (!mounted) return;
        if (_refreshPending) continue;
        final rows = cookies.map(_CookieRow.new).toList()
          ..sort((a, b) {
            final domainOrder = a.domain.compareTo(b.domain);
            return domainOrder != 0 ? domainOrder : a.name.compareTo(b.name);
          });
        final loc = AppLocalizations.of(context);
        setState(() {
          _all = rows;
          _status =
              loc?.webReverseCookieEditorCookieCount(rows.length) ??
              '${rows.length} cookies';
        });
      } catch (error, stack) {
        silentLog('web_reverse_cookie_editor', '刷新 Cookie 列表', error, stack);
        if (!mounted) return;
        if (_refreshPending) continue;
        final loc = AppLocalizations.of(context);
        setState(() {
          _status =
              '${loc?.webReverseCookieEditorRefresh ?? 'Refresh'}: $error';
        });
      }
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
    final loc = AppLocalizations.of(context);
    await _runMutation(
      action: () => widget.controller.deleteCookie(
        name: row.name,
        domain: row.domain,
        path: row.path,
        partitionKey: row.partitionKey,
      ),
      successMessage:
          loc?.webReverseCookieEditorDeleted(row.name) ?? 'Deleted ${row.name}',
      failureMessage:
          loc?.webReverseCookieEditorDeleteFailed ?? 'Delete failed',
      logAction: '删除 Cookie',
    );
  }

  Future<void> _edit(_CookieRow? row) async {
    final result = await webReverseToolDialogs.show<Map<String, Object?>>(
      context: context,
      builder: (_) => _CookieEditPanel(row: row),
    );
    if (result == null || !mounted) return;
    final loc = AppLocalizations.of(context);
    await _runMutation(
      action: () => widget.controller.setCookie(
        name: '${result['name'] ?? ''}',
        value: '${result['value'] ?? ''}',
        url: result['url'] as String?,
        domain: result['domain'] as String?,
        path: result['path'] as String?,
        partitionKey: result['partitionKey'] is Map
            ? stringKeyedMapFromValue(result['partitionKey'])
            : null,
        httpOnly: result['httpOnly'] as bool?,
        secure: result['secure'] as bool?,
        sameSite: result['sameSite'] as String?,
        expires: result['expires'] as num?,
      ),
      successMessage: loc?.webReverseCookieEditorSaved ?? 'Saved',
      failureMessage: loc?.webReverseCookieEditorWriteFailed ?? 'Write failed',
      logAction: '写入 Cookie',
    );
  }

  Future<void> _runMutation({
    required Future<bool> Function() action,
    required String successMessage,
    required String failureMessage,
    required String logAction,
  }) async {
    if (!mounted || _mutating) return;
    setState(() => _mutating = true);
    try {
      final success = await action();
      if (!mounted) return;
      if (!success) {
        showOpenHandErrorSnack(context, failureMessage);
        return;
      }
      showOpenHandSuccessSnack(context, successMessage);
      await _refresh();
    } catch (error, stack) {
      silentLog('web_reverse_cookie_editor', logAction, error, stack);
      if (mounted) showOpenHandErrorSnack(context, failureMessage);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _copyJson() async {
    final json = prettyPrintJson(_visible.map((c) => c.raw).toList());
    final loc = AppLocalizations.of(context);
    await copyWebReverseTextToClipboard(
      context: context,
      text: json,
      successBase: loc?.webReverseCookieEditorCopiedJson ?? 'JSON copied',
      logTag: 'web_reverse_cookie_editor_dialog',
      logAction: '复制 Cookie JSON',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final list = _visible;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthExtraWide,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.cookie_rounded,
            title: loc?.webReverseCookieEditorTitle ?? 'Cookie Editor',
            subtitle:
                loc?.webReverseCookieEditorSubtitle ??
                'Network.getCookies / setCookie / deleteCookies — common fields',
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
                    maxLength: 512,
                    decoration: InputDecoration(
                      hintText:
                          loc?.webReverseCookieEditorFilterHint ??
                          'Filter name / domain / value',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                      counterText: '',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _loading || _mutating ? null : () => _edit(null),
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
                ? OpenHandInlineEmptyState(
                    message:
                        loc?.webReverseCookieEditorEmptyCookies ?? 'No cookies',
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
                                  fontFamily: kOpenHandMonospaceFontFamily,
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
                              fontFamily: kOpenHandMonospaceFontFamily,
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
                            if (!c.canMutate)
                              _badge(theme, 'Opaque partition', cs.outline),
                            IconButton(
                              tooltip:
                                  loc?.webReverseCookieEditorEdit ?? 'Edit',
                              onPressed: c.canMutate && !_loading && !_mutating
                                  ? () => _edit(c)
                                  : null,
                              icon: const Icon(Icons.edit_rounded, size: 16),
                            ),
                            IconButton(
                              tooltip:
                                  loc?.webReverseCookieEditorDelete ?? 'Delete',
                              onPressed: c.canMutate && !_loading && !_mutating
                                  ? () => _delete(c)
                                  : null,
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                        onTap: c.canMutate && !_loading && !_mutating
                            ? () => _edit(c)
                            : null,
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
      showOpenHandErrorSnack(
        context,
        loc?.webReverseCookieEditorNameRequired ?? 'name required',
      );
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
      if (widget.row?.partitionKey case final partitionKey?)
        'partitionKey': partitionKey,
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
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightStandard,
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
                    maxLength: WebReverseSessionController.maxCookieNameChars,
                  ),
                  _field(
                    loc?.webReverseCookieEditorFieldValue ?? 'value',
                    _value,
                    maxLines: 4,
                    maxLength: WebReverseSessionController.maxCookieValueChars,
                  ),
                  _field(
                    loc?.webReverseCookieEditorFieldDomain ?? 'domain',
                    _domain,
                    hint: '.example.com',
                    maxLength: WebReverseSessionController.maxCookieDomainChars,
                  ),
                  _field(
                    loc?.webReverseCookieEditorFieldPath ?? 'path',
                    _path,
                    maxLength: WebReverseSessionController.maxCookiePathChars,
                  ),
                  _field(
                    loc?.webReverseCookieEditorFieldUrl ?? 'URL (optional)',
                    _url,
                    hint: 'https://...',
                    maxLength:
                        WebReverseSessionController.maxPageTargetUrlChars,
                  ),
                  _field(
                    loc?.webReverseCookieEditorFieldExpires ??
                        'expires (unix sec)',
                    _expires,
                    hint: '1700000000',
                    maxLength: 32,
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
          buildWebReverseDialogFooter(
            context,
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(context).pop(),
                label: loc?.webReverseCookieEditorCancel ?? 'Cancel',
              ),
              OpenHandDialogActionButton.primary(
                onPressed: _submit,
                label: loc?.webReverseCookieEditorSave ?? 'Save',
              ),
            ],
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
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          counterText: '',
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

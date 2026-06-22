/// 存储管理器：Cookies / LocalStorage / SessionStorage / IndexedDB。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/resizable_splitter.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseStorageDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _StorageDialog(controller: controller, isZh: isZh),
  );
}

class _StorageDialog extends StatefulWidget {
  const _StorageDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_StorageDialog> createState() => _StorageDialogState();
}

class _StorageDialogState extends State<_StorageDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String? _origin;
  bool _loading = false;

  List<Map<String, Object?>> _cookies = const [];
  List<({String key, String value})> _local = const [];
  List<({String key, String value})> _session = const [];

  List<String> _idbDbs = const [];
  String? _idbDb;
  List<String> _idbStores = const [];
  String? _idbStore;
  List<Map<String, Object?>> _idbEntries = const [];
  bool _idbHasMore = false;
  int _refreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(_onTab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshActive());
  }

  @override
  void dispose() {
    _tab.removeListener(_onTab);
    _tab.dispose();
    super.dispose();
  }

  void _onTab() {
    if (_tab.indexIsChanging) return;
    _refreshActive();
  }

  Future<void> _refreshActive() async {
    final generation = ++_refreshGeneration;
    final activeTab = _tab.index;
    if (mounted) setState(() => _loading = true);

    try {
      final resolvedOrigin = _origin ?? await widget.controller.currentOrigin();
      List<Map<String, Object?>>? cookies;
      List<({String key, String value})>? local;
      List<({String key, String value})>? session;
      List<String>? idbDbs;

      switch (activeTab) {
        case 0:
          cookies = await widget.controller.listCookies();
          break;
        case 1:
          local = resolvedOrigin == null
              ? const []
              : await widget.controller.listDomStorage(
                  origin: resolvedOrigin,
                  isLocalStorage: true,
                );
          break;
        case 2:
          session = resolvedOrigin == null
              ? const []
              : await widget.controller.listDomStorage(
                  origin: resolvedOrigin,
                  isLocalStorage: false,
                );
          break;
        case 3:
          idbDbs = await widget.controller.listIndexedDbNames();
          break;
      }

      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _origin = resolvedOrigin;
        if (cookies != null) _cookies = cookies;
        if (local != null) _local = local;
        if (session != null) _session = session;
        if (idbDbs != null) {
          _idbDbs = idbDbs;
          if (_idbDb != null && !_idbDbs.contains(_idbDb)) {
            _idbDb = null;
            _idbStores = const [];
            _idbStore = null;
            _idbEntries = const [];
          }
        }
        _loading = false;
      });
    } catch (error, stack) {
      silentLog('web_reverse_storage_dialog', 'refresh', error, stack);
      if (mounted && generation == _refreshGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _selectIdb(String db) async {
    setState(() {
      _loading = true;
      _idbDb = db;
      _idbStore = null;
      _idbEntries = const [];
    });
    try {
      final desc = await widget.controller.describeIndexedDb(db);
      if (!mounted) return;
      setState(() {
        _idbStores = desc?.stores ?? const [];
        _loading = false;
      });
    } catch (error, stack) {
      silentLog('web_reverse_storage_dialog', 'select indexeddb', error, stack);
      if (!mounted) return;
      setState(() {
        _idbStores = const [];
        _loading = false;
      });
    }
  }

  Future<void> _selectIdbStore(String store) async {
    final db = _idbDb;
    if (db == null) return;
    setState(() {
      _loading = true;
      _idbStore = store;
    });
    try {
      final res = await widget.controller.readIndexedDbStore(
        dbName: db,
        storeName: store,
      );
      if (!mounted) return;
      setState(() {
        _idbEntries = res?.entries ?? const [];
        _idbHasMore = res?.hasMore ?? false;
        _loading = false;
      });
    } catch (error, stack) {
      silentLog(
        'web_reverse_storage_dialog',
        'select indexeddb store',
        error,
        stack,
      );
      if (!mounted) return;
      setState(() {
        _idbEntries = const [];
        _idbHasMore = false;
        _loading = false;
      });
    }
  }

  Future<void> _copyJson(Object? data) async {
    final loc = AppLocalizations.of(context);
    late final WebReverseClipboardCopyResult copied;
    try {
      copied = await setWebReverseClipboardText(
        const JsonEncoder.withIndent('  ').convert(data),
      );
    } catch (err, st) {
      silentLog('web-reverse', 'storage.copy', err, st);
      return;
    }
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        webReverseClipboardSnackMessage(
          isZh: widget.isZh,
          base: loc?.webReverseStorageCopied ?? 'Copied',
          result: copied,
        ),
      );
    }
  }

  Future<void> _addCookieDialog() async {
    final loc = AppLocalizations.of(context);
    final nameCtl = TextEditingController();
    final valueCtl = TextEditingController();
    final domainCtl = TextEditingController();
    final pathCtl = TextEditingController(text: '/');
    bool secure = false;
    bool httpOnly = false;
    final ok = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return buildOpenHandDialogFormShell(
            context: ctx,
            title: loc?.webReverseStorageAddCookie ?? 'Add Cookie',
            maxWidth: 480,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                    labelText: 'name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: valueCtl,
                  decoration: const InputDecoration(
                    labelText: 'value',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: domainCtl,
                  decoration: const InputDecoration(
                    labelText: 'domain (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pathCtl,
                  decoration: const InputDecoration(
                    labelText: 'path',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Switch(
                      value: secure,
                      onChanged: (v) => setS(() => secure = v),
                    ),
                    const Text('Secure'),
                    const SizedBox(width: 16),
                    Switch(
                      value: httpOnly,
                      onChanged: (v) => setS(() => httpOnly = v),
                    ),
                    const Text('HttpOnly'),
                  ],
                ),
              ],
            ),
            actions: [
              OpenHandDialogActionButton.secondary(
                label: loc?.webReverseStorageCancel ?? 'Cancel',
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
              OpenHandDialogActionButton.primary(
                label: loc?.webReverseStorageSave ?? 'Save',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final name = nameCtl.text.trim();
    if (name.isEmpty) return;
    final success = await widget.controller.setCookie(
      name: name,
      value: valueCtl.text,
      domain: domainCtl.text.trim().isEmpty ? null : domainCtl.text.trim(),
      path: pathCtl.text.trim().isEmpty ? null : pathCtl.text.trim(),
      secure: secure,
      httpOnly: httpOnly,
    );
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      if (success) {
        OpenHandSnackBar.showSuccessOn(
          context,
          m,
          loc?.webReverseStorageCookieSaved ?? 'Cookie saved',
        );
      } else {
        OpenHandSnackBar.showErrorOn(
          context,
          m,
          loc?.webReverseStorageSaveFailed ?? 'Save failed',
        );
      }
    }
    await _refreshActive();
  }

  Future<void> _editStorageDialog({
    required bool isLocal,
    String? key0,
    String? value0,
  }) async {
    final loc = AppLocalizations.of(context);
    final origin = _origin;
    if (origin == null) return;
    final keyCtl = TextEditingController(text: key0 ?? '');
    final valueCtl = TextEditingController(text: value0 ?? '');
    final ok = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) {
        return buildOpenHandDialogFormShell(
          context: ctx,
          title: key0 == null
              ? (loc?.webReverseStorageAddEntry ?? 'Add entry')
              : (loc?.webReverseStorageEditEntry ?? 'Edit entry'),
          maxWidth: 520,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: keyCtl,
                enabled: key0 == null,
                decoration: const InputDecoration(
                  labelText: 'key',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: valueCtl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'value',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              label: loc?.webReverseStorageCancel ?? 'Cancel',
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            OpenHandDialogActionButton.primary(
              label: loc?.webReverseStorageSave ?? 'Save',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final key = keyCtl.text.trim();
    if (key.isEmpty) return;
    await widget.controller.setDomStorageItem(
      origin: origin,
      isLocalStorage: isLocal,
      key: key,
      value: valueCtl.text,
    );
    await _refreshActive();
  }

  Widget _cookiesView() {
    final cs = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    return Column(
      children: [
        _toolbar(
          right: [
            FilledButton.icon(
              onPressed: _addCookieDialog,
              icon: const Icon(Icons.add_rounded),
              label: Text(loc?.webReverseStorageAddCookie ?? 'Add Cookie'),
            ),
          ],
        ),
        Expanded(
          child: _cookies.isEmpty
              ? _emptyHint(loc?.webReverseStorageNoCookies ?? 'No cookies')
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _cookies.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: cs.outlineVariant),
                  itemBuilder: (_, i) {
                    final c = _cookies[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${c['name']}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      subtitle: Text(
                        '${c['domain']}${c['path']} • ${c['value']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip:
                                loc?.webReverseStorageCopyJson ?? 'Copy JSON',
                            onPressed: () => _copyJson(c),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_rounded,
                              size: 18,
                              color: cs.error,
                            ),
                            tooltip: loc?.webReverseStorageDelete ?? 'Delete',
                            onPressed: () async {
                              await widget.controller.deleteCookie(
                                name: '${c['name']}',
                                domain: c['domain'] as String?,
                                path: c['path'] as String?,
                              );
                              await _refreshActive();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _storageView({required bool isLocal}) {
    final list = isLocal ? _local : _session;
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _toolbar(
          right: [
            FilledButton.icon(
              onPressed: () => _editStorageDialog(isLocal: isLocal),
              icon: const Icon(Icons.add_rounded),
              label: Text(loc?.webReverseStorageAdd ?? 'Add'),
            ),
          ],
        ),
        Expanded(
          child: list.isEmpty
              ? _emptyHint(loc?.webReverseStorageEmpty ?? 'Empty')
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: cs.outlineVariant),
                  itemBuilder: (_, i) {
                    final e = list[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        e.key,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      subtitle: Text(
                        e.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            onPressed: () => _editStorageDialog(
                              isLocal: isLocal,
                              key0: e.key,
                              value0: e.value,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_rounded,
                              size: 18,
                              color: cs.error,
                            ),
                            onPressed: () async {
                              final origin = _origin;
                              if (origin == null) return;
                              await widget.controller.removeDomStorageItem(
                                origin: origin,
                                isLocalStorage: isLocal,
                                key: e.key,
                              );
                              await _refreshActive();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _idbView() {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _toolbar(),
        Expanded(
          // 嵌套 ResizableSplitter：左侧再切 DB 列表 / Store 列表，右侧是 Entry 区。
          child: ResizableSplitter(
            initialLeftFraction: 0.34,
            minLeft: 280,
            minRight: 320,
            left: ResizableSplitter(
              initialLeftFraction: 0.52,
              minLeft: 140,
              minRight: 120,
              left: _idbDbs.isEmpty
                  ? _emptyHint(
                      loc?.webReverseStorageNoDatabases ?? 'No databases',
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: [
                        for (final db in _idbDbs)
                          ListTile(
                            dense: true,
                            selected: db == _idbDb,
                            title: Text(
                              db,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () => _selectIdb(db),
                          ),
                      ],
                    ),
              right: _idbStores.isEmpty
                  ? _emptyHint(loc?.webReverseStoragePickDb ?? 'Pick DB')
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: [
                        for (final s in _idbStores)
                          ListTile(
                            dense: true,
                            selected: s == _idbStore,
                            title: Text(
                              s,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () => _selectIdbStore(s),
                          ),
                      ],
                    ),
            ),
            right: _idbEntries.isEmpty
                ? _emptyHint(loc?.webReverseStoragePickStore ?? 'Pick store')
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _idbEntries.length + (_idbHasMore ? 1 : 0),
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (_, i) {
                      if (i == _idbEntries.length) {
                        return Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            loc?.webReverseStorageMoreRecords ??
                                '… more records (showing first 50)',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        );
                      }
                      final e = _idbEntries[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          'key: ${(e['key'] as Map?)?['value'] ?? e['key']}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        subtitle: Text(
                          jsonEncode(e['value']),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () => _copyJson(e),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _toolbar({List<Widget> right = const []}) {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          if (_origin != null)
            Text(
              'origin: ${_origin!}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: loc?.webReverseStorageRefresh ?? 'Refresh',
            onPressed: _loading ? null : _refreshActive,
          ),
          ...right,
        ],
      ),
    );
  }

  Widget _emptyHint(String t) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        t,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.storage_rounded,
            title: loc?.webReverseStorageTitle ?? 'Storage Manager',
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
          ),
          TabBar(
            controller: _tab,
            tabs: const [
              Tab(text: 'Cookies'),
              Tab(text: 'LocalStorage'),
              Tab(text: 'SessionStorage'),
              Tab(text: 'IndexedDB'),
            ],
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _cookiesView(),
                _storageView(isLocal: true),
                _storageView(isLocal: false),
                _idbView(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: OpenHandDialogActionButton.primary(
                label: loc?.webReverseStorageClose ?? 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

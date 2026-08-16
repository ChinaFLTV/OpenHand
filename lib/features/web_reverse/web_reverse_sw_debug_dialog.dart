/// Service Worker 调试面板。
///
/// `ServiceWorker` 域比应用 tab 的简单列表更深入：
/// - 列出 registration scope 与运行状态
/// - 启动 / 停止 worker（startWorker / stopWorker）
/// - 强制更新（updateRegistration）/ 注销（unregister）
/// - 触发 sync 事件、传 push 通知
/// - 切换 setForceUpdateOnPageLoad（每次访问页都强制取新版本）
///
/// 注册与运行态统一由 controller 的有界 ServiceWorker 事件快照提供。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/byte_size_format.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseSwDebugDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _SwDebugDialog(controller: controller),
  );
}

class _SwReg {
  _SwReg({required this.registrationId, required this.scopeURL});
  final String registrationId;
  final String scopeURL;
}

class _SwVersion {
  _SwVersion({
    required this.versionId,
    required this.registrationId,
    required this.runningStatus,
    required this.status,
  });
  final String versionId;
  final String registrationId;
  final String runningStatus;
  final String status;
}

class _SwDebugDialog extends StatefulWidget {
  const _SwDebugDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_SwDebugDialog> createState() => _SwDebugDialogState();
}

class _SwDebugDialogState extends State<_SwDebugDialog> {
  static const int _maxSyncTagChars = 256;
  static const int _maxPushDataChars = 64 * kBytesPerKiB;

  bool _loading = false;
  bool _forceUpdate = false;
  List<_SwReg> _regs = const [];
  List<_SwVersion> _versions = const [];
  String _status = '';

  final TextEditingController _pushData = TextEditingController(
    text: '{"hello":"world"}',
  );
  final TextEditingController _syncTag = TextEditingController(
    text: 'oh-debug-sync',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _pushData.dispose();
    _syncTag.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _status =
          loc?.webReverseSwDebugFetchingRegs ?? 'Fetching registrations...';
    });
    try {
      final workers = await widget.controller.listServiceWorkers();
      if (!mounted) return;
      final regsById = <String, _SwReg>{};
      final vers = <_SwVersion>[];
      for (final worker in workers) {
        final registrationId = '${worker['registrationId'] ?? ''}';
        if (registrationId.isEmpty) continue;
        final scope = '${worker['scopeURL'] ?? ''}';
        regsById.putIfAbsent(
          registrationId,
          () => _SwReg(registrationId: registrationId, scopeURL: scope),
        );
        vers.add(
          _SwVersion(
            versionId: '${worker['versionId'] ?? ''}',
            registrationId: registrationId,
            runningStatus: '${worker['runningStatus'] ?? ''}',
            status: '${worker['status'] ?? ''}',
          ),
        );
      }
      _regs = List<_SwReg>.unmodifiable(regsById.values);
      _versions = List<_SwVersion>.unmodifiable(vers);
      setState(
        () => _status =
            loc?.webReverseSwDebugWorkersCount(_regs.length) ??
            '${_regs.length} Service Workers',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setForceUpdate(bool v) async {
    final loc = AppLocalizations.of(context);
    final r = await widget.controller.sendRawCdp(
      method: 'ServiceWorker.setForceUpdateOnPageLoad',
      paramsJson: jsonEncode({'forceUpdateOnPageLoad': v}),
      useSession: false,
    );
    if (!mounted) return;
    if (r == null || r['error'] != null) {
      _toast(
        loc?.webReverseSwDebugToggleFailed ?? 'Toggle failed',
        error: true,
      );
      return;
    }
    setState(() => _forceUpdate = v);
    _toast(
      v
          ? (loc?.webReverseSwDebugForceUpdateOn ?? 'Force-update on')
          : (loc?.webReverseSwDebugForceUpdateOff ?? 'Force-update off'),
    );
  }

  Future<void> _runForScope(String method, String scope) async {
    if (scope.isEmpty) return;
    await _runCdpMethod(method, <String, Object?>{'scopeURL': scope});
  }

  Future<void> _runForVersion(String method, String versionId) async {
    if (versionId.isEmpty) return;
    await _runCdpMethod(method, <String, Object?>{'versionId': versionId});
  }

  String? _httpOriginForScope(String scope) {
    final uri = Uri.tryParse(scope);
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return uri.origin;
  }

  Future<void> _runCdpMethod(String method, Map<String, Object?> params) async {
    final loc = AppLocalizations.of(context);
    final r = await widget.controller.sendRawCdp(
      method: method,
      paramsJson: jsonEncode(params),
      useSession: false,
    );
    if (!mounted) return;
    if (r == null || r['error'] != null) {
      _toast(
        loc?.webReverseSwDebugMethodFailed(
              method,
              '${r?['error'] ?? 'unknown'}',
            ) ??
            '$method failed: ${r?['error'] ?? 'unknown'}',
        error: true,
      );
      return;
    }
    _toast(loc?.webReverseSwDebugMethodOk(method) ?? '$method ok');
    await _refresh();
  }

  void _toast(String msg, {bool error = false}) {
    if (error) {
      showOpenHandErrorSnack(context, msg);
    } else {
      showOpenHandSuccessSnack(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightTall,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.miscellaneous_services_rounded,
            title: loc?.webReverseSwDebugTitle ?? 'Service Worker Debug',
            subtitle:
                loc?.webReverseSwDebugSubtitle ??
                'ServiceWorker domain: start/stop/update/unregister/sync/push',
            actions: [
              IconButton(
                tooltip: loc?.webReverseSwDebugRefresh ?? 'Refresh',
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Switch(
                  value: _forceUpdate,
                  onChanged: _loading ? null : _setForceUpdate,
                ),
                kOpenHandHGap6,
                Text(
                  loc?.webReverseSwDebugForceUpdateLabel ??
                      'Force update SW on every navigation',
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: _loading && _regs.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _regs.isEmpty
                ? OpenHandInlineEmptyState(
                    message:
                        loc?.webReverseSwDebugEmptyList ?? 'No service workers',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    itemCount: _regs.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (_, i) {
                      final reg = _regs[i];
                      final origin = _httpOriginForScope(reg.scopeURL);
                      final hasScope = reg.scopeURL.isNotEmpty;
                      final v = _versions.firstWhere(
                        (x) => x.registrationId == reg.registrationId,
                        orElse: () => _SwVersion(
                          versionId: '',
                          registrationId: reg.registrationId,
                          runningStatus: '',
                          status: '',
                        ),
                      );
                      return _RegTile(
                        reg: reg,
                        ver: v,
                        loc: loc,
                        onStart: hasScope
                            ? () => _runForScope(
                                'ServiceWorker.startWorker',
                                reg.scopeURL,
                              )
                            : null,
                        onStop: v.versionId.isEmpty
                            ? null
                            : () => _runForVersion(
                                'ServiceWorker.stopWorker',
                                v.versionId,
                              ),
                        onUpdate: hasScope
                            ? () => _runForScope(
                                'ServiceWorker.updateRegistration',
                                reg.scopeURL,
                              )
                            : null,
                        onUnregister: hasScope
                            ? () => _runForScope(
                                'ServiceWorker.unregister',
                                reg.scopeURL,
                              )
                            : null,
                        onSync: origin == null
                            ? null
                            : () => _runCdpMethod(
                                'ServiceWorker.dispatchSyncEvent',
                                <String, Object?>{
                                  'origin': origin,
                                  'registrationId': reg.registrationId,
                                  'tag': _syncTag.text.trim(),
                                  'lastChance': false,
                                },
                              ),
                        onPush: origin == null
                            ? null
                            : () => _runCdpMethod(
                                'ServiceWorker.deliverPushMessage',
                                <String, Object?>{
                                  'origin': origin,
                                  'registrationId': reg.registrationId,
                                  'data': _pushData.text,
                                },
                              ),
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _syncTag,
                    maxLength: _maxSyncTagChars,
                    decoration: const InputDecoration(
                      labelText: 'sync tag',
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                kOpenHandHGap8,
                Expanded(
                  child: TextField(
                    controller: _pushData,
                    maxLength: _maxPushDataChars,
                    decoration: InputDecoration(
                      labelText:
                          loc?.webReverseSwDebugPushDataLabel ??
                          'push data (string)',
                      isDense: true,
                      counterText: '',
                      border: const OutlineInputBorder(),
                    ),
                    style: const TextStyle(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
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
}

class _RegTile extends StatelessWidget {
  const _RegTile({
    required this.reg,
    required this.ver,
    required this.loc,
    required this.onStart,
    required this.onStop,
    required this.onUpdate,
    required this.onUnregister,
    required this.onSync,
    required this.onPush,
  });
  final _SwReg reg;
  final _SwVersion ver;
  final AppLocalizations? loc;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onUpdate;
  final VoidCallback? onUnregister;
  final VoidCallback? onSync;
  final VoidCallback? onPush;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ver.runningStatus == 'running'
                      ? Colors.green
                      : cs.outlineVariant,
                  shape: BoxShape.circle,
                ),
              ),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  reg.scopeURL,
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${ver.status} · ${ver.runningStatus}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          kOpenHandGap4,
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              'id: ${reg.registrationId}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          kOpenHandGap8,
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _btn(
                  loc?.webReverseSwDebugBtnStart ?? 'Start',
                  Icons.play_arrow_rounded,
                  onStart,
                ),
                _btn(
                  loc?.webReverseSwDebugBtnStop ?? 'Stop',
                  Icons.stop_rounded,
                  onStop,
                ),
                _btn(
                  loc?.webReverseSwDebugBtnUpdate ?? 'Update',
                  Icons.refresh_rounded,
                  onUpdate,
                ),
                _btn(
                  loc?.webReverseSwDebugBtnSync ?? 'Dispatch sync',
                  Icons.sync_rounded,
                  onSync,
                ),
                _btn(
                  loc?.webReverseSwDebugBtnPush ?? 'Deliver push',
                  Icons.notifications_active_rounded,
                  onPush,
                ),
                _btn(
                  loc?.webReverseSwDebugBtnUnregister ?? 'Unregister',
                  Icons.delete_outline_rounded,
                  onUnregister,
                  destructive: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool destructive = false,
  }) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ButtonStyle(
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
        foregroundColor: destructive
            ? WidgetStateProperty.all(Colors.red.shade400)
            : null,
      ),
    );
  }
}

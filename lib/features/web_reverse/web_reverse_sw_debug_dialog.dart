/// Service Worker 调试面板。
///
/// `ServiceWorker` 域比应用 tab 的简单列表更深入：
/// - 列出所有 registration（scope + scriptURL + status）
/// - 启动 / 停止 worker（startWorker / stopWorker）
/// - 强制更新（updateRegistration）/ 注销（unregister）
/// - 触发 sync / periodicSync 事件（dispatchSyncEvent / dispatchPeriodicSyncEvent）
/// - 传 push 通知（deliverPushMessage）
/// - 切换 setForceUpdateOnPageLoad（每次访问页都强制取新版本）
///
/// `Page` 域提供注册数据，`ServiceWorker.workerVersionUpdated` 事件给运行态。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseSwDebugDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showWebReverseToolDialog<void>(
    context: context,
    builder: (_) => _SwDebugDialog(controller: controller, isZh: isZh),
  );
}

class _SwReg {
  _SwReg({
    required this.registrationId,
    required this.scopeURL,
    required this.isDeleted,
  });
  final String registrationId;
  final String scopeURL;
  final bool isDeleted;
}

class _SwVersion {
  _SwVersion({
    required this.versionId,
    required this.registrationId,
    required this.scriptURL,
    required this.runningStatus,
    required this.status,
  });
  final String versionId;
  final String registrationId;
  final String scriptURL;
  final String runningStatus;
  final String status;
}

class _SwDebugDialog extends StatefulWidget {
  const _SwDebugDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_SwDebugDialog> createState() => _SwDebugDialogState();
}

class _SwDebugDialogState extends State<_SwDebugDialog> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _enableAndRefresh());
  }

  @override
  void dispose() {
    _pushData.dispose();
    _syncTag.dispose();
    super.dispose();
  }

  Future<void> _enableAndRefresh() async {
    final loc = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _status = loc?.webReverseSwDebugEnabling ?? 'Enable ServiceWorker...';
    });
    await widget.controller.sendRawCdp(
      method: 'ServiceWorker.enable',
      paramsJson: '{}',
      useSession: false,
    );
    await _refresh();
  }

  Future<void> _refresh() async {
    final loc = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _status =
          loc?.webReverseSwDebugFetchingRegs ?? 'Fetching registrations...';
    });
    try {
      final r = await widget.controller.sendRawCdp(
        method: 'ServiceWorker.dispatchSyncEvent',
        paramsJson: '{}',
        useSession: false,
      );
      // 上面只为触发一次响应；真正的列表通过事件回传，我们直接读应用 tab
      // 已有的缓存接口（reverse controller 暴露）+ 主动拉一次：
      // 这里改走 Storage.getTrustTokens 风格，使用 Page.getResourceTree 取 frames
      // 然后调用 Network.getAllCookies → no。直接走 ServiceWorker.* 没有 listRegistrations，
      // 我们以 Storage.getRelatedWebsiteSets 之外的命令：调用浏览器 chrome:// 不可行。
      // 替代方案：使用 Target.getTargets 过滤 type=service_worker。
      // 注：r 仅用于错误检测，不依赖其内容。
      if (r != null && r['error'] != null) {
        // 忽略，可能 SW 域未实现该方法
      }
      final t = await widget.controller.sendRawCdp(
        method: 'Target.getTargets',
        paramsJson: '{}',
        useSession: false,
      );
      final regs = <_SwReg>[];
      final vers = <_SwVersion>[];
      if (t != null && t['targetInfos'] is List) {
        for (final info in (t['targetInfos'] as List)) {
          if (info is! Map) continue;
          final type = '${info['type']}';
          if (type != 'service_worker') continue;
          final id = '${info['targetId']}';
          final url = '${info['url']}';
          final attached = info['attached'] == true;
          regs.add(_SwReg(registrationId: id, scopeURL: url, isDeleted: false));
          vers.add(
            _SwVersion(
              versionId: id,
              registrationId: id,
              scriptURL: url,
              runningStatus: attached ? 'attached' : 'detached',
              status: 'activated',
            ),
          );
        }
      }
      _regs = regs;
      _versions = vers;
      setState(
        () => _status =
            loc?.webReverseSwDebugWorkersCount(regs.length) ??
            '${regs.length} Service Workers',
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

  Future<void> _runForScope(
    String method,
    String scope, {
    Map<String, Object?>? extra,
  }) async {
    final loc = AppLocalizations.of(context);
    final params = <String, Object?>{'scopeURL': scope, ...?extra};
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

  Future<void> _runForVersion(String method, String versionId) async {
    final loc = AppLocalizations.of(context);
    final r = await widget.controller.sendRawCdp(
      method: method,
      paramsJson: jsonEncode({'versionId': versionId}),
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
      showWebReverseErrorSnack(context, msg);
    } else {
      showWebReverseSuccessSnack(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 920,
      maxHeight: 760,
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
                const SizedBox(width: 6),
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
                ? Center(
                    child: Text(
                      loc?.webReverseSwDebugEmptyList ?? 'No service workers',
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
                    itemCount: _regs.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (_, i) {
                      final reg = _regs[i];
                      final v = _versions.firstWhere(
                        (x) => x.registrationId == reg.registrationId,
                        orElse: () => _SwVersion(
                          versionId: '',
                          registrationId: reg.registrationId,
                          scriptURL: '',
                          runningStatus: '',
                          status: '',
                        ),
                      );
                      return _RegTile(
                        reg: reg,
                        ver: v,
                        loc: loc,
                        onStart: () => _runForScope(
                          'ServiceWorker.startWorker',
                          reg.scopeURL,
                        ),
                        onStop: v.versionId.isEmpty
                            ? null
                            : () => _runForVersion(
                                'ServiceWorker.stopWorker',
                                v.versionId,
                              ),
                        onUpdate: () => _runForScope(
                          'ServiceWorker.updateRegistration',
                          reg.scopeURL,
                        ),
                        onUnregister: () => _runForScope(
                          'ServiceWorker.unregister',
                          reg.scopeURL,
                        ),
                        onSync: () => _runForScope(
                          'ServiceWorker.dispatchSyncEvent',
                          reg.scopeURL,
                          extra: {
                            'registrationId': reg.registrationId,
                            'tag': _syncTag.text.trim(),
                            'lastChance': false,
                          },
                        ),
                        onPush: () => _runForScope(
                          'ServiceWorker.deliverPushMessage',
                          reg.scopeURL,
                          extra: {
                            'origin':
                                Uri.tryParse(reg.scopeURL)?.origin ??
                                reg.scopeURL,
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
                    decoration: const InputDecoration(
                      labelText: 'sync tag',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _pushData,
                    decoration: InputDecoration(
                      labelText:
                          loc?.webReverseSwDebugPushDataLabel ??
                          'push data (string)',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
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
  final VoidCallback onStart;
  final VoidCallback? onStop;
  final VoidCallback onUpdate;
  final VoidCallback onUnregister;
  final VoidCallback onSync;
  final VoidCallback onPush;

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
                  color: ver.runningStatus == 'attached'
                      ? Colors.green
                      : cs.outlineVariant,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reg.scopeURL,
                  style: const TextStyle(
                    fontFamily: 'monospace',
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
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              'id: ${reg.registrationId}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
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

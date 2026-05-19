/// WebAuthn 虚拟认证器面板。
///
/// 通过 CDP `WebAuthn` 域注入虚拟 FIDO2/WebAuthn 认证器，使 `navigator.credentials`
/// 流程在没有真实硬件密钥的情况下完成，便于逆向调试登录流程：
///
///   - `WebAuthn.enable` {enableUI:false}
///   - `WebAuthn.addVirtualAuthenticator` {options:{protocol, transport, hasResidentKey, hasUserVerification, isUserVerified, automaticPresenceSimulation}}
///   - `WebAuthn.getCredentials` {authenticatorId}
///   - `WebAuthn.removeVirtualAuthenticator` {authenticatorId}
///   - `WebAuthn.setUserVerified` {authenticatorId, isUserVerified}
///
/// 创建出的 authenticator 在当前页面会被 navigator.credentials.create / get
/// 直接拾取，无需任何客户端代码改动。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

class _VirtualAuth {
  _VirtualAuth({
    required this.id,
    required this.protocol,
    required this.transport,
    required this.hasResidentKey,
    required this.hasUserVerification,
    required this.isUserVerified,
  });
  final String id;
  final String protocol;
  final String transport;
  final bool hasResidentKey;
  final bool hasUserVerification;
  bool isUserVerified;
  List<Map<String, Object?>> credentials = <Map<String, Object?>>[];
}

Future<void> showWebReverseWebAuthnDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _WebAuthnDialog(controller: controller, isZh: isZh),
  );
}

class _WebAuthnDialog extends StatefulWidget {
  const _WebAuthnDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  // ignore: unused_field
  final bool isZh;
  @override
  State<_WebAuthnDialog> createState() => _WebAuthnDialogState();
}

class _WebAuthnDialogState extends State<_WebAuthnDialog> {
  bool _enabled = false;
  bool _busy = false;
  final List<_VirtualAuth> _auths = <_VirtualAuth>[];
  String? _lastError;

  // 新增 authenticator 表单参数
  String _newProtocol = 'ctap2';
  String _newTransport = 'usb';
  bool _newResidentKey = true;
  bool _newUserVerification = true;
  bool _newIsVerified = true;
  bool _newAutoPresence = true;

  Future<Map<String, Object?>?> _cdp(String method, Map<String, Object?> p) {
    return widget.controller.sendRawCdp(
      method: method,
      paramsJson: jsonEncode(p),
    );
  }

  Future<void> _toggleEnable(bool v) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      if (v) {
        final r = await _cdp('WebAuthn.enable', {'enableUI': false});
        if (r != null && r['error'] != null) {
          _lastError = '${r['error']}';
        } else {
          _enabled = true;
        }
      } else {
        final r = await _cdp('WebAuthn.disable', const {});
        if (r != null && r['error'] != null) {
          _lastError = '${r['error']}';
        } else {
          _enabled = false;
          _auths.clear();
        }
      }
    } catch (e, st) {
      silentLog('web_reverse_webauthn', 'enable', e, st);
      _lastError = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _addAuthenticator() async {
    if (_busy || !_enabled) return;
    setState(() {
      _busy = true;
      _lastError = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final r = await _cdp('WebAuthn.addVirtualAuthenticator', {
        'options': {
          'protocol': _newProtocol,
          'transport': _newTransport,
          'hasResidentKey': _newResidentKey,
          'hasUserVerification': _newUserVerification,
          'isUserVerified': _newIsVerified,
          'automaticPresenceSimulation': _newAutoPresence,
        },
      });
      if (r != null && r['error'] != null) {
        _lastError = '${r['error']}';
      } else {
        final id = r?['authenticatorId']?.toString() ?? '';
        if (id.isNotEmpty) {
          _auths.add(_VirtualAuth(
            id: id,
            protocol: _newProtocol,
            transport: _newTransport,
            hasResidentKey: _newResidentKey,
            hasUserVerification: _newUserVerification,
            isUserVerified: _newIsVerified,
          ));
          if (messenger != null && mounted) {
            OpenHandSnackBar.showSuccessOn(
              context,
              messenger,
              AppLocalizations.of(context)?.webReverseWebauthnAdded(id) ??
                  'Added $id',
            );
          }
        }
      }
    } catch (e, st) {
      silentLog('web_reverse_webauthn', 'add', e, st);
      _lastError = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _removeAuthenticator(_VirtualAuth a) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _cdp('WebAuthn.removeVirtualAuthenticator', {'authenticatorId': a.id});
      _auths.removeWhere((e) => e.id == a.id);
    } catch (e, st) {
      silentLog('web_reverse_webauthn', 'remove', e, st);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _refreshCredentials(_VirtualAuth a) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await _cdp('WebAuthn.getCredentials', {'authenticatorId': a.id});
      final list = r?['credentials'];
      if (list is List) {
        a.credentials = list
            .whereType<Map>()
            .map((e) => Map<String, Object?>.from(e))
            .toList();
      }
    } catch (e, st) {
      silentLog('web_reverse_webauthn', 'getCredentials', e, st);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleUserVerified(_VirtualAuth a, bool v) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await _cdp('WebAuthn.setUserVerified', {
        'authenticatorId': a.id,
        'isUserVerified': v,
      });
      if (r != null && r['error'] == null) {
        a.isUserVerified = v;
      }
    } catch (e, st) {
      silentLog('web_reverse_webauthn', 'setUserVerified', e, st);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);

    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.fingerprint_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc?.webReverseWebauthnTitle ??
                              'WebAuthn Virtual Authenticator',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'WebAuthn.enable / addVirtualAuthenticator / getCredentials',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _enabled,
                    onChanged: _busy ? null : _toggleEnable,
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
              child: !_enabled
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          loc?.webReverseWebauthnDisabledBody ??
                              'Toggle WebAuthn on to enable virtual authenticators. navigator.credentials.create/get will succeed without physical hardware.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc?.webReverseWebauthnAdd ??
                                'Add Virtual Authenticator',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              DropdownButton<String>(
                                value: _newProtocol,
                                items: const [
                                  DropdownMenuItem(value: 'ctap2', child: Text('protocol: ctap2')),
                                  DropdownMenuItem(value: 'u2f', child: Text('protocol: u2f')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _newProtocol = v ?? 'ctap2'),
                              ),
                              DropdownButton<String>(
                                value: _newTransport,
                                items: const [
                                  DropdownMenuItem(value: 'usb', child: Text('transport: usb')),
                                  DropdownMenuItem(value: 'nfc', child: Text('transport: nfc')),
                                  DropdownMenuItem(value: 'ble', child: Text('transport: ble')),
                                  DropdownMenuItem(value: 'internal', child: Text('transport: internal')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _newTransport = v ?? 'usb'),
                              ),
                              _Flag(
                                label: 'hasResidentKey',
                                value: _newResidentKey,
                                onChanged: (v) => setState(() => _newResidentKey = v),
                              ),
                              _Flag(
                                label: 'hasUserVerification',
                                value: _newUserVerification,
                                onChanged: (v) => setState(() => _newUserVerification = v),
                              ),
                              _Flag(
                                label: 'isUserVerified',
                                value: _newIsVerified,
                                onChanged: (v) => setState(() => _newIsVerified = v),
                              ),
                              _Flag(
                                label: 'autoPresenceSimulation',
                                value: _newAutoPresence,
                                onChanged: (v) => setState(() => _newAutoPresence = v),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _busy ? null : _addAuthenticator,
                                icon: const Icon(Icons.add_rounded),
                                label: Text(loc?.webReverseWebauthnAddBtn ?? 'Add'),
                              ),
                            ],
                          ),
                          if (_lastError != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _lastError!,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  color: cs.onErrorContainer,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Divider(color: cs.outlineVariant),
                          const SizedBox(height: 8),
                          Text(
                            loc?.webReverseWebauthnCreatedCount(_auths.length) ??
                                'Authenticators (${_auths.length})',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          if (_auths.isEmpty)
                            Text(
                              loc?.webReverseWebauthnNone ??
                                  'No authenticators yet',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          for (final a in _auths) _AuthCard(
                            auth: a,
                            busy: _busy,
                            onRemove: () => _removeAuthenticator(a),
                            onRefresh: () => _refreshCredentials(a),
                            onToggleVerified: (v) => _toggleUserVerified(a, v),
                          ),
                        ],
                      ),
                    ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    label: loc?.webReverseWebauthnClose ?? 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        Text(label, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ],
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.auth,
    required this.busy,
    required this.onRemove,
    required this.onRefresh,
    required this.onToggleVerified,
  });
  final _VirtualAuth auth;
  final bool busy;
  final VoidCallback onRemove;
  final VoidCallback onRefresh;
  final ValueChanged<bool> onToggleVerified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return Card(
      color: cs.surfaceContainerHigh,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    auth.id,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Tooltip(
                  message: loc?.webReverseWebauthnRefreshCreds ??
                      'Refresh credentials',
                  child: IconButton(
                    onPressed: busy ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                ),
                Tooltip(
                  message: loc?.webReverseWebauthnRemove ?? 'Remove',
                  child: IconButton(
                    onPressed: busy ? null : onRemove,
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 18, color: cs.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _badge(theme, auth.protocol),
                _badge(theme, auth.transport),
                if (auth.hasResidentKey) _badge(theme, 'resident'),
                if (auth.hasUserVerification) _badge(theme, 'UV'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Switch(
                  value: auth.isUserVerified,
                  onChanged: busy ? null : onToggleVerified,
                ),
                Text(
                  loc?.webReverseWebauthnUserVerified ?? 'User verified',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
            if (auth.credentials.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                loc?.webReverseWebauthnCredentialsCount(auth.credentials.length) ??
                    'Credentials (${auth.credentials.length})',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              for (final c in auth.credentials)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(c),
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(ThemeData theme, String text) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
    );
  }
}

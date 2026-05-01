// 2026-05-03: 系统级代理设置卡片。三档模式（无代理 / 自动发现代理
// (默认) / 手动配置代理）+ 多协议复选 + 主机/端口 + 鉴权 + 例外名单
// （IP / CIDR / 域名 / `*.glob` / `/regex/`）。所有变更通过
// `SettingsController.updateProxySettings(...)` 持久化，再由 main.dart
// 的 listener 同步给 `SystemProxyResolver`，实现实时热生效。
part of 'settings_view.dart';

class _SystemProxySection extends StatefulWidget {
  const _SystemProxySection({required this.controller});

  final SettingsController controller;

  @override
  State<_SystemProxySection> createState() => _SystemProxySectionState();
}

class _SystemProxySectionState extends State<_SystemProxySection> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _exceptionsCtrl;
  late final FocusNode _hostFocus;
  late final FocusNode _portFocus;
  late final FocusNode _userFocus;
  late final FocusNode _pwdFocus;
  late final FocusNode _exceptionsFocus;

  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    final proxy = widget.controller.proxySettings;
    _hostCtrl = TextEditingController(text: proxy.host);
    _portCtrl = TextEditingController(text: proxy.port.toString());
    _userCtrl = TextEditingController(text: proxy.username);
    _pwdCtrl = TextEditingController(text: proxy.password);
    _exceptionsCtrl = TextEditingController(text: proxy.exceptions.join('\n'));
    _hostFocus = FocusNode();
    _portFocus = FocusNode();
    _userFocus = FocusNode();
    _pwdFocus = FocusNode();
    _exceptionsFocus = FocusNode();
    widget.controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _exceptionsCtrl.dispose();
    _hostFocus.dispose();
    _portFocus.dispose();
    _userFocus.dispose();
    _pwdFocus.dispose();
    _exceptionsFocus.dispose();
    super.dispose();
  }

  void _syncFromController() {
    if (!mounted) return;
    final proxy = widget.controller.proxySettings;
    if (!_hostFocus.hasFocus && _hostCtrl.text != proxy.host) {
      _hostCtrl.text = proxy.host;
    }
    final portText = proxy.port.toString();
    if (!_portFocus.hasFocus && _portCtrl.text != portText) {
      _portCtrl.text = portText;
    }
    if (!_userFocus.hasFocus && _userCtrl.text != proxy.username) {
      _userCtrl.text = proxy.username;
    }
    if (!_pwdFocus.hasFocus && _pwdCtrl.text != proxy.password) {
      _pwdCtrl.text = proxy.password;
    }
    final exText = proxy.exceptions.join('\n');
    if (!_exceptionsFocus.hasFocus && _exceptionsCtrl.text != exText) {
      _exceptionsCtrl.text = exText;
    }
    setState(() {});
  }

  Future<void> _setMode(AppProxyMode mode) async {
    await widget.controller.updateProxySettings(mode: mode);
  }

  Future<void> _toggleProtocol(AppProxyProtocol protocol, bool selected) async {
    final current = Set<AppProxyProtocol>.from(
      widget.controller.proxySettings.protocols,
    );
    if (selected) {
      current.add(protocol);
    } else {
      current.remove(protocol);
    }
    if (current.isEmpty) {
      // 至少保留一个协议；若用户取消最后一个，我们恢复默认 http+https。
      current
        ..add(AppProxyProtocol.http)
        ..add(AppProxyProtocol.https);
    }
    await widget.controller.updateProxySettings(protocols: current);
  }

  Future<void> _saveHost() async {
    await widget.controller.updateProxySettings(host: _hostCtrl.text);
  }

  Future<void> _savePort() async {
    final parsed = int.tryParse(_portCtrl.text.trim());
    if (parsed == null || parsed < 1 || parsed > 65535) {
      _portCtrl.text =
          widget.controller.proxySettings.port.toString();
      return;
    }
    await widget.controller.updateProxySettings(port: parsed);
  }

  Future<void> _toggleAuth(bool enabled) async {
    await widget.controller.updateProxySettings(authEnabled: enabled);
  }

  Future<void> _saveUsername() async {
    await widget.controller.updateProxySettings(username: _userCtrl.text);
  }

  Future<void> _savePassword() async {
    await widget.controller.updateProxySettings(password: _pwdCtrl.text);
  }

  Future<void> _saveExceptions() async {
    final lines = _exceptionsCtrl.text
        .split(RegExp(r'[\r\n,]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    await widget.controller.updateProxySettings(exceptions: lines);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final proxy = widget.controller.proxySettings;
    final isManual = proxy.mode == AppProxyMode.manual;
    final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.38);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingRowLabel(
          label: l10n.proxyModeLabel,
          description: l10n.proxyModeBody,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: Text(l10n.proxyModeDisabled),
              selected: proxy.mode == AppProxyMode.disabled,
              onSelected: (_) => _setMode(AppProxyMode.disabled),
            ),
            ChoiceChip(
              label: Text(l10n.proxyModeAutomatic),
              selected: proxy.mode == AppProxyMode.automatic,
              onSelected: (_) => _setMode(AppProxyMode.automatic),
            ),
            ChoiceChip(
              label: Text(l10n.proxyModeManual),
              selected: proxy.mode == AppProxyMode.manual,
              onSelected: (_) => _setMode(AppProxyMode.manual),
            ),
          ],
        ),
        const SizedBox(height: 16),
        IgnorePointer(
          ignoring: !isManual,
          child: Opacity(
            opacity: isManual ? 1.0 : 0.55,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingRowLabel(
                  label: l10n.proxyProtocolsLabel,
                  description: l10n.proxyProtocolsBody,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    FilterChip(
                      label: const Text('HTTP'),
                      selected: proxy.protocols.contains(AppProxyProtocol.http),
                      onSelected: (selected) =>
                          _toggleProtocol(AppProxyProtocol.http, selected),
                    ),
                    FilterChip(
                      label: const Text('HTTPS'),
                      selected: proxy.protocols.contains(
                        AppProxyProtocol.https,
                      ),
                      onSelected: (selected) =>
                          _toggleProtocol(AppProxyProtocol.https, selected),
                    ),
                    FilterChip(
                      label: const Text('SOCKS'),
                      selected: proxy.protocols.contains(
                        AppProxyProtocol.socks,
                      ),
                      onSelected: (selected) =>
                          _toggleProtocol(AppProxyProtocol.socks, selected),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _hostCtrl,
                        focusNode: _hostFocus,
                        enabled: isManual,
                        decoration: InputDecoration(
                          labelText: l10n.proxyHostLabel,
                          hintText: '127.0.0.1',
                        ),
                        onSubmitted: (_) => _saveHost(),
                        onTapOutside: (_) {
                          _hostFocus.unfocus();
                          _saveHost();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _portCtrl,
                        focusNode: _portFocus,
                        enabled: isManual,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.proxyPortLabel,
                          hintText: '7890',
                        ),
                        onSubmitted: (_) => _savePort(),
                        onTapOutside: (_) {
                          _portFocus.unfocus();
                          _savePort();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.proxyAuthLabel),
                  subtitle: Text(
                    l10n.proxyAuthBody,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isManual
                          ? theme.colorScheme.onSurfaceVariant
                          : disabledColor,
                    ),
                  ),
                  value: proxy.authEnabled,
                  onChanged: isManual ? _toggleAuth : null,
                ),
                const SizedBox(height: 8),
                IgnorePointer(
                  ignoring: !proxy.authEnabled,
                  child: Opacity(
                    opacity: proxy.authEnabled ? 1.0 : 0.55,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _userCtrl,
                            focusNode: _userFocus,
                            enabled: isManual && proxy.authEnabled,
                            decoration: InputDecoration(
                              labelText: l10n.proxyUsernameLabel,
                            ),
                            onSubmitted: (_) => _saveUsername(),
                            onTapOutside: (_) {
                              _userFocus.unfocus();
                              _saveUsername();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _pwdCtrl,
                            focusNode: _pwdFocus,
                            enabled: isManual && proxy.authEnabled,
                            obscureText: !_showPassword,
                            decoration: InputDecoration(
                              labelText: l10n.proxyPasswordLabel,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _savePassword(),
                            onTapOutside: (_) {
                              _pwdFocus.unfocus();
                              _savePassword();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SettingRowLabel(
                  label: l10n.proxyExceptionsLabel,
                  description: l10n.proxyExceptionsBody,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _exceptionsCtrl,
                  focusNode: _exceptionsFocus,
                  enabled: isManual,
                  maxLines: 5,
                  minLines: 3,
                  decoration: InputDecoration(
                    hintText: l10n.proxyExceptionsHint,
                  ),
                  onTapOutside: (_) {
                    _exceptionsFocus.unfocus();
                    _saveExceptions();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingRowLabel extends StatelessWidget {
  const _SettingRowLabel({required this.label, this.description});

  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            description!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

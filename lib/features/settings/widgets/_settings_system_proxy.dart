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
  /// 2026-05-04 (代理诊断): 默认测试端点从模型层读取，
  /// 避免在 UI 层重复定义。Google generate_204 是历史最稳的
  /// "204 No Content" 探针。
  static const String _defaultTestEndpoint =
      AppProxySettings.defaultTestEndpoint;

  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _exceptionsCtrl;
  late final TextEditingController _testEndpointCtrl;
  late final FocusNode _hostFocus;
  late final FocusNode _portFocus;
  late final FocusNode _userFocus;
  late final FocusNode _pwdFocus;
  late final FocusNode _exceptionsFocus;
  late final FocusNode _testEndpointFocus;

  bool _showPassword = false;

  bool _testing = false;
  String? _testMessage;
  bool _testSucceeded = false;

  @override
  void initState() {
    super.initState();
    final proxy = widget.controller.proxySettings;
    _hostCtrl = TextEditingController(text: proxy.host);
    _portCtrl = TextEditingController(text: proxy.port.toString());
    _userCtrl = TextEditingController(text: proxy.username);
    _pwdCtrl = TextEditingController(text: proxy.password);
    _exceptionsCtrl = TextEditingController(text: proxy.exceptions.join('\n'));
    _testEndpointCtrl = TextEditingController(text: proxy.testEndpoint);
    _hostFocus = FocusNode();
    _portFocus = FocusNode();
    _userFocus = FocusNode();
    _pwdFocus = FocusNode();
    _exceptionsFocus = FocusNode();
    _testEndpointFocus = FocusNode();
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
    _testEndpointCtrl.dispose();
    _hostFocus.dispose();
    _portFocus.dispose();
    _userFocus.dispose();
    _pwdFocus.dispose();
    _exceptionsFocus.dispose();
    _testEndpointFocus.dispose();
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
    if (!_testEndpointFocus.hasFocus &&
        _testEndpointCtrl.text != proxy.testEndpoint) {
      _testEndpointCtrl.text = proxy.testEndpoint;
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
      _portCtrl.text = widget.controller.proxySettings.port.toString();
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

  Future<void> _saveTestEndpoint() async {
    final raw = _testEndpointCtrl.text.trim();
    final saved = await widget.controller.updateProxySettings(
      testEndpoint: raw,
    );
    if (!mounted) return;
    // 这里反馈文案依赖 Localizations.localeOf 直接取语言码，避免为单一
    // 提示新增 ARB 键；不需要 AppLocalizations 实例。
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final localizedSaved = saved
        ? (isEn ? 'Test URL saved' : '测试 URL 已保存')
        : (isEn ? 'Failed to save test URL' : '测试 URL 保存失败');
    if (!_testEndpointFocus.hasFocus) {
      _testEndpointCtrl.text = widget.controller.proxySettings.testEndpoint;
    }
    final messenger = ScaffoldMessenger.of(context);
    OpenHandSnackBar.show(
      context,
      messenger,
      saved
          ? OpenHandSnackBar.success(context, localizedSaved)
          : OpenHandSnackBar.error(context, localizedSaved),
    );
  }

  Future<void> _runConnectivityTest() async {
    if (_testing) return;
    final l10n = AppLocalizations.of(context)!;
    final rawEndpoint = _testEndpointCtrl.text.trim().isEmpty
        ? _defaultTestEndpoint
        : _testEndpointCtrl.text.trim();
    final uri = Uri.tryParse(rawEndpoint);
    if (uri == null ||
        !(uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) ||
        uri.host.isEmpty) {
      setState(() {
        _testing = false;
        _testSucceeded = false;
        _testMessage = l10n.proxyTestEndpointInvalid;
      });
      return;
    }

    setState(() {
      _testing = true;
      _testMessage = l10n.proxyTesting;
      _testSucceeded = false;
    });

    final result = await showAnimatedDialog<_ProxyTestOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ProxyTestConsoleDialog(
        endpoint: uri,
        proxySettings: widget.controller.proxySettings,
      ),
    );

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testSucceeded = result?.succeeded ?? false;
      _testMessage = result?.summary ?? l10n.proxyTestFailure('cancelled');
    });
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
                // 2026-05-19 — 自动模式下虽然字段禁用，但仍把 SystemProxyResolver
                // 探测到的 host:port 实时回填到文本框，方便用户校验"系统现在
                // 走的哪条代理"。手动模式下保留用户自填值。
                ValueListenableBuilder<int>(
                  valueListenable: SystemProxyResolver.instance.revision,
                  builder: (context, _, _) {
                    if (!isManual) {
                      final detected = SystemProxyResolver
                          .instance
                          .detectedAutomaticHostPort;
                      final detectedHost = detected?.host ?? '';
                      final detectedPort = detected?.port.toString() ?? '';
                      if (_hostCtrl.text != detectedHost) {
                        _hostCtrl.text = detectedHost;
                      }
                      if (_portCtrl.text != detectedPort) {
                        _portCtrl.text = detectedPort;
                      }
                    }
                    return Row(
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
                    );
                  },
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
        const SizedBox(height: 16),
        _SettingRowLabel(
          label: l10n.proxyTestEndpointLabel,
          description: l10n.proxyTestEndpointHint,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: _testing ? null : _runConnectivityTest,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: Text(l10n.proxyTestButton),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _testEndpointCtrl,
                focusNode: _testEndpointFocus,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: _defaultTestEndpoint,
                ),
                onSubmitted: (_) => _saveTestEndpoint(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: Localizations.localeOf(context).languageCode == 'en'
                  ? 'Save Test URL'
                  : '保存测试 URL',
              icon: const Icon(Icons.save_outlined),
              onPressed: _saveTestEndpoint,
            ),
          ],
        ),
        if (_testMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _testMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _testing
                  ? theme.colorScheme.onSurfaceVariant
                  : (_testSucceeded
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }
}

class _InputRepairSection extends StatefulWidget {
  const _InputRepairSection();

  @override
  State<_InputRepairSection> createState() => _InputRepairSectionState();
}

class _InputRepairSectionState extends State<_InputRepairSection> {
  bool _repairing = false;

  /// 输入修复流水线（强化版），按因果链顺序执行：
  ///
  ///   1) **回收已登记子进程** —— [killAllTrackedChildren] 把
  ///      [_trackedChildren] 里登记的外部进程全部 SIGTERM → SIGKILL。
  ///   2) **回收未登记子进程** —— [killAllDirectChildren] 用 pgrep/pkill
  ///      平台原语扫出本进程下所有直接子进程，把通过 `Process.run` 裸调用 /
  ///      shell 间接拉起的 osascript / mitmdump / npm / node 等遗孤全部
  ///      SIGKILL，补充第 1 步触达不到的漏网之鱼。
  ///   3) **保存焦点现场 + 解除当前焦点** —— 记下当前聚焦节点，然后释放
  ///      platform input client 占用，为后续 IMK 失活扫清障碍。
  ///   4) **`TextInput.clearClient`** —— 让 Flutter engine 把当前的
  ///      attached TextInputClient 断开（macOS 侧触发
  ///      `[FlutterTextInputView resignFirstResponder]` → IMK
  ///      `IMKInputSession deactivate`）。
  ///   5) **`TextInput.hide`** —— 收起 IMK candidate window。
  ///   6) **`TextInput.finishAutofillContext(false)`** —— 清空自动填充上下文。
  ///   7) **`TextInput.requestExistingInputState`** —— 验证 engine 侧
  ///      TextInput 通道是否恢复可用，同时让 platform 层重新建立状态机。
  ///   8) **post-frame 焦点重连** —— 在下一帧用一个临时 FocusNode 触发
  ///      engine 的 TextInput.attach → detach 全周期，迫使 platform 把
  ///      `[FlutterTextInputView becomeFirstResponder]` → IMK
  ///      `IMKInputSession activate` 整条链路重新走通。最后把焦点交还给
  ///      此前保存的节点（如果有），用户无需手动重新点击输入框。
  Future<void> _runRepair(BuildContext context) async {
    if (_repairing) return;
    setState(() {
      _repairing = true;
    });
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);

    int killedCount = 0;
    int untrackedKilled = 0;
    FocusNode? savedFocus;
    try {
      // ── 阶段 1：子进程回收 ──────────────────────────────────────────
      // (1a) 已登记子进程批量终止。
      killedCount = debugTrackedChildPids().length;
      await killAllTrackedChildren();
      // (1b) 平台级全量子进程扫出 + 终结（补刀未登记遗孤）。
      untrackedKilled = await killAllDirectChildren();

      // ── 阶段 2：IMK 输入上下文重置 ──────────────────────────────────
      // (2a) 保存当前焦点节点，随后释放焦点。
      savedFocus = FocusManager.instance.primaryFocus;
      FocusManager.instance.primaryFocus?.unfocus();

      // (2b) 断开 TextInputClient —— 触发 IMKInputSession deactivate。
      try {
        await SystemChannels.textInput.invokeMethod<void>(
          'TextInput.clearClient',
        );
      } catch (error, stack) {
        silentLog('settings.system', 'clearClient', error, stack);
      }

      // (2c) IMK candidate window 收起。
      try {
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      } catch (error, stack) {
        silentLog('settings.system', 'hideTextInput', error, stack);
      }

      // (2d) 重置自动填充上下文。
      try {
        await SystemChannels.textInput.invokeMethod<void>(
          'TextInput.finishAutofillContext',
          false,
        );
      } catch (error, stack) {
        silentLog('settings.system', 'finishAutofillContext', error, stack);
      }

      // (2e) 请求 engine 回读当前输入状态，验证通道可用性
      // 并促使 platform 层重新同步 IMK 状态机。
      try {
        await SystemChannels.textInput.invokeMethod<void>(
          'TextInput.requestExistingInputState',
        );
      } catch (_) {}

      // ── 阶段 3：焦点重连（post-frame） ──────────────────────────────
      // 在下一帧用一个临时 FocusNode 走完 attach → detach 全周期，
      // 确保 engine 重新创建 TextInput 通道 → platform IMK session activate。
      // 之后再交还焦点给原始节点（如果有），用户无需手动重选输入框。
      final restoreTarget = savedFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          // 先 hide 清除可能的候选窗残留。
          SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        } catch (_) {}
        // 临时 focus → unfocus 驱动完整的 TextInput 重建握手。
        final tempNode = FocusNode();
        tempNode.requestFocus();
        // 用微延迟让 engine 的 TextInput.attach 有时间落地。
        Future<void>.delayed(const Duration(milliseconds: 60), () {
          tempNode.unfocus();
          tempNode.dispose();
          // 把焦点交还给之前活跃的输入框。
          if (restoreTarget != null && restoreTarget.context != null) {
            restoreTarget.requestFocus();
          }
        });
      });
    } catch (error, stack) {
      silentLog('settings.system', 'repairTextInput', error, stack);
    } finally {
      if (mounted) {
        setState(() {
          _repairing = false;
        });
      }
    }

    if (messenger != null && context.mounted) {
      final total = killedCount + untrackedKilled;
      final detail = total > 0
          ? l10n.inputRepairDoneDetail(total)
          : l10n.inputRepairDone;
      OpenHandSnackBar.showSuccessOn(context, messenger, detail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _SettingsSubsectionCard(
      title: l10n.inputRepairTitle,
      description: l10n.inputRepairBody,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: _repairing ? null : () => _runRepair(context),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _repairing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.healing_rounded, size: 18),
          label: Text(l10n.inputRepairButton),
        ),
      ),
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

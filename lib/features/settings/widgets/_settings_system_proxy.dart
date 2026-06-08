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

  Future<void> _showRepairReportDialog(InputRepairReport report) {
    return showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowAlignment: OverflowBarAlignment.center,
        title: Text(AppLocalizations.of(dialogContext)!.inputRepairTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: SelectableText(
              _formatRepairReport(report),
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            label: _localizedText(dialogContext, zh: '复制', en: 'Copy'),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: _formatRepairReport(report)),
              );
            },
          ),
          OpenHandDialogActionButton.primary(
            label: _localizedText(dialogContext, zh: '重启', en: 'Restart'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              final exe = Platform.resolvedExecutable;
              if (Platform.isMacOS) {
                final macSfx = '/Contents/MacOS/${p.basename(exe)}';
                final bundle =
                    exe.endsWith(macSfx) ? exe.replaceAll(macSfx, '') : exe;
                Process.start(
                  '/bin/sh',
                  <String>[
                    '-c',
                    'sleep 0.6 && open -n -a "\$1"',
                    '_',
                    bundle,
                  ],
                  mode: ProcessStartMode.detached,
                );
              } else {
                Process.start(
                  exe,
                  <String>[],
                  mode: ProcessStartMode.detached,
                );
              }
              exit(0);
            },
          ),
          OpenHandDialogActionButton.primary(
            label: AppLocalizations.of(dialogContext)!.commonClose,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  String _formatRepairReport(InputRepairReport report) {
    final buffer = StringBuffer()
      ..writeln('result=${report.result.name}')
      ..writeln('tracked_children_before=${report.trackedChildrenBefore}')
      ..writeln('direct_children_killed=${report.directChildrenKilled}')
      ..writeln('focus_before=${report.primaryFocusBeforeLabel ?? '-'}')
      ..writeln('focus_after=${report.primaryFocusAfterLabel ?? '-'}')
      ..writeln('restored_focus=${report.restoredFocusLabel ?? '-'}');
    for (final step in report.steps) {
      buffer.writeln(
        '${step.stage.name}: ${step.status.name}${step.message == null || step.message!.isEmpty ? '' : ' (${step.message})'}',
      );
    }
    return buffer.toString().trimRight();
  }

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
    final sentinelFocusNode = InputRepairSentinelScope.maybeOf(context);
    if (sentinelFocusNode == null) return;
    setState(() {
      _repairing = true;
    });
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    late final InputRepairReport report;
    try {
      report = await InputRepairService.instance.repair(
        sentinelFocusNode: sentinelFocusNode,
        isSafeRestoreTarget: (node) {
          final label = node.debugLabel?.trim() ?? '';
          return label.isNotEmpty &&
              label != 'browser-surface' &&
              label != 'input-repair-sentinel';
        },
      );
    } catch (error, stack) {
      silentLog('settings.system', 'repairTextInput', error, stack);
      report = const InputRepairReport(
        result: InputRepairResult.failure,
        steps: <InputRepairStepReport>[],
        trackedChildrenBefore: 0,
        directChildrenKilled: 0,
      );
    } finally {
      if (mounted) {
        setState(() {
          _repairing = false;
        });
      }
    }

    if (messenger != null && context.mounted) {
      final total = report.trackedChildrenBefore + report.directChildrenKilled;
      final detail = total > 0
          ? l10n.inputRepairDoneDetail(total)
          : l10n.inputRepairDone;
      switch (report.result) {
        case InputRepairResult.success:
          OpenHandSnackBar.showSuccessOn(context, messenger, detail);
          unawaited(_showRepairReportDialog(report));
        case InputRepairResult.partialSuccess:
          OpenHandSnackBar.showInfoOn(context, messenger, detail);
          unawaited(_showRepairReportDialog(report));
        case InputRepairResult.failure:
          OpenHandSnackBar.showErrorOn(
            context,
            messenger,
            l10n.inputRepairDone,
          );
          unawaited(_showRepairReportDialog(report));
      }
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

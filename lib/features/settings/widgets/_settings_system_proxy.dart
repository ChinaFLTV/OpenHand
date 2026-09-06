// 系统级代理设置卡片。三档模式（无代理 / 自动发现代理
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
  /// 代理诊断的默认测试端点从模型层读取，
  /// 避免在 UI 层重复定义。Google generate_204 是历史最稳的
  /// "204 No Content" 探针。
  static const String _defaultTestEndpoint =
      AppProxySettings.defaultTestEndpoint;
  static const double _testEndpointControlHeight = 60;

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
    final parsed = tcpPortFromText(_portCtrl.text);
    if (parsed == null) {
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
    final lines = splitTrimmedNonEmpty(
      _exceptionsCtrl.text,
      separator: RegExp(r'[\r\n,]+'),
    );
    await widget.controller.updateProxySettings(exceptions: lines);
  }

  Future<void> _saveTestEndpoint() async {
    final raw = _testEndpointCtrl.text.trim();
    final saved = await widget.controller.updateProxySettings(
      testEndpoint: raw,
    );
    if (!mounted) return;
    final localizedSaved = saved
        ? openHandLocalizedText(context, zh: '测试 URL 已保存', en: 'Test URL saved')
        : openHandLocalizedText(
            context,
            zh: '测试 URL 保存失败',
            en: 'Failed to save test URL',
          );
    if (!_testEndpointFocus.hasFocus) {
      _testEndpointCtrl.text = widget.controller.proxySettings.testEndpoint;
    }
    if (saved) {
      showOpenHandSuccessSnack(context, localizedSaved);
    } else {
      showOpenHandErrorSnack(context, localizedSaved);
    }
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
        kOpenHandGap8,
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
        kOpenHandGap16,
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
                kOpenHandGap8,
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
                kOpenHandGap16,
                // 自动模式下虽然字段禁用，但仍把 SystemProxyResolver
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
                        kOpenHandHGap12,
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
                kOpenHandGap16,
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
                kOpenHandGap8,
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
                        kOpenHandHGap12,
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
                kOpenHandGap16,
                _SettingRowLabel(
                  label: l10n.proxyExceptionsLabel,
                  description: l10n.proxyExceptionsBody,
                ),
                kOpenHandGap8,
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
        kOpenHandGap16,
        _SettingRowLabel(
          label: l10n.proxyTestEndpointLabel,
          description: l10n.proxyTestEndpointHint,
        ),
        kOpenHandGap8,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: _testing ? null : _runConnectivityTest,
              icon: OpenHandBusyStatusIcon(
                busy: _testing,
                icon: Icons.network_check,
              ),
              label: Text(l10n.proxyTestButton),
            ),
            kOpenHandHGap12,
            Expanded(
              child: SizedBox(
                height: _testEndpointControlHeight,
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
            ),
            kOpenHandHGap8,
            SizedBox.square(
              dimension: _testEndpointControlHeight,
              child: IconButton.filledTonal(
                tooltip: Localizations.localeOf(context).languageCode == 'en'
                    ? 'Save Test URL'
                    : '保存测试 URL',
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(_testEndpointControlHeight),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const RoundedRectangleBorder(
                    borderRadius: kOpenHandBorderRadius16,
                  ),
                ),
                icon: const Icon(Icons.save_outlined),
                onPressed: _saveTestEndpoint,
              ),
            ),
          ],
        ),
        if (_testMessage != null) ...<Widget>[
          kOpenHandGap8,
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
    var restarting = false;
    return showOpenHandStatefulDialog<void>(
      context: context,
      builder: (dialogContext, setDialogState) => buildOpenHandAlertDialog(
        title: Text(AppLocalizations.of(dialogContext)!.inputRepairTitle),
        content: buildOpenHandDialogConstrainedContent(
          maxWidth: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              _formatRepairReport(report),
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            label: openHandLocalizedText(dialogContext, zh: '复制', en: 'Copy'),
            onPressed: restarting
                ? null
                : () async {
                    await copyOpenHandTextToClipboard(
                      logTag: 'settings',
                      context: dialogContext,
                      text: _formatRepairReport(report),
                      successMessage: AppLocalizations.of(
                        dialogContext,
                      )!.commonCopiedToClipboard,
                      logAction: '复制输入修复报告',
                    );
                  },
          ),
          OpenHandDialogActionButton.primary(
            label: openHandLocalizedText(
              dialogContext,
              zh: '重启',
              en: 'Restart',
            ),
            icon: Icons.restart_alt_rounded,
            busy: restarting,
            onPressed: restarting
                ? null
                : () async {
                    setDialogState(() {
                      restarting = true;
                    });
                    AppRelaunchTicket? ticket;
                    try {
                      final exitDelay = _resolveDialogExitDelay(dialogContext);
                      ticket = await AppRestartService.instance
                          .prepareRelaunch();
                      if (!dialogContext.mounted) {
                        await ticket.cancel();
                        return;
                      }
                      Navigator.of(dialogContext).pop();
                      if (exitDelay > Duration.zero) {
                        await Future<void>.delayed(exitDelay);
                      }
                      await AppRestartService.instance.exitCurrentProcess(
                        ticket: ticket,
                      );
                    } catch (error, stack) {
                      await ticket?.cancel();
                      silentLog('settings_system', '重启应用', error, stack);
                      final message = _formatRestartFailure(
                        dialogContext.mounted ? dialogContext : context,
                        error,
                      );
                      if (dialogContext.mounted) {
                        setDialogState(() {
                          restarting = false;
                        });
                        showOpenHandErrorSnack(dialogContext, message);
                      } else if (mounted) {
                        showOpenHandErrorSnack(context, message);
                      }
                    }
                  },
          ),
          OpenHandDialogActionButton.primary(
            label: AppLocalizations.of(dialogContext)!.commonClose,
            onPressed: restarting
                ? null
                : () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  Duration _resolveDialogExitDelay(BuildContext context) {
    try {
      final settings = openHandMotionSettingsOf(
        context,
        OpenHandMotionSettingsScope.dialog,
      );
      if (settings.exitDisabled) {
        return Duration.zero;
      }
      return settings.exitDuration + const Duration(milliseconds: 40);
    } catch (_) {
      return const Duration(milliseconds: 400);
    }
  }

  String _formatRestartFailure(BuildContext context, Object error) {
    if (error is AppRestartException) {
      return switch (error.failure) {
        AppRestartFailure.missingExecutable => openHandLocalizedText(
          context,
          zh: '重启失败：无法定位当前应用可执行文件。',
          en: 'Restart failed: current app executable was not found.',
        ),
        AppRestartFailure.prepareFailed => openHandLocalizedText(
          context,
          zh: '重启失败：无法准备新的应用实例，请手动退出后重新打开。',
          en: 'Restart failed: could not prepare a new app instance. Please quit and reopen manually.',
        ),
        AppRestartFailure.exitCanceled => openHandLocalizedText(
          context,
          zh: '重启已取消：当前应用没有退出。',
          en: 'Restart canceled: the current app did not exit.',
        ),
        AppRestartFailure.unsupportedPlatform => openHandLocalizedText(
          context,
          zh: '当前平台暂不支持应用内重启，请手动退出后重新打开。',
          en: 'In-app restart is not supported on this platform. Please quit and reopen manually.',
        ),
      };
    }
    return openHandLocalizedText(
      context,
      zh: '重启失败，请手动退出后重新打开应用。',
      en: 'Restart failed. Please quit and reopen the app manually.',
    );
  }

  String _formatRepairReport(InputRepairReport report) {
    String resultLabel(InputRepairResult result) => switch (result) {
      InputRepairResult.success => '成功',
      InputRepairResult.partialSuccess => '部分成功',
      InputRepairResult.failure => '失败',
    };
    String statusLabel(InputRepairStepStatus status) => switch (status) {
      InputRepairStepStatus.success => '成功',
      InputRepairStepStatus.warning => '警告',
      InputRepairStepStatus.failure => '失败',
    };
    String stageLabel(InputRepairStage stage) => switch (stage) {
      InputRepairStage.resetParticipantsBefore => '重置前通知参与者',
      InputRepairStage.killTrackedChildren => '回收已跟踪子进程',
      InputRepairStage.killDirectChildren => '回收直接子进程',
      InputRepairStage.clearTextInputClient => '清理文本输入客户端',
      InputRepairStage.hideTextInput => '隐藏文本输入',
      InputRepairStage.finishAutofillContext => '结束自动填充上下文',
      InputRepairStage.requestExistingInputState => '请求现有输入状态',
      InputRepairStage.focusSentinel => '聚焦修复哨兵',
      InputRepairStage.restoreSafeFocus => '恢复安全焦点',
      InputRepairStage.resetParticipantsAfter => '重置后通知参与者',
    };

    final buffer = StringBuffer()
      ..writeln('结果：${resultLabel(report.result)}')
      ..writeln('修复前已跟踪子进程：${report.trackedChildrenBefore}')
      ..writeln('已回收直接子进程：${report.directChildrenKilled}')
      ..writeln('修复前焦点：${report.primaryFocusBeforeLabel ?? '-'}')
      ..writeln('修复后焦点：${report.primaryFocusAfterLabel ?? '-'}')
      ..writeln('已恢复焦点：${report.restoredFocusLabel ?? '-'}');
    for (final step in report.steps) {
      buffer.writeln(
        '${stageLabel(step.stage)}：${statusLabel(step.status)}${step.message == null || step.message!.isEmpty ? '' : '（${step.message}）'}',
      );
    }
    return buffer.toString().trimRight();
  }

  /// 依次通知参与者、回收子进程、重置平台输入通道并恢复安全焦点。
  /// 单步异常写入报告，后续可恢复步骤继续执行。
  Future<void> _runRepair(BuildContext context) async {
    if (_repairing) return;
    final sentinelFocusNode = InputRepairSentinelScope.maybeOf(context);
    if (sentinelFocusNode == null) return;
    setState(() {
      _repairing = true;
    });
    final l10n = AppLocalizations.of(context)!;
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
      silentLog('settings_system', '修复文本输入', error, stack);
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

    if (context.mounted) {
      final total = report.trackedChildrenBefore + report.directChildrenKilled;
      final detail = total > 0
          ? l10n.inputRepairDoneDetail(total)
          : l10n.inputRepairDone;
      switch (report.result) {
        case InputRepairResult.success:
          showOpenHandSuccessSnack(context, detail);
          unawaited(_showRepairReportDialog(report));
        case InputRepairResult.partialSuccess:
          showOpenHandInfoSnack(context, detail);
          unawaited(_showRepairReportDialog(report));
        case InputRepairResult.failure:
          showOpenHandErrorSnack(context, l10n.inputRepairDone);
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
              borderRadius: BorderRadius.circular(kOpenHandRadius14),
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
          kOpenHandGap4,
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

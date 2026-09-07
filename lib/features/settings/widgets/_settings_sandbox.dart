part of 'settings_view.dart';

class _SandboxSettingsSection extends StatefulWidget {
  const _SandboxSettingsSection({
    required this.settingsController,
    required this.onPersistenceFailure,
  });

  final SettingsController settingsController;
  final VoidCallback onPersistenceFailure;

  @override
  State<_SandboxSettingsSection> createState() =>
      _SandboxSettingsSectionState();
}

class _SandboxSettingsSectionState extends State<_SandboxSettingsSection> {
  static const double _providerListMaxHeight = 560;

  late final TextEditingController _httpProxyPortController;
  late final TextEditingController _socksProxyPortController;
  final ScrollController _providerScrollController = ScrollController();
  final Set<AiSandboxProvider> _expandedProviders = <AiSandboxProvider>{};
  late AiSandboxService _sandboxService;
  late AiSandboxSettings _serviceSettings;
  Future<AiSandboxEnvironmentStatus>? _statusFuture;
  String _actionMessage = '';
  String _actionCommand = '';

  static const List<String> _sandboxableTools = <String>[
    'Bash',
    'BashBackground',
  ];

  @override
  void initState() {
    super.initState();
    _httpProxyPortController = TextEditingController();
    _socksProxyPortController = TextEditingController();
    _serviceSettings = widget.settingsController.aiSandboxSettings;
    _sandboxService = AiSandboxService(settings: _serviceSettings);
    _syncControllers();
    _statusFuture = _sandboxService.detectEnvironment();
  }

  @override
  void didUpdateWidget(covariant _SandboxSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final settings = widget.settingsController.aiSandboxSettings;
    if (!identical(oldWidget.settingsController, widget.settingsController) ||
        _serviceSettings != settings) {
      _serviceSettings = settings;
      _sandboxService.settings = settings;
      _syncControllers();
      _statusFuture = _sandboxService.detectEnvironment(refresh: true);
    }
  }

  @override
  void dispose() {
    _httpProxyPortController.dispose();
    _socksProxyPortController.dispose();
    _providerScrollController.dispose();
    unawaited(_sandboxService.shutdown());
    super.dispose();
  }

  void _syncControllers() {
    final settings = widget.settingsController.aiSandboxSettings;
    _httpProxyPortController.text = settings.httpProxyPort <= 0
        ? ''
        : '${settings.httpProxyPort}';
    _socksProxyPortController.text = settings.socksProxyPort <= 0
        ? ''
        : '${settings.socksProxyPort}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsController.aiSandboxSettings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        kOpenHandGap24,
        Divider(color: colorScheme.outlineVariant),
        kOpenHandGap18,
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              openHandSandboxLabel(context),
              style: theme.textTheme.titleMedium,
            ),
            _OfflineSpeechBadge(
              label: '1 个本地服务',
              color: theme.colorScheme.primary,
            ),
            _OfflineSpeechBadge(
              label: '1 个在线服务',
              color: theme.colorScheme.tertiary,
            ),
          ],
        ),
        kOpenHandGap8,
        Text(
          openHandLocalizedText(
            context,
            zh: '统一管理本地 OS 与在线 E2B 沙箱，任意时刻仅启用一种服务。',
            en: 'Manage local OS and online E2B sandboxes. Only one service can be active at a time.',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap16,
        _buildProviderList(context, settings),
        kOpenHandGap14,
        _ResponsiveSettingRow(
          title: openHandLocalizedText(
            context,
            zh: '环境不可用时阻断',
            en: 'Fail If Unavailable',
          ),
          subtitle: openHandLocalizedText(
            context,
            zh: '沙盒启用但依赖缺失时直接拦截命令，避免静默变成非沙盒执行。',
            en: 'Block commands when sandbox dependencies are missing instead of silently running unsandboxed.',
          ),
          control: _SettingsSwitch(
            value: settings.failIfUnavailable,
            onChanged: (value) =>
                _update(settings.copyWith(failIfUnavailable: value)),
          ),
        ),
        kOpenHandGap14,
        _ResponsiveSettingRow(
          title: openHandLocalizedText(
            context,
            zh: '允许排除命令非沙盒执行',
            en: 'Allow Excluded Commands Unsandboxed',
          ),
          subtitle: openHandLocalizedText(
            context,
            zh: '关闭时，命中排除列表的命令会被拦截而不是降级执行。',
            en: 'When off, commands matching the exclusion list are blocked instead of downgraded.',
          ),
          control: _SettingsSwitch(
            value: settings.allowUnsandboxedCommands,
            onChanged: (value) =>
                _update(settings.copyWith(allowUnsandboxedCommands: value)),
          ),
        ),
        kOpenHandGap14,
        _ResponsiveSettingRow(
          title: openHandLocalizedText(
            context,
            zh: '沙盒命令跳过写命令确认',
            en: 'Auto-allow Sandboxed Writes',
          ),
          subtitle: openHandLocalizedText(
            context,
            zh: '仅在当前所选沙箱实际生效时跳过 Bash 与 BashBackground 写命令确认；默认关闭。',
            en: 'Skip Bash and BashBackground write confirmation only when the selected sandbox is active. Off by default.',
          ),
          control: _SettingsSwitch(
            value: settings.autoAllowBashIfSandboxed,
            onChanged: (value) =>
                _update(settings.copyWith(autoAllowBashIfSandboxed: value)),
          ),
        ),
        kOpenHandGap14,
        _ResponsiveSettingRow(
          title: openHandLocalizedText(
            context,
            zh: '无域名规则时允许网络',
            en: 'Allow Network Without Domain Rules',
          ),
          subtitle: openHandLocalizedText(
            context,
            zh: settings.provider == AiSandboxProvider.e2b
                ? '关闭后，无规则时将禁用 E2B 外网访问；下方允许/禁止规则会合并到 E2B network.allowOut / denyOut。'
                : '关闭后，无域名规则的沙盒命令会禁用网络；配置域名规则时会启动本地过滤代理。macOS 会阻断直连绕过；Linux 严格模式会阻断尚无法强制过滤的域名规则。',
            en: settings.provider == AiSandboxProvider.e2b
                ? 'When off, E2B internet access is disabled without rules. Rules below merge into E2B network.allowOut and denyOut.'
                : 'When off, sandboxed commands without domain rules run with networking disabled. Domain rules start a local filtering proxy. macOS blocks direct bypass; Linux strict mode blocks domain rules that cannot be enforced yet.',
          ),
          control: _SettingsSwitch(
            value: settings.allowNetworkWhenNoDomainRules,
            onChanged: (value) => _update(
              settings.copyWith(allowNetworkWhenNoDomainRules: value),
            ),
          ),
        ),
        kOpenHandGap18,
        _buildToolChips(context, settings),
        kOpenHandGap18,
        if (settings.provider == AiSandboxProvider.operatingSystem) ...[
          _buildProxyPorts(context, settings),
          kOpenHandGap20,
          _buildFileRules(context, settings),
        ],
        kOpenHandGap20,
        _buildPatternRules(
          context: context,
          title: openHandLocalizedText(
            context,
            zh: '排除命令列表',
            en: 'Excluded Commands',
          ),
          body: openHandLocalizedText(
            context,
            zh: '命中这些规则的命令不会进入沙盒；是否允许降级执行由上方开关控制。',
            en: 'Commands matching these rules do not enter the sandbox; the downgrade policy is controlled above.',
          ),
          icon: Icons.remove_circle_outline_rounded,
          rules: settings.excludedCommands,
          onAdd: () => _showPatternRuleDialog(
            title: openHandLocalizedText(
              context,
              zh: '新增排除命令',
              en: 'Add Excluded Command',
            ),
            hint: 'npm run dev *',
            onSaved: (rule) => _update(
              settings.copyWith(
                excludedCommands: <AiSandboxPatternRule>[
                  ...settings.excludedCommands,
                  rule,
                ],
              ),
            ),
          ),
          onEdit: (rule) => _showPatternRuleDialog(
            title: openHandLocalizedText(
              context,
              zh: '编辑排除命令',
              en: 'Edit Excluded Command',
            ),
            hint: 'npm run dev *',
            initialRule: rule,
            onSaved: (updated) => _update(
              settings.copyWith(
                excludedCommands: _replacePatternRule(
                  settings.excludedCommands,
                  updated,
                ),
              ),
            ),
          ),
          onDelete: (rule) => _update(
            settings.copyWith(
              excludedCommands: settings.excludedCommands
                  .where((item) => item.id != rule.id)
                  .toList(growable: false),
            ),
          ),
        ),
        kOpenHandGap20,
        _buildPatternRules(
          context: context,
          title: openHandLocalizedText(
            context,
            zh: settings.provider == AiSandboxProvider.e2b
                ? 'E2B 允许出站规则'
                : '允许访问域名',
            en: settings.provider == AiSandboxProvider.e2b
                ? 'E2B Allow Out'
                : 'Allowed Domains',
          ),
          body: openHandLocalizedText(
            context,
            zh: settings.provider == AiSandboxProvider.e2b
                ? '与 E2B network.allowOut 合并，支持域名、通配域名、IP 与 CIDR；E2B 不接受正则。'
                : '用于本地沙盒代理过滤。简单模式支持 *，正则模式按原样匹配 host 或 host:port。',
            en: settings.provider == AiSandboxProvider.e2b
                ? 'Merged into E2B network.allowOut; supports domains, wildcard domains, IPs, and CIDRs.'
                : 'Used by the local sandbox proxy filter. Simple mode supports *, regex mode matches host or host:port as written.',
          ),
          icon: Icons.public_rounded,
          rules: settings.allowedDomains,
          simpleOnly: settings.provider == AiSandboxProvider.e2b,
          onAdd: () => _showPatternRuleDialog(
            title: openHandLocalizedText(
              context,
              zh: '新增允许域名',
              en: 'Add Allowed Domain',
            ),
            hint: '*.example.com',
            simpleOnly: settings.provider == AiSandboxProvider.e2b,
            onSaved: (rule) => _update(
              settings.copyWith(
                allowedDomains: <AiSandboxPatternRule>[
                  ...settings.allowedDomains,
                  rule,
                ],
              ),
            ),
          ),
          onEdit: (rule) => _showPatternRuleDialog(
            title: openHandLocalizedText(
              context,
              zh: '编辑允许域名',
              en: 'Edit Allowed Domain',
            ),
            hint: '*.example.com',
            initialRule: rule,
            simpleOnly: settings.provider == AiSandboxProvider.e2b,
            onSaved: (updated) => _update(
              settings.copyWith(
                allowedDomains: _replacePatternRule(
                  settings.allowedDomains,
                  updated,
                ),
              ),
            ),
          ),
          onDelete: (rule) => _update(
            settings.copyWith(
              allowedDomains: settings.allowedDomains
                  .where((item) => item.id != rule.id)
                  .toList(growable: false),
            ),
          ),
        ),
        kOpenHandGap20,
        _buildPatternRules(
          context: context,
          title: openHandLocalizedText(
            context,
            zh: settings.provider == AiSandboxProvider.e2b
                ? 'E2B 禁止出站规则'
                : '禁止访问域名',
            en: settings.provider == AiSandboxProvider.e2b
                ? 'E2B Deny Out'
                : 'Denied Domains',
          ),
          body: openHandLocalizedText(
            context,
            zh: settings.provider == AiSandboxProvider.e2b
                ? '与 E2B network.denyOut 合并；官方仅支持 IP 与 CIDR。allowOut 与 denyOut 冲突时允许规则优先。'
                : '用于沙盒代理过滤；命中禁止列表的域名应被代理拒绝。',
            en: settings.provider == AiSandboxProvider.e2b
                ? 'Merged into E2B network.denyOut; only IPs and CIDRs are supported.'
                : 'Used by the sandbox proxy filter; matching domains should be rejected by the proxy.',
          ),
          icon: Icons.public_off_rounded,
          rules: settings.deniedDomains,
          simpleOnly: settings.provider == AiSandboxProvider.e2b,
          onAdd: () => _showPatternRuleDialog(
            title: openHandLocalizedText(
              context,
              zh: '新增禁止域名',
              en: 'Add Denied Domain',
            ),
            hint: settings.provider == AiSandboxProvider.e2b
                ? '10.0.0.0/8'
                : '*.tracker.example',
            simpleOnly: settings.provider == AiSandboxProvider.e2b,
            ipOrCidrOnly: settings.provider == AiSandboxProvider.e2b,
            onSaved: (rule) => _update(
              settings.copyWith(
                deniedDomains: <AiSandboxPatternRule>[
                  ...settings.deniedDomains,
                  rule,
                ],
              ),
            ),
          ),
          onEdit: (rule) => _showPatternRuleDialog(
            title: openHandLocalizedText(
              context,
              zh: '编辑禁止域名',
              en: 'Edit Denied Domain',
            ),
            hint: settings.provider == AiSandboxProvider.e2b
                ? '10.0.0.0/8'
                : '*.tracker.example',
            initialRule: rule,
            simpleOnly: settings.provider == AiSandboxProvider.e2b,
            ipOrCidrOnly: settings.provider == AiSandboxProvider.e2b,
            onSaved: (updated) => _update(
              settings.copyWith(
                deniedDomains: _replacePatternRule(
                  settings.deniedDomains,
                  updated,
                ),
              ),
            ),
          ),
          onDelete: (rule) => _update(
            settings.copyWith(
              deniedDomains: settings.deniedDomains
                  .where((item) => item.id != rule.id)
                  .toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProviderList(BuildContext context, AiSandboxSettings settings) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _providerListMaxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest.withValues(
            alpha: 0.72,
          ),
          borderRadius: kOpenHandBorderRadius16,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.52),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: OpenHandSafeScrollbar(
            controller: _providerScrollController,
            child: ListView.separated(
              controller: _providerScrollController,
              primary: false,
              shrinkWrap: true,
              padding: const EdgeInsets.only(right: 4),
              itemCount: AiSandboxProvider.values.length,
              separatorBuilder: (_, _) => kOpenHandGap12,
              itemBuilder: (context, index) {
                final provider = AiSandboxProvider.values[index];
                return _buildProviderCard(context, settings, provider);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProviderCard(
    BuildContext context,
    AiSandboxSettings settings,
    AiSandboxProvider provider,
  ) {
    final theme = Theme.of(context);
    final online = provider == AiSandboxProvider.e2b;
    final selected = settings.provider == provider;
    final enabled = selected && settings.enabled;
    final expanded = _expandedProviders.contains(provider);
    final accent = online
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    final configured = !online || settings.e2b.isConfigured;
    final name = online ? 'E2B Cloud Sandbox' : 'OS Sandbox';
    final description = online
        ? openHandLocalizedText(
            context,
            zh: '通过 E2B 托管隔离环境执行命令，支持生命周期、网络、MCP、IAM 与卷挂载配置。',
            en: 'Run commands in E2B-hosted isolation with lifecycle, network, MCP, IAM, and volume configuration.',
          )
        : openHandLocalizedText(
            context,
            zh: '使用 macOS sandbox-exec 或 Linux bubblewrap 限制本机命令的文件与网络访问。',
            en: 'Restrict local command file and network access with macOS sandbox-exec or Linux bubblewrap.',
          );
    return AnimatedContainer(
      key: ValueKey<AiSandboxProvider>(provider),
      duration: openHandMotionDuration(context, kOpenHandMotion260),
      curve: kOpenHandEmphasizedCurve,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(
          color: enabled
              ? accent.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        color: Color.alphaBlend(
          accent.withValues(alpha: enabled ? 0.04 : 0),
          theme.colorScheme.surfaceContainer,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(
                          name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        _OfflineSpeechBadge(
                          label: online ? '在线' : '本地',
                          color: accent,
                        ),
                        _OfflineSpeechBadge(
                          label: configured ? '配置就绪' : '待补全',
                          color: configured
                              ? OpenHandStatusColors.success
                              : theme.colorScheme.error,
                        ),
                        if (enabled)
                          const _OfflineSpeechBadge(
                            label: '已启用',
                            color: OpenHandStatusColors.success,
                          ),
                        if (selected)
                          FutureBuilder<AiSandboxEnvironmentStatus>(
                            future: _statusFuture,
                            builder: (context, snapshot) {
                              final status = snapshot.data;
                              final waiting =
                                  snapshot.connectionState ==
                                  ConnectionState.waiting;
                              return _OfflineSpeechBadge(
                                label: waiting
                                    ? '检测中'
                                    : status?.available == true
                                    ? '环境可用'
                                    : '环境不可用',
                                color: waiting
                                    ? theme.colorScheme.secondary
                                    : status?.available == true
                                    ? OpenHandStatusColors.success
                                    : theme.colorScheme.error,
                              );
                            },
                          ),
                      ],
                    ),
                    kOpenHandGap5,
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    if (selected)
                      FutureBuilder<AiSandboxEnvironmentStatus>(
                        future: _statusFuture,
                        builder: (context, snapshot) {
                          final status = snapshot.data;
                          if (status == null || status.available) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              status.unavailableReason,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              kOpenHandHGap8,
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  if (!online) ...<Widget>[
                    _OfflineSpeechActionButton(
                      tooltip: openHandInstallLabel(context),
                      onPressed: () => _runEnvironmentAction(
                        _sandboxService.installEnvironment,
                      ),
                      child: const Icon(Icons.download_rounded, size: 22),
                    ),
                    _OfflineSpeechActionButton(
                      tooltip: openHandUpdateLabel(context),
                      onPressed: () => _runEnvironmentAction(
                        _sandboxService.updateEnvironment,
                      ),
                      child: const Icon(Icons.upgrade_rounded, size: 22),
                    ),
                    _OfflineSpeechActionButton(
                      tooltip: openHandUninstallLabel(context),
                      onPressed: () => _runEnvironmentAction(
                        _sandboxService.uninstallEnvironment,
                      ),
                      child: const Icon(Icons.delete_outline_rounded, size: 22),
                    ),
                  ] else
                    _OfflineSpeechActionButton(
                      tooltip: selected ? '检测 E2B 服务' : '选择 E2B 后可检测',
                      onPressed: selected
                          ? () => setState(() {
                              _statusFuture = _sandboxService.detectEnvironment(
                                refresh: true,
                              );
                            })
                          : null,
                      child: const Icon(Icons.science_rounded, size: 22),
                    ),
                  _AiProviderCardExpandButton(
                    expanded: expanded,
                    enabled: true,
                    onPressed: () {
                      setState(() {
                        expanded
                            ? _expandedProviders.remove(provider)
                            : _expandedProviders.add(provider);
                      });
                      HapticFeedback.selectionClick();
                    },
                  ),
                  Tooltip(
                    message: enabled ? '禁用沙箱' : '启用并切换到此沙箱',
                    child: _SettingsSwitch(
                      value: enabled,
                      onChanged: (value) => _update(
                        settings.copyWith(enabled: value, provider: provider),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          _AnimatedSettingReveal(
            visible: expanded,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: online
                  ? _E2bSandboxConfigEditor(
                      key: const ValueKey<String>('e2bSandboxConfig'),
                      settings: settings.e2b,
                      onChanged: (value) =>
                          _update(settings.copyWith(e2b: value)),
                    )
                  : selected
                  ? _buildEnvironmentCard(context)
                  : _AiTtsProviderSection(
                      title: '本地环境',
                      child: Text(
                        _actionMessage.isEmpty
                            ? '启用 OS Sandbox 后可检测当前平台环境。'
                            : '$_actionMessage${_actionCommand.isEmpty ? '' : '\n$_actionCommand'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvironmentCard(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(kOpenHandRadius18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<AiSandboxEnvironmentStatus>(
          future: _statusFuture,
          builder: (context, snapshot) {
            final status = snapshot.data;
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;
            final title = isLoading
                ? openHandLocalizedText(context, zh: '检测中', en: 'Detecting')
                : status?.available == true
                ? openHandLocalizedText(
                    context,
                    zh: '环境可用',
                    en: 'Environment Ready',
                  )
                : openHandLocalizedText(
                    context,
                    zh: '环境不可用',
                    en: 'Environment Unavailable',
                  );
            final body = status == null
                ? openHandLocalizedText(
                    context,
                    zh: '正在检测沙盒运行环境。',
                    en: 'Checking sandbox runtime environment.',
                  )
                : '${status.backend} · ${status.platform}${status.unavailableReason.isEmpty ? '' : '\n${status.unavailableReason}'}${status.warnings.isEmpty ? '' : '\n${status.warnings.join('\n')}'}';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      status?.available == true
                          ? Icons.check_circle_outline_rounded
                          : Icons.warning_amber_rounded,
                      color: status?.available == true
                          ? theme.colorScheme.secondary
                          : theme.colorScheme.error,
                    ),
                    kOpenHandHGap10,
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleSmall),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _statusFuture = _sandboxService.detectEnvironment(
                          refresh: true,
                        );
                      }),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        openHandLocalizedText(context, zh: '检测', en: 'Detect'),
                      ),
                    ),
                  ],
                ),
                kOpenHandGap8,
                Text(body, style: theme.textTheme.bodySmall),
                if (_actionMessage.isNotEmpty) ...[
                  kOpenHandGap12,
                  Text(_actionMessage, style: theme.textTheme.bodySmall),
                  if (_actionCommand.isNotEmpty) ...[
                    kOpenHandGap8,
                    SelectableText(
                      _actionCommand,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: kOpenHandMonospaceFontFamily,
                      ),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildToolChips(BuildContext context, AiSandboxSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          openHandLocalizedText(
            context,
            zh: '走沙盒的内建命令',
            en: 'Sandboxed Built-ins',
          ),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        kOpenHandGap10,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tool in _sandboxableTools)
              FilterChip(
                selected: settings.shouldSandboxBuiltinTool(tool),
                label: Text(tool),
                onSelected: (selected) {
                  final tools = settings.sandboxedBuiltinTools.toSet();
                  selected ? tools.add(tool) : tools.remove(tool);
                  _update(
                    settings.copyWith(
                      sandboxedBuiltinTools: tools.toList(growable: false),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildProxyPorts(BuildContext context, AiSandboxSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          openHandLocalizedText(
            context,
            zh: '沙盒代理端口',
            en: 'Sandbox Proxy Ports',
          ),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        kOpenHandGap6,
        Text(
          openHandLocalizedText(
            context,
            zh: 'HTTP 为空或 0 时自动选择临时端口；SOCKS 为空或 0 时不启用 SOCKS 入口。代理随沙盒命令启动并自动清理；Linux 关闭“环境不可用时阻断”后仅作为尽力而为的环境变量注入。',
            en: 'Blank or 0 HTTP uses an automatic temporary port; blank or 0 SOCKS disables the SOCKS entry point. The proxy starts per sandboxed command and is cleaned up automatically; on Linux with Fail If Unavailable off it is best-effort environment injection only.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        kOpenHandGap10,
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 180,
              child: TextField(
                controller: _httpProxyPortController,
                keyboardType: TextInputType.number,
                inputFormatters: const <TextInputFormatter>[],
                decoration: const InputDecoration(labelText: 'HTTP'),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _socksProxyPortController,
                keyboardType: TextInputType.number,
                inputFormatters: const <TextInputFormatter>[],
                decoration: const InputDecoration(labelText: 'SOCKS'),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _saveProxyPorts(settings),
              icon: const Icon(Icons.save_rounded),
              label: Text(AppLocalizations.of(context)!.settingsSave),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFileRules(BuildContext context, AiSandboxSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                openHandLocalizedText(
                  context,
                  zh: '文件路径与读写模式',
                  en: 'File Paths and Access',
                ),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _showFileRuleDialog(settings),
              icon: const Icon(Icons.add_rounded),
              label: Text(AppLocalizations.of(context)!.settingsAddRule),
            ),
          ],
        ),
        kOpenHandGap8,
        Text(
          openHandLocalizedText(
            context,
            zh: '路径支持简单模式（* 通配）和正则模式；默认 .openhand 为只读。rw 路径会在沙盒内开放写入。',
            en: 'Paths support simple mode (* wildcard) and regex mode. .openhand is read-only by default; rw paths are writable inside the sandbox.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        kOpenHandGap12,
        if (settings.filesystemRules.isEmpty)
          _SettingsStateBox(
            icon: Icons.folder_off_outlined,
            title: openHandLocalizedText(
              context,
              zh: '暂无文件规则',
              en: 'No file rules',
            ),
            body: openHandLocalizedText(
              context,
              zh: '添加规则以开放沙盒内的读写范围。',
              en: 'Add rules to define sandbox file access.',
            ),
          )
        else
          Column(
            children: [
              for (final rule in settings.filesystemRules) ...[
                _SandboxRuleTile(
                  icon: rule.accessMode == AiSandboxFileAccessMode.readWrite
                      ? Icons.edit_note_rounded
                      : Icons.visibility_outlined,
                  title: rule.path,
                  subtitle:
                      '${rule.accessMode.storageValue} · ${rule.matchMode.storageValue}${rule.note.trim().isEmpty ? '' : ' · ${rule.note.trim()}'}',
                  onEdit: () =>
                      _showFileRuleDialog(settings, initialRule: rule),
                  onDelete: () => _update(
                    settings.copyWith(
                      filesystemRules: settings.filesystemRules
                          .where((item) => item.id != rule.id)
                          .toList(growable: false),
                    ),
                  ),
                ),
                kOpenHandGap10,
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildPatternRules({
    required BuildContext context,
    required String title,
    required String body,
    required IconData icon,
    required List<AiSandboxPatternRule> rules,
    required VoidCallback onAdd,
    required void Function(AiSandboxPatternRule rule) onEdit,
    required void Function(AiSandboxPatternRule rule) onDelete,
    bool simpleOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(AppLocalizations.of(context)!.settingsAddRule),
            ),
          ],
        ),
        kOpenHandGap8,
        Text(body, style: Theme.of(context).textTheme.bodySmall),
        kOpenHandGap12,
        if (rules.isEmpty)
          _SettingsStateBox(
            icon: icon,
            title: openHandLocalizedText(context, zh: '暂无规则', en: 'No rules'),
            body: openHandLocalizedText(
              context,
              zh: simpleOnly ? '添加符合 E2B 约束的简单规则。' : '添加简单匹配或正则匹配规则。',
              en: simpleOnly
                  ? 'Add a simple rule accepted by E2B.'
                  : 'Add simple or regex matching rules.',
            ),
          )
        else
          Column(
            children: [
              for (final rule in rules) ...[
                _SandboxRuleTile(
                  icon: icon,
                  title: rule.pattern,
                  subtitle:
                      '${rule.matchMode.storageValue}${rule.note.trim().isEmpty ? '' : ' · ${rule.note.trim()}'}',
                  onEdit: () => onEdit(rule),
                  onDelete: () => onDelete(rule),
                ),
                kOpenHandGap10,
              ],
            ],
          ),
      ],
    );
  }

  Future<void> _runEnvironmentAction(
    Future<AiSandboxActionResult> Function() action,
  ) async {
    final result = await action();
    if (!mounted) return;
    setState(() {
      _actionMessage = result.message;
      _actionCommand = result.command;
      _statusFuture = _sandboxService.detectEnvironment(refresh: true);
    });
  }

  Future<void> _update(AiSandboxSettings settings) async {
    final saved = await widget.settingsController.updateAiSandboxSettings(
      settings,
    );
    if (!mounted) return;
    if (!saved) {
      widget.onPersistenceFailure();
      return;
    }
    _serviceSettings = settings;
    _sandboxService.settings = settings;
    setState(() {
      _statusFuture = _sandboxService.detectEnvironment(refresh: true);
    });
  }

  void _saveProxyPorts(AiSandboxSettings settings) {
    _update(
      settings.copyWith(
        httpProxyPort: _parsePort(_httpProxyPortController.text),
        socksProxyPort: _parsePort(_socksProxyPortController.text),
      ),
    );
  }

  int _parsePort(String value) {
    return tcpPortFromTextOr(value, fallback: 0);
  }

  Future<void> _showFileRuleDialog(
    AiSandboxSettings settings, {
    AiSandboxFileRule? initialRule,
  }) async {
    final result = await showAnimatedDialog<AiSandboxFileRule>(
      context: context,
      builder: (dialogContext) =>
          _SandboxFileRuleDialog(initialRule: initialRule),
    );
    if (result == null || !mounted) return;
    final rules = initialRule == null
        ? <AiSandboxFileRule>[...settings.filesystemRules, result]
        : settings.filesystemRules
              .map((item) => item.id == result.id ? result : item)
              .toList(growable: false);
    await _update(settings.copyWith(filesystemRules: rules));
  }

  Future<void> _showPatternRuleDialog({
    required String title,
    required String hint,
    required void Function(AiSandboxPatternRule rule) onSaved,
    AiSandboxPatternRule? initialRule,
    bool simpleOnly = false,
    bool ipOrCidrOnly = false,
  }) async {
    final result = await showAnimatedDialog<AiSandboxPatternRule>(
      context: context,
      builder: (dialogContext) => _SandboxPatternRuleDialog(
        title: title,
        hint: hint,
        initialRule: initialRule,
        simpleOnly: simpleOnly,
        ipOrCidrOnly: ipOrCidrOnly,
      ),
    );
    if (result == null || !mounted) return;
    onSaved(result);
  }

  List<AiSandboxPatternRule> _replacePatternRule(
    List<AiSandboxPatternRule> rules,
    AiSandboxPatternRule updated,
  ) {
    return rules
        .map((item) => item.id == updated.id ? updated : item)
        .toList(growable: false);
  }
}

class _E2bSandboxConfigEditor extends StatefulWidget {
  const _E2bSandboxConfigEditor({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final AiE2bSandboxSettings settings;
  final Future<void> Function(AiE2bSandboxSettings settings) onChanged;

  @override
  State<_E2bSandboxConfigEditor> createState() =>
      _E2bSandboxConfigEditorState();
}

class _E2bSandboxConfigEditorState extends State<_E2bSandboxConfigEditor> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  late AiE2bSandboxSettings _draft;
  bool _saving = false;
  bool _showSecrets = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.settings;
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _E2bSandboxConfigEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _draft = widget.settings;
      _syncControllers();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    final values = <String, String>{
      'apiKey': _draft.apiKey,
      'domain': _draft.domain,
      'apiUrl': _draft.apiUrl,
      'sandboxUrl': _draft.sandboxUrl,
      'requestTimeoutMs': '${_draft.requestTimeoutMs}',
      'proxy': _draft.proxy,
      'apiHeaders': _prettyJson(_draft.apiHeaders),
      'templateId': _draft.templateId,
      'timeoutSeconds': '${_draft.timeoutSeconds}',
      'allowOut': _prettyJson(_draft.allowOut),
      'denyOut': _prettyJson(_draft.denyOut),
      'egressProxyAddress': _draft.egressProxyAddress,
      'egressProxyUsername': _draft.egressProxyUsername,
      'egressProxyPassword': _draft.egressProxyPassword,
      'maskRequestHost': _draft.maskRequestHost,
      'networkRules': _prettyJson(_draft.networkRules),
      'metadata': _prettyJson(_draft.metadata),
      'environmentVariables': _prettyJson(_draft.environmentVariables),
      'mcp': _prettyJson(_draft.mcp),
      'iamTokens': _prettyJson(_draft.iamTokens),
      'volumeMounts': _prettyJson(
        _draft.volumeMounts.map((item) => item.toJson()).toList(),
      ),
      'commandUser': _draft.commandUser,
      'commandWorkingDirectory': _draft.commandWorkingDirectory,
    };
    for (final entry in values.entries) {
      final controller = _controllers.putIfAbsent(
        entry.key,
        TextEditingController.new,
      );
      _syncControllerText(controller, entry.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _AiTtsProviderSection(
            title: '连接配置',
            child: _AiTtsProviderFieldGrid(
              children: <Widget>[
                _field(
                  'apiKey',
                  'E2B API Key',
                  obscure: !_showSecrets,
                  suffix: IconButton(
                    tooltip: _showSecrets ? '隐藏密钥' : '显示密钥',
                    onPressed: () => setState(() {
                      _showSecrets = !_showSecrets;
                    }),
                    icon: Icon(
                      _showSecrets
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),
                _field('domain', 'Domain', required: true),
                _field('apiUrl', 'API URL（可选）', url: true),
                _field('sandboxUrl', 'Sandbox URL（可选）', url: true),
                _field(
                  'requestTimeoutMs',
                  '请求超时（ms，0 使用 60000）',
                  nonNegativeInteger: true,
                ),
                _field(
                  'proxy',
                  '客户端代理 URL（可选）',
                  url: true,
                  obscure: !_showSecrets,
                ),
                _jsonField('apiHeaders', 'API Headers · JSON 对象'),
              ],
            ),
          ),
          kOpenHandGap12,
          _AiTtsProviderSection(
            title: '创建与生命周期',
            child: _AiTtsProviderFieldGrid(
              children: <Widget>[
                _field('templateId', 'templateID', required: true),
                _field(
                  'timeoutSeconds',
                  'timeout（秒）',
                  nonNegativeInteger: true,
                ),
                _toggle(
                  'autoPause',
                  _draft.autoPause,
                  (value) => _setDraft(_draft.copyWith(autoPause: value)),
                ),
                _toggle(
                  'autoPauseMemory',
                  _draft.autoPauseMemory,
                  (value) => _setDraft(_draft.copyWith(autoPauseMemory: value)),
                ),
                _toggle(
                  'autoResume.enabled',
                  _draft.autoResumeEnabled,
                  (value) =>
                      _setDraft(_draft.copyWith(autoResumeEnabled: value)),
                ),
                _toggle(
                  'secure',
                  _draft.secure,
                  (value) => _setDraft(_draft.copyWith(secure: value)),
                ),
              ],
            ),
          ),
          kOpenHandGap12,
          _AiTtsProviderSection(
            title: '网络配置',
            child: _AiTtsProviderFieldGrid(
              children: <Widget>[
                _toggle(
                  'allow_internet_access',
                  _draft.allowInternetAccess,
                  (value) =>
                      _setDraft(_draft.copyWith(allowInternetAccess: value)),
                ),
                _toggle(
                  'network.allowPublicTraffic',
                  _draft.allowPublicTraffic,
                  (value) =>
                      _setDraft(_draft.copyWith(allowPublicTraffic: value)),
                ),
                _jsonField('allowOut', 'network.allowOut · JSON 数组'),
                _jsonField('denyOut', 'network.denyOut · JSON 数组'),
                _field('egressProxyAddress', 'network.egressProxy.address（可选）'),
                _field(
                  'egressProxyUsername',
                  'network.egressProxy.username（可选）',
                  maxLength: 255,
                ),
                _field(
                  'egressProxyPassword',
                  'network.egressProxy.password（可选）',
                  obscure: !_showSecrets,
                  maxLength: 255,
                ),
                _field('maskRequestHost', 'network.maskRequestHost（可选）'),
                _jsonField('networkRules', 'network.rules · JSON 对象'),
              ],
            ),
          ),
          kOpenHandGap12,
          _AiTtsProviderSection(
            title: '运行时与集成',
            child: _AiTtsProviderFieldGrid(
              children: <Widget>[
                _jsonField('metadata', 'metadata · JSON 字符串对象'),
                _jsonField('environmentVariables', 'envVars · JSON 字符串对象'),
                _jsonField('mcp', 'mcp · JSON 对象或 null'),
                _jsonField('iamTokens', 'iam.tokens · JSON 对象'),
                _jsonField(
                  'volumeMounts',
                  'volumeMounts · JSON 数组',
                  hint: '[{"name":"volume","path":"/data"}]',
                ),
                _field('commandUser', '命令用户（可选）'),
                _field('commandWorkingDirectory', '命令工作目录', required: true),
              ],
            ),
          ),
          if (_draft.autoPause &&
              !_draft.autoPauseMemory &&
              _draft.autoResumeEnabled) ...<Widget>[
            kOpenHandGap10,
            Text(
              'autoResume 不能与仅文件系统快照的 autoPause 组合使用。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          kOpenHandGap12,
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(AppLocalizations.of(context)!.settingsSave),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    bool nonNegativeInteger = false,
    bool url = false,
    bool obscure = false,
    int? maxLength,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: _controllers[key],
      obscureText: obscure,
      maxLength: maxLength,
      decoration: InputDecoration(labelText: label, suffixIcon: suffix),
      validator: (raw) {
        final value = (raw ?? '').trim();
        if (required && value.isEmpty) return '$label 不能为空。';
        if (nonNegativeInteger &&
            (int.tryParse(value) == null || int.parse(value) < 0)) {
          return '$label 必须为非负整数。';
        }
        if (url && value.isNotEmpty) {
          final uri = Uri.tryParse(value);
          if (uri == null ||
              (uri.scheme != 'http' && uri.scheme != 'https') ||
              uri.host.isEmpty) {
            return '$label 必须是有效的 HTTP(S) URL。';
          }
        }
        return null;
      },
    );
  }

  Widget _jsonField(String key, String label, {String? hint}) {
    return TextFormField(
      controller: _controllers[key],
      minLines: 2,
      maxLines: 5,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontFamily: kOpenHandMonospaceFontFamily),
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: (value) {
        try {
          final decoded = jsonDecode((value ?? '').trim());
          final expectsList =
              key == 'allowOut' || key == 'denyOut' || key == 'volumeMounts';
          if (expectsList && decoded is! List) return '$label 必须是 JSON 数组。';
          if (!expectsList && key == 'mcp' && decoded == null) return null;
          if (!expectsList && decoded is! Map) return '$label 必须是 JSON 对象。';
          if ((key == 'allowOut' || key == 'denyOut') &&
              (decoded as List).any((item) => item is! String)) {
            return '$label 的成员必须是字符串。';
          }
          if ((key == 'apiHeaders' ||
                  key == 'metadata' ||
                  key == 'environmentVariables') &&
              (decoded as Map).entries.any(
                (entry) => entry.key is! String || entry.value is! String,
              )) {
            return '$label 的键和值必须是字符串。';
          }
          if (key == 'volumeMounts') {
            for (final item in decoded as List) {
              if (item is! Map ||
                  '${item['name'] ?? ''}'.trim().isEmpty ||
                  '${item['path'] ?? ''}'.trim().isEmpty) {
                return '$label 的每项都需要非空 name 与 path。';
              }
            }
          }
          return null;
        } catch (_) {
          return '$label 不是有效 JSON。';
        }
      },
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return _AiTtsToggleField(label: label, value: value, onChanged: onChanged);
  }

  void _setDraft(AiE2bSandboxSettings value) {
    setState(() => _draft = value);
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true ||
        (_draft.autoPause &&
            !_draft.autoPauseMemory &&
            _draft.autoResumeEnabled)) {
      return;
    }
    setState(() => _saving = true);
    try {
      final mcp = _decodeJson('mcp');
      final volumes = (_decodeJson('volumeMounts') as List)
          .whereType<Map>()
          .map(
            (item) => AiE2bVolumeMount.fromJson(item.cast<String, Object?>()),
          )
          .where((item) => item.name.isNotEmpty && item.path.isNotEmpty)
          .toList(growable: false);
      await widget.onChanged(
        _draft.copyWith(
          apiKey: _text('apiKey'),
          domain: _text('domain'),
          apiUrl: _text('apiUrl'),
          sandboxUrl: _text('sandboxUrl'),
          requestTimeoutMs: int.parse(_text('requestTimeoutMs')),
          proxy: _text('proxy'),
          apiHeaders: _stringMap('apiHeaders'),
          templateId: _text('templateId'),
          timeoutSeconds: int.parse(_text('timeoutSeconds')),
          allowOut: _stringList('allowOut'),
          denyOut: _stringList('denyOut'),
          egressProxyAddress: _text('egressProxyAddress'),
          egressProxyUsername: _text('egressProxyUsername'),
          egressProxyPassword: _controllers['egressProxyPassword']!.text,
          maskRequestHost: _text('maskRequestHost'),
          networkRules: _objectMap('networkRules'),
          metadata: _stringMap('metadata'),
          environmentVariables: _stringMap('environmentVariables'),
          mcp: mcp is Map ? mcp.cast<String, Object?>() : null,
          clearMcp: mcp == null,
          iamTokens: _objectMap('iamTokens'),
          volumeMounts: volumes,
          commandUser: _text('commandUser'),
          commandWorkingDirectory: _text('commandWorkingDirectory'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _text(String key) => _controllers[key]!.text.trim();
  Object? _decodeJson(String key) => jsonDecode(_controllers[key]!.text.trim());

  List<String> _stringList(String key) => (_decodeJson(key) as List)
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);

  Map<String, Object?> _objectMap(String key) =>
      (_decodeJson(key) as Map).cast<String, Object?>();

  Map<String, String> _stringMap(String key) => <String, String>{
    for (final entry in (_decodeJson(key) as Map).entries)
      '${entry.key}': '${entry.value}',
  };

  static String _prettyJson(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);
}

class _SandboxRuleTile extends StatelessWidget {
  const _SandboxRuleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onEdit,
    required this.onDelete,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(kOpenHandRadius16),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: OpenHandRowEditDeleteActions(
          editTooltip: AppLocalizations.of(context)!.commonEdit,
          deleteTooltip: AppLocalizations.of(context)!.commonDelete,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
      ),
    );
  }
}

Widget _buildSandboxMatchModeField(
  BuildContext context, {
  required AiCommandMatchMode value,
  required ValueChanged<AiCommandMatchMode> onChanged,
  bool simpleOnly = false,
}) {
  return AnimatedDropdownButtonFormField<AiCommandMatchMode>(
    initialValue: value,
    decoration: InputDecoration(labelText: openHandMatchModeLabel(context)),
    items: [
      DropdownMenuItem(
        value: AiCommandMatchMode.simple,
        child: Text(openHandLocalizedText(context, zh: '简单匹配', en: 'Simple')),
      ),
      if (!simpleOnly)
        DropdownMenuItem(
          value: AiCommandMatchMode.regex,
          child: Text(openHandLocalizedText(context, zh: '正则匹配', en: 'Regex')),
        ),
    ],
    onChanged: (next) => onChanged(next ?? AiCommandMatchMode.simple),
  );
}

Widget _buildSandboxRuleDialog<T>({
  required BuildContext context,
  required Widget title,
  required GlobalKey<FormState> formKey,
  required List<Widget> fields,
  required T Function() createResult,
}) {
  return buildOpenHandAlertDialog(
    title: title,
    content: SizedBox(
      width: 560,
      child: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: fields),
      ),
    ),
    actions: [
      OpenHandDialogActionButton.secondary(
        onPressed: () => Navigator.of(context).pop(),
        label: AppLocalizations.of(context)!.commonCancel,
      ),
      OpenHandDialogActionButton.primary(
        onPressed: () {
          if (formKey.currentState?.validate() != true) return;
          Navigator.of(context).pop<T>(createResult());
        },
        label: AppLocalizations.of(context)!.commonSave,
      ),
    ],
  );
}

class _SandboxFileRuleDialog extends StatefulWidget {
  const _SandboxFileRuleDialog({this.initialRule});

  final AiSandboxFileRule? initialRule;

  @override
  State<_SandboxFileRuleDialog> createState() => _SandboxFileRuleDialogState();
}

class _SandboxFileRuleDialogState extends State<_SandboxFileRuleDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _pathController;
  late final TextEditingController _noteController;
  late AiSandboxFileAccessMode _accessMode;
  late AiCommandMatchMode _matchMode;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(
      text: widget.initialRule?.path ?? '',
    );
    _noteController = TextEditingController(
      text: widget.initialRule?.note ?? '',
    );
    _accessMode =
        widget.initialRule?.accessMode ?? AiSandboxFileAccessMode.readOnly;
    _matchMode = widget.initialRule?.matchMode ?? AiCommandMatchMode.simple;
  }

  @override
  void dispose() {
    _pathController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildSandboxRuleDialog<AiSandboxFileRule>(
      context: context,
      title: Text(
        widget.initialRule == null
            ? openHandLocalizedText(context, zh: '新增文件规则', en: 'Add File Rule')
            : openHandLocalizedText(
                context,
                zh: '编辑文件规则',
                en: 'Edit File Rule',
              ),
      ),
      formKey: _formKey,
      fields: [
        TextFormField(
          controller: _pathController,
          decoration: const InputDecoration(
            labelText: 'Path / Pattern',
            hintText: r'.openhand or ^/Users/.*/cache$',
          ),
          validator: (value) => (value ?? '').trim().isEmpty
              ? openHandLocalizedText(
                  context,
                  zh: '请输入路径。',
                  en: 'Enter a path.',
                )
              : null,
        ),
        kOpenHandGap14,
        AnimatedDropdownButtonFormField<AiSandboxFileAccessMode>(
          initialValue: _accessMode,
          decoration: InputDecoration(
            labelText: openHandLocalizedText(
              context,
              zh: '读写模式',
              en: 'Access Mode',
            ),
          ),
          items: const [
            DropdownMenuItem(
              value: AiSandboxFileAccessMode.readOnly,
              child: Text('ro'),
            ),
            DropdownMenuItem(
              value: AiSandboxFileAccessMode.readWrite,
              child: Text('rw'),
            ),
          ],
          onChanged: (value) => setState(() {
            _accessMode = value ?? AiSandboxFileAccessMode.readOnly;
          }),
        ),
        kOpenHandGap14,
        _buildSandboxMatchModeField(
          context,
          value: _matchMode,
          onChanged: (value) => setState(() => _matchMode = value),
        ),
        kOpenHandGap14,
        TextFormField(
          controller: _noteController,
          decoration: InputDecoration(
            labelText: _settingsSandboNoteLabel(context),
          ),
          maxLines: 2,
        ),
      ],
      createResult: () => AiSandboxFileRule(
        id: widget.initialRule?.id ?? _newSandboxRuleId(),
        path: _pathController.text.trim(),
        accessMode: _accessMode,
        matchMode: _matchMode,
        note: _noteController.text.trim(),
      ),
    );
  }
}

class _SandboxPatternRuleDialog extends StatefulWidget {
  const _SandboxPatternRuleDialog({
    required this.title,
    required this.hint,
    this.initialRule,
    this.simpleOnly = false,
    this.ipOrCidrOnly = false,
  });

  final String title;
  final String hint;
  final AiSandboxPatternRule? initialRule;
  final bool simpleOnly;
  final bool ipOrCidrOnly;

  @override
  State<_SandboxPatternRuleDialog> createState() =>
      _SandboxPatternRuleDialogState();
}

class _SandboxPatternRuleDialogState extends State<_SandboxPatternRuleDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _patternController;
  late final TextEditingController _noteController;
  late AiCommandMatchMode _matchMode;

  @override
  void initState() {
    super.initState();
    _patternController = TextEditingController(
      text: widget.initialRule?.pattern ?? '',
    );
    _noteController = TextEditingController(
      text: widget.initialRule?.note ?? '',
    );
    _matchMode = widget.simpleOnly
        ? AiCommandMatchMode.simple
        : widget.initialRule?.matchMode ?? AiCommandMatchMode.simple;
  }

  @override
  void dispose() {
    _patternController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildSandboxRuleDialog<AiSandboxPatternRule>(
      context: context,
      title: Text(widget.title),
      formKey: _formKey,
      fields: [
        TextFormField(
          controller: _patternController,
          decoration: InputDecoration(
            labelText: 'Pattern',
            hintText: widget.hint,
          ),
          validator: (value) {
            final normalized = (value ?? '').trim();
            if (normalized.isEmpty) {
              return openHandLocalizedText(
                context,
                zh: '请输入匹配表达式。',
                en: 'Enter a pattern.',
              );
            }
            if (widget.ipOrCidrOnly && !_isSandboxIpOrCidr(normalized)) {
              return 'E2B denyOut 仅支持 IP 或 CIDR。';
            }
            return null;
          },
        ),
        kOpenHandGap14,
        _buildSandboxMatchModeField(
          context,
          value: _matchMode,
          simpleOnly: widget.simpleOnly,
          onChanged: (value) => setState(() => _matchMode = value),
        ),
        kOpenHandGap14,
        TextFormField(
          controller: _noteController,
          decoration: InputDecoration(
            labelText: _settingsSandboNoteLabel(context),
          ),
          maxLines: 2,
        ),
      ],
      createResult: () => AiSandboxPatternRule(
        id: widget.initialRule?.id ?? _newSandboxRuleId(),
        pattern: _patternController.text.trim(),
        matchMode: _matchMode,
        note: _noteController.text.trim(),
      ),
    );
  }
}

String _newSandboxRuleId() =>
    'sandbox-${DateTime.now().microsecondsSinceEpoch}';

bool _isSandboxIpOrCidr(String value) {
  final parts = value.trim().split('/');
  if (parts.isEmpty || parts.length > 2) return false;
  try {
    final address = InternetAddress(parts.first);
    if (parts.length == 1) return true;
    final prefix = int.tryParse(parts[1]);
    final max = address.type == InternetAddressType.IPv4 ? 32 : 128;
    return prefix != null && prefix >= 0 && prefix <= max;
  } on ArgumentError {
    return false;
  }
}

String _settingsSandboNoteLabel(BuildContext context) {
  return openHandNoteLabel(context);
}

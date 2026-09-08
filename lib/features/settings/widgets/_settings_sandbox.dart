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
  final Set<AiSandboxProvider> _testingProviders = <AiSandboxProvider>{};
  late AiSandboxService _sandboxService;
  late AiSandboxSettings _serviceSettings;
  Future<AiSandboxEnvironmentStatus>? _statusFuture;
  late Future<AiSandboxEnvironmentStatus> _osStatusFuture;
  late final OpenHandDebouncer _proxySaveDebouncer;

  static const List<String> _sandboxableTools = <String>[
    'Bash',
    'BashBackground',
  ];

  @override
  void initState() {
    super.initState();
    _httpProxyPortController = TextEditingController();
    _socksProxyPortController = TextEditingController();
    _proxySaveDebouncer = OpenHandDebouncer(
      delay: const Duration(milliseconds: 420),
    );
    _serviceSettings = widget.settingsController.aiSandboxSettings;
    _sandboxService = AiSandboxService(settings: _serviceSettings);
    _syncControllers();
    _statusFuture = _sandboxService.detectEnvironment();
    _osStatusFuture = _detectProvider(AiSandboxProvider.operatingSystem);
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
      _osStatusFuture = _detectProvider(AiSandboxProvider.operatingSystem);
    }
  }

  @override
  void dispose() {
    _httpProxyPortController.dispose();
    _socksProxyPortController.dispose();
    _providerScrollController.dispose();
    _proxySaveDebouncer.dispose();
    unawaited(_sandboxService.shutdown());
    super.dispose();
  }

  void _syncControllers() {
    final settings = widget.settingsController.aiSandboxSettings;
    _syncControllerText(
      _httpProxyPortController,
      settings.httpProxyPort <= 0 ? '' : '${settings.httpProxyPort}',
    );
    _syncControllerText(
      _socksProxyPortController,
      settings.socksProxyPort <= 0 ? '' : '${settings.socksProxyPort}',
    );
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
              label: openHandLocalizedText(
                context,
                zh: '1 个本地服务',
                en: '1 Local Service',
              ),
              color: theme.colorScheme.primary,
            ),
            _OfflineSpeechBadge(
              label: openHandLocalizedText(
                context,
                zh: '1 个在线服务',
                en: '1 Online Service',
              ),
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
                ? '关闭后，无规则时将禁用 E2B 外网访问；下方的允许与禁止规则会自动合并。'
                : '关闭后，无域名规则的沙盒命令会禁用网络；配置域名规则时会启动本地过滤代理。macOS 会阻断直连绕过；Linux 严格模式会阻断尚无法强制过滤的域名规则。',
            en: settings.provider == AiSandboxProvider.e2b
                ? 'When off, E2B internet access is disabled without rules. The allow and deny rules below are merged automatically.'
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
                ? '与 E2B 允许规则合并，支持域名、通配域名、IP 与 CIDR；E2B 不接受正则。'
                : '用于本地沙盒代理过滤。简单模式支持 *，正则模式按原样匹配 host 或 host:port。',
            en: settings.provider == AiSandboxProvider.e2b
                ? 'Merged into E2B allow rules; supports domains, wildcard domains, IPs, and CIDRs.'
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
                ? '与 E2B 禁止规则合并；仅支持 IP 与 CIDR。与允许规则冲突时，允许规则优先。'
                : '用于沙盒代理过滤；命中禁止列表的域名应被代理拒绝。',
            en: settings.provider == AiSandboxProvider.e2b
                ? 'Merged into E2B deny rules; only IPs and CIDRs are supported. Allow rules take precedence on conflicts.'
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
    final name = online
        ? openHandLocalizedText(
            context,
            zh: 'E2B 云端沙盒',
            en: 'E2B Cloud Sandbox',
          )
        : openHandLocalizedText(context, zh: '操作系统沙盒', en: 'OS Sandbox');
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
                          label: online
                              ? openHandLocalizedText(
                                  context,
                                  zh: '在线',
                                  en: 'Online',
                                )
                              : openHandLocalizedText(
                                  context,
                                  zh: '本地',
                                  en: 'Local',
                                ),
                          color: accent,
                        ),
                        _OfflineSpeechBadge(
                          label: configured
                              ? openHandLocalizedText(
                                  context,
                                  zh: '配置就绪',
                                  en: 'Configured',
                                )
                              : openHandLocalizedText(
                                  context,
                                  zh: '待补全',
                                  en: 'Incomplete',
                                ),
                          color: configured
                              ? OpenHandStatusColors.success
                              : theme.colorScheme.error,
                        ),
                        if (enabled)
                          _OfflineSpeechBadge(
                            label: openHandLocalizedText(
                              context,
                              zh: '已启用',
                              en: 'Enabled',
                            ),
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
                                    ? openHandLocalizedText(
                                        context,
                                        zh: '检测中',
                                        en: 'Testing',
                                      )
                                    : status?.available == true
                                    ? openHandLocalizedText(
                                        context,
                                        zh: '环境可用',
                                        en: 'Available',
                                      )
                                    : openHandLocalizedText(
                                        context,
                                        zh: '环境不可用',
                                        en: 'Unavailable',
                                      ),
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
                  if (!online)
                    FutureBuilder<AiSandboxEnvironmentStatus>(
                      future: _osStatusFuture,
                      builder: (context, snapshot) {
                        final status = snapshot.data;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: <Widget>[
                            if (status?.resourceManaged == true &&
                                status?.resourceInstalled == false)
                              _sandboxResourceButton(
                                context,
                                action: AiSandboxResourceAction.install,
                              ),
                            if (status?.resourceManaged == true &&
                                status?.resourceInstalled == true &&
                                status?.resourceUpdateAvailable == true)
                              _sandboxResourceButton(
                                context,
                                action: AiSandboxResourceAction.update,
                              ),
                            if (status?.resourceManaged == true &&
                                status?.resourceInstalled == true)
                              _sandboxResourceButton(
                                context,
                                action: AiSandboxResourceAction.uninstall,
                              ),
                          ],
                        );
                      },
                    ),
                  _OfflineSpeechActionButton(
                    tooltip: openHandLocalizedText(
                      context,
                      zh: online ? '测试 E2B 沙盒' : '测试本地沙盒',
                      en: online ? 'Test E2B Sandbox' : 'Test Local Sandbox',
                    ),
                    onPressed: _testingProviders.contains(provider)
                        ? null
                        : () => _showEnvironmentTest(provider, settings),
                    child: _testingProviders.contains(provider)
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.science_rounded,
                            size: 22,
                            weight: 500,
                            opticalSize: 22,
                          ),
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
                    message: enabled
                        ? openHandLocalizedText(
                            context,
                            zh: '禁用沙盒',
                            en: 'Disable Sandbox',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '启用并切换到此沙盒',
                            en: 'Enable and Select This Sandbox',
                          ),
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
                      onChanged: (value) => _update(
                        settings.copyWith(e2b: value),
                        refreshEnvironment: false,
                      ),
                    )
                  : selected
                  ? _buildEnvironmentCard(context)
                  : _AiTtsProviderSection(
                      title: openHandLocalizedText(
                        context,
                        zh: '本地环境',
                        en: 'Local Environment',
                      ),
                      child: Text(
                        openHandLocalizedText(
                          context,
                          zh: '点击卡片右上角的测试按钮，可检测当前平台沙盒环境。',
                          en: 'Use the test button in the card header to check the local sandbox environment.',
                        ),
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
                  ],
                ),
                kOpenHandGap8,
                Text(body, style: theme.textTheme.bodySmall),
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
                onChanged: (_) => _scheduleProxySave(settings),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _socksProxyPortController,
                keyboardType: TextInputType.number,
                inputFormatters: const <TextInputFormatter>[],
                decoration: const InputDecoration(labelText: 'SOCKS'),
                onChanged: (_) => _scheduleProxySave(settings),
              ),
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
          OpenHandRemovableListScope(
            builder: (context, removal) => Column(
              children: <Widget>[
                for (final rule in settings.filesystemRules)
                  SettingsAwareAppearOnce(
                    key: ValueKey<String>('sandbox-file-rule-${rule.id}'),
                    child: OpenHandListRemovalTransition(
                      collapsed: removal.isRemoving(rule.id),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SandboxRuleTile(
                          icon:
                              rule.accessMode ==
                                  AiSandboxFileAccessMode.readWrite
                              ? Icons.edit_note_rounded
                              : Icons.visibility_outlined,
                          title: rule.path,
                          subtitle:
                              '${rule.accessMode.storageValue} · ${rule.matchMode.storageValue}${rule.note.trim().isEmpty ? '' : ' · ${rule.note.trim()}'}',
                          onEdit: () =>
                              _showFileRuleDialog(settings, initialRule: rule),
                          onDelete: () => unawaited(
                            removal.run(
                              rule.id,
                              () => _update(
                                settings.copyWith(
                                  filesystemRules: settings.filesystemRules
                                      .where((item) => item.id != rule.id)
                                      .toList(growable: false),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
    required Future<void> Function(AiSandboxPatternRule rule) onDelete,
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
          OpenHandRemovableListScope(
            builder: (context, removal) => Column(
              children: <Widget>[
                for (final rule in rules)
                  SettingsAwareAppearOnce(
                    key: ValueKey<String>('sandbox-pattern-rule-${rule.id}'),
                    child: OpenHandListRemovalTransition(
                      collapsed: removal.isRemoving(rule.id),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SandboxRuleTile(
                          icon: icon,
                          title: rule.pattern,
                          subtitle:
                              '${rule.matchMode.storageValue}${rule.note.trim().isEmpty ? '' : ' · ${rule.note.trim()}'}',
                          onEdit: () => onEdit(rule),
                          onDelete: () => unawaited(
                            removal.run(rule.id, () => onDelete(rule)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sandboxResourceButton(
    BuildContext context, {
    required AiSandboxResourceAction action,
  }) {
    final label = switch (action) {
      AiSandboxResourceAction.install => openHandInstallLabel(context),
      AiSandboxResourceAction.update => openHandUpdateLabel(context),
      AiSandboxResourceAction.uninstall => openHandUninstallLabel(context),
    };
    final icon = switch (action) {
      AiSandboxResourceAction.install => Icons.download_for_offline_outlined,
      AiSandboxResourceAction.update => Icons.system_update_alt_rounded,
      AiSandboxResourceAction.uninstall => Icons.delete_outline_rounded,
    };
    return _OfflineSpeechActionButton(
      tooltip: label,
      onPressed: () => _showResourceAction(action),
      child: Icon(icon, size: 22, weight: 500, opticalSize: 22),
    );
  }

  Future<void> _showEnvironmentTest(
    AiSandboxProvider provider,
    AiSandboxSettings settings,
  ) async {
    setState(() => _testingProviders.add(provider));
    try {
      await showOpenHandProfiledDialog<void>(
        context: context,
        barrierDismissible: false,
        dismissOnEscape: false,
        transitionProfile: const OpenHandAnimationTransitionProfile(
          fadeScaleBegin: 0.9,
          elasticScaleBegin: 0.9,
          springScaleBegin: 0.9,
          slideUpOffset: Offset(0, 0.1),
          slideDownOffset: Offset(0, -0.1),
        ),
        builder: (_) => _SandboxEnvironmentTestDialog(
          provider: provider,
          settings: settings.copyWith(provider: provider),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _testingProviders.remove(provider);
          if (provider == settings.provider) {
            _statusFuture = _sandboxService.detectEnvironment(refresh: true);
          }
          if (provider == AiSandboxProvider.operatingSystem) {
            _osStatusFuture = _detectProvider(provider);
          }
        });
      }
    }
  }

  Future<void> _showResourceAction(AiSandboxResourceAction action) async {
    final actionLabel = switch (action) {
      AiSandboxResourceAction.install => openHandInstallLabel(context),
      AiSandboxResourceAction.update => openHandUpdateLabel(context),
      AiSandboxResourceAction.uninstall => openHandUninstallLabel(context),
    };
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '$actionLabel本地沙盒资源？',
        en: '$actionLabel Local Sandbox Resource?',
      ),
      message: openHandLocalizedText(
        context,
        zh: action == AiSandboxResourceAction.uninstall
            ? '系统包管理器将移除 bubblewrap，完成后本地沙盒会暂时不可用。'
            : '系统包管理器将维护 bubblewrap，过程中请保持网络连接并完成系统授权。',
        en: action == AiSandboxResourceAction.uninstall
            ? 'The system package manager will remove bubblewrap, making the local sandbox unavailable.'
            : 'The system package manager will maintain bubblewrap. Keep the network connected and complete system authorization.',
      ),
      confirmLabel: actionLabel,
      destructive: action == AiSandboxResourceAction.uninstall,
    );
    if (!confirmed || !mounted) return;
    await showOpenHandProfiledDialog<void>(
      context: context,
      barrierDismissible: false,
      dismissOnEscape: false,
      transitionProfile: const OpenHandAnimationTransitionProfile(
        fadeScaleBegin: 0.9,
        elasticScaleBegin: 0.9,
        springScaleBegin: 0.9,
        slideUpOffset: Offset(0, 0.1),
        slideDownOffset: Offset(0, -0.1),
      ),
      builder: (_) => _SandboxResourceActionDialog(
        service: _sandboxService,
        action: action,
      ),
    );
    if (!mounted) return;
    setState(() {
      _osStatusFuture = _detectProvider(AiSandboxProvider.operatingSystem);
      if (_serviceSettings.provider == AiSandboxProvider.operatingSystem) {
        _statusFuture = _sandboxService.detectEnvironment(refresh: true);
      }
    });
  }

  Future<void> _update(
    AiSandboxSettings settings, {
    bool refreshEnvironment = true,
  }) async {
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
      if (refreshEnvironment) {
        _statusFuture = _sandboxService.detectEnvironment(refresh: true);
        _osStatusFuture = _detectProvider(AiSandboxProvider.operatingSystem);
      }
    });
  }

  Future<AiSandboxEnvironmentStatus> _detectProvider(
    AiSandboxProvider provider,
  ) async {
    final service = AiSandboxService(
      settings: _serviceSettings.copyWith(provider: provider),
    );
    try {
      return await service.detectEnvironment(refresh: true);
    } finally {
      await service.shutdown();
    }
  }

  void _scheduleProxySave(AiSandboxSettings settings) {
    _proxySaveDebouncer.schedule(
      () => _update(
        settings.copyWith(
          httpProxyPort: _parsePort(_httpProxyPortController.text),
          socksProxyPort: _parsePort(_socksProxyPortController.text),
        ),
      ),
      onError: (error, stack) =>
          silentLog('settings_sandbox', '自动保存沙盒代理端口', error, stack),
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
  bool _showSecrets = false;
  late final OpenHandDebouncer _saveDebouncer;
  int _saveRevision = 0;

  @override
  void initState() {
    super.initState();
    _draft = widget.settings;
    _saveDebouncer = OpenHandDebouncer(
      delay: const Duration(milliseconds: 420),
    );
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _E2bSandboxConfigEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings &&
        widget.settings != _draft &&
        !_saveDebouncer.isActive) {
      _draft = widget.settings;
      _syncControllers();
    }
  }

  @override
  void dispose() {
    _saveDebouncer.dispose();
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
      'templateId': _draft.templateId,
      'timeoutSeconds': '${_draft.timeoutSeconds}',
      'egressProxyAddress': _draft.egressProxyAddress,
      'egressProxyUsername': _draft.egressProxyUsername,
      'egressProxyPassword': _draft.egressProxyPassword,
      'maskRequestHost': _draft.maskRequestHost,
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
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _AiTtsProviderSection(
            title: _textFor(zh: '连接配置', en: 'Connection'),
            child: _AiTtsProviderFieldGrid(
              children: <Widget>[
                _field(
                  'apiKey',
                  _textFor(zh: 'E2B 接口密钥', en: 'E2B API Key'),
                  obscure: !_showSecrets,
                  suffix: IconButton(
                    style: _sandboxInputIconButtonStyle,
                    tooltip: _showSecrets
                        ? _textFor(zh: '隐藏密钥', en: 'Hide Secret')
                        : _textFor(zh: '显示密钥', en: 'Show Secret'),
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
                _field(
                  'domain',
                  _textFor(zh: '服务域名', en: 'Service Domain'),
                  required: true,
                ),
                _field(
                  'apiUrl',
                  _textFor(zh: '接口地址（可选）', en: 'API URL (Optional)'),
                  url: true,
                ),
                _field(
                  'sandboxUrl',
                  _textFor(zh: '沙盒地址（可选）', en: 'Sandbox URL (Optional)'),
                  url: true,
                ),
                _field(
                  'requestTimeoutMs',
                  _textFor(
                    zh: '请求超时（毫秒，0 使用 60000）',
                    en: 'Request Timeout (ms, 0 Uses 60000)',
                  ),
                  nonNegativeInteger: true,
                ),
                _field(
                  'proxy',
                  _textFor(
                    zh: '客户端代理地址（可选）',
                    en: 'Client Proxy URL (Optional)',
                  ),
                  url: true,
                  obscure: !_showSecrets,
                ),
                _stringMapField(
                  title: _textFor(zh: '接口请求头', en: 'API Headers'),
                  description: _textFor(
                    zh: '随 E2B 接口请求发送的自定义请求头。',
                    en: 'Custom headers sent with E2B API requests.',
                  ),
                  values: _draft.apiHeaders,
                  secret: true,
                  onChanged: (value) =>
                      _commit(_draft.copyWith(apiHeaders: value)),
                ),
              ],
            ),
          ),
          kOpenHandGap12,
          _AiTtsProviderSection(
            title: _textFor(zh: '创建与生命周期', en: 'Creation and Lifecycle'),
            child: _AiTtsProviderFieldGrid(
              children: <Widget>[
                _field(
                  'templateId',
                  _textFor(zh: '模板标识', en: 'Template ID'),
                  required: true,
                ),
                _field(
                  'timeoutSeconds',
                  _textFor(zh: '生存时间（秒）', en: 'Lifetime (Seconds)'),
                  nonNegativeInteger: true,
                ),
                _toggle(
                  _textFor(zh: '超时后自动暂停', en: 'Auto-pause on Timeout'),
                  _draft.autoPause,
                  (value) => _commit(_draft.copyWith(autoPause: value)),
                ),
                _toggle(
                  _textFor(zh: '暂停时保留内存', en: 'Preserve Memory When Paused'),
                  _draft.autoPauseMemory,
                  (value) => _commit(_draft.copyWith(autoPauseMemory: value)),
                ),
                _toggle(
                  _textFor(zh: '允许自动恢复', en: 'Enable Auto-resume'),
                  _draft.autoResumeEnabled,
                  (value) => _commit(_draft.copyWith(autoResumeEnabled: value)),
                ),
                _toggle(
                  _textFor(zh: '保护系统通信', en: 'Secure System Traffic'),
                  _draft.secure,
                  (value) => _commit(_draft.copyWith(secure: value)),
                ),
              ],
            ),
          ),
          kOpenHandGap12,
          _AiTtsProviderSection(
            title: _textFor(zh: '网络配置', en: 'Network'),
            child: Column(
              children: <Widget>[
                _AiTtsProviderFieldGrid(
                  children: <Widget>[
                    _toggle(
                      _textFor(zh: '允许访问互联网', en: 'Allow Internet Access'),
                      _draft.allowInternetAccess,
                      (value) =>
                          _commit(_draft.copyWith(allowInternetAccess: value)),
                    ),
                    _toggle(
                      _textFor(
                        zh: '允许公开访问沙盒地址',
                        en: 'Allow Public Sandbox Traffic',
                      ),
                      _draft.allowPublicTraffic,
                      (value) =>
                          _commit(_draft.copyWith(allowPublicTraffic: value)),
                    ),
                    _field(
                      'egressProxyAddress',
                      _textFor(
                        zh: '出站代理地址（可选）',
                        en: 'Egress Proxy Address (Optional)',
                      ),
                    ),
                    _field(
                      'egressProxyUsername',
                      _textFor(
                        zh: '出站代理用户名（可选）',
                        en: 'Egress Proxy Username (Optional)',
                      ),
                      maxLength: 255,
                    ),
                    _field(
                      'egressProxyPassword',
                      _textFor(
                        zh: '出站代理密码（可选）',
                        en: 'Egress Proxy Password (Optional)',
                      ),
                      obscure: !_showSecrets,
                      maxLength: 255,
                    ),
                    _field(
                      'maskRequestHost',
                      _textFor(
                        zh: '请求主机掩码（可选）',
                        en: 'Request Host Mask (Optional)',
                      ),
                    ),
                  ],
                ),
                kOpenHandGap12,
                _stringListField(
                  title: _textFor(zh: '允许的出站目标', en: 'Allowed Destinations'),
                  description: _textFor(
                    zh: '支持域名、通配域名、IP 地址和 CIDR。允许规则优先于禁止规则。',
                    en: 'Supports domains, wildcard domains, IP addresses, and CIDR blocks. Allow rules take precedence.',
                  ),
                  values: _draft.allowOut,
                  onChanged: (value) =>
                      _commit(_draft.copyWith(allowOut: value)),
                ),
                kOpenHandGap10,
                _stringListField(
                  title: _textFor(zh: '禁止的出站目标', en: 'Denied Destinations'),
                  description: _textFor(
                    zh: '官方仅支持 IP 地址和 CIDR。',
                    en: 'Only IP addresses and CIDR blocks are supported.',
                  ),
                  values: _draft.denyOut,
                  ipOrCidrOnly: true,
                  onChanged: (value) =>
                      _commit(_draft.copyWith(denyOut: value)),
                ),
                kOpenHandGap10,
                _networkRulesField(),
              ],
            ),
          ),
          kOpenHandGap12,
          _AiTtsProviderSection(
            title: _textFor(zh: '运行时与集成', en: 'Runtime and Integrations'),
            child: Column(
              children: <Widget>[
                _AiTtsProviderFieldGrid(
                  children: <Widget>[
                    _field(
                      'commandUser',
                      _textFor(zh: '命令用户（可选）', en: 'Command User (Optional)'),
                    ),
                    _field(
                      'commandWorkingDirectory',
                      _textFor(zh: '命令工作目录', en: 'Command Working Directory'),
                      required: true,
                    ),
                  ],
                ),
                kOpenHandGap12,
                _stringMapField(
                  title: _textFor(zh: '沙盒元数据', en: 'Sandbox Metadata'),
                  description: _textFor(
                    zh: '附加到沙盒的字符串键值信息。',
                    en: 'String key-value metadata attached to the sandbox.',
                  ),
                  values: _draft.metadata,
                  onChanged: (value) =>
                      _commit(_draft.copyWith(metadata: value)),
                ),
                kOpenHandGap10,
                _stringMapField(
                  title: _textFor(zh: '环境变量', en: 'Environment Variables'),
                  description: _textFor(
                    zh: '创建沙盒时注入的环境变量。',
                    en: 'Environment variables injected when creating the sandbox.',
                  ),
                  values: _draft.environmentVariables,
                  secret: true,
                  onChanged: (value) =>
                      _commit(_draft.copyWith(environmentVariables: value)),
                ),
                kOpenHandGap10,
                _mcpField(),
                kOpenHandGap10,
                _iamTokensField(),
                kOpenHandGap10,
                _volumeMountsField(),
              ],
            ),
          ),
          if (_draft.autoPause &&
              !_draft.autoPauseMemory &&
              _draft.autoResumeEnabled) ...<Widget>[
            kOpenHandGap10,
            Text(
              _textFor(
                zh: '仅保存文件系统快照时不能启用自动恢复。',
                en: 'Auto-resume cannot be enabled with filesystem-only snapshots.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          kOpenHandGap10,
          Row(
            children: <Widget>[
              Icon(
                Icons.cloud_done_outlined,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              kOpenHandHGap6,
              Text(
                _textFor(
                  zh: '配置修改后自动保存',
                  en: 'Configuration changes are saved automatically',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
        if (required && value.isEmpty) {
          return _textFor(zh: '$label 不能为空。', en: '$label cannot be empty.');
        }
        if (nonNegativeInteger) {
          final parsed = int.tryParse(value);
          if (parsed == null || parsed < 0) {
            return _textFor(
              zh: '$label 必须为非负整数。',
              en: '$label must be a non-negative integer.',
            );
          }
        }
        if (url && value.isNotEmpty) {
          final uri = Uri.tryParse(value);
          if (uri == null ||
              (uri.scheme != 'http' && uri.scheme != 'https') ||
              uri.host.isEmpty) {
            return _textFor(
              zh: '$label 必须是有效的 HTTP(S) 地址。',
              en: '$label must be a valid HTTP(S) URL.',
            );
          }
        }
        return null;
      },
      onChanged: (_) => _scheduleSave(),
    );
  }

  Widget _stringMapField({
    required String title,
    required String description,
    required Map<String, String> values,
    required ValueChanged<Map<String, String>> onChanged,
    bool secret = false,
  }) {
    final entries = values.entries.toList(growable: false);
    return _E2bStructuredField(
      icon: Icons.key_rounded,
      title: title,
      description: description,
      entries: <_E2bStructuredEntry>[
        for (final entry in entries)
          _E2bStructuredEntry(
            id: entry.key,
            title: entry.key,
            subtitle: secret
                ? _textFor(zh: '值已安全保存', en: 'Value Saved Securely')
                : entry.value,
          ),
      ],
      onAdd: () => _editStringMapEntry(
        title: title,
        values: values,
        onChanged: onChanged,
        secret: secret,
      ),
      onEdit: (id) => _editStringMapEntry(
        title: title,
        values: values,
        onChanged: onChanged,
        initialKey: id,
        secret: secret,
      ),
      onDelete: (id) {
        final updated = Map<String, String>.of(values)..remove(id);
        onChanged(updated);
      },
    );
  }

  Widget _stringListField({
    required String title,
    required String description,
    required List<String> values,
    required ValueChanged<List<String>> onChanged,
    bool ipOrCidrOnly = false,
  }) {
    return _E2bStructuredField(
      icon: Icons.route_outlined,
      title: title,
      description: description,
      entries: <_E2bStructuredEntry>[
        for (var index = 0; index < values.length; index++)
          _E2bStructuredEntry(
            id: '$index',
            title: values[index],
            subtitle: _textFor(zh: '出站目标', en: 'Destination'),
          ),
      ],
      onAdd: () => _editStringListEntry(
        title: title,
        values: values,
        onChanged: onChanged,
        ipOrCidrOnly: ipOrCidrOnly,
      ),
      onEdit: (id) => _editStringListEntry(
        title: title,
        values: values,
        onChanged: onChanged,
        initialIndex: int.tryParse(id),
        ipOrCidrOnly: ipOrCidrOnly,
      ),
      onDelete: (id) {
        final index = int.tryParse(id);
        if (index == null || index < 0 || index >= values.length) return;
        final updated = List<String>.of(values)..removeAt(index);
        onChanged(updated);
      },
    );
  }

  Widget _networkRulesField() {
    final rules = _readNetworkRules(_draft.networkRules);
    return _E2bStructuredField(
      icon: Icons.account_tree_outlined,
      title: _textFor(zh: '按域名变换请求头', en: 'Per-domain Header Transformations'),
      description: _textFor(
        zh: '为匹配域名的出站 HTTP 请求注入或覆盖请求头；域名仍需加入允许列表。',
        en: 'Inject or replace headers for matching outbound HTTP requests. The domain must also be allowed.',
      ),
      entries: <_E2bStructuredEntry>[
        for (final rule in rules)
          _E2bStructuredEntry(
            id: rule.id,
            title: rule.domain,
            subtitle: _textFor(
              zh: '${rule.headers.length} 个请求头',
              en: '${rule.headers.length} Headers',
            ),
          ),
      ],
      onAdd: () => _editNetworkRule(rules: rules),
      onEdit: (id) => _editNetworkRule(
        rules: rules,
        initial: rules.where((item) => item.id == id).firstOrNull,
      ),
      onDelete: (id) => _saveNetworkRules(
        rules.where((item) => item.id != id).toList(growable: false),
      ),
    );
  }

  Widget _mcpField() {
    final servers = _readMcpServers(_draft.mcp);
    return _E2bStructuredField(
      icon: Icons.hub_outlined,
      title: _textFor(zh: 'MCP 服务', en: 'MCP Servers'),
      description: _textFor(
        zh: '配置由 E2B MCP 网关启动的服务及其参数；未添加时不启用 MCP。',
        en: 'Configure servers and parameters started by the E2B MCP gateway. MCP stays disabled when empty.',
      ),
      entries: <_E2bStructuredEntry>[
        for (final server in servers)
          _E2bStructuredEntry(
            id: server.name,
            title: server.name,
            subtitle: _textFor(
              zh: '${server.parameters.length} 个参数',
              en: '${server.parameters.length} Parameters',
            ),
          ),
      ],
      onAdd: () => _editMcpServer(servers: servers),
      onEdit: (id) => _editMcpServer(
        servers: servers,
        initial: servers.where((item) => item.name == id).firstOrNull,
      ),
      onDelete: (id) => _saveMcpServers(
        servers.where((item) => item.name != id).toList(growable: false),
      ),
    );
  }

  Widget _iamTokensField() {
    final tokens = _readIamTokens(_draft.iamTokens);
    return _E2bStructuredField(
      icon: Icons.verified_user_outlined,
      title: _textFor(zh: '工作负载身份令牌', en: 'Workload Identity Tokens'),
      description: _textFor(
        zh: '每个命名令牌都需要受众和令牌类型。至少配置一项才会启用工作负载身份。',
        en: 'Each named token requires an audience and token type. Workload identity is enabled only when at least one token is configured.',
      ),
      entries: <_E2bStructuredEntry>[
        for (final token in tokens)
          _E2bStructuredEntry(
            id: token.name,
            title: token.name,
            subtitle: '${token.audience} · ${token.tokenType}',
          ),
      ],
      onAdd: () => _editIamToken(tokens: tokens),
      onEdit: (id) => _editIamToken(
        tokens: tokens,
        initial: tokens.where((item) => item.name == id).firstOrNull,
      ),
      onDelete: (id) => _saveIamTokens(
        tokens.where((item) => item.name != id).toList(growable: false),
      ),
    );
  }

  Widget _volumeMountsField() {
    final mounts = _draft.volumeMounts;
    return _E2bStructuredField(
      icon: Icons.storage_rounded,
      title: _textFor(zh: '卷挂载', en: 'Volume Mounts'),
      description: _textFor(
        zh: '将已存在的 E2B 卷挂载到沙盒内的指定路径。',
        en: 'Mount existing E2B volumes at selected sandbox paths.',
      ),
      entries: <_E2bStructuredEntry>[
        for (var index = 0; index < mounts.length; index++)
          _E2bStructuredEntry(
            id: '$index',
            title: mounts[index].name,
            subtitle: mounts[index].path,
          ),
      ],
      onAdd: () => _editVolumeMount(mounts: mounts),
      onEdit: (id) =>
          _editVolumeMount(mounts: mounts, initialIndex: int.tryParse(id)),
      onDelete: (id) {
        final index = int.tryParse(id);
        if (index == null || index < 0 || index >= mounts.length) return;
        final updated = List<AiE2bVolumeMount>.of(mounts)..removeAt(index);
        _commit(_draft.copyWith(volumeMounts: updated));
      },
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return _AiTtsToggleField(label: label, value: value, onChanged: onChanged);
  }

  String _textFor({required String zh, required String en}) =>
      openHandLocalizedText(context, zh: zh, en: en);

  String _text(String key) => _controllers[key]!.text.trim();

  AiE2bSandboxSettings? _candidateFromInputs([AiE2bSandboxSettings? base]) {
    final requestTimeoutMs = int.tryParse(_text('requestTimeoutMs'));
    final timeoutSeconds = int.tryParse(_text('timeoutSeconds'));
    if (requestTimeoutMs == null ||
        requestTimeoutMs < 0 ||
        timeoutSeconds == null ||
        timeoutSeconds < 0 ||
        _text('domain').isEmpty ||
        _text('templateId').isEmpty ||
        _text('commandWorkingDirectory').isEmpty) {
      return null;
    }
    final source = base ?? _draft;
    return source.copyWith(
      apiKey: _text('apiKey'),
      domain: _text('domain'),
      apiUrl: _text('apiUrl'),
      sandboxUrl: _text('sandboxUrl'),
      requestTimeoutMs: requestTimeoutMs,
      proxy: _text('proxy'),
      templateId: _text('templateId'),
      timeoutSeconds: timeoutSeconds,
      egressProxyAddress: _text('egressProxyAddress'),
      egressProxyUsername: _text('egressProxyUsername'),
      egressProxyPassword: _controllers['egressProxyPassword']!.text,
      maskRequestHost: _text('maskRequestHost'),
      commandUser: _text('commandUser'),
      commandWorkingDirectory: _text('commandWorkingDirectory'),
    );
  }

  void _scheduleSave() {
    _saveDebouncer.schedule(
      () {
        if (!mounted || _formKey.currentState?.validate() != true) return;
        final candidate = _candidateFromInputs();
        if (candidate != null) _persist(candidate);
      },
      onError: (error, stack) {
        silentLog('settings_sandbox', '自动保存 E2B 沙盒配置', error, stack);
      },
    );
  }

  void _commit(AiE2bSandboxSettings value) {
    _saveDebouncer.cancel();
    final candidate = _candidateFromInputs(value) ?? value;
    setState(() => _draft = candidate);
    if (candidate.autoPause &&
        !candidate.autoPauseMemory &&
        candidate.autoResumeEnabled) {
      return;
    }
    _persist(candidate);
  }

  void _persist(AiE2bSandboxSettings value) {
    if (value == widget.settings) return;
    final revision = ++_saveRevision;
    _draft = value;
    unawaited(() async {
      await widget.onChanged(value);
      if (!mounted || revision != _saveRevision) return;
      setState(() {});
    }());
  }

  Future<void> _editStringMapEntry({
    required String title,
    required Map<String, String> values,
    required ValueChanged<Map<String, String>> onChanged,
    String? initialKey,
    bool secret = false,
  }) async {
    final result = await showAnimatedDialog<_E2bKeyValueEntry>(
      context: context,
      builder: (_) => _E2bKeyValueDialog(
        title: title,
        initial: initialKey == null
            ? null
            : _E2bKeyValueEntry(initialKey, values[initialKey] ?? ''),
        secret: secret,
      ),
    );
    if (result == null || !mounted) return;
    final updated = Map<String, String>.of(values);
    if (initialKey != null && initialKey != result.key) {
      updated.remove(initialKey);
    }
    updated[result.key] = result.value;
    onChanged(updated);
  }

  Future<void> _editStringListEntry({
    required String title,
    required List<String> values,
    required ValueChanged<List<String>> onChanged,
    required bool ipOrCidrOnly,
    int? initialIndex,
  }) async {
    final result = await showAnimatedDialog<String>(
      context: context,
      builder: (_) => _E2bTextValueDialog(
        title: title,
        initialValue: initialIndex == null ? '' : values[initialIndex],
        ipOrCidrOnly: ipOrCidrOnly,
      ),
    );
    if (result == null || !mounted) return;
    final updated = List<String>.of(values);
    if (initialIndex == null) {
      if (!updated.contains(result)) updated.add(result);
    } else {
      updated[initialIndex] = result;
    }
    onChanged(updated.toSet().toList(growable: false));
  }

  List<_E2bNetworkRuleRecord> _readNetworkRules(Map<String, Object?> source) {
    final result = <_E2bNetworkRuleRecord>[];
    for (final domainEntry in source.entries) {
      final rawRules = domainEntry.value;
      if (rawRules is! List) continue;
      for (var index = 0; index < rawRules.length; index++) {
        final rule = rawRules[index];
        if (rule is! Map) continue;
        final transform = rule['transform'];
        final headers = transform is Map ? transform['headers'] : null;
        result.add(
          _E2bNetworkRuleRecord(
            id: '${domainEntry.key}\u0000$index',
            domain: domainEntry.key,
            headers: <String, String>{
              if (headers is Map)
                for (final entry in headers.entries)
                  '${entry.key}': '${entry.value}',
            },
          ),
        );
      }
    }
    return result;
  }

  Future<void> _editNetworkRule({
    required List<_E2bNetworkRuleRecord> rules,
    _E2bNetworkRuleRecord? initial,
  }) async {
    final result = await showAnimatedDialog<_E2bNetworkRuleRecord>(
      context: context,
      builder: (_) => _E2bNetworkRuleDialog(initial: initial),
    );
    if (result == null || !mounted) return;
    final updated =
        rules.where((item) => item.id != initial?.id).toList(growable: true)
          ..add(result);
    _saveNetworkRules(updated);
  }

  void _saveNetworkRules(List<_E2bNetworkRuleRecord> rules) {
    final grouped = <String, List<Object?>>{};
    for (final rule in rules) {
      grouped.putIfAbsent(rule.domain, () => <Object?>[]).add(<String, Object?>{
        'transform': <String, Object?>{'headers': rule.headers},
      });
    }
    _commit(_draft.copyWith(networkRules: grouped));
  }

  List<_E2bMcpServerRecord> _readMcpServers(Map<String, Object?>? source) =>
      <_E2bMcpServerRecord>[
        for (final entry in (source ?? const <String, Object?>{}).entries)
          _E2bMcpServerRecord(
            name: entry.key,
            parameters: entry.value is Map
                ? (entry.value as Map).cast<String, Object?>()
                : const <String, Object?>{},
          ),
      ];

  Future<void> _editMcpServer({
    required List<_E2bMcpServerRecord> servers,
    _E2bMcpServerRecord? initial,
  }) async {
    final result = await showAnimatedDialog<_E2bMcpServerRecord>(
      context: context,
      builder: (_) => _E2bMcpServerDialog(initial: initial),
    );
    if (result == null || !mounted) return;
    final updated =
        servers
            .where((item) => item.name != initial?.name)
            .toList(growable: true)
          ..add(result);
    _saveMcpServers(updated);
  }

  void _saveMcpServers(List<_E2bMcpServerRecord> servers) {
    if (servers.isEmpty) {
      _commit(_draft.copyWith(clearMcp: true));
      return;
    }
    _commit(
      _draft.copyWith(
        mcp: <String, Object?>{
          for (final server in servers) server.name: server.parameters,
        },
      ),
    );
  }

  List<_E2bIamTokenRecord> _readIamTokens(Map<String, Object?> source) =>
      <_E2bIamTokenRecord>[
        for (final entry in source.entries)
          if (entry.value is Map)
            _E2bIamTokenRecord(
              name: entry.key,
              audience: '${(entry.value as Map)['audience'] ?? ''}',
              tokenType: '${(entry.value as Map)['tokenType'] ?? ''}',
            ),
      ];

  Future<void> _editIamToken({
    required List<_E2bIamTokenRecord> tokens,
    _E2bIamTokenRecord? initial,
  }) async {
    final result = await showAnimatedDialog<_E2bIamTokenRecord>(
      context: context,
      builder: (_) => _E2bIamTokenDialog(initial: initial),
    );
    if (result == null || !mounted) return;
    final updated =
        tokens
            .where((item) => item.name != initial?.name)
            .toList(growable: true)
          ..add(result);
    _saveIamTokens(updated);
  }

  void _saveIamTokens(List<_E2bIamTokenRecord> tokens) {
    _commit(
      _draft.copyWith(
        iamTokens: <String, Object?>{
          for (final token in tokens)
            token.name: <String, Object?>{
              'audience': token.audience,
              'tokenType': token.tokenType,
            },
        },
      ),
    );
  }

  Future<void> _editVolumeMount({
    required List<AiE2bVolumeMount> mounts,
    int? initialIndex,
  }) async {
    final result = await showAnimatedDialog<AiE2bVolumeMount>(
      context: context,
      builder: (_) => _E2bVolumeMountDialog(
        initial: initialIndex == null ? null : mounts[initialIndex],
      ),
    );
    if (result == null || !mounted) return;
    final updated = List<AiE2bVolumeMount>.of(mounts);
    if (initialIndex == null) {
      updated.add(result);
    } else {
      updated[initialIndex] = result;
    }
    _commit(_draft.copyWith(volumeMounts: updated));
  }
}

class _E2bStructuredEntry {
  const _E2bStructuredEntry({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final String title;
  final String subtitle;
}

class _E2bStructuredField extends StatelessWidget {
  const _E2bStructuredField({
    required this.icon,
    required this.title,
    required this.description,
    required this.entries,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<_E2bStructuredEntry> entries;
  final VoidCallback onAdd;
  final ValueChanged<String> onEdit;
  final FutureOr<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.72),
      borderRadius: kOpenHandBorderRadius16,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.58,
                    ),
                    borderRadius: kOpenHandBorderRadius12,
                  ),
                  child: Icon(icon, size: 19, color: theme.colorScheme.primary),
                ),
                kOpenHandHGap10,
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Tooltip(
                  message: AppLocalizations.of(context)!.settingsAddRule,
                  child: IconButton.filledTonal(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
              ],
            ),
            kOpenHandGap6,
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            AnimatedSwitcher(
              duration: openHandMotionDuration(context, kOpenHandMotion260),
              switchInCurve: kOpenHandSwitchInCurve,
              switchOutCurve: kOpenHandSwitchOutCurve,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  alignment: AlignmentDirectional.topCenter,
                  child: child,
                ),
              ),
              child: entries.isEmpty
                  ? Padding(
                      key: const ValueKey<String>('empty'),
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        openHandLocalizedText(
                          context,
                          zh: '暂未配置，点击右上角添加。',
                          en: 'Not configured. Use Add in the upper-right.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : OpenHandRemovableListScope(
                      key: const ValueKey<String>('entries'),
                      builder: (context, removal) => Column(
                        children: <Widget>[
                          kOpenHandGap10,
                          for (final entry in entries)
                            SettingsAwareAppearOnce(
                              key: ValueKey<String>(
                                'e2b-structured-entry-${entry.id}',
                              ),
                              child: OpenHandListRemovalTransition(
                                collapsed: removal.isRemoving(entry.id),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Material(
                                    color: theme.colorScheme.surfaceContainer,
                                    borderRadius: kOpenHandBorderRadius12,
                                    child: ListTile(
                                      dense: true,
                                      title: Text(entry.title),
                                      subtitle: Text(
                                        entry.subtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: _SandboxEditDeleteActions(
                                        editTooltip: AppLocalizations.of(
                                          context,
                                        )!.commonEdit,
                                        deleteTooltip: AppLocalizations.of(
                                          context,
                                        )!.commonDelete,
                                        onEdit: () => onEdit(entry.id),
                                        onDelete: () => unawaited(
                                          removal.run(entry.id, () async {
                                            await onDelete(entry.id);
                                          }),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _E2bKeyValueEntry {
  const _E2bKeyValueEntry(this.key, this.value);

  final String key;
  final String value;
}

class _E2bNetworkRuleRecord {
  const _E2bNetworkRuleRecord({
    required this.id,
    required this.domain,
    required this.headers,
  });

  final String id;
  final String domain;
  final Map<String, String> headers;
}

class _E2bMcpServerRecord {
  const _E2bMcpServerRecord({required this.name, required this.parameters});

  final String name;
  final Map<String, Object?> parameters;
}

class _E2bIamTokenRecord {
  const _E2bIamTokenRecord({
    required this.name,
    required this.audience,
    required this.tokenType,
  });

  final String name;
  final String audience;
  final String tokenType;
}

class _E2bKeyValueDialog extends StatefulWidget {
  const _E2bKeyValueDialog({
    required this.title,
    required this.initial,
    required this.secret,
  });

  final String title;
  final _E2bKeyValueEntry? initial;
  final bool secret;

  @override
  State<_E2bKeyValueDialog> createState() => _E2bKeyValueDialogState();
}

class _E2bKeyValueDialogState extends State<_E2bKeyValueDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _keyController;
  late final TextEditingController _valueController;
  bool _showValue = false;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.initial?.key ?? '');
    _valueController = TextEditingController(text: widget.initial?.value ?? '');
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildSandboxRuleDialog<_E2bKeyValueEntry>(
      context: context,
      title: Text(widget.title),
      formKey: _formKey,
      fields: <Widget>[
        TextFormField(
          controller: _keyController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: openHandLocalizedText(context, zh: '名称', en: 'Name'),
          ),
          validator: (value) => _requiredDialogValue(context, value),
        ),
        kOpenHandGap12,
        TextFormField(
          controller: _valueController,
          obscureText: widget.secret && !_showValue,
          decoration: InputDecoration(
            labelText: openHandLocalizedText(context, zh: '值', en: 'Value'),
            suffixIcon: widget.secret
                ? IconButton(
                    style: _sandboxInputIconButtonStyle,
                    tooltip: _showValue
                        ? openHandLocalizedText(
                            context,
                            zh: '隐藏内容',
                            en: 'Hide Value',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '显示内容',
                            en: 'Show Value',
                          ),
                    onPressed: () => setState(() => _showValue = !_showValue),
                    icon: Icon(
                      _showValue
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  )
                : null,
          ),
          validator: (value) => _requiredDialogValue(context, value),
        ),
      ],
      createResult: () =>
          _E2bKeyValueEntry(_keyController.text.trim(), _valueController.text),
    );
  }
}

const ButtonStyle _sandboxInputIconButtonStyle = ButtonStyle(
  backgroundColor: WidgetStatePropertyAll<Color>(Colors.transparent),
  overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent),
  shadowColor: WidgetStatePropertyAll<Color>(Colors.transparent),
  surfaceTintColor: WidgetStatePropertyAll<Color>(Colors.transparent),
  elevation: WidgetStatePropertyAll<double>(0),
);
const double _sandboxDialogFieldHeight = 60;

class _E2bTextValueDialog extends StatefulWidget {
  const _E2bTextValueDialog({
    required this.title,
    required this.initialValue,
    required this.ipOrCidrOnly,
  });

  final String title;
  final String initialValue;
  final bool ipOrCidrOnly;

  @override
  State<_E2bTextValueDialog> createState() => _E2bTextValueDialogState();
}

class _E2bTextValueDialogState extends State<_E2bTextValueDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildSandboxRuleDialog<String>(
      context: context,
      title: Text(widget.title),
      formKey: _formKey,
      fields: <Widget>[
        TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: openHandLocalizedText(
              context,
              zh: '目标',
              en: 'Destination',
            ),
          ),
          validator: (value) {
            final requiredError = _requiredDialogValue(context, value);
            if (requiredError != null) return requiredError;
            if (widget.ipOrCidrOnly && !isValidIpOrCidr(value!)) {
              return openHandLocalizedText(
                context,
                zh: '请输入有效的 IP 地址或 CIDR。',
                en: 'Enter a valid IP address or CIDR block.',
              );
            }
            return null;
          },
        ),
      ],
      createResult: () => _controller.text.trim(),
    );
  }
}

class _E2bIamTokenDialog extends StatefulWidget {
  const _E2bIamTokenDialog({required this.initial});

  final _E2bIamTokenRecord? initial;

  @override
  State<_E2bIamTokenDialog> createState() => _E2bIamTokenDialogState();
}

class _E2bIamTokenDialogState extends State<_E2bIamTokenDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _audienceController;
  late final TextEditingController _typeController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _audienceController = TextEditingController(
      text: widget.initial?.audience ?? '',
    );
    _typeController = TextEditingController(
      text: widget.initial?.tokenType ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _audienceController.dispose();
    _typeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildSandboxRuleDialog<_E2bIamTokenRecord>(
      context: context,
      title: Text(
        openHandLocalizedText(
          context,
          zh: '工作负载身份令牌',
          en: 'Workload Identity Token',
        ),
      ),
      formKey: _formKey,
      fields: <Widget>[
        _dialogTextField(
          context,
          _nameController,
          zh: '令牌名称',
          en: 'Token Name',
        ),
        kOpenHandGap12,
        _dialogTextField(
          context,
          _audienceController,
          zh: '受众',
          en: 'Audience',
        ),
        kOpenHandGap12,
        _dialogTextField(
          context,
          _typeController,
          zh: '令牌类型',
          en: 'Token Type',
        ),
      ],
      createResult: () => _E2bIamTokenRecord(
        name: _nameController.text.trim(),
        audience: _audienceController.text.trim(),
        tokenType: _typeController.text.trim(),
      ),
    );
  }
}

class _E2bVolumeMountDialog extends StatefulWidget {
  const _E2bVolumeMountDialog({required this.initial});

  final AiE2bVolumeMount? initial;

  @override
  State<_E2bVolumeMountDialog> createState() => _E2bVolumeMountDialogState();
}

class _E2bVolumeMountDialogState extends State<_E2bVolumeMountDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _pathController = TextEditingController(text: widget.initial?.path ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildSandboxRuleDialog<AiE2bVolumeMount>(
      context: context,
      title: Text(
        openHandLocalizedText(context, zh: '卷挂载', en: 'Volume Mount'),
      ),
      formKey: _formKey,
      fields: <Widget>[
        _dialogTextField(
          context,
          _nameController,
          zh: '卷名称',
          en: 'Volume Name',
        ),
        kOpenHandGap12,
        _dialogTextField(
          context,
          _pathController,
          zh: '沙盒路径',
          en: 'Sandbox Path',
        ),
      ],
      createResult: () => AiE2bVolumeMount(
        name: _nameController.text.trim(),
        path: _pathController.text.trim(),
      ),
    );
  }
}

Widget _dialogTextField(
  BuildContext context,
  TextEditingController controller, {
  required String zh,
  required String en,
}) {
  return TextFormField(
    controller: controller,
    decoration: InputDecoration(
      labelText: openHandLocalizedText(context, zh: zh, en: en),
    ),
    validator: (value) => _requiredDialogValue(context, value),
  );
}

String? _requiredDialogValue(BuildContext context, String? value) {
  return value == null || value.trim().isEmpty
      ? openHandLocalizedText(
          context,
          zh: '此项不能为空。',
          en: 'This field cannot be empty.',
        )
      : null;
}

class _E2bEditablePair {
  _E2bEditablePair({required String key, required String value})
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class _E2bNetworkRuleDialog extends StatefulWidget {
  const _E2bNetworkRuleDialog({required this.initial});

  final _E2bNetworkRuleRecord? initial;

  @override
  State<_E2bNetworkRuleDialog> createState() => _E2bNetworkRuleDialogState();
}

class _E2bNetworkRuleDialogState extends State<_E2bNetworkRuleDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _domainController;
  final List<_E2bEditablePair> _headers = <_E2bEditablePair>[];

  @override
  void initState() {
    super.initState();
    _domainController = TextEditingController(
      text: widget.initial?.domain ?? '',
    );
    for (final entry
        in widget.initial?.headers.entries ??
            const <MapEntry<String, String>>[]) {
      _headers.add(_E2bEditablePair(key: entry.key, value: entry.value));
    }
  }

  @override
  void dispose() {
    _domainController.dispose();
    for (final header in _headers) {
      header.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return buildOpenHandAlertDialog(
      icon: const Icon(Icons.account_tree_outlined),
      title: Text(
        openHandLocalizedText(
          context,
          zh: '按域名变换请求头',
          en: 'Per-domain Header Transformation',
        ),
      ),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextFormField(
                    controller: _domainController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: openHandLocalizedText(
                        context,
                        zh: '匹配域名',
                        en: 'Matching Domain',
                      ),
                      hintText: 'api.example.com',
                    ),
                    validator: (value) => _requiredDialogValue(context, value),
                  ),
                  kOpenHandGap16,
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          openHandLocalizedText(
                            context,
                            zh: '注入或覆盖的请求头',
                            en: 'Headers to Inject or Replace',
                          ),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _headers.add(_E2bEditablePair(key: '', value: ''));
                        }),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(
                          openHandLocalizedText(
                            context,
                            zh: '添加请求头',
                            en: 'Add Header',
                          ),
                        ),
                      ),
                    ],
                  ),
                  kOpenHandGap12,
                  if (_headers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        openHandLocalizedText(
                          context,
                          zh: '当前规则不修改请求头。',
                          en: 'This rule does not modify headers.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (var index = 0; index < _headers.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: _dialogTextField(
                              context,
                              _headers[index].keyController,
                              zh: '请求头名称',
                              en: 'Header Name',
                            ),
                          ),
                          kOpenHandHGap10,
                          Expanded(
                            child: _dialogTextField(
                              context,
                              _headers[index].valueController,
                              zh: '请求头值',
                              en: 'Header Value',
                            ),
                          ),
                          kOpenHandHGap6,
                          SizedBox.square(
                            dimension: _sandboxDialogFieldHeight,
                            child: IconButton(
                              tooltip: AppLocalizations.of(
                                context,
                              )!.commonDelete,
                              onPressed: () => setState(() {
                                _headers.removeAt(index).dispose();
                              }),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: <Widget>[
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: AppLocalizations.of(context)!.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _submit,
          label: AppLocalizations.of(context)!.settingsSave,
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    final headers = <String, String>{};
    for (final header in _headers) {
      headers[header.keyController.text.trim()] = header.valueController.text;
    }
    Navigator.of(context).pop(
      _E2bNetworkRuleRecord(
        id: widget.initial?.id ?? _newSandboxRuleId(),
        domain: _domainController.text.trim(),
        headers: headers,
      ),
    );
  }
}

enum _E2bMcpValueType {
  text,
  integer,
  decimal,
  toggle,
  empty,
  textList,
  nested,
}

class _E2bMcpParameterRow {
  _E2bMcpParameterRow({required String key, required Object? value})
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: _textValue(value)),
      type = _typeOf(value),
      toggleValue = value is bool && value,
      originalValue = value;

  final TextEditingController keyController;
  final TextEditingController valueController;
  final Object? originalValue;
  _E2bMcpValueType type;
  bool toggleValue;

  Object? get value => switch (type) {
    _E2bMcpValueType.text => valueController.text,
    _E2bMcpValueType.integer => int.parse(valueController.text.trim()),
    _E2bMcpValueType.decimal => double.parse(valueController.text.trim()),
    _E2bMcpValueType.toggle => toggleValue,
    _E2bMcpValueType.empty => null,
    _E2bMcpValueType.textList =>
      valueController.text
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    _E2bMcpValueType.nested => originalValue,
  };

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }

  static _E2bMcpValueType _typeOf(Object? value) {
    if (value == null) return _E2bMcpValueType.empty;
    if (value is bool) return _E2bMcpValueType.toggle;
    if (value is int) return _E2bMcpValueType.integer;
    if (value is double) return _E2bMcpValueType.decimal;
    if (value is List && value.every((item) => item is String)) {
      return _E2bMcpValueType.textList;
    }
    if (value is Map || value is List) return _E2bMcpValueType.nested;
    return _E2bMcpValueType.text;
  }

  static String _textValue(Object? value) {
    if (value is List && value.every((item) => item is String)) {
      return value.join('\n');
    }
    return value is String || value is num ? '$value' : '';
  }
}

class _E2bMcpServerDialog extends StatefulWidget {
  const _E2bMcpServerDialog({required this.initial});

  final _E2bMcpServerRecord? initial;

  @override
  State<_E2bMcpServerDialog> createState() => _E2bMcpServerDialogState();
}

class _E2bMcpServerDialogState extends State<_E2bMcpServerDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final List<_E2bMcpParameterRow> _parameters = <_E2bMcpParameterRow>[];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    for (final entry
        in widget.initial?.parameters.entries ??
            const <MapEntry<String, Object?>>[]) {
      _parameters.add(_E2bMcpParameterRow(key: entry.key, value: entry.value));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final parameter in _parameters) {
      parameter.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return buildOpenHandAlertDialog(
      icon: const Icon(Icons.hub_outlined),
      title: Text(
        openHandLocalizedText(context, zh: 'MCP 服务', en: 'MCP Server'),
      ),
      content: SizedBox(
        width: 660,
        child: Form(
          key: _formKey,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 540),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextFormField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: openHandLocalizedText(
                        context,
                        zh: '服务标识',
                        en: 'Server Identifier',
                      ),
                      hintText: 'arxiv',
                    ),
                    validator: (value) => _requiredDialogValue(context, value),
                  ),
                  kOpenHandGap16,
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          openHandLocalizedText(
                            context,
                            zh: '服务参数',
                            en: 'Server Parameters',
                          ),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _parameters.add(
                            _E2bMcpParameterRow(key: '', value: ''),
                          );
                        }),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(
                          openHandLocalizedText(
                            context,
                            zh: '添加参数',
                            en: 'Add Parameter',
                          ),
                        ),
                      ),
                    ],
                  ),
                  kOpenHandGap12,
                  if (_parameters.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        openHandLocalizedText(
                          context,
                          zh: '此服务不需要额外参数。',
                          en: 'This server has no additional parameters.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (var index = 0; index < _parameters.length; index++)
                    _buildParameter(index),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: <Widget>[
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: AppLocalizations.of(context)!.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _submit,
          label: AppLocalizations.of(context)!.settingsSave,
        ),
      ],
    );
  }

  Widget _buildParameter(int index) {
    final parameter = _parameters[index];
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: kOpenHandBorderRadius14,
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: parameter.keyController,
                  decoration: InputDecoration(
                    labelText: openHandLocalizedText(
                      context,
                      zh: '参数名称',
                      en: 'Parameter Name',
                    ),
                  ),
                  validator: (value) {
                    final requiredError = _requiredDialogValue(context, value);
                    if (requiredError != null) return requiredError;
                    final normalized = value!.trim();
                    if (_parameters
                            .where(
                              (item) =>
                                  item.keyController.text.trim() == normalized,
                            )
                            .length >
                        1) {
                      return openHandLocalizedText(
                        context,
                        zh: '参数名称不能重复。',
                        en: 'Parameter names must be unique.',
                      );
                    }
                    return null;
                  },
                ),
              ),
              kOpenHandHGap10,
              SizedBox(
                width: 180,
                child: AnimatedDropdownButtonFormField<_E2bMcpValueType>(
                  initialValue: parameter.type,
                  decoration: InputDecoration(
                    labelText: openHandLocalizedText(
                      context,
                      zh: '值类型',
                      en: 'Value Type',
                    ),
                  ),
                  items: <DropdownMenuItem<_E2bMcpValueType>>[
                    for (final type in _E2bMcpValueType.values)
                      if (type != _E2bMcpValueType.nested ||
                          parameter.type == _E2bMcpValueType.nested)
                        DropdownMenuItem<_E2bMcpValueType>(
                          value: type,
                          child: Text(_mcpValueTypeLabel(context, type)),
                        ),
                  ],
                  onChanged: parameter.type == _E2bMcpValueType.nested
                      ? null
                      : (value) => setState(() {
                          parameter.type = value ?? _E2bMcpValueType.text;
                        }),
                ),
              ),
              kOpenHandHGap6,
              SizedBox.square(
                dimension: _sandboxDialogFieldHeight,
                child: IconButton(
                  tooltip: AppLocalizations.of(context)!.commonDelete,
                  onPressed: () => setState(() {
                    _parameters.removeAt(index).dispose();
                  }),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            ],
          ),
          kOpenHandGap10,
          if (parameter.type == _E2bMcpValueType.toggle)
            _AiTtsToggleField(
              label: openHandLocalizedText(
                context,
                zh: '参数值',
                en: 'Parameter Value',
              ),
              value: parameter.toggleValue,
              onChanged: (value) =>
                  setState(() => parameter.toggleValue = value),
            )
          else if (parameter.type == _E2bMcpValueType.nested)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                openHandLocalizedText(
                  context,
                  zh: '原有嵌套配置已保留；如需替换，请删除此参数后重新添加。',
                  en: 'The existing nested value is preserved. Delete and recreate this parameter to replace it.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else if (parameter.type != _E2bMcpValueType.empty)
            TextFormField(
              controller: parameter.valueController,
              minLines: parameter.type == _E2bMcpValueType.textList ? 2 : 1,
              maxLines: parameter.type == _E2bMcpValueType.textList ? 5 : 1,
              keyboardType:
                  parameter.type == _E2bMcpValueType.integer ||
                      parameter.type == _E2bMcpValueType.decimal
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: parameter.type == _E2bMcpValueType.textList
                    ? openHandLocalizedText(
                        context,
                        zh: '参数值（每行一项）',
                        en: 'Parameter Value (One Item per Line)',
                      )
                    : openHandLocalizedText(
                        context,
                        zh: '参数值',
                        en: 'Parameter Value',
                      ),
              ),
              validator: (value) {
                if (parameter.type == _E2bMcpValueType.integer &&
                    int.tryParse((value ?? '').trim()) == null) {
                  return openHandLocalizedText(
                    context,
                    zh: '请输入有效整数。',
                    en: 'Enter a valid integer.',
                  );
                }
                if (parameter.type == _E2bMcpValueType.decimal &&
                    optionalDoubleFromValue(value) == null) {
                  return openHandLocalizedText(
                    context,
                    zh: '请输入有效数值。',
                    en: 'Enter a valid number.',
                  );
                }
                return _requiredDialogValue(context, value);
              },
            ),
        ],
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(
      _E2bMcpServerRecord(
        name: _nameController.text.trim(),
        parameters: <String, Object?>{
          for (final parameter in _parameters)
            parameter.keyController.text.trim(): parameter.value,
        },
      ),
    );
  }
}

String _mcpValueTypeLabel(BuildContext context, _E2bMcpValueType type) {
  return switch (type) {
    _E2bMcpValueType.text => openHandLocalizedText(
      context,
      zh: '文本',
      en: 'Text',
    ),
    _E2bMcpValueType.integer => openHandLocalizedText(
      context,
      zh: '整数',
      en: 'Integer',
    ),
    _E2bMcpValueType.decimal => openHandLocalizedText(
      context,
      zh: '数值',
      en: 'Number',
    ),
    _E2bMcpValueType.toggle => openHandLocalizedText(
      context,
      zh: '开关',
      en: 'Boolean',
    ),
    _E2bMcpValueType.empty => openHandLocalizedText(
      context,
      zh: '空值',
      en: 'Null',
    ),
    _E2bMcpValueType.textList => openHandLocalizedText(
      context,
      zh: '文本列表',
      en: 'Text List',
    ),
    _E2bMcpValueType.nested => openHandLocalizedText(
      context,
      zh: '嵌套配置',
      en: 'Nested Value',
    ),
  };
}

class _SandboxEnvironmentTestDialog extends StatefulWidget {
  const _SandboxEnvironmentTestDialog({
    required this.provider,
    required this.settings,
  });

  final AiSandboxProvider provider;
  final AiSandboxSettings settings;

  @override
  State<_SandboxEnvironmentTestDialog> createState() =>
      _SandboxEnvironmentTestDialogState();
}

class _SandboxEnvironmentTestDialogState
    extends State<_SandboxEnvironmentTestDialog> {
  late final AiSandboxService _service;
  AiSandboxEnvironmentStatus? _status;
  Object? _error;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _service = AiSandboxService(settings: widget.settings);
    unawaited(_test());
  }

  @override
  void dispose() {
    unawaited(_service.shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = _status?.available == true;
    final accent = _running
        ? theme.colorScheme.primary
        : available
        ? OpenHandStatusColors.success
        : theme.colorScheme.error;
    return PopScope(
      child: buildOpenHandAlertDialog(
        icon: AnimatedSwitcher(
          duration: openHandMotionDuration(context, kOpenHandMotion200),
          child: Icon(
            _running
                ? Icons.science_rounded
                : available
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            key: ValueKey<Object?>(_running ? 'running' : available),
            color: accent,
          ),
        ),
        title: Text(
          openHandLocalizedText(
            context,
            zh: widget.provider == AiSandboxProvider.e2b
                ? 'E2B 沙盒测试'
                : '本地沙盒测试',
            en: widget.provider == AiSandboxProvider.e2b
                ? 'E2B Sandbox Test'
                : 'Local Sandbox Test',
          ),
        ),
        content: SizedBox(
          width: 460,
          child: AnimatedSwitcher(
            duration: openHandMotionDuration(context, kOpenHandMotion260),
            switchInCurve: kOpenHandSwitchInCurve,
            switchOutCurve: kOpenHandSwitchOutCurve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                alignment: AlignmentDirectional.topCenter,
                child: child,
              ),
            ),
            child: _running
                ? Column(
                    key: const ValueKey<String>('running'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: widget.provider == AiSandboxProvider.e2b
                              ? '正在验证 E2B 凭据、接口连通性与沙盒列表权限。'
                              : '正在验证当前平台、沙盒后端和运行依赖。',
                          en: widget.provider == AiSandboxProvider.e2b
                              ? 'Validating E2B credentials, API connectivity, and sandbox listing permissions.'
                              : 'Validating the current platform, sandbox backend, and runtime dependencies.',
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                      kOpenHandGap18,
                      ClipRRect(
                        borderRadius: kOpenHandBorderRadius12,
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          color: accent,
                          backgroundColor: accent.withValues(alpha: 0.13),
                        ),
                      ),
                    ],
                  )
                : _buildResult(theme, accent, available),
          ),
        ),
        actions: <Widget>[
          if (_running)
            OpenHandDialogActionButton.destructive(
              onPressed: () => Navigator.of(context).pop(),
              label: openHandLocalizedText(
                context,
                zh: '终止测试',
                en: 'Stop Test',
              ),
            )
          else ...<Widget>[
            OpenHandDialogActionButton.secondary(
              onPressed: _test,
              label: openHandLocalizedText(
                context,
                zh: '重新测试',
                en: 'Test Again',
              ),
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(context).pop(),
              label: openHandLocalizedText(context, zh: '完成', en: 'Done'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResult(ThemeData theme, Color accent, bool available) {
    final status = _status;
    final details = <String>[
      if (status != null) '${status.backend} · ${status.platform}',
      if (status?.resourceVersion.isNotEmpty == true) status!.resourceVersion,
      if (!available && status?.unavailableReason.isNotEmpty == true)
        status!.unavailableReason,
      ...?status?.warnings,
      if (_error != null) _settingsFullErrorText(context, _error!),
    ];
    return Container(
      key: const ValueKey<String>('result'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            available
                ? openHandLocalizedText(
                    context,
                    zh: '沙盒环境可用',
                    en: 'Sandbox Environment Is Available',
                  )
                : openHandLocalizedText(
                    context,
                    zh: '沙盒环境不可用',
                    en: 'Sandbox Environment Is Unavailable',
                  ),
            style: theme.textTheme.titleSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (details.isNotEmpty) ...<Widget>[
            kOpenHandGap8,
            Text(details.join('\n'), style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }

  Future<void> _test() async {
    if (mounted) {
      setState(() {
        _running = true;
        _status = null;
        _error = null;
      });
    }
    try {
      final status = await _service.detectEnvironment(refresh: true);
      if (mounted) setState(() => _status = status);
    } catch (error, stack) {
      silentLog('settings_sandbox', '测试沙盒环境', error, stack);
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}

class _SandboxResourceActionDialog extends StatefulWidget {
  const _SandboxResourceActionDialog({
    required this.service,
    required this.action,
  });

  final AiSandboxService service;
  final AiSandboxResourceAction action;

  @override
  State<_SandboxResourceActionDialog> createState() =>
      _SandboxResourceActionDialogState();
}

class _SandboxResourceActionDialogState
    extends State<_SandboxResourceActionDialog> {
  final Completer<void> _cancellation = Completer<void>();
  double _progress = 0.03;
  String _message = '';
  AiSandboxActionResult? _result;

  bool get _finished => _result != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  @override
  void dispose() {
    if (!_cancellation.isCompleted) _cancellation.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = _result?.success == true;
    final accent = !_finished
        ? theme.colorScheme.primary
        : success
        ? OpenHandStatusColors.success
        : theme.colorScheme.error;
    return PopScope(
      canPop: _finished,
      child: buildOpenHandAlertDialog(
        icon: AnimatedSwitcher(
          duration: openHandMotionDuration(context, kOpenHandMotion200),
          child: Icon(
            !_finished
                ? _actionIcon
                : success
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            key: ValueKey<Object?>(_finished ? success : widget.action),
            color: accent,
          ),
        ),
        title: Text(_title),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AnimatedSwitcher(
                duration: openHandMotionDuration(context, kOpenHandMotion200),
                child: Text(
                  _finished ? _result!.message : _message,
                  key: ValueKey<String>(_finished ? 'result' : _message),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
              if (!_finished) ...<Widget>[
                kOpenHandGap18,
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: _progress),
                  duration: openHandMotionDuration(
                    context,
                    const Duration(milliseconds: 520),
                  ),
                  curve: kOpenHandEmphasizedCurve,
                  builder: (context, value, _) => ClipRRect(
                    borderRadius: kOpenHandBorderRadius12,
                    child: LinearProgressIndicator(
                      value: value.clamp(0, 1),
                      minHeight: 11,
                      color: accent,
                      backgroundColor: accent.withValues(alpha: 0.13),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          if (_finished)
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(context).pop(),
              label: openHandLocalizedText(context, zh: '完成', en: 'Done'),
            )
          else
            OpenHandDialogActionButton.destructive(
              onPressed: _cancel,
              label: openHandLocalizedText(
                context,
                zh: '终止任务',
                en: 'Stop Task',
              ),
            ),
        ],
      ),
    );
  }

  String get _title => switch (widget.action) {
    AiSandboxResourceAction.install => openHandLocalizedText(
      context,
      zh: _finished ? '安装任务已结束' : '正在安装本地沙盒资源',
      en: _finished ? 'Installation Finished' : 'Installing Local Sandbox',
    ),
    AiSandboxResourceAction.update => openHandLocalizedText(
      context,
      zh: _finished ? '更新任务已结束' : '正在更新本地沙盒资源',
      en: _finished ? 'Update Finished' : 'Updating Local Sandbox',
    ),
    AiSandboxResourceAction.uninstall => openHandLocalizedText(
      context,
      zh: _finished ? '卸载任务已结束' : '正在卸载本地沙盒资源',
      en: _finished ? 'Removal Finished' : 'Removing Local Sandbox',
    ),
  };

  IconData get _actionIcon => switch (widget.action) {
    AiSandboxResourceAction.install => Icons.download_for_offline_outlined,
    AiSandboxResourceAction.update => Icons.system_update_alt_rounded,
    AiSandboxResourceAction.uninstall => Icons.delete_outline_rounded,
  };

  Future<void> _run() async {
    _message = openHandLocalizedText(
      context,
      zh: '正在准备系统资源任务',
      en: 'Preparing the system resource task',
    );
    try {
      final result = await widget.service.performEnvironmentAction(
        widget.action,
        cancelSignal: _cancellation.future,
        onProgress: (progress, message) {
          if (!mounted) return;
          setState(() {
            _progress = progress.clamp(_progress, 1);
            _message = message;
          });
        },
      );
      if (mounted) setState(() => _result = result);
    } catch (error, stack) {
      silentLog('settings_sandbox', '维护本地沙盒资源', error, stack);
      if (!mounted) return;
      setState(() {
        _result = AiSandboxActionResult(
          success: false,
          message: _settingsFullErrorText(context, error),
        );
      });
    }
  }

  void _cancel() {
    if (!_cancellation.isCompleted) _cancellation.complete();
    setState(() {
      _message = openHandLocalizedText(
        context,
        zh: '正在终止任务并清理进程',
        en: 'Stopping the task and cleaning up processes',
      );
    });
  }
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
        trailing: _SandboxEditDeleteActions(
          editTooltip: AppLocalizations.of(context)!.commonEdit,
          deleteTooltip: AppLocalizations.of(context)!.commonDelete,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
      ),
    );
  }
}

class _SandboxEditDeleteActions extends StatelessWidget {
  const _SandboxEditDeleteActions({
    required this.editTooltip,
    required this.deleteTooltip,
    required this.onEdit,
    required this.onDelete,
  });

  final String editTooltip;
  final String deleteTooltip;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          onPressed: onEdit,
          tooltip: editTooltip,
          icon: const Icon(Icons.edit_outlined),
        ),
        kOpenHandHGap8,
        IconButton(
          onPressed: onDelete,
          tooltip: deleteTooltip,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
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
          decoration: InputDecoration(labelText: openHandNoteLabel(context)),
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
            if (widget.ipOrCidrOnly && !isValidIpOrCidr(normalized)) {
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
          decoration: InputDecoration(labelText: openHandNoteLabel(context)),
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

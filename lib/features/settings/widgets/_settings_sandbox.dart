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
  late final TextEditingController _httpProxyPortController;
  late final TextEditingController _socksProxyPortController;
  late AiSandboxService _sandboxService;
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
    _sandboxService = AiSandboxService(
      settings: widget.settingsController.aiSandboxSettings,
    );
    _syncControllers();
    _statusFuture = _sandboxService.detectEnvironment();
  }

  @override
  void didUpdateWidget(covariant _SandboxSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.settingsController, widget.settingsController) ||
        oldWidget.settingsController.aiSandboxSettings.toJson().toString() !=
            widget.settingsController.aiSandboxSettings.toJson().toString()) {
      _sandboxService = AiSandboxService(
        settings: widget.settingsController.aiSandboxSettings,
      );
      _syncControllers();
      _statusFuture = _sandboxService.detectEnvironment(refresh: true);
    }
  }

  @override
  void dispose() {
    _httpProxyPortController.dispose();
    _socksProxyPortController.dispose();
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
        const SizedBox(height: 24),
        Divider(color: colorScheme.outlineVariant),
        const SizedBox(height: 18),
        Text(
          _localizedText(context, zh: '沙盒', en: 'Sandbox'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          _localizedText(
            context,
            zh: '为命令类内建工具加一层 OS 沙盒：限制写入路径，记录沙盒状态，并在环境不可用时按策略阻断或降级。',
            en: 'Add an OS sandbox around command-oriented built-ins: restrict writable paths, record sandbox status, and block or downgrade when unavailable.',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _buildEnvironmentCard(context),
        const SizedBox(height: 16),
        _ResponsiveSettingRow(
          title: _localizedText(context, zh: '启用沙盒', en: 'Enable Sandbox'),
          subtitle: _localizedText(
            context,
            zh: '默认关闭。开启后，仅你在下方多选的内建命令会进入沙盒。',
            en: 'Off by default. When enabled, only selected built-in commands run in the sandbox.',
          ),
          control: Switch(
            value: settings.enabled,
            onChanged: (value) => _update(settings.copyWith(enabled: value)),
          ),
        ),
        const SizedBox(height: 14),
        _ResponsiveSettingRow(
          title: _localizedText(
            context,
            zh: '环境不可用时阻断',
            en: 'Fail If Unavailable',
          ),
          subtitle: _localizedText(
            context,
            zh: '沙盒启用但依赖缺失时直接拦截命令，避免静默变成非沙盒执行。',
            en: 'Block commands when sandbox dependencies are missing instead of silently running unsandboxed.',
          ),
          control: Switch(
            value: settings.failIfUnavailable,
            onChanged: (value) =>
                _update(settings.copyWith(failIfUnavailable: value)),
          ),
        ),
        const SizedBox(height: 14),
        _ResponsiveSettingRow(
          title: _localizedText(
            context,
            zh: '允许排除命令非沙盒执行',
            en: 'Allow Excluded Commands Unsandboxed',
          ),
          subtitle: _localizedText(
            context,
            zh: '关闭时，命中排除列表的命令会被拦截而不是降级执行。',
            en: 'When off, commands matching the exclusion list are blocked instead of downgraded.',
          ),
          control: Switch(
            value: settings.allowUnsandboxedCommands,
            onChanged: (value) =>
                _update(settings.copyWith(allowUnsandboxedCommands: value)),
          ),
        ),
        const SizedBox(height: 14),
        _ResponsiveSettingRow(
          title: _localizedText(
            context,
            zh: '沙盒命令跳过写命令确认',
            en: 'Auto-allow Sandboxed Writes',
          ),
          subtitle: _localizedText(
            context,
            zh: '仅在 OS 沙盒实际生效时跳过 Bash 写命令确认；默认关闭。',
            en: 'Skip Bash write confirmation only when the OS sandbox is actually active. Off by default.',
          ),
          control: Switch(
            value: settings.autoAllowBashIfSandboxed,
            onChanged: (value) =>
                _update(settings.copyWith(autoAllowBashIfSandboxed: value)),
          ),
        ),
        const SizedBox(height: 14),
        _ResponsiveSettingRow(
          title: _localizedText(
            context,
            zh: '无域名规则时允许网络',
            en: 'Allow Network Without Domain Rules',
          ),
          subtitle: _localizedText(
            context,
            zh: '关闭后，无域名规则的沙盒命令会禁用网络；配置域名规则时会启动本地过滤代理。macOS 会阻断直连绕过；Linux 严格模式会阻断尚无法强制过滤的域名规则。',
            en: 'When off, sandboxed commands without domain rules run with networking disabled. Domain rules start a local filtering proxy. macOS blocks direct bypass; Linux strict mode blocks domain rules that cannot be enforced yet.',
          ),
          control: Switch(
            value: settings.allowNetworkWhenNoDomainRules,
            onChanged: (value) => _update(
              settings.copyWith(allowNetworkWhenNoDomainRules: value),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _buildToolChips(context, settings),
        const SizedBox(height: 18),
        _buildProxyPorts(context, settings),
        const SizedBox(height: 20),
        _buildFileRules(context, settings),
        const SizedBox(height: 20),
        _buildPatternRules(
          context: context,
          title: _localizedText(context, zh: '排除命令列表', en: 'Excluded Commands'),
          body: _localizedText(
            context,
            zh: '命中这些规则的命令不会进入沙盒；是否允许降级执行由上方开关控制。',
            en: 'Commands matching these rules do not enter the sandbox; the downgrade policy is controlled above.',
          ),
          icon: Icons.remove_circle_outline_rounded,
          rules: settings.excludedCommands,
          onAdd: () => _showPatternRuleDialog(
            title: _localizedText(
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
            title: _localizedText(
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
        const SizedBox(height: 20),
        _buildPatternRules(
          context: context,
          title: _localizedText(context, zh: '允许访问域名', en: 'Allowed Domains'),
          body: _localizedText(
            context,
            zh: '用于本地沙盒代理过滤。简单模式支持 *，正则模式按原样匹配 host 或 host:port。',
            en: 'Used by the local sandbox proxy filter. Simple mode supports *, regex mode matches host or host:port as written.',
          ),
          icon: Icons.public_rounded,
          rules: settings.allowedDomains,
          onAdd: () => _showPatternRuleDialog(
            title: _localizedText(
              context,
              zh: '新增允许域名',
              en: 'Add Allowed Domain',
            ),
            hint: '*.example.com',
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
            title: _localizedText(
              context,
              zh: '编辑允许域名',
              en: 'Edit Allowed Domain',
            ),
            hint: '*.example.com',
            initialRule: rule,
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
        const SizedBox(height: 20),
        _buildPatternRules(
          context: context,
          title: _localizedText(context, zh: '禁止访问域名', en: 'Denied Domains'),
          body: _localizedText(
            context,
            zh: '用于沙盒代理过滤；命中禁止列表的域名应被代理拒绝。',
            en: 'Used by the sandbox proxy filter; matching domains should be rejected by the proxy.',
          ),
          icon: Icons.public_off_rounded,
          rules: settings.deniedDomains,
          onAdd: () => _showPatternRuleDialog(
            title: _localizedText(
              context,
              zh: '新增禁止域名',
              en: 'Add Denied Domain',
            ),
            hint: '*.tracker.example',
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
            title: _localizedText(
              context,
              zh: '编辑禁止域名',
              en: 'Edit Denied Domain',
            ),
            hint: '*.tracker.example',
            initialRule: rule,
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

  Widget _buildEnvironmentCard(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<AiSandboxEnvironmentStatus>(
          future: _statusFuture,
          builder: (context, snapshot) {
            final status = snapshot.data;
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;
            final title = isLoading
                ? _localizedText(context, zh: '检测中', en: 'Detecting')
                : status?.available == true
                ? _localizedText(context, zh: '环境可用', en: 'Environment Ready')
                : _localizedText(
                    context,
                    zh: '环境不可用',
                    en: 'Environment Unavailable',
                  );
            final body = status == null
                ? _localizedText(
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
                    const SizedBox(width: 10),
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
                        _localizedText(context, zh: '检测', en: 'Detect'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(body, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _runEnvironmentAction(
                        _sandboxService.installEnvironment,
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        _localizedText(context, zh: '安装', en: 'Install'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _runEnvironmentAction(
                        _sandboxService.updateEnvironment,
                      ),
                      icon: const Icon(Icons.upgrade_rounded),
                      label: Text(
                        _localizedText(context, zh: '更新', en: 'Update'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _runEnvironmentAction(
                        _sandboxService.uninstallEnvironment,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(
                        _localizedText(context, zh: '卸载', en: 'Uninstall'),
                      ),
                    ),
                  ],
                ),
                if (_actionMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_actionMessage, style: theme.textTheme.bodySmall),
                  if (_actionCommand.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      _actionCommand,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
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
          _localizedText(context, zh: '走沙盒的内建命令', en: 'Sandboxed Built-ins'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 10),
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
          _localizedText(context, zh: '沙盒代理端口', en: 'Sandbox Proxy Ports'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text(
          _localizedText(
            context,
            zh: 'HTTP 为空或 0 时自动选择临时端口；SOCKS 为空或 0 时不启用 SOCKS 入口。代理随沙盒命令启动并自动清理；Linux 关闭“环境不可用时阻断”后仅作为尽力而为的环境变量注入。',
            en: 'Blank or 0 HTTP uses an automatic temporary port; blank or 0 SOCKS disables the SOCKS entry point. The proxy starts per sandboxed command and is cleaned up automatically; on Linux with Fail If Unavailable off it is best-effort environment injection only.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
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
                _localizedText(
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
        const SizedBox(height: 8),
        Text(
          _localizedText(
            context,
            zh: '路径支持简单模式（* 通配）和正则模式；默认 .openhand 为只读。rw 路径会在沙盒内开放写入。',
            en: 'Paths support simple mode (* wildcard) and regex mode. .openhand is read-only by default; rw paths are writable inside the sandbox.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (settings.filesystemRules.isEmpty)
          _SettingsStateBox(
            icon: Icons.folder_off_outlined,
            title: _localizedText(context, zh: '暂无文件规则', en: 'No file rules'),
            body: _localizedText(
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
                const SizedBox(height: 10),
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
        const SizedBox(height: 8),
        Text(body, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        if (rules.isEmpty)
          _SettingsStateBox(
            icon: icon,
            title: _localizedText(context, zh: '暂无规则', en: 'No rules'),
            body: _localizedText(
              context,
              zh: '添加简单匹配或正则匹配规则。',
              en: 'Add simple or regex matching rules.',
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
                const SizedBox(height: 10),
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
    final parsed = optionalIntFromText(value);
    if (parsed == null || parsed <= 0 || parsed > 65535) return 0;
    return parsed;
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
  }) async {
    final result = await showAnimatedDialog<AiSandboxPatternRule>(
      context: context,
      builder: (dialogContext) => _SandboxPatternRuleDialog(
        title: title,
        hint: hint,
        initialRule: initialRule,
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
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              onPressed: onEdit,
              tooltip: AppLocalizations.of(context)!.commonEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: AppLocalizations.of(context)!.commonDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
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
  late AiDenyCommandMatchMode _matchMode;

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
    _matchMode = widget.initialRule?.matchMode ?? AiDenyCommandMatchMode.simple;
  }

  @override
  void dispose() {
    _pathController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return buildOpenHandAlertDialog(
      title: Text(
        widget.initialRule == null
            ? _localizedText(context, zh: '新增文件规则', en: 'Add File Rule')
            : _localizedText(context, zh: '编辑文件规则', en: 'Edit File Rule'),
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: 'Path / Pattern',
                  hintText: r'.openhand or ^/Users/.*/cache$',
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? _localizedText(context, zh: '请输入路径。', en: 'Enter a path.')
                    : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<AiSandboxFileAccessMode>(
                initialValue: _accessMode,
                decoration: InputDecoration(
                  labelText: _localizedText(
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
              const SizedBox(height: 14),
              DropdownButtonFormField<AiDenyCommandMatchMode>(
                initialValue: _matchMode,
                decoration: InputDecoration(
                  labelText: _localizedText(
                    context,
                    zh: '匹配模式',
                    en: 'Match Mode',
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: AiDenyCommandMatchMode.simple,
                    child: Text(
                      _localizedText(context, zh: '简单匹配', en: 'Simple'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: AiDenyCommandMatchMode.regex,
                    child: Text(
                      _localizedText(context, zh: '正则匹配', en: 'Regex'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _matchMode = value ?? AiDenyCommandMatchMode.simple;
                }),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: _localizedText(context, zh: '备注', en: 'Note'),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: AppLocalizations.of(context)!.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              AiSandboxFileRule(
                id: widget.initialRule?.id ?? _newSandboxRuleId(),
                path: _pathController.text.trim(),
                accessMode: _accessMode,
                matchMode: _matchMode,
                note: _noteController.text.trim(),
              ),
            );
          },
          label: AppLocalizations.of(context)!.commonSave,
        ),
      ],
    );
  }
}

class _SandboxPatternRuleDialog extends StatefulWidget {
  const _SandboxPatternRuleDialog({
    required this.title,
    required this.hint,
    this.initialRule,
  });

  final String title;
  final String hint;
  final AiSandboxPatternRule? initialRule;

  @override
  State<_SandboxPatternRuleDialog> createState() =>
      _SandboxPatternRuleDialogState();
}

class _SandboxPatternRuleDialogState extends State<_SandboxPatternRuleDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _patternController;
  late final TextEditingController _noteController;
  late AiDenyCommandMatchMode _matchMode;

  @override
  void initState() {
    super.initState();
    _patternController = TextEditingController(
      text: widget.initialRule?.pattern ?? '',
    );
    _noteController = TextEditingController(
      text: widget.initialRule?.note ?? '',
    );
    _matchMode = widget.initialRule?.matchMode ?? AiDenyCommandMatchMode.simple;
  }

  @override
  void dispose() {
    _patternController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return buildOpenHandAlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _patternController,
                decoration: InputDecoration(
                  labelText: 'Pattern',
                  hintText: widget.hint,
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? _localizedText(
                        context,
                        zh: '请输入匹配表达式。',
                        en: 'Enter a pattern.',
                      )
                    : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<AiDenyCommandMatchMode>(
                initialValue: _matchMode,
                decoration: InputDecoration(
                  labelText: _localizedText(
                    context,
                    zh: '匹配模式',
                    en: 'Match Mode',
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: AiDenyCommandMatchMode.simple,
                    child: Text(
                      _localizedText(context, zh: '简单匹配', en: 'Simple'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: AiDenyCommandMatchMode.regex,
                    child: Text(
                      _localizedText(context, zh: '正则匹配', en: 'Regex'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _matchMode = value ?? AiDenyCommandMatchMode.simple;
                }),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: _localizedText(context, zh: '备注', en: 'Note'),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: AppLocalizations.of(context)!.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              AiSandboxPatternRule(
                id: widget.initialRule?.id ?? _newSandboxRuleId(),
                pattern: _patternController.text.trim(),
                matchMode: _matchMode,
                note: _noteController.text.trim(),
              ),
            );
          },
          label: AppLocalizations.of(context)!.commonSave,
        ),
      ],
    );
  }
}

String _newSandboxRuleId() =>
    'sandbox-${DateTime.now().microsecondsSinceEpoch}';

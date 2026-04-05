import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/openhand_dialog_action_button.dart';
import 'hardness_cli_catalog.dart';
import 'hardness_cli_install_dialog.dart';
import 'model/hardness_agent_role.dart';
import 'model/hardness_role_config.dart';
import 'model/hardness_session_config.dart';

// POSIX single-quote an executable / arg for embedding in shell -c strings.
String _posixQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

class HardnessEngineeringDialog extends StatefulWidget {
  const HardnessEngineeringDialog({super.key});

  @override
  State<HardnessEngineeringDialog> createState() =>
      _HardnessEngineeringDialogState();
}

class _HardnessEngineeringDialogState extends State<HardnessEngineeringDialog> {
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _workingDirController = TextEditingController();
  final TextEditingController _persistenceDirController = TextEditingController();

  final Map<HardnessAgentRole, String?> _selectedCli = {};
  final Map<HardnessAgentRole, String?> _selectedModel = {};

  // Quick-apply bar state
  String? _quickCli;
  String? _quickModel;

  List<CliScanEntry> _scanResults = [];
  bool _isScanning = true;
  bool _isCheckingAuth = false;

  @override
  void initState() {
    super.initState();
    _taskController.addListener(_onFormChanged);
    _workingDirController.addListener(_onFormChanged);
    _persistenceDirController.addListener(_onFormChanged);
    _scanClis();
  }

  @override
  void dispose() {
    _taskController.dispose();
    _workingDirController.dispose();
    _persistenceDirController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  Future<void> _scanClis() async {
    setState(() {
      _isScanning = true;
      _isCheckingAuth = false;
    });

    // Phase 1 — fast install probe (parallel)
    final results = await scanInstalledClis();
    if (!mounted) return;
    final hasCheckable = results.any((e) => e.installed && e.cli.hasLoginCheck);
    setState(() {
      _scanResults = results;
      _isScanning = false;
      _isCheckingAuth = hasCheckable;
    });

    if (!hasCheckable) return;

    // Phase 2 — auth probe for installed CLIs (parallel, slower)
    final authResults = await Future.wait(results.map(probeCliAuth));
    if (!mounted) return;
    setState(() {
      _scanResults = [
        for (int i = 0; i < results.length; i++)
          (
            cli: results[i].cli,
            installed: results[i].installed,
            resolvedPath: results[i].resolvedPath,
            isLoggedIn: authResults[i],
          ),
      ];
      _isCheckingAuth = false;
    });
  }

  bool get _isValid =>
      _taskController.text.trim().isNotEmpty &&
      _workingDirController.text.trim().isNotEmpty &&
      _persistenceDirController.text.trim().isNotEmpty;

  Future<void> _pickDirectory(TextEditingController controller) async {
    final current = controller.text.trim();
    final result = await getDirectoryPath(
      initialDirectory: current.isNotEmpty ? current : null,
    );
    if (result != null && mounted) {
      controller.text = result;
    }
  }

  List<String> _modelsForCli(String? cliName) {
    if (cliName == null) return const [];
    return _scanResults
            .where((r) => r.cli.name == cliName)
            .firstOrNull
            ?.cli
            .knownModels ??
        const [];
  }

  HardnessRoleConfig _roleConfig(HardnessAgentRole role) => HardnessRoleConfig(
        cliName: _selectedCli[role] ?? '',
        modelId: _selectedModel[role] ?? '',
      );

  CliScanEntry? _entryForCli(String? name) =>
      name == null ? null : _scanResults.where((r) => r.cli.name == name).firstOrNull;

  Future<void> _showInstallDialog(HardnessCli cli) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => HardnessCliInstallDialog(cli: cli),
    );
    if (result == true && mounted) {
      await _scanClis();
    }
  }

  Future<void> _openDocUrl(String url) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
      } else {
        await Clipboard.setData(ClipboardData(text: url));
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
    }
  }

  /// Opens a new terminal window running the CLI's interactive login command.
  /// Falls back to copying the command to clipboard if no terminal can be found.
  Future<void> _launchCliLogin(CliScanEntry entry, {required bool isZh}) async {
    final cli = entry.cli;
    if (cli.loginArgs == null) return;
    final exe = entry.resolvedPath ?? cli.executable;
    final cmdParts = [exe, ...cli.loginArgs!];
    final shellCmd = cmdParts.map(_posixQuote).join(' ');

    bool launched = false;
    try {
      if (Platform.isMacOS) {
        // Escape backslashes and double-quotes for the AppleScript string literal.
        final escaped =
            shellCmd.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
        await Process.run('osascript', [
          '-e', 'tell application "Terminal" to activate',
          '-e', 'tell application "Terminal" to do script "$escaped"',
        ]);
        launched = true;
      } else if (Platform.isLinux) {
        // Try common terminal emulators in priority order.
        for (final candidate in [
          ['gnome-terminal', '--', 'bash', '-lc', shellCmd],
          ['xterm', '-e', shellCmd],
          ['konsole', '-e', shellCmd],
          ['xfce4-terminal', '-x', shellCmd],
        ]) {
          try {
            final r = await Process.run(candidate.first, candidate.sublist(1));
            if (r.exitCode == 0 || r.exitCode == -1) {
              launched = true;
              break;
            }
          } catch (_) {}
        }
      } else if (Platform.isWindows) {
        await Process.run(
          'cmd',
          ['/c', 'start', 'cmd', '/k', cmdParts.join(' ')],
          runInShell: true,
        );
        launched = true;
      }
    } catch (_) {}

    if (!launched && mounted) {
      // Fallback: copy the command to clipboard and notify the user.
      await Clipboard.setData(ClipboardData(text: cmdParts.join(' ')));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isZh
                  ? '\u65e0\u6cd5\u6253\u5f00\u7ec8\u7aef\uff0c\u767b\u5f55\u547d\u4ee4\u5df2\u590d\u5236\u5230\u526a\u8d34\u677f\uff1a${cmdParts.join(' ')}'
                  : 'Could not open a terminal \u2014 login command copied to clipboard: ${cmdParts.join(' ')}',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _submit() {
    Navigator.of(context).pop(
      HardnessSessionConfig(
        task: _taskController.text.trim(),
        workingDirectory: _workingDirController.text.trim(),
        persistenceDirectory: _persistenceDirController.text.trim(),
        profilerConfig: _roleConfig(HardnessAgentRole.profiler),
        readerConfig: _roleConfig(HardnessAgentRole.reader),
        plannerConfig: _roleConfig(HardnessAgentRole.planner),
        implementerConfig: _roleConfig(HardnessAgentRole.implementer),
        reviewerConfig: _roleConfig(HardnessAgentRole.reviewer),
      ),
    );
  }

  /// Applies the quick-apply CLI + model to every role at once.
  void _applyQuickConfig() {
    if (_quickCli == null) return;
    setState(() {
      for (final role in HardnessAgentRole.values) {
        _selectedCli[role] = _quickCli;
        // Only apply model if it is valid for the chosen CLI.
        final models = _modelsForCli(_quickCli);
        _selectedModel[role] =
            (_quickModel != null && models.contains(_quickModel)) ? _quickModel : null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    return AlertDialog(
      title: Text(
        isZh ? 'Hardness Engineering 配置' : 'Hardness Engineering Setup',
      ),
      content: SizedBox(
        width: 860,
        child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isZh
                      ? 'OpenHand 将作为编排协调层，通过下方配置的各角色 CLI 工具执行具体编码任务。'
                      : 'OpenHand acts as orchestrator and delegates coding to the configured CLI tools for each agent role.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),

                // ── Task input ─────────────────────────────────────────
                TextField(
                  controller: _taskController,
                  autofocus: true,
                  maxLines: 5,
                  minLines: 3,
                  decoration: InputDecoration(
                    labelText: isZh ? '任务 / 需求' : 'Task / Requirement',
                    hintText: isZh
                        ? '描述你的开发任务或需求...'
                        : 'Describe your development task or requirement...',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Working directory ──────────────────────────────────
                _DirectoryField(
                  controller: _workingDirController,
                  label: isZh ? '工作目录（项目根目录）' : 'Working Directory',
                  hint: isZh ? '输入或选择项目根目录路径' : 'Enter or browse project root path',
                  browseTooltip: isZh ? '浏览文件夹' : 'Browse folder',
                  onBrowse: () => _pickDirectory(_workingDirController),
                ),
                const SizedBox(height: 14),

                // ── Persistence directory ──────────────────────────────
                _DirectoryField(
                  controller: _persistenceDirController,
                  label: isZh
                      ? '持久化根目录（steering 数据目录）'
                      : 'Persistence Root (steering dir)',
                  hint: isZh
                      ? '输入或选择持久化根目录路径'
                      : 'Enter or browse persistence root path',
                  browseTooltip: isZh ? '浏览文件夹' : 'Browse folder',
                  onBrowse: () => _pickDirectory(_persistenceDirController),
                ),
                const SizedBox(height: 28),

                // ── Role CLI config header ─────────────────────────────
                Row(
                  children: [
                    Text(
                      isZh ? '角色 CLI 配置' : 'Role CLI Configuration',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: colorScheme.onSurface),
                    ),
                    const Spacer(),
                    if (_isScanning || _isCheckingAuth)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      IconButton(
                        onPressed: _scanClis,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        tooltip: isZh ? '重新扫描 CLI' : 'Re-scan CLIs',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isZh
                      ? '为每个角色指定 CLI 客户端及模型。● 已安装，○ 未安装，✓ 已登录，✗ 未登录。'
                      : 'Assign a CLI and model to each role. ● installed, ○ not installed, ✓ logged in, ✗ not logged in.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),

                // ── Install & auth status panels ───────────────────────
                if (!_isScanning) ...[
                  _CliStatusPanel(
                    scanResults: _scanResults,
                    isZh: isZh,
                    onInstall: _showInstallDialog,
                    onOpenDoc: _openDocUrl,
                  ),
                  _CliAuthStatusPanel(
                    scanResults: _scanResults,
                    isCheckingAuth: _isCheckingAuth,
                    isZh: isZh,
                    onLogin: (entry) => _launchCliLogin(entry, isZh: isZh),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Quick-apply bar ────────────────────────────────────
                _QuickApplyBar(
                  isZh: isZh,
                  scanResults: _scanResults,
                  isScanning: _isScanning,
                  isCheckingAuth: _isCheckingAuth,
                  selectedCli: _quickCli,
                  selectedModel: _quickModel,
                  onCliChanged: (v) => setState(() {
                    _quickCli = v;
                    _quickModel = null;
                  }),
                  onModelChanged: (v) => setState(() => _quickModel = v),
                  onApply: _applyQuickConfig,
                  modelsForCli: _modelsForCli,
                ),
                const SizedBox(height: 12),

                if (_isScanning && _scanResults.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(strokeWidth: 2),
                          const SizedBox(height: 12),
                          Text(
                            isZh
                                ? '扫描已安装的 CLI...'
                                : 'Scanning installed CLIs...',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...HardnessAgentRole.values.map((role) {
                    final selectedCliName = _selectedCli[role];
                    final entry = _entryForCli(selectedCliName);
                    final cli = entry?.cli;
                    final notInstalled =
                        selectedCliName != null && !(entry?.installed ?? true);
                    final showInstall =
                        notInstalled && (cli?.isAutoInstallable ?? false);
                    final showViewDocs = notInstalled &&
                        !(cli?.isAutoInstallable ?? false) &&
                        (cli?.installDocUrl?.isNotEmpty ?? false);
                    // Show login button only when we have confirmed not-logged-in state.
                    final showLogin = selectedCliName != null &&
                        (entry?.installed ?? false) &&
                        entry?.isLoggedIn == false &&
                        (cli?.hasLoginTrigger ?? false);
                    return _RoleConfigRow(
                      role: role,
                      isZh: isZh,
                      scanResults: _scanResults,
                      selectedCli: selectedCliName,
                      availableModels: _modelsForCli(selectedCliName),
                      selectedModel: _selectedModel[role],
                      showInstallButton: showInstall,
                      showViewDocsButton: showViewDocs,
                      showLoginButton: showLogin,
                      isCheckingAuth: _isCheckingAuth,
                      onCliChanged: (v) => setState(() {
                        _selectedCli[role] = v;
                        _selectedModel[role] = null;
                      }),
                      onModelChanged: (v) => setState(() {
                        _selectedModel[role] = v;
                      }),
                      onInstall:
                          cli != null ? () => _showInstallDialog(cli) : null,
                      onViewDocs: (cli?.installDocUrl != null)
                          ? () => _openDocUrl(cli!.installDocUrl!)
                          : null,
                      onLogin: (entry != null && (cli?.hasLoginTrigger ?? false))
                          ? () => _launchCliLogin(entry, isZh: isZh)
                          : null,
                    );
                  }),

                // Env hint
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 13, color: colorScheme.outline),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          isZh
                              ? '若 CLI 未被检测到但实际已安装，可能因 App 启动方式导致环境变量未完全加载，可点击刷新图标重新扫描，或从终端启动 OpenHand。'
                              : 'If a CLI is not detected but is installed, the launch environment may not include your shell PATH. Try refreshing, or launch OpenHand from a terminal.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '取消' : 'Cancel',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: (_isValid && !_isScanning) ? _submit : null,
          label: isZh ? '开始会话' : 'Start Session',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Directory field: text input + folder browse icon button
// ─────────────────────────────────────────────────────────────────────────────

class _DirectoryField extends StatelessWidget {
  const _DirectoryField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.browseTooltip,
    required this.onBrowse,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String browseTooltip;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: browseTooltip,
          child: SizedBox(
            height: 52,
            width: 44,
            child: OutlinedButton(
              onPressed: onBrowse,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.6),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
              child: const Icon(Icons.folder_open_rounded, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Role config row with CLI/model dropdowns and optional install button
// ─────────────────────────────────────────────────────────────────────────────

class _RoleConfigRow extends StatelessWidget {
  const _RoleConfigRow({
    required this.role,
    required this.isZh,
    required this.scanResults,
    required this.selectedCli,
    required this.availableModels,
    required this.selectedModel,
    required this.showInstallButton,
    this.showViewDocsButton = false,
    this.showLoginButton = false,
    this.isCheckingAuth = false,
    required this.onCliChanged,
    required this.onModelChanged,
    this.onInstall,
    this.onViewDocs,
    this.onLogin,
  });

  final HardnessAgentRole role;
  final bool isZh;
  final List<CliScanEntry> scanResults;
  final String? selectedCli;
  final List<String> availableModels;
  final String? selectedModel;
  final bool showInstallButton;
  final bool showViewDocsButton;
  final bool showLoginButton;
  final bool isCheckingAuth;
  final ValueChanged<String?> onCliChanged;
  final ValueChanged<String?> onModelChanged;
  final VoidCallback? onInstall;
  final VoidCallback? onViewDocs;
  final VoidCallback? onLogin;

  // Returns the CliScanEntry for the currently selected CLI (if any).
  CliScanEntry? get _selectedEntry =>
      selectedCli == null
          ? null
          : scanResults.where((r) => r.cli.name == selectedCli).firstOrNull;

  List<DropdownMenuItem<String>> _buildCliItems(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return scanResults.where((e) => e.cli.supportsHeadless).map((entry) {
      // Build trailing login-state indicator for installed CLIs.
      Widget? loginIcon;
      if (entry.installed && entry.cli.hasLoginCheck) {
        if (isCheckingAuth) {
          loginIcon = const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          );
        } else if (entry.isLoggedIn == true) {
          loginIcon = Icon(Icons.check_circle_rounded,
              size: 11, color: Colors.green.shade600);
        } else if (entry.isLoggedIn == false) {
          loginIcon = Icon(Icons.cancel_rounded,
              size: 11, color: Colors.orange.shade700);
        }
      }
      return DropdownMenuItem<String>(
        value: entry.cli.name,
        child: Row(
          children: [
            Icon(
              entry.installed ? Icons.circle_rounded : Icons.circle_outlined,
              size: 10,
              color: entry.installed
                  ? colorScheme.primary
                  : colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                entry.cli.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (loginIcon != null) ...[const SizedBox(width: 4), loginIcon],
          ],
        ),
      );
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final roleName = isZh ? role.displayNameZh : role.displayNameEn;
    final effectiveModel =
        availableModels.contains(selectedModel) ? selectedModel : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 68,
                child: Text(
                  roleName,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CompactDropdown<String>(
                  label: isZh ? 'CLI 客户端' : 'CLI Client',
                  value: selectedCli,
                  items: _buildCliItems(context),
                  onChanged: onCliChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CompactDropdown<String>(
                  label: isZh ? '模型' : 'Model',
                  value: effectiveModel,
                  items: availableModels
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m,
                          child: Text(
                            m,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: availableModels.isNotEmpty ? onModelChanged : null,
                  enabled: selectedCli != null && availableModels.isNotEmpty,
                ),
              ),
              if (showInstallButton) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: isZh ? '安装此 CLI' : 'Install this CLI',
                  child: OutlinedButton.icon(
                    onPressed: onInstall,
                    icon: const Icon(Icons.download_rounded, size: 15),
                    label: Text(
                      isZh ? '安装' : 'Install',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      side: BorderSide(
                        color: colorScheme.primary.withValues(alpha: 0.7),
                      ),
                      foregroundColor: colorScheme.primary,
                    ),
                  ),
                ),
              ],
              if (showViewDocsButton && onViewDocs != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: isZh ? '打开安装文档' : 'Open install docs',
                  child: OutlinedButton.icon(
                    onPressed: onViewDocs,
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: Text(
                      isZh ? '安装文档' : 'Docs',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      side: BorderSide(
                        color: colorScheme.secondary.withValues(alpha: 0.7),
                      ),
                      foregroundColor: colorScheme.secondary,
                    ),
                  ),
                ),
              ],
              // Auth checking indicator
              if (isCheckingAuth &&
                  selectedCli != null &&
                  (_selectedEntry?.installed ?? false) &&
                  (_selectedEntry?.cli.hasLoginCheck ?? false)) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: isZh ? '正在检测登录状态...' : 'Checking login state...',
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: colorScheme.primary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
              // Logged-in confirmation badge
              if (!isCheckingAuth &&
                  selectedCli != null &&
                  _selectedEntry?.isLoggedIn == true &&
                  (_selectedEntry?.cli.hasLoginCheck ?? false)) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: isZh ? '已登录' : 'Logged in',
                  child: Icon(
                    Icons.verified_user_rounded,
                    size: 16,
                    color: Colors.green.shade600,
                  ),
                ),
              ],
              // Login button for confirmed-not-logged-in state
              if (showLoginButton) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: isZh ? '此 CLI 尚未登录，点击引导登录' : 'This CLI is not logged in — click to start login',
                  child: OutlinedButton.icon(
                    onPressed: onLogin,
                    icon: const Icon(Icons.login_rounded, size: 15),
                    label: Text(
                      isZh ? '登录' : 'Login',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      side: BorderSide(
                        color: Colors.orange.shade600.withValues(alpha: 0.8),
                      ),
                      foregroundColor: Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
              // GUI-only warning
              if (selectedCli != null &&
                  _selectedEntry?.cli.supportsHeadless == false) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: isZh
                      ? '此工具为 GUI 应用，不支持无交互调用，Hardness Engineering 将跳过此角色阶段'
                      : 'GUI-only app: non-interactive invocation is not supported. This role phase will be skipped.',
                  child: Icon(
                    Icons.monitor_rounded,
                    size: 18,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable compact dropdown
// ─────────────────────────────────────────────────────────────────────────────

class _CompactDropdown<T> extends StatelessWidget {
  const _CompactDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isDense: true,
          isExpanded: true,
          value: value,
          hint: Text(
            enabled ? label : '—',
            style: const TextStyle(fontSize: 13),
          ),
          items: items,
          onChanged: (enabled && items.isNotEmpty) ? onChanged : null,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick-apply bar: pick one CLI + model and apply to all roles at once
// ─────────────────────────────────────────────────────────────────────────────

class _QuickApplyBar extends StatelessWidget {
  const _QuickApplyBar({
    required this.isZh,
    required this.scanResults,
    required this.isScanning,
    required this.isCheckingAuth,
    required this.selectedCli,
    required this.selectedModel,
    required this.onCliChanged,
    required this.onModelChanged,
    required this.onApply,
    required this.modelsForCli,
  });

  final bool isZh;
  final List<CliScanEntry> scanResults;
  final bool isScanning;
  final bool isCheckingAuth;
  final String? selectedCli;
  final String? selectedModel;
  final ValueChanged<String?> onCliChanged;
  final ValueChanged<String?> onModelChanged;
  final VoidCallback onApply;
  final List<String> Function(String?) modelsForCli;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final models = modelsForCli(selectedCli);
    final effectiveModel = models.contains(selectedModel) ? selectedModel : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              isZh ? '一键统一配置' : 'Apply to all',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CompactDropdown<String>(
                label: isZh ? 'CLI 客户端' : 'CLI Client',
                value: selectedCli,
                items: scanResults.where((e) => e.cli.supportsHeadless).map((entry) {
                  final cs = Theme.of(context).colorScheme;
                  Widget? loginIcon;
                  if (entry.installed && entry.cli.hasLoginCheck) {
                    if (isCheckingAuth) {
                      loginIcon = const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      );
                    } else if (entry.isLoggedIn == true) {
                      loginIcon = Icon(Icons.check_circle_rounded,
                          size: 11, color: Colors.green.shade600);
                    } else if (entry.isLoggedIn == false) {
                      loginIcon = Icon(Icons.cancel_rounded,
                          size: 11, color: Colors.orange.shade700);
                    }
                  }
                  return DropdownMenuItem<String>(
                    value: entry.cli.name,
                    child: Row(
                      children: [
                        Icon(
                          entry.installed
                              ? Icons.circle_rounded
                              : Icons.circle_outlined,
                          size: 10,
                          color: entry.installed ? cs.primary : cs.outline,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.cli.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (loginIcon != null) ...[const SizedBox(width: 4), loginIcon],
                      ],
                    ),
                  );
                }).toList(growable: false),
                onChanged: isScanning ? null : onCliChanged,
                enabled: !isScanning && scanResults.isNotEmpty,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactDropdown<String>(
                label: isZh ? '模型' : 'Model',
                value: effectiveModel,
                items: models
                    .map(
                      (m) => DropdownMenuItem<String>(
                        value: m,
                        child: Text(
                          m,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: models.isNotEmpty ? onModelChanged : null,
                enabled: selectedCli != null && models.isNotEmpty,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: selectedCli != null ? onApply : null,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text(isZh ? '应用至所有角色' : 'Apply to all roles'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI status panel: shows uninstalled CLIs with install / view-docs buttons
// ─────────────────────────────────────────────────────────────────────────────

class _CliStatusPanel extends StatelessWidget {
  const _CliStatusPanel({
    required this.scanResults,
    required this.isZh,
    required this.onInstall,
    required this.onOpenDoc,
  });

  final List<CliScanEntry> scanResults;
  final bool isZh;
  final Future<void> Function(HardnessCli cli) onInstall;
  final Future<void> Function(String url) onOpenDoc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final notInstalled =
        scanResults.where((r) => !r.installed && r.cli.supportsHeadless).toList();
    if (notInstalled.isEmpty) return const SizedBox.shrink();

    final autoInstallable =
        notInstalled.where((r) => r.cli.isAutoInstallable).length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isZh
                        ? '以下 ${notInstalled.length} 个 CLI 未安装'
                            '${autoInstallable > 0 ? "，其中 $autoInstallable 个可一键安装" : "，请安装后点击刷新"}'
                        : '${notInstalled.length} CLI(s) not installed'
                            '${autoInstallable > 0 ? " — $autoInstallable auto-installable" : " — install then refresh"}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...notInstalled.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _CliInstallRow(
                  entry: entry,
                  isZh: isZh,
                  onInstall: () => onInstall(entry.cli),
                  onViewDocs: entry.cli.installDocUrl != null
                      ? () => onOpenDoc(entry.cli.installDocUrl!)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CliInstallRow extends StatelessWidget {
  const _CliInstallRow({
    required this.entry,
    required this.isZh,
    required this.onInstall,
    this.onViewDocs,
  });

  final CliScanEntry entry;
  final bool isZh;
  final VoidCallback onInstall;
  final VoidCallback? onViewDocs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cli = entry.cli;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.circle_outlined,
                size: 10, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cli.name,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurface,
                      )),
                  if (cli.installCommand != null)
                    Text(
                      cli.installCommand!.join(' '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (cli.isAutoInstallable)
              OutlinedButton.icon(
                onPressed: onInstall,
                icon: const Icon(Icons.download_rounded, size: 14),
                label: Text(
                  isZh ? '一键安装' : 'Install',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  side:
                      BorderSide(color: colorScheme.primary.withValues(alpha: 0.7)),
                  foregroundColor: colorScheme.primary,
                ),
              ),
            if (!cli.isAutoInstallable && onViewDocs != null) ...[
              OutlinedButton.icon(
                onPressed: onViewDocs,
                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                label: Text(
                  isZh ? '安装文档' : 'Docs',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  side: BorderSide(
                      color: colorScheme.secondary.withValues(alpha: 0.7)),
                  foregroundColor: colorScheme.secondary,
                ),
              ),
            ],
            if (!cli.supportsHeadless) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: isZh
                    ? '此工具为 GUI 应用，不支持无交互 CLI 调用，无法用于 Hardness Engineering'
                    : 'GUI-only app, does not support non-interactive CLI invocation',
                child: Icon(Icons.monitor_rounded,
                    size: 16, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI auth-status panel: installed but not logged in
// ─────────────────────────────────────────────────────────────────────────────

class _CliAuthStatusPanel extends StatelessWidget {
  const _CliAuthStatusPanel({
    required this.scanResults,
    required this.isCheckingAuth,
    required this.isZh,
    required this.onLogin,
  });

  final List<CliScanEntry> scanResults;
  final bool isCheckingAuth;
  final bool isZh;
  final Future<void> Function(CliScanEntry entry) onLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show a subtle loading row while auth probing is still in progress.
    if (isCheckingAuth) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isZh ? '正在检测 CLI 登录状态...' : 'Checking CLI login states...',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // Only show CLIs that are installed, have a login check, and are confirmed NOT logged in.
    final notLoggedIn = scanResults
        .where((r) => r.installed && r.cli.hasLoginCheck && r.isLoggedIn == false)
        .toList(growable: false);

    if (notLoggedIn.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.login_rounded, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isZh
                          ? '以下 ${notLoggedIn.length} 个 CLI 已安装但尚未登录，需要登录才能正常使用'
                          : '${notLoggedIn.length} installed CLI(s) are not logged in and may fail at runtime',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...notLoggedIn.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _CliLoginRow(
                    entry: entry,
                    isZh: isZh,
                    onLogin: () => onLogin(entry),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single row in the auth-status panel
// ─────────────────────────────────────────────────────────────────────────────

class _CliLoginRow extends StatelessWidget {
  const _CliLoginRow({
    required this.entry,
    required this.isZh,
    required this.onLogin,
  });

  final CliScanEntry entry;
  final bool isZh;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cli = entry.cli;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cancel_rounded,
                size: 12, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cli.name,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: colorScheme.onSurface),
                  ),
                  Text(
                    isZh ? '已安装，但未登录' : 'Installed, but not logged in',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade700,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_rounded, size: 14),
              label: Text(
                isZh ? '登录' : 'Login',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                side: BorderSide(color: Colors.orange.shade600.withValues(alpha: 0.8)),
                foregroundColor: Colors.orange.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

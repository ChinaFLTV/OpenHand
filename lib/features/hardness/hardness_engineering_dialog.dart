import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../shared/widgets/openhand_dialog_action_button.dart';
import 'hardness_cli_catalog.dart';
import 'hardness_cli_install_dialog.dart';
import 'hardness_cli_login_dialog.dart';
import 'model/hardness_agent_role.dart';
import 'model/hardness_role_config.dart';
import 'model/hardness_session_config.dart';

class HardnessEngineeringDialog extends StatefulWidget {
  const HardnessEngineeringDialog({super.key});

  @override
  State<HardnessEngineeringDialog> createState() =>
      _HardnessEngineeringDialogState();
}

class _HardnessEngineeringDialogState extends State<HardnessEngineeringDialog> {
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _workingDirController = TextEditingController();
  final TextEditingController _persistenceDirController =
      TextEditingController();
  String? _lastSuggestedPersistenceDir;

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

  String _defaultPersistenceDirectoryFor(String workingDirectory) {
    final trimmedWorkingDirectory = workingDirectory.trim();
    if (trimmedWorkingDirectory.isEmpty) {
      return '';
    }
    return p.join(trimmedWorkingDirectory, 'harness');
  }

  void _applyWorkingDirectorySelection(String workingDirectory) {
    final trimmedWorkingDirectory = workingDirectory.trim();
    final previousSuggestedPersistenceDir = _lastSuggestedPersistenceDir;
    _workingDirController.text = trimmedWorkingDirectory;

    if (trimmedWorkingDirectory.isEmpty) {
      _lastSuggestedPersistenceDir = null;
      return;
    }

    final nextSuggestedPersistenceDir = _defaultPersistenceDirectoryFor(
      trimmedWorkingDirectory,
    );
    final currentPersistenceDir = _persistenceDirController.text.trim();
    final shouldAutofillPersistenceDir =
        currentPersistenceDir.isEmpty ||
        (previousSuggestedPersistenceDir != null &&
            currentPersistenceDir == previousSuggestedPersistenceDir);

    if (shouldAutofillPersistenceDir) {
      _persistenceDirController.text = nextSuggestedPersistenceDir;
    }
    _lastSuggestedPersistenceDir = nextSuggestedPersistenceDir;
  }

  Future<void> _pickDirectory(TextEditingController controller) async {
    final current = controller.text.trim();
    final result = await getDirectoryPath(
      initialDirectory: current.isNotEmpty ? current : null,
    );
    if (result != null && mounted) {
      if (identical(controller, _workingDirController)) {
        _applyWorkingDirectorySelection(result);
        return;
      }
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

  String? _preferredModelForCli(String? cliName, {String? currentModel}) {
    if (cliName == null) {
      return null;
    }
    final trimmedCurrentModel = currentModel?.trim();
    return trimmedCurrentModel == null || trimmedCurrentModel.isEmpty
        ? null
        : trimmedCurrentModel;
  }

  HardnessRoleConfig _roleConfig(HardnessAgentRole role) => HardnessRoleConfig(
    cliName: _selectedCli[role] ?? '',
    modelId: (() {
      final cliName = _selectedCli[role] ?? '';
      final rawModelId = _selectedModel[role] ?? '';
      final cli = _entryForCli(cliName)?.cli ?? findHardnessCliByName(cliName);
      if (cli == null) {
        return rawModelId;
      }
      return normalizeHardnessCliModelId(cli, rawModelId);
    })(),
  );

  List<String> _configurationIssues(bool isZh) {
    final issues = <String>[];
    for (final role in HardnessAgentRole.values) {
      final roleLabel = isZh ? role.displayNameZh : role.displayNameEn;
      final roleConfig = _roleConfig(role);
      final cliName = roleConfig.cliName.trim();
      final modelId = roleConfig.modelId.trim();

      if (cliName.isEmpty) {
        issues.add(isZh ? '$roleLabel：请选择 CLI。' : '$roleLabel: choose a CLI.');
        continue;
      }

      final entry = _entryForCli(cliName);
      if (entry == null) {
        issues.add(
          isZh
              ? '$roleLabel：无法识别所选 CLI，请重新选择。'
              : '$roleLabel: the selected CLI is no longer available. Re-select it.',
        );
        continue;
      }

      if (!entry.installed) {
        issues.add(
          isZh
              ? '$roleLabel：所选 CLI 尚未安装。'
              : '$roleLabel: the selected CLI is not installed.',
        );
        continue;
      }

      if (modelId.isEmpty) {
        issues.add(isZh ? '$roleLabel：请选择模型。' : '$roleLabel: choose a model.');
        continue;
      }
    }
    return issues;
  }

  List<String> _geminiAccessAdvisories(bool isZh) {
    final geminiRoleLabels = <String>[];
    var hasLoggedInGemini = false;
    var hasPinnedGeminiModel = false;
    final geminiCli = findHardnessCliByName('Gemini CLI');

    for (final role in HardnessAgentRole.values) {
      final roleLabel = isZh ? role.displayNameZh : role.displayNameEn;
      final roleConfig = _roleConfig(role);
      final cliName = roleConfig.cliName.trim();
      final modelId = roleConfig.modelId.trim();

      if (cliName.isEmpty || modelId.isEmpty) {
        continue;
      }

      final entry = _entryForCli(cliName);
      if (entry == null ||
          !entry.installed ||
          entry.cli.executable != 'gemini') {
        continue;
      }

      geminiRoleLabels.add(roleLabel);
      hasLoggedInGemini = hasLoggedInGemini || entry.isLoggedIn == true;
      hasPinnedGeminiModel =
          hasPinnedGeminiModel ||
          !isHardnessCliDefaultModel(entry.cli, modelId);
    }

    if (geminiRoleLabels.isEmpty) {
      return const [];
    }

    final roleSummary = geminiRoleLabels.join(isZh ? '、' : ', ');
    final defaultModelLabel = describeHardnessCliModel(
      geminiCli,
      kHardnessGeminiDefaultModelId,
      isZh: isZh,
    );
    final flashModelLabel = describeHardnessCliModel(
      geminiCli,
      'gemini-2.5-flash',
      isZh: isZh,
    );

    return [
      isZh
          ? '当前使用 Gemini 的角色：$roleSummary。OpenHand 不会在 setup 阶段根据本地模型列表预先判定你填写的 Gemini 模型是否“受支持”，真正可用性要以 CLI 实际运行结果为准。'
          : 'Roles currently using Gemini: $roleSummary. OpenHand does not pre-judge whether a Gemini model is “supported” from the local catalog during setup; actual availability is determined by the real CLI/runtime result.',
      hasLoggedInGemini
          ? (isZh
                ? '即使状态显示“已登录”，免费版或受限账号在运行时仍可能对部分 Pro / Preview 模型返回无权限或 model not found 类错误。'
                : 'Even when the CLI shows as logged in, free-tier or restricted accounts can still return permission or model-not-found style errors for some Pro / Preview models at runtime.')
          : (isZh
                ? 'OpenHand 在 setup 阶段只能校验模型 ID 和登录状态，无法预先确认你随后使用的 Google 账号是否具备该模型权限。'
                : 'During setup, OpenHand can only validate the model ID and login state; it cannot pre-verify whether the Google account you use will actually be entitled to that model.'),
      hasPinnedGeminiModel
          ? (isZh
                ? '如果你不确定账号额度或权限，优先改用 $defaultModelLabel 或 $flashModelLabel；若运行后仍失败，可在 dashboard 中修改模型后从失败阶段手动重试。'
                : 'If you are unsure about quota or account entitlements, prefer $defaultModelLabel or $flashModelLabel. If runtime still fails, change the model in the dashboard and manually retry from the failed phase.')
          : (isZh
                ? '即使使用 $defaultModelLabel，也仍会受当前账号权限影响；若运行后失败，可在 dashboard 中改模型后从失败阶段手动重试。'
                : 'Even with $defaultModelLabel, runtime access still depends on the current account. If execution fails, change the model in the dashboard and manually retry from the failed phase.'),
    ];
  }

  CliScanEntry? _entryForCli(String? name) => name == null
      ? null
      : _scanResults.where((r) => r.cli.name == name).firstOrNull;

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

  /// Opens an in-app interactive login dialog for the selected CLI.
  Future<void> _launchCliLogin(CliScanEntry entry) async {
    final cli = entry.cli;
    if (!cli.hasLoginTrigger) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => HardnessCliLoginDialog(entry: entry),
    );

    if (mounted) {
      await _scanClis();
    }
  }

  /// Performs a CLI logout after user confirmation.
  Future<void> _launchCliLogout(CliScanEntry entry) async {
    final cli = entry.cli;
    if (!cli.hasLogoutTrigger) return;

    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    // Confirmation dialog.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isZh ? '确认登出' : 'Confirm Logout'),
        content: Text(
          isZh
              ? '确定要登出 ${cli.name} 吗？登出后需要重新登录才能使用该 CLI。'
              : 'Are you sure you want to log out of ${cli.name}? You will need to log in again to use this CLI.',
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(context).pop(false),
            label: isZh ? '取消' : 'Cancel',
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(context).pop(true),
            label: isZh ? '登出' : 'Logout',
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show a loading indicator while performing logout.
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _isCheckingAuth = true);

    final result = await performCliLogout(entry);

    if (!mounted) return;

    if (scaffoldMessenger != null) {
      final strippedMessage = stripHardnessCliTerminalSequences(result.message);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? (isZh
                    ? '${cli.name} 已登出。$strippedMessage'
                    : '${cli.name} logged out. $strippedMessage')
                : (isZh
                    ? '${cli.name} 登出失败：$strippedMessage'
                    : '${cli.name} logout failed: $strippedMessage'),
          ),
          backgroundColor: result.success ? null : Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    await _scanClis();
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
      final preferredModel = _preferredModelForCli(
        _quickCli,
        currentModel: _quickModel,
      );
      for (final role in HardnessAgentRole.values) {
        _selectedCli[role] = _quickCli;
        _selectedModel[role] = preferredModel;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final configurationIssues = _configurationIssues(isZh);
    final geminiAccessAdvisories = _geminiAccessAdvisories(isZh);
    final canSubmit = _isValid && !_isScanning && configurationIssues.isEmpty;

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
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
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
                hint: isZh
                    ? '输入或选择项目根目录路径'
                    : 'Enter or browse project root path',
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                    ),
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
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
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
                  onLogin: (entry) => _launchCliLogin(entry),
                  onLogout: (entry) => _launchCliLogout(entry),
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
                  _quickModel = _preferredModelForCli(
                    v,
                    currentModel: _quickModel,
                  );
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
                          isZh ? '扫描已安装的 CLI...' : 'Scanning installed CLIs...',
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
                  final showViewDocs =
                      notInstalled &&
                      !(cli?.isAutoInstallable ?? false) &&
                      (cli?.installDocUrl?.isNotEmpty ?? false);
                  // Show login button only when we have confirmed not-logged-in state.
                  final showLogin =
                      selectedCliName != null &&
                      (entry?.installed ?? false) &&
                      entry?.isLoggedIn == false &&
                      (cli?.hasLoginTrigger ?? false);
                  // Show logout button when confirmed logged-in and CLI supports logout.
                  final showLogout =
                      selectedCliName != null &&
                      (entry?.installed ?? false) &&
                      entry?.isLoggedIn == true &&
                      (cli?.hasLogoutTrigger ?? false);
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
                    showLogoutButton: showLogout,
                    isCheckingAuth: _isCheckingAuth,
                    onCliChanged: (v) => setState(() {
                      _selectedCli[role] = v;
                      _selectedModel[role] = _preferredModelForCli(
                        v,
                        currentModel: _selectedModel[role],
                      );
                    }),
                    onModelChanged: (v) => setState(() {
                      _selectedModel[role] = v;
                    }),
                    onInstall: cli != null
                        ? () => _showInstallDialog(cli)
                        : null,
                    onViewDocs: (cli?.installDocUrl != null)
                        ? () => _openDocUrl(cli!.installDocUrl!)
                        : null,
                    onLogin: (entry != null && (cli?.hasLoginTrigger ?? false))
                        ? () => _launchCliLogin(entry)
                        : null,
                    onLogout: (entry != null && (cli?.hasLogoutTrigger ?? false))
                        ? () => _launchCliLogout(entry)
                        : null,
                  );
                }),

              if (!_isScanning && configurationIssues.isNotEmpty) ...[
                const SizedBox(height: 4),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isZh
                                    ? '开始前请先修正以下配置问题'
                                    : 'Resolve these configuration issues before starting',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final issue in configurationIssues.take(4))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $issue',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface,
                                height: 1.4,
                              ),
                            ),
                          ),
                        if (configurationIssues.length > 4)
                          Text(
                            isZh
                                ? '还有 ${configurationIssues.length - 4} 项待处理。'
                                : '${configurationIssues.length - 4} more issue(s) need attention.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],

              if (!_isScanning && geminiAccessAdvisories.isNotEmpty) ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(
                      alpha: 0.28,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.secondary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: colorScheme.secondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isZh
                                    ? 'Gemini 模型访问说明'
                                    : 'Gemini model access note',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final advisory in geminiAccessAdvisories)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $advisory',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface,
                                height: 1.4,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: () =>
                              _openDocUrl(kHardnessGeminiModelsDocUrl),
                          icon: const Icon(Icons.open_in_new_rounded, size: 15),
                          label: Text(
                            isZh
                                ? '查看 Gemini 官方模型文档'
                                : 'View Gemini model docs',
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            foregroundColor: colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Env hint
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 13,
                      color: colorScheme.outline,
                    ),
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
          onPressed: canSubmit ? _submit : null,
          label: isZh ? '开始会话' : 'Start Session',
        ),
      ],
    );
  }
}

String _hardnessConfiguredModelLabel(
  HardnessCli? cli,
  String modelId, {
  required bool isZh,
}) {
  return describeHardnessCliModel(cli, modelId, isZh: isZh);
}

List<DropdownMenuItem<String>> _hardnessModelDropdownItems({
  required HardnessCli? cli,
  required List<String> availableModels,
  required String? configuredModel,
  required bool isZh,
}) {
  final items = <DropdownMenuItem<String>>[];
  final trimmedConfiguredModel = configuredModel?.trim();
  if (trimmedConfiguredModel != null &&
      trimmedConfiguredModel.isNotEmpty &&
      !availableModels.contains(trimmedConfiguredModel)) {
    items.add(
      DropdownMenuItem<String>(
        value: trimmedConfiguredModel,
        child: Text(
          _hardnessConfiguredModelLabel(
            cli,
            trimmedConfiguredModel,
            isZh: isZh,
          ),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
  items.addAll(
    availableModels.map(
      (modelId) => DropdownMenuItem<String>(
        value: modelId,
        child: Text(
          describeHardnessCliModel(cli, modelId, isZh: isZh),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    ),
  );
  return items;
}

String? _hardnessResolvedDropdownModelValue(
  List<DropdownMenuItem<String>> items,
  String? configuredModel,
) {
  final trimmedConfiguredModel = configuredModel?.trim();
  if (trimmedConfiguredModel == null || trimmedConfiguredModel.isEmpty) {
    return null;
  }
  return items.any((item) => item.value == trimmedConfiguredModel)
      ? trimmedConfiguredModel
      : null;
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
    this.showLogoutButton = false,
    this.isCheckingAuth = false,
    required this.onCliChanged,
    required this.onModelChanged,
    this.onInstall,
    this.onViewDocs,
    this.onLogin,
    this.onLogout,
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
  final bool showLogoutButton;
  final bool isCheckingAuth;
  final ValueChanged<String?> onCliChanged;
  final ValueChanged<String?> onModelChanged;
  final VoidCallback? onInstall;
  final VoidCallback? onViewDocs;
  final VoidCallback? onLogin;
  final VoidCallback? onLogout;

  // Returns the CliScanEntry for the currently selected CLI (if any).
  CliScanEntry? get _selectedEntry => selectedCli == null
      ? null
      : scanResults.where((r) => r.cli.name == selectedCli).firstOrNull;

  List<DropdownMenuItem<String>> _buildCliItems(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return scanResults
        .where((e) => e.cli.supportsHeadless)
        .map((entry) {
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
              loginIcon = Icon(
                Icons.check_circle_rounded,
                size: 11,
                color: Colors.green.shade600,
              );
            } else if (entry.isLoggedIn == false) {
              loginIcon = Icon(
                Icons.cancel_rounded,
                size: 11,
                color: Colors.orange.shade700,
              );
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
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final roleName = isZh ? role.displayNameZh : role.displayNameEn;
    final selectedCliEntry = _selectedEntry;
    final modelItems = _hardnessModelDropdownItems(
      cli: selectedCliEntry?.cli,
      availableModels: availableModels,
      configuredModel: selectedModel,
      isZh: isZh,
    );
    final effectiveModel = _hardnessResolvedDropdownModelValue(
      modelItems,
      selectedModel,
    );

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
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                  ),
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
                  items: modelItems,
                  onChanged: modelItems.isNotEmpty ? onModelChanged : null,
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
                  message: isZh
                      ? '此 CLI 尚未登录，点击引导登录'
                      : 'This CLI is not logged in — click to start login',
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
              // Logout button for confirmed-logged-in state
              if (showLogoutButton) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: isZh
                      ? '此 CLI 已登录，点击可登出以切换账号'
                      : 'This CLI is logged in — click to log out and switch accounts',
                  child: OutlinedButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_rounded, size: 15),
                    label: Text(
                      isZh ? '登出' : 'Logout',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      side: BorderSide(
                        color: colorScheme.outline.withValues(alpha: 0.6),
                      ),
                      foregroundColor: colorScheme.onSurfaceVariant,
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
    final selectedCliEntry = scanResults
        .where((entry) => entry.cli.name == selectedCli)
        .firstOrNull;
    final modelItems = _hardnessModelDropdownItems(
      cli: selectedCliEntry?.cli,
      availableModels: models,
      configuredModel: selectedModel,
      isZh: isZh,
    );
    final effectiveModel = _hardnessResolvedDropdownModelValue(
      modelItems,
      selectedModel,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.bolt_rounded, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              isZh ? '一键统一配置' : 'Apply to all',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CompactDropdown<String>(
                label: isZh ? 'CLI 客户端' : 'CLI Client',
                value: selectedCli,
                items: scanResults
                    .where((e) => e.cli.supportsHeadless)
                    .map((entry) {
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
                          loginIcon = Icon(
                            Icons.check_circle_rounded,
                            size: 11,
                            color: Colors.green.shade600,
                          );
                        } else if (entry.isLoggedIn == false) {
                          loginIcon = Icon(
                            Icons.cancel_rounded,
                            size: 11,
                            color: Colors.orange.shade700,
                          );
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
                            if (loginIcon != null) ...[
                              const SizedBox(width: 4),
                              loginIcon,
                            ],
                          ],
                        ),
                      );
                    })
                    .toList(growable: false),
                onChanged: isScanning ? null : onCliChanged,
                enabled: !isScanning && scanResults.isNotEmpty,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactDropdown<String>(
                label: isZh ? '模型' : 'Model',
                value: effectiveModel,
                items: modelItems,
                onChanged: modelItems.isNotEmpty ? onModelChanged : null,
                enabled: selectedCli != null && models.isNotEmpty,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: selectedCli != null ? onApply : null,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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

    final notInstalled = scanResults
        .where((r) => !r.installed && r.cli.supportsHeadless)
        .toList();
    if (notInstalled.isEmpty) return const SizedBox.shrink();

    final autoInstallable = notInstalled
        .where((r) => r.cli.isAutoInstallable)
        .length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: colorScheme.error,
                ),
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
            Icon(
              Icons.circle_outlined,
              size: 10,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cli.name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
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
            ],
            if (!cli.supportsHeadless) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: isZh
                    ? '此工具为 GUI 应用，不支持无交互 CLI 调用，无法用于 Hardness Engineering'
                    : 'GUI-only app, does not support non-interactive CLI invocation',
                child: Icon(
                  Icons.monitor_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
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
    required this.onLogout,
  });

  final List<CliScanEntry> scanResults;
  final bool isCheckingAuth;
  final bool isZh;
  final Future<void> Function(CliScanEntry entry) onLogin;
  final Future<void> Function(CliScanEntry entry) onLogout;

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
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // CLIs that are installed, have a login check, and are confirmed NOT logged in.
    final notLoggedIn = scanResults
        .where(
          (r) =>
              r.installed &&
              r.cli.hasLoginCheck &&
              r.cli.hasLoginTrigger &&
              r.isLoggedIn == false,
        )
        .toList(growable: false);

    // CLIs that are installed, confirmed logged in, and support logout.
    final loggedIn = scanResults
        .where(
          (r) =>
              r.installed &&
              r.cli.hasLoginCheck &&
              r.cli.hasLogoutTrigger &&
              r.isLoggedIn == true,
        )
        .toList(growable: false);

    if (notLoggedIn.isEmpty && loggedIn.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        // Not-logged-in panel (orange warning)
        if (notLoggedIn.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.35),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.login_rounded,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
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
                        child: _CliAuthRow(
                          entry: entry,
                          isZh: isZh,
                          isLoggedIn: false,
                          onLogin: () => onLogin(entry),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Logged-in panel (green info, with logout buttons)
        if (loggedIn.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.30),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isZh
                                ? '以下 ${loggedIn.length} 个 CLI 已安装并已登录，需要切换账号可点击登出'
                                : '${loggedIn.length} installed CLI(s) are logged in — logout to switch accounts',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...loggedIn.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _CliAuthRow(
                          entry: entry,
                          isZh: isZh,
                          isLoggedIn: true,
                          onLogout: () => onLogout(entry),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single row in the auth-status panel (supports both login and logout)
// ─────────────────────────────────────────────────────────────────────────────

class _CliAuthRow extends StatelessWidget {
  const _CliAuthRow({
    required this.entry,
    required this.isZh,
    required this.isLoggedIn,
    this.onLogin,
    this.onLogout,
  });

  final CliScanEntry entry;
  final bool isZh;
  final bool isLoggedIn;
  final VoidCallback? onLogin;
  final VoidCallback? onLogout;

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
            Icon(
              isLoggedIn
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
              size: 12,
              color: isLoggedIn
                  ? Colors.green.shade600
                  : Colors.orange.shade600,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cli.name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    isLoggedIn
                        ? (isZh ? '已安装，已登录' : 'Installed, logged in')
                        : (isZh ? '已安装，但未登录' : 'Installed, but not logged in'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isLoggedIn
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isLoggedIn && onLogin != null)
              OutlinedButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login_rounded, size: 14),
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
            if (isLoggedIn && onLogout != null)
              OutlinedButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded, size: 14),
                label: Text(
                  isZh ? '登出' : 'Logout',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  side: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.6),
                  ),
                  foregroundColor: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

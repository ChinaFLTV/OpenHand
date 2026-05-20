import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../app/state/settings_controller.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/model_search_selector.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../ai/index.dart';
import '../model/hardness_agent_role.dart';
import '../model/hardness_role_config.dart';
import '../model/hardness_session_config.dart';
import '../service/hardness_cli_catalog.dart';
import 'hardness_cli_install_dialog.dart';
import 'hardness_cli_login_dialog.dart';

const double _kHardnessModeDropdownWidth = 132;

class HardnessEngineeringDialog extends StatefulWidget {
  const HardnessEngineeringDialog({super.key, this.settingsController});

  /// Optional settings controller to access configured AI model lists.
  final SettingsController? settingsController;

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
  final Map<HardnessAgentRole, HardnessExecutionMode> _executionMode = {};
  final Map<HardnessAgentRole, String?> _selectedAiModelConfigId = {};
  final Map<HardnessAgentRole, String?> _selectedUrlModeModelId = {};

  // Quick-apply bar state
  HardnessExecutionMode _quickExecutionMode = HardnessExecutionMode.cli;
  String? _quickCli;
  String? _quickModel;
  String? _quickAiModelConfigId;
  String? _quickUrlModeModelId;

  List<CliScanEntry> _scanResults = [];
  bool _isScanning = true;
  bool _isCheckingAuth = false;
  int _scanRequestId = 0;
  final ValueNotifier<int> _logoutSuccessSignal = ValueNotifier<int>(0);
  final ValueNotifier<int> _logoutErrorSignal = ValueNotifier<int>(0);

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
    _logoutSuccessSignal.dispose();
    _logoutErrorSignal.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  Future<void> _scanClis() async {
    final requestId = ++_scanRequestId;
    setState(() {
      _isScanning = true;
      _isCheckingAuth = false;
    });

    // Phase 1 — fast install probe (parallel)
    final results = await scanInstalledClis();
    if (!mounted || requestId != _scanRequestId) return;
    final hasCheckable = results.any((e) => e.installed && e.cli.hasLoginCheck);
    setState(() {
      _scanResults = results;
      _isScanning = false;
      _isCheckingAuth = hasCheckable;
    });

    if (!hasCheckable) return;

    // Phase 2 — auth probe for installed CLIs (parallel, slower)
    final authResults = await Future.wait(results.map(probeCliAuth));
    if (!mounted || requestId != _scanRequestId) return;
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
    return p.join(trimmedWorkingDirectory, 'hardness');
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

  HardnessRoleConfig _roleConfig(HardnessAgentRole role) {
    final mode = _executionMode[role] ?? HardnessExecutionMode.cli;
    if (mode == HardnessExecutionMode.url) {
      return HardnessRoleConfig(
        cliName: '',
        modelId: '',
        executionMode: HardnessExecutionMode.url,
        aiModelConfigId: _selectedAiModelConfigId[role],
        urlModeModelId: _selectedUrlModeModelId[role],
      );
    }
    return HardnessRoleConfig(
      cliName: _selectedCli[role] ?? '',
      modelId: (() {
        final cliName = _selectedCli[role] ?? '';
        final rawModelId = _selectedModel[role] ?? '';
        final cli =
            _entryForCli(cliName)?.cli ?? findHardnessCliByName(cliName);
        if (cli == null) {
          return rawModelId;
        }
        return normalizeHardnessCliModelId(cli, rawModelId);
      })(),
    );
  }

  List<String> _configurationIssues(bool isZh) {
    final issues = <String>[];
    final settingsModels = widget.settingsController?.aiModels ?? const [];
    for (final role in HardnessAgentRole.values) {
      final roleLabel = isZh ? role.displayNameZh : role.displayNameEn;
      final roleConfig = _roleConfig(role);

      if (roleConfig.isUrlMode) {
        final configId = roleConfig.aiModelConfigId;
        if (configId == null || configId.trim().isEmpty) {
          issues.add(
            isZh
                ? '$roleLabel：请选择 API 模型提供商。'
                : '$roleLabel: choose an API model provider.',
          );
          continue;
        }
        final provider = settingsModels
            .where((m) => m.id == configId)
            .firstOrNull;
        if (provider == null) {
          issues.add(
            isZh
                ? '$roleLabel：所选 API 模型提供商不存在，请重新选择。'
                : '$roleLabel: the selected API model provider no longer exists.',
          );
          continue;
        }
        final urlModelId = roleConfig.urlModeModelId?.trim();
        if (urlModelId != null &&
            urlModelId.isNotEmpty &&
            !provider.allModelIds.contains(urlModelId)) {
          issues.add(
            isZh
                ? '$roleLabel：所选模型 "$urlModelId" 在该提供商中不存在。'
                : '$roleLabel: model "$urlModelId" not found in this provider.',
          );
        }
        continue;
      }

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

      // URL-mode roles don't invoke Gemini CLI — skip.
      if (roleConfig.isUrlMode) continue;

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
    final result = await showAnimatedDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => HardnessCliInstallDialog(cli: cli),
    );
    if (result == true && mounted) {
      await _scanClis();
    }
  }

  Future<void> _openDocUrl(String url) async {
    final normalizedUrl = url.trim();
    final parsedUrl = Uri.tryParse(normalizedUrl);
    final canOpenExternally =
        parsedUrl != null &&
        parsedUrl.hasScheme &&
        (parsedUrl.scheme == 'https' || parsedUrl.scheme == 'http');
    if (!canOpenExternally) {
      await Clipboard.setData(ClipboardData(text: normalizedUrl));
      return;
    }

    try {
      if (Platform.isMacOS) {
        await Process.run('open', [normalizedUrl]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [normalizedUrl]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', [
          '/c',
          'start',
          '',
          normalizedUrl,
        ], runInShell: true);
      } else {
        await Clipboard.setData(ClipboardData(text: normalizedUrl));
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: normalizedUrl));
    }
  }

  /// Opens an in-app interactive login dialog for the selected CLI.
  Future<void> _launchCliLogin(CliScanEntry entry) async {
    final cli = entry.cli;
    if (!cli.hasLoginTrigger) return;

    await showAnimatedDialog<void>(
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
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowAlignment: OverflowBarAlignment.center,
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
      final snackMessage = result.success
          ? (isZh
                ? '${cli.name} 已登出。$strippedMessage'
                : '${cli.name} logged out. $strippedMessage')
          : (isZh
                ? '${cli.name} 登出失败：$strippedMessage'
                : '${cli.name} logout failed: $strippedMessage');
      OpenHandSnackBar.show(
        context,
        scaffoldMessenger,
        result.success
            ? OpenHandSnackBar.success(context, snackMessage)
            : OpenHandSnackBar.error(context, snackMessage),
      );
      if (result.success) {
        _logoutSuccessSignal.value++;
      } else {
        _logoutErrorSignal.value++;
      }
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

  /// Applies the quick-apply config to every role at once.
  void _applyQuickConfig() {
    setState(() {
      if (_quickExecutionMode == HardnessExecutionMode.url) {
        if (_quickAiModelConfigId == null) return;
        for (final role in HardnessAgentRole.values) {
          _executionMode[role] = HardnessExecutionMode.url;
          _selectedAiModelConfigId[role] = _quickAiModelConfigId;
          _selectedUrlModeModelId[role] = _quickUrlModeModelId;
        }
      } else {
        if (_quickCli == null) return;
        final preferredModel = _preferredModelForCli(
          _quickCli,
          currentModel: _quickModel,
        );
        for (final role in HardnessAgentRole.values) {
          _executionMode[role] = HardnessExecutionMode.cli;
          _selectedCli[role] = _quickCli;
          _selectedModel[role] = preferredModel;
        }
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
    final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 908, maxHeight: maxDialogHeight),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isZh
                        ? 'Hardness Engineering 配置'
                        : 'Hardness Engineering Setup',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isZh
                                ? 'OpenHand 将作为编排协调层。每个角色可使用 CLI 模式（委托给外部 CLI 工具）或 URL 模式（使用设置中配置的 API 模型，由 OpenHand 直接调度含工具调用的多轮对话）。'
                                : 'OpenHand acts as orchestrator. Each role can use CLI mode (delegate to external CLI tools) or URL mode (use configured API models with full tool integration).',
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
                              labelText: isZh
                                  ? '任务 / 需求'
                                  : 'Task / Requirement',
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
                            onBrowse: () =>
                                _pickDirectory(_workingDirController),
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
                            onBrowse: () =>
                                _pickDirectory(_persistenceDirController),
                          ),
                          const SizedBox(height: 28),

                          // ── Role CLI config header ─────────────────────────────
                          Row(
                            children: [
                              Text(
                                isZh ? '角色配置' : 'Role Configuration',
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else
                                IconButton(
                                  onPressed: _scanClis,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  tooltip: isZh ? '重新扫描 CLI' : 'Re-scan CLIs',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isZh
                                ? '为每个角色选择执行模式（CLI 或 URL）并指定模型。● 已安装，○ 未安装，✓ 已登录，✗ 未登录。'
                                : 'Choose execution mode (CLI or URL) and model for each role. ● installed, ○ not installed, ✓ logged in, ✗ not logged in.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── Compact CLI scan summary ───────────────────────────
                          if (!_isScanning) ...[
                            _CliScanSummary(
                              scanResults: _scanResults,
                              isCheckingAuth: _isCheckingAuth,
                              isZh: isZh,
                            ),
                            const SizedBox(height: 12),
                          ],

                          // ── Quick-apply bar ────────────────────────────────────
                          _QuickApplyBar(
                            isZh: isZh,
                            scanResults: _scanResults,
                            isScanning: _isScanning,
                            isCheckingAuth: _isCheckingAuth,
                            executionMode: _quickExecutionMode,
                            selectedCli: _quickCli,
                            selectedModel: _quickModel,
                            settingsModels:
                                widget.settingsController?.aiModels ?? const [],
                            selectedAiModelConfigId: _quickAiModelConfigId,
                            selectedUrlModeModelId: _quickUrlModeModelId,
                            onExecutionModeChanged: (v) => setState(() {
                              _quickExecutionMode =
                                  v ?? HardnessExecutionMode.cli;
                            }),
                            onCliChanged: (v) => setState(() {
                              _quickCli = v;
                              _quickModel = _preferredModelForCli(
                                v,
                                currentModel: _quickModel,
                              );
                            }),
                            onModelChanged: (v) =>
                                setState(() => _quickModel = v),
                            onAiModelConfigChanged: (configId, modelId) =>
                                setState(() {
                                  _quickAiModelConfigId = configId;
                                  _quickUrlModeModelId = modelId;
                                }),
                            onApply: _applyQuickConfig,
                            modelsForCli: _modelsForCli,
                          ),
                          const SizedBox(height: 12),

                          if (_isScanning && _scanResults.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
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
                                  selectedCliName != null &&
                                  !(entry?.installed ?? true);
                              final showInstall =
                                  notInstalled &&
                                  (cli?.isAutoInstallable ?? false);
                              final showViewDocs =
                                  notInstalled &&
                                  !(cli?.isAutoInstallable ?? false) &&
                                  (cli?.installDocUrl?.isNotEmpty ?? false);
                              final showLogin =
                                  selectedCliName != null &&
                                  (entry?.installed ?? false) &&
                                  entry?.isLoggedIn == false &&
                                  (cli?.hasLoginTrigger ?? false);
                              final showLogout =
                                  selectedCliName != null &&
                                  (entry?.installed ?? false) &&
                                  entry?.isLoggedIn == true &&
                                  (cli?.hasLogoutTrigger ?? false);
                              final executionMode =
                                  _executionMode[role] ??
                                  HardnessExecutionMode.cli;
                              return _RoleConfigRow(
                                key: ValueKey(role),
                                role: role,
                                isZh: isZh,
                                scanResults: _scanResults,
                                executionMode: executionMode,
                                selectedCli: selectedCliName,
                                availableModels: _modelsForCli(selectedCliName),
                                selectedModel: _selectedModel[role],
                                settingsModels:
                                    widget.settingsController?.aiModels ??
                                    const [],
                                selectedAiModelConfigId:
                                    _selectedAiModelConfigId[role],
                                selectedUrlModeModelId:
                                    _selectedUrlModeModelId[role],
                                showInstallButton: showInstall,
                                showViewDocsButton: showViewDocs,
                                showLoginButton: showLogin,
                                showLogoutButton: showLogout,
                                isCheckingAuth: _isCheckingAuth,
                                onExecutionModeChanged: (v) => setState(() {
                                  _executionMode[role] =
                                      v ?? HardnessExecutionMode.cli;
                                }),
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
                                onAiModelConfigChanged: (configId, modelId) =>
                                    setState(() {
                                      _selectedAiModelConfigId[role] = configId;
                                      _selectedUrlModeModelId[role] = modelId;
                                    }),
                                onInstall: cli != null
                                    ? () => _showInstallDialog(cli)
                                    : null,
                                onViewDocs: (cli?.installDocUrl != null)
                                    ? () => _openDocUrl(cli!.installDocUrl!)
                                    : null,
                                onLogin:
                                    (entry != null &&
                                        (cli?.hasLoginTrigger ?? false))
                                    ? () => _launchCliLogin(entry)
                                    : null,
                                onLogout:
                                    (entry != null &&
                                        (cli?.hasLogoutTrigger ?? false))
                                    ? () => _launchCliLogout(entry)
                                    : null,
                              );
                            }),

                          if (!_isScanning &&
                              configurationIssues.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer.withValues(
                                  alpha: 0.16,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: colorScheme.error.withValues(
                                    alpha: 0.24,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  12,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: colorScheme.error,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    for (final issue
                                        in configurationIssues.take(4))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          '• $issue',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
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
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],

                          if (!_isScanning &&
                              geminiAccessAdvisories.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer
                                    .withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: colorScheme.secondary.withValues(
                                    alpha: 0.22,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  12,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: colorScheme.secondary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    for (final advisory
                                        in geminiAccessAdvisories)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          '• $advisory',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colorScheme.onSurface,
                                                height: 1.4,
                                              ),
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    TextButton.icon(
                                      onPressed: () => _openDocUrl(
                                        kHardnessGeminiModelsDocUrl,
                                      ),
                                      icon: const Icon(
                                        Icons.open_in_new_rounded,
                                        size: 15,
                                      ),
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
                  const SizedBox(height: 16),
                  OverflowBar(
                    spacing: 8,
                    overflowAlignment: OverflowBarAlignment.end,
                    alignment: MainAxisAlignment.end,
                    children: [
                      OpenHandDialogActionButton.secondary(
                        onPressed: () => Navigator.of(context).pop(),
                        label: isZh ? '取消' : 'Cancel',
                      ),
                      OpenHandDialogActionButton.primary(
                        onPressed: canSubmit ? _submit : null,
                        label: isZh ? '开始会话' : 'Start Session',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: HighlightPulse(
                  signal: _logoutSuccessSignal,
                  color: const Color(0xFF22C55E),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: HighlightPulse(
                  signal: _logoutErrorSignal,
                  color: const Color(0xFFEF4444),
                ),
              ),
            ),
          ],
        ),
      ),
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
    super.key,
    required this.role,
    required this.isZh,
    required this.scanResults,
    required this.executionMode,
    required this.selectedCli,
    required this.availableModels,
    required this.selectedModel,
    this.settingsModels = const [],
    this.selectedAiModelConfigId,
    this.selectedUrlModeModelId,
    required this.showInstallButton,
    this.showViewDocsButton = false,
    this.showLoginButton = false,
    this.showLogoutButton = false,
    this.isCheckingAuth = false,
    required this.onExecutionModeChanged,
    required this.onCliChanged,
    required this.onModelChanged,
    this.onAiModelConfigChanged,
    this.onInstall,
    this.onViewDocs,
    this.onLogin,
    this.onLogout,
  });

  final HardnessAgentRole role;
  final bool isZh;
  final List<CliScanEntry> scanResults;
  final HardnessExecutionMode executionMode;
  final String? selectedCli;
  final List<String> availableModels;
  final String? selectedModel;
  final List<AiModelConfig> settingsModels;
  final String? selectedAiModelConfigId;
  final String? selectedUrlModeModelId;
  final bool showInstallButton;
  final bool showViewDocsButton;
  final bool showLoginButton;
  final bool showLogoutButton;
  final bool isCheckingAuth;
  final ValueChanged<HardnessExecutionMode?> onExecutionModeChanged;
  final ValueChanged<String?> onCliChanged;
  final ValueChanged<String?> onModelChanged;
  final void Function(String? configId, String? modelId)?
  onAiModelConfigChanged;
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
    final isUrlMode = executionMode == HardnessExecutionMode.url;
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
              // Execution mode toggle.
              SizedBox(
                width: _kHardnessModeDropdownWidth,
                child: _CompactDropdown<HardnessExecutionMode>(
                  label: isZh ? '模式' : 'Mode',
                  value: executionMode,
                  items: const [
                    DropdownMenuItem(
                      value: HardnessExecutionMode.cli,
                      child: Text('CLI', style: TextStyle(fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: HardnessExecutionMode.url,
                      child: Text('URL', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                  onChanged: onExecutionModeChanged,
                ),
              ),
              const SizedBox(width: 10),
              if (isUrlMode) ...[
                // URL mode: show API model config dropdown.
                Expanded(
                  flex: 2,
                  child: _MenuAnchorModelSelector(
                    label: isZh ? 'API 模型' : 'API Model',
                    settingsModels: settingsModels,
                    selectedAiModelConfigId: selectedAiModelConfigId,
                    selectedUrlModeModelId: selectedUrlModeModelId,
                    onChanged: (configId, modelId) {
                      onAiModelConfigChanged?.call(configId, modelId);
                    },
                    enabled: settingsModels.isNotEmpty,
                  ),
                ),
                if (settingsModels.isEmpty) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: isZh
                        ? '请先在设置中配置 API 模型提供商'
                        : 'Configure API model providers in Settings first',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: colorScheme.error,
                    ),
                  ),
                ],
              ] else ...[
                // CLI mode: show CLI + Model dropdowns and action buttons.
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
              ],
              // Auth checking indicator (CLI mode only)
              if (!isUrlMode &&
                  isCheckingAuth &&
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
              // Logged-in confirmation badge (CLI mode only)
              if (!isUrlMode &&
                  !isCheckingAuth &&
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
              // Login button for confirmed-not-logged-in state (CLI mode only)
              if (!isUrlMode && showLoginButton) ...[
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
              // Logout button for confirmed-logged-in state (CLI mode only)
              if (!isUrlMode && showLogoutButton) ...[
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
              // GUI-only warning (CLI mode only)
              if (!isUrlMode &&
                  selectedCli != null &&
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
// Quick-apply bar: pick mode + model and apply to all roles at once
// ─────────────────────────────────────────────────────────────────────────────

class _QuickApplyBar extends StatelessWidget {
  const _QuickApplyBar({
    required this.isZh,
    required this.scanResults,
    required this.isScanning,
    required this.isCheckingAuth,
    required this.executionMode,
    required this.selectedCli,
    required this.selectedModel,
    required this.settingsModels,
    required this.selectedAiModelConfigId,
    required this.selectedUrlModeModelId,
    required this.onExecutionModeChanged,
    required this.onCliChanged,
    required this.onModelChanged,
    required this.onAiModelConfigChanged,
    required this.onApply,
    required this.modelsForCli,
  });

  final bool isZh;
  final List<CliScanEntry> scanResults;
  final bool isScanning;
  final bool isCheckingAuth;
  final HardnessExecutionMode executionMode;
  final String? selectedCli;
  final String? selectedModel;
  final List<AiModelConfig> settingsModels;
  final String? selectedAiModelConfigId;
  final String? selectedUrlModeModelId;
  final ValueChanged<HardnessExecutionMode?> onExecutionModeChanged;
  final ValueChanged<String?> onCliChanged;
  final ValueChanged<String?> onModelChanged;
  final void Function(String? configId, String? modelId) onAiModelConfigChanged;
  final VoidCallback onApply;
  final List<String> Function(String?) modelsForCli;

  bool get _hasUrlModelSelected {
    final id = selectedAiModelConfigId?.trim();
    if (id == null || id.isEmpty) return false;
    final provider = settingsModels.where((m) => m.id == id).firstOrNull;
    if (provider == null) return false;
    final modelId = selectedUrlModeModelId?.trim();
    if (modelId != null && modelId.isNotEmpty) return true;
    return provider.modelId.trim().isNotEmpty;
  }

  bool get _canApply {
    if (executionMode == HardnessExecutionMode.url) {
      return _hasUrlModelSelected;
    }
    return selectedCli != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUrlMode = executionMode == HardnessExecutionMode.url;
    final cliItems = isUrlMode
        ? const <DropdownMenuItem<String>>[]
        : scanResults
              .where((e) => e.cli.supportsHeadless)
              .map((entry) {
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
                      if (loginIcon != null) ...[
                        const SizedBox(width: 4),
                        loginIcon,
                      ],
                    ],
                  ),
                );
              })
              .toList(growable: false);

    // Pre-compute CLI model dropdown data outside the widget tree to avoid
    // the IIFE anti-pattern (which creates new widget instances every build
    // and confuses Flutter's element reconciliation / MouseTracker).
    final cliModels = isUrlMode ? const <String>[] : modelsForCli(selectedCli);
    final cliSelectedEntry = isUrlMode
        ? null
        : scanResults
              .where((entry) => entry.cli.name == selectedCli)
              .firstOrNull;
    final cliModelItems = isUrlMode
        ? const <DropdownMenuItem<String>>[]
        : _hardnessModelDropdownItems(
            cli: cliSelectedEntry?.cli,
            availableModels: cliModels,
            configuredModel: selectedModel,
            isZh: isZh,
          );
    final cliEffectiveModel = isUrlMode
        ? null
        : _hardnessResolvedDropdownModelValue(cliModelItems, selectedModel);

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
              isZh ? '一键配置' : 'Batch',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            // Execution mode toggle
            SizedBox(
              width: _kHardnessModeDropdownWidth,
              child: _CompactDropdown<HardnessExecutionMode>(
                label: isZh ? '模式' : 'Mode',
                value: executionMode,
                items: const [
                  DropdownMenuItem(
                    value: HardnessExecutionMode.cli,
                    child: Text('CLI', style: TextStyle(fontSize: 13)),
                  ),
                  DropdownMenuItem(
                    value: HardnessExecutionMode.url,
                    child: Text('URL', style: TextStyle(fontSize: 13)),
                  ),
                ],
                onChanged: onExecutionModeChanged,
              ),
            ),
            const SizedBox(width: 8),
            if (isUrlMode) ...[
              // URL mode: API model config dropdown
              Expanded(
                flex: 2,
                child: _MenuAnchorModelSelector(
                  label: isZh ? 'API 模型' : 'API Model',
                  settingsModels: settingsModels,
                  selectedAiModelConfigId: selectedAiModelConfigId,
                  selectedUrlModeModelId: selectedUrlModeModelId,
                  onChanged: onAiModelConfigChanged,
                  enabled: settingsModels.isNotEmpty,
                ),
              ),
            ] else ...[
              // CLI mode: CLI + model dropdowns
              Expanded(
                child: _CompactDropdown<String>(
                  label: isZh ? 'CLI 客户端' : 'CLI Client',
                  value: selectedCli,
                  items: cliItems,
                  onChanged: isScanning ? null : onCliChanged,
                  enabled: !isScanning && scanResults.isNotEmpty,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CompactDropdown<String>(
                  label: isZh ? '模型' : 'Model',
                  value: cliEffectiveModel,
                  items: cliModelItems,
                  onChanged: cliModelItems.isNotEmpty ? onModelChanged : null,
                  enabled: selectedCli != null && cliModels.isNotEmpty,
                ),
              ),
            ],
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _canApply ? onApply : null,
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
// Compact CLI scan summary: replaces the large install/auth panels
// ─────────────────────────────────────────────────────────────────────────────

class _CliScanSummary extends StatelessWidget {
  const _CliScanSummary({
    required this.scanResults,
    required this.isCheckingAuth,
    required this.isZh,
  });

  final List<CliScanEntry> scanResults;
  final bool isCheckingAuth;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final headless = scanResults.where((r) => r.cli.supportsHeadless).toList();
    if (headless.isEmpty) return const SizedBox.shrink();

    final installed = headless.where((r) => r.installed).toList();
    final notInstalled = headless.where((r) => !r.installed).toList();

    // Build compact status chips.
    final chips = <Widget>[];

    for (final entry in installed) {
      String? authSuffix;
      if (entry.cli.hasLoginCheck) {
        if (isCheckingAuth) {
          authSuffix = '…';
        } else if (entry.isLoggedIn == true) {
          authSuffix = '✓';
        } else if (entry.isLoggedIn == false) {
          authSuffix = '✗';
        }
      }
      final label = authSuffix != null
          ? '${entry.cli.name}($authSuffix)'
          : entry.cli.name;
      chips.add(
        _ScanChip(
          label: label,
          icon: Icons.circle_rounded,
          iconColor: colorScheme.primary,
        ),
      );
    }

    for (final entry in notInstalled) {
      chips.add(
        _ScanChip(
          label: entry.cli.name,
          icon: Icons.circle_outlined,
          iconColor: colorScheme.outline,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          isZh ? 'CLI 状态：' : 'CLIs:',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        ...chips,
        if (isCheckingAuth)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _ScanChip extends StatelessWidget {
  const _ScanChip({
    required this.label,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 8, color: iconColor),
        const SizedBox(width: 3),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MenuAnchor-based model selector (consistent with composer model selector)
// ─────────────────────────────────────────────────────────────────────────────

class _MenuAnchorModelSelector extends StatefulWidget {
  const _MenuAnchorModelSelector({
    required this.label,
    required this.settingsModels,
    required this.selectedAiModelConfigId,
    required this.selectedUrlModeModelId,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final List<AiModelConfig> settingsModels;
  final String? selectedAiModelConfigId;
  final String? selectedUrlModeModelId;
  final void Function(String? configId, String? modelId) onChanged;
  final bool enabled;

  @override
  State<_MenuAnchorModelSelector> createState() =>
      _MenuAnchorModelSelectorState();
}

class _MenuAnchorModelSelectorState extends State<_MenuAnchorModelSelector> {
  bool _menuOpen = false;

  String? get _displayLabel {
    final id = widget.selectedAiModelConfigId?.trim();
    if (id == null || id.isEmpty) return null;
    final config = widget.settingsModels.where((m) => m.id == id).firstOrNull;
    if (config == null) return null;
    final modelId = widget.selectedUrlModeModelId?.trim();
    if (modelId != null && modelId.isNotEmpty) return modelId;
    if (config.modelId.trim().isNotEmpty) return config.modelId;
    return config.providerLabel;
  }

  void _showMenu() {
    if (_menuOpen || !widget.enabled || widget.settingsModels.isEmpty) return;

    final settingsController = context
        .findAncestorStateOfType<_HardnessEngineeringDialogState>()
        ?.widget
        .settingsController;

    setState(() => _menuOpen = true);
    showModelSearchSelector(
      context: context,
      models: widget.settingsModels,
      recentSelections: settingsController?.recentModelSelections ?? const [],
      selectedConfigId: widget.selectedAiModelConfigId,
      selectedModelId: widget.selectedUrlModeModelId,
    ).then((value) {
      if (mounted) setState(() => _menuOpen = false);
      if (!mounted || value == null) return;
      settingsController?.addRecentModelSelection(value.$1, value.$2);
      widget.onChanged(value.$1, value.$2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: (widget.enabled && widget.settingsModels.isNotEmpty)
          ? _showMenu
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          isDense: true,
          suffixIcon: Icon(
            _menuOpen
                ? Icons.arrow_drop_up_rounded
                : Icons.arrow_drop_down_rounded,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
        ),
        child: Text(
          _displayLabel ?? (widget.enabled ? widget.label : '—'),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: widget.enabled
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

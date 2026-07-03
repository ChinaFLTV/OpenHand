import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/model/app_settings_snapshot.dart';
import '../../../app/state/settings_controller.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/model_search_selector.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/util/input_value_parsing.dart';

import '../../ai/index.dart';

class MachineExpertDialog extends StatefulWidget {
  const MachineExpertDialog({
    super.key,
    this.initialTask,
    this.availableModels = const <AiModelConfig>[],
    this.recentModelSelections = const <RecentModelSelection>[],
    this.initialSelectedModelConfigId,
    this.initialSelectedModelId,
  });

  final String? initialTask;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;
  final String? initialSelectedModelConfigId;
  final String? initialSelectedModelId;

  @override
  State<MachineExpertDialog> createState() => _MachineExpertDialogState();
}

class MachineExpertDialogResult {
  const MachineExpertDialogResult({
    required this.terminalApp,
    required this.windowId,
    required this.tabId,
    required this.taskRequirement,
    this.selectedModelConfigId,
    this.selectedModelId,
    this.windowIndex,
    this.tabIndex,
    this.sessionIndex,
  });

  final String terminalApp;
  final String windowId;
  final String tabId;
  final String taskRequirement;
  final String? selectedModelConfigId;
  final String? selectedModelId;

  /// 1-based window index for precise AppleScript addressing.
  final int? windowIndex;

  /// 1-based tab index within the window.
  final int? tabIndex;

  /// 1-based session index within the tab.
  final int? sessionIndex;

  String toPrompt() {
    var rawTerminal = terminalApp;
    if (rawTerminal == 'iTerm2') {
      rawTerminal = '$terminalApp (AppleScript 进程名为 iTerm)';
    } else if (rawTerminal == 'Terminal' && Platform.isMacOS) {
      rawTerminal = '$terminalApp (macOS 系统自带终端)';
    }

    final positionParts = <String>['窗口：$windowId', '会话：$tabId'];

    // Append precise AppleScript addressing hint when indices are available.
    String addressingHint = '';
    if (windowIndex != null && tabIndex != null && sessionIndex != null) {
      addressingHint =
          '\n- AppleScript 精确定位：【window $windowIndex → tab $tabIndex → session $sessionIndex】';
    } else if (windowIndex != null && tabIndex != null) {
      addressingHint =
          '\n- AppleScript 精确定位：【window $windowIndex → tab $tabIndex】';
    } else if (windowIndex != null) {
      addressingHint = '\n- AppleScript 精确定位：【window $windowIndex】';
    }

    return '''- 终端应用：【$rawTerminal】
- 打开的终端位置：【${positionParts.join('，')}】$addressingHint
- 需求内容（工作环境是：用户在【终端应用】与【打开的终端位置】输入参数中共同指定的目标终端会话环境）：【$taskRequirement】''';
  }
}

class _MachineExpertDialogState extends State<MachineExpertDialog> {
  final TextEditingController _taskController = TextEditingController();

  String? _selectedTerminal;
  String? _selectedWindow;
  String? _selectedTab;
  String? _selectedModelConfigId;
  String? _selectedModelId;

  List<String> _windows = [];
  List<String> _tabs = [];

  /// Maps flat _tabs index → (1-based tabIndex, 1-based sessionIndex) for
  /// iTerm2 precise addressing.  Populated only when the terminal is iTerm2.
  List<(int tabIndex, int sessionIndex)> _tabSessionIndices = [];

  bool _isLoading = false;
  bool _modelMenuOpen = false;
  int _fetchSequence = 0;
  List<String> _allTerminalsCached = [];
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);

  static const Duration _windowFallbackDelay = Duration(milliseconds: 150);
  static const Duration _tabFallbackDelay = Duration(milliseconds: 100);
  static const int _fallbackWindowCount = 10;
  static const int _fallbackSessionCount = 1;

  static const Map<String, List<String>> _terminalsByPlatform = {
    'macOS': [
      'iTerm2',
      'Terminal.app',
      'Warp',
      'Ghostty',
      'Alacritty',
      'Kitty',
      'WezTerm',
      'Tabby',
      'Hyper',
    ],
    'Windows': [
      'PowerShell',
      'Windows Terminal',
      'Command Prompt',
      'SecureCRT',
      'Xshell',
      'MobaXterm',
      'Alacritty',
      'WezTerm',
      'Tabby',
      'Hyper',
    ],
    'Linux': [
      'GNOME Terminal',
      'Konsole',
      'xterm',
      'Tilix',
      'Alacritty',
      'Kitty',
      'WezTerm',
      'Tabby',
      'Hyper',
    ],
  };

  @override
  void initState() {
    super.initState();
    _allTerminalsCached =
        _terminalsByPlatform.values
            .expand((element) => element)
            .toSet()
            .toList()
          ..sort();
    _initDefaults();
  }

  void _initDefaults() {
    final defaultOs = Platform.isMacOS
        ? 'macOS'
        : Platform.isWindows
        ? 'Windows'
        : 'Linux';
    _selectedTerminal = _terminalsByPlatform[defaultOs]?.firstOrNull;
    if (_selectedTerminal != null) {
      // Defer the AppleScript probe until *after* the dialog
      // has rendered its first frame.  Running osascript synchronously
      // inside initState fights for focus with the dialog's TextField on
      // macOS — it briefly activates the target app (iTerm/Terminal) via
      // Apple Events which leaves the host app's IMK input context stale
      // and surfaces as the recurring "can't type or paste in popup
      // text fields" bug accompanied by
      // `IMKCFRunLoopWakeUpReliable` console errors.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final terminal = _selectedTerminal;
        if (terminal != null) {
          _updateWindowsForTerminal(terminal);
        }
      });
    }
    if (widget.initialTask?.isNotEmpty == true) {
      _taskController.text = widget.initialTask!;
    }
    _selectedModelConfigId = widget.initialSelectedModelConfigId?.trim();
    _selectedModelId = widget.initialSelectedModelId?.trim();
    if (!_hasValidModelSelection()) {
      _selectedModelConfigId = null;
      _selectedModelId = null;
    }
  }

  @override
  void dispose() {
    _taskController.dispose();
    _errorPulse.dispose();
    super.dispose();
  }

  Future<List<String>> _fetchMacOSAppleScript(String script) async {
    if (!Platform.isMacOS) return const <String>[];
    final result = await runProcessWithTimeout(
      'osascript',
      ['-e', script],
      timeout: const Duration(seconds: 2),
      tag: 'machine_expert_dialog',
    );
    if (result == null || result.exitCode != 0) {
      return const <String>[];
    }
    final raw = (result.stdout as String).trim();
    if (raw.isEmpty || raw == 'missing value') {
      return const <String>[];
    }
    return raw
        .split(', ')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool _isActiveFetch(int fetchId) => mounted && _fetchSequence == fetchId;

  Future<void> _updateWindowsForTerminal(String terminal) async {
    final currentFetchId = ++_fetchSequence;
    final windowLabel = AppLocalizations.of(context)!.machineExpertWindow;

    setState(() {
      _isLoading = true;
      _windows = [];
      _selectedWindow = null;
      _tabs = [];
      _tabSessionIndices = [];
      _selectedTab = null;
    });

    var clearedLoading = false;
    try {
      List<String> windows = [];
      if (Platform.isMacOS) {
        final appName = terminal == 'iTerm2' ? 'iTerm' : terminal;
        windows = await _fetchMacOSAppleScript(
          'try\ntell application "$appName" to get name of every window\nend try',
        );
      }

      if (!_isActiveFetch(currentFetchId)) return;

      if (windows.isEmpty) {
        await Future.delayed(_windowFallbackDelay);
        if (!_isActiveFetch(currentFetchId)) return;
        windows = List.generate(
          _fallbackWindowCount,
          (index) => '$windowLabel ${index + 1}',
        );
      }

      final seen = <String, int>{};
      for (var i = 0; i < windows.length; i++) {
        final name = windows[i];
        if (seen.containsKey(name)) {
          final currentCount = seen[name]! + 1;
          seen[name] = currentCount;
          windows[i] = '$name ($currentCount)';
        } else {
          seen[name] = 1;
        }
      }

      setState(() {
        _windows = windows;
        _selectedWindow = _windows.firstOrNull;
      });

      if (_selectedWindow != null) {
        // _updateTabsForWindowInternal owns clearing _isLoading on success/early-return.
        clearedLoading = true;
        await _updateTabsForWindowInternal(_selectedWindow!, currentFetchId);
      }
    } finally {
      // Guarantee the loader flag settles for the LATEST fetch even if
      // osascript throws or an unexpected early-return path is taken.
      if (!clearedLoading && _isActiveFetch(currentFetchId) && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateTabsForWindow(String window) async {
    final currentFetchId = ++_fetchSequence;

    setState(() {
      _isLoading = true;
      _tabs = [];
      _tabSessionIndices = [];
      _selectedTab = null;
    });

    try {
      await _updateTabsForWindowInternal(window, currentFetchId);
    } finally {
      if (_isActiveFetch(currentFetchId) && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateTabsForWindowInternal(String window, int fetchId) async {
    // Capture locale-dependent labels before any async gap to avoid
    // use_build_context_synchronously warnings.
    final l10n = AppLocalizations.of(context)!;
    final tabLabel = l10n.machineExpertTab;
    final sessionLabel = l10n.machineExpertSession;

    var tabs = <String>[];
    var indices = <(int, int)>[];
    if (Platform.isMacOS && _selectedTerminal != null) {
      final appName = _selectedTerminal == 'iTerm2'
          ? 'iTerm'
          : _selectedTerminal!;
      final escapedWindow = window.replaceAll('"', '\\"');
      final windowIndex = _windows.indexOf(window) + 1;
      final winIdxStr = windowIndex > 0 ? windowIndex.toString() : '1';

      if (appName == 'iTerm') {
        // iTerm2: enumerate each tab and its sessions individually so we
        // preserve the precise (tab, session) indices.
        final tabCountData = await _fetchMacOSAppleScript(
          'try\ntell application "iTerm" to get count of tabs of window $winIdxStr\nend try',
        );
        final tabCount = tabCountData.isNotEmpty
            ? (optionalIntFromValue(tabCountData.first) ?? 0)
            : 0;
        for (var t = 1; t <= tabCount; t++) {
          final sessionNames = await _fetchMacOSAppleScript(
            'try\ntell application "iTerm" to get name of every session of tab $t of window $winIdxStr\nend try',
          );
          if (sessionNames.isEmpty) {
            // Tab exists but we couldn't get session names – use a placeholder.
            tabs.add('$tabLabel $t / $sessionLabel 1');
            indices.add((t, 1));
          } else {
            for (var s = 0; s < sessionNames.length; s++) {
              tabs.add(sessionNames[s]);
              indices.add((t, s + 1));
            }
          }
        }
      } else if (appName == 'Terminal') {
        tabs = await _fetchMacOSAppleScript(
          'try\ntell application "Terminal" to get custom title of every tab of window $winIdxStr\nend try',
        );
        if (tabs.isEmpty) {
          tabs = await _fetchMacOSAppleScript(
            'try\ntell application "Terminal" to get name of every tab of window $winIdxStr\nend try',
          );
        }
        // Terminal: each tab index maps 1:1.
        for (var i = 0; i < tabs.length; i++) {
          indices.add((i + 1, 1));
        }
      }

      if (tabs.isEmpty) {
        tabs = await _fetchMacOSAppleScript(
          'try\ntell application "$appName" to get name of every tab of window "$escapedWindow"\nend try',
        );
        for (var i = 0; i < tabs.length; i++) {
          indices.add((i + 1, 1));
        }
      }

      if (tabs.isEmpty) {
        // Fallback to exactly the real count of tabs/sessions if possible, otherwise just 1.
        int mockCount = _fallbackSessionCount;
        final countSubject = appName == 'iTerm'
            ? 'session of every tab'
            : 'tab';
        final countData = await _fetchMacOSAppleScript(
          'try\ntell application "$appName" to get count of $countSubject of window $winIdxStr\nend try',
        );
        if (countData.isNotEmpty) {
          final parsed = int.tryParse(countData.first.trim().split(' ').last);
          if (parsed != null && parsed > 0) {
            mockCount = parsed;
          }
        }
        tabs = List.generate(
          mockCount,
          (index) => '$sessionLabel ${index + 1}',
        );
        for (var i = 0; i < mockCount; i++) {
          indices.add((i + 1, 1));
        }
      }
    }

    if (!_isActiveFetch(fetchId)) return;

    if (tabs.isEmpty) {
      await Future.delayed(_tabFallbackDelay);
      if (!_isActiveFetch(fetchId)) return;
      tabs = <String>['$sessionLabel $_fallbackSessionCount'];
    }

    final seen = <String, int>{};
    for (var i = 0; i < tabs.length; i++) {
      final name = tabs[i];
      if (seen.containsKey(name)) {
        final currentCount = seen[name]! + 1;
        seen[name] = currentCount;
        tabs[i] = '$name ($currentCount)';
      } else {
        seen[name] = 1;
      }
    }

    setState(() {
      _tabs = tabs;
      _tabSessionIndices = indices;
      _selectedTab = _tabs.firstOrNull;
      _isLoading = false;
    });
  }

  Widget _buildDropdownItem({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?)? onChanged,
    String Function(String)? displayLabelBuilder,
  }) {
    return Expanded(
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isDense: true,
            isExpanded: true,
            value: value,
            items: items.map((val) {
              return DropdownMenuItem(
                value: val,
                child: Text(displayLabelBuilder?.call(val) ?? val),
              );
            }).toList(),
            onChanged: items.isEmpty ? null : onChanged,
          ),
        ),
      ),
    );
  }

  bool _hasValidModelSelection() {
    final configId = _selectedModelConfigId;
    final modelId = _selectedModelId;
    if (configId == null ||
        configId.isEmpty ||
        modelId == null ||
        modelId.isEmpty) {
      return false;
    }
    return widget.availableModels.any(
      (config) => config.id == configId && config.allModelIds.contains(modelId),
    );
  }

  String? _selectedModelDisplayLabel() {
    final configId = _selectedModelConfigId;
    final modelId = _selectedModelId;
    if (configId == null || configId.isEmpty) {
      return null;
    }
    final config = widget.availableModels
        .where((item) => item.id == configId)
        .firstOrNull;
    if (config == null) {
      return null;
    }
    if (modelId != null && modelId.isNotEmpty) {
      return modelId;
    }
    if (config.modelId.trim().isNotEmpty) {
      return config.modelId.trim();
    }
    return config.providerLabel;
  }

  Future<void> _showModelMenu() async {
    if (_modelMenuOpen) {
      return;
    }
    // 实时从 SettingsController 获取最新模型列表，避免弹窗打开后
    // 用户在设置中增删模型提供商导致数据不同步。
    final settingsController = Provider.of<SettingsController?>(
      context,
      listen: false,
    );
    final latestModels = settingsController?.aiModels ?? widget.availableModels;
    final latestRecent =
        settingsController?.recentModelSelections ??
        widget.recentModelSelections;
    if (latestModels.isEmpty) {
      return;
    }
    setState(() {
      _modelMenuOpen = true;
    });
    final value = await showModelSearchSelector(
      context: context,
      models: latestModels,
      recentSelections: latestRecent,
      selectedConfigId: _selectedModelConfigId,
      selectedModelId: _selectedModelId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _modelMenuOpen = false;
      if (value != null) {
        _selectedModelConfigId = value.$1;
        _selectedModelId = value.$2;
      }
    });
  }

  Widget _buildModelSelector(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final hasModels = widget.availableModels.isNotEmpty;
    final displayLabel = _selectedModelDisplayLabel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: hasModels ? _showModelMenu : null,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.machineExpertModelOptional,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              suffixIcon: Icon(
                _modelMenuOpen
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
              displayLabel ??
                  (hasModels
                      ? l10n.machineExpertModelChoose
                      : l10n.machineExpertModelNotConfiguredDefault),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: hasModels
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hasModels
              ? l10n.machineExpertModelHelperWithModels
              : l10n.machineExpertModelHelperNoModels,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_selectedTerminal == null ||
        _selectedWindow == null ||
        _selectedTab == null ||
        _taskController.text.trim().isEmpty) {
      _errorPulse.value++;
      return;
    }

    if (Platform.isMacOS) {
      setState(() {
        _isLoading = true;
      });
      try {
        final appName = _selectedTerminal == 'iTerm2'
            ? 'iTerm'
            : _selectedTerminal!;
        // Trigger accessibility / automation prompt by asking for a property.
        // Hard timeout + child kill is mandatory to avoid leaking osascript
        // child processes that could disrupt the host app's input method.
        await runProcessWithTimeout('osascript', [
          '-e',
          'try\ntell application "$appName" to get id\nend try',
        ], tag: 'machine_expert_dialog');
      } catch (error, stack) {
        silentLog(
          'machine_expert_dialog',
          'osascript automation prompt',
          error,
          stack,
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }

    if (!mounted) return;

    // Compute precise indices for AppleScript addressing.
    final winIdx = (_windows.indexOf(_selectedWindow!) + 1);
    int? tabIdx;
    int? sessIdx;
    final tabFlatIndex = _tabs.indexOf(_selectedTab!);
    if (tabFlatIndex >= 0 && tabFlatIndex < _tabSessionIndices.length) {
      final (t, s) = _tabSessionIndices[tabFlatIndex];
      tabIdx = t;
      sessIdx = s;
    }

    Navigator.of(context).pop(
      MachineExpertDialogResult(
        terminalApp: _selectedTerminal!,
        windowId: _selectedWindow!,
        tabId: _selectedTab!,
        taskRequirement: _taskController.text.trim(),
        selectedModelConfigId: _selectedModelConfigId,
        selectedModelId: _selectedModelId,
        windowIndex: winIdx > 0 ? winIdx : null,
        tabIndex: tabIdx,
        sessionIndex: sessIdx,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return buildOpenHandAlertDialog(
      title: Text(l10n.machineExpertDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SizedBox(
          width: double.maxFinite,
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.machineExpertDialogBody,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDropdownItem(
                          label: l10n.machineExpertTerminalProgram,
                          value: _selectedTerminal,
                          items: _allTerminalsCached,
                          onChanged: (value) {
                            if (value != null && value != _selectedTerminal) {
                              setState(() {
                                _selectedTerminal = value;
                              });
                              _updateWindowsForTerminal(value);
                            }
                          },
                        ),
                        const SizedBox(width: 16),
                        _buildDropdownItem(
                          label: l10n.machineExpertWindow,
                          value: _selectedWindow,
                          items: _windows,
                          displayLabelBuilder: (w) => w,
                          onChanged: (value) {
                            if (value != null && value != _selectedWindow) {
                              setState(() {
                                _selectedWindow = value;
                              });
                              _updateTabsForWindow(value);
                            }
                          },
                        ),
                        const SizedBox(width: 16),
                        _buildDropdownItem(
                          label: l10n.machineExpertSession,
                          value: _selectedTab,
                          items: _tabs,
                          displayLabelBuilder: (t) => t,
                          onChanged: (value) {
                            if (value != null && value != _selectedTab) {
                              setState(() {
                                _selectedTab = value;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildModelSelector(context),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _taskController,
                      maxLines: 8,
                      minLines: 4,
                      decoration: InputDecoration(
                        labelText: l10n.machineExpertTaskRequirement,
                        hintText: l10n.machineExpertTaskRequirementHint,
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
                        helperText: l10n.machineExpertTaskRequirementHelper,
                      ),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: HighlightPulse(
                    signal: _errorPulse,
                    color: OpenHandStatusColors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _taskController,
          builder: (context, textValue, _) {
            final isValid =
                _selectedTerminal != null &&
                _selectedWindow != null &&
                _selectedTab != null &&
                textValue.text.trim().isNotEmpty;
            return OpenHandDialogActionButton.primary(
              onPressed: (isValid && !_isLoading) ? _submit : null,
              label: l10n.machineExpertStartExecution,
            );
          },
        ),
      ],
    );
  }
}

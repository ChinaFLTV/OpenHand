import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/model/app_settings_snapshot.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/model_search_selector.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../ai/model/ai_model_config.dart';

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

  String _loc(BuildContext context, {required String zh, required String en}) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  }

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
      _updateWindowsForTerminal(_selectedTerminal!);
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
    super.dispose();
  }

  Future<List<String>> _fetchMacOSAppleScript(String script) async {
    if (!Platform.isMacOS) return const <String>[];
    try {
      final result = await Process.run('osascript', [
        '-e',
        script,
      ]).timeout(const Duration(seconds: 2));
      if (result.exitCode == 0) {
        final raw = (result.stdout as String).trim();
        if (raw.isEmpty || raw == 'missing value') return const <String>[];
        return raw
            .split(', ')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<void> _updateWindowsForTerminal(String terminal) async {
    final currentFetchId = ++_fetchSequence;

    setState(() {
      _isLoading = true;
      _windows = [];
      _selectedWindow = null;
      _tabs = [];
      _tabSessionIndices = [];
      _selectedTab = null;
    });

    List<String> windows = [];
    if (Platform.isMacOS) {
      final appName = terminal == 'iTerm2' ? 'iTerm' : terminal;
      windows = await _fetchMacOSAppleScript(
        'try\ntell application "$appName" to get name of every window\nend try',
      );
    }

    if (!mounted || _fetchSequence != currentFetchId) return;

    if (windows.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 150));
      windows = List.generate(
        10,
        (index) => '${_loc(context, zh: '窗口', en: 'Window')} ${index + 1}',
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
      await _updateTabsForWindowInternal(_selectedWindow!, currentFetchId);
    } else {
      setState(() {
        _isLoading = false;
      });
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

    await _updateTabsForWindowInternal(window, currentFetchId);
  }

  Future<void> _updateTabsForWindowInternal(String window, int fetchId) async {
    // Capture locale-dependent labels before any async gap to avoid
    // use_build_context_synchronously warnings.
    final tabLabel = _loc(context, zh: '标签页', en: 'Tab');
    final sessionLabel = _loc(context, zh: '会话', en: 'Session');

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
            ? (int.tryParse(tabCountData.first.trim()) ?? 0)
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
        int mockCount = 1;
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

    if (!mounted || _fetchSequence != fetchId) return;

    if (tabs.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      tabs = <String>['$sessionLabel 1'];
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
    if (_modelMenuOpen || widget.availableModels.isEmpty) {
      return;
    }
    setState(() {
      _modelMenuOpen = true;
    });
    final value = await showModelSearchSelector(
      context: context,
      models: widget.availableModels,
      recentSelections: widget.recentModelSelections,
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
    final hasModels = widget.availableModels.isNotEmpty;
    final displayLabel = _selectedModelDisplayLabel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: hasModels ? _showModelMenu : null,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: _loc(context, zh: '使用模型（可选）', en: 'Model (Optional)'),
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
                  _loc(
                    context,
                    zh: hasModels ? '点击选择模型' : '未配置可用模型，将沿用当前默认模型',
                    en: hasModels
                        ? 'Tap to choose a model'
                        : 'No models configured; current default model will be used',
                  ),
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
          _loc(
            context,
            zh: hasModels
                ? '仅影响本次新建的机器专家线程；若不选，则沿用当前已激活模型。'
                : '尚未在设置中配置模型；本次将继续使用当前激活的默认模型。',
            en: hasModels
                ? 'Applies only to this new Machine Expert session. If not selected, the current active model is kept.'
                : 'No models are configured in Settings. This session will keep using the current active default model.',
          ),
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
        // Trigger accessibility / automation prompt by asking for a property
        final result = await Process.run('osascript', [
          '-e',
          'try\ntell application "$appName" to get id\nend try',
        ]).timeout(const Duration(seconds: 4));
        if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
          // Permission interaction failed or denied
        }
      } catch (e) {
        // Error triggering osascript permission
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

    return AlertDialog(
      title: const Text('机器专家模板配置'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '请指定目标终端窗口与具体任务需求，机器专家将在此工作环境中自动为您执行命令。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDropdownItem(
                      label: '终端程序',
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
                      label: _loc(context, zh: '窗口', en: 'Window'),
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
                      label: _loc(context, zh: '会话', en: 'Session'),
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
                  decoration: const InputDecoration(
                    labelText: '任务需求',
                    hintText: '描述你想要执行的任务，例如：检查当前目录的文件列表，编译项目，部署到远程服务器等...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    helperText: '机器专家将根据该需求和终端现场进行交互式执行。',
                  ),
                ),
                if (_isLoading) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: AppLocalizations.of(context)?.commonCancel ?? '取消',
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
              label: '开始执行',
            );
          },
        ),
      ],
    );
  }
}

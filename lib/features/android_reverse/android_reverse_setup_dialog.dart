import 'package:flutter/material.dart';

import '../../app/model/app_settings_snapshot.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_model_selector_field.dart';
import '../../shared/util/localized_text.dart';
import '../ai/index.dart';
import 'android_reverse_session_config.dart';

/// 弹出 Android 逆向会话创建表单。
/// 返回 null 表示用户取消；返回结果后上层负责创建 controller 和会话。
Future<AndroidReverseSetupResult?> showAndroidReverseSetupDialog(
  BuildContext context, {
  String? initialPackageName,
  String? initialObjective,
  List<AiModelConfig> availableModels = const <AiModelConfig>[],
  List<RecentModelSelection> recentModelSelections =
      const <RecentModelSelection>[],
  String? initialSelectedModelConfigId,
  String? initialSelectedModelId,
}) {
  return showAnimatedDialog<AndroidReverseSetupResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AndroidReverseSetupDialog(
      initialPackageName: initialPackageName,
      initialObjective: initialObjective,
      availableModels: availableModels,
      recentModelSelections: recentModelSelections,
      initialSelectedModelConfigId: initialSelectedModelConfigId,
      initialSelectedModelId: initialSelectedModelId,
    ),
  );
}

class AndroidReverseSetupResult {
  const AndroidReverseSetupResult({
    required this.config,
    required this.selectedModelConfigId,
    required this.selectedModelId,
  });

  final AndroidReverseSessionConfig config;
  final String? selectedModelConfigId;
  final String? selectedModelId;
}

class _AndroidReverseSetupDialog extends StatefulWidget {
  const _AndroidReverseSetupDialog({
    required this.initialPackageName,
    required this.initialObjective,
    required this.availableModels,
    required this.recentModelSelections,
    required this.initialSelectedModelConfigId,
    required this.initialSelectedModelId,
  });

  final String? initialPackageName;
  final String? initialObjective;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;
  final String? initialSelectedModelConfigId;
  final String? initialSelectedModelId;

  @override
  State<_AndroidReverseSetupDialog> createState() =>
      _AndroidReverseSetupDialogState();
}

class _AndroidReverseSetupDialogState
    extends State<_AndroidReverseSetupDialog> {
  late final TextEditingController _objectiveCtrl;
  late final TextEditingController _packageCtrl;
  late final TextEditingController _apkCtrl;
  late final TextEditingController _deviceCtrl;
  late final TextEditingController _authorizationScopeCtrl;
  late final TextEditingController _keywordsCtrl;
  late final TextEditingController _notesCtrl;
  AndroidReverseAnalysisMode _analysisMode =
      AndroidReverseAnalysisMode.balanced;
  bool _adbMcpEnabled = false;
  bool _fridaMcpEnabled = false;
  String? _selectedModelConfigId;
  String? _selectedModelId;

  @override
  void initState() {
    super.initState();
    _objectiveCtrl = TextEditingController(text: widget.initialObjective ?? '');
    _packageCtrl = TextEditingController(text: widget.initialPackageName ?? '');
    _apkCtrl = TextEditingController();
    _deviceCtrl = TextEditingController();
    _authorizationScopeCtrl = TextEditingController();
    _keywordsCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _selectedModelConfigId = widget.initialSelectedModelConfigId?.trim();
    _selectedModelId = widget.initialSelectedModelId?.trim();
    if (!_hasValidModelSelection) {
      _selectedModelConfigId = null;
      _selectedModelId = null;
    }
  }

  @override
  void dispose() {
    _objectiveCtrl.dispose();
    _packageCtrl.dispose();
    _apkCtrl.dispose();
    _deviceCtrl.dispose();
    _authorizationScopeCtrl.dispose();
    _keywordsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _hasValidModelSelection {
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

  bool get _canSubmit =>
      _objectiveCtrl.text.trim().isNotEmpty && _hasValidModelSelection;

  void _submit() {
    final keywords = _keywordsCtrl.text
        .split(RegExp(r'[,\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final config = AndroidReverseSessionConfig(
      objective: _objectiveCtrl.text.trim(),
      packageName: _packageCtrl.text.trim().isEmpty
          ? null
          : _packageCtrl.text.trim(),
      apkPath: _apkCtrl.text.trim().isEmpty ? null : _apkCtrl.text.trim(),
      deviceSerial: _deviceCtrl.text.trim().isEmpty
          ? null
          : _deviceCtrl.text.trim(),
      authorizationScope: _authorizationScopeCtrl.text.trim().isEmpty
          ? null
          : _authorizationScopeCtrl.text.trim(),
      analysisMode: _analysisMode,
      adbMcpEnabled: _adbMcpEnabled,
      fridaMcpEnabled: _fridaMcpEnabled,
      keywords: keywords,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    Navigator.of(context).pop(
      AndroidReverseSetupResult(
        config: config,
        selectedModelConfigId: _selectedModelConfigId,
        selectedModelId: _selectedModelId,
      ),
    );
  }

  bool _isZh() => openHandIsChineseLocale(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = _isZh();
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 620,
      insetPadding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.android_rounded,
            title: isZh ? '新建 Android 逆向会话' : 'New Android Reverse Session',
            subtitle: isZh
                ? '通过 ADB + Frida + jadx 完成 APP 接口逆向与参数还原'
                : 'Reverse Android APP APIs via ADB + Frida + jadx',
            closeTooltip: isZh ? '关闭' : 'Close',
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LabelText(isZh ? '逆向目标 *' : 'Objective *'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _objectiveCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isZh
                          ? '例：还原微信 APP 的 sign 签名算法'
                          : 'e.g. reverse the sign algorithm in com.tencent.mm',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  OpenHandModelSelectorField(
                    models: widget.availableModels,
                    recentSelections: widget.recentModelSelections,
                    selectedConfigId: _selectedModelConfigId,
                    selectedModelId: _selectedModelId,
                    required: true,
                    onSelected: (selection) {
                      setState(() {
                        _selectedModelConfigId = selection.$1;
                        _selectedModelId = selection.$2;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  _LabelText(isZh ? '目标包名（可选）' : 'Package name (optional)'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _packageCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'com.example.app',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabelText(
                    isZh ? 'APK 路径（可选，仅用于静态分析）' : 'APK path (optional)',
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _apkCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '/path/to/app.apk',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabelText(
                    isZh
                        ? 'ADB 设备序列号（可选，留空自动选唯一在线设备）'
                        : 'Device serial (optional)',
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _deviceCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'emulator-5554',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabelText(isZh ? '分析模式' : 'Analysis mode'),
                  const SizedBox(height: 6),
                  SegmentedButton<AndroidReverseAnalysisMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: AndroidReverseAnalysisMode.staticFirst,
                        icon: const Icon(Icons.manage_search_rounded),
                        label: Text(isZh ? '静态优先' : 'Static'),
                      ),
                      ButtonSegment(
                        value: AndroidReverseAnalysisMode.balanced,
                        icon: const Icon(Icons.hub_rounded),
                        label: Text(isZh ? '均衡' : 'Balanced'),
                      ),
                      ButtonSegment(
                        value: AndroidReverseAnalysisMode.dynamicFirst,
                        icon: const Icon(Icons.play_circle_rounded),
                        label: Text(isZh ? '动态验证' : 'Dynamic'),
                      ),
                    ],
                    selected: {_analysisMode},
                    onSelectionChanged: (values) {
                      final next = values.firstOrNull;
                      if (next != null) {
                        setState(() => _analysisMode = next);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  _LabelText(
                    isZh ? '授权范围（建议填写）' : 'Authorization scope (recommended)',
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _authorizationScopeCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isZh
                          ? '例：自有测试 APP / CTF / 已获授权的安全研究，不涉及第三方隐私数据'
                          : 'e.g. owned test app / CTF / authorized research; no third-party private data',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _McpOptInTile(
                    icon: Icons.usb_rounded,
                    titleZh: 'ADB MCP（可选）',
                    titleEn: 'ADB MCP (optional)',
                    descZh: '默认关闭。需先在全局 MCP 配置安装/启用；开启后优先通过 ADB MCP 调用 adb。',
                    descEn:
                        'Off by default. Install/enable it in global MCP settings first; then adb uses ADB MCP first.',
                    isZh: isZh,
                    enabled: _adbMcpEnabled,
                    onChanged: (v) => setState(() => _adbMcpEnabled = v),
                  ),
                  const SizedBox(height: 10),
                  _McpOptInTile(
                    icon: Icons.bug_report_rounded,
                    titleZh: 'Frida MCP（可选）',
                    titleEn: 'Frida MCP (optional)',
                    descZh: '默认关闭。需先在全局 MCP 配置安装/启用；开启后优先通过 Frida MCP 注入脚本。',
                    descEn:
                        'Off by default. Install/enable it in global MCP settings first; then Frida injection uses Frida MCP first.',
                    isZh: isZh,
                    enabled: _fridaMcpEnabled,
                    onChanged: (v) => setState(() => _fridaMcpEnabled = v),
                  ),
                  const SizedBox(height: 14),
                  _LabelText(
                    isZh
                        ? '关键字（可选，逗号分隔）'
                        : 'Keywords (optional, comma-separated)',
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _keywordsCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'sign, encrypt, token',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabelText(isZh ? '备注（可选）' : 'Notes (optional)'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isZh
                          ? '例：账号 test@example.com，代理 127.0.0.1:8080'
                          : 'e.g. test account, proxy 127.0.0.1:8080',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          buildOpenHandDialogActionsBar(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(context).pop(),
                label: isZh ? '取消' : 'Cancel',
              ),
              OpenHandDialogActionButton.primary(
                onPressed: _canSubmit ? _submit : null,
                label: isZh ? '创建会话' : 'Create Session',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _McpOptInTile extends StatelessWidget {
  const _McpOptInTile({
    required this.icon,
    required this.titleZh,
    required this.titleEn,
    required this.descZh,
    required this.descEn,
    required this.isZh,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String titleZh;
  final String titleEn;
  final String descZh;
  final String descEn;
  final bool isZh;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: enabled
            ? cs.primaryContainer.withValues(alpha: 0.42)
            : cs.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled
              ? cs.primary.withValues(alpha: 0.46)
              : cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            enabled ? icon : icon,
            size: 18,
            color: enabled ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isZh ? titleZh : titleEn,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isZh ? descZh : descEn,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LabelText extends StatelessWidget {
  const _LabelText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/model/app_info.dart';
import '../../app/model/app_language.dart';
import '../../app/model/app_settings_snapshot.dart';
import '../../app/model/dialog_animation_settings.dart';
import '../../app/model/openhand_shortcut.dart';
import '../../app/state/settings_controller.dart';
import '../../app/state/settings_store.dart';
import '../../app/support/openhand_paths.dart';
import '../../app/support/url_validation.dart';
import '../../app/theme/openhand_theme_preset.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../../shared/widgets/animated_dialog.dart';
import '../ai/model/ai_allow_command_rule.dart';
import '../ai/model/ai_deny_command_rule.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/service/ai_chat_service.dart';
import '../ai/service/ai_model_scanner.dart';
import '../mcp/mcp_controller.dart';
import '../memory/memory_controller.dart';
import '../skills/skills_controller.dart';

typedef _SettingsPathGetter = String Function(SettingsController controller);
typedef _SettingsPathOperation = Future<bool> Function(String path);

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final TextEditingController _skillsPathController;
  late final FocusNode _skillsPathFocusNode;
  late final TextEditingController _memoryFileController;
  late final FocusNode _memoryFileFocusNode;
  late final TextEditingController _compressionThresholdController;
  late final FocusNode _compressionThresholdFocusNode;
  late final TextEditingController _toolCallLimitController;
  late final FocusNode _toolCallLimitFocusNode;
  late final TextEditingController _sequentialToolRoundLimitController;
  late final FocusNode _sequentialToolRoundLimitFocusNode;
  final Set<String> _testingAiModelIds = <String>{};

  @override
  void initState() {
    super.initState();
    _skillsPathController = TextEditingController();
    _skillsPathFocusNode = FocusNode();
    _memoryFileController = TextEditingController();
    _memoryFileFocusNode = FocusNode();
    _compressionThresholdController = TextEditingController();
    _compressionThresholdFocusNode = FocusNode();
    _toolCallLimitController = TextEditingController();
    _toolCallLimitFocusNode = FocusNode();
    _sequentialToolRoundLimitController = TextEditingController();
    _sequentialToolRoundLimitFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _skillsPathController.dispose();
    _skillsPathFocusNode.dispose();
    _memoryFileController.dispose();
    _memoryFileFocusNode.dispose();
    _compressionThresholdController.dispose();
    _compressionThresholdFocusNode.dispose();
    _toolCallLimitController.dispose();
    _toolCallLimitFocusNode.dispose();
    _sequentialToolRoundLimitController.dispose();
    _sequentialToolRoundLimitFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settingsController = context.watch<SettingsController>();
    final appInfo = context.read<AppInfo>();

    if (!_skillsPathFocusNode.hasFocus &&
        _skillsPathController.text != settingsController.skillsStoragePath) {
      _skillsPathController.text = settingsController.skillsStoragePath;
    }
    if (!_memoryFileFocusNode.hasFocus &&
        _memoryFileController.text != settingsController.userMemoryFilePath) {
      _memoryFileController.text = settingsController.userMemoryFilePath;
    }
    final compressionThresholdText =
        '${settingsController.aiMessageCompressionThresholdChars}';
    if (!_compressionThresholdFocusNode.hasFocus &&
        _compressionThresholdController.text != compressionThresholdText) {
      _compressionThresholdController.text = compressionThresholdText;
    }
    final toolCallLimitText =
        '${settingsController.aiSingleRoundToolCallLimit}';
    if (!_toolCallLimitFocusNode.hasFocus &&
        _toolCallLimitController.text != toolCallLimitText) {
      _toolCallLimitController.text = toolCallLimitText;
    }
    final sequentialToolRoundLimitText =
        '${settingsController.aiSequentialToolRoundLimit}';
    if (!_sequentialToolRoundLimitFocusNode.hasFocus &&
        _sequentialToolRoundLimitController.text !=
            sequentialToolRoundLimitText) {
      _sequentialToolRoundLimitController.text = sequentialToolRoundLimitText;
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PaneHeader(
              title: l10n.settingsTitle,
              subtitle: l10n.settingsSubtitle,
            ),
            if (settingsController.persistenceIssue != null) ...[
              const SizedBox(height: 18),
              _SettingsPersistenceIssueCard(
                issue: settingsController.persistenceIssue!,
                onDismiss: settingsController.clearPersistenceIssue,
              ),
            ],
            const SizedBox(height: 24),
            _SettingsGroupCard(
              title: l10n.settingsCategoryGeneral,
              description: l10n.settingsGeneralSubtitle,
              children: [
                _ResponsiveSettingRow(
                  title: l10n.themeSectionTitle,
                  subtitle: l10n.themeSectionBody,
                  controlMaxWidth: 440,
                  control: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          icon: const Icon(Icons.contrast_outlined),
                          label: Text(l10n.themeSystem, softWrap: false),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          icon: const Icon(Icons.light_mode_outlined),
                          label: Text(l10n.themeLight, softWrap: false),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          icon: const Icon(Icons.dark_mode_outlined),
                          label: Text(l10n.themeDark, softWrap: false),
                        ),
                      ],
                      selected: <ThemeMode>{settingsController.themeMode},
                      onSelectionChanged: (selection) async {
                        if (selection.isEmpty) {
                          return;
                        }
                        final saved = await settingsController.updateThemeMode(
                          selection.first,
                        );
                        if (!context.mounted || saved) {
                          return;
                        }
                        _showPersistenceFailureSnackBar(context);
                      },
                    ),
                  ),
                ),
                _ResponsiveSettingRow(
                  title: l10n.themePaletteSectionTitle,
                  subtitle: l10n.themePaletteSectionBody,
                  controlMaxWidth: 440,
                  control: SizedBox(
                    width: double.infinity,
                    child: DropdownButtonFormField<OpenHandThemePreset>(
                      initialValue: settingsController.themePreset,
                      decoration: InputDecoration(
                        prefixIcon: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: 12,
                            end: 8,
                          ),
                          child: _ThemePresetSwatch(
                            color: settingsController.themePreset.seedColor,
                          ),
                        ),
                      ),
                      items: OpenHandThemePreset.values
                          .map(
                            (preset) => DropdownMenuItem<OpenHandThemePreset>(
                              value: preset,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ThemePresetSwatch(color: preset.seedColor),
                                  const SizedBox(width: 12),
                                  Text(preset.label(l10n)),
                                ],
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) async {
                        if (value == null) {
                          return;
                        }
                        final saved = await settingsController
                            .updateThemePreset(value);
                        if (!context.mounted || saved) {
                          return;
                        }
                        _showPersistenceFailureSnackBar(context);
                      },
                    ),
                  ),
                ),
                _ResponsiveSettingRow(
                  title: l10n.languageSectionTitle,
                  subtitle: l10n.languageSectionBody,
                  controlMaxWidth: 440,
                  control: SizedBox(
                    width: double.infinity,
                    child: DropdownButtonFormField<AppLanguage>(
                      initialValue: settingsController.language,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.translate_outlined),
                      ),
                      items: AppLanguage.values
                          .map(
                            (language) => DropdownMenuItem<AppLanguage>(
                              value: language,
                              child: Text(language.label(l10n)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) async {
                        if (value == null) {
                          return;
                        }
                        final saved = await settingsController.updateLanguage(
                          value,
                        );
                        if (!context.mounted || saved) {
                          return;
                        }
                        _showPersistenceFailureSnackBar(context);
                      },
                    ),
                  ),
                ),
                _DialogAnimationSettingsSection(
                  settingsController: settingsController,
                ),
                _MenuAnimationSettingsSection(
                  settingsController: settingsController,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsGroupCard(
              title: _localizedText(context, zh: '快捷键', en: 'Shortcuts'),
              description: _localizedText(
                context,
                zh: '为常用操作配置组合键。当前最多支持同时按下 4 个按键。',
                en: 'Configure key combinations for common actions. OpenHand currently supports up to four simultaneous keys.',
              ),
              children: [_buildShortcutsSection(context, settingsController)],
            ),
            const SizedBox(height: 18),
            _SettingsGroupCard(
              title: l10n.settingsCategoryAi,
              description: l10n.settingsAiSubtitle,
              children: [_buildAiModelsSection(context, settingsController)],
            ),
            const SizedBox(height: 18),
            _SettingsGroupCard(
              title: l10n.mcpSectionTitle,
              description: l10n.mcpSectionBody,
              children: [_buildMcpSettingsSection(context, settingsController)],
            ),
            const SizedBox(height: 18),
            _SettingsGroupCard(
              title: l10n.settingsCategorySkills,
              description: l10n.settingsSkillsSubtitle,
              children: [_buildSkillsSection(context, settingsController)],
            ),
            const SizedBox(height: 18),
            _SettingsGroupCard(
              title: l10n.settingsCategoryMemory,
              description: l10n.settingsMemorySubtitle,
              children: [_buildMemorySection(context, settingsController)],
            ),
            const SizedBox(height: 18),
            _SettingsGroupCard(
              title: l10n.aboutSectionTitle,
              description: l10n.aboutSectionBody,
              children: [
                _ReadonlySettingRow(
                  label: l10n.aboutVersion,
                  value: appInfo.version,
                ),
                _ReadonlySettingRow(
                  label: l10n.aboutBuild,
                  value: appInfo.buildNumber,
                ),
                _ReadonlySettingRow(
                  label: l10n.aboutPackage,
                  value: appInfo.packageName,
                ),
                _ReadonlySettingRow(
                  label: l10n.aboutPlatforms,
                  value: l10n.aboutPlatformsValue,
                ),
                _ReadonlySettingRow(
                  label: l10n.settingsFilePathLabel,
                  value: settingsController.displaySettingsFilePath,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiModelsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final aiModels = settingsController.aiModels;
    final compressionControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsCompressionThresholdField'),
          controller: _compressionThresholdController,
          focusNode: _compressionThresholdFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiCompressionThresholdLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiMessageCompressionThresholdChars}',
          ),
          onSubmitted: (value) => _saveCompressionThreshold(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsCompressionThresholdSaveButton',
            ),
            onPressed: () => _saveCompressionThreshold(
              context,
              _compressionThresholdController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiCompressionThresholdSave),
          ),
        ),
      ],
    );
    final toolCallLimitControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsToolCallLimitField'),
          controller: _toolCallLimitController,
          focusNode: _toolCallLimitFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: _localizedText(
              context,
              zh: '单轮工具调用上限',
              en: 'Per-Response Tool Call Limit',
            ),
            hintText:
                '${AppSettingsSnapshot.defaultAiSingleRoundToolCallLimit}',
          ),
          onSubmitted: (value) => _saveToolCallLimit(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>('settingsToolCallLimitSaveButton'),
            onPressed: () =>
                _saveToolCallLimit(context, _toolCallLimitController.text),
            icon: const Icon(Icons.save_outlined),
            label: Text(_localizedText(context, zh: '保存上限', en: 'Save Limit')),
          ),
        ),
      ],
    );
    final sequentialToolRoundLimitControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsSequentialToolRoundLimitField'),
          controller: _sequentialToolRoundLimitController,
          focusNode: _sequentialToolRoundLimitFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: _localizedText(
              context,
              zh: '连续工具轮次上限',
              en: 'Sequential Tool Round Limit',
            ),
            hintText:
                '${AppSettingsSnapshot.defaultAiSequentialToolRoundLimit}',
          ),
          onSubmitted: (value) => _saveSequentialToolRoundLimit(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsSequentialToolRoundLimitSaveButton',
            ),
            onPressed: () => _saveSequentialToolRoundLimit(
              context,
              _sequentialToolRoundLimitController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(_localizedText(context, zh: '保存上限', en: 'Save Limit')),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSubsectionCard(
          title: _localizedText(context, zh: '模型提供商管理', en: 'Model Provider Management'),
          description: _localizedText(
            context,
            zh: '新增、选择、测试并维护当前可用的模型提供商配置。每个提供商可包含多个模型。',
            en: 'Add, select, test, and maintain model provider configurations. Each provider can serve multiple models.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.icon(
                onPressed: () => _showAiModelDialog(context),
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.aiModelAdd),
              ),
              const SizedBox(height: 16),
              if (aiModels.isEmpty)
                _SettingsStateBox(
                  icon: Icons.hub_outlined,
                  title: l10n.aiModelsEmptyTitle,
                  body: l10n.aiModelsEmptyBody,
                )
              else
                Column(
                  children: [
                    for (var index = 0; index < aiModels.length; index++) ...[
                      _AiModelTile(
                        model: aiModels[index],
                        isSelected:
                            settingsController.selectedAiModelId ==
                            aiModels[index].id,
                        isTesting: _testingAiModelIds.contains(
                          aiModels[index].id,
                        ),
                        isFirst: index == 0,
                        isLast: index == aiModels.length - 1,
                        onSelect: () => settingsController
                            .updateSelectedAiModel(aiModels[index].id),
                        onTest: () => _testAiModel(aiModels[index]),
                        onEdit: () => _showAiModelDialog(
                          context,
                          initialModel: aiModels[index],
                        ),
                        onMoveUp: () =>
                            settingsController.moveAiModel(index, index - 1),
                        onMoveDown: () =>
                            settingsController.moveAiModel(index, index + 1),
                        onDelete: () =>
                            _confirmDeleteAiModel(context, aiModels[index]),
                      ),
                      if (index != aiModels.length - 1)
                        const SizedBox(height: 14),
                    ],
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSubsectionCard(
          title: l10n.aiCompressionThresholdLabel,
          description: l10n.aiCompressionThresholdBody,
          child: Column(
            children: [
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '压缩触发阈值',
                  en: 'Compression Trigger',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '当线程中尚未被压缩的历史消息字符总数超过这个值时，系统会生成新的摘要检查点。',
                  en: 'Once the uncompressed history in a thread exceeds this value, OpenHand creates a new summary checkpoint.',
                ),
                control: compressionControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '单轮工具调用上限',
                  en: 'Per-Response Tool Call Limit',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '默认 40 次。一次人机对话响应过程中，如果工具调用总次数超过这个阈值，系统会追加警告消息并安全终止本轮响应。',
                  en: 'Defaults to 40. If one assistant response exceeds this many tool calls, OpenHand posts a warning message and stops the round safely.',
                ),
                control: toolCallLimitControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '连续工具轮次上限',
                  en: 'Sequential Tool Round Limit',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '默认 24 轮。一次会话中，如果助手在工具执行后又连续请求下一轮工具，达到这个轮次数时系统会安全停止，避免陷入无限工具回环。',
                  en: 'Defaults to 24 rounds. If the assistant keeps requesting another tool round after each execution, OpenHand stops once this round limit is reached to prevent runaway tool loops.',
                ),
                control: sequentialToolRoundLimitControl,
                controlMaxWidth: 360,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSubsectionCard(
          title: _localizedText(context, zh: '命令安全', en: 'Command Safety'),
          description: _localizedText(
            context,
            zh: '控制 bash 工具是否需要写命令确认，并集中管理禁止命令规则。',
            en: 'Control write-command confirmation for bash and manage deny rules in one place.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '写命令确认',
                  en: 'Write Command Confirmation',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '默认开启。AI 调用 bash 工具执行可能修改文件或系统状态的命令时，会先弹窗等待你确认。',
                  en: 'Enabled by default. When the AI tries to run a write-like bash command, OpenHand will ask for your confirmation first.',
                ),
                control: Switch(
                  value: settingsController.aiWriteCommandConfirmationEnabled,
                  onChanged: (value) async {
                    final saved = await settingsController
                        .updateAiWriteCommandConfirmationEnabled(value);
                    if (!context.mounted || saved) {
                      return;
                    }
                    _showPersistenceFailureSnackBar(context);
                  },
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _localizedText(context, zh: '允许命令列表', en: 'Allow Command List'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _localizedText(
                  context,
                  zh: '匹配到的写类 bash 命令会跳过确认弹窗直接执行。只适合长期明确放行的稳定命令模式。',
                  en: 'Matching write-like bash commands skip the confirmation dialog and run immediately. Only use this for stable command patterns you explicitly trust.',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _showAllowCommandRuleDialog(context),
                icon: const Icon(Icons.verified_outlined),
                label: Text(
                  _localizedText(context, zh: '新增允许规则', en: 'Add Allow Rule'),
                ),
              ),
              const SizedBox(height: 16),
              if (settingsController.aiAllowCommandRules.isEmpty)
                _SettingsStateBox(
                  icon: Icons.verified_user_outlined,
                  title: _localizedText(
                    context,
                    zh: '当前没有允许命令规则',
                    en: 'No allow rules configured',
                  ),
                  body: _localizedText(
                    context,
                    zh: '新增规则后，匹配到的写命令将跳过确认弹窗。',
                    en: 'Add a rule to let matching write commands bypass confirmation.',
                  ),
                )
              else
                Column(
                  children: settingsController.aiAllowCommandRules
                      .map(
                        (rule) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AllowCommandRuleTile(
                            rule: rule,
                            onEdit: () => _showAllowCommandRuleDialog(
                              context,
                              initialRule: rule,
                            ),
                            onDelete: () =>
                                _deleteAllowCommandRule(context, rule),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              const SizedBox(height: 18),
              Text(
                _localizedText(context, zh: '禁止命令列表', en: 'Deny Command List'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _localizedText(
                  context,
                  zh: '匹配到的 bash 命令将不会真正执行，而是把“被用户禁止”这一结果直接返回给模型。支持正则和简单通配写法，例如 `rm *`。',
                  en: 'Matching bash commands are blocked before execution and the denial result is returned to the model instead. Supports regex and simple wildcard patterns such as `rm *`.',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _showDenyCommandRuleDialog(context),
                icon: const Icon(Icons.block_rounded),
                label: Text(
                  _localizedText(context, zh: '新增规则', en: 'Add Rule'),
                ),
              ),
              const SizedBox(height: 16),
              if (settingsController.aiDenyCommandRules.isEmpty)
                _SettingsStateBox(
                  icon: Icons.rule_folder_outlined,
                  title: _localizedText(
                    context,
                    zh: '当前没有禁止命令规则',
                    en: 'No deny rules configured',
                  ),
                  body: _localizedText(
                    context,
                    zh: '新增规则后，匹配到的 bash 命令会被直接拦截。',
                    en: 'Add a rule to block matching bash commands before they run.',
                  ),
                )
              else
                Column(
                  children: settingsController.aiDenyCommandRules
                      .map(
                        (rule) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DenyCommandRuleTile(
                            rule: rule,
                            onEdit: () => _showDenyCommandRuleDialog(
                              context,
                              initialRule: rule,
                            ),
                            onDelete: () =>
                                _deleteDenyCommandRule(context, rule),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final bindings = settingsController.shortcutBindings;
    return _SettingsSubsectionCard(
      title: _localizedText(context, zh: '快捷键绑定', en: 'Shortcut Bindings'),
      description: _localizedText(
        context,
        zh: '点击录制后，按下新的组合键即可更新绑定。模型切换和会话切换会自动绕圈循环。',
        en: 'Click record, then press the new key combination to update a binding. Model and session switching wrap around automatically.',
      ),
      child: Column(
        children: OpenHandShortcutAction.values
            .map(
              (action) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ShortcutBindingTile(
                  actionStorageKey: openHandShortcutActionStorageKey(action),
                  title: _shortcutActionTitle(context, action),
                  subtitle: _shortcutActionSubtitle(context, action),
                  value: formatShortcutLabel(bindings[action] ?? const <int>[]),
                  onRecord: () => _showShortcutRecorderDialog(context, action),
                  onReset: () async {
                    final saved = await settingsController.resetShortcutBinding(
                      action,
                    );
                    if (!context.mounted || saved) {
                      return;
                    }
                    _showPersistenceFailureSnackBar(context);
                  },
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildSkillsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsSkillsPathField'),
          controller: _skillsPathController,
          focusNode: _skillsPathFocusNode,
          decoration: InputDecoration(
            labelText: l10n.skillsStorageCurrentPath,
            hintText: settingsController.defaultSkillsStorageLabel,
          ),
          onSubmitted: (value) => _saveSkillsPath(context, value),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.skillsStorageSectionBody,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              key: const ValueKey<String>('settingsSkillsSaveButton'),
              onPressed: () =>
                  _saveSkillsPath(context, _skillsPathController.text),
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.skillsStorageSave),
            ),
            OutlinedButton.icon(
              onPressed: () => _browseSkillsDirectory(context),
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(l10n.skillsStorageBrowse),
            ),
            OutlinedButton.icon(
              onPressed: () => _openSkillsDirectory(context),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(l10n.skillsStorageOpen),
            ),
            OutlinedButton.icon(
              onPressed: () => _resetSkillsPath(context),
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(l10n.skillsStorageReset),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _ReadonlySettingRow(
          label: l10n.skillsStorageCurrentPath,
          value: settingsController.displaySkillsStoragePath,
        ),
        _ReadonlySettingRow(
          label: l10n.skillsStorageDefaultPath,
          value: settingsController.defaultSkillsStorageLabel,
        ),
      ],
    );
  }

  Widget _buildMemorySection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResponsiveSettingRow(
          title: l10n.memoryEnabledLabel,
          subtitle: l10n.memoryEnabledBody,
          control: Switch(
            value: settingsController.memoryEnabled,
            onChanged: (value) async {
              final saved = await settingsController.updateMemoryEnabled(value);
              if (!context.mounted || saved) {
                return;
              }
              _showPersistenceFailureSnackBar(context);
            },
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey<String>('settingsMemoryFileField'),
          controller: _memoryFileController,
          focusNode: _memoryFileFocusNode,
          decoration: InputDecoration(
            labelText: l10n.userMemoryFileLabel,
            hintText: settingsController.defaultUserMemoryFileLabel,
          ),
          onSubmitted: (value) => _saveMemoryFilePath(context, value),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.memoryFileBody,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              key: const ValueKey<String>('settingsMemorySaveButton'),
              onPressed: () =>
                  _saveMemoryFilePath(context, _memoryFileController.text),
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.memoryFileSave),
            ),
            OutlinedButton.icon(
              onPressed: () => _browseMemoryFilePath(context),
              icon: const Icon(Icons.edit_note_outlined),
              label: Text(l10n.memoryFileBrowse),
            ),
            OutlinedButton.icon(
              onPressed: () => _openMemoryDirectory(context),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(l10n.memoryOpenDirectory),
            ),
            OutlinedButton.icon(
              onPressed: () => _resetMemoryFilePath(context),
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(l10n.memoryFileReset),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _ReadonlySettingRow(
          label: l10n.userMemoryFileLabel,
          value: settingsController.displayUserMemoryFilePath,
        ),
        _ReadonlySettingRow(
          label: l10n.memoryFileDefaultPath,
          value: settingsController.defaultUserMemoryFileLabel,
        ),
      ],
    );
  }

  Widget _buildMcpSettingsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResponsiveSettingRow(
          title: l10n.mcpEnabledLabel,
          subtitle: l10n.mcpEnabledBody,
          control: Switch(
            value: settingsController.mcpEnabled,
            onChanged: (value) async {
              final saved = await settingsController.updateMcpEnabled(value);
              if (!context.mounted || saved) {
                return;
              }
              _showPersistenceFailureSnackBar(context);
            },
          ),
        ),
        const SizedBox(height: 14),
        _ReadonlySettingRow(
          label: l10n.mcpFilePathLabel,
          value: settingsController.displayMcpServersFilePath,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () => _openMcpDirectory(context),
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(l10n.mcpOpenDirectory),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _saveSkillsPath(BuildContext context, String rawPath) async {
    final l10n = AppLocalizations.of(context)!;
    final settingsController = context.read<SettingsController>();
    final skillsController = context.read<SkillsController>();
    await _saveReloadablePathSetting(
      context: context,
      fieldController: _skillsPathController,
      rawPath: rawPath,
      currentPath: (controller) => controller.skillsStoragePath,
      saveSetting: settingsController.updateSkillsStoragePath,
      reloadRuntime: skillsController.reloadFromPath,
      restoreSetting: (previousPath) => _restoreSkillsPath(
        settingsController,
        skillsController,
        previousPath,
      ),
      successMessage: l10n.skillsPathSaved,
      failureMessage: l10n.skillOperationFailed,
    );
  }

  Future<void> _browseSkillsDirectory(BuildContext context) async {
    final selectedPath = await getDirectoryPath();
    if (!context.mounted || selectedPath == null || selectedPath.isEmpty) {
      return;
    }
    _skillsPathController.text = selectedPath;
    await _saveSkillsPath(context, selectedPath);
  }

  Future<void> _openSkillsDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<SkillsController>().openStorageDirectory();
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.skillOperationFailed);
    }
  }

  Future<void> _resetSkillsPath(BuildContext context) async {
    final defaultPath = context
        .read<SettingsController>()
        .defaultSkillsStoragePath;
    _skillsPathController.text = defaultPath;
    await _saveSkillsPath(context, defaultPath);
  }

  Future<void> _saveMemoryFilePath(BuildContext context, String rawPath) async {
    final l10n = AppLocalizations.of(context)!;
    final settingsController = context.read<SettingsController>();
    final memoryController = context.read<MemoryController>();
    await _saveReloadablePathSetting(
      context: context,
      fieldController: _memoryFileController,
      rawPath: rawPath,
      currentPath: (controller) => controller.userMemoryFilePath,
      saveSetting: settingsController.updateUserMemoryFilePath,
      reloadRuntime: memoryController.reloadFromFilePath,
      restoreSetting: (previousPath) => _restoreMemoryFilePath(
        settingsController,
        memoryController,
        previousPath,
      ),
      successMessage: l10n.memoryPathSaved,
      failureMessage: l10n.memoryOperationFailed,
    );
  }

  Future<void> _saveReloadablePathSetting({
    required BuildContext context,
    required TextEditingController fieldController,
    required String rawPath,
    required _SettingsPathGetter currentPath,
    required _SettingsPathOperation saveSetting,
    required _SettingsPathOperation reloadRuntime,
    required _SettingsPathOperation restoreSetting,
    required String successMessage,
    required String failureMessage,
  }) async {
    final settingsController = context.read<SettingsController>();
    final previousPath = currentPath(settingsController);
    try {
      final saved = await saveSetting(rawPath);
      if (!saved) {
        if (!context.mounted) {
          return;
        }
        fieldController.text = currentPath(settingsController);
        _showPersistenceFailureSnackBar(context);
        return;
      }
      final reloaded = await reloadRuntime(currentPath(settingsController));
      if (!reloaded) {
        final rolledBack = await restoreSetting(previousPath);
        if (!context.mounted) {
          return;
        }
        fieldController.text = currentPath(settingsController);
        if (!rolledBack && settingsController.persistenceIssue != null) {
          _showPersistenceFailureSnackBar(context);
          return;
        }
        _showSnackBar(context, failureMessage);
        return;
      }
      if (!context.mounted) {
        return;
      }
      fieldController.text = currentPath(settingsController);
      _showSnackBar(context, successMessage);
    } catch (_) {
      final rolledBack = await restoreSetting(previousPath);
      if (!context.mounted) {
        return;
      }
      fieldController.text = currentPath(settingsController);
      if (!rolledBack && settingsController.persistenceIssue != null) {
        _showPersistenceFailureSnackBar(context);
        return;
      }
      _showSnackBar(context, failureMessage);
    }
  }

  Future<bool> _restoreSkillsPath(
    SettingsController settingsController,
    SkillsController skillsController,
    String previousPath,
  ) async {
    if (settingsController.skillsStoragePath != previousPath) {
      final restored = await settingsController.updateSkillsStoragePath(
        previousPath,
      );
      if (!restored) {
        return false;
      }
    }
    return skillsController.reloadFromPath(previousPath);
  }

  Future<bool> _restoreMemoryFilePath(
    SettingsController settingsController,
    MemoryController memoryController,
    String previousPath,
  ) async {
    if (settingsController.userMemoryFilePath != previousPath) {
      final restored = await settingsController.updateUserMemoryFilePath(
        previousPath,
      );
      if (!restored) {
        return false;
      }
    }
    return memoryController.reloadFromFilePath(previousPath);
  }

  Future<void> _saveCompressionThreshold(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue <= 0) {
      _showSnackBar(context, l10n.aiCompressionThresholdInvalid);
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiMessageCompressionThresholdChars(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _compressionThresholdController.text =
          '${context.read<SettingsController>().aiMessageCompressionThresholdChars}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _compressionThresholdController.text = '$parsedValue';
    _showSnackBar(context, l10n.aiCompressionThresholdSaved);
  }

  Future<void> _saveToolCallLimit(BuildContext context, String rawValue) async {
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue <= 0) {
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '请输入大于 0 的工具调用上限。',
          en: 'Enter a tool call limit greater than 0.',
        ),
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiSingleRoundToolCallLimit(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _toolCallLimitController.text =
          '${context.read<SettingsController>().aiSingleRoundToolCallLimit}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _toolCallLimitController.text = '$parsedValue';
    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: '单轮工具调用上限已保存。',
        en: 'The per-response tool call limit has been saved.',
      ),
    );
  }

  Future<void> _saveSequentialToolRoundLimit(
    BuildContext context,
    String rawValue,
  ) async {
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue <= 0) {
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '请输入大于 0 的连续工具轮次上限。',
          en: 'Enter a sequential tool round limit greater than 0.',
        ),
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiSequentialToolRoundLimit(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _sequentialToolRoundLimitController.text =
          '${context.read<SettingsController>().aiSequentialToolRoundLimit}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _sequentialToolRoundLimitController.text = '$parsedValue';
    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: '连续工具轮次上限已保存。',
        en: 'The sequential tool round limit has been saved.',
      ),
    );
  }

  Future<void> _showDenyCommandRuleDialog(
    BuildContext context, {
    AiDenyCommandRule? initialRule,
  }) async {
    final settingsController = context.read<SettingsController>();
    final submittedRule = await showAnimatedDialog<AiDenyCommandRule>(
      context: context,
      builder: (dialogContext) {
        return _DenyCommandRuleDialog(
          initialRule: initialRule,
          draftRuleId:
              initialRule?.id ?? settingsController.createAiDenyCommandRuleId(),
        );
      },
    );
    if (!context.mounted || submittedRule == null) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) {
      return;
    }
    final saved = initialRule == null
        ? await settingsController.addAiDenyCommandRule(submittedRule)
        : await settingsController.updateAiDenyCommandRule(submittedRule);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: initialRule == null ? '禁止命令规则已新增。' : '禁止命令规则已更新。',
        en: initialRule == null
            ? 'The deny command rule has been added.'
            : 'The deny command rule has been updated.',
      ),
    );
  }

  Future<void> _deleteDenyCommandRule(
    BuildContext context,
    AiDenyCommandRule rule,
  ) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _localizedText(context, zh: '删除禁止命令规则', en: 'Delete Deny Rule'),
          ),
          content: Text(rule.pattern),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: AppLocalizations.of(context)!.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: AppLocalizations.of(context)!.commonDelete,
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final deleted = await context
        .read<SettingsController>()
        .deleteAiDenyCommandRule(rule.id);
    if (!context.mounted) {
      return;
    }
    if (!deleted) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: '禁止命令规则已删除。',
        en: 'The deny command rule has been deleted.',
      ),
    );
  }

  Future<void> _showAllowCommandRuleDialog(
    BuildContext context, {
    AiAllowCommandRule? initialRule,
  }) async {
    final settingsController = context.read<SettingsController>();
    final submittedRule = await showAnimatedDialog<AiAllowCommandRule>(
      context: context,
      builder: (dialogContext) {
        return _AllowCommandRuleDialog(
          initialRule: initialRule,
          draftRuleId:
              initialRule?.id ??
              settingsController.createAiAllowCommandRuleId(),
        );
      },
    );
    if (!context.mounted || submittedRule == null) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) {
      return;
    }
    final saved = initialRule == null
        ? await settingsController.addAiAllowCommandRule(submittedRule)
        : await settingsController.updateAiAllowCommandRule(submittedRule);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: initialRule == null ? '允许命令规则已新增。' : '允许命令规则已更新。',
        en: initialRule == null
            ? 'The allow command rule has been added.'
            : 'The allow command rule has been updated.',
      ),
    );
  }

  Future<void> _deleteAllowCommandRule(
    BuildContext context,
    AiAllowCommandRule rule,
  ) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _localizedText(context, zh: '删除允许命令规则', en: 'Delete Allow Rule'),
          ),
          content: Text(rule.pattern),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: AppLocalizations.of(context)!.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: AppLocalizations.of(context)!.commonDelete,
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final deleted = await context
        .read<SettingsController>()
        .deleteAiAllowCommandRule(rule.id);
    if (!context.mounted) {
      return;
    }
    if (!deleted) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: '允许命令规则已删除。',
        en: 'The allow command rule has been deleted.',
      ),
    );
  }

  Future<void> _browseMemoryFilePath(BuildContext context) async {
    final settingsController = context.read<SettingsController>();
    final selectedLocation = await getSaveLocation(
      initialDirectory: p.dirname(settingsController.userMemoryFilePath),
      suggestedName: OpenHandPaths.basename(
        settingsController.userMemoryFilePath,
      ),
    );
    final selectedPath = selectedLocation?.path;
    if (!context.mounted || selectedPath == null || selectedPath.isEmpty) {
      return;
    }
    _memoryFileController.text = selectedPath;
    await _saveMemoryFilePath(context, selectedPath);
  }

  Future<void> _openMemoryDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<MemoryController>().openStorageDirectory();
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.memoryOperationFailed);
    }
  }

  Future<void> _resetMemoryFilePath(BuildContext context) async {
    final defaultPath = context
        .read<SettingsController>()
        .defaultUserMemoryFilePath;
    _memoryFileController.text = defaultPath;
    await _saveMemoryFilePath(context, defaultPath);
  }

  Future<void> _openMcpDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<McpController>().openStorageDirectory();
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.mcpOperationFailed);
    }
  }

  Future<void> _showAiModelDialog(
    BuildContext context, {
    AiModelConfig? initialModel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final submitted = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _AiModelEditorDialog(initialModel: initialModel);
      },
    );

    if (!context.mounted || submitted != true) {
      return;
    }
    _showSnackBar(context, l10n.aiModelSaveSuccess);
  }

  Future<void> _testAiModel(AiModelConfig model) async {
    if (_testingAiModelIds.contains(model.id)) {
      return;
    }
    setState(() {
      _testingAiModelIds.add(model.id);
    });
    final service = AiChatService();
    try {
      await service.testModel(model);
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context)!;
      _showSnackBar(context, l10n.aiModelTestSuccess(model.providerLabel));
    } on AiChatException catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context)!;
      _showSnackBar(
        context,
        l10n.aiModelTestFailure(
          model.providerLabel,
          _normalizeAiModelTestMessage(error.message, l10n.chatRequestFailed),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context)!;
      _showSnackBar(
        context,
        l10n.aiModelTestFailure(
          model.providerLabel,
          _normalizeAiModelTestMessage('$error', l10n.chatRequestFailed),
        ),
      );
    } finally {
      service.dispose();
      if (mounted) {
        setState(() {
          _testingAiModelIds.remove(model.id);
        });
      }
    }
  }

  Future<void> _confirmDeleteAiModel(
    BuildContext context,
    AiModelConfig model,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.aiModelDeleteConfirmTitle),
          content: Text(
            '${l10n.aiModelDeleteConfirmBody}\n\n${model.providerLabel}',
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: l10n.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: l10n.commonDelete,
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final deleted = await context.read<SettingsController>().deleteAiModel(
      model.id,
    );
    if (!context.mounted) {
      return;
    }
    if (!deleted) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _showSnackBar(context, l10n.aiModelDeleteSuccess);
  }

  void _showPersistenceFailureSnackBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _showSnackBar(context, l10n.settingsPersistenceSaveFailedBody);
  }

  String _normalizeAiModelTestMessage(String raw, String fallback) {
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? fallback : normalized;
  }

  Future<void> _showShortcutRecorderDialog(
    BuildContext context,
    OpenHandShortcutAction action,
  ) async {
    final settingsController = context.read<SettingsController>();
    final shortcutBinding = await showAnimatedDialog<List<int>>(
      context: context,
      builder: (dialogContext) {
        return _ShortcutRecorderDialog(
          title: _shortcutActionTitle(dialogContext, action),
          initialKeyIds:
              settingsController.shortcutBindings[action] ?? const <int>[],
        );
      },
    );
    if (!context.mounted || shortcutBinding == null) {
      return;
    }
    final saved = await settingsController.updateShortcutBinding(
      action,
      shortcutBinding,
    );
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: '快捷键已更新。',
        en: 'The shortcut has been updated.',
      ),
    );
  }

  String _shortcutActionTitle(
    BuildContext context,
    OpenHandShortcutAction action,
  ) {
    return switch (action) {
      OpenHandShortcutAction.sendMessage => _localizedText(
        context,
        zh: '发送消息',
        en: 'Send Message',
      ),
      OpenHandShortcutAction.toggleComposer => _localizedText(
        context,
        zh: '折叠或展开输入框',
        en: 'Collapse or Expand Composer',
      ),
      OpenHandShortcutAction.selectPreviousModel => _localizedText(
        context,
        zh: '上一个模型',
        en: 'Previous Model',
      ),
      OpenHandShortcutAction.selectNextModel => _localizedText(
        context,
        zh: '下一个模型',
        en: 'Next Model',
      ),
      OpenHandShortcutAction.toggleAutoFollow => _localizedText(
        context,
        zh: '开关自动滚动',
        en: 'Toggle Auto Follow',
      ),
      OpenHandShortcutAction.selectPreviousSession => _localizedText(
        context,
        zh: '上一个会话',
        en: 'Previous Session',
      ),
      OpenHandShortcutAction.selectNextSession => _localizedText(
        context,
        zh: '下一个会话',
        en: 'Next Session',
      ),
    };
  }

  String _shortcutActionSubtitle(
    BuildContext context,
    OpenHandShortcutAction action,
  ) {
    return switch (action) {
      OpenHandShortcutAction.sendMessage => _localizedText(
        context,
        zh: '默认 Ctrl + Enter，仅在聊天输入框准备好时触发发送按钮。',
        en: 'Defaults to Ctrl + Enter and triggers the send button when the chat composer is ready.',
      ),
      OpenHandShortcutAction.toggleComposer => _localizedText(
        context,
        zh: '默认 Ctrl + P，用于快速折叠或展开输入框。',
        en: 'Defaults to Ctrl + P for quickly collapsing or expanding the composer.',
      ),
      OpenHandShortcutAction.selectPreviousModel => _localizedText(
        context,
        zh: '默认 Ctrl + ←，向前切换模型，切到头后自动绕回末尾。',
        en: 'Defaults to Ctrl + Left and wraps around to the last model when needed.',
      ),
      OpenHandShortcutAction.selectNextModel => _localizedText(
        context,
        zh: '默认 Ctrl + →，向后切换模型，切到末尾后自动绕回开头。',
        en: 'Defaults to Ctrl + Right and wraps around to the first model when needed.',
      ),
      OpenHandShortcutAction.toggleAutoFollow => _localizedText(
        context,
        zh: '默认 Ctrl + S，开关自动滚动模式。',
        en: 'Defaults to Ctrl + S for toggling auto follow.',
      ),
      OpenHandShortcutAction.selectPreviousSession => _localizedText(
        context,
        zh: '默认 Ctrl + ↑，切换到上一个会话并支持绕圈。',
        en: 'Defaults to Ctrl + Up and wraps to the end of the session list.',
      ),
      OpenHandShortcutAction.selectNextSession => _localizedText(
        context,
        zh: '默认 Ctrl + ↓，切换到下一个会话并支持绕圈。',
        en: 'Defaults to Ctrl + Down and wraps to the start of the session list.',
      ),
    };
  }

  void _showSnackBar(BuildContext context, String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  String _localizedText(
    BuildContext context, {
    required String zh,
    required String en,
  }) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode.startsWith('zh') ? zh : en;
  }
}

class _AiModelEditorDialog extends StatefulWidget {
  const _AiModelEditorDialog({this.initialModel});

  final AiModelConfig? initialModel;

  @override
  State<_AiModelEditorDialog> createState() => _AiModelEditorDialogState();
}

class _AiModelEditorDialogState extends State<_AiModelEditorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenController;
  late final TextEditingController _modelIdController;
  late final TextEditingController _maxContextTokensController;
  late final TextEditingController _manualModelIdController;
  late AiAuthScheme _authScheme;
  late AiProtocolType _protocolType;
  bool _obscureToken = true;
  bool _isSaving = false;
  bool _isScanning = false;
  String? _errorMessage;
  String? _scanError;
  List<String> _availableModelIds = const <String>[];
  String? _activeModelId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialModel?.name ?? '',
    );
    _baseUrlController = TextEditingController(
      text: widget.initialModel?.baseUrl ?? '',
    );
    _tokenController = TextEditingController(
      text: widget.initialModel?.token ?? '',
    );
    _modelIdController = TextEditingController(
      text: widget.initialModel?.modelId ?? '',
    );
    _maxContextTokensController = TextEditingController(
      text: widget.initialModel?.maxContextTokens?.toString() ?? '',
    );
    _manualModelIdController = TextEditingController();
    _authScheme = widget.initialModel?.authScheme ?? AiAuthScheme.bearer;
    _protocolType = widget.initialModel?.protocolType ?? AiProtocolType.openai;
    _availableModelIds = List<String>.from(
      widget.initialModel?.availableModelIds ?? const <String>[],
    );
    _activeModelId = widget.initialModel?.modelId.trim().isNotEmpty == true
        ? widget.initialModel!.modelId.trim()
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _tokenController.dispose();
    _modelIdController.dispose();
    _maxContextTokensController.dispose();
    _manualModelIdController.dispose();
    super.dispose();
  }

  String _localizedText({required String zh, required String en}) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode.startsWith('zh') ? zh : en;
  }

  Future<void> _scanModels() async {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty || !isValidHttpUrl(baseUrl)) {
      setState(() {
        _scanError = _localizedText(
          zh: '请先输入有效的 Base URL',
          en: 'Enter a valid Base URL first',
        );
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _scanError = null;
    });

    final scanner = AiModelScanner();
    try {
      final config = AiModelConfig(
        id: '',
        baseUrl: baseUrl,
        authScheme: _authScheme,
        token: _tokenController.text.trim(),
        modelId: '',
        protocolType: _protocolType,
      );
      final result = await scanner.scan(config);
      if (!mounted) return;

      if (result.isSuccess) {
        final merged = <String>{..._availableModelIds, ...result.modelIds};
        final sorted = merged.toList()..sort();
        setState(() {
          _availableModelIds = sorted;
          _isScanning = false;
          _scanError = result.modelIds.isEmpty
              ? _localizedText(
                  zh: '未从该提供商扫描到模型。',
                  en: 'No models found from this provider.',
                )
              : null;
          // Auto-select first model if none currently selected.
          if (_activeModelId == null && sorted.isNotEmpty) {
            _activeModelId = sorted.first;
            _modelIdController.text = sorted.first;
          }
        });
      } else {
        setState(() {
          _isScanning = false;
          _scanError = result.error;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _scanError = '$e';
      });
    } finally {
      scanner.dispose();
    }
  }

  void _addManualModelId() {
    final manualId = _manualModelIdController.text.trim();
    if (manualId.isEmpty) return;
    if (_availableModelIds.contains(manualId)) {
      _manualModelIdController.clear();
      return;
    }
    setState(() {
      _availableModelIds = [..._availableModelIds, manualId]..sort();
      _manualModelIdController.clear();
      // If no model was selected, auto-select this one.
      if (_activeModelId == null) {
        _activeModelId = manualId;
        _modelIdController.text = manualId;
      }
    });
  }

  void _removeModelId(String modelId) {
    setState(() {
      _availableModelIds = _availableModelIds
          .where((id) => id != modelId)
          .toList(growable: false);
      if (_activeModelId == modelId) {
        _activeModelId = _availableModelIds.isNotEmpty
            ? _availableModelIds.first
            : null;
        _modelIdController.text = _activeModelId ?? '';
      }
    });
  }

  void _selectModelId(String modelId) {
    setState(() {
      _activeModelId = modelId;
      _modelIdController.text = modelId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 780),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initialModel == null
                      ? l10n.aiModelDialogCreateTitle
                      : l10n.aiModelDialogEditTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: _localizedText(
                                zh: '提供商名称',
                                en: 'Provider Name',
                              ),
                              hintText: _localizedText(
                                zh: '可选，如 DeepSeek、本地 Ollama',
                                en: 'Optional, e.g. DeepSeek, Local Ollama',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _baseUrlController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: l10n.aiModelBaseUrl,
                            ),
                            validator: (value) {
                              final rawValue = value?.trim() ?? '';
                              if (rawValue.isEmpty) {
                                return l10n.aiModelBaseUrlRequired;
                              }
                              if (!isValidHttpUrl(rawValue)) {
                                return l10n.aiModelBaseUrlInvalid;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final stacked = constraints.maxWidth < 640;
                              final authDropdown =
                                  DropdownButtonFormField<AiAuthScheme>(
                                    initialValue: _authScheme,
                                    decoration: InputDecoration(
                                      labelText: l10n.aiModelAuthScheme,
                                    ),
                                    items: AiAuthScheme.values
                                        .map(
                                          (item) =>
                                              DropdownMenuItem<AiAuthScheme>(
                                                value: item,
                                                child: Text(item.label(l10n)),
                                              ),
                                        )
                                        .toList(growable: false),
                                    onChanged: _isSaving
                                        ? null
                                        : (value) {
                                            if (value == null) {
                                              return;
                                            }
                                            setState(() {
                                              _authScheme = value;
                                            });
                                          },
                                  );
                              final protocolDropdown =
                                  DropdownButtonFormField<AiProtocolType>(
                                    initialValue: _protocolType,
                                    decoration: InputDecoration(
                                      labelText: l10n.aiModelProtocol,
                                    ),
                                    items: AiProtocolType.values
                                        .map(
                                          (item) =>
                                              DropdownMenuItem<AiProtocolType>(
                                                value: item,
                                                child: Text(item.label(l10n)),
                                              ),
                                        )
                                        .toList(growable: false),
                                    onChanged: _isSaving
                                        ? null
                                        : (value) {
                                            if (value == null) {
                                              return;
                                            }
                                            setState(() {
                                              _protocolType = value;
                                            });
                                          },
                                  );
                              if (stacked) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    authDropdown,
                                    const SizedBox(height: 16),
                                    protocolDropdown,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: authDropdown),
                                  const SizedBox(width: 16),
                                  Expanded(child: protocolDropdown),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _tokenController,
                            enabled: !_isSaving,
                            obscureText: _obscureToken,
                            decoration: InputDecoration(
                              labelText: l10n.aiModelToken,
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 56,
                                minHeight: 40,
                              ),
                              suffixIcon: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 10,
                                ),
                                child: IconButton(
                                  onPressed: _isSaving
                                      ? null
                                      : () {
                                          setState(() {
                                            _obscureToken = !_obscureToken;
                                          });
                                        },
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor:
                                        colorScheme.onSurfaceVariant,
                                    disabledForegroundColor: colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.38),
                                    minimumSize: const Size(36, 36),
                                    maximumSize: const Size(36, 36),
                                    padding: EdgeInsets.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: Icon(
                                    _obscureToken
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // ── Model scan section ──
                          Row(
                            children: [
                              Text(
                                l10n.aiModelAvailableModels,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(width: 12),
                              if (_isScanning)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                FilledButton.tonalIcon(
                                  onPressed: _isSaving ? null : _scanModels,
                                  icon: const Icon(
                                    Icons.radar_rounded,
                                    size: 18,
                                  ),
                                  label: Text(l10n.aiModelScanButton),
                                ),
                              if (_isScanning) ...[
                                const SizedBox(width: 8),
                                Text(
                                  l10n.aiModelScanning,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ],
                          ),
                          if (_scanError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _scanError!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 12),
                          // Available models chip list
                          if (_availableModelIds.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 160),
                              child: SingleChildScrollView(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: _availableModelIds
                                      .map(
                                        (id) => InputChip(
                                          label: Text(id),
                                          selected: id == _activeModelId,
                                          onSelected: _isSaving
                                              ? null
                                              : (_) => _selectModelId(id),
                                          onDeleted: _isSaving
                                              ? null
                                              : () => _removeModelId(id),
                                          deleteIcon: const Icon(
                                            Icons.close,
                                            size: 16,
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                              ),
                            )
                          else
                            Text(
                              _localizedText(
                                zh: '点击「扫描模型」按钮自动发现可用模型，或手动添加。',
                                en: 'Tap "Scan Models" to discover models automatically, or add manually below.',
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          const SizedBox(height: 12),
                          // Manual model ID input
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _manualModelIdController,
                                  enabled: !_isSaving,
                                  decoration: InputDecoration(
                                    labelText: l10n.aiModelManualIdHint,
                                    isDense: true,
                                  ),
                                  onSubmitted: (_) => _addManualModelId(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: _isSaving ? null : _addManualModelId,
                                child: Text(l10n.aiModelManualIdAdd),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Current active model (legacy field, auto-synced)
                          TextFormField(
                            controller: _modelIdController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: _localizedText(
                                zh: '当前活跃模型 ID',
                                en: 'Active Model ID',
                              ),
                              helperText: _localizedText(
                                zh: '当前用于对话的模型。可从上方列表选择或直接输入。',
                                en: 'The model used for conversations. Select from the list above or type directly.',
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _activeModelId =
                                    value.trim().isEmpty ? null : value.trim();
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _maxContextTokensController,
                            enabled: !_isSaving,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _localizedText(
                                zh: '最大上下文 Token 上限',
                                en: 'Max Context Tokens',
                              ),
                              helperText: _localizedText(
                                zh: '可选。用于在压缩时限制历史切片大小。',
                                en: 'Optional. Limits the history slice used during compression.',
                              ),
                            ),
                            validator: (value) {
                              final trimmed = value?.trim() ?? '';
                              if (trimmed.isEmpty) {
                                return null;
                              }
                              final parsed = int.tryParse(trimmed);
                              if (parsed == null || parsed <= 0) {
                                return _localizedText(
                                  zh: '请输入大于 0 的整数',
                                  en: 'Enter a whole number greater than 0',
                                );
                              }
                              return null;
                            },
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: colorScheme.error),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_isSaving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OpenHandDialogActionButton.secondary(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      label: l10n.commonCancel,
                    ),
                    const SizedBox(width: 12),
                    OpenHandDialogActionButton.primary(
                      onPressed: _isSaving ? null : _handleSave,
                      label: l10n.commonSave,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final model = AiModelConfig(
      id:
          widget.initialModel?.id ??
          context.read<SettingsController>().createAiModelId(),
      name: _nameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      authScheme: _authScheme,
      token: _tokenController.text.trim(),
      modelId: _modelIdController.text.trim(),
      protocolType: _protocolType,
      maxContextTokens: _parseOptionalPositiveInt(
        _maxContextTokensController.text,
      ),
      availableModelIds: _availableModelIds,
    );

    late final bool saved;
    try {
      saved = await context.read<SettingsController>().saveAiModel(model);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.settingsPersistenceSaveFailedBody;
      });
      return;
    }
    if (!mounted) {
      return;
    }
    if (!saved) {
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.settingsPersistenceSaveFailedBody;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  int? _parseOptionalPositiveInt(String rawValue) {
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }
}

class _DenyCommandRuleTile extends StatelessWidget {
  const _DenyCommandRuleTile({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  final AiDenyCommandRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isChinese = Localizations.localeOf(
      context,
    ).languageCode.startsWith('zh');
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.block_rounded,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule.pattern, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    rule.matchMode == AiDenyCommandMatchMode.regex
                        ? (isChinese ? '正则匹配' : 'Regex Match')
                        : (isChinese ? '简单匹配' : 'Simple Match'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  if (rule.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      rule.note.trim(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
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

class _AllowCommandRuleTile extends StatelessWidget {
  const _AllowCommandRuleTile({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  final AiAllowCommandRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isChinese = Localizations.localeOf(
      context,
    ).languageCode.startsWith('zh');
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.verified_outlined,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule.pattern, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    rule.matchMode == AiDenyCommandMatchMode.regex
                        ? (isChinese ? '正则匹配' : 'Regex Match')
                        : (isChinese ? '简单匹配' : 'Simple Match'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  if (rule.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      rule.note.trim(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
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

class _DenyCommandRuleDialog extends StatefulWidget {
  const _DenyCommandRuleDialog({required this.draftRuleId, this.initialRule});

  final AiDenyCommandRule? initialRule;
  final String draftRuleId;

  @override
  State<_DenyCommandRuleDialog> createState() => _DenyCommandRuleDialogState();
}

class _DenyCommandRuleDialogState extends State<_DenyCommandRuleDialog> {
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
    final l10n = AppLocalizations.of(context)!;
    final isChinese = Localizations.localeOf(
      context,
    ).languageCode.startsWith('zh');
    return AlertDialog(
      title: Text(
        isChinese
            ? (widget.initialRule == null ? '新增禁止命令规则' : '编辑禁止命令规则')
            : (widget.initialRule == null
                  ? 'Add Deny Command Rule'
                  : 'Edit Deny Command Rule'),
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _patternController,
                decoration: InputDecoration(
                  labelText: isChinese ? '匹配表达式' : 'Pattern',
                  hintText: isChinese
                      ? '例如：rm * 或 ^rm\\s+'
                      : 'For example: rm * or ^rm\\s+',
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return isChinese
                        ? '请输入要拦截的命令表达式。'
                        : 'Enter the command pattern to block.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AiDenyCommandMatchMode>(
                initialValue: _matchMode,
                decoration: InputDecoration(
                  labelText: isChinese ? '匹配模式' : 'Match Mode',
                ),
                items: [
                  DropdownMenuItem(
                    value: AiDenyCommandMatchMode.simple,
                    child: Text(isChinese ? '简单匹配' : 'Simple Match'),
                  ),
                  DropdownMenuItem(
                    value: AiDenyCommandMatchMode.regex,
                    child: Text(isChinese ? '正则匹配' : 'Regex Match'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _matchMode = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: isChinese ? '备注' : 'Note',
                  hintText: isChinese
                      ? '可选，用于说明这条规则的用途'
                      : 'Optional description for this rule',
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
          label: l10n.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }
            Navigator.of(context).pop(
              AiDenyCommandRule(
                id: widget.initialRule?.id ?? widget.draftRuleId,
                pattern: _patternController.text.trim(),
                matchMode: _matchMode,
                note: _noteController.text.trim(),
              ),
            );
          },
          label: l10n.commonSave,
        ),
      ],
    );
  }
}

class _AllowCommandRuleDialog extends StatefulWidget {
  const _AllowCommandRuleDialog({required this.draftRuleId, this.initialRule});

  final AiAllowCommandRule? initialRule;
  final String draftRuleId;

  @override
  State<_AllowCommandRuleDialog> createState() =>
      _AllowCommandRuleDialogState();
}

class _AllowCommandRuleDialogState extends State<_AllowCommandRuleDialog> {
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
    final l10n = AppLocalizations.of(context)!;
    final isChinese = Localizations.localeOf(
      context,
    ).languageCode.startsWith('zh');
    return AlertDialog(
      title: Text(
        isChinese
            ? (widget.initialRule == null ? '新增允许命令规则' : '编辑允许命令规则')
            : (widget.initialRule == null
                  ? 'Add Allow Command Rule'
                  : 'Edit Allow Command Rule'),
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _patternController,
                decoration: InputDecoration(
                  labelText: isChinese ? '匹配表达式' : 'Pattern',
                  hintText: isChinese
                      ? '例如：flutter test * 或 ^git\\s+commit'
                      : 'For example: flutter test * or ^git\\s+commit',
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return isChinese
                        ? '请输入要放行的命令表达式。'
                        : 'Enter the command pattern to allow.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AiDenyCommandMatchMode>(
                initialValue: _matchMode,
                decoration: InputDecoration(
                  labelText: isChinese ? '匹配模式' : 'Match Mode',
                ),
                items: [
                  DropdownMenuItem(
                    value: AiDenyCommandMatchMode.simple,
                    child: Text(isChinese ? '简单匹配' : 'Simple Match'),
                  ),
                  DropdownMenuItem(
                    value: AiDenyCommandMatchMode.regex,
                    child: Text(isChinese ? '正则匹配' : 'Regex Match'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _matchMode = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: isChinese ? '备注' : 'Note',
                  hintText: isChinese
                      ? '可选，用于说明为什么允许这条命令'
                      : 'Optional description for why this command is allowed',
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
          label: l10n.commonCancel,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }
            Navigator.of(context).pop(
              AiAllowCommandRule(
                id: widget.initialRule?.id ?? widget.draftRuleId,
                pattern: _patternController.text.trim(),
                matchMode: _matchMode,
                note: _noteController.text.trim(),
              ),
            );
          },
          label: l10n.commonSave,
        ),
      ],
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              ..._intersperse(children, const SizedBox(height: 18)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSubsectionCard extends StatelessWidget {
  const _SettingsSubsectionCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _ThemePresetSwatch extends StatelessWidget {
  const _ThemePresetSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final outlineColor = Theme.of(context).colorScheme.outlineVariant;

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: outlineColor),
      ),
    );
  }
}

class _ResponsiveSettingRow extends StatelessWidget {
  const _ResponsiveSettingRow({
    required this.title,
    required this.subtitle,
    required this.control,
    this.controlMaxWidth = 320,
  });

  final String title;
  final String subtitle;
  final Widget control;
  final double controlMaxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 760;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              control,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: controlMaxWidth),
                child: control,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReadonlySettingRow extends StatelessWidget {
  const _ReadonlySettingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 680;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(value, style: theme.textTheme.bodyLarge),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(value, style: theme.textTheme.bodyLarge),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsStateBox extends StatelessWidget {
  const _SettingsStateBox({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutBindingTile extends StatelessWidget {
  const _ShortcutBindingTile({
    required this.actionStorageKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onRecord,
    required this.onReset,
  });

  final String actionStorageKey;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onRecord;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 680;
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
            final controls = Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  key: ValueKey<String>('shortcut-value-$actionStorageKey'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Text(
                    value,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: ValueKey<String>('shortcut-record-$actionStorageKey'),
                  onPressed: onRecord,
                  icon: const Icon(Icons.keyboard_alt_rounded),
                  label: Text(
                    Localizations.localeOf(
                          context,
                        ).languageCode.startsWith('zh')
                        ? '录制'
                        : 'Record',
                  ),
                ),
                IconButton(
                  key: ValueKey<String>('shortcut-reset-$actionStorageKey'),
                  onPressed: onReset,
                  tooltip:
                      Localizations.localeOf(
                        context,
                      ).languageCode.startsWith('zh')
                      ? '恢复默认'
                      : 'Reset to default',
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
              ],
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [content, const SizedBox(height: 14), controls],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: content),
                const SizedBox(width: 16),
                Flexible(child: controls),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ShortcutRecorderDialog extends StatefulWidget {
  const _ShortcutRecorderDialog({
    required this.title,
    required this.initialKeyIds,
  });

  final String title;
  final List<int> initialKeyIds;

  @override
  State<_ShortcutRecorderDialog> createState() =>
      _ShortcutRecorderDialogState();
}

class _ShortcutRecorderDialogState extends State<_ShortcutRecorderDialog> {
  late final FocusNode _focusNode;
  late List<int> _currentKeyIds;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _currentKeyIds = normalizeShortcutKeyIds(widget.initialKeyIds);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    final nextKeyIds = normalizeShortcutKeyIds(
      HardwareKeyboard.instance.logicalKeysPressed.map((key) => key.keyId),
    );
    if (nextKeyIds.length > openHandShortcutMaxKeyCount) {
      setState(() {
        _errorText =
            Localizations.localeOf(context).languageCode.startsWith('zh')
            ? '最多支持同时按下 4 个按键。'
            : 'OpenHand supports up to four simultaneous keys.';
      });
      return KeyEventResult.handled;
    }
    setState(() {
      _currentKeyIds = nextKeyIds;
      _errorText = null;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = Localizations.localeOf(
      context,
    ).languageCode.startsWith('zh');
    final canSave = isValidShortcutBinding(_currentKeyIds);
    return AlertDialog(
      title: Text(widget.title),
      content: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        autofocus: true,
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isChinese
                    ? '按下新的组合键即可更新绑定。最多支持同时按下 4 个按键。'
                    : 'Press the new key combination to update this binding. OpenHand supports up to four simultaneous keys.',
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  formatShortcutLabel(_currentKeyIds),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isChinese
                    ? '提示：至少需要一个非修饰键，例如 Enter、P、方向键。'
                    : 'Tip: include at least one non-modifier key such as Enter, P, or an arrow key.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
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
          onPressed: canSave
              ? () => Navigator.of(
                  context,
                ).pop(normalizeShortcutKeyIds(_currentKeyIds))
              : null,
          label: AppLocalizations.of(context)!.commonSave,
        ),
      ],
    );
  }
}

class _SettingsPersistenceIssueCard extends StatelessWidget {
  const _SettingsPersistenceIssueCard({
    required this.issue,
    required this.onDismiss,
  });

  final SettingsPersistenceIssue issue;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final (title, body) = switch (issue.kind) {
      SettingsPersistenceIssueKind.recoveredInvalidFile => (
        l10n.settingsPersistenceRecoveredTitle,
        '${l10n.settingsPersistenceRecoveredBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
      SettingsPersistenceIssueKind.sanitizedInvalidContent => (
        l10n.settingsPersistenceSanitizedTitle,
        '${l10n.settingsPersistenceSanitizedBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
      SettingsPersistenceIssueKind.saveFailed => (
        l10n.settingsPersistenceSaveFailedTitle,
        '${l10n.settingsPersistenceSaveFailedBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
    };

    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDismiss,
              tooltip: l10n.settingsPersistenceDismiss,
              icon: Icon(
                Icons.close_rounded,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiModelTile extends StatelessWidget {
  const _AiModelTile({
    required this.model,
    required this.isSelected,
    required this.isTesting,
    required this.isFirst,
    required this.isLast,
    required this.onSelect,
    required this.onTest,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final AiModelConfig model;
  final bool isSelected;
  final bool isTesting;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onSelect;
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  String _localizedText(BuildContext context,
      {required String zh, required String en}) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode.startsWith('zh') ? zh : en;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allModels = model.allModelIds;
    final modelCountLabel = allModels.isNotEmpty
        ? l10n.aiModelCount(allModels.length)
        : _localizedText(context, zh: '无模型', en: 'No models');

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.52)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.providerLabel,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${model.protocolType.label(l10n)} · ${model.authScheme.label(l10n)} · $modelCountLabel',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (model.modelId.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _localizedText(
                              context,
                              zh: '当前模型：${model.modelId}',
                              en: 'Active: ${model.modelId}',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        onPressed: isFirst ? null : onMoveUp,
                        tooltip: l10n.aiModelMoveUp,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                      IconButton(
                        onPressed: isLast ? null : onMoveDown,
                        tooltip: l10n.aiModelMoveDown,
                        icon: const Icon(Icons.arrow_downward_rounded),
                      ),
                      IconButton(
                        onPressed: onEdit,
                        tooltip: l10n.commonEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        onPressed: onDelete,
                        tooltip: l10n.commonDelete,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                      IconButton(
                        onPressed: isTesting ? null : onTest,
                        tooltip: isTesting
                            ? l10n.aiModelTesting
                            : l10n.aiModelTest,
                        icon: isTesting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.network_check_rounded),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  Chip(
                    avatar: const Icon(Icons.link_rounded, size: 18),
                    label: Text(model.normalizedBaseUrl),
                  ),
                  Chip(
                    avatar: const Icon(Icons.vpn_key_outlined, size: 18),
                    label: Text(
                      model.maskedToken.isEmpty
                          ? l10n.aiModelNoToken
                          : model.maskedToken,
                    ),
                  ),
                  if (isSelected)
                    Chip(
                      avatar: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                      ),
                      label: Text(l10n.aiModelSelected),
                    ),
                ],
              ),
              // Show available models as small chips when expanded.
              if (allModels.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: allModels
                      .map(
                        (id) => Chip(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(
                            id == model.modelId
                                ? Icons.star_rounded
                                : Icons.smart_toy_outlined,
                            size: 14,
                          ),
                          label: Text(
                            id,
                            style: theme.textTheme.labelSmall,
                          ),
                          backgroundColor: id == model.modelId
                              ? colorScheme.primaryContainer
                              : null,
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

List<Widget> _intersperse(List<Widget> items, Widget separator) {
  if (items.isEmpty) {
    return const <Widget>[];
  }
  final output = <Widget>[];
  for (var index = 0; index < items.length; index++) {
    output.add(items[index]);
    if (index != items.length - 1) {
      output.add(separator);
    }
  }
  return output;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog animation settings section
// ─────────────────────────────────────────────────────────────────────────────

class _DialogAnimationSettingsSection extends StatelessWidget {
  const _DialogAnimationSettingsSection({
    required this.settingsController,
  });

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final current = settingsController.dialogAnimationSettings;
    return _ResponsiveSettingRow(
      title: isZh ? '弹窗动画' : 'Dialog Animation',
      subtitle: isZh
          ? '配置全局弹窗的进场动画、退场动画、时长和速率曲线。'
          : 'Configure entrance/exit animation style, duration, and easing curve for all dialogs.',

      controlMaxWidth: 440,
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Entrance style
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '进场' : 'Enter',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationStyle>(
                  value: current.entranceStyle,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationStyle.values
                      .map(
                        (style) => DropdownMenuItem(
                          value: style,
                          child: Text(
                            style.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateDialogAnimationSettings(
                      current.copyWith(entranceStyle: value),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Exit style
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '退场' : 'Exit',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationStyle>(
                  value: current.exitStyle,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationStyle.values
                      .map(
                        (style) => DropdownMenuItem(
                          value: style,
                          child: Text(
                            style.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateDialogAnimationSettings(
                      current.copyWith(exitStyle: value),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Duration
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '时长' : 'Duration',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: current.durationMs.toDouble(),
                        min: 100,
                        max: 800,
                        divisions: 14,
                        label: '${current.durationMs}ms',
                        onChanged: (value) {
                          settingsController.updateDialogAnimationSettings(
                            current.copyWith(durationMs: value.round()),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 54,
                      child: Text(
                        '${current.durationMs}ms',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Curve
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '曲线' : 'Curve',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationCurve>(
                  value: current.curve,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationCurve.values
                      .map(
                        (curve) => DropdownMenuItem(
                          value: curve,
                          child: Text(
                            curve.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateDialogAnimationSettings(
                      current.copyWith(curve: value),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuAnimationSettingsSection extends StatelessWidget {
  const _MenuAnimationSettingsSection({
    required this.settingsController,
  });

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final current = settingsController.menuAnimationSettings;
    return _ResponsiveSettingRow(
      title: isZh ? '菜单动画' : 'Menu Animation',
      subtitle: isZh
          ? '配置弹出菜单、右键菜单和下拉菜单的进场动画、退场动画、时长和速率曲线。'
          : 'Configure entrance/exit animation style, duration, and easing curve for popup menus and context menus.',
      controlMaxWidth: 440,
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Entrance style
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '进场' : 'Enter',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationStyle>(
                  value: current.entranceStyle,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationStyle.values
                      .map(
                        (style) => DropdownMenuItem(
                          value: style,
                          child: Text(
                            style.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateMenuAnimationSettings(
                      current.copyWith(entranceStyle: value),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Exit style
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '退场' : 'Exit',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationStyle>(
                  value: current.exitStyle,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationStyle.values
                      .map(
                        (style) => DropdownMenuItem(
                          value: style,
                          child: Text(
                            style.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateMenuAnimationSettings(
                      current.copyWith(exitStyle: value),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Duration
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '时长' : 'Duration',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: current.durationMs.toDouble(),
                        min: 100,
                        max: 800,
                        divisions: 14,
                        label: '${current.durationMs}ms',
                        onChanged: (value) {
                          settingsController.updateMenuAnimationSettings(
                            current.copyWith(durationMs: value.round()),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 54,
                      child: Text(
                        '${current.durationMs}ms',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Curve
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isZh ? '曲线' : 'Curve',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<DialogAnimationCurve>(
                  value: current.curve,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: DialogAnimationCurve.values
                      .map(
                        (curve) => DropdownMenuItem(
                          value: curve,
                          child: Text(
                            curve.label(isZh),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsController.updateMenuAnimationSettings(
                      current.copyWith(curve: value),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

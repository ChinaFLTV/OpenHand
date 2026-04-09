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
import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../ai/model/ai_allow_command_rule.dart';
import '../ai/model/ai_deny_command_rule.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/service/ai_chat_service.dart';
import '../ai/service/ai_model_scanner.dart';
import '../mcp/mcp_controller.dart';
import '../memory/memory_controller.dart';
import '../skills/skills_controller.dart';


part '_settings_ai_model_editor.dart';
part '_settings_command_rules.dart';
part '_settings_shortcut_widgets.dart';
part '_settings_animation_sections.dart';
part '_settings_helper_widgets.dart';

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

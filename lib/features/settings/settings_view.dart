import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/model/app_info.dart';
import '../../app/model/app_language.dart';
import '../../app/model/app_settings_snapshot.dart';
import '../../app/state/settings_controller.dart';
import '../../app/state/settings_store.dart';
import '../../app/support/openhand_paths.dart';
import '../../app/theme/openhand_theme_preset.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../ai/model/ai_deny_command_rule.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/service/ai_chat_service.dart';
import '../memory/data/memory_store.dart';
import '../memory/memory_controller.dart';
import '../mcp/mcp_controller.dart';
import '../skills/skills_controller.dart';

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
  }

  @override
  void dispose() {
    _skillsPathController.dispose();
    _skillsPathFocusNode.dispose();
    _memoryFileController.dispose();
    _memoryFileFocusNode.dispose();
    _compressionThresholdController.dispose();
    _compressionThresholdFocusNode.dispose();
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
              ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSubsectionCard(
          title: _localizedText(context, zh: '模型管理', en: 'Model Management'),
          description: _localizedText(
            context,
            zh: '新增、选择、测试并维护当前可用的聊天模型。',
            en: 'Add, select, test, and maintain the chat models available to OpenHand.',
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
          child: _ResponsiveSettingRow(
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
    final previousPath = settingsController.skillsStoragePath;
    try {
      final saved = await settingsController.updateSkillsStoragePath(rawPath);
      if (!saved) {
        if (!context.mounted) {
          return;
        }
        _showPersistenceFailureSnackBar(context);
        return;
      }
      await skillsController.reloadFromPath(
        settingsController.skillsStoragePath,
      );
      if (skillsController.errorMessage != null) {
        final rolledBack = await _restoreSkillsPath(
          settingsController,
          skillsController,
          previousPath,
        );
        if (!context.mounted) {
          return;
        }
        _skillsPathController.text = settingsController.skillsStoragePath;
        if (!rolledBack && settingsController.persistenceIssue != null) {
          _showPersistenceFailureSnackBar(context);
          return;
        }
        _showSnackBar(context, l10n.skillOperationFailed);
        return;
      }
      if (!context.mounted) {
        return;
      }
      _skillsPathController.text = settingsController.skillsStoragePath;
      _showSnackBar(context, l10n.skillsPathSaved);
    } catch (_) {
      final rolledBack = await _restoreSkillsPath(
        settingsController,
        skillsController,
        previousPath,
      );
      if (!context.mounted) {
        return;
      }
      _skillsPathController.text = settingsController.skillsStoragePath;
      if (!rolledBack && settingsController.persistenceIssue != null) {
        _showPersistenceFailureSnackBar(context);
        return;
      }
      _showSnackBar(context, l10n.skillOperationFailed);
    }
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
    final previousPath = settingsController.userMemoryFilePath;
    try {
      final saved = await settingsController.updateUserMemoryFilePath(rawPath);
      if (!saved) {
        if (!context.mounted) {
          return;
        }
        _showPersistenceFailureSnackBar(context);
        return;
      }
      await memoryController.reloadFromFilePath(
        settingsController.userMemoryFilePath,
      );
      if (_didMemoryReloadFail(memoryController)) {
        final rolledBack = await _restoreMemoryFilePath(
          settingsController,
          memoryController,
          previousPath,
        );
        if (!context.mounted) {
          return;
        }
        _memoryFileController.text = settingsController.userMemoryFilePath;
        if (!rolledBack && settingsController.persistenceIssue != null) {
          _showPersistenceFailureSnackBar(context);
          return;
        }
        _showSnackBar(context, l10n.memoryOperationFailed);
        return;
      }
      if (!context.mounted) {
        return;
      }
      _memoryFileController.text = settingsController.userMemoryFilePath;
      _showSnackBar(context, l10n.memoryPathSaved);
    } catch (_) {
      final rolledBack = await _restoreMemoryFilePath(
        settingsController,
        memoryController,
        previousPath,
      );
      if (!context.mounted) {
        return;
      }
      _memoryFileController.text = settingsController.userMemoryFilePath;
      if (!rolledBack && settingsController.persistenceIssue != null) {
        _showPersistenceFailureSnackBar(context);
        return;
      }
      _showSnackBar(context, l10n.memoryOperationFailed);
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
    await skillsController.reloadFromPath(previousPath);
    return skillsController.errorMessage == null;
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
    await memoryController.reloadFromFilePath(previousPath);
    return !_didMemoryReloadFail(memoryController);
  }

  bool _didMemoryReloadFail(MemoryController memoryController) {
    return memoryController.errorMessage != null ||
        memoryController.persistenceIssue?.kind ==
            MemoryPersistenceIssueKind.saveFailed;
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
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _compressionThresholdController.text = '$parsedValue';
    _showSnackBar(context, l10n.aiCompressionThresholdSaved);
  }

  Future<void> _showDenyCommandRuleDialog(
    BuildContext context, {
    AiDenyCommandRule? initialRule,
  }) async {
    final settingsController = context.read<SettingsController>();
    final submittedRule = await showDialog<AiDenyCommandRule>(
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
    final confirmed = await showDialog<bool>(
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
    final submitted = await showDialog<bool>(
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
      _showSnackBar(context, l10n.aiModelTestSuccess(model.displayName));
    } on AiChatException catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context)!;
      _showSnackBar(
        context,
        l10n.aiModelTestFailure(
          model.displayName,
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
          model.displayName,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.aiModelDeleteConfirmTitle),
          content: Text(
            '${l10n.aiModelDeleteConfirmBody}\n\n${model.displayName}',
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
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenController;
  late final TextEditingController _modelIdController;
  late AiAuthScheme _authScheme;
  late AiProtocolType _protocolType;
  bool _obscureToken = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: widget.initialModel?.baseUrl ?? '',
    );
    _tokenController = TextEditingController(
      text: widget.initialModel?.token ?? '',
    );
    _modelIdController = TextEditingController(
      text: widget.initialModel?.modelId ?? '',
    );
    _authScheme = widget.initialModel?.authScheme ?? AiAuthScheme.bearer;
    _protocolType = widget.initialModel?.protocolType ?? AiProtocolType.openai;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _tokenController.dispose();
    _modelIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
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
                              final parsed = Uri.tryParse(rawValue);
                              if (parsed == null ||
                                  (!parsed.hasScheme &&
                                      !rawValue.startsWith('http'))) {
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
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _modelIdController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: l10n.aiModelIdField,
                            ),
                            validator: (value) {
                              if ((value?.trim() ?? '').isEmpty) {
                                return l10n.aiModelIdRequired;
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
      baseUrl: _baseUrlController.text.trim(),
      authScheme: _authScheme,
      token: _tokenController.text.trim(),
      modelId: _modelIdController.text.trim(),
      protocolType: _protocolType,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                          model.displayName,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${model.protocolType.label(l10n)} · ${model.authScheme.label(l10n)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
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

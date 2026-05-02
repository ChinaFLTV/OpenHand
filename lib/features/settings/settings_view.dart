import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/model/app_info.dart';
import '../../app/model/app_language.dart';
import '../../app/model/app_proxy_settings.dart';
import '../../app/model/app_settings_snapshot.dart';
import '../../app/model/dialog_animation_settings.dart';
import '../../app/model/editor_code_theme.dart';
import '../../app/model/editor_indent.dart';
import '../../app/model/editor_shortcut.dart';
import '../../app/model/openhand_shortcut.dart';
import '../../app/state/settings_controller.dart';
import '../../app/state/settings_store.dart';
import '../../app/support/openhand_paths.dart';
import '../../app/support/silent_log.dart';
import '../../app/support/system_proxy.dart';
import '../../app/support/url_validation.dart';
import '../../app/theme/openhand_theme_preset.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/error_snackbar.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../ai/ai_session_controller.dart';
import '../ai/model/ai_allow_command_rule.dart';
import '../ai/model/ai_builtin_tool_config.dart';
import '../ai/model/ai_deny_command_rule.dart';
import '../ai/model/ai_lsp_backend_catalog.dart';
import '../ai/model/ai_lsp_language_settings.dart';
import '../ai/model/ai_model_catalog.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/service/ai_chat_service.dart';
import '../ai/service/ai_image_generation_service.dart';
import '../ai/service/ai_lsp_managed_install_service.dart';
import '../ai/service/ai_model_scanner.dart';
import '../ai/service/ai_protocol_adapter.dart';
import '../ai/service/ai_tool_runtime_service.dart';
import '../crons/crons_controller.dart';
import '../hardness/hardness_cli_catalog.dart';
import '../mcp/mcp_controller.dart';
import '../memory/memory_controller.dart';
import '../skills/skills_controller.dart';
import 'data_cleanup/data_cleanup_models.dart';
import 'data_cleanup/data_cleanup_service.dart';
import 'thread_session_management_dialog.dart';

part '_settings_ai_model_editor.dart';
part '_settings_editor_lsp.dart';
part '_settings_command_rules.dart';
part '_settings_shortcut_widgets.dart';
part '_settings_animation_sections.dart';
part '_settings_builtin_tools.dart';
part '_settings_helper_widgets.dart';
part '_settings_user_profile.dart';
part '_settings_data_cleanup.dart';
part '_settings_system_proxy.dart';
part '_settings_proxy_test_dialog.dart';

typedef _SettingsPathGetter = String Function(SettingsController controller);
typedef _SettingsPathOperation = Future<bool> Function(String path);

enum _SettingsSection {
  header,
  persistenceIssue,
  general,
  shortcuts,
  ai,
  builtinTools,
  mcp,
  skills,
  memory,
  crons,
  hermesTalker,
  editor,
  appData,
  system,
  about,
}

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

/// Public launcher for the AI model editor dialog so non-settings surfaces
/// (e.g. the composer's quick-edit gear button) can re-use the exact same
/// editor without copying its UI. Returns `true` when the user saved a
/// change, otherwise `false`.
Future<bool> showAiModelEditorDialog(
  BuildContext context, {
  AiModelConfig? initialModel,
}) async {
  final submitted = await showAnimatedDialog<bool>(
    context: context,
    builder: (dialogContext) => _AiModelEditorDialog(initialModel: initialModel),
  );
  return submitted == true;
}

class _SettingsViewState extends State<SettingsView> {
  late final TextEditingController _skillsPathController;
  late final FocusNode _skillsPathFocusNode;
  late final TextEditingController _memoryFileController;
  late final FocusNode _memoryFileFocusNode;
  late final ScrollController _editorLspListScrollController;
  late final ScrollController _shortcutListScrollController;
  late final ScrollController _editorShortcutListScrollController;
  late final TextEditingController _compressionThresholdController;
  late final FocusNode _compressionThresholdFocusNode;
  late final TextEditingController _toolResultCompressionThresholdController;
  late final FocusNode _toolResultCompressionThresholdFocusNode;
  late final TextEditingController
  _toolResultCompressionHeadTailWindowController;
  late final FocusNode _toolResultCompressionHeadTailWindowFocusNode;
  late final TextEditingController _toolResultCompressionMaxPathHitsController;
  late final FocusNode _toolResultCompressionMaxPathHitsFocusNode;
  late final TextEditingController _writeToolSummaryMaxCharsController;
  late final FocusNode _writeToolSummaryMaxCharsFocusNode;
  late final TextEditingController _toolCallLimitController;
  late final FocusNode _toolCallLimitFocusNode;
  late final TextEditingController _sequentialToolRoundLimitController;
  late final FocusNode _sequentialToolRoundLimitFocusNode;
  late final TextEditingController _maxRecentErrorsController;
  late final FocusNode _maxRecentErrorsFocusNode;
  late final TextEditingController _maxPlanHistoryEntriesController;
  late final FocusNode _maxPlanHistoryEntriesFocusNode;
  late final TextEditingController _maxTruncationContinuationsController;
  late final FocusNode _maxTruncationContinuationsFocusNode;
  late final TextEditingController _estimatedCharactersPerTokenController;
  late final FocusNode _estimatedCharactersPerTokenFocusNode;
  late final TextEditingController _imageSizeLimitController;
  late final FocusNode _imageSizeLimitFocusNode;
  late final TextEditingController _connectTimeoutController;
  late final FocusNode _connectTimeoutFocusNode;
  late final TextEditingController _responseTimeoutController;
  late final FocusNode _responseTimeoutFocusNode;
  late final TextEditingController _streamIdleTimeoutController;
  late final FocusNode _streamIdleTimeoutFocusNode;
  final Set<String> _testingAiModelIds = <String>{};

  @override
  void initState() {
    super.initState();
    _skillsPathController = TextEditingController();
    _skillsPathFocusNode = FocusNode();
    _memoryFileController = TextEditingController();
    _memoryFileFocusNode = FocusNode();
    _editorLspListScrollController = ScrollController();
    _shortcutListScrollController = ScrollController();
    _editorShortcutListScrollController = ScrollController();
    _compressionThresholdController = TextEditingController();
    _compressionThresholdFocusNode = FocusNode();
    _toolResultCompressionThresholdController = TextEditingController();
    _toolResultCompressionThresholdFocusNode = FocusNode();
    _toolResultCompressionHeadTailWindowController = TextEditingController();
    _toolResultCompressionHeadTailWindowFocusNode = FocusNode();
    _toolResultCompressionMaxPathHitsController = TextEditingController();
    _toolResultCompressionMaxPathHitsFocusNode = FocusNode();
    _writeToolSummaryMaxCharsController = TextEditingController();
    _writeToolSummaryMaxCharsFocusNode = FocusNode();
    _toolCallLimitController = TextEditingController();
    _toolCallLimitFocusNode = FocusNode();
    _sequentialToolRoundLimitController = TextEditingController();
    _sequentialToolRoundLimitFocusNode = FocusNode();
    _maxRecentErrorsController = TextEditingController();
    _maxRecentErrorsFocusNode = FocusNode();
    _maxPlanHistoryEntriesController = TextEditingController();
    _maxPlanHistoryEntriesFocusNode = FocusNode();
    _maxTruncationContinuationsController = TextEditingController();
    _maxTruncationContinuationsFocusNode = FocusNode();
    _estimatedCharactersPerTokenController = TextEditingController();
    _estimatedCharactersPerTokenFocusNode = FocusNode();
    _imageSizeLimitController = TextEditingController();
    _imageSizeLimitFocusNode = FocusNode();
    _connectTimeoutController = TextEditingController();
    _connectTimeoutFocusNode = FocusNode();
    _responseTimeoutController = TextEditingController();
    _responseTimeoutFocusNode = FocusNode();
    _streamIdleTimeoutController = TextEditingController();
    _streamIdleTimeoutFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _skillsPathController.dispose();
    _skillsPathFocusNode.dispose();
    _memoryFileController.dispose();
    _memoryFileFocusNode.dispose();
    _editorLspListScrollController.dispose();
    _shortcutListScrollController.dispose();
    _editorShortcutListScrollController.dispose();
    _compressionThresholdController.dispose();
    _compressionThresholdFocusNode.dispose();
    _toolResultCompressionThresholdController.dispose();
    _toolResultCompressionThresholdFocusNode.dispose();
    _toolResultCompressionHeadTailWindowController.dispose();
    _toolResultCompressionHeadTailWindowFocusNode.dispose();
    _toolResultCompressionMaxPathHitsController.dispose();
    _toolResultCompressionMaxPathHitsFocusNode.dispose();
    _writeToolSummaryMaxCharsController.dispose();
    _writeToolSummaryMaxCharsFocusNode.dispose();
    _toolCallLimitController.dispose();
    _toolCallLimitFocusNode.dispose();
    _sequentialToolRoundLimitController.dispose();
    _sequentialToolRoundLimitFocusNode.dispose();
    _maxRecentErrorsController.dispose();
    _maxRecentErrorsFocusNode.dispose();
    _maxPlanHistoryEntriesController.dispose();
    _maxPlanHistoryEntriesFocusNode.dispose();
    _maxTruncationContinuationsController.dispose();
    _maxTruncationContinuationsFocusNode.dispose();
    _estimatedCharactersPerTokenController.dispose();
    _estimatedCharactersPerTokenFocusNode.dispose();
    _imageSizeLimitController.dispose();
    _imageSizeLimitFocusNode.dispose();
    _connectTimeoutController.dispose();
    _connectTimeoutFocusNode.dispose();
    _responseTimeoutController.dispose();
    _responseTimeoutFocusNode.dispose();
    _streamIdleTimeoutController.dispose();
    _streamIdleTimeoutFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    final toolResultCompressionThresholdText =
        '${settingsController.aiToolResultCompressionThresholdChars}';
    if (!_toolResultCompressionThresholdFocusNode.hasFocus &&
        _toolResultCompressionThresholdController.text !=
            toolResultCompressionThresholdText) {
      _toolResultCompressionThresholdController.text =
          toolResultCompressionThresholdText;
    }
    final toolResultCompressionHeadTailWindowText =
        '${settingsController.aiToolResultCompressionHeadTailWindowChars}';
    if (!_toolResultCompressionHeadTailWindowFocusNode.hasFocus &&
        _toolResultCompressionHeadTailWindowController.text !=
            toolResultCompressionHeadTailWindowText) {
      _toolResultCompressionHeadTailWindowController.text =
          toolResultCompressionHeadTailWindowText;
    }
    final toolResultCompressionMaxPathHitsText =
        '${settingsController.aiToolResultCompressionMaxPathHits}';
    if (!_toolResultCompressionMaxPathHitsFocusNode.hasFocus &&
        _toolResultCompressionMaxPathHitsController.text !=
            toolResultCompressionMaxPathHitsText) {
      _toolResultCompressionMaxPathHitsController.text =
          toolResultCompressionMaxPathHitsText;
    }
    final writeToolSummaryMaxCharsText =
        '${settingsController.aiWriteToolSummaryMaxChars}';
    if (!_writeToolSummaryMaxCharsFocusNode.hasFocus &&
        _writeToolSummaryMaxCharsController.text !=
            writeToolSummaryMaxCharsText) {
      _writeToolSummaryMaxCharsController.text = writeToolSummaryMaxCharsText;
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
    final maxRecentErrorsText = '${settingsController.aiMaxRecentErrors}';
    if (!_maxRecentErrorsFocusNode.hasFocus &&
        _maxRecentErrorsController.text != maxRecentErrorsText) {
      _maxRecentErrorsController.text = maxRecentErrorsText;
    }
    final maxPlanHistoryEntriesText =
        '${settingsController.aiMaxPlanHistoryEntries}';
    if (!_maxPlanHistoryEntriesFocusNode.hasFocus &&
        _maxPlanHistoryEntriesController.text != maxPlanHistoryEntriesText) {
      _maxPlanHistoryEntriesController.text = maxPlanHistoryEntriesText;
    }
    final maxTruncationContinuationsText =
        '${settingsController.aiMaxTruncationContinuations}';
    if (!_maxTruncationContinuationsFocusNode.hasFocus &&
        _maxTruncationContinuationsController.text !=
            maxTruncationContinuationsText) {
      _maxTruncationContinuationsController.text =
          maxTruncationContinuationsText;
    }
    final estimatedCharactersPerTokenText =
        '${settingsController.aiEstimatedCharactersPerToken}';
    if (!_estimatedCharactersPerTokenFocusNode.hasFocus &&
        _estimatedCharactersPerTokenController.text !=
            estimatedCharactersPerTokenText) {
      _estimatedCharactersPerTokenController.text =
          estimatedCharactersPerTokenText;
    }
    final imageSizeLimitText = _formatImageSizeLimitInput(
      settingsController.aiImageSizeLimitBytes,
    );
    if (!_imageSizeLimitFocusNode.hasFocus &&
        _imageSizeLimitController.text != imageSizeLimitText) {
      _imageSizeLimitController.text = imageSizeLimitText;
    }
    final connectTimeoutText = '${settingsController.aiConnectTimeoutSeconds}';
    if (!_connectTimeoutFocusNode.hasFocus &&
        _connectTimeoutController.text != connectTimeoutText) {
      _connectTimeoutController.text = connectTimeoutText;
    }
    final responseTimeoutText =
        '${settingsController.aiResponseTimeoutSeconds}';
    if (!_responseTimeoutFocusNode.hasFocus &&
        _responseTimeoutController.text != responseTimeoutText) {
      _responseTimeoutController.text = responseTimeoutText;
    }
    final streamIdleTimeoutText =
        '${settingsController.aiStreamIdleTimeoutSeconds}';
    if (!_streamIdleTimeoutFocusNode.hasFocus &&
        _streamIdleTimeoutController.text != streamIdleTimeoutText) {
      _streamIdleTimeoutController.text = streamIdleTimeoutText;
    }

    final sections = <_SettingsSection>[
      _SettingsSection.header,
      if (settingsController.persistenceIssue != null)
        _SettingsSection.persistenceIssue,
      _SettingsSection.general,
      _SettingsSection.shortcuts,
      _SettingsSection.ai,
      _SettingsSection.builtinTools,
      _SettingsSection.mcp,
      _SettingsSection.skills,
      _SettingsSection.memory,
      _SettingsSection.crons,
      _SettingsSection.hermesTalker,
      _SettingsSection.editor,
      _SettingsSection.appData,
      _SettingsSection.system,
      _SettingsSection.about,
    ];

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: sections.length,
        separatorBuilder: (context, index) {
          final current = sections[index];
          if (current == _SettingsSection.header &&
              sections[index + 1] == _SettingsSection.persistenceIssue) {
            return const SizedBox(height: 18);
          }
          if (current == _SettingsSection.header ||
              current == _SettingsSection.persistenceIssue) {
            return const SizedBox(height: 24);
          }
          return const SizedBox(height: 18);
        },
        itemBuilder: (context, index) {
          return _buildSettingsSection(
            context,
            settingsController,
            appInfo,
            sections[index],
          );
        },
      ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context,
    SettingsController settingsController,
    AppInfo appInfo,
    _SettingsSection section,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return switch (section) {
      _SettingsSection.header => _PaneHeader(
        title: l10n.settingsTitle,
        subtitle: l10n.settingsSubtitle,
      ),
      _SettingsSection.persistenceIssue => _SettingsPersistenceIssueCard(
        issue: settingsController.persistenceIssue!,
        onDismiss: settingsController.clearPersistenceIssue,
      ),
      _SettingsSection.general => _SettingsGroupCard(
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
                  final saved = await settingsController.updateThemePreset(
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
                  final saved = await settingsController.updateLanguage(value);
                  if (!context.mounted || saved) {
                    return;
                  }
                  _showPersistenceFailureSnackBar(context);
                },
              ),
            ),
          ),
          _AnimationRestoreDefaultsSection(
            settingsController: settingsController,
          ),
          _DialogAnimationSettingsSection(
            settingsController: settingsController,
          ),
          _MenuAnimationSettingsSection(settingsController: settingsController),
          _PageAnimationSettingsSection(settingsController: settingsController),
          _PanelAnimationSettingsSection(
            settingsController: settingsController,
          ),
          _ChipAnimationSettingsSection(
            settingsController: settingsController,
          ),
          _ListItemAnimationSettingsSection(
            settingsController: settingsController,
          ),
        ],
      ),
      _SettingsSection.shortcuts => _SettingsGroupCard(
        title: _localizedText(context, zh: '快捷键', en: 'Shortcuts'),
        description: _localizedText(
          context,
          zh: '为常用操作配置组合键。当前最多支持同时按下 4 个按键。',
          en: 'Configure key combinations for common actions. OpenHand currently supports up to four simultaneous keys.',
        ),
        children: [_buildShortcutsSection(context, settingsController)],
      ),
      _SettingsSection.ai => _SettingsGroupCard(
        title: l10n.settingsCategoryAi,
        description: l10n.settingsAiSubtitle,
        children: [_buildAiModelsSection(context, settingsController)],
      ),
      _SettingsSection.builtinTools => _SettingsGroupCard(
        title: _localizedText(context, zh: '内建工具', en: 'Built-in Tools'),
        description: _localizedText(
          context,
          zh:
              '管理应用内置的 AI 内建工具。可调整每个工具的启用状态、名称、描述、'
              'Schema、优先级、排序、加载策略和其他参数。',
          en:
              'Manage the built-in AI tools. Adjust each tool\'s enabled '
              'state, name, description, schema, priority, sort order, '
              'load strategy, and other parameters.',
        ),
        children: [_buildBuiltinToolsSection(context, settingsController)],
      ),
      _SettingsSection.mcp => _SettingsGroupCard(
        title: l10n.mcpSectionTitle,
        description: l10n.mcpSectionBody,
        children: [_buildMcpSettingsSection(context, settingsController)],
      ),
      _SettingsSection.skills => _SettingsGroupCard(
        title: l10n.settingsCategorySkills,
        description: l10n.settingsSkillsSubtitle,
        children: [_buildSkillsSection(context, settingsController)],
      ),
      _SettingsSection.memory => _SettingsGroupCard(
        title: l10n.settingsCategoryMemory,
        description: l10n.settingsMemorySubtitle,
        children: [_buildMemorySection(context, settingsController)],
      ),
      _SettingsSection.crons => _SettingsGroupCard(
        title: _localizedText(context, zh: '定时任务', en: 'Crons'),
        description: _localizedText(
          context,
          zh: '控制定时任务执行历史的保留与冷启动清理。清理 worker 仅在冷启动后异步运行一次，导致有超时兑底、独享运行锁、异常全部 silentLog，避免资源泄露与无限重试。',
          en: 'Controls retention and cold-start cleanup of cron execution history. The cleanup worker runs once per cold start with a hard timeout, single-flight lock and silentLog-only failures so it can never leak resources or loop indefinitely.',
        ),
        children: [_buildCronsSection(context, settingsController)],
      ),
      _SettingsSection.hermesTalker => _SettingsGroupCard(
        title: _localizedText(
          context,
          zh: 'Hermes Talker',
          en: 'Hermes Talker',
        ),
        description: _localizedText(
          context,
          zh: '配置 Hermes Talker 线程模板的自主学习：每 5 分钟扫描最近 7 天的会话，在后台派发受限子 Agent 更新记忆与技能。',
          en: 'Configure Hermes Talker self-learning: every 5 minutes a system cron scans sessions from the last 7 days and dispatches a restricted sub-agent to update memory and skills in the background.',
        ),
        children: [_buildHermesTalkerSection(context, settingsController)],
      ),
      _SettingsSection.editor => _SettingsGroupCard(
        title: _localizedText(context, zh: '编辑器', en: 'Editor'),
        description: _localizedText(
          context,
          zh: '管理各编程语言的 LSP 后端、安装根路径与下载辅助配置。保存后的配置会直接用于文件编辑器内的跳转、诊断、重命名和代码操作。',
          en: 'Manage per-language LSP backends, install roots, and download assistant settings. Saved mappings are applied directly to editor navigation, diagnostics, rename, and code actions.',
        ),
        children: [_buildEditorSection(context, settingsController)],
      ),
      _SettingsSection.appData => _SettingsGroupCard(
        title: _localizedText(context, zh: '应用数据', en: 'App Data'),
        description: _localizedText(
          context,
          zh: '管理 OpenHand 在本地占用的文件与数据库体积。所有清理动作都在后台 worker '
              '中运行，不会阻塞主线程；每个分类均需二次确认后才会真正删除。',
          en:
              'Manage the local files and database tables OpenHand owns on '
              'disk. Every cleanup runs on background workers — the UI '
              'thread stays responsive — and requires explicit second '
              'confirmation.',
        ),
        children: const [_DataCleanupSection()],
      ),
      _SettingsSection.system => _SettingsGroupCard(
        title: l10n.proxySectionTitle,
        description: l10n.proxySectionBody,
        children: [_SystemProxySection(controller: settingsController)],
      ),
      _SettingsSection.about => _SettingsGroupCard(
        title: l10n.aboutSectionTitle,
        description: l10n.aboutSectionBody,
        children: [
          _ReadonlySettingRow(label: l10n.aboutVersion, value: appInfo.version),
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
    };
  }

  Widget _buildAiModelsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final aiModels = settingsController.aiModels;
    final allowCommandRules = settingsController.aiAllowCommandRules;
    final denyCommandRules = settingsController.aiDenyCommandRules;
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
    final toolResultCompressionControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>(
            'settingsToolResultCompressionThresholdField',
          ),
          controller: _toolResultCompressionThresholdController,
          focusNode: _toolResultCompressionThresholdFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiToolResultCompressionThresholdLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiToolResultCompressionThresholdChars}',
          ),
          onSubmitted: (value) =>
              _saveToolResultCompressionThreshold(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsToolResultCompressionThresholdSaveButton',
            ),
            onPressed: () => _saveToolResultCompressionThreshold(
              context,
              _toolResultCompressionThresholdController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiToolResultCompressionThresholdSave),
          ),
        ),
      ],
    );
    final toolResultCompressionEnabledControl = Align(
      alignment: Alignment.centerLeft,
      child: Switch(
        key: const ValueKey<String>('settingsToolResultCompressionEnabledSwitch'),
        value: settingsController.aiToolResultCompressionEnabled,
        onChanged: (value) async {
          await settingsController.updateAiToolResultCompressionEnabled(value);
        },
      ),
    );
    final toolResultCompressionHeadTailWindowControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>(
            'settingsToolResultCompressionHeadTailWindowField',
          ),
          controller: _toolResultCompressionHeadTailWindowController,
          focusNode: _toolResultCompressionHeadTailWindowFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiToolResultCompressionHeadTailWindowLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiToolResultCompressionHeadTailWindowChars}',
          ),
          onSubmitted: (value) =>
              _saveToolResultCompressionHeadTailWindow(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsToolResultCompressionHeadTailWindowSaveButton',
            ),
            onPressed: () => _saveToolResultCompressionHeadTailWindow(
              context,
              _toolResultCompressionHeadTailWindowController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiToolResultCompressionHeadTailWindowSave),
          ),
        ),
      ],
    );
    final toolResultCompressionMaxPathHitsControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>(
            'settingsToolResultCompressionMaxPathHitsField',
          ),
          controller: _toolResultCompressionMaxPathHitsController,
          focusNode: _toolResultCompressionMaxPathHitsFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiToolResultCompressionMaxPathHitsLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiToolResultCompressionMaxPathHits}',
          ),
          onSubmitted: (value) =>
              _saveToolResultCompressionMaxPathHits(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsToolResultCompressionMaxPathHitsSaveButton',
            ),
            onPressed: () => _saveToolResultCompressionMaxPathHits(
              context,
              _toolResultCompressionMaxPathHitsController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiToolResultCompressionMaxPathHitsSave),
          ),
        ),
      ],
    );
    final writeToolSummaryMaxCharsControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsWriteToolSummaryMaxCharsField'),
          controller: _writeToolSummaryMaxCharsController,
          focusNode: _writeToolSummaryMaxCharsFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiWriteToolSummaryMaxCharsLabel,
            hintText: '${AppSettingsSnapshot.defaultAiWriteToolSummaryMaxChars}',
          ),
          onSubmitted: (value) =>
              _saveWriteToolSummaryMaxChars(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsWriteToolSummaryMaxCharsSaveButton',
            ),
            onPressed: () => _saveWriteToolSummaryMaxChars(
              context,
              _writeToolSummaryMaxCharsController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiWriteToolSummaryMaxCharsSave),
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
    final maxRecentErrorsControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsMaxRecentErrorsField'),
          controller: _maxRecentErrorsController,
          focusNode: _maxRecentErrorsFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiMaxRecentErrorsLabel,
            hintText: '${AppSettingsSnapshot.defaultAiMaxRecentErrors}',
          ),
          onSubmitted: (value) => _saveMaxRecentErrors(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>('settingsMaxRecentErrorsSaveButton'),
            onPressed: () => _saveMaxRecentErrors(
              context,
              _maxRecentErrorsController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiMaxRecentErrorsSave),
          ),
        ),
      ],
    );
    final maxPlanHistoryEntriesControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsMaxPlanHistoryEntriesField'),
          controller: _maxPlanHistoryEntriesController,
          focusNode: _maxPlanHistoryEntriesFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiMaxPlanHistoryEntriesLabel,
            hintText: '${AppSettingsSnapshot.defaultAiMaxPlanHistoryEntries}',
          ),
          onSubmitted: (value) => _saveMaxPlanHistoryEntries(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsMaxPlanHistoryEntriesSaveButton',
            ),
            onPressed: () => _saveMaxPlanHistoryEntries(
              context,
              _maxPlanHistoryEntriesController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiMaxPlanHistoryEntriesSave),
          ),
        ),
      ],
    );
    final maxTruncationContinuationsControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>(
            'settingsMaxTruncationContinuationsField',
          ),
          controller: _maxTruncationContinuationsController,
          focusNode: _maxTruncationContinuationsFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiMaxTruncationContinuationsLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiMaxTruncationContinuations}',
          ),
          onSubmitted: (value) =>
              _saveMaxTruncationContinuations(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsMaxTruncationContinuationsSaveButton',
            ),
            onPressed: () => _saveMaxTruncationContinuations(
              context,
              _maxTruncationContinuationsController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiMaxTruncationContinuationsSave),
          ),
        ),
      ],
    );
    final estimatedCharactersPerTokenControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>(
            'settingsEstimatedCharactersPerTokenField',
          ),
          controller: _estimatedCharactersPerTokenController,
          focusNode: _estimatedCharactersPerTokenFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiEstimatedCharactersPerTokenLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiEstimatedCharactersPerToken}',
          ),
          onSubmitted: (value) =>
              _saveEstimatedCharactersPerToken(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsEstimatedCharactersPerTokenSaveButton',
            ),
            onPressed: () => _saveEstimatedCharactersPerToken(
              context,
              _estimatedCharactersPerTokenController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiEstimatedCharactersPerTokenSave),
          ),
        ),
      ],
    );
    final imageSizeLimitControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsImageSizeLimitField'),
          controller: _imageSizeLimitController,
          focusNode: _imageSizeLimitFocusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: l10n.aiImageSizeLimitFieldLabel,
            hintText:
                (AppSettingsSnapshot.defaultAiImageSizeLimitBytes /
                        (1024 * 1024))
                    .toStringAsFixed(0),
            helperText: l10n.aiImageSizeLimitBody,
          ),
          onSubmitted: (value) => _saveImageSizeLimit(context, value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>('settingsImageSizeLimitSaveButton'),
            onPressed: () =>
                _saveImageSizeLimit(context, _imageSizeLimitController.text),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiImageSizeLimitSave),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSubsectionCard(
          title: _localizedText(context, zh: '会话设置', en: 'Session Settings'),
          description: _localizedText(
            context,
            zh: '配置新会话的默认行为，包括超时时间、自动标题、默认模式与权限。',
            en: 'Configure default behaviour for new sessions, including timeouts, auto-title, default mode, and permissions.',
          ),
          child: Column(
            children: [
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '发送超时时间（秒）',
                  en: 'Send Timeout (s)',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '建立 HTTP 连接并完成请求发送的最大等待时间，默认 60 秒。',
                  en: 'Maximum wait time to establish the HTTP connection and send the request. Default: 60 s.',
                ),
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _connectTimeoutController,
                      focusNode: _connectTimeoutFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '发送超时（秒）',
                          en: 'Send Timeout (s)',
                        ),
                        hintText:
                            '${AppSettingsSnapshot.defaultAiConnectTimeoutSeconds}',
                      ),
                      onSubmitted: (value) =>
                          _saveConnectTimeout(context, value),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _saveConnectTimeout(
                          context,
                          _connectTimeoutController.text,
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _localizedText(
                            context,
                            zh: '保存超时',
                            en: 'Save Timeout',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '响应超时时间（秒）',
                  en: 'Response Timeout (s)',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '非流式请求等待完整响应的最大时间，默认 120 秒。',
                  en: 'Maximum wait for a complete response in non-streaming mode. Default: 120 s.',
                ),
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _responseTimeoutController,
                      focusNode: _responseTimeoutFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '响应超时（秒）',
                          en: 'Response Timeout (s)',
                        ),
                        hintText:
                            '${AppSettingsSnapshot.defaultAiResponseTimeoutSeconds}',
                      ),
                      onSubmitted: (value) =>
                          _saveResponseTimeout(context, value),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _saveResponseTimeout(
                          context,
                          _responseTimeoutController.text,
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _localizedText(
                            context,
                            zh: '保存超时',
                            en: 'Save Timeout',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '等待超时时间（秒）',
                  en: 'Stream Idle Timeout (s)',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '流式响应中两次数据块之间的最大空闲等待时间，超时将中断请求并显示"Request timed out."，默认 120 秒。',
                  en: 'Maximum idle wait between stream chunks. Exceeding this causes "Request timed out.". Default: 120 s.',
                ),
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _streamIdleTimeoutController,
                      focusNode: _streamIdleTimeoutFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '等待超时（秒）',
                          en: 'Stream Idle Timeout (s)',
                        ),
                        hintText:
                            '${AppSettingsSnapshot.defaultAiStreamIdleTimeoutSeconds}',
                      ),
                      onSubmitted: (value) =>
                          _saveStreamIdleTimeout(context, value),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _saveStreamIdleTimeout(
                          context,
                          _streamIdleTimeoutController.text,
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _localizedText(
                            context,
                            zh: '保存超时',
                            en: 'Save Timeout',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: _localizedText(context, zh: '自动标题', en: 'Auto Title'),
                subtitle: _localizedText(
                  context,
                  zh: '开启后，新会话发送首条消息时将自动生成会话标题。',
                  en: 'When enabled, a title is automatically generated after the first message in a new session.',
                ),
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: Switch(
                    value: settingsController.aiAutoTitleEnabled,
                    onChanged: (value) =>
                        settingsController.updateAiAutoTitleEnabled(value),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '默认会话模式',
                  en: 'Default Session Mode',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '新会话的默认交互模式：对话（Chat）或规划（Plan）。',
                  en: 'Default interaction mode for new sessions: Chat or Plan.',
                ),
                control: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment<String>(
                        value: 'chat',
                        icon: const Icon(Icons.chat_outlined),
                        label: Text(
                          _localizedText(context, zh: '对话', en: 'Chat'),
                          softWrap: false,
                        ),
                      ),
                      ButtonSegment<String>(
                        value: 'plan',
                        icon: const Icon(Icons.account_tree_outlined),
                        label: Text(
                          _localizedText(context, zh: '规划', en: 'Plan'),
                          softWrap: false,
                        ),
                      ),
                    ],
                    selected: {settingsController.aiDefaultSessionMode},
                    onSelectionChanged: (values) {
                      if (values.isNotEmpty) {
                        settingsController.updateAiDefaultSessionMode(
                          values.first,
                        );
                      }
                    },
                  ),
                ),
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '默认全访问权限',
                  en: 'Default Full Access',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '开启后，新会话将默认使用全访问权限模式，允许 AI 直接执行文件与命令操作而无需逐一确认。',
                  en: 'When enabled, new sessions start in full-access mode, allowing the AI to execute file and command operations without per-action confirmation.',
                ),
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: Switch(
                    value: settingsController.aiDefaultFullAccessPermission,
                    onChanged: (value) => settingsController
                        .updateAiDefaultFullAccessPermission(value),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '用户画像',
                  en: 'User Profile',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '维护用于全局会话的用户画像（语言风格、关注领域、交流偏好等）。设置非空时，所有线程模板的内建系统提示词都会自动携带画像上下文，使 AI 回复更贴近你的习惯；自我学习也会增量更新这份画像。',
                  en: 'Maintain a global user profile (language style, focus areas, communication preferences). When non-empty, the profile is woven into the system prompt of every thread template so the AI feels personalised; self-learning incrementally refines it.',
                ),
                control: const Align(
                  alignment: Alignment.centerLeft,
                  child: _UserProfileSettingsButton(),
                ),
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!
                    .settingsThreadSessionManagementTitle,
                subtitle: AppLocalizations.of(context)!
                    .settingsThreadSessionManagementSubtitle,
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        showThreadSessionManagementDialog(context),
                    icon: const Icon(Icons.dynamic_feed_outlined),
                    label: Text(
                      AppLocalizations.of(context)!
                          .settingsThreadSessionManagementOpen,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSubsectionCard(
          title: _localizedText(
            context,
            zh: '模型提供商管理',
            en: 'Model Provider Management',
          ),
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 520),
                  // Use ListView.builder so that off-screen provider tiles
                  // (each tile renders a title row, icon button cluster and
                  // a Wrap of up to 20 model chips) are not built eagerly.
                  // With up to 20 providers, the previous Column-in-
                  // SingleChildScrollView built every tile on every rebuild
                  // of the settings page, which dominated Build time when
                  // opening the Settings section.
                  child: ListView.separated(
                    primary: false,
                    cacheExtent: 240,
                    itemCount: aiModels.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      return _AiModelTile(
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
                        onActiveModelChanged: (modelId) =>
                            settingsController.updateProviderActiveModel(
                              aiModels[index].id,
                              modelId,
                            ),
                      );
                    },
                  ),
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
                  zh: '工具调用输出压缩阈值',
                  en: 'Tool Call Output Compression Threshold',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '当某个工具调用返回的 raw 内容字符数超过该阈值时，OpenHand 会在拼装 conversation history 前将其压缩为「受影响路径+目的+首尾片段」的结构化摘要，释放 tokens。默认 1024。',
                  en: 'When a tool call returns more raw characters than this threshold, OpenHand condenses it into a structured summary (affected paths + purpose + head/tail snippet) before adding it to the conversation history. Defaults to 1024.',
                ),
                control: toolResultCompressionControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: l10n.aiToolResultCompressionEnabledLabel,
                subtitle: l10n.aiToolResultCompressionEnabledBody,
                control: toolResultCompressionEnabledControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: l10n.aiToolResultCompressionHeadTailWindowLabel,
                subtitle: l10n.aiToolResultCompressionHeadTailWindowBody,
                control: toolResultCompressionHeadTailWindowControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: l10n.aiToolResultCompressionMaxPathHitsLabel,
                subtitle: l10n.aiToolResultCompressionMaxPathHitsBody,
                control: toolResultCompressionMaxPathHitsControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: l10n.aiWriteToolSummaryMaxCharsLabel,
                subtitle: l10n.aiWriteToolSummaryMaxCharsBody,
                control: writeToolSummaryMaxCharsControl,
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
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: l10n.aiMaxRecentErrorsLabel,
                subtitle: l10n.aiMaxRecentErrorsBody,
                control: maxRecentErrorsControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: l10n.aiMaxPlanHistoryEntriesLabel,
                subtitle: l10n.aiMaxPlanHistoryEntriesBody,
                control: maxPlanHistoryEntriesControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: l10n.aiMaxTruncationContinuationsLabel,
                subtitle: l10n.aiMaxTruncationContinuationsBody,
                control: maxTruncationContinuationsControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: l10n.aiEstimatedCharactersPerTokenLabel,
                subtitle: l10n.aiEstimatedCharactersPerTokenBody,
                control: estimatedCharactersPerTokenControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '图片大小上限',
                  en: 'Image Size Limit',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '默认 1MB。用户附加的图片若超过这个大小，会在弹出图片编辑器之前先按比例自动压缩，并最终落盘到该上限以内，避免会话与提示词膨胀。',
                  en: 'Defaults to 1MB. Image attachments larger than this cap are auto-compressed before the editor opens and stored within the limit, keeping sessions and prompts compact.',
                ),
                control: imageSizeLimitControl,
                controlMaxWidth: 360,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSubsectionCard(
          title: _localizedText(context, zh: '成本控制', en: 'Cost Control'),
          description: _localizedText(
            context,
            zh: '通过冻结 prompt 静态前缀与协议层缓存断点来降低 token 成本。开启后：新会话创建时会冻结当前的内建工具/技能/MCP/指令/记忆作为不可变前缀；用户发出首条消息后会锁定服务商与模型；Anthropic 协议会自动注入 cache_control 断点。',
            en: 'Reduce token costs by freezing the prompt static prefix and inserting protocol-level cache breakpoints. When enabled: a new session freezes the current built-in tools / skills / MCP / instructions / memory as an immutable prefix; the provider and model are locked once the first user message is sent; the Anthropic adapter automatically injects cache_control breakpoints.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResponsiveSettingRow(
                title: _localizedText(
                  context,
                  zh: '启用输入缓存',
                  en: 'Enable Input Cache',
                ),
                subtitle: _localizedText(
                  context,
                  zh: '默认关闭。开启后，对所有线程模板、所有模型，新会话创建时即冻结其 prompt 静态前缀（系统提示/工具定义/技能列表/MCP/指令/记忆）。会话创建之后再修改技能、MCP、记忆等不会影响已存在的会话——只对此后新建的会话生效，以保证最大不可变性，最大化输入缓存命中。',
                  en: 'Disabled by default. When enabled, every newly created session — across all thread templates and models — freezes its prompt static prefix (system instructions / tool definitions / skills / MCP / instructions / memory). Subsequent edits to skills, MCP, memory, etc. do NOT affect existing sessions; they only take effect for sessions created afterward — ensuring maximum immutability and cache hit rate.',
                ),
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: Switch(
                    key: const ValueKey<String>(
                      'settingsAiInputCacheEnabledSwitch',
                    ),
                    value: settingsController.aiInputCacheEnabled,
                    onChanged: (value) async {
                      await settingsController
                          .updateAiInputCacheEnabled(value);
                    },
                  ),
                ),
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
              if (allowCommandRules.isEmpty)
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
                SizedBox(
                  height: math.min(360.0, allowCommandRules.length * 94.0),
                  child: ListView.separated(
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: allowCommandRules.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final rule = allowCommandRules[index];
                      return _AllowCommandRuleTile(
                        rule: rule,
                        onEdit: () => _showAllowCommandRuleDialog(
                          context,
                          initialRule: rule,
                        ),
                        onDelete: () => _deleteAllowCommandRule(context, rule),
                      );
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
              if (denyCommandRules.isEmpty)
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
                SizedBox(
                  height: math.min(360.0, denyCommandRules.length * 94.0),
                  child: ListView.separated(
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: denyCommandRules.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final rule = denyCommandRules[index];
                      return _DenyCommandRuleTile(
                        rule: rule,
                        onEdit: () => _showDenyCommandRuleDialog(
                          context,
                          initialRule: rule,
                        ),
                        onDelete: () => _deleteDenyCommandRule(context, rule),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildTelemetrySubsection(context, settingsController),
      ],
    );
  }

  Widget _buildTelemetrySubsection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    return _SettingsSubsectionCard(
      title: _localizedText(context, zh: '遥测', en: 'Telemetry'),
      description: _localizedText(
        context,
        zh: '开启后会捕获每条 AI 消息的原始响应、请求参数、耗时、错误等调试数据，方便在消息/会话审计弹窗中排查问题。',
        en: 'When enabled, OpenHand captures raw AI responses, request parameters, timings and errors so you can inspect them from message/session audit dialogs.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResponsiveSettingRow(
            title: _localizedText(context, zh: '开启调试', en: 'Debug Mode'),
            subtitle: _localizedText(
              context,
              zh: '默认关闭。开启后，在所有线程模板的消息卡片上鼠标悬停/聚焦时会显示【审计】按钮，会话顶部也会新增会话审计入口。',
              en: 'Off by default. When enabled, every message card exposes an Audit pill on hover/focus and each session toolbar shows a session-level Audit action.',
            ),
            control: Switch(
              key: const ValueKey<String>('settingsTelemetryDebugSwitch'),
              value: settingsController.telemetryDebugEnabled,
              onChanged: (value) async {
                final saved = await settingsController
                    .updateTelemetryDebugEnabled(value);
                if (!context.mounted || saved) {
                  return;
                }
                _showPersistenceFailureSnackBar(context);
              },
            ),
          ),
          const SizedBox(height: 18),
          _ResponsiveSettingRow(
            title: _localizedText(
              context,
              zh: '捕获原始响应',
              en: 'Capture Raw Payload',
            ),
            subtitle: _localizedText(
              context,
              zh: '默认开启。仅当调试开启时生效，将 AI 响应的原始 JSON/SSE 片段一并写入消息元数据，便于审计。',
              en: 'Enabled by default. Only active when debug mode is on. Attaches the raw JSON/SSE chunks to message metadata for auditing.',
            ),
            control: Switch(
              key: const ValueKey<String>('settingsTelemetryRawPayloadSwitch'),
              value: settingsController.telemetryCaptureRawPayload,
              onChanged: settingsController.telemetryDebugEnabled
                  ? (value) async {
                      final saved = await settingsController
                          .updateTelemetryCaptureRawPayload(value);
                      if (!context.mounted || saved) {
                        return;
                      }
                      _showPersistenceFailureSnackBar(context);
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 18),
          _ResponsiveSettingRow(
            title: _localizedText(
              context,
              zh: '捕获环境数据',
              en: 'Capture Environment',
            ),
            subtitle: _localizedText(
              context,
              zh: '默认关闭。仅当调试开启时生效。将工作目录、平台信息、进程环境变量（可能含敏感令牌）等写入消息元数据，便于深度排查，请谨慎开启。',
              en: 'Off by default. Only active when debug mode is on. Attaches working directory, platform details and process environment variables (may contain secrets) to message metadata — enable with care.',
            ),
            control: Switch(
              key: const ValueKey<String>(
                'settingsTelemetryCaptureEnvironmentSwitch',
              ),
              value: settingsController.telemetryCaptureEnvironment,
              onChanged: settingsController.telemetryDebugEnabled
                  ? (value) async {
                      final saved = await settingsController
                          .updateTelemetryCaptureEnvironment(value);
                      if (!context.mounted || saved) {
                        return;
                      }
                      _showPersistenceFailureSnackBar(context);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final bindings = settingsController.shortcutBindings;
    const actions = OpenHandShortcutAction.values;
    return _SettingsSubsectionCard(
      title: _localizedText(context, zh: '快捷键绑定', en: 'Shortcut Bindings'),
      description: _localizedText(
        context,
        zh: '点击录制后，按下新的组合键即可更新绑定。模型切换和会话切换会自动绕圈循环。',
        en: 'Click record, then press the new key combination to update a binding. Model and session switching wrap around automatically.',
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: PrimaryScrollController.none(
          child: Scrollbar(
            controller: _shortcutListScrollController,
            thumbVisibility: true,
            child: ListView.separated(
              controller: _shortcutListScrollController,
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: actions.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final action = actions[index];
                return _ShortcutBindingTile(
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
                );
              },
            ),
          ),
        ),
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

  Widget _buildCronsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final enabled = settingsController.cronAutoCleanupEnabled;
    final retention = settingsController.cronAutoCleanupRetentionDays;
    const minR = AppSettingsSnapshot.minCronAutoCleanupRetentionDays;
    const maxR = AppSettingsSnapshot.maxCronAutoCleanupRetentionDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResponsiveSettingRow(
          title: _localizedText(
            context,
            zh: '自动清理执行历史',
            en: 'Auto-cleanup execution history',
          ),
          subtitle: _localizedText(
            context,
            zh: '应用每次冷启动后，会异步启动一次清理 worker，删除超过保留天数的历史记录。worker 自带 single-flight、超时兜底与异常 silentLog，绝不无限重试或阻塞 UI。',
            en: 'On every cold start, an async worker runs once to delete history older than the retention window. The worker is single-flight, has a hard timeout, and silently logs failures so it can never block the UI or loop indefinitely.',
          ),
          control: Switch(
            value: enabled,
            onChanged: (value) async {
              final saved = await settingsController
                  .updateCronAutoCleanupEnabled(value);
              if (!context.mounted || saved) return;
              _showPersistenceFailureSnackBar(context);
            },
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _localizedText(
            context,
            zh: '保留天数：$retention 天',
            en: 'Retention window: $retention day(s)',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          min: minR.toDouble(),
          max: 30,
          divisions: 29,
          value: retention.clamp(minR, 30).toDouble(),
          label: '$retention',
          onChanged: enabled
              ? (value) async {
                  final saved = await settingsController
                      .updateCronAutoCleanupRetentionDays(value.round());
                  if (!context.mounted || saved) return;
                  _showPersistenceFailureSnackBar(context);
                }
              : null,
        ),
        Text(
          _localizedText(
            context,
            zh: '范围 $minR–$maxR 天，默认 7 天。下次冷启动时生效。',
            en: 'Range $minR–$maxR days; default 7. Takes effect on the next cold start.',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildHermesTalkerSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final enabled = settingsController.selfLearningEnabled;
    final concurrency = settingsController.selfLearningConcurrency;
    const minC = AppSettingsSnapshot.minSelfLearningConcurrency;
    const maxC = AppSettingsSnapshot.maxSelfLearningConcurrency;
    final flushMs = settingsController.selfLearningStreamFlushIntervalMs;
    const minFlushMs = AppSettingsSnapshot.minSelfLearningStreamFlushIntervalMs;
    const maxFlushMs = AppSettingsSnapshot.maxSelfLearningStreamFlushIntervalMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResponsiveSettingRow(
          title: _localizedText(
            context,
            zh: '启用自主学习',
            en: 'Enable self-learning',
          ),
          subtitle: _localizedText(
            context,
            zh: '关闭后，后台调度器跳过所有 Hermes Talker 会话；系统 Cron 条目会保留但不再派发子 Agent。',
            en: 'When off, the scheduler skips every Hermes Talker session. The system cron entry is preserved but never dispatches a sub-agent.',
          ),
          control: Switch(
            value: enabled,
            onChanged: (value) async {
              final saved = await settingsController.updateSelfLearningEnabled(
                value,
              );
              if (!context.mounted || saved) return;
              _showPersistenceFailureSnackBar(context);
            },
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _localizedText(
            context,
            zh: '并发 Worker 数：$concurrency',
            en: 'Concurrent workers: $concurrency',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          min: minC.toDouble(),
          max: maxC.toDouble(),
          divisions: maxC - minC,
          value: concurrency.toDouble(),
          label: '$concurrency',
          onChanged: enabled
              ? (value) async {
                  final saved = await settingsController
                      .updateSelfLearningConcurrency(value.round());
                  if (!context.mounted || saved) return;
                  _showPersistenceFailureSnackBar(context);
                }
              : null,
        ),
        Text(
          _localizedText(
            context,
            zh: '限制单轮 tick 同时派发的会话数 ($minC–$maxC)。默认 5。',
            en: 'Caps how many sessions can be dispatched in parallel per tick ($minC–$maxC). Defaults to 5.',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          AppLocalizations.of(context)!
              .selfLearningFlushIntervalLabel(flushMs),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          min: minFlushMs.toDouble(),
          max: maxFlushMs.toDouble(),
          divisions: ((maxFlushMs - minFlushMs) ~/ 100),
          value: flushMs.toDouble().clamp(
                minFlushMs.toDouble(),
                maxFlushMs.toDouble(),
              ),
          label: '${flushMs}ms',
          onChanged: (value) async {
            final saved = await settingsController
                .updateSelfLearningStreamFlushIntervalMs(value.round());
            if (!context.mounted || saved) return;
            _showPersistenceFailureSnackBar(context);
          },
        ),
        Text(
          AppLocalizations.of(context)!
              .selfLearningFlushIntervalHelper(minFlushMs, maxFlushMs),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        _ResponsiveSettingRow(
          title: _localizedText(
            context,
            zh: '显示自我学习消息',
            en: 'Show self-learning messages',
          ),
          subtitle: _localizedText(
            context,
            zh: '关闭后，对话中不再展示"自我学习"卡片（后台学习仍会运行）。默认开启。',
            en: 'When off, "self-learning" cards are hidden from the chat transcript (background learning still runs). Defaults to on.',
          ),
          control: Switch(
            value: settingsController.showSelfLearningMessages,
            onChanged: (value) async {
              final saved = await settingsController
                  .updateShowSelfLearningMessages(value);
              if (!context.mounted || saved) return;
              _showPersistenceFailureSnackBar(context);
            },
          ),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Builtin Tool Settings – builder & dialog methods
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBuiltinToolsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final configs = settingsController.builtinToolConfigs;
    final sorted = List<AiBuiltinToolConfig>.from(configs)
      ..sort((a, b) {
        final cmp = a.sortOrder.compareTo(b.sortOrder);
        return cmp != 0 ? cmp : a.kind.index.compareTo(b.kind.index);
      });
    final enabledCount = sorted.where((c) => c.enabled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSubsectionCard(
          title: _localizedText(
            context,
            zh: '工具目录总览',
            en: 'Tool Catalog Overview',
          ),
          description: _localizedText(
            context,
            zh:
                '当前共 ${sorted.length} 个内建工具，已启用 $enabledCount 个。'
                '可调整每个工具的名称、描述、Schema、优先级、排序和加载策略等。',
            en:
                '${sorted.length} built-in tools, $enabledCount enabled. '
                'Adjust name, description, schema, priority, sort order, and load strategy for each.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => _showBuiltinToolResetConfirmDialog(
                      context,
                      settingsController,
                    ),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(
                      _localizedText(context, zh: '重置全部', en: 'Reset All'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _toggleAllBuiltinTools(context, settingsController, true);
                    },
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      _localizedText(context, zh: '全部启用', en: 'Enable All'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _toggleAllBuiltinTools(
                        context,
                        settingsController,
                        false,
                      );
                    },
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    label: Text(
                      _localizedText(context, zh: '全部禁用', en: 'Disable All'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (sorted.isEmpty)
                _SettingsStateBox(
                  icon: Icons.build_circle_outlined,
                  title: _localizedText(
                    context,
                    zh: '没有内建工具配置',
                    en: 'No built-in tool configurations',
                  ),
                  body: _localizedText(
                    context,
                    zh: '点击"重置全部"恢复默认工具列表。',
                    en: 'Click "Reset All" to restore the default tool list.',
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: ListView.separated(
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: sorted.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final config = sorted[index];
                      return _BuiltinToolTile(
                        config: config,
                        isFirst: index == 0,
                        isLast: index == sorted.length - 1,
                        onToggle: (enabled) async {
                          final updated = config.copyWith(enabled: enabled);
                          await settingsController.updateBuiltinToolConfig(
                            updated,
                          );
                        },
                        onEdit: () => _showBuiltinToolEditorDialog(
                          context,
                          settingsController,
                          config: config,
                        ),
                        onMoveUp: index > 0
                            ? () {
                                final realOldIndex = configs.indexOf(config);
                                final realNewIndex = configs.indexOf(
                                  sorted[index - 1],
                                );
                                if (realOldIndex >= 0 && realNewIndex >= 0) {
                                  settingsController.moveBuiltinToolConfig(
                                    realOldIndex,
                                    realNewIndex,
                                  );
                                }
                              }
                            : null,
                        onMoveDown: index < sorted.length - 1
                            ? () {
                                final realOldIndex = configs.indexOf(config);
                                final realNewIndex = configs.indexOf(
                                  sorted[index + 1],
                                );
                                if (realOldIndex >= 0 && realNewIndex >= 0) {
                                  settingsController.moveBuiltinToolConfig(
                                    realOldIndex,
                                    realNewIndex,
                                  );
                                }
                              }
                            : null,
                        onDelete: config.isCustom
                            ? () => _confirmDeleteBuiltinTool(
                                context,
                                settingsController,
                                config,
                              )
                            : null,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _toggleAllBuiltinTools(
    BuildContext context,
    SettingsController settingsController,
    bool enabled,
  ) async {
    final configs = settingsController.builtinToolConfigs;
    final updated = configs
        .map((c) => c.copyWith(enabled: enabled))
        .toList(growable: false);
    final saved = await settingsController.updateBuiltinToolConfigs(updated);
    if (!context.mounted || saved) return;
    _showPersistenceFailureSnackBar(context);
  }

  Future<void> _showBuiltinToolResetConfirmDialog(
    BuildContext context,
    SettingsController settingsController,
  ) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.restart_alt_rounded),
          title: Text(
            _localizedText(
              context,
              zh: '重置内建工具配置',
              en: 'Reset Built-in Tool Configs',
            ),
          ),
          content: Text(
            _localizedText(
              context,
              zh:
                  '这将把所有内建工具配置恢复为出厂默认值，包括名称、描述、'
                  'Schema 覆盖、优先级、排序和加载策略。此操作不可撤销。',
              en:
                  'This will restore all built-in tool configurations to factory '
                  'defaults, including name, description, schema overrides, '
                  'priority, sort order, and load strategy. This cannot be undone.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_localizedText(context, zh: '取消', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_localizedText(context, zh: '重置', en: 'Reset')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    final saved = await settingsController.resetBuiltinToolConfigs();
    if (!context.mounted || saved) return;
    _showPersistenceFailureSnackBar(context);
  }

  Future<void> _confirmDeleteBuiltinTool(
    BuildContext context,
    SettingsController settingsController,
    AiBuiltinToolConfig config,
  ) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.delete_outline_rounded),
          title: Text(
            _localizedText(context, zh: '删除自定义工具', en: 'Delete Custom Tool'),
          ),
          content: Text(
            _localizedText(
              context,
              zh: '确定要删除 "${config.effectiveName}" 吗？此操作不可撤销。',
              en:
                  'Are you sure you want to delete "${config.effectiveName}"? '
                  'This cannot be undone.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_localizedText(context, zh: '取消', en: 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_localizedText(context, zh: '删除', en: 'Delete')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    final saved = await settingsController.removeBuiltinToolConfig(config.kind);
    if (!context.mounted || saved) return;
    _showPersistenceFailureSnackBar(context);
  }

  Future<void> _showBuiltinToolEditorDialog(
    BuildContext context,
    SettingsController settingsController, {
    required AiBuiltinToolConfig config,
  }) async {
    final defaults = AiToolRuntimeService.builtinToolDefault(config.kind);
    final result = await showAnimatedDialog<AiBuiltinToolConfig>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _BuiltinToolEditorDialog(
          initial: config,
          defaultName: defaults?.definition.name,
          defaultDescription: defaults?.definition.description,
          defaultParameters: defaults?.definition.parameters,
        );
      },
    );
    if (result == null || !context.mounted) return;
    final saved = await settingsController.updateBuiltinToolConfig(result);
    if (!context.mounted || saved) return;
    _showPersistenceFailureSnackBar(context);
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

  Future<void> _saveConnectTimeout(
    BuildContext context,
    String rawValue,
  ) async {
    final parsedValue = int.tryParse(rawValue.trim());
    const min = AppSettingsSnapshot.minAiConnectTimeoutSeconds;
    const max = AppSettingsSnapshot.maxAiConnectTimeoutSeconds;
    if (parsedValue == null || parsedValue < min || parsedValue > max) {
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '请输入 $min–$max 之间的秒数。',
          en: 'Enter a value between $min and $max seconds.',
        ),
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiConnectTimeoutSeconds(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _connectTimeoutController.text =
          '${context.read<SettingsController>().aiConnectTimeoutSeconds}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _connectTimeoutController.text = '$parsedValue';
    _showSnackBar(
      context,
      _localizedText(context, zh: '发送超时时间已保存。', en: 'Send timeout saved.'),
    );
  }

  Future<void> _saveResponseTimeout(
    BuildContext context,
    String rawValue,
  ) async {
    final parsedValue = int.tryParse(rawValue.trim());
    const min = AppSettingsSnapshot.minAiResponseTimeoutSeconds;
    const max = AppSettingsSnapshot.maxAiResponseTimeoutSeconds;
    if (parsedValue == null || parsedValue < min || parsedValue > max) {
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '请输入 $min–$max 之间的秒数。',
          en: 'Enter a value between $min and $max seconds.',
        ),
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiResponseTimeoutSeconds(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _responseTimeoutController.text =
          '${context.read<SettingsController>().aiResponseTimeoutSeconds}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _responseTimeoutController.text = '$parsedValue';
    _showSnackBar(
      context,
      _localizedText(context, zh: '响应超时时间已保存。', en: 'Response timeout saved.'),
    );
  }

  Future<void> _saveStreamIdleTimeout(
    BuildContext context,
    String rawValue,
  ) async {
    final parsedValue = int.tryParse(rawValue.trim());
    const min = AppSettingsSnapshot.minAiStreamIdleTimeoutSeconds;
    const max = AppSettingsSnapshot.maxAiStreamIdleTimeoutSeconds;
    if (parsedValue == null || parsedValue < min || parsedValue > max) {
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '请输入 $min–$max 之间的秒数。',
          en: 'Enter a value between $min and $max seconds.',
        ),
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiStreamIdleTimeoutSeconds(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _streamIdleTimeoutController.text =
          '${context.read<SettingsController>().aiStreamIdleTimeoutSeconds}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _streamIdleTimeoutController.text = '$parsedValue';
    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: '等待超时时间已保存。',
        en: 'Stream idle timeout saved.',
      ),
    );
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

  Future<void> _saveToolResultCompressionThreshold(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue <= 0) {
      _showSnackBar(context, l10n.aiToolResultCompressionThresholdInvalid);
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiToolResultCompressionThresholdChars(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _toolResultCompressionThresholdController.text =
          '${context.read<SettingsController>().aiToolResultCompressionThresholdChars}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _toolResultCompressionThresholdController.text =
        '${context.read<SettingsController>().aiToolResultCompressionThresholdChars}';
    _showSnackBar(context, l10n.aiToolResultCompressionThresholdSaved);
  }

  Future<void> _saveToolResultCompressionHeadTailWindow(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue < 0 || parsedValue > 8192) {
      _showSnackBar(
        context,
        l10n.aiToolResultCompressionHeadTailWindowInvalid,
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiToolResultCompressionHeadTailWindowChars(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _toolResultCompressionHeadTailWindowController.text =
          '${context.read<SettingsController>().aiToolResultCompressionHeadTailWindowChars}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _toolResultCompressionHeadTailWindowController.text =
        '${context.read<SettingsController>().aiToolResultCompressionHeadTailWindowChars}';
    _showSnackBar(context, l10n.aiToolResultCompressionHeadTailWindowSaved);
  }

  Future<void> _saveToolResultCompressionMaxPathHits(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue < 0 || parsedValue > 200) {
      _showSnackBar(context, l10n.aiToolResultCompressionMaxPathHitsInvalid);
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiToolResultCompressionMaxPathHits(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _toolResultCompressionMaxPathHitsController.text =
          '${context.read<SettingsController>().aiToolResultCompressionMaxPathHits}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _toolResultCompressionMaxPathHitsController.text =
        '${context.read<SettingsController>().aiToolResultCompressionMaxPathHits}';
    _showSnackBar(context, l10n.aiToolResultCompressionMaxPathHitsSaved);
  }

  Future<void> _saveWriteToolSummaryMaxChars(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue < 0 || parsedValue > 8192) {
      _showSnackBar(context, l10n.aiWriteToolSummaryMaxCharsInvalid);
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiWriteToolSummaryMaxChars(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _writeToolSummaryMaxCharsController.text =
          '${context.read<SettingsController>().aiWriteToolSummaryMaxChars}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _writeToolSummaryMaxCharsController.text =
        '${context.read<SettingsController>().aiWriteToolSummaryMaxChars}';
    _showSnackBar(context, l10n.aiWriteToolSummaryMaxCharsSaved);
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

  Future<void> _saveMaxRecentErrors(BuildContext context, String rawValue) async {
    final l10n = AppLocalizations.of(context)!;
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null ||
        parsed < AppSettingsSnapshot.minAiMaxRecentErrors ||
        parsed > AppSettingsSnapshot.maxAiMaxRecentErrors) {
      _showSnackBar(context, l10n.aiMaxRecentErrorsInvalid);
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiMaxRecentErrors(parsed);
    if (!context.mounted) return;
    if (!saved) {
      _maxRecentErrorsController.text =
          '${context.read<SettingsController>().aiMaxRecentErrors}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _maxRecentErrorsController.text =
        '${context.read<SettingsController>().aiMaxRecentErrors}';
    _showSnackBar(context, l10n.aiMaxRecentErrorsSaved);
  }

  Future<void> _saveMaxPlanHistoryEntries(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null ||
        parsed < AppSettingsSnapshot.minAiMaxPlanHistoryEntries ||
        parsed > AppSettingsSnapshot.maxAiMaxPlanHistoryEntries) {
      _showSnackBar(context, l10n.aiMaxPlanHistoryEntriesInvalid);
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiMaxPlanHistoryEntries(parsed);
    if (!context.mounted) return;
    if (!saved) {
      _maxPlanHistoryEntriesController.text =
          '${context.read<SettingsController>().aiMaxPlanHistoryEntries}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _maxPlanHistoryEntriesController.text =
        '${context.read<SettingsController>().aiMaxPlanHistoryEntries}';
    _showSnackBar(context, l10n.aiMaxPlanHistoryEntriesSaved);
  }

  Future<void> _saveMaxTruncationContinuations(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null ||
        parsed < AppSettingsSnapshot.minAiMaxTruncationContinuations ||
        parsed > AppSettingsSnapshot.maxAiMaxTruncationContinuations) {
      _showSnackBar(context, l10n.aiMaxTruncationContinuationsInvalid);
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiMaxTruncationContinuations(parsed);
    if (!context.mounted) return;
    if (!saved) {
      _maxTruncationContinuationsController.text =
          '${context.read<SettingsController>().aiMaxTruncationContinuations}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _maxTruncationContinuationsController.text =
        '${context.read<SettingsController>().aiMaxTruncationContinuations}';
    _showSnackBar(context, l10n.aiMaxTruncationContinuationsSaved);
  }

  Future<void> _saveEstimatedCharactersPerToken(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null ||
        parsed < AppSettingsSnapshot.minAiEstimatedCharactersPerToken ||
        parsed > AppSettingsSnapshot.maxAiEstimatedCharactersPerToken) {
      _showSnackBar(context, l10n.aiEstimatedCharactersPerTokenInvalid);
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiEstimatedCharactersPerToken(parsed);
    if (!context.mounted) return;
    if (!saved) {
      _estimatedCharactersPerTokenController.text =
          '${context.read<SettingsController>().aiEstimatedCharactersPerToken}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _estimatedCharactersPerTokenController.text =
        '${context.read<SettingsController>().aiEstimatedCharactersPerToken}';
    _showSnackBar(context, l10n.aiEstimatedCharactersPerTokenSaved);
  }

  /// Renders [bytes] as a human-friendly MB value used by the limit field.
  ///
  /// Examples: `1048576 -> '1'`, `1572864 -> '1.5'`. Trims trailing
  /// zeros so values like `2.0` show as `'2'`.
  String _formatImageSizeLimitInput(int bytes) {
    final mb = bytes / (1024 * 1024);
    final fixed = mb.toStringAsFixed(2);
    final trimmed = fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return trimmed.isEmpty ? '1' : trimmed;
  }

  Future<void> _saveImageSizeLimit(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = double.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue <= 0) {
      _showSnackBar(context, l10n.aiImageSizeLimitInvalid);
      return;
    }
    final bytes = (parsedValue * 1024 * 1024).round();
    final saved = await context
        .read<SettingsController>()
        .updateAiImageSizeLimitBytes(bytes);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _imageSizeLimitController.text = _formatImageSizeLimitInput(
        context.read<SettingsController>().aiImageSizeLimitBytes,
      );
      _showPersistenceFailureSnackBar(context);
      return;
    }
    final effectiveBytes = context
        .read<SettingsController>()
        .aiImageSizeLimitBytes;
    _imageSizeLimitController.text = _formatImageSizeLimitInput(effectiveBytes);
    _showSnackBar(context, l10n.aiImageSizeLimitSaved);
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
      showFriendlyErrorSnackBar(
        context,
        message: l10n.aiModelTestFailure(
          model.providerLabel,
          _normalizeAiModelTestMessage(error.message, l10n.chatRequestFailed),
        ),
        fallback: l10n.chatRequestFailed,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context)!;
      showFriendlyErrorSnackBar(
        context,
        message: l10n.aiModelTestFailure(
          model.providerLabel,
          _normalizeAiModelTestMessage('$error', l10n.chatRequestFailed),
        ),
        fallback: l10n.chatRequestFailed,
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
    // 保留换行，仅压缩单行内连续空格。这样上游传下来的
    // 「现象 / 原因 / 建议」三段式中英双语文案能进入下游 SnackBar
    // 与「详情 / Details」对话框，避免原本的多行诊断全部被推成
    // 一句读不顺的长句。
    final lines = raw
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((line) => line.isNotEmpty);
    final normalized = lines.join('\n').trim();
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

  Future<void> _showEditorShortcutRecorderDialog(
    BuildContext context,
    EditorShortcutAction action,
  ) async {
    final settingsController = context.read<SettingsController>();
    final shortcutBinding = await showAnimatedDialog<List<int>>(
      context: context,
      builder: (dialogContext) {
        return _ShortcutRecorderDialog(
          title: _editorShortcutActionTitle(dialogContext, action),
          initialKeyIds:
              settingsController.editorShortcutBindings[action] ??
              const <int>[],
        );
      },
    );
    if (!context.mounted || shortcutBinding == null) {
      return;
    }
    final saved = await settingsController.updateEditorShortcutBinding(
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
        zh: '编辑器快捷键已更新。',
        en: 'The editor shortcut has been updated.',
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

  String _editorShortcutActionTitle(
    BuildContext context,
    EditorShortcutAction action,
  ) {
    return switch (action) {
      EditorShortcutAction.saveFile => _localizedText(
        context,
        zh: '保存文件',
        en: 'Save File',
      ),
      EditorShortcutAction.triggerCompletion => _localizedText(
        context,
        zh: '触发智能补全',
        en: 'Trigger Completion',
      ),
      EditorShortcutAction.showSignatureHelp => _localizedText(
        context,
        zh: '显示签名帮助',
        en: 'Show Signature Help',
      ),
      EditorShortcutAction.find => _localizedText(
        context,
        zh: '查找',
        en: 'Find',
      ),
      EditorShortcutAction.replace => _localizedText(
        context,
        zh: '查找替换',
        en: 'Find and Replace',
      ),
      EditorShortcutAction.goToLine => _localizedText(
        context,
        zh: '跳转到行',
        en: 'Go to Line',
      ),
      EditorShortcutAction.showDocumentSymbols => _localizedText(
        context,
        zh: '文档符号',
        en: 'Document Symbols',
      ),
      EditorShortcutAction.showWorkspaceSymbols => _localizedText(
        context,
        zh: '全局符号',
        en: 'Workspace Symbols',
      ),
      EditorShortcutAction.goToDefinition => _localizedText(
        context,
        zh: '跳转到定义',
        en: 'Go to Definition',
      ),
      EditorShortcutAction.findReferences => _localizedText(
        context,
        zh: '查找引用',
        en: 'Find References',
      ),
      EditorShortcutAction.goToImplementation => _localizedText(
        context,
        zh: '跳转到实现',
        en: 'Go to Implementation',
      ),
      EditorShortcutAction.showHoverInfo => _localizedText(
        context,
        zh: '显示悬浮信息',
        en: 'Show Hover Info',
      ),
      EditorShortcutAction.renameSymbol => _localizedText(
        context,
        zh: '重命名符号',
        en: 'Rename Symbol',
      ),
      EditorShortcutAction.showCodeActions => _localizedText(
        context,
        zh: '代码操作',
        en: 'Code Actions',
      ),
      EditorShortcutAction.formatDocument => _localizedText(
        context,
        zh: '格式化文档',
        en: 'Format Document',
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

  String _editorShortcutActionSubtitle(
    BuildContext context,
    EditorShortcutAction action,
  ) {
    final defaultLabel = formatShortcutLabel(
      defaultEditorShortcutBindings()[action] ?? const <int>[],
    );
    return switch (action) {
      EditorShortcutAction.saveFile => _localizedText(
        context,
        zh: '默认 $defaultLabel，保存当前正在编辑的文件。',
        en: 'Defaults to $defaultLabel and saves the current file.',
      ),
      EditorShortcutAction.triggerCompletion => _localizedText(
        context,
        zh: '默认 $defaultLabel，主动弹出智能补全候选列表。',
        en: 'Defaults to $defaultLabel and opens the completion popup on demand.',
      ),
      EditorShortcutAction.showSignatureHelp => _localizedText(
        context,
        zh: '默认 $defaultLabel，显示当前调用位置的方法签名、参数解释和文档摘要。',
        en: 'Defaults to $defaultLabel and shows method signatures, parameter details, and summary docs for the current call site.',
      ),
      EditorShortcutAction.find => _localizedText(
        context,
        zh: '默认 $defaultLabel，打开或关闭查找面板。',
        en: 'Defaults to $defaultLabel and toggles the find panel.',
      ),
      EditorShortcutAction.replace => _localizedText(
        context,
        zh: '默认 $defaultLabel，打开或关闭替换面板。',
        en: 'Defaults to $defaultLabel and toggles the replace panel.',
      ),
      EditorShortcutAction.goToLine => _localizedText(
        context,
        zh: '默认 $defaultLabel，打开或关闭跳转到行面板。',
        en: 'Defaults to $defaultLabel and toggles the go-to-line panel.',
      ),
      EditorShortcutAction.showDocumentSymbols => _localizedText(
        context,
        zh: '默认 $defaultLabel，打开或关闭当前文件的符号列表。',
        en: 'Defaults to $defaultLabel and toggles the symbol list for the current file.',
      ),
      EditorShortcutAction.showWorkspaceSymbols => _localizedText(
        context,
        zh: '默认 $defaultLabel，打开或关闭全局符号检索面板。',
        en: 'Defaults to $defaultLabel and toggles the workspace symbol search panel.',
      ),
      EditorShortcutAction.goToDefinition => _localizedText(
        context,
        zh: '默认 $defaultLabel，跳转到当前符号定义。',
        en: 'Defaults to $defaultLabel and jumps to the current symbol definition.',
      ),
      EditorShortcutAction.findReferences => _localizedText(
        context,
        zh: '默认 $defaultLabel，查找当前符号的引用位置。',
        en: 'Defaults to $defaultLabel and finds references for the current symbol.',
      ),
      EditorShortcutAction.goToImplementation => _localizedText(
        context,
        zh: '默认 $defaultLabel，跳转到当前符号的实现位置。',
        en: 'Defaults to $defaultLabel and jumps to the current implementation.',
      ),
      EditorShortcutAction.showHoverInfo => _localizedText(
        context,
        zh: '默认 $defaultLabel，显示当前位置的类型或文档信息。',
        en: 'Defaults to $defaultLabel and shows type or documentation info at the current position.',
      ),
      EditorShortcutAction.renameSymbol => _localizedText(
        context,
        zh: '默认 $defaultLabel，发起当前符号重命名。',
        en: 'Defaults to $defaultLabel and starts rename for the current symbol.',
      ),
      EditorShortcutAction.showCodeActions => _localizedText(
        context,
        zh: '默认 $defaultLabel，显示可用的代码操作列表。',
        en: 'Defaults to $defaultLabel and shows available code actions.',
      ),
      EditorShortcutAction.formatDocument => _localizedText(
        context,
        zh: '默认 $defaultLabel，格式化当前编程文件；当选中多行时，Shift+Tab 仍优先执行反向缩进。',
        en: 'Defaults to $defaultLabel and formats the current programming file; Shift+Tab still outdents first when a multi-line selection is active.',
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

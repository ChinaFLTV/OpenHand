import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
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
import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../app/support/system_proxy.dart';
import '../../app/support/url_validation.dart';
import '../../app/theme/openhand_theme_preset.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/appear_once.dart';
import '../../shared/widgets/error_snackbar.dart';
import '../../shared/widgets/first_frame_pulse_box.dart';
import '../../shared/widgets/highlight_pulse.dart';
import '../../shared/widgets/key_tweakable_slider.dart';
import '../../shared/widgets/micro_press_feedback.dart';
import '../../shared/widgets/model_search_selector.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../../shared/widgets/openhand_snack_bar.dart';
import '../../shared/widgets/rolling_text.dart';
import '../ai/ai_session_controller.dart';
import '../ai/model/ai_allow_command_rule.dart';
import '../ai/model/ai_builtin_tool_config.dart';
import '../ai/model/ai_deny_command_rule.dart';
import '../ai/model/ai_lsp_backend_catalog.dart';
import '../ai/model/ai_lsp_language_settings.dart';
import '../ai/model/ai_model_catalog.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/service/ai_chat_service.dart';
import '../ai/service/ai_file_mutation_ledger.dart';
import '../ai/service/ai_image_generation_service.dart';
import '../ai/service/ai_lsp_managed_install_service.dart';
import '../ai/service/ai_model_scanner.dart';
import '../ai/service/ai_protocol_adapter.dart';
import '../ai/service/ai_tool_execution_registry.dart';
import '../ai/service/ai_tool_runtime_service.dart';
import '../ai/service/web_search/web_search_cache_store.dart';
import '../crons/crons_controller.dart';
import '../hardness/hardness_cli_catalog.dart';
import '../mcp/mcp_controller.dart';
import '../mcp/model/mcp_lazy_loading_mode.dart';
import '../mcp/model/mcp_stdio_mirror_mode.dart';
import '../mcp/service/mcp_tool_discovery_service.dart'
    show
        McpMirrorEffectiveSource,
        resetMcpStdioIsolatedCache,
        resolveMcpMirrorEffectiveSource;
import '../mcp/service/tool_search_history_export_prefs.dart';
import '../mcp/service/tool_search_replay_dispatcher.dart';
import '../mcp/widgets/tool_search_loaded_dialog.dart';
import '../memory/memory_controller.dart';
import '../skills/skills_controller.dart';
import 'data_cleanup/data_cleanup_models.dart';
import 'data_cleanup/data_cleanup_service.dart';
import 'thread_session_management_dialog.dart';
import 'widgets/prompt_cache_breakpoint_bar.dart';

part '_settings_ai_model_editor.dart';
part '_settings_editor_lsp.dart';
part '_settings_command_rules.dart';
part '_settings_shortcut_widgets.dart';
part '_settings_animation_sections.dart';
part '_settings_builtin_tools.dart';
part '_settings_web_search_editor.dart';
part '_settings_helper_widgets.dart';
part '_settings_user_profile.dart';
part '_settings_data_cleanup.dart';
part '_settings_system_proxy.dart';
part '_settings_proxy_test_dialog.dart';
part '_settings_active_tool_calls.dart';

typedef _SettingsPathGetter = String Function(SettingsController controller);
typedef _SettingsPathOperation = Future<bool> Function(String path);

enum _SettingsSection {
  header,
  persistenceIssue,
  general,
  shortcuts,
  ai,
  activeToolCalls,
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
    builder: (dialogContext) =>
        _AiModelEditorDialog(initialModel: initialModel),
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
  late final TextEditingController _aiInputCacheUpdateIntervalController;
  late final FocusNode _aiInputCacheUpdateIntervalFocusNode;
  late final TextEditingController _aiInputCacheBreakpointCountController;
  late final FocusNode _aiInputCacheBreakpointCountFocusNode;
  late final TextEditingController _aiBudgetUsdPerSessionController;
  late final FocusNode _aiBudgetUsdPerSessionFocusNode;
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
  late final TextEditingController _mcpLazyLoadingThresholdController;
  late final FocusNode _mcpLazyLoadingThresholdFocusNode;
  late final TextEditingController _mcpAutoProbeConcurrencyController;
  late final FocusNode _mcpAutoProbeConcurrencyFocusNode;
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
    _aiInputCacheUpdateIntervalController = TextEditingController();
    _aiInputCacheUpdateIntervalFocusNode = FocusNode();
    _aiInputCacheBreakpointCountController = TextEditingController();
    _aiInputCacheBreakpointCountFocusNode = FocusNode();
    _aiBudgetUsdPerSessionController = TextEditingController();
    _aiBudgetUsdPerSessionFocusNode = FocusNode();
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
    _mcpLazyLoadingThresholdController = TextEditingController();
    _mcpLazyLoadingThresholdFocusNode = FocusNode();
    _mcpAutoProbeConcurrencyController = TextEditingController();
    _mcpAutoProbeConcurrencyFocusNode = FocusNode();
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
    _aiInputCacheUpdateIntervalController.dispose();
    _aiInputCacheUpdateIntervalFocusNode.dispose();
    _aiInputCacheBreakpointCountController.dispose();
    _aiInputCacheBreakpointCountFocusNode.dispose();
    _aiBudgetUsdPerSessionController.dispose();
    _aiBudgetUsdPerSessionFocusNode.dispose();
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
    _mcpLazyLoadingThresholdController.dispose();
    _mcpLazyLoadingThresholdFocusNode.dispose();
    _mcpAutoProbeConcurrencyController.dispose();
    _mcpAutoProbeConcurrencyFocusNode.dispose();
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
    final aiInputCacheUpdateIntervalText =
        '${settingsController.aiInputCacheUpdateInterval}';
    if (!_aiInputCacheUpdateIntervalFocusNode.hasFocus &&
        _aiInputCacheUpdateIntervalController.text !=
            aiInputCacheUpdateIntervalText) {
      _aiInputCacheUpdateIntervalController.text =
          aiInputCacheUpdateIntervalText;
    }
    final aiInputCacheBreakpointCountText =
        '${settingsController.aiInputCacheBreakpointCount}';
    if (!_aiInputCacheBreakpointCountFocusNode.hasFocus &&
        _aiInputCacheBreakpointCountController.text !=
            aiInputCacheBreakpointCountText) {
      _aiInputCacheBreakpointCountController.text =
          aiInputCacheBreakpointCountText;
    }
    final aiBudgetUsdPerSessionText = _formatBudgetUsd(
      settingsController.aiBudgetUsdPerSession,
    );
    if (!_aiBudgetUsdPerSessionFocusNode.hasFocus &&
        _aiBudgetUsdPerSessionController.text != aiBudgetUsdPerSessionText) {
      _aiBudgetUsdPerSessionController.text = aiBudgetUsdPerSessionText;
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
    final mcpLazyLoadingThresholdText =
        '${settingsController.mcpLazyLoadingThresholdTokens}';
    if (!_mcpLazyLoadingThresholdFocusNode.hasFocus &&
        _mcpLazyLoadingThresholdController.text !=
            mcpLazyLoadingThresholdText) {
      _mcpLazyLoadingThresholdController.text = mcpLazyLoadingThresholdText;
    }
    final mcpAutoProbeConcurrencyText =
        '${settingsController.mcpAutoProbeConcurrency}';
    if (!_mcpAutoProbeConcurrencyFocusNode.hasFocus &&
        _mcpAutoProbeConcurrencyController.text !=
            mcpAutoProbeConcurrencyText) {
      _mcpAutoProbeConcurrencyController.text = mcpAutoProbeConcurrencyText;
    }

    final sections = <_SettingsSection>[
      _SettingsSection.header,
      if (settingsController.persistenceIssue != null)
        _SettingsSection.persistenceIssue,
      _SettingsSection.general,
      _SettingsSection.shortcuts,
      _SettingsSection.ai,
      _SettingsSection.activeToolCalls,
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
      child: Stack(
        children: [
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
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
          // Top-edge highlight pulse fired whenever any settings mutation
          // is successfully persisted. Subscribes to the controller's
          // `saveSuccessSignal` so individual `_save*` paths don't have
          // to wire up per-row notifiers. Honors reduceMotion via the
          // pulse widget itself.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: _SettingsSavePulse(
                signal: settingsController.saveSuccessSignal,
              ),
            ),
          ),
        ],
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
          _ResponsiveSettingRow(
            title: l10n.settingsReduceMotionLabel,
            subtitle: l10n.settingsReduceMotionBody,
            controlMaxWidth: 120,
            control: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Switch(
                value: settingsController.reduceMotion,
                onChanged: (value) async {
                  final saved = await settingsController.updateReduceMotion(
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
          _ChipAnimationSettingsSection(settingsController: settingsController),
          _ListItemAnimationSettingsSection(
            settingsController: settingsController,
          ),
        ],
      ),
      _SettingsSection.shortcuts => _SettingsGroupCard(
        title: AppLocalizations.of(context)!.settingsShortcuts,
        description: AppLocalizations.of(
          context,
        )!.settingsConfigureKeyCombinationsForCommonActions,
        children: [_buildShortcutsSection(context, settingsController)],
      ),
      _SettingsSection.ai => _SettingsGroupCard(
        title: l10n.settingsCategoryAi,
        description: l10n.settingsAiSubtitle,
        children: [_buildAiModelsSection(context, settingsController)],
      ),
      _SettingsSection.activeToolCalls => const Column(
        children: [
          _ActiveToolCallsPanel(),
          SizedBox(height: 18),
          _ToolHardeningParamsPanel(),
        ],
      ),
      _SettingsSection.builtinTools => _SettingsGroupCard(
        title: AppLocalizations.of(context)!.settingsBuiltInTools,
        description: AppLocalizations.of(
          context,
        )!.settingsManageTheBuiltInAiTools,
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
        title: AppLocalizations.of(context)!.settingsCrons,
        description: AppLocalizations.of(
          context,
        )!.settingsControlsRetentionAndColdStartCleanup,
        children: [_buildCronsSection(context, settingsController)],
      ),
      _SettingsSection.hermesTalker => _SettingsGroupCard(
        title: AppLocalizations.of(context)!.settingsHermesTalker,
        description: AppLocalizations.of(
          context,
        )!.settingsConfigureHermesTalkerSelfLearningEvery,
        children: [_buildHermesTalkerSection(context, settingsController)],
      ),
      _SettingsSection.editor => _SettingsGroupCard(
        title: AppLocalizations.of(context)!.settingsEditor,
        description: AppLocalizations.of(
          context,
        )!.settingsManagePerLanguageLspBackendsInstall,
        children: [_buildEditorSection(context, settingsController)],
      ),
      _SettingsSection.appData => _SettingsGroupCard(
        title: AppLocalizations.of(context)!.settingsAppData,
        description: AppLocalizations.of(
          context,
        )!.settingsManageTheLocalFilesAndDatabase,
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
        key: const ValueKey<String>(
          'settingsToolResultCompressionEnabledSwitch',
        ),
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
            hintText:
                '${AppSettingsSnapshot.defaultAiWriteToolSummaryMaxChars}',
          ),
          onSubmitted: (value) => _saveWriteToolSummaryMaxChars(context, value),
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
            labelText: AppLocalizations.of(
              context,
            )!.settingsPerResponseToolCallLimit,
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
            label: Text(AppLocalizations.of(context)!.settingsSaveLimit),
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
            labelText: AppLocalizations.of(
              context,
            )!.settingsSequentialToolRoundLimit,
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
            label: Text(AppLocalizations.of(context)!.settingsSaveLimit),
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
            onPressed: () =>
                _saveMaxRecentErrors(context, _maxRecentErrorsController.text),
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
          title: AppLocalizations.of(context)!.settingsSessionSettings,
          description: AppLocalizations.of(
            context,
          )!.settingsConfigureDefaultBehaviourForNewSessions,
          child: Column(
            children: [
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsSendTimeoutS,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsMaximumWaitTimeToEstablishThe,
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
                        labelText: AppLocalizations.of(
                          context,
                        )!.settingsSendTimeoutS,
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
                          AppLocalizations.of(context)!.settingsSaveTimeout,
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsResponseTimeoutS,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsMaximumWaitForACompleteResponse,
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
                        labelText: AppLocalizations.of(
                          context,
                        )!.settingsResponseTimeoutS,
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
                          AppLocalizations.of(context)!.settingsSaveTimeout,
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsStreamIdleTimeoutS,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsMaximumIdleWaitBetweenStreamChunks,
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
                        labelText: AppLocalizations.of(
                          context,
                        )!.settingsStreamIdleTimeoutS,
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
                          AppLocalizations.of(context)!.settingsSaveTimeout,
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsAutoTitle,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsWhenEnabledATitleIsAutomatically,
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
                title: AppLocalizations.of(context)!.settingsDefaultSessionMode,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefaultInteractionModeForNewSessions,
                control: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment<String>(
                        value: 'chat',
                        icon: const Icon(Icons.chat_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.settingsChat,
                          softWrap: false,
                        ),
                      ),
                      ButtonSegment<String>(
                        value: 'plan',
                        icon: const Icon(Icons.account_tree_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.settingsPlan,
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
                title: AppLocalizations.of(context)!.settingsDefaultFullAccess,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsWhenEnabledNewSessionsStartIn,
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
                title: AppLocalizations.of(context)!.settingsUserProfile,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsMaintainAGlobalUserProfileLanguage,
                control: const Align(
                  alignment: Alignment.centerLeft,
                  child: _UserProfileSettingsButton(),
                ),
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsThreadSessionManagementTitle,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsThreadSessionManagementSubtitle,
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => showThreadSessionManagementDialog(context),
                    icon: const Icon(Icons.dynamic_feed_outlined),
                    label: Text(
                      AppLocalizations.of(
                        context,
                      )!.settingsThreadSessionManagementOpen,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSubsectionCard(
          title: AppLocalizations.of(context)!.settingsModelProviderManagement,
          description: AppLocalizations.of(
            context,
          )!.settingsAddSelectTestAndMaintainModel,
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
                      return AppearOnce(
                        key: ValueKey<String>('ai-model-${aiModels[index].id}'),
                        child: _AiModelTile(
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
                title: AppLocalizations.of(context)!.settingsCompressionTrigger,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsOnceTheUncompressedHistoryInA,
                control: compressionControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsToolCallOutputCompressionThreshold,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsWhenAToolCallReturnsMore,
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
                title: AppLocalizations.of(
                  context,
                )!.settingsPerResponseToolCallLimit,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefaultsTo40IfOneAssistant,
                control: toolCallLimitControl,
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsSequentialToolRoundLimit,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefaultsTo24RoundsIfThe,
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
                title: AppLocalizations.of(context)!.settingsImageSizeLimit,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefaultsTo1mbImageAttachmentsLarger,
                control: imageSizeLimitControl,
                controlMaxWidth: 360,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSubsectionCard(
          title: AppLocalizations.of(context)!.settingsCostControl,
          description: AppLocalizations.of(
            context,
          )!.settingsReduceTokenCostsByFreezingThe,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsEnableInputCache,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDisabledByDefaultWhenEnabledEvery,
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: Switch(
                    key: const ValueKey<String>(
                      'settingsAiInputCacheEnabledSwitch',
                    ),
                    value: settingsController.aiInputCacheEnabled,
                    onChanged: (value) async {
                      await settingsController.updateAiInputCacheEnabled(value);
                    },
                  ),
                ),
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsCacheBreakpointUpdateMode,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsChooseTheSlidingUnitForThe,
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButton<String>(
                    key: const ValueKey<String>(
                      'settingsAiInputCacheUpdateModeDropdown',
                    ),
                    value: settingsController.aiInputCacheUpdateMode,
                    onChanged: (value) async {
                      if (value == null) return;
                      await settingsController.updateAiInputCacheUpdateMode(
                        value,
                      );
                    },
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: AppSettingsSnapshot
                            .aiInputCacheUpdateModeAllMessages,
                        child: Text(
                          AppLocalizations.of(
                            context,
                          )!.settingsByMessageCountUserAssistant,
                        ),
                      ),
                      DropdownMenuItem<String>(
                        value: AppSettingsSnapshot
                            .aiInputCacheUpdateModeUserMessages,
                        child: Text(
                          AppLocalizations.of(
                            context,
                          )!.settingsByUserMessageCountOnly,
                        ),
                      ),
                      DropdownMenuItem<String>(
                        value: AppSettingsSnapshot.aiInputCacheUpdateModeTokens,
                        child: Text(
                          AppLocalizations.of(
                            context,
                          )!.settingsByAccumulatedTokens,
                        ),
                      ),
                    ],
                  ),
                ),
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsCacheBreakpointUpdateInterval,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefault10MeaningDependsOnThe,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey<String>(
                        'settingsAiInputCacheUpdateIntervalField',
                      ),
                      controller: _aiInputCacheUpdateIntervalController,
                      focusNode: _aiInputCacheUpdateIntervalFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        hintText:
                            '${AppSettingsSnapshot.defaultAiInputCacheUpdateInterval}',
                      ),
                      onSubmitted: (value) =>
                          _saveAiInputCacheUpdateInterval(context, value),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        key: const ValueKey<String>(
                          'settingsAiInputCacheUpdateIntervalSaveButton',
                        ),
                        onPressed: () => _saveAiInputCacheUpdateInterval(
                          context,
                          _aiInputCacheUpdateIntervalController.text,
                        ),
                        icon: const Icon(Icons.save_rounded),
                        label: Text(AppLocalizations.of(context)!.settingsSave),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsCacheBreakpointCount,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefault4Range14Anthropic,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey<String>(
                        'settingsAiInputCacheBreakpointCountField',
                      ),
                      controller: _aiInputCacheBreakpointCountController,
                      focusNode: _aiInputCacheBreakpointCountFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        hintText:
                            '${AppSettingsSnapshot.defaultAiInputCacheBreakpointCount}',
                      ),
                      onSubmitted: (value) =>
                          _saveAiInputCacheBreakpointCount(context, value),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        key: const ValueKey<String>(
                          'settingsAiInputCacheBreakpointCountSaveButton',
                        ),
                        onPressed: () => _saveAiInputCacheBreakpointCount(
                          context,
                          _aiInputCacheBreakpointCountController.text,
                        ),
                        icon: const Icon(Icons.save_rounded),
                        label: Text(AppLocalizations.of(context)!.settingsSave),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              const SizedBox(height: 18),
              _buildAiInputCacheBreakpointPositionsRow(context),
              const SizedBox(height: 18),
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsAiBudgetUsdPerSession,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsAiBudgetUsdPerSessionBody,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey<String>(
                        'settingsAiBudgetUsdPerSessionField',
                      ),
                      controller: _aiBudgetUsdPerSessionController,
                      focusNode: _aiBudgetUsdPerSessionFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(hintText: '0'),
                      onSubmitted: (value) =>
                          _saveAiBudgetUsdPerSession(context, value),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        key: const ValueKey<String>(
                          'settingsAiBudgetUsdPerSessionSaveButton',
                        ),
                        onPressed: () => _saveAiBudgetUsdPerSession(
                          context,
                          _aiBudgetUsdPerSessionController.text,
                        ),
                        icon: const Icon(Icons.save_rounded),
                        label: Text(AppLocalizations.of(context)!.settingsSave),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSubsectionCard(
          title: AppLocalizations.of(context)!.settingsCommandSafety,
          description: AppLocalizations.of(
            context,
          )!.settingsControlWriteCommandConfirmationForBash,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsWriteCommandConfirmation,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsEnabledByDefaultWhenTheAi,
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
                AppLocalizations.of(context)!.settingsAllowCommandList,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(
                  context,
                )!.settingsMatchingWriteLikeBashCommandsSkip,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _showAllowCommandRuleDialog(context),
                icon: const Icon(Icons.verified_outlined),
                label: Text(AppLocalizations.of(context)!.settingsAddAllowRule),
              ),
              const SizedBox(height: 16),
              if (allowCommandRules.isEmpty)
                _SettingsStateBox(
                  icon: Icons.verified_user_outlined,
                  title: AppLocalizations.of(
                    context,
                  )!.settingsNoAllowRulesConfigured,
                  body: AppLocalizations.of(
                    context,
                  )!.settingsAddARuleToLetMatching,
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
                      return AppearOnce(
                        key: ValueKey<String>('allow-rule-${rule.id}'),
                        child: _AllowCommandRuleTile(
                          rule: rule,
                          onEdit: () => _showAllowCommandRuleDialog(
                            context,
                            initialRule: rule,
                          ),
                          onDelete: () =>
                              _deleteAllowCommandRule(context, rule),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                AppLocalizations.of(context)!.settingsDenyCommandList,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(
                  context,
                )!.settingsMatchingBashCommandsAreBlockedBefore,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _showDenyCommandRuleDialog(context),
                icon: const Icon(Icons.block_rounded),
                label: Text(AppLocalizations.of(context)!.settingsAddRule),
              ),
              const SizedBox(height: 16),
              if (denyCommandRules.isEmpty)
                _SettingsStateBox(
                  icon: Icons.rule_folder_outlined,
                  title: AppLocalizations.of(
                    context,
                  )!.settingsNoDenyRulesConfigured,
                  body: AppLocalizations.of(
                    context,
                  )!.settingsAddARuleToBlockMatching,
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
                      return AppearOnce(
                        key: ValueKey<String>('deny-rule-${rule.id}'),
                        child: _DenyCommandRuleTile(
                          rule: rule,
                          onEdit: () => _showDenyCommandRuleDialog(
                            context,
                            initialRule: rule,
                          ),
                          onDelete: () => _deleteDenyCommandRule(context, rule),
                        ),
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
      title: AppLocalizations.of(context)!.settingsTelemetry,
      description: AppLocalizations.of(
        context,
      )!.settingsWhenEnabledOpenhandCapturesRawAi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResponsiveSettingRow(
            title: AppLocalizations.of(context)!.settingsDebugMode,
            subtitle: AppLocalizations.of(
              context,
            )!.settingsOffByDefaultWhenEnabledEvery,
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
            title: AppLocalizations.of(context)!.settingsCaptureRawPayload,
            subtitle: AppLocalizations.of(
              context,
            )!.settingsEnabledByDefaultOnlyActiveWhen,
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
            title: AppLocalizations.of(context)!.settingsCaptureEnvironment,
            subtitle: AppLocalizations.of(
              context,
            )!.settingsOffByDefaultOnlyActiveWhen,
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
      title: AppLocalizations.of(context)!.settingsShortcutBindings,
      description: AppLocalizations.of(
        context,
      )!.settingsClickRecordThenPressTheNew,
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
          title: AppLocalizations.of(
            context,
          )!.settingsAutoCleanupExecutionHistory,
          subtitle: AppLocalizations.of(
            context,
          )!.settingsOnEveryColdStartAnAsync,
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
          AppLocalizations.of(
            context,
          )!.settingsRetentionWindowRetentionDayS(retention),
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
          AppLocalizations.of(
            context,
          )!.settingsRangeMinrMaxrDaysDefault7(minR, maxR),
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
          title: AppLocalizations.of(context)!.settingsEnableSelfLearning,
          subtitle: AppLocalizations.of(
            context,
          )!.settingsWhenOffTheSchedulerSkipsEvery,
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
          AppLocalizations.of(
            context,
          )!.settingsConcurrentWorkersConcurrency(concurrency),
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
          AppLocalizations.of(
            context,
          )!.settingsCapsHowManySessionsCanBe(minC, maxC),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          AppLocalizations.of(context)!.selfLearningFlushIntervalLabel(flushMs),
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
          AppLocalizations.of(
            context,
          )!.selfLearningFlushIntervalHelper(minFlushMs, maxFlushMs),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        _ResponsiveSettingRow(
          title: AppLocalizations.of(context)!.settingsShowSelfLearningMessages,
          subtitle: AppLocalizations.of(
            context,
          )!.settingsWhenOffSelfLearningCardsAre,
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
          title: AppLocalizations.of(context)!.settingsToolCatalogOverview,
          description: AppLocalizations.of(context)!
              .settingsSortedLengthBuiltInToolsEnabledcount(
                sorted.length,
                enabledCount,
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
                    label: Text(AppLocalizations.of(context)!.settingsResetAll),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _toggleAllBuiltinTools(context, settingsController, true);
                    },
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      AppLocalizations.of(context)!.settingsEnableAll,
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
                      AppLocalizations.of(context)!.settingsDisableAll,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (sorted.isEmpty)
                _SettingsStateBox(
                  icon: Icons.build_circle_outlined,
                  title: AppLocalizations.of(
                    context,
                  )!.settingsNoBuiltInToolConfigurations,
                  body: AppLocalizations.of(
                    context,
                  )!.settingsClickResetAllToRestoreThe,
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
            AppLocalizations.of(context)!.settingsResetBuiltInToolConfigs,
          ),
          content: Text(
            AppLocalizations.of(context)!.settingsThisWillRestoreAllBuiltIn,
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: AppLocalizations.of(context)!.settingsCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: AppLocalizations.of(context)!.settingsReset,
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
          title: Text(AppLocalizations.of(context)!.settingsDeleteCustomTool),
          content: Text(
            AppLocalizations.of(
              context,
            )!.settingsAreYouSureYouWantTo(config.effectiveName),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: AppLocalizations.of(context)!.settingsCancel,
            ),
            OpenHandDialogActionButton.destructive(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: AppLocalizations.of(context)!.settingsDelete,
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
          availableModels: settingsController.aiModels,
          recentModelSelections: settingsController.recentModelSelections,
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
            OutlinedButton.icon(
              onPressed: () => _resetStdioPackageCache(context),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(l10n.mcpStdioCacheResetAction),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _ResponsiveSettingRow(
          title: l10n.mcpStdioMirrorModeLabel,
          subtitle: l10n.mcpStdioMirrorModeBody,
          controlMaxWidth: 460,
          control: _McpStdioMirrorModeControl(
            settingsController: settingsController,
            onPersistenceFailure: () =>
                _showPersistenceFailureSnackBar(context),
            onReconnect: () => _reconnectMcpServersForMirrorChange(context),
          ),
        ),
        const SizedBox(height: 14),
        _ResponsiveSettingRow(
          title: l10n.mcpAutoProbeConcurrencyLabel,
          subtitle: l10n.mcpAutoProbeConcurrencyBody,
          control: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey<String>(
                  'settingsMcpAutoProbeConcurrencyField',
                ),
                controller: _mcpAutoProbeConcurrencyController,
                focusNode: _mcpAutoProbeConcurrencyFocusNode,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: l10n.mcpAutoProbeConcurrencyLabel,
                  hintText:
                      '${AppSettingsSnapshot.defaultMcpAutoProbeConcurrency}',
                ),
                onSubmitted: (value) =>
                    _saveMcpAutoProbeConcurrency(context, value),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey<String>(
                    'settingsMcpAutoProbeConcurrencySaveButton',
                  ),
                  onPressed: () => _saveMcpAutoProbeConcurrency(
                    context,
                    _mcpAutoProbeConcurrencyController.text,
                  ),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.mcpAutoProbeConcurrencySave),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _McpLazyLoadingHelpBanner(text: l10n.mcpLazyLoadingHowItWorks),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => _openCurrentSessionLoadedToolsDialog(context),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(l10n.mcpLazyLoadingViewLoadedAction),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => _resetToolSearchExportLastDir(context),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l10n.mcpToolSearchExportLastDirResetAction),
          ),
        ),
        // 调试入口：当 ToolSearch 重放在「3 秒反悔」窗口里被用户取消后，
        // dispatcher 会记下那次的 onFire；此处一键重发，方便快速验证。
        // 没有可重放项时按钮置灰；按下后 dispatcher 清空记忆。
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ValueListenableBuilder<bool>(
            valueListenable: context
                .read<ToolSearchReplayDispatcher>()
                .replayableListenable,
            builder: (ctx, hasReplayable, _) {
              return TextButton.icon(
                onPressed: hasReplayable
                    ? () => _replayLastCancelledToolSearch(ctx)
                    : null,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: Text(l10n.mcpToolSearchReplayLastCancelAction),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _ResponsiveSettingRow(
          title: l10n.mcpLazyLoadingModeLabel,
          subtitle: l10n.mcpLazyLoadingModeBody,
          controlMaxWidth: 440,
          control: SizedBox(
            width: double.infinity,
            child: SegmentedButton<McpLazyLoadingMode>(
              segments: <ButtonSegment<McpLazyLoadingMode>>[
                ButtonSegment<McpLazyLoadingMode>(
                  value: McpLazyLoadingMode.disabled,
                  icon: const Icon(Icons.toggle_off_outlined),
                  label: Text(l10n.mcpLazyLoadingModeDisabled, softWrap: false),
                ),
                ButtonSegment<McpLazyLoadingMode>(
                  value: McpLazyLoadingMode.auto,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(l10n.mcpLazyLoadingModeAuto, softWrap: false),
                ),
                ButtonSegment<McpLazyLoadingMode>(
                  value: McpLazyLoadingMode.enabled,
                  icon: const Icon(Icons.toggle_on_rounded),
                  label: Text(l10n.mcpLazyLoadingModeEnabled, softWrap: false),
                ),
              ],
              selected: <McpLazyLoadingMode>{
                settingsController.mcpLazyLoadingMode,
              },
              onSelectionChanged: (selection) async {
                if (selection.isEmpty) return;
                final saved = await settingsController.updateMcpLazyLoadingMode(
                  selection.first,
                );
                if (!context.mounted || saved) return;
                _showPersistenceFailureSnackBar(context);
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        _ResponsiveSettingRow(
          title: l10n.mcpLazyLoadingThresholdLabel,
          subtitle: l10n.mcpLazyLoadingThresholdBody,
          controlMaxWidth: 360,
          control: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey<String>(
                  'settingsMcpLazyLoadingThresholdField',
                ),
                controller: _mcpLazyLoadingThresholdController,
                focusNode: _mcpLazyLoadingThresholdFocusNode,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: l10n.mcpLazyLoadingThresholdLabel,
                  hintText:
                      '${AppSettingsSnapshot.defaultMcpLazyLoadingThresholdTokens}',
                ),
                onSubmitted: (value) =>
                    _saveMcpLazyLoadingThreshold(context, value),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey<String>(
                    'settingsMcpLazyLoadingThresholdSaveButton',
                  ),
                  onPressed: () => _saveMcpLazyLoadingThreshold(
                    context,
                    _mcpLazyLoadingThresholdController.text,
                  ),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.mcpLazyLoadingThresholdSave),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FirstFramePulseBox(
          child: _buildHardnessToolSearchHistoryRow(
            context,
            settingsController,
            l10n,
          ),
        ),
        const SizedBox(height: 18),
        FirstFramePulseBox(
          child: _buildToolSearchReplayCancelWindowRow(
            context,
            settingsController,
            l10n,
          ),
        ),
      ],
    );
  }

  /// Hardness ToolSearch 历史 LRU 桶上限滑块，1..64，默认 8。
  /// 与 cron retention 同款 Slider，无需 TextEditingController。
  Widget _buildHardnessToolSearchHistoryRow(
    BuildContext context,
    SettingsController settingsController,
    AppLocalizations l10n,
  ) {
    final cap = settingsController.hardnessToolSearchHistoryMaxPhases;
    const minCap = AppSettingsSnapshot.minHardnessToolSearchHistoryMaxPhases;
    const maxCap = AppSettingsSnapshot.maxHardnessToolSearchHistoryMaxPhases;
    const defaultCap =
        AppSettingsSnapshot.defaultHardnessToolSearchHistoryMaxPhases;
    return _ResponsiveSettingRow(
      title: l10n.settingsHardnessToolSearchHistoryCapLabel,
      subtitle: l10n.settingsHardnessToolSearchHistoryCapBody,
      controlMaxWidth: 360,
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.settingsHardnessToolSearchHistoryCapValue(cap),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: l10n.settingsHardnessToolSearchHistoryCapResetTooltip(
                  defaultCap,
                ),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                onPressed: cap == defaultCap
                    ? null
                    : () async {
                        final saved = await settingsController
                            .updateHardnessToolSearchHistoryMaxPhases(
                              defaultCap,
                            );
                        if (!context.mounted || saved) return;
                        _showPersistenceFailureSnackBar(context);
                      },
              ),
            ],
          ),
          KeyTweakableSlider(
            value: cap,
            min: minCap,
            max: maxCap,
            onChanged: (next) async {
              final saved = await settingsController
                  .updateHardnessToolSearchHistoryMaxPhases(next);
              if (!context.mounted || saved) return;
              _showPersistenceFailureSnackBar(context);
            },
            buildSlider: (context, value) => Slider(
              min: minCap.toDouble(),
              max: maxCap.toDouble(),
              divisions: maxCap - minCap,
              value: value.clamp(minCap, maxCap).toDouble(),
              label: '$value',
              onChanged: (v) async {
                final saved = await settingsController
                    .updateHardnessToolSearchHistoryMaxPhases(v.round());
                if (!context.mounted || saved) return;
                _showPersistenceFailureSnackBar(context);
              },
            ),
          ),
          Text(
            l10n.settingsHardnessToolSearchHistoryCapRange(minCap, maxCap),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// ToolSearch 历史「重放」按钮的反悔窗口（秒）。1..30，默认 3。
  Widget _buildToolSearchReplayCancelWindowRow(
    BuildContext context,
    SettingsController settingsController,
    AppLocalizations l10n,
  ) {
    final seconds = settingsController.toolSearchReplayCancelWindowSeconds;
    const minSec = AppSettingsSnapshot.minToolSearchReplayCancelWindowSeconds;
    const maxSec = AppSettingsSnapshot.maxToolSearchReplayCancelWindowSeconds;
    const defaultSec =
        AppSettingsSnapshot.defaultToolSearchReplayCancelWindowSeconds;
    return _ResponsiveSettingRow(
      title: l10n.settingsToolSearchReplayCancelWindowLabel,
      subtitle: l10n.settingsToolSearchReplayCancelWindowBody,
      controlMaxWidth: 360,
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.settingsToolSearchReplayCancelWindowValue(seconds),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: l10n.settingsToolSearchReplayCancelWindowResetTooltip(
                  defaultSec,
                ),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                onPressed: seconds == defaultSec
                    ? null
                    : () async {
                        final saved = await settingsController
                            .updateToolSearchReplayCancelWindowSeconds(
                              defaultSec,
                            );
                        if (!context.mounted || saved) return;
                        _showPersistenceFailureSnackBar(context);
                      },
              ),
            ],
          ),
          KeyTweakableSlider(
            value: seconds,
            min: minSec,
            max: maxSec,
            onChanged: (next) async {
              final saved = await settingsController
                  .updateToolSearchReplayCancelWindowSeconds(next);
              if (!context.mounted || saved) return;
              _showPersistenceFailureSnackBar(context);
            },
            buildSlider: (context, value) => Slider(
              min: minSec.toDouble(),
              max: maxSec.toDouble(),
              divisions: maxSec - minSec,
              value: value.clamp(minSec, maxSec).toDouble(),
              label: '${value}s',
              onChanged: (v) async {
                final saved = await settingsController
                    .updateToolSearchReplayCancelWindowSeconds(v.round());
                if (!context.mounted || saved) return;
                _showPersistenceFailureSnackBar(context);
              },
            ),
          ),
          Text(
            l10n.settingsToolSearchReplayCancelWindowRange(minSec, maxSec),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
      _showSnackBar(
        context,
        l10n.skillOperationFailed,
        kind: _SettingsSnackKind.error,
      );
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
        AppLocalizations.of(
          context,
        )!.settingsEnterAValueBetweenMinAnd(min, max),
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
      AppLocalizations.of(context)!.settingsSendTimeoutSaved,
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
        AppLocalizations.of(
          context,
        )!.settingsEnterAValueBetweenMinAnd(min, max),
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
      AppLocalizations.of(context)!.settingsResponseTimeoutSaved,
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
        AppLocalizations.of(
          context,
        )!.settingsEnterAValueBetweenMinAnd(min, max),
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
      AppLocalizations.of(context)!.settingsStreamIdleTimeoutSaved,
    );
  }

  Future<void> _saveCompressionThreshold(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue <= 0) {
      _showSnackBar(
        context,
        l10n.aiCompressionThresholdInvalid,
        kind: _SettingsSnackKind.error,
      );
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
    _compressionThresholdController.text =
        '${context.read<SettingsController>().aiMessageCompressionThresholdChars}';
    _showSnackBar(
      context,
      l10n.aiCompressionThresholdSaved,
      kind: _SettingsSnackKind.success,
    );
  }

  Future<void> _saveToolResultCompressionThreshold(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue <= 0) {
      _showSnackBar(
        context,
        l10n.aiToolResultCompressionThresholdInvalid,
        kind: _SettingsSnackKind.error,
      );
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
    _showSnackBar(
      context,
      l10n.aiToolResultCompressionThresholdSaved,
      kind: _SettingsSnackKind.success,
    );
  }

  Future<void> _saveToolResultCompressionHeadTailWindow(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue < 0 || parsedValue > 8192) {
      _showSnackBar(context, l10n.aiToolResultCompressionHeadTailWindowInvalid);
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
    _showSnackBar(
      context,
      l10n.aiToolResultCompressionHeadTailWindowSaved,
      kind: _SettingsSnackKind.success,
    );
  }

  Future<void> _saveToolResultCompressionMaxPathHits(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue < 0 || parsedValue > 200) {
      _showSnackBar(
        context,
        l10n.aiToolResultCompressionMaxPathHitsInvalid,
        kind: _SettingsSnackKind.error,
      );
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
    _showSnackBar(
      context,
      l10n.aiToolResultCompressionMaxPathHitsSaved,
      kind: _SettingsSnackKind.success,
    );
  }

  Future<void> _saveAiInputCacheUpdateInterval(
    BuildContext context,
    String rawValue,
  ) async {
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null ||
        parsedValue < AppSettingsSnapshot.minAiInputCacheUpdateInterval ||
        parsedValue > AppSettingsSnapshot.maxAiInputCacheUpdateInterval) {
      _showSnackBar(
        context,
        AppLocalizations.of(
          context,
        )!.settingsPleaseEnterAnIntegerBetweenAppsettingssn(
          AppSettingsSnapshot.minAiInputCacheUpdateInterval,
          AppSettingsSnapshot.maxAiInputCacheUpdateInterval,
        ),
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiInputCacheUpdateInterval(parsedValue);
    if (!context.mounted) return;
    if (!saved) {
      _aiInputCacheUpdateIntervalController.text =
          '${context.read<SettingsController>().aiInputCacheUpdateInterval}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _aiInputCacheUpdateIntervalController.text =
        '${context.read<SettingsController>().aiInputCacheUpdateInterval}';
    _showSnackBar(
      context,
      AppLocalizations.of(context)!.settingsCacheBreakpointUpdateIntervalSaved,
    );
  }

  Future<void> _saveAiInputCacheBreakpointCount(
    BuildContext context,
    String rawValue,
  ) async {
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null ||
        parsedValue < AppSettingsSnapshot.minAiInputCacheBreakpointCount ||
        parsedValue > AppSettingsSnapshot.maxAiInputCacheBreakpointCount) {
      _showSnackBar(
        context,
        AppLocalizations.of(
          context,
        )!.settingsPleaseEnterAnIntegerBetweenAppsettingssn2(
          AppSettingsSnapshot.minAiInputCacheBreakpointCount,
          AppSettingsSnapshot.maxAiInputCacheBreakpointCount,
        ),
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiInputCacheBreakpointCount(parsedValue);
    if (!context.mounted) return;
    if (!saved) {
      _aiInputCacheBreakpointCountController.text =
          '${context.read<SettingsController>().aiInputCacheBreakpointCount}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _aiInputCacheBreakpointCountController.text =
        '${context.read<SettingsController>().aiInputCacheBreakpointCount}';
    _showSnackBar(
      context,
      AppLocalizations.of(context)!.settingsCacheBreakpointCountSaved,
    );
  }

  // 2026-05-06 — 单会话预算输入：去掉小数尾零，0 显示为 "0"。
  static String _formatBudgetUsd(double value) {
    if (value <= 0) return '0';
    final fixed = value.toStringAsFixed(2);
    if (fixed.endsWith('.00')) return fixed.substring(0, fixed.length - 3);
    if (fixed.endsWith('0')) return fixed.substring(0, fixed.length - 1);
    return fixed;
  }

  Future<void> _saveAiBudgetUsdPerSession(
    BuildContext context,
    String rawValue,
  ) async {
    final trimmed = rawValue.trim();
    final parsed = trimmed.isEmpty ? 0.0 : double.tryParse(trimmed);
    if (parsed == null ||
        parsed.isNaN ||
        !parsed.isFinite ||
        parsed < AppSettingsSnapshot.minAiBudgetUsdPerSession ||
        parsed > AppSettingsSnapshot.maxAiBudgetUsdPerSession) {
      _showSnackBar(
        context,
        AppLocalizations.of(context)!.settingsAiBudgetUsdPerSessionInvalid,
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiBudgetUsdPerSession(parsed);
    if (!context.mounted) return;
    final current = context.read<SettingsController>().aiBudgetUsdPerSession;
    _aiBudgetUsdPerSessionController.text = _formatBudgetUsd(current);
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _showSnackBar(
      context,
      AppLocalizations.of(context)!.settingsAiBudgetUsdPerSessionSaved,
    );
  }

  /// 2026-05-04 — 缓存断点位置滑块行：N-1 个可拖拽拇指 + 末尾固定锚。
  /// 拖拽实时更新本地草稿，松手时通过 SettingsController 持久化。
  Widget _buildAiInputCacheBreakpointPositionsRow(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final count = controller.aiInputCacheBreakpointCount;
    final thumbCount = (count - 1).clamp(0, 3);
    // 没有可拖拽断点时（count=1），整行收起，避免空白控件。
    if (thumbCount == 0) {
      return const SizedBox.shrink();
    }
    final raw = controller.aiInputCacheBreakpointPositions;
    // 缺省 = 均匀铺开。例如 count=4 → [0.25, 0.5, 0.75]。
    final List<double> values = (raw.length == thumbCount)
        ? List<double>.from(raw)
        : List<double>.generate(thumbCount, (i) => (i + 1) / count);
    final liveKey = ValueKey<int>(thumbCount);
    return _ResponsiveSettingRow(
      title: AppLocalizations.of(context)!.settingsCacheBreakpointPositions,
      subtitle: AppLocalizations.of(
        context,
      )!.settingsDragTheThumbcountThumbsToPosition(thumbCount),
      control: PromptCacheBreakpointBar(
        key: liveKey,
        initialValues: List<double>.unmodifiable(values),
        thumbCount: thumbCount,
        onCommit: (positions) =>
            _saveAiInputCacheBreakpointPositions(context, positions),
        onReset: () =>
            _saveAiInputCacheBreakpointPositions(context, const <double>[]),
      ),
      controlMaxWidth: 460,
    );
  }

  Future<void> _saveAiInputCacheBreakpointPositions(
    BuildContext context,
    List<double> positions,
  ) async {
    final saved = await context
        .read<SettingsController>()
        .updateAiInputCacheBreakpointPositions(positions);
    if (!context.mounted) return;
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _showSnackBar(
      context,
      AppLocalizations.of(context)!.settingsCacheBreakpointPositionsSaved,
    );
  }

  Future<void> _saveWriteToolSummaryMaxChars(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue < 0 || parsedValue > 8192) {
      _showSnackBar(
        context,
        l10n.aiWriteToolSummaryMaxCharsInvalid,
        kind: _SettingsSnackKind.error,
      );
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
    _showSnackBar(
      context,
      l10n.aiWriteToolSummaryMaxCharsSaved,
      kind: _SettingsSnackKind.success,
    );
  }

  Future<void> _saveToolCallLimit(BuildContext context, String rawValue) async {
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null || parsedValue <= 0) {
      _showSnackBar(
        context,
        AppLocalizations.of(context)!.settingsEnterAToolCallLimitGreater,
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
      AppLocalizations.of(context)!.settingsThePerResponseToolCallLimit,
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
        AppLocalizations.of(context)!.settingsEnterASequentialToolRoundLimit,
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
      AppLocalizations.of(context)!.settingsTheSequentialToolRoundLimitHas,
    );
  }

  Future<void> _saveMaxRecentErrors(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null ||
        parsed < AppSettingsSnapshot.minAiMaxRecentErrors ||
        parsed > AppSettingsSnapshot.maxAiMaxRecentErrors) {
      _showSnackBar(
        context,
        l10n.aiMaxRecentErrorsInvalid,
        kind: _SettingsSnackKind.error,
      );
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
    _showSnackBar(
      context,
      l10n.aiMaxRecentErrorsSaved,
      kind: _SettingsSnackKind.success,
    );
  }

  Future<void> _saveMcpLazyLoadingThreshold(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null ||
        parsed < AppSettingsSnapshot.minMcpLazyLoadingThresholdTokens ||
        parsed > AppSettingsSnapshot.maxMcpLazyLoadingThresholdTokens) {
      _showSnackBar(
        context,
        l10n.mcpLazyLoadingThresholdInvalid,
        kind: _SettingsSnackKind.error,
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateMcpLazyLoadingThresholdTokens(parsed);
    if (!context.mounted) return;
    if (!saved) {
      _mcpLazyLoadingThresholdController.text =
          '${context.read<SettingsController>().mcpLazyLoadingThresholdTokens}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _mcpLazyLoadingThresholdController.text =
        '${context.read<SettingsController>().mcpLazyLoadingThresholdTokens}';
    _showSnackBar(
      context,
      l10n.mcpLazyLoadingThresholdSaved,
      kind: _SettingsSnackKind.success,
    );
  }

  Future<void> _saveMcpAutoProbeConcurrency(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null ||
        parsed < AppSettingsSnapshot.minMcpAutoProbeConcurrency ||
        parsed > AppSettingsSnapshot.maxMcpAutoProbeConcurrency) {
      _showSnackBar(
        context,
        l10n.mcpAutoProbeConcurrencyInvalid,
        kind: _SettingsSnackKind.error,
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateMcpAutoProbeConcurrency(parsed);
    if (!context.mounted) return;
    if (!saved) {
      _mcpAutoProbeConcurrencyController.text =
          '${context.read<SettingsController>().mcpAutoProbeConcurrency}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _mcpAutoProbeConcurrencyController.text =
        '${context.read<SettingsController>().mcpAutoProbeConcurrency}';
    _showSnackBar(
      context,
      l10n.mcpAutoProbeConcurrencySaved,
      kind: _SettingsSnackKind.success,
    );
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
      _showSnackBar(
        context,
        l10n.aiMaxPlanHistoryEntriesInvalid,
        kind: _SettingsSnackKind.error,
      );
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
    _showSnackBar(
      context,
      l10n.aiMaxPlanHistoryEntriesSaved,
      kind: _SettingsSnackKind.success,
    );
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
      _showSnackBar(
        context,
        l10n.aiMaxTruncationContinuationsInvalid,
        kind: _SettingsSnackKind.error,
      );
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
    _showSnackBar(
      context,
      l10n.aiMaxTruncationContinuationsSaved,
      kind: _SettingsSnackKind.success,
    );
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
      _showSnackBar(
        context,
        l10n.aiEstimatedCharactersPerTokenInvalid,
        kind: _SettingsSnackKind.error,
      );
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
    _showSnackBar(
      context,
      l10n.aiEstimatedCharactersPerTokenSaved,
      kind: _SettingsSnackKind.success,
    );
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
      _showSnackBar(
        context,
        l10n.aiImageSizeLimitInvalid,
        kind: _SettingsSnackKind.error,
      );
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
    _showSnackBar(
      context,
      l10n.aiImageSizeLimitSaved,
      kind: _SettingsSnackKind.success,
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
      (initialRule == null
          ? AppLocalizations.of(context)!.settingsTheDenyCommandRuleHasBeen
          : AppLocalizations.of(context)!.settingsTheDenyCommandRuleHasBeen2),
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
          title: Text(AppLocalizations.of(context)!.settingsDeleteDenyRule),
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
      AppLocalizations.of(context)!.settingsTheDenyCommandRuleHasBeen,
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
      (initialRule == null
          ? AppLocalizations.of(context)!.settingsTheAllowCommandRuleHasBeen
          : AppLocalizations.of(context)!.settingsTheAllowCommandRuleHasBeen2),
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
          title: Text(AppLocalizations.of(context)!.settingsDeleteAllowRule),
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
      AppLocalizations.of(context)!.settingsTheAllowCommandRuleHasBeen,
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
      _showSnackBar(
        context,
        l10n.memoryOperationFailed,
        kind: _SettingsSnackKind.error,
      );
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
      _showSnackBar(
        context,
        l10n.mcpOperationFailed,
        kind: _SettingsSnackKind.error,
      );
    }
  }

  /// 设置页快捷入口：弹出当前活跃会话已通过 ToolSearch 加载的 MCP 工具列表。
  /// 无活跃会话时仅 toast 提示，不弹 dialog（避免与空列表占位混淆）。
  void _openCurrentSessionLoadedToolsDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final aiCtrl = context.read<AiSessionController>();
    final sessionId = aiCtrl.currentSessionId;
    if (sessionId == null) {
      _showSnackBar(context, l10n.mcpLazyLoadingNoActiveSession);
      return;
    }
    final names = aiCtrl.loadedMcpToolNamesForSession(sessionId);
    final history = aiCtrl.loadedMcpToolHistoryForSession(sessionId);
    showToolSearchLoadedDialog(
      context,
      names: names,
      history: history,
      onClear: () => aiCtrl.clearLoadedMcpToolsForSession(sessionId),
    );
  }

  /// 清除 ToolSearch 历史导出对话框记忆的「上次落地目录」，让下次导出回到
  /// 系统默认位置（macOS Documents / Windows %USERPROFILE% 等）。
  Future<void> _resetToolSearchExportLastDir(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await ToolSearchHistoryExportPrefs.clear();
    if (!context.mounted) return;
    _showSnackBar(context, l10n.mcpToolSearchExportLastDirResetToast);
  }

  /// 一键重置 stdio MCP 隔离包缓存（~/.openhand/mcp/package-cache）。
  /// 弹确认对话框 → 删整个目录 → toast 反馈。失败时落 silentLog 并提示用户手删。
  Future<void> _reconnectMcpServersForMirrorChange(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final mcp = context.read<McpController>();
    // refresh() 会重新加载 servers 并对每个 enabled server 触发 force=true 的
    // 工具重拉，这会用新的 env（含 mirror override）重新 spawn 子进程，
    // 刚好覆盖「立刻按新设置重启」的诉求。
    unawaited(mcp.refresh());
    _showSnackBar(
      context,
      l10n.mcpStdioMirrorModeReconnectDone,
      kind: _SettingsSnackKind.success,
    );
  }

  Future<void> _resetStdioPackageCache(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.mcpStdioCacheResetConfirmTitle),
          content: Text(l10n.mcpStdioCacheResetConfirmBody),
          actions: <Widget>[
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: l10n.mcpStdioCacheResetCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: l10n.mcpStdioCacheResetConfirm,
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await resetMcpStdioIsolatedCache();
      if (!context.mounted) return;
      _showSnackBar(
        context,
        l10n.mcpStdioCacheResetDone,
        kind: _SettingsSnackKind.success,
      );
    } catch (error, stack) {
      silentLog('settings.mcp', 'resetStdioPackageCache', error, stack);
      if (!context.mounted) return;
      _showSnackBar(
        context,
        l10n.mcpStdioCacheResetFailed,
        kind: _SettingsSnackKind.error,
      );
    }
  }

  /// 调试快捷：重发上次被「3 秒反悔窗口」取消的 ToolSearch 重放。
  /// 没有可重放记忆时 toast「已无可重放」，否则 toast「已重发」。
  Future<void> _replayLastCancelledToolSearch(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final dispatcher = context.read<ToolSearchReplayDispatcher>();
    final fired = await dispatcher.replayLastCancelled();
    if (!context.mounted) return;
    _showSnackBar(
      context,
      fired
          ? l10n.mcpToolSearchReplayLastCancelToastFired
          : l10n.mcpToolSearchReplayLastCancelToastEmpty,
    );
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
    _showSnackBar(
      context,
      l10n.aiModelSaveSuccess,
      kind: _SettingsSnackKind.success,
    );
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
      _showSnackBar(
        context,
        l10n.aiModelTestSuccess(model.providerLabel),
        kind: _SettingsSnackKind.success,
      );
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
    _showSnackBar(
      context,
      l10n.aiModelDeleteSuccess,
      kind: _SettingsSnackKind.success,
    );
  }

  void _showPersistenceFailureSnackBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _showSnackBar(
      context,
      l10n.settingsPersistenceSaveFailedBody,
      kind: _SettingsSnackKind.error,
    );
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
      AppLocalizations.of(context)!.settingsTheShortcutHasBeenUpdated,
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
      AppLocalizations.of(context)!.settingsTheEditorShortcutHasBeenUpdated,
    );
  }

  String _shortcutActionTitle(
    BuildContext context,
    OpenHandShortcutAction action,
  ) {
    return switch (action) {
      OpenHandShortcutAction.sendMessage => AppLocalizations.of(
        context,
      )!.settingsSendMessage,
      OpenHandShortcutAction.toggleComposer => AppLocalizations.of(
        context,
      )!.settingsCollapseOrExpandComposer,
      OpenHandShortcutAction.selectPreviousModel => AppLocalizations.of(
        context,
      )!.settingsPreviousModel,
      OpenHandShortcutAction.selectNextModel => AppLocalizations.of(
        context,
      )!.settingsNextModel,
      OpenHandShortcutAction.toggleAutoFollow => AppLocalizations.of(
        context,
      )!.settingsToggleAutoFollow,
      OpenHandShortcutAction.selectPreviousSession => AppLocalizations.of(
        context,
      )!.settingsPreviousSession,
      OpenHandShortcutAction.selectNextSession => AppLocalizations.of(
        context,
      )!.settingsNextSession,
      OpenHandShortcutAction.undoLastFileMutation => AppLocalizations.of(
        context,
      )!.settingsUndoLastFileMutation,
    };
  }

  String _editorShortcutActionTitle(
    BuildContext context,
    EditorShortcutAction action,
  ) {
    return switch (action) {
      EditorShortcutAction.saveFile => AppLocalizations.of(
        context,
      )!.settingsSaveFile,
      EditorShortcutAction.triggerCompletion => AppLocalizations.of(
        context,
      )!.settingsTriggerCompletion,
      EditorShortcutAction.showSignatureHelp => AppLocalizations.of(
        context,
      )!.settingsShowSignatureHelp,
      EditorShortcutAction.find => AppLocalizations.of(context)!.settingsFind,
      EditorShortcutAction.replace => AppLocalizations.of(
        context,
      )!.settingsFindAndReplace,
      EditorShortcutAction.goToLine => AppLocalizations.of(
        context,
      )!.settingsGoToLine,
      EditorShortcutAction.showDocumentSymbols => AppLocalizations.of(
        context,
      )!.settingsDocumentSymbols,
      EditorShortcutAction.showWorkspaceSymbols => AppLocalizations.of(
        context,
      )!.settingsWorkspaceSymbols,
      EditorShortcutAction.goToDefinition => AppLocalizations.of(
        context,
      )!.settingsGoToDefinition,
      EditorShortcutAction.findReferences => AppLocalizations.of(
        context,
      )!.settingsFindReferences,
      EditorShortcutAction.goToImplementation => AppLocalizations.of(
        context,
      )!.settingsGoToImplementation,
      EditorShortcutAction.showHoverInfo => AppLocalizations.of(
        context,
      )!.settingsShowHoverInfo,
      EditorShortcutAction.renameSymbol => AppLocalizations.of(
        context,
      )!.settingsRenameSymbol,
      EditorShortcutAction.showCodeActions => AppLocalizations.of(
        context,
      )!.settingsCodeActions,
      EditorShortcutAction.formatDocument => AppLocalizations.of(
        context,
      )!.settingsFormatDocument,
    };
  }

  String _shortcutActionSubtitle(
    BuildContext context,
    OpenHandShortcutAction action,
  ) {
    return switch (action) {
      OpenHandShortcutAction.sendMessage => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlEnterAndTriggers,
      OpenHandShortcutAction.toggleComposer => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlPForQuickly,
      OpenHandShortcutAction.selectPreviousModel => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlLeftAndWraps,
      OpenHandShortcutAction.selectNextModel => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlRightAndWraps,
      OpenHandShortcutAction.toggleAutoFollow => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlSForToggling,
      OpenHandShortcutAction.selectPreviousSession => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlUpAndWraps,
      OpenHandShortcutAction.selectNextSession => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlDownAndWraps,
      OpenHandShortcutAction.undoLastFileMutation => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlShiftZForUndo,
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
      EditorShortcutAction.saveFile => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndSavesThe(defaultLabel),
      EditorShortcutAction.triggerCompletion => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndOpensThe(defaultLabel),
      EditorShortcutAction.showSignatureHelp => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndShowsMethod(defaultLabel),
      EditorShortcutAction.find => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndTogglesThe(defaultLabel),
      EditorShortcutAction.replace => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndTogglesThe2(defaultLabel),
      EditorShortcutAction.goToLine => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndTogglesThe3(defaultLabel),
      EditorShortcutAction.showDocumentSymbols => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndTogglesThe4(defaultLabel),
      EditorShortcutAction.showWorkspaceSymbols => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndTogglesThe5(defaultLabel),
      EditorShortcutAction.goToDefinition => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndJumpsTo(defaultLabel),
      EditorShortcutAction.findReferences => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndFindsReferences(defaultLabel),
      EditorShortcutAction.goToImplementation => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndJumpsTo2(defaultLabel),
      EditorShortcutAction.showHoverInfo => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndShowsType(defaultLabel),
      EditorShortcutAction.renameSymbol => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndStartsRename(defaultLabel),
      EditorShortcutAction.showCodeActions => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndShowsAvailable(defaultLabel),
      EditorShortcutAction.formatDocument => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndFormatsThe(defaultLabel),
    };
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    _SettingsSnackKind kind = _SettingsSnackKind.info,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      switch (kind) {
        case _SettingsSnackKind.success:
          OpenHandSnackBar.show(
            context,
            messenger,
            OpenHandSnackBar.success(context, message),
          );
        case _SettingsSnackKind.error:
          OpenHandSnackBar.show(
            context,
            messenger,
            OpenHandSnackBar.error(context, message),
          );
        case _SettingsSnackKind.info:
          OpenHandSnackBar.show(
            context,
            messenger,
            SnackBar(content: Text(message)),
          );
      }
    });
  }
}

enum _SettingsSnackKind { info, success, error }

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

class _McpStdioMirrorModeControl extends StatelessWidget {
  const _McpStdioMirrorModeControl({
    required this.settingsController,
    required this.onPersistenceFailure,
    required this.onReconnect,
  });

  final SettingsController settingsController;
  final VoidCallback onPersistenceFailure;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = settingsController.mcpStdioMirrorMode;
    final source = resolveMcpMirrorEffectiveSource();
    final injects = source.injects;
    final reasonText = switch (source) {
      McpMirrorEffectiveSource.envOn ||
      McpMirrorEffectiveSource.envOff => l10n.mcpStdioMirrorModeReasonEnv,
      McpMirrorEffectiveSource.settingForceOn ||
      McpMirrorEffectiveSource.settingForceOff =>
        l10n.mcpStdioMirrorModeReasonSetting,
      McpMirrorEffectiveSource.autoLocaleZh ||
      McpMirrorEffectiveSource.autoLocaleOther =>
        l10n.mcpStdioMirrorModeReasonLocale(Platform.localeName),
    };
    final statusBg = injects
        ? colorScheme.primaryContainer.withValues(alpha: 0.45)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final statusFg = injects
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final statusBorder = injects
        ? colorScheme.primary.withValues(alpha: 0.30)
        : colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<McpStdioMirrorMode>(
          segments: <ButtonSegment<McpStdioMirrorMode>>[
            ButtonSegment<McpStdioMirrorMode>(
              value: McpStdioMirrorMode.auto,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(l10n.mcpStdioMirrorModeAuto, softWrap: false),
            ),
            ButtonSegment<McpStdioMirrorMode>(
              value: McpStdioMirrorMode.forceOn,
              icon: const Icon(Icons.cloud_done_outlined),
              label: Text(l10n.mcpStdioMirrorModeForceOn, softWrap: false),
            ),
            ButtonSegment<McpStdioMirrorMode>(
              value: McpStdioMirrorMode.forceOff,
              icon: const Icon(Icons.cloud_off_outlined),
              label: Text(l10n.mcpStdioMirrorModeForceOff, softWrap: false),
            ),
          ],
          selected: <McpStdioMirrorMode>{selected},
          onSelectionChanged: (selection) async {
            if (selection.isEmpty) return;
            final saved = await settingsController.updateMcpStdioMirrorMode(
              selection.first,
            );
            if (!context.mounted || saved) return;
            onPersistenceFailure();
          },
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: statusBg,
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            border: Border.all(color: statusBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    injects ? Icons.cloud_done_outlined : Icons.public_outlined,
                    size: 18,
                    color: statusFg,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      injects
                          ? l10n.mcpStdioMirrorModeStatusInjected
                          : l10n.mcpStdioMirrorModeStatusBypassed,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: statusFg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  l10n.mcpStdioMirrorModeStatusReason(reasonText),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusFg.withValues(alpha: 0.78),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onReconnect,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l10n.mcpStdioMirrorModeReconnectAction),
          ),
        ),
      ],
    );
  }
}

class _McpLazyLoadingHelpBanner extends StatelessWidget {
  const _McpLazyLoadingHelpBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.search_rounded, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../features/ai/model/ai_allow_command_rule.dart';
import '../../features/ai/model/ai_builtin_tool_config.dart';
import '../../features/ai/model/ai_deny_command_rule.dart';
import '../../features/ai/model/ai_lsp_backend_catalog.dart';
import '../../features/ai/model/ai_lsp_language_settings.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../../features/mcp/model/mcp_lazy_loading_mode.dart';
import '../model/app_language.dart';
import '../model/app_proxy_settings.dart';
import '../model/app_settings_snapshot.dart';
import '../model/dialog_animation_settings.dart';
import '../model/editor_code_theme.dart';
import '../model/editor_indent.dart';
import '../model/editor_shortcut.dart';
import '../model/openhand_shortcut.dart';
import '../support/openhand_paths.dart';
import '../support/silent_log.dart';
import '../theme/openhand_theme_preset.dart';
import 'settings_store.dart';

enum _MutationDisposition { apply, successNoChange, reject }

class SettingsController extends ChangeNotifier {
  SettingsController._({
    required SettingsStore store,
    required AppSettingsSnapshot snapshot,
    SettingsPersistenceIssue? persistenceIssue,
  }) : _store = store,
       _themeMode = snapshot.themeMode,
       _themePreset = snapshot.themePreset,
       _language = snapshot.language,
       _skillsStoragePath = snapshot.skillsStoragePath,
       _mcpEnabled = snapshot.mcpEnabled,
       _mcpServersFilePath = snapshot.mcpServersFilePath,
       _mcpLazyLoadingMode = snapshot.mcpLazyLoadingMode,
       _mcpLazyLoadingThresholdTokens = snapshot.mcpLazyLoadingThresholdTokens,
       _memoryEnabled = snapshot.memoryEnabled,
       _userMemoryFilePath = snapshot.userMemoryFilePath,
       _editorWordWrap = snapshot.editorWordWrap,
       _editorIndentSpaces = snapshot.editorIndentSpaces,
       _editorCodeTheme = snapshot.editorCodeTheme,
       _editorLspSettings = _cloneEditorLspSettingsMap(
         snapshot.editorLspSettings,
       ),
       _editorShortcutBindings = _cloneEditorShortcutBindings(
         snapshot.editorShortcutBindings,
       ),
       _aiMessageCompressionThresholdChars =
           snapshot.aiMessageCompressionThresholdChars,
       _aiToolResultCompressionThresholdChars =
           snapshot.aiToolResultCompressionThresholdChars,
       _aiToolResultCompressionEnabled =
           snapshot.aiToolResultCompressionEnabled,
       _aiToolResultCompressionHeadTailWindowChars =
           snapshot.aiToolResultCompressionHeadTailWindowChars,
       _aiToolResultCompressionMaxPathHits =
           snapshot.aiToolResultCompressionMaxPathHits,
       _aiInputCacheEnabled = snapshot.aiInputCacheEnabled,
       _aiInputCacheUpdateMode = snapshot.aiInputCacheUpdateMode,
       _aiInputCacheUpdateInterval = snapshot.aiInputCacheUpdateInterval,
       _aiInputCacheBreakpointCount = snapshot.aiInputCacheBreakpointCount,
       _aiInputCacheBreakpointPositions =
           snapshot.aiInputCacheBreakpointPositions,
       _aiBudgetUsdPerSession = snapshot.aiBudgetUsdPerSession,
       _aiWriteToolSummaryMaxChars = snapshot.aiWriteToolSummaryMaxChars,
       _aiSingleRoundToolCallLimit = snapshot.aiSingleRoundToolCallLimit,
       _aiMaxRecentErrors = snapshot.aiMaxRecentErrors,
       _aiMaxPlanHistoryEntries = snapshot.aiMaxPlanHistoryEntries,
       _aiMaxTruncationContinuations = snapshot.aiMaxTruncationContinuations,
       _aiEstimatedCharactersPerToken = snapshot.aiEstimatedCharactersPerToken,
       _aiMaxToolOutputChars = snapshot.aiMaxToolOutputChars,
       _aiWriteConfirmationTimeoutMs = snapshot.aiWriteConfirmationTimeoutMs,
       _aiFastPathWriteAnalysisThreshold =
           snapshot.aiFastPathWriteAnalysisThreshold,
       _aiMaxHookTextCharacters = snapshot.aiMaxHookTextCharacters,
       _aiWebFetchMaxResponseBytes = snapshot.aiWebFetchMaxResponseBytes,
       _aiWebFetchMaxRedirects = snapshot.aiWebFetchMaxRedirects,
       _aiWebFetchMaxCacheEntries = snapshot.aiWebFetchMaxCacheEntries,
       _aiAttachmentMaxInlineImageDimension =
           snapshot.aiAttachmentMaxInlineImageDimension,
       _aiAttachmentMaxTextRawBytes = snapshot.aiAttachmentMaxTextRawBytes,
       _aiAttachmentMaxPdfRawBytes = snapshot.aiAttachmentMaxPdfRawBytes,
       _aiAttachmentMaxImageRawBytes = snapshot.aiAttachmentMaxImageRawBytes,
       _aiChatMaxStreamLineBufferBytes =
           snapshot.aiChatMaxStreamLineBufferBytes,
       _aiFallbackTitleMaxCharacters = snapshot.aiFallbackTitleMaxCharacters,
       _aiGeneratedTitleMaxCharacters = snapshot.aiGeneratedTitleMaxCharacters,
       _aiMinimumMeaningfulTitleCharacters =
           snapshot.aiMinimumMeaningfulTitleCharacters,
       _aiMinimumMeaningfulLatinTitleWords =
           snapshot.aiMinimumMeaningfulLatinTitleWords,
       _aiMaxSkillContentLength = snapshot.aiMaxSkillContentLength,
       _aiMaxWorkspaceDocumentCharacters =
           snapshot.aiMaxWorkspaceDocumentCharacters,
       _aiSequentialToolRoundLimit = snapshot.aiSequentialToolRoundLimit,
       _aiImageSizeLimitBytes = snapshot.aiImageSizeLimitBytes,
       _aiWriteCommandConfirmationEnabled =
           snapshot.aiWriteCommandConfirmationEnabled,
       _aiAllowCommandRules = List<AiAllowCommandRule>.from(
         snapshot.aiAllowCommandRules,
       ),
       _aiDenyCommandRules = List<AiDenyCommandRule>.from(
         snapshot.aiDenyCommandRules,
       ),
       _aiConnectTimeoutSeconds = snapshot.aiConnectTimeoutSeconds,
       _aiResponseTimeoutSeconds = snapshot.aiResponseTimeoutSeconds,
       _aiStreamIdleTimeoutSeconds = snapshot.aiStreamIdleTimeoutSeconds,
       _aiAutoTitleEnabled = snapshot.aiAutoTitleEnabled,
       _aiDefaultSessionMode = snapshot.aiDefaultSessionMode,
       _aiDefaultFullAccessPermission = snapshot.aiDefaultFullAccessPermission,
       _aiModels = List<AiModelConfig>.from(snapshot.aiModels),
       _selectedAiModelId = snapshot.selectedAiModelId,
       _recentModelSelections = List<RecentModelSelection>.from(
         snapshot.recentModelSelections,
       ),
       _shortcutBindings = _cloneShortcutBindings(snapshot.shortcutBindings),
       _dialogAnimationSettings = snapshot.dialogAnimationSettings,
       _menuAnimationSettings = snapshot.menuAnimationSettings,
       _pageAnimationSettings = snapshot.pageAnimationSettings,
       _panelAnimationSettings = snapshot.panelAnimationSettings,
       _chipAnimationSettings = snapshot.chipAnimationSettings,
       _listItemAnimationSettings = snapshot.listItemAnimationSettings,
       _builtinToolConfigs = List<AiBuiltinToolConfig>.from(
         snapshot.builtinToolConfigs,
       ),
       _telemetryDebugEnabled = snapshot.telemetryDebugEnabled,
       _telemetryCaptureRawPayload = snapshot.telemetryCaptureRawPayload,
       _telemetryCaptureEnvironment = snapshot.telemetryCaptureEnvironment,
       _telemetryMaxPayloadChars = snapshot.telemetryMaxPayloadChars,
       _selfLearningEnabled = snapshot.selfLearningEnabled,
       _selfLearningConcurrency = snapshot.selfLearningConcurrency,
       _selfLearningStreamFlushIntervalMs =
           snapshot.selfLearningStreamFlushIntervalMs,
       _showSelfLearningMessages = snapshot.showSelfLearningMessages,
       _cronAutoCleanupEnabled = snapshot.cronAutoCleanupEnabled,
       _cronAutoCleanupRetentionDays = snapshot.cronAutoCleanupRetentionDays,
       _reduceMotion = snapshot.reduceMotion,
       _proxySettings = snapshot.proxySettings,
       _persistenceIssue = persistenceIssue;

  static const int _maxRecentModelSelections = 10;
  static const Uuid _uuid = Uuid();

  static Future<SettingsController> create({SettingsStore? store}) async {
    final effectiveStore = store ?? SettingsStore();
    final loadResult = await effectiveStore.load();
    return SettingsController._(
      store: effectiveStore,
      snapshot: loadResult.snapshot,
      persistenceIssue: loadResult.issue,
    );
  }

  final SettingsStore _store;
  ThemeMode _themeMode;
  OpenHandThemePreset _themePreset;
  AppLanguage _language;
  String _skillsStoragePath;
  bool _mcpEnabled;
  String _mcpServersFilePath;
  McpLazyLoadingMode _mcpLazyLoadingMode;
  int _mcpLazyLoadingThresholdTokens;
  bool _memoryEnabled;
  String _userMemoryFilePath;
  bool _editorWordWrap;
  int _editorIndentSpaces;
  EditorCodeTheme _editorCodeTheme;
  Map<String, AiLspLanguageSettings> _editorLspSettings;
  Map<EditorShortcutAction, List<int>> _editorShortcutBindings;
  int _aiMessageCompressionThresholdChars;
  int _aiToolResultCompressionThresholdChars;
  bool _aiToolResultCompressionEnabled;
  int _aiToolResultCompressionHeadTailWindowChars;
  int _aiToolResultCompressionMaxPathHits;
  bool _aiInputCacheEnabled;
  String _aiInputCacheUpdateMode;
  int _aiInputCacheUpdateInterval;
  int _aiInputCacheBreakpointCount;
  List<double> _aiInputCacheBreakpointPositions;
  double _aiBudgetUsdPerSession;
  int _aiWriteToolSummaryMaxChars;
  int _aiSingleRoundToolCallLimit;
  int _aiMaxRecentErrors;
  int _aiMaxPlanHistoryEntries;
  int _aiMaxTruncationContinuations;
  int _aiEstimatedCharactersPerToken;
  int _aiMaxToolOutputChars;
  int _aiWriteConfirmationTimeoutMs;
  int _aiFastPathWriteAnalysisThreshold;
  int _aiMaxHookTextCharacters;
  int _aiWebFetchMaxResponseBytes;
  int _aiWebFetchMaxRedirects;
  int _aiWebFetchMaxCacheEntries;
  int _aiAttachmentMaxInlineImageDimension;
  int _aiAttachmentMaxTextRawBytes;
  int _aiAttachmentMaxPdfRawBytes;
  int _aiAttachmentMaxImageRawBytes;
  int _aiChatMaxStreamLineBufferBytes;
  int _aiFallbackTitleMaxCharacters;
  int _aiGeneratedTitleMaxCharacters;
  int _aiMinimumMeaningfulTitleCharacters;
  int _aiMinimumMeaningfulLatinTitleWords;
  int _aiMaxSkillContentLength;
  int _aiMaxWorkspaceDocumentCharacters;
  int _aiSequentialToolRoundLimit;
  int _aiImageSizeLimitBytes;
  bool _aiWriteCommandConfirmationEnabled;
  List<AiAllowCommandRule> _aiAllowCommandRules;
  List<AiDenyCommandRule> _aiDenyCommandRules;
  int _aiConnectTimeoutSeconds;
  int _aiResponseTimeoutSeconds;
  int _aiStreamIdleTimeoutSeconds;
  bool _aiAutoTitleEnabled;
  String _aiDefaultSessionMode;
  bool _aiDefaultFullAccessPermission;
  List<AiModelConfig> _aiModels;
  String? _selectedAiModelId;
  List<RecentModelSelection> _recentModelSelections;
  Map<OpenHandShortcutAction, List<int>> _shortcutBindings;
  DialogAnimationSettings _dialogAnimationSettings;
  DialogAnimationSettings _menuAnimationSettings;
  DialogAnimationSettings _pageAnimationSettings;
  DialogAnimationSettings _panelAnimationSettings;
  DialogAnimationSettings _chipAnimationSettings;
  DialogAnimationSettings _listItemAnimationSettings;
  List<AiBuiltinToolConfig> _builtinToolConfigs;
  bool _telemetryDebugEnabled;
  bool _telemetryCaptureRawPayload;
  bool _telemetryCaptureEnvironment;
  int _telemetryMaxPayloadChars;
  bool _selfLearningEnabled;
  int _selfLearningConcurrency;
  int _selfLearningStreamFlushIntervalMs;
  bool _showSelfLearningMessages;
  bool _cronAutoCleanupEnabled;
  int _cronAutoCleanupRetentionDays;
  bool _reduceMotion;
  AppProxySettings _proxySettings;
  SettingsPersistenceIssue? _persistenceIssue;
  bool _isDisposed = false;
  Future<void> _mutationQueue = Future<void>.value();

  /// Increments every time a mutation is successfully persisted to disk.
  /// Settings panels can listen on this to fire ephemeral feedback effects
  /// (e.g. a soft highlight pulse) without each `_save*` call site needing
  /// to wire up a per-row notifier.
  final ValueNotifier<int> _saveSuccessSignal = ValueNotifier<int>(0);
  ValueListenable<int> get saveSuccessSignal => _saveSuccessSignal;

  ThemeMode get themeMode => _themeMode;
  OpenHandThemePreset get themePreset => _themePreset;
  AppLanguage get language => _language;
  Locale get locale => _language.locale;
  String get skillsStoragePath => _skillsStoragePath;
  String get displaySkillsStoragePath =>
      OpenHandPaths.shortenHomePath(_skillsStoragePath);
  String get defaultSkillsStoragePath =>
      OpenHandPaths.defaultSkillsDirectoryPath();
  String get defaultSkillsStorageLabel =>
      OpenHandPaths.defaultSkillsDirectoryLabel;
  bool get mcpEnabled => _mcpEnabled;
  String get mcpServersFilePath => _mcpServersFilePath;
  McpLazyLoadingMode get mcpLazyLoadingMode => _mcpLazyLoadingMode;
  int get mcpLazyLoadingThresholdTokens => _mcpLazyLoadingThresholdTokens;
  String get displayMcpServersFilePath =>
      OpenHandPaths.shortenHomePath(_mcpServersFilePath);
  String get defaultMcpServersFilePath =>
      OpenHandPaths.defaultMcpServersFilePath();
  String get defaultMcpServersFileLabel =>
      OpenHandPaths.defaultMcpServersFileLabel;
  bool get memoryEnabled => _memoryEnabled;
  String get userMemoryFilePath => _userMemoryFilePath;
  bool get editorWordWrap => _editorWordWrap;
  int get editorIndentSpaces => _editorIndentSpaces;
  EditorCodeTheme get editorCodeTheme => _editorCodeTheme;
  Map<String, AiLspLanguageSettings> get editorLspSettings =>
      _cloneEditorLspSettingsMap(_editorLspSettings);
  Map<EditorShortcutAction, List<int>> get editorShortcutBindings =>
      _cloneEditorShortcutBindings(_editorShortcutBindings);
  AiLspLanguageSettings editorLspSettingsForLanguage(String language) {
    return _editorLspSettings[normalizeAiLspLanguage(language)] ??
        const AiLspLanguageSettings();
  }

  String defaultEditorLspRootPath(String language) {
    return OpenHandPaths.defaultLspDirectoryPathForLanguage(
      normalizeAiLspLanguage(language),
    );
  }

  String defaultEditorLspRootLabel(String language) {
    return OpenHandPaths.defaultLspDirectoryLabelForLanguage(
      normalizeAiLspLanguage(language),
    );
  }

  int get aiMessageCompressionThresholdChars =>
      _aiMessageCompressionThresholdChars;
  int get aiToolResultCompressionThresholdChars =>
      _aiToolResultCompressionThresholdChars;
  bool get aiToolResultCompressionEnabled => _aiToolResultCompressionEnabled;
  int get aiToolResultCompressionHeadTailWindowChars =>
      _aiToolResultCompressionHeadTailWindowChars;
  int get aiToolResultCompressionMaxPathHits =>
      _aiToolResultCompressionMaxPathHits;

  bool get aiInputCacheEnabled => _aiInputCacheEnabled;
  String get aiInputCacheUpdateMode => _aiInputCacheUpdateMode;
  int get aiInputCacheUpdateInterval => _aiInputCacheUpdateInterval;
  int get aiInputCacheBreakpointCount => _aiInputCacheBreakpointCount;

  /// 2026-05-04 — 用户自定义的前 N-1 个静态缓存点位置（百分比 0..1，升序）。
  /// 空列表表示沿用 mode-based 自动布点。
  List<double> get aiInputCacheBreakpointPositions =>
      _aiInputCacheBreakpointPositions;
  double get aiBudgetUsdPerSession => _aiBudgetUsdPerSession;
  int get aiWriteToolSummaryMaxChars => _aiWriteToolSummaryMaxChars;
  int get aiSingleRoundToolCallLimit => _aiSingleRoundToolCallLimit;
  int get aiMaxRecentErrors => _aiMaxRecentErrors;
  int get aiMaxPlanHistoryEntries => _aiMaxPlanHistoryEntries;
  int get aiMaxTruncationContinuations => _aiMaxTruncationContinuations;
  int get aiEstimatedCharactersPerToken => _aiEstimatedCharactersPerToken;
  int get aiMaxToolOutputChars => _aiMaxToolOutputChars;
  int get aiWriteConfirmationTimeoutMs => _aiWriteConfirmationTimeoutMs;
  int get aiFastPathWriteAnalysisThreshold => _aiFastPathWriteAnalysisThreshold;
  int get aiMaxHookTextCharacters => _aiMaxHookTextCharacters;
  int get aiWebFetchMaxResponseBytes => _aiWebFetchMaxResponseBytes;
  int get aiWebFetchMaxRedirects => _aiWebFetchMaxRedirects;
  int get aiWebFetchMaxCacheEntries => _aiWebFetchMaxCacheEntries;
  int get aiAttachmentMaxInlineImageDimension =>
      _aiAttachmentMaxInlineImageDimension;
  int get aiAttachmentMaxTextRawBytes => _aiAttachmentMaxTextRawBytes;
  int get aiAttachmentMaxPdfRawBytes => _aiAttachmentMaxPdfRawBytes;
  int get aiAttachmentMaxImageRawBytes => _aiAttachmentMaxImageRawBytes;
  int get aiChatMaxStreamLineBufferBytes => _aiChatMaxStreamLineBufferBytes;
  int get aiFallbackTitleMaxCharacters => _aiFallbackTitleMaxCharacters;
  int get aiGeneratedTitleMaxCharacters => _aiGeneratedTitleMaxCharacters;
  int get aiMinimumMeaningfulTitleCharacters =>
      _aiMinimumMeaningfulTitleCharacters;
  int get aiMinimumMeaningfulLatinTitleWords =>
      _aiMinimumMeaningfulLatinTitleWords;
  int get aiMaxSkillContentLength => _aiMaxSkillContentLength;
  int get aiMaxWorkspaceDocumentCharacters => _aiMaxWorkspaceDocumentCharacters;
  int get aiSequentialToolRoundLimit => _aiSequentialToolRoundLimit;
  int get aiImageSizeLimitBytes => _aiImageSizeLimitBytes;
  bool get aiWriteCommandConfirmationEnabled =>
      _aiWriteCommandConfirmationEnabled;
  List<AiAllowCommandRule> get aiAllowCommandRules =>
      List<AiAllowCommandRule>.unmodifiable(_aiAllowCommandRules);
  List<AiDenyCommandRule> get aiDenyCommandRules =>
      List<AiDenyCommandRule>.unmodifiable(_aiDenyCommandRules);
  int get aiConnectTimeoutSeconds => _aiConnectTimeoutSeconds;
  int get aiResponseTimeoutSeconds => _aiResponseTimeoutSeconds;
  int get aiStreamIdleTimeoutSeconds => _aiStreamIdleTimeoutSeconds;
  bool get aiAutoTitleEnabled => _aiAutoTitleEnabled;
  String get aiDefaultSessionMode => _aiDefaultSessionMode;
  bool get aiDefaultFullAccessPermission => _aiDefaultFullAccessPermission;
  String get displayUserMemoryFilePath =>
      OpenHandPaths.shortenHomePath(_userMemoryFilePath);
  String get defaultUserMemoryFilePath =>
      OpenHandPaths.defaultUserMemoryFilePath();
  String get defaultUserMemoryFileLabel =>
      OpenHandPaths.defaultUserMemoryFileLabel();
  String get settingsFilePath => _store.settingsFilePath;
  String get displaySettingsFilePath =>
      OpenHandPaths.shortenHomePath(_store.settingsFilePath);
  // Cached unmodifiable views: returning a fresh `List.unmodifiable` from the
  // getter on every call breaks `context.select` deduplication (each `==`
  // check sees a brand-new list reference) and makes downstream widgets that
  // only depend on these slices rebuild on every unrelated controller
  // notification (which fire frequently during streaming). The cached views
  // are invalidated through `_invalidateAiModelsView` /
  // `_invalidateRecentModelSelectionsView` from every mutation site so the
  // visible state remains correct.
  List<AiModelConfig>? _cachedAiModelsView;
  List<RecentModelSelection>? _cachedRecentModelSelectionsView;

  List<AiModelConfig> get aiModels =>
      _cachedAiModelsView ??= List<AiModelConfig>.unmodifiable(_aiModels);
  String? get selectedAiModelId => _selectedAiModelId;
  List<RecentModelSelection> get recentModelSelections =>
      _cachedRecentModelSelectionsView ??=
          List<RecentModelSelection>.unmodifiable(_recentModelSelections);
  Map<OpenHandShortcutAction, List<int>> get shortcutBindings =>
      _cloneShortcutBindings(_shortcutBindings);
  DialogAnimationSettings get dialogAnimationSettings =>
      _dialogAnimationSettings;
  DialogAnimationSettings get menuAnimationSettings => _menuAnimationSettings;
  DialogAnimationSettings get pageAnimationSettings => _pageAnimationSettings;
  DialogAnimationSettings get panelAnimationSettings => _panelAnimationSettings;
  DialogAnimationSettings get chipAnimationSettings => _chipAnimationSettings;
  DialogAnimationSettings get listItemAnimationSettings =>
      _listItemAnimationSettings;
  List<AiBuiltinToolConfig> get builtinToolConfigs =>
      List<AiBuiltinToolConfig>.unmodifiable(_builtinToolConfigs);
  bool get telemetryDebugEnabled => _telemetryDebugEnabled;
  bool get telemetryCaptureRawPayload => _telemetryCaptureRawPayload;
  bool get telemetryCaptureEnvironment => _telemetryCaptureEnvironment;
  int get telemetryMaxPayloadChars => _telemetryMaxPayloadChars;

  /// Whether the Hermes Talker self-learning scheduler is active.
  bool get selfLearningEnabled => _selfLearningEnabled;

  /// Maximum concurrent self-learning sub-agent dispatches.
  int get selfLearningConcurrency => _selfLearningConcurrency;

  /// 自学习卡片流式输出后台刷新（持久化）间隔，毫秒。
  int get selfLearningStreamFlushIntervalMs =>
      _selfLearningStreamFlushIntervalMs;

  /// Whether self-learning cards are rendered in the chat transcript.
  /// Independent of [selfLearningEnabled] which only controls the
  /// background scheduler.
  bool get showSelfLearningMessages => _showSelfLearningMessages;

  /// 2026-04-25 — 是否在冷启动时自动清理超过保留期的 cron 执行历史。
  bool get cronAutoCleanupEnabled => _cronAutoCleanupEnabled;

  /// 2026-04-25 — cron 执行历史保留天数；超过该天数的记录会被异步 worker
  /// 清理。
  int get cronAutoCleanupRetentionDays => _cronAutoCleanupRetentionDays;

  /// 2026-05 — 用户层减少动画总开关。true 时自研动画时长归 0，
  /// 同时通过 MediaQuery.disableAnimations 同步禁用 Flutter 内置动画
  /// （路由/弹窗/Hero）。默认 false；OS-level reduceMotion 仍由
  /// MediaQuery 自动接管。
  bool get reduceMotion => _reduceMotion;

  /// 系统级代理配置（模式、协议、主机、端口、鉴权与例外名单）。
  AppProxySettings get proxySettings => _proxySettings;

  SettingsPersistenceIssue? get persistenceIssue => _persistenceIssue;

  @override
  void notifyListeners() {
    if (_isDisposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _saveSuccessSignal.dispose();
    super.dispose();
  }

  AiModelConfig? get selectedAiModel {
    final selectedAiModelId = _selectedAiModelId;
    if (selectedAiModelId == null) {
      return null;
    }
    for (final item in _aiModels) {
      if (item.id == selectedAiModelId) {
        return item;
      }
    }
    return null;
  }

  void clearPersistenceIssue() {
    if (_persistenceIssue == null) {
      return;
    }
    _persistenceIssue = null;
    notifyListeners();
  }

  Future<bool> updateThemeMode(ThemeMode value) async {
    return _commitMutation(() {
      if (_themeMode == value) {
        return _MutationDisposition.successNoChange;
      }
      _themeMode = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateThemePreset(OpenHandThemePreset value) async {
    return _commitMutation(() {
      if (_themePreset == value) {
        return _MutationDisposition.successNoChange;
      }
      _themePreset = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateLanguage(AppLanguage value) async {
    return _commitMutation(() {
      if (_language == value) {
        return _MutationDisposition.successNoChange;
      }
      _language = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateSkillsStoragePath(String value) async {
    final normalizedPath = OpenHandPaths.normalizeUserPath(value);
    return _commitMutation(() {
      if (_skillsStoragePath == normalizedPath) {
        return _MutationDisposition.successNoChange;
      }
      _skillsStoragePath = normalizedPath;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateMcpEnabled(bool value) async {
    return _commitMutation(() {
      if (_mcpEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _mcpEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateMcpLazyLoadingMode(McpLazyLoadingMode value) async {
    return _commitMutation(() {
      if (_mcpLazyLoadingMode == value) {
        return _MutationDisposition.successNoChange;
      }
      _mcpLazyLoadingMode = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateMcpLazyLoadingThresholdTokens(int value) async {
    final clamped = value < AppSettingsSnapshot.minMcpLazyLoadingThresholdTokens
        ? AppSettingsSnapshot.defaultMcpLazyLoadingThresholdTokens
        : value.clamp(
            AppSettingsSnapshot.minMcpLazyLoadingThresholdTokens,
            AppSettingsSnapshot.maxMcpLazyLoadingThresholdTokens,
          );
    return _commitMutation(() {
      if (_mcpLazyLoadingThresholdTokens == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _mcpLazyLoadingThresholdTokens = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateMemoryEnabled(bool value) async {
    return _commitMutation(() {
      if (_memoryEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _memoryEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateUserMemoryFilePath(String value) async {
    final normalizedPath = OpenHandPaths.normalizePath(
      value,
      defaultPath: OpenHandPaths.defaultUserMemoryFilePath(),
    );
    return _commitMutation(() {
      if (_userMemoryFilePath == normalizedPath) {
        return _MutationDisposition.successNoChange;
      }
      _userMemoryFilePath = normalizedPath;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateEditorWordWrap(bool value) async {
    return _commitMutation(() {
      if (_editorWordWrap == value) {
        return _MutationDisposition.successNoChange;
      }
      _editorWordWrap = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateEditorIndentSpaces(int value) async {
    final normalizedValue = normalizeEditorIndentSpaces(value);
    return _commitMutation(() {
      if (_editorIndentSpaces == normalizedValue) {
        return _MutationDisposition.successNoChange;
      }
      _editorIndentSpaces = normalizedValue;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateEditorCodeTheme(EditorCodeTheme value) async {
    return _commitMutation(() {
      if (_editorCodeTheme == value) {
        return _MutationDisposition.successNoChange;
      }
      _editorCodeTheme = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateEditorLspSettings(
    String language,
    AiLspLanguageSettings value,
  ) async {
    final normalizedLanguage = normalizeAiLspLanguage(language);
    if (normalizedLanguage == 'plaintext') {
      return false;
    }
    final normalizedValue = AiLspLanguageSettings(
      backendId: value.backendId.trim(),
      rootPath: OpenHandPaths.normalizeOptionalPath(value.rootPath),
      sdkPath: OpenHandPaths.normalizeOptionalPath(value.sdkPath),
      version: value.version.trim(),
    );
    return _commitMutation(() {
      final next = _cloneEditorLspSettingsMap(_editorLspSettings);
      if (normalizedValue.isEmpty) {
        if (!next.containsKey(normalizedLanguage)) {
          return _MutationDisposition.successNoChange;
        }
        next.remove(normalizedLanguage);
      } else {
        if (next[normalizedLanguage] == normalizedValue) {
          return _MutationDisposition.successNoChange;
        }
        next[normalizedLanguage] = normalizedValue;
      }
      _editorLspSettings = next;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiMessageCompressionThresholdChars(int value) async {
    final normalizedValue =
        AppSettingsSnapshot.normalizeAiMessageCompressionThresholdChars(value);
    return _commitMutation(() {
      if (_aiMessageCompressionThresholdChars == normalizedValue) {
        return _MutationDisposition.successNoChange;
      }
      _aiMessageCompressionThresholdChars = normalizedValue;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiToolResultCompressionThresholdChars(int value) async {
    final clamped =
        AppSettingsSnapshot.normalizeAiToolResultCompressionThresholdChars(
          value,
        );
    return _commitMutation(() {
      if (_aiToolResultCompressionThresholdChars == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiToolResultCompressionThresholdChars = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiToolResultCompressionEnabled(bool value) async {
    return _commitMutation(() {
      if (_aiToolResultCompressionEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _aiToolResultCompressionEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiToolResultCompressionHeadTailWindowChars(
    int value,
  ) async {
    final clamped = value < 0
        ? AppSettingsSnapshot.defaultAiToolResultCompressionHeadTailWindowChars
        : value.clamp(
            AppSettingsSnapshot.minAiToolResultCompressionHeadTailWindowChars,
            AppSettingsSnapshot.maxAiToolResultCompressionHeadTailWindowChars,
          );
    return _commitMutation(() {
      if (_aiToolResultCompressionHeadTailWindowChars == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiToolResultCompressionHeadTailWindowChars = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiToolResultCompressionMaxPathHits(int value) async {
    final clamped = value < 0
        ? AppSettingsSnapshot.defaultAiToolResultCompressionMaxPathHits
        : value.clamp(
            AppSettingsSnapshot.minAiToolResultCompressionMaxPathHits,
            AppSettingsSnapshot.maxAiToolResultCompressionMaxPathHits,
          );
    return _commitMutation(() {
      if (_aiToolResultCompressionMaxPathHits == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiToolResultCompressionMaxPathHits = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiInputCacheEnabled(bool value) async {
    return _commitMutation(() {
      if (_aiInputCacheEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _aiInputCacheEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiInputCacheUpdateMode(String value) async {
    final normalized =
        AppSettingsSnapshot.validAiInputCacheUpdateModes.contains(value)
        ? value
        : AppSettingsSnapshot.defaultAiInputCacheUpdateMode;
    return _commitMutation(() {
      if (_aiInputCacheUpdateMode == normalized) {
        return _MutationDisposition.successNoChange;
      }
      _aiInputCacheUpdateMode = normalized;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiInputCacheUpdateInterval(int value) async {
    final clamped = value < AppSettingsSnapshot.minAiInputCacheUpdateInterval
        ? AppSettingsSnapshot.defaultAiInputCacheUpdateInterval
        : value.clamp(
            AppSettingsSnapshot.minAiInputCacheUpdateInterval,
            AppSettingsSnapshot.maxAiInputCacheUpdateInterval,
          );
    return _commitMutation(() {
      if (_aiInputCacheUpdateInterval == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiInputCacheUpdateInterval = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiInputCacheBreakpointCount(int value) async {
    final clamped = value < AppSettingsSnapshot.minAiInputCacheBreakpointCount
        ? AppSettingsSnapshot.defaultAiInputCacheBreakpointCount
        : value.clamp(
            AppSettingsSnapshot.minAiInputCacheBreakpointCount,
            AppSettingsSnapshot.maxAiInputCacheBreakpointCount,
          );
    return _commitMutation(() {
      if (_aiInputCacheBreakpointCount == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiInputCacheBreakpointCount = clamped;
      return _MutationDisposition.apply;
    });
  }

  /// 2026-05-04 — 提交用户拖拽得到的前 N-1 个缓存点位置。空列表表示
  /// 撤销自定义、回到 mode-based 自动布点。
  Future<bool> updateAiInputCacheBreakpointPositions(
    List<double> positions,
  ) async {
    final cleaned = <double>[];
    for (final v in positions) {
      if (!v.isFinite || v.isNaN) continue;
      cleaned.add(v.clamp(0.0, 1.0));
    }
    cleaned.sort();
    final next = List<double>.unmodifiable(cleaned);
    return _commitMutation(() {
      if (_listEqualsDouble(_aiInputCacheBreakpointPositions, next)) {
        return _MutationDisposition.successNoChange;
      }
      _aiInputCacheBreakpointPositions = next;
      return _MutationDisposition.apply;
    });
  }

  /// 2026-05-06 — 单会话 USD 预算上限。0 表示关闭预算告警。
  Future<bool> updateAiBudgetUsdPerSession(double value) async {
    final clamped = (value.isFinite && !value.isNaN)
        ? value.clamp(
            AppSettingsSnapshot.minAiBudgetUsdPerSession,
            AppSettingsSnapshot.maxAiBudgetUsdPerSession,
          )
        : AppSettingsSnapshot.defaultAiBudgetUsdPerSession;
    return _commitMutation(() {
      if (_aiBudgetUsdPerSession == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiBudgetUsdPerSession = clamped;
      return _MutationDisposition.apply;
    });
  }

  static bool _listEqualsDouble(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<bool> updateAiWriteToolSummaryMaxChars(int value) async {
    final clamped = value < 0
        ? AppSettingsSnapshot.defaultAiWriteToolSummaryMaxChars
        : value.clamp(
            AppSettingsSnapshot.minAiWriteToolSummaryMaxChars,
            AppSettingsSnapshot.maxAiWriteToolSummaryMaxChars,
          );
    return _commitMutation(() {
      if (_aiWriteToolSummaryMaxChars == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiWriteToolSummaryMaxChars = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiSingleRoundToolCallLimit(int value) async {
    final normalizedValue = value <= 0
        ? AppSettingsSnapshot.defaultAiSingleRoundToolCallLimit
        : value;
    return _commitMutation(() {
      if (_aiSingleRoundToolCallLimit == normalizedValue) {
        return _MutationDisposition.successNoChange;
      }
      _aiSingleRoundToolCallLimit = normalizedValue;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiSequentialToolRoundLimit(int value) async {
    final normalizedValue = value <= 0
        ? AppSettingsSnapshot.defaultAiSequentialToolRoundLimit
        : value;
    return _commitMutation(() {
      if (_aiSequentialToolRoundLimit == normalizedValue) {
        return _MutationDisposition.successNoChange;
      }
      _aiSequentialToolRoundLimit = normalizedValue;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiMaxRecentErrors(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiMaxRecentErrors,
      AppSettingsSnapshot.maxAiMaxRecentErrors,
    );
    return _commitMutation(() {
      if (_aiMaxRecentErrors == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiMaxRecentErrors = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiMaxPlanHistoryEntries(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiMaxPlanHistoryEntries,
      AppSettingsSnapshot.maxAiMaxPlanHistoryEntries,
    );
    return _commitMutation(() {
      if (_aiMaxPlanHistoryEntries == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiMaxPlanHistoryEntries = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiMaxTruncationContinuations(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiMaxTruncationContinuations,
      AppSettingsSnapshot.maxAiMaxTruncationContinuations,
    );
    return _commitMutation(() {
      if (_aiMaxTruncationContinuations == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiMaxTruncationContinuations = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiEstimatedCharactersPerToken(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiEstimatedCharactersPerToken,
      AppSettingsSnapshot.maxAiEstimatedCharactersPerToken,
    );
    return _commitMutation(() {
      if (_aiEstimatedCharactersPerToken == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiEstimatedCharactersPerToken = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiMaxToolOutputChars(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiMaxToolOutputChars,
      AppSettingsSnapshot.maxAiMaxToolOutputChars,
    );
    return _commitMutation(() {
      if (_aiMaxToolOutputChars == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiMaxToolOutputChars = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiWriteConfirmationTimeoutMs(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiWriteConfirmationTimeoutMs,
      AppSettingsSnapshot.maxAiWriteConfirmationTimeoutMs,
    );
    return _commitMutation(() {
      if (_aiWriteConfirmationTimeoutMs == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiWriteConfirmationTimeoutMs = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiFastPathWriteAnalysisThreshold(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiFastPathWriteAnalysisThreshold,
      AppSettingsSnapshot.maxAiFastPathWriteAnalysisThreshold,
    );
    return _commitMutation(() {
      if (_aiFastPathWriteAnalysisThreshold == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiFastPathWriteAnalysisThreshold = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiMaxHookTextCharacters(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiMaxHookTextCharacters,
      AppSettingsSnapshot.maxAiMaxHookTextCharacters,
    );
    return _commitMutation(() {
      if (_aiMaxHookTextCharacters == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiMaxHookTextCharacters = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiWebFetchMaxResponseBytes(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiWebFetchMaxResponseBytes,
      AppSettingsSnapshot.maxAiWebFetchMaxResponseBytes,
    );
    return _commitMutation(() {
      if (_aiWebFetchMaxResponseBytes == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiWebFetchMaxResponseBytes = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiWebFetchMaxRedirects(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiWebFetchMaxRedirects,
      AppSettingsSnapshot.maxAiWebFetchMaxRedirects,
    );
    return _commitMutation(() {
      if (_aiWebFetchMaxRedirects == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiWebFetchMaxRedirects = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiWebFetchMaxCacheEntries(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiWebFetchMaxCacheEntries,
      AppSettingsSnapshot.maxAiWebFetchMaxCacheEntries,
    );
    return _commitMutation(() {
      if (_aiWebFetchMaxCacheEntries == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiWebFetchMaxCacheEntries = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiAttachmentMaxInlineImageDimension(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiAttachmentMaxInlineImageDimension,
      AppSettingsSnapshot.maxAiAttachmentMaxInlineImageDimension,
    );
    return _commitMutation(() {
      if (_aiAttachmentMaxInlineImageDimension == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiAttachmentMaxInlineImageDimension = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiAttachmentMaxTextRawBytes(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiAttachmentMaxTextRawBytes,
      AppSettingsSnapshot.maxAiAttachmentMaxTextRawBytes,
    );
    return _commitMutation(() {
      if (_aiAttachmentMaxTextRawBytes == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiAttachmentMaxTextRawBytes = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiAttachmentMaxPdfRawBytes(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiAttachmentMaxPdfRawBytes,
      AppSettingsSnapshot.maxAiAttachmentMaxPdfRawBytes,
    );
    return _commitMutation(() {
      if (_aiAttachmentMaxPdfRawBytes == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiAttachmentMaxPdfRawBytes = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiAttachmentMaxImageRawBytes(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiAttachmentMaxImageRawBytes,
      AppSettingsSnapshot.maxAiAttachmentMaxImageRawBytes,
    );
    return _commitMutation(() {
      if (_aiAttachmentMaxImageRawBytes == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiAttachmentMaxImageRawBytes = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiChatMaxStreamLineBufferBytes(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiChatMaxStreamLineBufferBytes,
      AppSettingsSnapshot.maxAiChatMaxStreamLineBufferBytes,
    );
    return _commitMutation(() {
      if (_aiChatMaxStreamLineBufferBytes == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiChatMaxStreamLineBufferBytes = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiFallbackTitleMaxCharacters(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiFallbackTitleMaxCharacters,
      AppSettingsSnapshot.maxAiFallbackTitleMaxCharacters,
    );
    return _commitMutation(() {
      if (_aiFallbackTitleMaxCharacters == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiFallbackTitleMaxCharacters = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiGeneratedTitleMaxCharacters(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiGeneratedTitleMaxCharacters,
      AppSettingsSnapshot.maxAiGeneratedTitleMaxCharacters,
    );
    return _commitMutation(() {
      if (_aiGeneratedTitleMaxCharacters == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiGeneratedTitleMaxCharacters = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiMinimumMeaningfulTitleCharacters(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiMinimumMeaningfulTitleCharacters,
      AppSettingsSnapshot.maxAiMinimumMeaningfulTitleCharacters,
    );
    return _commitMutation(() {
      if (_aiMinimumMeaningfulTitleCharacters == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiMinimumMeaningfulTitleCharacters = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiMinimumMeaningfulLatinTitleWords(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiMinimumMeaningfulLatinTitleWords,
      AppSettingsSnapshot.maxAiMinimumMeaningfulLatinTitleWords,
    );
    return _commitMutation(() {
      if (_aiMinimumMeaningfulLatinTitleWords == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiMinimumMeaningfulLatinTitleWords = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiMaxSkillContentLength(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiMaxSkillContentLength,
      AppSettingsSnapshot.maxAiMaxSkillContentLength,
    );
    return _commitMutation(() {
      if (_aiMaxSkillContentLength == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiMaxSkillContentLength = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiMaxWorkspaceDocumentCharacters(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minAiMaxWorkspaceDocumentCharacters,
      AppSettingsSnapshot.maxAiMaxWorkspaceDocumentCharacters,
    );
    return _commitMutation(() {
      if (_aiMaxWorkspaceDocumentCharacters == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _aiMaxWorkspaceDocumentCharacters = clamped;
      return _MutationDisposition.apply;
    });
  }

  /// Updates the per-image attachment size cap (bytes).
  ///
  /// Values outside
  /// `[AppSettingsSnapshot.minAiImageSizeLimitBytes,
  ///   AppSettingsSnapshot.maxAiImageSizeLimitBytes]`
  /// are clamped so a misconfigured value cannot break the attachment
  /// pipeline.
  Future<bool> updateAiImageSizeLimitBytes(int value) async {
    final int normalizedValue;
    if (value <= 0) {
      normalizedValue = AppSettingsSnapshot.defaultAiImageSizeLimitBytes;
    } else {
      normalizedValue = value.clamp(
        AppSettingsSnapshot.minAiImageSizeLimitBytes,
        AppSettingsSnapshot.maxAiImageSizeLimitBytes,
      );
    }
    return _commitMutation(() {
      if (_aiImageSizeLimitBytes == normalizedValue) {
        return _MutationDisposition.successNoChange;
      }
      _aiImageSizeLimitBytes = normalizedValue;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiWriteCommandConfirmationEnabled(bool value) async {
    return _commitMutation(() {
      if (_aiWriteCommandConfirmationEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _aiWriteCommandConfirmationEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiConnectTimeoutSeconds(int value) async {
    final normalizedValue =
        value < AppSettingsSnapshot.minAiConnectTimeoutSeconds
        ? AppSettingsSnapshot.defaultAiConnectTimeoutSeconds
        : value.clamp(
            AppSettingsSnapshot.minAiConnectTimeoutSeconds,
            AppSettingsSnapshot.maxAiConnectTimeoutSeconds,
          );
    return _commitMutation(() {
      if (_aiConnectTimeoutSeconds == normalizedValue) {
        return _MutationDisposition.successNoChange;
      }
      _aiConnectTimeoutSeconds = normalizedValue;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiResponseTimeoutSeconds(int value) async {
    final normalizedValue =
        value < AppSettingsSnapshot.minAiResponseTimeoutSeconds
        ? AppSettingsSnapshot.defaultAiResponseTimeoutSeconds
        : value.clamp(
            AppSettingsSnapshot.minAiResponseTimeoutSeconds,
            AppSettingsSnapshot.maxAiResponseTimeoutSeconds,
          );
    return _commitMutation(() {
      if (_aiResponseTimeoutSeconds == normalizedValue) {
        return _MutationDisposition.successNoChange;
      }
      _aiResponseTimeoutSeconds = normalizedValue;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiStreamIdleTimeoutSeconds(int value) async {
    final normalizedValue =
        value < AppSettingsSnapshot.minAiStreamIdleTimeoutSeconds
        ? AppSettingsSnapshot.defaultAiStreamIdleTimeoutSeconds
        : value.clamp(
            AppSettingsSnapshot.minAiStreamIdleTimeoutSeconds,
            AppSettingsSnapshot.maxAiStreamIdleTimeoutSeconds,
          );
    return _commitMutation(() {
      if (_aiStreamIdleTimeoutSeconds == normalizedValue) {
        return _MutationDisposition.successNoChange;
      }
      _aiStreamIdleTimeoutSeconds = normalizedValue;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiAutoTitleEnabled(bool value) async {
    return _commitMutation(() {
      if (_aiAutoTitleEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _aiAutoTitleEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiDefaultSessionMode(String value) async {
    final normalized = value.trim() == 'plan' ? 'plan' : 'chat';
    return _commitMutation(() {
      if (_aiDefaultSessionMode == normalized) {
        return _MutationDisposition.successNoChange;
      }
      _aiDefaultSessionMode = normalized;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiDefaultFullAccessPermission(bool value) async {
    return _commitMutation(() {
      if (_aiDefaultFullAccessPermission == value) {
        return _MutationDisposition.successNoChange;
      }
      _aiDefaultFullAccessPermission = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> addAiAllowCommandRule(AiAllowCommandRule rule) async {
    return _commitMutation(() {
      if (_aiAllowCommandRules.any((item) => item.id == rule.id)) {
        return _MutationDisposition.reject;
      }
      _aiAllowCommandRules = <AiAllowCommandRule>[
        ..._aiAllowCommandRules,
        rule,
      ];
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiAllowCommandRule(AiAllowCommandRule rule) async {
    return _commitMutation(() {
      final index = _aiAllowCommandRules.indexWhere(
        (item) => item.id == rule.id,
      );
      if (index == -1) {
        return _MutationDisposition.reject;
      }
      final updatedRules = List<AiAllowCommandRule>.from(_aiAllowCommandRules);
      updatedRules[index] = rule;
      _aiAllowCommandRules = updatedRules;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> deleteAiAllowCommandRule(String id) async {
    return _commitMutation(() {
      final updatedRules = _aiAllowCommandRules
          .where((item) => item.id != id)
          .toList(growable: false);
      if (updatedRules.length == _aiAllowCommandRules.length) {
        return _MutationDisposition.successNoChange;
      }
      _aiAllowCommandRules = updatedRules;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> addAiDenyCommandRule(AiDenyCommandRule rule) async {
    return _commitMutation(() {
      if (_aiDenyCommandRules.any((item) => item.id == rule.id)) {
        return _MutationDisposition.reject;
      }
      _aiDenyCommandRules = <AiDenyCommandRule>[..._aiDenyCommandRules, rule];
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiDenyCommandRule(AiDenyCommandRule rule) async {
    return _commitMutation(() {
      final index = _aiDenyCommandRules.indexWhere(
        (item) => item.id == rule.id,
      );
      if (index == -1) {
        return _MutationDisposition.reject;
      }
      final updatedRules = List<AiDenyCommandRule>.from(_aiDenyCommandRules);
      updatedRules[index] = rule;
      _aiDenyCommandRules = updatedRules;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> deleteAiDenyCommandRule(String id) async {
    return _commitMutation(() {
      final updatedRules = _aiDenyCommandRules
          .where((item) => item.id != id)
          .toList(growable: false);
      if (updatedRules.length == _aiDenyCommandRules.length) {
        return _MutationDisposition.successNoChange;
      }
      _aiDenyCommandRules = updatedRules;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> saveAiModel(AiModelConfig value) async {
    return _commitMutation(() {
      final normalizedAvailableModelIds = AiModelConfig.normalizeModelIds(
        value.availableModelIds,
      );
      final normalizedModelId = value.modelId.trim().isNotEmpty
          ? value.modelId.trim()
          : (normalizedAvailableModelIds.isNotEmpty
                ? normalizedAvailableModelIds.first
                : '');
      final normalizedValue = value.copyWith(
        modelId: normalizedModelId,
        availableModelIds: AiModelConfig.normalizeModelIds(<String>[
          ...normalizedAvailableModelIds,
          if (normalizedModelId.isNotEmpty) normalizedModelId,
        ]),
      );
      final updatedModels = List<AiModelConfig>.from(_aiModels);
      final index = updatedModels.indexWhere(
        (item) => item.id == normalizedValue.id,
      );
      if (index == -1) {
        updatedModels.add(normalizedValue);
      } else {
        updatedModels[index] = normalizedValue;
      }
      final nextSelectedModelId = _selectedAiModelId ?? normalizedValue.id;
      _aiModels = updatedModels;
      _cachedAiModelsView = null;
      _recentModelSelections = _sanitizeRecentModelSelections(
        _recentModelSelections,
        updatedModels,
      );
      _cachedRecentModelSelectionsView = null;
      _selectedAiModelId =
          updatedModels.any((item) => item.id == nextSelectedModelId)
          ? nextSelectedModelId
          : normalizedValue.id;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> deleteAiModel(String id) async {
    return _commitMutation(() {
      final updatedModels = _aiModels.where((item) => item.id != id).toList();
      if (updatedModels.length == _aiModels.length) {
        return _MutationDisposition.successNoChange;
      }
      _aiModels = updatedModels;
      _cachedAiModelsView = null;
      _recentModelSelections = _sanitizeRecentModelSelections(
        _recentModelSelections,
        updatedModels,
      );
      _cachedRecentModelSelectionsView = null;
      if (_selectedAiModelId == id) {
        _selectedAiModelId = _aiModels.isEmpty ? null : _aiModels.first.id;
      }
      return _MutationDisposition.apply;
    });
  }

  Future<bool> moveAiModel(int fromIndex, int toIndex) async {
    return _commitMutation(() {
      if (fromIndex < 0 ||
          toIndex < 0 ||
          fromIndex >= _aiModels.length ||
          toIndex >= _aiModels.length ||
          fromIndex == toIndex) {
        return _MutationDisposition.successNoChange;
      }
      final updatedModels = List<AiModelConfig>.from(_aiModels);
      final model = updatedModels.removeAt(fromIndex);
      updatedModels.insert(toIndex, model);
      _aiModels = updatedModels;
      _cachedAiModelsView = null;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateSelectedAiModel(String? id) async {
    return _commitMutation(() {
      if (id != null && !_aiModels.any((item) => item.id == id)) {
        return _MutationDisposition.reject;
      }
      if (_selectedAiModelId == id) {
        return _MutationDisposition.successNoChange;
      }
      _selectedAiModelId = id;
      return _MutationDisposition.apply;
    });
  }

  /// Updates the active model ID for a specific provider config, and
  /// simultaneously selects that provider as the current one.
  Future<bool> updateProviderActiveModel(
    String providerConfigId,
    String modelId,
  ) async {
    return _commitMutation(() {
      final index = _aiModels.indexWhere((item) => item.id == providerConfigId);
      if (index == -1) {
        return _MutationDisposition.reject;
      }
      final normalizedModelId = modelId.trim();
      final updatedModels = List<AiModelConfig>.from(_aiModels);
      final current = updatedModels[index];
      updatedModels[index] = current.copyWith(
        modelId: normalizedModelId,
        availableModelIds: AiModelConfig.normalizeModelIds(<String>[
          ...current.availableModelIds,
          if (normalizedModelId.isNotEmpty) normalizedModelId,
        ]),
      );
      _aiModels = updatedModels;
      _cachedAiModelsView = null;
      _selectedAiModelId = providerConfigId;
      return _MutationDisposition.apply;
    });
  }

  /// Updates the available model IDs list for a specific provider config.
  Future<bool> updateProviderAvailableModels(
    String providerConfigId,
    List<String> availableModelIds,
  ) async {
    return _commitMutation(() {
      final index = _aiModels.indexWhere((item) => item.id == providerConfigId);
      if (index == -1) {
        return _MutationDisposition.reject;
      }
      final updatedModels = List<AiModelConfig>.from(_aiModels);
      final current = updatedModels[index];
      final normalizedAvailableModelIds = AiModelConfig.normalizeModelIds(
        availableModelIds,
      );
      final normalizedModelId = current.modelId.trim().isNotEmpty
          ? current.modelId.trim()
          : (normalizedAvailableModelIds.isNotEmpty
                ? normalizedAvailableModelIds.first
                : '');
      updatedModels[index] = current.copyWith(
        availableModelIds: AiModelConfig.normalizeModelIds(<String>[
          ...normalizedAvailableModelIds,
          if (normalizedModelId.isNotEmpty) normalizedModelId,
        ]),
        modelId: normalizedModelId,
      );
      _aiModels = updatedModels;
      _cachedAiModelsView = null;
      _recentModelSelections = _sanitizeRecentModelSelections(
        _recentModelSelections,
        updatedModels,
      );
      _cachedRecentModelSelectionsView = null;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> addRecentModelSelection(String configId, String modelId) async {
    final normalizedConfigId = configId.trim();
    final normalizedModelId = modelId.trim();
    if (normalizedConfigId.isEmpty || normalizedModelId.isEmpty) {
      return false;
    }
    return _commitMutation(() {
      final exists = _aiModels.any(
        (item) =>
            item.id == normalizedConfigId &&
            item.allModelIds.contains(normalizedModelId),
      );
      if (!exists) {
        return _MutationDisposition.successNoChange;
      }
      final next = <RecentModelSelection>[
        RecentModelSelection(
          configId: normalizedConfigId,
          modelId: normalizedModelId,
        ),
        ..._recentModelSelections,
      ];
      final sanitized = _sanitizeRecentModelSelections(next, _aiModels);
      if (_sameRecentSelectionList(sanitized, _recentModelSelections)) {
        return _MutationDisposition.successNoChange;
      }
      _recentModelSelections = sanitized;
      _cachedRecentModelSelectionsView = null;
      return _MutationDisposition.apply;
    });
  }

  /// Returns a flattened list of (providerConfigId, modelId) pairs for the
  /// model selector UI. Each entry represents one selectable model across all
  /// providers. Providers with no available models are skipped.
  List<({String providerConfigId, String modelId, String providerLabel})>
  get flatModelEntries {
    final entries =
        <({String providerConfigId, String modelId, String providerLabel})>[];
    for (final config in _aiModels) {
      final allIds = config.allModelIds;
      if (allIds.isEmpty) {
        continue;
      }
      for (final modelId in allIds) {
        entries.add((
          providerConfigId: config.id,
          modelId: modelId,
          providerLabel: config.providerLabel,
        ));
      }
    }
    return entries;
  }

  Future<bool> updateShortcutBinding(
    OpenHandShortcutAction action,
    List<int> keyIds,
  ) async {
    final normalizedKeyIds = normalizeShortcutKeyIds(keyIds);
    if (!isValidShortcutBinding(normalizedKeyIds)) {
      return false;
    }
    return _commitMutation(() {
      final currentKeyIds = _shortcutBindings[action] ?? const <int>[];
      if (_sameIntList(currentKeyIds, normalizedKeyIds)) {
        return _MutationDisposition.successNoChange;
      }
      _shortcutBindings = <OpenHandShortcutAction, List<int>>{
        ..._shortcutBindings,
        action: normalizedKeyIds,
      };
      return _MutationDisposition.apply;
    });
  }

  Future<bool> resetShortcutBinding(OpenHandShortcutAction action) async {
    return updateShortcutBinding(
      action,
      defaultOpenHandShortcutBindings()[action] ?? const <int>[],
    );
  }

  Future<bool> updateEditorShortcutBinding(
    EditorShortcutAction action,
    List<int> keyIds,
  ) async {
    final normalizedKeyIds = normalizeShortcutKeyIds(keyIds);
    if (!isValidShortcutBinding(normalizedKeyIds)) {
      return false;
    }
    return _commitMutation(() {
      final currentKeyIds = _editorShortcutBindings[action] ?? const <int>[];
      if (_sameIntList(currentKeyIds, normalizedKeyIds)) {
        return _MutationDisposition.successNoChange;
      }
      _editorShortcutBindings = <EditorShortcutAction, List<int>>{
        ..._editorShortcutBindings,
        action: normalizedKeyIds,
      };
      return _MutationDisposition.apply;
    });
  }

  Future<bool> resetEditorShortcutBinding(EditorShortcutAction action) async {
    return updateEditorShortcutBinding(
      action,
      defaultEditorShortcutBindings()[action] ?? const <int>[],
    );
  }

  Future<bool> updateDialogAnimationSettings(
    DialogAnimationSettings value,
  ) async {
    return _commitMutation(() {
      if (_dialogAnimationSettings == value) {
        return _MutationDisposition.successNoChange;
      }
      _dialogAnimationSettings = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateMenuAnimationSettings(
    DialogAnimationSettings value,
  ) async {
    return _commitMutation(() {
      if (_menuAnimationSettings == value) {
        return _MutationDisposition.successNoChange;
      }
      _menuAnimationSettings = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updatePageAnimationSettings(
    DialogAnimationSettings value,
  ) async {
    return _commitMutation(() {
      if (_pageAnimationSettings == value) {
        return _MutationDisposition.successNoChange;
      }
      _pageAnimationSettings = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updatePanelAnimationSettings(
    DialogAnimationSettings value,
  ) async {
    return _commitMutation(() {
      if (_panelAnimationSettings == value) {
        return _MutationDisposition.successNoChange;
      }
      _panelAnimationSettings = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateChipAnimationSettings(
    DialogAnimationSettings value,
  ) async {
    return _commitMutation(() {
      if (_chipAnimationSettings == value) {
        return _MutationDisposition.successNoChange;
      }
      _chipAnimationSettings = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateListItemAnimationSettings(
    DialogAnimationSettings value,
  ) async {
    return _commitMutation(() {
      if (_listItemAnimationSettings == value) {
        return _MutationDisposition.successNoChange;
      }
      _listItemAnimationSettings = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateTelemetryDebugEnabled(bool value) async {
    return _commitMutation(() {
      if (_telemetryDebugEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _telemetryDebugEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateTelemetryCaptureRawPayload(bool value) async {
    return _commitMutation(() {
      if (_telemetryCaptureRawPayload == value) {
        return _MutationDisposition.successNoChange;
      }
      _telemetryCaptureRawPayload = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateTelemetryCaptureEnvironment(bool value) async {
    return _commitMutation(() {
      if (_telemetryCaptureEnvironment == value) {
        return _MutationDisposition.successNoChange;
      }
      _telemetryCaptureEnvironment = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateTelemetryMaxPayloadChars(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minTelemetryMaxPayloadChars,
      AppSettingsSnapshot.maxTelemetryMaxPayloadChars,
    );
    return _commitMutation(() {
      if (_telemetryMaxPayloadChars == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _telemetryMaxPayloadChars = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateSelfLearningEnabled(bool value) async {
    return _commitMutation(() {
      if (_selfLearningEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _selfLearningEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateSelfLearningConcurrency(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minSelfLearningConcurrency,
      AppSettingsSnapshot.maxSelfLearningConcurrency,
    );
    return _commitMutation(() {
      if (_selfLearningConcurrency == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _selfLearningConcurrency = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateSelfLearningStreamFlushIntervalMs(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minSelfLearningStreamFlushIntervalMs,
      AppSettingsSnapshot.maxSelfLearningStreamFlushIntervalMs,
    );
    return _commitMutation(() {
      if (_selfLearningStreamFlushIntervalMs == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _selfLearningStreamFlushIntervalMs = clamped;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateShowSelfLearningMessages(bool value) async {
    return _commitMutation(() {
      if (_showSelfLearningMessages == value) {
        return _MutationDisposition.successNoChange;
      }
      _showSelfLearningMessages = value;
      return _MutationDisposition.apply;
    });
  }

  // 2026-04-25 — 定时任务（cron）执行历史的冷启动自动清理设置。
  Future<bool> updateCronAutoCleanupEnabled(bool value) async {
    return _commitMutation(() {
      if (_cronAutoCleanupEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _cronAutoCleanupEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateCronAutoCleanupRetentionDays(int value) async {
    final clamped = value.clamp(
      AppSettingsSnapshot.minCronAutoCleanupRetentionDays,
      AppSettingsSnapshot.maxCronAutoCleanupRetentionDays,
    );
    return _commitMutation(() {
      if (_cronAutoCleanupRetentionDays == clamped) {
        return _MutationDisposition.successNoChange;
      }
      _cronAutoCleanupRetentionDays = clamped;
      return _MutationDisposition.apply;
    });
  }

  // 2026-05 — 减少动画总开关。
  Future<bool> updateReduceMotion(bool value) async {
    return _commitMutation(() {
      if (_reduceMotion == value) {
        return _MutationDisposition.successNoChange;
      }
      _reduceMotion = value;
      return _MutationDisposition.apply;
    });
  }

  /// 更新系统代理配置。允许部分字段更新（任何 `null` 表示保持原值）。
  /// 所有字段会经过 `AppProxySettings.copyWith` 合并，再做必需的归一化
  /// （如 host trim、port 钳位、protocols 去空集合 fallback）。
  Future<bool> updateProxySettings({
    AppProxyMode? mode,
    Set<AppProxyProtocol>? protocols,
    String? host,
    int? port,
    bool? authEnabled,
    String? username,
    String? password,
    List<String>? exceptions,
    String? testEndpoint,
  }) async {
    return _commitMutation(() {
      final normalizedHost = host?.trim();
      final normalizedPort = port?.clamp(1, 65535);
      final normalizedProtocols = (protocols == null || protocols.isEmpty)
          ? null
          : protocols;
      final normalizedExceptions = exceptions
          ?.map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      String? normalizedTestEndpoint;
      if (testEndpoint != null) {
        final trimmed = testEndpoint.trim();
        normalizedTestEndpoint = trimmed.isEmpty
            ? AppProxySettings.defaultTestEndpoint
            : trimmed;
      }
      final next = _proxySettings.copyWith(
        mode: mode,
        protocols: normalizedProtocols,
        host: normalizedHost,
        port: normalizedPort,
        authEnabled: authEnabled,
        username: username,
        password: password,
        exceptions: normalizedExceptions,
        testEndpoint: normalizedTestEndpoint,
      );
      if (next == _proxySettings) {
        return _MutationDisposition.successNoChange;
      }
      _proxySettings = next;
      return _MutationDisposition.apply;
    });
  }

  String createAiModelId() {
    return _uuid.v4();
  }

  String createAiDenyCommandRuleId() {
    return _uuid.v4();
  }

  String createAiAllowCommandRuleId() {
    return _uuid.v4();
  }

  // ─────────────────────────────────────────────────────────────
  // Builtin Tool Config mutations
  // ─────────────────────────────────────────────────────────────

  Future<bool> updateBuiltinToolConfigs(
    List<AiBuiltinToolConfig> configs,
  ) async {
    return _commitMutation(() {
      _builtinToolConfigs = List<AiBuiltinToolConfig>.from(configs);
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateBuiltinToolConfig(AiBuiltinToolConfig config) async {
    return _commitMutation(() {
      final index = _builtinToolConfigs.indexWhere(
        (c) => c.kind == config.kind,
      );
      if (index >= 0) {
        _builtinToolConfigs[index] = config;
      } else {
        _builtinToolConfigs.add(config);
      }
      return _MutationDisposition.apply;
    });
  }

  Future<bool> removeBuiltinToolConfig(AiBuiltinToolKind kind) async {
    return _commitMutation(() {
      _builtinToolConfigs.removeWhere((c) => c.kind == kind && c.isCustom);
      return _MutationDisposition.apply;
    });
  }

  Future<bool> resetBuiltinToolConfigs() async {
    return _commitMutation(() {
      _builtinToolConfigs = AiBuiltinToolConfig.defaults();
      return _MutationDisposition.apply;
    });
  }

  Future<bool> moveBuiltinToolConfig(int oldIndex, int newIndex) async {
    return _commitMutation(() {
      if (oldIndex < 0 ||
          oldIndex >= _builtinToolConfigs.length ||
          newIndex < 0 ||
          newIndex >= _builtinToolConfigs.length ||
          oldIndex == newIndex) {
        return _MutationDisposition.successNoChange;
      }
      final item = _builtinToolConfigs.removeAt(oldIndex);
      _builtinToolConfigs.insert(newIndex, item);
      // 更新 sortOrder 以反映新位置
      for (var i = 0; i < _builtinToolConfigs.length; i++) {
        _builtinToolConfigs[i] = _builtinToolConfigs[i].copyWith(sortOrder: i);
      }
      return _MutationDisposition.apply;
    });
  }

  AppSettingsSnapshot _snapshot() {
    return AppSettingsSnapshot(
      themeMode: _themeMode,
      themePreset: _themePreset,
      language: _language,
      skillsStoragePath: _skillsStoragePath,
      mcpEnabled: _mcpEnabled,
      mcpServersFilePath: _mcpServersFilePath,
      mcpLazyLoadingMode: _mcpLazyLoadingMode,
      mcpLazyLoadingThresholdTokens: _mcpLazyLoadingThresholdTokens,
      memoryEnabled: _memoryEnabled,
      userMemoryFilePath: _userMemoryFilePath,
      editorWordWrap: _editorWordWrap,
      editorIndentSpaces: _editorIndentSpaces,
      editorCodeTheme: _editorCodeTheme,
      editorLspSettings: _cloneEditorLspSettingsMap(_editorLspSettings),
      editorShortcutBindings: _cloneEditorShortcutBindings(
        _editorShortcutBindings,
      ),
      aiMessageCompressionThresholdChars: _aiMessageCompressionThresholdChars,
      aiToolResultCompressionThresholdChars:
          _aiToolResultCompressionThresholdChars,
      aiToolResultCompressionEnabled: _aiToolResultCompressionEnabled,
      aiToolResultCompressionHeadTailWindowChars:
          _aiToolResultCompressionHeadTailWindowChars,
      aiToolResultCompressionMaxPathHits: _aiToolResultCompressionMaxPathHits,
      aiInputCacheEnabled: _aiInputCacheEnabled,
      aiInputCacheUpdateMode: _aiInputCacheUpdateMode,
      aiInputCacheUpdateInterval: _aiInputCacheUpdateInterval,
      aiInputCacheBreakpointCount: _aiInputCacheBreakpointCount,
      aiInputCacheBreakpointPositions: _aiInputCacheBreakpointPositions,
      aiBudgetUsdPerSession: _aiBudgetUsdPerSession,
      aiWriteToolSummaryMaxChars: _aiWriteToolSummaryMaxChars,
      aiSingleRoundToolCallLimit: _aiSingleRoundToolCallLimit,
      aiMaxRecentErrors: _aiMaxRecentErrors,
      aiMaxPlanHistoryEntries: _aiMaxPlanHistoryEntries,
      aiMaxTruncationContinuations: _aiMaxTruncationContinuations,
      aiEstimatedCharactersPerToken: _aiEstimatedCharactersPerToken,
      aiMaxToolOutputChars: _aiMaxToolOutputChars,
      aiWriteConfirmationTimeoutMs: _aiWriteConfirmationTimeoutMs,
      aiFastPathWriteAnalysisThreshold: _aiFastPathWriteAnalysisThreshold,
      aiMaxHookTextCharacters: _aiMaxHookTextCharacters,
      aiWebFetchMaxResponseBytes: _aiWebFetchMaxResponseBytes,
      aiWebFetchMaxRedirects: _aiWebFetchMaxRedirects,
      aiWebFetchMaxCacheEntries: _aiWebFetchMaxCacheEntries,
      aiAttachmentMaxInlineImageDimension: _aiAttachmentMaxInlineImageDimension,
      aiAttachmentMaxTextRawBytes: _aiAttachmentMaxTextRawBytes,
      aiAttachmentMaxPdfRawBytes: _aiAttachmentMaxPdfRawBytes,
      aiAttachmentMaxImageRawBytes: _aiAttachmentMaxImageRawBytes,
      aiChatMaxStreamLineBufferBytes: _aiChatMaxStreamLineBufferBytes,
      aiFallbackTitleMaxCharacters: _aiFallbackTitleMaxCharacters,
      aiGeneratedTitleMaxCharacters: _aiGeneratedTitleMaxCharacters,
      aiMinimumMeaningfulTitleCharacters: _aiMinimumMeaningfulTitleCharacters,
      aiMinimumMeaningfulLatinTitleWords: _aiMinimumMeaningfulLatinTitleWords,
      aiMaxSkillContentLength: _aiMaxSkillContentLength,
      aiMaxWorkspaceDocumentCharacters: _aiMaxWorkspaceDocumentCharacters,
      aiSequentialToolRoundLimit: _aiSequentialToolRoundLimit,
      aiImageSizeLimitBytes: _aiImageSizeLimitBytes,
      aiWriteCommandConfirmationEnabled: _aiWriteCommandConfirmationEnabled,
      aiAllowCommandRules: List<AiAllowCommandRule>.from(_aiAllowCommandRules),
      aiDenyCommandRules: List<AiDenyCommandRule>.from(_aiDenyCommandRules),
      aiConnectTimeoutSeconds: _aiConnectTimeoutSeconds,
      aiResponseTimeoutSeconds: _aiResponseTimeoutSeconds,
      aiStreamIdleTimeoutSeconds: _aiStreamIdleTimeoutSeconds,
      aiAutoTitleEnabled: _aiAutoTitleEnabled,
      aiDefaultSessionMode: _aiDefaultSessionMode,
      aiDefaultFullAccessPermission: _aiDefaultFullAccessPermission,
      aiModels: List<AiModelConfig>.from(_aiModels),
      selectedAiModelId: _selectedAiModelId,
      recentModelSelections: List<RecentModelSelection>.from(
        _recentModelSelections,
      ),
      shortcutBindings: _cloneShortcutBindings(_shortcutBindings),
      dialogAnimationSettings: _dialogAnimationSettings,
      menuAnimationSettings: _menuAnimationSettings,
      pageAnimationSettings: _pageAnimationSettings,
      panelAnimationSettings: _panelAnimationSettings,
      chipAnimationSettings: _chipAnimationSettings,
      listItemAnimationSettings: _listItemAnimationSettings,
      builtinToolConfigs: List<AiBuiltinToolConfig>.from(_builtinToolConfigs),
      telemetryDebugEnabled: _telemetryDebugEnabled,
      telemetryCaptureRawPayload: _telemetryCaptureRawPayload,
      telemetryCaptureEnvironment: _telemetryCaptureEnvironment,
      telemetryMaxPayloadChars: _telemetryMaxPayloadChars,
      selfLearningEnabled: _selfLearningEnabled,
      selfLearningConcurrency: _selfLearningConcurrency,
      selfLearningStreamFlushIntervalMs: _selfLearningStreamFlushIntervalMs,
      showSelfLearningMessages: _showSelfLearningMessages,
      cronAutoCleanupEnabled: _cronAutoCleanupEnabled,
      cronAutoCleanupRetentionDays: _cronAutoCleanupRetentionDays,
      reduceMotion: _reduceMotion,
      proxySettings: _proxySettings,
    );
  }

  void _applySnapshot(AppSettingsSnapshot snapshot) {
    _themeMode = snapshot.themeMode;
    _themePreset = snapshot.themePreset;
    _language = snapshot.language;
    _skillsStoragePath = snapshot.skillsStoragePath;
    _mcpEnabled = snapshot.mcpEnabled;
    _mcpLazyLoadingMode = snapshot.mcpLazyLoadingMode;
    _mcpLazyLoadingThresholdTokens = snapshot.mcpLazyLoadingThresholdTokens;
    _mcpServersFilePath = snapshot.mcpServersFilePath;
    _memoryEnabled = snapshot.memoryEnabled;
    _userMemoryFilePath = snapshot.userMemoryFilePath;
    _editorWordWrap = snapshot.editorWordWrap;
    _editorIndentSpaces = snapshot.editorIndentSpaces;
    _editorCodeTheme = snapshot.editorCodeTheme;
    _editorLspSettings = _cloneEditorLspSettingsMap(snapshot.editorLspSettings);
    _editorShortcutBindings = _cloneEditorShortcutBindings(
      snapshot.editorShortcutBindings,
    );
    _aiMessageCompressionThresholdChars =
        snapshot.aiMessageCompressionThresholdChars;
    _aiToolResultCompressionThresholdChars =
        snapshot.aiToolResultCompressionThresholdChars;
    _aiToolResultCompressionEnabled = snapshot.aiToolResultCompressionEnabled;
    _aiToolResultCompressionHeadTailWindowChars =
        snapshot.aiToolResultCompressionHeadTailWindowChars;
    _aiToolResultCompressionMaxPathHits =
        snapshot.aiToolResultCompressionMaxPathHits;
    _aiInputCacheEnabled = snapshot.aiInputCacheEnabled;
    _aiInputCacheUpdateMode = snapshot.aiInputCacheUpdateMode;
    _aiInputCacheUpdateInterval = snapshot.aiInputCacheUpdateInterval;
    _aiInputCacheBreakpointCount = snapshot.aiInputCacheBreakpointCount;
    _aiInputCacheBreakpointPositions = snapshot.aiInputCacheBreakpointPositions;
    _aiBudgetUsdPerSession = snapshot.aiBudgetUsdPerSession;
    _aiWriteToolSummaryMaxChars = snapshot.aiWriteToolSummaryMaxChars;
    _aiSingleRoundToolCallLimit = snapshot.aiSingleRoundToolCallLimit;
    _aiMaxRecentErrors = snapshot.aiMaxRecentErrors;
    _aiMaxPlanHistoryEntries = snapshot.aiMaxPlanHistoryEntries;
    _aiMaxTruncationContinuations = snapshot.aiMaxTruncationContinuations;
    _aiEstimatedCharactersPerToken = snapshot.aiEstimatedCharactersPerToken;
    _aiMaxToolOutputChars = snapshot.aiMaxToolOutputChars;
    _aiWriteConfirmationTimeoutMs = snapshot.aiWriteConfirmationTimeoutMs;
    _aiFastPathWriteAnalysisThreshold =
        snapshot.aiFastPathWriteAnalysisThreshold;
    _aiMaxHookTextCharacters = snapshot.aiMaxHookTextCharacters;
    _aiWebFetchMaxResponseBytes = snapshot.aiWebFetchMaxResponseBytes;
    _aiWebFetchMaxRedirects = snapshot.aiWebFetchMaxRedirects;
    _aiWebFetchMaxCacheEntries = snapshot.aiWebFetchMaxCacheEntries;
    _aiAttachmentMaxInlineImageDimension =
        snapshot.aiAttachmentMaxInlineImageDimension;
    _aiAttachmentMaxTextRawBytes = snapshot.aiAttachmentMaxTextRawBytes;
    _aiAttachmentMaxPdfRawBytes = snapshot.aiAttachmentMaxPdfRawBytes;
    _aiAttachmentMaxImageRawBytes = snapshot.aiAttachmentMaxImageRawBytes;
    _aiChatMaxStreamLineBufferBytes = snapshot.aiChatMaxStreamLineBufferBytes;
    _aiFallbackTitleMaxCharacters = snapshot.aiFallbackTitleMaxCharacters;
    _aiGeneratedTitleMaxCharacters = snapshot.aiGeneratedTitleMaxCharacters;
    _aiMinimumMeaningfulTitleCharacters =
        snapshot.aiMinimumMeaningfulTitleCharacters;
    _aiMinimumMeaningfulLatinTitleWords =
        snapshot.aiMinimumMeaningfulLatinTitleWords;
    _aiMaxSkillContentLength = snapshot.aiMaxSkillContentLength;
    _aiMaxWorkspaceDocumentCharacters =
        snapshot.aiMaxWorkspaceDocumentCharacters;
    _aiSequentialToolRoundLimit = snapshot.aiSequentialToolRoundLimit;
    _aiImageSizeLimitBytes = snapshot.aiImageSizeLimitBytes;
    _aiWriteCommandConfirmationEnabled =
        snapshot.aiWriteCommandConfirmationEnabled;
    _aiAllowCommandRules = List<AiAllowCommandRule>.from(
      snapshot.aiAllowCommandRules,
    );
    _aiDenyCommandRules = List<AiDenyCommandRule>.from(
      snapshot.aiDenyCommandRules,
    );
    _aiConnectTimeoutSeconds = snapshot.aiConnectTimeoutSeconds;
    _aiResponseTimeoutSeconds = snapshot.aiResponseTimeoutSeconds;
    _aiStreamIdleTimeoutSeconds = snapshot.aiStreamIdleTimeoutSeconds;
    _aiAutoTitleEnabled = snapshot.aiAutoTitleEnabled;
    _aiDefaultSessionMode = snapshot.aiDefaultSessionMode;
    _aiDefaultFullAccessPermission = snapshot.aiDefaultFullAccessPermission;
    _aiModels = List<AiModelConfig>.from(snapshot.aiModels);
    _cachedAiModelsView = null;
    _selectedAiModelId = snapshot.selectedAiModelId;
    _recentModelSelections = _sanitizeRecentModelSelections(
      snapshot.recentModelSelections,
      _aiModels,
    );
    _cachedRecentModelSelectionsView = null;
    _shortcutBindings = _cloneShortcutBindings(snapshot.shortcutBindings);
    _dialogAnimationSettings = snapshot.dialogAnimationSettings;
    _menuAnimationSettings = snapshot.menuAnimationSettings;
    _pageAnimationSettings = snapshot.pageAnimationSettings;
    _panelAnimationSettings = snapshot.panelAnimationSettings;
    _chipAnimationSettings = snapshot.chipAnimationSettings;
    _listItemAnimationSettings = snapshot.listItemAnimationSettings;
    _builtinToolConfigs = List<AiBuiltinToolConfig>.from(
      snapshot.builtinToolConfigs,
    );
    _telemetryDebugEnabled = snapshot.telemetryDebugEnabled;
    _telemetryCaptureRawPayload = snapshot.telemetryCaptureRawPayload;
    _telemetryCaptureEnvironment = snapshot.telemetryCaptureEnvironment;
    _telemetryMaxPayloadChars = snapshot.telemetryMaxPayloadChars;
    _selfLearningEnabled = snapshot.selfLearningEnabled;
    _selfLearningConcurrency = snapshot.selfLearningConcurrency;
    _selfLearningStreamFlushIntervalMs =
        snapshot.selfLearningStreamFlushIntervalMs;
    _showSelfLearningMessages = snapshot.showSelfLearningMessages;
    _reduceMotion = snapshot.reduceMotion;
    _proxySettings = snapshot.proxySettings;
  }

  Future<bool> _commitMutation(_MutationDisposition Function() mutation) async {
    final completer = Completer<bool>();
    _mutationQueue = _mutationQueue
        .catchError((Object error, StackTrace stack) {
          silentLog(
            'settings_controller',
            'previous mutation queue',
            error,
            stack,
          );
        })
        .then((_) async {
          try {
            final previousSnapshot = _snapshot();
            final disposition = mutation();
            if (disposition == _MutationDisposition.successNoChange) {
              completer.complete(true);
              return;
            }
            if (disposition == _MutationDisposition.reject) {
              completer.complete(false);
              return;
            }
            notifyListeners();
            try {
              await _store.save(_snapshot());
              if (_persistenceIssue != null) {
                _persistenceIssue = null;
                notifyListeners();
              }
              // Successful persistence — fire the highlight-pulse signal
              // so subscribed surfaces (currently the settings panel) can
              // flash a soft confirmation without each `_save*` call site
              // needing its own per-row notifier.
              _saveSuccessSignal.value = _saveSuccessSignal.value + 1;
              completer.complete(true);
            } catch (error) {
              try {
                _applySnapshot(previousSnapshot);
              } catch (rollbackError, rollbackStack) {
                silentLog(
                  'settings_controller',
                  'rollback settings snapshot',
                  rollbackError,
                  rollbackStack,
                );
                // Rollback itself failed – snapshot is inconsistent but we must
                // still complete the completer to avoid hanging the queue.
              }
              _persistenceIssue = SettingsPersistenceIssue(
                kind: SettingsPersistenceIssueKind.saveFailed,
                filePath: _store.settingsFilePath,
                detail: '$error',
              );
              notifyListeners();
              completer.complete(false);
            }
          } catch (error, stack) {
            silentLog(
              'settings_controller',
              'commit settings mutation',
              error,
              stack,
            );
            // mutation() itself threw – complete with false to unblock callers.
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          }
        });
    return completer.future;
  }

  List<RecentModelSelection> _sanitizeRecentModelSelections(
    List<RecentModelSelection> candidates,
    List<AiModelConfig> models,
  ) {
    if (candidates.isEmpty || models.isEmpty) {
      return const <RecentModelSelection>[];
    }
    final allowed = <String, Set<String>>{
      for (final model in models) model.id: model.allModelIds.toSet(),
    };
    final dedupKeys = <String>{};
    final result = <RecentModelSelection>[];
    for (final item in candidates) {
      final configId = item.configId.trim();
      final modelId = item.modelId.trim();
      if (configId.isEmpty || modelId.isEmpty) {
        continue;
      }
      final allowedModels = allowed[configId];
      if (allowedModels == null || !allowedModels.contains(modelId)) {
        continue;
      }
      final key = '$configId::$modelId';
      if (!dedupKeys.add(key)) {
        continue;
      }
      result.add(RecentModelSelection(configId: configId, modelId: modelId));
      if (result.length >= _maxRecentModelSelections) {
        break;
      }
    }
    return result;
  }

  bool _sameRecentSelectionList(
    List<RecentModelSelection> left,
    List<RecentModelSelection> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }
}

Map<String, AiLspLanguageSettings> _cloneEditorLspSettingsMap(
  Map<String, AiLspLanguageSettings> settings,
) {
  return <String, AiLspLanguageSettings>{
    for (final entry in settings.entries) entry.key: entry.value,
  };
}

Map<OpenHandShortcutAction, List<int>> _cloneShortcutBindings(
  Map<OpenHandShortcutAction, List<int>> bindings,
) {
  return <OpenHandShortcutAction, List<int>>{
    for (final entry in bindings.entries)
      entry.key: List<int>.from(entry.value, growable: false),
  };
}

Map<EditorShortcutAction, List<int>> _cloneEditorShortcutBindings(
  Map<EditorShortcutAction, List<int>> bindings,
) {
  return <EditorShortcutAction, List<int>>{
    for (final entry in bindings.entries)
      entry.key: List<int>.from(entry.value, growable: false),
  };
}

bool _sameIntList(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

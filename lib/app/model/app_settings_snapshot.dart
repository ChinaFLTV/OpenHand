// 2026-05-01: app_settings_snapshot intentionally lists every field of
// each `DialogAnimationSettings` literal so the parallel block of
// `panelAnimationSettings` / `chipAnimationSettings` /
// `listItemAnimationSettings` reads as self-documenting defaults. A few
// of those values happen to coincide with the constructor defaults — that
// equivalence is documentation, not noise.
// ignore_for_file: avoid_redundant_argument_values

import 'package:flutter/material.dart';

import '../../features/ai/model/ai_allow_command_rule.dart';
import '../../features/ai/model/ai_builtin_tool_config.dart';
import '../../features/ai/model/ai_deny_command_rule.dart';
import '../../features/ai/model/ai_lsp_language_settings.dart';
import '../../features/ai/model/ai_message_content_format.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../../features/ai/model/ai_sandbox_settings.dart';
import '../../features/mcp/model/mcp_keyword_index_update_mode.dart';
import '../../features/mcp/model/mcp_lazy_loading_mode.dart';
import '../../features/mcp/model/mcp_stdio_mirror_mode.dart';
import '../model/app_language.dart';
import '../model/app_proxy_settings.dart';
import '../model/dialog_animation_settings.dart';
import '../model/editor_code_theme.dart';
import '../model/editor_indent.dart';
import '../model/editor_shortcut.dart';
import '../support/openhand_paths.dart';
import '../theme/openhand_theme_preset.dart';
import 'openhand_shortcut.dart';

class AppSettingsSnapshot {
  factory AppSettingsSnapshot.defaults() {
    return AppSettingsSnapshot(
      themeMode: ThemeMode.system,
      themePreset: OpenHandThemePreset.deepSeaBlue,
      language: AppLanguage.simplifiedChinese,
      skillsStoragePath: OpenHandPaths.defaultSkillsDirectoryPath(),
      mcpEnabled: true,
      mcpServersFilePath: OpenHandPaths.defaultMcpServersFilePath(),
      mcpLazyLoadingMode: defaultMcpLazyLoadingMode,
      mcpLazyLoadingThresholdTokens: defaultMcpLazyLoadingThresholdTokens,
      mcpStdioMirrorMode: defaultMcpStdioMirrorMode,
      mcpAutoProbeConcurrency: defaultMcpAutoProbeConcurrency,
      mcpKeywordIndexUpdateMode: defaultMcpKeywordIndexUpdateMode,
      mcpKeywordIndexIntervalValue: defaultMcpKeywordIndexIntervalValue,
      mcpKeywordIndexIntervalUnit: defaultMcpKeywordIndexIntervalUnit,
      mcpKeywordIndexScheduledTimeOfDay:
          defaultMcpKeywordIndexScheduledTimeOfDay,
      memoryEnabled: true,
      userMemoryFilePath: OpenHandPaths.defaultUserMemoryFilePath(),
      editorWordWrap: true,
      editorIndentSpaces: defaultEditorIndentSpaces,
      editorCodeTheme: EditorCodeTheme.materialYou,
      editorLspSettings: const <String, AiLspLanguageSettings>{},
      editorShortcutBindings: defaultEditorShortcutBindings(),
      aiMessageCompressionThresholdChars:
          defaultAiMessageCompressionThresholdChars,
      aiToolResultCompressionThresholdChars:
          defaultAiToolResultCompressionThresholdChars,
      aiToolResultCompressionEnabled: true,
      aiMicroCompressionEnabled: false,
      aiMessageContentFormat: defaultAiMessageContentFormat,
      aiHtmlRenderFallback: defaultAiHtmlRenderFallback,
      aiToolResultCompressionHeadTailWindowChars:
          defaultAiToolResultCompressionHeadTailWindowChars,
      aiToolResultCompressionMaxPathHits:
          defaultAiToolResultCompressionMaxPathHits,
      aiInputCacheEnabled: defaultAiInputCacheEnabled,
      aiInputCacheUpdateMode: defaultAiInputCacheUpdateMode,
      aiInputCacheUpdateInterval: defaultAiInputCacheUpdateInterval,
      aiInputCacheBreakpointCount: defaultAiInputCacheBreakpointCount,
      aiInputCacheBreakpointPositions: defaultAiInputCacheBreakpointPositions,
      aiBudgetUsdPerSession: defaultAiBudgetUsdPerSession,
      aiWriteToolSummaryMaxChars: defaultAiWriteToolSummaryMaxChars,
      aiSingleRoundToolCallLimit: defaultAiSingleRoundToolCallLimit,
      aiSequentialToolRoundLimit: defaultAiSequentialToolRoundLimit,
      aiMaxRecentErrors: defaultAiMaxRecentErrors,
      aiMaxPlanHistoryEntries: defaultAiMaxPlanHistoryEntries,
      aiMaxTruncationContinuations: defaultAiMaxTruncationContinuations,
      aiEstimatedCharactersPerToken: defaultAiEstimatedCharactersPerToken,
      aiMaxToolOutputChars: defaultAiMaxToolOutputChars,
      aiWriteConfirmationTimeoutMs: defaultAiWriteConfirmationTimeoutMs,
      aiFastPathWriteAnalysisThreshold: defaultAiFastPathWriteAnalysisThreshold,
      aiMaxHookTextCharacters: defaultAiMaxHookTextCharacters,
      aiWebFetchMaxResponseBytes: defaultAiWebFetchMaxResponseBytes,
      aiWebFetchMaxRedirects: defaultAiWebFetchMaxRedirects,
      aiWebFetchMaxCacheEntries: defaultAiWebFetchMaxCacheEntries,
      aiAttachmentMaxInlineImageDimension:
          defaultAiAttachmentMaxInlineImageDimension,
      aiAttachmentMaxTextRawBytes: defaultAiAttachmentMaxTextRawBytes,
      aiAttachmentMaxPdfRawBytes: defaultAiAttachmentMaxPdfRawBytes,
      aiAttachmentMaxImageRawBytes: defaultAiAttachmentMaxImageRawBytes,
      aiChatMaxStreamLineBufferBytes: defaultAiChatMaxStreamLineBufferBytes,
      aiFallbackTitleMaxCharacters: defaultAiFallbackTitleMaxCharacters,
      aiGeneratedTitleMaxCharacters: defaultAiGeneratedTitleMaxCharacters,
      aiAutoTitleMaxRetryCount: defaultAiAutoTitleMaxRetryCount,
      aiMinimumMeaningfulTitleCharacters:
          defaultAiMinimumMeaningfulTitleCharacters,
      aiMinimumMeaningfulLatinTitleWords:
          defaultAiMinimumMeaningfulLatinTitleWords,
      aiMaxSkillContentLength: defaultAiMaxSkillContentLength,
      aiMaxWorkspaceDocumentCharacters: defaultAiMaxWorkspaceDocumentCharacters,
      aiImageSizeLimitBytes: defaultAiImageSizeLimitBytes,
      aiWriteCommandConfirmationEnabled: true,
      aiAllowCommandRules: const <AiAllowCommandRule>[],
      aiDenyCommandRules: const <AiDenyCommandRule>[],
      aiSandboxSettings: AiSandboxSettings.defaults(),
      aiConnectTimeoutSeconds: defaultAiConnectTimeoutSeconds,
      aiResponseTimeoutSeconds: defaultAiResponseTimeoutSeconds,
      aiStreamIdleTimeoutSeconds: defaultAiStreamIdleTimeoutSeconds,
      aiStreamMaxCharsPerSecond: defaultAiStreamMaxCharsPerSecond,
      aiStreamMaxMessageCardsPerSecond: defaultAiStreamMaxMessageCardsPerSecond,
      aiStreamThrottleEnabled: defaultAiStreamThrottleEnabled,
      aiStreamThrottleAutoMode: defaultAiStreamThrottleAutoMode,
      aiStreamThrottleDurationSeconds: defaultAiStreamThrottleDurationSeconds,
      aiStreamThrottleCloudSyncProvider:
          defaultAiStreamThrottleCloudSyncProvider,
      aiStreamThrottleCloudSyncEndpoint:
          defaultAiStreamThrottleCloudSyncEndpoint,
      aiStreamThrottleCloudSyncToken: defaultAiStreamThrottleCloudSyncToken,
      aiStreamThrottleConfigUpdatedAtMs:
          defaultAiStreamThrottleConfigUpdatedAtMs,
      aiAutoTitleEnabled: true,
      aiDefaultSessionMode: defaultAiDefaultSessionMode,
      aiDefaultFullAccessPermission: false,
      aiModels: const <AiModelConfig>[],
      selectedAiModelId: null,
      recentModelSelections: const <RecentModelSelection>[],
      shortcutBindings: defaultOpenHandShortcutBindings(),
      dialogAnimationSettings: const DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.springScale,
        exitStyle: DialogAnimationStyle.springScale,
        durationMs: 360,
        curve: DialogAnimationCurve.easeOutCubic,
      ),
      menuAnimationSettings: const DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.springScale,
        exitStyle: DialogAnimationStyle.springScale,
        durationMs: 260,
        curve: DialogAnimationCurve.easeOutCubic,
      ),
      pageAnimationSettings: const DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.fade,
        exitStyle: DialogAnimationStyle.fade,
        durationMs: 800,
        curve: DialogAnimationCurve.easeInOutCubicEmphasized,
      ),
      panelAnimationSettings: const DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.fade,
        exitStyle: DialogAnimationStyle.fade,
        durationMs: 600,
        curve: DialogAnimationCurve.easeInOutCubicEmphasized,
      ),
      // 2026-05-01: chip = capsule entrance/exit (composer skill /
      // attachment / @-reference / queued-message chips). Q-bouncy
      // spring-scale + emphasized curve so X-close feels delightful.
      chipAnimationSettings: const DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.springScale,
        exitStyle: DialogAnimationStyle.fadeScale,
        durationMs: 320,
        curve: DialogAnimationCurve.easeInOutCubicEmphasized,
      ),
      // List-item entrance for sidebar threads, instructions / hooks /
      // crons / memory / mcp tiles. Defaults map to the existing
      // `AppearOnce` rhythm (320ms emphasized fade-and-slide).
      listItemAnimationSettings: const DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.slideUp,
        exitStyle: DialogAnimationStyle.fade,
        durationMs: 320,
        curve: DialogAnimationCurve.easeInOutCubicEmphasized,
      ),
      builtinToolConfigs: AiBuiltinToolConfig.defaults(),
      telemetryDebugEnabled: false,
      telemetryCaptureRawPayload: true,
      telemetryCaptureEnvironment: false,
      telemetryMaxPayloadChars: defaultTelemetryMaxPayloadChars,
      proxySettings: AppProxySettings.defaults(),
      subprocessGracefulShutdownMs: defaultSubprocessGracefulShutdownMs,
      bashOutputMaxBytes: defaultBashOutputMaxBytes,
      maxConcurrentTools: defaultMaxConcurrentTools,
    );
  }
  const AppSettingsSnapshot({
    required this.themeMode,
    required this.themePreset,
    required this.language,
    required this.skillsStoragePath,
    required this.mcpEnabled,
    required this.mcpServersFilePath,
    required this.mcpLazyLoadingMode,
    required this.mcpLazyLoadingThresholdTokens,
    required this.mcpStdioMirrorMode,
    required this.mcpAutoProbeConcurrency,
    required this.mcpKeywordIndexUpdateMode,
    required this.mcpKeywordIndexIntervalValue,
    required this.mcpKeywordIndexIntervalUnit,
    required this.mcpKeywordIndexScheduledTimeOfDay,
    required this.memoryEnabled,
    required this.userMemoryFilePath,
    required this.editorWordWrap,
    required this.editorIndentSpaces,
    required this.editorCodeTheme,
    required this.editorLspSettings,
    required this.editorShortcutBindings,
    required this.aiMessageCompressionThresholdChars,
    required this.aiToolResultCompressionThresholdChars,
    required this.aiToolResultCompressionEnabled,
    this.aiMicroCompressionEnabled = false,
    this.aiMessageContentFormat = defaultAiMessageContentFormat,
    this.aiHtmlRenderFallback = defaultAiHtmlRenderFallback,
    required this.aiToolResultCompressionHeadTailWindowChars,
    required this.aiToolResultCompressionMaxPathHits,
    required this.aiInputCacheEnabled,
    required this.aiInputCacheUpdateMode,
    required this.aiInputCacheUpdateInterval,
    required this.aiInputCacheBreakpointCount,
    required this.aiInputCacheBreakpointPositions,
    required this.aiBudgetUsdPerSession,
    required this.aiWriteToolSummaryMaxChars,
    required this.aiSingleRoundToolCallLimit,
    required this.aiSequentialToolRoundLimit,
    required this.aiMaxRecentErrors,
    required this.aiMaxPlanHistoryEntries,
    required this.aiMaxTruncationContinuations,
    required this.aiEstimatedCharactersPerToken,
    required this.aiMaxToolOutputChars,
    required this.aiWriteConfirmationTimeoutMs,
    required this.aiFastPathWriteAnalysisThreshold,
    required this.aiMaxHookTextCharacters,
    required this.aiWebFetchMaxResponseBytes,
    required this.aiWebFetchMaxRedirects,
    required this.aiWebFetchMaxCacheEntries,
    required this.aiAttachmentMaxInlineImageDimension,
    required this.aiAttachmentMaxTextRawBytes,
    required this.aiAttachmentMaxPdfRawBytes,
    required this.aiAttachmentMaxImageRawBytes,
    required this.aiChatMaxStreamLineBufferBytes,
    required this.aiFallbackTitleMaxCharacters,
    required this.aiGeneratedTitleMaxCharacters,
    required this.aiAutoTitleMaxRetryCount,
    required this.aiMinimumMeaningfulTitleCharacters,
    required this.aiMinimumMeaningfulLatinTitleWords,
    required this.aiMaxSkillContentLength,
    required this.aiMaxWorkspaceDocumentCharacters,
    required this.aiImageSizeLimitBytes,
    required this.aiWriteCommandConfirmationEnabled,
    required this.aiAllowCommandRules,
    required this.aiDenyCommandRules,
    required this.aiSandboxSettings,
    required this.aiConnectTimeoutSeconds,
    required this.aiResponseTimeoutSeconds,
    required this.aiStreamIdleTimeoutSeconds,
    required this.aiStreamMaxCharsPerSecond,
    required this.aiStreamMaxMessageCardsPerSecond,
    required this.aiStreamThrottleEnabled,
    required this.aiStreamThrottleAutoMode,
    required this.aiStreamThrottleDurationSeconds,
    required this.aiStreamThrottleCloudSyncProvider,
    required this.aiStreamThrottleCloudSyncEndpoint,
    required this.aiStreamThrottleCloudSyncToken,
    required this.aiStreamThrottleConfigUpdatedAtMs,
    required this.aiAutoTitleEnabled,
    required this.aiDefaultSessionMode,
    required this.aiDefaultFullAccessPermission,
    required this.aiModels,
    required this.selectedAiModelId,
    required this.recentModelSelections,
    required this.shortcutBindings,
    required this.dialogAnimationSettings,
    required this.menuAnimationSettings,
    required this.pageAnimationSettings,
    required this.panelAnimationSettings,
    required this.chipAnimationSettings,
    required this.listItemAnimationSettings,
    required this.builtinToolConfigs,
    required this.telemetryDebugEnabled,
    required this.telemetryCaptureRawPayload,
    required this.telemetryCaptureEnvironment,
    required this.telemetryMaxPayloadChars,
    this.selfLearningEnabled = true,
    this.selfLearningConcurrency = defaultSelfLearningConcurrency,
    this.selfLearningStreamFlushIntervalMs =
        defaultSelfLearningStreamFlushIntervalMs,
    this.showSelfLearningMessages = true,
    this.cronAutoCleanupEnabled = true,
    this.cronAutoCleanupRetentionDays = defaultCronAutoCleanupRetentionDays,
    this.hardnessToolSearchHistoryMaxPhases =
        defaultHardnessToolSearchHistoryMaxPhases,
    this.toolSearchReplayCancelWindowSeconds =
        defaultToolSearchReplayCancelWindowSeconds,
    this.reduceMotion = false,
    this.subprocessGracefulShutdownMs = defaultSubprocessGracefulShutdownMs,
    this.bashOutputMaxBytes = defaultBashOutputMaxBytes,
    this.maxConcurrentTools = defaultMaxConcurrentTools,
    AppProxySettings? proxySettings,
  }) : proxySettings =
           proxySettings ??
           const AppProxySettings(
             mode: AppProxyMode.automatic,
             protocols: <AppProxyProtocol>{
               AppProxyProtocol.http,
               AppProxyProtocol.https,
             },
             host: '',
             port: 7890,
             authEnabled: false,
             username: '',
             password: '',
             exceptions: <String>[],
           );

  /// Default and bounds for Hermes Talker self-learning concurrency (Task 21).
  static const int defaultSelfLearningConcurrency = 5;
  static const int minSelfLearningConcurrency = 1;
  static const int maxSelfLearningConcurrency = 10;

  /// 2026-04-29 — 自学习卡片流式输出后台刷新间隔。越大越平滑，
  /// 但用户看到的增量越延迟；越小越实时，但渲染负担与布局拖拽越大。
  /// 默认 600ms 是 "人眼可接受的延迟 + UI 顺畅" 的折衰点。
  static const int defaultSelfLearningStreamFlushIntervalMs = 600;
  static const int minSelfLearningStreamFlushIntervalMs = 100;
  static const int maxSelfLearningStreamFlushIntervalMs = 5000;

  /// 2026-04-25 — 冷启动后自动清理 cron 历史的默认保留天数。
  static const int defaultCronAutoCleanupRetentionDays = 7;
  static const int minCronAutoCleanupRetentionDays = 1;
  static const int maxCronAutoCleanupRetentionDays = 365;

  /// Hardness ToolSearch 历史按 phase-session 分桶存储，同时保留
  /// 的最近 phase 个数（LRU 淘汰）。默认 8，允许 1..64，避免
  /// 长会话内存膨胀。
  static const int defaultHardnessToolSearchHistoryMaxPhases = 8;
  static const int minHardnessToolSearchHistoryMaxPhases = 1;
  static const int maxHardnessToolSearchHistoryMaxPhases = 64;
  static const int defaultToolSearchReplayCancelWindowSeconds = 3;
  static const int minToolSearchReplayCancelWindowSeconds = 1;
  static const int maxToolSearchReplayCancelWindowSeconds = 30;

  static const int defaultAiMessageCompressionThresholdChars = 12000;
  static const int minAiMessageCompressionThresholdChars = 2000;
  static const int maxAiMessageCompressionThresholdChars = 1000000;

  static int normalizeAiMessageCompressionThresholdChars(int value) {
    if (value <= 0) {
      return defaultAiMessageCompressionThresholdChars;
    }
    return value
        .clamp(
          minAiMessageCompressionThresholdChars,
          maxAiMessageCompressionThresholdChars,
        )
        .toInt();
  }

  /// 2026-04-27 — 工具调用输出进入 conversation history 前的字符上限。
  /// 超过该上限的工具返回会被压缩为结构化摘要（受影响文件路径
  /// + 行号 + AI 自述 purpose + 首尾片段），避免长篇 raw 输出吞噁
  /// 上下文 token。默认 1024 字符。
  static const int defaultAiToolResultCompressionThresholdChars = 1024;
  static const int minAiToolResultCompressionThresholdChars = 256;
  static const int maxAiToolResultCompressionThresholdChars = 65536;

  static int normalizeAiToolResultCompressionThresholdChars(int value) {
    if (value <= 0) {
      return defaultAiToolResultCompressionThresholdChars;
    }
    return value
        .clamp(
          minAiToolResultCompressionThresholdChars,
          maxAiToolResultCompressionThresholdChars,
        )
        .toInt();
  }

  /// 2026-04-27 — 压缩摘要首尾片段窗口（字符）。越大保留越多 raw
  /// 上下文，但会占用更多 tokens。0 表示不保留首尾片段。
  static const int defaultAiToolResultCompressionHeadTailWindowChars = 256;
  static const int minAiToolResultCompressionHeadTailWindowChars = 0;
  static const int maxAiToolResultCompressionHeadTailWindowChars = 8192;

  /// 2026-04-27 — 压缩摘要中提取的文件路径条数上限。0 表示不提取。
  static const int defaultAiToolResultCompressionMaxPathHits = 12;
  static const int minAiToolResultCompressionMaxPathHits = 0;
  static const int maxAiToolResultCompressionMaxPathHits = 200;

  /// 2026-05-02 — 成本控制：是否启用输入缓存优化。开启后，会话创建时
  /// 会冻结 prompt 的静态前缀（系统指令/工具/技能/MCP/记忆/指令），并
  /// 在 Anthropic 协议上自动注入 cache_control 断点；同时在用户首条消息
  /// 发出后锁定服务商/模型选择，确保缓存命中。
  static const bool defaultAiInputCacheEnabled = false;

  /// 2026-05-02 — 缓存断点更新模式：allMessages | userMessages | tokens。
  static const String aiInputCacheUpdateModeAllMessages = 'allMessages';
  static const String aiInputCacheUpdateModeUserMessages = 'userMessages';
  static const String aiInputCacheUpdateModeTokens = 'tokens';
  static const String defaultAiInputCacheUpdateMode =
      aiInputCacheUpdateModeAllMessages;
  static const Set<String> validAiInputCacheUpdateModes = <String>{
    aiInputCacheUpdateModeAllMessages,
    aiInputCacheUpdateModeUserMessages,
    aiInputCacheUpdateModeTokens,
  };

  /// 2026-05-02 — 缓存断点更新间隔。单位由 [aiInputCacheUpdateMode] 决定：
  /// allMessages → 每 N 条用户+助手消息；userMessages → 每 N 条用户消息；
  /// tokens → 每累计 N tokens 移动一次断点。
  static const int defaultAiInputCacheUpdateInterval = 10;
  static const int minAiInputCacheUpdateInterval = 1;
  static const int maxAiInputCacheUpdateInterval = 200000;

  /// 2026-05-02 — Anthropic cache_control 断点数量上限（协议侧硬上限 4）。
  /// 第 N 个断点固定用于动态消息侧，前 N-1 个用于静态前缀切片。
  static const int defaultAiInputCacheBreakpointCount = 4;
  static const int minAiInputCacheBreakpointCount = 1;
  static const int maxAiInputCacheBreakpointCount = 4;

  /// 2026-05-04 — 用户自定义的前 N-1 个静态缓存点位置，单位是消息流的
  /// 百分比 [0, 1]。空列表表示沿用 mode-based 自动布点；非空时长度应 ==
  /// `aiInputCacheBreakpointCount - 1`，最后一个断点固定落在末尾消息。
  static const List<double> defaultAiInputCacheBreakpointPositions = <double>[];

  /// 2026-05-06 — 单会话 USD 预算上限。0 表示关闭预算告警；超过该阈值时
  /// TopBar 与会话元数据对话框将以警示样式提示用户当前会话累计成本已破
  /// 预算。仅作为软提醒，不会中断对话或限制发送。
  static const double defaultAiBudgetUsdPerSession = 0;
  static const double minAiBudgetUsdPerSession = 0;
  static const double maxAiBudgetUsdPerSession = 100000;

  /// 2026-04-27 — 写类工具结果摘要中保留原始 summary 文本的字符上限。
  /// 超过该上限的 result_text 会被刪除（不进入 prompt history）。
  static const int defaultAiWriteToolSummaryMaxChars = 280;
  static const int minAiWriteToolSummaryMaxChars = 0;
  static const int maxAiWriteToolSummaryMaxChars = 8192;

  /// Default cap for per-message raw payload capture (characters).
  static const int defaultTelemetryMaxPayloadChars = 200000;
  static const int minTelemetryMaxPayloadChars = 4000;
  static const int maxTelemetryMaxPayloadChars = 2000000;
  static const int defaultAiSingleRoundToolCallLimit = 40;
  static const int defaultAiSequentialToolRoundLimit = 24;

  /// 2026-04-29 — Group A: AI 会话控制参数。
  static const int defaultAiMaxRecentErrors = 20;
  static const int minAiMaxRecentErrors = 0;
  static const int maxAiMaxRecentErrors = 1000;

  static const int defaultAiMaxPlanHistoryEntries = 20;
  static const int minAiMaxPlanHistoryEntries = 0;
  static const int maxAiMaxPlanHistoryEntries = 1000;

  static const int defaultAiMaxTruncationContinuations = 5;
  static const int minAiMaxTruncationContinuations = 0;
  static const int maxAiMaxTruncationContinuations = 100;

  static const int defaultAiEstimatedCharactersPerToken = 4;
  static const int minAiEstimatedCharactersPerToken = 1;
  static const int maxAiEstimatedCharactersPerToken = 32;

  /// 2026-04-29 — Group B: 工具调用与确认参数。
  static const int defaultAiMaxToolOutputChars = 200000;
  static const int minAiMaxToolOutputChars = 1000;
  static const int maxAiMaxToolOutputChars = 10000000;

  static const int defaultAiWriteConfirmationTimeoutMs = 300000;
  static const int minAiWriteConfirmationTimeoutMs = 1000;
  static const int maxAiWriteConfirmationTimeoutMs = 3600000;

  static const int defaultAiFastPathWriteAnalysisThreshold = 512;
  static const int minAiFastPathWriteAnalysisThreshold = 0;
  static const int maxAiFastPathWriteAnalysisThreshold = 100000;

  static const int defaultAiMaxHookTextCharacters = 4000;
  static const int minAiMaxHookTextCharacters = 100;
  static const int maxAiMaxHookTextCharacters = 1000000;

  /// 2026-04-29 — Group C: 网络与附件类参数。
  static const int defaultAiWebFetchMaxResponseBytes = 1024 * 1024;
  static const int minAiWebFetchMaxResponseBytes = 16 * 1024;
  static const int maxAiWebFetchMaxResponseBytes = 256 * 1024 * 1024;

  static const int defaultAiWebFetchMaxRedirects = 5;
  static const int minAiWebFetchMaxRedirects = 0;
  static const int maxAiWebFetchMaxRedirects = 50;

  static const int defaultAiWebFetchMaxCacheEntries = 64;
  static const int minAiWebFetchMaxCacheEntries = 0;
  static const int maxAiWebFetchMaxCacheEntries = 4096;

  static const int defaultAiAttachmentMaxInlineImageDimension = 1568;
  static const int minAiAttachmentMaxInlineImageDimension = 64;
  static const int maxAiAttachmentMaxInlineImageDimension = 16384;

  static const int defaultAiAttachmentMaxTextRawBytes = 2 * 1024 * 1024;
  static const int minAiAttachmentMaxTextRawBytes = 1024;
  static const int maxAiAttachmentMaxTextRawBytes = 256 * 1024 * 1024;

  static const int defaultAiAttachmentMaxPdfRawBytes = 2 * 1024 * 1024;
  static const int minAiAttachmentMaxPdfRawBytes = 1024;
  static const int maxAiAttachmentMaxPdfRawBytes = 256 * 1024 * 1024;

  static const int defaultAiAttachmentMaxImageRawBytes = 50 * 1024 * 1024;
  static const int minAiAttachmentMaxImageRawBytes = 64 * 1024;
  static const int maxAiAttachmentMaxImageRawBytes = 1024 * 1024 * 1024;

  static const int defaultAiChatMaxStreamLineBufferBytes = 4 * 1024 * 1024;
  static const int minAiChatMaxStreamLineBufferBytes = 4 * 1024;
  static const int maxAiChatMaxStreamLineBufferBytes = 1024 * 1024 * 1024;
  static const int defaultAiFallbackTitleMaxCharacters = 80;
  static const int minAiFallbackTitleMaxCharacters = 4;
  static const int maxAiFallbackTitleMaxCharacters = 200;
  static const int defaultAiGeneratedTitleMaxCharacters = 80;
  static const int minAiGeneratedTitleMaxCharacters = 4;
  static const int maxAiGeneratedTitleMaxCharacters = 200;

  /// 线程会话标题获取最大重试次数。当首次自动标题生成失败后，后续
  /// 每次打开该会话时会尝试重新获取标题，直到达到此上限。
  static const int defaultAiAutoTitleMaxRetryCount = 5;
  static const int minAiAutoTitleMaxRetryCount = 0;
  static const int maxAiAutoTitleMaxRetryCount = 20;
  static const int defaultAiMinimumMeaningfulTitleCharacters = 4;
  static const int minAiMinimumMeaningfulTitleCharacters = 1;
  static const int maxAiMinimumMeaningfulTitleCharacters = 50;
  static const int defaultAiMinimumMeaningfulLatinTitleWords = 2;
  static const int minAiMinimumMeaningfulLatinTitleWords = 1;
  static const int maxAiMinimumMeaningfulLatinTitleWords = 20;
  static const int defaultAiMaxSkillContentLength = 100000;
  static const int minAiMaxSkillContentLength = 1000;
  static const int maxAiMaxSkillContentLength = 10000000;
  static const int defaultAiMaxWorkspaceDocumentCharacters = 16000;
  static const int minAiMaxWorkspaceDocumentCharacters = 1000;
  static const int maxAiMaxWorkspaceDocumentCharacters = 1000000;

  /// Default per-image attachment size cap (1 MiB).
  ///
  /// When a user attaches an image larger than this threshold, the attachment
  /// pipeline downscales it before the editor opens so that storage, prompt
  /// payload and clipboard handoff remain bounded.
  static const int defaultAiImageSizeLimitBytes = 1024 * 1024;

  /// Hard floor to prevent users from saving an unusable threshold.
  static const int minAiImageSizeLimitBytes = 64 * 1024;

  /// Hard ceiling so a misconfigured value cannot blow up memory at runtime.
  static const int maxAiImageSizeLimitBytes = 64 * 1024 * 1024;

  /// Timeout (seconds) for establishing the HTTP connection and receiving
  /// initial response headers from the AI provider.
  static const int defaultAiConnectTimeoutSeconds = 60;
  static const int minAiConnectTimeoutSeconds = 5;
  static const int maxAiConnectTimeoutSeconds = 300;

  /// Timeout (seconds) for receiving a complete non-streaming AI response.
  static const int defaultAiResponseTimeoutSeconds = 120;
  static const int minAiResponseTimeoutSeconds = 10;
  static const int maxAiResponseTimeoutSeconds = 600;

  /// Per-chunk idle timeout (seconds) for streaming AI responses.
  /// When the stream receives no new data within this window, the request
  /// is aborted and an error is shown (the "Request timed out." case).
  static const int defaultAiStreamIdleTimeoutSeconds = 120;
  static const int minAiStreamIdleTimeoutSeconds = 10;
  static const int maxAiStreamIdleTimeoutSeconds = 600;

  /// 2026-05-17 — 流式输出渲染节流：每秒最多向当前流式消息卡片追加渲染的
  /// 字符数（按 Unicode code point 计）。当 AI 侧短时间内回吐大量字符时，
  /// 通过该背压阀控制 UI 端追加速率，避免主线程被 markdown/widget 重建洪
  /// 水冲垮，从而保持 60fps 流畅滚动与稳定 UI。设置为 0 表示关闭节流。
  static const int defaultAiStreamMaxCharsPerSecond = 10;
  static const int minAiStreamMaxCharsPerSecond = 0;
  static const int maxAiStreamMaxCharsPerSecond = 100000;

  /// 2026-05-17 — 每秒最多向当前会话追加渲染的新消息卡片数。当 AI 侧
  /// 同一轮内连发多个工具调用 / 助手分段时，先放出 1 个再节流后续，
  /// 避免消息列表瞬间堆叠出现"上下弹跳/抽搐"。0 表示关闭节流。
  static const int defaultAiStreamMaxMessageCardsPerSecond = 1;
  static const int minAiStreamMaxMessageCardsPerSecond = 0;
  static const int maxAiStreamMaxMessageCardsPerSecond = 60;

  /// 2026-05-17 — 全局节流总开关（默认 true）。关闭后字符 / 卡片限速
  /// 全部失效，所有会话以真实速率全速渲染。
  static const bool defaultAiStreamThrottleEnabled = true;

  /// 2026-05-17 — 自动模式总开关（默认 false）。开启后自动按平台 /
  /// 设备性能选择速率，忽略手动配置。
  static const bool defaultAiStreamThrottleAutoMode = false;
  static const int autoStreamMaxCharsPerSecondDesktop = 12;
  static const int autoStreamMaxCharsPerSecondMobile = 6;
  static const int autoStreamMaxMessageCardsPerSecondAuto = 2;

  /// 2026-05-17 — 节流时长（秒）。在该时长内按节流速率均匀放出字符 /
  /// 卡片；时长耗尽后剩余流式响应直接按 AI 端真实接收节奏追加渲染，
  /// 兼顾"前段优雅打字机"与"后段不再卡读者节奏"。0 = 持续节流（不限时）。
  static const int defaultAiStreamThrottleDurationSeconds = 0;
  static const int minAiStreamThrottleDurationSeconds = 0;
  static const int maxAiStreamThrottleDurationSeconds = 600;

  /// 2026-05-18 — 节流配置云端同步默认值；当前 provider/endpoint/token
  /// 均空表示功能关闭。
  static const String defaultAiStreamThrottleCloudSyncProvider = 'custom';
  static const String defaultAiStreamThrottleCloudSyncEndpoint = '';
  static const String defaultAiStreamThrottleCloudSyncToken = '';

  /// 2026-05-19 — 节流配置最近一次本地修改的 epoch millis；自动同步比对
  /// 远端 updated_at 决定 push / apply 顺序，避免老覆新。
  static const int defaultAiStreamThrottleConfigUpdatedAtMs = 0;

  /// 子进程 graceful shutdown 等待窗口（毫秒）。在 SIGTERM 之后等待
  /// 该时长，若进程仍未退出则升级到 SIGKILL。值越大越仁慈，但 UI
  /// 取消反馈延迟也越大。
  static const int defaultSubprocessGracefulShutdownMs = 500;
  static const int minSubprocessGracefulShutdownMs = 100;
  static const int maxSubprocessGracefulShutdownMs = 5000;

  /// 单次 bash 工具调用 stdout/stderr 合并捕获上限（字节，UTF-16 chars 近似）。
  /// 超过会从中段截断并保留头尾，避免巨型日志撑爆消息序列化。
  static const int defaultBashOutputMaxBytes = 200000;
  static const int minBashOutputMaxBytes = 16000;
  static const int maxBashOutputMaxBytes = 4000000;

  /// 同会话内并发派发的工具调用上限。超过会进入排队，避免一次 plan
  /// 100 个写命令瞬间打爆系统资源（也降低被 OS 限速触发的概率）。
  static const int defaultMaxConcurrentTools = 8;
  static const int minMaxConcurrentTools = 1;
  static const int maxMaxConcurrentTools = 64;

  /// Default session mode string: 'chat' or 'plan'.
  static const String defaultAiDefaultSessionMode = 'chat';

  /// 2026-05-03 — MCP 工具懒加载默认配置。
  ///   - 默认 [McpLazyLoadingMode.auto]：仅在 MCP 工具体量超过阈值时启用。
  ///   - 默认阈值 80 000 tokens（≈ Claude 200K 上下文窗口的 40%）。
  static const McpLazyLoadingMode defaultMcpLazyLoadingMode =
      McpLazyLoadingMode.auto;
  static const int defaultMcpLazyLoadingThresholdTokens = 80000;
  static const int minMcpLazyLoadingThresholdTokens = 1000;
  static const int maxMcpLazyLoadingThresholdTokens = 1000000;
  static const McpStdioMirrorMode defaultMcpStdioMirrorMode =
      McpStdioMirrorMode.auto;
  static const int defaultMcpAutoProbeConcurrency = 5;
  static const int minMcpAutoProbeConcurrency = 1;
  static const int maxMcpAutoProbeConcurrency = 32;

  /// 2026-05-04 — MCP 关键词倒排索引的更新模式 / 周期 / 计划时间默认值。
  static const McpKeywordIndexUpdateMode defaultMcpKeywordIndexUpdateMode =
      McpKeywordIndexUpdateMode.coldStart;
  static const int defaultMcpKeywordIndexIntervalValue = 6;
  static const int minMcpKeywordIndexIntervalValue = 1;
  static const int maxMcpKeywordIndexIntervalValue = 30;
  static const McpKeywordIndexIntervalUnit defaultMcpKeywordIndexIntervalUnit =
      McpKeywordIndexIntervalUnit.hour;
  static const String defaultMcpKeywordIndexScheduledTimeOfDay = '02:00';

  final ThemeMode themeMode;
  final OpenHandThemePreset themePreset;
  final AppLanguage language;
  final String skillsStoragePath;
  final bool mcpEnabled;
  final String mcpServersFilePath;

  /// 2026-05-03 — MCP 工具懒加载模式（关闭/自动/开启）。
  /// 启用后会在系统提示词中剥离 MCP 工具 schema，改用 ToolSearch 内建工具按需检索。
  final McpLazyLoadingMode mcpLazyLoadingMode;

  /// 2026-05-03 — MCP 工具懒加载阈值（token 数）。仅在 [mcpLazyLoadingMode]
  /// = auto 时生效：当所有 MCP 工具描述合计 token 数（按字符 / 估算系数）超过
  /// 此阈值时，自动启用懒加载。
  final int mcpLazyLoadingThresholdTokens;

  /// 2026-05-04 — stdio MCP 包管理器镜像源模式。
  /// 决策顺序：`OPENHAND_MCP_MIRROR` 环变 > 该设置 > Platform.localeName。
  final McpStdioMirrorMode mcpStdioMirrorMode;

  /// MCP 服务自动健康检查 / Tools 拉取的并发 worker 数。
  /// 默认 5，避免慢服务把整批检查串行拖住；范围限制防止资源被打满。
  final int mcpAutoProbeConcurrency;

  /// 2026-05-04 — MCP 关键词倒排索引的更新模式。仅在 [interval]/[scheduled]
  /// 模式下，内建 cron 任务 `mcp_keyword_index.rebuild` 才会被启用。
  final McpKeywordIndexUpdateMode mcpKeywordIndexUpdateMode;

  /// [McpKeywordIndexUpdateMode.interval] 模式下的间隔数值（与单位结合）。
  final int mcpKeywordIndexIntervalValue;

  /// [McpKeywordIndexUpdateMode.interval] 模式下的时间单位（分/时/日）。
  final McpKeywordIndexIntervalUnit mcpKeywordIndexIntervalUnit;

  /// [McpKeywordIndexUpdateMode.scheduled] 模式下的固定触发时间（HH:mm）。
  final String mcpKeywordIndexScheduledTimeOfDay;
  final bool memoryEnabled;
  final String userMemoryFilePath;
  final bool editorWordWrap;
  final int editorIndentSpaces;
  final EditorCodeTheme editorCodeTheme;
  final Map<String, AiLspLanguageSettings> editorLspSettings;
  final Map<EditorShortcutAction, List<int>> editorShortcutBindings;
  final int aiMessageCompressionThresholdChars;
  final int aiToolResultCompressionThresholdChars;

  /// 2026-04-27 — 总开关：关闭后工具调用输出不再进行压缩。
  final bool aiToolResultCompressionEnabled;

  /// 2026-05-23 — 正常对话中是否启用工具结果微压缩（清除旧工具结果）。
  /// 关闭后仅在主动/被动压缩时才执行微压缩，可提高跨轮前缀缓存命中率。
  final bool aiMicroCompressionEnabled;

  /// 2026-05-24 — 助手消息内容渲染格式（Markdown / 纯文本 / HTML）。
  /// 非 Markdown 模式会在 Prompt 末尾注入对应 `output_format` 片段。
  final AiMessageContentFormat aiMessageContentFormat;

  /// 2026-05-24 — HTML 渲染失败时的回退策略，仅在
  /// [aiMessageContentFormat] 为 HTML 时生效。
  final AiHtmlRenderFallback aiHtmlRenderFallback;

  /// 2026-04-27 — 压缩摘要首尾片段窗口长度（字符）。
  final int aiToolResultCompressionHeadTailWindowChars;

  /// 2026-04-27 — 压缩摘要中提取的文件路径条数上限。
  final int aiToolResultCompressionMaxPathHits;

  /// 2026-05-02 — 成本控制：是否启用输入缓存优化（冻结静态前缀 + 模型锁
  /// + Anthropic cache_control 断点注入）。
  final bool aiInputCacheEnabled;

  /// 2026-05-02 — 缓存断点更新模式（allMessages / userMessages / tokens）。
  final String aiInputCacheUpdateMode;

  /// 2026-05-02 — 缓存断点更新间隔（含义由模式决定）。
  final int aiInputCacheUpdateInterval;

  /// 2026-05-02 — cache_control 断点数量（1-4）。
  final int aiInputCacheBreakpointCount;

  /// 2026-05-04 — 用户自定义的前 N-1 个断点位置（百分比 0..1，升序）。
  /// 空列表表示沿用 mode-based 自动布点。
  final List<double> aiInputCacheBreakpointPositions;

  /// 2026-05-06 — 单会话 USD 预算上限（0 = 关闭）。
  final double aiBudgetUsdPerSession;

  /// 2026-04-27 — 写类工具摘要中 result_text 的字符上限。
  final int aiWriteToolSummaryMaxChars;
  final int aiSingleRoundToolCallLimit;
  final int aiSequentialToolRoundLimit;

  /// Group A: 会话错误记录保留上限。
  final int aiMaxRecentErrors;

  /// Group A: plan_history 保留上限。
  final int aiMaxPlanHistoryEntries;

  /// Group A: 超长响应被截断后的自动续接轮次上限。
  final int aiMaxTruncationContinuations;

  /// Group A: token 估算系数（每个 token 平均多少字符）。
  final int aiEstimatedCharactersPerToken;
  final int aiMaxToolOutputChars;
  final int aiWriteConfirmationTimeoutMs;
  final int aiFastPathWriteAnalysisThreshold;
  final int aiMaxHookTextCharacters;
  final int aiWebFetchMaxResponseBytes;
  final int aiWebFetchMaxRedirects;
  final int aiWebFetchMaxCacheEntries;
  final int aiAttachmentMaxInlineImageDimension;
  final int aiAttachmentMaxTextRawBytes;
  final int aiAttachmentMaxPdfRawBytes;
  final int aiAttachmentMaxImageRawBytes;
  final int aiChatMaxStreamLineBufferBytes;

  /// Group D — 回退标题最大字符数。
  final int aiFallbackTitleMaxCharacters;

  /// Group D — 自动生成标题最大字符数。
  final int aiGeneratedTitleMaxCharacters;

  /// Group D — 线程会话标题获取最大重试次数。
  final int aiAutoTitleMaxRetryCount;

  /// Group D — 有效中文标题最小字符数。
  final int aiMinimumMeaningfulTitleCharacters;

  /// Group D — 有效拉丁标题最小词数。
  final int aiMinimumMeaningfulLatinTitleWords;

  /// Group E — Skill 内容字符上限。
  final int aiMaxSkillContentLength;

  /// Group E — 工作区指令文档字符上限。
  final int aiMaxWorkspaceDocumentCharacters;
  final int aiImageSizeLimitBytes;
  final bool aiWriteCommandConfirmationEnabled;
  final List<AiAllowCommandRule> aiAllowCommandRules;
  final List<AiDenyCommandRule> aiDenyCommandRules;
  final AiSandboxSettings aiSandboxSettings;
  final int aiConnectTimeoutSeconds;
  final int aiResponseTimeoutSeconds;
  final int aiStreamIdleTimeoutSeconds;

  /// 2026-05-17 — 流式输出节流：每秒最多向当前流式卡片追加的字符数。
  /// 0 表示关闭节流。
  final int aiStreamMaxCharsPerSecond;

  /// 2026-05-17 — 每秒最多向当前会话追加渲染的新消息卡片数。
  /// 0 表示关闭节流。
  final int aiStreamMaxMessageCardsPerSecond;

  /// 2026-05-17 — 全局节流总开关。关闭后字符 / 卡片限速全部失效。
  final bool aiStreamThrottleEnabled;

  /// 2026-05-17 — 自动模式总开关。开启后忽略手动配置，按平台 / 性能
  /// 选择速率。
  final bool aiStreamThrottleAutoMode;

  /// 2026-05-17 — 节流持续时长（秒）。在该时长内按节流速率渲染；时长
  /// 耗尽后剩余流式响应直接按真实接收节奏追加，避免长文末尾被节流"卡住"
  /// 用户阅读节奏。0 = 持续节流（不限时）。
  final int aiStreamThrottleDurationSeconds;

  /// 2026-05-18 — 节流配置云端同步 provider 标识 (custom / icloud /
  /// oauth)；当前仅 custom 走真实网络 IO，其余作为占位入口。
  final String aiStreamThrottleCloudSyncProvider;

  /// 2026-05-18 — 节流配置云端同步 endpoint（custom provider 走 HTTP
  /// PUT/GET）。
  final String aiStreamThrottleCloudSyncEndpoint;

  /// 2026-05-18 — 节流配置云端同步 Bearer token；为空表示不发送
  /// Authorization header。
  final String aiStreamThrottleCloudSyncToken;

  /// 2026-05-19 — 节流配置最近一次本地修改的 epoch millis（UTC）；
  /// 自动同步比对远端 updated_at 决定 push / apply 顺序。0 表示尚未
  /// 修改过。
  final int aiStreamThrottleConfigUpdatedAtMs;

  final bool aiAutoTitleEnabled;
  final String aiDefaultSessionMode;
  final bool aiDefaultFullAccessPermission;
  final List<AiModelConfig> aiModels;
  final String? selectedAiModelId;
  final List<RecentModelSelection> recentModelSelections;
  final Map<OpenHandShortcutAction, List<int>> shortcutBindings;
  final DialogAnimationSettings dialogAnimationSettings;
  final DialogAnimationSettings menuAnimationSettings;
  final DialogAnimationSettings pageAnimationSettings;
  final DialogAnimationSettings panelAnimationSettings;
  final DialogAnimationSettings chipAnimationSettings;
  final DialogAnimationSettings listItemAnimationSettings;
  final List<AiBuiltinToolConfig> builtinToolConfigs;
  final bool telemetryDebugEnabled;
  final bool telemetryCaptureRawPayload;

  /// Controls whether a session/message-level environment snapshot
  /// (working directory, OS env variables, platform info) is persisted
  /// into message metadata for audit. Off by default because
  /// `Platform.environment` can contain secrets (tokens, API keys).
  final bool telemetryCaptureEnvironment;
  final int telemetryMaxPayloadChars;

  /// Whether the Hermes Talker self-learning scheduler is active.
  /// When false, [SelfLearningScheduler.tick] short-circuits to a no-op.
  final bool selfLearningEnabled;

  /// Upper bound on concurrent self-learning sub-agent dispatches.
  /// Clamped to [minSelfLearningConcurrency] .. [maxSelfLearningConcurrency].
  final int selfLearningConcurrency;

  /// 自学习卡片流式输出后台刷新（持久化）间隔，毫秒。
  /// Clamped to [minSelfLearningStreamFlushIntervalMs] ..
  /// [maxSelfLearningStreamFlushIntervalMs].
  final int selfLearningStreamFlushIntervalMs;

  /// Whether self-learning (Hermes Talker) cards are rendered in the chat
  /// transcript. Independent of [selfLearningEnabled]: the scheduler may
  /// still produce cards in the background; this flag only controls UI
  /// visibility. Default true.
  final bool showSelfLearningMessages;

  /// 2026-04-25 — 冷启动后是否异步清理过期 cron 执行历史。
  /// 默认 true，免得历史表不受控增长。
  final bool cronAutoCleanupEnabled;

  /// 2026-04-25 — 保留上限天数；超过该天数的条目在冷启动起动
  /// 的 worker 里被删除。[minCronAutoCleanupRetentionDays] 与
  /// [maxCronAutoCleanupRetentionDays] 是输入安全护栏。
  final int cronAutoCleanupRetentionDays;

  /// Hardness ToolSearch 加载历史 LRU 桶上限，但到该上限后会从
  /// 「全会话」维度淘汰最早的 phase 桶。默认 8。
  final int hardnessToolSearchHistoryMaxPhases;

  /// ToolSearch 历史「重放」按钮按下后的反悔窗口（秒）。该窗口期内
  /// 用户可在 snackbar 上点 Cancel 撤销发送，超时则提交。范围 1..30。
  final int toolSearchReplayCancelWindowSeconds;

  /// 2026-05 — 用户层减少动画总开关。true 时所有自定义动画
  /// 时长压到 0；built-in 动画（路由/弹窗/HeroAnimation）通过
  /// MediaQuery.disableAnimations 同步禁用。`AppearOnce`、
  /// `AnimatedExpandable` 等自研组件经由 InheritedWidget 读取。
  /// 默认 false（OS-level reduceMotion 仍会被 MediaQuery 自动
  /// 抓取，所以即便此处为 false，开了系统辅助功能用户也能拿到
  /// 减弱动画体验）。
  final bool reduceMotion;

  /// 系统级代理配置。`SystemProxyResolver` 会从此处读取生效模式与
  /// 主机/端口/鉴权/例外名单。
  final AppProxySettings proxySettings;

  /// 子进程 SIGTERM → SIGKILL 之间的宽限期（毫秒）。
  final int subprocessGracefulShutdownMs;

  /// 单次 bash 工具调用合并捕获 stdout+stderr 上限（字符）。
  final int bashOutputMaxBytes;

  /// 同会话内并发派发工具调用的上限。
  final int maxConcurrentTools;

  AppSettingsSnapshot copyWith({
    ThemeMode? themeMode,
    OpenHandThemePreset? themePreset,
    AppLanguage? language,
    String? skillsStoragePath,
    bool? mcpEnabled,
    String? mcpServersFilePath,
    McpLazyLoadingMode? mcpLazyLoadingMode,
    int? mcpLazyLoadingThresholdTokens,
    McpStdioMirrorMode? mcpStdioMirrorMode,
    int? mcpAutoProbeConcurrency,
    McpKeywordIndexUpdateMode? mcpKeywordIndexUpdateMode,
    int? mcpKeywordIndexIntervalValue,
    McpKeywordIndexIntervalUnit? mcpKeywordIndexIntervalUnit,
    String? mcpKeywordIndexScheduledTimeOfDay,
    bool? memoryEnabled,
    String? userMemoryFilePath,
    bool? editorWordWrap,
    int? editorIndentSpaces,
    EditorCodeTheme? editorCodeTheme,
    Map<String, AiLspLanguageSettings>? editorLspSettings,
    Map<EditorShortcutAction, List<int>>? editorShortcutBindings,
    int? aiMessageCompressionThresholdChars,
    int? aiToolResultCompressionThresholdChars,
    bool? aiToolResultCompressionEnabled,
    bool? aiMicroCompressionEnabled,
    AiMessageContentFormat? aiMessageContentFormat,
    AiHtmlRenderFallback? aiHtmlRenderFallback,
    int? aiToolResultCompressionHeadTailWindowChars,
    int? aiToolResultCompressionMaxPathHits,
    bool? aiInputCacheEnabled,
    String? aiInputCacheUpdateMode,
    int? aiInputCacheUpdateInterval,
    int? aiInputCacheBreakpointCount,
    List<double>? aiInputCacheBreakpointPositions,
    double? aiBudgetUsdPerSession,
    int? aiWriteToolSummaryMaxChars,
    int? aiSingleRoundToolCallLimit,
    int? aiSequentialToolRoundLimit,
    int? aiMaxRecentErrors,
    int? aiMaxPlanHistoryEntries,
    int? aiMaxTruncationContinuations,
    int? aiEstimatedCharactersPerToken,
    int? aiMaxToolOutputChars,
    int? aiWriteConfirmationTimeoutMs,
    int? aiFastPathWriteAnalysisThreshold,
    int? aiMaxHookTextCharacters,
    int? aiWebFetchMaxResponseBytes,
    int? aiWebFetchMaxRedirects,
    int? aiWebFetchMaxCacheEntries,
    int? aiAttachmentMaxInlineImageDimension,
    int? aiAttachmentMaxTextRawBytes,
    int? aiAttachmentMaxPdfRawBytes,
    int? aiAttachmentMaxImageRawBytes,
    int? aiChatMaxStreamLineBufferBytes,
    int? aiFallbackTitleMaxCharacters,
    int? aiGeneratedTitleMaxCharacters,
    int? aiAutoTitleMaxRetryCount,
    int? aiMinimumMeaningfulTitleCharacters,
    int? aiMinimumMeaningfulLatinTitleWords,
    int? aiMaxSkillContentLength,
    int? aiMaxWorkspaceDocumentCharacters,
    int? aiImageSizeLimitBytes,
    bool? aiWriteCommandConfirmationEnabled,
    List<AiAllowCommandRule>? aiAllowCommandRules,
    List<AiDenyCommandRule>? aiDenyCommandRules,
    AiSandboxSettings? aiSandboxSettings,
    int? aiConnectTimeoutSeconds,
    int? aiResponseTimeoutSeconds,
    int? aiStreamIdleTimeoutSeconds,
    int? aiStreamMaxCharsPerSecond,
    int? aiStreamMaxMessageCardsPerSecond,
    bool? aiStreamThrottleEnabled,
    bool? aiStreamThrottleAutoMode,
    int? aiStreamThrottleDurationSeconds,
    String? aiStreamThrottleCloudSyncProvider,
    String? aiStreamThrottleCloudSyncEndpoint,
    String? aiStreamThrottleCloudSyncToken,
    int? aiStreamThrottleConfigUpdatedAtMs,
    bool? aiAutoTitleEnabled,
    String? aiDefaultSessionMode,
    bool? aiDefaultFullAccessPermission,
    List<AiModelConfig>? aiModels,
    String? selectedAiModelId,
    List<RecentModelSelection>? recentModelSelections,
    Map<OpenHandShortcutAction, List<int>>? shortcutBindings,
    DialogAnimationSettings? dialogAnimationSettings,
    DialogAnimationSettings? menuAnimationSettings,
    DialogAnimationSettings? pageAnimationSettings,
    DialogAnimationSettings? panelAnimationSettings,
    DialogAnimationSettings? chipAnimationSettings,
    DialogAnimationSettings? listItemAnimationSettings,
    List<AiBuiltinToolConfig>? builtinToolConfigs,
    bool? telemetryDebugEnabled,
    bool? telemetryCaptureRawPayload,
    bool? telemetryCaptureEnvironment,
    int? telemetryMaxPayloadChars,
    bool? selfLearningEnabled,
    int? selfLearningConcurrency,
    int? selfLearningStreamFlushIntervalMs,
    bool? showSelfLearningMessages,
    bool? cronAutoCleanupEnabled,
    int? cronAutoCleanupRetentionDays,
    int? hardnessToolSearchHistoryMaxPhases,
    int? toolSearchReplayCancelWindowSeconds,
    bool? reduceMotion,
    AppProxySettings? proxySettings,
    int? subprocessGracefulShutdownMs,
    int? bashOutputMaxBytes,
    int? maxConcurrentTools,
    bool clearSelectedAiModelId = false,
  }) {
    return AppSettingsSnapshot(
      themeMode: themeMode ?? this.themeMode,
      themePreset: themePreset ?? this.themePreset,
      language: language ?? this.language,
      skillsStoragePath: skillsStoragePath ?? this.skillsStoragePath,
      mcpEnabled: mcpEnabled ?? this.mcpEnabled,
      mcpServersFilePath: mcpServersFilePath ?? this.mcpServersFilePath,
      mcpLazyLoadingMode: mcpLazyLoadingMode ?? this.mcpLazyLoadingMode,
      mcpLazyLoadingThresholdTokens:
          mcpLazyLoadingThresholdTokens ?? this.mcpLazyLoadingThresholdTokens,
      mcpStdioMirrorMode: mcpStdioMirrorMode ?? this.mcpStdioMirrorMode,
      mcpAutoProbeConcurrency:
          mcpAutoProbeConcurrency ?? this.mcpAutoProbeConcurrency,
      mcpKeywordIndexUpdateMode:
          mcpKeywordIndexUpdateMode ?? this.mcpKeywordIndexUpdateMode,
      mcpKeywordIndexIntervalValue:
          mcpKeywordIndexIntervalValue ?? this.mcpKeywordIndexIntervalValue,
      mcpKeywordIndexIntervalUnit:
          mcpKeywordIndexIntervalUnit ?? this.mcpKeywordIndexIntervalUnit,
      mcpKeywordIndexScheduledTimeOfDay:
          mcpKeywordIndexScheduledTimeOfDay ??
          this.mcpKeywordIndexScheduledTimeOfDay,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      userMemoryFilePath: userMemoryFilePath ?? this.userMemoryFilePath,
      editorWordWrap: editorWordWrap ?? this.editorWordWrap,
      editorIndentSpaces: editorIndentSpaces ?? this.editorIndentSpaces,
      editorCodeTheme: editorCodeTheme ?? this.editorCodeTheme,
      editorLspSettings: editorLspSettings ?? this.editorLspSettings,
      editorShortcutBindings:
          editorShortcutBindings ?? this.editorShortcutBindings,
      aiMessageCompressionThresholdChars:
          aiMessageCompressionThresholdChars ??
          this.aiMessageCompressionThresholdChars,
      aiToolResultCompressionThresholdChars:
          aiToolResultCompressionThresholdChars ??
          this.aiToolResultCompressionThresholdChars,
      aiToolResultCompressionEnabled:
          aiToolResultCompressionEnabled ?? this.aiToolResultCompressionEnabled,
      aiMicroCompressionEnabled:
          aiMicroCompressionEnabled ?? this.aiMicroCompressionEnabled,
      aiMessageContentFormat:
          aiMessageContentFormat ?? this.aiMessageContentFormat,
      aiHtmlRenderFallback:
          aiHtmlRenderFallback ?? this.aiHtmlRenderFallback,
      aiToolResultCompressionHeadTailWindowChars:
          aiToolResultCompressionHeadTailWindowChars ??
          this.aiToolResultCompressionHeadTailWindowChars,
      aiToolResultCompressionMaxPathHits:
          aiToolResultCompressionMaxPathHits ??
          this.aiToolResultCompressionMaxPathHits,
      aiInputCacheEnabled: aiInputCacheEnabled ?? this.aiInputCacheEnabled,
      aiInputCacheUpdateMode:
          aiInputCacheUpdateMode ?? this.aiInputCacheUpdateMode,
      aiInputCacheUpdateInterval:
          aiInputCacheUpdateInterval ?? this.aiInputCacheUpdateInterval,
      aiInputCacheBreakpointCount:
          aiInputCacheBreakpointCount ?? this.aiInputCacheBreakpointCount,
      aiInputCacheBreakpointPositions:
          aiInputCacheBreakpointPositions ??
          this.aiInputCacheBreakpointPositions,
      aiBudgetUsdPerSession:
          aiBudgetUsdPerSession ?? this.aiBudgetUsdPerSession,
      aiWriteToolSummaryMaxChars:
          aiWriteToolSummaryMaxChars ?? this.aiWriteToolSummaryMaxChars,
      aiSingleRoundToolCallLimit:
          aiSingleRoundToolCallLimit ?? this.aiSingleRoundToolCallLimit,
      aiSequentialToolRoundLimit:
          aiSequentialToolRoundLimit ?? this.aiSequentialToolRoundLimit,
      aiMaxRecentErrors: aiMaxRecentErrors ?? this.aiMaxRecentErrors,
      aiMaxPlanHistoryEntries:
          aiMaxPlanHistoryEntries ?? this.aiMaxPlanHistoryEntries,
      aiMaxTruncationContinuations:
          aiMaxTruncationContinuations ?? this.aiMaxTruncationContinuations,
      aiEstimatedCharactersPerToken:
          aiEstimatedCharactersPerToken ?? this.aiEstimatedCharactersPerToken,
      aiMaxToolOutputChars: aiMaxToolOutputChars ?? this.aiMaxToolOutputChars,
      aiWriteConfirmationTimeoutMs:
          aiWriteConfirmationTimeoutMs ?? this.aiWriteConfirmationTimeoutMs,
      aiFastPathWriteAnalysisThreshold:
          aiFastPathWriteAnalysisThreshold ??
          this.aiFastPathWriteAnalysisThreshold,
      aiMaxHookTextCharacters:
          aiMaxHookTextCharacters ?? this.aiMaxHookTextCharacters,
      aiWebFetchMaxResponseBytes:
          aiWebFetchMaxResponseBytes ?? this.aiWebFetchMaxResponseBytes,
      aiWebFetchMaxRedirects:
          aiWebFetchMaxRedirects ?? this.aiWebFetchMaxRedirects,
      aiWebFetchMaxCacheEntries:
          aiWebFetchMaxCacheEntries ?? this.aiWebFetchMaxCacheEntries,
      aiAttachmentMaxInlineImageDimension:
          aiAttachmentMaxInlineImageDimension ??
          this.aiAttachmentMaxInlineImageDimension,
      aiAttachmentMaxTextRawBytes:
          aiAttachmentMaxTextRawBytes ?? this.aiAttachmentMaxTextRawBytes,
      aiAttachmentMaxPdfRawBytes:
          aiAttachmentMaxPdfRawBytes ?? this.aiAttachmentMaxPdfRawBytes,
      aiAttachmentMaxImageRawBytes:
          aiAttachmentMaxImageRawBytes ?? this.aiAttachmentMaxImageRawBytes,
      aiChatMaxStreamLineBufferBytes:
          aiChatMaxStreamLineBufferBytes ?? this.aiChatMaxStreamLineBufferBytes,
      aiFallbackTitleMaxCharacters:
          aiFallbackTitleMaxCharacters ?? this.aiFallbackTitleMaxCharacters,
      aiGeneratedTitleMaxCharacters:
          aiGeneratedTitleMaxCharacters ?? this.aiGeneratedTitleMaxCharacters,
      aiAutoTitleMaxRetryCount:
          aiAutoTitleMaxRetryCount ?? this.aiAutoTitleMaxRetryCount,
      aiMinimumMeaningfulTitleCharacters:
          aiMinimumMeaningfulTitleCharacters ??
          this.aiMinimumMeaningfulTitleCharacters,
      aiMinimumMeaningfulLatinTitleWords:
          aiMinimumMeaningfulLatinTitleWords ??
          this.aiMinimumMeaningfulLatinTitleWords,
      aiMaxSkillContentLength:
          aiMaxSkillContentLength ?? this.aiMaxSkillContentLength,
      aiMaxWorkspaceDocumentCharacters:
          aiMaxWorkspaceDocumentCharacters ??
          this.aiMaxWorkspaceDocumentCharacters,
      aiImageSizeLimitBytes:
          aiImageSizeLimitBytes ?? this.aiImageSizeLimitBytes,
      aiWriteCommandConfirmationEnabled:
          aiWriteCommandConfirmationEnabled ??
          this.aiWriteCommandConfirmationEnabled,
      aiAllowCommandRules: aiAllowCommandRules ?? this.aiAllowCommandRules,
      aiDenyCommandRules: aiDenyCommandRules ?? this.aiDenyCommandRules,
      aiSandboxSettings: aiSandboxSettings ?? this.aiSandboxSettings,
      aiConnectTimeoutSeconds:
          aiConnectTimeoutSeconds ?? this.aiConnectTimeoutSeconds,
      aiResponseTimeoutSeconds:
          aiResponseTimeoutSeconds ?? this.aiResponseTimeoutSeconds,
      aiStreamIdleTimeoutSeconds:
          aiStreamIdleTimeoutSeconds ?? this.aiStreamIdleTimeoutSeconds,
      aiStreamMaxCharsPerSecond:
          aiStreamMaxCharsPerSecond ?? this.aiStreamMaxCharsPerSecond,
      aiStreamMaxMessageCardsPerSecond:
          aiStreamMaxMessageCardsPerSecond ??
          this.aiStreamMaxMessageCardsPerSecond,
      aiStreamThrottleEnabled:
          aiStreamThrottleEnabled ?? this.aiStreamThrottleEnabled,
      aiStreamThrottleAutoMode:
          aiStreamThrottleAutoMode ?? this.aiStreamThrottleAutoMode,
      aiStreamThrottleDurationSeconds:
          aiStreamThrottleDurationSeconds ??
          this.aiStreamThrottleDurationSeconds,
      aiStreamThrottleCloudSyncProvider:
          aiStreamThrottleCloudSyncProvider ??
          this.aiStreamThrottleCloudSyncProvider,
      aiStreamThrottleCloudSyncEndpoint:
          aiStreamThrottleCloudSyncEndpoint ??
          this.aiStreamThrottleCloudSyncEndpoint,
      aiStreamThrottleCloudSyncToken:
          aiStreamThrottleCloudSyncToken ?? this.aiStreamThrottleCloudSyncToken,
      aiStreamThrottleConfigUpdatedAtMs:
          aiStreamThrottleConfigUpdatedAtMs ??
          this.aiStreamThrottleConfigUpdatedAtMs,
      aiAutoTitleEnabled: aiAutoTitleEnabled ?? this.aiAutoTitleEnabled,
      aiDefaultSessionMode: aiDefaultSessionMode ?? this.aiDefaultSessionMode,
      aiDefaultFullAccessPermission:
          aiDefaultFullAccessPermission ?? this.aiDefaultFullAccessPermission,
      aiModels: aiModels ?? this.aiModels,
      selectedAiModelId: clearSelectedAiModelId
          ? null
          : selectedAiModelId ?? this.selectedAiModelId,
      recentModelSelections:
          recentModelSelections ?? this.recentModelSelections,
      shortcutBindings: shortcutBindings ?? this.shortcutBindings,
      dialogAnimationSettings:
          dialogAnimationSettings ?? this.dialogAnimationSettings,
      menuAnimationSettings:
          menuAnimationSettings ?? this.menuAnimationSettings,
      pageAnimationSettings:
          pageAnimationSettings ?? this.pageAnimationSettings,
      panelAnimationSettings:
          panelAnimationSettings ?? this.panelAnimationSettings,
      chipAnimationSettings:
          chipAnimationSettings ?? this.chipAnimationSettings,
      listItemAnimationSettings:
          listItemAnimationSettings ?? this.listItemAnimationSettings,
      builtinToolConfigs: builtinToolConfigs ?? this.builtinToolConfigs,
      telemetryDebugEnabled:
          telemetryDebugEnabled ?? this.telemetryDebugEnabled,
      telemetryCaptureRawPayload:
          telemetryCaptureRawPayload ?? this.telemetryCaptureRawPayload,
      telemetryCaptureEnvironment:
          telemetryCaptureEnvironment ?? this.telemetryCaptureEnvironment,
      telemetryMaxPayloadChars:
          telemetryMaxPayloadChars ?? this.telemetryMaxPayloadChars,
      selfLearningEnabled: selfLearningEnabled ?? this.selfLearningEnabled,
      selfLearningConcurrency:
          selfLearningConcurrency ?? this.selfLearningConcurrency,
      selfLearningStreamFlushIntervalMs:
          selfLearningStreamFlushIntervalMs ??
          this.selfLearningStreamFlushIntervalMs,
      showSelfLearningMessages:
          showSelfLearningMessages ?? this.showSelfLearningMessages,
      cronAutoCleanupEnabled:
          cronAutoCleanupEnabled ?? this.cronAutoCleanupEnabled,
      cronAutoCleanupRetentionDays:
          cronAutoCleanupRetentionDays ?? this.cronAutoCleanupRetentionDays,
      hardnessToolSearchHistoryMaxPhases:
          hardnessToolSearchHistoryMaxPhases ??
          this.hardnessToolSearchHistoryMaxPhases,
      toolSearchReplayCancelWindowSeconds:
          toolSearchReplayCancelWindowSeconds ??
          this.toolSearchReplayCancelWindowSeconds,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      proxySettings: proxySettings ?? this.proxySettings,
      subprocessGracefulShutdownMs:
          subprocessGracefulShutdownMs ?? this.subprocessGracefulShutdownMs,
      bashOutputMaxBytes: bashOutputMaxBytes ?? this.bashOutputMaxBytes,
      maxConcurrentTools: maxConcurrentTools ?? this.maxConcurrentTools,
    );
  }
}

/// A recently selected model entry for quick access in the model selector.
class RecentModelSelection {
  const RecentModelSelection({required this.configId, required this.modelId});

  factory RecentModelSelection.fromJson(Map<String, Object?> json) {
    return RecentModelSelection(
      configId: '${json['config_id'] ?? ''}'.trim(),
      modelId: '${json['model_id'] ?? ''}'.trim(),
    );
  }

  final String configId;
  final String modelId;

  Map<String, Object?> toJson() {
    return <String, Object?>{'config_id': configId, 'model_id': modelId};
  }

  @override
  bool operator ==(Object other) {
    return other is RecentModelSelection &&
        other.configId == configId &&
        other.modelId == modelId;
  }

  @override
  int get hashCode => Object.hash(configId, modelId);
}

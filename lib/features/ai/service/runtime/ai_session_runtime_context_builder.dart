import 'dart:io';

import '../../../../app/model/app_info.dart';
import '../../../../app/state/settings_controller.dart';
import '../../../../shared/util/date_time_format.dart';
import '../../../../shared/util/hex_encoding.dart';
import '../../../instructions/index.dart';
import '../../../mcp/index.dart';
import '../../../memory/index.dart';
import '../../../skills/index.dart';
import '../../../workflows/index.dart' show WorkflowDefinition;
import '../../model/ai_allow_command_rule.dart';
import '../../model/ai_builtin_tool_config.dart';
import '../../model/ai_dingtalk_dws_command.dart';
import '../../model/ai_session_runtime_context.dart';

/// 设置项到 [AiSessionRuntimeContext] 的唯一映射。
///
/// 桌面主界面、工具目录预览、Web 网关三条链路此前各写一份构造，且长短不一：
/// 网关那份只填了 40 项、漏掉 45 项，于是同一个会话从手机端发起时，超时、
/// 工具轮次上限、允许命令规则、沙箱设置、附件上限等统统退回默认值——和桌面
/// 端发起跑出来不是一回事。新增一项设置只改其中一处也会立刻分叉。
///
/// 这里只保留一份设置映射，随会话变化的字段由调用方传入。
AiSessionRuntimeContext buildAiSessionRuntimeContext({
  required SettingsController settingsController,
  required AppInfo appInfo,
  required String appThemeBrightness,
  required DateTime localNow,
  required String workingDirectory,
  required List<UserMemoryEntry> memoryEntries,
  required List<AiAllowCommandRule> allowCommandRules,
  required List<LocalSkill> availableSkills,
  List<WorkflowDefinition> availableWorkflows = const <WorkflowDefinition>[],
  required List<McpServer> availableMcpServers,
  List<AiDingTalkDwsCommand> availableDingTalkDwsCommands =
      const <AiDingTalkDwsCommand>[],
  required Map<String, McpToolCatalog> mcpToolCatalogsByServerName,
  required List<AiBuiltinToolConfig> builtinToolConfigs,
  AiRepositorySnapshot? repositorySnapshot,
  List<AiWorkspaceInstructionDocument> workspaceInstructionDocuments =
      const <AiWorkspaceInstructionDocument>[],
  List<UserInstructionEntry> userInstructions = const <UserInstructionEntry>[],
  Set<String> skippedInstructionIds = const <String>{},
  String templateId = '',
  Map<String, Object?> toolExecutionMetadata = const <String, Object?>{},
}) {
  return AiSessionRuntimeContext(
    templateId: templateId,
    toolExecutionMetadata: toolExecutionMetadata,
    // 技能正文上限由会话控制器回灌给 SkillManager 工具；此前这份映射没填，
    // 于是它恒等于模型默认值，用户改了设置也不生效。
    maxSkillContentLength: settingsController.aiMaxSkillContentLength,
    maxWorkspaceDocumentCharacters:
        settingsController.aiMaxWorkspaceDocumentCharacters,
    fallbackTitleMaxCharacters: settingsController.aiFallbackTitleMaxCharacters,
    generatedTitleMaxCharacters:
        settingsController.aiGeneratedTitleMaxCharacters,
    minimumMeaningfulTitleCharacters:
        settingsController.aiMinimumMeaningfulTitleCharacters,
    minimumMeaningfulLatinTitleWords:
        settingsController.aiMinimumMeaningfulLatinTitleWords,
    localeTag: settingsController.locale.toLanguageTag(),
    appVersion: appInfo.version,
    appBuildNumber: appInfo.buildNumber,
    settingsFilePath: settingsController.settingsFilePath,
    skillsStoragePath: settingsController.skillsStoragePath,
    mcpServersFilePath: settingsController.mcpServersFilePath,
    userMemoryFilePath: settingsController.userMemoryFilePath,
    compressionThresholdChars:
        settingsController.aiMessageCompressionThresholdChars,
    toolResultCompressionThresholdChars:
        settingsController.aiToolResultCompressionThresholdChars,
    toolResultCompressionEnabled:
        settingsController.aiToolResultCompressionEnabled,
    toolResultCompressionHeadTailWindowChars:
        settingsController.aiToolResultCompressionHeadTailWindowChars,
    toolResultCompressionMaxPathHits:
        settingsController.aiToolResultCompressionMaxPathHits,
    microCompressionEnabled: settingsController.aiMicroCompressionEnabled,
    messageContentFormat: settingsController.aiMessageContentFormat,
    htmlRenderFallback: settingsController.aiHtmlRenderFallback,
    htmlContentRichness: settingsController.aiHtmlContentRichness,
    appThemeBrightness: appThemeBrightness,
    appThemePresetName: settingsController.themePreset.storageValue,
    appThemePrimaryColor:
        '#${rgbHexFromArgb32(settingsController.themePreset.seedColor.toARGB32()).toUpperCase()}',
    writeToolSummaryMaxChars: settingsController.aiWriteToolSummaryMaxChars,
    aiInputCacheEnabled: settingsController.aiInputCacheEnabled,
    aiInputCacheUpdateMode: settingsController.aiInputCacheUpdateMode,
    aiInputCacheUpdateInterval: settingsController.aiInputCacheUpdateInterval,
    aiInputCacheBreakpointCount: settingsController.aiInputCacheBreakpointCount,
    aiInputCacheBreakpointPositions:
        settingsController.aiInputCacheBreakpointPositions,
    singleRoundToolCallLimit: settingsController.aiSingleRoundToolCallLimit,
    sequentialToolRoundLimit: settingsController.aiSequentialToolRoundLimit,
    maxRecentErrors: settingsController.aiMaxRecentErrors,
    maxPlanHistoryEntries: settingsController.aiMaxPlanHistoryEntries,
    maxTruncationContinuations: settingsController.aiMaxTruncationContinuations,
    estimatedCharactersPerToken:
        settingsController.aiEstimatedCharactersPerToken,
    maxToolOutputChars: settingsController.aiMaxToolOutputChars,
    writeConfirmationTimeoutMs: settingsController.aiWriteConfirmationTimeoutMs,
    fastPathWriteAnalysisThreshold:
        settingsController.aiFastPathWriteAnalysisThreshold,
    maxHookTextCharacters: settingsController.aiMaxHookTextCharacters,
    subprocessGracefulShutdownMs:
        settingsController.subprocessGracefulShutdownMs,
    bashOutputMaxBytes: settingsController.bashOutputMaxBytes,
    maxConcurrentTools: settingsController.maxConcurrentTools,
    attachmentMaxInlineImageDimension:
        settingsController.aiAttachmentMaxInlineImageDimension,
    attachmentMaxTextRawBytes: settingsController.aiAttachmentMaxTextRawBytes,
    attachmentMaxPdfRawBytes: settingsController.aiAttachmentMaxPdfRawBytes,
    attachmentMaxImageRawBytes: settingsController.aiAttachmentMaxImageRawBytes,
    chatMaxStreamLineBufferBytes:
        settingsController.aiChatMaxStreamLineBufferBytes,
    imageSizeLimitBytes: settingsController.aiImageSizeLimitBytes,
    memoryEnabled: settingsController.memoryEnabled,
    mcpLazyLoadingMode: settingsController.mcpLazyLoadingMode,
    mcpLazyLoadingThresholdTokens:
        settingsController.mcpLazyLoadingThresholdTokens,
    builtinToolLazyLoadingMode: settingsController.builtinToolLazyLoadingMode,
    writeCommandConfirmationEnabled:
        settingsController.aiWriteCommandConfirmationEnabled,
    connectTimeoutSeconds: settingsController.aiConnectTimeoutSeconds,
    responseTimeoutSeconds: settingsController.aiResponseTimeoutSeconds,
    streamIdleTimeoutSeconds: settingsController.aiStreamIdleTimeoutSeconds,
    streamMaxCharsPerSecond: settingsController.aiStreamMaxCharsPerSecond,
    streamThrottleEnabled: settingsController.aiStreamThrottleEnabled,
    streamThrottleAutoMode: settingsController.aiStreamThrottleAutoMode,
    streamThrottleDurationSeconds:
        settingsController.aiStreamThrottleDurationSeconds,
    streamMaxMessageCardsPerSecond:
        settingsController.aiStreamMaxMessageCardsPerSecond,
    autoTitleEnabled: settingsController.aiAutoTitleEnabled,
    autoTitleFetchMode: settingsController.aiAutoTitleFetchMode,
    autoTitleMaxRetryCount: settingsController.aiAutoTitleMaxRetryCount,
    telemetryDebugEnabled: settingsController.telemetryDebugEnabled,
    telemetryCaptureRawPayload: settingsController.telemetryCaptureRawPayload,
    telemetryCaptureEnvironment: settingsController.telemetryCaptureEnvironment,
    telemetryMaxPayloadChars: settingsController.telemetryMaxPayloadChars,
    platformName: Platform.operatingSystem,
    workingDirectory: workingDirectory,
    todayLocalDate: formatYearMonthDay(localNow),
    timeZoneName: localNow.timeZoneName,
    repositorySnapshot: repositorySnapshot,
    memoryEntries: memoryEntries,
    allowCommandRules: allowCommandRules,
    sandboxSettings: settingsController.aiSandboxSettings,
    availableSkills: availableSkills,
    availableWorkflows: availableWorkflows,
    availableMcpServers: availableMcpServers,
    availableDingTalkDwsCommands: availableDingTalkDwsCommands,
    mcpToolCatalogsByServerName: mcpToolCatalogsByServerName,
    builtinToolConfigs: builtinToolConfigs,
    workspaceInstructionDocuments: workspaceInstructionDocuments,
    userInstructions: userInstructions,
    skippedInstructionIds: skippedInstructionIds,
  );
}

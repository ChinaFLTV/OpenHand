import '../../../app/support/openhand_paths.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../instructions/index.dart';
import '../../mcp/index.dart';
import '../../memory/index.dart';
import '../../skills/index.dart';
import '../../workflows/index.dart' show WorkflowDefinition;
import 'ai_allow_command_rule.dart';
import 'ai_auto_title_fetch_mode.dart';
import 'ai_builtin_tool_config.dart';
import 'ai_dingtalk_dws_command.dart';
import 'ai_message_content_format.dart';
import 'ai_request_timeout_policy.dart';
import 'ai_sandbox_settings.dart';
import 'ai_stream_throttle_policy.dart';
import 'ai_tool_call_limit_policy.dart';
import 'ai_tool_execution_limit_policy.dart';

class AiRepositorySnapshot {
  factory AiRepositorySnapshot.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return AiRepositorySnapshot(
      workingDirectory: stringFromValue(json['working_directory']),
      isGitRepository: boolFromValue(json['is_git_repository']),
      repositoryRootPath: stringFromValue(json['repository_root_path']),
      currentBranch: stringFromValue(json['current_branch']),
      mainBranch: stringFromValue(json['main_branch']),
      statusSnapshot: stringFromValue(json['status_snapshot']),
      recentCommits: stringListFromValueOrJsonText(json['recent_commits']),
      capturedAtIso8601: stringFromValue(json['captured_at']),
    );
  }
  const AiRepositorySnapshot({
    required this.workingDirectory,
    required this.isGitRepository,
    this.repositoryRootPath = '',
    this.currentBranch = '',
    this.mainBranch = '',
    this.statusSnapshot = '',
    this.recentCommits = const <String>[],
    this.capturedAtIso8601 = '',
  });

  final String workingDirectory;
  final bool isGitRepository;
  final String repositoryRootPath;
  final String currentBranch;
  final String mainBranch;
  final String statusSnapshot;
  final List<String> recentCommits;
  final String capturedAtIso8601;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'working_directory': workingDirectory,
      'is_git_repository': isGitRepository,
      'repository_root_path': repositoryRootPath,
      'current_branch': currentBranch,
      'main_branch': mainBranch,
      'status_snapshot': statusSnapshot,
      'recent_commits': recentCommits,
      'captured_at': capturedAtIso8601,
    };
  }
}

class AiWorkspaceInstructionDocument {
  const AiWorkspaceInstructionDocument({
    required this.path,
    required this.name,
    required this.content,
  });

  final String path;
  final String name;
  final String content;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'name': name,
      'character_count': content.length,
    };
  }
}

class AiSessionRuntimeContext {
  AiSessionRuntimeContext({
    required this.localeTag,
    required this.appVersion,
    required this.appBuildNumber,
    required this.settingsFilePath,
    required this.skillsStoragePath,
    required this.mcpServersFilePath,
    required this.userMemoryFilePath,
    required this.compressionThresholdChars,
    this.toolResultCompressionThresholdChars = 1024,
    this.toolResultCompressionEnabled = true,
    this.microCompressionEnabled = true,
    this.messageContentFormat = defaultAiMessageContentFormat,
    this.htmlRenderFallback = defaultAiHtmlRenderFallback,
    this.htmlContentRichness = defaultAiHtmlContentRichness,
    this.appThemeBrightness = 'dark',
    this.appThemePresetName = 'deepSeaBlue',
    this.appThemePrimaryColor = '#2D63B8',
    this.toolResultCompressionHeadTailWindowChars = 256,
    this.toolResultCompressionMaxPathHits = 12,
    this.writeToolSummaryMaxChars = 280,
    // 与 AppSettingsSnapshot.defaultAiInputCacheEnabled
    // 同步改为 true：绝大多数用户依赖 Claude 协议前缀缓存降低成本；
    // 关闭后 Claude native 不再注入显式 cache_control 断点。手动关闭入口
    // 仍在"输入缓存"设置页。
    this.aiInputCacheEnabled = true,
    this.aiInputCacheUpdateMode = 'allMessages',
    this.aiInputCacheUpdateInterval = 10,
    this.aiInputCacheBreakpointCount = 4,
    this.aiInputCacheBreakpointPositions = const <double>[],
    required this.memoryEnabled,
    required this.memoryEntries,
    this.templateId = '',
    int singleRoundToolCallLimit = defaultSingleRoundToolCallLimit,
    int sequentialToolRoundLimit = defaultSequentialToolRoundLimit,
    this.maxRecentErrors = 20,
    this.maxPlanHistoryEntries = 20,
    this.maxTruncationContinuations = 5,
    this.estimatedCharactersPerToken = 4,
    int maxToolOutputChars = defaultMaxToolOutputChars,
    int writeConfirmationTimeoutMs = defaultWriteConfirmationTimeoutMs,
    int fastPathWriteAnalysisThreshold = defaultFastPathWriteAnalysisThreshold,
    int maxHookTextCharacters = defaultMaxHookTextCharacters,
    int subprocessGracefulShutdownMs = defaultSubprocessGracefulShutdownMs,
    int bashOutputMaxBytes = defaultBashOutputMaxBytes,
    int maxConcurrentTools = defaultMaxConcurrentTools,
    this.attachmentMaxInlineImageDimension = 1568,
    this.attachmentMaxTextRawBytes = 2 * kBytesPerMiB,
    this.attachmentMaxPdfRawBytes = 2 * kBytesPerMiB,
    this.attachmentMaxImageRawBytes = 50 * kBytesPerMiB,
    this.chatMaxStreamLineBufferBytes = 4 * kBytesPerMiB,
    this.fallbackTitleMaxCharacters = 20,
    this.generatedTitleMaxCharacters = 20,
    this.minimumMeaningfulTitleCharacters = 4,
    this.minimumMeaningfulLatinTitleWords = 2,
    this.maxSkillContentLength = 100000,
    this.maxWorkspaceDocumentCharacters = 16000,
    this.imageSizeLimitBytes = kBytesPerMiB,
    this.writeCommandConfirmationEnabled = true,
    int connectTimeoutSeconds = defaultConnectTimeoutSeconds,
    int responseTimeoutSeconds = defaultResponseTimeoutSeconds,
    int streamIdleTimeoutSeconds = defaultStreamIdleTimeoutSeconds,
    int streamMaxCharsPerSecond = defaultStreamMaxCharsPerSecond,
    int streamMaxMessageCardsPerSecond = defaultStreamMaxMessageCardsPerSecond,
    this.streamThrottleEnabled = true,
    this.streamThrottleAutoMode = false,
    int streamThrottleDurationSeconds = defaultStreamThrottleDurationSeconds,
    this.autoTitleEnabled = true,
    this.autoTitleFetchMode = AiAutoTitleFetchMode.asynchronous,
    this.autoTitleMaxRetryCount = 5,
    this.telemetryDebugEnabled = false,
    this.telemetryCaptureRawPayload = true,
    this.telemetryCaptureEnvironment = false,
    this.telemetryMaxPayloadChars = 200000,
    this.platformName = '',
    this.workingDirectory = '',
    this.todayLocalDate = '',
    this.timeZoneName = '',
    this.repositorySnapshot,
    this.allowCommandRules = const <AiAllowCommandRule>[],
    AiSandboxSettings? sandboxSettings,
    this.availableSkills = const <LocalSkill>[],
    this.availableWorkflows = const <WorkflowDefinition>[],
    this.availableMcpServers = const <McpServer>[],
    this.availableDingTalkDwsCommands = const <AiDingTalkDwsCommand>[],
    this.mcpToolCatalogsByServerName = const <String, McpToolCatalog>{},
    this.mcpLazyLoadingMode = McpLazyLoadingMode.auto,
    this.mcpLazyLoadingThresholdTokens = 16000,
    this.builtinToolLazyLoadingMode = AiBuiltinToolLazyLoadingMode.auto,
    this.builtinToolConfigs = const <AiBuiltinToolConfig>[],
    this.workspaceInstructionDocuments =
        const <AiWorkspaceInstructionDocument>[],
    this.userInstructions = const <UserInstructionEntry>[],
    this.skippedInstructionIds = const <String>{},
    this.toolExecutionMetadata = const <String, Object?>{},
  }) : singleRoundToolCallLimit = normalizeSingleRoundToolCallLimit(
         singleRoundToolCallLimit,
       ),
       sequentialToolRoundLimit = normalizeSequentialToolRoundLimit(
         sequentialToolRoundLimit,
       ),
       maxToolOutputChars = normalizeMaxToolOutputChars(maxToolOutputChars),
       writeConfirmationTimeoutMs = normalizeWriteConfirmationTimeoutMs(
         writeConfirmationTimeoutMs,
       ),
       fastPathWriteAnalysisThreshold = normalizeFastPathWriteAnalysisThreshold(
         fastPathWriteAnalysisThreshold,
       ),
       maxHookTextCharacters = normalizeMaxHookTextCharacters(
         maxHookTextCharacters,
       ),
       subprocessGracefulShutdownMs = normalizeSubprocessGracefulShutdownMs(
         subprocessGracefulShutdownMs,
       ),
       bashOutputMaxBytes = normalizeBashOutputMaxBytes(bashOutputMaxBytes),
       maxConcurrentTools = normalizeMaxConcurrentTools(maxConcurrentTools),
       connectTimeoutSeconds = normalizeConnectTimeoutSeconds(
         connectTimeoutSeconds,
       ),
       responseTimeoutSeconds = normalizeResponseTimeoutSeconds(
         responseTimeoutSeconds,
       ),
       streamIdleTimeoutSeconds = normalizeStreamIdleTimeoutSeconds(
         streamIdleTimeoutSeconds,
       ),
       streamMaxCharsPerSecond = normalizeStreamMaxCharsPerSecond(
         streamMaxCharsPerSecond,
       ),
       streamMaxMessageCardsPerSecond = normalizeStreamMaxMessageCardsPerSecond(
         streamMaxMessageCardsPerSecond,
       ),
       streamThrottleDurationSeconds = normalizeStreamThrottleDurationSeconds(
         streamThrottleDurationSeconds,
       ),
       sandboxSettings = sandboxSettings ?? AiSandboxSettings.defaultValue;

  static const int defaultSingleRoundToolCallLimit =
      AiToolCallLimitPolicy.defaultSingleRoundToolCallLimit;
  static const int defaultSequentialToolRoundLimit =
      AiToolCallLimitPolicy.defaultSequentialToolRoundLimit;

  static int normalizeSingleRoundToolCallLimit(int value) {
    return AiToolCallLimitPolicy.normalizeSingleRound(value);
  }

  static int normalizeSequentialToolRoundLimit(int value) {
    return AiToolCallLimitPolicy.normalizeSequentialRound(value);
  }

  static const int defaultMaxToolOutputChars =
      AiToolExecutionLimitPolicy.defaultMaxToolOutputChars;
  static const int defaultWriteConfirmationTimeoutMs =
      AiToolExecutionLimitPolicy.defaultWriteConfirmationTimeoutMs;
  static const int defaultFastPathWriteAnalysisThreshold =
      AiToolExecutionLimitPolicy.defaultFastPathWriteAnalysisThreshold;
  static const int defaultMaxHookTextCharacters =
      AiToolExecutionLimitPolicy.defaultMaxHookTextCharacters;
  static const int defaultSubprocessGracefulShutdownMs =
      AiToolExecutionLimitPolicy.defaultSubprocessGracefulShutdownMs;
  static const int defaultBashOutputMaxBytes =
      AiToolExecutionLimitPolicy.defaultBashOutputMaxBytes;
  static const int defaultMaxConcurrentTools =
      AiToolExecutionLimitPolicy.defaultMaxConcurrentTools;

  static int normalizeMaxToolOutputChars(int value) {
    return AiToolExecutionLimitPolicy.normalizeMaxToolOutputChars(value);
  }

  static int normalizeWriteConfirmationTimeoutMs(int value) {
    return AiToolExecutionLimitPolicy.normalizeWriteConfirmationTimeoutMs(
      value,
    );
  }

  static int normalizeFastPathWriteAnalysisThreshold(int value) {
    return AiToolExecutionLimitPolicy.normalizeFastPathWriteAnalysisThreshold(
      value,
    );
  }

  static int normalizeMaxHookTextCharacters(int value) {
    return AiToolExecutionLimitPolicy.normalizeMaxHookTextCharacters(value);
  }

  static int normalizeSubprocessGracefulShutdownMs(int value) {
    return AiToolExecutionLimitPolicy.normalizeSubprocessGracefulShutdownMs(
      value,
    );
  }

  static int normalizeBashOutputMaxBytes(int value) {
    return AiToolExecutionLimitPolicy.normalizeBashOutputMaxBytes(value);
  }

  static int normalizeMaxConcurrentTools(int value) {
    return AiToolExecutionLimitPolicy.normalizeMaxConcurrentTools(value);
  }

  static const int defaultConnectTimeoutSeconds =
      AiRequestTimeoutPolicy.defaultConnectTimeoutSeconds;
  static const int defaultResponseTimeoutSeconds =
      AiRequestTimeoutPolicy.defaultResponseTimeoutSeconds;
  static const int defaultStreamIdleTimeoutSeconds =
      AiRequestTimeoutPolicy.defaultStreamIdleTimeoutSeconds;

  static int normalizeConnectTimeoutSeconds(int value) {
    return AiRequestTimeoutPolicy.normalizeConnectTimeoutSeconds(value);
  }

  static int normalizeResponseTimeoutSeconds(int value) {
    return AiRequestTimeoutPolicy.normalizeResponseTimeoutSeconds(value);
  }

  static int normalizeStreamIdleTimeoutSeconds(int value) {
    return AiRequestTimeoutPolicy.normalizeStreamIdleTimeoutSeconds(value);
  }

  static const int defaultStreamMaxCharsPerSecond =
      AiStreamThrottlePolicy.defaultMaxCharsPerSecond;
  static const int defaultStreamMaxMessageCardsPerSecond =
      AiStreamThrottlePolicy.defaultMaxMessageCardsPerSecond;
  static const int defaultStreamThrottleDurationSeconds =
      AiStreamThrottlePolicy.defaultDurationSeconds;

  static int normalizeStreamMaxCharsPerSecond(int value) {
    return AiStreamThrottlePolicy.normalizeMaxCharsPerSecond(value);
  }

  static int normalizeStreamMaxMessageCardsPerSecond(int value) {
    return AiStreamThrottlePolicy.normalizeMaxMessageCardsPerSecond(value);
  }

  static int normalizeStreamThrottleDurationSeconds(int value) {
    return AiStreamThrottlePolicy.normalizeDurationSeconds(value);
  }

  final String localeTag;
  final String appVersion;
  final String appBuildNumber;
  final String settingsFilePath;
  final String skillsStoragePath;
  final String mcpServersFilePath;
  final String userMemoryFilePath;
  final int compressionThresholdChars;

  /// 工具调用输出进入 prompt history 时的结构化摘要阈值。尚未被模型消费
  /// 的最新工具结果保留原文；已消费的旧结果超过阈值后会摘要，避免大文件
  /// 输出长期占用上下文和缓存预算。
  final int toolResultCompressionThresholdChars;

  /// 工具调用输出压缩总开关。关闭后返回原始内容。
  final bool toolResultCompressionEnabled;

  /// 生成摘要检查点 prompt 时是否启用工具结果微压缩。正常对话 history
  /// 保持稳定摘要形态，避免跨轮改写旧工具结果破坏输入缓存前缀命中。
  final bool microCompressionEnabled;

  /// 助手消息渲染格式（Markdown / 纯文本 / HTML）。
  /// `AiPromptBuilder` 会在非 Markdown 模式下于 [3d] 后追加
  /// `output_format` reminder，告知模型当轮输出需遵守的约束。
  final AiMessageContentFormat messageContentFormat;

  /// HTML 渲染失败时的回退策略，仅在
  /// [messageContentFormat] 为 `AiMessageContentFormat.html` 时生效。
  final AiHtmlRenderFallback htmlRenderFallback;

  /// HTML 内容丰富度。仅在 [messageContentFormat] 为 HTML 时生效；
  /// `AiPromptBuilder` 根据该值选择不同强度的 `output_format` reminder。
  final AiHtmlContentRichness htmlContentRichness;

  /// 当前应用界面的亮度模式（light / dark）。
  /// 在 HTML 模式下通过 theme_context 告知模型，避免生成与当前主题基调冲突的内容。
  final String appThemeBrightness;

  /// 当前应用主题预设的名称（如 deepSeaBlue / frostMorningBlue）。
  /// 在 HTML 模式下通过 theme_context 告知模型，让其在保持基调的前提下
  /// 结合主题配色做更丰富的视觉表达。
  final String appThemePresetName;

  /// 当前应用主题预设的主色 seed color（如 #2D63B8）。
  /// 在 HTML 模式下通过 theme_context 告知模型，引导其在需要强调色时
  /// 优先使用与当前主题协调的色彩。
  final String appThemePrimaryColor;

  /// 压缩摘要首尾片段窗口长度（字符）。
  final int toolResultCompressionHeadTailWindowChars;

  /// 压缩摘要中提取的文件路径条数上限。
  final int toolResultCompressionMaxPathHits;

  /// 写类工具摘要中保留 result_text 的字符上限。
  final int writeToolSummaryMaxChars;

  /// 是否启用输入缓存 (Anthropic prompt caching 等)。
  final bool aiInputCacheEnabled;

  /// 缓存断点更新模式: allMessages / userMessages / tokens。
  final String aiInputCacheUpdateMode;

  /// 缓存断点更新间隔。
  final int aiInputCacheUpdateInterval;

  /// Anthropic cache breakpoint 最大数量 (1..4)。
  final int aiInputCacheBreakpointCount;

  /// 用户自定义的历史消息候选点位置（百分比 0..1，升序）。
  /// 空列表 = 沿用 mode-based 自动布点。
  final List<double> aiInputCacheBreakpointPositions;
  final bool memoryEnabled;
  final List<UserMemoryEntry> memoryEntries;

  /// 当前会话的线程模板 ID，用于限定 `skill_manager` 等模板专用内置工具。
  final String templateId;
  final int singleRoundToolCallLimit;
  final int sequentialToolRoundLimit;

  /// 会话错误记录保留上限。
  final int maxRecentErrors;

  /// plan_history 保留上限。
  final int maxPlanHistoryEntries;

  /// 超长响应被截断后的自动续接轮次上限。
  final int maxTruncationContinuations;

  /// token 估算系数（每个 token 的平均字符数）。
  final int estimatedCharactersPerToken;

  /// 工具输出字符上限，超出后截断。
  final int maxToolOutputChars;

  /// 写命令确认超时（毫秒）。
  final int writeConfirmationTimeoutMs;

  /// 快速路径写命令的静态分析阈值（命令字符数）。
  final int fastPathWriteAnalysisThreshold;

  /// Hook 文本输出字符上限。
  final int maxHookTextCharacters;

  /// 子进程优雅退出等待窗口（毫秒）。
  final int subprocessGracefulShutdownMs;

  /// 单次 Bash 调用的标准输出与标准错误合并捕获上限。
  final int bashOutputMaxBytes;

  /// 同会话并发派发工具调用上限。
  final int maxConcurrentTools;

  /// 附件图片解码最大边长（像素）。
  final int attachmentMaxInlineImageDimension;

  /// 附件文本原始字节读取上限。
  final int attachmentMaxTextRawBytes;

  /// 附件 PDF 原始字节读取上限。
  final int attachmentMaxPdfRawBytes;

  /// 附件图片原始字节读取上限。
  final int attachmentMaxImageRawBytes;

  /// 聊天流式行缓冲字节上限。
  final int chatMaxStreamLineBufferBytes;

  /// 备用标题的字符上限。
  final int fallbackTitleMaxCharacters;

  /// 生成标题的字符上限。
  final int generatedTitleMaxCharacters;

  /// 有效标题的最少字符数。
  final int minimumMeaningfulTitleCharacters;

  /// 有效拉丁文标题的最少单词数。
  final int minimumMeaningfulLatinTitleWords;

  /// 技能内容字符上限。
  final int maxSkillContentLength;

  /// 工作区指令文档字符上限。
  final int maxWorkspaceDocumentCharacters;

  /// 单张附件图片的字节上限，超限图片在持久化和打开编辑器前自动压缩。
  final int imageSizeLimitBytes;
  final bool writeCommandConfirmationEnabled;

  /// AI 请求的 HTTP 连接与发送超时（秒）。
  final int connectTimeoutSeconds;

  /// 非流式 AI 请求的响应超时（秒）。
  final int responseTimeoutSeconds;

  /// 流式 AI 请求的分块空闲超时（秒）。
  final int streamIdleTimeoutSeconds;

  /// 流式输出节流：每秒最多向当前流式卡片追加渲染的用户感知字符数。
  /// 0 表示关闭节流，>0 时使用令牌桶限速。
  final int streamMaxCharsPerSecond;

  /// 每秒最多向当前会话追加渲染的新消息卡片数。
  /// 0 表示关闭节流。
  final int streamMaxMessageCardsPerSecond;

  /// 全局节流总开关（false 时上述速率全部强制为 0）。
  final bool streamThrottleEnabled;

  /// 自动模式（true 时按平台预设，覆盖手动配置）。
  final bool streamThrottleAutoMode;

  /// 节流持续时长（秒）。0 = 持续节流；>0 时该时长后剩余流式
  /// 响应直接按真实接收节奏追加。
  final int streamThrottleDurationSeconds;

  /// 返回生效的字符节流速率。
  int effectiveStreamMaxCharsPerSecond() {
    if (!streamThrottleEnabled) return 0;
    return streamMaxCharsPerSecond;
  }

  /// 返回生效的卡片节流速率。语义同 [effectiveStreamMaxCharsPerSecond]。
  int effectiveStreamMaxMessageCardsPerSecond() {
    if (!streamThrottleEnabled) return 0;
    return streamMaxMessageCardsPerSecond;
  }

  /// 是否自动生成会话标题。
  final bool autoTitleEnabled;

  /// 首个文本轮次的自动标题调度方式。
  final AiAutoTitleFetchMode autoTitleFetchMode;

  /// 线程会话标题获取最大重试次数。
  final int autoTitleMaxRetryCount;

  /// 是否开启遥测调试模式，开启后在消息元数据中记录请求响应信息。
  final bool telemetryDebugEnabled;

  /// 是否在遥测数据中持久化 AI 原始响应体。
  final bool telemetryCaptureRawPayload;

  /// 是否在消息元数据中记录进程环境、工作目录和平台信息。
  /// 环境变量可能包含密钥，因此默认关闭。
  final bool telemetryCaptureEnvironment;

  /// 每条消息持久化的遥测载荷字符上限。
  final int telemetryMaxPayloadChars;
  final String platformName;
  final String workingDirectory;
  final String todayLocalDate;
  final String timeZoneName;
  final AiRepositorySnapshot? repositorySnapshot;
  final List<AiAllowCommandRule> allowCommandRules;
  final AiSandboxSettings sandboxSettings;
  final List<LocalSkill> availableSkills;
  final List<WorkflowDefinition> availableWorkflows;
  final List<McpServer> availableMcpServers;
  final List<AiDingTalkDwsCommand> availableDingTalkDwsCommands;
  final Map<String, McpToolCatalog> mcpToolCatalogsByServerName;

  /// MCP 工具懒加载模式（disabled / auto / enabled）。
  final McpLazyLoadingMode mcpLazyLoadingMode;

  /// auto 模式下的 token 阈值：当所有 MCP 工具描述估算 token
  /// 总量超过此值时则启用懒加载。默认值保持偏保守，优先降低反复发送
  /// 大工具目录造成的上下文成本与缓存失效风险。
  final int mcpLazyLoadingThresholdTokens;
  final AiBuiltinToolLazyLoadingMode builtinToolLazyLoadingMode;
  final List<AiBuiltinToolConfig> builtinToolConfigs;
  final List<AiWorkspaceInstructionDocument> workspaceInstructionDocuments;

  /// 【指令】模块注入。包含全部指令（含禁用），prompt
  /// builder 会只拼装 enabled 且不在 [skippedInstructionIds] 中的条目。
  final List<UserInstructionEntry> userInstructions;

  /// 本轮临时跳过的指令 ID 集合（UI从输入框胶囊上点击 X 产生）。
  final Set<String> skippedInstructionIds;

  /// 注入到每次工具执行的附加元数据，用于来源侧运行时策略。
  final Map<String, Object?> toolExecutionMetadata;

  Map<String, Object?> toJson() {
    final serializableToolExecutionMetadata = <String, Object?>{
      for (final entry in toolExecutionMetadata.entries)
        if (entry.value is! Function) entry.key: entry.value,
    };
    return <String, Object?>{
      'locale_tag': localeTag,
      'app_version': appVersion,
      'app_build_number': appBuildNumber,
      'application_directory': OpenHandPaths.applicationDirectoryPath(),
      'home_directory': OpenHandPaths.homeDirectoryPath(),
      'settings_file_path': settingsFilePath,
      'skills_storage_path': skillsStoragePath,
      'mcp_servers_file_path': mcpServersFilePath,
      'user_memory_file_path': userMemoryFilePath,
      'sessions_directory_path': OpenHandPaths.defaultSessionsDirectoryPath(),
      'compression_threshold_chars': compressionThresholdChars,
      'tool_result_compression_threshold_chars':
          toolResultCompressionThresholdChars,
      'tool_result_compression_enabled': toolResultCompressionEnabled,
      'micro_compression_enabled': microCompressionEnabled,
      'message_content_format': messageContentFormat.storageKey,
      'html_render_fallback': htmlRenderFallback.storageKey,
      'html_content_richness': htmlContentRichness.storageKey,
      'app_theme_brightness': appThemeBrightness,
      'app_theme_preset_name': appThemePresetName,
      'app_theme_primary_color': appThemePrimaryColor,
      'tool_result_compression_head_tail_window_chars':
          toolResultCompressionHeadTailWindowChars,
      'tool_result_compression_max_path_hits': toolResultCompressionMaxPathHits,
      'write_tool_summary_max_chars': writeToolSummaryMaxChars,
      'ai_input_cache_enabled': aiInputCacheEnabled,
      'ai_input_cache_update_mode': aiInputCacheUpdateMode,
      'ai_input_cache_update_interval': aiInputCacheUpdateInterval,
      'ai_input_cache_breakpoint_count': aiInputCacheBreakpointCount,
      'ai_input_cache_breakpoint_positions': aiInputCacheBreakpointPositions,
      'single_round_tool_call_limit': normalizeSingleRoundToolCallLimit(
        singleRoundToolCallLimit,
      ),
      'sequential_tool_round_limit': normalizeSequentialToolRoundLimit(
        sequentialToolRoundLimit,
      ),
      'max_recent_errors': maxRecentErrors,
      'max_plan_history_entries': maxPlanHistoryEntries,
      'max_truncation_continuations': maxTruncationContinuations,
      'estimated_characters_per_token': estimatedCharactersPerToken,
      'max_tool_output_chars': normalizeMaxToolOutputChars(maxToolOutputChars),
      'write_confirmation_timeout_ms': normalizeWriteConfirmationTimeoutMs(
        writeConfirmationTimeoutMs,
      ),
      'fast_path_write_analysis_threshold':
          normalizeFastPathWriteAnalysisThreshold(
            fastPathWriteAnalysisThreshold,
          ),
      'max_hook_text_characters': normalizeMaxHookTextCharacters(
        maxHookTextCharacters,
      ),
      'subprocess_graceful_shutdown_ms': normalizeSubprocessGracefulShutdownMs(
        subprocessGracefulShutdownMs,
      ),
      'bash_output_max_bytes': normalizeBashOutputMaxBytes(bashOutputMaxBytes),
      'max_concurrent_tools': normalizeMaxConcurrentTools(maxConcurrentTools),
      'attachment_max_inline_image_dimension':
          attachmentMaxInlineImageDimension,
      'attachment_max_text_raw_bytes': attachmentMaxTextRawBytes,
      'attachment_max_pdf_raw_bytes': attachmentMaxPdfRawBytes,
      'attachment_max_image_raw_bytes': attachmentMaxImageRawBytes,
      'chat_max_stream_line_buffer_bytes': chatMaxStreamLineBufferBytes,
      'fallback_title_max_characters': fallbackTitleMaxCharacters,
      'generated_title_max_characters': generatedTitleMaxCharacters,
      'auto_title_fetch_mode': autoTitleFetchMode.storageValue,
      'minimum_meaningful_title_characters': minimumMeaningfulTitleCharacters,
      'minimum_meaningful_latin_title_words': minimumMeaningfulLatinTitleWords,
      'max_skill_content_length': maxSkillContentLength,
      'max_workspace_document_characters': maxWorkspaceDocumentCharacters,
      'image_size_limit_bytes': imageSizeLimitBytes,
      'write_command_confirmation_enabled': writeCommandConfirmationEnabled,
      'platform_name': platformName,
      'working_directory': workingDirectory,
      'today_local_date': todayLocalDate,
      'time_zone_name': timeZoneName,
      'memory_enabled': memoryEnabled,
      'memory_entry_count': memoryEntries.length,
      'available_skill_count': availableSkills.length,
      'available_skill_names': availableSkills
          .map((item) => item.name)
          .toList(growable: false),
      'available_workflow_count': availableWorkflows.length,
      'available_workflow_names': availableWorkflows
          .where((item) => item.enabled)
          .map((item) => item.name)
          .toList(growable: false),
      'allow_command_rule_count': allowCommandRules.length,
      'allow_command_patterns': allowCommandRules
          .map((item) => item.pattern)
          .toList(growable: false),
      'allow_command_rules': allowCommandRules
          .map((item) => item.toJson())
          .toList(growable: false),
      'sandbox': sandboxSettings.toJson(),
      'available_mcp_server_count': availableMcpServers.length,
      'available_mcp_server_names': availableMcpServers
          .map((item) => item.name)
          .toList(growable: false),
      'available_dingtalk_dws_command_count':
          availableDingTalkDwsCommands.length,
      'mcp_tool_catalog_snapshot_count': mcpToolCatalogsByServerName.length,
      'mcp_tool_catalog_ready_count': mcpToolCatalogsByServerName.values
          .where((catalog) => catalog.status == McpToolCatalogStatus.ready)
          .length,
      'mcp_lazy_loading_mode': mcpLazyLoadingMode.storageValue,
      'mcp_lazy_loading_threshold_tokens': mcpLazyLoadingThresholdTokens,
      'builtin_tool_lazy_loading_mode': builtinToolLazyLoadingMode.storageValue,
      'workspace_instruction_document_count':
          workspaceInstructionDocuments.length,
      'workspace_instruction_documents': workspaceInstructionDocuments
          .map((item) => item.toJson())
          .toList(growable: false),
      if (serializableToolExecutionMetadata.isNotEmpty)
        'tool_execution_metadata': serializableToolExecutionMetadata,
      'repository_snapshot': repositorySnapshot?.toJson(),
    };
  }
}

import '../../../app/support/openhand_paths.dart';
import '../../instructions/index.dart';
import '../../mcp/model/mcp_lazy_loading_mode.dart';
import '../../mcp/model/mcp_server.dart';
import '../../mcp/model/mcp_tool.dart';
import '../../memory/model/user_memory_entry.dart';
import '../../skills/model/local_skill.dart';
import 'ai_allow_command_rule.dart';
import 'ai_builtin_tool_config.dart';
import 'ai_deny_command_rule.dart';
import 'ai_sandbox_settings.dart';

class AiRepositorySnapshot {
  factory AiRepositorySnapshot.fromJson(Map<String, Object?> json) {
    final recentCommitsValue = json['recent_commits'];
    return AiRepositorySnapshot(
      workingDirectory: '${json['working_directory'] ?? ''}',
      isGitRepository: json['is_git_repository'] == true,
      repositoryRootPath: '${json['repository_root_path'] ?? ''}',
      currentBranch: '${json['current_branch'] ?? ''}',
      mainBranch: '${json['main_branch'] ?? ''}',
      statusSnapshot: '${json['status_snapshot'] ?? ''}',
      recentCommits: recentCommitsValue is List
          ? recentCommitsValue
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
      capturedAtIso8601: '${json['captured_at'] ?? ''}',
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
  const AiSessionRuntimeContext({
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
    this.toolResultCompressionHeadTailWindowChars = 256,
    this.toolResultCompressionMaxPathHits = 12,
    this.writeToolSummaryMaxChars = 280,
    this.aiInputCacheEnabled = false,
    this.aiInputCacheUpdateMode = 'allMessages',
    this.aiInputCacheUpdateInterval = 10,
    this.aiInputCacheBreakpointCount = 4,
    this.aiInputCacheBreakpointPositions = const <double>[],
    required this.memoryEnabled,
    required this.memoryEntries,
    this.templateId = '',
    this.singleRoundToolCallLimit = 40,
    this.sequentialToolRoundLimit = 24,
    this.maxRecentErrors = 20,
    this.maxPlanHistoryEntries = 20,
    this.maxTruncationContinuations = 5,
    this.estimatedCharactersPerToken = 4,
    this.maxToolOutputChars = 200000,
    this.writeConfirmationTimeoutMs = 300000,
    this.fastPathWriteAnalysisThreshold = 512,
    this.maxHookTextCharacters = 4000,
    this.subprocessGracefulShutdownMs = 500,
    this.bashOutputMaxBytes = 200000,
    this.maxConcurrentTools = 8,
    this.webFetchMaxResponseBytes = 1024 * 1024,
    this.webFetchMaxRedirects = 5,
    this.webFetchMaxCacheEntries = 64,
    this.attachmentMaxInlineImageDimension = 1568,
    this.attachmentMaxTextRawBytes = 2 * 1024 * 1024,
    this.attachmentMaxPdfRawBytes = 2 * 1024 * 1024,
    this.attachmentMaxImageRawBytes = 50 * 1024 * 1024,
    this.chatMaxStreamLineBufferBytes = 4 * 1024 * 1024,
    this.fallbackTitleMaxCharacters = 20,
    this.generatedTitleMaxCharacters = 20,
    this.minimumMeaningfulTitleCharacters = 4,
    this.minimumMeaningfulLatinTitleWords = 2,
    this.maxSkillContentLength = 100000,
    this.maxWorkspaceDocumentCharacters = 16000,
    this.imageSizeLimitBytes = 1024 * 1024,
    this.writeCommandConfirmationEnabled = true,
    this.connectTimeoutSeconds = 60,
    this.responseTimeoutSeconds = 120,
    this.streamIdleTimeoutSeconds = 120,
    this.autoTitleEnabled = true,
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
    this.availableMcpServers = const <McpServer>[],
    this.mcpToolCatalogsByServerName = const <String, McpToolCatalog>{},
    this.mcpLazyLoadingMode = McpLazyLoadingMode.auto,
    this.mcpLazyLoadingThresholdTokens = 80000,
    this.builtinToolConfigs = const <AiBuiltinToolConfig>[],
    this.workspaceInstructionDocuments =
        const <AiWorkspaceInstructionDocument>[],
    this.userInstructions = const <UserInstructionEntry>[],
    this.skippedInstructionIds = const <String>{},
  }) : sandboxSettings =
           sandboxSettings ??
           const AiSandboxSettings(
             enabled: false,
             failIfUnavailable: true,
             allowUnsandboxedCommands: false,
             autoAllowBashIfSandboxed: false,
             sandboxedBuiltinTools: <String>[],
             filesystemRules: <AiSandboxFileRule>[
               AiSandboxFileRule(
                 id: 'default-openhand-ro',
                 path: '.openhand',
                 accessMode: AiSandboxFileAccessMode.readOnly,
                 matchMode: AiDenyCommandMatchMode.simple,
                 note: 'OpenHand workspace metadata is read-only by default.',
               ),
             ],
             excludedCommands: <AiSandboxPatternRule>[],
             allowedDomains: <AiSandboxPatternRule>[],
             deniedDomains: <AiSandboxPatternRule>[],
             httpProxyPort: 0,
             socksProxyPort: 0,
             allowNetworkWhenNoDomainRules: true,
           );

  final String localeTag;
  final String appVersion;
  final String appBuildNumber;
  final String settingsFilePath;
  final String skillsStoragePath;
  final String mcpServersFilePath;
  final String userMemoryFilePath;
  final int compressionThresholdChars;

  /// 2026-04-27 — 工具调用输出进入 conversation history 前的字符上限。
  /// prompt builder 会依该阈值压缩 raw 过长的工具返回。
  final int toolResultCompressionThresholdChars;

  /// 2026-04-27 — 工具调用输出压缩总开关。关闭后返回原始内容。
  final bool toolResultCompressionEnabled;

  /// 2026-04-27 — 压缩摘要首尾片段窗口长度（字符）。
  final int toolResultCompressionHeadTailWindowChars;

  /// 2026-04-27 — 压缩摘要中提取的文件路径条数上限。
  final int toolResultCompressionMaxPathHits;

  /// 2026-04-27 — 写类工具摘要中保留 result_text 的字符上限。
  final int writeToolSummaryMaxChars;

  /// 2026-05-01 — 是否启用输入缓存 (Anthropic prompt caching 等)。
  final bool aiInputCacheEnabled;

  /// 2026-05-01 — 缓存断点更新模式: allMessages / userMessages / tokens。
  final String aiInputCacheUpdateMode;

  /// 2026-05-01 — 缓存断点更新间隔。
  final int aiInputCacheUpdateInterval;

  /// 2026-05-01 — Anthropic cache breakpoint 最大数量 (1..4)。
  final int aiInputCacheBreakpointCount;

  /// 用户自定义的前 N-1 个静态缓存点位置（百分比 0..1，升序）。
  /// 空列表 = 沿用 mode-based 自动布点。
  final List<double> aiInputCacheBreakpointPositions;
  final bool memoryEnabled;
  final List<UserMemoryEntry> memoryEntries;

  /// Identifier of the thread template currently active for this session.
  /// Used by the tool runtime to scope template-specific builtins such as
  /// `skill_manager` (Hermes Talker only).
  final String templateId;
  final int singleRoundToolCallLimit;
  final int sequentialToolRoundLimit;

  /// Group A — 会话错误记录保留上限。
  final int maxRecentErrors;

  /// Group A — plan_history 保留上限。
  final int maxPlanHistoryEntries;

  /// Group A — 超长响应被截断后的自动续接轮次上限。
  final int maxTruncationContinuations;

  /// Group A — token 估算系数（每个 token 平均多少字符）。
  final int estimatedCharactersPerToken;

  /// Group B — 工具输出字符上限（超出截断）。
  final int maxToolOutputChars;

  /// Group B — 写命令确认超时（毫秒）。
  final int writeConfirmationTimeoutMs;

  /// Group B — Fast-path 写命令静态分析阈值（命令字符数）。
  final int fastPathWriteAnalysisThreshold;

  /// Group B — Hook 文本输出字符上限。
  final int maxHookTextCharacters;

  /// 2026-05 — 工具加固：子进程 graceful shutdown 等待窗口（毫秒）。
  final int subprocessGracefulShutdownMs;

  /// 2026-05 — 工具加固：单次 bash 调用 stdout+stderr 合并捕获上限。
  final int bashOutputMaxBytes;

  /// 2026-05 — 工具加固：同会话并发派发工具调用上限。
  final int maxConcurrentTools;

  /// Group C — WebFetch 单次响应字节上限。
  final int webFetchMaxResponseBytes;

  /// Group C — WebFetch 最大重定向次数。
  final int webFetchMaxRedirects;

  /// Group C — WebFetch 内存缓存条目上限。
  final int webFetchMaxCacheEntries;

  /// Group C — 附件图片解码最大边长（像素）。
  final int attachmentMaxInlineImageDimension;

  /// Group C — 附件文本原始字节读取上限。
  final int attachmentMaxTextRawBytes;

  /// Group C — 附件 PDF 原始字节读取上限。
  final int attachmentMaxPdfRawBytes;

  /// Group C — 附件图片原始字节读取上限。
  final int attachmentMaxImageRawBytes;

  /// Group C — Chat 流式行缓冲字节上限。
  final int chatMaxStreamLineBufferBytes;

  /// Group D — FallbackTitleMaxCharacters.
  final int fallbackTitleMaxCharacters;

  /// Group D — GeneratedTitleMaxCharacters.
  final int generatedTitleMaxCharacters;

  /// Group D — MinimumMeaningfulTitleCharacters.
  final int minimumMeaningfulTitleCharacters;

  /// Group D — MinimumMeaningfulLatinTitleWords.
  final int minimumMeaningfulLatinTitleWords;

  /// Group E — Skill 内容字符上限。
  final int maxSkillContentLength;

  /// Group E — 工作区指令文档字符上限。
  final int maxWorkspaceDocumentCharacters;

  /// Per-image attachment size cap (bytes). When the user picks an image
  /// larger than this value, the attachment pipeline auto-compresses it
  /// before persisting and before the editor opens.
  final int imageSizeLimitBytes;
  final bool writeCommandConfirmationEnabled;

  /// HTTP connection/send timeout for AI requests (seconds).
  final int connectTimeoutSeconds;

  /// Response timeout for non-streaming AI requests (seconds).
  final int responseTimeoutSeconds;

  /// Per-chunk stream idle timeout for streaming AI requests (seconds).
  final int streamIdleTimeoutSeconds;

  /// Whether to auto-generate session titles.
  final bool autoTitleEnabled;

  /// 线程会话标题获取最大重试次数。
  final int autoTitleMaxRetryCount;

  /// Whether telemetry debug mode is enabled (populates request/response
  /// metadata on messages for the audit dialogs).
  final bool telemetryDebugEnabled;

  /// Whether to persist the raw AI response body alongside other telemetry.
  final bool telemetryCaptureRawPayload;

  /// Whether to capture process environment variables, working directory
  /// and platform info into message metadata. Off by default because env
  /// vars can contain secrets.
  final bool telemetryCaptureEnvironment;

  /// Hard cap on how many characters of captured payload to persist per
  /// message to keep on-disk session files bounded.
  final int telemetryMaxPayloadChars;
  final String platformName;
  final String workingDirectory;
  final String todayLocalDate;
  final String timeZoneName;
  final AiRepositorySnapshot? repositorySnapshot;
  final List<AiAllowCommandRule> allowCommandRules;
  final AiSandboxSettings sandboxSettings;
  final List<LocalSkill> availableSkills;
  final List<McpServer> availableMcpServers;
  final Map<String, McpToolCatalog> mcpToolCatalogsByServerName;

  /// 2026-05-03 — MCP 工具懒加载模式（disabled / auto / enabled）。
  final McpLazyLoadingMode mcpLazyLoadingMode;

  /// 2026-05-03 — auto 模式下的 token 阈值：当所有 MCP 工具描述估算 token
  /// 总量超过此值时则启用懒加载。
  final int mcpLazyLoadingThresholdTokens;
  final List<AiBuiltinToolConfig> builtinToolConfigs;
  final List<AiWorkspaceInstructionDocument> workspaceInstructionDocuments;

  /// 2026-04-25 — 【指令】模块注入。包含全部指令（含禁用），prompt
  /// builder 会只拼装 enabled 且不在 [skippedInstructionIds] 中的条目。
  final List<UserInstructionEntry> userInstructions;

  /// 本轮临时跳过的指令 ID 集合（UI从输入框胶囊上点击 X 产生）。
  final Set<String> skippedInstructionIds;

  Map<String, Object?> toJson() {
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
      'tool_result_compression_head_tail_window_chars':
          toolResultCompressionHeadTailWindowChars,
      'tool_result_compression_max_path_hits': toolResultCompressionMaxPathHits,
      'write_tool_summary_max_chars': writeToolSummaryMaxChars,
      'ai_input_cache_enabled': aiInputCacheEnabled,
      'ai_input_cache_update_mode': aiInputCacheUpdateMode,
      'ai_input_cache_update_interval': aiInputCacheUpdateInterval,
      'ai_input_cache_breakpoint_count': aiInputCacheBreakpointCount,
      'ai_input_cache_breakpoint_positions': aiInputCacheBreakpointPositions,
      'single_round_tool_call_limit': singleRoundToolCallLimit,
      'sequential_tool_round_limit': sequentialToolRoundLimit,
      'max_recent_errors': maxRecentErrors,
      'max_plan_history_entries': maxPlanHistoryEntries,
      'max_truncation_continuations': maxTruncationContinuations,
      'estimated_characters_per_token': estimatedCharactersPerToken,
      'max_tool_output_chars': maxToolOutputChars,
      'write_confirmation_timeout_ms': writeConfirmationTimeoutMs,
      'fast_path_write_analysis_threshold': fastPathWriteAnalysisThreshold,
      'max_hook_text_characters': maxHookTextCharacters,
      'subprocess_graceful_shutdown_ms': subprocessGracefulShutdownMs,
      'bash_output_max_bytes': bashOutputMaxBytes,
      'max_concurrent_tools': maxConcurrentTools,
      'web_fetch_max_response_bytes': webFetchMaxResponseBytes,
      'web_fetch_max_redirects': webFetchMaxRedirects,
      'web_fetch_max_cache_entries': webFetchMaxCacheEntries,
      'attachment_max_inline_image_dimension':
          attachmentMaxInlineImageDimension,
      'attachment_max_text_raw_bytes': attachmentMaxTextRawBytes,
      'attachment_max_pdf_raw_bytes': attachmentMaxPdfRawBytes,
      'attachment_max_image_raw_bytes': attachmentMaxImageRawBytes,
      'chat_max_stream_line_buffer_bytes': chatMaxStreamLineBufferBytes,
      'fallback_title_max_characters': fallbackTitleMaxCharacters,
      'generated_title_max_characters': generatedTitleMaxCharacters,
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
      'mcp_tool_catalog_snapshot_count': mcpToolCatalogsByServerName.length,
      'mcp_tool_catalog_ready_count': mcpToolCatalogsByServerName.values
          .where((catalog) => catalog.status == McpToolCatalogStatus.ready)
          .length,
      'mcp_lazy_loading_mode': mcpLazyLoadingMode.storageValue,
      'mcp_lazy_loading_threshold_tokens': mcpLazyLoadingThresholdTokens,
      'workspace_instruction_document_count':
          workspaceInstructionDocuments.length,
      'workspace_instruction_documents': workspaceInstructionDocuments
          .map((item) => item.toJson())
          .toList(growable: false),
      'repository_snapshot': repositorySnapshot?.toJson(),
    };
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/model/dingtalk_multimodal_capability.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/lifecycle_cache.dart';
import '../../../../shared/util/path_safety.dart';
import '../../../../shared/util/physical_path_safety.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../../../shared/util/tool_name_normalization.dart';
import '../../../agents/index.dart';
import '../../../instructions/instructions_controller.dart';
import '../../../knowledge_base/knowledge_base_controller.dart';
import '../../../machine_terminal/index.dart';
import '../../../mcp/index.dart';
import '../../../memory/index.dart';
import '../../../skills/index.dart';
import '../../model/ai_builtin_tool_config.dart';
import '../../model/ai_deny_command_rule.dart';
import '../../model/ai_dingtalk_dws_command.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_session_runtime_context.dart';
import '../../tools/ai_tool_registry.dart';
import '../../tools/ai_tool_utils.dart';
import '../../tools/memory/ai_memory_tool.dart';
import '../../tools/web_reverse_cdp_first_guard.dart';
import '../bash/ai_bash_tool_service.dart';
import '../chat/ai_chat_service.dart';
import '../chat/ai_protocol_adapter.dart';
import '../fs/ai_file_history_service.dart';
import '../fs/ai_file_mutation_ledger.dart';
import '../fs/ai_file_tracker_service.dart';
import '../hook/ai_claude_hook_service.dart';
import '../prompt/ai_prompt_template_assembly.dart';
import '../web_fetch/web_fetch_scrapling_bridge.dart';
import 'ai_plan_mode_guidance.dart';
import 'ai_tool_execution_registry.dart';

enum AiRuntimeToolSource { builtin, mcp, skill }

const int _maxPostHocLedgerCaptureBytes = 16 * kBytesPerMiB;
const int _maxSkillLinkedResources = 32;
const int _maxSkillLinkedDirectoryEntries = 256;
const Duration _skillLinkedResourcePathCheckTimeout = Duration(seconds: 2);
const int _maxSessionFileTrackers = 128;
const int _maxConcurrentToolExecutions = kOpenHandMaxAsyncConcurrency;
const int _maxQueuedToolExecutions = 256;
const Duration _toolExecutionQueueTimeout = Duration(seconds: 30);
const int _minToolOutputTruncationPayloadChars = 40;
const int kAiTaskDescriptionMaxCharacters = 512;
const int kAiTaskPromptMaxCharacters = 120000;
const int kAiToolSearchMaxQueryCharacters = 4 * kBytesPerKiB;
const int kAiKnowledgeSearchMaxQueryCharacters = 2000;
const int kAiKnowledgeSearchMaxSourceIds = 32;
const int kAiKnowledgeSearchMaxTags = 32;
const int kAiKnowledgeTagMaxCharacters = 128;
const int kAiKnowledgeIdMaxCharacters = 256;
const String _toolResultsSubdirectoryName = 'tool-results';
const String _toolOutputTruncationStrategyHeadTail = 'head_tail';
const String _toolOutputRecoveryHintRerunNarrower = 'rerun_with_narrower_query';
const String _toolOutputRecoveryHintReadPersisted = 'read_persisted_output';
const String _toolOutputPersistenceFormatText = 'text';
const String _filePathResolvedAgainstCwdDescription =
    'The absolute or relative file path. Relative paths are resolved against the working directory.';

/// 数字员工选择器入参：三选一，与 [_agentToolAgentSelectorAnyOf] 配套。
const Map<String, Object?> _agentToolAgentSelectorProperties =
    <String, Object?>{
      'agent_id': <String, Object?>{'type': 'string'},
      'agent_name': <String, Object?>{'type': 'string'},
      'agent': <String, Object?>{
        'type': 'string',
        'description': 'Agent id or exact display name.',
      },
    };

/// 标签入参：labels 为正名，tags 为兼容别名。
const Map<String, Object?> _agentToolLabelProperties = <String, Object?>{
  'labels': <String, Object?>{
    'type': 'array',
    'items': <String, Object?>{'type': 'string'},
  },
  'tags': <String, Object?>{
    'type': 'array',
    'items': <String, Object?>{'type': 'string'},
    'description': 'Alias for labels.',
  },
};

const List<Object?> _agentToolAgentSelectorAnyOf = <Object?>[
  <String, Object?>{
    'required': <String>['agent_id'],
  },
  <String, Object?>{
    'required': <String>['agent_name'],
  },
  <String, Object?>{
    'required': <String>['agent'],
  },
];
const List<Object?> _agentToolTaskSelectorAnyOf = <Object?>[
  <String, Object?>{
    'required': <String>['task_id'],
  },
  <String, Object?>{
    'required': <String>['id'],
  },
];

/// 任务选择器入参：二选一，与 [_agentToolTaskSelectorAnyOf] 配套。
const Map<String, Object?> _agentToolTaskSelectorProperties = <String, Object?>{
  'task_id': <String, Object?>{'type': 'string'},
  'id': <String, Object?>{
    'type': 'string',
    'description': 'Alias for task_id.',
  },
};

/// 任务级工具的完整定位入参：数字员工三选一 + 任务标识二选一。
const Map<String, Object?> _agentToolAgentTaskSelectorProperties =
    <String, Object?>{
      ..._agentToolAgentSelectorProperties,
      ..._agentToolTaskSelectorProperties,
    };

/// 任务进度：归一化到 0~1。
const Map<String, Object?> _agentToolProgressSchema = <String, Object?>{
  'type': 'number',
  'minimum': 0,
  'maximum': 1,
};
const List<Object?> _agentToolAgentTaskAllOf = <Object?>[
  <String, Object?>{'anyOf': _agentToolAgentSelectorAnyOf},
  <String, Object?>{'anyOf': _agentToolTaskSelectorAnyOf},
];
const Map<String, Object?> _agentToolExtraSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': true,
};

class AiResolvedToolCatalog {
  const AiResolvedToolCatalog({
    required this.definitions,
    required this.toolsByName,
    this.notices = const <String>[],
    this.mcpServerInstructionsByName = const <String, String>{},
  });

  final List<AiToolDefinition> definitions;
  final Map<String, AiResolvedTool> toolsByName;
  final List<String> notices;
  final Map<String, String> mcpServerInstructionsByName;

  AiResolvedTool? find(String name) {
    final direct = toolsByName[name];
    if (direct != null) {
      return direct;
    }
    final normalizedName = normalizeAsciiLookupKey(name);
    if (normalizedName.isEmpty) {
      return null;
    }
    for (final entry in toolsByName.entries) {
      if (normalizeAsciiLookupKey(entry.key) == normalizedName) {
        return entry.value;
      }
    }
    final aliasKind = _builtinAliasKind(normalizedName);
    if (aliasKind != null) {
      for (final tool in toolsByName.values) {
        if (tool.source == AiRuntimeToolSource.builtin &&
            tool.builtinKind == aliasKind) {
          return tool;
        }
      }
    }
    return null;
  }

  AiResolvedTool? findDeferredTool(String name) {
    final normalizedName = normalizeAsciiLookupKey(name);
    if (normalizedName.isEmpty) return null;
    for (final tool in toolsByName.values) {
      if (tool.builtinKind != AiBuiltinToolKind.toolSearch &&
          tool.builtinKind != AiBuiltinToolKind.dingTalkToolSearch) {
        continue;
      }
      final direct = tool.toolSearchDeferredTools[name];
      if (direct != null) return direct;
      for (final entry in tool.toolSearchDeferredTools.entries) {
        if (normalizeAsciiLookupKey(entry.key) == normalizedName ||
            normalizeAsciiLookupKey(entry.value.name) == normalizedName ||
            normalizeAsciiLookupKey(entry.value.definition.name) ==
                normalizedName) {
          return entry.value;
        }
      }
    }
    return null;
  }

  static AiBuiltinToolKind? _builtinAliasKind(String normalizedName) {
    return switch (normalizedName) {
      'agent' => AiBuiltinToolKind.task,
      'bashoutputtool' || 'agentoutputtool' => AiBuiltinToolKind.taskOutput,
      'killshell' => AiBuiltinToolKind.taskStop,
      'askuserquestion' => AiBuiltinToolKind.askUserChoice,
      _ => null,
    };
  }
}

class AiResolvedTool {
  const AiResolvedTool({
    required this.name,
    required this.definition,
    required this.source,
    this.builtinKind,
    this.mcpServer,
    this.mcpTool,
    this.skill,
    this.builtinConfig,
    this.toolSearchDeferredToolDefinitions = const <String, AiToolDefinition>{},
    this.toolSearchDeferredTools = const <String, AiResolvedTool>{},
    this.dingtalkDwsCommand,
    this.dingtalkDwsCommands = const <AiDingTalkDwsCommand>[],
  });

  final String name;
  final AiToolDefinition definition;
  final AiRuntimeToolSource source;
  final AiBuiltinToolKind? builtinKind;
  final McpServer? mcpServer;
  final McpTool? mcpTool;
  final LocalSkill? skill;

  /// 用户层面的内建工具配置（仅 builtin 来源）。携带 timeout / retry 等
  /// 运行时策略；execute() 据此包裹超时与重试逻辑。
  final AiBuiltinToolConfig? builtinConfig;

  /// 当前目录中由 ToolSearch 使用的延迟工具定义快照。
  final Map<String, AiToolDefinition> toolSearchDeferredToolDefinitions;

  /// 以可调用名称索引的延迟工具完整元数据。
  final Map<String, AiResolvedTool> toolSearchDeferredTools;
  final AiDingTalkDwsCommand? dingtalkDwsCommand;
  final List<AiDingTalkDwsCommand> dingtalkDwsCommands;

  AiResolvedTool withToolSearchDeferredTools({
    required Map<String, AiToolDefinition> definitions,
    required Map<String, AiResolvedTool> tools,
  }) {
    return AiResolvedTool(
      name: name,
      definition: definition,
      source: source,
      builtinKind: builtinKind,
      mcpServer: mcpServer,
      mcpTool: mcpTool,
      skill: skill,
      builtinConfig: builtinConfig,
      dingtalkDwsCommand: dingtalkDwsCommand,
      dingtalkDwsCommands: dingtalkDwsCommands,
      toolSearchDeferredToolDefinitions:
          Map<String, AiToolDefinition>.unmodifiable(definitions),
      toolSearchDeferredTools: Map<String, AiResolvedTool>.unmodifiable(tools),
    );
  }
}

enum AiBuiltinToolKind {
  task,
  bash,
  bashBackground,
  taskOutput,
  taskStop,
  glob,
  grep,
  ls,
  exitPlanMode,
  read,
  edit,
  multiEdit,
  applyFileDiffs,
  write,
  notebookEdit,
  webFetch,
  todoWrite,
  webSearch,
  lsp,
  codebaseSearch,
  git,
  deleteFile,
  readLints,
  askUserChoice,
  skillManager,
  toolSearch,
  memory,
  knowledgeSearch,
  knowledgeRead,
  agentList,
  agentDetail,
  agentActivityLog,
  agentAuditReport,
  agentAuditRecord,
  agentApprovalRequest,
  agentKpiUpsert,
  agentResourceUpdate,
  agentClusterConfigure,
  agentClusterStatus,
  agentTaskList,
  agentTaskPublish,
  agentTaskTrack,
  agentTaskProgress,
  agentTaskCancel,
  agentTaskPause,
  agentTaskTerminate,
  agentTaskResume,
  agentTaskComplete,
  agentTaskResult,
  machineTerminalRead,
  machineTerminalWrite,
  machineTerminalExec,
  machineTerminalControl,
  dingTalkToolSearch,
  dingtalkDws,
  dingtalkImageGeneration,
  dingtalkVideoGeneration,
  dingtalkAudioGeneration,
}

class AiToolExecutionResult {
  factory AiToolExecutionResult.fromBash(
    BashToolExecutionResult result, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiToolExecutionResult(
      status: result.status,
      command: result.command,
      workingDirectory: result.workingDirectory,
      stdout: result.stdout,
      stderr: result.stderr,
      durationMs: result.durationMs,
      exitCode: result.exitCode,
      matchedRuleId: result.matchedRuleId,
      matchedRulePattern: result.matchedRulePattern,
      isWriteCommand: result.isWriteCommand,
      writeAnalysisReason: result.writeAnalysisReason,
      resultText: result.toToolOutput(),
      metadata: <String, Object?>{
        ...result.sandboxMetadata,
        ...result.metadata,
        ...metadata,
      },
    );
  }
  const AiToolExecutionResult({
    required this.status,
    required this.command,
    required this.workingDirectory,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    required this.resultText,
    this.exitCode,
    this.matchedRuleId,
    this.matchedRulePattern,
    this.isWriteCommand = false,
    this.writeAnalysisReason = '',
    this.metadata = const <String, Object?>{},
  });

  final BashToolExecutionStatus status;
  final String command;
  final String workingDirectory;
  final String stdout;
  final String stderr;
  final int durationMs;
  final String resultText;
  final int? exitCode;
  final String? matchedRuleId;
  final String? matchedRulePattern;
  final bool isWriteCommand;
  final String writeAnalysisReason;
  final Map<String, Object?> metadata;

  /// 按需替换若干字段，其余原样保留。
  ///
  /// 截断输出、补记文件变更、合并元数据这几处此前各自手抄一遍十三个字段的
  /// 构造调用：漏抄一个字段就是静默丢数据，新增字段还得逐处补齐。
  AiToolExecutionResult copyWith({
    String? stdout,
    String? stderr,
    String? resultText,
    Map<String, Object?>? metadata,
  }) {
    return AiToolExecutionResult(
      status: status,
      command: command,
      workingDirectory: workingDirectory,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      durationMs: durationMs,
      resultText: resultText ?? this.resultText,
      exitCode: exitCode,
      matchedRuleId: matchedRuleId,
      matchedRulePattern: matchedRulePattern,
      isWriteCommand: isWriteCommand,
      writeAnalysisReason: writeAnalysisReason,
      metadata: metadata ?? this.metadata,
    );
  }

  String toToolOutput() => nullIfBlank(resultText) ?? '';
}

class _PersistedToolOutput {
  const _PersistedToolOutput({required this.path, required this.originalChars});

  final String path;
  final int originalChars;
}

/// 工具目录装配过程中的可变累积体。
///
/// 收敛「实时探测」与「运行时快照」两条装配路径的注册去重、提示汇总与
/// MCP 服务端说明收集，保证两者产出的目录结构完全一致。
class _ToolCatalogBuilder {
  final List<AiToolDefinition> definitions = <AiToolDefinition>[];
  final Map<String, AiResolvedTool> toolsByName = <String, AiResolvedTool>{};
  final Set<String> reservedToolNames = <String>{};
  final List<String> notices = <String>[];
  final Map<String, String> mcpServerInstructionsByName = <String, String>{};

  /// 同名工具先到先得：高优先级来源先注册即可占位。
  void register(AiResolvedTool tool) {
    if (!reservedToolNames.add(tool.name)) return;
    toolsByName[tool.name] = tool;
    definitions.add(tool.definition);
  }

  void addServerNotice(String serverName, String message) {
    notices.add('MCP $serverName: $message');
  }

  AiResolvedToolCatalog build() {
    return AiResolvedToolCatalog(
      definitions: definitions,
      toolsByName: toolsByName,
      notices: notices,
      mcpServerInstructionsByName: mcpServerInstructionsByName,
    );
  }
}

class AiToolRuntimeService {
  AiToolRuntimeService({
    required AiBashToolService bashToolService,
    required AiClaudeHookService hookService,
    required McpToolDiscoveryService mcpToolService,
    required AiChatClient backgroundChatClient,
    http.Client? httpClient,
    Future<List<InternetAddress>> Function(String host)? hostLookup,
    AiFileHistoryService? fileHistoryService,
    AiFileMutationLedger? mutationLedger,
    String Function()? skillsDirProvider,
    MemoryControllerProvider? memoryControllerProvider,
    AgentsControllerProvider? agentsControllerProvider,
    InstructionsControllerProvider? instructionsControllerProvider,
    KnowledgeBaseController? Function()? knowledgeBaseControllerProvider,
    List<AiModelConfig> Function()? aiModelsProvider,
    MachineTerminalService? machineTerminalService,
    String Function(String sessionId)? toolOutputDirectoryProvider,
    AiSubToolExecutionObserver? subToolExecutionObserver,
  }) : _bashToolService = bashToolService,
       _hookService = hookService,
       _mcpToolService = mcpToolService,
       _backgroundChatClient = backgroundChatClient,
       _httpClient =
           httpClient ?? SystemProxyResolver.instance.createHttpClient(),
       _ownsHttpClient = httpClient == null,
       _scraplingBridge = WebFetchScraplingBridge(),
       _hostLookup = hostLookup ?? ((host) => InternetAddress.lookup(host)),
       _fileHistory = fileHistoryService ?? AiFileHistoryService(),
       _mutationLedger = mutationLedger ?? AiFileMutationLedger(),
       _agentsControllerProvider = agentsControllerProvider,
       _machineTerminalService = machineTerminalService,
       _subToolExecutionObserver = subToolExecutionObserver,
       _toolOutputDirectoryProvider = toolOutputDirectoryProvider {
    _toolRegistry = AiToolRegistry.withServiceDependencies(
      bashToolService: _bashToolService,
      hookService: _hookService,
      backgroundChatClient: _backgroundChatClient,
      httpClient: _httpClient,
      scraplingBridge: _scraplingBridge,
      hostLookup: _hostLookup,
      skillsDirProvider: skillsDirProvider,
      memoryControllerProvider: memoryControllerProvider,
      agentsControllerProvider: agentsControllerProvider,
      instructionsControllerProvider: instructionsControllerProvider,
      knowledgeBaseControllerProvider: knowledgeBaseControllerProvider,
      aiModelsProvider: aiModelsProvider,
      machineTerminalService: machineTerminalService,
      subToolExecutionObserver: _notifySubToolExecuted,
    );
  }

  static const Set<AiBuiltinToolKind> _nonRetryableSideEffectBuiltinKinds =
      <AiBuiltinToolKind>{
        AiBuiltinToolKind.task,
        AiBuiltinToolKind.bash,
        AiBuiltinToolKind.bashBackground,
        AiBuiltinToolKind.taskOutput,
        AiBuiltinToolKind.taskStop,
        AiBuiltinToolKind.machineTerminalWrite,
        AiBuiltinToolKind.machineTerminalExec,
        AiBuiltinToolKind.machineTerminalControl,
        AiBuiltinToolKind.dingtalkDws,
        AiBuiltinToolKind.dingtalkImageGeneration,
        AiBuiltinToolKind.dingtalkVideoGeneration,
        AiBuiltinToolKind.dingtalkAudioGeneration,
        AiBuiltinToolKind.edit,
        AiBuiltinToolKind.multiEdit,
        AiBuiltinToolKind.applyFileDiffs,
        AiBuiltinToolKind.write,
        AiBuiltinToolKind.notebookEdit,
        AiBuiltinToolKind.deleteFile,
        AiBuiltinToolKind.skillManager,
        AiBuiltinToolKind.agentAuditRecord,
        AiBuiltinToolKind.agentApprovalRequest,
        AiBuiltinToolKind.agentKpiUpsert,
        AiBuiltinToolKind.agentResourceUpdate,
        AiBuiltinToolKind.agentClusterConfigure,
        AiBuiltinToolKind.agentTaskPublish,
        AiBuiltinToolKind.agentTaskCancel,
        AiBuiltinToolKind.agentTaskPause,
        AiBuiltinToolKind.agentTaskTerminate,
        AiBuiltinToolKind.agentTaskResume,
        AiBuiltinToolKind.agentTaskComplete,
      };
  static final RegExp _unsafeToolOutputStorageCharsPattern = RegExp(
    r'[^A-Za-z0-9_.-]+',
  );
  static final RegExp _cdpIdentityTokenPattern = RegExp(
    r'(^|[^a-z0-9])cdp([^a-z0-9]|$)',
  );
  static final RegExp _markdownLinkTargetPattern = RegExp(
    r'\[[^\]]+\]\(([^)]+)\)',
    multiLine: true,
  );

  final AiBashToolService _bashToolService;
  final AiClaudeHookService _hookService;
  final McpToolDiscoveryService _mcpToolService;
  final AiChatClient _backgroundChatClient;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final WebFetchScraplingBridge _scraplingBridge;
  final Future<List<InternetAddress>> Function(String host) _hostLookup;
  late final AiToolRegistry _toolRegistry;

  /// 暴露给 [AiSessionController]，用于同步需要随设置变化更新的工具实例。
  AiToolRegistry get toolRegistry => _toolRegistry;

  // 文件追踪和历史版本服务
  final LifecycleLruCache<AiFileTrackerService> _fileTrackers =
      LifecycleLruCache<AiFileTrackerService>(
        maxEntries: _maxSessionFileTrackers,
      );
  final AiFileHistoryService _fileHistory;
  final AiFileMutationLedger _mutationLedger;
  final AgentsControllerProvider? _agentsControllerProvider;
  final MachineTerminalService? _machineTerminalService;
  AiSubToolExecutionObserver? _subToolExecutionObserver;
  final String Function(String sessionId)? _toolOutputDirectoryProvider;
  final OpenHandAsyncSemaphore _executionSlots = OpenHandAsyncSemaphore(
    _maxConcurrentToolExecutions,
    maxWaiters: _maxQueuedToolExecutions,
  );
  final Set<Completer<void>> _activeExecutionAborts = <Completer<void>>{};
  Future<void>? _shutdownFuture;
  bool _isShuttingDown = false;

  void configureSubToolExecutionObserver(AiSubToolExecutionObserver? observer) {
    if (_isShuttingDown) return;
    _subToolExecutionObserver = observer;
  }

  Future<void> _notifySubToolExecuted(
    AiToolExecutionContext parentContext,
    AiToolExecutionContext subContext,
    AiToolExecutionResult result,
  ) async {
    final observer = _subToolExecutionObserver;
    if (observer != null) {
      await observer(parentContext, subContext, result);
    }
  }

  AiFileTrackerService _fileTrackerForSession(String sessionId) {
    return _fileTrackers.putIfAbsent(sessionId, AiFileTrackerService.new);
  }

  void clearSessionReadResultTracking(String sessionId) {
    _fileTrackers.get(sessionId)?.clearReadResultTracking();
  }

  void removeSessionFileTracking(String sessionId) {
    _fileTrackers.remove(sessionId);
  }

  void pruneSessionFileTracking(Set<String> liveSessionIds) {
    _fileTrackers.removeWhere(
      (sessionId, _) => !liveSessionIds.contains(sessionId),
    );
  }

  /// 获取文件历史服务（供外部访问，如回滚功能）
  AiFileHistoryService get fileHistory => _fileHistory;

  /// 新型文件变动 ledger（全局单例，供工具钩子/UI
  /// 联动 undo/redo 使用）。
  AiFileMutationLedger get mutationLedger => _mutationLedger;

  Future<WebFetchScraplingProbeStatus> probeWebFetchScrapling({
    required AiWebFetchScraplingSettings settings,
  }) => _scraplingBridge.probe(settings: settings);

  Stream<WebFetchScraplingRuntimeEvent>
  installWebFetchScraplingRuntimeStreaming({
    required AiWebFetchScraplingSettings settings,
  }) => _scraplingBridge.installRuntimeStreaming(settings: settings);

  Stream<WebFetchScraplingRuntimeEvent>
  uninstallWebFetchScraplingRuntimeStreaming({
    required AiWebFetchScraplingSettings settings,
  }) => _scraplingBridge.uninstallRuntimeStreaming(settings: settings);

  Future<void> resetWebFetchScrapling() => _scraplingBridge.reset();

  WebFetchScraplingProbeStatus get lastWebFetchScraplingProbe =>
      _scraplingBridge.lastProbe;

  /// 工具输出单轮最大字符数限制。
  /// 超过此限制时截断并附刚抽提提示，防止 Context 溢出和 API token 超限。
  /// 由用户设置注入，可在运行时调整。
  int maxToolOutputChars = 150000;

  /// 仅此模板可使用内建技能管理工具。
  static const String _skillManagerTemplateId =
      AiPromptTemplatePolicies.hermesTalkerTemplateId;

  /// 判断工具是否应出现在指定线程模板中。
  bool _isBuiltinAllowedForTemplate(AiResolvedTool tool, String templateId) {
    if (templateId == kMachineExpertTemplateId &&
        (tool.builtinKind == AiBuiltinToolKind.bash ||
            tool.builtinKind == AiBuiltinToolKind.bashBackground)) {
      return false;
    }
    if (tool.builtinKind == AiBuiltinToolKind.skillManager) {
      return templateId == _skillManagerTemplateId;
    }
    if (tool.builtinKind == AiBuiltinToolKind.memory) {
      return templateId == _skillManagerTemplateId;
    }
    if (_isAgentBuiltinKind(tool.builtinKind)) {
      final kind = tool.builtinKind;
      return kind != null && _enabledAgentsExposeBuiltinTool(kind, tool.name);
    }
    if (_isMachineTerminalBuiltinKind(tool.builtinKind)) {
      return templateId == kMachineExpertTemplateId;
    }
    return true;
  }

  bool _isMachineTerminalBuiltinKind(AiBuiltinToolKind? kind) {
    return kind == AiBuiltinToolKind.machineTerminalRead ||
        kind == AiBuiltinToolKind.machineTerminalWrite ||
        kind == AiBuiltinToolKind.machineTerminalExec ||
        kind == AiBuiltinToolKind.machineTerminalControl;
  }

  bool _enabledAgentsExposeBuiltinTool(
    AiBuiltinToolKind kind,
    String toolName,
  ) {
    final controller = _agentsControllerProvider?.call();
    if (controller == null) return false;
    for (final agent in controller.enabledAgents) {
      final configuredToolNames = normalizeAgentBuiltinToolNames(
        agent.builtinToolNames,
      );
      if (configuredToolNames.isEmpty) return true;
      final configuredAgentToolNames = configuredToolNames
          .where(isAgentCoordinationBuiltinToolName)
          .toList(growable: false);
      if (configuredAgentToolNames.isEmpty) continue;
      if (configuredAgentToolNames.any(
        (name) => _agentBuiltinToolNameMatches(kind, toolName, name),
      )) {
        return true;
      }
    }
    return false;
  }

  bool _agentBuiltinToolNameMatches(
    AiBuiltinToolKind kind,
    String toolName,
    String configuredName,
  ) {
    final normalized = normalizeAsciiLookupKey(configuredName);
    if (normalized.isEmpty) return false;
    return normalized == normalizeAsciiLookupKey(toolName) ||
        normalized == normalizeAsciiLookupKey(kind.name) ||
        AiResolvedToolCatalog._builtinAliasKind(normalized) == kind;
  }

  bool _isAgentBuiltinKind(AiBuiltinToolKind? kind) {
    return kind?.isAgentCoordinationTool ?? false;
  }

  int _toolNameCompare(String left, String right) {
    final normalizedCompare = normalizeAsciiLookupKey(
      left,
    ).compareTo(normalizeAsciiLookupKey(right));
    if (normalizedCompare != 0) {
      return normalizedCompare;
    }
    return left.compareTo(right);
  }

  List<LocalSkill> _sortedSkills(List<LocalSkill> skills) {
    final sorted = List<LocalSkill>.from(skills);
    sorted.sort((a, b) => _toolNameCompare(a.name, b.name));
    return sorted;
  }

  List<McpServer> _sortedEnabledMcpServers(List<McpServer> servers) {
    final sorted = servers.where((item) => item.enabled).toList(growable: false)
      ..sort((a, b) => _toolNameCompare(a.name, b.name));
    return sorted;
  }

  List<McpTool> _sortedMcpTools(Iterable<McpTool> tools) {
    final sorted = tools.toList(growable: false)
      ..sort((a, b) => _toolNameCompare(a.id, b.id));
    return sorted;
  }

  /// 应用内建工具的启用状态、覆盖配置、顺序和优先级。
  List<AiResolvedTool> _resolveConfiguredBuiltinTools(
    List<AiBuiltinToolConfig> configs,
  ) {
    final effectiveConfigs = configs.isEmpty
        ? AiBuiltinToolConfig.defaults()
        : configs;
    final sortedConfigs = List<AiBuiltinToolConfig>.from(effectiveConfigs)
      ..sort((a, b) {
        final cmp = a.sortOrder.compareTo(b.sortOrder);
        if (cmp != 0) return cmp;
        final priorityCmp = a.priority.compareTo(b.priority);
        return priorityCmp != 0
            ? priorityCmp
            : a.kind.index.compareTo(b.kind.index);
      });
    final toolByKind = <AiBuiltinToolKind, AiResolvedTool>{};
    for (final tool in _builtinTools) {
      if (tool.builtinKind != null) {
        toolByKind[tool.builtinKind!] = tool;
      }
    }
    final result = <AiResolvedTool>[];
    for (final cfg in sortedConfigs) {
      if (!cfg.enabled) continue;
      if (cfg.kind == AiBuiltinToolKind.dingTalkToolSearch ||
          cfg.kind == AiBuiltinToolKind.dingtalkDws) {
        continue;
      }
      final baseTool = toolByKind[cfg.kind];
      if (baseTool == null) continue;
      final overrideName = nullIfBlank(cfg.displayName);
      final overrideDesc = nullIfBlank(cfg.promptOverride);
      final overrideSummary = nullIfBlank(cfg.summary);
      final needsOverride =
          overrideName != null ||
          overrideDesc != null ||
          overrideSummary != null ||
          cfg.schemaOverride != null;
      if (!needsOverride) {
        // 即使没有 prompt/schema 覆盖，也要把用户配置（timeout/retry/...）
        // 透传给 execute()，否则 retry-on-failure 等策略不会生效。
        result.add(
          AiResolvedTool(
            name: baseTool.name,
            definition: baseTool.definition,
            source: baseTool.source,
            builtinKind: baseTool.builtinKind,
            mcpServer: baseTool.mcpServer,
            mcpTool: baseTool.mcpTool,
            skill: baseTool.skill,
            builtinConfig: cfg,
            dingtalkDwsCommand: baseTool.dingtalkDwsCommand,
            dingtalkDwsCommands: baseTool.dingtalkDwsCommands,
            toolSearchDeferredToolDefinitions:
                baseTool.toolSearchDeferredToolDefinitions,
            toolSearchDeferredTools: baseTool.toolSearchDeferredTools,
          ),
        );
        continue;
      }
      var desc = baseTool.definition.description;
      if (overrideDesc != null) {
        desc = overrideDesc;
      }
      if (overrideSummary != null) {
        desc = '$desc\n\n$overrideSummary';
      }
      result.add(
        AiResolvedTool(
          name: overrideName ?? baseTool.name,
          definition: AiToolDefinition(
            name: overrideName ?? baseTool.definition.name,
            description: desc,
            parameters: cfg.schemaOverride ?? baseTool.definition.parameters,
          ),
          source: baseTool.source,
          builtinKind: baseTool.builtinKind,
          builtinConfig: cfg,
          dingtalkDwsCommand: baseTool.dingtalkDwsCommand,
          dingtalkDwsCommands: baseTool.dingtalkDwsCommands,
        ),
      );
    }
    return result;
  }

  /// 装配可调用工具目录：MCP 目录来自实时探测。
  ///
  /// 运行时快照已带目录时直接走 [resolveCatalogFromRuntimeSnapshot]，避免
  /// 重复探测。能力调用优先级 Skill > MCP > Builtin：按优先级从高到低注册，
  /// 同名时高优先级工具胜出；definitions 的呈现顺序同样遵循该优先级，
  /// 让模型在工具列表中首先看到 Skill、其次 MCP、最后 Builtin。
  Future<AiResolvedToolCatalog> resolveCatalog({
    required AiSessionRuntimeContext runtimeContext,
    String? templateId,
  }) async {
    if (runtimeContext.mcpToolCatalogsByServerName.isNotEmpty) {
      return resolveCatalogFromRuntimeSnapshot(
        runtimeContext: runtimeContext,
        mcpToolCatalogsByServerName: runtimeContext.mcpToolCatalogsByServerName,
        templateId: templateId,
      );
    }
    final builder = _ToolCatalogBuilder();
    final effectiveTemplateId = (templateId ?? runtimeContext.templateId)
        .trim();

    _registerSkillTools(builder, runtimeContext);

    for (final server in _sortedEnabledMcpServers(
      runtimeContext.availableMcpServers,
    )) {
      if (!server.isVisibleToTemplate(effectiveTemplateId)) continue;
      try {
        final catalog = await _mcpToolService.discoverTools(server);
        if (catalog.status != McpToolCatalogStatus.ready) {
          final errorMessage = nullIfBlank(catalog.errorMessage);
          if (errorMessage != null) {
            builder.addServerNotice(server.name, errorMessage);
          }
          continue;
        }
        _absorbMcpCatalog(builder, server, catalog);
      } catch (error) {
        builder.addServerNotice(server.name, '$error');
      }
    }

    _registerBuiltinTools(builder, runtimeContext, effectiveTemplateId);
    return builder.build();
  }

  /// Skill 工具优先级最高，最先注册以占位同名工具。
  void _registerSkillTools(
    _ToolCatalogBuilder builder,
    AiSessionRuntimeContext runtimeContext,
  ) {
    for (final skill in _sortedSkills(runtimeContext.availableSkills)) {
      builder.register(_buildSkillTool(skill, builder.reservedToolNames));
    }
  }

  /// Builtin 工具优先级最低，最后注册；与模板不匹配的直接跳过。
  void _registerBuiltinTools(
    _ToolCatalogBuilder builder,
    AiSessionRuntimeContext runtimeContext,
    String effectiveTemplateId,
  ) {
    for (final tool in _resolveConfiguredBuiltinTools(
      runtimeContext.builtinToolConfigs,
    )) {
      if (!_isBuiltinAllowedForTemplate(tool, effectiveTemplateId)) continue;
      builder.register(tool);
    }
    _registerDingTalkDwsTools(builder, runtimeContext);
    _registerDingTalkMultimodalTools(builder, runtimeContext);
  }

  void _registerDingTalkDwsTools(
    _ToolCatalogBuilder builder,
    AiSessionRuntimeContext runtimeContext,
  ) {
    final commands = runtimeContext.availableDingTalkDwsCommands
        .where((item) => item.cliPath.trim().isNotEmpty)
        .toList(growable: false);
    final deferredTools = <String, AiResolvedTool>{};
    final deferredDefinitions = <String, AiToolDefinition>{};
    final usedToolNames = <String>{};
    for (final command in commands) {
      final name = dingtalkDwsToolName(command, usedNames: usedToolNames);
      final definition = AiToolDefinition(
        name: name,
        description:
            '${command.description.isEmpty ? command.summary : command.description}\n'
            'DWS 命令：${command.cliPath}；产品：${command.productName}；效果：${command.effect}；风险：${command.risk}。',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': command.parameters,
          'required': command.requiredParameterNames,
          'additionalProperties': false,
        },
      );
      final resolved = AiResolvedTool(
        name: name,
        definition: definition,
        source: AiRuntimeToolSource.builtin,
        builtinKind: AiBuiltinToolKind.dingtalkDws,
        dingtalkDwsCommand: command,
      );
      // 网关设置中勾选的 DWS 能力属于显式启用项：直接注册到当前工具目录，
      // 让其 Schema 随提示词模板加载；仅未勾选的能力不进入本次会话。
      builder.register(resolved);
      deferredTools[name] = resolved;
      deferredDefinitions[name] = definition;
    }
    const searchDefinition = AiToolDefinition(
      name: 'DingTalkToolSearchTool',
      description:
          '按关键词搜索当前钉钉网关已启用的 DWS 扩展工具。支持 select:精确名称、关键词和 +必含词；只返回工具 Schema，不执行命令。',
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'description': '搜索词或 select:工具名，不能为空。',
          },
          'max_results': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 12,
          },
          'tool_name': <String, Object?>{
            'type': 'string',
            'description': '搜索结果中的精确 DWS 工具名。执行时与 arguments 一起提供。',
          },
          'arguments': <String, Object?>{
            'type': 'object',
            'description': '目标 DWS 工具的参数对象。',
            'additionalProperties': true,
          },
        },
        'required': <String>['query'],
        'additionalProperties': false,
      },
    );
    builder.register(
      AiResolvedTool(
        name: searchDefinition.name,
        definition: searchDefinition,
        source: AiRuntimeToolSource.builtin,
        builtinKind: AiBuiltinToolKind.dingTalkToolSearch,
        dingtalkDwsCommands: commands,
        toolSearchDeferredToolDefinitions:
            Map<String, AiToolDefinition>.unmodifiable(deferredDefinitions),
        toolSearchDeferredTools: Map<String, AiResolvedTool>.unmodifiable(
          deferredTools,
        ),
      ),
    );
  }

  void _registerDingTalkMultimodalTools(
    _ToolCatalogBuilder builder,
    AiSessionRuntimeContext runtimeContext,
  ) {
    final raw = runtimeContext
        .toolExecutionMetadata['dingtalk_multimodal_capabilities'];
    final enabled = <AiDingTalkMultimodalCapability>{};
    final values = raw is List ? raw : const <Object?>[];
    for (final value in values) {
      final capability = AiDingTalkMultimodalCapability.fromStorage(value);
      if (capability != null) enabled.add(capability);
    }
    for (final capability in AiDingTalkMultimodalCapability.values) {
      if (!enabled.contains(capability)) continue;
      final definition = AiToolDefinition(
        name: capability.toolName,
        description:
            '同步生成并发送${capability.displayName}到当前钉钉会话。生成过程会等待最终结果，成功后该工具调用即视为正式响应。',
        parameters: _dingtalkMultimodalParameters(capability),
      );
      builder.register(
        AiResolvedTool(
          name: definition.name,
          definition: definition,
          source: AiRuntimeToolSource.builtin,
          builtinKind: switch (capability) {
            AiDingTalkMultimodalCapability.imageGeneration =>
              AiBuiltinToolKind.dingtalkImageGeneration,
            AiDingTalkMultimodalCapability.videoGeneration =>
              AiBuiltinToolKind.dingtalkVideoGeneration,
            AiDingTalkMultimodalCapability.audioGeneration =>
              AiBuiltinToolKind.dingtalkAudioGeneration,
          },
        ),
      );
    }
  }

  Map<String, Object?> _dingtalkMultimodalParameters(
    AiDingTalkMultimodalCapability capability,
  ) {
    final properties = <String, Object?>{
      'prompt': const <String, Object?>{
        'type': 'string',
        'minLength': 1,
        'maxLength': 12000,
        'description': '媒体生成要求，必须具体且可执行。',
      },
      'options': const <String, Object?>{
        'type': 'object',
        'description': '可选生成参数，支持尺寸、比例、质量、时长、格式、声音等线程会话参数。',
        'additionalProperties': true,
      },
      'size': const <String, Object?>{'type': 'string'},
      'aspect_ratio': const <String, Object?>{'type': 'string'},
      'duration_seconds': const <String, Object?>{
        'type': 'integer',
        'minimum': 1,
        'maximum': 600,
      },
      'count': const <String, Object?>{
        'type': 'integer',
        'minimum': 1,
        'maximum': 4,
      },
      'quality': const <String, Object?>{'type': 'string'},
      'style': const <String, Object?>{'type': 'string'},
      'output_format': const <String, Object?>{'type': 'string'},
      'background': const <String, Object?>{'type': 'string'},
      'negative_prompt': const <String, Object?>{'type': 'string'},
      'prompt_enhance': const <String, Object?>{'type': 'boolean'},
      'watermark': const <String, Object?>{'type': 'boolean'},
      'seed': const <String, Object?>{'type': 'integer', 'minimum': 0},
      'resolution': const <String, Object?>{'type': 'string'},
      'frame_rate': const <String, Object?>{
        'type': 'integer',
        'minimum': 1,
        'maximum': 60,
      },
      'num_frames': const <String, Object?>{
        'type': 'integer',
        'minimum': 1,
        'maximum': 441,
      },
      'mode': const <String, Object?>{'type': 'string'},
      'voice': const <String, Object?>{'type': 'string'},
      'speed': const <String, Object?>{'type': 'number'},
      'volume': const <String, Object?>{
        'type': 'number',
        'minimum': 0,
        'maximum': 10,
      },
      'sample_rate': const <String, Object?>{
        'type': 'integer',
        'minimum': 8000,
        'maximum': 96000,
      },
      'bitrate': const <String, Object?>{
        'type': 'integer',
        'minimum': 8000,
        'maximum': 512000,
      },
      'pitch': const <String, Object?>{'type': 'number'},
      'language_boost': const <String, Object?>{'type': 'string'},
      'emotion': const <String, Object?>{'type': 'string'},
      'text_normalization': const <String, Object?>{'type': 'boolean'},
      'latex_read': const <String, Object?>{'type': 'boolean'},
      'channel': const <String, Object?>{'type': 'integer', 'minimum': 1},
      'force_cbr': const <String, Object?>{'type': 'boolean'},
      'subtitle_enable': const <String, Object?>{'type': 'boolean'},
      'subtitle_type': const <String, Object?>{'type': 'string'},
      'pronunciation_tone': const <String, Object?>{
        'type': 'array',
        'maxItems': 64,
        'items': <String, Object?>{'type': 'string'},
      },
      'timbre_weights': const <String, Object?>{
        'type': 'array',
        'maxItems': 32,
        'items': <String, Object?>{'type': 'object'},
      },
      'voice_modify': const <String, Object?>{
        'type': 'object',
        'additionalProperties': true,
      },
      'reference_image_paths': const <String, Object?>{
        'type': 'array',
        'maxItems': 8,
        'items': <String, Object?>{'type': 'string', 'maxLength': 1024},
      },
      'purpose': const <String, Object?>{
        'type': 'string',
        'description': '本次生成调用的简短目的。',
      },
    };
    return <String, Object?>{
      'type': 'object',
      'properties': properties,
      'required': const <String>['prompt'],
      'additionalProperties': false,
    };
  }

  /// 把已就绪的 MCP 目录并入装配结果：透传告警、记录服务端说明并注册工具。
  void _absorbMcpCatalog(
    _ToolCatalogBuilder builder,
    McpServer server,
    McpToolCatalog catalog,
  ) {
    final warningMessage = nullIfBlank(catalog.warningMessage);
    if (warningMessage != null) {
      builder.addServerNotice(server.name, warningMessage);
    }
    final serverInstructions = nullIfBlank(catalog.serverInstructions);
    if (serverInstructions != null) {
      builder.mcpServerInstructionsByName[server.name] = serverInstructions;
    }
    for (final mcpTool in _sortedMcpTools(catalog.tools)) {
      builder.register(
        _buildMcpTool(
          server: server,
          tool: mcpTool,
          takenNames: builder.reservedToolNames,
        ),
      );
    }
  }

  /// 装配可调用工具目录：MCP 目录取自已扫描的运行时快照，全程同步。
  ///
  /// 优先级与 [resolveCatalog] 一致；快照里尚未扫描或正在刷新的服务端
  /// 只登记提示，不阻塞其余工具的装配。
  AiResolvedToolCatalog resolveCatalogFromRuntimeSnapshot({
    required AiSessionRuntimeContext runtimeContext,
    Map<String, McpToolCatalog> mcpToolCatalogsByServerName =
        const <String, McpToolCatalog>{},
    String? templateId,
  }) {
    final builder = _ToolCatalogBuilder();
    final effectiveTemplateId = (templateId ?? runtimeContext.templateId)
        .trim();

    _registerSkillTools(builder, runtimeContext);

    for (final server in _sortedEnabledMcpServers(
      runtimeContext.availableMcpServers,
    )) {
      if (!server.isVisibleToTemplate(effectiveTemplateId)) continue;
      final catalog = mcpToolCatalogsByServerName[server.name];
      if (catalog == null || catalog.status == McpToolCatalogStatus.idle) {
        builder.addServerNotice(server.name, '工具目录尚未扫描。');
        continue;
      }
      if (catalog.status == McpToolCatalogStatus.loading) {
        builder.addServerNotice(server.name, '工具目录正在刷新。');
        continue;
      }
      if (catalog.status != McpToolCatalogStatus.ready) {
        final errorMessage = nullIfBlank(catalog.errorMessage);
        if (errorMessage != null) {
          builder.addServerNotice(server.name, errorMessage);
        }
        continue;
      }
      _absorbMcpCatalog(builder, server, catalog);
    }

    _registerBuiltinTools(builder, runtimeContext, effectiveTemplateId);
    return builder.build();
  }

  Future<AiToolExecutionResult> execute({
    required String sessionId,
    required AiResolvedToolCatalog catalog,
    required AiToolCall toolCall,
    required AiModelConfig model,
    required Set<String> previouslyReadFiles,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required Future<BashCommandApprovalDecision> Function(
      BashCommandApprovalRequest request,
    )?
    confirmWriteCommand,
    Future<void>? cancelSignal,
    void Function(BashToolExecutionUpdate update)? onBashUpdate,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final executionAbort = await _beginExecution(cancelSignal);
    if (executionAbort == null) {
      const message = '工具执行已取消。';
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.cancelled,
        command: toolCall.name,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: message,
        durationMs: 0,
        resultText: 'status: cancelled\nerror: $message',
        metadata: const <String, Object?>{'execution_cancelled': true},
      );
    }
    final effectiveCancelSignal = combineCancelSignals(<Future<void>?>[
      cancelSignal,
      executionAbort.future,
    ]);
    try {
      return await _execute(
        sessionId: sessionId,
        catalog: catalog,
        toolCall: toolCall,
        model: model,
        previouslyReadFiles: previouslyReadFiles,
        denyCommandRules: denyCommandRules,
        requireWriteCommandConfirmation: requireWriteCommandConfirmation,
        confirmWriteCommand: confirmWriteCommand,
        cancelSignal: effectiveCancelSignal,
        onBashUpdate: onBashUpdate,
        metadata: metadata,
      );
    } finally {
      _finishExecution(executionAbort);
    }
  }

  Future<AiToolExecutionResult> _execute({
    required String sessionId,
    required AiResolvedToolCatalog catalog,
    required AiToolCall toolCall,
    required AiModelConfig model,
    required Set<String> previouslyReadFiles,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required Future<BashCommandApprovalDecision> Function(
      BashCommandApprovalRequest request,
    )?
    confirmWriteCommand,
    Future<void>? cancelSignal,
    void Function(BashToolExecutionUpdate update)? onBashUpdate,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final catalogTool = catalog.find(toolCall.name);
    if (catalogTool == null) {
      // 工具未命中时，给模型一份可操作的引导，而不是只丢一句
      // “Unsupported tool name”。常见两种诱因：
      //   1) 模型在 plan 待批准轮次幻觉调用 Write/TodoWrite —— 此时 catalog
      //      被刻意清空，应提示先调用 ExitPlanMode 或等待用户批准；
      //   2) 模型把 Claude Code 风格名字（如 TodoWrite）当成了别名 —— 给出
      //      当前轮次真实可用的工具名清单，便于自我纠正。
      final availableNames = trimmedNonEmptyStrings(
        catalog.definitions.map((tool) => tool.name),
      );
      final guidance = StringBuffer('不支持的工具名称：${toolCall.name}。');
      if (availableNames.isEmpty) {
        guidance.write(AiPlanModeGuidance.unsupportedEmptyCatalog);
      } else {
        // 限制建议数量，避免 MCP 工具过多撑大结果。
        const maxSuggestions = 24;
        final preview = availableNames.length <= maxSuggestions
            ? availableNames.join(', ')
            : '${availableNames.take(maxSuggestions).join(', ')}……'
                  '（另有 ${availableNames.length - maxSuggestions} 个）';
        guidance.write(
          ' 只能使用本轮目录中的准确名称：$preview。请使用正确的工具名称和匹配的参数结构重新调用，禁止改为在聊天中倾倒代码。',
        );
      }
      final guidanceText = guidance.toString();
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.invalidArguments,
        command: toolCall.name,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: guidanceText,
        durationMs: 0,
        resultText: 'status: invalid_arguments\nerror: $guidanceText',
        metadata: <String, Object?>{
          ...metadata,
          'unsupported_tool_name': toolCall.name,
          'available_tool_names': availableNames,
          'tool_catalog_empty': availableNames.isEmpty,
        },
      );
    }
    var resolvedTool = catalogTool;
    var executionCatalog = catalog;
    if (resolvedTool.builtinKind == AiBuiltinToolKind.toolSearch) {
      executionCatalog = _toolSearchCatalogForTemplate(
        catalog: catalog,
        toolSearch: resolvedTool,
        metadata: metadata,
      );
      resolvedTool = executionCatalog.find(toolCall.name) ?? resolvedTool;
      final gatewayArguments = AiToolUtils.decodeArguments(
        toolCall.arguments,
        parameters: resolvedTool.definition.parameters,
      );
      final deferredToolName = AiToolUtils.readString(
        gatewayArguments['tool_name'],
      );
      if (deferredToolName.isNotEmpty) {
        final deferredTool = executionCatalog.findDeferredTool(
          deferredToolName,
        );
        if (deferredTool == null) {
          return AiToolUtils.invalidResult(
            'ToolSearch',
            '延迟工具不可用：$deferredToolName。请先执行 ToolSearch 查询，并使用结果中的精确名称。',
          );
        }
        final delegatedArguments = _toolSearchDelegatedArguments(
          gatewayArguments['arguments'],
        );
        if (delegatedArguments == null) {
          return AiToolUtils.invalidResult(
            'ToolSearch',
            '`arguments` 必须是符合目标工具 Schema 的 JSON 对象。',
          );
        }
        final delegatedToolCall = AiToolCall(
          id: toolCall.id,
          name: deferredTool.definition.name,
          arguments: jsonEncode(delegatedArguments),
        );
        final delegatedResult = await execute(
          sessionId: sessionId,
          catalog: AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[deferredTool.definition],
            toolsByName: <String, AiResolvedTool>{
              deferredTool.definition.name: deferredTool,
            },
            notices: executionCatalog.notices,
            mcpServerInstructionsByName:
                executionCatalog.mcpServerInstructionsByName,
          ),
          toolCall: delegatedToolCall,
          model: model,
          previouslyReadFiles: previouslyReadFiles,
          denyCommandRules: denyCommandRules,
          requireWriteCommandConfirmation: requireWriteCommandConfirmation,
          confirmWriteCommand: confirmWriteCommand,
          cancelSignal: cancelSignal,
          onBashUpdate: onBashUpdate,
          metadata: <String, Object?>{
            ...metadata,
            'tool_search_gateway': true,
            'tool_search_gateway_tool_name': deferredTool.definition.name,
          },
        );
        return AiToolExecutionResult(
          status: delegatedResult.status,
          command: delegatedResult.command,
          workingDirectory: delegatedResult.workingDirectory,
          stdout: delegatedResult.stdout,
          stderr: delegatedResult.stderr,
          durationMs: delegatedResult.durationMs,
          resultText: delegatedResult.resultText,
          exitCode: delegatedResult.exitCode,
          matchedRuleId: delegatedResult.matchedRuleId,
          matchedRulePattern: delegatedResult.matchedRulePattern,
          isWriteCommand: delegatedResult.isWriteCommand,
          writeAnalysisReason: delegatedResult.writeAnalysisReason,
          metadata: <String, Object?>{
            ...delegatedResult.metadata,
            'tool_search_gateway': true,
            'tool_search_gateway_tool_name': deferredTool.definition.name,
          },
        );
      }
    }
    if (resolvedTool.builtinKind == AiBuiltinToolKind.dingTalkToolSearch) {
      executionCatalog = _toolSearchCatalogForTemplate(
        catalog: catalog,
        toolSearch: resolvedTool,
        metadata: metadata,
      );
      resolvedTool = executionCatalog.find(toolCall.name) ?? resolvedTool;
      final gatewayArguments = AiToolUtils.decodeArguments(
        toolCall.arguments,
        parameters: resolvedTool.definition.parameters,
      );
      final deferredToolName = AiToolUtils.readString(
        gatewayArguments['tool_name'],
      );
      if (deferredToolName.isNotEmpty) {
        final deferredTool = executionCatalog.findDeferredTool(
          deferredToolName,
        );
        if (deferredTool == null ||
            deferredTool.builtinKind != AiBuiltinToolKind.dingtalkDws) {
          return AiToolUtils.invalidResult(
            'DingTalkToolSearchTool',
            '钉钉 DWS 工具不可用：$deferredToolName。请先搜索并使用已返回的精确工具名。',
          );
        }
        final delegatedArguments = _toolSearchDelegatedArguments(
          gatewayArguments['arguments'],
        );
        if (delegatedArguments == null) {
          return AiToolUtils.invalidResult(
            'DingTalkToolSearchTool',
            '`arguments` 必须是符合目标工具 Schema 的 JSON 对象。',
          );
        }
        final delegatedToolCall = AiToolCall(
          id: toolCall.id,
          name: deferredTool.definition.name,
          arguments: jsonEncode(delegatedArguments),
        );
        final delegatedResult = await execute(
          sessionId: sessionId,
          catalog: AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[deferredTool.definition],
            toolsByName: <String, AiResolvedTool>{
              deferredTool.definition.name: deferredTool,
            },
            notices: executionCatalog.notices,
            mcpServerInstructionsByName:
                executionCatalog.mcpServerInstructionsByName,
          ),
          toolCall: delegatedToolCall,
          model: model,
          previouslyReadFiles: previouslyReadFiles,
          denyCommandRules: denyCommandRules,
          requireWriteCommandConfirmation: requireWriteCommandConfirmation,
          confirmWriteCommand: confirmWriteCommand,
          cancelSignal: cancelSignal,
          onBashUpdate: onBashUpdate,
          metadata: <String, Object?>{
            ...metadata,
            'dingtalk_tool_search_gateway': true,
            'dingtalk_tool_search_gateway_tool_name':
                deferredTool.definition.name,
          },
        );
        return AiToolExecutionResult(
          status: delegatedResult.status,
          command: delegatedResult.command,
          workingDirectory: delegatedResult.workingDirectory,
          stdout: delegatedResult.stdout,
          stderr: delegatedResult.stderr,
          durationMs: delegatedResult.durationMs,
          resultText: delegatedResult.resultText,
          exitCode: delegatedResult.exitCode,
          matchedRuleId: delegatedResult.matchedRuleId,
          matchedRulePattern: delegatedResult.matchedRulePattern,
          isWriteCommand: delegatedResult.isWriteCommand,
          writeAnalysisReason: delegatedResult.writeAnalysisReason,
          metadata: <String, Object?>{
            ...delegatedResult.metadata,
            'dingtalk_tool_search_gateway': true,
            'dingtalk_tool_search_gateway_tool_name':
                deferredTool.definition.name,
          },
        );
      }
    }
    final decodedArguments = AiToolUtils.decodeArguments(
      toolCall.arguments,
      parameters: resolvedTool.definition.parameters,
    );
    final hookToolName = _hookToolName(resolvedTool);
    final hookMatcherValue = _hookMatcherValue(resolvedTool, hookToolName);
    final hookWorkingDirectory = _hookWorkingDirectory(decodedArguments);
    final preHookResult = await _hookService.runHooks(
      eventName: 'PreToolUse',
      sessionId: sessionId,
      matcherValue: hookMatcherValue,
      cwd: hookWorkingDirectory,
      payload: _toolHookPayload(
        eventName: 'PreToolUse',
        toolName: hookToolName,
        toolSource: resolvedTool.source.name,
        sessionId: sessionId,
        toolInput: decodedArguments,
        cwd: hookWorkingDirectory,
      ),
    );
    if (preHookResult.blocked) {
      return _hookBlockedToolResult(
        toolName: hookToolName,
        decodedArguments: decodedArguments,
        hookResult: preHookResult,
      );
    }

    final rawExecutionStartedAt = Stopwatch()..start();
    // 登记到全局执行中心，以支持 UI 可观测与独立中断。
    // 取消在 finally 中反注销；Bash 子进程启动后会从
    // ai_bash_tool_service 里重新 attachKiller / attachPid 以支持真正
    // 发信号。不同 source 使用不同 kind；skill / mcp 默认 killer 为 no-op。
    final registryKind = switch (resolvedTool.source) {
      AiRuntimeToolSource.builtin => AiToolExecutionKind.builtin,
      AiRuntimeToolSource.mcp => AiToolExecutionKind.mcp,
      AiRuntimeToolSource.skill => AiToolExecutionKind.skill,
    };
    AiToolExecutionRegistration? executionRegistration;
    late AiToolExecutionResult rawResult;
    // 用户层 timeout / retry 策略包裹真正的 dispatch。
    // 仅当工具来自 builtin 且携带 [builtinConfig] 时启用：
    //   • timeout: 仅包裹无副作用 builtin；Task/Bash/写工具使用各自可控边界。
    //   • retry: 仅对无副作用工具的瞬时失败启用。Task、写文件、Bash、
    //     后台进程、技能管理、Memory 写入等可能产生副作用的调用不自动重放。
    final builtinCfg = resolvedTool.builtinConfig;
    // 为 MCP 调用设置统一上限，避免远端异常导致整轮无限等待。
    const defaultMcpTimeout = Duration(seconds: 120);
    final timeoutDuration = _runtimeTimeoutDuration(
      tool: resolvedTool,
      decodedArguments: decodedArguments,
      builtinConfig: builtinCfg,
      defaultMcpTimeout: defaultMcpTimeout,
    );
    final maxRetries = builtinCfg?.effectiveMaxRetries ?? 0;

    Future<bool> cancellationRequested(
      AiToolExecutionRegistration? registration,
    ) async {
      if (registration?.isCancellationRequested == true) return true;
      return isCancelSignalCompleted(cancelSignal);
    }

    AiToolExecutionResult cancelledResult([Object? error]) {
      return _cancelledToolExecutionResult(
        _toolExecutionErrorResult(
          tool: resolvedTool,
          fallbackWorkingDirectory: hookWorkingDirectory,
          error: error ?? '工具执行已取消。',
          durationMs: rawExecutionStartedAt.elapsedMilliseconds,
        ),
      );
    }

    Future<AiToolExecutionResult> dispatchOnce(
      Future<void>? effectiveCancelSignal,
      AiToolExecutionRegistration? registration,
    ) async {
      return AiToolExecutionRegistry.instance.runRegistered(
        registration,
        () async => switch (resolvedTool.source) {
          AiRuntimeToolSource.builtin => _executeBuiltinTool(
            sessionId: sessionId,
            catalog: executionCatalog,
            tool: resolvedTool,
            toolCall: toolCall,
            decodedArguments: decodedArguments,
            model: model,
            previouslyReadFiles: previouslyReadFiles,
            denyCommandRules: denyCommandRules,
            requireWriteCommandConfirmation: requireWriteCommandConfirmation,
            confirmWriteCommand: confirmWriteCommand,
            cancelSignal: effectiveCancelSignal,
            onBashUpdate: onBashUpdate,
            metadata: metadata,
          ),
          AiRuntimeToolSource.mcp => _executeMcpTool(
            tool: resolvedTool,
            toolCall: toolCall,
            decodedArguments: decodedArguments,
            cancelSignal: effectiveCancelSignal,
            metadata: metadata,
          ),
          AiRuntimeToolSource.skill => _executeSkillTool(
            tool: resolvedTool,
            toolCall: toolCall,
            decodedArguments: decodedArguments,
          ),
        },
      );
    }

    bool isRetryableResult(AiToolExecutionResult r) {
      // 仅在用户启用 retry-on-failure 时判定。
      if (!_retryEnabled(builtinCfg)) return false;
      if (_retrySuppressionReason(
            tool: resolvedTool,
            decodedArguments: decodedArguments,
            result: r,
          ) !=
          null) {
        return false;
      }
      switch (r.status) {
        case BashToolExecutionStatus.failed:
        case BashToolExecutionStatus.timedOut:
          return true;
        case BashToolExecutionStatus.success:
        case BashToolExecutionStatus.cancelled:
        case BashToolExecutionStatus.denied:
        case BashToolExecutionStatus.rejected:
        case BashToolExecutionStatus.invalidArguments:
          return false;
      }
    }

    Future<AiToolExecutionResult> dispatchWithTimeout(
      AiToolExecutionRegistration? registration,
    ) async {
      Future<void>? combinedCancelSignal([Future<void>? timeoutSignal]) {
        return combineCancelSignals(<Future<void>?>[
          cancelSignal,
          registration?.cancelSignal,
          timeoutSignal,
        ]);
      }

      final localTimeout = timeoutDuration;
      if (localTimeout == null) {
        return dispatchOnce(combinedCancelSignal(), registration);
      }
      final timeoutCancellation = Completer<void>();
      final effectiveCancelSignal = combinedCancelSignal(
        timeoutCancellation.future,
      );
      final f = dispatchOnce(effectiveCancelSignal, registration);

      AiToolExecutionResult timedOutResult() => AiToolExecutionResult(
        status: BashToolExecutionStatus.timedOut,
        command: resolvedTool.name,
        workingDirectory: hookWorkingDirectory,
        stdout: '',
        stderr: '工具“${resolvedTool.name}”超过配置的 ${localTimeout.inSeconds} 秒时限。',
        durationMs: rawExecutionStartedAt.elapsedMilliseconds,
        resultText:
            'status: timed_out\nerror: 工具超过 ${localTimeout.inSeconds} 秒时限',
      );

      Future<void> cancelTimedOutExecution() async {
        if (!timeoutCancellation.isCompleted) {
          timeoutCancellation.complete();
        }
        await AiToolExecutionRegistry.instance.cancelRegistration(registration);
      }

      try {
        return await f.timeout(
          localTimeout,
          onTimeout: () async {
            await cancelTimedOutExecution();
            return timedOutResult();
          },
        );
      } on TimeoutException {
        await cancelTimedOutExecution();
        return timedOutResult();
      }
    }

    Future<AiToolExecutionResult> dispatchAttempt() async {
      if (await cancellationRequested(null)) return cancelledResult();
      final registration = AiToolExecutionRegistry.instance.register(
        toolCallId: toolCall.id,
        sessionId: sessionId,
        kind: registryKind,
        displayName: resolvedTool.name,
      );
      executionRegistration = registration;
      try {
        final result = await dispatchWithTimeout(registration);
        if (result.status != BashToolExecutionStatus.timedOut &&
            await cancellationRequested(registration)) {
          return _cancelledToolExecutionResult(result);
        }
        return result;
      } catch (error) {
        if (await cancellationRequested(registration)) {
          return cancelledResult(error);
        }
        rethrow;
      } finally {
        if (registration != null) {
          AiToolExecutionRegistry.instance.unregister(registration);
        }
        if (identical(executionRegistration, registration)) {
          executionRegistration = null;
        }
      }
    }

    Future<bool> waitForRetryBackoff(Duration backoff) async {
      final registration = AiToolExecutionRegistry.instance.register(
        toolCallId: toolCall.id,
        sessionId: sessionId,
        kind: registryKind,
        displayName: resolvedTool.name,
      );
      executionRegistration = registration;
      try {
        return delayUntilCancelled(
          backoff,
          cancelSignal: combineCancelSignals(<Future<void>?>[
            cancelSignal,
            registration?.cancelSignal,
          ]),
        );
      } finally {
        if (registration != null) {
          AiToolExecutionRegistry.instance.unregister(registration);
        }
        if (identical(executionRegistration, registration)) {
          executionRegistration = null;
        }
      }
    }

    AiToolExecutionResult? attemptResult;
    var attempts = 0;
    try {
      while (true) {
        attempts += 1;
        try {
          attemptResult = await dispatchAttempt();
          if (!isRetryableResult(attemptResult) || attempts > maxRetries) {
            attemptResult = _annotateRetrySuppressionIfNeeded(
              tool: resolvedTool,
              decodedArguments: decodedArguments,
              result: attemptResult,
              builtinConfig: builtinCfg,
            );
            break;
          }
        } catch (error) {
          if (!_retryEnabled(builtinCfg) ||
              attempts > maxRetries ||
              _retrySuppressionReason(
                    tool: resolvedTool,
                    decodedArguments: decodedArguments,
                  ) !=
                  null) {
            attemptResult = _toolExecutionErrorResult(
              tool: resolvedTool,
              fallbackWorkingDirectory: hookWorkingDirectory,
              error: error,
              durationMs: rawExecutionStartedAt.elapsedMilliseconds,
            );
            attemptResult = _annotateRetrySuppressionIfNeeded(
              tool: resolvedTool,
              decodedArguments: decodedArguments,
              result: attemptResult,
              builtinConfig: builtinCfg,
            );
            break;
          }
        }
        // 指数退避：仅在还要继续下一轮重试时才等待。
        if (builtinCfg != null) {
          final backoff = builtinCfg.retryBackoffFor(attempts);
          if (backoff > Duration.zero) {
            final cancelled = await waitForRetryBackoff(backoff);
            if (cancelled) {
              attemptResult = cancelledResult();
              break;
            }
          }
        }
      }
      rawResult = attemptResult;
      // 捕获后插入 ledger：MCP / Skill 等工具可能只在 metadata 提供
      // file_mutation_path，却没有创建 ledger 记录。此时用当前磁盘内容补
      // after，before 保持 null。
      rawResult = await _capturePostHocLedgerRecord(
        sessionId: sessionId,
        toolName: hookToolName,
        toolCallId: toolCall.id,
        result: rawResult,
      );
      final postHookWorkingDirectory = _effectiveWorkingDirectory(
        rawResult.workingDirectory,
        fallback: hookWorkingDirectory,
      );
      final postHookResult = await _hookService.runHooks(
        eventName: rawResult.status == BashToolExecutionStatus.success
            ? 'PostToolUse'
            : 'PostToolUseFailure',
        sessionId: sessionId,
        matcherValue: hookMatcherValue,
        cwd: postHookWorkingDirectory,
        payload: _toolHookPayload(
          eventName: rawResult.status == BashToolExecutionStatus.success
              ? 'PostToolUse'
              : 'PostToolUseFailure',
          toolName: hookToolName,
          toolSource: resolvedTool.source.name,
          sessionId: sessionId,
          toolInput: decodedArguments,
          cwd: postHookWorkingDirectory,
          toolOutput: <String, Object?>{
            'status': rawResult.status.storageValue,
            'command': rawResult.command,
            'working_directory': rawResult.workingDirectory,
            'stdout': rawResult.stdout,
            'stderr': rawResult.stderr,
            'duration_ms': rawResult.durationMs,
            'exit_code': rawResult.exitCode,
            ...rawResult.metadata,
          },
        ),
      );
      return await _applyOutputBudget(
        _mergeHookResultIntoToolResult(
          rawResult: rawResult,
          preHookResult: preHookResult,
          postHookResult: postHookResult,
        ),
        sessionId: sessionId,
        toolCallId: toolCall.id,
      );
    } finally {
      final activeRegistration = executionRegistration;
      if (activeRegistration != null) {
        AiToolExecutionRegistry.instance.unregister(activeRegistration);
      }
    }
  }

  AiResolvedToolCatalog _toolSearchCatalogForTemplate({
    required AiResolvedToolCatalog catalog,
    required AiResolvedTool toolSearch,
    required Map<String, Object?> metadata,
  }) {
    final templateId = '${metadata['template_id'] ?? ''}'.trim();
    final deferredTools = <String, AiResolvedTool>{};
    final deferredDefinitions = <String, AiToolDefinition>{};
    for (final entry in toolSearch.toolSearchDeferredTools.entries) {
      final tool = entry.value;
      final server = tool.mcpServer;
      if (tool.source == AiRuntimeToolSource.mcp &&
          (server == null ||
              !server.enabled ||
              (server.visibleTemplateIds != null &&
                  (templateId.isEmpty ||
                      !server.isVisibleToTemplate(templateId))))) {
        continue;
      }
      deferredTools[entry.key] = tool;
      deferredDefinitions[entry.key] =
          toolSearch.toolSearchDeferredToolDefinitions[entry.key] ??
          tool.definition;
    }
    if (deferredTools.length == toolSearch.toolSearchDeferredTools.length) {
      return catalog;
    }
    final scopedToolSearch = toolSearch.withToolSearchDeferredTools(
      definitions: deferredDefinitions,
      tools: deferredTools,
    );
    return AiResolvedToolCatalog(
      definitions: catalog.definitions,
      toolsByName: <String, AiResolvedTool>{
        for (final entry in catalog.toolsByName.entries)
          entry.key: identical(entry.value, toolSearch)
              ? scopedToolSearch
              : entry.value,
      },
      notices: catalog.notices,
      mcpServerInstructionsByName: catalog.mcpServerInstructionsByName,
    );
  }

  Map<String, Object?>? _toolSearchDelegatedArguments(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return stringKeyedMapFromValue(value);
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return stringKeyedMapFromValue(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // 工具输出 budget 保护。
  // 对 resultText 进行字符数上限保护，超限时先尝试持久化完整结果，
  // 再向模型返回 head/tail 预算内预览和恢复提示。
  // 这防止了单次工具调用将大量输出（如 WebFetch 、Bash cat 大文件）直接塑进 API 上下文。
  // stdout/stderr 截断边界与 resultText 保持一致。
  Future<AiToolExecutionResult> _applyOutputBudget(
    AiToolExecutionResult result, {
    required String sessionId,
    required String toolCallId,
  }) async {
    final rawResult = result.resultText;
    if (rawResult.length <= maxToolOutputChars) {
      return result;
    }
    final persisted = await _persistToolOutput(
      sessionId: sessionId,
      toolCallId: toolCallId,
      content: rawResult,
    );
    final persistedPath = persisted?.path ?? '';
    final resultView = _truncateOutputTextToBudget(
      rawResult,
      maxToolOutputChars,
      persistedPath: persistedPath,
    );
    String capStream(String value) {
      return _truncateOutputTextToBudget(
        value,
        maxToolOutputChars,
        persistedPath: persistedPath,
      ).text;
    }

    final truncatedStdout = capStream(result.stdout);
    final truncatedStderr = capStream(result.stderr);
    final fullContentAvailable = persisted != null;
    return result.copyWith(
      stdout: truncatedStdout,
      stderr: truncatedStderr,
      resultText: resultView.text,
      metadata: <String, Object?>{
        ...result.metadata,
        'tool_output_truncated': true,
        'tool_output_original_length': rawResult.length,
        'tool_output_budget_chars': maxToolOutputChars,
        'tool_output_included_chars': resultView.includedChars,
        'tool_output_omitted_chars': resultView.omittedChars,
        'tool_output_truncation_strategy':
            _toolOutputTruncationStrategyHeadTail,
        'tool_output_full_content_available': fullContentAvailable,
        'tool_output_recovery_hint': fullContentAvailable
            ? _toolOutputRecoveryHintReadPersisted
            : _toolOutputRecoveryHintRerunNarrower,
        if (persisted != null) ...<String, Object?>{
          'tool_output_persisted': true,
          'tool_output_persisted_path': persisted.path,
          'tool_output_persisted_chars': persisted.originalChars,
          'tool_output_persistence_format': _toolOutputPersistenceFormatText,
        },
      },
    );
  }

  ({String text, int includedChars, int omittedChars})
  _truncateOutputTextToBudget(
    String value,
    int budget, {
    String persistedPath = '',
  }) {
    if (value.length <= budget) {
      return (text: value, includedChars: value.length, omittedChars: 0);
    }
    var notice = _toolOutputTruncationNotice(
      originalChars: value.length,
      omittedChars: value.length,
      budgetChars: budget,
      persistedPath: persistedPath,
    );
    var payloadBudget = math.max(
      _minToolOutputTruncationPayloadChars,
      budget - notice.length,
    );
    payloadBudget = math.min(payloadBudget, value.length);
    var omittedChars = value.length - payloadBudget;
    notice = _toolOutputTruncationNotice(
      originalChars: value.length,
      omittedChars: omittedChars,
      budgetChars: budget,
      persistedPath: persistedPath,
    );
    final effectivePayloadBudget = math.max(0, budget - notice.length);
    if (effectivePayloadBudget <= 0) {
      final fallback = notice.length <= budget
          ? notice
          : clipTextByCodeUnits(notice, budget, suffix: '');
      return (text: fallback, includedChars: 0, omittedChars: value.length);
    }
    final includedChars = math.min(effectivePayloadBudget, value.length);
    omittedChars = value.length - includedChars;
    final headChars = (includedChars / 2).ceil();
    final tailChars = includedChars - headChars;
    // 用不拆分代理对的安全边界切分：裸 substring 会把 emoji / 增补区字符从中间
    // 劈开，留下孤立代理码元（显示成 �，还可能污染后续 JSON 编码）。
    final head = value.substring(0, safeUtf16PrefixCodeUnits(value, headChars));
    final tail = tailChars <= 0
        ? ''
        : value.substring(
            safeUtf16SuffixStart(value, value.length - tailChars),
          );
    return (
      text: '$head$notice$tail',
      includedChars: includedChars,
      omittedChars: omittedChars,
    );
  }

  String _toolOutputTruncationNotice({
    required int originalChars,
    required int omittedChars,
    required int budgetChars,
    String persistedPath = '',
  }) {
    final recovery = nullIfBlank(persistedPath) == null
        ? 'Full output was not persisted; rerun a narrower command, add '
              'filters, or use file offsets if exact omitted content is '
              'needed.'
        : 'Full output saved to: $persistedPath. Read that file or rerun a '
              'narrower command if exact omitted content is needed.';
    return '\n\n[Output truncated: omitted $omittedChars middle chars from '
        '$originalChars-character result because it exceeded the '
        '$budgetChars-character tool output budget. $recovery]\n\n';
  }

  Future<_PersistedToolOutput?> _persistToolOutput({
    required String sessionId,
    required String toolCallId,
    required String content,
  }) async {
    final normalizedToolCallId = nullIfBlank(toolCallId);
    if (normalizedToolCallId == null || content.isEmpty) {
      return null;
    }
    final directoryPath = _toolOutputDirectoryPath(sessionId);
    if (nullIfBlank(directoryPath) == null) {
      return null;
    }
    final file = File(
      p.join(
        directoryPath,
        '${_safeToolOutputStorageIdentifier(normalizedToolCallId, 'tool_result')}.txt',
      ),
    );
    try {
      if (!await file.exists().timeout(defaultBoundedFileReadIdleTimeout)) {
        await writeFileAtomically(file, content);
      }
      return _PersistedToolOutput(
        path: file.path,
        originalChars: content.length,
      );
    } catch (error, stack) {
      silentLog('ai_tool_runtime_service', '持久化工具输出', error, stack);
      return null;
    }
  }

  String _toolOutputDirectoryPath(String sessionId) {
    final provider = _toolOutputDirectoryProvider;
    if (provider != null) {
      return provider(sessionId);
    }
    return p.join(
      OpenHandPaths.defaultSessionsDirectoryPath(),
      _safeToolOutputStorageIdentifier(sessionId, 'session'),
      _toolResultsSubdirectoryName,
    );
  }

  String _safeToolOutputStorageIdentifier(String raw, String fallback) {
    final normalized = collapseRepeatedUnderscores(
      (nullIfBlank(raw) ?? '').replaceAll(
        _unsafeToolOutputStorageCharsPattern,
        '_',
      ),
    );
    final value = normalized.isEmpty ? fallback : normalized;
    return value.length <= 120 ? value : value.substring(0, 120);
  }

  bool _retryEnabled(AiBuiltinToolConfig? config) {
    return config != null &&
        config.retryOnFailure &&
        config.effectiveMaxRetries > 0;
  }

  Duration? _runtimeTimeoutDuration({
    required AiResolvedTool tool,
    required Map<String, Object?> decodedArguments,
    required AiBuiltinToolConfig? builtinConfig,
    required Duration defaultMcpTimeout,
  }) {
    if (tool.source == AiRuntimeToolSource.mcp) return defaultMcpTimeout;
    if (builtinConfig == null) return null;
    if (tool.source == AiRuntimeToolSource.builtin &&
        _builtinToolCallMayHaveSideEffects(tool, decodedArguments)) {
      return null;
    }
    return Duration(seconds: builtinConfig.effectiveTimeoutSeconds);
  }

  AiToolExecutionResult _annotateRetrySuppressionIfNeeded({
    required AiResolvedTool tool,
    required Map<String, Object?> decodedArguments,
    required AiToolExecutionResult result,
    required AiBuiltinToolConfig? builtinConfig,
  }) {
    if (!_retryEnabled(builtinConfig)) return result;
    if (!_isRetryableFailureStatus(result.status)) return result;
    final reason = _retrySuppressionReason(
      tool: tool,
      decodedArguments: decodedArguments,
      result: result,
    );
    if (reason == null) return result;
    return AiToolUtils.withMergedMetadata(result, <String, Object?>{
      'retry_suppressed': true,
      'retry_suppressed_reason': reason,
    });
  }

  bool _isRetryableFailureStatus(BashToolExecutionStatus status) {
    return status == BashToolExecutionStatus.failed ||
        status == BashToolExecutionStatus.timedOut;
  }

  String? _retrySuppressionReason({
    required AiResolvedTool tool,
    required Map<String, Object?> decodedArguments,
    AiToolExecutionResult? result,
  }) {
    if (tool.source == AiRuntimeToolSource.builtin &&
        _builtinToolCallMayHaveSideEffects(tool, decodedArguments)) {
      return 'builtin_tool_may_have_side_effects';
    }
    if (result != null && _toolResultHasMutationSignal(result)) {
      return 'tool_result_has_mutation_signal';
    }
    return null;
  }

  bool _builtinToolCallMayHaveSideEffects(
    AiResolvedTool tool,
    Map<String, Object?> decodedArguments,
  ) {
    final kind = tool.builtinKind;
    if (kind == null) return false;
    if (_nonRetryableSideEffectBuiltinKinds.contains(kind)) return true;
    final registeredTool = _toolRegistry.getTool(kind);
    if (registeredTool?.isDestructive == true) return true;
    if (kind == AiBuiltinToolKind.memory) {
      final action = optionalLowercaseStringFromValue(
        decodedArguments['action'],
      );
      return action != null && action != 'list';
    }
    if (kind.isAgentCoordinationTool) return kind.isAgentMutationTool;
    return false;
  }

  bool _toolResultHasMutationSignal(AiToolExecutionResult result) {
    if (result.isWriteCommand) return true;
    final metadata = result.metadata;
    return metadata['file_mutation_kind'] != null ||
        metadata['file_mutation_path'] != null ||
        metadata['file_mutation_paths'] != null ||
        metadata['file_mutation_ledger_record_id'] != null ||
        metadata['file_mutation_ledger_record_ids'] != null;
  }

  /// 退化版 ledger 记录：当上游工具只返回 `file_mutation_path(s)`，
  /// 但没有携带 `file_mutation_ledger_record_id(s)` 时，读取当前磁盘内容
  /// 作为 after-content 补上 ledger。before 未知，记为 null。
  Future<AiToolExecutionResult> _capturePostHocLedgerRecord({
    required String sessionId,
    required String toolName,
    required String toolCallId,
    required AiToolExecutionResult result,
  }) async {
    if (result.status != BashToolExecutionStatus.success) return result;
    final meta = result.metadata;
    // 已由内置工具写入 ledger 的结果直接跳过。
    if (meta.containsKey('file_mutation_ledger_record_id') ||
        meta.containsKey('file_mutation_ledger_record_ids')) {
      return result;
    }
    final paths = <String>[];
    final singlePath = meta['file_mutation_path'];
    final normalizedSinglePath = singlePath is String
        ? nullIfBlank(singlePath)
        : null;
    if (normalizedSinglePath != null) {
      paths.add(normalizedSinglePath);
    }
    final multiPaths = meta['file_mutation_paths'];
    if (multiPaths is List) {
      for (final item in multiPaths) {
        final path = item is String ? nullIfBlank(item) : null;
        if (path != null) paths.add(path);
      }
    }
    if (paths.isEmpty) return result;
    final recorded = <String, String?>{};
    for (final path in paths) {
      try {
        final file = File(path);
        if (!await isRegularFilePath(path, followLinks: true)) {
          recorded[path] = null;
          continue;
        }
        String? after;
        try {
          after = await readBoundedFileString(
            file,
            maxBytes: _maxPostHocLedgerCaptureBytes,
          );
        } catch (error, stack) {
          silentLog('ai_tool_runtime_service', '读取工具执行后的账本内容', error, stack);
          after = null;
        }
        final id = await AiToolUtils.recordFileMutationToLedger(
          ledger: _mutationLedger,
          sessionId: sessionId,
          toolCallId: toolCallId,
          toolName: toolName,
          filePath: path,
          kind: FileMutationKind.modify,
          beforeContent: null,
          afterContent: after,
        );
        recorded[path] = id;
      } catch (error, stack) {
        silentLog('ai_tool_runtime_service', '记录工具执行后的文件变更', error, stack);
        recorded[path] = null;
      }
    }
    if (recorded.isEmpty) return result;
    return result.copyWith(
      metadata: <String, Object?>{
        ...meta,
        'file_mutation_ledger_record_ids': recorded,
        'file_mutation_ledger_capture_mode': 'after_only',
      },
    );
  }

  Future<AiToolExecutionResult> _executeBuiltinTool({
    required String sessionId,
    required AiResolvedToolCatalog catalog,
    required AiResolvedTool tool,
    required AiToolCall toolCall,
    required Map<String, Object?> decodedArguments,
    required AiModelConfig model,
    required Set<String> previouslyReadFiles,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required Future<BashCommandApprovalDecision> Function(
      BashCommandApprovalRequest request,
    )?
    confirmWriteCommand,
    Future<void>? cancelSignal,
    void Function(BashToolExecutionUpdate update)? onBashUpdate,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final kind = tool.builtinKind;
    if (kind == null) {
      return _invalidToolResult(
        toolCall.name,
        'Missing builtin tool metadata.',
      );
    }
    var dispatchKind = kind;
    var dispatchToolCall = toolCall;
    var dispatchArguments = decodedArguments;
    var dispatchMetadata = const <String, Object?>{};
    if (kind == AiBuiltinToolKind.bash &&
        AiToolUtils.readBool(decodedArguments['run_in_background']) == true) {
      final backgroundTool = _findResolvedBuiltinTool(
        catalog,
        AiBuiltinToolKind.bashBackground,
      );
      if (backgroundTool == null) {
        return _invalidToolResult(
          toolCall.name,
          'Bash run_in_background requires BashBackground to be enabled in the current tool catalog.',
        );
      }
      dispatchKind = AiBuiltinToolKind.bashBackground;
      dispatchToolCall = AiToolCall(
        id: toolCall.id,
        name: backgroundTool.name,
        arguments: toolCall.arguments,
      );
      dispatchArguments = <String, Object?>{
        ...decodedArguments,
        'action': 'start',
      }..remove('run_in_background');
      dispatchMetadata = <String, Object?>{
        'bash_run_in_background_alias': true,
        'routed_from_tool': tool.name,
        'routed_to_tool': backgroundTool.name,
      };
    } else if (kind == AiBuiltinToolKind.taskOutput ||
        kind == AiBuiltinToolKind.taskStop) {
      dispatchKind = AiBuiltinToolKind.bashBackground;
      dispatchToolCall = AiToolCall(
        id: toolCall.id,
        name: kind == AiBuiltinToolKind.taskOutput ? 'TaskOutput' : 'TaskStop',
        arguments: toolCall.arguments,
      );
      dispatchArguments = <String, Object?>{
        ...decodedArguments,
        'action': kind == AiBuiltinToolKind.taskOutput ? 'read' : 'stop',
      };
      dispatchMetadata = <String, Object?>{
        'background_task_alias': true,
        'routed_from_tool': toolCall.name,
        'routed_to_tool': 'BashBackground',
      };
    }
    // 优先通过多态 Registry 路由（轻量工具已迁移）
    // 通过 metadata 传递文件追踪和历史服务（遵循 AiToolExecutionContext 冻结约束）
    final registryContext = AiToolExecutionContext(
      sessionId: sessionId,
      catalog: catalog,
      toolCall: dispatchToolCall,
      decodedArguments: dispatchArguments,
      model: model,
      previouslyReadFiles: previouslyReadFiles,
      denyCommandRules: denyCommandRules,
      requireWriteCommandConfirmation: requireWriteCommandConfirmation,
      confirmWriteCommand: confirmWriteCommand,
      cancelSignal: cancelSignal,
      onBashUpdate: onBashUpdate,
      metadata: <String, Object?>{
        ...metadata,
        'file_tracker': _fileTrackerForSession(sessionId),
        'file_history': _fileHistory,
        'mutation_ledger': _mutationLedger,
        if (_machineTerminalService != null)
          'machine_terminal_service': _machineTerminalService,
        'write_confirmation_timeout_ms':
            _bashToolService.writeConfirmationTimeoutMs,
      },
    );
    final registryResult = await _toolRegistry.tryExecute(
      registryContext,
      dispatchKind,
    );
    if (registryResult != null) {
      if (dispatchMetadata.isEmpty) return registryResult;
      return AiToolUtils.withMergedMetadata(registryResult, dispatchMetadata);
    }
    // 注册表可能已释放，或可选处理器尚未注册。
    return _invalidToolResult(
      toolCall.name,
      'No registered handler found for builtin tool: ${kind.name}',
    );
  }

  AiResolvedTool? _findResolvedBuiltinTool(
    AiResolvedToolCatalog catalog,
    AiBuiltinToolKind kind,
  ) {
    for (final tool in catalog.toolsByName.values) {
      if (tool.source == AiRuntimeToolSource.builtin &&
          tool.builtinKind == kind) {
        return tool;
      }
    }
    return null;
  }

  Future<AiToolExecutionResult> _executeMcpTool({
    required AiResolvedTool tool,
    required AiToolCall toolCall,
    required Map<String, Object?> decodedArguments,
    Future<void>? cancelSignal,
    required Map<String, Object?> metadata,
  }) async {
    final server = tool.mcpServer;
    final mcpTool = tool.mcpTool;
    if (server == null || mcpTool == null) {
      return _invalidToolResult(toolCall.name, 'Missing MCP tool metadata.');
    }
    if (!server.enabled) {
      return _invalidToolResult(toolCall.name, '该 MCP 服务已停用。');
    }
    if (server.visibleTemplateIds != null) {
      final templateId = '${metadata['template_id'] ?? ''}'.trim();
      if (templateId.isEmpty || !server.isVisibleToTemplate(templateId)) {
        return _invalidToolResult(toolCall.name, '当前线程模板不可使用该 MCP 服务。');
      }
    }
    final cdpFirstBlock = _webReverseMcpCdpFirstBlock(
      tool: tool,
      toolCall: toolCall,
      decodedArguments: decodedArguments,
      metadata: metadata,
    );
    if (cdpFirstBlock != null) return cdpFirstBlock;

    final startedAt = Stopwatch()..start();
    final result = await _mcpToolService.callTool(
      server: server,
      toolName: mcpTool.id,
      arguments: decodedArguments,
      toolCallId: toolCall.id,
      cancelSignal: cancelSignal,
    );
    final outputText =
        nullIfBlank(result.outputText) ?? 'The MCP tool returned no output.';
    return AiToolExecutionResult(
      status: result.isError
          ? BashToolExecutionStatus.failed
          : BashToolExecutionStatus.success,
      command: '${tool.name} (${server.name}/${mcpTool.id})',
      workingDirectory: AiToolUtils.defaultWorkingDirectory(),
      stdout: result.isError ? '' : outputText,
      stderr: result.isError ? outputText : '',
      durationMs: startedAt.elapsedMilliseconds,
      resultText: outputText,
      metadata: <String, Object?>{
        'tool_source': 'mcp',
        'mcp_server_name': server.name,
        'mcp_tool_id': mcpTool.id,
        'mcp_tool_name': mcpTool.name,
        'mcp_is_error': result.isError,
      },
    );
  }

  AiToolExecutionResult? _webReverseMcpCdpFirstBlock({
    required AiResolvedTool tool,
    required AiToolCall toolCall,
    required Map<String, Object?> decodedArguments,
    required Map<String, Object?> metadata,
  }) {
    if (!WebReverseCdpFirstGuard.isRequired(metadata: metadata)) {
      return null;
    }
    if (_isCdpMcpTool(tool)) {
      return null;
    }
    if (_isNonCdpBrowserAutomationMcpTool(tool)) {
      final message =
          '${tool.name} is blocked for Web Reverse because target-origin browser automation must use the OpenHand-managed CDP session. Use CDP MCP tools or local jsonl/HAR artifacts instead.';
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.invalidArguments,
        command: tool.name,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: message,
        durationMs: 0,
        resultText: 'status: invalid_arguments\nerror: $message',
        metadata: <String, Object?>{
          'tool_source': 'mcp',
          'mcp_server_name': tool.mcpServer?.name,
          'mcp_tool_id': tool.mcpTool?.id,
          'mcp_tool_name': tool.mcpTool?.name,
          'web_reverse_mcp_blocked_for_cdp_first': true,
          'web_reverse_mcp_block_reason': 'non_cdp_browser_automation',
        },
      );
    }

    final argumentsText = _jsonishText(decodedArguments);
    final decision = WebReverseCdpFirstGuard.evaluateTextReference(
      text: argumentsText,
      metadata: metadata,
    );
    if (decision == null) return null;
    final message = decision.blockedMessage('MCP');
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.invalidArguments,
      command: tool.name,
      workingDirectory: AiToolUtils.defaultWorkingDirectory(),
      stdout: '',
      stderr: message,
      durationMs: 0,
      resultText: 'status: invalid_arguments\nerror: $message',
      metadata: <String, Object?>{
        'tool_source': 'mcp',
        'mcp_server_name': tool.mcpServer?.name,
        'mcp_tool_id': tool.mcpTool?.id,
        'mcp_tool_name': tool.mcpTool?.name,
        ...decision.metadata(
          requestedUrl: argumentsText,
          blockedFlag: 'web_reverse_mcp_blocked_for_cdp_first',
        ),
      },
    );
  }

  bool _isNonCdpBrowserAutomationMcpTool(AiResolvedTool tool) {
    final identity = _mcpToolIdentity(tool);
    if (identity.isEmpty) return false;
    if (_hasCdpMcpSignal(identity)) return false;
    if (_containsAny(identity, const <String>[
      '@playwright/mcp',
      'playwright',
      'puppeteer',
      'selenium',
      'webdriver',
      'browserless',
    ])) {
      return true;
    }
    final hasBrowserHost = _containsAny(identity, const <String>[
      'browser',
      'chrome',
      'chromium',
      'edge',
      'page',
    ]);
    final hasBrowserAction = _containsAny(identity, const <String>[
      'click',
      'evaluate',
      'fill',
      'hover',
      'navigate',
      'navigation',
      'press',
      'screenshot',
      'select',
      'upload',
      'wait',
    ]);
    return hasBrowserHost && hasBrowserAction;
  }

  bool _isCdpMcpTool(AiResolvedTool tool) {
    return _hasCdpMcpSignal(_mcpToolIdentity(tool));
  }

  bool _hasCdpMcpSignal(String identity) {
    return _containsAny(identity, const <String>[
          'chrome-devtools-mcp',
          'chrome devtools protocol',
          'chrome-devtools',
          'chrome_devtools',
          'devtools protocol',
          'js-reverse',
          'js_reverse',
          'javascript reverse',
          'web reverse',
        ]) ||
        _cdpIdentityTokenPattern.hasMatch(identity);
  }

  String _mcpToolIdentity(AiResolvedTool tool) {
    final server = tool.mcpServer;
    final mcpTool = tool.mcpTool;
    final parts = <Object?>[
      tool.name,
      tool.definition.name,
      tool.definition.description,
      server?.name,
      server?.summary,
      server?.command,
      if (server != null) ...server.args,
      server?.url,
      mcpTool?.id,
      mcpTool?.name,
      mcpTool?.description,
      mcpTool?.outputDescription,
      mcpTool?.annotations,
      mcpTool?.execution,
      mcpTool?.rawMetadata,
    ];
    return trimmedNonEmptyStrings(parts).join('\n').toLowerCase();
  }

  bool _containsAny(String value, Iterable<String> needles) {
    for (final needle in needles) {
      if (value.contains(needle)) return true;
    }
    return false;
  }

  String _jsonishText(Map<String, Object?> value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  Future<AiToolExecutionResult> _executeSkillTool({
    required AiResolvedTool tool,
    required AiToolCall toolCall,
    required Map<String, Object?> decodedArguments,
  }) async {
    final skill = tool.skill;
    if (skill == null) {
      return _invalidToolResult(toolCall.name, 'Missing skill metadata.');
    }
    final startedAt = Stopwatch()..start();
    final requestedTask =
        optionalStringFromValue(decodedArguments['task']) ??
        optionalStringFromValue(decodedArguments['prompt']);
    final String manifestContent;
    try {
      manifestContent = await readBoundedFileString(
        File(skill.manifestPath),
        maxBytes: skillManifestMaxBytes,
      );
    } catch (error) {
      return _invalidToolResult(
        toolCall.name,
        'Failed to read skill manifest at "${skill.manifestPath}": $error',
      );
    }
    final linkedResources = await _loadSkillLinkedResources(
      skill.directoryPath,
      manifestContent,
    );
    final buffer = StringBuffer()
      ..writeln('skill_name: ${skill.name}')
      ..writeln('description: ${skill.description}')
      ..writeln('directory: ${skill.directoryPath}')
      ..writeln('manifest_path: ${skill.manifestPath}');
    final defaultPrompt = nullIfBlank(skill.defaultPrompt);
    if (defaultPrompt != null) {
      buffer
        ..writeln('default_prompt:')
        ..writeln(skill.defaultPrompt!.trimRight());
    }
    if (requestedTask != null) {
      buffer.writeln('requested_task: $requestedTask');
    }
    buffer
      ..writeln('manifest:')
      ..writeln(manifestContent.trimRight());
    if (linkedResources.isNotEmpty) {
      buffer
        ..writeln('linked_resources:')
        ..writeln(linkedResources.trimRight());
    }
    final output = nullIfBlank(buffer.toString()) ?? '';
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: tool.name,
      workingDirectory: skill.directoryPath,
      stdout: output,
      stderr: '',
      durationMs: startedAt.elapsedMilliseconds,
      resultText: output,
      metadata: <String, Object?>{
        'tool_source': 'skill',
        'skill_id': skill.relativeDirectoryPath,
        'skill_name': skill.name,
        'skill_manifest_path': skill.manifestPath,
        'skill_directory_path': skill.directoryPath,
      },
    );
  }

  String _hookToolName(AiResolvedTool tool) {
    final builtinKind = tool.builtinKind;
    if (builtinKind != null && builtinKind.isAgentCoordinationTool) {
      return agentBuiltinToolCanonicalName(builtinKind);
    }
    return switch (builtinKind) {
      AiBuiltinToolKind.task => 'Task',
      AiBuiltinToolKind.bash => 'Bash',
      AiBuiltinToolKind.bashBackground => 'BashBackground',
      AiBuiltinToolKind.taskOutput => 'TaskOutput',
      AiBuiltinToolKind.taskStop => 'TaskStop',
      AiBuiltinToolKind.machineTerminalRead => 'MachineTerminalRead',
      AiBuiltinToolKind.machineTerminalWrite => 'MachineTerminalWrite',
      AiBuiltinToolKind.machineTerminalExec => 'MachineTerminalExec',
      AiBuiltinToolKind.machineTerminalControl => 'MachineTerminalControl',
      AiBuiltinToolKind.glob => 'Glob',
      AiBuiltinToolKind.grep => 'Grep',
      AiBuiltinToolKind.ls => 'LS',
      AiBuiltinToolKind.exitPlanMode => 'ExitPlanMode',
      AiBuiltinToolKind.read => 'Read',
      AiBuiltinToolKind.edit => 'Edit',
      AiBuiltinToolKind.multiEdit => 'MultiEdit',
      AiBuiltinToolKind.applyFileDiffs => 'ApplyFileDiffs',
      AiBuiltinToolKind.write => 'Write',
      AiBuiltinToolKind.notebookEdit => 'NotebookEdit',
      AiBuiltinToolKind.webFetch => 'WebFetch',
      AiBuiltinToolKind.todoWrite => 'TodoWrite',
      AiBuiltinToolKind.webSearch => 'WebSearch',
      AiBuiltinToolKind.lsp => 'LSP',
      AiBuiltinToolKind.codebaseSearch => 'CodebaseSearch',
      AiBuiltinToolKind.git => 'Git',
      AiBuiltinToolKind.deleteFile => 'DeleteFile',
      AiBuiltinToolKind.readLints => 'ReadLints',
      AiBuiltinToolKind.askUserChoice => 'AskUserChoice',
      AiBuiltinToolKind.skillManager => 'SkillManager',
      AiBuiltinToolKind.toolSearch => 'ToolSearch',
      AiBuiltinToolKind.memory => 'Memory',
      AiBuiltinToolKind.knowledgeSearch => 'KnowledgeSearch',
      AiBuiltinToolKind.knowledgeRead => 'KnowledgeRead',
      _ => tool.name,
    };
  }

  String _hookMatcherValue(AiResolvedTool tool, String hookToolName) {
    return switch (tool.builtinKind) {
      AiBuiltinToolKind.lsp => '$hookToolName\nLsp',
      _ => hookToolName,
    };
  }

  String _hookWorkingDirectory(Map<String, Object?> decodedArguments) {
    return optionalStringFromValue(decodedArguments['working_directory']) ??
        optionalStringFromValue(decodedArguments['cwd']) ??
        AiToolUtils.defaultWorkingDirectory();
  }

  String _effectiveWorkingDirectory(String value, {required String fallback}) {
    return nullIfBlank(value) ?? fallback;
  }

  // 所有工具来源共用同一套蛇形命名 Hook 载荷。
  Map<String, Object?> _toolHookPayload({
    required String eventName,
    required String toolName,
    required String toolSource,
    required String sessionId,
    required Map<String, Object?> toolInput,
    required String cwd,
    Map<String, Object?>? toolOutput,
  }) {
    return <String, Object?>{
      'hook_event_name': eventName,
      'session_id': sessionId,
      'cwd': cwd,
      'tool_name': toolName,
      'tool_source': toolSource,
      'tool_input': toolInput,
      if (toolOutput != null) 'tool_output': toolOutput,
    };
  }

  AiToolExecutionResult _hookBlockedToolResult({
    required String toolName,
    required Map<String, Object?> decodedArguments,
    required AiClaudeHookInvocationResult hookResult,
  }) {
    final blockReason =
        nullIfBlank(hookResult.blockReason) ?? 'Blocked by hook.';
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: toolName,
      workingDirectory: _hookWorkingDirectory(decodedArguments),
      stdout: '',
      stderr: blockReason,
      durationMs: 0,
      resultText: 'status: failed\nerror: $blockReason',
      metadata: <String, Object?>{
        'hook_blocked': true,
        'hook_block_reason': blockReason,
        'hook_event_name': 'PreToolUse',
        'hook_loaded_config_paths': hookResult.loadedConfigPaths,
        'hook_executed_commands': hookResult.executedCommands,
        if (hookResult.systemReminders.isNotEmpty)
          aiHookSystemRemindersMetadataKey: hookResult.systemReminders,
      },
    );
  }

  AiToolExecutionResult _mergeHookResultIntoToolResult({
    required AiToolExecutionResult rawResult,
    required AiClaudeHookInvocationResult preHookResult,
    required AiClaudeHookInvocationResult postHookResult,
  }) {
    final hookReminders = <String>[
      ...preHookResult.systemReminders,
      ...postHookResult.systemReminders,
    ];
    final mergedMetadata = <String, Object?>{
      ...rawResult.metadata,
      'hook_pre_executed_count': preHookResult.executedHookCount,
      'hook_post_executed_count': postHookResult.executedHookCount,
      'hook_loaded_config_paths': <String>[
        ...preHookResult.loadedConfigPaths,
        ...postHookResult.loadedConfigPaths,
      ],
      'hook_executed_commands': <String>[
        ...preHookResult.executedCommands,
        ...postHookResult.executedCommands,
      ],
    };
    if (hookReminders.isNotEmpty) {
      mergedMetadata[aiHookSystemRemindersMetadataKey] = <String>[
        ...hookReminders,
      ];
    }
    return AiToolExecutionResult(
      status: rawResult.status,
      command: rawResult.command,
      workingDirectory: rawResult.workingDirectory,
      stdout: rawResult.stdout,
      stderr: rawResult.stderr,
      durationMs: rawResult.durationMs,
      resultText: rawResult.resultText,
      exitCode: rawResult.exitCode,
      matchedRuleId: rawResult.matchedRuleId,
      matchedRulePattern: rawResult.matchedRulePattern,
      isWriteCommand: rawResult.isWriteCommand,
      writeAnalysisReason: rawResult.writeAnalysisReason,
      metadata: mergedMetadata,
    );
  }

  Future<String> _loadSkillLinkedResources(
    String skillDirectoryPath,
    String manifestContent,
  ) async {
    final linkedPaths = _markdownLinkTargetPattern
        .allMatches(manifestContent)
        .map((match) => nullIfBlank(match.group(1)))
        .whereType<String>()
        .where(
          (value) =>
              !value.startsWith('http://') &&
              !value.startsWith('https://') &&
              !value.startsWith('#'),
        )
        .toSet();
    if (linkedPaths.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (final linkedPath in linkedPaths.take(_maxSkillLinkedResources)) {
      if (p.isAbsolute(linkedPath) ||
          safeRelativePathError(linkedPath) != null) {
        continue;
      }
      final resolvedPath = p.normalize(p.join(skillDirectoryPath, linkedPath));
      if (!isPathWithinOrEqual(skillDirectoryPath, resolvedPath) ||
          !await isPhysicalPathWithinOrEqual(
            skillDirectoryPath,
            resolvedPath,
          ).timeout(
            _skillLinkedResourcePathCheckTimeout,
            onTimeout: () => false,
          )) {
        continue;
      }
      final entityType = await probeFileSystemEntityType(resolvedPath);
      if (entityType == FileSystemEntityType.notFound) {
        continue;
      }
      buffer.writeln('- path: $linkedPath');
      if (entityType == FileSystemEntityType.directory) {
        final entries = (await listDirectoryBounded(
          Directory(resolvedPath),
          maxEntries: _maxSkillLinkedDirectoryEntries,
          totalTimeout: const Duration(seconds: 3),
        )).entries.toList(growable: false);
        entries.sort((left, right) => left.path.compareTo(right.path));
        for (final entry in entries.take(20)) {
          buffer.writeln('  - ${p.basename(entry.path)}');
        }
        continue;
      }
      if (entityType != FileSystemEntityType.file) {
        continue;
      }
      try {
        final linkedFile = File(resolvedPath);
        final linkedFileLength = await AiToolUtils.fileLengthBounded(
          linkedFile,
        );
        final previewBytes = await AiToolUtils.readFilePrefix(
          linkedFile,
          linkedFileLength,
        );
        final extension = p.extension(resolvedPath).toLowerCase();
        if (AiToolUtils.looksBinary(previewBytes) &&
            !AiToolUtils.isKnownTextExtension(extension)) {
          buffer.writeln('  content: [binary file omitted]');
          if (linkedFileLength > previewBytes.length) {
            buffer.writeln(
              '  content_note: truncated binary preview (${previewBytes.length}/$linkedFileLength bytes)',
            );
          }
          continue;
        }
        final content = AiToolUtils.decodeTextBytes(previewBytes).trimRight();
        final renderedContent = AiToolUtils.truncateContent(content, 4000);
        buffer
          ..writeln('  content:')
          ..writeln(
            renderedContent.split('\n').map((line) => '    $line').join('\n'),
          );
        if (linkedFileLength > previewBytes.length) {
          buffer.writeln(
            '  content_note: truncated preview (${previewBytes.length}/$linkedFileLength bytes)',
          );
        }
      } catch (_) {
        buffer.writeln('  content: [unreadable as text]');
      }
    }
    return buffer.toString().trimRight();
  }

  String _safeToolName(String prefix, String token, Set<String> takenNames) {
    final candidate = compactToolName(prefix: prefix, token: token);
    var suffix = 1;
    var uniqueCandidate = candidate;
    while (takenNames.contains(uniqueCandidate)) {
      uniqueCandidate = appendUniqueToolNameSuffix(candidate, suffix++);
    }
    return uniqueCandidate;
  }

  AiResolvedTool _buildMcpTool({
    required McpServer server,
    required McpTool tool,
    required Set<String> takenNames,
  }) {
    final name = _safeToolName('mcp__${server.name}', tool.id, takenNames);
    final description = nullIfBlank(tool.description);
    final displayName = nullIfBlank(tool.name);
    final toolId = nullIfBlank(tool.id) ?? tool.id;
    final descriptionParts = <String>[
      'MCP tool from server "${server.name}".',
      if (description != null) description,
      if (displayName != null && displayName != toolId)
        'Display name: $displayName.',
    ];
    return AiResolvedTool(
      name: name,
      definition: AiToolDefinition(
        name: name,
        description: descriptionParts.join(' '),
        parameters: tool.inputSchema.isEmpty
            ? const <String, Object?>{'type': 'object'}
            : tool.inputSchema,
      ),
      source: AiRuntimeToolSource.mcp,
      mcpServer: server,
      mcpTool: tool,
    );
  }

  /// 技能目录只携带元数据，完整内容由对应工具按需读取。
  static const int _skillCatalogDescriptionCap = 512;

  AiResolvedTool _buildSkillTool(LocalSkill skill, Set<String> takenNames) {
    final relativeDirectoryPath = nullIfBlank(skill.relativeDirectoryPath);
    final directoryToken = relativeDirectoryPath == null
        ? ''
        : p.basename(relativeDirectoryPath);
    final token = nullIfBlank(directoryToken) == null
        ? skill.name
        : directoryToken;
    final name = _safeToolName('skill', token, takenNames);
    final rawSummary = nullIfBlank(skill.description) ?? '';
    final summary = rawSummary.length > _skillCatalogDescriptionCap
        ? '${clipTextByCodeUnits(rawSummary, _skillCatalogDescriptionCap - 1, suffix: '').trimRight()}…'
        : rawSummary;
    final description = [
      'Load the full instructions for the local skill "${skill.name}" only when the current request clearly matches it.',
      summary,
      'Do not call this unless the selected skill or its specialized workflow is required.',
      'Catalog shows summary only; this call returns the full SKILL.md body on demand.',
    ].where((item) => item.isNotEmpty).join(' ');
    return AiResolvedTool(
      name: name,
      definition: AiToolDefinition(
        name: name,
        description: description,
        parameters: const <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'task': <String, Object?>{
              'type': 'string',
              'description':
                  'Optional task or question to solve with the skill loaded.',
            },
          },
          'additionalProperties': false,
        },
      ),
      source: AiRuntimeToolSource.skill,
      skill: skill,
    );
  }

  AiToolExecutionResult _invalidToolResult(String command, String message) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.invalidArguments,
      command: command,
      workingDirectory: AiToolUtils.defaultWorkingDirectory(),
      stdout: '',
      stderr: message,
      durationMs: 0,
      resultText: 'status: invalid_arguments\nerror: $message',
    );
  }

  AiToolExecutionResult _toolExecutionErrorResult({
    required AiResolvedTool tool,
    required String fallbackWorkingDirectory,
    required Object error,
    required int durationMs,
  }) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: _toolExecutionCommand(tool),
      workingDirectory: fallbackWorkingDirectory,
      stdout: '',
      stderr: '$error',
      durationMs: durationMs,
      resultText: 'status: failed\nerror: $error',
      metadata: _toolExecutionMetadata(tool),
    );
  }

  AiToolExecutionResult _cancelledToolExecutionResult(
    AiToolExecutionResult result,
  ) {
    if (result.status == BashToolExecutionStatus.cancelled) return result;
    const message = '工具执行已取消。';
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.cancelled,
      command: result.command,
      workingDirectory: result.workingDirectory,
      stdout: result.stdout,
      stderr: result.stderr.trim().isEmpty ? message : result.stderr,
      durationMs: result.durationMs,
      resultText: 'status: cancelled\nerror: $message',
      exitCode: result.exitCode,
      matchedRuleId: result.matchedRuleId,
      matchedRulePattern: result.matchedRulePattern,
      isWriteCommand: result.isWriteCommand,
      writeAnalysisReason: result.writeAnalysisReason,
      metadata: <String, Object?>{
        ...result.metadata,
        'execution_cancelled': true,
      },
    );
  }

  String _toolExecutionCommand(AiResolvedTool tool) {
    return switch (tool.source) {
      AiRuntimeToolSource.builtin => tool.name,
      AiRuntimeToolSource.mcp =>
        '${tool.name} (${tool.mcpServer?.name ?? 'mcp'}/${tool.mcpTool?.id ?? tool.name})',
      AiRuntimeToolSource.skill => tool.name,
    };
  }

  Map<String, Object?> _toolExecutionMetadata(AiResolvedTool tool) {
    return switch (tool.source) {
      AiRuntimeToolSource.builtin => const <String, Object?>{
        'tool_source': 'builtin',
      },
      AiRuntimeToolSource.mcp => <String, Object?>{
        'tool_source': 'mcp',
        if (tool.mcpServer != null) 'mcp_server_name': tool.mcpServer!.name,
        if (tool.mcpTool != null) ...<String, Object?>{
          'mcp_tool_id': tool.mcpTool!.id,
          'mcp_tool_name': tool.mcpTool!.name,
        },
      },
      AiRuntimeToolSource.skill => <String, Object?>{
        'tool_source': 'skill',
        if (tool.skill != null) ...<String, Object?>{
          'skill_id': tool.skill!.relativeDirectoryPath,
          'skill_name': tool.skill!.name,
          'skill_manifest_path': tool.skill!.manifestPath,
          'skill_directory_path': tool.skill!.directoryPath,
        },
      },
    };
  }

  Future<void> shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    _isShuttingDown = true;
    _executionSlots.cancelWaiters();
    for (final abort in _activeExecutionAborts.toList(growable: false)) {
      if (!abort.isCompleted) abort.complete();
    }
    _activeExecutionAborts.clear();
    _subToolExecutionObserver = null;
    _fileTrackers.clear();
    return _shutdownFuture = _finishShutdown();
  }

  Future<Completer<void>?> _beginExecution(Future<void>? cancelSignal) async {
    if (_isShuttingDown) throw StateError('AI 工具运行时已关闭。');
    late final bool acquired;
    try {
      acquired = await _executionSlots.acquireWithin(
        _toolExecutionQueueTimeout,
        cancelSignal: cancelSignal,
      );
    } on StateError {
      if (_isShuttingDown) throw StateError('AI 工具运行时已关闭。');
      throw StateError('AI 工具执行排队已满。');
    }
    if (!acquired) {
      if (_isShuttingDown) throw StateError('AI 工具运行时已关闭。');
      if (await isCancelSignalCompleted(cancelSignal)) return null;
      throw TimeoutException('AI 工具执行排队超时。', _toolExecutionQueueTimeout);
    }
    if (_isShuttingDown) {
      _executionSlots.release();
      throw StateError('AI 工具运行时已关闭。');
    }
    final abort = Completer<void>();
    _activeExecutionAborts.add(abort);
    return abort;
  }

  void _finishExecution(Completer<void> abort) {
    if (!abort.isCompleted) abort.complete();
    _activeExecutionAborts.remove(abort);
    _executionSlots.release();
  }

  Future<void> _finishShutdown() async {
    // 先释放工具实例，再关闭 Scrapling，避免工具销毁过程中继续使用桥接进程。
    await runAsyncCleanupBounded(
      _toolRegistry.dispose,
      onError: (error, stack) =>
          silentLog('ai_tool_runtime_service', '关闭工具注册表', error, stack),
    );
    await runAsyncCleanupBounded(
      _scraplingBridge.dispose,
      onError: (error, stack) => silentLog(
        'ai_tool_runtime_service',
        '关闭 Scrapling 桥接进程',
        error,
        stack,
      ),
    );
    if (_ownsHttpClient) {
      await runAsyncCleanupBounded(
        _httpClient.close,
        onError: (error, stack) =>
            silentLog('ai_tool_runtime_service', '关闭 HTTP 客户端', error, stack),
      );
    }
  }

  void dispose() {
    unawaited(
      shutdown().catchError((Object error, StackTrace stack) {
        silentLog('ai_tool_runtime_service', '关闭工具运行时', error, stack);
      }),
    );
  }

  static final List<AiResolvedTool> _builtinTools = <AiResolvedTool>[
    _builtinTool(
      kind: AiBuiltinToolKind.task,
      name: 'Task',
      description:
          'Launch a focused, stateless background sub-agent. Set description to a short title, prompt to the complete task, and optionally set subagent_type to declare the goal: '
          '`research` (read-only multi-file exploration), '
          '`verify` (run tests/lints/builds and report pass/fail), '
          '`summarize` (compress long output into a structured digest), '
          '`advice` (compare design options and recommend), '
          'or `general-purpose` (default fallback when omitted). Each call is isolated and receives a restricted sub-tool catalog: no file editing tools, TodoWrite, ExitPlanMode, AskUserChoice, Memory, ToolSearch, or MCP tools. '
          'Local skill tools are also parent-thread only. '
          'Write-like Bash commands are blocked inside every Task sub-agent; the parent agent must perform writes directly when appropriate. '
          'Only read-only subagent types (`research`, `summarize`, `advice`) may run in parallel with sibling tool calls.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'description': <String, Object?>{
            'type': 'string',
            'maxLength': kAiTaskDescriptionMaxCharacters,
            'description':
                'Short task title for hook logs and parent transcript.',
          },
          'prompt': <String, Object?>{
            'type': 'string',
            'maxLength': kAiTaskPromptMaxCharacters,
            'description':
                'Complete subtask instructions, including scope, paths, constraints, and expected output.',
          },
          'subagent_type': <String, Object?>{
            'type': 'string',
            'description':
                'Optional sub-agent profile to use for this isolated Task invocation. If omitted, general-purpose is used.',
            'enum': <String>[
              'general-purpose',
              'research',
              'verify',
              'summarize',
              'advice',
            ],
          },
        },
        'required': <String>['description', 'prompt'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.bash,
      name: 'Bash',
      description:
          'Fallback for shell-only commands; do not use for file read/search/list/edit when Read, Grep, Glob, LS, or Edit-family tools are available. Use command (Claude-style) or cmd for the command string and optionally working_directory/cwd for the working directory. Set run_in_background to true for Claude-style long-running commands that should be started through BashBackground. '
          'Use Bash for tests, builds, package managers, project scripts, and commands with no dedicated OpenHand tool. '
          'If a write-like command needs confirmation, OpenHand handles that approval flow automatically.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'command': <String, Object?>{
            'type': 'string',
            'description': 'Command to execute. Claude-style alias for cmd.',
          },
          'cmd': <String, Object?>{
            'type': 'string',
            'description':
                'Command to execute. Kept for OpenHand compatibility.',
          },
          'working_directory': <String, Object?>{'type': 'string'},
          'cwd': <String, Object?>{
            'type': 'string',
            'description': 'Working directory. Alias for working_directory.',
          },
          'timeout': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 600000,
          },
          'timeout_ms': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 600000,
            'description': 'Timeout in milliseconds. Alias for timeout.',
          },
          'description': <String, Object?>{
            'type': 'string',
            'description':
                'Optional concise active-voice description of what this command does.',
          },
          'run_in_background': <String, Object?>{
            'type': 'boolean',
            'description':
                'When true, route this command to BashBackground start and return a background handle instead of waiting for completion.',
          },
          'dangerouslyDisableSandbox': <String, Object?>{
            'type': 'boolean',
            'description':
                'Claude-style sandbox override. OpenHand honors this only when sandbox settings allow unsandboxed commands; otherwise the call is denied.',
          },
        },
        'anyOf': <Object?>[
          <String, Object?>{
            'required': <String>['command'],
          },
          <String, Object?>{
            'required': <String>['cmd'],
          },
        ],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.bashBackground,
      name: 'BashBackground',
      description:
          'Manage long-running background shell processes (dev servers, REPLs, watchers). '
          'Pick `action`: '
          '`start` (cmd + optional working_directory → returns a `handle`), '
          '`write` (handle + input → send a line to the process stdin), '
          '`read` (handle + optional max_bytes → drain new stdout/stderr since last read and report alive/exit_code), '
          '`stop` (handle → SIGKILL), '
          '`list` (no args → enumerate active sessions). '
          'If `start` is write-like, OpenHand runs the same PermissionRequest/write-confirmation gate before spawning. '
          'Use this instead of Bash when the command would block the agent loop indefinitely.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>['start', 'write', 'read', 'stop', 'list'],
          },
          'cmd': <String, Object?>{'type': 'string'},
          'working_directory': <String, Object?>{'type': 'string'},
          'handle': <String, Object?>{'type': 'string'},
          'input': <String, Object?>{'type': 'string'},
          'block': <String, Object?>{'type': 'boolean'},
          'timeout': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 600000,
          },
          'timeout_ms': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 600000,
          },
          'max_bytes': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 65536,
          },
        },
        'required': <String>['action'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.taskOutput,
      name: 'TaskOutput',
      description:
          'Claude-style compatibility tool for reading output from an OpenHand background shell task. '
          'Use task_id with the BashBackground handle returned by Bash(run_in_background=true) or BashBackground start. '
          'block defaults to true and waits until the task exits or timeout elapses; set block=false for a non-blocking status/output check. '
          'This is routed internally to BashBackground read.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'task_id': <String, Object?>{
            'type': 'string',
            'description':
                'Background task ID. In OpenHand this is the BashBackground handle, e.g. bg_1.',
          },
          'handle': <String, Object?>{
            'type': 'string',
            'description': 'OpenHand alias for task_id.',
          },
          'block': <String, Object?>{
            'type': 'boolean',
            'description':
                'Whether to wait for completion before returning. Defaults to true.',
          },
          'timeout': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 600000,
            'description':
                'Maximum wait time in milliseconds when block=true. Defaults to 30000 and is capped at 600000.',
          },
          'timeout_ms': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 600000,
            'description': 'Alias for timeout.',
          },
          'max_bytes': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 65536,
            'description':
                'Maximum stdout/stderr bytes to drain from each stream.',
          },
        },
        'anyOf': <Object?>[
          <String, Object?>{
            'required': <String>['task_id'],
          },
          <String, Object?>{
            'required': <String>['handle'],
          },
        ],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.taskStop,
      name: 'TaskStop',
      description:
          'Stop an OpenHand background shell task. Use task_id with the handle returned by Bash(run_in_background=true) or BashBackground start.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'task_id': <String, Object?>{
            'type': 'string',
            'description':
                'Background task ID. In OpenHand this is the BashBackground handle, e.g. bg_1.',
          },
          'shell_id': <String, Object?>{
            'type': 'string',
            'description': 'Deprecated alias for task_id.',
          },
          'handle': <String, Object?>{
            'type': 'string',
            'description': 'OpenHand alias for task_id.',
          },
        },
        'anyOf': <Object?>[
          <String, Object?>{
            'required': <String>['task_id'],
          },
          <String, Object?>{
            'required': <String>['shell_id'],
          },
          <String, Object?>{
            'required': <String>['handle'],
          },
        ],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.machineTerminalRead,
      name: 'MachineTerminalRead',
      description:
          'Machine Expert only. Read the active OpenHand terminal state and recent output without starting or switching terminals.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'terminal_id': <String, Object?>{
            'type': 'string',
            'description':
                'Optional active terminal id. Inactive terminal targets are rejected.',
          },
        },
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.machineTerminalWrite,
      name: 'MachineTerminalWrite',
      description:
          'Machine Expert only. Write bounded interactive input to the active OpenHand terminal. Session-exit commands, EOF/job-control characters, SSH disconnect escapes, and inactive terminal targets are rejected.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'terminal_id': <String, Object?>{
            'type': 'string',
            'description':
                'Optional active terminal id. Inactive terminal targets are rejected.',
          },
          'data': <String, Object?>{
            'type': 'string',
            'description': 'Raw text to write to the terminal.',
          },
          'input': <String, Object?>{
            'type': 'string',
            'description': 'Alias for data.',
          },
          'text': <String, Object?>{
            'type': 'string',
            'description': 'Alias for data.',
          },
          'append_newline': <String, Object?>{
            'type': 'boolean',
            'description': 'Append Enter/newline after data.',
          },
          'enter': <String, Object?>{
            'type': 'boolean',
            'description': 'Alias for append_newline.',
          },
        },
        'anyOf': <Object?>[
          <String, Object?>{
            'required': <String>['data'],
          },
          <String, Object?>{
            'required': <String>['input'],
          },
          <String, Object?>{
            'required': <String>['text'],
          },
        ],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.machineTerminalExec,
      name: 'MachineTerminalExec',
      description:
          'Machine Expert only. Execute a non-interactive command in the active OpenHand terminal and return marker-isolated output. Timeouts send an interrupt to the command and never restart the terminal.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'terminal_id': <String, Object?>{
            'type': 'string',
            'description':
                'Optional active terminal id. Inactive terminal targets are rejected.',
          },
          'command': <String, Object?>{
            'type': 'string',
            'description': 'Shell command to run in the terminal.',
          },
          'cmd': <String, Object?>{
            'type': 'string',
            'description': 'Alias for command.',
          },
          'timeout_ms': <String, Object?>{
            'type': 'integer',
            'minimum': 1000,
            'maximum': 600000,
          },
          'timeout': <String, Object?>{
            'type': 'integer',
            'minimum': 1000,
            'maximum': 600000,
            'description': 'Alias for timeout_ms.',
          },
        },
        'anyOf': <Object?>[
          <String, Object?>{
            'required': <String>['command'],
          },
          <String, Object?>{
            'required': <String>['cmd'],
          },
        ],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.machineTerminalControl,
      name: 'MachineTerminalControl',
      description:
          'Machine Expert only. Clear or resize the active OpenHand terminal. All lifecycle and target-selection actions are user-owned and rejected.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>['clear', 'resize'],
          },
          'terminal_id': <String, Object?>{
            'type': 'string',
            'description':
                'Optional active terminal id. Inactive terminal targets are rejected.',
          },
          'columns': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 400,
            'description': 'Terminal columns for action=resize.',
          },
          'rows': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 240,
            'description': 'Terminal rows for action=resize.',
          },
        },
        'required': <String>['action'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.glob,
      name: 'Glob',
      description:
          'Match file paths against a glob pattern. Returns relative matching file paths sorted by modification time, capped at 100 results.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'pattern': <String, Object?>{
            'type': 'string',
            'description':
                'The glob pattern to match (e.g. "*.md", "**/*.dart").',
          },
          'path': <String, Object?>{
            'type': 'string',
            'description':
                'The directory to search in. Omit to use the working directory; do not pass a file path.',
          },
        },
        'required': <String>['pattern'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.lsp,
      name: 'LSP',
      description:
          'Code intelligence (definitions, references, symbols, hover) based on LSP.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'operation': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'goToDefinition',
              'findReferences',
              'hover',
              'documentSymbol',
              'workspaceSymbol',
              'goToImplementation',
              'prepareCallHierarchy',
              'incomingCalls',
              'outgoingCalls',
            ],
            'description': 'The LSP operation to perform',
          },
          'file_path': <String, Object?>{
            'type': 'string',
            'description':
                'OpenHand alias for filePath. The absolute or relative path to the file',
          },
          'filePath': <String, Object?>{
            'type': 'string',
            'description':
                'Claude-style file path field. The absolute or relative path to the file',
          },
          'line': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'description': 'The line number (1-based, as shown in editors)',
          },
          'character': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'description':
                'The character offset (1-based, as shown in editors)',
          },
        },
        'required': <String>['operation', 'line', 'character'],
        'anyOf': <Object>[
          <String, Object?>{
            'required': <String>['filePath'],
          },
          <String, Object?>{
            'required': <String>['file_path'],
          },
        ],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.grep,
      name: 'Grep',
      description:
          'Search file contents using ripgrep-compatible arguments. '
          'Always backed by the application-bundled `rg` (ripgrep) binary on '
          'every platform — never falls back to POSIX `grep` — so PCRE2 '
          'character classes, `--multiline`, `--type`, and `--glob` are '
          'available without any host installation. Prefer this tool over '
          'shelling out to `grep`/`rg` via Bash.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'pattern': <String, Object?>{'type': 'string'},
          'path': <String, Object?>{'type': 'string'},
          'glob': <String, Object?>{
            'type': 'string',
            'description':
                'Glob pattern(s) to filter files. Comma or space separated patterns are split unless the pattern uses braces.',
          },
          'output_mode': <String, Object?>{
            'type': 'string',
            'enum': <String>['content', 'files_with_matches', 'count'],
          },
          '-B': <String, Object?>{'type': 'integer', 'minimum': 0},
          '-A': <String, Object?>{'type': 'integer', 'minimum': 0},
          '-C': <String, Object?>{'type': 'integer', 'minimum': 0},
          'context': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'description': 'Claude-style alias for -C context lines.',
          },
          '-n': <String, Object?>{
            'type': 'boolean',
            'description':
                'Show line numbers in content output. Defaults to true.',
          },
          '-i': <String, Object?>{'type': 'boolean'},
          'type': <String, Object?>{'type': 'string'},
          'head_limit': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'description':
                'Limit output to the first N lines or entries after offset. Defaults to 250; pass 0 only when unlimited output is intentional.',
          },
          'offset': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'description':
                'Skip the first N output lines or entries before applying head_limit.',
          },
          'multiline': <String, Object?>{'type': 'boolean'},
        },
        'required': <String>['pattern'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.ls,
      name: 'LS',
      description:
          'List files and directories under a directory path. Accepts absolute or relative paths and returns names with types.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'path': <String, Object?>{
            'type': 'string',
            'description':
                'The directory path to list. Omit to use the working directory; do not pass a file path.',
          },
          'ignore': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description':
                'Glob patterns of file/directory names or paths to ignore.',
          },
        },
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.exitPlanMode,
      name: 'ExitPlanMode',
      description:
          'Signal that planning is complete and implementation can begin. The plan argument is preferred and should be a short numbered or bulleted execution step list; when omitted, the runtime can recover from current plan context.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'plan': <String, Object?>{
            'type': 'string',
            'description':
                'Preferred concise numbered or bulleted execution plan. Optional only when current plan context can recover it.',
          },
          'allowed_prompts': <String, Object?>{
            'type': 'array',
            'description':
                'Optional semantic Bash action categories needed to implement the plan; records intent only and does not bypass runtime confirmation.',
            'items': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'tool': <String, Object?>{
                  'type': 'string',
                  'enum': <String>['Bash'],
                },
                'prompt': <String, Object?>{
                  'type': 'string',
                  'description':
                      'Short semantic action category, e.g. run tests or build web assets; not a concrete command.',
                },
              },
              'required': <String>['tool', 'prompt'],
              'additionalProperties': false,
            },
          },
          'allowedPrompts': <String, Object?>{
            'type': 'array',
            'description':
                'CamelCase alias for allowed_prompts; prefer allowed_prompts in OpenHand prompts.',
            'items': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'tool': <String, Object?>{
                  'type': 'string',
                  'enum': <String>['Bash'],
                },
                'prompt': <String, Object?>{'type': 'string'},
              },
              'required': <String>['tool', 'prompt'],
              'additionalProperties': false,
            },
          },
        },
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.read,
      name: 'Read',
      description:
          'Read a local file from disk. Accepts absolute or relative file_path values and resolves them against the working directory. '
          'Refuses special device paths that may block or produce infinite output. '
          'macOS screenshot paths are retried with regular/thin-space AM/PM variants when the requested path is missing. '
          'Full image/PDF/notebook rendering is bounded; oversized structured files return metadata only.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{
            'type': 'string',
            'description': _filePathResolvedAgainstCwdDescription,
          },
          'offset': <String, Object?>{
            'type': 'integer',
            'description':
                '1-based line number to start reading from. Values <= 1 start at the first line.',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 20000,
            'description':
                'Maximum number of lines to read. Defaults to 2000, capped at 20000.',
          },
          'pages': <String, Object?>{
            'anyOf': <Object?>[
              <String, Object?>{'type': 'string'},
              <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{
                  'anyOf': <Object?>[
                    <String, Object?>{'type': 'string'},
                    <String, Object?>{'type': 'integer'},
                  ],
                },
              },
            ],
            'description':
                'Claude-style PDF page range such as "1", "1-5", "1,3-5", or ["1","3-5"]. Maximum 20 pages. Current runtime returns PDF metadata and the requested range, not extracted page text.',
          },
        },
        'required': <String>['file_path'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.edit,
      name: 'Edit',
      description:
          'Perform an exact string replacement in a file. '
          'Accepts absolute or relative file_path values and resolves them against the working directory. '
          'Jupyter Notebook .ipynb cell changes must use NotebookEdit instead.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{
            'type': 'string',
            'description': _filePathResolvedAgainstCwdDescription,
          },
          'old_string': <String, Object?>{
            'type': 'string',
            'description':
                'The exact text to find and replace. Must match exactly once unless replace_all is true. Empty old_string is allowed only to create a new file or replace an empty file.',
          },
          'new_string': <String, Object?>{
            'type': 'string',
            'description': 'The replacement text.',
          },
          'replace_all': <String, Object?>{
            'type': 'boolean',
            'description':
                'If true, replace all occurrences. Defaults to false. Not valid with empty old_string.',
          },
        },
        'required': <String>['file_path', 'old_string', 'new_string'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.multiEdit,
      name: 'MultiEdit',
      description:
          'Perform multiple exact string replacements in a file. '
          'Accepts absolute or relative file_path values and resolves them against the working directory. '
          'For a new or empty file, the first edit may use empty old_string to seed the file content. '
          'Jupyter Notebook .ipynb cell changes must use NotebookEdit instead.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{
            'type': 'string',
            'description': _filePathResolvedAgainstCwdDescription,
          },
          'edits': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'old_string': <String, Object?>{
                  'type': 'string',
                  'description':
                      'Exact text to replace. Empty old_string is allowed only for the first edit when creating a new or empty file.',
                },
                'new_string': <String, Object?>{'type': 'string'},
                'replace_all': <String, Object?>{
                  'type': 'boolean',
                  'description':
                      'If true, replace every occurrence. Not valid with empty old_string.',
                },
              },
              'required': <String>['old_string', 'new_string'],
              'additionalProperties': false,
            },
          },
        },
        'required': <String>['file_path', 'edits'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.applyFileDiffs,
      name: 'ApplyFileDiffs',
      description:
          'Apply hunk-level edits across multiple files in one atomic call. '
          'Use when a single logical change touches >1 file (rename, signature update, config sync). '
          'Each diff has `file_path` + `hunks` (array of {old_string, new_string, replace_all?}). '
          'Plans all hunks in memory and collects all confirmations before writing; if any hunk fails or confirmation is denied, no file is written. '
          'If a write or verification fails after writing starts, previously written files are rolled back best-effort. '
          'Accepts absolute or relative file_path values and resolves them against the working directory. '
          'Jupyter Notebook .ipynb cell changes must use NotebookEdit instead. Up to 32 files per call.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'diffs': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'file_path': <String, Object?>{
                  'type': 'string',
                  'description': _filePathResolvedAgainstCwdDescription,
                },
                'hunks': <String, Object?>{
                  'type': 'array',
                  'items': <String, Object?>{
                    'type': 'object',
                    'properties': <String, Object?>{
                      'old_string': <String, Object?>{
                        'type': 'string',
                        'description':
                            'Exact text to replace. Empty old_string is allowed only for the first hunk when creating a new or empty file.',
                      },
                      'new_string': <String, Object?>{'type': 'string'},
                      'replace_all': <String, Object?>{
                        'type': 'boolean',
                        'description':
                            'If true, replace every occurrence. Not valid with empty old_string.',
                      },
                    },
                    'required': <String>['old_string', 'new_string'],
                    'additionalProperties': false,
                  },
                },
              },
              'required': <String>['file_path', 'hunks'],
              'additionalProperties': false,
            },
          },
        },
        'required': <String>['diffs'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.write,
      name: 'Write',
      description:
          'Create or overwrite a file on disk. Accepts absolute or relative file_path values and resolves them against the working directory. '
          'Parent directories are created automatically if they do not exist. '
          'Arguments must be a flat JSON object with exactly two string keys. '
          'Example: {"file_path":"src/hello.txt","content":"hello world"}',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{
            'type': 'string',
            'description':
                'The absolute or relative file path to write to. Relative paths are resolved against the working directory.',
          },
          'content': <String, Object?>{
            'type': 'string',
            'description': 'The full content to write to the file.',
          },
        },
        'required': <String>['file_path', 'content'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.notebookEdit,
      name: 'NotebookEdit',
      description:
          'Edit a Jupyter notebook cell. `new_source` is used for replace/insert and ignored for delete.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'notebook_path': <String, Object?>{
            'type': 'string',
            'description':
                'The absolute or relative path to the .ipynb file. Relative paths are resolved against the working directory.',
          },
          'cell_id': <String, Object?>{
            'type': 'string',
            'description':
                'Target cell id. Required for replace/delete; optional insertion anchor for insert.',
          },
          'new_source': <String, Object?>{
            'type': 'string',
            'description':
                'Replacement or inserted cell source. Required for replace/insert; ignored for delete.',
          },
          'cell_type': <String, Object?>{
            'type': 'string',
            'enum': <String>['code', 'markdown', 'raw'],
            'description':
                'Cell type override. Required for insert; optional for replace.',
          },
          'edit_mode': <String, Object?>{
            'type': 'string',
            'enum': <String>['replace', 'insert', 'delete'],
            'description': 'Defaults to replace.',
          },
        },
        'required': <String>['notebook_path'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.webFetch,
      name: 'WebFetch',
      description:
          'Fetch a URL with configured engines, then answer a prompt against the fetched content.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'url': <String, Object?>{'type': 'string'},
          'prompt': <String, Object?>{'type': 'string'},
        },
        'required': <String>['url', 'prompt'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.todoWrite,
      name: 'TodoWrite',
      description:
          'Create or update the structured todo list for the current task. '
          'The "todos" parameter MUST be a JSON array of objects — NOT an XML-style wrapper like {"item":[...]}. '
          'Each object needs content (string) and status '
          '("pending"|"in_progress"|"completed"; legacy "failed" is accepted only for recovery/UI compatibility); id is optional and generated when omitted. '
          'activeForm is recommended for Claude-style progress wording. At most one in_progress at a time. '
          'Example: {"todos":[{"content":"Step A","status":"in_progress","activeForm":"Working on Step A"},{"content":"Step B","status":"pending"}]}',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'todos': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'content': <String, Object?>{'type': 'string'},
                'status': <String, Object?>{
                  'type': 'string',
                  'enum': <String>[
                    'pending',
                    'in_progress',
                    'completed',
                    'failed',
                  ],
                },
                'id': <String, Object?>{'type': 'string'},
                'activeForm': <String, Object?>{'type': 'string'},
                'active_form': <String, Object?>{'type': 'string'},
              },
              'required': <String>['content', 'status'],
              'additionalProperties': false,
            },
          },
        },
        'required': <String>['todos'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.webSearch,
      name: 'WebSearch',
      description:
          'Search the web for current information. The "query" parameter MUST be a plain string '
          '(no XML, no CDATA, no nested objects). Minimum 2 characters. '
          'Example: {"query":"Three.js voxel minecraft tutorial 2025"}',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{'type': 'string'},
          'allowed_domains': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
          },
          'blocked_domains': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
          },
        },
        'required': <String>['query'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.codebaseSearch,
      name: 'CodebaseSearch',
      description:
          'Semantic code search: finds relevant code snippets by natural language query. '
          'Uses multi-signal weighted matching (keyword extraction, pattern grep, filename glob). '
          'Best for discovering code by intent when you don\'t know the exact text.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'description':
                'Natural language query describing the code you are looking for.',
          },
          'path': <String, Object?>{
            'type': 'string',
            'description':
                'Optional directory to scope the search (absolute or relative).',
          },
          'target_directories': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description':
                'Optional Claude-style directory list. The first non-empty directory is used when path is omitted.',
          },
          'file_pattern': <String, Object?>{
            'type': 'string',
            'description':
                'Optional glob pattern to filter files (e.g. "*.dart", "*.ts").',
          },
        },
        'required': <String>['query'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.git,
      name: 'Git',
      description:
          'Structured read-only Git operations. Supports: status, diff, log, blame, show, branch, stash_list. '
          'For write operations (commit, push, rebase) use the Bash tool instead.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'operation': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'status',
              'diff',
              'log',
              'blame',
              'show',
              'branch',
              'stash_list',
            ],
            'description': 'The Git operation to perform.',
          },
          'target': <String, Object?>{
            'type': 'string',
            'description':
                'Target ref, commit hash, or file path depending on operation.',
          },
          'working_directory': <String, Object?>{
            'type': 'string',
            'description':
                'Directory to run git from. Omit to use the working directory.',
          },
          'file_path': <String, Object?>{
            'type': 'string',
            'description': 'File path for blame or scoped diff.',
          },
          'staged': <String, Object?>{
            'type': 'boolean',
            'description': 'For diff: show staged changes only.',
          },
          'count': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 100,
            'description': 'For log: max number of commits to show.',
          },
          'author': <String, Object?>{
            'type': 'string',
            'description': 'For log: filter by author.',
          },
          'since': <String, Object?>{
            'type': 'string',
            'description': 'For log: show commits since this date.',
          },
          'start_line': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'description': 'For blame: start line (1-based).',
          },
          'end_line': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'description': 'For blame: end line (1-based).',
          },
        },
        'required': <String>['operation'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.deleteFile,
      name: 'DeleteFile',
      description:
          'Delete a single file from disk. Cannot delete directories. '
          'Blocked for system-critical paths (/System, /usr, /bin, /sbin, /etc, home root).',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{
            'type': 'string',
            'description': _filePathResolvedAgainstCwdDescription,
          },
          'target_file': <String, Object?>{
            'type': 'string',
            'description':
                'Legacy alias for file_path. Prefer file_path for new calls.',
          },
        },
        'anyOf': <Object>[
          <String, Object?>{
            'required': <String>['file_path'],
          },
          <String, Object?>{
            'required': <String>['target_file'],
          },
        ],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.readLints,
      name: 'ReadLints',
      description:
          'Read diagnostics and lint errors from the workspace. '
          'Runs flutter analyze / dart analyze and returns structured results. '
          'Optionally scoped to specific file paths.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'paths': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description':
                'Optional list of file or directory paths to analyze. If empty, analyzes the whole workspace.',
          },
          'working_directory': <String, Object?>{
            'type': 'string',
            'description':
                'Directory to run analysis from. Relative paths are resolved against the default working directory.',
          },
        },
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.askUserChoice,
      name: 'AskUserChoice',
      description:
          'Ask the user to make a single choice via a modal dialog when you '
          'need them to pick from a small, well-defined list of options. The '
          'dialog always exposes the predefined `options` as radio choices and '
          '(unless `allow_custom_input` is false) an extra "custom input" '
          'radio that lets the user type a free-form answer. Prefer this over '
          'phrasing multi-choice questions in plain chat text whenever a '
          'deterministic, machine-readable answer is required (e.g. brainstorm '
          'direction picking, confirming which of N candidate paths to use). '
          'In Plan mode, use this only to clarify requirements or choose '
          'between approaches before finalizing the plan; do not ask whether '
          'the plan is approved or whether implementation should proceed. '
          'Use ExitPlanMode for plan approval. '
          'Returns JSON `{"value": "...", "is_custom": true|false}`.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'title': <String, Object?>{
            'type': 'string',
            'description': 'Short dialog title shown as the question headline.',
          },
          'description': <String, Object?>{
            'type': 'string',
            'description':
                'Optional longer description or context displayed below the title.',
          },
          'options': <String, Object?>{
            'type': 'array',
            'minItems': 1,
            'items': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'value': <String, Object?>{
                  'type': 'string',
                  'description':
                      'Machine-readable identifier returned when the user picks this option.',
                },
                'label': <String, Object?>{
                  'type': 'string',
                  'description':
                      'Human-readable primary label shown in the radio tile.',
                },
                'description': <String, Object?>{
                  'type': 'string',
                  'description':
                      'Optional secondary helper text shown beneath the label.',
                },
              },
              'required': <String>['value', 'label'],
              'additionalProperties': false,
            },
          },
          'allow_custom_input': <String, Object?>{
            'type': 'boolean',
            'description':
                'Whether to also show a "custom input" radio with a free-form text field. Defaults to true.',
          },
          'confirm_label': <String, Object?>{
            'type': 'string',
            'description': 'Optional override for the confirm button label.',
          },
          'cancel_label': <String, Object?>{
            'type': 'string',
            'description': 'Optional override for the cancel button label.',
          },
          'custom_option_label': <String, Object?>{
            'type': 'string',
            'description':
                'Optional override for the label displayed on the custom-input radio.',
          },
          'custom_input_hint': <String, Object?>{
            'type': 'string',
            'description':
                'Optional placeholder hint inside the free-form text field.',
          },
        },
        'required': <String>['title', 'options'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.skillManager,
      name: 'SkillManager',
      description:
          'Manage AI skills on disk. Skills live under the user-configured '
          'skills directory as `[<category>/]<name>/SKILL.md` with a YAML '
          'frontmatter (name + description required). Supported actions: '
          '`create`, `edit`, `delete`, `patch`, `write_file`, `remove_file`. '
          'Prefer `patch` (unique-match substring replace) over `edit` '
          '(full rewrite). `write_file`/`remove_file` are restricted to the '
          '{references, templates, scripts, assets} sub-directories of an '
          'existing skill. Confirm with the user before calling `delete`. '
          'ANTI-FRAGMENTATION: before `create`, scan the existing skill '
          'catalog; if any skill already covers — even partially — the '
          'workflow you are about to save, you MUST extend it via `patch` '
          'or `edit` instead of creating an overlapping sibling. Two skills '
          'whose descriptions would trigger on the same request is a bug. '
          'When unsure, do nothing rather than fragmenting the catalog.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'create',
              'edit',
              'delete',
              'patch',
              'write_file',
              'remove_file',
            ],
          },
          'name': <String, Object?>{
            'type': 'string',
            'description':
                'Skill name. Must match ^[a-z0-9][a-z0-9._-]*\$, length <= 64, '
                'globally unique across categories.',
          },
          'category': <String, Object?>{
            'type': 'string',
            'description':
                'Optional single-segment category directory name (same '
                'regex/length rules as `name`). Only used by `create`.',
          },
          'content': <String, Object?>{
            'type': 'string',
            'description':
                'For `create`/`edit`: full SKILL.md content (must begin with '
                'a `---\\n...\\n---\\n` frontmatter block containing `name` '
                'and `description`, body non-empty, total <= 100000 chars). '
                'For `write_file`: the file contents to write.',
          },
          'old_string': <String, Object?>{
            'type': 'string',
            'description':
                'For `patch`: the exact substring to replace. Must match '
                'exactly once unless `replace_all` is true.',
          },
          'new_string': <String, Object?>{
            'type': 'string',
            'description': 'For `patch`: the replacement text.',
          },
          'replace_all': <String, Object?>{
            'type': 'boolean',
            'description':
                'For `patch`: when true, replace every occurrence. Defaults '
                'to false (unique-match required).',
          },
          'file_path': <String, Object?>{
            'type': 'string',
            'description':
                'For `patch`/`write_file`/`remove_file`: relative path within '
                'the skill directory. Must start with one of '
                '{references, templates, scripts, assets}. Omit (or empty) '
                'when patching SKILL.md.',
          },
        },
        'required': <String>['action', 'name'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.toolSearch,
      name: 'ToolSearch',
      description:
          'Search and invoke deferred runtime tools through one stable gateway. '
          'Deferred MCP and built-in schemas stay out of the native tool list '
          'to preserve prompt-cache reuse. Search by exact name when known or '
          'by task keywords.\n\n'
          'Query forms:\n'
          '- `select:Name1,Name2` — fetch these exact tools by name (best '
          'when you already know the tool name).\n'
          '- `slack send` — keyword search; ranks deferred tools by '
          'matches against their name parts and descriptions.\n'
          '- `+github issues list` — prefix a term with `+` to make it '
          'required; remaining terms refine the ranking.\n\n'
          'Search result: matched tools are returned as structured JSON with a '
          '`functions` array. Each entry contains `name`, `description`, and '
          '`parameters`. To invoke one, call ToolSearch again with `tool_name` '
          'set to the exact returned name and `arguments` matching its schema. '
          'Do not call the deferred name as a native tool. Search mode is '
          'read-only; gateway invocation has the selected tool\'s effects.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'maxLength': kAiToolSearchMaxQueryCharacters,
            'description':
                'Either `select:NAME[,NAME...]` for direct selection or one '
                'or more keywords. Prefix a term with `+` to require it.',
          },
          'max_results': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 50,
            'description': 'Maximum matches to return (default 5).',
          },
          'tool_name': <String, Object?>{
            'type': 'string',
            'description':
                'Exact deferred tool name returned by a previous ToolSearch query.',
          },
          'arguments': <String, Object?>{
            'type': 'object',
            'description':
                'Arguments matching the selected deferred tool JSON Schema.',
            'additionalProperties': true,
          },
        },
        'anyOf': <Object?>[
          <String, Object?>{
            'required': <String>['query'],
          },
          <String, Object?>{
            'required': <String>['tool_name', 'arguments'],
          },
        ],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.knowledgeSearch,
      name: 'KnowledgeSearch',
      description:
          'Read-only ranked search over local OpenHand Knowledge Base chunks. '
          'Use this as the Knowledge Base search path; it returns chunk_id values ranked by chunk content, title, and heading. '
          'If any returned title, heading, or preview matches the question, use that row as evidence and ignore unrelated lower-ranked rows. '
          'Call KnowledgeRead with a returned chunk_id when exact chunk content is needed. '
          'Do not use filesystem Read/Grep on source paths as a substitute for Knowledge Base retrieval.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'maxLength': kAiKnowledgeSearchMaxQueryCharacters,
            'description': 'Natural language or exact text query.',
          },
          'tags': <String, Object?>{
            'type': 'array',
            'maxItems': kAiKnowledgeSearchMaxTags,
            'items': <String, Object?>{
              'type': 'string',
              'maxLength': kAiKnowledgeTagMaxCharacters,
            },
            'description':
                'Optional exact tag filters. Every provided tag must match.',
          },
          'date_from': <String, Object?>{
            'type': 'string',
            'description': 'Optional ISO date lower bound.',
          },
          'date_to': <String, Object?>{
            'type': 'string',
            'description': 'Optional ISO date upper bound.',
          },
          'source_ids': <String, Object?>{
            'type': 'array',
            'maxItems': kAiKnowledgeSearchMaxSourceIds,
            'items': <String, Object?>{
              'type': 'string',
              'maxLength': kAiKnowledgeIdMaxCharacters,
            },
          },
          'top_k': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 20,
            'description': 'Maximum results to return. Defaults to 6.',
          },
        },
        'required': <String>['query'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.knowledgeRead,
      name: 'KnowledgeRead',
      description:
          'Read-only fetch for Knowledge Base chunks. Prefer chunk_id returned by KnowledgeSearch. '
          'When content_status is complete, the content field is exact and complete. '
          'source_id is limited to a small preview and must not be used to dump a whole document.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'chunk_id': <String, Object?>{
            'type': 'string',
            'maxLength': kAiKnowledgeIdMaxCharacters,
            'description': 'A concrete knowledge chunk id to read.',
          },
          'source_id': <String, Object?>{
            'type': 'string',
            'maxLength': kAiKnowledgeIdMaxCharacters,
            'description':
                'Optional source id. Without chunk_id/around_chunk_id, returns only a small source preview.',
          },
          'around_chunk_id': <String, Object?>{
            'type': 'string',
            'maxLength': kAiKnowledgeIdMaxCharacters,
            'description':
                'Read a small ordered window around a concrete chunk id.',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 8,
            'description':
                'Maximum chunks to return for a chunk window or source preview. Defaults to 4.',
          },
        },
        'anyOf': <Object?>[
          <String, Object?>{
            'required': <String>['chunk_id'],
          },
          <String, Object?>{
            'required': <String>['source_id'],
          },
          <String, Object?>{
            'required': <String>['around_chunk_id'],
          },
        ],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentList,
      name: 'AgentList',
      description:
          'List enabled OpenHand digital employees (Hermes Agents). Use this before assigning work when you need to discover available specialist agents. Disabled agents are hidden by default.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'include_disabled': <String, Object?>{
            'type': 'boolean',
            'description':
                'When true, include stopped/disabled agents for inspection only. Do not assign tasks to disabled agents.',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 500,
            'description': 'Maximum returned agents. Defaults to 100.',
          },
        },
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentDetail,
      name: 'AgentDetail',
      description:
          'Fetch one digital employee profile, including persona, mentor, responsibility boundary, linked capabilities, tasks, approvals, workers, and optional audit/resource details.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentSelectorProperties,
          'include_disabled': <String, Object?>{'type': 'boolean'},
          'include_tasks': <String, Object?>{
            'type': 'boolean',
            'description': 'Defaults to true.',
          },
          'include_audit': <String, Object?>{'type': 'boolean'},
          'include_resources': <String, Object?>{'type': 'boolean'},
          'include_prompt': <String, Object?>{
            'type': 'boolean',
            'description':
                'When true, return the rendered prompt metadata without the full prompt text.',
          },
          'include_prompt_text': <String, Object?>{
            'type': 'boolean',
            'description':
                'When true, include the full rendered digital employee system prompt. Use sparingly.',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 200,
            'description':
                'Maximum returned items per detail collection. Defaults to 50.',
          },
        },
        'anyOf': _agentToolAgentSelectorAnyOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentActivityLog,
      name: 'AgentActivityLog',
      description:
          'Read one digital employee history stream with recent activities, audit events, capability/tool usage summary, task or worker filters, and lightweight counts. Use this when the user asks for historical activity, logs, audit trail, capability usage, or task/worker execution evidence.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentSelectorProperties,
          'include_disabled': <String, Object?>{
            'type': 'boolean',
            'description':
                'When true, allow inspecting a stopped/disabled agent history.',
          },
          'include_activities': <String, Object?>{
            'type': 'boolean',
            'description': 'Defaults to true.',
          },
          'include_audit': <String, Object?>{
            'type': 'boolean',
            'description': 'Defaults to true.',
          },
          'kind': <String, Object?>{
            'type': 'string',
            'description':
                'Optional activity/audit kind filter such as task_assigned, skill_call, approval_requested, or resource_updated.',
          },
          'activity_kind': <String, Object?>{
            'type': 'string',
            'description': 'Alias for kind.',
          },
          'message_type': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'thought',
              'tool_call',
              'response',
              'multimedia',
              'task',
              'approval',
              'lifecycle',
              'system',
              'event',
            ],
            'description':
                'Optional activity message type filter. Use task for task lifecycle items, tool_call for capability/tool use, thought for reasoning, response for final answers, and multimedia for media output.',
          },
          'activity_type': <String, Object?>{
            'type': 'string',
            'description': 'Alias for message_type.',
          },
          'tool_name': <String, Object?>{
            'type': 'string',
            'description':
                'Optional audited skill, MCP, builtin tool, or capability name filter.',
          },
          'tool': <String, Object?>{
            'type': 'string',
            'description': 'Alias for tool_name.',
          },
          'task_id': <String, Object?>{'type': 'string'},
          'id': <String, Object?>{
            'type': 'string',
            'description': 'Alias for task_id.',
          },
          'worker_id': <String, Object?>{'type': 'string'},
          'limit': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 100,
            'description': 'Maximum records per stream. Defaults to 30.',
          },
        },
        'anyOf': _agentToolAgentSelectorAnyOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentAuditReport,
      name: 'AgentAuditReport',
      description:
          'Generate a compact digital employee audit report with task completion metrics, worker execution, worker capacity, KPI status, approval counts, resource/load pressure, recent activities, and capability usage summaries. Use when the user asks for operational review, utilization, load, KPI, approval, token/request, worker, or capability-use reporting.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentSelectorProperties,
          'include_disabled': <String, Object?>{
            'type': 'boolean',
            'description':
                'When true, allow reporting on a stopped/disabled agent.',
          },
          'task_id': <String, Object?>{'type': 'string'},
          'id': <String, Object?>{
            'type': 'string',
            'description': 'Alias for task_id.',
          },
          'worker_id': <String, Object?>{'type': 'string'},
          'kind': <String, Object?>{
            'type': 'string',
            'description':
                'Optional activity/audit kind filter such as skill_call, mcp_call, task_assigned, or resource_updated.',
          },
          'activity_kind': <String, Object?>{
            'type': 'string',
            'description': 'Alias for kind.',
          },
          'message_type': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'thought',
              'tool_call',
              'response',
              'multimedia',
              'task',
              'approval',
              'lifecycle',
              'system',
              'event',
            ],
            'description':
                'Optional recent activity message type filter for the activity side of the audit report.',
          },
          'activity_type': <String, Object?>{
            'type': 'string',
            'description': 'Alias for message_type.',
          },
          'tool_name': <String, Object?>{
            'type': 'string',
            'description':
                'Optional audited skill, MCP, builtin tool, or capability name filter.',
          },
          'tool': <String, Object?>{
            'type': 'string',
            'description': 'Alias for tool_name.',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 100,
            'description':
                'Maximum recent records per report section. Defaults to 20.',
          },
        },
        'anyOf': _agentToolAgentSelectorAnyOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentAuditRecord,
      name: 'AgentAuditRecord',
      description:
          'Record an auditable digital employee capability event such as Skill, MCP, memory, knowledge, builtin tool, model request, worker execution, or external resource use. Include request_count, token_usage, task_id, and worker_id when known so audit dashboards and task summaries stay accurate.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentSelectorProperties,
          'kind': <String, Object?>{
            'type': 'string',
            'description':
                'Event kind, for example skill_call, mcp_call, memory_write, builtin_tool_call, model_request, worker_execution, or resource_write.',
          },
          'summary': <String, Object?>{
            'type': 'string',
            'description': 'Short audit summary.',
          },
          'tool_name': <String, Object?>{
            'type': 'string',
            'description':
                'Name of the audited skill, MCP tool, builtin tool, or external capability.',
          },
          'tool': <String, Object?>{
            'type': 'string',
            'description': 'Alias for tool_name.',
          },
          'token_usage': <String, Object?>{'type': 'integer', 'minimum': 0},
          'request_count': <String, Object?>{'type': 'integer', 'minimum': 0},
          'task_id': <String, Object?>{'type': 'string'},
          'worker_id': <String, Object?>{'type': 'string'},
          'metadata': _agentToolExtraSchema,
          'extra': _agentToolExtraSchema,
        },
        'required': <String>['summary'],
        'anyOf': _agentToolAgentSelectorAnyOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentApprovalRequest,
      name: 'AgentApprovalRequest',
      description:
          'Create an auditable approval request for an enabled digital employee when a task or capability use needs mentor/user permission. Prefer an explicit agent id/name after AgentList or AgentDetail; when omitted, OpenHand routes by approval context and route metadata. Do not use this for ordinary status updates or work that does not need approval.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'agent_id': <String, Object?>{'type': 'string'},
          'agent_name': <String, Object?>{'type': 'string'},
          'agent': <String, Object?>{
            'type': 'string',
            'description':
                'Agent id or exact display name. Optional when the approval context clearly matches one enabled agent route.',
          },
          'title': <String, Object?>{
            'type': 'string',
            'description': 'Short approval title.',
          },
          'reason': <String, Object?>{
            'type': 'string',
            'description': 'Why approval is required.',
          },
          'requested_action': <String, Object?>{
            'type': 'string',
            'description':
                'The exact action, permission, tool use, path, or external operation being requested.',
          },
          ..._agentToolLabelProperties,
          'extra': _agentToolExtraSchema,
        },
        'required': <String>['title'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentKpiUpsert,
      name: 'AgentKpiUpsert',
      description:
          'Create or update a digital employee KPI so the agent work loop has an auditable target, plan, status, and progress. Use kpi_id to update a known KPI; when kpi_id is omitted, OpenHand updates a matching KPI name before creating a new one. Prefer explicit agent id/name after AgentList or AgentDetail unless one enabled agent or route metadata clearly matches the KPI.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'agent_id': <String, Object?>{'type': 'string'},
          'agent_name': <String, Object?>{'type': 'string'},
          'agent': <String, Object?>{
            'type': 'string',
            'description':
                'Agent id or exact display name. Optional when the KPI context clearly matches one enabled agent route.',
          },
          'kpi_id': <String, Object?>{
            'type': 'string',
            'description': 'Existing KPI id. Omit to create or update by name.',
          },
          'id': <String, Object?>{
            'type': 'string',
            'description': 'Alias for kpi_id.',
          },
          'name': <String, Object?>{
            'type': 'string',
            'description': 'KPI name. Required when creating a new KPI.',
          },
          'title': <String, Object?>{
            'type': 'string',
            'description': 'Alias for name.',
          },
          'target': <String, Object?>{
            'type': 'string',
            'description': 'Measurable target or acceptance criteria.',
          },
          'plan': <String, Object?>{
            'type': 'string',
            'description': 'Current execution plan or next steps.',
          },
          'status': <String, Object?>{
            'type': 'string',
            'enum': <String>['tracking', 'at_risk', 'done', 'paused'],
          },
          'progress': _agentToolProgressSchema,
          ..._agentToolLabelProperties,
          'extra': _agentToolExtraSchema,
        },
        'anyOf': <Object?>[
          <String, Object?>{
            'required': <String>['name'],
          },
          <String, Object?>{
            'required': <String>['title'],
          },
          <String, Object?>{
            'required': <String>['kpi_id'],
          },
          <String, Object?>{
            'required': <String>['id'],
          },
        ],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentResourceUpdate,
      name: 'AgentResourceUpdate',
      description:
          'Update one enabled digital employee resource snapshot with observed CPU, memory, disk, persisted storage, token, and open-handle usage. Omitted fields keep their previous values. Use this after a worker run, report generation, durable artifact write, or resource cleanup so audit/resource dashboards stay current.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentSelectorProperties,
          'cpu_percent': <String, Object?>{
            'type': 'number',
            'minimum': 0,
            'maximum': 1,
            'description': '0..1 CPU pressure ratio.',
          },
          'memory_bytes': <String, Object?>{'type': 'integer', 'minimum': 0},
          'disk_bytes': <String, Object?>{'type': 'integer', 'minimum': 0},
          'persisted_bytes': <String, Object?>{'type': 'integer', 'minimum': 0},
          'token_budget': <String, Object?>{'type': 'integer', 'minimum': 0},
          'token_used': <String, Object?>{'type': 'integer', 'minimum': 0},
          'open_handles': <String, Object?>{'type': 'integer', 'minimum': 0},
          'extra': _agentToolExtraSchema,
        },
        'anyOf': _agentToolAgentSelectorAnyOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentClusterConfigure,
      name: 'AgentClusterConfigure',
      description:
          'Configure one enabled digital employee worker cluster: min/max workers, scale thresholds, retry policy, scheduler policy, removal policy, and worker labels. Omitted fields keep their previous values. Use before publishing delegated work when capacity, retries, labels, or scheduling need to change.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentSelectorProperties,
          'min_workers': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 999,
          },
          'max_workers': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 999,
          },
          'scale_out_threshold': <String, Object?>{
            'type': 'number',
            'minimum': 0,
            'maximum': 1,
          },
          'scale_in_threshold': <String, Object?>{
            'type': 'number',
            'minimum': 0,
            'maximum': 1,
          },
          'worker_removal_policy': <String, Object?>{
            'type': 'string',
            'enum': <String>['least_busy', 'newest_first'],
          },
          'retry_policy': <String, Object?>{
            'type': 'string',
            'enum': <String>['bounded_retry', 'none'],
          },
          'max_retries': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 20,
          },
          'scheduler_policy': <String, Object?>{
            'type': 'string',
            'enum': <String>['least_busy', 'priority_first', 'round_robin'],
          },
          'tags': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description': 'Worker labels. Passing an empty array clears tags.',
          },
          'labels': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description': 'Alias for tags.',
          },
        },
        'anyOf': _agentToolAgentSelectorAnyOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentClusterStatus,
      name: 'AgentClusterStatus',
      description:
          'Read one digital employee worker cluster status: scale settings, queue pressure, worker idle/busy state, executed task counts, busy score, priority, current task, and recent cluster events. Use before delegating, polling, scaling, or explaining worker capacity.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentSelectorProperties,
          'include_disabled': <String, Object?>{
            'type': 'boolean',
            'description':
                'When true, allow inspecting a stopped/disabled agent cluster.',
          },
          'worker_id': <String, Object?>{
            'type': 'string',
            'description': 'Optional worker id filter.',
          },
          'include_tasks': <String, Object?>{
            'type': 'boolean',
            'description': 'Defaults to true.',
          },
          'include_audit': <String, Object?>{
            'type': 'boolean',
            'description':
                'Defaults to true. Includes recent cluster activity and audit events.',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 100,
            'description':
                'Maximum recent records per status section. Defaults to 20.',
          },
        },
        'anyOf': _agentToolAgentSelectorAnyOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentTaskList,
      name: 'AgentTaskList',
      description:
          'List tasks from one digital employee task desk with optional status, worker, label, and limit filters. Use before tracking or changing a task when you need to discover task ids, inspect queue health, or summarize the current task board.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentSelectorProperties,
          'include_disabled': <String, Object?>{
            'type': 'boolean',
            'description':
                'When true, allow inspecting a stopped/disabled agent task desk.',
          },
          'status': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'backlog',
              'ready',
              'running',
              'waiting_approval',
              'paused',
              'completed',
              'failed',
              'canceled',
            ],
          },
          'worker_id': <String, Object?>{'type': 'string'},
          ..._agentToolLabelProperties,
          'label': <String, Object?>{
            'type': 'string',
            'description': 'Single-label filter alias.',
          },
          'tag': <String, Object?>{
            'type': 'string',
            'description': 'Single-tag filter alias.',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 200,
            'description': 'Maximum tasks to return. Defaults to 50.',
          },
        },
        'anyOf': _agentToolAgentSelectorAnyOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentTaskPublish,
      name: 'AgentTaskPublish',
      description:
          'Publish a concrete task to an enabled digital employee only when the task matches an agent responsibility or needs delegated execution beyond the current session. Prefer an explicit agent id/name after AgentList or AgentDetail. By default OpenHand starts the assigned worker and waits briefly for a result; inspect task.state, worker_execution, result_available, and next_poll before responding.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'agent_id': <String, Object?>{'type': 'string'},
          'agent_name': <String, Object?>{'type': 'string'},
          'agent': <String, Object?>{
            'type': 'string',
            'description':
                'Agent id or exact display name. Optional when the task context clearly matches one enabled agent route.',
          },
          'title': <String, Object?>{
            'type': 'string',
            'description': 'Short task title.',
          },
          'description': <String, Object?>{
            'type': 'string',
            'description': 'What should be done and why.',
          },
          'content': <String, Object?>{
            'type': 'string',
            'description':
                'Detailed task payload, inputs, constraints, and acceptance criteria.',
          },
          'note': <String, Object?>{'type': 'string'},
          ..._agentToolLabelProperties,
          'extra': _agentToolExtraSchema,
          'wait_for_result': <String, Object?>{
            'type': 'boolean',
            'description':
                'Defaults to true. When true, run the assigned worker in this tool call within wait_ms and return the latest result or wait state.',
          },
          'auto_execute': <String, Object?>{
            'type': 'boolean',
            'description':
                'Alias for wait_for_result. Pass false only when you want to publish without starting the worker.',
          },
          'wait_ms': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 90000,
            'description':
                'Automatic worker wait budget. Defaults to 30000. Use 0 to publish only.',
          },
          'timeout_ms': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 90000,
            'description': 'Alias for wait_ms.',
          },
        },
        'required': <String>['title'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentTaskTrack,
      name: 'AgentTaskTrack',
      description:
          'Read one agent task with status, progress, state, result_available, handoff, next_poll, assigned worker, operational summary, timestamps, and metadata. Use after AgentTaskPublish when you need the full task record plus the next polling or result-handoff action.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentTaskSelectorProperties,
        },
        'allOf': _agentToolAgentTaskAllOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentTaskProgress,
      name: 'AgentTaskProgress',
      description:
          'Read lightweight status, progress, state, next_poll, assigned worker, and operational summary for one agent task. Use for polling while state.needs_polling is true.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentTaskSelectorProperties,
        },
        'allOf': _agentToolAgentTaskAllOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentTaskCancel,
      name: 'AgentTaskCancel',
      description:
          'Cancel a queued or active agent task and keep the cancellation auditable in the agent activity log.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentTaskSelectorProperties,
          'note': <String, Object?>{'type': 'string'},
          'result': <String, Object?>{'type': 'string'},
          'extra': _agentToolExtraSchema,
        },
        'allOf': _agentToolAgentTaskAllOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentTaskPause,
      name: 'AgentTaskPause',
      description:
          'Pause an agent task so a mentor/user can inspect or unblock it before it resumes.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentTaskSelectorProperties,
          'note': <String, Object?>{'type': 'string'},
          'progress': _agentToolProgressSchema,
          'extra': _agentToolExtraSchema,
        },
        'allOf': _agentToolAgentTaskAllOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentTaskTerminate,
      name: 'AgentTaskTerminate',
      description:
          'Terminate an agent task as failed when it must stop immediately. Use cancel for normal withdrawal and terminate for abnormal stop/failure.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentTaskSelectorProperties,
          'note': <String, Object?>{'type': 'string'},
          'result': <String, Object?>{'type': 'string'},
          'progress': _agentToolProgressSchema,
          'extra': _agentToolExtraSchema,
        },
        'allOf': _agentToolAgentTaskAllOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentTaskResume,
      name: 'AgentTaskResume',
      description: 'Resume a paused agent task by returning it to ready state.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentTaskSelectorProperties,
          'note': <String, Object?>{'type': 'string'},
          'extra': _agentToolExtraSchema,
        },
        'allOf': _agentToolAgentTaskAllOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentTaskComplete,
      name: 'AgentTaskComplete',
      description:
          'Mark an agent task as completed and write back the worker result. Use this when the assigned worker has produced a verified deliverable.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentTaskSelectorProperties,
          'result': <String, Object?>{
            'type': 'string',
            'description': 'Final task result or handoff summary.',
          },
          'note': <String, Object?>{'type': 'string'},
          'extra': _agentToolExtraSchema,
        },
        'required': <String>['result'],
        'allOf': _agentToolAgentTaskAllOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.agentTaskResult,
      name: 'AgentTaskResult',
      description:
          'Read the final or latest task result, note, status, progress, result_available, handoff, next_poll, assigned worker, and operational summary. Waits up to wait_ms (default 30000) while active tasks are still running.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          ..._agentToolAgentTaskSelectorProperties,
          'wait_ms': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 90000,
          },
          'timeout_ms': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 90000,
            'description': 'Alias for wait_ms.',
          },
          'poll_ms': <String, Object?>{
            'type': 'integer',
            'minimum': 300,
            'maximum': 6000,
          },
        },
        'allOf': _agentToolAgentTaskAllOf,
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.memory,
      name: 'Memory',
      description:
          'Manage the user memory store (Hermes Talker self-learning only). '
          'Supported actions: `list` (optional tag filter), `append` '
          '(insert a new memory), `upsert_profile` (create or update the '
          'single user_profile entry), `update` (by id), `delete` (by id). '
          'ANTI-FRAGMENTATION: before `append` or `upsert_profile`, call '
          '`list` (or scan injected memory context) and prefer `update` to '
          'fold the new fact into an existing related entry — two entries '
          'with paraphrased titles is a bug. `upsert_profile` must be '
          'dialectical: preserve correct existing fields, only add or '
          'correct what genuinely changed (≤~30% growth per turn). `append` '
          'is the last resort, justified only when the topic is orthogonal '
          'to every existing entry AND has clear cross-conversation reuse '
          'value (not "we just discussed X"). NEVER `delete` memories the '
          'user authored manually — `delete` is only for collapsing your '
          'own historical entries now fully superseded by an updated one. '
          'A no-op is a valid outcome; skipping a save when the bar is not '
          'met is correct behaviour.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'list',
              'append',
              'upsert_profile',
              'update',
              'delete',
            ],
          },
          'id': <String, Object?>{
            'type': 'string',
            'maxLength': UserMemoryEntry.maxIdCharacters,
            'description': 'Required for `update`/`delete`.',
          },
          'content': <String, Object?>{
            'type': 'string',
            'maxLength': UserMemoryEntry.maxContentCharacters,
            'description':
                'Memory content. Required for `append`/`upsert_profile`/'
                '`update`.',
          },
          'title': <String, Object?>{
            'type': 'string',
            'maxLength': UserMemoryEntry.maxTitleLength,
            'description':
                'Optional short title for append/update. '
                'Used by the UI as the card heading; falls back to a '
                'preview of `content` when omitted. For `update`, omit to '
                'keep the existing title, pass an empty string to clear it.',
          },
          'tags': <String, Object?>{
            'anyOf': <Object?>[
              <String, Object?>{
                'type': 'string',
                'maxLength':
                    UserMemoryEntry.maxTags *
                    (UserMemoryEntry.maxTagCharacters + 1),
              },
              <String, Object?>{
                'type': 'array',
                'maxItems': UserMemoryEntry.maxTags,
                'items': <String, Object?>{
                  'type': 'string',
                  'maxLength': UserMemoryEntry.maxTagCharacters,
                },
              },
            ],
            'description':
                'Optional tags: array, comma-separated text, or JSON array text. Omit on update/upsert_profile to preserve; [] clears.',
          },
          'tag': <String, Object?>{
            'type': 'string',
            'maxLength': UserMemoryEntry.maxTagCharacters,
            'description':
                'Optional filter for `list`. Matches case-insensitively.',
          },
        },
        'required': <String>['action'],
        'additionalProperties': false,
      },
    ),
  ];

  static AiResolvedTool _builtinTool({
    required AiBuiltinToolKind kind,
    required String name,
    required String description,
    required Map<String, Object?> parameters,
  }) {
    // 统一为所有内建工具注入可选 purpose 字段。
    // AI 在发起任何工具调用时都可以填写一句话目的/目标/动作概述，
    // 我们会把它作为 conversation history 压缩后的补充信息保留下来，
    // 既能让模型有意识地表达意图，也能在长上下文里维持可追溯性。
    final enrichedParameters = _injectPurposeProperty(parameters);
    return AiResolvedTool(
      name: name,
      definition: AiToolDefinition(
        name: name,
        description: description,
        parameters: enrichedParameters,
      ),
      source: AiRuntimeToolSource.builtin,
      builtinKind: kind,
    );
  }

  /// 向对象参数副本注入可选的 `purpose` 字段。
  static Map<String, Object?> _injectPurposeProperty(
    Map<String, Object?> parameters,
  ) {
    if (parameters['type'] != 'object') {
      return parameters;
    }
    final propertiesRaw = parameters['properties'];
    final properties = propertiesRaw is Map
        ? Map<String, Object?>.from(propertiesRaw)
        : <String, Object?>{};
    if (properties.containsKey('purpose')) {
      return parameters;
    }
    properties['purpose'] = const <String, Object?>{
      'type': 'string',
      'description':
          'Optional one-sentence statement of what you intend to achieve with '
          'this tool call (intent / goal / brief summary). When the result '
          'exceeds the prompt-history compression threshold, this purpose '
          'is preserved alongside the extracted file paths so future turns '
          'still understand why the call was made.',
    };
    final next = Map<String, Object?>.from(parameters);
    next['properties'] = properties;
    return next;
  }

  /// 返回指定类型的默认内建工具。
  static AiResolvedTool? builtinToolDefault(AiBuiltinToolKind kind) {
    for (final tool in _builtinTools) {
      if (tool.builtinKind == kind) return tool;
    }
    return null;
  }
}

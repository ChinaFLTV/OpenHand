import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/path_safety.dart';
import '../../../mcp/index.dart';
import '../../../skills/index.dart';
import '../../model/ai_builtin_tool_config.dart';
import '../../model/ai_deny_command_rule.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_session_runtime_context.dart';
import '../../tools/ai_tool_registry.dart';
import '../../tools/ai_tool_utils.dart';
import '../../tools/memory/ai_memory_tool.dart';
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
const int _minToolOutputTruncationPayloadChars = 40;
const String _toolResultsSubdirectoryName = 'tool-results';
const String _toolOutputTruncationStrategyHeadTail = 'head_tail';
const String _toolOutputRecoveryHintRerunNarrower = 'rerun_with_narrower_query';
const String _toolOutputRecoveryHintReadPersisted = 'read_persisted_output';
const String _toolOutputPersistenceFormatText = 'text';
const String _filePathResolvedAgainstCwdDescription =
    'The absolute or relative file path. Relative paths are resolved against the working directory.';

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
    final normalizedName = _normalizeToolLookupKey(name);
    if (normalizedName.isEmpty) {
      return null;
    }
    for (final entry in toolsByName.entries) {
      if (_normalizeToolLookupKey(entry.key) == normalizedName) {
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

  /// Aggressive normalization for tool-name lookup so that PascalCase,
  /// camelCase, snake_case, kebab-case and even slightly garbled names
  /// (extra spaces / underscores / dashes) all resolve to the same tool.
  static String _normalizeToolLookupKey(String value) {
    final buffer = StringBuffer();
    for (final code in value.codeUnits) {
      if ((code >= 0x30 && code <= 0x39) ||
          (code >= 0x41 && code <= 0x5A) ||
          (code >= 0x61 && code <= 0x7A)) {
        buffer.writeCharCode(code | 0x20); // lowercase ASCII
      }
    }
    return buffer.toString();
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
  });

  final String name;
  final AiToolDefinition definition;
  final AiRuntimeToolSource source;
  final AiBuiltinToolKind? builtinKind;
  final McpServer? mcpServer;
  final McpTool? mcpTool;
  final LocalSkill? skill;

  /// 用户层面的内建工具配置（仅 builtin 来源）。携带 timeout / retry 等
  /// 运行时策略；execute() 据此包裹超时与重试逻辑（2026-04-29）。
  final AiBuiltinToolConfig? builtinConfig;

  /// Per-catalog sidecar used only by the built-in ToolSearch tool.
  ///
  /// Runtime-tool lazy loading is resolved per session/round, while the tool
  /// registry keeps one global ToolSearch instance. Keeping deferred schemas
  /// here lets ToolSearch execute against the same catalog the model saw, even
  /// if another session refreshes its own catalog before this tool call runs.
  final Map<String, AiToolDefinition> toolSearchDeferredToolDefinitions;
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

  String toToolOutput() => resultText.trim();
}

class _PersistedToolOutput {
  const _PersistedToolOutput({required this.path, required this.originalChars});

  final String path;
  final int originalChars;
}

class AiToolRuntimeService {
  AiToolRuntimeService({
    required AiBashToolService bashToolService,
    required AiClaudeHookService hookService,
    required McpToolDiscoveryService mcpToolService,
    required AiChatClient backgroundChatClient,
    http.Client? httpClient,
    Future<List<InternetAddress>> Function(String host)? hostLookup,
    AiFileTrackerService? fileTrackerService,
    AiFileHistoryService? fileHistoryService,
    AiFileMutationLedger? mutationLedger,
    String Function()? skillsDirProvider,
    MemoryControllerProvider? memoryControllerProvider,
    String Function(String sessionId)? toolOutputDirectoryProvider,
  }) : _bashToolService = bashToolService,
       _hookService = hookService,
       _mcpToolService = mcpToolService,
       _backgroundChatClient = backgroundChatClient,
       _httpClient =
           httpClient ?? SystemProxyResolver.instance.createHttpClient(),
       _scraplingBridge = WebFetchScraplingBridge(),
       _hostLookup = hostLookup ?? ((host) => InternetAddress.lookup(host)),
       _fileTracker = fileTrackerService ?? AiFileTrackerService(),
       _fileHistory = fileHistoryService ?? AiFileHistoryService(),
       _mutationLedger = mutationLedger ?? AiFileMutationLedger(),
       _toolOutputDirectoryProvider = toolOutputDirectoryProvider {
    // 2026-04-01 02:02:39 初始化完整服务依赖注入的多态工具注册中心
    _toolRegistry = AiToolRegistry.withServiceDependencies(
      bashToolService: _bashToolService,
      hookService: _hookService,
      backgroundChatClient: _backgroundChatClient,
      httpClient: _httpClient,
      scraplingBridge: _scraplingBridge,
      hostLookup: _hostLookup,
      skillsDirProvider: skillsDirProvider,
      memoryControllerProvider: memoryControllerProvider,
    );
  }

  static const Set<AiBuiltinToolKind> _nonRetryableSideEffectBuiltinKinds =
      <AiBuiltinToolKind>{
        AiBuiltinToolKind.task,
        AiBuiltinToolKind.bash,
        AiBuiltinToolKind.bashBackground,
        AiBuiltinToolKind.taskOutput,
        AiBuiltinToolKind.taskStop,
        AiBuiltinToolKind.edit,
        AiBuiltinToolKind.multiEdit,
        AiBuiltinToolKind.applyFileDiffs,
        AiBuiltinToolKind.write,
        AiBuiltinToolKind.notebookEdit,
        AiBuiltinToolKind.deleteFile,
        AiBuiltinToolKind.skillManager,
      };

  final AiBashToolService _bashToolService;
  final AiClaudeHookService _hookService;
  final McpToolDiscoveryService _mcpToolService;
  final AiChatClient _backgroundChatClient;
  final http.Client _httpClient;
  final WebFetchScraplingBridge _scraplingBridge;
  final Future<List<InternetAddress>> Function(String host) _hostLookup;
  late final AiToolRegistry _toolRegistry;

  /// Group C — 暴露给 [AiSessionController]，用于把 runtime context 中的网络
  /// 类参数下放到 [AiWebFetchTool] 实例。
  AiToolRegistry get toolRegistry => _toolRegistry;

  // 2026-04-12: 文件追踪和历史版本服务
  final AiFileTrackerService _fileTracker;
  final AiFileHistoryService _fileHistory;
  final AiFileMutationLedger _mutationLedger;
  final String Function(String sessionId)? _toolOutputDirectoryProvider;

  /// 获取文件追踪服务（供外部访问，如会话重置时清理）
  AiFileTrackerService get fileTracker => _fileTracker;

  /// 获取文件历史服务（供外部访问，如回滚功能）
  AiFileHistoryService get fileHistory => _fileHistory;

  /// 2026-05-03 — 新型文件变动 ledger（全局单例，供工具钩子/UI
  /// 联动 undo/redo 使用）。
  AiFileMutationLedger get mutationLedger => _mutationLedger;

  Future<WebFetchScraplingProbeStatus> probeWebFetchScrapling({
    required AiWebFetchScraplingSettings settings,
  }) => _scraplingBridge.probe(settings: settings);

  Stream<WebFetchScraplingRuntimeEvent>
  installWebFetchScraplingRuntimeStreaming({
    required AiWebFetchScraplingSettings settings,
  }) => _scraplingBridge.installRuntimeStreaming(settings: settings);

  Future<void> installWebFetchScraplingRuntime({
    required AiWebFetchScraplingSettings settings,
  }) => _scraplingBridge.installRuntime(settings: settings);

  Stream<WebFetchScraplingRuntimeEvent>
  uninstallWebFetchScraplingRuntimeStreaming({
    required AiWebFetchScraplingSettings settings,
  }) => _scraplingBridge.uninstallRuntimeStreaming(settings: settings);

  Future<void> uninstallWebFetchScraplingRuntime({
    required AiWebFetchScraplingSettings settings,
  }) => _scraplingBridge.uninstallRuntime(settings: settings);

  Future<void> resetWebFetchScrapling() => _scraplingBridge.dispose();

  WebFetchScraplingProbeStatus get lastWebFetchScraplingProbe =>
      _scraplingBridge.lastProbe;

  static const int _maxToolNameLength = 64;

  /// 2026-04-01 工具输出单轮最大字符数限制。
  /// 超过此限制时截断并附刚抽提提示，防止 Context 溢出和 API token 超限。
  /// 2026-04-29 — Group B: 由用户设置注入，可运行时调整。
  int maxToolOutputChars = 200000;

  /// Template ID for which `skill_manager` is exposed as a builtin. All other
  /// templates never see `skill_manager` in their tool catalog regardless of
  /// user builtin-tool configs.
  static const String _skillManagerTemplateId =
      AiPromptTemplatePolicies.hermesTalkerTemplateId;

  /// Returns true iff the resolved [tool] should appear in the catalog of a
  /// session whose thread template is [templateId].
  bool _isBuiltinAllowedForTemplate(AiResolvedTool tool, String templateId) {
    if (tool.builtinKind == AiBuiltinToolKind.skillManager) {
      return templateId == _skillManagerTemplateId;
    }
    if (tool.builtinKind == AiBuiltinToolKind.memory) {
      return templateId == _skillManagerTemplateId;
    }
    return true;
  }

  int _toolNameCompare(String left, String right) {
    return AiResolvedToolCatalog._normalizeToolLookupKey(
      left,
    ).compareTo(AiResolvedToolCatalog._normalizeToolLookupKey(right));
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

  /// Apply user builtin-tool configs: filter disabled, apply overrides,
  /// respect sort order and priority.
  List<AiResolvedTool> _resolveConfiguredBuiltinTools(
    List<AiBuiltinToolConfig> configs,
  ) {
    if (configs.isEmpty) return _builtinTools;
    final configByKind = <AiBuiltinToolKind, AiBuiltinToolConfig>{};
    for (final c in configs) {
      configByKind[c.kind] = c;
    }
    // Build list respecting configs' sort order.
    final sortedConfigs = List<AiBuiltinToolConfig>.from(configs)
      ..sort((a, b) {
        final cmp = a.sortOrder.compareTo(b.sortOrder);
        return cmp != 0 ? cmp : a.kind.index.compareTo(b.kind.index);
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
      final baseTool = toolByKind[cfg.kind];
      if (baseTool == null) continue;
      // Apply overrides.
      final overrideName = cfg.displayName?.trim().isNotEmpty == true
          ? cfg.displayName!
          : null;
      final overrideDesc = cfg.promptOverride?.trim().isNotEmpty == true
          ? cfg.promptOverride!
          : null;
      final overrideSummary = cfg.summary?.trim().isNotEmpty == true
          ? cfg.summary!
          : null;
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
        ),
      );
    }
    return result;
  }

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
    final definitions = <AiToolDefinition>[];
    final toolsByName = <String, AiResolvedTool>{};
    final reservedToolNames = <String>{};
    final notices = <String>[];
    final mcpServerInstructionsByName = <String, String>{};

    void register(AiResolvedTool tool) {
      if (!reservedToolNames.add(tool.name)) {
        return;
      }
      toolsByName[tool.name] = tool;
      definitions.add(tool.definition);
    }

    // 2026-04-08 能力调用优先级：Skill > MCP > Builtin
    // 按优先级从高到低注册，同名时高优先级工具胜出。
    // 工具目录（definitions 列表）的呈现顺序也遵循此优先级，
    // 让模型在工具列表中首先看到 Skill、其次 MCP、最后 Builtin。

    // ── 第一优先级：Skill 工具 ─────────────────────────────────────
    for (final skill in _sortedSkills(runtimeContext.availableSkills)) {
      final tool = _buildSkillTool(skill, reservedToolNames);
      register(tool);
    }

    // ── 第二优先级：MCP 工具 ──────────────────────────────────────
    final enabledServers = _sortedEnabledMcpServers(
      runtimeContext.availableMcpServers,
    );
    for (final server in enabledServers) {
      try {
        final catalog = await _mcpToolService.discoverTools(server);
        if (catalog.status != McpToolCatalogStatus.ready) {
          final errorMessage = catalog.errorMessage?.trim() ?? '';
          if (errorMessage.isNotEmpty) {
            notices.add('MCP ${server.name}: $errorMessage');
          }
          continue;
        }
        if (catalog.warningMessage?.trim().isNotEmpty ?? false) {
          notices.add('MCP ${server.name}: ${catalog.warningMessage!.trim()}');
        }
        final serverInstructions = catalog.serverInstructions.trim();
        if (serverInstructions.isNotEmpty) {
          mcpServerInstructionsByName[server.name] = serverInstructions;
        }
        for (final mcpTool in _sortedMcpTools(catalog.tools)) {
          final tool = _buildMcpTool(
            server: server,
            tool: mcpTool,
            takenNames: reservedToolNames,
          );
          register(tool);
        }
      } catch (error) {
        notices.add('MCP ${server.name}: $error');
      }
    }

    // ── 第三优先级：Builtin 工具 ──────────────────────────────────
    final effectiveTemplateId = templateId ?? runtimeContext.templateId;
    for (final tool in _resolveConfiguredBuiltinTools(
      runtimeContext.builtinToolConfigs,
    )) {
      if (!_isBuiltinAllowedForTemplate(tool, effectiveTemplateId)) {
        continue;
      }
      register(tool);
    }

    return AiResolvedToolCatalog(
      definitions: definitions,
      toolsByName: toolsByName,
      notices: notices,
      mcpServerInstructionsByName: mcpServerInstructionsByName,
    );
  }

  AiResolvedToolCatalog resolveCatalogFromRuntimeSnapshot({
    required AiSessionRuntimeContext runtimeContext,
    Map<String, McpToolCatalog> mcpToolCatalogsByServerName =
        const <String, McpToolCatalog>{},
    String? templateId,
  }) {
    final definitions = <AiToolDefinition>[];
    final toolsByName = <String, AiResolvedTool>{};
    final reservedToolNames = <String>{};
    final notices = <String>[];
    final mcpServerInstructionsByName = <String, String>{};

    void register(AiResolvedTool tool) {
      if (!reservedToolNames.add(tool.name)) {
        return;
      }
      toolsByName[tool.name] = tool;
      definitions.add(tool.definition);
    }

    // 2026-04-08 能力调用优先级：Skill > MCP > Builtin（与 resolveCatalog 保持一致）

    // ── 第一优先级：Skill 工具 ─────────────────────────────────────
    for (final skill in _sortedSkills(runtimeContext.availableSkills)) {
      final tool = _buildSkillTool(skill, reservedToolNames);
      register(tool);
    }

    // ── 第二优先级：MCP 工具 ──────────────────────────────────────
    final enabledServers = _sortedEnabledMcpServers(
      runtimeContext.availableMcpServers,
    );
    for (final server in enabledServers) {
      final catalog = mcpToolCatalogsByServerName[server.name];
      if (catalog == null || catalog.status == McpToolCatalogStatus.idle) {
        notices.add(
          'MCP ${server.name}: Tool catalog has not been scanned yet.',
        );
        continue;
      }
      if (catalog.status == McpToolCatalogStatus.loading) {
        notices.add('MCP ${server.name}: Tool catalog is refreshing.');
        continue;
      }
      if (catalog.status != McpToolCatalogStatus.ready) {
        final errorMessage = catalog.errorMessage?.trim() ?? '';
        if (errorMessage.isNotEmpty) {
          notices.add('MCP ${server.name}: $errorMessage');
        }
        continue;
      }
      if (catalog.warningMessage?.trim().isNotEmpty ?? false) {
        notices.add('MCP ${server.name}: ${catalog.warningMessage!.trim()}');
      }
      final serverInstructions = catalog.serverInstructions.trim();
      if (serverInstructions.isNotEmpty) {
        mcpServerInstructionsByName[server.name] = serverInstructions;
      }
      for (final mcpTool in _sortedMcpTools(catalog.tools)) {
        final tool = _buildMcpTool(
          server: server,
          tool: mcpTool,
          takenNames: reservedToolNames,
        );
        register(tool);
      }
    }

    // ── 第三优先级：Builtin 工具 ──────────────────────────────────
    final effectiveTemplateId = templateId ?? runtimeContext.templateId;
    for (final tool in _resolveConfiguredBuiltinTools(
      runtimeContext.builtinToolConfigs,
    )) {
      if (!_isBuiltinAllowedForTemplate(tool, effectiveTemplateId)) {
        continue;
      }
      register(tool);
    }

    return AiResolvedToolCatalog(
      definitions: definitions,
      toolsByName: toolsByName,
      notices: notices,
      mcpServerInstructionsByName: mcpServerInstructionsByName,
    );
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
    final resolvedTool = catalog.find(toolCall.name);
    if (resolvedTool == null) {
      // 2026-04-28: 工具未命中时，给模型一份可操作的引导，而不是只丢一句
      // “Unsupported tool name”。常见两种诱因：
      //   1) 模型在 plan 待批准轮次幻觉调用 Write/TodoWrite —— 此时 catalog
      //      被刻意清空，应提示先调用 ExitPlanMode 或等待用户批准；
      //   2) 模型把 Claude Code 风格名字（如 TodoWrite）当成了别名 —— 给出
      //      当前轮次真实可用的工具名清单，便于自我纠正。
      final availableNames = catalog.definitions
          .map((tool) => tool.name.trim())
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
      final guidance = StringBuffer('Unsupported tool name: ${toolCall.name}.');
      if (availableNames.isEmpty) {
        guidance.write(AiPlanModeGuidance.unsupportedEmptyCatalog);
      } else {
        // Cap the suggestion list so an MCP-heavy session does not blow the
        // tool-result envelope.
        const maxSuggestions = 24;
        final preview = availableNames.length <= maxSuggestions
            ? availableNames.join(', ')
            : '${availableNames.take(maxSuggestions).join(', ')} … '
                  '(${availableNames.length - maxSuggestions} more)';
        guidance.write(
          ' Use only exact names from this turn\'s catalog: $preview. '
          'Re-issue the call with the correct tool name (and matching argument '
          'schema) — do NOT fall back to dumping code into chat.',
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
    // 2026-05-09: 登记到全局执行中心，以支持 UI 可观测与独立中断。
    // 取消在 finally 中反注销；Bash 子进程启动后会从
    // ai_bash_tool_service 里重新 attachKiller / attachPid 以支持真正
    // 发信号。不同 source 使用不同 kind；skill / mcp 默认 killer 为 no-op。
    final registryKind = switch (resolvedTool.source) {
      AiRuntimeToolSource.builtin => AiToolExecutionKind.builtin,
      AiRuntimeToolSource.mcp => AiToolExecutionKind.mcp,
      AiRuntimeToolSource.skill => AiToolExecutionKind.skill,
    };
    final shouldRegister = toolCall.id.isNotEmpty;
    if (shouldRegister) {
      AiToolExecutionRegistry.instance.register(
        toolCallId: toolCall.id,
        sessionId: sessionId,
        kind: registryKind,
        displayName: resolvedTool.name,
      );
    }
    late AiToolExecutionResult rawResult;
    // 2026-04-29 — 用户层 timeout / retry 策略包裹真正的 dispatch。
    // 仅当工具来自 builtin 且携带 [builtinConfig] 时启用：
    //   • timeout: 仅包裹无副作用 builtin；Task/Bash/写工具使用各自可控边界。
    //   • retry: 仅对无副作用工具的瞬时失败启用。Task、写文件、Bash、
    //     后台进程、技能管理、Memory 写入等可能产生副作用的调用不自动重放。
    final builtinCfg = resolvedTool.builtinConfig;
    // MCP servers can become unresponsive (network hang, server crash, slow
    // remote tool). Without a guard, `_executeMcpTool` would await the
    // server response indefinitely and freeze the entire turn. Apply a
    // generous default cap so MCP tools, like builtins, surface a
    // `timed_out` status instead of hanging.
    const defaultMcpTimeout = Duration(seconds: 120);
    final timeoutDuration = _runtimeTimeoutDuration(
      tool: resolvedTool,
      decodedArguments: decodedArguments,
      builtinConfig: builtinCfg,
      defaultMcpTimeout: defaultMcpTimeout,
    );
    final maxRetries = builtinCfg?.effectiveMaxRetries ?? 0;
    Future<AiToolExecutionResult> dispatchOnce() async {
      return switch (resolvedTool.source) {
        AiRuntimeToolSource.builtin => _executeBuiltinTool(
          sessionId: sessionId,
          catalog: catalog,
          tool: resolvedTool,
          toolCall: toolCall,
          decodedArguments: decodedArguments,
          model: model,
          previouslyReadFiles: previouslyReadFiles,
          denyCommandRules: denyCommandRules,
          requireWriteCommandConfirmation: requireWriteCommandConfirmation,
          confirmWriteCommand: confirmWriteCommand,
          cancelSignal: cancelSignal,
          onBashUpdate: onBashUpdate,
          metadata: metadata,
        ),
        AiRuntimeToolSource.mcp => _executeMcpTool(
          tool: resolvedTool,
          toolCall: toolCall,
          decodedArguments: decodedArguments,
        ),
        AiRuntimeToolSource.skill => _executeSkillTool(
          tool: resolvedTool,
          toolCall: toolCall,
          decodedArguments: decodedArguments,
        ),
      };
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

    Future<AiToolExecutionResult> dispatchWithTimeout() async {
      final f = dispatchOnce();
      final localTimeout = timeoutDuration;
      if (localTimeout == null) return f;
      try {
        return await f.timeout(
          localTimeout,
          onTimeout: () => AiToolExecutionResult(
            status: BashToolExecutionStatus.timedOut,
            command: resolvedTool.name,
            workingDirectory: hookWorkingDirectory,
            stdout: '',
            stderr:
                'Tool "${resolvedTool.name}" exceeded the configured '
                '${localTimeout.inSeconds}s timeout.',
            durationMs: rawExecutionStartedAt.elapsedMilliseconds,
            resultText:
                'status: timed_out\nerror: tool exceeded ${localTimeout.inSeconds}s timeout',
          ),
        );
      } on TimeoutException {
        return AiToolExecutionResult(
          status: BashToolExecutionStatus.timedOut,
          command: resolvedTool.name,
          workingDirectory: hookWorkingDirectory,
          stdout: '',
          stderr:
              'Tool "${resolvedTool.name}" exceeded the configured '
              '${localTimeout.inSeconds}s timeout.',
          durationMs: rawExecutionStartedAt.elapsedMilliseconds,
          resultText:
              'status: timed_out\nerror: tool exceeded ${localTimeout.inSeconds}s timeout',
        );
      }
    }

    AiToolExecutionResult? attemptResult;
    var attempts = 0;
    try {
      while (true) {
        attempts += 1;
        try {
          attemptResult = await dispatchWithTimeout();
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
            await Future<void>.delayed(backoff);
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
      final postHookResult = await _hookService.runHooks(
        eventName: rawResult.status == BashToolExecutionStatus.success
            ? 'PostToolUse'
            : 'PostToolUseFailure',
        sessionId: sessionId,
        matcherValue: hookMatcherValue,
        cwd: rawResult.workingDirectory.trim().isEmpty
            ? hookWorkingDirectory
            : rawResult.workingDirectory,
        payload: _toolHookPayload(
          eventName: rawResult.status == BashToolExecutionStatus.success
              ? 'PostToolUse'
              : 'PostToolUseFailure',
          toolName: hookToolName,
          toolSource: resolvedTool.source.name,
          sessionId: sessionId,
          toolInput: decodedArguments,
          cwd: rawResult.workingDirectory.trim().isEmpty
              ? hookWorkingDirectory
              : rawResult.workingDirectory,
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
      if (shouldRegister) {
        AiToolExecutionRegistry.instance.unregister(toolCall.id);
      }
    }
  }

  // 2026-04-01 工具输出 budget 保护。
  // 对 resultText 进行字符数上限保护，超限时先尝试持久化完整结果，
  // 再向模型返回 head/tail 预算内预览和恢复提示。
  // 这防止了单次工具调用将大量输出（如 WebFetch 、Bash cat 大文件）直接塑进 API 上下文。
  // FIX: stdout/stderr 截断边界与 resultText 保持一致，避免上下文看到不同片段。
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
    return AiToolExecutionResult(
      status: result.status,
      command: result.command,
      workingDirectory: result.workingDirectory,
      stdout: truncatedStdout,
      stderr: truncatedStderr,
      durationMs: result.durationMs,
      resultText: resultView.text,
      exitCode: result.exitCode,
      matchedRuleId: result.matchedRuleId,
      matchedRulePattern: result.matchedRulePattern,
      isWriteCommand: result.isWriteCommand,
      writeAnalysisReason: result.writeAnalysisReason,
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
          : notice.substring(0, math.max(0, budget));
      return (text: fallback, includedChars: 0, omittedChars: value.length);
    }
    final includedChars = math.min(effectivePayloadBudget, value.length);
    omittedChars = value.length - includedChars;
    final headChars = (includedChars / 2).ceil();
    final tailChars = includedChars - headChars;
    final head = value.substring(0, headChars);
    final tail = tailChars <= 0
        ? ''
        : value.substring(value.length - tailChars);
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
    final recovery = persistedPath.trim().isEmpty
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
    if (toolCallId.trim().isEmpty || content.isEmpty) {
      return null;
    }
    final directoryPath = _toolOutputDirectoryPath(sessionId);
    if (directoryPath.trim().isEmpty) {
      return null;
    }
    final file = File(
      p.join(
        directoryPath,
        '${_safeToolOutputStorageIdentifier(toolCallId, 'tool_result')}.txt',
      ),
    );
    try {
      await file.parent.create(recursive: true);
      if (!await file.exists()) {
        await file.writeAsString(content, flush: true);
      }
      return _PersistedToolOutput(
        path: file.path,
        originalChars: content.length,
      );
    } catch (error, stack) {
      silentLog('ai_tool_runtime_service', 'persist tool output', error, stack);
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
    final normalized = raw
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
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
      final action = '${decodedArguments['action'] ?? ''}'.trim().toLowerCase();
      return action.isNotEmpty && action != 'list';
    }
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
    if (singlePath is String && singlePath.trim().isNotEmpty) {
      paths.add(singlePath.trim());
    }
    final multiPaths = meta['file_mutation_paths'];
    if (multiPaths is List) {
      for (final p in multiPaths) {
        if (p is String && p.trim().isNotEmpty) paths.add(p.trim());
      }
    }
    if (paths.isEmpty) return result;
    final recorded = <String, String?>{};
    for (final path in paths) {
      try {
        final file = File(path);
        if (!await file.exists()) {
          recorded[path] = null;
          continue;
        }
        String? after;
        try {
          after = await file.readAsString();
          if (after.length > _maxPostHocLedgerCaptureBytes) after = null;
        } catch (error, stack) {
          silentLog(
            'AiToolRuntimeService',
            '_capturePostHocLedgerRecord.read',
            error,
            stack,
          );
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
        silentLog(
          'AiToolRuntimeService',
          '_capturePostHocLedgerRecord',
          error,
          stack,
        );
        recorded[path] = null;
      }
    }
    if (recorded.isEmpty) return result;
    return AiToolExecutionResult(
      status: result.status,
      command: result.command,
      workingDirectory: result.workingDirectory,
      stdout: result.stdout,
      stderr: result.stderr,
      durationMs: result.durationMs,
      resultText: result.resultText,
      exitCode: result.exitCode,
      matchedRuleId: result.matchedRuleId,
      matchedRulePattern: result.matchedRulePattern,
      isWriteCommand: result.isWriteCommand,
      writeAnalysisReason: result.writeAnalysisReason,
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
        _readBoolArgument(decodedArguments['run_in_background']) == true) {
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
    // 2026-04-01 优先通过多态 Registry 路由（轻量工具已迁移）
    // 2026-04-12 通过 metadata 传递文件追踪和历史服务（遵循 AiToolExecutionContext 冻结约束）
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
        'file_tracker': _fileTracker,
        'file_history': _fileHistory,
        'mutation_ledger': _mutationLedger,
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
    // 2026-04-01 所有工具均已通过 Registry 注册，此路径不可达。
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

  bool? _readBoolArgument(Object? rawValue) {
    if (rawValue is bool) return rawValue;
    final normalized = '$rawValue'.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
    return null;
  }

  Future<AiToolExecutionResult> _executeMcpTool({
    required AiResolvedTool tool,
    required AiToolCall toolCall,
    required Map<String, Object?> decodedArguments,
  }) async {
    final server = tool.mcpServer;
    final mcpTool = tool.mcpTool;
    if (server == null || mcpTool == null) {
      return _invalidToolResult(toolCall.name, 'Missing MCP tool metadata.');
    }
    final startedAt = Stopwatch()..start();
    final result = await _mcpToolService.callTool(
      server: server,
      toolName: mcpTool.id,
      arguments: decodedArguments,
      toolCallId: toolCall.id,
    );
    final outputText = result.outputText.trim().isEmpty
        ? 'The MCP tool returned no output.'
        : result.outputText.trim();
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
        '${decodedArguments['task'] ?? decodedArguments['prompt'] ?? ''}'
            .trim();
    final String manifestContent;
    try {
      manifestContent = await File(skill.manifestPath).readAsString();
    } on FileSystemException catch (error) {
      return _invalidToolResult(
        toolCall.name,
        'Failed to read skill manifest at "${skill.manifestPath}": ${error.message}',
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
    if ((skill.defaultPrompt ?? '').trim().isNotEmpty) {
      buffer
        ..writeln('default_prompt:')
        ..writeln(skill.defaultPrompt!.trimRight());
    }
    if (requestedTask.isNotEmpty) {
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
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: tool.name,
      workingDirectory: skill.directoryPath,
      stdout: buffer.toString().trim(),
      stderr: '',
      durationMs: startedAt.elapsedMilliseconds,
      resultText: buffer.toString().trim(),
      metadata: <String, Object?>{
        'tool_source': 'skill',
        'skill_name': skill.name,
        'skill_manifest_path': skill.manifestPath,
        'skill_directory_path': skill.directoryPath,
      },
    );
  }

  String _hookToolName(AiResolvedTool tool) {
    return switch (tool.builtinKind) {
      AiBuiltinToolKind.task => 'Task',
      AiBuiltinToolKind.bash => 'Bash',
      AiBuiltinToolKind.bashBackground => 'BashBackground',
      AiBuiltinToolKind.taskOutput => 'TaskOutput',
      AiBuiltinToolKind.taskStop => 'TaskStop',
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
      null => tool.name,
    };
  }

  String _hookMatcherValue(AiResolvedTool tool, String hookToolName) {
    return switch (tool.builtinKind) {
      AiBuiltinToolKind.lsp => '$hookToolName\nLsp',
      _ => hookToolName,
    };
  }

  String _hookWorkingDirectory(Map<String, Object?> decodedArguments) {
    final rawWorkingDirectory =
        '${decodedArguments['working_directory'] ?? decodedArguments['cwd'] ?? ''}'
            .trim();
    return rawWorkingDirectory.isEmpty
        ? AiToolUtils.defaultWorkingDirectory()
        : rawWorkingDirectory;
  }

  // 2026-04-01 10:27:21
  // H1: 移除 camelCase 双写字段（hookEventName / sessionId / toolName / toolInput / toolOutput）
  //     外部 hook 脚本统一使用 snake_case 字段，序列化体积减少约 50%。
  // M2: 新增 tool_source 字段，hook 脚本可按 builtin/mcp/skill 路由处理逻辑。
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
    final blockReason = hookResult.blockReason?.trim().isNotEmpty == true
        ? hookResult.blockReason!.trim()
        : 'Blocked by hook.';
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
    final linkedPaths = RegExp(r'\[[^\]]+\]\(([^)]+)\)', multiLine: true)
        .allMatches(manifestContent)
        .map((match) => match.group(1) ?? '')
        .where((value) {
          final trimmed = value.trim();
          return trimmed.isNotEmpty &&
              !trimmed.startsWith('http://') &&
              !trimmed.startsWith('https://') &&
              !trimmed.startsWith('#');
        })
        .toSet();
    if (linkedPaths.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (final linkedPath in linkedPaths) {
      if (p.isAbsolute(linkedPath) ||
          safeRelativePathError(linkedPath) != null) {
        continue;
      }
      final resolvedPath = p.normalize(p.join(skillDirectoryPath, linkedPath));
      if (!isPathWithinOrEqual(skillDirectoryPath, resolvedPath)) {
        continue;
      }
      final entityType = FileSystemEntity.typeSync(resolvedPath);
      if (entityType == FileSystemEntityType.notFound) {
        continue;
      }
      buffer.writeln('- path: $linkedPath');
      if (entityType == FileSystemEntityType.directory) {
        final entries = await Directory(
          resolvedPath,
        ).list(followLinks: false).toList();
        entries.sort((left, right) => left.path.compareTo(right.path));
        for (final entry in entries.take(20)) {
          buffer.writeln('  - ${p.basename(entry.path)}');
        }
        continue;
      }
      try {
        final linkedFile = File(resolvedPath);
        final linkedFileLength = await linkedFile.length();
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
    final normalizedPrefix = _normalizeToolToken(prefix);
    final normalizedToken = _normalizeToolToken(token);
    var candidate = '${normalizedPrefix}__$normalizedToken';
    if (candidate.length > _maxToolNameLength) {
      final hash = _stableToolNameHash(token);
      final allowedTokenLength =
          _maxToolNameLength - normalizedPrefix.length - hash.length - 4;
      final shortenedToken = normalizedToken.substring(
        0,
        allowedTokenLength > 8 && allowedTokenLength < normalizedToken.length
            ? allowedTokenLength
            : (normalizedToken.length < 24 ? normalizedToken.length : 24),
      );
      candidate = '${normalizedPrefix}__${shortenedToken}_$hash';
      if (candidate.length > _maxToolNameLength) {
        candidate = candidate.substring(0, _maxToolNameLength);
      }
    }
    var suffix = 1;
    var uniqueCandidate = candidate;
    while (takenNames.contains(uniqueCandidate)) {
      uniqueCandidate = _toolNameWithUniqueSuffix(candidate, suffix++);
    }
    return uniqueCandidate;
  }

  String _toolNameWithUniqueSuffix(String candidate, int suffix) {
    final suffixToken = '_$suffix';
    final baseLength = math.max(1, _maxToolNameLength - suffixToken.length);
    final base = candidate.length > baseLength
        ? candidate.substring(0, baseLength)
        : candidate;
    final value = '$base$suffixToken';
    return value.length > _maxToolNameLength
        ? value.substring(0, _maxToolNameLength)
        : value;
  }

  String _stableToolNameHash(String value) {
    var hash = 0x811c9dc5;
    for (final code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _normalizeToolToken(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? 'tool' : sanitized;
  }

  AiResolvedTool _buildMcpTool({
    required McpServer server,
    required McpTool tool,
    required Set<String> takenNames,
  }) {
    final name = _safeToolName('mcp__${server.name}', tool.id, takenNames);
    final descriptionParts = <String>[
      'MCP tool from server "${server.name}".',
      if (tool.description.trim().isNotEmpty) tool.description.trim(),
      if (tool.name.trim() != tool.id.trim()) 'Display name: ${tool.name}.',
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

  /// Skill catalog cap: the catalog only ships skill metadata; the full
  /// SKILL.md body is loaded on demand through the per-skill `skill__<name>`
  /// tool.
  static const int _skillCatalogDescriptionCap = 512;

  AiResolvedTool _buildSkillTool(LocalSkill skill, Set<String> takenNames) {
    final token = p.basename(skill.relativeDirectoryPath.trim()).isEmpty
        ? skill.name
        : p.basename(skill.relativeDirectoryPath.trim());
    final name = _safeToolName('skill', token, takenNames);
    final rawSummary = skill.description.trim();
    final summary = rawSummary.length > _skillCatalogDescriptionCap
        ? '${rawSummary.substring(0, _skillCatalogDescriptionCap - 1).trimRight()}…'
        : rawSummary;
    final description = [
      'Load the full instructions for the local skill "${skill.name}" only when the current request clearly matches it.',
      summary,
      'Do not call this for greetings, casual chat, simple answers, or underspecified creative requests; answer directly or ask a clarifying question instead.',
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
          'skill_name': tool.skill!.name,
          'skill_manifest_path': tool.skill!.manifestPath,
          'skill_directory_path': tool.skill!.directoryPath,
        },
      },
    };
  }

  void dispose() {
    unawaited(_scraplingBridge.dispose());
    _bashToolService.dispose();
    _httpClient.close();
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
            'description':
                'Short task title for hook logs and parent transcript.',
          },
          'prompt': <String, Object?>{
            'type': 'string',
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
          'Execute a shell command in a subprocess. Use command (Claude-style) or cmd for the command string and optionally working_directory/cwd for the working directory. Set run_in_background to true for Claude-style long-running commands that should be started through BashBackground. '
          'For code/text search, prefer the dedicated Grep tool (which is backed by the application-bundled ripgrep binary) over shelling out to `grep`/`rg`. '
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
          'timeout': <String, Object?>{'type': 'integer'},
          'timeout_ms': <String, Object?>{
            'type': 'integer',
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
          'max_bytes': <String, Object?>{'type': 'integer'},
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
            'description':
                'Maximum wait time in milliseconds when block=true. Defaults to 30000 and is capped at 600000.',
          },
          'timeout_ms': <String, Object?>{
            'type': 'integer',
            'description': 'Alias for timeout.',
          },
          'max_bytes': <String, Object?>{
            'type': 'integer',
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
          'Claude-style compatibility tool for stopping an OpenHand background shell task. '
          'Use task_id with the BashBackground handle returned by Bash(run_in_background=true) or BashBackground start. '
          'shell_id is accepted for deprecated KillShell compatibility. This is routed internally to BashBackground stop.',
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
            'description': 'The line number (1-based, as shown in editors)',
          },
          'character': <String, Object?>{
            'type': 'integer',
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
          '-B': <String, Object?>{'type': 'integer'},
          '-A': <String, Object?>{'type': 'integer'},
          '-C': <String, Object?>{'type': 'integer'},
          'context': <String, Object?>{
            'type': 'integer',
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
            'description':
                'Limit output to the first N lines or entries after offset. Defaults to 250; pass 0 only when unlimited output is intentional.',
          },
          'offset': <String, Object?>{
            'type': 'integer',
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
            'description': 'Maximum number of lines to read. Defaults to 2000.',
          },
          'pages': <String, Object?>{
            'type': 'string',
            'description':
                'Claude-style PDF page range such as "1", "1-5", or "1,3-5". Maximum 20 pages. Current runtime returns PDF metadata and the requested range, not extracted page text.',
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
            'description': 'For blame: start line (1-based).',
          },
          'end_line': <String, Object?>{
            'type': 'integer',
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
          'Fetch full schema definitions for deferred runtime tools so they '
          'become callable. Deferred tools may be MCP tools or built-in tools '
          'whose load strategy is lazy/deferred. Their full schemas are '
          'omitted from the prompt to save context; names and short summaries '
          'appear in this description. Without ToolSearch, only already '
          'visible tools are callable.\n\n'
          'Query forms:\n'
          '- `select:Name1,Name2` — fetch these exact tools by name (best '
          'when you already know the tool name).\n'
          '- `slack send` — keyword search; ranks deferred tools by '
          'matches against their name parts and descriptions.\n'
          '- `+github issues list` — prefix a term with `+` to make it '
          'required; remaining terms refine the ranking.\n\n'
          'Result: matched tools are returned inside a `<functions>` block '
          'whose entries follow the same JSONSchema encoding as the tools '
          'declared at the top of the prompt. Once a tool appears in that '
          'result, invoke it by exact name from the next model request onward. '
          'Issuing the same query twice with different keywords is fine; '
          'ToolSearch is read-only and side-effect free.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
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
        },
        'required': <String>['query'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.memory,
      name: 'Memory',
      description:
          'Manage the user memory store (Hermes Talker self-learning only). '
          'Supported actions: `list` (optional tag filter), `append` '
          '(insert a new memory), `upsert_profile` (create or replace the '
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
            'description': 'Required for `update`/`delete`.',
          },
          'content': <String, Object?>{
            'type': 'string',
            'description':
                'Memory content. Required for `append`/`upsert_profile`/'
                '`update`.',
          },
          'title': <String, Object?>{
            'type': 'string',
            'description':
                'Optional short title (≤80 chars) for the memory entry. '
                'Used by the UI as the card heading; falls back to a '
                'preview of `content` when omitted. For `update`, omit to '
                'keep the existing title, pass an empty string to clear it.',
          },
          'tags': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description': 'Optional list of tags to attach to the entry.',
          },
          'tag': <String, Object?>{
            'type': 'string',
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
    // 2026-04-27: 统一为所有内建工具注入可选 purpose 字段。
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

  /// Inject an optional `purpose` string property into a JSON-schema-style
  /// parameters object. Returns a new map; the original is not mutated.
  /// If [parameters] is not an `object` schema, it is returned unchanged.
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

  /// Returns the default (unmodified) [AiResolvedTool] for the given
  /// [AiBuiltinToolKind], or `null` if no such built-in tool exists.
  static AiResolvedTool? builtinToolDefault(AiBuiltinToolKind kind) {
    for (final tool in _builtinTools) {
      if (tool.builtinKind == kind) return tool;
    }
    return null;
  }
}

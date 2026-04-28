import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../mcp/model/mcp_server.dart';
import '../../mcp/model/mcp_tool.dart';
import '../../mcp/service/mcp_tool_discovery_service.dart';
import '../../skills/model/local_skill.dart';
import '../model/ai_builtin_tool_config.dart';
import '../model/ai_deny_command_rule.dart';
import '../model/ai_model_config.dart';
import '../model/ai_session_runtime_context.dart';
import '../tools/ai_memory_tool.dart';
import '../tools/ai_tool_registry.dart';
import '../tools/ai_tool_utils.dart';
import 'ai_bash_tool_service.dart';
import 'ai_chat_service.dart';
import 'ai_claude_hook_service.dart';
import 'ai_file_history_service.dart';
import 'ai_file_tracker_service.dart';
import 'ai_protocol_adapter.dart';

enum AiRuntimeToolSource { builtin, mcp, skill }

class AiResolvedToolCatalog {
  const AiResolvedToolCatalog({
    required this.definitions,
    required this.toolsByName,
    this.notices = const <String>[],
  });

  final List<AiToolDefinition> definitions;
  final Map<String, AiResolvedTool> toolsByName;
  final List<String> notices;

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
  });

  final String name;
  final AiToolDefinition definition;
  final AiRuntimeToolSource source;
  final AiBuiltinToolKind? builtinKind;
  final McpServer? mcpServer;
  final McpTool? mcpTool;
  final LocalSkill? skill;
}

enum AiBuiltinToolKind {
  task,
  bash,
  glob,
  grep,
  ls,
  exitPlanMode,
  read,
  edit,
  multiEdit,
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
      metadata: metadata,
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
    String Function()? skillsDirProvider,
    MemoryControllerProvider? memoryControllerProvider,
  }) : _bashToolService = bashToolService,
       _hookService = hookService,
       _mcpToolService = mcpToolService,
       _backgroundChatClient = backgroundChatClient,
       _httpClient = httpClient ?? http.Client(),
       _hostLookup = hostLookup ?? ((host) => InternetAddress.lookup(host)),
       _fileTracker = fileTrackerService ?? AiFileTrackerService(),
       _fileHistory = fileHistoryService ?? AiFileHistoryService() {
    // 2026-04-01 02:02:39 初始化完整服务依赖注入的多态工具注册中心
    _toolRegistry = AiToolRegistry.withServiceDependencies(
      bashToolService: _bashToolService,
      hookService: _hookService,
      backgroundChatClient: _backgroundChatClient,
      httpClient: _httpClient,
      hostLookup: _hostLookup,
      skillsDirProvider: skillsDirProvider,
      memoryControllerProvider: memoryControllerProvider,
    );
  }

  final AiBashToolService _bashToolService;
  final AiClaudeHookService _hookService;
  final McpToolDiscoveryService _mcpToolService;
  final AiChatClient _backgroundChatClient;
  final http.Client _httpClient;
  final Future<List<InternetAddress>> Function(String host) _hostLookup;
  late final AiToolRegistry _toolRegistry;

  /// Group C — 暴露给 [AiSessionController]，用于把 runtime context 中的网络
  /// 类参数下放到 [AiWebFetchTool] 实例。
  AiToolRegistry get toolRegistry => _toolRegistry;

  // 2026-04-12: 文件追踪和历史版本服务
  final AiFileTrackerService _fileTracker;
  final AiFileHistoryService _fileHistory;

  /// 获取文件追踪服务（供外部访问，如会话重置时清理）
  AiFileTrackerService get fileTracker => _fileTracker;

  /// 获取文件历史服务（供外部访问，如回滚功能）
  AiFileHistoryService get fileHistory => _fileHistory;

  static const int _maxToolNameLength = 64;

  /// 2026-04-01 工具输出单轮最大字符数限制。
  /// 超过此限制时截断并附刚抽提提示，防止 Context 溢出和 API token 超限。
  /// 2026-04-29 — Group B: 由用户设置注入，可运行时调整。
  int maxToolOutputChars = 200000;

  /// Template ID for which `skill_manager` is exposed as a builtin. All other
  /// templates never see `skill_manager` in their tool catalog regardless of
  /// user builtin-tool configs.
  static const String _skillManagerTemplateId = 'hermes_talker';

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
        result.add(baseTool);
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
        ),
      );
    }
    return result;
  }

  Future<AiResolvedToolCatalog> resolveCatalog({
    required AiSessionRuntimeContext runtimeContext,
    String? templateId,
  }) async {
    final definitions = <AiToolDefinition>[];
    final toolsByName = <String, AiResolvedTool>{};
    final notices = <String>[];

    void register(AiResolvedTool tool) {
      if (toolsByName.containsKey(tool.name)) {
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
    for (final skill in runtimeContext.availableSkills) {
      final tool = _buildSkillTool(skill, toolsByName.keys.toSet());
      register(tool);
    }

    // ── 第二优先级：MCP 工具 ──────────────────────────────────────
    final enabledServers = runtimeContext.availableMcpServers
        .where((item) => item.enabled)
        .toList(growable: false);
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
        final takenNames = toolsByName.keys.toSet();
        for (final mcpTool in catalog.tools) {
          final tool = _buildMcpTool(
            server: server,
            tool: mcpTool,
            takenNames: takenNames,
          );
          takenNames.add(tool.name);
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
    // 2026-04-01 已移除 register(_legacyBashAlias)：
    // 'bash' 别名现由 AiBashTool.aliases + AiToolRegistry._aliasToKind 统一管理。

    return AiResolvedToolCatalog(
      definitions: definitions,
      toolsByName: toolsByName,
      notices: notices,
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
    final notices = <String>[];

    void register(AiResolvedTool tool) {
      if (toolsByName.containsKey(tool.name)) {
        return;
      }
      toolsByName[tool.name] = tool;
      definitions.add(tool.definition);
    }

    // 2026-04-08 能力调用优先级：Skill > MCP > Builtin（与 resolveCatalog 保持一致）

    // ── 第一优先级：Skill 工具 ─────────────────────────────────────
    for (final skill in runtimeContext.availableSkills) {
      final tool = _buildSkillTool(skill, toolsByName.keys.toSet());
      register(tool);
    }

    // ── 第二优先级：MCP 工具 ──────────────────────────────────────
    final enabledServers = runtimeContext.availableMcpServers
        .where((item) => item.enabled)
        .toList(growable: false);
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
      final takenNames = toolsByName.keys.toSet();
      for (final mcpTool in catalog.tools) {
        final tool = _buildMcpTool(
          server: server,
          tool: mcpTool,
          takenNames: takenNames,
        );
        takenNames.add(tool.name);
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
    required Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    Future<void>? cancelSignal,
    void Function(BashToolExecutionUpdate update)? onBashUpdate,
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
        guidance.write(
          ' The tool catalog is empty for this turn — usually because the '
          'system is waiting for the user to approve a pending plan. Do NOT '
          'invent tool names; respond by presenting the captured plan and '
          'asking the user to confirm. Once approved, the next turn will '
          'restore Write/Edit/MultiEdit/Bash automatically.',
        );
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
      );
    }
    final decodedArguments = AiToolUtils.decodeArguments(toolCall.arguments);
    final hookToolName = _hookToolName(resolvedTool);
    final hookWorkingDirectory = _hookWorkingDirectory(decodedArguments);
    final preHookResult = await _hookService.runHooks(
      eventName: 'PreToolUse',
      sessionId: sessionId,
      matcherValue: hookToolName,
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
    late final AiToolExecutionResult rawResult;
    try {
      rawResult = await switch (resolvedTool.source) {
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
    } catch (error) {
      rawResult = _toolExecutionErrorResult(
        tool: resolvedTool,
        fallbackWorkingDirectory: hookWorkingDirectory,
        error: error,
        durationMs: rawExecutionStartedAt.elapsedMilliseconds,
      );
    }
    final postHookResult = await _hookService.runHooks(
      eventName: rawResult.status == BashToolExecutionStatus.success
          ? 'PostToolUse'
          : 'PostToolUseFailure',
      sessionId: sessionId,
      matcherValue: hookToolName,
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
    return _applyOutputBudget(
      _mergeHookResultIntoToolResult(
        rawResult: rawResult,
        preHookResult: preHookResult,
        postHookResult: postHookResult,
      ),
    );
  }

  // 2026-04-01 工具输出 budget 截断。
  // 对 resultText 进行字符数上限保护，超限时截断内容并附上提示。
  // 这防止了单次工具调用将大量输出（如 WebFetch 、Bash cat 大文件）直接塑进 API 上下文。
  // FIX: stdout/stderr 截断边界与 resultText 保持一致，避免上下文看到不同片段。
  AiToolExecutionResult _applyOutputBudget(AiToolExecutionResult result) {
    final rawResult = result.resultText;
    if (rawResult.length <= maxToolOutputChars) {
      return result;
    }
    final truncated = rawResult.substring(0, maxToolOutputChars);
    final notice =
        '\n\n[Output truncated: result exceeded the $maxToolOutputChars-character tool output budget. '
        'Only the first $maxToolOutputChars characters are included. '
        'Use more targeted commands or file offsets to read the remaining content.]';
    final truncatedResult = '$truncated$notice';
    // Keep stdout and stderr consistent with resultText: all are capped at maxToolOutputChars.
    final truncatedStdout = result.stdout.length > maxToolOutputChars
        ? '${result.stdout.substring(0, maxToolOutputChars)}$notice'
        : result.stdout;
    final truncatedStderr = result.stderr.length > maxToolOutputChars
        ? '${result.stderr.substring(0, maxToolOutputChars)}$notice'
        : result.stderr;
    return AiToolExecutionResult(
      status: result.status,
      command: result.command,
      workingDirectory: result.workingDirectory,
      stdout: truncatedStdout,
      stderr: truncatedStderr,
      durationMs: result.durationMs,
      resultText: truncatedResult,
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
    required Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    Future<void>? cancelSignal,
    void Function(BashToolExecutionUpdate update)? onBashUpdate,
  }) async {
    final kind = tool.builtinKind;
    if (kind == null) {
      return _invalidToolResult(
        toolCall.name,
        'Missing builtin tool metadata.',
      );
    }
    // 2026-04-01 优先通过多态 Registry 路由（轻量工具已迁移）
    // 2026-04-12 通过 metadata 传递文件追踪和历史服务（遵循 AiToolExecutionContext 冻结约束）
    final registryContext = AiToolExecutionContext(
      sessionId: sessionId,
      catalog: catalog,
      toolCall: toolCall,
      decodedArguments: decodedArguments,
      model: model,
      previouslyReadFiles: previouslyReadFiles,
      denyCommandRules: denyCommandRules,
      requireWriteCommandConfirmation: requireWriteCommandConfirmation,
      confirmWriteCommand: confirmWriteCommand,
      cancelSignal: cancelSignal,
      onBashUpdate: onBashUpdate,
      metadata: <String, Object?>{
        'file_tracker': _fileTracker,
        'file_history': _fileHistory,
        'write_confirmation_timeout_ms': _bashToolService.writeConfirmationTimeoutMs,
      },
    );
    final registryResult = await _toolRegistry.tryExecute(
      registryContext,
      kind,
    );
    if (registryResult != null) return registryResult;
    // 2026-04-01 所有工具均已通过 Registry 注册，此路径不可达。
    return _invalidToolResult(
      toolCall.name,
      'No registered handler found for builtin tool: ${kind.name}',
    );
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
      AiBuiltinToolKind.glob => 'Glob',
      AiBuiltinToolKind.grep => 'Grep',
      AiBuiltinToolKind.ls => 'LS',
      AiBuiltinToolKind.exitPlanMode => 'ExitPlanMode',
      AiBuiltinToolKind.read => 'Read',
      AiBuiltinToolKind.edit => 'Edit',
      AiBuiltinToolKind.multiEdit => 'MultiEdit',
      AiBuiltinToolKind.write => 'Write',
      AiBuiltinToolKind.notebookEdit => 'NotebookEdit',
      AiBuiltinToolKind.webFetch => 'WebFetch',
      AiBuiltinToolKind.todoWrite => 'TodoWrite',
      AiBuiltinToolKind.webSearch => 'WebSearch',
      AiBuiltinToolKind.lsp => 'Lsp',
      AiBuiltinToolKind.codebaseSearch => 'CodebaseSearch',
      AiBuiltinToolKind.git => 'Git',
      AiBuiltinToolKind.deleteFile => 'DeleteFile',
      AiBuiltinToolKind.readLints => 'ReadLints',
      AiBuiltinToolKind.askUserChoice => 'AskUserChoice',
      AiBuiltinToolKind.skillManager => 'SkillManager',
      AiBuiltinToolKind.memory => 'Memory',
      null => tool.name,
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
      final resolvedPath = p.normalize(
        p.isAbsolute(linkedPath)
            ? linkedPath
            : p.join(skillDirectoryPath, linkedPath),
      );
      if (!p.isWithin(skillDirectoryPath, resolvedPath) &&
          resolvedPath != skillDirectoryPath) {
        continue;
      }
      final entityType = FileSystemEntity.typeSync(resolvedPath);
      if (entityType == FileSystemEntityType.notFound) {
        continue;
      }
      buffer.writeln('- path: $linkedPath');
      if (entityType == FileSystemEntityType.directory) {
        final entries = await Directory(resolvedPath).list().toList();
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
      final hash = token.hashCode.abs().toRadixString(16);
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
      uniqueCandidate = '${candidate}_${suffix++}';
      if (uniqueCandidate.length > _maxToolNameLength) {
        uniqueCandidate = uniqueCandidate.substring(0, _maxToolNameLength);
      }
    }
    return uniqueCandidate;
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

  AiResolvedTool _buildSkillTool(LocalSkill skill, Set<String> takenNames) {
    final token = p.basename(skill.relativeDirectoryPath.trim()).isEmpty
        ? skill.name
        : p.basename(skill.relativeDirectoryPath.trim());
    final name = _safeToolName('skill', token, takenNames);
    final description = [
      'Load and apply the local skill "${skill.name}".',
      skill.description.trim(),
      'Use this when the task matches the skill instead of loosely paraphrasing it.',
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
    _bashToolService.dispose();
    _httpClient.close();
  }

  static final List<AiResolvedTool> _builtinTools = <AiResolvedTool>[
    _builtinTool(
      kind: AiBuiltinToolKind.task,
      name: 'Task',
      description:
          'Launch a focused background subtask for research or reasoning. Available subagent_type values: general-purpose.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'description': <String, Object?>{'type': 'string'},
          'prompt': <String, Object?>{'type': 'string'},
          'subagent_type': <String, Object?>{
            'type': 'string',
            'enum': <String>['general-purpose'],
          },
        },
        'required': <String>['description', 'prompt', 'subagent_type'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.bash,
      name: 'Bash',
      description:
          'Execute a shell command in a subprocess. Use cmd for the command string and optionally working_directory for the working directory. Call this directly when shell work is needed. '
          'For code/text search, prefer the dedicated Grep tool (which is backed by the application-bundled ripgrep binary) over shelling out to `grep`/`rg`. '
          'If a write-like command needs confirmation, OpenHand handles that approval flow automatically.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'cmd': <String, Object?>{'type': 'string'},
          'working_directory': <String, Object?>{'type': 'string'},
          'timeout': <String, Object?>{'type': 'integer'},
        },
        'required': <String>['cmd'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.glob,
      name: 'Glob',
      description:
          'Match file paths against a glob pattern. Returns matching file paths.',
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
                'The directory to search in. Defaults to the working directory.',
          },
        },
        'required': <String>['pattern'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.lsp,
      name: 'Lsp',
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
            'description': 'The absolute or relative path to the file',
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
        'required': <String>['operation', 'file_path', 'line', 'character'],
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
          'glob': <String, Object?>{'type': 'string'},
          'output_mode': <String, Object?>{
            'type': 'string',
            'enum': <String>['content', 'files_with_matches', 'count'],
          },
          '-B': <String, Object?>{'type': 'integer'},
          '-A': <String, Object?>{'type': 'integer'},
          '-C': <String, Object?>{'type': 'integer'},
          '-n': <String, Object?>{'type': 'boolean'},
          '-i': <String, Object?>{'type': 'boolean'},
          'type': <String, Object?>{'type': 'string'},
          'head_limit': <String, Object?>{'type': 'integer'},
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
          'List files and directories under a path. Returns names and types.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'path': <String, Object?>{
            'type': 'string',
            'description': 'The absolute directory path to list.',
          },
          'ignore': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description': 'Patterns of file/directory names to ignore.',
          },
        },
        'required': <String>['path'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.exitPlanMode,
      name: 'ExitPlanMode',
      description:
          'Signal that planning is complete and implementation can begin. The plan argument should be a short numbered or bulleted execution step list.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'plan': <String, Object?>{'type': 'string'},
        },
        'required': <String>['plan'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.read,
      name: 'Read',
      description:
          'Read a local file from disk. The file_path MUST be an absolute path (starting with /).',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{
            'type': 'string',
            'description':
                'The absolute file path to read (must start with /).',
          },
          'offset': <String, Object?>{
            'type': 'integer',
            'description': 'Line offset to start reading from (0-based).',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'description': 'Maximum number of lines to read. Defaults to 2000.',
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
          'The file_path MUST be an absolute path (starting with /).',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{
            'type': 'string',
            'description':
                'The absolute file path to edit (must start with /).',
          },
          'old_string': <String, Object?>{
            'type': 'string',
            'description': 'The exact text to find and replace.',
          },
          'new_string': <String, Object?>{
            'type': 'string',
            'description': 'The replacement text.',
          },
          'replace_all': <String, Object?>{
            'type': 'boolean',
            'description':
                'If true, replace all occurrences. Defaults to false (first match only).',
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
          'The file_path MUST be an absolute path (starting with /).',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{
            'type': 'string',
            'description':
                'The absolute file path to edit (must start with /).',
          },
          'edits': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'old_string': <String, Object?>{'type': 'string'},
                'new_string': <String, Object?>{'type': 'string'},
                'replace_all': <String, Object?>{'type': 'boolean'},
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
      kind: AiBuiltinToolKind.write,
      name: 'Write',
      description:
          'Create or overwrite a file on disk. The file_path MUST be an absolute path (starting with /). '
          'Parent directories are created automatically if they do not exist. '
          'Arguments must be a flat JSON object with exactly two string keys. '
          'Example: {"file_path":"/tmp/hello.txt","content":"hello world"}',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{
            'type': 'string',
            'description':
                'The absolute file path to write to (must start with /). Example: /Users/name/project/file.md',
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
      description: 'Edit a Jupyter notebook cell.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'notebook_path': <String, Object?>{'type': 'string'},
          'cell_id': <String, Object?>{'type': 'string'},
          'new_source': <String, Object?>{'type': 'string'},
          'cell_type': <String, Object?>{'type': 'string'},
          'edit_mode': <String, Object?>{
            'type': 'string',
            'enum': <String>['replace', 'insert', 'delete'],
          },
        },
        'required': <String>['notebook_path', 'new_source'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.webFetch,
      name: 'WebFetch',
      description:
          'Fetch a URL and answer a prompt against the fetched content.',
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
          'Each object needs id (string), content (string) and status '
          '("pending"|"in_progress"|"completed"|"failed"). At most one in_progress at a time. '
          'Example: {"todos":[{"id":"1","content":"Step A","status":"in_progress"},{"id":"2","content":"Step B","status":"pending"}]}',
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
              },
              'required': <String>['content', 'status', 'id'],
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
            'description': 'Absolute or relative path to the file to delete.',
          },
        },
        'required': <String>['file_path'],
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
          'existing skill. Confirm with the user before calling `delete`.',
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
      kind: AiBuiltinToolKind.memory,
      name: 'Memory',
      description:
          'Manage the user memory store (Hermes Talker self-learning only). '
          'Supported actions: `list` (optional tag filter), `append` '
          '(insert a new memory), `upsert_profile` (create or replace the '
          'single user_profile entry), `update` (by id), `delete` (by id).',
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

  // 2026-04-01 _legacyBashAlias 已迁移至 AiBashTool.aliases = ['bash']
  // AiToolRegistry.register() 会自动处理别名注册，此处无需保留。

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

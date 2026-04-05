import 'dart:async';
import 'dart:io';

// 2026-04-01 02:29:02
// 变更1：移除 _legacyBashAlias 硬编码（已由 AiBashTool.aliases + AiToolRegistry 接管）
// 变更2：增加工具输出 budget 截断保护（_maxToolOutputChars = 200000 字符）


import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../mcp/model/mcp_server.dart';
import '../../mcp/model/mcp_tool.dart';
import '../../mcp/service/mcp_tool_discovery_service.dart';
import '../../skills/model/local_skill.dart';
import '../model/ai_deny_command_rule.dart';
import '../model/ai_model_config.dart';
import '../model/ai_session_runtime_context.dart';
import '../tools/ai_tool_registry.dart';
import '../tools/ai_tool_utils.dart';
import 'ai_bash_tool_service.dart';
import 'ai_chat_service.dart';
import 'ai_claude_hook_service.dart';
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
    final normalizedName = name.trim().toLowerCase();
    for (final entry in toolsByName.entries) {
      if (entry.key.trim().toLowerCase() == normalizedName) {
        return entry.value;
      }
    }
    return null;
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
  }) : _bashToolService = bashToolService,
       _hookService = hookService,
       _mcpToolService = mcpToolService,
       _backgroundChatClient = backgroundChatClient,
       _httpClient = httpClient ?? http.Client(),
       _hostLookup =
           hostLookup ??
           ((host) => InternetAddress.lookup(host)) {
    // 2026-04-01 02:02:39 初始化完整服务依赖注入的多态工具注册中心
    _toolRegistry = AiToolRegistry.withServiceDependencies(
      bashToolService: _bashToolService,
      hookService: _hookService,
      backgroundChatClient: _backgroundChatClient,
      httpClient: _httpClient,
      hostLookup: _hostLookup,
    );
  }

  final AiBashToolService _bashToolService;
  final AiClaudeHookService _hookService;
  final McpToolDiscoveryService _mcpToolService;
  final AiChatClient _backgroundChatClient;
  final http.Client _httpClient;
  final Future<List<InternetAddress>> Function(String host) _hostLookup;
  late final AiToolRegistry _toolRegistry;

  static const int _maxToolNameLength = 64;

  /// 2026-04-01 工具输出单轮最大字符数限制。
  /// 超过此限制时截断并附刚抽提提示，防止 Context 溢出和 API token 超限。
  static const int _maxToolOutputChars = 200000;

  Future<AiResolvedToolCatalog> resolveCatalog({

    required AiSessionRuntimeContext runtimeContext,
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

    for (final tool in _builtinTools) {
      register(tool);
    }
    // 2026-04-01 已移除 register(_legacyBashAlias)：
    // 'bash' 别名现由 AiBashTool.aliases + AiToolRegistry._aliasToKind 统一管理。

    for (final skill in runtimeContext.availableSkills) {
      final tool = _buildSkillTool(skill, toolsByName.keys.toSet());
      register(tool);
    }

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

    for (final tool in _builtinTools) {
      register(tool);
    }
    // 2026-04-01 已移除 register(_legacyBashAlias)：
    // 'bash' 别名现由 AiBashTool.aliases + AiToolRegistry._aliasToKind 统一管理。

    for (final skill in runtimeContext.availableSkills) {
      final tool = _buildSkillTool(skill, toolsByName.keys.toSet());
      register(tool);
    }

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
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.invalidArguments,
        command: toolCall.name,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: 'Unsupported tool name: ${toolCall.name}',
        durationMs: 0,
        resultText:
            'status: invalid_arguments\nerror: Unsupported tool name: ${toolCall.name}',
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
  // FIX: stdout 截断边界与 resultText 保持一致，避免上下文看到不同片段。
  AiToolExecutionResult _applyOutputBudget(AiToolExecutionResult result) {
    final rawResult = result.resultText;
    if (rawResult.length <= _maxToolOutputChars) {
      return result;
    }
    final truncated = rawResult.substring(0, _maxToolOutputChars);
    const notice =
        '\n\n[Output truncated: result exceeded the 200,000-character tool output budget. '
        'Only the first 200,000 characters are included. '
        'Use more targeted commands or file offsets to read the remaining content.]';
    final truncatedResult = '$truncated$notice';
    // Keep stdout consistent with resultText: both are capped at _maxToolOutputChars.
    final truncatedStdout = result.stdout.length > _maxToolOutputChars
        ? '${result.stdout.substring(0, _maxToolOutputChars)}$notice'
        : result.stdout;
    return AiToolExecutionResult(
      status: result.status,
      command: result.command,
      workingDirectory: result.workingDirectory,
      stdout: truncatedStdout,
      stderr: result.stderr,
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
        'tool_output_budget_chars': _maxToolOutputChars,
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
    );
    final registryResult = await _toolRegistry.tryExecute(registryContext, kind);
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
        final previewBytes = await AiToolUtils.readFilePrefix(linkedFile, linkedFileLength);
        final extension = p.extension(resolvedPath).toLowerCase();
        if (AiToolUtils.looksBinary(previewBytes) && !AiToolUtils.isKnownTextExtension(extension)) {
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
          'Execute a shell command in a subprocess. Use cmd for the command string and optionally working_directory for the working directory. Call this directly when shell work is needed. If a write-like command needs confirmation, OpenHand handles that approval flow automatically.',
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
      description: 'Match file paths against a glob pattern.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'pattern': <String, Object?>{'type': 'string'},
          'path': <String, Object?>{'type': 'string'},
        },
        'required': <String>['pattern'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.lsp,
      name: 'Lsp',
      description: 'Code intelligence (definitions, references, symbols, hover) based on LSP.',
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
              'outgoingCalls'
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
            'description': 'The character offset (1-based, as shown in editors)',
          },
        },
        'required': <String>['operation', 'file_path', 'line', 'character'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.grep,
      name: 'Grep',
      description: 'Search file contents using ripgrep-compatible arguments.',
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
      description: 'List files and directories under a path.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'path': <String, Object?>{'type': 'string'},
          'ignore': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
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
      description: 'Read a local file from disk.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{'type': 'string'},
          'offset': <String, Object?>{'type': 'integer'},
          'limit': <String, Object?>{'type': 'integer'},
        },
        'required': <String>['file_path'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.edit,
      name: 'Edit',
      description: 'Perform an exact string replacement in a file.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{'type': 'string'},
          'old_string': <String, Object?>{'type': 'string'},
          'new_string': <String, Object?>{'type': 'string'},
          'replace_all': <String, Object?>{'type': 'boolean'},
        },
        'required': <String>['file_path', 'old_string', 'new_string'],
        'additionalProperties': false,
      },
    ),
    _builtinTool(
      kind: AiBuiltinToolKind.multiEdit,
      name: 'MultiEdit',
      description: 'Perform multiple exact string replacements in a file.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{'type': 'string'},
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
      description: 'Write a file to disk.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'file_path': <String, Object?>{'type': 'string'},
          'content': <String, Object?>{'type': 'string'},
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
          'Create or update the structured todo list for the current task.',
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
      description: 'Search the web for current information.',
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
  ];

  // 2026-04-01 _legacyBashAlias 已迁移至 AiBashTool.aliases = ['bash']
  // AiToolRegistry.register() 会自动处理别名注册，此处无需保留。

  static AiResolvedTool _builtinTool({
    required AiBuiltinToolKind kind,
    required String name,
    required String description,
    required Map<String, Object?> parameters,
  }) {
    return AiResolvedTool(
      name: name,
      definition: AiToolDefinition(
        name: name,
        description: description,
        parameters: parameters,
      ),
      source: AiRuntimeToolSource.builtin,
      builtinKind: kind,
    );
  }
}


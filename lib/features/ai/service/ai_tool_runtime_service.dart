import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../mcp/model/mcp_server.dart';
import '../../mcp/model/mcp_tool.dart';
import '../../mcp/service/mcp_tool_discovery_service.dart';
import '../../skills/model/local_skill.dart';
import '../model/ai_deny_command_rule.dart';
import '../model/ai_model_config.dart';
import '../model/ai_session_runtime_context.dart';
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
}

class AiToolExecutionResult {
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
}

class AiToolRuntimeService {
  AiToolRuntimeService({
    required AiBashToolService bashToolService,
    required AiClaudeHookService hookService,
    required McpToolDiscoveryService mcpToolService,
    required AiChatClient backgroundChatClient,
    http.Client? httpClient,
  }) : _bashToolService = bashToolService,
       _hookService = hookService,
       _mcpToolService = mcpToolService,
       _backgroundChatClient = backgroundChatClient,
       _httpClient = httpClient ?? http.Client();

  static const int _maxFileCharacters = 64000;
  static const int _maxReadBytes = _maxFileCharacters * 4;
  static const int _maxSearchOutputCharacters = 24000;
  static const int _maxWebContentCharacters = 20000;
  static const int _maxReadLineLength = 2000;
  static const int _defaultReadLimit = 2000;
  static const int _maxToolNameLength = 64;
  static const int _maxBinaryPreviewBytes = 32;
  static const int _maxWebFetchRedirects = 5;
  static const Duration _webFetchCacheTtl = Duration(minutes: 15);
  static const Map<String, String> _taskSubagentDescriptions = <String, String>{
    'general-purpose':
        'General-purpose agent for researching complex questions, searching for code, and executing multi-step tasks.',
  };

  final AiBashToolService _bashToolService;
  final AiClaudeHookService _hookService;
  final McpToolDiscoveryService _mcpToolService;
  final AiChatClient _backgroundChatClient;
  final http.Client _httpClient;
  final Map<String, _CachedWebFetchContent> _webFetchCache =
      <String, _CachedWebFetchContent>{};

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
    register(_legacyBashAlias);

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
        workingDirectory: _defaultWorkingDirectory(),
        stdout: '',
        stderr: 'Unsupported tool name: ${toolCall.name}',
        durationMs: 0,
        resultText:
            'status: invalid_arguments\nerror: Unsupported tool name: ${toolCall.name}',
      );
    }
    final decodedArguments = _decodeArguments(toolCall.arguments);
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
    return _mergeHookResultIntoToolResult(
      rawResult: rawResult,
      preHookResult: preHookResult,
      postHookResult: postHookResult,
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
    final startedAt = Stopwatch()..start();
    try {
      return switch (kind) {
        AiBuiltinToolKind.task => await _executeTaskTool(
          sessionId,
          toolCall.id,
          decodedArguments,
          model,
          catalog,
          denyCommandRules,
          requireWriteCommandConfirmation,
          confirmWriteCommand,
          startedAt,
          cancelSignal,
        ),
        AiBuiltinToolKind.bash => () async {
          final permissionHookReminders = <String>[];
          final wrappedConfirmWriteCommand = confirmWriteCommand == null
              ? null
              : (BashCommandApprovalRequest request) async {
                  final permissionHookResult = await _hookService.runHooks(
                    eventName: 'PermissionRequest',
                    sessionId: sessionId,
                    matcherValue: 'Bash',
                    cwd: request.workingDirectory,
                    payload: <String, Object?>{
                      'tool_name': 'Bash',
                      'toolName': 'Bash',
                      'command': request.command,
                      'working_directory': request.workingDirectory,
                      'permission_type': 'write_command_confirmation',
                      'is_write_command': request.isWriteCommand,
                    },
                  );
                  permissionHookReminders.addAll(
                    permissionHookResult.systemReminders,
                  );
                  if (permissionHookResult.blocked) {
                    final notificationHookResult = await _runAuxiliaryHook(
                      eventName: 'Notification',
                      sessionId: sessionId,
                      matcherValue: 'permission_prompt',
                      cwd: request.workingDirectory,
                      payload: <String, Object?>{
                        'notification_type': 'permission_prompt',
                        'tool_name': 'Bash',
                        'command': request.command,
                        'status': 'blocked',
                      },
                    );
                    permissionHookReminders.addAll(
                      notificationHookResult.systemReminders,
                    );
                    return false;
                  }
                  final approved = await confirmWriteCommand(request);
                  final notificationHookResult = await _runAuxiliaryHook(
                    eventName: 'Notification',
                    sessionId: sessionId,
                    matcherValue: 'permission_prompt',
                    cwd: request.workingDirectory,
                    payload: <String, Object?>{
                      'notification_type': 'permission_prompt',
                      'tool_name': 'Bash',
                      'command': request.command,
                      'status': approved ? 'approved' : 'rejected',
                    },
                  );
                  permissionHookReminders.addAll(
                    notificationHookResult.systemReminders,
                  );
                  return approved;
                };
          final bashResult = await _executeBashTool(
            sessionId: sessionId,
            decodedArguments: decodedArguments,
            denyCommandRules: denyCommandRules,
            requireWriteCommandConfirmation: requireWriteCommandConfirmation,
            confirmWriteCommand: wrappedConfirmWriteCommand,
            cancelSignal: cancelSignal,
            onBashUpdate: onBashUpdate,
          );
          return AiToolExecutionResult.fromBash(
            bashResult,
            metadata: permissionHookReminders.isEmpty
                ? const <String, Object?>{}
                : <String, Object?>{
                    aiHookSystemRemindersMetadataKey: permissionHookReminders,
                  },
          );
        }(),
        AiBuiltinToolKind.glob => await _executeGlobTool(
          decodedArguments,
          startedAt,
        ),
        AiBuiltinToolKind.grep => await _executeGrepTool(
          decodedArguments,
          startedAt,
        ),
        AiBuiltinToolKind.ls => await _executeLsTool(
          decodedArguments,
          startedAt,
        ),
        AiBuiltinToolKind.exitPlanMode => _executeExitPlanModeTool(
          decodedArguments,
          startedAt,
        ),
        AiBuiltinToolKind.read => await _executeReadTool(
          decodedArguments,
          startedAt,
        ),
        AiBuiltinToolKind.edit => await _executeEditTool(
          decodedArguments,
          previouslyReadFiles,
          startedAt,
        ),
        AiBuiltinToolKind.multiEdit => await _executeMultiEditTool(
          decodedArguments,
          previouslyReadFiles,
          startedAt,
        ),
        AiBuiltinToolKind.write => await _executeWriteTool(
          decodedArguments,
          previouslyReadFiles,
          startedAt,
        ),
        AiBuiltinToolKind.notebookEdit => await _executeNotebookEditTool(
          decodedArguments,
          previouslyReadFiles,
          startedAt,
        ),
        AiBuiltinToolKind.webFetch => await _executeWebFetchTool(
          decodedArguments,
          model,
          startedAt,
        ),
        AiBuiltinToolKind.todoWrite => _executeTodoWriteTool(
          decodedArguments,
          startedAt,
        ),
        AiBuiltinToolKind.webSearch => await _executeWebSearchTool(
          decodedArguments,
          model,
          startedAt,
        ),
      };
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: tool.name,
        workingDirectory: _defaultWorkingDirectory(),
        stdout: '',
        stderr: '$error',
        durationMs: startedAt.elapsedMilliseconds,
        resultText: 'status: failed\nerror: $error',
      );
    }
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
      workingDirectory: _defaultWorkingDirectory(),
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

  Future<BashToolExecutionResult> _executeBashTool({
    required String sessionId,
    required Map<String, Object?> decodedArguments,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    Future<void>? cancelSignal,
    void Function(BashToolExecutionUpdate update)? onBashUpdate,
  }) async {
    final timeoutMs =
        _readInt(decodedArguments['timeout']) ??
        _readInt(decodedArguments['timeout_ms']) ??
        AiBashToolService.defaultTimeoutMs;
    if (timeoutMs <= 0 || timeoutMs > 600000) {
      throw ArgumentError(
        'Bash timeout must be between 1 and 600000 milliseconds.',
      );
    }
    return _bashToolService.execute(
      command: '${decodedArguments['cmd'] ?? decodedArguments['command'] ?? ''}'
          .trim(),
      sessionId: sessionId,
      workingDirectory:
          '${decodedArguments['working_directory'] ?? decodedArguments['cwd'] ?? ''}'
              .trim(),
      denyRules: denyCommandRules,
      requireWriteConfirmation: requireWriteCommandConfirmation,
      confirmWriteCommand: confirmWriteCommand,
      cancelSignal: cancelSignal,
      onUpdate: onBashUpdate,
      timeoutMs: timeoutMs,
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
    final manifestContent = await File(skill.manifestPath).readAsString();
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
      null => tool.name,
    };
  }

  String _hookWorkingDirectory(Map<String, Object?> decodedArguments) {
    final rawWorkingDirectory =
        '${decodedArguments['working_directory'] ?? decodedArguments['cwd'] ?? ''}'
            .trim();
    return rawWorkingDirectory.isEmpty
        ? _defaultWorkingDirectory()
        : rawWorkingDirectory;
  }

  Map<String, Object?> _toolHookPayload({
    required String eventName,
    required String toolName,
    required String sessionId,
    required Map<String, Object?> toolInput,
    required String cwd,
    Map<String, Object?>? toolOutput,
  }) {
    return <String, Object?>{
      'hook_event_name': eventName,
      'hookEventName': eventName,
      'session_id': sessionId,
      'sessionId': sessionId,
      'cwd': cwd,
      'tool_name': toolName,
      'toolName': toolName,
      'tool_input': toolInput,
      'toolInput': toolInput,
      if (toolOutput != null) ...<String, Object?>{
        'tool_output': toolOutput,
        'toolOutput': toolOutput,
      },
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

  Future<AiToolExecutionResult> _executeTaskTool(
    String sessionId,
    String toolCallId,
    Map<String, Object?> arguments,
    AiModelConfig model,
    AiResolvedToolCatalog catalog,
    List<AiDenyCommandRule> denyCommandRules,
    bool requireWriteCommandConfirmation,
    Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    Stopwatch startedAt,
    Future<void>? cancelSignal,
  ) async {
    final description = '${arguments['description'] ?? ''}'.trim();
    final prompt = '${arguments['prompt'] ?? ''}'.trim();
    final subagentType = '${arguments['subagent_type'] ?? ''}'.trim();
    if (description.isEmpty || prompt.isEmpty || subagentType.isEmpty) {
      return _invalidToolResult(
        'Task',
        'Task requires description, prompt, and subagent_type.',
      );
    }
    final canonicalSubagentType = _canonicalTaskSubagentType(subagentType);
    if (canonicalSubagentType == null) {
      return _invalidToolResult(
        'Task',
        'Unsupported subagent_type "$subagentType". Available types: ${_taskSubagentDescriptions.keys.join(', ')}',
      );
    }
    final subagentProfile =
        _taskSubagentDescriptions[canonicalSubagentType] ??
        'Focused background agent.';
    final subagentToolEntries = catalog.toolsByName.entries
        .where(
          (entry) =>
              entry.key != 'Task' &&
              entry.key != 'ExitPlanMode' &&
              entry.key != 'bash',
        )
        .toList(growable: false);
    final subagentCatalog = AiResolvedToolCatalog(
      definitions: subagentToolEntries
          .map((entry) => entry.value.definition)
          .toList(growable: false),
      toolsByName: Map<String, AiResolvedTool>.fromEntries(subagentToolEntries),
    );
    final turns = <AiChatTurn>[
      AiChatTurn(
        role: AiChatRole.system,
        content:
            'You are a focused "$canonicalSubagentType" background sub-agent for OpenHand. $subagentProfile This Task invocation is stateless and isolated from other Task calls. Complete the assigned subtask directly. Use tools when they materially help. Do not call Task or ExitPlanMode. Return only the useful result for the parent agent.',
      ),
      AiChatTurn(
        role: AiChatRole.user,
        content:
            'Description: $description\nSubagent type: $canonicalSubagentType\n\nTask:\n$prompt',
      ),
    ];
    final readFiles = <String>{};
    final subagentSessionId =
        '$sessionId/task/${_normalizeToolToken(toolCallId.trim().isEmpty ? canonicalSubagentType : toolCallId)}';
    final subagentStartHookResult = await _hookService.runHooks(
      eventName: 'SubagentStart',
      sessionId: subagentSessionId,
      matcherValue: canonicalSubagentType,
      cwd: _defaultWorkingDirectory(),
      payload: <String, Object?>{
        'subagent_type': canonicalSubagentType,
        'subagentType': canonicalSubagentType,
        'description': description,
        'stateless': true,
      },
    );
    if (subagentStartHookResult.blocked) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'Task $description',
        workingDirectory: _defaultWorkingDirectory(),
        stdout: '',
        stderr:
            subagentStartHookResult.blockReason ?? 'Blocked by subagent hook.',
        durationMs: startedAt.elapsedMilliseconds,
        resultText:
            'status: failed\nerror: ${subagentStartHookResult.blockReason ?? 'Blocked by subagent hook.'}',
        metadata: <String, Object?>{
          'subagent_type': canonicalSubagentType,
          'subagent_session_isolated': true,
          'hook_blocked': true,
          'hook_event_name': 'SubagentStart',
          if (subagentStartHookResult.systemReminders.isNotEmpty)
            aiHookSystemRemindersMetadataKey:
                subagentStartHookResult.systemReminders,
        },
      );
    }
    for (var round = 0; round < 6; round++) {
      final completion = await _backgroundChatClient.sendMessage(
        model: model,
        messages: turns,
        tools: subagentCatalog.definitions,
      );
      final reply = completion.reply.trim();
      if (completion.toolCalls.isEmpty) {
        final output = reply.isEmpty
            ? 'The background task completed without additional output.'
            : reply;
        final subagentStopHookResult = await _runAuxiliaryHook(
          eventName: 'SubagentStop',
          sessionId: subagentSessionId,
          matcherValue: canonicalSubagentType,
          cwd: _defaultWorkingDirectory(),
          payload: <String, Object?>{
            'subagent_type': canonicalSubagentType,
            'subagentType': canonicalSubagentType,
            'description': description,
            'status': 'completed',
            'stateless': true,
          },
        );
        return _simpleSuccessResult(
          command: 'Task $description',
          output: output,
          durationMs: startedAt.elapsedMilliseconds,
          metadata: <String, Object?>{
            'subagent_type': canonicalSubagentType,
            'subagent_session_isolated': true,
            'task_tool_rounds': round,
            if (subagentStartHookResult.systemReminders.isNotEmpty ||
                subagentStopHookResult.systemReminders.isNotEmpty)
              aiHookSystemRemindersMetadataKey: <String>[
                ...subagentStartHookResult.systemReminders,
                ...subagentStopHookResult.systemReminders,
              ],
          },
        );
      }
      turns.add(
        AiChatTurn(
          role: AiChatRole.assistant,
          content: reply,
          toolCalls: completion.toolCalls,
        ),
      );
      for (var index = 0; index < completion.toolCalls.length; index++) {
        final toolCall = completion.toolCalls[index];
        final toolResult = await execute(
          sessionId: subagentSessionId,
          catalog: subagentCatalog,
          toolCall: toolCall,
          model: model,
          previouslyReadFiles: readFiles,
          denyCommandRules: denyCommandRules,
          requireWriteCommandConfirmation: requireWriteCommandConfirmation,
          confirmWriteCommand: confirmWriteCommand,
          cancelSignal: cancelSignal,
        );
        final readFilePath = '${toolResult.metadata['read_file_path'] ?? ''}'
            .trim();
        if (readFilePath.isNotEmpty) {
          readFiles.add(readFilePath);
        }
        turns.add(
          AiChatTurn(
            role: AiChatRole.tool,
            toolCallId: toolCall.id,
            content: toolResult.toToolOutput(),
          ),
        );
      }
    }
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: 'Task $description',
      workingDirectory: _defaultWorkingDirectory(),
      stdout: '',
      stderr: 'The background task exceeded the maximum tool rounds.',
      durationMs: startedAt.elapsedMilliseconds,
      resultText:
          'status: failed\nerror: The background task exceeded the maximum tool rounds.',
      metadata: <String, Object?>{
        'subagent_type': canonicalSubagentType,
        'subagent_session_isolated': true,
        if (subagentStartHookResult.systemReminders.isNotEmpty)
          aiHookSystemRemindersMetadataKey:
              subagentStartHookResult.systemReminders,
      },
    );
  }

  Future<AiClaudeHookInvocationResult> _runAuxiliaryHook({
    required String eventName,
    required String sessionId,
    required Map<String, Object?> payload,
    String? matcherValue,
    String? cwd,
  }) async {
    try {
      return await _hookService.runHooks(
        eventName: eventName,
        sessionId: sessionId,
        matcherValue: matcherValue,
        cwd: cwd,
        payload: payload,
      );
    } catch (error) {
      return AiClaudeHookInvocationResult(
        systemReminders: <String>['Hook event $eventName failed: $error'],
      );
    }
  }

  AiToolExecutionResult _executeExitPlanModeTool(
    Map<String, Object?> arguments,
    Stopwatch startedAt,
  ) {
    final plan = '${arguments['plan'] ?? ''}'.trim();
    if (plan.isEmpty) {
      return _invalidToolResult(
        'ExitPlanMode',
        'ExitPlanMode requires a non-empty plan.',
      );
    }
    return _simpleSuccessResult(
      command: 'ExitPlanMode',
      output:
          'Plan captured. Present the plan to the user and wait for explicit approval before implementation.',
      durationMs: startedAt.elapsedMilliseconds,
      metadata: <String, Object?>{
        'plan_mode_awaiting_approval': true,
        'pending_plan': plan,
      },
    );
  }

  Future<AiToolExecutionResult> _executeReadTool(
    Map<String, Object?> arguments,
    Stopwatch startedAt,
  ) async {
    final filePath = _requireAbsoluteFilePath(
      '${arguments['file_path'] ?? ''}'.trim(),
    );
    if (filePath == null) {
      return _invalidToolResult('Read', 'Read requires an absolute file_path.');
    }
    final file = File(filePath);
    if (!await file.exists()) {
      return _invalidToolResult('Read', 'File does not exist: $filePath');
    }
    final offset = _readInt(arguments['offset']);
    final limit = _readInt(arguments['limit']) ?? _defaultReadLimit;
    final renderedRead = await _renderReadForFile(file, filePath);
    final rawContent = renderedRead.content;
    if (rawContent.isEmpty) {
      return _simpleSuccessResult(
        command: 'Read $filePath',
        output: 'File is empty: $filePath',
        durationMs: startedAt.elapsedMilliseconds,
        metadata: <String, Object?>{
          'read_file_path': filePath,
          'read_file_kind': renderedRead.fileKind,
          'read_render_mode': renderedRead.renderMode,
          aiHookSystemRemindersMetadataKey: <String>[
            'Read opened an empty file: $filePath',
          ],
        },
      );
    }
    if (!renderedRead.lineAddressable) {
      return _simpleSuccessResult(
        command: 'Read $filePath',
        output: rawContent,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(filePath),
        metadata: <String, Object?>{
          'read_file_path': filePath,
          'read_file_kind': renderedRead.fileKind,
          'read_render_mode': renderedRead.renderMode,
          'read_truncated': renderedRead.truncated,
        },
      );
    }
    final lines = const LineSplitter().convert(rawContent);
    final startIndex = offset == null || offset <= 1 ? 0 : offset - 1;
    final safeStartIndex = startIndex < lines.length
        ? startIndex
        : lines.length;
    final endIndex = (safeStartIndex + limit) < lines.length
        ? safeStartIndex + limit
        : lines.length;
    final visibleLines = lines.sublist(safeStartIndex, endIndex);
    final lineNumberWidth = endIndex.toString().length < 4
        ? 4
        : endIndex.toString().length;
    final output = visibleLines.isEmpty
        ? 'No lines available in the requested range.'
        : visibleLines
              .asMap()
              .entries
              .map((entry) {
                final lineNumber = safeStartIndex + entry.key + 1;
                final line = entry.value.length > _maxReadLineLength
                    ? '${entry.value.substring(0, _maxReadLineLength)}...'
                    : entry.value;
                return '${lineNumber.toString().padLeft(lineNumberWidth)}\t$line';
              })
              .join('\n');
    return _simpleSuccessResult(
      command: 'Read $filePath',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      metadata: <String, Object?>{
        'read_file_path': filePath,
        'read_file_kind': renderedRead.fileKind,
        'read_render_mode': renderedRead.renderMode,
        'read_truncated': renderedRead.truncated,
        if (renderedRead.truncated)
          aiHookSystemRemindersMetadataKey: <String>[
            'Read truncated a large file preview: $filePath',
          ],
      },
    );
  }

  Future<AiToolExecutionResult> _executeLsTool(
    Map<String, Object?> arguments,
    Stopwatch startedAt,
  ) async {
    final path = _requireAbsoluteDirectoryPath(
      '${arguments['path'] ?? ''}'.trim(),
    );
    if (path == null) {
      return _invalidToolResult('LS', 'LS requires an absolute path.');
    }
    final directory = Directory(path);
    if (!await directory.exists()) {
      return _invalidToolResult('LS', 'Directory does not exist: $path');
    }
    final ignorePatterns = arguments['ignore'] is List
        ? (arguments['ignore'] as List)
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final entries = await directory.list().toList();
    entries.sort((left, right) => left.path.compareTo(right.path));
    final lines = <String>[];
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (_matchesAnyGlob(name, ignorePatterns) ||
          _matchesAnyGlob(entry.path, ignorePatterns)) {
        continue;
      }
      final type = entry is Directory
          ? 'dir'
          : entry is Link
          ? 'link'
          : 'file';
      lines.add('$type\t$name');
    }
    final output = lines.isEmpty ? '(empty)' : lines.join('\n');
    return _simpleSuccessResult(
      command: 'LS $path',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: path,
    );
  }

  Future<AiToolExecutionResult> _executeGlobTool(
    Map<String, Object?> arguments,
    Stopwatch startedAt,
  ) async {
    final pattern = '${arguments['pattern'] ?? ''}'.trim();
    if (pattern.isEmpty) {
      return _invalidToolResult('Glob', 'Glob requires pattern.');
    }
    final rootPath = _resolvePath('${arguments['path'] ?? ''}'.trim());
    final rootEntity = FileSystemEntity.typeSync(rootPath);
    if (rootEntity == FileSystemEntityType.notFound) {
      return _invalidToolResult('Glob', 'Path does not exist: $rootPath');
    }
    final matches = <String>[];
    if (rootEntity == FileSystemEntityType.file) {
      final filePath = p.normalize(rootPath);
      final relative = p.basename(filePath);
      if (_globMatches(relative, pattern)) {
        matches.add(filePath);
      }
    } else {
      await for (final entity in Directory(rootPath).list(recursive: true)) {
        final normalizedPath = p.normalize(entity.path);
        final relativePath = p
            .relative(normalizedPath, from: rootPath)
            .replaceAll('\\', '/');
        if (_globMatches(relativePath, pattern)) {
          matches.add(normalizedPath);
        }
      }
    }
    final fileStats = <String, DateTime>{};
    for (final match in matches) {
      try {
        fileStats[match] = (await FileStat.stat(match)).modified;
      } catch (_) {
        fileStats[match] = DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    matches.sort((left, right) {
      final leftModified =
          fileStats[left] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightModified =
          fileStats[right] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final modifiedComparison = rightModified.compareTo(leftModified);
      if (modifiedComparison != 0) {
        return modifiedComparison;
      }
      return left.compareTo(right);
    });
    final output = matches.isEmpty ? '(no matches)' : matches.join('\n');
    return _simpleSuccessResult(
      command: 'Glob $pattern',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: rootPath,
    );
  }

  Future<AiToolExecutionResult> _executeGrepTool(
    Map<String, Object?> arguments,
    Stopwatch startedAt,
  ) async {
    final pattern = '${arguments['pattern'] ?? ''}'.trim();
    if (pattern.isEmpty) {
      return _invalidToolResult('Grep', 'Grep requires pattern.');
    }
    final path = _resolvePath('${arguments['path'] ?? ''}'.trim());
    final glob = '${arguments['glob'] ?? ''}'.trim();
    final outputMode = '${arguments['output_mode'] ?? 'files_with_matches'}'
        .trim();
    final before = _readInt(arguments['-B']);
    final after = _readInt(arguments['-A']);
    final context = _readInt(arguments['-C']);
    final showLineNumbers = arguments['-n'] == true;
    final caseInsensitive = arguments['-i'] == true;
    final type = '${arguments['type'] ?? ''}'.trim();
    final headLimit = _readInt(arguments['head_limit']);
    final multiline = arguments['multiline'] == true;

    final rgArgs = <String>[];
    switch (outputMode) {
      case 'content':
        break;
      case 'count':
        rgArgs.add('--count');
      case 'files_with_matches':
        rgArgs.add('--files-with-matches');
      default:
        rgArgs.add('--files-with-matches');
    }
    if (before != null) {
      rgArgs
        ..add('-B')
        ..add('$before');
    }
    if (after != null) {
      rgArgs
        ..add('-A')
        ..add('$after');
    }
    if (context != null) {
      rgArgs
        ..add('-C')
        ..add('$context');
    }
    if (showLineNumbers) {
      rgArgs.add('-n');
    }
    if (caseInsensitive) {
      rgArgs.add('-i');
    }
    if (type.isNotEmpty) {
      rgArgs
        ..add('--type')
        ..add(type);
    }
    if (glob.isNotEmpty) {
      rgArgs
        ..add('--glob')
        ..add(glob);
    }
    if (multiline) {
      rgArgs
        ..add('-U')
        ..add('--multiline-dotall');
    }
    rgArgs
      ..add(pattern)
      ..add(path);

    final rgResult = await _runProcess('rg', rgArgs);
    if (rgResult.exitCode == 0 ||
        (rgResult.exitCode == 1 && rgResult.stdout.trim().isEmpty)) {
      var output = rgResult.stdout.trimRight();
      if (output.isEmpty) {
        output = outputMode == 'count' ? '(zero matches)' : '(no matches)';
      } else if (headLimit != null && headLimit > 0) {
        output = output.split('\n').take(headLimit).join('\n');
      }
      if (output.length > _maxSearchOutputCharacters) {
        output = '${output.substring(0, _maxSearchOutputCharacters)}...';
      }
      return _simpleSuccessResult(
        command: 'Grep $pattern',
        output: output,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: path,
      );
    }
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: 'Grep $pattern',
      workingDirectory: path,
      stdout: rgResult.stdout,
      stderr: rgResult.stderr,
      durationMs: startedAt.elapsedMilliseconds,
      exitCode: rgResult.exitCode,
      resultText:
          'status: failed\nexit_code: ${rgResult.exitCode}\nstdout:\n${rgResult.stdout.trimRight()}\nstderr:\n${rgResult.stderr.trimRight()}'
              .trim(),
    );
  }

  Future<AiToolExecutionResult> _executeEditTool(
    Map<String, Object?> arguments,
    Set<String> previouslyReadFiles,
    Stopwatch startedAt,
  ) async {
    final filePath = _requireAbsoluteFilePath(
      '${arguments['file_path'] ?? ''}'.trim(),
    );
    final oldString = '${arguments['old_string'] ?? ''}';
    final newString = '${arguments['new_string'] ?? ''}';
    final replaceAll = arguments['replace_all'] == true;
    if (filePath == null) {
      return _invalidToolResult('Edit', 'Edit requires an absolute file_path.');
    }
    if (oldString == newString) {
      return _invalidToolResult(
        'Edit',
        'old_string and new_string must differ.',
      );
    }
    final file = File(filePath);
    if (!await file.exists()) {
      return _invalidToolResult('Edit', 'File does not exist: $filePath');
    }
    final readValidation = await _validateReadBeforeMutation(
      toolName: 'Edit',
      filePath: filePath,
      previouslyReadFiles: previouslyReadFiles,
    );
    if (readValidation != null) {
      return readValidation;
    }
    final content = await file.readAsString();
    final replacement = _replaceOnceOrAll(
      content: content,
      oldString: oldString,
      newString: newString,
      replaceAll: replaceAll,
    );
    if (!replacement.success) {
      return _invalidToolResult('Edit', replacement.errorMessage);
    }
    await file.writeAsString(replacement.content, flush: true);
    return _simpleSuccessResult(
      command: 'Edit $filePath',
      output: 'Updated $filePath',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      isWriteCommand: true,
      metadata: <String, Object?>{'tool_source': 'builtin'},
    );
  }

  Future<AiToolExecutionResult> _executeMultiEditTool(
    Map<String, Object?> arguments,
    Set<String> previouslyReadFiles,
    Stopwatch startedAt,
  ) async {
    final filePath = _requireAbsoluteFilePath(
      '${arguments['file_path'] ?? ''}'.trim(),
    );
    if (filePath == null) {
      return _invalidToolResult(
        'MultiEdit',
        'MultiEdit requires an absolute file_path.',
      );
    }
    final edits = arguments['edits'];
    if (edits is! List || edits.isEmpty) {
      return _invalidToolResult(
        'MultiEdit',
        'MultiEdit requires a non-empty edits array.',
      );
    }
    final file = File(filePath);
    final readValidation = await _validateReadBeforeMutation(
      toolName: 'MultiEdit',
      filePath: filePath,
      previouslyReadFiles: previouslyReadFiles,
      requireExistingFileRead: await file.exists(),
    );
    if (readValidation != null) {
      return readValidation;
    }
    var content = await file.exists() ? await file.readAsString() : '';
    var isCreatingFile = !await file.exists();
    for (final rawEdit in edits) {
      if (rawEdit is! Map) {
        return _invalidToolResult('MultiEdit', 'Each edit must be an object.');
      }
      final edit = Map<String, Object?>.from(rawEdit);
      final oldString = '${edit['old_string'] ?? ''}';
      final newString = '${edit['new_string'] ?? ''}';
      final replaceAll = edit['replace_all'] == true;
      if (oldString.isEmpty && isCreatingFile) {
        content = newString;
        isCreatingFile = false;
        continue;
      }
      final replacement = _replaceOnceOrAll(
        content: content,
        oldString: oldString,
        newString: newString,
        replaceAll: replaceAll,
      );
      if (!replacement.success) {
        return _invalidToolResult('MultiEdit', replacement.errorMessage);
      }
      content = replacement.content;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
    return _simpleSuccessResult(
      command: 'MultiEdit $filePath',
      output: 'Updated $filePath',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      isWriteCommand: true,
    );
  }

  Future<AiToolExecutionResult> _executeWriteTool(
    Map<String, Object?> arguments,
    Set<String> previouslyReadFiles,
    Stopwatch startedAt,
  ) async {
    final filePath = _requireAbsoluteFilePath(
      '${arguments['file_path'] ?? ''}'.trim(),
    );
    if (filePath == null) {
      return _invalidToolResult(
        'Write',
        'Write requires an absolute file_path.',
      );
    }
    final content = '${arguments['content'] ?? ''}';
    final file = File(filePath);
    final readValidation = await _validateReadBeforeMutation(
      toolName: 'Write',
      filePath: filePath,
      previouslyReadFiles: previouslyReadFiles,
      requireExistingFileRead: await file.exists(),
    );
    if (readValidation != null) {
      return readValidation;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
    return _simpleSuccessResult(
      command: 'Write $filePath',
      output: 'Wrote ${content.length} characters to $filePath',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      isWriteCommand: true,
    );
  }

  Future<AiToolExecutionResult> _executeNotebookEditTool(
    Map<String, Object?> arguments,
    Set<String> previouslyReadFiles,
    Stopwatch startedAt,
  ) async {
    final notebookPath = _requireAbsoluteFilePath(
      '${arguments['notebook_path'] ?? ''}'.trim(),
    );
    if (notebookPath == null) {
      return _invalidToolResult(
        'NotebookEdit',
        'NotebookEdit requires an absolute notebook_path.',
      );
    }
    final newSource = '${arguments['new_source'] ?? ''}';
    final editMode = '${arguments['edit_mode'] ?? 'replace'}'.trim();
    final cellId = '${arguments['cell_id'] ?? ''}'.trim();
    final cellType = '${arguments['cell_type'] ?? ''}'.trim();
    final file = File(notebookPath);
    if (!await file.exists()) {
      return _invalidToolResult(
        'NotebookEdit',
        'Notebook does not exist: $notebookPath',
      );
    }
    final readValidation = await _validateReadBeforeMutation(
      toolName: 'NotebookEdit',
      filePath: notebookPath,
      previouslyReadFiles: previouslyReadFiles,
    );
    if (readValidation != null) {
      return readValidation;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return _invalidToolResult(
        'NotebookEdit',
        'Notebook JSON root is invalid.',
      );
    }
    final notebook = Map<String, Object?>.from(decoded);
    final rawCells = notebook['cells'];
    if (rawCells is! List) {
      return _invalidToolResult(
        'NotebookEdit',
        'Notebook cells array is invalid.',
      );
    }
    final cells = rawCells
        .map(
          (item) => item is Map
              ? Map<String, Object?>.from(item)
              : <String, Object?>{},
        )
        .toList(growable: true);
    final index = cellId.isEmpty
        ? -1
        : cells.indexWhere((cell) => '${cell['id'] ?? ''}'.trim() == cellId);
    switch (editMode) {
      case 'insert':
        if (cellType.isEmpty) {
          return _invalidToolResult(
            'NotebookEdit',
            'NotebookEdit insert requires cell_type.',
          );
        }
        final insertedCell = <String, Object?>{
          'cell_type': cellType,
          'metadata': const <String, Object?>{},
          'source': newSource,
        };
        if (index == -1) {
          cells.insert(0, insertedCell);
        } else {
          cells.insert(index + 1, insertedCell);
        }
        break;
      case 'delete':
        if (index == -1) {
          return _invalidToolResult(
            'NotebookEdit',
            'Target cell_id was not found.',
          );
        }
        cells.removeAt(index);
        break;
      case 'replace':
      default:
        if (index == -1) {
          return _invalidToolResult(
            'NotebookEdit',
            'Target cell_id was not found.',
          );
        }
        final updatedCell = Map<String, Object?>.from(cells[index]);
        if (cellType.isNotEmpty) {
          updatedCell['cell_type'] = cellType;
        }
        updatedCell['source'] = newSource;
        cells[index] = updatedCell;
    }
    notebook['cells'] = cells;
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(notebook),
      flush: true,
    );
    return _simpleSuccessResult(
      command: 'NotebookEdit $notebookPath',
      output: 'Updated notebook $notebookPath',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(notebookPath),
      isWriteCommand: true,
    );
  }

  Future<AiToolExecutionResult> _executeWebFetchTool(
    Map<String, Object?> arguments,
    AiModelConfig model,
    Stopwatch startedAt,
  ) async {
    final rawUrl = '${arguments['url'] ?? ''}'.trim();
    final prompt = '${arguments['prompt'] ?? ''}'.trim();
    if (rawUrl.isEmpty || prompt.isEmpty) {
      return _invalidToolResult(
        'WebFetch',
        'WebFetch requires url and prompt.',
      );
    }
    final uri = _normalizeWebFetchUri(Uri.tryParse(rawUrl));
    if (uri == null) {
      return _invalidToolResult('WebFetch', 'Invalid URL: $rawUrl');
    }
    final fetchResult = await _fetchWebContent(uri);
    if (fetchResult.crossHostRedirectUrl != null) {
      final redirectUrl = fetchResult.crossHostRedirectUrl!;
      return _simpleSuccessResult(
        command: 'WebFetch $rawUrl',
        output:
            'Cross-host redirect detected.\nredirect_url: $redirectUrl\nmessage: WebFetch encountered a redirect to a different host. Make a new WebFetch request with redirect_url to continue.',
        durationMs: startedAt.elapsedMilliseconds,
        metadata: <String, Object?>{
          'webfetch_redirect_cross_host': true,
          'webfetch_redirect_url': redirectUrl,
          'webfetch_source_url': rawUrl,
        },
      );
    }
    if (fetchResult.errorMessage != null) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'WebFetch $rawUrl',
        workingDirectory: _defaultWorkingDirectory(),
        stdout: '',
        stderr: fetchResult.errorMessage!,
        durationMs: startedAt.elapsedMilliseconds,
        resultText: 'status: failed\nerror: ${fetchResult.errorMessage!}',
      );
    }
    final body = fetchResult.body ?? '';
    final contentType = fetchResult.contentType ?? '';
    final normalizedContent = _truncateContent(
      _htmlToText(contentType.contains('html') ? body : body),
      _maxWebContentCharacters,
    );
    final completion = await _backgroundChatClient.sendMessage(
      model: model,
      messages: <AiChatTurn>[
        const AiChatTurn(
          role: AiChatRole.system,
          content:
              'Answer the prompt using only the fetched page content. If the page content is insufficient, say so briefly.',
        ),
        AiChatTurn(
          role: AiChatRole.user,
          content:
              'URL: $rawUrl\nPrompt: $prompt\n\nFetched content:\n$normalizedContent',
        ),
      ],
    );
    final output = completion.reply.trim().isEmpty
        ? normalizedContent
        : completion.reply.trim();
    return _simpleSuccessResult(
      command: 'WebFetch $rawUrl',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
      metadata: <String, Object?>{
        'webfetch_final_url': fetchResult.finalUrl ?? uri.toString(),
        'webfetch_cache_hit': fetchResult.fromCache,
        'webfetch_content_type': contentType,
      },
    );
  }

  AiToolExecutionResult _executeTodoWriteTool(
    Map<String, Object?> arguments,
    Stopwatch startedAt,
  ) {
    final todos = arguments['todos'];
    if (todos is! List) {
      return _invalidToolResult(
        'TodoWrite',
        'TodoWrite requires a todos array.',
      );
    }
    final normalizedTodos = <Map<String, Object?>>[];
    final seenIds = <String>{};
    var inProgressCount = 0;
    for (final rawTodo in todos) {
      if (rawTodo is! Map) {
        return _invalidToolResult('TodoWrite', 'Each todo must be an object.');
      }
      final todo = Map<String, Object?>.from(rawTodo);
      final id = '${todo['id'] ?? ''}'.trim();
      final content = '${todo['content'] ?? ''}'.trim();
      final status = '${todo['status'] ?? ''}'.trim();
      if (id.isEmpty || content.isEmpty) {
        return _invalidToolResult(
          'TodoWrite',
          'Each todo must include id and content.',
        );
      }
      if (!seenIds.add(id)) {
        return _invalidToolResult(
          'TodoWrite',
          'Todo ids must be unique within a single TodoWrite call.',
        );
      }
      if (status != 'pending' &&
          status != 'in_progress' &&
          status != 'completed' &&
          status != 'failed') {
        return _invalidToolResult(
          'TodoWrite',
          'Todo status must be pending, in_progress, completed, or failed.',
        );
      }
      if (status == 'in_progress') {
        inProgressCount += 1;
      }
      normalizedTodos.add(<String, Object?>{
        'id': id,
        'content': content,
        'status': status,
      });
    }
    if (inProgressCount > 1) {
      return _invalidToolResult(
        'TodoWrite',
        'Only one todo may be in_progress at a time.',
      );
    }
    final lines = normalizedTodos.isEmpty
        ? '(todo list cleared)'
        : normalizedTodos
              .map((todo) {
                final status = '${todo['status']}';
                final marker = switch (status) {
                  'completed' => '[x]',
                  'in_progress' => '[-]',
                  'failed' => '[!]',
                  _ => '[ ]',
                };
                return '$marker ${todo['id']}: ${todo['content']}';
              })
              .join('\n');
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: 'TodoWrite',
      workingDirectory: _defaultWorkingDirectory(),
      stdout: lines,
      stderr: '',
      durationMs: startedAt.elapsedMilliseconds,
      resultText: lines,
      metadata: <String, Object?>{
        'todo_items': normalizedTodos,
        'todo_list_replaced': true,
      },
    );
  }

  Future<AiToolExecutionResult> _executeWebSearchTool(
    Map<String, Object?> arguments,
    AiModelConfig model,
    Stopwatch startedAt,
  ) async {
    final query = '${arguments['query'] ?? ''}'.trim();
    if (query.length < 2) {
      return _invalidToolResult(
        'WebSearch',
        'WebSearch requires query with at least 2 characters.',
      );
    }
    final allowedDomains = _normalizeStringList(arguments['allowed_domains']);
    final blockedDomains = _normalizeStringList(arguments['blocked_domains']);
    final uri = Uri.https('duckduckgo.com', '/html/', <String, String>{
      'q': query,
    });
    final response = await _httpClient
        .get(uri)
        .timeout(const Duration(seconds: 20));
    final html = response.body;
    final results = _parseDuckDuckGoResults(html)
        .where((item) {
          final host = Uri.tryParse(item.url)?.host.toLowerCase() ?? '';
          if (allowedDomains.isNotEmpty &&
              !allowedDomains.any(
                (domain) => host == domain || host.endsWith('.$domain'),
              )) {
            return false;
          }
          if (blockedDomains.any(
            (domain) => host == domain || host.endsWith('.$domain'),
          )) {
            return false;
          }
          return true;
        })
        .take(8)
        .toList(growable: false);
    if (results.isEmpty) {
      return _simpleSuccessResult(
        command: 'WebSearch $query',
        output: 'No search results found.',
        durationMs: startedAt.elapsedMilliseconds,
      );
    }
    final rawResults = results
        .map((item) => '- ${item.title}\n  ${item.url}\n  ${item.snippet}')
        .join('\n');
    final completion = await _backgroundChatClient.sendMessage(
      model: model,
      messages: <AiChatTurn>[
        const AiChatTurn(
          role: AiChatRole.system,
          content:
              'Summarize the search results faithfully. Do not invent results that were not provided.',
        ),
        AiChatTurn(
          role: AiChatRole.user,
          content: 'Query: $query\n\nResults:\n$rawResults',
        ),
      ],
    );
    final output = completion.reply.trim().isEmpty
        ? rawResults
        : completion.reply.trim();
    return _simpleSuccessResult(
      command: 'WebSearch $query',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
    );
  }

  Future<AiToolExecutionResult?> _validateReadBeforeMutation({
    required String toolName,
    required String filePath,
    required Set<String> previouslyReadFiles,
    bool requireExistingFileRead = true,
  }) async {
    if (!requireExistingFileRead) {
      return null;
    }
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }
    if (previouslyReadFiles.contains(filePath)) {
      return null;
    }
    return _invalidToolResult(
      toolName,
      '$toolName requires reading the file with Read before mutating it: $filePath',
    );
  }

  Future<String> _renderNotebookForRead(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return '';
    }
    final notebook = Map<String, Object?>.from(decoded);
    final rawCells = notebook['cells'];
    if (rawCells is! List || rawCells.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (var index = 0; index < rawCells.length; index++) {
      final cell = _asMap(rawCells[index]) ?? const <String, Object?>{};
      final cellType = _readText(cell['cell_type']);
      buffer.writeln('# Cell $index [$cellType]');
      final source = _renderNotebookValue(cell['source']);
      if (source.isNotEmpty) {
        buffer.writeln(source.trimRight());
      }
      final outputs = cell['outputs'];
      if (outputs is List && outputs.isNotEmpty) {
        buffer.writeln('## Outputs');
        for (final output in outputs) {
          final outputMap = _asMap(output) ?? const <String, Object?>{};
          final text = _renderNotebookValue(
            outputMap['text'] ?? outputMap['data'] ?? outputMap['traceback'],
          );
          if (text.isNotEmpty) {
            buffer.writeln(text.trimRight());
          }
        }
      }
      if (index != rawCells.length - 1) {
        buffer.writeln();
      }
    }
    return buffer.toString().trimRight();
  }

  Future<_RenderedReadContent> _renderReadForFile(
    File file,
    String filePath,
  ) async {
    final extension = p.extension(filePath).toLowerCase();
    if (extension == '.ipynb') {
      return _RenderedReadContent(
        content: await _renderNotebookForRead(file),
        fileKind: extension,
        renderMode: 'notebook',
        lineAddressable: true,
      );
    }
    final fileLength = await file.length();
    if (fileLength == 0) {
      return _RenderedReadContent(
        content: '',
        fileKind: extension.isEmpty ? 'text' : extension,
        renderMode: 'text',
        lineAddressable: true,
      );
    }
    if (_isRasterImageExtension(extension)) {
      final bytes = await file.readAsBytes();
      return _renderImageReadContent(bytes, filePath, extension);
    }
    if (extension == '.pdf') {
      final bytes = await file.readAsBytes();
      return _renderPdfReadContent(bytes, filePath);
    }
    final bytes = await _readFilePrefix(file, fileLength);
    final truncated = fileLength > bytes.length;
    if (_looksBinary(bytes) && !_isKnownTextExtension(extension)) {
      return _renderBinaryReadContent(
        bytes,
        filePath,
        extension,
        totalByteSize: fileLength,
        truncated: truncated,
      );
    }
    var content = _decodeTextBytes(bytes);
    if (truncated) {
      content =
          '${_truncateContent(content, _maxFileCharacters)}\n\n[truncated: showing the first ${bytes.length} bytes of $fileLength bytes]';
    } else {
      content = _truncateContent(content, _maxFileCharacters);
    }
    return _RenderedReadContent(
      content: content,
      fileKind: extension.isEmpty ? 'text' : extension,
      renderMode: 'text',
      lineAddressable: true,
      truncated: truncated,
    );
  }

  _RenderedReadContent _renderImageReadContent(
    List<int> bytes,
    String filePath,
    String extension,
  ) {
    final decodedImage = img.decodeImage(Uint8List.fromList(bytes));
    final byteSize = bytes.length;
    final buffer = StringBuffer()
      ..writeln('file_type: image')
      ..writeln('path: $filePath')
      ..writeln(
        'format: ${extension.isEmpty ? 'unknown' : extension.substring(1)}',
      )
      ..writeln('size_bytes: $byteSize');
    if (decodedImage != null) {
      buffer
        ..writeln('width: ${decodedImage.width}')
        ..writeln('height: ${decodedImage.height}');
    }
    buffer.writeln(
      'preview: Raster image files are not line-addressable in this runtime.',
    );
    return _RenderedReadContent(
      content: buffer.toString().trimRight(),
      fileKind: extension.isEmpty ? 'image' : extension,
      renderMode: 'image',
      lineAddressable: false,
    );
  }

  _RenderedReadContent _renderPdfReadContent(List<int> bytes, String filePath) {
    final latinText = latin1.decode(bytes, allowInvalid: true);
    final headerLine = latinText.split(RegExp(r'[\r\n]')).first.trim();
    final pageCount = RegExp(r'/Type\s*/Page\b').allMatches(latinText).length;
    final buffer = StringBuffer()
      ..writeln('file_type: pdf')
      ..writeln('path: $filePath')
      ..writeln('size_bytes: ${bytes.length}');
    if (headerLine.isNotEmpty) {
      buffer.writeln('header: $headerLine');
    }
    if (pageCount > 0) {
      buffer.writeln('page_count_estimate: $pageCount');
    }
    buffer.writeln(
      'preview: PDF files are not line-addressable in this runtime.',
    );
    return _RenderedReadContent(
      content: buffer.toString().trimRight(),
      fileKind: '.pdf',
      renderMode: 'pdf',
      lineAddressable: false,
    );
  }

  _RenderedReadContent _renderBinaryReadContent(
    List<int> bytes,
    String filePath,
    String extension, {
    required int totalByteSize,
    required bool truncated,
  }) {
    final previewBytes = bytes
        .take(_maxBinaryPreviewBytes)
        .toList(growable: false);
    final hexPreview = previewBytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final buffer = StringBuffer()
      ..writeln('file_type: binary')
      ..writeln('path: $filePath')
      ..writeln('size_bytes: $totalByteSize');
    if (extension.isNotEmpty) {
      buffer.writeln('extension: $extension');
    }
    if (hexPreview.isNotEmpty) {
      buffer.writeln('hex_preview: $hexPreview');
    }
    if (truncated) {
      buffer.writeln(
        'preview_scope: first ${bytes.length} bytes captured for binary inspection',
      );
    }
    buffer.writeln(
      'preview: Binary files are not line-addressable in this runtime.',
    );
    return _RenderedReadContent(
      content: buffer.toString().trimRight(),
      fileKind: extension.isEmpty ? 'binary' : extension,
      renderMode: 'binary',
      lineAddressable: false,
      truncated: truncated,
    );
  }

  String _renderNotebookValue(Object? value) {
    if (value is List) {
      return value.map((item) => '$item').join();
    }
    if (value is Map) {
      final textPlain = value['text/plain'];
      if (textPlain != null) {
        return _renderNotebookValue(textPlain);
      }
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return '$value'.trim();
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
        final previewBytes = await _readFilePrefix(
          linkedFile,
          linkedFileLength,
        );
        final extension = p.extension(resolvedPath).toLowerCase();
        if (_looksBinary(previewBytes) && !_isKnownTextExtension(extension)) {
          buffer.writeln('  content: [binary file omitted]');
          if (linkedFileLength > previewBytes.length) {
            buffer.writeln(
              '  content_note: truncated binary preview (${previewBytes.length}/$linkedFileLength bytes)',
            );
          }
          continue;
        }
        final content = _decodeTextBytes(previewBytes).trimRight();
        final renderedContent = _truncateContent(content, 4000);
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

  Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) async {
    try {
      return await Process.run(executable, arguments);
    } on ProcessException catch (error) {
      return ProcessResult(0, 127, '', error.message);
    }
  }

  Map<String, Object?> _decodeArguments(String rawArguments) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {}
    return const <String, Object?>{};
  }

  String _defaultWorkingDirectory() {
    return p.normalize(Directory.current.path);
  }

  String? _canonicalTaskSubagentType(String rawType) {
    final normalized = rawType.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (_taskSubagentDescriptions.containsKey(normalized)) {
      return normalized;
    }
    return null;
  }

  String _resolvePath(String rawPath) {
    final normalizedInput = rawPath.trim();
    if (normalizedInput.isEmpty) {
      return _defaultWorkingDirectory();
    }
    if (p.isAbsolute(normalizedInput)) {
      return p.normalize(normalizedInput);
    }
    return p.normalize(p.join(_defaultWorkingDirectory(), normalizedInput));
  }

  String? _requireAbsoluteFilePath(String rawPath) {
    final normalizedInput = rawPath.trim();
    if (normalizedInput.isEmpty || !p.isAbsolute(normalizedInput)) {
      return null;
    }
    return p.normalize(normalizedInput);
  }

  String? _requireAbsoluteDirectoryPath(String rawPath) {
    final normalizedInput = rawPath.trim();
    if (normalizedInput.isEmpty || !p.isAbsolute(normalizedInput)) {
      return null;
    }
    return p.normalize(normalizedInput);
  }

  Future<List<int>> _readFilePrefix(File file, int fileLength) async {
    final byteLimit = fileLength < _maxReadBytes ? fileLength : _maxReadBytes;
    if (byteLimit <= 0) {
      return const <int>[];
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, byteLimit)) {
      builder.add(chunk);
      if (builder.length >= byteLimit) {
        break;
      }
    }
    return builder.takeBytes();
  }

  Uri? _normalizeWebFetchUri(Uri? uri) {
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      return null;
    }
    final normalizedScheme = uri.scheme.toLowerCase();
    if (normalizedScheme != 'http' && normalizedScheme != 'https') {
      return null;
    }
    if (normalizedScheme == 'http') {
      final upgradePort = uri.hasPort && uri.port != 80 ? uri.port : 443;
      return uri.replace(scheme: 'https', port: upgradePort);
    }
    return uri;
  }

  Future<_WebFetchContentResult> _fetchWebContent(Uri initialUri) async {
    _pruneExpiredWebFetchCache();
    final cached = _webFetchCache[initialUri.toString()];
    if (cached != null && !_isWebFetchCacheExpired(cached)) {
      return _WebFetchContentResult(
        body: cached.body,
        contentType: cached.contentType,
        finalUrl: cached.finalUrl,
        fromCache: true,
      );
    }

    var currentUri = initialUri;
    final visitedUrls = <String>{};
    for (
      var redirectCount = 0;
      redirectCount <= _maxWebFetchRedirects;
      redirectCount++
    ) {
      final visitKey = currentUri.toString();
      if (!visitedUrls.add(visitKey)) {
        return const _WebFetchContentResult(
          errorMessage: 'Redirect loop detected while fetching the URL.',
        );
      }
      final request = http.Request('GET', currentUri)
        ..followRedirects = false
        ..maxRedirects = 0;
      late final http.Response response;
      try {
        response = await http.Response.fromStream(
          await _httpClient.send(request).timeout(const Duration(seconds: 20)),
        );
      } on TimeoutException {
        return const _WebFetchContentResult(
          errorMessage: 'WebFetch timed out while retrieving the URL.',
        );
      } catch (error) {
        return _WebFetchContentResult(errorMessage: '$error');
      }

      if (_isRedirectStatusCode(response.statusCode)) {
        final location = (response.headers['location'] ?? '').trim();
        if (location.isEmpty) {
          return _WebFetchContentResult(
            errorMessage:
                'Received redirect response without a location header from $currentUri.',
          );
        }
        final nextUri = _normalizeWebFetchUri(currentUri.resolve(location));
        if (nextUri == null) {
          return _WebFetchContentResult(
            errorMessage: 'Invalid redirect target: $location',
          );
        }
        if (currentUri.host.toLowerCase() != nextUri.host.toLowerCase()) {
          return _WebFetchContentResult(
            crossHostRedirectUrl: nextUri.toString(),
            finalUrl: currentUri.toString(),
          );
        }
        currentUri = nextUri;
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return _WebFetchContentResult(
          errorMessage:
              'WebFetch failed with HTTP ${response.statusCode} for $currentUri.',
        );
      }
      final cachedContent = _CachedWebFetchContent(
        body: response.body,
        contentType: (response.headers['content-type'] ?? '').trim(),
        finalUrl: currentUri.toString(),
        fetchedAt: DateTime.now().toUtc(),
      );
      _webFetchCache[initialUri.toString()] = cachedContent;
      _webFetchCache[currentUri.toString()] = cachedContent;
      return _WebFetchContentResult(
        body: cachedContent.body,
        contentType: cachedContent.contentType,
        finalUrl: cachedContent.finalUrl,
        fromCache: false,
      );
    }
    return const _WebFetchContentResult(
      errorMessage: 'WebFetch exceeded the maximum redirect limit.',
    );
  }

  bool _isRedirectStatusCode(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  void _pruneExpiredWebFetchCache() {
    final expiredKeys = _webFetchCache.entries
        .where((entry) => _isWebFetchCacheExpired(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expiredKeys) {
      _webFetchCache.remove(key);
    }
  }

  bool _isWebFetchCacheExpired(_CachedWebFetchContent entry) {
    return DateTime.now().toUtc().difference(entry.fetchedAt) >
        _webFetchCacheTtl;
  }

  bool _isRasterImageExtension(String extension) {
    return const <String>{
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.ico',
      '.tga',
    }.contains(extension);
  }

  bool _isKnownTextExtension(String extension) {
    if (extension.isEmpty) {
      return false;
    }
    return const <String>{
      '.txt',
      '.md',
      '.markdown',
      '.json',
      '.yaml',
      '.yml',
      '.toml',
      '.xml',
      '.html',
      '.htm',
      '.css',
      '.scss',
      '.sass',
      '.js',
      '.jsx',
      '.ts',
      '.tsx',
      '.dart',
      '.go',
      '.py',
      '.java',
      '.kt',
      '.kts',
      '.rb',
      '.rs',
      '.c',
      '.cc',
      '.cpp',
      '.h',
      '.hpp',
      '.sh',
      '.zsh',
      '.bash',
      '.fish',
      '.sql',
      '.csv',
      '.tsv',
      '.env',
      '.ini',
      '.cfg',
      '.conf',
      '.log',
      '.svg',
      '.vue',
    }.contains(extension);
  }

  bool _looksBinary(List<int> bytes) {
    final preview = bytes.take(2048);
    var suspiciousCount = 0;
    var inspected = 0;
    for (final value in preview) {
      inspected += 1;
      if (value == 0) {
        return true;
      }
      final isControl = value < 32 && value != 9 && value != 10 && value != 13;
      if (isControl) {
        suspiciousCount += 1;
      }
    }
    if (inspected == 0) {
      return false;
    }
    return suspiciousCount / inspected > 0.12;
  }

  String _decodeTextBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  String _readText(Object? value) {
    final text = '$value'.trim();
    if (text == 'null') {
      return '';
    }
    return text;
  }

  Map<String, Object?>? _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    return null;
  }

  int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse('$value'.trim());
  }

  List<String> _normalizeStringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((item) => '$item'.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _htmlToText(String html) {
    final withoutScripts = html
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
          ' ',
        );
    final withoutTags = withoutScripts.replaceAll(RegExp(r'<[^>]+>'), ' ');
    final withoutEntities = withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return withoutEntities.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _truncateContent(String content, int maxCharacters) {
    if (content.length <= maxCharacters) {
      return content;
    }
    return '${content.substring(0, maxCharacters)}...';
  }

  bool _globMatches(String value, String pattern) {
    final normalizedValue = value.replaceAll('\\', '/');
    final normalizedPattern = pattern.replaceAll('\\', '/');
    final regex = _globToRegExp(normalizedPattern);
    return regex.hasMatch(normalizedValue) ||
        regex.hasMatch('/$normalizedValue');
  }

  bool _matchesAnyGlob(String value, List<String> patterns) {
    for (final pattern in patterns) {
      if (_globMatches(value, pattern)) {
        return true;
      }
    }
    return false;
  }

  RegExp _globToRegExp(String pattern) {
    final buffer = StringBuffer('^');
    for (var index = 0; index < pattern.length; index++) {
      final char = pattern[index];
      if (char == '*') {
        final isDoubleStar =
            index + 1 < pattern.length && pattern[index + 1] == '*';
        if (isDoubleStar) {
          buffer.write('.*');
          index += 1;
        } else {
          buffer.write('[^/]*');
        }
        continue;
      }
      if (char == '?') {
        buffer.write('.');
        continue;
      }
      if (r'\.^$+()[]{}|'.contains(char)) {
        buffer.write('\\$char');
        continue;
      }
      buffer.write(char);
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  _ReplacementResult _replaceOnceOrAll({
    required String content,
    required String oldString,
    required String newString,
    required bool replaceAll,
  }) {
    if (oldString.isEmpty) {
      return const _ReplacementResult.failure('old_string must not be empty.');
    }
    final matchCount = RegExp(
      RegExp.escape(oldString),
    ).allMatches(content).length;
    if (matchCount == 0) {
      return const _ReplacementResult.failure(
        'old_string was not found in the file.',
      );
    }
    if (!replaceAll && matchCount > 1) {
      return const _ReplacementResult.failure(
        'old_string matched multiple locations. Provide more context or set replace_all.',
      );
    }
    return _ReplacementResult.success(
      replaceAll
          ? content.replaceAll(oldString, newString)
          : content.replaceFirst(oldString, newString),
    );
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

  AiToolExecutionResult _simpleSuccessResult({
    required String command,
    required String output,
    required int durationMs,
    String? workingDirectory,
    bool isWriteCommand = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: command,
      workingDirectory: workingDirectory ?? _defaultWorkingDirectory(),
      stdout: output,
      stderr: '',
      durationMs: durationMs,
      resultText: output.trim(),
      isWriteCommand: isWriteCommand,
      writeAnalysisReason: isWriteCommand ? 'builtin file mutation tool' : '',
      metadata: metadata,
    );
  }

  AiToolExecutionResult _invalidToolResult(String command, String message) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.invalidArguments,
      command: command,
      workingDirectory: _defaultWorkingDirectory(),
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

  List<_WebSearchResult> _parseDuckDuckGoResults(String html) {
    final matches = RegExp(
      r'<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>[\s\S]*?<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>',
      caseSensitive: false,
    ).allMatches(html);
    final results = <_WebSearchResult>[];
    for (final match in matches) {
      final url = _htmlToText(match.group(1) ?? '');
      final title = _htmlToText(match.group(2) ?? '');
      final snippet = _htmlToText(match.group(3) ?? '');
      if (url.isEmpty || title.isEmpty) {
        continue;
      }
      results.add(_WebSearchResult(title: title, url: url, snippet: snippet));
    }
    return results;
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
          'Execute a shell command in a subprocess. Use cmd for the command string and optionally working_directory for the working directory.',
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
          'Signal that planning is complete and implementation can begin.',
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

  static final AiResolvedTool _legacyBashAlias = _builtinTool(
    kind: AiBuiltinToolKind.bash,
    name: 'bash',
    description:
        'Legacy alias for Bash. Execute a shell command in a subprocess.',
    parameters: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'cmd': <String, Object?>{'type': 'string'},
        'working_directory': <String, Object?>{'type': 'string'},
      },
      'required': <String>['cmd'],
      'additionalProperties': false,
    },
  );

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

class _ReplacementResult {
  const _ReplacementResult._({
    required this.success,
    required this.content,
    required this.errorMessage,
  });

  const _ReplacementResult.success(String content)
    : this._(success: true, content: content, errorMessage: '');

  const _ReplacementResult.failure(String errorMessage)
    : this._(success: false, content: '', errorMessage: errorMessage);

  final bool success;
  final String content;
  final String errorMessage;
}

class _WebSearchResult {
  const _WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  final String title;
  final String url;
  final String snippet;
}

class _RenderedReadContent {
  const _RenderedReadContent({
    required this.content,
    required this.fileKind,
    required this.renderMode,
    required this.lineAddressable,
    this.truncated = false,
  });

  final String content;
  final String fileKind;
  final String renderMode;
  final bool lineAddressable;
  final bool truncated;
}

class _CachedWebFetchContent {
  const _CachedWebFetchContent({
    required this.body,
    required this.contentType,
    required this.finalUrl,
    required this.fetchedAt,
  });

  final String body;
  final String contentType;
  final String finalUrl;
  final DateTime fetchedAt;
}

class _WebFetchContentResult {
  const _WebFetchContentResult({
    this.body,
    this.contentType,
    this.finalUrl,
    this.crossHostRedirectUrl,
    this.errorMessage,
    this.fromCache = false,
  });

  final String? body;
  final String? contentType;
  final String? finalUrl;
  final String? crossHostRedirectUrl;
  final String? errorMessage;
  final bool fromCache;
}

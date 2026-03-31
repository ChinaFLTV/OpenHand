// 2026-04-01 02:02:39
// AiToolRegistry — 多态工具调度中心（完整版，含服务依赖注册）
// 用法：
//   final registry = AiToolRegistry.withServiceDependencies(...)
//   final result = await registry.tryExecute(context, kind)
import 'dart:io';

import 'package:http/http.dart' as http;

import '../service/ai_bash_tool_service.dart';
import '../service/ai_chat_service.dart';
import '../service/ai_claude_hook_service.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_bash_tool.dart';
import 'ai_edit_tool.dart';
import 'ai_exit_plan_mode_tool.dart';
import 'ai_glob_tool.dart';
import 'ai_grep_tool.dart';
import 'ai_ls_tool.dart';
import 'ai_multi_edit_tool.dart';
import 'ai_notebook_edit_tool.dart';
import 'ai_read_tool.dart';
import 'ai_task_tool.dart';
import 'ai_todo_write_tool.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_web_fetch_tool.dart';
import 'ai_web_search_tool.dart';
import 'ai_write_tool.dart';

export 'ai_task_tool.dart' show AiSubToolExecutor;
export 'ai_tool.dart';
export 'ai_tool_execution_context.dart';

class AiToolRegistry {
  AiToolRegistry._();

  final Map<AiBuiltinToolKind, AiTool> _tools = {};

  // ──────────────────────────────────────────────────────────────
  // 工厂：仅注册无外部 IO 依赖的轻量工具（用于测试和内部组合）
  // ──────────────────────────────────────────────────────────────
  factory AiToolRegistry.lightweightOnly() {
    return AiToolRegistry._()
      ..register(AiLsTool())
      ..register(AiGlobTool())
      ..register(AiGrepTool())
      ..register(AiEditTool())
      ..register(AiMultiEditTool())
      ..register(AiWriteTool())
      ..register(AiExitPlanModeTool())
      ..register(AiTodoWriteTool())
      ..register(AiNotebookEditTool())
      ..register(AiReadTool());
  }

  // ──────────────────────────────────────────────────────────────
  // 工厂：注册所有工具（含外部服务依赖，供 AiToolRuntimeService 使用）
  // ──────────────────────────────────────────────────────────────
  factory AiToolRegistry.withServiceDependencies({
    required AiBashToolService bashToolService,
    required AiClaudeHookService hookService,
    required AiChatClient backgroundChatClient,
    required http.Client httpClient,
    Future<List<InternetAddress>> Function(String host)? hostLookup,
  }) {
    final registry = AiToolRegistry.lightweightOnly();

    // Bash — 需要 AiBashToolService + AiClaudeHookService（Permission hooks）
    registry.register(AiBashTool(
      bashToolService: bashToolService,
      hookService: hookService,
    ));

    // WebFetch — 需要 http.Client + AiChatClient
    registry.register(AiWebFetchTool(
      backgroundChatClient: backgroundChatClient,
      httpClient: httpClient,
      hostLookup: hostLookup,
    ));

    // WebSearch — 需要 http.Client + AiChatClient
    registry.register(AiWebSearchTool(
      backgroundChatClient: backgroundChatClient,
      httpClient: httpClient,
    ));

    // Task — 需要 AiChatClient + AiClaudeHookService + Sub-tool executor
    final taskTool = AiTaskTool(
      backgroundChatClient: backgroundChatClient,
      hookService: hookService,
    );
    // 注入 sub-tool executor：将子工具调用委托回 registry 本身
    taskTool.withExecutor((parentContext, subContext) async {
      final resolvedTool = subContext.catalog.find(subContext.toolCall.name);
      if (resolvedTool?.builtinKind == null) {
        return AiToolExecutionResult(
          status: BashToolExecutionStatus.invalidArguments,
          command: subContext.toolCall.name,
          workingDirectory: subContext.catalog.toolsByName.isEmpty
              ? ''
              : subContext.catalog.toolsByName.values.first.definition.name,
          stdout: '',
          stderr: 'Unsupported sub-tool: ${subContext.toolCall.name}',
          durationMs: 0,
          resultText:
              'status: invalid_arguments\nerror: Unsupported sub-tool: ${subContext.toolCall.name}',
        );
      }
      final result = await registry.tryExecute(subContext, resolvedTool!.builtinKind!);
      if (result != null) return result;
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.invalidArguments,
        command: subContext.toolCall.name,
        workingDirectory: '',
        stdout: '',
        stderr: 'Sub-tool not available in subagent context: ${subContext.toolCall.name}',
        durationMs: 0,
        resultText:
            'status: invalid_arguments\nerror: Sub-tool not available in subagent context: ${subContext.toolCall.name}',
      );
    });
    registry.register(taskTool);

    return registry;
  }

  // ──────────────────────────────────────────────────────────────
  // 核心操作
  // ──────────────────────────────────────────────────────────────

  void register(AiTool tool) {
    _tools[tool.kind] = tool;
  }

  AiTool? getTool(AiBuiltinToolKind kind) => _tools[kind];

  bool supports(AiBuiltinToolKind kind) => _tools.containsKey(kind);

  /// 尝试通过 Registry 执行工具，若未注册则返回 null（由调用方回退到旧路径）。
  Future<AiToolExecutionResult?> tryExecute(
    AiToolExecutionContext context,
    AiBuiltinToolKind kind,
  ) async {
    final tool = _tools[kind];
    if (tool == null) return null;
    return tool.execute(context);
  }
}

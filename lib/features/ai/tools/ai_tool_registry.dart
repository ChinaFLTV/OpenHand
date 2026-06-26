import 'dart:io';

import 'package:http/http.dart' as http;

import '../service/bash/ai_bash_tool_service.dart';
import '../service/chat/ai_chat_service.dart';
import '../service/hook/ai_claude_hook_service.dart';
import '../service/runtime/ai_tool_runtime_service.dart';
import '../service/web_fetch/web_fetch_scrapling_bridge.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'bash/ai_bash_background_tool.dart';
import 'bash/ai_bash_tool.dart';
import 'fs/ai_apply_file_diffs_tool.dart';
import 'fs/ai_delete_file_tool.dart';
import 'fs/ai_edit_tool.dart';
import 'fs/ai_glob_tool.dart';
import 'fs/ai_ls_tool.dart';
import 'fs/ai_multi_edit_tool.dart';
import 'fs/ai_notebook_edit_tool.dart';
import 'fs/ai_read_tool.dart';
import 'fs/ai_write_tool.dart';
import 'git/ai_git_tool.dart';
import 'knowledge/ai_knowledge_base_tool.dart';
import 'lsp/ai_lsp_tool.dart';
import 'lsp/ai_read_lints_tool.dart';
import 'memory/ai_memory_tool.dart';
import 'planning/ai_ask_user_choice_tool.dart';
import 'planning/ai_exit_plan_mode_tool.dart';
import 'planning/ai_task_tool.dart';
import 'planning/ai_todo_write_tool.dart';
import 'search/ai_codebase_search_tool.dart';
import 'search/ai_grep_tool.dart';
import 'search/ai_tool_search_tool.dart';
import 'skill/ai_skill_manager_tool.dart';
import 'web/ai_web_fetch_tool.dart';
import 'web/ai_web_search_tool.dart';

export 'ai_tool.dart';
export 'ai_tool_execution_context.dart';
export 'planning/ai_task_tool.dart' show AiSubToolExecutor;

class AiToolRegistry {
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
      ..register(AiApplyFileDiffsTool())
      ..register(AiWriteTool())
      ..register(AiExitPlanModeTool())
      ..register(AiTodoWriteTool())
      ..register(AiNotebookEditTool())
      ..register(AiReadTool())
      ..register(AiLspTool())
      ..register(AiCodebaseSearchTool())
      ..register(AiGitTool())
      ..register(AiDeleteFileTool())
      ..register(AiReadLintsTool())
      ..register(AiKnowledgeSearchTool())
      ..register(AiKnowledgeReadTool())
      ..register(AiToolSearchTool())
      ..register(AiAskUserChoiceTool());
  }

  // ──────────────────────────────────────────────────────────────
  // 工厂：注册所有工具（含外部服务依赖，供 AiToolRuntimeService 使用）
  // ──────────────────────────────────────────────────────────────
  factory AiToolRegistry.withServiceDependencies({
    required AiBashToolService bashToolService,
    required AiClaudeHookService hookService,
    required AiChatClient backgroundChatClient,
    required http.Client httpClient,
    required WebFetchScraplingBridge scraplingBridge,
    Future<List<InternetAddress>> Function(String host)? hostLookup,
    String Function()? skillsDirProvider,
    MemoryControllerProvider? memoryControllerProvider,
  }) {
    final registry = AiToolRegistry.lightweightOnly();

    // Bash — 需要 AiBashToolService + AiClaudeHookService（Permission hooks）
    registry.register(
      AiBashTool(bashToolService: bashToolService, hookService: hookService),
    );

    // BashBackground — 长跑后台子进程，共用 Bash 写命令分析、hook 与 sandbox 设置。
    registry.register(
      AiBashBackgroundTool(
        bashToolService: bashToolService,
        hookService: hookService,
      ),
    );

    // SkillManager — 需要 skills directory provider (Hermes Talker builtin).
    // Only registered when a provider is wired; sessions where the user has
    // not configured a skills directory will surface a friendly error at
    // runtime via the provider returning an empty string.
    if (skillsDirProvider != null) {
      registry.register(
        AiSkillManagerTool(skillsDirProvider: skillsDirProvider),
      );
    }

    // Memory — Hermes Talker self-learning sub-agent writes here.
    if (memoryControllerProvider != null) {
      registry.register(
        AiMemoryTool(memoryControllerProvider: memoryControllerProvider),
      );
    }

    // WebFetch — 需要 http.Client + AiChatClient
    registry.register(
      AiWebFetchTool(
        backgroundChatClient: backgroundChatClient,
        httpClient: httpClient,
        scraplingBridge: scraplingBridge,
        hostLookup: hostLookup,
      ),
    );

    // WebSearch — 需要 http.Client + AiChatClient
    registry.register(
      AiWebSearchTool(
        backgroundChatClient: backgroundChatClient,
        httpClient: httpClient,
      ),
    );

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
      final result = await registry.tryExecute(
        subContext,
        resolvedTool!.builtinKind!,
      );
      if (result != null) return result;
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.invalidArguments,
        command: subContext.toolCall.name,
        workingDirectory: '',
        stdout: '',
        stderr:
            'Sub-tool not available in subagent context: ${subContext.toolCall.name}',
        durationMs: 0,
        resultText:
            'status: invalid_arguments\nerror: Sub-tool not available in subagent context: ${subContext.toolCall.name}',
      );
    });
    registry.register(taskTool);

    return registry;
  }
  AiToolRegistry._();

  final Map<AiBuiltinToolKind, AiTool> _tools = {};

  /// 别名映射表：工具名称字符串 → AiBuiltinToolKind
  /// 由 [register] 在注册时自动填充来自 [AiTool.aliases] 的别名。
  final Map<String, AiBuiltinToolKind> _aliasToKind = {};

  // ──────────────────────────────────────────────────────────────
  // 核心操作
  // ──────────────────────────────────────────────────────────────

  /// 注册工具。
  /// 同时将 [AiTool.aliases] 中的每个别名映射到本工具的 [AiTool.kind]，
  /// 以支持向后兼容旧工具名（如 'bash' → AiBuiltinToolKind.bash）。
  void register(AiTool tool) {
    _tools[tool.kind] = tool;
    for (final alias in tool.aliases) {
      final normalized = alias.trim();
      if (normalized.isNotEmpty) {
        _aliasToKind[normalized] = tool.kind;
      }
    }
  }

  AiTool? getTool(AiBuiltinToolKind kind) => _tools[kind];

  bool supports(AiBuiltinToolKind kind) => _tools.containsKey(kind);

  /// 通过别名字符串查找对应的 [AiBuiltinToolKind]。
  /// 若无匹配别名则返回 null。
  ///
  /// 使用场景：
  /// - [tryExecute] 内部将此方法作为全局 kind 查找失败后的备用路径。
  /// - 外部调用方可用于工具名字串→kind 的类型安全转换。
  AiBuiltinToolKind? kindFromAlias(String alias) {
    return _aliasToKind[alias.trim()];
  }

  // 2026-04-01 10:27:21 L1: 别名兼容层
  // 2026-04-01 10:31:10 P1-3: 集成权限门 —— execute 前先调用 checkPermissions。
  // AiToolPermissionAllowed → 继续执行。
  // AiToolPermissionDenied  → 构造拒绝结果直接返回，不调用 execute()。
  Future<AiToolExecutionResult?> tryExecute(
    AiToolExecutionContext context,
    AiBuiltinToolKind kind,
  ) async {
    final tool = _tools[kind] ?? _toolFromCallAlias(context.toolCall.name);
    if (tool == null) return null;
    final permResult = await tool.checkPermissions(context);
    if (permResult case final AiToolPermissionDenied denied) {
      return _permissionDeniedResult(context.toolCall.name, denied.reason);
    }
    return tool.execute(context);
  }

  /// 构造权限拒绝的 [AiToolExecutionResult]。
  AiToolExecutionResult _permissionDeniedResult(
    String toolName,
    String reason,
  ) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: toolName,
      workingDirectory: '',
      stdout: '',
      stderr: reason,
      durationMs: 0,
      resultText: 'status: permission_denied\nerror: $reason',
      metadata: const <String, Object?>{
        'tool_source': 'builtin',
        'permission_denied': true,
      },
    );
  }

  /// 通过工具调用名称字符串查找工具实例（别名备用路径）。
  AiTool? _toolFromCallAlias(String name) {
    final aliasKind = kindFromAlias(name);
    if (aliasKind == null) return null;
    return _tools[aliasKind];
  }
}

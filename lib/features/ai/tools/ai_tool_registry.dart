import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../app/support/silent_log.dart';
import '../../../shared/model/dingtalk_multimodal_capability.dart';
import '../../knowledge_base/knowledge_base_controller.dart';
import '../../machine_terminal/index.dart';
import '../model/ai_model_config.dart';
import '../service/bash/ai_bash_tool_service.dart';
import '../service/chat/ai_chat_service.dart';
import '../service/hook/ai_claude_hook_service.dart';
import '../service/runtime/ai_tool_runtime_service.dart';
import '../service/web_fetch/web_fetch_scrapling_bridge.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'bash/ai_bash_background_tool.dart';
import 'bash/ai_bash_tool.dart';
import 'dingtalk/ai_dingtalk_dws_tool.dart';
import 'dingtalk/ai_dingtalk_media_generation_tool.dart';
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
import 'search/ai_dingtalk_tool_search_tool.dart';
import 'search/ai_grep_tool.dart';
import 'search/ai_tool_search_tool.dart';
import 'skill/ai_skill_manager_tool.dart';
import 'terminal/ai_machine_terminal_tools.dart';
import 'web/ai_web_fetch_tool.dart';
import 'web/ai_web_search_tool.dart';

export 'ai_tool.dart';
export 'ai_tool_execution_context.dart';
export 'planning/ai_task_tool.dart' show AiSubToolExecutor;

typedef AiSubToolExecutionObserver =
    Future<void> Function(
      AiToolExecutionContext parentContext,
      AiToolExecutionContext subContext,
      AiToolExecutionResult result,
    );

class AiToolRegistry {
  // 先注册无外部 IO 依赖的基础工具，供完整注册表继续装配。
  factory AiToolRegistry.lightweightOnly({
    KnowledgeBaseController? Function()? knowledgeBaseControllerProvider,
    List<AiModelConfig> Function()? aiModelsProvider,
  }) {
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
      ..register(
        AiKnowledgeSearchTool(
          knowledgeBaseControllerProvider: knowledgeBaseControllerProvider,
          aiModelsProvider: aiModelsProvider,
        ),
      )
      ..register(AiKnowledgeReadTool())
      ..register(AiToolSearchTool())
      ..register(AiDingTalkToolSearchTool())
      ..register(AiDingTalkDwsTool())
      ..register(
        AiDingTalkMediaGenerationTool(
          AiDingTalkMultimodalCapability.imageGeneration,
        ),
      )
      ..register(
        AiDingTalkMediaGenerationTool(
          AiDingTalkMultimodalCapability.videoGeneration,
        ),
      )
      ..register(
        AiDingTalkMediaGenerationTool(
          AiDingTalkMultimodalCapability.audioGeneration,
        ),
      )
      ..register(AiAskUserChoiceTool());
  }

  // 工厂：注册所有工具（含外部服务依赖，供 AiToolRuntimeService 使用）
  factory AiToolRegistry.withServiceDependencies({
    required AiBashToolService bashToolService,
    required AiClaudeHookService hookService,
    required AiChatClient backgroundChatClient,
    required http.Client httpClient,
    required WebFetchScraplingBridge scraplingBridge,
    Future<List<InternetAddress>> Function(String host)? hostLookup,
    String Function()? skillsDirProvider,
    MemoryControllerProvider? memoryControllerProvider,
    KnowledgeBaseController? Function()? knowledgeBaseControllerProvider,
    List<AiModelConfig> Function()? aiModelsProvider,
    MachineTerminalService? machineTerminalService,
    AiSubToolExecutionObserver? subToolExecutionObserver,
  }) {
    final registry = AiToolRegistry.lightweightOnly(
      knowledgeBaseControllerProvider: knowledgeBaseControllerProvider,
      aiModelsProvider: aiModelsProvider,
    );

    // Bash 需要 AiBashToolService 和 AiClaudeHookService（权限钩子）。
    registry.register(
      AiBashTool(bashToolService: bashToolService, hookService: hookService),
    );

    // BashBackground 负责长跑后台子进程，共用 Bash 写命令分析、钩子与沙箱设置。
    registry.register(
      AiBashBackgroundTool(
        bashToolService: bashToolService,
        hookService: hookService,
      ),
    );

    // SkillManager 仅在接入目录提供器后注册，空目录由工具在运行时提示。
    if (skillsDirProvider != null) {
      registry.register(
        AiSkillManagerTool(skillsDirProvider: skillsDirProvider),
      );
    }

    // Memory 用于保存 Hermes Talker 子智能体的自学习内容。
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

    if (machineTerminalService != null) {
      registry
        ..register(AiMachineTerminalReadTool())
        ..register(AiMachineTerminalWriteTool())
        ..register(AiMachineTerminalExecTool())
        ..register(AiMachineTerminalControlTool());
    }

    // Task 需要 AiChatClient、AiClaudeHookService 和子工具执行器。
    final taskTool = AiTaskTool(
      backgroundChatClient: backgroundChatClient,
      hookService: hookService,
    );
    taskTool.withExecutor(
      (parentContext, subContext) => registry._executeSubTool(
        parentContext,
        subContext,
        observer: subToolExecutionObserver,
        unsupportedError: '不支持的子工具：${subContext.toolCall.name}',
        unavailableError: '子智能体上下文中不可用的工具：${subContext.toolCall.name}',
      ),
    );
    registry.register(taskTool);

    return registry;
  }
  AiToolRegistry._();

  final Map<AiBuiltinToolKind, AiTool> _tools = {};
  Future<void>? _disposeFuture;
  bool _disposed = false;

  /// 别名映射表：工具名称字符串 → AiBuiltinToolKind
  /// 由 [register] 在注册时自动填充来自 [AiTool.aliases] 的别名。
  final Map<String, AiBuiltinToolKind> _aliasToKind = {};

  // 核心操作

  /// 注册工具。
  /// 同时将 [AiTool.aliases] 中的每个别名映射到本工具的 [AiTool.kind]，
  /// 以支持向后兼容旧工具名（如 'bash' → AiBuiltinToolKind.bash）。
  void register(AiTool tool) {
    if (_disposed) {
      throw StateError('AI 工具注册表已释放。');
    }
    _tools[tool.kind] = tool;
    for (final alias in tool.aliases) {
      final normalized = alias.trim();
      if (normalized.isNotEmpty) {
        _aliasToKind[normalized] = tool.kind;
      }
    }
  }

  AiTool? getTool(AiBuiltinToolKind kind) => _tools[kind];

  /// 通过别名字符串查找对应的 [AiBuiltinToolKind]。
  /// 若无匹配别名则返回 null。
  ///
  /// 使用场景：
  /// - [tryExecute] 内部将此方法作为全局 kind 查找失败后的备用路径。
  /// - 外部调用方可用于工具名字串→kind 的类型安全转换。
  AiBuiltinToolKind? kindFromAlias(String alias) {
    return _aliasToKind[alias.trim()];
  }

  Future<AiToolExecutionResult?> tryExecute(
    AiToolExecutionContext context,
    AiBuiltinToolKind kind,
  ) async {
    if (_disposed) return null;
    final tool = _tools[kind] ?? _toolFromCallAlias(context.toolCall.name);
    if (tool == null) return null;
    return tool.execute(context);
  }

  Future<AiToolExecutionResult> _executeSubTool(
    AiToolExecutionContext parentContext,
    AiToolExecutionContext subContext, {
    required AiSubToolExecutionObserver? observer,
    required String unsupportedError,
    required String unavailableError,
  }) async {
    AiToolExecutionResult invalidResult(String error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.invalidArguments,
        command: subContext.toolCall.name,
        workingDirectory: '',
        stdout: '',
        stderr: error,
        durationMs: 0,
        resultText: 'status: invalid_arguments\nerror: $error',
      );
    }

    final kind = subContext.catalog.find(subContext.toolCall.name)?.builtinKind;
    if (kind == null) return invalidResult(unsupportedError);

    final result = await tryExecute(subContext, kind);
    if (result == null) return invalidResult(unavailableError);

    await _notifySubToolExecuted(observer, parentContext, subContext, result);
    return result;
  }

  /// 通过工具调用名称字符串查找工具实例（别名备用路径）。
  AiTool? _toolFromCallAlias(String name) {
    final aliasKind = kindFromAlias(name);
    if (aliasKind == null) return null;
    return _tools[aliasKind];
  }

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    _disposed = true;
    final tools = _tools.values.toSet().toList(growable: false);
    _tools.clear();
    _aliasToKind.clear();
    return _disposeFuture = Future.wait<void>(
      tools.map((tool) => tool.dispose()),
    );
  }
}

Future<void> _notifySubToolExecuted(
  AiSubToolExecutionObserver? observer,
  AiToolExecutionContext parentContext,
  AiToolExecutionContext subContext,
  AiToolExecutionResult result,
) async {
  if (observer == null) return;
  try {
    await observer(parentContext, subContext, result);
  } catch (error, stack) {
    silentLog('ai_tool_registry', '记录子智能体工具调用统计', error, stack);
  }
}

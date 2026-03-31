// 2026-04-01 01:21:38
// AiToolRegistry — 多态工具调度中心
// 职责：注册 AiTool 实例，根据 AiBuiltinToolKind 路由执行请求。
// 用法：
//   final registry = AiToolRegistry.defaultRegistry();
//   final result = await registry.execute(context, kind);

import '../service/ai_tool_runtime_service.dart';
import 'ai_edit_tool.dart';
import 'ai_exit_plan_mode_tool.dart';
import 'ai_glob_tool.dart';
import 'ai_grep_tool.dart';
import 'ai_ls_tool.dart';
import 'ai_multi_edit_tool.dart';
import 'ai_todo_write_tool.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_write_tool.dart';

export 'ai_tool.dart';
export 'ai_tool_execution_context.dart';

class AiToolRegistry {
  AiToolRegistry._();

  final Map<AiBuiltinToolKind, AiTool> _tools = {};

  /// 创建并注册所有"无外部依赖"的内建轻量工具。
  /// WebFetch / WebSearch / Bash / Task / Read / NotebookEdit 因需注入服务依赖，
  /// 在 AiToolRuntimeService 中通过 registerServiceDependentTools() 补充注册。
  factory AiToolRegistry.defaultRegistry() {
    return AiToolRegistry._()
      ..register(AiLsTool())
      ..register(AiGlobTool())
      ..register(AiGrepTool())
      ..register(AiEditTool())
      ..register(AiMultiEditTool())
      ..register(AiWriteTool())
      ..register(AiExitPlanModeTool())
      ..register(AiTodoWriteTool());
  }

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

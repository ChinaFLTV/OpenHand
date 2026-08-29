import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../hooks/index.dart';
import '../knowledge_base/knowledge_base_controller.dart';
import '../machine_terminal/index.dart';
import '../memory/index.dart';
import 'ai_session_controller.dart';
import 'model/ai_model_config.dart';
import 'service/hook/ai_claude_hook_service.dart';

/// AI 是状态机心脏，由 [AiSessionController] 持有整个会话状态。bootstrap
/// 必须 await，且依赖：
/// - hooks executor（hook 服务）
/// - skills directory provider（懒求值的字符串提供者）
/// - memory controller provider（延迟绑定；memory 是非首屏关键路径，
///   构造时可能尚未就绪；通过 provider 闭包延迟取值）
///
/// 注意：AiSessionController.create 是真正异步重活（state 装载 + I/O），
/// 不要原地 await — 由 main.dart 早 kick-off + 后期 await，与 hooks/skills/mcp
/// 等并行启动。
class AiModule {
  AiModule._({required this.controller});

  final AiSessionController controller;

  static Future<AiModule> bootstrap({
    required HooksExecutor userHooksExecutor,
    required String Function() skillsDirProvider,
    required MemoryController? Function() memoryControllerProvider,
    required List<AiModelConfig> Function() aiModelsProvider,
    required KnowledgeBaseController? Function()
    knowledgeBaseControllerProvider,
    required MachineTerminalService machineTerminalService,
  }) async {
    final controller = await AiSessionController.create(
      hookService: AiClaudeHookService(),
      userHooksExecutor: userHooksExecutor,
      skillsDirProvider: skillsDirProvider,
      memoryControllerProvider: memoryControllerProvider,
      aiModelsProvider: aiModelsProvider,
      knowledgeBaseControllerProvider: knowledgeBaseControllerProvider,
      machineTerminalService: machineTerminalService,
    );
    return AiModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(AiModule m) => [
    ChangeNotifierProvider<AiSessionController>.value(value: m.controller),
  ];
}

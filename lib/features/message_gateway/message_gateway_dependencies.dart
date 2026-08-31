import '../../app/model/app_info.dart';
import '../../app/state/settings_controller.dart';
import '../ai/index.dart';
import '../crons/index.dart';
import '../hooks/index.dart' show HooksController;
import '../instructions/index.dart';
import '../knowledge_base/index.dart' show KnowledgeBaseController;
import '../machine_terminal/index.dart';
import '../mcp/index.dart';
import '../memory/index.dart';
import '../skills/index.dart';
import '../workflows/index.dart' show WorkflowsController;

/// 消息网关运行所需的全部外部依赖。
///
/// 这些依赖此前在模块 bootstrap、控制器构造、平台服务构造三处逐字重复
/// 声明，再逐层原样转发两次：新增一个依赖要改三处签名加两处转发，漏一处就是
/// 编译错误，而同类型参数写错顺序则是静默错配。收成一个参数对象后只剩一处
/// 定义、一处构造。
class MessageGatewayDependencies {
  const MessageGatewayDependencies({
    required this.sessionController,
    required this.settingsController,
    required this.skillsController,
    required this.mcpController,
    required this.memoryController,
    required this.cronsController,
    required this.hooksController,
    required this.instructionsController,
    required this.machineTerminalService,
    required this.appInfo,
    required this.workflowsController,
    this.knowledgeBaseController,
  });

  final AiSessionController sessionController;
  final SettingsController settingsController;
  final SkillsController skillsController;
  final McpController mcpController;
  final MemoryController memoryController;
  final CronsController cronsController;
  final HooksController hooksController;
  final InstructionsController instructionsController;
  final MachineTerminalService machineTerminalService;
  final AppInfo appInfo;
  final WorkflowsController workflowsController;

  /// 知识库为可选能力：未启用时网关照常工作，只是不提供检索类接口。
  final KnowledgeBaseController? knowledgeBaseController;
}

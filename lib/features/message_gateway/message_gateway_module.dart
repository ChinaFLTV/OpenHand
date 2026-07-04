import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../app/model/app_info.dart';
import '../../app/state/settings_controller.dart';
import '../agents/index.dart';
import '../ai/index.dart';
import '../crons/index.dart';
import '../instructions/index.dart';
import '../knowledge_base/index.dart' show KnowledgeBaseController;
import '../mcp/index.dart';
import '../memory/index.dart';
import '../skills/index.dart';
import 'message_gateway_controller.dart';

class MessageGatewayModule {
  MessageGatewayModule._({required this.controller});

  final MessageGatewayController controller;

  static Future<MessageGatewayModule> bootstrap({
    required AiSessionController sessionController,
    required SettingsController settingsController,
    required AgentsController agentsController,
    required SkillsController skillsController,
    required McpController mcpController,
    required MemoryController memoryController,
    required CronsController cronsController,
    required InstructionsController instructionsController,
    KnowledgeBaseController? knowledgeBaseController,
    required AppInfo appInfo,
  }) async {
    final controller = MessageGatewayController.uninitialized(
      sessionController: sessionController,
      settingsController: settingsController,
      agentsController: agentsController,
      skillsController: skillsController,
      mcpController: mcpController,
      memoryController: memoryController,
      cronsController: cronsController,
      instructionsController: instructionsController,
      knowledgeBaseController: knowledgeBaseController,
      appInfo: appInfo,
    );
    return MessageGatewayModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(MessageGatewayModule m) => [
    ChangeNotifierProvider<MessageGatewayController>.value(value: m.controller),
  ];
}

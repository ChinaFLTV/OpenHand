import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../app/model/app_info.dart';
import '../../app/state/settings_controller.dart';
import '../ai/ai_session_controller.dart';
import '../crons/index.dart';
import '../instructions/index.dart';
import '../mcp/index.dart';
import '../memory/index.dart';
import '../skills/index.dart';
import 'message_gateway_controller.dart';

/// Assembly point for the message_gateway feature.
///
/// MessageGatewayController is a cross-feature coordinator — it injects
/// every other feature's controller. Therefore `bootstrap()` MUST be called
/// AFTER the dependent modules' futures have resolved, and CANNOT be kicked
/// off in parallel with them. The plugin_service controller is late-bound
/// via the existing public field.
///
/// Pending: features/ai/* deep imports remain inside this controller until
/// P1 ai 拆解 lands a proper ai barrel.
class MessageGatewayModule {
  MessageGatewayModule._({required this.controller});

  final MessageGatewayController controller;

  static Future<MessageGatewayModule> bootstrap({
    required AiSessionController sessionController,
    required SettingsController settingsController,
    required SkillsController skillsController,
    required McpController mcpController,
    required MemoryController memoryController,
    required CronsController cronsController,
    required InstructionsController instructionsController,
    required AppInfo appInfo,
  }) async {
    final controller = MessageGatewayController.uninitialized(
      sessionController: sessionController,
      settingsController: settingsController,
      skillsController: skillsController,
      mcpController: mcpController,
      memoryController: memoryController,
      cronsController: cronsController,
      instructionsController: instructionsController,
      appInfo: appInfo,
    );
    return MessageGatewayModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(MessageGatewayModule m) => [
    ChangeNotifierProvider<MessageGatewayController>.value(
      value: m.controller,
    ),
  ];
}

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'message_gateway_controller.dart';
import 'message_gateway_dependencies.dart';

class MessageGatewayModule {
  MessageGatewayModule._({required this.controller});

  final MessageGatewayController controller;

  static Future<MessageGatewayModule> bootstrap(
    MessageGatewayDependencies dependencies,
  ) async {
    return MessageGatewayModule._(
      controller: MessageGatewayController.uninitialized(dependencies),
    );
  }

  static List<SingleChildWidget> providers(MessageGatewayModule m) => [
    ChangeNotifierProvider<MessageGatewayController>.value(value: m.controller),
  ];
}

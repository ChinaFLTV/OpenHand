import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'agents_controller.dart';
import 'data/agents_store.dart';

class AgentsModule {
  const AgentsModule._({required this.controller});

  final AgentsController controller;

  static Future<AgentsModule> bootstrap({AgentsStore? store}) async {
    return AgentsModule._(
      controller: AgentsController.uninitialized(store: store),
    );
  }

  static List<SingleChildWidget> providers(AgentsModule module) => [
    ChangeNotifierProvider<AgentsController>.value(value: module.controller),
  ];
}

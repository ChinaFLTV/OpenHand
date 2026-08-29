import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'workflows_controller.dart';

class WorkflowsModule {
  WorkflowsModule._(this.controller);

  final WorkflowsController controller;

  static Future<WorkflowsModule> bootstrap() async {
    return WorkflowsModule._(await WorkflowsController.create());
  }

  static List<SingleChildWidget> providers(
    WorkflowsModule module,
  ) => <SingleChildWidget>[
    ChangeNotifierProvider<WorkflowsController>.value(value: module.controller),
  ];
}

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'instructions_controller.dart';

/// 模块构造保持轻量；`main.dart` 在后台刷新数据，避免 SQLite 加载阻塞首帧。
class InstructionsModule {
  InstructionsModule._({required this.controller});

  final InstructionsController controller;

  static Future<InstructionsModule> bootstrap() async {
    final controller = InstructionsController.uninitialized();
    return InstructionsModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(InstructionsModule m) => [
    ChangeNotifierProvider<InstructionsController>.value(value: m.controller),
  ];
}

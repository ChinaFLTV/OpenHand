import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'memory_controller.dart';

/// 模块构造保持轻量；`main.dart` 在后台刷新数据，避免记忆加载阻塞首帧。
class MemoryModule {
  MemoryModule._({required this.controller});

  final MemoryController controller;

  static Future<MemoryModule> bootstrap() async {
    final controller = MemoryController.uninitialized();
    return MemoryModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(MemoryModule m) => [
    ChangeNotifierProvider<MemoryController>.value(value: m.controller),
  ];
}

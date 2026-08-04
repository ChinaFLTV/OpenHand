import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'crons_controller.dart';

/// 定时任务模块装配入口。
///
/// 控制器同步构造；数据库、调度器与信号监听在 [CronsController.initialize]
/// 中延迟初始化，避免阻塞启动。
class CronsModule {
  CronsModule._({required this.controller});

  final CronsController controller;

  static Future<CronsModule> bootstrap() async {
    final controller = CronsController.uninitialized();
    return CronsModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(CronsModule m) => [
    ChangeNotifierProvider<CronsController>.value(value: m.controller),
  ];
}

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'plugin_service_controller.dart';

/// 插件服务功能的装配入口。
///
/// 模块同步构造，首次扫描由 `main.dart` 在后台启动，避免阻塞首帧。
class PluginServiceModule {
  PluginServiceModule._({required this.controller});

  final PluginServiceController controller;

  static Future<PluginServiceModule> bootstrap() async {
    final controller = PluginServiceController();
    return PluginServiceModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(PluginServiceModule m) => [
    ChangeNotifierProvider<PluginServiceController>.value(value: m.controller),
  ];
}

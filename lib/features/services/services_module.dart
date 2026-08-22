import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../app/support/silent_log.dart';
import 'ai_model_proxy_controller.dart';
import 'data/ai_exposure_preferences_store.dart';
import 'model/ai_exposure_models.dart';
import 'services_controller.dart';

class ServicesModule {
  const ServicesModule._({
    required this.controller,
    required this.aiModelProxyController,
  });

  final ServicesController controller;
  final AiModelProxyController aiModelProxyController;

  static Future<ServicesModule> bootstrap() async {
    final store = AiExposurePreferencesStore();
    AiExposurePreferences preferences;
    try {
      preferences = await store.load();
    } catch (error, stack) {
      silentLog('services_module', '加载扫描服务设置', error, stack);
      preferences = AiExposurePreferences.defaults();
    }
    final controller = ServicesController(
      preferencesStore: store,
      initialPreferences: preferences,
    );
    final aiModelProxyController = AiModelProxyController();
    aiModelProxyController.attachNetworkProxyProvider(
      () => controller.proxyConfiguration,
    );
    await aiModelProxyController.load();
    return ServicesModule._(
      controller: controller,
      aiModelProxyController: aiModelProxyController,
    );
  }

  static List<SingleChildWidget> providers(
    ServicesModule module,
  ) => <SingleChildWidget>[
    ChangeNotifierProvider<ServicesController>.value(value: module.controller),
    ChangeNotifierProvider<AiModelProxyController>.value(
      value: module.aiModelProxyController,
    ),
  ];
}

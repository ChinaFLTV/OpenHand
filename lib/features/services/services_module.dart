import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../app/support/silent_log.dart';
import 'data/ai_exposure_preferences_store.dart';
import 'model/ai_exposure_models.dart';
import 'services_controller.dart';

class ServicesModule {
  const ServicesModule._({required this.controller});

  final ServicesController controller;

  static Future<ServicesModule> bootstrap() async {
    final store = AiExposurePreferencesStore();
    AiExposurePreferences preferences;
    try {
      preferences = await store.load();
    } catch (error, stack) {
      silentLog('services_module', '加载扫描服务设置', error, stack);
      preferences = AiExposurePreferences.defaults();
    }
    return ServicesModule._(
      controller: ServicesController(
        preferencesStore: store,
        initialPreferences: preferences,
      ),
    );
  }

  static List<SingleChildWidget> providers(
    ServicesModule module,
  ) => <SingleChildWidget>[
    ChangeNotifierProvider<ServicesController>.value(value: module.controller),
  ];
}

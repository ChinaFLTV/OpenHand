import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'data/ai_exposure_preferences_store.dart';
import 'services_controller.dart';

class ServicesModule {
  const ServicesModule._({required this.controller});

  final ServicesController controller;

  static Future<ServicesModule> bootstrap() async {
    final store = AiExposurePreferencesStore();
    final preferences = await store.load();
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

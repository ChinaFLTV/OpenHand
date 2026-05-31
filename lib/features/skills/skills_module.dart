import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'data/skills_repository.dart';
import 'skills_controller.dart';

/// Assembly point for the skills feature.
///
/// Construction is synchronous via [SkillsController.uninitialized].
/// `main.dart` currently bootstraps the module during app startup and then
/// schedules `controller.refresh()` in the background so the filesystem scan
/// stays off the first-frame critical path.
///
/// Unlike other Plan-2 modules, this bootstrap takes [initialStoragePath]
/// because the underlying controller's lazy-init factory has it as a
/// required dependency.
class SkillsModule {
  SkillsModule._({required this.controller});

  final SkillsController controller;

  static Future<SkillsModule> bootstrap({
    required String initialStoragePath,
    SkillsRepository? repository,
  }) async {
    final controller = SkillsController.uninitialized(
      initialStoragePath: initialStoragePath,
      repository: repository,
    );
    return SkillsModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(SkillsModule m) => [
    ChangeNotifierProvider<SkillsController>.value(value: m.controller),
  ];
}

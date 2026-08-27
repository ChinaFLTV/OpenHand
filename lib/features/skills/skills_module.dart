import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'data/skills_repository.dart';
import 'skills_controller.dart';

/// 模块构造保持轻量；`main.dart` 在后台刷新技能目录，避免文件扫描阻塞首帧。
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

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'knowledge_base_controller.dart';

class KnowledgeBaseModule {
  KnowledgeBaseModule._({required this.controller});

  final KnowledgeBaseController controller;

  static Future<KnowledgeBaseModule> bootstrap() async {
    return KnowledgeBaseModule._(controller: KnowledgeBaseController());
  }

  static List<SingleChildWidget> providers(KnowledgeBaseModule module) => [
    ChangeNotifierProvider<KnowledgeBaseController>.value(
      value: module.controller,
    ),
  ];
}

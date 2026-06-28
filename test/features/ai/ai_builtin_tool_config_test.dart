import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';

void main() {
  test('knowledge tools are enabled and force-loaded by default', () {
    final configs = {
      for (final config in AiBuiltinToolConfig.defaults()) config.kind: config,
    };
    for (final kind in <AiBuiltinToolKind>[
      AiBuiltinToolKind.knowledgeSearch,
      AiBuiltinToolKind.knowledgeRead,
    ]) {
      final config = configs[kind];
      expect(config, isNotNull);
      expect(config!.enabled, isTrue);
      expect(config.loadStrategy, AiBuiltinToolLoadStrategy.eager);
      expect(config.forceLoad, isTrue);
      expect(AiBuiltinToolConfig.defaultForceLoadForKind(kind), isTrue);
    }
  });
}

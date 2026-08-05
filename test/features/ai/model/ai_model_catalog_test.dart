import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_catalog.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';

void main() {
  group('AiModelCatalog.lookup', () {
    test('按最长模型 ID 后缀复用精确目录配置', () {
      final direct = AiModelCatalog.lookup(
        'openai/gpt-5.5',
        AiProtocolType.openai,
      );
      final routed = AiModelCatalog.lookup(
        'blackboxai/openai/gpt-5.5',
        AiProtocolType.openai,
      );

      expect(routed, isNotNull);
      expect(routed!.displayName, direct!.displayName);
      expect(routed.maxContextLength, direct.maxContextLength);
      expect(routed.maxOutputLength, direct.maxOutputLength);
      expect(routed.inputUsdPer1M, direct.inputUsdPer1M);
      expect(routed.canonicalSlug, direct.canonicalSlug);
    });

    test('后缀匹配忽略大小写并保留专用型号', () {
      final profile = AiModelCatalog.lookup(
        'BLACKBOXAI/OPENAI/GPT-5.5-PRO',
        AiProtocolType.openai,
      );

      expect(profile, isNotNull);
      expect(profile!.displayName, 'GPT-5.5 Pro');
      expect(profile.inputUsdPer1M, 30);
    });

    test('后缀匹配忽略空路径段', () {
      final profile = AiModelCatalog.lookup(
        '/blackboxai//openai/gpt-5.5/',
        AiProtocolType.openai,
      );

      expect(profile, isNotNull);
      expect(profile!.canonicalSlug, 'openai/gpt-5.5-20260423');
    });

    test('未知后缀不套用无关精确目录配置', () {
      final profile = AiModelCatalog.lookup(
        'blackboxai/openai/not-gpt-5.5',
        AiProtocolType.openai,
      );

      expect(profile, isNull);
    });
  });

  test('推理档位模板完整且默认值可选', () {
    expect(AiReasoningEffortPreset.all.map((preset) => preset.id), <String>{
      'gemini',
      'openai',
      'anthropic',
      'kimi',
      'qwen',
      'glm',
      'seed',
      'grok',
      'mistral',
    });
    for (final preset in AiReasoningEffortPreset.all) {
      expect(preset.options, isNotEmpty, reason: preset.id);
      expect(
        preset.options.any(
          (option) =>
              option.isSelectable && option.value == preset.defaultValue,
        ),
        isTrue,
        reason: preset.id,
      );
    }
  });
}

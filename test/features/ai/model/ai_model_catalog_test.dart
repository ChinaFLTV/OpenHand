import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_catalog.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/openrouter_latest_model_catalog.dart';

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

  group('最新模型目录', () {
    test('保留完整的 OpenRouter 在线增量快照', () {
      expect(openRouterLatestModelProfiles.length, greaterThanOrEqualTo(51));
      expect(
        openRouterLatestModelProfiles.keys,
        containsAll(<String>[
          'anthropic/claude-fable-5',
          'anthropic/claude-opus-5',
          'deepseek/deepseek-v4-flash-0731',
          'minimax/minimax-m3',
          'moonshotai/kimi-k3',
          'openai/gpt-5.6-sol',
          'qwen/qwen3.8-max',
          'x-ai/grok-4.5',
          'z-ai/glm-5.2',
        ]),
      );
    });

    test('网关后缀路由复用精确的新模型档案', () {
      final profile = AiModelCatalog.lookup(
        'blackboxai/x-ai/grok-4.5',
        AiProtocolType.openai,
      );

      expect(profile, isNotNull);
      expect(profile!.displayName, 'Grok 4.5');
      expect(profile.maxContextLength, 500000);
      expect(
        profile.reasoningEffortOptions.map((option) => option.value),
        <String>['low', 'medium', 'high', 'xhigh'],
      );
    });

    test('原生 GPT-5.6 档案使用官方限制与价格', () {
      final luna = AiModelCatalog.lookup('gpt-5.6-luna', AiProtocolType.openai);
      final terra = AiModelCatalog.lookup(
        'gpt-5.6-terra',
        AiProtocolType.openai,
      );
      final sol = AiModelCatalog.lookup('gpt-5.6', AiProtocolType.openai);

      expect(luna!.maxContextLength, 1050000);
      expect(luna.inputUsdPer1M, 0.2);
      expect(luna.outputUsdPer1M, 1.2);
      expect(terra!.inputUsdPer1M, 2);
      expect(terra.outputUsdPer1M, 12);
      expect(sol!.displayName, 'GPT-5.6 Sol');
      expect(sol.cacheReadUsdPer1M, 0.5);
    });

    test('厂商原生规则覆盖新一代文本与多模态型号', () {
      final cases = <(String, AiProtocolType, String, int, int)>[
        (
          'claude-opus-5',
          AiProtocolType.claude,
          'Claude Opus 5',
          1000000,
          128000,
        ),
        ('qwen3.8-max', AiProtocolType.qwen, 'Qwen3.8-Max', 1000000, 131072),
        ('glm-5.2', AiProtocolType.glm, 'GLM-5.2', 1000000, 128000),
        ('kimi-k3', AiProtocolType.kimi, 'Kimi K3', 1048576, 131072),
        (
          'deepseek-v4-flash-0731',
          AiProtocolType.deepseek,
          'DeepSeek V4 Flash 0731',
          1048576,
          65536,
        ),
      ];

      for (final modelCase in cases) {
        final profile = AiModelCatalog.lookup(modelCase.$1, modelCase.$2);
        expect(profile, isNotNull, reason: modelCase.$1);
        expect(profile!.displayName, modelCase.$3, reason: modelCase.$1);
        expect(profile.maxContextLength, modelCase.$4, reason: modelCase.$1);
        expect(profile.maxOutputLength, modelCase.$5, reason: modelCase.$1);
      }
    });

    test('Kimi K3 使用官方推理档位', () {
      final profile = AiModelCatalog.lookup('kimi-k3', AiProtocolType.kimi);

      expect(profile!.thinkingEnabled, isTrue);
      expect(profile.reasoningEffort, 'max');
      expect(
        profile.reasoningEffortOptions.map((option) => option.value),
        <String>['low', 'high', 'max'],
      );
    });

    test('MiniMax H3 识别为多模态视频生成模型', () {
      final profile = AiModelCatalog.lookup(
        'MiniMax-H3',
        AiProtocolType.minimax,
      );

      expect(profile, isNotNull);
      expect(profile!.displayName, 'MiniMax H3');
      expect(profile.capabilities, contains(AiModelCapability.videoGeneration));
      expect(
        profile.supportedModalities,
        containsAll(<AiModelModality>[
          AiModelModality.text,
          AiModelModality.image,
          AiModelModality.video,
          AiModelModality.audio,
        ]),
      );
      expect(
        profile.supportedModalities,
        isNot(contains(AiModelModality.file)),
      );
      expect(
        profile.supportedParameters,
        containsAll(<String>['content', 'ratio']),
      );
      expect(AiModelCatalog.lookup('h3', AiProtocolType.openai), isNull);
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

import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'model_metadata',
  source: _checks,
);

const _checks = '''
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/data/openrouter_model_profile_store.dart';
import 'package:openhand/features/ai/model/ai_model_catalog.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/openrouter_model_profile_mapper.dart';
import 'package:openhand/features/ai/model/openrouter_exact_model_catalog.dart';
import 'package:openhand/features/ai/model/openrouter_latest_model_catalog.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/model_registry/ai_title_model_resolver.dart';
import 'package:openhand/shared/db/database_service.dart';

AiModelConfig model(String id, {Map<String, AiModelProfile> profiles = const {}}) => AiModelConfig(
  id: '校验', baseUrl: 'https://example.invalid', authScheme: AiAuthScheme.bearer,
  token: '', modelId: id, protocolType: AiProtocolType.openai, modelProfiles: profiles,
);

void main() {
  final snapshot = Platform.environment['OPENHAND_MODEL_SNAPSHOT'];
  if (snapshot != null) {
    test('全部在线模型原始字段与核验快照逐项一致', () async {
      final payload = jsonDecode(await File(snapshot).readAsString()) as Map;
      for (final raw in payload['data'] as List) {
        final id = raw['id'] as String;
        final profile = openRouterLatestModelProfiles[id] ?? openRouterExactModelProfiles[id];
        expect(profile, isNotNull, reason: id);
        expect(profile!.sourceMetadata, raw, reason: id);
        expect(AiModelProfile.fromJson(profile.toJson()).sourceMetadata, raw, reason: id);
      }
    });
  }
  test('目录保留全部历史型号与新增型号，档案按需解析并复用', () {
    final ids = {...openRouterExactModelProfiles.keys, ...openRouterLatestModelProfiles.keys};
    expect(ids.length, greaterThanOrEqualTo(569));
    expect(ids, contains('cognitivecomputations/dolphin-mistral-24b-venice-edition:free'));
    for (final id in ['openai/gpt-6-luna', 'anthropic/claude-opus-5.5', 'x-ai/grok-4.7', 'deepseek/deepseek-v4.1-flash']) {
      expect(ids, contains(id));
      final profile = AiModelCatalog.lookup(id, AiProtocolType.openai)!;
      expect(profile.sourceMetadata['id'], id);
      expect(profile.maxThinkingLength, isNull);
    }
    final entries = <String, Object>{'model': <String, Object?>{'id': 'model'}};
    final profiles = OpenRouterModelProfiles(entries);
    entries['model'] = <String, Object?>{'id': 'model', 'name': '按需解析'};
    final first = profiles['model'];
    expect(first?.displayName, '按需解析');
    expect(identical(first, profiles['model']), isTrue);
    expect(profiles['missing'], isNull);
    expect(() => profiles.clear(), throwsUnsupportedError);
  });
  test('来源字段完整往返，未知上限与默认档位保持未配置', () {
    final raw = <String, Object?>{
      'id': 'provider/model',
      'architecture': {'input_modalities': ['text', 'image'], 'output_modalities': ['text']},
      'top_provider': {'max_completion_tokens': 8192, 'is_moderated': false},
      'pricing': {'prompt': '0.0000002', 'completion': '0.000001', 'request': '0.05', 'unknown_unit': '0.01'},
      'pricing_overrides': [{'threshold': 200000, 'multiplier': 2}],
      'reasoning': {'supported_efforts': ['low', 'high'], 'default_enabled': false},
      'future_metadata': {'unknown': ['preserved', 42]},
    };
    final profile = mapOpenRouterModel(raw)!;
    expect(profile.sourceMetadata, raw);
    expect(profile.inputUsdPer1M, 0.2);
    expect(mapOpenRouterModel({'id': 'small', 'pricing': {'prompt': '3e-9'}})?.inputUsdPer1M, 0.003);
    expect(mapOpenRouterModel({'id': 'overflow', 'pricing': {'prompt': '1e308'}})?.inputUsdPer1M, isNull);
    expect(profile.reasoningEffort, isNull);
    expect(profile.thinkingEnabled, isFalse);
    expect(profile.maxThinkingLength, isNull);
    expect(profile.maxContextLength, isNull);
    expect(profile.capabilities, isEmpty);
    final saved = AiModelProfile.fromJson(jsonDecode(jsonEncode(profile.toJson())));
    expect(saved.sourceMetadata, raw);
    expect(saved.copyWith(displayName: '自定义').sourceMetadata, raw);
    expect(model('provider/model', profiles: {'provider/model': saved}).profileFor('provider/model').sourceMetadata, raw);
    expect(mapOpenRouterModel({'id': 'unknown'})?.reasoningEffortControlEnabled, isFalse);
    expect(mapOpenRouterModel({'id': 'invalid', 'pricing': {'prompt': '-1', 'completion': 'NaN'}})?.inputUsdPer1M, isNull);
  });
  test('官方直连与网关规格分离，分时价格不伪装成固定美元价格', () {
    final native = AiModelCatalog.lookup('deepseek-flash', AiProtocolType.deepseek)!;
    expect((native.maxContextLength, native.maxOutputLength), (1048576, 393216));
    expect(native.supportedModalities, contains(AiModelModality.image));
    expect(native.maxThinkingLength, isNull);
    expect(native.inputUsdPer1M, isNull);
    expect(native.sourceMetadata['pricing_currency'], 'USD');
    expect(native.sourceMetadata['verified_at'], '2026-09-26');
    final gateway = AiModelCatalog.lookup('deepseek/deepseek-v4-flash', AiProtocolType.openai)!;
    expect(gateway.sourceMetadata['id'], 'deepseek/deepseek-v4-flash');
    expect(gateway.inputUsdPer1M, isNotNull);
    final sol = AiModelCatalog.lookup('openai/gpt-6-sol', AiProtocolType.openai)!;
    expect(sol.knowledgeCutoff, sol.sourceMetadata['knowledge_cutoff']);
  });
  test('新视觉与音频型号保留输入输出边界', () {
    final omni = AiModelCatalog.lookup('qwen3.8-omni-flash', AiProtocolType.qwen)!;
    expect(omni.supportedModalities, contains(AiModelModality.audio));
    expect(omni.capabilities, isNot(contains(AiModelCapability.audioGeneration)));
    for (final id in ['gemini-3.8-flash-tts', 'gemini-3.8-flash-lite-tts']) {
      final tts = AiModelCatalog.lookup(id, AiProtocolType.gemini)!;
      expect((tts.maxContextLength, tts.maxOutputLength), (8192, 16384));
      expect(tts.capabilities, contains(AiModelCapability.audioGeneration));
      expect(tts.thinkingEnabled, isFalse);
    }
    expect(AiModelCatalog.lookup('gemini-99-unknown', AiProtocolType.gemini), isNull);
    final step = AiModelCatalog.lookup('step-5-preview', AiProtocolType.stepfun)!;
    expect((step.maxContextLength, step.maxOutputLength), (1000000, 64000));
    expect(step.supportedModalities, contains(AiModelModality.video));
    expect(AiModelCatalog.lookup('doubao-seed-2-1-pro-260915', AiProtocolType.seed)?.maxContextLength, 1024000);
    expect(AiModelCatalog.lookup('hy4-preview', AiProtocolType.hunyuan)?.maxOutputLength, 64000);
  });
  test('可灵视频与文心参数保留原生单位，不推测词元价格', () {
    final kling = AiModelCatalog.lookup('kling-v3-omni', AiProtocolType.openai)!;
    expect(kling.capabilities, containsAll([AiModelCapability.videoGeneration, AiModelCapability.imageGeneration]));
    expect(kling.sourceMetadata['model_field'], 'model_name');
    expect(kling.supportedParameters, contains('multi_prompt'));
    expect(kling.maxContextLength, isNull);
    expect(kling.inputUsdPer1M, isNull);
    final ernie = AiModelCatalog.lookup('ernie-5.1', AiProtocolType.wenxin)!;
    expect((ernie.maxContextLength, ernie.maxOutputLength), (248832, 65536));
    expect(ernie.sourceMetadata['max_completions_tokens'], 126976);
    expect(ernie.sourceMetadata['pricing_currency'], 'CNY');
    expect(ernie.inputUsdPer1M, isNull);
    expect(ernie.supportedModalities, {AiModelModality.text});
  });
  test('MiniMax M3 区分推荐值、最大输出与聊天接口支持参数', () {
    final config = model('MiniMax-M3').copyWith(protocolType: AiProtocolType.minimax);
    final profile = config.profileFor(config.modelId);
    expect(profile.maxOutputLength, 524288);
    expect(profile.sourceMetadata['recommended_max_completion_tokens'], 131072);
    expect(profile.sourceMetadata['thinking_default_by_api'], {'chat_completions': true, 'messages': false});
    expect(config.resolvedReasoningEffortControlEnabled, isFalse);
    expect(profile.maxThinkingLength, isNull);
    expect(profile.inputUsdPer1M, isNull);
  });
  test('GLM 常开思考模型覆盖用户关闭值及不兼容推理档位', () {
    for (final id in ['glm-5.3', 'glm-5.3-flash', 'glm-5.3-flashx']) {
      final config = model(id, profiles: {id: const AiModelProfile(thinkingEnabled: false)}).copyWith(protocolType: AiProtocolType.glm);
      expect(config.resolvedThinkingEnabled, isTrue, reason: id);
      final body = <String, Object?>{'thinking': {'type': 'disabled', 'clear_thinking': false}, 'reasoning_effort': 'medium'};
      AiThinkingRequestPolicy.normalizeModelRequestBody(body, config);
      expect(body['thinking'], {'type': 'enabled', 'clear_thinking': false});
      expect(body['reasoning_effort'], 'max');
      if (id.contains('flash')) expect(config.profileFor(id).supportedModalities, contains(AiModelModality.image));
    }
  });
  test('模型档案初始化失败可重试，大小写更新不产生重复记录', () async {
    final store = OpenRouterModelProfileStore.instance;
    await expectLater(store.ensureLoaded(), throwsStateError);
    final directory = await Directory.systemTemp.createTemp('openhand_profiles_');
    final service = await DatabaseService.initialize(
      databasePath: '\${directory.path}/check.db', useNoIsolateFactory: true,
    );
    try {
      const oldProfile = AiModelProfile(displayName: '旧档案');
      const newProfile = AiModelProfile(displayName: '新档案');
      await service.database.insert('openrouter_model_profiles', {
        'model_id': 'Vendor/Model',
        'profile_json': jsonEncode(oldProfile.toJson()),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await service.database.insert('openrouter_model_profiles', {
        'model_id': 'vendor/model',
        'profile_json': jsonEncode(const AiModelProfile(displayName: '过期档案').toJson()),
        'updated_at': '2000-01-01T00:00:00.000Z',
      });
      final loading = store.ensureLoaded();
      expect(identical(loading, store.ensureLoaded()), isTrue);
      await loading;
      expect(AiModelCatalog.lookup('vendor/model', AiProtocolType.openai)?.displayName, '旧档案');
      await store.upsertBatch([const MapEntry('vendor/model', newProfile)]);
      await store.upsertBatch([const MapEntry('VENDOR/MODEL', newProfile)]);
      final rows = await service.database.query('openrouter_model_profiles');
      expect(rows, hasLength(1));
      expect(rows.single['model_id'], 'vendor/model');
      expect(AiModelCatalog.lookup('VENDOR/MODEL', AiProtocolType.openai)?.displayName, '新档案');
      await expectLater(store.upsertBatch([
        const MapEntry('vendor/model', oldProfile),
        const MapEntry('VENDOR/MODEL', oldProfile),
      ]), throwsFormatException);
      expect(await service.database.query('openrouter_model_profiles'), rows);
      expect(AiModelCatalog.lookup('vendor/model', AiProtocolType.openai)?.displayName, '新档案');
    } finally {
      AiModelCatalog.registerExternalProfiles({}, replace: true);
      await service.close();
      await directory.delete(recursive: true);
    }
  });
  test('未核实版本不继承旧版规格，已知点号版本和快照可识别', () {
    for (final id in ['claude-fable-5-2', 'claude-fable-5.2', 'anthropic/claude-opus-5.2', 'claude-fable-5-10', 'gpt-6-sol-2', 'gpt-6-luna-2']) {
      expect(AiModelCatalog.lookup(id, AiProtocolType.claude), isNull, reason: id);
      final config = model(id).copyWith(protocolType: AiProtocolType.claude);
      expect(config.resolvedSupportsThinking, isFalse, reason: id);
      expect(config.profileFor(id).reasoningEffortOptions, isEmpty, reason: id);
    }
    expect(AiModelCatalog.lookup('claude-fable-5.1', AiProtocolType.claude)?.cacheReadUsdPer1M, 0.25);
    expect(AiModelCatalog.lookup('claude-fable-5-1-20260831', AiProtocolType.claude)?.displayName, 'Claude Fable 5.1');
  });
  test('新模型的上下文、价格、知识截止日期和别名与官方规格一致', () {
    final sol = AiModelCatalog.lookup('gpt-6-sol', AiProtocolType.openai)!;
    final luna = AiModelCatalog.lookup('gpt-6-luna', AiProtocolType.openai)!;
    final opus = AiModelCatalog.lookup('anthropic.claude-opus-5-5', AiProtocolType.claude)!;
    expect((sol.maxContextLength, sol.maxOutputLength, sol.inputUsdPer1M, sol.outputUsdPer1M, sol.cacheReadUsdPer1M, sol.cacheWriteUsdPer1M, sol.knowledgeCutoff), (1050000, 128000, 2.0, 10.0, 0.2, 2.5, '2026-04-20'));
    expect((luna.maxContextLength, luna.maxOutputLength, luna.inputUsdPer1M, luna.outputUsdPer1M, luna.cacheReadUsdPer1M, luna.cacheWriteUsdPer1M, luna.knowledgeCutoff), (1050000, 128000, 0.1, 0.5, 0.01, 0.125, '2026-05-18'));
    expect((opus.maxContextLength, opus.maxOutputLength, opus.inputUsdPer1M, opus.outputUsdPer1M, opus.cacheReadUsdPer1M, opus.cacheWriteUsdPer1M, opus.knowledgeCutoff), (1000000, 128000, 4.0, 20.0, 0.2, 5.0, '2026-06'));
    expect(model('gpt-6-sol').resolvedReasoningEffortOptions.map((item) => item.value), ['none', 'low', 'medium', 'high', 'xhigh', 'max']);
    expect(model('gpt-6-luna').resolvedReasoningEffortOptions.map((item) => item.value), ['none', 'low', 'medium', 'high', 'xhigh', 'max']);
    expect(model('anthropic/claude-opus-5.5').usesAlwaysOnClaudeAdaptiveThinking, isTrue);
    expect(opus.reasoningEffort, 'medium');
  });
  test('带网关前缀的 Fable 仍保持官方常开思考约束', () {
    const id = 'anthropic/claude-fable-5.1';
    final config = model(id, profiles: {id: const AiModelProfile(thinkingEnabled: false)});
    expect(config.usesAlwaysOnClaudeAdaptiveThinking, isTrue);
    expect(config.resolvedThinkingEnabled, isTrue);
  });
  test('运行时精确资料仍优先于内置推断', () {
    AiModelCatalog.registerExternalProfiles({'claude-fable-5-2': const AiModelProfile(displayName: '提供商资料')});
    try {
      expect(AiModelCatalog.lookup('claude-fable-5-2', AiProtocolType.claude)?.displayName, '提供商资料');
    } finally {
      AiModelCatalog.registerExternalProfiles({}, replace: true);
    }
  });
  test('Astra 保留有效参数并清除已拒绝的旧参数', () {
    final body = <String, Object?>{'temperature': 0.5, 'top_p': 0.9, 'reasoning': {'effort': 'none', 'summary': 'auto'}, 'include': ['message.output_text.logprobs', 'reasoning.encrypted_content']};
    AiThinkingRequestPolicy.normalizeModelRequestBody(body, model('openai/gpt-6-astra'));
    expect(body.containsKey('temperature'), isFalse);
    expect(body.containsKey('top_p'), isFalse);
    expect(body['reasoning'], {'effort': 'low', 'summary': 'auto'});
    expect(body['include'], ['reasoning.encrypted_content']);
    final proBody = <String, Object?>{'temperature': 0.5};
    AiThinkingRequestPolicy.normalizeModelRequestBody(proBody, model('openai/gpt-6-astra-pro'));
    expect(proBody.containsKey('temperature'), isFalse);
  });
  test('Astra 官方工具调用不错误降级为 Chat Completions', () {
    final config = model('gpt-6-astra').copyWith(baseUrl: 'https://api.openai.com/v1');
    expect(() => AiThinkingRequestPolicy.normalizeModelRequestBody({'messages': [], 'tools': [{'type': 'function'}]}, config), throwsUnsupportedError);
    final body = <String, Object?>{'input': [], 'tools': [{'type': 'function'}]};
    AiThinkingRequestPolicy.normalizeModelRequestBody(body, config);
    expect(body['tools'], isNotEmpty);
  });
  test('Sol/Luna 的官方 Chat Completions 工具调用只允许 none 推理档位', () {
    for (final id in ['gpt-6-sol', 'gpt-6-luna']) {
      final config = model(id).copyWith(baseUrl: 'https://api.openai.com/v1');
      expect(() => AiThinkingRequestPolicy.normalizeModelRequestBody({'messages': [], 'tools': [{'type': 'function'}]}, config), throwsUnsupportedError);
      final body = <String, Object?>{'messages': [], 'tools': [{'type': 'function'}], 'reasoning_effort': 'none'};
      AiThinkingRequestPolicy.normalizeModelRequestBody(body, config);
      expect(body['reasoning_effort'], 'none');
    }
  });
  test('Fable 点号别名保留展示配置并修正强制工具调用', () {
    final body = <String, Object?>{'thinking': {'type': 'disabled', 'display': 'summarized', 'budget_tokens': 1024}, 'tool_choice': {'type': 'function', 'function': {'name': '工具'}}};
    AiThinkingRequestPolicy.normalizeModelRequestBody(body, model('anthropic/claude-fable-5.1'));
    expect(body['thinking'], {'type': 'adaptive', 'display': 'summarized'});
    expect(body['tool_choice'], 'auto');
  });
  test('Opus 5.5 禁用思考与强制工具调用会被修正', () {
    final body = <String, Object?>{'thinking': {'type': 'disabled', 'budget_tokens': 1024}, 'tool_choice': {'type': 'any'}};
    AiThinkingRequestPolicy.normalizeModelRequestBody(body, model('anthropic/claude-opus-5.5'));
    expect(body['thinking'], {'type': 'adaptive'});
    expect(body['tool_choice'], {'type': 'auto'});
  });
  test('Gemini 保留采样参数，修正不支持的推理预算和档位', () {
    for (final keys in [ ['generationConfig', 'thinkingConfig', 'thinkingLevel', 'thinkingBudget'], ['generation_config', 'thinking_config', 'thinking_level', 'thinking_budget'] ]) {
      final body = <String, Object?>{'temperature': 0.8, keys[0]: {'topP': 0.9, keys[1]: {keys[2]: 'minimal', keys[3]: 1024, 'includeThoughts': true}}};
      AiThinkingRequestPolicy.normalizeModelRequestBody(body, model('gemini-3.8-flash'));
      expect(body['temperature'], 0.8);
      final config = body[keys[0]] as Map;
      expect(config['topP'], 0.9);
      expect(config[keys[1]], {keys[2]: 'low', 'includeThoughts': true});
    }
  });
  test('Jev 区分输入与输出，不参与标题生成或聊天请求', () {
    for (final id in ['jev-latest', 'jev-preview', 'jev-1.13.0', 'typesafe/jev-1.13', '~typesafe/jev-latest']) {
      final config = model(id).copyWith(protocolType: AiProtocolType.jev);
      expect(AiTitleModelResolver.supportsTextTitleGeneration(config), isFalse);
      expect(config.resolvedSupportsThinking, isFalse);
      expect(() => AiThinkingRequestPolicy.normalizeModelRequestBody({}, config), throwsUnsupportedError);
    }
    expect(AiModelCatalog.lookup('jev-1.13.0', AiProtocolType.openai)?.maxContextLength, 64000);
    expect(AiModelCatalog.lookup('jev-latest', AiProtocolType.openai)?.maxContextLength, isNull);
    expect(AiModelCatalog.lookup('typesafe/jev-1.13', AiProtocolType.openai)?.maxContextLength, 32000);
  });
  test('Laya 检查点仅产生结构化决策，使用 Jev 兼容接口', () {
    for (final entry in <String, int>{'convaiinnovations/laya': 512, 'convaiinnovations/laya-multilingual': 1024, 'convaiinnovations/laya-typed-decisions': 1024}.entries) {
      final profile = AiModelCatalog.lookup(entry.key, AiProtocolType.jev)!;
      expect(profile.maxContextLength, entry.value);
      expect(profile.architecture?.outputModalities, ['decisions']);
      expect(profile.inputUsdPer1M, isNull);
      final config = model(entry.key).copyWith(protocolType: AiProtocolType.jev);
      expect(config.usesDecisionProtocol, isTrue);
      expect(AiTitleModelResolver.supportsTextTitleGeneration(config), isFalse);
    }
  });
  test('文本输入的非文本输出模型不能生成标题，普通文本模型不受影响', () {
    const id = '自定义';
    final config = model(id, profiles: {id: const AiModelProfile(supportedModalities: {AiModelModality.text}, architecture: AiModelArchitectureMetadata(modality: 'text->image', outputModalities: ['image']))});
    expect(AiTitleModelResolver.supportsTextTitleGeneration(config), isFalse);
    expect(AiTitleModelResolver.supportsTextTitleGeneration(model('gpt-6-astra')), isTrue);
    expect(AiTitleModelResolver.supportsTextTitleGeneration(model('text-embedding-3-small')), isFalse);
  });
}
''';

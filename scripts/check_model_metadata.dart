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
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/model_registry/ai_title_model_resolver.dart';
import 'package:openhand/shared/db/database_service.dart';

AiModelConfig model(String id, {Map<String, AiModelProfile> profiles = const {}}) => AiModelConfig(
  id: '校验', baseUrl: 'https://example.invalid', authScheme: AiAuthScheme.bearer,
  token: '', modelId: id, protocolType: AiProtocolType.openai, modelProfiles: profiles,
);

void main() {
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
    for (final id in ['claude-fable-5-2', 'claude-fable-5.2', 'anthropic/claude-opus-5.2', 'claude-fable-5-10']) {
      expect(AiModelCatalog.lookup(id, AiProtocolType.claude), isNull, reason: id);
      final config = model(id).copyWith(protocolType: AiProtocolType.claude);
      expect(config.resolvedSupportsThinking, isFalse, reason: id);
      expect(config.profileFor(id).reasoningEffortOptions, isEmpty, reason: id);
    }
    expect(AiModelCatalog.lookup('claude-fable-5.1', AiProtocolType.claude)?.cacheReadUsdPer1M, 0.25);
    expect(AiModelCatalog.lookup('claude-fable-5-1-20260831', AiProtocolType.claude)?.displayName, 'Claude Fable 5.1');
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
  test('Fable 点号别名保留展示配置并修正强制工具调用', () {
    final body = <String, Object?>{'thinking': {'type': 'disabled', 'display': 'summarized', 'budget_tokens': 1024}, 'tool_choice': {'type': 'function', 'function': {'name': '工具'}}};
    AiThinkingRequestPolicy.normalizeModelRequestBody(body, model('anthropic/claude-fable-5.1'));
    expect(body['thinking'], {'type': 'adaptive', 'display': 'summarized'});
    expect(body['tool_choice'], 'auto');
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
  test('文本输入的非文本输出模型不能生成标题，普通文本模型不受影响', () {
    const id = '自定义';
    final config = model(id, profiles: {id: const AiModelProfile(supportedModalities: {AiModelModality.text}, architecture: AiModelArchitectureMetadata(modality: 'text->image', outputModalities: ['image']))});
    expect(AiTitleModelResolver.supportsTextTitleGeneration(config), isFalse);
    expect(AiTitleModelResolver.supportsTextTitleGeneration(model('gpt-6-astra')), isTrue);
    expect(AiTitleModelResolver.supportsTextTitleGeneration(model('text-embedding-3-small')), isFalse);
  });
}
''';

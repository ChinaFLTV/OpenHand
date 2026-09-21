import 'dart:io';
import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'decisions',
  source: _checks,
);

const _checks = '''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_api_dialect.dart';
import 'package:openhand/features/ai/model/ai_operation_routing.dart';
import 'package:openhand/features/ai/service/model_registry/ai_title_model_resolver.dart';
import 'package:openhand/features/ai/service/media/ai_image_generation_service.dart';
import 'package:openhand/features/ai/model/ai_endpoint_override.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/operations/ai_decisions_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_endpoint_router.dart';
import 'package:openhand/features/ai/service/model_registry/ai_model_scanner.dart';
import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_usage_promotion_store.dart';
import 'package:openhand/features/ai/tools/ai_tool_registry.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';
import 'package:openhand/features/instructions/model/user_instruction_entry.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:openhand/shared/util/decision_payload.dart';
import 'package:openhand/shared/ui/decision_card.dart';

AiModelConfig config({String base = 'https://api.typesafe.ai/v1', String id = 'jev-latest'}) => AiModelConfig(id: '测试', baseUrl: base, authScheme: AiAuthScheme.bearer, token: '测试令牌', modelId: id, protocolType: AiProtocolType.jev);
const question = {'判断': {'type': 'noul', 'instructions': '成立吗？'}};
const response = {'model': 'jev-1.13.0', 'answers': {'判断': {'type': 'noul', 'noul': 0.8}}, 'usage': {'input_tokens': 12, 'output_tokens': 3}};
List<AiChatTurn> turns() => [const AiChatTurn(role: AiChatRole.system, content: '不得发送的系统提示词'), AiChatTurn(role: AiChatRole.user, content: DecisionPayload.encode(DecisionPayload.requestLanguage, {'state': '待判断内容', 'questions': question}))];
Widget app({required Widget home}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

AiSessionRuntimeContext decisionContext({bool enabled = true, int count = 1}) => AiSessionRuntimeContext(
  localeTag: 'zh', appVersion: '测试', appBuildNumber: '1',
  settingsFilePath: '', skillsStoragePath: '', mcpServersFilePath: '', userMemoryFilePath: '',
  compressionThresholdChars: 1, autoTitleEnabled: true,
  streamMaxCharsPerSecond: 1, streamMaxMessageCardsPerSecond: 1,
  memoryEnabled: enabled, memoryEntries: [for (var i = 0; i < count; i++) UserMemoryEntry(
    id: '记忆-\$i', type: i == 0 ? UserMemoryEntry.userProfileType : UserMemoryEntry.userType,
    createdAt: DateTime.utc(2026), content: '用户居住在杭州，偏好简洁回答。', tags: [],
  )],
  userInstructions: [UserInstructionEntry(id: '指令', name: '不应进入请求', body: '禁止进入决策的额外指令',
    createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026), sortOrder: 0)],
);
AiSession decisionSession(List<AiSessionMessage> messages) => AiSession(
  id: '决策回归', title: '决策回归', templateId: 'chat', templateName: '对话',
  templateIconName: 'chat', templateInternalVersion: '1',
  createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026),
  environment: AiSessionEnvironment.fromJson({}), statistics: const AiSessionStatistics.initial(),
  recentErrors: [], messages: messages,
);
class DecisionRuntime implements AiToolRuntimeService {
  @override
  final toolRegistry = AiToolRegistry.lightweightOnly();
  @override
  Future<AiResolvedToolCatalog> resolveCatalog({required AiSessionRuntimeContext runtimeContext, String? templateId}) async {
    throw StateError('决策不得解析工具目录');
  }
  @override
  Future<void> shutdown() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
class DecisionHooks extends AiNoopClaudeHookService {
  int calls = 0;
  @override
  Future<AiClaudeHookInvocationResult> runHooks({required String eventName, required String sessionId,
    required Map<String, Object?> payload, String? matcherValue, String? cwd}) async {
    calls++;
    return const AiClaudeHookInvocationResult(blocked: true, blockReason: '不应执行的钩子');
  }
}

void main() {
  test('决策标题精确截取十五个完整字符，保留标点和多语言', () {
    for (final entry in {
      '第一，请检查标点，不能被清理。后续内容': '第一，请检查标点，不能被清理。',
      'abc!?dé日本語中文。': 'abc!?dé日本語中文。',
      '👩‍💻' * 16: '👩‍💻' * 15,
      'e\\u0301' * 16: 'e\\u0301' * 15,
    }.entries) {
      expect(DecisionPayload.title(DecisionPayload.encode(DecisionPayload.requestLanguage,
        {'state': entry.key, 'questions': question})), entry.value);
    }
  });
  test('Jev 协议决定能力，任意模型名称及旧覆盖不能改写接口类型', () {
    for (final id in ['custom-router-v2', 'gpt-6-astra', 'claude-fable-5-1', 'text-embedding-3-small']) {
      final model = config(id: id).copyWith(modelProfiles: {id: const AiModelProfile(
        thinkingEnabled: true, reasoningEffortControlEnabled: true,
        requiresReasoningEcho: true, supportsAttachments: true, isMultimodal: true,
        capabilities: {AiModelCapability.imageGeneration}, isGlobalDefaultTitleModel: true,
        architecture: AiModelArchitectureMetadata(outputModalities: ['text', 'image']),
      )});
      final restored = AiModelConfig.fromJson(model.toJson());
      final profile = restored.profileFor(id);
      expect(restored.apiDialect, AiApiDialect.jevNative);
      expect(restored.usesDecisionProtocol, isTrue);
      expect(profile.capabilities, isEmpty);
      expect(profile.supportedModalities, {AiModelModality.text});
      expect(restored.resolvedSupportsThinking, isFalse);
      expect(restored.resolvedThinkingEnabled, isFalse);
      expect(restored.resolvedReasoningEffortControlEnabled, isFalse);
      expect(restored.requiresReasoningEcho, isFalse);
      expect(AiProtocolRegistry.supportsInlineImages(restored), isFalse);
      expect(AiProtocolRegistry.adapterForModel(restored).supportsToolCalls, isFalse);
      expect(AiProtocolRegistry.adapterForModel(restored).operationFamily, AiApiFamily.decisions);
      expect(AiImageGenerationService.supportsImageGenerationForModel(restored), isFalse);
      expect(AiTitleModelResolver.supportsTextTitleGeneration(restored), isFalse);
    }
    final chat = config().copyWith(protocolType: AiProtocolType.openai);
    expect(chat.usesDecisionProtocol, isFalse);
    expect(chat.apiDialect, AiApiDialect.openAiCompat);
    expect(AiModelConfig.fromJson(chat.toJson()).protocolType, AiProtocolType.openai);
    expect(config().copyWith(protocolType: AiProtocolType.claude).apiDialect, AiApiDialect.anthropicNative);
    final metadataOnly = chat.copyWith(modelId: 'custom', modelProfiles: {
      'custom': const AiModelProfile(architecture: AiModelArchitectureMetadata(outputModalities: ['decisions']))});
    expect(metadataOnly.usesDecisionProtocol, isFalse);
  });
  test('仅迁移旧纯决策配置，混合提供商和明确协议保持原样', () {
    final legacy = config().toJson()..remove('protocol_routing_version')..['protocol_type'] = 'openai'..['api_dialect'] = 'openai_compat';
    expect(AiModelConfig.fromJson(legacy).protocolType, AiProtocolType.jev);
    legacy['available_model_ids'] = ['jev-latest', 'gpt-4o-mini'];
    expect(AiModelConfig.fromJson(legacy).protocolType, AiProtocolType.openai);
    legacy['available_model_ids'] = ['jev-latest'];
    legacy['operation_routing'] = {'chat_model_id': 'gpt-4o-mini'};
    expect(AiModelConfig.fromJson(legacy).protocolType, AiProtocolType.openai);
    legacy.remove('operation_routing');
    legacy['protocol_type'] = 'claude';
    expect(AiModelConfig.fromJson(legacy).protocolType, AiProtocolType.claude);
  });
  test('决策请求不继承聊天路由和旧标题配置', () {
    final model = config(id: 'custom-router').copyWith(defaultTitleModelId: 'old-title',
      operationRouting: const AiOperationRouting(chatModelId: 'old-chat', embeddingModelId: 'old-embedding'));
    expect(model.resolveOperationModelId(AiApiFamily.decisions), 'custom-router');
    expect(model.allModelIds, ['custom-router']);
    expect(AiTitleModelResolver.normalizeProviderTitleDefaults(model).defaultTitleModelId, isEmpty);
  });
  test('自定义模型健康测试直接调用决策接口且保留请求方法', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/evaluate/custom-router');
      expect(request.url.queryParameters['tenant'], 'demo');
      final body = jsonDecode(request.body) as Map;
      expect(body.keys.toSet(), {'model', 'state', 'questions'});
      expect(body['model'], 'custom-router');
      final questions = body['questions'] as Map;
      return http.Response(jsonEncode({'answers': {
        for (final key in questions.keys) key: {'type': 'noul', 'noul': 1},
      }}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    addTearDown(client.close);
    final result = await service.testModel(config(id: 'custom-router').copyWith(
      requestMethod: 'PUT', operationRouting: const AiOperationRouting(chatModelId: 'wrong'),
      endpointOverrides: {AiApiFamily.decisions: const AiEndpointOverride(url: 'https://example.test/evaluate/{model_id}', queryDefaults: {'tenant': 'demo'})},
    ), responseTimeout: const Duration(seconds: 2));
    expect(result.chatApiFamily, AiApiFamily.decisions);
    expect(result.reply, contains('custom-router'));
    expect(result.reply, contains('openhand-decision'));
  });
  test('模型名称不能让 OpenAI 协议跳转决策接口', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/chat/completions');
      expect((jsonDecode(request.body) as Map)['messages'], isNotEmpty);
      return http.Response(jsonEncode({'choices': [{'message': {'content': '正常回复'}}]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    addTearDown(client.close);
    final result = await service.sendMessage(model: config().copyWith(protocolType: AiProtocolType.openai,
      capabilityOverrides: {AiApiFamily.responses: 'disabled'}), messages: turns());
    expect(result.reply, '正常回复');
  });
  test('决策只携带当前输入与自动记忆，不污染历史、问题或用户原文', () async {
    final bundle = await AiPromptTemplateRepository().loadBundle('chat');
    for (final enabled in [false, true]) {
      final runtime = decisionContext(enabled: enabled);
      for (final state in <Object>['用户住在哪里？', {'城市': '杭州'}, ['杭州', '上海']]) {
        final original = DecisionPayload.encode(DecisionPayload.requestLanguage, {'state': state, 'questions': question});
        final user = AiSessionMessage.user(id: '当前', content: original, createdAt: DateTime.utc(2026));
        final history = [AiSessionMessage.user(id: '旧消息', content: '不应进入请求的旧消息', createdAt: DateTime.utc(2025)), user];
        final built = await const AiPromptBuilder().buildSessionPrompt(templateBundle: bundle,
          session: decisionSession(history), model: config(), runtimeContext: runtime,
          memoryEntries: runtime.memoryEntries, sessionMessages: history, latestUserMessageId: user.id);
        expect(built.messages, hasLength(1));
        final payload = DecisionPayload.request(built.messages.single.content);
        expect(payload['questions'], question);
        expect(user.content, original);
        expect(built.systemMessageCount, 0);
        expect(built.historyMessageCount, 0);
        expect(built.messages.single.content, isNot(contains('禁止进入决策的额外指令')));
        expect(built.messages.single.content, isNot(contains('不应进入请求的旧消息')));
        expect(payload['state'], enabled ? isA<Map>() : state);
        if (enabled) {
          expect((payload['state'] as Map)['input'], state);
          expect((payload['state'] as Map)['user_memory'], contains('杭州'));
          expect(built.memoryResourceIds, {'记忆-0'});
        } else {
          expect(built.memoryResourceIds, isEmpty);
        }
      }
    }
  });
  test('决策记忆有条数和字符预算，接近请求上限时保留完整原文', () async {
    final bundle = await AiPromptTemplateRepository().loadBundle('chat');
    final runtime = decisionContext(count: 100);
    for (final state in ['待评估内容', '文' * (DecisionPayload.maxCharacters - 512)]) {
      final user = AiSessionMessage.user(id: '预算', content: DecisionPayload.encode(
        DecisionPayload.requestLanguage, {'state': state, 'questions': question}), createdAt: DateTime.utc(2026));
      final built = await const AiPromptBuilder().buildSessionPrompt(templateBundle: bundle,
        session: decisionSession([user]), model: config(), runtimeContext: runtime,
        memoryEntries: runtime.memoryEntries, sessionMessages: [user]);
      expect(built.memoryResourceIds.length, lessThanOrEqualTo(64));
      expect(built.promptCharacterCount, lessThanOrEqualTo(DecisionPayload.maxCharacters));
      final result = DecisionPayload.request(built.messages.single.content)['state'];
      expect(result is Map ? result['input'] : result, state);
    }
  });
  test('完整决策发送跳过钩子、工具和压缩，原文落库而记忆仅随请求发送', () async {
    final directory = await Directory.systemTemp.createTemp('openhand_decision_');
    final database = await DatabaseService.initialize(databasePath: '\${directory.path}/test.db');
    final store = AiSessionStore(sessionsDirectoryPath: directory.path);
    final hooks = DecisionHooks();
    final usage = AiToolUsagePromotionStore(filePath: '\${directory.path}/usage.json');
    final bodies = <Map<String, dynamic>>[];
    var mismatch = false;
    final client = AiChatService(client: MockClient((request) async {
      expect(request.url.path, endsWith('/v1/systemone'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bodies.add(body);
      final questions = body['questions'] as Map;
      return http.Response(jsonEncode({...response, 'answers': {
        for (final entry in questions.entries) entry.key: switch (mismatch ? 'noul' : entry.value['type']) {
          'choice' => {'type': 'choice', 'choice': '甲', 'probabilities': {'甲': .8, '乙': .2}},
          'score' => {'type': 'score', 'score': .4, 'probabilities': {'0': .6, '1': .4}},
          _ => {'type': 'noul', 'noul': .8},
        },
      }}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await store.save(decisionSession([]).copyWith(mode: AiSessionMode.plan));
    final controller = await AiSessionController.create(store: store, chatClient: client,
      hookService: hooks, toolRuntimeService: DecisionRuntime(), toolUsagePromotionStore: usage);
    addTearDown(() async {
      await controller.shutdown();
      await usage.shutdown();
      await database.close();
      await directory.delete(recursive: true);
    });
    final original = DecisionPayload.encode(DecisionPayload.requestLanguage, {'state': '用户住在杭州吗？', 'questions': question});
    expect(await controller.sendMessage(sessionId: '决策回归', content: original,
      model: config(), runtimeContext: decisionContext(),
      additionalSystemReminders: ['禁止携带的提醒'], selectedSkillMetadata: {'name': '禁止携带的技能'}), isTrue,
      reason: controller.lastErrorMessageForSession('决策回归'));
    expect(hooks.calls, 0);
    expect(bodies, hasLength(1));
    expect(bodies.single.keys.toSet(), {'model', 'state', 'questions'});
    expect((bodies.single['state'] as Map)['user_memory'], contains('杭州'));
    final saved = (await store.loadSession('决策回归'))!;
    expect(saved.mode, AiSessionMode.chat);
    expect(saved.title, DecisionPayload.title(original));
    expect(saved.autoTitleAcquired, true);
    final titleCalls = bodies.length;
    expect(await controller.generateTitleManually(sessionId: saved.id, content: '不应覆盖的摘要', model: config(), maxTitleCharacters: 30), saved.title);
    expect(bodies.length, titleCalls);
    expect(saved.messages.where((message) => message.kind == AiSessionMessageKind.user).single.content, original);
    expect(saved.messages.any((message) => message.kind == AiSessionMessageKind.hook), false);
    final mixedQuestions = {
      '选择': {'type': 'choice', 'instructions': '哪个候选项最符合？', 'criteria': {'甲': null, '乙': null}},
      '评分': {'type': 'score', 'instructions': '评分', 'criteria': ['低', '高']},
      ...question,
    };
    final inputs = [original];
    for (final enabled in [false, true]) {
      for (final questions in [for (final entry in mixedQuestions.entries) {entry.key: entry.value}, mixedQuestions]) {
        final state = '第 \${inputs.length} 轮待评估内容';
        final content = DecisionPayload.encode(DecisionPayload.requestLanguage, {'state': state, 'questions': questions});
        inputs.add(content);
        expect(await controller.sendMessage(sessionId: saved.id, content: content, model: config(),
          runtimeContext: decisionContext(enabled: enabled), additionalSystemReminders: ['禁止携带的运行时提醒']), isTrue,
          reason: controller.lastErrorMessageForSession(saved.id));
        expect(bodies.last['questions'], questions);
        expect(enabled ? (bodies.last['state'] as Map)['input'] : bodies.last['state'], state);
        expect(jsonEncode(bodies.last), isNot(contains('openhand_runtime_context')));
        final stored = (await store.loadSession(saved.id))!;
        expect(stored.title, saved.title);
        expect(stored.messages.where((message) => message.kind == AiSessionMessageKind.user).map((message) => message.content), inputs);
        final answers = stored.messages.where((message) => message.kind == AiSessionMessageKind.assistant).toList();
        expect(answers, hasLength(inputs.length));
        final result = DecisionPayload.tryResult(answers.last.content.split('\\n')[1])!;
        expect(result['questions'], questions);
        for (final entry in questions.entries) {
          expect(((result['answers'] as Map)[entry.key] as Map)['type'], entry.value['type']);
        }
      }
    }
    expect(hooks.calls, 0);
    mismatch = true;
    final beforeFailure = bodies.length;
    expect(await controller.sendMessage(sessionId: saved.id, content: DecisionPayload.encode(
      DecisionPayload.requestLanguage, {'state': '不能变成判断的选择题', 'questions': {'选择': mixedQuestions['选择']}}),
      model: config(), runtimeContext: decisionContext()), false);
    expect(bodies.length, beforeFailure + 1);
    final failed = (await store.loadSession(saved.id))!;
    expect(failed.messages.where((message) => message.kind == AiSessionMessageKind.assistant), hasLength(inputs.length));
    expect(controller.lastErrorMessageForSession(saved.id), isNotEmpty);
    final count = bodies.length;
    expect(await controller.sendMessage(sessionId: saved.id, content: original, model: config(),
      runtimeContext: decisionContext(), attachmentFilePaths: ['不支持的附件.txt']), false);
    expect(bodies.length, count);
  });
  test('决策标题在重新打开、分页、切换模型和手动改名后不请求模型', () async {
    final directory = await Directory.systemTemp.createTemp('openhand_decision_title_');
    final database = await DatabaseService.initialize(databasePath: '\${directory.path}/test.db');
    final store = AiSessionStore(sessionsDirectoryPath: directory.path);
    final original = DecisionPayload.encode(DecisionPayload.requestLanguage, {
      'state': '首条决策标题保留完整字符和标点！后续不覆盖', 'questions': question,
    });
    final first = AiSessionMessage.user(id: '首条', content: original, createdAt: DateTime.utc(2026));
    final title = DecisionPayload.title(original);
    await store.save(decisionSession([
      first,
      for (var i = 0; i < 160; i++) AiSessionMessage.user(
        id: '后续-\$i', content: '后续普通消息', createdAt: DateTime.utc(2026, 1, 2)),
    ]).copyWith(title: title, autoTitleAcquired: true, autoTitleSourceMessageId: first.id));
    var requests = 0;
    final client = AiChatService(client: MockClient((request) async {
      requests++;
      throw StateError('决策会话不得调用标题模型');
    }));
    final controller = await AiSessionController.create(store: store, chatClient: client);
    addTearDown(() async {
      await controller.shutdown();
      await database.close();
      await directory.delete(recursive: true);
    });
    const id = '决策回归';
    await controller.selectSession(id);
    await controller.ensureSessionMessageWindowHydrated(id);
    expect(controller.sessionById(id)!.hasMoreHistoricalMessages, true);
    expect(await controller.updateSessionLastUsedModel(id, providerConfigId: '普通提供商', modelId: '普通模型'), true);
    final plainModel = config().copyWith(protocolType: AiProtocolType.openai);
    expect(await controller.generateTitleManually(sessionId: id, content: '错误摘要', model: plainModel, maxTitleCharacters: 30), title);
    expect(await controller.renameSession(id, '我手动选择的标题'), true);
    expect(await controller.generateTitleManually(sessionId: id, content: original, model: plainModel, maxTitleCharacters: 30), '我手动选择的标题');
    expect((await store.loadSession(id))!.title, '我手动选择的标题');
    expect(requests, 0);
  });
  test('换行、缩进和长围栏不改变决策类型，未闭合配置拒绝发送', () {
    for (final type in DecisionPayload.types) {
      final request = {'state': '内容包含 ``` 和 ~~~', 'questions': {'决策': {
        'type': type, 'instructions': '评估',
        if (type == 'choice') 'criteria': {'甲': null, '乙': null},
        if (type == 'score') 'criteria': ['低', '高'],
      }}};
      for (final fence in ['```', '````', '~~~', '~~~~']) {
        for (final newline in ['\\n', '\\r\\n']) {
          final text = '  \${fence}openhand-decision-request \\t\$newline\${jsonEncode(request)}\$newline  \$fence';
          expect(DecisionPayload.containsRequest(text), true);
          expect(DecisionPayload.request(text), request);
          expect(() => DecisionPayload.request(text.substring(0, text.length - fence.length)), throwsFormatException);
        }
      }
    }
  });
  test('错误类型、缺失和多余答案均失败且保留原始响应用于诊断', () async {
    for (final type in DecisionPayload.types) {
      final questions = {'决策': {'type': type, 'instructions': '评估',
        if (type == 'choice') 'criteria': {'甲': null, '乙': null},
        if (type == 'score') 'criteria': ['低', '高'],
      }};
      final valid = switch (type) {
        'choice' => {'type': type, 'choice': '甲', 'probabilities': {'甲': .8, '乙': .2}},
        'score' => {'type': type, 'score': .4, 'probabilities': {'0': .6, '1': .4}},
        _ => {'type': type, 'noul': .8},
      };
      for (final answers in [
        {'决策': {...valid, 'type': type == 'noul' ? 'choice' : 'noul'}},
        {'旧问题': valid},
        {'决策': valid, '旧问题': valid},
      ]) {
        var calls = 0;
        final raw = jsonEncode({'answers': answers});
        final client = MockClient((_) async { calls++; return http.Response(raw, 200,
          headers: {'content-type': 'application/json; charset=utf-8'}); });
        addTearDown(client.close);
        await expectLater(AiDecisionsService(client).evaluate(model: config(), messages: [AiChatTurn(
          role: AiChatRole.user, content: DecisionPayload.encode(DecisionPayload.requestLanguage,
          {'state': '当前内容', 'questions': questions}))], timeout: const Duration(seconds: 1)),
          throwsA(isA<AiChatException>()
            .having((error) => error.telemetry?.rawResponse, '原始响应', raw)
            .having((error) => error.telemetry?.requestBody?['questions'], '原始问题', questions)));
        expect(calls, 1);
      }
    }
  });
  test('三类默认问题按类型更新，自定义问题保留', () {
    expect(DecisionPayload.builtInQuestionTexts.length, greaterThanOrEqualTo(9));
    for (final type in DecisionPayload.types) {
      final expected = DecisionPayload.defaultQuestionForType(type);
      for (final current in ['', '  ', ...DecisionPayload.builtInQuestionTexts]) {
        expect(DecisionPayload.questionForType(type, current: current), expected);
      }
      expect(DecisionPayload.questionForType(type, current: '  该请求是否需要人工处理？  '), '  该请求是否需要人工处理？  ');
    }
  });
  test('原生、网关与完整接口地址正确归一化', () {
    const router = AiEndpointRouter();
    for (final base in ['https://api.typesafe.ai', 'https://api.typesafe.ai/v1', 'https://api.typesafe.ai/v1/systemone']) {
      expect(router.resolve(config(base: base), AiApiFamily.decisions).url, 'https://api.typesafe.ai/v1/systemone');
    }
    for (final base in ['https://openrouter.ai', 'https://openrouter.ai/api', 'https://openrouter.ai/api/v1', 'https://openrouter.ai/api/alpha/decisions']) {
      expect(router.resolve(config(base: base, id: 'typesafe/jev-1.13'), AiApiFamily.decisions).url, 'https://openrouter.ai/api/alpha/decisions');
    }
    expect(router.resolve(config(base: 'https://custom.test/prefix').copyWith(autoCompleteBaseUrl: false), AiApiFamily.decisions).url, 'https://custom.test/prefix/systemone');
    final custom = config().copyWith(endpointOverrides: {AiApiFamily.decisions: const AiEndpointOverride(url: 'https://relay.example/evaluate')});
    expect(router.resolve(custom, AiApiFamily.decisions).url, 'https://relay.example/evaluate');
  });
  test('请求不发送聊天字段，答案保留结构和用量', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/v1/systemone');
      expect(jsonDecode(request.body), {'model': 'jev-latest', 'state': '待判断内容', 'questions': question});
      expect(request.headers['authorization'], 'Bearer 测试令牌');
      return http.Response(jsonEncode(response), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    addTearDown(client.close);
    final result = await service.sendMessage(model: config(), messages: turns());
    expect(result.reply, contains('openhand-decision'));
    expect(result.reply, contains('0.8'));
    expect(result.usage, isNotNull);
    expect(calls, 1);
  });
  test('决策流只发送完整结果，错误不回退到聊天接口', () async {
    var status = 200;
    var calls = 0;
    final client = MockClient((request) async { calls++; return http.Response(jsonEncode(status == 200 ? response : {'error': '拒绝访问'}), status, headers: {'content-type': 'application/json; charset=utf-8'}); });
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    addTearDown(client.close);
    final stream = await service.sendMessageStream(model: config(), messages: turns());
    final events = await stream.events.toList();
    expect(events.where((event) => event.type == AiChatStreamEventType.textDelta).length, 1);
    expect((await stream.result).reply, contains('openhand-decision'));
    status = 429;
    await expectLater(service.sendMessage(model: config(), messages: turns()), throwsA(isA<AiChatException>()));
    expect(calls, 2);
  });
  test('TypeSafe 模型目录解析 name 字段', () async {
    final client = MockClient((_) async => http.Response('{"models":[{"name":"jev-latest"},{"name":"jev-preview"}]}', 200));
    final scanner = AiModelScanner(httpClient: client);
    addTearDown(scanner.dispose);
    addTearDown(client.close);
    expect((await scanner.scan(config())).modelIds, ['jev-latest', 'jev-preview']);
  });
  test('选择与评分保留概率分布，无效结果不能伪装成功', () {
    final questions = {'分类': {'type': 'choice', 'instructions': '归类', 'criteria': {'甲': null, '乙': null}}, '评分': {'type': 'score', 'instructions': '评分', 'criteria': ['低', '高']}};
    final result = DecisionPayload.result({'answers': {'分类': {'type': 'choice', 'choice': '甲', 'probabilities': {'甲': .8, '乙': .2}, 'confidence': .7}, '评分': {'type': 'score', 'score': .4, 'legend': {'0': '低', '1': '高'}, 'probabilities': {'0': .6, '1': .4}, 'confidence': .2}}}, questions);
    expect(result['answers'], isNotEmpty);
    expect(() => DecisionPayload.result({'answers': {'判断': {'type': 'noul', 'noul': 2}}}, question), throwsFormatException);
    expect(() => DecisionPayload.result({'answers': {}}, question), throwsFormatException);
    expect(() => DecisionPayload.request('{"state":"内容","questions":{"问题":{"type":"score","instructions":"评分","criteria":["低"]}}}'), throwsFormatException);
  });
  test('取消等待立即释放结果，迟到响应不再产生输出', () async {
    final pending = Completer<http.Response>();
    final client = MockClient((_) => pending.future);
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    addTearDown(client.close);
    final stream = await service.sendMessageStream(model: config(), messages: turns());
    final events = stream.events.toList();
    await stream.cancel!();
    expect((await stream.result.timeout(const Duration(seconds: 2))).wasCancelled, isTrue);
    pending.complete(http.Response(jsonEncode(response), 200, headers: {'content-type': 'application/json; charset=utf-8'}));
    expect(await events, isEmpty);
  });
  test('文本分段可作为决策输入', () async {
    final client = MockClient((request) async {
      expect((jsonDecode(request.body) as Map)['state'], '分段文本');
      return http.Response(jsonEncode(response), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    addTearDown(client.close);
    final result = await AiDecisionsService(client).evaluate(model: config(), messages: [const AiChatTurn(role: AiChatRole.user, content: '', parts: [AiChatContentPart.text('分段文本')])], timeout: const Duration(seconds: 1));
    expect(result.reply, contains('openhand-decision'));
  });
  test('超时终止等待且不重复请求', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final client = MockClient((_) { calls++; return pending.future; });
    addTearDown(client.close);
    await expectLater(AiDecisionsService(client).evaluate(model: config(), messages: turns(), timeout: const Duration(milliseconds: 20)), throwsA(isA<TimeoutException>()));
    expect(calls, 1);
    pending.complete(http.Response('{}', 200));
  });
  test('复杂决策配置往返不丢失批量问题与描述', () {
    final request = {'state': {'内容': '批量'}, 'questions': {'分类': {'type': 'choice', 'instructions': '分类', 'criteria': {'甲': '详细标准', '乙': null}}, '判断': {'type': 'noul', 'instructions': '成立吗？'}}};
    final encoded = DecisionPayload.encode(DecisionPayload.requestLanguage, request);
    expect(DecisionPayload.request(encoded), request);
  });
  testWidgets('决策请求与结果卡片窄屏无溢出', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(app(home: Scaffold(body: RepaintBoundary(key: key, child: ListView(children: [
      OpenHandDecisionCard(data: DecisionPayload.result(Map<String,Object?>.from(response), question)),
      OpenHandDecisionRequestCard(data: DecisionPayload.request(DecisionPayload.encode(DecisionPayload.requestLanguage, {'state': '一加一等于二', 'questions': question}))),
    ])))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('决策结果'), findsNothing);
    expect(find.text('决策请求'), findsNothing);
    expect(find.text('按问题查看答案与概率分布'), findsNothing);
    expect(find.text('结构化决策'), findsNothing);
    expect(find.text('判断'), findsWidgets);
    expect(find.text('成立吗？'), findsWidgets);
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/openhand-jev-card.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
  test('会话正文围栏与裸 JSON 都能解析决策结果', () {
    final payload = <String, Object?>{
      'questions': question,
      'answers': <String, Object?>{'判断': <String, Object?>{'type': 'noul', 'noul': 0.8}},
    };
    expect(DecisionPayload.tryResult(jsonEncode(payload)), isNotNull);
    expect(DecisionPayload.tryResultMessage(DecisionPayload.encode(DecisionPayload.resultLanguage, payload)), isNotNull);
    expect(DecisionPayload.tryResultMessage(DecisionPayload.encode(DecisionPayload.requestLanguage, {'state': '待判断内容', 'questions': question})), isNull);
  });
  testWidgets('决策结果卡片只展示概率条，提问与置信度不重复出现', (tester) async {
    await tester.pumpWidget(app(home: Scaffold(body: OpenHandDecisionCard(data: <String, Object?>{
      'questions': <String, Object?>{
        'choice': <String, Object?>{
          'type': 'choice',
          'instructions': DecisionPayload.questionChoiceEn,
          'criteria': <String, Object?>{'甲': null, '乙': null},
        },
      },
      'answers': <String, Object?>{
        'choice': <String, Object?>{
          'type': 'choice',
          'choice': '甲',
          'probabilities': <String, Object?>{'甲': 0.9, '乙': 0.1},
          'confidence': 0.99,
        },
      },
    }))));
    await tester.pumpAndSettle();
    expect(find.text('选择'), findsNothing);
    expect(find.text(DecisionPayload.questionChoiceZh), findsNothing);
    expect(find.text(DecisionPayload.questionChoiceEn), findsNothing);
    expect(find.text('Choice'), findsNothing);
    expect(find.text('Confidence'), findsNothing);
    expect(find.text('置信度 99.0%'), findsNothing);
    expect(find.text('甲'), findsOneWidget);
    expect(find.text('90.0%'), findsOneWidget);
  });
}
''';

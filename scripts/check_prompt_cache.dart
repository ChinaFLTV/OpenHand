import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'prompt_cache',
  source: _checks,
);

const _checks = r'''
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/operations/ai_responses_service.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_sections.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

final instant = DateTime.utc(2026);
final model = AiModelConfig(id: '测试', baseUrl: 'https://example.com/v1',
  authScheme: AiAuthScheme.bearer, token: '测试', modelId: 'test-model', protocolType: AiProtocolType.openai);
AiSessionRuntimeContext context({String project = '项目规则'}) => AiSessionRuntimeContext(
  localeTag: 'zh', appVersion: '测试', appBuildNumber: '1',
  settingsFilePath: '', skillsStoragePath: '', mcpServersFilePath: '', userMemoryFilePath: '',
  compressionThresholdChars: 100000, autoTitleEnabled: false,
  streamMaxCharsPerSecond: 1, streamMaxMessageCardsPerSecond: 1,
  memoryEnabled: false, memoryEntries: [], workspaceInstructionDocuments: [
    AiWorkspaceInstructionDocument(path: '/项目/AGENTS.md', name: 'AGENTS.md', content: project),
  ],
);
AiSession session(AiPromptTemplateBundle bundle, List<AiSessionMessage> messages) => AiSession(
  id: '缓存回归', title: '缓存回归', templateId: bundle.template.id, templateName: bundle.template.name,
  templateIconName: bundle.template.iconName, templateInternalVersion: bundle.template.internalVersion,
  createdAt: instant, updatedAt: instant, environment: AiSessionEnvironment.fromJson({}),
  statistics: const AiSessionStatistics.initial(), recentErrors: [], messages: messages,
);
AiSessionMessage user(String id, String content, {Map<String, Object?> metadata = const {}}) =>
  AiSessionMessage.user(id: id, content: content, createdAt: instant, metadata: metadata);
const tools = [
  AiToolDefinition(name: 'Write', description: '写文件', parameters: {
    'type': 'object', 'properties': {'path': {'type': 'string'}, 'content': {'type': 'string'}},
    'required': ['path', 'content'],
  }),
  AiToolDefinition(name: 'Read', description: '读文件', parameters: {
    'properties': {'path': {'type': 'string'}}, 'required': ['path'],
  }),
  AiToolDefinition(name: 'skill__test', description: '测试技能', parameters: {}),
  AiToolDefinition(name: 'mcp__test', description: '测试工具', parameters: {}),
];
Future<AiPromptBuildResult> build(AiPromptTemplateBundle bundle, List<AiSessionMessage> messages,
  {List<AiToolDefinition> catalog = tools, String project = '项目规则', bool dsml = false, String? anchor}) =>
  const AiPromptBuilder().buildSessionPrompt(templateBundle: bundle, session: session(bundle, messages),
    model: model, runtimeContext: context(project: project), memoryEntries: [], sessionMessages: messages,
    latestUserMessageId: messages.lastWhere((m) => m.kind == AiSessionMessageKind.user).id,
    runtimeContextAnchorMessageId: anchor, availableTools: catalog, useDsmlToolCalls: dsml);
List<Object?> content(List<AiChatTurn> turns) => [for (final turn in turns) {
  'role': turn.role.name, 'content': turn.content, 'tool_calls': [for (final call in turn.toolCalls) {'id': call.id, 'name': call.name, 'arguments': call.arguments}],
  'tool_call_id': turn.toolCallId,
}];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = AiPromptTemplateRepository(loader: (path) => File(path).readAsString());
  for (final entry in AiPromptTemplatePolicies.entries) {
    test('${entry.id}：提问内容不改变内置装配，工具换序不改变前缀', () async {
      final bundle = await repository.loadBundle(entry.id);
      final first = await build(bundle, [user('首轮', '阅读项目')]);
      for (final question in ['直接回答', '修改代码并验证', '你好', '研究缓存问题']) {
        final next = await build(bundle, [user('首轮', question)], catalog: tools.reversed.toList());
        expect(content(next.messages.where((t) => t.role == AiChatRole.system).toList()),
          content(first.messages.where((t) => t.role == AiChatRole.system).toList()));
        expect(next.metadata['stable_prefix_hash'], first.metadata['stable_prefix_hash']);
        expect(next.metadata['tool_catalog_hash'], first.metadata['tool_catalog_hash']);
      }
      final changed = await build(bundle, [user('首轮', '阅读项目')], project: '更新后的项目规则');
      expect(content(changed.messages.take(2).toList()), content(first.messages.take(2).toList()));
      expect(first.messages[0].content, isNot(contains('项目规则')));
      expect(first.messages.firstWhere((t) => t.content.startsWith(AiPromptSectionHeaders.toolCatalog)).content,
        isNot(contains('写文件')));
      expect(changed.messages[2].content, contains('更新后的项目规则'));
      expect(changed.messages[2].content, startsWith(AiPromptSectionHeaders.workspaceInstructions));
      expect(changed.metadata['stable_prefix_hash'], isNot(first.metadata['stable_prefix_hash']));
    });
    test('${entry.id}：工具续写与下一轮原位重放已发送输入', () async {
      final bundle = await repository.loadBundle(entry.id);
      final first = await build(bundle, [user('首轮', '阅读项目')], anchor: '首轮');
      final persisted = user('首轮', '阅读项目', metadata: {
        aiPromptRuntimeTailSnapshotMetadataKey: first.metadata[aiPromptRuntimeTailSnapshotMetadataKey],
      });
      final exchange = [persisted,
        AiSessionMessage.toolCall(id: '调用', content: '', createdAt: instant, metadata: {
          'tool_call_id': 'read-1', 'tool_name': 'Read', 'tool_arguments': '{"path":"README.md"}',
          'tool_calls': [{'id': 'read-1', 'name': 'Read', 'arguments': '{"path":"README.md"}'}],
        }),
        AiSessionMessage.toolResult(id: '结果', content: '项目说明', createdAt: instant, metadata: {
          'tool_call_id': 'read-1', 'tool_name': 'Read',
        }),
      ];
      final continuation = await build(bundle, exchange, anchor: '结果');
      expect(content(continuation.messages.take(first.messages.length).toList()), content(first.messages));
      final anchoredExchange = [...exchange.take(2), exchange.last.copyWith(metadata: {
        ...exchange.last.metadata,
        aiPromptRuntimeTailSnapshotMetadataKey: continuation.metadata[aiPromptRuntimeTailSnapshotMetadataKey],
      })];
      final next = await build(bundle, [...anchoredExchange,
        AiSessionMessage.assistant(id: '回复', content: '项目结构已确认', createdAt: instant),
        user('下一轮', '继续检查'),
      ], anchor: '下一轮');
      expect(content(next.messages.take(continuation.messages.length).toList()), content(continuation.messages));
      for (final adapter in <AiProtocolAdapter>[
        const OpenAiProtocolAdapter(AiProtocolType.openai), const ClaudeProtocolAdapter(), const GeminiProtocolAdapter(),
      ]) {
        final config = model.copyWith(protocolType: adapter.protocolType);
        final before = await adapter.buildBody(config, first.messages, tools: tools);
        final after = await adapter.buildBody(config, continuation.messages, tools: tools);
        final key = adapter.protocolType == AiProtocolType.gemini ? 'contents' : 'messages';
        final previous = before[key] as List;
        expect((after[key] as List).take(previous.length).toList(), previous);
        expect(after['system'], before['system']);
        expect(after['systemInstruction'], before['systemInstruction']);
        expect(after['tools'], before['tools']);
      }
      final responses = AiResponsesService();
      addTearDown(responses.dispose);
      final before = await responses.buildChatRequest(model: model, messages: first.messages, tools: tools);
      final after = await responses.buildChatRequest(model: model, messages: continuation.messages, tools: tools);
      final previous = before.body['input'] as List;
      expect((after.body['input'] as List).take(previous.length).toList(), previous);

    });
    test('${entry.id}：空目录与 DSML 使用统一目录结构', () async {
      final bundle = await repository.loadBundle(entry.id);
      final empty = await build(bundle, [user('首轮', '检查')], catalog: []);
      expect(empty.messages.firstWhere((t) => t.content.startsWith(AiPromptSectionHeaders.toolCatalog)).content,
        contains('No runtime tools'));
      final dsml = await build(bundle, [user('首轮', '检查')], dsml: true);
      final catalog = dsml.messages.firstWhere((t) => t.content.startsWith(AiPromptSectionHeaders.toolCatalog)).content;
      for (final marker in ['## Skills', '## MCP', '## Builtin', 'DSML:function_calls', 'Args:']) {
        expect(catalog, contains(marker));
      }
    });
  }
  test('所有原生协议：工具换序与等价参数排列不改变请求字节', () async {
    final messages = [const AiChatTurn(role: AiChatRole.user, content: '检查')];
    final reversed = tools.reversed.toList();
    final originalOrder = tools.map((t) => t.name).toList();
    for (final adapter in <AiProtocolAdapter>[
      const OpenAiProtocolAdapter(AiProtocolType.openai), const ClaudeProtocolAdapter(), const GeminiProtocolAdapter(),
    ]) {
      final config = model.copyWith(protocolType: adapter.protocolType);
      final before = await adapter.buildBody(config, messages, tools: tools);
      final after = await adapter.buildBody(config, messages, tools: reversed);
      expect(jsonEncode(after), jsonEncode(before));
    }
    final responses = AiResponsesService();
    addTearDown(responses.dispose);
    final before = await responses.buildChatRequest(model: model, messages: messages, tools: tools);
    final after = await responses.buildChatRequest(model: model, messages: messages, tools: reversed);
    expect(jsonEncode(after.body), jsonEncode(before.body));
    expect(tools.map((t) => t.name), originalOrder);
    final equivalent = AiToolDefinition(name: 'Write', description: '写文件', parameters: {
      'required': ['content', 'path'], 'properties': {'content': {'type': 'string'}, 'path': {'type': 'string'}}, 'type': 'object',
    });
    final bundle = await repository.loadBundle('default');
    final a = await build(bundle, [user('首轮', '检查')], catalog: [tools.first]);
    final b = await build(bundle, [user('首轮', '检查')], catalog: [equivalent]);
    expect(a.metadata['tool_catalog_hash'], b.metadata['tool_catalog_hash']);
    final strict = await build(bundle, [user('首轮', '检查')], catalog: [AiToolDefinition(
      name: equivalent.name, description: equivalent.description, parameters: equivalent.parameters, strict: true,
    )]);
    expect(a.metadata['tool_catalog_hash'], isNot(strict.metadata['tool_catalog_hash']));
  });
}
''';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';

const _cacheConfig = AiInputCacheRuntimeConfig(
  enabled: true,
  mode: 'allMessages',
  updateInterval: 10,
  breakpointCount: 4,
  cacheAffinityId: 'session-1',
  promptCacheKey: 'cache-key-1',
);

AiModelConfig _openAiModel(String modelId) => AiModelConfig(
  id: modelId,
  baseUrl: 'https://gateway.example.com/v1',
  authScheme: AiAuthScheme.bearer,
  token: 'test-token',
  modelId: modelId,
  protocolType: AiProtocolType.openai,
  providerKind: AiProviderKind.openai,
  operationExtras: const <String, Object?>{
    'responses': <String, Object?>{
      'body': <String, Object?>{'prompt_cache_retention': '24h'},
    },
  },
);

void main() {
  test('全部内置线程模板共享同一基础装配段', () {
    const templates = AiPromptTemplatePolicies.entries;
    expect(templates, isNotEmpty);
    final baselineTags = templates.first.policy.sharedSections
        .map((section) => section.tag)
        .toList(growable: false);
    for (final template in templates) {
      expect(
        template.policy.sharedSections.map((section) => section.tag),
        baselineTags,
        reason: template.id,
      );
      expect(
        template.policy.promptAssetPathFor(
          AiPromptTemplateAssetFiles.systemInstructions,
        ),
        isNotEmpty,
      );
      expect(
        template.policy.promptAssetPathFor(
          AiPromptTemplateAssetFiles.developerInstructions,
        ),
        isNotEmpty,
      );
      expect(
        template.policy.promptAssetPathFor(
          AiPromptTemplateAssetFiles.compressionSummaryInstructions,
        ),
        isNotEmpty,
      );
    }
  });

  test('全部内置线程模板实际装配保持稳定前缀并落入统一缓存边界', () async {
    const builder = AiPromptBuilder();
    final model = _openAiModel('gpt-5.6-terra');
    final now = DateTime.utc(2026, 7, 16, 12);

    for (final template in AiPromptTemplatePolicies.entries) {
      final initialSession = _session(template, <AiSessionMessage>[
        AiSessionMessage.user(id: 'user-1', content: '第一轮', createdAt: now),
      ]);
      final followUpSession = _session(template, <AiSessionMessage>[
        AiSessionMessage.user(id: 'user-1', content: '第一轮', createdAt: now),
        AiSessionMessage.assistant(
          id: 'assistant-1',
          content: '第一轮回复',
          createdAt: now.add(const Duration(seconds: 1)),
        ),
        AiSessionMessage.user(
          id: 'user-2',
          content: '第二轮',
          createdAt: now.add(const Duration(seconds: 2)),
        ),
      ]);
      final initial = await builder.buildSessionPrompt(
        templateBundle: _bundle(template.id),
        session: initialSession,
        model: model,
        runtimeContext: _runtimeContext,
        memoryEntries: const <UserMemoryEntry>[],
        sessionMessages: initialSession.messages,
        latestUserMessageId: 'user-1',
        availableTools: _tools,
        planModeRecoveryInspectionRequired: false,
      );
      final followUp = await builder.buildSessionPrompt(
        templateBundle: _bundle(template.id),
        session: followUpSession,
        model: model,
        runtimeContext: _runtimeContext,
        memoryEntries: const <UserMemoryEntry>[],
        sessionMessages: followUpSession.messages,
        latestUserMessageId: 'user-2',
        availableTools: _tools,
        planModeRecoveryInspectionRequired: false,
      );

      expect(
        followUp.metadata['prompt_assembly_layout'],
        initial.metadata['prompt_assembly_layout'],
        reason: template.id,
      );
      expect(
        followUp.metadata['stable_prefix_hash'],
        initial.metadata['stable_prefix_hash'],
        reason: template.id,
      );
      expect(
        followUp.metadata['cache_anchor_hash'],
        initial.metadata['cache_anchor_hash'],
        reason: template.id,
      );
      expect(
        followUp.metadata['stable_prefix_message_count'],
        initial.metadata['stable_prefix_message_count'],
        reason: template.id,
      );
      expect(
        followUp.metadata['runtime_prefix_message_count'],
        initial.metadata['runtime_prefix_message_count'],
        reason: template.id,
      );

      final request = await AiResponsesService().buildChatRequest(
        model: model,
        messages: followUp.messages,
        tools: _tools,
        inputCacheConfig: AiInputCacheRuntimeConfig(
          enabled: true,
          mode: 'allMessages',
          updateInterval: 10,
          breakpointCount: 4,
          cacheAffinityId: followUpSession.id,
          promptCacheKey: '${followUp.metadata['stable_cache_key']}',
          stablePrefixMessageCount:
              followUp.metadata['stable_prefix_message_count']! as int,
        ),
      );
      expect(
        request.body['prompt_cache_key'],
        followUp.metadata['stable_cache_key'],
        reason: template.id,
      );
      expect(request.body['prompt_cache_options'], <String, String>{
        'mode': 'implicit',
        'ttl': '30m',
      }, reason: template.id);
      expect(_breakpointCount(request.body), 2, reason: template.id);
      final stablePrefixMessageCount =
          followUp.metadata['stable_prefix_message_count']! as int;
      final input = request.body['input']! as List<Object?>;
      expect(
        _breakpointCount(input[stablePrefixMessageCount - 1]),
        1,
        reason: template.id,
      );
      expect(
        _breakpointCount(input[stablePrefixMessageCount]),
        1,
        reason: template.id,
      );
    }
  });

  test('用户问题内容不会改变任何线程模板的内置提示词装配', () async {
    const builder = AiPromptBuilder();
    final model = _openAiModel('gpt-5.6-terra');
    final now = DateTime.utc(2026, 7, 16, 12);

    for (final template in AiPromptTemplatePolicies.entries) {
      final firstSession = _session(template, <AiSessionMessage>[
        AiSessionMessage.user(id: 'user-1', content: '你好', createdAt: now),
      ]);
      final secondSession = _session(template, <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'user-1',
          content: '检查并修改项目，然后运行完整验证',
          createdAt: now,
        ),
      ]);
      final first = await builder.buildSessionPrompt(
        templateBundle: _bundle(template.id),
        session: firstSession,
        model: model,
        runtimeContext: _runtimeContext,
        memoryEntries: const <UserMemoryEntry>[],
        sessionMessages: firstSession.messages,
        latestUserMessageId: 'user-1',
        availableTools: _tools,
        planModeRecoveryInspectionRequired: false,
      );
      final second = await builder.buildSessionPrompt(
        templateBundle: _bundle(template.id),
        session: secondSession,
        model: model,
        runtimeContext: _runtimeContext,
        memoryEntries: const <UserMemoryEntry>[],
        sessionMessages: secondSession.messages,
        latestUserMessageId: 'user-1',
        availableTools: _tools,
        planModeRecoveryInspectionRequired: false,
      );

      expect(
        second.messages
            .where((message) => message.role == AiChatRole.system)
            .map((message) => message.content),
        first.messages
            .where((message) => message.role == AiChatRole.system)
            .map((message) => message.content),
        reason: template.id,
      );
      expect(
        second.metadata['cache_anchor_hash'],
        first.metadata['cache_anchor_hash'],
        reason: template.id,
      );
      expect(
        second.metadata['stable_prefix_message_count'],
        first.metadata['stable_prefix_message_count'],
        reason: template.id,
      );
      expect(
        second.metadata['runtime_prefix_message_count'],
        first.metadata['runtime_prefix_message_count'],
        reason: template.id,
      );
    }
  });

  group('GPT-5.6+ Prompt 缓存控制', () {
    test('统一识别 GPT-5.6 及后续系列', () {
      expect(
        _openAiModel('gpt-5.6-terra').supportsOpenAiPromptCacheBreakpoints,
        true,
      );
      expect(
        _openAiModel('openai/gpt-6-sol').supportsOpenAiPromptCacheBreakpoints,
        true,
      );
      expect(
        _openAiModel('gpt-5.5').supportsOpenAiPromptCacheBreakpoints,
        false,
      );
    });

    test('Responses 请求使用新 TTL 并标记稳定系统前缀', () {
      final request = AiResponsesService().buildRequest(
        model: _openAiModel('gpt-5.6-terra'),
        input: <Map<String, Object?>>[
          <String, Object?>{'role': 'system', 'content': '固定系统提示词'},
          <String, Object?>{'role': 'user', 'content': '本轮问题'},
        ],
        inputCacheConfig: _cacheConfig,
      );

      expect(request.body.keys.last, 'input');
      expect(request.body['prompt_cache_key'], 'cache-key-1');
      expect(request.body['prompt_cache_options'], <String, String>{
        'mode': 'implicit',
        'ttl': '30m',
      });
      expect(request.body.containsKey('prompt_cache_retention'), false);
      final input = request.body['input']! as List<Object?>;
      final system = input.first! as Map<String, Object?>;
      final content = system['content']! as List<Object?>;
      final block = content.single! as Map<String, Object?>;
      expect(block['type'], 'input_text');
      expect(block['prompt_cache_breakpoint'], <String, String>{
        'mode': 'explicit',
      });
    });

    test('Chat Completions 与 Responses 使用相同缓存策略', () async {
      final request = await const OpenAiProtocolAdapter(AiProtocolType.openai)
          .buildChatRequest(
            model: _openAiModel('gpt-5.6-sol'),
            messages: const <AiChatTurn>[
              AiChatTurn(role: AiChatRole.system, content: '固定系统提示词'),
              AiChatTurn(role: AiChatRole.user, content: '本轮问题'),
            ],
            inputCacheConfig: _cacheConfig,
          );

      expect(request.body.keys.last, 'messages');
      expect(request.body['prompt_cache_options'], <String, String>{
        'mode': 'implicit',
        'ttl': '30m',
      });
      final messages = request.body['messages']! as List<Object?>;
      final system = messages.first! as Map<String, Object?>;
      final content = system['content']! as List<Object?>;
      final block = content.single! as Map<String, Object?>;
      expect(block['type'], 'text');
      expect(block['prompt_cache_breakpoint'], <String, String>{
        'mode': 'explicit',
      });
    });

    test('旧系列保持原协议且降级时保留缓存亲和键', () {
      final oldRequest = AiResponsesService().buildRequest(
        model: _openAiModel('gpt-5.5'),
        input: <Map<String, Object?>>[
          <String, Object?>{'role': 'system', 'content': '固定系统提示词'},
        ],
        inputCacheConfig: _cacheConfig,
      );
      expect(oldRequest.body['prompt_cache_retention'], '24h');
      expect(oldRequest.body.containsKey('prompt_cache_options'), false);

      final modernRequest = AiResponsesService().buildRequest(
        model: _openAiModel('gpt-5.6-terra'),
        input: <Map<String, Object?>>[
          <String, Object?>{'role': 'system', 'content': '固定系统提示词'},
        ],
        inputCacheConfig: _cacheConfig,
      );
      final downgraded = AiOpenAiPromptCacheControl.withoutMarkers(
        modernRequest.body,
      );
      expect(downgraded['prompt_cache_key'], 'cache-key-1');
      expect(downgraded.containsKey('prompt_cache_options'), false);
      expect(AiOpenAiPromptCacheControl.bodyHasMarkers(downgraded), false);
    });
  });
}

AiPromptTemplateBundle _bundle(String templateId) {
  final template = AiPromptTemplateRepository().resolveTemplate(templateId);
  return AiPromptTemplateBundle(
    template: template,
    systemInstructions: '<identity>固定系统提示词</identity>',
    developerInstructions: '<tool_catalog>固定开发者提示词</tool_catalog>',
    compressionSummaryInstructions: '<role>固定摘要提示词</role>',
  );
}

AiSession _session(
  AiPromptTemplateCatalogEntry template,
  List<AiSessionMessage> messages,
) {
  final now = DateTime.utc(2026, 7, 16, 12);
  return AiSession(
    id: 'session-${template.id}',
    title: '缓存回归',
    templateId: template.info.id,
    templateName: template.info.name,
    templateIconName: template.info.iconName,
    templateInternalVersion: template.info.internalVersion,
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: AiSessionEnvironment(
      localeTag: 'zh-Hans',
      platform: 'test',
      appVersion: 'test',
      appBuildNumber: '1',
      applicationDirectory: '',
      homeDirectory: '',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      sessionsDirectoryPath: '',
      compressionThresholdChars: 100000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}

int _breakpointCount(Object? value) {
  if (value is Map) {
    return (value.containsKey(AiOpenAiPromptCacheControl.breakpointField)
            ? 1
            : 0) +
        value.values.fold<int>(
          0,
          (count, child) => count + _breakpointCount(child),
        );
  }
  if (value is List) {
    return value.fold<int>(
      0,
      (count, child) => count + _breakpointCount(child),
    );
  }
  return 0;
}

final _runtimeContext = AiSessionRuntimeContext(
  localeTag: 'zh-Hans',
  appVersion: 'test',
  appBuildNumber: '1',
  settingsFilePath: '',
  skillsStoragePath: '',
  mcpServersFilePath: '',
  userMemoryFilePath: '',
  compressionThresholdChars: 100000,
  memoryEnabled: false,
  memoryEntries: <UserMemoryEntry>[],
  platformName: 'test',
  workingDirectory: '/tmp/openhand-test',
  timeZoneName: 'Asia/Shanghai',
);

const _tools = <AiToolDefinition>[
  AiToolDefinition(
    name: 'Write',
    description: '写入文件。',
    parameters: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  ),
];

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

AiModelConfig _model(String modelId) => AiModelConfig(
  id: modelId,
  baseUrl: 'https://gateway.example.com/v1',
  authScheme: AiAuthScheme.bearer,
  token: 'test-token',
  modelId: modelId,
  protocolType: AiProtocolType.openai,
  providerKind: AiProviderKind.openai,
);

void main() {
  test('所有 OpenAI 兼容模型统一使用自动缓存亲和', () {
    for (final modelId in const <String>[
      'gpt-5.5',
      'gpt-5.6-terra',
      'custom-compatible-model',
    ]) {
      final request = AiResponsesService().buildRequest(
        model: _model(modelId),
        input: <Map<String, Object?>>[
          <String, Object?>{'role': 'system', 'content': '固定系统提示词'},
          <String, Object?>{'role': 'user', 'content': '本轮问题'},
        ],
        inputCacheConfig: _cacheConfig,
      );

      expect(request.body.keys.last, 'input', reason: modelId);
      expect(
        request.body['prompt_cache_key'],
        _cacheConfig.promptCacheKey,
        reason: modelId,
      );
      expect(
        request.headers[AiPromptCacheAffinity.standardSessionAffinityHeader],
        _cacheConfig.cacheAffinityId,
        reason: modelId,
      );
      expect(request.body.containsKey('prompt_cache_options'), false);
      expect(_containsKey(request.body, 'prompt_cache_breakpoint'), false);
    }
  });

  test('全部内置线程模板共享同一基础装配段', () {
    const templates = AiPromptTemplatePolicies.entries;
    final baselineTags = templates.first.policy.sharedSections
        .map((section) => section.tag)
        .toList(growable: false);
    for (final template in templates) {
      expect(
        template.policy.sharedSections.map((section) => section.tag),
        baselineTags,
        reason: template.id,
      );
    }
  });

  test('用户问题内容不会改变任何模板的内置提示词装配', () async {
    const builder = AiPromptBuilder();
    final model = _model('custom-compatible-model');
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
      final first = await _buildPrompt(
        builder: builder,
        template: template,
        session: firstSession,
        model: model,
        latestUserMessageId: 'user-1',
      );
      final second = await _buildPrompt(
        builder: builder,
        template: template,
        session: secondSession,
        model: model,
        latestUserMessageId: 'user-1',
      );

      expect(
        _systemContents(second),
        _systemContents(first),
        reason: template.id,
      );
      expect(
        second.metadata['stable_prefix_hash'],
        first.metadata['stable_prefix_hash'],
        reason: template.id,
      );
      expect(
        second.metadata['cache_anchor_hash'],
        first.metadata['cache_anchor_hash'],
        reason: template.id,
      );
    }
  });

  test('全部内置线程模板在追加历史后保持前缀稳定', () async {
    const builder = AiPromptBuilder();
    final model = _model('custom-compatible-model');
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
      final initial = await _buildPrompt(
        builder: builder,
        template: template,
        session: initialSession,
        model: model,
        latestUserMessageId: 'user-1',
      );
      final followUp = await _buildPrompt(
        builder: builder,
        template: template,
        session: followUpSession,
        model: model,
        latestUserMessageId: 'user-2',
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
    }
  });
}

Future<AiPromptBuildResult> _buildPrompt({
  required AiPromptBuilder builder,
  required AiPromptTemplateCatalogEntry template,
  required AiSession session,
  required AiModelConfig model,
  required String latestUserMessageId,
}) {
  return builder.buildSessionPrompt(
    templateBundle: _bundle(template.id),
    session: session,
    model: model,
    runtimeContext: _runtimeContext,
    memoryEntries: const <UserMemoryEntry>[],
    sessionMessages: session.messages,
    latestUserMessageId: latestUserMessageId,
    availableTools: _tools,
    planModeRecoveryInspectionRequired: false,
  );
}

List<String> _systemContents(AiPromptBuildResult result) => result.messages
    .where((message) => message.role == AiChatRole.system)
    .map((message) => message.content)
    .toList(growable: false);

bool _containsKey(Object? value, String key) {
  if (value is Map) {
    return value.containsKey(key) ||
        value.values.any((child) => _containsKey(child, key));
  }
  return value is List && value.any((child) => _containsKey(child, key));
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

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';

const _model = AiModelConfig(
  id: 'claude-test',
  baseUrl: 'https://example.com',
  authScheme: AiAuthScheme.bearer,
  token: 'test-token',
  modelId: 'claude-test',
  protocolType: AiProtocolType.claude,
);

const _cacheConfig = AiInputCacheRuntimeConfig(
  enabled: true,
  mode: 'allMessages',
  updateInterval: 10,
  breakpointCount: 4,
);

const _tool = AiToolDefinition(
  name: 'Read',
  description: '读取文件。',
  parameters: <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{},
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Claude 连续请求保留上一消息尾锚', () async {
    const adapter = ClaudeProtocolAdapter();
    final firstBody = await adapter.buildBody(
      _model,
      _turns(5),
      tools: const <AiToolDefinition>[_tool],
      inputCacheConfig: _cacheConfig,
    );
    final secondBody = await adapter.buildBody(
      _model,
      _turns(7),
      tools: const <AiToolDefinition>[_tool],
      inputCacheConfig: _cacheConfig,
    );

    expect(_messageMarkerIndices(firstBody), <int>[0, 2, 4]);
    expect(_messageMarkerIndices(secondBody), <int>[0, 4, 6]);
    final firstMessages = firstBody['messages']! as List<Object?>;
    final secondMessages = secondBody['messages']! as List<Object?>;
    expect(secondMessages[4], firstMessages[4]);
    expect(_cacheMarkerCount(secondBody), 4);
    expect(_cacheMarkerCount(secondBody['system']), 1);
    expect(_cacheMarkerCount(secondBody['tools']), 0);
  });

  test('Claude 在不同上下文下严格遵守断点预算', () async {
    const adapter = ClaudeProtocolAdapter();
    for (var count = 1; count <= 4; count++) {
      final body = await adapter.buildBody(
        _model,
        _turns(7),
        tools: const <AiToolDefinition>[_tool],
        inputCacheConfig: AiInputCacheRuntimeConfig(
          enabled: true,
          mode: 'allMessages',
          updateInterval: 10,
          breakpointCount: count,
        ),
      );
      expect(_cacheMarkerCount(body), count, reason: '断点数量 $count');
      expect(_cacheMarkerCount(body['system']), 1, reason: '断点数量 $count');
      expect(_cacheMarkerCount(body['tools']), 0, reason: '断点数量 $count');
    }

    final toolsOnlyBody = await adapter.buildBody(
      _model,
      _conversationTurns(5),
      tools: const <AiToolDefinition>[_tool],
      inputCacheConfig: _cacheConfig,
    );
    expect(_cacheMarkerCount(toolsOnlyBody), 4);
    expect(_cacheMarkerCount(toolsOnlyBody['tools']), 1);
    expect(_messageMarkerIndices(toolsOnlyBody), <int>[0, 2, 4]);

    final messagesOnlyBody = await adapter.buildBody(
      _model,
      _conversationTurns(5),
      inputCacheConfig: _cacheConfig,
    );
    expect(_cacheMarkerCount(messagesOnlyBody), 4);
    expect(_messageMarkerIndices(messagesOnlyBody), <int>[0, 1, 2, 4]);

    final shortBody = await adapter.buildBody(
      _model,
      _turns(1),
      inputCacheConfig: _cacheConfig,
    );
    expect(_cacheMarkerCount(shortBody), 2);
    expect(_messageMarkerIndices(shortBody), <int>[0]);

    final clampedBody = await adapter.buildBody(
      _model,
      _turns(7),
      inputCacheConfig: const AiInputCacheRuntimeConfig(
        enabled: true,
        mode: 'allMessages',
        updateInterval: 10,
        breakpointCount: 8,
      ),
    );
    expect(_cacheMarkerCount(clampedBody), 4);

    final disabledBody = await adapter.buildBody(
      _model,
      _turns(7),
      tools: const <AiToolDefinition>[_tool],
      inputCacheConfig: AiInputCacheRuntimeConfig.disabled,
    );
    expect(_cacheMarkerCount(disabledBody), 0);
  });

  test('Claude 优先保留连续尾锚再采用自定义历史候选点', () async {
    const adapter = ClaudeProtocolAdapter();
    final body = await adapter.buildBody(
      _model,
      _turns(11),
      inputCacheConfig: const AiInputCacheRuntimeConfig(
        enabled: true,
        mode: 'allMessages',
        updateInterval: 10,
        breakpointCount: 4,
        breakpointPositions: <double>[0.1, 0.3, 0.5],
      ),
    );

    expect(_cacheMarkerCount(body), 4);
    expect(_messageMarkerIndices(body), <int>[5, 8, 10]);
  });

  test('全部内置模板的 Prompt 装配不受用户问题影响', () async {
    final repository = AiPromptTemplateRepository();
    final expected = AiPromptTemplatePolicies
        .entries
        .first
        .policy
        .sharedSections
        .map((section) => section.tag)
        .toList(growable: false);

    for (final entry in AiPromptTemplatePolicies.entries) {
      final bundle = await repository.loadBundle(entry.id);
      expect(
        entry.policy.sharedSections.map((section) => section.tag),
        expected,
        reason: entry.id,
      );
      final first = await _buildPrompt(bundle, '普通问题');
      final second = await _buildPrompt(bundle, '检查并修改项目，然后运行完整验证');
      expect(_systemContents(second), _systemContents(first), reason: entry.id);
      expect(
        second.metadata['stable_prefix_hash'],
        first.metadata['stable_prefix_hash'],
        reason: entry.id,
      );
      expect(
        second.metadata['cache_anchor_hash'],
        first.metadata['cache_anchor_hash'],
        reason: entry.id,
      );
    }
  });
}

Future<AiPromptBuildResult> _buildPrompt(
  AiPromptTemplateBundle bundle,
  String userContent,
) {
  final now = DateTime.utc(2026, 8, 6);
  final userMessage = AiSessionMessage.user(
    id: 'user-1',
    content: userContent,
    createdAt: now,
  );
  final template = bundle.template;
  final session = AiSession(
    id: 'session-${template.id}',
    title: '缓存回归',
    templateId: template.id,
    templateName: template.name,
    templateIconName: template.iconName,
    templateInternalVersion: template.internalVersion,
    createdAt: now,
    updatedAt: now,
    messages: <AiSessionMessage>[userMessage],
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
  return const AiPromptBuilder().buildSessionPrompt(
    templateBundle: bundle,
    session: session,
    model: _model,
    runtimeContext: AiSessionRuntimeContext(
      localeTag: 'zh-Hans',
      appVersion: 'test',
      appBuildNumber: '1',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      compressionThresholdChars: 100000,
      memoryEnabled: false,
      memoryEntries: [],
      platformName: 'test',
      workingDirectory: '/tmp/openhand-test',
      timeZoneName: 'Asia/Shanghai',
    ),
    memoryEntries: [],
    sessionMessages: session.messages,
    latestUserMessageId: userMessage.id,
    availableTools: <AiToolDefinition>[_tool],
    planModeRecoveryInspectionRequired: false,
  );
}

List<String> _systemContents(AiPromptBuildResult result) => result.messages
    .where((message) => message.role == AiChatRole.system)
    .map((message) => message.content)
    .toList(growable: false);

List<AiChatTurn> _turns(int conversationTurnCount) {
  return <AiChatTurn>[
    const AiChatTurn(role: AiChatRole.system, content: '固定系统提示词'),
    ..._conversationTurns(conversationTurnCount),
  ];
}

List<AiChatTurn> _conversationTurns(int count) => <AiChatTurn>[
  for (var index = 0; index < count; index++)
    AiChatTurn(
      role: index.isEven ? AiChatRole.user : AiChatRole.assistant,
      content: '消息 $index',
    ),
];

List<int> _messageMarkerIndices(Map<String, Object?> body) {
  final messages = body['messages']! as List<Object?>;
  return <int>[
    for (var index = 0; index < messages.length; index++)
      if (_cacheMarkerCount(messages[index]) > 0) index,
  ];
}

int _cacheMarkerCount(Object? value) {
  if (value is Map) {
    return (value.containsKey('cache_control') ? 1 : 0) +
        value.values.fold<int>(
          0,
          (sum, child) => sum + _cacheMarkerCount(child),
        );
  }
  if (value is List) {
    return value.fold<int>(0, (sum, child) => sum + _cacheMarkerCount(child));
  }
  return 0;
}

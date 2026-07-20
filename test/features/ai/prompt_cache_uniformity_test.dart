import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OpenAI 兼容协议统一使用保留期提示且不创建显式断点', () async {
    for (final modelId in const <String>[
      'custom-compatible-model',
      'gpt-5.5',
      'gpt-5.6-terra',
    ]) {
      final model = _model(modelId);
      final responsesRequest = AiResponsesService().buildRequest(
        model: model,
        input: <Map<String, Object?>>[
          <String, Object?>{'role': 'system', 'content': '固定系统提示词'},
          <String, Object?>{'role': 'user', 'content': '本轮问题'},
        ],
        inputCacheConfig: _cacheConfig,
      );
      final chatRequest =
          await const OpenAiProtocolAdapter(
            AiProtocolType.openai,
          ).buildChatRequest(
            model: model,
            messages: const <AiChatTurn>[
              AiChatTurn(role: AiChatRole.system, content: '固定系统提示词'),
              AiChatTurn(role: AiChatRole.user, content: '本轮问题'),
            ],
            inputCacheConfig: _cacheConfig,
          );

      for (final body in <Map<String, Object?>>[
        responsesRequest.body,
        chatRequest.body,
      ]) {
        expect(
          body[AiPromptCacheRetentionPolicy.bodyField],
          AiPromptCacheRetentionPolicy.extendedRetention,
          reason: modelId,
        );
        expect(body['prompt_cache_key'], _cacheConfig.promptCacheKey);
        expect(_containsKey(body, 'prompt_cache_options'), false);
        expect(_containsKey(body, 'prompt_cache_breakpoint'), false);
      }
      expect(responsesRequest.body.keys.last, 'input');
      expect(chatRequest.body.keys.last, 'messages');
    }
  });

  test('缓存关闭与网关降级均不破坏原请求', () {
    final disabledRequest = AiResponsesService().buildRequest(
      model: _model('custom-compatible-model'),
      input: '固定系统提示词',
      inputCacheConfig: AiInputCacheRuntimeConfig.disabled,
    );
    expect(
      disabledRequest.body.containsKey(AiPromptCacheRetentionPolicy.bodyField),
      false,
    );

    final enabledRequest = AiResponsesService().buildRequest(
      model: _model('custom-compatible-model'),
      input: '固定系统提示词',
      inputCacheConfig: _cacheConfig,
    );
    final downgraded = AiPromptCacheRetentionPolicy.withoutMarker(
      enabledRequest.body,
    );
    expect(downgraded['prompt_cache_key'], _cacheConfig.promptCacheKey);
    expect(
      downgraded.containsKey(AiPromptCacheRetentionPolicy.bodyField),
      false,
    );
    expect(
      AiPromptCacheRetentionPolicy.shouldRetryWithoutMarker(
        statusCode: 400,
        errorBody: 'Unsupported parameter: prompt_cache_retention',
        requestBody: enabledRequest.body,
      ),
      true,
    );
  });

  test('网关拒绝保留期提示后仅重试一次并短期记忆能力', () async {
    final requestBodies = <Map<String, Object?>>[];
    final service = AiResponsesService(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requestBodies.add(Map<String, Object?>.from(body));
        if (body.containsKey(AiPromptCacheRetentionPolicy.bodyField)) {
          return http.Response(
            '{"error":"Unsupported parameter: prompt_cache_retention"}',
            400,
          );
        }
        return http.Response.bytes(
          utf8.encode(
            '{"output_text":"完成","usage":{"input_tokens":1,'
            '"output_tokens":1,"total_tokens":2}}',
          ),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );
    const model = AiModelConfig(
      id: 'retention-reject',
      baseUrl: 'https://retention-reject.example.com/v1',
      authScheme: AiAuthScheme.bearer,
      token: 'test-token',
      modelId: 'custom-compatible-model',
      protocolType: AiProtocolType.openai,
      providerKind: AiProviderKind.openai,
    );

    for (var index = 0; index < 2; index++) {
      await service.createResponseFromRequest(
        request: service.buildRequest(
          model: model,
          input: '固定系统提示词',
          inputCacheConfig: _cacheConfig,
        ),
      );
    }

    expect(requestBodies, hasLength(3));
    expect(
      requestBodies.first.containsKey(AiPromptCacheRetentionPolicy.bodyField),
      true,
    );
    expect(
      requestBodies
          .skip(1)
          .every(
            (body) =>
                !body.containsKey(AiPromptCacheRetentionPolicy.bodyField) &&
                body['prompt_cache_key'] == _cacheConfig.promptCacheKey,
          ),
      true,
    );
  });

  test('内建工具自动阈值独立封顶并保留安全下限', () {
    expect(
      AiBuiltinToolLazyLoadingApplier.effectiveAutoThresholdTokens(16000),
      AiBuiltinToolLazyLoadingApplier.defaultAutoThresholdTokens,
    );
    expect(
      AiBuiltinToolLazyLoadingApplier.effectiveAutoThresholdTokens(500),
      AiBuiltinToolLazyLoadingApplier.minAutoThresholdTokens,
    );

    const toolSearch = AiResolvedTool(
      name: 'ToolSearch',
      definition: AiToolDefinition(
        name: 'ToolSearch',
        description: '固定延迟工具网关。',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
        },
      ),
      source: AiRuntimeToolSource.builtin,
      builtinKind: AiBuiltinToolKind.toolSearch,
    );
    final deferredTool = AiResolvedTool(
      name: 'Write',
      definition: AiToolDefinition(
        name: 'Write',
        description: '写入文件。${'参数说明' * 9000}',
        parameters: const <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
        },
      ),
      source: AiRuntimeToolSource.builtin,
      builtinKind: AiBuiltinToolKind.write,
    );
    final catalog = AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[
        toolSearch.definition,
        deferredTool.definition,
      ],
      toolsByName: <String, AiResolvedTool>{
        toolSearch.name: toolSearch,
        deferredTool.name: deferredTool,
      },
    );
    final lazyCatalog = AiBuiltinToolLazyLoadingApplier.apply(
      catalog: catalog,
      sourceCatalog: catalog,
      mode: AiBuiltinToolLazyLoadingMode.auto,
      thresholdTokens:
          AiBuiltinToolLazyLoadingApplier.defaultAutoThresholdTokens,
      charsPerToken: 4,
    );
    expect(lazyCatalog.definitions.map((tool) => tool.name), <String>[
      'ToolSearch',
    ]);
    expect(lazyCatalog.findDeferredTool('Write'), same(deferredTool));
  });

  test('关闭供应商显式缓存后不再发送协议缓存标记', () {
    final policy = AiInputCachePolicy.resolve(
      model: const AiModelConfig(
        id: 'claude',
        baseUrl: 'https://gateway.example.com/v1',
        authScheme: AiAuthScheme.bearer,
        token: 'test-token',
        modelId: 'claude-compatible',
        protocolType: AiProtocolType.claude,
        apiDialect: AiApiDialect.anthropicNative,
        explicitPromptCacheEnabled: false,
      ),
      runtimeContext: _runtimeContext,
    );
    expect(policy.strategy, AiInputCacheControlStrategy.providerDisabled);
    expect(policy.emitsProtocolCacheHints, false);
  });

  test('全部线程模板不按用户问题改变内置系统装配', () async {
    const builder = AiPromptBuilder();
    final model = _model('custom-compatible-model');
    final now = DateTime.utc(2026, 7, 20, 12);
    final baselineSharedSections = AiPromptTemplatePolicies
        .entries
        .first
        .policy
        .sharedSections
        .map((section) => section.tag)
        .toList(growable: false);

    for (final template in AiPromptTemplatePolicies.entries) {
      expect(
        template.policy.sharedSections.map((section) => section.tag),
        baselineSharedSections,
        reason: template.id,
      );
      final firstSession = _session(template, '你好', now);
      final secondSession = _session(template, '检查并修改项目', now);
      final first = await _buildPrompt(builder, firstSession, model);
      final second = await _buildPrompt(builder, secondSession, model);

      expect(
        _systemContents(second),
        _systemContents(first),
        reason: template.id,
      );
      expect(
        second.metadata['cache_anchor_hash'],
        first.metadata['cache_anchor_hash'],
        reason: template.id,
      );
    }
  });
}

Future<AiPromptBuildResult> _buildPrompt(
  AiPromptBuilder builder,
  AiSession session,
  AiModelConfig model,
) async {
  return builder.buildSessionPrompt(
    templateBundle: await _templateRepository.loadBundle(session.templateId),
    session: session,
    model: model,
    runtimeContext: _runtimeContext,
    memoryEntries: const <UserMemoryEntry>[],
    sessionMessages: session.messages,
    latestUserMessageId: 'user-1',
    availableTools: _tools,
    planModeRecoveryInspectionRequired: false,
  );
}

AiSession _session(
  AiPromptTemplateCatalogEntry template,
  String content,
  DateTime now,
) {
  return AiSession(
    id: 'session-${template.id}',
    title: '缓存回归',
    templateId: template.id,
    templateName: template.info.name,
    templateIconName: template.info.iconName,
    templateInternalVersion: template.info.internalVersion,
    createdAt: now,
    updatedAt: now,
    messages: <AiSessionMessage>[
      AiSessionMessage.user(id: 'user-1', content: content, createdAt: now),
    ],
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

final _templateRepository = AiPromptTemplateRepository();

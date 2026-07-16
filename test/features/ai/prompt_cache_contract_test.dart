import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/harness/index.dart';
import 'package:openhand/features/mcp/index.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';

void main() {
  test('全部线程模板共享固定装配流程且不受用户内容影响', () async {
    const builder = AiPromptBuilder();
    final model = _model();
    final now = DateTime.utc(2026, 7, 16, 12);
    final baselineTags = AiPromptTemplatePolicies
        .entries
        .first
        .policy
        .sharedSections
        .map((section) => section.tag)
        .toList(growable: false);

    for (final template in AiPromptTemplatePolicies.entries) {
      expect(
        template.policy.sharedSections.map((section) => section.tag),
        baselineTags,
        reason: template.id,
      );
      final first = await _buildPrompt(
        builder: builder,
        template: template,
        session: _session(template, <AiSessionMessage>[
          AiSessionMessage.user(id: 'user-1', content: '你好', createdAt: now),
        ]),
        model: model,
        latestUserMessageId: 'user-1',
      );
      final second = await _buildPrompt(
        builder: builder,
        template: template,
        session: _session(template, <AiSessionMessage>[
          AiSessionMessage.user(
            id: 'user-1',
            content: '创建远程会话并执行操作',
            createdAt: now,
          ),
        ]),
        model: model,
        latestUserMessageId: 'user-1',
      );
      final followUp = await _buildPrompt(
        builder: builder,
        template: template,
        session: _session(template, <AiSessionMessage>[
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
        ]),
        model: model,
        latestUserMessageId: 'user-2',
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
      expect(
        followUp.metadata['stable_prefix_hash'],
        first.metadata['stable_prefix_hash'],
        reason: template.id,
      );
      expect(
        followUp.metadata['cache_anchor_hash'],
        first.metadata['cache_anchor_hash'],
        reason: template.id,
      );
    }
  });

  test('ToolSearch 匹配后原生工具目录保持不变', () async {
    const toolName = 'mcp__server__remote_action';
    const toolSearch = AiResolvedTool(
      name: 'ToolSearch',
      definition: AiToolDefinition(
        name: 'ToolSearch',
        description: '固定工具网关。',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'query': <String, Object?>{'type': 'string'},
            'max_results': <String, Object?>{'type': 'integer'},
            'tool_name': <String, Object?>{'type': 'string'},
            'arguments': <String, Object?>{
              'type': 'object',
              'additionalProperties': true,
            },
          },
          'anyOf': <Object?>[
            <String, Object?>{
              'required': <String>['query'],
            },
            <String, Object?>{
              'required': <String>['tool_name', 'arguments'],
            },
          ],
          'additionalProperties': false,
        },
      ),
      source: AiRuntimeToolSource.builtin,
      builtinKind: AiBuiltinToolKind.toolSearch,
    );
    const deferredTool = AiResolvedTool(
      name: toolName,
      definition: AiToolDefinition(
        name: toolName,
        description: '执行远程操作。',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'value': <String, Object?>{'type': 'string'},
          },
          'required': <String>['value'],
        },
      ),
      source: AiRuntimeToolSource.mcp,
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
    final idleCatalog = McpLazyLoadingApplier.apply(
      catalog: AiResolvedToolCatalog(
        definitions: <AiToolDefinition>[toolSearch.definition],
        toolsByName: const <String, AiResolvedTool>{'ToolSearch': toolSearch},
      ),
      runtimeContext: _runtimeContext,
      keepToolSearchWhenIdle: true,
    );
    final lazyCatalog = McpLazyLoadingApplier.apply(
      catalog: catalog,
      runtimeContext: _runtimeContext,
      keepToolSearchWhenIdle: true,
    );
    final nativeCatalogBefore = jsonEncode(
      lazyCatalog.definitions.map((tool) => tool.toOpenAiJson()).toList(),
    );

    expect(lazyCatalog.definitions.map((tool) => tool.name), <String>[
      'ToolSearch',
    ]);
    expect(
      jsonEncode(
        idleCatalog.definitions.map((tool) => tool.toOpenAiJson()).toList(),
      ),
      nativeCatalogBefore,
    );
    expect(lazyCatalog.findDeferredTool(toolName), same(deferredTool));
    final catalogWithoutGateway = McpLazyLoadingApplier.apply(
      catalog: AiResolvedToolCatalog(
        definitions: <AiToolDefinition>[deferredTool.definition],
        toolsByName: const <String, AiResolvedTool>{toolName: deferredTool},
      ),
      runtimeContext: _runtimeContext,
    );
    expect(catalogWithoutGateway.definitions.single.name, toolName);
    final promotedCatalog = McpLazyLoadingApplier.apply(
      catalog: catalog,
      runtimeContext: _runtimeContext,
      keepToolSearchWhenIdle: true,
      promotedToolNames: const <String>{toolName},
    );
    expect(promotedCatalog.definitions.map((tool) => tool.name), <String>[
      'ToolSearch',
      toolName,
    ]);
    expect(promotedCatalog.findDeferredTool(toolName), isNull);

    final result = await AiToolSearchTool().execute(
      AiToolExecutionContext(
        sessionId: 'session-1',
        catalog: lazyCatalog,
        toolCall: const AiToolCall(
          id: 'call-1',
          name: 'ToolSearch',
          arguments: '{"query":"select:$toolName"}',
        ),
        decodedArguments: const <String, Object?>{'query': 'select:$toolName'},
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      ),
    );
    final payload = jsonDecode(result.resultText) as Map<String, dynamic>;

    expect(payload['loaded_tools'], <String>[toolName]);
    expect('${payload['message']}', contains('tool_name'));
    expect(
      jsonEncode(
        lazyCatalog.definitions.map((tool) => tool.toOpenAiJson()).toList(),
      ),
      nativeCatalogBefore,
    );
  });

  test('Harness 只允许网关代理当前阶段具备权限的工具', () async {
    const deferredTool = AiResolvedTool(
      name: 'mcp__server__write_remote',
      definition: AiToolDefinition(
        name: 'mcp__server__write_remote',
        description: '写入远端资源。',
        parameters: <String, Object?>{'type': 'object'},
      ),
      source: AiRuntimeToolSource.mcp,
    );
    final toolSearch = AiResolvedTool(
      name: 'ToolSearch',
      definition: const AiToolDefinition(
        name: 'ToolSearch',
        description: '固定工具网关。',
        parameters: <String, Object?>{'type': 'object'},
      ),
      source: AiRuntimeToolSource.builtin,
      builtinKind: AiBuiltinToolKind.toolSearch,
      toolSearchDeferredToolDefinitions: <String, AiToolDefinition>{
        'mcp__server__write_remote': deferredTool.definition,
      },
      toolSearchDeferredTools: <String, AiResolvedTool>{
        'mcp__server__write_remote': deferredTool,
      },
    );
    final catalog = AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[toolSearch.definition],
      toolsByName: <String, AiResolvedTool>{'ToolSearch': toolSearch},
    );
    const builder = HarnessPromptBuilder();

    final readingCatalog = builder.filterToolsForPhase(
      phase: HarnessPhase.reading,
      catalog: catalog,
    );
    final implementingCatalog = builder.filterToolsForPhase(
      phase: HarnessPhase.implementing,
      catalog: catalog,
    );

    expect(
      readingCatalog.findDeferredTool('mcp__server__write_remote'),
      isNull,
    );
    expect(
      implementingCatalog.findDeferredTool('mcp__server__write_remote'),
      same(deferredTool),
    );
    final promotedCatalog = AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[
        toolSearch.definition,
        deferredTool.definition,
      ],
      toolsByName: <String, AiResolvedTool>{
        'ToolSearch': toolSearch,
        deferredTool.name: deferredTool,
      },
    );
    expect(
      builder
          .filterToolsForPhase(
            phase: HarnessPhase.reading,
            catalog: promotedCatalog,
          )
          .find(deferredTool.name),
      isNull,
    );
    expect(
      builder
          .filterToolsForPhase(
            phase: HarnessPhase.implementing,
            catalog: promotedCatalog,
          )
          .find(deferredTool.name),
      same(deferredTool),
    );

    final searchTool = AiToolSearchTool()
      ..setDeferredToolSnapshot(toolSearch.toolSearchDeferredToolDefinitions);
    final result = await searchTool.execute(
      AiToolExecutionContext(
        sessionId: 'session-1',
        catalog: readingCatalog,
        toolCall: const AiToolCall(
          id: 'call-1',
          name: 'ToolSearch',
          arguments: '{"query":"write remote"}',
        ),
        decodedArguments: const <String, Object?>{'query': 'write remote'},
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      ),
    );
    final payload = jsonDecode(result.resultText) as Map<String, dynamic>;
    expect(payload['loaded_tools'], isEmpty);
  });

  test('晋升的内置工具进入原生目录且不再保留延迟副本', () {
    const toolName = 'WebFetch';
    const toolSearch = AiResolvedTool(
      name: 'ToolSearch',
      definition: AiToolDefinition(
        name: 'ToolSearch',
        description: '固定工具网关。',
        parameters: <String, Object?>{'type': 'object'},
      ),
      source: AiRuntimeToolSource.builtin,
      builtinKind: AiBuiltinToolKind.toolSearch,
    );
    const deferredTool = AiResolvedTool(
      name: toolName,
      definition: AiToolDefinition(
        name: toolName,
        description: '读取网页。',
        parameters: <String, Object?>{'type': 'object'},
      ),
      source: AiRuntimeToolSource.builtin,
      builtinKind: AiBuiltinToolKind.webFetch,
      builtinConfig: AiBuiltinToolConfig(
        kind: AiBuiltinToolKind.webFetch,
        loadStrategy: AiBuiltinToolLoadStrategy.lazy,
      ),
    );
    final sourceCatalog = AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[
        toolSearch.definition,
        deferredTool.definition,
      ],
      toolsByName: <String, AiResolvedTool>{
        'ToolSearch': toolSearch,
        toolName: deferredTool,
      },
    );

    final lazyCatalog = AiBuiltinToolLazyLoadingApplier.apply(
      catalog: sourceCatalog,
      sourceCatalog: sourceCatalog,
      mode: AiBuiltinToolLazyLoadingMode.enabled,
      thresholdTokens: 1,
      charsPerToken: 4,
    );
    final promotedCatalog = AiBuiltinToolLazyLoadingApplier.apply(
      catalog: sourceCatalog,
      sourceCatalog: sourceCatalog,
      mode: AiBuiltinToolLazyLoadingMode.enabled,
      thresholdTokens: 1,
      charsPerToken: 4,
      promotedToolNames: const <String>{toolName},
    );

    expect(lazyCatalog.definitions.map((tool) => tool.name), <String>[
      'ToolSearch',
    ]);
    expect(lazyCatalog.findDeferredTool(toolName), same(deferredTool));
    expect(promotedCatalog.definitions.map((tool) => tool.name), <String>[
      'ToolSearch',
      toolName,
    ]);
    expect(promotedCatalog.findDeferredTool(toolName), isNull);
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
    availableTools: const <AiToolDefinition>[
      AiToolDefinition(
        name: 'Write',
        description: '写入文件。',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
        },
      ),
    ],
    planModeRecoveryInspectionRequired: false,
  );
}

List<String> _systemContents(AiPromptBuildResult result) => result.messages
    .where((message) => message.role == AiChatRole.system)
    .map((message) => message.content)
    .toList(growable: false);

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

AiModelConfig _model() => const AiModelConfig(
  id: 'model-1',
  baseUrl: 'https://gateway.example.com/v1',
  authScheme: AiAuthScheme.bearer,
  token: 'test-token',
  modelId: 'cache-test-model',
  protocolType: AiProtocolType.openai,
  providerKind: AiProviderKind.openai,
);

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
  mcpLazyLoadingMode: McpLazyLoadingMode.enabled,
);

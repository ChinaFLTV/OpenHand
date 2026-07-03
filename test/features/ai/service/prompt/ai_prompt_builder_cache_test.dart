import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_allow_command_rule.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_sections.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/instructions/index.dart';
import 'package:openhand/features/mcp/index.dart';
import 'package:openhand/features/memory/index.dart';

void main() {
  test('tool catalog order is stable when normalized names collide', () {
    final dashTool = _tool('Read-File', 'Dash variant.');
    final underscoreTool = _tool('Read_File', 'Underscore variant.');

    final first = _buildPrompt(<AiToolDefinition>[dashTool, underscoreTool]);
    final second = _buildPrompt(<AiToolDefinition>[underscoreTool, dashTool]);
    final firstCatalog = _toolCatalogText(first);
    final secondCatalog = _toolCatalogText(second);

    expect(firstCatalog, secondCatalog);
    expect(
      first.metadata['stable_prefix_hash'],
      second.metadata['stable_prefix_hash'],
    );
    expect(
      firstCatalog.indexOf('- Read-File:'),
      lessThan(firstCatalog.indexOf('- Read_File:')),
    );
  });

  test('tool catalog argument order is stable across schema map order', () {
    final alphaFirstTool = _toolWithParameters('SchemaProbe', <String, Object?>{
      'alpha': const <String, Object?>{'type': 'string'},
      'zeta': const <String, Object?>{'type': 'string'},
    });
    final zetaFirstTool = _toolWithParameters('SchemaProbe', <String, Object?>{
      'zeta': const <String, Object?>{'type': 'string'},
      'alpha': const <String, Object?>{'type': 'string'},
    });

    final first = _buildPrompt(<AiToolDefinition>[alphaFirstTool]);
    final second = _buildPrompt(<AiToolDefinition>[zetaFirstTool]);
    final firstCatalog = _toolCatalogText(first);
    final secondCatalog = _toolCatalogText(second);

    expect(firstCatalog, secondCatalog);
    expect(
      first.metadata['stable_prefix_hash'],
      second.metadata['stable_prefix_hash'],
    );
    expect(firstCatalog, contains('Args: alpha, zeta.'));
  });

  test('post-compact MCP restore context has stable ordering', () {
    final longPrefixTool = _tool(
      'mcp__alpha__beta__inspect',
      'Long-prefix MCP tool.',
    );
    final shortPrefixTool = _tool('mcp__alpha__list', 'Short-prefix MCP tool.');
    final first = _buildPrompt(
      <AiToolDefinition>[longPrefixTool, shortPrefixTool],
      session: _compressedSession(),
      runtimeContext: _runtimeContext(
        availableMcpServers: const <McpServer>[
          McpServer(
            name: 'alpha',
            type: McpServerType.stdio,
            enabled: true,
            command: 'alpha',
          ),
          McpServer(
            name: 'alpha__beta',
            type: McpServerType.stdio,
            enabled: true,
            command: 'alpha-beta',
          ),
        ],
      ),
    );
    final second = _buildPrompt(
      <AiToolDefinition>[shortPrefixTool, longPrefixTool],
      session: _compressedSession(),
      runtimeContext: _runtimeContext(
        availableMcpServers: const <McpServer>[
          McpServer(
            name: 'alpha__beta',
            type: McpServerType.stdio,
            enabled: true,
            command: 'alpha-beta',
          ),
          McpServer(
            name: 'alpha',
            type: McpServerType.stdio,
            enabled: true,
            command: 'alpha',
          ),
        ],
      ),
    );
    final firstRestoredMcp = _sectionText(
      first,
      AiPromptSectionHeaders.restoredMcpContext,
    );
    final secondRestoredMcp = _sectionText(
      second,
      AiPromptSectionHeaders.restoredMcpContext,
    );

    expect(firstRestoredMcp, secondRestoredMcp);
    expect(
      first.metadata['stable_prefix_hash'],
      second.metadata['stable_prefix_hash'],
    );
    expect(
      firstRestoredMcp.indexOf('### alpha__beta'),
      lessThan(firstRestoredMcp.indexOf('- mcp__alpha__beta__inspect:')),
    );
  });

  test('post-compact dynamic MCP rehydration has stable ordering', () {
    final first = _buildPrompt(
      const <AiToolDefinition>[],
      session: _compressedSession(),
      runtimeContext: _runtimeContext(
        availableMcpServers: const <McpServer>[
          McpServer(
            name: 'zeta',
            type: McpServerType.stdio,
            enabled: true,
            command: 'zeta',
          ),
          McpServer(
            name: 'alpha',
            type: McpServerType.stdio,
            enabled: true,
            command: 'alpha',
          ),
        ],
      ),
      mcpServerInstructionsByName: const <String, String>{
        'zeta': 'Zeta instruction',
        'alpha': 'Alpha instruction',
      },
    );
    final second = _buildPrompt(
      const <AiToolDefinition>[],
      session: _compressedSession(),
      runtimeContext: _runtimeContext(
        availableMcpServers: const <McpServer>[
          McpServer(
            name: 'alpha',
            type: McpServerType.stdio,
            enabled: true,
            command: 'alpha',
          ),
          McpServer(
            name: 'zeta',
            type: McpServerType.stdio,
            enabled: true,
            command: 'zeta',
          ),
        ],
      ),
      mcpServerInstructionsByName: const <String, String>{
        'alpha': 'Alpha instruction',
        'zeta': 'Zeta instruction',
      },
    );
    final firstDynamic = _runtimeSectionText(
      first,
      AiPromptSectionHeaders.dynamicSessionState,
    );
    final secondDynamic = _runtimeSectionText(
      second,
      AiPromptSectionHeaders.dynamicSessionState,
    );

    expect(firstDynamic, secondDynamic);
    expect(
      firstDynamic.indexOf('"alpha"'),
      lessThan(firstDynamic.indexOf('"zeta"')),
    );
  });

  test('reverse runtime metadata maps are stable across key order', () {
    final first = _buildPrompt(
      const <AiToolDefinition>[],
      session: _compressedSession(
        templateId: AiPromptTemplatePolicies.webReverseExpertTemplateId,
        metadata: const <String, Object?>{
          'web_reverse_config': <String, Object?>{
            'zeta': <String, Object?>{'tail': true, 'alpha': 1},
            'alpha': <String, Object?>{'zeta': 2, 'alpha': 1},
          },
        },
      ),
      templateId: AiPromptTemplatePolicies.webReverseExpertTemplateId,
    );
    final second = _buildPrompt(
      const <AiToolDefinition>[],
      session: _compressedSession(
        templateId: AiPromptTemplatePolicies.webReverseExpertTemplateId,
        metadata: const <String, Object?>{
          'web_reverse_config': <String, Object?>{
            'alpha': <String, Object?>{'alpha': 1, 'zeta': 2},
            'zeta': <String, Object?>{'alpha': 1, 'tail': true},
          },
        },
      ),
      templateId: AiPromptTemplatePolicies.webReverseExpertTemplateId,
    );
    final firstDynamic = _runtimeSectionText(
      first,
      AiPromptSectionHeaders.dynamicSessionState,
    );
    final secondDynamic = _runtimeSectionText(
      second,
      AiPromptSectionHeaders.dynamicSessionState,
    );

    expect(firstDynamic, secondDynamic);
    expect(
      firstDynamic.indexOf('"alpha"'),
      lessThan(firstDynamic.indexOf('"zeta"')),
    );
  });

  test('user memory rendering is stable across entry and tag order', () {
    final newerMemoryCreatedAt = DateTime.utc(2026, 1, 3);
    final olderMemoryCreatedAt = DateTime.utc(2026, 1, 2);
    final newerProfileCreatedAt = DateTime.utc(2026, 1, 4);
    final olderProfileCreatedAt = DateTime.utc(2026);
    final firstEntries = <UserMemoryEntry>[
      _memory(
        id: 'mem-new',
        createdAt: newerMemoryCreatedAt,
        content: 'Prefers concise output.',
        tags: const <String>['Work', 'ai'],
      ),
      _memory(
        id: 'profile-old',
        type: UserMemoryEntry.userProfileType,
        createdAt: olderProfileCreatedAt,
        content: 'Older profile.',
      ),
      _memory(
        id: 'profile-new',
        type: UserMemoryEntry.userProfileType,
        createdAt: newerProfileCreatedAt,
        content: 'Prefers precise engineering answers.',
      ),
      _memory(
        id: 'mem-old',
        createdAt: olderMemoryCreatedAt,
        content: 'Uses Flutter.',
        tags: const <String>['mobile', 'Work'],
      ),
    ];
    final secondEntries = <UserMemoryEntry>[
      _memory(
        id: 'mem-old',
        createdAt: olderMemoryCreatedAt,
        content: 'Uses Flutter.',
        tags: const <String>['Work', 'mobile'],
      ),
      _memory(
        id: 'profile-new',
        type: UserMemoryEntry.userProfileType,
        createdAt: newerProfileCreatedAt,
        content: 'Prefers precise engineering answers.',
      ),
      _memory(
        id: 'mem-new',
        createdAt: newerMemoryCreatedAt,
        content: 'Prefers concise output.',
        tags: const <String>['ai', 'Work'],
      ),
      _memory(
        id: 'profile-old',
        type: UserMemoryEntry.userProfileType,
        createdAt: olderProfileCreatedAt,
        content: 'Older profile.',
      ),
    ];

    final first = _buildPrompt(
      const <AiToolDefinition>[],
      memoryEnabled: true,
      memoryEntries: firstEntries,
    );
    final second = _buildPrompt(
      const <AiToolDefinition>[],
      memoryEnabled: true,
      memoryEntries: secondEntries,
    );
    final firstMemory = _sectionText(first, AiPromptSectionHeaders.userMemory);
    final secondMemory = _sectionText(
      second,
      AiPromptSectionHeaders.userMemory,
    );

    expect(firstMemory, secondMemory);
    expect(
      first.metadata['stable_prefix_hash'],
      second.metadata['stable_prefix_hash'],
    );
    expect(
      firstMemory,
      contains('## User Profile\nPrefers precise engineering answers.\n\n'),
    );
    expect(firstMemory, contains('- Prefers concise output. (tags: ai, Work)'));
    expect(
      firstMemory.indexOf('- Prefers concise output.'),
      lessThan(firstMemory.indexOf('- Uses Flutter.')),
    );
  });

  test(
    'user instructions rendering is stable across entry and metadata order',
    () {
      final firstCreatedAt = DateTime.utc(2026);
      final secondCreatedAt = DateTime.utc(2026, 1, 2);
      final firstInstructions = <UserInstructionEntry>[
        _instruction(
          id: 'deploy',
          name: 'Deploy',
          body: 'Use staging first.',
          sortOrder: 2,
          createdAt: secondCreatedAt,
          taskTypes: const <String>['Release', 'build'],
          keywords: const <String>['Flutter', 'CI'],
        ),
        _instruction(
          id: 'style',
          name: 'Style',
          body: 'Be concise.',
          sortOrder: 1,
          createdAt: firstCreatedAt,
          taskTypes: const <String>['review', 'Refactor'],
          keywords: const <String>['prompt', 'Cache'],
        ),
      ];
      final secondInstructions = <UserInstructionEntry>[
        _instruction(
          id: 'style',
          name: 'Style',
          body: 'Be concise.',
          sortOrder: 1,
          createdAt: firstCreatedAt,
          taskTypes: const <String>['Refactor', 'review'],
          keywords: const <String>['Cache', 'prompt'],
        ),
        _instruction(
          id: 'deploy',
          name: 'Deploy',
          body: 'Use staging first.',
          sortOrder: 2,
          createdAt: secondCreatedAt,
          taskTypes: const <String>['build', 'Release'],
          keywords: const <String>['CI', 'Flutter'],
        ),
      ];

      final first = _buildPrompt(
        const <AiToolDefinition>[],
        userInstructions: firstInstructions,
      );
      final second = _buildPrompt(
        const <AiToolDefinition>[],
        userInstructions: secondInstructions,
      );
      final firstInstructionsText = _sectionText(
        first,
        AiPromptSectionHeaders.userInstructions,
      );
      final secondInstructionsText = _sectionText(
        second,
        AiPromptSectionHeaders.userInstructions,
      );

      expect(firstInstructionsText, secondInstructionsText);
      expect(
        first.metadata['stable_prefix_hash'],
        second.metadata['stable_prefix_hash'],
      );
      expect(
        firstInstructionsText.indexOf('## 1. Style'),
        lessThan(firstInstructionsText.indexOf('## 2. Deploy')),
      );
      expect(firstInstructionsText, contains('- taskTypes: build, Release'));
      expect(firstInstructionsText, contains('- keywords: CI, Flutter'));
    },
  );

  test('allow command rules are stable across settings order', () {
    final first = _buildPrompt(
      const <AiToolDefinition>[],
      allowCommandRules: const <AiAllowCommandRule>[
        AiAllowCommandRule(
          id: 'z-rule',
          pattern: 'pnpm *',
          matchMode: AiDenyCommandMatchMode.simple,
          note: 'package scripts',
        ),
        AiAllowCommandRule(
          id: 'a-rule',
          pattern: r'^flutter test\b',
          matchMode: AiDenyCommandMatchMode.regex,
          note: 'tests',
        ),
        AiAllowCommandRule(
          id: 'empty-rule',
          pattern: ' ',
          matchMode: AiDenyCommandMatchMode.simple,
        ),
      ],
    );
    final second = _buildPrompt(
      const <AiToolDefinition>[],
      allowCommandRules: const <AiAllowCommandRule>[
        AiAllowCommandRule(
          id: 'empty-rule',
          pattern: ' ',
          matchMode: AiDenyCommandMatchMode.simple,
        ),
        AiAllowCommandRule(
          id: 'z-rule',
          pattern: ' pnpm * ',
          matchMode: AiDenyCommandMatchMode.simple,
          note: ' package scripts ',
        ),
        AiAllowCommandRule(
          id: 'a-rule',
          pattern: r'^flutter test\b',
          matchMode: AiDenyCommandMatchMode.regex,
          note: ' tests ',
        ),
      ],
    );
    final firstStatic = _sectionText(
      first,
      AiPromptSectionHeaders.staticSessionState,
    );
    final secondStatic = _sectionText(
      second,
      AiPromptSectionHeaders.staticSessionState,
    );

    expect(firstStatic, secondStatic);
    expect(
      first.metadata['stable_prefix_hash'],
      second.metadata['stable_prefix_hash'],
    );
    expect(firstStatic, contains(r'regex:^flutter test\\b (tests)'));
    expect(firstStatic, contains('simple:pnpm * (package scripts)'));
    expect(firstStatic, isNot(contains('empty-rule')));
  });

  test(
    'post-compact task tool listing is stable across resolved tool order',
    () {
      final alphaTask = _resolvedTaskTool('Task_Alpha');
      final zetaTask = _resolvedTaskTool('Task_Zeta');
      final first = _buildPrompt(
        const <AiToolDefinition>[],
        session: _compressedSession(),
        resolvedToolsByName: <String, AiResolvedTool>{
          zetaTask.name: zetaTask,
          alphaTask.name: alphaTask,
        },
      );
      final second = _buildPrompt(
        const <AiToolDefinition>[],
        session: _compressedSession(),
        resolvedToolsByName: <String, AiResolvedTool>{
          alphaTask.name: alphaTask,
          zetaTask.name: zetaTask,
        },
      );
      final firstListing = _sectionText(
        first,
        AiPromptSectionHeaders.restoredToolAndAgentListing,
      );
      final secondListing = _sectionText(
        second,
        AiPromptSectionHeaders.restoredToolAndAgentListing,
      );

      expect(firstListing, secondListing);
      expect(
        first.metadata['stable_prefix_hash'],
        second.metadata['stable_prefix_hash'],
      );
      expect(firstListing, contains('- Task tool: Task_Alpha'));
    },
  );
}

AiPromptBuildResult _buildPrompt(
  List<AiToolDefinition> tools, {
  AiSession? session,
  AiSessionRuntimeContext? runtimeContext,
  bool memoryEnabled = false,
  List<UserMemoryEntry> memoryEntries = const <UserMemoryEntry>[],
  List<UserInstructionEntry> userInstructions = const <UserInstructionEntry>[],
  List<AiAllowCommandRule> allowCommandRules = const <AiAllowCommandRule>[],
  Map<String, AiResolvedTool> resolvedToolsByName =
      const <String, AiResolvedTool>{},
  Map<String, String> mcpServerInstructionsByName = const <String, String>{},
  String templateId = AiPromptTemplatePolicies.defaultTemplateId,
}) {
  final now = DateTime.utc(2026);
  final userMessage = AiSessionMessage.user(
    id: 'user-1',
    content: '测试工具目录排序',
    createdAt: now,
  );
  final effectiveSession =
      session ?? _session(messages: <AiSessionMessage>[userMessage], now: now);
  return const AiPromptBuilder().buildSessionPrompt(
    templateBundle: _templateBundle(templateId: templateId),
    session: effectiveSession,
    model: _model(),
    runtimeContext:
        runtimeContext ??
        _runtimeContext(
          memoryEnabled: memoryEnabled,
          memoryEntries: memoryEntries,
          userInstructions: userInstructions,
          allowCommandRules: allowCommandRules,
        ),
    memoryEntries: memoryEntries,
    sessionMessages: effectiveSession.messages,
    latestUserMessageId: 'user-1',
    availableTools: tools,
    resolvedToolsByName: resolvedToolsByName,
    displayCatalogOverride: tools,
    mcpServerInstructionsByName: mcpServerInstructionsByName,
  );
}

AiResolvedTool _resolvedTaskTool(String name) {
  return AiResolvedTool(
    name: name,
    definition: _tool(name, 'Task tool.'),
    source: AiRuntimeToolSource.builtin,
    builtinKind: AiBuiltinToolKind.task,
  );
}

UserInstructionEntry _instruction({
  required String id,
  required String name,
  required String body,
  required int sortOrder,
  required DateTime createdAt,
  List<String> taskTypes = const <String>[],
  List<String> keywords = const <String>[],
}) {
  return UserInstructionEntry(
    id: id,
    name: name,
    body: body,
    createdAt: createdAt,
    updatedAt: createdAt,
    sortOrder: sortOrder,
    taskTypes: taskTypes,
    keywords: keywords,
  );
}

UserMemoryEntry _memory({
  required String id,
  String type = UserMemoryEntry.userType,
  required DateTime createdAt,
  required String content,
  List<String> tags = const <String>[],
}) {
  return UserMemoryEntry(
    id: id,
    type: type,
    createdAt: createdAt,
    content: content,
    tags: tags,
  );
}

AiSession _compressedSession({
  String templateId = AiPromptTemplatePolicies.defaultTemplateId,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  final now = DateTime.utc(2026);
  return _session(
    messages: <AiSessionMessage>[
      AiSessionMessage.compressionPoint(
        id: 'compact-1',
        content: 'Checkpoint',
        createdAt: now,
        metadata: const <String, Object?>{},
      ),
      AiSessionMessage.user(
        id: 'user-1',
        content: '继续',
        createdAt: now.add(const Duration(seconds: 1)),
      ),
    ],
    now: now,
    templateId: templateId,
    metadata: metadata,
  );
}

AiSession _session({
  required List<AiSessionMessage> messages,
  required DateTime now,
  String templateId = AiPromptTemplatePolicies.defaultTemplateId,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return AiSession(
    id: 'session-1',
    title: 'cache test',
    templateId: templateId,
    templateName: _templateName(templateId),
    templateIconName: 'auto_awesome_rounded',
    templateInternalVersion: 'test',
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: _environment(),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
    metadata: metadata,
  );
}

AiToolDefinition _tool(String name, String description) {
  return AiToolDefinition(
    name: name,
    description: description,
    parameters: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  );
}

AiToolDefinition _toolWithParameters(
  String name,
  Map<String, Object?> properties,
) {
  return AiToolDefinition(
    name: name,
    description: 'Schema order probe.',
    parameters: <String, Object?>{
      'type': 'object',
      'properties': properties,
      'required': const <String>['zeta', 'alpha'],
    },
  );
}

String _toolCatalogText(AiPromptBuildResult result) {
  return _sectionText(result, AiPromptSectionHeaders.toolCatalog);
}

String _sectionText(AiPromptBuildResult result, String header) {
  return result.messages
      .firstWhere(
        (turn) =>
            turn.role == AiChatRole.system && turn.content.startsWith(header),
      )
      .content;
}

String _runtimeSectionText(AiPromptBuildResult result, String header) {
  return result.messages
      .firstWhere((turn) => turn.content.contains(header))
      .content;
}

AiPromptTemplateBundle _templateBundle({
  String templateId = AiPromptTemplatePolicies.defaultTemplateId,
}) {
  return AiPromptTemplateBundle(
    template: AiThreadTemplate(
      id: templateId,
      name: _templateName(templateId),
      iconName: 'auto_awesome_rounded',
      description: 'Default test template',
      internalVersion: 'test',
      promptAssetDirectory: _templatePromptAssetDirectory(templateId),
    ),
    systemInstructions: 'System',
    developerInstructions: 'Developer',
    compressionSummaryInstructions: 'Compression',
  );
}

String _templateName(String templateId) {
  return switch (templateId) {
    AiPromptTemplatePolicies.webReverseExpertTemplateId => 'Web Reverse',
    AiPromptTemplatePolicies.androidReverseExpertTemplateId =>
      'Android Reverse',
    _ => 'Default',
  };
}

String _templatePromptAssetDirectory(String templateId) {
  return switch (templateId) {
    AiPromptTemplatePolicies.webReverseExpertTemplateId =>
      AiPromptTemplatePolicies.webReverseExpertPromptAssetDirectory,
    AiPromptTemplatePolicies.androidReverseExpertTemplateId =>
      AiPromptTemplatePolicies.androidReverseExpertPromptAssetDirectory,
    _ => AiPromptTemplatePolicies.defaultPromptAssetDirectory,
  };
}

AiSessionRuntimeContext _runtimeContext({
  List<McpServer> availableMcpServers = const <McpServer>[],
  bool memoryEnabled = false,
  List<UserMemoryEntry> memoryEntries = const <UserMemoryEntry>[],
  List<UserInstructionEntry> userInstructions = const <UserInstructionEntry>[],
  List<AiAllowCommandRule> allowCommandRules = const <AiAllowCommandRule>[],
}) {
  return AiSessionRuntimeContext(
    localeTag: 'zh-Hans',
    appVersion: 'test',
    appBuildNumber: '1',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.json',
    compressionThresholdChars: 100000,
    memoryEnabled: memoryEnabled,
    memoryEntries: memoryEntries,
    platformName: 'test',
    workingDirectory: '/tmp/openhand-test',
    timeZoneName: 'UTC',
    availableMcpServers: availableMcpServers,
    userInstructions: userInstructions,
    allowCommandRules: allowCommandRules,
  );
}

AiSessionEnvironment _environment() {
  return const AiSessionEnvironment(
    localeTag: 'zh-Hans',
    platform: 'test',
    appVersion: 'test',
    appBuildNumber: '1',
    applicationDirectory: '/tmp/openhand',
    homeDirectory: '/tmp',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.json',
    sessionsDirectoryPath: '/tmp/sessions',
    compressionThresholdChars: 100000,
  );
}

AiModelConfig _model() {
  return const AiModelConfig(
    id: 'model-1',
    baseUrl: 'https://example.invalid',
    authScheme: AiAuthScheme.bearer,
    token: 'token',
    modelId: 'test-model',
    protocolType: AiProtocolType.openai,
    maxTokens: 1024,
  );
}

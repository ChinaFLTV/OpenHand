import 'package:flutter_test/flutter_test.dart';
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
import 'package:openhand/features/mcp/index.dart';

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
}

AiPromptBuildResult _buildPrompt(
  List<AiToolDefinition> tools, {
  AiSession? session,
  AiSessionRuntimeContext? runtimeContext,
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
    templateBundle: _templateBundle(),
    session: effectiveSession,
    model: _model(),
    runtimeContext: runtimeContext ?? _runtimeContext(),
    memoryEntries: const [],
    sessionMessages: effectiveSession.messages,
    latestUserMessageId: 'user-1',
    availableTools: tools,
    displayCatalogOverride: tools,
  );
}

AiSession _compressedSession() {
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
  );
}

AiSession _session({
  required List<AiSessionMessage> messages,
  required DateTime now,
}) {
  return AiSession(
    id: 'session-1',
    title: 'cache test',
    templateId: AiPromptTemplatePolicies.defaultTemplateId,
    templateName: 'Default',
    templateIconName: 'auto_awesome_rounded',
    templateInternalVersion: 'test',
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: _environment(),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
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

AiPromptTemplateBundle _templateBundle() {
  return const AiPromptTemplateBundle(
    template: AiThreadTemplate(
      id: AiPromptTemplatePolicies.defaultTemplateId,
      name: 'Default',
      iconName: 'auto_awesome_rounded',
      description: 'Default test template',
      internalVersion: 'test',
      promptAssetDirectory:
          AiPromptTemplatePolicies.defaultPromptAssetDirectory,
    ),
    systemInstructions: 'System',
    developerInstructions: 'Developer',
    compressionSummaryInstructions: 'Compression',
  );
}

AiSessionRuntimeContext _runtimeContext({
  List<McpServer> availableMcpServers = const <McpServer>[],
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
    memoryEnabled: false,
    memoryEntries: [],
    platformName: 'test',
    workingDirectory: '/tmp/openhand-test',
    timeZoneName: 'UTC',
    availableMcpServers: availableMcpServers,
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

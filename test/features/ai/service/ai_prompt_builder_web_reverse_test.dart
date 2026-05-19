import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';

void main() {
  test(
    'includes Web Reverse CDP runtime and current target in prompt state',
    () {
      final now = DateTime.utc(2026, 5, 19);
      final latestUserMessage = AiSessionMessage.user(
        id: 'user-1',
        content: 'Start reversing https://example.test',
        createdAt: now,
      );
      final session = _webReverseSession(
        now: now,
        latestUserMessage: latestUserMessage,
        metadata: const <String, Object?>{
          'web_reverse_config': <String, Object?>{
            'target_url': 'https://example.test',
            'cdp_port': 9222,
          },
          'web_reverse_cdp_runtime': <String, Object?>{
            'cdp_port': 9233,
            'cdp_http_endpoint': 'http://127.0.0.1:9233',
            'json_list_url': 'http://127.0.0.1:9233/json/list',
            'browser_alive': true,
            'current_target': <String, Object?>{
              'id': 'target-1',
              'url': 'https://example.test/app',
              'title': 'Example App',
            },
          },
          'web_reverse_browser_current_target': <String, Object?>{
            'id': 'target-1',
            'url': 'https://example.test/app',
            'title': 'Example App',
          },
        },
      );

      final result = _buildWebReversePrompt(session, latestUserMessage);

      final webReverseRuntime = result.metadata['web_reverse_runtime'];
      expect(webReverseRuntime, isA<Map<String, Object?>>());
      final runtimeMap = webReverseRuntime! as Map<String, Object?>;
      expect(runtimeMap['cdp_first_required'], true);
      final availability =
          runtimeMap['cdp_mcp_tool_availability']! as Map<String, Object?>;
      expect(availability['browser_runtime_live'], true);
      expect(availability['current_turn_callable'], false);
      expect(availability['live_cdp_actions_current_turn_callable'], false);
      expect(availability['warning'], contains('Do not invent cdp_*'));
      expect(runtimeMap['config'], containsPair('desired_cdp_port', 9222));
      expect(runtimeMap['config'], isNot(contains('cdp_port')));
      expect(
        runtimeMap['dashboard_visible_metadata_keys'],
        containsAll(<String>[
          'web_reverse_browser_current_target',
          'web_reverse_cdp_runtime',
          'web_reverse_config',
        ]),
      );
      expect(
        runtimeMap['cdp_runtime'],
        containsPair('json_list_url', 'http://127.0.0.1:9233/json/list'),
      );
      expect(
        runtimeMap['cdp_runtime'],
        containsPair(
          'current_target',
          containsPair('url', 'https://example.test/app'),
        ),
      );
      expect(
        runtimeMap['dashboard_state'],
        containsPair(
          'browser_current_target',
          containsPair('url', 'https://example.test/app'),
        ),
      );

      final sessionStateText = result.messages
          .map((turn) => turn.content)
          .firstWhere((content) => content.contains('# [3] Session State'));
      expect(sessionStateText, contains('"cdp_runtime"'));
      expect(sessionStateText, contains('http://127.0.0.1:9233/json/list'));
      expect(sessionStateText, contains('"browser_current_target"'));

      final fullPromptText = result.messages
          .map((turn) => turn.content)
          .join('\n');
      expect(fullPromptText, isNot(contains('OpenHand CDP Bridge')));
      expect(fullPromptText, isNot(contains('CDP Bridge')));
    },
  );

  test('marks callable CDP MCP tools in Web Reverse runtime state', () {
    final now = DateTime.utc(2026, 5, 19);
    final latestUserMessage = AiSessionMessage.user(
      id: 'user-1',
      content: 'Start reversing https://example.test',
      createdAt: now,
    );
    final session = _webReverseSession(
      now: now,
      latestUserMessage: latestUserMessage,
      metadata: const <String, Object?>{
        'web_reverse_config': <String, Object?>{
          'target_url': 'https://example.test',
          'cdp_port': 9222,
        },
        'web_reverse_cdp_runtime': <String, Object?>{
          'cdp_port': 9233,
          'browser_alive': true,
        },
      },
    );
    final cdpTool = _mcpTool(
      catalogName: 'mcp__chrome_devtools__navigate_page',
      toolName: 'navigate_page',
      description: 'Navigate a Chrome DevTools Protocol page target.',
    );

    final result = _buildWebReversePrompt(
      session,
      latestUserMessage,
      availableTools: <AiToolDefinition>[cdpTool.definition],
      resolvedToolsByName: <String, AiResolvedTool>{cdpTool.name: cdpTool},
    );

    final runtimeMap =
        result.metadata['web_reverse_runtime']! as Map<String, Object?>;
    final availability =
        runtimeMap['cdp_mcp_tool_availability']! as Map<String, Object?>;
    expect(availability['browser_runtime_live'], true);
    expect(availability['current_turn_callable'], true);
    expect(availability['live_cdp_actions_current_turn_callable'], true);
    expect(availability['current_turn_callable_count'], 1);
    expect(
      availability['current_turn_callable_names'],
      contains('mcp__chrome_devtools__navigate_page'),
    );
    expect(availability, isNot(contains('warning')));
  });

  test('points Web Reverse to ToolSearch when CDP MCP tools are deferred', () {
    final now = DateTime.utc(2026, 5, 19);
    final latestUserMessage = AiSessionMessage.user(
      id: 'user-1',
      content: 'Start reversing https://example.test',
      createdAt: now,
    );
    final session = _webReverseSession(
      now: now,
      latestUserMessage: latestUserMessage,
      metadata: const <String, Object?>{
        'web_reverse_config': <String, Object?>{
          'target_url': 'https://example.test',
          'cdp_port': 9222,
        },
        'web_reverse_cdp_runtime': <String, Object?>{
          'cdp_port': 9233,
          'browser_alive': true,
        },
      },
    );
    final deferredCdpTool = _mcpTool(
      catalogName: 'mcp__chrome_devtools__navigate_page',
      toolName: 'navigate_page',
      description: 'Navigate a Chrome DevTools Protocol page target.',
    );
    final toolSearch = _toolSearchTool(<String, AiToolDefinition>{
      deferredCdpTool.name: deferredCdpTool.definition,
    });

    final result = _buildWebReversePrompt(
      session,
      latestUserMessage,
      availableTools: <AiToolDefinition>[toolSearch.definition],
      resolvedToolsByName: <String, AiResolvedTool>{
        toolSearch.name: toolSearch,
      },
    );

    final runtimeMap =
        result.metadata['web_reverse_runtime']! as Map<String, Object?>;
    final availability =
        runtimeMap['cdp_mcp_tool_availability']! as Map<String, Object?>;
    expect(availability['browser_runtime_live'], true);
    expect(availability['current_turn_callable'], false);
    expect(availability['live_cdp_actions_current_turn_callable'], false);
    expect(availability['tool_search_available'], true);
    expect(availability['tool_search_deferred_cdp_mcp_count'], 1);
    expect(
      availability['tool_search_deferred_cdp_mcp_names'],
      contains('mcp__chrome_devtools__navigate_page'),
    );
    expect(
      availability['tool_search_recommended_query'],
      'select:mcp__chrome_devtools__navigate_page',
    );
    expect(availability['guidance'], contains('call ToolSearch'));
    expect(availability, isNot(contains('warning')));
  });

  test(
    'strips live CDP endpoints and marks targets last when browser is dead',
    () {
      final now = DateTime.utc(2026, 5, 19);
      final latestUserMessage = AiSessionMessage.user(
        id: 'user-1',
        content: 'Continue reversing https://example.test',
        createdAt: now,
      );
      final session = _webReverseSession(
        now: now,
        latestUserMessage: latestUserMessage,
        metadata: const <String, Object?>{
          'web_reverse_config': <String, Object?>{
            'target_url': 'https://example.test',
            'cdp_port': 9222,
          },
          'web_reverse_cdp_runtime': <String, Object?>{
            'cdp_port': 9233,
            'cdp_host': '127.0.0.1',
            'cdp_http_endpoint': 'http://127.0.0.1:9233',
            'json_version_url': 'http://127.0.0.1:9233/json/version',
            'json_list_url': 'http://127.0.0.1:9233/json/list',
            'browser_alive': false,
            'is_running': false,
            'current_target': <String, Object?>{
              'id': 'target-old',
              'url': 'https://example.test/old-tab',
              'title': 'Old Tab',
            },
          },
          'web_reverse_browser_current_target': <String, Object?>{
            'id': 'target-old',
            'url': 'https://example.test/old-tab',
            'title': 'Old Tab',
          },
        },
      );

      final result = _buildWebReversePrompt(session, latestUserMessage);

      final runtimeMap =
          result.metadata['web_reverse_runtime']! as Map<String, Object?>;
      final cdpRuntime = runtimeMap['cdp_runtime']! as Map<String, Object?>;
      final availability =
          runtimeMap['cdp_mcp_tool_availability']! as Map<String, Object?>;
      expect(
        runtimeMap['cdp_runtime_warning'],
        contains('historical last_* values only'),
      );
      expect(
        runtimeMap['fallback_policy'],
        contains('Live CDP MCP actions require browser_alive=true'),
      );
      expect(availability['browser_runtime_live'], false);
      expect(availability['live_cdp_actions_current_turn_callable'], false);
      expect(
        availability['runtime_liveness_blocker'],
        contains('Tool availability alone is not enough'),
      );
      expect(runtimeMap['config'], containsPair('desired_cdp_port', 9222));
      expect(runtimeMap['config'], isNot(contains('cdp_port')));
      expect(cdpRuntime['browser_alive'], false);
      expect(cdpRuntime['is_running'], false);
      expect(cdpRuntime['last_cdp_port'], 9233);
      expect(
        cdpRuntime['last_current_target'],
        containsPair('url', 'https://example.test/old-tab'),
      );
      expect(cdpRuntime, isNot(contains('cdp_port')));
      expect(cdpRuntime, isNot(contains('cdp_http_endpoint')));
      expect(cdpRuntime, isNot(contains('json_version_url')));
      expect(cdpRuntime, isNot(contains('json_list_url')));
      expect(cdpRuntime, isNot(contains('current_target')));
      final dashboardState =
          runtimeMap['dashboard_state']! as Map<String, Object?>;
      expect(
        dashboardState['browser_last_current_target'],
        containsPair('url', 'https://example.test/old-tab'),
      );
      expect(dashboardState, isNot(contains('browser_current_target')));

      final promptText = result.messages.map((turn) => turn.content).join('\n');
      expect(promptText, contains('"browser_alive": false'));
      expect(promptText, contains('"last_cdp_port": 9233'));
      expect(promptText, contains('"last_current_target"'));
      expect(promptText, contains('historical last_* values only'));
      expect(promptText, isNot(contains('http://127.0.0.1:9233')));
    },
  );

  test(
    'blocks live CDP actions when browser is dead even if tool is visible',
    () {
      final now = DateTime.utc(2026, 5, 19);
      final latestUserMessage = AiSessionMessage.user(
        id: 'user-1',
        content: 'Continue reversing https://example.test',
        createdAt: now,
      );
      final session = _webReverseSession(
        now: now,
        latestUserMessage: latestUserMessage,
        metadata: const <String, Object?>{
          'web_reverse_config': <String, Object?>{
            'target_url': 'https://example.test',
            'cdp_port': 9222,
          },
          'web_reverse_cdp_runtime': <String, Object?>{
            'cdp_port': 9233,
            'browser_alive': false,
          },
        },
      );
      final cdpTool = _mcpTool(
        catalogName: 'mcp__chrome_devtools__navigate_page',
        toolName: 'navigate_page',
        description: 'Navigate a Chrome DevTools Protocol page target.',
      );

      final result = _buildWebReversePrompt(
        session,
        latestUserMessage,
        availableTools: <AiToolDefinition>[cdpTool.definition],
        resolvedToolsByName: <String, AiResolvedTool>{cdpTool.name: cdpTool},
      );

      final runtimeMap =
          result.metadata['web_reverse_runtime']! as Map<String, Object?>;
      final availability =
          runtimeMap['cdp_mcp_tool_availability']! as Map<String, Object?>;
      expect(availability['current_turn_callable'], true);
      expect(availability['browser_runtime_live'], false);
      expect(availability['live_cdp_actions_current_turn_callable'], false);
      expect(availability['guidance'], contains('do not use them for live'));
      expect(availability, contains('runtime_liveness_blocker'));
    },
  );
}

const _templateBundle = AiPromptTemplateBundle(
  template: AiThreadTemplate(
    id: 'web_reverse_expert',
    name: 'Web Reverse Expert',
    iconName: 'travel_explore_rounded',
    description: 'Reverse a browser target through CDP.',
    internalVersion: '1.1.0',
    promptAssetDirectory: 'assets/prompts/web_reverse_expert',
  ),
  systemInstructions: 'system',
  developerInstructions: 'developer',
  compressionSummaryInstructions: 'compress',
);

const _model = AiModelConfig(
  id: 'test-model',
  baseUrl: 'http://localhost/v1',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'openhand-test-model',
  protocolType: AiProtocolType.openai,
);

const _environment = AiSessionEnvironment(
  localeTag: 'zh-CN',
  platform: 'macos',
  appVersion: '0.1.0',
  appBuildNumber: '1',
  applicationDirectory: '/tmp/openhand',
  homeDirectory: '/tmp',
  settingsFilePath: '/tmp/openhand/settings.json',
  skillsStoragePath: '/tmp/openhand/skills',
  mcpServersFilePath: '/tmp/openhand/mcp_servers.json',
  userMemoryFilePath: '/tmp/openhand/memory.json',
  sessionsDirectoryPath: '/tmp/openhand/sessions',
  compressionThresholdChars: 100000,
);

const _runtimeContext = AiSessionRuntimeContext(
  localeTag: 'zh-CN',
  appVersion: '0.1.0',
  appBuildNumber: '1',
  settingsFilePath: '/tmp/openhand/settings.json',
  skillsStoragePath: '/tmp/openhand/skills',
  mcpServersFilePath: '/tmp/openhand/mcp_servers.json',
  userMemoryFilePath: '/tmp/openhand/memory.json',
  compressionThresholdChars: 100000,
  memoryEnabled: false,
  memoryEntries: <Never>[],
  templateId: 'web_reverse_expert',
  platformName: 'macos',
  workingDirectory: '/tmp/openhand',
  todayLocalDate: '2026-05-19',
  timeZoneName: 'UTC',
);

AiSession _webReverseSession({
  required DateTime now,
  required AiSessionMessage latestUserMessage,
  required Map<String, Object?> metadata,
}) {
  return AiSession(
    id: 'session-1',
    title: 'Web Reverse',
    templateId: 'web_reverse_expert',
    templateName: 'Web Reverse Expert',
    templateIconName: 'travel_explore_rounded',
    templateInternalVersion: '1.1.0',
    createdAt: now,
    updatedAt: now,
    messages: <AiSessionMessage>[latestUserMessage],
    environment: _environment,
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
    metadata: metadata,
  );
}

AiPromptBuildResult _buildWebReversePrompt(
  AiSession session,
  AiSessionMessage latestUserMessage, {
  List<AiToolDefinition> availableTools = const <AiToolDefinition>[],
  Map<String, AiResolvedTool> resolvedToolsByName =
      const <String, AiResolvedTool>{},
}) {
  return const AiPromptBuilder().buildConversationPrompt(
    templateBundle: _templateBundle,
    session: session,
    model: _model,
    runtimeContext: _runtimeContext,
    memoryEntries: const <Never>[],
    historyMessages: const <AiSessionMessage>[],
    latestUserMessage: latestUserMessage,
    availableTools: availableTools,
    resolvedToolsByName: resolvedToolsByName,
  );
}

AiResolvedTool _mcpTool({
  required String catalogName,
  required String toolName,
  required String description,
}) {
  return AiResolvedTool(
    name: catalogName,
    definition: AiToolDefinition(
      name: catalogName,
      description: description,
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    ),
    source: AiRuntimeToolSource.mcp,
    mcpServer: const McpServer(
      name: 'chrome-devtools',
      type: McpServerType.stdio,
      enabled: true,
      command: 'npx',
      args: <String>['chrome-devtools-mcp'],
    ),
    mcpTool: McpTool(
      id: toolName,
      name: toolName,
      description: description,
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    ),
  );
}

AiResolvedTool _toolSearchTool(
  Map<String, AiToolDefinition> deferredDefinitions,
) {
  return AiResolvedTool(
    name: 'ToolSearch',
    definition: const AiToolDefinition(
      name: 'ToolSearch',
      description: 'Load deferred MCP tools.',
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    ),
    source: AiRuntimeToolSource.builtin,
    builtinKind: AiBuiltinToolKind.toolSearch,
    toolSearchDeferredToolDefinitions: deferredDefinitions,
  );
}

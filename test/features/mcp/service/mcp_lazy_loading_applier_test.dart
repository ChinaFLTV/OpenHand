import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/search/ai_tool_search_tool.dart';
import 'package:openhand/features/mcp/index.dart';

void main() {
  test('keeps force-visible MCP tools in catalog and out of ToolSearch', () {
    final runtimeService = AiToolRuntimeService(
      bashToolService: AiBashToolService(),
      hookService: AiClaudeHookService(),
      mcpToolService: _FakeMcpToolDiscoveryService(),
      backgroundChatClient: _FakeChatClient(),
    );
    final catalog = AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[
        _toolSearch.definition,
        _mcpDefinition('cdp_evaluate'),
        _mcpDefinition('regular_browser_tool'),
      ],
      toolsByName: <String, AiResolvedTool>{
        'ToolSearch': _toolSearch,
        'cdp_evaluate': _mcpTool('cdp_evaluate'),
        'regular_browser_tool': _mcpTool('regular_browser_tool'),
      },
    );

    final result = McpLazyLoadingApplier.apply(
      catalog: catalog,
      runtimeContext: _runtimeContext,
      toolRuntimeService: runtimeService,
      forceVisibleNames: const <String>{'cdp_evaluate'},
    );

    expect(result.toolsByName, contains('ToolSearch'));
    expect(result.toolsByName, contains('cdp_evaluate'));
    expect(result.toolsByName, isNot(contains('regular_browser_tool')));
    expect(
      result.notices.join('\n'),
      contains('kept 1 MCP tool(s) directly visible: cdp_evaluate'),
    );

    final toolSearch = runtimeService.toolRegistry.getTool(
      AiBuiltinToolKind.toolSearch,
    );
    expect(toolSearch, isA<AiToolSearchTool>());
    final searchTool = toolSearch! as AiToolSearchTool;
    expect(searchTool.deferredToolNames, contains('regular_browser_tool'));
    expect(searchTool.deferredToolNames, isNot(contains('cdp_evaluate')));
    expect(
      searchTool.deferredToolDefinitions,
      contains('regular_browser_tool'),
    );
    expect(searchTool.deferredToolDefinitions, isNot(contains('cdp_evaluate')));
  });

  test('keeps ToolSearch-loaded MCP tools visible on next catalog build', () {
    final runtimeService = AiToolRuntimeService(
      bashToolService: AiBashToolService(),
      hookService: AiClaudeHookService(),
      mcpToolService: _FakeMcpToolDiscoveryService(),
      backgroundChatClient: _FakeChatClient(),
    );
    final catalog = AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[
        _toolSearch.definition,
        _mcpDefinition('mcp__chrome_devtools__navigate_page'),
        _mcpDefinition('mcp__browserless__playwright_run'),
      ],
      toolsByName: <String, AiResolvedTool>{
        'ToolSearch': _toolSearch,
        'mcp__chrome_devtools__navigate_page': _mcpTool(
          'mcp__chrome_devtools__navigate_page',
        ),
        'mcp__browserless__playwright_run': _mcpTool(
          'mcp__browserless__playwright_run',
        ),
      },
    );

    final result = McpLazyLoadingApplier.apply(
      catalog: catalog,
      runtimeContext: _runtimeContext,
      toolRuntimeService: runtimeService,
      alreadyLoadedNames: const <String>{'mcp__chrome_devtools__navigate_page'},
    );

    expect(result.toolsByName, contains('ToolSearch'));
    expect(result.toolsByName, contains('mcp__chrome_devtools__navigate_page'));
    expect(
      result.toolsByName,
      isNot(contains('mcp__browserless__playwright_run')),
    );

    final toolSearch = runtimeService.toolRegistry.getTool(
      AiBuiltinToolKind.toolSearch,
    );
    final searchTool = toolSearch! as AiToolSearchTool;
    expect(
      searchTool.deferredToolNames,
      isNot(contains('mcp__chrome_devtools__navigate_page')),
    );
    expect(
      searchTool.deferredToolNames,
      contains('mcp__browserless__playwright_run'),
    );
  });

  test('ToolSearch select query uses comma-separated multi-select', () {
    final tool = AiToolSearchTool()
      ..deferredToolNames = const <String>[
        'mcp__chrome_devtools__navigate_page',
        'mcp__chrome_devtools__list_network_requests',
      ];

    expect(
      tool.debugRunSearch(
        query:
            'select:mcp__chrome_devtools__navigate_page,mcp__chrome_devtools__list_network_requests',
      ),
      <String>[
        'mcp__chrome_devtools__navigate_page',
        'mcp__chrome_devtools__list_network_requests',
      ],
    );
    expect(
      tool.debugRunSearch(
        query:
            'select:mcp__chrome_devtools__navigate_page mcp__chrome_devtools__list_network_requests',
      ),
      isEmpty,
    );
  });
}

const AiResolvedTool _toolSearch = AiResolvedTool(
  name: 'ToolSearch',
  definition: AiToolDefinition(
    name: 'ToolSearch',
    description: 'Load deferred MCP tools.',
    parameters: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  ),
  source: AiRuntimeToolSource.builtin,
  builtinKind: AiBuiltinToolKind.toolSearch,
);

AiResolvedTool _mcpTool(String name) {
  return AiResolvedTool(
    name: name,
    definition: _mcpDefinition(name),
    source: AiRuntimeToolSource.mcp,
  );
}

AiToolDefinition _mcpDefinition(String name) {
  return AiToolDefinition(
    name: name,
    description: 'MCP tool $name for browser automation.',
    parameters: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  );
}

const AiSessionRuntimeContext _runtimeContext = AiSessionRuntimeContext(
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
  mcpLazyLoadingMode: McpLazyLoadingMode.enabled,
);

class _FakeMcpToolDiscoveryService implements McpToolDiscoveryService {
  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    return const McpToolCatalog();
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    return const McpServerHealth();
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
  }) async {
    return const McpToolCallResult(outputText: '');
  }

  @override
  void dispose() {}
}

class _FakeChatClient implements AiChatClient {
  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 1),
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnsupportedError('not used');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 1),
    Duration streamIdleTimeout = const Duration(seconds: 1),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnsupportedError('not used');
  }

  @override
  Future<String> testModel(AiModelConfig model) {
    throw UnsupportedError('not used');
  }

  @override
  void dispose() {}
}

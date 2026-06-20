import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/mcp/index.dart';

void main() {
  group('AiToolRuntimeService Web Reverse MCP CDP-first guard', () {
    test('blocks non-CDP browser automation MCP before dispatch', () async {
      final mcpService = _RecordingMcpService();
      final service = _runtimeService(mcpService);
      const server = McpServer(
        name: 'playwright',
        type: McpServerType.stdio,
        enabled: true,
        command: 'npx',
        args: <String>['@playwright/mcp'],
      );
      final mcpTool = _mcpTool(
        id: 'browser_navigate',
        name: 'browser_navigate',
        description: 'Navigate a Playwright browser page to a URL.',
      );
      final catalog = _catalog(server: server, mcpTool: mcpTool);

      final result = await service.execute(
        sessionId: 'session-web-reverse',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-playwright',
          name: 'mcp__playwright__browser_navigate',
          arguments: jsonEncode(<String, Object?>{
            'url': 'https://linux.do/t/topic/2401043.json',
          }),
        ),
        model: _model,
        previouslyReadFiles: const <String>{},
        denyCommandRules: const [],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
        metadata: _liveWebReverseMetadata(),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.metadata['web_reverse_mcp_blocked_for_cdp_first'], isTrue);
      expect(
        result.metadata['web_reverse_mcp_block_reason'],
        'non_cdp_browser_automation',
      );
      expect(mcpService.callCount, 0);
    });

    test('blocks target-host non-CDP MCP arguments before dispatch', () async {
      final mcpService = _RecordingMcpService();
      final service = _runtimeService(mcpService);
      const server = McpServer(
        name: 'generic_fetcher',
        type: McpServerType.stdio,
        enabled: true,
        command: 'fetcher-mcp',
      );
      final mcpTool = _mcpTool(
        id: 'fetch_url',
        name: 'fetch_url',
        description: 'Fetch the supplied URL.',
      );
      final catalog = _catalog(server: server, mcpTool: mcpTool);

      final result = await service.execute(
        sessionId: 'session-web-reverse',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-fetcher',
          name: 'mcp__generic_fetcher__fetch_url',
          arguments: jsonEncode(<String, Object?>{
            'url': 'https://linux.do/t/topic/2401043.json',
          }),
        ),
        model: _model,
        previouslyReadFiles: const <String>{},
        denyCommandRules: const [],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
        metadata: _liveWebReverseMetadata(),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.metadata['web_reverse_mcp_blocked_for_cdp_first'], isTrue);
      expect(
        result.metadata['web_reverse_requested_origin'],
        'https://linux.do',
      );
      expect(mcpService.callCount, 0);
    });

    test('allows Chrome DevTools MCP target navigation', () async {
      final mcpService = _RecordingMcpService();
      final service = _runtimeService(mcpService);
      const server = McpServer(
        name: 'web_reverse_cdp_test',
        type: McpServerType.stdio,
        enabled: true,
        command: 'npx',
        args: <String>['chrome-devtools-mcp@latest'],
      );
      final mcpTool = _mcpTool(
        id: 'navigate_page',
        name: 'navigate_page',
        description: 'Navigate through Chrome DevTools Protocol.',
      );
      final catalog = _catalog(server: server, mcpTool: mcpTool);

      final result = await service.execute(
        sessionId: 'session-web-reverse',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-cdp',
          name: 'mcp__web_reverse_cdp_test__navigate_page',
          arguments: jsonEncode(<String, Object?>{
            'url': 'https://linux.do/t/topic/2401043/5',
          }),
        ),
        model: _model,
        previouslyReadFiles: const <String>{},
        denyCommandRules: const [],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
        metadata: _liveWebReverseMetadata(),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, 'ok');
      expect(mcpService.callCount, 1);
    });
  });
}

AiToolRuntimeService _runtimeService(McpToolDiscoveryService mcpService) {
  return AiToolRuntimeService(
    bashToolService: AiBashToolService(),
    hookService: AiNoopClaudeHookService(),
    mcpToolService: mcpService,
    backgroundChatClient: _ThrowingChatClient(),
  );
}

AiResolvedToolCatalog _catalog({
  required McpServer server,
  required McpTool mcpTool,
}) {
  final name = 'mcp__${server.name}__${mcpTool.id}';
  final definition = AiToolDefinition(
    name: name,
    description: mcpTool.description,
    parameters: mcpTool.inputSchema,
  );
  return AiResolvedToolCatalog(
    definitions: <AiToolDefinition>[definition],
    toolsByName: <String, AiResolvedTool>{
      name: AiResolvedTool(
        name: name,
        definition: definition,
        source: AiRuntimeToolSource.mcp,
        mcpServer: server,
        mcpTool: mcpTool,
      ),
    },
  );
}

McpTool _mcpTool({
  required String id,
  required String name,
  required String description,
}) {
  return McpTool(
    id: id,
    name: name,
    description: description,
    inputSchema: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'url': <String, Object?>{'type': 'string'},
      },
    },
  );
}

Map<String, Object?> _liveWebReverseMetadata() {
  return const <String, Object?>{
    'web_reverse_config': <String, Object?>{
      'target_url': 'https://linux.do/t/topic/2401043/5',
    },
    'web_reverse_cdp_runtime': <String, Object?>{
      'browser_alive': true,
      'cdp_port': 9223,
    },
  };
}

class _RecordingMcpService implements McpToolDiscoveryService {
  int callCount = 0;

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    return const McpToolCatalog(status: McpToolCatalogStatus.ready);
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    return const McpServerHealth(status: McpServerHealthStatus.healthy);
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
    Map<String, String>? customHeaders,
  }) async {
    callCount += 1;
    return const McpToolCallResult(outputText: 'ok');
  }

  @override
  void dispose() {}
}

class _ThrowingChatClient implements AiChatClient {
  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(minutes: 2),
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw StateError('MCP guard test should not call background chat.');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(minutes: 2),
    Duration streamIdleTimeout = const Duration(seconds: 30),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw StateError('MCP guard test should not call streaming chat.');
  }

  @override
  Future<String> testModel(AiModelConfig model) async => 'ok';

  @override
  void dispose() {}
}

const _model = AiModelConfig(
  id: 'test',
  baseUrl: 'https://example.invalid',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

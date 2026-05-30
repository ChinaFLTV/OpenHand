import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';
import 'package:openhand/features/skills/model/local_skill.dart';

void main() {
  group('AiToolRuntimeService', () {
    test('stabilizes skill and mcp ordering before builtin tools', () async {
      final service = AiToolRuntimeService(
        bashToolService: AiBashToolService(),
        hookService: AiClaudeHookService(),
        mcpToolService: _FakeMcpToolDiscoveryService(
          catalogsByServerName: <String, McpToolCatalog>{
            'z-server': const McpToolCatalog(
              status: McpToolCatalogStatus.ready,
              tools: <McpTool>[
                McpTool(
                  id: 'z_tool',
                  name: 'Z Tool',
                  description: 'z',
                  inputSchema: <String, Object?>{'type': 'object'},
                ),
              ],
            ),
            'a-server': const McpToolCatalog(
              status: McpToolCatalogStatus.ready,
              tools: <McpTool>[
                McpTool(
                  id: 'b_tool',
                  name: 'B Tool',
                  description: 'b',
                  inputSchema: <String, Object?>{'type': 'object'},
                ),
                McpTool(
                  id: 'a_tool',
                  name: 'A Tool',
                  description: 'a',
                  inputSchema: <String, Object?>{'type': 'object'},
                ),
              ],
            ),
          },
        ),
        backgroundChatClient: _NoopChatClient(),
        httpClient: http.Client(),
      );

      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '1.0.0',
        appBuildNumber: '1',
        settingsFilePath: '/tmp/settings.json',
        skillsStoragePath: '/tmp/skills',
        mcpServersFilePath: '/tmp/mcp.json',
        userMemoryFilePath: '/tmp/memory.json',
        compressionThresholdChars: 1000,
        memoryEnabled: true,
        memoryEntries: [],
        templateId: 'default',
        availableSkills: <LocalSkill>[
          LocalSkill(
            name: 'z-skill',
            description: 'z',
            directoryPath: '/tmp/skills/z',
            manifestPath: '/tmp/skills/z/SKILL.md',
            relativeDirectoryPath: 'z',
          ),
          LocalSkill(
            name: 'a-skill',
            description: 'a',
            directoryPath: '/tmp/skills/a',
            manifestPath: '/tmp/skills/a/SKILL.md',
            relativeDirectoryPath: 'a',
          ),
        ],
        availableMcpServers: <McpServer>[
          McpServer(name: 'z-server', type: McpServerType.sse, enabled: true),
          McpServer(name: 'a-server', type: McpServerType.sse, enabled: true),
        ],
      );

      final catalog = await service.resolveCatalog(runtimeContext: runtimeContext);
      final names = catalog.definitions.map((item) => item.name).toList();
      expect(
        names.take(4),
        <String>[
          'skill__a',
          'skill__z',
          'mcp__a-server__a_tool',
          'mcp__a-server__b_tool',
        ],
      );
      expect(names[4], 'mcp__z-server__z_tool');
      expect(names, contains('Read'));
    });
  });
}

class _FakeMcpToolDiscoveryService implements McpToolDiscoveryService {
  _FakeMcpToolDiscoveryService({required this.catalogsByServerName});

  final Map<String, McpToolCatalog> catalogsByServerName;

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    return const McpServerHealth(status: McpServerHealthStatus.healthy);
  }

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    return catalogsByServerName[server.name] ?? const McpToolCatalog();
  }

  @override
  void dispose() {}
}

class _NoopChatClient implements AiChatClient {
  @override
  void dispose() {}

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = Duration.zero,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = Duration.zero,
    Duration streamIdleTimeout = Duration.zero,
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> testModel(AiModelConfig model) {
    throw UnimplementedError();
  }
}

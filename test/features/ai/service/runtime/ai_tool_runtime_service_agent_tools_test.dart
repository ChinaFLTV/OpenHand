import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/data/agents_store.dart';
import 'package:openhand/features/agents/index.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/mcp/index.dart';
import 'package:openhand/features/memory/index.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Agent builtin tool catalog gate', () {
    late Directory tempDir;
    late AgentsController controller;
    late AiToolRuntimeService runtime;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'openhand_agent_tool_catalog_test_',
      );
      controller = AgentsController.uninitialized(
        store: AgentsStore(filePath: p.join(tempDir.path, 'agents.json')),
      );
      await controller.refresh();
      runtime = _runtimeService(() => controller);
    });

    tearDown(() async {
      runtime.dispose();
      controller.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('hides agent tools until at least one agent is enabled', () async {
      var catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(catalog.find('AgentList'), isNull);
      expect(catalog.find('AgentTaskPublish'), isNull);

      await controller.saveAgent(_agent(enabled: false));
      catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(catalog.find('AgentList'), isNull);

      await controller.setAgentEnabled('agent-1', enabled: true);
      catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(
        catalog.find('AgentList')?.builtinKind,
        AiBuiltinToolKind.agentList,
      );
      expect(
        catalog.find('AgentTaskPublish')?.builtinKind,
        AiBuiltinToolKind.agentTaskPublish,
      );

      await controller.setAgentEnabled('agent-1', enabled: false);
      catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(catalog.find('AgentList'), isNull);
      expect(catalog.find('AgentTaskPublish'), isNull);
    });
  });
}

AiToolRuntimeService _runtimeService(AgentsControllerProvider provider) {
  return AiToolRuntimeService(
    bashToolService: AiBashToolService(),
    hookService: AiNoopClaudeHookService(),
    mcpToolService: _FakeMcpToolDiscoveryService(),
    backgroundChatClient: _FakeAiChatClient(),
    agentsControllerProvider: provider,
  );
}

AiSessionRuntimeContext _runtimeContext() {
  return const AiSessionRuntimeContext(
    localeTag: 'en',
    appVersion: 'test',
    appBuildNumber: '1',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.json',
    compressionThresholdChars: 100000,
    memoryEnabled: false,
    memoryEntries: <UserMemoryEntry>[],
  );
}

AgentProfile _agent({required bool enabled}) {
  return AgentProfile(
    id: 'agent-1',
    name: 'Ops Agent',
    enabled: enabled,
    lifecycleState: enabled
        ? AgentLifecycleState.running
        : AgentLifecycleState.stopped,
  );
}

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
    Map<String, String>? customHeaders,
  }) async {
    return const McpToolCallResult(outputText: '');
  }

  @override
  void dispose() {}
}

class _FakeAiChatClient implements AiChatClient {
  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 1),
    Future<void>? cancelSignal,
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
    Duration timeout = const Duration(seconds: 1),
    Duration streamIdleTimeout = const Duration(seconds: 1),
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

  @override
  void dispose() {}
}

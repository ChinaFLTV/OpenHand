import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/data/agents_store.dart';
import 'package:openhand/features/agents/index.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/ai/tools/agents/ai_agent_tools.dart';

void main() {
  test('web agent policy exposes only selected agents', () async {
    final harness = await _AgentAccessHarness.create();
    addTearDown(harness.dispose);

    final listResult = await harness
        .tool(AiBuiltinToolKind.agentList)
        .execute(
          harness.context(
            toolName: 'AgentList',
            arguments: const <String, Object?>{},
            metadata: const <String, Object?>{
              aiAgentToolAccessEnabledMetadataKey: true,
              aiAgentToolAllowedAgentIdsMetadataKey: <String>['agent-a'],
              aiAgentToolAccessSourceMetadataKey: 'web_gateway',
            },
          ),
        );
    expect(listResult.status, BashToolExecutionStatus.success);
    final payload = jsonDecode(listResult.stdout) as Map<String, Object?>;
    final agents = payload['agents'] as List<Object?>;
    expect(agents, hasLength(1));
    expect((agents.single as Map<String, Object?>)['id'], 'agent-a');

    final blockedResult = await harness
        .tool(AiBuiltinToolKind.agentDetail)
        .execute(
          harness.context(
            toolName: 'AgentDetail',
            arguments: const <String, Object?>{'agent_id': 'agent-b'},
            metadata: const <String, Object?>{
              aiAgentToolAccessEnabledMetadataKey: true,
              aiAgentToolAllowedAgentIdsMetadataKey: <String>['agent-a'],
              aiAgentToolAccessSourceMetadataKey: 'web_gateway',
            },
          ),
        );
    expect(blockedResult.status, BashToolExecutionStatus.invalidArguments);
    expect(blockedResult.resultText, contains('not exposed'));
  });
}

class _AgentAccessHarness {
  _AgentAccessHarness({
    required this.tempDir,
    required this.controller,
    required this.tools,
  });

  final Directory tempDir;
  final AgentsController controller;
  final List<AiAgentTool> tools;

  static Future<_AgentAccessHarness> create() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'openhand-agent-policy-test-',
    );
    final controller = AgentsController.uninitialized(
      store: AgentsStore(filePath: '${tempDir.path}/agents.json'),
    );
    await controller.refresh();
    await controller.saveAgent(
      const AgentProfile(
        id: 'agent-a',
        name: '资料员',
        enabled: true,
        lifecycleState: AgentLifecycleState.running,
      ),
    );
    await controller.saveAgent(
      const AgentProfile(
        id: 'agent-b',
        name: '规划员',
        enabled: true,
        lifecycleState: AgentLifecycleState.running,
      ),
    );
    final tools = AiAgentTool.all(agentsControllerProvider: () => controller);
    return _AgentAccessHarness(
      tempDir: tempDir,
      controller: controller,
      tools: tools,
    );
  }

  AiAgentTool tool(AiBuiltinToolKind kind) {
    return tools.firstWhere((tool) => tool.kind == kind);
  }

  AiToolExecutionContext context({
    required String toolName,
    required Map<String, Object?> arguments,
    required Map<String, Object?> metadata,
  }) {
    return AiToolExecutionContext(
      sessionId: 'session-1',
      catalog: _catalog(tools),
      toolCall: AiToolCall(
        id: 'call-1',
        name: toolName,
        arguments: jsonEncode(arguments),
      ),
      decodedArguments: arguments,
      model: const AiModelConfig(
        id: 'model-config',
        baseUrl: 'http://localhost',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'test-model',
        protocolType: AiProtocolType.openai,
      ),
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: null,
      metadata: metadata,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

AiResolvedToolCatalog _catalog(List<AiAgentTool> tools) {
  final resolved = tools
      .map(
        (tool) => AiResolvedTool(
          name: tool.aliases.first,
          definition: AiToolDefinition(
            name: tool.aliases.first,
            description: '${tool.aliases.first} description',
            parameters: const <String, Object?>{'type': 'object'},
          ),
          source: AiRuntimeToolSource.builtin,
          builtinKind: tool.kind,
        ),
      )
      .toList(growable: false);
  return AiResolvedToolCatalog(
    definitions: resolved.map((tool) => tool.definition).toList(),
    toolsByName: <String, AiResolvedTool>{
      for (final tool in resolved) tool.name: tool,
    },
  );
}

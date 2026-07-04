import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';

void main() {
  test('WebMessagePlatformConfig defaults agent access on', () {
    final config = WebMessagePlatformConfig.fromJson(const <String, Object?>{});

    expect(config.agentsEnabled, isTrue);
    expect(config.allowedAgentIds, isEmpty);
  });

  test('WebMessagePlatformConfig round-trips agent exposure fields', () {
    const config = WebMessagePlatformConfig(
      agentsEnabled: false,
      allowedAgentIds: <String>['agent-a', 'agent-b'],
    );

    final restored = WebMessagePlatformConfig.fromJson(config.toJson());

    expect(restored.agentsEnabled, isFalse);
    expect(restored.allowedAgentIds, <String>['agent-a', 'agent-b']);
    expect(restored.toJson()['agents_enabled'], isFalse);
    expect(restored.toJson()['allowed_agent_ids'], <String>[
      'agent-a',
      'agent-b',
    ]);
  });

  test('AiSessionRuntimeContext serializes tool execution metadata', () {
    final context = _runtimeContext(
      toolExecutionMetadata: <String, Object?>{
        aiAgentToolAccessEnabledMetadataKey: true,
        aiAgentToolAllowedAgentIdsMetadataKey: <String>['agent-a'],
        aiAgentToolAccessSourceMetadataKey: 'web_gateway',
      },
    );

    expect(context.toJson()['tool_execution_metadata'], <String, Object?>{
      aiAgentToolAccessEnabledMetadataKey: true,
      aiAgentToolAllowedAgentIdsMetadataKey: <String>['agent-a'],
      aiAgentToolAccessSourceMetadataKey: 'web_gateway',
    });
  });
}

AiSessionRuntimeContext _runtimeContext({
  Map<String, Object?> toolExecutionMetadata = const <String, Object?>{},
}) {
  return AiSessionRuntimeContext(
    localeTag: 'zh-Hans',
    appVersion: '1.0.0',
    appBuildNumber: '1',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.json',
    compressionThresholdChars: 120000,
    memoryEnabled: false,
    memoryEntries: const [],
    toolExecutionMetadata: toolExecutionMetadata,
  );
}

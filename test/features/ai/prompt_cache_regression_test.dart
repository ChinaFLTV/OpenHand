import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';

void main() {
  test(
    'cache hit trend user view excludes cold start and background rounds',
    () {
      final now = DateTime.utc(2026, 7, 4, 10);
      final session = _session(<AiSessionMessage>[
        _user('u1', now),
        _assistant('a1', now.add(const Duration(seconds: 1)), 100, 0),
        _tool('t1', now.add(const Duration(seconds: 2))),
        _assistant('a2', now.add(const Duration(seconds: 3)), 120, 0),
        _user('u2', now.add(const Duration(seconds: 4))),
        _assistant('a3', now.add(const Duration(seconds: 5)), 100, 80),
        _user('u3', now.add(const Duration(seconds: 6))),
        _assistant('a4', now.add(const Duration(seconds: 7)), 100, 90),
      ]);

      final trend = SessionCacheHitTrend.fromSession(
        session,
        claudeStyle: false,
      );
      final userView = trend.displayData(
        SessionCacheHitDisplayMode.excludeExtremeMisses,
      );
      final allRequests = trend.displayData(
        SessionCacheHitDisplayMode.includeAll,
      );

      expect(allRequests.trend.points, hasLength(4));
      expect(userView.trend.points, hasLength(2));
      expect(
        userView.trend.points.map((point) => point.starterOrigin),
        everyElement(aiSessionMessageSenderOriginExplicitUser),
      );
      expect(userView.excludedPointCount, 2);
      expect(userView.averageHitRatio, closeTo(0.85, 0.0001));
    },
  );

  test('agent core coordination tools are never folded by lazy loading', () {
    final tools = <AiResolvedTool>[
      _builtin(AiBuiltinToolKind.toolSearch, 'ToolSearch'),
      _builtin(AiBuiltinToolKind.agentList, 'AgentList'),
      _builtin(AiBuiltinToolKind.agentTaskPublish, 'AgentTaskPublish'),
      _builtin(AiBuiltinToolKind.agentTaskTrack, 'AgentTaskTrack'),
      _builtin(AiBuiltinToolKind.agentTaskResult, 'AgentTaskResult'),
      _builtin(AiBuiltinToolKind.agentTaskProgress, 'AgentTaskProgress'),
    ];
    final catalog = AiResolvedToolCatalog(
      definitions: tools.map((tool) => tool.definition).toList(growable: false),
      toolsByName: <String, AiResolvedTool>{
        for (final tool in tools) tool.name: tool,
      },
    );

    final applied = AiBuiltinToolLazyLoadingApplier.apply(
      catalog: catalog,
      sourceCatalog: catalog,
      mode: AiBuiltinToolLazyLoadingMode.enabled,
      thresholdTokens: 1,
      charsPerToken: 4,
    );

    expect(
      applied.toolsByName.keys,
      containsAll(<String>[
        'ToolSearch',
        'AgentList',
        'AgentTaskPublish',
        'AgentTaskTrack',
        'AgentTaskResult',
      ]),
    );
    expect(applied.toolsByName.keys, isNot(contains('AgentTaskProgress')));
    expect(
      applied.toolsByName['ToolSearch']!.toolSearchDeferredToolDefinitions.keys,
      contains('AgentTaskProgress'),
    );
  });
}

AiResolvedTool _builtin(AiBuiltinToolKind kind, String name) {
  return AiResolvedTool(
    name: name,
    definition: AiToolDefinition(
      name: name,
      description: '$name description',
      parameters: const <String, Object?>{'type': 'object'},
    ),
    source: AiRuntimeToolSource.builtin,
    builtinKind: kind,
    builtinConfig: AiBuiltinToolConfig(
      kind: kind,
      loadStrategy: AiBuiltinToolLoadStrategy.lazy,
    ),
  );
}

AiSession _session(List<AiSessionMessage> messages) {
  final now = DateTime.utc(2026, 7, 4);
  return AiSession(
    id: 's1',
    title: 'cache trend',
    templateId: 'default',
    templateName: 'Default',
    templateIconName: 'auto',
    templateInternalVersion: 'test',
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'en',
      platform: 'test',
      appVersion: '0',
      appBuildNumber: '0',
      applicationDirectory: '/',
      homeDirectory: '/',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      sessionsDirectoryPath: '',
      compressionThresholdChars: 0,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}

AiSessionMessage _user(String id, DateTime createdAt) {
  return AiSessionMessage.user(id: id, content: id, createdAt: createdAt);
}

AiSessionMessage _assistant(
  String id,
  DateTime createdAt,
  int promptTokens,
  int cacheReadTokens,
) {
  return AiSessionMessage.assistant(
    id: id,
    content: id,
    createdAt: createdAt,
    usage: AiTokenUsage(
      promptTokens: promptTokens,
      completionTokens: 1,
      totalTokens: promptTokens + 1,
      cacheReadTokens: cacheReadTokens,
    ),
  );
}

AiSessionMessage _tool(String id, DateTime createdAt) {
  return AiSessionMessage.toolResult(
    id: id,
    content: id,
    createdAt: createdAt,
    metadata: const <String, Object?>{
      aiSessionMessageSenderOriginJsonKey:
          aiSessionMessageSenderOriginOpenHandBackground,
    },
  );
}

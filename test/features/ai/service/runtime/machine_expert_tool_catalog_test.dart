import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/machine_terminal/index.dart';
import 'package:openhand/features/mcp/index.dart';

void main() {
  test('machine_expert hides Bash and keeps terminal tools eager', () {
    final service = _runtimeService();
    addTearDown(service.dispose);

    final catalog = service.resolveCatalogFromRuntimeSnapshot(
      runtimeContext: _runtimeContext(
        templateId: kMachineExpertTemplateId,
        builtinToolConfigs: _machineExpertBuiltinConfigs(),
      ),
    );

    final names = _toolNames(catalog);
    expect(names, isNot(contains('Bash')));
    expect(names, isNot(contains('BashBackground')));
    expect(names, containsAll(_machineTerminalToolNames));

    final lazyCatalog = AiBuiltinToolLazyLoadingApplier.apply(
      catalog: catalog,
      sourceCatalog: catalog,
      mode: AiBuiltinToolLazyLoadingMode.enabled,
      thresholdTokens: 1,
      charsPerToken: 4,
      toolRuntimeService: service,
    );
    final lazyNames = _toolNames(lazyCatalog);

    expect(lazyCatalog.notices, contains(contains('lazy loading active')));
    expect(lazyNames, containsAll(_machineTerminalToolNames));
    expect(lazyNames, isNot(contains('Bash')));
    expect(lazyNames, isNot(contains('BashBackground')));
    expect(lazyNames, isNot(contains('Write')));
  });

  test('MachineTerminalWrite schema accepts data, input, or text', () {
    final service = _runtimeService();
    addTearDown(service.dispose);

    final catalog = service.resolveCatalogFromRuntimeSnapshot(
      runtimeContext: _runtimeContext(
        templateId: kMachineExpertTemplateId,
        builtinToolConfigs: _machineExpertBuiltinConfigs(),
      ),
    );

    final writeTool = catalog.find('MachineTerminalWrite');
    expect(writeTool, isNotNull);
    final anyOf = writeTool!.definition.parameters['anyOf'];
    expect(anyOf, isA<List<Object?>>());
    final requiredKeys = <String>[
      for (final branch in anyOf! as List<Object?>)
        ...((((branch as Map)['required'] ?? const <Object?>[]) as List).map(
          (value) => '$value',
        )),
    ];

    expect(requiredKeys, containsAll(<String>['data', 'input', 'text']));
  });

  test('non-machine templates do not expose machine terminal tools', () {
    final service = _runtimeService();
    addTearDown(service.dispose);

    final catalog = service.resolveCatalogFromRuntimeSnapshot(
      runtimeContext: _runtimeContext(
        templateId: 'default',
        builtinToolConfigs: _machineExpertBuiltinConfigs(),
      ),
    );

    final names = _toolNames(catalog);
    expect(names, contains('Bash'));
    expect(names, contains('BashBackground'));
    for (final toolName in _machineTerminalToolNames) {
      expect(names, isNot(contains(toolName)));
    }
  });
}

const List<String> _machineTerminalToolNames = <String>[
  'MachineTerminalRead',
  'MachineTerminalWrite',
  'MachineTerminalExec',
  'MachineTerminalControl',
];

AiToolRuntimeService _runtimeService() {
  return AiToolRuntimeService(
    bashToolService: AiBashToolService(),
    hookService: AiNoopClaudeHookService(),
    mcpToolService: _NoopMcpToolDiscoveryService(),
    backgroundChatClient: _NoopChatClient(),
  );
}

AiSessionRuntimeContext _runtimeContext({
  required String templateId,
  required List<AiBuiltinToolConfig> builtinToolConfigs,
}) {
  return AiSessionRuntimeContext(
    localeTag: 'zh-CN',
    appVersion: '0.1.0',
    appBuildNumber: '1',
    settingsFilePath: 'db://settings',
    skillsStoragePath: '/tmp/openhand-test-skills',
    mcpServersFilePath: '/tmp/openhand-test-mcp.json',
    userMemoryFilePath: '/tmp/openhand-test-memory.json',
    compressionThresholdChars: 0,
    memoryEnabled: false,
    memoryEntries: const [],
    templateId: templateId,
    builtinToolConfigs: builtinToolConfigs,
  );
}

List<AiBuiltinToolConfig> _machineExpertBuiltinConfigs() {
  return const <AiBuiltinToolConfig>[
    AiBuiltinToolConfig(kind: AiBuiltinToolKind.toolSearch),
    AiBuiltinToolConfig(
      kind: AiBuiltinToolKind.bash,
      loadStrategy: AiBuiltinToolLoadStrategy.lazy,
    ),
    AiBuiltinToolConfig(
      kind: AiBuiltinToolKind.bashBackground,
      loadStrategy: AiBuiltinToolLoadStrategy.lazy,
    ),
    AiBuiltinToolConfig(
      kind: AiBuiltinToolKind.write,
      loadStrategy: AiBuiltinToolLoadStrategy.lazy,
    ),
    AiBuiltinToolConfig(
      kind: AiBuiltinToolKind.machineTerminalRead,
      loadStrategy: AiBuiltinToolLoadStrategy.lazy,
    ),
    AiBuiltinToolConfig(
      kind: AiBuiltinToolKind.machineTerminalWrite,
      loadStrategy: AiBuiltinToolLoadStrategy.lazy,
    ),
    AiBuiltinToolConfig(
      kind: AiBuiltinToolKind.machineTerminalExec,
      loadStrategy: AiBuiltinToolLoadStrategy.lazy,
    ),
    AiBuiltinToolConfig(
      kind: AiBuiltinToolKind.machineTerminalControl,
      loadStrategy: AiBuiltinToolLoadStrategy.lazy,
    ),
  ];
}

List<String> _toolNames(AiResolvedToolCatalog catalog) {
  return catalog.definitions.map((tool) => tool.name).toList(growable: false);
}

class _NoopMcpToolDiscoveryService implements McpToolDiscoveryService {
  @override
  Future<McpServerHealth> checkHealth(McpServer server) {
    throw UnimplementedError();
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
    Map<String, String>? customHeaders,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}

class _NoopChatClient implements AiChatClient {
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

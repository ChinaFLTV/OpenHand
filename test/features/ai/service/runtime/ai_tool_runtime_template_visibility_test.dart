import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/mcp/index.dart';

class _UnusedAiChatClient implements AiChatClient {
  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('测试不应调用后台模型');
  }
}

class _UnusedMcpToolDiscoveryService implements McpToolDiscoveryService {
  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('快照测试不应调用 MCP 发现服务');
  }
}

void main() {
  const model = AiModelConfig(
    id: 'test-provider',
    baseUrl: '',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'test-model',
    protocolType: AiProtocolType.openai,
  );
  const commonServerName = '通用 MCP';
  const webServerName = 'Web 专属 MCP';
  const commonServer = McpServer(
    name: commonServerName,
    type: McpServerType.streamableHttp,
    enabled: true,
    url: 'https://example.com/common',
  );
  const webServer = McpServer(
    name: webServerName,
    type: McpServerType.streamableHttp,
    enabled: true,
    url: 'https://example.com/web',
    visibleTemplateIds: <String>{McpServer.webReverseExpertTemplateId},
  );
  const catalogs = <String, McpToolCatalog>{
    commonServerName: McpToolCatalog(
      status: McpToolCatalogStatus.ready,
      tools: <McpTool>[
        McpTool(
          id: 'common_tool',
          name: 'common_tool',
          description: '通用工具',
          inputSchema: <String, Object?>{'type': 'object'},
        ),
      ],
      serverInstructions: '通用服务指令',
    ),
    webServerName: McpToolCatalog(
      status: McpToolCatalogStatus.ready,
      tools: <McpTool>[
        McpTool(
          id: 'web_tool',
          name: 'web_tool',
          description: 'Web 专属工具',
          inputSchema: <String, Object?>{'type': 'object'},
        ),
      ],
      serverInstructions: 'Web 专属服务指令',
    ),
  };

  AiSessionRuntimeContext runtimeContext(String templateId) {
    return AiSessionRuntimeContext(
      localeTag: 'zh_CN',
      appVersion: 'test',
      appBuildNumber: '1',
      settingsFilePath: '/tmp/settings.json',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp_servers.json',
      userMemoryFilePath: '/tmp/memory.json',
      compressionThresholdChars: 1000,
      memoryEnabled: false,
      memoryEntries: const [],
      templateId: templateId,
      availableMcpServers: const <McpServer>[commonServer, webServer],
      mcpToolCatalogsByServerName: catalogs,
      mcpLazyLoadingMode: McpLazyLoadingMode.enabled,
      builtinToolConfigs: const <AiBuiltinToolConfig>[
        AiBuiltinToolConfig(kind: AiBuiltinToolKind.toolSearch),
      ],
    );
  }

  late AiBashToolService bashToolService;
  late AiToolRuntimeService toolRuntimeService;

  setUpAll(() {
    bashToolService = AiBashToolService();
    toolRuntimeService = AiToolRuntimeService(
      bashToolService: bashToolService,
      hookService: AiNoopClaudeHookService(),
      mcpToolService: _UnusedMcpToolDiscoveryService(),
      backgroundChatClient: _UnusedAiChatClient(),
    );
  });

  tearDownAll(() async {
    await toolRuntimeService.shutdown();
    await bashToolService.shutdown();
  });

  group('MCP 运行时模板可见性', () {
    test('默认模板排除 Web 专属工具及服务指令', () {
      final catalog = toolRuntimeService.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: runtimeContext('default'),
        mcpToolCatalogsByServerName: catalogs,
      );

      final mcpServerNames = catalog.toolsByName.values
          .where((tool) => tool.source == AiRuntimeToolSource.mcp)
          .map((tool) => tool.mcpServer?.name)
          .toSet();
      expect(mcpServerNames, <String?>{commonServerName});
      expect(catalog.mcpServerInstructionsByName, <String, String>{
        commonServerName: '通用服务指令',
      });
    });

    test('Web 逆向专家模板包含专属工具及服务指令', () {
      final catalog = toolRuntimeService.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: runtimeContext(McpServer.webReverseExpertTemplateId),
        mcpToolCatalogsByServerName: catalogs,
      );

      final mcpServerNames = catalog.toolsByName.values
          .where((tool) => tool.source == AiRuntimeToolSource.mcp)
          .map((tool) => tool.mcpServer?.name)
          .toSet();
      expect(mcpServerNames, <String?>{commonServerName, webServerName});
      expect(catalog.mcpServerInstructionsByName, <String, String>{
        commonServerName: '通用服务指令',
        webServerName: 'Web 专属服务指令',
      });
    });

    test('默认模板的 ToolSearch 延迟目录不包含 Web 专属工具', () {
      final context = runtimeContext('default');
      final fullCatalog = toolRuntimeService.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: context,
        mcpToolCatalogsByServerName: catalogs,
      );

      expect(
        fullCatalog.toolsByName.values.any(
          (tool) => tool.mcpServer?.name == webServerName,
        ),
        isFalse,
      );

      final lazyCatalog = McpLazyLoadingApplier.apply(
        catalog: fullCatalog,
        runtimeContext: context,
        toolRuntimeService: toolRuntimeService,
      );
      final toolSearch = lazyCatalog.toolsByName.values.singleWhere(
        (tool) => tool.builtinKind == AiBuiltinToolKind.toolSearch,
      );
      final deferredServerNames = toolSearch.toolSearchDeferredTools.values
          .map((tool) => tool.mcpServer?.name)
          .toSet();

      expect(deferredServerNames, <String?>{commonServerName});
      expect(deferredServerNames, isNot(contains(webServerName)));
    });

    test('执行阶段拒绝跨模板复用旧目录中的受限工具', () async {
      final catalog = toolRuntimeService.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: runtimeContext(McpServer.webReverseExpertTemplateId),
        mcpToolCatalogsByServerName: catalogs,
      );
      final webTool = catalog.toolsByName.values.singleWhere(
        (tool) => tool.mcpServer?.name == webServerName,
      );

      final result = await toolRuntimeService.execute(
        sessionId: 'default-session',
        catalog: catalog,
        toolCall: AiToolCall(id: 'call-1', name: webTool.name, arguments: '{}'),
        model: model,
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
        metadata: const <String, Object?>{'template_id': 'default'},
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.resultText, contains('当前线程模板不可使用该 MCP 服务'));
    });

    test('ToolSearch 查询和代理调用均过滤跨模板旧目录', () async {
      final context = runtimeContext(McpServer.webReverseExpertTemplateId);
      final fullCatalog = toolRuntimeService.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: context,
        mcpToolCatalogsByServerName: catalogs,
      );
      final webTool = fullCatalog.toolsByName.values.singleWhere(
        (tool) => tool.mcpServer?.name == webServerName,
      );
      final lazyCatalog = McpLazyLoadingApplier.apply(
        catalog: fullCatalog,
        runtimeContext: context,
        toolRuntimeService: toolRuntimeService,
      );
      final toolSearch = lazyCatalog.toolsByName.values.singleWhere(
        (tool) => tool.builtinKind == AiBuiltinToolKind.toolSearch,
      );

      final queryResult = await toolRuntimeService.execute(
        sessionId: 'default-session',
        catalog: lazyCatalog,
        toolCall: AiToolCall(
          id: 'call-search',
          name: toolSearch.name,
          arguments: jsonEncode(<String, Object?>{'query': '专属'}),
        ),
        model: model,
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
        metadata: const <String, Object?>{'template_id': 'default'},
      );
      expect(queryResult.status, BashToolExecutionStatus.success);
      expect(
        queryResult.metadata['tool_search_loaded_names'],
        isNot(contains(webTool.name)),
      );
      expect(queryResult.resultText, isNot(contains(webTool.name)));

      final proxyResult = await toolRuntimeService.execute(
        sessionId: 'default-session',
        catalog: lazyCatalog,
        toolCall: AiToolCall(
          id: 'call-proxy',
          name: toolSearch.name,
          arguments: jsonEncode(<String, Object?>{
            'tool_name': webTool.name,
            'arguments': <String, Object?>{},
          }),
        ),
        model: model,
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
        metadata: const <String, Object?>{'template_id': 'default'},
      );
      expect(proxyResult.status, BashToolExecutionStatus.invalidArguments);
      expect(proxyResult.resultText, contains('延迟工具不可用'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/mcp_bridge/web_reverse_mcp_tool_policy.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/mcp/index.dart';

void main() {
  test(
    'keeps chrome-devtools MCP tools visible even with generic tool names',
    () {
      final catalog = _catalog(<AiResolvedTool>[
        _mcpTool(
          catalogName: 'mcp__Browser__navigate_page',
          serverName: 'Browser',
          command: 'npx',
          args: const <String>['chrome-devtools-mcp@latest', '--autoConnect'],
          toolId: 'navigate_page',
          toolName: 'navigate page',
          description: 'Navigate the current page.',
        ),
        _mcpTool(
          catalogName: 'mcp__files__read_file',
          serverName: 'files',
          command: 'node',
          args: const <String>['server.js'],
          toolId: 'read_file',
          toolName: 'read file',
          description: 'Read a local file.',
        ),
      ]);

      final names = WebReverseMcpToolPolicy.forceVisibleToolNames(catalog);

      expect(names, contains('mcp__Browser__navigate_page'));
      expect(names, isNot(contains('mcp__files__read_file')));
    },
  );

  test('does not demote chrome-devtools tools whose docs mention Playwright', () {
    final catalog = _catalog(<AiResolvedTool>[
      _mcpTool(
        catalogName: 'mcp__Chrome_DevTools__evaluate_script',
        serverName: 'Chrome DevTools',
        command: 'npx',
        args: const <String>['chrome-devtools-mcp@latest'],
        toolId: 'evaluate_script',
        toolName: 'evaluate script',
        description:
            'Evaluate JavaScript through Chrome DevTools Protocol; useful for teams migrating from Playwright.',
      ),
    ]);

    expect(
      WebReverseMcpToolPolicy.forceVisibleToolNames(catalog),
      contains('mcp__Chrome_DevTools__evaluate_script'),
    );
  });

  test('keeps non-CDP Playwright automation deferred', () {
    final catalog = _catalog(<AiResolvedTool>[
      _mcpTool(
        catalogName: 'mcp__Playwright_MCP__browser_evaluate',
        serverName: 'Playwright MCP',
        command: 'npx',
        args: const <String>['@playwright/mcp'],
        toolId: 'browser_evaluate',
        toolName: 'browser evaluate',
        description:
            'Evaluate JavaScript, optionally against a CDP-backed browser.',
      ),
    ]);

    expect(
      WebReverseMcpToolPolicy.forceVisibleToolNames(catalog),
      isNot(contains('mcp__Playwright_MCP__browser_evaluate')),
    );
  });

  test('keeps Playwright deferred even when launched with a CDP endpoint', () {
    final catalog = _catalog(<AiResolvedTool>[
      _mcpTool(
        catalogName: 'mcp__Playwright_MCP__browser_navigate',
        serverName: 'Playwright MCP',
        command: 'npx',
        args: const <String>[
          '@playwright/mcp',
          '--cdp-endpoint=http://127.0.0.1:9222',
        ],
        toolId: 'browser_navigate',
        toolName: 'browser navigate',
        description: 'Navigate through the Playwright MCP browser session.',
      ),
    ]);

    expect(
      WebReverseMcpToolPolicy.forceVisibleToolNames(catalog),
      isNot(contains('mcp__Playwright_MCP__browser_navigate')),
    );
  });

  test('keeps Puppeteer automation deferred even when it mentions CDP', () {
    final catalog = _catalog(<AiResolvedTool>[
      _mcpTool(
        catalogName: 'mcp__Puppeteer__page_evaluate',
        serverName: 'Puppeteer',
        command: 'npx',
        args: const <String>['puppeteer-mcp'],
        toolId: 'page_evaluate',
        toolName: 'page evaluate',
        description: 'Evaluate through a Puppeteer CDP session.',
      ),
    ]);

    expect(
      WebReverseMcpToolPolicy.forceVisibleToolNames(catalog),
      isNot(contains('mcp__Puppeteer__page_evaluate')),
    );
  });

  test(
    'keeps Browserless deferred even when identity mentions Chrome DevTools',
    () {
      final catalog = _catalog(<AiResolvedTool>[
        _mcpTool(
          catalogName: 'mcp__Browserless_Chrome_DevTools__evaluate',
          serverName: 'Browserless Chrome DevTools',
          command: 'npx',
          args: const <String>['browserless-mcp'],
          toolId: 'evaluate',
          toolName: 'evaluate',
          description: 'Evaluate JavaScript through a remote Browserless tab.',
        ),
      ]);

      expect(
        WebReverseMcpToolPolicy.forceVisibleToolNames(catalog),
        isNot(contains('mcp__Browserless_Chrome_DevTools__evaluate')),
      );
    },
  );

  test('keeps chrome-devtools-mcp visible despite a generic server label', () {
    final catalog = _catalog(<AiResolvedTool>[
      _mcpTool(
        catalogName: 'mcp__Generic_Browser__navigate_page',
        serverName: 'Generic Browser',
        command: 'npx',
        args: const <String>['chrome-devtools-mcp@latest'],
        toolId: 'navigate_page',
        toolName: 'navigate page',
        description: 'Navigate the current Chrome page.',
      ),
    ]);

    expect(
      WebReverseMcpToolPolicy.forceVisibleToolNames(catalog),
      contains('mcp__Generic_Browser__navigate_page'),
    );
  });

  test('keeps documentation tools deferred when only text mentions CDP', () {
    final catalog = _catalog(<AiResolvedTool>[
      _mcpTool(
        catalogName: 'mcp__Docs__search',
        serverName: 'Docs Search',
        command: 'node',
        args: const <String>['docs-mcp.js'],
        toolId: 'search',
        toolName: 'search',
        description:
            'Search local Chrome DevTools Protocol and CDP reference docs.',
      ),
    ]);

    expect(
      WebReverseMcpToolPolicy.forceVisibleToolNames(catalog),
      isNot(contains('mcp__Docs__search')),
    );
  });

  test('keeps CDP documentation search tools deferred by identity', () {
    final catalog = _catalog(<AiResolvedTool>[
      _mcpTool(
        catalogName: 'mcp__Docs__cdp_search',
        serverName: 'Docs Search',
        command: 'node',
        args: const <String>['docs-mcp.js'],
        toolId: 'cdp_search',
        toolName: 'cdp search',
        description: 'Search local protocol reference docs.',
      ),
    ]);

    expect(
      WebReverseMcpToolPolicy.forceVisibleToolNames(catalog),
      isNot(contains('mcp__Docs__cdp_search')),
    );
  });

  test('keeps custom CDP browser-control tools visible', () {
    final catalog = _catalog(<AiResolvedTool>[
      _mcpTool(
        catalogName: 'mcp__Browser__navigate_page',
        serverName: 'Browser Controller',
        command: 'node',
        args: const <String>['custom-browser-mcp.js'],
        toolId: 'navigate_page',
        toolName: 'navigate page',
        description: 'Navigate the current tab through a CDP session.',
      ),
    ]);

    expect(
      WebReverseMcpToolPolicy.forceVisibleToolNames(catalog),
      contains('mcp__Browser__navigate_page'),
    );
  });
}

AiResolvedToolCatalog _catalog(List<AiResolvedTool> tools) {
  return AiResolvedToolCatalog(
    definitions: tools.map((tool) => tool.definition).toList(growable: false),
    toolsByName: <String, AiResolvedTool>{
      for (final tool in tools) tool.name: tool,
    },
  );
}

AiResolvedTool _mcpTool({
  required String catalogName,
  required String serverName,
  required String command,
  required List<String> args,
  required String toolId,
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
    mcpServer: McpServer(
      name: serverName,
      type: McpServerType.stdio,
      enabled: true,
      command: command,
      args: args,
    ),
    mcpTool: McpTool(
      id: toolId,
      name: toolName,
      description: description,
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    ),
  );
}

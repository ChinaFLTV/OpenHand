import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/mcp_bridge/web_reverse_mcp_tool_policy.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/mcp/index.dart';

void main() {
  group('WebReverseMcpToolPolicy', () {
    test('keeps transient chrome-devtools-mcp tools visible', () {
      final tool = _mcpTool(
        catalogName: 'mcp__web_reverse_cdp_abcd__navigate_page',
        serverName: 'web_reverse_cdp_abcd',
        serverCommand: 'npx',
        serverArgs: const <String>[
          '--yes',
          'chrome-devtools-mcp@latest',
          '--browser-url=http://127.0.0.1:9223/',
        ],
        mcpName: 'navigate_page',
        description: 'Navigate the current Chrome page.',
      );

      expect(WebReverseMcpToolPolicy.shouldForceVisibleTool(tool), isTrue);
    });

    test('does not force visible non-CDP browser automation tools', () {
      final tool = _mcpTool(
        catalogName: 'mcp__playwright__browser_navigate',
        serverName: 'playwright',
        serverCommand: 'npx',
        serverArgs: const <String>['@playwright/mcp'],
        mcpName: 'browser_navigate',
        description: 'Navigate a Playwright browser page.',
      );

      expect(WebReverseMcpToolPolicy.shouldForceVisibleTool(tool), isFalse);
    });

    test('keeps browser-control tools whose description exposes CDP', () {
      final tool = _mcpTool(
        catalogName: 'mcp__custom__browser_network_get',
        serverName: 'custom_browser',
        mcpName: 'browser_network_get',
        description:
            'Calls CDP Network.getResponseBody through Chrome DevTools Protocol.',
      );

      expect(WebReverseMcpToolPolicy.shouldForceVisibleTool(tool), isTrue);
    });

    test('returns only matching names from a mixed catalog', () {
      final visible = _mcpTool(
        catalogName: 'mcp__web_reverse_cdp_abcd__evaluate_script',
        serverName: 'web_reverse_cdp_abcd',
        serverCommand: 'npx',
        serverArgs: const <String>['chrome-devtools-mcp@latest'],
        mcpName: 'evaluate_script',
        description: 'Evaluate JavaScript in Chrome.',
      );
      final hidden = _mcpTool(
        catalogName: 'mcp__playwright__browser_click',
        serverName: 'playwright',
        serverCommand: 'npx',
        serverArgs: const <String>['@playwright/mcp'],
        mcpName: 'browser_click',
        description: 'Click using Playwright.',
      );

      final names = WebReverseMcpToolPolicy.forceVisibleToolNames(
        AiResolvedToolCatalog(
          definitions: <AiToolDefinition>[
            visible.definition,
            hidden.definition,
          ],
          toolsByName: <String, AiResolvedTool>{
            visible.name: visible,
            hidden.name: hidden,
          },
        ),
      );

      expect(names, <String>{'mcp__web_reverse_cdp_abcd__evaluate_script'});
    });
  });
}

AiResolvedTool _mcpTool({
  required String catalogName,
  required String serverName,
  required String mcpName,
  required String description,
  String serverCommand = 'custom-mcp',
  List<String> serverArgs = const <String>[],
}) {
  final definition = AiToolDefinition(
    name: catalogName,
    description: description,
    parameters: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
      'additionalProperties': false,
    },
  );
  return AiResolvedTool(
    name: catalogName,
    definition: definition,
    source: AiRuntimeToolSource.mcp,
    mcpServer: McpServer(
      name: serverName,
      type: McpServerType.stdio,
      enabled: true,
      command: serverCommand,
      args: serverArgs,
    ),
    mcpTool: McpTool(
      id: mcpName,
      name: mcpName,
      description: description,
      inputSchema: const <String, Object?>{},
    ),
  );
}

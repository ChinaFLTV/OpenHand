import 'package:flutter/foundation.dart';

import '../runtime/ai_tool_runtime_service.dart';

class WebReverseMcpToolPolicy {
  const WebReverseMcpToolPolicy._();

  static final RegExp _cdpTokenPattern = RegExp(
    r'(^|[^a-z0-9])cdp([^a-z0-9]|$)',
  );

  static Set<String> forceVisibleToolNames(AiResolvedToolCatalog catalog) {
    final names = <String>{};
    for (final entry in catalog.toolsByName.entries) {
      if (shouldForceVisibleTool(entry.value, catalogName: entry.key)) {
        names.add(entry.key);
      }
    }
    return names;
  }

  @visibleForTesting
  static bool shouldForceVisibleTool(
    AiResolvedTool tool, {
    String? catalogName,
  }) {
    if (tool.source != AiRuntimeToolSource.mcp) return false;

    final server = tool.mcpServer;
    final mcpTool = tool.mcpTool;
    final identity = _joinParts(<Object?>[
      catalogName,
      tool.name,
      tool.definition.name,
      server?.name,
      server?.summary,
      server?.command,
      if (server != null) ...server.args,
      server?.url,
      mcpTool?.id,
      mcpTool?.name,
    ]);
    final descriptive = _joinParts(<Object?>[
      identity,
      tool.definition.description,
      mcpTool?.description,
      mcpTool?.outputDescription,
      mcpTool?.annotations,
      mcpTool?.execution,
      mcpTool?.rawMetadata,
    ]);

    final cdpByIdentity = _hasCdpSignal(identity);
    final nonCdpAutomationByIdentity = _containsAny(identity, const <String>[
      '@playwright/mcp',
      'playwright',
      'puppeteer',
    ]);
    if (nonCdpAutomationByIdentity && !cdpByIdentity) return false;

    return cdpByIdentity || _hasCdpSignal(descriptive);
  }

  static bool _hasCdpSignal(String value) {
    return _cdpTokenPattern.hasMatch(value) ||
        _containsAny(value, const <String>[
          'chrome-devtools',
          'chrome_devtools',
          'chrome devtools',
          'chrome devtools protocol',
          'devtools protocol',
          'remote debugging protocol',
        ]) ||
        (value.contains('chrome') && value.contains('devtools'));
  }

  static bool _containsAny(String value, Iterable<String> needles) {
    for (final needle in needles) {
      if (value.contains(needle)) return true;
    }
    return false;
  }

  static String _joinParts(Iterable<Object?> parts) {
    return parts
        .where((part) => part != null)
        .map((part) => '$part'.trim())
        .where((part) => part.isNotEmpty)
        .join('\n')
        .toLowerCase();
  }
}

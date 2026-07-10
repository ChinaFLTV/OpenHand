import '../../../../shared/util/input_value_parsing.dart';
import '../runtime/ai_tool_runtime_service.dart';

class WebReverseMcpToolPolicy {
  const WebReverseMcpToolPolicy._();

  static final RegExp _cdpTokenPattern = RegExp(
    r'(^|[^a-z0-9])cdp([^a-z0-9]|$)',
  );

  static Set<String> forceVisibleToolNames(AiResolvedToolCatalog catalog) {
    final names = <String>{};
    for (final entry in catalog.toolsByName.entries) {
      if (_shouldForceVisibleTool(entry.value, catalogName: entry.key)) {
        names.add(entry.key);
      }
    }
    return names;
  }

  static bool _shouldForceVisibleTool(
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
    final launchIdentity = _joinParts(<Object?>[
      server?.command,
      if (server != null) ...server.args,
      server?.url,
    ]);

    final chromeDevtoolsByIdentity = _hasChromeDevtoolsSignal(identity);
    final jsReverseByIdentity = _hasJsReverseSignal(identity);
    final chromeDevtoolsMcpLaunch = launchIdentity.contains(
      'chrome-devtools-mcp',
    );
    final nonCdpAutomationByIdentity = _containsAny(identity, const <String>[
      '@playwright/mcp',
      'playwright',
      'puppeteer',
      'selenium',
      'webdriver',
      'browserless',
    ]);
    if (nonCdpAutomationByIdentity && !chromeDevtoolsMcpLaunch) return false;

    final browserControlIdentity = _hasBrowserControlIdentity(identity);
    final cdpByIdentity = _hasCdpSignal(identity) && browserControlIdentity;
    final cdpByDescription =
        _hasCdpSignal(descriptive) && browserControlIdentity;

    return chromeDevtoolsMcpLaunch ||
        (chromeDevtoolsByIdentity && browserControlIdentity) ||
        (jsReverseByIdentity && browserControlIdentity) ||
        cdpByIdentity ||
        cdpByDescription;
  }

  static bool _hasChromeDevtoolsSignal(String value) {
    return _containsAny(value, const <String>[
          'chrome-devtools',
          'chrome_devtools',
          'chrome devtools',
          'chrome devtools protocol',
        ]) ||
        (value.contains('chrome') && value.contains('devtools'));
  }

  static bool _hasCdpSignal(String value) {
    return _cdpTokenPattern.hasMatch(value) ||
        _hasChromeDevtoolsSignal(value) ||
        _hasJsReverseSignal(value) ||
        _containsAny(value, const <String>[
          'devtools protocol',
          'remote debugging protocol',
        ]);
  }

  static bool _hasJsReverseSignal(String value) {
    return _containsAny(value, const <String>[
      'js-reverse',
      'js_reverse',
      'javascript reverse',
      'web reverse',
    ]);
  }

  static bool _hasBrowserControlIdentity(String value) {
    final hasBrowserHost =
        _hasCdpSignal(value) ||
        _containsAny(value, const <String>[
          'browser',
          'chrome',
          'chromium',
          'edge',
          'devtools',
        ]);
    if (!hasBrowserHost) return false;

    return _containsAny(value, const <String>[
      'call',
      'click',
      'close',
      'command',
      'console',
      'cookie',
      'debug',
      'dom',
      'drag',
      'emulate',
      'evaluate',
      'fill',
      'form',
      'get',
      'handle',
      'har',
      'hover',
      'input',
      'key',
      'list',
      'navigate',
      'navigation',
      'network',
      'page',
      'performance',
      'press',
      'request',
      'resize',
      'runtime',
      'screenshot',
      'select',
      'send',
      'session',
      'snapshot',
      'sse',
      'storage',
      'tab',
      'target',
      'trace',
      'upload',
      'wait',
      'websocket',
    ]);
  }

  static bool _containsAny(String value, Iterable<String> needles) {
    for (final needle in needles) {
      if (value.contains(needle)) return true;
    }
    return false;
  }

  static String _joinParts(Iterable<Object?> parts) {
    return trimmedNonEmptyStrings(parts).join('\n').toLowerCase();
  }
}

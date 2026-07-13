import '../runtime/ai_tool_runtime_service.dart';
import 'mcp_reverse_tool_policy_utils.dart';

class WebReverseMcpToolPolicy {
  const WebReverseMcpToolPolicy._();

  static final RegExp _cdpTokenPattern = RegExp(
    r'(^|[^a-z0-9])cdp([^a-z0-9]|$)',
  );

  static Set<String> forceVisibleToolNames(AiResolvedToolCatalog catalog) {
    return forceVisibleMcpToolNames(
      catalog,
      (tool, catalogName) =>
          _shouldForceVisibleTool(tool, catalogName: catalogName),
    );
  }

  static bool _shouldForceVisibleTool(
    AiResolvedTool tool, {
    required String catalogName,
  }) {
    if (tool.source != AiRuntimeToolSource.mcp) return false;

    final text = mcpReverseToolSearchText(tool, catalogName: catalogName);
    final identity = text.identity;

    final chromeDevtoolsByIdentity = _hasChromeDevtoolsSignal(identity);
    final jsReverseByIdentity = _hasJsReverseSignal(identity);
    final chromeDevtoolsMcpLaunch = text.launchIdentity.contains(
      'chrome-devtools-mcp',
    );
    final nonCdpAutomationByIdentity =
        mcpToolSearchTextContainsAny(identity, const <String>[
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
        _hasCdpSignal(text.descriptive) && browserControlIdentity;

    return chromeDevtoolsMcpLaunch ||
        (chromeDevtoolsByIdentity && browserControlIdentity) ||
        (jsReverseByIdentity && browserControlIdentity) ||
        cdpByIdentity ||
        cdpByDescription;
  }

  static bool _hasChromeDevtoolsSignal(String value) {
    return mcpToolSearchTextContainsAny(value, const <String>[
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
        mcpToolSearchTextContainsAny(value, const <String>[
          'devtools protocol',
          'remote debugging protocol',
        ]);
  }

  static bool _hasJsReverseSignal(String value) {
    return mcpToolSearchTextContainsAny(value, const <String>[
      'js-reverse',
      'js_reverse',
      'javascript reverse',
      'web reverse',
    ]);
  }

  static bool _hasBrowserControlIdentity(String value) {
    final hasBrowserHost =
        _hasCdpSignal(value) ||
        mcpToolSearchTextContainsAny(value, const <String>[
          'browser',
          'chrome',
          'chromium',
          'edge',
          'devtools',
        ]);
    if (!hasBrowserHost) return false;

    return mcpToolSearchTextContainsAny(value, const <String>[
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
}

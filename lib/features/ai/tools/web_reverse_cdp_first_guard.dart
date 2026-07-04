import '../../../app/support/url_validation.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../service/web_reverse_runtime_metadata.dart';

class WebReverseCdpFirstDecision {
  const WebReverseCdpFirstDecision({
    required this.requestedUri,
    required this.targetUri,
    required this.routeKind,
    required this.toolNames,
    required this.requiresToolSearch,
    required this.fallbackToolLabel,
    this.nextActionOverride,
  });

  final Uri requestedUri;
  final Uri targetUri;
  final String routeKind;
  final List<String> toolNames;
  final bool requiresToolSearch;
  final String fallbackToolLabel;
  final String? nextActionOverride;

  List<String> get toolPreview => toolNames.take(8).toList(growable: false);

  String get toolText {
    final preview = toolPreview;
    return preview.isEmpty ? fallbackToolLabel : preview.join(', ');
  }

  String get targetOrigin => _httpOriginLabel(targetUri);

  String get requestedOrigin => _httpOriginLabel(requestedUri);

  String get nextAction {
    final override = nextActionOverride?.trim();
    if (override != null && override.isNotEmpty) return override;
    if (requiresToolSearch) {
      return 'Call ToolSearch first to load the CDP / Chrome DevTools / js-reverse MCP tools, then inspect the live browser with those exact tool names.';
    }
    return 'Use the exact callable CDP / Chrome DevTools / js-reverse MCP tools first: $toolText.';
  }

  String blockedMessage(String toolName) {
    final unavailable = routeKind == _WebReverseCdpRoute.unavailableKind;
    final reason = unavailable
        ? 'because live CDP is unavailable and this Web Reverse target must use local artifacts or restored CDP.'
        : 'because live CDP is available.';
    final allowed = unavailable
        ? 'Use $toolName only for unrelated external docs/static references. For this Web Reverse target, use local artifacts or restored CDP.'
        : 'Use $toolName only for unrelated external docs/static references, or after CDP-first target handling is no longer required.';
    return '$toolName is blocked for this Web Reverse target $reason\n'
        'target_origin: $targetOrigin\n'
        'requested_origin: $requestedOrigin\n'
        'next_action: $nextAction\n'
        'allowed: $allowed';
  }

  Map<String, Object?> metadata({
    required String requestedUrl,
    required String blockedFlag,
  }) {
    return <String, Object?>{
      blockedFlag: true,
      'web_reverse_cdp_first_block_reason':
          routeKind == _WebReverseCdpRoute.unavailableKind
          ? 'same_target_origin_without_live_cdp_runtime'
          : 'same_target_origin_with_live_cdp_runtime',
      'web_reverse_cdp_route': routeKind,
      'web_reverse_cdp_route_requires_tool_search': requiresToolSearch,
      'web_reverse_target_url': targetUri.toString(),
      'web_reverse_target_origin': targetOrigin,
      'web_reverse_requested_url': requestedUrl,
      'web_reverse_requested_origin': requestedOrigin,
      'web_reverse_cdp_tool_preview': toolPreview,
    };
  }
}

class WebReverseCdpFirstGuard {
  const WebReverseCdpFirstGuard._();

  static bool isRequired({required Map<String, Object?> metadata}) {
    final runtime = _webReverseRuntimeFromMetadata(metadata);
    return runtime != null &&
        webReverseRuntimeBoolTrue(runtime['cdp_first_required']);
  }

  static WebReverseCdpFirstDecision? evaluateUrl({
    required Uri requestedUri,
    required Map<String, Object?> metadata,
  }) {
    final runtime = _webReverseRuntimeFromMetadata(metadata);
    if (runtime == null ||
        !webReverseRuntimeBoolTrue(runtime['cdp_first_required'])) {
      return null;
    }

    final route = _webReverseCdpRoute(runtime);
    if (route == null) return null;

    for (final targetUri in _webReverseTargetUris(runtime)) {
      if (_isSameHttpTargetHost(requestedUri, targetUri)) {
        return WebReverseCdpFirstDecision(
          requestedUri: requestedUri,
          targetUri: targetUri,
          routeKind: route.kind,
          toolNames: route.toolNames,
          requiresToolSearch: route.requiresToolSearch,
          fallbackToolLabel: route.fallbackToolLabel,
          nextActionOverride: route.nextActionOverride,
        );
      }
    }
    return null;
  }

  static WebReverseCdpFirstDecision? evaluateCommand({
    required String command,
    required Map<String, Object?> metadata,
  }) {
    if (!_networkCommandPattern.hasMatch(command)) return null;
    for (final uri in _extractHttpUris(command)) {
      final decision = evaluateUrl(requestedUri: uri, metadata: metadata);
      if (decision != null) return decision;
    }
    return _evaluateTargetHostReference(command: command, metadata: metadata);
  }

  static WebReverseCdpFirstDecision? evaluateTextReference({
    required String text,
    required Map<String, Object?> metadata,
  }) {
    for (final uri in _extractHttpUris(text)) {
      final decision = evaluateUrl(requestedUri: uri, metadata: metadata);
      if (decision != null) return decision;
    }
    return _evaluateTargetHostReference(command: text, metadata: metadata);
  }

  static WebReverseCdpFirstDecision? _evaluateTargetHostReference({
    required String command,
    required Map<String, Object?> metadata,
  }) {
    final runtime = _webReverseRuntimeFromMetadata(metadata);
    if (runtime == null ||
        !webReverseRuntimeBoolTrue(runtime['cdp_first_required'])) {
      return null;
    }

    final route = _webReverseCdpRoute(runtime);
    if (route == null) return null;

    for (final targetUri in _webReverseTargetUris(runtime)) {
      if (_commandContainsTargetHostReference(command, targetUri.host)) {
        return WebReverseCdpFirstDecision(
          requestedUri: targetUri,
          targetUri: targetUri,
          routeKind: route.kind,
          toolNames: route.toolNames,
          requiresToolSearch: route.requiresToolSearch,
          fallbackToolLabel: route.fallbackToolLabel,
          nextActionOverride: route.nextActionOverride,
        );
      }
    }
    return null;
  }

  static const List<String> _networkCommandNamePatterns = <String>[
    'curl',
    'wget2?',
    'aria2c',
    'http',
    'https',
    'httpie',
    'httpx',
    'xh',
    'curlie',
    'grpcurl',
    'websocat',
    'wscat',
    'open',
    'xdg-open',
    'start',
    'osascript',
    'cmd(?:\\.exe)?',
    'powershell(?:\\.exe)?',
    'pwsh(?:\\.exe)?',
    'python3?',
    'node',
    'deno',
    'bun',
    'npm',
    'pnpm',
    'yarn',
    'ts-node',
    'tsx',
    'go',
    'java',
    'kotlin',
    'kotlinc',
    'scala',
    'dotnet',
    'swift',
    'dart',
    'flutter',
    'julia',
    'rscript',
    'r',
    'lua',
    'luajit',
    'ruby',
    'php',
    'perl',
    'npx',
    'playwright',
    'puppeteer',
    'google-chrome',
    'chrome',
    'chromium(?:-browser)?',
    'msedge',
    'microsoft-edge',
    'brave(?:-browser)?',
    'lynx',
    'links',
    'elinks',
    'w3m',
  ];

  static const List<String> _networkApiCallPatterns = <String>[
    'fetch',
    'axios',
    r'requests\.(?:get|post|put|patch|delete|request)',
    r'httpx\.(?:get|post|put|patch|delete|request)',
    r'urllib\.request',
  ];

  static const List<String> _powerShellNetworkCommandPatterns = <String>[
    'Invoke-WebRequest',
    'Invoke-RestMethod',
    'Start-Process',
    'iwr',
    'irm',
  ];

  static final RegExp _networkCommandPattern = RegExp(
    '(^|[\\s;&|()])(?:${_networkCommandNamePatterns.join('|')})\\b(?!:)|'
    '\\b(?:${_networkApiCallPatterns.join('|')})\\s*[\\.(]|'
    '\\b(?:${_powerShellNetworkCommandPatterns.join('|')})\\b',
    caseSensitive: false,
  );

  static List<Uri> _extractHttpUris(String command) {
    return extractHttpUrisFromText(command);
  }

  static bool _commandContainsTargetHostReference(String command, String host) {
    final siteHost = _protectedTargetSiteHost(host);
    if (siteHost.isEmpty) return false;
    final pattern = RegExp(
      '(^|[^A-Za-z0-9.-])(?:[A-Za-z0-9-]+\\.)*${RegExp.escape(siteHost)}([^A-Za-z0-9.-]|\$)',
      caseSensitive: false,
    );
    return pattern.hasMatch(command);
  }
}

Map<String, Object?>? _webReverseRuntimeFromMetadata(
  Map<String, Object?> metadata,
) {
  final runtime = webReverseRuntimeObjectMap(metadata['web_reverse_runtime']);
  if (runtime != null) {
    final currentCdpRuntime = webReverseRuntimeObjectMap(
      metadata['web_reverse_cdp_runtime'],
    );
    if (currentCdpRuntime == null) return runtime;
    return _runtimeWithCurrentCdpRuntime(runtime, currentCdpRuntime);
  }

  final config = webReverseRuntimeObjectMap(metadata['web_reverse_config']);
  final cdpRuntime = webReverseRuntimeObjectMap(
    metadata['web_reverse_cdp_runtime'],
  );
  if (config == null) return null;

  final dashboardState = <String, Object?>{};
  final currentTarget = metadata['web_reverse_browser_current_target'];
  if (currentTarget != null) {
    dashboardState['browser_current_target'] = currentTarget;
  }
  final tabUrls = metadata['web_reverse_browser_tab_urls'];
  if (tabUrls != null) {
    dashboardState['browser_tab_urls'] = tabUrls;
  }

  return <String, Object?>{
    'cdp_first_required': true,
    'config': config,
    if (cdpRuntime != null) 'cdp_runtime': cdpRuntime,
    if (dashboardState.isNotEmpty) 'dashboard_state': dashboardState,
    'cdp_mcp_tool_availability': <String, Object?>{
      'session_ai_cdp_mcp_enabled': webReverseRuntimeBoolTrue(
        config['cdp_mcp_enabled'],
      ),
      'browser_runtime_live': webReverseCdpRuntimeIsLive(cdpRuntime),
      'tool_search_available': false,
      'legacy_metadata_fallback': true,
    },
  };
}

Map<String, Object?> _runtimeWithCurrentCdpRuntime(
  Map<String, Object?> runtime,
  Map<String, Object?> currentCdpRuntime,
) {
  final next = <String, Object?>{...runtime, 'cdp_runtime': currentCdpRuntime};
  if (!webReverseCdpRuntimeIsLive(currentCdpRuntime)) {
    final availability = webReverseRuntimeObjectMap(
      runtime['cdp_mcp_tool_availability'],
    );
    if (availability != null) {
      next['cdp_mcp_tool_availability'] = <String, Object?>{
        ...availability,
        'browser_runtime_live': false,
        'live_cdp_actions_current_turn_callable': false,
      };
    }
  }
  return next;
}

_WebReverseCdpRoute? _webReverseCdpRoute(Map<String, Object?> runtime) {
  final availability = webReverseRuntimeObjectMap(
    runtime['cdp_mcp_tool_availability'],
  );
  final cdpRuntime = webReverseRuntimeObjectMap(runtime['cdp_runtime']);
  if (cdpRuntime != null && !webReverseCdpRuntimeIsLive(cdpRuntime)) {
    return _WebReverseCdpRoute.runtimeUnavailable();
  }

  final runtimeLive =
      webReverseRuntimeBoolTrue(availability?['browser_runtime_live']) ||
      (cdpRuntime != null && webReverseCdpRuntimeIsLive(cdpRuntime));
  if (!runtimeLive) return _WebReverseCdpRoute.runtimeUnavailable();

  final currentToolNames = stringListFromValue(
    availability?['current_turn_callable_names'],
  );
  final currentToolCount = intFromValue(
    availability?['current_turn_callable_count'],
    fallback: 0,
  );
  final currentCallable =
      webReverseRuntimeBoolTrue(
        availability?['live_cdp_actions_current_turn_callable'],
      ) ||
      (webReverseRuntimeBoolTrue(availability?['current_turn_callable']) &&
          (currentToolNames.isNotEmpty || currentToolCount > 0));
  if (currentCallable) {
    return _WebReverseCdpRoute.current(
      currentToolNames,
      fallbackToolLabel: currentToolCount > 0
          ? '$currentToolCount current CDP MCP tools'
          : 'current CDP MCP tools',
    );
  }

  final deferredToolNames = stringListFromValue(
    availability?['tool_search_deferred_cdp_mcp_names'],
  );
  final deferredToolCount = intFromValue(
    availability?['tool_search_deferred_cdp_mcp_count'],
    fallback: 0,
  );
  if (webReverseRuntimeBoolTrue(availability?['tool_search_available']) &&
      (deferredToolNames.isNotEmpty || deferredToolCount > 0)) {
    return _WebReverseCdpRoute.deferred(
      deferredToolNames,
      fallbackToolLabel: deferredToolCount > 0
          ? '$deferredToolCount deferred CDP MCP tools'
          : 'deferred CDP MCP tools',
    );
  }

  final toolSearchAvailable = webReverseRuntimeBoolTrue(
    availability?['tool_search_available'],
  );
  final sessionCdpMcpEnabled = webReverseRuntimeBoolTrue(
    availability?['session_ai_cdp_mcp_enabled'],
  );
  return _WebReverseCdpRoute.runtimeLiveWithoutTools(
    toolSearchAvailable: toolSearchAvailable,
    sessionCdpMcpEnabled: sessionCdpMcpEnabled,
  );
}

List<Uri> _webReverseTargetUris(Map<String, Object?> runtime) {
  final urls = <String>[];
  final config = webReverseRuntimeObjectMap(runtime['config']);
  _addUrl(urls, config?['target_url']);

  final cdpRuntime = webReverseRuntimeObjectMap(runtime['cdp_runtime']);
  _addUrl(
    urls,
    webReverseRuntimeObjectMap(cdpRuntime?['current_target'])?['url'],
  );

  final dashboardState = webReverseRuntimeObjectMap(runtime['dashboard_state']);
  _addUrl(
    urls,
    webReverseRuntimeObjectMap(
      dashboardState?['browser_current_target'],
    )?['url'],
  );
  final tabUrls = dashboardState?['browser_tab_urls'];
  if (tabUrls is List) {
    for (final entry in tabUrls) {
      if (entry is Map) {
        _addUrl(urls, webReverseRuntimeObjectMap(entry)?['url']);
      } else {
        _addUrl(urls, entry);
      }
    }
  }

  final seen = <String>{};
  final uris = <Uri>[];
  for (final url in urls) {
    final uri = tryParseValidHttpUrl(url);
    if (uri == null || uri.host.isEmpty) continue;
    final key =
        '${uri.scheme}://${uri.host.toLowerCase()}:${_effectivePort(uri)}';
    if (seen.add(key)) uris.add(uri);
  }
  return uris;
}

void _addUrl(List<String> urls, Object? raw) {
  final value = '${raw ?? ''}'.trim();
  if (value.isNotEmpty) urls.add(value);
}

bool _isSameHttpTargetHost(Uri requested, Uri target) {
  if (!_isHttpScheme(requested.scheme) || !_isHttpScheme(target.scheme)) {
    return false;
  }
  final requestedHost = _normalizeHttpHost(requested.host);
  final targetHost = _normalizeHttpHost(target.host);
  if (requestedHost.isEmpty || targetHost.isEmpty) return false;
  if (requestedHost == targetHost) return true;

  final protectedSite = _protectedTargetSiteHost(targetHost);
  if (protectedSite.isEmpty) return false;
  return requestedHost == protectedSite ||
      requestedHost.endsWith('.$protectedSite');
}

bool _isHttpScheme(String scheme) {
  final normalized = scheme.toLowerCase();
  return normalized == 'http' || normalized == 'https';
}

String _httpOriginLabel(Uri uri) {
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final port = _effectivePort(uri);
  final defaultPort = _defaultPort(uri.scheme);
  final portSuffix = defaultPort == port ? '' : ':$port';
  return '${uri.scheme.toLowerCase()}://$host$portSuffix';
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) return uri.port;
  return _defaultPort(uri.scheme);
}

int _defaultPort(String scheme) {
  return switch (scheme.toLowerCase()) {
    'http' => 80,
    'https' => 443,
    _ => 0,
  };
}

const Set<String> _targetSiteHostPrefixes = <String>{
  'www',
  'm',
  'mobile',
  'h5',
  'app',
};

String _protectedTargetSiteHost(String host) {
  final normalized = _normalizeHttpHost(host);
  final parts = normalized.split('.');
  if (parts.length >= 3 && _targetSiteHostPrefixes.contains(parts.first)) {
    return parts.skip(1).join('.');
  }
  return normalized;
}

String _normalizeHttpHost(String host) {
  var normalized = lowercaseStringFromValue(host);
  if (normalized.startsWith('[') && normalized.endsWith(']')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  return normalized;
}

class _WebReverseCdpRoute {
  const _WebReverseCdpRoute._({
    required this.kind,
    required this.toolNames,
    required this.requiresToolSearch,
    required this.fallbackToolLabel,
    this.nextActionOverride,
  });

  factory _WebReverseCdpRoute.current(
    List<String> toolNames, {
    required String fallbackToolLabel,
  }) {
    return _WebReverseCdpRoute._(
      kind: 'current_turn_callable',
      toolNames: toolNames,
      requiresToolSearch: false,
      fallbackToolLabel: fallbackToolLabel,
    );
  }

  factory _WebReverseCdpRoute.deferred(
    List<String> toolNames, {
    required String fallbackToolLabel,
  }) {
    return _WebReverseCdpRoute._(
      kind: 'deferred_tool_search',
      toolNames: toolNames,
      requiresToolSearch: true,
      fallbackToolLabel: fallbackToolLabel,
    );
  }

  factory _WebReverseCdpRoute.runtimeLiveWithoutTools({
    required bool toolSearchAvailable,
    required bool sessionCdpMcpEnabled,
  }) {
    return _WebReverseCdpRoute._(
      kind: 'runtime_live_without_callable_cdp_tools',
      toolNames: const <String>[],
      requiresToolSearch: false,
      fallbackToolLabel: 'live OpenHand CDP runtime',
      nextActionOverride: !sessionCdpMcpEnabled
          ? 'AI-side CDP MCP is disabled for this Web Reverse session. Use local jsonl/HAR artifacts, or ask the user to enable it in the Web Reverse debugger before live CDP MCP actions. Do not use target-origin WebFetch/Bash/WebSearch while a live CDP endpoint is available.'
          : toolSearchAvailable
          ? 'Call ToolSearch for CDP / Chrome DevTools / js-reverse MCP tools if available; otherwise wait for OpenHand to finish preparing transient CDP MCP or use local jsonl/HAR artifacts. Do not use target-origin WebFetch/Bash/WebSearch while a live CDP endpoint is available.'
          : 'Wait for OpenHand to finish preparing transient CDP MCP or use local jsonl/HAR artifacts; ask the user to restart or refresh CDP MCP if tools remain unavailable. Do not use target-origin WebFetch/Bash/WebSearch while a live CDP endpoint is available.',
    );
  }

  factory _WebReverseCdpRoute.runtimeUnavailable() {
    return const _WebReverseCdpRoute._(
      kind: unavailableKind,
      toolNames: <String>[],
      requiresToolSearch: false,
      fallbackToolLabel: 'Web Reverse local jsonl/HAR artifacts',
      nextActionOverride:
          'Live CDP is unavailable for this Web Reverse target. Use local jsonl/HAR artifacts, or ask the user to restart/restore the Web Reverse browser before live browser operations. Do not use target-origin WebFetch/Bash/WebSearch.',
    );
  }

  static const String unavailableKind = 'runtime_unavailable_without_live_cdp';

  final String kind;
  final List<String> toolNames;
  final bool requiresToolSearch;
  final String fallbackToolLabel;
  final String? nextActionOverride;
}

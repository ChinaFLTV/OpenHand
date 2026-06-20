import '../../../app/support/url_validation.dart';

class WebReverseCdpFirstDecision {
  const WebReverseCdpFirstDecision({
    required this.requestedUri,
    required this.targetUri,
    required this.routeKind,
    required this.toolNames,
    required this.requiresToolSearch,
    required this.fallbackToolLabel,
  });

  final Uri requestedUri;
  final Uri targetUri;
  final String routeKind;
  final List<String> toolNames;
  final bool requiresToolSearch;
  final String fallbackToolLabel;

  List<String> get toolPreview => toolNames.take(8).toList(growable: false);

  String get toolText {
    final preview = toolPreview;
    return preview.isEmpty ? fallbackToolLabel : preview.join(', ');
  }

  String get targetOrigin => _httpOriginLabel(targetUri);

  String get requestedOrigin => _httpOriginLabel(requestedUri);

  String get nextAction {
    if (requiresToolSearch) {
      return 'Call ToolSearch first to load the CDP MCP tools, then inspect the live browser with those exact tool names.';
    }
    return 'Use the exact callable CDP MCP tools first: $toolText.';
  }

  String blockedMessage(String toolName) {
    return '$toolName is blocked for this Web Reverse target because live CDP is available.\n'
        'target_origin: $targetOrigin\n'
        'requested_origin: $requestedOrigin\n'
        'next_action: $nextAction\n'
        'allowed: Use $toolName only for unrelated external docs/static references, or after live CDP is unavailable.';
  }

  Map<String, Object?> metadata({
    required String requestedUrl,
    required String blockedFlag,
  }) {
    return <String, Object?>{
      blockedFlag: true,
      'web_reverse_cdp_first_block_reason':
          'same_target_origin_with_live_cdp_route',
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

  static WebReverseCdpFirstDecision? evaluateUrl({
    required Uri requestedUri,
    required Map<String, Object?> metadata,
  }) {
    final runtime = _stringObjectMap(metadata['web_reverse_runtime']);
    if (runtime == null || !_boolValue(runtime['cdp_first_required'])) {
      return null;
    }

    final route = _webReverseCdpRoute(runtime);
    if (route == null) return null;

    for (final targetUri in _webReverseTargetUris(runtime)) {
      if (_isSameHttpOrigin(requestedUri, targetUri)) {
        return WebReverseCdpFirstDecision(
          requestedUri: requestedUri,
          targetUri: targetUri,
          routeKind: route.kind,
          toolNames: route.toolNames,
          requiresToolSearch: route.requiresToolSearch,
          fallbackToolLabel: route.fallbackToolLabel,
        );
      }
    }
    return null;
  }

  static WebReverseCdpFirstDecision? evaluateCommand({
    required String command,
    required Map<String, Object?> metadata,
  }) {
    if (!_looksLikeExplicitNetworkCommand(command)) return null;
    for (final uri in _extractHttpUris(command)) {
      final decision = evaluateUrl(requestedUri: uri, metadata: metadata);
      if (decision != null) return decision;
    }
    return null;
  }

  static final RegExp _networkCommandPattern = RegExp(
    r'(^|[\s;&|()])(?:curl|wget|aria2c|http|https|xh|open|xdg-open|start|python3?|node|deno|bun|ruby|php|perl|npx|playwright|puppeteer)\b|'
    r'\b(?:fetch|axios|requests\.(?:get|post|put|patch|delete|request)|httpx\.(?:get|post|put|patch|delete|request)|urllib\.request)\s*[\.(]',
    caseSensitive: false,
  );

  static final RegExp _httpUrlPattern = RegExp(
    "https?://[^\\s<>\"'\\)\\]}]+",
    caseSensitive: false,
  );

  static bool _looksLikeExplicitNetworkCommand(String command) {
    return _networkCommandPattern.hasMatch(command) &&
        _httpUrlPattern.hasMatch(command);
  }

  static List<Uri> _extractHttpUris(String command) {
    final uris = <Uri>[];
    final seen = <String>{};
    for (final match in _httpUrlPattern.allMatches(command)) {
      final raw = _trimUrlToken(match.group(0) ?? '');
      final uri = tryParseValidHttpUrl(raw);
      if (uri == null || uri.host.isEmpty) continue;
      final key = uri.toString();
      if (seen.add(key)) uris.add(uri);
    }
    return uris;
  }

  static String _trimUrlToken(String value) {
    return value.replaceFirst(RegExp(r'[,.;:]+$'), '');
  }
}

_WebReverseCdpRoute? _webReverseCdpRoute(Map<String, Object?> runtime) {
  final availability = _stringObjectMap(runtime['cdp_mcp_tool_availability']);
  final cdpRuntime = _stringObjectMap(runtime['cdp_runtime']);
  final runtimeLive =
      _boolValue(availability?['browser_runtime_live']) ||
      _boolValue(cdpRuntime?['browser_alive']);
  if (!runtimeLive) return null;

  final currentToolNames = _stringList(
    availability?['current_turn_callable_names'],
  );
  final currentToolCount = _intValue(
    availability?['current_turn_callable_count'],
  );
  final currentCallable =
      _boolValue(availability?['live_cdp_actions_current_turn_callable']) ||
      (_boolValue(availability?['current_turn_callable']) &&
          (currentToolNames.isNotEmpty || currentToolCount > 0));
  if (currentCallable) {
    return _WebReverseCdpRoute.current(
      currentToolNames,
      fallbackToolLabel: currentToolCount > 0
          ? '$currentToolCount current CDP MCP tools'
          : 'current CDP MCP tools',
    );
  }

  final deferredToolNames = _stringList(
    availability?['tool_search_deferred_cdp_mcp_names'],
  );
  final deferredToolCount = _intValue(
    availability?['tool_search_deferred_cdp_mcp_count'],
  );
  if (_boolValue(availability?['tool_search_available']) &&
      (deferredToolNames.isNotEmpty || deferredToolCount > 0)) {
    return _WebReverseCdpRoute.deferred(
      deferredToolNames,
      fallbackToolLabel: deferredToolCount > 0
          ? '$deferredToolCount deferred CDP MCP tools'
          : 'deferred CDP MCP tools',
    );
  }

  return null;
}

List<Uri> _webReverseTargetUris(Map<String, Object?> runtime) {
  final urls = <String>[];
  final config = _stringObjectMap(runtime['config']);
  _addUrl(urls, config?['target_url']);

  final cdpRuntime = _stringObjectMap(runtime['cdp_runtime']);
  _addUrl(urls, _stringObjectMap(cdpRuntime?['current_target'])?['url']);

  final dashboardState = _stringObjectMap(runtime['dashboard_state']);
  _addUrl(
    urls,
    _stringObjectMap(dashboardState?['browser_current_target'])?['url'],
  );
  final tabUrls = dashboardState?['browser_tab_urls'];
  if (tabUrls is List) {
    for (final entry in tabUrls) {
      if (entry is Map) {
        _addUrl(urls, _stringObjectMap(entry)?['url']);
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

bool _isSameHttpOrigin(Uri a, Uri b) {
  return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
      a.host.toLowerCase() == b.host.toLowerCase() &&
      _effectivePort(a) == _effectivePort(b);
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

Map<String, Object?>? _stringObjectMap(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is! Map) return null;
  return <String, Object?>{
    for (final entry in raw.entries) '${entry.key}': entry.value,
  };
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map((entry) => '$entry'.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

bool _boolValue(Object? raw) {
  if (raw is bool) return raw;
  final normalized = '${raw ?? ''}'.trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

int _intValue(Object? raw) {
  if (raw is num) return raw.toInt();
  return int.tryParse('${raw ?? ''}'.trim()) ?? 0;
}

class _WebReverseCdpRoute {
  const _WebReverseCdpRoute._({
    required this.kind,
    required this.toolNames,
    required this.requiresToolSearch,
    required this.fallbackToolLabel,
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

  final String kind;
  final List<String> toolNames;
  final bool requiresToolSearch;
  final String fallbackToolLabel;
}

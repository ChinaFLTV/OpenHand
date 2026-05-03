import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/net/http_redirect_utils.dart';
import '../../ai/service/ai_transport_diagnostic_messages.dart';
import '../model/mcp_server.dart';
import '../model/mcp_server_health.dart';
import '../model/mcp_tool.dart';

abstract class McpToolDiscoveryService {
  Future<McpToolCatalog> discoverTools(McpServer server);
  Future<McpServerHealth> checkHealth(McpServer server);
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  });

  void dispose();
}

class McpToolCallResult {
  const McpToolCallResult({
    required this.outputText,
    this.isError = false,
    this.rawResult,
  });

  final String outputText;
  final bool isError;
  final Object? rawResult;
}

class DefaultMcpToolDiscoveryService implements McpToolDiscoveryService {
  DefaultMcpToolDiscoveryService({http.Client? client})
    : _client = client ?? SystemProxyResolver.instance.createHttpClient();

  static const Duration _scanTimeout = Duration(seconds: 8);
  static const Duration _healthCheckTimeout = Duration(seconds: 6);
  static const Duration _requestTimeout = Duration(seconds: 6);
  static const Duration _toolCallTimeout = Duration(seconds: 30);
  static const Duration _legacyEndpointTimeout = Duration(seconds: 4);
  static const Duration _stdioShutdownTimeout = Duration(milliseconds: 400);
  static const int _maxStdioStdoutBufferBytes = 4 * 1024 * 1024;
  static const int _maxRedirects = 4;
  static const int _maxToolPages = 8;
  static const String _streamableHttpProtocolVersion = '2025-11-25';
  static const String _legacySseProtocolVersion = '2024-11-05';

  final http.Client _client;
  int _nextRequestId = 0;

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    final scannedAt = DateTime.now().toUtc();
    try {
      final discovered = await switch (server.type) {
        McpServerType.streamableHttp => _discoverOverStreamableHttp(server),
        McpServerType.sse => _discoverOverLegacySseWithFallback(server),
        McpServerType.stdio => _discoverOverStdio(server),
      }.timeout(_scanTimeout);
      return McpToolCatalog(
        status: McpToolCatalogStatus.ready,
        tools: discovered.tools,
        warningMessage: discovered.warningMessage,
        serverInstructions: discovered.serverInstructions,
        lastScannedAt: scannedAt,
      );
    } on TimeoutException {
      return McpToolCatalog(
        status: McpToolCatalogStatus.failed,
        errorMessage: _friendlyTimeoutMessage(
          server,
          stage: 'discover',
          limit: _scanTimeout,
        ),
        lastScannedAt: scannedAt,
      );
    } on McpToolDiscoveryException catch (error) {
      return McpToolCatalog(
        status: McpToolCatalogStatus.failed,
        errorMessage: error.message,
        lastScannedAt: scannedAt,
      );
    } catch (error) {
      return McpToolCatalog(
        status: McpToolCatalogStatus.failed,
        errorMessage: _friendlyMcpDiscoveryError(server, error),
        lastScannedAt: scannedAt,
      );
    }
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    final checkedAt = DateTime.now().toUtc();
    try {
      await switch (server.type) {
        McpServerType.streamableHttp => _checkStreamableHttpHealth(server),
        McpServerType.sse => _checkLegacySseHealthWithFallback(server),
        McpServerType.stdio => _checkStdioHealth(server),
      }.timeout(_healthCheckTimeout);
      return McpServerHealth(
        status: McpServerHealthStatus.healthy,
        lastCheckedAt: checkedAt,
      );
    } on TimeoutException {
      return McpServerHealth(
        status: McpServerHealthStatus.unhealthy,
        errorMessage: _friendlyTimeoutMessage(
          server,
          stage: 'health',
          limit: _healthCheckTimeout,
        ),
        lastCheckedAt: checkedAt,
      );
    } on McpToolDiscoveryException catch (error) {
      return McpServerHealth(
        status: McpServerHealthStatus.unhealthy,
        errorMessage: error.message,
        lastCheckedAt: checkedAt,
      );
    } catch (error) {
      return McpServerHealth(
        status: McpServerHealthStatus.unhealthy,
        errorMessage: _friendlyMcpDiscoveryError(server, error),
        lastCheckedAt: checkedAt,
      );
    }
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    late final Map<String, Object?> result;
    try {
      result = await switch (server.type) {
        McpServerType.streamableHttp => _callToolOverStreamableHttp(
          server,
          toolName,
          arguments,
        ),
        McpServerType.sse => _callToolOverLegacySseWithFallback(
          server,
          toolName,
          arguments,
        ),
        McpServerType.stdio => _callToolOverStdio(server, toolName, arguments),
      }.timeout(_toolCallTimeout);
    } on TimeoutException {
      throw const McpToolDiscoveryException(
        'Tool call timed out. The MCP server did not respond in time.',
      );
    }
    return McpToolCallResult(
      outputText: _renderToolCallResult(result),
      isError: result['isError'] == true,
      rawResult: result,
    );
  }

  Future<_DiscoveredTools> _discoverOverStreamableHttp(McpServer server) async {
    final session = await _initializeStreamableHttpSession(server);

    return _listTools(
      (cursor) => _postJsonRpc(
        server: server,
        uri: session.uri,
        protocolVersion: session.protocolVersion,
        sessionId: session.sessionId,
        payload: _jsonRpcRequest(
          id: _nextId(),
          method: 'tools/list',
          params: cursor == null ? null : <String, Object?>{'cursor': cursor},
        ),
        expectResponse: true,
      ).then((response) => response.message),
      serverInstructions: session.instructions,
    );
  }

  Future<_DiscoveredTools> _discoverOverLegacySse(McpServer server) async {
    final session = await _initializeLegacySseSession(server);
    try {
      return _listTools(
        (cursor) => session.sendRequest(
          _jsonRpcRequest(
            id: _nextId(),
            method: 'tools/list',
            params: cursor == null ? null : <String, Object?>{'cursor': cursor},
          ),
        ),
        serverInstructions: session.instructions,
      );
    } finally {
      await session.close();
    }
  }

  Future<_DiscoveredTools> _discoverOverLegacySseWithFallback(
    McpServer server,
  ) {
    return _runLegacySseWithStreamableFallback(
      primaryOperation: () => _discoverOverLegacySse(server),
      fallbackOperation: () => _discoverOverStreamableHttp(server),
    );
  }

  Future<_DiscoveredTools> _discoverOverStdio(McpServer server) async {
    final session = await _initializeStdioSession(server);
    try {
      return _listTools(
        (cursor) => session.sendRequest(
          _jsonRpcRequest(
            id: _nextId(),
            method: 'tools/list',
            params: cursor == null ? null : <String, Object?>{'cursor': cursor},
          ),
        ),
        serverInstructions: session.instructions,
      );
    } finally {
      await session.close();
    }
  }

  Future<Map<String, Object?>> _callToolOverStreamableHttp(
    McpServer server,
    String toolName,
    Map<String, Object?> arguments,
  ) async {
    final session = await _initializeStreamableHttpSession(server);
    final response = await _postJsonRpc(
      server: server,
      uri: session.uri,
      protocolVersion: session.protocolVersion,
      sessionId: session.sessionId,
      payload: _jsonRpcRequest(
        id: _nextId(),
        method: 'tools/call',
        params: <String, Object?>{'name': toolName, 'arguments': arguments},
      ),
      requestTimeout: _toolCallTimeout,
      expectResponse: true,
    );
    return _extractResult(response.message);
  }

  Future<Map<String, Object?>> _callToolOverLegacySse(
    McpServer server,
    String toolName,
    Map<String, Object?> arguments,
  ) async {
    final session = await _initializeLegacySseSession(server);
    try {
      return _extractResult(
        await session.sendRequest(
          _jsonRpcRequest(
            id: _nextId(),
            method: 'tools/call',
            params: <String, Object?>{'name': toolName, 'arguments': arguments},
          ),
          timeout: _toolCallTimeout,
        ),
      );
    } finally {
      await session.close();
    }
  }

  Future<Map<String, Object?>> _callToolOverLegacySseWithFallback(
    McpServer server,
    String toolName,
    Map<String, Object?> arguments,
  ) {
    return _runLegacySseWithStreamableFallback(
      primaryOperation: () =>
          _callToolOverLegacySse(server, toolName, arguments),
      fallbackOperation: () =>
          _callToolOverStreamableHttp(server, toolName, arguments),
    );
  }

  Future<Map<String, Object?>> _callToolOverStdio(
    McpServer server,
    String toolName,
    Map<String, Object?> arguments,
  ) async {
    final session = await _initializeStdioSession(server);
    try {
      return _extractResult(
        await session.sendRequest(
          _jsonRpcRequest(
            id: _nextId(),
            method: 'tools/call',
            params: <String, Object?>{'name': toolName, 'arguments': arguments},
          ),
          timeout: _toolCallTimeout,
        ),
      );
    } finally {
      await session.close();
    }
  }

  Future<void> _checkStreamableHttpHealth(McpServer server) async {
    await _initializeStreamableHttpSession(server);
  }

  Future<void> _checkLegacySseHealth(McpServer server) async {
    final session = await _initializeLegacySseSession(server);
    await session.close();
  }

  Future<void> _checkLegacySseHealthWithFallback(McpServer server) {
    return _runLegacySseWithStreamableFallback(
      primaryOperation: () => _checkLegacySseHealth(server),
      fallbackOperation: () => _checkStreamableHttpHealth(server),
    );
  }

  Future<void> _checkStdioHealth(McpServer server) async {
    final session = await _initializeStdioSession(server);
    await session.close();
  }

  Future<_InitializedStreamableHttpSession> _initializeStreamableHttpSession(
    McpServer server,
  ) async {
    final uri = _parseServerUri(server.url);
    final initializeResponse = await _postJsonRpc(
      server: server,
      uri: uri,
      protocolVersion: _streamableHttpProtocolVersion,
      payload: _jsonRpcInitializeRequest(
        id: _nextId(),
        protocolVersion: _streamableHttpProtocolVersion,
      ),
      expectResponse: true,
    );
    final initializeResult = _extractResult(initializeResponse.message);
    final protocolVersion = _readText(initializeResult['protocolVersion']);
    final instructions = _readText(initializeResult['instructions']);
    final negotiatedProtocolVersion = protocolVersion.isNotEmpty
        ? protocolVersion
        : _streamableHttpProtocolVersion;
    final resolvedUri = initializeResponse.uri ?? uri;

    await _postJsonRpc(
      server: server,
      uri: resolvedUri,
      protocolVersion: negotiatedProtocolVersion,
      sessionId: initializeResponse.sessionId,
      payload: _jsonRpcNotification('notifications/initialized'),
      expectResponse: false,
    );
    return _InitializedStreamableHttpSession(
      uri: resolvedUri,
      protocolVersion: negotiatedProtocolVersion,
      sessionId: initializeResponse.sessionId,
      instructions: instructions,
    );
  }

  Future<_LegacySseSession> _initializeLegacySseSession(
    McpServer server,
  ) async {
    final session = await _LegacySseSession.connect(
      client: _client,
      sseUri: _parseServerUri(server.url),
      headers: server.headers,
      sensitiveHeaderNames: _sensitiveHeaderNames(server.headers),
      endpointTimeout: _legacyEndpointTimeout,
      requestTimeout: _requestTimeout,
    );
    try {
      final initializeResult = _extractResult(
        await session.sendRequest(
          _jsonRpcInitializeRequest(
            id: _nextId(),
            protocolVersion: _legacySseProtocolVersion,
          ),
        ),
      );
      session.instructions = _readText(initializeResult['instructions']);
      await session.sendNotification(
        _jsonRpcNotification('notifications/initialized'),
      );
      return session;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  Future<_StdioSession> _initializeStdioSession(McpServer server) async {
    final session = _StdioSession(
      process: await Process.start(
        server.command,
        server.args,
        runInShell: Platform.isWindows,
      ),
      requestTimeout: _requestTimeout,
    );
    try {
      final initializeResult = _extractResult(
        await session.sendRequest(
          _jsonRpcInitializeRequest(
            id: _nextId(),
            protocolVersion: _streamableHttpProtocolVersion,
          ),
        ),
      );
      session.instructions = _readText(initializeResult['instructions']);
      await session.sendNotification(
        _jsonRpcNotification('notifications/initialized'),
      );
      return session;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  Future<_DiscoveredTools> _listTools(
    Future<Map<String, Object?>?> Function(String? cursor) sendRequest, {
    String serverInstructions = '',
  }) async {
    final tools = <McpTool>[];
    final warnings = <String>[];
    final seenToolIds = <String>{};
    var cursor = '';
    var invalidTools = 0;
    var duplicateTools = 0;
    var metadataWarnings = 0;

    for (var pageIndex = 0; pageIndex < _maxToolPages; pageIndex++) {
      final envelope = await sendRequest(cursor.isEmpty ? null : cursor);
      final result = _extractResult(envelope);
      final rawTools = result['tools'];
      if (rawTools is! List) {
        throw const McpToolDiscoveryException(
          'Tool scan failed because the server returned an invalid tools list.',
        );
      }
      for (final rawTool in rawTools) {
        final parsedTool = _parseTool(rawTool);
        if (parsedTool == null) {
          invalidTools += 1;
          continue;
        }
        if (!seenToolIds.add(parsedTool.id)) {
          duplicateTools += 1;
          continue;
        }
        if (parsedTool.hasMetadataWarning) {
          metadataWarnings += 1;
        }
        tools.add(parsedTool);
      }
      final nextCursor = _readText(result['nextCursor']);
      if (nextCursor.isEmpty) {
        cursor = '';
        break;
      }
      cursor = nextCursor;
    }

    if (cursor.isNotEmpty) {
      warnings.add(
        'Tool scan stopped after $_maxToolPages pages. The tool list may be incomplete.',
      );
    }
    if (invalidTools > 0) {
      warnings.add(
        'Ignored $invalidTools invalid tool entr${invalidTools == 1 ? 'y' : 'ies'}.',
      );
    }
    if (duplicateTools > 0) {
      warnings.add(
        'Ignored $duplicateTools duplicate tool entr${duplicateTools == 1 ? 'y' : 'ies'}.',
      );
    }
    if (metadataWarnings > 0) {
      warnings.add(
        '$metadataWarnings tool entr${metadataWarnings == 1 ? 'y has' : 'ies have'} incomplete metadata.',
      );
    }

    return _DiscoveredTools(
      tools: tools,
      warningMessage: warnings.isEmpty ? null : warnings.join(' '),
      serverInstructions: serverInstructions,
    );
  }

  McpTool? _parseTool(Object? rawTool) {
    final rawMap = _asMap(rawTool);
    if (rawMap == null) {
      return null;
    }

    final id = _readText(rawMap['name']);
    if (id.isEmpty) {
      return null;
    }

    final displayName =
        _firstNonEmptyText(rawMap, const <String>['title', 'displayName']) ??
        id;
    final description =
        _firstNonEmptyText(rawMap, const <String>[
          'description',
          'summary',
          'details',
        ]) ??
        '';
    final rawInputSchema = _firstPresentValue(rawMap, const <String>[
      'inputSchema',
      'input_schema',
      'parameters',
      'argsSchema',
      'argumentSchema',
    ]);
    final resolvedOutputMetadata = _resolveToolOutputMetadata(
      rawMap,
      description,
    );
    final rawOutputSchema = resolvedOutputMetadata.rawSchema;
    final inputSchema = _asMap(rawInputSchema);
    final outputSchema = _asMap(rawOutputSchema);
    final annotations =
        _asMap(rawMap['annotations']) ?? const <String, Object?>{};
    final execution = _asMap(rawMap['execution']) ?? const <String, Object?>{};
    final metadataWarnings = <String>[];

    final resolvedInputSchema =
        inputSchema ?? const <String, Object?>{'type': 'object'};
    if (rawInputSchema == null) {
      metadataWarnings.add('Missing input schema.');
    } else if (inputSchema == null) {
      metadataWarnings.add(
        'Input schema is not a structured object. Showing raw metadata instead.',
      );
    }
    if (rawOutputSchema != null && outputSchema == null) {
      metadataWarnings.add(
        'Output schema is not a structured object. Showing raw metadata instead.',
      );
    }

    return McpTool(
      id: id,
      name: displayName,
      description: description,
      inputSchema: resolvedInputSchema,
      outputSchema: outputSchema,
      outputDescription: resolvedOutputMetadata.description,
      outputDescriptionIsInferred: resolvedOutputMetadata.descriptionIsInferred,
      annotations: annotations,
      execution: execution,
      rawInputSchema: rawInputSchema,
      rawOutputSchema: rawOutputSchema,
      rawMetadata: rawMap,
      metadataWarning: metadataWarnings.isEmpty
          ? null
          : metadataWarnings.join(' '),
    );
  }

  Future<_JsonRpcHttpResponse> _postJsonRpc({
    required McpServer server,
    required Uri uri,
    required String protocolVersion,
    required Map<String, Object?> payload,
    String? sessionId,
    Duration? requestTimeout,
    required bool expectResponse,
  }) async {
    final headers = _mergeRequestHeaders(
      baseHeaders: const <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json, text/event-stream',
      },
      extraHeaders: server.headers,
      protectedHeaderNames: const <String>{
        'content-type',
        'accept',
        'mcp-protocol-version',
        'mcp-session-id',
      },
    );
    if (protocolVersion.trim().isNotEmpty) {
      headers['mcp-protocol-version'] = protocolVersion.trim();
    }
    if (sessionId?.trim().isNotEmpty ?? false) {
      headers['mcp-session-id'] = sessionId!.trim();
    }

    final response = await _sendRequestWithRedirects(
      client: _client,
      method: 'POST',
      uri: uri,
      headers: headers,
      body: jsonEncode(payload),
      requestTimeout: requestTimeout ?? _requestTimeout,
      maxRedirects: _maxRedirects,
      additionalSensitiveHeaderNames: _sensitiveHeaderNames(server.headers),
    );
    final responseUri = response.request?.url ?? uri;
    final responseSessionId = _readHeader(response.headers, 'mcp-session-id');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final responseBody = await response.stream.bytesToString();
      throw McpToolDiscoveryException(
        'Tool scan request failed with HTTP ${response.statusCode}${responseBody.trim().isEmpty ? '' : ': ${responseBody.trim()}'}',
      );
    }
    if (!expectResponse) {
      await response.stream.drain<void>();
      return _JsonRpcHttpResponse(
        sessionId: responseSessionId,
        uri: responseUri,
      );
    }

    final contentType = _readHeader(response.headers, 'content-type');
    final body = await response.stream.bytesToString();
    if (contentType.contains('text/event-stream')) {
      final message = _firstSseJsonRpcMessage(body, payload['id']);
      return _JsonRpcHttpResponse(
        message: message,
        sessionId: responseSessionId,
        uri: responseUri,
      );
    }

    final decoded = jsonDecode(body);
    final message = _firstJsonRpcMessageForRequestId(decoded, payload['id']);
    if (message == null) {
      throw const McpToolDiscoveryException(
        'Tool scan failed because the MCP server returned an invalid JSON-RPC response.',
      );
    }
    return _JsonRpcHttpResponse(
      message: message,
      sessionId: responseSessionId,
      uri: responseUri,
    );
  }

  Future<T> _runLegacySseWithStreamableFallback<T>({
    required Future<T> Function() primaryOperation,
    required Future<T> Function() fallbackOperation,
  }) async {
    try {
      return await primaryOperation();
    } on TimeoutException {
      return fallbackOperation();
    } on McpToolDiscoveryException catch (error) {
      if (!_shouldFallbackFromLegacySse(error)) {
        rethrow;
      }
      return fallbackOperation();
    }
  }

  bool _shouldFallbackFromLegacySse(McpToolDiscoveryException error) {
    final message = error.message.toLowerCase();
    return message.contains('sse endpoint') ||
        message.contains('message endpoint') ||
        message.contains('http 301') ||
        message.contains('http 302') ||
        message.contains('http 303') ||
        message.contains('http 307') ||
        message.contains('http 308') ||
        message.contains('http 404') ||
        message.contains('http 405') ||
        message.contains('http 406') ||
        message.contains('http 415') ||
        message.contains('invalid json-rpc') ||
        message.contains('did not return a response');
  }

  Map<String, Object?> _jsonRpcRequest({
    required int id,
    required String method,
    Map<String, Object?>? params,
  }) {
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      ...?(params == null ? null : <String, Object?>{'params': params}),
    };
  }

  Map<String, Object?> _jsonRpcInitializeRequest({
    required int id,
    required String protocolVersion,
  }) {
    return _jsonRpcRequest(
      id: id,
      method: 'initialize',
      params: <String, Object?>{
        'protocolVersion': protocolVersion,
        'capabilities': const <String, Object?>{},
        'clientInfo': const <String, Object?>{
          'name': 'OpenHand',
          'version': '1.0.0',
        },
      },
    );
  }

  Map<String, Object?> _jsonRpcNotification(
    String method, {
    Map<String, Object?>? params,
  }) {
    return <String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      ...?(params == null ? null : <String, Object?>{'params': params}),
    };
  }

  Map<String, Object?> _extractResult(Map<String, Object?>? envelope) {
    if (envelope == null) {
      throw const McpToolDiscoveryException(
        'Tool scan failed because the MCP server did not return a response.',
      );
    }
    final error = _asMap(envelope['error']);
    if (error != null) {
      final message = _readText(error['message']);
      throw McpToolDiscoveryException(
        message.isEmpty
            ? 'Tool scan failed because the MCP server returned an error.'
            : message,
      );
    }
    final result = _asMap(envelope['result']);
    if (result == null) {
      throw const McpToolDiscoveryException(
        'Tool scan failed because the MCP server returned an invalid result payload.',
      );
    }
    return result;
  }

  Uri _parseServerUri(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme) {
      throw const McpToolDiscoveryException(
        'Tool scan failed because the MCP server URL is invalid.',
      );
    }
    return uri;
  }

  Map<String, Object?>? _firstSseJsonRpcMessage(
    Object body,
    Object? requestId,
  ) {
    final events = _parseSseEvents('$body');
    for (final event in events) {
      if (event.name.isNotEmpty && event.name != 'message') {
        continue;
      }
      try {
        final decoded = jsonDecode(event.data);
        final message = _firstJsonRpcMessageForRequestId(decoded, requestId);
        if (message != null) {
          return message;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String _readText(Object? value) {
    final text = '$value'.trim();
    if (text == 'null') {
      return '';
    }
    return text;
  }

  String _renderToolCallResult(Map<String, Object?> result) {
    final content = result['content'];
    if (content is List) {
      final renderedItems = content
          .map((item) => _renderToolCallContentItem(item))
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (renderedItems.isNotEmpty) {
        final isError = result['isError'] == true;
        final buffer = StringBuffer()
          ..writeln('is_error: $isError')
          ..writeln('content:')
          ..write(renderedItems.join('\n'));
        return buffer.toString().trim();
      }
    }
    return const JsonEncoder.withIndent('  ').convert(result);
  }

  String _renderToolCallContentItem(Object? rawItem) {
    final item = _asMap(rawItem);
    if (item == null) {
      return '$rawItem'.trim();
    }
    final type = _readText(item['type']);
    switch (type) {
      case 'text':
        return _readText(item['text']);
      case 'image':
        return '[image] ${_readText(item['mimeType'])}';
      case 'resource':
        return '[resource] ${_readText(item['uri'])}';
      case 'resource_link':
        return '[resource_link] ${_readText(item['uri'])}';
      default:
        return const JsonEncoder.withIndent('  ').convert(item);
    }
  }

  String _readHeader(Map<String, String> headers, String name) {
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) {
        return entry.value.trim();
      }
    }
    return '';
  }

  Object? _firstPresentValue(Map<String, Object?> source, List<String> keys) {
    for (final key in keys) {
      if (source.containsKey(key)) {
        return source[key];
      }
    }
    return null;
  }

  String? _firstNonEmptyText(Map<String, Object?> source, List<String> keys) {
    for (final key in keys) {
      final value = _readText(source[key]);
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  _ResolvedToolOutputMetadata _resolveToolOutputMetadata(
    Map<String, Object?> rawMap,
    String toolDescription,
  ) {
    const schemaKeys = <String>[
      'outputSchema',
      'output_schema',
      'returnSchema',
      'return_schema',
      'resultSchema',
      'result_schema',
      'responseSchema',
      'response_schema',
    ];
    const descriptorKeys = <String>[
      'returns',
      'returnValue',
      'return_value',
      'result',
      'response',
      'output',
    ];
    const descriptionKeys = <String>[
      'outputDescription',
      'output_description',
      'returnDescription',
      'return_description',
      'resultDescription',
      'result_description',
      'responseDescription',
      'response_description',
      'returnsDescription',
      'returns_description',
    ];

    final containers = _toolMetadataContainers(rawMap);
    Object? rawSchema;
    String? description;
    var descriptionIsInferred = false;

    rawSchema = _firstPresentValue(rawMap, schemaKeys);
    for (final container in containers) {
      rawSchema ??= _firstPresentValue(container, schemaKeys);
      final descriptor = _firstPresentValue(container, descriptorKeys);
      final resolvedDescriptor = _resolveOutputDescriptor(descriptor);
      rawSchema ??= resolvedDescriptor.rawSchema;
      description ??= resolvedDescriptor.description;
    }

    if (rawSchema is Map) {
      final rawSchemaMap = Map<String, Object?>.from(rawSchema);
      final nestedDescriptor = _resolveOutputDescriptor(rawSchemaMap);
      if (nestedDescriptor.rawSchema != null) {
        rawSchema = nestedDescriptor.rawSchema;
      }
      description ??= nestedDescriptor.description;
    }

    for (final container in containers) {
      description ??= _firstNonEmptyText(container, descriptionKeys);
    }
    description ??= _schemaDescription(rawSchema);
    if (description == null) {
      description = _inferOutputDescriptionFromToolDescription(toolDescription);
      descriptionIsInferred = description != null;
    }

    return _ResolvedToolOutputMetadata(
      rawSchema: rawSchema,
      description: description,
      descriptionIsInferred: descriptionIsInferred,
    );
  }

  List<Map<String, Object?>> _toolMetadataContainers(
    Map<String, Object?> rawMap,
  ) {
    final containers = <Map<String, Object?>>[rawMap];
    for (final key in const <String>[
      'annotations',
      '_meta',
      'meta',
      'metadata',
    ]) {
      final container = _asMap(rawMap[key]);
      if (container != null) {
        containers.add(container);
      }
    }
    return containers;
  }

  _ResolvedToolOutputMetadata _resolveOutputDescriptor(Object? descriptor) {
    final descriptorMap = _asMap(descriptor);
    if (descriptorMap == null) {
      final description = _readText(descriptor);
      return _ResolvedToolOutputMetadata(
        description: description.isEmpty ? null : description,
      );
    }

    final nestedSchema = descriptorMap.containsKey('schema')
        ? descriptorMap['schema']
        : _firstPresentValue(descriptorMap, const <String>[
            'outputSchema',
            'output_schema',
            'returnSchema',
            'return_schema',
            'resultSchema',
            'result_schema',
            'responseSchema',
            'response_schema',
          ]);
    final rawSchema =
        nestedSchema ??
        (_looksLikeSchemaMap(descriptorMap) ? descriptorMap : null);
    final description =
        _firstNonEmptyText(descriptorMap, const <String>[
          'description',
          'summary',
          'details',
          'title',
          'text',
        ]) ??
        _schemaDescription(rawSchema);
    return _ResolvedToolOutputMetadata(
      rawSchema: rawSchema,
      description: description,
    );
  }

  bool _looksLikeSchemaMap(Map<String, Object?> value) {
    for (final key in const <String>[
      'type',
      'properties',
      'items',
      'required',
      'oneOf',
      'anyOf',
      'allOf',
      '\$ref',
      'enum',
    ]) {
      if (value.containsKey(key)) {
        return true;
      }
    }
    return false;
  }

  String? _schemaDescription(Object? schema) {
    final schemaMap = _asMap(schema);
    if (schemaMap == null) {
      return null;
    }
    return _firstNonEmptyText(schemaMap, const <String>[
      'description',
      'summary',
      'details',
      'title',
    ]);
  }

  String? _inferOutputDescriptionFromToolDescription(String description) {
    final normalized = description.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final matchedLines = normalized
        .split(RegExp(r'[\r\n]+'))
        .map((item) => item.trim())
        .where(
          (item) => item.isNotEmpty && _looksLikeOutputDescriptionLine(item),
        )
        .toList(growable: false);
    if (matchedLines.isNotEmpty) {
      return matchedLines.join('\n');
    }

    final sentenceMatch = RegExp(
      r'[^。！？.!?]*(返回|输出|结果|returns?|output|response|result)[^。！？.!?]*[。！？.!?]?',
      caseSensitive: false,
    ).allMatches(normalized);
    final sentences = sentenceMatch
        .map((match) => match.group(0)?.trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (sentences.isNotEmpty) {
      return sentences.join('\n');
    }
    return null;
  }

  bool _looksLikeOutputDescriptionLine(String line) {
    final normalized = line.toLowerCase();
    return line.contains('返回') ||
        line.contains('输出') ||
        line.contains('结果') ||
        normalized.contains('return') ||
        normalized.contains('output') ||
        normalized.contains('response') ||
        normalized.contains('result');
  }

  Map<String, Object?>? _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    return null;
  }

  List<_SseEvent> _parseSseEvents(String body) {
    final normalized = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split('\n\n');
    final events = <_SseEvent>[];
    for (final block in blocks) {
      final trimmedBlock = block.trim();
      if (trimmedBlock.isEmpty) {
        continue;
      }
      var eventName = '';
      final dataLines = <String>[];
      for (final line in trimmedBlock.split('\n')) {
        if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
          continue;
        }
        if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trim());
        }
      }
      if (dataLines.isEmpty) {
        continue;
      }
      events.add(_SseEvent(name: eventName, data: dataLines.join('\n')));
    }
    return events;
  }

  int _nextId() {
    _nextRequestId += 1;
    return _nextRequestId;
  }

  @override
  void dispose() {
    _client.close();
  }
}

Map<String, Object?>? _jsonRpcMessageAsMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return null;
}

Iterable<Map<String, Object?>> _jsonRpcMessagesFromDecoded(
  Object? value,
) sync* {
  final singleMessage = _jsonRpcMessageAsMap(value);
  if (singleMessage != null) {
    yield singleMessage;
    return;
  }
  if (value is! List) {
    return;
  }
  for (final item in value) {
    final message = _jsonRpcMessageAsMap(item);
    if (message != null) {
      yield message;
    }
  }
}

Map<String, Object?>? _firstJsonRpcMessageForRequestId(
  Object? value,
  Object? requestId,
) {
  final requestIdText = '$requestId';
  for (final message in _jsonRpcMessagesFromDecoded(value)) {
    if ('${message['id']}' == requestIdText) {
      return message;
    }
  }
  return null;
}

Future<http.StreamedResponse> _sendRequestWithRedirects({
  required http.Client client,
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  String? body,
  required Duration requestTimeout,
  required int maxRedirects,
  Set<String> additionalSensitiveHeaderNames = const <String>{},
}) async {
  var currentMethod = method;
  var currentUri = uri;
  var currentBody = body;
  final currentHeaders = Map<String, String>.from(headers);

  for (var redirectCount = 0; ; redirectCount++) {
    final request = http.Request(currentMethod, currentUri)
      ..followRedirects = false
      ..headers.addAll(currentHeaders);
    if (currentBody != null) {
      request.body = currentBody;
    }

    final response = await client.send(request).timeout(requestTimeout);
    if (!isRedirectStatusCode(response.statusCode)) {
      return response;
    }

    final redirectLocation = readResponseHeader(response.headers, 'location');
    if (redirectLocation.isEmpty) {
      return response;
    }
    if (redirectCount >= maxRedirects) {
      final responseBody = await response.stream.bytesToString();
      throw McpToolDiscoveryException(
        'Tool scan request followed too many redirects (${maxRedirects + 1})${responseBody.trim().isEmpty ? '' : ': ${responseBody.trim()}'}',
      );
    }

    await response.stream.drain<void>();
    final redirectedUri = currentUri.resolve(redirectLocation);
    if (isCrossOriginRedirect(currentUri, redirectedUri)) {
      _stripSensitiveRedirectHeaders(
        currentHeaders,
        additionalSensitiveHeaderNames,
      );
    }
    currentUri = redirectedUri;
    if (response.statusCode == 303 &&
        currentMethod != 'GET' &&
        currentMethod != 'HEAD') {
      currentMethod = 'GET';
      currentBody = null;
    }
  }
}

void _stripSensitiveRedirectHeaders(
  Map<String, String> headers,
  Set<String> additionalSensitiveHeaderNames,
) {
  final sensitiveHeaderNames = <String>{
    'authorization',
    'cookie',
    'mcp-session-id',
    'proxy-authorization',
    ...additionalSensitiveHeaderNames.map((item) => item.toLowerCase()),
  };
  headers.removeWhere(
    (name, value) => sensitiveHeaderNames.contains(name.toLowerCase()),
  );
}

class McpToolDiscoveryException implements Exception {
  const McpToolDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DiscoveredTools {
  const _DiscoveredTools({
    required this.tools,
    this.warningMessage,
    this.serverInstructions = '',
  });

  final List<McpTool> tools;
  final String? warningMessage;
  final String serverInstructions;
}

class _ResolvedToolOutputMetadata {
  const _ResolvedToolOutputMetadata({
    this.rawSchema,
    this.description,
    this.descriptionIsInferred = false,
  });

  final Object? rawSchema;
  final String? description;
  final bool descriptionIsInferred;
}

class _InitializedStreamableHttpSession {
  const _InitializedStreamableHttpSession({
    required this.uri,
    required this.protocolVersion,
    this.sessionId,
    this.instructions = '',
  });

  final Uri uri;
  final String protocolVersion;
  final String? sessionId;
  final String instructions;
}

class _JsonRpcHttpResponse {
  const _JsonRpcHttpResponse({this.message, this.sessionId, this.uri});

  final Map<String, Object?>? message;
  final String? sessionId;
  final Uri? uri;
}

class _LegacySseSession {
  _LegacySseSession._({
    required http.Client client,
    required Uri endpointUri,
    required Map<String, String> headers,
    required Set<String> sensitiveHeaderNames,
    required StreamController<Map<String, Object?>> messages,
    required StreamSubscription<String> subscription,
    required Duration requestTimeout,
  }) : _client = client,
       _endpointUri = endpointUri,
       _headers = headers,
       _sensitiveHeaderNames = sensitiveHeaderNames,
       _messages = messages,
       _subscription = subscription,
       _requestTimeout = requestTimeout;

  final http.Client _client;
  final Uri _endpointUri;
  final Map<String, String> _headers;
  final Set<String> _sensitiveHeaderNames;
  final StreamController<Map<String, Object?>> _messages;
  final StreamSubscription<String> _subscription;
  final Duration _requestTimeout;
  String instructions = '';

  static Future<_LegacySseSession> connect({
    required http.Client client,
    required Uri sseUri,
    required Map<String, String> headers,
    required Set<String> sensitiveHeaderNames,
    required Duration endpointTimeout,
    required Duration requestTimeout,
  }) async {
    final response = await _sendRequestWithRedirects(
      client: client,
      method: 'GET',
      uri: sseUri,
      headers: _mergeRequestHeaders(
        baseHeaders: const <String, String>{'accept': 'text/event-stream'},
        extraHeaders: headers,
        protectedHeaderNames: const <String>{'accept'},
      ),
      requestTimeout: requestTimeout,
      maxRedirects: DefaultMcpToolDiscoveryService._maxRedirects,
      additionalSensitiveHeaderNames: sensitiveHeaderNames,
    );
    final resolvedSseUri = response.request?.url ?? sseUri;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw McpToolDiscoveryException(
        'Tool scan could not connect to the SSE endpoint (HTTP ${response.statusCode})${body.trim().isEmpty ? '' : ': ${body.trim()}'}',
      );
    }
    final contentType = readResponseHeader(response.headers, 'content-type');
    if (!contentType.toLowerCase().contains('text/event-stream')) {
      final body = await response.stream.bytesToString();
      throw McpToolDiscoveryException(
        'Tool scan could not connect to the SSE endpoint because the server did not return an event stream${body.trim().isEmpty ? '' : ': ${body.trim()}'}',
      );
    }

    final endpointCompleter = Completer<Uri>();
    final messages = StreamController<Map<String, Object?>>.broadcast(
      sync: true,
    );
    var eventName = '';
    final dataLines = <String>[];

    void emitEvent() {
      if (dataLines.isEmpty) {
        eventName = '';
        return;
      }
      final data = dataLines.join('\n');
      if (eventName == 'endpoint' && !endpointCompleter.isCompleted) {
        final endpoint = Uri.tryParse(data.trim());
        if (endpoint != null) {
          endpointCompleter.complete(
            endpoint.hasScheme ? endpoint : resolvedSseUri.resolveUri(endpoint),
          );
        }
      } else if (eventName.isEmpty || eventName == 'message') {
        try {
          final decoded = jsonDecode(data);
          for (final message in _jsonRpcMessagesFromDecoded(decoded)) {
            if (messages.isClosed) {
              break;
            }
            messages.add(message);
          }
        } catch (error, stack) {
          silentLog(
            'mcp_tool_discovery_service',
            'decode SSE event payload',
            error,
            stack,
          );
        }
      }
      eventName = '';
      dataLines.clear();
    }

    late final StreamSubscription<String> subscription;
    subscription = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.isEmpty) {
              emitEvent();
              return;
            }
            if (line.startsWith('event:')) {
              eventName = line.substring(6).trim();
              return;
            }
            if (line.startsWith('data:')) {
              dataLines.add(line.substring(5).trim());
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!endpointCompleter.isCompleted) {
              endpointCompleter.completeError(error, stackTrace);
            }
            if (!messages.isClosed) {
              messages.addError(error, stackTrace);
            }
          },
          onDone: () {
            emitEvent();
            if (!endpointCompleter.isCompleted) {
              endpointCompleter.completeError(
                const McpToolDiscoveryException(
                  'Tool scan failed because the SSE endpoint closed before reporting a message endpoint.',
                ),
              );
            }
            if (!messages.isClosed) {
              unawaited(messages.close());
            }
          },
          cancelOnError: false,
        );
    try {
      final endpointUri = await endpointCompleter.future.timeout(
        endpointTimeout,
      );
      return _LegacySseSession._(
        client: client,
        endpointUri: endpointUri,
        headers: headers,
        sensitiveHeaderNames: sensitiveHeaderNames,
        messages: messages,
        subscription: subscription,
        requestTimeout: requestTimeout,
      );
    } catch (_) {
      await subscription.cancel();
      if (!messages.isClosed) {
        await messages.close();
      }
      rethrow;
    }
  }

  Future<Map<String, Object?>?> sendRequest(
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    final requestIdText = '${payload['id']}';
    final responseFuture = _messages.stream
        .firstWhere(
          (message) => '${message['id']}' == requestIdText,
          // Stream closed (e.g. server hung up) before a matching response
          // arrived. Surface a uniform timeout so callers handle a single
          // failure mode regardless of whether the stream closed or stalled.
          orElse: () => throw TimeoutException(
            'MCP stream closed before response for request $requestIdText',
          ),
        )
        .timeout(timeout ?? _requestTimeout);
    await _post(payload, timeout: timeout);
    return responseFuture;
  }

  Future<void> sendNotification(Map<String, Object?> payload) async {
    await _post(payload);
  }

  Future<void> _post(Map<String, Object?> payload, {Duration? timeout}) async {
    final response = await _sendRequestWithRedirects(
      client: _client,
      method: 'POST',
      uri: _endpointUri,
      headers: _mergeRequestHeaders(
        baseHeaders: const <String, String>{'content-type': 'application/json'},
        extraHeaders: _headers,
        protectedHeaderNames: const <String>{'content-type'},
      ),
      body: jsonEncode(payload),
      requestTimeout: timeout ?? _requestTimeout,
      maxRedirects: DefaultMcpToolDiscoveryService._maxRedirects,
      additionalSensitiveHeaderNames: _sensitiveHeaderNames,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw McpToolDiscoveryException(
        'Tool scan request failed with HTTP ${response.statusCode}${body.trim().isEmpty ? '' : ': ${body.trim()}'}',
      );
    }
    await response.stream.drain<void>();
  }

  Future<void> close() async {
    await _subscription.cancel();
    if (!_messages.isClosed) {
      await _messages.close();
    }
  }
}

class _StdioSession {
  _StdioSession({required Process process, required Duration requestTimeout})
    : _process = process,
      _requestTimeout = requestTimeout {
    _stdoutSubscription = _process.stdout.listen(
      _handleStdoutData,
      onError: (Object error, StackTrace stackTrace) {
        _failPendingResponses(error, stackTrace);
      },
      onDone: () {
        _appendTrace('stdout:done');
        _failPendingResponses(
          McpToolDiscoveryException(_closedUnexpectedlyMessage()),
        );
      },
      cancelOnError: false,
    );
    _stderrSubscription = _process.stderr.transform(utf8.decoder).listen((
      chunk,
    ) {
      if (_stderrBuffer.length >= 4096) {
        return;
      }
      _stderrBuffer.write(chunk);
    });
    unawaited(
      _process.exitCode.then((code) {
        _appendTrace('process:exit:$code');
      }),
    );
  }

  final Process _process;
  final Duration _requestTimeout;
  final List<int> _stdoutBuffer = <int>[];
  final StringBuffer _stderrBuffer = StringBuffer();
  final StringBuffer _traceBuffer = StringBuffer();
  final Map<String, Completer<Map<String, Object?>?>> _pendingResponses =
      <String, Completer<Map<String, Object?>?>>{};
  final Map<String, Map<String, Object?>> _bufferedResponses =
      <String, Map<String, Object?>>{};
  String instructions = '';
  late final StreamSubscription<List<int>> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;

  Future<Map<String, Object?>?> sendRequest(
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    final requestIdText = '${payload['id']}';
    final completer = Completer<Map<String, Object?>?>();
    _pendingResponses[requestIdText] = completer;
    try {
      await _write(payload);
    } catch (_) {
      _pendingResponses.remove(requestIdText);
      rethrow;
    }
    final bufferedResponse = _bufferedResponses.remove(requestIdText);
    if (bufferedResponse != null && !completer.isCompleted) {
      completer.complete(bufferedResponse);
    }
    try {
      return await completer.future.timeout(timeout ?? _requestTimeout);
    } finally {
      _pendingResponses.remove(requestIdText);
    }
  }

  Future<void> sendNotification(Map<String, Object?> payload) async {
    await _write(payload);
  }

  void _handleStdoutData(List<int> chunk) {
    try {
      _appendTrace('stdout:chunk:${chunk.length}');
      _stdoutBuffer.addAll(chunk);
      _drainStdoutBuffer();
      _enforceStdoutBufferLimit();
    } catch (error, stackTrace) {
      _failPendingResponses(error, stackTrace);
    }
  }

  void _drainStdoutBuffer() {
    while (true) {
      final payload = _takeNextMessage();
      if (payload == null) {
        return;
      }
      if (payload.isEmpty) {
        continue;
      }
      final decoded = jsonDecode(payload);
      for (final message in _jsonRpcMessagesFromDecoded(decoded)) {
        final messageIdText = _messageIdText(message['id']);
        _appendTrace(
          'stdout:message:${messageIdText.isEmpty ? message['method'] ?? 'unknown' : messageIdText}',
        );
        if (messageIdText.isEmpty) {
          continue;
        }
        final pendingResponse = _pendingResponses.remove(messageIdText);
        if (pendingResponse != null && !pendingResponse.isCompleted) {
          pendingResponse.complete(message);
          continue;
        }
        _bufferedResponses[messageIdText] = message;
      }
    }
  }

  String? _takeNextMessage() {
    while (true) {
      final framedMessage = _tryTakeFramedMessage();
      if (framedMessage != null) {
        return framedMessage;
      }
      _trimLeadingWhitespace();
      if (_stdoutBuffer.isEmpty) {
        return null;
      }
      if (_looksLikeFramedMessagePrefix()) {
        return null;
      }
      if (_looksLikeJsonLine(_stdoutBuffer.first)) {
        final newlineIndex = _stdoutBuffer.indexOf(10);
        if (newlineIndex == -1) {
          return null;
        }
        final lineBytes = _stdoutBuffer.sublist(0, newlineIndex);
        _stdoutBuffer.removeRange(0, newlineIndex + 1);
        return utf8.decode(lineBytes).trim();
      }
      final newlineIndex = _stdoutBuffer.indexOf(10);
      if (newlineIndex == -1) {
        return null;
      }
      _stdoutBuffer.removeRange(0, newlineIndex + 1);
    }
  }

  String? _tryTakeFramedMessage() {
    final headerEnd = _findHeaderEnd(_stdoutBuffer);
    if (headerEnd == -1) {
      return null;
    }
    final separatorLength = _headerSeparatorLength(_stdoutBuffer, headerEnd);
    final headerText = ascii.decode(
      _stdoutBuffer.sublist(0, headerEnd),
      allowInvalid: true,
    );
    final contentLength = _parseContentLength(headerText);
    if (contentLength == null) {
      _stdoutBuffer.removeRange(0, headerEnd + separatorLength);
      return '';
    }
    final bodyStart = headerEnd + separatorLength;
    final bodyEnd = bodyStart + contentLength;
    if (_stdoutBuffer.length < bodyEnd) {
      return null;
    }
    final bodyBytes = _stdoutBuffer.sublist(bodyStart, bodyEnd);
    _stdoutBuffer.removeRange(0, bodyEnd);
    return utf8.decode(bodyBytes);
  }

  void _trimLeadingWhitespace() {
    var trimLength = 0;
    while (trimLength < _stdoutBuffer.length) {
      final byte = _stdoutBuffer[trimLength];
      if (byte != 9 && byte != 10 && byte != 13 && byte != 32) {
        break;
      }
      trimLength += 1;
    }
    if (trimLength > 0) {
      _stdoutBuffer.removeRange(0, trimLength);
    }
  }

  bool _looksLikeJsonLine(int firstByte) {
    return firstByte == 0x7B || firstByte == 0x5B;
  }

  String _closedUnexpectedlyMessage() {
    final stderr = _stderrBuffer.toString().trim();
    final trace = _traceBuffer.toString().trim();
    final traceSuffix = trace.isEmpty ? '' : ' Trace: $trace';
    if (stderr.isEmpty) {
      return 'Tool scan failed because the stdio MCP server closed unexpectedly.$traceSuffix';
    }
    return 'Tool scan failed because the stdio MCP server closed unexpectedly: $stderr$traceSuffix';
  }

  void _enforceStdoutBufferLimit() {
    if (_stdoutBuffer.length <=
        DefaultMcpToolDiscoveryService._maxStdioStdoutBufferBytes) {
      return;
    }
    throw McpToolDiscoveryException(_stdoutOverflowMessage());
  }

  String _stdoutOverflowMessage() {
    final trace = _traceBuffer.toString().trim();
    final traceSuffix = trace.isEmpty ? '' : ' Trace: $trace';
    const maxMiB =
        DefaultMcpToolDiscoveryService._maxStdioStdoutBufferBytes ~/
        (1024 * 1024);
    return 'Tool scan failed because the stdio MCP server wrote more than $maxMiB MiB to stdout without a complete protocol message.$traceSuffix';
  }

  void _appendTrace(String message) {
    if (_traceBuffer.length >= 1024) {
      return;
    }
    if (_traceBuffer.isNotEmpty) {
      _traceBuffer.write(' | ');
    }
    _traceBuffer.write(message);
  }

  String _messageIdText(Object? value) {
    final text = '$value'.trim();
    if (text == 'null') {
      return '';
    }
    return text;
  }

  void _failPendingResponses(Object error, [StackTrace? stackTrace]) {
    if (_pendingResponses.isEmpty) {
      return;
    }
    final pendingResponses = _pendingResponses.values.toList(growable: false);
    _pendingResponses.clear();
    for (final pendingResponse in pendingResponses) {
      if (pendingResponse.isCompleted) {
        continue;
      }
      pendingResponse.completeError(error, stackTrace);
    }
  }

  bool _looksLikeFramedMessagePrefix() {
    final prefixLength = _stdoutBuffer.length < 32 ? _stdoutBuffer.length : 32;
    final prefix = ascii
        .decode(_stdoutBuffer.sublist(0, prefixLength), allowInvalid: true)
        .trimLeft()
        .toLowerCase();
    return prefix.isNotEmpty &&
        ('content-length'.startsWith(prefix) ||
            prefix.startsWith('content-length'));
  }

  int? _parseContentLength(String headers) {
    final normalized = headers.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final line in normalized.split('\n')) {
      final separatorIndex = line.indexOf(':');
      if (separatorIndex == -1) {
        continue;
      }
      final name = line.substring(0, separatorIndex).trim().toLowerCase();
      if (name != 'content-length') {
        continue;
      }
      return int.tryParse(line.substring(separatorIndex + 1).trim());
    }
    return null;
  }

  int _findHeaderEnd(List<int> buffer) {
    for (var index = 0; index < buffer.length - 1; index++) {
      if (buffer[index] == 13 &&
          buffer[index + 1] == 10 &&
          index + 3 < buffer.length &&
          buffer[index + 2] == 13 &&
          buffer[index + 3] == 10) {
        return index;
      }
      if (buffer[index] == 10 && buffer[index + 1] == 10) {
        return index;
      }
    }
    return -1;
  }

  int _headerSeparatorLength(List<int> buffer, int headerEnd) {
    if (headerEnd + 3 < buffer.length &&
        buffer[headerEnd] == 13 &&
        buffer[headerEnd + 1] == 10 &&
        buffer[headerEnd + 2] == 13 &&
        buffer[headerEnd + 3] == 10) {
      return 4;
    }
    return 2;
  }

  Future<void> _write(Map<String, Object?> payload) async {
    _appendTrace(
      'stdin:write:${payload['method'] ?? 'unknown'}:${payload['id'] ?? ''}',
    );
    final body = utf8.encode(jsonEncode(payload));
    final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');
    _process.stdin.add(header);
    _process.stdin.add(body);
    await _process.stdin.flush();
  }

  Future<void> close() async {
    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
    await _process.stdin.close();
    try {
      await _process.exitCode.timeout(
        DefaultMcpToolDiscoveryService._stdioShutdownTimeout,
      );
    } on TimeoutException {
      _process.kill();
    }
    _failPendingResponses(
      McpToolDiscoveryException(_closedUnexpectedlyMessage()),
    );
  }
}

class _SseEvent {
  const _SseEvent({required this.name, required this.data});

  final String name;
  final String data;
}

Map<String, String> _mergeRequestHeaders({
  required Map<String, String> baseHeaders,
  Map<String, String> extraHeaders = const <String, String>{},
  Set<String> protectedHeaderNames = const <String>{},
}) {
  final merged = <String, String>{};
  for (final entry in extraHeaders.entries) {
    final name = entry.key.trim();
    final value = entry.value.trim();
    if (name.isEmpty || value.isEmpty) {
      continue;
    }
    if (protectedHeaderNames.contains(name.toLowerCase())) {
      continue;
    }
    _setHeaderIgnoreCase(merged, name, value);
  }
  for (final entry in baseHeaders.entries) {
    _setHeaderIgnoreCase(merged, entry.key, entry.value);
  }
  return merged;
}

Set<String> _sensitiveHeaderNames(Map<String, String> headers) {
  return headers.keys
      .map((item) => item.trim().toLowerCase())
      .where((item) => item.isNotEmpty)
      .toSet();
}

void _setHeaderIgnoreCase(
  Map<String, String> headers,
  String name,
  String value,
) {
  final normalizedName = name.toLowerCase();
  final existingKeys = headers.keys
      .where((item) => item.toLowerCase() == normalizedName)
      .toList(growable: false);
  for (final existingKey in existingKeys) {
    headers.remove(existingKey);
  }
  headers[name] = value;
}

/// 把 MCP 服务发现 / 健康检查阶段的底层异常翻译成「现象 / 原因 / 建议」
/// 三段式中英双语文案。HTTP / SSE 传输借用
/// [AiTransportDiagnosticMessages]；stdio 传输有自己的 ProcessException
/// 措辞 (强调命令名 / PATH / 可执行权限 / 依赖缺失)。
String _friendlyMcpDiscoveryError(McpServer server, Object error) {
  final label = 'MCP · ${server.name}';
  if (error is HandshakeException) {
    return AiTransportDiagnosticMessages.handshake(error, contextLabel: label);
  }
  if (error is TlsException) {
    return AiTransportDiagnosticMessages.tls(error, contextLabel: label);
  }
  if (error is SocketException) {
    return AiTransportDiagnosticMessages.socket(error, contextLabel: label);
  }
  if (error is http.ClientException) {
    return AiTransportDiagnosticMessages.httpClient(error, contextLabel: label);
  }
  if (error is ProcessException) {
    return AiTransportDiagnosticMessages.format(
      title: 'MCP stdio launch failed · MCP 进程启动失败 [${server.name}]',
      reason:
          '尝试以子进程方式启动 MCP 服务时被操作系统拒绝：\n'
          '  · 命令: ${error.executable}${error.arguments.isEmpty ? '' : ' ${error.arguments.join(' ')}'}\n'
          '  · 退出 / errno: ${error.errorCode}\n'
          '常见诱因：\n'
          '  · 命令拼写错误 / 不在 PATH 上 (例如未安装 npx / node / uvx)\n'
          '  · 可执行文件缺少执行权限 (chmod +x)\n'
          '  · 依赖未安装 (例如 npm 包未 install / Python venv 未激活)\n'
          '  · 沙盒 / SIP / Gatekeeper 拒绝该二进制运行',
      try_:
          '· 在终端单独运行该命令复现报错\n'
          '· 检查 PATH 与可执行权限\n'
          '· 重新安装该 MCP 工具的依赖\n'
          '· 查看系统 console 是否有 Gatekeeper 拦截记录',
      raw: error.message.isEmpty ? null : error.message,
    );
  }
  return '$error';
}

/// MCP 阶段超时单独成函，标题带上 server.name 帮助用户在多服务面板
/// 里快速定位。
String _friendlyTimeoutMessage(
  McpServer server, {
  required String stage,
  required Duration limit,
}) {
  final label = 'MCP · ${server.name}';
  final stageLabel = switch (stage) {
    'discover' => 'tool discovery / 工具扫描',
    'health' => 'health check / 健康检查',
    _ => stage,
  };
  return AiTransportDiagnosticMessages.format(
    title: 'MCP timed out · MCP 超时 [${server.name}]',
    reason:
        '$stageLabel 在 ${limit.inSeconds} 秒内未完成。常见诱因：\n'
        '  · stdio 服务进程启动慢 (npx / uvx 首次 cold start 拉镜像 / 依赖)\n'
        '  · HTTP / SSE 服务被网络层 (代理 / 防火墙) 拦在中途\n'
        '  · 服务自身内部死锁或在等待外部 API 响应\n'
        '  · 该机器 CPU / IO 极度繁忙',
    try_:
        '· 等几秒后再试 (尤其 npx / uvx 首启会下载依赖)\n'
        '· 在终端独立运行 server.command 验证启动耗时\n'
        '· 提高 MCP 扫描超时阈值或拆分配置\n'
        '· 检查代理 / 防火墙是否拦截了出站 / 上游连接',
    raw: label,
  );
}

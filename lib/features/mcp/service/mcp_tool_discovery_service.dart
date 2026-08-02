import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/net/http_redirect_utils.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/net/http_status_utils.dart';
import '../../../shared/util/argument_guards.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_delete.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/timer_safety.dart';
import '../../ai/index.dart';
import '../model/mcp_http_headers.dart';
import '../model/mcp_server.dart';
import '../model/mcp_server_health.dart';
import '../model/mcp_tool.dart';
import 'mcp_node_package_resolver.dart';
import 'mcp_stdio_cache.dart';
import 'mcp_stdio_io_utils.dart';
import 'mcp_stdio_process_manager.dart';
import 'mcp_tool_discovery_exception.dart';

export 'mcp_stdio_cache.dart' show mcpStdioIsolatedCacheRoot;
export 'mcp_tool_discovery_exception.dart'
    show
        McpToolDiscoveryException,
        isExpectedMcpToolDiscoveryLifecycleError,
        kMcpStdioSessionClosingMessage;

final RegExp _stdioLineBreakPattern = RegExp(r'[\r\n]');
final RegExp _stdioLineBreaksPattern = RegExp(r'[\r\n]+');

// 国内最稳的 npm / PyPI 镜像源。集中定义，避免注入逻辑与多语言提示文案
// 各处硬编码不一致。
const String _kNpmMirrorRegistry = mcpNpmMirrorRegistry;
const int _mcpHttpMaxResponseBytes = 16 * kBytesPerMiB;
const int _mcpHttpMaxErrorBytes = 64 * kBytesPerKiB;
const int _mcpServerResponseDisplayMaxCharacters = 64 * kBytesPerKiB;
const int _mcpLegacySseMaxLineBytes = 4 * kBytesPerMiB;
const int _mcpLegacySseMaxEventBytes = 4 * kBytesPerMiB;
const Duration _mcpHttpDiscardTimeout = Duration(seconds: 3);
const Duration _mcpStreamCleanupTimeout = Duration(milliseconds: 500);
const Duration _mcpSessionCloseTimeout = Duration(seconds: 2);
const String _httpClientAlreadyClosedMessage =
    'HTTP request failed. Client is already closed.';
const String _httpConnectionClosedBeforeHeadersMessage =
    'Connection closed before full header was received';
const Duration _mcpStdioFileOperationTimeout = mcpStdioFileOperationTimeout;
const int _mcpStdioPathProbeLimit = 256;
const Map<String, String> _mcpFreshRequestHeaders = <String, String>{
  'cache-control': 'no-cache, no-store, max-age=0',
  'pragma': 'no-cache',
};
const BoundedDeletePolicy _mcpCacheDeletePolicy = BoundedDeletePolicy(
  maxEntries: 500000,
  maxDepth: 256,
  directoryIdleTimeout: Duration(seconds: 5),
  operationTimeout: Duration(seconds: 30),
  totalTimeout: Duration(minutes: 10),
);

Future<String> _readMcpHttpResponseBody(
  http.StreamedResponse response, {
  required Duration timeout,
  int maxBytes = _mcpHttpMaxResponseBytes,
  bool allowMalformed = false,
}) {
  return readBoundedByteStreamText(
    response.stream,
    maxBytes: maxBytes,
    idleTimeout: timeout,
    totalTimeout: timeout,
    allowMalformed: allowMalformed,
  );
}

Future<String> _readMcpHttpErrorBodyBestEffort(
  http.StreamedResponse response, {
  required Duration timeout,
}) async {
  try {
    return await _readMcpHttpResponseBody(
      response,
      timeout: timeout,
      maxBytes: _mcpHttpMaxErrorBytes,
      allowMalformed: true,
    );
  } catch (error, stack) {
    silentLog('mcp_tool_discovery_service', '读取有界 HTTP 错误响应', error, stack);
    return '';
  }
}

Future<void> _drainMcpHttpResponse(
  http.StreamedResponse response, {
  required Duration timeout,
}) {
  final totalTimeout = timeout < _mcpHttpDiscardTimeout
      ? timeout
      : _mcpHttpDiscardTimeout;
  return drainByteStreamWithTimeout(
    response.stream,
    idleTimeout: totalTimeout,
    totalTimeout: totalTimeout,
  );
}

bool _isExpectedStreamableSessionCloseError(Object error) {
  if (error is TimeoutException || error is http.RequestAbortedException) {
    return true;
  }
  if (error is! http.ClientException) return false;
  final message = error.message.trim();
  return message == _httpClientAlreadyClosedMessage ||
      message.startsWith(_httpConnectionClosedBeforeHeadersMessage);
}

abstract class McpToolDiscoveryService {
  Future<McpToolCatalog> discoverTools(McpServer server);
  Future<McpServerHealth> checkHealth(McpServer server);
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
    Map<String, String>? customHeaders,
    Future<void>? cancelSignal,
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

class _McpToolCallGuard {
  _McpToolCallGuard({required Duration timeout, this.cancelSignal})
    : _timeout = timeout,
      _stopwatch = Stopwatch()..start() {
    cancelSignal?.then(
      (_) => _cancelled = true,
      onError: (Object _, StackTrace stackTrace) => _cancelled = true,
    );
  }

  final Duration _timeout;
  final Stopwatch _stopwatch;
  final Future<void>? cancelSignal;
  bool _cancelled = false;

  Duration get remaining {
    throwIfExpired();
    final value = _timeout - _stopwatch.elapsed;
    return value > Duration.zero ? value : const Duration(microseconds: 1);
  }

  void throwIfExpired() {
    if (_cancelled || _stopwatch.elapsed >= _timeout) {
      throw TimeoutException('MCP 工具调用已超过时限。');
    }
  }
}

class DefaultMcpToolDiscoveryService implements McpToolDiscoveryService {
  DefaultMcpToolDiscoveryService({http.Client? client})
    : _client = client ?? SystemProxyResolver.instance.createHttpClient(),
      _ownsClient = client == null;

  static const Duration _scanTimeout = Duration(seconds: 8);
  // stdio 首次冷启动通常要跑 npx / uvx 拉远端包；chrome-devtools-mcp 这类
  // 还要顺带装 puppeteer + Chrome Beta（≈50MB 中间产品，最终 250MB），
  // 家宽 3~5 分钟很常见。三层超时应遵守「内小外大」：
  //   外层 _stdioScanTimeout / _stdioHealthCheckTimeout ＝ 6 分钟
  //   中层 _stdioInitializeTimeout              ＝ 5 分钟【覆盖 sendRequest 默认 6s】
  //   内层 _requestTimeout (sendRequest 默认)  ＝ 6 秒
  // 另外 _initializeStdioSession 中 initialize RPC 必须显式传 _stdioInitializeTimeout
  // 覆盖默认 6 秒 —— 否则外层再大也在 6 秒后就被内层 timeout 杚死。
  static const Duration _stdioScanTimeout = Duration(minutes: 6);
  static const Duration _healthCheckTimeout = Duration(seconds: 6);
  static const Duration _stdioHealthCheckTimeout = Duration(minutes: 6);
  static const Duration _stdioInitializeTimeout = Duration(minutes: 5);
  static const Duration _stdioProcessStartTimeout = Duration(seconds: 10);
  static const Duration _requestTimeout = Duration(seconds: 6);
  static const Duration _toolCallTimeout = Duration(seconds: 30);
  static const Duration _legacyEndpointTimeout = Duration(seconds: 4);
  static const Duration _stdioShutdownTimeout = Duration(milliseconds: 400);
  static const int _maxConcurrentOperations = 8;
  static const int _maxQueuedOperations = 64;
  static const Duration _operationQueueTimeout = Duration(seconds: 30);
  static const int _maxStdoutMessagesPerDrain = 256;
  static const int _maxStdioStdoutBufferBytes = 4 * kBytesPerMiB;
  static const int _maxRedirects = 4;
  static const int _maxToolPages = 8;
  static const String _streamableHttpProtocolVersion = '2025-11-25';
  static const String _legacySseProtocolVersion = '2024-11-05';
  static final RegExp _outputDescriptionLineSeparatorPattern = RegExp(
    r'[\r\n]+',
  );
  static final RegExp _outputDescriptionSentencePattern = RegExp(
    r'[^。！？.!?]*(返回|输出|结果|returns?|output|response|result)[^。！？.!?]*[。！？.!?]?',
    caseSensitive: false,
  );

  final http.Client _client;
  final bool _ownsClient;
  final OpenHandAsyncSemaphore _operationSlots = OpenHandAsyncSemaphore(
    _maxConcurrentOperations,
    maxWaiters: _maxQueuedOperations,
  );
  final Set<Completer<void>> _activeOperationAborts = <Completer<void>>{};
  int _nextRequestId = 0;
  bool _isDisposed = false;

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) {
    return _runOperation((operationCancelSignal) async {
      final scannedAt = DateTime.now().toUtc();
      final scanTimeout = server.type == McpServerType.stdio
          ? _stdioScanTimeout
          : _scanTimeout;
      try {
        final discovered = await switch (server.type) {
          McpServerType.streamableHttp => _discoverOverStreamableHttp(
            server,
            cancelSignal: operationCancelSignal,
          ),
          McpServerType.sse => _discoverOverLegacySseWithFallback(
            server,
            cancelSignal: operationCancelSignal,
          ),
          McpServerType.stdio => _discoverOverStdio(server),
        }.timeout(scanTimeout);
        return McpToolCatalog(
          status: McpToolCatalogStatus.ready,
          tools: discovered.tools,
          isComplete: discovered.isComplete,
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
            limit: scanTimeout,
          ),
          lastScannedAt: scannedAt,
        );
      } on McpToolDiscoveryException catch (error) {
        if (error.isExpectedLifecycleCancellation) {
          return const McpToolCatalog();
        }
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
    });
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) {
    return _runOperation((operationCancelSignal) async {
      final checkedAt = DateTime.now().toUtc();
      final healthTimeout = server.type == McpServerType.stdio
          ? _stdioHealthCheckTimeout
          : _healthCheckTimeout;
      try {
        await switch (server.type) {
          McpServerType.streamableHttp => _checkStreamableHttpHealth(
            server,
            cancelSignal: operationCancelSignal,
          ),
          McpServerType.sse => _checkLegacySseHealthWithFallback(
            server,
            cancelSignal: operationCancelSignal,
          ),
          McpServerType.stdio => _checkStdioHealth(server),
        }.timeout(healthTimeout);
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
            limit: healthTimeout,
          ),
          lastCheckedAt: checkedAt,
        );
      } on McpToolDiscoveryException catch (error) {
        if (error.isExpectedLifecycleCancellation) {
          return const McpServerHealth();
        }
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
    });
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
    Map<String, String>? customHeaders,
    Future<void>? cancelSignal,
  }) {
    return _runOperation((operationCancelSignal) async {
      final guard = _McpToolCallGuard(
        timeout: _toolCallTimeout,
        cancelSignal: operationCancelSignal,
      );
      late final Map<String, Object?> result;
      try {
        result = await switch (server.type) {
          McpServerType.streamableHttp => _callToolOverStreamableHttp(
            server,
            toolName,
            arguments,
            guard: guard,
            customHeaders: customHeaders,
          ),
          McpServerType.sse => _callToolOverLegacySseWithFallback(
            server,
            toolName,
            arguments,
            guard: guard,
            customHeaders: customHeaders,
          ),
          McpServerType.stdio => _callToolOverStdio(
            server,
            toolName,
            arguments,
            guard: guard,
            toolCallId: toolCallId,
          ),
        }.timeout(_toolCallTimeout);
      } on TimeoutException {
        throw const McpToolDiscoveryException('MCP 工具调用超时，服务未及时响应。');
      }
      return McpToolCallResult(
        outputText: _renderToolCallResult(result),
        isError: result['isError'] == true,
        rawResult: result,
      );
    }, cancelSignal: cancelSignal);
  }

  Future<_DiscoveredTools> _discoverOverStreamableHttp(
    McpServer server, {
    Future<void>? cancelSignal,
  }) async {
    final session = await _initializeStreamableHttpSession(
      server,
      cancelSignal: cancelSignal,
    );
    try {
      return await _listTools(
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
          cancelSignal: cancelSignal,
        ).then((response) => response.message),
        serverInstructions: session.instructions,
      );
    } finally {
      await _closeStreamableHttpSession(
        server,
        session,
        cancelSignal: cancelSignal,
      );
    }
  }

  Future<_DiscoveredTools> _discoverOverLegacySse(
    McpServer server, {
    Future<void>? cancelSignal,
  }) async {
    final session = await _initializeLegacySseSession(
      server,
      cancelSignal: cancelSignal,
    );
    try {
      return await _listTools(
        (cursor) => session.sendRequest(
          _jsonRpcRequest(
            id: _nextId(),
            method: 'tools/list',
            params: cursor == null ? null : <String, Object?>{'cursor': cursor},
          ),
          cancelSignal: cancelSignal,
        ),
        serverInstructions: session.instructions,
      );
    } finally {
      await session.close();
    }
  }

  Future<_DiscoveredTools> _discoverOverLegacySseWithFallback(
    McpServer server, {
    Future<void>? cancelSignal,
  }) {
    return _runLegacySseWithStreamableFallback(
      primaryOperation: () =>
          _discoverOverLegacySse(server, cancelSignal: cancelSignal),
      fallbackOperation: () =>
          _discoverOverStreamableHttp(server, cancelSignal: cancelSignal),
    );
  }

  Future<_DiscoveredTools> _discoverOverStdio(McpServer server) async {
    // 通过 process manager 的长驻进程发送 tools/list。
    // Playwright 等 stdio MCP 服务在 macOS GUI 应用环境中，discovery service
    // 启动的短命进程会在 tools/list 阶段异常退出（原因未明，可能与 GUI 应用
    // 的进程调度或 pipe buffer 行为有关）。通过复用 process manager 的长驻
    // 进程，既避免了此问题，又省去了冷启动开销。
    // 如果 process manager 中没有该服务的进程，先启动一个并等待握手完成。
    final processInfo = McpStdioProcessManager.instance.infoFor(server.name);
    if (processInfo.isStopped) {
      await McpStdioProcessManager.instance.startServer(server);
    }

    final managedSession = await McpStdioProcessManager.instance
        .borrowSessionForDiscovery(server.name);
    if (managedSession != null) {
      try {
        return await _listTools(
          (cursor) => managedSession.sendRequest(
            _jsonRpcRequest(
              id: _nextId(),
              method: 'tools/list',
              params: cursor == null
                  ? null
                  : <String, Object?>{'cursor': cursor},
            ),
          ),
          serverInstructions: managedSession.instructions,
        );
      } finally {
        McpStdioProcessManager.instance.returnSession(server.name);
      }
    }

    // 兜底：borrowSession 失败（进程启动失败/握手超时），回退到独立进程。
    final session = await _initializeStdioSession(server);
    try {
      return await _listTools(
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
    Map<String, Object?> arguments, {
    required _McpToolCallGuard guard,
    Map<String, String>? customHeaders,
  }) async {
    guard.throwIfExpired();
    final session = await _initializeStreamableHttpSession(
      server,
      customHeaders: customHeaders,
      cancelSignal: guard.cancelSignal,
    );
    try {
      guard.throwIfExpired();
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
        requestTimeout: guard.remaining,
        expectResponse: true,
        customHeaders: customHeaders,
        cancelSignal: guard.cancelSignal,
      );
      return _extractResult(response.message);
    } finally {
      await _closeStreamableHttpSession(
        server,
        session,
        customHeaders: customHeaders,
        cancelSignal: guard.cancelSignal,
      );
    }
  }

  Future<Map<String, Object?>> _callToolOverLegacySse(
    McpServer server,
    String toolName,
    Map<String, Object?> arguments, {
    required _McpToolCallGuard guard,
    Map<String, String>? customHeaders,
  }) async {
    guard.throwIfExpired();
    final session = await _initializeLegacySseSession(
      server,
      customHeaders: customHeaders,
      cancelSignal: guard.cancelSignal,
    );
    try {
      guard.throwIfExpired();
      return _extractResult(
        await session.sendRequest(
          _jsonRpcRequest(
            id: _nextId(),
            method: 'tools/call',
            params: <String, Object?>{'name': toolName, 'arguments': arguments},
          ),
          timeout: guard.remaining,
          cancelSignal: guard.cancelSignal,
        ),
      );
    } finally {
      await session.close();
    }
  }

  Future<Map<String, Object?>> _callToolOverLegacySseWithFallback(
    McpServer server,
    String toolName,
    Map<String, Object?> arguments, {
    required _McpToolCallGuard guard,
    Map<String, String>? customHeaders,
  }) {
    return _runLegacySseWithStreamableFallback(
      primaryOperation: () => _callToolOverLegacySse(
        server,
        toolName,
        arguments,
        guard: guard,
        customHeaders: customHeaders,
      ),
      fallbackOperation: () => _callToolOverStreamableHttp(
        server,
        toolName,
        arguments,
        guard: guard,
        customHeaders: customHeaders,
      ),
    );
  }

  Future<Map<String, Object?>> _callToolOverStdio(
    McpServer server,
    String toolName,
    Map<String, Object?> arguments, {
    required _McpToolCallGuard guard,
    String? toolCallId,
  }) async {
    guard.throwIfExpired();
    // 优先复用 process manager 中已运行的进程（确保先启动）
    final processInfo = McpStdioProcessManager.instance.infoFor(server.name);
    if (processInfo.isStopped) {
      await McpStdioProcessManager.instance.startServer(server);
      guard.throwIfExpired();
    }
    final managedSession = await McpStdioProcessManager.instance
        .borrowSessionForDiscovery(server.name);
    if (managedSession != null) {
      final requestId = _nextId();
      if (toolCallId != null && toolCallId.isNotEmpty) {
        final pid = McpStdioProcessManager.instance.infoFor(server.name).pid;
        if (pid != null) {
          AiToolExecutionRegistry.instance.attachPid(toolCallId, pid);
        }
        AiToolExecutionRegistry.instance.attachKiller(
          toolCallId,
          () => managedSession.cancelRequest(requestId),
        );
      }
      try {
        guard.throwIfExpired();
        return _extractResult(
          await managedSession.sendRequest(
            _jsonRpcRequest(
              id: requestId,
              method: 'tools/call',
              params: <String, Object?>{
                'name': toolName,
                'arguments': arguments,
              },
            ),
            timeout: guard.remaining,
          ),
        );
      } finally {
        McpStdioProcessManager.instance.returnSession(server.name);
      }
    }

    // 兜底：启动独立进程
    final session = await _initializeStdioSession(server);
    final registeredToolCallId = toolCallId;
    if (registeredToolCallId != null && registeredToolCallId.isNotEmpty) {
      AiToolExecutionRegistry.instance.attachPid(
        registeredToolCallId,
        session.process.pid,
      );
      AiToolExecutionRegistry.instance.attachKiller(
        registeredToolCallId,
        () async => session.close(),
      );
    }
    try {
      guard.throwIfExpired();
      return _extractResult(
        await session.sendRequest(
          _jsonRpcRequest(
            id: _nextId(),
            method: 'tools/call',
            params: <String, Object?>{'name': toolName, 'arguments': arguments},
          ),
          timeout: guard.remaining,
        ),
      );
    } finally {
      await session.close();
    }
  }

  Future<void> _checkStreamableHttpHealth(
    McpServer server, {
    Future<void>? cancelSignal,
  }) async {
    final session = await _initializeStreamableHttpSession(
      server,
      cancelSignal: cancelSignal,
    );
    await _closeStreamableHttpSession(
      server,
      session,
      cancelSignal: cancelSignal,
    );
  }

  Future<void> _checkLegacySseHealth(
    McpServer server, {
    Future<void>? cancelSignal,
  }) async {
    final session = await _initializeLegacySseSession(
      server,
      cancelSignal: cancelSignal,
    );
    await session.close();
  }

  Future<void> _checkLegacySseHealthWithFallback(
    McpServer server, {
    Future<void>? cancelSignal,
  }) {
    return _runLegacySseWithStreamableFallback(
      primaryOperation: () =>
          _checkLegacySseHealth(server, cancelSignal: cancelSignal),
      fallbackOperation: () =>
          _checkStreamableHttpHealth(server, cancelSignal: cancelSignal),
    );
  }

  Future<void> _checkStdioHealth(McpServer server) async {
    // 快速路径：如果进程管理器中已有该服务的运行中进程，直接视为健康。
    // 避免每次健康检查都重新启动一个完整的 MCP 进程（冷启动可能需要数分钟）。
    final processInfo = McpStdioProcessManager.instance.infoFor(server.name);
    if (processInfo.isRunning && processInfo.pid != null) {
      // 验证进程是否仍然存活（发送 signal 0 不会杀死进程，只检查是否存在）
      try {
        final checkResult = await runTrackedProcessOrFailed(
          'kill',
          ['-0', '${processInfo.pid}'],
          timeout: const Duration(seconds: 2),
          tag: 'mcp_tool_discovery.kill0',
        );
        if (checkResult.exitCode == 0) return; // 进程存活，健康
      } catch (error, stack) {
        silentLog(
          'mcp_tool_discovery_service',
          '检查运行中进程 ${processInfo.pid}',
          error,
          stack,
        );
      }
    }

    // 常规路径：启动新进程进行完整 MCP 握手验证
    final session = await _initializeStdioSession(server);
    await session.close();
  }

  Future<_InitializedStreamableHttpSession> _initializeStreamableHttpSession(
    McpServer server, {
    Map<String, String>? customHeaders,
    Future<void>? cancelSignal,
  }) async {
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
      customHeaders: customHeaders,
      cancelSignal: cancelSignal,
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
      customHeaders: customHeaders,
      cancelSignal: cancelSignal,
    );
    return _InitializedStreamableHttpSession(
      uri: resolvedUri,
      protocolVersion: negotiatedProtocolVersion,
      sessionId: initializeResponse.sessionId,
      instructions: instructions,
    );
  }

  Future<void> _closeStreamableHttpSession(
    McpServer server,
    _InitializedStreamableHttpSession session, {
    Map<String, String>? customHeaders,
    Future<void>? cancelSignal,
  }) async {
    final sessionId = nullIfBlank(session.sessionId);
    if (sessionId == null || _isDisposed) return;
    final headers = _mergeRequestHeaders(
      baseHeaders: const <String, String>{
        'accept': 'application/json',
        ..._mcpFreshRequestHeaders,
      },
      extraHeaders: customHeaders ?? server.headers,
      protectedHeaderNames: const <String>{
        'accept',
        'cache-control',
        'pragma',
        'mcp-protocol-version',
        'mcp-session-id',
      },
    );
    headers['mcp-protocol-version'] = session.protocolVersion;
    headers['mcp-session-id'] = sessionId;
    try {
      final response = await _sendRequestWithRedirects(
        client: _client,
        method: 'DELETE',
        uri: session.uri,
        headers: headers,
        requestTimeout: _mcpSessionCloseTimeout,
        maxRedirects: _maxRedirects,
        additionalSensitiveHeaderNames: _sensitiveHeaderNames(
          customHeaders ?? server.headers,
        ),
        cancelSignal: cancelSignal,
      );
      await _drainMcpHttpResponse(response, timeout: _mcpSessionCloseTimeout);
    } catch (error, stack) {
      if (_isExpectedStreamableSessionCloseError(error)) return;
      silentLog(
        'mcp_tool_discovery_service',
        '关闭 Streamable HTTP 会话',
        error,
        stack,
      );
    }
  }

  Future<_LegacySseSession> _initializeLegacySseSession(
    McpServer server, {
    Map<String, String>? customHeaders,
    Future<void>? cancelSignal,
  }) async {
    final session = await _LegacySseSession.connect(
      client: _client,
      sseUri: _parseServerUri(server.url),
      headers: customHeaders ?? server.headers,
      sensitiveHeaderNames: _sensitiveHeaderNames(
        customHeaders ?? server.headers,
      ),
      endpointTimeout: _legacyEndpointTimeout,
      requestTimeout: _requestTimeout,
      cancelSignal: cancelSignal,
    );
    try {
      final initializeResult = _extractResult(
        await session.sendRequest(
          _jsonRpcInitializeRequest(
            id: _nextId(),
            protocolVersion: _legacySseProtocolVersion,
          ),
          cancelSignal: cancelSignal,
        ),
      );
      session.instructions = _readText(initializeResult['instructions']);
      await session.sendNotification(
        _jsonRpcNotification('notifications/initialized'),
        cancelSignal: cancelSignal,
      );
      return session;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  Future<_StdioSession> _initializeStdioSession(McpServer server) async {
    final resolved = await _resolveStdioLaunch(server);
    final session = _StdioSession(
      process: await startTrackedProcessBounded(
        resolved.executable,
        resolved.args,
        timeout: _stdioProcessStartTimeout,
        tag: 'mcp_tool_discovery_service',
        startInNewProcessGroup: true,
        environment: <String, String>{
          ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
          ...resolved.environment,
          ...server.environment,
        },
        // Windows 的 .cmd/.bat/.ps1 启动器只能经 Shell 解析；macOS/Linux
        // 已解析为绝对路径，直接执行可保持参数引用语义准确。
        runInShell: Platform.isWindows,
      ),
      requestTimeout: _requestTimeout,
      onStderrLine: (line) {
        // 把 npm/uvx 首启时的下载进度行实时透出给 UI 「正在 bootstrap」chip。
        // 行已经在 _StdioSession 里 trim 过，这里做长度截断防爆 Tooltip。
        final clean = clipTextWithEllipsis(line, 200);
        mcpStdioBootstrapStatus.update(server.name, clean);
      },
    );
    try {
      final initializeResult = _extractResult(
        await session.sendRequest(
          _jsonRpcInitializeRequest(
            id: _nextId(),
            protocolVersion: _streamableHttpProtocolVersion,
          ),
          // initialize 是 stdio MCP 冷启动唯一会被 npx/uvx 拉包 / Chrome Beta
          // 下载阻塞的 RPC。默认 _requestTimeout = 6s 完全不够 ——
          // 以前表面上看到的「健康检查 4 分钟超时」其实是少补了这个 timeout
          // 参数后在 6s 就仆了、但被外层 4min envelope 接中后复述成了 4min。
          // 这里明确赋 5min（外层 6min envelope 就能火上火块包住）。
          timeout: _stdioInitializeTimeout,
        ),
      );
      session.instructions = _readText(initializeResult['instructions']);
      await session.sendNotification(
        _jsonRpcNotification('notifications/initialized'),
      );
      // initialize 已成功，bootstrap 阶段结束，清掉进度行避免 UI 残留。
      mcpStdioBootstrapStatus.clear(server.name);
      return session;
    } catch (_) {
      mcpStdioBootstrapStatus.clear(server.name);
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
    Map<String, Object?>? warningResponse;
    Map<String, Object?>? lastEnvelope;

    for (var pageIndex = 0; pageIndex < _maxToolPages; pageIndex++) {
      final envelope = await sendRequest(cursor.isEmpty ? null : cursor);
      lastEnvelope = envelope;
      final result = _extractResult(envelope);
      final rawTools = result['tools'];
      if (rawTools is! List) {
        throw McpToolDiscoveryException(
          '工具扫描失败：服务返回了无效的工具列表。'
          '${_mcpServerResponseDetail(envelope)}',
        );
      }
      final invalidBefore = invalidTools;
      final duplicateBefore = duplicateTools;
      final metadataBefore = metadataWarnings;
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
      if (invalidTools != invalidBefore ||
          duplicateTools != duplicateBefore ||
          metadataWarnings != metadataBefore) {
        warningResponse = envelope;
      }
      final nextCursor = _readText(result['nextCursor']);
      if (nextCursor.isEmpty) {
        cursor = '';
        break;
      }
      cursor = nextCursor;
    }

    if (cursor.isNotEmpty) {
      warnings.add('工具扫描达到 $_maxToolPages 页后停止，工具列表可能不完整。');
      warningResponse = lastEnvelope;
    }
    if (invalidTools > 0) {
      warnings.add('已忽略 $invalidTools 个无效工具条目。');
    }
    if (duplicateTools > 0) {
      warnings.add('已忽略 $duplicateTools 个重复工具条目。');
    }
    if (metadataWarnings > 0) {
      warnings.add('$metadataWarnings 个工具条目的元数据不完整。');
    }

    return _DiscoveredTools(
      tools: tools,
      isComplete: cursor.isEmpty && invalidTools == 0,
      warningMessage: warnings.isEmpty
          ? null
          : '${warnings.join(' ')}${_mcpServerResponseDetail(warningResponse)}',
      serverInstructions: serverInstructions,
    );
  }

  McpTool? _parseTool(Object? rawTool) {
    final rawMap = optionalStringKeyedMapFromValue(rawTool);
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
    final inputSchema = optionalStringKeyedMapFromValue(rawInputSchema);
    final outputSchema = optionalStringKeyedMapFromValue(rawOutputSchema);
    final annotations =
        optionalStringKeyedMapFromValue(rawMap['annotations']) ??
        const <String, Object?>{};
    final execution =
        optionalStringKeyedMapFromValue(rawMap['execution']) ??
        const <String, Object?>{};
    final metadataWarnings = <String>[];

    final resolvedInputSchema =
        inputSchema ?? const <String, Object?>{'type': 'object'};
    if (rawInputSchema == null) {
      metadataWarnings.add('缺少输入架构。');
    } else if (inputSchema == null) {
      metadataWarnings.add('输入架构不是结构化对象，已改为显示原始元数据。');
    }
    if (rawOutputSchema != null && outputSchema == null) {
      metadataWarnings.add('输出架构不是结构化对象，已改为显示原始元数据。');
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
    Map<String, String>? customHeaders,
    Future<void>? cancelSignal,
  }) async {
    final headers = _mergeRequestHeaders(
      baseHeaders: const <String, String>{
        kContentTypeHeaderName: 'application/json',
        'accept': 'application/json, text/event-stream',
        ..._mcpFreshRequestHeaders,
      },
      extraHeaders: customHeaders ?? server.headers,
      protectedHeaderNames: const <String>{
        kContentTypeHeaderName,
        'accept',
        'mcp-protocol-version',
        'mcp-session-id',
        'cache-control',
        'pragma',
      },
    );
    final normalizedProtocolVersion = nullIfBlank(protocolVersion);
    if (normalizedProtocolVersion != null) {
      headers['mcp-protocol-version'] = normalizedProtocolVersion;
    }
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId != null) {
      headers['mcp-session-id'] = normalizedSessionId;
    }

    final effectiveRequestTimeout = requestTimeout ?? _requestTimeout;
    final response = await _sendRequestWithRedirects(
      client: _client,
      method: 'POST',
      uri: uri,
      headers: headers,
      body: jsonEncode(payload),
      requestTimeout: effectiveRequestTimeout,
      maxRedirects: _maxRedirects,
      additionalSensitiveHeaderNames: _sensitiveHeaderNames(
        customHeaders ?? server.headers,
      ),
      cancelSignal: cancelSignal,
    );
    final responseUri = response.request?.url ?? uri;
    final responseSessionId = readResponseHeader(
      response.headers,
      'mcp-session-id',
    );
    if (isHttpFailureStatus(response.statusCode)) {
      final responseBody = await _readMcpHttpErrorBodyBestEffort(
        response,
        timeout: effectiveRequestTimeout,
      );
      throw McpToolDiscoveryException(
        '工具扫描请求失败，HTTP 状态码 ${response.statusCode}'
        '${_mcpServerResponseDetail(responseBody)}',
      );
    }
    if (!expectResponse) {
      await _drainMcpHttpResponse(response, timeout: effectiveRequestTimeout);
      return _JsonRpcHttpResponse(
        sessionId: responseSessionId,
        uri: responseUri,
      );
    }

    final contentType = readResponseHeader(
      response.headers,
      kContentTypeHeaderName,
    );
    final body = await _readMcpHttpResponseBody(
      response,
      timeout: effectiveRequestTimeout,
    );
    if (contentType.contains('text/event-stream')) {
      final message = _firstSseJsonRpcMessage(body, payload['id']);
      if (message == null) {
        throw McpToolDiscoveryException(
          '工具扫描失败：MCP 服务返回了无效的 JSON-RPC 响应。'
          '${_mcpServerResponseDetail(body)}',
        );
      }
      return _JsonRpcHttpResponse(
        message: message,
        sessionId: responseSessionId,
        uri: responseUri,
      );
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw McpToolDiscoveryException(
        '工具扫描失败：MCP 服务返回的内容不是有效 JSON。'
        '${_mcpServerResponseDetail(body)}',
      );
    }
    final message = _firstJsonRpcMessageForRequestId(decoded, payload['id']);
    if (message == null) {
      throw McpToolDiscoveryException(
        '工具扫描失败：MCP 服务返回了无效的 JSON-RPC 响应。'
        '${_mcpServerResponseDetail(body)}',
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
        message.contains('sse 端点') ||
        message.contains('message endpoint') ||
        message.contains('消息端点') ||
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
        message.contains('无效的 json-rpc') ||
        message.contains('did not return a response') ||
        message.contains('未返回响应');
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
      throw const McpToolDiscoveryException('工具扫描失败：MCP 服务未返回响应。');
    }
    final error = optionalStringKeyedMapFromValue(envelope['error']);
    if (error != null) {
      final message = _readText(error['message']);
      throw McpToolDiscoveryException(
        '${message.isEmpty ? '工具扫描失败：MCP 服务返回错误。' : message}'
        '${_mcpServerResponseDetail(envelope)}',
      );
    }
    final result = optionalStringKeyedMapFromValue(envelope['result']);
    if (result == null) {
      throw McpToolDiscoveryException(
        '工具扫描失败：MCP 服务返回了无效的结果载荷。'
        '${_mcpServerResponseDetail(envelope)}',
      );
    }
    return result;
  }

  Uri _parseServerUri(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme) {
      throw const McpToolDiscoveryException('工具扫描失败：MCP 服务地址无效。');
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
    return prettyPrintJson(result);
  }

  String _renderToolCallContentItem(Object? rawItem) {
    final item = optionalStringKeyedMapFromValue(rawItem);
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
        return prettyPrintJson(item);
    }
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
      final rawSchemaMap = stringKeyedMapFromValue(rawSchema);
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
      final container = optionalStringKeyedMapFromValue(rawMap[key]);
      if (container != null) {
        containers.add(container);
      }
    }
    return containers;
  }

  _ResolvedToolOutputMetadata _resolveOutputDescriptor(Object? descriptor) {
    final descriptorMap = optionalStringKeyedMapFromValue(descriptor);
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
    final schemaMap = optionalStringKeyedMapFromValue(schema);
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
    final matchedLines = splitTrimmedNonEmpty(
      normalized,
      separator: _outputDescriptionLineSeparatorPattern,
    ).where(_looksLikeOutputDescriptionLine).toList(growable: false);
    if (matchedLines.isNotEmpty) {
      return matchedLines.join('\n');
    }

    final sentenceMatch = _outputDescriptionSentencePattern.allMatches(
      normalized,
    );
    final sentences = stringListFromValue(
      sentenceMatch.map((match) => match.group(0)).toList(growable: false),
    );
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
    if (_isDisposed) return;
    _isDisposed = true;
    _operationSlots.cancelWaiters();
    for (final abort in _activeOperationAborts.toList(growable: false)) {
      if (!abort.isCompleted) abort.complete();
    }
    _activeOperationAborts.clear();
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<T> _runOperation<T>(
    Future<T> Function(Future<void> cancelSignal) operation, {
    Future<void>? cancelSignal,
  }) async {
    if (_isDisposed) throw StateError('MCP 工具发现服务已关闭。');
    final queueTimeoutSignal = Completer<void>();
    final queueTimer = Timer(
      _operationQueueTimeout,
      queueTimeoutSignal.complete,
    );
    late final bool acquired;
    try {
      acquired = await _operationSlots.acquireUnlessCancelled(
        combineCancelSignals(<Future<void>?>[
          cancelSignal,
          queueTimeoutSignal.future,
        ])!,
      );
    } on StateError {
      if (_isDisposed) throw StateError('MCP 工具发现服务已关闭。');
      throw const McpToolDiscoveryException('MCP 操作排队已满。');
    } finally {
      queueTimer.cancel();
    }
    if (!acquired) {
      if (_isDisposed) {
        throw StateError('MCP 工具发现服务已关闭。');
      }
      if (!await isCancelSignalCompleted(cancelSignal)) {
        throw TimeoutException('MCP 操作排队超时。', _operationQueueTimeout);
      }
      throw const McpToolDiscoveryException('MCP 操作已取消。');
    }
    if (_isDisposed) {
      _operationSlots.release();
      throw StateError('MCP 工具发现服务已关闭。');
    }
    final abort = Completer<void>();
    _activeOperationAborts.add(abort);
    final effectiveCancelSignal = combineCancelSignals(<Future<void>?>[
      cancelSignal,
      abort.future,
    ])!;
    try {
      return await operation(effectiveCancelSignal);
    } finally {
      if (!abort.isCompleted) abort.complete();
      _activeOperationAborts.remove(abort);
      _operationSlots.release();
    }
  }
}

Iterable<Map<String, Object?>> _jsonRpcMessagesFromDecoded(
  Object? value,
) sync* {
  final singleMessage = optionalStringKeyedMapFromValue(value);
  if (singleMessage != null) {
    yield singleMessage;
    return;
  }
  if (value is! List) {
    return;
  }
  for (final item in value) {
    final message = optionalStringKeyedMapFromValue(item);
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
  Future<void>? cancelSignal,
}) {
  return sendHttpRequestFollowingRedirects(
    client: client,
    method: method,
    uri: uri,
    headers: headers,
    body: body,
    timeout: requestTimeout,
    maxRedirects: maxRedirects,
    additionalSensitiveHeaderNames: <String>{
      'mcp-session-id',
      ...additionalSensitiveHeaderNames,
    },
    cancelSignal: cancelSignal,
    drainResponse: (response) =>
        _drainMcpHttpResponse(response, timeout: requestTimeout),
    onTooManyRedirects: (response) async {
      final responseBody = await _readMcpHttpErrorBodyBestEffort(
        response,
        timeout: requestTimeout,
      );
      throw McpToolDiscoveryException(
        '工具扫描请求重定向次数过多（${maxRedirects + 1} 次）'
        '${_mcpServerResponseDetail(responseBody)}',
      );
    },
  );
}

String _mcpServerResponseDetail(Object? response) {
  String raw;
  if (response is String) {
    raw = response.trim();
  } else if (response == null) {
    raw = '';
  } else {
    try {
      raw = const JsonEncoder.withIndent('  ').convert(response);
    } catch (_) {
      raw = '$response';
    }
  }
  final label = openHandAmbientText(
    zh: '服务端原始响应',
    zhHant: '服務端原始回應',
    en: 'Raw server response',
    fr: 'Réponse brute du serveur',
    de: 'Unverarbeitete Serverantwort',
    ja: 'サーバーの生レスポンス',
  );
  final empty = openHandAmbientText(
    zh: '（空响应）',
    zhHant: '（空回應）',
    en: '(empty response)',
    fr: '(réponse vide)',
    de: '(leere Antwort)',
    ja: '（空のレスポンス）',
  );
  final truncated = openHandAmbientText(
    zh: '…（响应过长，已截断）',
    zhHant: '…（回應過長，已截斷）',
    en: '… (response truncated)',
    fr: '… (réponse tronquée)',
    de: '… (Antwort gekürzt)',
    ja: '…（レスポンスを省略）',
  );
  final content = raw.isEmpty
      ? empty
      : clipText(
          raw,
          _mcpServerResponseDisplayMaxCharacters,
          suffix: '\n$truncated',
        );
  return '\n\n$label:\n$content';
}

class _DiscoveredTools {
  const _DiscoveredTools({
    required this.tools,
    required this.isComplete,
    this.warningMessage,
    this.serverInstructions = '',
  });

  final List<McpTool> tools;
  final bool isComplete;
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
    required StreamSubscription<_SseEvent> subscription,
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
  final StreamSubscription<_SseEvent> _subscription;
  final Duration _requestTimeout;
  String instructions = '';

  static Future<_LegacySseSession> connect({
    required http.Client client,
    required Uri sseUri,
    required Map<String, String> headers,
    required Set<String> sensitiveHeaderNames,
    required Duration endpointTimeout,
    required Duration requestTimeout,
    Future<void>? cancelSignal,
  }) async {
    final response = await _sendRequestWithRedirects(
      client: client,
      method: 'GET',
      uri: sseUri,
      headers: _mergeRequestHeaders(
        baseHeaders: const <String, String>{
          'accept': 'text/event-stream',
          ..._mcpFreshRequestHeaders,
        },
        extraHeaders: headers,
        protectedHeaderNames: const <String>{
          'accept',
          'cache-control',
          'pragma',
        },
      ),
      requestTimeout: requestTimeout,
      maxRedirects: DefaultMcpToolDiscoveryService._maxRedirects,
      additionalSensitiveHeaderNames: sensitiveHeaderNames,
      cancelSignal: cancelSignal,
    );
    final resolvedSseUri = response.request?.url ?? sseUri;
    if (isHttpFailureStatus(response.statusCode)) {
      final body = await _readMcpHttpErrorBodyBestEffort(
        response,
        timeout: requestTimeout,
      );
      throw McpToolDiscoveryException(
        '工具扫描无法连接 SSE 端点（HTTP ${response.statusCode}）'
        '${_mcpServerResponseDetail(body)}',
      );
    }
    final contentType = readResponseHeader(
      response.headers,
      kContentTypeHeaderName,
    );
    if (!contentType.toLowerCase().contains('text/event-stream')) {
      final body = await _readMcpHttpErrorBodyBestEffort(
        response,
        timeout: requestTimeout,
      );
      throw McpToolDiscoveryException(
        '工具扫描无法连接 SSE 端点：服务未返回事件流。'
        '${_mcpServerResponseDetail(body)}',
      );
    }

    final endpointCompleter = Completer<Uri>();
    final messages = StreamController<Map<String, Object?>>.broadcast(
      sync: true,
    );
    void handleEvent(_SseEvent event) {
      if (event.name == 'endpoint' && !endpointCompleter.isCompleted) {
        final data = event.data;
        final endpoint = Uri.tryParse(data.trim());
        if (endpoint != null) {
          endpointCompleter.complete(
            endpoint.hasScheme ? endpoint : resolvedSseUri.resolveUri(endpoint),
          );
        }
      } else if (event.name.isEmpty || event.name == 'message') {
        try {
          final decoded = jsonDecode(event.data);
          final decodedMessages = _jsonRpcMessagesFromDecoded(
            decoded,
          ).toList(growable: false);
          if (decodedMessages.isEmpty) {
            throw McpToolDiscoveryException(
              '工具扫描失败：SSE 端点返回了无效的 JSON-RPC 消息。'
              '${_mcpServerResponseDetail(event.data)}',
            );
          }
          for (final message in decodedMessages) {
            if (messages.isClosed) {
              break;
            }
            messages.add(message);
          }
        } catch (error, stack) {
          final surfacedError = error is McpToolDiscoveryException
              ? error
              : McpToolDiscoveryException(
                  '工具扫描失败：SSE 端点返回的内容不是有效 JSON。'
                  '${_mcpServerResponseDetail(event.data)}',
                );
          silentLog(
            'mcp_tool_discovery_service',
            '解析 SSE 事件载荷',
            surfacedError,
            stack,
          );
          if (!messages.isClosed) {
            messages.addError(surfacedError, stack);
          }
        }
      }
    }

    late final StreamSubscription<_SseEvent> subscription;
    subscription = response.stream
        .transform(
          const _BoundedSseEventTransformer(
            maxLineBytes: _mcpLegacySseMaxLineBytes,
            maxEventBytes: _mcpLegacySseMaxEventBytes,
          ),
        )
        .listen(
          handleEvent,
          onError: (Object error, StackTrace stackTrace) {
            if (!endpointCompleter.isCompleted) {
              endpointCompleter.completeError(error, stackTrace);
            }
            if (!messages.isClosed) {
              messages.addError(error, stackTrace);
              unawaited(
                _closeMcpStreamController(messages, where: '旧版 SSE 错误消息流'),
              );
            }
          },
          onDone: () {
            if (!endpointCompleter.isCompleted) {
              endpointCompleter.completeError(
                const McpToolDiscoveryException('工具扫描失败：SSE 端点在报告消息端点前已关闭。'),
              );
            }
            if (!messages.isClosed) {
              unawaited(
                _closeMcpStreamController(messages, where: '旧版 SSE 完成消息流'),
              );
            }
          },
          cancelOnError: true,
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
      await _cancelMcpStreamSubscription(subscription, where: '旧版 SSE 连接');
      await _closeMcpStreamController(messages, where: '旧版 SSE 连接消息流');
      rethrow;
    }
  }

  Future<Map<String, Object?>?> sendRequest(
    Map<String, Object?> payload, {
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    final requestIdText = '${payload['id']}';
    final responseFuture = _messages.stream
        .firstWhere(
          (message) => '${message['id']}' == requestIdText,
          // 匹配响应到达前连接关闭时统一转换为超时，让调用方只处理一种失败模式。
          orElse: () =>
              throw TimeoutException('MCP 流在请求 $requestIdText 返回响应前已关闭。'),
        )
        .timeout(timeout ?? _requestTimeout);
    observeMcpPendingFuture(responseFuture);
    await _post(payload, timeout: timeout, cancelSignal: cancelSignal);
    if (cancelSignal == null) return responseFuture;
    return Future.any<Map<String, Object?>?>(<Future<Map<String, Object?>?>>[
      responseFuture,
      cancelSignal.then<Map<String, Object?>?>(
        (_) => throw const McpToolDiscoveryException(
          'MCP 请求已取消。',
          isExpectedLifecycleCancellation: true,
        ),
        onError: (Object _, StackTrace _) =>
            throw const McpToolDiscoveryException(
              'MCP 请求已取消。',
              isExpectedLifecycleCancellation: true,
            ),
      ),
    ]);
  }

  Future<void> sendNotification(
    Map<String, Object?> payload, {
    Future<void>? cancelSignal,
  }) async {
    await _post(payload, cancelSignal: cancelSignal);
  }

  Future<void> _post(
    Map<String, Object?> payload, {
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    final effectiveTimeout = timeout ?? _requestTimeout;
    final response = await _sendRequestWithRedirects(
      client: _client,
      method: 'POST',
      uri: _endpointUri,
      headers: _mergeRequestHeaders(
        baseHeaders: const <String, String>{
          kContentTypeHeaderName: 'application/json',
          ..._mcpFreshRequestHeaders,
        },
        extraHeaders: _headers,
        protectedHeaderNames: const <String>{
          kContentTypeHeaderName,
          'cache-control',
          'pragma',
        },
      ),
      body: jsonEncode(payload),
      requestTimeout: effectiveTimeout,
      maxRedirects: DefaultMcpToolDiscoveryService._maxRedirects,
      additionalSensitiveHeaderNames: _sensitiveHeaderNames,
      cancelSignal: cancelSignal,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      final body = await _readMcpHttpErrorBodyBestEffort(
        response,
        timeout: effectiveTimeout,
      );
      throw McpToolDiscoveryException(
        '工具扫描请求失败，HTTP 状态码 ${response.statusCode}'
        '${_mcpServerResponseDetail(body)}',
      );
    }
    await _drainMcpHttpResponse(response, timeout: effectiveTimeout);
  }

  Future<void> close() async {
    await _cancelMcpStreamSubscription(_subscription, where: '旧版 SSE 会话');
    await _closeMcpStreamController(_messages, where: '旧版 SSE 会话消息流');
  }
}

/// 解析 MCP stdio 配置中的 `command`，把它升级成 *绝对路径 + 增强 PATH 的环境*。
///
/// 背景：从 Finder / Xcode / VS Code 启动的 macOS Flutter 应用，子进程继承到的
/// `PATH` 通常只剩 `/usr/bin:/bin:/usr/sbin:/sbin`，缺少 Homebrew (`/opt/homebrew/bin`、
/// `/usr/local/bin`)、`npm -g`、`pipx`、`uv`、`bun`、`deno`、`cargo`、`volta`、
/// `fnm`、`nvm` 等开发工具的 bin 目录。即便 PATH 里直接看到 nvm 的 `node/<v>/bin`，
/// 这些路径在 GUI 上下文里仍不可信 —— nvm/fnm/volta 等工具的真实 shim 是在 `.zshrc`
/// 里通过函数 / `$NVM_DIR` 注入的，不走静态目录。结果就是用户写
/// `npx chrome-devtools-mcp@latest` 这类配置时被 `errno=2 (No such file or directory)` 拒绝。
///
/// 解决方案分两层：
///   1. **登录 shell PATH 探测**（macOS / Linux）：首启时用 `/bin/zsh -ilc 'echo PATH=...'`
///      取得用户登录 shell 的 PATH（已 source 过 `.zshrc` / `.zprofile` / nvm.sh），
///      合并到环境里。
///   2. **bare 命令包裹登录 shell 执行**（macOS / Linux）：command 不含路径分隔符时，
///      改用 `/bin/zsh -lc 'exec <cmd> "$@"' _ <args...>`，由登录 shell 完成 PATH 查找。
///      这样 nvm 用 `node` 的 shell 函数也能正常工作。
class _ResolvedStdioLaunch {
  const _ResolvedStdioLaunch({
    required this.executable,
    required this.args,
    required this.environment,
    required this.augmentedPath,
  });

  final String executable;
  final List<String> args;
  final Map<String, String> environment;
  final String augmentedPath;
}

/// 登录 shell PATH 探测结果缓存。第一次调用阻塞（最多 [_loginShellProbeTimeout]），
/// 之后命中缓存。失败缓存为空字符串，避免反复花时间。
String? _cachedLoginShellPath;
Completer<String>? _loginShellPathProbe;
const Duration _loginShellProbeTimeout = Duration(seconds: 3);
const int _loginShellProbeMaxStdoutBytes = 64 * kBytesPerKiB;
const int _loginShellProbeMaxStderrBytes = 16 * kBytesPerKiB;

Future<String> _probeLoginShellPath() {
  if (_cachedLoginShellPath != null) {
    return Future.value(_cachedLoginShellPath!);
  }
  if (_loginShellPathProbe != null) return _loginShellPathProbe!.future;
  final completer = Completer<String>();
  _loginShellPathProbe = completer;

  () async {
    String result = '';
    try {
      // `-i` 让 zsh 当成交互式 (会读 .zshrc)，`-l` 当成登录 shell (读 .zprofile)。
      // 加 `-i` 并不会真的等待终端输入，因为我们重定向到 stdout / stdin 的管道。
      for (final candidate in await existingMcpLoginShells()) {
        try {
          final probe = await runProcessWithTimeout(
            candidate,
            const <String>['-ilc', 'printf %s "\$PATH"'],
            timeout: _loginShellProbeTimeout,
            tag: 'mcp.stdio.login_shell_path',
            maxStdoutBytes: _loginShellProbeMaxStdoutBytes,
            maxStderrBytes: _loginShellProbeMaxStderrBytes,
          );
          final path = probe == null ? null : nullIfBlank('${probe.stdout}');
          if (path != null) {
            result = path;
            break;
          }
        } catch (error, stack) {
          silentLog('mcp_stdio', '探测登录 Shell 路径/$candidate', error, stack);
        }
      }
    } catch (error, stack) {
      silentLog('mcp_stdio', '探测登录 Shell 路径', error, stack);
    }
    _cachedLoginShellPath = result;
    completer.complete(result);
  }();
  return completer.future;
}

Future<_ResolvedStdioLaunch> _resolveStdioLaunch(McpServer server) async {
  final separator = Platform.isWindows ? ';' : ':';
  final originalPath = Platform.environment['PATH'] ?? '';
  final originalSegments = splitTrimmedNonEmpty(
    originalPath,
    separator: separator,
  );

  final extraSegments = <String>[];
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (Platform.isMacOS) {
    extraSegments.addAll(const [
      '/opt/homebrew/bin',
      '/opt/homebrew/sbin',
      '/usr/local/bin',
      '/usr/local/sbin',
    ]);
  } else if (Platform.isLinux) {
    extraSegments.addAll(const [
      '/usr/local/bin',
      '/usr/local/sbin',
      '/snap/bin',
    ]);
  }
  if (home != null && home.isNotEmpty) {
    if (Platform.isWindows) {
      extraSegments.addAll([
        '$home\\AppData\\Roaming\\npm',
        '$home\\AppData\\Local\\Programs\\Python\\Python312\\Scripts',
        '$home\\.cargo\\bin',
        '$home\\.bun\\bin',
        '$home\\.deno\\bin',
        '$home\\.local\\bin',
      ]);
    } else {
      extraSegments.addAll([
        '$home/.npm-global/bin',
        '$home/.local/bin',
        '$home/.cargo/bin',
        '$home/.bun/bin',
        '$home/.deno/bin',
        '$home/.volta/bin',
      ]);
    }
  }

  // 登录 shell 探测得到的 PATH 在 macOS / Linux 上通常包含 nvm / fnm / volta 实
  // 际激活的 node bin，质量比启发式列表更可靠 —— 优先放最前面。
  if (!Platform.isWindows) {
    final shellPath = await _probeLoginShellPath();
    if (shellPath.isNotEmpty) {
      final shellSegments = splitTrimmedNonEmpty(
        shellPath,
        separator: separator,
      );
      extraSegments.insertAll(0, shellSegments);
    }
  }

  final mergedSegments = <String>[];
  final seen = <String>{};
  // 登录 shell PATH > 进程 PATH > 启发式扩展 PATH。
  for (final segment in [...extraSegments, ...originalSegments]) {
    if (seen.add(segment)) {
      mergedSegments.add(segment);
    }
  }
  final mergedPath = mergedSegments.join(separator);

  final rawCommandField = server.command.trim();
  // 兼容：用户经常把整条命令行（"npx chrome-devtools-mcp@latest"）粘进
  // "启动命令" 字段，而不是只填可执行文件名。这里 POSIX 风格拆词：第一段
  // 当作真正的可执行名，剩下的 token 作为 args 前缀拼到用户手填的 args 前。
  // 同时支持单 / 双引号包裹的 token，比如 `"node /path with space/x.js"`。
  final tokens = tokenizeMcpShellCommand(rawCommandField);
  final rawCommand = tokens.isNotEmpty ? tokens.first : rawCommandField;
  final inlineArgs = tokens.length > 1 ? tokens.sublist(1) : const <String>[];

  String executable = rawCommand;
  List<String> args = [...inlineArgs, ...server.args];

  // 快速路径：对 npx 命令，尝试直接定位已全局安装的包入口脚本用 node 执行。
  // 这避免了 npx 的启动开销和隔离缓存中的下载/兼容性问题。
  final isNpxCommand = rawCommand == 'npx' || rawCommand.endsWith('/npx');
  final packageArgIndex = isNpxCommand ? firstMcpNpxPackageArgIndex(args) : -1;
  if (isNpxCommand && packageArgIndex >= 0 && !Platform.isWindows) {
    final packageName = args[packageArgIndex];
    final resolved = await resolveInstalledMcpNodePackage(
      packageName,
      homeDirectory: home,
    );
    if (resolved != null) {
      final extraArgs = packageArgIndex + 1 < args.length
          ? args.sublist(packageArgIndex + 1)
          : const <String>[];
      return _ResolvedStdioLaunch(
        executable: resolved.nodeBin,
        args: [resolved.entryScript, ...extraArgs],
        environment: <String, String>{'PATH': mergedPath},
        augmentedPath: mergedPath,
      );
    }
  }

  final containsSeparator =
      rawCommand.contains('/') ||
      (Platform.isWindows && rawCommand.contains('\\'));

  if (rawCommand.isNotEmpty && !containsSeparator) {
    // 1) 先在合并 PATH 里直接 stat 文件，命中就用绝对路径直接 exec —— 最快、最干净。
    final candidates = <String>[rawCommand];
    if (Platform.isWindows) {
      final lower = rawCommand.toLowerCase();
      const exts = ['.cmd', '.bat', '.exe', '.ps1'];
      for (final ext in exts) {
        if (!lower.endsWith(ext)) {
          candidates.add('$rawCommand$ext');
        }
      }
    }
    String? hit;
    for (final dir in mergedSegments.take(_mcpStdioPathProbeLimit)) {
      for (final candidate in candidates) {
        final full = dir.endsWith(Platform.pathSeparator)
            ? '$dir$candidate'
            : '$dir${Platform.pathSeparator}$candidate';
        try {
          // 同时接受普通文件和指向文件的 symlink (nvm 的 npx 是 symlink → JS)。
          final type = await FileSystemEntity.type(
            full,
          ).timeout(_mcpStdioFileOperationTimeout);
          if (type == FileSystemEntityType.file) {
            hit = full;
            break;
          }
        } catch (_) {
          // 权限 / 其他系统错误：跳过该候选。
        }
      }
      if (hit != null) break;
    }
    if (hit != null) {
      executable = hit;
    } else if (!Platform.isWindows) {
      // 2) 没在静态目录命中：通过登录 shell 间接执行。这样 nvm 的 `npx` 函数
      //    （而非真实文件）也能被找到。`exec` 让 shell 替换为目标进程，避免
      //    多套一层 wait。args 用 `"$@"` 透传，避免引号 / 空格灾难。
      final shellArgs = <String>[
        '-lc',
        'exec ${quoteMcpShellToken(rawCommand)} "\$@"',
        '_', // $0 占位，保证 args 从 $1 开始。
        ...args,
      ];
      executable = await resolveMcpLoginShell();
      args = shellArgs;
    }
  }

  return _ResolvedStdioLaunch(
    executable: executable,
    args: args,
    environment: <String, String>{
      'PATH': mergedPath,
      // 把 npm / pnpm / yarn / bun / uv / pip 的缓存目录隔离到 ~/.openhand/mcp/package-cache，
      // 避开用户 ~/.npm 因历史 sudo install 留下的 root 属主文件 (典型症状：
      // EACCES rename / EEXIST / ENOTEMPTY)。所有目录懒创建，存在则复用。
      ...await mcpStdioIsolatedCacheEnv(),
    },
    augmentedPath: mergedPath,
  );
}

/// 删除整个隔离缓存目录；目录不存在视为成功。
/// 失败抛 [FileSystemException]，调用方负责 toast。
Future<void> resetMcpStdioIsolatedCache() async {
  final dir = Directory(mcpStdioIsolatedCacheRoot());
  final type = await FileSystemEntity.type(
    dir.path,
    followLinks: false,
  ).timeout(_mcpStdioFileOperationTimeout);
  if (type == FileSystemEntityType.notFound) return;
  if (type != FileSystemEntityType.directory) {
    throw FileSystemException('MCP 软件包缓存路径不是目录。', dir.path);
  }
  await deletePathBounded(p.absolute(dir.path), policy: _mcpCacheDeletePolicy);
}

/// 全局可监听：每个 stdio MCP server 当前 bootstrap 进度行（通常是 npm /
/// uv 的下载进度），UI 用它在「Bootstrapping…」chip / Tooltip 里实时刷新。
/// init 成功或失败后会自动清空对应 server 的状态。
final McpStdioBootstrapStatus mcpStdioBootstrapStatus =
    McpStdioBootstrapStatus._();

class McpStdioBootstrapStatus extends ChangeNotifier {
  McpStdioBootstrapStatus._();

  final Map<String, String> _byServer = <String, String>{};

  /// 取某个 server 的最新进度行；不存在返回 null。
  String? statusOf(String serverId) => _byServer[serverId];

  void update(String serverId, String line) {
    if (_byServer[serverId] == line) return;
    _byServer[serverId] = line;
    notifyListeners();
  }

  void clear(String serverId) {
    if (_byServer.remove(serverId) != null) {
      notifyListeners();
    }
  }
}

/// 把 stdio MCP server stderr 关键词翻译成「现象 / 原因 / 建议」式中文提示。
/// 无法识别返回空串。设计原则：宁缺勿滥，匹配高置信度的用户环境配置错误。
String _diagnoseStdioStderr(String stderr) {
  final text = stderr;
  final lower = text.toLowerCase();
  // npm 缓存损坏 / 权限错乱（最常见：曾经 sudo npm install 留下 root 权限的
  // ~/.npm，现在普通用户身份的 GUI 应用写不进去）。EACCES + EEXIST + ENOTEMPTY
  // 任意命中 npm 路径都给同一个建议。
  final hitsEacces =
      lower.contains('eacces') || lower.contains('permission denied');
  final hitsEexist = lower.contains('eexist');
  final hitsEnotempty = lower.contains('enotempty');
  final hitsNpmCache =
      lower.contains('/.npm/') ||
      lower.contains(r'\.npm\') ||
      lower.contains('_cacache') ||
      lower.contains('_npx');
  if ((hitsEacces || hitsEexist || hitsEnotempty) && hitsNpmCache) {
    return '【诊断 / Diagnosis】 npm 缓存目录权限或文件状态异常 —— 可能曾经用 '
        '`sudo npm` 安装过包，留下属主为 root 的缓存文件。\n'
        '【建议 / Try】\n'
        '  · 一次性修复属主：`sudo chown -R \$(whoami) ~/.npm`\n'
        '  · 或者直接清空缓存：`rm -rf ~/.npm/_cacache ~/.npm/_npx` 后重试\n'
        '  · 若仍报 EEXIST：`npm cache clean --force` 然后再次启动';
  }
  // node 未安装 / 版本不兼容
  if (lower.contains('engine') &&
      lower.contains('node') &&
      (lower.contains('unsupported') || lower.contains('incompatible'))) {
    return '【诊断 / Diagnosis】 该 MCP 服务对 Node 版本有要求，但当前 Node 版本不满足。\n'
        '【建议 / Try】 升级 Node (建议 LTS)，nvm/volta 用户记得切到符合要求的版本。';
  }
  // 网络层：取包失败 / 代理拦截
  if (lower.contains('etimedout') ||
      lower.contains('econnrefused') ||
      lower.contains('enotfound') ||
      (lower.contains('npm error') && lower.contains('network'))) {
    return '【诊断 / Diagnosis】 npm 取包阶段被网络层拦截或目标服务器不可达。\n'
        '【建议 / Try】\n'
        '  · 检查代理 / VPN 配置（npm 默认不走系统代理）\n'
        '  · 切换 registry：`npm config set registry $_kNpmMirrorRegistry`\n'
        '  · 等几秒后重试';
  }
  // python uv / pipx 缺包
  if (lower.contains('no module named') ||
      lower.contains('modulenotfounderror')) {
    return '【诊断 / Diagnosis】 Python 依赖未安装。\n'
        '【建议 / Try】 在该 MCP 服务对应 venv 里 `pip install` 缺失模块；'
        '若用 uvx，可尝试 `uv tool install <pkg>` 后再启动。';
  }
  // chrome-devtools-mcp 特有：需要 Chrome/Chromium 浏览器可用
  if (lower.contains('chrome') &&
      (lower.contains('not found') ||
          lower.contains('no chrome') ||
          lower.contains('cannot find') ||
          lower.contains('failed to launch') ||
          lower.contains('connect econnrefused'))) {
    return '【诊断 / Diagnosis】 chrome-devtools-mcp 需要本机安装 Chrome 或 Chromium 浏览器。\n'
        '【建议 / Try】\n'
        '  · 确认 Chrome / Chromium 已安装且可正常启动\n'
        '  · 若使用 --channel=beta，需安装 Chrome Beta 版本\n'
        '  · 若使用 --autoConnect，需先手动启动 Chrome 并开启远程调试端口\n'
        '  · 尝试不带 --autoConnect 参数启动，让 MCP 服务自行管理浏览器实例';
  }
  // 进程立即退出（通用）
  if (lower.contains('exited with code') ||
      lower.contains('spawn') && lower.contains('enoent')) {
    return '【诊断 / Diagnosis】 MCP 服务进程启动后立即退出或可执行文件不存在。\n'
        '【建议 / Try】\n'
        '  · 在终端手动运行该命令确认能正常启动\n'
        '  · 检查命令路径是否正确（npx 包名是否拼写正确）\n'
        '  · 确认 Node.js / npm 已正确安装且在 PATH 中';
  }
  return '';
}

class _StdioSession {
  _StdioSession({
    required Process process,
    required Duration requestTimeout,
    this.onStderrLine,
  }) : _process = process,
       _requestTimeout = requestTimeout {
    _stdoutSubscription = _process.stdout.listen(
      _handleStdoutData,
      onError: (Object error, StackTrace stackTrace) {
        _failPendingResponses(_stdioSessionStreamError(error), stackTrace);
      },
      onDone: () {
        _appendTrace('stdout:done');
        _failPendingResponses(_stdioSessionClosedError());
      },
      cancelOnError: false,
    );
    _stderrSubscription = _process.stderr.transform(utf8.decoder).listen((
      chunk,
    ) {
      if (_stderrBuffer.length < 4096) {
        _stderrBuffer.write(chunk);
      }
      // 行级解析：按 \r 或 \n 切分（npm/yarn 进度条爱用 \r 原地刷新），
      // 把最新一行透出给 UI 做「正在下载 puppeteer 32%」类实时提示。
      final cb = onStderrLine;
      if (cb != null) {
        _stderrLineBuffer.write(chunk);
        var buffer = _stderrLineBuffer.toString();
        var splitIndex = buffer.lastIndexOf(_stdioLineBreakPattern);
        if (splitIndex < 0) {
          if (buffer.length > 4096) {
            // 防御：单行超长（无换行）时也切，避免无限堆积。
            _stderrLineBuffer
              ..clear()
              ..write(buffer.substring(buffer.length ~/ 2));
          }
          return;
        }
        final completed = buffer.substring(0, splitIndex);
        final tail = buffer.substring(splitIndex + 1);
        _stderrLineBuffer
          ..clear()
          ..write(tail);
        for (final raw in completed.split(_stdioLineBreaksPattern)) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          try {
            cb(line);
          } catch (error, stack) {
            silentLog('mcp_stdio', '处理标准错误输出行', error, stack);
          }
        }
      }
    });
    unawaited(
      _process.exitCode.then<void>(
        (code) => _appendTrace('process:exit:$code'),
        onError: (Object error, StackTrace stack) {
          silentLog('mcp_stdio', '监听进程退出', error, stack);
        },
      ),
    );
  }

  static const McpToolDiscoveryException _closingWriteException =
      McpToolDiscoveryException(
        kMcpStdioSessionClosingMessage,
        isExpectedLifecycleCancellation: true,
      );

  final Process _process;
  Process get process => _process;
  final Duration _requestTimeout;
  final List<int> _stdoutBuffer = <int>[];
  final StringBuffer _stderrBuffer = StringBuffer();
  final StringBuffer _stderrLineBuffer = StringBuffer();
  final StringBuffer _traceBuffer = StringBuffer();
  final void Function(String line)? onStderrLine;
  final Map<String, Completer<Map<String, Object?>?>> _pendingResponses =
      <String, Completer<Map<String, Object?>?>>{};
  final McpStdioWriteQueue _stdinWriteQueue = McpStdioWriteQueue();
  String instructions = '';
  late final StreamSubscription<List<int>> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;
  Future<void>? _closeFuture;
  bool _stdoutDrainScheduled = false;

  Future<Map<String, Object?>?> sendRequest(
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    final requestIdText = '${payload['id']}';
    if (_pendingResponses.containsKey(requestIdText)) {
      throw McpToolDiscoveryException('MCP stdio 请求编号重复：$requestIdText。');
    }
    if (_pendingResponses.length >= kMcpStdioMaxPendingRequests) {
      throw McpToolDiscoveryException(
        'MCP stdio 待处理请求过多'
        '（${_pendingResponses.length}/$kMcpStdioMaxPendingRequests）。',
      );
    }
    final completer = Completer<Map<String, Object?>?>();
    observeMcpPendingFuture(completer.future);
    _pendingResponses[requestIdText] = completer;
    try {
      await _write(payload);
    } catch (error, stack) {
      _pendingResponses.remove(requestIdText);
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
      rethrow;
    }
    try {
      return await completer.future.timeout(timeout ?? _requestTimeout);
    } on TimeoutException catch (error, stack) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
      rethrow;
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
    // 无效行和空帧同样计入批次，避免异常输出长时间独占事件循环。
    var takes = 0;
    while (takes < DefaultMcpToolDiscoveryService._maxStdoutMessagesPerDrain) {
      final payload = _takeNextMessage();
      if (payload == null) {
        return;
      }
      takes += 1;
      if (payload.isEmpty) {
        continue;
      }
      Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        throw McpToolDiscoveryException(
          '工具扫描失败：stdio MCP 服务返回的内容不是有效 JSON。'
          '${_mcpServerResponseDetail(payload)}',
        );
      }
      final decodedMessages = _jsonRpcMessagesFromDecoded(
        decoded,
      ).toList(growable: false);
      if (decodedMessages.isEmpty) {
        throw McpToolDiscoveryException(
          '工具扫描失败：stdio MCP 服务返回了无效的 JSON-RPC 消息。'
          '${_mcpServerResponseDetail(payload)}',
        );
      }
      for (final message in decodedMessages) {
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
        }
      }
    }
    _scheduleStdoutDrain();
  }

  String? _takeNextMessage() {
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
    return '';
  }

  void _scheduleStdoutDrain() {
    if (_stdoutDrainScheduled || _stdoutBuffer.isEmpty) return;
    _stdoutDrainScheduled = true;
    startSafeTimer(Duration.zero, () {
      _stdoutDrainScheduled = false;
      try {
        _drainStdoutBuffer();
        _enforceStdoutBufferLimit();
      } catch (error, stackTrace) {
        _failPendingResponses(error, stackTrace);
      }
    });
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
    final traceSuffix = trace.isEmpty ? '' : ' 跟踪：$trace';
    if (stderr.isEmpty) {
      return '工具扫描失败：stdio MCP 服务意外关闭。$traceSuffix';
    }
    final hint = _diagnoseStdioStderr(stderr);
    final hintSuffix = hint.isEmpty ? '' : '\n\n$hint';
    return '工具扫描失败：stdio MCP 服务意外关闭：$stderr$traceSuffix$hintSuffix';
  }

  Object _stdioSessionStreamError(Object error) {
    if (_closeFuture != null) {
      return _closingWriteException;
    }
    return error;
  }

  Object _stdioSessionClosedError() {
    if (_closeFuture != null) {
      return _closingWriteException;
    }
    return McpToolDiscoveryException(_closedUnexpectedlyMessage());
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
    final traceSuffix = trace.isEmpty ? '' : ' 跟踪：$trace';
    const maxMiB =
        DefaultMcpToolDiscoveryService._maxStdioStdoutBufferBytes ~/
        kBytesPerMiB;
    return '工具扫描失败：stdio MCP 服务向标准输出写入超过 $maxMiB MiB，仍未形成完整协议消息。$traceSuffix';
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
    // 至少需要 4 个字符才能有意义地匹配 "content-length" 前缀，
    // 避免单个 'c' / 'co' / 'con' 等常见 stdout 输出（如 "connecting..."）
    // 导致解析器误判为 framed message 而无限等待。
    if (prefix.length < 4) return false;
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
      return optionalIntFromValue(line.substring(separatorIndex + 1));
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
    if (_closeFuture != null || _stdinWriteQueue.isClosed) {
      throw _closingWriteException;
    }
    await _stdinWriteQueue.run(() async {
      _appendTrace(
        'stdin:write:${payload['method'] ?? 'unknown'}:${payload['id'] ?? ''}',
      );
      // MCP stdio 传输使用 JSON-line 模式：每条消息为一行完整 JSON + 换行符。
      // 不发送 Content-Length header——Playwright 等主流 MCP 服务使用 JSON-line
      // 解析，Content-Length header 会干扰其消息边界检测导致后续消息丢失。
      try {
        await writeMcpJsonLineToStdin(_process.stdin, payload);
      } on StateError catch (error, stack) {
        if (!isExpectedMcpStdioSinkStateError(error)) {
          silentLog('mcp_stdio', '写入进程标准输入', error, stack);
          throw McpToolDiscoveryException('工具扫描失败：标准输入不可用：$error');
        }
        throw _closingWriteException;
      }
    });
  }

  Future<void> close() {
    final closeFuture = _closeFuture;
    if (closeFuture != null) {
      return closeFuture;
    }
    _stdinWriteQueue.rejectNewWrites(_closingWriteException);
    return _closeFuture = _closeOnce();
  }

  Future<void> _closeOnce() async {
    await _stdinWriteQueue.drain(
      DefaultMcpToolDiscoveryService._stdioShutdownTimeout,
    );
    // 关闭前释放 pending responses，避免上层仍在等待已经不可达的响应。
    _failPendingResponses(_closingWriteException);
    await closeMcpStdioSinkQuietly(
      stdin: _process.stdin,
      timeout: DefaultMcpToolDiscoveryService._stdioShutdownTimeout,
      logTag: 'mcp.stdio',
      logWhere: '关闭标准输入',
    );
    await _waitForExitOrKill();
    await _cancelSubscription(_stdoutSubscription, '关闭标准输出流');
    await _cancelSubscription(_stderrSubscription, '关闭标准错误流');
  }

  Future<void> _waitForExitOrKill() async {
    if (await _waitForExit()) return;
    await terminateTrackedProcessTree(
      _process,
      gracefulTimeout: DefaultMcpToolDiscoveryService._stdioShutdownTimeout,
    );
    await _waitForExit();
  }

  Future<bool> _waitForExit() async {
    try {
      await _process.exitCode.timeout(
        DefaultMcpToolDiscoveryService._stdioShutdownTimeout,
      );
      return true;
    } on TimeoutException {
      return false;
    } catch (error, stack) {
      silentLog('mcp_stdio', '关闭时读取进程退出码', error, stack);
      return true;
    }
  }

  Future<void> _cancelSubscription<T>(
    StreamSubscription<T> subscription,
    String where,
  ) async {
    await cancelStreamSubscriptionBounded<T>(
      subscription,
      timeout: _mcpStreamCleanupTimeout,
      onError: (error, stack) => silentLog('mcp_stdio', where, error, stack),
    );
  }
}

Future<void> _cancelMcpStreamSubscription<T>(
  StreamSubscription<T> subscription, {
  required String where,
}) async {
  await cancelStreamSubscriptionBounded<T>(
    subscription,
    timeout: _mcpStreamCleanupTimeout,
    onError: (error, stack) =>
        silentLog('mcp_tool_discovery_service', '取消：$where', error, stack),
  );
}

Future<void> _closeMcpStreamController<T>(
  StreamController<T> controller, {
  required String where,
}) async {
  if (controller.isClosed) return;
  try {
    await controller.close().timeout(_mcpStreamCleanupTimeout);
  } catch (error, stack) {
    silentLog('mcp_tool_discovery_service', '关闭：$where', error, stack);
  }
}

class _BoundedSseEventTransformer
    extends StreamTransformerBase<List<int>, _SseEvent> {
  const _BoundedSseEventTransformer({
    required this.maxLineBytes,
    required this.maxEventBytes,
  });

  final int maxLineBytes;
  final int maxEventBytes;

  @override
  Stream<_SseEvent> bind(Stream<List<int>> stream) {
    final parser = _BoundedSseEventParser(
      maxLineBytes: maxLineBytes,
      maxEventBytes: maxEventBytes,
    );
    StreamSubscription<List<int>>? sourceSubscription;
    Future<void>? sourceCancellation;
    var cancelPending = false;
    var terminated = false;

    Future<void> cancelSource() {
      final active = sourceSubscription;
      if (active == null) {
        cancelPending = true;
        return Future<void>.value();
      }
      return sourceCancellation ??= _cancelMcpStreamSubscription(
        active,
        where: '旧版 SSE 响应流',
      );
    }

    late final StreamController<_SseEvent> output;

    void emit(_SseEvent event) {
      if (!terminated && !output.isClosed) {
        output.add(event);
      }
    }

    void fail(Object error, StackTrace stack) {
      if (terminated) return;
      terminated = true;
      if (!output.isClosed) {
        output.addError(error, stack);
        unawaited(output.close());
      }
      unawaited(cancelSource());
    }

    output = StreamController<_SseEvent>(
      sync: true,
      onListen: () {
        try {
          sourceSubscription = stream.listen(
            (chunk) {
              if (terminated) return;
              try {
                parser.addChunk(chunk, emit);
              } catch (error, stack) {
                fail(error, stack);
              }
            },
            onError: (Object error, StackTrace stack) => fail(error, stack),
            onDone: () {
              if (terminated) return;
              try {
                parser.finish(emit);
                terminated = true;
                unawaited(output.close());
              } catch (error, stack) {
                fail(error, stack);
              }
            },
            cancelOnError: false,
          );
          if (cancelPending || terminated) {
            unawaited(cancelSource());
          }
        } catch (error, stack) {
          fail(error, stack);
        }
      },
      onPause: () => sourceSubscription?.pause(),
      onResume: () => sourceSubscription?.resume(),
      onCancel: () {
        terminated = true;
        return cancelSource();
      },
    );
    return output.stream;
  }
}

class _BoundedSseEventParser {
  _BoundedSseEventParser({
    required this.maxLineBytes,
    required this.maxEventBytes,
  }) {
    requirePositiveInt(maxLineBytes, 'maxLineBytes');
    requirePositiveInt(maxEventBytes, 'maxEventBytes');
  }

  static const int _carriageReturn = 0x0d;
  static const int _lineFeed = 0x0a;
  static const int _colon = 0x3a;
  static const int _space = 0x20;

  final int maxLineBytes;
  final int maxEventBytes;
  final BytesBuilder _line = BytesBuilder();
  final BytesBuilder _data = BytesBuilder();
  String _eventName = '';
  int _eventNameBytes = 0;
  bool _hasData = false;
  bool _skipLeadingLineFeed = false;

  void addChunk(List<int> chunk, void Function(_SseEvent event) emit) {
    var start = 0;
    if (_skipLeadingLineFeed && chunk.isNotEmpty) {
      _skipLeadingLineFeed = false;
      if (chunk.first == _lineFeed) {
        start = 1;
      }
    }
    while (start < chunk.length) {
      var delimiter = -1;
      for (var i = start; i < chunk.length; i++) {
        if (chunk[i] == _lineFeed || chunk[i] == _carriageReturn) {
          delimiter = i;
          break;
        }
      }
      if (delimiter < 0) {
        _appendLineBytes(chunk, start, chunk.length);
        return;
      }
      _appendLineBytes(chunk, start, delimiter);
      _finishLine(emit);
      final delimiterByte = chunk[delimiter];
      start = delimiter + 1;
      if (delimiterByte == _carriageReturn) {
        if (start < chunk.length && chunk[start] == _lineFeed) {
          start++;
        } else if (start == chunk.length) {
          _skipLeadingLineFeed = true;
        }
      }
    }
  }

  void finish(void Function(_SseEvent event) emit) {
    if (_line.isNotEmpty) {
      _finishLine(emit);
    }
    _emitEvent(emit);
  }

  void _appendLineBytes(List<int> chunk, int start, int end) {
    final addedBytes = end - start;
    if (addedBytes <= 0) return;
    if (_line.length + addedBytes > maxLineBytes) {
      throw McpToolDiscoveryException(
        'MCP SSE 单行超过 ${formatByteSize(maxLineBytes)} 的安全上限。',
      );
    }
    if (chunk is Uint8List) {
      _line.add(Uint8List.sublistView(chunk, start, end));
    } else {
      _line.add(chunk.sublist(start, end));
    }
  }

  void _finishLine(void Function(_SseEvent event) emit) {
    final line = _line.takeBytes();
    final end = line.length;
    if (end == 0) {
      _emitEvent(emit);
      return;
    }
    if (line[0] == _colon) return;

    var colon = -1;
    for (var i = 0; i < end; i++) {
      if (line[i] == _colon) {
        colon = i;
        break;
      }
    }
    final fieldEnd = colon < 0 ? end : colon;
    var valueStart = colon < 0 ? end : colon + 1;
    if (valueStart < end && line[valueStart] == _space) {
      valueStart++;
    }

    if (_isEventField(line, fieldEnd)) {
      final valueBytes = end - valueStart;
      _ensureEventCapacity(_data.length + valueBytes, replacingEventName: true);
      _eventName = utf8.decode(Uint8List.sublistView(line, valueStart, end));
      _eventNameBytes = valueBytes;
      return;
    }
    if (!_isDataField(line, fieldEnd)) return;

    final separatorBytes = _hasData ? 1 : 0;
    final valueBytes = end - valueStart;
    _ensureEventCapacity(
      _data.length + separatorBytes + valueBytes,
      replacingEventName: false,
    );
    if (_hasData) {
      _data.addByte(_lineFeed);
    }
    if (valueBytes > 0) {
      _data.add(Uint8List.sublistView(line, valueStart, end));
    }
    _hasData = true;
  }

  void _ensureEventCapacity(
    int prospectiveDataBytes, {
    required bool replacingEventName,
  }) {
    final prospectiveBytes =
        prospectiveDataBytes + (replacingEventName ? 0 : _eventNameBytes);
    if (prospectiveBytes > maxEventBytes) {
      throw McpToolDiscoveryException(
        'MCP SSE 事件超过 ${formatByteSize(maxEventBytes)} 的安全上限。',
      );
    }
  }

  void _emitEvent(void Function(_SseEvent event) emit) {
    if (_hasData) {
      emit(_SseEvent(name: _eventName, data: utf8.decode(_data.takeBytes())));
    } else {
      _data.clear();
    }
    _eventName = '';
    _eventNameBytes = 0;
    _hasData = false;
  }

  bool _isEventField(Uint8List line, int end) {
    return end == 5 &&
        line[0] == 0x65 &&
        line[1] == 0x76 &&
        line[2] == 0x65 &&
        line[3] == 0x6e &&
        line[4] == 0x74;
  }

  bool _isDataField(Uint8List line, int end) {
    return end == 4 &&
        line[0] == 0x64 &&
        line[1] == 0x61 &&
        line[2] == 0x74 &&
        line[3] == 0x61;
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
    if (!isValidMcpHttpHeader(name, value)) {
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
  return stringListFromValue(
    headers.keys.toList(growable: false),
  ).map((item) => item.toLowerCase()).toSet();
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
    final processPath = Platform.environment['PATH'] ?? '';
    final shellPath = _cachedLoginShellPath ?? '';
    final emptyPathText = openHandAmbientText(
      zh: '(空)',
      zhHant: '(空)',
      en: '(empty)',
      fr: '(vide)',
      de: '(leer)',
      ja: '(空)',
    );
    String pathHint;
    if (shellPath.isNotEmpty) {
      pathHint = openHandAmbientText(
        zh:
            '登录 shell 探测: $shellPath\n'
            '  · 进程 PATH: ${processPath.isEmpty ? emptyPathText : processPath}',
        zhHant:
            '登入 shell 探測: $shellPath\n'
            '  · 行程 PATH: ${processPath.isEmpty ? emptyPathText : processPath}',
        en:
            'Login shell probe: $shellPath\n'
            '  · Process PATH: ${processPath.isEmpty ? emptyPathText : processPath}',
        fr:
            'Sonde du shell de connexion : $shellPath\n'
            '  · PATH du processus : ${processPath.isEmpty ? emptyPathText : processPath}',
        de:
            'Login-Shell-Prüfung: $shellPath\n'
            '  · Prozess-PATH: ${processPath.isEmpty ? emptyPathText : processPath}',
        ja:
            'ログイン shell の検出: $shellPath\n'
            '  · プロセス PATH: ${processPath.isEmpty ? emptyPathText : processPath}',
      );
    } else {
      pathHint = processPath.isEmpty ? emptyPathText : processPath;
    }
    return AiTransportDiagnosticMessages.format(
      title: openHandAmbientText(
        zh: 'MCP 进程启动失败 [${server.name}]',
        zhHant: 'MCP 行程啟動失敗 [${server.name}]',
        en: 'MCP stdio launch failed [${server.name}]',
        fr: 'Échec du lancement stdio MCP [${server.name}]',
        de: 'MCP-stdio-Start fehlgeschlagen [${server.name}]',
        ja: 'MCP stdio の起動に失敗しました [${server.name}]',
      ),
      reason: openHandAmbientText(
        zh:
            '尝试以子进程方式启动 MCP 服务时被操作系统拒绝：\n'
            '  · 命令: ${error.executable}${error.arguments.isEmpty ? '' : ' ${error.arguments.join(' ')}'}\n'
            '  · 退出 / errno: ${error.errorCode}\n'
            '  · 解析后的 PATH: $pathHint\n'
            '常见诱因：\n'
            '  · 命令不在 PATH 上 (GUI 启动的应用 PATH 极简，不含 Homebrew / nvm / volta / npm-global 等)\n'
            '  · 命令拼写错误 / 二进制未安装 (例如未装 Node 就写了 npx)\n'
            '  · 可执行文件缺少执行权限 (chmod +x)\n'
            '  · 依赖未安装 (例如 npm 包未 install / Python venv 未激活)\n'
            '  · 沙盒 / SIP / Gatekeeper 拒绝该二进制运行',
        zhHant:
            '嘗試以子行程啟動 MCP 服務時被作業系統拒絕：\n'
            '  · 命令: ${error.executable}${error.arguments.isEmpty ? '' : ' ${error.arguments.join(' ')}'}\n'
            '  · 退出 / errno: ${error.errorCode}\n'
            '  · 解析後的 PATH: $pathHint\n'
            '常見原因：\n'
            '  · 命令不在 PATH 上 (GUI 啟動的應用 PATH 很精簡，不含 Homebrew / nvm / volta / npm-global 等)\n'
            '  · 命令拼寫錯誤 / 二進位未安裝 (例如未安裝 Node 卻使用 npx)\n'
            '  · 可執行檔缺少執行權限 (chmod +x)\n'
            '  · 依賴未安裝 (例如 npm 包未 install / Python venv 未啟用)\n'
            '  · 沙盒 / SIP / Gatekeeper 拒絕該二進位執行',
        en:
            'The operating system refused to start the MCP service as a child process:\n'
            '  · Command: ${error.executable}${error.arguments.isEmpty ? '' : ' ${error.arguments.join(' ')}'}\n'
            '  · Exit / errno: ${error.errorCode}\n'
            '  · Resolved PATH: $pathHint\n'
            'Common causes:\n'
            '  · The command is not on PATH (GUI-launched apps often have a minimal PATH without Homebrew / nvm / volta / npm-global)\n'
            '  · The command is misspelled or the binary is not installed (for example npx without Node)\n'
            '  · The executable lacks permission (chmod +x)\n'
            '  · Dependencies are missing (for example npm install not run or Python venv not activated)\n'
            '  · Sandbox / SIP / Gatekeeper blocked the binary',
        fr:
            'Le système a refusé de lancer le service MCP comme sous-processus :\n'
            '  · Commande : ${error.executable}${error.arguments.isEmpty ? '' : ' ${error.arguments.join(' ')}'}\n'
            '  · Sortie / errno : ${error.errorCode}\n'
            '  · PATH résolu : $pathHint\n'
            'Causes fréquentes :\n'
            '  · La commande n’est pas dans PATH (les apps lancées par GUI ont souvent un PATH minimal sans Homebrew / nvm / volta / npm-global)\n'
            '  · Commande mal orthographiée ou binaire absent (par exemple npx sans Node)\n'
            '  · Permission d’exécution manquante (chmod +x)\n'
            '  · Dépendances non installées (npm install absent ou venv Python non activé)\n'
            '  · Sandbox / SIP / Gatekeeper bloque le binaire',
        de:
            'Das Betriebssystem hat den Start des MCP-Dienstes als Kindprozess verweigert:\n'
            '  · Befehl: ${error.executable}${error.arguments.isEmpty ? '' : ' ${error.arguments.join(' ')}'}\n'
            '  · Exit / errno: ${error.errorCode}\n'
            '  · Aufgelöster PATH: $pathHint\n'
            'Häufige Ursachen:\n'
            '  · Der Befehl liegt nicht auf PATH (GUI-Apps haben oft einen minimalen PATH ohne Homebrew / nvm / volta / npm-global)\n'
            '  · Befehl falsch geschrieben oder Binary nicht installiert (z. B. npx ohne Node)\n'
            '  · Ausführungsrecht fehlt (chmod +x)\n'
            '  · Abhängigkeiten fehlen (z. B. npm install nicht ausgeführt oder Python venv nicht aktiv)\n'
            '  · Sandbox / SIP / Gatekeeper blockiert das Binary',
        ja:
            'MCP サービスを子プロセスとして起動しようとしましたが、OS に拒否されました:\n'
            '  · コマンド: ${error.executable}${error.arguments.isEmpty ? '' : ' ${error.arguments.join(' ')}'}\n'
            '  · 終了 / errno: ${error.errorCode}\n'
            '  · 解決後の PATH: $pathHint\n'
            'よくある原因:\n'
            '  · コマンドが PATH にない (GUI から起動したアプリの PATH は最小限で、Homebrew / nvm / volta / npm-global などを含まないことがあります)\n'
            '  · コマンドのスペルミス、またはバイナリ未インストール (Node なしで npx を使うなど)\n'
            '  · 実行権限がない (chmod +x)\n'
            '  · 依存関係が未インストール (npm install 未実行、Python venv 未有効化など)\n'
            '  · Sandbox / SIP / Gatekeeper がバイナリを拒否',
      ),
      try_: openHandAmbientText(
        zh:
            '· 在终端独立运行该命令复现报错：`which npx && npx <pkg>`\n'
            '· 把 command 改成绝对路径 (如 /opt/homebrew/bin/npx) 再保存\n'
            '· 用 nvm / volta 的用户：在登录 shell 启动应用，或用 corepack/volta shim\n'
            '· 检查 PATH 与可执行权限\n'
            '· 重新安装该 MCP 工具的依赖',
        zhHant:
            '· 在終端獨立執行該命令重現錯誤：`which npx && npx <pkg>`\n'
            '· 將 command 改成絕對路徑 (如 /opt/homebrew/bin/npx) 後儲存\n'
            '· 使用 nvm / volta：從登入 shell 啟動應用，或使用 corepack/volta shim\n'
            '· 檢查 PATH 與執行權限\n'
            '· 重新安裝該 MCP 工具的依賴',
        en:
            '· Run the command directly in a terminal to reproduce it: `which npx && npx <pkg>`\n'
            '· Save command as an absolute path, such as /opt/homebrew/bin/npx\n'
            '· For nvm / volta users: launch the app from a login shell, or use a corepack/volta shim\n'
            '· Check PATH and executable permissions\n'
            '· Reinstall this MCP tool’s dependencies',
        fr:
            '· Exécutez la commande dans un terminal : `which npx && npx <pkg>`\n'
            '· Enregistrez command avec un chemin absolu, par exemple /opt/homebrew/bin/npx\n'
            '· Avec nvm / volta : lancez l’app depuis un shell de connexion, ou utilisez un shim corepack/volta\n'
            '· Vérifiez PATH et les permissions d’exécution\n'
            '· Réinstallez les dépendances de cet outil MCP',
        de:
            '· Führe den Befehl direkt im Terminal aus: `which npx && npx <pkg>`\n'
            '· Speichere command als absoluten Pfad, z. B. /opt/homebrew/bin/npx\n'
            '· Für nvm / volta: App aus einer Login-Shell starten oder corepack/volta shim nutzen\n'
            '· PATH und Ausführungsrechte prüfen\n'
            '· Abhängigkeiten dieses MCP-Tools neu installieren',
        ja:
            '· ターミナルで直接コマンドを実行して再現してください: `which npx && npx <pkg>`\n'
            '· command を /opt/homebrew/bin/npx などの絶対パスにして保存してください\n'
            '· nvm / volta 利用時はログイン shell からアプリを起動するか、corepack/volta shim を使ってください\n'
            '· PATH と実行権限を確認してください\n'
            '· この MCP ツールの依存関係を再インストールしてください',
      ),
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
    'discover' => openHandAmbientText(
      zh: '工具扫描',
      zhHant: '工具掃描',
      en: 'tool discovery',
      fr: 'découverte des outils',
      de: 'Tool-Erkennung',
      ja: 'ツール検出',
    ),
    'health' => openHandAmbientText(
      zh: '健康检查',
      zhHant: '健康檢查',
      en: 'health check',
      fr: 'contrôle de santé',
      de: 'Health Check',
      ja: 'ヘルスチェック',
    ),
    _ => stage,
  };
  final humanLimit = limit.inSeconds >= 90
      ? openHandAmbientText(
          zh: '${(limit.inSeconds / 60).toStringAsFixed(limit.inSeconds % 60 == 0 ? 0 : 1)} 分钟',
          zhHant:
              '${(limit.inSeconds / 60).toStringAsFixed(limit.inSeconds % 60 == 0 ? 0 : 1)} 分鐘',
          en: '${(limit.inSeconds / 60).toStringAsFixed(limit.inSeconds % 60 == 0 ? 0 : 1)} min',
          fr: '${(limit.inSeconds / 60).toStringAsFixed(limit.inSeconds % 60 == 0 ? 0 : 1)} min',
          de: '${(limit.inSeconds / 60).toStringAsFixed(limit.inSeconds % 60 == 0 ? 0 : 1)} Min.',
          ja: '${(limit.inSeconds / 60).toStringAsFixed(limit.inSeconds % 60 == 0 ? 0 : 1)} 分',
        )
      : openHandAmbientText(
          zh: '${limit.inSeconds} 秒',
          zhHant: '${limit.inSeconds} 秒',
          en: '${limit.inSeconds} sec',
          fr: '${limit.inSeconds} s',
          de: '${limit.inSeconds} Sek.',
          ja: '${limit.inSeconds} 秒',
        );
  return AiTransportDiagnosticMessages.format(
    title: openHandAmbientText(
      zh: 'MCP 超时 [${server.name}]',
      zhHant: 'MCP 逾時 [${server.name}]',
      en: 'MCP timed out [${server.name}]',
      fr: 'MCP a expiré [${server.name}]',
      de: 'MCP-Zeitüberschreitung [${server.name}]',
      ja: 'MCP がタイムアウトしました [${server.name}]',
    ),
    reason: openHandAmbientText(
      zh:
          '$stageLabel 在 $humanLimit 内未完成。常见诱因：\n'
          '  · stdio 服务进程启动慢 (npx / uvx 首次 cold start 拉镜像 / 依赖，chrome-devtools-mcp 这类还会下载 Chrome Beta ≈250MB)\n'
          '  · HTTP / SSE 服务被网络层 (代理 / 防火墙) 拦在中途\n'
          '  · 服务自身内部死锁或在等待外部 API 响应\n'
          '  · 该机器 CPU / IO 极度繁忙',
      zhHant:
          '$stageLabel 在 $humanLimit 內未完成。常見原因：\n'
          '  · stdio 服務行程啟動慢 (npx / uvx 首次 cold start 拉映像 / 依賴，chrome-devtools-mcp 這類還會下載 Chrome Beta ≈250MB)\n'
          '  · HTTP / SSE 服務被網路層 (代理 / 防火牆) 中途攔截\n'
          '  · 服務內部死鎖或正在等待外部 API 回應\n'
          '  · 此機器 CPU / IO 極度繁忙',
      en:
          '$stageLabel did not finish within $humanLimit. Common causes:\n'
          '  · The stdio service starts slowly (npx / uvx first cold start may fetch images / dependencies; chrome-devtools-mcp may also download Chrome Beta ≈250MB)\n'
          '  · An HTTP / SSE service is blocked by the network layer (proxy / firewall)\n'
          '  · The service is deadlocked internally or waiting for an external API\n'
          '  · This machine is under heavy CPU / IO load',
      fr:
          '$stageLabel ne s’est pas terminé en $humanLimit. Causes fréquentes :\n'
          '  · Le service stdio démarre lentement (npx / uvx au premier cold start peut récupérer images / dépendances ; chrome-devtools-mcp peut aussi télécharger Chrome Beta ≈250 Mo)\n'
          '  · Un service HTTP / SSE est bloqué par le réseau (proxy / pare-feu)\n'
          '  · Le service est bloqué en interne ou attend une API externe\n'
          '  · La machine est très chargée en CPU / IO',
      de:
          '$stageLabel wurde nicht innerhalb von $humanLimit abgeschlossen. Häufige Ursachen:\n'
          '  · Der stdio-Dienst startet langsam (npx / uvx kann beim ersten Cold Start Images / Abhängigkeiten laden; chrome-devtools-mcp lädt ggf. Chrome Beta ≈250 MB)\n'
          '  · Ein HTTP / SSE-Dienst wird durch Netzwerk, Proxy oder Firewall blockiert\n'
          '  · Der Dienst hängt intern oder wartet auf eine externe API\n'
          '  · Diese Maschine ist stark durch CPU / IO belastet',
      ja:
          '$stageLabel が $humanLimit 以内に完了しませんでした。よくある原因:\n'
          '  · stdio サービスの起動が遅い (npx / uvx の初回 cold start でイメージ / 依存関係を取得し、chrome-devtools-mcp は Chrome Beta ≈250MB をダウンロードする場合があります)\n'
          '  · HTTP / SSE サービスがネットワーク層 (プロキシ / ファイアウォール) でブロックされている\n'
          '  · サービス内部でデッドロックしている、または外部 API を待っている\n'
          '  · このマシンの CPU / IO 負荷が非常に高い',
    ),
    try_: openHandAmbientText(
      zh:
          '· 在终端单独跑一遍 server.command 看下载是否走得通 (网络/代理/镜像源)\n'
          '· 已把 stdio 缓存隔离到 ~/.openhand/mcp/package-cache，可手动 rm -rf 重置\n'
          '· 首启过后命中缓存即恢复秒级，故失败可直接重试\n'
          '· 必要时给 npm/uv 配镜像源 (例：~/.npmrc -> registry=$_kNpmMirrorRegistry)',
      zhHant:
          '· 在終端單獨執行 server.command，確認下載是否可行 (網路/代理/映像源)\n'
          '· stdio 快取已隔離到 ~/.openhand/mcp/package-cache，可手動 rm -rf 重置\n'
          '· 首次啟動後命中快取即可恢復秒級，失敗時可直接重試\n'
          '· 必要時為 npm/uv 設定映像源 (例：~/.npmrc -> registry=$_kNpmMirrorRegistry)',
      en:
          '· Run server.command directly in a terminal to verify downloads (network / proxy / mirror)\n'
          '· stdio cache is isolated at ~/.openhand/mcp/package-cache and can be reset with rm -rf\n'
          '· After the first successful launch, cache hits should return to seconds; retrying is fine\n'
          '· Configure npm/uv mirrors if needed, for example ~/.npmrc -> registry=$_kNpmMirrorRegistry',
      fr:
          '· Exécutez server.command dans un terminal pour vérifier les téléchargements (réseau / proxy / miroir)\n'
          '· Le cache stdio est isolé dans ~/.openhand/mcp/package-cache et peut être réinitialisé avec rm -rf\n'
          '· Après le premier lancement réussi, le cache ramène le délai à quelques secondes ; vous pouvez réessayer\n'
          '· Configurez des miroirs npm/uv si nécessaire, par exemple ~/.npmrc -> registry=$_kNpmMirrorRegistry',
      de:
          '· Führe server.command im Terminal aus, um Downloads zu prüfen (Netzwerk / Proxy / Mirror)\n'
          '· Der stdio-Cache liegt isoliert unter ~/.openhand/mcp/package-cache und kann mit rm -rf zurückgesetzt werden\n'
          '· Nach dem ersten erfolgreichen Start sollten Cache-Treffer wieder Sekunden dauern; erneutes Versuchen ist ok\n'
          '· Konfiguriere bei Bedarf npm/uv-Mirrors, z. B. ~/.npmrc -> registry=$_kNpmMirrorRegistry',
      ja:
          '· ターミナルで server.command を直接実行し、ダウンロード可否を確認してください (ネットワーク / プロキシ / ミラー)\n'
          '· stdio キャッシュは ~/.openhand/mcp/package-cache に分離されており、rm -rf でリセットできます\n'
          '· 初回成功後はキャッシュにより秒単位に戻るため、失敗時はそのまま再試行できます\n'
          '· 必要なら npm/uv のミラーを設定してください。例: ~/.npmrc -> registry=$_kNpmMirrorRegistry',
    ),
    raw: label,
  );
}

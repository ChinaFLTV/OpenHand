import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../../app/model/app_info.dart';
import '../../../app/state/settings_controller.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../ai/ai_session_controller.dart';
import '../../ai/model/ai_creation_mode.dart';
import '../../ai/model/ai_model_config.dart';
import '../../ai/model/ai_session.dart';
import '../../ai/model/ai_session_message.dart';
import '../../ai/model/ai_session_runtime_context.dart';
import '../../ai/model/ai_thread_template.dart';
import '../../instructions/instructions_controller.dart';
import '../../mcp/mcp_controller.dart';
import '../../mcp/model/mcp_tool.dart';
import '../../memory/memory_controller.dart';
import '../../skills/skills_controller.dart';
import '../model/web_gateway_runtime.dart';
import '../model/web_gateway_session_metadata.dart';
import '../model/web_message_platform_config.dart';
import 'web_gateway_accessible_urls.dart';
import 'web_message_platform_legacy_client_html.dart';

// 公共类型已抽到 model/web_gateway_runtime.dart，re-export 让 view 现有 import 继续生效。
export '../model/web_gateway_runtime.dart';
export '../model/web_gateway_session_metadata.dart';

// 内部子系统 — 通过 part 共享同一 library，保持私有 API 表面不变。
part 'web_message_platform_service_logger.part.dart';
part 'web_message_platform_service_auth.part.dart';
part 'web_message_platform_service_telemetry.part.dart';

class WebMessagePlatformService {
  WebMessagePlatformService({
    required AiSessionController sessionController,
    required SettingsController settingsController,
    required SkillsController skillsController,
    required McpController mcpController,
    required MemoryController memoryController,
    required InstructionsController instructionsController,
    required AppInfo appInfo,
    String? cacheDirectoryPath,
    String? logsDirectoryPath,
    String? workspaceDirectoryPath,
  }) : _sessionController = sessionController,
       _settingsController = settingsController,
       _skillsController = skillsController,
       _mcpController = mcpController,
       _memoryController = memoryController,
       _instructionsController = instructionsController,
       _appInfo = appInfo,
       _cacheDirectoryPath =
           cacheDirectoryPath ?? OpenHandPaths.defaultCacheDirectoryPath(),
       _workspaceDirectoryPath =
           workspaceDirectoryPath ?? OpenHandPaths.applicationDirectoryPath(),
       _fileLogger = _WebGatewayRotatingLogger(
         logsDirectoryPath: logsDirectoryPath,
       );

  final AiSessionController _sessionController;
  final SettingsController _settingsController;
  final SkillsController _skillsController;
  final McpController _mcpController;
  final MemoryController _memoryController;
  final InstructionsController _instructionsController;
  final AppInfo _appInfo;
  final String _cacheDirectoryPath;
  final String _workspaceDirectoryPath;
  final _WebGatewayRotatingLogger _fileLogger;
  final StreamController<WebGatewayLogEntry> _logStreamController =
      StreamController<WebGatewayLogEntry>.broadcast();
  final List<WebGatewayLogEntry> _memoryLogs = <WebGatewayLogEntry>[];
  final List<WebGatewayCleanupResult> _cleanupHistory =
      <WebGatewayCleanupResult>[];
  final Map<String, _WebGatewayAuthSession> _authSessions =
      <String, _WebGatewayAuthSession>{};

  HttpServer? _server;
  WebGatewayRuntimeState _state = WebGatewayRuntimeState.stopped;
  WebMessagePlatformConfig _config = const WebMessagePlatformConfig();
  WebGatewayThemeSnapshot _theme = const WebGatewayThemeSnapshot();
  DateTime? _startedAt;
  int _activeRequests = 0;
  int _totalRequests = 0;
  int _totalErrors = 0;
  int _totalBytesIn = 0;
  int _totalBytesOut = 0;
  int _crashCount = 0;
  int _restartCount = 0;
  int _nextLogId = 1;
  String _lastError = '';
  _ProcessDiagnostics _processDiagnostics = const _ProcessDiagnostics();
  DateTime? _processDiagnosticsAt;
  _LinuxCpuSample? _previousLinuxCpuSample;

  /// 缓存当前主机非环回 IPv4 地址列表，作为 `accessibleUrls` 在
  /// 监听 `0.0.0.0` / `::` 时枚举局域网 URL 的数据源。`start()` 后填充，
  /// `runtimeSnapshotAsync()` 触发时按 30s TTL 刷新。
  List<String> _localAddressesCache = const <String>[];
  DateTime? _localAddressesAt;

  Stream<WebGatewayLogEntry> get logStream => _logStreamController.stream;
  List<WebGatewayLogEntry> get logs =>
      List<WebGatewayLogEntry>.unmodifiable(_memoryLogs);
  List<WebGatewayCleanupResult> get cleanupHistory =>
      List<WebGatewayCleanupResult>.unmodifiable(_cleanupHistory);
  WebGatewayRuntimeState get state => _state;
  bool get isRunning =>
      _server != null && _state == WebGatewayRuntimeState.running;
  String get boundUrl => _server == null
      ? ''
      : 'http://${_displayHost(_config.listenHost)}:${_server!.port}';

  /// 当前可访问该 Web 服务的全部 URL：
  /// - 监听具体 IP（如 `192.168.1.5`）→ 仅返回 `[boundUrl]`
  /// - 监听通配符 (`0.0.0.0` / `::` / 空串) → 返回 `localhost` + `127.0.0.1`
  ///   + 所有非环回 IPv4 地址。`_localAddressesCache` 由 `_refreshLocalAddresses`
  ///   异步填充；服务未启动时返回空列表。
  List<String> get accessibleUrls => computeWebGatewayAccessibleUrls(
        listenHost: _config.listenHost,
        boundPort: _server?.port,
        localIPv4Addresses: _localAddressesCache,
      );

  void updateTheme(WebGatewayThemeSnapshot theme) {
    _theme = theme;
  }

  Future<void> start(WebMessagePlatformConfig config) async {
    _config = config;
    if (_server != null) {
      await stop();
    }
    if (!config.enabled) {
      _state = WebGatewayRuntimeState.stopped;
      return;
    }
    _state = WebGatewayRuntimeState.starting;
    _log(WebGatewayLogLevel.info, 'BOOT', '正在启动 Web 通用消息平台', <String, Object?>{
      'host': config.listenHost,
      'port': config.listenPort,
    });
    try {
      final address = _bindAddress(config.listenHost);
      final pipeline = const shelf.Pipeline()
          .addMiddleware(_corsMiddleware())
          .addMiddleware(_telemetryAndLimitMiddleware());
      final handler = pipeline.addHandler(_buildRouter().call);
      final server = await shelf_io.serve(
        handler,
        address,
        config.listenPort,
        shared: true,
      );
      server.serverHeader = 'OpenHand-WebGateway/1.0';
      _server = server;
      _startedAt = DateTime.now().toUtc();
      _state = WebGatewayRuntimeState.running;
      // 启动后立刻探测一次主机 IP 列表，使 BOOT 日志可同时打出 LAN URL；
      // NetworkInterface.list 内部毫秒级，且失败仅 silentLog，不阻塞 boot。
      await _refreshLocalAddressesIfStale(ttl: Duration.zero);
      final urls = accessibleUrls;
      final logSummary = urls.length <= 1
          ? boundUrl
          : '$boundUrl  (LAN: ${urls.where((u) => u != boundUrl).join(", ")})';
      _log(
        WebGatewayLogLevel.success,
        'BOOT',
        'Web 服务已监听 $logSummary',
        <String, Object?>{
          'bound_url': boundUrl,
          'accessible_urls': urls,
        },
      );
      // 启动后顺手做一次过期清理；失败不应阻塞 boot 流程，但要走 silentLog
      // 防止 Future error 被 unawaited 静默吞掉。
      unawaited(() async {
        try {
          await cleanupArtifacts(
            logs: true,
            uploads: true,
            expiredOnly: true,
          );
        } catch (error, stack) {
          silentLog(
            'web_message_platform_service',
            'start cleanupArtifacts',
            error,
            stack,
          );
        }
      }());
    } catch (error, stack) {
      _state = WebGatewayRuntimeState.crashed;
      _crashCount++;
      _lastError = '$error';
      _log(WebGatewayLogLevel.error, 'BOOT', 'Web 服务启动失败: $error');
      silentLog('web_message_platform_service', 'start', error, stack);
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) {
      _state = WebGatewayRuntimeState.stopped;
      return;
    }
    _state = WebGatewayRuntimeState.stopping;
    _log(WebGatewayLogLevel.warn, 'OPS', '正在停止 Web 服务');
    _server = null;
    try {
      await server.close(force: true);
      _state = WebGatewayRuntimeState.stopped;
      _startedAt = null;
      _authSessions.clear();
      _log(WebGatewayLogLevel.success, 'OPS', 'Web 服务已停止');
    } catch (error, stack) {
      _state = WebGatewayRuntimeState.crashed;
      _crashCount++;
      _lastError = '$error';
      _log(WebGatewayLogLevel.error, 'OPS', '停止 Web 服务失败: $error');
      silentLog('web_message_platform_service', 'stop', error, stack);
    }
  }

  Future<void> restart(WebMessagePlatformConfig config) async {
    _restartCount++;
    await stop();
    await start(config);
  }

  Future<void> reloadConfig(WebMessagePlatformConfig config) async {
    final needsRestart =
        config.enabled != _config.enabled ||
        config.listenHost != _config.listenHost ||
        config.listenPort != _config.listenPort;
    _config = config;
    _log(WebGatewayLogLevel.info, 'OPS', '配置已重新加载');
    if (needsRestart) {
      await restart(config);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _logStreamController.close();
  }

  WebGatewayRuntimeSnapshot runtimeSnapshot() {
    final startedAt = _startedAt;
    final uptimeMs = startedAt == null
        ? 0
        : DateTime.now().toUtc().difference(startedAt).inMilliseconds;
    return WebGatewayRuntimeSnapshot(
      state: _state,
      startedAt: startedAt,
      uptimeMs: uptimeMs,
      boundUrl: boundUrl,
      accessibleUrls: accessibleUrls,
      activeRequests: _activeRequests,
      totalRequests: _totalRequests,
      totalErrors: _totalErrors,
      totalBytesIn: _totalBytesIn,
      totalBytesOut: _totalBytesOut,
      crashCount: _crashCount,
      restartCount: _restartCount,
      currentRssBytes: ProcessInfo.currentRss,
      maxRssBytes: ProcessInfo.maxRss,
      cpuPercent: _processDiagnostics.cpuPercent,
      threadCount: _processDiagnostics.threadCount,
      fileHandleCount: _processDiagnostics.fileHandleCount,
      swapBytes: _processDiagnostics.swapBytes,
      logBytes: _fileLogger.currentSizeBytes,
      openSessionCount: _sessionController.sessions.length,
      lastError: _lastError,
    );
  }

  Future<WebGatewayRuntimeSnapshot> runtimeSnapshotAsync() async {
    await _refreshProcessDiagnosticsIfStale();
    await _refreshLocalAddressesIfStale();
    return runtimeSnapshot();
  }

  /// 刷新主机非环回 IPv4 地址列表，30 s TTL。失败不抛，仅 silentLog——
  /// 缓存保持上一次结果（启动期为空列表，UI 仍能显示 localhost/127.0.0.1）。
  Future<void> _refreshLocalAddressesIfStale({Duration ttl = const Duration(seconds: 30)}) async {
    final stamp = _localAddressesAt;
    if (stamp != null && DateTime.now().toUtc().difference(stamp) < ttl) {
      return;
    }
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final addrs = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final value = addr.address.trim();
          if (value.isNotEmpty) addrs.add(value);
        }
      }
      _localAddressesCache = List<String>.unmodifiable(addrs);
      _localAddressesAt = DateTime.now().toUtc();
    } catch (error, stack) {
      silentLog(
        'web_message_platform_service',
        'refresh local addresses',
        error,
        stack,
      );
    }
  }

  Future<WebGatewayHealthResult> runHealthCheck() async {
    if (_server == null) {
      return const WebGatewayHealthResult(
        ok: false,
        statusCode: 0,
        durationMs: 0,
        summary: 'Web 服务未运行',
      );
    }
    final health = _config.healthCheck;
    final query = <String, String>{...health.queryParameters};
    final uri = Uri(
      scheme: 'http',
      host: _displayHost(_config.listenHost),
      port: _server!.port,
      path: health.path.startsWith('/') ? health.path : '/${health.path}',
      queryParameters: query.isEmpty ? null : query,
    );
    final stopwatch = Stopwatch()..start();
    final client = HttpClient()
      ..connectionTimeout = Duration(milliseconds: health.timeoutMs);
    try {
      final request = await client
          .openUrl(health.method, uri)
          .timeout(Duration(milliseconds: health.timeoutMs));
      request.followRedirects = health.followRedirects;
      final response = await request.close().timeout(
        Duration(milliseconds: health.timeoutMs),
      );
      final body = await utf8
          .decodeStream(response)
          .timeout(Duration(milliseconds: health.timeoutMs));
      stopwatch.stop();
      final containsOk =
          health.responseContains.trim().isEmpty ||
          body.contains(health.responseContains.trim());
      final ok = response.statusCode == health.expectedStatusCode && containsOk;
      final result = WebGatewayHealthResult(
        ok: ok,
        statusCode: response.statusCode,
        durationMs: stopwatch.elapsedMilliseconds,
        summary: ok ? '健康检查通过' : '健康检查未满足断言',
        bodyPreview: _truncate(body, 600),
      );
      _log(
        ok ? WebGatewayLogLevel.success : WebGatewayLogLevel.warn,
        'HEALTH',
        result.summary,
        result.toJson(),
      );
      return result;
    } catch (error, stack) {
      stopwatch.stop();
      silentLog('web_message_platform_service', 'health check', error, stack);
      final result = WebGatewayHealthResult(
        ok: false,
        statusCode: 0,
        durationMs: stopwatch.elapsedMilliseconds,
        summary: '健康检查失败: $error',
      );
      _log(WebGatewayLogLevel.error, 'HEALTH', result.summary);
      return result;
    } finally {
      client.close(force: true);
    }
  }

  Future<WebGatewayCleanupResult> cleanupArtifacts({
    required bool logs,
    required bool uploads,
    bool expiredOnly = false,
  }) async {
    var stats = const _CleanupStats();
    var memoryLogEntriesCleared = 0;
    if (logs) {
      if (expiredOnly) {
        stats += await _fileLogger.prune(_config.logConfig);
      } else {
        memoryLogEntriesCleared = _memoryLogs.length;
        _memoryLogs.clear();
        stats += await _fileLogger.clear();
      }
    }
    if (uploads) {
      stats += await _cleanupUploadCache(expiredOnly: expiredOnly);
    }
    final target = logs && uploads
        ? 'all'
        : logs
        ? 'logs'
        : uploads
        ? 'uploads'
        : 'none';
    final result = WebGatewayCleanupResult(
      timestamp: DateTime.now().toUtc(),
      target: target,
      expiredOnly: expiredOnly,
      deletedFiles: stats.deletedFiles,
      deletedDirectories: stats.deletedDirectories,
      bytesFreed: stats.bytesFreed,
      memoryLogEntriesCleared: memoryLogEntriesCleared,
    );
    if (target != 'none') {
      _cleanupHistory.add(result);
      if (_cleanupHistory.length > 50) {
        _cleanupHistory.removeRange(0, _cleanupHistory.length - 50);
      }
      _log(
        WebGatewayLogLevel.warn,
        'CLEANUP',
        expiredOnly ? '已执行过期资源清理' : '已执行资源清理',
        result.toJson(),
      );
    }
    return result;
  }

  Future<String> exportLogBundleJson() async {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(await _logBundlePayload());
  }

  Future<String> exportCurrentLogText() async {
    final currentFileText = await _fileLogger.readCurrentLogText();
    if (currentFileText.trim().isNotEmpty) {
      return currentFileText;
    }
    return _memoryLogs.map((entry) => entry.toLogLine()).join('\n');
  }

  /// shelf 路由表。所有 handler 经过：
  /// `_corsMiddleware` → `_telemetryAndLimitMiddleware` → router。
  ///
  /// 匿名公开路由（不走鉴权）：`GET /`、`GET /login`、`GET /thread`、
  /// `GET /api/health`、`GET /api/meta`、`POST /api/login`。
  /// 其余全部经 `_withAuth` 包装：未鉴权返回 401，鉴权后注入
  /// `_WebGatewayAuthSession` 给 handler。
  Router _buildRouter() {
    final router = Router(notFoundHandler: _shelfNotFound);
    // SPA shell：优先返回 clients/web 构建产物（assets/web/index.html），缺失
    // 时 fallback 到 legacy 内嵌模板，保证未跑过 build_web.sh 的环境也可访问。
    router.get('/', (shelf.Request _) => _serveWebShell());
    router.get('/login', (shelf.Request _) => _serveWebShell());
    router.get('/thread', (shelf.Request _) => _serveWebShell());
    router.get('/threads', (shelf.Request _) => _serveWebShell());
    // SPA 深路由：/threads/<id> 直接刷新或粘贴打开都能命中前端 Router。
    router.get('/threads/<rest|.+>', (shelf.Request _, String rest) => _serveWebShell());
    // Vite 产物里 index.html 引用 app.js / app.css 同级文件，直接出 bundle。
    router.get('/app.js', (shelf.Request _) =>
        _serveBundleAsset('assets/web/app.js', 'application/javascript; charset=utf-8'));
    router.get('/app.css', (shelf.Request _) =>
        _serveBundleAsset('assets/web/app.css', 'text/css; charset=utf-8'));
    // 通配子路径覆盖 chunks/*.js 与 assets/*.{png,svg,woff2,...}。
    router.get('/chunks/<path|.+>', (shelf.Request _, String path) =>
        _serveBundleAsset('assets/web/chunks/$path', _guessContentType(path)));
    router.get('/assets/<path|.+>', (shelf.Request _, String path) =>
        _serveBundleAsset('assets/web/assets/$path', _guessContentType(path)));
    router.get('/api/health', _apiHealth);
    router.get('/api/meta', _apiMeta);
    router.post('/api/login', _login);

    router.get('/api/sessions', (shelf.Request r) => _withAuth(r, _listSessions));
    router.post('/api/sessions', (shelf.Request r) => _withAuth(r, _createSession));
    router.get('/api/sessions/<sessionId>', (shelf.Request r, String sessionId) =>
        _withAuth(r, (req, auth) => _getSession(req, auth, sessionId)));
    router.patch('/api/sessions/<sessionId>', (shelf.Request r, String sessionId) =>
        _withAuth(r, (req, auth) => _renameSession(req, auth, sessionId)));
    router.delete('/api/sessions/<sessionId>', (shelf.Request r, String sessionId) =>
        _withAuth(r, (req, auth) => _deleteSession(req, auth, sessionId)));
    router.get('/api/sessions/<sessionId>/messages', (shelf.Request r, String sessionId) =>
        _withAuth(r, (req, auth) => _listMessages(req, auth, sessionId)));
    router.post('/api/sessions/<sessionId>/messages', (shelf.Request r, String sessionId) =>
        _withAuth(r, (req, auth) => _sendMessage(req, auth, sessionId)));
    router.post('/api/sessions/<sessionId>/stop', (shelf.Request r, String sessionId) =>
        _withAuth(r, (req, auth) => _stopSendMessage(req, auth, sessionId)));

    router.get('/api/ops', (shelf.Request r) => _withAuth(r, (_, _) => _opsSnapshot()));
    router.get('/api/ops/cleanup/history', (shelf.Request r) => _withAuth(r, (_, _) => _cleanupHistoryPayload()));
    router.post('/api/ops/cleanup', (shelf.Request r) => _withAuth(r, (req, _) => _cleanupOps(req)));
    router.get('/api/logs', (shelf.Request r) => _withAuth(r, (req, _) => _listLogs(req)));
    router.get('/api/logs/export', (shelf.Request r) => _withAuth(r, (_, _) => _exportLogs()));
    router.get('/api/workspace/files', (shelf.Request r) => _withAuth(r, (req, _) => _listWorkspaceFiles(req)));
    router.get('/api/workspace/file', (shelf.Request r) => _withAuth(r, (req, _) => _readWorkspaceFile(req)));
    router.put('/api/workspace/file', (shelf.Request r) => _withAuth(r, (req, _) => _writeWorkspaceFile(req)));

    return router;
  }

  shelf.Response _shelfNotFound(shelf.Request request) =>
      _json(HttpStatus.notFound, <String, Object?>{'error': 'not_found'});

  /// CORS 头 + OPTIONS 预检统一处理。
  shelf.Middleware _corsMiddleware() {
    const corsHeaders = <String, String>{
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
      'access-control-allow-headers':
          'authorization,content-type,x-openhand-device-id,x-openhand-source,x-openhand-device-mac,x-openhand-device-name,x-openhand-device-platform',
    };
    return (innerHandler) {
      return (shelf.Request request) async {
        if (request.method == 'OPTIONS') {
          return shelf.Response(HttpStatus.noContent, headers: corsHeaders);
        }
        final response = await innerHandler(request);
        return response.change(headers: corsHeaders);
      };
    };
  }

  /// 并发限流 + 请求/字节计数 + 异常兜底 + 访问日志。
  /// 与旧 `_handleRequest` 的副作用一一对应：超过 `maxConcurrentRequests`
  /// 直接返回 429，否则在 finally 写访问日志，按状态码挑选 level。
  shelf.Middleware _telemetryAndLimitMiddleware() {
    return (innerHandler) {
      return (shelf.Request request) async {
        _totalRequests++;
        final requestBytes = request.contentLength ?? 0;
        _totalBytesIn += requestBytes;
        if (_activeRequests >= _config.maxConcurrentRequests) {
          _totalErrors++;
          _log(
            WebGatewayLogLevel.warn,
            'HTTP',
            '请求被并发限制拒绝',
            <String, Object?>{
              'path': request.requestedUri.path,
              'active_requests': _activeRequests,
              'limit': _config.maxConcurrentRequests,
            },
          );
          return _json(
            HttpStatus.tooManyRequests,
            const <String, Object?>{'error': 'too_many_requests'},
          );
        }
        _activeRequests++;
        final stopwatch = Stopwatch()..start();
        var statusCode = 0;
        var responseBytes = 0;
        String? errorText;
        try {
          final response = await innerHandler(request);
          statusCode = response.statusCode;
          responseBytes = response.contentLength ?? 0;
          return response;
        } catch (error, stack) {
          statusCode = HttpStatus.internalServerError;
          errorText = '$error';
          _totalErrors++;
          _lastError = errorText;
          silentLog(
            'web_message_platform_service',
            'handle request',
            error,
            stack,
          );
          final fallback = _json(
            HttpStatus.internalServerError,
            <String, Object?>{
              'error': 'internal_error',
              'message': errorText,
            },
          );
          responseBytes = fallback.contentLength ?? 0;
          return fallback;
        } finally {
          _activeRequests = math.max(0, _activeRequests - 1);
          stopwatch.stop();
          _totalBytesOut += responseBytes;
          final connectionInfo = request.context['shelf.io.connection_info']
              as HttpConnectionInfo?;
          final level = statusCode >= 500
              ? WebGatewayLogLevel.error
              : statusCode >= 400
                  ? WebGatewayLogLevel.warn
                  : (_config.telemetryEnabled
                      ? WebGatewayLogLevel.telemetry
                      : WebGatewayLogLevel.info);
          final shouldLog = _config.loggingEnabled ||
              _config.telemetryEnabled ||
              statusCode >= 400;
          if (shouldLog) {
            _log(
              level,
              'HTTP',
              '${request.method} ${request.requestedUri.path} -> $statusCode ${stopwatch.elapsedMilliseconds}ms',
              <String, Object?>{
                'method': request.method,
                'path': request.requestedUri.path,
                'query': request.requestedUri.queryParameters,
                'status_code': statusCode,
                'duration_ms': stopwatch.elapsedMilliseconds,
                'remote_ip': connectionInfo?.remoteAddress.address,
                'remote_port': connectionInfo?.remotePort,
                'user_agent': request.headers[HttpHeaders.userAgentHeader],
                'content_length': requestBytes,
                'response_bytes': responseBytes,
                'active_requests': _activeRequests,
                if (errorText != null) 'error': errorText,
              },
            );
          }
        }
      };
    };
  }

  /// 把 handler 包成「先鉴权后调用」的入口；401 时返回 JSON 错误。
  Future<shelf.Response> _withAuth(
    shelf.Request request,
    Future<shelf.Response> Function(shelf.Request, _WebGatewayAuthSession) handler,
  ) async {
    final auth = _authorize(request);
    if (auth == null) {
      return _json(HttpStatus.unauthorized, <String, Object?>{
        'error': 'unauthorized',
      });
    }
    return handler(request, auth);
  }

  shelf.Response _apiHealth(shelf.Request request) {
    return _json(HttpStatus.ok, <String, Object?>{
      'status': 'ok',
      'service': webMessagePlatformBuiltinName,
      'state': _state.name,
      'time': DateTime.now().toUtc().toIso8601String(),
    });
  }

  shelf.Response _apiMeta(shelf.Request request) {
    return _json(HttpStatus.ok, _metaPayload());
  }

  Future<shelf.Response> _opsSnapshot() async {
    if (!_config.opsEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'ops_disabled',
      });
    }
    return _json(HttpStatus.ok, (await runtimeSnapshotAsync()).toJson());
  }

  Map<String, Object?> _metaPayload() {
    return <String, Object?>{
      'service': <String, Object?>{
        'id': webMessagePlatformBuiltinId,
        'name': webMessagePlatformBuiltinName,
        'description': _config.description,
        'bound_url': boundUrl,
        'accessible_urls': accessibleUrls,
        'auth_enabled': _config.authEnabled,
        'telemetry_enabled': _config.telemetryEnabled,
        'logging_enabled': _config.loggingEnabled,
        'ops_enabled': _config.opsEnabled,
        'plan_mode_enabled': _config.planModeEnabled,
        'session_management_enabled': _config.sessionManagementEnabled,
        'single_message_token_limit': _config.singleMessageTokenLimit,
        'max_messages_per_session': _config.maxMessagesPerSession,
      },
      'workspace_files': <String, Object?>{
        'enabled': _config.workspaceFilesEnabled,
        'write_enabled': _config.workspaceFileWriteEnabled,
        'max_file_bytes': _config.workspaceFileMaxBytes,
        'allowed_extensions': _config.workspaceFileAllowedExtensions,
      },
      'theme': _theme.toJson(),
      'templates': _allowedTemplates()
          .map(
            (template) => <String, Object?>{
              'id': template.id,
              'name': template.name,
              'description': template.description,
              'icon': template.iconName,
            },
          )
          .toList(growable: false),
      'conversation_modes': _config.allowedConversationModes
          .map((item) => item.storageValue)
          .toList(growable: false),
      'message_types': _config.allowedMessageTypes
          .map((item) => item.storageValue)
          .toList(growable: false),
      'models': _allowedModels()
          .map(
            (item) => <String, Object?>{
              'key': item.key,
              'provider_id': item.providerId,
              'provider': item.providerLabel,
              'model_id': item.modelId,
              'label': item.label,
            },
          )
          .toList(growable: false),
    };
  }

  Future<shelf.Response> _login(shelf.Request request) async {
    final body = await _readJsonBody(request);
    final source = WebGatewayLoginSource.fromStorage(
      _string(body['source'], 'WEB_PC'),
    );
    final deviceId = _string(body['device_id'], '').trim();
    if (deviceId.isEmpty) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'device_id_required',
      });
    }
    if (_config.authEnabled) {
      final username = _string(body['username'], '').trim();
      final password = _string(body['password'], '');
      if (username != _config.username || password != _config.password) {
        _log(WebGatewayLogLevel.warn, 'AUTH', '登录失败', <String, Object?>{
          'username': username,
          'device_id': deviceId,
          'remote_ip': (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress.address,
        });
        return _json(HttpStatus.unauthorized, <String, Object?>{
          'error': 'invalid_credentials',
        });
      }
    }
    final token = _makeToken();
    final session = _WebGatewayAuthSession(
      token: token,
      source: source,
      deviceId: deviceId,
      deviceMacAddress: _string(body['device_mac_address'], ''),
      deviceName: _string(body['device_name'], ''),
      devicePlatform: _string(body['device_platform'], ''),
      loginAt: DateTime.now().toUtc(),
      remoteAddress: (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress.address ?? '',
      userAgent: request.headers[HttpHeaders.userAgentHeader] ?? '',
    );
    _authSessions[token] = session;
    _log(WebGatewayLogLevel.success, 'AUTH', '登录成功', session.toMetadata());
    return _json(HttpStatus.ok, <String, Object?>{
      'token': token,
      'expires_in': null,
      'profile': session.toMetadata(),
    });
  }

  Future<shelf.Response> _listSessions(
    shelf.Request request,
    _WebGatewayAuthSession auth,
  ) async {
    final page = math.max(
      1,
      int.tryParse(request.requestedUri.queryParameters['page'] ?? '') ?? 1,
    );
    final pageSize = math.min(
      50,
      math.max(
        1,
        int.tryParse(request.requestedUri.queryParameters['page_size'] ?? '') ?? 10,
      ),
    );
    final canAccessAll = _authCanAccessAllSessions(auth);
    final sourceQuery = request.requestedUri.queryParameters['source']?.trim() ?? '';
    final deviceQuery = request.requestedUri.queryParameters['device_id']?.trim() ?? '';
    final source = canAccessAll
        ? sourceQuery
        : (sourceQuery.isEmpty ? auth.source.storageValue : sourceQuery);
    final deviceId = canAccessAll
        ? deviceQuery
        : (deviceQuery.isEmpty ? auth.deviceId : deviceQuery);
    final filtered =
        _sessionController.sessions
            .where((session) {
              final context = _webContext(session.metadata);
              if (source.isNotEmpty &&
                  _string(context['login_source'], '') != source) {
                return false;
              }
              if (deviceId.isNotEmpty &&
                  _string(context['device_id'], '') != deviceId) {
                return false;
              }
              return true;
            })
            .toList(growable: false)
          ..sort((a, b) {
            final updated = b.updatedAt.compareTo(a.updatedAt);
            return updated != 0 ? updated : b.id.compareTo(a.id);
          });
    final start = (page - 1) * pageSize;
    final end = math.min(filtered.length, start + pageSize);
    final items = start >= filtered.length
        ? const <Map<String, Object?>>[]
        : filtered
              .sublist(start, end)
              .map(_sessionSummary)
              .toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{
      'items': items,
      'page': page,
      'page_size': pageSize,
      'total': filtered.length,
      'has_more': end < filtered.length,
      'sort': 'updated_at_desc,id_desc',
      'scope': canAccessAll ? 'authenticated_all' : 'current_device',
    });
  }

  Future<shelf.Response> _createSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
  ) async {
    final body = await _readJsonBody(request);
    final templateId = _string(body['template_id'], 'default').trim();
    if (!_templateAllowed(templateId)) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'template_not_allowed',
      });
    }
    final requestedMode = _string(body['mode'], 'chat').trim();
    final mode = requestedMode == 'plan' && _config.planModeEnabled
        ? AiSessionMode.plan
        : AiSessionMode.chat;
    final metadata = _metadataForRequest(auth, request, <String, Object?>{
      'created_via': 'web_api',
      'requested_template_id': templateId,
      'requested_mode': mode.storageValue,
    });
    final ok = await _sessionController.createSession(
      templateId: templateId,
      runtimeContext: _buildRuntimeContext(templateId: templateId),
      mode: mode,
      metadata: metadata,
    );
    if (!ok || _sessionController.currentSession == null) {
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'create_failed',
      });
    }
    var session = _sessionController.currentSession!;
    final title = _string(body['title'], '').trim();
    if (title.isNotEmpty) {
      await _sessionController.renameSession(session.id, title);
      session = _sessionController.sessions.firstWhere(
        (item) => item.id == session.id,
        orElse: () => session,
      );
    }
    _log(
      WebGatewayLogLevel.success,
      'SESSION',
      'Web 新建会话 ${session.id}',
      <String, Object?>{
        'template_id': templateId,
        'mode': mode.storageValue,
        'device_id': auth.deviceId,
      },
    );
    return _json(HttpStatus.created, <String, Object?>{
      'session': _sessionSummary(session),
    });
  }

  Future<shelf.Response> _getSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    return _json(HttpStatus.ok, <String, Object?>{
      'session': _sessionSummary(session),
      'runtime': <String, Object?>{
        'send_phase': _sessionController.sendPhaseForSession(session.id).name,
        'can_stop': _sessionController.canStopResponding(session.id),
        'last_error': _sessionController.lastErrorMessageForSession(session.id),
      },
    });
  }

  Future<shelf.Response> _renameSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    if (!_config.sessionManagementEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'session_management_disabled',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final body = await _readJsonBody(request);
    final title = _string(body['title'], '').trim();
    if (title.isEmpty) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'title_required',
      });
    }
    final ok = await _sessionController.renameSession(session.id, title);
    final committed = _sessionController.sessions.firstWhere(
      (item) => item.id == session.id,
      orElse: () => session.copyWith(title: title),
    );
    final updated = ok ? committed.copyWith(title: title) : committed;
    _log(
      WebGatewayLogLevel.info,
      'SESSION',
      'Web 重命名会话 ${session.id}',
      <String, Object?>{'title': title, 'device_id': auth.deviceId},
    );
    return _json(ok ? HttpStatus.ok : HttpStatus.conflict,
      <String, Object?>{'ok': ok, 'session': _sessionSummary(updated)},
    );
  }

  Future<shelf.Response> _deleteSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    if (!_config.sessionManagementEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'session_management_disabled',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final ok = await _sessionController.deleteSession(session.id);
    _log(
      WebGatewayLogLevel.warn,
      'SESSION',
      'Web 删除会话 ${session.id}',
      <String, Object?>{'title': session.title, 'device_id': auth.deviceId},
    );
    return _json(ok ? HttpStatus.ok : HttpStatus.conflict,
      <String, Object?>{'ok': ok, 'deleted_session_id': session.id},
    );
  }

  Future<shelf.Response> _listMessages(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final limit = math.min(
      200,
      math.max(
        1,
        int.tryParse(request.requestedUri.queryParameters['limit'] ?? '') ?? 80,
      ),
    );
    final offset = math.max(
      0,
      int.tryParse(request.requestedUri.queryParameters['offset'] ?? '') ?? 0,
    );
    final page = await _sessionController.store.loadMessages(
      session.id,
      limit: limit,
      offset: offset,
    );
    return _json(HttpStatus.ok, <String, Object?>{
      'items': page.messages
          .where((message) => !message.isDeleted)
          .map(_messageJson)
          .toList(growable: false),
      'offset': offset,
      'limit': limit,
      'total': page.totalCount,
      'has_more': page.hasMore,
      'send_phase': _sessionController.sendPhaseForSession(session.id).name,
      'last_error': _sessionController.lastErrorMessageForSession(session.id),
    });
  }

  Future<shelf.Response> _sendMessage(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    if (session.displayMessages.length >= _config.maxMessagesPerSession) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'session_message_limit_reached',
      });
    }
    final body = await _readJsonBody(request, maxBytes: 24 * 1024 * 1024);
    final content = _string(body['content'], '').trim();
    final estimatedTokens = (content.length / 4).ceil();
    if (estimatedTokens > _config.singleMessageTokenLimit) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'message_too_large',
        'estimated_tokens': estimatedTokens,
        'limit': _config.singleMessageTokenLimit,
      });
    }
    final rawMode = _string(body['mode'], 'normal');
    final conversationMode =
        WebGatewayConversationMode.fromStorage(rawMode) ??
        WebGatewayConversationMode.normal;
    if (!_config.allowedConversationModes.contains(conversationMode)) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'conversation_mode_not_allowed',
      });
    }
    final attachments = await _materializeAttachments(
      session.id,
      body['attachments'],
    );
    if (attachments.isNotEmpty &&
        !_config.allowedMessageTypes.contains(
          WebGatewayMessageType.attachment,
        )) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'attachments_not_allowed',
      });
    }
    if (content.isNotEmpty &&
        !_config.allowedMessageTypes.contains(WebGatewayMessageType.text)) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'text_not_allowed',
      });
    }
    final model = _resolveModel(_string(body['model_key'], ''));
    if (model == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'model_not_configured',
      });
    }
    final creationRequest = _creationRequestFor(conversationMode);
    final responseModalities = switch (conversationMode) {
      WebGatewayConversationMode.image => const <String>['image'],
      WebGatewayConversationMode.video => const <String>['video'],
      WebGatewayConversationMode.audio => const <String>['audio'],
      _ => const <String>[],
    };
    final sent = await _sessionController.sendMessage(
      sessionId: session.id,
      content: content,
      model: model,
      runtimeContext: _buildRuntimeContext(templateId: session.templateId),
      attachmentFilePaths: attachments,
      responseModalities: responseModalities,
      creationRequest: creationRequest,
      denyCommandRules: _settingsController.aiDenyCommandRules,
      requireWriteCommandConfirmation: false,
      userMessageMetadata: _metadataForRequest(auth, request, <String, Object?>{
        'sent_via': 'web_api',
        'conversation_mode': conversationMode.storageValue,
        'model_key': _modelKey(model.id, model.modelId),
        'attachment_count': attachments.length,
      }),
    );
    if (!sent) {
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'send_failed',
        'message': _sessionController.lastErrorMessageForSession(session.id),
      });
    }
    _log(
      WebGatewayLogLevel.success,
      'MESSAGE',
      'Web 消息已送入会话 ${session.id}',
      <String, Object?>{
        'chars': content.length,
        'attachments': attachments.length,
        'mode': conversationMode.storageValue,
      },
    );
    return _json(HttpStatus.accepted, <String, Object?>{
      'ok': true,
      'send_phase': _sessionController.sendPhaseForSession(session.id).name,
    });
  }

  /// 主动中断当前会话的助手回复（对应桌面端「停止响应」按钮）。
  ///
  /// 返回值：
  /// - 200 {ok:true, send_phase:'idle'} 中断成功，下一轮 listMessages 会拿到 finalize 后的内容；
  /// - 200 {ok:false, send_phase:<当前>} 当前会话无可中断的回复（idle 等）；
  /// - 404 会话不存在或当前 token 无权访问。
  Future<shelf.Response> _stopSendMessage(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    if (!_sessionController.canStopResponding(session.id)) {
      return _json(HttpStatus.ok, <String, Object?>{
        'ok': false,
        'send_phase': _sessionController.sendPhaseForSession(session.id).name,
        'reason': 'not_running',
      });
    }
    await _sessionController.stopResponding(session.id);
    _log(
      WebGatewayLogLevel.warn,
      'MESSAGE',
      'Web 主动中断会话 ${session.id} 的助手回复',
      <String, Object?>{'device_id': auth.deviceId},
    );
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'send_phase': _sessionController.sendPhaseForSession(session.id).name,
    });
  }

  Future<shelf.Response> _listLogs(shelf.Request request) async {
    final offset = math.max(
      0,
      int.tryParse(request.requestedUri.queryParameters['offset'] ?? '') ?? 0,
    );
    final limit = math.min(
      2000,
      math.max(
        1,
        int.tryParse(request.requestedUri.queryParameters['limit'] ?? '') ??
            _config.logConfig.lazyReadPageSize,
      ),
    );
    final slice = _memoryLogs.skip(offset).take(limit).toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{
      'items': slice.map((entry) => entry.toJson()).toList(growable: false),
      'offset': offset,
      'limit': limit,
      'total': _memoryLogs.length,
      'has_more': offset + slice.length < _memoryLogs.length,
    });
  }

  Future<shelf.Response> _cleanupOps(shelf.Request request) async {
    final body = await _readJsonBody(request);
    final target = _string(body['target'], 'all').trim().toLowerCase();
    final expiredOnly = body['expired_only'] as bool? ?? false;
    final logs = target == 'logs' || target == 'all';
    final uploads = target == 'uploads' || target == 'all';
    if (!logs && !uploads) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'invalid_cleanup_target',
      });
    }
    final result = await cleanupArtifacts(
      logs: logs,
      uploads: uploads,
      expiredOnly: expiredOnly,
    );
    return _json(HttpStatus.ok, result.toJson());
  }

  Future<shelf.Response> _cleanupHistoryPayload() async {
    return _json(HttpStatus.ok, <String, Object?>{
      'items': _cleanupHistory.reversed
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'total': _cleanupHistory.length,
      'max_items': 50,
    });
  }

  Future<shelf.Response> _exportLogs() async {
    final body = await exportLogBundleJson();
    return shelf.Response.ok(
      body,
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.cacheControlHeader: 'no-store',
        'content-disposition':
            'attachment; filename="openhand-web-gateway-logs.json"',
      },
    );
  }

  Future<Map<String, Object?>> _logBundlePayload() async {
    return <String, Object?>{
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'service': webMessagePlatformBuiltinName,
      'memory_logs': _memoryLogs.map((entry) => entry.toJson()).toList(),
      'disk_logs': await _fileLogger.readBundle(),
    };
  }

  Future<shelf.Response> _listWorkspaceFiles(shelf.Request request) async {
    if (!_config.workspaceFilesEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'workspace_files_disabled',
      });
    }
    final relative = request.requestedUri.queryParameters['path'] ?? '';
    final query = (request.requestedUri.queryParameters['q'] ?? '').trim().toLowerCase();
    final typeFilter = (request.requestedUri.queryParameters['type'] ?? 'all')
        .trim()
        .toLowerCase();
    final extensionFilter = _workspaceExtensionsForQuery(
      request.requestedUri.queryParameters['extensions'],
    );
    final dir = _resolveWorkspacePath(relative);
    if (dir == null || !await FileSystemEntity.isDirectory(dir)) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'directory_not_found',
      });
    }
    final root = _workspaceDirectoryPath;
    final entries = Directory(dir).listSync(followLinks: false)
      ..sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
    final items = <Map<String, Object?>>[];
    for (final entry in entries) {
      final isDirectory = entry is Directory;
      final entryType = isDirectory ? 'directory' : 'file';
      if (typeFilter == 'file' && isDirectory) continue;
      if (typeFilter == 'directory' && !isDirectory) continue;
      if (!isDirectory &&
          !_workspaceExtensionAllowed(entry.path, extensionFilter)) {
        continue;
      }
      final relativePath = _relativeWorkspacePath(entry.path);
      final name = p.basename(entry.path);
      if (query.isNotEmpty &&
          !name.toLowerCase().contains(query) &&
          !relativePath.toLowerCase().contains(query)) {
        continue;
      }
      final stat = entry.statSync();
      items.add(<String, Object?>{
        'name': name,
        'path': relativePath,
        'type': entryType,
        'size': stat.size,
        'modified_at': stat.modified.toUtc().toIso8601String(),
        if (!isDirectory) 'extension': p.extension(entry.path).toLowerCase(),
        if (!isDirectory)
          'editable': stat.size <= _config.workspaceFileMaxBytes,
      });
      if (items.length >= 300) break;
    }
    return _json(HttpStatus.ok, <String, Object?>{
      'root': root,
      'path': _relativeWorkspacePath(dir),
      'items': items,
      'query': query,
      'type': typeFilter,
      'write_enabled': _config.workspaceFileWriteEnabled,
      'max_file_bytes': _config.workspaceFileMaxBytes,
      'allowed_extensions': _config.workspaceFileAllowedExtensions,
    });
  }

  Future<shelf.Response> _readWorkspaceFile(shelf.Request request) async {
    if (!_config.workspaceFilesEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'workspace_files_disabled',
      });
    }
    final relative = request.requestedUri.queryParameters['path'] ?? '';
    final filePath = _resolveWorkspacePath(relative);
    if (filePath == null || !await FileSystemEntity.isFile(filePath)) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'file_not_found',
      });
    }
    if (!_workspaceExtensionAllowed(filePath, _workspaceAllowedExtensions())) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'file_extension_not_allowed',
      });
    }
    final stat = await File(filePath).stat();
    if (stat.size > _config.workspaceFileMaxBytes) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'file_too_large',
        'limit_bytes': _config.workspaceFileMaxBytes,
      });
    }
    final bytes = await File(filePath).readAsBytes();
    if (_looksBinary(bytes)) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'binary_file_not_supported',
      });
    }
    return _json(HttpStatus.ok, <String, Object?>{
      'path': _relativeWorkspacePath(filePath),
      'content': utf8.decode(bytes, allowMalformed: true),
      'size': stat.size,
      'modified_at': stat.modified.toUtc().toIso8601String(),
    });
  }

  Future<shelf.Response> _writeWorkspaceFile(shelf.Request request) async {
    if (!_config.workspaceFilesEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'workspace_files_disabled',
      });
    }
    if (!_config.workspaceFileWriteEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'workspace_file_write_disabled',
      });
    }
    final body = await _readJsonBody(
      request,
      maxBytes: _config.workspaceFileMaxBytes + 1024,
    );
    final relative = _string(body['path'], '');
    final content = _string(body['content'], '');
    if (utf8.encode(content).length > _config.workspaceFileMaxBytes) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'content_too_large',
        'limit_bytes': _config.workspaceFileMaxBytes,
      });
    }
    final filePath = _resolveWorkspacePath(relative);
    if (filePath == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'path_outside_workspace',
      });
    }
    if (!_workspaceExtensionAllowed(filePath, _workspaceAllowedExtensions())) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'file_extension_not_allowed',
      });
    }
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    final stat = await file.stat();
    _log(WebGatewayLogLevel.warn, 'FILES', 'Web 写入项目文件', <String, Object?>{
      'path': _relativeWorkspacePath(filePath),
      'size': stat.size,
    });
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'path': _relativeWorkspacePath(filePath),
      'size': stat.size,
      'modified_at': stat.modified.toUtc().toIso8601String(),
    });
  }

  _WebGatewayAuthSession? _authorize(shelf.Request request) {
    if (!_config.authEnabled) {
      final deviceId =
          request.headers['x-openhand-device-id'] ?? 'anonymous-web';
      return _WebGatewayAuthSession(
        token: 'anonymous',
        source: WebGatewayLoginSource.fromStorage(
          request.headers['x-openhand-source'] ?? 'WEB_PC',
        ),
        deviceId: deviceId,
        deviceMacAddress: request.headers['x-openhand-device-mac'] ?? '',
        deviceName: request.headers['x-openhand-device-name'] ?? '',
        devicePlatform:
            request.headers['x-openhand-device-platform'] ?? '',
        loginAt: DateTime.now().toUtc(),
        remoteAddress: (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress.address ?? '',
        userAgent: request.headers[HttpHeaders.userAgentHeader] ?? '',
      );
    }
    final authHeader =
        request.headers[HttpHeaders.authorizationHeader] ?? '';
    if (!authHeader.startsWith('Bearer ')) return null;
    final token = authHeader.substring('Bearer '.length).trim();
    if (token.isEmpty) return null;
    return _authSessions[token];
  }

  AiSession? _findAuthorizedSession(
    _WebGatewayAuthSession auth,
    String sessionId,
  ) {
    for (final session in _sessionController.sessions) {
      if (session.id != sessionId) continue;
      if (_authCanAccessAllSessions(auth)) return session;
      final context = _webContext(session.metadata);
      if (_string(context['device_id'], '') != auth.deviceId) return null;
      if (_string(context['login_source'], '') != auth.source.storageValue) {
        return null;
      }
      return session;
    }
    return null;
  }

  bool _authCanAccessAllSessions(_WebGatewayAuthSession auth) {
    return _config.authEnabled && auth.token != 'anonymous';
  }

  Map<String, Object?> _metadataForRequest(
    _WebGatewayAuthSession auth,
    shelf.Request request,
    Map<String, Object?> extra,
  ) {
    return buildLegacyWebGatewayRequestMetadata(
      authMetadata: auth.toMetadata(),
      requestMethod: request.method,
      requestPath: request.requestedUri.path,
      requestId: _nextLogId,
      extras: extra,
    );
  }

  Map<String, Object?> _webContext(Map<String, Object?> metadata) {
    final raw = metadata[webGatewayMetadataKey];
    if (raw is Map) return Map<String, Object?>.from(raw);
    return const <String, Object?>{};
  }

  Map<String, Object?> _sessionSummary(AiSession session) {
    final context = _webContext(session.metadata);
    final displayMessages = session.displayMessages;
    final last = displayMessages.isEmpty ? null : displayMessages.last;
    return <String, Object?>{
      'id': session.id,
      'title': session.title,
      'template_id': session.templateId,
      'template_name': session.templateName,
      'created_at': session.createdAt.toUtc().toIso8601String(),
      'updated_at': session.updatedAt.toUtc().toIso8601String(),
      'mode': session.mode.storageValue,
      'message_count': displayMessages.length,
      'last_message_preview': last == null
          ? ''
          : _truncate(last.content.replaceAll('\n', ' '), 160),
      'last_message_kind': last?.kind.storageValue,
      'send_phase': _sessionController.sendPhaseForSession(session.id).name,
      'source': context['login_source'],
      'device_id': context['device_id'],
      'metadata': context,
    };
  }

  Map<String, Object?> _messageJson(AiSessionMessage message) {
    return <String, Object?>{
      'id': message.id,
      'kind': message.kind.storageValue,
      'role': message.role.storageValue,
      'content': message.content,
      'created_at': message.createdAt.toUtc().toIso8601String(),
      'character_count': message.characterCount,
      'model_id': message.modelId,
      'model_label': message.modelLabel,
      'metadata': message.metadata,
    };
  }

  AiSessionRuntimeContext _buildRuntimeContext({required String templateId}) {
    final now = DateTime.now().toLocal();
    final mcpToolCatalogsByServerName = <String, McpToolCatalog>{
      for (final server in _mcpController.servers)
        server.name: _mcpController.toolCatalogFor(server.name),
    };
    return AiSessionRuntimeContext(
      localeTag: _settingsController.locale.toLanguageTag(),
      appVersion: _appInfo.version,
      appBuildNumber: _appInfo.buildNumber,
      settingsFilePath: _settingsController.settingsFilePath,
      skillsStoragePath: _settingsController.skillsStoragePath,
      mcpServersFilePath: _settingsController.mcpServersFilePath,
      userMemoryFilePath: _settingsController.userMemoryFilePath,
      compressionThresholdChars:
          _settingsController.aiMessageCompressionThresholdChars,
      memoryEnabled: _settingsController.memoryEnabled,
      memoryEntries: _settingsController.memoryEnabled
          ? _memoryController.entries
          : const [],
      templateId: templateId,
      platformName: Platform.operatingSystem,
      workingDirectory: OpenHandPaths.applicationDirectoryPath(),
      todayLocalDate:
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      timeZoneName: now.timeZoneName,
      availableSkills: _config.allowedSkillNames.isEmpty
          ? _skillsController.skills
          : _skillsController.skills
                .where(
                  (skill) => _config.allowedSkillNames.contains(skill.name),
                )
                .toList(growable: false),
      availableMcpServers: _config.allowedMcpServerNames.isEmpty
          ? _mcpController.servers
          : _mcpController.servers
                .where(
                  (server) =>
                      _config.allowedMcpServerNames.contains(server.name),
                )
                .toList(growable: false),
      mcpToolCatalogsByServerName: mcpToolCatalogsByServerName,
      builtinToolConfigs: _settingsController.builtinToolConfigs
          .where(
            (tool) =>
                _config.allowedBuiltinToolNames.isEmpty ||
                _config.allowedBuiltinToolNames.contains(tool.effectiveName),
          )
          .toList(growable: false),
      userInstructions: _instructionsController.entries,
    );
  }

  List<AiThreadTemplate> _allowedTemplates() {
    if (_config.allowedTemplateIds.isEmpty) return _sessionController.templates;
    return _sessionController.templates
        .where((template) => _config.allowedTemplateIds.contains(template.id))
        .toList(growable: false);
  }

  bool _templateAllowed(String templateId) {
    return _config.allowedTemplateIds.isEmpty ||
        _config.allowedTemplateIds.contains(templateId);
  }

  List<_AllowedWebModel> _allowedModels() {
    final result = <_AllowedWebModel>[];
    for (final provider in _settingsController.aiModels) {
      for (final modelId in provider.allModelIds) {
        final key = _modelKey(provider.id, modelId);
        if (_config.allowedModelKeys.isNotEmpty &&
            !_config.allowedModelKeys.contains(key)) {
          continue;
        }
        result.add(
          _AllowedWebModel(
            key: key,
            providerId: provider.id,
            providerLabel: provider.providerLabel,
            modelId: modelId,
            label: '${provider.providerLabel} / $modelId',
          ),
        );
      }
    }
    return result;
  }

  AiModelConfig? _resolveModel(String key) {
    final requested = key.trim();
    if (requested.isNotEmpty &&
        (_config.allowedModelKeys.isEmpty ||
            _config.allowedModelKeys.contains(requested))) {
      final parsed = _parseModelKey(requested);
      if (parsed != null) {
        for (final provider in _settingsController.aiModels) {
          if (provider.id == parsed.providerId &&
              provider.allModelIds.contains(parsed.modelId)) {
            return provider.copyWith(modelId: parsed.modelId);
          }
        }
      }
    }
    final selected = _settingsController.selectedAiModel;
    if (selected != null) {
      final selectedKey = _modelKey(selected.id, selected.modelId);
      if (_config.allowedModelKeys.isEmpty ||
          _config.allowedModelKeys.contains(selectedKey)) {
        return selected;
      }
    }
    for (final model in _allowedModels()) {
      final parsed = _parseModelKey(model.key);
      if (parsed == null) continue;
      for (final provider in _settingsController.aiModels) {
        if (provider.id == parsed.providerId) {
          return provider.copyWith(modelId: parsed.modelId);
        }
      }
    }
    return null;
  }

  AiCreationRequest _creationRequestFor(WebGatewayConversationMode mode) {
    return switch (mode) {
      WebGatewayConversationMode.image => const AiCreationRequest(
        mode: AiCreationMode.image,
      ),
      WebGatewayConversationMode.video => const AiCreationRequest(
        mode: AiCreationMode.video,
      ),
      WebGatewayConversationMode.audio => const AiCreationRequest(
        mode: AiCreationMode.audio,
      ),
      WebGatewayConversationMode.deepResearch => const AiCreationRequest(
        mode: AiCreationMode.deepResearch,
      ),
      WebGatewayConversationMode.normal => AiCreationRequest.none,
    };
  }

  Future<List<String>> _materializeAttachments(
    String sessionId,
    Object? raw,
  ) async {
    if (raw is! List || raw.isEmpty) return const <String>[];
    final output = <String>[];
    final dir = Directory(p.join(_uploadCacheDirectoryPath, sessionId));
    await dir.create(recursive: true);
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, Object?>.from(item);
      final name = _safeFileName(_string(map['name'], 'attachment.bin'));
      final data = _string(map['data_base64'], '').trim();
      if (data.isEmpty) continue;
      final bytes = base64Decode(data);
      final file = File(
        p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}-$name'),
      );
      await file.writeAsBytes(bytes);
      output.add(file.path);
    }
    return output;
  }

  String get _uploadCacheDirectoryPath =>
      p.join(_cacheDirectoryPath, 'message_gateway', 'uploads');

  Future<_CleanupStats> _cleanupUploadCache({required bool expiredOnly}) async {
    final root = Directory(_uploadCacheDirectoryPath);
    if (!await root.exists()) return const _CleanupStats();
    if (!expiredOnly) {
      final stats = await _measureDirectory(root);
      await root.delete(recursive: true);
      return stats.copyWith(deletedDirectories: stats.deletedDirectories + 1);
    }
    final cutoff = DateTime.now().subtract(
      Duration(days: _config.uploadCacheRetentionDays),
    );
    final entities = await root
        .list(recursive: true, followLinks: false)
        .toList();
    entities.sort((a, b) => b.path.length.compareTo(a.path.length));
    var stats = const _CleanupStats();
    for (final entity in entities) {
      try {
        final stat = await entity.stat();
        if (stat.modified.isAfter(cutoff)) continue;
        if (entity is File) {
          stats += _CleanupStats(deletedFiles: 1, bytesFreed: stat.size);
          await entity.delete();
        } else if (entity is Directory) {
          final isEmpty = await entity.list(followLinks: false).isEmpty;
          if (!isEmpty) continue;
          stats += const _CleanupStats(deletedDirectories: 1);
          await entity.delete();
        }
      } catch (error, stack) {
        silentLog(
          'web_message_platform_service',
          'cleanup upload cache',
          error,
          stack,
        );
      }
    }
    return stats + await _enforceUploadCacheMaxBytes();
  }

  Future<_CleanupStats> _enforceUploadCacheMaxBytes() async {
    final root = Directory(_uploadCacheDirectoryPath);
    if (!await root.exists()) return const _CleanupStats();
    final files = <File>[];
    var totalBytes = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        totalBytes += stat.size;
        files.add(entity);
      } catch (_) {}
    }
    if (totalBytes <= _config.uploadCacheMaxBytes) {
      return const _CleanupStats();
    }
    files.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );
    var stats = const _CleanupStats();
    var remainingBytes = totalBytes;
    for (final file in files) {
      if (remainingBytes <= _config.uploadCacheMaxBytes) break;
      try {
        final stat = await file.stat();
        await file.delete();
        remainingBytes -= stat.size;
        stats += _CleanupStats(deletedFiles: 1, bytesFreed: stat.size);
      } catch (error, stack) {
        silentLog(
          'web_message_platform_service',
          'enforce upload cache max bytes',
          error,
          stack,
        );
      }
    }
    return stats;
  }

  Future<_CleanupStats> _measureDirectory(Directory directory) async {
    var stats = const _CleanupStats();
    if (!await directory.exists()) return stats;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      try {
        final stat = await entity.stat();
        if (entity is File) {
          stats += _CleanupStats(deletedFiles: 1, bytesFreed: stat.size);
        } else if (entity is Directory) {
          stats += const _CleanupStats(deletedDirectories: 1);
        }
      } catch (_) {}
    }
    return stats;
  }

  /// 读取并解析 JSON 请求体；超过 [maxBytes] 抛 `FormatException`，
  /// 由外层中间件转 500。空 body 返回 `{}`。
  Future<Map<String, Object?>> _readJsonBody(
    shelf.Request request, {
    int maxBytes = 1024 * 1024,
  }) async {
    final chunks = <int>[];
    await for (final chunk in request.read()) {
      chunks.addAll(chunk);
      if (chunks.length > maxBytes) {
        throw const FormatException('Request body is too large.');
      }
    }
    if (chunks.isEmpty) return <String, Object?>{};
    final decoded = jsonDecode(utf8.decode(chunks));
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    return <String, Object?>{};
  }

  /// 构造 JSON 响应。`Cache-Control: no-store` 避免浏览器/CDN 缓存敏感数据。
  shelf.Response _json(int statusCode, Map<String, Object?> payload) {
    final body = jsonEncode(payload);
    return shelf.Response(
      statusCode,
      body: body,
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.cacheControlHeader: 'no-store',
      },
    );
  }

  /// 构造 HTML 响应。仅给三条 SPA 入口路由用，浏览器允许缓存。
  shelf.Response _html(String html) {
    return shelf.Response.ok(
      html,
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
      },
    );
  }

  /// SPA shell：优先尝试 `assets/web/index.html`（clients/web 子项目的 Vite
  /// 构建产物），缺失时退回内嵌 legacy 模板，保证未跑 build_web.sh 的环境
  /// 也能访问。`rootBundle` 在桌面/移动平台均可用，service 与 Flutter app
  /// 在同一 isolate。
  Future<shelf.Response> _serveWebShell() async {
    try {
      final html = await rootBundle.loadString('assets/web/index.html');
      return _html(html);
    } catch (e, stack) {
      silentLog('web_gateway_service', '_serveWebShell.fallback', e, stack);
      return _html(_buildWebClientHtml());
    }
  }

  /// 静态资源（app.js / app.css / chunks/* / assets/*）从 rootBundle 取，
  /// 缺失或读取失败 → 404。`Cache-Control: max-age=0,must-revalidate` 保证
  /// 重新构建后旧浏览器拿到的是新版本（文件名是确定性的，没有 hash）。
  Future<shelf.Response> _serveBundleAsset(String key, String contentType) async {
    try {
      final data = await rootBundle.load(key);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      return shelf.Response.ok(
        bytes,
        headers: <String, String>{
          HttpHeaders.contentTypeHeader: contentType,
          HttpHeaders.cacheControlHeader: 'max-age=0, must-revalidate',
          HttpHeaders.contentLengthHeader: bytes.length.toString(),
        },
      );
    } catch (e, stack) {
      silentLog('web_gateway_service', '_serveBundleAsset:$key', e, stack);
      return shelf.Response.notFound('asset_not_found: $key');
    }
  }

  /// 极简 MIME 推断，只覆盖 Vite 构建会产生的扩展名。
  String _guessContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
      return 'application/javascript; charset=utf-8';
    }
    if (lower.endsWith('.css')) return 'text/css; charset=utf-8';
    if (lower.endsWith('.json')) return 'application/json; charset=utf-8';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.woff2')) return 'font/woff2';
    if (lower.endsWith('.woff')) return 'font/woff';
    if (lower.endsWith('.ttf')) return 'font/ttf';
    if (lower.endsWith('.map')) return 'application/json; charset=utf-8';
    return 'application/octet-stream';
  }

  void _log(
    WebGatewayLogLevel level,
    String tag,
    String message, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    final entry = WebGatewayLogEntry(
      id: _nextLogId++,
      timestamp: DateTime.now().toUtc(),
      level: level,
      tag: tag,
      message: message,
      data: data,
    );
    _memoryLogs.add(entry);
    if (_memoryLogs.length > 5000) {
      _memoryLogs.removeRange(0, _memoryLogs.length - 5000);
    }
    if (!_logStreamController.isClosed) {
      _logStreamController.add(entry);
    }
    if (_config.loggingEnabled) {
      unawaited(_fileLogger.write(entry, _config.logConfig));
    }
  }

  InternetAddress _bindAddress(String host) {
    final normalized = host.trim();
    if (normalized.isEmpty || normalized == '0.0.0.0') {
      return InternetAddress.anyIPv4;
    }
    if (normalized == '::' || normalized == '::0') {
      return InternetAddress.anyIPv6;
    }
    return InternetAddress(normalized);
  }

  String _displayHost(String host) {
    final normalized = host.trim();
    if (normalized.isEmpty || normalized == '0.0.0.0' || normalized == '::') {
      return '127.0.0.1';
    }
    return normalized;
  }

  String? _resolveWorkspacePath(String rawPath) {
    final root = _workspaceDirectoryPath;
    final normalizedInput = rawPath.trim().replaceAll('\\', '/');
    if (normalizedInput.startsWith('/')) return null;
    final resolved = p.normalize(p.join(root, normalizedInput));
    if (resolved == root || p.isWithin(root, resolved)) return resolved;
    return null;
  }

  String _relativeWorkspacePath(String absolutePath) {
    final root = _workspaceDirectoryPath;
    if (absolutePath == root) return '';
    return p.relative(absolutePath, from: root).replaceAll('\\', '/');
  }

  Set<String> _workspaceAllowedExtensions() {
    return _config.workspaceFileAllowedExtensions
        .map(_normalizeWorkspaceExtension)
        .where((extension) => extension.isNotEmpty)
        .toSet();
  }

  Set<String> _workspaceExtensionsForQuery(String? raw) {
    final configured = _workspaceAllowedExtensions();
    final requested = (raw ?? '')
        .split(',')
        .map(_normalizeWorkspaceExtension)
        .where((extension) => extension.isNotEmpty)
        .toSet();
    if (requested.isEmpty) return configured;
    if (configured.isEmpty) return requested;
    return requested.where(configured.contains).toSet();
  }

  bool _workspaceExtensionAllowed(String path, Set<String> allowedExtensions) {
    if (allowedExtensions.isEmpty) return true;
    final extension = _normalizeWorkspaceExtension(p.extension(path));
    return allowedExtensions.contains(extension);
  }

  bool _looksBinary(List<int> bytes) {
    final sampleLength = math.min(bytes.length, 4096);
    for (var i = 0; i < sampleLength; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  Future<void> _refreshProcessDiagnosticsIfStale() async {
    final now = DateTime.now();
    final previous = _processDiagnosticsAt;
    if (previous != null && now.difference(previous).inSeconds < 2) return;
    _processDiagnosticsAt = now;
    try {
      if (Platform.isMacOS) {
        _processDiagnostics = await _sampleMacProcessDiagnostics();
      } else if (Platform.isLinux) {
        _processDiagnostics = await _sampleLinuxProcessDiagnostics();
      }
    } catch (error, stack) {
      silentLog(
        'web_message_platform_service',
        'process diagnostics',
        error,
        stack,
      );
    }
  }

  Future<_ProcessDiagnostics> _sampleMacProcessDiagnostics() async {
    double? cpuPercent;
    int? threadCount;
    final ps = await runProcessWithTimeout(
      'ps',
      <String>['-o', '%cpu=', '-o', 'nlwp=', '-p', '$pid'],
      timeout: const Duration(milliseconds: 900),
      tag: 'web_message_gateway_ops',
    );
    if (ps != null && ps.exitCode == 0) {
      final parts = '${ps.stdout}'.trim().split(RegExp(r'\s+'));
      if (parts.isNotEmpty) cpuPercent = double.tryParse(parts[0]);
      if (parts.length > 1) threadCount = int.tryParse(parts[1]);
    }
    final lsof = await runProcessWithTimeout(
      'lsof',
      <String>['-n', '-p', '$pid'],
      timeout: const Duration(milliseconds: 1200),
      tag: 'web_message_gateway_ops',
    );
    final fileHandleCount = lsof == null || lsof.exitCode != 0
        ? null
        : math.max(0, '${lsof.stdout}'.trim().split('\n').length - 1);
    final swap = await runProcessWithTimeout(
      'sysctl',
      const <String>['vm.swapusage'],
      timeout: const Duration(milliseconds: 900),
      tag: 'web_message_gateway_ops',
    );
    return _ProcessDiagnostics(
      cpuPercent: cpuPercent,
      threadCount: threadCount,
      fileHandleCount: fileHandleCount,
      swapBytes: _parseMacSwapBytes('${swap?.stdout ?? ''}'),
    );
  }

  Future<_ProcessDiagnostics> _sampleLinuxProcessDiagnostics() async {
    final cpuPercent = await _sampleLinuxCpuPercent();
    int? threadCount;
    int? swapBytes;
    try {
      final status = await File('/proc/self/status').readAsLines();
      for (final line in status) {
        if (line.startsWith('Threads:')) {
          threadCount = int.tryParse(line.split(RegExp(r'\s+')).last);
        }
        if (line.startsWith('VmSwap:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length > 1) {
            swapBytes = (int.tryParse(parts[1]) ?? 0) * 1024;
          }
        }
      }
    } catch (_) {}
    int? fileHandleCount;
    try {
      fileHandleCount = Directory('/proc/self/fd').listSync().length;
    } catch (_) {}
    return _ProcessDiagnostics(
      cpuPercent: cpuPercent,
      threadCount: threadCount,
      fileHandleCount: fileHandleCount,
      swapBytes: swapBytes,
    );
  }

  Future<double?> _sampleLinuxCpuPercent() async {
    final sample = await _readLinuxCpuSample();
    if (sample == null) return _processDiagnostics.cpuPercent;
    final previous = _previousLinuxCpuSample;
    _previousLinuxCpuSample = sample;
    if (previous == null) return _processDiagnostics.cpuPercent;
    final processDelta = sample.processTicks - previous.processTicks;
    final totalDelta = sample.totalTicks - previous.totalTicks;
    if (processDelta < 0 || totalDelta <= 0) {
      return _processDiagnostics.cpuPercent;
    }
    final cpuCount = math.max(1, Platform.numberOfProcessors);
    return processDelta / totalDelta * cpuCount * 100;
  }

  Future<_LinuxCpuSample?> _readLinuxCpuSample() async {
    try {
      final processStat = await File('/proc/self/stat').readAsString();
      final processEnd = processStat.lastIndexOf(')');
      if (processEnd < 0) return null;
      final processFields = processStat
          .substring(processEnd + 1)
          .trim()
          .split(RegExp(r'\s+'));
      if (processFields.length <= 12) return null;
      final userTicks = int.tryParse(processFields[11]);
      final systemTicks = int.tryParse(processFields[12]);
      if (userTicks == null || systemTicks == null) return null;

      final statLines = await File('/proc/stat').readAsLines();
      final cpuLine = statLines.firstWhere(
        (line) => line.startsWith('cpu '),
        orElse: () => '',
      );
      if (cpuLine.isEmpty) return null;
      var totalTicks = 0;
      for (final part in cpuLine.trim().split(RegExp(r'\s+')).skip(1)) {
        totalTicks += int.tryParse(part) ?? 0;
      }
      if (totalTicks <= 0) return null;
      return _LinuxCpuSample(
        processTicks: userTicks + systemTicks,
        totalTicks: totalTicks,
      );
    } catch (_) {
      return null;
    }
  }

  String _makeToken() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _buildWebClientHtml() {
    return webMessagePlatformLegacyClientHtml
        .replaceAll('{{primary}}', _theme.primary)
        .replaceAll('{{onPrimary}}', _theme.onPrimary)
        .replaceAll('{{surface}}', _theme.surface)
        .replaceAll('{{surfaceContainer}}', _theme.surfaceContainer)
        .replaceAll('{{onSurface}}', _theme.onSurface)
        .replaceAll('{{onSurfaceVariant}}', _theme.onSurfaceVariant)
        .replaceAll('{{outline}}', _theme.outline)
        .replaceAll('{{error}}', _theme.error);
  }
}

class _AllowedWebModel {
  const _AllowedWebModel({
    required this.key,
    required this.providerId,
    required this.providerLabel,
    required this.modelId,
    required this.label,
  });

  final String key;
  final String providerId;
  final String providerLabel;
  final String modelId;
  final String label;
}

class _ParsedModelKey {
  const _ParsedModelKey({required this.providerId, required this.modelId});

  final String providerId;
  final String modelId;
}

String _modelKey(String providerId, String modelId) => '$providerId::$modelId';

_ParsedModelKey? _parseModelKey(String key) {
  final parts = key.split('::');
  if (parts.length != 2) return null;
  final providerId = parts[0].trim();
  final modelId = parts[1].trim();
  if (providerId.isEmpty || modelId.isEmpty) return null;
  return _ParsedModelKey(providerId: providerId, modelId: modelId);
}

String _string(Object? value, String fallback) {
  if (value == null) return fallback;
  final text = '$value';
  return text.isEmpty ? fallback : text;
}

String _truncate(String value, int maxChars) {
  if (value.length <= maxChars) return value;
  return '${value.substring(0, maxChars)}...';
}

String _safeFileName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  if (sanitized.isEmpty) return 'attachment.bin';
  return sanitized.length > 120 ? sanitized.substring(0, 120) : sanitized;
}

String _normalizeWorkspaceExtension(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  final withoutLeadingDot = trimmed.startsWith('.')
      ? trimmed.substring(1)
      : trimmed;
  final safe = withoutLeadingDot.replaceAll(RegExp(r'[^a-z0-9_+-]'), '');
  return safe.isEmpty ? '' : '.$safe';
}



// _webClientHtml 已迁出至 service/web_message_platform_legacy_client_html.dart

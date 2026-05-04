import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

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
import '../model/web_message_platform_config.dart';

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
      final server = await HttpServer.bind(
        address,
        config.listenPort,
        shared: true,
      );
      server.serverHeader = 'OpenHand-WebGateway/1.0';
      _server = server;
      _startedAt = DateTime.now().toUtc();
      _state = WebGatewayRuntimeState.running;
      _log(WebGatewayLogLevel.success, 'BOOT', 'Web 服务已监听 $boundUrl');
      unawaited(cleanupArtifacts(logs: true, uploads: true, expiredOnly: true));
      unawaited(_serve(server));
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
    return runtimeSnapshot();
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

  Future<void> _serve(HttpServer server) async {
    try {
      await for (final request in server) {
        unawaited(_handleRequest(request));
      }
    } catch (error, stack) {
      if (!identical(_server, server)) return;
      _state = WebGatewayRuntimeState.crashed;
      _crashCount++;
      _lastError = '$error';
      _log(WebGatewayLogLevel.error, 'SERVE', '请求循环崩溃: $error');
      silentLog('web_message_platform_service', 'serve loop', error, stack);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final stopwatch = Stopwatch()..start();
    var statusCode = 200;
    var responseBytes = 0;
    String? errorText;
    final requestBytes = request.contentLength > 0 ? request.contentLength : 0;
    _totalRequests++;
    _totalBytesIn += requestBytes;
    if (_activeRequests >= _config.maxConcurrentRequests) {
      _totalErrors++;
      await _json(request, HttpStatus.tooManyRequests, <String, Object?>{
        'error': 'too_many_requests',
      });
      _log(WebGatewayLogLevel.warn, 'HTTP', '请求被并发限制拒绝', <String, Object?>{
        'path': request.uri.path,
        'active_requests': _activeRequests,
        'limit': _config.maxConcurrentRequests,
      });
      return;
    }
    _activeRequests++;
    try {
      _applyCors(request.response);
      if (request.method == 'OPTIONS') {
        statusCode = HttpStatus.noContent;
        request.response.statusCode = statusCode;
        await request.response.close();
        return;
      }
      responseBytes = await _route(request);
      statusCode = request.response.statusCode;
    } catch (error, stack) {
      statusCode = HttpStatus.internalServerError;
      errorText = '$error';
      _totalErrors++;
      _lastError = errorText;
      silentLog('web_message_platform_service', 'handle request', error, stack);
      try {
        await _json(request, statusCode, <String, Object?>{
          'error': 'internal_error',
          'message': errorText,
        });
      } catch (responseError, responseStack) {
        silentLog(
          'web_message_platform_service',
          'write error response',
          responseError,
          responseStack,
        );
        try {
          await request.response.close();
        } catch (_) {
          // Response is already closed.
        }
      }
    } finally {
      _activeRequests = math.max(0, _activeRequests - 1);
      stopwatch.stop();
      _totalBytesOut += responseBytes;
      final level = statusCode >= 500
          ? WebGatewayLogLevel.error
          : statusCode >= 400
          ? WebGatewayLogLevel.warn
          : (_config.telemetryEnabled
                ? WebGatewayLogLevel.telemetry
                : WebGatewayLogLevel.info);
      final shouldLog =
          _config.loggingEnabled ||
          _config.telemetryEnabled ||
          statusCode >= 400;
      if (shouldLog) {
        _log(
          level,
          'HTTP',
          '${request.method} ${request.uri.path} -> $statusCode ${stopwatch.elapsedMilliseconds}ms',
          <String, Object?>{
            'method': request.method,
            'path': request.uri.path,
            'query': request.uri.queryParameters,
            'status_code': statusCode,
            'duration_ms': stopwatch.elapsedMilliseconds,
            'remote_ip': request.connectionInfo?.remoteAddress.address,
            'remote_port': request.connectionInfo?.remotePort,
            'user_agent': request.headers.value(HttpHeaders.userAgentHeader),
            'content_length': request.contentLength,
            'response_bytes': responseBytes,
            'active_requests': _activeRequests,
            if (errorText != null) 'error': errorText,
          },
        );
      }
    }
  }

  Future<int> _route(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/' || path == '/login' || path == '/thread') {
      return _html(request, _buildWebClientHtml());
    }
    if (path == '/api/health') {
      return _json(request, HttpStatus.ok, <String, Object?>{
        'status': 'ok',
        'service': webMessagePlatformBuiltinName,
        'state': _state.name,
        'time': DateTime.now().toUtc().toIso8601String(),
      });
    }
    if (path == '/api/meta' && request.method == 'GET') {
      return _json(request, HttpStatus.ok, _metaPayload());
    }
    if (path == '/api/login' && request.method == 'POST') {
      return _login(request);
    }

    final auth = _authorize(request);
    if (auth == null) {
      return _json(request, HttpStatus.unauthorized, <String, Object?>{
        'error': 'unauthorized',
      });
    }

    if (path == '/api/sessions' && request.method == 'GET') {
      return _listSessions(request, auth);
    }
    if (path == '/api/sessions' && request.method == 'POST') {
      return _createSession(request, auth);
    }
    if (path == '/api/ops' && request.method == 'GET') {
      if (!_config.opsEnabled) {
        return _json(request, HttpStatus.forbidden, <String, Object?>{
          'error': 'ops_disabled',
        });
      }
      return _json(
        request,
        HttpStatus.ok,
        (await runtimeSnapshotAsync()).toJson(),
      );
    }
    if (path == '/api/ops/cleanup/history' && request.method == 'GET') {
      if (!_config.opsEnabled) {
        return _json(request, HttpStatus.forbidden, <String, Object?>{
          'error': 'ops_disabled',
        });
      }
      return _cleanupHistoryPayload(request);
    }
    if (path == '/api/ops/cleanup' && request.method == 'POST') {
      if (!_config.opsEnabled) {
        return _json(request, HttpStatus.forbidden, <String, Object?>{
          'error': 'ops_disabled',
        });
      }
      return _cleanupOps(request);
    }
    if (path == '/api/logs' && request.method == 'GET') {
      return _listLogs(request);
    }
    if (path == '/api/logs/export' && request.method == 'GET') {
      return _exportLogs(request);
    }
    if (path == '/api/workspace/files' && request.method == 'GET') {
      return _listWorkspaceFiles(request);
    }
    if (path == '/api/workspace/file' && request.method == 'GET') {
      return _readWorkspaceFile(request);
    }
    if (path == '/api/workspace/file' && request.method == 'PUT') {
      return _writeWorkspaceFile(request);
    }

    final segments = request.uri.pathSegments;
    if (segments.length >= 3 &&
        segments[0] == 'api' &&
        segments[1] == 'sessions') {
      final sessionId = segments[2];
      if (segments.length == 3 && request.method == 'GET') {
        return _getSession(request, auth, sessionId);
      }
      if (segments.length == 3 && request.method == 'PATCH') {
        return _renameSession(request, auth, sessionId);
      }
      if (segments.length == 3 && request.method == 'DELETE') {
        return _deleteSession(request, auth, sessionId);
      }
      if (segments.length == 4 && segments[3] == 'messages') {
        if (request.method == 'GET') {
          return _listMessages(request, auth, sessionId);
        }
        if (request.method == 'POST') {
          return _sendMessage(request, auth, sessionId);
        }
      }
    }

    return _json(request, HttpStatus.notFound, <String, Object?>{
      'error': 'not_found',
    });
  }

  Map<String, Object?> _metaPayload() {
    return <String, Object?>{
      'service': <String, Object?>{
        'id': webMessagePlatformBuiltinId,
        'name': webMessagePlatformBuiltinName,
        'description': _config.description,
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

  Future<int> _login(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final source = WebGatewayLoginSource.fromStorage(
      _string(body['source'], 'WEB_PC'),
    );
    final deviceId = _string(body['device_id'], '').trim();
    if (deviceId.isEmpty) {
      return _json(request, HttpStatus.badRequest, <String, Object?>{
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
          'remote_ip': request.connectionInfo?.remoteAddress.address,
        });
        return _json(request, HttpStatus.unauthorized, <String, Object?>{
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
      remoteAddress: request.connectionInfo?.remoteAddress.address ?? '',
      userAgent: request.headers.value(HttpHeaders.userAgentHeader) ?? '',
    );
    _authSessions[token] = session;
    _log(WebGatewayLogLevel.success, 'AUTH', '登录成功', session.toMetadata());
    return _json(request, HttpStatus.ok, <String, Object?>{
      'token': token,
      'expires_in': null,
      'profile': session.toMetadata(),
    });
  }

  Future<int> _listSessions(
    HttpRequest request,
    _WebGatewayAuthSession auth,
  ) async {
    final page = math.max(
      1,
      int.tryParse(request.uri.queryParameters['page'] ?? '') ?? 1,
    );
    final pageSize = math.min(
      50,
      math.max(
        1,
        int.tryParse(request.uri.queryParameters['page_size'] ?? '') ?? 10,
      ),
    );
    final canAccessAll = _authCanAccessAllSessions(auth);
    final sourceQuery = request.uri.queryParameters['source']?.trim() ?? '';
    final deviceQuery = request.uri.queryParameters['device_id']?.trim() ?? '';
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
    return _json(request, HttpStatus.ok, <String, Object?>{
      'items': items,
      'page': page,
      'page_size': pageSize,
      'total': filtered.length,
      'has_more': end < filtered.length,
      'sort': 'updated_at_desc,id_desc',
      'scope': canAccessAll ? 'authenticated_all' : 'current_device',
    });
  }

  Future<int> _createSession(
    HttpRequest request,
    _WebGatewayAuthSession auth,
  ) async {
    final body = await _readJsonBody(request);
    final templateId = _string(body['template_id'], 'default').trim();
    if (!_templateAllowed(templateId)) {
      return _json(request, HttpStatus.forbidden, <String, Object?>{
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
      return _json(request, HttpStatus.internalServerError, <String, Object?>{
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
    return _json(request, HttpStatus.created, <String, Object?>{
      'session': _sessionSummary(session),
    });
  }

  Future<int> _getSession(
    HttpRequest request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(request, HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    return _json(request, HttpStatus.ok, <String, Object?>{
      'session': _sessionSummary(session),
      'runtime': <String, Object?>{
        'send_phase': _sessionController.sendPhaseForSession(session.id).name,
        'can_stop': _sessionController.canStopResponding(session.id),
        'last_error': _sessionController.lastErrorMessageForSession(session.id),
      },
    });
  }

  Future<int> _renameSession(
    HttpRequest request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    if (!_config.sessionManagementEnabled) {
      return _json(request, HttpStatus.forbidden, <String, Object?>{
        'error': 'session_management_disabled',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(request, HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final body = await _readJsonBody(request);
    final title = _string(body['title'], '').trim();
    if (title.isEmpty) {
      return _json(request, HttpStatus.badRequest, <String, Object?>{
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
    return _json(
      request,
      ok ? HttpStatus.ok : HttpStatus.conflict,
      <String, Object?>{'ok': ok, 'session': _sessionSummary(updated)},
    );
  }

  Future<int> _deleteSession(
    HttpRequest request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    if (!_config.sessionManagementEnabled) {
      return _json(request, HttpStatus.forbidden, <String, Object?>{
        'error': 'session_management_disabled',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(request, HttpStatus.notFound, <String, Object?>{
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
    return _json(
      request,
      ok ? HttpStatus.ok : HttpStatus.conflict,
      <String, Object?>{'ok': ok, 'deleted_session_id': session.id},
    );
  }

  Future<int> _listMessages(
    HttpRequest request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(request, HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final limit = math.min(
      200,
      math.max(
        1,
        int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 80,
      ),
    );
    final offset = math.max(
      0,
      int.tryParse(request.uri.queryParameters['offset'] ?? '') ?? 0,
    );
    final page = await _sessionController.store.loadMessages(
      session.id,
      limit: limit,
      offset: offset,
    );
    return _json(request, HttpStatus.ok, <String, Object?>{
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

  Future<int> _sendMessage(
    HttpRequest request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(request, HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    if (session.displayMessages.length >= _config.maxMessagesPerSession) {
      return _json(request, HttpStatus.forbidden, <String, Object?>{
        'error': 'session_message_limit_reached',
      });
    }
    final body = await _readJsonBody(request, maxBytes: 24 * 1024 * 1024);
    final content = _string(body['content'], '').trim();
    final estimatedTokens = (content.length / 4).ceil();
    if (estimatedTokens > _config.singleMessageTokenLimit) {
      return _json(request, HttpStatus.badRequest, <String, Object?>{
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
      return _json(request, HttpStatus.forbidden, <String, Object?>{
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
      return _json(request, HttpStatus.forbidden, <String, Object?>{
        'error': 'attachments_not_allowed',
      });
    }
    if (content.isNotEmpty &&
        !_config.allowedMessageTypes.contains(WebGatewayMessageType.text)) {
      return _json(request, HttpStatus.forbidden, <String, Object?>{
        'error': 'text_not_allowed',
      });
    }
    final model = _resolveModel(_string(body['model_key'], ''));
    if (model == null) {
      return _json(request, HttpStatus.badRequest, <String, Object?>{
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
      return _json(request, HttpStatus.conflict, <String, Object?>{
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
    return _json(request, HttpStatus.accepted, <String, Object?>{
      'ok': true,
      'send_phase': _sessionController.sendPhaseForSession(session.id).name,
    });
  }

  Future<int> _listLogs(HttpRequest request) async {
    final offset = math.max(
      0,
      int.tryParse(request.uri.queryParameters['offset'] ?? '') ?? 0,
    );
    final limit = math.min(
      2000,
      math.max(
        1,
        int.tryParse(request.uri.queryParameters['limit'] ?? '') ??
            _config.logConfig.lazyReadPageSize,
      ),
    );
    final slice = _memoryLogs.skip(offset).take(limit).toList(growable: false);
    return _json(request, HttpStatus.ok, <String, Object?>{
      'items': slice.map((entry) => entry.toJson()).toList(growable: false),
      'offset': offset,
      'limit': limit,
      'total': _memoryLogs.length,
      'has_more': offset + slice.length < _memoryLogs.length,
    });
  }

  Future<int> _cleanupOps(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final target = _string(body['target'], 'all').trim().toLowerCase();
    final expiredOnly = body['expired_only'] as bool? ?? false;
    final logs = target == 'logs' || target == 'all';
    final uploads = target == 'uploads' || target == 'all';
    if (!logs && !uploads) {
      return _json(request, HttpStatus.badRequest, <String, Object?>{
        'error': 'invalid_cleanup_target',
      });
    }
    final result = await cleanupArtifacts(
      logs: logs,
      uploads: uploads,
      expiredOnly: expiredOnly,
    );
    return _json(request, HttpStatus.ok, result.toJson());
  }

  Future<int> _cleanupHistoryPayload(HttpRequest request) async {
    return _json(request, HttpStatus.ok, <String, Object?>{
      'items': _cleanupHistory.reversed
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'total': _cleanupHistory.length,
      'max_items': 50,
    });
  }

  Future<int> _exportLogs(HttpRequest request) async {
    final bytes = utf8.encode(await exportLogBundleJson());
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.headers.set(
      'content-disposition',
      'attachment; filename="openhand-web-gateway-logs.json"',
    );
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
    return bytes.length;
  }

  Future<Map<String, Object?>> _logBundlePayload() async {
    return <String, Object?>{
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'service': webMessagePlatformBuiltinName,
      'memory_logs': _memoryLogs.map((entry) => entry.toJson()).toList(),
      'disk_logs': await _fileLogger.readBundle(),
    };
  }

  Future<int> _listWorkspaceFiles(HttpRequest request) async {
    if (!_config.workspaceFilesEnabled) {
      return _json(request, HttpStatus.forbidden, <String, Object?>{
        'error': 'workspace_files_disabled',
      });
    }
    final relative = request.uri.queryParameters['path'] ?? '';
    final query = (request.uri.queryParameters['q'] ?? '').trim().toLowerCase();
    final typeFilter = (request.uri.queryParameters['type'] ?? 'all')
        .trim()
        .toLowerCase();
    final extensionFilter = _workspaceExtensionsForQuery(
      request.uri.queryParameters['extensions'],
    );
    final dir = _resolveWorkspacePath(relative);
    if (dir == null || !await FileSystemEntity.isDirectory(dir)) {
      return _json(request, HttpStatus.notFound, <String, Object?>{
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
    return _json(request, HttpStatus.ok, <String, Object?>{
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

  Future<int> _readWorkspaceFile(HttpRequest request) async {
    if (!_config.workspaceFilesEnabled) {
      return _json(request, HttpStatus.forbidden, <String, Object?>{
        'error': 'workspace_files_disabled',
      });
    }
    final relative = request.uri.queryParameters['path'] ?? '';
    final filePath = _resolveWorkspacePath(relative);
    if (filePath == null || !await FileSystemEntity.isFile(filePath)) {
      return _json(request, HttpStatus.notFound, <String, Object?>{
        'error': 'file_not_found',
      });
    }
    if (!_workspaceExtensionAllowed(filePath, _workspaceAllowedExtensions())) {
      return _json(request, HttpStatus.forbidden, <String, Object?>{
        'error': 'file_extension_not_allowed',
      });
    }
    final stat = await File(filePath).stat();
    if (stat.size > _config.workspaceFileMaxBytes) {
      return _json(request, HttpStatus.badRequest, <String, Object?>{
        'error': 'file_too_large',
        'limit_bytes': _config.workspaceFileMaxBytes,
      });
    }
    final bytes = await File(filePath).readAsBytes();
    if (_looksBinary(bytes)) {
      return _json(request, HttpStatus.badRequest, <String, Object?>{
        'error': 'binary_file_not_supported',
      });
    }
    return _json(request, HttpStatus.ok, <String, Object?>{
      'path': _relativeWorkspacePath(filePath),
      'content': utf8.decode(bytes, allowMalformed: true),
      'size': stat.size,
      'modified_at': stat.modified.toUtc().toIso8601String(),
    });
  }

  Future<int> _writeWorkspaceFile(HttpRequest request) async {
    if (!_config.workspaceFilesEnabled) {
      return _json(request, HttpStatus.forbidden, <String, Object?>{
        'error': 'workspace_files_disabled',
      });
    }
    if (!_config.workspaceFileWriteEnabled) {
      return _json(request, HttpStatus.forbidden, <String, Object?>{
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
      return _json(request, HttpStatus.badRequest, <String, Object?>{
        'error': 'content_too_large',
        'limit_bytes': _config.workspaceFileMaxBytes,
      });
    }
    final filePath = _resolveWorkspacePath(relative);
    if (filePath == null) {
      return _json(request, HttpStatus.badRequest, <String, Object?>{
        'error': 'path_outside_workspace',
      });
    }
    if (!_workspaceExtensionAllowed(filePath, _workspaceAllowedExtensions())) {
      return _json(request, HttpStatus.forbidden, <String, Object?>{
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
    return _json(request, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'path': _relativeWorkspacePath(filePath),
      'size': stat.size,
      'modified_at': stat.modified.toUtc().toIso8601String(),
    });
  }

  _WebGatewayAuthSession? _authorize(HttpRequest request) {
    if (!_config.authEnabled) {
      final deviceId =
          request.headers.value('x-openhand-device-id') ?? 'anonymous-web';
      return _WebGatewayAuthSession(
        token: 'anonymous',
        source: WebGatewayLoginSource.fromStorage(
          request.headers.value('x-openhand-source') ?? 'WEB_PC',
        ),
        deviceId: deviceId,
        deviceMacAddress: request.headers.value('x-openhand-device-mac') ?? '',
        deviceName: request.headers.value('x-openhand-device-name') ?? '',
        devicePlatform:
            request.headers.value('x-openhand-device-platform') ?? '',
        loginAt: DateTime.now().toUtc(),
        remoteAddress: request.connectionInfo?.remoteAddress.address ?? '',
        userAgent: request.headers.value(HttpHeaders.userAgentHeader) ?? '',
      );
    }
    final authHeader =
        request.headers.value(HttpHeaders.authorizationHeader) ?? '';
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
    HttpRequest request,
    Map<String, Object?> extra,
  ) {
    return <String, Object?>{
      webGatewayMetadataKey: <String, Object?>{
        ...auth.toMetadata(),
        ...extra,
        'request_id': _nextLogId,
        'request_method': request.method,
        'request_path': request.uri.path,
        'captured_at': DateTime.now().toUtc().toIso8601String(),
      },
    };
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

  Future<Map<String, Object?>> _readJsonBody(
    HttpRequest request, {
    int maxBytes = 1024 * 1024,
  }) async {
    final chunks = <int>[];
    await for (final chunk in request) {
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

  Future<int> _json(
    HttpRequest request,
    int statusCode,
    Map<String, Object?> payload,
  ) async {
    final bytes = utf8.encode(jsonEncode(payload));
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
    return bytes.length;
  }

  Future<int> _html(HttpRequest request, String html) async {
    final bytes = utf8.encode(html);
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.html;
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
    return bytes.length;
  }

  void _applyCors(HttpResponse response) {
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    response.headers.set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    );
    response.headers.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'authorization,content-type,x-openhand-device-id,x-openhand-source,x-openhand-device-mac,x-openhand-device-name,x-openhand-device-platform',
    );
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
    return _webClientHtml
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



const String _webClientHtml = r'''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>Web通用消息平台</title>
<style>
:root {
  color-scheme: light dark;
  --primary: {{primary}};
  --on-primary: {{onPrimary}};
  --surface: {{surface}};
  --surface-container: {{surfaceContainer}};
  --on-surface: {{onSurface}};
  --on-surface-variant: {{onSurfaceVariant}};
  --outline: {{outline}};
  --error: {{error}};
  --surface-low: color-mix(in srgb, var(--surface) 88%, white);
  --surface-high: color-mix(in srgb, var(--surface-container) 84%, var(--surface));
  --surface-highest: color-mix(in srgb, var(--surface-container) 92%, var(--primary) 8%);
  --primary-container: color-mix(in srgb, var(--primary) 18%, var(--surface));
  --primary-state: color-mix(in srgb, var(--primary) 12%, transparent);
  --primary-state-strong: color-mix(in srgb, var(--primary) 22%, transparent);
  --error-container: color-mix(in srgb, var(--error) 14%, var(--surface));
  --outline-soft: color-mix(in srgb, var(--outline) 64%, transparent);
  --shadow: rgba(18, 18, 18, .14);
  --elevation-1: 0 2px 8px rgba(18,18,18,.08), 0 1px 3px rgba(18,18,18,.06);
  --elevation-2: 0 10px 24px rgba(18,18,18,.12), 0 3px 8px rgba(18,18,18,.08);
  --elevation-3: 0 18px 44px rgba(18,18,18,.16), 0 8px 18px rgba(18,18,18,.10);
  --radius-xs: 10px;
  --radius-sm: 14px;
  --radius-md: 18px;
  --radius-lg: 24px;
  --radius-xl: 28px;
  --radius-full: 999px;
  --motion: cubic-bezier(.2, 0, 0, 1);
  --motion-spring: cubic-bezier(.2, 1.4, .2, 1);
}
* { box-sizing: border-box; }
html, body { height: 100%; margin: 0; }
body {
  font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background:
    linear-gradient(180deg, color-mix(in srgb, var(--surface) 92%, var(--primary) 8%), var(--surface));
  color: var(--on-surface);
  overflow: hidden;
}
button, input, select, textarea { font: inherit; }
button { border: 0; cursor: pointer; user-select: none; }
button:disabled { cursor: default; opacity: .46; transform: none !important; }
button, .session, .file-row, input, select, textarea, .panel, .msg {
  transition: background .2s var(--motion), border-color .2s var(--motion), box-shadow .2s var(--motion), transform .18s var(--motion-spring), opacity .2s var(--motion);
}
button:not(:disabled):active { transform: scale(.96); }
.app { height: 100%; display: grid; grid-template-columns: minmax(292px, 380px) minmax(0, 1fr); }
.sidebar { min-width: 0; display: flex; flex-direction: column; gap: 10px; padding: 12px; border-right: 1px solid var(--outline-soft); background: var(--surface-high); }
.side-head { padding: 12px; display: flex; gap: 12px; align-items: center; border: 1px solid var(--outline-soft); border-radius: var(--radius-xl); background: var(--surface); box-shadow: var(--elevation-1); }
.brand { width: 44px; height: 44px; border-radius: var(--radius-md); background: var(--primary); color: var(--on-primary); display: grid; place-items: center; font-weight: 850; letter-spacing: 0; box-shadow: var(--elevation-1); }
.side-title { font-size: 17px; font-weight: 780; line-height: 1.2; }
.side-subtitle { font-size: 12px; color: var(--on-surface-variant); }
.toolbar { display: flex; gap: 8px; padding: 4px 2px 0; }
.icon-btn, .text-btn { min-height: 40px; border-radius: var(--radius-full); color: var(--primary); background: var(--primary-state); padding: 0 16px; display: inline-flex; align-items: center; justify-content: center; gap: 8px; font-weight: 680; }
.icon-btn { width: 40px; min-width: 40px; padding: 0; font-size: 20px; }
.icon-btn:not(:disabled):hover, .text-btn:not(:disabled):hover, .session-action:not(:disabled):hover { background: var(--primary-state-strong); box-shadow: var(--elevation-1); }
.text-btn.primary { background: var(--primary); color: var(--on-primary); box-shadow: var(--elevation-1); }
.text-btn.primary:not(:disabled):hover { box-shadow: var(--elevation-2); }
.text-btn.danger { color: var(--error); background: var(--error-container); }
.text-btn.danger.primary { color: white; background: var(--error); }
.session-filters { display: grid; grid-template-columns: 1fr; gap: 8px; padding: 2px 0 6px; }
.session-list { overflow: auto; padding: 0 2px 8px; display: flex; flex-direction: column; gap: 10px; }
.session { text-align: left; padding: 14px; border-radius: var(--radius-lg); background: color-mix(in srgb, var(--surface) 82%, transparent); color: var(--on-surface); border: 1px solid transparent; box-shadow: none; }
.session.active { background: var(--primary-container); border-color: color-mix(in srgb, var(--primary) 44%, var(--outline)); box-shadow: var(--elevation-1); }
.session:hover { background: color-mix(in srgb, var(--primary) 10%, var(--surface)); border-color: color-mix(in srgb, var(--primary) 28%, var(--outline)); }
.session-main { width: 100%; padding: 0; border-radius: 0; background: transparent; color: inherit; text-align: left; }
.session-actions { display: flex; gap: 8px; margin-top: 10px; }
.session-action { min-height: 32px; min-width: 48px; border-radius: var(--radius-full); color: var(--primary); background: var(--primary-state); font-size: 12px; font-weight: 650; }
.session-action.danger { color: var(--error); background: var(--error-container); }
.session-title { font-weight: 760; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.session-meta, .session-preview { color: var(--on-surface-variant); font-size: 12px; margin-top: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.chat { min-width: 0; display: flex; flex-direction: column; background: color-mix(in srgb, var(--surface) 96%, var(--primary) 4%); }
.topbar { min-height: 72px; display: flex; align-items: center; gap: 12px; padding: 10px 18px; border-bottom: 1px solid var(--outline-soft); background: color-mix(in srgb, var(--surface) 86%, transparent); backdrop-filter: blur(18px); }
.topbar-main { flex: 1; min-width: 0; }
.mobile-menu { display: none; }
.thread-title { font-size: 18px; font-weight: 780; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.thread-subtitle { font-size: 12px; color: var(--on-surface-variant); }
.messages { flex: 1; overflow: auto; padding: 20px; display: flex; flex-direction: column; gap: 14px; scroll-behavior: smooth; }
.msg { max-width: min(760px, 86%); padding: 14px 16px; border-radius: var(--radius-xl); box-shadow: var(--elevation-1); white-space: pre-wrap; overflow-wrap: anywhere; line-height: 1.5; animation: messageIn .24s var(--motion-spring); }
.msg.user { align-self: flex-end; border-bottom-right-radius: var(--radius-xs); background: var(--primary); color: var(--on-primary); }
.msg.assistant, .msg.tool, .msg.status { align-self: flex-start; border-bottom-left-radius: var(--radius-xs); background: var(--surface-highest); color: var(--on-surface); border: 1px solid var(--outline-soft); }
.msg .meta { margin-top: 8px; opacity: .72; font-size: 11px; }
.composer { display: grid; grid-template-columns: auto minmax(0, 1fr) auto; gap: 10px; align-items: end; padding: 12px 16px 16px; border-top: 1px solid var(--outline-soft); background: color-mix(in srgb, var(--surface) 90%, transparent); backdrop-filter: blur(18px); }
textarea { min-height: 46px; max-height: 150px; resize: vertical; border: 1px solid var(--outline-soft); border-radius: var(--radius-lg); padding: 12px 14px; background: var(--surface); color: var(--on-surface); outline: none; box-shadow: inset 0 0 0 1px transparent; }
input, select { height: 44px; border: 1px solid var(--outline-soft); border-radius: var(--radius-lg); padding: 0 14px; background: var(--surface); color: var(--on-surface); outline: none; }
textarea:focus, input:focus, select:focus { border-color: var(--primary); box-shadow: 0 0 0 4px color-mix(in srgb, var(--primary) 18%, transparent); }
.empty { flex: 1; display: grid; place-items: center; color: var(--on-surface-variant); text-align: center; padding: 24px; }
.login { height: 100%; display: grid; place-items: center; padding: 18px; }
.panel { width: min(420px, 100%); border: 1px solid var(--outline-soft); border-radius: var(--radius-xl); padding: 24px; background: var(--surface-high); box-shadow: var(--elevation-3); }
.panel h1 { margin: 0 0 8px; font-size: 24px; font-weight: 780; }
.field { display: grid; gap: 7px; margin-top: 14px; }
.field span { font-size: 12px; color: var(--on-surface-variant); font-weight: 640; }
.modal { position: fixed; inset: 0; display: grid; place-items: center; background: rgba(0,0,0,.32); padding: 18px; z-index: 5; opacity: 0; visibility: hidden; pointer-events: none; transition: opacity .22s var(--motion), visibility .22s var(--motion); }
.modal.open { opacity: 1; visibility: visible; pointer-events: auto; }
.modal .panel { width: min(560px, 100%); transform: translateY(12px) scale(.98); transition: transform .28s var(--motion-spring), opacity .22s var(--motion); }
.modal.open .panel { transform: translateY(0) scale(1); }
.modal .panel.wide { width: min(980px, 100%); max-height: min(780px, calc(100vh - 36px)); display: flex; flex-direction: column; }
.dialog-message { margin: 10px 0 0; color: var(--on-surface-variant); line-height: 1.45; }
.dialog-actions { display: flex; gap: 10px; margin-top: 18px; justify-content: flex-end; }
.file-tools { display: grid; grid-template-columns: minmax(180px, 1fr) minmax(180px, 1fr) 140px; gap: 10px; }
.file-layout { min-height: 0; display: grid; grid-template-columns: minmax(220px, 320px) 1fr; gap: 12px; margin-top: 12px; }
.file-list { min-height: 320px; max-height: 58vh; overflow: auto; border: 1px solid var(--outline-soft); border-radius: var(--radius-lg); padding: 8px; background: color-mix(in srgb, var(--surface) 70%, transparent); }
.file-row { width: 100%; min-height: 38px; border-radius: var(--radius-md); background: transparent; color: var(--on-surface); text-align: left; padding: 8px 10px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.file-row:hover { background: var(--primary-state); }
.file-editor { display: flex; min-height: 320px; flex-direction: column; gap: 8px; }
.file-editor textarea { flex: 1; min-height: 320px; max-height: 58vh; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 13px; }
.fab { position: fixed; right: 24px; bottom: 88px; width: 64px; height: 64px; border-radius: var(--radius-lg); background: var(--primary); color: var(--on-primary); font-size: 30px; box-shadow: var(--elevation-3); }
.fab:not(:disabled):hover { transform: translateY(-2px); }
.toast { position: fixed; left: 50%; bottom: 18px; transform: translateX(-50%) translateY(8px); background: color-mix(in srgb, #222 86%, var(--primary)); color: white; border-radius: var(--radius-lg); padding: 11px 16px; opacity: 0; pointer-events: none; transition: opacity .2s var(--motion), transform .2s var(--motion); z-index: 8; max-width: min(640px, calc(100vw - 32px)); box-shadow: var(--elevation-2); }
.toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
.hidden { display: none !important; }
@keyframes messageIn { from { opacity: 0; transform: translateY(8px) scale(.98); } to { opacity: 1; transform: translateY(0) scale(1); } }
@media (max-width: 860px) {
  .app { grid-template-columns: 1fr; }
  .sidebar { position: fixed; inset: 0 auto 0 0; width: min(88vw, 360px); z-index: 3; transform: translateX(-105%); transition: transform .26s var(--motion); box-shadow: var(--elevation-3); border-radius: 0 var(--radius-xl) var(--radius-xl) 0; }
  .sidebar.open { transform: translateX(0); }
  .mobile-menu { display: inline-flex; }
  .messages { padding: 12px; }
  .msg { max-width: 94%; }
  .composer { grid-template-columns: auto 1fr auto; padding: 10px; }
  .file-tools { grid-template-columns: 1fr; }
  .file-layout { grid-template-columns: 1fr; }
  .text-btn span { display: none; }
  .fab { right: 16px; bottom: 82px; }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { transition-duration: .01ms !important; animation-duration: .01ms !important; scroll-behavior: auto !important; }
}
</style>
</head>
<body>
<div id="login" class="login hidden">
  <form class="panel" id="loginForm">
    <h1>Web通用消息平台</h1>
    <p class="side-subtitle">登录后继续访问此设备可见的 OpenHand 线程会话。</p>
    <label class="field"><span>用户名</span><input id="username" autocomplete="username" value="openhand" /></label>
    <label class="field"><span>密码</span><input id="password" type="password" autocomplete="current-password" /></label>
    <button class="text-btn primary" style="width:100%;margin-top:18px" type="submit">登录</button>
  </form>
</div>
<div id="app" class="app hidden">
  <aside id="sidebar" class="sidebar">
    <div class="side-head"><div class="brand">OH</div><div><div class="side-title">Web通用消息平台</div><div id="serviceLine" class="side-subtitle">连接中</div></div></div>
    <div class="toolbar"><button id="refresh" class="icon-btn" title="刷新">↻</button><button id="loadMore" class="text-btn"><span>更多</span></button></div>
    <div class="session-filters"><select id="sourceFilter"><option value="">全部来源</option><option value="WEB_PC">WEB_PC</option><option value="WEB_MOBILE">WEB_MOBILE</option><option value="APP_PC">APP_PC</option><option value="APP_MOBILE">APP_MOBILE</option><option value="APP_TABLET">APP_TABLET</option></select><input id="deviceFilter" placeholder="设备 ID 过滤" /></div>
    <div id="sessions" class="session-list"></div>
  </aside>
  <main class="chat">
    <div class="topbar"><button id="menu" class="icon-btn mobile-menu">☰</button><div class="topbar-main"><div id="threadTitle" class="thread-title">选择一个线程</div><div id="threadSub" class="thread-subtitle">下拉刷新，上滑加载更多线程</div></div><button id="files" class="icon-btn" title="项目文件">▣</button></div>
    <div id="messages" class="messages"><div class="empty">选择或新建一个线程会话。</div></div>
    <form id="composer" class="composer"><input id="file" type="file" multiple hidden /><button id="attach" type="button" class="icon-btn" title="附件">＋</button><textarea id="input" placeholder="输入消息"></textarea><button class="text-btn primary" type="submit">发送</button></form>
  </main>
  <button id="newSession" class="fab" title="新建线程">＋</button>
</div>
<div id="newModal" class="modal"><form id="newForm" class="panel"><h1>新建线程</h1><label class="field"><span>线程名称</span><input id="newTitle" placeholder="新会话" /></label><label class="field"><span>线程模板</span><select id="template"></select></label><label class="field"><span>对话模式</span><select id="mode"></select></label><label class="field"><span>模型</span><select id="model"></select></label><div style="display:flex;gap:10px;margin-top:18px"><button type="button" id="cancelNew" class="text-btn">取消</button><button class="text-btn primary" style="flex:1" type="submit">创建</button></div></form></div>
<div id="fileModal" class="modal"><div class="panel wide"><div style="display:flex;gap:10px;align-items:center"><h1 style="flex:1">项目文件</h1><button id="closeFiles" class="icon-btn">×</button></div><div class="file-tools"><label class="field"><span>路径</span><input id="filePath" value="" /></label><label class="field"><span>搜索</span><input id="fileSearch" placeholder="文件名或相对路径" /></label><label class="field"><span>类型</span><select id="fileType"><option value="all">全部</option><option value="directory">文件夹</option><option value="file">文件</option></select></label></div><div id="filePolicy" class="side-subtitle" style="margin-top:8px"></div><div class="file-layout"><div id="fileList" class="file-list"></div><div class="file-editor"><input id="editingPath" readonly placeholder="选择文本文件" /><textarea id="fileContent" spellcheck="false"></textarea><div style="display:flex;gap:10px"><button id="saveFile" class="text-btn primary" style="flex:1">保存文件</button><button id="reloadFile" class="text-btn">重载</button></div></div></div></div></div>
<div id="dialogModal" class="modal"><form id="dialogForm" class="panel"><h1 id="dialogTitle"></h1><p id="dialogMessage" class="dialog-message"></p><label id="dialogInputWrap" class="field hidden"><span id="dialogInputLabel"></span><input id="dialogInput" /></label><div class="dialog-actions"><button type="button" id="dialogCancel" class="text-btn">取消</button><button id="dialogOk" class="text-btn primary" type="submit">确认</button></div></form></div>
<div id="toast" class="toast"></div>
<script>
const state = { meta:null, token:localStorage.getItem('oh_token') || '', deviceId: localStorage.getItem('oh_device_id') || '', source:'WEB_PC', sessionSource:'', sessionDevice:'', sessionManagement:true, page:1, hasMore:true, sessions:[], active:null, poll:null, modelKey:'', filePath:'', fileSearch:'', fileType:'all', editingPath:'', workspaceFiles:{enabled:true,write:true,maxBytes:1048576,allowedExtensions:[]} };
if(!state.deviceId){ state.deviceId = crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random(); localStorage.setItem('oh_device_id', state.deviceId); }
function detectSource(){ const w = Math.min(innerWidth, screen.width || innerWidth); state.source = w < 760 ? 'WEB_MOBILE' : 'WEB_PC'; }
function headers(){ const h = {'content-type':'application/json','x-openhand-device-id':state.deviceId,'x-openhand-source':state.source,'x-openhand-device-platform':navigator.platform || ''}; if(state.token) h.authorization = 'Bearer '+state.token; return h; }
function toast(msg){ const el=document.getElementById('toast'); el.textContent=msg; el.classList.add('show'); setTimeout(()=>el.classList.remove('show'),2200); }
function openDialog(options){ return new Promise(resolve=>{ const modal=document.getElementById('dialogModal'); const form=document.getElementById('dialogForm'); const input=document.getElementById('dialogInput'); const wrap=document.getElementById('dialogInputWrap'); const ok=document.getElementById('dialogOk'); document.getElementById('dialogTitle').textContent=options.title||'确认'; document.getElementById('dialogMessage').textContent=options.message||''; document.getElementById('dialogInputLabel').textContent=options.inputLabel||''; input.value=options.value||''; input.placeholder=options.placeholder||''; wrap.classList.toggle('hidden',!options.input); ok.textContent=options.confirmText||'确认'; ok.className='text-btn primary'+(options.danger?' danger':''); const close=value=>{ modal.classList.remove('open'); form.onsubmit=null; document.getElementById('dialogCancel').onclick=null; resolve(value); }; document.getElementById('dialogCancel').onclick=()=>close(null); form.onsubmit=e=>{ e.preventDefault(); if(options.requiredText && input.value!==options.requiredText){ toast('请输入 '+options.requiredText+' 以确认'); input.focus(); return; } close(options.input?input.value:true); }; modal.classList.add('open'); setTimeout(()=> options.input ? input.focus() : ok.focus(), 0); }); }
async function api(path, opts={}){ const res = await fetch(path,{...opts,headers:{...headers(),...(opts.headers||{})}}); const json = await res.json().catch(()=>({})); if(!res.ok) throw Object.assign(new Error(json.message||json.error||res.statusText),{status:res.status,json}); return json; }
async function boot(){ detectSource(); state.meta = await api('/api/meta'); applyMeta(); if(state.meta.service.auth_enabled && !state.token){ showLogin(); } else { if(!state.token) await anonymousLogin(); showApp(); await loadSessions(true); } }
function applyMeta(){ document.getElementById('serviceLine').textContent = state.meta.service.auth_enabled ? '鉴权已开启' : '免鉴权本地访问'; state.sessionManagement=state.meta.service.session_management_enabled!==false; const wf=state.meta.workspace_files||{}; state.workspaceFiles={enabled:wf.enabled!==false,write:wf.write_enabled!==false,maxBytes:wf.max_file_bytes||1048576,allowedExtensions:wf.allowed_extensions||[]}; const filesBtn=document.getElementById('files'); filesBtn.disabled=!state.workspaceFiles.enabled; fill('template', state.meta.templates.map(t=>[t.id,t.name])); fill('mode', state.meta.conversation_modes.map(m=>[m,m])); fill('model', state.meta.models.map(m=>[m.key,m.label])); state.modelKey = state.meta.models[0]?.key || ''; syncFilePolicy(); }
function fill(id, rows){ const el=document.getElementById(id); el.innerHTML=''; rows.forEach(([v,l])=>{ const o=document.createElement('option'); o.value=v; o.textContent=l; el.appendChild(o); }); }
function showLogin(){ document.getElementById('login').classList.remove('hidden'); document.getElementById('app').classList.add('hidden'); }
async function anonymousLogin(){ const j = await api('/api/login',{method:'POST',body:JSON.stringify(devicePayload())}); state.token=j.token; if(j.token !== 'anonymous') localStorage.setItem('oh_token',j.token); }
function showApp(){ document.getElementById('login').classList.add('hidden'); document.getElementById('app').classList.remove('hidden'); }
function devicePayload(){ return {source:state.source,device_id:state.deviceId,device_name:navigator.userAgent,device_platform:navigator.platform || '',device_mac_address:''}; }
document.getElementById('loginForm').onsubmit = async e => { e.preventDefault(); try{ const j=await api('/api/login',{method:'POST',body:JSON.stringify({...devicePayload(),username:username.value,password:password.value})}); state.token=j.token; localStorage.setItem('oh_token',j.token); showApp(); await loadSessions(true); }catch(err){ toast('登录失败'); }};
async function loadSessions(reset=false){ if(reset){state.page=1;state.sessions=[];state.hasMore=true;} if(!state.hasMore) return; state.sessionSource=sourceFilter.value; state.sessionDevice=deviceFilter.value.trim(); const params=new URLSearchParams({page:String(state.page),page_size:'10'}); if(state.sessionSource) params.set('source',state.sessionSource); if(state.sessionDevice) params.set('device_id',state.sessionDevice); const j=await api('/api/sessions?'+params.toString()); state.sessions.push(...j.items); state.hasMore=j.has_more; state.page++; renderSessions(); }
function renderSessions(){ const box=document.getElementById('sessions'); box.innerHTML=''; if(!state.sessions.length){ const empty=document.createElement('div'); empty.className='side-subtitle'; empty.style.padding='12px'; empty.textContent='没有匹配的线程'; box.appendChild(empty); return; } state.sessions.forEach(s=>{ const row=document.createElement('div'); row.className='session'+(state.active===s.id?' active':''); const main=document.createElement('button'); main.className='session-main'; main.innerHTML=`<div class="session-title"></div><div class="session-preview"></div><div class="session-meta"></div>`; main.children[0].textContent=s.title; main.children[1].textContent=s.last_message_preview||'暂无消息'; main.children[2].textContent=`${s.source||'UNKNOWN'} · ${s.device_id||'unknown'} · ${s.message_count} 条 · ${s.send_phase}`; main.onclick=()=>openSession(s.id); row.append(main); if(state.sessionManagement){ const actions=document.createElement('div'); actions.className='session-actions'; const rename=document.createElement('button'); rename.className='session-action'; rename.textContent='改名'; rename.onclick=()=>renameSession(s); const del=document.createElement('button'); del.className='session-action danger'; del.textContent='删除'; del.onclick=()=>deleteSession(s); actions.append(rename,del); row.append(actions); } box.appendChild(row); }); }
async function renameSession(session){ const title=await openDialog({title:'重命名线程',message:'更新 Web 侧展示的线程标题。',input:true,inputLabel:'线程名称',value:session.title||'',confirmText:'保存'}); if(title===null) return; const next=title.trim(); if(!next) return toast('标题不能为空'); try{ const j=await api('/api/sessions/'+session.id,{method:'PATCH',body:JSON.stringify({title:next})}); const idx=state.sessions.findIndex(s=>s.id===session.id); if(idx>=0) state.sessions[idx]=j.session; if(state.active===session.id) document.getElementById('threadTitle').textContent=j.session.title; renderSessions(); toast('线程已重命名'); }catch(err){ toast(err.message); } }
async function deleteSession(session){ const typed=await openDialog({title:'删除线程',message:'删除线程「'+session.title+'」不可恢复。输入 DELETE 确认。',input:true,inputLabel:'确认文本',placeholder:'DELETE',confirmText:'删除',requiredText:'DELETE',danger:true}); if(typed===null) return; try{ await api('/api/sessions/'+session.id,{method:'DELETE'}); state.sessions=state.sessions.filter(s=>s.id!==session.id); if(state.active===session.id){ state.active=null; clearInterval(state.poll); document.getElementById('threadTitle').textContent='选择一个线程'; document.getElementById('threadSub').textContent='线程已删除'; document.getElementById('messages').innerHTML='<div class="empty">线程已删除，请选择其他会话。</div>'; } renderSessions(); toast('线程已删除'); }catch(err){ toast(err.message); } }
async function openSession(id){ state.active=id; document.getElementById('sidebar').classList.remove('open'); renderSessions(); await refreshThread(); clearInterval(state.poll); state.poll=setInterval(refreshThread,1800); }
async function refreshThread(){ if(!state.active) return; try{ const s=await api('/api/sessions/'+state.active); document.getElementById('threadTitle').textContent=s.session.title; document.getElementById('threadSub').textContent=`${s.session.template_name} · ${s.runtime.send_phase}`; const j=await api('/api/sessions/'+state.active+'/messages?limit=120&offset=0'); renderMessages(j.items); }catch(err){ if(err.status===404){ toast('线程已在 APP 端删除'); state.active=null; clearInterval(state.poll); await loadSessions(true); document.getElementById('messages').innerHTML='<div class="empty">线程已删除，请选择其他会话。</div>'; } } }
function renderMessages(items){ const box=document.getElementById('messages'); box.innerHTML=''; if(!items.length){ box.innerHTML='<div class="empty">还没有消息。</div>'; return; } items.forEach(m=>{ const div=document.createElement('div'); const cls=m.role==='user'?'user':(m.kind||'assistant'); div.className='msg '+cls; const text=document.createElement('div'); text.textContent=m.content||' '; const meta=document.createElement('div'); meta.className='meta'; meta.textContent=`${m.kind} · ${new Date(m.created_at).toLocaleString()}`; div.append(text,meta); box.appendChild(div); }); box.scrollTop=box.scrollHeight; }
document.getElementById('refresh').onclick=()=>loadSessions(true).catch(e=>toast(e.message));
document.getElementById('loadMore').onclick=()=>loadSessions(false).catch(e=>toast(e.message));
document.getElementById('sourceFilter').onchange=()=>loadSessions(true).catch(e=>toast(e.message));
document.getElementById('deviceFilter').onkeydown=e=>{ if(e.key==='Enter') loadSessions(true).catch(err=>toast(err.message)); };
document.getElementById('menu').onclick=()=>document.getElementById('sidebar').classList.toggle('open');
document.getElementById('newSession').onclick=()=>document.getElementById('newModal').classList.add('open');
document.getElementById('cancelNew').onclick=()=>document.getElementById('newModal').classList.remove('open');
document.getElementById('newForm').onsubmit=async e=>{ e.preventDefault(); try{ const j=await api('/api/sessions',{method:'POST',body:JSON.stringify({title:newTitle.value,template_id:template.value,mode:mode.value==='normal'?'chat':'chat'})}); document.getElementById('newModal').classList.remove('open'); await loadSessions(true); await openSession(j.session.id); }catch(err){ toast(err.message); }};
document.getElementById('files').onclick=()=>{ if(!state.workspaceFiles.enabled) return toast('项目文件访问已关闭'); document.getElementById('fileModal').classList.add('open'); syncFilePolicy(); loadFiles(state.filePath).catch(e=>toast(e.message)); };
document.getElementById('closeFiles').onclick=()=>document.getElementById('fileModal').classList.remove('open');
document.getElementById('filePath').onkeydown=e=>{ if(e.key==='Enter') loadFiles(filePath.value).catch(err=>toast(err.message)); };
document.getElementById('fileSearch').onkeydown=e=>{ if(e.key==='Enter'){ state.fileSearch=fileSearch.value.trim(); loadFiles(state.filePath).catch(err=>toast(err.message)); }};
document.getElementById('fileType').onchange=()=>{ state.fileType=fileType.value||'all'; loadFiles(state.filePath).catch(err=>toast(err.message)); };
document.getElementById('reloadFile').onclick=()=> state.editingPath ? readFile(state.editingPath).catch(e=>toast(e.message)) : loadFiles(state.filePath).catch(e=>toast(e.message));
document.getElementById('saveFile').onclick=async()=>{ if(!state.workspaceFiles.write) return toast('当前为只读模式'); if(!state.editingPath) return toast('请选择文件'); try{ await api('/api/workspace/file',{method:'PUT',body:JSON.stringify({path:state.editingPath,content:fileContent.value})}); toast('文件已保存'); }catch(err){ toast(err.message); } };
function bytesLabel(bytes){ if(bytes<1024) return bytes+' B'; const kb=bytes/1024; if(kb<1024) return kb.toFixed(1)+' KB'; const mb=kb/1024; return mb.toFixed(1)+' MB'; }
function syncFilePolicy(){ const ext=state.workspaceFiles.allowedExtensions.length?state.workspaceFiles.allowedExtensions.join(', '):'全部文本'; filePolicy.textContent=`${state.workspaceFiles.write?'读写':'只读'} · 单文件 ${bytesLabel(state.workspaceFiles.maxBytes)} · 扩展名 ${ext}`; saveFile.disabled=!state.workspaceFiles.write||!state.editingPath; fileContent.readOnly=!state.workspaceFiles.write; }
async function loadFiles(path=''){ state.fileSearch=fileSearch.value.trim(); state.fileType=fileType.value||'all'; const params=new URLSearchParams({path:path||'',q:state.fileSearch,type:state.fileType}); const j=await api('/api/workspace/files?'+params.toString()); state.filePath=j.path||''; filePath.value=state.filePath; renderFiles(j); syncFilePolicy(); }
function parentPath(path){ const parts=String(path||'').split('/').filter(Boolean); parts.pop(); return parts.join('/'); }
function renderFiles(data){ const box=document.getElementById('fileList'); box.innerHTML=''; if(data.path){ const up=document.createElement('button'); up.className='file-row'; up.textContent='..'; up.onclick=()=>loadFiles(parentPath(data.path)).catch(e=>toast(e.message)); box.appendChild(up); } if(!data.items.length){ const empty=document.createElement('div'); empty.className='side-subtitle'; empty.style.padding='12px'; empty.textContent='没有匹配的文件'; box.appendChild(empty); return; } data.items.forEach(item=>{ const b=document.createElement('button'); b.className='file-row'; b.textContent=(item.type==='directory'?'▸ ':'  ')+item.name+(item.type==='file'&&item.editable===false?' · 过大':''); b.title=item.path; b.onclick=()=> item.type==='directory' ? loadFiles(item.path).catch(e=>toast(e.message)) : readFile(item.path).catch(e=>toast(e.message)); box.appendChild(b); }); }
async function readFile(path){ const j=await api('/api/workspace/file?path='+encodeURIComponent(path)); state.editingPath=j.path; editingPath.value=j.path; fileContent.value=j.content||''; syncFilePolicy(); }
document.getElementById('attach').onclick=()=>document.getElementById('file').click();
document.getElementById('composer').onsubmit=async e=>{ e.preventDefault(); if(!state.active) return toast('请先选择线程'); const files=[...document.getElementById('file').files]; const attachments=[]; for(const f of files){ const data=await new Promise((resolve,reject)=>{ const r=new FileReader(); r.onload=()=>resolve(String(r.result).split(',')[1]||''); r.onerror=reject; r.readAsDataURL(f); }); attachments.push({name:f.name,mime_type:f.type,data_base64:data}); } try{ await api('/api/sessions/'+state.active+'/messages',{method:'POST',body:JSON.stringify({content:input.value,attachments,mode:mode.value,model_key:model.value})}); input.value=''; file.value=''; await refreshThread(); }catch(err){ toast(err.message); }};
addEventListener('resize', detectSource);
boot().catch(err=>{ console.error(err); toast(err.message || '启动失败'); });
</script>
</body>
</html>''';

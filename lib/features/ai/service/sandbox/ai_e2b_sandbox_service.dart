import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../../app/support/system_proxy.dart';
import '../../../../shared/net/abortable_http_request.dart';
import '../../../../shared/net/http_response_utils.dart';
import '../../../../shared/net/network_limits.dart';
import '../../../../shared/util/text_clip.dart';
import '../../model/ai_command_rule.dart';
import '../../model/ai_sandbox_settings.dart';

const int _e2bEnvdPort = 49983;
const int _e2bMaxControlResponseBytes = 2 * 1024 * 1024;
const int _e2bMaxStreamFrameBytes = 8 * 1024 * 1024;
const Duration _e2bResponseIdleTimeout = Duration(seconds: 75);
const Duration _e2bDefaultRequestTimeout = Duration(seconds: 60);
const Set<String> _e2bSharedSandboxDomains = <String>{
  'e2b.app',
  'e2b.dev',
  'e2b.pro',
  'e2b-staging.dev',
};

class AiE2bCommandResult {
  const AiE2bCommandResult({
    required this.exitCode,
    required this.exited,
    this.error = '',
  });

  final int exitCode;
  final bool exited;
  final String error;
}

class AiE2bCommandHandle {
  const AiE2bCommandHandle._({
    required this.sandboxId,
    required this.pid,
    required this.result,
    required this._write,
    required this._kill,
    required this._disconnect,
  });

  final String sandboxId;
  final int pid;
  final Future<AiE2bCommandResult> result;
  final Future<void> Function(List<int> bytes) _write;
  final Future<void> Function() _kill;
  final Future<void> Function() _disconnect;

  Future<void> write(List<int> bytes) => _write(bytes);
  Future<void> kill() => _kill();
  Future<void> disconnect() => _disconnect();
}

class AiE2bSandboxService {
  AiE2bSandboxService({required AiSandboxSettings settings})
    : _settings = settings,
      _client = _createClient(settings.e2b.proxy);

  AiSandboxSettings _settings;
  http.Client _client;
  _E2bSandbox? _sandbox;
  Future<_E2bSandbox>? _sandboxStart;
  bool _disposed = false;

  AiSandboxSettings get settings => _settings;

  set settings(AiSandboxSettings value) {
    if (_settings == value) return;
    final previous = _settings;
    _settings = value;
    if (previous.e2b == value.e2b &&
        previous.allowedDomains == value.allowedDomains &&
        previous.deniedDomains == value.deniedDomains &&
        previous.allowNetworkWhenNoDomainRules ==
            value.allowNetworkWhenNoDomainRules) {
      return;
    }
    final oldClient = _client;
    final sandbox = _sandbox;
    final sandboxStart = _sandboxStart;
    _sandbox = null;
    _sandboxStart = null;
    _client = _createClient(value.e2b.proxy);
    unawaited(
      _retireSandbox(
        sandbox,
        sandboxStart: sandboxStart,
        client: oldClient,
        settings: previous,
      ),
    );
  }

  String get configurationIssue {
    final config = settings.e2b;
    if (config.apiKey.trim().isEmpty) return '缺少 E2B API Key。';
    if (config.templateId.trim().isEmpty) return '缺少 E2B Template ID。';
    if (config.timeoutSeconds > 0x7fffffff) {
      return 'E2B timeout 不能超过 int32 上限。';
    }
    if (config.domain.trim().isEmpty) return 'E2B Domain 不能为空。';
    if (config.apiUrl.isNotEmpty && !_isHttpUrl(config.apiUrl)) {
      return 'E2B API URL 必须是有效的 HTTP(S) URL。';
    }
    if (config.sandboxUrl.isNotEmpty && !_isHttpUrl(config.sandboxUrl)) {
      return 'E2B Sandbox URL 必须是有效的 HTTP(S) URL。';
    }
    if (config.proxy.isNotEmpty && !_isHttpUrl(config.proxy)) {
      return 'E2B 客户端代理必须是有效的 HTTP(S) URL。';
    }
    if (!_isDomain(config.domain)) return 'E2B Domain 必须是有效的主机名。';
    if (Duration(milliseconds: config.requestTimeoutMs) >
        kOpenHandMaxNetworkOperationTimeout) {
      return 'E2B 请求超时不能超过 24 小时。';
    }
    if (config.autoResumeEnabled &&
        config.autoPause &&
        !config.autoPauseMemory) {
      return 'autoResume 与文件系统快照模式不能同时启用。';
    }
    if (config.commandWorkingDirectory.trim().isEmpty) {
      return 'E2B 命令工作目录不能为空。';
    }
    if (config.egressProxyAddress.isEmpty &&
        (config.egressProxyUsername.isNotEmpty ||
            config.egressProxyPassword.isNotEmpty)) {
      return 'E2B egressProxy 配置凭据时必须同时填写 address。';
    }
    if (config.egressProxyAddress.isNotEmpty &&
        !_isHostPort(config.egressProxyAddress)) {
      return 'E2B egressProxy.address 必须使用 host:port 格式。';
    }
    if (utf8ByteLength(config.egressProxyUsername) > 255 ||
        utf8ByteLength(config.egressProxyPassword) > 255) {
      return 'E2B egressProxy 用户名和密码不能超过 255 字节。';
    }
    for (final value in config.denyOut) {
      if (!_isIpOrCidr(value)) return 'E2B denyOut 仅支持 IP 或 CIDR：$value';
    }
    final networkIssue = _validateNetworkRules(config.networkRules);
    if (networkIssue.isNotEmpty) return networkIssue;
    final iamIssue = _validateIamTokens(config.iamTokens);
    if (iamIssue.isNotEmpty) return iamIssue;
    for (final mount in config.volumeMounts) {
      if (mount.name.trim().isEmpty || mount.path.trim().isEmpty) {
        return 'E2B volumeMounts 的 name 与 path 不能为空。';
      }
    }
    for (final rule in settings.allowedDomains) {
      if (rule.matchMode == AiCommandMatchMode.regex) {
        return 'E2B allowOut 不支持正则规则：${rule.pattern}';
      }
    }
    for (final rule in settings.deniedDomains) {
      if (rule.matchMode == AiCommandMatchMode.regex ||
          !_isIpOrCidr(rule.pattern)) {
        return 'E2B denyOut 仅支持 IP 或 CIDR：${rule.pattern}';
      }
    }
    return '';
  }

  Future<int> probe() async {
    final issue = configurationIssue;
    if (issue.isNotEmpty) throw StateError(issue);
    final uri = _apiUri(
      '/v2/sandboxes',
    ).replace(queryParameters: const <String, String>{'limit': '1'});
    final response = await _send(
      http.Request('GET', uri)..headers.addAll(_apiHeaders()),
    );
    final body = await _readControlBody(response);
    _ensureSuccess(response.statusCode, body, uri);
    final decoded = jsonDecode(body);
    return decoded is List ? decoded.length : 0;
  }

  Future<AiE2bCommandHandle> startCommand({
    required String command,
    required String workingDirectory,
    required Map<String, String> environment,
    required int timeoutMs,
    required bool keepStdinOpen,
    void Function(String chunk)? onStdout,
    void Function(String chunk)? onStderr,
  }) async {
    if (_disposed) throw StateError('E2B 沙箱服务已关闭。');
    final sandbox = await _ensureSandbox();
    if (_disposed) throw StateError('E2B 沙箱服务已关闭。');
    final streamAbort = Completer<void>();
    final started = Completer<int>();
    final result = Completer<AiE2bCommandResult>();
    final request =
        http.Request('POST', _sandboxUri('/process.Process/Start', sandbox))
          ..headers.addAll(
            _envdHeaders(
              sandbox,
              streaming: true,
              timeoutMs: timeoutMs,
              user: settings.e2b.commandUser,
            ),
          )
          ..bodyBytes = _encodeConnectJsonMessage(<String, Object?>{
            'process': <String, Object?>{
              'cmd': '/bin/bash',
              'args': <String>['-l', '-c', command],
              'envs': <String, String>{
                ...settings.e2b.environmentVariables,
                ...environment,
              },
              'cwd': workingDirectory,
            },
            'stdin': keepStdinOpen,
          });
    try {
      final response = await _send(request, cancelSignal: streamAbort.future);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 404 || response.statusCode == 502) {
          _dropSandbox(sandbox);
        }
        final body = await _readControlBody(response);
        _ensureSuccess(response.statusCode, body, request.url);
      }
      unawaited(
        _consumeCommandStream(
          response.stream,
          started: started,
          result: result,
          onStdout: onStdout,
          onStderr: onStderr,
        ).catchError((Object error, StackTrace stack) {
          if (!started.isCompleted) started.completeError(error, stack);
          if (!result.isCompleted) result.completeError(error, stack);
          if (!streamAbort.isCompleted) _dropSandbox(sandbox);
        }),
      );
      final pid = await started.future.timeout(
        _requestTimeout(),
        onTimeout: () {
          if (!streamAbort.isCompleted) streamAbort.complete();
          throw TimeoutException('E2B 命令启动超时。');
        },
      );
      return AiE2bCommandHandle._(
        sandboxId: sandbox.id,
        pid: pid,
        result: result.future,
        write: (bytes) => _sendInput(sandbox, pid, bytes),
        kill: () => _sendSignal(sandbox, pid),
        disconnect: () async {
          if (!streamAbort.isCompleted) streamAbort.complete();
        },
      );
    } catch (_) {
      if (!streamAbort.isCompleted) streamAbort.complete();
      rethrow;
    }
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    final pending = _sandboxStart;
    _sandboxStart = null;
    final sandbox = _sandbox;
    _sandbox = null;
    if (sandbox != null) {
      await _deleteSandbox(sandbox);
    } else if (pending != null) {
      try {
        await _deleteSandbox(await pending);
      } catch (_) {
        // 启动失败时没有可回收的远端沙箱。
      }
    }
    _client.close();
  }

  Future<_E2bSandbox> _ensureSandbox() {
    final existing = _sandbox;
    if (existing != null) return Future<_E2bSandbox>.value(existing);
    final pending = _sandboxStart;
    if (pending != null) return pending;
    final start = _createSandbox();
    _sandboxStart = start;
    return start.then(
      (sandbox) {
        if (identical(_sandboxStart, start)) {
          _sandboxStart = null;
          _sandbox = sandbox;
        }
        return sandbox;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_sandboxStart, start)) _sandboxStart = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  Future<_E2bSandbox> _createSandbox() async {
    final issue = configurationIssue;
    if (issue.isNotEmpty) throw StateError(issue);
    final config = settings.e2b;
    final allowOut = <String>{
      ...config.allowOut,
      ...settings.allowedDomains.map((rule) => rule.pattern.trim()),
    }..removeWhere((item) => item.isEmpty);
    final denyOut = <String>{
      ...config.denyOut,
      ...settings.deniedDomains.map((rule) => rule.pattern.trim()),
    }..removeWhere((item) => item.isEmpty);
    final hasNetworkRules =
        settings.allowedDomains.isNotEmpty ||
        settings.deniedDomains.isNotEmpty ||
        config.allowOut.isNotEmpty ||
        config.denyOut.isNotEmpty ||
        config.networkRules.isNotEmpty;
    final allowInternet =
        config.allowInternetAccess &&
        (hasNetworkRules || settings.allowNetworkWhenNoDomainRules);
    final network = <String, Object?>{
      'allowPublicTraffic': config.allowPublicTraffic,
      'allowOut': allowOut.toList(growable: false),
      'denyOut': denyOut.toList(growable: false),
      if (config.egressProxyAddress.isNotEmpty)
        'egressProxy': <String, Object?>{
          'address': config.egressProxyAddress,
          if (config.egressProxyUsername.isNotEmpty)
            'username': config.egressProxyUsername,
          if (config.egressProxyPassword.isNotEmpty)
            'password': config.egressProxyPassword,
        },
      if (config.maskRequestHost.isNotEmpty)
        'maskRequestHost': config.maskRequestHost,
      if (config.networkRules.isNotEmpty) 'rules': config.networkRules,
    };
    final payload = <String, Object?>{
      'templateID': config.templateId,
      'timeout': config.timeoutSeconds,
      'autoPause': config.autoPause,
      'autoPauseMemory': config.autoPauseMemory,
      'autoResume': <String, Object?>{'enabled': config.autoResumeEnabled},
      'secure': config.secure,
      'allow_internet_access': allowInternet,
      'network': network,
      'metadata': config.metadata,
      'envVars': config.environmentVariables,
      'mcp': config.mcp,
      'iam': <String, Object?>{'tokens': config.iamTokens},
      'volumeMounts': config.volumeMounts
          .map((mount) => mount.toJson())
          .toList(growable: false),
    };
    final uri = _apiUri('/sandboxes');
    final response = await _send(
      http.Request('POST', uri)
        ..headers.addAll(<String, String>{
          ..._apiHeaders(),
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode(payload),
    );
    final body = await _readControlBody(response);
    _ensureSuccess(response.statusCode, body, uri);
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('E2B 创建响应格式无效。');
    final json = decoded.cast<String, Object?>();
    final id = '${json['sandboxID'] ?? ''}'.trim();
    if (id.isEmpty) throw const FormatException('E2B 创建响应缺少 sandboxID。');
    return _E2bSandbox(id: id, accessToken: '${json['envdAccessToken'] ?? ''}');
  }

  Future<void> _sendInput(_E2bSandbox sandbox, int pid, List<int> bytes) async {
    await _sendEnvdUnary(
      sandbox,
      '/process.Process/SendInput',
      <String, Object?>{
        'process': <String, Object?>{'pid': pid},
        'input': <String, Object?>{'stdin': base64Encode(bytes)},
      },
    );
  }

  Future<void> _sendSignal(_E2bSandbox sandbox, int pid) async {
    await _sendEnvdUnary(
      sandbox,
      '/process.Process/SendSignal',
      <String, Object?>{
        'process': <String, Object?>{'pid': pid},
        'signal': 'SIGNAL_SIGKILL',
      },
    );
  }

  Future<void> _sendEnvdUnary(
    _E2bSandbox sandbox,
    String path,
    Map<String, Object?> body,
  ) async {
    final uri = _sandboxUri(path, sandbox);
    final response = await _send(
      http.Request('POST', uri)
        ..headers.addAll(_envdHeaders(sandbox))
        ..body = jsonEncode(body),
    );
    final responseBody = await _readControlBody(response);
    _ensureSuccess(response.statusCode, responseBody, uri);
  }

  Future<void> _consumeCommandStream(
    Stream<List<int>> stream, {
    required Completer<int> started,
    required Completer<AiE2bCommandResult> result,
    void Function(String chunk)? onStdout,
    void Function(String chunk)? onStderr,
  }) async {
    final buffer = <int>[];
    await for (final chunk in stream.timeout(_e2bResponseIdleTimeout)) {
      buffer.addAll(chunk);
      while (buffer.length >= 5) {
        final flags = buffer[0];
        final length =
            (buffer[1] << 24) |
            (buffer[2] << 16) |
            (buffer[3] << 8) |
            buffer[4];
        if (flags > 3 || length < 0 || length > _e2bMaxStreamFrameBytes) {
          throw const FormatException('E2B Connect 流帧格式无效。');
        }
        if (buffer.length < length + 5) break;
        final payload = Uint8List.fromList(buffer.sublist(5, length + 5));
        buffer.removeRange(0, length + 5);
        final decoded = jsonDecode(utf8.decode(payload));
        if (decoded is! Map) continue;
        final json = decoded.cast<String, Object?>();
        if ((flags & 2) != 0) {
          final error = json['error'];
          if (error != null) throw StateError('E2B Connect 错误：$error');
          continue;
        }
        _consumeCommandEvent(
          json,
          started: started,
          result: result,
          onStdout: onStdout,
          onStderr: onStderr,
        );
      }
    }
    if (buffer.isNotEmpty) {
      final text = utf8.decode(buffer, allowMalformed: true).trim();
      if (text.isNotEmpty) {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          _consumeCommandEvent(
            decoded.cast<String, Object?>(),
            started: started,
            result: result,
            onStdout: onStdout,
            onStderr: onStderr,
          );
        }
      }
    }
    if (!result.isCompleted) {
      throw StateError('E2B 命令流在返回结束事件前中断。');
    }
  }

  void _consumeCommandEvent(
    Map<String, Object?> json, {
    required Completer<int> started,
    required Completer<AiE2bCommandResult> result,
    void Function(String chunk)? onStdout,
    void Function(String chunk)? onStderr,
  }) {
    final rawEvent = json['event'];
    if (rawEvent is! Map) return;
    final event = rawEvent.cast<String, Object?>();
    final rawStart = event['start'];
    if (rawStart is Map && !started.isCompleted) {
      final pid = int.tryParse('${rawStart['pid'] ?? ''}');
      if (pid != null) started.complete(pid);
    }
    final rawData = event['data'];
    if (rawData is Map) {
      final data = rawData.cast<String, Object?>();
      final stdout = _decodeOutput(data['stdout']);
      final stderr = _decodeOutput(data['stderr']);
      if (stdout.isNotEmpty) onStdout?.call(stdout);
      if (stderr.isNotEmpty) onStderr?.call(stderr);
    }
    final rawEnd = event['end'];
    if (rawEnd is Map && !result.isCompleted) {
      final end = rawEnd.cast<String, Object?>();
      result.complete(
        AiE2bCommandResult(
          exitCode:
              int.tryParse('${end['exitCode'] ?? end['exit_code'] ?? -1}') ??
              -1,
          exited: end['exited'] != false,
          error: '${end['error'] ?? ''}',
        ),
      );
    }
  }

  String _decodeOutput(Object? value) {
    if (value is! String || value.isEmpty) return '';
    try {
      return utf8.decode(base64Decode(value), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  Future<http.StreamedResponse> _send(
    http.Request request, {
    Future<void>? cancelSignal,
  }) {
    return sendAbortableHttpRequest(
      client: _client,
      request: request,
      connectionTimeout: _requestTimeout(),
      cancelSignal: cancelSignal,
    );
  }

  Future<String> _readControlBody(http.StreamedResponse response) async {
    final bytes = await readBoundedByteStream(
      response.stream,
      maxBytes: _e2bMaxControlResponseBytes,
      idleTimeout: _e2bResponseIdleTimeout,
      totalTimeout: Duration(milliseconds: _requestTimeout().inMilliseconds),
    );
    return utf8.decode(bytes, allowMalformed: true);
  }

  Map<String, String> _apiHeaders() => <String, String>{
    ...settings.e2b.apiHeaders,
    'X-API-Key': settings.e2b.apiKey,
    'Accept': 'application/json',
  };

  Map<String, String> _envdHeaders(
    _E2bSandbox sandbox, {
    bool streaming = false,
    int? timeoutMs,
    String user = '',
  }) => <String, String>{
    'Connect-Protocol-Version': '1',
    'Content-Type': streaming ? 'application/connect+json' : 'application/json',
    'E2b-Sandbox-Id': sandbox.id,
    'E2b-Sandbox-Port': '$_e2bEnvdPort',
    if (sandbox.accessToken.isNotEmpty) 'X-Access-Token': sandbox.accessToken,
    if (streaming) 'Keepalive-Ping-Interval': '50',
    if (timeoutMs != null && timeoutMs > 0) 'Connect-Timeout-Ms': '$timeoutMs',
    if (user.trim().isNotEmpty)
      'Authorization': 'Basic ${base64Encode(utf8.encode('${user.trim()}:'))}',
  };

  Uri _apiUri(String path) => _resolvePath(settings.e2b.resolvedApiUri, path);

  Duration _requestTimeout([AiSandboxSettings? source]) {
    final timeoutMs = (source ?? settings).e2b.requestTimeoutMs;
    return timeoutMs <= 0
        ? _e2bDefaultRequestTimeout
        : Duration(milliseconds: timeoutMs);
  }

  Uri _sandboxUri(String path, _E2bSandbox sandbox) {
    final config = settings.e2b;
    final customUrl = config.sandboxUrl.trim();
    if (customUrl.isNotEmpty) {
      return _resolvePath(config.resolvedSandboxUri, path);
    }
    final domain = config.domain.trim();
    final host = _e2bSharedSandboxDomains.contains(domain.toLowerCase())
        ? 'sandbox.$domain'
        : '$_e2bEnvdPort-${sandbox.id}.$domain';
    return _resolvePath(Uri(scheme: 'https', host: host), path);
  }

  Uri _resolvePath(Uri base, String path) {
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$prefix$path', query: '', fragment: '');
  }

  void _ensureSuccess(int statusCode, String body, Uri uri) {
    if (statusCode >= 200 && statusCode < 300) return;
    var message = body.trim();
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        message = '${decoded['message']}';
      }
    } catch (_) {
      // 非 JSON 错误正文直接保留。
    }
    throw HttpException(
      'E2B 请求失败（HTTP $statusCode）${message.isEmpty ? '' : '：$message'}',
      uri: uri,
    );
  }

  void _dropSandbox(_E2bSandbox sandbox) {
    if (identical(_sandbox, sandbox)) _sandbox = null;
  }

  Future<void> _retireSandbox(
    _E2bSandbox? sandbox, {
    required Future<_E2bSandbox>? sandboxStart,
    required http.Client client,
    required AiSandboxSettings settings,
  }) async {
    var target = sandbox;
    if (target == null && sandboxStart != null) {
      try {
        target = await sandboxStart;
      } catch (_) {
        // 创建失败时没有远端资源需要回收。
      }
    }
    await _deleteSandbox(target, client: client, settings: settings);
    client.close();
  }

  Future<void> _deleteSandbox(
    _E2bSandbox? sandbox, {
    http.Client? client,
    AiSandboxSettings? settings,
  }) async {
    if (sandbox == null) return;
    final effectiveSettings = settings ?? _settings;
    final api = effectiveSettings.e2b.resolvedApiUri;
    final uri = _resolvePath(
      api,
      '/sandboxes/${Uri.encodeComponent(sandbox.id)}',
    );
    final targetClient = client ?? _client;
    try {
      final request = http.Request('DELETE', uri)
        ..headers.addAll(<String, String>{
          ...effectiveSettings.e2b.apiHeaders,
          'X-API-Key': effectiveSettings.e2b.apiKey,
        });
      final response = await sendAbortableHttpRequest(
        client: targetClient,
        request: request,
        connectionTimeout: _requestTimeout(effectiveSettings),
      );
      await readBoundedByteStream(
        response.stream,
        maxBytes: _e2bMaxControlResponseBytes,
        idleTimeout: _e2bResponseIdleTimeout,
        totalTimeout: _e2bResponseIdleTimeout,
      );
    } catch (_) {
      // 远端沙箱仍会按 TTL 自动回收，关闭失败不阻断本地释放。
    }
  }

  static http.Client _createClient(String proxy) {
    final value = proxy.trim();
    if (value.isEmpty) {
      return SystemProxyResolver.instance.createHttpClient(
        userAgent: 'OpenHand/E2B',
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return SystemProxyResolver.instance.createHttpClient(
        userAgent: 'OpenHand/E2B',
      );
    }
    final proxyPort = uri.hasPort
        ? uri.port
        : uri.scheme == 'https'
        ? 443
        : 80;
    final raw = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'OpenHand/E2B'
      ..findProxy = (_) => 'PROXY ${uri.host}:$proxyPort';
    if (uri.userInfo.isNotEmpty) {
      final split = uri.userInfo.split(':');
      raw.addProxyCredentials(
        uri.host,
        proxyPort,
        '',
        HttpClientBasicCredentials(
          Uri.decodeComponent(split.first),
          split.length > 1
              ? Uri.decodeComponent(split.sublist(1).join(':'))
              : '',
        ),
      );
    }
    return IOClient(raw);
  }

  static bool _isIpOrCidr(String value) {
    final parts = value.trim().split('/');
    if (parts.isEmpty || parts.length > 2) return false;
    try {
      final address = InternetAddress(parts.first);
      if (parts.length == 1) return true;
      final prefix = int.tryParse(parts[1]);
      final max = address.type == InternetAddressType.IPv4 ? 32 : 128;
      return prefix != null && prefix >= 0 && prefix <= max;
    } on ArgumentError {
      return false;
    }
  }

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static bool _isDomain(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.contains(RegExp(r'[/:\s]'))) {
      return false;
    }
    final uri = Uri.tryParse('https://$normalized');
    return uri != null && uri.host.toLowerCase() == normalized.toLowerCase();
  }

  static bool _isHostPort(String value) {
    final normalized = value.trim();
    final separator = normalized.startsWith('[')
        ? normalized.indexOf(']:') + 1
        : normalized.lastIndexOf(':');
    if (separator <= 0 || separator >= normalized.length - 1) return false;
    final host = normalized.substring(0, separator).trim();
    final port = int.tryParse(normalized.substring(separator + 1));
    return host.isNotEmpty &&
        !host.contains(RegExp(r'\s')) &&
        port != null &&
        port > 0 &&
        port <= 65535;
  }

  static Uint8List _encodeConnectJsonMessage(Object value) {
    final payload = utf8.encode(jsonEncode(value));
    final frame = Uint8List(payload.length + 5);
    final length = payload.length;
    frame[1] = (length >> 24) & 0xff;
    frame[2] = (length >> 16) & 0xff;
    frame[3] = (length >> 8) & 0xff;
    frame[4] = length & 0xff;
    frame.setRange(5, frame.length, payload);
    return frame;
  }

  static String _validateNetworkRules(Map<String, Object?> rules) {
    for (final entry in rules.entries) {
      if (entry.key.trim().isEmpty || entry.value is! List) {
        return 'E2B network.rules 必须以域名映射到规则数组。';
      }
      for (final rawRule in entry.value! as List) {
        if (rawRule is! Map) return 'E2B network.rules 的规则必须是对象。';
        final transform = rawRule['transform'];
        if (transform == null) continue;
        if (transform is! Map) return 'E2B network.rules.transform 必须是对象。';
        final headers = transform['headers'];
        if (headers != null &&
            (headers is! Map ||
                headers.entries.any(
                  (header) => header.key is! String || header.value is! String,
                ))) {
          return 'E2B network.rules.transform.headers 必须是字符串对象。';
        }
      }
    }
    return '';
  }

  static String _validateIamTokens(Map<String, Object?> tokens) {
    for (final entry in tokens.entries) {
      final token = entry.value;
      if (entry.key.trim().isEmpty || token is! Map) {
        return 'E2B iam.tokens 必须以名称映射到令牌对象。';
      }
      if ('${token['audience'] ?? ''}'.trim().isEmpty ||
          '${token['tokenType'] ?? ''}'.trim().isEmpty) {
        return 'E2B iam.tokens.${entry.key} 需要 audience 与 tokenType。';
      }
    }
    return '';
  }
}

class _E2bSandbox {
  const _E2bSandbox({required this.id, required this.accessToken});

  final String id;
  final String accessToken;
}

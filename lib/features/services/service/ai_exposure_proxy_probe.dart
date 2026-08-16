import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../shared/net/http_redirect_utils.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/ai_exposure_models.dart';

const Duration _kProxyProbeAttemptTimeout = Duration(seconds: 4);
const Duration _kProxyIdentityTimeout = Duration(seconds: 8);
const int _kMaxProxyResponseLineBytes = 2048;
const int _kMaxProxyResponseHeaderBytes = 16 * kBytesPerKiB;
const int _kMaxProxyIdentityResponseBytes = 64 * kBytesPerKiB;
const List<({String host, int port})> _kProxyProbeTargets = [
  (host: 'cp.cloudflare.com', port: 443),
  (host: 'connectivitycheck.gstatic.com', port: 443),
];
const String _kProxyUserAgent = 'OpenHand-Proxy-Probe';
const String _kProxyAuthFailureMessage = '代理认证失败，请核对用户名、密码或供应商认证方式。';
const String _kProxyIdentityHttpsUrl = 'https://ipwho.is/';
const String _kProxyIdentityHttpUrl = 'http://ipwho.is/';
const List<int> _kHttpLineBreak = <int>[0x0d, 0x0a];
const List<int> _kHttpHeaderBreak = <int>[0x0d, 0x0a, 0x0d, 0x0a];

final RegExp _httpStatusLinePattern = RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})\b');

/// 从 HTTP 状态行（或以状态行开头的响应头文本）解析状态码，解析失败返回 null。
int? _statusCodeFromHttpStatusLine(String text) {
  return int.tryParse(_httpStatusLinePattern.firstMatch(text)?.group(1) ?? '');
}

/// 代理巡检取消令牌；取消时主动关闭当前 Socket，避免停止操作被网络超时拖住。
class AiExposureProxyProbeCancellation {
  final Completer<void> _cancelled = Completer<void>();
  final Set<void Function()> _listeners = <void Function()>{};

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void addListener(void Function() listener) {
    if (isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}

class AiExposureProxyProbeCancelledException implements Exception {
  const AiExposureProxyProbeCancelledException();
}

class AiExposureProxyProbe {
  const AiExposureProxyProbe();

  Future<AiExposureProxyProbeSample> inspect(
    AiExposureProxyEndpoint endpoint, {
    String? inspectionRunId,
    DateTime? scheduledAt,
    AiExposureProxyProbeCancellation? cancellation,
  }) async {
    _throwIfCancelled(cancellation);
    final startedAt = DateTime.now();
    final sampleId = [
      inspectionRunId ?? 'manual',
      endpoint.runtimeId,
      '${startedAt.microsecondsSinceEpoch}',
    ].join(':');
    final proxy = _tryParseProxyUri(endpoint.url);
    if (proxy == null) {
      final finishedAt = DateTime.now();
      return AiExposureProxyProbeSample(
        id: sampleId,
        inspectionRunId: inspectionRunId,
        scheduledAt: scheduledAt,
        startedAt: startedAt,
        finishedAt: finishedAt,
        checkedAt: startedAt,
        error: '代理地址格式无效，请检查协议与主机。',
        stepResults: [
          AiExposureProxyProbeStepResult(
            step: '代理网关连接',
            succeeded: false,
            startedAt: startedAt,
            finishedAt: finishedAt,
            durationMs: finishedAt.difference(startedAt).inMilliseconds,
            message: '代理地址格式无效，请检查协议与主机。',
          ),
        ],
      );
    }
    _ProxyProbeAttempt? failure;
    for (final target in _kProxyProbeTargets) {
      final attempt = await _probeTunnel(
        proxy,
        target,
        cancellation: cancellation,
      );
      _throwIfCancelled(cancellation);
      if (attempt.reachable) {
        final finishedAt = DateTime.now();
        return AiExposureProxyProbeSample(
          id: sampleId,
          inspectionRunId: inspectionRunId,
          scheduledAt: scheduledAt,
          startedAt: startedAt,
          finishedAt: finishedAt,
          checkedAt: startedAt,
          latencyMs: attempt.latencyMs,
          statusCode: attempt.statusCode,
          gatewayReachable: true,
          stepResults: [
            AiExposureProxyProbeStepResult(
              step: '代理转发与协议检查',
              succeeded: true,
              startedAt: startedAt,
              finishedAt: finishedAt,
              durationMs: finishedAt.difference(startedAt).inMilliseconds,
              message: '代理转发与协议检查通过。',
            ),
          ],
        );
      }
      failure = _preferredFailure(failure, attempt);
      if (!attempt.retryable) break;
    }
    final finishedAt = DateTime.now();
    final resolvedFailure =
        failure?.failure ?? AiExposureProxyProbeFailure.forwarding;
    final error = failure?.error ?? '代理检测失败';
    return AiExposureProxyProbeSample(
      id: sampleId,
      inspectionRunId: inspectionRunId,
      scheduledAt: scheduledAt,
      startedAt: startedAt,
      finishedAt: finishedAt,
      checkedAt: startedAt,
      statusCode: failure?.statusCode,
      gatewayReachable: failure?.gatewayReachable ?? false,
      failure: resolvedFailure,
      error: error,
      stepResults: [
        AiExposureProxyProbeStepResult(
          step: _proxyProbeFailureStepName(resolvedFailure),
          succeeded: false,
          startedAt: startedAt,
          finishedAt: finishedAt,
          durationMs: finishedAt.difference(startedAt).inMilliseconds,
          message: error,
        ),
      ],
    );
  }

  Future<AiExposureProxyIdentity> inspectIdentity(
    AiExposureProxyEndpoint endpoint,
  ) async {
    final proxy = _tryParseProxyUri(endpoint.url);
    if (proxy == null) {
      throw const FormatException('代理地址格式无效，请检查协议与主机。');
    }
    try {
      final body = proxy.scheme == 'https'
          ? await _loadIdentityThroughSecureProxy(proxy)
          : await _loadIdentityThroughHttpProxy(proxy);
      return _parseIdentity(body);
    } on TimeoutException {
      throw const FormatException('代理身份查询超时');
    } on HandshakeException {
      throw const FormatException('代理身份查询的 TLS 握手失败');
    } on SocketException {
      throw const FormatException('代理网关未完成身份查询转发，请检查供应商线路或节点状态。');
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('代理身份查询失败：$error');
    }
  }
}

/// 统一处理代理身份查询的认证状态码，返回对应的错误描述。
/// 返回 null 表示非认证类状态码，由调用方自行处理。
String? _proxyIdentityAuthError(int? status) {
  if (_isProxyAuthenticationFailure(status)) {
    return _kProxyAuthFailureMessage;
  }
  return null;
}

Uri? _tryParseProxyUri(String value) {
  final proxy = Uri.tryParse(value.trim());
  if (proxy == null ||
      !const <String>{'http', 'https'}.contains(proxy.scheme.toLowerCase()) ||
      proxy.host.isEmpty) {
    return null;
  }
  return proxy.replace(scheme: proxy.scheme.toLowerCase());
}

bool _isProxyAuthenticationFailure(int? status) =>
    status == HttpStatus.unauthorized ||
    status == HttpStatus.proxyAuthenticationRequired;

String _proxyProbeFailureStepName(AiExposureProxyProbeFailure failure) =>
    switch (failure) {
      AiExposureProxyProbeFailure.gateway => '代理网关连接',
      AiExposureProxyProbeFailure.authentication => '代理身份认证',
      AiExposureProxyProbeFailure.access => '代理访问控制',
      AiExposureProxyProbeFailure.forwarding => '代理转发',
      AiExposureProxyProbeFailure.protocol => '代理协议检查',
      AiExposureProxyProbeFailure.timeout => '代理响应等待',
    };

Future<_ProxyProbeAttempt> _probeTunnel(
  Uri proxy,
  ({String host, int port}) target, {
  AiExposureProxyProbeCancellation? cancellation,
}) async {
  final stopwatch = Stopwatch()..start();
  Socket? socket;
  var gatewayReachable = false;
  void closeSocket() => socket?.destroy();
  cancellation?.addListener(closeSocket);
  try {
    socket = await _connectProxyCancellable(
      proxy,
      _remaining(_kProxyProbeAttemptTimeout, stopwatch),
      cancellation,
    );
    _throwIfCancelled(cancellation);
    gatewayReachable = true;
    socket.setOption(SocketOption.tcpNoDelay, true);
    socket.add(utf8.encode(_connectRequest(proxy, target)));
    await socket.flush().timeout(
      _remaining(_kProxyProbeAttemptTimeout, stopwatch),
    );
    final statusCode = await _readStatusCode(
      socket,
    ).timeout(_remaining(_kProxyProbeAttemptTimeout, stopwatch));
    stopwatch.stop();
    if (statusCode >= 200 && statusCode < 300) {
      return _ProxyProbeAttempt.success(
        latencyMs: stopwatch.elapsedMilliseconds,
        statusCode: statusCode,
      );
    }
    return _statusFailure(statusCode);
  } on TimeoutException {
    _throwIfCancelled(cancellation);
    return _ProxyProbeAttempt.failure(
      gatewayReachable: gatewayReachable,
      failure: AiExposureProxyProbeFailure.timeout,
      error: gatewayReachable
          ? '代理网关已连接，但转发响应超时，请检查供应商线路或目标限制。'
          : '连接代理网关超时，请检查主机、端口或网络。',
      retryable: gatewayReachable,
    );
  } on HandshakeException {
    _throwIfCancelled(cancellation);
    return const _ProxyProbeAttempt.failure(
      gatewayReachable: false,
      failure: AiExposureProxyProbeFailure.gateway,
      error: 'HTTPS 代理握手失败，请确认节点协议与证书。',
      retryable: false,
    );
  } on SocketException {
    _throwIfCancelled(cancellation);
    return _ProxyProbeAttempt.failure(
      gatewayReachable: gatewayReachable,
      failure: gatewayReachable
          ? AiExposureProxyProbeFailure.forwarding
          : AiExposureProxyProbeFailure.gateway,
      error: gatewayReachable
          ? '代理网关已连接，但连接在转发前被中止，请检查供应商凭据、IP 白名单或套餐状态。'
          : '无法连接代理网关，请检查主机、端口或网络。',
      retryable: gatewayReachable,
    );
  } on FormatException catch (error) {
    _throwIfCancelled(cancellation);
    return _ProxyProbeAttempt.failure(
      gatewayReachable: gatewayReachable,
      failure: AiExposureProxyProbeFailure.protocol,
      error: error.message,
      retryable: gatewayReachable,
    );
  } catch (_) {
    _throwIfCancelled(cancellation);
    return _ProxyProbeAttempt.failure(
      gatewayReachable: gatewayReachable,
      failure: gatewayReachable
          ? AiExposureProxyProbeFailure.forwarding
          : AiExposureProxyProbeFailure.gateway,
      error: gatewayReachable ? '代理转发检测失败。' : '代理网关连接失败。',
      retryable: gatewayReachable,
    );
  } finally {
    cancellation?.removeListener(closeSocket);
    stopwatch.stop();
    socket?.destroy();
  }
}

Future<Socket> _connectProxyCancellable(
  Uri proxy,
  Duration timeout,
  AiExposureProxyProbeCancellation? cancellation,
) {
  final connection = _connectProxy(proxy, timeout);
  if (cancellation == null) return connection;
  unawaited(
    connection.then<void>((socket) {
      if (cancellation.isCancelled) socket.destroy();
    }, onError: (Object _, StackTrace _) {}),
  );
  return Future.any<Socket>(<Future<Socket>>[
    connection,
    cancellation.whenCancelled.then<Socket>(
      (_) => throw const AiExposureProxyProbeCancelledException(),
    ),
  ]);
}

void _throwIfCancelled(AiExposureProxyProbeCancellation? cancellation) {
  if (cancellation?.isCancelled == true) {
    throw const AiExposureProxyProbeCancelledException();
  }
}

_ProxyProbeAttempt _statusFailure(int statusCode) {
  if (_isProxyAuthenticationFailure(statusCode)) {
    return _ProxyProbeAttempt.failure(
      gatewayReachable: true,
      statusCode: statusCode,
      failure: AiExposureProxyProbeFailure.authentication,
      error: _kProxyAuthFailureMessage,
      retryable: false,
    );
  }
  if (statusCode == HttpStatus.forbidden ||
      statusCode == HttpStatus.tooManyRequests) {
    return _ProxyProbeAttempt.failure(
      gatewayReachable: true,
      statusCode: statusCode,
      failure: AiExposureProxyProbeFailure.access,
      error: statusCode == HttpStatus.forbidden
          ? '代理拒绝转发，请检查 IP 白名单、套餐状态或目标限制。'
          : '代理请求受限，请检查套餐额度或并发限制。',
      retryable: statusCode == HttpStatus.forbidden,
    );
  }
  return _ProxyProbeAttempt.failure(
    gatewayReachable: true,
    statusCode: statusCode,
    failure: AiExposureProxyProbeFailure.forwarding,
    error: statusCode >= 500
        ? '代理网关暂时无法完成转发（HTTP $statusCode）。'
        : '代理拒绝建立 HTTPS 隧道（HTTP $statusCode）。',
    retryable: statusCode >= 500,
  );
}

_ProxyProbeAttempt _preferredFailure(
  _ProxyProbeAttempt? current,
  _ProxyProbeAttempt next,
) {
  if (current == null) return next;
  const priority = <AiExposureProxyProbeFailure, int>{
    AiExposureProxyProbeFailure.authentication: 6,
    AiExposureProxyProbeFailure.access: 5,
    AiExposureProxyProbeFailure.protocol: 4,
    AiExposureProxyProbeFailure.forwarding: 3,
    AiExposureProxyProbeFailure.timeout: 2,
    AiExposureProxyProbeFailure.gateway: 1,
  };
  return (priority[next.failure] ?? 0) > (priority[current.failure] ?? 0)
      ? next
      : current;
}

Future<Uint8List> _loadIdentityThroughHttpProxy(Uri proxy) async {
  final stopwatch = Stopwatch()..start();
  final client = HttpClient()
    ..autoUncompress = true
    ..connectionTimeout = _kProxyIdentityTimeout
    ..idleTimeout = _kProxyIdentityTimeout
    ..userAgent = _kProxyUserAgent
    ..findProxy = (_) => 'PROXY ${_proxyAuthority(proxy)}';
  final credentials = _proxyCredentials(proxy);
  if (credentials != null) {
    client.addProxyCredentials(
      proxy.host,
      proxy.port,
      '',
      HttpClientBasicCredentials(credentials.$1, credentials.$2),
    );
  }
  try {
    final request = await client
        .getUrl(Uri.parse(_kProxyIdentityHttpsUrl))
        .timeout(_remaining(_kProxyIdentityTimeout, stopwatch));
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.acceptHeader, kApplicationJsonMimeType)
      ..headers.set(HttpHeaders.connectionHeader, kConnectionClose);
    final response = await request.close().timeout(
      _remaining(_kProxyIdentityTimeout, stopwatch),
    );
    final authError = _proxyIdentityAuthError(response.statusCode);
    if (authError != null) throw FormatException(authError);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException('出口身份服务返回 HTTP ${response.statusCode}');
    }
    final remaining = _remaining(_kProxyIdentityTimeout, stopwatch);
    return await readBoundedByteStream(
      response,
      maxBytes: _kMaxProxyIdentityResponseBytes,
      idleTimeout: remaining,
      totalTimeout: remaining,
    );
  } on ByteStreamSizeLimitException {
    throw const FormatException('代理身份响应过大');
  } on HttpException catch (error) {
    final status = int.tryParse(
      RegExp(r'tunnel \((\d{3})\b').firstMatch(error.message)?.group(1) ?? '',
    );
    final authError = _proxyIdentityAuthError(status);
    if (authError != null) throw FormatException(authError);
    if (status == 403) {
      throw const FormatException('代理拒绝身份查询，请检查 IP 白名单、套餐状态或目标限制。');
    }
    throw FormatException(
      status == null ? '代理网关未完成身份查询转发' : '代理网关无法建立身份查询隧道（HTTP $status）',
    );
  } finally {
    stopwatch.stop();
    client.close(force: true);
  }
}

Future<Uint8List> _loadIdentityThroughSecureProxy(Uri proxy) async {
  final stopwatch = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await _connectProxy(
      proxy,
      _remaining(_kProxyIdentityTimeout, stopwatch),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    socket.add(
      utf8.encode(_getRequest(proxy, Uri.parse(_kProxyIdentityHttpUrl))),
    );
    await socket.flush().timeout(_remaining(_kProxyIdentityTimeout, stopwatch));
    final response = await _readRawIdentityResponse(
      socket,
    ).timeout(_remaining(_kProxyIdentityTimeout, stopwatch));
    final headerEnd = _indexOfBytes(response, _kHttpHeaderBreak);
    if (headerEnd < 0) throw const FormatException('代理身份响应格式无效');
    final header = ascii.decode(
      Uint8List.sublistView(response, 0, headerEnd),
      allowInvalid: true,
    );
    final status = _statusCodeFromHttpStatusLine(header);
    final authError = _proxyIdentityAuthError(status);
    if (authError != null) throw FormatException(authError);
    if (status == null || status < 200 || status >= 300) {
      throw FormatException('出口身份服务返回 HTTP ${status ?? '--'}');
    }
    final encodedBody = Uint8List.sublistView(
      response,
      headerEnd + _kHttpHeaderBreak.length,
    );
    final chunked = _hasChunkedTransferEncoding(header);
    final contentLength = chunked ? null : _contentLength(header);
    if (contentLength != null && encodedBody.length < contentLength) {
      throw const FormatException('代理身份响应不完整');
    }
    final boundedBody = contentLength == null
        ? encodedBody
        : Uint8List.sublistView(encodedBody, 0, contentLength);
    return chunked ? _decodeChunkedBody(encodedBody) : boundedBody;
  } finally {
    stopwatch.stop();
    socket?.destroy();
  }
}

Future<Uint8List> _readRawIdentityResponse(Socket socket) async {
  final buffer = BytesBuilder(copy: false);
  var headerEnd = -1;
  int? contentLength;
  var chunked = false;
  await for (final chunk in socket) {
    if (buffer.length + chunk.length >
        _kMaxProxyIdentityResponseBytes + _kMaxProxyResponseHeaderBytes) {
      throw const FormatException('代理身份响应过大');
    }
    buffer.add(chunk);
    final raw = buffer.toBytes();
    if (headerEnd < 0) {
      headerEnd = _indexOfBytes(raw, _kHttpHeaderBreak);
      if (headerEnd < 0) {
        if (raw.length > _kMaxProxyResponseHeaderBytes) {
          throw const FormatException('代理身份响应头过大');
        }
        continue;
      }
      final header = ascii.decode(
        Uint8List.sublistView(raw, 0, headerEnd),
        allowInvalid: true,
      );
      chunked = _hasChunkedTransferEncoding(header);
      contentLength = chunked ? null : _contentLength(header);
      if (contentLength != null &&
          contentLength > _kMaxProxyIdentityResponseBytes) {
        throw const FormatException('代理身份响应过大');
      }
    }
    final bodyStart = headerEnd + _kHttpHeaderBreak.length;
    final bodyLength = raw.length - bodyStart;
    if (bodyLength > _kMaxProxyIdentityResponseBytes) {
      throw const FormatException('代理身份响应过大');
    }
    if (contentLength != null && bodyLength >= contentLength) return raw;
    if (chunked) {
      try {
        _decodeChunkedBody(Uint8List.sublistView(raw, bodyStart));
        return raw;
      } on FormatException {
        continue;
      }
    }
  }
  // Socket 在完整响应到达前关闭，视为不完整响应。
  throw const FormatException('代理身份响应不完整');
}

AiExposureProxyIdentity _parseIdentity(Uint8List body) {
  final decoded = jsonDecode(utf8.decode(body));
  if (decoded is! Map || decoded['success'] == false) {
    final message = decoded is Map ? '${decoded['message'] ?? ''}'.trim() : '';
    throw FormatException(message.isEmpty ? '代理身份响应格式无效' : message);
  }
  final exitIp = '${decoded['ip'] ?? ''}'.trim();
  final address = InternetAddress.tryParse(exitIp);
  if (address == null) throw const FormatException('代理身份响应缺少有效出口 IP');
  final connection = _stringMap(decoded['connection']);
  final timezone = _stringMap(decoded['timezone']);
  final currency = _stringMap(decoded['currency']);
  final security = _stringMap(decoded['security']);
  final hasSecurity = security.isNotEmpty;
  final mobile = boolFromValue(security['mobile']);
  final proxyDetected =
      boolFromValue(security['proxy']) ||
      boolFromValue(security['vpn']) ||
      boolFromValue(security['tor']) ||
      boolFromValue(security['anonymous']);
  final hosting = boolFromValue(security['hosting']);
  return AiExposureProxyIdentity(
    exitIp: exitIp,
    ipType: switch (address.type) {
      InternetAddressType.IPv4 => 'IPv4',
      InternetAddressType.IPv6 => 'IPv6',
      _ => '--',
    },
    networkType: !hasSecurity
        ? 'unknown'
        : mobile
        ? 'mobile'
        : hosting
        ? 'datacenter'
        : proxyDetected
        ? 'public_proxy'
        : 'residential',
    cleanliness: !hasSecurity
        ? 'unknown'
        : proxyDetected && hosting
        ? 'low'
        : proxyDetected || hosting
        ? 'medium'
        : 'high',
    continent: '${decoded['continent'] ?? ''}',
    country: '${decoded['country'] ?? ''}',
    countryCode: '${decoded['country_code'] ?? ''}',
    region: '${decoded['region'] ?? ''}',
    city: '${decoded['city'] ?? ''}',
    district: '',
    postalCode: '${decoded['postal'] ?? ''}',
    timezone: '${timezone['id'] ?? ''}',
    currency: '${currency['code'] ?? ''}',
    isp: '${connection['isp'] ?? ''}',
    organization: '${connection['org'] ?? ''}',
    asn: _asnLabel(connection['asn']),
    asName: '${connection['org'] ?? ''}',
    mobile: mobile,
    proxy: proxyDetected,
    hosting: hosting,
    latitude: optionalDoubleFromValue(decoded['latitude']),
    longitude: optionalDoubleFromValue(decoded['longitude']),
    observedAt: DateTime.now(),
  );
}

Future<Socket> _connectProxy(Uri proxy, Duration timeout) =>
    proxy.scheme == 'https'
    ? SecureSocket.connect(proxy.host, proxy.port, timeout: timeout)
    : Socket.connect(proxy.host, proxy.port, timeout: timeout);

String _connectRequest(Uri proxy, ({String host, int port}) target) {
  final authority = '${target.host}:${target.port}';
  final authorization = _proxyAuthorization(proxy);
  return 'CONNECT $authority HTTP/1.1\r\n'
      'Host: $authority\r\n'
      'User-Agent: $_kProxyUserAgent\r\n'
      'Accept: */*\r\n'
      'Connection: keep-alive\r\n'
      'Proxy-Connection: keep-alive\r\n'
      '${authorization == null ? '' : 'Proxy-Authorization: Basic $authorization\r\n'}'
      '\r\n';
}

String _getRequest(Uri proxy, Uri target) {
  final authorization = _proxyAuthorization(proxy);
  return 'GET $target HTTP/1.1\r\n'
      'Host: ${target.host}\r\n'
      'User-Agent: $_kProxyUserAgent\r\n'
      'Accept: application/json\r\n'
      'Accept-Encoding: identity\r\n'
      'Connection: close\r\n'
      'Proxy-Connection: close\r\n'
      '${authorization == null ? '' : 'Proxy-Authorization: Basic $authorization\r\n'}'
      '\r\n';
}

Future<int> _readStatusCode(Socket socket) async {
  final bytes = <int>[];
  await for (final chunk in socket) {
    final lineEnd = chunk.indexOf(0x0a);
    final take = lineEnd < 0 ? chunk.length : lineEnd + 1;
    if (bytes.length + take > _kMaxProxyResponseLineBytes) {
      throw const FormatException('代理响应头过长，请确认节点协议与端口。');
    }
    bytes.addAll(chunk.take(take));
    if (lineEnd >= 0) break;
  }
  if (bytes.isEmpty) {
    throw const FormatException('代理网关已连接，但未返回协议响应，请检查供应商凭据、IP 白名单或套餐状态。');
  }
  final firstLine = ascii.decode(bytes, allowInvalid: true).trim();
  final statusCode = _statusCodeFromHttpStatusLine(firstLine);
  if (statusCode == null) {
    throw const FormatException('代理网关返回非 HTTP 响应，请确认节点协议与端口。');
  }
  return statusCode;
}

int? _contentLength(String header) {
  for (final line in header.split('\r\n').skip(1)) {
    final separator = line.indexOf(':');
    if (separator <= 0 ||
        line.substring(0, separator).trim().toLowerCase() !=
            HttpHeaders.contentLengthHeader) {
      continue;
    }
    final value = int.tryParse(line.substring(separator + 1).trim());
    if (value == null || value < 0) {
      throw const FormatException('代理身份响应长度无效');
    }
    return value;
  }
  return null;
}

bool _hasChunkedTransferEncoding(String header) {
  for (final line in header.split('\r\n').skip(1)) {
    final separator = line.indexOf(':');
    if (separator <= 0 ||
        line.substring(0, separator).trim().toLowerCase() !=
            HttpHeaders.transferEncodingHeader) {
      continue;
    }
    return line
        .substring(separator + 1)
        .split(',')
        .any((value) => value.trim().toLowerCase() == 'chunked');
  }
  return false;
}

Uint8List _decodeChunkedBody(Uint8List source) {
  final output = BytesBuilder(copy: false);
  var offset = 0;
  while (offset < source.length) {
    final lineEnd = _indexOfBytes(source, _kHttpLineBreak, offset);
    if (lineEnd < 0) throw const FormatException('代理身份分块响应无效');
    final size = int.tryParse(
      ascii
          .decode(
            Uint8List.sublistView(source, offset, lineEnd),
            allowInvalid: true,
          )
          .split(';')
          .first
          .trim(),
      radix: 16,
    );
    if (size == null || size < 0) {
      throw const FormatException('代理身份分块响应无效');
    }
    if (size == 0) return output.takeBytes();
    final start = lineEnd + _kHttpLineBreak.length;
    final end = start + size;
    if (end + _kHttpLineBreak.length > source.length ||
        source[end] != _kHttpLineBreak[0] ||
        source[end + 1] != _kHttpLineBreak[1]) {
      throw const FormatException('代理身份响应不完整');
    }
    output.add(Uint8List.sublistView(source, start, end));
    offset = end + _kHttpLineBreak.length;
  }
  throw const FormatException('代理身份响应不完整');
}

int _indexOfBytes(Uint8List source, List<int> pattern, [int start = 0]) {
  if (pattern.isEmpty || start < 0) return -1;
  final lastStart = source.length - pattern.length;
  for (var index = start; index <= lastStart; index++) {
    var matched = true;
    for (var patternIndex = 0; patternIndex < pattern.length; patternIndex++) {
      if (source[index + patternIndex] != pattern[patternIndex]) {
        matched = false;
        break;
      }
    }
    if (matched) return index;
  }
  return -1;
}

String _proxyAuthority(Uri proxy) {
  final host = proxy.host.contains(':') ? '[${proxy.host}]' : proxy.host;
  return '$host:${proxy.port}';
}

(String, String)? _proxyCredentials(Uri proxy) {
  if (proxy.userInfo.isEmpty) return null;
  final credentials = aiExposureProxyCredentials(proxy.userInfo);
  return (credentials.username, credentials.password);
}

String? _proxyAuthorization(Uri proxy) {
  final credentials = _proxyCredentials(proxy);
  return credentials == null
      ? null
      : base64Encode(utf8.encode('${credentials.$1}:${credentials.$2}'));
}

Duration _remaining(Duration limit, Stopwatch stopwatch) {
  final remaining = limit - stopwatch.elapsed;
  if (remaining <= Duration.zero) throw TimeoutException('代理请求超时');
  return remaining;
}

Map<String, Object?> _stringMap(Object? value) => value is Map
    ? <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      }
    : const <String, Object?>{};

String _asnLabel(Object? value) {
  final label = '$value'.trim();
  if (label.isEmpty || label == 'null') return '';
  return label.toUpperCase().startsWith('AS') ? label : 'AS$label';
}

class _ProxyProbeAttempt {
  const _ProxyProbeAttempt.success({
    required this.latencyMs,
    required this.statusCode,
  }) : reachable = true,
       gatewayReachable = true,
       failure = AiExposureProxyProbeFailure.forwarding,
       error = '',
       retryable = false;

  const _ProxyProbeAttempt.failure({
    required this.gatewayReachable,
    required this.failure,
    required this.error,
    required this.retryable,
    this.statusCode,
  }) : reachable = false,
       latencyMs = null;

  final bool reachable;
  final bool gatewayReachable;
  final int? latencyMs;
  final int? statusCode;
  final AiExposureProxyProbeFailure failure;
  final String error;
  final bool retryable;
}

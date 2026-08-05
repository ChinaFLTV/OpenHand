import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../shared/net/http_response_utils.dart';
import '../model/ai_exposure_models.dart';

const Duration _kProxyProbeAttemptTimeout = Duration(seconds: 4);
const Duration _kProxyIdentityTimeout = Duration(seconds: 8);
const int _kMaxProxyResponseLineBytes = 2048;
const int _kMaxProxyIdentityResponseBytes = 64 * 1024;
const List<({String host, int port})> _kProxyProbeTargets = [
  (host: 'cp.cloudflare.com', port: 443),
  (host: 'connectivitycheck.gstatic.com', port: 443),
];
const String _kProxyIdentityTarget = 'https://ipwho.is/';
const String _kSecureProxyIdentityTarget = 'http://ipwho.is/';
const List<int> _kHttpLineBreak = <int>[0x0d, 0x0a];
const List<int> _kHttpHeaderBreak = <int>[0x0d, 0x0a, 0x0d, 0x0a];

class AiExposureProxyProbe {
  const AiExposureProxyProbe();

  Future<AiExposureProxyProbeSample> inspect(
    AiExposureProxyEndpoint endpoint,
  ) async {
    final checkedAt = DateTime.now();
    final proxy = Uri.parse(endpoint.url);
    _ProxyProbeAttempt? failure;
    for (final target in _kProxyProbeTargets) {
      final attempt = await _probeTunnel(proxy, target);
      if (attempt.reachable) {
        return AiExposureProxyProbeSample(
          checkedAt: checkedAt,
          latencyMs: attempt.latencyMs,
          statusCode: attempt.statusCode,
          gatewayReachable: true,
        );
      }
      failure = _preferredFailure(failure, attempt);
      if (!attempt.retryable) break;
    }
    return AiExposureProxyProbeSample(
      checkedAt: checkedAt,
      statusCode: failure?.statusCode,
      gatewayReachable: failure?.gatewayReachable ?? false,
      failure: failure?.failure ?? AiExposureProxyProbeFailure.forwarding,
      error: failure?.error ?? '代理检测失败',
    );
  }

  Future<AiExposureProxyIdentity> inspectIdentity(
    AiExposureProxyEndpoint endpoint,
  ) async {
    final proxy = Uri.parse(endpoint.url);
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
    }
  }
}

Future<_ProxyProbeAttempt> _probeTunnel(
  Uri proxy,
  ({String host, int port}) target,
) async {
  final stopwatch = Stopwatch()..start();
  Socket? socket;
  var gatewayReachable = false;
  try {
    socket = await _connectProxy(
      proxy,
      _remaining(_kProxyProbeAttemptTimeout, stopwatch),
    );
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
    return _ProxyProbeAttempt.failure(
      gatewayReachable: gatewayReachable,
      failure: AiExposureProxyProbeFailure.timeout,
      error: gatewayReachable
          ? '代理网关已连接，但转发响应超时，请检查供应商线路或目标限制。'
          : '连接代理网关超时，请检查主机、端口或网络。',
      retryable: gatewayReachable,
    );
  } on HandshakeException {
    return const _ProxyProbeAttempt.failure(
      gatewayReachable: false,
      failure: AiExposureProxyProbeFailure.gateway,
      error: 'HTTPS 代理握手失败，请确认节点协议与证书。',
      retryable: false,
    );
  } on SocketException {
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
    return _ProxyProbeAttempt.failure(
      gatewayReachable: gatewayReachable,
      failure: AiExposureProxyProbeFailure.protocol,
      error: error.message,
      retryable: gatewayReachable,
    );
  } catch (_) {
    return _ProxyProbeAttempt.failure(
      gatewayReachable: gatewayReachable,
      failure: gatewayReachable
          ? AiExposureProxyProbeFailure.forwarding
          : AiExposureProxyProbeFailure.gateway,
      error: gatewayReachable ? '代理转发检测失败。' : '代理网关连接失败。',
      retryable: gatewayReachable,
    );
  } finally {
    stopwatch.stop();
    socket?.destroy();
  }
}

_ProxyProbeAttempt _statusFailure(int statusCode) {
  if (statusCode == 401 || statusCode == 407) {
    return _ProxyProbeAttempt.failure(
      gatewayReachable: true,
      statusCode: statusCode,
      failure: AiExposureProxyProbeFailure.authentication,
      error: '代理认证失败，请核对用户名、密码或供应商认证方式。',
      retryable: false,
    );
  }
  if (statusCode == 403 || statusCode == 429) {
    return _ProxyProbeAttempt.failure(
      gatewayReachable: true,
      statusCode: statusCode,
      failure: AiExposureProxyProbeFailure.access,
      error: statusCode == 403
          ? '代理拒绝转发，请检查 IP 白名单、套餐状态或目标限制。'
          : '代理请求受限，请检查套餐额度或并发限制。',
      retryable: statusCode == 403,
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
    ..userAgent = 'OpenHand Proxy Probe'
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
        .getUrl(Uri.parse(_kProxyIdentityTarget))
        .timeout(_remaining(_kProxyIdentityTimeout, stopwatch));
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.acceptHeader, 'application/json')
      ..headers.set(HttpHeaders.connectionHeader, 'close');
    final response = await request.close().timeout(
      _remaining(_kProxyIdentityTimeout, stopwatch),
    );
    if (response.statusCode == 401 || response.statusCode == 407) {
      throw const FormatException('代理认证失败，请核对用户名、密码或供应商认证方式。');
    }
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
    if (status == 401 || status == 407) {
      throw const FormatException('代理认证失败，请核对用户名、密码或供应商认证方式。');
    }
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
      utf8.encode(_getRequest(proxy, Uri.parse(_kSecureProxyIdentityTarget))),
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
    final status = int.tryParse(
      RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})\b').firstMatch(header)?.group(1) ??
          '',
    );
    if (status == 401 || status == 407) {
      throw const FormatException('代理认证失败，请核对用户名、密码或供应商认证方式。');
    }
    if (status == null || status < 200 || status >= 300) {
      throw FormatException('出口身份服务返回 HTTP ${status ?? '--'}');
    }
    final encodedBody = Uint8List.sublistView(
      response,
      headerEnd + _kHttpHeaderBreak.length,
    );
    final contentLength = _contentLength(header);
    if (contentLength != null && encodedBody.length < contentLength) {
      throw const FormatException('代理身份响应不完整');
    }
    final boundedBody = contentLength == null
        ? encodedBody
        : Uint8List.sublistView(encodedBody, 0, contentLength);
    return header.toLowerCase().contains('transfer-encoding: chunked')
        ? _decodeChunkedBody(encodedBody)
        : boundedBody;
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
        _kMaxProxyIdentityResponseBytes + 16 * 1024) {
      throw const FormatException('代理身份响应过大');
    }
    buffer.add(chunk);
    final raw = buffer.toBytes();
    if (headerEnd < 0) {
      headerEnd = _indexOfBytes(raw, _kHttpHeaderBreak);
      if (headerEnd < 0) continue;
      final header = ascii.decode(
        Uint8List.sublistView(raw, 0, headerEnd),
        allowInvalid: true,
      );
      contentLength = _contentLength(header);
      chunked = header.toLowerCase().contains('transfer-encoding: chunked');
    }
    final body = Uint8List.sublistView(
      raw,
      headerEnd + _kHttpHeaderBreak.length,
    );
    if (body.length > _kMaxProxyIdentityResponseBytes) {
      throw const FormatException('代理身份响应过大');
    }
    if (contentLength != null && body.length >= contentLength) return raw;
    if (chunked) {
      try {
        _decodeChunkedBody(body);
        return raw;
      } on FormatException {
        continue;
      }
    }
  }
  return buffer.takeBytes();
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
  final mobile = security['mobile'] == true;
  final proxyDetected =
      security['proxy'] == true ||
      security['vpn'] == true ||
      security['tor'] == true ||
      security['anonymous'] == true;
  final hosting = security['hosting'] == true;
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
    latitude: (decoded['latitude'] as num?)?.toDouble(),
    longitude: (decoded['longitude'] as num?)?.toDouble(),
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
  final match = RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})\b').firstMatch(firstLine);
  final statusCode = int.tryParse(match?.group(1) ?? '');
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
  final separator = proxy.userInfo.indexOf(':');
  return (
    Uri.decodeComponent(
      separator < 0 ? proxy.userInfo : proxy.userInfo.substring(0, separator),
    ),
    separator < 0
        ? ''
        : Uri.decodeComponent(proxy.userInfo.substring(separator + 1)),
  );
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../model/ai_exposure_models.dart';

const Duration _kProxyProbeTimeout = Duration(seconds: 8);
const int _kMaxProxyResponseLineBytes = 2048;
const int _kMaxProxyIdentityResponseBytes = 64 * 1024;
const String _kProxyProbeTarget =
    'http://connectivitycheck.gstatic.com/generate_204';
const String _kProxyIdentityTarget =
    'http://ip-api.com/json/?fields=status,message,query,continent,country,countryCode,regionName,city,district,zip,lat,lon,timezone,currency,isp,org,as,asname,mobile,proxy,hosting';
const List<int> _kHttpLineBreak = <int>[0x0d, 0x0a];
const List<int> _kHttpHeaderBreak = <int>[0x0d, 0x0a, 0x0d, 0x0a];

class AiExposureProxyProbe {
  const AiExposureProxyProbe();

  Future<AiExposureProxyProbeSample> inspect(
    AiExposureProxyEndpoint endpoint,
  ) async {
    final checkedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      final proxy = Uri.parse(endpoint.url);
      socket = proxy.scheme == 'https'
          ? await SecureSocket.connect(
              proxy.host,
              proxy.port,
              timeout: _kProxyProbeTimeout,
            )
          : await Socket.connect(
              proxy.host,
              proxy.port,
              timeout: _kProxyProbeTimeout,
            );
      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.add(utf8.encode(_requestHead(proxy)));
      await socket.flush().timeout(_kProxyProbeTimeout);
      final statusCode = await _readStatusCode(
        socket,
      ).timeout(_kProxyProbeTimeout);
      stopwatch.stop();
      if (statusCode == 407) {
        return AiExposureProxyProbeSample(
          checkedAt: checkedAt,
          statusCode: statusCode,
          error: '代理认证失败',
        );
      }
      if (statusCode < 200 || statusCode >= 400) {
        return AiExposureProxyProbeSample(
          checkedAt: checkedAt,
          statusCode: statusCode,
          error: '代理返回 HTTP $statusCode',
        );
      }
      return AiExposureProxyProbeSample(
        checkedAt: checkedAt,
        latencyMs: stopwatch.elapsedMilliseconds,
        statusCode: statusCode,
      );
    } on TimeoutException {
      return AiExposureProxyProbeSample(checkedAt: checkedAt, error: '代理连接超时');
    } on HandshakeException {
      return AiExposureProxyProbeSample(
        checkedAt: checkedAt,
        error: 'HTTPS 代理握手失败',
      );
    } on SocketException {
      return AiExposureProxyProbeSample(
        checkedAt: checkedAt,
        error: '无法连接代理节点',
      );
    } on FormatException catch (error) {
      return AiExposureProxyProbeSample(
        checkedAt: checkedAt,
        error: error.message,
      );
    } catch (_) {
      return AiExposureProxyProbeSample(checkedAt: checkedAt, error: '代理检测失败');
    } finally {
      stopwatch.stop();
      socket?.destroy();
    }
  }

  Future<AiExposureProxyIdentity> inspectIdentity(
    AiExposureProxyEndpoint endpoint,
  ) async {
    Socket? socket;
    try {
      final proxy = Uri.parse(endpoint.url);
      socket = proxy.scheme == 'https'
          ? await SecureSocket.connect(
              proxy.host,
              proxy.port,
              timeout: _kProxyProbeTimeout,
            )
          : await Socket.connect(
              proxy.host,
              proxy.port,
              timeout: _kProxyProbeTimeout,
            );
      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.add(
        utf8.encode(_requestHead(proxy, target: _kProxyIdentityTarget)),
      );
      await socket.flush().timeout(_kProxyProbeTimeout);
      final response = await socket
          .fold<BytesBuilder>(BytesBuilder(copy: false), (buffer, chunk) {
            if (buffer.length + chunk.length >
                _kMaxProxyIdentityResponseBytes) {
              throw const FormatException('代理身份响应过大');
            }
            buffer.add(chunk);
            return buffer;
          })
          .timeout(_kProxyProbeTimeout);
      final raw = response.takeBytes();
      final headerEnd = _indexOfBytes(raw, _kHttpHeaderBreak);
      if (headerEnd < 0) throw const FormatException('代理身份响应格式无效');
      final header = ascii.decode(
        Uint8List.sublistView(raw, 0, headerEnd),
        allowInvalid: true,
      );
      final status = int.tryParse(
        RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})\b').firstMatch(header)?.group(1) ??
            '',
      );
      if (status == 407) throw const FormatException('代理认证失败');
      if (status == null || status < 200 || status >= 300) {
        throw FormatException('代理身份查询返回 HTTP ${status ?? '--'}');
      }
      final encodedBody = Uint8List.sublistView(
        raw,
        headerEnd + _kHttpHeaderBreak.length,
      );
      final body = header.toLowerCase().contains('transfer-encoding: chunked')
          ? _decodeChunkedBody(encodedBody)
          : encodedBody;
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map || decoded['status'] != 'success') {
        throw FormatException(
          '${decoded is Map ? decoded['message'] : ''}'.trim().isEmpty
              ? '代理身份查询失败'
              : '${decoded['message']}',
        );
      }
      final exitIp = '${decoded['query'] ?? ''}'.trim();
      final address = InternetAddress.tryParse(exitIp);
      final mobile = decoded['mobile'] == true;
      final proxyDetected = decoded['proxy'] == true;
      final hosting = decoded['hosting'] == true;
      return AiExposureProxyIdentity(
        exitIp: exitIp,
        ipType: switch (address?.type) {
          InternetAddressType.IPv4 => 'IPv4',
          InternetAddressType.IPv6 => 'IPv6',
          _ => '--',
        },
        networkType: mobile
            ? 'mobile'
            : hosting
            ? 'datacenter'
            : proxyDetected
            ? 'public_proxy'
            : 'residential',
        cleanliness: proxyDetected && hosting
            ? 'low'
            : proxyDetected || hosting
            ? 'medium'
            : 'high',
        continent: '${decoded['continent'] ?? ''}',
        country: '${decoded['country'] ?? ''}',
        countryCode: '${decoded['countryCode'] ?? ''}',
        region: '${decoded['regionName'] ?? ''}',
        city: '${decoded['city'] ?? ''}',
        district: '${decoded['district'] ?? ''}',
        postalCode: '${decoded['zip'] ?? ''}',
        timezone: '${decoded['timezone'] ?? ''}',
        currency: '${decoded['currency'] ?? ''}',
        isp: '${decoded['isp'] ?? ''}',
        organization: '${decoded['org'] ?? ''}',
        asn: '${decoded['as'] ?? ''}',
        asName: '${decoded['asname'] ?? ''}',
        mobile: mobile,
        proxy: proxyDetected,
        hosting: hosting,
        latitude: (decoded['lat'] as num?)?.toDouble(),
        longitude: (decoded['lon'] as num?)?.toDouble(),
        observedAt: DateTime.now(),
      );
    } on TimeoutException {
      throw const FormatException('代理身份查询超时');
    } on HandshakeException {
      throw const FormatException('HTTPS 代理握手失败');
    } on SocketException {
      throw const FormatException('无法连接代理节点');
    } finally {
      socket?.destroy();
    }
  }
}

String _requestHead(Uri proxy, {String target = _kProxyProbeTarget}) {
  final authorization = _proxyAuthorization(proxy);
  final targetUri = Uri.parse(target);
  return 'GET $target HTTP/1.1\r\n'
      'Host: ${targetUri.host}\r\n'
      'Accept: */*\r\n'
      'Connection: close\r\n'
      'Proxy-Connection: close\r\n'
      '${authorization == null ? '' : 'Proxy-Authorization: Basic $authorization\r\n'}'
      '\r\n';
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

String? _proxyAuthorization(Uri proxy) {
  if (proxy.userInfo.isEmpty) return null;
  final separator = proxy.userInfo.indexOf(':');
  final username = Uri.decodeComponent(
    separator < 0 ? proxy.userInfo : proxy.userInfo.substring(0, separator),
  );
  final password = separator < 0
      ? ''
      : Uri.decodeComponent(proxy.userInfo.substring(separator + 1));
  return base64Encode(utf8.encode('$username:$password'));
}

Future<int> _readStatusCode(Socket socket) async {
  final bytes = <int>[];
  await for (final chunk in socket) {
    final lineEnd = chunk.indexOf(0x0a);
    final take = lineEnd < 0 ? chunk.length : lineEnd + 1;
    if (bytes.length + take > _kMaxProxyResponseLineBytes) {
      throw const FormatException('代理响应头过长');
    }
    bytes.addAll(chunk.take(take));
    if (lineEnd >= 0) break;
  }
  if (bytes.isEmpty) throw const FormatException('代理未返回响应');
  final firstLine = ascii.decode(bytes, allowInvalid: true).trim();
  final match = RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})\b').firstMatch(firstLine);
  final statusCode = int.tryParse(match?.group(1) ?? '');
  if (statusCode == null) throw const FormatException('代理响应格式无效');
  return statusCode;
}

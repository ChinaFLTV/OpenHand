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
      final raw = utf8.decode(response.takeBytes());
      final headerEnd = raw.indexOf('\r\n\r\n');
      if (headerEnd < 0) throw const FormatException('代理身份响应格式无效');
      final header = raw.substring(0, headerEnd);
      final status = int.tryParse(
        RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})\b').firstMatch(header)?.group(1) ??
            '',
      );
      if (status == 407) throw const FormatException('代理认证失败');
      if (status == null || status < 200 || status >= 300) {
        throw FormatException('代理身份查询返回 HTTP ${status ?? '--'}');
      }
      final body = header.toLowerCase().contains('transfer-encoding: chunked')
          ? _decodeChunkedBody(raw.substring(headerEnd + 4))
          : raw.substring(headerEnd + 4);
      final decoded = jsonDecode(body);
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

String _decodeChunkedBody(String source) {
  final output = StringBuffer();
  var offset = 0;
  while (offset < source.length) {
    final lineEnd = source.indexOf('\r\n', offset);
    if (lineEnd < 0) throw const FormatException('代理身份分块响应无效');
    final size = int.tryParse(
      source.substring(offset, lineEnd).split(';').first.trim(),
      radix: 16,
    );
    if (size == null) throw const FormatException('代理身份分块响应无效');
    if (size == 0) break;
    final start = lineEnd + 2;
    final end = start + size;
    if (end > source.length) throw const FormatException('代理身份响应不完整');
    output.write(source.substring(start, end));
    offset = end + 2;
  }
  return output.toString();
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

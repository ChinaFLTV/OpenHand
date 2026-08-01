import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/ai_exposure_models.dart';

const Duration _kProxyProbeTimeout = Duration(seconds: 8);
const int _kMaxProxyResponseLineBytes = 2048;
const String _kProxyProbeTarget =
    'http://connectivitycheck.gstatic.com/generate_204';

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
}

String _requestHead(Uri proxy) {
  final authorization = _proxyAuthorization(proxy);
  return 'GET $_kProxyProbeTarget HTTP/1.1\r\n'
      'Host: connectivitycheck.gstatic.com\r\n'
      'Accept: */*\r\n'
      'Connection: close\r\n'
      'Proxy-Connection: close\r\n'
      '${authorization == null ? '' : 'Proxy-Authorization: Basic $authorization\r\n'}'
      '\r\n';
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

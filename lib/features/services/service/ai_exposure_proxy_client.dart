import 'dart:io';

import '../model/ai_exposure_models.dart';

/// 为 HttpClient 配置 HTTP/HTTPS 正向代理与基础认证。
void configureAiExposureProxyHttpClient(HttpClient client, Uri proxy) {
  final scheme = proxy.scheme.toLowerCase();
  if (!const <String>{'http', 'https'}.contains(scheme) ||
      proxy.host.isEmpty ||
      proxy.port <= 0) {
    throw const FormatException('中转代理地址无效。');
  }

  client.findProxy = (_) => 'PROXY ${aiExposureProxyAuthority(proxy)}';
  if (scheme == 'https') {
    client.connectionFactory = (target, proxyHost, proxyPort) {
      if (proxyHost != null && proxyPort != null) {
        return SecureSocket.startConnect(proxyHost, proxyPort);
      }
      return target.scheme == 'https'
          ? SecureSocket.startConnect(target.host, target.port)
          : Socket.startConnect(target.host, target.port);
    };
  }

  if (proxy.userInfo.isEmpty) return;
  final credentials = aiExposureProxyCredentials(proxy.userInfo);
  client.addProxyCredentials(
    proxy.host,
    proxy.port,
    '',
    HttpClientBasicCredentials(credentials.username, credentials.password),
  );
}

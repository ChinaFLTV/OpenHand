import 'dart:io';

import '../../shared/util/argument_guards.dart';

const String webReverseCdpLoopbackHost = '127.0.0.1';
const Duration _webReverseCdpMaxHttpTimeout = Duration(minutes: 1);

/// CDP HTTP 端点：获取浏览器版本与 WebSocket 调试 URL。
const String webReverseCdpJsonVersionPath = '/json/version';

Future<T> withWebReverseCdpHttpClient<T>({
  required Future<T> Function(HttpClient client) action,
  Duration connectionTimeout = const Duration(seconds: 2),
  Duration idleTimeout = const Duration(seconds: 2),
}) async {
  requirePositiveDurationAtMost(
    connectionTimeout,
    _webReverseCdpMaxHttpTimeout,
    'connectionTimeout',
  );
  requirePositiveDurationAtMost(
    idleTimeout,
    _webReverseCdpMaxHttpTimeout,
    'idleTimeout',
  );
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.connectionTimeout = connectionTimeout;
  client.idleTimeout = idleTimeout;
  try {
    return await action(client);
  } finally {
    client.close(force: true);
  }
}

Uri webReverseCdpHttpUri(int port, String path) {
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return Uri(
    scheme: 'http',
    host: webReverseCdpLoopbackHost,
    port: port,
    path: normalizedPath,
  );
}

String webReverseCdpHttpOrigin(int port) {
  return Uri(
    scheme: 'http',
    host: webReverseCdpLoopbackHost,
    port: port,
  ).toString();
}

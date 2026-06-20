import 'dart:io';

const String webReverseCdpLoopbackHost = '127.0.0.1';

HttpClient createWebReverseCdpHttpClient({
  Duration connectionTimeout = const Duration(seconds: 2),
  Duration idleTimeout = const Duration(seconds: 2),
}) {
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.connectionTimeout = connectionTimeout;
  client.idleTimeout = idleTimeout;
  return client;
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

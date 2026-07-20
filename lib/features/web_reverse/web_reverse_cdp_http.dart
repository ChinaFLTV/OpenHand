import 'dart:io';

const String webReverseCdpLoopbackHost = '127.0.0.1';

Future<T> withWebReverseCdpHttpClient<T>({
  required Future<T> Function(HttpClient client) action,
  Duration connectionTimeout = const Duration(seconds: 2),
  Duration idleTimeout = const Duration(seconds: 2),
}) async {
  _requirePositiveDuration(connectionTimeout, 'connectionTimeout');
  _requirePositiveDuration(idleTimeout, 'idleTimeout');
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

void _requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, '必须大于零。');
  }
}

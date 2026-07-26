import 'dart:async';
import 'dart:io';
import '../util/argument_guards.dart';

Future<ServerSocket> bindServerSocketBounded(
  Object address,
  int port, {
  required Duration timeout,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
}) {
  return _bindBounded(
    () => ServerSocket.bind(
      address,
      port,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
    ),
    timeout: timeout,
    closeLateServer: (server) => server.close(),
  );
}

Future<HttpServer> bindHttpServerBounded(
  Object address,
  int port, {
  required Duration timeout,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
}) {
  return _bindBounded(
    () => HttpServer.bind(
      address,
      port,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
    ),
    timeout: timeout,
    closeLateServer: (server) => server.close(force: true),
  );
}

Future<T> _bindBounded<T>(
  Future<T> Function() bind, {
  required Duration timeout,
  required Future<void> Function(T server) closeLateServer,
}) async {
  requirePositiveDuration(timeout, 'timeout');
  final bindFuture = bind();
  try {
    return await bindFuture.timeout(timeout);
  } on TimeoutException {
    unawaited(
      bindFuture.then<void>((server) async {
        try {
          await closeLateServer(server).timeout(timeout);
        } catch (_) {
          // A late bind must never surface a second asynchronous failure.
        }
      }, onError: (Object _, StackTrace _) {}),
    );
    rethrow;
  }
}

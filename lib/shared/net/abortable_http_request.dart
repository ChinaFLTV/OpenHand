import 'dart:async';

import 'package:http/http.dart' as http;

/// Sends a regular package:http request as an [http.AbortableRequest].
///
/// External cancellation aborts both header acquisition and a subsequently
/// consumed response stream. A header timeout also aborts the underlying I/O
/// instead of only detaching the caller's wait.
Future<http.StreamedResponse> sendAbortableHttpRequest({
  required http.Client client,
  required http.Request request,
  required Duration connectionTimeout,
  Future<void>? cancelSignal,
}) async {
  if (connectionTimeout <= Duration.zero) {
    throw ArgumentError.value(
      connectionTimeout,
      'connectionTimeout',
      'Must be positive.',
    );
  }
  if (request.finalized) {
    throw StateError('Cannot send an already finalized HTTP request.');
  }

  final connectionTimeoutAbort = Completer<void>();
  final normalizedCancelSignal = cancelSignal?.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {},
  );
  final abortTrigger = normalizedCancelSignal == null
      ? connectionTimeoutAbort.future
      : Future.any<void>([
          normalizedCancelSignal,
          connectionTimeoutAbort.future,
        ]);
  final abortableRequest =
      http.AbortableRequest(
          request.method,
          request.url,
          abortTrigger: abortTrigger,
        )
        ..headers.addAll(request.headers)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection
        ..bodyBytes = request.bodyBytes;

  return client
      .send(abortableRequest)
      .timeout(
        connectionTimeout,
        onTimeout: () {
          if (!connectionTimeoutAbort.isCompleted) {
            connectionTimeoutAbort.complete();
          }
          throw TimeoutException(
            'HTTP response headers exceeded the connection time limit.',
            connectionTimeout,
          );
        },
      );
}

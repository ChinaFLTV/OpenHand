import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads an HTTP response into memory with explicit idle, total, and size
/// limits. Callers remain responsible for closing the owning [HttpClient].
Future<Uint8List> readBoundedHttpResponseBytes(
  HttpClientResponse response, {
  required int maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
}) {
  if (maxBytes < 1) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
  }
  if (idleTimeout <= Duration.zero) {
    throw ArgumentError.value(idleTimeout, 'idleTimeout', 'Must be positive.');
  }
  if (totalTimeout != null && totalTimeout <= Duration.zero) {
    throw ArgumentError.value(
      totalTimeout,
      'totalTimeout',
      'Must be positive.',
    );
  }
  if (response.contentLength > maxBytes) {
    throw HttpException('HTTP response exceeds the $maxBytes byte limit.');
  }

  return readBoundedByteStream(
    response,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
}

Future<String> readBoundedHttpResponseText(
  HttpClientResponse response, {
  required int maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
  bool allowMalformed = false,
}) async {
  final bytes = await readBoundedHttpResponseBytes(
    response,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  return utf8.decode(bytes, allowMalformed: allowMalformed);
}

/// Collects a package:http or dart:io byte stream with explicit memory and
/// timing bounds. The subscription is cancelled when any limit wins, so a
/// timed-out producer cannot keep buffering in the background.
Future<Uint8List> readBoundedByteStream(
  Stream<List<int>> stream, {
  required int maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
}) {
  return _consumeByteStream(
    stream,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
    retainBytes: true,
  );
}

Future<String> readBoundedByteStreamText(
  Stream<List<int>> stream, {
  required int maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
  bool allowMalformed = false,
}) async {
  final bytes = await readBoundedByteStream(
    stream,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  return utf8.decode(bytes, allowMalformed: allowMalformed);
}

/// Discards a response stream while retaining connection-pool hygiene without
/// allowing a hostile peer to hold the caller forever.
Future<void> drainByteStreamWithTimeout(
  Stream<List<int>> stream, {
  required Duration idleTimeout,
  required Duration totalTimeout,
}) async {
  await _consumeByteStream(
    stream,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
    retainBytes: false,
  );
}

Future<Uint8List> _consumeByteStream(
  Stream<List<int>> stream, {
  int? maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
  required bool retainBytes,
}) {
  if (maxBytes != null && maxBytes < 1) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
  }
  if (idleTimeout <= Duration.zero) {
    throw ArgumentError.value(idleTimeout, 'idleTimeout', 'Must be positive.');
  }
  if (totalTimeout != null && totalTimeout <= Duration.zero) {
    throw ArgumentError.value(
      totalTimeout,
      'totalTimeout',
      'Must be positive.',
    );
  }

  final completer = Completer<Uint8List>();
  final bytes = retainBytes ? BytesBuilder(copy: false) : null;
  StreamSubscription<List<int>>? subscription;
  Timer? idleTimer;
  Timer? totalTimer;
  var receivedBytes = 0;
  var settled = false;

  void cancelTimers() {
    idleTimer?.cancel();
    totalTimer?.cancel();
    idleTimer = null;
    totalTimer = null;
  }

  void cancelSubscription() {
    final active = subscription;
    if (active == null) return;
    unawaited(
      active.cancel().catchError((Object _, StackTrace _) {
        // The primary response/limit result must not be replaced by a cleanup
        // failure from a transport that is already being discarded.
      }),
    );
  }

  void fail(Object error, StackTrace stack) {
    if (settled) return;
    settled = true;
    cancelTimers();
    cancelSubscription();
    completer.completeError(error, stack);
  }

  void resetIdleTimer() {
    idleTimer?.cancel();
    idleTimer = Timer(
      idleTimeout,
      () => fail(
        TimeoutException('HTTP response stream stalled.', idleTimeout),
        StackTrace.current,
      ),
    );
  }

  if (totalTimeout != null) {
    totalTimer = Timer(
      totalTimeout,
      () => fail(
        TimeoutException(
          'HTTP response stream exceeded its total time limit.',
          totalTimeout,
        ),
        StackTrace.current,
      ),
    );
  }
  resetIdleTimer();
  try {
    subscription = stream.listen(
      (chunk) {
        if (settled) return;
        resetIdleTimer();
        receivedBytes += chunk.length;
        if (maxBytes != null && receivedBytes > maxBytes) {
          fail(
            HttpException('HTTP response exceeds the $maxBytes byte limit.'),
            StackTrace.current,
          );
          return;
        }
        bytes?.add(chunk);
      },
      onError: (Object error, StackTrace stack) => fail(error, stack),
      onDone: () {
        if (settled) return;
        settled = true;
        cancelTimers();
        completer.complete(bytes?.takeBytes() ?? Uint8List(0));
      },
      cancelOnError: true,
    );
  } catch (error, stack) {
    fail(error, stack);
  }
  if (settled) {
    cancelSubscription();
  }
  return completer.future;
}

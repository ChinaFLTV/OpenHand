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
/// When [truncateOnOverflow] is true, the byte limit returns a prefix instead
/// of throwing and completes as soon as the limit is reached; this is intended
/// for bounded diagnostic/error previews.
Future<Uint8List> readBoundedByteStream(
  Stream<List<int>> stream, {
  required int maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
  bool truncateOnOverflow = false,
}) {
  return _consumeByteStream(
    stream,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
    retainBytes: true,
    truncateOnOverflow: truncateOnOverflow,
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

/// Streams bytes to an asynchronous sink with backpressure while enforcing
/// the same idle, total, and size bounds as in-memory response collection.
Future<int> writeBoundedByteStream(
  Stream<List<int>> stream, {
  required Future<void> Function(List<int> chunk) writeChunk,
  required int maxBytes,
  required Duration idleTimeout,
  required Duration totalTimeout,
}) async {
  if (maxBytes < 1) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
  }
  var writtenBytes = 0;
  final writeStream = stream.asyncMap<List<int>>((chunk) async {
    final nextByteCount = writtenBytes + chunk.length;
    if (nextByteCount > maxBytes) {
      throw HttpException('HTTP response exceeds the $maxBytes byte limit.');
    }
    await writeChunk(chunk);
    writtenBytes = nextByteCount;
    return const <int>[];
  });
  await drainByteStreamWithTimeout(
    writeStream,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  return writtenBytes;
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
    truncateOnOverflow: false,
  );
}

Future<Uint8List> _consumeByteStream(
  Stream<List<int>> stream, {
  int? maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
  required bool retainBytes,
  required bool truncateOnOverflow,
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
        final nextByteCount = receivedBytes + chunk.length;
        if (maxBytes != null &&
            truncateOnOverflow &&
            nextByteCount >= maxBytes) {
          final remaining = maxBytes - receivedBytes;
          if (remaining > 0) {
            bytes?.add(chunk.take(remaining).toList(growable: false));
          }
          settled = true;
          cancelTimers();
          cancelSubscription();
          completer.complete(bytes?.takeBytes() ?? Uint8List(0));
          return;
        }
        if (maxBytes != null && nextByteCount > maxBytes) {
          fail(
            HttpException('HTTP response exceeds the $maxBytes byte limit.'),
            StackTrace.current,
          );
          return;
        }
        receivedBytes = nextByteCount;
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

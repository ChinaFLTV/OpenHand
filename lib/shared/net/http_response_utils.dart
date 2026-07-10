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

  final readFuture = _collectBoundedHttpResponseBytes(
    response,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
  );
  return totalTimeout == null ? readFuture : readFuture.timeout(totalTimeout);
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

Future<Uint8List> _collectBoundedHttpResponseBytes(
  HttpClientResponse response, {
  required int maxBytes,
  required Duration idleTimeout,
}) async {
  final bytes = BytesBuilder(copy: false);
  var received = 0;
  await for (final chunk in response.timeout(idleTimeout)) {
    received += chunk.length;
    if (received > maxBytes) {
      throw HttpException('HTTP response exceeds the $maxBytes byte limit.');
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

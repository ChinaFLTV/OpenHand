import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../../app/support/system_proxy.dart';
import '../../../../shared/net/http_response_utils.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';

const String _contentTypeHeaderName = 'content-type';
const Duration _fallbackRequestTimeout = Duration(seconds: 60);
const Duration _responseIdleTimeout = Duration(seconds: 30);
const Duration _fileCleanupTimeout = Duration(seconds: 2);
const int defaultAiTransportResponseMaxBytes = 16 * kBytesPerMiB;
const int defaultAiTransportErrorResponseMaxBytes = kBytesPerMiB;
const int defaultAiTransportDownloadMaxBytes = 64 * kBytesPerMiB;
const int defaultAiTransportFileDownloadMaxBytes = 512 * kBytesPerMiB;
const int defaultAiMultipartFileMaxBytes = 256 * kBytesPerMiB;
const int defaultAiMultipartTotalMaxBytes = 512 * kBytesPerMiB;

typedef AiMultipartFileLengthReader = Future<int> Function(String filePath);

Future<int> _readMultipartFileLength(String filePath) {
  return File(filePath).length();
}

class AiMultipartUploadFile {
  const AiMultipartUploadFile({required this.filePath, this.filename});

  final String filePath;
  final String? filename;
}

class AiTransportFileDownloadResult {
  const AiTransportFileDownloadResult({
    required this.statusCode,
    required this.headers,
    required this.bytesWritten,
    required this.errorBody,
    this.filePath,
    this.reasonPhrase,
  });

  final int statusCode;
  final Map<String, String> headers;
  final int bytesWritten;
  final String errorBody;
  final String? filePath;
  final String? reasonPhrase;

  bool get isSuccess => isHttpSuccessStatus(statusCode);
}

class AiTransportResponseException implements Exception {
  const AiTransportResponseException({
    required this.statusCode,
    required this.body,
    required this.uri,
    this.reasonPhrase,
  });

  final int statusCode;
  final String body;
  final Uri uri;
  final String? reasonPhrase;

  @override
  String toString() {
    final reason = nullIfBlank(reasonPhrase);
    final preview = nullIfBlank(body);
    return [
      'HTTP $statusCode${reason == null ? '' : ' $reason'}',
      if (preview != null) preview,
    ].join(': ');
  }
}

class AiTransportClient {
  AiTransportClient({
    http.Client? client,
    AiMultipartFileLengthReader? multipartFileLengthReader,
  }) : _client = client ?? SystemProxyResolver.instance.createHttpClient(),
       _ownsClient = client == null,
       _multipartFileLengthReader =
           multipartFileLengthReader ?? _readMultipartFileLength;

  final http.Client _client;
  final bool _ownsClient;
  final AiMultipartFileLengthReader _multipartFileLengthReader;
  final Set<Completer<void>> _activeAborts = <Completer<void>>{};
  bool _disposed = false;

  Future<http.Response> sendJson({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? body,
    required Duration timeout,
    int maxResponseBytes = defaultAiTransportResponseMaxBytes,
  }) async {
    _requirePositive(maxResponseBytes, 'maxResponseBytes');
    final encodedBody = jsonEncode(body);
    return _runAbortable((abort) {
      final request =
          http.AbortableRequest(
              method.toUpperCase(),
              uri,
              abortTrigger: abort.future,
            )
            ..headers.addAll(headers)
            ..body = encodedBody;
      return _send(
        request,
        abort: abort,
        timeout: timeout,
        maxResponseBytes: maxResponseBytes,
      );
    });
  }

  Future<http.Response> sendForm({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Map<String, String> body,
    required Duration timeout,
    int maxResponseBytes = defaultAiTransportResponseMaxBytes,
  }) async {
    _requirePositive(maxResponseBytes, 'maxResponseBytes');
    return _runAbortable((abort) {
      final request =
          http.AbortableRequest(
              method.toUpperCase(),
              uri,
              abortTrigger: abort.future,
            )
            ..headers.addAll(headers)
            ..bodyFields = body;
      return _send(
        request,
        abort: abort,
        timeout: timeout,
        maxResponseBytes: maxResponseBytes,
      );
    });
  }

  Future<http.Response> sendText({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
    Encoding encoding = utf8,
    int maxResponseBytes = defaultAiTransportResponseMaxBytes,
  }) async {
    _requirePositive(maxResponseBytes, 'maxResponseBytes');
    return _runAbortable((abort) {
      final request = http.AbortableRequest(
        method.toUpperCase(),
        uri,
        abortTrigger: abort.future,
      )..headers.addAll(headers);
      if (body.isNotEmpty) {
        request
          ..encoding = encoding
          ..body = body;
      }
      return _send(
        request,
        abort: abort,
        timeout: timeout,
        maxResponseBytes: maxResponseBytes,
      );
    });
  }

  /// Sends JSON and lets [consume] process a bounded successful response
  /// incrementally. HTTP failures are converted to a bounded
  /// [AiTransportResponseException].
  Future<T> consumeJsonStream<T>({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? body,
    required Duration timeout,
    required int maxResponseBytes,
    required Future<T> Function(
      http.StreamedResponse response,
      Stream<List<int>> stream,
    )
    consume,
  }) async {
    _requirePositive(maxResponseBytes, 'maxResponseBytes');
    final encodedBody = jsonEncode(body);
    return _runAbortable((abort) {
      final request =
          http.AbortableRequest(
              method.toUpperCase(),
              uri,
              abortTrigger: abort.future,
            )
            ..headers.addAll(headers)
            ..body = encodedBody;
      return _executeRequest(
        request,
        abort: abort,
        timeout: timeout,
        consume: (streamed, remainingBudget) async {
          if (isHttpFailureStatus(streamed.statusCode)) {
            final response = await _collectResponse(
              streamed,
              requestUrl: uri,
              remainingBudget: remainingBudget,
              maxResponseBytes: maxResponseBytes,
            );
            throw AiTransportResponseException(
              statusCode: response.statusCode,
              body: response.body,
              uri: uri,
              reasonPhrase: response.reasonPhrase,
            );
          }
          _rejectOversizedDeclaredResponse(
            streamed,
            responseLimit: maxResponseBytes,
            requestUrl: uri,
          );
          final remaining = _requireRemainingBudget(remainingBudget);
          final stream = limitByteStream(
            streamed.stream,
            maxBytes: maxResponseBytes,
            idleTimeout: _shorterDuration(_responseIdleTimeout, remaining),
            totalTimeout: remaining,
          );
          try {
            return await consume(streamed, stream).timeout(
              remaining,
              onTimeout: () => throw TimeoutException(
                'HTTP response exceeded the request time limit.',
                remaining,
              ),
            );
          } finally {
            _cancelResponseStream(streamed.stream);
          }
        },
      );
    });
  }

  Future<http.Response> sendMultipart({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required Duration timeout,
    int maxResponseBytes = defaultAiTransportResponseMaxBytes,
    int maxFileBytes = defaultAiMultipartFileMaxBytes,
    int maxTotalBytes = defaultAiMultipartTotalMaxBytes,
  }) async {
    _requirePositive(maxResponseBytes, 'maxResponseBytes');
    _requirePositive(maxFileBytes, 'maxFileBytes');
    _requirePositive(maxTotalBytes, 'maxTotalBytes');
    final effectiveTimeout = _effectiveRequestTimeout(timeout);
    return _runAbortable((abort) async {
      final preparation = Stopwatch()..start();
      try {
        final request = http.AbortableMultipartRequest(
          method.toUpperCase(),
          uri,
          abortTrigger: abort.future,
        );
        headers.forEach((key, value) {
          if (lowercaseStringFromValue(key) == _contentTypeHeaderName) return;
          request.headers[key] = value;
        });
        var totalFileBytes = 0;

        Future<void> addFile(String field, AiMultipartUploadFile upload) async {
          final remaining = effectiveTimeout - preparation.elapsed;
          if (remaining <= Duration.zero) {
            throw TimeoutException(
              'Multipart request preparation exceeded its time limit.',
              effectiveTimeout,
            );
          }
          final length = await _multipartFileLengthReader(upload.filePath)
              .timeout(
                remaining,
                onTimeout: () => throw TimeoutException(
                  'Multipart file inspection exceeded the request time limit.',
                  effectiveTimeout,
                ),
              );
          if (length < 0) {
            throw FileSystemException(
              'Multipart file reported an invalid negative size.',
              upload.filePath,
            );
          }
          if (length > maxFileBytes) {
            throw HttpException(
              'Multipart file exceeds the $maxFileBytes byte limit.',
              uri: Uri.file(upload.filePath),
            );
          }
          if (totalFileBytes > maxTotalBytes - length) {
            throw HttpException(
              'Multipart files exceed the $maxTotalBytes byte total limit.',
              uri: uri,
            );
          }
          totalFileBytes += length;
          request.files.add(
            http.MultipartFile(
              field,
              File(upload.filePath).openRead(0, length),
              length,
              filename: upload.filename ?? p.basename(upload.filePath),
            ),
          );
        }

        for (final entry in body.entries) {
          final key = entry.key;
          final value = entry.value;
          if (value == null) continue;
          if (value is AiMultipartUploadFile) {
            await addFile(key, value);
            continue;
          }
          if (value is List<AiMultipartUploadFile>) {
            for (final item in value) {
              await addFile(key, item);
            }
            continue;
          }
          request.fields[key] = _multipartFieldValue(value);
        }
        if (request.contentLength > maxTotalBytes) {
          throw HttpException(
            'Multipart request exceeds the $maxTotalBytes byte total limit.',
            uri: uri,
          );
        }
        final remaining = effectiveTimeout - preparation.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException(
            'Multipart request preparation exceeded its time limit.',
            effectiveTimeout,
          );
        }
        return await _send(
          request,
          abort: abort,
          timeout: remaining,
          maxResponseBytes: maxResponseBytes,
        );
      } finally {
        preparation.stop();
      }
    });
  }

  Future<http.Response> get({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
    int maxResponseBytes = defaultAiTransportResponseMaxBytes,
  }) async {
    return _get(
      uri: uri,
      headers: headers,
      timeout: timeout,
      maxResponseBytes: maxResponseBytes,
    );
  }

  Future<List<int>> downloadBytes({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
    int maxBytes = defaultAiTransportDownloadMaxBytes,
  }) async {
    final response = await _get(
      uri: uri,
      headers: headers,
      timeout: timeout,
      maxResponseBytes: maxBytes,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  /// Streams a successful response to [destination] without retaining the
  /// payload in memory. Non-success bodies remain bounded diagnostic previews.
  /// A partial destination is removed when any limit or I/O operation fails.
  Future<AiTransportFileDownloadResult> downloadToFile({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
    required File destination,
    int maxBytes = defaultAiTransportFileDownloadMaxBytes,
    int maxJsonBytes = defaultAiTransportResponseMaxBytes,
  }) {
    _requirePositive(maxBytes, 'maxBytes');
    _requirePositive(maxJsonBytes, 'maxJsonBytes');
    return _runAbortable((abort) {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..headers.addAll(headers);
      return _executeRequest(
        request,
        abort: abort,
        timeout: timeout,
        consume: (streamed, remainingBudget) async {
          if (isHttpFailureStatus(streamed.statusCode)) {
            final response = await _collectResponse(
              streamed,
              requestUrl: uri,
              remainingBudget: remainingBudget,
              maxResponseBytes: maxJsonBytes,
            );
            return AiTransportFileDownloadResult(
              statusCode: response.statusCode,
              headers: Map<String, String>.unmodifiable(response.headers),
              bytesWritten: 0,
              errorBody: response.body,
              reasonPhrase: response.reasonPhrase,
            );
          }

          final contentType = _headerValue(streamed.headers, 'content-type');
          final responseLimit = _isJsonContentType(contentType)
              ? _smallerInt(maxBytes, maxJsonBytes)
              : maxBytes;
          _rejectOversizedDeclaredResponse(
            streamed,
            responseLimit: responseLimit,
            requestUrl: uri,
          );
          final bytesWritten = await _writeResponseToFile(
            streamed,
            destination: destination,
            responseLimit: responseLimit,
            remainingBudget: remainingBudget,
          );
          return AiTransportFileDownloadResult(
            statusCode: streamed.statusCode,
            headers: Map<String, String>.unmodifiable(streamed.headers),
            bytesWritten: bytesWritten,
            errorBody: '',
            filePath: destination.path,
            reasonPhrase: streamed.reasonPhrase,
          );
        },
      );
    });
  }

  Future<http.Response> _send(
    http.BaseRequest request, {
    required Completer<void> abort,
    required Duration timeout,
    required int maxResponseBytes,
  }) {
    _requirePositive(maxResponseBytes, 'maxResponseBytes');
    return _executeRequest(
      request,
      abort: abort,
      timeout: timeout,
      consume: (streamed, remainingBudget) => _collectResponse(
        streamed,
        requestUrl: request.url,
        remainingBudget: remainingBudget,
        maxResponseBytes: maxResponseBytes,
      ),
    );
  }

  Future<T> _executeRequest<T>(
    http.BaseRequest request, {
    required Completer<void> abort,
    required Duration timeout,
    required Future<T> Function(
      http.StreamedResponse response,
      Duration Function() remainingBudget,
    )
    consume,
  }) async {
    final effectiveTimeout = _effectiveRequestTimeout(timeout);
    final stopwatch = Stopwatch()..start();
    Duration remainingBudget() => effectiveTimeout - stopwatch.elapsed;
    try {
      final sendFuture = _client.send(request);
      final streamed = await sendFuture.timeout(
        effectiveTimeout,
        onTimeout: () {
          _abort(abort);
          unawaited(_cancelLateResponse(sendFuture));
          throw TimeoutException(
            'HTTP response headers exceeded the request time limit.',
            effectiveTimeout,
          );
        },
      );
      final remaining = remainingBudget();
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'HTTP response exceeded the request time limit.',
          effectiveTimeout,
        );
      }
      return await consume(streamed, remainingBudget);
    } finally {
      // Completing after a successful body read is harmless and releases the
      // callbacks retained by clients that observe the abort trigger.
      _abort(abort);
      stopwatch.stop();
    }
  }

  Future<http.Response> _collectResponse(
    http.StreamedResponse streamed, {
    required Uri requestUrl,
    required Duration Function() remainingBudget,
    required int maxResponseBytes,
  }) async {
    final isFailure = isHttpFailureStatus(streamed.statusCode);
    final responseLimit = isFailure
        ? _smallerInt(maxResponseBytes, defaultAiTransportErrorResponseMaxBytes)
        : maxResponseBytes;
    if (!isFailure) {
      _rejectOversizedDeclaredResponse(
        streamed,
        responseLimit: responseLimit,
        requestUrl: requestUrl,
      );
    }
    final remaining = remainingBudget();
    if (remaining <= Duration.zero) {
      throw TimeoutException('HTTP response exceeded the request time limit.');
    }
    final bodyBytes = await readBoundedByteStream(
      streamed.stream,
      maxBytes: responseLimit,
      idleTimeout: _shorterDuration(_responseIdleTimeout, remaining),
      totalTimeout: remaining,
      truncateOnOverflow: isFailure,
    );
    return http.Response.bytes(
      bodyBytes,
      streamed.statusCode,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  Future<http.Response> _get({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
    required int maxResponseBytes,
  }) {
    return _runAbortable((abort) {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..headers.addAll(headers);
      return _send(
        request,
        abort: abort,
        timeout: timeout,
        maxResponseBytes: maxResponseBytes,
      );
    });
  }

  Future<int> _writeResponseToFile(
    http.StreamedResponse response, {
    required File destination,
    required int responseLimit,
    required Duration Function() remainingBudget,
  }) async {
    RandomAccessFile? output;
    Future<void>? outputClose;
    var removeDestinationOnExit = false;
    try {
      final destinationExists = await _runWithinBudget(
        remainingBudget,
        destination.exists,
        'Checking the download destination timed out.',
      );
      if (destinationExists) {
        throw FileSystemException(
          'Refusing to overwrite an existing download destination.',
          destination.path,
        );
      }
      await _runWithinBudget(
        remainingBudget,
        () => destination.parent.create(recursive: true),
        'Creating the download directory timed out.',
      );
      final openedOutput = await _openDownloadDestination(
        destination,
        remainingBudget,
      );
      output = openedOutput;
      removeDestinationOnExit = true;
      final remaining = _requireRemainingBudget(remainingBudget);
      final bytesWritten = await writeBoundedByteStream(
        response.stream,
        writeChunk: openedOutput.writeFrom,
        maxBytes: responseLimit,
        idleTimeout: _shorterDuration(_responseIdleTimeout, remaining),
        totalTimeout: remaining,
      );
      await _runWithinBudget(
        remainingBudget,
        openedOutput.flush,
        'Flushing the downloaded file timed out.',
      );
      final closeFuture = openedOutput.close();
      outputClose = closeFuture;
      await closeFuture.timeout(
        _requireRemainingBudget(remainingBudget),
        onTimeout: () =>
            throw TimeoutException('Closing the downloaded file timed out.'),
      );
      output = null;
      outputClose = null;
      removeDestinationOnExit = false;
      return bytesWritten;
    } catch (_) {
      _cancelResponseStream(response.stream);
      rethrow;
    } finally {
      final activeOutput = output;
      if (activeOutput != null) {
        try {
          await (outputClose ?? activeOutput.close()).timeout(
            _fileCleanupTimeout,
          );
        } catch (_) {
          // Preserve the primary transport or file error.
        }
      }
      if (removeDestinationOnExit) {
        try {
          if (await destination.exists().timeout(_fileCleanupTimeout)) {
            await destination.delete().timeout(_fileCleanupTimeout);
          }
        } catch (_) {
          // Partial-file cleanup is best effort and must remain bounded.
        }
      }
    }
  }

  void _rejectOversizedDeclaredResponse(
    http.StreamedResponse response, {
    required int responseLimit,
    required Uri requestUrl,
  }) {
    final declaredLength = response.contentLength;
    if (declaredLength == null || declaredLength <= responseLimit) return;
    _cancelResponseStream(response.stream);
    throw HttpException(
      'HTTP response exceeds the $responseLimit byte limit.',
      uri: requestUrl,
    );
  }

  Future<T> _runWithinBudget<T>(
    Duration Function() remainingBudget,
    Future<T> Function() operation,
    String timeoutMessage,
  ) {
    final remaining = _requireRemainingBudget(remainingBudget);
    return operation().timeout(
      remaining,
      onTimeout: () => throw TimeoutException(timeoutMessage, remaining),
    );
  }

  Future<RandomAccessFile> _openDownloadDestination(
    File destination,
    Duration Function() remainingBudget,
  ) async {
    final remaining = _requireRemainingBudget(remainingBudget);
    final openFuture = destination.open(mode: FileMode.writeOnly);
    try {
      return await openFuture.timeout(
        remaining,
        onTimeout: () => throw TimeoutException(
          'Opening the download destination timed out.',
          remaining,
        ),
      );
    } on TimeoutException {
      unawaited(_cleanupLateOpenedDestination(openFuture, destination));
      rethrow;
    }
  }

  Future<void> _cleanupLateOpenedDestination(
    Future<RandomAccessFile> openFuture,
    File destination,
  ) async {
    try {
      final output = await openFuture;
      await output.close().timeout(_fileCleanupTimeout);
    } catch (_) {
      // A timed-out resource acquisition must never surface a late cleanup
      // failure or retain an open handle indefinitely.
    }
    try {
      if (await destination.exists().timeout(_fileCleanupTimeout)) {
        await destination.delete().timeout(_fileCleanupTimeout);
      }
    } catch (_) {
      // The caller has already received the timeout; cleanup stays best effort.
    }
  }

  Duration _requireRemainingBudget(Duration Function() remainingBudget) {
    final remaining = remainingBudget();
    if (remaining <= Duration.zero) {
      throw TimeoutException('HTTP response exceeded the request time limit.');
    }
    return remaining;
  }

  String? _headerValue(Map<String, String> headers, String name) {
    final normalizedName = lowercaseStringFromValue(name);
    for (final entry in headers.entries) {
      if (lowercaseStringFromValue(entry.key) == normalizedName) {
        return nullIfBlank(entry.value);
      }
    }
    return null;
  }

  bool _isJsonContentType(String? contentType) {
    final mimeType = lowercaseStringFromValue(
      (contentType ?? '').split(';').first,
    );
    return mimeType == 'application/json' ||
        mimeType == 'text/json' ||
        mimeType.endsWith('+json');
  }

  void _requirePositive(int value, String name) {
    if (value < 1) {
      throw ArgumentError.value(value, name, 'Must be positive.');
    }
  }

  int _smallerInt(int first, int second) => first < second ? first : second;

  Duration _shorterDuration(Duration first, Duration second) {
    return first < second ? first : second;
  }

  Future<T> _runAbortable<T>(
    Future<T> Function(Completer<void> abort) operation,
  ) async {
    final abort = _createAbort();
    try {
      return await operation(abort);
    } finally {
      _abort(abort);
    }
  }

  Completer<void> _createAbort() {
    if (_disposed) {
      throw StateError('AI transport client has been disposed.');
    }
    final abort = Completer<void>();
    _activeAborts.add(abort);
    return abort;
  }

  void _abort(Completer<void> abort) {
    if (!abort.isCompleted) abort.complete();
    _activeAborts.remove(abort);
  }

  void _cancelResponseStream(Stream<List<int>> stream) {
    try {
      final subscription = stream.listen(
        null,
        onError: (Object _, StackTrace _) {},
      );
      unawaited(
        subscription.cancel().catchError((Object _, StackTrace _) {
          // Cleanup failures must not replace the response-size error.
        }),
      );
    } catch (_) {
      // The response has already been aborted; a synchronous listen failure
      // carries no additional actionable information.
    }
  }

  Future<void> _cancelLateResponse(
    Future<http.StreamedResponse> responseFuture,
  ) async {
    try {
      final response = await responseFuture;
      _cancelResponseStream(response.stream);
    } catch (_) {
      // A late transport failure is already represented by the timeout.
    }
  }

  Duration _effectiveRequestTimeout(Duration timeout) {
    return timeout > Duration.zero ? timeout : _fallbackRequestTimeout;
  }

  String _multipartFieldValue(Object value) {
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return jsonEncode(value);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final aborts = _activeAborts.toList(growable: false);
    _activeAborts.clear();
    for (final abort in aborts) {
      if (!abort.isCompleted) abort.complete();
    }
    if (_ownsClient) {
      _client.close();
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../../app/support/system_proxy.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_response_utils.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/argument_guards.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/duration_bounds.dart';
import '../../../../shared/util/input_value_parsing.dart';

const Duration _fallbackRequestTimeout = Duration(seconds: 60);
const Duration _responseIdleTimeout = Duration(seconds: 30);
const Duration _fileCleanupTimeout = Duration(seconds: 2);
const int _multipartReadChunkBytes = 64 * kBytesPerKiB;
const int defaultAiTransportResponseMaxBytes = 16 * kBytesPerMiB;
const int defaultAiTransportErrorResponseMaxBytes = kBytesPerMiB;
const int defaultAiTransportDownloadMaxBytes = 64 * kBytesPerMiB;
const int defaultAiTransportFileDownloadMaxBytes = 512 * kBytesPerMiB;
const int defaultAiMultipartFileMaxBytes = 256 * kBytesPerMiB;
const int defaultAiMultipartTotalMaxBytes = 512 * kBytesPerMiB;
const int defaultAiMultipartMaxFiles = 128;
const int _maxConcurrentAiTransportRequests = 16;
const int _maxQueuedAiTransportRequests = 128;
const Duration _aiTransportQueueTimeout = Duration(seconds: 30);

typedef AiMultipartFileLengthReader = Future<int> Function(String filePath);

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

class _AiMultipartFileLease {
  _AiMultipartFileLease({required this.file, required RandomAccessFile input})
    : input = BoundedRandomAccessFileLease(input);

  final File file;
  final BoundedRandomAccessFileLease input;
  late final int length;
  late final List<String> chunkDigests;

  Future<void> close() => input.cleanup();
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
       _multipartFileLengthReader = multipartFileLengthReader;

  final http.Client _client;
  final bool _ownsClient;
  final AiMultipartFileLengthReader? _multipartFileLengthReader;
  final OpenHandAsyncSemaphore _requestSlots = OpenHandAsyncSemaphore(
    _maxConcurrentAiTransportRequests,
    maxWaiters: _maxQueuedAiTransportRequests,
  );
  final Set<Completer<void>> _activeAborts = <Completer<void>>{};
  bool _disposed = false;

  Future<http.Response> sendJson({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? body,
    required Duration timeout,
    int maxResponseBytes = defaultAiTransportResponseMaxBytes,
    Future<void>? cancelSignal,
  }) async {
    requirePositiveInt(maxResponseBytes, 'maxResponseBytes');
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
    }, cancelSignal: cancelSignal);
  }

  Future<http.Response> sendForm({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Map<String, String> body,
    required Duration timeout,
    int maxResponseBytes = defaultAiTransportResponseMaxBytes,
    Future<void>? cancelSignal,
  }) async {
    requirePositiveInt(maxResponseBytes, 'maxResponseBytes');
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
    }, cancelSignal: cancelSignal);
  }

  Future<http.Response> sendText({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
    Encoding encoding = utf8,
    int maxResponseBytes = defaultAiTransportResponseMaxBytes,
    Future<void>? cancelSignal,
  }) async {
    requirePositiveInt(maxResponseBytes, 'maxResponseBytes');
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
    }, cancelSignal: cancelSignal);
  }

  /// 发送 JSON，并由 [consume] 增量处理有界的成功响应。HTTP 失败响应会转换为
  /// 有界的 [AiTransportResponseException]。
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
    Future<void>? cancelSignal,
  }) async {
    requirePositiveInt(maxResponseBytes, 'maxResponseBytes');
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
            idleTimeout: shorterDuration(_responseIdleTimeout, remaining),
            totalTimeout: remaining,
          );
          try {
            return await consume(streamed, stream).timeout(
              remaining,
              onTimeout: () =>
                  throw TimeoutException('HTTP 响应超过请求时限。', remaining),
            );
          } finally {
            unawaited(cancelByteStream(streamed.stream));
          }
        },
      );
    }, cancelSignal: cancelSignal);
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
    int maxFiles = defaultAiMultipartMaxFiles,
    Future<void>? cancelSignal,
  }) async {
    requirePositiveInt(maxResponseBytes, 'maxResponseBytes');
    requirePositiveInt(maxFileBytes, 'maxFileBytes');
    requirePositiveInt(maxTotalBytes, 'maxTotalBytes');
    requirePositiveInt(maxFiles, 'maxFiles');
    final effectiveTimeout = _effectiveRequestTimeout(timeout);
    return _runAbortable((abort) async {
      final preparation = Stopwatch()..start();
      final fileLeases = <_AiMultipartFileLease>{};
      Duration remainingPreparation() {
        final remaining = effectiveTimeout - preparation.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException('Multipart 请求准备超过时限。', effectiveTimeout);
        }
        return remaining;
      }

      try {
        final request = http.AbortableMultipartRequest(
          method.toUpperCase(),
          uri,
          abortTrigger: abort.future,
        );
        headers.forEach((key, value) {
          if (lowercaseStringFromValue(key) == kContentTypeHeaderName) return;
          request.headers[key] = value;
        });
        var totalFileBytes = 0;
        var fileCount = 0;

        Future<void> addFile(String field, AiMultipartUploadFile upload) async {
          if (fileCount >= maxFiles) {
            throw HttpException('Multipart 请求超过 $maxFiles 个文件上限。', uri: uri);
          }
          fileCount += 1;
          final file = File(upload.filePath);
          final reader = _multipartFileLengthReader;
          int? inspectedLength;
          if (reader != null) {
            inspectedLength = await reader(upload.filePath).timeout(
              remainingPreparation(),
              onTimeout: () => throw TimeoutException(
                'Multipart 文件检查超过请求时限。',
                effectiveTimeout,
              ),
            );
            _validateMultipartFileLength(
              inspectedLength,
              file: file,
              maxFileBytes: maxFileBytes,
              requestUri: uri,
            );
          }

          final preflightStat = await file.stat().timeout(
            remainingPreparation(),
          );
          if (!isRegularFileStat(preflightStat)) {
            throw FileSystemException('Multipart 上传路径不是普通文件。', file.path);
          }
          final input = await _openMultipartInput(file, remainingPreparation);
          final lease = _AiMultipartFileLease(file: file, input: input);
          fileLeases.add(lease);
          final initialStat = await file.stat().timeout(remainingPreparation());
          if (!isRegularFileStat(initialStat) ||
              initialStat.size != preflightStat.size ||
              initialStat.modified != preflightStat.modified ||
              initialStat.changed != preflightStat.changed) {
            throw FileSystemException('Multipart 上传文件在打开前已变更。', file.path);
          }
          final length = await lease.input.run(
            (input) => input.length(),
            timeout: remainingPreparation(),
          );
          _validateMultipartFileLength(
            length,
            file: file,
            maxFileBytes: maxFileBytes,
            requestUri: uri,
          );
          if (length != initialStat.size) {
            throw FileSystemException('Multipart 上传文件在打开前已变更。', file.path);
          }
          if (inspectedLength != null && inspectedLength != length) {
            throw FileSystemException('Multipart 上传文件在检查期间已变更。', file.path);
          }
          if (totalFileBytes > maxTotalBytes - length) {
            throw HttpException(
              'Multipart 文件总量超过 $maxTotalBytes 字节上限。',
              uri: uri,
            );
          }
          totalFileBytes += length;
          lease.length = length;
          lease.chunkDigests = await _snapshotMultipartFile(
            lease,
            initialStat: initialStat,
            remainingBudget: remainingPreparation,
          );
          request.files.add(
            http.MultipartFile(
              field,
              _readMultipartFile(lease),
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
            'Multipart 请求超过 $maxTotalBytes 字节总量上限。',
            uri: uri,
          );
        }
        final remaining = remainingPreparation();
        return await _send(
          request,
          abort: abort,
          timeout: remaining,
          maxResponseBytes: maxResponseBytes,
        );
      } finally {
        preparation.stop();
        await _closeMultipartFileLeases(fileLeases);
      }
    }, cancelSignal: cancelSignal);
  }

  void _validateMultipartFileLength(
    int length, {
    required File file,
    required int maxFileBytes,
    required Uri requestUri,
  }) {
    if (length < 0) {
      throw FileSystemException('Multipart 文件报告了无效的负数大小。', file.path);
    }
    if (length > maxFileBytes) {
      throw HttpException(
        'Multipart 文件超过 $maxFileBytes 字节上限。',
        uri: file.path.isEmpty ? requestUri : Uri.file(file.path),
      );
    }
  }

  Future<RandomAccessFile> _openMultipartInput(
    File file,
    Duration Function() remainingBudget,
  ) async {
    final timeout = remainingBudget();
    final openFuture = file.open();
    try {
      return await openFuture.timeout(
        timeout,
        onTimeout: () =>
            throw TimeoutException('打开 Multipart 上传文件超时。', timeout),
      );
    } on TimeoutException {
      unawaited(_closeLateMultipartInput(openFuture));
      rethrow;
    }
  }

  Stream<List<int>> _readMultipartFile(_AiMultipartFileLease lease) async* {
    try {
      var remaining = lease.length;
      var chunkIndex = 0;
      while (remaining > 0) {
        final chunkLength = remaining < _multipartReadChunkBytes
            ? remaining
            : _multipartReadChunkBytes;
        final chunk = await _readExactMultipartChunk(
          lease,
          chunkLength,
          () => _responseIdleTimeout,
        );
        if (chunkIndex >= lease.chunkDigests.length ||
            sha256.convert(chunk).toString() !=
                lease.chunkDigests[chunkIndex]) {
          throw FileSystemException('Multipart 上传文件在检查后已变更。', lease.file.path);
        }
        remaining -= chunk.length;
        chunkIndex += 1;
        yield chunk;
      }
      if (chunkIndex != lease.chunkDigests.length) {
        throw FileSystemException('Multipart 上传文件快照不一致。', lease.file.path);
      }
    } finally {
      try {
        await lease.close().timeout(_fileCleanupTimeout);
      } catch (_) {
        // 保留请求结果为主结果；外层租约清理会复用同一关闭任务，不会保留第二个文件句柄。
      }
    }
  }

  Future<List<String>> _snapshotMultipartFile(
    _AiMultipartFileLease lease, {
    required FileStat initialStat,
    required Duration Function() remainingBudget,
  }) async {
    Duration nextOperationTimeout() =>
        shorterDuration(_responseIdleTimeout, remainingBudget());

    final digests = <String>[];
    var remaining = lease.length;
    while (remaining > 0) {
      final chunkLength = remaining < _multipartReadChunkBytes
          ? remaining
          : _multipartReadChunkBytes;
      final chunk = await _readExactMultipartChunk(
        lease,
        chunkLength,
        nextOperationTimeout,
      );
      remaining -= chunk.length;
      digests.add(sha256.convert(chunk).toString());
    }

    final finalLength = await lease.input.run(
      (input) => input.length(),
      timeout: nextOperationTimeout(),
    );
    final finalStat = await lease.file.stat().timeout(nextOperationTimeout());
    if (finalLength != lease.length ||
        !isRegularFileStat(finalStat) ||
        finalStat.size != lease.length ||
        finalStat.modified != initialStat.modified ||
        finalStat.changed != initialStat.changed) {
      throw FileSystemException('Multipart 上传文件在检查时已变更。', lease.file.path);
    }
    await lease.input.run(
      (input) => input.setPosition(0),
      timeout: nextOperationTimeout(),
    );
    return List<String>.unmodifiable(digests);
  }

  Future<Uint8List> _readExactMultipartChunk(
    _AiMultipartFileLease lease,
    int length,
    Duration Function() nextOperationTimeout,
  ) async {
    final chunk = Uint8List(length);
    var offset = 0;
    while (offset < length) {
      final read = await lease.input.run(
        (input) => input.readInto(chunk, offset, length),
        timeout: nextOperationTimeout(),
      );
      if (read <= 0) {
        throw FileSystemException('Multipart 上传文件在读取时已变更。', lease.file.path);
      }
      offset += read;
    }
    return chunk;
  }

  Future<void> _closeLateMultipartInput(
    Future<RandomAccessFile> openFuture,
  ) async {
    try {
      final input = await openFuture;
      await input.close().timeout(_fileCleanupTimeout);
    } catch (_) {
      // 准备阶段已经失败，延迟清理仅尽力执行。
    }
  }

  Future<void> _closeMultipartFileLeases(
    Set<_AiMultipartFileLease> leases,
  ) async {
    await Future.wait<void>(<Future<void>>[
      for (final lease in leases)
        lease.close().timeout(_fileCleanupTimeout).catchError((
          Object _,
          StackTrace _,
        ) {
          // 保留主要的请求或准备结果。
        }),
    ]);
  }

  Future<http.Response> get({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
    int maxResponseBytes = defaultAiTransportResponseMaxBytes,
    Future<void>? cancelSignal,
  }) async {
    return _get(
      uri: uri,
      headers: headers,
      timeout: timeout,
      maxResponseBytes: maxResponseBytes,
      cancelSignal: cancelSignal,
    );
  }

  Future<List<int>> downloadBytes({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
    int maxBytes = defaultAiTransportDownloadMaxBytes,
    Future<void>? cancelSignal,
  }) async {
    final response = await _get(
      uri: uri,
      headers: headers,
      timeout: timeout,
      maxResponseBytes: maxBytes,
      cancelSignal: cancelSignal,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  /// 将成功响应流式写入 [destination]，不在内存中保留完整载荷。失败响应体仅保留
  /// 有界诊断预览；任何边界或 I/O 操作失败时删除未完成文件。
  Future<AiTransportFileDownloadResult> downloadToFile({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
    required File destination,
    int maxBytes = defaultAiTransportFileDownloadMaxBytes,
    int maxJsonBytes = defaultAiTransportResponseMaxBytes,
    Future<void>? cancelSignal,
  }) {
    requirePositiveInt(maxBytes, 'maxBytes');
    requirePositiveInt(maxJsonBytes, 'maxJsonBytes');
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

          final contentType = readResponseHeaderOrNull(
            streamed.headers,
            kContentTypeHeaderName,
          );
          final responseLimit = isJsonMimeType(contentType)
              ? math.min(maxBytes, maxJsonBytes)
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
    }, cancelSignal: cancelSignal);
  }

  Future<http.Response> _send(
    http.BaseRequest request, {
    required Completer<void> abort,
    required Duration timeout,
    required int maxResponseBytes,
  }) {
    requirePositiveInt(maxResponseBytes, 'maxResponseBytes');
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
          throw TimeoutException('获取 HTTP 响应头超过请求时限。', effectiveTimeout);
        },
      );
      final remaining = remainingBudget();
      if (remaining <= Duration.zero) {
        throw TimeoutException('HTTP 响应超过请求时限。', effectiveTimeout);
      }
      return await consume(streamed, remainingBudget);
    } finally {
      // 成功读取响应体后触发取消信号不会产生副作用，并能释放客户端保留的回调。
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
        ? math.min(maxResponseBytes, defaultAiTransportErrorResponseMaxBytes)
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
      throw TimeoutException('HTTP 响应超过请求时限。');
    }
    final bodyBytes = await readBoundedByteStream(
      streamed.stream,
      maxBytes: responseLimit,
      idleTimeout: shorterDuration(_responseIdleTimeout, remaining),
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
    Future<void>? cancelSignal,
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
    }, cancelSignal: cancelSignal);
  }

  Future<int> _writeResponseToFile(
    http.StreamedResponse response, {
    required File destination,
    required int responseLimit,
    required Duration Function() remainingBudget,
  }) async {
    BoundedRandomAccessFileLease? output;
    var removeDestinationOnExit = false;
    var deleteOnRelease = true;
    try {
      final destinationExists = await _runWithinBudget(
        remainingBudget,
        destination.exists,
        '检查下载目标超时。',
      );
      if (destinationExists) {
        throw FileSystemException('拒绝覆盖已存在的下载目标。', destination.path);
      }
      await _runWithinBudget(
        remainingBudget,
        () => destination.parent.create(recursive: true),
        '创建下载目录超时。',
      );
      final openedOutput = await openBoundedRandomAccessFileLease(
        destination,
        mode: FileMode.writeOnly,
        timeout: _requireRemainingBudget(remainingBudget),
        deleteIfOpenCompletesLate: true,
        release: (file) async {
          await file.close();
          if (deleteOnRelease &&
              await destination.exists().timeout(_fileCleanupTimeout)) {
            await destination.delete().timeout(_fileCleanupTimeout);
          }
        },
      );
      output = openedOutput;
      removeDestinationOnExit = true;
      final remaining = _requireRemainingBudget(remainingBudget);
      final bytesWritten = await writeBoundedByteStream(
        response.stream,
        writeChunk: (chunk) => openedOutput.run<void>(
          (file) async {
            await file.writeFrom(chunk);
          },
          timeout: shorterDuration(
            _responseIdleTimeout,
            _requireRemainingBudget(remainingBudget),
          ),
        ),
        maxBytes: responseLimit,
        idleTimeout: shorterDuration(_responseIdleTimeout, remaining),
        totalTimeout: remaining,
      );
      await openedOutput.run<void>(
        (file) async {
          await file.flush();
        },
        timeout: shorterDuration(
          _responseIdleTimeout,
          _requireRemainingBudget(remainingBudget),
        ),
      );
      deleteOnRelease = false;
      try {
        await openedOutput.close(
          timeout: _requireRemainingBudget(remainingBudget),
        );
      } catch (_) {
        deleteOnRelease = true;
        rethrow;
      }
      output = null;
      removeDestinationOnExit = false;
      return bytesWritten;
    } catch (_) {
      unawaited(cancelByteStream(response.stream));
      rethrow;
    } finally {
      deleteOnRelease = output != null;
      await output?.cleanup();
      if (removeDestinationOnExit) {
        try {
          if (await destination.exists().timeout(_fileCleanupTimeout)) {
            await destination.delete().timeout(_fileCleanupTimeout);
          }
        } catch (_) {
          // 半成品清理保持有界，不能覆盖主要下载错误。
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
    unawaited(cancelByteStream(response.stream));
    throw HttpException('HTTP 响应超过 $responseLimit 字节上限。', uri: requestUrl);
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

  Duration _requireRemainingBudget(Duration Function() remainingBudget) {
    final remaining = remainingBudget();
    if (remaining <= Duration.zero) {
      throw TimeoutException('HTTP 响应超过请求时限。');
    }
    return remaining;
  }

  Future<T> _runAbortable<T>(
    Future<T> Function(Completer<void> abort) operation, {
    Future<void>? cancelSignal,
  }) async {
    if (_disposed) throw StateError('AI 传输客户端已释放。');
    late final bool acquired;
    try {
      acquired = await _requestSlots.acquireWithin(
        _aiTransportQueueTimeout,
        cancelSignal: cancelSignal,
      );
    } on StateError {
      if (_disposed) throw StateError('AI 传输客户端已释放。');
      throw StateError('AI 传输请求排队已满。');
    }
    if (!acquired) {
      if (_disposed) throw StateError('AI 传输客户端已释放。');
      if (await isCancelSignalCompleted(cancelSignal)) {
        throw http.RequestAbortedException();
      }
      throw TimeoutException('AI 传输请求排队超时。', _aiTransportQueueTimeout);
    }
    if (_disposed) {
      _requestSlots.release();
      throw StateError('AI 传输客户端已释放。');
    }
    final abort = _createAbort();
    if (cancelSignal != null) {
      unawaited(
        cancelSignal.then<void>(
          (_) => _abort(abort),
          onError: (Object _, StackTrace _) => _abort(abort),
        ),
      );
    }
    try {
      return await operation(abort);
    } finally {
      _abort(abort);
      _requestSlots.release();
    }
  }

  Completer<void> _createAbort() {
    if (_disposed) {
      throw StateError('AI 传输客户端已释放。');
    }
    final abort = Completer<void>();
    _activeAborts.add(abort);
    return abort;
  }

  void _abort(Completer<void> abort) {
    if (!abort.isCompleted) abort.complete();
    _activeAborts.remove(abort);
  }

  Future<void> _cancelLateResponse(
    Future<http.StreamedResponse> responseFuture,
  ) async {
    try {
      final response = await responseFuture;
      await cancelByteStream(response.stream);
    } catch (_) {
      // 延迟到达的传输失败已由超时结果表示。
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
    _requestSlots.cancelWaiters();
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

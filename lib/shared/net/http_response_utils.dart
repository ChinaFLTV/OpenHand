import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../util/argument_guards.dart';
import '../util/async_concurrency.dart';
import '../util/timer_safety.dart';
import 'http_redirect_utils.dart';
import 'http_status_utils.dart';

const Duration _byteStreamCancelTimeout = Duration(milliseconds: 500);

final class ByteStreamSizeLimitException extends HttpException {
  ByteStreamSizeLimitException(this.maxBytes) : super('字节流超过 $maxBytes 字节上限。');

  final int maxBytes;
}

final class BoundedByteStreamPrefix {
  const BoundedByteStreamPrefix({required this.bytes, required this.truncated});

  final Uint8List bytes;
  final bool truncated;
}

/// 判断响应类型是否符合调用方要求。
///
/// 部分下载服务会把二进制内容标记为 `application/octet-stream`，在显式允许
/// 时将其视为兼容类型；缺失 Content-Type 不作强制猜测，交由调用方决定。
bool matchesExpectedContentType(
  ContentType? contentType, {
  required String expectedPrimaryType,
  bool allowOctetStream = true,
}) {
  if (contentType == null) return true;
  if (contentType.primaryType == expectedPrimaryType) return true;
  return allowOctetStream &&
      contentType.mimeType == kApplicationOctetStreamMimeType;
}

/// 获取 HTTP(S) 资源，并统一执行状态码、类型、空闲时限、总时限和容量校验。
/// 调用方仍负责关闭 [client]。
Future<Uint8List> fetchBoundedHttpBytes({
  required HttpClient client,
  required Uri uri,
  required int maxBytes,
  required Duration openTimeout,
  required Duration idleTimeout,
  Duration? totalTimeout,
  String? expectedPrimaryType,
  bool allowOctetStream = true,
}) async {
  final scheme = uri.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
    throw FormatException('仅支持有效的 HTTP(S) 地址：$uri');
  }
  requirePositiveDuration(openTimeout, 'openTimeout');
  _validateByteStreamLimits(
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );

  final deadline = totalTimeout == null
      ? null
      : MonotonicDeadline(totalTimeout, timeoutMessage: 'HTTP 资源获取超过总时限。');
  Duration remainingTotalBudget() {
    return deadline?.remaining() ?? openTimeout;
  }

  Duration nextOpenTimeout() {
    final remaining = remainingTotalBudget();
    return remaining < openTimeout ? remaining : openTimeout;
  }

  try {
    final request = await client.getUrl(uri).timeout(nextOpenTimeout());
    final response = await request.close().timeout(nextOpenTimeout());
    var responseConsumptionStarted = false;
    try {
      if (isHttpFailureStatus(response.statusCode)) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final contentType = response.headers.contentType;
      if (expectedPrimaryType != null &&
          !matchesExpectedContentType(
            contentType,
            expectedPrimaryType: expectedPrimaryType,
            allowOctetStream: allowOctetStream,
          )) {
        throw HttpException(
          '响应内容类型不符合预期：${contentType?.mimeType ?? '未知'}',
          uri: uri,
        );
      }
      final remainingTotal = totalTimeout == null
          ? null
          : remainingTotalBudget();
      final effectiveIdleTimeout =
          remainingTotal != null && remainingTotal < idleTimeout
          ? remainingTotal
          : idleTimeout;
      responseConsumptionStarted = true;
      return await readBoundedHttpResponseBytes(
        response,
        maxBytes: maxBytes,
        idleTimeout: effectiveIdleTimeout,
        totalTimeout: remainingTotal,
      );
    } catch (_) {
      if (!responseConsumptionStarted) await cancelByteStream(response);
      rethrow;
    }
  } finally {
    deadline?.stop();
  }
}

/// 在明确的空闲、总时长和容量限制内读取 HTTP 响应。
/// 调用方仍负责关闭响应所属的 [HttpClient]。
Future<Uint8List> readBoundedHttpResponseBytes(
  HttpClientResponse response, {
  required int maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
}) {
  _validateByteStreamLimits(
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  if (response.contentLength > maxBytes) {
    unawaited(cancelByteStream(response));
    throw ByteStreamSizeLimitException(maxBytes);
  }

  return _consumeByteStream(
    response,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
    retainBytes: true,
    truncateOnOverflow: false,
    cancelOnFailure: true,
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

/// 在明确的容量、空闲和总时限内读取字节流。任一限制触发后会取消订阅，
/// 避免超时的数据源继续在后台缓冲。
/// [truncateOnOverflow] 为 true 时返回限定长度的前缀，适用于错误信息预览。
/// [cancelOnFailure] 仅供必须先写出错误响应的服务端请求流关闭；其他调用方
/// 应保留默认值，确保失败后立即释放底层流。
Future<Uint8List> readBoundedByteStream(
  Stream<List<int>> stream, {
  required int maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
  bool truncateOnOverflow = false,
  bool cancelOnFailure = true,
}) {
  _validateByteStreamLimits(
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  return _consumeByteStream(
    stream,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
    retainBytes: true,
    truncateOnOverflow: truncateOnOverflow,
    cancelOnFailure: cancelOnFailure,
  );
}

/// 在容量、空闲和总时限内读取字节流前缀；超限时取消源订阅并返回截断标记。
Future<BoundedByteStreamPrefix> readBoundedByteStreamPrefix(
  Stream<List<int>> stream, {
  required int maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
}) async {
  _validateByteStreamLimits(
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  final probed = await readBoundedByteStream(
    stream,
    maxBytes: maxBytes + 1,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
    truncateOnOverflow: true,
  );
  final truncated = probed.length > maxBytes;
  return BoundedByteStreamPrefix(
    bytes: truncated ? Uint8List.sublistView(probed, 0, maxBytes) : probed,
    truncated: truncated,
  );
}

Future<String> readBoundedByteStreamText(
  Stream<List<int>> stream, {
  required int maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
  bool allowMalformed = false,
  bool cancelOnFailure = true,
}) async {
  final bytes = await readBoundedByteStream(
    stream,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
    cancelOnFailure: cancelOnFailure,
  );
  return utf8.decode(bytes, allowMalformed: allowMalformed);
}

/// 保持流式背压，并拒绝首个会突破 [maxBytes] 的数据块。
/// 取消返回的流时会同步取消源订阅。
Stream<List<int>> limitByteStream(
  Stream<List<int>> stream, {
  required int maxBytes,
  Duration? idleTimeout,
  Duration? totalTimeout,
}) {
  _validateByteStreamLimits(
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );

  late final StreamController<List<int>> controller;
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

  Future<void> cancelSubscriptionBounded([
    StreamSubscription<List<int>>? target,
  ]) async {
    final active = target ?? subscription;
    await cancelStreamSubscriptionBounded<List<int>>(
      active,
      timeout: _byteStreamCancelTimeout,
    );
  }

  void terminate([Object? error, StackTrace? stack]) {
    if (settled) return;
    settled = true;
    cancelTimers();
    unawaited(cancelSubscriptionBounded());
    if (error != null) controller.addError(error, stack ?? StackTrace.current);
    unawaited(controller.close());
  }

  void resetIdleTimer() {
    final timeout = idleTimeout;
    if (timeout == null || settled) return;
    idleTimer?.cancel();
    idleTimer = startSafeTimer(
      timeout,
      () => terminate(_idleTimeoutException(timeout), StackTrace.current),
    );
  }

  controller = StreamController<List<int>>(
    sync: true,
    onListen: () {
      final timeout = totalTimeout;
      if (timeout != null) {
        totalTimer = startSafeTimer(
          timeout,
          () => terminate(_totalTimeoutException(timeout), StackTrace.current),
        );
      }
      resetIdleTimer();
      try {
        final active = stream.listen(
          (chunk) {
            if (settled) return;
            resetIdleTimer();
            if (chunk.length > maxBytes - receivedBytes) {
              terminate(
                ByteStreamSizeLimitException(maxBytes),
                StackTrace.current,
              );
              return;
            }
            receivedBytes += chunk.length;
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            terminate(error, stack);
          },
          onDone: () {
            if (settled) return;
            settled = true;
            cancelTimers();
            unawaited(controller.close());
          },
        );
        subscription = active;
        if (settled) unawaited(cancelSubscriptionBounded(active));
      } catch (error, stack) {
        terminate(error, stack);
      }
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      if (settled) return;
      settled = true;
      cancelTimers();
      await cancelSubscriptionBounded();
    },
  );
  return controller.stream;
}

/// 保持背压地将字节写入异步接收端，并执行与内存读取一致的限制。
Future<int> writeBoundedByteStream(
  Stream<List<int>> stream, {
  required Future<void> Function(List<int> chunk) writeChunk,
  required int maxBytes,
  required Duration idleTimeout,
  required Duration totalTimeout,
}) async {
  _validateByteStreamLimits(
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  var writtenBytes = 0;
  final writeStream = limitByteStream(stream, maxBytes: maxBytes)
      .asyncMap<List<int>>((chunk) async {
        await writeChunk(chunk);
        writtenBytes += chunk.length;
        return const <int>[];
      });
  await drainByteStreamWithTimeout(
    writeStream,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  return writtenBytes;
}

/// 丢弃响应流并保持连接池可复用，同时防止异常对端无限占用调用方。
Future<void> drainByteStreamWithTimeout(
  Stream<List<int>> stream, {
  required Duration idleTimeout,
  required Duration totalTimeout,
}) async {
  _validateByteStreamLimits(
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  await _consumeByteStream(
    stream,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
    retainBytes: false,
    truncateOnOverflow: false,
    cancelOnFailure: true,
  );
}

/// 取消尚未消费的字节流，并限制底层取消操作的等待时间。
Future<bool> cancelByteStream(
  Stream<List<int>> stream, {
  Duration timeout = _byteStreamCancelTimeout,
  OpenHandAsyncCleanupErrorHandler? onError,
}) async {
  try {
    final subscription = stream.listen(
      null,
      onError: (Object _, StackTrace _) {},
      cancelOnError: true,
    );
    return cancelStreamSubscriptionBounded<List<int>>(
      subscription,
      timeout: timeout,
      onError: onError,
    );
  } catch (error, stack) {
    try {
      onError?.call(error, stack);
    } catch (_) {
      // 清理日志异常不能覆盖取消结果。
    }
    return false;
  }
}

Future<Uint8List> _consumeByteStream(
  Stream<List<int>> stream, {
  int? maxBytes,
  required Duration idleTimeout,
  Duration? totalTimeout,
  required bool retainBytes,
  required bool truncateOnOverflow,
  required bool cancelOnFailure,
}) {
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
      cancelStreamSubscriptionBounded<List<int>>(
        active,
        timeout: _byteStreamCancelTimeout,
      ),
    );
  }

  void fail(Object error, StackTrace stack) {
    if (settled) return;
    settled = true;
    cancelTimers();
    if (cancelOnFailure) cancelSubscription();
    completer.completeError(error, stack);
  }

  void resetIdleTimer() {
    idleTimer?.cancel();
    idleTimer = startSafeTimer(
      idleTimeout,
      () => fail(_idleTimeoutException(idleTimeout), StackTrace.current),
    );
  }

  if (totalTimeout != null) {
    totalTimer = startSafeTimer(
      totalTimeout,
      () => fail(_totalTimeoutException(totalTimeout), StackTrace.current),
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
            nextByteCount > maxBytes) {
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
          fail(ByteStreamSizeLimitException(maxBytes), StackTrace.current);
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
  if (settled && cancelOnFailure) {
    cancelSubscription();
  }
  return completer.future;
}

void _validateByteStreamLimits({
  int? maxBytes,
  Duration? idleTimeout,
  Duration? totalTimeout,
}) {
  if (maxBytes != null) requirePositiveInt(maxBytes, 'maxBytes');
  if (idleTimeout != null) {
    requirePositiveDuration(idleTimeout, 'idleTimeout');
  }
  if (totalTimeout != null) {
    requirePositiveDuration(totalTimeout, 'totalTimeout');
  }
}

TimeoutException _idleTimeoutException(Duration timeout) {
  return TimeoutException('HTTP 响应流在限定时间内没有新数据。', timeout);
}

TimeoutException _totalTimeoutException(Duration timeout) {
  return TimeoutException('HTTP 响应流超过总时长限制。', timeout);
}

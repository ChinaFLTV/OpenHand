import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/support/silent_log.dart';

/// Serializes writes to an MCP stdio stdin pipe.
///
/// `IOSink.flush` can temporarily bind the sink to an internal stream. Closing
/// stdin while that flush is still in flight raises "StreamSink is bound to a
/// stream", so close paths should drain this queue with a bounded timeout first.
class McpStdioWriteQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() operation) {
    final queued = _tail.then((_) => operation());
    _tail = queued.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return queued;
  }

  Future<void> drain(Duration timeout) async {
    try {
      await _tail.timeout(timeout);
    } on TimeoutException {
      // Close will continue and terminate the process if the pipe stays busy.
    } catch (_) {
      // The queue tail already swallows write failures; keep drain best-effort.
    }
  }
}

void observeMcpStdioPendingFuture<T>(Future<T> future) {
  unawaited(_ignoreMcpStdioPendingFuture(future));
}

Future<void> _ignoreMcpStdioPendingFuture<T>(Future<T> future) async {
  try {
    await future;
  } catch (_) {
    // The request owner still awaits the same future and receives the error.
  }
}

Future<void> writeMcpJsonLineToStdin(
  IOSink stdin,
  Map<String, Object?> payload,
) async {
  stdin.add(utf8.encode(jsonEncode(payload)));
  stdin.add(const [0x0A]);
  await stdin.flush();
}

Future<void> closeMcpStdioSinkQuietly({
  required IOSink stdin,
  required Duration timeout,
  required String logTag,
  required String logWhere,
}) async {
  try {
    await stdin.close().timeout(timeout);
  } on TimeoutException {
    // The caller will kill the process if graceful shutdown does not complete.
  } on StateError catch (error, stack) {
    if (!isExpectedMcpStdioSinkStateError(error)) {
      silentLog(logTag, logWhere, error, stack);
    }
  } catch (error, stack) {
    silentLog(logTag, logWhere, error, stack);
  }
}

bool isExpectedMcpStdioSinkStateError(StateError error) {
  final message = error.message.toLowerCase();
  return message.contains('streamsink is bound to a stream') ||
      message.contains('streamsink is closed') ||
      message.contains('cannot add event after closing') ||
      message.contains('cannot add to a closed sink');
}

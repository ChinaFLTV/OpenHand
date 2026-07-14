import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/support/silent_log.dart';

const int kMcpStdioMaxPendingRequests = 256;
final RegExp _mcpShellWhitespacePattern = RegExp(r'\s');

List<String> tokenizeMcpShellCommand(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return const <String>[];
  if (!trimmed.contains(_mcpShellWhitespacePattern)) return <String>[trimmed];
  final tokens = <String>[];
  final buffer = StringBuffer();
  var inSingle = false;
  var inDouble = false;
  var hasContent = false;
  for (var index = 0; index < trimmed.length; index++) {
    final character = trimmed[index];
    if (!inSingle &&
        !inDouble &&
        character == '\\' &&
        index + 1 < trimmed.length) {
      buffer.write(trimmed[++index]);
      hasContent = true;
      continue;
    }
    if (!inDouble && character == "'") {
      inSingle = !inSingle;
      hasContent = true;
      continue;
    }
    if (!inSingle && character == '"') {
      inDouble = !inDouble;
      hasContent = true;
      continue;
    }
    if (!inSingle &&
        !inDouble &&
        _mcpShellWhitespacePattern.hasMatch(character)) {
      if (hasContent) {
        tokens.add(buffer.toString());
        buffer.clear();
        hasContent = false;
      }
      continue;
    }
    buffer.write(character);
    hasContent = true;
  }
  if (inSingle || inDouble) return <String>[trimmed];
  if (hasContent) tokens.add(buffer.toString());
  return tokens.isEmpty ? <String>[trimmed] : tokens;
}

/// Serializes writes to an MCP stdio stdin pipe.
///
/// `IOSink.flush` can temporarily bind the sink to an internal stream. Closing
/// stdin while that flush is still in flight raises "StreamSink is bound to a
/// stream", so close paths should drain this queue with a bounded timeout first.
class McpStdioWriteQueue {
  Future<void> _tail = Future<void>.value();
  Object? _closedError;

  bool get isClosed => _closedError != null;

  void rejectNewWrites(Object error) {
    _closedError ??= error;
  }

  Future<void> run(Future<void> Function() operation) {
    final closedError = _closedError;
    if (closedError != null) {
      return Future<void>.error(closedError);
    }
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

void observeMcpPendingFuture<T>(Future<T> future) {
  unawaited(_ignoreMcpPendingFuture(future));
}

Future<void> _ignoreMcpPendingFuture<T>(Future<T> future) async {
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

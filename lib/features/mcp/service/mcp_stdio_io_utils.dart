import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/support/silent_log.dart';
import '../../../shared/util/serial_task_queue.dart';

const int kMcpStdioMaxPendingRequests = 256;
const Duration _mcpStdioWriteTimeout = Duration(seconds: 2);
final RegExp _mcpShellWhitespacePattern = RegExp(r'\s');

List<String> tokenizeMcpShellCommand(String input, {bool? isWindows}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return const <String>[];
  final useWindowsRules = isWindows ?? Platform.isWindows;
  final tokens = <String>[];
  final buffer = StringBuffer();
  var inSingle = false;
  var inDouble = false;
  var hasContent = false;
  for (var index = 0; index < trimmed.length; index++) {
    final character = trimmed[index];
    if (!useWindowsRules &&
        !inSingle &&
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

bool isMcpNpxCommand(String executable) {
  final fileName = executable
      .trim()
      .replaceAll('\\', '/')
      .split('/')
      .last
      .toLowerCase();
  return const <String>{
    'npx',
    'npx.cmd',
    'npx.bat',
    'npx.exe',
    'npx.ps1',
  }.contains(fileName);
}

int firstMcpNpxPackageArgIndex(List<String> args) {
  for (var index = 0; index < args.length; index++) {
    final arg = args[index].trim();
    if (arg.isEmpty ||
        arg == '--' ||
        arg == '-y' ||
        arg == '--yes' ||
        arg == '--no-install' ||
        arg.startsWith('-')) {
      continue;
    }
    return index;
  }
  return -1;
}

/// 串行写入 MCP stdio 标准输入管道。
///
/// `IOSink.flush` 会暂时把输出绑定到内部流；关闭前应在限定时间内排空队列，
/// 避免刷新期间关闭导致输出流状态冲突。
class McpStdioWriteQueue {
  final SerialTaskQueue _queue = SerialTaskQueue();
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
    return _queue.enqueue(operation);
  }

  Future<void> drain(Duration timeout) async {
    try {
      await _queue.idle.timeout(timeout);
    } on TimeoutException {
      // 管道持续繁忙时由关闭流程继续终止子进程。
    } catch (_) {
      // 写入失败已传递给任务调用方，排空仅尽力执行。
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
    // 请求所有者仍会等待同一 Future 并收到错误。
  }
}

Future<void> writeMcpJsonLineToStdin(
  IOSink stdin,
  Map<String, Object?> payload,
) async {
  stdin.add(utf8.encode(jsonEncode(payload)));
  stdin.add(const [0x0A]);
  await stdin.flush().timeout(_mcpStdioWriteTimeout);
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
    // 优雅关闭失败时由调用方继续终止子进程。
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

/// 判断完整命令行（可能含参数）是否以 [executable] 开头。
///
/// 兼容两种用户输入：
///   1. command="npx", args=["@playwright/mcp"]
///   2. command="npx chrome-devtools-mcp@latest", args=["--autoConnect"]
/// 同时支持绝对路径形式（如 /opt/homebrew/bin/npx）。
bool _commandLineMatches(String commandLine, String executable) {
  final cmd = commandLine.trim();
  if (cmd.isEmpty) return false;
  if (cmd == executable || cmd.endsWith('/$executable')) return true;
  final firstToken = cmd.split(_mcpShellWhitespacePattern).first;
  return firstToken == executable || firstToken.endsWith('/$executable');
}

/// 判断 STDIO MCP 服务是否使用 npx 启动（command 可能含参数）。
bool isMcpNpxCommandLine(String command) => _commandLineMatches(command, 'npx');

/// 判断 STDIO MCP 服务是否使用 uvx 启动（command 可能含参数）。
bool isMcpUvxCommandLine(String command) => _commandLineMatches(command, 'uvx');

/// 判断 STDIO MCP 服务是否使用包管理器（npx 或 uvx）启动。
bool isMcpPackageManagerCommandLine(String command) =>
    isMcpNpxCommandLine(command) || isMcpUvxCommandLine(command);

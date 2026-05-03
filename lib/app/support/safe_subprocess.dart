import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/ai/service/ai_tool_execution_registry.dart';
import 'silent_log.dart';

/// 全局默认的子进程 graceful shutdown 等待窗口（毫秒）。AiSessionController
/// 在 `_captureLatestRuntimeContext` 中按用户设置项更新此值，所有不显式
/// 传 `gracefulShutdownMs` 的调用方自动跟随。默认 500ms 与既有行为一致。
int safeSubprocessDefaultGracefulShutdownMs = 500;

/// Runs an external command with a hard wall-clock timeout that **kills**
/// the child process on expiry.
///
/// Why not just `Process.run(...).timeout(...)`?  `Future.timeout` only
/// abandons the dart-side `Future`; the underlying child process keeps
/// running.  On macOS this is especially harmful for `osascript`, which
/// continues to send Apple Events to other apps and can leave the host
/// process's input-method context in a bad state — observed in practice
/// as "TextField in dialogs no longer accepts input or paste" plus
/// `IMKCFRunLoopWakeUpReliable` console errors.
///
/// Returns null when the command times out, fails to start, or exits with
/// a non-zero status.  All errors are logged via [silentLog] (debug-only).
///
/// **Tool-execution registry integration**: when [toolCallId] is provided
/// and non-empty, the spawned process registers its pid + a SIGTERM→SIGKILL
/// killer with [AiToolExecutionRegistry], enabling the per-call Stop UX.
/// The registration is automatically cleaned up on return (success / timeout
/// / exception). Pass null when the call site has no AiToolExecutionContext
/// in scope (e.g. boot-time CLI probes).
Future<ProcessResult?> runProcessWithTimeout(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 4),
  String tag = 'safe_subprocess',
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
  String? toolCallId,
  int? gracefulShutdownMs,
}) async {
  final effectiveGracefulMs =
      gracefulShutdownMs ?? safeSubprocessDefaultGracefulShutdownMs;
  Process? process;
  final shouldRegisterKiller =
      toolCallId != null && toolCallId.isNotEmpty;
  try {
    process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
      includeParentEnvironment: includeParentEnvironment,
    );
    if (shouldRegisterKiller) {
      final spawned = process;
      AiToolExecutionRegistry.instance.attachPid(toolCallId, spawned.pid);
      AiToolExecutionRegistry.instance.attachKiller(toolCallId, () async {
        spawned.kill();
        await Future<void>.delayed(Duration(milliseconds: effectiveGracefulMs));
        spawned.kill(ProcessSignal.sigkill);
      });
    }
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    String stdoutText = '';
    String stderrText = '';
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        // Crucial: forcibly terminate the lingering child so it cannot
        // continue talking to other apps via Apple Events / IPC.
        process?.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    try {
      stdoutText = await stdoutFuture.timeout(
        const Duration(milliseconds: 200),
        onTimeout: () => '',
      );
    } on TimeoutException {
      stdoutText = '';
    }
    try {
      stderrText = await stderrFuture.timeout(
        const Duration(milliseconds: 200),
        onTimeout: () => '',
      );
    } on TimeoutException {
      stderrText = '';
    }
    if (exitCode == -1) {
      return null;
    }
    return ProcessResult(process.pid, exitCode, stdoutText, stderrText);
  } catch (error, stack) {
    process?.kill(ProcessSignal.sigkill);
    silentLog(tag, '$executable ${arguments.take(1).join(' ')}', error, stack);
    return null;
  }
}

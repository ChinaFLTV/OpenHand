import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/ai/service/runtime/ai_tool_execution_registry.dart';
import 'silent_log.dart';

/// 全局默认的子进程 graceful shutdown 等待窗口（毫秒）。AiSessionController
/// 在 `_captureLatestRuntimeContext` 中按用户设置项更新此值，所有不显式
/// 传 `gracefulShutdownMs` 的调用方自动跟随。默认 500ms 与既有行为一致。
int safeSubprocessDefaultGracefulShutdownMs = 500;

/// 全局子进程登记簿。`runProcessWithTimeout` 与 [startTrackedProcess] 启动
/// 的所有 [Process] 都会在 spawn 时记入、`exitCode` 触发时摘除。应用主体
/// 进程被 SIGTERM / SIGINT / `AppLifecycleListener.onExitRequested` 触发
/// 退出时，[killAllTrackedChildren] 会逐个 SIGTERM → 等 grace → SIGKILL，
/// 杜绝遗留 osascript / LSP / mitmdump / npm 等子进程继续向系统投递
/// Apple Events / 抢占 IMK 上下文造成全局 TextField 输入死锁。
///
/// 之所以维护 pid → Process 而不是只存 pid：
///   1) `Process.kill(SIGKILL)` 不需要再 lookup，无 pid 复用风险；
///   2) `exitCode` 已被组件代码 await 时，我们也能并行听到。
final Map<int, Process> _trackedChildren = <int, Process>{};

void _registerTrackedChild(Process process) {
  _trackedChildren[process.pid] = process;
  // 用 block + void 返回值，避免 dart_async 备忘录里的「whenComplete 返回
  // 同一 Future 触发 self-await 挂死」陷阱。
  unawaited(
    process.exitCode.whenComplete(() {
      _trackedChildren.remove(process.pid);
    }),
  );
}

/// 启动一个长驻子进程（LSP / mitmdump / Hook / Cron / MCP 调试探针等）并
/// 登记到全局子进程簿；调用方仍然完整持有 [Process] 句柄，自行 await
/// `exitCode` / drain 管道即可。
///
/// 与 [runProcessWithTimeout] 的区别：本方法不施加超时也不主动 kill，仅
/// 负责"应用退出时陪葬"。不要用于一次性短命令——那些请走
/// [runProcessWithTimeout]。
Future<Process> startTrackedProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
  ProcessStartMode mode = ProcessStartMode.normal,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: runInShell,
    includeParentEnvironment: includeParentEnvironment,
    mode: mode,
  );
  // ProcessStartMode.detached* 模式下 process.exitCode 会抛 Bad state，
  // 这种由调用方明确"脱钩"的进程也不应纳入清理（如浏览器主进程）。
  if (mode == ProcessStartMode.normal ||
      mode == ProcessStartMode.inheritStdio) {
    _registerTrackedChild(process);
  }
  return process;
}

/// 关闭所有登记在册的子进程：先 SIGTERM 让对方有机会 flush，等待
/// [gracefulTimeout]，仍未退出则 SIGKILL。所有失败都 swallow，因为这是
/// 退出兜底路径，不能再抛新异常。
Future<void> killAllTrackedChildren({
  Duration gracefulTimeout = const Duration(milliseconds: 400),
}) async {
  if (_trackedChildren.isEmpty) return;
  // 拷贝快照，避免迭代过程中 exitCode 回调修改原 map 触发
  // ConcurrentModificationError。
  final snapshot = List<Process>.of(_trackedChildren.values);
  for (final p in snapshot) {
    try {
      p.kill();
    } catch (_) {
      // 已退出会抛，忽略即可。
    }
  }
  // 给整个批次一次性 grace，而不是每个进程 400ms 串行等。
  await Future<void>.delayed(gracefulTimeout);
  for (final p in snapshot) {
    try {
      p.kill(ProcessSignal.sigkill);
    } catch (_) {}
  }
}

/// 仅供测试 / 诊断使用：当前未退出的子进程 pid 列表。
List<int> debugTrackedChildPids() =>
    List<int>.unmodifiable(_trackedChildren.keys);

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
  final shouldRegisterKiller = toolCallId != null && toolCallId.isNotEmpty;
  try {
    process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
      includeParentEnvironment: includeParentEnvironment,
    );
    // 登记到全局子进程簿，应用退出时被 [killAllTrackedChildren] 兜底。
    _registerTrackedChild(process);
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

/// 兼容 `Process.run(...).timeout(...)` 写法的封装：永远返回非空
/// [ProcessResult]，launch 失败/超时统一回落到 `ProcessResult(-1, -1, '', '')`。
/// 子进程登记到全局簿（应用退出兜底）+ 超时强制 SIGKILL，避免 orphan
/// osascript / mitmdump / npm 等继续污染 macOS IMK 输入上下文。
///
/// 用法（与 `Process.run().timeout()` 几乎 1:1 替换）：
/// ```dart
/// final r = await runTrackedProcessOrFailed('which', ['node'],
///     timeout: const Duration(seconds: 5));
/// if (r.exitCode == 0) { ... }
/// ```
Future<ProcessResult> runTrackedProcessOrFailed(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 4),
  String tag = 'safe_subprocess',
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
}) async {
  final r = await runProcessWithTimeout(
    executable,
    arguments,
    timeout: timeout,
    tag: tag,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: runInShell,
    includeParentEnvironment: includeParentEnvironment,
  );
  return r ?? ProcessResult(-1, -1, '', '');
}

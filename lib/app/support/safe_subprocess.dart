import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../features/ai/service/runtime/ai_tool_execution_registry.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/timer_safety.dart';
import 'silent_log.dart';
import 'url_validation.dart';

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
final Set<int> _trackedProcessGroupLeaders = <int>{};
Future<String?>? _processGroupLauncherProbe;

const Duration _directChildEnumerationTimeout = Duration(seconds: 2);
const Duration _directChildTerminateGrace = Duration(milliseconds: 120);
const Duration _processTreeFinalWait = Duration(milliseconds: 250);

bool _isMissingExecutableProcessException(Object error) {
  if (error is! ProcessException) return false;
  if (error.errorCode == 2 || error.errorCode == 3) return true;
  final haystack = <String>[
    error.message,
    error.executable,
    error.toString(),
  ].join('\n').toLowerCase();
  return haystack.contains('no such file or directory') ||
      haystack.contains('cannot find the file') ||
      haystack.contains('the system cannot find') ||
      haystack.contains('failed to start') ||
      haystack.contains('executable not found');
}

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

/// Starts a tracked process in a fresh POSIX process group when the platform
/// provides `setsid`, then records the wrapper pid as the group leader.
///
/// This lets callers stop the whole command tree with
/// [terminateTrackedProcessTree] instead of killing only the shell process.
/// On Windows, detached modes, or systems without `setsid`, it falls back to
/// [startTrackedProcess] and still receives normal app-exit cleanup.
Future<Process> startTrackedProcessInNewGroup(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
  ProcessStartMode mode = ProcessStartMode.normal,
}) async {
  if (Platform.isWindows ||
      runInShell ||
      (mode != ProcessStartMode.normal &&
          mode != ProcessStartMode.inheritStdio)) {
    return startTrackedProcess(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
      includeParentEnvironment: includeParentEnvironment,
      mode: mode,
    );
  }
  final launcher = await _resolveProcessGroupLauncher();
  if (launcher == null) {
    return startTrackedProcess(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      mode: mode,
    );
  }
  final process = await startTrackedProcess(
    launcher,
    <String>[executable, ...arguments],
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    mode: mode,
  );
  _trackedProcessGroupLeaders.add(process.pid);
  unawaited(
    process.exitCode.whenComplete(() {
      _trackedProcessGroupLeaders.remove(process.pid);
    }),
  );
  return process;
}

/// Terminates a process plus its POSIX process group when the process was
/// launched through [startTrackedProcessInNewGroup].
Future<void> terminateTrackedProcessTree(
  Process process, {
  Duration? gracefulTimeout,
}) async {
  if (Platform.isWindows) {
    try {
      process.kill();
    } catch (error, stack) {
      silentLog('safe_subprocess', 'terminate windows child', error, stack);
    }
    return;
  }

  final pid = process.pid;
  final isGroupLeader = _trackedProcessGroupLeaders.contains(pid);
  try {
    process.kill();
  } catch (error, stack) {
    silentLog('safe_subprocess', 'sigterm child', error, stack);
  }
  if (isGroupLeader) {
    await _sendSignalToProcessGroup(pid, 'TERM');
  }

  try {
    await process.exitCode.timeout(
      gracefulTimeout ??
          Duration(milliseconds: safeSubprocessDefaultGracefulShutdownMs),
    );
    return;
  } on TimeoutException {
    // Escalate below.
  } catch (error, stack) {
    silentLog('safe_subprocess', 'wait child after sigterm', error, stack);
  }

  try {
    process.kill(ProcessSignal.sigkill);
  } catch (error, stack) {
    silentLog('safe_subprocess', 'sigkill child', error, stack);
  }
  if (isGroupLeader) {
    await _sendSignalToProcessGroup(pid, 'KILL');
  }
  try {
    await process.exitCode.timeout(_processTreeFinalWait);
  } catch (_) {
    // Final best-effort path; no caller should block indefinitely here.
  }
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
    } catch (error, stack) {
      // 已退出会抛，忽略即可。
      silentLog('safe_subprocess', 'sigterm tracked child', error, stack);
    }
    if (_trackedProcessGroupLeaders.contains(p.pid)) {
      unawaited(_sendSignalToProcessGroup(p.pid, 'TERM'));
    }
  }
  // 给整个批次一次性 grace，而不是每个进程 400ms 串行等。
  await Future<void>.delayed(gracefulTimeout);
  for (final p in snapshot) {
    try {
      p.kill(ProcessSignal.sigkill);
    } catch (error, stack) {
      silentLog('safe_subprocess', 'sigkill on graceful exit', error, stack);
    }
    if (_trackedProcessGroupLeaders.contains(p.pid)) {
      unawaited(_sendSignalToProcessGroup(p.pid, 'KILL'));
    }
  }
}

/// 仅供测试 / 诊断使用：当前未退出的子进程 pid 列表。
List<int> debugTrackedChildPids() =>
    List<int>.unmodifiable(_trackedChildren.keys);

Future<String?> _resolveProcessGroupLauncher() {
  if (_processGroupLauncherProbe != null) return _processGroupLauncherProbe!;
  _processGroupLauncherProbe = () async {
    const candidates = <String>[
      '/usr/bin/setsid',
      '/usr/local/bin/setsid',
      '/opt/homebrew/bin/setsid',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    try {
      final result = await runTrackedProcessOrFailed(
        '/bin/sh',
        <String>['-lc', 'command -v setsid 2>/dev/null'],
        timeout: const Duration(seconds: 2),
        tag: 'safe_subprocess.setsid_probe',
      );
      final path = nullIfBlank(result.stdout as String);
      if (path != null && File(path).existsSync()) return path;
    } catch (error, stack) {
      silentLog('safe_subprocess', 'resolve setsid', error, stack);
    }
    return null;
  }();
  return _processGroupLauncherProbe!;
}

Future<void> _sendSignalToProcessGroup(int pid, String signal) async {
  if (Platform.isWindows) return;
  try {
    await Process.run('/bin/kill', <String>[
      '-$signal',
      '-$pid',
    ]).timeout(const Duration(seconds: 2));
  } catch (error, stack) {
    silentLog('safe_subprocess', 'kill -$signal -$pid', error, stack);
  }
}

/// 扫出本进程下所有直接子进程并 SIGKILL，返回杀死的进程数。
///
/// [killAllTrackedChildren] 只能清理走 [startTrackedProcess] /
/// [runProcessWithTimeout] / [runTrackedProcessOrFailed] 登记过的子进程；
/// 对于 `Process.run`、`Process.start` 裸调用以及通过 shell 间接拉起的
/// osascript / mitmdump / npm / node 等遗孤则触达不到。本方法用平台原语
/// 枚举直接子进程并强制终结，是输入修复流水线的关键补充。
Future<int> killAllDirectChildren() async {
  int killed = 0;
  try {
    final myPid = pid;
    if (Platform.isMacOS || Platform.isLinux) {
      final result = await Process.run('pgrep', [
        '-P',
        '$myPid',
      ]).timeout(_directChildEnumerationTimeout);
      if (result.exitCode == 0) {
        killed += await _terminatePidSet(
          _parseChildPids(result.stdout, parentPid: myPid),
          tag: 'kill direct child pid',
        );
      }
      // 第二遍补漏：pgrep 与逐个 kill 之间可能又 fork 出新的直接子进程。
      try {
        final r2 = await Process.run('pkill', [
          '-TERM',
          '-P',
          '$myPid',
        ]).timeout(_directChildEnumerationTimeout);
        if (r2.exitCode == 0) {
          await Future<void>.delayed(_directChildTerminateGrace);
          await Process.run('pkill', [
            '-KILL',
            '-P',
            '$myPid',
          ]).timeout(_directChildEnumerationTimeout);
          killed = killed + 1; // pkill 本身不报数，保守计 1。
        }
      } catch (error, stack) {
        silentLog('safe_subprocess', 'pkill -P fallback', error, stack);
      }
    } else if (Platform.isWindows) {
      final result = await Process.run('wmic', [
        'process',
        'where',
        '(ParentProcessId=$myPid)',
        'get',
        'ProcessId',
      ]).timeout(_directChildEnumerationTimeout);
      if (result.exitCode == 0) {
        killed += await _terminatePidSet(
          _parseChildPids(result.stdout, parentPid: myPid),
          tag: 'kill windows child pid',
        );
      }
    }
  } catch (error, stack) {
    silentLog('safe_subprocess', 'enumerate direct children', error, stack);
  }
  return killed;
}

Set<int> _parseChildPids(Object? stdout, {required int parentPid}) {
  return '$stdout'
      .split(RegExp(r'\s+'))
      .map(optionalIntFromValue)
      .whereType<int>()
      .where((childPid) => childPid > 0 && childPid != parentPid)
      .toSet();
}

Future<int> _terminatePidSet(Set<int> pids, {required String tag}) async {
  if (pids.isEmpty) {
    return 0;
  }
  final signalled = <int>{};
  for (final childPid in pids) {
    try {
      if (Process.killPid(childPid)) {
        signalled.add(childPid);
      }
    } catch (error, stack) {
      silentLog('safe_subprocess', tag, error, stack);
    }
  }
  if (signalled.isEmpty) {
    return 0;
  }
  await Future<void>.delayed(_directChildTerminateGrace);
  for (final childPid in signalled) {
    try {
      Process.killPid(childPid, ProcessSignal.sigkill);
    } catch (error, stack) {
      silentLog('safe_subprocess', tag, error, stack);
    }
  }
  return signalled.length;
}

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
    if (!_isMissingExecutableProcessException(error)) {
      silentLog(
        tag,
        '$executable ${arguments.take(1).join(' ')}',
        error,
        stack,
      );
    }
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

typedef ProcessLogLineHandler = void Function(String line);

class TrackedProcessLineLogResult {
  const TrackedProcessLineLogResult({
    required this.pid,
    required this.exitCode,
    required this.timedOut,
  });

  final int pid;
  final int exitCode;
  final bool timedOut;
}

/// Starts a tracked process, streams stdout/stderr as decoded text lines, and
/// kills the process when [timeout] expires.
///
/// This is intended for UI install/update flows that need live logs without
/// duplicating stdout/stderr subscription, timeout, and cleanup code. Stream
/// errors are logged and do not fail the process run; spawn/exit failures still
/// propagate to the caller.
Future<TrackedProcessLineLogResult> runTrackedProcessWithLineLogging(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  String tag = 'safe_subprocess',
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
  ProcessLogLineHandler? onStdoutLine,
  ProcessLogLineHandler? onStderrLine,
  void Function()? onTimeout,
  Duration streamDrainTimeout = const Duration(milliseconds: 500),
}) async {
  final process = await startTrackedProcess(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: runInShell,
    includeParentEnvironment: includeParentEnvironment,
  );
  var timedOut = false;
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  StreamSubscription<String>? stdoutSub;
  StreamSubscription<String>? stderrSub;

  void complete(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  void handleLine(ProcessLogLineHandler? handler, String line) {
    if (handler == null || nullIfBlank(line) == null) return;
    try {
      handler(line);
    } catch (error, stack) {
      silentLog(tag, 'line handler $executable', error, stack);
    }
  }

  StreamSubscription<String> listenLines({
    required Stream<List<int>> stream,
    required String streamName,
    required Completer<void> done,
    required ProcessLogLineHandler? handler,
    bool trimLine = false,
  }) {
    return stream
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => handleLine(handler, trimLine ? line.trim() : line),
          onError: (Object error, StackTrace stack) {
            silentLog(tag, '$streamName $executable', error, stack);
            complete(done);
          },
          onDone: () => complete(done),
          cancelOnError: false,
        );
  }

  Future<void> waitForStreamDrain() async {
    try {
      await Future.wait<void>([
        stdoutDone.future,
        stderrDone.future,
      ]).timeout(streamDrainTimeout);
    } on TimeoutException {
      silentLog(
        tag,
        'stream drain timeout',
        '$executable ${arguments.take(1).join(' ')}',
      );
    }
  }

  try {
    stdoutSub = listenLines(
      stream: process.stdout,
      streamName: 'stdout',
      done: stdoutDone,
      handler: onStdoutLine,
    );
    stderrSub = listenLines(
      stream: process.stderr,
      streamName: 'stderr',
      done: stderrDone,
      handler: onStderrLine,
      trimLine: true,
    );
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        try {
          onTimeout?.call();
        } catch (error, stack) {
          silentLog(tag, 'timeout handler $executable', error, stack);
        }
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await waitForStreamDrain();
    return TrackedProcessLineLogResult(
      pid: process.pid,
      exitCode: exitCode,
      timedOut: timedOut,
    );
  } finally {
    await stdoutSub?.cancel();
    await stderrSub?.cancel();
  }
}

/// Runs a short-lived process with optional stdin bytes, bounded stdout/stderr
/// capture, and a hard timeout that kills the child on expiry.
///
/// Use this for OS helpers such as `pbcopy` / `pbpaste` where callers need
/// byte-accurate input or output.  It intentionally returns raw [Uint8List]
/// values in [ProcessResult.stdout] / [ProcessResult.stderr].
Future<ProcessResult?> runBinaryProcessWithTimeout(
  String executable,
  List<String> arguments, {
  List<int> stdinBytes = const <int>[],
  Duration timeout = const Duration(seconds: 4),
  int maxStdoutBytes = 1024 * 1024,
  int maxStderrBytes = 64 * 1024,
  String tag = 'safe_subprocess.binary',
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
}) async {
  Process? process;
  StreamSubscription<List<int>>? stdoutSub;
  StreamSubscription<List<int>>? stderrSub;
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  final stdoutBytes = BytesBuilder(copy: false);
  final stderrBytes = BytesBuilder(copy: false);

  void completeIfNeeded(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  void collectLimited(BytesBuilder builder, List<int> chunk, int maxBytes) {
    if (maxBytes <= 0 || builder.length >= maxBytes) return;
    final remaining = maxBytes - builder.length;
    if (chunk.length <= remaining) {
      builder.add(chunk);
    } else {
      builder.add(chunk.sublist(0, remaining));
    }
  }

  try {
    process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
      includeParentEnvironment: includeParentEnvironment,
    );
    _registerTrackedChild(process);
    stdoutSub = process.stdout.listen(
      (chunk) => collectLimited(stdoutBytes, chunk, maxStdoutBytes),
      onError: (_) => completeIfNeeded(stdoutDone),
      onDone: () => completeIfNeeded(stdoutDone),
      cancelOnError: true,
    );
    stderrSub = process.stderr.listen(
      (chunk) => collectLimited(stderrBytes, chunk, maxStderrBytes),
      onError: (_) => completeIfNeeded(stderrDone),
      onDone: () => completeIfNeeded(stderrDone),
      cancelOnError: true,
    );

    final stdinFuture = () async {
      try {
        if (stdinBytes.isNotEmpty) {
          process?.stdin.add(stdinBytes);
        }
        await process?.stdin.flush();
      } finally {
        await process?.stdin.close();
      }
    }();

    final exitCode =
        await (() async {
          await stdinFuture;
          return process!.exitCode;
        })().timeout(
          timeout,
          onTimeout: () {
            process?.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
    await stdoutDone.future.timeout(
      const Duration(milliseconds: 200),
      onTimeout: () {},
    );
    await stderrDone.future.timeout(
      const Duration(milliseconds: 200),
      onTimeout: () {},
    );
    if (exitCode == -1) return null;
    return ProcessResult(
      process.pid,
      exitCode,
      stdoutBytes.takeBytes(),
      stderrBytes.takeBytes(),
    );
  } catch (error, stack) {
    try {
      process?.kill(ProcessSignal.sigkill);
    } catch (killError, killStack) {
      silentLog(tag, 'kill after failure', killError, killStack);
    }
    if (!_isMissingExecutableProcessException(error)) {
      silentLog(
        tag,
        '$executable ${arguments.take(1).join(' ')}',
        error,
        stack,
      );
    }
    return null;
  } finally {
    await stdoutSub?.cancel();
    await stderrSub?.cancel();
  }
}

/// 跨平台「拉起系统 GUI 应用打开 URL / 文件 / 目录」专用通道。
///
/// 历史教训（与 `Process.run('open', ...)` 等价用法的差别）：
///   - macOS `open` 本身只是个轻量 launcher，会通过 LaunchServices 派发
///     Apple Event 给 Finder/Safari/默认浏览器；这条 IPC 必须立即让出
///     线程，否则在 `await Process.run(...)` 期间，子进程持续向系统
///     LaunchServices 发包，把宿主 Flutter 的 IMK 输入上下文挤掉，
///     全局 `TextField` 输入/复制/粘贴随即被冻结，伴随 console
///     `error messaging the mach port for IMKCFRunLoopWakeUpReliable`。
///   - Windows `explorer` / `cmd /c start` 偶发卡 5s+；Linux
///     `xdg-open` 在桌面环境异常时同样会无限等待。
///   - 这些子进程从未登记到 [_trackedChildren]，应用退出兜底也清不掉
///     ([killAllTrackedChildren] 触达不到)，导致重启后仍有遗留子进程
///     继续投递事件、污染下一轮宿主的 IMK。
///
/// 因此本方法：
///   1) 以 [ProcessStartMode.detached] 启动，spawn 完立即返回，宿主
///      事件循环不被挂；
///   2) 由于 detached 不会回调 exitCode，我们用一个内置 1s 看门狗：
///      若 pid 仍然存在（仅 macOS / Linux 探测），SIGKILL 兜底 —— `open`
///      / `xdg-open` 正常 launch 完都会瞬退，超过 1s 没退就是异常；
///   3) 当 [trackUntilExit] 为 true 时改用 normal 模式 + [_registerTrackedChild]
///      把 `open -W`、`cmd /c start /WAIT` 这类「等待 GUI 关闭」的场景
///      纳入退出兜底（默认不需要）。
///
/// 返回 true 表示 spawn 成功，false 表示 launcher 二进制不可用（不抛）。
Future<bool> runDetachedSystemOpen(
  String executable,
  List<String> arguments, {
  String tag = 'safe_subprocess.open',
  Duration watchdog = const Duration(seconds: 1),
  bool trackUntilExit = false,
  bool runInShell = false,
}) async {
  try {
    final process = await Process.start(
      executable,
      arguments,
      runInShell: runInShell,
      mode: trackUntilExit
          ? ProcessStartMode.normal
          : ProcessStartMode.detached,
    );
    if (trackUntilExit) {
      _registerTrackedChild(process);
      return true;
    }
    // detached 模式：1s 后若 pid 仍存活则 SIGKILL 兜底（仅 POSIX 平台
    // 能优雅探测——Windows detached 子进程已和宿主完全脱钩，无害）。
    if (Platform.isMacOS || Platform.isLinux) {
      final pid = process.pid;
      startSafeTimer(watchdog, () {
        try {
          // ProcessSignal.sigterm 不存在于 detached 的 Process 句柄上；
          // 直接用 POSIX kill 默认 SIGTERM、再补一发 SIGKILL。
          Process.killPid(pid);
          startSafeTimer(const Duration(milliseconds: 300), () {
            try {
              Process.killPid(pid, ProcessSignal.sigkill);
            } catch (error, stack) {
              silentLog(
                'safe_subprocess',
                'sigkill detached watchdog',
                error,
                stack,
              );
            }
          });
        } catch (error, stack) {
          // 已退出 → killPid 返回 false / 抛错，正常路径，无需处理。
          silentLog(
            'safe_subprocess',
            'sigterm detached watchdog',
            error,
            stack,
          );
        }
      });
    }
    return true;
  } catch (error, stack) {
    if (!_isMissingExecutableProcessException(error)) {
      silentLog(
        tag,
        '$executable ${arguments.take(1).join(' ')}',
        error,
        stack,
      );
    }
    return false;
  }
}

/// Opens a local file or directory with the system default application.
///
/// This is the preferred high-level wrapper for app UI actions. It rejects
/// URI-like strings and leading dash arguments so local-path open actions
/// cannot be accidentally upgraded into URL launches or command options.
Future<bool> openLocalPathWithSystemApp(
  String path, {
  String tag = 'safe_subprocess.open_path',
}) async {
  final target = _safeLocalPathArgument(path);
  if (target == null) return false;
  if (Platform.isMacOS) {
    return runDetachedSystemOpen('open', <String>[target], tag: tag);
  }
  if (Platform.isWindows) {
    return runDetachedSystemOpen(
      'cmd',
      <String>['/c', 'start', '', target],
      tag: tag,
      runInShell: true,
    );
  }
  if (Platform.isLinux) {
    return runDetachedSystemOpen('xdg-open', <String>[target], tag: tag);
  }
  return false;
}

/// Opens a http(s) URL with the user's system default browser.
///
/// Only absolute `http` / `https` URLs with a host are accepted. User-info and
/// whitespace are rejected so UI text cannot be promoted into launcher flags or
/// surprising credential-bearing URLs.
Future<bool> openHttpUrlWithSystemBrowser(
  String url, {
  String tag = 'safe_subprocess.open_url',
}) async {
  final uri = _safeHttpUrlArgument(url);
  if (uri == null) return false;
  final target = uri.toString();
  if (Platform.isMacOS) {
    return runDetachedSystemOpen('open', <String>[target], tag: tag);
  }
  if (Platform.isWindows) {
    return runDetachedSystemOpen('rundll32', <String>[
      'url.dll,FileProtocolHandler',
      target,
    ], tag: tag);
  }
  if (Platform.isLinux) {
    return runDetachedSystemOpen('xdg-open', <String>[target], tag: tag);
  }
  return false;
}

/// Reveals a local file or directory in the system file manager.
///
/// macOS and Windows highlight the target where supported. Linux file managers
/// do not share a portable "select file" contract, so this opens the target
/// directory, or the containing directory for files.
Future<bool> revealLocalPathInSystemFileManager(
  String path, {
  String tag = 'safe_subprocess.reveal_path',
}) async {
  final target = _safeLocalPathArgument(path);
  if (target == null) return false;
  if (Platform.isMacOS) {
    return runDetachedSystemOpen('open', <String>['-R', target], tag: tag);
  }
  if (Platform.isWindows) {
    final type = FileSystemEntity.typeSync(target, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      return runDetachedSystemOpen('explorer.exe', <String>[target], tag: tag);
    }
    return runDetachedSystemOpen('explorer.exe', <String>[
      '/select,$target',
    ], tag: tag);
  }
  if (Platform.isLinux) {
    return runDetachedSystemOpen('xdg-open', <String>[
      _directoryForReveal(target),
    ], tag: tag);
  }
  return false;
}

Uri? _safeHttpUrlArgument(String value) {
  final target = nullIfBlank(value);
  if (target == null || target.startsWith('-')) return null;
  return tryParseValidHttpUrl(target);
}

String? _safeLocalPathArgument(String value) {
  final target = nullIfBlank(value);
  if (target == null || target.startsWith('-')) return null;
  final looksLikeUri = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(target);
  if (looksLikeUri && !(Platform.isWindows && _isWindowsDrivePath(target))) {
    return null;
  }
  return target;
}

bool _isWindowsDrivePath(String value) =>
    RegExp(r'^[A-Za-z]:([\\/]|$)').hasMatch(value);

String _directoryForReveal(String target) {
  try {
    final type = FileSystemEntity.typeSync(target, followLinks: false);
    if (type == FileSystemEntityType.directory) return target;
  } catch (error, stack) {
    silentLog('safe_subprocess', 'resolve reveal directory', error, stack);
  }
  return File(target).parent.path;
}

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../features/ai/service/runtime/ai_tool_execution_registry.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
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
final Expando<bool> _trackedProcessGroupLeaders = Expando<bool>(
  'openhand.processGroupLeader',
);
Future<_ProcessGroupLauncher?>? _processGroupLauncherProbe;

const Duration _directChildEnumerationTimeout = Duration(seconds: 2);
const Duration _directChildTerminateGrace = Duration(milliseconds: 120);
const Duration _processTreeFinalWait = Duration(milliseconds: 250);
const Duration _processStreamCleanupTimeout = Duration(milliseconds: 500);
const Duration _windowsTaskkillTimeout = Duration(seconds: 2);
const int _maxDescendantProcesses = 256;

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
  unawaited(
    process.exitCode.then<void>(
      (_) => _trackedChildren.remove(process.pid),
      onError: (Object error, StackTrace stack) {
        _trackedChildren.remove(process.pid);
        silentLog(
          'safe_subprocess',
          'observe tracked child exit',
          error,
          stack,
        );
      },
    ),
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
  final argumentSnapshot = List<String>.of(arguments, growable: false);
  final environmentSnapshot = environment == null
      ? null
      : Map<String, String>.of(environment);
  final process = await Process.start(
    executable,
    argumentSnapshot,
    workingDirectory: workingDirectory,
    environment: environmentSnapshot,
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
  return (await _startTrackedProcessInNewGroup(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: runInShell,
    includeParentEnvironment: includeParentEnvironment,
    mode: mode,
  )).process;
}

Future<_TrackedProcessLaunch> _startTrackedProcessInNewGroup(
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
    return _TrackedProcessLaunch(
      process: await startTrackedProcess(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: runInShell,
        includeParentEnvironment: includeParentEnvironment,
        mode: mode,
      ),
      isProcessGroupLeader: false,
    );
  }
  final launcher = await _resolveProcessGroupLauncher();
  if (launcher == null) {
    return _TrackedProcessLaunch(
      process: await startTrackedProcess(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
        mode: mode,
      ),
      isProcessGroupLeader: false,
    );
  }
  final process = await startTrackedProcess(
    launcher.executable,
    <String>[...launcher.prefixArguments, executable, ...arguments],
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    mode: mode,
  );
  // Keep group identity on the Process handle even after the leader exits.
  // Descendants may still own inherited pipes at that point; an Expando
  // avoids both PID-reuse ambiguity and a global set that grows forever.
  _trackedProcessGroupLeaders[process] = true;
  return _TrackedProcessLaunch(process: process, isProcessGroupLeader: true);
}

class _TrackedProcessLaunch {
  const _TrackedProcessLaunch({
    required this.process,
    required this.isProcessGroupLeader,
  });

  final Process process;
  final bool isProcessGroupLeader;
}

class _ProcessGroupLauncher {
  const _ProcessGroupLauncher(
    this.executable, [
    this.prefixArguments = const <String>[],
  ]);

  final String executable;
  final List<String> prefixArguments;
}

/// Terminates a process plus its POSIX process group when the process was
/// launched through [startTrackedProcessInNewGroup].
Future<void> terminateTrackedProcessTree(
  Process process, {
  Duration? gracefulTimeout,
}) async {
  await _terminateTrackedProcessTree(process, gracefulTimeout: gracefulTimeout);
}

Future<void> _terminateTrackedProcessTree(
  Process process, {
  Duration? gracefulTimeout,
  bool knownProcessGroupLeader = false,
}) async {
  final pid = process.pid;
  if (pid <= 0) return;
  if (Platform.isWindows) {
    await _runWindowsTaskkillTree(pid, force: false);
    try {
      process.kill();
    } catch (error, stack) {
      silentLog('safe_subprocess', 'terminate windows child', error, stack);
    }
    final effectiveGracefulTimeout =
        gracefulTimeout ??
        Duration(milliseconds: safeSubprocessDefaultGracefulShutdownMs);
    final boundedGracefulTimeout = effectiveGracefulTimeout.isNegative
        ? Duration.zero
        : effectiveGracefulTimeout;
    try {
      await process.exitCode.timeout(boundedGracefulTimeout);
      return;
    } on TimeoutException {
      // Escalate the complete Windows process tree below.
    } catch (error, stack) {
      silentLog('safe_subprocess', 'wait windows child', error, stack);
    }
    await _runWindowsTaskkillTree(pid, force: true);
    try {
      process.kill(ProcessSignal.sigkill);
    } catch (error, stack) {
      silentLog('safe_subprocess', 'force kill windows child', error, stack);
    }
    return;
  }
  final isGroupLeader =
      knownProcessGroupLeader ||
      (_trackedProcessGroupLeaders[process] ?? false);
  final descendants = isGroupLeader
      ? const <int>[]
      : await _collectDescendantPids(pid);
  final effectiveGracefulTimeout =
      gracefulTimeout ??
      Duration(milliseconds: safeSubprocessDefaultGracefulShutdownMs);
  final boundedGracefulTimeout = effectiveGracefulTimeout.isNegative
      ? Duration.zero
      : effectiveGracefulTimeout;

  if (isGroupLeader) {
    await _sendSignalToProcessGroup(pid, 'TERM');
  } else {
    _signalProcessIds(
      descendants.reversed,
      ProcessSignal.sigterm,
      where: 'sigterm process descendant',
    );
  }
  try {
    process.kill();
  } catch (error, stack) {
    silentLog('safe_subprocess', 'sigterm child', error, stack);
  }

  if (!isGroupLeader && descendants.isEmpty) {
    try {
      await process.exitCode.timeout(boundedGracefulTimeout);
      return;
    } on TimeoutException {
      // Escalate below.
    } catch (error, stack) {
      silentLog('safe_subprocess', 'wait child after sigterm', error, stack);
    }
  } else if (boundedGracefulTimeout > Duration.zero) {
    // A direct parent's exit does not prove that its descendants stopped.
    // Give the complete group/snapshot the configured grace before SIGKILL.
    await Future<void>.delayed(boundedGracefulTimeout);
  }

  if (isGroupLeader) {
    await _sendSignalToProcessGroup(pid, 'KILL');
  } else {
    _signalProcessIds(
      descendants.reversed,
      ProcessSignal.sigkill,
      where: 'sigkill process descendant',
    );
  }
  try {
    process.kill(ProcessSignal.sigkill);
  } catch (error, stack) {
    silentLog('safe_subprocess', 'sigkill child', error, stack);
  }
  try {
    await process.exitCode.timeout(_processTreeFinalWait);
  } catch (error, stack) {
    silentLog('safe_subprocess', 'final process exit wait', error, stack);
  }
}

Future<void> _runWindowsTaskkillTree(
  int processId, {
  required bool force,
}) async {
  if (processId <= 0) return;
  final launchFuture = startTrackedProcess('taskkill', <String>[
    '/PID',
    '$processId',
    '/T',
    if (force) '/F',
  ]);
  Process? taskkill;
  StreamSubscription<List<int>>? stdoutSub;
  StreamSubscription<List<int>>? stderrSub;
  try {
    taskkill = await launchFuture.timeout(_windowsTaskkillTimeout);
    stdoutSub = taskkill.stdout.listen(
      (_) {},
      onError: (Object error, StackTrace stack) {
        silentLog('safe_subprocess', 'taskkill stdout', error, stack);
      },
      cancelOnError: true,
    );
    stderrSub = taskkill.stderr.listen(
      (_) {},
      onError: (Object error, StackTrace stack) {
        silentLog('safe_subprocess', 'taskkill stderr', error, stack);
      },
      cancelOnError: true,
    );
    await taskkill.exitCode.timeout(
      _windowsTaskkillTimeout,
      onTimeout: () {
        taskkill?.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  } on TimeoutException {
    unawaited(
      launchFuture.then<void>((lateProcess) {
        lateProcess.kill(ProcessSignal.sigkill);
      }, onError: (Object _, StackTrace _) {}),
    );
  } catch (error, stack) {
    silentLog('safe_subprocess', 'taskkill process tree', error, stack);
    try {
      taskkill?.kill(ProcessSignal.sigkill);
    } catch (killError, killStack) {
      silentLog('safe_subprocess', 'kill stuck taskkill', killError, killStack);
    }
  } finally {
    await Future.wait<void>(<Future<void>>[
      _cancelProcessSubscription(stdoutSub, 'safe_subprocess', 'taskkill out'),
      _cancelProcessSubscription(stderrSub, 'safe_subprocess', 'taskkill err'),
    ]);
  }
}

Future<List<int>> _collectDescendantPids(int rootPid) async {
  if ((!Platform.isMacOS && !Platform.isLinux) || rootPid <= 0) {
    return const <int>[];
  }
  final pgrep = File('/usr/bin/pgrep').existsSync()
      ? '/usr/bin/pgrep'
      : 'pgrep';
  final pendingParents = ListQueue<int>()..add(rootPid);
  final descendants = <int>{};
  final stopwatch = Stopwatch()..start();
  while (pendingParents.isNotEmpty &&
      descendants.length < _maxDescendantProcesses) {
    final remaining = _directChildEnumerationTimeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) break;
    final parentPid = pendingParents.removeFirst();
    try {
      final result = await Process.run(pgrep, <String>[
        '-P',
        '$parentPid',
      ]).timeout(remaining);
      if (result.exitCode != 0) continue;
      for (final childPid in _parseChildPids(
        result.stdout,
        parentPid: parentPid,
      )) {
        if (descendants.add(childPid)) {
          pendingParents.add(childPid);
          if (descendants.length >= _maxDescendantProcesses) break;
        }
      }
    } on TimeoutException {
      break;
    } catch (error, stack) {
      silentLog(
        'safe_subprocess',
        'enumerate process descendants',
        error,
        stack,
      );
      break;
    }
  }
  stopwatch.stop();
  return List<int>.unmodifiable(descendants);
}

void _signalProcessIds(
  Iterable<int> processIds,
  ProcessSignal signal, {
  required String where,
}) {
  for (final processId in processIds) {
    if (processId <= 0 || processId == pid) continue;
    try {
      Process.killPid(processId, signal);
    } catch (error, stack) {
      silentLog('safe_subprocess', where, error, stack);
    }
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
    if (_trackedProcessGroupLeaders[p] ?? false) {
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
    if (_trackedProcessGroupLeaders[p] ?? false) {
      unawaited(_sendSignalToProcessGroup(p.pid, 'KILL'));
    }
  }
}

/// 当前仍由应用跟踪的子进程 PID 快照。
List<int> trackedChildPidsSnapshot() =>
    List<int>.unmodifiable(_trackedChildren.keys);

Future<_ProcessGroupLauncher?> _resolveProcessGroupLauncher() {
  if (_processGroupLauncherProbe != null) return _processGroupLauncherProbe!;
  _processGroupLauncherProbe = () async {
    const candidates = <String>[
      '/usr/bin/setsid',
      '/usr/local/bin/setsid',
      '/opt/homebrew/bin/setsid',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return _ProcessGroupLauncher(candidate);
      }
    }
    try {
      final result = await runTrackedProcessOrFailed(
        '/bin/sh',
        <String>['-lc', 'command -v setsid 2>/dev/null'],
        timeout: const Duration(seconds: 2),
        tag: 'safe_subprocess.setsid_probe',
        startInNewProcessGroup: false,
      );
      final path = nullIfBlank(result.stdout as String);
      if (path != null && File(path).existsSync()) {
        return _ProcessGroupLauncher(path);
      }
    } catch (error, stack) {
      silentLog('safe_subprocess', 'resolve setsid', error, stack);
    }
    // macOS does not ship coreutils `setsid`. System Perl exposes the same
    // syscall, so use a direct argv-preserving exec shim rather than silently
    // losing process-tree cleanup on the primary desktop platform.
    const perl = '/usr/bin/perl';
    if (Platform.isMacOS && File(perl).existsSync()) {
      return const _ProcessGroupLauncher(perl, <String>[
        '-MPOSIX',
        '-e',
        'defined POSIX::setsid() or die "setsid failed: \$!"; '
            'exec @ARGV; die "exec failed: \$!";',
        '--',
      ]);
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
/// Stdout/stderr are drained continuously but retained only up to
/// [maxStdoutBytes]/[maxStderrBytes], so a noisy process or a descendant that
/// inherits the pipes cannot grow memory without bound. Returns null when the
/// command times out or fails to start; non-zero exits remain normal
/// [ProcessResult] values. All errors are logged via [silentLog] (debug-only).
/// [stdinBytes] are written before stdin is always closed, and that work shares
/// the same wall-clock timeout. [onProcessStarted] runs once after output
/// subscriptions are installed so cancellable callers can retain a safe handle.
/// [onFailure] observes launch/runtime failures before this helper converts them
/// to `null`; callback failures are isolated from process cleanup.
/// [outputDecoder] defaults to tolerant UTF-8; callers wrapping legacy system
/// tools may supply [SystemEncoding.decoder] without duplicating collection.
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
  List<int> stdinBytes = const <int>[],
  Duration timeout = const Duration(seconds: 4),
  String tag = 'safe_subprocess',
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
  String? toolCallId,
  int? gracefulShutdownMs,
  int maxStdoutBytes = 1024 * 1024,
  int maxStderrBytes = 256 * 1024,
  Converter<List<int>, String> outputDecoder = const Utf8Decoder(
    allowMalformed: true,
  ),
  bool startInNewProcessGroup = true,
  void Function(Process process)? onProcessStarted,
  void Function(Object error, StackTrace stack)? onFailure,
  ProcessResult Function(int pid, String stdout, String stderr)?
  timeoutResultBuilder,
}) async {
  final configuredGracefulMs =
      gracefulShutdownMs ?? safeSubprocessDefaultGracefulShutdownMs;
  final effectiveGracefulMs = configuredGracefulMs < 0
      ? 0
      : configuredGracefulMs;
  final effectiveTimeout = timeout.isNegative ? Duration.zero : timeout;
  final argumentSnapshot = List<String>.of(arguments, growable: false);
  final environmentSnapshot = environment == null
      ? null
      : Map<String, String>.of(environment);
  Process? process;
  var isProcessGroupLeader = false;
  var timedOut = false;
  StreamSubscription<List<int>>? stdoutSubscription;
  StreamSubscription<List<int>>? stderrSubscription;
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  final stdoutBytes = BytesBuilder(copy: false);
  final stderrBytes = BytesBuilder(copy: false);
  final normalizedToolCallId = nullIfBlank(toolCallId);
  final stdoutLimit = maxStdoutBytes < 0 ? 0 : maxStdoutBytes;
  final stderrLimit = maxStderrBytes < 0 ? 0 : maxStderrBytes;
  final executionStopwatch = Stopwatch()..start();

  void completeStream(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  void collectBounded(BytesBuilder target, List<int> chunk, int maxBytes) {
    if (maxBytes <= 0 || target.length >= maxBytes) return;
    final remaining = maxBytes - target.length;
    target.add(chunk.length <= remaining ? chunk : chunk.sublist(0, remaining));
  }

  String decodeOutput(BytesBuilder source, String streamName) {
    final bytes = source.takeBytes();
    try {
      return outputDecoder.convert(bytes);
    } catch (error, stack) {
      silentLog(tag, 'decode $streamName $executable', error, stack);
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
  }

  Future<bool> waitForStreams() async {
    try {
      await Future.wait<void>([
        stdoutDone.future,
        stderrDone.future,
      ]).timeout(_processStreamCleanupTimeout);
      return true;
    } on TimeoutException {
      // Subscriptions are explicitly cancelled in finally. A descendant that
      // inherited the pipe therefore cannot keep buffering after this call.
      return false;
    } catch (error, stack) {
      silentLog(tag, 'wait output streams $executable', error, stack);
      return false;
    }
  }

  try {
    final launchFuture = startInNewProcessGroup
        ? _startTrackedProcessInNewGroup(
            executable,
            argumentSnapshot,
            workingDirectory: workingDirectory,
            environment: environmentSnapshot,
            runInShell: runInShell,
            includeParentEnvironment: includeParentEnvironment,
          )
        : startTrackedProcess(
            executable,
            argumentSnapshot,
            workingDirectory: workingDirectory,
            environment: environmentSnapshot,
            runInShell: runInShell,
            includeParentEnvironment: includeParentEnvironment,
          ).then(
            (started) => _TrackedProcessLaunch(
              process: started,
              isProcessGroupLeader: false,
            ),
          );
    late final _TrackedProcessLaunch launch;
    try {
      launch = await launchFuture.timeout(effectiveTimeout);
    } on TimeoutException {
      timedOut = true;
      unawaited(
        launchFuture.then<void>(
          (lateLaunch) async {
            await _terminateTrackedProcessTree(
              lateLaunch.process,
              gracefulTimeout: Duration(milliseconds: effectiveGracefulMs),
              knownProcessGroupLeader: lateLaunch.isProcessGroupLeader,
            );
          },
          onError: (Object error, StackTrace stack) {
            if (!_isMissingExecutableProcessException(error)) {
              silentLog(tag, 'late process start $executable', error, stack);
            }
          },
        ),
      );
      return timeoutResultBuilder?.call(-1, '', '');
    }
    process = launch.process;
    isProcessGroupLeader = launch.isProcessGroupLeader;
    if (normalizedToolCallId != null) {
      final spawned = process;
      final spawnedAsGroupLeader = isProcessGroupLeader;
      AiToolExecutionRegistry.instance.attachPid(
        normalizedToolCallId,
        spawned.pid,
      );
      AiToolExecutionRegistry.instance.attachKiller(
        normalizedToolCallId,
        () async {
          await _terminateTrackedProcessTree(
            spawned,
            gracefulTimeout: Duration(milliseconds: effectiveGracefulMs),
            knownProcessGroupLeader: spawnedAsGroupLeader,
          );
        },
      );
    }
    stdoutSubscription = process.stdout.listen(
      (chunk) => collectBounded(stdoutBytes, chunk, stdoutLimit),
      onError: (Object error, StackTrace stack) {
        silentLog(tag, 'stdout $executable', error, stack);
        completeStream(stdoutDone);
      },
      onDone: () => completeStream(stdoutDone),
      cancelOnError: true,
    );
    stderrSubscription = process.stderr.listen(
      (chunk) => collectBounded(stderrBytes, chunk, stderrLimit),
      onError: (Object error, StackTrace stack) {
        silentLog(tag, 'stderr $executable', error, stack);
        completeStream(stderrDone);
      },
      onDone: () => completeStream(stderrDone),
      cancelOnError: true,
    );
    onProcessStarted?.call(process);

    Future<void> closeStdin() async {
      try {
        if (stdinBytes.isNotEmpty) process!.stdin.add(stdinBytes);
        await process!.stdin.flush();
      } catch (error, stack) {
        silentLog(tag, 'write stdin $executable', error, stack);
      } finally {
        try {
          await process!.stdin.close();
        } catch (error, stack) {
          silentLog(tag, 'close stdin $executable', error, stack);
        }
      }
    }

    final remainingTimeout = effectiveTimeout - executionStopwatch.elapsed;
    final exitCode =
        await (() async {
          await closeStdin();
          return process!.exitCode;
        })().timeout(
          remainingTimeout > Duration.zero ? remainingTimeout : Duration.zero,
          onTimeout: () async {
            timedOut = true;
            // Crucial: terminate the complete command tree before returning.
            await _terminateTrackedProcessTree(
              process!,
              gracefulTimeout: Duration(milliseconds: effectiveGracefulMs),
              knownProcessGroupLeader: isProcessGroupLeader,
            );
            return -1;
          },
        );
    final streamsFinished = await waitForStreams();
    if (!streamsFinished && !timedOut) {
      await _terminateTrackedProcessTree(
        process,
        gracefulTimeout: Duration(milliseconds: effectiveGracefulMs),
        knownProcessGroupLeader: isProcessGroupLeader,
      );
    }
    final stdoutText = decodeOutput(stdoutBytes, 'stdout');
    final stderrText = decodeOutput(stderrBytes, 'stderr');
    if (timedOut) {
      return timeoutResultBuilder?.call(process.pid, stdoutText, stderrText);
    }
    return ProcessResult(process.pid, exitCode, stdoutText, stderrText);
  } catch (error, stack) {
    if (process != null) {
      await _terminateTrackedProcessTree(
        process,
        gracefulTimeout: Duration(milliseconds: effectiveGracefulMs),
        knownProcessGroupLeader: isProcessGroupLeader,
      );
    }
    try {
      onFailure?.call(error, stack);
    } catch (callbackError, callbackStack) {
      silentLog(
        tag,
        'process failure callback $executable',
        callbackError,
        callbackStack,
      );
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
    await Future.wait<void>(<Future<void>>[
      _cancelProcessSubscription(stdoutSubscription, tag, 'stdout'),
      _cancelProcessSubscription(stderrSubscription, tag, 'stderr'),
    ]);
  }
}

Future<void> _cancelProcessSubscription<T>(
  StreamSubscription<T>? subscription,
  String tag,
  String streamName,
) async {
  await cancelStreamSubscriptionBounded<T>(
    subscription,
    timeout: _processStreamCleanupTimeout,
    onError: (error, stack) =>
        silentLog(tag, 'cancel $streamName subscription', error, stack),
  );
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
  bool startInNewProcessGroup = true,
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
    startInNewProcessGroup: startInNewProcessGroup,
  );
  return r ?? ProcessResult(-1, -1, '', '');
}

typedef ProcessLogLineHandler = void Function(String line);

class TrackedProcessLineLogResult {
  const TrackedProcessLineLogResult({
    required this.pid,
    required this.exitCode,
    required this.timedOut,
    required this.stdout,
    required this.stderr,
  });

  final int pid;
  final int exitCode;
  final bool timedOut;
  final String stdout;
  final String stderr;
}

class _BoundedProcessLineCapture {
  _BoundedProcessLineCapture({required int maxLines})
    : _maxLines = maxLines < 0 ? 0 : maxLines;

  final int _maxLines;
  final ListQueue<String> _lines = ListQueue<String>();

  void add(String line) {
    if (_maxLines == 0) return;
    if (_lines.length >= _maxLines) {
      _lines.removeFirst();
    }
    _lines.add(line);
  }

  String get text => _lines.join('\n');
}

class _BoundedProcessLineDecoder {
  _BoundedProcessLineDecoder({required int maxCharacters, required this.onLine})
    : _maxCharacters = maxCharacters < 1 ? 1 : maxCharacters;

  final int _maxCharacters;
  final void Function(String line) onLine;
  final StringBuffer _buffer = StringBuffer();
  bool _truncated = false;

  void add(String chunk) {
    var start = 0;
    while (start < chunk.length) {
      final lineEnd = chunk.indexOf('\n', start);
      if (lineEnd < 0) {
        _append(chunk.substring(start));
        return;
      }
      _append(chunk.substring(start, lineEnd));
      _emit();
      start = lineEnd + 1;
    }
  }

  void close() {
    if (_buffer.isNotEmpty || _truncated) _emit();
  }

  void _append(String segment) {
    if (segment.isEmpty || _truncated) return;
    final candidate = '${_buffer.toString()}$segment';
    final bounded = clipText(candidate, _maxCharacters, suffix: '');
    _truncated = bounded != candidate;
    _buffer
      ..clear()
      ..write(bounded);
  }

  void _emit() {
    var line = _buffer.toString();
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (_truncated) line = '$line…';
    onLine(line);
    _buffer.clear();
    _truncated = false;
  }
}

/// Starts a tracked process, streams stdout/stderr as decoded text lines, and
/// kills the process when [timeout] expires.
///
/// This is intended for UI install/update flows that need live logs without
/// duplicating stdout/stderr subscription, timeout, and cleanup code. Stream
/// errors are logged and do not fail the process run; spawn/exit failures still
/// propagate to the caller. By default the command starts in a dedicated POSIX
/// process group, so a timeout terminates the complete command tree instead of
/// leaving npm/pip/shell descendants behind. [onProcessStarted] runs after both
/// output subscriptions are installed so interactive callers can retain a safe
/// cancellation handle without reimplementing stream ownership. An optional
/// [processStartTimeout] can cap only the launch phase while [timeout] remains
/// the total wall-clock deadline.
Future<TrackedProcessLineLogResult> runTrackedProcessWithLineLogging(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  Duration? processStartTimeout,
  String tag = 'safe_subprocess',
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
  ProcessLogLineHandler? onStdoutLine,
  ProcessLogLineHandler? onStderrLine,
  void Function(Process process)? onProcessStarted,
  void Function()? onTimeout,
  Duration streamDrainTimeout = const Duration(milliseconds: 500),
  Duration gracefulTerminationTimeout = const Duration(milliseconds: 500),
  bool startInNewProcessGroup = true,
  bool trimStdoutLines = false,
  bool trimStderrLines = true,
  int maxCapturedLinesPerStream = 0,
  int maxLineCharacters = 4000,
}) async {
  final effectiveTimeout = timeout.isNegative ? Duration.zero : timeout;
  final configuredStartTimeout = processStartTimeout;
  final effectiveStartTimeout = configuredStartTimeout == null
      ? effectiveTimeout
      : configuredStartTimeout.isNegative
      ? Duration.zero
      : configuredStartTimeout > effectiveTimeout
      ? effectiveTimeout
      : configuredStartTimeout;
  final effectiveDrainTimeout = streamDrainTimeout.isNegative
      ? Duration.zero
      : streamDrainTimeout;
  final executionStopwatch = Stopwatch()..start();
  var timedOut = false;
  Process? process;
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  final stdoutCapture = _BoundedProcessLineCapture(
    maxLines: maxCapturedLinesPerStream,
  );
  final stderrCapture = _BoundedProcessLineCapture(
    maxLines: maxCapturedLinesPerStream,
  );
  StreamSubscription<String>? stdoutSub;
  StreamSubscription<String>? stderrSub;

  void notifyTimeout() {
    try {
      onTimeout?.call();
    } catch (error, stack) {
      silentLog(tag, 'timeout handler $executable', error, stack);
    }
  }

  void complete(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  void handleLine(
    ProcessLogLineHandler? handler,
    _BoundedProcessLineCapture capture,
    String line,
  ) {
    if (nullIfBlank(line) == null) return;
    final boundedLine = clipTextWithEllipsis(
      line,
      maxLineCharacters < 1 ? 1 : maxLineCharacters,
    );
    capture.add(boundedLine);
    if (handler == null) return;
    try {
      handler(boundedLine);
    } catch (error, stack) {
      silentLog(tag, 'line handler $executable', error, stack);
    }
  }

  StreamSubscription<String> listenLines({
    required Stream<List<int>> stream,
    required String streamName,
    required Completer<void> done,
    required ProcessLogLineHandler? handler,
    required _BoundedProcessLineCapture capture,
    bool trimLine = false,
  }) {
    late final _BoundedProcessLineDecoder decoder;
    decoder = _BoundedProcessLineDecoder(
      maxCharacters: maxLineCharacters,
      onLine: (line) =>
          handleLine(handler, capture, trimLine ? line.trim() : line),
    );
    return stream
        .transform(const SystemEncoding().decoder)
        .listen(
          decoder.add,
          onError: (Object error, StackTrace stack) {
            silentLog(tag, '$streamName $executable', error, stack);
            complete(done);
          },
          onDone: () {
            decoder.close();
            complete(done);
          },
          cancelOnError: false,
        );
  }

  Future<bool> waitForStreamDrain() async {
    try {
      await Future.wait<void>([
        stdoutDone.future,
        stderrDone.future,
      ]).timeout(effectiveDrainTimeout);
      return true;
    } on TimeoutException {
      silentLog(
        tag,
        'stream drain timeout',
        '$executable ${arguments.take(1).join(' ')}',
      );
      return false;
    } catch (error, stack) {
      silentLog(tag, 'wait output streams $executable', error, stack);
      return false;
    }
  }

  try {
    final launchFuture = startInNewProcessGroup
        ? startTrackedProcessInNewGroup(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            runInShell: runInShell,
            includeParentEnvironment: includeParentEnvironment,
          )
        : startTrackedProcess(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            runInShell: runInShell,
            includeParentEnvironment: includeParentEnvironment,
          );
    try {
      process = await launchFuture.timeout(effectiveStartTimeout);
    } on TimeoutException {
      timedOut = true;
      notifyTimeout();
      unawaited(
        launchFuture.then<void>(
          (lateProcess) => terminateTrackedProcessTree(
            lateProcess,
            gracefulTimeout: gracefulTerminationTimeout,
          ),
          onError: (Object error, StackTrace stack) {
            if (!_isMissingExecutableProcessException(error)) {
              silentLog(tag, 'late process start $executable', error, stack);
            }
          },
        ),
      );
      return TrackedProcessLineLogResult(
        pid: -1,
        exitCode: -1,
        timedOut: true,
        stdout: stdoutCapture.text,
        stderr: stderrCapture.text,
      );
    }
    stdoutSub = listenLines(
      stream: process.stdout,
      streamName: 'stdout',
      done: stdoutDone,
      handler: onStdoutLine,
      capture: stdoutCapture,
      trimLine: trimStdoutLines,
    );
    stderrSub = listenLines(
      stream: process.stderr,
      streamName: 'stderr',
      done: stderrDone,
      handler: onStderrLine,
      capture: stderrCapture,
      trimLine: trimStderrLines,
    );
    onProcessStarted?.call(process);
    final remainingTimeout = effectiveTimeout - executionStopwatch.elapsed;
    final exitCode =
        await (() async {
          try {
            await process!.stdin.close();
          } catch (error, stack) {
            silentLog(tag, 'close stdin $executable', error, stack);
          }
          return process!.exitCode;
        })().timeout(
          remainingTimeout > Duration.zero ? remainingTimeout : Duration.zero,
          onTimeout: () async {
            timedOut = true;
            notifyTimeout();
            await terminateTrackedProcessTree(
              process!,
              gracefulTimeout: gracefulTerminationTimeout,
            );
            return -1;
          },
        );
    final streamsFinished = await waitForStreamDrain();
    if (!streamsFinished) {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: gracefulTerminationTimeout,
      );
    }
    return TrackedProcessLineLogResult(
      pid: process.pid,
      exitCode: exitCode,
      timedOut: timedOut,
      stdout: stdoutCapture.text,
      stderr: stderrCapture.text,
    );
  } catch (_) {
    if (process != null) {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: gracefulTerminationTimeout,
      );
    }
    rethrow;
  } finally {
    await Future.wait<void>(<Future<void>>[
      _cancelProcessSubscription(stdoutSub, tag, 'stdout'),
      _cancelProcessSubscription(stderrSub, tag, 'stderr'),
    ]);
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
    await Future.wait<void>(<Future<void>>[
      _cancelProcessSubscription(stdoutSub, tag, 'stdout'),
      _cancelProcessSubscription(stderrSub, tag, 'stderr'),
    ]);
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

/// Opens a constrained external URI with the system default application.
///
/// Accepted schemes are deliberately narrow: http(s), file and mailto. Local
/// files are routed through [openLocalPathWithSystemApp] so path safety checks
/// stay centralized; http(s) URLs reuse [openHttpUrlWithSystemBrowser].
Future<bool> openExternalUriWithSystemApp(
  Uri uri, {
  String tag = 'safe_subprocess.open_external_uri',
}) async {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    return openHttpUrlWithSystemBrowser(uri.toString(), tag: tag);
  }
  if (scheme == 'file') {
    try {
      return openLocalPathWithSystemApp(uri.toFilePath(), tag: tag);
    } catch (error, stack) {
      silentLog('safe_subprocess', 'open file uri', error, stack);
      return false;
    }
  }
  if (scheme == 'mailto') {
    final target = _safeMailtoUriArgument(uri);
    if (target == null) return false;
    return _openSystemDefaultTarget(target, tag: tag);
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

Future<bool> _openSystemDefaultTarget(String target, {required String tag}) {
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
  return Future<bool>.value(false);
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

String? _safeMailtoUriArgument(Uri uri) {
  if (uri.scheme.toLowerCase() != 'mailto') return null;
  final target = uri.toString();
  if (target.startsWith('-') || RegExp(r'\s').hasMatch(target)) return null;
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

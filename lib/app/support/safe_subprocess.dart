import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import '../../features/ai/service/runtime/ai_tool_execution_registry.dart';
import '../../shared/util/argument_guards.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/bounded_log_buffer.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/duration_bounds.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/text_normalization.dart';
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
/// 退出时，[killAllTrackedChildren] 会批量 SIGTERM → 统一等待 → SIGKILL，
/// 杜绝遗留 osascript / LSP / mitmdump / npm 等子进程继续向系统投递
/// Apple Events / 抢占 IMK 上下文造成全局 TextField 输入死锁。
///
/// 之所以维护 pid → Process 而不是只存 pid：
///   1) `Process.kill(SIGKILL)` 不需要再 lookup，无 pid 复用风险；
///   2) `exitCode` 已被组件代码 await 时，我们也能并行听到。
final Map<int, Process> _trackedChildren = <int, Process>{};
final Map<int, Process> _trackedProcessGroups = <int, Process>{};
final Expando<bool> _trackedProcessGroupLeaders = Expando<bool>(
  'openhand.processGroupLeader',
);
final _processGroupLauncherCache =
    OpenHandRetryableAsyncCache<_ProcessGroupLauncher?>(
      _probeProcessGroupLauncher,
    );
Timer? _processGroupPruneTimer;
Future<void>? _trackedChildrenCleanupFuture;
_TrackedChildrenCleanupPhase _trackedChildrenCleanupPhase =
    _TrackedChildrenCleanupPhase.idle;
final Set<Process> _trackedChildrenRegisteredDuringCleanup =
    HashSet<Process>.identity();

const Duration _directChildEnumerationTimeout = Duration(seconds: 2);
const Duration _directChildTerminateGrace = Duration(milliseconds: 120);
const Duration _processTreeFinalWait = Duration(milliseconds: 250);
const Duration _processStreamCleanupTimeout = Duration(milliseconds: 500);
const Duration _windowsTaskkillTimeout = Duration(seconds: 2);
const Duration _processGroupSignalFallbackTimeout = Duration(seconds: 2);
const Duration _processExecutableProbeTimeout = Duration(milliseconds: 500);
const Duration _systemOpenProcessStartTimeout = Duration(seconds: 5);
const Duration _processGroupPruneInterval = Duration(seconds: 5);
const Duration _processGroupProbeTimeout = Duration(milliseconds: 500);
const Duration _trackedChildrenCleanupPreparationTimeout = Duration(
  milliseconds: 250,
);
const Duration _maxSubprocessGracefulTimeout = Duration(seconds: 5);
const Duration _maxSubprocessExecutionTimeout = Duration(hours: 24);
const Duration _maxSubprocessStartTimeout = Duration(minutes: 5);
const Duration _maxSubprocessStreamDrainTimeout = Duration(seconds: 30);
const int _processGroupProbeConcurrency = 4;
const int _maxDescendantProcesses = 256;
const int _maxCapturedProcessBytesPerStream = 16 * kBytesPerMiB;
const int _posixExistenceProbeSignal = 0;

typedef _NativePosixKill = Int32 Function(Int32 processId, Int32 signal);
typedef _PosixKill = int Function(int processId, int signal);

final _PosixKill? _posixKill = _resolvePosixKill();

enum _TrackedChildrenCleanupPhase {
  idle,
  preparing,
  terminating,
  waitingForGrace,
  forcing,
}

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
  _applyTrackedChildrenCleanupPhase(process);
  unawaited(
    process.exitCode.then<void>(
      (_) {
        if (identical(_trackedChildren[process.pid], process)) {
          _trackedChildren.remove(process.pid);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_trackedChildren[process.pid], process)) {
          _trackedChildren.remove(process.pid);
        }
        silentLog('safe_subprocess', '监听已跟踪子进程退出', error, stack);
      },
    ),
  );
}

void _applyTrackedChildrenCleanupPhase(Process process) {
  switch (_trackedChildrenCleanupPhase) {
    case _TrackedChildrenCleanupPhase.idle:
      return;
    case _TrackedChildrenCleanupPhase.preparing:
      _trackedChildrenRegisteredDuringCleanup.add(process);
      return;
    case _TrackedChildrenCleanupPhase.terminating:
    case _TrackedChildrenCleanupPhase.waitingForGrace:
      _trackedChildrenRegisteredDuringCleanup.add(process);
      _signalTrackedProcessForCleanup(process, ProcessSignal.sigterm);
      return;
    case _TrackedChildrenCleanupPhase.forcing:
      _trackedChildrenRegisteredDuringCleanup.add(process);
      _signalTrackedProcessForCleanup(process, ProcessSignal.sigkill);
      return;
  }
}

void _signalTrackedProcessForCleanup(Process process, ProcessSignal signal) {
  if (identical(_trackedProcessGroups[process.pid], process)) {
    final delivered = _sendSignalToProcessGroupDirect(process.pid, signal);
    if (delivered && signal == ProcessSignal.sigkill) {
      _trackedProcessGroups.remove(process.pid);
    }
  }
  if (!identical(_trackedChildren[process.pid], process)) return;
  try {
    process.kill(signal);
  } catch (error, stack) {
    silentLog('safe_subprocess', '终止清理期间新增的子进程', error, stack);
  }
}

void _ensureProcessGroupPruner() {
  if (_processGroupPruneTimer?.isActive ?? false) return;
  _processGroupPruneTimer = startNonOverlappingPeriodicTimer(
    _processGroupPruneInterval,
    (_) => _pruneExitedProcessGroups(),
    onError: (error, stack) =>
        silentLog('safe_subprocess', '清理已退出进程组', error, stack),
  );
}

void _stopProcessGroupPrunerIfIdle() {
  if (_trackedProcessGroups.isNotEmpty) return;
  _processGroupPruneTimer?.cancel();
  _processGroupPruneTimer = null;
}

Future<void> _pruneExitedProcessGroups() async {
  if (_trackedProcessGroups.isEmpty) {
    _stopProcessGroupPrunerIfIdle();
    return;
  }
  final snapshot = _trackedProcessGroups.entries.toList(growable: false);
  try {
    await forEachIndexWithConcurrencyLimit(
      itemCount: snapshot.length,
      maxConcurrency: _processGroupProbeConcurrency,
      task: (index) async {
        final entry = snapshot[index];
        if (await _isProcessGroupAlive(entry.key)) return;
        if (identical(_trackedProcessGroups[entry.key], entry.value)) {
          _trackedProcessGroups.remove(entry.key);
        }
      },
    );
  } finally {
    _stopProcessGroupPrunerIfIdle();
  }
}

Future<bool> _isProcessGroupAlive(int processGroupId) async {
  if (Platform.isWindows || processGroupId <= 0) return false;
  final posixKill = _posixKill;
  if (posixKill != null) {
    try {
      return posixKill(-processGroupId, _posixExistenceProbeSignal) == 0;
    } catch (error, stack) {
      // 探针异常时保守保留登记，交给后续周期任务重试。
      silentLog('safe_subprocess', '探测 POSIX 进程组状态', error, stack);
      return true;
    }
  }
  final result = await runBinaryProcessWithTimeout(
    '/bin/kill',
    <String>['-0', '-$processGroupId'],
    timeout: _processGroupProbeTimeout,
    maxStdoutBytes: 0,
    maxStderrBytes: 0,
    tag: 'safe_subprocess.probe_group',
    terminateProcessTreeOnFailure: false,
  );
  // 探针启动失败时保守保留登记，避免误丢仍存活的进程组。
  return result == null || result.exitCode == 0;
}

_PosixKill? _resolvePosixKill() {
  if (!Platform.isMacOS && !Platform.isLinux) return null;
  try {
    return DynamicLibrary.process()
        .lookupFunction<_NativePosixKill, _PosixKill>('kill');
  } catch (error, stack) {
    silentLog('safe_subprocess', '加载 POSIX 进程组探针', error, stack);
    return null;
  }
}

Future<void> _handleExitedProcessGroup(Process process) async {
  final processGroupId = process.pid;
  if (!identical(_trackedProcessGroups[processGroupId], process)) return;
  if (await _isProcessGroupAlive(processGroupId)) {
    if (identical(_trackedProcessGroups[processGroupId], process)) {
      _ensureProcessGroupPruner();
    }
    return;
  }
  if (identical(_trackedProcessGroups[processGroupId], process)) {
    _trackedProcessGroups.remove(processGroupId);
  }
  _stopProcessGroupPrunerIfIdle();
}

/// 启动一个长驻子进程（LSP / mitmdump / Hook / Cron / MCP 调试探针等）并
/// 登记到全局子进程簿；调用方仍然完整持有 [Process] 句柄，自行 await
/// `exitCode` / drain 管道即可。
///
/// 与 [runProcessWithTimeout] 的区别：本方法不限制运行时长，仅负责
/// “应用退出时陪葬”。业务代码应优先使用 [startTrackedProcessBounded]，
/// 一次性短命令请走 [runProcessWithTimeout]。
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

/// 在有限时长内启动受跟踪的长驻进程；超时后自动终止迟到创建的进程树。
Future<Process> startTrackedProcessBounded(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  String tag = 'safe_subprocess.tracked',
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
  bool startInNewProcessGroup = false,
}) async {
  requirePositiveDurationAtMost(timeout, _maxSubprocessStartTimeout, 'timeout');
  final launchFuture = startInNewProcessGroup
      ? _startTrackedProcessInNewGroup(
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
        ).then(
          (process) => _TrackedProcessLaunch(
            process: process,
            isProcessGroupLeader: false,
          ),
        );
  try {
    return (await launchFuture.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('受跟踪进程启动超时。', timeout),
    )).process;
  } on TimeoutException {
    _terminateLateBinaryProcess(
      launchFuture,
      tag: tag,
      terminateProcessTree: true,
    );
    rethrow;
  }
}

/// 在有限时长内启动脱离进程；启动超时后回收迟到创建的进程。
///
/// 脱离进程不会进入全局子进程簿，适用于重启助手和外部终端等明确需要独立于
/// 当前应用存活的进程。调用成功后由调用方负责其后续生命周期。
Future<Process> startDetachedProcessBounded(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  String tag = 'safe_subprocess.detached',
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
}) async {
  requirePositiveDurationAtMost(timeout, _maxSubprocessStartTimeout, 'timeout');
  final launchFuture = Process.start(
    executable,
    List<String>.of(arguments, growable: false),
    workingDirectory: workingDirectory,
    environment: environment == null
        ? null
        : Map<String, String>.of(environment),
    runInShell: runInShell,
    includeParentEnvironment: includeParentEnvironment,
    mode: ProcessStartMode.detached,
  );
  try {
    return await launchFuture.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('脱离进程启动超时。', timeout),
    );
  } on TimeoutException {
    unawaited(
      launchFuture.then<void>(
        (process) {
          try {
            process.kill(ProcessSignal.sigkill);
          } catch (error, stack) {
            silentLog(tag, '回收迟到启动的脱离进程', error, stack);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!_isMissingExecutableProcessException(error)) {
            silentLog(tag, '等待迟到脱离进程启动', error, stack);
          }
        },
      ),
    );
    rethrow;
  }
}

/// 平台提供 `setsid` 时，在新的 POSIX 进程组中启动受跟踪进程，并把包装进程
/// pid 记录为组长。
///
/// 调用方可通过 [terminateTrackedProcessTree] 终止整棵命令树，而不是只结束外层
/// shell。Windows、脱离模式或缺少 `setsid` 时回退到 [startTrackedProcess]，
/// 仍接受正常的应用退出清理。
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
  _trackedProcessGroupLeaders[process] = true;
  _trackedProcessGroups[process.pid] = process;
  _applyTrackedChildrenCleanupPhase(process);
  unawaited(
    process.exitCode
        .then<void>(
          (_) => _handleExitedProcessGroup(process),
          onError: (Object error, StackTrace stack) {
            silentLog('safe_subprocess', '监听进程组长退出', error, stack);
            return _handleExitedProcessGroup(process);
          },
        )
        .catchError((Object error, StackTrace stack) {
          silentLog('safe_subprocess', '清理退出进程组登记', error, stack);
        }),
  );
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

/// 终止进程；通过 [startTrackedProcessInNewGroup] 启动时同时终止其 POSIX 进程组。
Future<void> terminateTrackedProcessTree(
  Process process, {
  Duration? gracefulTimeout,
}) async {
  await _terminateTrackedProcessTree(process, gracefulTimeout: gracefulTimeout);
}

/// [TrackedProcessSlot] 默认的优雅终止等待窗口。
const Duration kTrackedProcessSlotGracePeriod = Duration(milliseconds: 500);

/// 单进程槽位：同一时刻只跟踪一个子进程，并用代际号作废过期的那一轮。
///
/// 安装 / 校验类弹窗共享同一套生命周期：开新一轮前自增代际，旧代际迟到交回
/// 的进程立刻终止而不占用槽位；取消与销毁时终止在跑的进程。此前 LSP 安装与
/// Harness CLI 安装各写了一份，任何加固都得改两处且容易漏。
///
/// 只负责进程与代际，`mounted` / `disposed` 这类 Widget 状态仍由调用方判断。
class TrackedProcessSlot {
  TrackedProcessSlot({
    required this.logTag,
    Duration gracefulTimeout = kTrackedProcessSlotGracePeriod,
  }) : gracefulTimeout = _boundedSubprocessGracefulTimeout(gracefulTimeout);

  /// 终止失败时 [silentLog] 使用的组件标签。
  final String logTag;

  /// 优雅终止的等待时长，超时后强杀整棵进程树。
  final Duration gracefulTimeout;

  Process? _process;
  int _generation = 0;

  /// 开启新一轮运行并返回本轮代际号。
  int beginRun() => ++_generation;

  /// [generation] 是否仍是当前这一轮。
  bool isCurrent(int generation) => generation == _generation;

  /// 认领本轮启动的进程；代际已过期则直接终止，不写入槽位。
  void claim(Process process, int generation, {required String staleAction}) {
    if (!isCurrent(generation)) {
      unawaited(terminate(process, staleAction));
      return;
    }
    _process = process;
  }

  /// 进程已自行退出后释放槽位；仅当槽位里仍是该进程时生效。
  void release(Process? process) {
    if (process != null && identical(_process, process)) _process = null;
  }

  /// 作废当前代际并终止槽位内的进程，用于取消与销毁。
  void abort(String action) {
    _generation += 1;
    final process = _process;
    _process = null;
    if (process != null) unawaited(terminate(process, action));
  }

  /// 终止指定进程；失败只记日志，不向上抛出。
  Future<void> terminate(Process process, String action) async {
    try {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: gracefulTimeout,
      );
    } catch (error, stack) {
      silentLog(logTag, action, error, stack);
    }
  }
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
      silentLog('safe_subprocess', '终止 Windows 子进程', error, stack);
    }
    final boundedGracefulTimeout = _boundedSubprocessGracefulTimeout(
      gracefulTimeout ??
          Duration(milliseconds: safeSubprocessDefaultGracefulShutdownMs),
    );
    try {
      await process.exitCode.timeout(boundedGracefulTimeout);
      return;
    } on TimeoutException {
      // 下方升级为强制终止整棵 Windows 进程树。
    } catch (error, stack) {
      silentLog('safe_subprocess', '等待 Windows 子进程退出', error, stack);
    }
    await _runWindowsTaskkillTree(pid, force: true);
    try {
      process.kill(ProcessSignal.sigkill);
    } catch (error, stack) {
      silentLog('safe_subprocess', '强制终止 Windows 子进程', error, stack);
    }
    return;
  }
  final isGroupLeader =
      knownProcessGroupLeader ||
      (_trackedProcessGroupLeaders[process] ?? false);
  final descendants = isGroupLeader
      ? const <int>[]
      : await _collectDescendantPids(pid);
  final boundedGracefulTimeout = _boundedSubprocessGracefulTimeout(
    gracefulTimeout ??
        Duration(milliseconds: safeSubprocessDefaultGracefulShutdownMs),
  );

  if (isGroupLeader) {
    await _sendSignalToProcessGroup(pid, ProcessSignal.sigterm);
  } else {
    _signalProcessIds(
      descendants.reversed,
      ProcessSignal.sigterm,
      where: '向 SIGTERM 子进程后代发送信号',
    );
  }
  try {
    process.kill();
  } catch (error, stack) {
    silentLog('safe_subprocess', '向子进程发送 SIGTERM', error, stack);
  }

  if (!isGroupLeader && descendants.isEmpty) {
    try {
      await process.exitCode.timeout(boundedGracefulTimeout);
      return;
    } on TimeoutException {
      // 下方升级为强制终止。
    } catch (error, stack) {
      silentLog('safe_subprocess', '等待 SIGTERM 后子进程退出', error, stack);
    }
  } else if (boundedGracefulTimeout > Duration.zero) {
    // 直接父进程退出不能证明后代已停止；发送 SIGKILL 前给整个进程组或快照
    // 留出配置的优雅退出窗口。
    await Future<void>.delayed(boundedGracefulTimeout);
  }

  if (isGroupLeader) {
    await _sendSignalToProcessGroup(pid, ProcessSignal.sigkill);
  } else {
    _signalProcessIds(
      descendants.reversed,
      ProcessSignal.sigkill,
      where: '向 SIGKILL 子进程后代发送信号',
    );
  }
  try {
    process.kill(ProcessSignal.sigkill);
  } catch (error, stack) {
    silentLog('safe_subprocess', '向子进程发送 SIGKILL', error, stack);
  }
  try {
    await process.exitCode.timeout(_processTreeFinalWait);
  } catch (error, stack) {
    silentLog('safe_subprocess', '最终等待子进程退出', error, stack);
  }
  if (isGroupLeader &&
      !await _isProcessGroupAlive(pid) &&
      identical(_trackedProcessGroups[pid], process)) {
    _trackedProcessGroups.remove(pid);
    _stopProcessGroupPrunerIfIdle();
  }
}

Future<void> _runWindowsTaskkillTree(
  int processId, {
  required bool force,
}) async {
  if (processId <= 0) return;
  await runBinaryProcessWithTimeout(
    'taskkill',
    <String>['/PID', '$processId', '/T', if (force) '/F'],
    timeout: _windowsTaskkillTimeout,
    maxStdoutBytes: 0,
    tag: 'safe_subprocess.taskkill',
    terminateProcessTreeOnFailure: false,
  );
}

Future<List<int>> _collectDescendantPids(
  int rootPid, {
  Duration timeout = _directChildEnumerationTimeout,
}) async {
  if ((!Platform.isMacOS && !Platform.isLinux) || rootPid <= 0) {
    return const <int>[];
  }
  final boundedTimeout = shorterDuration(
    nonNegativeDuration(timeout),
    _directChildEnumerationTimeout,
  );
  if (boundedTimeout <= Duration.zero) return const <int>[];
  final stopwatch = Stopwatch()..start();

  Duration remainingTime() {
    return nonNegativeDuration(boundedTimeout - stopwatch.elapsed);
  }

  String pgrep = 'pgrep';
  try {
    final remaining = remainingTime();
    if (remaining <= Duration.zero) return const <int>[];
    pgrep =
        await _firstExistingProcessExecutable(const <String>[
          '/usr/bin/pgrep',
        ]).timeout(remaining) ??
        pgrep;
  } on TimeoutException {
    return const <int>[];
  } catch (error, stack) {
    silentLog('safe_subprocess', '解析后代进程枚举器', error, stack);
    return const <int>[];
  }
  final pendingParents = ListQueue<int>()..add(rootPid);
  final descendants = <int>{};
  while (pendingParents.isNotEmpty &&
      descendants.length < _maxDescendantProcesses) {
    final remaining = remainingTime();
    if (remaining <= Duration.zero) break;
    final parentPid = pendingParents.removeFirst();
    try {
      final result = await runBinaryProcessWithTimeout(
        pgrep,
        <String>['-P', '$parentPid'],
        timeout: remaining,
        maxStdoutBytes: 64 * kBytesPerKiB,
        maxStderrBytes: 8 * kBytesPerKiB,
        tag: 'safe_subprocess.pgrep_descendants',
        terminateProcessTreeOnFailure: false,
      );
      if (result == null) break;
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
      silentLog('safe_subprocess', '枚举后代进程', error, stack);
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

/// 关闭所有登记在册的子进程：先批量发送 SIGTERM，统一等待
/// [gracefulTimeout]，再批量发送 SIGKILL。先用最多 250ms 收集未建组进程
/// 的后代 PID；宽限期最多五秒，收尾只等待一次固定窗口，避免进程数量放大
/// 退出时延。所有失败都会被吞掉，因为这是退出兜底路径，不能再抛新异常。
Future<void> killAllTrackedChildren({
  Duration gracefulTimeout = const Duration(milliseconds: 400),
}) {
  final active = _trackedChildrenCleanupFuture;
  if (active != null) return active;
  late final Future<void> cleanupFuture;
  cleanupFuture = _killAllTrackedChildren(gracefulTimeout: gracefulTimeout)
      .whenComplete(() {
        if (identical(_trackedChildrenCleanupFuture, cleanupFuture)) {
          _trackedChildrenCleanupFuture = null;
        }
      });
  _trackedChildrenCleanupFuture = cleanupFuture;
  return cleanupFuture;
}

Future<void> _killAllTrackedChildren({
  Duration gracefulTimeout = const Duration(milliseconds: 400),
}) async {
  _trackedChildrenCleanupPhase = _TrackedChildrenCleanupPhase.preparing;
  _trackedChildrenRegisteredDuringCleanup.clear();
  try {
    // 使用对象身份去重，避免 PID 复用导致旧回调影响新登记。
    final initialTargets = HashSet<Process>.identity()
      ..addAll(_trackedProcessGroups.values)
      ..addAll(_trackedChildren.values);
    if (initialTargets.isEmpty) return;

    final initialSnapshot = initialTargets.toList(growable: false);
    final boundedGracefulTimeout = _boundedSubprocessGracefulTimeout(
      gracefulTimeout,
    );
    final descendantPidsByProcess = HashMap<Process, List<int>>.identity();
    final preparationStopwatch = Stopwatch()..start();

    Duration remainingPreparationTime() {
      return nonNegativeDuration(
        _trackedChildrenCleanupPreparationTimeout -
            preparationStopwatch.elapsed,
      );
    }

    List<Process> collectCleanupTargets() {
      final targets = HashSet<Process>.identity()
        ..addAll(initialSnapshot)
        ..addAll(_trackedChildrenRegisteredDuringCleanup);
      return targets.toList(growable: false);
    }

    await forEachIndexWithConcurrencyLimit(
      itemCount: initialSnapshot.length,
      maxConcurrency: _processGroupProbeConcurrency,
      shouldContinue: () => remainingPreparationTime() > Duration.zero,
      task: (index) async {
        final process = initialSnapshot[index];
        if (identical(_trackedProcessGroups[process.pid], process)) return;
        final remaining = remainingPreparationTime();
        if (remaining <= Duration.zero) return;
        final descendants = await _collectDescendantPids(
          process.pid,
          timeout: remaining,
        ).timeout(remaining, onTimeout: () => const <int>[]);
        if (descendants.isNotEmpty) {
          descendantPidsByProcess[process] = descendants;
        }
      },
    );
    preparationStopwatch.stop();

    Set<Process> signalAll(
      Iterable<Process> targets,
      ProcessSignal signal,
      String operation,
    ) {
      final deliveredGroups = HashSet<Process>.identity();
      for (final process in targets) {
        final isCurrentGroup = identical(
          _trackedProcessGroups[process.pid],
          process,
        );
        if (isCurrentGroup) {
          if (_sendSignalToProcessGroupDirect(process.pid, signal)) {
            deliveredGroups.add(process);
          }
        } else {
          _signalProcessIds(
            (descendantPidsByProcess[process] ?? const <int>[]).reversed,
            signal,
            where: signal == ProcessSignal.sigkill
                ? '强制终止已跟踪子进程后代'
                : '终止已跟踪子进程后代',
          );
        }
        if (!identical(_trackedChildren[process.pid], process)) continue;
        try {
          process.kill(signal);
        } catch (error, stack) {
          silentLog('safe_subprocess', operation, error, stack);
        }
      }
      return deliveredGroups;
    }

    Future<void> waitForExit(Iterable<Process> targets) async {
      try {
        await Future.wait<void>(
          targets.map((process) async {
            try {
              await process.exitCode;
            } catch (error, stack) {
              silentLog('safe_subprocess', '等待已跟踪子进程退出', error, stack);
            }
          }),
        ).timeout(_processTreeFinalWait);
      } on TimeoutException {
        // 强制信号已发出，不能让异常子进程继续阻塞应用退出。
      } catch (error, stack) {
        silentLog('safe_subprocess', '收尾等待已跟踪子进程退出', error, stack);
      }
    }

    _trackedChildrenCleanupPhase = _TrackedChildrenCleanupPhase.terminating;
    signalAll(collectCleanupTargets(), ProcessSignal.sigterm, '终止已跟踪子进程');
    _trackedChildrenCleanupPhase = _TrackedChildrenCleanupPhase.waitingForGrace;
    if (boundedGracefulTimeout > Duration.zero) {
      await Future<void>.delayed(boundedGracefulTimeout);
    }

    _trackedChildrenCleanupPhase = _TrackedChildrenCleanupPhase.forcing;
    final forceTargets = collectCleanupTargets();
    final forceKilledGroups = signalAll(
      forceTargets,
      ProcessSignal.sigkill,
      '强制终止已跟踪子进程',
    );
    await waitForExit(forceTargets);
    for (final process in forceKilledGroups) {
      if (identical(_trackedProcessGroups[process.pid], process)) {
        _trackedProcessGroups.remove(process.pid);
      }
    }
  } catch (error, stack) {
    silentLog('safe_subprocess', '清理已跟踪子进程', error, stack);
  } finally {
    _trackedChildrenRegisteredDuringCleanup.clear();
    _trackedChildrenCleanupPhase = _TrackedChildrenCleanupPhase.idle;
    _stopProcessGroupPrunerIfIdle();
  }
}

Duration _boundedSubprocessGracefulTimeout(Duration timeout) {
  if (timeout.isNegative) return Duration.zero;
  return timeout > _maxSubprocessGracefulTimeout
      ? _maxSubprocessGracefulTimeout
      : timeout;
}

Duration _boundedSubprocessExecutionTimeout(Duration timeout) {
  return shorterDuration(
    nonNegativeDuration(timeout),
    _maxSubprocessExecutionTimeout,
  );
}

/// 当前仍由应用跟踪的子进程 PID 快照。
List<int> trackedChildPidsSnapshot() => List<int>.unmodifiable(<int>{
  ..._trackedChildren.keys,
  ..._trackedProcessGroups.keys,
});

Future<_ProcessGroupLauncher?> _resolveProcessGroupLauncher() async {
  try {
    return await _processGroupLauncherCache.load();
  } catch (error, stack) {
    silentLog('safe_subprocess', '探测进程组启动器', error, stack);
    return null;
  }
}

Future<_ProcessGroupLauncher?> _probeProcessGroupLauncher() async {
  const candidates = <String>[
    '/usr/bin/setsid',
    '/usr/local/bin/setsid',
    '/opt/homebrew/bin/setsid',
  ];
  Object? probeError;
  StackTrace? probeStack;
  try {
    final directLauncher = await _firstExistingProcessExecutable(candidates);
    if (directLauncher != null) {
      return _ProcessGroupLauncher(directLauncher);
    }
    final result = await runTrackedProcessOrFailed(
      '/bin/sh',
      <String>['-lc', 'command -v setsid 2>/dev/null'],
      timeout: const Duration(seconds: 2),
      tag: 'safe_subprocess.setsid_probe',
      startInNewProcessGroup: false,
    );
    if (result.exitCode < 0) {
      throw StateError('setsid 命令路径探测未正常完成。');
    }
    final path = nullIfBlank(result.stdout as String);
    if (path != null && await _isProcessExecutableFile(path)) {
      return _ProcessGroupLauncher(path);
    }
  } catch (error, stack) {
    probeError = error;
    probeStack = stack;
  }

  // macOS 未内置 coreutils setsid，改用系统 Perl 调用同名系统接口，
  // 保留原始参数边界并确保可终止完整进程树。
  const perl = '/usr/bin/perl';
  if (Platform.isMacOS && await _isProcessExecutableFile(perl)) {
    return const _ProcessGroupLauncher(perl, <String>[
      '-MPOSIX',
      '-e',
      'defined POSIX::setsid() or die "setsid failed: \$!"; '
          'exec @ARGV; die "exec failed: \$!";',
      '--',
    ]);
  }
  if (probeError != null) {
    Error.throwWithStackTrace(probeError, probeStack ?? StackTrace.current);
  }
  return null;
}

bool _sendSignalToProcessGroupDirect(int processGroupId, ProcessSignal signal) {
  if (Platform.isWindows || processGroupId <= 0) return false;
  try {
    if (Process.killPid(-processGroupId, signal)) return true;
  } catch (error, stack) {
    silentLog('safe_subprocess', '向进程组发送信号', error, stack);
  }
  return false;
}

Future<bool> _sendSignalToProcessGroup(
  int processGroupId,
  ProcessSignal signal,
) async {
  if (_sendSignalToProcessGroupDirect(processGroupId, signal)) return true;
  final signalName = signal == ProcessSignal.sigkill ? 'KILL' : 'TERM';
  try {
    final result = await runBinaryProcessWithTimeout(
      '/bin/kill',
      <String>['-$signalName', '-$processGroupId'],
      timeout: _processGroupSignalFallbackTimeout,
      maxStdoutBytes: 0,
      maxStderrBytes: 8 * kBytesPerKiB,
      tag: 'safe_subprocess.kill_group',
      terminateProcessTreeOnFailure: false,
    );
    return result?.exitCode == 0;
  } catch (error, stack) {
    silentLog('safe_subprocess', '向进程组发送兼容信号', error, stack);
    return false;
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
      final result = await runBinaryProcessWithTimeout(
        'pgrep',
        <String>['-P', '$myPid'],
        timeout: _directChildEnumerationTimeout,
        maxStdoutBytes: 64 * kBytesPerKiB,
        maxStderrBytes: 8 * kBytesPerKiB,
        tag: 'safe_subprocess.pgrep_direct_children',
        terminateProcessTreeOnFailure: false,
      );
      if (result?.exitCode == 0) {
        killed += await _terminatePidSet(
          _parseChildPids(result?.stdout, parentPid: myPid),
          tag: '终止 Unix 直接子进程',
        );
      }
      // 第二遍补漏：pgrep 与逐个 kill 之间可能又 fork 出新的直接子进程。
      try {
        final termResult = await runBinaryProcessWithTimeout(
          'pkill',
          <String>['-TERM', '-P', '$myPid'],
          timeout: _directChildEnumerationTimeout,
          maxStdoutBytes: 0,
          maxStderrBytes: 8 * kBytesPerKiB,
          tag: 'safe_subprocess.pkill_term_children',
          terminateProcessTreeOnFailure: false,
        );
        if (termResult?.exitCode == 0) {
          await Future<void>.delayed(_directChildTerminateGrace);
          await runBinaryProcessWithTimeout(
            'pkill',
            <String>['-KILL', '-P', '$myPid'],
            timeout: _directChildEnumerationTimeout,
            maxStdoutBytes: 0,
            maxStderrBytes: 8 * kBytesPerKiB,
            tag: 'safe_subprocess.pkill_force_children',
            terminateProcessTreeOnFailure: false,
          );
          killed = killed + 1; // pkill 本身不报数，保守计 1。
        }
      } catch (error, stack) {
        silentLog('safe_subprocess', '执行 pkill -P 兜底', error, stack);
      }
    } else if (Platform.isWindows) {
      final result = await runBinaryProcessWithTimeout(
        'wmic',
        <String>[
          'process',
          'where',
          '(ParentProcessId=$myPid)',
          'get',
          'ProcessId',
        ],
        timeout: _directChildEnumerationTimeout,
        maxStdoutBytes: 64 * kBytesPerKiB,
        maxStderrBytes: 8 * kBytesPerKiB,
        tag: 'safe_subprocess.wmic_children',
        terminateProcessTreeOnFailure: false,
      );
      if (result?.exitCode == 0) {
        killed += await _terminatePidSet(
          _parseChildPids(result?.stdout, parentPid: myPid),
          tag: '终止 Windows 直接子进程',
        );
      }
    }
  } catch (error, stack) {
    silentLog('safe_subprocess', '枚举直接子进程', error, stack);
  }
  return killed;
}

Set<int> _parseChildPids(Object? stdout, {required int parentPid}) {
  final output = switch (stdout) {
    final List<int> bytes => _decodeProcessManagementOutput(bytes),
    _ => '$stdout',
  };
  return output
      .split(kInlineWhitespacePattern)
      .map(optionalIntFromValue)
      .whereType<int>()
      .where((childPid) => childPid > 0 && childPid != parentPid)
      .toSet();
}

String _decodeProcessManagementOutput(List<int> bytes) {
  try {
    return systemEncoding.decode(bytes);
  } catch (_) {
    return const Utf8Decoder(allowMalformed: true).convert(bytes);
  }
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

/// 在严格墙钟时限内执行外部命令，超时后终止子进程。
///
/// 不能只用 `Process.run(...).timeout(...)`：`Future.timeout` 只放弃 Dart 侧
/// Future，底层子进程仍会运行。macOS 的 `osascript` 还会继续向其他应用发送
/// Apple Event，可能破坏宿主输入法上下文，表现为弹窗 TextField 无法输入或粘贴，
/// 并伴随 `IMKCFRunLoopWakeUpReliable` 控制台错误。
///
/// stdout/stderr 持续排空，但最多保留 [maxStdoutBytes]/[maxStderrBytes]，避免高噪声
/// 进程或继承管道的后代无限增长内存。命令超时或启动失败时返回 null，非零退出码仍
/// 作为正常 [ProcessResult] 返回；异常仅通过调试态 [silentLog] 记录。
/// [stdinBytes] 写完后始终关闭 stdin，并共享同一墙钟时限。输出订阅安装完成后只
/// 调用一次 [onProcessStarted]，便于可取消调用方安全持有句柄。[onFailure] 在失败
/// 转换为 null 前观察启动或运行异常，回调异常与进程清理隔离。[outputDecoder]
/// 默认使用容错 UTF-8；旧系统工具可传入 [SystemEncoding.decoder]，无需重复采集。
///
/// 提供非空 [toolCallId] 时，会向 [AiToolExecutionRegistry] 登记子进程 pid 和
/// SIGTERM→SIGKILL 终止器，以支持单次工具调用停止；工具调用完整结束后由所属运行时
/// 移除登记。当前没有工具执行上下文时传 null，例如启动期 CLI 探测。
Future<ProcessResult?> runProcessWithTimeout(
  String executable,
  List<String> arguments, {
  List<int> stdinBytes = const <int>[],
  Duration timeout = const Duration(seconds: 4),
  Future<void>? cancelSignal,
  String tag = 'safe_subprocess',
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
  String? toolCallId,
  int? gracefulShutdownMs,
  int maxStdoutBytes = kBytesPerMiB,
  int maxStderrBytes = 256 * kBytesPerKiB,
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
  final effectiveGracefulMs = configuredGracefulMs
      .clamp(0, _maxSubprocessGracefulTimeout.inMilliseconds)
      .toInt();
  final effectiveTimeout = _boundedSubprocessExecutionTimeout(timeout);
  final processStartTimeout = shorterDuration(
    effectiveTimeout,
    _maxSubprocessStartTimeout,
  );
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
  final stdoutLimit = maxStdoutBytes
      .clamp(0, _maxCapturedProcessBytesPerStream)
      .toInt();
  final stderrLimit = maxStderrBytes
      .clamp(0, _maxCapturedProcessBytesPerStream)
      .toInt();
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
      silentLog(tag, '解码 $streamName $executable 输出', error, stack);
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
      // finally 会明确取消订阅，继承管道的后代无法在本次调用结束后继续堆积缓冲。
      return false;
    } catch (error, stack) {
      silentLog(tag, '等待 $executable 输出流', error, stack);
      return false;
    }
  }

  void observeLateLaunch(Future<_TrackedProcessLaunch> launchFuture) {
    unawaited(
      launchFuture.then<void>(
        (lateLaunch) async {
          try {
            await _terminateTrackedProcessTree(
              lateLaunch.process,
              gracefulTimeout: Duration(milliseconds: effectiveGracefulMs),
              knownProcessGroupLeader: lateLaunch.isProcessGroupLeader,
            );
          } catch (error, stack) {
            silentLog(tag, '终止延迟启动进程 $executable', error, stack);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!_isMissingExecutableProcessException(error)) {
            silentLog(tag, '延迟启动进程 $executable', error, stack);
          }
        },
      ),
    );
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
      final launched = await awaitWithCancelSignal(
        launchFuture,
        cancelSignal: cancelSignal,
      ).timeout(processStartTimeout);
      if (launched == null) {
        timedOut = true;
        observeLateLaunch(launchFuture);
        return timeoutResultBuilder?.call(-1, '', '');
      }
      launch = launched;
    } on TimeoutException {
      timedOut = true;
      observeLateLaunch(launchFuture);
      return timeoutResultBuilder?.call(-1, '', '');
    }
    process = launch.process;
    isProcessGroupLeader = launch.isProcessGroupLeader;
    if (await isCancelSignalCompleted(cancelSignal)) {
      timedOut = true;
      await _terminateTrackedProcessTree(
        process,
        gracefulTimeout: Duration(milliseconds: effectiveGracefulMs),
        knownProcessGroupLeader: isProcessGroupLeader,
      );
      return timeoutResultBuilder?.call(process.pid, '', '');
    }
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
        silentLog(tag, '读取 $executable 标准输出', error, stack);
        completeStream(stdoutDone);
      },
      onDone: () => completeStream(stdoutDone),
      cancelOnError: true,
    );
    stderrSubscription = process.stderr.listen(
      (chunk) => collectBounded(stderrBytes, chunk, stderrLimit),
      onError: (Object error, StackTrace stack) {
        silentLog(tag, '读取 $executable 标准错误', error, stack);
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
        silentLog(tag, '写入 $executable 标准输入', error, stack);
      } finally {
        try {
          await process!.stdin.close();
        } catch (error, stack) {
          silentLog(tag, '关闭 $executable 标准输入', error, stack);
        }
      }
    }

    final remainingTimeout = effectiveTimeout - executionStopwatch.elapsed;
    final exitFuture = (() async {
      await closeStdin();
      return process!.exitCode;
    })();
    final timeout = Completer<({int? exitCode, bool interrupted})>();
    final timeoutTimer = startSafeTimer(
      remainingTimeout > Duration.zero ? remainingTimeout : Duration.zero,
      () => timeout.complete((exitCode: null, interrupted: true)),
    );
    late final ({int? exitCode, bool interrupted}) exit;
    try {
      final waits = <Future<({int? exitCode, bool interrupted})>>[
        exitFuture.then((exitCode) => (exitCode: exitCode, interrupted: false)),
        timeout.future,
      ];
      if (cancelSignal != null) {
        waits.add(
          cancelSignal.then(
            (_) => (exitCode: null, interrupted: true),
            onError: (_, _) => (exitCode: null, interrupted: true),
          ),
        );
      }
      exit = await Future.any(waits);
    } finally {
      timeoutTimer.cancel();
    }
    if (exit.interrupted) {
      timedOut = true;
      await _terminateTrackedProcessTree(
        process,
        gracefulTimeout: Duration(milliseconds: effectiveGracefulMs),
        knownProcessGroupLeader: isProcessGroupLeader,
      );
    }
    final exitCode = exit.exitCode ?? -1;
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
      silentLog(tag, '执行 $executable 进程失败回调', callbackError, callbackStack);
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
        silentLog(tag, '取消 $streamName 流订阅', error, stack),
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
  Future<void>? cancelSignal,
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
    cancelSignal: cancelSignal,
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

// DWS Schema 目录可能包含数万行 JSON；仍以字符数上限控制内存，允许完整保留
// 大型结构化输出，避免按行截断后无法解析。
const int _maxCapturedProcessLinesPerStream = 64 * kBytesPerKiB;
const int _maxCapturedProcessCharactersPerStream = 4 * kBytesPerMiB;
const int _maxProcessLineCharacters = 64 * kBytesPerKiB;

class TrackedProcessLineLogResult {
  const TrackedProcessLineLogResult({
    required this.pid,
    required this.exitCode,
    required this.timedOut,
    required this.cancelled,
    required this.stdout,
    required this.stderr,
  });

  final int pid;
  final int exitCode;
  final bool timedOut;
  final bool cancelled;
  final String stdout;
  final String stderr;
}

class _BoundedProcessLineCapture {
  _BoundedProcessLineCapture({required int maxLines})
    : _buffer = maxLines < 1
          ? null
          : BoundedLogBuffer(
              maxLines: maxLines
                  .clamp(1, _maxCapturedProcessLinesPerStream)
                  .toInt(),
              maxCharacters: _maxCapturedProcessCharactersPerStream,
            );

  final BoundedLogBuffer? _buffer;

  void add(String line) => _buffer?.add(line);

  String get text => _buffer?.snapshot().join('\n') ?? '';
}

/// 增量解析进程文本流，并限制单行 UTF-16 代码单元，避免无换行输出无限增长。
/// [splitOnCarriageReturn] 用于解析以 `\r` 原地刷新的进度输出。
class BoundedProcessLineDecoder {
  BoundedProcessLineDecoder({
    required int maxCharacters,
    required this.onLine,
    this.splitOnCarriageReturn = false,
  }) : _maxCharacters = maxCharacters < 1 ? 1 : maxCharacters;

  final int _maxCharacters;
  final void Function(String line) onLine;
  final bool splitOnCarriageReturn;
  final StringBuffer _buffer = StringBuffer();
  bool _truncated = false;
  bool _skipLeadingLineFeed = false;

  void add(String chunk) {
    if (chunk.isEmpty) return;
    var start = 0;
    if (_skipLeadingLineFeed) {
      _skipLeadingLineFeed = false;
      if (chunk.startsWith('\n')) start = 1;
    }
    while (start < chunk.length) {
      var lineEnd = -1;
      if (splitOnCarriageReturn) {
        for (var index = start; index < chunk.length; index++) {
          final codeUnit = chunk.codeUnitAt(index);
          if (codeUnit == 0x0a || codeUnit == 0x0d) {
            lineEnd = index;
            break;
          }
        }
      } else {
        lineEnd = chunk.indexOf('\n', start);
      }
      if (lineEnd < 0) {
        _append(chunk.substring(start));
        return;
      }
      _append(chunk.substring(start, lineEnd));
      _emit();
      start = lineEnd + 1;
      if (splitOnCarriageReturn && chunk.codeUnitAt(lineEnd) == 0x0d) {
        if (start < chunk.length && chunk.codeUnitAt(start) == 0x0a) {
          start += 1;
        } else if (start == chunk.length) {
          _skipLeadingLineFeed = true;
        }
      }
    }
  }

  void close() {
    if (_buffer.isNotEmpty || _truncated) _emit();
  }

  void _append(String segment) {
    if (segment.isEmpty || _truncated) return;
    final remaining = _maxCharacters - _buffer.length;
    if (segment.length <= remaining) {
      _buffer.write(segment);
      return;
    }
    if (remaining > 0) {
      _buffer.write(clipTextByCodeUnits(segment, remaining, suffix: ''));
    }
    _truncated = true;
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

/// 启动受跟踪进程，按文本行转发 stdout/stderr，并在 [timeout] 到期时终止进程。
///
/// 用于需要实时日志的安装、更新流程，统一管理输出订阅、超时和清理。流读取异常只
/// 记录日志，启动和退出异常仍交给调用方。默认使用独立 POSIX 进程组，超时时会
/// 终止整棵进程树。[onProcessStarted] 在输出订阅完成后调用；
/// [processStartTimeout] 仅限制启动阶段，[timeout] 限制完整执行时长；
/// [cancelSignal] 完成时立即终止进程树并返回取消结果。
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
  Future<void>? cancelSignal,
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
  final effectiveMaxLineCharacters = maxLineCharacters
      .clamp(1, _maxProcessLineCharacters)
      .toInt();
  final effectiveTimeout = _boundedSubprocessExecutionTimeout(timeout);
  final configuredStartTimeout = processStartTimeout;
  final boundedStartTimeout = configuredStartTimeout == null
      ? _maxSubprocessStartTimeout
      : shorterDuration(
          nonNegativeDuration(configuredStartTimeout),
          _maxSubprocessStartTimeout,
        );
  final effectiveStartTimeout = shorterDuration(
    boundedStartTimeout,
    effectiveTimeout,
  );
  final effectiveDrainTimeout = shorterDuration(
    nonNegativeDuration(streamDrainTimeout),
    _maxSubprocessStreamDrainTimeout,
  );
  final executionStopwatch = Stopwatch()..start();
  var timedOut = false;
  var cancelled = false;
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
      silentLog(tag, '执行 $executable 超时处理器', error, stack);
    }
  }

  void complete(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  void terminateLateLaunch(Future<Process> launchFuture) {
    unawaited(
      launchFuture.then<void>(
        (lateProcess) async {
          try {
            await terminateTrackedProcessTree(
              lateProcess,
              gracefulTimeout: gracefulTerminationTimeout,
            );
          } catch (error, stack) {
            silentLog(tag, '终止延迟启动进程 $executable', error, stack);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!_isMissingExecutableProcessException(error)) {
            silentLog(tag, '延迟启动进程 $executable', error, stack);
          }
        },
      ),
    );
  }

  void handleLine(
    ProcessLogLineHandler? handler,
    _BoundedProcessLineCapture capture,
    String line,
  ) {
    if (nullIfBlank(line) == null) return;
    final boundedLine = clipTextWithEllipsis(line, effectiveMaxLineCharacters);
    capture.add(boundedLine);
    if (handler == null) return;
    try {
      handler(boundedLine);
    } catch (error, stack) {
      silentLog(tag, '执行 $executable 行处理器', error, stack);
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
    late final BoundedProcessLineDecoder decoder;
    decoder = BoundedProcessLineDecoder(
      maxCharacters: effectiveMaxLineCharacters,
      onLine: (line) =>
          handleLine(handler, capture, trimLine ? line.trim() : line),
    );
    return stream
        .transform(const SystemEncoding().decoder)
        .listen(
          decoder.add,
          onError: (Object error, StackTrace stack) {
            silentLog(tag, '读取 $executable $streamName', error, stack);
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
    } on TimeoutException catch (e, stack) {
      silentLog(
        tag,
        '输出流排空超时',
        '$executable ${arguments.take(1).join(' ')}',
        stack,
      );
      return false;
    } catch (error, stack) {
      silentLog(tag, '等待 $executable 输出流', error, stack);
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
      process = await awaitWithCancelSignal(
        launchFuture,
        cancelSignal: cancelSignal,
      ).timeout(effectiveStartTimeout);
      if (process == null) {
        cancelled = true;
        terminateLateLaunch(launchFuture);
        return TrackedProcessLineLogResult(
          pid: -1,
          exitCode: -1,
          timedOut: false,
          cancelled: true,
          stdout: stdoutCapture.text,
          stderr: stderrCapture.text,
        );
      }
    } on TimeoutException {
      timedOut = true;
      notifyTimeout();
      terminateLateLaunch(launchFuture);
      return TrackedProcessLineLogResult(
        pid: -1,
        exitCode: -1,
        timedOut: true,
        cancelled: false,
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
    final exitFuture = () async {
      try {
        await process!.stdin.close();
      } catch (error, stack) {
        silentLog(tag, '关闭 $executable 标准输入', error, stack);
      }
      return process!.exitCode;
    }();
    final completedExitCode =
        await awaitWithCancelSignal(
          exitFuture,
          cancelSignal: cancelSignal,
        ).timeout(
          remainingTimeout > Duration.zero ? remainingTimeout : Duration.zero,
          onTimeout: () {
            timedOut = true;
            notifyTimeout();
            return null;
          },
        );
    if (completedExitCode == null) {
      cancelled = !timedOut;
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: gracefulTerminationTimeout,
      );
    }
    final exitCode = completedExitCode ?? -1;
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
      cancelled: cancelled,
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

/// 运行短生命周期二进制命令，限制输入输出与总执行时间。
///
/// 默认不新建进程组，避免内部探针形成额外资源循环；确有子孙进程时可显式
/// 启用 [startInNewProcessGroup]，超时和输出流异常都会回收完整进程树。
/// [terminateProcessTreeOnFailure] 仅用于终止工具自身，默认保持完整回收。
Future<ProcessResult?> runBinaryProcessWithTimeout(
  String executable,
  List<String> arguments, {
  List<int> stdinBytes = const <int>[],
  Duration timeout = const Duration(seconds: 4),
  int maxStdoutBytes = kBytesPerMiB,
  int maxStderrBytes = 64 * kBytesPerKiB,
  String tag = 'safe_subprocess.binary',
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
  bool startInNewProcessGroup = false,
  bool terminateProcessTreeOnFailure = true,
}) async {
  final effectiveTimeout = _boundedSubprocessExecutionTimeout(timeout);
  final processStartTimeout = shorterDuration(
    effectiveTimeout,
    _maxSubprocessStartTimeout,
  );
  final stopwatch = Stopwatch()..start();
  Process? process;
  var isProcessGroupLeader = false;
  StreamSubscription<List<int>>? stdoutSub;
  StreamSubscription<List<int>>? stderrSub;
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  final stdoutBytes = BytesBuilder(copy: false);
  final stderrBytes = BytesBuilder(copy: false);
  final stdoutLimit = maxStdoutBytes
      .clamp(0, _maxCapturedProcessBytesPerStream)
      .toInt();
  final stderrLimit = maxStderrBytes
      .clamp(0, _maxCapturedProcessBytesPerStream)
      .toInt();

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

  Duration remainingTimeout() {
    final remainingMicroseconds =
        effectiveTimeout.inMicroseconds - stopwatch.elapsedMicroseconds;
    if (remainingMicroseconds <= 0) return Duration.zero;
    return Duration(microseconds: remainingMicroseconds);
  }

  Future<bool> waitForStreams() async {
    try {
      await Future.wait<void>(<Future<void>>[
        stdoutDone.future,
        stderrDone.future,
      ]).timeout(_processStreamCleanupTimeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (error, stack) {
      silentLog(tag, '等待二进制子进程输出流', error, stack);
      return false;
    }
  }

  Future<void> terminateProcess() async {
    final target = process;
    if (target == null) return;
    if (!terminateProcessTreeOnFailure) {
      await _terminateBinaryProcessDirectly(target, tag: tag);
      return;
    }
    await _terminateTrackedProcessTree(
      target,
      gracefulTimeout: Duration.zero,
      knownProcessGroupLeader: isProcessGroupLeader,
    );
  }

  try {
    final launchFuture = startInNewProcessGroup
        ? _startTrackedProcessInNewGroup(
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
          ).then(
            (started) => _TrackedProcessLaunch(
              process: started,
              isProcessGroupLeader: false,
            ),
          );
    try {
      final launch = await launchFuture.timeout(
        shorterDuration(remainingTimeout(), processStartTimeout),
      );
      process = launch.process;
      isProcessGroupLeader = launch.isProcessGroupLeader;
    } on TimeoutException {
      _terminateLateBinaryProcess(
        launchFuture,
        tag: tag,
        terminateProcessTree: terminateProcessTreeOnFailure,
      );
      return null;
    }
    stdoutSub = process.stdout.listen(
      (chunk) => collectLimited(stdoutBytes, chunk, stdoutLimit),
      onError: (_) => completeIfNeeded(stdoutDone),
      onDone: () => completeIfNeeded(stdoutDone),
      cancelOnError: true,
    );
    stderrSub = process.stderr.listen(
      (chunk) => collectLimited(stderrBytes, chunk, stderrLimit),
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
          remainingTimeout(),
          onTimeout: () async {
            await terminateProcess();
            return -1;
          },
        );
    if (!await waitForStreams()) {
      await terminateProcess();
    }
    if (exitCode == -1) return null;
    return ProcessResult(
      process.pid,
      exitCode,
      stdoutBytes.takeBytes(),
      stderrBytes.takeBytes(),
    );
  } catch (error, stack) {
    await terminateProcess();
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
    stopwatch.stop();
    await Future.wait<void>(<Future<void>>[
      _cancelProcessSubscription(stdoutSub, tag, 'stdout'),
      _cancelProcessSubscription(stderrSub, tag, 'stderr'),
    ]);
  }
}

Future<void> _terminateBinaryProcessDirectly(
  Process process, {
  required String tag,
}) async {
  try {
    process.kill();
  } catch (error, stack) {
    silentLog(tag, '直接终止二进制子进程', error, stack);
  }
  try {
    await process.exitCode.timeout(_processTreeFinalWait);
    return;
  } on TimeoutException {
    // 继续强制终止，避免内部任务自身再次进入树终止流程。
  } catch (error, stack) {
    silentLog(tag, '等待二进制子进程退出', error, stack);
    return;
  }
  try {
    process.kill(ProcessSignal.sigkill);
  } catch (error, stack) {
    silentLog(tag, '强制终止二进制子进程', error, stack);
  }
  try {
    await process.exitCode.timeout(_processTreeFinalWait);
  } catch (error, stack) {
    silentLog(tag, '等待强制终止后的子进程退出', error, stack);
  }
}

void _terminateLateBinaryProcess(
  Future<_TrackedProcessLaunch> launchFuture, {
  required String tag,
  required bool terminateProcessTree,
}) {
  unawaited(
    launchFuture.then<void>(
      (lateLaunch) async {
        final lateProcess = lateLaunch.process;
        StreamSubscription<List<int>>? stdoutSub;
        StreamSubscription<List<int>>? stderrSub;
        try {
          stdoutSub = lateProcess.stdout.listen(
            (_) {},
            onError: (Object _, StackTrace _) {},
            cancelOnError: true,
          );
          stderrSub = lateProcess.stderr.listen(
            (_) {},
            onError: (Object _, StackTrace _) {},
            cancelOnError: true,
          );
          unawaited(
            lateProcess.stdin.close().catchError((Object _, StackTrace _) {}),
          );
          if (terminateProcessTree) {
            await _terminateTrackedProcessTree(
              lateProcess,
              gracefulTimeout: Duration.zero,
              knownProcessGroupLeader: lateLaunch.isProcessGroupLeader,
            );
          } else {
            await _terminateBinaryProcessDirectly(lateProcess, tag: tag);
          }
        } catch (error, stack) {
          if (!_isMissingExecutableProcessException(error)) {
            silentLog(tag, '终止延迟启动的二进制子进程', error, stack);
          }
        } finally {
          await Future.wait<void>(<Future<void>>[
            _cancelProcessSubscription(stdoutSub, tag, 'late binary stdout'),
            _cancelProcessSubscription(stderrSub, tag, 'late binary stderr'),
          ]);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_isMissingExecutableProcessException(error)) {
          silentLog(tag, '延迟启动二进制子进程', error, stack);
        }
      },
    ),
  );
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
///   1) 使用普通子进程启动，spawn 完立即返回，宿主事件循环不被挂；
///   2) 异步观察 `exitCode` 并在看门狗超时后通过 [Process] 句柄终止；
///      禁止延迟按裸 PID 发送信号，避免启动器退出后的 PID 复用误杀；
///
/// 返回 true 表示 spawn 成功，false 表示 launcher 二进制不可用（不抛）。
Future<bool> runDetachedSystemOpen(
  String executable,
  List<String> arguments, {
  String tag = 'safe_subprocess.open',
  Duration watchdog = const Duration(seconds: 1),
  bool runInShell = false,
}) async {
  try {
    final process = await startTrackedProcessBounded(
      executable,
      arguments,
      timeout: _systemOpenProcessStartTimeout,
      tag: tag,
      runInShell: runInShell,
    );
    _watchSystemOpenLauncher(process, watchdog: watchdog, tag: tag);
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

void _watchSystemOpenLauncher(
  Process process, {
  required Duration watchdog,
  required String tag,
}) {
  var exited = false;
  Timer? watchdogTimer;
  final stdoutSub = process.stdout.listen(
    (_) {},
    onError: (Object error, StackTrace stack) =>
        silentLog(tag, '读取系统打开器标准输出', error, stack),
  );
  final stderrSub = process.stderr.listen(
    (_) {},
    onError: (Object error, StackTrace stack) =>
        silentLog(tag, '读取系统打开器标准错误', error, stack),
  );
  unawaited(
    process.stdin.close().catchError((Object error, StackTrace stack) {
      silentLog(tag, '关闭系统打开器标准输入', error, stack);
    }),
  );
  unawaited(
    process.exitCode.then<void>(
      (_) async {
        exited = true;
        watchdogTimer?.cancel();
        await Future.wait<void>(<Future<void>>[
          _cancelProcessSubscription(stdoutSub, tag, '系统打开器标准输出'),
          _cancelProcessSubscription(stderrSub, tag, '系统打开器标准错误'),
        ]);
      },
      onError: (Object error, StackTrace stack) async {
        exited = true;
        watchdogTimer?.cancel();
        silentLog(tag, '监听系统打开器退出', error, stack);
        await Future.wait<void>(<Future<void>>[
          _cancelProcessSubscription(stdoutSub, tag, '系统打开器标准输出'),
          _cancelProcessSubscription(stderrSub, tag, '系统打开器标准错误'),
        ]);
      },
    ),
  );
  watchdogTimer = startSafeTimer(watchdog, () async {
    if (exited) return;
    try {
      process.kill();
      await process.exitCode.timeout(const Duration(milliseconds: 300));
    } on TimeoutException {
      if (exited) return;
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (error, stack) {
        silentLog(tag, '强制终止系统打开器', error, stack);
      }
    } catch (error, stack) {
      // 进程可能恰好退出，记录后交给 exitCode 监听完成资源回收。
      silentLog(tag, '终止超时系统打开器', error, stack);
    }
  });
}

/// 使用系统默认应用打开本地文件或目录。
///
/// UI 操作优先使用此高层封装。它拒绝类似 URI 的字符串和横线开头参数，避免本地路径
/// 打开操作意外升级为 URL 启动或命令选项。
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

/// 使用用户的系统默认浏览器打开 HTTP(S) URL。
///
/// 仅接受带主机的绝对 `http` / `https` URL；拒绝用户信息和空白字符，防止 UI 文本
/// 被解释为启动器参数或意外携带凭据的 URL。
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

/// 使用系统默认应用打开受约束的外部 URI。
///
/// 仅接受 http(s)、file 和 mailto。文件统一经 [openLocalPathWithSystemApp]
/// 执行路径安全检查；HTTP(S) URL 复用 [openHttpUrlWithSystemBrowser]。
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
      return await openLocalPathWithSystemApp(uri.toFilePath(), tag: tag);
    } catch (error, stack) {
      silentLog('safe_subprocess', '打开文件 URI', error, stack);
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

/// 在系统文件管理器中显示本地文件或目录。
///
/// macOS 和 Windows 在支持时选中目标。Linux 文件管理器没有统一可移植的“选择文件”
/// 协议，因此目录直接打开，文件则打开其所在目录。
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
    final type = await probeFileSystemEntityType(target);
    if (type == FileSystemEntityType.directory) {
      return runDetachedSystemOpen('explorer.exe', <String>[target], tag: tag);
    }
    return runDetachedSystemOpen('explorer.exe', <String>[
      '/select,$target',
    ], tag: tag);
  }
  if (Platform.isLinux) {
    return runDetachedSystemOpen('xdg-open', <String>[
      await _directoryForReveal(target),
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

Future<String> _directoryForReveal(String target) async {
  final type = await probeFileSystemEntityType(target);
  if (type == FileSystemEntityType.directory) return target;
  return File(target).parent.path;
}

Future<String?> _firstExistingProcessExecutable(
  Iterable<String> candidates,
) async {
  for (final candidate in candidates) {
    if (await _isProcessExecutableFile(candidate)) return candidate;
  }
  return null;
}

Future<bool> _isProcessExecutableFile(String path) {
  return isRegularFilePath(
    path,
    timeout: _processExecutableProbeTimeout,
    followLinks: true,
  );
}

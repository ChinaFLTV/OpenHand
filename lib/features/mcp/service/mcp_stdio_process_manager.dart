import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../mcp_errors.dart';
import '../model/mcp_server.dart';
import 'mcp_stdio_cache.dart';
import 'mcp_stdio_io_utils.dart';
import 'mcp_stdio_launch_resolver.dart';
import 'mcp_tool_discovery_exception.dart';

const int _jsonRpcMalformedLinePreviewChars = 200;
const int _jsonRpcCompactLinePreviewChars = 120;
const int _jsonRpcToolDescriptionPreviewChars = 60;
const int _stopAllConcurrency = 8;
const int _shutdownStopAllConcurrency = 16;
final Stopwatch _mcpStdioProcessStopwatch = Stopwatch()..start();

Map<String, Object?>? _parseMcpStdioJsonRpcLine(String line) {
  final trimmed = nullIfBlank(line);
  if (trimmed == null || !trimmed.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    return stringKeyedMapFromValue(decoded);
  } catch (_) {
    return null;
  }
}

/// STDIO MCP 服务进程的运行状态。
enum StdioProcessState { stopped, starting, running, stopping }

/// 单个 STDIO MCP 服务进程的运行时信息快照。
class StdioProcessInfo {
  const StdioProcessInfo({
    this.state = StdioProcessState.stopped,
    this.pid,
    this.startedAt,
    this._startedAtElapsed,
    this.memoryBytes,
    this.logs = const <String>[],
    this.errorMessage,
  });

  final StdioProcessState state;
  final int? pid;
  final DateTime? startedAt;
  final Duration? _startedAtElapsed;
  final int? memoryBytes;
  final List<String> logs;
  final String? errorMessage;

  bool get isRunning => state == StdioProcessState.running;
  bool get isStopped => state == StdioProcessState.stopped;
  bool get isTransitioning =>
      state == StdioProcessState.starting ||
      state == StdioProcessState.stopping;

  Duration? get uptime {
    if (startedAt == null || !isRunning) return null;
    final startedAtElapsed = _startedAtElapsed;
    if (startedAtElapsed != null) {
      return _mcpStdioProcessStopwatch.elapsed - startedAtElapsed;
    }
    final elapsed = DateTime.now().toUtc().difference(startedAt!);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  StdioProcessInfo copyWith({
    StdioProcessState? state,
    int? pid,
    bool clearPid = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
    int? memoryBytes,
    bool clearMemoryBytes = false,
    List<String>? logs,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return StdioProcessInfo(
      state: state ?? this.state,
      pid: clearPid ? null : pid ?? this.pid,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      startedAtElapsed: clearStartedAt ? null : _startedAtElapsed,
      memoryBytes: clearMemoryBytes ? null : memoryBytes ?? this.memoryBytes,
      logs: logs ?? this.logs,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

/// 管理 STDIO 类型 MCP 服务的进程生命周期。
///
/// 每个 STDIO MCP 服务可以独立启动/停止，进程日志实时收集，
/// 应用退出时自动终止所有子进程。
class McpStdioProcessManager extends ChangeNotifier {
  McpStdioProcessManager._()
    : _stdinCloseTimeout = _defaultStdinCloseTimeout,
      _gracefulStopTimeout = _defaultGracefulStopTimeout,
      _forceStopTimeout = _defaultForceStopTimeout,
      _processStartTimeout = _defaultProcessStartTimeout,
      _subscriptionCancelTimeout = _defaultSubscriptionCancelTimeout,
      _initializeStartupDelay = _defaultInitializeStartupDelay,
      _initializeResponseTimeout = _defaultInitializeResponseTimeout,
      _responseBufferLimit = _defaultResponseBufferLimit;

  static final McpStdioProcessManager instance = McpStdioProcessManager._();

  static const int _maxLogLines = 2000;
  static const Duration _defaultStdinCloseTimeout = Duration(milliseconds: 400);
  static const Duration _defaultGracefulStopTimeout = Duration(seconds: 3);
  static const Duration _defaultForceStopTimeout = Duration(seconds: 2);
  static const Duration _defaultProcessStartTimeout = Duration(seconds: 10);
  static const Duration _defaultSubscriptionCancelTimeout = Duration(
    milliseconds: 500,
  );
  static const Duration _defaultInitializeStartupDelay = Duration(seconds: 2);
  static const Duration _defaultInitializeResponseTimeout = Duration(
    seconds: 90,
  );
  static const Duration _borrowReleaseTimeout = Duration(seconds: 2);
  static const Duration _handshakePollInterval = Duration(milliseconds: 200);
  static const Duration _borrowPollInterval = Duration(milliseconds: 80);
  static const Duration _shutdownGracefulStopTimeout = Duration(
    milliseconds: 250,
  );
  static const int _defaultResponseBufferLimit = kBytesPerMiB;
  static const int _maxLogLineChars = 4 * kBytesPerKiB;
  static const int _maxManagedProcesses = 64;
  static const int _maxRuntimeCacheScanEntries = 20000;
  static const Duration _runtimeCacheScanTimeout = Duration(seconds: 5);
  static const Duration _runtimeCacheStatTimeout = Duration(milliseconds: 500);

  final Map<String, _ManagedProcess> _processes = {};
  final Map<String, Future<void>> _stopFutures = <String, Future<void>>{};
  final Set<String> _immediateStopRequests = <String>{};
  bool _isShuttingDown = false;
  bool _isDisposed = false;
  final Duration _stdinCloseTimeout;
  final Duration _gracefulStopTimeout;
  final Duration _forceStopTimeout;
  final Duration _processStartTimeout;
  final Duration _subscriptionCancelTimeout;
  final Duration _initializeStartupDelay;
  final Duration _initializeResponseTimeout;
  final int _responseBufferLimit;
  int _nextGeneration = 1;

  /// 获取指定服务的进程信息。
  StdioProcessInfo infoFor(String serverName) {
    return _processes[serverName]?.info ?? const StdioProcessInfo();
  }

  /// 启动指定 STDIO MCP 服务进程。
  Future<void> startServer(McpServer server) async {
    if (_isDisposed || _isShuttingDown || server.type != McpServerType.stdio) {
      return;
    }
    final name = server.name;
    final fingerprint = _serverFingerprint(server);

    final existing = _processes[name];
    if (existing != null && !existing.info.isStopped) {
      if (existing.configFingerprint == fingerprint) return;
      await stopServer(name);
    }
    final managedProcessCount = _processes.values
        .where((managed) => !managed.info.isStopped || managed.process != null)
        .length;
    if (managedProcessCount >= _maxManagedProcesses) {
      throw StateError('MCP stdio 托管进程已达到上限 $_maxManagedProcesses。');
    }

    final generation = _nextGeneration++;
    _processes[name] = _ManagedProcess(
      generation: generation,
      configFingerprint: fingerprint,
      info: const StdioProcessInfo(state: StdioProcessState.starting),
    );
    notifyListeners();

    Process? process;
    StreamSubscription<String>? stdoutSubscription;
    StreamSubscription<String>? stderrSubscription;
    try {
      // 解析实际的可执行文件和参数。对于 npx 命令，尝试直接定位已安装包的
      // 入口脚本并用 node 执行，避免 npx 的启动开销和标准输入转发问题。
      final launch = await resolveMcpStdioLaunch(server);
      if (!_isCurrentStart(name, generation)) {
        return;
      }
      // npx -y / uvx 等首次拉包 + 后续 MCP 服务运行期出站都依赖同一套
      // 代理环境。把 SystemProxyResolver 解析出的 HTTP(S)/SOCKS 端点注
      // 入子进程，否则在企业代理 / 内网透明代理环境下会 TCP 握手超时。
      process = await startTrackedProcessBounded(
        launch.executable,
        launch.args,
        timeout: _processStartTimeout,
        tag: 'mcp_stdio_process_manager',
        startInNewProcessGroup: true,
        environment: <String, String>{
          ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
          ...launch.environment,
          ...server.environment,
        },
        runInShell: launch.runInShell,
      );
      if (!_isCurrentStart(name, generation)) {
        unawaited(_terminateUnmanagedProcess(process));
        return;
      }

      final logs = <String>[];
      logs.add('[${_timestamp()}] 进程已启动 (PID: ${process.pid})');
      logs.add(
        '[${_timestamp()}] 命令: ${launch.executable} ${launch.args.join(' ')}',
      );
      logs.add('');

      final responseRouter = _ManagedResponseRouter(
        maxBufferedChars: _responseBufferLimit,
      );
      final managed = _ManagedProcess(
        generation: generation,
        configFingerprint: fingerprint,
        info: StdioProcessInfo(
          state: StdioProcessState.running,
          pid: process.pid,
          startedAt: DateTime.now().toUtc(),
          startedAtElapsed: _mcpStdioProcessStopwatch.elapsed,
          logs: List.unmodifiable(logs),
        ),
        process: process,
        responseRouter: responseRouter,
      );
      _processes[name] = managed;

      // 监听标准输出，同时用于日志、握手响应检测和工具发现响应路由。
      stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .listen(
            (data) {
              // 优先尝试路由到工具发现会话的待处理请求。
              final routerWasClosed = responseRouter.isClosed;
              responseRouter.tryRoute(data);
              _appendLog(
                name,
                data,
                isStderr: false,
                expectedGeneration: generation,
              );
              if (!routerWasClosed && responseRouter.isClosed) {
                unawaited(_terminateProcessTreeBounded(process!));
                return;
              }
            },
            onError: (Object error, StackTrace stack) {
              responseRouter.rejectNewWrites(error, stack);
              silentLog('mcp_stdio_process_manager', '监听标准输出', error, stack);
              _appendLog(
                name,
                '[标准输出异常] ${mcpFailureMessage(error, fallback: '标准输出监听失败。')}',
                isStderr: true,
                expectedGeneration: generation,
              );
              unawaited(_terminateProcessTreeBounded(process!));
            },
            onDone: () {
              responseRouter.rejectNewWrites(StateError('标准输出已关闭。'));
              _appendLog(
                name,
                '[标准输出已关闭]',
                isStderr: false,
                expectedGeneration: generation,
              );
              unawaited(_terminateProcessTreeBounded(process!));
            },
            cancelOnError: true,
          );

      // 监听标准错误。
      stderrSubscription = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            (data) => _appendLog(
              name,
              data,
              isStderr: true,
              expectedGeneration: generation,
            ),
            onError: (Object error, StackTrace stack) {
              silentLog('mcp_stdio_process_manager', '监听标准错误', error, stack);
              _appendLog(
                name,
                '[标准错误异常] ${mcpFailureMessage(error, fallback: '标准错误监听失败。')}',
                isStderr: true,
                expectedGeneration: generation,
              );
            },
            onDone: () => _appendLog(
              name,
              '[标准错误已关闭]',
              isStderr: false,
              expectedGeneration: generation,
            ),
          );

      // 持有订阅句柄，停止进程时显式取消，避免管道未及时关闭时泄漏监听器。
      final current = _processes[name];
      if (current == null ||
          current.generation != generation ||
          !identical(current.process, process) ||
          !current.info.isRunning) {
        await _terminateUnmanagedProcess(
          process,
          stdoutSubscription: stdoutSubscription,
          stderrSubscription: stderrSubscription,
        );
        return;
      }
      _processes[name] = managed.copyWith(
        stdoutSubscription: stdoutSubscription,
        stderrSubscription: stderrSubscription,
      );
      notifyListeners();

      // 监听进程退出
      void handleProcessExit({int? code, Object? error, StackTrace? stack}) {
        final exitError = error ?? StateError('进程已退出，退出码：$code。');
        if (error != null) {
          silentLog('mcp_stdio_process_manager', '监听进程退出', error, stack);
        }
        _appendLog(
          name,
          error == null
              ? '\n[${_timestamp()}] 进程已退出（退出码：$code）'
              : '\n[${_timestamp()}] 进程退出监听异常：${mcpFailureMessage(error, fallback: '进程退出监听失败。')}',
          isStderr: error != null,
          expectedGeneration: generation,
        );
        responseRouter.rejectNewWrites(exitError, stack);
        unawaited(
          Future.wait<void>(<Future<void>>[
            _cancelSubscriptionBounded(
              stdoutSubscription,
              '取消已退出进程 $name 的标准输出订阅',
            ),
            _cancelSubscriptionBounded(
              stderrSubscription,
              '取消已退出进程 $name 的标准错误订阅',
            ),
          ]),
        );
        final current = _processes[name];
        if (current != null &&
            current.generation == generation &&
            identical(current.process, process)) {
          if (error != null ||
              current.info.state != StdioProcessState.stopping) {
            unawaited(_terminateProcessTreeBounded(process!));
          }
          _processes[name] = _ManagedProcess(
            generation: generation,
            configFingerprint: current.configFingerprint,
            info: current.info.copyWith(
              state: StdioProcessState.stopped,
              clearPid: true,
            ),
          );
          notifyListeners();
        }
      }

      unawaited(
        process.exitCode
            .then<void>(
              (code) => handleProcessExit(code: code),
              onError: (Object error, StackTrace stack) =>
                  handleProcessExit(error: error, stack: stack),
            )
            .catchError((Object error, StackTrace stack) {
              silentLog('mcp_stdio_process_manager', '处理进程退出回调', error, stack);
            }),
      );

      // 启动后自动执行 MCP 协议握手
      unawaited(
        _initializeMcpProtocol(name, generation, process, responseRouter),
      );
    } catch (error, stack) {
      silentLog('mcp_stdio_process_manager', '启动 MCP stdio 进程', error, stack);
      final message = mcpFailureMessage(
        error,
        fallback: 'MCP stdio 进程启动失败，请稍后重试。',
      );
      if (process != null) {
        await _terminateUnmanagedProcess(
          process,
          stdoutSubscription: stdoutSubscription,
          stderrSubscription: stderrSubscription,
        );
      }
      final current = _processes[name];
      if (current != null &&
          current.generation == generation &&
          (current.info.state == StdioProcessState.starting ||
              identical(current.process, process))) {
        _processes[name] = _ManagedProcess(
          generation: generation,
          configFingerprint: fingerprint,
          info: StdioProcessInfo(
            errorMessage: message,
            logs: ['[${_timestamp()}] 启动失败：$message'],
          ),
        );
        notifyListeners();
      }
    }
  }

  bool _isCurrentStart(String serverName, int generation) {
    final current = _processes[serverName];
    return current != null &&
        current.generation == generation &&
        current.info.state == StdioProcessState.starting;
  }

  Future<void> _terminateUnmanagedProcess(
    Process process, {
    StreamSubscription<String>? stdoutSubscription,
    StreamSubscription<String>? stderrSubscription,
  }) async {
    StreamSubscription<List<int>>? rawStdoutSubscription;
    StreamSubscription<List<int>>? rawStderrSubscription;
    if (stdoutSubscription == null) {
      try {
        rawStdoutSubscription = process.stdout.listen(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
      } catch (error, stack) {
        silentLog('mcp_stdio_process_manager', '接管未托管进程标准输出', error, stack);
      }
    }
    if (stderrSubscription == null) {
      try {
        rawStderrSubscription = process.stderr.listen(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
      } catch (error, stack) {
        silentLog('mcp_stdio_process_manager', '接管未托管进程标准错误', error, stack);
      }
    }

    try {
      await Future.wait<void>(<Future<void>>[
        closeMcpStdioSinkQuietly(
          stdin: process.stdin,
          timeout: _stdinCloseTimeout,
          logTag: 'mcp_stdio_process_manager',
          logWhere: '关闭未托管进程标准输入',
        ),
        _terminateProcessTreeBounded(process),
      ]);
    } catch (error, stack) {
      silentLog('mcp_stdio_process_manager', '清理未托管进程', error, stack);
    }
    await Future.wait<void>(<Future<void>>[
      _cancelSubscriptionBounded(stdoutSubscription, '取消未托管进程标准输出订阅'),
      _cancelSubscriptionBounded(stderrSubscription, '取消未托管进程标准错误订阅'),
      _cancelSubscriptionBounded(rawStdoutSubscription, '取消未托管进程原始标准输出订阅'),
      _cancelSubscriptionBounded(rawStderrSubscription, '取消未托管进程原始标准错误订阅'),
    ]);
  }

  Future<void> _terminateProcessTreeBounded(
    Process process, {
    Duration? gracefulTimeout,
  }) async {
    // 先终止直接进程；后代枚举虽有时限，但繁忙主机仍可能稍有延迟。
    try {
      process.kill();
    } catch (error, stack) {
      silentLog('mcp_stdio_process_manager', '清理进程树前发送终止信号', error, stack);
    }
    final effectiveGracefulTimeout = gracefulTimeout ?? _gracefulStopTimeout;
    final totalTimeout = Duration(
      microseconds:
          effectiveGracefulTimeout.inMicroseconds +
          _forceStopTimeout.inMicroseconds +
          const Duration(seconds: 3).inMicroseconds,
    );
    try {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: effectiveGracefulTimeout,
      ).timeout(totalTimeout);
    } on TimeoutException catch (error, stack) {
      silentLog('mcp_stdio_process_manager', '终止进程树超时', error, stack);
    } catch (error, stack) {
      silentLog('mcp_stdio_process_manager', '终止进程树', error, stack);
    }
  }

  Future<void> _cancelSubscriptionBounded<T>(
    StreamSubscription<T>? subscription,
    String where,
  ) async {
    await cancelStreamSubscriptionBounded<T>(
      subscription,
      timeout: _subscriptionCancelTimeout,
      onError: (error, stack) =>
          silentLog('mcp_stdio_process_manager', where, error, stack),
    );
  }

  /// 停止指定 STDIO MCP 服务进程。
  Future<void> stopServer(String serverName) {
    return _stopServerSingleFlight(serverName);
  }

  Future<void> _stopServerSingleFlight(
    String serverName, {
    bool immediate = false,
  }) {
    if (immediate) {
      _immediateStopRequests.add(serverName);
    }
    final active = _stopFutures[serverName];
    if (active != null) return active;
    late final Future<void> future;
    future = _stopServer(serverName).whenComplete(() {
      if (identical(_stopFutures[serverName], future)) {
        _stopFutures.remove(serverName);
        _immediateStopRequests.remove(serverName);
      }
    });
    _stopFutures[serverName] = future;
    return future;
  }

  Future<void> _stopServer(String serverName) async {
    final managed = _processes[serverName];
    if (managed == null) return;
    if (managed.info.state == StdioProcessState.stopping) return;
    if (managed.process == null) {
      if (managed.info.state == StdioProcessState.starting) {
        _processes[serverName] = _ManagedProcess(
          generation: managed.generation,
          configFingerprint: managed.configFingerprint,
          info: managed.info.copyWith(state: StdioProcessState.stopped),
        );
        notifyListeners();
      }
      return;
    }
    final generation = managed.generation;

    _processes[serverName] = managed.copyWith(
      info: managed.info.copyWith(state: StdioProcessState.stopping),
    );
    notifyListeners();

    _appendLog(
      serverName,
      '\n[${_timestamp()}] 正在停止进程…',
      isStderr: false,
      expectedGeneration: generation,
    );

    try {
      managed.responseRouter?.rejectNewWrites(_stoppingException(serverName));
      if (!_immediateStopRequests.contains(serverName)) {
        await _waitForBorrowedSessions(serverName, generation);
      }
      await managed.responseRouter?.drainWrites(_stdinCloseTimeout);
      await closeMcpStdioSinkQuietly(
        stdin: managed.process!.stdin,
        timeout: _stdinCloseTimeout,
        logTag: 'mcp_stdio_process_manager',
        logWhere: '关闭进程标准输入：$serverName',
      );
      await _terminateProcessTreeBounded(
        managed.process!,
        gracefulTimeout: _immediateStopRequests.contains(serverName)
            ? _shutdownGracefulStopTimeout
            : null,
      );
    } catch (error, stack) {
      silentLog('mcp_stdio_process_manager', '停止 MCP stdio 进程', error, stack);
      _appendLog(
        serverName,
        '[${_timestamp()}] 停止异常：${mcpFailureMessage(error, fallback: 'MCP stdio 进程停止失败，请稍后重试。')}',
        isStderr: true,
        expectedGeneration: generation,
      );
    }

    await Future.wait<void>(<Future<void>>[
      _cancelSubscriptionBounded(
        managed.stdoutSubscription,
        '取消 $serverName 标准输出订阅',
      ),
      _cancelSubscriptionBounded(
        managed.stderrSubscription,
        '取消 $serverName 标准错误订阅',
      ),
    ]);

    final current = _processes[serverName];
    if (current != null && current.generation == generation) {
      _processes[serverName] = _ManagedProcess(
        generation: generation,
        configFingerprint: current.configFingerprint,
        info: current.info.copyWith(
          state: StdioProcessState.stopped,
          clearPid: true,
        ),
      );
      notifyListeners();
    }
  }

  /// 停止所有正在运行的进程（应用退出时调用）。
  Future<void> stopAll({bool immediate = false}) async {
    if (immediate) {
      _isShuttingDown = true;
    }
    final names = <String>{
      ..._stopFutures.keys,
      for (final entry in _processes.entries)
        if (!entry.value.info.isStopped) entry.key,
    }.toList(growable: false);
    await forEachIndexWithConcurrencyLimit(
      itemCount: names.length,
      maxConcurrency: immediate
          ? _shutdownStopAllConcurrency
          : _stopAllConcurrency,
      task: (index) =>
          _stopServerSingleFlight(names[index], immediate: immediate),
    );
  }

  Future<void> removeServer(String serverName) async {
    await stopServer(serverName);
    _processes.remove(serverName);
    _sessionBorrowCount.remove(serverName);
    notifyListeners();
  }

  /// 清除指定服务的日志。
  void clearLogs(String serverName) {
    final managed = _processes[serverName];
    if (managed == null) return;
    _processes[serverName] = managed.copyWith(
      info: managed.info.copyWith(logs: const []),
    );
    notifyListeners();
  }

  // 工具发现服务复用已运行进程的会话借用机制

  final Map<String, int> _sessionBorrowCount = {};

  /// 尝试借用已运行且握手完成的进程供工具发现服务发送 tools/list。
  /// 如果进程正在启动或握手尚未完成，最多等待 [_handshakeWaitTimeout]。
  /// 返回 null 表示无可用进程（未启动/已停止/等待超时），调用方应回退到启动新进程。
  /// 借用计数用于 stopServer 给已借出的请求一个短暂收尾窗口；停止请求仍会
  /// 立即拒绝新写入，避免关闭流程被长时间 tools/list 卡住。
  static const Duration _handshakeWaitTimeout = Duration(minutes: 2);

  Future<ManagedStdioSession?> borrowSessionForDiscovery(
    String serverName, {
    Future<void>? cancelSignal,
  }) async {
    var cancellationRequested = await isCancelSignalCompleted(cancelSignal);
    if (_isDisposed || _isShuttingDown || cancellationRequested) {
      return null;
    }
    final signal = cancelSignal;
    if (signal != null) {
      unawaited(
        signal.then<void>(
          (_) => cancellationRequested = true,
          onError: (Object _, StackTrace _) => cancellationRequested = true,
        ),
      );
    }
    _ManagedProcess? managed = _processes[serverName];
    // 完全不存在条目时，调用方应先触发 startServer。
    if (managed == null) {
      return null;
    }
    if (managed.info.state == StdioProcessState.stopping) {
      return null;
    }
    // 已停止（非启动中）— 没有可复用的进程
    if (managed.info.isStopped && managed.process == null) {
      return null;
    }
    final generation = managed.generation;

    // 轮询等待进程启动并完成握手，覆盖同步占位和初始化回环阶段。
    final deadline = MonotonicDeadline(_handshakeWaitTimeout);
    try {
      while (!managed!.handshakeCompleted || managed.process == null) {
        if (deadline.isExpired) return null;
        final stillActive = await delayWhileContinuing(
          _handshakePollInterval,
          () {
            final current = _processes[serverName];
            return !cancellationRequested &&
                !_isDisposed &&
                !_isShuttingDown &&
                !deadline.isExpired &&
                current != null &&
                current.generation == generation &&
                current.info.state != StdioProcessState.stopping &&
                !(current.info.isStopped && current.process == null);
          },
        );
        if (!stillActive) return null;
        managed = _processes[serverName];
        if (managed == null ||
            managed.generation != generation ||
            managed.info.state == StdioProcessState.stopping ||
            managed.info.isStopped && managed.process == null) {
          return null;
        }
      }
    } finally {
      deadline.stop();
    }

    if (_isDisposed ||
        _isShuttingDown ||
        cancellationRequested ||
        await isCancelSignalCompleted(cancelSignal) ||
        managed.info.state != StdioProcessState.running ||
        managed.responseRouter == null ||
        managed.responseRouter!.isClosed) {
      return null;
    }
    _sessionBorrowCount[serverName] =
        (_sessionBorrowCount[serverName] ?? 0) + 1;
    final latest = _processes[serverName];
    if (latest == null ||
        latest.generation != generation ||
        latest.info.state != StdioProcessState.running ||
        latest.process != managed.process ||
        latest.responseRouter != managed.responseRouter ||
        latest.responseRouter == null ||
        latest.responseRouter!.isClosed) {
      returnSession(serverName);
      return null;
    }
    return ManagedStdioSession._(
      managed.process!,
      managed.responseRouter!,
      managed.instructions,
    );
  }

  /// 归还借用的会话，释放引用计数。
  void returnSession(String serverName) {
    final count = _sessionBorrowCount[serverName] ?? 0;
    if (count <= 1) {
      _sessionBorrowCount.remove(serverName);
    } else {
      _sessionBorrowCount[serverName] = count - 1;
    }
  }

  Future<void> _waitForBorrowedSessions(
    String serverName,
    int generation,
  ) async {
    final deadline = MonotonicDeadline(_borrowReleaseTimeout);
    try {
      while ((_sessionBorrowCount[serverName] ?? 0) > 0) {
        if (_immediateStopRequests.contains(serverName)) return;
        if (_processes[serverName]?.generation != generation) return;
        if (deadline.isExpired) {
          _appendLog(
            serverName,
            '[${_timestamp()}] 停止等待会话归还超时，继续关闭进程',
            isStderr: true,
            expectedGeneration: generation,
          );
          return;
        }
        final stillWaiting = await delayWhileContinuing(
          _borrowPollInterval,
          () =>
              (_sessionBorrowCount[serverName] ?? 0) > 0 &&
              !deadline.isExpired &&
              !_immediateStopRequests.contains(serverName) &&
              _processes[serverName]?.generation == generation,
        );
        if (!stillWaiting) return;
      }
    } finally {
      deadline.stop();
    }
  }

  void _appendLog(
    String serverName,
    String data, {
    required bool isStderr,
    int? expectedGeneration,
  }) {
    final managed = _processes[serverName];
    if (managed == null ||
        (expectedGeneration != null &&
            managed.generation != expectedGeneration)) {
      return;
    }

    final lines = data.split('\n');
    final currentLogs = List<String>.from(managed.info.logs);
    for (final rawLine in lines) {
      final wasTruncated = rawLine.length > _maxLogLineChars;
      final line = wasTruncated
          ? clipText(
              rawLine,
              _maxLogLineChars,
              suffix: '… [截断，共 ${rawLine.length} 字符]',
            )
          : rawLine;
      if (nullIfBlank(line) == null &&
          currentLogs.isNotEmpty &&
          currentLogs.last.isEmpty) {
        continue; // 避免连续空行
      }
      if (isStderr) {
        currentLogs.add('[标准错误] $line');
      } else {
        // 标准输出：检测 JSON-RPC 响应并格式化摘要。
        final trimmed = line.trim();
        if (!wasTruncated &&
            trimmed.startsWith('{') &&
            trimmed.contains('"jsonrpc"')) {
          _appendJsonRpcSummary(currentLogs, trimmed);
        } else {
          currentLogs.add(line);
        }
      }
    }

    // 限制日志行数
    while (currentLogs.length > _maxLogLines) {
      currentLogs.removeAt(0);
    }

    _processes[serverName] = managed.copyWith(
      info: managed.info.copyWith(logs: List.unmodifiable(currentLogs)),
    );
    notifyListeners();
  }

  /// 将 JSON-RPC 响应解析为结构化摘要，避免超长单行 JSON 淹没日志。
  void _appendJsonRpcSummary(List<String> logs, String jsonLine) {
    final parsed = _parseMcpStdioJsonRpcLine(jsonLine);
    if (parsed == null) {
      // JSON 解析失败，原样输出（截断超长行）
      if (jsonLine.length > _jsonRpcMalformedLinePreviewChars) {
        logs.add(
          clipText(
            jsonLine,
            _jsonRpcMalformedLinePreviewChars,
            suffix: '… [截断，共 ${jsonLine.length} 字符]',
          ),
        );
      } else {
        logs.add(jsonLine);
      }
      return;
    }
    try {
      final id = parsed['id'];
      final result = parsed['result'];

      if (result is Map) {
        final resultMap = stringKeyedMapFromValue(result);
        // initialize 方法响应。
        if (resultMap.containsKey('protocolVersion')) {
          final version = resultMap['protocolVersion'] ?? '?';
          final serverInfo = stringKeyedMapFromValue(resultMap['serverInfo']);
          final serverName = serverInfo['name'] ?? '';
          final serverVersion = serverInfo['version'] ?? '';
          logs.add('[jsonrpc:$id] ← initialize 响应');
          logs.add('  协议版本: $version');
          if (serverName.toString().isNotEmpty) {
            logs.add('  服务名称: $serverName v$serverVersion');
          }
          final capabilities = stringKeyedMapFromValue(
            resultMap['capabilities'],
          );
          if (capabilities.isNotEmpty) {
            logs.add('  能力: ${capabilities.keys.join(', ')}');
          }
          return;
        }
        // tools/list 方法响应。
        if (resultMap.containsKey('tools')) {
          final tools = resultMap['tools'];
          if (tools is List) {
            logs.add('[jsonrpc:$id] ← tools/list 响应 (${tools.length} 个工具)');
            for (final toolRaw in tools.take(12)) {
              if (toolRaw is Map) {
                final tool = stringKeyedMapFromValue(toolRaw);
                final name = tool['name'] ?? '?';
                final desc = tool['description'] ?? '';
                final descStr = desc.toString();
                final shortDesc = clipTextWithEllipsis(
                  descStr,
                  _jsonRpcToolDescriptionPreviewChars,
                );
                logs.add('  · $name — $shortDesc');
              }
            }
            if (tools.length > 12) {
              logs.add('  … 还有 ${tools.length - 12} 个工具');
            }
            return;
          }
        }
        // 其他 result 字段响应：生成紧凑摘要。
        final keys = resultMap.keys.take(5).join(', ');
        logs.add(
          '[jsonrpc:$id] ← 响应 {$keys${resultMap.length > 5 ? ", …" : ""}}',
        );
        return;
      }

      // error 字段响应。
      final error = parsed['error'];
      if (error is Map) {
        final errorMap = stringKeyedMapFromValue(error);
        final code = errorMap['code'] ?? '?';
        final message = errorMap['message'] ?? '';
        logs.add('[jsonrpc:$id] ← 错误 [$code] $message');
        return;
      }

      // 无 id 的通知消息。
      final method = parsed['method'];
      if (method != null) {
        logs.add('[jsonrpc] ← 通知: $method');
        return;
      }

      // 兜底：紧凑单行
      logs.add(_compactJsonRpcLine(jsonLine));
    } catch (error, stack) {
      silentLog('mcp_stdio_process_manager', '汇总 JSON-RPC 日志行', error, stack);
      logs.add(_compactJsonRpcLine(jsonLine));
    }
  }

  String _compactJsonRpcLine(String line) {
    return clipTextWithEllipsis(line, _jsonRpcCompactLinePreviewChars);
  }

  /// 启动后自动通过标准输入发送 MCP initialize 请求完成协议握手。
  Future<void> _initializeMcpProtocol(
    String serverName,
    int generation,
    Process process,
    _ManagedResponseRouter responseRouter,
  ) async {
    _appendLog(
      serverName,
      '[${_timestamp()}] MCP 协议握手中…',
      isStderr: false,
      expectedGeneration: generation,
    );
    final requestId = 'openhand-initialize-$generation';
    final responseCompleter = Completer<Map<String, Object?>?>();
    try {
      // 等待 npx 解析并启动实际的 MCP 服务进程（首次可能需要下载包）
      final startupStillActive = await delayWhileContinuing(
        _initializeStartupDelay,
        () {
          final current = _processes[serverName];
          return !_isDisposed &&
              !_isShuttingDown &&
              current != null &&
              current.generation == generation &&
              identical(current.process, process) &&
              current.info.isRunning &&
              identical(current.responseRouter, responseRouter) &&
              !responseRouter.isClosed;
        },
      );
      if (!startupStillActive) return;
      final managed = _processes[serverName];
      if (managed == null ||
          managed.generation != generation ||
          !identical(managed.process, process) ||
          !managed.info.isRunning ||
          !identical(managed.responseRouter, responseRouter) ||
          responseRouter.isClosed) {
        return;
      }

      responseRouter.register(requestId, responseCompleter);
      await responseRouter.writeMessage(process.stdin, {
        'jsonrpc': '2.0',
        'id': requestId,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-11-25',
          'capabilities': {},
          'clientInfo': {'name': 'OpenHand', 'version': '1.0.0'},
        },
      });

      // 通过 JSON-RPC ID 路由完整响应，兼容 stdout 分片并避免无关响应误判。
      final response = await responseCompleter.future.timeout(
        _initializeResponseTimeout,
      );
      final gotResponse =
          response != null &&
          response['error'] == null &&
          response['result'] is Map;

      if (gotResponse) {
        final result = stringKeyedMapFromValue(response['result']);
        final instructions =
            optionalStringFromValue(result['instructions']) ?? '';
        _appendLog(
          serverName,
          '[${_timestamp()}] ✓ MCP 握手成功',
          isStderr: false,
          expectedGeneration: generation,
        );

        final currentBeforeNotify = _processes[serverName];
        if (currentBeforeNotify == null ||
            currentBeforeNotify.generation != generation ||
            !identical(currentBeforeNotify.process, process) ||
            !currentBeforeNotify.info.isRunning ||
            !identical(currentBeforeNotify.responseRouter, responseRouter) ||
            responseRouter.isClosed) {
          return;
        }

        await responseRouter.writeMessage(process.stdin, {
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        });
        _appendLog(
          serverName,
          '[${_timestamp()}] ✓ 服务已就绪，可正常使用',
          isStderr: false,
          expectedGeneration: generation,
        );

        // 标记握手完成，允许工具发现服务复用此进程。
        final current = _processes[serverName];
        if (current != null &&
            current.generation == generation &&
            identical(current.process, process) &&
            current.info.isRunning &&
            identical(current.responseRouter, responseRouter) &&
            !responseRouter.isClosed) {
          _processes[serverName] = current.copyWith(
            handshakeCompleted: true,
            instructions: instructions,
          );
        }
      } else {
        final detail = response?['error'] ?? '响应缺少 result 字段';
        _appendLog(
          serverName,
          '[${_timestamp()}] ⚠ MCP 握手失败：$detail',
          isStderr: true,
          expectedGeneration: generation,
        );
      }
    } on TimeoutException {
      _appendLog(
        serverName,
        '[${_timestamp()}] ⚠ 握手超时或进程已退出',
        isStderr: false,
        expectedGeneration: generation,
      );
    } catch (error, stack) {
      silentLog('mcp_stdio_process_manager', '执行 MCP stdio 握手', error, stack);
      _appendLog(
        serverName,
        '[${_timestamp()}] ⚠ 握手异常：${mcpFailureMessage(error, fallback: 'MCP stdio 握手失败，请稍后重试。')}',
        isStderr: false,
        expectedGeneration: generation,
      );
    } finally {
      responseRouter.unregister(requestId);
    }
  }

  /// 获取进程的运行时环境信息。
  Future<Map<String, String>> getRuntimeInfo(String serverName) async {
    final managed = _processes[serverName];
    final info = <String, String>{};

    info['状态'] = switch (managed?.info.state ?? StdioProcessState.stopped) {
      StdioProcessState.stopped => '已停止',
      StdioProcessState.starting => '启动中',
      StdioProcessState.running => '运行中',
      StdioProcessState.stopping => '停止中',
    };

    if (managed?.info.pid != null) {
      info['PID'] = '${managed!.info.pid}';
    }

    if (managed?.info.startedAt != null) {
      final uptime = managed!.info.uptime;
      if (uptime != null) {
        info['运行时长'] = _formatDuration(uptime);
      }
      info['启动时间'] = managed.info.startedAt!
          .toLocal()
          .toString()
          .split('.')
          .first;
    }

    info['操作系统'] =
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    info['处理器数'] = '${Platform.numberOfProcessors}';
    info['Dart 版本'] = Platform.version.split(' ').first;

    // 尝试获取进程内存信息（macOS/Linux）
    final pid = managed?.info.pid;
    if (pid != null && !Platform.isWindows) {
      try {
        final result = await runTrackedProcessOrFailed(
          'ps',
          ['-o', 'rss=', '-p', '$pid'],
          timeout: const Duration(seconds: 3),
          tag: 'mcp_stdio.ps_rss',
        );
        if (result.exitCode == 0) {
          final rssKb = optionalIntFromValue(result.stdout);
          if (rssKb != null) {
            info['内存 (RSS)'] = formatByteSize(rssKb * kBytesPerKiB);
          }
        }
      } catch (error, stack) {
        silentLog('mcp_stdio_process_manager', '读取进程 $pid 内存', error, stack);
      }

      // 获取线程数
      try {
        final result = await runTrackedProcessOrFailed(
          'ps',
          ['-M', '-p', '$pid'],
          timeout: const Duration(seconds: 3),
          tag: 'mcp_stdio.ps_threads',
        );
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().trim().split('\n');
          info['线程数'] = '${lines.length - 1}'; // 减去 header 行
        }
      } catch (error, stack) {
        silentLog('mcp_stdio_process_manager', '读取进程 $pid 线程数', error, stack);
      }
    }

    // 隔离缓存目录信息
    final cacheRoot = mcpStdioIsolatedCacheRoot();
    final cacheDir = Directory(cacheRoot);
    final cacheExists = await isDirectoryPath(cacheRoot, followLinks: true);
    info['隔离缓存'] = cacheExists ? cacheRoot : '(未创建)';
    if (cacheExists) {
      try {
        final usage = await measureDirectoryBounded(
          cacheDir,
          maxEntries: _maxRuntimeCacheScanEntries,
          totalTimeout: _runtimeCacheScanTimeout,
          operationTimeout: _runtimeCacheStatTimeout,
        );
        final partialSuffix = usage.truncated ? '（部分统计）' : '';
        info['缓存大小'] = '${formatByteSize(usage.totalBytes)}$partialSuffix';
        info['缓存文件数'] = '${usage.fileCount}$partialSuffix';
      } catch (error, stack) {
        silentLog('mcp_stdio_process_manager', '扫描缓存 $cacheRoot', error, stack);
      }
    }

    return info;
  }

  static String _timestamp() {
    return formatHourMinuteSecond(DateTime.now());
  }

  static McpToolDiscoveryException _stoppingException(String serverName) {
    return McpToolDiscoveryException(
      'Stdio MCP 服务“$serverName”正在停止，请稍后重试。',
      isExpectedLifecycleCancellation: true,
    );
  }

  static String _formatDuration(Duration d) {
    if (d.inDays > 0) {
      return '${d.inDays}天 ${d.inHours % 24}时 ${d.inMinutes % 60}分';
    }
    if (d.inHours > 0) {
      return '${d.inHours}时 ${d.inMinutes % 60}分 ${d.inSeconds % 60}秒';
    }
    if (d.inMinutes > 0) return '${d.inMinutes}分 ${d.inSeconds % 60}秒';
    return '${d.inSeconds}秒';
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    unawaited(
      stopAll(immediate: true).catchError((Object error, StackTrace stack) {
        silentLog('mcp_stdio_process_manager', '释放时停止全部进程', error, stack);
      }),
    );
    super.dispose();
  }
}

/// 轻量级会话包装器，供工具发现服务通过已运行的进程发送 JSON-RPC 请求。
/// 不拥有进程生命周期——进程由 McpStdioProcessManager 管理。
/// 响应路由通过 McpStdioProcessManager 的标准输出监听器完成。
class ManagedStdioSession {
  ManagedStdioSession._(this._process, this._responseRouter, this.instructions);

  final Process _process;
  final _ManagedResponseRouter _responseRouter;
  final Set<String> _cancelledRequestIds = <String>{};
  final String instructions;

  static const Duration _requestTimeout = Duration(seconds: 8);

  Future<Map<String, Object?>?> sendRequest(
    Map<String, Object?> payload, {
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    final requestIdText = '${payload['id']}';
    if (await isCancelSignalCompleted(cancelSignal)) {
      throw kMcpStdioRequestCancelledException;
    }
    if (_cancelledRequestIds.remove(requestIdText)) {
      throw kMcpStdioRequestCancelledException;
    }
    final completer = Completer<Map<String, Object?>?>();
    observeMcpPendingFuture(completer.future);
    try {
      _responseRouter.register(requestIdText, completer);
    } catch (error, stack) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
      rethrow;
    }
    var settled = false;
    try {
      await _responseRouter.writeMessage(_process.stdin, payload);
    } on StateError catch (e, stack) {
      _responseRouter.unregister(requestIdText);
      if (!completer.isCompleted) {
        completer.completeError(e, stack);
      }
      throw McpToolDiscoveryException('无法写入托管的 MCP stdio 进程：${e.message}');
    } catch (e, stack) {
      _responseRouter.unregister(requestIdText);
      if (!completer.isCompleted) {
        completer.completeError(e, stack);
      }
      rethrow;
    }
    Future<void> cancelPendingRequest() async {
      if (settled) return;
      try {
        await _responseRouter.cancelRequest(
          _process.stdin,
          requestId: payload['id'],
          requestIdText: requestIdText,
        );
      } catch (error, stack) {
        silentLog(
          'mcp_stdio_process_manager',
          '取消托管 MCP stdio 请求',
          error,
          stack,
        );
      }
    }

    final signal = cancelSignal;
    if (signal != null) {
      unawaited(
        signal.then<void>(
          (_) => cancelPendingRequest(),
          onError: (Object _, StackTrace _) => cancelPendingRequest(),
        ),
      );
    }
    try {
      return await completer.future.timeout(timeout ?? _requestTimeout);
    } on TimeoutException catch (_, stack) {
      const error = McpToolDiscoveryException('等待托管 MCP stdio 进程响应超时。');
      unawaited(cancelPendingRequest());
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
      throw error;
    } finally {
      settled = true;
      _cancelledRequestIds.remove(requestIdText);
      _responseRouter.unregister(requestIdText);
    }
  }

  Future<void> cancelRequest(Object? requestId) async {
    final requestIdText = '$requestId';
    _cancelledRequestIds.add(requestIdText);
    await _responseRouter.cancelRequest(
      _process.stdin,
      requestId: requestId,
      requestIdText: requestIdText,
    );
  }
}

/// 管理进程标准输出中 JSON-RPC 响应的路由分发。
/// 标准输出数据可能跨多个分块到达（尤其是较大的 tools/list 响应），
/// 因此需要内部缓冲并按行边界解析。
class _ManagedResponseRouter {
  _ManagedResponseRouter({required this._maxBufferedChars});

  final Map<String, Completer<Map<String, Object?>?>> _pending = {};
  final StringBuffer _lineBuffer = StringBuffer();
  final McpStdioWriteQueue _writeQueue = McpStdioWriteQueue();
  final int _maxBufferedChars;
  Object? _closedError;

  bool get isClosed => _closedError != null;

  void register(String id, Completer<Map<String, Object?>?> completer) {
    final closedError = _closedError;
    if (closedError != null) {
      throw closedError;
    }
    if (_pending.containsKey(id)) {
      throw StateError('MCP stdio 请求编号重复：$id。');
    }
    if (_pending.length >= kMcpStdioMaxPendingRequests) {
      throw StateError(
        'MCP stdio 待处理请求过多'
        '（${_pending.length}/$kMcpStdioMaxPendingRequests）。',
      );
    }
    _pending[id] = completer;
  }

  void unregister(String id) {
    _pending.remove(id);
    if (_pending.isEmpty) {
      _lineBuffer.clear();
    }
  }

  Future<void> cancelRequest(
    IOSink stdin, {
    required Object? requestId,
    required String requestIdText,
  }) async {
    final completer = _pending.remove(requestIdText);
    if (completer == null) return;
    if (_pending.isEmpty) _lineBuffer.clear();
    if (!completer.isCompleted) {
      completer.completeError(kMcpStdioRequestCancelledException);
    }
    await writeMessage(stdin, <String, Object?>{
      'jsonrpc': '2.0',
      'method': 'notifications/cancelled',
      'params': <String, Object?>{'requestId': requestId, 'reason': '用户已取消。'},
    });
  }

  Future<void> writeMessage(IOSink stdin, Map<String, Object?> payload) {
    final closedError = _closedError;
    if (closedError != null) {
      return Future<void>.error(closedError);
    }
    return _writeQueue.run(() async {
      final closedError = _closedError;
      if (closedError != null) {
        throw closedError;
      }
      await writeMcpJsonLineToStdin(stdin, payload);
    });
  }

  Future<void> drainWrites(Duration timeout) {
    return _writeQueue.drain(timeout);
  }

  void rejectNewWrites(Object error, [StackTrace? stackTrace]) {
    _closedError ??= error;
    _writeQueue.rejectNewWrites(error);
    failAll(error, stackTrace);
  }

  /// 将标准输出数据送入路由器。数据可能跨多个分块到达，
  /// 内部按换行符分割并尝试解析完整的 JSON-RPC 响应。
  void tryRoute(String data) {
    if (_pending.isEmpty) return;
    if (data.length > _maxBufferedChars - _lineBuffer.length) {
      rejectNewWrites(
        StateError('MCP stdio 响应超过 $_maxBufferedChars 字符缓冲上限，且未形成完整行。'),
      );
      return;
    }
    _lineBuffer.write(data);
    final buffer = _lineBuffer.toString();
    // 查找最后一个换行符，之前的部分可以尝试解析
    final lastNewline = buffer.lastIndexOf('\n');
    if (lastNewline < 0) return;
    final complete = buffer.substring(0, lastNewline);
    final remainder = buffer.substring(lastNewline + 1);
    _lineBuffer
      ..clear()
      ..write(remainder);
    for (final line in complete.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('{')) continue;
      try {
        final decoded = _parseMcpStdioJsonRpcLine(trimmed);
        if (decoded == null) continue;
        final id = decoded['id'];
        if (id == null) continue;
        final idText = '$id';
        final completer = _pending.remove(idText);
        if (completer != null && !completer.isCompleted) {
          completer.complete(decoded);
        }
      } catch (_) {
        // JSON 解析失败——可能是非 JSON 输出（如 npm 进度信息），跳过
      }
    }
    if (_pending.isEmpty) _lineBuffer.clear();
  }

  void failAll(Object error, [StackTrace? stackTrace]) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(error, stackTrace);
    }
    _pending.clear();
    _lineBuffer.clear();
  }

  bool get hasPending => _pending.isNotEmpty;
}

class _ManagedProcess {
  const _ManagedProcess({
    required this.generation,
    required this.configFingerprint,
    required this.info,
    this.process,
    this.handshakeCompleted = false,
    this.instructions = '',
    this.responseRouter,
    this.stdoutSubscription,
    this.stderrSubscription,
  });

  final int generation;
  final String configFingerprint;
  final StdioProcessInfo info;
  final Process? process;
  final bool handshakeCompleted;
  final String instructions;
  final _ManagedResponseRouter? responseRouter;
  final StreamSubscription<String>? stdoutSubscription;
  final StreamSubscription<String>? stderrSubscription;

  _ManagedProcess copyWith({
    StdioProcessInfo? info,
    Process? process,
    bool? handshakeCompleted,
    String? instructions,
    _ManagedResponseRouter? responseRouter,
    StreamSubscription<String>? stdoutSubscription,
    StreamSubscription<String>? stderrSubscription,
    bool clearProcess = false,
  }) {
    return _ManagedProcess(
      generation: generation,
      configFingerprint: configFingerprint,
      info: info ?? this.info,
      process: clearProcess ? null : (process ?? this.process),
      handshakeCompleted: handshakeCompleted ?? this.handshakeCompleted,
      instructions: instructions ?? this.instructions,
      responseRouter: responseRouter ?? this.responseRouter,
      stdoutSubscription: stdoutSubscription ?? this.stdoutSubscription,
      stderrSubscription: stderrSubscription ?? this.stderrSubscription,
    );
  }
}

String _serverFingerprint(McpServer server) {
  final environmentKeys = server.environment.keys.toList()..sort();
  return jsonEncode(<String, Object?>{
    'command': server.command,
    'args': server.args,
    'environment': <String, String>{
      for (final key in environmentKeys) key: server.environment[key]!,
    },
  });
}

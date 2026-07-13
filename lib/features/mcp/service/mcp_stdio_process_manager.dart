import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/version_compare.dart';
import '../model/mcp_server.dart';
import 'mcp_stdio_io_utils.dart';
import 'mcp_tool_discovery_service.dart';

final RegExp _stdioCommandTokenSeparatorPattern = RegExp(r'\s+');
final RegExp _npxPackageVersionSuffixPattern = RegExp(r'@[^/]*$');
const int _jsonRpcMalformedLinePreviewChars = 200;
const int _jsonRpcCompactLinePreviewChars = 120;
const int _jsonRpcToolDescriptionPreviewChars = 60;

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
    this.memoryBytes,
    this.logs = const <String>[],
    this.errorMessage,
  });

  final StdioProcessState state;
  final int? pid;
  final DateTime? startedAt;
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
    return DateTime.now().toUtc().difference(startedAt!);
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
      memoryBytes: clearMemoryBytes ? null : memoryBytes ?? this.memoryBytes,
      logs: logs ?? this.logs,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

typedef McpStdioProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

Future<Process> _startMcpStdioProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) {
  return startTrackedProcessInNewGroup(
    executable,
    arguments,
    environment: environment,
  );
}

Duration _positiveDuration(String name, Duration value) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'must be greater than zero');
  }
  return value;
}

Duration _nonNegativeDuration(String name, Duration value) {
  if (value < Duration.zero) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
  return value;
}

int _positiveLimit(String name, int value) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be greater than zero');
  }
  return value;
}

/// 管理 STDIO 类型 MCP 服务的进程生命周期。
///
/// 每个 STDIO MCP 服务可以独立启动/停止，进程日志实时收集，
/// 应用退出时自动终止所有子进程。
class McpStdioProcessManager extends ChangeNotifier {
  McpStdioProcessManager._({
    McpStdioProcessStarter processStarter = _startMcpStdioProcess,
    Duration stdinCloseTimeout = _defaultStdinCloseTimeout,
    Duration gracefulStopTimeout = _defaultGracefulStopTimeout,
    Duration forceStopTimeout = _defaultForceStopTimeout,
    Duration processStartTimeout = _defaultProcessStartTimeout,
    Duration subscriptionCancelTimeout = _defaultSubscriptionCancelTimeout,
    Duration initializeStartupDelay = _defaultInitializeStartupDelay,
    Duration initializeResponseTimeout = _defaultInitializeResponseTimeout,
    int responseBufferLimit = _defaultResponseBufferLimit,
  }) : _processStarter = processStarter,
       _stdinCloseTimeout = _positiveDuration(
         'stdinCloseTimeout',
         stdinCloseTimeout,
       ),
       _gracefulStopTimeout = _positiveDuration(
         'gracefulStopTimeout',
         gracefulStopTimeout,
       ),
       _forceStopTimeout = _positiveDuration(
         'forceStopTimeout',
         forceStopTimeout,
       ),
       _processStartTimeout = _positiveDuration(
         'processStartTimeout',
         processStartTimeout,
       ),
       _subscriptionCancelTimeout = _positiveDuration(
         'subscriptionCancelTimeout',
         subscriptionCancelTimeout,
       ),
       _initializeStartupDelay = _nonNegativeDuration(
         'initializeStartupDelay',
         initializeStartupDelay,
       ),
       _initializeResponseTimeout = _positiveDuration(
         'initializeResponseTimeout',
         initializeResponseTimeout,
       ),
       _responseBufferLimit = _positiveLimit(
         'responseBufferLimit',
         responseBufferLimit,
       );

  /// Creates an isolated manager with deterministic process dependencies.
  /// Production code should use [instance].
  McpStdioProcessManager.forTesting({
    required McpStdioProcessStarter processStarter,
    Duration stdinCloseTimeout = const Duration(milliseconds: 10),
    Duration gracefulStopTimeout = const Duration(milliseconds: 10),
    Duration forceStopTimeout = const Duration(milliseconds: 10),
    Duration processStartTimeout = const Duration(milliseconds: 100),
    Duration subscriptionCancelTimeout = const Duration(milliseconds: 20),
    Duration initializeStartupDelay = Duration.zero,
    Duration initializeResponseTimeout = const Duration(milliseconds: 100),
    int responseBufferLimit = _defaultResponseBufferLimit,
  }) : this._(
         processStarter: processStarter,
         stdinCloseTimeout: stdinCloseTimeout,
         gracefulStopTimeout: gracefulStopTimeout,
         forceStopTimeout: forceStopTimeout,
         processStartTimeout: processStartTimeout,
         subscriptionCancelTimeout: subscriptionCancelTimeout,
         initializeStartupDelay: initializeStartupDelay,
         initializeResponseTimeout: initializeResponseTimeout,
         responseBufferLimit: responseBufferLimit,
       );

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
  static const Duration _borrowPollInterval = Duration(milliseconds: 80);
  static const int _defaultResponseBufferLimit = kBytesPerMiB;
  static const int _maxLogLineChars = 4 * kBytesPerKiB;

  final Map<String, _ManagedProcess> _processes = {};
  final McpStdioProcessStarter _processStarter;
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

  /// 获取所有正在运行的服务名列表。
  List<String> get runningServers => _processes.entries
      .where((e) => e.value.info.isRunning)
      .map((e) => e.key)
      .toList(growable: false);

  /// 启动指定 STDIO MCP 服务进程。
  Future<void> startServer(McpServer server) async {
    if (server.type != McpServerType.stdio) return;
    final name = server.name;

    final existing = _processes[name];
    if (existing != null && !existing.info.isStopped) return;

    final generation = _nextGeneration++;
    _processes[name] = _ManagedProcess(
      generation: generation,
      info: const StdioProcessInfo(state: StdioProcessState.starting),
    );
    notifyListeners();

    Process? process;
    StreamSubscription<String>? stdoutSubscription;
    StreamSubscription<String>? stderrSubscription;
    try {
      // 解析实际的可执行文件和参数。对于 npx 命令，尝试直接定位已安装包的
      // 入口脚本用 node 执行，避免 npx 的启动开销和 stdin 转发问题。
      final launch = await _resolveDirectLaunch(server);
      if (!_isCurrentStart(name, generation)) {
        return;
      }
      // npx -y / uvx 等首次拉包 + 后续 MCP 服务运行期出站都依赖同一套
      // 代理环境。把 SystemProxyResolver 解析出的 HTTP(S)/SOCKS 端点注
      // 入子进程，否则在企业代理 / 内网透明代理环境下会 TCP 握手超时。
      process = await _startProcessBounded(
        launch.executable,
        launch.args,
        environment: SystemProxyResolver.instance
            .resolveSubprocessEnvironment(),
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
      final handshakeCompleter = Completer<bool>();
      final managed = _ManagedProcess(
        generation: generation,
        info: StdioProcessInfo(
          state: StdioProcessState.running,
          pid: process.pid,
          startedAt: DateTime.now().toUtc(),
          logs: List.unmodifiable(logs),
        ),
        process: process,
        responseRouter: responseRouter,
        handshakeCompleter: handshakeCompleter,
      );
      _processes[name] = managed;
      notifyListeners();

      // 监听 stdout - 同时用于日志、握手响应检测和 discovery 响应路由
      stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .listen(
            (data) {
              // 优先尝试路由到 discovery session 的 pending requests
              final routed = responseRouter.tryRoute(data);
              _appendLog(
                name,
                data,
                isStderr: false,
                expectedGeneration: generation,
              );
              // 检测 MCP initialize 响应
              if (!handshakeCompleter.isCompleted &&
                  (data.contains('"result"') ||
                      data.contains('"protocolVersion"'))) {
                handshakeCompleter.complete(true);
              }
              // 如果路由成功但日志已记录，不影响功能
              if (routed) return;
            },
            onError: (e) {
              responseRouter.failAll(e is Object ? e : StateError('$e'));
              _appendLog(
                name,
                '[stdout error] $e',
                isStderr: true,
                expectedGeneration: generation,
              );
            },
            onDone: () {
              responseRouter.failAll(StateError('stdout closed'));
              _appendLog(
                name,
                '[stdout closed]',
                isStderr: false,
                expectedGeneration: generation,
              );
              if (!handshakeCompleter.isCompleted) {
                handshakeCompleter.complete(false);
              }
            },
          );

      // 监听 stderr
      stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .listen(
            (data) => _appendLog(
              name,
              data,
              isStderr: true,
              expectedGeneration: generation,
            ),
            onError: (e) => _appendLog(
              name,
              '[stderr error] $e',
              isStderr: true,
              expectedGeneration: generation,
            ),
            onDone: () => _appendLog(
              name,
              '[stderr closed]',
              isStderr: false,
              expectedGeneration: generation,
            ),
          );

      // 持有订阅句柄，停止进程时显式 cancel，避免管道未及时关闭时泄漏监听器。
      _processes[name] = managed.copyWith(
        stdoutSubscription: stdoutSubscription,
        stderrSubscription: stderrSubscription,
      );

      // 监听进程退出
      unawaited(
        process.exitCode.then((code) {
          _appendLog(
            name,
            '\n[${_timestamp()}] 进程已退出 (exit code: $code)',
            isStderr: false,
            expectedGeneration: generation,
          );
          responseRouter.failAll(StateError('process exited with code $code'));
          unawaited(
            Future.wait<void>(<Future<void>>[
              _cancelSubscriptionBounded(
                stdoutSubscription,
                'cancel exited stdout $name',
              ),
              _cancelSubscriptionBounded(
                stderrSubscription,
                'cancel exited stderr $name',
              ),
            ]),
          );
          final current = _processes[name];
          if (current != null &&
              current.generation == generation &&
              identical(current.process, process)) {
            if (current.info.state != StdioProcessState.stopping) {
              unawaited(_terminateProcessTreeBounded(process!));
            }
            _processes[name] = _ManagedProcess(
              generation: generation,
              info: current.info.copyWith(
                state: StdioProcessState.stopped,
                clearPid: true,
              ),
            );
            notifyListeners();
          }
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.complete(false);
          }
        }),
      );

      // 启动后自动执行 MCP 协议握手
      unawaited(
        _initializeMcpProtocol(
          name,
          generation,
          process,
          responseRouter,
          handshakeCompleter,
        ),
      );
    } catch (e) {
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
          info: StdioProcessInfo(
            errorMessage: '$e',
            logs: ['[${_timestamp()}] 启动失败: $e'],
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

  Future<Process> _startProcessBounded(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    final startFuture = _processStarter(
      executable,
      arguments,
      environment: environment,
    );
    var timedOut = false;
    unawaited(
      startFuture.then<void>((lateProcess) {
        if (timedOut) {
          unawaited(_terminateUnmanagedProcess(lateProcess));
        }
      }, onError: (Object _, StackTrace _) {}),
    );
    return startFuture.timeout(
      _processStartTimeout,
      onTimeout: () {
        timedOut = true;
        throw TimeoutException(
          'MCP stdio process start timed out after '
          '${_processStartTimeout.inMilliseconds}ms',
          _processStartTimeout,
        );
      },
    );
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
        silentLog(
          'mcp_stdio_process_manager',
          'attach unmanaged stdout drain',
          error,
          stack,
        );
      }
    }
    if (stderrSubscription == null) {
      try {
        rawStderrSubscription = process.stderr.listen(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
      } catch (error, stack) {
        silentLog(
          'mcp_stdio_process_manager',
          'attach unmanaged stderr drain',
          error,
          stack,
        );
      }
    }

    try {
      await Future.wait<void>(<Future<void>>[
        closeMcpStdioSinkQuietly(
          stdin: process.stdin,
          timeout: _stdinCloseTimeout,
          logTag: 'mcp_stdio_process_manager',
          logWhere: 'close unmanaged stdin',
        ),
        _terminateProcessTreeBounded(process),
      ]);
    } catch (error, stack) {
      silentLog(
        'mcp_stdio_process_manager',
        'clean unmanaged process',
        error,
        stack,
      );
    }
    await Future.wait<void>(<Future<void>>[
      _cancelSubscriptionBounded(stdoutSubscription, 'cancel unmanaged stdout'),
      _cancelSubscriptionBounded(stderrSubscription, 'cancel unmanaged stderr'),
      _cancelSubscriptionBounded(
        rawStdoutSubscription,
        'cancel raw unmanaged stdout',
      ),
      _cancelSubscriptionBounded(
        rawStderrSubscription,
        'cancel raw unmanaged stderr',
      ),
    ]);
  }

  Future<void> _terminateProcessTreeBounded(Process process) async {
    // Signal the direct process immediately. Descendant enumeration inside
    // the shared tree terminator is bounded but may still take a moment on a
    // congested host; Stop must never return before even attempting TERM.
    try {
      process.kill();
    } catch (error, stack) {
      silentLog(
        'mcp_stdio_process_manager',
        'signal process before tree cleanup',
        error,
        stack,
      );
    }
    final totalTimeout = Duration(
      microseconds:
          _gracefulStopTimeout.inMicroseconds +
          _forceStopTimeout.inMicroseconds +
          const Duration(seconds: 3).inMicroseconds,
    );
    try {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: _gracefulStopTimeout,
      ).timeout(totalTimeout);
    } on TimeoutException catch (error, stack) {
      silentLog(
        'mcp_stdio_process_manager',
        'terminate process tree timed out',
        error,
        stack,
      );
    } catch (error, stack) {
      silentLog(
        'mcp_stdio_process_manager',
        'terminate process tree',
        error,
        stack,
      );
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
  Future<void> stopServer(String serverName) async {
    final managed = _processes[serverName];
    if (managed == null) return;
    if (managed.info.state == StdioProcessState.stopping) return;
    if (managed.process == null) {
      if (managed.info.state == StdioProcessState.starting) {
        _processes[serverName] = _ManagedProcess(
          generation: managed.generation,
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
      final handshakeCompleter = managed.handshakeCompleter;
      if (handshakeCompleter != null && !handshakeCompleter.isCompleted) {
        handshakeCompleter.complete(false);
      }
      await _waitForBorrowedSessions(serverName, generation);
      await managed.responseRouter?.drainWrites(_stdinCloseTimeout);
      await closeMcpStdioSinkQuietly(
        stdin: managed.process!.stdin,
        timeout: _stdinCloseTimeout,
        logTag: 'mcp_stdio_process_manager',
        logWhere: 'close stdin $serverName',
      );
      await _terminateProcessTreeBounded(managed.process!);
    } catch (e) {
      _appendLog(
        serverName,
        '[${_timestamp()}] 停止异常: $e',
        isStderr: true,
        expectedGeneration: generation,
      );
    }

    await Future.wait<void>(<Future<void>>[
      _cancelSubscriptionBounded(
        managed.stdoutSubscription,
        'cancel stdout $serverName',
      ),
      _cancelSubscriptionBounded(
        managed.stderrSubscription,
        'cancel stderr $serverName',
      ),
    ]);

    final current = _processes[serverName];
    if (current != null && current.generation == generation) {
      _processes[serverName] = _ManagedProcess(
        generation: generation,
        info: current.info.copyWith(
          state: StdioProcessState.stopped,
          clearPid: true,
        ),
      );
      notifyListeners();
    }
  }

  /// 停止所有正在运行的进程（应用退出时调用）。
  Future<void> stopAll() async {
    final names = _processes.entries
        .where((entry) => !entry.value.info.isStopped)
        .map((entry) => entry.key)
        .toList(growable: false);
    await Future.wait(names.map(stopServer));
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

  // ─────────────────────────────────────────────────────────────────────────
  // Discovery Service 复用已运行进程的会话借用机制
  // ─────────────────────────────────────────────────────────────────────────

  final Map<String, int> _sessionBorrowCount = {};

  /// 尝试借用已运行且握手完成的进程供 discovery service 发送 tools/list。
  /// 如果进程正在启动或握手尚未完成，最多等待 [_handshakeWaitTimeout]。
  /// 返回 null 表示无可用进程（未启动/已停止/等待超时），调用方应回退到启动新进程。
  /// 借用计数用于 stopServer 给已借出的请求一个短暂收尾窗口；停止请求仍会
  /// 立即拒绝新写入，避免关闭流程被长时间 tools/list 卡住。
  static const Duration _handshakeWaitTimeout = Duration(minutes: 2);

  Future<ManagedStdioSession?> borrowSessionForDiscovery(
    String serverName,
  ) async {
    _ManagedProcess? managed = _processes[serverName];
    // 完全不存在 entry — 调用方应先触发 startServer
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

    // 轮询等待：进程启动 + 握手完成。覆盖两种情况：
    //   a) 进程刚 startServer，process 字段还是 null（同步占位阶段）
    //   b) 进程已启动，但 handshake 还在进行（initialize 回环）
    final deadline = DateTime.now().add(_handshakeWaitTimeout);
    while (!managed!.handshakeCompleted || managed.process == null) {
      if (DateTime.now().isAfter(deadline)) {
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      managed = _processes[serverName];
      if (managed == null) {
        return null;
      }
      if (managed.info.state == StdioProcessState.stopping) {
        return null;
      }
      if (managed.info.isStopped && managed.process == null) {
        return null;
      }
    }

    if (managed.info.state != StdioProcessState.running ||
        managed.responseRouter == null ||
        managed.responseRouter!.isClosed) {
      return null;
    }
    _sessionBorrowCount[serverName] =
        (_sessionBorrowCount[serverName] ?? 0) + 1;
    final latest = _processes[serverName];
    if (latest == null ||
        latest.info.state != StdioProcessState.running ||
        latest.process != managed.process ||
        latest.responseRouter != managed.responseRouter ||
        latest.responseRouter == null ||
        latest.responseRouter!.isClosed) {
      returnSession(serverName);
      return null;
    }
    return ManagedStdioSession._(managed.process!, managed.responseRouter!);
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
    final deadline = DateTime.now().add(_borrowReleaseTimeout);
    while ((_sessionBorrowCount[serverName] ?? 0) > 0) {
      if (_processes[serverName]?.generation != generation) {
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        _appendLog(
          serverName,
          '[${_timestamp()}] 停止等待会话归还超时，继续关闭进程',
          isStderr: true,
          expectedGeneration: generation,
        );
        return;
      }
      await Future<void>.delayed(_borrowPollInterval);
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
        currentLogs.add('[stderr] $line');
      } else {
        // stdout: 检测 JSON-RPC 响应并格式化摘要
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
        // initialize 响应
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
        // tools/list 响应
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
        // 其他 result 响应：紧凑摘要
        final keys = resultMap.keys.take(5).join(', ');
        logs.add(
          '[jsonrpc:$id] ← 响应 {$keys${resultMap.length > 5 ? ", …" : ""}}',
        );
        return;
      }

      // error 响应
      final error = parsed['error'];
      if (error is Map) {
        final errorMap = stringKeyedMapFromValue(error);
        final code = errorMap['code'] ?? '?';
        final message = errorMap['message'] ?? '';
        logs.add('[jsonrpc:$id] ← 错误 [$code] $message');
        return;
      }

      // notification（无 id）
      final method = parsed['method'];
      if (method != null) {
        logs.add('[jsonrpc] ← 通知: $method');
        return;
      }

      // 兜底：紧凑单行
      logs.add(_compactJsonRpcLine(jsonLine));
    } catch (error, stack) {
      silentLog(
        'mcp_stdio_process_manager',
        'summarize json-rpc line',
        error,
        stack,
      );
      logs.add(_compactJsonRpcLine(jsonLine));
    }
  }

  String _compactJsonRpcLine(String line) {
    return clipTextWithEllipsis(line, _jsonRpcCompactLinePreviewChars);
  }

  /// 启动后自动通过 stdin 发送 MCP initialize 请求完成协议握手。
  Future<void> _initializeMcpProtocol(
    String serverName,
    int generation,
    Process process,
    _ManagedResponseRouter responseRouter,
    Completer<bool> responseCompleter,
  ) async {
    _appendLog(
      serverName,
      '[${_timestamp()}] MCP 协议握手中…',
      isStderr: false,
      expectedGeneration: generation,
    );
    try {
      // 等待 npx 解析并启动实际的 MCP 服务进程（首次可能需要下载包）
      await Future.delayed(_initializeStartupDelay);
      final managed = _processes[serverName];
      if (managed == null ||
          managed.generation != generation ||
          !identical(managed.process, process) ||
          !managed.info.isRunning ||
          !identical(managed.responseRouter, responseRouter) ||
          responseRouter.isClosed) {
        return;
      }

      await responseRouter.writeMessage(process.stdin, {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-11-25',
          'capabilities': {},
          'clientInfo': {'name': 'OpenHand', 'version': '1.0.0'},
        },
      });

      // 等待 stdout 中出现响应（最多 90 秒，npx 首次运行需要下载包）
      final gotResponse = await responseCompleter.future.timeout(
        _initializeResponseTimeout,
        onTimeout: () => false,
      );

      if (gotResponse) {
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

        // 标记握手完成，允许 discovery service 复用此进程
        final current = _processes[serverName];
        if (current != null &&
            current.generation == generation &&
            identical(current.process, process) &&
            current.info.isRunning &&
            identical(current.responseRouter, responseRouter) &&
            !responseRouter.isClosed) {
          _processes[serverName] = current.copyWith(handshakeCompleted: true);
        }
      } else {
        _appendLog(
          serverName,
          '[${_timestamp()}] ⚠ 握手超时或进程已退出',
          isStderr: false,
          expectedGeneration: generation,
        );
      }
    } catch (e) {
      _appendLog(
        serverName,
        '[${_timestamp()}] ⚠ 握手异常: $e',
        isStderr: false,
        expectedGeneration: generation,
      );
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
            info['内存 (RSS)'] = formatByteSize(rssKb * 1024);
          }
        }
      } catch (error, stack) {
        silentLog('mcp_stdio_process_manager', 'read rss $pid', error, stack);
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
        silentLog(
          'mcp_stdio_process_manager',
          'read thread count $pid',
          error,
          stack,
        );
      }
    }

    // 隔离缓存目录信息
    final cacheRoot = mcpStdioIsolatedCacheRoot();
    final cacheDir = Directory(cacheRoot);
    info['隔离缓存'] = cacheDir.existsSync() ? cacheRoot : '(未创建)';
    if (cacheDir.existsSync()) {
      try {
        int totalSize = 0;
        int fileCount = 0;
        await for (final entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
            fileCount++;
          }
        }
        info['缓存大小'] = formatByteSize(totalSize);
        info['缓存文件数'] = '$fileCount';
      } catch (error, stack) {
        silentLog(
          'mcp_stdio_process_manager',
          'scan cache $cacheRoot',
          error,
          stack,
        );
      }
    }

    return info;
  }

  static String _timestamp() {
    return formatHourMinuteSecond(DateTime.now());
  }

  static McpToolDiscoveryException _stoppingException(String serverName) {
    return McpToolDiscoveryException(
      'Stdio MCP server "$serverName" is stopping. Try again after it finishes stopping.',
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
  void dispose() {
    unawaited(
      stopAll().catchError((Object error, StackTrace stack) {
        silentLog('mcp_stdio_process_manager', 'dispose.stopAll', error, stack);
      }),
    );
    super.dispose();
  }
}

/// 轻量级会话包装器，供 discovery service 通过已运行的进程发送 JSON-RPC 请求。
/// 不拥有进程生命周期——进程由 McpStdioProcessManager 管理。
/// 响应路由通过 McpStdioProcessManager 的 stdout 监听器完成。
class ManagedStdioSession {
  ManagedStdioSession._(this._process, this._responseRouter);

  final Process _process;
  final _ManagedResponseRouter _responseRouter;
  String instructions = '';

  static const Duration _requestTimeout = Duration(seconds: 8);

  Future<Map<String, Object?>?> sendRequest(
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    final requestIdText = '${payload['id']}';
    final completer = Completer<Map<String, Object?>?>();
    observeMcpStdioPendingFuture(completer.future);
    try {
      _responseRouter.register(requestIdText, completer);
    } catch (error, stack) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
      rethrow;
    }
    try {
      await _responseRouter.writeMessage(_process.stdin, payload);
    } on StateError catch (e, stack) {
      _responseRouter.unregister(requestIdText);
      if (!completer.isCompleted) {
        completer.completeError(e, stack);
      }
      throw McpToolDiscoveryException(
        'Cannot write to managed stdio process: $e',
      );
    } catch (e, stack) {
      _responseRouter.unregister(requestIdText);
      if (!completer.isCompleted) {
        completer.completeError(e, stack);
      }
      rethrow;
    }
    try {
      return await completer.future.timeout(timeout ?? _requestTimeout);
    } on TimeoutException catch (_, stack) {
      const error = McpToolDiscoveryException(
        'Tool scan timed out waiting for response from managed stdio process.',
      );
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
      throw error;
    } finally {
      _responseRouter.unregister(requestIdText);
    }
  }
}

/// 管理进程 stdout 中 JSON-RPC 响应的路由分发。
/// stdout 数据可能跨多个 chunk 到达（尤其是大的 tools/list 响应），
/// 因此需要内部缓冲并按行边界解析。
class _ManagedResponseRouter {
  _ManagedResponseRouter({required int maxBufferedChars})
    : _maxBufferedChars = maxBufferedChars;

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
    _pending[id] = completer;
  }

  void unregister(String id) {
    _pending.remove(id);
    if (_pending.isEmpty) {
      _lineBuffer.clear();
    }
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

  /// 将 stdout 数据喂入路由器。数据可能跨多个 chunk 到达，
  /// 内部按换行符分割并尝试解析完整的 JSON-RPC 响应。
  /// 返回 true 表示成功路由了至少一个响应。
  bool tryRoute(String data) {
    if (_pending.isEmpty) return false;
    if (data.length > _maxBufferedChars - _lineBuffer.length) {
      rejectNewWrites(
        StateError(
          'MCP stdio response exceeded the $_maxBufferedChars character '
          'buffer limit without a complete line.',
        ),
      );
      return false;
    }
    _lineBuffer.write(data);
    final buffer = _lineBuffer.toString();
    // 查找最后一个换行符，之前的部分可以尝试解析
    final lastNewline = buffer.lastIndexOf('\n');
    if (lastNewline < 0) return false;
    final complete = buffer.substring(0, lastNewline);
    final remainder = buffer.substring(lastNewline + 1);
    _lineBuffer
      ..clear()
      ..write(remainder);
    bool routed = false;
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
          routed = true;
        }
      } catch (_) {
        // JSON 解析失败——可能是非 JSON 输出（如 npm 进度信息），跳过
      }
    }
    return routed;
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
    required this.info,
    this.process,
    this.handshakeCompleted = false,
    this.responseRouter,
    this.handshakeCompleter,
    this.stdoutSubscription,
    this.stderrSubscription,
  });

  final int generation;
  final StdioProcessInfo info;
  final Process? process;
  final bool handshakeCompleted;
  final _ManagedResponseRouter? responseRouter;
  final Completer<bool>? handshakeCompleter;
  final StreamSubscription<String>? stdoutSubscription;
  final StreamSubscription<String>? stderrSubscription;

  _ManagedProcess copyWith({
    StdioProcessInfo? info,
    Process? process,
    bool? handshakeCompleted,
    _ManagedResponseRouter? responseRouter,
    Completer<bool>? handshakeCompleter,
    StreamSubscription<String>? stdoutSubscription,
    StreamSubscription<String>? stderrSubscription,
    bool clearProcess = false,
  }) {
    return _ManagedProcess(
      generation: generation,
      info: info ?? this.info,
      process: clearProcess ? null : (process ?? this.process),
      handshakeCompleted: handshakeCompleted ?? this.handshakeCompleted,
      responseRouter: responseRouter ?? this.responseRouter,
      handshakeCompleter: handshakeCompleter ?? this.handshakeCompleter,
      stdoutSubscription: stdoutSubscription ?? this.stdoutSubscription,
      stderrSubscription: stderrSubscription ?? this.stderrSubscription,
    );
  }
}

class _DirectLaunch {
  const _DirectLaunch({required this.executable, required this.args});
  final String executable;
  final List<String> args;
}

/// 解析 STDIO MCP 服务的直接启动参数。
/// 对于 npx 命令，尝试定位已全局安装的包入口脚本，直接用 node 执行。
/// 这避免了 npx 的启动开销、下载延迟、以及 login shell stdin 转发问题。
/// 兼容用户把整条命令粘进 command 字段的情况（如 "npx chrome-devtools-mcp@latest"）。
Future<_DirectLaunch> _resolveDirectLaunch(McpServer server) async {
  final command = server.command.trim();
  // 拆词：兼容 command="npx pkg@latest" 的写法
  final tokens = command.split(_stdioCommandTokenSeparatorPattern);
  final executable = tokens.first;
  final inlineArgs = tokens.length > 1 ? tokens.sublist(1) : const <String>[];
  final allArgs = [...inlineArgs, ...server.args];

  final isNpx = executable == 'npx' || executable.endsWith('/npx');

  final packageArgIndex = isNpx ? _firstNpxPackageArgIndex(allArgs) : -1;
  if (isNpx && packageArgIndex >= 0) {
    final packageName = allArgs[packageArgIndex].trim();
    final extraArgs = packageArgIndex + 1 < allArgs.length
        ? allArgs.sublist(packageArgIndex + 1)
        : const <String>[];

    // 尝试通过 login shell 定位已安装包的实际路径
    final resolved = await _resolveNpxPackagePath(packageName);
    if (resolved != null) {
      return _DirectLaunch(
        executable: resolved.nodeBin,
        args: [resolved.entryScript, ...extraArgs],
      );
    }
  }

  // 回退：通过 login shell 执行原始命令
  final shell = _pickShellForLaunch();
  final cmdLine = [
    executable,
    ...allArgs,
  ].map((p) => p.contains(' ') ? "'$p'" : p).join(' ');
  // 使用 exec 替换 shell 进程，确保 stdin 直接连接到目标进程
  return _DirectLaunch(executable: shell, args: ['-l', '-c', 'exec $cmdLine']);
}

int _firstNpxPackageArgIndex(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i].trim();
    if (arg.isEmpty) continue;
    if (arg == '--') continue;
    if (arg == '-y' || arg == '--yes' || arg == '--no-install') {
      continue;
    }
    if (arg.startsWith('-')) continue;
    return i;
  }
  return -1;
}

class _ResolvedNpxPackage {
  const _ResolvedNpxPackage({required this.nodeBin, required this.entryScript});
  final String nodeBin;
  final String entryScript;
}

/// 通过多种策略定位 npx 包的实际安装路径和入口脚本。
Future<_ResolvedNpxPackage?> _resolveNpxPackagePath(String packageName) async {
  // 解析包名（处理 @scope/name@version 格式）
  final cleanName = packageName.replaceAll(_npxPackageVersionSuffixPattern, '');

  // 策略 1：直接扫描 nvm 目录（最可靠，GUI 应用中 nvm 是最常见的 node 管理器）
  final home = Platform.environment['HOME'] ?? '';
  if (home.isNotEmpty) {
    final nvmDir = Platform.environment['NVM_DIR'] ?? '$home/.nvm';
    final versionsDir = Directory('$nvmDir/versions/node');
    if (versionsDir.existsSync()) {
      // 找到最新版本的 node
      final versions = <String>[];
      try {
        for (final entity in versionsDir.listSync()) {
          if (entity is Directory &&
              entity.path.split('/').last.startsWith('v')) {
            versions.add(entity.path.split('/').last);
          }
        }
      } catch (error, stack) {
        silentLog(
          'mcp_stdio_process_manager',
          'list nvm versions',
          error,
          stack,
        );
      }
      versions.sort(compareSemanticVersions);
      // 从最新版本开始查找包
      for (final version in versions.reversed) {
        final nodeBin = '$nvmDir/versions/node/$version/bin/node';
        final packageDir =
            '$nvmDir/versions/node/$version/lib/node_modules/$cleanName';
        if (File(nodeBin).existsSync() && Directory(packageDir).existsSync()) {
          final entry = _findBinEntry(packageDir);
          if (entry != null) {
            return _ResolvedNpxPackage(nodeBin: nodeBin, entryScript: entry);
          }
        }
      }
    }

    // 策略 2：检查 volta
    final voltaDir = '$home/.volta/tools/image/packages';
    if (Directory(voltaDir).existsSync()) {
      // volta 的全局包在 ~/.volta/tools/image/packages/<name>/
      final voltaPkgDir = '$voltaDir/$cleanName';
      if (Directory(voltaPkgDir).existsSync()) {
        final voltaNode = '$home/.volta/bin/node';
        if (File(voltaNode).existsSync()) {
          final entry = _findBinEntry(voltaPkgDir);
          if (entry != null) {
            return _ResolvedNpxPackage(nodeBin: voltaNode, entryScript: entry);
          }
        }
      }
    }
  }

  // 策略 3：通过 login shell 查询（兜底）
  try {
    final shell = _pickShellForLaunch();
    final result = await runTrackedProcessOrFailed(
      shell,
      ['-l', '-c', 'which node && npm root -g'],
      timeout: const Duration(seconds: 8),
      tag: 'mcp_stdio.login_shell_probe',
    );
    if (result.exitCode == 0) {
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length >= 2) {
        final nodeBin = lines[0].trim();
        final globalRoot = lines[1].trim();
        if (nodeBin.isNotEmpty &&
            globalRoot.isNotEmpty &&
            File(nodeBin).existsSync()) {
          final packageDir = '$globalRoot/$cleanName';
          if (Directory(packageDir).existsSync()) {
            final entry = _findBinEntry(packageDir);
            if (entry != null) {
              return _ResolvedNpxPackage(nodeBin: nodeBin, entryScript: entry);
            }
          }
        }
      }
    }
  } catch (error, stack) {
    silentLog(
      'mcp_stdio_process_manager',
      'login shell package probe',
      error,
      stack,
    );
  }

  return null;
}

/// 从 package.json 的 bin 字段解析入口脚本路径。
String? _findBinEntry(String packageDir) {
  try {
    final pkgJsonFile = File('$packageDir/package.json');
    if (!pkgJsonFile.existsSync()) return null;
    final pkgJson = jsonDecode(pkgJsonFile.readAsStringSync());
    final bin = pkgJson['bin'];
    String? entryScript;
    if (bin is String) {
      entryScript = '$packageDir/$bin';
    } else if (bin is Map && bin.isNotEmpty) {
      entryScript = '$packageDir/${bin.values.first}';
    }
    if (entryScript != null && File(entryScript).existsSync()) {
      return entryScript;
    }
  } catch (error, stack) {
    silentLog(
      'mcp_stdio_process_manager',
      'read bin entry $packageDir',
      error,
      stack,
    );
  }
  return null;
}

/// 选择 login shell。
String _pickShellForLaunch() {
  final preferred = Platform.environment['SHELL']?.trim();
  if (preferred != null &&
      preferred.isNotEmpty &&
      File(preferred).existsSync()) {
    return preferred;
  }
  if (File('/bin/zsh').existsSync()) return '/bin/zsh';
  return '/bin/bash';
}

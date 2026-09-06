import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/duration_bounds.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/serial_task_queue.dart';
import '../../../../shared/util/text_clip.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../web_engine/web_engine_http_exception.dart';
import '../web_engine/web_engine_value_parsing.dart';

enum WebFetchScraplingRuntimeEventType {
  command,
  status,
  stdout,
  stderr,
  success,
  warning,
}

const Duration _tlsBundleProbeTimeout = Duration(milliseconds: 500);
const Duration _pythonProbeTimeout = Duration(seconds: 12);

class WebFetchScraplingRuntimeEvent {
  const WebFetchScraplingRuntimeEvent({required this.type, required this.line});

  final WebFetchScraplingRuntimeEventType type;
  final String line;
}

class WebFetchScraplingBridgeResult {
  const WebFetchScraplingBridgeResult({
    required this.url,
    required this.title,
    required this.content,
    required this.contentType,
    required this.statusCode,
    required this.responseHeaders,
  });

  final String url;
  final String title;
  final String content;
  final String contentType;
  final int? statusCode;
  final Map<String, String> responseHeaders;
}

class WebFetchScraplingProbeStatus {
  const WebFetchScraplingProbeStatus({
    required this.ready,
    required this.code,
    required this.detail,
    this.pythonExecutable,
    this.updatedAt,
    this.runtimeInstalled = false,
  });

  final bool ready;
  final String code;
  final String detail;
  final String? pythonExecutable;
  final DateTime? updatedAt;
  final bool runtimeInstalled;
}

class WebFetchScraplingBridge {
  static const String _assetPath =
      'assets/tooling/webfetch_scrapling_bridge.py';
  static const String _pythonNotFoundCode = 'python_not_found';
  static const String _pythonNotFoundDetail =
      '未找到 Python 3。请安装 Python 3.10 或更高版本，或配置自定义可执行文件路径。';
  static const Duration _defaultProcessStopTimeout = Duration(seconds: 2);
  static const Duration _defaultProcessKillTimeout = Duration(
    milliseconds: 250,
  );
  static const int _maxStderrTailLength = 800;
  static const int _maxRuntimeEvents = 400;
  static const int _maxRuntimeLineCharacters = 4000;
  static const int _maxBridgeResponseLineCharacters =
      AiWebFetchEngineConfig.maxTruncationChars * 2;
  static const int _maxCapturedRuntimeLinesPerStream = 400;
  static const int _maxPendingOperations = 32;
  static const String _pythonRuntimeProbeScript = '''
import json
import platform
import sys

result = {
    "executable": sys.executable,
    "machine": platform.machine(),
    "version": platform.python_version(),
    "supported": sys.version_info >= (3, 10),
    "ready": False,
}
if result["supported"]:
    try:
        import scrapling
        from scrapling.fetchers import Fetcher
        result["ready"] = True
    except ModuleNotFoundError as error:
        result["missing"] = getattr(error, "name", "") or "unknown"
    except Exception as error:
        result["error"] = "%s: %s" % (type(error).__name__, error)
print(json.dumps(result, ensure_ascii=False))
''';

  _ScraplingProcessRuntime? _runtime;
  final SerialTaskQueue _operationQueue = SerialTaskQueue(
    maxPendingTasks: _maxPendingOperations,
  );
  Future<void>? _disposeFuture;
  bool _disposed = false;
  Process? _runtimeCommandProcess;
  String? _helperPath;
  int _requestSeq = 0;
  WebFetchScraplingProbeStatus _lastProbe = const WebFetchScraplingProbeStatus(
    ready: false,
    code: 'not_started',
    detail: 'Scrapling 桥接尚未启动。',
  );
  WebFetchScraplingProbeStatus get lastProbe => _lastProbe;

  Stream<WebFetchScraplingRuntimeEvent> installRuntimeStreaming({
    required AiWebFetchScraplingSettings settings,
  }) {
    return _runRuntimeCommandStreaming(
      settings: settings,
      command: const <String>['-m', 'pip', 'install', 'scrapling[fetchers]'],
      tag: 'web_fetch_scrapling.install',
      successMessage: 'Scrapling 运行时已安装。',
      failureCode: 'install_failed',
    );
  }

  Stream<WebFetchScraplingRuntimeEvent> uninstallRuntimeStreaming({
    required AiWebFetchScraplingSettings settings,
  }) {
    return _runRuntimeCommandStreaming(
      settings: settings,
      command: const <String>['-m', 'pip', 'uninstall', '-y', 'scrapling'],
      tag: 'web_fetch_scrapling.uninstall',
      successMessage: 'Scrapling 运行时已移除。',
      failureCode: 'uninstall_failed',
      runtimeInstalledOnFailure: true,
      runtimeInstalledOnSuccess: false,
      successCode: 'scrapling_not_installed',
    );
  }

  Future<WebFetchScraplingProbeStatus> probe({
    required AiWebFetchScraplingSettings settings,
  }) {
    return _runExclusive(() async {
      final python = await _resolvePythonExecutable(settings);
      _throwIfDisposed();
      if (python == null) {
        return _lastProbe;
      }
      final previousProbe = _lastProbe;
      try {
        await _ensureReady(settings: settings, pythonExecutable: python);
        final response = await _sendCommand(
          command: <String, Object?>{'command': 'probe'},
          timeout: Duration(seconds: settings.startupTimeoutSeconds),
        );
        _lastProbe = _probeFromResponse(
          response,
          fallbackPython: python.displayName,
        );
        return _lastProbe;
      } catch (error, stack) {
        final reportedByRuntime =
            !identical(previousProbe, _lastProbe) && !_lastProbe.ready;
        if (!reportedByRuntime) {
          silentLog('web_fetch_scrapling_bridge', '探测运行时', error, stack);
        }
        await _killProcess();
        if (reportedByRuntime) return _lastProbe;
        return _lastProbe = WebFetchScraplingProbeStatus(
          ready: false,
          code: 'probe_failed',
          detail: '$error',
          pythonExecutable: python.displayName,
          updatedAt: DateTime.now().toUtc(),
        );
      }
    });
  }

  Future<WebFetchScraplingBridgeResult> fetch({
    required String url,
    required int maxChars,
    required AiWebFetchScraplingSettings settings,
    Future<void>? cancelSignal,
  }) async {
    final operation = _runExclusive(() async {
      if (await isCancelSignalCompleted(cancelSignal)) {
        throw WebEngineHttpException('cancelled');
      }
      final python = await _resolvePythonExecutable(settings);
      _throwIfDisposed();
      if (python == null) {
        throw WebEngineHttpException(_lastProbe.code);
      }
      await _ensureReady(settings: settings, pythonExecutable: python);
      if (await isCancelSignalCompleted(cancelSignal)) {
        throw WebEngineHttpException('cancelled');
      }
      final timeout = Duration(seconds: settings.requestTimeoutSeconds);
      final response = await _sendCommand(
        command: <String, Object?>{
          'command': 'fetch',
          'url': url,
          'max_chars': maxChars,
          'timeout_seconds': settings.requestTimeoutSeconds,
        },
        timeout: timeout,
        cancelSignal: cancelSignal,
      );
      if (response['ok'] != true) {
        final code = '${response['error'] ?? 'scrapling_fetch_failed'}';
        final detail = optionalStringFromValue(response['detail']) ?? code;
        _lastProbe = WebFetchScraplingProbeStatus(
          ready: false,
          code: code,
          detail: detail,
          pythonExecutable: python.displayName,
          updatedAt: DateTime.now().toUtc(),
          runtimeInstalled:
              code != 'scrapling_not_installed' &&
              code != 'scrapling_fetchers_missing',
        );
        if (_shouldRecycle(code)) {
          await _killProcess();
        }
        throw WebEngineHttpException('$code: $detail');
      }
      _lastProbe = WebFetchScraplingProbeStatus(
        ready: true,
        code: 'ready',
        detail: 'Scrapling 桥接已就绪。',
        pythonExecutable: python.displayName,
        updatedAt: DateTime.now().toUtc(),
        runtimeInstalled: true,
      );
      final rawHeaders = response['response_headers'];
      final headers = <String, String>{};
      if (rawHeaders is Map) {
        for (final entry in rawHeaders.entries) {
          headers['${entry.key}'.toLowerCase()] = '${entry.value}';
        }
      }
      final finalUrl = optionalStringFromValue(response['final_url']) ?? url;
      return WebFetchScraplingBridgeResult(
        url: finalUrl,
        title: '${response['title'] ?? ''}',
        content: '${response['content'] ?? ''}',
        contentType:
            '${response['content_type'] ?? headers[kContentTypeHeaderName] ?? kTextHtmlMimeType}',
        statusCode: webEngineHttpStatusFromValue(response['status_code']),
        responseHeaders: headers,
      );
    });
    final result = await awaitWithCancelSignal(
      operation,
      cancelSignal: cancelSignal,
    );
    if (result == null) throw WebEngineHttpException('cancelled');
    return result;
  }

  Future<void> reset() => _runExclusive(_killProcess);

  Future<void> dispose() {
    final active = _disposeFuture;
    if (active != null) return active;
    _disposed = true;
    return _disposeFuture = _finishDispose();
  }

  Future<void> _finishDispose() async {
    await Future.wait<void>(<Future<void>>[
      _killProcess(),
      _stopRuntimeCommandProcess(),
    ]);
    await runAsyncCleanupBounded(
      () => _operationQueue.idle,
      timeout: _defaultProcessStopTimeout + _defaultProcessKillTimeout,
      onError: (error, stack) => silentLog(
        'web_fetch_scrapling_bridge',
        '等待 Scrapling 操作队列结束',
        error,
        stack,
      ),
    );
    await Future.wait<void>(<Future<void>>[
      _killProcess(),
      _stopRuntimeCommandProcess(),
    ]);
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    if (_disposed) return Future<T>.error(_disposedError);
    return _operationQueue.enqueue(() {
      _throwIfDisposed();
      return action();
    });
  }

  StateError get _disposedError => StateError('Scrapling 桥接已关闭。');

  void _throwIfDisposed() {
    if (_disposed) throw _disposedError;
  }

  Future<_PythonLaunch?> _resolvePythonExecutable(
    AiWebFetchScraplingSettings settings,
  ) async {
    final custom = nullIfBlank(settings.pythonExecutable) ?? '';
    final current = _runtime;
    if (current != null &&
        !current.stopHandlingScheduled &&
        current.pythonExecutable.sourceKey == custom) {
      return current.pythonExecutable;
    }

    final candidates = custom.isNotEmpty
        ? <String>[custom]
        : <String>[
            'python3',
            if (Platform.isMacOS) ...<String>[
              '/Library/Frameworks/Python.framework/Versions/Current/bin/python3',
              '/opt/homebrew/bin/python3',
              '/usr/local/bin/python3',
              '/usr/bin/python3',
            ],
            'python',
          ];
    final seenCandidates = <String>{};
    final seenExecutables = <String>{};
    _PythonLaunch? missingDependencyFallback;
    _PythonProbeOutcome? firstFailure;
    for (final candidate in candidates) {
      if (!seenCandidates.add(candidate)) continue;
      final launch = _PythonLaunch(executable: candidate, sourceKey: custom);
      final outcome = await _probePythonRuntime(launch, settings);
      final actualExecutable = outcome.actualExecutable;
      if (actualExecutable != null && !seenExecutables.add(actualExecutable)) {
        continue;
      }
      if (outcome.ready) return outcome.launch;
      if (outcome.missingDependency) {
        missingDependencyFallback ??= outcome.launch;
        continue;
      }
      if (outcome.pythonStarted) firstFailure ??= outcome;
      if (Platform.isMacOS && outcome.hasArchitectureMismatch) {
        final executable = actualExecutable ?? candidate;
        for (final architecture in const <String>['arm64', 'x86_64']) {
          final architectureLaunch = _PythonLaunch(
            executable: '/usr/bin/arch',
            prefixArguments: <String>['-$architecture', executable],
            sourceKey: custom,
            displayName: '$executable ($architecture)',
          );
          final architectureOutcome = await _probePythonRuntime(
            architectureLaunch,
            settings,
          );
          if (architectureOutcome.ready) return architectureOutcome.launch;
          if (architectureOutcome.missingDependency) {
            missingDependencyFallback ??= architectureOutcome.launch;
          }
          if (architectureOutcome.pythonStarted) {
            firstFailure ??= architectureOutcome;
          }
        }
      }
    }
    if (missingDependencyFallback != null) return missingDependencyFallback;

    final failure = firstFailure;
    if (failure != null && failure.pythonStarted) {
      final unsupported = !failure.supported;
      _lastProbe = WebFetchScraplingProbeStatus(
        ready: false,
        code: unsupported
            ? 'python_version_unsupported'
            : 'python_runtime_incompatible',
        detail: unsupported
            ? 'Scrapling 需要 Python 3.10 或更高版本，当前为 ${failure.version ?? '未知版本'}。'
            : 'Python 运行时与已安装依赖不兼容：${clipTextWithEllipsis(failure.detail, _maxStderrTailLength)}',
        pythonExecutable: failure.launch.displayName,
        updatedAt: DateTime.now().toUtc(),
      );
    } else {
      _lastProbe = _pythonNotFoundProbeStatus();
    }
    return null;
  }

  Future<_PythonProbeOutcome> _probePythonRuntime(
    _PythonLaunch launch,
    AiWebFetchScraplingSettings settings,
  ) async {
    final configuredTimeout = Duration(seconds: settings.startupTimeoutSeconds);
    final result = await runTrackedProcessOrFailed(
      launch.executable,
      launch.arguments(<String>['-c', _pythonRuntimeProbeScript]),
      timeout: shorterDuration(configuredTimeout, _pythonProbeTimeout),
      tag: 'web_fetch_scrapling.python_probe',
      environment: _pythonEnvironment(),
    );
    Map<String, Object?>? payload;
    for (final line in '${result.stdout}'.split('\n').reversed) {
      final text = nullIfBlank(line);
      if (text == null) continue;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          payload = stringKeyedMapFromValue(decoded);
          break;
        }
      } catch (_) {
        // 部分依赖可能向标准输出写诊断信息，仅解析最后一条 JSON 状态。
      }
    }
    return _PythonProbeOutcome(
      launch: launch,
      exitCode: result.exitCode,
      payload: payload,
      stderr: '${result.stderr}',
    );
  }

  Map<String, String> _pythonEnvironment([Map<String, String>? additions]) {
    return <String, String>{
      ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
      'PIP_DISABLE_PIP_VERSION_CHECK': '1',
      ...?additions,
    };
  }

  Future<void> _ensureReady({
    required AiWebFetchScraplingSettings settings,
    required _PythonLaunch pythonExecutable,
  }) async {
    _throwIfDisposed();
    final startupTimeout = Duration(seconds: settings.startupTimeoutSeconds);
    final current = _runtime;
    if (current != null &&
        !current.stopHandlingScheduled &&
        current.pythonExecutable.commandKey == pythonExecutable.commandKey) {
      try {
        await current.ready.future.timeout(startupTimeout);
        _throwIfDisposed();
        if (!identical(_runtime, current)) {
          throw WebEngineHttpException('scrapling_bridge_restarted');
        }
        return;
      } catch (error, stack) {
        await _cleanupRuntime(current, cause: error, stackTrace: stack);
        Error.throwWithStackTrace(error, stack);
      }
    }

    if (current != null) {
      await _cleanupRuntime(
        current,
        cause: WebEngineHttpException('scrapling_bridge_restarted'),
        stackTrace: StackTrace.current,
      );
    }

    _ScraplingProcessRuntime? startedRuntime;
    try {
      final helperPath = await _ensureHelperScriptWritten();
      _throwIfDisposed();
      final startupStopwatch = Stopwatch()..start();
      final process = await _startBridgeProcess(
        pythonExecutable: pythonExecutable,
        helperPath: helperPath,
        timeout: nonNegativeDuration(startupTimeout - startupStopwatch.elapsed),
      );
      if (_disposed) {
        await _disposeUnclaimedProcess(process);
        throw _disposedError;
      }
      final runtime = _ScraplingProcessRuntime(
        process: process,
        pythonExecutable: pythonExecutable,
      );
      startedRuntime = runtime;
      _runtime = runtime;
      _listenToRuntime(runtime);
      _throwIfDisposed();
      await runtime.ready.future.timeout(
        nonNegativeDuration(startupTimeout - startupStopwatch.elapsed),
      );
      _throwIfDisposed();
      if (!identical(_runtime, runtime)) {
        throw WebEngineHttpException('scrapling_bridge_restarted');
      }
    } catch (error, stack) {
      final runtime = startedRuntime;
      if (runtime != null) {
        await _cleanupRuntime(runtime, cause: error, stackTrace: stack);
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<Process> _startBridgeProcess({
    required _PythonLaunch pythonExecutable,
    required String helperPath,
    required Duration timeout,
  }) async {
    if (timeout <= Duration.zero) throw _BridgeProcessStartTimeout(timeout);
    try {
      return await startTrackedProcessBounded(
        pythonExecutable.executable,
        pythonExecutable.arguments(<String>['-u', helperPath]),
        timeout: timeout,
        tag: 'web_fetch_scrapling_bridge',
        startInNewProcessGroup: true,
        workingDirectory: OpenHandPaths.applicationDirectoryPath(),
        environment: _pythonEnvironment(),
      );
    } on TimeoutException {
      throw _BridgeProcessStartTimeout(timeout);
    }
  }

  Future<void> _disposeUnclaimedProcess(Process process) async {
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    StreamSubscription<List<int>>? stdoutSubscription;
    StreamSubscription<List<int>>? stderrSubscription;

    void complete(Completer<void> completer) {
      if (!completer.isCompleted) completer.complete();
    }

    try {
      final drainTimeout =
          _defaultProcessStopTimeout + _defaultProcessKillTimeout;
      stdoutSubscription = process.stdout.listen(
        (_) {},
        onError: (Object error, StackTrace stack) {
          complete(stdoutDone);
          silentLog('web_fetch_scrapling_bridge', '读取延迟进程标准输出', error, stack);
        },
        onDone: () => complete(stdoutDone),
      );
      stderrSubscription = process.stderr.listen(
        (_) {},
        onError: (Object error, StackTrace stack) {
          complete(stderrDone);
          silentLog('web_fetch_scrapling_bridge', '读取延迟进程标准错误', error, stack);
        },
        onDone: () => complete(stderrDone),
      );
      await Future.wait<void>(<Future<void>>[
        _terminateRuntimeProcess(process),
        _closeRuntimeStdin(process.stdin),
      ]);
      try {
        await Future.wait<void>([
          stdoutDone.future,
          stderrDone.future,
        ]).timeout(drainTimeout);
      } on TimeoutException catch (error, stack) {
        silentLog('web_fetch_scrapling_bridge', '排空延迟进程输出流', error, stack);
      }
    } catch (error, stack) {
      silentLog('web_fetch_scrapling_bridge', '释放延迟进程', error, stack);
    } finally {
      await Future.wait<void>(<Future<void>>[
        _cancelRuntimeSubscription(stdoutSubscription, '延迟进程标准输出'),
        _cancelRuntimeSubscription(stderrSubscription, '延迟进程标准错误'),
      ]);
    }
  }

  void _listenToRuntime(_ScraplingProcessRuntime runtime) {
    final stdoutDecoder = BoundedProcessLineDecoder(
      maxCharacters: _maxBridgeResponseLineCharacters,
      onLine: (line) => _handleRuntimeStdoutLine(runtime, line),
    );
    runtime.stdoutSubscription = runtime.process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          stdoutDecoder.add,
          onError: (Object error, StackTrace stack) {
            stdoutDecoder.close();
            if (!identical(_runtime, runtime)) return;
            silentLog('web_fetch_scrapling_bridge', '读取标准输出', error, stack);
            _handleRuntimeFailure(runtime, error, stack);
          },
          onDone: () {
            stdoutDecoder.close();
            if (!identical(_runtime, runtime)) return;
            _scheduleRuntimeStopped(runtime);
          },
        );
    final stderrDecoder = BoundedProcessLineDecoder(
      maxCharacters: _maxRuntimeLineCharacters,
      onLine: (line) {
        if (!identical(_runtime, runtime)) return;
        final trimmed = nullIfBlank(line);
        if (trimmed == null) return;
        runtime.stderrTail = trimmed.length > _maxStderrTailLength
            ? trimmed.substring(
                safeUtf16SuffixStart(
                  trimmed,
                  trimmed.length - _maxStderrTailLength,
                ),
              )
            : trimmed;
      },
    );
    runtime.stderrSubscription = runtime.process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          stderrDecoder.add,
          onError: (Object error, StackTrace stack) {
            stderrDecoder.close();
            if (!runtime.stderrDone.isCompleted) {
              runtime.stderrDone.complete();
            }
            if (!identical(_runtime, runtime)) return;
            silentLog('web_fetch_scrapling_bridge', '读取标准错误', error, stack);
            _handleRuntimeFailure(runtime, error, stack);
          },
          onDone: () {
            stderrDecoder.close();
            if (!runtime.stderrDone.isCompleted) {
              runtime.stderrDone.complete();
            }
          },
        );
    unawaited(_watchRuntimeExit(runtime));
  }

  void _handleRuntimeStdoutLine(_ScraplingProcessRuntime runtime, String line) {
    if (!identical(_runtime, runtime) || nullIfBlank(line) == null) return;
    Map<String, Object?> json;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return;
      json = stringKeyedMapFromValue(decoded);
    } catch (_) {
      return;
    }
    if (json['type'] == 'ready') {
      _lastProbe = _probeFromResponse(
        json,
        fallbackPython: runtime.pythonExecutable.displayName,
      );
      if (_lastProbe.ready) {
        if (!runtime.ready.isCompleted) runtime.ready.complete();
      } else if (!runtime.ready.isCompleted) {
        runtime.ready.completeError(
          WebEngineHttpException('${_lastProbe.code}: ${_lastProbe.detail}'),
        );
      }
      return;
    }
    final id = optionalStringFromValue(json['id']) ?? '';
    final pending = runtime.pending.remove(id);
    if (pending != null && !pending.isCompleted) {
      pending.complete(json);
    }
  }

  Future<void> _watchRuntimeExit(_ScraplingProcessRuntime runtime) async {
    try {
      await runtime.process.exitCode;
      if (!identical(_runtime, runtime)) return;
      _scheduleRuntimeStopped(runtime);
    } catch (error, stack) {
      if (!identical(_runtime, runtime)) return;
      silentLog('web_fetch_scrapling_bridge', '读取退出码', error, stack);
      _handleRuntimeFailure(runtime, error, stack);
    }
  }

  void _scheduleRuntimeStopped(_ScraplingProcessRuntime runtime) {
    if (!identical(_runtime, runtime) || runtime.stopHandlingScheduled) return;
    runtime.stopHandlingScheduled = true;
    unawaited(_finishRuntimeStopped(runtime));
  }

  Future<void> _finishRuntimeStopped(_ScraplingProcessRuntime runtime) async {
    try {
      await runtime.stderrDone.future.timeout(_defaultProcessKillTimeout);
    } on TimeoutException {
      // 保留已缓冲的标准错误，同时避免异常管道阻塞清理。
    }
    if (!identical(_runtime, runtime)) return;
    _handleRuntimeFailure(
      runtime,
      _runtimeStoppedError(runtime),
      StackTrace.current,
    );
  }

  void _handleRuntimeFailure(
    _ScraplingProcessRuntime runtime,
    Object error,
    StackTrace stack,
  ) {
    if (!identical(_runtime, runtime)) return;
    if (!runtime.ready.isCompleted) {
      runtime.ready.completeError(error, stack);
    }
    _failPending(runtime, error, stack);
    unawaited(_cleanupRuntime(runtime, cause: error, stackTrace: stack));
  }

  WebEngineHttpException _runtimeStoppedError(
    _ScraplingProcessRuntime runtime,
  ) {
    return WebEngineHttpException(
      runtime.stderrTail.isEmpty
          ? 'scrapling_bridge_stopped'
          : 'scrapling_bridge_stopped: ${runtime.stderrTail}',
    );
  }

  WebFetchScraplingProbeStatus _probeFromResponse(
    Map<String, Object?> response, {
    required String fallbackPython,
  }) {
    final ok = response['ok'] == true;
    final code = ok ? 'ready' : '${response['error'] ?? 'scrapling_not_ready'}';
    final detail = ok
        ? 'Scrapling 桥接已就绪。'
        : optionalStringFromValue(response['detail']) ?? code;
    return WebFetchScraplingProbeStatus(
      ready: ok,
      code: code,
      detail: detail,
      pythonExecutable: '${response['python'] ?? fallbackPython}',
      updatedAt: DateTime.now().toUtc(),
      runtimeInstalled: response['runtime_installed'] == true || ok,
    );
  }

  WebFetchScraplingProbeStatus _pythonNotFoundProbeStatus() {
    return WebFetchScraplingProbeStatus(
      ready: false,
      code: _pythonNotFoundCode,
      detail: _pythonNotFoundDetail,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  bool _shouldRecycle(String code) {
    return code == 'bridge_exception' ||
        code == 'scrapling_bridge_stopped' ||
        code == 'python_architecture_mismatch' ||
        code == 'scrapling_fetchers_missing' ||
        code == 'scrapling_not_installed';
  }

  Future<Map<String, Object?>> _sendCommand({
    required Map<String, Object?> command,
    required Duration timeout,
    Future<void>? cancelSignal,
  }) async {
    _throwIfDisposed();
    final runtime = _runtime;
    if (runtime == null) {
      throw WebEngineHttpException('scrapling_bridge_not_running');
    }
    final id = 'req_${++_requestSeq}';
    final payload = <String, Object?>{'id': id, ...command};
    final completer = Completer<Map<String, Object?>>();
    runtime.pending[id] = completer;
    try {
      runtime.process.stdin.writeln(jsonEncode(payload));
      final commandOutcome = Future.any<Object?>([
        completer.future,
        Future<void>.delayed(
          timeout,
        ).then<Object?>((_) => const _TimeoutToken()),
      ]);
      final result = await awaitWithCancelSignal(
        commandOutcome,
        cancelSignal: cancelSignal,
      );
      if (result is _TimeoutToken) {
        runtime.pending.remove(id);
        final error = WebEngineHttpException('scrapling_bridge_timeout');
        await _cleanupRuntime(
          runtime,
          cause: error,
          stackTrace: StackTrace.current,
        );
        throw error;
      }
      if (result == null) {
        runtime.pending.remove(id);
        final error = WebEngineHttpException('cancelled');
        await _cleanupRuntime(
          runtime,
          cause: error,
          stackTrace: StackTrace.current,
        );
        throw error;
      }
      return result as Map<String, Object?>;
    } on StateError catch (_, stack) {
      runtime.pending.remove(id);
      final error = WebEngineHttpException('scrapling_bridge_stdin_closed');
      await _cleanupRuntime(runtime, cause: error, stackTrace: stack);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Stream<WebFetchScraplingRuntimeEvent> _runRuntimeCommandStreaming({
    required AiWebFetchScraplingSettings settings,
    required List<String> command,
    required String tag,
    required String successMessage,
    required String failureCode,
    String successCode = 'ready',
    bool runtimeInstalledOnFailure = false,
    bool runtimeInstalledOnSuccess = true,
  }) {
    late final StreamController<WebFetchScraplingRuntimeEvent> controller;
    final cancellation = _RuntimeCommandCancellation();
    var started = false;
    var cancelled = false;

    Future<void> run() async {
      try {
        await _runExclusive(() async {
          if (cancellation.isCancelled) return;
          await for (final event in _runRuntimeCommandStreamingExclusive(
            settings: settings,
            command: command,
            tag: tag,
            successMessage: successMessage,
            failureCode: failureCode,
            successCode: successCode,
            runtimeInstalledOnFailure: runtimeInstalledOnFailure,
            runtimeInstalledOnSuccess: runtimeInstalledOnSuccess,
            cancellation: cancellation,
          )) {
            if (!cancelled && !controller.isClosed) controller.add(event);
          }
        });
      } catch (error, stack) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(error, stack);
        }
      } finally {
        // 暂停的监听者可能延迟接收 done，不能反向阻塞生产任务结束。
        if (!controller.isClosed) unawaited(controller.close());
      }
    }

    controller = StreamController<WebFetchScraplingRuntimeEvent>(
      onListen: () {
        if (started) return;
        started = true;
        unawaited(run());
      },
      onCancel: () {
        cancelled = true;
        return cancellation.cancel();
      },
    );
    return controller.stream;
  }

  Stream<WebFetchScraplingRuntimeEvent> _runRuntimeCommandStreamingExclusive({
    required AiWebFetchScraplingSettings settings,
    required List<String> command,
    required String tag,
    required String successMessage,
    required String failureCode,
    required String successCode,
    required bool runtimeInstalledOnFailure,
    required bool runtimeInstalledOnSuccess,
    required _RuntimeCommandCancellation cancellation,
  }) async* {
    if (cancellation.isCancelled) return;
    final python = await _resolvePythonExecutable(settings);
    if (cancellation.isCancelled) return;
    _throwIfDisposed();
    if (python == null) {
      throw WebEngineHttpException(_lastProbe.code);
    }

    await _killProcess();
    if (cancellation.isCancelled) return;
    _throwIfDisposed();
    yield const WebFetchScraplingRuntimeEvent(
      type: WebFetchScraplingRuntimeEventType.status,
      line: '正在准备运行时命令……',
    );
    yield WebFetchScraplingRuntimeEvent(
      type: WebFetchScraplingRuntimeEventType.command,
      line: '> ${python.commandDisplay(command)}',
    );

    var attempt = await _runRuntimeAttempt(
      python: python,
      command: command,
      timeoutSeconds: settings.installTimeoutSeconds,
      tag: tag,
      cancellation: cancellation,
    );
    if (cancellation.isCancelled) return;
    _throwIfDisposed();
    for (final event in attempt.events) {
      yield event;
    }

    final tlsBundle = await _detectTlsBundle(attempt, python);
    if (cancellation.isCancelled) return;
    _throwIfDisposed();
    if (!attempt.succeeded && tlsBundle != null) {
      yield WebFetchScraplingRuntimeEvent(
        type: WebFetchScraplingRuntimeEventType.status,
        line: '检测到 TLS 证书校验失败，正在使用 CA 证书包重试：$tlsBundle',
      );
      attempt = await _runRuntimeAttempt(
        python: python,
        command: command,
        timeoutSeconds: settings.installTimeoutSeconds,
        tag: '$tag.ca_retry',
        cancellation: cancellation,
        environment: <String, String>{
          'PIP_CERT': tlsBundle,
          'SSL_CERT_FILE': tlsBundle,
          'REQUESTS_CA_BUNDLE': tlsBundle,
          'CURL_CA_BUNDLE': tlsBundle,
        },
      );
      if (cancellation.isCancelled) return;
      _throwIfDisposed();
      for (final event in attempt.events) {
        yield event;
      }
    }

    if (attempt.succeeded) {
      _lastProbe = WebFetchScraplingProbeStatus(
        ready: runtimeInstalledOnSuccess,
        code: successCode,
        detail: successMessage,
        pythonExecutable: python.displayName,
        updatedAt: DateTime.now().toUtc(),
        runtimeInstalled: runtimeInstalledOnSuccess,
      );
      yield WebFetchScraplingRuntimeEvent(
        type: WebFetchScraplingRuntimeEventType.success,
        line: successMessage,
      );
      return;
    }

    final detail = _summarizeRuntimeFailure(attempt);
    _lastProbe = WebFetchScraplingProbeStatus(
      ready: false,
      code: failureCode,
      detail: detail,
      pythonExecutable: python.displayName,
      updatedAt: DateTime.now().toUtc(),
      runtimeInstalled: runtimeInstalledOnFailure,
    );
    yield WebFetchScraplingRuntimeEvent(
      type: WebFetchScraplingRuntimeEventType.warning,
      line: detail,
    );
    throw WebEngineHttpException('$failureCode: $detail');
  }

  Future<_RuntimeAttemptResult> _runRuntimeAttempt({
    required _PythonLaunch python,
    required List<String> command,
    required int timeoutSeconds,
    required String tag,
    required _RuntimeCommandCancellation cancellation,
    Map<String, String>? environment,
  }) async {
    final events = ListQueue<WebFetchScraplingRuntimeEvent>();
    Process? attemptProcess;

    void recordEvent(WebFetchScraplingRuntimeEventType type, String line) {
      if (events.length >= _maxRuntimeEvents) events.removeFirst();
      events.add(
        WebFetchScraplingRuntimeEvent(
          type: type,
          line: clipTextWithEllipsis(line, _maxRuntimeLineCharacters),
        ),
      );
    }

    try {
      final timeout = Duration(seconds: timeoutSeconds);
      final workingDirectory = OpenHandPaths.applicationDirectoryPath();
      final result = await runTrackedProcessWithLineLogging(
        python.executable,
        python.arguments(command),
        timeout: timeout,
        tag: tag,
        workingDirectory: workingDirectory,
        environment: _pythonEnvironment(environment),
        onStdoutLine: (line) =>
            recordEvent(WebFetchScraplingRuntimeEventType.stdout, line),
        onStderrLine: (line) =>
            recordEvent(WebFetchScraplingRuntimeEventType.stderr, line),
        onProcessStarted: (process) {
          attemptProcess = process;
          _runtimeCommandProcess = process;
          cancellation.attach(process);
          if (_disposed) unawaited(_stopRuntimeCommandProcess());
        },
        streamDrainTimeout: _defaultProcessKillTimeout,
        gracefulTerminationTimeout: _defaultProcessStopTimeout,
        maxCapturedLinesPerStream: _maxCapturedRuntimeLinesPerStream,
      );
      if (result.timedOut) {
        recordEvent(WebFetchScraplingRuntimeEventType.warning, '进程执行超时。');
      } else {
        recordEvent(
          result.exitCode == 0
              ? WebFetchScraplingRuntimeEventType.status
              : WebFetchScraplingRuntimeEventType.warning,
          '进程已退出，退出码 ${result.exitCode}。',
        );
      }
      const maxCapturedCharacters =
          _maxCapturedRuntimeLinesPerStream * (_maxRuntimeLineCharacters + 1);
      return _RuntimeAttemptResult(
        succeeded: !result.timedOut && result.exitCode == 0,
        exitCode: result.exitCode,
        stdout: clipText(result.stdout, maxCapturedCharacters, suffix: ''),
        stderr: clipText(result.stderr, maxCapturedCharacters, suffix: ''),
        events: List<WebFetchScraplingRuntimeEvent>.unmodifiable(events),
        timedOut: result.timedOut,
      );
    } catch (error, stack) {
      silentLog('web_fetch_scrapling_bridge', '执行运行时命令：$tag', error, stack);
      recordEvent(WebFetchScraplingRuntimeEventType.stderr, '$error');
      return _RuntimeAttemptResult(
        succeeded: false,
        exitCode: -1,
        stdout: '',
        stderr: clipText('$error', _maxRuntimeLineCharacters, suffix: ''),
        events: List<WebFetchScraplingRuntimeEvent>.unmodifiable(events),
      );
    } finally {
      final process = attemptProcess;
      if (process != null) cancellation.detach(process);
      if (process != null && identical(_runtimeCommandProcess, process)) {
        _runtimeCommandProcess = null;
      }
    }
  }

  Future<String?> _detectTlsBundle(
    _RuntimeAttemptResult result,
    _PythonLaunch python,
  ) async {
    final combined = '${result.stdout}\n${result.stderr}'.toLowerCase();
    if (!combined.contains('certificate_verify_failed')) return null;
    final certifi = await _probeCertifiBundle(python);
    if (certifi != null &&
        await isRegularFilePath(
          certifi,
          timeout: _tlsBundleProbeTimeout,
          followLinks: true,
        )) {
      return certifi;
    }
    for (final candidate in <String>[
      '/etc/ssl/cert.pem',
      '/private/etc/ssl/cert.pem',
      '/etc/ssl/certs/ca-certificates.crt',
      '/opt/homebrew/etc/openssl@3/cert.pem',
    ]) {
      if (await isRegularFilePath(
        candidate,
        timeout: _tlsBundleProbeTimeout,
        followLinks: true,
      )) {
        return candidate;
      }
    }
    return null;
  }

  Future<String?> _probeCertifiBundle(_PythonLaunch python) async {
    try {
      final result = await runTrackedProcessOrFailed(
        python.executable,
        python.arguments(const <String>[
          '-c',
          'import certifi; print(certifi.where())',
        ]),
        timeout: const Duration(seconds: 2),
        tag: 'web_fetch_scrapling_bridge.probe_certifi',
        environment: _pythonEnvironment(),
      );
      if (result.exitCode == 0) {
        return optionalStringFromValue(result.stdout);
      }
    } catch (error, stack) {
      silentLog('web_fetch_scrapling_bridge', '探测 certifi 证书包', error, stack);
    }
    return null;
  }

  String _summarizeRuntimeFailure(_RuntimeAttemptResult result) {
    final combined = '${result.stdout}\n${result.stderr}'.toLowerCase();
    if (result.timedOut) {
      return '运行时命令执行超时。';
    }
    if (combined.contains('certificate_verify_failed')) {
      return '访问 PyPI 时 TLS 证书校验失败。请检查 Python CA 证书、代理拦截证书或 pip 证书包配置。';
    }
    if (combined.contains('no matching distribution found')) {
      return 'pip 无法解析请求的软件包版本。';
    }
    if (combined.contains('could not fetch url')) {
      return 'pip 无法从 PyPI 获取软件包元数据。';
    }
    return '进程退出码：${result.exitCode}。';
  }

  Future<String> _ensureHelperScriptWritten() async {
    final existingPath = _helperPath;
    if (existingPath != null && await isRegularFilePath(existingPath)) {
      return existingPath;
    }
    _helperPath = null;
    final bytes = await rootBundle.load(_assetPath);
    final dir = Directory(
      p.join(
        OpenHandPaths.defaultCacheDirectoryPath(),
        'web_fetch',
        'scrapling',
      ),
    );
    final file = File(p.join(dir.path, 'bridge.py'));
    await writeBytesFileAtomically(file, bytes.buffer.asUint8List());
    if (!Platform.isWindows) {
      try {
        final result = await runTrackedProcessOrFailed(
          'chmod',
          <String>['700', file.path],
          timeout: const Duration(seconds: 2),
          tag: 'web_fetch_scrapling_bridge.chmod_helper',
        );
        if (result.exitCode != 0) {
          silentLog(
            'web_fetch_scrapling_bridge',
            '设置辅助脚本权限',
            '退出码 ${result.exitCode}：${result.stderr}',
          );
        }
      } catch (error, stack) {
        silentLog('web_fetch_scrapling_bridge', '设置辅助脚本权限', error, stack);
      }
    }
    _helperPath = file.path;
    return file.path;
  }

  void _failPending(
    _ScraplingProcessRuntime runtime,
    Object error,
    StackTrace stack,
  ) {
    final pending = List<Completer<Map<String, Object?>>>.from(
      runtime.pending.values,
    );
    runtime.pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    }
  }

  Future<void> _killProcess() async {
    final runtime = _runtime;
    if (runtime == null) return;
    await _cleanupRuntime(
      runtime,
      cause: WebEngineHttpException('scrapling_bridge_restarted'),
      stackTrace: StackTrace.current,
    );
  }

  Future<void> _stopRuntimeCommandProcess() async {
    final process = _runtimeCommandProcess;
    if (process == null) return;
    _runtimeCommandProcess = null;
    try {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: _defaultProcessStopTimeout,
      );
    } catch (error, stack) {
      silentLog('web_fetch_scrapling_bridge', '停止运行时命令进程', error, stack);
    }
  }

  Future<void> _cleanupRuntime(
    _ScraplingProcessRuntime runtime, {
    required Object cause,
    required StackTrace stackTrace,
  }) {
    final existingCleanup = runtime.cleanupFuture;
    if (existingCleanup != null) return existingCleanup;

    final completer = Completer<void>();
    runtime.cleanupFuture = completer.future;
    unawaited(() async {
      try {
        await _performRuntimeCleanup(
          runtime,
          cause: cause,
          stackTrace: stackTrace,
        );
      } catch (error, stack) {
        silentLog('web_fetch_scrapling_bridge', '清理运行时', error, stack);
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    }());
    return completer.future;
  }

  Future<void> _performRuntimeCleanup(
    _ScraplingProcessRuntime runtime, {
    required Object cause,
    required StackTrace stackTrace,
  }) async {
    if (identical(_runtime, runtime)) {
      _runtime = null;
    }
    if (!runtime.ready.isCompleted) {
      runtime.ready.completeError(cause, stackTrace);
    }
    _failPending(runtime, cause, stackTrace);

    final stdoutSubscription = runtime.stdoutSubscription;
    final stderrSubscription = runtime.stderrSubscription;
    runtime.stdoutSubscription = null;
    runtime.stderrSubscription = null;
    await Future.wait<void>(<Future<void>>[
      _cancelRuntimeSubscription(stdoutSubscription, '标准输出'),
      _cancelRuntimeSubscription(stderrSubscription, '标准错误'),
    ]);
    if (!runtime.stderrDone.isCompleted) {
      runtime.stderrDone.complete();
    }
    await Future.wait<void>(<Future<void>>[
      _terminateRuntimeProcess(runtime.process),
      _closeRuntimeStdin(runtime.process.stdin),
    ]);
  }

  Future<void> _cancelRuntimeSubscription<T>(
    StreamSubscription<T>? subscription,
    String streamName,
  ) async {
    await cancelStreamSubscriptionBounded<T>(
      subscription,
      timeout: _defaultProcessKillTimeout,
      onError: (error, stack) => silentLog(
        'web_fetch_scrapling_bridge',
        '取消 $streamName 订阅',
        error,
        stack,
      ),
    );
  }

  Future<void> _terminateRuntimeProcess(Process process) async {
    try {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: _defaultProcessStopTimeout,
      );
    } catch (error, stack) {
      silentLog('web_fetch_scrapling_bridge', '终止进程树', error, stack);
    }
    if (await _waitForProcessExit(process, _defaultProcessKillTimeout)) return;
    silentLog(
      'web_fetch_scrapling_bridge',
      '等待进程树终止',
      TimeoutException('进程树终止后 Scrapling 桥接仍未退出。', _defaultProcessKillTimeout),
    );
  }

  Future<bool> _waitForProcessExit(Process process, Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (error, stack) {
      silentLog('web_fetch_scrapling_bridge', '等待进程退出', error, stack);
      return false;
    }
  }

  Future<void> _closeRuntimeStdin(IOSink stdin) async {
    try {
      await stdin.close().timeout(_defaultProcessKillTimeout);
    } catch (error, stack) {
      silentLog('web_fetch_scrapling_bridge', '关闭进程标准输入', error, stack);
    }
  }
}

class _ScraplingProcessRuntime {
  _ScraplingProcessRuntime({
    required this.process,
    required this.pythonExecutable,
  });

  final Process process;
  final _PythonLaunch pythonExecutable;
  final Completer<void> ready = Completer<void>();
  final Completer<void> stderrDone = Completer<void>();
  final Map<String, Completer<Map<String, Object?>>> pending =
      <String, Completer<Map<String, Object?>>>{};
  StreamSubscription<String>? stdoutSubscription;
  StreamSubscription<String>? stderrSubscription;
  String stderrTail = '';
  bool stopHandlingScheduled = false;
  Future<void>? cleanupFuture;
}

class _PythonLaunch {
  const _PythonLaunch({
    required this.executable,
    required this.sourceKey,
    this.prefixArguments = const <String>[],
    this._displayName,
  });

  final String executable;
  final String sourceKey;
  final List<String> prefixArguments;
  final String? _displayName;

  String get displayName => _displayName ?? executable;
  String get commandKey => <String>[executable, ...prefixArguments].join('\n');

  List<String> arguments(List<String> command) => <String>[
    ...prefixArguments,
    '-E',
    '-X',
    'utf8',
    ...command,
  ];

  String commandDisplay(List<String> command) =>
      <String>[executable, ...arguments(command)].join(' ');
}

class _PythonProbeOutcome {
  const _PythonProbeOutcome({
    required this.launch,
    required this.exitCode,
    required this.payload,
    required this.stderr,
  });

  final _PythonLaunch launch;
  final int exitCode;
  final Map<String, Object?>? payload;
  final String stderr;

  bool get pythonStarted => payload != null;
  bool get supported => payload?['supported'] == true;
  bool get ready => supported && payload?['ready'] == true;
  bool get missingDependency =>
      supported && nullIfBlank('${payload?['missing'] ?? ''}') != null;
  String? get actualExecutable =>
      optionalStringFromValue(payload?['executable']);
  String? get version => optionalStringFromValue(payload?['version']);
  String get detail =>
      optionalStringFromValue(payload?['error']) ??
      nullIfBlank(stderr) ??
      'Python 探测进程退出码：$exitCode';
  bool get hasArchitectureMismatch {
    final text = detail.toLowerCase();
    return text.contains('incompatible architecture') ||
        text.contains('wrong architecture') ||
        text.contains('mach-o');
  }
}

class _RuntimeCommandCancellation {
  Process? _process;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void attach(Process process) {
    _process = process;
    if (_cancelled) unawaited(_terminate(process));
  }

  void detach(Process process) {
    if (identical(_process, process)) _process = null;
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    final process = _process;
    if (process != null) await _terminate(process);
  }

  Future<void> _terminate(Process process) async {
    try {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: WebFetchScraplingBridge._defaultProcessStopTimeout,
      );
    } catch (error, stack) {
      silentLog('web_fetch_scrapling_bridge', '取消运行时命令', error, stack);
    }
  }
}

class _RuntimeAttemptResult {
  const _RuntimeAttemptResult({
    required this.succeeded,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.events,
    this.timedOut = false,
  });

  final bool succeeded;
  final int exitCode;
  final String stdout;
  final String stderr;
  final List<WebFetchScraplingRuntimeEvent> events;
  final bool timedOut;
}

class _TimeoutToken {
  const _TimeoutToken();
}

class _BridgeProcessStartTimeout extends TimeoutException {
  _BridgeProcessStartTimeout(Duration duration)
    : super('Scrapling 桥接进程启动超时。', duration);
}

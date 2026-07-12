import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../web_engine/web_engine_http_exception.dart';
import 'web_fetch_value_parsing.dart';

enum WebFetchScraplingRuntimeEventType {
  command,
  status,
  stdout,
  stderr,
  success,
  warning,
}

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
  WebFetchScraplingBridge() : this.withDependencies();

  WebFetchScraplingBridge.withDependencies({
    Future<String?> Function(AiWebFetchScraplingSettings settings)?
    pythonExecutableResolver,
    Future<String> Function()? helperPathProvider,
    Future<Process> Function(String pythonExecutable, String helperPath)?
    processStarter,
    Duration? startupTimeoutOverride,
    Duration processStopTimeout = _defaultProcessStopTimeout,
    Duration processKillTimeout = _defaultProcessKillTimeout,
  }) : _pythonExecutableResolver = pythonExecutableResolver,
       _helperPathProvider = helperPathProvider,
       _processStarter = processStarter,
       _startupTimeoutOverride = startupTimeoutOverride,
       _processStopTimeout = processStopTimeout,
       _processKillTimeout = processKillTimeout {
    if (startupTimeoutOverride?.isNegative ?? false) {
      throw ArgumentError.value(
        startupTimeoutOverride,
        'startupTimeoutOverride',
        'Must not be negative.',
      );
    }
    if (processStopTimeout.isNegative) {
      throw ArgumentError.value(
        processStopTimeout,
        'processStopTimeout',
        'Must not be negative.',
      );
    }
    if (processKillTimeout.isNegative) {
      throw ArgumentError.value(
        processKillTimeout,
        'processKillTimeout',
        'Must not be negative.',
      );
    }
  }

  static const String _assetPath =
      'assets/tooling/webfetch_scrapling_bridge.py';
  static const String _pythonNotFoundCode = 'python_not_found';
  static const String _pythonNotFoundDetail =
      'Python 3 not found. Install Python 3.10+ or set a custom executable path.';
  static const Duration _defaultProcessStopTimeout = Duration(seconds: 2);
  static const Duration _defaultProcessKillTimeout = Duration(
    milliseconds: 250,
  );
  static const int _maxStderrTailLength = 800;

  final Future<String?> Function(AiWebFetchScraplingSettings settings)?
  _pythonExecutableResolver;
  final Future<String> Function()? _helperPathProvider;
  final Future<Process> Function(String pythonExecutable, String helperPath)?
  _processStarter;
  final Duration? _startupTimeoutOverride;
  final Duration _processStopTimeout;
  final Duration _processKillTimeout;

  _ScraplingProcessRuntime? _runtime;
  Future<void> _serial = Future<void>.value();
  String? _helperPath;
  int _requestSeq = 0;
  WebFetchScraplingProbeStatus _lastProbe = const WebFetchScraplingProbeStatus(
    ready: false,
    code: 'not_started',
    detail: 'Scrapling bridge not started.',
  );
  WebFetchScraplingProbeStatus get lastProbe => _lastProbe;

  Stream<WebFetchScraplingRuntimeEvent> installRuntimeStreaming({
    required AiWebFetchScraplingSettings settings,
  }) {
    return _runRuntimeCommandStreaming(
      settings: settings,
      command: const <String>['-m', 'pip', 'install', 'scrapling[fetchers]'],
      tag: 'web_fetch_scrapling.install',
      successMessage: '✓ Scrapling runtime installed.',
      failureCode: 'install_failed',
    );
  }

  Future<void> installRuntime({
    required AiWebFetchScraplingSettings settings,
  }) async {
    await for (final _ in installRuntimeStreaming(settings: settings)) {}
  }

  Stream<WebFetchScraplingRuntimeEvent> uninstallRuntimeStreaming({
    required AiWebFetchScraplingSettings settings,
  }) {
    return _runRuntimeCommandStreaming(
      settings: settings,
      command: const <String>['-m', 'pip', 'uninstall', '-y', 'scrapling'],
      tag: 'web_fetch_scrapling.uninstall',
      successMessage: '✓ Scrapling runtime removed.',
      failureCode: 'uninstall_failed',
      runtimeInstalledOnFailure: true,
      runtimeInstalledOnSuccess: false,
      successCode: 'scrapling_not_installed',
    );
  }

  Future<void> uninstallRuntime({
    required AiWebFetchScraplingSettings settings,
  }) async {
    await for (final _ in uninstallRuntimeStreaming(settings: settings)) {}
  }

  Future<WebFetchScraplingProbeStatus> probe({
    required AiWebFetchScraplingSettings settings,
  }) {
    return _runExclusive(() async {
      final python = await _resolvePythonExecutable(settings);
      if (python == null) {
        return _lastProbe = _pythonNotFoundProbeStatus();
      }
      try {
        await _ensureReady(settings: settings, pythonExecutable: python);
        final response = await _sendCommand(
          command: <String, Object?>{'command': 'probe'},
          timeout: Duration(seconds: settings.startupTimeoutSeconds),
        );
        _lastProbe = _probeFromResponse(response, fallbackPython: python);
        return _lastProbe;
      } catch (error, stack) {
        silentLog('web_fetch_scrapling_bridge', 'probe', error, stack);
        await _killProcess();
        return _lastProbe = WebFetchScraplingProbeStatus(
          ready: false,
          code: 'probe_failed',
          detail: '$error',
          pythonExecutable: python,
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
  }) {
    return _runExclusive(() async {
      final python = await _resolvePythonExecutable(settings);
      if (python == null) {
        _lastProbe = _pythonNotFoundProbeStatus();
        throw WebEngineHttpException(_lastProbe.code);
      }
      await _ensureReady(settings: settings, pythonExecutable: python);
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
          pythonExecutable: python,
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
        detail: 'Scrapling bridge ready.',
        pythonExecutable: python,
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
            '${response['content_type'] ?? headers['content-type'] ?? 'text/html'}',
        statusCode: webFetchHttpStatusFromValue(response['status_code']),
        responseHeaders: headers,
      );
    });
  }

  Future<void> dispose() => _runExclusive(_killProcess);

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<String?> _resolvePythonExecutable(
    AiWebFetchScraplingSettings settings,
  ) async {
    final resolver = _pythonExecutableResolver;
    if (resolver != null) {
      return nullIfBlank(await resolver(settings));
    }
    final custom = nullIfBlank(settings.pythonExecutable) ?? '';
    if (custom.isNotEmpty) {
      final result = await runTrackedProcessOrFailed(
        custom,
        const <String>['--version'],
        timeout: Duration(seconds: settings.startupTimeoutSeconds),
        tag: 'web_fetch_scrapling.which',
        environment: SystemProxyResolver.instance
            .resolveSubprocessEnvironment(),
      );
      return result.exitCode == 0 ? custom : null;
    }
    for (final candidate in <String>['python3', 'python']) {
      final result = await runTrackedProcessOrFailed(
        candidate,
        const <String>['--version'],
        timeout: Duration(seconds: settings.startupTimeoutSeconds),
        tag: 'web_fetch_scrapling.which',
        environment: SystemProxyResolver.instance
            .resolveSubprocessEnvironment(),
      );
      if (result.exitCode == 0) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> _ensureReady({
    required AiWebFetchScraplingSettings settings,
    required String pythonExecutable,
  }) async {
    final startupTimeout =
        _startupTimeoutOverride ??
        Duration(seconds: settings.startupTimeoutSeconds);
    final current = _runtime;
    if (current != null &&
        !current.stopHandlingScheduled &&
        current.pythonExecutable == pythonExecutable) {
      try {
        await current.ready.future.timeout(startupTimeout);
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
      final startupStopwatch = Stopwatch()..start();
      final processStart = _startBridgeProcess(
        pythonExecutable: pythonExecutable,
        helperPath: helperPath,
      );
      final process = await _awaitBridgeProcessStart(
        processStart,
        timeout: _remainingStartupTimeout(startupTimeout, startupStopwatch),
      );
      final runtime = _ScraplingProcessRuntime(
        process: process,
        pythonExecutable: pythonExecutable,
      );
      startedRuntime = runtime;
      _runtime = runtime;
      _listenToRuntime(runtime);
      await runtime.ready.future.timeout(
        _remainingStartupTimeout(startupTimeout, startupStopwatch),
      );
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

  Duration _remainingStartupTimeout(Duration timeout, Stopwatch stopwatch) {
    final remaining = timeout - stopwatch.elapsed;
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  Future<Process> _awaitBridgeProcessStart(
    Future<Process> processStart, {
    required Duration timeout,
  }) async {
    try {
      return await processStart.timeout(
        timeout,
        onTimeout: () => throw _BridgeProcessStartTimeout(timeout),
      );
    } on _BridgeProcessStartTimeout {
      _scheduleUnclaimedProcessCleanup(processStart);
      rethrow;
    }
  }

  void _scheduleUnclaimedProcessCleanup(Future<Process> processStart) {
    unawaited(
      processStart.then<void>(
        _disposeUnclaimedProcess,
        onError: (Object error, StackTrace stack) {
          silentLog(
            'web_fetch_scrapling_bridge',
            'late process start',
            error,
            stack,
          );
        },
      ),
    );
  }

  Future<void> _disposeUnclaimedProcess(Process process) async {
    try {
      final drainTimeout = _processStopTimeout + _processKillTimeout;
      await Future.wait<void>(<Future<void>>[
        _drainUnclaimedProcessStream(
          process.stdout,
          'late process stdout',
          drainTimeout,
        ),
        _drainUnclaimedProcessStream(
          process.stderr,
          'late process stderr',
          drainTimeout,
        ),
        _terminateRuntimeProcess(process),
        _closeRuntimeStdin(process.stdin),
      ]);
    } catch (error, stack) {
      silentLog(
        'web_fetch_scrapling_bridge',
        'dispose late process',
        error,
        stack,
      );
    }
  }

  Future<void> _drainUnclaimedProcessStream(
    Stream<List<int>> stream,
    String streamName,
    Duration timeout,
  ) async {
    try {
      await stream.drain<void>().timeout(timeout);
    } catch (error, stack) {
      silentLog('web_fetch_scrapling_bridge', streamName, error, stack);
    }
  }

  Future<Process> _startBridgeProcess({
    required String pythonExecutable,
    required String helperPath,
  }) {
    final starter = _processStarter;
    if (starter != null) {
      return starter(pythonExecutable, helperPath);
    }
    return startTrackedProcess(
      pythonExecutable,
      <String>[helperPath],
      workingDirectory: OpenHandPaths.applicationDirectoryPath(),
      environment: SystemProxyResolver.instance.resolveSubprocessEnvironment(),
    );
  }

  void _listenToRuntime(_ScraplingProcessRuntime runtime) {
    runtime.stdoutSubscription = runtime.process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _handleRuntimeStdoutLine(runtime, line),
          onError: (Object error, StackTrace stack) {
            if (!identical(_runtime, runtime)) return;
            silentLog('web_fetch_scrapling_bridge', 'stdout', error, stack);
            _handleRuntimeFailure(runtime, error, stack);
          },
          onDone: () {
            if (!identical(_runtime, runtime)) return;
            _scheduleRuntimeStopped(runtime);
          },
        );
    runtime.stderrSubscription = runtime.process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (!identical(_runtime, runtime)) return;
            final trimmed = nullIfBlank(line);
            if (trimmed == null) return;
            runtime.stderrTail = trimmed.length > _maxStderrTailLength
                ? trimmed.substring(trimmed.length - _maxStderrTailLength)
                : trimmed;
          },
          onError: (Object error, StackTrace stack) {
            if (!runtime.stderrDone.isCompleted) {
              runtime.stderrDone.complete();
            }
            if (!identical(_runtime, runtime)) return;
            silentLog('web_fetch_scrapling_bridge', 'stderr', error, stack);
            _handleRuntimeFailure(runtime, error, stack);
          },
          onDone: () {
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
        fallbackPython: runtime.pythonExecutable,
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
      silentLog('web_fetch_scrapling_bridge', 'exit code', error, stack);
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
      await runtime.stderrDone.future.timeout(_processKillTimeout);
    } on TimeoutException {
      // Preserve any buffered stderr without letting a broken pipe hang cleanup.
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
        ? 'Scrapling bridge ready.'
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
        code == 'scrapling_fetchers_missing' ||
        code == 'scrapling_not_installed';
  }

  Future<Map<String, Object?>> _sendCommand({
    required Map<String, Object?> command,
    required Duration timeout,
    Future<void>? cancelSignal,
  }) async {
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
  }) async* {
    final python = await _resolvePythonExecutable(settings);
    if (python == null) {
      _lastProbe = _pythonNotFoundProbeStatus();
      throw WebEngineHttpException(_lastProbe.code);
    }

    await _killProcess();
    yield const WebFetchScraplingRuntimeEvent(
      type: WebFetchScraplingRuntimeEventType.status,
      line: 'Preparing runtime command...',
    );
    yield WebFetchScraplingRuntimeEvent(
      type: WebFetchScraplingRuntimeEventType.command,
      line: '> $python ${command.join(' ')}',
    );

    var attempt = await _runRuntimeAttempt(
      python: python,
      command: command,
      timeoutSeconds: settings.installTimeoutSeconds,
      tag: tag,
    );
    for (final event in attempt.events) {
      yield event;
    }

    final tlsBundle = await _detectTlsBundle(attempt);
    if (!attempt.succeeded && tlsBundle != null) {
      yield WebFetchScraplingRuntimeEvent(
        type: WebFetchScraplingRuntimeEventType.status,
        line:
            'Detected TLS certificate verification failure. Retrying with CA bundle: $tlsBundle',
      );
      attempt = await _runRuntimeAttempt(
        python: python,
        command: command,
        timeoutSeconds: settings.installTimeoutSeconds,
        tag: '$tag.ca_retry',
        environment: <String, String>{
          ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
          'PIP_CERT': tlsBundle,
          'SSL_CERT_FILE': tlsBundle,
          'REQUESTS_CA_BUNDLE': tlsBundle,
          'CURL_CA_BUNDLE': tlsBundle,
        },
      );
      for (final event in attempt.events) {
        yield event;
      }
    }

    if (attempt.succeeded) {
      _lastProbe = WebFetchScraplingProbeStatus(
        ready: runtimeInstalledOnSuccess,
        code: successCode,
        detail: successMessage,
        pythonExecutable: python,
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
      pythonExecutable: python,
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
    required String python,
    required List<String> command,
    required int timeoutSeconds,
    required String tag,
    Map<String, String>? environment,
  }) async {
    final events = <WebFetchScraplingRuntimeEvent>[];
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    try {
      // 把 SystemProxyResolver 解析出的代理端点叠加到子进程环境。
      // pip install / uninstall 一定要走代理，否则在企业代理 / 内网透明
      // 代理环境下 PyPI 连接会超时失败（参见 plugin_service 同源修复）。
      final mergedEnv = <String, String>{
        ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
        ...?environment,
      };
      final process = await startTrackedProcess(
        python,
        command,
        workingDirectory: OpenHandPaths.applicationDirectoryPath(),
        environment: mergedEnv,
      );
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
            stdout.writeln(line);
            events.add(
              WebFetchScraplingRuntimeEvent(
                type: WebFetchScraplingRuntimeEventType.stdout,
                line: line,
              ),
            );
          }, onDone: () => stdoutDone.complete());
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
            stderr.writeln(line);
            events.add(
              WebFetchScraplingRuntimeEvent(
                type: WebFetchScraplingRuntimeEventType.stderr,
                line: line,
              ),
            );
          }, onDone: () => stderrDone.complete());

      final timeout = Duration(seconds: timeoutSeconds);
      final exitOrTimeout = await Future.any<Object?>([
        process.exitCode,
        Future<void>.delayed(
          timeout,
        ).then<Object?>((_) => const _TimeoutToken()),
      ]);
      if (exitOrTimeout is _TimeoutToken) {
        process.kill();
        if (!Platform.isWindows) {
          process.kill(ProcessSignal.sigkill);
        }
        await Future.wait([stdoutDone.future, stderrDone.future]);
        events.add(
          const WebFetchScraplingRuntimeEvent(
            type: WebFetchScraplingRuntimeEventType.warning,
            line: 'Process timed out.',
          ),
        );
        return _RuntimeAttemptResult(
          succeeded: false,
          exitCode: -1,
          stdout: stdout.toString(),
          stderr: stderr.toString(),
          timedOut: true,
          events: events,
        );
      }

      final exitCode = exitOrTimeout as int;
      await Future.wait([stdoutDone.future, stderrDone.future]);
      events.add(
        WebFetchScraplingRuntimeEvent(
          type: exitCode == 0
              ? WebFetchScraplingRuntimeEventType.status
              : WebFetchScraplingRuntimeEventType.warning,
          line: 'Process exited with code $exitCode.',
        ),
      );
      return _RuntimeAttemptResult(
        succeeded: exitCode == 0,
        exitCode: exitCode,
        stdout: stdout.toString(),
        stderr: stderr.toString(),
        events: events,
      );
    } catch (error, stack) {
      silentLog('web_fetch_scrapling_bridge', tag, error, stack);
      events.add(
        WebFetchScraplingRuntimeEvent(
          type: WebFetchScraplingRuntimeEventType.stderr,
          line: '$error',
        ),
      );
      return _RuntimeAttemptResult(
        succeeded: false,
        exitCode: -1,
        stdout: stdout.toString(),
        stderr: stderr.toString(),
        events: events,
      );
    }
  }

  Future<String?> _detectTlsBundle(_RuntimeAttemptResult result) async {
    final combined = '${result.stdout}\n${result.stderr}'.toLowerCase();
    if (!combined.contains('certificate_verify_failed')) return null;
    final certifi = await _probeCertifiBundle();
    if (certifi != null && File(certifi).existsSync()) return certifi;
    for (final candidate in <String>[
      '/etc/ssl/cert.pem',
      '/private/etc/ssl/cert.pem',
      '/etc/ssl/certs/ca-certificates.crt',
      '/opt/homebrew/etc/openssl@3/cert.pem',
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<String?> _probeCertifiBundle() async {
    try {
      final result = await runTrackedProcessOrFailed(
        'python3',
        const <String>['-c', 'import certifi; print(certifi.where())'],
        timeout: const Duration(seconds: 2),
        tag: 'web_fetch_scrapling_bridge.probe_certifi',
      );
      if (result.exitCode == 0) {
        return optionalStringFromValue(result.stdout);
      }
    } catch (error, stack) {
      silentLog(
        'web_fetch_scrapling_bridge',
        'probe certifi bundle',
        error,
        stack,
      );
    }
    return null;
  }

  String _summarizeRuntimeFailure(_RuntimeAttemptResult result) {
    final combined = '${result.stdout}\n${result.stderr}'.toLowerCase();
    if (result.timedOut) {
      return 'Runtime command timed out.';
    }
    if (combined.contains('certificate_verify_failed')) {
      return 'TLS certificate verification failed while reaching PyPI. Check Python CA certificates, proxy interception certificates, or configure a valid certificate bundle for pip.';
    }
    if (combined.contains('no matching distribution found')) {
      return 'pip could not resolve the requested package version.';
    }
    if (combined.contains('could not fetch url')) {
      return 'pip could not fetch package metadata from PyPI.';
    }
    return 'Process exited with code ${result.exitCode}.';
  }

  Future<String> _ensureHelperScriptWritten() async {
    if (_helperPath != null) return _helperPath!;
    final provider = _helperPathProvider;
    if (provider != null) {
      final helperPath = nullIfBlank(await provider());
      if (helperPath == null) {
        throw StateError('Scrapling helper path must not be blank.');
      }
      return _helperPath = helperPath;
    }
    final bytes = await rootBundle.load(_assetPath);
    final dir = Directory(
      p.join(
        OpenHandPaths.defaultCacheDirectoryPath(),
        'web_fetch',
        'scrapling',
      ),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, 'bridge.py'));
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
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
            'chmod helper',
            'exit ${result.exitCode}: ${result.stderr}',
          );
        }
      } catch (error, stack) {
        silentLog('web_fetch_scrapling_bridge', 'chmod helper', error, stack);
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
        silentLog(
          'web_fetch_scrapling_bridge',
          'cleanup runtime',
          error,
          stack,
        );
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
      _cancelRuntimeSubscription(stdoutSubscription, 'stdout'),
      _cancelRuntimeSubscription(stderrSubscription, 'stderr'),
    ]);
    if (!runtime.stderrDone.isCompleted) {
      runtime.stderrDone.complete();
    }
    await Future.wait<void>(<Future<void>>[
      _terminateRuntimeProcess(runtime.process),
      _closeRuntimeStdin(runtime.process.stdin),
    ]);
  }

  Future<void> _cancelRuntimeSubscription(
    StreamSubscription<String>? subscription,
    String streamName,
  ) async {
    if (subscription == null) return;
    try {
      await subscription.cancel().timeout(_processKillTimeout);
    } catch (error, stack) {
      silentLog(
        'web_fetch_scrapling_bridge',
        'cancel $streamName subscription',
        error,
        stack,
      );
    }
  }

  Future<void> _terminateRuntimeProcess(Process process) async {
    try {
      process.kill();
    } catch (error, stack) {
      silentLog(
        'web_fetch_scrapling_bridge',
        'terminate process',
        error,
        stack,
      );
    }
    if (await _waitForProcessExit(process, _processStopTimeout)) return;

    try {
      if (Platform.isWindows) {
        process.kill();
      } else {
        process.kill(ProcessSignal.sigkill);
      }
    } catch (error, stack) {
      silentLog('web_fetch_scrapling_bridge', 'kill process', error, stack);
    }
    if (await _waitForProcessExit(process, _processKillTimeout)) return;
    silentLog(
      'web_fetch_scrapling_bridge',
      'wait after forced process termination',
      TimeoutException(
        'Scrapling bridge did not exit after forced termination.',
        _processKillTimeout,
      ),
    );
  }

  Future<bool> _waitForProcessExit(Process process, Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (error, stack) {
      silentLog(
        'web_fetch_scrapling_bridge',
        'wait for process exit',
        error,
        stack,
      );
      return false;
    }
  }

  Future<void> _closeRuntimeStdin(IOSink stdin) async {
    try {
      await stdin.close().timeout(_processKillTimeout);
    } catch (error, stack) {
      silentLog(
        'web_fetch_scrapling_bridge',
        'close process stdin',
        error,
        stack,
      );
    }
  }
}

class _ScraplingProcessRuntime {
  _ScraplingProcessRuntime({
    required this.process,
    required this.pythonExecutable,
  });

  final Process process;
  final String pythonExecutable;
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
    : super('Scrapling bridge process start timed out.', duration);
}

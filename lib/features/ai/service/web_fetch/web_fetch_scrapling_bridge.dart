import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/silent_log.dart';
import '../../model/ai_web_fetch_settings.dart';
import 'web_fetch_engine.dart';

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
  WebFetchScraplingBridge();

  static const String _assetPath =
      'assets/tooling/webfetch_scrapling_bridge.py';

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Completer<void>? _readyCompleter;
  Future<void> _serial = Future<void>.value();
  String? _activePythonExecutable;
  String _stderrTail = '';
  String? _helperPath;
  int _requestSeq = 0;
  WebFetchScraplingProbeStatus _lastProbe = const WebFetchScraplingProbeStatus(
    ready: false,
    code: 'not_started',
    detail: 'Scrapling bridge not started.',
  );
  final Map<String, Completer<Map<String, Object?>>> _pending =
      <String, Completer<Map<String, Object?>>>{};

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
        return _lastProbe = WebFetchScraplingProbeStatus(
          ready: false,
          code: 'python_not_found',
          detail:
              'Python 3 not found. Install Python 3.10+ or set a custom executable path.',
          updatedAt: DateTime.now().toUtc(),
          runtimeInstalled: false,
        );
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
          runtimeInstalled: false,
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
        _lastProbe = WebFetchScraplingProbeStatus(
          ready: false,
          code: 'python_not_found',
          detail:
              'Python 3 not found. Install Python 3.10+ or set a custom executable path.',
          updatedAt: DateTime.now().toUtc(),
          runtimeInstalled: false,
        );
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
        final detail = '${response['detail'] ?? code}'.trim();
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
      return WebFetchScraplingBridgeResult(
        url: '${response['final_url'] ?? url}'.trim().isEmpty
            ? url
            : '${response['final_url']}'.trim(),
        title: '${response['title'] ?? ''}',
        content: '${response['content'] ?? ''}',
        contentType:
            '${response['content_type'] ?? headers['content-type'] ?? 'text/html'}',
        statusCode: response['status_code'] is num
            ? (response['status_code'] as num).toInt()
            : null,
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
    final custom = settings.pythonExecutable?.trim() ?? '';
    if (custom.isNotEmpty) {
      final result = await runTrackedProcessOrFailed(
        custom,
        const <String>['--version'],
        timeout: Duration(seconds: settings.startupTimeoutSeconds),
        tag: 'web_fetch_scrapling.which',
      );
      return result.exitCode == 0 ? custom : null;
    }
    for (final candidate in <String>['python3', 'python']) {
      final result = await runTrackedProcessOrFailed(
        candidate,
        const <String>['--version'],
        timeout: Duration(seconds: settings.startupTimeoutSeconds),
        tag: 'web_fetch_scrapling.which',
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
    final needRestart =
        _process == null ||
        _readyCompleter == null ||
        _activePythonExecutable != pythonExecutable;
    if (!needRestart && _process != null && _readyCompleter != null) {
      await _readyCompleter!.future.timeout(
        Duration(seconds: settings.startupTimeoutSeconds),
      );
      return;
    }
    await _killProcess();
    final helperPath = await _ensureHelperScriptWritten();
    final ready = Completer<void>();
    _readyCompleter = ready;
    _activePythonExecutable = pythonExecutable;
    _stderrTail = '';
    final process = await startTrackedProcess(pythonExecutable, <String>[
      helperPath,
    ], workingDirectory: OpenHandPaths.applicationDirectoryPath());
    _process = process;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.trim().isEmpty) return;
            Map<String, Object?> json;
            try {
              final decoded = jsonDecode(line);
              if (decoded is! Map) return;
              json = Map<String, Object?>.from(decoded);
            } catch (_) {
              return;
            }
            if (json['type'] == 'ready') {
              _lastProbe = _probeFromResponse(
                json,
                fallbackPython: pythonExecutable,
              );
              if (_lastProbe.ready) {
                if (!ready.isCompleted) ready.complete();
              } else {
                if (!ready.isCompleted) {
                  ready.completeError(
                    WebEngineHttpException(
                      '${_lastProbe.code}: ${_lastProbe.detail}',
                    ),
                  );
                }
              }
              return;
            }
            final id = '${json['id'] ?? ''}'.trim();
            final pending = _pending.remove(id);
            if (pending != null && !pending.isCompleted) {
              pending.complete(json);
            }
          },
          onError: (Object error, StackTrace stack) {
            silentLog('web_fetch_scrapling_bridge', 'stdout', error, stack);
            if (!ready.isCompleted) ready.completeError(error, stack);
            _failPending(error, stack);
          },
          onDone: () {
            final error = WebEngineHttpException(
              _stderrTail.isEmpty
                  ? 'scrapling_bridge_stopped'
                  : 'scrapling_bridge_stopped: $_stderrTail',
            );
            if (!ready.isCompleted) ready.completeError(error);
            _failPending(error, StackTrace.current);
          },
        );
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return;
          _stderrTail = trimmed.length > 800
              ? trimmed.substring(trimmed.length - 800)
              : trimmed;
        });
    unawaited(
      process.exitCode.then((_) {
        _process = null;
      }),
    );
    await ready.future.timeout(
      Duration(seconds: settings.startupTimeoutSeconds),
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
        : '${response['detail'] ?? code}';
    return WebFetchScraplingProbeStatus(
      ready: ok,
      code: code,
      detail: detail,
      pythonExecutable: '${response['python'] ?? fallbackPython}',
      updatedAt: DateTime.now().toUtc(),
      runtimeInstalled: response['runtime_installed'] == true || ok,
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
    final process = _process;
    if (process == null) {
      throw WebEngineHttpException('scrapling_bridge_not_running');
    }
    final id = 'req_${++_requestSeq}';
    final payload = <String, Object?>{'id': id, ...command};
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    try {
      process.stdin.writeln(jsonEncode(payload));
      final futures = <Future<Object?>>[
        completer.future,
        Future<void>.delayed(
          timeout,
        ).then<Object?>((_) => const _TimeoutToken()),
      ];
      if (cancelSignal != null) {
        futures.add(cancelSignal.then<Object?>((_) => const _CancelledToken()));
      }
      final result = await Future.any(futures);
      if (result is _TimeoutToken) {
        _pending.remove(id);
        await _killProcess();
        throw WebEngineHttpException('scrapling_bridge_timeout');
      }
      if (result is _CancelledToken) {
        _pending.remove(id);
        await _killProcess();
        throw WebEngineHttpException('cancelled');
      }
      return result as Map<String, Object?>;
    } on StateError {
      _pending.remove(id);
      await _killProcess();
      throw WebEngineHttpException('scrapling_bridge_stdin_closed');
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
      _lastProbe = WebFetchScraplingProbeStatus(
        ready: false,
        code: 'python_not_found',
        detail:
            'Python 3 not found. Install Python 3.10+ or set a custom executable path.',
        updatedAt: DateTime.now().toUtc(),
        runtimeInstalled: false,
      );
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

    final tlsBundle = _detectTlsBundle(attempt);
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
      final process = await startTrackedProcess(
        python,
        command,
        workingDirectory: OpenHandPaths.applicationDirectoryPath(),
        environment: environment,
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

  String? _detectTlsBundle(_RuntimeAttemptResult result) {
    final combined = '${result.stdout}\n${result.stderr}'.toLowerCase();
    if (!combined.contains('certificate_verify_failed')) return null;
    final certifi = _probeCertifiBundle();
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

  String? _probeCertifiBundle() {
    try {
      final result = Process.runSync('python3', const <String>[
        '-c',
        'import certifi; print(certifi.where())',
      ]);
      if (result.exitCode == 0) {
        final value = '${result.stdout}'.trim();
        return value.isEmpty ? null : value;
      }
    } catch (_) {}
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
        await Process.run('chmod', <String>['700', file.path]);
      } catch (error, stack) {
        silentLog('web_fetch_scrapling_bridge', 'chmod helper', error, stack);
      }
    }
    _helperPath = file.path;
    return file.path;
  }

  void _failPending(Object error, StackTrace stack) {
    final pending = List<Completer<Map<String, Object?>>>.from(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    }
  }

  Future<void> _killProcess() async {
    final process = _process;
    _process = null;
    _activePythonExecutable = null;
    final stdoutSub = _stdoutSubscription;
    final stderrSub = _stderrSubscription;
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _readyCompleter = null;
    if (stdoutSub != null) {
      await stdoutSub.cancel();
    }
    if (stderrSub != null) {
      await stderrSub.cancel();
    }
    if (process != null) {
      try {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 2)).catchError((
          _,
        ) async {
          if (!Platform.isWindows) {
            process.kill(ProcessSignal.sigkill);
          }
          return -1;
        });
      } catch (error, stack) {
        silentLog('web_fetch_scrapling_bridge', 'kill process', error, stack);
      }
    }
    _failPending(
      WebEngineHttpException('scrapling_bridge_restarted'),
      StackTrace.current,
    );
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

class _CancelledToken {
  const _CancelledToken();
}

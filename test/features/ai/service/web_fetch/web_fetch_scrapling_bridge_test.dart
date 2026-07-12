import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/safe_subprocess.dart';
import 'package:openhand/features/ai/model/ai_web_fetch_settings.dart';
import 'package:openhand/features/ai/service/web_engine/web_engine_http_exception.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_scrapling_bridge.dart';

const _settings = AiWebFetchScraplingSettings(
  startupTimeoutSeconds: 1,
  requestTimeoutSeconds: 1,
);

void main() {
  group('WebFetchScraplingBridge process lifecycle', () {
    test('rejects negative lifecycle timeouts', () {
      expect(
        () => WebFetchScraplingBridge.withDependencies(
          startupTimeoutOverride: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(
        () => WebFetchScraplingBridge.withDependencies(
          processStopTimeout: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(
        () => WebFetchScraplingBridge.withDependencies(
          processKillTimeout: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('recovers after the process starter throws', () async {
      final successfulProcess = _successfulProcess(pid: 102);
      var startCount = 0;
      final bridge = _createBridge((_, _) async {
        startCount += 1;
        if (startCount == 1) {
          throw const ProcessException(
            'fake-python',
            <String>['/fake/bridge.py'],
            'spawn failed',
            2,
          );
        }
        return successfulProcess;
      });
      addTearDown(() => bridge.dispose());

      await expectLater(_fetch(bridge), throwsA(isA<ProcessException>()));

      final result = await _fetch(bridge);
      expect(result.content, 'fake content');
      expect(startCount, 2);
    });

    test('recycles a process returned after its start timed out', () async {
      final delayedStart = Completer<Process>();
      final lateProcess = _FakeProcess(pid: 151);
      final currentProcess = _successfulProcess(pid: 152);
      var startCount = 0;
      final bridge = _createBridge((_, _) {
        startCount += 1;
        return startCount == 1
            ? delayedStart.future
            : Future<Process>.value(currentProcess);
      });
      addTearDown(() => bridge.dispose());

      await expectLater(_fetch(bridge), throwsA(isA<TimeoutException>()));
      expect((await _fetch(bridge)).content, 'fake content');

      delayedStart.complete(lateProcess);
      await _waitForCondition(() => lateProcess.killSignals.isNotEmpty);
      expect(lateProcess.killSignals, contains(ProcessSignal.sigterm));

      expect((await _fetch(bridge)).content, 'fake content');
      expect(startCount, 2);
      expect(currentProcess.receivedCommands, hasLength(2));
    });

    test('cleans up a ready timeout and retries with a new process', () async {
      final stalledProcess = _FakeProcess(pid: 201);
      final successfulProcess = _successfulProcess(pid: 202);
      final processes = <_FakeProcess>[stalledProcess, successfulProcess];
      var startCount = 0;
      final bridge = _createBridge((_, _) async {
        startCount += 1;
        return processes.removeAt(0);
      });
      addTearDown(() => bridge.dispose());

      await expectLater(_fetch(bridge), throwsA(isA<TimeoutException>()));

      expect(stalledProcess.stdoutCancelled, isTrue);
      expect(stalledProcess.stderrCancelled, isTrue);
      expect(stalledProcess.killSignals, contains(ProcessSignal.sigterm));

      final result = await _fetch(bridge);
      expect(result.url, 'https://example.test/page');
      expect(result.statusCode, 200);
      expect(startCount, 2);
    });

    test('cleans up an early exit and allows a later fetch', () async {
      final failedProcess = _FakeProcess(pid: 301);
      final successfulProcess = _successfulProcess(pid: 302);
      final processes = <_FakeProcess>[failedProcess, successfulProcess];
      var startCount = 0;
      final bridge = _createBridge((_, _) async {
        startCount += 1;
        final process = processes.removeAt(0);
        if (identical(process, failedProcess)) {
          scheduleMicrotask(() {
            process.emitStderrLine('bridge startup failed');
            process.completeExit(17);
          });
        }
        return process;
      });
      addTearDown(() => bridge.dispose());

      await expectLater(
        _fetch(bridge),
        throwsA(
          isA<WebEngineHttpException>()
              .having(
                (error) => error.message,
                'message',
                contains('scrapling_bridge_stopped'),
              )
              .having(
                (error) => error.message,
                'stderr tail',
                contains('bridge startup failed'),
              ),
        ),
      );

      expect(failedProcess.stdoutCancelled, isTrue);
      expect(failedProcess.stderrCancelled, isTrue);
      expect((await _fetch(bridge)).content, 'fake content');
      expect(startCount, 2);
    });

    test('restarts instead of reusing a process that has exited', () async {
      final exitedProcess = _successfulProcess(pid: 351);
      final replacementProcess = _successfulProcess(pid: 352);
      final processes = <_FakeProcess>[exitedProcess, replacementProcess];
      var startCount = 0;
      final bridge = _createBridge((_, _) async {
        startCount += 1;
        return processes.removeAt(0);
      });
      addTearDown(() => bridge.dispose());

      expect((await _fetch(bridge)).content, 'fake content');
      exitedProcess.completeExit();

      expect((await _fetch(bridge)).content, 'fake content');
      expect(startCount, 2);
      expect(exitedProcess.receivedCommands, hasLength(1));
      expect(replacementProcess.receivedCommands, hasLength(1));
    });

    test('ignores an old process exit after a replacement is ready', () async {
      final oldProcess = _FakeProcess(
        pid: 401,
        exitOnTerminate: false,
        exitOnKill: false,
      );
      final currentProcess = _successfulProcess(pid: 402);
      final processes = <_FakeProcess>[oldProcess, currentProcess];
      var startCount = 0;
      final bridge = _createBridge((_, _) async {
        startCount += 1;
        return processes.removeAt(0);
      });
      addTearDown(() => bridge.dispose());

      await expectLater(_fetch(bridge), throwsA(isA<TimeoutException>()));
      expect(oldProcess.killSignals, contains(ProcessSignal.sigterm));
      if (!Platform.isWindows) {
        expect(oldProcess.killSignals, contains(ProcessSignal.sigkill));
      }

      expect((await _fetch(bridge)).content, 'fake content');
      oldProcess.completeExit(-9);
      await Future<void>.delayed(Duration.zero);

      expect((await _fetch(bridge)).content, 'fake content');
      expect(startCount, 2);
      expect(currentProcess.receivedCommands, hasLength(2));
    });
  });

  group('WebFetchScraplingBridge runtime commands', () {
    test('serializes install and uninstall commands', () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var invocationCount = 0;
      var activeCount = 0;
      var maxActiveCount = 0;
      final bridge = _createBridge(
        (_, _) async => _successfulProcess(pid: 501),
        runtimeCommandRunner:
            ({
              required executable,
              required arguments,
              required timeout,
              required tag,
              required workingDirectory,
              required environment,
              required onStdoutLine,
              required onStderrLine,
            }) async {
              invocationCount += 1;
              activeCount += 1;
              if (activeCount > maxActiveCount) maxActiveCount = activeCount;
              if (invocationCount == 1) {
                firstStarted.complete();
                await releaseFirst.future;
              }
              activeCount -= 1;
              return _successfulRuntimeCommandResult(invocationCount);
            },
      );
      addTearDown(() => bridge.dispose());

      final install = bridge.installRuntime(settings: _settings);
      await firstStarted.future;
      final uninstall = bridge.uninstallRuntime(settings: _settings);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(invocationCount, 1);
      expect(maxActiveCount, 1);

      releaseFirst.complete();
      await Future.wait<void>([install, uninstall]);

      expect(invocationCount, 2);
      expect(maxActiveCount, 1);
      expect(bridge.lastProbe.runtimeInstalled, isFalse);
    });

    test('keeps fetch queued until a runtime command finishes', () async {
      final commandStarted = Completer<void>();
      final releaseCommand = Completer<void>();
      var bridgeStartCount = 0;
      final bridge = _createBridge(
        (_, _) async {
          bridgeStartCount += 1;
          return _successfulProcess(pid: 502);
        },
        runtimeCommandRunner:
            ({
              required executable,
              required arguments,
              required timeout,
              required tag,
              required workingDirectory,
              required environment,
              required onStdoutLine,
              required onStderrLine,
            }) async {
              commandStarted.complete();
              await releaseCommand.future;
              return _successfulRuntimeCommandResult(1);
            },
      );
      addTearDown(() => bridge.dispose());

      final install = bridge.installRuntime(settings: _settings);
      await commandStarted.future;
      final fetch = _fetch(bridge);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bridgeStartCount, 0);

      releaseCommand.complete();
      await install;
      expect((await fetch).content, 'fake content');
      expect(bridgeStartCount, 1);
    });

    test('bounds retained runtime events and individual lines', () async {
      final bridge = _createBridge(
        (_, _) async => _successfulProcess(pid: 503),
        runtimeCommandRunner:
            ({
              required executable,
              required arguments,
              required timeout,
              required tag,
              required workingDirectory,
              required environment,
              required onStdoutLine,
              required onStderrLine,
            }) async {
              for (var index = 0; index < 449; index += 1) {
                onStdoutLine('line-$index');
              }
              onStdoutLine('x' * 5000);
              return _successfulRuntimeCommandResult(1);
            },
      );
      addTearDown(() => bridge.dispose());

      final events = await bridge
          .installRuntimeStreaming(settings: _settings)
          .toList();
      final stdoutEvents = events
          .where(
            (event) => event.type == WebFetchScraplingRuntimeEventType.stdout,
          )
          .toList();

      expect(stdoutEvents, hasLength(399));
      expect(stdoutEvents.first.line, 'line-51');
      expect(stdoutEvents.last.line, endsWith('…'));
      expect(stdoutEvents.last.line.length, 4001);
      expect(events.length, lessThanOrEqualTo(403));
    });
  });
}

WebFetchScraplingBridge _createBridge(
  Future<Process> Function(String pythonExecutable, String helperPath)
  starter, {
  WebFetchScraplingRuntimeCommandRunner? runtimeCommandRunner,
}) {
  return WebFetchScraplingBridge.withDependencies(
    pythonExecutableResolver: (_) async => 'fake-python',
    helperPathProvider: () async => '/fake/bridge.py',
    processStarter: starter,
    runtimeCommandRunner: runtimeCommandRunner,
    startupTimeoutOverride: const Duration(milliseconds: 30),
    processStopTimeout: const Duration(milliseconds: 10),
    processKillTimeout: const Duration(milliseconds: 10),
  );
}

Future<WebFetchScraplingBridgeResult> _fetch(WebFetchScraplingBridge bridge) {
  return bridge.fetch(
    url: 'https://example.test/page',
    maxChars: 1000,
    settings: _settings,
  );
}

Future<void> _waitForCondition(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

_FakeProcess _successfulProcess({required int pid}) {
  final process = _FakeProcess(pid: pid);
  process.onCommand = (command) {
    if (command['command'] != 'fetch') return;
    process.emitStdoutJson(<String, Object?>{
      'id': command['id'],
      'ok': true,
      'final_url': command['url'],
      'title': 'Fake page',
      'content': 'fake content',
      'content_type': 'text/html',
      'status_code': 200,
      'response_headers': <String, String>{'X-Test': 'true'},
    });
  };
  scheduleMicrotask(() {
    process.emitStdoutJson(<String, Object?>{
      'type': 'ready',
      'ok': true,
      'python': 'fake-python',
      'runtime_installed': true,
    });
  });
  return process;
}

TrackedProcessLineLogResult _successfulRuntimeCommandResult(int pid) {
  return TrackedProcessLineLogResult(
    pid: pid,
    exitCode: 0,
    timedOut: false,
    stdout: '',
    stderr: '',
  );
}

class _FakeProcess implements Process {
  _FakeProcess({
    required this.pid,
    this.exitOnTerminate = true,
    this.exitOnKill = true,
  }) {
    _stdoutController = StreamController<List<int>>(
      sync: true,
      onCancel: () => stdoutCancelled = true,
    );
    _stderrController = StreamController<List<int>>(
      sync: true,
      onCancel: () => stderrCancelled = true,
    );
    _stdinController = StreamController<List<int>>(sync: true);
    _stdin = IOSink(_stdinController.sink);
    _stdinController.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleCommandLine);
  }

  final bool exitOnTerminate;
  final bool exitOnKill;
  final Completer<int> _exitCode = Completer<int>();
  final List<ProcessSignal> killSignals = <ProcessSignal>[];
  final List<Map<String, Object?>> receivedCommands = <Map<String, Object?>>[];

  late final StreamController<List<int>> _stdoutController;
  late final StreamController<List<int>> _stderrController;
  late final StreamController<List<int>> _stdinController;
  late final IOSink _stdin;
  bool _stdoutClosed = false;
  bool _stderrClosed = false;
  bool stdoutCancelled = false;
  bool stderrCancelled = false;
  void Function(Map<String, Object?> command)? onCommand;

  @override
  final int pid;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  void emitStdoutJson(Map<String, Object?> json) {
    if (_stdoutClosed) return;
    _stdoutController.add(utf8.encode('${jsonEncode(json)}\n'));
  }

  void emitStderrLine(String line) {
    if (_stderrClosed) return;
    _stderrController.add(utf8.encode('$line\n'));
  }

  void completeExit([int code = 0]) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
    if (!_stdoutClosed) {
      _stdoutClosed = true;
      unawaited(_stdoutController.close());
    }
    if (!_stderrClosed) {
      _stderrClosed = true;
      unawaited(_stderrController.close());
    }
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if (_exitCode.isCompleted) return false;
    final shouldExit = signal == ProcessSignal.sigkill
        ? exitOnKill
        : exitOnTerminate;
    if (shouldExit) completeExit(-signal.signalNumber);
    return true;
  }

  void _handleCommandLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) return;
    final command = <String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    };
    receivedCommands.add(command);
    onCommand?.call(command);
  }
}

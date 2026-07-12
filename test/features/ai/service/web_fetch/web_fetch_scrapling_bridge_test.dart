import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}

WebFetchScraplingBridge _createBridge(
  Future<Process> Function(String pythonExecutable, String helperPath) starter,
) {
  return WebFetchScraplingBridge.withDependencies(
    pythonExecutableResolver: (_) async => 'fake-python',
    helperPathProvider: () async => '/fake/bridge.py',
    processStarter: starter,
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

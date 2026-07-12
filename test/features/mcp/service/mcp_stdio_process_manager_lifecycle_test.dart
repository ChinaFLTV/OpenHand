import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/service/mcp_stdio_process_manager.dart';

void main() {
  const server = McpServer(
    name: 'lifecycle-test',
    type: McpServerType.stdio,
    enabled: true,
    command: 'fake-mcp-server',
  );

  test(
    'late exit from a stopped process cannot overwrite its replacement',
    () async {
      final first = _FakeProcess(pid: 11001, completeExitOnKill: false);
      final second = _FakeProcess(pid: 11002, completeExitOnKill: true);
      final processes = <_FakeProcess>[first, second];
      var launchIndex = 0;
      final manager = McpStdioProcessManager.forTesting(
        processStarter: (executable, arguments, {environment}) async {
          return processes[launchIndex++];
        },
        gracefulStopTimeout: const Duration(milliseconds: 5),
        forceStopTimeout: const Duration(milliseconds: 5),
      );

      try {
        await manager.startServer(server);
        expect(manager.infoFor(server.name).pid, first.pid);

        // The fake process ignores both TERM and KILL, so stop completes through
        // its bounded fallback while the old exitCode Future remains pending.
        await manager.stopServer(server.name);
        expect(manager.infoFor(server.name).isStopped, isTrue);
        expect(first.wasKilled, isTrue);

        await manager.startServer(server);
        expect(manager.infoFor(server.name).pid, second.pid);

        first.completeExit(37);
        await Future<void>.delayed(Duration.zero);

        final current = manager.infoFor(server.name);
        expect(current.state, StdioProcessState.running);
        expect(current.pid, second.pid);
        expect(current.logs.join('\n'), isNot(contains('exit code: 37')));
      } finally {
        await manager.stopServer(server.name);
        await Future.wait<void>(
          processes.map((process) => process.closeStreams()),
        );
      }
    },
  );

  test(
    'old stop cleanup cannot reset a concurrently restarted process',
    () async {
      final stdoutCancelGate = Completer<void>();
      final first = _FakeProcess(
        pid: 12001,
        completeExitOnKill: false,
        stdoutCancelGate: stdoutCancelGate,
      );
      final second = _FakeProcess(pid: 12002, completeExitOnKill: true);
      final processes = <_FakeProcess>[first, second];
      var launchIndex = 0;
      final manager = McpStdioProcessManager.forTesting(
        processStarter: (executable, arguments, {environment}) async {
          return processes[launchIndex++];
        },
        // Keep the handshake task from replacing the initial subscriptions
        // before stopServer captures them for this cancellation race.
        initializeStartupDelay: const Duration(milliseconds: 200),
        subscriptionCancelTimeout: const Duration(seconds: 1),
      );

      try {
        await manager.startServer(server);
        final stopFuture = manager.stopServer(server.name);

        first.completeExit(0);
        await _waitUntil(() => manager.infoFor(server.name).isStopped);

        // stopServer is now blocked cancelling the old stdout subscription, but
        // the exit callback has already made a restart legal.
        await manager.startServer(server);
        expect(manager.infoFor(server.name).pid, second.pid);

        stdoutCancelGate.complete();
        await stopFuture;

        final current = manager.infoFor(server.name);
        expect(current.state, StdioProcessState.running);
        expect(current.pid, second.pid);
      } finally {
        if (!stdoutCancelGate.isCompleted) {
          stdoutCancelGate.complete();
        }
        await manager.stopServer(server.name);
        await Future.wait<void>(
          processes.map((process) => process.closeStreams()),
        );
        // Let the intentionally delayed handshake tasks observe the stopped
        // generation and return before the test zone is torn down.
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
    },
  );

  test(
    'process returned after stop is discarded instead of replacing restart',
    () async {
      final delayedLaunch = Completer<Process>();
      final stale = _FakeProcess(pid: 13001, completeExitOnKill: true);
      final replacement = _FakeProcess(pid: 13002, completeExitOnKill: true);
      var launchCount = 0;
      final manager = McpStdioProcessManager.forTesting(
        processStarter: (executable, arguments, {environment}) {
          launchCount += 1;
          return launchCount == 1
              ? delayedLaunch.future
              : Future<Process>.value(replacement);
        },
      );

      try {
        final staleStart = manager.startServer(server);
        await _waitUntil(() => launchCount == 1);
        expect(manager.infoFor(server.name).state, StdioProcessState.starting);

        await manager.stopServer(server.name);
        expect(manager.infoFor(server.name).isStopped, isTrue);

        await manager.startServer(server);
        expect(manager.infoFor(server.name).pid, replacement.pid);

        delayedLaunch.complete(stale);
        await staleStart;
        await Future<void>.delayed(Duration.zero);

        expect(stale.wasKilled, isTrue);
        expect(manager.infoFor(server.name).state, StdioProcessState.running);
        expect(manager.infoFor(server.name).pid, replacement.pid);
      } finally {
        if (!delayedLaunch.isCompleted) {
          delayedLaunch.complete(stale);
        }
        await manager.stopServer(server.name);
        await Future.wait<void>(<Future<void>>[
          stale.closeStreams(),
          replacement.closeStreams(),
        ]);
      }
    },
  );

  test(
    'start timeout reaps a process that arrives after the deadline',
    () async {
      final delayedLaunch = Completer<Process>();
      final lateProcess = _FakeProcess(
        pid: 14001,
        completeExitOnKill: false,
        completeExitOnSigkill: true,
      );
      final manager = McpStdioProcessManager.forTesting(
        processStarter: (executable, arguments, {environment}) {
          return delayedLaunch.future;
        },
        processStartTimeout: const Duration(milliseconds: 5),
        gracefulStopTimeout: const Duration(milliseconds: 5),
        forceStopTimeout: const Duration(milliseconds: 20),
      );

      try {
        await manager.startServer(server);
        final failed = manager.infoFor(server.name);
        expect(failed.isStopped, isTrue);
        expect(failed.errorMessage, contains('process start timed out'));

        delayedLaunch.complete(lateProcess);
        await _waitUntil(
          () => lateProcess.killSignals.contains(ProcessSignal.sigkill),
        );

        expect(lateProcess.killSignals.first, ProcessSignal.sigterm);
        expect(manager.infoFor(server.name).isStopped, isTrue);
        expect(manager.infoFor(server.name).pid, isNull);
      } finally {
        if (!delayedLaunch.isCompleted) {
          delayedLaunch.complete(lateProcess);
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await lateProcess.closeStreams();
      }
    },
  );

  test(
    'router rejects an unterminated response above its hard limit',
    () async {
      final process = _FakeProcess(pid: 15001, completeExitOnKill: true);
      final manager = McpStdioProcessManager.forTesting(
        processStarter: (executable, arguments, {environment}) async => process,
        responseBufferLimit: 64,
      );

      try {
        await manager.startServer(server);
        final session = await manager.borrowSessionForDiscovery(server.name);
        expect(session, isNotNull);

        final request = session!.sendRequest(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 42,
          'method': 'tools/list',
        });
        await Future<void>.delayed(Duration.zero);
        process.emitStdout('x' * 65);

        await expectLater(request, throwsStateError);

        process.emitStdout('z' * 5000);
        await Future<void>.delayed(Duration.zero);
        final truncatedLogs = manager
            .infoFor(server.name)
            .logs
            .where((line) => line.contains('截断，共 5000 字符'))
            .toList(growable: false);
        expect(truncatedLogs, hasLength(1));
        expect(truncatedLogs.single.length, lessThan(4200));
      } finally {
        await manager.stopServer(server.name);
        await process.closeStreams();
      }
    },
  );

  test('rejects invalid timeout and buffer limits at runtime', () {
    Future<Process> starter(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    }) {
      throw UnimplementedError();
    }

    expect(
      () => McpStdioProcessManager.forTesting(
        processStarter: starter,
        processStartTimeout: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => McpStdioProcessManager.forTesting(
        processStarter: starter,
        responseBufferLimit: 0,
      ),
      throwsArgumentError,
    );
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Condition was not reached before the test deadline');
}

class _FakeProcess implements Process {
  _FakeProcess({
    required this.pid,
    required this.completeExitOnKill,
    this.completeExitOnSigkill = false,
    Completer<void>? stdoutCancelGate,
  }) : _stdoutController = StreamController<List<int>>(
         onCancel: stdoutCancelGate == null
             ? null
             : () => stdoutCancelGate.future,
       ) {
    _stdinSubscription = _stdinController.stream.listen(_receiveInput);
  }

  final bool completeExitOnKill;
  final bool completeExitOnSigkill;
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  late final StreamSubscription<List<int>> _stdinSubscription;
  late final IOSink _stdin = IOSink(_stdinController.sink);
  String _stdinBuffer = '';

  bool wasKilled = false;
  final List<ProcessSignal> killSignals = <ProcessSignal>[];

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

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    wasKilled = true;
    killSignals.add(signal);
    if (completeExitOnKill ||
        (completeExitOnSigkill && signal == ProcessSignal.sigkill)) {
      completeExit(-15);
    }
    return true;
  }

  void completeExit(int code) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
  }

  void emitStdout(String data) {
    if (!_stdoutController.isClosed) {
      _stdoutController.add(utf8.encode(data));
    }
  }

  Future<void> closeStreams() async {
    await _stdinSubscription.cancel();
    if (!_stdinController.isClosed) {
      await _stdinController.close();
    }
    if (!_stdoutController.isClosed) {
      await _stdoutController.close();
    }
    if (!_stderrController.isClosed) {
      await _stderrController.close();
    }
  }

  void _receiveInput(List<int> bytes) {
    _stdinBuffer += utf8.decode(bytes);
    while (true) {
      final newline = _stdinBuffer.indexOf('\n');
      if (newline < 0) {
        return;
      }
      final line = _stdinBuffer.substring(0, newline).trim();
      _stdinBuffer = _stdinBuffer.substring(newline + 1);
      if (line.isEmpty) {
        continue;
      }
      final message = jsonDecode(line) as Map<String, Object?>;
      if (message['method'] == 'initialize') {
        final response = jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': message['id'],
          'result': <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
            'serverInfo': <String, Object?>{
              'name': 'fake-mcp',
              'version': '1.0.0',
            },
          },
        });
        _stdoutController.add(utf8.encode('$response\n'));
      }
    }
  }
}

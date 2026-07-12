import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/lsp/web_reverse_lsp_client.dart';

void main() {
  test('concurrent starts share one process and initialization', () async {
    var spawnCount = 0;
    final process = _FakeLspProcess(respondToInitialize: true);
    final client = _createClient(
      processStarter: _starter((_) {
        spawnCount += 1;
        return Future<Process>.value(process);
      }),
    );

    try {
      final results = await Future.wait<bool>(<Future<bool>>[
        client.start(),
        client.start(),
        client.start(),
      ]);

      expect(results, everyElement(isTrue));
      expect(spawnCount, 1);
      expect(process.receivedMethods.where((item) => item == 'initialize'), [
        'initialize',
      ]);
      expect(client.status, WebReverseLspStatus.ready);
    } finally {
      await client.stop();
    }
  });

  test('initialize timeout terminates the process and permits retry', () async {
    final processes = <_FakeLspProcess>[];
    final terminated = <Process>[];
    final client = _createClient(
      requestTimeout: const Duration(milliseconds: 30),
      processStarter: _starter((_) {
        final process = _FakeLspProcess(
          respondToInitialize: processes.isNotEmpty,
        );
        processes.add(process);
        return Future<Process>.value(process);
      }),
      processTerminator: (process) async {
        terminated.add(process);
        process.kill();
        await process.exitCode;
      },
    );

    try {
      expect(await client.start(), isFalse);
      expect(client.status, WebReverseLspStatus.failed);
      expect(processes, hasLength(1));
      expect(terminated, contains(same(processes.first)));

      expect(await client.start(), isTrue);
      expect(processes, hasLength(2));
      expect(client.status, WebReverseLspStatus.ready);
      expect(client.lastError, isNull);
    } finally {
      await client.stop();
    }
  });

  test(
    'stop rejects and terminates a process that finishes spawning late',
    () async {
      final pendingSpawn = Completer<Process>();
      final terminated = <Process>[];
      var spawnCount = 0;
      final client = _createClient(
        processStarter: _starter((_) {
          spawnCount += 1;
          return pendingSpawn.future;
        }),
        processTerminator: (process) async {
          terminated.add(process);
          process.kill();
          await process.exitCode;
        },
      );

      final starting = client.start();
      await _waitUntil(() => spawnCount == 1);
      await client.stop();
      expect(client.status, WebReverseLspStatus.idle);

      final lateProcess = _FakeLspProcess(respondToInitialize: true);
      pendingSpawn.complete(lateProcess);
      expect(await starting, isFalse);
      expect(terminated, contains(same(lateProcess)));
      expect(lateProcess.wasKilled, isTrue);
      expect(client.status, WebReverseLspStatus.idle);
    },
  );

  test(
    'startup timeout returns promptly and cleans up a late process',
    () async {
      final pendingSpawn = Completer<Process>();
      final terminated = <Process>[];
      final client = _createClient(
        startupTimeout: const Duration(milliseconds: 30),
        processStarter: _starter((_) => pendingSpawn.future),
        processTerminator: (process) async {
          terminated.add(process);
          process.kill();
          await process.exitCode;
        },
      );

      expect(await client.start(), isFalse);
      expect(client.status, WebReverseLspStatus.failed);
      expect(client.lastError, 'process startup timeout');

      final lateProcess = _FakeLspProcess(respondToInitialize: true);
      pendingSpawn.complete(lateProcess);
      await _waitUntil(() => lateProcess.wasKilled);
      expect(terminated, contains(same(lateProcess)));
      await client.stop();
    },
  );

  test('stale process events cannot corrupt a replacement session', () async {
    final processes = <_FakeLspProcess>[];
    final terminated = <Process>[];
    final firstTerminationGate = Completer<void>();
    final client = _createClient(
      processStarter: _starter((_) {
        final process = _FakeLspProcess(respondToInitialize: true);
        processes.add(process);
        return Future<Process>.value(process);
      }),
      processTerminator: (process) async {
        terminated.add(process);
        if (identical(process, processes.first)) {
          await firstTerminationGate.future;
          return;
        }
        process.kill();
        await process.exitCode;
      },
    );

    try {
      expect(await client.start(), isTrue);
      const uri = 'untitled:test.js';
      await client.openOrChange(
        uri: uri,
        languageId: 'javascript',
        text: 'const value = 1;',
      );
      await _waitUntil(
        () => processes.first.receivedMethods.contains('textDocument/didOpen'),
      );
      expect(processes.first.receivedMethods.last, 'textDocument/didOpen');

      processes.first.emitStdout(utf8.encode('Content-Length: 3\r\n\r\nnot'));
      await _waitUntil(() => client.status == WebReverseLspStatus.failed);
      expect(terminated, contains(same(processes.first)));

      var replacementStarted = false;
      final replacementStart = client.start().then((result) {
        replacementStarted = true;
        return result;
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(processes, hasLength(1));
      expect(replacementStarted, isFalse);

      firstTerminationGate.complete();
      expect(await replacementStart, isTrue);
      await client.openOrChange(
        uri: uri,
        languageId: 'javascript',
        text: 'const value = 2;',
      );
      await _waitUntil(
        () => processes.last.receivedMethods.contains('textDocument/didOpen'),
      );
      expect(processes.last.receivedMethods.last, 'textDocument/didOpen');

      processes.first.completeExit(17);
      await Future<void>.delayed(Duration.zero);
      expect(client.status, WebReverseLspStatus.ready);
    } finally {
      if (!firstTerminationGate.isCompleted) firstTerminationGate.complete();
      processes.first.kill();
      await client.stop();
    }
  });

  test('concurrent stops share the in-flight process cleanup', () async {
    final process = _FakeLspProcess(respondToInitialize: true);
    final terminationGate = Completer<void>();
    var terminationCount = 0;
    final client = _createClient(
      processStarter: _starter((_) => Future<Process>.value(process)),
      processTerminator: (process) async {
        terminationCount += 1;
        await terminationGate.future;
        process.kill();
        await process.exitCode;
      },
    );

    expect(await client.start(), isTrue);
    final firstStop = client.stop();
    final secondStop = client.stop();
    var secondCompleted = false;
    unawaited(secondStop.then((_) => secondCompleted = true));

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(terminationCount, 1);
    expect(secondCompleted, isFalse);

    terminationGate.complete();
    await Future.wait<void>(<Future<void>>[firstStop, secondStop]);
    expect(secondCompleted, isTrue);
    expect(client.status, WebReverseLspStatus.idle);
  });

  test(
    'document versions increase deterministically and stderr is bounded',
    () async {
      final process = _FakeLspProcess(respondToInitialize: true);
      final client = _createClient(
        processStarter: _starter((_) => Future<Process>.value(process)),
      );

      try {
        expect(await client.start(), isTrue);
        for (var index = 0; index < 3; index += 1) {
          await client.openOrChange(
            uri: 'untitled:version.js',
            languageId: 'javascript',
            text: 'const value = $index;',
          );
        }
        await _waitUntil(() => process.documentVersions.length == 3);
        expect(process.documentVersions, <int>[1, 2, 3]);

        process.emitStderr(utf8.encode('x' * 400));
        await Future<void>.delayed(Duration.zero);
        expect(client.lastError, hasLength(256));
      } finally {
        await client.stop();
      }
    },
  );
}

WebReverseLspClient _createClient({
  required WebReverseLspProcessStarter processStarter,
  WebReverseLspProcessTerminator? processTerminator,
  Duration requestTimeout = const Duration(milliseconds: 200),
  Duration startupTimeout = const Duration(milliseconds: 200),
}) {
  return WebReverseLspClient(
    requestTimeout: requestTimeout,
    startupTimeout: startupTimeout,
    processStarter: processStarter,
    processTerminator: processTerminator ?? _terminateFakeProcess,
  );
}

WebReverseLspProcessStarter _starter(
  Future<Process> Function(String executable) callback,
) {
  return (executable, arguments, {required runInShell, required environment}) {
    return callback(executable);
  };
}

Future<void> _terminateFakeProcess(Process process) async {
  process.kill();
  await process.exitCode;
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Condition was not reached before the test deadline');
}

class _FakeLspProcess implements Process {
  _FakeLspProcess({required this.respondToInitialize}) : _pid = _nextPid++ {
    _stdinSubscription = _stdinController.stream.listen(_receiveInput);
  }

  static int _nextPid = 20000;
  static final RegExp _contentLengthPattern = RegExp(
    r'Content-Length:\s*(\d+)',
  );

  final bool respondToInitialize;
  final int _pid;
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  late final StreamSubscription<List<int>> _stdinSubscription;
  late final IOSink _stdin = IOSink(_stdinController.sink);
  String _inputBuffer = '';
  bool _closed = false;

  bool wasKilled = false;
  final List<Map<String, Object?>> receivedMessages = <Map<String, Object?>>[];

  List<String> get receivedMethods => receivedMessages
      .map((message) => '${message['method'] ?? ''}')
      .toList(growable: false);

  List<int> get documentVersions => receivedMessages
      .where(
        (message) =>
            message['method'] == 'textDocument/didOpen' ||
            message['method'] == 'textDocument/didChange',
      )
      .map((message) {
        final params = message['params'] as Map<String, Object?>;
        final document = params['textDocument'] as Map<String, Object?>;
        return document['version']! as int;
      })
      .toList(growable: false);

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => _pid;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (wasKilled) return false;
    wasKilled = true;
    completeExit(signal == ProcessSignal.sigkill ? -9 : -15);
    unawaited(_closeStreams());
    return true;
  }

  void emitStdout(List<int> bytes) {
    if (!_stdoutController.isClosed) _stdoutController.add(bytes);
  }

  void emitStderr(List<int> bytes) {
    if (!_stderrController.isClosed) _stderrController.add(bytes);
  }

  void completeExit([int code = 0]) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }

  void _receiveInput(List<int> bytes) {
    _inputBuffer += utf8.decode(bytes);
    while (true) {
      final headerEnd = _inputBuffer.indexOf('\r\n\r\n');
      if (headerEnd < 0) return;
      final lengthMatch = _contentLengthPattern.firstMatch(
        _inputBuffer.substring(0, headerEnd),
      );
      if (lengthMatch == null) return;
      final contentLength = int.parse(lengthMatch.group(1)!);
      final bodyStart = headerEnd + 4;
      final bodyEnd = bodyStart + contentLength;
      if (_inputBuffer.length < bodyEnd) return;
      final message =
          jsonDecode(_inputBuffer.substring(bodyStart, bodyEnd))
              as Map<String, Object?>;
      _inputBuffer = _inputBuffer.substring(bodyEnd);
      receivedMessages.add(message);
      if (message['method'] == 'initialize' && respondToInitialize) {
        _respond(message['id']);
      }
    }
  }

  void _respond(Object? id) {
    final response = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{'capabilities': <String, Object?>{}},
    });
    emitStdout(
      utf8.encode(
        'Content-Length: ${utf8.encode(response).length}\r\n\r\n$response',
      ),
    );
  }

  Future<void> _closeStreams() async {
    if (_closed) return;
    _closed = true;
    await _stdin.close();
    await _stdinSubscription.cancel();
    await _stdoutController.close();
    await _stderrController.close();
  }
}

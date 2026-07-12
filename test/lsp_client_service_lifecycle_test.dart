import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_lsp_language_settings.dart';
import 'package:openhand/features/ai/service/lsp/lsp_client_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory workspace;
  late String sourcePath;
  late String executablePath;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('openhand_lsp_test_');
    sourcePath = p.join(workspace.path, 'lib', 'sample.dart');
    executablePath = p.join(workspace.path, 'dart');
    await Directory(p.dirname(sourcePath)).create(recursive: true);
    await File(sourcePath).writeAsString('void main() {}\n');
    await File(
      p.join(workspace.path, 'pubspec.yaml'),
    ).writeAsString('name: lsp_lifecycle_test\n');
    // Backend resolution validates the configured path before invoking the
    // injected launcher. The in-memory process itself never executes this.
    await File(executablePath).writeAsString('test executable placeholder\n');
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  test('concurrent cache misses share one session startup', () async {
    var launchCount = 0;
    late _FakeLspProcess process;
    final service = await _createService(
      executablePath: executablePath,
      launcher: ({required backend, environment}) async {
        launchCount += 1;
        process = _FakeLspProcess(_InitializeBehavior.success);
        return process;
      },
    );

    try {
      await Future.wait<void>(<Future<void>>[
        service.syncDocument(
          filePath: sourcePath,
          documentText: 'void main() {}\n',
          language: 'dart',
        ),
        service.syncDocument(
          filePath: sourcePath,
          documentText: 'void main() {}\n',
          language: 'dart',
        ),
      ]);

      expect(launchCount, 1);
      expect(process.wasKilled, isFalse);
    } finally {
      await service.disposeAll();
    }

    expect(process.wasKilled, isTrue);
  });

  test('initialize timeout shuts down the process and permits retry', () async {
    final processes = <_FakeLspProcess>[];
    final service = await _createService(
      executablePath: executablePath,
      requestTimeout: const Duration(milliseconds: 50),
      launcher: ({required backend, environment}) async {
        final process = _FakeLspProcess(
          processes.isEmpty
              ? _InitializeBehavior.noResponse
              : _InitializeBehavior.success,
        );
        processes.add(process);
        return process;
      },
    );

    try {
      await expectLater(
        service.syncDocument(
          filePath: sourcePath,
          documentText: 'void main() {}\n',
          language: 'dart',
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(processes, hasLength(1));
      expect(processes.single.wasKilled, isTrue);

      await service.syncDocument(
        filePath: sourcePath,
        documentText: 'void main() {}\n',
        language: 'dart',
      );
      expect(processes, hasLength(2));
      expect(processes.last.wasKilled, isFalse);
    } finally {
      await service.disposeAll();
    }

    expect(processes.last.wasKilled, isTrue);
  });

  test('unexpected exit fails pending work and starts a new session', () async {
    final processes = <_FakeLspProcess>[];
    var launchCount = 0;
    final service = await _createService(
      executablePath: executablePath,
      requestTimeout: const Duration(seconds: 2),
      launcher: ({required backend, environment}) async {
        launchCount += 1;
        final process = _FakeLspProcess(_InitializeBehavior.success);
        processes.add(process);
        return process;
      },
    );

    try {
      await service.syncDocument(
        filePath: sourcePath,
        documentText: 'void main() {}\n',
        language: 'dart',
      );
      final firstProcess = processes.single;
      final pendingRequest = service.request(
        operation: 'goToDefinition',
        filePath: sourcePath,
        line: 1,
        character: 1,
        language: 'dart',
        documentText: 'void main() {}\n',
      );
      await _waitUntil(
        () => firstProcess.receivedMethods.contains('textDocument/definition'),
      );

      firstProcess.completeExit(17);
      await expectLater(
        pendingRequest.timeout(const Duration(milliseconds: 500)),
        throwsStateError,
      );

      await service.syncDocument(
        filePath: sourcePath,
        documentText: 'void main() {}\n',
        language: 'dart',
      );
      expect(launchCount, 2);
      expect(processes.last, isNot(same(firstProcess)));
    } finally {
      await service.disposeAll();
    }
  });

  test(
    'dispose rejects a late startup without replacing the new session',
    () async {
      final firstLaunch = Completer<Process>();
      final processes = <_FakeLspProcess>[];
      var launchCount = 0;
      final service = await _createService(
        executablePath: executablePath,
        startupDisposeWait: const Duration(milliseconds: 20),
        launcher: ({required backend, environment}) {
          launchCount += 1;
          if (launchCount == 1) {
            return firstLaunch.future;
          }
          final process = _FakeLspProcess(_InitializeBehavior.success);
          processes.add(process);
          return Future<Process>.value(process);
        },
      );

      try {
        final staleRequest = service.syncDocument(
          filePath: sourcePath,
          documentText: 'void main() {}\n',
          language: 'dart',
        );
        await _waitUntil(() => launchCount == 1);
        final staleExpectation = expectLater(staleRequest, throwsStateError);

        final disposeFuture = service.disposeAll();
        await service.syncDocument(
          filePath: sourcePath,
          documentText: 'void main() {}\n',
          language: 'dart',
        );
        expect(launchCount, 2);

        // Disposal is bounded even though the process launcher has not returned.
        await disposeFuture;
        final staleProcess = _FakeLspProcess(_InitializeBehavior.success);
        firstLaunch.complete(staleProcess);
        await staleExpectation;

        expect(staleProcess.wasKilled, isTrue);
        expect(processes.single.wasKilled, isFalse);

        // The stale completion must not overwrite (or evict) generation two.
        await service.syncDocument(
          filePath: sourcePath,
          documentText: 'void main() {}\n',
          language: 'dart',
        );
        expect(launchCount, 2);
      } finally {
        if (!firstLaunch.isCompleted) {
          firstLaunch.complete(_FakeLspProcess(_InitializeBehavior.success));
        }
        await service.disposeAll();
      }
    },
  );

  test('uses callbacks owned by the isolated service instance', () async {
    late _FakeLspProcess process;
    final service = await _createService(
      executablePath: executablePath,
      launcher: ({required backend, environment}) async {
        process = _FakeLspProcess(_InitializeBehavior.success);
        return process;
      },
    );
    final diagnosticsPushed = Completer<String>();
    final editHandled = Completer<void>();
    service.diagnosticsPushCallback = (filePath, diagnostics) {
      if (!diagnosticsPushed.isCompleted) diagnosticsPushed.complete(filePath);
    };
    service.workspaceEditHandler = (edit) async {
      if (!editHandled.isCompleted) editHandled.complete();
      return true;
    };

    try {
      await service.syncDocument(
        filePath: sourcePath,
        documentText: 'void main() {}\n',
        language: 'dart',
      );
      final uri = Uri.file(sourcePath).toString();
      process.emitMessage(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'textDocument/publishDiagnostics',
        'params': <String, Object?>{
          'uri': uri,
          'diagnostics': const <Object?>[],
        },
      });
      expect(
        await diagnosticsPushed.future.timeout(
          const Duration(milliseconds: 200),
        ),
        sourcePath,
      );

      process.emitMessage(_workspaceApplyEditRequest(uri: uri, id: 700));
      await editHandled.future.timeout(const Duration(milliseconds: 200));
      await _waitUntil(
        () => process.receivedMessages.any(
          (message) =>
              message['id'] == 700 &&
              (message['result'] as Map?)?['applied'] == true,
        ),
      );
    } finally {
      await service.disposeAll();
    }
  });

  test('bounds and serializes server workspace edit requests', () async {
    late _FakeLspProcess process;
    final service = await _createService(
      executablePath: executablePath,
      launcher: ({required backend, environment}) async {
        process = _FakeLspProcess(_InitializeBehavior.success);
        return process;
      },
    );
    final releaseFirst = Completer<void>();
    var handlerCalls = 0;
    var activeHandlers = 0;
    var maxActiveHandlers = 0;
    service.workspaceEditHandler = (edit) async {
      handlerCalls += 1;
      activeHandlers += 1;
      if (activeHandlers > maxActiveHandlers) {
        maxActiveHandlers = activeHandlers;
      }
      if (handlerCalls == 1) await releaseFirst.future;
      await Future<void>.delayed(Duration.zero);
      activeHandlers -= 1;
      return true;
    };

    try {
      await service.syncDocument(
        filePath: sourcePath,
        documentText: 'void main() {}\n',
        language: 'dart',
      );
      final uri = Uri.file(sourcePath).toString();
      for (var index = 0; index < 40; index += 1) {
        process.emitMessage(
          _workspaceApplyEditRequest(uri: uri, id: 800 + index),
        );
      }
      await _waitUntil(
        () =>
            process.receivedMessages
                .where(
                  (message) =>
                      message['id'] is int &&
                      (message['id'] as int) >= 800 &&
                      (message['error'] as Map?)?['code'] == -32000,
                )
                .length ==
            8,
      );

      expect(handlerCalls, 1);
      expect(maxActiveHandlers, 1);

      releaseFirst.complete();
      await _waitUntil(
        () =>
            process.receivedMessages
                .where(
                  (message) =>
                      message['id'] is int &&
                      (message['id'] as int) >= 800 &&
                      (message['id'] as int) < 840 &&
                      (message.containsKey('result') ||
                          message.containsKey('error')),
                )
                .length ==
            40,
      );
      expect(handlerCalls, 32);
      expect(maxActiveHandlers, 1);
    } finally {
      if (!releaseFirst.isCompleted) releaseFirst.complete();
      await service.disposeAll();
    }
  });

  test(
    'rejects an oversized protocol header and releases the session',
    () async {
      late _FakeLspProcess process;
      final service = await _createService(
        executablePath: executablePath,
        requestTimeout: const Duration(seconds: 1),
        launcher: ({required backend, environment}) async {
          process = _FakeLspProcess(_InitializeBehavior.success);
          return process;
        },
      );

      try {
        await service.syncDocument(
          filePath: sourcePath,
          documentText: 'void main() {}\n',
          language: 'dart',
        );
        final request = service.request(
          operation: 'goToDefinition',
          filePath: sourcePath,
          line: 1,
          character: 1,
          language: 'dart',
          documentText: 'void main() {}\n',
        );
        await _waitUntil(
          () => process.receivedMethods.contains('textDocument/definition'),
        );
        final rejected = expectLater(request, throwsA(isA<FormatException>()));
        process.emitRaw(List<int>.filled(64 * 1024 + 1, 65));

        await rejected;
        await _waitUntil(() => process.wasKilled);
      } finally {
        await service.disposeAll();
      }
    },
  );
}

Future<AiLspClientService> _createService({
  required String executablePath,
  required AiLspProcessLauncher launcher,
  Duration requestTimeout = const Duration(milliseconds: 100),
  Duration startupDisposeWait = const Duration(milliseconds: 100),
}) async {
  final service = AiLspClientService.forTesting(
    processLauncher: launcher,
    requestTimeout: requestTimeout,
    startupDisposeWait: startupDisposeWait,
  );
  service.updateLanguageSettings(<String, AiLspLanguageSettings>{
    'dart': AiLspLanguageSettings(
      backendId: 'dart-analysis-server',
      rootPath: executablePath,
    ),
  });
  // updateLanguageSettings invalidates sessions asynchronously. Let that
  // empty initial disposal finish before a test begins a startup generation.
  await Future<void>.delayed(Duration.zero);
  return service;
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Condition was not reached before the test deadline');
}

Map<String, Object?> _workspaceApplyEditRequest({
  required String uri,
  required int id,
}) {
  return <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'method': 'workspace/applyEdit',
    'params': <String, Object?>{
      'edit': <String, Object?>{
        'changes': <String, Object?>{
          uri: <Object?>[
            <String, Object?>{
              'range': <String, Object?>{
                'start': <String, Object?>{'line': 0, 'character': 0},
                'end': <String, Object?>{'line': 0, 'character': 0},
              },
              'newText': '// updated\n',
            },
          ],
        },
      },
    },
  };
}

enum _InitializeBehavior { success, noResponse }

class _FakeLspProcess implements Process {
  _FakeLspProcess(this.initializeBehavior) : _pid = _nextPid++ {
    _stdinSubscription = _stdinController.stream.listen(_receiveInput);
  }

  static int _nextPid = 10000;
  static final RegExp _contentLengthPattern = RegExp(
    r'Content-Length:\s*(\d+)',
  );

  final _InitializeBehavior initializeBehavior;
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
  final List<int> _inputBuffer = <int>[];

  bool wasKilled = false;
  final List<String> receivedMethods = <String>[];
  final List<Map<String, Object?>> receivedMessages = <Map<String, Object?>>[];

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
    if (wasKilled) {
      return false;
    }
    wasKilled = true;
    if (!_exitCode.isCompleted) {
      _exitCode.complete(-15);
    }
    unawaited(_stdinSubscription.cancel());
    unawaited(_stdinController.close());
    unawaited(_stdoutController.close());
    unawaited(_stderrController.close());
    return true;
  }

  void _receiveInput(List<int> bytes) {
    _inputBuffer.addAll(bytes);
    while (true) {
      final headerEnd = _findHeaderEnd(_inputBuffer);
      if (headerEnd < 0) return;
      final lengthMatch = _contentLengthPattern.firstMatch(
        latin1.decode(_inputBuffer.sublist(0, headerEnd)),
      );
      if (lengthMatch == null) return;
      final contentLength = int.parse(lengthMatch.group(1)!);
      final bodyStart = headerEnd + 4;
      final bodyEnd = bodyStart + contentLength;
      if (_inputBuffer.length < bodyEnd) return;
      final message =
          jsonDecode(utf8.decode(_inputBuffer.sublist(bodyStart, bodyEnd)))
              as Map<String, Object?>;
      _inputBuffer.removeRange(0, bodyEnd);
      _handleMessage(message);
    }
  }

  void _handleMessage(Map<String, Object?> message) {
    receivedMessages.add(message);
    receivedMethods.add('${message['method'] ?? ''}');
    if (message['method'] != 'initialize' ||
        initializeBehavior == _InitializeBehavior.noResponse) {
      return;
    }
    emitMessage(<String, Object?>{
      'jsonrpc': '2.0',
      'id': message['id'],
      'result': <String, Object?>{
        'capabilities': <String, Object?>{},
        'serverInfo': <String, Object?>{'name': '测试🙂 LSP'},
      },
    });
  }

  void emitMessage(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode(message));
    final frame = <int>[
      ...utf8.encode('Content-Length: ${body.length}\r\n\r\n'),
      ...body,
    ];
    const firstSplit = 7;
    final secondSplit = frame.length ~/ 2;
    _stdoutController
      ..add(frame.sublist(0, firstSplit))
      ..add(frame.sublist(firstSplit, secondSplit))
      ..add(frame.sublist(secondSplit));
  }

  void emitRaw(List<int> bytes) => _stdoutController.add(bytes);

  int _findHeaderEnd(List<int> bytes) {
    for (var index = 0; index + 3 < bytes.length; index += 1) {
      if (bytes[index] == 13 &&
          bytes[index + 1] == 10 &&
          bytes[index + 2] == 13 &&
          bytes[index + 3] == 10) {
        return index;
      }
    }
    return -1;
  }

  void completeExit([int code = 0]) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
    unawaited(_stdoutController.close());
    unawaited(_stderrController.close());
  }
}

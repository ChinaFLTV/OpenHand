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
  String _inputBuffer = '';

  bool wasKilled = false;
  final List<String> receivedMethods = <String>[];

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
    _inputBuffer += utf8.decode(bytes);
    while (true) {
      final headerEnd = _inputBuffer.indexOf('\r\n\r\n');
      if (headerEnd < 0) {
        return;
      }
      final lengthMatch = _contentLengthPattern.firstMatch(
        _inputBuffer.substring(0, headerEnd),
      );
      if (lengthMatch == null) {
        return;
      }
      final contentLength = int.parse(lengthMatch.group(1)!);
      final bodyStart = headerEnd + 4;
      final bodyEnd = bodyStart + contentLength;
      if (_inputBuffer.length < bodyEnd) {
        return;
      }
      final message =
          jsonDecode(_inputBuffer.substring(bodyStart, bodyEnd))
              as Map<String, Object?>;
      _inputBuffer = _inputBuffer.substring(bodyEnd);
      _handleMessage(message);
    }
  }

  void _handleMessage(Map<String, Object?> message) {
    receivedMethods.add('${message['method'] ?? ''}');
    if (message['method'] != 'initialize' ||
        initializeBehavior == _InitializeBehavior.noResponse) {
      return;
    }
    final response = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': message['id'],
      'result': <String, Object?>{'capabilities': <String, Object?>{}},
    });
    final framed =
        'Content-Length: ${utf8.encode(response).length}\r\n\r\n'
        '$response';
    _stdoutController.add(utf8.encode(framed));
  }

  void completeExit([int code = 0]) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
    unawaited(_stdoutController.close());
    unawaited(_stderrController.close());
  }
}

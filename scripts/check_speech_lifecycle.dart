import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final service = File(
    '${root.path}/lib/features/ai/service/operations/offline_speech_model_service.dart',
  );
  final source = await readFlutterCheckSource(service, root: root);
  await runFlutterWidgetCheck(
    root: root,
    name: 'speech_lifecycle',
    source:
        "import 'package:flutter_test/flutter_test.dart';\n$source\n$_checks",
  );
}

const _checks = r'''
class _SpeechService extends OfflineSpeechModelService {
  _SpeechService() : super._();

  @override
  Future<void> _inspectHardware() async {}

  // 生命周期检查连接本地服务，跳过仅允许 WSS 的生产地址校验。
  @override
  OfflineSpeechModelAvailability availabilityFor(OfflineSpeechModelDefinition model, Map<String, Object?> configuration) =>
      const OfflineSpeechModelAvailability(available: true, reason: '本地回归服务');
}

class _ObservedCancelFuture implements Future<void> {
  _ObservedCancelFuture(this.future);
  final Future<void> future;
  int listeners = 0;

  @override
  Future<R> then<R>(FutureOr<R> Function(void) onValue, {Function? onError}) {
    listeners++;
    return future.then<R>(onValue, onError: onError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

enum _SpeechMode { local, task, realtime, queued }

class _SpeechServer {
  _SpeechServer(this.server) {
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      final disconnected = Completer<void>();
      sockets[socket] = disconnected;
      socket.listen((event) {
        final waiting = heldRequest;
        if (waiting != null) {
          if (!waiting.isCompleted) waiting.complete();
          return;
        }
        final message = jsonDecode(event as String) as Map;
        final action = (message['header'] as Map?)?['action'];
        final type = message['type'];
        if (failRequests) {
          if (message.containsKey('operation') || type == 'text') {
            socket.add(jsonEncode({'type': 'error', 'message': '测试合成失败'}));
          } else if (message.containsKey('header')) {
            socket.add(jsonEncode({'header': {'event': 'task-failed', 'error_message': '测试合成失败'}}));
          } else if (message.containsKey('business')) {
            socket.add(jsonEncode({'code': 1, 'message': '测试合成失败'}));
          } else {
            socket.add(jsonEncode({'type': 'error', 'error': {'message': '测试合成失败'}}));
          }
          return;
        }
        if (message.containsKey('operation')) {
          socket.add(jsonEncode({'type': 'start', 'sample_rate': 16000, 'channels': 1}));
        } else if (action == 'run-task') {
          socket.add(jsonEncode({'header': {'event': 'task-started'}}));
        } else if (type == 'session.update') {
          socket.add(jsonEncode({'type': 'session.updated'}));
        } else if (type == 'text' || action == 'continue-task') {
          socket.add([1, 2, 3, 4]);
        } else if (type == 'input_text_buffer.append') {
          socket.add(jsonEncode({'type': 'response.audio.delta', 'delta': base64Encode([1, 2, 3, 4])}));
        } else if (type == 'finish') {
          socket.add(jsonEncode({'type': 'end'}));
        } else if (action == 'finish-task') {
          socket.add(jsonEncode({'header': {'event': 'task-finished'}}));
        } else if (type == 'session.finish') {
          socket.add(jsonEncode({'type': 'session.finished'}));
        } else if (message.containsKey('business')) {
          socket.add(jsonEncode({'code': 0, 'data': {'status': 2, 'audio': base64Encode([1, 2, 3, 4])}}));
        }
      }, onDone: () {
        sockets.remove(socket);
        disconnected.complete();
      });
    });
  }

  final HttpServer server;
  final Map<WebSocket, Completer<void>> sockets = {};
  bool failRequests = false;
  Completer<void>? heldRequest;

  Uri get endpoint => Uri.parse('ws://127.0.0.1:${server.port}/speech');

  static Future<_SpeechServer> start() async =>
      _SpeechServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Future<void> waitForDisconnect() async {
    await Future.wait(sockets.values.map((ended) => ended.future))
        .timeout(const Duration(seconds: 1));
  }

  Future<void> close() async {
    await Future.wait(sockets.keys.toList().map((socket) => socket.close()));
    await server.close(force: true);
  }
}

Future<OfflineSpeechAudioStream> _openSpeech(
  _SpeechService service,
  _SpeechServer server,
  _SpeechMode mode, {
  Future<void>? cancelSignal,
  Map<String, Object?> configurationOverrides = const {},
}) {
  if (mode == _SpeechMode.local) {
    return service._openRealtimeSpeechStream(server.endpoint, cancelSignal: cancelSignal);
  }
  final onlineService = switch (mode) {
    _SpeechMode.task => OnlineSpeechService.bailianTaskTts,
    _SpeechMode.realtime => OnlineSpeechService.bailianRealtimeTts,
    _ => OnlineSpeechService.xfyunTts,
  };
  final model = OfflineSpeechModelCatalog.models.firstWhere((model) => model.onlineService == onlineService);
  final configuration = <String, Object?>{
    ...model.normalizeConfiguration(null),
    'endpoint': '${server.endpoint}',
    'api_key': 'test',
    'auth_mode': 'api_password',
    'api_password': 'test',
    'tte': 'UTF8',
    'mode': 'server_commit',
    ...configurationOverrides,
  };
  return service.startSynthesisStream(model, configuration: configuration, cancelSignal: cancelSignal);
}

void main() {
  for (final mode in _SpeechMode.values) {
    group('语音流 ${mode.name}', () {
      late _SpeechServer server;
      late _SpeechService service;
      setUp(() async {
        server = await _SpeechServer.start();
        service = _SpeechService();
      });
      tearDown(() async {
        await service.shutdown();
        await server.close();
      });

      for (final paused in [false, true]) {
        test('${paused ? '暂停' : '未订阅'}音频仍能关闭，并发关闭等待同一清理', () async {
          final stream = await _openSpeech(service, server, mode);
          final subscription = paused ? stream.audio.listen((_) {}) : null;
          subscription?.pause();
          try {
            await Future.wait([stream.close(), stream.close()]).timeout(const Duration(seconds: 1));
            await stream.done.timeout(const Duration(seconds: 1));
            expect(() => stream.addText('已关闭'), throwsStateError);
          } finally {
            await subscription?.cancel();
          }
        });
      }

      test('正常结束不依赖消费者，晚订阅仍收到完整音频', () async {
        final stream = await _openSpeech(service, server, mode);
        stream.addText('生命周期检查');
        await stream.finish().timeout(const Duration(seconds: 3));
        await stream.done.timeout(const Duration(seconds: 3));
        final chunks = await stream.audio.toList().timeout(const Duration(seconds: 1));
        expect(chunks.expand((chunk) => chunk).toList(), [1, 2, 3, 4]);
        await stream.close();
      });

      test('异常完成的取消信号安全关闭且复用单个监听', () async {
        final cancellation = Completer<void>();
        final signal = _ObservedCancelFuture(cancellation.future);
        for (var index = 0; index < 3; index++) {
          final stream = await _openSpeech(service, server, mode, cancelSignal: signal);
          await stream.close().timeout(const Duration(seconds: 1));
        }
        final active = await _openSpeech(service, server, mode, cancelSignal: signal);
        cancellation.completeError(StateError('取消信号异常'));
        await active.done.timeout(const Duration(seconds: 1));
        await active.close().timeout(const Duration(seconds: 1));
        expect(signal.listeners, 1);
      });

      test('提前失败不会产生孤立错误，稍后仍可读取失败原因', () async {
        final stream = await _openSpeech(service, server, mode);
        server.failRequests = true;
        stream.addText('触发失败');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await expectLater(stream.done, throwsStateError);
        await expectLater(stream.finish(), throwsStateError);
        final errors = <Object>[];
        final subscription = stream.audio.listen((_) {}, onError: errors.add);
        await stream.close().timeout(const Duration(seconds: 1));
        await Future<void>.delayed(Duration.zero);
        expect(errors, hasLength(1));
        await subscription.cancel();
      });

      test('合成期间取消会释放正在等待响应的连接', () async {
        final cancellation = Completer<void>();
        final stream = await _openSpeech(service, server, mode, cancelSignal: cancellation.future);
        final waiting = server.heldRequest = Completer<void>();
        stream.addText('等待期间取消');
        await waiting.future.timeout(const Duration(seconds: 1));
        cancellation.completeError(StateError('取消正在合成的语音'));
        await stream.done.timeout(const Duration(seconds: 1));
        await stream.close().timeout(const Duration(seconds: 1));
        await server.waitForDisconnect();
      });

      if (mode != _SpeechMode.queued) {
        test('启动失败及时抛出并释放连接', () async {
          server.failRequests = true;
          await expectLater(
            _openSpeech(service, server, mode).timeout(const Duration(seconds: 1)),
            throwsStateError,
          );
          await server.waitForDisconnect();
          expect(server.sockets, isEmpty);
        });

        test('启动期间取消不等待未订阅音频结束', () async {
          final waiting = server.heldRequest = Completer<void>();
          final cancellation = Completer<void>();
          final rejected = expectLater(
            _openSpeech(service, server, mode, cancelSignal: cancellation.future)
                .timeout(const Duration(seconds: 1)),
            throwsA(isA<OfflineSpeechTestCancelled>()),
          );
          await waiting.future.timeout(const Duration(seconds: 1));
          cancellation.completeError(StateError('取消启动'));
          await rejected;
          await server.waitForDisconnect();
        });
      }

      if (mode == _SpeechMode.task) {
        test('启动参数解析失败保留原始错误，清理不产生孤立取消异常', () async {
          await expectLater(
            _openSpeech(service, server, mode,
              configurationOverrides: {'hot_fix_pronunciation': '['},
            ).timeout(const Duration(seconds: 1)),
            throwsFormatException,
          );
          await server.waitForDisconnect();
          expect(server.sockets, isEmpty);
        });
      }
    });
  }
}
''';

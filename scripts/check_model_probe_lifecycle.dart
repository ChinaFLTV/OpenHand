import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'model_probe_lifecycle',
  source: _checks,
);

const _checks = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_operation_routing.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/model_registry/ai_model_scanner.dart';
import 'package:openhand/features/services/ai_model_health_controller.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';
import 'package:openhand/features/services/service/ai_exposure_proxy_probe.dart';
import 'package:openhand/features/ai/service/usage/ai_usage_tracker.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:openhand/shared/util/localized_text.dart';

const timeout = Duration(seconds: 2);

final class ObservedCancelFuture implements Future<void> {
  ObservedCancelFuture(this.future);
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

class ObservedHealthCancellation extends AiModelHealthCancellation {
  ObservedHealthCancellation() { signal = ObservedCancelFuture(super.whenCancelled); }
  late final ObservedCancelFuture signal;
  @override
  Future<void> get whenCancelled => signal;
}

class ObservedProxyCancellation extends AiExposureProxyProbeCancellation {
  ObservedProxyCancellation() { signal = ObservedCancelFuture(super.whenCancelled); }
  late final ObservedCancelFuture signal;
  @override
  Future<void> get whenCancelled => signal;
}

AiModelConfig model({AiProtocolType protocol = AiProtocolType.stepfun, String? baseUrl}) => AiModelConfig(
  id: '测试配置',
  baseUrl: baseUrl ?? 'https://api.stepfun.com/step_plan/v1',
  modelId: 'step-test',
  authScheme: AiAuthScheme.bearer,
  token: 'test-token',
  protocolType: protocol,
);

http.StreamedResponse response(Object body, [int status = 200]) => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode(body))), status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.StreamedResponse failure() => response({'error': {'message': '测试接口不可用'}}, 404);

class ProbeClient extends http.BaseClient {
  ProbeClient(this.handler);
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest) handler;
  final paths = <String>[];
  bool closed = false;
  int sendsAfterClose = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) {
      sendsAfterClose++;
      throw http.ClientException('客户端已关闭。', request.url);
    }
    paths.add(request.url.path);
    final operation = Future.sync(() => handler(request));
    if (request is http.AbortableRequest && request.abortTrigger != null) {
      return Future.any([
        operation,
        request.abortTrigger!.then<http.StreamedResponse>((_) => throw http.RequestAbortedException(request.url)),
      ]);
    }
    return operation;
  }

  @override
  void close() { closed = true; }
}

class ProbeTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  ProbeTestBinding();
  openHandAmbientLocale = const Locale('zh', 'CN');
  late Directory databaseDirectory;
  late DatabaseService database;
  final diagnostics = <String>[];
  final originalDebugPrint = debugPrint;
  setUpAll(() async {
    databaseDirectory = await Directory.systemTemp.createTemp('模型探测检查');
    database = await DatabaseService.initialize(
      databasePath: '${databaseDirectory.path}/test.db',
      useNoIsolateFactory: true,
    );
    debugPrint = (message, {wrapWidth}) {
      if (message != null) diagnostics.add(message);
    };
  });
  setUp(diagnostics.clear);
  tearDown(() async {
    await pumpEventQueue();
    await AiUsageTracker.instance.flush();
    expect(diagnostics, isEmpty, reason: '取消和诊断不应产生忽略异常日志。');
  });
  tearDownAll(() async {
    debugPrint = originalDebugPrint;
    await database.close();
    await databaseDirectory.delete(recursive: true);
  });

  test('已取消的测试和扫描不发送请求', () async {
    final client = ProbeClient((_) => failure());
    final service = AiChatService(client: client);
    final scanner = AiModelScanner(httpClient: client);
    addTearDown(service.dispose);
    addTearDown(scanner.dispose);
    final cancel = Completer<void>()..complete();
    await expectLater(service.testModel(model(), responseTimeout: timeout, cancelSignal: cancel.future), throwsA(isA<AiChatCancelledException>()));
    await expectLater(scanner.scan(model(), cancelSignal: cancel.future), throwsA(isA<http.RequestAbortedException>()));
    expect(client.paths, isEmpty);
  });

  for (final phase in ['responses', 'chat/completions', 'models']) {
    for (final dispose in [false, true]) {
      test('${dispose ? '释放服务' : '取消并关闭客户端'}停止 $phase 阶段及后续诊断', () async {
        final entered = Completer<void>();
        final pending = Completer<http.StreamedResponse>();
        final aborted = Completer<void>();
        final client = ProbeClient((request) {
          if (!request.url.path.endsWith('/$phase')) return failure();
          final abortable = request as http.AbortableRequest;
          abortable.abortTrigger!.then((_) { if (!aborted.isCompleted) aborted.complete(); });
          entered.complete();
          return pending.future;
        });
        final service = AiChatService(client: client);
        addTearDown(service.dispose);
        final cancel = Completer<void>();
        final result = service.testModel(model(), responseTimeout: timeout, cancelSignal: cancel.future);
        final checked = expectLater(result, throwsA(isA<AiChatCancelledException>()));
        await entered.future.timeout(timeout);
        final sent = client.paths.length;
        if (dispose) {
          service.dispose();
          expect(client.closed, isFalse);
        } else {
          cancel.complete();
          client.close();
        }
        await checked.timeout(timeout);
        await aborted.future.timeout(timeout);
        pending.complete(failure());
        await pumpEventQueue();
        expect(client.paths.length, sent);
        expect(client.sendsAfterClose, 0);
      });
    }
  }

  test('双端点失败保留模型目录补充，连续测试不误关共享客户端', () async {
    final client = ProbeClient((request) => request.url.path.endsWith('/models')
      ? response({'data': [{'id': 'step-test'}]}) : failure());
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    for (var index = 0; index < 2; index++) {
      await expectLater(service.testModel(model(), responseTimeout: timeout), throwsA(isA<AiChatException>()
        .having((e) => e.sources?.length, '诊断来源数量', 3)
        .having((e) => e.sources!.last.body, '模型目录诊断', contains('已包含当前模型'))));
      expect(client.closed, isFalse);
    }
    expect(client.paths.where((path) => path.endsWith('/models')).length, 2);
  });

  test('Responses 不可用时仍可通过聊天接口验证成功', () async {
    final client = ProbeClient((request) => request.url.path.endsWith('/chat/completions')
      ? response({'choices': [{'message': {'role': 'assistant', 'content': 'OK'}, 'finish_reason': 'stop'}]}) : failure());
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    final result = await service.testModel(model(), responseTimeout: timeout);
    expect(result.reply, 'OK');
    expect(result.chatApiFamily, AiApiFamily.chatCompletions);
    expect(client.paths.any((path) => path.endsWith('/models')), isFalse);
  });

  test('扫描的普通客户端异常保留明确网络诊断', () async {
    final client = ProbeClient((_) => throw http.ClientException('测试连接被重置。'));
    final scanner = AiModelScanner(httpClient: client);
    addTearDown(scanner.dispose);
    final result = await scanner.scan(model());
    expect(result.isSuccess, isFalse);
    expect(result.error, contains('测试连接被重置'));
  });

  for (final protocol in [AiProtocolType.ollama, AiProtocolType.claude, AiProtocolType.gemini]) {
    test('$protocol 扫描取消后不回退、不翻页、不返回部分成功', () async {
      final cancel = Completer<void>();
      final client = ProbeClient((_) {
        cancel.complete();
        if (protocol == AiProtocolType.ollama) throw http.RequestAbortedException();
        return response({
          'data': [{'id': 'step-test'}], 'has_more': true, 'last_id': 'step-test',
          'models': [{'name': 'models/step-test'}], 'nextPageToken': '下一页',
        });
      });
      final scanner = AiModelScanner(httpClient: client);
      addTearDown(scanner.dispose);
      await expectLater(scanner.scan(model(protocol: protocol), cancelSignal: cancel.future), throwsA(isA<http.RequestAbortedException>()));
      expect(client.paths.length, 1);
    });
  }

  test('模型目录超时中止请求并保留原始双端点错误', () async {
    final pending = Completer<http.StreamedResponse>();
    final aborted = Completer<void>();
    final client = ProbeClient((request) {
      if (!request.url.path.endsWith('/models')) return failure();
      (request as http.AbortableRequest).abortTrigger!.then((_) => aborted.complete());
      return pending.future;
    });
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    await expectLater(service.testModel(model(), responseTimeout: const Duration(milliseconds: 30)),
      throwsA(isA<AiChatException>().having((error) => error.sources?.length, '诊断来源数量', 3)));
    await aborted.future.timeout(timeout);
    pending.complete(failure());
    expect(client.paths.length, 3);
    expect(client.closed, isFalse);
  });

  test('取消一个并发测试不会关闭共享客户端或中断另一个测试', () async {
    final entered = Completer<void>();
    final pending = Completer<http.StreamedResponse>();
    final client = ProbeClient((request) {
      final body = jsonDecode((request as http.Request).body) as Map;
      if (body['model'] == 'step-test') {
        entered.complete();
        return pending.future;
      }
      return response({'choices': [{'message': {'role': 'assistant', 'content': 'OK'}, 'finish_reason': 'stop'}]});
    });
    final service = AiChatService(client: client);
    addTearDown(service.dispose);
    final cancel = Completer<void>();
    final cancelled = expectLater(service.testModel(model(), responseTimeout: timeout, cancelSignal: cancel.future),
      throwsA(isA<AiChatCancelledException>()));
    await entered.future.timeout(timeout);
    cancel.complete();
    await cancelled;
    final other = model().copyWith(modelId: 'step-other', capabilityOverrides: {AiApiFamily.responses: 'disabled'});
    final result = await service.sendMessage(model: other, messages: const [AiChatTurn(role: AiChatRole.user, content: '测试')], timeout: timeout);
    expect(result.reply, 'OK');
    expect(client.closed, isFalse);
    pending.complete(failure());
  });

  test('已释放服务拒绝新测试且不触发扫描', () async {
    final client = ProbeClient((_) => failure());
    final service = AiChatService(client: client)..dispose();
    final scanner = AiModelScanner(httpClient: client)..dispose();
    await expectLater(service.testModel(model(), responseTimeout: timeout), throwsStateError);
    await expectLater(scanner.scan(model()), throwsStateError);
    expect(client.paths, isEmpty);
    expect(client.closed, isFalse);
  });

  test('Jev 健康检查使用决策请求并复用整批取消监听', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final paths = <String>[];
    final subscription = server.listen((request) async {
      paths.add(request.uri.path);
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body.keys.toSet(), {'model', 'state', 'questions'});
      expect(body['model'], 'custom-router');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'answers': {
        for (final key in (body['questions'] as Map).keys) key: {'type': 'noul', 'noul': 1},
      }}));
      await request.response.close();
    });
    addTearDown(subscription.cancel);
    final controller = AiModelHealthController();
    addTearDown(controller.dispose);
    final config = model(protocol: AiProtocolType.jev, baseUrl: 'http://127.0.0.1:${server.port}').copyWith(
      modelId: 'custom-router', operationRouting: const AiOperationRouting(imageModelId: 'custom-router'));
    final cancellation = ObservedHealthCancellation();
    for (var i = 0; i < 3; i++) {
      final record = await controller.checkModel(config, cancellation: cancellation);
      expect(record?.success, isTrue, reason: record?.errorMessage);
      expect(record?.modelKind, 'decisions');
      expect(record?.metadata['probe_type'], 'decision_availability_probe');
      expect(record?.metadata['protocol'], 'jev');
    }
    expect(paths, List.filled(3, '/v1/systemone'));
    expect(cancellation.signal.listeners, 1);
    cancellation.cancel();
  });

  test('代理巡检成功后复用取消监听', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final subscription = server.listen((request) async {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    });
    addTearDown(subscription.cancel);
    final endpoint = AiExposureProxyEndpoint(url: 'http://127.0.0.1:${server.port}');
    final cancellation = ObservedProxyCancellation();
    for (var i = 0; i < 3; i++) {
      final sample = await const AiExposureProxyProbe().inspect(endpoint, cancellation: cancellation);
      expect(sample.reachable, isTrue, reason: sample.error);
    }
    expect(cancellation.signal.listeners, 1);
    cancellation.cancel();
  });

  test('代理巡检取消后销毁迟到的真实连接', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final accepted = server.first;
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    final peer = await accepted;
    addTearDown(socket.destroy);
    addTearDown(peer.destroy);
    final disconnected = peer.drain<void>();
    final connection = Completer<Socket>();
    final started = Completer<void>();
    final cancellation = ObservedProxyCancellation();
    final pending = IOOverrides.runZoned(
      () => const AiExposureProxyProbe().inspect(
        AiExposureProxyEndpoint(url: 'http://127.0.0.1:${server.port}'),
        cancellation: cancellation,
      ),
      socketConnect: (host, port, {sourceAddress, sourcePort = 0, Duration? timeout}) {
        started.complete();
        return connection.future;
      },
    );
    final cancelled = expectLater(pending, throwsA(isA<AiExposureProxyProbeCancelledException>()));
    await started.future.timeout(timeout);
    cancellation.cancel();
    await cancelled.timeout(timeout);
    connection.complete(socket);
    await disconnected.timeout(timeout);
    expect(cancellation.signal.listeners, 1);
  });

  for (final dispose in [false, true]) {
    test('真实 HTTP 并发健康检测${dispose ? '释放控制器' : '取消'}后不继续扫描', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      final entered = Completer<void>();
      final subscription = server.listen((request) {
        paths.add(request.uri.path);
        if (paths.length == 3) entered.complete();
      });
      addTearDown(subscription.cancel);
      final controller = AiModelHealthController();
      addTearDown(controller.dispose);
      final cancel = AiModelHealthCancellation();
      final config = model(baseUrl: 'http://127.0.0.1:${server.port}/step_plan/v1');
      final pending = Future.wait(List.generate(3, (_) => controller.checkModel(config, cancellation: dispose ? null : cancel)));
      await entered.future.timeout(timeout, onTimeout: () => fail('本地服务器未收到三个请求：$paths，记录：${controller.records.map((record) => record.errorMessage)}'));
      if (dispose) {
        controller.dispose();
      } else {
        cancel.cancel();
      }
      expect(await pending.timeout(timeout), everyElement(isNull));
      await pumpEventQueue();
      expect(paths.length, 3);
      expect(controller.records, isEmpty);
    });
  }
}
''';

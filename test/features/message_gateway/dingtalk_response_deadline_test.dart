import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';
import 'package:openhand/features/message_gateway/service/dingtalk_response_deadline.dart';
import 'package:openhand/shared/net/abortable_http_request.dart';

void main() {
  test('旧配置默认五分钟，保存与规范化保留自定义时限', () {
    expect(
      DingTalkGatewaySettings.fromJson({}).responseTimeout,
      const Duration(minutes: 5),
    );
    final settings = const DingTalkGatewaySettings(
      responseTimeoutMinutes: 12,
    ).normalized();
    expect(
      DingTalkGatewaySettings.fromJson(settings.toJson()).responseTimeout,
      const Duration(minutes: 12),
    );
    for (final value in [null, '', '非法', 0, -1, 1.5]) {
      expect(DingTalkGatewaySettings.normalizeResponseTimeoutMinutes(value), 5);
    }
    expect(
      DingTalkGatewaySettings.normalizeResponseTimeoutMinutes(999),
      DingTalkGatewaySettings.maxResponseTimeoutMinutes,
    );
  });

  test('整轮多阶段共用时限，超时仅取消一次且不启动下一步', () async {
    var cancellations = 0;
    var lateOperationStarted = false;
    final deadline = DingTalkResponseDeadline(
      const Duration(milliseconds: 400),
      onTimeout: () => cancellations++,
    );
    addTearDown(deadline.dispose);
    await deadline.wait(
      () => Future<void>.delayed(const Duration(milliseconds: 240)),
    );
    await expectLater(
      deadline.wait(
        () => Future<void>.delayed(const Duration(milliseconds: 240)),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(deadline.timedOut, isTrue);
    await expectLater(
      deadline.wait(() async {
        lateOperationStarted = true;
      }),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancellations, 1);
    expect(lateOperationStarted, isFalse);
  });

  test('正常完成与普通失败均不触发超时取消', () async {
    var cancellations = 0;
    final deadline = DingTalkResponseDeadline(
      const Duration(milliseconds: 80),
      onTimeout: () => cancellations++,
    );
    expect(await deadline.wait(() async => 42), 42);
    await expectLater(
      deadline.wait<int>(() async => throw StateError('请求失败')),
      throwsStateError,
    );
    deadline.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(cancellations, 0);
  });

  test('超时后的迟到错误被收敛，不影响后续独立响应', () async {
    final pending = Completer<int>();
    final deadline = DingTalkResponseDeadline(
      const Duration(milliseconds: 20),
      onTimeout: () {},
    );
    await expectLater(
      deadline.wait(() => pending.future),
      throwsA(isA<TimeoutException>()),
    );
    deadline.dispose();
    pending.completeError(StateError('旧请求迟到失败'));
    final next = DingTalkResponseDeadline(
      const Duration(seconds: 1),
      onTimeout: () => fail('新响应不应超时'),
    );
    expect(await next.wait(() async => 1), 1);
    next.dispose();
  });

  for (final streamStarted in [false, true]) {
    test(streamStarted ? '持续心跳不能延长总时限，超时中止响应流' : '无响应头时超时中止底层连接', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = http.Client();
      Timer? heartbeat;
      addTearDown(() async {
        heartbeat?.cancel();
        client.close();
        await server.close(force: true);
      });
      final received = Completer<void>();
      server.listen((request) {
        received.complete();
        if (streamStarted) {
          request.response.bufferOutput = false;
          request.response.headers.contentType = ContentType.text;
          heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
            request.response.write('心跳\n');
          });
          unawaited(
            request.response.done.then<void>(
              (_) => heartbeat?.cancel(),
              onError: (Object _) => heartbeat?.cancel(),
            ),
          );
        }
      });
      final cancel = Completer<void>();
      final deadline = DingTalkResponseDeadline(
        const Duration(milliseconds: 200),
        onTimeout: cancel.complete,
      );
      addTearDown(deadline.dispose);
      final request = () async {
        final response = await sendAbortableHttpRequest(
          client: client,
          request: http.Request(
            'GET',
            Uri.parse('http://127.0.0.1:${server.port}/'),
          ),
          connectionTimeout: const Duration(seconds: 5),
          cancelSignal: cancel.future,
        );
        await response.stream.drain<void>();
      }();
      final requestError = request.then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      final result = deadline.wait(() => request);
      await received.future;
      await expectLater(result, throwsA(isA<TimeoutException>()));
      expect(cancel.isCompleted, isTrue);
      expect(
        await requestError.timeout(const Duration(seconds: 2)),
        isA<http.RequestAbortedException>(),
      );
    });
  }
}

import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'runtime_lifecycle',
  source: _checks,
);

const _checks = '''
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/app_runtime_cleanup_registry.dart';
import 'package:openhand/features/web_reverse/web_reverse_cdp_client.dart';

final class _Sink implements StreamSink<dynamic> {
  final ended = Completer<void>();
  Object? sendError;
  @override
  void add(dynamic data) { if (sendError != null) throw sendError!; }
  @override
  Future<void> close() => ended.future;
  @override
  Future<void> get done => ended.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('关闭立即终止待响应命令，不等待传输清理', () async {
    final sink = _Sink();
    final events = StreamController<dynamic>();
    var connections = 0;
    final client = WebReverseCdpClient(
      endpoint: 'ws://localhost:9222',
      connector: (_) {
        connections++;
        return WebReverseCdpTransport(ready: Future.value(), stream: events.stream, sink: sink);
      },
    );
    final connecting = client.connect();
    expect(identical(connecting, client.connect()), isTrue);
    await connecting;
    expect(connections, 1);
    final pending = client.send('Page.enable');
    final rejected = expectLater(pending.timeout(const Duration(milliseconds: 100)), throwsStateError);
    final closing = client.close();
    expect(identical(closing, client.close()), isTrue);
    try {
      await rejected;
    } finally {
      sink.ended.complete();
      await closing;
      await events.close();
    }
  });

  test('同步发送失败只交给调用方，不产生孤立 Future 错误', () async {
    final sink = _Sink()..sendError = StateError('传输已关闭');
    final events = StreamController<dynamic>();
    final client = WebReverseCdpClient(
      endpoint: 'ws://localhost:9222',
      connector: (_) => WebReverseCdpTransport(ready: Future.value(), stream: events.stream, sink: sink),
    );
    await client.connect();
    await expectLater(client.send('Page.enable'), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    sink.ended.complete();
    await client.close();
    await events.close();
  });

  test('连接失败后允许重试，关闭后拒绝再次连接', () async {
    final sink = _Sink();
    final events = StreamController<dynamic>();
    var attempts = 0;
    final client = WebReverseCdpClient(
      endpoint: 'ws://localhost:9222',
      connector: (_) {
        if (++attempts == 1) throw StateError('连接失败');
        return WebReverseCdpTransport(ready: Future.value(), stream: events.stream, sink: sink);
      },
    );
    await expectLater(client.connect(), throwsStateError);
    await client.connect();
    expect(attempts, 2);
    expect(client.canSendCommands, isTrue);
    sink.ended.complete();
    await client.close();
    await expectLater(client.connect(), throwsStateError);
    await events.close();
  });

  test('资源注册表逆序清理且同步重入共享完成信号', () async {
    final registry = AppRuntimeCleanupRegistry();
    final order = <int>[];
    Future<void>? nested;
    registry.register('先注册', () => order.add(1));
    registry.register('后注册', () {
      nested = registry.dispose();
      expect(() => registry.register('迟到注册', () {}), throwsStateError);
      order.add(2);
    });
    final closing = registry.dispose();
    await closing;
    expect(identical(closing, nested), isTrue);
    expect(identical(closing, registry.dispose()), isTrue);
    expect(order, [2, 1]);
  });
}
''';

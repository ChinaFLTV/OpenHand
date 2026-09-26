import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final source = await readFlutterCheckSource(
    File(
      '${root.path}/lib/features/web_reverse/web_reverse_session_controller.dart',
    ),
    root: root,
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'trace_lifecycle',
    source:
        "import 'package:flutter_test/flutter_test.dart';\n$source\n$_checks",
  );
}

const _checks = '''
class _TraceCdp implements WebReverseCdpClient {
  final eventsController = StreamController<CdpEvent>.broadcast();
  int starts = 0;
  int stops = 0;
  bool failStart = false;

  @override
  bool get isClosed => false;
  @override
  Stream<CdpEvent> get events => eventsController.stream;
  @override
  Future<Map<String, Object?>> send(String method, {
    Map<String, Object?>? params, String? sessionId,
    Duration timeout = const Duration(seconds: 8), int maxResponseCharacters = 1,
  }) async {
    if (method == 'Tracing.start') {
      starts++;
      if (failStart) throw StateError('跟踪启动失败');
    } else if (method == 'Tracing.end') {
      stops++;
      eventsController.add(const CdpEvent(method: 'Tracing.tracingComplete', params: {}));
    }
    return {};
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('旧跟踪取消信号不影响下一轮，提前停止后不遗留定时器', (tester) async {
    final cdp = _TraceCdp();
    final controller = WebReverseSessionController(
      config: WebReverseSessionConfig.fromJson({
        'target_url': 'https://example.test', 'cdp_port': 9222, 'browser_kind': 'chrome',
      })!,
      executablePath: '', artifactsRootDir: '',
    ).._browserCdp = cdp;
    final firstStop = Completer<void>();
    final lateStop = Completer<void>();
    final first = controller.recordTrace(duration: const Duration(minutes: 1), earlyStop: firstStop.future);
    expect(controller.recordTrace(duration: const Duration(minutes: 1), earlyStop: lateStop.future), same(first));
    await tester.pump();
    firstStop.complete();
    await tester.pump();
    expect(await first, isNotNull);
    expect(cdp.stops, 1);
    expect(cdp.eventsController.hasListener, isFalse);

    final secondStop = Completer<void>();
    final second = controller.recordTrace(duration: const Duration(minutes: 1), earlyStop: secondStop.future);
    await tester.pump();
    lateStop.completeError(StateError('上一轮迟到取消'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(cdp.stops, 1, reason: '上一轮附加的取消信号不能停止新跟踪');
    secondStop.complete();
    await tester.pump();
    expect(await second, isNotNull);
    expect(cdp.starts, 2);
    expect(cdp.stops, 2);
    expect(cdp.eventsController.hasListener, isFalse);

    cdp.failStart = true;
    final failed = controller.recordTrace(duration: const Duration(minutes: 1));
    await tester.pump();
    expect(await failed, isNull);
    expect(cdp.eventsController.hasListener, isFalse);
    controller._browserCdp = null;
    await controller.shutdown();
    controller.dispose();
    await cdp.eventsController.close();
  });
}
''';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_cdp_client.dart';

const _endpoint = 'ws://127.0.0.1:9222/devtools/browser/test';

void main() {
  group('WebReverseCdpClient lifecycle', () {
    test('validates lifecycle configuration', () {
      expect(
        () => WebReverseCdpClient(endpoint: 'https://example.test'),
        throwsArgumentError,
      );
      expect(
        () =>
            WebReverseCdpClient(endpoint: _endpoint, reconnectMaxAttempts: -1),
        throwsArgumentError,
      );
      expect(
        () => WebReverseCdpClient(
          endpoint: _endpoint,
          handshakeTimeout: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => WebReverseCdpClient(
          endpoint: _endpoint,
          reconnectInitialDelay: const Duration(milliseconds: 2),
          reconnectMaxDelay: const Duration(milliseconds: 1),
        ),
        throwsArgumentError,
      );
    });

    test('shares one handshake across concurrent connect calls', () async {
      final transport = _FakeCdpTransport();
      var connectorCalls = 0;
      final client = _createClient((_) {
        connectorCalls += 1;
        return transport.value;
      });
      addTearDown(() async {
        await client.close();
        await transport.dispose();
      });

      final first = client.connect();
      final second = client.connect();
      final third = client.connect();

      expect(identical(first, second), isTrue);
      expect(identical(first, third), isTrue);
      await _waitForCondition(() => connectorCalls == 1);

      transport.completeReady();
      await Future.wait<void>([first, second, third]);
      expect(connectorCalls, 1);
    });

    test('times out a handshake, closes it, and allows retry', () async {
      final stalled = _FakeCdpTransport();
      final replacement = _FakeCdpTransport()..completeReady();
      final transports = <_FakeCdpTransport>[stalled, replacement];
      final client = _createClient(
        (_) => transports.removeAt(0).value,
        handshakeTimeout: const Duration(milliseconds: 15),
      );
      addTearDown(() async {
        await client.close();
        await stalled.dispose();
        await replacement.dispose();
      });

      await expectLater(client.connect(), throwsA(isA<TimeoutException>()));
      expect(stalled.sink.closeCount, 1);

      await client.connect();
      expect(replacement.sink.closeCount, 0);
    });

    test('close cancels a connecting handshake without awaiting it', () async {
      final transport = _FakeCdpTransport();
      final client = _createClient((_) {
        transport.wasRequested = true;
        return transport.value;
      }, handshakeTimeout: const Duration(seconds: 1));
      addTearDown(transport.dispose);

      final connect = client.connect();
      await _waitForCondition(() => transport.wasRequested);
      final connectCancelled = expectLater(
        connect.timeout(const Duration(milliseconds: 100)),
        throwsA(isA<StateError>()),
      );
      final stopwatch = Stopwatch()..start();
      await client.close();
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 200)));
      expect(transport.sink.closeCount, 1);
      await connectCancelled;
      expect(client.isClosed, isTrue);
    });

    test(
      'close cancels a reconnect handshake and ignores late ready',
      () async {
        final active = _FakeCdpTransport()..completeReady();
        final reconnecting = _FakeCdpTransport();
        final transports = <_FakeCdpTransport>[active, reconnecting];
        final events = <CdpEvent>[];
        final client = _createClient((_) {
          final next = transports.removeAt(0);
          next.wasRequested = true;
          return next.value;
        }, reconnectMaxAttempts: 1);
        final eventSubscription = client.events.listen(events.add);
        addTearDown(() async {
          await eventSubscription.cancel();
          await client.close();
          await active.dispose();
          await reconnecting.dispose();
        });

        await client.connect();
        await active.finishInbound();
        await _waitForCondition(() => reconnecting.wasRequested);

        await client.close();
        expect(reconnecting.sink.closeCount, 1);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(reconnecting.sink.closeCount, 1);
        expect(
          events.where((event) => event.method == '__cdp_reconnected__'),
          isEmpty,
        );
      },
    );

    test('ignores an old sink error after reconnect succeeds', () async {
      final oldTransport = _FakeCdpTransport(completeSinkDoneOnClose: false)
        ..completeReady();
      final currentTransport = _FakeCdpTransport()..completeReady();
      final transports = <_FakeCdpTransport>[oldTransport, currentTransport];
      final client = _createClient(
        (_) => transports.removeAt(0).value,
        reconnectMaxAttempts: 1,
      );
      addTearDown(() async {
        await client.close();
        await oldTransport.dispose();
        await currentTransport.dispose();
      });

      await client.connect();
      final reconnected = client.events.firstWhere(
        (event) => event.method == '__cdp_reconnected__',
      );
      await oldTransport.finishInbound();
      await reconnected;

      oldTransport.sink.failDone(StateError('late old sink error'));
      await Future<void>.delayed(Duration.zero);

      final response = client.send('Runtime.evaluate');
      final payload = jsonDecode(currentTransport.sink.values.single as String);
      currentTransport.emit(
        jsonEncode(<String, Object?>{
          'id': (payload as Map)['id'],
          'result': <String, Object?>{'ok': true},
        }),
      );
      expect(await response, <String, Object?>{'ok': true});
    });

    test('bounds failed reconnects and publishes one dead event', () async {
      final active = _FakeCdpTransport()..completeReady();
      final firstFailure = _FakeCdpTransport();
      final secondFailure = _FakeCdpTransport();
      final transports = <_FakeCdpTransport>[
        active,
        firstFailure,
        secondFailure,
      ];
      final events = <CdpEvent>[];
      final client = _createClient(
        (_) => transports.removeAt(0).value,
        handshakeTimeout: const Duration(milliseconds: 10),
      );
      final eventSubscription = client.events.listen(events.add);
      addTearDown(() async {
        await eventSubscription.cancel();
        await client.close();
        await active.dispose();
        await firstFailure.dispose();
        await secondFailure.dispose();
      });

      await client.connect();
      await active.finishInbound();
      await _waitForCondition(
        () => events.any((event) => event.method == '__cdp_dead__'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(firstFailure.sink.closeCount, 1);
      expect(secondFailure.sink.closeCount, 1);
      expect(
        events.where((event) => event.method == '__cdp_dead__'),
        hasLength(1),
      );
      expect(client.isClosed, isTrue);
    });
  });
}

WebReverseCdpClient _createClient(
  WebReverseCdpTransport Function(Uri endpoint) connector, {
  int reconnectMaxAttempts = 2,
  Duration handshakeTimeout = const Duration(milliseconds: 50),
}) {
  return WebReverseCdpClient(
    endpoint: _endpoint,
    reconnectMaxAttempts: reconnectMaxAttempts,
    handshakeTimeout: handshakeTimeout,
    connectionCleanupTimeout: const Duration(milliseconds: 10),
    reconnectInitialDelay: Duration.zero,
    reconnectMaxDelay: Duration.zero,
    connector: (endpoint) {
      final transport = connector(endpoint);
      return transport;
    },
  );
}

Future<void> _waitForCondition(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

class _FakeCdpTransport {
  _FakeCdpTransport({bool completeSinkDoneOnClose = true})
    : sink = _FakeCdpSink(completeDoneOnClose: completeSinkDoneOnClose) {
    value = WebReverseCdpTransport(
      ready: _ready.future,
      stream: _inbound.stream,
      sink: sink,
    );
  }

  final Completer<void> _ready = Completer<void>();
  final StreamController<dynamic> _inbound =
      StreamController<dynamic>.broadcast(sync: true);
  final _FakeCdpSink sink;
  late final WebReverseCdpTransport value;
  bool wasRequested = false;

  void completeReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  void emit(dynamic value) => _inbound.add(value);

  Future<void> finishInbound() => _inbound.close();

  Future<void> dispose() async {
    sink.completeDone();
    if (!_inbound.isClosed) await _inbound.close();
  }
}

class _FakeCdpSink implements StreamSink<dynamic> {
  _FakeCdpSink({required this.completeDoneOnClose});

  final bool completeDoneOnClose;
  final List<dynamic> values = <dynamic>[];
  final Completer<void> _done = Completer<void>();
  int closeCount = 0;
  bool _closed = false;

  @override
  void add(dynamic data) {
    if (_closed) throw StateError('sink is closed');
    values.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    failDone(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final value in stream) {
      add(value);
    }
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    _closed = true;
    if (completeDoneOnClose) completeDone();
  }

  @override
  Future<void> get done => _done.future;

  void completeDone() {
    if (!_done.isCompleted) _done.complete();
  }

  void failDone(Object error, [StackTrace? stack]) {
    if (!_done.isCompleted) {
      _done.completeError(error, stack ?? StackTrace.current);
    }
  }
}

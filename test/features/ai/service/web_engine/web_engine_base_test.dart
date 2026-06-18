import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/web_engine/web_engine_base.dart';

void main() {
  group('WebEngineBase cancellation', () {
    test('does not start fetch when cancel signal already completed', () async {
      final cancel = Completer<void>()..complete();
      final engine = _TestWebEngine();

      final result = await engine.run(
        _TestWebEngineRequest(cancelSignal: cancel.future),
      );

      expect(result.error, 'cancelled');
      expect(result.attempts, 0);
      expect(engine.fetchCount, 0);
    });

    test('interrupts an in-flight fetch', () async {
      final cancel = Completer<void>();
      final fetch = Completer<List<String>>();
      final engine = _TestWebEngine(
        fetchHandler: (_) => fetch.future,
        fetchTimeout: const Duration(seconds: 30),
      );

      final pending = engine.run(
        _TestWebEngineRequest(cancelSignal: cancel.future),
      );
      await Future<void>.delayed(Duration.zero);
      expect(engine.fetchCount, 1);

      cancel.complete();
      final result = await pending.timeout(const Duration(seconds: 1));

      expect(result.error, 'cancelled');
      expect(result.attempts, 0);
    });

    test('interrupts retry backoff', () async {
      final cancel = Completer<void>();
      final engine = _TestWebEngine(
        maxRetries: 8,
        fetchHandler: (_) async => throw StateError('boom'),
      );

      final pending = engine.run(
        _TestWebEngineRequest(cancelSignal: cancel.future),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(engine.fetchCount, 1);

      cancel.complete();
      final result = await pending.timeout(const Duration(seconds: 2));

      expect(result.error, 'cancelled');
      expect(result.attempts, 1);
      expect(engine.fetchCount, 1);
    });
  });
}

class _TestWebEngineRequest extends WebEngineRequest {
  const _TestWebEngineRequest({super.cancelSignal});
}

class _TestWebEngineResult {
  const _TestWebEngineResult({
    required this.items,
    required this.error,
    required this.attempts,
    required this.elapsedMs,
  });

  final List<String> items;
  final String? error;
  final int attempts;
  final int elapsedMs;
}

class _TestWebEngine
    extends
        WebEngineBase<
          String,
          String,
          _TestWebEngineRequest,
          _TestWebEngineResult
        > {
  _TestWebEngine({
    this.maxRetries = 0,
    this.fetchTimeout = const Duration(seconds: 5),
    Future<List<String>> Function(_TestWebEngineRequest request)? fetchHandler,
  }) : _fetchHandler = fetchHandler;

  final Future<List<String>> Function(_TestWebEngineRequest request)?
  _fetchHandler;

  int fetchCount = 0;

  @override
  String get kind => 'test';

  @override
  bool get isReady => true;

  @override
  final int maxRetries;

  @override
  final Duration fetchTimeout;

  @override
  Future<List<String>> fetch(_TestWebEngineRequest request) {
    fetchCount += 1;
    return _fetchHandler?.call(request) ?? Future.value(const <String>['ok']);
  }

  @override
  _TestWebEngineResult buildResult({
    required List<String> items,
    String? error,
    required int attempts,
    required int elapsedMs,
  }) {
    return _TestWebEngineResult(
      items: items,
      error: error,
      attempts: attempts,
      elapsedMs: elapsedMs,
    );
  }
}

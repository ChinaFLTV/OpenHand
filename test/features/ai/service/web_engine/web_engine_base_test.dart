import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/web_engine/web_engine_base.dart';

void main() {
  group('WebEngineBase', () {
    test('treats cancel signal errors as cancellation during fetch', () async {
      final cancel = Completer<void>();
      final engine = _FakeWebEngine(
        onFetch: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return <String>['late'];
        },
      );

      final run = engine.run(
        _FakeWebEngineRequest(cancelSignal: cancel.future),
      );
      await Future<void>.delayed(Duration.zero);
      cancel.completeError(StateError('cancelled'));

      final result = await run;
      expect(result.error, 'cancelled');
      expect(result.items, isEmpty);
      expect(result.attempts, 0);
    });

    test(
      'treats cancel signal errors as cancellation during backoff',
      () async {
        final cancel = Completer<void>();
        final engine = _FakeWebEngine(
          maxRetries: 2,
          onFetch: (_) async => throw StateError('temporary'),
        );

        final run = engine.run(
          _FakeWebEngineRequest(cancelSignal: cancel.future),
        );
        await Future<void>.delayed(Duration.zero);
        cancel.completeError(StateError('cancelled'));

        final result = await run;
        expect(result.error, 'cancelled');
        expect(result.items, isEmpty);
        expect(result.attempts, 1);
      },
    );
  });
}

class _FakeWebEngineRequest extends WebEngineRequest {
  const _FakeWebEngineRequest({super.cancelSignal});
}

class _FakeWebEngineResult {
  const _FakeWebEngineResult({
    required this.items,
    required this.error,
    required this.attempts,
  });

  final List<String> items;
  final String? error;
  final int attempts;
}

class _FakeWebEngine
    extends
        WebEngineBase<
          String,
          String,
          _FakeWebEngineRequest,
          _FakeWebEngineResult
        > {
  _FakeWebEngine({required this.onFetch, this.maxRetries = 0});

  final Future<List<String>> Function(_FakeWebEngineRequest request) onFetch;

  @override
  final int maxRetries;

  @override
  String get kind => 'fake';

  @override
  bool get isReady => true;

  @override
  Duration get fetchTimeout => const Duration(seconds: 1);

  @override
  Future<List<String>> fetch(_FakeWebEngineRequest request) => onFetch(request);

  @override
  _FakeWebEngineResult buildResult({
    required List<String> items,
    String? error,
    required int attempts,
    required int elapsedMs,
  }) {
    return _FakeWebEngineResult(items: items, error: error, attempts: attempts);
  }
}

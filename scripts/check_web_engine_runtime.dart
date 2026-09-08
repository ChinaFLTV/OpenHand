import 'dart:async';
import 'dart:io';

import 'package:openhand/features/ai/service/web_engine/web_engine_base.dart';

Future<void> main() async {
  var failures = 0;
  failures += await _checkTimedOutAttemptStopsBeforeRetry();
  failures += await _checkExternalCancellationStopsRetry();
  if (failures > 0) {
    stderr.writeln('[Web 引擎检查] 失败 $failures 项。');
    exit(1);
  }
  stdout.writeln('[Web 引擎检查] 通过。');
}

Future<int> _checkTimedOutAttemptStopsBeforeRetry() async {
  final engine = _ProbeWebEngine();
  final result = await engine.run(const _ProbeWebEngineRequest());
  if (result.error != null ||
      result.items.length != 1 ||
      result.items.single != 7 ||
      result.attempts != 2 ||
      engine.cancelledAttempts != 1 ||
      engine.maxActiveAttempts != 1) {
    stderr.writeln('超时请求未在重试前完成取消收口。');
    return 1;
  }
  return 0;
}

Future<int> _checkExternalCancellationStopsRetry() async {
  final cancellation = Completer<void>();
  final engine = _ProbeWebEngine(alwaysWaitForCancellation: true);
  final running = engine.run(
    _ProbeWebEngineRequest(cancelSignal: cancellation.future),
  );
  await Future<void>.delayed(const Duration(milliseconds: 10));
  cancellation.complete();
  final result = await running;
  if (result.error != 'cancelled' ||
      result.attempts != 0 ||
      engine.startedAttempts != 1 ||
      engine.cancelledAttempts != 1) {
    stderr.writeln('外部取消后仍继续执行或重试。');
    return 1;
  }
  return 0;
}

final class _ProbeWebEngineRequest
    extends WebEngineRequest<_ProbeWebEngineRequest> {
  const _ProbeWebEngineRequest({super.cancelSignal});

  @override
  _ProbeWebEngineRequest withCancelSignal(Future<void>? cancelSignal) {
    return _ProbeWebEngineRequest(cancelSignal: cancelSignal);
  }
}

final class _ProbeWebEngineResult {
  const _ProbeWebEngineResult({
    required this.items,
    required this.attempts,
    this.error,
  });

  final List<int> items;
  final int attempts;
  final String? error;
}

final class _ProbeWebEngine
    extends
        WebEngineBase<
          String,
          int,
          _ProbeWebEngineRequest,
          _ProbeWebEngineResult
        > {
  _ProbeWebEngine({this.alwaysWaitForCancellation = false});

  final bool alwaysWaitForCancellation;
  int startedAttempts = 0;
  int cancelledAttempts = 0;
  int _activeAttempts = 0;
  int maxActiveAttempts = 0;

  @override
  String get kind => '检查';

  @override
  bool get isReady => true;

  @override
  int get maxRetries => 1;

  @override
  Duration get fetchTimeout => const Duration(milliseconds: 20);

  @override
  Future<List<int>> fetch(_ProbeWebEngineRequest request) async {
    startedAttempts += 1;
    _activeAttempts += 1;
    if (_activeAttempts > maxActiveAttempts) {
      maxActiveAttempts = _activeAttempts;
    }
    try {
      if (!alwaysWaitForCancellation && startedAttempts > 1) {
        return const <int>[7];
      }
      await request.cancelSignal;
      cancelledAttempts += 1;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      throw StateError('请求已取消。');
    } finally {
      _activeAttempts -= 1;
    }
  }

  @override
  _ProbeWebEngineResult buildResult({
    required List<int> items,
    String? error,
    required int attempts,
    required int elapsedMs,
  }) {
    return _ProbeWebEngineResult(
      items: items,
      attempts: attempts,
      error: error,
    );
  }
}

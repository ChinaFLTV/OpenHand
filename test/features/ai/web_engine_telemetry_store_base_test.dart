import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'web engine telemetry base normalizes persisted numeric fields',
    () async {
      final dir = await Directory.systemTemp.createTemp('openhand_telemetry_');
      final store = _TestTelemetryStore(dir.path);
      final now = DateTime.now().millisecondsSinceEpoch;
      await File(p.join(dir.path, 'engines.json')).writeAsString(
        '{"alpha":{"cooldown_until_ms":"${now + 5000}",'
        '"total_calls":"2","success_calls":1e999,'
        '"total_duration_ms":"-8","total_hits":"5"}}',
      );
      await File(p.join(dir.path, 'engine_history.json')).writeAsString(
        '{"alpha":[{"ts":"${now - 1000}"},{"ts":1e999},{"ts":"-1"}]}',
      );

      try {
        expect(
          await store.cooldownRemaining(_TestEngineKind.alpha),
          greaterThan(0),
        );
        expect(await store.callsInLastMinute(_TestEngineKind.alpha), 1);

        await store.recordCallRaw(
          callJson: <String, Object?>{'timestamp_ms': now},
          timestampMs: now,
          perEngine: <WebEngineCallEvent>[
            WebEngineCallEvent(
              kindName: _TestEngineKind.alpha.name,
              success: true,
              elapsedMs: -20,
              aggregateBumps: const <String, num>{
                'total_hits': double.infinity,
              },
            ),
          ],
        );

        final stats = await store.rawEngineStats();
        final alpha = stats[_TestEngineKind.alpha.name]!;
        expect(alpha['total_calls'], 3);
        expect(alpha['success_calls'], 1);
        expect(alpha['total_duration_ms'], 0);
        expect(alpha['total_hits'], 5);
        expect(alpha['cooldown_until_ms'], isNull);

        final history = await store.rawEngineHistory();
        expect(history[_TestEngineKind.alpha.name]!.last['dur'], 0);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}

enum _TestEngineKind { alpha }

class _TestTelemetryStore extends WebEngineTelemetryStoreBase<_TestEngineKind> {
  _TestTelemetryStore(this.directoryPath);

  final String directoryPath;

  @override
  String get subdir => 'test';

  @override
  String get logTag => 'test_telemetry';

  @override
  List<_TestEngineKind> get kindValues => _TestEngineKind.values;

  @override
  _TestEngineKind? parseKind(String name) {
    return _TestEngineKind.values
        .where((kind) => kind.name == name)
        .firstOrNull;
  }

  @override
  String defaultDirectoryPath() => directoryPath;
}

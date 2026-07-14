import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/web_engine/web_engine_cache_store_base.dart';
import 'package:openhand/features/ai/service/web_engine/web_engine_persistence_io.dart';
import 'package:openhand/features/ai/service/web_engine/web_engine_telemetry_store_base.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-web-engine-persistence-',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('cache lookup and store accept only bounded SHA-256 entries', () async {
    final cache = _TestCacheStore('${temporaryDirectory.path}/cache');
    const settings = _CacheSettings(enabled: true, maxBytes: 1024);
    final key = List<String>.filled(64, 'a').join();

    await cache.baseStore(
      key: key,
      settings: settings,
      payload: 'payload',
      extraEntryFields: const <String, Object?>{},
    );
    final loaded = await cache.baseLookup(key: key, settings: settings);
    await cache.chain;

    expect(loaded?.payload, 'payload');
    expect(
      await cache.baseLookup(key: '../escape', settings: settings),
      isNull,
    );
    await cache.baseStore(
      key: List<String>.filled(64, 'b').join(),
      settings: const _CacheSettings(enabled: true, maxBytes: 4),
      payload: '12345',
      extraEntryFields: const <String, Object?>{},
    );
    expect(
      await Directory(cache.path).list().where((entity) {
        return entity.path.endsWith(
          '${List<String>.filled(64, 'b').join()}.txt',
        );
      }).isEmpty,
      isTrue,
    );
  });

  test('prewarm never deletes a path referenced outside the cache', () async {
    final cache = _TestCacheStore('${temporaryDirectory.path}/cache');
    final directory = Directory(cache.path);
    await directory.create(recursive: true);
    final sentinel = File('${temporaryDirectory.path}/sentinel.txt');
    await sentinel.writeAsString('keep');
    final key = List<String>.filled(64, 'c').join();
    await File('${directory.path}/index.json').writeAsString(
      jsonEncode(<String, Object?>{
        'entries': <String, Object?>{
          key: <String, Object?>{
            'payload_path': '../sentinel.txt',
            'expires_at': 0,
          },
        },
      }),
    );

    final report = await cache.prewarm();

    expect(report.removedOrphanEntries, 1);
    expect(await sentinel.readAsString(), 'keep');
  });

  test('telemetry keeps bounded call and engine history windows', () async {
    final telemetry = _TestTelemetryStore(
      '${temporaryDirectory.path}/telemetry',
    );
    for (var index = 0; index < 3; index++) {
      await telemetry.recordCallRaw(
        callJson: <String, Object?>{'index': index},
        timestampMs: index + 1,
        perEngine: <WebEngineCallEvent>[
          WebEngineCallEvent(
            kindName: _TestKind.engine.name,
            success: true,
            elapsedMs: 10,
          ),
        ],
        maxRecentCalls: 2,
        maxHistorySamples: 2,
      );
    }

    expect(await telemetry.rawCalls(), hasLength(2));
    expect(
      (await telemetry.rawEngineHistory())[_TestKind.engine.name],
      hasLength(2),
    );
    expect(
      (await telemetry.rawEngineStats())[_TestKind.engine.name]?['total_calls'],
      3,
    );
  });

  test(
    'cache and telemetry clear nested contents without following links',
    () async {
      final cache = _TestCacheStore('${temporaryDirectory.path}/cache');
      final telemetry = _TestTelemetryStore(
        '${temporaryDirectory.path}/telemetry',
      );
      final outside = File('${temporaryDirectory.path}/outside.txt');
      await outside.writeAsString('keep');
      await Directory('${cache.path}/nested').create(recursive: true);
      await File('${cache.path}/nested/payload.txt').writeAsString('payload');
      if (!Platform.isWindows) {
        await Link('${cache.path}/outside-link').create(outside.path);
      }
      await Directory('${telemetry.path}/nested').create(recursive: true);
      await File('${telemetry.path}/nested/history.json').writeAsString('{}');

      await cache.clearAll();
      await telemetry.clearAll();

      expect(await Directory(cache.path).list().isEmpty, isTrue);
      expect(await Directory(telemetry.path).list().isEmpty, isTrue);
      expect(await outside.readAsString(), 'keep');
    },
  );

  test('cache index normalization rejects unsafe keys', () {
    final validKey = List<String>.filled(64, 'd').join();

    final entries = webEngineCacheEntriesFromValue(<String, Object?>{
      validKey: const <String, Object?>{'value': 1},
      '../escape': const <String, Object?>{'value': 2},
    });

    expect(entries.keys, <String>[validKey]);
  });
}

class _CacheSettings {
  const _CacheSettings({required this.enabled, required this.maxBytes});

  final bool enabled;
  final int maxBytes;
}

class _TestCacheStore extends WebEngineCacheStoreBase<_CacheSettings> {
  _TestCacheStore(this.path);

  final String path;

  @override
  String get subdir => 'test';

  @override
  String get logTag => 'test_cache';

  @override
  String get payloadPathField => 'payload_path';

  @override
  String get payloadBytesField => 'payload_bytes';

  @override
  String get payloadCharsField => 'payload_chars';

  @override
  bool isCacheEnabled(_CacheSettings settings) => settings.enabled;

  @override
  int cacheTtlSeconds(_CacheSettings settings) => 60;

  @override
  int cacheMaxBytes(_CacheSettings settings) => settings.maxBytes;

  @override
  String defaultDirectoryPath() => path;
}

enum _TestKind { engine }

class _TestTelemetryStore extends WebEngineTelemetryStoreBase<_TestKind> {
  _TestTelemetryStore(this.path);

  final String path;

  @override
  String get subdir => 'test';

  @override
  String get logTag => 'test_telemetry';

  @override
  List<_TestKind> get kindValues => _TestKind.values;

  @override
  _TestKind? parseKind(String name) {
    return name == _TestKind.engine.name ? _TestKind.engine : null;
  }

  @override
  String defaultDirectoryPath() => path;
}

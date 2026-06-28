import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:path/path.dart' as p;

void main() {
  test('web engine cache base normalizes persisted numeric fields', () async {
    final dir = await Directory.systemTemp.createTemp('openhand_cache_');
    final store = _TestCacheStore(dir.path);
    final now = DateTime.now().millisecondsSinceEpoch;
    final future = now + 60000;
    final expired = now - 1000;
    await File(p.join(dir.path, 'hit.txt')).writeAsString('cached');
    await File(p.join(dir.path, 'expired.txt')).writeAsString('expired');
    await File(p.join(dir.path, 'index.json')).writeAsString(
      '{"entries":{'
      '"hit":{"payload_path":"hit.txt","payload_bytes":"6",'
      '"payload_chars":"6","created_at":"${now - 1000}",'
      '"expires_at":"$future","last_accessed_at":"${now - 1000}",'
      '"score":1e999},'
      '"expired":{"payload_path":"expired.txt","expires_at":"$expired"},'
      '"missing":{"payload_path":"missing.txt","expires_at":"$future"}'
      '}}',
    );

    try {
      final report = await store.prewarm();
      expect(report.removedExpired, 1);
      expect(report.removedOrphanEntries, 1);

      final lookup = await store.baseLookup(
        key: 'hit',
        settings: const _TestCacheSettings(),
      );
      expect(lookup, isNotNull);
      expect(lookup!.payload, 'cached');
      expect(lookup.metadata['score'], 0);
      expect(lookup.expiresAt.millisecondsSinceEpoch, future);
      expect(await File(p.join(dir.path, 'expired.txt')).exists(), isFalse);

      await store.baseStore(
        key: 'stored',
        settings: const _TestCacheSettings(),
        payload: 'stored payload',
        extraEntryFields: <String, Object?>{
          'score': double.infinity,
          'nested': <String, Object?>{'bad': double.nan},
        },
      );

      final root =
          jsonDecode(await File(p.join(dir.path, 'index.json')).readAsString())
              as Map;
      final entries = root['entries'] as Map;
      final stored = entries['stored'] as Map;
      expect(stored['score'], 0);
      expect((stored['nested'] as Map)['bad'], 0);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

class _TestCacheSettings {
  const _TestCacheSettings();

  bool get enabled => true;
  int get ttlSeconds => 60;
  int get maxBytes => 0;
}

class _TestCacheStore extends WebEngineCacheStoreBase<_TestCacheSettings> {
  _TestCacheStore(this.directoryPath);

  final String directoryPath;

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
  bool isCacheEnabled(_TestCacheSettings settings) => settings.enabled;

  @override
  int cacheTtlSeconds(_TestCacheSettings settings) => settings.ttlSeconds;

  @override
  int cacheMaxBytes(_TestCacheSettings settings) => settings.maxBytes;

  @override
  String defaultDirectoryPath() => directoryPath;
}

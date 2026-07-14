import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/media/media_cache_service.dart';

import '../../support/test_directory.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory cacheDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-media-cache-',
    );
    cacheDirectory = Directory('${temporaryDirectory.path}/cache');
  });

  tearDown(() => deleteTestDirectory(temporaryDirectory));

  test(
    'persisted cache is validated asynchronously before hot-path use',
    () async {
      const url = 'https://example.com/generated/image.png';
      final source = File('${temporaryDirectory.path}/source.png');
      await source.writeAsBytes(<int>[1, 2, 3, 4]);
      final writer = MediaCacheService.forTesting(
        cacheDirectoryPath: cacheDirectory.path,
      );

      final imported = await writer.importFile(
        url,
        source.path,
        kind: MediaCacheKind.image,
        mimeType: 'image/png',
      );

      expect(imported, isNotNull);
      expect(
        writer.cachedPathForUrl(url, kind: MediaCacheKind.image),
        imported,
      );

      final reader = MediaCacheService.forTesting(
        cacheDirectoryPath: cacheDirectory.path,
      );
      expect(reader.cachedPathForUrl(url, kind: MediaCacheKind.image), isNull);

      final validated = await reader.ensureCached(
        url,
        kind: MediaCacheKind.image,
      );

      expect(validated, imported);
      expect(
        reader.cachedPathForUrl(url, kind: MediaCacheKind.image),
        imported,
      );
    },
  );

  test('validated path hot cache evicts the least recently used URL', () async {
    final source = File('${temporaryDirectory.path}/source.png');
    await source.writeAsBytes(<int>[1, 2, 3, 4]);
    final service = MediaCacheService.forTesting(
      cacheDirectoryPath: cacheDirectory.path,
      validatedPathCacheMaxEntries: 2,
    );
    const firstUrl = 'https://example.com/generated/first.png';
    const secondUrl = 'https://example.com/generated/second.png';
    const thirdUrl = 'https://example.com/generated/third.png';

    final first = await service.importFile(
      firstUrl,
      source.path,
      kind: MediaCacheKind.image,
    );
    final second = await service.importFile(
      secondUrl,
      source.path,
      kind: MediaCacheKind.image,
    );
    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(
      service.cachedPathForUrl(firstUrl, kind: MediaCacheKind.image),
      first,
    );

    final third = await service.importFile(
      thirdUrl,
      source.path,
      kind: MediaCacheKind.image,
    );

    expect(third, isNotNull);
    expect(
      service.cachedPathForUrl(secondUrl, kind: MediaCacheKind.image),
      isNull,
    );
    expect(
      service.cachedPathForUrl(firstUrl, kind: MediaCacheKind.image),
      first,
    );
    expect(
      service.cachedPathForUrl(thirdUrl, kind: MediaCacheKind.image),
      third,
    );
  });
}

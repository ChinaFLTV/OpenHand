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
}

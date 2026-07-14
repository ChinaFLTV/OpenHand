import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_browser_kind.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_config.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_controller.dart';

import '../../support/test_directory.dart';

void main() {
  test('source map reports retained character cost for bounded caching', () {
    final info = WebReverseSourceMapInfo(
      scriptUrl: 'script.js',
      mapUrl: 'script.js.map',
      sources: const <String>['one.ts', 'two.ts'],
      sourcesContent: const <String?>['const one = 1;', null],
      names: const <String>['one'],
      sourceRoot: '/src/',
      mappings: 'AAAA',
    );

    expect(
      info.estimatedRetainedChars,
      'script.js'.length +
          'script.js.map'.length +
          'one.ts'.length +
          'two.ts'.length +
          'const one = 1;'.length +
          'one'.length +
          '/src/'.length +
          'AAAA'.length,
    );
  });

  test('shutdown is idempotent and rejects browser restart', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'openhand-web-reverse-lifecycle-',
    );
    final controller = WebReverseSessionController(
      config: WebReverseSessionConfig(
        targetUrl: 'https://example.com',
        objective: 'test',
        cdpPort: 9222,
        userDataDir: '${tempDir.path}/profile',
        browserKind: WebReverseBrowserKind.chromium,
      ),
      executablePath: '/missing-browser',
      artifactsRootDir: '${tempDir.path}/artifacts',
    );

    await Future.wait<void>(<Future<void>>[
      controller.shutdown(),
      controller.shutdown(),
    ]);
    controller.dispose();

    await expectLater(controller.restartBrowser(), throwsStateError);
    await expectLater(controller.start(), throwsStateError);
    expect(controller.dispose, returnsNormally);
    await deleteTestDirectory(tempDir);
  });
}

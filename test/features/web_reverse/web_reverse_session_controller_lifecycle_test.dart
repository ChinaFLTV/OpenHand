import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_browser_kind.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_config.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_controller.dart';

void main() {
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
    await tempDir.delete(recursive: true);
  });
}

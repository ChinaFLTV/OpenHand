import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/android_reverse/android_reverse_session_config.dart';
import 'package:openhand/features/android_reverse/android_reverse_session_controller.dart';

void main() {
  test('shutdown is idempotent and rejects late capture starts', () async {
    final controller = AndroidReverseSessionController(
      config: const AndroidReverseSessionConfig(objective: 'test'),
      artifactsRootDir: '/tmp/openhand-android-reverse-lifecycle-test',
    );

    await Future.wait<void>(<Future<void>>[
      controller.shutdown(),
      controller.shutdown(),
    ]);
    final result = await controller.startNetworkCapture();
    controller.dispose();

    expect(controller.state, AndroidReverseSessionState.stopped);
    expect(result.ok, isFalse);
    expect(result.stderr, contains('stopped'));
    expect(controller.dispose, returnsNormally);
  });
}

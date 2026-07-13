import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_service.dart';

void main() {
  test('shutdown and notifier disposal are idempotent', () async {
    final service = MachineTerminalService();

    await Future.wait<void>(<Future<void>>[
      service.shutdown(),
      service.shutdown(),
    ]);
    service.dispose();

    expect(service.dispose, returnsNormally);
    await expectLater(service.shutdown(), completes);
    expect(
      () => service.ensureWorkspace(sessionId: 'late-session', start: false),
      throwsStateError,
    );
  });
}

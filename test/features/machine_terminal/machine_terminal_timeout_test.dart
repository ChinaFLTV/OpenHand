import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/index.dart';

void main() {
  test(
    'clampMachineTerminalCommandTimeoutMs keeps command timeouts bounded',
    () {
      expect(
        clampMachineTerminalCommandTimeoutMs(0),
        kMachineTerminalMinCommandTimeoutMs,
      );
      expect(
        clampMachineTerminalCommandTimeoutMs(
          kMachineTerminalDefaultCommandTimeout.inMilliseconds,
        ),
        kMachineTerminalDefaultCommandTimeout.inMilliseconds,
      );
      expect(
        clampMachineTerminalCommandTimeoutMs(
          kMachineTerminalMaxCommandTimeoutMs + 1,
        ),
        kMachineTerminalMaxCommandTimeoutMs,
      );
    },
  );
}

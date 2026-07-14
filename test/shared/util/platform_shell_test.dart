import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/platform_shell.dart';

void main() {
  test('prefers the configured shell', () {
    expect(
      preferredPosixShellExecutable(
        environmentShell: ' /custom/shell ',
        isMacOS: false,
      ),
      '/custom/shell',
    );
  });

  test('uses stable platform fallbacks', () {
    expect(
      preferredPosixShellExecutable(environmentShell: '', isMacOS: true),
      defaultMacOsShellExecutable,
    );
    expect(
      preferredPosixShellExecutable(environmentShell: '', isMacOS: false),
      defaultPosixShellExecutable,
    );
  });
}

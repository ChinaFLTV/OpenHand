import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/net/bounded_server_bind.dart';

void main() {
  test('binds and closes a bounded server socket', () async {
    final server = await bindServerSocketBounded(
      InternetAddress.loopbackIPv4,
      0,
      timeout: const Duration(seconds: 1),
    );

    expect(server.port, greaterThan(0));
    await server.close();
  });

  test('binds and closes a bounded HTTP server', () async {
    final server = await bindHttpServerBounded(
      InternetAddress.loopbackIPv4,
      0,
      timeout: const Duration(seconds: 1),
    );

    expect(server.port, greaterThan(0));
    await server.close(force: true);
  });

  test('rejects a non-positive bind timeout', () async {
    await expectLater(
      bindServerSocketBounded(
        InternetAddress.loopbackIPv4,
        0,
        timeout: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}

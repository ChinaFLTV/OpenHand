import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  group('AiSandboxProxyService', () {
    test('rejects HTTP proxy requests matching denied domain rules', () async {
      final lease = await AiSandboxProxyService().start(
        settings: AiSandboxSettings.defaults().copyWith(
          deniedDomains: const <AiSandboxPatternRule>[
            AiSandboxPatternRule(
              id: 'deny-blocked',
              pattern: 'blocked.test',
              matchMode: AiDenyCommandMatchMode.simple,
            ),
          ],
        ),
      );

      Socket? socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          lease.httpPort,
          timeout: const Duration(seconds: 2),
        );
        socket.write(
          'GET http://blocked.test/ HTTP/1.1\r\n'
          'Host: blocked.test\r\n'
          '\r\n',
        );
        await socket.flush();

        final response = await socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 2));

        expect(response, contains('403 Forbidden'));
        expect(
          response,
          anyOf(contains('deny-blocked'), contains('blocked.test')),
        );
      } finally {
        socket?.destroy();
        await lease.close();
      }
    });
  });
}

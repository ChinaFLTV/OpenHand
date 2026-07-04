import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/safe_subprocess.dart';

void main() {
  test('missing probe executables fail without debug stack noise', () async {
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() {
      debugPrint = previousDebugPrint;
    });

    final result = await runTrackedProcessOrFailed(
      '__openhand_missing_hermes_agent_probe__',
      const <String>['--version'],
      tag: 'plugin_lifecycle.verify.hermes-agent',
      timeout: const Duration(milliseconds: 500),
    );

    expect(result.exitCode, -1);
    expect(logs, isEmpty);
  });

  test(
    'missing absolute executable paths fail without debug stack noise',
    () async {
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() {
        debugPrint = previousDebugPrint;
      });

      final missingPath = Platform.isWindows
          ? r'C:\openhand\missing\hermes-agent.exe'
          : '/tmp/openhand/missing/hermes-agent';
      final result = await runTrackedProcessOrFailed(
        missingPath,
        const <String>['--version'],
        tag: 'plugin_lifecycle.verify.hermes-agent',
        timeout: const Duration(milliseconds: 500),
      );

      expect(result.exitCode, -1);
      expect(logs, isEmpty);
    },
  );

  test(
    'line logging still kills timed out process when timeout callback throws',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() {
        debugPrint = previousDebugPrint;
      });

      final result = await runTrackedProcessWithLineLogging(
        '/bin/sh',
        const <String>['-c', 'sleep 1'],
        timeout: const Duration(milliseconds: 50),
        streamDrainTimeout: const Duration(milliseconds: 50),
        onTimeout: () => throw StateError('callback failed'),
      );

      expect(result.timedOut, isTrue);
      expect(result.exitCode, -1);
      expect(
        logs.any((line) => line.contains('timeout handler /bin/sh')),
        isTrue,
      );
    },
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';

void main() {
  test('persistent Bash bounds a line that never emits a newline', () async {
    if (Platform.isWindows) return;

    final service = AiBashToolService()..maxCapturedCharacters = 1024;
    try {
      final result = await service.execute(
        command: "printf '%100000s' '' | tr ' ' x",
        sessionId: 'output-bounding-regression',
        workingDirectory: Directory.systemTemp.path,
        denyRules: const [],
        requireWriteConfirmation: false,
        timeoutMs: 10000,
        dangerouslyDisableSandbox: true,
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, startsWith('x'));
      expect(result.stdout, contains('output truncated'));
      expect(result.stdout.length, lessThan(1100));
    } finally {
      service.dispose();
    }
  });

  test('concurrent commands share one persistent Bash session', () async {
    if (Platform.isWindows) return;

    final service = AiBashToolService();
    try {
      Future<BashToolExecutionResult> execute(String command) {
        return service.execute(
          command: command,
          sessionId: 'single-flight-regression',
          workingDirectory: Directory.systemTemp.path,
          denyRules: const [],
          requireWriteConfirmation: false,
          timeoutMs: 10000,
          dangerouslyDisableSandbox: true,
        );
      }

      final results = await Future.wait(<Future<BashToolExecutionResult>>[
        execute('sleep 0.2; printf first'),
        execute('printf second'),
      ]);

      expect(
        results.where(
          (result) => result.status == BashToolExecutionStatus.success,
        ),
        hasLength(1),
      );
      expect(
        results.where(
          (result) =>
              result.status == BashToolExecutionStatus.failed &&
              result.stderr.contains('Another bash command is already running'),
        ),
        hasLength(1),
      );
    } finally {
      service.dispose();
    }
  });
}

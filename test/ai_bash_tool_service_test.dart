import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/service/ai_bash_tool_service.dart';

void main() {
  test('AiBashToolService blocks commands matching deny rules', () async {
    final service = AiBashToolService();

    final result = await service.execute(
      command: 'rm build/output.txt',
      denyRules: const <AiDenyCommandRule>[
        AiDenyCommandRule(
          id: 'rule-1',
          pattern: 'rm *',
          matchMode: AiDenyCommandMatchMode.simple,
        ),
      ],
      requireWriteConfirmation: false,
    );

    expect(result.status, BashToolExecutionStatus.denied);
    expect(result.matchedRuleId, 'rule-1');
  });

  test(
    'AiBashToolService rejects write commands when confirmation is not granted',
    () async {
      final service = AiBashToolService();

      final result = await service.execute(
        command: 'touch /tmp/openhand-confirmation-test',
        denyRules: const <AiDenyCommandRule>[],
        requireWriteConfirmation: true,
        confirmWriteCommand: (_) async => false,
      );

      expect(result.status, BashToolExecutionStatus.rejected);
      expect(result.stderr, contains('confirmation'));
    },
  );

  test(
    'AiBashToolService cancels cleanly while waiting for write confirmation',
    () async {
      final service = AiBashToolService();
      final cancelCompleter = Completer<void>();
      final approvalCompleter = Completer<bool>();

      final future = service.execute(
        command: 'touch /tmp/openhand-cancel-test',
        denyRules: const <AiDenyCommandRule>[],
        requireWriteConfirmation: true,
        confirmWriteCommand: (_) => approvalCompleter.future,
        cancelSignal: cancelCompleter.future,
      );

      cancelCompleter.complete();
      final result = await future;

      expect(result.status, BashToolExecutionStatus.cancelled);
      expect(result.stderr, contains('cancelled'));
      expect(approvalCompleter.isCompleted, isFalse);
    },
  );

  test(
    'AiBashToolService parses shell commands structurally for write checks',
    () {
      final service = AiBashToolService();

      expect(service.isLikelyWriteCommand('pwd'), isFalse);
      expect(
        service.isLikelyWriteCommand('cat README.md | rg OpenHand'),
        isFalse,
      );
      expect(service.isLikelyWriteCommand('find . -name "*.dart"'), isFalse);
      expect(service.isLikelyWriteCommand('git diff --stat'), isFalse);
      expect(service.isLikelyWriteCommand('tar -tf archive.tar'), isFalse);

      expect(service.isLikelyWriteCommand('echo hello > out.txt'), isTrue);
      expect(
        service.isLikelyWriteCommand('find . -type f -exec rm {} +'),
        isTrue,
      );
      expect(service.isLikelyWriteCommand('xargs rm < files.txt'), isTrue);
      expect(
        service.isLikelyWriteCommand("bash -lc 'echo hello > out.txt'"),
        isTrue,
      );
      expect(
        service.isLikelyWriteCommand('git checkout -- lib/main.dart'),
        isTrue,
      );
      expect(service.isLikelyWriteCommand('tar -xzf archive.tar.gz'), isTrue);
      expect(service.isLikelyWriteCommand('python script.py'), isTrue);
      expect(service.isLikelyWriteCommand('flutter test'), isTrue);
    },
  );

  test(
    'AiBashToolService treats stderr suppression and fd duplication as read-only',
    () {
      final service = AiBashToolService();

      expect(
        service.isLikelyWriteCommand(
          'find ~/Library/Application\\ Support/JetBrains -name "*.app" -type d 2>/dev/null | head -10',
        ),
        isFalse,
      );
      expect(service.isLikelyWriteCommand('which brew 2>/dev/null'), isFalse);
      expect(
        service.isLikelyWriteCommand('ls -la /Applications/ 2>&1'),
        isFalse,
      );
      expect(service.isLikelyWriteCommand('echo hello >/dev/null'), isFalse);
    },
  );

  test('AiBashToolService fast-paths long heredoc write commands', () {
    final service = AiBashToolService();
    final longCommand =
        "mkdir -p temp_particle_project && cd temp_particle_project && cat > particle_web.html <<'EOF'\n${'<!DOCTYPE html>\n' * 120}EOF";

    final analysis = service.analyzeWriteCommand(longCommand);

    expect(analysis.isWrite, isTrue);
    expect(analysis.reason, contains('fast-path'));
  });

  test(
    'AiBashToolService reuses environment state inside a persistent session',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final service = AiBashToolService();
      addTearDown(service.dispose);

      final exportResult = await service.execute(
        command: 'export OPENHAND_PERSIST_TEST=sticky_value',
        sessionId: 'persistent-env',
        denyRules: const <AiDenyCommandRule>[],
        requireWriteConfirmation: false,
      );
      final readResult = await service.execute(
        command: r'printf %s "$OPENHAND_PERSIST_TEST"',
        sessionId: 'persistent-env',
        denyRules: const <AiDenyCommandRule>[],
        requireWriteConfirmation: false,
      );

      expect(exportResult.status, BashToolExecutionStatus.success);
      expect(readResult.status, BashToolExecutionStatus.success);
      expect(readResult.stdout.trim(), 'sticky_value');
    },
  );

  test(
    'AiBashToolService preserves cwd across persistent session commands',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final service = AiBashToolService();
      addTearDown(service.dispose);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-bash-cwd-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final changeDirectoryResult = await service.execute(
        command: 'cd ${_quoteForShell(tempDirectory.path)}',
        sessionId: 'persistent-cwd',
        denyRules: const <AiDenyCommandRule>[],
        requireWriteConfirmation: false,
      );
      final pwdResult = await service.execute(
        command: 'pwd',
        sessionId: 'persistent-cwd',
        denyRules: const <AiDenyCommandRule>[],
        requireWriteConfirmation: false,
      );

      expect(changeDirectoryResult.status, BashToolExecutionStatus.success);
      expect(
        p.normalize(pwdResult.stdout.trim()),
        p.normalize(tempDirectory.path),
      );
    },
  );

  test(
    'AiBashToolService returns a failed result when a persistent session cannot start',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final service = AiBashToolService();
      addTearDown(service.dispose);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-bash-missing-cwd-',
      );
      final missingDirectoryPath = tempDirectory.path;
      await tempDirectory.delete(recursive: true);

      final result = await service.execute(
        command: 'pwd',
        sessionId: 'persistent-missing-cwd',
        workingDirectory: missingDirectoryPath,
        denyRules: const <AiDenyCommandRule>[],
        requireWriteConfirmation: false,
      );

      expect(result.status, BashToolExecutionStatus.failed);
      expect(result.workingDirectory, p.normalize(missingDirectoryPath));
      expect(result.stderr, isNotEmpty);
    },
  );
}

String _quoteForShell(String value) {
  return "'${value.replaceAll("'", r"'\''")}'";
}

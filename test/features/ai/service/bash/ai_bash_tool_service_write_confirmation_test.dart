import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';

void main() {
  group('AiBashToolService write confirmation metadata', () {
    test(
      'marks missing confirmation callback as rejected no-run write',
      () async {
        final result = await _executeWriteLikeCommand();

        expect(result.status, BashToolExecutionStatus.rejected);
        expect(result.isWriteCommand, isTrue);
        expect(result.metadata['write_confirmation_decision'], 'rejected');
        expect(result.metadata['write_confirmation_rejected'], isTrue);
        expect(result.metadata['write_confirmation_missing_callback'], isTrue);
        expect(
          result.toToolOutput(),
          contains('write_confirmation_decision: rejected'),
        );

        final converted = AiToolExecutionResult.fromBash(
          result,
          metadata: const <String, Object?>{'outer_metadata': true},
        );
        expect(converted.metadata['write_confirmation_decision'], 'rejected');
        expect(
          converted.metadata['write_confirmation_missing_callback'],
          isTrue,
        );
        expect(converted.metadata['outer_metadata'], isTrue);
      },
    );

    test('preserves explicit rejection decision metadata', () async {
      final result = await _executeWriteLikeCommand(
        decision: BashCommandApprovalDecision.rejected,
      );

      expect(result.status, BashToolExecutionStatus.rejected);
      expect(result.metadata['write_confirmation_decision'], 'rejected');
      expect(result.metadata['write_confirmation_rejected'], isTrue);
      expect(result.stderr, contains('explicitly rejected'));
    });

    test('preserves dismissed dialog as deferred decision metadata', () async {
      final result = await _executeWriteLikeCommand(
        decision: BashCommandApprovalDecision.dismissed,
      );

      expect(result.status, BashToolExecutionStatus.rejected);
      expect(result.metadata['write_confirmation_decision'], 'dismissed');
      expect(result.metadata['write_confirmation_dismissed'], isTrue);
      expect(result.stderr, contains('decision deferred'));
    });

    test(
      'marks timed out confirmation future without executing command',
      () async {
        final service = _serviceWithWriteCommand();
        service.writeConfirmationTimeoutMs = 1;
        final pending = Completer<BashCommandApprovalDecision>();

        final result = await service.execute(
          command: _writeCommand,
          workingDirectory: '/tmp',
          denyRules: const [],
          requireWriteConfirmation: true,
          confirmWriteCommand: (_) => pending.future,
        );

        expect(result.status, BashToolExecutionStatus.timedOut);
        expect(result.metadata['write_confirmation_decision'], 'timed_out');
        expect(result.metadata['write_confirmation_timed_out'], isTrue);
        expect(result.stderr, contains('confirmation prompt timed out'));
      },
    );

    test('marks session cancellation before confirmation completes', () async {
      final service = _serviceWithWriteCommand();
      final pending = Completer<BashCommandApprovalDecision>();

      final result = await service.execute(
        command: _writeCommand,
        workingDirectory: '/tmp',
        denyRules: const [],
        requireWriteConfirmation: true,
        confirmWriteCommand: (_) => pending.future,
        cancelSignal: Future<void>.value(),
      );

      expect(result.status, BashToolExecutionStatus.cancelled);
      expect(result.metadata['write_confirmation_decision'], 'cancelled');
      expect(result.metadata['write_confirmation_cancelled'], isTrue);
      expect(result.stderr, contains('command was cancelled'));
    });
  });
}

const String _writeCommand = 'touch /tmp/openhand-bash-confirmation-test';

AiBashToolService _serviceWithWriteCommand() {
  final service = AiBashToolService();
  expect(service.analyzeWriteCommand(_writeCommand).isWrite, isTrue);
  return service;
}

Future<BashToolExecutionResult> _executeWriteLikeCommand({
  BashCommandApprovalDecision? decision,
  Future<BashCommandApprovalDecision> Function(
    BashCommandApprovalRequest request,
  )?
  confirmWriteCommand,
}) {
  final service = _serviceWithWriteCommand();
  final callback =
      confirmWriteCommand ??
      (decision == null
          ? null
          : (BashCommandApprovalRequest request) async {
              expect(request.command, _writeCommand);
              expect(request.workingDirectory, '/tmp');
              expect(request.isWriteCommand, isTrue);
              return decision;
            });
  return service.execute(
    command: _writeCommand,
    workingDirectory: '/tmp',
    denyRules: const [],
    requireWriteConfirmation: true,
    confirmWriteCommand: callback,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_utils.dart';

void main() {
  group('AiToolUtils.requestWriteConfirmation', () {
    test('returns null when confirmation is not required', () async {
      final result = await _request(
        requireWriteConfirmation: false,
        decision: BashCommandApprovalDecision.rejected,
      );

      expect(result, isNull);
    });

    test('returns null after approval', () async {
      final result = await _request(
        decision: BashCommandApprovalDecision.approved,
      );

      expect(result, isNull);
    });

    test('rejects safely when confirmation callback is missing', () async {
      final result = await AiToolUtils.requestWriteConfirmation(
        toolName: 'Write',
        operationDescription: 'Overwrite file',
        targetPath: '/tmp/openhand-test.txt',
        requireWriteConfirmation: true,
        confirmWriteCommand: null,
        metadata: const <String, Object?>{'source': 'test'},
      );

      expect(result, isNotNull);
      expect(result!.status, BashToolExecutionStatus.rejected);
      expect(result.isWriteCommand, isTrue);
      expect(result.metadata['source'], 'test');
      expect(result.metadata['write_confirmation_decision'], 'rejected');
      expect(result.metadata['write_confirmation_rejected'], isTrue);
      expect(result.metadata['write_confirmation_missing_callback'], isTrue);
    });

    test(
      'preserves explicit user rejection as no-run write metadata',
      () async {
        final result = await _request(
          decision: BashCommandApprovalDecision.rejected,
        );

        expect(result, isNotNull);
        expect(result!.status, BashToolExecutionStatus.rejected);
        expect(result.isWriteCommand, isTrue);
        expect(result.stderr, contains('请勿重试'));
        expect(result.metadata['write_confirmation_decision'], 'rejected');
        expect(result.metadata['write_confirmation_rejected'], isTrue);
      },
    );

    test('treats dismissed dialog as deferred decision', () async {
      final result = await _request(
        decision: BashCommandApprovalDecision.dismissed,
      );

      expect(result, isNotNull);
      expect(result!.status, BashToolExecutionStatus.rejected);
      expect(result.isWriteCommand, isTrue);
      expect(result.stderr, contains('决策悬置'));
      expect(result.metadata['write_confirmation_decision'], 'dismissed');
      expect(result.metadata['write_confirmation_dismissed'], isTrue);
    });

    test('marks presenter timeout without executing the write', () async {
      final result = await _request(
        decision: BashCommandApprovalDecision.timedOut,
      );

      expect(result, isNotNull);
      expect(result!.status, BashToolExecutionStatus.timedOut);
      expect(result.isWriteCommand, isTrue);
      expect(result.stderr, contains('本次工具调用未执行'));
      expect(result.metadata['write_confirmation_decision'], 'timed_out');
      expect(result.metadata['write_confirmation_timed_out'], isTrue);
    });

    test('marks cancellation as a write confirmation cancellation', () async {
      final result = await _request(
        decision: BashCommandApprovalDecision.cancelled,
      );

      expect(result, isNotNull);
      expect(result!.status, BashToolExecutionStatus.cancelled);
      expect(result.isWriteCommand, isTrue);
      expect(result.stderr, contains('本次工具调用未执行'));
      expect(result.metadata['write_confirmation_decision'], 'cancelled');
      expect(result.metadata['write_confirmation_cancelled'], isTrue);
    });
  });
}

Future<AiToolExecutionResult?> _request({
  required BashCommandApprovalDecision decision,
  bool requireWriteConfirmation = true,
}) {
  return AiToolUtils.requestWriteConfirmation(
    toolName: 'Write',
    operationDescription: 'Overwrite file',
    targetPath: '/tmp/openhand-test.txt',
    requireWriteConfirmation: requireWriteConfirmation,
    confirmWriteCommand: (request) async {
      expect(request.command, contains('Overwrite file'));
      expect(request.workingDirectory, '/tmp');
      expect(request.isWriteCommand, isTrue);
      return decision;
    },
    metadata: const <String, Object?>{'source': 'test'},
  );
}

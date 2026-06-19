import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/planning/ai_exit_plan_mode_tool.dart';

void main() {
  group('AiExitPlanModeTool', () {
    test('captures a trimmed plan and requests approval', () async {
      final result = await AiExitPlanModeTool().execute(
        _context(
          plan:
              '  1. Inspect the affected runtime path.\n'
              '2. Patch the narrow behavior.\n'
              '3. Run targeted tests and build.  ',
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('Plan captured'));
      expect(result.metadata['plan_mode_awaiting_approval'], true);
      expect(
        result.metadata['pending_plan'],
        '1. Inspect the affected runtime path.\n'
        '2. Patch the narrow behavior.\n'
        '3. Run targeted tests and build.',
      );
    });

    test('rejects an empty plan', () async {
      final result = await AiExitPlanModeTool().execute(_context(plan: '   '));

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('requires a non-empty plan'));
      expect(result.metadata, isEmpty);
    });
  });
}

AiToolExecutionContext _context({required String plan}) {
  final arguments = <String, Object?>{'plan': plan};
  return AiToolExecutionContext(
    sessionId: 'session-1',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'tool-call-1',
      name: 'ExitPlanMode',
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: _testModel,
    previouslyReadFiles: const <String>{},
    denyCommandRules: const <AiDenyCommandRule>[],
    requireWriteCommandConfirmation: true,
    confirmWriteCommand: null,
  );
}

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

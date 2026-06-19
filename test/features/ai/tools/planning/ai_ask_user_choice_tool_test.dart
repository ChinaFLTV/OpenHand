import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/planning/ai_ask_user_choice_tool.dart';

void main() {
  group('AiAskUserChoiceTool', () {
    void Function()? disposePresenter;

    tearDown(() {
      disposePresenter?.call();
      disposePresenter = null;
    });

    test('blocks plan approval questions before opening the dialog', () async {
      var presenterCalls = 0;
      disposePresenter = AiAskUserChoiceTool.registerPresenter((request) async {
        presenterCalls += 1;
        return const AskUserChoiceResponse(value: 'approve', isCustom: false);
      });

      final result = await AiAskUserChoiceTool().execute(
        _context(
          title: 'Is this plan okay?',
          description: 'Should I proceed with implementation now?',
          metadata: _planningMetadata,
        ),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('use ExitPlanMode'));
      expect(result.metadata['ask_user_choice_blocked_plan_approval'], isTrue);
      expect(
        result.metadata['ask_user_choice_block_reason'],
        'plan_approval_requires_exit_plan_mode',
      );
      expect(result.metadata['plan_approval_tool'], 'ExitPlanMode');
      expect(result.metadata['plan_mode_active'], isTrue);
      expect(result.metadata['awaiting_plan_approval'], isFalse);
      expect(result.metadata['plan_mode_execution_approved_for_send'], isFalse);
      expect(presenterCalls, 0);
    });

    test('allows plan clarification choices before approval', () async {
      var presenterCalls = 0;
      disposePresenter = AiAskUserChoiceTool.registerPresenter((request) async {
        presenterCalls += 1;
        expect(request.title, 'Choose auth strategy');
        return const AskUserChoiceResponse(value: 'oauth', isCustom: false);
      });

      final result = await AiAskUserChoiceTool().execute(
        _context(
          title: 'Choose auth strategy',
          description: 'Pick the approach the implementation plan should use.',
          metadata: _planningMetadata,
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(jsonDecode(result.stdout), <String, Object?>{
        'value': 'oauth',
        'is_custom': false,
      });
      expect(presenterCalls, 1);
    });
  });
}

AiToolExecutionContext _context({
  required String title,
  required String description,
  required Map<String, Object?> metadata,
}) {
  final arguments = <String, Object?>{
    'title': title,
    'description': description,
    'options': <Map<String, Object?>>[
      <String, Object?>{'value': 'oauth', 'label': 'OAuth'},
      <String, Object?>{'value': 'jwt', 'label': 'JWT'},
    ],
    'allow_custom_input': false,
  };
  return AiToolExecutionContext(
    sessionId: 'session-1',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'tool-call-1',
      name: 'AskUserChoice',
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: _testModel,
    previouslyReadFiles: const <String>{},
    denyCommandRules: const <AiDenyCommandRule>[],
    requireWriteCommandConfirmation: true,
    confirmWriteCommand: null,
    metadata: metadata,
  );
}

const Map<String, Object?> _planningMetadata = <String, Object?>{
  'plan_mode_active': true,
  'awaiting_plan_approval': false,
  'plan_mode_execution_approved_for_send': false,
};

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

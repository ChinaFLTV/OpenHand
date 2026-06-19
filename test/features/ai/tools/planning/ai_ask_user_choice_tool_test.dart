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

    test('accepts Claude AskUserQuestion single-choice payload', () async {
      var presenterCalls = 0;
      disposePresenter = AiAskUserChoiceTool.registerPresenter((request) async {
        presenterCalls += 1;
        expect(request.title, 'Which auth strategy should we implement?');
        expect(request.description, 'Auth');
        expect(request.allowCustomInput, isFalse);
        expect(request.options, hasLength(2));
        expect(request.options[0].value, 'OAuth');
        expect(request.options[0].label, 'OAuth');
        expect(request.options[0].description, 'Use OAuth provider login.');
        return const AskUserChoiceResponse(value: 'OAuth', isCustom: false);
      });

      final result = await AiAskUserChoiceTool().execute(
        _rawContext(
          name: 'AskUserQuestion',
          arguments: <String, Object?>{
            'questions': <Map<String, Object?>>[
              <String, Object?>{
                'question': 'Which auth strategy should we implement?',
                'header': 'Auth',
                'options': <Map<String, Object?>>[
                  <String, Object?>{
                    'label': 'OAuth',
                    'description': 'Use OAuth provider login.',
                  },
                  <String, Object?>{
                    'label': 'JWT',
                    'description': 'Use signed local tokens.',
                  },
                ],
              },
            ],
          },
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.command, 'AskUserQuestion');
      expect(jsonDecode(result.stdout), <String, Object?>{
        'questions': <Object?>[
          <String, Object?>{
            'question': 'Which auth strategy should we implement?',
            'header': 'Auth',
            'options': <Object?>[
              <String, Object?>{
                'label': 'OAuth',
                'description': 'Use OAuth provider login.',
              },
              <String, Object?>{
                'label': 'JWT',
                'description': 'Use signed local tokens.',
              },
            ],
            'multiSelect': false,
          },
        ],
        'answers': <String, Object?>{
          'Which auth strategy should we implement?': 'OAuth',
        },
      });
      expect(presenterCalls, 1);
    });

    test('rejects unsupported Claude AskUserQuestion shapes', () async {
      var presenterCalls = 0;
      disposePresenter = AiAskUserChoiceTool.registerPresenter((request) async {
        presenterCalls += 1;
        return const AskUserChoiceResponse(value: 'OAuth', isCustom: false);
      });

      Future<AiToolExecutionResult> run(Map<String, Object?> arguments) {
        return AiAskUserChoiceTool().execute(
          _rawContext(name: 'AskUserQuestion', arguments: arguments),
        );
      }

      final multiQuestion = await run(<String, Object?>{
        'questions': <Map<String, Object?>>[
          _claudeQuestion('First?'),
          _claudeQuestion('Second?'),
        ],
      });
      expect(multiQuestion.status, BashToolExecutionStatus.invalidArguments);
      expect(multiQuestion.stderr, contains('exactly one question'));

      final multiSelect = await run(<String, Object?>{
        'questions': <Map<String, Object?>>[
          <String, Object?>{
            ..._claudeQuestion('Pick features?'),
            'multiSelect': true,
          },
        ],
      });
      expect(multiSelect.status, BashToolExecutionStatus.invalidArguments);
      expect(multiSelect.stderr, contains('multiSelect'));

      final preview = await run(<String, Object?>{
        'questions': <Map<String, Object?>>[
          <String, Object?>{
            ..._claudeQuestion('Pick style?'),
            'options': <Map<String, Object?>>[
              <String, Object?>{
                'label': 'Compact',
                'description': 'Dense layout.',
                'preview': '<div>Compact</div>',
              },
              <String, Object?>{
                'label': 'Spacious',
                'description': 'Roomier layout.',
              },
            ],
          },
        ],
      });
      expect(preview.status, BashToolExecutionStatus.invalidArguments);
      expect(preview.stderr, contains('preview'));
      expect(presenterCalls, 0);
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

AiToolExecutionContext _rawContext({
  required String name,
  required Map<String, Object?> arguments,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return AiToolExecutionContext(
    sessionId: 'session-1',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'tool-call-1',
      name: name,
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

Map<String, Object?> _claudeQuestion(String question) {
  return <String, Object?>{
    'question': question,
    'header': 'Choice',
    'options': <Map<String, Object?>>[
      <String, Object?>{
        'label': 'OAuth',
        'description': 'Use OAuth provider login.',
      },
      <String, Object?>{
        'label': 'JWT',
        'description': 'Use signed local tokens.',
      },
    ],
  };
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

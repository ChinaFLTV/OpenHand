import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';

void main() {
  group('AiTodoWriteTool argument parsing', () {
    test('normalizes dirty todo maps while preserving validation', () async {
      final result = await AiTodoWriteTool().execute(
        _toolContext(
          name: 'TodoWrite',
          arguments: <String, Object?>{
            'todos': <Object?>[
              <Object?, Object?>{
                'id': 7,
                'content': ' inspect parsing ',
                'status': 'pending',
                'active_form': ' inspecting parsing ',
              },
              <Object?, Object?>{
                'content': 'verify behavior',
                'status': 'completed',
              },
            ],
          },
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      final todoItems = stringKeyedMapListFromValue(
        result.metadata['todo_items'],
      );
      expect(todoItems, hasLength(2));
      expect(todoItems.first['id'], '7');
      expect(todoItems.first['activeForm'], 'inspecting parsing');
      expect(todoItems.last['id'], '2');
      expect(result.stdout, contains('[ ] 7: inspect parsing'));
      expect(result.stdout, contains('[x] 2: verify behavior'));
    });

    test('keeps non-object todo entries invalid', () async {
      final result = await AiTodoWriteTool().execute(
        _toolContext(
          name: 'TodoWrite',
          arguments: <String, Object?>{
            'todos': <Object?>['not an object'],
          },
        ),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('Each todo must be an object'));
    });

    test('accepts todo arrays encoded as JSON text', () async {
      final result = await AiTodoWriteTool().execute(
        _toolContext(
          name: 'TodoWrite',
          arguments: <String, Object?>{
            'todos': jsonEncode(<Object?>[
              <String, Object?>{
                'content': 'ship parser fallback',
                'status': 'in_progress',
              },
            ]),
          },
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      final todoItems = stringKeyedMapListFromValue(
        result.metadata['todo_items'],
      );
      expect(todoItems.single['content'], 'ship parser fallback');
      expect(todoItems.single['status'], 'in_progress');
    });
  });

  group('AiAskUserChoiceTool argument parsing', () {
    test('normalizes dirty option maps and string boolean flags', () async {
      AskUserChoiceRequest? capturedRequest;
      final dispose = AiAskUserChoiceTool.registerPresenter((request) async {
        capturedRequest = request;
        return const AskUserChoiceResponse(value: 'b', isCustom: false);
      });
      addTearDown(dispose);

      final result = await AiAskUserChoiceTool().execute(
        _toolContext(
          name: 'AskUserChoice',
          arguments: <String, Object?>{
            'title': 'Pick one',
            'allow_custom_input': 'false',
            'options': <Object?>[
              <Object?, Object?>{
                'value': 'a',
                'label': ' A ',
                'description': ' First ',
              },
              <Object?, Object?>{'value': 'b', 'label': 'B'},
            ],
          },
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.allowCustomInput, isFalse);
      expect(capturedRequest!.options.first.label, 'A');
      expect(capturedRequest!.options.first.description, 'First');
      expect(jsonDecode(result.stdout), <String, Object?>{
        'value': 'b',
        'is_custom': false,
      });
    });

    test('normalizes AskUserQuestion compatibility objects', () async {
      AskUserChoiceRequest? capturedRequest;
      final dispose = AiAskUserChoiceTool.registerPresenter((request) async {
        capturedRequest = request;
        return const AskUserChoiceResponse(value: 'One', isCustom: false);
      });
      addTearDown(dispose);

      final result = await AiAskUserChoiceTool().execute(
        _toolContext(
          name: 'AskUserQuestion',
          arguments: <String, Object?>{
            'questions': jsonEncode(<Object?>[
              <Object?, Object?>{
                'question': 'Choose',
                'header': 'Short',
                'multiSelect': 0,
                'options': jsonEncode(<Object?>[
                  <Object?, Object?>{
                    'label': 'One',
                    'description': 'First option',
                  },
                  <Object?, Object?>{'label': 'Two'},
                ]),
              },
            ]),
          },
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.title, 'Choose');
      expect(capturedRequest!.description, 'Short');
      expect(capturedRequest!.allowCustomInput, isFalse);
      expect(capturedRequest!.options.map((item) => item.value), <String>[
        'One',
        'Two',
      ]);
      final decoded = stringKeyedMapFromValue(jsonDecode(result.stdout));
      expect(decoded['answers'], <String, Object?>{'Choose': 'One'});
    });
  });

  group('AiExitPlanModeTool argument parsing', () {
    test('accepts allowed_prompts encoded as JSON text', () async {
      final result = await AiExitPlanModeTool().execute(
        _toolContext(
          name: 'ExitPlanMode',
          arguments: <String, Object?>{
            'plan': '1. Run focused validation',
            'allowed_prompts': jsonEncode(<Object?>[
              <String, Object?>{
                'tool': 'Bash',
                'prompt': 'run focused validation',
              },
            ]),
          },
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      final allowedPrompts = stringKeyedMapListFromValue(
        result.metadata['plan_mode_allowed_prompts'],
      );
      expect(allowedPrompts.single['tool'], 'Bash');
      expect(allowedPrompts.single['prompt'], 'run focused validation');
    });

    test('recovers plan from current_todos encoded as JSON text', () async {
      final result = await AiExitPlanModeTool().execute(
        _toolContext(
          name: 'ExitPlanMode',
          arguments: const <String, Object?>{},
          metadata: <String, Object?>{
            'current_todos': jsonEncode(<Object?>[
              <String, Object?>{
                'content': 'Inspect affected parser paths',
                'status': 'pending',
              },
              <String, Object?>{
                'content': 'Skip completed work',
                'status': 'completed',
              },
            ]),
          },
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(
        result.metadata['pending_plan'],
        '1. Inspect affected parser paths',
      );
      expect(result.metadata['pending_plan_source'], 'current_todos');
    });
  });
}

AiToolExecutionContext _toolContext({
  required String name,
  required Map<String, Object?> arguments,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return AiToolExecutionContext(
    sessionId: 'test-session',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'tool-call',
      name: name,
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: const AiModelConfig(
      id: 'test-model',
      baseUrl: 'https://example.invalid',
      authScheme: AiAuthScheme.none,
      token: '',
      modelId: 'test',
      protocolType: AiProtocolType.openai,
    ),
    previouslyReadFiles: <String>{},
    denyCommandRules: const <AiDenyCommandRule>[],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
    metadata: metadata,
  );
}

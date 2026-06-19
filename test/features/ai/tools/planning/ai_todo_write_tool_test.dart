import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/planning/ai_todo_write_tool.dart';

void main() {
  group('AiTodoWriteTool', () {
    test('normalizes todos and replaces the session todo list', () async {
      final result = await AiTodoWriteTool().execute(
        _context(
          todos: <Map<String, Object?>>[
            <String, Object?>{
              'id': ' 1 ',
              'content': ' Inspect implementation ',
              'status': 'in_progress',
            },
            <String, Object?>{
              'id': '2',
              'content': 'Run tests',
              'status': 'pending',
            },
            <String, Object?>{
              'id': '3',
              'content': 'Commit verified changes',
              'status': 'completed',
            },
          ],
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('[-] 1: Inspect implementation'));
      expect(result.stdout, contains('[ ] 2: Run tests'));
      expect(result.stdout, contains('[x] 3: Commit verified changes'));
      expect(result.metadata['todo_list_replaced'], true);
      expect(result.metadata['oldTodos'], isEmpty);
      expect(result.metadata['todo_items'], <Map<String, Object?>>[
        <String, Object?>{
          'id': '1',
          'content': 'Inspect implementation',
          'status': 'in_progress',
        },
        <String, Object?>{
          'id': '2',
          'content': 'Run tests',
          'status': 'pending',
        },
        <String, Object?>{
          'id': '3',
          'content': 'Commit verified changes',
          'status': 'completed',
        },
      ]);
      expect(result.metadata['newTodos'], result.metadata['todo_items']);
      expect(result.metadata['todo_all_completed'], false);
      expect(
        result.metadata['todo_items_for_next_turn'],
        result.metadata['todo_items'],
      );
    });

    test('allows clearing the todo list', () async {
      final result = await AiTodoWriteTool().execute(
        _context(todos: const <Map<String, Object?>>[]),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, '(todo list cleared)');
      expect(result.metadata['todo_items'], isEmpty);
      expect(result.metadata['todo_list_replaced'], true);
    });

    test(
      'accepts Claude-style todos with activeForm and generated ids',
      () async {
        final result = await AiTodoWriteTool().execute(
          _context(
            todos: const <Map<String, Object?>>[
              <String, Object?>{
                'content': 'Inspect current flow',
                'status': 'in_progress',
                'activeForm': 'Inspecting current flow',
              },
              <String, Object?>{
                'content': 'Implement minimal change',
                'status': 'pending',
              },
            ],
          ),
        );

        expect(result.status, BashToolExecutionStatus.success);
        expect(result.stdout, contains('[-] 1: Inspect current flow'));
        expect(result.stdout, contains('[ ] 2: Implement minimal change'));
        expect(result.metadata['todo_items'], <Map<String, Object?>>[
          <String, Object?>{
            'id': '1',
            'content': 'Inspect current flow',
            'status': 'in_progress',
            'activeForm': 'Inspecting current flow',
          },
          <String, Object?>{
            'id': '2',
            'content': 'Implement minimal change',
            'status': 'pending',
          },
        ]);
      },
    );

    test(
      'reminds verification before final claim after completing major todos',
      () async {
        final result = await AiTodoWriteTool().execute(
          _context(
            todos: const <Map<String, Object?>>[
              <String, Object?>{
                'id': '1',
                'content': 'Inspect implementation',
                'status': 'completed',
              },
              <String, Object?>{
                'id': '2',
                'content': 'Patch runtime',
                'status': 'completed',
              },
              <String, Object?>{
                'id': '3',
                'content': 'Commit verified changes',
                'status': 'completed',
              },
            ],
          ),
        );

        expect(result.status, BashToolExecutionStatus.success);
        expect(result.stdout, contains('verification_reminder'));
        expect(result.stdout, contains('Task(subagent_type: verify)'));
        expect(result.metadata['todo_verification_reminder'], true);
        expect(result.metadata['todo_all_completed'], true);
        expect(result.metadata['todo_items_for_next_turn'], isEmpty);
      },
    );

    test(
      'does not repeat verification reminder when completed todos include verification',
      () async {
        final result = await AiTodoWriteTool().execute(
          _context(
            todos: const <Map<String, Object?>>[
              <String, Object?>{
                'id': '1',
                'content': 'Inspect implementation',
                'status': 'completed',
              },
              <String, Object?>{
                'id': '2',
                'content': 'Patch runtime',
                'status': 'completed',
              },
              <String, Object?>{
                'id': '3',
                'content': 'Run tests',
                'status': 'completed',
              },
            ],
            metadata: const <String, Object?>{
              'current_todos': <Map<String, Object?>>[
                <String, Object?>{
                  'id': '1',
                  'content': 'Inspect implementation',
                  'status': 'in_progress',
                  'activeForm': 'Inspecting implementation',
                },
              ],
            },
          ),
        );

        expect(result.status, BashToolExecutionStatus.success);
        expect(result.stdout, isNot(contains('verification_reminder')));
        expect(result.metadata['todo_verification_reminder'], isNull);
        expect(result.metadata['todo_all_completed'], true);
        expect(result.metadata['oldTodos'], <Map<String, Object?>>[
          <String, Object?>{
            'id': '1',
            'content': 'Inspect implementation',
            'status': 'in_progress',
            'activeForm': 'Inspecting implementation',
          },
        ]);
        expect(result.metadata['newTodos'], result.metadata['todo_items']);
        expect(result.metadata['todo_items_for_next_turn'], isEmpty);
      },
    );

    test('rejects duplicate ids', () async {
      final result = await AiTodoWriteTool().execute(
        _context(
          todos: const <Map<String, Object?>>[
            <String, Object?>{
              'id': '1',
              'content': 'First',
              'status': 'in_progress',
            },
            <String, Object?>{
              'id': '1',
              'content': 'Second',
              'status': 'pending',
            },
          ],
        ),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('Todo ids must be unique'));
    });

    test('rejects unsupported statuses', () async {
      final result = await AiTodoWriteTool().execute(
        _context(
          todos: const <Map<String, Object?>>[
            <String, Object?>{
              'id': '1',
              'content': 'Inspect implementation',
              'status': 'blocked',
            },
          ],
        ),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(
        result.stderr,
        contains('pending, in_progress, completed, or failed'),
      );
    });

    test('rejects multiple in-progress todos', () async {
      final result = await AiTodoWriteTool().execute(
        _context(
          todos: const <Map<String, Object?>>[
            <String, Object?>{
              'id': '1',
              'content': 'Inspect implementation',
              'status': 'in_progress',
            },
            <String, Object?>{
              'id': '2',
              'content': 'Run tests',
              'status': 'in_progress',
            },
          ],
        ),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('Only one todo may be in_progress'));
    });
  });
}

AiToolExecutionContext _context({
  required Object? todos,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  final arguments = <String, Object?>{'todos': todos};
  return AiToolExecutionContext(
    sessionId: 'session-1',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'tool-call-1',
      name: 'TodoWrite',
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

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

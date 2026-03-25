import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/model/ai_allow_command_rule.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';

void main() {
  test('AiPromptBuilder skips orphan tool history turns', () {
    const builder = AiPromptBuilder();
    final prompt = builder.buildSessionPrompt(
      templateBundle: _templateBundle(),
      session: _session(
        messages: [
          AiSessionMessage.toolResult(
            id: 'tool-result-1',
            content: '{"status":"ok"}',
            createdAt: DateTime.utc(2026, 3, 23, 6, 0, 0),
            metadata: const <String, Object?>{
              'tool_call_id': 'tool-call-1',
              'tool_name': 'bash',
            },
          ),
          AiSessionMessage.user(
            id: 'user-1',
            content: 'Hello',
            createdAt: DateTime.utc(2026, 3, 23, 6, 0, 1),
          ),
        ],
      ),
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: const [],
      sessionMessages: _session(
        messages: [
          AiSessionMessage.toolResult(
            id: 'tool-result-1',
            content: '{"status":"ok"}',
            createdAt: DateTime.utc(2026, 3, 23, 6, 0, 0),
            metadata: const <String, Object?>{
              'tool_call_id': 'tool-call-1',
              'tool_name': 'bash',
            },
          ),
          AiSessionMessage.user(
            id: 'user-1',
            content: 'Hello',
            createdAt: DateTime.utc(2026, 3, 23, 6, 0, 1),
          ),
        ],
      ).messages,
      latestUserMessageId: 'user-1',
    );

    expect(
      prompt.messages.where((item) => item.role == AiChatRole.tool),
      isEmpty,
    );
    expect(prompt.historyMessageCount, 0);
  });

  test('AiPromptBuilder keeps complete tool exchanges together', () {
    const builder = AiPromptBuilder();
    final prompt = builder.buildSessionPrompt(
      templateBundle: _templateBundle(),
      session: _session(
        messages: [
          AiSessionMessage.toolCall(
            id: 'tool-call-message',
            content: '',
            createdAt: DateTime.utc(2026, 3, 23, 6, 5, 0),
            metadata: const <String, Object?>{
              'tool_calls': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'tool-call-1',
                  'name': 'bash',
                  'arguments': '{"cmd":"pwd"}',
                },
              ],
            },
          ),
          AiSessionMessage.toolResult(
            id: 'tool-result-1',
            content: '/workspace',
            createdAt: DateTime.utc(2026, 3, 23, 6, 5, 1),
            metadata: const <String, Object?>{
              'tool_call_id': 'tool-call-1',
              'tool_name': 'bash',
            },
          ),
          AiSessionMessage.user(
            id: 'user-1',
            content: 'Continue',
            createdAt: DateTime.utc(2026, 3, 23, 6, 5, 2),
          ),
        ],
      ),
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: const [],
      sessionMessages: _session(
        messages: [
          AiSessionMessage.toolCall(
            id: 'tool-call-message',
            content: '',
            createdAt: DateTime.utc(2026, 3, 23, 6, 5, 0),
            metadata: const <String, Object?>{
              'tool_calls': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'tool-call-1',
                  'name': 'bash',
                  'arguments': '{"cmd":"pwd"}',
                },
              ],
            },
          ),
          AiSessionMessage.toolResult(
            id: 'tool-result-1',
            content: '/workspace',
            createdAt: DateTime.utc(2026, 3, 23, 6, 5, 1),
            metadata: const <String, Object?>{
              'tool_call_id': 'tool-call-1',
              'tool_name': 'bash',
            },
          ),
          AiSessionMessage.user(
            id: 'user-1',
            content: 'Continue',
            createdAt: DateTime.utc(2026, 3, 23, 6, 5, 2),
          ),
        ],
      ).messages,
      latestUserMessageId: 'user-1',
    );

    final toolTurn = prompt.messages.singleWhere(
      (item) => item.role == AiChatRole.tool,
    );
    final assistantToolCallTurn = prompt.messages.singleWhere(
      (item) => item.role == AiChatRole.assistant && item.toolCalls.isNotEmpty,
    );
    expect(toolTurn.toolCallId, 'tool-call-1');
    expect(assistantToolCallTurn.toolCalls.single.name, 'bash');
    expect(prompt.historyMessageCount, 2);
  });

  test(
    'AiPromptBuilder groups consecutive tool-call messages into one tool round',
    () {
      const builder = AiPromptBuilder();
      final prompt = builder.buildSessionPrompt(
        templateBundle: _templateBundle(),
        session: _session(
          messages: [
            AiSessionMessage.toolCall(
              id: 'tool-call-message-1',
              content: '**bash**\n\n```json\n{"cmd":"pwd"}\n```',
              createdAt: DateTime.utc(2026, 3, 23, 6, 6, 0),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-1',
                'tool_name': 'bash',
                'tool_arguments': '{"cmd":"pwd"}',
                'tool_calls': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'tool-call-1',
                    'name': 'bash',
                    'arguments': '{"cmd":"pwd"}',
                  },
                ],
              },
            ),
            AiSessionMessage.toolCall(
              id: 'tool-call-message-2',
              content: '**bash**\n\n```json\n{"cmd":"ls -la"}\n```',
              createdAt: DateTime.utc(2026, 3, 23, 6, 6, 1),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-2',
                'tool_name': 'bash',
                'tool_arguments': '{"cmd":"ls -la"}',
                'tool_calls': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'tool-call-2',
                    'name': 'bash',
                    'arguments': '{"cmd":"ls -la"}',
                  },
                ],
              },
            ),
            AiSessionMessage.toolResult(
              id: 'tool-result-1',
              content: '/workspace',
              createdAt: DateTime.utc(2026, 3, 23, 6, 6, 2),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-1',
                'tool_name': 'bash',
              },
            ),
            AiSessionMessage.toolResult(
              id: 'tool-result-2',
              content: 'README.md',
              createdAt: DateTime.utc(2026, 3, 23, 6, 6, 3),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-2',
                'tool_name': 'bash',
              },
            ),
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue',
              createdAt: DateTime.utc(2026, 3, 23, 6, 6, 4),
            ),
          ],
        ),
        model: _model(),
        runtimeContext: _runtimeContext(),
        memoryEntries: const [],
        sessionMessages: _session(
          messages: [
            AiSessionMessage.toolCall(
              id: 'tool-call-message-1',
              content: '**bash**\n\n```json\n{"cmd":"pwd"}\n```',
              createdAt: DateTime.utc(2026, 3, 23, 6, 6, 0),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-1',
                'tool_name': 'bash',
                'tool_arguments': '{"cmd":"pwd"}',
                'tool_calls': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'tool-call-1',
                    'name': 'bash',
                    'arguments': '{"cmd":"pwd"}',
                  },
                ],
              },
            ),
            AiSessionMessage.toolCall(
              id: 'tool-call-message-2',
              content: '**bash**\n\n```json\n{"cmd":"ls -la"}\n```',
              createdAt: DateTime.utc(2026, 3, 23, 6, 6, 1),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-2',
                'tool_name': 'bash',
                'tool_arguments': '{"cmd":"ls -la"}',
                'tool_calls': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'tool-call-2',
                    'name': 'bash',
                    'arguments': '{"cmd":"ls -la"}',
                  },
                ],
              },
            ),
            AiSessionMessage.toolResult(
              id: 'tool-result-1',
              content: '/workspace',
              createdAt: DateTime.utc(2026, 3, 23, 6, 6, 2),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-1',
                'tool_name': 'bash',
              },
            ),
            AiSessionMessage.toolResult(
              id: 'tool-result-2',
              content: 'README.md',
              createdAt: DateTime.utc(2026, 3, 23, 6, 6, 3),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-2',
                'tool_name': 'bash',
              },
            ),
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue',
              createdAt: DateTime.utc(2026, 3, 23, 6, 6, 4),
            ),
          ],
        ).messages,
        latestUserMessageId: 'user-1',
      );

      final assistantToolCallTurn = prompt.messages.singleWhere(
        (item) =>
            item.role == AiChatRole.assistant && item.toolCalls.isNotEmpty,
      );
      final toolTurns = prompt.messages
          .where((item) => item.role == AiChatRole.tool)
          .toList(growable: false);

      expect(assistantToolCallTurn.toolCalls, hasLength(2));
      expect(
        assistantToolCallTurn.toolCalls.map((item) => item.id).toList(),
        <String>['tool-call-1', 'tool-call-2'],
      );
      expect(toolTurns.map((item) => item.toolCallId).toList(), <String>[
        'tool-call-1',
        'tool-call-2',
      ]);
      expect(prompt.historyMessageCount, 3);
    },
  );

  test(
    'AiPromptBuilder does not inject leaked session marker into history',
    () {
      const builder = AiPromptBuilder();
      final prompt = builder.buildSessionPrompt(
        templateBundle: _templateBundle(),
        session: _session(
          messages: [
            AiSessionMessage.assistant(
              id: 'assistant-1',
              content: 'Historical answer',
              createdAt: DateTime.utc(2026, 3, 23, 6, 4, 0),
            ),
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue',
              createdAt: DateTime.utc(2026, 3, 23, 6, 5, 0),
            ),
          ],
        ),
        model: _model(),
        runtimeContext: _runtimeContext(),
        memoryEntries: const [],
        sessionMessages: _session(
          messages: [
            AiSessionMessage.assistant(
              id: 'assistant-1',
              content: 'Historical answer',
              createdAt: DateTime.utc(2026, 3, 23, 6, 4, 0),
            ),
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue',
              createdAt: DateTime.utc(2026, 3, 23, 6, 5, 0),
            ),
          ],
        ).messages,
        latestUserMessageId: 'user-1',
      );

      final historyTurn = prompt.messages.firstWhere(
        (item) =>
            item.role == AiChatRole.assistant &&
            item.toolCalls.isEmpty &&
            item.content == 'Historical answer',
      );
      expect(
        historyTurn.content,
        isNot(contains('[[5] Current Session Messages]')),
      );
    },
  );

  test(
    'AiPromptBuilder appends workspace instruction files to the system turn',
    () {
      const builder = AiPromptBuilder();
      final prompt = builder.buildSessionPrompt(
        templateBundle: _templateBundle(),
        session: _session(
          messages: [
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Review the repo rules.',
              createdAt: DateTime.utc(2026, 3, 23, 6, 7, 0),
            ),
          ],
        ),
        model: _model(),
        runtimeContext: _runtimeContext(
          workspaceInstructionDocuments: const <AiWorkspaceInstructionDocument>[
            AiWorkspaceInstructionDocument(
              path: '/workspace/openhand/AGENTS.md',
              name: 'AGENTS.md',
              content: 'Always read the workspace rules first.',
            ),
          ],
        ),
        memoryEntries: const [],
        sessionMessages: _session(
          messages: [
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Review the repo rules.',
              createdAt: DateTime.utc(2026, 3, 23, 6, 7, 0),
            ),
          ],
        ).messages,
        latestUserMessageId: 'user-1',
      );

      expect(
        prompt.messages.first.content,
        contains('# Workspace Instructions'),
      );
      expect(
        prompt.messages.first.content,
        contains('Always read the workspace rules first.'),
      );
      expect(prompt.metadata['workspace_instruction_document_count'], 1);
    },
  );

  test(
    'AiPromptBuilder appends runtime environment and repository snapshot to the system turn',
    () {
      const builder = AiPromptBuilder();
      final prompt = builder.buildSessionPrompt(
        templateBundle: _templateBundle(),
        session: _session(
          messages: [
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Inspect the repository state.',
              createdAt: DateTime.utc(2026, 3, 23, 6, 7, 30),
            ),
          ],
        ),
        model: _model(),
        runtimeContext: _runtimeContext(
          platformName: 'macos',
          workingDirectory: '/workspace/openhand',
          todayLocalDate: '2026-03-23',
          timeZoneName: 'Asia/Shanghai',
          repositorySnapshot: const AiRepositorySnapshot(
            workingDirectory: '/workspace/openhand',
            isGitRepository: true,
            repositoryRootPath: '/workspace/openhand',
            currentBranch: 'feature/claude-migration',
            mainBranch: 'main',
            statusSnapshot: '## feature/claude-migration\n M lib/app.dart',
            recentCommits: <String>[
              'abc1234 add runtime snapshot',
              'def5678 tighten tool contracts',
            ],
            capturedAtIso8601: '2026-03-23T06:07:30.000Z',
          ),
        ),
        memoryEntries: const [],
        sessionMessages: _session(
          messages: [
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Inspect the repository state.',
              createdAt: DateTime.utc(2026, 3, 23, 6, 7, 30),
            ),
          ],
        ).messages,
        latestUserMessageId: 'user-1',
      );

      expect(
        prompt.messages.first.content,
        contains('# Runtime Environment Snapshot'),
      );
      expect(
        prompt.messages.first.content,
        contains('Current branch: feature/claude-migration'),
      );
      expect(prompt.messages.first.content, contains('Main branch: main'));
      expect(
        prompt.messages.first.content,
        contains('abc1234 add runtime snapshot'),
      );
      expect(prompt.metadata['today_local_date'], '2026-03-23');
      expect(
        prompt.metadata['repository_snapshot'],
        isA<Map<String, Object?>>(),
      );
    },
  );

  test(
    'AiPromptBuilder reuses the first repository snapshot from session metadata',
    () {
      const builder = AiPromptBuilder();
      final prompt = builder.buildSessionPrompt(
        templateBundle: _templateBundle(),
        session: _session(
          messages: [
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue.',
              createdAt: DateTime.utc(2026, 3, 23, 6, 12, 0),
            ),
          ],
          lastPromptMetadata: const <String, Object?>{
            'repository_snapshot': <String, Object?>{
              'working_directory': '/workspace/openhand',
              'is_git_repository': true,
              'repository_root_path': '/workspace/openhand',
              'current_branch': 'initial-branch',
              'main_branch': 'main',
              'status_snapshot': '## initial-branch',
              'recent_commits': <String>['1111111 initial snapshot'],
              'captured_at': '2026-03-23T06:00:00.000Z',
            },
          },
        ),
        model: _model(),
        runtimeContext: _runtimeContext(
          platformName: 'macos',
          workingDirectory: '/workspace/openhand',
          todayLocalDate: '2026-03-23',
          timeZoneName: 'Asia/Shanghai',
          repositorySnapshot: const AiRepositorySnapshot(
            workingDirectory: '/workspace/openhand',
            isGitRepository: true,
            repositoryRootPath: '/workspace/openhand',
            currentBranch: 'changed-branch',
            mainBranch: 'main',
            statusSnapshot: '## changed-branch',
            recentCommits: <String>['2222222 changed snapshot'],
            capturedAtIso8601: '2026-03-23T06:12:00.000Z',
          ),
        ),
        memoryEntries: const [],
        sessionMessages: _session(
          messages: [
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue.',
              createdAt: DateTime.utc(2026, 3, 23, 6, 12, 0),
            ),
          ],
          lastPromptMetadata: const <String, Object?>{
            'repository_snapshot': <String, Object?>{
              'working_directory': '/workspace/openhand',
              'is_git_repository': true,
              'repository_root_path': '/workspace/openhand',
              'current_branch': 'initial-branch',
              'main_branch': 'main',
              'status_snapshot': '## initial-branch',
              'recent_commits': <String>['1111111 initial snapshot'],
              'captured_at': '2026-03-23T06:00:00.000Z',
            },
          },
        ).messages,
        latestUserMessageId: 'user-1',
      );

      expect(
        prompt.messages.first.content,
        contains('Current branch: initial-branch'),
      );
      expect(prompt.messages.first.content, isNot(contains('changed-branch')));
    },
  );

  test(
    'AiPromptBuilder renders command approval policy in runtime snapshot',
    () {
      const builder = AiPromptBuilder();
      final prompt = builder.buildSessionPrompt(
        templateBundle: _templateBundle(),
        session: _session(
          messages: [
            AiSessionMessage.user(
              id: 'user-allow',
              content: 'Continue.',
              createdAt: DateTime.utc(2026, 3, 23, 6, 15, 0),
            ),
          ],
        ),
        model: _model(),
        runtimeContext: _runtimeContext(
          writeCommandConfirmationEnabled: true,
          allowCommandRules: const <AiAllowCommandRule>[
            AiAllowCommandRule(
              id: 'allow-1',
              pattern: 'flutter test *',
              matchMode: AiDenyCommandMatchMode.simple,
              note: 'trusted tests',
            ),
          ],
        ),
        memoryEntries: const [],
        sessionMessages: _session(
          messages: [
            AiSessionMessage.user(
              id: 'user-allow',
              content: 'Continue.',
              createdAt: DateTime.utc(2026, 3, 23, 6, 15, 0),
            ),
          ],
        ).messages,
        latestUserMessageId: 'user-allow',
      );

      expect(
        prompt.messages.first.content,
        contains('Write command confirmation required: Yes'),
      );
      expect(
        prompt.messages.first.content,
        contains('- simple: flutter test * (trusted tests)'),
      );
      expect(prompt.metadata['allow_command_rule_count'], 1);
      expect(prompt.metadata['write_command_confirmation_enabled'], isTrue);
    },
  );

  test('AiPromptBuilder adds a TodoWrite reminder for non-trivial work', () {
    const builder = AiPromptBuilder();
    final prompt = builder.buildSessionPrompt(
      templateBundle: _templateBundle(),
      session: _session(
        messages: [
          AiSessionMessage.user(
            id: 'user-todo',
            content:
                'Implement the migration, update the prompt builder, then run the focused tests and verify the results.',
            createdAt: DateTime.utc(2026, 3, 23, 6, 16, 0),
          ),
        ],
      ),
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: const [],
      sessionMessages: _session(
        messages: [
          AiSessionMessage.user(
            id: 'user-todo',
            content:
                'Implement the migration, update the prompt builder, then run the focused tests and verify the results.',
            createdAt: DateTime.utc(2026, 3, 23, 6, 16, 0),
          ),
        ],
      ).messages,
      latestUserMessageId: 'user-todo',
    );

    expect(
      prompt.messages.any(
        (item) =>
            item.role == AiChatRole.system &&
            item.content.contains('Use TodoWrite now'),
      ),
      isTrue,
    );
    expect(prompt.metadata['todo_write_recommended'], isTrue);
    expect(
      '${prompt.metadata['todo_write_reason'] ?? ''}',
      contains('Use TodoWrite now'),
    );
  });

  test('AiPromptBuilder skips TodoWrite reminders for product questions', () {
    const builder = AiPromptBuilder();
    final prompt = builder.buildSessionPrompt(
      templateBundle: _templateBundle(),
      session: _session(
        messages: [
          AiSessionMessage.user(
            id: 'user-question',
            content: 'How do Claude Code hooks work?',
            createdAt: DateTime.utc(2026, 3, 23, 6, 17, 0),
          ),
        ],
      ),
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: const [],
      sessionMessages: _session(
        messages: [
          AiSessionMessage.user(
            id: 'user-question',
            content: 'How do Claude Code hooks work?',
            createdAt: DateTime.utc(2026, 3, 23, 6, 17, 0),
          ),
        ],
      ).messages,
      latestUserMessageId: 'user-question',
    );

    expect(prompt.metadata['todo_write_recommended'], isFalse);
    expect(
      prompt.messages.any(
        (item) =>
            item.role == AiChatRole.system &&
            item.content.contains('Use TodoWrite now'),
      ),
      isFalse,
    );
  });

  test('AiPromptBuilder promotes system-reminder tags into system turns', () {
    const builder = AiPromptBuilder();
    final prompt = builder.buildSessionPrompt(
      templateBundle: _templateBundle(),
      session: _session(
        messages: [
          AiSessionMessage.user(
            id: 'user-1',
            content:
                '<system-reminder>Hook reminder</system-reminder>\nContinue implementation.',
            createdAt: DateTime.utc(2026, 3, 23, 6, 8, 0),
          ),
        ],
      ),
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: const [],
      sessionMessages: _session(
        messages: [
          AiSessionMessage.user(
            id: 'user-1',
            content:
                '<system-reminder>Hook reminder</system-reminder>\nContinue implementation.',
            createdAt: DateTime.utc(2026, 3, 23, 6, 8, 0),
          ),
        ],
      ).messages,
      latestUserMessageId: 'user-1',
    );

    expect(
      prompt.messages.any(
        (item) =>
            item.role == AiChatRole.system &&
            item.content.contains('Hook reminder'),
      ),
      isTrue,
    );
    final latestUserTurn = prompt.messages.last;
    expect(latestUserTurn.role, AiChatRole.user);
    expect(latestUserTurn.content, contains('Continue implementation.'));
    expect(latestUserTurn.content, isNot(contains('<system-reminder>')));
    expect(prompt.systemMessageCount, greaterThan(5));
  });

  test(
    'AiPromptBuilder keeps tool turns when tool results include system reminders',
    () {
      const builder = AiPromptBuilder();
      final prompt = builder.buildSessionPrompt(
        templateBundle: _templateBundle(),
        session: _session(
          messages: [
            AiSessionMessage.toolCall(
              id: 'tool-call-message',
              content: '',
              createdAt: DateTime.utc(2026, 3, 23, 6, 9, 0),
              metadata: const <String, Object?>{
                'tool_calls': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'tool-call-1',
                    'name': 'Read',
                    'arguments': '{"file_path":"README.md"}',
                  },
                ],
              },
            ),
            AiSessionMessage.toolResult(
              id: 'tool-result-1',
              content:
                  '<system-reminder>Reminder after tool</system-reminder>\nREADME body',
              createdAt: DateTime.utc(2026, 3, 23, 6, 9, 1),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-1',
                'tool_name': 'Read',
              },
            ),
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue',
              createdAt: DateTime.utc(2026, 3, 23, 6, 9, 2),
            ),
          ],
        ),
        model: _model(),
        runtimeContext: _runtimeContext(),
        memoryEntries: const [],
        sessionMessages: _session(
          messages: [
            AiSessionMessage.toolCall(
              id: 'tool-call-message',
              content: '',
              createdAt: DateTime.utc(2026, 3, 23, 6, 9, 0),
              metadata: const <String, Object?>{
                'tool_calls': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'tool-call-1',
                    'name': 'Read',
                    'arguments': '{"file_path":"README.md"}',
                  },
                ],
              },
            ),
            AiSessionMessage.toolResult(
              id: 'tool-result-1',
              content:
                  '<system-reminder>Reminder after tool</system-reminder>\nREADME body',
              createdAt: DateTime.utc(2026, 3, 23, 6, 9, 1),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-1',
                'tool_name': 'Read',
              },
            ),
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue',
              createdAt: DateTime.utc(2026, 3, 23, 6, 9, 2),
            ),
          ],
        ).messages,
        latestUserMessageId: 'user-1',
      );

      expect(
        prompt.messages.any(
          (item) =>
              item.role == AiChatRole.system &&
              item.content.contains('Reminder after tool'),
        ),
        isTrue,
      );
      expect(
        prompt.messages.any(
          (item) =>
              item.role == AiChatRole.tool &&
              item.toolCallId == 'tool-call-1' &&
              item.content.contains('README body'),
        ),
        isTrue,
      );
    },
  );

  test(
    'AiPromptBuilder injects hidden user-prompt hook feedback into the user turn',
    () {
      const builder = AiPromptBuilder();
      final prompt = builder.buildSessionPrompt(
        templateBundle: _templateBundle(),
        session: _session(
          messages: [
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue implementation.',
              createdAt: DateTime.utc(2026, 3, 23, 6, 10, 0),
              metadata: const <String, Object?>{
                aiUserPromptHookFeedbackMetadataKey: <String>[
                  'Remember to follow the repository policy.',
                ],
              },
            ),
          ],
        ),
        model: _model(),
        runtimeContext: _runtimeContext(),
        memoryEntries: const [],
        sessionMessages: _session(
          messages: [
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue implementation.',
              createdAt: DateTime.utc(2026, 3, 23, 6, 10, 0),
              metadata: const <String, Object?>{
                aiUserPromptHookFeedbackMetadataKey: <String>[
                  'Remember to follow the repository policy.',
                ],
              },
            ),
          ],
        ).messages,
        latestUserMessageId: 'user-1',
      );

      final latestUserTurn = prompt.messages.last;
      expect(latestUserTurn.role, AiChatRole.user);
      expect(latestUserTurn.content, contains('<user-prompt-submit-hook>'));
      expect(
        latestUserTurn.content,
        contains('Remember to follow the repository policy.'),
      );
    },
  );

  test(
    'AiPromptBuilder promotes hidden hook reminders from metadata into system turns',
    () {
      const builder = AiPromptBuilder();
      final prompt = builder.buildSessionPrompt(
        templateBundle: _templateBundle(),
        session: _session(
          messages: [
            AiSessionMessage.toolCall(
              id: 'tool-call-message',
              content: '',
              createdAt: DateTime.utc(2026, 3, 23, 6, 11, 0),
              metadata: const <String, Object?>{
                'tool_calls': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'tool-call-1',
                    'name': 'Read',
                    'arguments': '{"file_path":"README.md"}',
                  },
                ],
              },
            ),
            AiSessionMessage.toolResult(
              id: 'tool-result-1',
              content: 'README body',
              createdAt: DateTime.utc(2026, 3, 23, 6, 11, 1),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-1',
                'tool_name': 'Read',
                aiHookSystemRemindersMetadataKey: <String>[
                  'Formatter hook already ran.',
                ],
              },
            ),
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue',
              createdAt: DateTime.utc(2026, 3, 23, 6, 11, 2),
            ),
          ],
        ),
        model: _model(),
        runtimeContext: _runtimeContext(),
        memoryEntries: const [],
        sessionMessages: _session(
          messages: [
            AiSessionMessage.toolCall(
              id: 'tool-call-message',
              content: '',
              createdAt: DateTime.utc(2026, 3, 23, 6, 11, 0),
              metadata: const <String, Object?>{
                'tool_calls': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'tool-call-1',
                    'name': 'Read',
                    'arguments': '{"file_path":"README.md"}',
                  },
                ],
              },
            ),
            AiSessionMessage.toolResult(
              id: 'tool-result-1',
              content: 'README body',
              createdAt: DateTime.utc(2026, 3, 23, 6, 11, 1),
              metadata: const <String, Object?>{
                'tool_call_id': 'tool-call-1',
                'tool_name': 'Read',
                aiHookSystemRemindersMetadataKey: <String>[
                  'Formatter hook already ran.',
                ],
              },
            ),
            AiSessionMessage.user(
              id: 'user-1',
              content: 'Continue',
              createdAt: DateTime.utc(2026, 3, 23, 6, 11, 2),
            ),
          ],
        ).messages,
        latestUserMessageId: 'user-1',
      );

      expect(
        prompt.messages.any(
          (item) =>
              item.role == AiChatRole.system &&
              item.content.contains('Formatter hook already ran.'),
        ),
        isTrue,
      );
    },
  );
}

AiPromptTemplateBundle _templateBundle() {
  final repository = AiPromptTemplateRepository();
  return AiPromptTemplateBundle(
    template: repository.resolveTemplate('default'),
    systemInstructions: 'System',
    developerInstructions: 'Developer',
    compressionSummaryInstructions: 'Compression',
  );
}

AiSession _session({
  required List<AiSessionMessage> messages,
  Map<String, Object?> lastPromptMetadata = const <String, Object?>{},
}) {
  return AiSession(
    id: 'session-1',
    title: 'Prompt Builder Session',
    templateId: 'default',
    templateName: 'Default Assistant',
    templateIconName: 'auto_awesome_rounded',
    templateInternalVersion: '1.0.0',
    createdAt: DateTime.utc(2026, 3, 23, 6, 0, 0),
    updatedAt: DateTime.utc(2026, 3, 23, 6, 5, 0),
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'en-US',
      platform: 'macos',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '/workspace/openhand',
      homeDirectory: '/Users/example',
      settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
      skillsStoragePath: '/Users/example/.openhand/skills',
      mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
      userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
      sessionsDirectoryPath: '/Users/example/.openhand/sessions',
      compressionThresholdChars: 12000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
    lastPromptMetadata: lastPromptMetadata,
  );
}

AiSessionRuntimeContext _runtimeContext({
  List<AiWorkspaceInstructionDocument> workspaceInstructionDocuments =
      const <AiWorkspaceInstructionDocument>[],
  List<AiAllowCommandRule> allowCommandRules = const <AiAllowCommandRule>[],
  bool writeCommandConfirmationEnabled = true,
  String platformName = '',
  String workingDirectory = '',
  String todayLocalDate = '',
  String timeZoneName = '',
  AiRepositorySnapshot? repositorySnapshot,
}) {
  return AiSessionRuntimeContext(
    localeTag: 'en-US',
    appVersion: '0.1.0',
    appBuildNumber: '1',
    settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
    skillsStoragePath: '/Users/example/.openhand/skills',
    mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
    userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
    compressionThresholdChars: 12000,
    memoryEnabled: true,
    memoryEntries: [],
    writeCommandConfirmationEnabled: writeCommandConfirmationEnabled,
    platformName: platformName,
    workingDirectory: workingDirectory,
    todayLocalDate: todayLocalDate,
    timeZoneName: timeZoneName,
    repositorySnapshot: repositorySnapshot,
    allowCommandRules: allowCommandRules,
    workspaceInstructionDocuments: workspaceInstructionDocuments,
  );
}

AiModelConfig _model() {
  return const AiModelConfig(
    id: 'model-1',
    baseUrl: 'https://api.example.com',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'gpt-test',
    protocolType: AiProtocolType.openai,
  );
}

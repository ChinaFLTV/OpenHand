import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_sections.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  group('AiPromptBuilder compression prompt', () {
    test('preserves effective permission and plan gate state', () {
      final now = DateTime.utc(2026, 6, 19, 8);
      final session = AiSession(
        id: 'session-1',
        title: 'Planning session',
        templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
        templateName: '编程专家',
        templateIconName: 'code_rounded',
        templateInternalVersion: 'test',
        createdAt: now,
        updatedAt: now,
        messages: <AiSessionMessage>[
          AiSessionMessage.user(
            id: 'u1',
            content: 'Plan the change',
            createdAt: now,
          ),
        ],
        environment: _testEnvironment,
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
        todoItems: const <AiSessionTodoItem>[
          AiSessionTodoItem(
            id: '1',
            content: 'Inspect code',
            status: 'in_progress',
          ),
        ],
        mode: AiSessionMode.plan,
        pendingPlan: '1. Inspect\n2. Change\n3. Verify',
        pendingPlanAllowedPrompts: const <AiSessionPlanAllowedPrompt>[
          AiSessionPlanAllowedPrompt(
            tool: 'Bash',
            prompt: 'run targeted tests',
          ),
        ],
        planHistory: <AiSessionPlanRecord>[
          AiSessionPlanRecord(
            id: 'plan-1',
            createdAt: now,
            updatedAt: now,
            status: AiSessionPlanStatus.pendingApproval,
            plan: '1. Inspect\n2. Change\n3. Verify',
            allowedPrompts: const <AiSessionPlanAllowedPrompt>[
              AiSessionPlanAllowedPrompt(
                tool: 'Bash',
                prompt: 'run targeted tests',
              ),
            ],
          ),
        ],
        fullAccessPermission: true,
      );

      final turns = const AiPromptBuilder().buildCompressionPrompt(
        templateBundle: _testBundle,
        template: _testTemplate,
        session: session,
        runtimeContext: _testRuntimeContext,
        messagesToCompress: session.messages,
        previousCompressionPoint: null,
      );

      final payload = _compressionPayload(turns.last.content);
      final sessionState = payload['session_state'] as Map<String, Object?>;
      expect(sessionState['mode'], 'plan');
      expect(sessionState['full_access_permission'], isTrue);
      expect(sessionState['write_command_confirmation_enabled'], isTrue);
      expect(sessionState['write_command_confirmation_required'], isFalse);
      expect(sessionState['pending_plan'], '1. Inspect\n2. Change\n3. Verify');
      expect(
        sessionState['pending_plan_allowed_prompts'],
        <Map<String, String>>[
          <String, String>{'tool': 'Bash', 'prompt': 'run targeted tests'},
        ],
      );
      final recentPlanRecords =
          sessionState['recent_plan_records'] as List<Object?>;
      final recentPlanRecord = Map<String, Object?>.from(
        recentPlanRecords.single as Map,
      );
      expect(recentPlanRecord['allowed_prompts'], <Map<String, String>>[
        <String, String>{'tool': 'Bash', 'prompt': 'run targeted tests'},
      ]);

      final planMode = sessionState['plan_mode'] as Map<String, Object?>;
      expect(planMode['has_incomplete_todo'], isTrue);
      expect(planMode['exit_plan_mode_available'], isTrue);
      expect(
        planMode['planning_tool_names'],
        containsAll(<String>['Lsp', 'CodebaseSearch']),
      );
      expect(
        planMode['tool_gate_reason'],
        'plan_mode_planning_with_exit_allowed',
      );
    });

    test('preserves write confirmation decision in compressed transcript', () {
      final now = DateTime.utc(2026, 6, 19, 8);
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'u1',
          content: 'Run the write command',
          createdAt: now,
        ),
        AiSessionMessage.toolResult(
          id: 't1',
          content:
              'status: rejected\n'
              'write_confirmation_decision: dismissed\n'
              'write_confirmation_dismissed: true',
          createdAt: now.add(const Duration(seconds: 1)),
          metadata: const <String, Object?>{
            'tool_name': 'Bash',
            'tool_execution_status': 'rejected',
            'tool_execution_is_write_command': true,
            'file_mutation_kind': 'bash_write',
            'tool_execution_working_directory': '/tmp/project',
            'tool_execution_write_analysis_reason': 'mutating command touch',
            'tool_execution_result':
                'status: rejected\n'
                'write_confirmation_decision: dismissed\n'
                'write_confirmation_dismissed: true',
            'write_confirmation_decision': 'dismissed',
            'write_confirmation_dismissed': true,
          },
        ),
      ];
      final session = AiSession(
        id: 'session-1',
        title: 'Write confirmation session',
        templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
        templateName: '编程专家',
        templateIconName: 'code_rounded',
        templateInternalVersion: 'test',
        createdAt: now,
        updatedAt: now,
        messages: messages,
        environment: _testEnvironment,
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
      );

      final turns = const AiPromptBuilder().buildCompressionPrompt(
        templateBundle: _testBundle,
        template: _testTemplate,
        session: session,
        runtimeContext: _testRuntimeContext,
        messagesToCompress: messages,
        previousCompressionPoint: null,
      );

      final content = turns.last.content;
      expect(content, contains('[write_result] Bash'));
      expect(content, contains('status: rejected'));
      expect(content, contains('write_confirmation_decision: dismissed'));
      expect(content, contains('write_confirmation_dismissed: true'));
      expect(content, contains('mutation: bash_write'));
      expect(content, contains('reason: mutating command touch'));
    });

    test('preserves plan gate blocks in compressed transcript', () {
      final now = DateTime.utc(2026, 6, 19, 8);
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'u1',
          content: 'Continue after planning',
          createdAt: now,
        ),
        AiSessionMessage.toolResult(
          id: 't1',
          content: 'Error: plan approval must use the dedicated tool.',
          createdAt: now.add(const Duration(seconds: 1)),
          metadata: const <String, Object?>{
            'tool_name': 'AskUserChoice',
            'status': 'invalid_arguments',
            'ask_user_choice_blocked_plan_approval': true,
            'ask_user_choice_block_reason':
                'plan_approval_requires_exit_plan_mode',
            'plan_approval_tool': 'ExitPlanMode',
            'plan_mode_active': true,
            'awaiting_plan_approval': false,
            'plan_mode_execution_approved_for_send': false,
          },
        ),
        AiSessionMessage.toolResult(
          id: 't2',
          content: 'Error: verify subagent is blocked until plan approval.',
          createdAt: now.add(const Duration(seconds: 2)),
          metadata: const <String, Object?>{
            'tool_name': 'Task',
            'status': 'invalid_arguments',
            'task_blocked_plan_mode_subagent': true,
            'task_block_reason': 'plan_mode_execution_unapproved',
            'subagent_type': 'verify',
            'allowed_subagent_types_before_approval': <String>[
              'research',
              'summarize',
              'advice',
            ],
            'plan_mode_active': true,
            'plan_mode_execution_approved_for_send': false,
          },
        ),
        AiSessionMessage.toolResult(
          id: 't3',
          content: 'Unsupported tool: Patch',
          createdAt: now.add(const Duration(seconds: 3)),
          metadata: const <String, Object?>{
            'tool_name': 'Patch',
            'status': 'unsupported_tool',
            'unsupported_tool_name': 'Patch',
            'tool_catalog_empty': true,
          },
        ),
      ];
      final session = AiSession(
        id: 'session-1',
        title: 'Plan gate compression session',
        templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
        templateName: '编程专家',
        templateIconName: 'code_rounded',
        templateInternalVersion: 'test',
        createdAt: now,
        updatedAt: now,
        messages: messages,
        environment: _testEnvironment,
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
      );

      final turns = const AiPromptBuilder().buildCompressionPrompt(
        templateBundle: _testBundle,
        template: _testTemplate,
        session: session,
        runtimeContext: _testRuntimeContext,
        messagesToCompress: messages,
        previousCompressionPoint: null,
      );

      final content = turns.last.content;
      expect(
        content,
        contains('plan_gate_block: ask_user_choice_plan_approval'),
      );
      expect(
        content,
        contains(
          'ask_user_choice_block_reason: '
          'plan_approval_requires_exit_plan_mode',
        ),
      );
      expect(content, contains('plan_approval_tool: ExitPlanMode'));
      expect(
        content,
        contains('plan_gate_block: task_subagent_execution_unapproved'),
      );
      expect(
        content,
        contains('task_block_reason: plan_mode_execution_unapproved'),
      );
      expect(content, contains('subagent_type: verify'));
      expect(
        content,
        contains(
          'allowed_subagent_types_before_approval: research, summarize, advice',
        ),
      );
      expect(content, contains('unsupported_tool_name: Patch'));
      expect(content, contains('tool_catalog_empty: true'));
      expect(content, contains('plan_mode_active: true'));
      expect(content, contains('plan_mode_execution_approved_for_send: false'));
    });

    test('preserves tool output budget truncation in compressed transcript', () {
      final now = DateTime.utc(2026, 6, 19, 8);
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'u1',
          content: 'Summarize the large command output',
          createdAt: now,
        ),
        AiSessionMessage.toolResult(
          id: 't1',
          content:
              'Short visible prefix from a much larger tool result.\n'
              '${List<String>.filled(5000, 'x').join()}',
          createdAt: now.add(const Duration(seconds: 1)),
          metadata: const <String, Object?>{
            'tool_name': 'Bash',
            'status': 'success',
            'tool_output_truncated': true,
            'tool_output_original_length': 120000,
            'tool_output_budget_chars': 20000,
            'tool_output_included_chars': 19800,
            'tool_output_omitted_chars': 100200,
            'tool_output_truncation_strategy': 'head_tail',
            'tool_output_full_content_available': true,
            'tool_output_recovery_hint': 'read_persisted_output',
            'tool_output_persisted': true,
            'tool_output_persisted_path':
                '/tmp/openhand/session-1/tool-results/call-1.txt',
            'tool_output_persisted_chars': 120000,
            'tool_output_persistence_format': 'text',
          },
        ),
      ];
      final session = AiSession(
        id: 'session-1',
        title: 'Tool truncation compression session',
        templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
        templateName: '编程专家',
        templateIconName: 'code_rounded',
        templateInternalVersion: 'test',
        createdAt: now,
        updatedAt: now,
        messages: messages,
        environment: _testEnvironment,
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
      );

      final turns = const AiPromptBuilder().buildCompressionPrompt(
        templateBundle: _testBundle,
        template: _testTemplate,
        session: session,
        runtimeContext: _testRuntimeContext,
        messagesToCompress: messages,
        previousCompressionPoint: null,
      );

      final content = turns.last.content;
      expect(content, contains('tool_output_truncated: true'));
      expect(content, contains('tool_output_original_length: 120000'));
      expect(content, contains('tool_output_budget_chars: 20000'));
      expect(content, contains('tool_output_included_chars: 19800'));
      expect(content, contains('tool_output_omitted_chars: 100200'));
      expect(content, contains('tool_output_truncation_strategy: head_tail'));
      expect(content, contains('tool_output_full_content_available: true'));
      expect(content, contains('tool_output_persisted: true'));
      expect(
        content,
        contains(
          'tool_output_persisted_path: /tmp/openhand/session-1/tool-results/call-1.txt',
        ),
      );
      expect(content, contains('tool_output_persisted_chars: 120000'));
      expect(content, contains('tool_output_persistence_format: text'));
      expect(
        content,
        contains('tool_output_recovery_hint: read_persisted_output'),
      );
      expect(
        content,
        contains(
          'note: Exact omitted output is available at tool_output_persisted_path.',
        ),
      );
    });

    test(
      'preserves plan approval allowed prompts in compressed transcript',
      () {
        final now = DateTime.utc(2026, 6, 19, 8);
        final messages = <AiSessionMessage>[
          AiSessionMessage.user(
            id: 'u1',
            content: 'Prepare an implementation plan',
            createdAt: now,
          ),
          AiSessionMessage.toolResult(
            id: 't1',
            content: 'Plan captured.',
            createdAt: now.add(const Duration(seconds: 1)),
            metadata: const <String, Object?>{
              'tool_name': 'ExitPlanMode',
              'status': 'success',
              'plan_mode_awaiting_approval': true,
              'pending_plan': '1. Patch behavior.\n2. Run verification.',
              'plan_mode_allowed_prompt_count': 2,
              'plan_mode_allowed_prompts': <Map<String, String>>[
                <String, String>{
                  'tool': 'Bash',
                  'prompt': 'run targeted tests',
                },
                <String, String>{'tool': 'Bash', 'prompt': 'build web assets'},
              ],
            },
          ),
        ];
        final session = AiSession(
          id: 'session-1',
          title: 'Plan approval allowed prompt session',
          templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
          templateName: '编程专家',
          templateIconName: 'code_rounded',
          templateInternalVersion: 'test',
          createdAt: now,
          updatedAt: now,
          messages: messages,
          environment: _testEnvironment,
          statistics: const AiSessionStatistics.initial(),
          recentErrors: const <AiSessionErrorRecord>[],
        );

        final turns = const AiPromptBuilder().buildCompressionPrompt(
          templateBundle: _testBundle,
          template: _testTemplate,
          session: session,
          runtimeContext: _testRuntimeContext,
          messagesToCompress: messages,
          previousCompressionPoint: null,
        );

        final content = turns.last.content;
        expect(content, contains('plan_mode_awaiting_approval: true'));
        expect(content, contains('plan_mode_allowed_prompt_count: 2'));
        expect(
          content,
          contains('plan_mode_allowed_prompt: Bash: run targeted tests'),
        );
        expect(
          content,
          contains('plan_mode_allowed_prompt: Bash: build web assets'),
        );
      },
    );

    test(
      'surfaces write confirmation decision in post-compact focus context',
      () {
        final now = DateTime.utc(2026, 6, 19, 8);
        final messages = <AiSessionMessage>[
          AiSessionMessage.toolResult(
            id: 't1',
            content:
                'status: rejected\n'
                'write_confirmation_decision: dismissed\n'
                'write_confirmation_dismissed: true',
            createdAt: now,
            metadata: const <String, Object?>{
              'tool_name': 'Bash',
              'status': 'rejected',
              'command': 'touch /tmp/openhand-focus-test',
              'tool_execution_is_write_command': true,
              'write_confirmation_decision': 'dismissed',
              'write_confirmation_dismissed': true,
            },
          ),
          AiSessionMessage.compressionPoint(
            id: 'c1',
            content: 'Checkpoint after rejected write confirmation.',
            createdAt: now.add(const Duration(seconds: 1)),
            metadata: const <String, Object?>{},
          ),
          AiSessionMessage.user(
            id: 'u1',
            content: 'What happened before compaction?',
            createdAt: now.add(const Duration(seconds: 2)),
          ),
        ];
        final session = AiSession(
          id: 'session-1',
          title: 'Focus context session',
          templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
          templateName: '编程专家',
          templateIconName: 'code_rounded',
          templateInternalVersion: 'test',
          createdAt: now,
          updatedAt: now,
          messages: messages,
          environment: _testEnvironment,
          statistics: const AiSessionStatistics.initial(),
          recentErrors: const <AiSessionErrorRecord>[],
        );

        final result = const AiPromptBuilder().buildSessionPrompt(
          templateBundle: _testBundle,
          session: session,
          model: _testModel,
          runtimeContext: _testRuntimeContext,
          memoryEntries: const <Never>[],
          sessionMessages: messages,
          latestUserMessageId: 'u1',
        );
        final focusContext = result.messages
            .map((turn) => turn.content)
            .firstWhere(
              (content) =>
                  content.startsWith(AiPromptSectionHeaders.focusContext),
            );

        expect(focusContext, contains('Bash · status=rejected'));
        expect(focusContext, contains('write_confirmation=dismissed'));
        expect(focusContext, contains('cmd=touch /tmp/openhand-focus-test'));
      },
    );

    test('surfaces plan gate blocks in post-compact focus context', () {
      final now = DateTime.utc(2026, 6, 19, 8);
      final messages = <AiSessionMessage>[
        AiSessionMessage.toolResult(
          id: 't1',
          content: 'Error: plan approval must use the dedicated tool.',
          createdAt: now,
          metadata: const <String, Object?>{
            'tool_name': 'AskUserChoice',
            'status': 'invalid_arguments',
            'ask_user_choice_blocked_plan_approval': true,
            'ask_user_choice_block_reason':
                'plan_approval_requires_exit_plan_mode',
            'plan_approval_tool': 'ExitPlanMode',
            'plan_mode_active': true,
            'awaiting_plan_approval': false,
            'plan_mode_execution_approved_for_send': false,
          },
        ),
        AiSessionMessage.toolResult(
          id: 't2',
          content: 'Error: verify subagent is blocked until plan approval.',
          createdAt: now.add(const Duration(seconds: 1)),
          metadata: const <String, Object?>{
            'tool_name': 'Task',
            'status': 'invalid_arguments',
            'task_blocked_plan_mode_subagent': true,
            'task_block_reason': 'plan_mode_execution_unapproved',
            'subagent_type': 'verify',
            'allowed_subagent_types_before_approval': <String>[
              'research',
              'summarize',
              'advice',
            ],
            'plan_mode_active': true,
            'plan_mode_execution_approved_for_send': false,
          },
        ),
        AiSessionMessage.toolResult(
          id: 't3',
          content: 'Unsupported tool: Patch',
          createdAt: now.add(const Duration(seconds: 2)),
          metadata: const <String, Object?>{
            'tool_name': 'Patch',
            'status': 'unsupported_tool',
            'unsupported_tool_name': 'Patch',
            'tool_catalog_empty': true,
          },
        ),
        AiSessionMessage.compressionPoint(
          id: 'c1',
          content: 'Checkpoint after plan gate blocks.',
          createdAt: now.add(const Duration(seconds: 3)),
          metadata: const <String, Object?>{},
        ),
        AiSessionMessage.user(
          id: 'u1',
          content: 'What happened before compaction?',
          createdAt: now.add(const Duration(seconds: 4)),
        ),
      ];
      final session = AiSession(
        id: 'session-1',
        title: 'Plan gate focus context session',
        templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
        templateName: '编程专家',
        templateIconName: 'code_rounded',
        templateInternalVersion: 'test',
        createdAt: now,
        updatedAt: now,
        messages: messages,
        environment: _testEnvironment,
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
      );

      final result = const AiPromptBuilder().buildSessionPrompt(
        templateBundle: _testBundle,
        session: session,
        model: _testModel,
        runtimeContext: _testRuntimeContext,
        memoryEntries: const <Never>[],
        sessionMessages: messages,
        latestUserMessageId: 'u1',
      );
      final focusContext = result.messages
          .map((turn) => turn.content)
          .firstWhere(
            (content) =>
                content.startsWith(AiPromptSectionHeaders.focusContext),
          );

      expect(
        focusContext,
        contains('AskUserChoice · status=invalid_arguments'),
      );
      expect(focusContext, contains('plan_gate=ask_choice_requires_exit'));
      expect(focusContext, contains('Task · status=invalid_arguments'));
      expect(focusContext, contains('plan_gate=task_unapproved'));
      expect(focusContext, contains('Patch · status=unsupported_tool'));
      expect(focusContext, contains('unsupported_tool=Patch'));
      expect(focusContext, contains('catalog_empty=true'));
    });

    test(
      'surfaces tool output budget truncation in post-compact focus context',
      () {
        final now = DateTime.utc(2026, 6, 19, 8);
        final messages = <AiSessionMessage>[
          AiSessionMessage.toolResult(
            id: 't1',
            content: 'Short visible prefix from a much larger tool result.',
            createdAt: now,
            metadata: const <String, Object?>{
              'tool_name': 'Bash',
              'status': 'success',
              'tool_output_truncated': true,
              'tool_output_original_length': 120000,
              'tool_output_budget_chars': 20000,
              'tool_output_included_chars': 19800,
              'tool_output_omitted_chars': 100200,
              'tool_output_truncation_strategy': 'head_tail',
              'tool_output_full_content_available': true,
              'tool_output_recovery_hint': 'read_persisted_output',
              'tool_output_persisted': true,
              'tool_output_persisted_path':
                  '/tmp/openhand/session-1/tool-results/call-1.txt',
              'tool_output_persisted_chars': 120000,
              'tool_output_persistence_format': 'text',
            },
          ),
          AiSessionMessage.compressionPoint(
            id: 'c1',
            content: 'Checkpoint after truncated tool output.',
            createdAt: now.add(const Duration(seconds: 1)),
            metadata: const <String, Object?>{},
          ),
          AiSessionMessage.user(
            id: 'u1',
            content: 'What happened before compaction?',
            createdAt: now.add(const Duration(seconds: 2)),
          ),
        ];
        final session = AiSession(
          id: 'session-1',
          title: 'Tool truncation focus context session',
          templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
          templateName: '编程专家',
          templateIconName: 'code_rounded',
          templateInternalVersion: 'test',
          createdAt: now,
          updatedAt: now,
          messages: messages,
          environment: _testEnvironment,
          statistics: const AiSessionStatistics.initial(),
          recentErrors: const <AiSessionErrorRecord>[],
        );

        final result = const AiPromptBuilder().buildSessionPrompt(
          templateBundle: _testBundle,
          session: session,
          model: _testModel,
          runtimeContext: _testRuntimeContext,
          memoryEntries: const <Never>[],
          sessionMessages: messages,
          latestUserMessageId: 'u1',
        );
        final focusContext = result.messages
            .map((turn) => turn.content)
            .firstWhere(
              (content) =>
                  content.startsWith(AiPromptSectionHeaders.focusContext),
            );

        expect(focusContext, contains('Bash · status=success'));
        expect(focusContext, contains('output_truncated=120000/20000'));
        expect(focusContext, contains('truncation=head_tail'));
        expect(focusContext, contains('full_output=true'));
        expect(
          focusContext,
          contains(
            'persisted_output=/tmp/openhand/session-1/tool-results/call-1.txt',
          ),
        );
        expect(focusContext, contains('recovery=read_persisted_output'));
      },
    );

    test(
      'keeps persisted output recovery anchors when micro-compacting old tool results',
      () {
        final now = DateTime.utc(2026, 6, 19, 8);
        final messages = <AiSessionMessage>[];
        for (var i = 0; i < 6; i += 1) {
          final toolCallId = 'call-$i';
          final arguments = jsonEncode(<String, Object?>{
            'cmd': 'generate-output-$i',
          });
          messages
            ..add(
              AiSessionMessage.toolCall(
                id: 'tc-$i',
                content: 'Tool call: Bash',
                createdAt: now.add(Duration(seconds: i * 3)),
                metadata: <String, Object?>{
                  'tool_call_id': toolCallId,
                  'tool_name': 'Bash',
                  'tool_arguments': arguments,
                  'tool_calls': <Map<String, Object?>>[
                    <String, Object?>{
                      'id': toolCallId,
                      'name': 'Bash',
                      'arguments': arguments,
                    },
                  ],
                },
              ),
            )
            ..add(
              AiSessionMessage.toolResult(
                id: 'tr-$i',
                content:
                    'visible output $i ${List<String>.filled(80, 'x').join()}',
                createdAt: now.add(Duration(seconds: i * 3 + 1)),
                metadata: <String, Object?>{
                  'tool_call_id': toolCallId,
                  'tool_name': 'Bash',
                  'status': 'success',
                  if (i == 0) ...<String, Object?>{
                    'tool_output_truncated': true,
                    'tool_output_original_length': 120000,
                    'tool_output_budget_chars': 20000,
                    'tool_output_included_chars': 19800,
                    'tool_output_omitted_chars': 100200,
                    'tool_output_truncation_strategy': 'head_tail',
                    'tool_output_full_content_available': true,
                    'tool_output_recovery_hint': 'read_persisted_output',
                    'tool_output_persisted': true,
                    'tool_output_persisted_path':
                        '/tmp/openhand/session-1/tool-results/call-0.txt',
                    'tool_output_persisted_chars': 120000,
                    'tool_output_persistence_format': 'text',
                  },
                },
              ),
            )
            ..add(
              AiSessionMessage.assistant(
                id: 'a-$i',
                content: 'Observed result $i.',
                createdAt: now.add(Duration(seconds: i * 3 + 2)),
              ),
            );
        }
        messages.add(
          AiSessionMessage.user(
            id: 'u-latest',
            content: 'Continue from the prior tool work.',
            createdAt: now.add(const Duration(seconds: 30)),
          ),
        );
        final session = AiSession(
          id: 'session-1',
          title: 'Micro compact persisted output session',
          templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
          templateName: '编程专家',
          templateIconName: 'code_rounded',
          templateInternalVersion: 'test',
          createdAt: now,
          updatedAt: now,
          messages: messages,
          environment: _testEnvironment,
          statistics: const AiSessionStatistics.initial(),
          recentErrors: const <AiSessionErrorRecord>[],
        );

        final result = const AiPromptBuilder().buildSessionPrompt(
          templateBundle: _testBundle,
          session: session,
          model: _testModel,
          runtimeContext: _testRuntimeContextWithMicroCompression,
          memoryEntries: const <Never>[],
          sessionMessages: messages,
          latestUserMessageId: 'u-latest',
        );
        final transcript = result.messages
            .map((turn) => turn.content)
            .join('\n---\n');

        expect(transcript, contains('[old_tool_result_cleared] Bash'));
        expect(
          transcript,
          contains(
            'tool_output_persisted_path: /tmp/openhand/session-1/tool-results/call-0.txt',
          ),
        );
        expect(
          transcript,
          contains(
            'note: Exact omitted output is available at tool_output_persisted_path.',
          ),
        );
      },
    );

    test(
      'surfaces plan approval allowed prompts in post-compact focus context',
      () {
        final now = DateTime.utc(2026, 6, 19, 8);
        final messages = <AiSessionMessage>[
          AiSessionMessage.toolResult(
            id: 't1',
            content: 'Plan captured.',
            createdAt: now,
            metadata: const <String, Object?>{
              'tool_name': 'ExitPlanMode',
              'status': 'success',
              'plan_mode_awaiting_approval': true,
              'pending_plan': '1. Patch behavior.\n2. Run verification.',
              'plan_mode_allowed_prompt_count': 2,
              'plan_mode_allowed_prompts': <Map<String, String>>[
                <String, String>{
                  'tool': 'Bash',
                  'prompt': 'run targeted tests',
                },
                <String, String>{'tool': 'Bash', 'prompt': 'build web assets'},
              ],
            },
          ),
          AiSessionMessage.compressionPoint(
            id: 'c1',
            content: 'Checkpoint after plan approval request.',
            createdAt: now.add(const Duration(seconds: 1)),
            metadata: const <String, Object?>{},
          ),
          AiSessionMessage.user(
            id: 'u1',
            content: 'What happened before compaction?',
            createdAt: now.add(const Duration(seconds: 2)),
          ),
        ];
        final session = AiSession(
          id: 'session-1',
          title: 'Plan approval focus context session',
          templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
          templateName: '编程专家',
          templateIconName: 'code_rounded',
          templateInternalVersion: 'test',
          createdAt: now,
          updatedAt: now,
          messages: messages,
          environment: _testEnvironment,
          statistics: const AiSessionStatistics.initial(),
          recentErrors: const <AiSessionErrorRecord>[],
        );

        final result = const AiPromptBuilder().buildSessionPrompt(
          templateBundle: _testBundle,
          session: session,
          model: _testModel,
          runtimeContext: _testRuntimeContext,
          memoryEntries: const <Never>[],
          sessionMessages: messages,
          latestUserMessageId: 'u1',
        );
        final focusContext = result.messages
            .map((turn) => turn.content)
            .firstWhere(
              (content) =>
                  content.startsWith(AiPromptSectionHeaders.focusContext),
            );

        expect(focusContext, contains('ExitPlanMode · status=success'));
        expect(focusContext, contains('plan_approval=pending'));
        expect(focusContext, contains('allowed_prompts=2'));
      },
    );
  });
}

Map<String, Object?> _compressionPayload(String content) {
  final match = RegExp(
    r'# Compression Task Payload\s+```json\n([\s\S]*?)\n```',
  ).firstMatch(content);
  expect(match, isNotNull);
  final decoded = jsonDecode(match!.group(1)!);
  return Map<String, Object?>.from(decoded as Map);
}

const AiThreadTemplate _testTemplate = AiThreadTemplate(
  id: AiPromptTemplatePolicies.programmingExpertTemplateId,
  name: '编程专家',
  iconName: 'code_rounded',
  description: 'test',
  internalVersion: 'test',
  promptAssetDirectory:
      AiPromptTemplatePolicies.programmingExpertPromptAssetDirectory,
);

const AiPromptTemplateBundle _testBundle = AiPromptTemplateBundle(
  template: _testTemplate,
  systemInstructions: 'system',
  developerInstructions: 'developer',
  compressionSummaryInstructions: 'compression',
);

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

const AiSessionEnvironment _testEnvironment = AiSessionEnvironment(
  localeTag: 'zh-CN',
  platform: 'macOS',
  appVersion: 'test',
  appBuildNumber: '1',
  applicationDirectory: '/tmp/openhand',
  homeDirectory: '/tmp',
  settingsFilePath: '/tmp/settings.json',
  skillsStoragePath: '/tmp/skills',
  mcpServersFilePath: '/tmp/mcp.json',
  userMemoryFilePath: '/tmp/memory.json',
  sessionsDirectoryPath: '/tmp/sessions',
  compressionThresholdChars: 1000,
);

const AiSessionRuntimeContext _testRuntimeContext = AiSessionRuntimeContext(
  localeTag: 'zh-CN',
  appVersion: 'test',
  appBuildNumber: '1',
  settingsFilePath: '/tmp/settings.json',
  skillsStoragePath: '/tmp/skills',
  mcpServersFilePath: '/tmp/mcp.json',
  userMemoryFilePath: '/tmp/memory.json',
  compressionThresholdChars: 1000,
  memoryEnabled: false,
  memoryEntries: <Never>[],
  workingDirectory: '/tmp/project',
  platformName: 'macOS',
  timeZoneName: 'Asia/Shanghai',
);

const AiSessionRuntimeContext _testRuntimeContextWithMicroCompression =
    AiSessionRuntimeContext(
      localeTag: 'zh-CN',
      appVersion: 'test',
      appBuildNumber: '1',
      settingsFilePath: '/tmp/settings.json',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.json',
      compressionThresholdChars: 1000,
      microCompressionEnabled: true,
      memoryEnabled: false,
      memoryEntries: <Never>[],
      workingDirectory: '/tmp/project',
      platformName: 'macOS',
      timeZoneName: 'Asia/Shanghai',
    );

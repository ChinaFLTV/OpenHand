import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/runtime/ai_plan_mode_guidance.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';

void main() {
  test('all thread templates inherit the same baseline shared sections', () {
    const expectedBaseline = <String>[
      'identity',
      'refusal_handling',
      'tone_and_formatting',
      'workflow',
    ];

    for (final entry in AiPromptTemplatePolicies.entries) {
      final tags = entry.policy.sharedSections
          .map((section) => section.tag)
          .toList(growable: false);

      expect(
        tags.take(expectedBaseline.length).toList(growable: false),
        expectedBaseline,
        reason: '${entry.id} must use the unified prompt assembly baseline.',
      );
    }
  });

  test(
    'all thread templates preserve stable prefix across appended history',
    () {
      const builder = AiPromptBuilder();
      final now = DateTime.utc(2026, 6, 28, 12);

      for (final entry in AiPromptTemplatePolicies.entries) {
        final initialSession = _session(
          templateEntry: entry,
          messages: <AiSessionMessage>[
            AiSessionMessage.user(
              id: 'user-1',
              content: 'First turn.',
              createdAt: now,
            ),
          ],
        );
        final followUpSession = _session(
          templateEntry: entry,
          messages: <AiSessionMessage>[
            AiSessionMessage.user(
              id: 'user-1',
              content: 'First turn.',
              createdAt: now,
            ),
            AiSessionMessage.assistant(
              id: 'assistant-1',
              content: 'Reply.',
              createdAt: now.add(const Duration(seconds: 1)),
            ),
            AiSessionMessage.user(
              id: 'user-2',
              content: 'Second turn.',
              createdAt: now.add(const Duration(seconds: 2)),
            ),
          ],
          lastPromptMetadata: const <String, Object?>{
            'stable_prefix_hash': 'previous',
            'tool_catalog_hash': 'previous-tools',
            'stable_cache_key': 'previous-key',
          },
        );
        final initialResult = builder.buildSessionPrompt(
          templateBundle: _bundle(entry.id),
          session: initialSession,
          model: _model,
          runtimeContext: _runtimeContext,
          memoryEntries: const <UserMemoryEntry>[],
          sessionMessages: initialSession.messages,
          latestUserMessageId: 'user-1',
          availableTools: _tools,
          planModeRecoveryInspectionRequired: false,
        );
        final followUpResult = builder.buildSessionPrompt(
          templateBundle: _bundle(entry.id),
          session: followUpSession,
          model: _model,
          runtimeContext: _runtimeContext,
          memoryEntries: const <UserMemoryEntry>[],
          sessionMessages: followUpSession.messages,
          latestUserMessageId: 'user-2',
          availableTools: _tools,
          planModeRecoveryInspectionRequired: false,
        );

        expect(
          followUpResult.metadata['stable_prefix_hash'],
          initialResult.metadata['stable_prefix_hash'],
          reason: '${entry.id} must not vary stable prefix when history grows.',
        );
        expect(
          followUpResult.metadata['stable_prefix_message_count'],
          initialResult.metadata['stable_prefix_message_count'],
          reason: '${entry.id} must keep the same stable assembly skeleton.',
        );
        expect(
          followUpResult.metadata['latest_user_message_count'],
          1,
          reason: '${entry.id} must keep latest user outside stable prefix.',
        );
      }
    },
  );

  test('plan reminder is controlled by runtime flags, not latest text', () {
    final session = _session(mode: AiSessionMode.plan, latestUserContent: '继续');
    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: _bundle(),
      session: session,
      model: _model,
      runtimeContext: _runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: session.messages,
      latestUserMessageId: 'user-1',
      availableTools: _tools,
      planModeRecoveryInspectionRequired: false,
    );
    final promptText = result.messages
        .map((message) => message.content)
        .join('\n\n');

    expect(promptText, contains(AiPlanModeGuidance.planningReminder));
    expect(
      promptText,
      isNot(contains(AiPlanModeGuidance.approvalExecutionReminder)),
    );
  });

  test('display catalog override drives stable cache metadata while gated', () {
    final awaitingSession = _session(
      mode: AiSessionMode.plan,
      awaitingPlanApproval: true,
      pendingPlan: '1. Inspect\n2. Implement',
    );
    final activeSession = _session(mode: AiSessionMode.plan);
    const builder = AiPromptBuilder();
    final awaitingResult = builder.buildSessionPrompt(
      templateBundle: _bundle(),
      session: awaitingSession,
      model: _model,
      runtimeContext: _runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: awaitingSession.messages,
      latestUserMessageId: 'user-1',
      displayCatalogOverride: _tools,
      planModeRecoveryInspectionRequired: false,
    );
    final activeResult = builder.buildSessionPrompt(
      templateBundle: _bundle(),
      session: activeSession,
      model: _model,
      runtimeContext: _runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: activeSession.messages,
      latestUserMessageId: 'user-1',
      availableTools: _tools,
      planModeRecoveryInspectionRequired: false,
    );

    expect(
      awaitingResult.metadata['stable_prefix_hash'],
      activeResult.metadata['stable_prefix_hash'],
    );
    expect(
      awaitingResult.metadata['tool_catalog_hash'],
      activeResult.metadata['tool_catalog_hash'],
    );
    expect(
      awaitingResult.metadata['stable_cache_key'],
      activeResult.metadata['stable_cache_key'],
    );
    expect(
      awaitingResult.messages.map((message) => message.content).join('\n\n'),
      contains('Write'),
    );
  });

  test('deferred knowledge tools stay in the dynamic catalog preview', () {
    final session = _session();
    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: _bundle(),
      session: session,
      model: _model,
      runtimeContext: _runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: session.messages,
      latestUserMessageId: 'user-1',
      availableTools: _toolsWithDeferredKnowledge,
      planModeRecoveryInspectionRequired: false,
    );
    final promptText = result.messages
        .map((message) => message.content)
        .join('\n\n');
    final builtinSection = promptText.substring(
      promptText.indexOf('## Builtin'),
    );

    expect(promptText, contains('## Dynamic Tools'));
    expect(promptText, contains('[built-in] KnowledgeSearch'));
    expect(promptText, contains('[built-in] KnowledgeRead'));
    expect(builtinSection, contains('- ToolSearch:'));
    expect(builtinSection, isNot(contains('- KnowledgeSearch:')));
    expect(builtinSection, isNot(contains('- KnowledgeRead:')));
  });
}

AiPromptTemplateBundle _bundle([
  String templateId = AiPromptTemplatePolicies.defaultTemplateId,
]) {
  final template = AiPromptTemplateRepository().resolveTemplate(templateId);
  return AiPromptTemplateBundle(
    template: template,
    systemInstructions: '<identity>Test system.</identity>',
    developerInstructions: '<tool_catalog>Test developer.</tool_catalog>',
    compressionSummaryInstructions: '<role>Summarize.</role>',
  );
}

AiSession _session({
  AiPromptTemplateCatalogEntry? templateEntry,
  AiSessionMode mode = AiSessionMode.chat,
  bool awaitingPlanApproval = false,
  String? pendingPlan,
  String latestUserContent = 'Do the work.',
  List<AiSessionMessage>? messages,
  Map<String, Object?> lastPromptMetadata = const <String, Object?>{},
}) {
  final now = DateTime.utc(2026, 6, 28, 12);
  final entry =
      templateEntry ??
      AiPromptTemplatePolicies.byTemplateId[AiPromptTemplatePolicies
          .defaultTemplateId]!;
  return AiSession(
    id: 'session-1',
    title: 'Prompt cache',
    templateId: entry.info.id,
    templateName: entry.info.name,
    templateIconName: entry.info.iconName,
    templateInternalVersion: entry.info.internalVersion,
    createdAt: now,
    updatedAt: now,
    messages:
        messages ??
        <AiSessionMessage>[
          AiSessionMessage.user(
            id: 'user-1',
            content: latestUserContent,
            createdAt: now,
          ),
        ],
    environment: const AiSessionEnvironment(
      localeTag: 'zh-Hans',
      platform: 'test',
      appVersion: 'test',
      appBuildNumber: '1',
      applicationDirectory: '',
      homeDirectory: '',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      sessionsDirectoryPath: '',
      compressionThresholdChars: 100000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
    mode: mode,
    awaitingPlanApproval: awaitingPlanApproval,
    pendingPlan: pendingPlan,
    lastPromptMetadata: lastPromptMetadata,
  );
}

const AiSessionRuntimeContext _runtimeContext = AiSessionRuntimeContext(
  localeTag: 'zh-Hans',
  appVersion: 'test',
  appBuildNumber: '1',
  settingsFilePath: '',
  skillsStoragePath: '',
  mcpServersFilePath: '',
  userMemoryFilePath: '',
  compressionThresholdChars: 100000,
  memoryEnabled: false,
  memoryEntries: <UserMemoryEntry>[],
  platformName: 'test',
  workingDirectory: '/tmp/openhand-test',
  timeZoneName: 'Asia/Shanghai',
);

const AiModelConfig _model = AiModelConfig(
  id: 'model-1',
  baseUrl: 'https://example.invalid',
  authScheme: AiAuthScheme.bearer,
  token: '',
  modelId: 'claude-test',
  protocolType: AiProtocolType.claude,
);

const List<AiToolDefinition> _tools = <AiToolDefinition>[
  AiToolDefinition(
    name: 'Write',
    description: 'Write a file.',
    parameters: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  ),
];

const List<AiToolDefinition> _toolsWithDeferredKnowledge = <AiToolDefinition>[
  AiToolDefinition(
    name: 'ToolSearch',
    description:
        'Fetch full schema definitions for deferred runtime tools.\n\n'
        '## Deferred built-in tools (2)\n'
        '- KnowledgeSearch - Search local knowledge base chunks.\n'
        '- KnowledgeRead - Read local knowledge base chunks.',
    parameters: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  ),
  AiToolDefinition(
    name: 'WebFetch',
    description: 'Fetch a web page.',
    parameters: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  ),
];

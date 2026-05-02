import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/model/ai_attachment.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/ai/service/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';
import 'package:openhand/features/skills/model/local_skill.dart';

void main() {
  test('compression prompt uses concise no-tools identity', () {
    const template = AiThreadTemplate(
      id: 'machine_expert',
      name: '机器专家',
      iconName: 'build_circle_rounded',
      description: 'terminal workflow',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/machine_expert',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'FULL SYSTEM INSTRUCTIONS SHOULD NOT BE INCLUDED',
      developerInstructions: 'developer instructions',
      compressionSummaryInstructions: 'KEEP TERMINAL BINDING STATE',
    );
    final now = DateTime.utc(2026, 5, 3);
    final session = _session(
      template: template,
      now: now,
      messages: <AiSessionMessage>[
        AiSessionMessage.user(id: 'm1', content: '继续排查远端终端问题', createdAt: now),
      ],
    );

    final prompt = const AiPromptBuilder().buildCompressionPrompt(
      templateBundle: bundle,
      template: template,
      session: session,
      runtimeContext: _runtimeContext(),
      messagesToCompress: session.messages,
      previousCompressionPoint: null,
    );

    expect(prompt.first.content, contains('TEXT ONLY'));
    expect(prompt.first.content, contains('Do not call tools'));
    expect(
      prompt.first.content,
      isNot(contains('FULL SYSTEM INSTRUCTIONS SHOULD NOT BE INCLUDED')),
    );
    expect(prompt[1].content, contains('KEEP TERMINAL BINDING STATE'));
    expect(prompt.last.content, contains('继续排查远端终端问题'));
  });

  test('micro compact clears older consumed tool results', () {
    const template = AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description: 'default',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'system',
      developerInstructions: 'developer',
      compressionSummaryInstructions: 'compression',
    );
    final now = DateTime.utc(2026, 5, 3);
    final history = <AiSessionMessage>[
      AiSessionMessage.user(id: 'u1', content: 'run tools', createdAt: now),
      for (var i = 0; i < 7; i++) ...<AiSessionMessage>[
        _toolCall('tc$i', 'call$i', now),
        _toolResult('tr$i', 'call$i', 'raw result $i', now),
      ],
      AiSessionMessage.assistant(
        id: 'a1',
        content: 'consumed tool outputs',
        createdAt: now,
      ),
    ];
    final latest = AiSessionMessage.user(
      id: 'latest',
      content: 'continue',
      createdAt: now,
    );
    final messages = <AiSessionMessage>[...history, latest];
    final session = _session(template: template, now: now, messages: messages);

    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: messages,
      latestUserMessageId: latest.id,
    );
    final promptText = result.messages.map((turn) => turn.content).join('\n');

    expect(
      RegExp(r'\[old_tool_result_cleared\]').allMatches(promptText).length,
      2,
    );
    expect(promptText, isNot(contains('raw result 0')));
    expect(promptText, isNot(contains('raw result 1')));
    expect(promptText, contains('raw result 2'));
    expect(promptText, contains('raw result 6'));
  });

  test('records context budget metadata for prompt builds', () {
    const template = AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description: 'default',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'system',
      developerInstructions: 'developer',
      compressionSummaryInstructions: 'compression',
    );
    final now = DateTime.utc(2026, 5, 3);
    final latest = AiSessionMessage.user(
      id: 'latest',
      content: 'hello',
      createdAt: now,
    );
    final session = _session(template: template, now: now, messages: [latest]);

    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model(maxContextTokens: 1000),
      runtimeContext: _runtimeContext(),
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: [latest],
      latestUserMessageId: latest.id,
    );

    expect(
      result.metadata['current_prompt_character_count'],
      result.promptCharacterCount,
    );
    expect(
      result.metadata['context_budget_estimated_prompt_tokens'],
      isA<int>().having((value) => value, 'value', greaterThan(0)),
    );
    expect(result.metadata['context_budget_model_max_tokens'], 1000);
    expect(result.metadata['context_budget_summary_reserve_tokens'], 500);
    expect(result.metadata['context_budget_effective_window_tokens'], 500);
    expect(
      result.metadata['context_budget_auto_compact_threshold_tokens'],
      450,
    );
    expect(result.metadata['context_budget_status'], isNot('unknown'));
    expect(result.metadata['context_budget_usage_percent'], isA<int>());
    expect(result.metadata['context_budget_percent_left'], isA<int>());
  });

  test('records post-compact rehydration metadata', () {
    const template = AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description: 'default',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'system',
      developerInstructions: 'developer',
      compressionSummaryInstructions: 'compression',
    );
    final now = DateTime.utc(2026, 5, 3);
    final checkpoint = AiSessionMessage.compressionPoint(
      id: 'cp1',
      content: 'summary',
      createdAt: now,
      metadata: const <String, Object?>{},
    );
    final readResult = AiSessionMessage.toolResult(
      id: 'read1',
      content: '1\tvoid main() {}',
      createdAt: now,
      metadata: const <String, Object?>{
        'tool_call_id': 'call-read1',
        'tool_name': 'Read',
        'status': 'success',
        'read_file_path': '/tmp/project/lib/main.dart',
        'read_file_kind': 'text',
        'read_render_mode': 'line',
      },
    );
    final latest = AiSessionMessage.user(
      id: 'latest',
      content: 'continue',
      createdAt: now,
    );
    final session = _session(
      template: template,
      now: now,
      messages: <AiSessionMessage>[readResult, checkpoint, latest],
    );

    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: <UserMemoryEntry>[
        UserMemoryEntry(
          id: 'mem1',
          type: UserMemoryEntry.userType,
          createdAt: now,
          content: 'User prefers concise Chinese summaries.',
          tags: const <String>[],
        ),
      ],
      sessionMessages: <AiSessionMessage>[readResult, checkpoint, latest],
      latestUserMessageId: latest.id,
    );
    final promptText = result.messages.map((turn) => turn.content).join('\n');

    final rehydration = Map<String, Object?>.from(
      result.metadata['post_compact_rehydration']! as Map,
    );
    expect(rehydration['active'], isTrue);
    expect(rehydration['checkpoint_message_id'], 'cp1');
    expect(rehydration['session_memory_sidecar_present'], isTrue);
    expect(
      rehydration['session_memory_sidecar_path'],
      '/tmp/sessions/session-1/memory/compact-latest.md',
    );
    expect(rehydration['memory_entry_count'], 1);
    expect(
      rehydration['restored_channels'],
      containsAll(<String>[
        'system_instructions',
        'developer_instructions',
        'tool_catalog',
        'session_state',
        'conversation_checkpoint',
        'recent_history_tail',
        'user_memory',
        'recent_read_files',
      ]),
    );
    expect(rehydration['recent_read_file_count'], 1);
    expect(promptText, contains('Recent read files'));
    expect(promptText, contains('/tmp/project/lib/main.dart'));
  });

  test('bounds oversized checkpoint in compression prompts', () {
    const template = AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description: 'default',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'system',
      developerInstructions: 'developer',
      compressionSummaryInstructions: 'compression',
    );
    final now = DateTime.utc(2026, 5, 3);
    final head = List<String>.filled(23000, 'H').join();
    final tail = List<String>.filled(23000, 'T').join();
    final checkpoint = AiSessionMessage.compressionPoint(
      id: 'cp-long',
      content: '${head}MIDDLE_SHOULD_BE_OMITTED$tail',
      createdAt: now,
      metadata: const <String, Object?>{},
    );
    final session = _session(
      template: template,
      now: now,
      messages: <AiSessionMessage>[
        checkpoint,
        AiSessionMessage.user(id: 'u1', content: 'continue', createdAt: now),
      ],
    );

    final prompt = const AiPromptBuilder().buildCompressionPrompt(
      templateBundle: bundle,
      template: template,
      session: session,
      runtimeContext: _runtimeContext(),
      messagesToCompress: session.messages.skip(1).toList(growable: false),
      previousCompressionPoint: checkpoint,
    );
    final promptText = prompt.last.content;

    expect(promptText, contains('[checkpoint_middle_omitted]'));
    expect(promptText, isNot(contains('MIDDLE_SHOULD_BE_OMITTED')));
    expect(promptText, contains('HHHH'));
    expect(promptText, contains('TTTT'));
  });

  test('bounds attachment details in compression prompts', () {
    const template = AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description: 'default',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'system',
      developerInstructions: 'developer',
      compressionSummaryInstructions: 'compression',
    );
    final now = DateTime.utc(2026, 5, 3);
    final longDocumentText = List<String>.filled(2500, 'D').join();
    final message = AiSessionMessage.user(
      id: 'u1',
      content: 'summarize attachments',
      createdAt: now,
      metadata: <String, Object?>{
        aiSessionMessageAttachmentsMetadataKey:
            AiMessageAttachment.listToMetadata(<AiMessageAttachment>[
              AiMessageAttachment(
                id: 'doc1',
                name: 'long.txt',
                storagePath: '/tmp/long.txt',
                kind: AiAttachmentKind.text,
                mimeType: 'text/plain',
                sizeBytes: longDocumentText.length,
                promptText: '${longDocumentText}SHOULD_BE_TRUNCATED',
              ),
              const AiMessageAttachment(
                id: 'img1',
                name: 'photo.png',
                storagePath: '/tmp/photo.png',
                kind: AiAttachmentKind.image,
                mimeType: 'image/png',
                sizeBytes: 1024,
              ),
            ]),
      },
    );
    final session = _session(
      template: template,
      now: now,
      messages: <AiSessionMessage>[message],
    );

    final prompt = const AiPromptBuilder().buildCompressionPrompt(
      templateBundle: bundle,
      template: template,
      session: session,
      runtimeContext: _runtimeContext(),
      messagesToCompress: <AiSessionMessage>[message],
      previousCompressionPoint: null,
    );
    final promptText = prompt.last.content;

    expect(promptText, contains('[attachment_content_truncated:'));
    expect(promptText, isNot(contains('SHOULD_BE_TRUNCATED')));
    expect(promptText, contains('[image] photo.png (image/png)'));
  });

  test('restores recent read file content after compact', () async {
    final root = await Directory.systemTemp.createTemp(
      'openhand-restored-file-test-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final file = File('${root.path}/main.dart');
    await file.writeAsString('void main() {\n  print("restored");\n}\n');
    const template = AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description: 'default',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'system',
      developerInstructions: 'developer',
      compressionSummaryInstructions: 'compression',
    );
    final now = DateTime.utc(2026, 5, 3);
    final readResult = AiSessionMessage.toolResult(
      id: 'read-before-compact',
      content: '1\tvoid main() {',
      createdAt: now,
      metadata: <String, Object?>{
        'tool_call_id': 'call-read-before-compact',
        'tool_name': 'Read',
        'status': 'success',
        'read_file_path': file.path,
        'read_file_kind': 'text',
        'read_render_mode': 'line',
      },
    );
    final checkpoint = AiSessionMessage.compressionPoint(
      id: 'cp-restore',
      content: 'summary',
      createdAt: now,
      metadata: const <String, Object?>{},
    );
    final latest = AiSessionMessage.user(
      id: 'latest',
      content: 'continue',
      createdAt: now,
    );
    final messages = <AiSessionMessage>[readResult, checkpoint, latest];
    final session = _session(template: template, now: now, messages: messages);

    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: messages,
      latestUserMessageId: latest.id,
    );
    final promptText = result.messages.map((turn) => turn.content).join('\n');

    expect(promptText, contains('# [5.6] Restored File Context'));
    expect(promptText, contains(file.path));
    expect(promptText, contains('print("restored")'));
  });

  test('restores invoked skill context after compact', () async {
    final root = await Directory.systemTemp.createTemp(
      'openhand-restored-skill-test-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final manifest = File('${root.path}/SKILL.md');
    await manifest.writeAsString(
      '# Flutter Audit\nUse WidgetTester carefully.\n',
    );
    const template = AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description: 'default',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'system',
      developerInstructions: 'developer',
      compressionSummaryInstructions: 'compression',
    );
    final now = DateTime.utc(2026, 5, 3);
    final skillResult = AiSessionMessage.skillResult(
      id: 'skill-before-compact',
      content: 'skill invoked',
      createdAt: now,
      metadata: <String, Object?>{
        'tool_call_id': 'call-skill-before-compact',
        'tool_name': 'skill__flutter-audit',
        'tool_source': 'skill',
        'skill_name': 'flutter-audit',
        'skill_manifest_path': manifest.path,
      },
    );
    final checkpoint = AiSessionMessage.compressionPoint(
      id: 'cp-skill-restore',
      content: 'summary',
      createdAt: now,
      metadata: const <String, Object?>{},
    );
    final latest = AiSessionMessage.user(
      id: 'latest',
      content: 'continue',
      createdAt: now,
    );
    final messages = <AiSessionMessage>[skillResult, checkpoint, latest];
    final session = _session(template: template, now: now, messages: messages);

    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model(),
      runtimeContext: _runtimeContext(
        availableSkills: <LocalSkill>[
          LocalSkill(
            name: 'flutter-audit',
            description: 'Audit Flutter widgets',
            directoryPath: root.path,
            manifestPath: manifest.path,
            relativeDirectoryPath: 'flutter-audit',
            defaultPrompt: 'Always preserve accessibility labels.',
          ),
        ],
      ),
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: messages,
      latestUserMessageId: latest.id,
    );
    final promptText = result.messages.map((turn) => turn.content).join('\n');
    final rehydration = Map<String, Object?>.from(
      result.metadata['post_compact_rehydration']! as Map,
    );

    expect(promptText, contains('# [5.7] Restored Skill Context'));
    expect(promptText, contains('Always preserve accessibility labels.'));
    expect(promptText, contains('Use WidgetTester carefully.'));
    expect(rehydration['invoked_skill_count'], 1);
    expect(rehydration['restored_channels'], contains('invoked_skills'));
  });

  test('restores plan context after compact', () {
    const template = AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description: 'default',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'system',
      developerInstructions: 'developer',
      compressionSummaryInstructions: 'compression',
    );
    final now = DateTime.utc(2026, 5, 3);
    final checkpoint = AiSessionMessage.compressionPoint(
      id: 'cp-plan-restore',
      content: 'summary',
      createdAt: now,
      metadata: const <String, Object?>{},
    );
    final latest = AiSessionMessage.user(
      id: 'latest',
      content: '继续执行计划',
      createdAt: now,
    );
    final messages = <AiSessionMessage>[checkpoint, latest];
    final session = _session(template: template, now: now, messages: messages)
        .copyWith(
          mode: AiSessionMode.plan,
          awaitingPlanApproval: true,
          pendingPlan: '1. Inspect compact state\n2. Patch prompt restore',
          planHistory: <AiSessionPlanRecord>[
            AiSessionPlanRecord(
              id: 'plan-1',
              createdAt: now.subtract(const Duration(minutes: 5)),
              updatedAt: now,
              status: AiSessionPlanStatus.pendingApproval,
              plan: 'Restore plan details after checkpoint.',
              steps: const <AiSessionTodoItem>[
                AiSessionTodoItem(
                  id: 'step-1',
                  content: 'Inspect compact state',
                  status: 'completed',
                ),
                AiSessionTodoItem(
                  id: 'step-2',
                  content: 'Patch prompt restore',
                  status: 'in_progress',
                ),
              ],
            ),
          ],
          todoItems: const <AiSessionTodoItem>[
            AiSessionTodoItem(
              id: 'todo-1',
              content: 'Patch prompt restore',
              status: 'in_progress',
            ),
          ],
        );

    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: messages,
      latestUserMessageId: latest.id,
    );
    final promptText = result.messages.map((turn) => turn.content).join('\n');
    final rehydration = Map<String, Object?>.from(
      result.metadata['post_compact_rehydration']! as Map,
    );

    expect(promptText, contains('# [5.8] Restored Plan Context'));
    expect(promptText, contains('awaiting_plan_approval: true'));
    expect(promptText, contains('Restore plan details after checkpoint.'));
    expect(promptText, contains('- [in_progress] Patch prompt restore'));
    expect(rehydration['restored_channels'], contains('plan_context'));
  });

  test('restores mcp context after compact', () {
    const template = AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description: 'default',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'system',
      developerInstructions: 'developer',
      compressionSummaryInstructions: 'compression',
    );
    final now = DateTime.utc(2026, 5, 3);
    final checkpoint = AiSessionMessage.compressionPoint(
      id: 'cp-mcp-restore',
      content: 'summary',
      createdAt: now,
      metadata: const <String, Object?>{},
    );
    final latest = AiSessionMessage.user(
      id: 'latest',
      content: '继续使用 MCP',
      createdAt: now,
    );
    final messages = <AiSessionMessage>[checkpoint, latest];
    final session = _session(template: template, now: now, messages: messages);

    final result = const AiPromptBuilder().buildSessionPrompt(
      templateBundle: bundle,
      session: session,
      model: _model(),
      runtimeContext: _runtimeContext(
        availableMcpServers: const <McpServer>[
          McpServer(
            name: 'filesystem',
            type: McpServerType.stdio,
            enabled: true,
            command: 'npx',
            args: <String>['-y', '@modelcontextprotocol/server-filesystem'],
          ),
        ],
      ),
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: messages,
      latestUserMessageId: latest.id,
      availableTools: const <AiToolDefinition>[
        AiToolDefinition(
          name: 'mcp__filesystem__read_file',
          description: 'MCP tool from server "filesystem". Read a file.',
          parameters: <String, Object?>{'type': 'object'},
        ),
      ],
    );
    final promptText = result.messages.map((turn) => turn.content).join('\n');
    final rehydration = Map<String, Object?>.from(
      result.metadata['post_compact_rehydration']! as Map,
    );

    expect(promptText, contains('# [5.9] Restored MCP Context'));
    expect(promptText, contains('filesystem (stdio, enabled=true)'));
    expect(promptText, contains('mcp__filesystem__read_file'));
    expect(rehydration['mcp_server_count'], 1);
    expect(rehydration['mcp_tool_count'], 1);
    expect(rehydration['restored_channels'], contains('mcp_context'));
  });
}

AiSessionMessage _toolCall(String id, String callId, DateTime now) {
  return AiSessionMessage.toolCall(
    id: id,
    content: 'Tool call $callId',
    createdAt: now,
    metadata: <String, Object?>{
      'tool_calls': <Map<String, Object?>>[
        <String, Object?>{
          'id': callId,
          'name': 'Bash',
          'arguments': '{"cmd":"echo $callId"}',
        },
      ],
    },
  );
}

AiSessionMessage _toolResult(
  String id,
  String callId,
  String content,
  DateTime now,
) {
  return AiSessionMessage.toolResult(
    id: id,
    content: content,
    createdAt: now,
    metadata: <String, Object?>{
      'tool_call_id': callId,
      'tool_name': 'Bash',
      'status': 'success',
    },
  );
}

AiModelConfig _model({int? maxContextTokens}) {
  return AiModelConfig(
    id: 'model',
    baseUrl: 'https://example.test/v1',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'test-model',
    protocolType: AiProtocolType.openai,
    maxContextTokens: maxContextTokens,
  );
}

AiSession _session({
  required AiThreadTemplate template,
  required DateTime now,
  required List<AiSessionMessage> messages,
}) {
  return AiSession(
    id: 'session-1',
    title: 'Compression Test',
    templateId: template.id,
    templateName: template.name,
    templateIconName: template.iconName,
    templateInternalVersion: template.internalVersion,
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'zh-Hans',
      platform: 'macos',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '/tmp/openhand',
      homeDirectory: '/tmp',
      settingsFilePath: '/tmp/settings.json',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.md',
      sessionsDirectoryPath: '/tmp/sessions',
      compressionThresholdChars: 12000,
    ),
    statistics: AiSessionStatistics.fromMessages(
      messages,
      totalPromptCharacters: 0,
      promptBuildCount: 0,
      compressionRunCount: 0,
      totalUsage: const AiTokenUsage(),
      lastPromptSystemMessageCount: 0,
      lastPromptHistoryMessageCount: 0,
    ),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}

AiSessionRuntimeContext _runtimeContext({
  List<LocalSkill> availableSkills = const <LocalSkill>[],
  List<McpServer> availableMcpServers = const <McpServer>[],
}) {
  return AiSessionRuntimeContext(
    localeTag: 'zh-Hans',
    appVersion: '0.1.0',
    appBuildNumber: '1',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.md',
    compressionThresholdChars: 12000,
    memoryEnabled: true,
    memoryEntries: const <UserMemoryEntry>[],
    availableSkills: availableSkills,
    availableMcpServers: availableMcpServers,
  );
}

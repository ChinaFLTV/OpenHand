import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
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

  test('AiPromptBuilder groups consecutive tool-call messages into one tool round', () {
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
      (item) => item.role == AiChatRole.assistant && item.toolCalls.isNotEmpty,
    );
    final toolTurns = prompt.messages
        .where((item) => item.role == AiChatRole.tool)
        .toList(growable: false);

    expect(assistantToolCallTurn.toolCalls, hasLength(2));
    expect(
      assistantToolCallTurn.toolCalls.map((item) => item.id).toList(),
      <String>['tool-call-1', 'tool-call-2'],
    );
    expect(
      toolTurns.map((item) => item.toolCallId).toList(),
      <String>['tool-call-1', 'tool-call-2'],
    );
    expect(prompt.historyMessageCount, 3);
  });

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

AiSession _session({required List<AiSessionMessage> messages}) {
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
  );
}

AiSessionRuntimeContext _runtimeContext() {
  return const AiSessionRuntimeContext(
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

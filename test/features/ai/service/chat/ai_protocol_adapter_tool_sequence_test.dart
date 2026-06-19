import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';

void main() {
  group('OpenAiProtocolAdapter tool sequence repair', () {
    test(
      'combines consecutive tool calls and inlines system reminders',
      () async {
        final body = await const OpenAiProtocolAdapter(AiProtocolType.openai)
            .buildBody(_testModel, <AiChatTurn>[
              const AiChatTurn(role: AiChatRole.system, content: 'system'),
              const AiChatTurn(
                role: AiChatRole.assistant,
                content: 'Tool call: TodoWrite',
                toolCalls: <AiToolCall>[
                  AiToolCall(
                    id: 'call-1',
                    name: 'TodoWrite',
                    arguments: '{"todos":[]}',
                  ),
                ],
              ),
              const AiChatTurn(
                role: AiChatRole.assistant,
                content: 'Tool call: LS',
                toolCalls: <AiToolCall>[
                  AiToolCall(
                    id: 'call-2',
                    name: 'LS',
                    arguments: '{"path":"/tmp/project"}',
                  ),
                ],
              ),
              const AiChatTurn(
                role: AiChatRole.system,
                content: '# System Reminder\nhook command failed',
              ),
              const AiChatTurn(
                role: AiChatRole.tool,
                toolCallId: 'call-1',
                content: 'todo ok',
              ),
              const AiChatTurn(
                role: AiChatRole.tool,
                toolCallId: 'call-2',
                content: 'ls ok',
              ),
              const AiChatTurn(role: AiChatRole.user, content: 'continue'),
            ]);

        final messages = _messages(body);
        final assistantIndex = messages.indexWhere(
          (message) => message['role'] == 'assistant',
        );
        expect(assistantIndex, greaterThanOrEqualTo(0));

        final assistant = messages[assistantIndex];
        expect(assistant['tool_calls'], hasLength(2));
        expect(messages[assistantIndex + 1]['role'], 'tool');
        expect(messages[assistantIndex + 1]['tool_call_id'], 'call-1');
        expect(
          messages[assistantIndex + 1]['content'],
          contains('[system_reminder] hook command failed'),
        );
        expect(messages[assistantIndex + 2]['role'], 'tool');
        expect(messages[assistantIndex + 2]['tool_call_id'], 'call-2');
        expect(messages[assistantIndex + 3]['role'], 'user');
      },
    );

    test('downgrades incomplete tool exchanges before sending', () async {
      final body = await const OpenAiProtocolAdapter(AiProtocolType.openai)
          .buildBody(_testModel, <AiChatTurn>[
            const AiChatTurn(
              role: AiChatRole.assistant,
              content: 'Tool call: Read',
              toolCalls: <AiToolCall>[
                AiToolCall(
                  id: 'missing-call',
                  name: 'Read',
                  arguments: '{"file_path":"/tmp/missing.txt"}',
                ),
              ],
            ),
            const AiChatTurn(role: AiChatRole.user, content: 'what happened?'),
          ]);

      final messages = _messages(body);
      expect(
        messages.any((message) => message.containsKey('tool_calls')),
        isFalse,
      );
      expect(messages.any((message) => message['role'] == 'tool'), isFalse);
      expect(messages.first['role'], 'assistant');
      expect(messages.first['content'], contains('[tool_exchange_repaired]'));
      expect(messages.first['content'], contains('missing-call'));
      expect(messages.last['role'], 'user');
    });
  });
}

List<Map<String, Object?>> _messages(Map<String, Object?> body) {
  final messages = body['messages'] as List;
  return messages
      .map((message) => Map<String, Object?>.from(message as Map))
      .toList(growable: false);
}

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

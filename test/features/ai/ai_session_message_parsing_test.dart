import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('AiSessionMessage.fromJson parses loose flags and JSON text usage', () {
    final message = AiSessionMessage.fromJson('''
      {
        "id": "message-1",
        "kind": "assistant",
        "role": "assistant",
        "content": "hello",
        "created_at": "2026-06-28T12:00:00Z",
        "character_count": "42",
        "is_deleted": "yes",
        "usage": "{\\"prompt_tokens\\":\\"7\\",\\"completion_tokens\\":\\"3\\",\\"total_tokens\\":\\"10\\"}"
      }
    ''');

    expect(message.id, 'message-1');
    expect(message.kind, AiSessionMessageKind.assistant);
    expect(message.role, AiSessionMessageRole.assistant);
    expect(message.characterCount, 42);
    expect(message.isDeleted, isTrue);
    expect(message.usage?.promptTokens, 7);
    expect(message.usage?.completionTokens, 3);
    expect(message.usage?.totalTokens, 10);
  });

  test('AiSessionMessage.fromJson falls back for invalid character counts', () {
    final message = AiSessionMessage.fromJson(<String, Object?>{
      'content': ' hello ',
      'character_count': -1,
      'is_deleted': 'off',
    });

    expect(message.characterCount, 5);
    expect(message.isDeleted, isFalse);
    expect(message.usage, isNull);
  });

  test('AiSessionMessageResponseVariant.fromJson parses JSON text usage', () {
    final variant = AiSessionMessageResponseVariant.fromJson('''
      {
        "id": "variant-1",
        "content": "answer",
        "created_at": "2026-06-28T12:00:00Z",
        "usage": {"total_tokens": "12"},
        "message_feedback": "liked",
        "intermediate_message_ids": "a,b"
      }
    ''');

    expect(variant.id, 'variant-1');
    expect(variant.content, 'answer');
    expect(variant.usage?.totalTokens, 12);
    expect(variant.feedback, AiSessionMessageFeedback.liked);
    expect(variant.intermediateMessageIds, <String>['a', 'b']);
  });
}

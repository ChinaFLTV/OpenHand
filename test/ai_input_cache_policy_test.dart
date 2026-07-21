import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_attachment.dart';
import 'package:openhand/features/ai/model/ai_input_cache_policy.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';

void main() {
  final createdAt = DateTime.utc(2026, 7, 21);

  AiSessionMessage user(String content, {bool deleted = false}) {
    return AiSessionMessage.user(
      id: 'user-$content-$deleted',
      content: content,
      createdAt: createdAt,
    ).copyWith(isDeleted: deleted);
  }

  AiSessionMessage assistant(String content, {bool deleted = false}) {
    return AiSessionMessage.assistant(
      id: 'assistant-$content-$deleted',
      content: content,
      createdAt: createdAt,
    ).copyWith(isDeleted: deleted);
  }

  bool locked(List<AiSessionMessage> messages, {bool enabled = true}) {
    return isInputCacheModelSelectionLocked(
      inputCacheEnabled: enabled,
      messages: messages,
    );
  }

  test('输入缓存关闭时不锁定模型', () {
    expect(
      locked(<AiSessionMessage>[user('问题'), assistant('回答')], enabled: false),
      isFalse,
    );
  });

  test('空用户消息或空 AI 占位不会锁定模型', () {
    expect(locked(<AiSessionMessage>[user('   '), assistant('回答')]), isFalse);
    expect(locked(<AiSessionMessage>[user('问题'), assistant('   ')]), isFalse);
  });

  test('仅在有效用户消息之后收到有效 AI 内容时锁定模型', () {
    expect(locked(<AiSessionMessage>[assistant('预置内容'), user('问题')]), isFalse);
    expect(locked(<AiSessionMessage>[user('问题'), assistant('回答')]), isTrue);
    expect(
      locked(<AiSessionMessage>[
        user('问题'),
        AiSessionMessage.reasoning(
          id: 'reasoning',
          content: '正在思考',
          createdAt: createdAt,
        ),
      ]),
      isTrue,
    );
    expect(
      locked(<AiSessionMessage>[
        user('问题'),
        AiSessionMessage.toolCall(
          id: 'tool-call',
          content: '',
          createdAt: createdAt,
          metadata: const <String, Object?>{'tool_name': 'search'},
        ),
      ]),
      isTrue,
    );
    expect(
      locked(<AiSessionMessage>[
        user('问题'),
        AiSessionMessage.toolResult(
          id: 'tool-result',
          content: '工具结果',
          createdAt: createdAt,
          metadata: const <String, Object?>{},
        ),
      ]),
      isFalse,
    );
  });

  test('仅附件的用户消息收到 AI 响应后也会锁定模型', () {
    final attachmentOnlyUser = user('').copyWith(
      metadata: const <String, Object?>{
        aiSessionMessageAttachmentsMetadataKey: <String>['image.png'],
      },
    );
    expect(
      locked(<AiSessionMessage>[attachmentOnlyUser, assistant('回答')]),
      isTrue,
    );
  });

  test('已删除的用户消息或 AI 内容不会触发锁定', () {
    expect(
      locked(<AiSessionMessage>[user('问题', deleted: true), assistant('回答')]),
      isFalse,
    );
    expect(
      locked(<AiSessionMessage>[user('问题'), assistant('回答', deleted: true)]),
      isFalse,
    );
  });
}

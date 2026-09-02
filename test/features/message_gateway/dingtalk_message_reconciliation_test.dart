import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';

void main() {
  group('normalizeDingTalkConversationMessages', () {
    test(
      'repairs malformed IDs and duplicate source ownership deterministically',
      () {
        final base = DateTime.utc(2026, 9, 2, 8);
        final result =
            normalizeDingTalkConversationMessages(<DingTalkGatewayMessage>[
              _message(
                id: 'remote-1]',
                content: '旧重复正文',
                createdAt: base.add(const Duration(minutes: 1)),
                sourceId: 'physical-source',
              ),
              _message(
                id: 'remote-1',
                content: '新重复正文',
                createdAt: base.add(const Duration(minutes: 2)),
                sourceId: 'physical-source',
              ),
              _message(
                id: 'echo-a',
                content: '第一条回显仍需保留',
                createdAt: base.add(const Duration(minutes: 3)),
                sourceId: ' shared-source ',
              ),
              _message(
                id: 'echo-b',
                content: '第二条回显仍需保留',
                createdAt: base.add(const Duration(minutes: 4)),
                sourceId: 'shared-source',
              ),
              _message(
                id: 'user-z',
                content: '用户消息',
                createdAt: base,
                sourceId: 'invalid-user-source',
                role: DingTalkGatewayMessageRole.user,
              ),
              _message(
                id: '  ',
                content: '空标识消息',
                createdAt: base.add(const Duration(minutes: 5)),
              ),
            ]);

        expect(result.changed, isTrue);
        expect(result.messages.map((message) => message.id), <String>[
          'user-z',
          'remote-1',
          'echo-a',
          'echo-b',
        ]);
        expect(
          result.messages
              .singleWhere((message) => message.id == 'remote-1')
              .content,
          '新重复正文',
        );
        expect(
          result.messages
              .singleWhere((message) => message.id == 'echo-a')
              .sourceAiMessageId,
          isEmpty,
        );
        expect(
          result.messages
              .singleWhere((message) => message.id == 'echo-b')
              .sourceAiMessageId,
          'shared-source',
        );
        expect(result.messages.first.sourceAiMessageId, isEmpty);
        expect(
          result.messages.map((message) => message.content),
          containsAll(<String>['第一条回显仍需保留', '第二条回显仍需保留']),
        );

        final secondPass = normalizeDingTalkConversationMessages(
          result.messages,
        );
        expect(secondPass.changed, isFalse);
        expect(secondPass.messages, orderedEquals(result.messages));
      },
    );

    test('orders equal timestamps by normalized message ID', () {
      final createdAt = DateTime.utc(2026, 9, 2, 9);
      final result =
          normalizeDingTalkConversationMessages(<DingTalkGatewayMessage>[
            _message(id: 'z-message', content: 'z', createdAt: createdAt),
            _message(id: 'a-message', content: 'a', createdAt: createdAt),
          ]);

      expect(result.changed, isTrue);
      expect(result.messages.map((message) => message.id), <String>[
        'a-message',
        'z-message',
      ]);
    });
  });

  group('DingTalkMessageRenderTopology', () {
    test(
      'keeps a unique AI source stable across local to remote ID binding',
      () {
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        final local = DingTalkMessageRenderTopology(<DingTalkGatewayMessage>[
          _message(
            id: 'assistant-ai-source',
            content: '流式正文',
            createdAt: createdAt,
            sourceId: 'ai-source',
          ),
        ]);
        final remote = DingTalkMessageRenderTopology(<DingTalkGatewayMessage>[
          _message(
            id: 'remote-message-id',
            content: '完整正文',
            createdAt: createdAt,
            sourceId: 'ai-source',
          ),
        ]);

        expect(local.identityAt(0), 'ai:ai-source');
        expect(remote.identityAt(0), local.identityAt(0));
        expect(remote.reverseIndexOf(remote.identityAt(0)), 0);
      },
    );

    test('falls back from duplicate sources and always emits unique keys', () {
      final createdAt = DateTime.utc(2026, 9, 2, 11);
      final topology = DingTalkMessageRenderTopology(<DingTalkGatewayMessage>[
        _message(
          id: 'same-id',
          content: '第一条',
          createdAt: createdAt,
          sourceId: 'duplicate-source',
        ),
        _message(
          id: 'same-id',
          content: '第二条',
          createdAt: createdAt,
          sourceId: 'duplicate-source',
        ),
        _message(
          id: 'same-id#2',
          content: '可能与后缀碰撞',
          createdAt: createdAt,
          role: DingTalkGatewayMessageRole.user,
        ),
      ]);
      final identities = List<String>.generate(
        topology.length,
        topology.identityAt,
      );

      expect(identities.toSet(), hasLength(identities.length));
      expect(identities.first, 'message:same-id');
      expect(topology.reverseIndexOf(identities[0]), 2);
      expect(topology.reverseIndexOf(identities[1]), 1);
      expect(topology.reverseIndexOf(identities[2]), 0);
    });

    test('keeps reverse indices aligned when older messages are prepended', () {
      final base = DateTime.utc(2026, 9, 2, 12);
      final currentMessages = <DingTalkGatewayMessage>[
        _message(id: 'a', content: 'a', createdAt: base),
        _message(
          id: 'b',
          content: 'b',
          createdAt: base.add(const Duration(minutes: 1)),
        ),
        _message(
          id: 'c',
          content: 'c',
          createdAt: base.add(const Duration(minutes: 2)),
        ),
      ];
      final current = DingTalkMessageRenderTopology(currentMessages);
      final prepended = DingTalkMessageRenderTopology(<DingTalkGatewayMessage>[
        _message(
          id: 'older',
          content: 'older',
          createdAt: base.subtract(const Duration(minutes: 1)),
        ),
        ...currentMessages,
      ]);

      for (var index = 0; index < currentMessages.length; index++) {
        final currentIdentity = current.identityAt(index);
        final prependedIdentity = prepended.identityAt(index + 1);
        expect(prependedIdentity, currentIdentity);
        expect(
          prepended.reverseIndexOf(prependedIdentity),
          current.reverseIndexOf(currentIdentity),
        );
      }
    });
  });
}

DingTalkGatewayMessage _message({
  required String id,
  required String content,
  required DateTime createdAt,
  String sourceId = '',
  DingTalkGatewayMessageRole role = DingTalkGatewayMessageRole.assistant,
}) {
  return DingTalkGatewayMessage(
    id: id,
    conversationId: 'conversation',
    conversationType: DingTalkConversationType.direct,
    role: role,
    content: content,
    createdAt: createdAt,
    sourceAiMessageId: sourceId,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';

void main() {
  group('AiSessionMessage.selfLearning', () {
    test('factory produces a self_learning message with system role', () {
      final ts = DateTime.utc(2026, 4, 25, 12);
      final msg = AiSessionMessage.selfLearning(
        id: 'sl-1',
        content: '  summary of updates  ',
        createdAt: ts,
        metadata: const <String, Object?>{'memory_changes': 3},
      );
      expect(msg.kind, AiSessionMessageKind.selfLearning);
      expect(msg.role, AiSessionMessageRole.system);
      expect(msg.content, 'summary of updates'); // trimmed
      expect(msg.createdAt, ts);
      expect(msg.metadata['memory_changes'], 3);
    });

    test('isVisible is true for selfLearning messages', () {
      final msg = AiSessionMessage.selfLearning(
        id: 'sl-2',
        content: 'anything',
        createdAt: DateTime.utc(2026, 4, 25),
        metadata: const <String, Object?>{},
      );
      expect(msg.isVisible, isTrue);
    });

    test('isConversationTurn is true for selfLearning', () {
      final msg = AiSessionMessage.selfLearning(
        id: 'sl-3',
        content: 'x',
        createdAt: DateTime.utc(2026, 4, 25),
        metadata: const <String, Object?>{},
      );
      expect(msg.isConversationTurn, isTrue);
    });

    test('round-trips through toJson/fromJson preserving kind', () {
      final original = AiSessionMessage.selfLearning(
        id: 'sl-4',
        content: 'round trip',
        createdAt: DateTime.utc(2026, 4, 25, 9, 30),
        metadata: const <String, Object?>{
          'memory_changes': <Object?>['a', 'b'],
        },
      );
      final roundTripped = AiSessionMessage.fromJson(original.toJson());
      expect(roundTripped.kind, AiSessionMessageKind.selfLearning);
      expect(roundTripped.role, AiSessionMessageRole.system);
      expect(roundTripped.content, 'round trip');
      expect(roundTripped.createdAt, original.createdAt);
      expect(roundTripped.metadata['memory_changes'], <Object?>['a', 'b']);
    });

    test('fromStorage("self_learning") maps to selfLearning kind', () {
      expect(
        AiSessionMessageKind.fromStorage('self_learning'),
        AiSessionMessageKind.selfLearning,
      );
    });
  });
}

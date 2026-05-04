import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';

void main() {
  test('file mutation summary is visible but not a conversation turn', () {
    final message = AiSessionMessage.fileMutationSummary(
      id: 'summary-1',
      createdAt: DateTime.utc(2026),
    );

    expect(message.kind, AiSessionMessageKind.fileMutationSummary);
    expect(message.isVisible, isTrue);
    expect(message.isConversationTurn, isFalse);
    expect(message.metadata['round_file_mutation_summary'], isTrue);
  });

  test('legacy status summaries stay visible', () {
    final message = AiSessionMessage.status(
      id: 'summary-legacy',
      content: '',
      createdAt: DateTime.utc(2026),
      metadata: const <String, Object?>{'round_file_mutation_summary': true},
    );

    expect(message.kind, AiSessionMessageKind.status);
    expect(message.isVisible, isTrue);
    expect(message.isConversationTurn, isFalse);
  });
}

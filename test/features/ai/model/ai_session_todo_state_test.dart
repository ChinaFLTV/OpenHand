import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session.dart';

void main() {
  group('AiSessionTodoState', () {
    test('normalizes status strings before comparison', () {
      expect(AiSessionTodoState.isCompletedStatus(' Completed '), isTrue);
      expect(AiSessionTodoState.isIncompleteStatus(' pending '), isTrue);
      expect(AiSessionTodoState.isFailureStatus(' FAILED '), isTrue);
    });

    test('treats empty lists as not all completed', () {
      expect(
        AiSessionTodoState.hasIncomplete(const <AiSessionTodoItem>[]),
        isFalse,
      );
      expect(
        AiSessionTodoState.allCompleted(const <AiSessionTodoItem>[]),
        isFalse,
      );
      expect(
        AiSessionTodoState.hasFailure(const <AiSessionTodoItem>[]),
        isFalse,
      );
    });

    test('summarizes active and completed todo lists', () {
      const todos = <AiSessionTodoItem>[
        AiSessionTodoItem(id: '1', content: 'Inspect', status: 'completed'),
        AiSessionTodoItem(id: '2', content: 'Patch', status: 'in_progress'),
      ];

      expect(AiSessionTodoState.hasIncomplete(todos), isTrue);
      expect(AiSessionTodoState.allCompleted(todos), isFalse);
      expect(AiSessionTodoState.hasFailure(todos), isFalse);
    });

    test('keeps legacy failed statuses grouped as failures', () {
      const todos = <AiSessionTodoItem>[
        AiSessionTodoItem(id: '1', content: 'Retry build', status: 'blocked'),
        AiSessionTodoItem(
          id: '2',
          content: 'Run smoke test',
          status: 'cancelled',
        ),
      ];

      expect(AiSessionTodoState.hasIncomplete(todos), isTrue);
      expect(AiSessionTodoState.allCompleted(todos), isFalse);
      expect(AiSessionTodoState.hasFailure(todos), isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session_goal.dart';

void main() {
  test('goal state parsing ignores non-finite numeric fields', () {
    final state = AiSessionGoalState.fromJson(<String, Object?>{
      'current': <String, Object?>{
        'id': 'goal-1',
        'objective': 'Keep parsing safe',
        'status': 'running',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'max_turns': double.infinity,
        'token_budget': double.nan,
        'turn_count': double.infinity,
        'tokens_used': double.nan,
        'evaluations': <Object?>[
          <String, Object?>{
            'id': 'eval-1',
            'created_at': '2026-01-01T00:00:00Z',
            'round_index': double.infinity,
            'passed': true,
            'summary': 'ok',
            'confidence': double.nan,
          },
        ],
      },
    });

    final goal = state.current;
    expect(goal, isNotNull);
    expect(goal!.maxTurns, isNull);
    expect(goal.tokenBudget, isNull);
    expect(goal.turnCount, 0);
    expect(goal.tokensUsed, 0);
    expect(goal.evaluations.single.roundIndex, 0);
    expect(goal.evaluations.single.confidence, isNull);
  });

  test('goal state parsing keeps finite rounded numeric counters', () {
    final state = AiSessionGoalState.fromJson(<String, Object?>{
      'current': <String, Object?>{
        'id': 'goal-1',
        'objective': 'Keep finite values',
        'status': 'running',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'max_turns': 2.4,
        'token_budget': 8.6,
        'turn_count': 3.5,
        'tokens_used': '12',
      },
    });

    final goal = state.current;
    expect(goal, isNotNull);
    expect(goal!.maxTurns, 2);
    expect(goal.tokenBudget, 9);
    expect(goal.turnCount, 4);
    expect(goal.tokensUsed, 12);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session_goal.dart';

void main() {
  group('AiSessionGoalEvaluationRecord', () {
    test('fromJson clamps confidence into the unit interval', () {
      expect(_evaluationWithConfidence(-0.25)?.confidence, 0);
      expect(_evaluationWithConfidence('0.42')?.confidence, 0.42);
      expect(_evaluationWithConfidence(1.25)?.confidence, 1);
      expect(_evaluationWithConfidence('bad')?.confidence, isNull);
    });

    test('fromJson limits evidence and missing lists', () {
      final evaluation =
          AiSessionGoalEvaluationRecord.fromJson(<String, Object?>{
            'id': 'eval-1',
            'summary': 'not yet',
            'evidence': List<String>.generate(12, (index) => 'e$index'),
            'missing': List<String>.generate(12, (index) => 'm$index'),
          });

      expect(evaluation, isNotNull);
      expect(
        evaluation!.evidence,
        hasLength(aiSessionGoalEvaluationMaxEvidenceItems),
      );
      expect(
        evaluation.missing,
        hasLength(aiSessionGoalEvaluationMaxEvidenceItems),
      );
    });
  });
}

AiSessionGoalEvaluationRecord? _evaluationWithConfidence(Object? confidence) {
  return AiSessionGoalEvaluationRecord.fromJson(<String, Object?>{
    'id': 'eval-1',
    'summary': 'ok',
    'confidence': confidence,
  });
}

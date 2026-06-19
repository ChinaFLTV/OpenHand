import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/runtime/ai_plan_approval_detector.dart';

void main() {
  group('AiPlanApprovalDetector', () {
    test('recognizes explicit plan approval', () {
      expect(AiPlanApprovalDetector.looksLikePlanApproval('approved'), isTrue);
      expect(AiPlanApprovalDetector.looksLikePlanApproval('去做吧'), isTrue);
      expect(AiPlanApprovalDetector.looksLikePlanApproval('OK'), isTrue);
    });

    test('does not treat negative or wait messages as approval', () {
      expect(
        AiPlanApprovalDetector.looksLikePlanApproval('do not approve'),
        isFalse,
      );
      expect(
        AiPlanApprovalDetector.looksLikePlanApproval("don't proceed"),
        isFalse,
      );
      expect(AiPlanApprovalDetector.looksLikePlanApproval('先别执行'), isFalse);
      expect(AiPlanApprovalDetector.looksLikePlanApproval('等一下'), isFalse);
    });

    test('keeps continuation and recovery signals distinct from negation', () {
      expect(
        AiPlanApprovalDetector.looksLikePlanExecutionContinuation('继续推进'),
        isTrue,
      );
      expect(
        AiPlanApprovalDetector.looksLikePlanExecutionContinuation(
          "don't continue",
        ),
        isFalse,
      );
      expect(
        AiPlanApprovalDetector.looksLikePlanRecoveryContinuation(
          'retry the failed step',
        ),
        isTrue,
      );
      expect(
        AiPlanApprovalDetector.looksLikePlanRecoveryContinuation(
          'retry the cancelled step',
        ),
        isTrue,
      );
      expect(
        AiPlanApprovalDetector.looksLikePlanRecoveryContinuation(
          'wait first, do not continue',
        ),
        isFalse,
      );
    });
  });
}

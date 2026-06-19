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

    test('recognizes plan approval requests in assistant text', () {
      expect(
        AiPlanApprovalDetector.looksLikePlanApprovalRequest(
          'Is this plan okay? Should I proceed with implementation?',
        ),
        isTrue,
      );
      expect(
        AiPlanApprovalDetector.looksLikePlanApprovalRequest('计划可以吗？是否继续？'),
        isTrue,
      );
    });

    test(
      'does not treat planning rules or clarifications as approval requests',
      () {
        expect(
          AiPlanApprovalDetector.looksLikePlanApprovalRequest(
            'Do not ask for plan approval in plain chat.',
          ),
          isFalse,
        );
        expect(
          AiPlanApprovalDetector.looksLikePlanApprovalRequest(
            'Pick the approach the implementation plan should use.',
          ),
          isFalse,
        );
      },
    );
  });
}

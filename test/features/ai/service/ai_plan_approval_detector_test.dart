import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_plan_approval_detector.dart';

void main() {
  group('AiPlanApprovalDetector.looksLikePlanApproval', () {
    test('treats bare standalone Chinese acknowledgements as approval', () {
      // 2026-04-28 regression: the controller copy was missing bare "继续",
      // which left the next turn's tool catalog empty and made the model
      // hallucinate Write/TodoWrite calls.
      const approvals = <String>[
        '继续',
        '继续。',
        '继续~',
        '好',
        '好的',
        '好嘞！',
        '可以',
        '行',
        '中',
        '嗯',
        '嗯嗯',
        '同意',
        '批准',
        '通过',
        '确认',
      ];
      for (final reply in approvals) {
        expect(
          AiPlanApprovalDetector.looksLikePlanApproval(reply),
          isTrue,
          reason: '"$reply" should count as plan approval',
        );
      }
    });

    test('treats bare standalone English acknowledgements as approval', () {
      const approvals = <String>[
        'OK',
        'ok.',
        'Okay',
        'yes',
        'YES',
        'yep',
        'yeah',
        'sure',
        'go',
        'continue',
        'proceed',
        'k',
        'kk',
      ];
      for (final reply in approvals) {
        expect(
          AiPlanApprovalDetector.looksLikePlanApproval(reply),
          isTrue,
          reason: '"$reply" should count as plan approval',
        );
      }
    });

    test('matches longer endorsement phrases via substring', () {
      const phrases = <String>[
        '去写吧',
        '去做吧 ✨',
        '动手吧！',
        'do it',
        "let's go",
        'ship it',
        'start implementing now please',
      ];
      for (final reply in phrases) {
        expect(
          AiPlanApprovalDetector.looksLikePlanApproval(reply),
          isTrue,
          reason: '"$reply" should count as plan approval',
        );
      }
    });

    test('does NOT treat continuations or hedged replies as approval', () {
      // These all contain or look like approval words but are clearly NOT a
      // green light to start implementing. NOTE: detector intentionally
      // uses substring matching for long phrases, so we deliberately avoid
      // negatives that embed an unambiguous approval token (e.g. "do it",
      // "动手", "继续执行") — that is an accepted limitation of the
      // heuristic.
      const negatives = <String>[
        '',
        '   ',
        '继续观察一下',
        '继续等',
        '继续讨论',
        '再想想',
        '不行',
        '暂停',
        '稍等',
        '等等',
        'no go',
        'hold on, let me check',
      ];
      for (final reply in negatives) {
        expect(
          AiPlanApprovalDetector.looksLikePlanApproval(reply),
          isFalse,
          reason: '"$reply" must NOT count as plan approval',
        );
      }
    });
  });
}

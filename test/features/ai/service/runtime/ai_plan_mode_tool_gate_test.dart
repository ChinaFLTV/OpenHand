import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/runtime/ai_plan_mode_tool_gate.dart';

void main() {
  group('AiPlanModeToolGate', () {
    test('allows direct read-only code intelligence tools while planning', () {
      expect(AiPlanModeToolGate.isPlanningTool('LSP'), isTrue);
      expect(AiPlanModeToolGate.isPlanningTool('Lsp'), isTrue);
      expect(AiPlanModeToolGate.isPlanningTool('CodebaseSearch'), isTrue);
      expect(
        AiPlanModeToolGate.isAllowedPlanningTool(
          'LSP',
          allowExitPlanMode: false,
        ),
        isTrue,
      );
      expect(
        AiPlanModeToolGate.isAllowedPlanningTool(
          'CodebaseSearch',
          allowExitPlanMode: false,
        ),
        isTrue,
      );
    });

    test('keeps implementation tools blocked while planning', () {
      expect(AiPlanModeToolGate.isPlanningTool('Edit'), isFalse);
      expect(AiPlanModeToolGate.isPlanningTool('Bash'), isFalse);
      expect(
        AiPlanModeToolGate.isAllowedPlanningTool(
          'ExitPlanMode',
          allowExitPlanMode: false,
        ),
        isFalse,
      );
      expect(
        AiPlanModeToolGate.isAllowedPlanningTool(
          'ExitPlanMode',
          allowExitPlanMode: true,
        ),
        isTrue,
      );
    });

    test('does not classify planning research tools as execution tools', () {
      expect(
        AiPlanModeToolGate.hasExecutionTool(<String>[
          'Read',
          'LSP',
          'CodebaseSearch',
          'TodoWrite',
        ]),
        isFalse,
      );
      expect(
        AiPlanModeToolGate.hasExecutionTool(<String>[
          'Read',
          'CodebaseSearch',
          'Edit',
        ]),
        isTrue,
      );
    });
  });
}

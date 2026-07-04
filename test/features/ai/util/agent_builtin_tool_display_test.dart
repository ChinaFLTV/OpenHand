import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart' show AiBuiltinToolKind;
import 'package:openhand/features/ai/util/agent_builtin_tool_display.dart';

void main() {
  testWidgets('localizes agent builtin tool labels and summaries', (
    tester,
  ) async {
    late BuildContext zhContext;
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('zh'),
        delegates: const <LocalizationsDelegate<dynamic>>[
          DefaultWidgetsLocalizations.delegate,
        ],
        child: Builder(
          builder: (context) {
            zhContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      agentBuiltinToolCanonicalName(AiBuiltinToolKind.agentTaskPublish),
      'AgentTaskPublish',
    );
    expect(
      agentBuiltinToolLabel(zhContext, AiBuiltinToolKind.agentTaskPublish),
      '任务发布',
    );
    expect(
      agentBuiltinToolSummary(zhContext, AiBuiltinToolKind.agentTaskPublish),
      '向匹配智能体派发任务',
    );

    late BuildContext enContext;
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: const <LocalizationsDelegate<dynamic>>[
          DefaultWidgetsLocalizations.delegate,
        ],
        child: Builder(
          builder: (context) {
            enContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      agentBuiltinToolLabel(enContext, AiBuiltinToolKind.agentTaskPublish),
      'Task publish',
    );
    expect(
      agentBuiltinToolSummary(enContext, AiBuiltinToolKind.agentTaskPublish),
      'Delegate matched work',
    );
  });
}

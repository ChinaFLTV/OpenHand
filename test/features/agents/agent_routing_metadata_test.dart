import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/index.dart';

void main() {
  test('parses yaml front matter and builds stable routing keywords', () {
    const agent = AgentProfile(
      id: 'agent-1',
      name: 'Finance Agent',
      routeFrontMatter: '''
---
route: finance
priority: 20
keywords:
  - invoice
  - reconciliation
domains: cloud, finops
---
''',
      taskLabels: <String>['finance', 'audit'],
      skillNames: <String>['invoice'],
    );

    final routing = AgentRoutingMetadata.fromAgent(agent);

    expect(routing.hasRoute, isTrue);
    expect(routing.frontMatter['route'], 'finance');
    expect(routing.frontMatter['priority'], 20);
    expect(routing.keywords, <String>[
      'invoice',
      'reconciliation',
      'cloud',
      'finops',
      'finance',
      'audit',
    ]);
  });

  test('parses json routing metadata', () {
    final parsed = parseAgentRouteFrontMatter(
      '{"intents":["deploy","rollback"],"priority":10}',
    );

    expect(parsed['intents'], <Object?>['deploy', 'rollback']);
    expect(parsed['priority'], 10);
  });

  test('prompt metadata exposes structured routing profile', () async {
    final renderer = AgentPromptRenderer(
      loader: (_) async => '''
<agent_profile>
{{AGENT_PROFILE_JSON}}
</agent_profile>
<capability_bindings>
{{CAPABILITY_BINDINGS_JSON}}
</capability_bindings>
<runtime_policy>
{{RUNTIME_POLICY_JSON}}
</runtime_policy>
<task_context>
{{TASK_CONTEXT_JSON}}
</task_context>
''',
    );

    final snapshot = await renderer.render(
      agent: const AgentProfile(
        id: 'agent-1',
        name: 'Release Agent',
        routeFrontMatter: 'keywords: release, deploy',
        taskLabels: <String>['release'],
      ),
    );

    final profile = snapshot.metadataJson()['profile'] as Map<String, Object?>;
    final routing = profile['routing'] as Map<String, Object?>;

    expect(routing['has_route'], isTrue);
    expect(routing['keywords'], <Object?>['release', 'deploy']);
    expect(snapshot.renderedPrompt, contains('"routing"'));
  });
}

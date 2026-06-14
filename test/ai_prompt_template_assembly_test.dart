import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';

void main() {
  test('programming expert registers resource adaptation workflow section', () {
    final sections = aiPromptExtensionSectionsForTemplate('programming_expert');

    expect(
      sections.map((section) => section.tag),
      contains('resource_adaptation_workflow'),
    );
    expect(
      sections.map((section) => section.assetPath),
      contains(
        'assets/prompts/programming_expert/sections/resource_adaptation_workflow.md',
      ),
    );
  });

  test('append sections skips an existing XML tag', () {
    final output = appendAiPromptSharedSectionsIfAbsent(
      '<resource_adaptation_workflow>\nexisting\n</resource_adaptation_workflow>',
      const <AiPromptLoadedSection>[
        AiPromptLoadedSection(
          tag: 'resource_adaptation_workflow',
          content:
              '<resource_adaptation_workflow>\nreplacement\n</resource_adaptation_workflow>',
        ),
      ],
    );

    expect(output, contains('existing'));
    expect(output, isNot(contains('replacement')));
  });
}

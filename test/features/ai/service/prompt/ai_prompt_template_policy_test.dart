import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  group('AiPromptTemplatePolicy', () {
    test('declares explicit policy for every bundled template', () {
      final repository = AiPromptTemplateRepository(loader: (_) async => '');
      final templateIds = repository.templates
          .map((template) => template.id)
          .toSet();

      expect(
        AiPromptTemplatePolicies.byId.keys.toSet(),
        containsAll(templateIds),
      );
      for (final template in repository.templates) {
        final policy = AiPromptTemplatePolicies.resolve(template.id);
        expect(policy.templateId, template.id);
        expect(policy.promptAssetDirectory, template.promptAssetDirectory);
      }
    });

    test('points every template policy to complete prompt assets', () {
      for (final policy in AiPromptTemplatePolicies.byId.values) {
        for (final fileName in <String>[
          'system_instructions.md',
          'developer_instructions.md',
          'compression_summary_instructions.md',
        ]) {
          expect(
            File('${policy.promptAssetDirectory}/$fileName').existsSync(),
            isTrue,
            reason: '${policy.templateId}: $fileName',
          );
        }
      }
    });

    test('centralizes cache-friendly session-state layout per template', () {
      for (final templateId in <String>[
        AiPromptTemplatePolicies.defaultTemplateId,
        AiPromptTemplatePolicies.programmingExpertTemplateId,
        AiPromptTemplatePolicies.hermesTalkerTemplateId,
        AiPromptTemplatePolicies.siriHelperTemplateId,
      ]) {
        expect(
          AiPromptTemplatePolicies.resolve(templateId).usesCompactSessionState,
          isTrue,
          reason: templateId,
        );
      }

      for (final templateId in <String>[
        AiPromptTemplatePolicies.machineExpertTemplateId,
        AiPromptTemplatePolicies.hardnessEngineeringTemplateId,
        AiPromptTemplatePolicies.webReverseExpertTemplateId,
      ]) {
        expect(
          AiPromptTemplatePolicies.resolve(templateId).usesCompactSessionState,
          isFalse,
          reason: templateId,
        );
      }
    });

    test('keeps shared and extension prompt sections policy-driven', () {
      final hermesTags = aiPromptSharedSectionsForTemplate(
        AiPromptTemplatePolicies.hermesTalkerTemplateId,
      ).map((section) => section.tag);
      expect(
        hermesTags,
        containsAll(<String>[
          'identity',
          'refusal_handling',
          'tone_and_formatting',
        ]),
      );
      expect(hermesTags, isNot(contains('workflow')));

      final programmingExtensionTags = aiPromptExtensionSectionsForTemplate(
        AiPromptTemplatePolicies.programmingExpertTemplateId,
      ).map((section) => section.tag);
      expect(
        programmingExtensionTags,
        containsAll(<String>[
          'runtime_turn_model',
          'intent_workflows',
          'project_resource_trust',
          'resource_adaptation_workflow',
          'context_recovery',
        ]),
      );
    });
  });
}

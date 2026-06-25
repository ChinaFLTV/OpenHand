import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  test('prompt template catalog entries are unique and consistent', () {
    const entries = AiPromptTemplatePolicies.entries;
    expect(entries, isNotEmpty);

    final ids = <String>{};
    for (final entry in entries) {
      expect(entry.isConsistent, isTrue, reason: entry.id);
      expect(ids.add(entry.id), isTrue, reason: 'duplicate id: ${entry.id}');
      expect(entry.info.name.trim(), isNotEmpty, reason: entry.id);
      expect(entry.info.description.trim(), isNotEmpty, reason: entry.id);
      expect(entry.info.internalVersion.trim(), isNotEmpty);
      expect(entry.policy.compressionIdentity.trim(), isNotEmpty);
    }

    expect(AiPromptTemplatePolicies.byTemplateId.keys.toSet(), ids);
    expect(AiPromptTemplatePolicies.byId.keys.toSet(), ids);
    expect(
      AiPromptTemplatePolicies.templateInfos.map((template) => template.id),
      orderedEquals(entries.map((entry) => entry.id)),
    );
  });

  test('prompt repository resolves templates from the shared catalog', () {
    final repository = AiPromptTemplateRepository(loader: (_) async => '');

    expect(
      repository.templates.map((template) => template.id),
      orderedEquals(AiPromptTemplatePolicies.entries.map((entry) => entry.id)),
    );
    expect(
      repository.resolveTemplate('missing-template').id,
      AiPromptTemplatePolicies.defaultTemplateId,
    );
  });

  test('platform-only templates fall back to the first supported template', () {
    final repository = AiPromptTemplateRepository(loader: (_) async => '');

    final resolved = repository.resolveTemplateForPlatform(
      AiPromptTemplatePolicies.siriHelperTemplateId,
      platform: TargetPlatform.windows,
    );

    expect(resolved.id, AiPromptTemplatePolicies.defaultTemplateId);
  });

  test('siri helper inherits default developer and compression prompts', () {
    final policy = AiPromptTemplatePolicies.resolve(
      AiPromptTemplatePolicies.siriHelperTemplateId,
    );

    expect(
      policy.promptAssetPathFor(AiPromptTemplateAssetFiles.systemInstructions),
      '${AiPromptTemplatePolicies.siriHelperPromptAssetDirectory}/'
      '${AiPromptTemplateAssetFiles.systemInstructions}',
    );
    expect(
      policy.promptAssetPathFor(
        AiPromptTemplateAssetFiles.developerInstructions,
      ),
      '${AiPromptTemplatePolicies.defaultPromptAssetDirectory}/'
      '${AiPromptTemplateAssetFiles.developerInstructions}',
    );
    expect(
      policy.promptAssetPathFor(
        AiPromptTemplateAssetFiles.compressionSummaryInstructions,
      ),
      '${AiPromptTemplatePolicies.defaultPromptAssetDirectory}/'
      '${AiPromptTemplateAssetFiles.compressionSummaryInstructions}',
    );
  });

  test('template icon names resolve through a safe catalog', () {
    expect(
      AiThreadTemplateIcons.resolve(AiThreadTemplateIcons.codeRounded),
      Icons.code_rounded,
    );
    expect(
      AiThreadTemplateIcons.resolve('unknown'),
      AiThreadTemplateIcons.fallback,
    );
    expect(AiThreadTemplateIcons.resolve(''), AiThreadTemplateIcons.fallback);
  });
}

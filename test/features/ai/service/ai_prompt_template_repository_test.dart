import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';

void main() {
  test('loads all bundled thread template prompt assets', () async {
    final repository = AiPromptTemplateRepository(loader: _loadWorkspaceAsset);
    expect(
      repository.templates.map((template) => template.id),
      containsAll(<String>[
        'default',
        'machine_expert',
        'hardness_engineering',
        'programming_expert',
        'hermes_talker',
      ]),
    );

    for (final template in repository.templates) {
      final bundle = await repository.loadBundle(template.id);
      expect(bundle.systemInstructions, isNot(contains(_fallbackMarker)));
      expect(bundle.developerInstructions, isNot(contains(_fallbackMarker)));
      expect(
        bundle.compressionSummaryInstructions,
        isNot(contains(_fallbackMarker)),
      );
      expect(bundle.systemInstructions.length, greaterThan(100));
      expect(bundle.developerInstructions.length, greaterThan(100));
      expect(bundle.compressionSummaryInstructions, contains('<role>'));
      expect(
        _hasCompressionContract(bundle.compressionSummaryInstructions),
        isTrue,
        reason: '${template.id} compression summary needs preserve/rules shape',
      );
      expect(
        _hasUserMessageCompressionContract(
          bundle.compressionSummaryInstructions,
        ),
        isTrue,
        reason:
            '${template.id} compression summary must preserve user messages',
      );
    }
  });

  test('does not duplicate shared injected prompt sections', () async {
    final repository = AiPromptTemplateRepository(loader: _loadWorkspaceAsset);

    for (final template in repository.templates) {
      final bundle = await repository.loadBundle(template.id);
      expect(
        _countIgnoreCase(bundle.systemInstructions, '## Memory Tone Policy'),
        lessThanOrEqualTo(1),
        reason: '${template.id} should not duplicate memory tone policy',
      );
      expect(
        _countIgnoreCase(
          bundle.systemInstructions,
          '<atomic_change_discipline>',
        ),
        lessThanOrEqualTo(1),
        reason: '${template.id} should not duplicate v4 discipline',
      );
      expect(
        _countIgnoreCase(bundle.systemInstructions, '<uncertainty_honesty>'),
        lessThanOrEqualTo(1),
        reason: '${template.id} should not duplicate uncertainty honesty',
      );
    }
  });

  test(
    'recognizes markdown discipline heading and existing memory policy',
    () async {
      final repository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          if (assetPath.endsWith('system_instructions.md')) {
            return '''# Custom System

## Atomic Change Discipline
Keep changes focused.

## Memory Tone Policy
Already present.
''';
          }
          if (assetPath.endsWith('developer_instructions.md')) {
            return 'Developer instructions are present and specific enough.';
          }
          if (assetPath.endsWith('compression_summary_instructions.md')) {
            return '<role>Summarize.</role>\n<rules>Keep facts.</rules>';
          }
          if (assetPath.endsWith('v4_discipline_en.md')) {
            return '<atomic_change_discipline>SHOULD_NOT_APPEND</atomic_change_discipline>';
          }
          if (assetPath.endsWith('v4_discipline_zh.md')) {
            return '<atomic_change_discipline>SHOULD_NOT_APPEND_ZH</atomic_change_discipline>';
          }
          return '';
        },
      );

      final bundle = await repository.loadBundle('default');

      expect(bundle.systemInstructions, isNot(contains('SHOULD_NOT_APPEND')));
      expect(
        bundle.systemInstructions,
        isNot(contains('SHOULD_NOT_APPEND_ZH')),
      );
      expect(
        _countIgnoreCase(bundle.systemInstructions, '## Memory Tone Policy'),
        1,
      );
    },
  );
}

const String _fallbackMarker = '[OpenHand prompt asset failed to load]';

Future<String> _loadWorkspaceAsset(String assetPath) {
  return File(assetPath).readAsString();
}

bool _hasCompressionContract(String content) {
  final lower = content.toLowerCase();
  return lower.contains('<role>') &&
      (lower.contains('<preserve>') || lower.contains('<general_rules>')) &&
      (lower.contains('<rules>') || lower.contains('<must_keep_checklist>'));
}

int _countIgnoreCase(String haystack, String needle) {
  final normalizedHaystack = haystack.toLowerCase();
  final normalizedNeedle = needle.toLowerCase();
  var count = 0;
  var index = 0;
  while (true) {
    index = normalizedHaystack.indexOf(normalizedNeedle, index);
    if (index < 0) {
      return count;
    }
    count++;
    index += normalizedNeedle.length;
  }
}

bool _hasUserMessageCompressionContract(String content) {
  final lower = content.toLowerCase();
  return lower.contains('user messages') || lower.contains('用户消息');
}

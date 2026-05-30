import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  group('AiPromptTemplateRepository', () {
    test('appends shared sections when tags are absent', () async {
      final repository = AiPromptTemplateRepository(
        loader: (path) async {
          if (path.endsWith('system_instructions.md')) {
            return '<tool_use>base</tool_use>';
          }
          if (path.endsWith('developer_instructions.md')) {
            return 'developer';
          }
          if (path.endsWith('compression_summary_instructions.md')) {
            return 'compression';
          }
          if (path.endsWith('_shared/identity.md')) {
            return '<identity>identity</identity>';
          }
          if (path.endsWith('_shared/refusal.md')) {
            return '<refusal_handling>refusal</refusal_handling>';
          }
          if (path.endsWith('_shared/tone.md')) {
            return '<tone_and_formatting>tone</tone_and_formatting>';
          }
          if (path.endsWith('_shared/workflow.md')) {
            return '<workflow>workflow</workflow>';
          }
          if (path.endsWith('v4_discipline_zh.md')) {
            return '<uncertainty_honesty>discipline</uncertainty_honesty>';
          }
          return '';
        },
      );

      final bundle = await repository.loadBundle('hardness_engineering');
      expect(bundle.systemInstructions, contains('<identity>identity</identity>'));
      expect(
        bundle.systemInstructions,
        contains('<refusal_handling>refusal</refusal_handling>'),
      );
      expect(
        bundle.systemInstructions,
        contains('<tone_and_formatting>tone</tone_and_formatting>'),
      );
      expect(bundle.systemInstructions, contains('<workflow>workflow</workflow>'));
    });

    test('does not append shared sections for machine expert', () async {
      final repository = AiPromptTemplateRepository(
        loader: (path) async {
          if (path.endsWith('system_instructions.md')) {
            return '<role_definition>machine</role_definition>';
          }
          if (path.endsWith('developer_instructions.md')) {
            return 'developer';
          }
          if (path.endsWith('compression_summary_instructions.md')) {
            return 'compression';
          }
          if (path.endsWith('_shared/identity.md')) {
            return '<identity>identity</identity>';
          }
          if (path.endsWith('v4_discipline_zh.md')) {
            return '<uncertainty_honesty>discipline</uncertainty_honesty>';
          }
          return '';
        },
      );

      final bundle = await repository.loadBundle('machine_expert');
      expect(bundle.systemInstructions, isNot(contains('<identity>identity</identity>')));
    });

    test('does not append shared sections that already exist in source', () async {
      final repository = AiPromptTemplateRepository(
        loader: (path) async {
          if (path.endsWith('system_instructions.md')) {
            return [
              '<identity>base identity</identity>',
              '<workflow>base workflow</workflow>',
            ].join('\n\n');
          }
          if (path.endsWith('developer_instructions.md')) {
            return 'developer';
          }
          if (path.endsWith('compression_summary_instructions.md')) {
            return 'compression';
          }
          if (path.endsWith('_shared/identity.md')) {
            return '<identity>shared identity</identity>';
          }
          if (path.endsWith('_shared/workflow.md')) {
            return '<workflow>shared workflow</workflow>';
          }
          if (path.endsWith('v4_discipline_en.md')) {
            return '## Atomic Change Discipline\nrule';
          }
          return '';
        },
      );

      final bundle = await repository.loadBundle('default');
      expect(
        RegExp('<identity>', caseSensitive: false)
            .allMatches(bundle.systemInstructions)
            .length,
        1,
      );
      expect(
        RegExp('<workflow>', caseSensitive: false)
            .allMatches(bundle.systemInstructions)
            .length,
        1,
      );
      expect(bundle.systemInstructions, contains('base workflow'));
    });

    test('does not append v4 discipline when universal discipline tag exists', () async {
      final repository = AiPromptTemplateRepository(
        loader: (path) async {
          if (path.endsWith('system_instructions.md')) {
            return '<identity>base</identity>\n\n<universal_discipline>built in</universal_discipline>';
          }
          if (path.endsWith('developer_instructions.md')) {
            return 'developer';
          }
          if (path.endsWith('compression_summary_instructions.md')) {
            return 'compression';
          }
          if (path.endsWith('v4_discipline_zh.md')) {
            return '<uncertainty_honesty>discipline</uncertainty_honesty>';
          }
          return '';
        },
      );

      final bundle = await repository.loadBundle('machine_expert');
      expect(
        RegExp('<uncertainty_honesty>', caseSensitive: false)
            .allMatches(bundle.systemInstructions)
            .length,
        0,
      );
      expect(bundle.systemInstructions, contains('<universal_discipline>'));
    });

    test('appends v4 discipline when markers are absent', () async {
      final repository = AiPromptTemplateRepository(
        loader: (path) async {
          if (path.endsWith('system_instructions.md')) {
            return '<identity>base</identity>';
          }
          if (path.endsWith('developer_instructions.md')) {
            return 'developer';
          }
          if (path.endsWith('compression_summary_instructions.md')) {
            return 'compression';
          }
          if (path.endsWith('v4_discipline_en.md')) {
            return '## Atomic Change Discipline\nrule';
          }
          return '';
        },
      );

      final bundle = await repository.loadBundle('default');
      expect(bundle.systemInstructions, contains('## Atomic Change Discipline'));
      expect(bundle.systemInstructions, contains('## Memory Tone Policy'));
    });

    test('does not append v4 discipline when xml markers already exist', () async {
      final repository = AiPromptTemplateRepository(
        loader: (path) async {
          if (path.endsWith('system_instructions.md')) {
            return '<identity>base</identity>\n\n<uncertainty_honesty>rule</uncertainty_honesty>';
          }
          if (path.endsWith('developer_instructions.md')) {
            return 'developer';
          }
          if (path.endsWith('compression_summary_instructions.md')) {
            return 'compression';
          }
          if (path.endsWith('v4_discipline_en.md')) {
            return '## Atomic Change Discipline\nrule';
          }
          return '';
        },
      );

      final bundle = await repository.loadBundle('default');
      expect(
        RegExp('Atomic Change Discipline', caseSensitive: false)
            .allMatches(bundle.systemInstructions)
            .length,
        0,
      );
      expect(bundle.systemInstructions, contains('<uncertainty_honesty>'));
      expect(bundle.systemInstructions, contains('## Memory Tone Policy'));
    });
  });
}

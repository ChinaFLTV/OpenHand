import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  group('AiPromptTemplateRepository', () {
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

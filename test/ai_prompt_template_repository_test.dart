import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';

void main() {
  test('AiPromptTemplateRepository falls back when prompt assets are missing', () async {
    final repository = AiPromptTemplateRepository(
      loader: (_) async => throw Exception('missing asset'),
    );

    final bundle = await repository.loadBundle('default');

    expect(bundle.template.id, 'default');
    expect(bundle.systemInstructions, isNotEmpty);
    expect(bundle.developerInstructions, isNotEmpty);
    expect(bundle.compressionSummaryInstructions, isNotEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test(
    'reads cache tokens from input details when prompt details omit them',
    () {
      final usage = AiTokenUsageParser.parseOpenAi(<String, Object?>{
        'prompt_tokens': 2048,
        'completion_tokens': 12,
        'prompt_tokens_details': <String, Object?>{'audio_tokens': 0},
        'input_tokens_details': <String, Object?>{'cached_tokens': 1024},
      });

      expect(usage, isNotNull);
      expect(usage!.promptTokens, 2048);
      expect(usage.cacheReadTokens, 1024);
    },
  );

  test('reads reasoning tokens from output details fallback', () {
    final usage = AiTokenUsageParser.parseOpenAi(<String, Object?>{
      'input_tokens': 100,
      'output_tokens': 20,
      'completion_tokens_details': <String, Object?>{'accepted_tokens': 20},
      'output_tokens_details': <String, Object?>{'reasoning_tokens': 7},
    });

    expect(usage, isNotNull);
    expect(usage!.reasoningTokens, 7);
  });
}

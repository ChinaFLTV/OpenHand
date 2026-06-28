import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('token usage parser accepts only integral token counts', () {
    final usage = AiTokenUsageParser.parseOpenAi(<String, Object?>{
      'prompt_tokens': '12.0',
      'completion_tokens': 3.5,
      'total_tokens': double.infinity,
      'completion_tokens_details': <String, Object?>{'reasoning_tokens': '4.0'},
    });

    expect(usage, isNotNull);
    expect(usage!.promptTokens, 12);
    expect(usage.completionTokens, isNull);
    expect(usage.totalTokens, 12);
    expect(usage.reasoningTokens, 4);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('fromJson accepts JSON text and loose integral token values', () {
    final usage = AiTokenUsage.fromJson('''
      {
        "prompt_tokens": "12",
        "completion_tokens": 3.0,
        "total_tokens": 15,
        "cache_creation_tokens": "2.0",
        "cache_read_tokens": 0,
        "reasoning_tokens": "4"
      }
    ''');

    expect(usage.promptTokens, 12);
    expect(usage.completionTokens, 3);
    expect(usage.totalTokens, 15);
    expect(usage.cacheCreationTokens, 2);
    expect(usage.cacheReadTokens, 0);
    expect(usage.reasoningTokens, 4);
  });

  test('fromJson ignores negative, fractional and non-finite token values', () {
    final usage = AiTokenUsage.fromJson(<Object?, Object?>{
      'prompt_tokens': -1,
      'completion_tokens': 3.5,
      'total_tokens': double.infinity,
      'cache_creation_tokens': 'NaN',
      'cache_read_tokens': '2.25',
      'reasoning_tokens': null,
    });

    expect(usage.isEmpty, isTrue);
  });
}

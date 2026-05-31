import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/session_io/ai_token_usage_parser.dart';

void main() {
  test('parses openai compatible usage with nested cached tokens and reasoning', () {
    final usage = AiTokenUsageParser.parseOpenAi(<String, Object?>{
      'prompt_tokens': 120,
      'completion_tokens': 45,
      'total_tokens': 165,
      'prompt_tokens_details': <String, Object?>{
        'cached_tokens': 70,
        'cache_creation_tokens': 15,
      },
      'completion_tokens_details': <String, Object?>{'reasoning_tokens': 9},
    });

    expect(usage, isNotNull);
    expect(usage!.promptTokens, 120);
    expect(usage.completionTokens, 45);
    expect(usage.totalTokens, 165);
    expect(usage.cacheReadTokens, 70);
    expect(usage.cacheCreationTokens, 15);
    expect(usage.reasoningTokens, 9);
  });

  test('parses claude usage with detailed cache creation fallback', () {
    final usage = AiTokenUsageParser.parseClaude(<String, Object?>{
      'input_tokens': 210,
      'output_tokens': 36,
      'cache_read_input_tokens': 140,
      'cache_creation': <String, Object?>{
        'ephemeral_5m_input_tokens': 30,
        'ephemeral_1h_input_tokens': 12,
      },
    });

    expect(usage, isNotNull);
    expect(usage!.promptTokens, 210);
    expect(usage.completionTokens, 36);
    expect(usage.cacheReadTokens, 140);
    expect(usage.cacheCreationTokens, 42);
    expect(usage.totalTokens, 246);
  });

  test('parses gemini usage with cache token details fallback', () {
    final usage = AiTokenUsageParser.parseGemini(<String, Object?>{
      'promptTokenCount': 88,
      'candidatesTokenCount': 22,
      'totalTokenCount': 110,
      'thoughtsTokenCount': 5,
      'cacheTokensDetails': <Object?>[
        <String, Object?>{'tokenCount': 11},
        <String, Object?>{'tokenCount': 7},
      ],
    });

    expect(usage, isNotNull);
    expect(usage!.promptTokens, 88);
    expect(usage.completionTokens, 22);
    expect(usage.totalTokens, 110);
    expect(usage.cacheReadTokens, 18);
    expect(usage.reasoningTokens, 5);
  });

  test('carryForward preserves prior cache fields when incoming frame omits them', () {
    final previous = AiTokenUsageParser.parseClaude(<String, Object?>{
      'input_tokens': 100,
      'output_tokens': 10,
      'cache_read_input_tokens': 60,
      'cache_creation_input_tokens': 20,
    });
    final incoming = AiTokenUsageParser.parseClaude(<String, Object?>{
      'input_tokens': 100,
      'output_tokens': 18,
      'total_tokens': 118,
    });

    final merged = AiTokenUsageParser.carryForward(previous, incoming!);
    expect(merged.promptTokens, 100);
    expect(merged.completionTokens, 18);
    expect(merged.totalTokens, 118);
    expect(merged.cacheReadTokens, 60);
    expect(merged.cacheCreationTokens, 20);
  });
}

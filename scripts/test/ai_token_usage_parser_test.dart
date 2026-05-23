import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/ai/service/session_io/ai_token_usage_parser.dart';

void main() {
  // ── parseOpenAi ──────────────────────────────────────────────────

  group('AiTokenUsageParser.parseOpenAi', () {
    test('standard OpenAI fields', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 100,
        'completion_tokens': 50,
        'total_tokens': 150,
      });
      expect(usage, isNotNull);
      expect(usage!.promptTokens, 100);
      expect(usage.completionTokens, 50);
      expect(usage.totalTokens, 150);
    });

    test('standard fields as String', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': '100',
        'completion_tokens': '50',
        'total_tokens': '150',
      });
      expect(usage, isNotNull);
      expect(usage!.promptTokens, 100);
      expect(usage.completionTokens, 50);
      expect(usage.totalTokens, 150);
    });

    test('standard fields as double', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 100.0,
        'completion_tokens': 50.0,
        'total_tokens': 150.0,
      });
      expect(usage, isNotNull);
      expect(usage!.promptTokens, 100);
      expect(usage.completionTokens, 50);
      expect(usage.totalTokens, 150);
    });

    test('totalTokens auto-computed from prompt + completion', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 100,
        'completion_tokens': 50,
      });
      expect(usage, isNotNull);
      expect(usage!.totalTokens, 150);
    });

    // ── Cache read fields ──────────────────────────────────────────

    test('DeepSeek prompt_cache_hit_tokens (flat KV cache hit)', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'total_tokens': 1200,
        'prompt_cache_hit_tokens': 850,
      });
      expect(usage, isNotNull);
      expect(usage!.promptTokens, 1000);
      expect(usage.cacheReadTokens, 850,
          reason: 'DeepSeek 平铺 KV 缓存命中字段必须正确解析');
    });

    test('DeepSeek prompt_cache_hit_tokens as String', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'prompt_cache_hit_tokens': '850',
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 850);
    });

    test('OpenAI official: prompt_tokens_details.cached_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'prompt_tokens_details': {
          'cached_tokens': 750,
        },
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 750);
    });

    test('Responses API: input_tokens_details.cached_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'input_tokens_details': {
          'cached_tokens': 700,
        },
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 700);
    });

    test('vLLM / SGLang: flat cached_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'cached_tokens': 600,
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 600);
    });

    test('OpenAI→Claude gateway: cache_read_input_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'cache_read_input_tokens': 500,
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 500);
    });

    test('prompt_tokens_details.cache_read_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'prompt_tokens_details': {
          'cache_read_tokens': 400,
        },
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 400);
    });

    test('flat cache_read_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'cache_read_tokens': 350,
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 350);
    });

    test('flat cached_prompt_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'cached_prompt_tokens': 300,
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 300);
    });

    // ── Cache write fields ─────────────────────────────────────────

    test('prompt_tokens_details.cache_creation_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'prompt_tokens_details': {
          'cache_creation_tokens': 200,
        },
      });
      expect(usage, isNotNull);
      expect(usage!.cacheCreationTokens, 200);
    });

    test('flat cache_creation_input_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'cache_creation_input_tokens': 150,
      });
      expect(usage, isNotNull);
      expect(usage!.cacheCreationTokens, 150);
    });

    // ── Reasoning tokens ───────────────────────────────────────────

    test('o-series: completion_tokens_details.reasoning_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 500,
        'completion_tokens_details': {
          'reasoning_tokens': 300,
        },
      });
      expect(usage, isNotNull);
      expect(usage!.reasoningTokens, 300);
    });

    test('deepseek: completion_tokens_details.thinking_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 500,
        'completion_tokens_details': {
          'thinking_tokens': 250,
        },
      });
      expect(usage, isNotNull);
      expect(usage!.reasoningTokens, 250);
    });

    test('flat reasoning_tokens', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 500,
        'reasoning_tokens': 200,
      });
      expect(usage, isNotNull);
      expect(usage!.reasoningTokens, 200);
    });

    // ── input_tokens / output_tokens aliases ───────────────────────

    test('input_tokens / output_tokens aliases', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'input_tokens': 800,
        'output_tokens': 400,
      });
      expect(usage, isNotNull);
      expect(usage!.promptTokens, 800);
      expect(usage.completionTokens, 400);
    });

    // ── Edge cases ─────────────────────────────────────────────────

    test('returns null for empty map', () {
      expect(AiTokenUsageParser.parseOpenAi({}), isNull);
    });

    test('returns null when all fields are absent', () {
      expect(
        AiTokenUsageParser.parseOpenAi({'foo': 'bar'}),
        isNull,
      );
    });

    test('zero values are valid', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 0,
        'completion_tokens': 0,
        'total_tokens': 0,
      });
      expect(usage, isNotNull);
      expect(usage!.promptTokens, 0);
      expect(usage.completionTokens, 0);
      expect(usage.totalTokens, 0);
    });

    test('cacheReadTokens null when no cache field present', () {
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 100,
        'completion_tokens': 50,
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, isNull);
      expect(usage.cacheCreationTokens, isNull);
    });

    test(
        'prompt_tokens_details with cache_read_tokens takes precedence '
        'when listed after cached_tokens in scan order (first wins)', () {
      // prompt_tokens_details.cached_tokens is scanned first via _firstInt
      final usage = AiTokenUsageParser.parseOpenAi({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'prompt_tokens_details': {
          'cache_read_tokens': 555,
        },
        'prompt_cache_hit_tokens': 333,
      });
      // prompt_tokens_details.cache_read_tokens is scanned first
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 555);
    });
  });

  // ── parseClaude ──────────────────────────────────────────────────

  group('AiTokenUsageParser.parseClaude', () {
    test('standard Anthropic fields', () {
      final usage = AiTokenUsageParser.parseClaude({
        'input_tokens': 500,
        'output_tokens': 300,
      });
      expect(usage, isNotNull);
      expect(usage!.promptTokens, 500);
      expect(usage.completionTokens, 300);
    });

    test('cache_read_input_tokens', () {
      final usage = AiTokenUsageParser.parseClaude({
        'input_tokens': 500,
        'output_tokens': 300,
        'cache_read_input_tokens': 400,
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 400);
    });

    test('cache_creation_input_tokens (flat)', () {
      final usage = AiTokenUsageParser.parseClaude({
        'input_tokens': 500,
        'output_tokens': 300,
        'cache_creation_input_tokens': 100,
      });
      expect(usage, isNotNull);
      expect(usage!.cacheCreationTokens, 100);
    });

    test('cache_creation sub-object (ephemeral_5m + ephemeral_1h)', () {
      final usage = AiTokenUsageParser.parseClaude({
        'input_tokens': 500,
        'output_tokens': 300,
        'cache_creation': {
          'ephemeral_5m_input_tokens': 60,
          'ephemeral_1h_input_tokens': 40,
        },
      });
      expect(usage, isNotNull);
      expect(usage!.cacheCreationTokens, 100);
    });

    test(
        'cache_creation flat has priority over sub-object',
        () {
      final usage = AiTokenUsageParser.parseClaude({
        'input_tokens': 500,
        'output_tokens': 300,
        'cache_creation_input_tokens': 200,
        'cache_creation': {
          'ephemeral_5m_input_tokens': 60,
          'ephemeral_1h_input_tokens': 40,
        },
      });
      expect(usage, isNotNull);
      expect(usage!.cacheCreationTokens, 200,
          reason: '平铺 cache_creation_input_tokens 优先级高于子对象求和');
    });

    test('cache_creation with only ep_5m', () {
      final usage = AiTokenUsageParser.parseClaude({
        'input_tokens': 500,
        'output_tokens': 300,
        'cache_creation': {
          'ephemeral_5m_input_tokens': 60,
        },
      });
      expect(usage, isNotNull);
      expect(usage!.cacheCreationTokens, 60);
    });

    test('returns null for empty map', () {
      expect(AiTokenUsageParser.parseClaude({}), isNull);
    });

    test('totalTokens auto-computed', () {
      final usage = AiTokenUsageParser.parseClaude({
        'input_tokens': 200,
        'output_tokens': 100,
      });
      expect(usage, isNotNull);
      expect(usage!.totalTokens, 300);
    });
  });

  // ── parseGemini ──────────────────────────────────────────────────

  group('AiTokenUsageParser.parseGemini', () {
    test('standard Gemini usageMetadata fields', () {
      final usage = AiTokenUsageParser.parseGemini({
        'promptTokenCount': 400,
        'candidatesTokenCount': 200,
        'totalTokenCount': 600,
      });
      expect(usage, isNotNull);
      expect(usage!.promptTokens, 400);
      expect(usage.completionTokens, 200);
      expect(usage.totalTokens, 600);
    });

    test('cachedContentTokenCount (implicit/explicit cache hit)', () {
      final usage = AiTokenUsageParser.parseGemini({
        'promptTokenCount': 400,
        'candidatesTokenCount': 200,
        'cachedContentTokenCount': 350,
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 350);
    });

    test('thoughtsTokenCount (Gemini 2.5 thinking)', () {
      final usage = AiTokenUsageParser.parseGemini({
        'promptTokenCount': 400,
        'candidatesTokenCount': 500,
        'thoughtsTokenCount': 300,
      });
      expect(usage, isNotNull);
      expect(usage!.reasoningTokens, 300);
    });

    test('cacheTokensDetails list aggregated to cacheRead', () {
      final usage = AiTokenUsageParser.parseGemini({
        'promptTokenCount': 400,
        'candidatesTokenCount': 200,
        'cacheTokensDetails': [
          {'tokenCount': 100},
          {'tokenCount': 200},
          {'tokenCount': 50},
        ],
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 350);
    });

    test('cacheTokensDetails with mixed invalid entries', () {
      final usage = AiTokenUsageParser.parseGemini({
        'promptTokenCount': 400,
        'cacheTokensDetails': [
          {'tokenCount': 100},
          'not_a_map',
          {'tokenCount': 200},
          {'no_token_count': 'here'},
        ],
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 300);
    });

    test('cachedContentTokenCount has precedence over details list', () {
      final usage = AiTokenUsageParser.parseGemini({
        'promptTokenCount': 400,
        'cachedContentTokenCount': 999,
        'cacheTokensDetails': [
          {'tokenCount': 100},
        ],
      });
      expect(usage, isNotNull);
      expect(usage!.cacheReadTokens, 999);
    });

    test('returns null for empty map', () {
      expect(AiTokenUsageParser.parseGemini({}), isNull);
    });
  });

  // ── carryForward ─────────────────────────────────────────────────

  group('AiTokenUsageParser.carryForward', () {
    test('returns incoming when previous is null', () {
      final incoming = AiTokenUsage(
        promptTokens: 100,
        completionTokens: 50,
      );
      expect(AiTokenUsageParser.carryForward(null, incoming), incoming);
    });

    test('new non-null values overwrite old', () {
      final prev = AiTokenUsage(
        promptTokens: 100,
        cacheReadTokens: 50,
      );
      final incoming = AiTokenUsage(
        promptTokens: 200,
        cacheReadTokens: 80,
      );
      final result = AiTokenUsageParser.carryForward(prev, incoming);
      expect(result.promptTokens, 200);
      expect(result.cacheReadTokens, 80);
    });

    test('null in incoming preserves previous', () {
      final prev = AiTokenUsage(
        promptTokens: 100,
        cacheReadTokens: 50,
        cacheCreationTokens: 30,
      );
      final incoming = AiTokenUsage(
        completionTokens: 200,
        // promptTokens / cacheRead / cacheCreation all null
      );
      final result = AiTokenUsageParser.carryForward(prev, incoming);
      expect(result.promptTokens, 100,
          reason: 'incoming 未下发 promptTokens → 保留旧值');
      expect(result.completionTokens, 200);
      expect(result.cacheReadTokens, 50,
          reason: 'message_delta 可能不再下发 cache_* → 保留 message_start 的初值');
      expect(result.cacheCreationTokens, 30);
    });

    test('completionTokens uses max (never rolls back)', () {
      final prev = AiTokenUsage(completionTokens: 300);
      final incoming = AiTokenUsage(completionTokens: 200);
      final result = AiTokenUsageParser.carryForward(prev, incoming);
      expect(result.completionTokens, 300,
          reason: '流式累计中 completionTokens 只增不减');
    });

    test('totalTokens uses max', () {
      final prev = AiTokenUsage(totalTokens: 1000);
      final incoming = AiTokenUsage(totalTokens: 500);
      final result = AiTokenUsageParser.carryForward(prev, incoming);
      expect(result.totalTokens, 1000);
    });

    test('reasoningTokens uses max', () {
      final prev = AiTokenUsage(reasoningTokens: 200);
      final incoming = AiTokenUsage(reasoningTokens: 400);
      final result = AiTokenUsageParser.carryForward(prev, incoming);
      expect(result.reasoningTokens, 400);
    });

    test('previous reasoningTokens preserved when incoming null', () {
      final prev = AiTokenUsage(reasoningTokens: 200);
      final incoming = AiTokenUsage(completionTokens: 100);
      final result = AiTokenUsageParser.carryForward(prev, incoming);
      expect(result.reasoningTokens, 200);
    });

    test('all fields carry forward correctly in a streaming scenario', () {
      // message_start: initial cache hit data
      final msgStart = AiTokenUsage(
        promptTokens: 1000,
        completionTokens: 0,
        cacheReadTokens: 850,
        cacheCreationTokens: 0,
      );
      // First delta: some completion tokens
      final delta1 = AiTokenUsage(completionTokens: 50);
      final afterDelta1 = AiTokenUsageParser.carryForward(msgStart, delta1);
      expect(afterDelta1.promptTokens, 1000);
      expect(afterDelta1.completionTokens, 50);
      expect(afterDelta1.cacheReadTokens, 850);

      // Second delta: more completion tokens, cacheRead no longer sent
      final delta2 = AiTokenUsage(completionTokens: 150);
      final afterDelta2 = AiTokenUsageParser.carryForward(afterDelta1, delta2);
      expect(afterDelta2.completionTokens, 150);
      expect(afterDelta2.cacheReadTokens, 850,
          reason: 'message_delta 停止下发 cacheRead → 保留 message_start 初值');

      // Final: message_stop with total
      final stop = AiTokenUsage(totalTokens: 1200);
      final finalResult = AiTokenUsageParser.carryForward(afterDelta2, stop);
      expect(finalResult.totalTokens, 1200);
      expect(finalResult.cacheReadTokens, 850);
      expect(finalResult.promptTokens, 1000);
      expect(finalResult.completionTokens, 150);
    });
  });
}

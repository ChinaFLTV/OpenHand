import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_token_usage.dart';

/// 统一的 token usage 解析器：把各家 AI 服务商的 usage 字段差异收敛在此处。
///
/// 三种协议家族：
/// - OpenAI 兼容（OpenAI / DeepSeek / Kimi / GLM(Z.AI) / Doubao(Seed) /
///   Grok(xAI) / Qwen / 阶跃星辰(StepFun) / MiniMax / LongCat / JoyCode /
///   Wenxin / Hunyuan / MIMO / vLLM / SGLang / Meta / Ollama 等）。
/// - Anthropic / Claude（input_tokens / output_tokens / cache_creation /
///   cache_read_input_tokens，含 ephemeral_5m / ephemeral_1h 子项）。
/// - Google Gemini（usageMetadata 系列字段）。
///
/// 解析时容忍数值以 int / double / String 形式出现，且兼容 snake_case 与
/// camelCase 拼写差异。无法识别的字段不会抛错——只要有一项命中就返回非空
/// usage。
class AiTokenUsageParser {
  const AiTokenUsageParser._();

  static AiTokenUsage? parseResponsePayload(Object? raw) {
    final root = _readMap(raw);
    if (root == null) return null;
    final candidates = <Map<String, Object?>>[];

    void collect(Map<String, Object?> payload, int depth) {
      final usage = _readMap(payload['usage']);
      if (usage != null) candidates.add(usage);
      final usageMetadata = _readMap(payload['usageMetadata']);
      if (usageMetadata != null) candidates.add(usageMetadata);
      candidates.add(payload);
      if (depth >= 2) return;
      for (final key in const <String>[
        'data',
        'result',
        'output',
        'response',
      ]) {
        final nested = payload[key];
        final nestedMap = _readMap(nested);
        if (nestedMap != null) {
          collect(nestedMap, depth + 1);
          continue;
        }
        if (nested is List) {
          for (final item in nested) {
            final itemMap = _readMap(item);
            if (itemMap != null) collect(itemMap, depth + 1);
          }
        }
      }
    }

    collect(root, 0);
    for (final candidate in candidates) {
      final parsed =
          parseOpenAi(candidate) ??
          parseClaude(candidate) ??
          parseGemini(candidate);
      if (parsed != null && !parsed.isEmpty) return parsed;
    }
    return null;
  }

  /// OpenAI / OpenAI-compatible providers:
  /// - 标准: prompt_tokens / completion_tokens / total_tokens
  /// - 缓存命中常见字段:
  ///   * prompt_tokens_details.cached_tokens（OpenAI 官方 / Grok / Kimi /
  ///     Doubao / Wenxin / Hunyuan / LongCat / StepFun / MiniMax / Qwen 等）
  ///   * input_tokens_details.cached_tokens（Responses API / 部分代理）
  ///   * prompt_cache_hit_tokens（DeepSeek 平铺 KV 缓存命中）
  ///   * cached_tokens（vLLM / SGLang / 自托管网关平铺写法）
  ///   * cache_read_input_tokens（少数 Claude→OpenAI 转译网关）
  /// - 缓存写入 / 未命中写入字段:
  ///   * prompt_tokens_details.cache_creation_tokens
  ///   * cache_creation_input_tokens
  ///   * prompt_cache_miss_tokens（DeepSeek KV Cache miss，代表本轮未命中
  ///     并按常规输入计费的 prompt tokens，下一轮可成为缓存命中）
  static AiTokenUsage? parseOpenAi(Map<String, Object?> usageMap) {
    final promptTokens = _firstInt(<Object?>[
      usageMap['prompt_tokens'],
      usageMap['input_tokens'],
      usageMap['promptTokens'],
      usageMap['inputTokens'],
    ]);
    final completionTokens = _firstInt(<Object?>[
      usageMap['completion_tokens'],
      usageMap['output_tokens'],
      usageMap['completionTokens'],
      usageMap['outputTokens'],
    ]);
    final totalTokens = _firstInt(<Object?>[
      usageMap['total_tokens'],
      usageMap['totalTokens'],
    ]);

    final promptDetails =
        _readMap(usageMap['prompt_tokens_details']) ??
        _readMap(usageMap['promptTokensDetails']);
    final inputDetails =
        _readMap(usageMap['input_tokens_details']) ??
        _readMap(usageMap['inputTokensDetails']);
    final completionDetails =
        _readMap(usageMap['completion_tokens_details']) ??
        _readMap(usageMap['completionTokensDetails']);
    final outputDetails =
        _readMap(usageMap['output_tokens_details']) ??
        _readMap(usageMap['outputTokensDetails']);

    final cacheRead = _firstInt([
      promptDetails?['cached_tokens'],
      promptDetails?['cachedTokens'],
      promptDetails?['cache_read_tokens'],
      promptDetails?['cacheReadTokens'],
      inputDetails?['cached_tokens'],
      inputDetails?['cachedTokens'],
      inputDetails?['cache_read_tokens'],
      inputDetails?['cacheReadTokens'],
      usageMap['prompt_cache_hit_tokens'],
      usageMap['cached_tokens'],
      usageMap['cache_read_input_tokens'],
      usageMap['cache_read_tokens'],
      usageMap['cached_prompt_tokens'],
      usageMap['cacheReadTokens'],
      usageMap['cachedTokens'],
    ]);

    final cacheWrite = _firstInt([
      promptDetails?['cache_creation_tokens'],
      promptDetails?['cacheCreationTokens'],
      promptDetails?['cache_write_tokens'],
      promptDetails?['cacheWriteTokens'],
      promptDetails?['cache_miss_tokens'],
      inputDetails?['cache_creation_tokens'],
      inputDetails?['cacheCreationTokens'],
      inputDetails?['cache_write_tokens'],
      inputDetails?['cacheWriteTokens'],
      inputDetails?['cache_miss_tokens'],
      usageMap['cache_creation_input_tokens'],
      usageMap['cache_creation_tokens'],
      usageMap['cache_write_tokens'],
      usageMap['prompt_cache_miss_tokens'],
      usageMap['cache_miss_tokens'],
      usageMap['cached_creation_tokens'],
      usageMap['cacheCreationTokens'],
      usageMap['cacheWriteTokens'],
    ]);

    // Reasoning / thinking 阶段计费量。在 OpenAI o-系列、DeepSeek-R1、Z.AI 思考模式
    // 里都通过 completion_tokens_details.reasoning_tokens 暴露；少数代理把它平铺
    // 到 usage 顶层（非官方约定，但兜底解析）。
    final reasoning = _firstInt([
      completionDetails?['reasoning_tokens'],
      completionDetails?['reasoningTokens'],
      completionDetails?['thinking_tokens'],
      outputDetails?['reasoning_tokens'],
      outputDetails?['reasoningTokens'],
      outputDetails?['thinking_tokens'],
      usageMap['reasoning_tokens'],
      usageMap['thinking_tokens'],
      usageMap['reasoningTokens'],
      usageMap['thinkingTokens'],
    ]);
    final audioInputTokens = _firstInt(<Object?>[
      promptDetails?['audio_tokens'],
      promptDetails?['audioTokens'],
      inputDetails?['audio_tokens'],
      inputDetails?['audioTokens'],
    ]);
    final imageInputTokens = _firstInt(<Object?>[
      promptDetails?['image_tokens'],
      promptDetails?['imageTokens'],
      inputDetails?['image_tokens'],
      inputDetails?['imageTokens'],
    ]);
    final videoInputTokens = _firstInt(<Object?>[
      promptDetails?['video_tokens'],
      promptDetails?['videoTokens'],
      inputDetails?['video_tokens'],
      inputDetails?['videoTokens'],
    ]);
    final webSearchUsage =
        _readMap(usageMap['web_search_usage']) ??
        _readMap(usageMap['webSearchUsage']);
    final webSearchToolUsage = _firstInt(<Object?>[
      webSearchUsage?['tool_usage'],
      webSearchUsage?['toolUsage'],
    ]);
    final webSearchPageUsage = _firstInt(<Object?>[
      webSearchUsage?['page_usage'],
      webSearchUsage?['pageUsage'],
    ]);

    if (promptTokens == null &&
        completionTokens == null &&
        totalTokens == null &&
        cacheRead == null &&
        cacheWrite == null &&
        reasoning == null &&
        audioInputTokens == null &&
        imageInputTokens == null &&
        videoInputTokens == null &&
        webSearchToolUsage == null &&
        webSearchPageUsage == null) {
      return null;
    }

    return AiTokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: resolveAiTotalTokens(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
      ),
      cacheReadTokens: cacheRead,
      cacheCreationTokens: cacheWrite,
      reasoningTokens: reasoning,
      audioInputTokens: audioInputTokens,
      imageInputTokens: imageInputTokens,
      videoInputTokens: videoInputTokens,
      webSearchToolUsage: webSearchToolUsage,
      webSearchPageUsage: webSearchPageUsage,
    );
  }

  /// Anthropic / Claude usage shape.
  /// - input_tokens / output_tokens（streaming 中累计）。
  /// - cache_creation_input_tokens（写入总量，可能仅 5m/1h 之一非零）。
  /// - cache_read_input_tokens（命中读取总量）。
  /// - cache_creation 子对象：ephemeral_5m_input_tokens +
  ///   ephemeral_1h_input_tokens（与上面 cache_creation_input_tokens 等价的
  ///   细分；某些版本只下发其一）。
  static AiTokenUsage? parseClaude(Map<String, Object?> usageMap) {
    final promptTokens = optionalNonNegativeIntegralIntFromValue(
      usageMap['input_tokens'],
    );
    final completionTokens = optionalNonNegativeIntegralIntFromValue(
      usageMap['output_tokens'],
    );
    final totalTokens = optionalNonNegativeIntegralIntFromValue(
      usageMap['total_tokens'],
    );

    int? cacheCreation = optionalNonNegativeIntegralIntFromValue(
      usageMap['cache_creation_input_tokens'],
    );
    final creationDetails = _readMap(usageMap['cache_creation']);
    if (creationDetails != null) {
      final ephemeral5m = optionalNonNegativeIntegralIntFromValue(
        creationDetails['ephemeral_5m_input_tokens'],
      );
      final ephemeral1h = optionalNonNegativeIntegralIntFromValue(
        creationDetails['ephemeral_1h_input_tokens'],
      );
      final detailedSum = (ephemeral5m ?? 0) + (ephemeral1h ?? 0);
      // 优先使用平铺 cache_creation_input_tokens；缺失时退到子对象之和。
      cacheCreation ??= detailedSum > 0 ? detailedSum : null;
    }
    final cacheRead = optionalNonNegativeIntegralIntFromValue(
      usageMap['cache_read_input_tokens'],
    );

    if (promptTokens == null &&
        completionTokens == null &&
        totalTokens == null &&
        cacheCreation == null &&
        cacheRead == null) {
      return null;
    }

    return AiTokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: resolveAiTotalTokens(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
      ),
      cacheCreationTokens: cacheCreation,
      cacheReadTokens: cacheRead,
    );
  }

  /// Google Gemini `usageMetadata` shape.
  /// - promptTokenCount / candidatesTokenCount / totalTokenCount。
  /// - cachedContentTokenCount（显式或隐式上下文缓存命中数量）。
  /// - cacheTokensDetails（少数版本细分到 modality；当前仅汇总到 cacheRead）。
  /// - Gemini 不暴露独立的 cache write 字段——隐式缓存对调用方免费，
  ///   显式缓存的写入计入 promptTokenCount，与此处无关。
  static AiTokenUsage? parseGemini(Map<String, Object?> usageMap) {
    final promptTokens = optionalNonNegativeIntegralIntFromValue(
      usageMap['promptTokenCount'],
    );
    final completionTokens = optionalNonNegativeIntegralIntFromValue(
      usageMap['candidatesTokenCount'],
    );
    final totalTokens = optionalNonNegativeIntegralIntFromValue(
      usageMap['totalTokenCount'],
    );
    // Gemini 2.5 Pro / Flash 思考模型：thoughtsTokenCount 包含在
    // candidatesTokenCount 之内。
    final reasoning = optionalNonNegativeIntegralIntFromValue(
      usageMap['thoughtsTokenCount'],
    );

    int? cacheRead = optionalNonNegativeIntegralIntFromValue(
      usageMap['cachedContentTokenCount'],
    );
    if (cacheRead == null) {
      final details = usageMap['cacheTokensDetails'];
      if (details is List) {
        var sum = 0;
        var anyMatched = false;
        for (final entry in details) {
          if (entry is! Map) continue;
          final value = optionalNonNegativeIntegralIntFromValue(
            entry['tokenCount'],
          );
          if (value != null) {
            sum += value;
            anyMatched = true;
          }
        }
        if (anyMatched) cacheRead = sum;
      }
    }

    if (promptTokens == null &&
        completionTokens == null &&
        totalTokens == null &&
        cacheRead == null &&
        reasoning == null) {
      return null;
    }

    return AiTokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: resolveAiTotalTokens(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
      ),
      cacheReadTokens: cacheRead,
      reasoningTokens: reasoning,
    );
  }

  /// 在流式更新中合并新 usage 与上一帧 usage：
  /// - 新值非空时用新值；否则保留旧值。
  /// - total/output_tokens 使用 max（避免回退）。
  /// - cache 字段用新值兜底旧值，因为 Anthropic message_delta 可能不再下发
  ///   cache_*；保留 message_start 拿到的初值。
  static AiTokenUsage carryForward(
    AiTokenUsage? previous,
    AiTokenUsage incoming,
  ) {
    if (previous == null) return incoming;
    int? maxNullable(int? a, int? b) {
      if (a == null) return b;
      if (b == null) return a;
      return a > b ? a : b;
    }

    return AiTokenUsage(
      promptTokens: incoming.promptTokens ?? previous.promptTokens,
      completionTokens: maxNullable(
        previous.completionTokens,
        incoming.completionTokens,
      ),
      totalTokens: maxNullable(previous.totalTokens, incoming.totalTokens),
      cacheCreationTokens:
          incoming.cacheCreationTokens ?? previous.cacheCreationTokens,
      cacheReadTokens: incoming.cacheReadTokens ?? previous.cacheReadTokens,
      reasoningTokens: maxNullable(
        previous.reasoningTokens,
        incoming.reasoningTokens,
      ),
      audioInputTokens: maxNullable(
        previous.audioInputTokens,
        incoming.audioInputTokens,
      ),
      imageInputTokens: maxNullable(
        previous.imageInputTokens,
        incoming.imageInputTokens,
      ),
      videoInputTokens: maxNullable(
        previous.videoInputTokens,
        incoming.videoInputTokens,
      ),
      webSearchToolUsage: maxNullable(
        previous.webSearchToolUsage,
        incoming.webSearchToolUsage,
      ),
      webSearchPageUsage: maxNullable(
        previous.webSearchPageUsage,
        incoming.webSearchPageUsage,
      ),
    );
  }
}

int? _firstInt(List<Object?> candidates) {
  for (final candidate in candidates) {
    final value = optionalNonNegativeIntegralIntFromValue(candidate);
    if (value != null) return value;
  }
  return null;
}

Map<String, Object?>? _readMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return stringKeyedMapFromValue(value);
  return null;
}

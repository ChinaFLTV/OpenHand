/// 2026-05-04 — 单轮 / 多轮聚合的 USD 成本拆解。
///
/// 计算约定：
///   * `inputUsd`        来源于 [AiTokenUsage.promptTokens]
///   * `outputUsd`       来源于 [AiTokenUsage.completionTokens]
///   * `cacheReadUsd`    来源于 [AiTokenUsage.cacheReadTokens]
///   * `cacheWriteUsd`   来源于 [AiTokenUsage.cacheCreationTokens]
///
/// 不同协议对 token 字段的语义并不一致：
///   * Claude：`input_tokens` 不包含 cache_read_input_tokens，二者**不重叠**。
///     可直接把 promptTokens × inputPrice + cacheRead × cacheReadPrice 相加。
///   * OpenAI：`prompt_tokens` 已包含 `prompt_tokens_details.cached_tokens`，
///     直接相加会导致 cache 部分被双重计费。compute() 暴露 [claudeStyle]
///     开关，OpenAI 系传 false，会自动从 promptTokens 中扣除 cacheReadTokens。
///
/// 任意 profile 价格缺失时返回 `null`（不参与渲染）；调用方应优雅降级。
library;

import 'ai_model_config.dart';
import 'ai_token_usage.dart';

class AiCostBreakdown {
  const AiCostBreakdown({
    this.inputUsd,
    this.outputUsd,
    this.cacheReadUsd,
    this.cacheWriteUsd,
  });

  final double? inputUsd;
  final double? outputUsd;
  final double? cacheReadUsd;
  final double? cacheWriteUsd;

  double? get totalUsd {
    if (inputUsd == null &&
        outputUsd == null &&
        cacheReadUsd == null &&
        cacheWriteUsd == null) {
      return null;
    }
    return (inputUsd ?? 0) +
        (outputUsd ?? 0) +
        (cacheReadUsd ?? 0) +
        (cacheWriteUsd ?? 0);
  }

  bool get isEmpty =>
      inputUsd == null &&
      outputUsd == null &&
      cacheReadUsd == null &&
      cacheWriteUsd == null;

  /// 根据 [usage] × [profile] 价格表推算成本；任一关键价格缺失时对应分量
  /// 为 `null`。整体全为 `null` 时返回 `null`，由上层决定是否隐藏。
  ///
  /// [claudeStyle] = true（默认）：promptTokens 与 cacheReadTokens 不重叠。
  /// false：OpenAI 系，promptTokens 包含 cacheRead，需扣减。
  static AiCostBreakdown? compute({
    required AiTokenUsage usage,
    required AiModelProfile? profile,
    bool claudeStyle = true,
  }) {
    if (profile == null) return null;
    final inputPrice = profile.inputUsdPer1M;
    final outputPrice = profile.outputUsdPer1M;
    final cacheReadPrice = profile.cacheReadUsdPer1M;
    final cacheWritePrice = profile.cacheWriteUsdPer1M;
    if (inputPrice == null &&
        outputPrice == null &&
        cacheReadPrice == null &&
        cacheWritePrice == null) {
      return null;
    }

    final cacheReadTokens = usage.cacheReadTokens ?? 0;
    final cacheCreateTokens = usage.cacheCreationTokens ?? 0;
    final rawPrompt = usage.promptTokens ?? 0;
    final effectivePrompt = claudeStyle
        ? rawPrompt
        : (rawPrompt - cacheReadTokens).clamp(0, rawPrompt);
    final completion = usage.completionTokens ?? 0;

    double? mul(int tokens, double? price) =>
        price == null ? null : tokens * price / 1000000.0;

    return AiCostBreakdown(
      inputUsd: usage.promptTokens == null ? null : mul(effectivePrompt, inputPrice),
      outputUsd:
          usage.completionTokens == null ? null : mul(completion, outputPrice),
      cacheReadUsd: usage.cacheReadTokens == null
          ? null
          : mul(cacheReadTokens, cacheReadPrice),
      cacheWriteUsd: usage.cacheCreationTokens == null
          ? null
          : mul(cacheCreateTokens, cacheWritePrice),
    );
  }

  /// 跨轮 / 跨 session 成本聚合：分量逐项相加，任一边非 null 即出现在结果。
  AiCostBreakdown merge(AiCostBreakdown other) {
    return AiCostBreakdown(
      inputUsd: _sumNullable(inputUsd, other.inputUsd),
      outputUsd: _sumNullable(outputUsd, other.outputUsd),
      cacheReadUsd: _sumNullable(cacheReadUsd, other.cacheReadUsd),
      cacheWriteUsd: _sumNullable(cacheWriteUsd, other.cacheWriteUsd),
    );
  }

  static double? _sumNullable(double? left, double? right) {
    if (left == null && right == null) return null;
    return (left ?? 0) + (right ?? 0);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (inputUsd != null) 'input_usd': inputUsd,
        if (outputUsd != null) 'output_usd': outputUsd,
        if (cacheReadUsd != null) 'cache_read_usd': cacheReadUsd,
        if (cacheWriteUsd != null) 'cache_write_usd': cacheWriteUsd,
      };
}

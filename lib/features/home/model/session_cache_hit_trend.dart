import '../../../shared/util/input_value_parsing.dart';
import '../../ai/index.dart';

/// 过期异常判定：距离上一轮请求超过 30 分钟，且本轮缓存命中率不足 3%。
const int kCacheHitExpiryIdleGapSeconds = 1800; // 30 分钟
const double kCacheHitExpiryHitRatioThreshold = 0.03; // 3%
const int kAutomaticProviderCacheMissMinGapSeconds = 0;
const double kAutomaticProviderCacheMissHitRatioThreshold = 0.80;

/// 前缀复用健康阈值：本轮缓存读取达到上一轮可复用前缀的 95% 以上，
/// 视为已达理论上限（供应商按 token 块对齐缓存，允许少量块级抖动）。
/// 命中率（read/prompt）会被"本轮新增且必然未缓存"的输入稀释，
/// 复用率才是衡量 Prompt 装配是否破坏缓存的口径。
const double kCacheHitHealthyPrefixReuseRatio = 0.95;

enum SessionCacheHitDisplayMode { excludeExpiredMisses, includeExpiredMisses }

class SessionCacheHitDisplayData {
  const SessionCacheHitDisplayData({
    required this.mode,
    required this.trend,
    required this.averageHitRatio,
    required this.averagePrefixReuseRatio,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.uncachedPromptTokens,
    required this.excludedPointCount,
    required this.excludedFirstRequestCount,
    required this.excludedExpiredMissCount,
    required this.averagePointCount,
  });

  final SessionCacheHitDisplayMode mode;
  final SessionCacheHitTrend trend;
  final double averageHitRatio;

  /// 平均前缀复用率 = Σ缓存读取 / Σ上一轮可复用前缀，仅统计存在上一轮
  /// 基准的轮次；无可统计轮次时为 null。
  final double? averagePrefixReuseRatio;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int uncachedPromptTokens;
  final int excludedPointCount;
  final int excludedFirstRequestCount;
  final int excludedExpiredMissCount;
  final int averagePointCount;
}

bool shouldShowSessionCacheHitMetrics({
  required int cacheReadTokens,
  required int cacheWriteTokens,
  required bool hasTrendPoints,
  required bool hasCacheUsageTelemetry,
  required double? cacheHitRatio,
}) {
  return hasCacheUsageTelemetry ||
      cacheHitRatio != null ||
      cacheReadTokens > 0 ||
      cacheWriteTokens > 0 ||
      hasTrendPoints;
}

class SessionCacheHitTurnPoint {
  const SessionCacheHitTurnPoint({
    required this.turnIndex,
    required this.starterMessageId,
    required this.starterMessageKind,
    required this.starterOrigin,
    required this.anchorMessageId,
    required this.timestamp,
    required this.hitRatio,
    required this.averageHitRatio,
    required this.promptTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.denominatorTokens,
    required this.previousDenominatorTokens,
    required this.idleGapSeconds,
    required this.ttlSuspected,
    required this.prefixDriftSuspected,
    required this.automaticProviderMissSuspected,
  });

  final int turnIndex;
  final String starterMessageId;
  final String starterMessageKind;
  final String starterOrigin;
  final String anchorMessageId;
  final DateTime timestamp;
  final double hitRatio;
  final double averageHitRatio;
  final int promptTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;

  /// 本轮请求总输入规模（命中率分母口径，兼容 Claude / OpenAI 两种统计）。
  final int denominatorTokens;

  /// 上一轮请求的总输入规模；首轮或缺失时为 null。
  /// 该值即"本轮理论可复用前缀"的上限基准。
  final int? previousDenominatorTokens;
  final int? idleGapSeconds;
  final bool ttlSuspected;
  final bool prefixDriftSuspected;
  final bool automaticProviderMissSuspected;

  bool get isFirstRequest => turnIndex <= 1;

  /// 本轮相对上一轮新增的输入 token（新工具结果 / 新对话内容）。
  /// 这部分内容首次出现，结构上不可能命中任何缓存。
  int get freshInputTokens {
    final previous = previousDenominatorTokens;
    if (previous == null) return 0;
    final delta = denominatorTokens - previous;
    return delta > 0 ? delta : 0;
  }

  /// 前缀复用率 = 本轮缓存读取 / 上一轮可复用前缀。
  /// 该值接近 1 表示 Prompt 装配保持了前缀延展，未破坏缓存。
  double? get prefixReuseRatio {
    final previous = previousDenominatorTokens;
    if (previous == null || previous <= 0) return null;
    return unitRatio(cacheReadTokens, previous);
  }

  /// 本轮缓存复用已达理论上限（未命中部分基本都是新增输入）。
  bool get reachedTheoreticalCeiling {
    final reuse = prefixReuseRatio;
    return reuse != null && reuse >= kCacheHitHealthyPrefixReuseRatio;
  }

  AiSessionCacheHitTrendPoint toStatisticsPoint() {
    return AiSessionCacheHitTrendPoint(
      turnIndex: turnIndex,
      hitRatio: hitRatio,
      promptTokens: promptTokens,
      cacheReadTokens: cacheReadTokens,
      cacheWriteTokens: cacheWriteTokens,
      starterMessageId: starterMessageId,
      starterMessageKind: starterMessageKind,
      starterOrigin: starterOrigin,
      anchorMessageId: anchorMessageId,
      idleGapSeconds: idleGapSeconds,
      previousDenominatorTokens: previousDenominatorTokens,
    );
  }

  Map<String, Object?> toJson() => toStatisticsPoint().toJson();
}

class SessionCacheHitViewport {
  const SessionCacheHitViewport({
    required this.start,
    required this.end,
    required this.totalPoints,
  });

  factory SessionCacheHitViewport.full(int totalPoints) {
    final clampedTotal = totalPoints < 1 ? 1 : totalPoints;
    return SessionCacheHitViewport(
      start: 0,
      end: (clampedTotal - 1).toDouble(),
      totalPoints: clampedTotal,
    );
  }

  final double start;
  final double end;
  final int totalPoints;

  double get span => end - start;
  bool get isFullRange =>
      start <= 0.0001 && (end - (totalPoints - 1)).abs() <= 0.0001;

  SessionCacheHitViewport zoomAround({
    required double anchor,
    required double scale,
    double minVisiblePoints = 6,
  }) {
    if (totalPoints <= 1) return this;
    final maxSpan = (totalPoints - 1).toDouble();
    final minSpan = (minVisiblePoints - 1).clamp(1, totalPoints - 1).toDouble();
    final safeScale = scale <= 0 ? 1.0 : scale;
    final nextSpan = (span / safeScale).clamp(minSpan, maxSpan);
    final normalizedAnchor = unitRatio(anchor - start, span);
    var nextStart = anchor - normalizedAnchor * nextSpan;
    var nextEnd = nextStart + nextSpan;
    if (nextStart < 0) {
      nextEnd -= nextStart;
      nextStart = 0;
    }
    if (nextEnd > maxSpan) {
      final overflow = nextEnd - maxSpan;
      nextStart = (nextStart - overflow).clamp(0.0, maxSpan - nextSpan);
      nextEnd = maxSpan;
    }
    return SessionCacheHitViewport(
      start: nextStart,
      end: nextEnd,
      totalPoints: totalPoints,
    );
  }

  SessionCacheHitViewport panBy(double deltaPoints) {
    if (totalPoints <= 1) return this;
    final maxSpan = (totalPoints - 1).toDouble();
    if (span >= maxSpan) return SessionCacheHitViewport.full(totalPoints);
    var nextStart = (start + deltaPoints).clamp(0.0, maxSpan - span);
    final nextEnd = nextStart + span;
    return SessionCacheHitViewport(
      start: nextStart,
      end: nextEnd,
      totalPoints: totalPoints,
    );
  }
}

class SessionCacheHitTrend {
  const SessionCacheHitTrend({
    required this.points,
    required this.averageHitRatio,
    required this.claudeStyle,
  });

  final List<SessionCacheHitTurnPoint> points;
  final double averageHitRatio;
  final bool claudeStyle;

  bool get hasEnoughPoints => points.length >= 2;

  SessionCacheHitDisplayData displayData(SessionCacheHitDisplayMode mode) {
    // 每个点代表一次完整的模型请求响应。工具结果续请仍计入，
    // 默认仅排除首次冷请求和长时间空闲导致的过期未命中。
    final chartPoints = switch (mode) {
      SessionCacheHitDisplayMode.includeExpiredMisses => points,
      SessionCacheHitDisplayMode.excludeExpiredMisses =>
        points
            .where(
              (point) => !point.isFirstRequest && !_isExpiredCacheMiss(point),
            )
            .toList(growable: false),
    };
    final averagePoints = points
        .where(
          (point) =>
              !point.isFirstRequest &&
              (mode == SessionCacheHitDisplayMode.includeExpiredMisses ||
                  !_isExpiredCacheMiss(point)),
        )
        .toList(growable: false);
    var cacheReadTokens = 0;
    var cacheWriteTokens = 0;
    var uncachedPromptTokens = 0;
    var reusableCacheReadTokens = 0;
    var reusablePrefixTokens = 0;
    for (final point in averagePoints) {
      cacheReadTokens += point.cacheReadTokens;
      cacheWriteTokens += point.cacheWriteTokens;
      uncachedPromptTokens += computeUncachedPromptTokens(
        promptTokens: point.promptTokens,
        cacheReadTokens: point.cacheReadTokens,
        claudeStyle: claudeStyle,
        cacheWriteTokens: point.cacheWriteTokens,
      );
      final previousDenominator = point.previousDenominatorTokens;
      if (previousDenominator != null && previousDenominator > 0) {
        reusableCacheReadTokens += point.cacheReadTokens;
        reusablePrefixTokens += previousDenominator;
      }
    }
    final denominator =
        cacheReadTokens + cacheWriteTokens + uncachedPromptTokens;
    final averageHitRatio = unitRatio(cacheReadTokens, denominator);
    final averagePrefixReuseRatio = reusablePrefixTokens > 0
        ? unitRatio(reusableCacheReadTokens, reusablePrefixTokens)
        : null;
    final visibleTurnIndexes = chartPoints
        .map((point) => point.turnIndex)
        .toSet();
    return SessionCacheHitDisplayData(
      mode: mode,
      trend: SessionCacheHitTrend(
        points: List<SessionCacheHitTurnPoint>.unmodifiable(chartPoints),
        averageHitRatio: averageHitRatio,
        claudeStyle: claudeStyle,
      ),
      averageHitRatio: averageHitRatio,
      averagePrefixReuseRatio: averagePrefixReuseRatio,
      cacheReadTokens: cacheReadTokens,
      cacheWriteTokens: cacheWriteTokens,
      uncachedPromptTokens: uncachedPromptTokens,
      excludedPointCount: points.length - chartPoints.length,
      excludedFirstRequestCount: points.where((point) {
        return point.isFirstRequest &&
            !visibleTurnIndexes.contains(point.turnIndex);
      }).length,
      excludedExpiredMissCount: points.where((point) {
        return !point.isFirstRequest &&
            _isExpiredCacheMiss(point) &&
            !visibleTurnIndexes.contains(point.turnIndex);
      }).length,
      averagePointCount: averagePoints.length,
    );
  }

  static SessionCacheHitTrend fromSession(
    AiSession session, {
    required bool claudeStyle,
  }) {
    final points = <SessionCacheHitTurnPoint>[];
    var turnIndex = 0;
    var averagePromptTotal = 0;
    var averageCacheReadTotal = 0;
    var averageCacheWriteTotal = 0;
    int? previousDenominatorTokens;
    AiSessionMessage? previousRoundStarter;

    for (var index = 0; index < session.messages.length; index++) {
      final message = session.messages[index];
      if (!message.startsConversationRound) {
        continue;
      }
      final previousStarter = previousRoundStarter;
      previousRoundStarter = message;
      final telemetryMessage = _cacheHitRelatedTelemetryMessage(
        session.messages,
        index,
      );
      if (telemetryMessage == null) {
        continue;
      }
      final usage = telemetryMessage.usage ?? message.usage;
      final usageEstimated =
          telemetryMessage
              .metadata[aiSessionMessageUsageEstimatedMetadataKey] ==
          true;
      final hasCacheUsageTelemetry = _hasCacheUsageTelemetry(usage);
      if (usageEstimated && !hasCacheUsageTelemetry) {
        continue;
      }
      final promptTokens = usage?.promptTokens ?? 0;
      final cacheReadTokens = usage?.cacheReadTokens ?? 0;
      final cacheWriteTokens = usage?.cacheCreationTokens ?? 0;
      final hitRatio = computeCacheHitRatio(
        promptTokens: promptTokens,
        cacheReadTokens: cacheReadTokens,
        claudeStyle: claudeStyle,
        cacheWriteTokens: cacheWriteTokens,
      );
      final denominator = computeCacheHitDenominatorTokens(
        promptTokens: promptTokens,
        cacheReadTokens: cacheReadTokens,
        claudeStyle: claudeStyle,
        cacheWriteTokens: cacheWriteTokens,
      );
      if (denominator <= 0) {
        continue;
      }
      turnIndex += 1;
      final pointPreviousDenominator = previousDenominatorTokens;
      previousDenominatorTokens = denominator;
      // 供应商未返回缓存字段时只能判定为“未知”，不能伪造为 0% 命中。
      if (!hasCacheUsageTelemetry) {
        continue;
      }
      averagePromptTotal += promptTokens;
      averageCacheReadTotal += cacheReadTokens;
      averageCacheWriteTotal += cacheWriteTokens;
      final averageHitRatio = computeCacheHitRatio(
        promptTokens: averagePromptTotal,
        cacheReadTokens: averageCacheReadTotal,
        claudeStyle: claudeStyle,
        cacheWriteTokens: averageCacheWriteTotal,
      );
      final fallbackIdleGapSeconds = previousStarter == null
          ? null
          : message.createdAt.difference(previousStarter.createdAt).inSeconds;
      final prefixReuseRatio =
          pointPreviousDenominator != null && pointPreviousDenominator > 0
          ? unitRatio(cacheReadTokens, pointPreviousDenominator)
          : null;
      final diagnostics = _cacheHitDiagnostics(
        primaryMetadata: telemetryMessage.metadata,
        relatedMetadata: message.metadata,
        fallbackIdleGapSeconds: fallbackIdleGapSeconds,
        hitRatio: hitRatio,
        prefixReuseRatio: prefixReuseRatio,
        requiresExplicitCacheControls: claudeStyle,
      );
      final anchor = session.transcriptAnchorForRoundStarter(message.id);
      points.add(
        SessionCacheHitTurnPoint(
          turnIndex: turnIndex,
          starterMessageId: message.id,
          starterMessageKind: message.kind.storageValue,
          starterOrigin: message.senderOrigin,
          anchorMessageId: anchor?.id ?? '',
          timestamp: telemetryMessage.createdAt,
          hitRatio: hitRatio,
          averageHitRatio: averageHitRatio,
          promptTokens: promptTokens,
          cacheReadTokens: cacheReadTokens,
          cacheWriteTokens: cacheWriteTokens,
          denominatorTokens: denominator,
          previousDenominatorTokens: pointPreviousDenominator,
          idleGapSeconds: diagnostics.idleGapSeconds,
          ttlSuspected: diagnostics.ttlSuspected,
          prefixDriftSuspected: diagnostics.prefixDriftSuspected,
          automaticProviderMissSuspected:
              diagnostics.automaticProviderMissSuspected,
        ),
      );
    }

    return _buildTrend(points, claudeStyle: claudeStyle);
  }

  static bool statisticsTrendUsesRoundStarterSchema(
    AiSessionStatistics statistics,
  ) {
    final points = statistics.cacheHitTrendPoints;
    return points.isNotEmpty &&
        points.every(
          (point) =>
              point.schemaVersion >=
                  AiSessionCacheHitTrendPoint.currentSchemaVersion &&
              point.starterOrigin != null,
        );
  }

  static bool statisticsNeedHydration(AiSession session) {
    final statistics = session.statistics;
    if (!statistics.hasCacheUsageTelemetry || session.messageTotalCount <= 0) {
      return false;
    }
    final cacheRead = statistics.cacheReadTokens ?? 0;
    final cacheWrite = statistics.cacheCreationTokens ?? 0;
    final hasCacheTokens = cacheRead > 0 || cacheWrite > 0;
    final hasCurrentTrendSchema = statisticsTrendUsesRoundStarterSchema(
      statistics,
    );
    final staleZeroRatio =
        cacheRead > 0 &&
        (statistics.cacheHitRatio ?? 0) <= 0 &&
        !hasCurrentTrendSchema;
    final likelyWindowedStatistics =
        session.hasPartialMessages &&
        statistics.totalMessageCount < session.messageTotalCount;
    return staleZeroRatio ||
        (hasCacheTokens &&
            (!hasCurrentTrendSchema || likelyWindowedStatistics));
  }

  static SessionCacheHitTrend fromStatistics(
    AiSessionStatistics statistics, {
    required bool claudeStyle,
  }) {
    final points = <SessionCacheHitTurnPoint>[];
    var promptTotal = 0;
    var cacheReadTotal = 0;
    var cacheWriteTotal = 0;
    int? previousDenominatorTokens;
    final fallbackTimestamp = DateTime.fromMillisecondsSinceEpoch(
      0,
      isUtc: true,
    );
    for (final point in statistics.cacheHitTrendPoints) {
      final denominator = computeCacheHitDenominatorTokens(
        promptTokens: point.promptTokens,
        cacheReadTokens: point.cacheReadTokens,
        cacheWriteTokens: point.cacheWriteTokens,
        claudeStyle: claudeStyle,
      );
      if (denominator <= 0) continue;
      promptTotal += point.promptTokens;
      cacheReadTotal += point.cacheReadTokens;
      cacheWriteTotal += point.cacheWriteTokens;
      final hitRatio = computeCacheHitRatio(
        promptTokens: point.promptTokens,
        cacheReadTokens: point.cacheReadTokens,
        cacheWriteTokens: point.cacheWriteTokens,
        claudeStyle: claudeStyle,
      );
      final averageHitRatio = computeCacheHitRatio(
        promptTokens: promptTotal,
        cacheReadTokens: cacheReadTotal,
        cacheWriteTokens: cacheWriteTotal,
        claudeStyle: claudeStyle,
      );
      final ttlSuspected = _isExpiredCacheMissByValues(
        idleGapSeconds: point.idleGapSeconds,
        hitRatio: hitRatio,
      );
      points.add(
        SessionCacheHitTurnPoint(
          turnIndex: point.turnIndex,
          starterMessageId: point.starterMessageId ?? '',
          starterMessageKind: point.starterMessageKind ?? '',
          starterOrigin: point.starterOrigin ?? '',
          anchorMessageId: point.anchorMessageId ?? '',
          timestamp: fallbackTimestamp,
          hitRatio: hitRatio,
          averageHitRatio: averageHitRatio,
          promptTokens: point.promptTokens,
          cacheReadTokens: point.cacheReadTokens,
          cacheWriteTokens: point.cacheWriteTokens,
          denominatorTokens: denominator,
          previousDenominatorTokens:
              point.previousDenominatorTokens ?? previousDenominatorTokens,
          idleGapSeconds: point.idleGapSeconds,
          ttlSuspected: ttlSuspected,
          prefixDriftSuspected: false,
          automaticProviderMissSuspected: false,
        ),
      );
      previousDenominatorTokens = denominator;
    }
    return _buildTrend(points, claudeStyle: claudeStyle);
  }

  static SessionCacheHitTrend _buildTrend(
    List<SessionCacheHitTurnPoint> points, {
    required bool claudeStyle,
  }) {
    final averageHitRatio = _averageCacheHitRatioForPoints(
      points.where((point) {
        return !point.isFirstRequest && !_isExpiredCacheMiss(point);
      }),
      claudeStyle: claudeStyle,
    );
    return SessionCacheHitTrend(
      points: List<SessionCacheHitTurnPoint>.unmodifiable(points),
      averageHitRatio: averageHitRatio,
      claudeStyle: claudeStyle,
    );
  }

  static SessionCacheHitTrend fromStatisticsOrSession(
    AiSession session, {
    required bool claudeStyle,
  }) {
    if (statisticsTrendUsesRoundStarterSchema(session.statistics)) {
      return fromStatistics(session.statistics, claudeStyle: claudeStyle);
    }
    return fromSession(session, claudeStyle: claudeStyle);
  }
}

bool _hasCacheUsageTelemetry(AiTokenUsage? usage) {
  return usage?.cacheReadTokens != null || usage?.cacheCreationTokens != null;
}

double _averageCacheHitRatioForPoints(
  Iterable<SessionCacheHitTurnPoint> points, {
  required bool claudeStyle,
}) {
  var cacheReadTokens = 0;
  var cacheWriteTokens = 0;
  var uncachedPromptTokens = 0;
  for (final point in points) {
    cacheReadTokens += point.cacheReadTokens;
    cacheWriteTokens += point.cacheWriteTokens;
    uncachedPromptTokens += computeUncachedPromptTokens(
      promptTokens: point.promptTokens,
      cacheReadTokens: point.cacheReadTokens,
      claudeStyle: claudeStyle,
      cacheWriteTokens: point.cacheWriteTokens,
    );
  }
  final denominator = cacheReadTokens + cacheWriteTokens + uncachedPromptTokens;
  return unitRatio(cacheReadTokens, denominator);
}

class _CacheHitDiagnostics {
  const _CacheHitDiagnostics({
    required this.idleGapSeconds,
    required this.ttlSuspected,
    required this.prefixDriftSuspected,
    required this.automaticProviderMissSuspected,
  });

  final int? idleGapSeconds;
  final bool ttlSuspected;
  final bool prefixDriftSuspected;
  final bool automaticProviderMissSuspected;
}

AiSessionMessage? _cacheHitRelatedTelemetryMessage(
  List<AiSessionMessage> messages,
  int startIndex,
) {
  if (startIndex < 0 || startIndex >= messages.length) {
    return null;
  }
  AiSessionMessage? firstAiReply;
  AiSessionMessage? fallbackTelemetry;
  for (var index = startIndex + 1; index < messages.length; index++) {
    final candidate = messages[index];
    if (candidate.isDeleted) {
      continue;
    }
    if (candidate.startsConversationRound) {
      break;
    }
    if (!candidate.isAiSideConversationMessage) {
      continue;
    }
    firstAiReply ??= candidate;
    if (candidate.usage != null) {
      return candidate;
    }
    fallbackTelemetry ??= candidate.carriesRequestTelemetry ? candidate : null;
  }
  return fallbackTelemetry ?? firstAiReply;
}

_CacheHitDiagnostics _cacheHitDiagnostics({
  required Map<String, Object?> primaryMetadata,
  required Map<String, Object?> relatedMetadata,
  required int? fallbackIdleGapSeconds,
  required double hitRatio,
  required double? prefixReuseRatio,
  required bool requiresExplicitCacheControls,
}) {
  Map<String, Object?>? asMap(Object? value) => switch (value) {
    Map<String, Object?> map => map,
    Map map => stringKeyedMapFromValue(map),
    _ => null,
  };

  final promptMetadata =
      asMap(primaryMetadata['prompt_metadata']) ??
      asMap(relatedMetadata['prompt_metadata']);
  int? firstInt(List<Object?> values) {
    for (final value in values) {
      final parsed = optionalIntFromValue(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool firstBool(List<Object?> values) {
    for (final value in values) {
      final parsed = optionalBoolFromValue(value);
      if (parsed != null) return parsed;
    }
    return false;
  }

  String firstString(List<Object?> values) {
    for (final value in values) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  final idleGapSeconds = firstInt([
    primaryMetadata['idle_gap_seconds'],
    relatedMetadata['idle_gap_seconds'],
    if (promptMetadata != null) promptMetadata['idle_gap_seconds'],
    fallbackIdleGapSeconds,
  ]);
  final stablePrefixHash = firstString([
    primaryMetadata['stable_prefix_hash'],
    relatedMetadata['stable_prefix_hash'],
    if (promptMetadata != null) promptMetadata['stable_prefix_hash'],
  ]);
  final previousStablePrefixHash = firstString([
    primaryMetadata['previous_stable_prefix_hash'],
    relatedMetadata['previous_stable_prefix_hash'],
    if (promptMetadata != null) promptMetadata['previous_stable_prefix_hash'],
  ]);
  final toolCatalogHash = firstString([
    primaryMetadata['tool_catalog_hash'],
    relatedMetadata['tool_catalog_hash'],
    if (promptMetadata != null) promptMetadata['tool_catalog_hash'],
  ]);
  final previousToolCatalogHash = firstString([
    primaryMetadata['previous_tool_catalog_hash'],
    relatedMetadata['previous_tool_catalog_hash'],
    if (promptMetadata != null) promptMetadata['previous_tool_catalog_hash'],
  ]);
  final inputCacheEnabled = firstBool([
    primaryMetadata['cache_enabled'],
    primaryMetadata['input_cache_enabled'],
    relatedMetadata['cache_enabled'],
    relatedMetadata['input_cache_enabled'],
    if (promptMetadata != null) promptMetadata['cache_enabled'],
    if (promptMetadata != null) promptMetadata['input_cache_enabled'],
  ]);
  final cacheControlStrategy = firstString([
    primaryMetadata['cache_control_strategy'],
    relatedMetadata['cache_control_strategy'],
    if (promptMetadata != null) promptMetadata['cache_control_strategy'],
  ]);
  final automaticProviderCacheProtected = firstBool([
    primaryMetadata['cache_provider_automatic_cache_protected'],
    relatedMetadata['cache_provider_automatic_cache_protected'],
    if (promptMetadata != null)
      promptMetadata['cache_provider_automatic_cache_protected'],
  ]);
  final automaticProviderCacheBestEffort =
      firstBool([
        primaryMetadata['cache_provider_automatic_cache_best_effort'],
        relatedMetadata['cache_provider_automatic_cache_best_effort'],
        if (promptMetadata != null)
          promptMetadata['cache_provider_automatic_cache_best_effort'],
      ]) ||
      cacheControlStrategy == 'automatic_provider_cache';
  final cacheAffinityEnabled = firstBool([
    primaryMetadata['cache_affinity_enabled'],
    relatedMetadata['cache_affinity_enabled'],
    if (promptMetadata != null) promptMetadata['cache_affinity_enabled'],
  ]);
  final protocolControlled =
      firstBool([
        primaryMetadata['cache_protocol_controlled'],
        relatedMetadata['cache_protocol_controlled'],
        if (promptMetadata != null) promptMetadata['cache_protocol_controlled'],
      ]) ||
      cacheControlStrategy == 'explicit_cache_control';
  final explicitCacheControlsRequired =
      requiresExplicitCacheControls || protocolControlled;
  final stablePrefixCacheEnabled =
      inputCacheEnabled ||
      automaticProviderCacheProtected ||
      automaticProviderCacheBestEffort;
  final requestCacheControlMarkerCount = firstInt([
    primaryMetadata['request_cache_control_marker_count'],
    relatedMetadata['request_cache_control_marker_count'],
  ]);
  final cacheControlsMissing =
      explicitCacheControlsRequired &&
      stablePrefixCacheEnabled &&
      requestCacheControlMarkerCount != null &&
      requestCacheControlMarkerCount <= 0;
  final requestCacheAffinityMarkerCount = firstInt([
    primaryMetadata['request_cache_affinity_marker_count'],
    relatedMetadata['request_cache_affinity_marker_count'],
  ]);
  final cacheAffinityDegraded = firstBool([
    primaryMetadata['cache_affinity_degraded'],
    relatedMetadata['cache_affinity_degraded'],
    if (promptMetadata != null) promptMetadata['cache_affinity_degraded'],
  ]);
  final cacheAffinityMissing =
      cacheAffinityEnabled &&
      !cacheAffinityDegraded &&
      requestCacheAffinityMarkerCount != null &&
      requestCacheAffinityMarkerCount <= 0;
  final stablePrefixKnown =
      stablePrefixHash.isNotEmpty && previousStablePrefixHash.isNotEmpty;
  final stablePrefixUnchanged =
      stablePrefixKnown && stablePrefixHash == previousStablePrefixHash;
  final toolCatalogStable =
      toolCatalogHash.isEmpty ||
      previousToolCatalogHash.isEmpty ||
      toolCatalogHash == previousToolCatalogHash;
  final requestPrefixContinuity = firstBool([
    primaryMetadata['request_payload_prefix_continuity'],
    relatedMetadata['request_payload_prefix_continuity'],
  ]);
  final requestPrefixProbeComplete = firstBool([
    primaryMetadata['request_payload_prefix_probe_complete'],
    relatedMetadata['request_payload_prefix_probe_complete'],
  ]);
  final ttlSuspected = _isExpiredCacheMissByValues(
    idleGapSeconds: idleGapSeconds,
    hitRatio: hitRatio,
  );
  // 前缀复用率达标说明未命中部分只是本轮新增输入：即使原始命中率被大体量
  // 工具结果稀释到阈值以下，也不属于供应商缓存丢失，不应误报。
  final prefixReuseHealthy =
      prefixReuseRatio != null &&
      prefixReuseRatio >= kCacheHitHealthyPrefixReuseRatio;
  final automaticProviderMissSuspected =
      !explicitCacheControlsRequired &&
      (automaticProviderCacheProtected || automaticProviderCacheBestEffort) &&
      !ttlSuspected &&
      !prefixReuseHealthy &&
      stablePrefixUnchanged &&
      toolCatalogStable &&
      idleGapSeconds != null &&
      idleGapSeconds >= kAutomaticProviderCacheMissMinGapSeconds &&
      hitRatio < kAutomaticProviderCacheMissHitRatioThreshold;
  final prefixDriftSuspected =
      !ttlSuspected &&
      !automaticProviderMissSuspected &&
      idleGapSeconds != null &&
      idleGapSeconds < 3600 &&
      ((stablePrefixKnown && stablePrefixHash != previousStablePrefixHash) ||
          (requestPrefixProbeComplete && !requestPrefixContinuity) ||
          (toolCatalogHash.isNotEmpty &&
              previousToolCatalogHash.isNotEmpty &&
              toolCatalogHash != previousToolCatalogHash) ||
          cacheControlsMissing ||
          cacheAffinityMissing);
  return _CacheHitDiagnostics(
    idleGapSeconds: idleGapSeconds,
    ttlSuspected: ttlSuspected,
    prefixDriftSuspected: prefixDriftSuspected,
    automaticProviderMissSuspected: automaticProviderMissSuspected,
  );
}

/// 过期异常 = 长时间空闲（> 30 分钟）后命中率不足 3% 的轮次。
///
/// 设计要点：
/// - 用 `idleGapSeconds > 1800`（超过 30 分钟）排除会话内短暂停顿造成的低命中轮，
///   也避免冷启动首轮（idleGap 为 0）被误判。
/// - 用 `hitRatio < 0.03`（3%）作为过期异常阈值；只要存在少量残留命中，
///   也能按请求级真实比例正确归类。
/// - 不再依赖 `cacheReadTokens <= 0` 的硬等于判定，避免因少量残留命中导致
///   整轮过期异常被忽略。
bool _isExpiredCacheMiss(SessionCacheHitTurnPoint point) {
  return _isExpiredCacheMissByValues(
    idleGapSeconds: point.idleGapSeconds,
    hitRatio: point.hitRatio,
  );
}

bool _isExpiredCacheMissByValues({
  required int? idleGapSeconds,
  required double hitRatio,
}) {
  final idleGap = idleGapSeconds ?? 0;
  if (idleGap <= kCacheHitExpiryIdleGapSeconds) {
    return false;
  }
  return hitRatio < kCacheHitExpiryHitRatioThreshold;
}

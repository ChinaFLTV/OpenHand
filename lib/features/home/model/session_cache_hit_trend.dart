import '../../../shared/util/input_value_parsing.dart';
import '../../ai/index.dart';
import 'cache_hit_ratio.dart';

/// 过期异常判定：距离上一轮请求超过 30 分钟，且本轮缓存命中率不足 3%。
const int kCacheHitExpiryIdleGapSeconds = 1800; // 30 分钟
const double kCacheHitExpiryHitRatioThreshold = 0.03; // 3%
const int kAutomaticProviderCacheMissMinGapSeconds = 0;
const double kAutomaticProviderCacheMissHitRatioThreshold = 0.80;

enum SessionCacheHitDisplayMode { excludeExpiredMisses, includeExpiredMisses }

class SessionCacheHitDisplayData {
  const SessionCacheHitDisplayData({
    required this.mode,
    required this.trend,
    required this.averageHitRatio,
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
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int uncachedPromptTokens;
  final int excludedPointCount;
  final int excludedFirstRequestCount;
  final int excludedExpiredMissCount;
  final int averagePointCount;
}

bool shouldShowSessionCacheHitMetrics({
  required int totalPromptTokens,
  required int totalTokens,
  required int cacheReadTokens,
  required int cacheWriteTokens,
  required bool hasTrendPoints,
}) {
  return cacheReadTokens > 0 || cacheWriteTokens > 0 || hasTrendPoints;
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
  final int? idleGapSeconds;
  final bool ttlSuspected;
  final bool prefixDriftSuspected;
  final bool automaticProviderMissSuspected;

  bool get isFirstRequest => turnIndex <= 1;

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
    // A cache point is one model request + one model response. Tool-result
    // continuations are first-class requests; the default view only removes the
    // cold first request and true long-idle expiry misses.
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
    for (final point in averagePoints) {
      cacheReadTokens += point.cacheReadTokens;
      cacheWriteTokens += point.cacheWriteTokens;
      uncachedPromptTokens += computeUncachedPromptTokens(
        promptTokens: point.promptTokens,
        cacheReadTokens: point.cacheReadTokens,
        claudeStyle: claudeStyle,
        cacheWriteTokens: point.cacheWriteTokens,
      );
    }
    final denominator =
        cacheReadTokens + cacheWriteTokens + uncachedPromptTokens;
    final averageHitRatio = unitRatio(cacheReadTokens, denominator);
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
    final sessionHasCacheUsageTelemetry = _sessionHasCacheUsageTelemetry(
      session,
    );
    var turnIndex = 0;
    var averagePromptTotal = 0;
    var averageCacheReadTotal = 0;
    var averageCacheWriteTotal = 0;
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
      if (!sessionHasCacheUsageTelemetry && !_hasCacheUsageTelemetry(usage)) {
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
      final diagnostics = _cacheHitDiagnostics(
        primaryMetadata: telemetryMessage.metadata,
        relatedMetadata: message.metadata,
        fallbackIdleGapSeconds: fallbackIdleGapSeconds,
        hitRatio: hitRatio,
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
          idleGapSeconds: diagnostics.idleGapSeconds,
          ttlSuspected: diagnostics.ttlSuspected,
          prefixDriftSuspected: diagnostics.prefixDriftSuspected,
          automaticProviderMissSuspected:
              diagnostics.automaticProviderMissSuspected,
        ),
      );
    }

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

  static bool statisticsTrendUsesRoundStarterSchema(
    AiSessionStatistics statistics,
  ) {
    final points = statistics.cacheHitTrendPoints;
    return points.isNotEmpty &&
        points.every((point) => point.starterOrigin != null);
  }

  static bool statisticsNeedHydration(AiSession session) {
    final statistics = session.statistics;
    final hasCacheUsageTelemetry =
        statistics.cacheReadTokens != null ||
        statistics.cacheCreationTokens != null;
    if (!hasCacheUsageTelemetry || session.messageTotalCount <= 0) {
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
          idleGapSeconds: point.idleGapSeconds,
          ttlSuspected: ttlSuspected,
          prefixDriftSuspected: false,
          automaticProviderMissSuspected: false,
        ),
      );
    }
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

bool _sessionHasCacheUsageTelemetry(AiSession session) {
  for (final message in session.messages) {
    if (_hasCacheUsageTelemetry(message.usage)) {
      return true;
    }
  }
  return false;
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
    final metadata = candidate.metadata;
    final hasTelemetry =
        candidate.modelId != null ||
        candidate.usage != null ||
        metadata.containsKey('started_at') ||
        metadata.containsKey('request_url') ||
        metadata.containsKey('request_payload') ||
        metadata.containsKey('response_raw') ||
        metadata.containsKey('error') ||
        metadata.containsKey('telemetry');
    fallbackTelemetry ??= hasTelemetry ? candidate : null;
  }
  return fallbackTelemetry ?? firstAiReply;
}

_CacheHitDiagnostics _cacheHitDiagnostics({
  required Map<String, Object?> primaryMetadata,
  required Map<String, Object?> relatedMetadata,
  required int? fallbackIdleGapSeconds,
  required double hitRatio,
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
  final requestPrefixStable =
      !requestPrefixProbeComplete || requestPrefixContinuity;
  final ttlSuspected = _isExpiredCacheMissByValues(
    idleGapSeconds: idleGapSeconds,
    hitRatio: hitRatio,
  );
  final automaticProviderMissSuspected =
      !explicitCacheControlsRequired &&
      (automaticProviderCacheProtected || automaticProviderCacheBestEffort) &&
      !ttlSuspected &&
      stablePrefixUnchanged &&
      toolCatalogStable &&
      requestPrefixStable &&
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

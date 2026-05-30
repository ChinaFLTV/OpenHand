import '../../ai/index.dart';

enum SessionCacheMissKind { normal, ttlSuspected, prefixDrift }

class SessionCacheHitTurnPoint {
  const SessionCacheHitTurnPoint({
    required this.turnIndex,
    required this.timestamp,
    required this.hitRatio,
    required this.averageHitRatio,
    required this.promptTokens,
    required this.cacheReadTokens,
    required this.idleGapSeconds,
    required this.ttlSuspected,
    required this.prefixDriftSuspected,
  });

  final int turnIndex;
  final DateTime timestamp;
  final double hitRatio;
  final double averageHitRatio;
  final int promptTokens;
  final int cacheReadTokens;
  final int? idleGapSeconds;
  final bool ttlSuspected;
  final bool prefixDriftSuspected;

  SessionCacheMissKind get missKind {
    if (ttlSuspected) return SessionCacheMissKind.ttlSuspected;
    if (prefixDriftSuspected) return SessionCacheMissKind.prefixDrift;
    return SessionCacheMissKind.normal;
  }
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
    final normalizedAnchor = span <= 0
        ? 0.0
        : ((anchor - start) / span).clamp(0.0, 1.0);
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
  });

  final List<SessionCacheHitTurnPoint> points;
  final double averageHitRatio;

  bool get hasEnoughPoints => points.length >= 2;

  static SessionCacheHitTrend fromSession(
    AiSession session, {
    required bool claudeStyle,
  }) {
    final points = <SessionCacheHitTurnPoint>[];
    var turnIndex = 0;
    var pendingUserTurn = false;
    var averagePromptTotal = 0;
    var averageCacheReadTotal = 0;

    for (final message in session.visibleMessages) {
      if (message.kind == AiSessionMessageKind.user) {
        pendingUserTurn = true;
        continue;
      }
      if (!pendingUserTurn || message.kind != AiSessionMessageKind.assistant) {
        continue;
      }
      final usage = message.usage;
      final promptTokens = usage?.promptTokens ?? 0;
      final cacheReadTokens = usage?.cacheReadTokens ?? 0;
      final denominator = claudeStyle
          ? promptTokens + cacheReadTokens
          : promptTokens;
      if (denominator <= 0) {
        pendingUserTurn = false;
        continue;
      }
      turnIndex += 1;
      if (turnIndex > 1) {
        averagePromptTotal += promptTokens;
        averageCacheReadTotal += cacheReadTokens;
      }
      final hitRatio = cacheReadTokens / denominator;
      final averageHitRatio =
          averagePromptTotal <= 0 && averageCacheReadTotal <= 0
          ? 0.0
          : averageCacheReadTotal /
                (claudeStyle
                    ? averagePromptTotal + averageCacheReadTotal
                    : averagePromptTotal);
      final metadata = message.metadata;
      final idleGapSeconds = switch (metadata['idle_gap_seconds']) {
        int value => value,
        num value => value.toInt(),
        _ => int.tryParse('${metadata['idle_gap_seconds'] ?? ''}'),
      };
      final stablePrefixHash = '${metadata['stable_prefix_hash'] ?? ''}'.trim();
      final previousStablePrefixHash =
          '${metadata['previous_stable_prefix_hash'] ?? ''}'.trim();
      final toolCatalogHash = '${metadata['tool_catalog_hash'] ?? ''}'.trim();
      final previousToolCatalogHash =
          '${metadata['previous_tool_catalog_hash'] ?? ''}'.trim();
      final ttlSuspected = metadata['ttl_suspected'] == true;
      final prefixDriftSuspected =
          !ttlSuspected &&
          cacheReadTokens <= 0 &&
          idleGapSeconds != null &&
          idleGapSeconds < 3600 &&
          ((stablePrefixHash.isNotEmpty &&
                  previousStablePrefixHash.isNotEmpty &&
                  stablePrefixHash != previousStablePrefixHash) ||
              (toolCatalogHash.isNotEmpty &&
                  previousToolCatalogHash.isNotEmpty &&
                  toolCatalogHash != previousToolCatalogHash));
      points.add(
        SessionCacheHitTurnPoint(
          turnIndex: turnIndex,
          timestamp: message.createdAt,
          hitRatio: hitRatio.clamp(0.0, 1.0),
          averageHitRatio: averageHitRatio.isFinite
              ? averageHitRatio.clamp(0.0, 1.0)
              : 0.0,
          promptTokens: promptTokens,
          cacheReadTokens: cacheReadTokens,
          idleGapSeconds: idleGapSeconds,
          ttlSuspected: ttlSuspected,
          prefixDriftSuspected: prefixDriftSuspected,
        ),
      );
      pendingUserTurn = false;
    }

    final averageHitRatio =
        averagePromptTotal <= 0 && averageCacheReadTotal <= 0
        ? 0.0
        : averageCacheReadTotal /
              (claudeStyle
                  ? averagePromptTotal + averageCacheReadTotal
                  : averagePromptTotal);
    return SessionCacheHitTrend(
      points: List<SessionCacheHitTurnPoint>.unmodifiable(points),
      averageHitRatio: averageHitRatio.isFinite
          ? averageHitRatio.clamp(0.0, 1.0)
          : 0.0,
    );
  }
}

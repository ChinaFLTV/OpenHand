import '../../ai/index.dart';
import 'cache_hit_ratio.dart';

enum SessionCacheMissKind { normal, ttlSuspected, prefixDrift }

/// "极端值"判定：长时间空闲（≥ 30 分钟）后命中率近乎为 0（< 1%）。
const int kExtremeIdleGapSeconds = 1800; // 30 分钟
const double kExtremeHitRatioThreshold = 0.01; // 1%
const int kShortAutoCacheIdleGapSeconds = 60;
const double kPartialAutoCacheHitRatioThreshold = 0.80;

enum SessionCacheHitDisplayMode { excludeExtremeMisses, includeAll }

class SessionCacheHitDisplayData {
  const SessionCacheHitDisplayData({
    required this.mode,
    required this.trend,
    required this.averageHitRatio,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.uncachedPromptTokens,
    required this.excludedPointCount,
  });

  final SessionCacheHitDisplayMode mode;
  final SessionCacheHitTrend trend;
  final double averageHitRatio;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int uncachedPromptTokens;
  final int excludedPointCount;
}

class SessionCacheHitTurnPoint {
  const SessionCacheHitTurnPoint({
    required this.turnIndex,
    required this.timestamp,
    required this.hitRatio,
    required this.averageHitRatio,
    required this.promptTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
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
  final int cacheWriteTokens;
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
    required this.claudeStyle,
  });

  final List<SessionCacheHitTurnPoint> points;
  final double averageHitRatio;
  final bool claudeStyle;

  bool get hasEnoughPoints => points.length >= 2;
  bool get hasExtremeIdleExpiryMisses => points.any(_isExtremeIdleExpiryMiss);

  SessionCacheHitDisplayData displayData(SessionCacheHitDisplayMode mode) {
    final filteredPoints = switch (mode) {
      SessionCacheHitDisplayMode.includeAll => points,
      SessionCacheHitDisplayMode.excludeExtremeMisses =>
        points
            .where((point) => !_isExtremeIdleExpiryMiss(point))
            .toList(growable: false),
    };
    var cacheReadTokens = 0;
    var cacheWriteTokens = 0;
    var uncachedPromptTokens = 0;
    for (final point in filteredPoints) {
      if (point.turnIndex == 1) {
        continue;
      }
      cacheReadTokens += point.cacheReadTokens;
      cacheWriteTokens += point.cacheWriteTokens;
      uncachedPromptTokens += computeUncachedPromptTokens(
        promptTokens: point.promptTokens,
        cacheReadTokens: point.cacheReadTokens,
        claudeStyle: claudeStyle,
      );
    }
    final denominator = cacheReadTokens + uncachedPromptTokens;
    final averageHitRatio = denominator <= 0
        ? 0.0
        : cacheReadTokens / denominator;
    return SessionCacheHitDisplayData(
      mode: mode,
      trend: SessionCacheHitTrend(
        points: List<SessionCacheHitTurnPoint>.unmodifiable(filteredPoints),
        averageHitRatio: averageHitRatio.clamp(0.0, 1.0),
        claudeStyle: claudeStyle,
      ),
      averageHitRatio: averageHitRatio.clamp(0.0, 1.0),
      cacheReadTokens: cacheReadTokens,
      cacheWriteTokens: cacheWriteTokens,
      uncachedPromptTokens: uncachedPromptTokens,
      excludedPointCount: points.length - filteredPoints.length,
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

    for (var index = 0; index < session.visibleMessages.length; index++) {
      final message = session.visibleMessages[index];
      if (message.kind != AiSessionMessageKind.user) {
        continue;
      }
      final assistantMessage = _cacheHitRelatedTelemetryMessage(
        session,
        message,
      );
      if (assistantMessage == null ||
          assistantMessage.kind != AiSessionMessageKind.assistant) {
        continue;
      }
      final usage = assistantMessage.usage ?? message.usage;
      final promptTokens = usage?.promptTokens ?? 0;
      final cacheReadTokens = usage?.cacheReadTokens ?? 0;
      final cacheWriteTokens = usage?.cacheCreationTokens ?? 0;
      final hitRatio = computeCacheHitRatio(
        promptTokens: promptTokens,
        cacheReadTokens: cacheReadTokens,
        claudeStyle: claudeStyle,
      );
      final denominator = claudeStyle
          ? promptTokens + cacheReadTokens
          : promptTokens;
      if (denominator <= 0) {
        continue;
      }
      turnIndex += 1;
      if (turnIndex > 1) {
        averagePromptTotal += promptTokens;
        averageCacheReadTotal += cacheReadTokens;
      }
      final averageHitRatio = computeCacheHitRatio(
        promptTokens: averagePromptTotal,
        cacheReadTokens: averageCacheReadTotal,
        claudeStyle: claudeStyle,
      );
      final previousUserMessage = _previousUserMessage(session, message.id);
      final fallbackIdleGapSeconds = previousUserMessage == null
          ? null
          : message.createdAt
                .difference(previousUserMessage.createdAt)
                .inSeconds;
      final diagnostics = _cacheHitDiagnostics(
        primaryMetadata: assistantMessage.metadata,
        relatedMetadata: message.metadata,
        fallbackIdleGapSeconds: fallbackIdleGapSeconds,
        hitRatio: hitRatio,
        requiresExplicitCacheControls: claudeStyle,
      );
      points.add(
        SessionCacheHitTurnPoint(
          turnIndex: turnIndex,
          timestamp: assistantMessage.createdAt,
          hitRatio: hitRatio.clamp(0.0, 1.0),
          averageHitRatio: averageHitRatio.isFinite
              ? averageHitRatio.clamp(0.0, 1.0)
              : 0.0,
          promptTokens: promptTokens,
          cacheReadTokens: cacheReadTokens,
          cacheWriteTokens: cacheWriteTokens,
          idleGapSeconds: diagnostics.idleGapSeconds,
          ttlSuspected: diagnostics.ttlSuspected,
          prefixDriftSuspected: diagnostics.prefixDriftSuspected,
        ),
      );
    }

    final averageHitRatio = computeCacheHitRatio(
      promptTokens: averagePromptTotal,
      cacheReadTokens: averageCacheReadTotal,
      claudeStyle: claudeStyle,
    );
    return SessionCacheHitTrend(
      points: List<SessionCacheHitTurnPoint>.unmodifiable(points),
      averageHitRatio: averageHitRatio.isFinite
          ? averageHitRatio.clamp(0.0, 1.0)
          : 0.0,
      claudeStyle: claudeStyle,
    );
  }
}

class _CacheHitDiagnostics {
  const _CacheHitDiagnostics({
    required this.idleGapSeconds,
    required this.ttlSuspected,
    required this.prefixDriftSuspected,
  });

  final int? idleGapSeconds;
  final bool ttlSuspected;
  final bool prefixDriftSuspected;
}

AiSessionMessage? _previousUserMessage(
  AiSession session,
  String currentUserMessageId,
) {
  final startIndex = session.messages.indexWhere(
    (item) => item.id == currentUserMessageId,
  );
  if (startIndex <= 0) {
    return null;
  }
  for (var index = startIndex - 1; index >= 0; index--) {
    final candidate = session.messages[index];
    if (!candidate.isDeleted && candidate.kind == AiSessionMessageKind.user) {
      return candidate;
    }
  }
  return null;
}

AiSessionMessage? _cacheHitRelatedTelemetryMessage(
  AiSession session,
  AiSessionMessage userMessage,
) {
  final startIndex = session.messages.indexWhere(
    (item) => item.id == userMessage.id,
  );
  if (startIndex == -1) {
    return null;
  }
  AiSessionMessage? firstAssistantReply;
  AiSessionMessage? fallbackTelemetry;
  for (var index = startIndex + 1; index < session.messages.length; index++) {
    final candidate = session.messages[index];
    if (candidate.kind == AiSessionMessageKind.user) {
      break;
    }
    if (candidate.isDeleted) {
      continue;
    }
    if (candidate.kind == AiSessionMessageKind.assistant) {
      firstAssistantReply ??= candidate;
      if (candidate.usage != null) {
        return candidate;
      }
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
  return firstAssistantReply ?? fallbackTelemetry;
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
    Map map => Map<String, Object?>.from(map),
    _ => null,
  };

  final promptMetadata =
      asMap(primaryMetadata['prompt_metadata']) ??
      asMap(relatedMetadata['prompt_metadata']);
  int? firstInt(List<Object?> values) {
    for (final value in values) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      final parsed = int.tryParse('${value ?? ''}');
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool firstBool(List<Object?> values) {
    for (final value in values) {
      if (value is bool) return value;
      if (value == null) continue;
      final text = '$value'.trim().toLowerCase();
      if (text == 'true') return true;
      if (text == 'false') return false;
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
  final ttlSuspected = firstBool([
    primaryMetadata['ttl_suspected'],
    relatedMetadata['ttl_suspected'],
    if (promptMetadata != null) promptMetadata['ttl_suspected'],
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
    relatedMetadata['cache_enabled'],
    if (promptMetadata != null) promptMetadata['cache_enabled'],
  ]);
  final cacheControlMarkerCount = firstInt([
    primaryMetadata['request_cache_control_marker_count'],
    relatedMetadata['request_cache_control_marker_count'],
  ]);
  final cacheControlsMissing =
      requiresExplicitCacheControls &&
      inputCacheEnabled &&
      cacheControlMarkerCount != null &&
      cacheControlMarkerCount <= 0;
  final stablePrefixKnown =
      stablePrefixHash.isNotEmpty && previousStablePrefixHash.isNotEmpty;
  final stablePrefixUnchanged =
      stablePrefixKnown && stablePrefixHash == previousStablePrefixHash;
  final toolCatalogStable =
      toolCatalogHash.isEmpty ||
      previousToolCatalogHash.isEmpty ||
      toolCatalogHash == previousToolCatalogHash;
  final shortIdleAutoCacheMissSuspected =
      !requiresExplicitCacheControls &&
      !ttlSuspected &&
      stablePrefixUnchanged &&
      toolCatalogStable &&
      idleGapSeconds != null &&
      idleGapSeconds >= kShortAutoCacheIdleGapSeconds &&
      hitRatio < kPartialAutoCacheHitRatioThreshold;
  final effectiveTtlSuspected = ttlSuspected || shortIdleAutoCacheMissSuspected;
  final prefixDriftSuspected =
      !effectiveTtlSuspected &&
      idleGapSeconds != null &&
      idleGapSeconds < 3600 &&
      ((stablePrefixKnown && stablePrefixHash != previousStablePrefixHash) ||
          (toolCatalogHash.isNotEmpty &&
              previousToolCatalogHash.isNotEmpty &&
              toolCatalogHash != previousToolCatalogHash) ||
          cacheControlsMissing);
  return _CacheHitDiagnostics(
    idleGapSeconds: idleGapSeconds,
    ttlSuspected: effectiveTtlSuspected,
    prefixDriftSuspected: prefixDriftSuspected,
  );
}

/// 极端值 = 长时间空闲（≥ 30 分钟）后命中率近乎为 0（< 1%）的轮次。
///
/// 设计要点：
/// - 用 `idleGapSeconds >= 1800`（30 分钟）排除会话内短暂停顿造成的低命中轮，
///   也避免冷启动首轮（idleGap 为 0）被误判。
/// - 用 `hitRatio < 0.01`（1%）作为"几乎完全失效"阈值；只要存在极少量
///   `cacheReadTokens`（例如远小于 prompt 的 1%）的边界情况，也能正确归类。
/// - 不再依赖 `cacheReadTokens <= 0` 的硬等于判定，避免因少量残留命中导致
///   整轮极端值被忽略。
bool _isExtremeIdleExpiryMiss(SessionCacheHitTurnPoint point) {
  final idleGap = point.idleGapSeconds ?? 0;
  if (idleGap < kExtremeIdleGapSeconds) {
    return false;
  }
  return point.hitRatio < kExtremeHitRatioThreshold;
}

import 'dart:math' as math;

import 'package:characters/characters.dart';

import '../../../shared/util/input_value_parsing.dart';

const int kKnowledgeVectorDistributionDefaultMaxPoints = 600;
const int kKnowledgeVectorDistributionPageSize = 120;
const int kKnowledgeVectorPreviewChars = 50;
const String kKnowledgeVectorProjectionAlgorithm =
    'deterministic_random_projection_3d';
const int _knowledgeVectorTitleChars = 72;
const double _projectionZeroDistanceEpsilon = 1e-9;
const double _projectionMinCoordinate = -1.0;
const double _projectionMaxCoordinate = 1.0;
const double _fallbackRadiusBase = 0.34;
const double _fallbackRadiusSpread = 0.56;

class KnowledgeVectorPointKind {
  const KnowledgeVectorPointKind._();

  static const corpus = 'corpus';
  static const match = 'match';
  static const query = 'query';
}

class KnowledgeVectorProjectionInput {
  const KnowledgeVectorProjectionInput({
    required this.id,
    required this.kind,
    required this.title,
    required this.preview,
    required this.vector,
    this.score,
    this.rerankScore,
  });

  final String id;
  final String kind;
  final String title;
  final String preview;
  final List<double> vector;
  final double? score;
  final double? rerankScore;
}

class KnowledgeVectorDistributionPoint {
  const KnowledgeVectorDistributionPoint({
    required this.id,
    required this.kind,
    required this.title,
    required this.preview,
    required this.x,
    required this.y,
    required this.z,
    this.score,
    this.rerankScore,
  });

  final String id;
  final String kind;
  final String title;
  final String preview;
  final double x;
  final double y;
  final double z;
  final double? score;
  final double? rerankScore;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind,
      'title': title,
      'preview': preview,
      'x': x,
      'y': y,
      'z': z,
      if (score != null) 'score': score,
      if (rerankScore != null) 'rerank_score': rerankScore,
    };
  }

  static KnowledgeVectorDistributionPoint? fromJson(Object? value) {
    final map = stringKeyedMapFromValue(value);
    if (map.isEmpty) return null;
    final id = '${map['id'] ?? ''}'.trim();
    final kind = '${map['kind'] ?? ''}'.trim();
    final x = optionalDoubleFromValue(map['x']);
    final y = optionalDoubleFromValue(map['y']);
    final z = optionalDoubleFromValue(map['z']);
    if (id.isEmpty || kind.isEmpty || x == null || y == null || z == null) {
      return null;
    }
    return KnowledgeVectorDistributionPoint(
      id: id,
      kind: kind,
      title: '${map['title'] ?? ''}'.trim(),
      preview: '${map['preview'] ?? ''}'.trim(),
      x: x,
      y: y,
      z: z,
      score: optionalDoubleFromValue(map['score']),
      rerankScore: optionalDoubleFromValue(map['rerank_score']),
    );
  }
}

class KnowledgeVectorDistribution {
  const KnowledgeVectorDistribution({
    required this.points,
    required this.originalDimensions,
    this.algorithm = kKnowledgeVectorProjectionAlgorithm,
    this.sampledCount = 0,
    this.hasMore = false,
    this.durationMs,
    this.generatedAt,
  });

  final List<KnowledgeVectorDistributionPoint> points;
  final int originalDimensions;
  final String algorithm;
  final int sampledCount;
  final bool hasMore;
  final int? durationMs;
  final DateTime? generatedAt;

  bool get isEmpty => points.isEmpty;

  KnowledgeVectorDistribution copyWith({
    List<KnowledgeVectorDistributionPoint>? points,
    int? originalDimensions,
    String? algorithm,
    int? sampledCount,
    bool? hasMore,
    int? durationMs,
    DateTime? generatedAt,
  }) {
    return KnowledgeVectorDistribution(
      points: points ?? this.points,
      originalDimensions: originalDimensions ?? this.originalDimensions,
      algorithm: algorithm ?? this.algorithm,
      sampledCount: sampledCount ?? this.sampledCount,
      hasMore: hasMore ?? this.hasMore,
      durationMs: durationMs ?? this.durationMs,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'algorithm': algorithm,
      'original_dimensions': originalDimensions,
      'sampled_count': sampledCount,
      'has_more': hasMore,
      if (durationMs != null) 'duration_ms': durationMs,
      if (generatedAt != null)
        'generated_at': generatedAt!.toUtc().toIso8601String(),
      'points': points.map((point) => point.toJson()).toList(growable: false),
    };
  }

  static KnowledgeVectorDistribution? fromJson(Object? value) {
    final map = stringKeyedMapFromValue(value);
    if (map.isEmpty) return null;
    final points = stringKeyedMapListFromValue(map['points'])
        .map(KnowledgeVectorDistributionPoint.fromJson)
        .whereType<KnowledgeVectorDistributionPoint>()
        .toList(growable: false);
    return KnowledgeVectorDistribution(
      points: points,
      originalDimensions: nonNegativeIntFromValue(
        map['original_dimensions'],
        fallback: 0,
      ),
      algorithm:
          nullIfBlank('${map['algorithm'] ?? ''}') ??
          kKnowledgeVectorProjectionAlgorithm,
      sampledCount: nonNegativeIntFromValue(
        map['sampled_count'],
        fallback: points.length,
      ),
      hasMore: boolFromValue(map['has_more']),
      durationMs: optionalNonNegativeIntFromValue(map['duration_ms']),
      generatedAt: dateTimeFromValue(map['generated_at']),
    );
  }
}

class KnowledgeVectorProjector {
  const KnowledgeVectorProjector._();

  static KnowledgeVectorDistribution project({
    required List<KnowledgeVectorProjectionInput> inputs,
    required int originalDimensions,
    bool hasMore = false,
    int? durationMs,
    DateTime? generatedAt,
  }) {
    final valid = inputs.where(_hasFiniteVector).toList(growable: false);
    if (valid.isEmpty) {
      return KnowledgeVectorDistribution(
        points: const <KnowledgeVectorDistributionPoint>[],
        originalDimensions: originalDimensions,
        sampledCount: inputs.length,
        hasMore: hasMore,
        durationMs: durationMs,
        generatedAt: generatedAt,
      );
    }
    final dimensions = math.max(
      1,
      valid.fold<int>(
        0,
        (maxLength, input) => math.max(maxLength, input.vector.length),
      ),
    );
    final mean = List<double>.filled(dimensions, 0);
    final counts = List<int>.filled(dimensions, 0);
    for (final input in valid) {
      for (var i = 0; i < input.vector.length && i < dimensions; i++) {
        final value = input.vector[i];
        if (!_isFinite(value)) continue;
        mean[i] += value;
        counts[i] += 1;
      }
    }
    for (var i = 0; i < dimensions; i++) {
      if (counts[i] > 0) mean[i] /= counts[i];
    }

    final projected =
        <
          ({KnowledgeVectorProjectionInput input, double x, double y, double z})
        >[];
    for (final input in valid) {
      var x = 0.0;
      var y = 0.0;
      var z = 0.0;
      for (var i = 0; i < input.vector.length && i < dimensions; i++) {
        final value = input.vector[i];
        if (!_isFinite(value)) continue;
        final centered = value - mean[i];
        x += centered * _axisWeight(i, 0);
        y += centered * _axisWeight(i, 1);
        z += centered * _axisWeight(i, 2);
      }
      final factor = 1 / math.sqrt(dimensions);
      projected.add((
        input: input,
        x: x * factor,
        y: y * factor,
        z: z * factor,
      ));
    }

    var cx = 0.0;
    var cy = 0.0;
    var cz = 0.0;
    for (final item in projected) {
      cx += item.x;
      cy += item.y;
      cz += item.z;
    }
    cx /= projected.length;
    cy /= projected.length;
    cz /= projected.length;

    var maxDistance = 0.0;
    for (final item in projected) {
      maxDistance = math.max(
        maxDistance,
        math.sqrt(
          math.pow(item.x - cx, 2) +
              math.pow(item.y - cy, 2) +
              math.pow(item.z - cz, 2),
        ),
      );
    }

    final points = <KnowledgeVectorDistributionPoint>[];
    for (var index = 0; index < projected.length; index++) {
      final item = projected[index];
      final fallbackAngle = index * math.pi * (3 - math.sqrt(5));
      final fallbackRadius = _fallbackRadius(index, projected.length);
      final normalized = maxDistance <= _projectionZeroDistanceEpsilon
          ? (
              x: math.cos(fallbackAngle) * fallbackRadius,
              y: math.sin(fallbackAngle) * fallbackRadius,
              z: _fallbackZ(index),
            )
          : (
              x: _normalizedCoordinate(item.x, cx, maxDistance),
              y: _normalizedCoordinate(item.y, cy, maxDistance),
              z: _normalizedCoordinate(item.z, cz, maxDistance),
            );
      points.add(
        KnowledgeVectorDistributionPoint(
          id: item.input.id,
          kind: item.input.kind,
          title: _truncate(item.input.title, _knowledgeVectorTitleChars),
          preview: _truncate(item.input.preview, kKnowledgeVectorPreviewChars),
          x: normalized.x,
          y: normalized.y,
          z: normalized.z,
          score: item.input.score,
          rerankScore: item.input.rerankScore,
        ),
      );
    }

    return KnowledgeVectorDistribution(
      points: points,
      originalDimensions: originalDimensions > 0
          ? originalDimensions
          : dimensions,
      sampledCount: inputs.length,
      hasMore: hasMore,
      durationMs: durationMs,
      generatedAt: generatedAt,
    );
  }

  static double _axisWeight(int dimension, int axis) {
    final seed =
        math.sin((dimension + 1) * 12.9898 + (axis + 1) * 78.233) *
        43758.5453123;
    final unit = seed - seed.floorToDouble();
    return unit * 2 - 1;
  }

  static String _truncate(String value, int maxChars) {
    final normalized = value.trim();
    if (normalized.isEmpty || maxChars <= 0) return '';
    final chars = normalized.characters;
    if (chars.length <= maxChars) return normalized;
    return '${chars.take(maxChars)}...';
  }
}

bool _hasFiniteVector(KnowledgeVectorProjectionInput input) {
  return input.vector.any(_isFinite);
}

bool _isFinite(double value) {
  return value.isFinite;
}

double _normalizedCoordinate(double value, double center, double maxDistance) {
  return ((value - center) / maxDistance).clamp(
    _projectionMinCoordinate,
    _projectionMaxCoordinate,
  );
}

double _fallbackRadius(int index, int total) {
  if (total <= 1) return 0;
  return _fallbackRadiusBase +
      _fallbackRadiusSpread * unitRatio(index, total - 1);
}

double _fallbackZ(int index) {
  return ((index % 7) - 3) / 5.0;
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_vector_distribution.dart';

void main() {
  group('KnowledgeVectorProjector', () {
    test('spreads identical vectors with bounded fallback radii', () {
      final distribution = KnowledgeVectorProjector.project(
        inputs: const <KnowledgeVectorProjectionInput>[
          KnowledgeVectorProjectionInput(
            id: 'a',
            kind: KnowledgeVectorPointKind.corpus,
            title: 'A',
            preview: '',
            vector: <double>[1, 2, 3],
          ),
          KnowledgeVectorProjectionInput(
            id: 'b',
            kind: KnowledgeVectorPointKind.corpus,
            title: 'B',
            preview: '',
            vector: <double>[1, 2, 3],
          ),
          KnowledgeVectorProjectionInput(
            id: 'c',
            kind: KnowledgeVectorPointKind.query,
            title: 'C',
            preview: '',
            vector: <double>[1, 2, 3],
          ),
        ],
        originalDimensions: 3,
      );

      expect(distribution.points, hasLength(3));
      for (final point in distribution.points) {
        expect(point.x.isFinite, isTrue);
        expect(point.y.isFinite, isTrue);
        expect(point.z.isFinite, isTrue);
        expect(point.x.abs(), lessThanOrEqualTo(1));
        expect(point.y.abs(), lessThanOrEqualTo(1));
        expect(point.z.abs(), lessThanOrEqualTo(1));
      }

      final firstRadius = _xyRadius(distribution.points.first);
      final lastRadius = _xyRadius(distribution.points.last);
      expect(firstRadius, closeTo(0.34, 0.000001));
      expect(lastRadius, closeTo(0.90, 0.000001));
    });
  });
}

double _xyRadius(KnowledgeVectorDistributionPoint point) {
  return math.sqrt(point.x * point.x + point.y * point.y);
}

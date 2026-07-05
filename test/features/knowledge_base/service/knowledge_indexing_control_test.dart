import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_indexing_control.dart';

void main() {
  group('KnowledgeIndexingProgress', () {
    test('omits fraction when total chunks are unavailable', () {
      const progress = KnowledgeIndexingProgress(processedChunks: 5);

      expect(progress.hasChunkProgress, isFalse);
      expect(progress.clampedProcessedChunks, 0);
      expect(progress.fraction, isNull);
    });

    test('clamps processed chunks into the available range', () {
      const overflow = KnowledgeIndexingProgress(
        processedChunks: 12,
        totalChunks: 10,
      );
      const negative = KnowledgeIndexingProgress(
        processedChunks: -3,
        totalChunks: 10,
      );

      expect(overflow.clampedProcessedChunks, 10);
      expect(overflow.fraction, 1);
      expect(negative.clampedProcessedChunks, 0);
      expect(negative.fraction, 0);
    });

    test('computes bounded fractional progress', () {
      const progress = KnowledgeIndexingProgress(
        processedChunks: 4,
        totalChunks: 10,
      );

      expect(progress.clampedProcessedChunks, 4);
      expect(progress.fraction, closeTo(0.4, 0.000001));
    });
  });
}

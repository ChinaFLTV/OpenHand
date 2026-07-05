import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_source.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_chunker.dart';

void main() {
  group('KnowledgeChunker', () {
    test('fixed windows stay bounded for malformed tuning values', () {
      const settings = KnowledgeBaseSettings(
        chunkStrategy: KnowledgeChunkStrategy.fixedTokenWindow,
        targetTokens: -5,
        hardMaxTokens: -1,
        overlapTokens: 999999,
      );

      final chunks = const KnowledgeChunker().chunk(
        source: _source,
        text: 'abcdefghij',
        settings: settings,
      );

      expect(chunks, isNotEmpty);
      expect(chunks.length, lessThanOrEqualTo(10));
      for (final chunk in chunks) {
        expect(chunk.content, isNotEmpty);
        expect(chunk.startOffset, inInclusiveRange(0, 10));
        expect(chunk.endOffset, inInclusiveRange(chunk.startOffset!, 10));
      }
    });
  });
}

final DateTime _now = DateTime.utc(2026);

final KnowledgeSource _source = KnowledgeSource(
  id: 'source',
  title: 'Source',
  kind: 'note',
  originalPath: '/tmp/source.md',
  storedPath: '',
  mimeType: 'text/markdown',
  sizeBytes: 10,
  contentHash: 'hash',
  status: 'indexed',
  errorMessage: '',
  importedAt: _now,
  createdAt: _now,
  updatedAt: _now,
);

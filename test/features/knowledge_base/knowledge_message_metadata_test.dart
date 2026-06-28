import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_chunk.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_message_metadata.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_retrieval_result.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_source.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_vector_distribution.dart';

void main() {
  test('object normalizes loose map keys', () {
    final value = KnowledgeMessageMetadata.object(<Object?, Object?>{
      1: 'numeric-key',
      'prompt_append': <Object?, Object?>{'chunk_count': '1'},
    });

    expect(value, isNotNull);
    expect(value!['1'], 'numeric-key');
    expect((value['prompt_append'] as Map)['chunk_count'], '1');
  });

  test('object keeps invalid JSON as null while accepting JSON objects', () {
    expect(KnowledgeMessageMetadata.object('not-json'), isNull);
    expect(KnowledgeMessageMetadata.object('[1, 2]'), isNull);
    expect(
      KnowledgeMessageMetadata.object('{"enabled": true, "status": "success"}'),
      <String, Object?>{'enabled': true, 'status': 'success'},
    );
  });

  test('success stores rerank trace and projected vectors only', () {
    final now = DateTime.utc(2026, 1, 2);
    final source = KnowledgeSource(
      id: 'source-1',
      title: 'Handbook',
      kind: 'markdown',
      originalPath: '/tmp/handbook.md',
      storedPath: '/tmp/handbook.md',
      mimeType: 'text/markdown',
      sizeBytes: 12,
      contentHash: 'hash',
      status: 'indexed',
      errorMessage: '',
      importedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    final chunk = KnowledgeChunk(
      id: 'chunk-1',
      sourceId: source.id,
      chunkIndex: 0,
      title: 'Setup',
      headingPath: 'Setup',
      content: 'Install and configure the local knowledge base.',
      contentHash: 'chunk-hash',
      charCount: 48,
      tokenEstimate: 8,
      createdAt: now,
      updatedAt: now,
    );
    final metadata = KnowledgeMessageMetadata.success(
      settings: const KnowledgeBaseSettings(dimensions: 3),
      result: KnowledgeRetrievalResult(
        query: 'setup',
        hits: <KnowledgeRetrievalHit>[
          KnowledgeRetrievalHit(
            chunk: chunk,
            source: source,
            score: 0.91,
            vector: const <double>[0.1, 0.2, 0.3],
            rerankScore: 0.98,
          ),
        ],
        durationMs: 12,
        promptAppend: 'context',
        promptTokenEstimate: 8,
        queryVector: const <double>[0.2, 0.1, 0.4],
        rerankTrace: const KnowledgeRerankTrace(
          mode: KnowledgeRerankMode.model,
          strategy: 'model',
          candidateCount: 1,
          rerankInputCount: 1,
          rerankOutputCount: 1,
          keptCount: 1,
        ),
      ),
      embeddingDurationMs: 7,
      promptAppendContent: 'context',
    );

    expect((metadata['rerank'] as Map)['strategy'], 'model');
    final distribution = KnowledgeVectorDistribution.fromJson(
      metadata['vector_distribution'],
    );
    expect(distribution, isNotNull);
    expect(distribution!.points.map((point) => point.kind), contains('query'));
    expect(distribution.points.map((point) => point.kind), contains('match'));
    final rawPoints =
        (metadata['vector_distribution'] as Map)['points'] as List;
    expect((rawPoints.first as Map).containsKey('vector'), isFalse);
  });
}

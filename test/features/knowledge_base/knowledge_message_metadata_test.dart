import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_chunk.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_message_metadata.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_retrieval_result.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_source.dart';

void main() {
  group('KnowledgeBaseSettings', () {
    test('round-trips persisted JSON and derives a stable collection name', () {
      const settings = KnowledgeBaseSettings(
        providerConfigId: 'Provider A',
        modelId: 'text-embedding/3-large',
        dimensions: 1024,
        topN: 40,
        topK: 5,
        allowQueryCloudEmbedding: true,
        htmlParsingMode: 'plain_text',
        structuredDataParsingMode: 'raw_fenced',
        spreadsheetParsingMode: 'row_blocks',
        presentationParsingMode: 'outline',
      );

      final decoded = KnowledgeBaseSettings.decode(settings.encode());

      expect(decoded.hasEmbeddingModel, isTrue);
      expect(decoded.providerConfigId, 'Provider A');
      expect(decoded.modelId, 'text-embedding/3-large');
      expect(decoded.dimensions, 1024);
      expect(decoded.topN, 40);
      expect(decoded.topK, 5);
      expect(decoded.allowQueryCloudEmbedding, isTrue);
      expect(decoded.documentParsingEngine, 'auto');
      expect(decoded.officeParsingEngine, 'open_xml');
      expect(decoded.pdfParsingEngine, 'basic_text_stream');
      expect(decoded.htmlParsingMode, 'plain_text');
      expect(decoded.structuredDataParsingMode, 'raw_fenced');
      expect(decoded.spreadsheetParsingMode, 'row_blocks');
      expect(decoded.presentationParsingMode, 'outline');
      expect(
        decoded.effectiveCollectionName,
        'openhand_knowledge_provider_a_text_embedding_3_large_1024',
      );
    });
  });

  group('KnowledgeMessageMetadata', () {
    test('detects successful references and keeps prompt append hidden', () {
      final now = DateTime.utc(2026, 6, 27, 10);
      const settings = KnowledgeBaseSettings(
        providerConfigId: 'embedding-provider',
        modelId: 'embedding-model',
      );
      final source = KnowledgeSource(
        id: 'source-1',
        title: 'Runbook',
        kind: 'markdown',
        originalPath: '/docs/runbook.md',
        storedPath: '/stored/runbook.md',
        mimeType: 'text/markdown',
        sizeBytes: 128,
        contentHash: 'source-hash',
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
        title: 'Deploy',
        headingPath: 'Runbook > Deploy',
        content: 'Use the production deployment checklist.',
        contentHash: 'chunk-hash',
        charCount: 41,
        tokenEstimate: 9,
        documentTime: now,
        createdAt: now,
        updatedAt: now,
        tags: const <String>['ops'],
      );
      final result = KnowledgeRetrievalResult(
        query: 'deployment checklist',
        hits: <KnowledgeRetrievalHit>[
          KnowledgeRetrievalHit(
            chunk: chunk,
            source: source,
            score: 0.91,
            rerankScore: 0.94,
            finalScore: 0.92,
            timeField: 'document_time',
          ),
        ],
        durationMs: 18,
        promptAppend:
            '<OpenHandKnowledgeBaseContext>...</OpenHandKnowledgeBaseContext>',
        promptTokenEstimate: 128,
      );

      final metadata = KnowledgeMessageMetadata.success(
        settings: settings,
        result: result,
        embeddingDurationMs: 12,
        promptAppendContent: result.promptAppend,
      );

      expect(
        KnowledgeMessageMetadata.hasReferences(<String, Object?>{
          knowledgeBaseMessageMetadataKey: metadata,
        }),
        isTrue,
      );
      expect(metadata['status'], 'success');
      expect(
        metadata[knowledgeBasePromptAppendMetadataKey],
        result.promptAppend,
      );
      expect(
        KnowledgeMessageMetadata.promptAppendContent(<String, Object?>{
          knowledgeBaseMessageMetadataKey: metadata,
        }),
        result.promptAppend,
      );
      expect((metadata['results'] as List), hasLength(1));

      final parsed = KnowledgeMessageMetadata.object(jsonEncode(metadata));
      expect(parsed, isNotNull);
      expect(parsed?['query'], 'deployment checklist');
    });

    test('does not show references for failed retrieval metadata', () {
      final failed = KnowledgeMessageMetadata.failed(
        query: 'anything',
        error: 'qdrant unavailable',
        settings: const KnowledgeBaseSettings(),
      );

      expect(
        KnowledgeMessageMetadata.hasReferences(<String, Object?>{
          knowledgeBaseMessageMetadataKey: failed,
        }),
        isFalse,
      );
      expect(failed['status'], 'failed');
      expect(failed['results'], isEmpty);
    });
  });
}

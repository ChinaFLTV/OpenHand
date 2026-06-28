import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';

void main() {
  test('normalizes chunk strategy and rerank mode from persisted json', () {
    final settings = KnowledgeBaseSettings.fromJson(const <String, Object?>{
      'chunk_strategy': 'unknown',
      'rerank_mode': 'invalid',
      'skip_model_rerank_when_embedding_supports_rerank': true,
    });

    expect(
      settings.chunkStrategy,
      KnowledgeChunkStrategy.markdownHeadingRecursive,
    );
    expect(settings.rerankMode, KnowledgeRerankMode.localHybrid);
    expect(settings.skipModelRerankWhenEmbeddingSupportsRerank, isTrue);
  });

  test('migrates legacy cloud rerank settings to model rerank mode', () {
    final settings = KnowledgeBaseSettings.fromJson(const <String, Object?>{
      'provider_config_id': 'provider-a',
      'cloud_rerank_enabled': true,
      'rerank_model_id': 'jina-reranker-v2-base-multilingual',
    });

    expect(settings.rerankMode, KnowledgeRerankMode.model);
    expect(settings.modelRerankEnabled, isTrue);
    expect(settings.rerankProviderConfigId, 'provider-a');
    expect(settings.rerankModelId, 'jina-reranker-v2-base-multilingual');
  });

  test('serializes model rerank mode with provider and model ids', () {
    final json = const KnowledgeBaseSettings(
      rerankMode: KnowledgeRerankMode.model,
      rerankProviderConfigId: 'provider-b',
      rerankModelId: 'bge-reranker-v2-m3',
      skipModelRerankWhenEmbeddingSupportsRerank: true,
    ).toJson();

    expect(json['cloud_rerank_enabled'], isTrue);
    expect(json['rerank_mode'], KnowledgeRerankMode.model);
    expect(json['rerank_provider_config_id'], 'provider-b');
    expect(json['rerank_model_id'], 'bge-reranker-v2-m3');
    expect(json['skip_model_rerank_when_embedding_supports_rerank'], isTrue);
  });

  test('persists reader parser rules by normalized source type', () {
    final settings = KnowledgeBaseSettings.fromJson(<String, Object?>{
      'reader_parser_rules': <String, Object?>{
        'HTM': <String, Object?>{
          'mode': 'model',
          'provider_config_id': 'reader-provider',
          'model_id': 'reader-model',
          'target_type': 'JSON',
        },
      },
    });

    final rule = settings.readerRuleForSourceType('html');
    expect(rule.mode, KnowledgeReaderParserMode.model);
    expect(rule.providerConfigId, 'reader-provider');
    expect(rule.modelId, 'reader-model');
    expect(rule.targetType, 'json');

    final json = settings.toJson();
    final rules = json['reader_parser_rules'] as Map<String, Object?>;
    expect(rules.keys, contains('html'));
  });

  test('falls back for invalid or non-finite numeric settings', () {
    final settings = KnowledgeBaseSettings.fromJson(<String, Object?>{
      'dimensions': double.infinity,
      'retry_count': -1,
      'min_similarity': 'NaN',
      'vector_weight': 'Infinity',
      'qdrant_log_retain_lines': 'bad',
      'overlap_tokens': '0',
      'top_k': '12',
    });

    expect(settings.dimensions, 1536);
    expect(settings.retryCount, 2);
    expect(settings.minSimilarity, 0.25);
    expect(settings.vectorWeight, 0.65);
    expect(settings.qdrantLogRetainLines, 300);
    expect(settings.overlapTokens, 0);
    expect(settings.topK, 12);
  });

  test('parses persisted strings and rejects ambiguous boolean numbers', () {
    final settings = KnowledgeBaseSettings.fromJson(<String, Object?>{
      'provider_config_id': '  provider-a  ',
      'copy_imported_files': double.nan,
      'allow_query_cloud_embedding': 2,
      'enable_dangerous_admin_operations': 'enabled',
    });

    expect(settings.providerConfigId, 'provider-a');
    expect(settings.copyImportedFiles, isTrue);
    expect(settings.allowQueryCloudEmbedding, isFalse);
    expect(settings.enableDangerousAdminOperations, isTrue);
  });

  test('decode falls back for malformed persisted settings', () {
    expect(KnowledgeBaseSettings.decode('{').dimensions, 1536);
    expect(KnowledgeBaseSettings.decode('[]').dimensions, 1536);
    expect(
      KnowledgeBaseSettings.decode('{"dimensions":"256"}').dimensions,
      256,
    );
  });
}

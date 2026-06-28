import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';

void main() {
  test('normalizes chunk strategy and rerank mode from persisted json', () {
    final settings = KnowledgeBaseSettings.fromJson(const <String, Object?>{
      'chunk_strategy': 'unknown',
      'rerank_mode': 'invalid',
    });

    expect(
      settings.chunkStrategy,
      KnowledgeChunkStrategy.markdownHeadingRecursive,
    );
    expect(settings.rerankMode, KnowledgeRerankMode.localHybrid);
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
    ).toJson();

    expect(json['cloud_rerank_enabled'], isTrue);
    expect(json['rerank_mode'], KnowledgeRerankMode.model);
    expect(json['rerank_provider_config_id'], 'provider-b');
    expect(json['rerank_model_id'], 'bge-reranker-v2-m3');
  });
}

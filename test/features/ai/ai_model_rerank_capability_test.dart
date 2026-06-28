import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('catalog marks common reranker model ids as rerank capable', () {
    for (final modelId in const <String>[
      'jina-reranker-v2-base-multilingual',
      'bge-reranker-v2-m3',
      'qwen3-reranker-4b',
      'gte-rerank-v2',
      'cohere-rerank-v3.5',
    ]) {
      final profile = AiModelCatalog.lookup(modelId, AiProtocolType.openai);

      expect(profile, isNotNull, reason: modelId);
      expect(profile!.supportsRerank, isTrue, reason: modelId);
      expect(profile.supportsEmbeddings, isFalse, reason: modelId);
    }
  });

  test('model profile parses rerank capability from storage', () {
    final profile = AiModelProfile.fromJson(const <String, Object?>{
      'capabilities': <String>['rerank'],
    });

    expect(profile.supportsRerank, isTrue);
  });

  test('model profile parses reader conversion capability and type ranges', () {
    final profile = AiModelProfile.fromJson(const <String, Object?>{
      'capabilities': <String>['reader_conversion'],
      'reader_source_types': <String>['HTML', 'md', 'pdf'],
      'reader_target_types': <String>['Markdown', 'json'],
    });

    expect(profile.supportsReaderConversion, isTrue);
    expect(profile.readerSourceTypes, <String>['html', 'markdown', 'pdf']);
    expect(profile.readerTargetTypes, <String>['markdown', 'json']);
    expect(
      profile.supportsReaderConversionFor(
        sourceType: 'htm',
        targetType: 'JSON',
      ),
      isTrue,
    );
    expect(profile.toJson()['reader_source_types'], isNotNull);
  });

  test('model profile numeric metadata ignores invalid non-finite values', () {
    final profile = AiModelProfile.fromJson(<String, Object?>{
      'max_context_length': '0',
      'max_output_length': '8192',
      'input_usd_per_1m': 'NaN',
      'output_usd_per_1m': '-1',
      'cache_read_usd_per_1m': '0.25',
      'created': double.infinity,
      'embedding_dimensions': '1024',
    });

    expect(profile.maxContextLength, isNull);
    expect(profile.maxOutputLength, 8192);
    expect(profile.inputUsdPer1M, isNull);
    expect(profile.outputUsdPer1M, isNull);
    expect(profile.cacheReadUsdPer1M, 0.25);
    expect(profile.created, isNull);
    expect(profile.embeddingDimensions, 1024);
  });

  test('model config numeric parsing ignores invalid non-finite values', () {
    final model = AiModelConfig.fromJson(<String, Object?>{
      'id': 'model',
      'name': 'Model',
      'base_url': 'https://example.test/',
      'model_id': 'example-model',
      'max_context_tokens': '4096',
      'max_tokens': double.infinity,
      'temperature': 'NaN',
    });

    expect(model.maxContextTokens, 4096);
    expect(model.maxTokens, isNull);
    expect(model.temperature, isNull);
  });
}

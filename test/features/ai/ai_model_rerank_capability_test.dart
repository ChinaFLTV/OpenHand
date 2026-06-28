import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/shared/util/reader_file_type.dart';

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
      'reader_source_types': <String>['HTML', 'md', 'pdf', 'ndjson', 'tex'],
      'reader_target_types': <String>['Markdown', 'json', 'YML', 'tsv'],
    });

    expect(profile.supportsReaderConversion, isTrue);
    expect(profile.readerSourceTypes, <String>[
      'html',
      'markdown',
      'pdf',
      'jsonl',
      'latex',
    ]);
    expect(profile.readerTargetTypes, <String>[
      'markdown',
      'json',
      'yaml',
      'tsv',
    ]);
    expect(
      profile.supportsReaderConversionFor(
        sourceType: 'htm',
        targetType: 'JSON',
      ),
      isTrue,
    );
    expect(profile.toJson()['reader_source_types'], isNotNull);
  });

  test('reader file type covers structured text source and target formats', () {
    expect(ReaderFileType.normalize('.ndjson'), ReaderFileType.jsonl);
    expect(
      ReaderFileType.normalize('tab separated values'),
      ReaderFileType.tsv,
    );
    expect(ReaderFileType.normalize('tex'), ReaderFileType.latex);
    expect(ReaderFileType.isTextLikeSource('rtf'), isTrue);
    expect(
      ReaderFileType.targetTypes,
      containsAll(<String>[
        ReaderFileType.html,
        ReaderFileType.yaml,
        ReaderFileType.csv,
        ReaderFileType.tsv,
        ReaderFileType.xml,
      ]),
    );
  });

  test('catalog marks common reader conversion model ids', () {
    for (final modelId in const <String>[
      'jina-reader',
      'readerlm-v2',
      'docling-parse',
      'marker-html2markdown',
    ]) {
      final profile = AiModelCatalog.lookup(modelId, AiProtocolType.openai);

      expect(profile, isNotNull, reason: modelId);
      expect(profile!.supportsReaderConversion, isTrue, reason: modelId);
      expect(profile.readerSourceTypes, contains(ReaderFileType.pdf));
      expect(profile.readerTargetTypes, contains(ReaderFileType.markdown));
      expect(profile.readerTargetTypes, contains(ReaderFileType.html));
    }
  });

  test(
    'catalog fills gateway provider model profiles without protocol enum',
    () {
      final sparkEmbedding = AiModelCatalog.lookup(
        'spark-embedding',
        AiProtocolType.openai,
      );
      final sparkRerank = AiModelCatalog.lookup(
        'spark-rerank',
        AiProtocolType.openai,
      );
      final klingVideo = AiModelCatalog.lookup(
        'kling-v2-master',
        AiProtocolType.openai,
      );
      final sakana = AiModelCatalog.lookup(
        'sakana-chat',
        AiProtocolType.openai,
      );

      expect(sparkEmbedding?.supportsEmbeddings, isTrue);
      expect(sparkEmbedding?.embeddingEndpointPath, 'embeddings');
      expect(sparkRerank?.supportsRerank, isTrue);
      expect(sparkRerank?.rerankEndpointPath, 'rerank');
      expect(sparkRerank?.rerankSupportsReturnDocuments, isTrue);
      expect(
        sparkRerank?.rerankSupportedParameters,
        contains('return_documents'),
      );
      expect(
        klingVideo?.capabilities,
        contains(AiModelCapability.videoGeneration),
      );
      expect(sakana?.displayName, 'Sakana AI');
    },
  );

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

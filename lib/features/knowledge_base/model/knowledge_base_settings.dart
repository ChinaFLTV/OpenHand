import 'dart:convert';

import '../../../shared/net/tcp_port_utils.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/reader_file_type.dart';
import '../../../shared/util/text_clip.dart';

const _skipDualCapabilityRerankJsonKey =
    'skip_model_rerank_when_embedding_supports_rerank';
const int _maxKnowledgeBaseSettingsBytes = kBytesPerMiB;
final RegExp _knowledgeCollectionNameUnsafeCharsPattern = RegExp(
  r'[^a-zA-Z0-9_]+',
);

class KnowledgeBaseSettingRanges {
  const KnowledgeBaseSettingRanges._();

  static const int defaultDimensions = 1536;
  static const int defaultMaxInputTokens = 8192;
  static const int defaultBatchSize = 16;
  static const int defaultRequestTimeoutSeconds = 60;
  static const int defaultRetryCount = 2;
  static const int defaultRetryBackoffMs = 800;
  static const int defaultConcurrentRequests = 2;
  static const String defaultQdrantHost = '127.0.0.1';
  static const int defaultQdrantRestPort = 6333;
  static const int defaultQdrantGrpcPort = 6334;
  static const int defaultHnswM = 16;
  static const int defaultHnswEfConstruct = 100;
  static const int defaultSearchEf = 64;
  static const int defaultMaxFileSizeMb = 50;
  static const int defaultTargetTokens = 700;
  static const int defaultHardMaxTokens = 1200;
  static const int defaultOverlapTokens = 120;
  static const int defaultTopN = 80;
  static const int defaultTopK = 6;
  static const double defaultMinSimilarity = 0.25;
  static const int defaultSourceCap = 3;
  static const double defaultVectorWeight = 0.65;
  static const double defaultTitleWeight = 0.10;
  static const double defaultTagWeight = 0.10;
  static const double defaultTimeWeight = 0.08;
  static const double defaultExactPhraseWeight = 0.05;
  static const double defaultSourceQualityWeight = 0.02;
  static const double defaultMmrLambda = 0.72;
  static const int defaultMaxChunksPerSource = 3;
  static const int defaultRerankTopN = 24;
  static const int defaultRerankTimeoutSeconds = 30;
  static const int defaultMaxPromptChunks = 6;
  static const int defaultMaxPromptTokens = 6000;
  static const int defaultQdrantMetricsRefreshSeconds = 10;
  static const int defaultQdrantLogRetainLines = 300;
  static const int maxQdrantLogRetainLines = 10000;

  static const IntValueRange dimensions = IntValueRange(
    fallback: defaultDimensions,
    min: 1,
    max: 65536,
  );
  static const IntValueRange maxInputTokens = IntValueRange(
    fallback: defaultMaxInputTokens,
    min: 1,
    max: 2000000,
  );
  static const IntValueRange batchSize = IntValueRange(
    fallback: defaultBatchSize,
    min: 1,
    max: 1024,
  );
  static const IntValueRange requestTimeoutSeconds = IntValueRange(
    fallback: defaultRequestTimeoutSeconds,
    min: 1,
    max: 86400,
  );
  static const IntValueRange retryCount = IntValueRange(
    fallback: defaultRetryCount,
    min: 0,
    max: 20,
  );
  static const IntValueRange retryBackoffMs = IntValueRange(
    fallback: defaultRetryBackoffMs,
    min: 1,
    max: 300000,
  );
  static const IntValueRange concurrentRequests = IntValueRange(
    fallback: defaultConcurrentRequests,
    min: 1,
    max: 64,
  );
  static const IntValueRange hnswM = IntValueRange(
    fallback: defaultHnswM,
    min: 1,
    max: 4096,
  );
  static const IntValueRange hnswEfConstruct = IntValueRange(
    fallback: defaultHnswEfConstruct,
    min: 1,
    max: 1000000,
  );
  static const IntValueRange searchEf = IntValueRange(
    fallback: defaultSearchEf,
    min: 1,
    max: 1000000,
  );
  static const IntValueRange maxFileSizeMb = IntValueRange(
    fallback: defaultMaxFileSizeMb,
    min: 1,
    max: 256,
  );
  static const IntValueRange targetTokens = IntValueRange(
    fallback: defaultTargetTokens,
    min: 1,
    max: 1000000,
  );
  static const IntValueRange hardMaxTokens = IntValueRange(
    fallback: defaultHardMaxTokens,
    min: 1,
    max: 1000000,
  );
  static const IntValueRange overlapTokens = IntValueRange(
    fallback: defaultOverlapTokens,
    min: 0,
    max: 1000000,
  );
  static const IntValueRange topN = IntValueRange(
    fallback: defaultTopN,
    min: 1,
    max: 10000,
  );
  static const IntValueRange topK = IntValueRange(
    fallback: defaultTopK,
    min: 1,
    max: 10000,
  );
  static const DoubleValueRange minSimilarity = DoubleValueRange(
    fallback: defaultMinSimilarity,
    min: 0,
    max: 1,
  );
  static const IntValueRange sourceCap = IntValueRange(
    fallback: defaultSourceCap,
    min: 1,
    max: 10000,
  );
  static const DoubleValueRange vectorWeight = DoubleValueRange(
    fallback: defaultVectorWeight,
    min: 0,
    max: 100,
  );
  static const DoubleValueRange titleWeight = DoubleValueRange(
    fallback: defaultTitleWeight,
    min: 0,
    max: 100,
  );
  static const DoubleValueRange tagWeight = DoubleValueRange(
    fallback: defaultTagWeight,
    min: 0,
    max: 100,
  );
  static const DoubleValueRange timeWeight = DoubleValueRange(
    fallback: defaultTimeWeight,
    min: 0,
    max: 100,
  );
  static const DoubleValueRange exactPhraseWeight = DoubleValueRange(
    fallback: defaultExactPhraseWeight,
    min: 0,
    max: 100,
  );
  static const DoubleValueRange sourceQualityWeight = DoubleValueRange(
    fallback: defaultSourceQualityWeight,
    min: 0,
    max: 100,
  );
  static const DoubleValueRange mmrLambda = DoubleValueRange(
    fallback: defaultMmrLambda,
    min: 0,
    max: 1,
  );
  static const IntValueRange maxChunksPerSource = IntValueRange(
    fallback: defaultMaxChunksPerSource,
    min: 1,
    max: 10000,
  );
  static const IntValueRange rerankTopN = IntValueRange(
    fallback: defaultRerankTopN,
    min: 1,
    max: 10000,
  );
  static const IntValueRange rerankTimeoutSeconds = IntValueRange(
    fallback: defaultRerankTimeoutSeconds,
    min: 1,
    max: 86400,
  );
  static const IntValueRange maxPromptChunks = IntValueRange(
    fallback: defaultMaxPromptChunks,
    min: 1,
    max: 10000,
  );
  static const IntValueRange maxPromptTokens = IntValueRange(
    fallback: defaultMaxPromptTokens,
    min: 1,
    max: 10000000,
  );
  static const IntValueRange qdrantMetricsRefreshSeconds = IntValueRange(
    fallback: defaultQdrantMetricsRefreshSeconds,
    min: 1,
    max: 86400,
  );
  static const IntValueRange qdrantLogRetainLines = IntValueRange(
    fallback: defaultQdrantLogRetainLines,
    min: 1,
    max: maxQdrantLogRetainLines,
  );
}

String _normalizeKnownValue(
  String value, {
  required List<String> allowedValues,
  required String fallback,
}) {
  final normalized = value.trim();
  return allowedValues.contains(normalized) ? normalized : fallback;
}

class KnowledgeChunkStrategy {
  const KnowledgeChunkStrategy._();

  static const markdownHeadingRecursive = 'markdown_heading_recursive';
  static const paragraphWindow = 'paragraph_window';
  static const fixedTokenWindow = 'fixed_token_window';
  static const semanticLight = 'semantic_light';

  static const values = <String>[
    markdownHeadingRecursive,
    paragraphWindow,
    fixedTokenWindow,
    semanticLight,
  ];

  static String normalize(String value) {
    return _normalizeKnownValue(
      value,
      allowedValues: values,
      fallback: markdownHeadingRecursive,
    );
  }
}

class KnowledgeRerankMode {
  const KnowledgeRerankMode._();

  static const off = 'off';
  static const localHybrid = 'local_hybrid';
  static const mmr = 'mmr';
  static const model = 'model';

  static const values = <String>[off, localHybrid, mmr, model];

  static String normalize(String value) {
    return _normalizeKnownValue(
      value,
      allowedValues: values,
      fallback: localHybrid,
    );
  }
}

class KnowledgeDistanceMetric {
  const KnowledgeDistanceMetric._();

  static const cosine = 'cosine';
  static const dot = 'dot';
  static const euclidean = 'euclidean';

  static const values = <String>[cosine, dot, euclidean];

  static String normalize(String value) {
    return _normalizeKnownValue(value, allowedValues: values, fallback: cosine);
  }
}

class KnowledgeTagFilterMode {
  const KnowledgeTagFilterMode._();

  static const any = 'any';
  static const all = 'all';

  static const values = <String>[any, all];

  static String normalize(String value) {
    return _normalizeKnownValue(value, allowedValues: values, fallback: any);
  }
}

class KnowledgeDateFilterMode {
  const KnowledgeDateFilterMode._();

  static const hardWhenExplicit = 'hard_when_explicit';
  static const softBoost = 'soft_boost';
  static const off = 'off';

  static const values = <String>[hardWhenExplicit, softBoost, off];

  static String normalize(String value) {
    return _normalizeKnownValue(
      value,
      allowedValues: values,
      fallback: hardWhenExplicit,
    );
  }
}

class KnowledgeFailureStrategy {
  const KnowledgeFailureStrategy._();

  static const failOpen = 'fail_open';
  static const failClosed = 'fail_closed';

  static const values = <String>[failOpen, failClosed];

  static String normalize(String value) {
    return _normalizeKnownValue(
      value,
      allowedValues: values,
      fallback: failOpen,
    );
  }
}

class KnowledgeReaderParserMode {
  const KnowledgeReaderParserMode._();

  static const local = 'local';
  static const model = 'model';

  static const values = <String>[local, model];

  static String normalize(String value) {
    return _normalizeKnownValue(value, allowedValues: values, fallback: local);
  }
}

class KnowledgeReaderParserRule {
  const KnowledgeReaderParserRule({
    this.mode = KnowledgeReaderParserMode.local,
    this.providerConfigId = '',
    this.modelId = '',
    this.targetType = ReaderFileType.markdown,
  });

  factory KnowledgeReaderParserRule.fromJson(Map<String, Object?> json) {
    return KnowledgeReaderParserRule(
      mode: KnowledgeReaderParserMode.normalize(
        KnowledgeBaseSettings._string(json['mode']),
      ),
      providerConfigId: KnowledgeBaseSettings._string(
        json['provider_config_id'],
      ),
      modelId: KnowledgeBaseSettings._string(json['model_id']),
      targetType: _normalizeTargetType(json['target_type']),
    );
  }

  final String mode;
  final String providerConfigId;
  final String modelId;
  final String targetType;

  bool get usesModel => mode == KnowledgeReaderParserMode.model;

  bool get hasModel =>
      nullIfBlank(providerConfigId) != null && nullIfBlank(modelId) != null;

  KnowledgeReaderParserRule copyWith({
    String? mode,
    String? providerConfigId,
    String? modelId,
    String? targetType,
  }) {
    return KnowledgeReaderParserRule(
      mode: mode == null
          ? this.mode
          : KnowledgeReaderParserMode.normalize(mode),
      providerConfigId: providerConfigId ?? this.providerConfigId,
      modelId: modelId ?? this.modelId,
      targetType: targetType == null
          ? this.targetType
          : _normalizeTargetType(targetType),
    );
  }

  Map<String, Object?> toJson() {
    final normalizedProviderConfigId = nullIfBlank(providerConfigId);
    final normalizedModelId = nullIfBlank(modelId);
    return <String, Object?>{
      'mode': KnowledgeReaderParserMode.normalize(mode),
      if (normalizedProviderConfigId != null)
        'provider_config_id': normalizedProviderConfigId,
      if (normalizedModelId != null) 'model_id': normalizedModelId,
      'target_type': _normalizeTargetType(targetType),
    };
  }

  static String _normalizeTargetType(Object? value) {
    final normalized = ReaderFileType.normalize('${value ?? ''}');
    return ReaderFileType.targetTypes.contains(normalized)
        ? normalized
        : ReaderFileType.markdown;
  }
}

class KnowledgeBaseSettings {
  const KnowledgeBaseSettings({
    this.providerConfigId = '',
    this.modelId = '',
    this.displayName = '',
    this.dimensions = KnowledgeBaseSettingRanges.defaultDimensions,
    this.maxInputTokens = KnowledgeBaseSettingRanges.defaultMaxInputTokens,
    this.batchSize = KnowledgeBaseSettingRanges.defaultBatchSize,
    this.requestTimeoutSeconds =
        KnowledgeBaseSettingRanges.defaultRequestTimeoutSeconds,
    this.retryCount = KnowledgeBaseSettingRanges.defaultRetryCount,
    this.retryBackoffMs = KnowledgeBaseSettingRanges.defaultRetryBackoffMs,
    this.concurrentRequests =
        KnowledgeBaseSettingRanges.defaultConcurrentRequests,
    this.allowDocumentCloudEmbedding = false,
    this.allowQueryCloudEmbedding = false,
    this.vectorStoreType = 'qdrant',
    this.qdrantHost = KnowledgeBaseSettingRanges.defaultQdrantHost,
    this.qdrantRestPort = KnowledgeBaseSettingRanges.defaultQdrantRestPort,
    this.qdrantGrpcPort = KnowledgeBaseSettingRanges.defaultQdrantGrpcPort,
    this.collectionName = '',
    this.distanceMetric = KnowledgeDistanceMetric.cosine,
    this.hnswM = KnowledgeBaseSettingRanges.defaultHnswM,
    this.hnswEfConstruct = KnowledgeBaseSettingRanges.defaultHnswEfConstruct,
    this.searchEf = KnowledgeBaseSettingRanges.defaultSearchEf,
    this.autoStartSidecar = false,
    this.copyImportedFiles = true,
    this.watchOriginalFiles = false,
    this.maxFileSizeMb = KnowledgeBaseSettingRanges.defaultMaxFileSizeMb,
    this.documentParsingEngine = 'auto',
    this.officeParsingEngine = 'open_xml',
    this.pdfParsingEngine = 'basic_text_stream',
    this.htmlParsingMode = 'readable_text',
    this.structuredDataParsingMode = 'readable_markdown',
    this.spreadsheetParsingMode = 'markdown_table',
    this.presentationParsingMode = 'slide_text',
    this.readerParserRules = const <String, KnowledgeReaderParserRule>{},
    this.chunkStrategy = KnowledgeChunkStrategy.markdownHeadingRecursive,
    this.targetTokens = KnowledgeBaseSettingRanges.defaultTargetTokens,
    this.hardMaxTokens = KnowledgeBaseSettingRanges.defaultHardMaxTokens,
    this.overlapTokens = KnowledgeBaseSettingRanges.defaultOverlapTokens,
    this.parentChildEnabled = true,
    this.autoPathTags = true,
    this.autoFrontMatterTags = true,
    this.autoTagSuggestions = false,
    this.defaultDocumentTimeSource = 'front_matter',
    this.parseNaturalLanguageTime = true,
    this.recencyBoostEnabled = true,
    this.topN = KnowledgeBaseSettingRanges.defaultTopN,
    this.topK = KnowledgeBaseSettingRanges.defaultTopK,
    this.minSimilarity = KnowledgeBaseSettingRanges.defaultMinSimilarity,
    this.sourceCap = KnowledgeBaseSettingRanges.defaultSourceCap,
    this.tagFilterMode = KnowledgeTagFilterMode.any,
    this.dateFilterMode = KnowledgeDateFilterMode.hardWhenExplicit,
    this.vectorWeight = KnowledgeBaseSettingRanges.defaultVectorWeight,
    this.titleWeight = KnowledgeBaseSettingRanges.defaultTitleWeight,
    this.tagWeight = KnowledgeBaseSettingRanges.defaultTagWeight,
    this.timeWeight = KnowledgeBaseSettingRanges.defaultTimeWeight,
    this.exactPhraseWeight =
        KnowledgeBaseSettingRanges.defaultExactPhraseWeight,
    this.sourceQualityWeight =
        KnowledgeBaseSettingRanges.defaultSourceQualityWeight,
    this.mmrEnabled = true,
    this.mmrLambda = KnowledgeBaseSettingRanges.defaultMmrLambda,
    this.neighborExpansionEnabled = true,
    this.parentExpansionEnabled = true,
    this.maxChunksPerSource =
        KnowledgeBaseSettingRanges.defaultMaxChunksPerSource,
    this.cloudRerankEnabled = false,
    this.rerankMode = KnowledgeRerankMode.localHybrid,
    this.rerankProviderConfigId = '',
    this.rerankModelId = '',
    this.skipModelRerankWhenEmbeddingSupportsRerank = false,
    this.rerankTopN = KnowledgeBaseSettingRanges.defaultRerankTopN,
    this.rerankTimeoutSeconds =
        KnowledgeBaseSettingRanges.defaultRerankTimeoutSeconds,
    this.maxPromptChunks = KnowledgeBaseSettingRanges.defaultMaxPromptChunks,
    this.maxPromptTokens = KnowledgeBaseSettingRanges.defaultMaxPromptTokens,
    this.includeScore = true,
    this.includeTags = true,
    this.includeDate = true,
    this.includeSourcePath = true,
    this.includeChunkId = true,
    this.failureStrategy = KnowledgeFailureStrategy.failOpen,
    this.embeddingFailureStrategy = KnowledgeFailureStrategy.failOpen,
    this.continueWhenNoHits = true,
    this.showPreviewBeforeSend = false,
    this.cacheQueryEmbedding = true,
    this.qdrantMetricsRefreshSeconds =
        KnowledgeBaseSettingRanges.defaultQdrantMetricsRefreshSeconds,
    this.qdrantLogRetainLines =
        KnowledgeBaseSettingRanges.defaultQdrantLogRetainLines,
    this.enableDangerousAdminOperations = false,
  });

  factory KnowledgeBaseSettings.fromJson(Map<String, Object?> json) {
    final legacyCloudRerankEnabled = _bool(json['cloud_rerank_enabled']);
    final parsedRerankMode = KnowledgeRerankMode.normalize(
      _string(
        json['rerank_mode'],
        legacyCloudRerankEnabled
            ? KnowledgeRerankMode.model
            : KnowledgeRerankMode.localHybrid,
      ),
    );
    final targetTokens = KnowledgeBaseSettingRanges.targetTokens.fromValue(
      json['target_tokens'],
    );
    final hardMaxTokens = _normalizeHardMaxTokens(
      KnowledgeBaseSettingRanges.hardMaxTokens.fromValue(
        json['hard_max_tokens'],
      ),
      targetTokens: targetTokens,
    );
    final overlapTokens = _normalizeOverlapTokens(
      KnowledgeBaseSettingRanges.overlapTokens.fromValue(
        json['overlap_tokens'],
      ),
      targetTokens: targetTokens,
    );
    final topN = KnowledgeBaseSettingRanges.topN.fromValue(json['top_n']);
    final topK = _normalizeTopK(
      KnowledgeBaseSettingRanges.topK.fromValue(json['top_k']),
      topN: topN,
    );
    return KnowledgeBaseSettings(
      providerConfigId: _string(json['provider_config_id']),
      modelId: _string(json['model_id']),
      displayName: _string(json['display_name']),
      dimensions: KnowledgeBaseSettingRanges.dimensions.fromValue(
        json['dimensions'],
      ),
      maxInputTokens: KnowledgeBaseSettingRanges.maxInputTokens.fromValue(
        json['max_input_tokens'],
      ),
      batchSize: KnowledgeBaseSettingRanges.batchSize.fromValue(
        json['batch_size'],
      ),
      requestTimeoutSeconds: KnowledgeBaseSettingRanges.requestTimeoutSeconds
          .fromValue(json['request_timeout_seconds']),
      retryCount: KnowledgeBaseSettingRanges.retryCount.fromValue(
        json['retry_count'],
      ),
      retryBackoffMs: KnowledgeBaseSettingRanges.retryBackoffMs.fromValue(
        json['retry_backoff_ms'],
      ),
      concurrentRequests: KnowledgeBaseSettingRanges.concurrentRequests
          .fromValue(json['concurrent_requests']),
      allowDocumentCloudEmbedding: _bool(
        json['allow_document_cloud_embedding'],
      ),
      allowQueryCloudEmbedding: _bool(json['allow_query_cloud_embedding']),
      vectorStoreType: _string(json['vector_store_type'], 'qdrant'),
      qdrantHost: normalizeQdrantHost(json['qdrant_host']),
      qdrantRestPort: tcpPortFromValueOr(
        json['qdrant_rest_port'],
        fallback: KnowledgeBaseSettingRanges.defaultQdrantRestPort,
      ),
      qdrantGrpcPort: tcpPortFromValueOr(
        json['qdrant_grpc_port'],
        fallback: KnowledgeBaseSettingRanges.defaultQdrantGrpcPort,
      ),
      collectionName: _string(json['collection_name']),
      distanceMetric: KnowledgeDistanceMetric.normalize(
        _string(json['distance_metric'], KnowledgeDistanceMetric.cosine),
      ),
      hnswM: KnowledgeBaseSettingRanges.hnswM.fromValue(json['hnsw_m']),
      hnswEfConstruct: KnowledgeBaseSettingRanges.hnswEfConstruct.fromValue(
        json['hnsw_ef_construct'],
      ),
      searchEf: KnowledgeBaseSettingRanges.searchEf.fromValue(
        json['search_ef'],
      ),
      autoStartSidecar: _bool(json['auto_start_sidecar']),
      copyImportedFiles: _bool(json['copy_imported_files'], true),
      watchOriginalFiles: _bool(json['watch_original_files']),
      maxFileSizeMb: KnowledgeBaseSettingRanges.maxFileSizeMb.fromValue(
        json['max_file_size_mb'],
      ),
      documentParsingEngine: _string(json['document_parsing_engine'], 'auto'),
      officeParsingEngine: _string(json['office_parsing_engine'], 'open_xml'),
      pdfParsingEngine: _string(
        json['pdf_parsing_engine'],
        'basic_text_stream',
      ),
      htmlParsingMode: _string(json['html_parsing_mode'], 'readable_text'),
      structuredDataParsingMode: _string(
        json['structured_data_parsing_mode'],
        'readable_markdown',
      ),
      spreadsheetParsingMode: _string(
        json['spreadsheet_parsing_mode'],
        'markdown_table',
      ),
      presentationParsingMode: _string(
        json['presentation_parsing_mode'],
        'slide_text',
      ),
      readerParserRules: _parseReaderParserRules(json['reader_parser_rules']),
      chunkStrategy: KnowledgeChunkStrategy.normalize(
        _string(
          json['chunk_strategy'],
          KnowledgeChunkStrategy.markdownHeadingRecursive,
        ),
      ),
      targetTokens: targetTokens,
      hardMaxTokens: hardMaxTokens,
      overlapTokens: overlapTokens,
      parentChildEnabled: _bool(json['parent_child_enabled'], true),
      autoPathTags: _bool(json['auto_path_tags'], true),
      autoFrontMatterTags: _bool(json['auto_front_matter_tags'], true),
      autoTagSuggestions: _bool(json['auto_tag_suggestions']),
      defaultDocumentTimeSource: _string(
        json['default_document_time_source'],
        'front_matter',
      ),
      parseNaturalLanguageTime: _bool(
        json['parse_natural_language_time'],
        true,
      ),
      recencyBoostEnabled: _bool(json['recency_boost_enabled'], true),
      topN: topN,
      topK: topK,
      minSimilarity: KnowledgeBaseSettingRanges.minSimilarity.fromValue(
        json['min_similarity'],
      ),
      sourceCap: KnowledgeBaseSettingRanges.sourceCap.fromValue(
        json['source_cap'],
      ),
      tagFilterMode: KnowledgeTagFilterMode.normalize(
        _string(json['tag_filter_mode'], KnowledgeTagFilterMode.any),
      ),
      dateFilterMode: KnowledgeDateFilterMode.normalize(
        _string(
          json['date_filter_mode'],
          KnowledgeDateFilterMode.hardWhenExplicit,
        ),
      ),
      vectorWeight: KnowledgeBaseSettingRanges.vectorWeight.fromValue(
        json['vector_weight'],
      ),
      titleWeight: KnowledgeBaseSettingRanges.titleWeight.fromValue(
        json['title_weight'],
      ),
      tagWeight: KnowledgeBaseSettingRanges.tagWeight.fromValue(
        json['tag_weight'],
      ),
      timeWeight: KnowledgeBaseSettingRanges.timeWeight.fromValue(
        json['time_weight'],
      ),
      exactPhraseWeight: KnowledgeBaseSettingRanges.exactPhraseWeight.fromValue(
        json['exact_phrase_weight'],
      ),
      sourceQualityWeight: KnowledgeBaseSettingRanges.sourceQualityWeight
          .fromValue(json['source_quality_weight']),
      mmrEnabled: _bool(json['mmr_enabled'], true),
      mmrLambda: KnowledgeBaseSettingRanges.mmrLambda.fromValue(
        json['mmr_lambda'],
      ),
      neighborExpansionEnabled: _bool(json['neighbor_expansion_enabled'], true),
      parentExpansionEnabled: _bool(json['parent_expansion_enabled'], true),
      maxChunksPerSource: KnowledgeBaseSettingRanges.maxChunksPerSource
          .fromValue(json['max_chunks_per_source']),
      cloudRerankEnabled:
          parsedRerankMode == KnowledgeRerankMode.model ||
          legacyCloudRerankEnabled,
      rerankMode: parsedRerankMode,
      rerankProviderConfigId: _string(
        json['rerank_provider_config_id'],
        _string(json['provider_config_id']),
      ),
      rerankModelId: _string(json['rerank_model_id']),
      skipModelRerankWhenEmbeddingSupportsRerank: _bool(
        json[_skipDualCapabilityRerankJsonKey],
      ),
      rerankTopN: KnowledgeBaseSettingRanges.rerankTopN.fromValue(
        json['rerank_top_n'],
      ),
      rerankTimeoutSeconds: KnowledgeBaseSettingRanges.rerankTimeoutSeconds
          .fromValue(json['rerank_timeout_seconds']),
      maxPromptChunks: KnowledgeBaseSettingRanges.maxPromptChunks.fromValue(
        json['max_prompt_chunks'],
      ),
      maxPromptTokens: KnowledgeBaseSettingRanges.maxPromptTokens.fromValue(
        json['max_prompt_tokens'],
      ),
      includeScore: _bool(json['include_score'], true),
      includeTags: _bool(json['include_tags'], true),
      includeDate: _bool(json['include_date'], true),
      includeSourcePath: _bool(json['include_source_path'], true),
      includeChunkId: _bool(json['include_chunk_id'], true),
      failureStrategy: KnowledgeFailureStrategy.normalize(
        _string(json['failure_strategy'], KnowledgeFailureStrategy.failOpen),
      ),
      embeddingFailureStrategy: KnowledgeFailureStrategy.normalize(
        _string(
          json['embedding_failure_strategy'],
          KnowledgeFailureStrategy.failOpen,
        ),
      ),
      continueWhenNoHits: _bool(json['continue_when_no_hits'], true),
      showPreviewBeforeSend: _bool(json['show_preview_before_send']),
      cacheQueryEmbedding: _bool(json['cache_query_embedding'], true),
      qdrantMetricsRefreshSeconds: KnowledgeBaseSettingRanges
          .qdrantMetricsRefreshSeconds
          .fromValue(json['qdrant_metrics_refresh_seconds']),
      qdrantLogRetainLines: KnowledgeBaseSettingRanges.qdrantLogRetainLines
          .fromValue(json['qdrant_log_retain_lines']),
      enableDangerousAdminOperations: _bool(
        json['enable_dangerous_admin_operations'],
      ),
    );
  }

  final String providerConfigId;
  final String modelId;
  final String displayName;
  final int dimensions;
  final int maxInputTokens;
  final int batchSize;
  final int requestTimeoutSeconds;
  final int retryCount;
  final int retryBackoffMs;
  final int concurrentRequests;
  final bool allowDocumentCloudEmbedding;
  final bool allowQueryCloudEmbedding;
  final String vectorStoreType;
  final String qdrantHost;
  final int qdrantRestPort;
  final int qdrantGrpcPort;
  final String collectionName;
  final String distanceMetric;
  final int hnswM;
  final int hnswEfConstruct;
  final int searchEf;
  final bool autoStartSidecar;
  final bool copyImportedFiles;
  final bool watchOriginalFiles;
  final int maxFileSizeMb;
  final String documentParsingEngine;
  final String officeParsingEngine;
  final String pdfParsingEngine;
  final String htmlParsingMode;
  final String structuredDataParsingMode;
  final String spreadsheetParsingMode;
  final String presentationParsingMode;
  final Map<String, KnowledgeReaderParserRule> readerParserRules;
  final String chunkStrategy;
  final int targetTokens;
  final int hardMaxTokens;
  final int overlapTokens;
  final bool parentChildEnabled;
  final bool autoPathTags;
  final bool autoFrontMatterTags;
  final bool autoTagSuggestions;
  final String defaultDocumentTimeSource;
  final bool parseNaturalLanguageTime;
  final bool recencyBoostEnabled;
  final int topN;
  final int topK;
  final double minSimilarity;
  final int sourceCap;
  final String tagFilterMode;
  final String dateFilterMode;
  final double vectorWeight;
  final double titleWeight;
  final double tagWeight;
  final double timeWeight;
  final double exactPhraseWeight;
  final double sourceQualityWeight;
  final bool mmrEnabled;
  final double mmrLambda;
  final bool neighborExpansionEnabled;
  final bool parentExpansionEnabled;
  final int maxChunksPerSource;
  final bool cloudRerankEnabled;
  final String rerankMode;
  final String rerankProviderConfigId;
  final String rerankModelId;
  final bool skipModelRerankWhenEmbeddingSupportsRerank;
  final int rerankTopN;
  final int rerankTimeoutSeconds;
  final int maxPromptChunks;
  final int maxPromptTokens;
  final bool includeScore;
  final bool includeTags;
  final bool includeDate;
  final bool includeSourcePath;
  final bool includeChunkId;
  final String failureStrategy;
  final String embeddingFailureStrategy;
  final bool continueWhenNoHits;
  final bool showPreviewBeforeSend;
  final bool cacheQueryEmbedding;
  final int qdrantMetricsRefreshSeconds;
  final int qdrantLogRetainLines;
  final bool enableDangerousAdminOperations;

  bool get hasEmbeddingModel =>
      nullIfBlank(providerConfigId) != null && nullIfBlank(modelId) != null;

  bool get modelRerankEnabled => rerankMode == KnowledgeRerankMode.model;

  bool get hasRerankModel =>
      nullIfBlank(rerankProviderConfigId) != null &&
      nullIfBlank(rerankModelId) != null;

  KnowledgeReaderParserRule readerRuleForSourceType(String sourceType) {
    final normalized = ReaderFileType.normalize(sourceType);
    return readerParserRules[normalized] ?? const KnowledgeReaderParserRule();
  }

  String get effectiveCollectionName {
    final normalizedCollectionName = nullIfBlank(collectionName);
    if (normalizedCollectionName != null) return normalizedCollectionName;
    final raw = '${providerConfigId}_${modelId}_$dimensions'
        .replaceAll(_knowledgeCollectionNameUnsafeCharsPattern, '_')
        .toLowerCase();
    return 'openhand_knowledge_$raw';
  }

  Uri get qdrantBaseUri => Uri(
    scheme: 'http',
    host: normalizeQdrantHost(qdrantHost),
    port: tcpPortFromValueOr(
      qdrantRestPort,
      fallback: KnowledgeBaseSettingRanges.defaultQdrantRestPort,
    ),
  );

  KnowledgeBaseSettings copyWith({
    String? providerConfigId,
    String? modelId,
    String? displayName,
    int? dimensions,
    int? maxInputTokens,
    int? batchSize,
    int? requestTimeoutSeconds,
    int? retryCount,
    int? retryBackoffMs,
    int? concurrentRequests,
    bool? allowDocumentCloudEmbedding,
    bool? allowQueryCloudEmbedding,
    String? vectorStoreType,
    String? qdrantHost,
    int? qdrantRestPort,
    int? qdrantGrpcPort,
    String? collectionName,
    String? distanceMetric,
    int? hnswM,
    int? hnswEfConstruct,
    int? searchEf,
    bool? autoStartSidecar,
    bool? copyImportedFiles,
    bool? watchOriginalFiles,
    int? maxFileSizeMb,
    String? documentParsingEngine,
    String? officeParsingEngine,
    String? pdfParsingEngine,
    String? htmlParsingMode,
    String? structuredDataParsingMode,
    String? spreadsheetParsingMode,
    String? presentationParsingMode,
    Map<String, KnowledgeReaderParserRule>? readerParserRules,
    String? chunkStrategy,
    int? targetTokens,
    int? hardMaxTokens,
    int? overlapTokens,
    bool? parentChildEnabled,
    bool? autoPathTags,
    bool? autoFrontMatterTags,
    bool? autoTagSuggestions,
    String? defaultDocumentTimeSource,
    bool? parseNaturalLanguageTime,
    bool? recencyBoostEnabled,
    int? topN,
    int? topK,
    double? minSimilarity,
    int? sourceCap,
    String? tagFilterMode,
    String? dateFilterMode,
    double? vectorWeight,
    double? titleWeight,
    double? tagWeight,
    double? timeWeight,
    double? exactPhraseWeight,
    double? sourceQualityWeight,
    bool? mmrEnabled,
    double? mmrLambda,
    bool? neighborExpansionEnabled,
    bool? parentExpansionEnabled,
    int? maxChunksPerSource,
    bool? cloudRerankEnabled,
    String? rerankMode,
    String? rerankProviderConfigId,
    String? rerankModelId,
    bool? skipModelRerankWhenEmbeddingSupportsRerank,
    int? rerankTopN,
    int? rerankTimeoutSeconds,
    int? maxPromptChunks,
    int? maxPromptTokens,
    bool? includeScore,
    bool? includeTags,
    bool? includeDate,
    bool? includeSourcePath,
    bool? includeChunkId,
    String? failureStrategy,
    String? embeddingFailureStrategy,
    bool? continueWhenNoHits,
    bool? showPreviewBeforeSend,
    bool? cacheQueryEmbedding,
    int? qdrantMetricsRefreshSeconds,
    int? qdrantLogRetainLines,
    bool? enableDangerousAdminOperations,
  }) {
    final nextRerankMode = rerankMode ?? this.rerankMode;
    final nextTargetTokens = KnowledgeBaseSettingRanges.targetTokens.normalize(
      targetTokens ?? this.targetTokens,
    );
    final nextHardMaxTokens = _normalizeHardMaxTokens(
      KnowledgeBaseSettingRanges.hardMaxTokens.normalize(
        hardMaxTokens ?? this.hardMaxTokens,
      ),
      targetTokens: nextTargetTokens,
    );
    final nextOverlapTokens = _normalizeOverlapTokens(
      KnowledgeBaseSettingRanges.overlapTokens.normalize(
        overlapTokens ?? this.overlapTokens,
      ),
      targetTokens: nextTargetTokens,
    );
    final nextTopN = KnowledgeBaseSettingRanges.topN.normalize(
      topN ?? this.topN,
    );
    final nextTopK = _normalizeTopK(
      KnowledgeBaseSettingRanges.topK.normalize(topK ?? this.topK),
      topN: nextTopN,
    );
    return KnowledgeBaseSettings(
      providerConfigId: providerConfigId ?? this.providerConfigId,
      modelId: modelId ?? this.modelId,
      displayName: displayName ?? this.displayName,
      dimensions: KnowledgeBaseSettingRanges.dimensions.normalize(
        dimensions ?? this.dimensions,
      ),
      maxInputTokens: KnowledgeBaseSettingRanges.maxInputTokens.normalize(
        maxInputTokens ?? this.maxInputTokens,
      ),
      batchSize: KnowledgeBaseSettingRanges.batchSize.normalize(
        batchSize ?? this.batchSize,
      ),
      requestTimeoutSeconds: KnowledgeBaseSettingRanges.requestTimeoutSeconds
          .normalize(requestTimeoutSeconds ?? this.requestTimeoutSeconds),
      retryCount: KnowledgeBaseSettingRanges.retryCount.normalize(
        retryCount ?? this.retryCount,
      ),
      retryBackoffMs: KnowledgeBaseSettingRanges.retryBackoffMs.normalize(
        retryBackoffMs ?? this.retryBackoffMs,
      ),
      concurrentRequests: KnowledgeBaseSettingRanges.concurrentRequests
          .normalize(concurrentRequests ?? this.concurrentRequests),
      allowDocumentCloudEmbedding:
          allowDocumentCloudEmbedding ?? this.allowDocumentCloudEmbedding,
      allowQueryCloudEmbedding:
          allowQueryCloudEmbedding ?? this.allowQueryCloudEmbedding,
      vectorStoreType: vectorStoreType ?? this.vectorStoreType,
      qdrantHost: normalizeQdrantHost(qdrantHost ?? this.qdrantHost),
      qdrantRestPort: tcpPortFromValueOr(
        qdrantRestPort ?? this.qdrantRestPort,
        fallback: KnowledgeBaseSettingRanges.defaultQdrantRestPort,
      ),
      qdrantGrpcPort: tcpPortFromValueOr(
        qdrantGrpcPort ?? this.qdrantGrpcPort,
        fallback: KnowledgeBaseSettingRanges.defaultQdrantGrpcPort,
      ),
      collectionName: collectionName ?? this.collectionName,
      distanceMetric: distanceMetric == null
          ? this.distanceMetric
          : KnowledgeDistanceMetric.normalize(distanceMetric),
      hnswM: KnowledgeBaseSettingRanges.hnswM.normalize(hnswM ?? this.hnswM),
      hnswEfConstruct: KnowledgeBaseSettingRanges.hnswEfConstruct.normalize(
        hnswEfConstruct ?? this.hnswEfConstruct,
      ),
      searchEf: KnowledgeBaseSettingRanges.searchEf.normalize(
        searchEf ?? this.searchEf,
      ),
      autoStartSidecar: autoStartSidecar ?? this.autoStartSidecar,
      copyImportedFiles: copyImportedFiles ?? this.copyImportedFiles,
      watchOriginalFiles: watchOriginalFiles ?? this.watchOriginalFiles,
      maxFileSizeMb: KnowledgeBaseSettingRanges.maxFileSizeMb.normalize(
        maxFileSizeMb ?? this.maxFileSizeMb,
      ),
      documentParsingEngine:
          documentParsingEngine ?? this.documentParsingEngine,
      officeParsingEngine: officeParsingEngine ?? this.officeParsingEngine,
      pdfParsingEngine: pdfParsingEngine ?? this.pdfParsingEngine,
      htmlParsingMode: htmlParsingMode ?? this.htmlParsingMode,
      structuredDataParsingMode:
          structuredDataParsingMode ?? this.structuredDataParsingMode,
      spreadsheetParsingMode:
          spreadsheetParsingMode ?? this.spreadsheetParsingMode,
      presentationParsingMode:
          presentationParsingMode ?? this.presentationParsingMode,
      readerParserRules: _normalizeReaderParserRules(
        readerParserRules ?? this.readerParserRules,
      ),
      chunkStrategy: chunkStrategy == null
          ? this.chunkStrategy
          : KnowledgeChunkStrategy.normalize(chunkStrategy),
      targetTokens: nextTargetTokens,
      hardMaxTokens: nextHardMaxTokens,
      overlapTokens: nextOverlapTokens,
      parentChildEnabled: parentChildEnabled ?? this.parentChildEnabled,
      autoPathTags: autoPathTags ?? this.autoPathTags,
      autoFrontMatterTags: autoFrontMatterTags ?? this.autoFrontMatterTags,
      autoTagSuggestions: autoTagSuggestions ?? this.autoTagSuggestions,
      defaultDocumentTimeSource:
          defaultDocumentTimeSource ?? this.defaultDocumentTimeSource,
      parseNaturalLanguageTime:
          parseNaturalLanguageTime ?? this.parseNaturalLanguageTime,
      recencyBoostEnabled: recencyBoostEnabled ?? this.recencyBoostEnabled,
      topN: nextTopN,
      topK: nextTopK,
      minSimilarity: KnowledgeBaseSettingRanges.minSimilarity.normalize(
        minSimilarity ?? this.minSimilarity,
      ),
      sourceCap: KnowledgeBaseSettingRanges.sourceCap.normalize(
        sourceCap ?? this.sourceCap,
      ),
      tagFilterMode: tagFilterMode == null
          ? this.tagFilterMode
          : KnowledgeTagFilterMode.normalize(tagFilterMode),
      dateFilterMode: dateFilterMode == null
          ? this.dateFilterMode
          : KnowledgeDateFilterMode.normalize(dateFilterMode),
      vectorWeight: KnowledgeBaseSettingRanges.vectorWeight.normalize(
        vectorWeight ?? this.vectorWeight,
      ),
      titleWeight: KnowledgeBaseSettingRanges.titleWeight.normalize(
        titleWeight ?? this.titleWeight,
      ),
      tagWeight: KnowledgeBaseSettingRanges.tagWeight.normalize(
        tagWeight ?? this.tagWeight,
      ),
      timeWeight: KnowledgeBaseSettingRanges.timeWeight.normalize(
        timeWeight ?? this.timeWeight,
      ),
      exactPhraseWeight: KnowledgeBaseSettingRanges.exactPhraseWeight.normalize(
        exactPhraseWeight ?? this.exactPhraseWeight,
      ),
      sourceQualityWeight: KnowledgeBaseSettingRanges.sourceQualityWeight
          .normalize(sourceQualityWeight ?? this.sourceQualityWeight),
      mmrEnabled: mmrEnabled ?? this.mmrEnabled,
      mmrLambda: KnowledgeBaseSettingRanges.mmrLambda.normalize(
        mmrLambda ?? this.mmrLambda,
      ),
      neighborExpansionEnabled:
          neighborExpansionEnabled ?? this.neighborExpansionEnabled,
      parentExpansionEnabled:
          parentExpansionEnabled ?? this.parentExpansionEnabled,
      maxChunksPerSource: KnowledgeBaseSettingRanges.maxChunksPerSource
          .normalize(maxChunksPerSource ?? this.maxChunksPerSource),
      cloudRerankEnabled:
          cloudRerankEnabled ?? (nextRerankMode == KnowledgeRerankMode.model),
      rerankMode: KnowledgeRerankMode.normalize(nextRerankMode),
      rerankProviderConfigId:
          rerankProviderConfigId ?? this.rerankProviderConfigId,
      rerankModelId: rerankModelId ?? this.rerankModelId,
      skipModelRerankWhenEmbeddingSupportsRerank:
          skipModelRerankWhenEmbeddingSupportsRerank ??
          this.skipModelRerankWhenEmbeddingSupportsRerank,
      rerankTopN: KnowledgeBaseSettingRanges.rerankTopN.normalize(
        rerankTopN ?? this.rerankTopN,
      ),
      rerankTimeoutSeconds: KnowledgeBaseSettingRanges.rerankTimeoutSeconds
          .normalize(rerankTimeoutSeconds ?? this.rerankTimeoutSeconds),
      maxPromptChunks: KnowledgeBaseSettingRanges.maxPromptChunks.normalize(
        maxPromptChunks ?? this.maxPromptChunks,
      ),
      maxPromptTokens: KnowledgeBaseSettingRanges.maxPromptTokens.normalize(
        maxPromptTokens ?? this.maxPromptTokens,
      ),
      includeScore: includeScore ?? this.includeScore,
      includeTags: includeTags ?? this.includeTags,
      includeDate: includeDate ?? this.includeDate,
      includeSourcePath: includeSourcePath ?? this.includeSourcePath,
      includeChunkId: includeChunkId ?? this.includeChunkId,
      failureStrategy: failureStrategy == null
          ? this.failureStrategy
          : KnowledgeFailureStrategy.normalize(failureStrategy),
      embeddingFailureStrategy: embeddingFailureStrategy == null
          ? this.embeddingFailureStrategy
          : KnowledgeFailureStrategy.normalize(embeddingFailureStrategy),
      continueWhenNoHits: continueWhenNoHits ?? this.continueWhenNoHits,
      showPreviewBeforeSend:
          showPreviewBeforeSend ?? this.showPreviewBeforeSend,
      cacheQueryEmbedding: cacheQueryEmbedding ?? this.cacheQueryEmbedding,
      qdrantMetricsRefreshSeconds: KnowledgeBaseSettingRanges
          .qdrantMetricsRefreshSeconds
          .normalize(
            qdrantMetricsRefreshSeconds ?? this.qdrantMetricsRefreshSeconds,
          ),
      qdrantLogRetainLines: KnowledgeBaseSettingRanges.qdrantLogRetainLines
          .normalize(qdrantLogRetainLines ?? this.qdrantLogRetainLines),
      enableDangerousAdminOperations:
          enableDangerousAdminOperations ?? this.enableDangerousAdminOperations,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'provider_config_id': providerConfigId,
      'model_id': modelId,
      'display_name': displayName,
      'dimensions': dimensions,
      'max_input_tokens': maxInputTokens,
      'batch_size': batchSize,
      'request_timeout_seconds': requestTimeoutSeconds,
      'retry_count': retryCount,
      'retry_backoff_ms': retryBackoffMs,
      'concurrent_requests': concurrentRequests,
      'allow_document_cloud_embedding': allowDocumentCloudEmbedding,
      'allow_query_cloud_embedding': allowQueryCloudEmbedding,
      'vector_store_type': vectorStoreType,
      'qdrant_host': qdrantHost,
      'qdrant_rest_port': qdrantRestPort,
      'qdrant_grpc_port': qdrantGrpcPort,
      'collection_name': collectionName,
      'distance_metric': distanceMetric,
      'hnsw_m': hnswM,
      'hnsw_ef_construct': hnswEfConstruct,
      'search_ef': searchEf,
      'auto_start_sidecar': autoStartSidecar,
      'copy_imported_files': copyImportedFiles,
      'watch_original_files': watchOriginalFiles,
      'max_file_size_mb': maxFileSizeMb,
      'document_parsing_engine': documentParsingEngine,
      'office_parsing_engine': officeParsingEngine,
      'pdf_parsing_engine': pdfParsingEngine,
      'html_parsing_mode': htmlParsingMode,
      'structured_data_parsing_mode': structuredDataParsingMode,
      'spreadsheet_parsing_mode': spreadsheetParsingMode,
      'presentation_parsing_mode': presentationParsingMode,
      if (readerParserRules.isNotEmpty)
        'reader_parser_rules': <String, Object?>{
          for (final entry in readerParserRules.entries)
            ReaderFileType.normalize(entry.key): entry.value.toJson(),
        },
      'chunk_strategy': chunkStrategy,
      'target_tokens': targetTokens,
      'hard_max_tokens': hardMaxTokens,
      'overlap_tokens': overlapTokens,
      'parent_child_enabled': parentChildEnabled,
      'auto_path_tags': autoPathTags,
      'auto_front_matter_tags': autoFrontMatterTags,
      'auto_tag_suggestions': autoTagSuggestions,
      'default_document_time_source': defaultDocumentTimeSource,
      'parse_natural_language_time': parseNaturalLanguageTime,
      'recency_boost_enabled': recencyBoostEnabled,
      'top_n': topN,
      'top_k': topK,
      'min_similarity': minSimilarity,
      'source_cap': sourceCap,
      'tag_filter_mode': tagFilterMode,
      'date_filter_mode': dateFilterMode,
      'vector_weight': vectorWeight,
      'title_weight': titleWeight,
      'tag_weight': tagWeight,
      'time_weight': timeWeight,
      'exact_phrase_weight': exactPhraseWeight,
      'source_quality_weight': sourceQualityWeight,
      'mmr_enabled': mmrEnabled,
      'mmr_lambda': mmrLambda,
      'neighbor_expansion_enabled': neighborExpansionEnabled,
      'parent_expansion_enabled': parentExpansionEnabled,
      'max_chunks_per_source': maxChunksPerSource,
      'cloud_rerank_enabled': modelRerankEnabled,
      'rerank_mode': rerankMode,
      'rerank_provider_config_id': rerankProviderConfigId,
      'rerank_model_id': rerankModelId,
      _skipDualCapabilityRerankJsonKey:
          skipModelRerankWhenEmbeddingSupportsRerank,
      'rerank_top_n': rerankTopN,
      'rerank_timeout_seconds': rerankTimeoutSeconds,
      'max_prompt_chunks': maxPromptChunks,
      'max_prompt_tokens': maxPromptTokens,
      'include_score': includeScore,
      'include_tags': includeTags,
      'include_date': includeDate,
      'include_source_path': includeSourcePath,
      'include_chunk_id': includeChunkId,
      'failure_strategy': failureStrategy,
      'embedding_failure_strategy': embeddingFailureStrategy,
      'continue_when_no_hits': continueWhenNoHits,
      'show_preview_before_send': showPreviewBeforeSend,
      'cache_query_embedding': cacheQueryEmbedding,
      'qdrant_metrics_refresh_seconds': qdrantMetricsRefreshSeconds,
      'qdrant_log_retain_lines': qdrantLogRetainLines,
      'enable_dangerous_admin_operations': enableDangerousAdminOperations,
    };
  }

  String encode() {
    final payload = toJson();
    _validateJson(payload);
    final encoded = jsonEncode(payload);
    if (utf8ByteLength(encoded) > _maxKnowledgeBaseSettingsBytes) {
      throw const FormatException('知识库配置超过安全上限。');
    }
    return encoded;
  }

  static KnowledgeBaseSettings decode(String value) {
    final text = nullIfBlank(value);
    if (text == null) {
      throw const FormatException('知识库配置为空。');
    }
    if (utf8ByteLength(text) > _maxKnowledgeBaseSettingsBytes) {
      throw const FormatException('知识库配置超过安全上限。');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('知识库配置必须是 JSON 对象。');
    }
    final payload = stringKeyedMapFromValue(decoded);
    _validateJson(payload);
    return KnowledgeBaseSettings.fromJson(payload);
  }

  static void _validateJson(Map<String, Object?> payload) {
    validateCanonicalJsonSubset(
      payload,
      payload,
      path: 'knowledge_base_settings',
      maxDepth: 8,
      maxContainerItems: 256,
      maxTotalNodes: 4096,
    );
  }

  static String _string(Object? value, [String fallback = '']) {
    return stringFromValue(value, fallback: fallback);
  }

  static bool _bool(Object? value, [bool fallback = false]) {
    return boolFromValue(value, defaultValue: fallback);
  }

  static String normalizeQdrantHost(
    Object? value, {
    String fallback = KnowledgeBaseSettingRanges.defaultQdrantHost,
  }) {
    final fallbackHost =
        nullIfBlank(fallback) ?? KnowledgeBaseSettingRanges.defaultQdrantHost;
    final raw = optionalStringFromValue(value);
    if (raw == null) return fallbackHost;
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return parsed.host;
    }
    final inferred = Uri.tryParse('http://$raw');
    if (inferred != null && inferred.host.isNotEmpty) {
      return inferred.host;
    }
    return raw;
  }

  static int _normalizeHardMaxTokens(int value, {required int targetTokens}) {
    return value < targetTokens ? targetTokens : value;
  }

  static int _normalizeOverlapTokens(int value, {required int targetTokens}) {
    if (targetTokens <= 1) return 0;
    final maxOverlap = targetTokens - 1;
    return value > maxOverlap ? maxOverlap : value;
  }

  static int _normalizeTopK(int value, {required int topN}) {
    return value > topN ? topN : value;
  }

  static Map<String, KnowledgeReaderParserRule> _parseReaderParserRules(
    Object? value,
  ) {
    if (value is! Map) return const <String, KnowledgeReaderParserRule>{};
    final result = <String, KnowledgeReaderParserRule>{};
    final map = stringKeyedMapFromValue(value);
    for (final entry in map.entries) {
      final sourceType = ReaderFileType.normalize(entry.key);
      if (sourceType.isEmpty) continue;
      final rawRule = entry.value;
      if (rawRule is! Map) continue;
      result[sourceType] = KnowledgeReaderParserRule.fromJson(
        stringKeyedMapFromValue(rawRule),
      );
    }
    return Map<String, KnowledgeReaderParserRule>.unmodifiable(result);
  }

  static Map<String, KnowledgeReaderParserRule> _normalizeReaderParserRules(
    Map<String, KnowledgeReaderParserRule> rules,
  ) {
    if (rules.isEmpty) return const <String, KnowledgeReaderParserRule>{};
    final result = <String, KnowledgeReaderParserRule>{};
    for (final entry in rules.entries) {
      final sourceType = ReaderFileType.normalize(entry.key);
      if (sourceType.isEmpty) continue;
      result[sourceType] = entry.value.copyWith();
    }
    return Map<String, KnowledgeReaderParserRule>.unmodifiable(result);
  }
}

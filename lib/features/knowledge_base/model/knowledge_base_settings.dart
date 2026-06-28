import 'dart:convert';

const _skipDualCapabilityRerankJsonKey =
    'skip_model_rerank_when_embedding_supports_rerank';

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
    final normalized = value.trim();
    return values.contains(normalized) ? normalized : markdownHeadingRecursive;
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
    final normalized = value.trim();
    return values.contains(normalized) ? normalized : localHybrid;
  }
}

class KnowledgeBaseSettings {
  const KnowledgeBaseSettings({
    this.providerConfigId = '',
    this.modelId = '',
    this.displayName = '',
    this.dimensions = 1536,
    this.maxInputTokens = 8192,
    this.batchSize = 16,
    this.requestTimeoutSeconds = 60,
    this.retryCount = 2,
    this.retryBackoffMs = 800,
    this.concurrentRequests = 2,
    this.allowDocumentCloudEmbedding = false,
    this.allowQueryCloudEmbedding = false,
    this.vectorStoreType = 'qdrant',
    this.qdrantHost = '127.0.0.1',
    this.qdrantRestPort = 6333,
    this.qdrantGrpcPort = 6334,
    this.collectionName = '',
    this.distanceMetric = 'cosine',
    this.hnswM = 16,
    this.hnswEfConstruct = 100,
    this.searchEf = 64,
    this.autoStartSidecar = false,
    this.copyImportedFiles = true,
    this.watchOriginalFiles = false,
    this.maxFileSizeMb = 50,
    this.documentParsingEngine = 'auto',
    this.officeParsingEngine = 'open_xml',
    this.pdfParsingEngine = 'basic_text_stream',
    this.htmlParsingMode = 'readable_text',
    this.structuredDataParsingMode = 'readable_markdown',
    this.spreadsheetParsingMode = 'markdown_table',
    this.presentationParsingMode = 'slide_text',
    this.chunkStrategy = KnowledgeChunkStrategy.markdownHeadingRecursive,
    this.targetTokens = 700,
    this.hardMaxTokens = 1200,
    this.overlapTokens = 120,
    this.parentChildEnabled = true,
    this.autoPathTags = true,
    this.autoFrontMatterTags = true,
    this.autoTagSuggestions = false,
    this.defaultDocumentTimeSource = 'front_matter',
    this.parseNaturalLanguageTime = true,
    this.recencyBoostEnabled = true,
    this.topN = 80,
    this.topK = 6,
    this.minSimilarity = 0.25,
    this.sourceCap = 3,
    this.tagFilterMode = 'any',
    this.dateFilterMode = 'hard_when_explicit',
    this.vectorWeight = 0.65,
    this.titleWeight = 0.10,
    this.tagWeight = 0.10,
    this.timeWeight = 0.08,
    this.exactPhraseWeight = 0.05,
    this.sourceQualityWeight = 0.02,
    this.mmrEnabled = true,
    this.mmrLambda = 0.72,
    this.neighborExpansionEnabled = true,
    this.parentExpansionEnabled = true,
    this.maxChunksPerSource = 3,
    this.cloudRerankEnabled = false,
    this.rerankMode = KnowledgeRerankMode.localHybrid,
    this.rerankProviderConfigId = '',
    this.rerankModelId = '',
    this.skipModelRerankWhenEmbeddingSupportsRerank = false,
    this.rerankTopN = 24,
    this.rerankTimeoutSeconds = 30,
    this.maxPromptChunks = 6,
    this.maxPromptTokens = 6000,
    this.includeScore = true,
    this.includeTags = true,
    this.includeDate = true,
    this.includeSourcePath = true,
    this.includeChunkId = true,
    this.failureStrategy = 'fail_open',
    this.embeddingFailureStrategy = 'fail_open',
    this.continueWhenNoHits = true,
    this.showPreviewBeforeSend = false,
    this.cacheQueryEmbedding = true,
    this.exposeReadonlyTools = false,
    this.qdrantMetricsRefreshSeconds = 10,
    this.qdrantLogRetainLines = 300,
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
    return KnowledgeBaseSettings(
      providerConfigId: _string(json['provider_config_id']),
      modelId: _string(json['model_id']),
      displayName: _string(json['display_name']),
      dimensions: _positiveInt(json['dimensions'], 1536),
      maxInputTokens: _positiveInt(json['max_input_tokens'], 8192),
      batchSize: _positiveInt(json['batch_size'], 16),
      requestTimeoutSeconds: _positiveInt(json['request_timeout_seconds'], 60),
      retryCount: _nonNegativeInt(json['retry_count'], 2),
      retryBackoffMs: _positiveInt(json['retry_backoff_ms'], 800),
      concurrentRequests: _positiveInt(json['concurrent_requests'], 2),
      allowDocumentCloudEmbedding: _bool(
        json['allow_document_cloud_embedding'],
      ),
      allowQueryCloudEmbedding: _bool(json['allow_query_cloud_embedding']),
      vectorStoreType: _string(json['vector_store_type'], 'qdrant'),
      qdrantHost: _string(json['qdrant_host'], '127.0.0.1'),
      qdrantRestPort: _positiveInt(json['qdrant_rest_port'], 6333),
      qdrantGrpcPort: _positiveInt(json['qdrant_grpc_port'], 6334),
      collectionName: _string(json['collection_name']),
      distanceMetric: _string(json['distance_metric'], 'cosine'),
      hnswM: _positiveInt(json['hnsw_m'], 16),
      hnswEfConstruct: _positiveInt(json['hnsw_ef_construct'], 100),
      searchEf: _positiveInt(json['search_ef'], 64),
      autoStartSidecar: _bool(json['auto_start_sidecar']),
      copyImportedFiles: _bool(json['copy_imported_files'], true),
      watchOriginalFiles: _bool(json['watch_original_files']),
      maxFileSizeMb: _positiveInt(json['max_file_size_mb'], 50),
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
      chunkStrategy: KnowledgeChunkStrategy.normalize(
        _string(
          json['chunk_strategy'],
          KnowledgeChunkStrategy.markdownHeadingRecursive,
        ),
      ),
      targetTokens: _positiveInt(json['target_tokens'], 700),
      hardMaxTokens: _positiveInt(json['hard_max_tokens'], 1200),
      overlapTokens: _nonNegativeInt(json['overlap_tokens'], 120),
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
      topN: _positiveInt(json['top_n'], 80),
      topK: _positiveInt(json['top_k'], 6),
      minSimilarity: _double(json['min_similarity'], 0.25),
      sourceCap: _positiveInt(json['source_cap'], 3),
      tagFilterMode: _string(json['tag_filter_mode'], 'any'),
      dateFilterMode: _string(json['date_filter_mode'], 'hard_when_explicit'),
      vectorWeight: _double(json['vector_weight'], 0.65),
      titleWeight: _double(json['title_weight'], 0.10),
      tagWeight: _double(json['tag_weight'], 0.10),
      timeWeight: _double(json['time_weight'], 0.08),
      exactPhraseWeight: _double(json['exact_phrase_weight'], 0.05),
      sourceQualityWeight: _double(json['source_quality_weight'], 0.02),
      mmrEnabled: _bool(json['mmr_enabled'], true),
      mmrLambda: _double(json['mmr_lambda'], 0.72),
      neighborExpansionEnabled: _bool(json['neighbor_expansion_enabled'], true),
      parentExpansionEnabled: _bool(json['parent_expansion_enabled'], true),
      maxChunksPerSource: _positiveInt(json['max_chunks_per_source'], 3),
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
      rerankTopN: _positiveInt(json['rerank_top_n'], 24),
      rerankTimeoutSeconds: _positiveInt(json['rerank_timeout_seconds'], 30),
      maxPromptChunks: _positiveInt(json['max_prompt_chunks'], 6),
      maxPromptTokens: _positiveInt(json['max_prompt_tokens'], 6000),
      includeScore: _bool(json['include_score'], true),
      includeTags: _bool(json['include_tags'], true),
      includeDate: _bool(json['include_date'], true),
      includeSourcePath: _bool(json['include_source_path'], true),
      includeChunkId: _bool(json['include_chunk_id'], true),
      failureStrategy: _string(json['failure_strategy'], 'fail_open'),
      embeddingFailureStrategy: _string(
        json['embedding_failure_strategy'],
        'fail_open',
      ),
      continueWhenNoHits: _bool(json['continue_when_no_hits'], true),
      showPreviewBeforeSend: _bool(json['show_preview_before_send']),
      cacheQueryEmbedding: _bool(json['cache_query_embedding'], true),
      exposeReadonlyTools: _bool(json['expose_readonly_tools']),
      qdrantMetricsRefreshSeconds: _positiveInt(
        json['qdrant_metrics_refresh_seconds'],
        10,
      ),
      qdrantLogRetainLines: _positiveInt(json['qdrant_log_retain_lines'], 300),
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
  final bool exposeReadonlyTools;
  final int qdrantMetricsRefreshSeconds;
  final int qdrantLogRetainLines;
  final bool enableDangerousAdminOperations;

  bool get hasEmbeddingModel =>
      providerConfigId.trim().isNotEmpty && modelId.trim().isNotEmpty;

  bool get modelRerankEnabled => rerankMode == KnowledgeRerankMode.model;

  bool get hasRerankModel =>
      rerankProviderConfigId.trim().isNotEmpty &&
      rerankModelId.trim().isNotEmpty;

  String get effectiveCollectionName {
    if (collectionName.trim().isNotEmpty) return collectionName.trim();
    final raw = '${providerConfigId}_${modelId}_$dimensions'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]+'), '_')
        .toLowerCase();
    return 'openhand_knowledge_$raw';
  }

  Uri get qdrantBaseUri => Uri.parse('http://$qdrantHost:$qdrantRestPort');

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
    bool? exposeReadonlyTools,
    int? qdrantMetricsRefreshSeconds,
    int? qdrantLogRetainLines,
    bool? enableDangerousAdminOperations,
  }) {
    final nextRerankMode = rerankMode ?? this.rerankMode;
    return KnowledgeBaseSettings(
      providerConfigId: providerConfigId ?? this.providerConfigId,
      modelId: modelId ?? this.modelId,
      displayName: displayName ?? this.displayName,
      dimensions: dimensions ?? this.dimensions,
      maxInputTokens: maxInputTokens ?? this.maxInputTokens,
      batchSize: batchSize ?? this.batchSize,
      requestTimeoutSeconds:
          requestTimeoutSeconds ?? this.requestTimeoutSeconds,
      retryCount: retryCount ?? this.retryCount,
      retryBackoffMs: retryBackoffMs ?? this.retryBackoffMs,
      concurrentRequests: concurrentRequests ?? this.concurrentRequests,
      allowDocumentCloudEmbedding:
          allowDocumentCloudEmbedding ?? this.allowDocumentCloudEmbedding,
      allowQueryCloudEmbedding:
          allowQueryCloudEmbedding ?? this.allowQueryCloudEmbedding,
      vectorStoreType: vectorStoreType ?? this.vectorStoreType,
      qdrantHost: qdrantHost ?? this.qdrantHost,
      qdrantRestPort: qdrantRestPort ?? this.qdrantRestPort,
      qdrantGrpcPort: qdrantGrpcPort ?? this.qdrantGrpcPort,
      collectionName: collectionName ?? this.collectionName,
      distanceMetric: distanceMetric ?? this.distanceMetric,
      hnswM: hnswM ?? this.hnswM,
      hnswEfConstruct: hnswEfConstruct ?? this.hnswEfConstruct,
      searchEf: searchEf ?? this.searchEf,
      autoStartSidecar: autoStartSidecar ?? this.autoStartSidecar,
      copyImportedFiles: copyImportedFiles ?? this.copyImportedFiles,
      watchOriginalFiles: watchOriginalFiles ?? this.watchOriginalFiles,
      maxFileSizeMb: maxFileSizeMb ?? this.maxFileSizeMb,
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
      chunkStrategy: chunkStrategy == null
          ? this.chunkStrategy
          : KnowledgeChunkStrategy.normalize(chunkStrategy),
      targetTokens: targetTokens ?? this.targetTokens,
      hardMaxTokens: hardMaxTokens ?? this.hardMaxTokens,
      overlapTokens: overlapTokens ?? this.overlapTokens,
      parentChildEnabled: parentChildEnabled ?? this.parentChildEnabled,
      autoPathTags: autoPathTags ?? this.autoPathTags,
      autoFrontMatterTags: autoFrontMatterTags ?? this.autoFrontMatterTags,
      autoTagSuggestions: autoTagSuggestions ?? this.autoTagSuggestions,
      defaultDocumentTimeSource:
          defaultDocumentTimeSource ?? this.defaultDocumentTimeSource,
      parseNaturalLanguageTime:
          parseNaturalLanguageTime ?? this.parseNaturalLanguageTime,
      recencyBoostEnabled: recencyBoostEnabled ?? this.recencyBoostEnabled,
      topN: topN ?? this.topN,
      topK: topK ?? this.topK,
      minSimilarity: minSimilarity ?? this.minSimilarity,
      sourceCap: sourceCap ?? this.sourceCap,
      tagFilterMode: tagFilterMode ?? this.tagFilterMode,
      dateFilterMode: dateFilterMode ?? this.dateFilterMode,
      vectorWeight: vectorWeight ?? this.vectorWeight,
      titleWeight: titleWeight ?? this.titleWeight,
      tagWeight: tagWeight ?? this.tagWeight,
      timeWeight: timeWeight ?? this.timeWeight,
      exactPhraseWeight: exactPhraseWeight ?? this.exactPhraseWeight,
      sourceQualityWeight: sourceQualityWeight ?? this.sourceQualityWeight,
      mmrEnabled: mmrEnabled ?? this.mmrEnabled,
      mmrLambda: mmrLambda ?? this.mmrLambda,
      neighborExpansionEnabled:
          neighborExpansionEnabled ?? this.neighborExpansionEnabled,
      parentExpansionEnabled:
          parentExpansionEnabled ?? this.parentExpansionEnabled,
      maxChunksPerSource: maxChunksPerSource ?? this.maxChunksPerSource,
      cloudRerankEnabled:
          cloudRerankEnabled ?? (nextRerankMode == KnowledgeRerankMode.model),
      rerankMode: KnowledgeRerankMode.normalize(nextRerankMode),
      rerankProviderConfigId:
          rerankProviderConfigId ?? this.rerankProviderConfigId,
      rerankModelId: rerankModelId ?? this.rerankModelId,
      skipModelRerankWhenEmbeddingSupportsRerank:
          skipModelRerankWhenEmbeddingSupportsRerank ??
          this.skipModelRerankWhenEmbeddingSupportsRerank,
      rerankTopN: rerankTopN ?? this.rerankTopN,
      rerankTimeoutSeconds: rerankTimeoutSeconds ?? this.rerankTimeoutSeconds,
      maxPromptChunks: maxPromptChunks ?? this.maxPromptChunks,
      maxPromptTokens: maxPromptTokens ?? this.maxPromptTokens,
      includeScore: includeScore ?? this.includeScore,
      includeTags: includeTags ?? this.includeTags,
      includeDate: includeDate ?? this.includeDate,
      includeSourcePath: includeSourcePath ?? this.includeSourcePath,
      includeChunkId: includeChunkId ?? this.includeChunkId,
      failureStrategy: failureStrategy ?? this.failureStrategy,
      embeddingFailureStrategy:
          embeddingFailureStrategy ?? this.embeddingFailureStrategy,
      continueWhenNoHits: continueWhenNoHits ?? this.continueWhenNoHits,
      showPreviewBeforeSend:
          showPreviewBeforeSend ?? this.showPreviewBeforeSend,
      cacheQueryEmbedding: cacheQueryEmbedding ?? this.cacheQueryEmbedding,
      exposeReadonlyTools: exposeReadonlyTools ?? this.exposeReadonlyTools,
      qdrantMetricsRefreshSeconds:
          qdrantMetricsRefreshSeconds ?? this.qdrantMetricsRefreshSeconds,
      qdrantLogRetainLines: qdrantLogRetainLines ?? this.qdrantLogRetainLines,
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
      'expose_readonly_tools': exposeReadonlyTools,
      'qdrant_metrics_refresh_seconds': qdrantMetricsRefreshSeconds,
      'qdrant_log_retain_lines': qdrantLogRetainLines,
      'enable_dangerous_admin_operations': enableDangerousAdminOperations,
    };
  }

  String encode() => jsonEncode(toJson());

  static KnowledgeBaseSettings decode(String value) {
    if (value.trim().isEmpty) return const KnowledgeBaseSettings();
    final decoded = jsonDecode(value);
    if (decoded is Map) {
      return KnowledgeBaseSettings.fromJson(Map<String, Object?>.from(decoded));
    }
    return const KnowledgeBaseSettings();
  }

  static String _string(Object? value, [String fallback = '']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? fallback : text;
  }

  static bool _bool(Object? value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = '${value ?? ''}'.trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return fallback;
  }

  static int _positiveInt(Object? value, int fallback) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed == null || parsed <= 0 ? fallback : parsed;
  }

  static int _nonNegativeInt(Object? value, int fallback) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed == null || parsed < 0 ? fallback : parsed;
  }

  static double _double(Object? value, double fallback) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null || parsed.isNaN || !parsed.isFinite) return fallback;
    return parsed;
  }
}

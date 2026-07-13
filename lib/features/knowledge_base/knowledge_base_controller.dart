import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../app/support/openhand_paths.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/util/input_value_parsing.dart';
import '../ai/index.dart';
import '../plugin_service/index.dart';
import 'data/knowledge_base_settings_store.dart';
import 'data/knowledge_base_store.dart';
import 'model/knowledge_base_settings.dart';
import 'model/knowledge_chunk.dart';
import 'model/knowledge_retrieval_result.dart';
import 'model/knowledge_source.dart';
import 'model/knowledge_vector_distribution.dart';
import 'service/knowledge_chunker.dart';
import 'service/knowledge_dependency_service.dart';
import 'service/knowledge_document_parser.dart';
import 'service/knowledge_embedding_service.dart';
import 'service/knowledge_indexing_control.dart';
import 'service/knowledge_ingestion_service.dart';
import 'service/knowledge_retrieval_service.dart';
import 'service/knowledge_vector_store.dart';
import 'service/qdrant_admin_service.dart';
import 'service/qdrant_knowledge_vector_store.dart';
import 'service/qdrant_monitoring_service.dart';

class KnowledgeBaseController extends ChangeNotifier {
  KnowledgeBaseController({
    KnowledgeBaseSettingsStore? settingsStore,
    KnowledgeBaseStore? store,
    KnowledgeEmbeddingService? embeddingService,
    KnowledgeDependencyService dependencyService =
        const KnowledgeDependencyService(),
  }) : _settingsStore = settingsStore ?? KnowledgeBaseSettingsStore(),
       _store = store ?? KnowledgeBaseStore(),
       _embeddingService = embeddingService ?? KnowledgeEmbeddingService(),
       _dependencyService = dependencyService;

  final KnowledgeBaseSettingsStore _settingsStore;
  final KnowledgeBaseStore _store;
  final KnowledgeEmbeddingService _embeddingService;
  final KnowledgeDependencyService _dependencyService;
  final QdrantAdminService _qdrantAdminService = QdrantAdminService();

  KnowledgeBaseSettings _settings = const KnowledgeBaseSettings();
  List<KnowledgeSource> _sources = const <KnowledgeSource>[];
  bool _loading = true;
  bool _busy = false;
  String _query = '';
  String? _error;

  KnowledgeBaseSettings get settings => _settings;
  List<KnowledgeSource> get sources => _sources;
  bool get loading => _loading;
  bool get busy => _busy;
  String get query => _query;
  String? get error => _error;
  List<QdrantAdminOperationLog> get qdrantAdminLogs => _qdrantAdminService.logs;

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> initialize() async {
    _loading = true;
    notifyListeners();
    try {
      _settings = await _settingsStore.load();
      _sources = await _store.loadSources();
      _error = null;
    } catch (error) {
      _error = '$error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  KnowledgeDependencySnapshot dependencies(PluginServiceController controller) {
    return _dependencyService.snapshot(controller);
  }

  Future<void> updateSettings(KnowledgeBaseSettings settings) async {
    await _settingsStore.save(settings);
    _settings = settings;
    _qdrantAdminService.trimLogs(settings.qdrantLogRetainLines);
    notifyListeners();
  }

  Future<void> searchSources(String query) async {
    _query = query;
    _sources = await _store.loadSources(query: query);
    notifyListeners();
  }

  Future<KnowledgeSource?> importFile({
    required String filePath,
    required AiModelConfig embeddingModel,
    List<AiModelConfig> readerModels = const <AiModelConfig>[],
    List<String> tags = const <String>[],
    KnowledgeIndexingCancelToken? cancelToken,
    KnowledgeIndexingProgressCallback? onProgress,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final vectorStore = QdrantKnowledgeVectorStore(settings: _settings);
      final ingestion = KnowledgeIngestionService(
        store: _store,
        embeddingService: _embeddingService,
        vectorStore: vectorStore,
      );
      final KnowledgeSource source;
      try {
        source = await ingestion.importFile(
          filePath: filePath,
          settings: _settings,
          embeddingModel: embeddingModel,
          readerModels: readerModels,
          tags: tags,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
      } finally {
        ingestion.dispose();
      }
      _sources = await _store.loadSources(query: _query);
      return source;
    } on KnowledgeIndexingCancelledException {
      _error = null;
      _sources = await _store.loadSources(query: _query);
      return null;
    } catch (error) {
      _error = '$error';
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<KnowledgeSource?> importNote({
    required String title,
    required String content,
    required AiModelConfig embeddingModel,
    List<String> tags = const <String>[],
    KnowledgeIndexingCancelToken? cancelToken,
    KnowledgeIndexingProgressCallback? onProgress,
  }) async {
    cancelToken?.throwIfCancelled();
    final normalizedTitle = title.trim().isEmpty
        ? 'OpenHand Note'
        : title.trim();
    final normalizedContent = content.trim();
    if (normalizedContent.isEmpty) {
      throw StateError('笔记内容不能为空。');
    }
    final notesDir = Directory(
      p.join(
        OpenHandPaths.homeDirectoryPath(),
        '.openhand',
        'knowledge',
        'notes',
      ),
    );
    if (!await notesDir.exists()) {
      await notesDir.create(recursive: true);
    }
    final safeTitle = normalizedTitle
        .replaceAll(RegExp(r'[^a-zA-Z0-9\u4e00-\u9fa5._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    final file = File(
      p.join(
        notesDir.path,
        '${safeTitle.isEmpty ? 'note' : safeTitle}_${DateTime.now().millisecondsSinceEpoch}.md',
      ),
    );
    await writeFileAtomically(
      file,
      '# $normalizedTitle\n\n$normalizedContent\n',
    );
    cancelToken?.throwIfCancelled();
    return importFile(
      filePath: file.path,
      embeddingModel: embeddingModel,
      tags: tags,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }

  Future<List<KnowledgeChunk>> loadChunksForSource(String sourceId) async {
    final chunks = await _store.loadChunksForSource(sourceId);
    if (chunks.isNotEmpty) {
      return chunks;
    }
    final source = await _store.loadSource(sourceId);
    if (source == null || source.status != 'indexed') {
      return chunks;
    }
    final restored = await _restoreMissingChunksForSource(source);
    if (restored.isNotEmpty) {
      notifyListeners();
      return restored;
    }
    return chunks;
  }

  Future<KnowledgeSource?> loadSource(String sourceId) {
    return _store.loadSource(sourceId);
  }

  Future<({KnowledgeBaseSettings settings, KnowledgeRetrievalResult result})?>
  retrieveForTool({
    required String query,
    required int topK,
    required List<AiModelConfig> models,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return null;
    final embeddingModel = resolveEmbeddingModel(models);
    if (embeddingModel == null) return null;
    final effectiveTopK = topK.clamp(1, 20).toInt();
    final retrievalSettings = _settings.copyWith(
      topK: effectiveTopK,
      maxPromptChunks: math.max(effectiveTopK, _settings.maxPromptChunks),
      topN: math.max(_settings.topN, effectiveTopK),
    );
    final vectorStore = QdrantKnowledgeVectorStore(settings: retrievalSettings);
    final retrievalService = KnowledgeRetrievalService(
      store: _store,
      embeddingService: _embeddingService,
      vectorStore: vectorStore,
    );
    try {
      final result = await retrievalService.retrieve(
        query: normalizedQuery,
        settings: retrievalSettings,
        embeddingModel: embeddingModel,
        rerankModel: resolveRerankModel(models),
      );
      return (settings: retrievalSettings, result: result);
    } finally {
      retrievalService.dispose();
    }
  }

  Future<List<KnowledgeChunk>> _restoreMissingChunksForSource(
    KnowledgeSource source,
  ) async {
    try {
      final file = await _resolveReadableSourceFile(source);
      if (file == null) {
        return const <KnowledgeChunk>[];
      }
      final stat = await file.stat();
      final tags = _sourceTags(source);
      final parsed = await const KnowledgeDocumentParserRegistry().parse(
        KnowledgeDocumentParseRequest(
          file: file,
          settings: _settings,
          stat: stat,
          tags: tags,
        ),
      );
      final chunks = const KnowledgeChunker().chunk(
        source: source,
        text: parsed.text,
        settings: _settings,
        tags: tags,
      );
      if (chunks.isEmpty) {
        return const <KnowledgeChunk>[];
      }
      await _store.replaceChunks(sourceId: source.id, chunks: chunks);
      return chunks;
    } catch (_) {
      return const <KnowledgeChunk>[];
    }
  }

  Future<File?> _resolveReadableSourceFile(KnowledgeSource source) async {
    for (final path in <String>[source.storedPath, source.originalPath]) {
      final normalized = path.trim();
      if (normalized.isEmpty) {
        continue;
      }
      final file = File(normalized);
      if (await file.exists()) {
        return file;
      }
    }
    return null;
  }

  List<String> _sourceTags(KnowledgeSource source) {
    final raw = source.metadata['tags'];
    if (raw is! Iterable) {
      return const <String>[];
    }
    return stringListFromValue(
      raw.toList(growable: false),
    ).toSet().toList(growable: false);
  }

  Future<({int sourceCount, int chunkCount, int pendingJobs, int failedJobs})>
  loadStats() {
    return _store.loadStats();
  }

  Future<bool> deleteSource(KnowledgeSource source) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final vectorStore = QdrantKnowledgeVectorStore(settings: _settings);
      await vectorStore.deleteBySource(
        collectionName: _settings.effectiveCollectionName,
        sourceId: source.id,
      );
      await _store.deleteSource(source.id);
      _sources = await _store.loadSources(query: _query);
      return true;
    } catch (error) {
      _error = '$error';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<QdrantMonitoringSnapshot> loadMonitoringSnapshot() {
    return QdrantMonitoringService(store: _store).load(_settings);
  }

  Future<List<Map<String, Object?>>> listQdrantCollections() {
    return _qdrantAdminService.listCollections(_settings);
  }

  Future<Map<String, Object?>> loadQdrantCollectionInfo(String collection) {
    return _qdrantAdminService.collectionInfo(_settings, collection);
  }

  Future<Map<String, Object?>> scrollQdrantPoints({
    int limit = 20,
    Map<String, Object?>? filter,
  }) {
    return _qdrantAdminService.scroll(
      _settings,
      collection: _settings.effectiveCollectionName,
      limit: limit,
      filter: filter,
    );
  }

  Future<Map<String, Object?>> loadQdrantPointsByIds(List<String> ids) {
    return _qdrantAdminService.pointsByIds(
      _settings,
      collection: _settings.effectiveCollectionName,
      ids: ids,
    );
  }

  Future<Map<String, Object?>> searchQdrantRawVector({
    required List<double> vector,
    int limit = 10,
    Map<String, Object?>? filter,
  }) {
    return _qdrantAdminService.searchRawVector(
      _settings,
      collection: _settings.effectiveCollectionName,
      vector: vector,
      limit: limit,
      filter: filter,
    );
  }

  Future<KnowledgeVectorDistribution> loadVectorDistribution({
    int maxPoints = kKnowledgeVectorDistributionDefaultMaxPoints,
  }) async {
    final stopwatch = Stopwatch()..start();
    final vectorStore = QdrantKnowledgeVectorStore(settings: _settings);
    final safeMaxPoints = maxPoints.clamp(1, 2000).toInt();
    final samples = <KnowledgeVectorSamplePoint>[];
    Object? offset;
    var hasMore = false;
    while (samples.length < safeMaxPoints) {
      final limit = math.min(
        kKnowledgeVectorDistributionPageSize,
        safeMaxPoints - samples.length,
      );
      final page = await vectorStore.sample(
        collectionName: _settings.effectiveCollectionName,
        limit: limit,
        offset: offset,
      );
      samples.addAll(page.points);
      offset = page.nextPageOffset;
      hasMore = offset != null;
      if (page.points.isEmpty || offset == null) break;
    }
    final chunkIds = stringListFromValue(
      samples.map((point) => point.payload['chunk_id']).toList(growable: false),
    );
    final chunksById = await _store.loadChunksByIds(chunkIds);
    final sourcesById = await _store.loadSourcesByIds(
      chunksById.values.map((chunk) => chunk.sourceId),
    );
    final inputs = <KnowledgeVectorProjectionInput>[];
    for (final point in samples) {
      final chunkId = '${point.payload['chunk_id'] ?? ''}'.trim();
      final chunk = chunksById[chunkId];
      final source = chunk == null ? null : sourcesById[chunk.sourceId];
      final fallbackTitle =
          '${point.payload['source_title'] ?? point.payload['title'] ?? ''}'
              .trim();
      final fallbackPreview =
          '${point.payload['heading_path'] ?? point.payload['path'] ?? ''}'
              .trim();
      inputs.add(
        KnowledgeVectorProjectionInput(
          id: chunkId.isNotEmpty ? chunkId : point.id,
          kind: KnowledgeVectorPointKind.corpus,
          title: chunk?.title.isNotEmpty == true
              ? chunk!.title
              : source?.title ?? fallbackTitle,
          preview: chunk?.content ?? fallbackPreview,
          vector: point.vector,
        ),
      );
    }
    stopwatch.stop();
    return KnowledgeVectorProjector.project(
      inputs: inputs,
      originalDimensions: _settings.dimensions,
      hasMore: hasMore,
      durationMs: stopwatch.elapsedMilliseconds,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  Future<Map<String, Object?>> createDefaultQdrantPayloadIndexes() {
    return _qdrantAdminService.createDefaultPayloadIndexes(
      _settings,
      collection: _settings.effectiveCollectionName,
    );
  }

  Future<void> deleteQdrantPoints(List<String> ids) {
    return _qdrantAdminService.deletePoints(
      _settings,
      collection: _settings.effectiveCollectionName,
      ids: ids,
    );
  }

  Future<void> deleteQdrantCollection(String collection) {
    return _qdrantAdminService.deleteCollection(_settings, collection);
  }

  AiModelConfig? resolveEmbeddingModel(List<AiModelConfig> models) {
    for (final model in models) {
      if (model.id == _settings.providerConfigId) {
        final profile = model.profileFor(_settings.modelId);
        if (!profile.supportsEmbeddings) return null;
        return model.copyWith(modelId: _settings.modelId);
      }
    }
    return null;
  }

  AiModelConfig? resolveRerankModel(List<AiModelConfig> models) {
    if (!_settings.modelRerankEnabled || !_settings.hasRerankModel) {
      return null;
    }
    for (final model in models) {
      if (model.id == _settings.rerankProviderConfigId) {
        final profile = model.profileFor(_settings.rerankModelId);
        if (!profile.supportsRerank) return null;
        return model.copyWith(modelId: _settings.rerankModelId);
      }
    }
    return null;
  }

  List<AiModelConfig> embeddingCapableModels(List<AiModelConfig> models) {
    return models
        .where(
          (model) => model.allModelIds.any(
            (id) => model
                .profileFor(id)
                .capabilities
                .contains(AiModelCapability.embeddingGeneration),
          ),
        )
        .toList(growable: false);
  }

  List<AiModelConfig> rerankCapableModels(List<AiModelConfig> models) {
    return models
        .where(
          (model) => model.allModelIds.any(
            (id) => model.profileFor(id).supportsRerank,
          ),
        )
        .toList(growable: false);
  }

  List<AiModelConfig> readerCapableModels(List<AiModelConfig> models) {
    return models
        .where(
          (model) => model.allModelIds.any(
            (id) => model.profileFor(id).supportsReaderConversion,
          ),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _embeddingService.dispose();
    super.dispose();
  }
}

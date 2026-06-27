import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../app/support/openhand_paths.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../ai/index.dart';
import '../plugin_service/index.dart';
import 'data/knowledge_base_settings_store.dart';
import 'data/knowledge_base_store.dart';
import 'model/knowledge_base_settings.dart';
import 'model/knowledge_chunk.dart';
import 'model/knowledge_message_metadata.dart';
import 'model/knowledge_retrieval_result.dart';
import 'model/knowledge_source.dart';
import 'service/knowledge_dependency_service.dart';
import 'service/knowledge_embedding_service.dart';
import 'service/knowledge_indexing_control.dart';
import 'service/knowledge_ingestion_service.dart';
import 'service/knowledge_retrieval_service.dart';
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
  KnowledgeRetrievalResult? _lastRetrieval;

  KnowledgeBaseSettings get settings => _settings;
  List<KnowledgeSource> get sources => _sources;
  bool get loading => _loading;
  bool get busy => _busy;
  String get query => _query;
  String? get error => _error;
  KnowledgeRetrievalResult? get lastRetrieval => _lastRetrieval;
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
    _settings = settings;
    await _settingsStore.save(settings);
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
      final source = await ingestion.importFile(
        filePath: filePath,
        settings: _settings,
        embeddingModel: embeddingModel,
        tags: tags,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
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

  Future<List<KnowledgeChunk>> loadChunksForSource(String sourceId) {
    return _store.loadChunksForSource(sourceId);
  }

  Future<KnowledgeSource?> loadSource(String sourceId) {
    return _store.loadSource(sourceId);
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

  Future<Map<String, Object?>?> buildMessageAugmentation({
    required String query,
    required bool enabled,
    required AiModelConfig? embeddingModel,
  }) async {
    final normalized = query.trim();
    if (!enabled) {
      return KnowledgeMessageMetadata.skipped(
        enabled: false,
        reason: 'session_toggle_off',
        query: normalized,
      );
    }
    if (normalized.isEmpty) {
      return KnowledgeMessageMetadata.skipped(
        enabled: true,
        reason: 'empty_query',
        query: normalized,
      );
    }
    if (!_settings.hasEmbeddingModel) {
      return KnowledgeMessageMetadata.failed(
        query: normalized,
        error: '未配置知识库 embedding 模型。',
        settings: _settings,
      );
    }
    if (embeddingModel == null) {
      return KnowledgeMessageMetadata.failed(
        query: normalized,
        error: '找不到知识库配置中指定的 embedding 模型。',
        settings: _settings,
      );
    }
    final embeddingStopwatch = Stopwatch()..start();
    try {
      final vectorStore = QdrantKnowledgeVectorStore(settings: _settings);
      final retrieval = KnowledgeRetrievalService(
        store: _store,
        embeddingService: _embeddingService,
        vectorStore: vectorStore,
      );
      final result = await retrieval.retrieve(
        query: normalized,
        settings: _settings,
        embeddingModel: embeddingModel,
      );
      _lastRetrieval = result;
      embeddingStopwatch.stop();
      return KnowledgeMessageMetadata.success(
        settings: _settings,
        result: result,
        embeddingDurationMs: embeddingStopwatch.elapsedMilliseconds,
        promptAppendContent: result.promptAppend,
      );
    } catch (error) {
      embeddingStopwatch.stop();
      if (_settings.failureStrategy == 'fail_closed') {
        rethrow;
      }
      return KnowledgeMessageMetadata.failed(
        query: normalized,
        error: '$error',
        settings: _settings,
        embeddingDurationMs: embeddingStopwatch.elapsedMilliseconds,
      );
    } finally {
      notifyListeners();
    }
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

  @override
  void dispose() {
    _embeddingService.dispose();
    super.dispose();
  }
}

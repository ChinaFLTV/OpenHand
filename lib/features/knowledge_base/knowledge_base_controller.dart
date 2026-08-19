import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../app/support/openhand_paths.dart';
import '../../app/support/silent_log.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_normalization.dart';
import '../../shared/util/timer_safety.dart';
import '../ai/index.dart';
import '../plugin_service/index.dart';
import 'data/knowledge_base_settings_store.dart';
import 'data/knowledge_base_store.dart';
import 'knowledge_base_errors.dart';
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
import 'service/knowledge_source_storage.dart';
import 'service/knowledge_vector_store.dart';
import 'service/qdrant_admin_service.dart';
import 'service/qdrant_knowledge_vector_store.dart';
import 'service/qdrant_monitoring_service.dart';

const Duration _knowledgeSourceSearchDelay = Duration(milliseconds: 180);
const Duration _knowledgeControllerShutdownTimeout = Duration(seconds: 3);
const int _knowledgeNoteFileStemMaxCharacters = 64;
const String _knowledgeMutationUnavailableMessage = '知识库正在加载或执行其他操作，请稍后重试。';

String _reportKnowledgeBaseFailure(
  String action,
  Object error,
  StackTrace stack, {
  String? fallback,
}) {
  silentLog('knowledge_base_controller', action, error, stack);
  return knowledgeBaseFailureMessage(
    error,
    fallback: fallback ?? '$action失败，请稍后重试。',
  );
}

class KnowledgeBaseController extends ChangeNotifier {
  KnowledgeBaseController({
    KnowledgeBaseSettingsStore? settingsStore,
    KnowledgeBaseStore? store,
    KnowledgeEmbeddingService? embeddingService,
    KnowledgeEmbeddingService Function()? queryEmbeddingServiceFactory,
    KnowledgeDependencyService dependencyService =
        const KnowledgeDependencyService(),
  }) : _settingsStore = settingsStore ?? KnowledgeBaseSettingsStore(),
       _store = store ?? KnowledgeBaseStore(),
       _embeddingService = embeddingService ?? KnowledgeEmbeddingService(),
       _queryEmbeddingServiceFactory =
           queryEmbeddingServiceFactory ?? KnowledgeEmbeddingService.new,
       _dependencyService = dependencyService;

  final KnowledgeBaseSettingsStore _settingsStore;
  final KnowledgeBaseStore _store;
  final KnowledgeEmbeddingService _embeddingService;
  final KnowledgeEmbeddingService Function() _queryEmbeddingServiceFactory;
  final KnowledgeDependencyService _dependencyService;
  final QdrantAdminService _qdrantAdminService = QdrantAdminService();
  final OpenHandDebouncer _sourceSearchDebouncer = OpenHandDebouncer(
    delay: _knowledgeSourceSearchDelay,
  );

  KnowledgeBaseSettings _settings = const KnowledgeBaseSettings();
  List<KnowledgeSource> _sources = const <KnowledgeSource>[];
  bool _loading = true;
  bool _busy = false;
  String _query = '';
  String? _error;
  bool _hasTrustedSettings = false;
  bool _isDisposed = false;
  bool _isShuttingDown = false;
  int _sourceLoadGeneration = 0;
  Future<void>? _activeMutation;
  Future<void>? _shutdownFuture;
  KnowledgeIndexingCancelToken? _activeIndexingCancelToken;
  final OpenHandSingleFlight<void> _initializeFlight =
      OpenHandSingleFlight<void>();

  bool get _isStopping => _isDisposed || _isShuttingDown;

  KnowledgeBaseSettings get settings => _settings;
  List<KnowledgeSource> get sources => _sources;
  bool get loading => _loading;
  bool get busy => _busy;
  String get query => _query;
  String? get error => _error;
  List<QdrantAdminOperationLog> get qdrantAdminLogs => _qdrantAdminService.logs;

  void clearError() {
    if (_error == null || _isStopping) return;
    _error = null;
    notifyListeners();
  }

  Future<void> initialize() {
    if (_initializeFlight.isRunning) return _initializeFlight.run(_initialize);
    if (_busy || _isStopping) return Future<void>.value();
    return _initializeFlight.run(_initialize);
  }

  Future<void> _initialize() async {
    _loading = true;
    notifyListeners();
    try {
      final settings = await _settingsStore.load();
      if (_isStopping) return;
      _settings = settings;
      _hasTrustedSettings = true;
      _error = null;
    } catch (error, stack) {
      if (_isStopping) return;
      _hasTrustedSettings = false;
      _error = _reportKnowledgeBaseFailure(
        '读取知识库配置',
        error,
        stack,
        fallback: '读取知识库配置失败，已保留现有数据。',
      );
    }
    try {
      await _reloadSources();
      if (_isStopping) return;
      schedulePendingKnowledgeSourceFileCleanups(
        sourceExists: (sourceId) async =>
            await _store.loadSource(sourceId) != null,
      );
    } catch (error, stack) {
      if (!_isStopping) {
        final failure = _reportKnowledgeBaseFailure('加载知识源', error, stack);
        _error ??= failure;
      }
    } finally {
      if (!_isDisposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  KnowledgeDependencySnapshot dependencies(PluginServiceController controller) {
    return _dependencyService.snapshot(controller);
  }

  Future<void> updateSettings(KnowledgeBaseSettings settings) async {
    if (!_hasTrustedSettings) {
      throw StateError('知识库配置不可用，已保留现有数据。');
    }
    await _runExclusiveMutation<void>(
      unavailableResult: null,
      unavailableMessage: _knowledgeMutationUnavailableMessage,
      operation: () async {
        await _settingsStore.save(settings);
        if (_isDisposed) return;
        _settings = settings;
        _qdrantAdminService.trimLogs(settings.qdrantLogRetainLines);
      },
    );
  }

  void searchSources(String query) {
    if (_isStopping) return;
    _query = query;
    final generation = ++_sourceLoadGeneration;
    _sourceSearchDebouncer.schedule(() async {
      try {
        final sources = await _store.loadSources(query: query);
        if (_isStopping || generation != _sourceLoadGeneration) return;
        _sources = List<KnowledgeSource>.unmodifiable(sources);
        notifyListeners();
      } catch (error, stack) {
        if (_isStopping || generation != _sourceLoadGeneration) return;
        _error = _reportKnowledgeBaseFailure('搜索知识源', error, stack);
        notifyListeners();
      }
    });
  }

  Future<KnowledgeSource?> importFile({
    required String filePath,
    required AiModelConfig embeddingModel,
    List<AiModelConfig> readerModels = const <AiModelConfig>[],
    List<String> tags = const <String>[],
    KnowledgeIndexingCancelToken? cancelToken,
    KnowledgeIndexingProgressCallback? onProgress,
  }) {
    final effectiveCancelToken = cancelToken ?? KnowledgeIndexingCancelToken();
    return _runExclusiveMutation<KnowledgeSource?>(
      unavailableResult: null,
      cancelToken: effectiveCancelToken,
      operation: () => _importFile(
        filePath: filePath,
        embeddingModel: embeddingModel,
        readerModels: readerModels,
        tags: tags,
        cancelToken: effectiveCancelToken,
        onProgress: onProgress,
      ),
    );
  }

  Future<KnowledgeSource?> _importFile({
    required String filePath,
    required AiModelConfig embeddingModel,
    required List<AiModelConfig> readerModels,
    required List<String> tags,
    required KnowledgeIndexingCancelToken? cancelToken,
    required KnowledgeIndexingProgressCallback? onProgress,
  }) async {
    try {
      final settings = _settings;
      final vectorStore = QdrantKnowledgeVectorStore(settings: settings);
      final ingestion = KnowledgeIngestionService(
        store: _store,
        embeddingService: _embeddingService,
        vectorStore: vectorStore,
      );
      final KnowledgeSource source;
      try {
        source = await ingestion.importFile(
          filePath: filePath,
          settings: settings,
          embeddingModel: embeddingModel,
          readerModels: readerModels,
          tags: tags,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
      } finally {
        ingestion.dispose();
      }
      await _reloadSources();
      return source;
    } on KnowledgeIndexingCancelledException {
      if (!_isStopping) _error = null;
      await _reloadSources();
      return null;
    } catch (error, stack) {
      if (!_isStopping) {
        _error = _reportKnowledgeBaseFailure(
          '导入知识源',
          error,
          stack,
          fallback: '导入知识源失败，请检查文件、模型与向量服务配置。',
        );
      }
      return null;
    }
  }

  Future<KnowledgeSource?> importNote({
    required String title,
    required String content,
    required AiModelConfig embeddingModel,
    List<String> tags = const <String>[],
    KnowledgeIndexingCancelToken? cancelToken,
    KnowledgeIndexingProgressCallback? onProgress,
  }) {
    final effectiveCancelToken = cancelToken ?? KnowledgeIndexingCancelToken();
    return _runExclusiveMutation<KnowledgeSource?>(
      unavailableResult: null,
      cancelToken: effectiveCancelToken,
      operation: () => _importNote(
        title: title,
        content: content,
        embeddingModel: embeddingModel,
        tags: tags,
        cancelToken: effectiveCancelToken,
        onProgress: onProgress,
      ),
    );
  }

  Future<KnowledgeSource?> _importNote({
    required String title,
    required String content,
    required AiModelConfig embeddingModel,
    required List<String> tags,
    required KnowledgeIndexingCancelToken? cancelToken,
    required KnowledgeIndexingProgressCallback? onProgress,
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
    final safeTitle = collapseRepeatedUnderscores(
      normalizedTitle.replaceAll(RegExp(r'[^a-zA-Z0-9\u4e00-\u9fa5._-]+'), '_'),
    ).trim();
    final fileStem = safeTitle.isEmpty
        ? 'note'
        : safeTitle.length <= _knowledgeNoteFileStemMaxCharacters
        ? safeTitle
        : safeTitle.substring(0, _knowledgeNoteFileStemMaxCharacters);
    final file = File(
      p.join(
        notesDir.path,
        '${fileStem}_${DateTime.now().microsecondsSinceEpoch}.md',
      ),
    );
    await writeFileAtomically(
      file,
      '# $normalizedTitle\n\n$normalizedContent\n',
    );
    cancelToken?.throwIfCancelled();
    return _importFile(
      filePath: file.path,
      embeddingModel: embeddingModel,
      readerModels: const <AiModelConfig>[],
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
    Future<void>? cancelSignal,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || _isStopping) return null;
    final settings = _settings;
    final embeddingModel = resolveEmbeddingModel(models, settings: settings);
    if (embeddingModel == null) return null;
    final rerankModel = resolveRerankModel(models, settings: settings);
    final effectiveTopK = topK.clamp(1, 20).toInt();
    final retrievalSettings = settings.copyWith(
      topK: effectiveTopK,
      maxPromptChunks: math.max(effectiveTopK, settings.maxPromptChunks),
      topN: math.max(settings.topN, effectiveTopK),
    );
    final vectorStore = QdrantKnowledgeVectorStore(settings: retrievalSettings);
    final available = await vectorStore.isAvailable(cancelSignal: cancelSignal);
    if (!available || _isStopping) return null;
    final queryEmbeddingService = _queryEmbeddingServiceFactory();
    final retrievalService = KnowledgeRetrievalService(
      store: _store,
      embeddingService: queryEmbeddingService,
      vectorStore: vectorStore,
    );
    try {
      final result = await retrievalService.retrieve(
        query: normalizedQuery,
        settings: retrievalSettings,
        embeddingModel: embeddingModel,
        rerankModel: rerankModel,
        cancelSignal: cancelSignal,
      );
      return (settings: retrievalSettings, result: result);
    } finally {
      retrievalService.dispose();
      queryEmbeddingService.dispose();
    }
  }

  Future<List<KnowledgeChunk>> _restoreMissingChunksForSource(
    KnowledgeSource source,
  ) async {
    try {
      final settings = _settings;
      final file = await _resolveReadableSourceFile(source);
      if (file == null) {
        return const <KnowledgeChunk>[];
      }
      final stat = await file.stat().timeout(defaultBoundedFileReadIdleTimeout);
      if (!isRegularFileStat(stat)) return const <KnowledgeChunk>[];
      final tags = _sourceTags(source);
      final parsed = await const KnowledgeDocumentParserRegistry().parse(
        KnowledgeDocumentParseRequest(
          file: file,
          settings: settings,
          stat: stat,
          tags: tags,
        ),
      );
      final chunks = const KnowledgeChunker().chunk(
        source: source,
        text: parsed.text,
        settings: settings,
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
      if (await isRegularFilePath(normalized, followLinks: true)) {
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

  Future<bool> deleteSource(KnowledgeSource source) {
    return _runExclusiveMutation<bool>(
      unavailableResult: false,
      operation: () => _deleteSource(source),
    );
  }

  Future<bool> _deleteSource(KnowledgeSource source) async {
    var sourceDeleted = false;
    try {
      final settings = _settings;
      await stageManagedKnowledgeSourceFileCleanup(source);
      final vectorStore = QdrantKnowledgeVectorStore(settings: settings);
      await vectorStore.deleteBySource(
        collectionName: settings.effectiveCollectionName,
        sourceId: source.id,
      );
      await _store.deleteSource(source.id);
      sourceDeleted = true;
      try {
        await completeManagedKnowledgeSourceFileCleanup(source);
      } catch (error, stack) {
        silentLog('knowledge_base_controller', '删除托管源文件', error, stack);
      }
      await _reloadSources();
      return true;
    } catch (error, stack) {
      if (!sourceDeleted) {
        try {
          if (await _store.loadSource(source.id) != null) {
            await cancelManagedKnowledgeSourceFileCleanup(source);
          }
        } catch (cleanupError, cleanupStack) {
          silentLog(
            'knowledge_base_controller',
            '取消托管源文件清理',
            cleanupError,
            cleanupStack,
          );
        }
      }
      if (!_isStopping) {
        _error = _reportKnowledgeBaseFailure('删除知识源', error, stack);
      } else {
        silentLog('knowledge_base_controller', '删除知识源', error, stack);
      }
      return false;
    }
  }

  Future<T> _runExclusiveMutation<T>({
    required T unavailableResult,
    required Future<T> Function() operation,
    String? unavailableMessage,
    KnowledgeIndexingCancelToken? cancelToken,
  }) {
    if (_loading || _initializeFlight.isRunning || _busy || _isStopping) {
      if (unavailableMessage != null) {
        return Future<T>.error(StateError(unavailableMessage));
      }
      return Future<T>.value(unavailableResult);
    }
    final mutation = _executeExclusiveMutation(operation, cancelToken);
    _activeMutation = mutation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return mutation;
  }

  Future<T> _executeExclusiveMutation<T>(
    Future<T> Function() operation,
    KnowledgeIndexingCancelToken? cancelToken,
  ) async {
    _busy = true;
    _activeIndexingCancelToken = cancelToken;
    _error = null;
    notifyListeners();
    try {
      return await operation();
    } finally {
      if (identical(_activeIndexingCancelToken, cancelToken)) {
        _activeIndexingCancelToken = null;
      }
      if (!_isDisposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _reloadSources() async {
    _sourceSearchDebouncer.cancel();
    final generation = ++_sourceLoadGeneration;
    final sources = await _store.loadSources(query: _query);
    if (_isStopping || generation != _sourceLoadGeneration) return;
    _sources = List<KnowledgeSource>.unmodifiable(sources);
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
    final settings = _settings;
    final vectorStore = QdrantKnowledgeVectorStore(settings: settings);
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
        collectionName: settings.effectiveCollectionName,
        limit: limit,
        offset: offset,
      );
      final acceptedPoints = page.points.take(limit).toList(growable: false);
      samples.addAll(acceptedPoints);
      final nextOffset = page.nextPageOffset;
      final paginationStalled = nextOffset != null && nextOffset == offset;
      offset = nextOffset;
      hasMore =
          nextOffset != null || page.points.length > acceptedPoints.length;
      if (acceptedPoints.isEmpty || nextOffset == null || paginationStalled) {
        break;
      }
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
      originalDimensions: settings.dimensions,
      hasMore: hasMore,
      durationMs: stopwatch.elapsedMilliseconds,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  Future<Map<String, Object?>> createDefaultQdrantPayloadIndexes() {
    final settings = _settings;
    return _runExclusiveMutation<Map<String, Object?>>(
      unavailableResult: const <String, Object?>{},
      unavailableMessage: _knowledgeMutationUnavailableMessage,
      operation: () => _qdrantAdminService.createDefaultPayloadIndexes(
        settings,
        collection: settings.effectiveCollectionName,
      ),
    );
  }

  Future<void> deleteQdrantPoints(List<String> ids) {
    final settings = _settings;
    return _runExclusiveMutation<void>(
      unavailableResult: null,
      unavailableMessage: _knowledgeMutationUnavailableMessage,
      operation: () => _qdrantAdminService.deletePoints(
        settings,
        collection: settings.effectiveCollectionName,
        ids: ids,
      ),
    );
  }

  Future<void> deleteQdrantCollection(String collection) {
    final settings = _settings;
    return _runExclusiveMutation<void>(
      unavailableResult: null,
      unavailableMessage: _knowledgeMutationUnavailableMessage,
      operation: () =>
          _qdrantAdminService.deleteCollection(settings, collection),
    );
  }

  AiModelConfig? resolveEmbeddingModel(
    List<AiModelConfig> models, {
    KnowledgeBaseSettings? settings,
  }) {
    final current = settings ?? _settings;
    for (final model in models) {
      if (model.id == current.providerConfigId) {
        final profile = model.profileFor(current.modelId);
        if (!profile.supportsEmbeddings) return null;
        return model.copyWith(modelId: current.modelId);
      }
    }
    return null;
  }

  AiModelConfig? resolveRerankModel(
    List<AiModelConfig> models, {
    KnowledgeBaseSettings? settings,
  }) {
    final current = settings ?? _settings;
    if (!current.modelRerankEnabled || !current.hasRerankModel) {
      return null;
    }
    for (final model in models) {
      if (model.id == current.rerankProviderConfigId) {
        final profile = model.profileFor(current.rerankModelId);
        if (!profile.supportsRerank) return null;
        return model.copyWith(modelId: current.rerankModelId);
      }
    }
    return null;
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isShuttingDown = true;
    _isDisposed = true;
    _sourceLoadGeneration++;
    _activeIndexingCancelToken?.cancel();
    _activeIndexingCancelToken = null;
    _sourceSearchDebouncer.dispose();
    _embeddingService.dispose();
    super.dispose();
  }

  /// 取消活动索引并有界等待初始化和变更结束，可重复调用。
  Future<void> shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    _isShuttingDown = true;
    _sourceLoadGeneration++;
    _sourceSearchDebouncer.cancel();
    _activeIndexingCancelToken?.cancel();
    final mutation = _activeMutation ?? Future<void>.value();
    final shutdown = () async {
      await runAsyncCleanupBounded(
        () =>
            Future.wait<void>(<Future<void>>[_initializeFlight.idle, mutation]),
        timeout: _knowledgeControllerShutdownTimeout,
        onError: (error, stack) =>
            silentLog('knowledge_base_controller', '等待知识库操作结束', error, stack),
      );
      await runAsyncCleanupBounded(
        flushPendingKnowledgeSourceFileCleanups,
        timeout: _knowledgeControllerShutdownTimeout,
        onError: (error, stack) =>
            silentLog('knowledge_base_controller', '等待知识源清理结束', error, stack),
      );
      dispose();
    }();
    _shutdownFuture = shutdown;
    return shutdown;
  }
}

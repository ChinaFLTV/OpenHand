import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/knowledge_base/data/knowledge_base_store.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_chunk.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_source.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_embedding_service.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_retrieval_service.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late KnowledgeBaseStore store;
  late _FakeVectorStore vectorStore;
  late KnowledgeEmbeddingService embeddingService;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE knowledge_sources (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL DEFAULT '',
              kind TEXT NOT NULL DEFAULT 'note',
              original_path TEXT NOT NULL DEFAULT '',
              stored_path TEXT NOT NULL DEFAULT '',
              mime_type TEXT NOT NULL DEFAULT '',
              size_bytes INTEGER NOT NULL DEFAULT 0,
              content_hash TEXT NOT NULL DEFAULT '',
              status TEXT NOT NULL DEFAULT 'pending',
              error_message TEXT NOT NULL DEFAULT '',
              document_time TEXT,
              imported_at TEXT NOT NULL,
              indexed_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              metadata_json TEXT NOT NULL DEFAULT '{}'
            )
          ''');
          await database.execute('''
            CREATE TABLE knowledge_chunks (
              id TEXT PRIMARY KEY,
              source_id TEXT NOT NULL,
              chunk_index INTEGER NOT NULL DEFAULT 0,
              parent_chunk_id TEXT,
              title TEXT NOT NULL DEFAULT '',
              heading_path TEXT NOT NULL DEFAULT '',
              content TEXT NOT NULL DEFAULT '',
              content_hash TEXT NOT NULL DEFAULT '',
              char_count INTEGER NOT NULL DEFAULT 0,
              token_estimate INTEGER NOT NULL DEFAULT 0,
              start_offset INTEGER,
              end_offset INTEGER,
              page_number INTEGER,
              document_time TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              metadata_json TEXT NOT NULL DEFAULT '{}',
              FOREIGN KEY (source_id) REFERENCES knowledge_sources(id) ON DELETE CASCADE
            )
          ''');
          await database.execute('''
            CREATE TABLE knowledge_embedding_jobs (
              id TEXT PRIMARY KEY,
              chunk_id TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              FOREIGN KEY (chunk_id) REFERENCES knowledge_chunks(id) ON DELETE CASCADE
            )
          ''');
        },
        version: 1,
      ),
    );
    store = KnowledgeBaseStore(database: db);
    vectorStore = _FakeVectorStore();
    embeddingService = KnowledgeEmbeddingService(
      embeddings: _FakeEmbeddingsService(),
    );
    await _seedStore(store);
  });

  tearDown(() async {
    embeddingService.dispose();
    await db.close();
  });

  test('model rerank mode requests rerank model after vector recall', () async {
    final rerankService = _RecordingRerankService(
      items: const <AiRerankItem>[
        AiRerankItem(index: 1, score: 0.99),
        AiRerankItem(index: 0, score: 0.31),
      ],
    );
    final service = KnowledgeRetrievalService(
      store: store,
      embeddingService: embeddingService,
      vectorStore: vectorStore,
      rerankService: rerankService,
    );

    final result = await service.retrieve(
      query: 'query',
      settings: _settings(skipDualCapabilityRerank: false),
      embeddingModel: _embeddingModel(supportsRerank: true),
      rerankModel: _rerankModel(),
    );

    expect(rerankService.callCount, 1);
    expect(rerankService.documents, hasLength(2));
    expect(result.hits.first.chunk.id, 'source-1_chunk_1');
    expect(result.hits.first.rerankScore, 0.99);
    service.dispose();
  });

  test(
    'dual-capability skip keeps vector order and avoids rerank request',
    () async {
      final rerankService = _RecordingRerankService(
        items: const <AiRerankItem>[AiRerankItem(index: 1, score: 0.99)],
      );
      final service = KnowledgeRetrievalService(
        store: store,
        embeddingService: embeddingService,
        vectorStore: vectorStore,
        rerankService: rerankService,
      );

      final result = await service.retrieve(
        query: 'query',
        settings: _settings(skipDualCapabilityRerank: true),
        embeddingModel: _embeddingModel(supportsRerank: true),
        rerankModel: _rerankModel(),
      );

      expect(rerankService.callCount, 0);
      expect(result.hits.first.chunk.id, 'source-1_chunk_0');
      expect(result.hits.first.rerankScore, isNull);
      service.dispose();
    },
  );

  test(
    'dual-capability skip still reranks when embedding model lacks rerank',
    () async {
      final rerankService = _RecordingRerankService(
        items: const <AiRerankItem>[AiRerankItem(index: 1, score: 0.99)],
      );
      final service = KnowledgeRetrievalService(
        store: store,
        embeddingService: embeddingService,
        vectorStore: vectorStore,
        rerankService: rerankService,
      );

      final result = await service.retrieve(
        query: 'query',
        settings: _settings(skipDualCapabilityRerank: true),
        embeddingModel: _embeddingModel(supportsRerank: false),
        rerankModel: _rerankModel(),
      );

      expect(rerankService.callCount, 1);
      expect(result.hits.first.chunk.id, 'source-1_chunk_1');
      expect(result.hits.first.rerankScore, 0.99);
      service.dispose();
    },
  );
}

KnowledgeBaseSettings _settings({required bool skipDualCapabilityRerank}) {
  return KnowledgeBaseSettings(
    providerConfigId: 'embedding-provider',
    modelId: 'dual-embedding',
    dimensions: 2,
    allowQueryCloudEmbedding: true,
    rerankMode: KnowledgeRerankMode.model,
    rerankProviderConfigId: 'rerank-provider',
    rerankModelId: 'reranker',
    skipModelRerankWhenEmbeddingSupportsRerank: skipDualCapabilityRerank,
    topN: 4,
    topK: 2,
    minSimilarity: 0,
    sourceCap: 2,
    maxChunksPerSource: 2,
  );
}

AiModelConfig _embeddingModel({required bool supportsRerank}) {
  return AiModelConfig(
    id: 'embedding-provider',
    baseUrl: 'https://example.test/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'token',
    modelId: 'dual-embedding',
    protocolType: AiProtocolType.openai,
    modelProfiles: <String, AiModelProfile>{
      'dual-embedding': AiModelProfile(
        capabilities: <AiModelCapability>{
          AiModelCapability.embeddingGeneration,
          if (supportsRerank) AiModelCapability.rerank,
        },
        embeddingDimensions: 2,
      ),
    },
  );
}

AiModelConfig _rerankModel() {
  return const AiModelConfig(
    id: 'rerank-provider',
    baseUrl: 'https://example.test/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'token',
    modelId: 'reranker',
    protocolType: AiProtocolType.openai,
    modelProfiles: <String, AiModelProfile>{
      'reranker': AiModelProfile(
        capabilities: <AiModelCapability>{AiModelCapability.rerank},
      ),
    },
  );
}

Future<void> _seedStore(KnowledgeBaseStore store) async {
  final now = DateTime.utc(2026, 6, 28);
  final source = KnowledgeSource(
    id: 'source-1',
    title: 'Doc',
    kind: 'markdown',
    originalPath: '/tmp/doc.md',
    storedPath: '/tmp/doc.md',
    mimeType: 'text/markdown',
    sizeBytes: 42,
    contentHash: 'source-hash',
    status: 'indexed',
    errorMessage: '',
    importedAt: now,
    createdAt: now,
    updatedAt: now,
  );
  await store.upsertSource(source);
  await store.replaceChunks(
    sourceId: source.id,
    chunks: <KnowledgeChunk>[
      _chunk(source.id, 0, 'Alpha content', now),
      _chunk(source.id, 1, 'Beta content', now),
    ],
  );
}

KnowledgeChunk _chunk(
  String sourceId,
  int index,
  String content,
  DateTime now,
) {
  return KnowledgeChunk(
    id: '${sourceId}_chunk_$index',
    sourceId: sourceId,
    chunkIndex: index,
    title: 'Doc',
    headingPath: 'Doc',
    content: content,
    contentHash: 'chunk-$index',
    charCount: content.length,
    tokenEstimate: 4,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeEmbeddingsService extends AiEmbeddingsService {
  @override
  Future<AiEmbeddingResult> createEmbeddings({
    required AiModelConfig model,
    required List<String> input,
    Duration timeout = const Duration(seconds: 60),
    int? dimensions,
    String? encodingFormat,
    String? inputType,
    String? taskType,
    String? title,
    String? outputDType,
    String? truncation,
    String? user,
  }) async {
    return AiEmbeddingResult(
      vectors: List<List<double>>.generate(
        input.length,
        (_) => <double>[0.1, 0.2],
        growable: false,
      ),
      rawResponse: '{}',
    );
  }

  @override
  void dispose() {}
}

class _FakeVectorStore implements KnowledgeVectorStore {
  @override
  Future<void> ensureCollection({
    required String collectionName,
    required int dimensions,
    required String distance,
    Future<void>? cancelSignal,
  }) async {}

  @override
  Future<void> upsert({
    required String collectionName,
    required List<KnowledgeVectorPoint> points,
    Future<void>? cancelSignal,
  }) async {}

  @override
  Future<List<KnowledgeVectorSearchHit>> search({
    required String collectionName,
    required List<double> vector,
    required int limit,
    double? scoreThreshold,
    Map<String, Object?>? filter,
    bool includeVector = false,
  }) async {
    return const <KnowledgeVectorSearchHit>[
      KnowledgeVectorSearchHit(
        id: 'source-1_chunk_0',
        score: 0.9,
        vector: <double>[0.9, 0.1],
        payload: <String, Object?>{'chunk_id': 'source-1_chunk_0'},
      ),
      KnowledgeVectorSearchHit(
        id: 'source-1_chunk_1',
        score: 0.8,
        vector: <double>[0.8, 0.2],
        payload: <String, Object?>{'chunk_id': 'source-1_chunk_1'},
      ),
    ];
  }

  @override
  Future<KnowledgeVectorSamplePage> sample({
    required String collectionName,
    required int limit,
    Object? offset,
    Map<String, Object?>? filter,
  }) async {
    return const KnowledgeVectorSamplePage(
      points: <KnowledgeVectorSamplePoint>[],
    );
  }

  @override
  Future<void> deleteBySource({
    required String collectionName,
    required String sourceId,
  }) async {}
}

class _RecordingRerankService extends AiRerankService {
  _RecordingRerankService({required this.items});

  final List<AiRerankItem> items;
  int callCount = 0;
  List<Object> documents = const <Object>[];

  @override
  Future<AiRerankResult> rerank({
    required AiModelConfig model,
    required String query,
    required List<Object> documents,
    Duration timeout = const Duration(seconds: 60),
    int? topN,
    bool? returnDocuments,
    int? maxChunksPerDoc,
    int? maxTokensPerDoc,
    int? priority,
    String? instruction,
    bool? truncation,
  }) async {
    callCount += 1;
    this.documents = documents;
    return AiRerankResult(items: items, rawResponse: '{}');
  }

  @override
  void dispose() {}
}

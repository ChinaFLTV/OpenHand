import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/stable_hash.dart';
import '../../ai/index.dart';
import '../data/knowledge_base_store.dart';
import '../model/knowledge_base_settings.dart';
import '../model/knowledge_source.dart';
import 'knowledge_chunker.dart';
import 'knowledge_document_parser.dart';
import 'knowledge_embedding_service.dart';
import 'knowledge_vector_store.dart';

class KnowledgeIngestionService {
  KnowledgeIngestionService({
    required KnowledgeBaseStore store,
    required KnowledgeEmbeddingService embeddingService,
    required KnowledgeVectorStore vectorStore,
    KnowledgeChunker chunker = const KnowledgeChunker(),
    KnowledgeDocumentParserRegistry parserRegistry =
        const KnowledgeDocumentParserRegistry(),
  }) : _store = store,
       _embeddingService = embeddingService,
       _vectorStore = vectorStore,
       _chunker = chunker,
       _parserRegistry = parserRegistry;

  final KnowledgeBaseStore _store;
  final KnowledgeEmbeddingService _embeddingService;
  final KnowledgeVectorStore _vectorStore;
  final KnowledgeChunker _chunker;
  final KnowledgeDocumentParserRegistry _parserRegistry;
  final Uuid _uuid = const Uuid();

  Future<KnowledgeSource> importFile({
    required String filePath,
    required KnowledgeBaseSettings settings,
    required AiModelConfig embeddingModel,
    List<String> tags = const <String>[],
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', filePath);
    }
    final stat = await file.stat();
    final maxBytes = settings.maxFileSizeMb * 1024 * 1024;
    if (stat.size > maxBytes) {
      throw StateError('文件超过知识库最大单文件大小 ${settings.maxFileSizeMb}MB。');
    }
    final parsed = await _parserRegistry.parse(
      KnowledgeDocumentParseRequest(
        file: file,
        settings: settings,
        stat: stat,
        tags: tags,
      ),
    );
    final now = DateTime.now().toUtc();
    final sourceId = _uuid.v4();
    final storedPath = settings.copyImportedFiles
        ? await _copyToKnowledgeStorage(file, sourceId)
        : file.path;
    final title = parsed.title?.trim().isNotEmpty == true
        ? parsed.title!.trim()
        : p.basename(file.path);
    var source = KnowledgeSource(
      id: sourceId,
      title: title,
      kind: parsed.kind,
      originalPath: file.path,
      storedPath: storedPath,
      mimeType: parsed.mimeType,
      sizeBytes: stat.size,
      contentHash: stableFnv1a32Hex(parsed.text),
      status: 'indexing',
      errorMessage: '',
      documentTime: stat.modified.toUtc(),
      importedAt: now,
      createdAt: now,
      updatedAt: now,
      metadata: <String, Object?>{
        'tags': tags,
        'copied_to_openhand_storage': settings.copyImportedFiles,
        'parser_id': parsed.parserId,
        'parsed_text_char_count': parsed.text.length,
        'parsed_text_hash': stableFnv1a32Hex(parsed.text),
        ...parsed.metadata,
      },
    );
    await _store.upsertSource(source);
    try {
      final chunks = _chunker.chunk(
        source: source,
        text: parsed.text,
        settings: settings,
        tags: tags,
      );
      if (chunks.isEmpty) {
        throw StateError('文档解析后没有可索引内容。');
      }
      await _store.replaceChunks(sourceId: source.id, chunks: chunks);
      await _vectorStore.ensureCollection(
        collectionName: settings.effectiveCollectionName,
        dimensions: settings.dimensions,
        distance: settings.distanceMetric,
      );
      for (var start = 0; start < chunks.length; start += settings.batchSize) {
        final end = (start + settings.batchSize).clamp(0, chunks.length);
        final batch = chunks.sublist(start, end);
        final vectors = await _embeddingService.embedBatch(
          settings: settings,
          model: embeddingModel,
          inputs: batch
              .map(
                (chunk) => chunk.embeddingInput(
                  sourceTitle: source.title,
                  path: source.originalPath,
                ),
              )
              .toList(growable: false),
          isQuery: false,
        );
        await _vectorStore.upsert(
          collectionName: settings.effectiveCollectionName,
          points: <KnowledgeVectorPoint>[
            for (var i = 0; i < batch.length; i++)
              KnowledgeVectorPoint(
                id: batch[i].id,
                vector: vectors[i],
                payload: batch[i].toPayload(
                  sourceTitle: source.title,
                  sourceKind: source.kind,
                  path: source.originalPath,
                ),
              ),
          ],
        );
      }
      source = source.copyWith(
        status: 'indexed',
        indexedAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _store.upsertSource(source);
      return source;
    } catch (error) {
      await _discardPartialIndex(
        sourceId: source.id,
        collectionName: settings.effectiveCollectionName,
      );
      source = source.copyWith(
        status: 'failed',
        errorMessage: '$error',
        updatedAt: DateTime.now().toUtc(),
      );
      await _store.upsertSource(source);
      rethrow;
    }
  }

  Future<void> _discardPartialIndex({
    required String sourceId,
    required String collectionName,
  }) async {
    try {
      await _vectorStore.deleteBySource(
        collectionName: collectionName,
        sourceId: sourceId,
      );
    } catch (_) {
      // Preserve the original ingestion failure.
    }
    try {
      await _store.replaceChunks(sourceId: sourceId, chunks: const []);
    } catch (_) {
      // Preserve the original ingestion failure.
    }
  }

  Future<String> _copyToKnowledgeStorage(File file, String sourceId) async {
    final root = Directory(
      '${OpenHandPaths.homeDirectoryPath()}/.openhand/knowledge/sources',
    );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final ext = p.extension(file.path);
    final target = File(p.join(root.path, '$sourceId$ext'));
    await writeFileBytesAtomically(target, await file.readAsBytes());
    return target.path;
  }
}

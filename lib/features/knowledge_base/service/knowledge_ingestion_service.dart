import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/reader_file_type.dart';
import '../../../shared/util/stable_hash.dart';
import '../../../shared/util/timer_safety.dart';
import '../../ai/index.dart';
import '../data/knowledge_base_store.dart';
import '../knowledge_base_errors.dart';
import '../model/knowledge_base_settings.dart';
import '../model/knowledge_source.dart';
import 'knowledge_chunker.dart';
import 'knowledge_document_parser.dart';
import 'knowledge_embedding_service.dart';
import 'knowledge_indexing_control.dart';
import 'knowledge_reader_conversion_service.dart';
import 'knowledge_source_storage.dart';
import 'knowledge_vector_store.dart';

const int kKnowledgeTagMaxCount = 64;
const int kKnowledgeTagMaxCharacters = 128;

class KnowledgeIngestionService {
  KnowledgeIngestionService({
    required KnowledgeBaseStore store,
    required KnowledgeEmbeddingService embeddingService,
    required KnowledgeVectorStore vectorStore,
    KnowledgeChunker chunker = const KnowledgeChunker(),
    KnowledgeDocumentParserRegistry parserRegistry =
        const KnowledgeDocumentParserRegistry(),
    KnowledgeReaderConversionService? readerConversionService,
  }) : _store = store,
       _embeddingService = embeddingService,
       _vectorStore = vectorStore,
       _chunker = chunker,
       _parserRegistry = parserRegistry,
       _readerConversionService =
           readerConversionService ?? KnowledgeReaderConversionService(),
       _ownsReaderConversionService = readerConversionService == null;

  final KnowledgeBaseStore _store;
  final KnowledgeEmbeddingService _embeddingService;
  final KnowledgeVectorStore _vectorStore;
  final KnowledgeChunker _chunker;
  final KnowledgeDocumentParserRegistry _parserRegistry;
  final KnowledgeReaderConversionService _readerConversionService;
  final bool _ownsReaderConversionService;
  final Uuid _uuid = const Uuid();
  static const Duration _readerFileIdleTimeout = Duration(seconds: 30);
  static const Duration _readerFileTotalTimeout = Duration(minutes: 5);
  static const Duration _partialIndexCleanupTimeout = Duration(seconds: 10);
  static const Duration _partialIndexCleanupSettleTimeout = Duration(
    seconds: 12,
  );

  Future<KnowledgeSource> importFile({
    required String filePath,
    required KnowledgeBaseSettings settings,
    required AiModelConfig embeddingModel,
    List<AiModelConfig> readerModels = const <AiModelConfig>[],
    List<String> tags = const <String>[],
    KnowledgeIndexingCancelToken? cancelToken,
    KnowledgeIndexingProgressCallback? onProgress,
  }) async {
    void report(KnowledgeIndexingProgress progress) {
      onProgress?.call(progress);
    }

    final file = File(filePath);
    final normalizedTags = _normalizeKnowledgeTags(tags);
    final initialTitle = p.basename(file.path);
    report(KnowledgeIndexingProgress(sourceTitle: initialTitle));
    cancelToken?.throwIfCancelled();
    if (!await regularFileExistsBounded(
      file,
      timeout: _readerFileIdleTimeout,
    )) {
      throw FileSystemException('文件不存在', filePath);
    }
    final stat = await file.stat().timeout(_readerFileIdleTimeout);
    if (!isRegularFileStat(stat)) {
      throw FileSystemException('路径不是普通文件。', filePath);
    }
    cancelToken?.throwIfCancelled();
    final maxFileSizeMb = KnowledgeBaseSettingRanges.maxFileSizeMb.normalize(
      settings.maxFileSizeMb,
    );
    final maxBytes = maxFileSizeMb * kBytesPerMiB;
    if (stat.size > maxBytes) {
      throw StateError('文件超过知识库最大单文件大小 ${maxFileSizeMb}MB。');
    }
    report(
      KnowledgeIndexingProgress(
        phase: KnowledgeIndexingPhase.parsing,
        sourceTitle: initialTitle,
      ),
    );
    final parseRequest = KnowledgeDocumentParseRequest(
      file: file,
      settings: settings,
      stat: stat,
      tags: normalizedTags,
    );
    final parsed = await _parseWithReaderIfConfigured(
      request: parseRequest,
      readerModels: readerModels,
      cancelToken: cancelToken,
      maxBytes: maxBytes,
    );
    cancelToken?.throwIfCancelled();
    final now = DateTime.now().toUtc();
    final sourceId = _uuid.v4();
    final title = _titleOrFallback(parsed.title, initialTitle);
    report(
      KnowledgeIndexingProgress(
        phase: KnowledgeIndexingPhase.storing,
        sourceTitle: title,
      ),
    );
    final storedPath = settings.copyImportedFiles
        ? await _copyToKnowledgeStorage(file, sourceId, maxBytes: maxBytes)
        : file.path;
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
        'tags': normalizedTags,
        'copied_to_openhand_storage': settings.copyImportedFiles,
        'parser_id': parsed.parserId,
        'parsed_text_char_count': parsed.text.length,
        'parsed_text_hash': stableFnv1a32Hex(parsed.text),
        ...parsed.metadata,
      },
    );
    try {
      await _store.upsertSource(source);
    } catch (error, stack) {
      try {
        await deleteManagedKnowledgeSourceFile(source);
      } catch (cleanupError, cleanupStack) {
        silentLog(
          'knowledge_ingestion_service',
          '初次写入失败后清理暂存知识源',
          cleanupError,
          cleanupStack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
    try {
      cancelToken?.throwIfCancelled();
      report(
        KnowledgeIndexingProgress(
          phase: KnowledgeIndexingPhase.chunking,
          sourceTitle: source.title,
        ),
      );
      final chunks = _chunker.chunk(
        source: source,
        text: parsed.text,
        settings: settings,
        tags: normalizedTags,
      );
      if (chunks.isEmpty) {
        throw StateError('文档解析后没有可索引内容。');
      }
      cancelToken?.throwIfCancelled();
      await _store.replaceChunks(sourceId: source.id, chunks: chunks);
      report(
        KnowledgeIndexingProgress(
          phase: KnowledgeIndexingPhase.ensuringCollection,
          sourceTitle: source.title,
          totalChunks: chunks.length,
        ),
      );
      await _vectorStore.ensureCollection(
        collectionName: settings.effectiveCollectionName,
        dimensions: settings.dimensions,
        distance: settings.distanceMetric,
        cancelSignal: cancelToken?.whenCancelled,
      );
      final batchSize = KnowledgeBaseSettingRanges.batchSize.normalize(
        settings.batchSize,
      );
      for (var start = 0; start < chunks.length; start += batchSize) {
        cancelToken?.throwIfCancelled();
        final end = (start + batchSize).clamp(0, chunks.length);
        final batch = chunks.sublist(start, end);
        report(
          KnowledgeIndexingProgress(
            phase: KnowledgeIndexingPhase.embedding,
            sourceTitle: source.title,
            processedChunks: start,
            totalChunks: chunks.length,
            detail: '${start + 1}-$end/${chunks.length}',
          ),
        );
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
          cancelToken: cancelToken,
        );
        cancelToken?.throwIfCancelled();
        report(
          KnowledgeIndexingProgress(
            phase: KnowledgeIndexingPhase.upserting,
            sourceTitle: source.title,
            processedChunks: start,
            totalChunks: chunks.length,
            detail: '${start + 1}-$end/${chunks.length}',
          ),
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
          cancelSignal: cancelToken?.whenCancelled,
        );
        cancelToken?.throwIfCancelled();
        report(
          KnowledgeIndexingProgress(
            phase: KnowledgeIndexingPhase.embedding,
            sourceTitle: source.title,
            processedChunks: end,
            totalChunks: chunks.length,
            detail: '$end/${chunks.length}',
          ),
        );
      }
      report(
        KnowledgeIndexingProgress(
          phase: KnowledgeIndexingPhase.finalizing,
          sourceTitle: source.title,
          processedChunks: chunks.length,
          totalChunks: chunks.length,
        ),
      );
      source = source.copyWith(
        status: 'indexed',
        indexedAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _store.upsertSource(source);
      report(
        KnowledgeIndexingProgress(
          phase: KnowledgeIndexingPhase.completed,
          sourceTitle: source.title,
          processedChunks: chunks.length,
          totalChunks: chunks.length,
        ),
      );
      return source;
    } on KnowledgeIndexingCancelledException {
      report(
        KnowledgeIndexingProgress(
          phase: KnowledgeIndexingPhase.cancelling,
          sourceTitle: source.title,
        ),
      );
      await _discardPartialIndex(
        sourceId: source.id,
        collectionName: settings.effectiveCollectionName,
      );
      source = source.copyWith(
        status: 'cancelled',
        errorMessage: '',
        updatedAt: DateTime.now().toUtc(),
      );
      await _store.upsertSource(source);
      report(
        KnowledgeIndexingProgress(
          phase: KnowledgeIndexingPhase.cancelled,
          sourceTitle: source.title,
        ),
      );
      rethrow;
    } catch (error, stack) {
      await _discardPartialIndex(
        sourceId: source.id,
        collectionName: settings.effectiveCollectionName,
      );
      source = source.copyWith(
        status: 'failed',
        errorMessage: knowledgeBaseFailureMessage(
          error,
          fallback: '知识源索引失败，请检查模型与向量服务配置。',
        ),
        updatedAt: DateTime.now().toUtc(),
      );
      try {
        await _store.upsertSource(source);
      } catch (persistError, persistStack) {
        silentLog(
          'knowledge_ingestion_service',
          '保存知识源失败状态',
          persistError,
          persistStack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _discardPartialIndex({
    required String sourceId,
    required String collectionName,
  }) async {
    final remoteCleanupDeadline = Completer<void>();
    final remoteCleanupTimer = startSafeTimer(
      _partialIndexCleanupTimeout,
      remoteCleanupDeadline.complete,
    );
    final remoteCleanup = () async {
      try {
        await _vectorStore
            .deleteBySource(
              collectionName: collectionName,
              sourceId: sourceId,
              cancelSignal: remoteCleanupDeadline.future,
            )
            .timeout(_partialIndexCleanupSettleTimeout);
      } catch (_) {
        // 保留原始导入异常。
      } finally {
        remoteCleanupTimer.cancel();
      }
    }();
    final localCleanup = () async {
      try {
        await _store
            .replaceChunks(sourceId: sourceId, chunks: const [])
            .timeout(_partialIndexCleanupTimeout);
      } catch (_) {
        // 保留原始导入异常。
      }
    }();
    await Future.wait<void>(<Future<void>>[remoteCleanup, localCleanup]);
  }

  Future<String> _copyToKnowledgeStorage(
    File file,
    String sourceId, {
    required int maxBytes,
  }) async {
    final root = Directory(knowledgeManagedSourcesDirectoryPath);
    final ext = p.extension(file.path);
    final target = File(p.join(root.path, '$sourceId$ext'));
    await copyFileAtomically(file, target, maxBytes: maxBytes);
    return target.path;
  }

  Future<KnowledgeDocumentParseResult> _parseWithReaderIfConfigured({
    required KnowledgeDocumentParseRequest request,
    required List<AiModelConfig> readerModels,
    required KnowledgeIndexingCancelToken? cancelToken,
    required int maxBytes,
  }) async {
    final sourceType = ReaderFileType.normalize(p.extension(request.file.path));
    final rule = request.settings.readerRuleForSourceType(sourceType);
    if (!rule.usesModel) {
      return _parserRegistry.parse(request);
    }
    final readerModel = _resolveReaderModel(
      readerModels: readerModels,
      rule: rule,
      sourceType: sourceType,
    );
    if (readerModel == null) {
      return _fallbackLocalParse(
        request,
        reason: 'reader_model_unavailable',
        failClosed:
            request.settings.failureStrategy ==
            KnowledgeFailureStrategy.failClosed,
      );
    }
    try {
      cancelToken?.throwIfCancelled();
      final localParsed = ReaderFileType.isTextLikeSource(sourceType)
          ? null
          : await _parserRegistry.parse(request);
      final sourceText =
          localParsed?.text ??
          await _readTextFile(request.file, maxBytes: maxBytes);
      final sourceTitle = _titleOrFallback(
        localParsed?.title,
        p.basename(request.file.path),
      );
      final conversion = await _readerConversionService.convert(
        KnowledgeReaderConversionRequest(
          model: readerModel,
          sourceType: sourceType,
          targetType: rule.targetType,
          content: sourceText,
          sourceTitle: sourceTitle,
          cancelSignal: cancelToken?.whenCancelled,
        ),
      );
      cancelToken?.throwIfCancelled();
      final targetType = ReaderFileType.normalize(rule.targetType);
      return KnowledgeDocumentParseResult(
        text: conversion.text,
        kind: targetType,
        mimeType: ReaderFileType.mimeType(targetType),
        parserId: 'model_reader_conversion',
        title: sourceTitle,
        metadata: <String, Object?>{
          if (localParsed != null) ...localParsed.metadata,
          'reader_parse_mode': KnowledgeReaderParserMode.model,
          'reader_input_source_type': sourceType,
          if (localParsed != null)
            'reader_local_extraction_parser_id': localParsed.parserId,
          ...conversion.metadata,
        },
      );
    } on KnowledgeIndexingCancelledException {
      rethrow;
    } catch (error, stack) {
      silentLog('knowledge_ingestion_service', '模型解析知识源', error, stack);
      return _fallbackLocalParse(
        request,
        reason: 'reader_conversion_failed',
        error: knowledgeBaseFailureMessage(error, fallback: '模型文档解析失败。'),
        failClosed:
            request.settings.failureStrategy ==
            KnowledgeFailureStrategy.failClosed,
      );
    }
  }

  AiModelConfig? _resolveReaderModel({
    required List<AiModelConfig> readerModels,
    required KnowledgeReaderParserRule rule,
    required String sourceType,
  }) {
    final providerConfigId = rule.providerConfigId.trim();
    final modelId = rule.modelId.trim();
    if (providerConfigId.isEmpty || modelId.isEmpty) return null;
    for (final config in readerModels) {
      if (config.id != providerConfigId ||
          !config.allModelIds.contains(modelId)) {
        continue;
      }
      final profile = config.profileFor(modelId);
      if (!profile.supportsReaderConversionFor(
        sourceType: sourceType,
        targetType: rule.targetType,
      )) {
        return null;
      }
      return config.copyWith(modelId: modelId);
    }
    return null;
  }

  Future<KnowledgeDocumentParseResult> _fallbackLocalParse(
    KnowledgeDocumentParseRequest request, {
    required String reason,
    String? error,
    required bool failClosed,
  }) async {
    if (failClosed) {
      throw StateError(error == null ? reason : '$reason: $error');
    }
    final parsed = await _parserRegistry.parse(request);
    return KnowledgeDocumentParseResult(
      text: parsed.text,
      kind: parsed.kind,
      mimeType: parsed.mimeType,
      parserId: parsed.parserId,
      title: parsed.title,
      metadata: <String, Object?>{
        ...parsed.metadata,
        'reader_parse_mode': KnowledgeReaderParserMode.model,
        'reader_fallback_reason': reason,
        if (error != null) 'reader_fallback_error': error,
      },
    );
  }

  Future<String> _readTextFile(File file, {required int maxBytes}) async {
    final bytes = await readBoundedFileBytes(
      file,
      maxBytes: maxBytes,
      idleTimeout: _readerFileIdleTimeout,
      totalTimeout: _readerFileTotalTimeout,
    );
    return String.fromCharCodes(bytes).trim().isEmpty
        ? ''
        : const Utf8Decoder(allowMalformed: true).convert(bytes);
  }

  void dispose() {
    if (_ownsReaderConversionService) {
      _readerConversionService.dispose();
    }
  }
}

String _titleOrFallback(String? title, String fallback) {
  return nullIfBlank(title) ?? fallback;
}

List<String> _normalizeKnowledgeTags(List<String> tags) {
  final normalized = <String>[];
  final seen = <String>{};
  for (final rawTag in tags) {
    final tag = rawTag.trim();
    if (tag.isEmpty || !seen.add(tag.toLowerCase())) continue;
    if (tag.length > kKnowledgeTagMaxCharacters) {
      throw StateError('知识标签不能超过 $kKnowledgeTagMaxCharacters 个字符。');
    }
    if (normalized.length >= kKnowledgeTagMaxCount) {
      throw StateError('知识笔记标签不能超过 $kKnowledgeTagMaxCount 个。');
    }
    normalized.add(tag);
  }
  return List<String>.unmodifiable(normalized);
}

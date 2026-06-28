import 'dart:convert';

import '../../../shared/util/input_value_parsing.dart';
import 'knowledge_model_codec.dart';

class KnowledgeChunk {
  const KnowledgeChunk({
    required this.id,
    required this.sourceId,
    required this.chunkIndex,
    this.parentChunkId,
    required this.title,
    required this.headingPath,
    required this.content,
    required this.contentHash,
    required this.charCount,
    required this.tokenEstimate,
    this.startOffset,
    this.endOffset,
    this.pageNumber,
    this.documentTime,
    required this.createdAt,
    required this.updatedAt,
    this.metadata = const <String, Object?>{},
    this.tags = const <String>[],
  });

  final String id;
  final String sourceId;
  final int chunkIndex;
  final String? parentChunkId;
  final String title;
  final String headingPath;
  final String content;
  final String contentHash;
  final int charCount;
  final int tokenEstimate;
  final int? startOffset;
  final int? endOffset;
  final int? pageNumber;
  final DateTime? documentTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, Object?> metadata;
  final List<String> tags;

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': id,
      'source_id': sourceId,
      'chunk_index': chunkIndex,
      'parent_chunk_id': parentChunkId,
      'title': title,
      'heading_path': headingPath,
      'content': content,
      'content_hash': contentHash,
      'char_count': charCount,
      'token_estimate': tokenEstimate,
      'start_offset': startOffset,
      'end_offset': endOffset,
      'page_number': pageNumber,
      'document_time': documentTime?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'metadata_json': jsonEncode(metadata),
    };
  }

  Map<String, Object?> toPayload({
    required String sourceTitle,
    required String sourceKind,
    required String path,
  }) {
    return <String, Object?>{
      'chunk_id': id,
      'source_id': sourceId,
      'source_title': sourceTitle,
      'source_kind': sourceKind,
      'tags': tags,
      'document_time': documentTime?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'imported_at': metadata['imported_at'],
      'path': path,
      'heading_path': headingPath,
      'chunk_index': chunkIndex,
    };
  }

  String embeddingInput({required String sourceTitle, required String path}) {
    return [
      'Title: $sourceTitle',
      'Source: $path',
      'Tags: ${tags.join(", ")}',
      'Document Time: ${documentTime?.toUtc().toIso8601String() ?? ""}',
      'Heading: $headingPath',
      '',
      content,
    ].join('\n');
  }

  static KnowledgeChunk fromRow(
    Map<String, Object?> row, {
    List<String> tags = const <String>[],
  }) {
    return KnowledgeChunk(
      id: '${row['id'] ?? ''}',
      sourceId: '${row['source_id'] ?? ''}',
      chunkIndex: nonNegativeIntFromValue(row['chunk_index'], fallback: 0),
      parentChunkId: knowledgeNullableString(row['parent_chunk_id']),
      title: '${row['title'] ?? ''}',
      headingPath: '${row['heading_path'] ?? ''}',
      content: '${row['content'] ?? ''}',
      contentHash: '${row['content_hash'] ?? ''}',
      charCount: nonNegativeIntFromValue(row['char_count'], fallback: 0),
      tokenEstimate: nonNegativeIntFromValue(
        row['token_estimate'],
        fallback: 0,
      ),
      startOffset: optionalNonNegativeIntFromValue(row['start_offset']),
      endOffset: optionalNonNegativeIntFromValue(row['end_offset']),
      pageNumber: optionalNonNegativeIntFromValue(row['page_number']),
      documentTime: knowledgeDate(row['document_time']),
      createdAt: knowledgeDate(row['created_at']) ?? DateTime.now().toUtc(),
      updatedAt: knowledgeDate(row['updated_at']) ?? DateTime.now().toUtc(),
      metadata: knowledgeJsonMap(row['metadata_json']),
      tags: tags,
    );
  }
}

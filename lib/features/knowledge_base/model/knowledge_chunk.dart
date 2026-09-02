import '../../../shared/util/byte_size_format.dart';
import 'knowledge_model_codec.dart';
import 'knowledge_source.dart';

const int kKnowledgeMaxChunkCountPerSource = 10000;
const int kKnowledgeMaxChunkCount = 100000;
const int kKnowledgeMaxChunkLookupIds = 10000;
const int kKnowledgeMaxChunkIdCharacters = 768;
const int kKnowledgeMaxChunkPayloadBytes = 16 * kBytesPerMiB;
const int kKnowledgeMaxTotalChunkPayloadBytes = 320 * kBytesPerMiB;

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

  KnowledgeChunk copyWith({List<String>? tags}) {
    return KnowledgeChunk(
      id: id,
      sourceId: sourceId,
      chunkIndex: chunkIndex,
      parentChunkId: parentChunkId,
      title: title,
      headingPath: headingPath,
      content: content,
      contentHash: contentHash,
      charCount: charCount,
      tokenEstimate: tokenEstimate,
      startOffset: startOffset,
      endOffset: endOffset,
      pageNumber: pageNumber,
      documentTime: documentTime,
      createdAt: createdAt,
      updatedAt: updatedAt,
      metadata: metadata,
      tags: tags ?? this.tags,
    );
  }

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
      'metadata_json': knowledgeEncodeJsonMap(<String, Object?>{
        ...metadata,
        if (tags.isNotEmpty) 'tags': List<String>.from(tags),
      }, field: '知识分块 metadata_json'),
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
    final id = knowledgeText(
      row,
      'id',
      allowEmpty: false,
      maxCharacters: kKnowledgeMaxChunkIdCharacters,
    );
    final sourceId = knowledgeText(
      row,
      'source_id',
      allowEmpty: false,
      maxCharacters: 512,
    );
    final content = knowledgeText(
      row,
      'content',
      allowEmpty: false,
      maxCharacters: 4 * kBytesPerMiB,
    );
    final charCount = knowledgeNonNegativeInt(row, 'char_count');
    final metadata = knowledgeJsonMap(
      row['metadata_json'],
      field: '知识分块 metadata_json',
    );
    final storedTags = metadata['tags'];
    if (storedTags != null &&
        (storedTags is! List || storedTags.any((item) => item is! String))) {
      throw FormatException('知识分块标签无效：$id');
    }
    final effectiveTags = tags.isNotEmpty
        ? tags
        : storedTags == null
        ? const <String>[]
        : List<String>.unmodifiable((storedTags as List).cast<String>());
    if (id.trim() != id ||
        sourceId.trim() != sourceId ||
        charCount != content.length ||
        effectiveTags.length > kKnowledgeTagMaxCount ||
        effectiveTags.any(
          (tag) =>
              tag.isEmpty ||
              tag.trim() != tag ||
              tag.length > kKnowledgeTagMaxCharacters,
        ) ||
        effectiveTags.map((tag) => tag.toLowerCase()).toSet().length !=
            effectiveTags.length) {
      throw FormatException('知识分块字段格式无效：$id');
    }
    final startOffset = knowledgeOptionalNonNegativeInt(row, 'start_offset');
    final endOffset = knowledgeOptionalNonNegativeInt(row, 'end_offset');
    if (startOffset != null && endOffset != null && endOffset < startOffset) {
      throw FormatException('知识分块偏移范围无效：$id');
    }
    return KnowledgeChunk(
      id: id,
      sourceId: sourceId,
      chunkIndex: knowledgeNonNegativeInt(row, 'chunk_index'),
      parentChunkId: knowledgeNullableString(
        row['parent_chunk_id'],
        field: '知识分块 parent_chunk_id',
        maxCharacters: kKnowledgeMaxChunkIdCharacters,
      ),
      title: knowledgeText(row, 'title', maxCharacters: 32 * kBytesPerKiB),
      headingPath: knowledgeText(
        row,
        'heading_path',
        maxCharacters: 64 * kBytesPerKiB,
      ),
      content: content,
      contentHash: knowledgeText(
        row,
        'content_hash',
        allowEmpty: false,
        maxCharacters: 128,
      ),
      charCount: charCount,
      tokenEstimate: knowledgeNonNegativeInt(row, 'token_estimate'),
      startOffset: startOffset,
      endOffset: endOffset,
      pageNumber: knowledgeOptionalNonNegativeInt(row, 'page_number'),
      documentTime: knowledgeDate(
        row['document_time'],
        field: '知识分块 document_time',
      ),
      createdAt: knowledgeDate(
        row['created_at'],
        field: '知识分块 created_at',
        nullable: false,
      )!,
      updatedAt: knowledgeDate(
        row['updated_at'],
        field: '知识分块 updated_at',
        nullable: false,
      )!,
      metadata: metadata,
      tags: effectiveTags,
    );
  }
}

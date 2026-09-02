import '../../../shared/util/byte_size_format.dart';
import 'knowledge_model_codec.dart';

const int kKnowledgeMaxSourceCount = 10000;
const int kKnowledgeMaxSourceQueryCharacters = 1024;
const int kKnowledgeMaxSourceIdCharacters = 512;
const int kKnowledgeMaxSourceFieldCharacters = 32 * kBytesPerKiB;
const int kKnowledgeMaxSourcePayloadBytes = 2 * kBytesPerMiB;
const int kKnowledgeMaxTotalSourcePayloadBytes = 256 * kBytesPerMiB;
const int kKnowledgeTagMaxCount = 64;
const int kKnowledgeTagMaxCharacters = 128;
const Set<String> _knowledgeSourceStatuses = <String>{
  'pending',
  'indexing',
  'indexed',
  'cancelled',
  'failed',
};

class KnowledgeSource {
  const KnowledgeSource({
    required this.id,
    required this.title,
    required this.kind,
    required this.originalPath,
    required this.storedPath,
    required this.mimeType,
    required this.sizeBytes,
    required this.contentHash,
    required this.status,
    required this.errorMessage,
    this.documentTime,
    required this.importedAt,
    this.indexedAt,
    required this.createdAt,
    required this.updatedAt,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String title;
  final String kind;
  final String originalPath;
  final String storedPath;
  final String mimeType;
  final int sizeBytes;
  final String contentHash;
  final String status;
  final String errorMessage;
  final DateTime? documentTime;
  final DateTime importedAt;
  final DateTime? indexedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, Object?> metadata;

  KnowledgeSource copyWith({
    String? title,
    String? kind,
    String? storedPath,
    String? status,
    String? errorMessage,
    DateTime? documentTime,
    DateTime? indexedAt,
    DateTime? updatedAt,
    Map<String, Object?>? metadata,
  }) {
    return KnowledgeSource(
      id: id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      originalPath: originalPath,
      storedPath: storedPath ?? this.storedPath,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      contentHash: contentHash,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      documentTime: documentTime ?? this.documentTime,
      importedAt: importedAt,
      indexedAt: indexedAt ?? this.indexedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'kind': kind,
      'original_path': originalPath,
      'stored_path': storedPath,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'content_hash': contentHash,
      'status': status,
      'error_message': errorMessage,
      'document_time': documentTime?.toUtc().toIso8601String(),
      'imported_at': importedAt.toUtc().toIso8601String(),
      'indexed_at': indexedAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'metadata_json': knowledgeEncodeJsonMap(
        metadata,
        field: '知识源 metadata_json',
      ),
    };
  }

  static KnowledgeSource fromRow(Map<String, Object?> row) {
    final id = knowledgeText(
      row,
      'id',
      allowEmpty: false,
      maxCharacters: kKnowledgeMaxSourceIdCharacters,
    );
    final title = knowledgeText(
      row,
      'title',
      allowEmpty: false,
      maxCharacters: kKnowledgeMaxSourceFieldCharacters,
    );
    final kind = knowledgeText(
      row,
      'kind',
      allowEmpty: false,
      maxCharacters: 64,
    );
    final status = knowledgeText(
      row,
      'status',
      allowEmpty: false,
      maxCharacters: 32,
    );
    if (id.trim() != id ||
        title.trim() != title ||
        kind.trim() != kind ||
        status.trim() != status ||
        !_knowledgeSourceStatuses.contains(status)) {
      throw FormatException('知识源字段格式无效：$id');
    }
    final metadata = knowledgeJsonMap(
      row['metadata_json'],
      field: '知识源 metadata_json',
    );
    final tags = metadata['tags'];
    if (tags != null &&
        (tags is! List ||
            tags.length > kKnowledgeTagMaxCount ||
            tags.any(
              (tag) =>
                  tag is! String ||
                  tag.isEmpty ||
                  tag.trim() != tag ||
                  tag.length > kKnowledgeTagMaxCharacters,
            ))) {
      throw FormatException('知识源标签无效：$id');
    }
    if (tags is List &&
        tags.cast<String>().map((tag) => tag.toLowerCase()).toSet().length !=
            tags.length) {
      throw FormatException('知识源标签重复：$id');
    }
    return KnowledgeSource(
      id: id,
      title: title,
      kind: kind,
      originalPath: knowledgeText(
        row,
        'original_path',
        maxCharacters: kKnowledgeMaxSourceFieldCharacters,
      ),
      storedPath: knowledgeText(
        row,
        'stored_path',
        maxCharacters: kKnowledgeMaxSourceFieldCharacters,
      ),
      mimeType: knowledgeText(row, 'mime_type', maxCharacters: 256),
      sizeBytes: knowledgeNonNegativeInt(row, 'size_bytes'),
      contentHash: knowledgeText(
        row,
        'content_hash',
        allowEmpty: false,
        maxCharacters: 128,
      ),
      status: status,
      errorMessage: knowledgeText(
        row,
        'error_message',
        maxCharacters: kKnowledgeMaxSourceFieldCharacters,
      ),
      documentTime: knowledgeDate(
        row['document_time'],
        field: '知识源 document_time',
      ),
      importedAt: knowledgeDate(
        row['imported_at'],
        field: '知识源 imported_at',
        nullable: false,
      )!,
      indexedAt: knowledgeDate(row['indexed_at'], field: '知识源 indexed_at'),
      createdAt: knowledgeDate(
        row['created_at'],
        field: '知识源 created_at',
        nullable: false,
      )!,
      updatedAt: knowledgeDate(
        row['updated_at'],
        field: '知识源 updated_at',
        nullable: false,
      )!,
      metadata: metadata,
    );
  }
}

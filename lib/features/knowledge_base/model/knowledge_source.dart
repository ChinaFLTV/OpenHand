import 'dart:convert';

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
      'metadata_json': jsonEncode(metadata),
    };
  }

  static KnowledgeSource fromRow(Map<String, Object?> row) {
    return KnowledgeSource(
      id: '${row['id'] ?? ''}',
      title: '${row['title'] ?? ''}',
      kind: '${row['kind'] ?? 'note'}',
      originalPath: '${row['original_path'] ?? ''}',
      storedPath: '${row['stored_path'] ?? ''}',
      mimeType: '${row['mime_type'] ?? ''}',
      sizeBytes: (row['size_bytes'] as num?)?.toInt() ?? 0,
      contentHash: '${row['content_hash'] ?? ''}',
      status: '${row['status'] ?? 'pending'}',
      errorMessage: '${row['error_message'] ?? ''}',
      documentTime: _date(row['document_time']),
      importedAt: _date(row['imported_at']) ?? DateTime.now().toUtc(),
      indexedAt: _date(row['indexed_at']),
      createdAt: _date(row['created_at']) ?? DateTime.now().toUtc(),
      updatedAt: _date(row['updated_at']) ?? DateTime.now().toUtc(),
      metadata: _jsonMap(row['metadata_json']),
    );
  }

  static DateTime? _date(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text == 'null') return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  static Map<String, Object?> _jsonMap(Object? value) {
    if (value is! String || value.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
    return const {};
  }
}

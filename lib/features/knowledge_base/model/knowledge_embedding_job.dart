class KnowledgeEmbeddingJob {
  const KnowledgeEmbeddingJob({
    required this.id,
    required this.chunkId,
    required this.providerConfigId,
    required this.modelId,
    required this.dimensions,
    required this.status,
    required this.retryCount,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String chunkId;
  final String providerConfigId;
  final String modelId;
  final int dimensions;
  final String status;
  final int retryCount;
  final String errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': id,
      'chunk_id': chunkId,
      'provider_config_id': providerConfigId,
      'model_id': modelId,
      'dimensions': dimensions,
      'status': status,
      'retry_count': retryCount,
      'error_message': errorMessage,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}
